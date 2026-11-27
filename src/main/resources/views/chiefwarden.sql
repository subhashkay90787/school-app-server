-- Screen queries for /api/v1/chief-warden. Hostels in the path are checked against the caller's assignments.

-- name: getHome
WITH h AS (SELECT api.my_hostels() AS id)
SELECT api.feed('CHIEF_WARDEN',
    (SELECT api.card('missing', 'CRITICAL', 'OUTING_OVERDUE', 'Students not back', string_agg(api.student_ref(o.student_id) ->> 'name', ', '), count(*), 'CRITICAL', 'outings?status=OVERDUE')
       FROM hostel.outing_request o WHERE o.status = 'OVERDUE' AND o.hostel_id IN (SELECT id FROM h)),
    (SELECT api.card('roll-absent', 'CRITICAL', 'ROLL_ABSENT', 'Absent at roll call without a pass', NULL, count(*), 'CRITICAL', 'roll-calls')
       FROM hostel.roll_call_entry e JOIN hostel.roll_call rc ON rc.roll_call_id = e.roll_call_id
      WHERE rc.roll_date = current_date AND rc.hostel_id IN (SELECT id FROM h) AND e.status = 'ABSENT'),
    (SELECT api.card('outing-approvals', 'NEEDS_YOU', 'OUTING_APPROVAL', 'Outings waiting for warden approval', NULL, count(*), 'ACTION', 'outings?status=REQUESTED')
       FROM hostel.outing_request o WHERE o.status = 'REQUESTED' AND o.warden_status = 'PENDING' AND o.parent_status IN ('APPROVED', 'NOT_REQUIRED')
        AND o.hostel_id IN (SELECT id FROM h)),
    (SELECT api.card('allocation', 'NEEDS_YOU', 'ALLOCATION_REQUESTS', 'Room requests', NULL, count(*), 'ACTION', 'allocation-requests')
       FROM hostel.allocation_request r WHERE r.status IN ('REQUESTED', 'WAITLISTED') AND (r.preferred_hostel_id IS NULL OR r.preferred_hostel_id IN (SELECT id FROM h))),
    (SELECT api.card('incidents', 'NEEDS_YOU', 'INCIDENTS', 'Open hostel incidents', string_agg(DISTINCT i.category, ', '), count(*), 'ACTION', 'incidents')
       FROM discipline.incident i WHERE i.status IN ('REPORTED', 'UNDER_REVIEW') AND i.hostel_id IN (SELECT id FROM h)),
    (SELECT api.card('out-now', 'NOW', 'ON_OUTING', 'Out on pass now', NULL, count(*), 'INFO', 'outings?status=OUT')
       FROM hostel.outing_request o WHERE o.status = 'OUT' AND o.hostel_id IN (SELECT id FROM h)),
    (SELECT api.card('sick-bay', 'NOW', 'SICK_BAY', 'In sick bay', NULL, count(*), 'INFO', 'sick-bay')
       FROM wellbeing.infirmary_visit v JOIN hostel.allocation a ON a.student_id = v.person_id AND a.status = 'ACTIVE'
      WHERE v.person_kind = 'STUDENT' AND v.disposition = 'SICK_BAY' AND v.discharged_at IS NULL AND a.hostel_id IN (SELECT id FROM h)),
    (SELECT api.card('groups', 'TODAY', 'TRAVEL_GROUPS', 'Travel groups leaving soon', string_agg(g.title, ', '), count(*), 'INFO', 'travel-groups')
       FROM hostel.outing_group g WHERE g.status = 'PLANNED' AND g.hostel_id IN (SELECT id FROM h) AND g.campus_departure_at < now() + interval '3 days'));

