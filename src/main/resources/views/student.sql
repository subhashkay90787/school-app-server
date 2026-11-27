-- Screen queries for /api/v1/student: always the caller's own record (api.my_student()).

-- name: getHome
WITH me AS (SELECT s.* FROM academics.student s WHERE s.student_id = api.my_student())
SELECT api.feed('STUDENT',
    (SELECT api.card('hostel-missing', 'CRITICAL', 'OUTING_OVERDUE', 'You are late returning', 'Report to the gate now', NULL, 'CRITICAL', 'outings')
       FROM me WHERE api.hostel_status(me.student_id) = 'MISSING'),
    (SELECT api.card('homework-due', 'NEEDS_YOU', 'HOMEWORK_DUE', 'Assignments due', string_agg(h.title, ', '), count(*), 'ACTION', 'assignments')
       FROM me JOIN operations.homework h ON h.class_section_id = me.class_section_id
      WHERE h.due_date BETWEEN current_date AND current_date + 2 AND coalesce(h.submission_mode, 'ONLINE') = 'ONLINE'
        AND NOT EXISTS (SELECT 1 FROM operations.homework_submission hs WHERE hs.homework_id = h.homework_id AND hs.student_id = me.student_id)),
    (SELECT api.card('quizzes', 'NEEDS_YOU', 'QUIZ_OPEN', 'Quizzes open', string_agg(q.title, ', '), count(*), 'ACTION', 'quizzes')
       FROM me JOIN learning.quiz q ON q.class_section_id = me.class_section_id
      WHERE now() BETWEEN coalesce(q.opens_at, '-infinity') AND coalesce(q.closes_at, 'infinity')
        AND NOT EXISTS (SELECT 1 FROM learning.quiz_attempt a WHERE a.quiz_id = q.quiz_id AND a.student_id = me.student_id AND a.submitted_at IS NOT NULL)),
    (SELECT api.card('next-period', 'NOW', 'NEXT_PERIOD', coalesce(sub.subject_name, 'Free period'), p.period_time || coalesce(' · ' || loc.room_name, ''),
                     NULL, 'INFO', 'timetable')
       FROM me JOIN academics.class_section_period csp ON csp.class_section_id = me.class_section_id
       JOIN academics.period p ON p.period_id = csp.period_id
       JOIN academics.timetable tt ON tt.class_section_period_id = csp.class_section_period_id AND tt.day_of_week = api.dow(current_date)
       LEFT JOIN academics.staff_subject ss ON ss.staff_subject_id = tt.staff_subject_id
       LEFT JOIN academics.subject sub ON sub.subject_id = ss.subject_id
       LEFT JOIN inventory.location loc ON loc.location_id = tt.room_location_id
      WHERE coalesce(api.period_end(p.period_time), time '23:59') > localtime
      ORDER BY api.period_start(p.period_time) LIMIT 1),
    (SELECT api.card('exams', 'TODAY', 'EXAMS_SOON', 'Exams coming up', string_agg(e.exam_name || ' ' || to_char(e.exam_date, 'DD Mon'), ', '), count(*), 'INFO', 'results')
       FROM me JOIN assessment.exams e ON e.class_section_id = me.class_section_id
      WHERE e.exam_date BETWEEN current_date AND current_date + 7 AND e.status = 'SCHEDULED'),
    (SELECT api.card('results', 'FEED', 'RESULTS', 'New results', max(e.exam_name), count(*), 'INFO', 'results')
       FROM me JOIN assessment.marks m ON m.student_id = me.student_id JOIN assessment.exams e ON e.exam_id = m.exam_id
      WHERE e.status = 'PUBLISHED' AND m.entered_at > now() - interval '14 days'),
    (SELECT api.card('menu', 'FEED', 'MESS_MENU', 'Today''s menu', (SELECT string_agg(x ->> 'meal' || ': ' || (x ->> 'items'), ' · ')
                                                                      FROM jsonb_array_elements(hc -> 'todayMenu') x), NULL, 'INFO', 'hostel')
       FROM (SELECT api.hostel_card(student_id) AS hc FROM me) h WHERE hc IS NOT NULL));

