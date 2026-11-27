-- Screen queries for /api/v1/warden: residents of the hostels (blocks) the caller is assigned to.

-- name: getHome
WITH h AS (SELECT api.my_hostels() AS id),
     open_rc AS (SELECT rc.* FROM hostel.roll_call rc WHERE rc.hostel_id IN (SELECT id FROM h) AND rc.roll_date = current_date AND rc.status = 'OPEN')
SELECT api.feed('WARDEN',
    (SELECT api.card('missing', 'CRITICAL', 'OUTING_OVERDUE', 'Not back from outing', string_agg(api.student_ref(o.student_id) ->> 'name', ', '), count(*), 'CRITICAL', 'outings?status=OVERDUE')
       FROM hostel.outing_request o WHERE o.status = 'OVERDUE' AND o.hostel_id IN (SELECT id FROM h)),
    (SELECT api.card('roll-call', 'NEEDS_YOU', 'ROLL_CALL', initcap(open_rc.session) || ' roll call open', NULL, NULL, 'ACTION', 'roll-calls/' || open_rc.roll_call_id)
       FROM open_rc ORDER BY open_rc.roll_call_id DESC LIMIT 1),
    (SELECT api.card('approvals', 'NEEDS_YOU', 'OUTING_APPROVAL', 'Outings to approve', NULL, count(*), 'ACTION', 'outings?status=REQUESTED')
       FROM hostel.outing_request o WHERE o.status = 'REQUESTED' AND o.warden_status = 'PENDING' AND o.parent_status IN ('APPROVED', 'NOT_REQUIRED')
        AND o.hostel_id IN (SELECT id FROM h)),
    (SELECT api.card('phones-due', 'NEEDS_YOU', 'CUSTODY_DUE', 'Devices due back', NULL, count(*), 'ACTION', 'custody?due=true')
       FROM custody.item i JOIN hostel.allocation a ON a.student_id = i.student_id AND a.status = 'ACTIVE'
      WHERE i.status IN ('RELEASED_TEMP', 'RELEASED_TRAVEL') AND i.due_back_at < now() AND a.hostel_id IN (SELECT id FROM h)),
    (SELECT api.card('tickets', 'NEEDS_YOU', 'TICKETS', 'Open room tickets', NULL, count(*), 'INFO', 'tickets')
       FROM facility.ticket t JOIN hostel.room r ON r.room_id = t.room_id WHERE t.status IN ('OPEN', 'ASSIGNED', 'REOPENED') AND r.hostel_id IN (SELECT id FROM h)),
    (SELECT api.card('out-now', 'NOW', 'ON_OUTING', 'Out on pass', NULL, count(*), 'INFO', 'outings?status=OUT')
       FROM hostel.outing_request o WHERE o.status = 'OUT' AND o.hostel_id IN (SELECT id FROM h)),
    (SELECT api.card('returns', 'TODAY', 'RETURNS_DUE', 'Returns due today', NULL, count(*), 'INFO', 'outings?status=OUT')
       FROM hostel.outing_request o WHERE o.status = 'OUT' AND o.return_planned_at::date = current_date AND o.hostel_id IN (SELECT id FROM h)),
    (SELECT api.card('sick', 'TODAY', 'SICK_BAY', 'In sick bay', NULL, count(*), 'INFO', 'residents')
       FROM wellbeing.infirmary_visit v JOIN hostel.allocation a ON a.student_id = v.person_id AND a.status = 'ACTIVE'
      WHERE v.person_kind = 'STUDENT' AND v.disposition = 'SICK_BAY' AND v.discharged_at IS NULL AND a.hostel_id IN (SELECT id FROM h)));

-- name: listResidents
SELECT coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object('student', api.student_ref(a.student_id), 'room', r.room_number, 'bed', b.bed_label,
       'status', api.hostel_status(a.student_id),
       'phoneCustody', (SELECT i.status FROM custody.item i WHERE i.student_id = a.student_id AND i.item_type = 'MOBILE_PHONE' AND i.status <> 'CLOSED' LIMIT 1),
       'alerts', api.student_alerts(a.student_id))) ORDER BY r.room_number, b.bed_label), '[]'::jsonb)