-- name: getHostelNow
WITH hs AS (SELECT * FROM hostel.hostel WHERE hostel_id = :hostelId::bigint AND hostel_id IN (SELECT api.my_hostels())),
     res AS (SELECT a.student_id, r.block_id FROM hostel.allocation a JOIN hostel.room r ON r.room_id = a.room_id, hs
              WHERE a.hostel_id = hs.hostel_id AND a.status = 'ACTIVE'),
     last_rc AS (SELECT DISTINCT ON (rc.hostel_id) rc.* FROM hostel.roll_call rc, hs WHERE rc.hostel_id = hs.hostel_id AND rc.roll_date = current_date
                  ORDER BY rc.hostel_id, rc.started_at DESC NULLS LAST, rc.roll_call_id DESC)
SELECT jsonb_build_object('hostelId', hs.hostel_id, 'asOf', now(),
    'rollCall', coalesce((SELECT jsonb_agg(jsonb_build_object('blockId', b.block_id, 'block', b.name,
                    'expected', (SELECT count(*) FROM res WHERE res.block_id = b.block_id),
                    'present', (SELECT count(*) FROM hostel.roll_call_entry e, last_rc WHERE e.roll_call_id = last_rc.roll_call_id AND e.status = 'PRESENT'
                                  AND e.student_id IN (SELECT student_id FROM res WHERE res.block_id = b.block_id)),
                    'absentWithPass', (SELECT count(*) FROM hostel.roll_call_entry e, last_rc WHERE e.roll_call_id = last_rc.roll_call_id
                                         AND e.status IN ('ON_OUTING', 'ON_LEAVE', 'SICK_BAY', 'EXCUSED') AND e.student_id IN (SELECT student_id FROM res WHERE res.block_id = b.block_id)),
                    'absentNoPass', (SELECT count(*) FROM hostel.roll_call_entry e, last_rc WHERE e.roll_call_id = last_rc.roll_call_id AND e.status = 'ABSENT'
                                       AND e.student_id IN (SELECT student_id FROM res WHERE res.block_id = b.block_id)),
                    'submitted', coalesce((SELECT status <> 'OPEN' FROM last_rc), false)) ORDER BY b.name)
                   FROM hostel.block b WHERE b.hostel_id = hs.hostel_id), '[]'::jsonb),
    'onOuting', (SELECT count(*) FROM hostel.outing_request o WHERE o.hostel_id = hs.hostel_id AND o.status = 'OUT'),
    'overdue', coalesce((SELECT jsonb_agg(api.outing_view(o.outing_id) ORDER BY o.return_planned_at) FROM hostel.outing_request o
                          WHERE o.hostel_id = hs.hostel_id AND o.status = 'OVERDUE'), '[]'::jsonb),
    'sickBay', (SELECT count(*) FROM wellbeing.infirmary_visit v WHERE v.person_kind = 'STUDENT' AND v.disposition = 'SICK_BAY' AND v.discharged_at IS NULL
                  AND v.person_id IN (SELECT student_id FROM res)),
    'occupancy', (SELECT round(100.0 * count(*) FILTER (WHERE b.status = 'OCCUPIED') / nullif(count(*) FILTER (WHERE b.status <> 'MAINTENANCE'), 0), 1)
                    FROM hostel.bed b JOIN hostel.room r ON r.room_id = b.room_id WHERE r.hostel_id = hs.hostel_id),
    'phonesHeld', (SELECT count(*) FROM custody.item i WHERE i.item_type = 'MOBILE_PHONE' AND i.status = 'IN_CUSTODY' AND i.student_id IN (SELECT student_id FROM res)),
    'phonesPending', (SELECT count(*) FROM custody.item i WHERE i.item_type = 'MOBILE_PHONE' AND i.status IN ('RELEASED_TEMP', 'RELEASED_TRAVEL')
                        AND i.due_back_at < now() AND i.student_id IN (SELECT student_id FROM res)),
    'wardensOnDuty', coalesce((SELECT jsonb_agg(DISTINCT api.person(sa.user_id, sa.duty)) FROM hostel.staff_assignment sa
                                WHERE sa.hostel_id = hs.hostel_id AND sa.from_date <= current_date AND (sa.to_date IS NULL OR sa.to_date >= current_date)
                                  AND sa.duty IN ('BLOCK_WARDEN', 'FLOOR_WARDEN', 'ROOM_WARDEN', 'ASSISTANT_WARDEN', 'CHIEF_WARDEN')), '[]'::jsonb))
