-- Screen queries for /api/v1/principal (branch head).

-- name: getHome
SELECT api.feed('PRINCIPAL',
    (SELECT api.card('critical', 'CRITICAL', 'CRITICAL_ALERT', max(n.title), max(n.body), count(*), 'CRITICAL', 'alerts')
       FROM communication.notification_recipient r JOIN communication.notification n ON n.notification_id = r.notification_id
      WHERE r.recipient_user_id = :me::bigint AND n.severity = 'CRITICAL' AND r.acknowledged_at IS NULL AND n.sent_time > now() - interval '24 hours'),
    (SELECT api.card('missing', 'CRITICAL', 'OUTING_OVERDUE', 'Students not back', string_agg(api.student_ref(o.student_id) ->> 'name', ', '), count(*), 'CRITICAL', 'hostel')
       FROM hostel.outing_request o WHERE o.status = 'OVERDUE'),
    (SELECT api.card('approvals', 'NEEDS_YOU', 'APPROVALS', 'Approvals waiting', NULL, count(*), 'ACTION', 'approvals')
       FROM platform.flow_instance fi WHERE fi.status = 'OPEN' AND fi.current_step = 'PRINCIPAL' AND coalesce(fi.submitted_by_user_id, -1) <> :me::bigint),
    (SELECT api.card('uncovered', 'NEEDS_YOU', 'COVER_NEEDED', 'Periods without cover today', NULL, count(*), 'URGENT', 'cover-board')
       FROM operations.staff_absences a JOIN academics.timetable tt ON tt.day_of_week = api.dow(current_date)
       JOIN academics.staff_subject ss ON ss.staff_subject_id = tt.staff_subject_id AND ss.user_id = a.user_id
      WHERE a.date = current_date
        AND NOT EXISTS (SELECT 1 FROM operations.substitution s WHERE s.staff_absence_id = a.staff_absence_id AND s.class_section_period_id = tt.class_section_period_id)),
    (SELECT api.card('report-cards', 'NEEDS_YOU', 'REPORT_CARDS', 'Report cards to publish', NULL, count(*), 'ACTION', 'report-cards')
       FROM assessment.report_card rc WHERE rc.status = 'APPROVED'),
    (SELECT api.card('attendance', 'NOW', 'ATTENDANCE', 'Student attendance', coalesce(api.student_attendance_pct(:school::bigint, current_date)::text || '%', 'Not taken yet'),
                     NULL, 'INFO', 'pulse')),
    (SELECT api.card('staff-late', 'NOW', 'STAFF_LATE', 'Staff late or absent today', NULL, count(*), 'INFO', 'staff-presence')
       FROM operations.daily_presence dp WHERE dp.person_kind = 'STAFF' AND dp.presence_date = current_date AND dp.status IN ('LATE', 'ABSENT')),
    (SELECT api.card('sick-bay', 'TODAY', 'SICK_BAY', 'In sick bay', NULL, count(*), 'INFO', 'hostel')
       FROM wellbeing.infirmary_visit v WHERE v.disposition = 'SICK_BAY' AND v.discharged_at IS NULL),
    (SELECT api.card('incidents', 'TODAY', 'INCIDENTS', 'Open incidents', string_agg(DISTINCT i.category, ', '), count(*), 'ACTION', 'incidents')
       FROM discipline.incident i WHERE i.status IN ('REPORTED', 'UNDER_REVIEW')),
    (SELECT api.card('events', 'FEED', 'CALENDAR', e.title, to_char(e.start_date, 'Dy DD Mon'), NULL, 'INFO', 'calendar')
       FROM calendar.event e WHERE e.start_date BETWEEN current_date AND current_date + 7 ORDER BY e.start_date LIMIT 1));

-- name: getPulse
SELECT jsonb_build_object('asOf', now(), 'scope', 'BRANCH', 'kpis', api.branch_kpis(:school::bigint) || jsonb_build_array(
    api.kpi('OPEN_INCIDENTS', 'Open incidents', (SELECT count(*) FROM discipline.incident WHERE status IN ('REPORTED', 'UNDER_REVIEW'))),
    api.kpi('PENDING_APPROVALS', 'Waiting for you', (SELECT count(*) FROM platform.flow_instance WHERE status = 'OPEN' AND current_step = 'PRINCIPAL')),
    api.kpi('SYLLABUS', 'Syllabus delivered', (SELECT round(100.0 * count(*) FILTER (WHERE status IN ('DELIVERED', 'PARTIAL'))
                                                         / nullif(count(*) FILTER (WHERE planned_date <= current_date), 0), 1) FROM learning.lesson_plan), '%')),
    'branches', '[]'::jsonb);

