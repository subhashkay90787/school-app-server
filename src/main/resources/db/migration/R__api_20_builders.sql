-- Response builders shared by several actors' screen queries (parent, student, assistant, teacher, hostel staff).
-- Repeatable migration (CREATE OR REPLACE); SECURITY INVOKER so row-level security applies.

-- TimetableGrid for a section: the published timetable version (or rows without a version)
CREATE OR REPLACE FUNCTION api.timetable_grid(p_class_section_id BIGINT) RETURNS JSONB
    LANGUAGE sql STABLE AS $$
    WITH v AS (SELECT tv.timetable_version_id FROM academics.timetable_version tv
                WHERE tv.status = 'PUBLISHED' ORDER BY tv.generated_at DESC NULLS LAST, tv.timetable_version_id DESC LIMIT 1),
         t AS (SELECT tt.*, csp.period_id, p.period_time FROM academics.timetable tt
                 JOIN academics.class_section_period csp ON csp.class_section_period_id = tt.class_section_period_id
                 JOIN academics.period p ON p.period_id = csp.period_id
                WHERE csp.class_section_id = p_class_section_id
                  AND (tt.timetable_version_id IS NULL OR tt.timetable_version_id = (SELECT timetable_version_id FROM v)))
    SELECT jsonb_strip_nulls(jsonb_build_object(
        'classSectionId', p_class_section_id, 'versionId', (SELECT timetable_version_id FROM v),
        'periods', coalesce((SELECT jsonb_agg(p.period_time ORDER BY api.period_start(p.period_time), p.period_id)
                               FROM academics.period p JOIN academics.class_section_period csp ON csp.period_id = p.period_id
                              WHERE csp.class_section_id = p_class_section_id), '[]'::jsonb),
        'cells', coalesce((SELECT jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
                     'day', t.day_of_week, 'periodId', t.period_id, 'timetableId', t.timetable_id,
                     'subject', coalesce(sub.subject_name, osub.subject_name), 'teacher', api.user_name(coalesce(ss.user_id, oss.user_id)),
                     'room', loc.room_name))
                   ORDER BY array_position(ARRAY['MON','TUE','WED','THU','FRI','SAT','SUN'], t.day_of_week), api.period_start(t.period_time))
                 FROM t
                 LEFT JOIN academics.staff_subject ss ON ss.staff_subject_id = t.staff_subject_id
                 LEFT JOIN academics.subject sub ON sub.subject_id = ss.subject_id
                 LEFT JOIN academics.course_offering co ON co.offering_id = t.offering_id
                 LEFT JOIN academics.subject osub ON osub.subject_id = co.subject_id
                 LEFT JOIN academics.staff_subject oss ON oss.staff_subject_id = co.staff_subject_id
                 LEFT JOIN inventory.location loc ON loc.location_id = t.room_location_id), '[]'::jsonb)))
$$;

-- AttendanceCalendar for a student and month (YYYY-MM; current month when NULL)
CREATE OR REPLACE FUNCTION api.attendance_calendar(p_student_id BIGINT, p_month TEXT) RETURNS JSONB
    LANGUAGE sql STABLE AS $$
    WITH m AS (SELECT coalesce(to_date(p_month || '-01', 'YYYY-MM-DD'), date_trunc('month', current_date)::date) AS s),
         d AS (SELECT dp.presence_date AS day, dp.status, dp.first_in_at FROM operations.daily_presence dp, m
                WHERE dp.person_kind = 'STUDENT' AND dp.person_id = p_student_id
                  AND dp.presence_date >= m.s AND dp.presence_date < (m.s + interval '1 month'))
    SELECT jsonb_build_object(
        'studentId', p_student_id, 'month', to_char((SELECT s FROM m), 'YYYY-MM'),
        'days', coalesce((SELECT jsonb_agg(jsonb_strip_nulls(jsonb_build_object('date', d.day, 'status', d.status, 'arrivedAt', d.first_in_at,
                    'note', (SELECT string_agg(DISTINCT coalesce(a.absence_reason, 'ABSENT'), ', ') FROM operations.student_absence a
                              WHERE a.student_id = p_student_id AND a.date = d.day))) ORDER BY d.day) FROM d), '[]'::jsonb),
        'presentPct', (SELECT round(100.0 * count(*) FILTER (WHERE status IN ('PRESENT', 'LATE', 'ON_DUTY'))
                                   / nullif(count(*) FILTER (WHERE status NOT IN ('HOLIDAY', 'WEEKLY_OFF')), 0), 1) FROM d))