FROM hs;

-- name: getAllocationBoard
WITH hs AS (SELECT * FROM hostel.hostel WHERE hostel_id = :hostelId::bigint AND hostel_id IN (SELECT api.my_hostels())
              AND (:gender IS NULL OR gender = :gender OR gender = 'CO_ED'))
SELECT jsonb_strip_nulls(jsonb_build_object('hostelId', hs.hostel_id, 'floor', :floor::int,
    'rooms', coalesce((SELECT jsonb_agg(jsonb_strip_nulls(jsonb_build_object('roomId', r.room_id, 'roomNumber', r.room_number, 'floor', r.floor_number,
                     'roomType', r.room_type, 'isAc', coalesce(r.is_ac, false),
                     'beds', coalesce((SELECT jsonb_agg(jsonb_strip_nulls(jsonb_build_object('bedId', b.bed_id, 'label', b.bed_label, 'status', b.status,
                                         'student', api.student_ref(a.student_id), 'allocationId', a.allocation_id)) ORDER BY b.bed_label)
                                       FROM hostel.bed b LEFT JOIN hostel.allocation a ON a.bed_id = b.bed_id AND a.status = 'ACTIVE'
                                      WHERE b.room_id = r.room_id), '[]'::jsonb)))
                   ORDER BY r.floor_number, r.room_number)
                 FROM hostel.room r WHERE r.hostel_id = hs.hostel_id AND (:floor IS NULL OR r.floor_number = :floor::int)
                  AND (:roomType IS NULL OR r.room_type = :roomType)), '[]'::jsonb),
    'waitlist', coalesce((SELECT jsonb_agg(api.camel(to_jsonb(q)) ORDER BY q.request_id) FROM hostel.allocation_request q
                           WHERE q.status IN ('REQUESTED', 'WAITLISTED') AND (q.preferred_hostel_id IS NULL OR q.preferred_hostel_id = hs.hostel_id)), '[]'::jsonb)))
FROM hs;

-- name: vacate write
-- Ends the allocation and frees the bed (the check-out inspection is raised separately)
WITH b AS (SELECT :body::jsonb AS j),
     up AS (UPDATE hostel.allocation a SET status = 'VACATED', check_out_date = coalesce((b.j ->> 'checkOutDate')::date, current_date)
              FROM b WHERE a.allocation_id = :allocationId::bigint AND a.status = 'ACTIVE' AND a.hostel_id IN (SELECT api.my_hostels())
            RETURNING a.*),
     bed AS (UPDATE hostel.bed SET status = 'VACANT' WHERE bed_id = (SELECT bed_id FROM up) RETURNING 1),
     room AS (UPDATE hostel.room SET status = 'AVAILABLE' WHERE room_id = (SELECT room_id FROM up) AND status = 'FULL' RETURNING 1)
SELECT api.camel(to_jsonb(up)) FROM up WHERE (SELECT count(*) FROM bed) + (SELECT count(*) FROM room) >= 0;

