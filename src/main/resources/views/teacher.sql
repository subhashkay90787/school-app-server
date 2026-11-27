-- Screen queries for /api/v1/teacher. Sections, students and exams named in the path are checked against the
-- teacher's own (ScopeService: class teacher, timetable, offerings, invigilation) before the query runs.

-- name: getHome
WITH my AS (SELECT api.my_sections() AS cs),
     ct AS (SELECT cs.* FROM academics.class_section cs WHERE cs.teacher_user_id = :me::bigint
              AND cs.academic_year_id IN (SELECT academic_year_id FROM academics.academic_year WHERE is_current)),
     periods AS (SELECT api.my_periods(current_date) AS p)
SELECT api.feed('TEACHER',
    (SELECT api.card('critical', 'CRITICAL', 'CRITICAL_ALERT', max(n.title), max(n.body), count(*), 'CRITICAL', 'alerts')
       FROM communication.notification_recipient r JOIN communication.notification n ON n.notification_id = r.notification_id
      WHERE r.recipient_user_id = :me::bigint AND n.severity = 'CRITICAL' AND r.acknowledged_at IS NULL AND n.sent_time > now() - interval '24 hours'),
    (SELECT api.card('register-' || ct.class_section_id, 'NEEDS_YOU', 'REGISTER_PENDING', 'Take the register', ct.section_name, NULL, 'ACTION',
                     'classes/' || ct.class_section_id || '/register')
       FROM ct WHERE localtime >= coalesce(ct.day_start_time, time '08:30') AND extract(isodow FROM current_date) < 7
        AND NOT EXISTS (SELECT 1 FROM operations.daily_presence dp JOIN academics.student s ON s.student_id = dp.person_id
                         WHERE dp.person_kind = 'STUDENT' AND dp.presence_date = current_date AND s.class_section_id = ct.class_section_id)
      LIMIT 1),
    (SELECT api.card('marks', 'NEEDS_YOU', 'MARKS_PENDING', 'Marks to enter', string_agg(e.exam_name, ', '), count(*), 'ACTION', 'exams')
       FROM assessment.exams e JOIN academics.staff_subject ss ON ss.staff_subject_id = e.staff_subject_id AND ss.user_id = :me::bigint
      WHERE e.status = 'MARKS_ENTRY'),
    (SELECT api.card('grading', 'NEEDS_YOU', 'SUBMISSIONS_TO_GRADE', 'Submissions to grade', NULL, count(*), 'ACTION', 'homework')
       FROM operations.homework_submission hs JOIN operations.homework h ON h.homework_id = hs.homework_id
       JOIN academics.staff_subject ss ON ss.staff_subject_id = h.staff_subject_id AND ss.user_id = :me::bigint
      WHERE hs.status IN ('SUBMITTED', 'LATE')),
    (SELECT api.card('unread', 'NEEDS_YOU', 'MESSAGES', 'Unread parent messages', NULL, count(*), 'INFO', 'conversations')
       FROM communication.conversation_member cm JOIN communication.message m ON m.conversation_id = cm.conversation_id
      WHERE cm.user_id = :me::bigint AND m.sender_user_id <> :me::bigint AND m.deleted_at IS NULL AND m.sent_at > coalesce(cm.last_read_at, '-infinity')),
    (SELECT api.card('next-period', 'NOW', 'NEXT_PERIOD', (x ->> 'subject') || ' · ' || (x ->> 'classSection'),
                     (x ->> 'periodLabel') || coalesce(' · ' || (x ->> 'room'), '') || CASE WHEN (x ->> 'isSubstitution')::boolean THEN ' · substitution' ELSE '' END,
                     NULL, 'INFO', 'today', NULL, x)
       FROM periods, jsonb_array_elements(periods.p) x WHERE coalesce((x ->> 'end')::time, time '23:59') > localtime
      ORDER BY x ->> 'start' LIMIT 1),
    (SELECT api.card('subs', 'TODAY', 'SUBSTITUTIONS', 'Substitution periods today', NULL, count(*), 'INFO', 'today')
       FROM periods, jsonb_array_elements(periods.p) x WHERE (x ->> 'isSubstitution')::boolean),
    (SELECT api.card('invigilation', 'TODAY', 'INVIGILATION', 'Invigilation', string_agg(d ->> 'label', ', '), count(*), 'INFO', 'invigilation')
       FROM jsonb_array_elements(api.my_duties()) d WHERE d ->> 'kind' = 'INVIGILATOR' AND (d ->> 'from')::timestamptz::date <= current_date + 1),
    (SELECT api.card('ptm', 'TODAY', 'PTM', 'PTM bookings', to_char(min(sl.start_at), 'Dy DD Mon HH24:MI'), count(*), 'INFO', 'ptm')
       FROM communication.ptm_slot sl WHERE sl.teacher_user_id = :me::bigint AND sl.status = 'BOOKED' AND sl.start_at BETWEEN now() AND now() + interval '7 days'));