$$;

-- HomeworkView rows for a student (assigned on/after p_from; last 30 days when NULL), newest first
CREATE OR REPLACE FUNCTION api.homework_views(p_student_id BIGINT, p_from DATE) RETURNS JSONB
    LANGUAGE sql STABLE AS $$
    SELECT coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
        'homeworkId', h.homework_id, 'subject', sub.subject_name, 'title', h.title, 'description', h.description,
        'assignedDate', h.assigned_date, 'dueDate', h.due_date, 'attachmentUrls', to_jsonb(h.attachment_urls),
        'submissionMode', h.submission_mode,
        'submissionStatus', coalesce(hs.status, CASE WHEN hx.exception_id IS NOT NULL THEN 'EXCUSED'
                                                     WHEN h.submission_mode = 'NONE' THEN NULL
                                                     WHEN h.due_date < current_date THEN 'OVERDUE' ELSE 'PENDING' END),
        'marks', hs.marks, 'feedback', hs.feedback)) ORDER BY h.assigned_date DESC, h.homework_id DESC), '[]'::jsonb)
    FROM academics.student s
    JOIN operations.homework h ON h.class_section_id = s.class_section_id
    LEFT JOIN academics.staff_subject ss ON ss.staff_subject_id = h.staff_subject_id
    LEFT JOIN academics.subject sub ON sub.subject_id = ss.subject_id
    LEFT JOIN operations.homework_submission hs ON hs.homework_id = h.homework_id AND hs.student_id = s.student_id
    LEFT JOIN operations.homework_exception hx ON hx.homework_id = h.homework_id AND hx.student_id = s.student_id
    WHERE s.student_id = p_student_id AND h.assigned_date >= coalesce(p_from, current_date - 30)
$$;

-- Grade for a percentage on the program's (or the first) grade scale
CREATE OR REPLACE FUNCTION api.grade_for(p_student_id BIGINT, p_pct NUMERIC) RETURNS TEXT
    LANGUAGE sql STABLE AS $$
    SELECT g.grade_name FROM assessment.grade g
     WHERE g.grade_scale_id = coalesce(
             (SELECT gs.grade_scale_id FROM assessment.grade_scale gs JOIN academics.class_section cs ON cs.program_id = gs.program_id
                JOIN academics.student s ON s.class_section_id = cs.class_section_id WHERE s.student_id = p_student_id LIMIT 1),
             (SELECT min(grade_scale_id) FROM assessment.grade_scale))
       AND p_pct >= coalesce(g.min_score, 0) AND p_pct <= coalesce(g.max_score, 100)
     ORDER BY g.min_score DESC NULLS LAST LIMIT 1
$$;

-- ExamResult rows (published exams only), newest first
CREATE OR REPLACE FUNCTION api.exam_results(p_student_id BIGINT) RETURNS JSONB
    LANGUAGE sql STABLE AS $$
    SELECT coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
        'examId', e.exam_id, 'examName', e.exam_name, 'subject', sub.subject_name, 'maxMarks', e.max_marks,
        'markObtained', m.mark_obtained, 'absent', coalesce(m.is_absent, false),
        'grade', coalesce(g.grade_name, CASE WHEN m.mark_obtained IS NOT NULL AND e.max_marks > 0
                                             THEN api.grade_for(p_student_id, 100.0 * m.mark_obtained::numeric / e.max_marks) END)))
        ORDER BY e.exam_date DESC NULLS LAST, e.exam_id DESC), '[]'::jsonb)
    FROM assessment.marks m
    JOIN assessment.exams e ON e.exam_id = m.exam_id AND e.status = 'PUBLISHED'
    LEFT JOIN academics.staff_subject ss ON ss.staff_subject_id = e.staff_subject_id
    LEFT JOIN academics.course_offering co ON co.offering_id = e.offering_id
    LEFT JOIN academics.subject sub ON sub.subject_id = coalesce(ss.subject_id, co.subject_id)
    LEFT JOIN assessment.grade g ON g.grade_id = m.grade_id
    WHERE m.student_id = p_student_id
$$;

-- Overdue amount for a student
CREATE OR REPLACE FUNCTION api.overdue(p_student_id BIGINT) RETURNS NUMERIC
    LANGUAGE sql STABLE AS $$
    SELECT coalesce(sum(f.remaining_due), 0) FROM finance.fee f
     WHERE f.student_id = p_student_id AND f.status IN ('DUE', 'PART_PAID') AND f.due_date < current_date
$$;