-- name: transferBed write
-- Moves the student to a vacant bed in one of my hostels: old allocation TRANSFERRED, new one ACTIVE
WITH b AS (SELECT :body::jsonb AS j),
     cur AS (SELECT a.* FROM hostel.allocation a WHERE a.allocation_id = :allocationId::bigint AND a.status = 'ACTIVE' AND a.hostel_id IN (SELECT api.my_hostels())),
     tgt AS (SELECT bd.bed_id, r.room_id, r.hostel_id FROM hostel.bed bd JOIN hostel.room r ON r.room_id = bd.room_id, b
              WHERE bd.bed_id = (b.j ->> 'toBedId')::bigint AND bd.status = 'VACANT' AND r.hostel_id IN (SELECT api.my_hostels())),
     old AS (UPDATE hostel.allocation a SET status = 'TRANSFERRED', check_out_date = coalesce((b.j ->> 'date')::date, current_date)
              FROM b, tgt WHERE a.allocation_id = (SELECT allocation_id FROM cur) RETURNING a.bed_id),
     freed AS (UPDATE hostel.bed SET status = 'VACANT' WHERE bed_id = (SELECT bed_id FROM old) RETURNING 1),
     taken AS (UPDATE hostel.bed SET status = 'OCCUPIED' WHERE bed_id = (SELECT bed_id FROM tgt) AND EXISTS (SELECT 1 FROM old) RETURNING 1),
     ins AS (INSERT INTO hostel.allocation (school_id, student_id, bed_id, room_id, hostel_id, academic_year_id, fee_plan_id, check_in_date, status, allocated_by_user_id)
             SELECT cur.school_id, cur.student_id, tgt.bed_id, tgt.room_id, tgt.hostel_id, cur.academic_year_id, cur.fee_plan_id,
                    coalesce((b.j ->> 'date')::date, current_date), 'ACTIVE', :me::bigint
               FROM cur, tgt, b WHERE EXISTS (SELECT 1 FROM old) RETURNING *)
SELECT api.camel(to_jsonb(ins)) FROM ins WHERE (SELECT count(*) FROM freed) + (SELECT count(*) FROM taken) >= 0;

-- name: getTravelGroup
SELECT api.travel_group_board(g.group_id) FROM hostel.outing_group g WHERE g.group_id = :groupId::bigint AND g.hostel_id IN (SELECT api.my_hostels());

-- name: addStudentsToGroup write
-- Links the students' open weekend / vacation outings to the group (one outing per student is expected)
WITH g AS (SELECT * FROM hostel.outing_group WHERE group_id = :groupId::bigint AND hostel_id IN (SELECT api.my_hostels()) AND status = 'PLANNED'),
     ids AS (SELECT jsonb_array_elements_text(coalesce(:body::jsonb -> 'ids', '[]'::jsonb))::bigint AS sid),
     up AS (UPDATE hostel.outing_request o SET group_id = g.group_id, travel_departure_at = coalesce(o.travel_departure_at, g.carrier_departure_at)
              FROM g WHERE o.student_id IN (SELECT sid FROM ids) AND o.hostel_id = g.hostel_id AND o.status IN ('REQUESTED', 'APPROVED')
               AND o.outing_type IN ('WEEKEND_HOME', 'HOME_LEAVE', 'VACATION') RETURNING o.outing_id)
SELECT g.group_id AS result FROM g WHERE (SELECT count(*) FROM up) >= 0;
-- then
SELECT api.travel_group_board(:result::bigint);

-- name: assignWarden write
WITH b AS (SELECT :body::jsonb AS j),
     ins AS (INSERT INTO hostel.staff_assignment (school_id, hostel_id, user_id, duty, scope_type, block_id, floor_number, is_resident, from_date, to_date, assigned_by_user_id)
             SELECT h.school_id, h.hostel_id, (j ->> 'userId')::bigint, j ->> 'duty', coalesce(j ->> 'scopeType', 'HOSTEL'), (j ->> 'blockId')::bigint,
                    (j ->> 'floorNumber')::int, coalesce((j ->> 'isResident')::boolean, false), coalesce((j ->> 'fromDate')::date, current_date),
                    (j ->> 'toDate')::date, :me::bigint
               FROM hostel.hostel h, b WHERE h.hostel_id = :hostelId::bigint AND h.hostel_id IN (SELECT api.my_hostels())
             RETURNING *)