FROM hostel.allocation a JOIN hostel.room r ON r.room_id = a.room_id JOIN hostel.bed b ON b.bed_id = a.bed_id
WHERE a.status = 'ACTIVE' AND a.hostel_id IN (SELECT api.my_hostels())
  AND (NOT EXISTS (SELECT 1 FROM hostel.staff_assignment sa WHERE sa.user_id = :me::bigint AND sa.hostel_id = a.hostel_id AND sa.scope_type = 'BLOCK'
                     AND (sa.to_date IS NULL OR sa.to_date >= current_date))
       OR r.block_id IN (SELECT sa.block_id FROM hostel.staff_assignment sa WHERE sa.user_id = :me::bigint AND sa.scope_type = 'BLOCK'
                           AND (sa.to_date IS NULL OR sa.to_date >= current_date)));

-- name: startRollCall write
-- One open roll call per hostel and session per day (starting again returns it); entries prefilled from
-- outings and sick bay, everyone else ABSENT until marked
WITH b AS (SELECT :body::jsonb AS j),
     hs AS (SELECT h.* FROM hostel.hostel h, b WHERE h.hostel_id = (b.j ->> 'hostelId')::bigint AND h.hostel_id IN (SELECT api.my_hostels())),
     ex AS (SELECT rc.roll_call_id FROM hostel.roll_call rc, hs, b WHERE rc.hostel_id = hs.hostel_id AND rc.roll_date = current_date
              AND rc.session = coalesce(b.j ->> 'session', 'NIGHT') AND rc.status = 'OPEN'),
     rc AS (INSERT INTO hostel.roll_call (school_id, hostel_id, assignment_id, session, roll_date, conducted_by_user_id, started_at, status)
            SELECT hs.school_id, hs.hostel_id, (b.j ->> 'assignmentId')::bigint, coalesce(b.j ->> 'session', 'NIGHT'), current_date, :me::bigint, now(), 'OPEN'
              FROM hs, b WHERE NOT EXISTS (SELECT 1 FROM ex) RETURNING roll_call_id, school_id, hostel_id),
     ent AS (INSERT INTO hostel.roll_call_entry (school_id, roll_call_id, student_id, status, outing_id, custody_pending)
             SELECT rc.school_id, rc.roll_call_id, a.student_id,
                    CASE api.hostel_status(a.student_id) WHEN 'SICK_BAY' THEN 'SICK_BAY' WHEN 'ON_OUTING' THEN 'ON_OUTING' WHEN 'ON_LEAVE' THEN 'ON_LEAVE'
                                                         WHEN 'MISSING' THEN 'ON_OUTING' ELSE 'ABSENT' END,
                    (SELECT o.outing_id FROM hostel.outing_request o WHERE o.student_id = a.student_id AND o.status IN ('OUT', 'OVERDUE') LIMIT 1),
                    EXISTS (SELECT 1 FROM custody.item i WHERE i.student_id = a.student_id AND i.status IN ('RELEASED_TEMP', 'RELEASED_TRAVEL') AND i.due_back_at < now())
               FROM rc JOIN hostel.allocation a ON a.hostel_id = rc.hostel_id AND a.status = 'ACTIVE' RETURNING 1)
SELECT coalesce((SELECT roll_call_id FROM rc), (SELECT roll_call_id FROM ex)) AS result WHERE EXISTS (SELECT 1 FROM hs) AND (SELECT count(*) FROM ent) >= 0;
-- then
SELECT api.roll_call_sheet(:result::bigint);

-- name: getRollCall
SELECT api.roll_call_sheet(rc.roll_call_id) FROM hostel.roll_call rc WHERE rc.roll_call_id = :rollCallId::bigint AND rc.hostel_id IN (SELECT api.my_hostels());

