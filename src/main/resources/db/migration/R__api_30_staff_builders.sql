-- Response builders for staff screens (teacher, hostel, security). Repeatable migration; SECURITY INVOKER.

-- Locked register rows: approved leave, hostel outing / sick bay on that date
CREATE OR REPLACE FUNCTION api.register_lock(p_student_id BIGINT, p_date DATE) RETURNS TEXT
    LANGUAGE sql STABLE AS $$
    SELECT CASE
        WHEN EXISTS (SELECT 1 FROM operations.student_leave_request l WHERE l.student_id = p_student_id AND l.status = 'APPROVED'
                       AND p_date BETWEEN l.from_date AND l.to_date) THEN 'ON_LEAVE'
        WHEN EXISTS (SELECT 1 FROM hostel.outing_request o WHERE o.student_id = p_student_id AND o.status IN ('OUT', 'OVERDUE')
                       AND p_date BETWEEN o.depart_planned_at::date AND o.return_planned_at::date) THEN 'ON_OUTING'
        END
$$;

-- RegisterSheet for a section (day register, or one period) or for a college offering (its registered students)
CREATE OR REPLACE FUNCTION api.register_sheet(p_class_section_id BIGINT, p_offering_id BIGINT, p_date DATE, p_period_id BIGINT) RETURNS JSONB
    LANGUAGE sql STABLE AS $$
    WITH d AS (SELECT coalesce(p_date, current_date) AS day),
         csp AS (SELECT csp.class_section_period_id FROM academics.class_section_period csp
                  WHERE csp.class_section_id = p_class_section_id AND csp.period_id = p_period_id),
         st AS (SELECT s.* FROM academics.student s WHERE s.status = 'ACTIVE' AND (
                    (p_offering_id IS NULL AND s.class_section_id = p_class_section_id)
                 OR (p_offering_id IS NOT NULL AND s.student_id IN (SELECT r.student_id FROM academics.course_registration r
                                                                      WHERE r.offering_id = p_offering_id AND r.status = 'REGISTERED')))),
         rows AS (
            SELECT st.student_id, st.student_admission_number, btrim(st.first_name || ' ' || coalesce(st.last_name, '')) AS name, st.photo_url,
                   api.register_lock(st.student_id, d.day) AS lock,
                   CASE WHEN p_period_id IS NULL AND p_offering_id IS NULL THEN
                            (SELECT dp.status FROM operations.daily_presence dp WHERE dp.person_kind = 'STUDENT' AND dp.person_id = st.student_id
                               AND dp.presence_date = d.day)
                        ELSE (SELECT CASE WHEN a.absence_reason = 'EXCUSED' THEN 'EXCUSED' ELSE 'ABSENT' END FROM operations.student_absence a
                               WHERE a.student_id = st.student_id AND a.date = d.day
                                 AND ((p_offering_id IS NOT NULL AND a.offering_id = p_offering_id)
                                      OR (p_offering_id IS NULL AND a.class_section_period_id = (SELECT class_section_period_id FROM csp)))
                               LIMIT 1) END AS status
              FROM st, d),
         taken AS (SELECT CASE WHEN p_period_id IS NULL AND p_offering_id IS NULL
                               THEN (SELECT max(coalesce(dp.recomputed_at, dp.first_in_at, now())) FROM operations.daily_presence dp
                                      WHERE dp.person_kind = 'STUDENT' AND dp.presence_date = (SELECT day FROM d) AND dp.computed_by = 'MANUAL'
                                        AND dp.person_id IN (SELECT student_id FROM st))
                               END AS at)
    SELECT jsonb_strip_nulls(jsonb_build_object(
        'classSectionId', p_class_section_id, 'offeringId', p_offering_id, 'date', (SELECT day FROM d), 'periodId', p_period_id,
        'submitted', (SELECT at IS NOT NULL FROM taken) OR EXISTS (SELECT 1 FROM rows WHERE status IS NOT NULL),
        'submittedAt', (SELECT at FROM taken),
        'rows', coalesce((SELECT jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
                     'studentId', student_id, 'rollNo', student_admission_number, 'name', name, 'photoUrl', photo_url,
                     'status', coalesce(lock, CASE WHEN status IN ('PRESENT', 'ABSENT', 'LATE', 'EXCUSED', 'ON_LEAVE', 'ON_OUTING') THEN status END, 'PRESENT'),
                     'locked', lock IS NOT NULL, 'lockReason', CASE lock WHEN 'ON_LEAVE' THEN 'Approved leave' WHEN 'ON_OUTING' THEN 'Out on hostel pass' END))
                   ORDER BY name) FROM rows), '[]'::jsonb),
        'presentCount', (SELECT count(*) FROM rows WHERE lock IS NULL AND coalesce(status, 'PRESENT') IN ('PRESENT', 'LATE')),
        'absentCount', (SELECT count(*) FROM rows WHERE status = 'ABSENT' OR lock IS NOT NULL)))