-- name: getToday
SELECT api.my_periods(:date::date);

-- name: markTaught write
-- Updates the named lesson plan (or the one planned for this period today, else creates one) for my period
WITH b AS (SELECT :body::jsonb AS j),
     tt AS (SELECT tt.*, csp.class_section_id FROM academics.timetable tt
              JOIN academics.class_section_period csp ON csp.class_section_period_id = tt.class_section_period_id
             WHERE tt.timetable_id = :timetableId::bigint
               AND (tt.staff_subject_id IN (SELECT staff_subject_id FROM academics.staff_subject WHERE user_id = :me::bigint)
                    OR EXISTS (SELECT 1 FROM operations.substitution s JOIN operations.staff_absences a ON a.staff_absence_id = s.staff_absence_id
                                WHERE s.substitute_user_id = :me::bigint AND a.date = current_date AND s.class_section_period_id = tt.class_section_period_id))),
     target AS (SELECT lp.plan_id FROM learning.lesson_plan lp, tt, b
                 WHERE lp.class_section_id = tt.class_section_id AND lp.staff_subject_id = tt.staff_subject_id
                   AND (lp.plan_id = (b.j ->> 'lessonPlanId')::bigint
                        OR ((b.j ->> 'lessonPlanId') IS NULL AND lp.planned_date = current_date AND lp.status = 'PLANNED'))
                 ORDER BY lp.plan_id LIMIT 1),
     up AS (UPDATE learning.lesson_plan lp SET status = coalesce(b.j ->> 'status', 'DELIVERED'), delivered_on = current_date,
                   timetable_id = tt.timetable_id, activities = coalesce(b.j ->> 'note', lp.activities)
              FROM b, tt WHERE lp.plan_id = (SELECT plan_id FROM target) RETURNING lp.plan_id),
     ins AS (INSERT INTO learning.lesson_plan (school_id, staff_subject_id, class_section_id, planned_date, objectives, status, delivered_on, timetable_id)
             SELECT tt.school_id, tt.staff_subject_id, tt.class_section_id, current_date, coalesce(b.j ->> 'note', 'Taught'),
                    coalesce(b.j ->> 'status', 'DELIVERED'), current_date, tt.timetable_id
               FROM tt, b WHERE NOT EXISTS (SELECT 1 FROM target) AND tt.staff_subject_id IS NOT NULL RETURNING plan_id)
SELECT tt.timetable_id AS result FROM tt WHERE EXISTS (SELECT 1 FROM up) OR EXISTS (SELECT 1 FROM ins);
-- then
SELECT api.period_slot(:result::bigint, current_date);

