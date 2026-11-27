-- Screen queries for /api/v1/parent. :studentId is checked against the caller's children before the query runs
-- (core.data.ScopeService), and every query also joins through api.my_children().

-- name: listChildren
SELECT coalesce(jsonb_agg(api.child_summary(c) ORDER BY c), '[]'::jsonb) FROM api.my_children() c;

-- name: getChild
SELECT api.student_card(c) FROM api.my_children() c WHERE c = :studentId::bigint;

-- name: getHome
-- One feed for all children (or the one in studentId): Critical -> Needs you -> Now -> Today -> Feed
WITH kids AS (SELECT c AS sid FROM api.my_children() c WHERE :studentId IS NULL OR c = :studentId::bigint)
SELECT api.feed('PARENT',
    (SELECT api.card('missing-' || o.outing_id, 'CRITICAL', 'OUTING_OVERDUE', api.student_ref(o.student_id) ->> 'name' || ' is not back',
                     'Was due ' || to_char(o.return_planned_at, 'HH24:MI'), NULL, 'CRITICAL', 'outings/' || o.outing_id, o.return_planned_at)
       FROM hostel.outing_request o WHERE o.student_id IN (SELECT sid FROM kids) AND o.status = 'OVERDUE' ORDER BY o.return_planned_at LIMIT 1),
    (SELECT api.card('critical', 'CRITICAL', 'CRITICAL_ALERT', 'Urgent message from school', max(n.title), count(*), 'CRITICAL', 'inbox?severity=CRITICAL')
       FROM communication.notification_recipient r JOIN communication.notification n ON n.notification_id = r.notification_id
      WHERE r.recipient_user_id = :me::bigint AND n.severity = 'CRITICAL' AND r.acknowledged_at IS NULL AND n.sent_time > now() - interval '24 hours'),
    (SELECT api.card('outing-decisions', 'NEEDS_YOU', 'OUTING_APPROVAL', 'Outing requests to approve', NULL, count(*), 'ACTION', 'outings?pending=true')
       FROM hostel.outing_request o WHERE o.student_id IN (SELECT sid FROM kids) AND o.parent_status = 'PENDING' AND o.status = 'REQUESTED'),
    (SELECT api.card('consents', 'NEEDS_YOU', 'CONSENT', 'Consent forms waiting', NULL, count(*), 'ACTION', 'consents')
       FROM compliance.consent_form f, kids
      WHERE f.published_at IS NOT NULL AND coalesce(f.signer_parent, false)
        AND NOT EXISTS (SELECT 1 FROM compliance.consent_record cr WHERE cr.form_id = f.form_id AND cr.form_version = f.version
                          AND cr.subject_kind = 'STUDENT' AND cr.subject_id = kids.sid)),
    (SELECT api.card('acks', 'NEEDS_YOU', 'ACKNOWLEDGE', 'Notices to acknowledge', max(n.title), count(*), 'ACTION', 'inbox?unreadOnly=true')
       FROM communication.notification_recipient r JOIN communication.notification n ON n.notification_id = r.notification_id
      WHERE r.recipient_user_id = :me::bigint AND coalesce(n.requires_ack, false) AND r.acknowledged_at IS NULL AND n.severity <> 'CRITICAL'),
    (SELECT api.card('fees', 'NEEDS_YOU', 'FEES_OVERDUE', 'Fees overdue', '₹' || to_char(sum(f.remaining_due), 'FM99,99,99,990'), count(DISTINCT f.student_id), 'ACTION', 'fees')
       FROM finance.fee f WHERE f.student_id IN (SELECT sid FROM kids) AND f.status IN ('DUE', 'PART_PAID') AND f.due_date < current_date),
    (SELECT api.card('ptm', 'NEEDS_YOU', 'PTM_BOOKING', 'Book a PTM slot', NULL, count(DISTINCT ps.ptm_id), 'INFO', 'ptm')
       FROM communication.ptm_session ps JOIN academics.student s ON s.class_section_id = ps.class_section_id AND s.student_id IN (SELECT sid FROM kids)
      WHERE EXISTS (SELECT 1 FROM communication.ptm_slot sl WHERE sl.ptm_id = ps.ptm_id AND sl.status = 'OPEN' AND sl.start_at > now())
        AND NOT EXISTS (SELECT 1 FROM communication.ptm_slot sl WHERE sl.ptm_id = ps.ptm_id AND sl.student_id = s.student_id AND sl.status = 'BOOKED')),
    (SELECT api.card('child-' || sid, 'NOW', 'CHILD_STATUS', cs ->> 'name', cs ->> 'statusText', NULL,
                     CASE cs ->> 'statusDot' WHEN 'RED' THEN 'URGENT' WHEN 'AMBER' THEN 'ACTION' ELSE 'INFO' END, 'children/' || sid, NULL, cs)
       FROM (SELECT sid, api.child_summary(sid) AS cs FROM kids ORDER BY sid LIMIT 1) k),
    (SELECT api.card('child-' || sid, 'NOW', 'CHILD_STATUS', cs ->> 'name', cs ->> 'statusText', NULL,
                     CASE cs ->> 'statusDot' WHEN 'RED' THEN 'URGENT' WHEN 'AMBER' THEN 'ACTION' ELSE 'INFO' END, 'children/' || sid, NULL, cs)
       FROM (SELECT sid, api.child_summary(sid) AS cs FROM kids ORDER BY sid OFFSET 1 LIMIT 1) k),
    (SELECT api.card('bus', 'NOW', 'BUS', 'Bus ' || lower(b ->> 'status'), b ->> 'route', NULL, 'INFO', 'children/' || sid || '/bus', NULL, b)
       FROM (SELECT sid, api.bus_status(sid) AS b FROM kids) x WHERE b ->> 'status' = 'RUNNING' LIMIT 1),
    (SELECT api.card('homework', 'TODAY', 'HOMEWORK_DUE', 'Homework due soon', string_agg(DISTINCT h.title, ', '), count(*), 'INFO', 'homework')
       FROM operations.homework h JOIN academics.student s ON s.class_section_id = h.class_section_id AND s.student_id IN (SELECT sid FROM kids)
      WHERE h.due_date BETWEEN current_date AND current_date + 1
        AND NOT EXISTS (SELECT 1 FROM operations.homework_submission hs WHERE hs.homework_id = h.homework_id AND hs.student_id = s.student_id)),
    (SELECT api.card('events', 'TODAY', 'CALENDAR', e.title, to_char(e.start_date, 'Dy DD Mon'), NULL, 'INFO', 'calendar')
       FROM calendar.event e WHERE e.start_date BETWEEN current_date AND current_date + 7 ORDER BY e.start_date LIMIT 1),
    (SELECT api.card('news', 'FEED', 'NEWS', 'School news', max(p.title), count(*), 'INFO', 'news')
       FROM communication.news_post p WHERE p.deleted_at IS NULL AND p.expires_at > now() AND p.created_at > now() - interval '3 days'
        AND (p.audience_type = 'ALL' OR p.class_section_id IN (SELECT s.class_section_id FROM academics.student s WHERE s.student_id IN (SELECT sid FROM kids)))));