$$;

-- PeriodSlot for one timetable entry on a date, from the caller's point of view (substitution, taught)
CREATE OR REPLACE FUNCTION api.period_slot(p_timetable_id BIGINT, p_date DATE, p_substitution BOOLEAN DEFAULT false) RETURNS JSONB
    LANGUAGE sql STABLE AS $$
    SELECT jsonb_strip_nulls(jsonb_build_object(
        'timetableId', tt.timetable_id, 'periodLabel', p.period_time, 'start', api.period_start(p.period_time), 'end', api.period_end(p.period_time),
        'subject', coalesce(sub.subject_name, osub.subject_name), 'classSection', api.section_label(csp.class_section_id), 'room', loc.room_name,
        'topic', (SELECT u.title FROM learning.lesson_plan lp JOIN learning.syllabus_unit u ON u.unit_id = lp.unit_id
                   WHERE lp.class_section_id = csp.class_section_id AND lp.staff_subject_id = tt.staff_subject_id
                     AND (lp.timetable_id = tt.timetable_id AND lp.delivered_on = p_date OR lp.planned_date = p_date)
                   ORDER BY (lp.timetable_id = tt.timetable_id) DESC NULLS LAST LIMIT 1),
        'isSubstitution', p_substitution,
        'taught', EXISTS (SELECT 1 FROM learning.lesson_plan lp WHERE lp.timetable_id = tt.timetable_id AND lp.delivered_on = p_date
                            AND lp.status IN ('DELIVERED', 'PARTIAL'))))
    FROM academics.timetable tt
    JOIN academics.class_section_period csp ON csp.class_section_period_id = tt.class_section_period_id
    JOIN academics.period p ON p.period_id = csp.period_id
    LEFT JOIN academics.staff_subject ss ON ss.staff_subject_id = tt.staff_subject_id
    LEFT JOIN academics.subject sub ON sub.subject_id = ss.subject_id
    LEFT JOIN academics.course_offering co ON co.offering_id = tt.offering_id
    LEFT JOIN academics.subject osub ON osub.subject_id = co.subject_id
    LEFT JOIN inventory.location loc ON loc.location_id = tt.room_location_id
    WHERE tt.timetable_id = p_timetable_id
$$;

-- The calling teacher's periods on a date: own timetable minus periods handed to a substitute, plus substitutions
CREATE OR REPLACE FUNCTION api.my_periods(p_date DATE) RETURNS JSONB
    LANGUAGE sql STABLE AS $$
    WITH d AS (SELECT coalesce(p_date, current_date) AS day),
         own AS (SELECT tt.timetable_id, false AS sub FROM academics.timetable tt
                   JOIN academics.staff_subject ss ON ss.staff_subject_id = tt.staff_subject_id AND ss.user_id = platform.current_user_id(), d
                  WHERE tt.day_of_week = api.dow(d.day)
                    AND NOT EXISTS (SELECT 1 FROM operations.substitution s JOIN operations.staff_absences a ON a.staff_absence_id = s.staff_absence_id
                                     WHERE a.user_id = platform.current_user_id() AND a.date = d.day
                                       AND s.class_section_period_id = tt.class_section_period_id)),
         subs AS (SELECT tt.timetable_id, true AS sub FROM operations.substitution s
                    JOIN operations.staff_absences a ON a.staff_absence_id = s.staff_absence_id, d
                    JOIN academics.timetable tt ON tt.day_of_week = api.dow(d.day)
                   WHERE s.substitute_user_id = platform.current_user_id() AND a.date = d.day
                     AND tt.class_section_period_id = s.class_section_period_id),
         all_ AS (SELECT * FROM own UNION ALL SELECT * FROM subs)
    SELECT coalesce(jsonb_agg(v ORDER BY v ->> 'start' NULLS LAST, v ->> 'periodLabel'), '[]'::jsonb)
    FROM (SELECT api.period_slot(all_.timetable_id, d.day, all_.sub) AS v FROM all_, d) x