-- name: listMyClasses
SELECT coalesce(jsonb_agg(jsonb_build_object(
       'classSectionId', cs.class_section_id, 'sectionName', cs.section_name,
       'programName', (SELECT p.name FROM academics.program p WHERE p.program_id = cs.program_id),
       'isClassTeacher', cs.teacher_user_id = :me::bigint,
       'subjects', coalesce((SELECT jsonb_agg(DISTINCT sub.subject_name) FROM academics.timetable tt
                               JOIN academics.class_section_period csp ON csp.class_section_period_id = tt.class_section_period_id
                               JOIN academics.staff_subject ss ON ss.staff_subject_id = tt.staff_subject_id AND ss.user_id = :me::bigint
                               JOIN academics.subject sub ON sub.subject_id = ss.subject_id
                              WHERE csp.class_section_id = cs.class_section_id), '[]'::jsonb),
       'studentCount', (SELECT count(*) FROM academics.student s WHERE s.class_section_id = cs.class_section_id AND s.status = 'ACTIVE'),
       'registerTakenToday', EXISTS (SELECT 1 FROM operations.daily_presence dp JOIN academics.student s ON s.student_id = dp.person_id
                                      WHERE dp.person_kind = 'STUDENT' AND dp.presence_date = current_date AND s.class_section_id = cs.class_section_id))
       ORDER BY cs.teacher_user_id = :me::bigint DESC, cs.section_name), '[]'::jsonb)
FROM academics.class_section cs WHERE cs.class_section_id IN (SELECT api.my_sections());

-- name: getStudent
SELECT api.student_card(s.student_id) FROM academics.student s
WHERE s.student_id = :studentId::bigint AND s.class_section_id IN (SELECT api.my_sections());

-- name: listClassStudents
SELECT coalesce(jsonb_agg(api.student_card(s.student_id) ORDER BY s.first_name, s.last_name), '[]'::jsonb)
FROM academics.student s
WHERE s.class_section_id = :classSectionId::bigint AND s.status = 'ACTIVE' AND :classSectionId::bigint IN (SELECT api.my_sections());

-- name: getRegister
SELECT api.register_sheet(:classSectionId::bigint, NULL, :date::date, :periodId::bigint) WHERE :classSectionId::bigint IN (SELECT api.my_sections());

-- name: submitRegister write
-- Day register (no periodId; class teacher): every student gets a daily_presence row (absentees ABSENT or LATE,
-- locked rows keep ON_LEAVE / ON_OUTING) and absentees a day-level absence. Period register: absences for that
-- period only. Resubmitting replaces the earlier entry for that day / period.
WITH b AS (SELECT :body::jsonb AS j),
     d AS (SELECT coalesce((j ->> 'date')::date, current_date) AS day, (j ->> 'periodId')::bigint AS period_id FROM b),
     cs AS (SELECT cs.* FROM academics.class_section cs, d WHERE cs.class_section_id = :classSectionId::bigint
              AND ((d.period_id IS NULL AND cs.teacher_user_id = :me::bigint) OR (d.period_id IS NOT NULL AND cs.class_section_id IN (SELECT api.my_sections())))
              AND d.day <= current_date AND d.day >= current_date - 7),
     csp AS (SELECT csp.class_section_period_id FROM academics.class_section_period csp, d, cs
              WHERE csp.class_section_id = cs.class_section_id AND csp.period_id = d.period_id),
     ab AS (SELECT (x ->> 'studentId')::bigint AS sid, coalesce(x ->> 'reason', 'UNEXCUSED') AS reason, coalesce((x ->> 'late')::boolean, false) AS late
              FROM b, jsonb_array_elements(coalesce(b.j -> 'absentees', '[]'::jsonb)) x),
     st AS (SELECT s.student_id, api.register_lock(s.student_id, d.day) AS lock, ab.reason, ab.late, ab.sid IS NOT NULL AS listed
              FROM academics.student s JOIN cs ON s.class_section_id = cs.class_section_id CROSS JOIN d
              LEFT JOIN ab ON ab.sid = s.student_id WHERE s.status = 'ACTIVE'),
     dp AS (INSERT INTO operations.daily_presence (school_id, person_kind, person_id, presence_date, first_in_at, late_minutes, status, computed_by, corrected_by_user_id, recomputed_at)
            SELECT cs.school_id, 'STUDENT', st.student_id, d.day, NULL, NULL,
                   coalesce(st.lock, CASE WHEN st.listed AND st.late THEN 'LATE' WHEN st.listed THEN 'ABSENT' ELSE 'PRESENT' END),
                   'MANUAL', :me::bigint, now()
              FROM st, cs, d WHERE d.period_id IS NULL
            ON CONFLICT (school_id, person_kind, person_id, presence_date) DO UPDATE
               SET status = EXCLUDED.status, computed_by = 'MANUAL', corrected_by_user_id = EXCLUDED.corrected_by_user_id, recomputed_at = now()
            RETURNING 1),
     del AS (DELETE FROM operations.student_absence a USING d, cs
              WHERE a.date = d.day AND a.student_id IN (SELECT student_id FROM st)
                AND ((d.period_id IS NULL AND a.class_section_period_id IS NULL AND a.offering_id IS NULL)
                     OR (d.period_id IS NOT NULL AND a.class_section_period_id = (SELECT class_section_period_id FROM csp)))
                AND a.student_leave_request_id IS NULL RETURNING 1),
     ins AS (INSERT INTO operations.student_absence (school_id, student_id, class_section_period_id, date, reported_by_user_id, absence_reason)
             SELECT cs.school_id, st.student_id, (SELECT class_section_period_id FROM csp), d.day, :me::bigint, st.reason
               FROM st, cs, d WHERE st.listed AND NOT st.late AND st.lock IS NULL
                AND (d.period_id IS NULL OR EXISTS (SELECT 1 FROM csp)) RETURNING 1)
