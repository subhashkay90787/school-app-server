-- Read-only answers for voice assistants (/api/v1/assistant, MCP). Children are the caller's own; classes are
-- the caller's own sections; everything is short.

-- name: getAssistantContext
SELECT jsonb_build_object('userId', u.user_id, 'role', u.user_category,
    'categories', CASE u.user_category WHEN 'PARENT' THEN '["attendance","homework","timetable","results","fees","hostel","notices"]'::jsonb
                                       ELSE '["timetable","attendance","notices","overview"]'::jsonb END,
    'children', coalesce((SELECT jsonb_agg(api.child_summary(c) ORDER BY c) FROM api.my_children() c), '[]'::jsonb),
    'pinRequiredFor', '["fees","results"]'::jsonb)
FROM directory.app_user u WHERE u.user_id = :me::bigint;

-- name: listNotices
SELECT coalesce(jsonb_agg(jsonb_build_object('notificationId', n.notification_id, 'title', n.title, 'body', n.body, 'sentAt', n.sent_time)
       ORDER BY n.sent_time DESC), '[]'::jsonb)
FROM (SELECT n.* FROM communication.notification_recipient r JOIN communication.notification n ON n.notification_id = r.notification_id
       WHERE r.recipient_user_id = :me::bigint AND n.sent_time > now() - interval '7 days' ORDER BY n.sent_time DESC LIMIT 10) n;

-- name: getChildAttendanceToday
SELECT jsonb_strip_nulls(jsonb_build_object('studentId', c, 'date', current_date, 'status', coalesce(api.attendance_today(c), 'NOT_TAKEN'),
    'arrivedAt', (SELECT dp.first_in_at FROM operations.daily_presence dp WHERE dp.person_kind = 'STUDENT' AND dp.person_id = c AND dp.presence_date = current_date),
    'periodsAbsent', (SELECT jsonb_agg(p.period_time ORDER BY p.period_id) FROM operations.student_absence a
                        JOIN academics.class_section_period csp ON csp.class_section_period_id = a.class_section_period_id
                        JOIN academics.period p ON p.period_id = csp.period_id WHERE a.student_id = c AND a.date = current_date)))
FROM api.my_children() c WHERE c = :studentId::bigint;

-- name: getChildHomework
SELECT coalesce((SELECT jsonb_agg(h) FROM jsonb_array_elements(api.homework_views(c, current_date - 7)) h
                  WHERE (h ->> 'dueDate')::date >= current_date), '[]'::jsonb)
FROM api.my_children() c WHERE c = :studentId::bigint;

-- name: getChildTimetableToday
SELECT coalesce((SELECT jsonb_agg(jsonb_strip_nulls(jsonb_build_object('timetableId', (x ->> 'timetableId')::bigint, 'periodLabel', p.period_time,
                         'start', api.period_start(p.period_time), 'end', api.period_end(p.period_time), 'subject', x ->> 'subject',
                         'classSection', api.section_label(s.class_section_id), 'room', x ->> 'room')) ORDER BY api.period_start(p.period_time))
                   FROM jsonb_array_elements(api.timetable_grid(s.class_section_id) -> 'cells') x
                   JOIN academics.period p ON p.period_id = (x ->> 'periodId')::bigint
                  WHERE x ->> 'day' = api.dow(current_date)), '[]'::jsonb)
FROM academics.student s WHERE s.student_id = :studentId::bigint AND s.student_id IN (SELECT api.my_children());

-- name: getChildResults
SELECT coalesce((SELECT jsonb_agg(r) FROM (SELECT r FROM jsonb_array_elements(api.exam_results(c)) r LIMIT 5) x), '[]'::jsonb)
FROM api.my_children() c WHERE c = :studentId::bigint;

-- name: getChildFees
SELECT jsonb_strip_nulls(jsonb_build_object('studentId', c,
    'totalDue', (SELECT coalesce(sum(f.remaining_due), 0) FROM finance.fee f WHERE f.student_id = c AND f.status IN ('DUE', 'PART_PAID')),
    'nextDueDate', (SELECT min(f.due_date) FROM finance.fee f WHERE f.student_id = c AND f.status IN ('DUE', 'PART_PAID') AND f.due_date >= current_date),
    'overdue', api.overdue(c)))
FROM api.my_children() c WHERE c = :studentId::bigint;

-- name: getChildHostelStatus
SELECT jsonb_strip_nulls(jsonb_build_object('studentId', c, 'status', api.hostel_status(c),
    'expectedBackAt', hc ->> 'expectedBackAt', 'lastRollCall', hc ->> 'lastRollCall'))
FROM (SELECT c, api.hostel_card(c) AS hc FROM api.my_children() c WHERE c = :studentId::bigint) x WHERE hc IS NOT NULL;

-- name: getMyTimetableToday
SELECT api.my_periods(current_date);

-- name: getClassAttendanceSummary
SELECT jsonb_build_object('classSectionId', cs.class_section_id, 'date', current_date,
    'present', (SELECT count(*) FROM operations.daily_presence dp JOIN academics.student s ON s.student_id = dp.person_id
                 WHERE dp.person_kind = 'STUDENT' AND dp.presence_date = current_date AND s.class_section_id = cs.class_section_id AND dp.status = 'PRESENT'),
    'absent', (SELECT count(*) FROM operations.daily_presence dp JOIN academics.student s ON s.student_id = dp.person_id
                WHERE dp.person_kind = 'STUDENT' AND dp.presence_date = current_date AND s.class_section_id = cs.class_section_id AND dp.status = 'ABSENT'),
    'late', (SELECT count(*) FROM operations.daily_presence dp JOIN academics.student s ON s.student_id = dp.person_id
              WHERE dp.person_kind = 'STUDENT' AND dp.presence_date = current_date AND s.class_section_id = cs.class_section_id AND dp.status = 'LATE'),
    'notTaken', NOT EXISTS (SELECT 1 FROM operations.daily_presence dp JOIN academics.student s ON s.student_id = dp.person_id
                             WHERE dp.person_kind = 'STUDENT' AND dp.presence_date = current_date AND s.class_section_id = cs.class_section_id))
FROM academics.class_section cs WHERE cs.class_section_id = :classSectionId::bigint AND cs.class_section_id IN (SELECT api.my_sections());

-- name: getSchoolOverview
SELECT jsonb_build_object('asOf', now(), 'scope', 'BRANCH', 'kpis', api.branch_kpis(:school::bigint), 'branches', '[]'::jsonb);