$$;

-- MarksSheet for an exam: every student of the section (or registered for the offering)
CREATE OR REPLACE FUNCTION api.marks_sheet(p_exam_id BIGINT) RETURNS JSONB
    LANGUAGE sql STABLE AS $$
    WITH e AS (SELECT * FROM assessment.exams WHERE exam_id = p_exam_id),
         st AS (SELECT s.* FROM academics.student s, e WHERE s.status = 'ACTIVE' AND (
                    (e.offering_id IS NULL AND s.class_section_id = e.class_section_id)
                 OR (e.offering_id IS NOT NULL AND s.student_id IN (SELECT r.student_id FROM academics.course_registration r
                                                                      WHERE r.offering_id = e.offering_id AND r.status <> 'DROPPED')))),
         r AS (SELECT st.student_id, st.student_admission_number, btrim(st.first_name || ' ' || coalesce(st.last_name, '')) AS name,
                      m.mark_obtained, coalesce(m.is_absent, false) AS absent,
                      coalesce(g.grade_name, CASE WHEN m.mark_obtained IS NOT NULL AND e.max_marks > 0
                                                  THEN api.grade_for(st.student_id, 100.0 * m.mark_obtained::numeric / e.max_marks) END) AS grade
                 FROM st CROSS JOIN e
                 LEFT JOIN assessment.marks m ON m.exam_id = e.exam_id AND m.student_id = st.student_id
                 LEFT JOIN assessment.grade g ON g.grade_id = m.grade_id)
    SELECT jsonb_strip_nulls(jsonb_build_object(
        'examId', e.exam_id, 'examName', e.exam_name, 'maxMarks', e.max_marks, 'status', e.status,
        'rows', coalesce((SELECT jsonb_agg(jsonb_strip_nulls(jsonb_build_object('studentId', student_id, 'rollNo', student_admission_number,
                     'name', name, 'markObtained', mark_obtained, 'absent', absent, 'exempt', false, 'grade', grade,
                     'locked', e.status IN ('LOCKED', 'PUBLISHED'))) ORDER BY name) FROM r), '[]'::jsonb),
        'average', (SELECT round(avg(mark_obtained)::numeric, 2) FROM r WHERE NOT absent)))
    FROM e
$$;

-- TravelGroupBoard: the group and each student on it (parent confirmation, scanned out, phone released, arrival)
CREATE OR REPLACE FUNCTION api.travel_group_board(p_group_id BIGINT) RETURNS JSONB
    LANGUAGE sql STABLE AS $$
    SELECT jsonb_build_object('group', api.camel(to_jsonb(g)),
        'students', coalesce((SELECT jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
                'student', api.student_ref(o.student_id), 'outingId', o.outing_id,
                'parentConfirmed', o.parent_status IN ('APPROVED', 'NOT_REQUIRED'),
                'scannedOut', EXISTS (SELECT 1 FROM hostel.outing_movement mv WHERE mv.outing_id = o.outing_id AND mv.direction = 'OUT'),
                'phoneReleased', EXISTS (SELECT 1 FROM custody.event ce WHERE ce.outing_id = o.outing_id AND ce.event_type = 'RELEASE'),
                'arrivedAt', (SELECT max(mv.moved_at) FROM hostel.outing_movement mv WHERE mv.outing_id = o.outing_id AND mv.direction = 'IN')))
              ORDER BY api.student_ref(o.student_id) ->> 'name')
            FROM hostel.outing_request o WHERE o.group_id = g.group_id AND o.status NOT IN ('CANCELLED', 'REJECTED')), '[]'::jsonb))
    FROM hostel.outing_group g WHERE g.group_id = p_group_id
$$;

