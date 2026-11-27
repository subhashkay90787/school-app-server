-- Screen queries for /api/v1/security (guard at a post: gate, patrol, welfare checks).

-- name: getHome
WITH r AS (SELECT re.*, p.code AS post_code, sh.code AS shift_code, sh.start_time, sh.end_time, sh.crosses_midnight
             FROM hr.roster_entry re JOIN hr.shift sh ON sh.shift_id = re.shift_id LEFT JOIN hr.post p ON p.post_id = re.post_id
            WHERE re.user_id = :me::bigint AND re.duty_date IN (current_date, current_date - 1) AND re.status IN ('ON_DUTY', 'PLANNED')
            ORDER BY (re.status = 'ON_DUTY') DESC, re.duty_date DESC LIMIT 1),
     nxt AS (SELECT pr.*, rt.name AS route FROM security.patrol_round pr JOIN security.patrol_route rt ON rt.route_id = pr.route_id
              WHERE pr.guard_user_id = :me::bigint AND pr.status IN ('DUE', 'IN_PROGRESS') ORDER BY pr.due_at LIMIT 1)
SELECT jsonb_strip_nulls(jsonb_build_object(
    'post', (SELECT post_code FROM r), 'shift', (SELECT shift_code FROM r),
    'onDutyFrom', (SELECT (duty_date + start_time)::timestamptz FROM r),
    'onDutyTo', (SELECT (duty_date + end_time + CASE WHEN crosses_midnight THEN interval '1 day' ELSE interval '0' END)::timestamptz FROM r),
    'nextCheckpoint', (SELECT c.name FROM nxt JOIN security.route_checkpoint rc ON rc.route_id = nxt.route_id JOIN security.checkpoint c ON c.checkpoint_id = rc.checkpoint_id
                        WHERE NOT EXISTS (SELECT 1 FROM security.patrol_scan s WHERE s.round_id = nxt.round_id AND s.checkpoint_id = rc.checkpoint_id)
                        ORDER BY rc.sequence LIMIT 1),
    'nextCheckpointDueAt', (SELECT due_at FROM nxt),
    'welfarePingDueAt', (SELECT max(w.sent_at) + interval '1 hour' FROM security.welfare_ping w WHERE w.roster_entry_id = (SELECT roster_entry_id FROM r)),
    'expected', (SELECT coalesce(jsonb_agg(x ORDER BY x ->> 'at'), '[]'::jsonb) FROM (
        SELECT jsonb_build_object('kind', 'OUTING_RETURN', 'title', (api.student_ref(o.student_id) ->> 'name') || ' returning', 'at', o.return_planned_at,
                                  'refId', o.outing_id, 'count', 1) AS x
          FROM hostel.outing_request o WHERE o.status IN ('OUT', 'OVERDUE') AND o.return_planned_at < now() + interval '6 hours'
        UNION ALL
        SELECT jsonb_build_object('kind', 'TRAVEL_GROUP_DEPARTURE', 'title', g.title, 'at', g.campus_departure_at, 'refId', g.group_id,
                                  'count', (SELECT count(*) FROM hostel.outing_request o WHERE o.group_id = g.group_id AND o.status NOT IN ('CANCELLED', 'REJECTED')))
          FROM hostel.outing_group g WHERE g.status = 'PLANNED' AND g.campus_departure_at BETWEEN now() - interval '1 hour' AND now() + interval '24 hours') y),
    'cards', api.feed('SECURITY',
        (SELECT api.card('overdue', 'CRITICAL', 'OUTING_OVERDUE', 'Students overdue', string_agg(api.student_ref(o.student_id) ->> 'name', ', '), count(*), 'CRITICAL', 'gate/expected')
           FROM hostel.outing_request o WHERE o.status = 'OVERDUE'),
        (SELECT api.card('round', 'NEEDS_YOU', 'PATROL_DUE', 'Patrol ' || nxt.route, to_char(nxt.due_at, 'HH24:MI'), NULL,
                         CASE WHEN nxt.due_at < now() THEN 'URGENT' ELSE 'ACTION' END, 'patrol/current') FROM nxt),
        (SELECT api.card('visitors', 'NOW', 'VISITORS_IN', 'Visitors on campus', NULL, count(*), 'INFO', 'visits')
           FROM frontoffice.visit v WHERE v.check_out_at IS NULL),
        (SELECT api.card('vehicles', 'NOW', 'VEHICLES_IN', 'Vehicles inside', string_agg(e.vehicle_number, ', '), count(*), 'INFO', 'vehicles')
           FROM security.vehicle_entry e WHERE e.out_at IS NULL)) -> 'cards'));