-- name: getCoverBoard
-- Absent teachers on the date and their periods with no substitute, with free teachers suggested per period
WITH d AS (SELECT coalesce(:date::date, current_date) AS day),
     absent AS (SELECT a.* FROM operations.staff_absences a, d WHERE a.date = d.day),
     periods AS (SELECT a.staff_absence_id, a.user_id, tt.class_section_period_id, csp.class_section_id, p.period_id, p.period_time, sub.subject_name
                   FROM absent a, d
                   JOIN academics.timetable tt ON tt.day_of_week = api.dow(d.day)
                   JOIN academics.staff_subject ss ON ss.staff_subject_id = tt.staff_subject_id
                   JOIN academics.subject sub ON sub.subject_id = ss.subject_id
                   JOIN academics.class_section_period csp ON csp.class_section_period_id = tt.class_section_period_id
                   JOIN academics.period p ON p.period_id = csp.period_id
                  WHERE ss.user_id = a.user_id
                    AND NOT EXISTS (SELECT 1 FROM operations.substitution s WHERE s.staff_absence_id = a.staff_absence_id
                                      AND s.class_section_period_id = tt.class_section_period_id))
SELECT jsonb_build_object('date', (SELECT day FROM d),
    'absentTeachers', coalesce((SELECT jsonb_agg(api.person(a.user_id, a.absence_kind) ORDER BY a.user_id) FROM absent a), '[]'::jsonb),
    'uncovered', coalesce((SELECT jsonb_agg(jsonb_build_object('classSectionPeriodId', p.class_section_period_id, 'staffAbsenceId', p.staff_absence_id,
                     'period', p.period_time, 'classSection', api.section_label(p.class_section_id), 'subject', p.subject_name,
                     'suggestions', coalesce((SELECT jsonb_agg(api.person(t.user_id)) FROM (
                         SELECT DISTINCT ss2.user_id FROM academics.staff_subject ss2, d
                          WHERE ss2.user_id NOT IN (SELECT user_id FROM absent)
                            AND NOT EXISTS (SELECT 1 FROM academics.timetable t2 JOIN academics.class_section_period c2 ON c2.class_section_period_id = t2.class_section_period_id
                                             JOIN academics.staff_subject s2 ON s2.staff_subject_id = t2.staff_subject_id
                                            WHERE s2.user_id = ss2.user_id AND t2.day_of_week = api.dow(d.day) AND c2.period_id = p.period_id)
                            AND NOT EXISTS (SELECT 1 FROM operations.substitution s3 JOIN operations.staff_absences a3 ON a3.staff_absence_id = s3.staff_absence_id
                                             JOIN academics.class_section_period c3 ON c3.class_section_period_id = s3.class_section_period_id
                                            WHERE s3.substitute_user_id = ss2.user_id AND a3.date = d.day AND c3.period_id = p.period_id)
                          LIMIT 3) t), '[]'::jsonb))
                   ORDER BY api.period_start(p.period_time), p.class_section_id) FROM periods p), '[]'::jsonb));

-- name: listStaffPresence
WITH d AS (SELECT coalesce(:date::date, current_date) AS day)
SELECT api.page(coalesce(jsonb_agg(v ORDER BY v ->> 'name'), '[]'::jsonb), :page, :size) FROM (
    SELECT jsonb_strip_nulls(jsonb_build_object('userId', e.user_id, 'name', api.user_name(e.user_id),
           'department', dep.name, 'shift', sh.code, 'status', coalesce(dp.status, 'ABSENT'), 'firstInAt', dp.first_in_at,
           'lateMinutes', dp.late_minutes, 'onLeave', coalesce(dp.status = 'ON_LEAVE', false)
                                                      OR EXISTS (SELECT 1 FROM hr.leave_request lr WHERE lr.user_id = e.user_id AND lr.status = 'APPROVED'
                                                                   AND d.day BETWEEN lr.from_date AND lr.to_date),
           'locked', dp.computed_by = 'SYSTEM' AND dp.recomputed_at IS NOT NULL)) AS v
      FROM hr.employee_profile e CROSS JOIN d
      LEFT JOIN academics.department dep ON dep.department_id = e.department_id
      LEFT JOIN operations.daily_presence dp ON dp.person_kind = 'STAFF' AND dp.person_id = e.user_id AND dp.presence_date = d.day
      LEFT JOIN hr.shift sh ON sh.shift_id = dp.shift_id
     WHERE e.status = 'ACTIVE' AND (:department IS NULL OR dep.name = :department OR dep.department_code = :department)
       AND (:status IS NULL OR coalesce(dp.status, 'ABSENT') = :status)
) x;