SELECT cs.class_section_id AS result FROM cs
 WHERE (SELECT count(*) FROM dp) + (SELECT count(*) FROM del) + (SELECT count(*) FROM ins) >= 0
   AND ((SELECT period_id FROM d) IS NULL OR EXISTS (SELECT 1 FROM csp));
-- then
SELECT api.register_sheet(:result::bigint, NULL, coalesce((:body::jsonb ->> 'date')::date, current_date), (:body::jsonb ->> 'periodId')::bigint);

-- name: getLectureAttendance
SELECT api.register_sheet(co.class_section_id, co.offering_id, :date::date, NULL)
FROM academics.course_offering co JOIN academics.staff_subject ss ON ss.staff_subject_id = co.staff_subject_id AND ss.user_id = :me::bigint
WHERE co.offering_id = :offeringId::bigint;

-- name: submitLectureAttendance write
WITH b AS (SELECT :body::jsonb AS j),
     co AS (SELECT co.* FROM academics.course_offering co JOIN academics.staff_subject ss ON ss.staff_subject_id = co.staff_subject_id AND ss.user_id = :me::bigint
             WHERE co.offering_id = :offeringId::bigint),
     d AS (SELECT coalesce((j ->> 'date')::date, current_date) AS day FROM b),
     ab AS (SELECT (x ->> 'studentId')::bigint AS sid, coalesce(x ->> 'reason', 'UNEXCUSED') AS reason
              FROM b, jsonb_array_elements(coalesce(b.j -> 'absentees', '[]'::jsonb)) x WHERE NOT coalesce((x ->> 'late')::boolean, false)),
     del AS (DELETE FROM operations.student_absence a USING co, d WHERE a.offering_id = co.offering_id AND a.date = d.day RETURNING 1),
     ins AS (INSERT INTO operations.student_absence (school_id, student_id, offering_id, date, reported_by_user_id, absence_reason)
             SELECT co.school_id, ab.sid, co.offering_id, d.day, :me::bigint, ab.reason FROM co, d, ab
              WHERE ab.sid IN (SELECT r.student_id FROM academics.course_registration r WHERE r.offering_id = co.offering_id AND r.status = 'REGISTERED')
             RETURNING 1)
SELECT co.offering_id AS result FROM co WHERE (SELECT count(*) FROM del) + (SELECT count(*) FROM ins) >= 0;
-- then
SELECT api.register_sheet(co.class_section_id, co.offering_id, coalesce((:body::jsonb ->> 'date')::date, current_date), NULL)
FROM academics.course_offering co WHERE co.offering_id = :result::bigint;

-- name: getMarksSheet
SELECT api.marks_sheet(:examId::bigint);