-- name: recordGateMovement write
-- OUT needs an approved outing (pickup person checked against the outing); IN closes it (late minutes noted)
WITH b AS (SELECT :body::jsonb AS j),
     o AS (SELECT o.* FROM hostel.outing_request o, b WHERE o.outing_id = (b.j ->> 'outingId')::bigint
             AND ((b.j ->> 'direction' = 'OUT' AND o.status = 'APPROVED'
                   AND (o.pickup_person_id IS NULL OR o.pickup_person_id = (b.j ->> 'verifiedPickupPersonId')::bigint OR o.travel_mode NOT IN ('AUTHORISED_PICKUP')))
               OR (b.j ->> 'direction' = 'IN' AND o.status IN ('OUT', 'OVERDUE')))),
     mv AS (INSERT INTO hostel.outing_movement (school_id, outing_id, direction, moved_at, gate_user_id, roster_entry_id, verified_pickup_person_id, verification)
            SELECT o.school_id, o.outing_id, b.j ->> 'direction', coalesce((b.j ->> 'movedAt')::timestamptz, now()), :me::bigint,
                   (SELECT re.roster_entry_id FROM hr.roster_entry re WHERE re.user_id = :me::bigint AND re.duty_date = current_date AND re.status = 'ON_DUTY' LIMIT 1),
                   (b.j ->> 'verifiedPickupPersonId')::bigint, coalesce(b.j ->> 'verification', 'QR')
              FROM o, b RETURNING *),
     st AS (UPDATE hostel.outing_request r SET
                status = CASE WHEN mv.direction = 'OUT' THEN 'OUT' ELSE 'RETURNED' END,
                late_minutes = CASE WHEN mv.direction = 'IN' THEN greatest(0, extract(epoch FROM (mv.moved_at - r.return_planned_at)) / 60)::int ELSE r.late_minutes END
              FROM mv WHERE r.outing_id = mv.outing_id RETURNING 1)
SELECT api.camel(to_jsonb(mv)) FROM mv WHERE (SELECT count(*) FROM st) >= 0;

-- name: releaseDayScholar write
WITH up AS (UPDATE frontoffice.gate_pass SET out_at = now(), verified_by_user_id = :me::bigint
             WHERE gate_pass_id = :gatePassId::bigint AND approved_by_user_id IS NOT NULL AND out_at IS NULL RETURNING *)
SELECT api.camel(to_jsonb(up)) FROM up;