-- name: markRollCall write
WITH rc AS (SELECT * FROM hostel.roll_call WHERE roll_call_id = :rollCallId::bigint AND status = 'OPEN' AND hostel_id IN (SELECT api.my_hostels())),
     m AS (SELECT (x ->> 'studentId')::bigint AS sid, x ->> 'status' AS st, x ->> 'note' AS note
             FROM jsonb_array_elements(coalesce(:body::jsonb -> 'marks', '[]'::jsonb)) x),
     up AS (INSERT INTO hostel.roll_call_entry (school_id, roll_call_id, student_id, status, note)
            SELECT rc.school_id, rc.roll_call_id, m.sid, m.st, m.note FROM rc, m
             WHERE m.sid IN (SELECT a.student_id FROM hostel.allocation a WHERE a.hostel_id = rc.hostel_id AND a.status = 'ACTIVE')
            ON CONFLICT (school_id, roll_call_id, student_id) DO UPDATE SET status = EXCLUDED.status, note = coalesce(EXCLUDED.note, hostel.roll_call_entry.note)
            RETURNING 1)
SELECT rc.roll_call_id AS result FROM rc WHERE (SELECT count(*) FROM up) >= 0;
-- then
SELECT api.roll_call_sheet(:result::bigint);

-- name: submitRollCall write
-- Submitted; with anyone ABSENT (no pass) it is ESCALATED instead (the escalation flow notifies the chief warden)
WITH up AS (UPDATE hostel.roll_call rc SET submitted_at = now(),
                   status = CASE WHEN EXISTS (SELECT 1 FROM hostel.roll_call_entry e WHERE e.roll_call_id = rc.roll_call_id AND e.status = 'ABSENT')
                                 THEN 'ESCALATED' ELSE 'SUBMITTED' END
             WHERE rc.roll_call_id = :rollCallId::bigint AND rc.status = 'OPEN' AND rc.hostel_id IN (SELECT api.my_hostels()) RETURNING rc.roll_call_id)
SELECT roll_call_id AS result FROM up;
-- then
SELECT api.roll_call_sheet(:result::bigint);

-- name: checkRelease
-- Can this item go out now: a release window open now, an approved outing that releases items, or a travel group
WITH i AS (SELECT i.*, a.hostel_id FROM custody.item i JOIN hostel.allocation a ON a.student_id = i.student_id AND a.status = 'ACTIVE'
            WHERE i.item_id = :itemId::bigint AND a.hostel_id IN (SELECT api.my_hostels())),
     w AS (SELECT rw.* FROM custody.release_window rw, i WHERE rw.hostel_id = i.hostel_id AND coalesce(rw.is_active, true)
             AND rw.day_of_week = api.dow(current_date) AND localtime BETWEEN rw.start_time AND rw.end_time
             AND (rw.item_types IS NULL OR position(i.item_type IN rw.item_types) > 0) LIMIT 1),
     o AS (SELECT o.* FROM hostel.outing_request o, i WHERE o.student_id = i.student_id AND o.status IN ('APPROVED', 'OUT')
             AND coalesce(o.release_custody_items, false) ORDER BY o.depart_planned_at LIMIT 1)
SELECT jsonb_strip_nulls(jsonb_build_object('itemId', i.item_id,
    'allowed', i.status = 'IN_CUSTODY' AND (EXISTS (SELECT 1 FROM w) OR EXISTS (SELECT 1 FROM o)),
    'reason', CASE WHEN i.status <> 'IN_CUSTODY' THEN 'Item is ' || lower(replace(i.status, '_', ' '))
                   WHEN EXISTS (SELECT 1 FROM o) THEN 'Approved outing'
                   WHEN EXISTS (SELECT 1 FROM w) THEN (SELECT name FROM w)
                   ELSE 'No release window now' END,
    'dueBackAt', coalesce((SELECT return_planned_at FROM o), (SELECT (current_date + end_time)::timestamptz FROM w)),
    'windowId', (SELECT window_id FROM w), 'outingId', (SELECT outing_id FROM o)))