-- name: saveMarks write
-- My exam (subject teacher) while SCHEDULED / MARKS_ENTRY; after LOCKED only with a reason (the audit log keeps
-- before/after); never once PUBLISHED. Grade from the scale.
WITH b AS (SELECT :body::jsonb AS j),
     e AS (SELECT e.* FROM assessment.exams e, b WHERE e.exam_id = :examId::bigint
             AND (e.staff_subject_id IN (SELECT staff_subject_id FROM academics.staff_subject WHERE user_id = :me::bigint)
                  OR e.class_section_id IN (SELECT class_section_id FROM academics.class_section WHERE teacher_user_id = :me::bigint))
             AND (e.status IN ('DRAFT', 'SCHEDULED', 'MARKS_ENTRY') OR (e.status = 'LOCKED' AND coalesce(b.j ->> 'reason', '') <> ''))),
     x AS (SELECT (r ->> 'studentId')::bigint AS sid, (r ->> 'markObtained')::numeric AS mark,
                  coalesce((r ->> 'absent')::boolean, false) OR coalesce((r ->> 'exempt')::boolean, false) AS absent
             FROM b, jsonb_array_elements(coalesce(b.j -> 'entries', '[]'::jsonb)) r),
     ok AS (SELECT x.* FROM x, e WHERE (x.mark IS NULL OR (x.mark >= 0 AND x.mark <= coalesce(e.max_marks, x.mark)))
              AND x.sid IN (SELECT s.student_id FROM academics.student s WHERE s.class_section_id = e.class_section_id
                            UNION SELECT r.student_id FROM academics.course_registration r WHERE r.offering_id = e.offering_id)),
     up AS (INSERT INTO assessment.marks (school_id, exam_id, student_id, mark_obtained, is_absent, entered_by_user_id, entered_at)
            SELECT e.school_id, e.exam_id, ok.sid, CASE WHEN ok.absent THEN NULL ELSE ok.mark END, ok.absent, :me::bigint, now() FROM ok, e
            ON CONFLICT (school_id, exam_id, student_id) DO UPDATE
               SET mark_obtained = EXCLUDED.mark_obtained, is_absent = EXCLUDED.is_absent, entered_by_user_id = EXCLUDED.entered_by_user_id,
                   entered_at = now()
            RETURNING 1),
     st AS (UPDATE assessment.exams SET status = 'MARKS_ENTRY' WHERE exam_id = (SELECT exam_id FROM e) AND status IN ('DRAFT', 'SCHEDULED') RETURNING 1)
SELECT e.exam_id AS result FROM e WHERE (SELECT count(*) FROM up) + (SELECT count(*) FROM st) >= 0
   AND NOT EXISTS (SELECT 1 FROM x WHERE x.sid NOT IN (SELECT sid FROM ok));
-- then
SELECT api.marks_sheet(:result::bigint);

-- name: lockMarks write
WITH up AS (UPDATE assessment.exams e SET status = 'LOCKED'
             WHERE e.exam_id = :examId::bigint AND e.status = 'MARKS_ENTRY'
               AND (e.staff_subject_id IN (SELECT staff_subject_id FROM academics.staff_subject WHERE user_id = :me::bigint)
                    OR e.class_section_id IN (SELECT class_section_id FROM academics.class_section WHERE teacher_user_id = :me::bigint))
             RETURNING e.exam_id)
SELECT exam_id AS result FROM up;
-- then
SELECT api.marks_sheet(:result::bigint);

-- name: gradeSubmission write
WITH b AS (SELECT :body::jsonb AS j),
     up AS (UPDATE operations.homework_submission hs
               SET marks = coalesce((b.j ->> 'marks')::numeric, hs.marks), feedback = coalesce(b.j ->> 'feedback', hs.feedback),
                   status = coalesce(b.j ->> 'status', 'GRADED'), graded_by_user_id = :me::bigint
              FROM b, operations.homework h
             WHERE hs.submission_id = :submissionId::bigint AND hs.homework_id = :homeworkId::bigint AND h.homework_id = hs.homework_id
               AND (h.staff_subject_id IN (SELECT staff_subject_id FROM academics.staff_subject WHERE user_id = :me::bigint)
                    OR h.class_section_id IN (SELECT class_section_id FROM academics.class_section WHERE teacher_user_id = :me::bigint))
               AND ((b.j ->> 'marks') IS NULL OR h.max_marks IS NULL OR (b.j ->> 'marks')::numeric BETWEEN 0 AND h.max_marks)
             RETURNING hs.*)