-- name: listExpected
SELECT coalesce(jsonb_agg(x ORDER BY x ->> 'at'), '[]'::jsonb) FROM (
    SELECT jsonb_build_object('kind', 'OUTING_RETURN', 'title', (api.student_ref(o.student_id) ->> 'name') || ' returning', 'at', o.return_planned_at,
                              'refId', o.outing_id, 'count', 1) AS x
      FROM hostel.outing_request o WHERE o.status IN ('OUT', 'OVERDUE') AND o.return_planned_at < now() + interval '12 hours'
    UNION ALL
    SELECT jsonb_build_object('kind', 'TRAVEL_GROUP_DEPARTURE', 'title', g.title, 'at', g.campus_departure_at, 'refId', g.group_id,
                              'count', (SELECT count(*) FROM hostel.outing_request o WHERE o.group_id = g.group_id AND o.status NOT IN ('CANCELLED', 'REJECTED')))
      FROM hostel.outing_group g WHERE g.status = 'PLANNED' AND g.campus_departure_at < now() + interval '72 hours'
    UNION ALL
    SELECT jsonb_build_object('kind', 'VISITOR', 'title', v.name || ' (in since ' || to_char(vi.check_in_at, 'HH24:MI') || ')', 'at', vi.check_in_at, 'refId', vi.visit_id, 'count', 1)
      FROM frontoffice.visit vi JOIN frontoffice.visitor v ON v.visitor_id = vi.visitor_id WHERE vi.check_out_at IS NULL
    UNION ALL
    SELECT jsonb_build_object('kind', 'VEHICLE', 'title', e.vehicle_number || coalesce(' · ' || lower(e.purpose), ''), 'at', e.in_at, 'refId', e.vehicle_entry_id, 'count', 1)
      FROM security.vehicle_entry e WHERE e.out_at IS NULL
) y;

-- name: getGroupGate
SELECT api.travel_group_board(:groupId::bigint) WHERE EXISTS (SELECT 1 FROM hostel.outing_group WHERE group_id = :groupId::bigint);

-- name: groupOut write
-- Scans the listed students of the group out together (approved outings only)
WITH b AS (SELECT :body::jsonb AS j),
     o AS (SELECT o.* FROM hostel.outing_request o, b WHERE o.group_id = :groupId::bigint AND o.status = 'APPROVED'
             AND o.student_id IN (SELECT jsonb_array_elements_text(coalesce(b.j -> 'studentIds', '[]'::jsonb))::bigint)),
     mv AS (INSERT INTO hostel.outing_movement (school_id, outing_id, direction, moved_at, gate_user_id, verification)
            SELECT o.school_id, o.outing_id, 'OUT', coalesce((b.j ->> 'movedAt')::timestamptz, now()), :me::bigint, 'QR' FROM o, b RETURNING outing_id),
     st AS (UPDATE hostel.outing_request r SET status = 'OUT' WHERE r.outing_id IN (SELECT outing_id FROM mv) RETURNING 1),
     g AS (UPDATE hostel.outing_group SET status = 'DEPARTED' WHERE group_id = :groupId::bigint AND EXISTS (SELECT 1 FROM mv) AND status = 'PLANNED' RETURNING 1)
SELECT :groupId::bigint AS result WHERE EXISTS (SELECT 1 FROM hostel.outing_group WHERE group_id = :groupId::bigint)
   AND (SELECT count(*) FROM st) + (SELECT count(*) FROM g) >= 0;
-- then
SELECT api.travel_group_board(:result::bigint);

-- name: getCurrentRound
WITH pr AS (SELECT * FROM security.patrol_round WHERE guard_user_id = :me::bigint AND status IN ('IN_PROGRESS', 'DUE')
              ORDER BY (status = 'IN_PROGRESS') DESC, due_at LIMIT 1)
SELECT jsonb_build_object('roundId', pr.round_id, 'route', rt.name, 'dueAt', pr.due_at, 'status', pr.status,
    'checkpoints', coalesce((SELECT jsonb_agg(jsonb_strip_nulls(jsonb_build_object('checkpointId', c.checkpoint_id, 'name', c.name, 'sequence', rc.sequence,
                     'scannedAt', s.scanned_at, 'photoRequired', coalesce(rc.photo_required, false),
                     'state', CASE WHEN s.scanned_at IS NOT NULL AND s.scanned_at <= pr.due_at + make_interval(mins => coalesce(rt.max_round_minutes, 30)) THEN 'DONE'
                                   WHEN s.scanned_at IS NOT NULL THEN 'LATE'
                                   WHEN now() > pr.due_at + make_interval(mins => coalesce(rt.max_round_minutes, 30)) THEN 'MISSED' ELSE 'PENDING' END))
                   ORDER BY rc.sequence)
                 FROM security.route_checkpoint rc JOIN security.checkpoint c ON c.checkpoint_id = rc.checkpoint_id
                 LEFT JOIN LATERAL (SELECT min(ps.scanned_at) AS scanned_at FROM security.patrol_scan ps WHERE ps.round_id = pr.round_id AND ps.checkpoint_id = c.checkpoint_id) s ON true
                WHERE rc.route_id = pr.route_id), '[]'::jsonb))