FROM i;

-- name: recordCustodyEvent write
-- Event on an item of my residents; the item's status / unit / due-back follow the event type
WITH b AS (SELECT :body::jsonb AS j),
     i AS (SELECT i.* FROM custody.item i JOIN hostel.allocation a ON a.student_id = i.student_id AND a.status = 'ACTIVE'
            WHERE i.item_id = :itemId::bigint AND a.hostel_id IN (SELECT api.my_hostels())),
     ev AS (INSERT INTO custody.event (school_id, item_id, event_type, release_reason, outing_id, group_id, window_id, incident_id, from_unit_id, to_unit_id,
                                       performed_by_user_id, counterparty_kind, counterparty_user_id, counterparty_pickup_person_id, verification, condition_note,
                                       photo_url, due_back_at, occurred_at)
            SELECT i.school_id, i.item_id, b.j ->> 'eventType', b.j ->> 'releaseReason', (b.j ->> 'outingId')::bigint, (b.j ->> 'groupId')::bigint,
                   (b.j ->> 'windowId')::bigint, (b.j ->> 'incidentId')::bigint, i.storage_unit_id, (b.j ->> 'toUnitId')::bigint, :me::bigint,
                   b.j ->> 'counterpartyKind', (b.j ->> 'counterpartyUserId')::bigint, (b.j ->> 'counterpartyPickupPersonId')::bigint, b.j ->> 'verification',
                   b.j ->> 'conditionNote', b.j ->> 'photoUrl',
                   CASE WHEN b.j ->> 'eventType' = 'RELEASE' THEN coalesce(
                        (SELECT o.return_planned_at FROM hostel.outing_request o WHERE o.outing_id = (b.j ->> 'outingId')::bigint),
                        (SELECT (current_date + rw.end_time)::timestamptz FROM custody.release_window rw WHERE rw.window_id = (b.j ->> 'windowId')::bigint),
                        now() + interval '2 hours') END, now()
              FROM i, b RETURNING item_id, event_type, to_unit_id, due_back_at, release_reason),
     up AS (UPDATE custody.item t SET
                status = CASE ev.event_type WHEN 'DEPOSIT' THEN 'IN_CUSTODY' WHEN 'RETURN' THEN 'IN_CUSTODY'
                                            WHEN 'RELEASE' THEN CASE WHEN ev.release_reason = 'TRAVEL_HOME' THEN 'RELEASED_TRAVEL' ELSE 'RELEASED_TEMP' END
                                            WHEN 'CONFISCATE' THEN 'CONFISCATED' WHEN 'HANDOVER_PARENT' THEN 'WITH_PARENT' WHEN 'MARK_LOST' THEN 'LOST'
                                            WHEN 'MARK_DAMAGED' THEN 'DAMAGED' WHEN 'CLOSE' THEN 'CLOSED' ELSE t.status END,
                storage_unit_id = coalesce(ev.to_unit_id, t.storage_unit_id),
                due_back_at = CASE WHEN ev.event_type = 'RELEASE' THEN ev.due_back_at WHEN ev.event_type IN ('RETURN', 'DEPOSIT') THEN NULL ELSE t.due_back_at END
              FROM ev WHERE t.item_id = ev.item_id RETURNING t.*)
SELECT api.camel(to_jsonb(up)) FROM up;

-- name: listOutings
SELECT api.page(coalesce(jsonb_agg(api.outing_view(o.outing_id) ORDER BY (o.status = 'OVERDUE') DESC, o.depart_planned_at DESC), '[]'::jsonb), :page, :size)
FROM hostel.outing_request o WHERE o.hostel_id IN (SELECT api.my_hostels()) AND (:status IS NULL OR o.status = :status);