SELECT api.camel(to_jsonb(up)) FROM up;

-- name: getSyllabus
SELECT api.syllabus_tree(coalesce(:subjectId::bigint,
         (SELECT ss.subject_id FROM academics.staff_subject ss WHERE ss.user_id = :me::bigint ORDER BY ss.staff_subject_id LIMIT 1)),
       :classSectionId::bigint);

-- name: messageParents write
-- ONE_STUDENT: the parent-teacher conversation for that student (created when missing); GROUP / WHOLE_CLASS: the
-- section's class group. Push / WhatsApp delivery comes with the notification flows.
WITH b AS (SELECT :body::jsonb AS j),
     cs AS (SELECT * FROM academics.class_section WHERE class_section_id = :classSectionId::bigint AND class_section_id IN (SELECT api.my_sections())),
     one AS (SELECT s.student_id FROM academics.student s, b, cs
              WHERE b.j ->> 'audience' = 'ONE_STUDENT' AND s.class_section_id = cs.class_section_id
                AND s.student_id = (b.j -> 'studentIds' ->> 0)::bigint),
     existing AS (
        SELECT c.conversation_id FROM communication.conversation c, cs, b
         WHERE (b.j ->> 'audience' = 'ONE_STUDENT' AND c.kind = 'PARENT_TEACHER' AND c.student_id = (SELECT student_id FROM one)
                AND EXISTS (SELECT 1 FROM communication.conversation_member m WHERE m.conversation_id = c.conversation_id AND m.user_id = :me::bigint))
            OR (coalesce(b.j ->> 'audience', 'WHOLE_CLASS') <> 'ONE_STUDENT' AND c.kind = 'CLASS_GROUP' AND c.class_section_id = cs.class_section_id)
         ORDER BY c.conversation_id LIMIT 1),
     created AS (
        INSERT INTO communication.conversation (school_id, kind, student_id, class_section_id, created_by_user_id, parents_can_reply, is_locked, created_at)
        SELECT cs.school_id, CASE WHEN b.j ->> 'audience' = 'ONE_STUDENT' THEN 'PARENT_TEACHER' ELSE 'CLASS_GROUP' END,
               (SELECT student_id FROM one), cs.class_section_id, :me::bigint, b.j ->> 'audience' = 'ONE_STUDENT', false, now()
          FROM cs, b WHERE NOT EXISTS (SELECT 1 FROM existing) AND (b.j ->> 'audience' <> 'ONE_STUDENT' OR EXISTS (SELECT 1 FROM one))
        RETURNING conversation_id, school_id),
     conv AS (SELECT conversation_id FROM existing UNION ALL SELECT conversation_id FROM created),
     members AS (
        INSERT INTO communication.conversation_member (school_id, conversation_id, user_id, member_role, last_read_at)
        SELECT :school::bigint, (SELECT conversation_id FROM conv), u.uid, u.role, CASE WHEN u.uid = :me::bigint THEN now() END
          FROM (SELECT :me::bigint AS uid, 'MODERATOR' AS role
                UNION SELECT sp.user_id, 'PARENT' FROM academics.student_parent sp
                 WHERE sp.student_id IN (SELECT student_id FROM one
                                         UNION SELECT s.student_id FROM academics.student s, cs, b
                                                WHERE b.j ->> 'audience' <> 'ONE_STUDENT' AND s.class_section_id = cs.class_section_id AND s.status = 'ACTIVE')) u
         WHERE EXISTS (SELECT 1 FROM conv)
        ON CONFLICT DO NOTHING RETURNING 1),
     msg AS (
        INSERT INTO communication.message (school_id, conversation_id, sender_user_id, body, attachment_urls, sent_at)
        SELECT :school::bigint, conv.conversation_id, :me::bigint,
               coalesce(b.j ->> 'body', (SELECT t.body FROM communication.template t WHERE t.template_id = (b.j ->> 'templateId')::bigint)),
               (SELECT array_agg(x) FROM jsonb_array_elements_text(coalesce(b.j -> 'attachmentUrls', '[]'::jsonb)) x), now()
          FROM conv, b RETURNING conversation_id)