SELECT api.camel(to_jsonb(ins)) FROM ins;

-- name: listOutings
SELECT api.page(coalesce(jsonb_agg(api.outing_view(o.outing_id) ORDER BY (o.status = 'OVERDUE') DESC, o.depart_planned_at DESC), '[]'::jsonb), :page, :size)
FROM hostel.outing_request o
WHERE o.hostel_id IN (SELECT api.my_hostels()) AND (:status IS NULL OR o.status = :status)
  AND (:from IS NULL OR o.depart_planned_at >= :from::date);

-- name: getMonthlyReport
WITH hs AS (SELECT * FROM hostel.hostel WHERE hostel_id = :hostelId::bigint AND hostel_id IN (SELECT api.my_hostels())),
     m AS (SELECT coalesce(to_date(:month || '-01', 'YYYY-MM-DD'), date_trunc('month', current_date)::date) AS s)
SELECT jsonb_build_object('hostelId', hs.hostel_id, 'month', to_char(m.s, 'YYYY-MM'),
    'occupancy', (SELECT round(100.0 * count(*) FILTER (WHERE b.status = 'OCCUPIED') / nullif(count(*) FILTER (WHERE b.status <> 'MAINTENANCE'), 0), 1)
                    FROM hostel.bed b JOIN hostel.room r ON r.room_id = b.room_id WHERE r.hostel_id = hs.hostel_id),
    'outings', (SELECT count(*) FROM hostel.outing_request o WHERE o.hostel_id = hs.hostel_id AND o.depart_planned_at >= m.s AND o.depart_planned_at < m.s + interval '1 month'
                  AND o.status NOT IN ('REJECTED', 'CANCELLED')),
    'lateReturns', (SELECT count(*) FROM hostel.outing_request o WHERE o.hostel_id = hs.hostel_id AND coalesce(o.late_minutes, 0) > 0
                      AND o.depart_planned_at >= m.s AND o.depart_planned_at < m.s + interval '1 month'),
    'incidents', (SELECT count(*) FROM discipline.incident i WHERE i.hostel_id = hs.hostel_id AND i.occurred_at >= m.s AND i.occurred_at < m.s + interval '1 month'),
    'inspections', (SELECT count(*) FROM hostel.room_inspection ri JOIN hostel.room r ON r.room_id = ri.room_id
                     WHERE r.hostel_id = hs.hostel_id AND ri.inspected_at >= m.s AND ri.inspected_at < m.s + interval '1 month'),
    'avgHygiene', (SELECT round(avg(ri.hygiene_score), 1) FROM hostel.room_inspection ri JOIN hostel.room r ON r.room_id = ri.room_id
                    WHERE r.hostel_id = hs.hostel_id AND ri.inspected_at >= m.s AND ri.inspected_at < m.s + interval '1 month'),
    'messRating', (SELECT round(avg(f.rating), 1) FROM hostel.mess_feedback f JOIN hostel.mess ms ON ms.mess_id = f.mess_id
                    WHERE (ms.hostel_id = hs.hostel_id OR ms.hostel_id IS NULL) AND f.meal_date >= m.s AND f.meal_date < m.s + interval '1 month'))
FROM hs, m;