-- name: raiseOuting write
-- Medical / emergency / official outing raised by the warden for a resident; the parent is asked unless the
-- policy says otherwise; the warden's own approval is recorded
WITH b AS (SELECT :body::jsonb AS j),
     a AS (SELECT al.* FROM hostel.allocation al, b WHERE al.student_id = (b.j ->> 'studentId')::bigint AND al.status = 'ACTIVE'
             AND al.hostel_id IN (SELECT api.my_hostels())),
     pol AS (SELECT p.* FROM hostel.outing_policy p, a, b WHERE p.hostel_id = a.hostel_id AND p.outing_type = b.j ->> 'outingType' LIMIT 1),
     ins AS (INSERT INTO hostel.outing_request (school_id, student_id, hostel_id, policy_id, outing_type, purpose, destination, depart_planned_at, return_planned_at,
                                                travel_mode, requested_by_kind, requested_by_user_id, parent_status, warden_status, warden_user_id, warden_decided_at, status)
             SELECT a.school_id, a.student_id, a.hostel_id, (SELECT policy_id FROM pol), b.j ->> 'outingType', b.j ->> 'purpose', b.j ->> 'destination',
                    (b.j ->> 'departPlannedAt')::timestamptz, (b.j ->> 'returnPlannedAt')::timestamptz, b.j ->> 'travelMode', 'WARDEN', :me::bigint,
                    CASE WHEN coalesce((SELECT requires_parent_approval FROM pol), true) THEN 'PENDING' ELSE 'NOT_REQUIRED' END,
                    'APPROVED', :me::bigint, now(),
                    CASE WHEN coalesce((SELECT requires_parent_approval FROM pol), true) THEN 'REQUESTED' ELSE 'APPROVED' END
               FROM a, b RETURNING outing_id)
SELECT outing_id AS result FROM ins;
-- then
SELECT api.outing_view(:result::bigint);

-- name: getHandoverDraft
WITH h AS (SELECT api.my_hostels() AS id)
SELECT jsonb_build_object(
    'openItems', coalesce((SELECT jsonb_agg(x) FROM (
         SELECT 'Roll call ' || lower(rc.session) || ' still open' AS x FROM hostel.roll_call rc WHERE rc.hostel_id IN (SELECT id FROM h) AND rc.roll_date = current_date AND rc.status = 'OPEN'
         UNION ALL SELECT 'Ticket: ' || t.description FROM facility.ticket t JOIN hostel.room r ON r.room_id = t.room_id
                    WHERE r.hostel_id IN (SELECT id FROM h) AND t.status IN ('OPEN', 'ASSIGNED')
         UNION ALL SELECT 'Device due back: ' || (api.student_ref(i.student_id) ->> 'name') FROM custody.item i JOIN hostel.allocation a ON a.student_id = i.student_id AND a.status = 'ACTIVE'
                    WHERE a.hostel_id IN (SELECT id FROM h) AND i.status IN ('RELEASED_TEMP', 'RELEASED_TRAVEL') AND i.due_back_at < now()) y), '[]'::jsonb),
    'sickStudents', coalesce((SELECT jsonb_agg(api.student_ref(v.person_id)) FROM wellbeing.infirmary_visit v JOIN hostel.allocation a ON a.student_id = v.person_id AND a.status = 'ACTIVE'
                               WHERE v.person_kind = 'STUDENT' AND v.disposition = 'SICK_BAY' AND v.discharged_at IS NULL AND a.hostel_id IN (SELECT id FROM h)), '[]'::jsonb),
    'lateReturns', coalesce((SELECT jsonb_agg(api.outing_view(o.outing_id)) FROM hostel.outing_request o WHERE o.status = 'OVERDUE' AND o.hostel_id IN (SELECT id FROM h)), '[]'::jsonb),
    'openIncidents', coalesce((SELECT jsonb_agg(api.camel(to_jsonb(i)) ORDER BY i.occurred_at DESC) FROM discipline.incident i
                                WHERE i.hostel_id IN (SELECT id FROM h) AND i.status IN ('REPORTED', 'UNDER_REVIEW')), '[]'::jsonb));