-- ReportCardStatus rows: published cards are held while fees are overdue
CREATE OR REPLACE FUNCTION api.report_card_statuses(p_student_id BIGINT) RETURNS JSONB
    LANGUAGE sql STABLE AS $$
    SELECT coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
        'reportCardId', rc.report_card_id, 'term', t.name,
        'status', CASE WHEN rc.status = 'WITHHELD' THEN 'WITHHELD'
                       WHEN rc.status = 'PUBLISHED' AND api.overdue(p_student_id) > 0 THEN 'DUES_HOLD'
                       WHEN rc.status = 'PUBLISHED' THEN 'READY' ELSE 'NOT_PUBLISHED' END,
        'message', CASE WHEN rc.status = 'WITHHELD' THEN coalesce(rc.withheld_reason, 'Withheld by the school')
                        WHEN rc.status = 'PUBLISHED' AND api.overdue(p_student_id) > 0 THEN 'Available once overdue fees are cleared'
                        WHEN rc.status <> 'PUBLISHED' THEN 'Not published yet' END,
        'publishedAt', rc.published_at)) ORDER BY t.sequence DESC NULLS LAST, rc.report_card_id DESC), '[]'::jsonb)
    FROM assessment.report_card rc JOIN academics.academic_term t ON t.term_id = rc.term_id
    WHERE rc.student_id = p_student_id
$$;

-- FamilyDues for a set of students: open lines oldest first, totals and wallet balances
CREATE OR REPLACE FUNCTION api.family_dues(p_students BIGINT[]) RETURNS JSONB
    LANGUAGE sql STABLE AS $$
    WITH f AS (SELECT f.*, h.name AS head FROM finance.fee f LEFT JOIN finance.fee_head h ON h.fee_head_id = f.fee_head_id
                WHERE f.student_id = ANY (p_students) AND f.status IN ('DUE', 'PART_PAID'))
    SELECT jsonb_build_object(
        'students', coalesce((SELECT jsonb_agg(api.student_ref(s) ORDER BY s) FROM unnest(p_students) s), '[]'::jsonb),
        'lines', coalesce((SELECT jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
                     'feeId', f.fee_id, 'student', api.student_ref(f.student_id), 'head', coalesce(f.head, 'Fee'), 'dueDate', f.due_date,
                     'net', f.net_amount, 'paid', coalesce(f.paid_amount, 0), 'remaining', f.remaining_due, 'fine', coalesce(f.fine_amount, 0),
                     'status', CASE WHEN f.due_date < current_date THEN 'OVERDUE' ELSE f.status END)) ORDER BY f.due_date NULLS LAST, f.fee_id)
                   FROM f), '[]'::jsonb),
        'totalDue', coalesce((SELECT sum(remaining_due) FROM f), 0),
        'overdue', coalesce((SELECT sum(remaining_due) FROM f WHERE due_date < current_date), 0),
        'walletBalances', coalesce((SELECT jsonb_object_agg(w.student_id::text, w.balance) FROM finance.student_wallet w
                                     WHERE w.student_id = ANY (p_students)), '{}'::jsonb))
$$;

-- HostelCard for a hosteller; NULL for day scholars
CREATE OR REPLACE FUNCTION api.hostel_card(p_student_id BIGINT) RETURNS JSONB
    LANGUAGE sql STABLE AS $$
    SELECT jsonb_strip_nulls(jsonb_build_object(
        'studentId', p_student_id, 'hostel', h.name, 'room', r.room_number, 'bed', b.bed_label,
        'status', api.hostel_status(p_student_id),
        'expectedBackAt', (SELECT o.return_planned_at FROM hostel.outing_request o WHERE o.student_id = p_student_id
                             AND o.status IN ('OUT', 'OVERDUE') ORDER BY o.depart_planned_at DESC LIMIT 1),
        'lastRollCall', (SELECT coalesce(rc.submitted_at, rc.started_at) FROM hostel.roll_call_entry e JOIN hostel.roll_call rc ON rc.roll_call_id = e.roll_call_id
                           WHERE e.student_id = p_student_id AND rc.status <> 'OPEN' ORDER BY rc.roll_date DESC, rc.submitted_at DESC NULLS LAST LIMIT 1),
        'phoneCustody', (SELECT i.status FROM custody.item i WHERE i.student_id = p_student_id AND i.item_type = 'MOBILE_PHONE'
                           AND i.status <> 'CLOSED' ORDER BY i.item_id DESC LIMIT 1),
        'walletBalance', (SELECT w.balance FROM finance.student_wallet w WHERE w.student_id = p_student_id LIMIT 1),
        'todayMenu', (SELECT jsonb_agg(api.camel(to_jsonb(mm)) ORDER BY array_position(ARRAY['BREAKFAST','LUNCH','SNACKS','DINNER'], mm.meal))
                        FROM hostel.mess_menu mm
                       WHERE mm.mess_id = (SELECT ms.mess_id FROM hostel.mess_subscription sub JOIN hostel.mess_plan ms ON ms.plan_id = sub.plan_id
                                             WHERE sub.student_id = p_student_id AND sub.status = 'ACTIVE' LIMIT 1)
                         AND (mm.menu_date = current_date OR (mm.menu_date IS NULL AND mm.day_of_week = api.dow(current_date))))))
    FROM hostel.allocation a
    JOIN hostel.hostel h ON h.hostel_id = a.hostel_id
    JOIN hostel.room r ON r.room_id = a.room_id
    JOIN hostel.bed b ON b.bed_id = a.bed_id
    WHERE a.student_id = p_student_id AND a.status = 'ACTIVE'
    ORDER BY a.check_in_date DESC LIMIT 1