-- name: getAttendance
SELECT api.attendance_calendar(c, :month) FROM api.my_children() c WHERE c = :studentId::bigint;

-- name: getTimetable
SELECT api.timetable_grid(s.class_section_id) FROM academics.student s WHERE s.student_id = :studentId::bigint
   AND s.student_id IN (SELECT api.my_children()) AND s.class_section_id IS NOT NULL;

-- name: listHomework
SELECT api.page(api.homework_views(c, :from::date), :page, :size) FROM api.my_children() c WHERE c = :studentId::bigint;

-- name: listResults
SELECT api.exam_results(c) FROM api.my_children() c WHERE c = :studentId::bigint;

-- name: listReportCards
SELECT api.report_card_statuses(c) FROM api.my_children() c WHERE c = :studentId::bigint;

-- name: getFees
SELECT api.family_dues(coalesce(array_agg(c), '{}'::bigint[])) FROM api.my_children() c;

-- name: getHostelCard
SELECT api.hostel_card(c) FROM api.my_children() c WHERE c = :studentId::bigint;

-- name: listOutings
SELECT api.page(coalesce(jsonb_agg(api.outing_view(o.outing_id) ORDER BY o.depart_planned_at DESC), '[]'::jsonb), :page, :size)
FROM hostel.outing_request o WHERE o.student_id = :studentId::bigint AND o.student_id IN (SELECT api.my_children());