SELECT conversation_id AS result FROM msg WHERE (SELECT count(*) FROM members) >= 0;
-- then
SELECT jsonb_strip_nulls(jsonb_build_object('conversationId', c.conversation_id, 'kind', c.kind,
       'title', CASE WHEN c.kind = 'CLASS_GROUP' THEN api.section_label(c.class_section_id) || ' group' ELSE api.student_ref(c.student_id) ->> 'name' || ' (parents)' END,
       'student', api.student_ref(c.student_id),
       'lastMessage', (SELECT m.body FROM communication.message m WHERE m.conversation_id = c.conversation_id ORDER BY m.sent_at DESC LIMIT 1),
       'lastMessageAt', (SELECT max(m.sent_at) FROM communication.message m WHERE m.conversation_id = c.conversation_id),
       'unread', 0, 'locked', coalesce(c.is_locked, false), 'withinChatHours', true))
FROM communication.conversation c WHERE c.conversation_id = :result::bigint;

-- name: escalateToIncident write
-- Raises a discipline incident from a behaviour note I logged (or about my section); the note links to it
WITH l AS (SELECT l.* FROM assessment.student_behavior_log l JOIN academics.student s ON s.student_id = l.student_id
            WHERE l.log_id = :logId::bigint AND l.incident_id IS NULL
              AND (l.logged_by_user_id = :me::bigint OR s.class_section_id IN (SELECT api.my_sections()))),
     inc AS (INSERT INTO discipline.incident (school_id, occurred_at, category, severity, description, reported_by_user_id, status)
             SELECT l.school_id, l.log_date::timestamptz, 'OTHER', CASE WHEN upper(coalesce(l.severity, '')) IN ('HIGH', 'MAJOR') THEN 'MAJOR' ELSE 'MODERATE' END,
                    coalesce(l.category || ': ', '') || coalesce(l.note, ''), :me::bigint, 'REPORTED'
               FROM l RETURNING incident_id, school_id),
     inv AS (INSERT INTO discipline.incident_student (school_id, incident_id, student_id, involvement)
             SELECT inc.school_id, inc.incident_id, l.student_id, 'PRIMARY' FROM inc, l RETURNING 1),
     link AS (UPDATE assessment.student_behavior_log t SET incident_id = inc.incident_id FROM inc WHERE t.log_id = :logId::bigint RETURNING 1)
SELECT incident_id AS result FROM inc WHERE (SELECT count(*) FROM inv) + (SELECT count(*) FROM link) >= 0;
-- then
SELECT api.camel(to_jsonb(i)) FROM discipline.incident i WHERE i.incident_id = :result::bigint;