-- name: correctStaffPresence write
-- Manual correction by someone other than the person (a DB rule); the reason goes to the audit log via request id
WITH b AS (SELECT :body::jsonb AS j),
     up AS (UPDATE operations.daily_presence dp SET status = b.j ->> 'status', computed_by = 'MANUAL', corrected_by_user_id = :me::bigint, recomputed_at = now()
              FROM b WHERE dp.presence_id = :presenceId::bigint AND dp.person_kind = 'STAFF' AND coalesce(b.j ->> 'reason', '') <> ''
            RETURNING dp.*)
SELECT api.camel(to_jsonb(up)) FROM up;

-- name: getHeatmap
-- Average % per section (rows) and subject (columns) for the term's locked / published exams
WITH t AS (SELECT coalesce(:termId::bigint, (SELECT term_id FROM academics.academic_term WHERE start_date <= current_date ORDER BY start_date DESC LIMIT 1)) AS term_id),
     m AS (SELECT cs.section_name AS r, sub.subject_name AS c, 100.0 * m.mark_obtained / e.max_marks AS pct
             FROM assessment.marks m JOIN assessment.exams e ON e.exam_id = m.exam_id
             JOIN academics.class_section cs ON cs.class_section_id = e.class_section_id
             JOIN academics.staff_subject ss ON ss.staff_subject_id = e.staff_subject_id
             JOIN academics.subject sub ON sub.subject_id = ss.subject_id, t
            WHERE e.term_id = t.term_id AND e.status IN ('LOCKED', 'PUBLISHED', 'MARKS_ENTRY') AND e.max_marks > 0 AND NOT coalesce(m.is_absent, false)),
     rs AS (SELECT DISTINCT r FROM m), cs AS (SELECT DISTINCT c FROM m)
SELECT jsonb_build_object('termId', (SELECT term_id FROM t),
    'rows', coalesce((SELECT jsonb_agg(r ORDER BY r) FROM rs), '[]'::jsonb),
    'columns', coalesce((SELECT jsonb_agg(c ORDER BY c) FROM cs), '[]'::jsonb),
    'values', coalesce((SELECT jsonb_agg((SELECT jsonb_agg((SELECT round(avg(pct)::numeric, 1) FROM m WHERE m.r = rs.r AND m.c = cs.c) ORDER BY cs.c) FROM cs) ORDER BY rs.r) FROM rs), '[]'::jsonb));

-- name: getMarksDistribution
WITH e AS (SELECT * FROM assessment.exams WHERE exam_id = :examId::bigint),
     p AS (SELECT 100.0 * m.mark_obtained / e.max_marks AS pct FROM assessment.marks m, e
            WHERE m.exam_id = e.exam_id AND NOT coalesce(m.is_absent, false) AND m.mark_obtained IS NOT NULL AND e.max_marks > 0)
SELECT jsonb_build_object('examId', e.exam_id,
    'buckets', (SELECT jsonb_agg(jsonb_build_object('label', lbl, 'count', (SELECT count(*) FROM p WHERE pct >= lo AND pct < hi)) ORDER BY lo)
                  FROM (VALUES ('0-32', 0, 33), ('33-59', 33, 60), ('60-74', 60, 75), ('75-89', 75, 90), ('90-100', 90, 100.01)) b(lbl, lo, hi)),
    'average', (SELECT round(avg(pct)::numeric, 1) FROM p),
    'median', (SELECT round((percentile_cont(0.5) WITHIN GROUP (ORDER BY pct))::numeric, 1) FROM p),
    'passPct', (SELECT round(100.0 * count(*) FILTER (WHERE pct >= 33) / nullif(count(*), 0), 1) FROM p))
FROM e;

-- name: getSyllabusCoverage
SELECT coalesce(jsonb_agg(jsonb_build_object('classSection', cs.section_name, 'subject', sub.subject_name, 'teacher', api.user_name(ss.user_id),
       'coveragePct', round(100.0 * x.delivered / nullif(x.due, 0), 1), 'behindBy', greatest(x.due - x.delivered, 0))
       ORDER BY round(100.0 * x.delivered / nullif(x.due, 0), 1) NULLS FIRST, cs.section_name), '[]'::jsonb)