-- SyllabusTree for a subject (and section, for delivered periods); two levels of units
CREATE OR REPLACE FUNCTION api.syllabus_tree(p_subject_id BIGINT, p_class_section_id BIGINT) RETURNS JSONB
    LANGUAGE sql STABLE AS $$
    WITH sy AS (SELECT sy.* FROM learning.syllabus sy
                 WHERE sy.subject_id = p_subject_id
                   AND (p_class_section_id IS NULL OR sy.program_id IS NULL
                        OR sy.program_id = (SELECT cs.program_id FROM academics.class_section cs WHERE cs.class_section_id = p_class_section_id))
                 ORDER BY sy.academic_year_id DESC NULLS LAST LIMIT 1),
         u AS (SELECT u.*, (SELECT count(*) FROM learning.lesson_plan lp WHERE lp.unit_id = u.unit_id AND lp.status IN ('DELIVERED', 'PARTIAL')
                              AND (p_class_section_id IS NULL OR lp.class_section_id = p_class_section_id)) AS delivered
                 FROM learning.syllabus_unit u, sy WHERE u.syllabus_id = sy.syllabus_id)
    SELECT jsonb_build_object('syllabusId', sy.syllabus_id,
        'subject', (SELECT subject_name FROM academics.subject WHERE subject_id = sy.subject_id),
        'coveragePct', (SELECT round(100.0 * count(*) FILTER (WHERE delivered > 0) / nullif(count(*), 0), 1) FROM u),
        'units', coalesce((SELECT jsonb_agg(jsonb_build_object('unitId', p.unit_id, 'title', p.title, 'sequence', p.sequence,
                     'plannedPeriods', p.planned_periods,
                     'deliveredPeriods', p.delivered + coalesce((SELECT sum(c.delivered) FROM u c WHERE c.parent_unit_id = p.unit_id), 0),
                     'children', coalesce((SELECT jsonb_agg(jsonb_build_object('unitId', c.unit_id, 'title', c.title, 'sequence', c.sequence,
                                     'plannedPeriods', c.planned_periods, 'deliveredPeriods', c.delivered, 'children', '[]'::jsonb)
                                   ORDER BY c.sequence, c.unit_id) FROM u c WHERE c.parent_unit_id = p.unit_id), '[]'::jsonb))
                   ORDER BY p.sequence, p.unit_id) FROM u p WHERE p.parent_unit_id IS NULL), '[]'::jsonb))
    FROM sy
$$;

-- RollCallSheet: entries with room, prefill flag (status other than PRESENT came from outings / sick bay), escalations
CREATE OR REPLACE FUNCTION api.roll_call_sheet(p_roll_call_id BIGINT) RETURNS JSONB
    LANGUAGE sql STABLE AS $$
    SELECT jsonb_strip_nulls(jsonb_build_object('rollCallId', rc.roll_call_id, 'session', rc.session, 'rollDate', rc.roll_date, 'status', rc.status,
        'rows', coalesce((SELECT jsonb_agg(jsonb_strip_nulls(jsonb_build_object('entryId', e.entry_id, 'student', api.student_ref(e.student_id),
                     'room', (SELECT r.room_number FROM hostel.allocation a JOIN hostel.room r ON r.room_id = a.room_id
                               WHERE a.student_id = e.student_id AND a.status = 'ACTIVE' LIMIT 1),
                     'status', e.status, 'prefilled', e.status IN ('ON_OUTING', 'ON_LEAVE', 'SICK_BAY'),
                     'custodyPending', coalesce(e.custody_pending, false), 'note', e.note))
                   ORDER BY api.student_ref(e.student_id) ->> 'name') FROM hostel.roll_call_entry e WHERE e.roll_call_id = rc.roll_call_id), '[]'::jsonb),
        'escalations', coalesce((SELECT jsonb_agg(jsonb_strip_nulls(jsonb_build_object('notificationId', n.notification_id, 'title', n.title, 'body', n.body,
                     'raisedAt', n.sent_time)) ORDER BY n.sent_time DESC)
                   FROM communication.notification n WHERE n.category = 'HOSTEL' AND n.severity = 'CRITICAL' AND n.sent_time::date = rc.roll_date), '[]'::jsonb)))
    FROM hostel.roll_call rc WHERE rc.roll_call_id = p_roll_call_id
$$;

GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA api TO schoolcrm_app;