-- name: requestOuting write
-- Parent-raised outing: parent approval is implied; the hostel's policy for the type is attached; warden decides
WITH b AS (SELECT :body::jsonb AS j),
     a AS (SELECT al.* FROM hostel.allocation al WHERE al.student_id = :studentId::bigint AND al.status = 'ACTIVE'
             AND al.student_id IN (SELECT api.my_children()) LIMIT 1),
     ins AS (
    INSERT INTO hostel.outing_request (school_id, student_id, hostel_id, policy_id, outing_type, purpose, destination, depart_planned_at,
        return_planned_at, travel_mode, travel_ref, travel_departure_at, pickup_person_id, requested_by_kind, requested_by_user_id,
        parent_status, parent_user_id, parent_decided_at, warden_status, release_custody_items, status)
    SELECT a.school_id, a.student_id, a.hostel_id,
           (SELECT p.policy_id FROM hostel.outing_policy p WHERE p.hostel_id = a.hostel_id AND p.outing_type = b.j ->> 'outingType' LIMIT 1),
           b.j ->> 'outingType', b.j ->> 'purpose', b.j ->> 'destination', (b.j ->> 'departPlannedAt')::timestamptz,
           (b.j ->> 'returnPlannedAt')::timestamptz, b.j ->> 'travelMode', b.j ->> 'travelRef', (b.j ->> 'travelDepartureAt')::timestamptz,
           (SELECT pp.pickup_person_id FROM frontoffice.pickup_person pp WHERE pp.pickup_person_id = (b.j ->> 'pickupPersonId')::bigint
              AND pp.student_id = a.student_id AND coalesce(pp.is_active, true)),
           'PARENT', :me::bigint, 'APPROVED', :me::bigint, now(), 'PENDING', coalesce((b.j ->> 'releaseCustodyItems')::boolean, false), 'REQUESTED'
      FROM a, b RETURNING outing_id)
SELECT outing_id AS result FROM ins;
-- then
SELECT api.outing_view(:result::bigint);

-- name: decideOuting write
-- Approve or decline a request raised by the student or the hostel; declining closes it
WITH b AS (SELECT :body::jsonb AS j),
     up AS (
    UPDATE hostel.outing_request o
       SET parent_status = b.j ->> 'decision', parent_user_id = :me::bigint, parent_decided_at = now(),
           pickup_person_id = coalesce((SELECT pp.pickup_person_id FROM frontoffice.pickup_person pp
                                         WHERE pp.pickup_person_id = (b.j ->> 'pickupPersonId')::bigint AND pp.student_id = o.student_id), o.pickup_person_id),
           status = CASE WHEN b.j ->> 'decision' = 'DECLINED' THEN 'REJECTED' ELSE o.status END
      FROM b
     WHERE o.outing_id = :outingId::bigint AND o.student_id IN (SELECT api.my_children())
       AND o.status = 'REQUESTED' AND o.parent_status = 'PENDING' AND b.j ->> 'decision' IN ('APPROVED', 'DECLINED')
    RETURNING o.outing_id)
SELECT outing_id AS result FROM up;
-- then
SELECT api.outing_view(:result::bigint);

-- name: cancelOuting write
WITH up AS (
    UPDATE hostel.outing_request o SET status = 'CANCELLED'
     WHERE o.outing_id = :outingId::bigint AND o.student_id IN (SELECT api.my_children()) AND o.status IN ('REQUESTED', 'APPROVED')
    RETURNING o.outing_id)