$$;

-- OutingView: the request, policy checks, approval / movement timeline, gate pass token once approved
CREATE OR REPLACE FUNCTION api.outing_view(p_outing_id BIGINT) RETURNS JSONB
    LANGUAGE sql STABLE AS $$
    SELECT jsonb_strip_nulls(jsonb_build_object(
        'outing', api.camel(to_jsonb(o)), 'student', api.student_ref(o.student_id),
        'policyChecks', jsonb_build_array(
            jsonb_build_object('code', 'POLICY', 'label', 'Outing type allowed', 'passed', o.policy_id IS NOT NULL),
            jsonb_build_object('code', 'MONTHLY_LIMIT', 'label', 'Within monthly limit',
                'passed', pol.max_per_month IS NULL OR (SELECT count(*) FROM hostel.outing_request x WHERE x.student_id = o.student_id
                    AND x.outing_type = o.outing_type AND x.status NOT IN ('REJECTED', 'CANCELLED')
                    AND date_trunc('month', x.depart_planned_at) = date_trunc('month', o.depart_planned_at)) <= pol.max_per_month),
            jsonb_build_object('code', 'DURATION', 'label', 'Within allowed hours',
                'passed', pol.max_hours IS NULL OR o.return_planned_at - o.depart_planned_at <= make_interval(hours => pol.max_hours)),
            jsonb_build_object('code', 'PICKUP', 'label', 'Pickup person named',
                'passed', NOT coalesce(pol.requires_pickup_person, false) OR o.pickup_person_id IS NOT NULL OR o.travel_mode IN ('PARENT_PICKUP'))),
        'timeline', jsonb_build_array(
            jsonb_strip_nulls(jsonb_build_object('step', 'REQUESTED', 'by', coalesce(api.user_name(o.requested_by_user_id), initcap(o.requested_by_kind)), 'done', true)),
            jsonb_strip_nulls(jsonb_build_object('step', 'PARENT_' || o.parent_status, 'at', o.parent_decided_at, 'by', api.user_name(o.parent_user_id),
                'done', o.parent_status IN ('APPROVED', 'DECLINED', 'NOT_REQUIRED'))),
            jsonb_strip_nulls(jsonb_build_object('step', 'WARDEN_' || o.warden_status, 'at', o.warden_decided_at, 'by', api.user_name(o.warden_user_id),
                'done', o.warden_status <> 'PENDING')),
            jsonb_strip_nulls(jsonb_build_object('step', 'OUT', 'at', (SELECT min(mv.moved_at) FROM hostel.outing_movement mv WHERE mv.outing_id = o.outing_id AND mv.direction = 'OUT'),
                'done', EXISTS (SELECT 1 FROM hostel.outing_movement mv WHERE mv.outing_id = o.outing_id AND mv.direction = 'OUT'))),
            jsonb_strip_nulls(jsonb_build_object('step', 'BACK', 'at', (SELECT max(mv.moved_at) FROM hostel.outing_movement mv WHERE mv.outing_id = o.outing_id AND mv.direction = 'IN'),
                'done', EXISTS (SELECT 1 FROM hostel.outing_movement mv WHERE mv.outing_id = o.outing_id AND mv.direction = 'IN')))),
        'gatePassQr', CASE WHEN o.status IN ('APPROVED', 'OUT', 'OVERDUE') THEN o.gate_pass_token END))
    FROM hostel.outing_request o LEFT JOIN hostel.outing_policy pol ON pol.policy_id = o.policy_id
    WHERE o.outing_id = p_outing_id