FROM pr JOIN security.patrol_route rt ON rt.route_id = pr.route_id;

-- name: startRound write
WITH up AS (UPDATE security.patrol_round SET status = 'IN_PROGRESS', started_at = now(), guard_user_id = coalesce(guard_user_id, :me::bigint)
             WHERE round_id = :roundId::bigint AND status = 'DUE' AND coalesce(guard_user_id, :me::bigint) = :me::bigint RETURNING round_id)
SELECT round_id AS result FROM up;
-- then
SELECT jsonb_build_object('roundId', pr.round_id, 'route', rt.name, 'dueAt', pr.due_at, 'status', pr.status,
    'checkpoints', coalesce((SELECT jsonb_agg(jsonb_build_object('checkpointId', c.checkpoint_id, 'name', c.name, 'sequence', rc.sequence,
                     'photoRequired', coalesce(rc.photo_required, false), 'state', 'PENDING') ORDER BY rc.sequence)
                 FROM security.route_checkpoint rc JOIN security.checkpoint c ON c.checkpoint_id = rc.checkpoint_id WHERE rc.route_id = pr.route_id), '[]'::jsonb))
FROM security.patrol_round pr JOIN security.patrol_route rt ON rt.route_id = pr.route_id WHERE pr.round_id = :result::bigint;

-- name: scanCheckpoint write
-- Checkpoint by tag or id, on this round's route; the round completes when every checkpoint has a scan
WITH b AS (SELECT :body::jsonb AS j),
     pr AS (SELECT * FROM security.patrol_round WHERE round_id = :roundId::bigint AND status = 'IN_PROGRESS' AND guard_user_id = :me::bigint),
     cp AS (SELECT c.* FROM security.checkpoint c JOIN security.route_checkpoint rc ON rc.checkpoint_id = c.checkpoint_id, pr, b
             WHERE rc.route_id = pr.route_id AND (c.checkpoint_id = (b.j ->> 'checkpointId')::bigint OR c.tag_uid = b.j ->> 'tagUid') LIMIT 1),
     ins AS (INSERT INTO security.patrol_scan (school_id, round_id, checkpoint_id, scanned_at, lat, lng, method, photo_url, note)
             SELECT pr.school_id, pr.round_id, cp.checkpoint_id, coalesce((b.j ->> 'scannedAt')::timestamptz, now()), (b.j ->> 'lat')::numeric, (b.j ->> 'lng')::numeric,
                    coalesce(b.j ->> 'method', 'NFC'), b.j ->> 'photoUrl', b.j ->> 'note'
               FROM pr, cp, b WHERE coalesce(b.j ->> 'method', 'NFC') <> 'MANUAL_WITH_REASON' OR coalesce(b.j ->> 'note', '') <> '' RETURNING round_id)
SELECT round_id AS result FROM ins;
-- then
WITH done AS (UPDATE security.patrol_round pr SET status = CASE WHEN now() > pr.due_at + interval '30 minutes' THEN 'LATE' ELSE 'COMPLETED' END, completed_at = now()
               WHERE pr.round_id = :result::bigint AND pr.status = 'IN_PROGRESS'
                 AND NOT EXISTS (SELECT 1 FROM security.route_checkpoint rc WHERE rc.route_id = pr.route_id
                                   AND NOT EXISTS (SELECT 1 FROM security.patrol_scan s WHERE s.round_id = pr.round_id AND s.checkpoint_id = rc.checkpoint_id))
              RETURNING status)