-- name: getTimetable
SELECT api.timetable_grid(s.class_section_id) FROM academics.student s WHERE s.student_id = api.my_student() AND s.class_section_id IS NOT NULL;

-- name: getAttendance
SELECT api.subject_attendance(api.my_student()) WHERE api.my_student() IS NOT NULL;

-- name: listAssignments
SELECT api.page(api.homework_views(api.my_student(), NULL), :page, :size) WHERE api.my_student() IS NOT NULL;

-- name: startQuiz write
-- One open attempt per quiz; starting again returns the open attempt
WITH q AS (SELECT q.* FROM learning.quiz q JOIN academics.student s ON s.class_section_id = q.class_section_id AND s.student_id = api.my_student()
            WHERE q.quiz_id = :quizId::bigint AND now() BETWEEN coalesce(q.opens_at, '-infinity') AND coalesce(q.closes_at, 'infinity')),
     open AS (SELECT a.attempt_id FROM learning.quiz_attempt a, q WHERE a.quiz_id = q.quiz_id AND a.student_id = api.my_student() AND a.submitted_at IS NULL),
     ins AS (INSERT INTO learning.quiz_attempt (school_id, quiz_id, student_id, started_at, answers)
             SELECT q.school_id, q.quiz_id, api.my_student(), now(), '{}'::jsonb FROM q WHERE NOT EXISTS (SELECT 1 FROM open)
             RETURNING attempt_id)
SELECT coalesce((SELECT attempt_id FROM ins), (SELECT attempt_id FROM open)) AS result WHERE EXISTS (SELECT 1 FROM q);
-- then
SELECT api.camel(to_jsonb(a)) FROM learning.quiz_attempt a WHERE a.attempt_id = :result::bigint;

-- name: saveQuizAnswers write
-- Saves answers while the attempt is open and the quiz window / duration allow; submit=true closes it (scoring
-- against learning.question.answer for MCQ/MSQ/NUMERIC)
WITH b AS (SELECT :body::jsonb AS j),
     a AS (SELECT a.*, q.duration_minutes, q.closes_at FROM learning.quiz_attempt a JOIN learning.quiz q ON q.quiz_id = a.quiz_id
            WHERE a.attempt_id = :attemptId::bigint AND a.student_id = api.my_student() AND a.submitted_at IS NULL
              AND now() <= coalesce(q.closes_at, 'infinity')
              AND (q.duration_minutes IS NULL OR now() <= a.started_at + make_interval(mins => q.duration_minutes + 1))),
     up AS (
    UPDATE learning.quiz_attempt t
       SET answers = coalesce(t.answers, '{}'::jsonb) || coalesce(b.j -> 'answers', '{}'::jsonb),
           submitted_at = CASE WHEN coalesce((b.j ->> 'submit')::boolean, false) THEN now() END,
           score = CASE WHEN coalesce((b.j ->> 'submit')::boolean, false) THEN (
               SELECT coalesce(sum(qs.marks), 0) FROM learning.quiz_question qq JOIN learning.question qs ON qs.question_id = qq.question_id
                WHERE qq.quiz_id = t.quiz_id AND qs.question_type IN ('MCQ', 'MSQ', 'NUMERIC')
                  AND (coalesce(t.answers, '{}'::jsonb) || coalesce(b.j -> 'answers', '{}'::jsonb)) -> qs.question_id::text = qs.answer) END
      FROM b, a WHERE t.attempt_id = a.attempt_id RETURNING t.attempt_id)
SELECT attempt_id AS result FROM up;
-- then
SELECT api.camel(to_jsonb(a)) FROM learning.quiz_attempt a WHERE a.attempt_id = :result::bigint;

-- name: listResults
SELECT api.exam_results(api.my_student()) WHERE api.my_student() IS NOT NULL;

-- name: getFees
SELECT api.family_dues(ARRAY[api.my_student()]) WHERE api.my_student() IS NOT NULL;

-- name: getHostelCard
SELECT api.hostel_card(api.my_student());

-- name: listOutings
SELECT api.page(coalesce(jsonb_agg(api.outing_view(o.outing_id) ORDER BY o.depart_planned_at DESC), '[]'::jsonb), :page, :size)
FROM hostel.outing_request o WHERE o.student_id = api.my_student();