-- name: publishPtmSlots write
-- Slots of slotMinutes (default: the session's) between startAt and endAt for me; overlapping slots are skipped
WITH b AS (SELECT :body::jsonb AS j),
     ps AS (SELECT * FROM communication.ptm_session WHERE ptm_id = :ptmId::bigint
              AND (class_section_id IS NULL OR class_section_id IN (SELECT api.my_sections()))),
     g AS (SELECT gs AS start_at FROM b, ps,
                  generate_series((b.j ->> 'startAt')::timestamptz,
                                  (b.j ->> 'endAt')::timestamptz - make_interval(mins => coalesce((b.j ->> 'slotMinutes')::int, ps.slot_minutes, 10)),
                                  make_interval(mins => coalesce((b.j ->> 'slotMinutes')::int, ps.slot_minutes, 10))) gs
            WHERE (b.j ->> 'endAt')::timestamptz - (b.j ->> 'startAt')::timestamptz <= interval '12 hours'),
     ins AS (INSERT INTO communication.ptm_slot (school_id, ptm_id, teacher_user_id, start_at, status)
             SELECT ps.school_id, ps.ptm_id, :me::bigint, g.start_at, 'OPEN' FROM ps, g
              WHERE NOT EXISTS (SELECT 1 FROM communication.ptm_slot x WHERE x.ptm_id = ps.ptm_id AND x.teacher_user_id = :me::bigint
                                  AND x.start_at = g.start_at AND x.status <> 'CANCELLED')
             RETURNING 1)
SELECT ps.ptm_id AS result FROM ps WHERE (SELECT count(*) FROM ins) >= 0;
-- then
SELECT coalesce(jsonb_agg(api.camel(to_jsonb(sl)) ORDER BY sl.start_at), '[]'::jsonb)
FROM communication.ptm_slot sl WHERE sl.ptm_id = :result::bigint AND sl.teacher_user_id = :me::bigint;

-- name: listInvigilation
-- Exams I invigilate on the date (default: today and the next 14 days)
SELECT coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
       'examId', e.exam_id, 'examName', e.exam_name,
       'room', (SELECT l.room_name FROM inventory.location l WHERE l.location_id = coalesce(d.room_location_id, e.room_location_id)),
       'start', e.start_time, 'durationMinutes', e.duration_minutes,
       'candidates', coalesce((SELECT jsonb_agg(jsonb_build_object('studentId', s.student_id, 'rollNo', s.student_admission_number,
                         'name', btrim(s.first_name || ' ' || coalesce(s.last_name, '')), 'status',
                         CASE WHEN api.register_lock(s.student_id, e.exam_date) IS NOT NULL THEN api.register_lock(s.student_id, e.exam_date)
                              WHEN EXISTS (SELECT 1 FROM assessment.hall_ticket ht WHERE ht.student_id = s.student_id AND ht.exam_session_id = e.exam_session_id
                                             AND coalesce(ht.is_blocked, false)) THEN 'EXCUSED' ELSE 'PRESENT' END,
                         'locked', EXISTS (SELECT 1 FROM assessment.hall_ticket ht WHERE ht.student_id = s.student_id AND ht.exam_session_id = e.exam_session_id
                                             AND coalesce(ht.is_blocked, false)),
                         'lockReason', (SELECT ht.blocked_reason FROM assessment.hall_ticket ht WHERE ht.student_id = s.student_id
                                          AND ht.exam_session_id = e.exam_session_id AND coalesce(ht.is_blocked, false) LIMIT 1))
                       ORDER BY s.first_name)
                     FROM academics.student s WHERE s.class_section_id = e.class_section_id AND s.status = 'ACTIVE'), '[]'::jsonb),
       'seating', coalesce((SELECT jsonb_agg(jsonb_build_object('studentId', st.student_id, 'name', api.student_ref(st.student_id) ->> 'name',
                         'seatLabel', st.seat_label) ORDER BY st.seat_label)
                     FROM assessment.seating st WHERE st.exam_id = e.exam_id
                      AND (d.room_location_id IS NULL OR st.room_location_id = d.room_location_id)), '[]'::jsonb)))
       ORDER BY e.exam_date, e.start_time), '[]'::jsonb)
FROM assessment.exams e
LEFT JOIN LATERAL (SELECT i.room_location_id FROM assessment.invigilation_duty i WHERE i.exam_id = e.exam_id AND i.user_id = :me::bigint LIMIT 1) d ON true
WHERE (e.invigilated_by_user_id = :me::bigint OR EXISTS (SELECT 1 FROM assessment.invigilation_duty i WHERE i.exam_id = e.exam_id AND i.user_id = :me::bigint))
  AND ((:date IS NOT NULL AND e.exam_date = :date::date) OR (:date IS NULL AND e.exam_date BETWEEN current_date AND current_date + 14));

-- name: getEscortGroup
SELECT api.travel_group_board(g.group_id) FROM hostel.outing_group g WHERE g.group_id = :groupId::bigint AND g.escort_user_id = :me::bigint;