-- name: saveOutingPolicies write
-- One policy per outing type: existing types updated, new ones added (requests keep their policy row)
WITH h AS (SELECT * FROM hostel.hostel WHERE hostel_id = :hostelId::bigint AND hostel_id IN (SELECT api.my_hostels())),
     p AS (SELECT x FROM jsonb_array_elements(CASE WHEN jsonb_typeof(:body::jsonb) = 'array' THEN :body::jsonb ELSE '[]'::jsonb END) x),
     up AS (UPDATE hostel.outing_policy op SET min_level = x ->> 'minLevel', allowed_days = x ->> 'allowedDays', max_per_month = (x ->> 'maxPerMonth')::int,
                   max_hours = (x ->> 'maxHours')::int, requires_parent_approval = coalesce((x ->> 'requiresParentApproval')::boolean, true),
                   requires_pickup_person = coalesce((x ->> 'requiresPickupPerson')::boolean, false), approver_duty = x ->> 'approverDuty',
                   allow_phone_release = coalesce((x ->> 'allowPhoneRelease')::boolean, false), phone_release_at = x ->> 'phoneReleaseAt',
                   grace_minutes = (x ->> 'graceMinutes')::int
              FROM h, p WHERE op.hostel_id = h.hostel_id AND op.outing_type = p.x ->> 'outingType' RETURNING 1),
     ins AS (INSERT INTO hostel.outing_policy (school_id, hostel_id, outing_type, min_level, allowed_days, max_per_month, max_hours, requires_parent_approval,
                                               requires_pickup_person, approver_duty, allow_phone_release, phone_release_at, grace_minutes)
             SELECT h.school_id, h.hostel_id, x ->> 'outingType', x ->> 'minLevel', x ->> 'allowedDays', (x ->> 'maxPerMonth')::int, (x ->> 'maxHours')::int,
                    coalesce((x ->> 'requiresParentApproval')::boolean, true), coalesce((x ->> 'requiresPickupPerson')::boolean, false), x ->> 'approverDuty',
                    coalesce((x ->> 'allowPhoneRelease')::boolean, false), x ->> 'phoneReleaseAt', (x ->> 'graceMinutes')::int
               FROM h, p WHERE NOT EXISTS (SELECT 1 FROM hostel.outing_policy op WHERE op.hostel_id = h.hostel_id AND op.outing_type = p.x ->> 'outingType')
             RETURNING 1)
SELECT h.hostel_id AS result FROM h WHERE (SELECT count(*) FROM up) + (SELECT count(*) FROM ins) >= 0;
-- then
SELECT coalesce(jsonb_agg(api.camel(to_jsonb(op)) ORDER BY op.outing_type), '[]'::jsonb) FROM hostel.outing_policy op WHERE op.hostel_id = :result::bigint;

-- name: saveReleaseWindows write
-- Windows by (day, name): updated or added; windows not in the list are switched off (history keeps them)
WITH h AS (SELECT * FROM hostel.hostel WHERE hostel_id = :hostelId::bigint AND hostel_id IN (SELECT api.my_hostels())),
     w AS (SELECT x FROM jsonb_array_elements(CASE WHEN jsonb_typeof(:body::jsonb) = 'array' THEN :body::jsonb ELSE '[]'::jsonb END) x),
     off AS (UPDATE custody.release_window rw SET is_active = false FROM h
              WHERE rw.hostel_id = h.hostel_id AND (rw.day_of_week, rw.name) NOT IN (SELECT x ->> 'dayOfWeek', x ->> 'name' FROM w) RETURNING 1),
     up AS (UPDATE custody.release_window rw SET start_time = (x ->> 'startTime')::time, end_time = (x ->> 'endTime')::time, item_types = x ->> 'itemTypes',
                   min_level = x ->> 'minLevel', is_active = coalesce((x ->> 'isActive')::boolean, true)
              FROM h, w WHERE rw.hostel_id = h.hostel_id AND rw.day_of_week = w.x ->> 'dayOfWeek' AND rw.name = w.x ->> 'name' RETURNING 1),
     ins AS (INSERT INTO custody.release_window (school_id, hostel_id, name, day_of_week, start_time, end_time, item_types, min_level, is_active)
             SELECT h.school_id, h.hostel_id, x ->> 'name', x ->> 'dayOfWeek', (x ->> 'startTime')::time, (x ->> 'endTime')::time, x ->> 'itemTypes', x ->> 'minLevel',
                    coalesce((x ->> 'isActive')::boolean, true)
               FROM h, w WHERE NOT EXISTS (SELECT 1 FROM custody.release_window rw WHERE rw.hostel_id = h.hostel_id AND rw.day_of_week = w.x ->> 'dayOfWeek'
                                             AND rw.name = w.x ->> 'name')
             RETURNING 1)