$$;

-- CustodyItemView rows for a student (open items)
CREATE OR REPLACE FUNCTION api.custody_items(p_student_id BIGINT) RETURNS JSONB
    LANGUAGE sql STABLE AS $$
    SELECT coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
        'itemId', i.item_id, 'itemType', i.item_type,
        'description', concat_ws(' ', i.brand, i.model, CASE WHEN i.colour IS NOT NULL THEN '(' || i.colour || ')' END),
        'status', i.status, 'unit', u.code,
        'since', (SELECT max(e.occurred_at) FROM custody.event e WHERE e.item_id = i.item_id),
        'dueBackAt', i.due_back_at)) ORDER BY i.item_type, i.item_id), '[]'::jsonb)
    FROM custody.item i LEFT JOIN custody.storage_unit u ON u.unit_id = i.storage_unit_id
    WHERE i.student_id = p_student_id AND i.status <> 'CLOSED'
$$;

-- BusStatus: today's running (else latest) trip on the student's route; NULL when not on transport
CREATE OR REPLACE FUNCTION api.bus_status(p_student_id BIGINT) RETURNS JSONB
    LANGUAGE sql STABLE AS $$
    WITH sr AS (SELECT * FROM transport.student_route WHERE student_id = p_student_id AND status = 'ACTIVE' LIMIT 1),
         t AS (SELECT tr.* FROM transport.trip tr, sr WHERE tr.route_id = sr.route_id AND tr.trip_date = current_date
                ORDER BY (tr.status = 'RUNNING') DESC, tr.started_at DESC NULLS LAST, tr.trip_id DESC LIMIT 1),
         loc AS (SELECT l.* FROM transport.trip_location l, t WHERE l.trip_id = t.trip_id ORDER BY l.recorded_at DESC LIMIT 1),
         stop AS (SELECT s.* FROM transport.stop s, sr, t WHERE s.stop_id = CASE WHEN t.direction = 'DROP' THEN sr.drop_stop_id ELSE sr.pickup_stop_id END)
    SELECT jsonb_strip_nulls(jsonb_build_object(
        'tripId', t.trip_id, 'route', r.name, 'status', t.status, 'lat', loc.lat, 'lng', loc.lng,
        'etaMinutes', CASE WHEN t.status = 'RUNNING' AND stop.stop_id IS NOT NULL THEN greatest(0,
                          extract(epoch FROM ((current_date + CASE WHEN t.direction = 'DROP' THEN stop.drop_time ELSE stop.pickup_time END)::timestamp
                                              - localtimestamp)) / 60)::int END,
        'boardedAt', (SELECT max(b.event_at) FROM transport.boarding b WHERE b.trip_id = t.trip_id AND b.student_id = p_student_id AND b.event = 'BOARDED'),
        'alightedAt', (SELECT max(b.event_at) FROM transport.boarding b WHERE b.trip_id = t.trip_id AND b.student_id = p_student_id AND b.event = 'ALIGHTED')))
    FROM sr JOIN transport.route r ON r.route_id = sr.route_id
    LEFT JOIN t ON true LEFT JOIN loc ON true LEFT JOIN stop ON true
$$;

-- Alerts shown on a student card: medical, safety, fees
CREATE OR REPLACE FUNCTION api.student_alerts(p_student_id BIGINT) RETURNS JSONB
    LANGUAGE sql STABLE AS $$
    SELECT coalesce(jsonb_agg(a), '[]'::jsonb) FROM (
        SELECT 'Allergy: ' || mp.allergies AS a FROM wellbeing.medical_profile mp WHERE mp.student_id = p_student_id AND coalesce(mp.allergies, '') <> ''
        UNION ALL SELECT 'Condition: ' || mp.conditions FROM wellbeing.medical_profile mp WHERE mp.student_id = p_student_id AND coalesce(mp.conditions, '') <> ''
        UNION ALL SELECT CASE api.hostel_status(p_student_id) WHEN 'MISSING' THEN 'Not back from outing' WHEN 'SICK_BAY' THEN 'In sick bay' END
                   WHERE api.hostel_status(p_student_id) IN ('MISSING', 'SICK_BAY')
        UNION ALL SELECT 'Fees overdue' WHERE api.overdue(p_student_id) > 0
    ) x
$$;