SELECT outing_id AS result FROM up;
-- then
SELECT api.outing_view(:result::bigint);

-- name: getWallet
SELECT api.wallet_statement(c) FROM api.my_children() c WHERE c = :studentId::bigint;

-- name: listCustody
SELECT api.custody_items(c) FROM api.my_children() c WHERE c = :studentId::bigint;

-- name: getBusStatus
SELECT api.bus_status(c) FROM api.my_children() c WHERE c = :studentId::bigint;

-- name: bookPtmSlot write
-- An open future slot of a PTM for the child's section; one booking per child per PTM
WITH b AS (SELECT (:body::jsonb ->> 'studentId')::bigint AS sid),
     up AS (
    UPDATE communication.ptm_slot sl SET status = 'BOOKED', booked_by_user_id = :me::bigint, student_id = b.sid
      FROM b, communication.ptm_session ps
     WHERE sl.slot_id = :slotId::bigint AND sl.status = 'OPEN' AND sl.start_at > now() AND ps.ptm_id = sl.ptm_id
       AND b.sid IN (SELECT api.my_children())
       AND (ps.class_section_id IS NULL OR ps.class_section_id = (SELECT s.class_section_id FROM academics.student s WHERE s.student_id = b.sid))
       AND NOT EXISTS (SELECT 1 FROM communication.ptm_slot x WHERE x.ptm_id = sl.ptm_id AND x.student_id = b.sid AND x.status = 'BOOKED')
    RETURNING sl.*)
SELECT api.camel(to_jsonb(up)) FROM up;

-- name: answerPoll write
-- One answer per parent (per child when the poll asks for that); answering again replaces the answer
WITH b AS (SELECT :body::jsonb AS j),
     ok AS (SELECT p.*, (b.j ->> 'optionKey') AS opt,
                   CASE WHEN coalesce(p.one_per_child, false) THEN (b.j ->> 'studentId')::bigint END AS sid
              FROM communication.poll p, b
             WHERE p.poll_id = :pollId::bigint AND (p.closes_at IS NULL OR p.closes_at > now())
               AND EXISTS (SELECT 1 FROM jsonb_array_elements(p.options) o WHERE o ->> 'key' = b.j ->> 'optionKey')
               AND (NOT coalesce(p.one_per_child, false) OR (b.j ->> 'studentId')::bigint IN (SELECT api.my_children()))),
     ins AS (INSERT INTO communication.poll_response (school_id, poll_id, user_id, student_id, option_key, responded_at)
             SELECT ok.school_id, ok.poll_id, :me::bigint, ok.sid, ok.opt, now() FROM ok
             ON CONFLICT (school_id, poll_id, user_id, student_id) DO UPDATE SET option_key = EXCLUDED.option_key, responded_at = EXCLUDED.responded_at
             RETURNING 1)
SELECT CASE WHEN EXISTS (SELECT 1 FROM ins) THEN '{}' END;

-- name: respondReenrollment write
WITH b AS (SELECT :body::jsonb AS j),
     up AS (
    UPDATE admissions.reenrollment r SET status = b.j ->> 'status', leaving_reason = b.j ->> 'leavingReason',
           responded_by_user_id = :me::bigint, responded_at = now()
      FROM b
     WHERE r.reenrollment_id = :reenrollmentId::bigint AND r.student_id IN (SELECT api.my_children())
       AND r.status = 'INVITED' AND b.j ->> 'status' IN ('CONFIRMED', 'DECLINED', 'LEAVING')
    RETURNING r.*)
SELECT api.camel(to_jsonb(up)) FROM up;

-- name: removePickupPerson write
-- Deactivated, not deleted: past outings and gate records keep pointing at the person
WITH up AS (UPDATE frontoffice.pickup_person SET is_active = false, valid_to = least(coalesce(valid_to, current_date), current_date)
             WHERE pickup_person_id = :pickupPersonId::bigint AND student_id IN (SELECT api.my_children()) RETURNING 1)
SELECT CASE WHEN EXISTS (SELECT 1 FROM up) THEN '{}' END;