FROM (SELECT lp.class_section_id, lp.staff_subject_id,
             count(*) FILTER (WHERE lp.planned_date <= current_date) AS due,
             count(*) FILTER (WHERE lp.status IN ('DELIVERED', 'PARTIAL')) AS delivered
        FROM learning.lesson_plan lp GROUP BY lp.class_section_id, lp.staff_subject_id) x
JOIN academics.class_section cs ON cs.class_section_id = x.class_section_id
JOIN academics.staff_subject ss ON ss.staff_subject_id = x.staff_subject_id
JOIN academics.subject sub ON sub.subject_id = ss.subject_id;

-- name: sendCircular write
SELECT api.create_notification(:body::jsonb, :me::bigint, :school::bigint) AS result;
-- then
SELECT api.camel(to_jsonb(n)) FROM communication.notification n WHERE n.notification_id = :result::bigint;

-- name: getReadReceipts
SELECT jsonb_build_object('notificationId', n.notification_id,
    'recipients', (SELECT count(*) FROM communication.notification_recipient r WHERE r.notification_id = n.notification_id),
    'read', (SELECT count(*) FROM communication.notification_recipient r WHERE r.notification_id = n.notification_id AND r.read_at IS NOT NULL),
    'acknowledged', (SELECT count(*) FROM communication.notification_recipient r WHERE r.notification_id = n.notification_id AND r.acknowledged_at IS NOT NULL),
    'pending', coalesce((SELECT jsonb_agg(api.person(r.recipient_user_id, api.student_ref(r.student_id) ->> 'name') ORDER BY r.recipient_user_id)
                           FROM (SELECT * FROM communication.notification_recipient r WHERE r.notification_id = n.notification_id
                                    AND (r.read_at IS NULL OR (coalesce(n.requires_ack, false) AND r.acknowledged_at IS NULL)) LIMIT 200) r), '[]'::jsonb))
FROM communication.notification n WHERE n.notification_id = :notificationId::bigint;

-- name: publishReportCards write
-- APPROVED (or DRAFT) cards in the list become PUBLISHED; withheld ones are reported as failures
WITH ids AS (SELECT jsonb_array_elements_text(coalesce(:body::jsonb -> 'ids', '[]'::jsonb))::bigint AS id),
     up AS (UPDATE assessment.report_card rc SET status = 'PUBLISHED', published_at = now()
             WHERE rc.report_card_id IN (SELECT id FROM ids) AND rc.status IN ('APPROVED', 'DRAFT') RETURNING rc.report_card_id)
SELECT jsonb_build_object('requested', (SELECT count(*) FROM ids), 'succeeded', (SELECT count(*) FROM up),
    'failed', (SELECT count(*) FROM ids) - (SELECT count(*) FROM up),
    'errors', coalesce((SELECT jsonb_agg(jsonb_build_object('refId', ids.id, 'code', coalesce(rc.status, 'NOT_FOUND'),
                         'message', CASE WHEN rc.report_card_id IS NULL THEN 'No such report card' ELSE 'Cannot publish a ' || lower(rc.status) || ' card' END))
                         FROM ids LEFT JOIN assessment.report_card rc ON rc.report_card_id = ids.id
                        WHERE ids.id NOT IN (SELECT report_card_id FROM up)), '[]'::jsonb));

-- name: publishTimetable write
-- The version becomes the one published; the previous published version is archived
WITH v AS (SELECT * FROM academics.timetable_version WHERE timetable_version_id = :timetableVersionId::bigint AND status IN ('DRAFT', 'GENERATED')),
     old AS (UPDATE academics.timetable_version t SET status = 'ARCHIVED' FROM v
              WHERE t.status = 'PUBLISHED' AND t.timetable_version_id <> v.timetable_version_id
                AND t.academic_year_id IS NOT DISTINCT FROM v.academic_year_id AND t.term_id IS NOT DISTINCT FROM v.term_id RETURNING 1),
     up AS (UPDATE academics.timetable_version t SET status = 'PUBLISHED', published_by_user_id = :me::bigint
              FROM v WHERE t.timetable_version_id = v.timetable_version_id RETURNING t.*)
SELECT api.camel(to_jsonb(up)) FROM up WHERE (SELECT count(*) FROM old) >= 0;