SELECT jsonb_build_object('roundId', pr.round_id, 'route', rt.name, 'dueAt', pr.due_at, 'status', coalesce((SELECT status FROM done), pr.status),
    'checkpoints', coalesce((SELECT jsonb_agg(jsonb_strip_nulls(jsonb_build_object('checkpointId', c.checkpoint_id, 'name', c.name, 'sequence', rc.sequence,
                     'scannedAt', (SELECT min(s.scanned_at) FROM security.patrol_scan s WHERE s.round_id = pr.round_id AND s.checkpoint_id = c.checkpoint_id),
                     'photoRequired', coalesce(rc.photo_required, false),
                     'state', CASE WHEN EXISTS (SELECT 1 FROM security.patrol_scan s WHERE s.round_id = pr.round_id AND s.checkpoint_id = c.checkpoint_id) THEN 'DONE' ELSE 'PENDING' END))
                   ORDER BY rc.sequence)
                 FROM security.route_checkpoint rc JOIN security.checkpoint c ON c.checkpoint_id = rc.checkpoint_id WHERE rc.route_id = pr.route_id), '[]'::jsonb))
FROM security.patrol_round pr JOIN security.patrol_route rt ON rt.route_id = pr.route_id WHERE pr.round_id = :result::bigint;

-- name: answerWelfarePing write
WITH up AS (UPDATE security.welfare_ping w SET responded_at = now(), status = 'OK'
              FROM hr.roster_entry re WHERE w.ping_id = :pingId::bigint AND re.roster_entry_id = w.roster_entry_id AND re.user_id = :me::bigint
               AND w.responded_at IS NULL RETURNING w.*)
SELECT api.camel(to_jsonb(up)) FROM up;

-- name: logVehicleOut write
WITH up AS (UPDATE security.vehicle_entry SET out_at = now() WHERE vehicle_entry_id = :vehicleEntryId::bigint AND out_at IS NULL RETURNING *)
SELECT api.camel(to_jsonb(up)) FROM up;

-- name: checkInVisitor write
WITH b AS (SELECT :body::jsonb AS j),
     found AS (SELECT v.* FROM frontoffice.visitor v, b WHERE regexp_replace(v.phone, '\D', '', 'g') = regexp_replace(b.j ->> 'phone', '\D', '', 'g') LIMIT 1),
     newv AS (INSERT INTO frontoffice.visitor (school_id, name, phone, photo_url, id_proof_type, id_proof_last4)
              SELECT :school::bigint, b.j ->> 'name', b.j ->> 'phone', b.j ->> 'photoUrl', b.j ->> 'idProofType', b.j ->> 'idProofLast4'
                FROM b WHERE NOT EXISTS (SELECT 1 FROM found) RETURNING visitor_id),
     vis AS (SELECT visitor_id FROM found WHERE NOT coalesce(is_blacklisted, false) UNION ALL SELECT visitor_id FROM newv),
     ins AS (INSERT INTO frontoffice.visit (school_id, visitor_id, purpose, host_user_id, student_id, pickup_person_id, badge_number, check_in_at)
             SELECT :school::bigint, vis.visitor_id, coalesce(b.j ->> 'purpose', 'OTHER'), (b.j ->> 'hostUserId')::bigint, (b.j ->> 'studentId')::bigint,
                    (b.j ->> 'pickupPersonId')::bigint, b.j ->> 'badgeNumber', now() FROM vis, b RETURNING *)
SELECT api.camel(to_jsonb(ins)) FROM ins;

-- name: checkOutVisitor write
WITH up AS (UPDATE frontoffice.visit SET check_out_at = now() WHERE visit_id = :visitId::bigint AND check_out_at IS NULL RETURNING *)
SELECT api.camel(to_jsonb(up)) FROM up;