SELECT h.hostel_id AS result FROM h WHERE (SELECT count(*) FROM off) + (SELECT count(*) FROM up) + (SELECT count(*) FROM ins) >= 0;
-- then
SELECT coalesce(jsonb_agg(api.camel(to_jsonb(rw)) ORDER BY array_position(ARRAY['MON','TUE','WED','THU','FRI','SAT','SUN'], rw.day_of_week), rw.start_time), '[]'::jsonb)
FROM custody.release_window rw WHERE rw.hostel_id = :result::bigint;

-- name: endAssignment write
-- Ends the duty today (history and roll calls keep the assignment)
WITH up AS (UPDATE hostel.staff_assignment SET to_date = least(coalesce(to_date, current_date), current_date)
             WHERE assignment_id = :assignmentId::bigint AND hostel_id IN (SELECT api.my_hostels()) RETURNING 1)
SELECT CASE WHEN EXISTS (SELECT 1 FROM up) THEN '{}' END;

-- name: allocateBed write
-- A vacant bed in one of my hostels for a student without an active allocation; the bed becomes OCCUPIED and
-- the room FULL when no vacant bed is left; a linked request is marked DONE
WITH b AS (SELECT :body::jsonb AS j),
     bed AS (SELECT bd.bed_id, r.room_id, r.hostel_id FROM hostel.bed bd JOIN hostel.room r ON r.room_id = bd.room_id, b
              WHERE bd.bed_id = (b.j ->> 'bedId')::bigint AND bd.status = 'VACANT' AND r.hostel_id IN (SELECT api.my_hostels())),
     st AS (SELECT s.* FROM academics.student s, b WHERE s.student_id = (b.j ->> 'studentId')::bigint AND s.status = 'ACTIVE'
              AND NOT EXISTS (SELECT 1 FROM hostel.allocation a WHERE a.student_id = s.student_id AND a.status = 'ACTIVE')),
     ins AS (INSERT INTO hostel.allocation (school_id, student_id, bed_id, room_id, hostel_id, academic_year_id, fee_plan_id, check_in_date, status,
                                            allocated_by_user_id, request_id)
             SELECT st.school_id, st.student_id, bed.bed_id, bed.room_id, bed.hostel_id,
                    (SELECT academic_year_id FROM academics.academic_year WHERE is_current LIMIT 1), (b.j ->> 'feePlanId')::bigint,
                    coalesce((b.j ->> 'checkInDate')::date, current_date), 'ACTIVE', :me::bigint, (b.j ->> 'requestId')::bigint
               FROM st, bed, b RETURNING *),
     bd AS (UPDATE hostel.bed SET status = 'OCCUPIED' WHERE bed_id = (SELECT bed_id FROM ins) RETURNING room_id),
     rm AS (UPDATE hostel.room r SET status = 'FULL' WHERE r.room_id = (SELECT room_id FROM bd)
              AND NOT EXISTS (SELECT 1 FROM hostel.bed x WHERE x.room_id = r.room_id AND x.status = 'VACANT' AND x.bed_id <> (SELECT bed_id FROM ins)) RETURNING 1),
     rq AS (UPDATE hostel.allocation_request SET status = 'DONE', decided_by_user_id = :me::bigint
             WHERE request_id = (SELECT request_id FROM ins) RETURNING 1),
     res AS (UPDATE academics.student SET residency_type = 'HOSTELLER' WHERE student_id = (SELECT student_id FROM ins) RETURNING 1)
SELECT api.camel(to_jsonb(ins)) FROM ins WHERE (SELECT count(*) FROM rm) + (SELECT count(*) FROM rq) + (SELECT count(*) FROM res) >= 0;