-- name: requestOuting write
-- Student-raised: parent approval pending when the policy asks for it; warden decides after
WITH b AS (SELECT :body::jsonb AS j),
     a AS (SELECT al.* FROM hostel.allocation al WHERE al.student_id = api.my_student() AND al.status = 'ACTIVE' LIMIT 1),
     pol AS (SELECT p.* FROM hostel.outing_policy p, a, b WHERE p.hostel_id = a.hostel_id AND p.outing_type = b.j ->> 'outingType' LIMIT 1),
     ins AS (
    INSERT INTO hostel.outing_request (school_id, student_id, hostel_id, policy_id, outing_type, purpose, destination, depart_planned_at,
        return_planned_at, travel_mode, travel_ref, travel_departure_at, pickup_person_id, requested_by_kind, requested_by_user_id,
        parent_status, warden_status, release_custody_items, status)
    SELECT a.school_id, a.student_id, a.hostel_id, (SELECT policy_id FROM pol),
           b.j ->> 'outingType', b.j ->> 'purpose', b.j ->> 'destination', (b.j ->> 'departPlannedAt')::timestamptz,
           (b.j ->> 'returnPlannedAt')::timestamptz, b.j ->> 'travelMode', b.j ->> 'travelRef', (b.j ->> 'travelDepartureAt')::timestamptz,
           (SELECT pp.pickup_person_id FROM frontoffice.pickup_person pp WHERE pp.pickup_person_id = (b.j ->> 'pickupPersonId')::bigint
              AND pp.student_id = a.student_id AND coalesce(pp.is_active, true)),
           'STUDENT', :me::bigint,
           CASE WHEN coalesce((SELECT requires_parent_approval FROM pol), true) THEN 'PENDING' ELSE 'NOT_REQUIRED' END,
           'PENDING', coalesce((b.j ->> 'releaseCustodyItems')::boolean, false), 'REQUESTED'
      FROM a, b RETURNING outing_id)
SELECT outing_id AS result FROM ins;
-- then
SELECT api.outing_view(:result::bigint);

-- name: listCustody
SELECT api.custody_items(api.my_student()) WHERE api.my_student() IS NOT NULL;

-- name: getIdCard
SELECT jsonb_strip_nulls(jsonb_build_object('cardNumber', c.card_number, 'name', btrim(s.first_name || ' ' || coalesce(s.last_name, '')),
       'photoUrl', s.photo_url, 'validTill', c.valid_till, 'qrToken', c.qr_token,
       'gateEntryEnabled', c.status = 'ACTIVE' AND coalesce(c.valid_till, current_date) >= current_date))
FROM records.id_card c JOIN academics.student s ON s.student_id = c.holder_id
WHERE c.holder_kind = 'STUDENT' AND c.holder_id = api.my_student() AND c.status = 'ACTIVE'
ORDER BY c.issued_on DESC NULLS LAST LIMIT 1;

-- name: applyToDrive write
-- Open drives only; applying twice returns the existing application
WITH d AS (SELECT * FROM placement.drive WHERE drive_id = :driveId::bigint AND status = 'OPEN'),
     ex AS (SELECT a.application_id FROM placement.application a, d WHERE a.drive_id = d.drive_id AND a.student_id = api.my_student()),
     ins AS (INSERT INTO placement.application (school_id, drive_id, student_id, stage)
             SELECT d.school_id, d.drive_id, api.my_student(), 'APPLIED' FROM d
              WHERE api.my_student() IS NOT NULL AND NOT EXISTS (SELECT 1 FROM ex) RETURNING application_id)
SELECT coalesce((SELECT application_id FROM ins), (SELECT application_id FROM ex)) AS result WHERE EXISTS (SELECT 1 FROM d);
-- then
SELECT api.camel(to_jsonb(a)) FROM placement.application a WHERE a.application_id = :result::bigint;

-- name: dropCourse write
WITH up AS (UPDATE academics.course_registration SET status = 'DROPPED'
             WHERE registration_id = :registrationId::bigint AND student_id = api.my_student() AND status = 'REGISTERED' RETURNING 1)
SELECT CASE WHEN EXISTS (SELECT 1 FROM up) THEN '{}' END;