-- name: returnKey write
WITH up AS (UPDATE security.key_movement SET returned_at = now() WHERE key_movement_id = :keyMovementId::bigint AND returned_at IS NULL RETURNING *)
SELECT api.camel(to_jsonb(up)) FROM up;

-- name: acceptHandover write
-- The incoming guard (whose roster entry the handover names) accepts it
WITH up AS (UPDATE security.shift_handover h SET accepted = true
              FROM hr.roster_entry re WHERE h.handover_id = :handoverId::bigint AND re.roster_entry_id = h.to_roster_entry_id AND re.user_id = :me::bigint
               AND NOT coalesce(h.accepted, false) RETURNING h.*)
SELECT api.camel(to_jsonb(up)) FROM up;

-- name: scanGatePass
-- Gate verdict for a scanned outing pass (gate_pass_token) or early-leave pass ("GP:<id>"); read-only — the
-- movement is recorded with recordGateMovement / releaseDayScholar
WITH b AS (SELECT :body::jsonb AS j),
     o AS (SELECT o.* FROM hostel.outing_request o, b WHERE o.gate_pass_token = b.j ->> 'code'),
     gp AS (SELECT g.* FROM frontoffice.gate_pass g, b WHERE b.j ->> 'code' ~ '^GP:\d+$' AND g.gate_pass_id = substring(b.j ->> 'code' FROM 4)::bigint),
     dir AS (SELECT coalesce(j ->> 'direction', 'OUT') AS d FROM b)
SELECT coalesce(
    (SELECT jsonb_strip_nulls(jsonb_build_object(
        'verdict', CASE WHEN dir.d = 'OUT' AND o.status = 'APPROVED' AND o.depart_planned_at <= now() + interval '2 hours' THEN 'ALLOWED'
                        WHEN dir.d = 'IN' AND o.status IN ('OUT', 'OVERDUE') THEN 'ALLOWED' ELSE 'STOP' END,
        'reason', CASE WHEN dir.d = 'OUT' AND o.status = 'APPROVED' AND o.depart_planned_at > now() + interval '2 hours' THEN 'Too early'
                       WHEN dir.d = 'OUT' AND o.status <> 'APPROVED' THEN 'Pass ' || lower(o.status)
                       WHEN dir.d = 'IN' AND o.status NOT IN ('OUT', 'OVERDUE') THEN 'Not marked out' END,
        'student', api.student_ref(o.student_id), 'classSection', api.section_label((SELECT class_section_id FROM academics.student WHERE student_id = o.student_id)),
        'passType', o.outing_type, 'outingId', o.outing_id,
        'pickupPerson', (SELECT jsonb_strip_nulls(jsonb_build_object('name', pp.name, 'photoUrl', pp.photo_url, 'label', pp.relationship))
                           FROM frontoffice.pickup_person pp WHERE pp.pickup_person_id = o.pickup_person_id),
        'requiresParentOtp', coalesce((SELECT pp.requires_parent_otp FROM frontoffice.pickup_person pp WHERE pp.pickup_person_id = o.pickup_person_id), false)))
       FROM o, dir),
    (SELECT jsonb_strip_nulls(jsonb_build_object('verdict', CASE WHEN gp.approved_by_user_id IS NOT NULL AND gp.out_at IS NULL THEN 'ALLOWED' ELSE 'STOP' END,
        'reason', CASE WHEN gp.approved_by_user_id IS NULL THEN 'Not approved' WHEN gp.out_at IS NOT NULL THEN 'Already used' END,
        'student', api.student_ref(gp.student_id), 'passType', 'EARLY_LEAVE', 'gatePassId', gp.gate_pass_id,
        'requiresParentOtp', gp.verification = 'PARENT_OTP'))
       FROM gp),
    jsonb_build_object('verdict', 'UNVERIFIED', 'reason', 'Unknown pass'));