-- StudentCard
CREATE OR REPLACE FUNCTION api.student_card(p_student_id BIGINT) RETURNS JSONB
    LANGUAGE sql STABLE AS $$
    SELECT jsonb_strip_nulls(jsonb_build_object(
        'studentId', s.student_id, 'name', btrim(s.first_name || ' ' || coalesce(s.last_name, '')),
        'rollNo', s.student_admission_number, 'photoUrl', s.photo_url, 'classSection', api.section_label(s.class_section_id),
        'residency', s.residency_type, 'alerts', api.student_alerts(s.student_id), 'duesHold', api.overdue(s.student_id) > 0,
        'parents', coalesce((SELECT jsonb_agg(api.person(sp.user_id, sp.relationship_type) ORDER BY sp.is_primary_contact DESC NULLS LAST, sp.user_id)
                               FROM academics.student_parent sp WHERE sp.student_id = s.student_id), '[]'::jsonb)))
    FROM academics.student s WHERE s.student_id = p_student_id
$$;

-- WalletStatement (last 50 transactions)
CREATE OR REPLACE FUNCTION api.wallet_statement(p_student_id BIGINT) RETURNS JSONB
    LANGUAGE sql STABLE AS $$
    SELECT jsonb_build_object('wallet', api.camel(to_jsonb(w)),
        'transactions', coalesce((SELECT jsonb_agg(api.camel(to_jsonb(t)) ORDER BY t.txn_at DESC)
                                    FROM (SELECT * FROM finance.wallet_txn x WHERE x.wallet_id = w.wallet_id ORDER BY x.txn_at DESC LIMIT 50) t), '[]'::jsonb))
    FROM finance.student_wallet w WHERE w.student_id = p_student_id
$$;

-- SubjectAttendance for a student this term: periods held (timetable slots on school days so far) vs attended
CREATE OR REPLACE FUNCTION api.subject_attendance(p_student_id BIGINT) RETURNS JSONB
    LANGUAGE sql STABLE AS $$
    WITH s AS (SELECT * FROM academics.student WHERE student_id = p_student_id),
         term AS (SELECT t.* FROM academics.academic_term t WHERE t.start_date <= current_date AND coalesce(t.end_date, current_date) >= current_date
                   ORDER BY t.start_date DESC LIMIT 1),
         days AS (SELECT d::date AS d FROM term, generate_series(coalesce(term.start_date, current_date - 30), current_date, interval '1 day') d
                   WHERE NOT EXISTS (SELECT 1 FROM calendar.event e WHERE coalesce(e.is_holiday, false) AND d::date BETWEEN e.start_date AND coalesce(e.end_date, e.start_date))),
         slots AS (SELECT days.d, tt.class_section_period_id, coalesce(ss.subject_id, co.subject_id) AS subject_id
                     FROM s JOIN academics.class_section_period csp ON csp.class_section_id = s.class_section_id
                     JOIN academics.timetable tt ON tt.class_section_period_id = csp.class_section_period_id
                     LEFT JOIN academics.staff_subject ss ON ss.staff_subject_id = tt.staff_subject_id
                     LEFT JOIN academics.course_offering co ON co.offering_id = tt.offering_id
                     JOIN days ON api.dow(days.d) = tt.day_of_week),
         held AS (SELECT sl.subject_id, count(*) AS held,
                         count(*) FILTER (WHERE EXISTS (SELECT 1 FROM operations.student_absence a WHERE a.student_id = p_student_id AND a.date = sl.d
                                                          AND (a.class_section_period_id IS NULL OR a.class_section_period_id = sl.class_section_period_id))
                                             OR EXISTS (SELECT 1 FROM operations.daily_presence dp WHERE dp.person_kind = 'STUDENT' AND dp.person_id = p_student_id
                                                          AND dp.presence_date = sl.d AND dp.status = 'ABSENT')) AS missed
                    FROM slots sl GROUP BY sl.subject_id)
    SELECT coalesce(jsonb_agg(jsonb_build_object(
        'subject', sub.subject_name, 'held', held.held, 'attended', held.held - held.missed,
        'pct', round(100.0 * (held.held - held.missed) / nullif(held.held, 0), 1), 'minimumPct', 75,
        'canMiss', greatest(0, floor((held.held - held.missed) / 0.75 - held.held))::int,
        'shortfall', (held.held - held.missed) < 0.75 * held.held) ORDER BY sub.subject_name), '[]'::jsonb)
    FROM held JOIN academics.subject sub ON sub.subject_id = held.subject_id
$$;

GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA api TO schoolcrm_app;
