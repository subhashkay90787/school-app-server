-- Screen queries for /api/v1/security-supervisor.

-- name: getHome
SELECT api.feed('SECURITY_SUPERVISOR',
    (SELECT api.card('unmanned', 'CRITICAL', 'POST_UNMANNED', 'Posts without a guard', string_agg(p.code, ', '), count(*), 'CRITICAL', 'live-posts')
       FROM hr.post p WHERE p.post_type IN ('GATE', 'PATROL', 'HOSTEL_NIGHT')
        AND NOT EXISTS (SELECT 1 FROM hr.roster_entry re WHERE re.post_id = p.post_id AND re.duty_date = current_date AND re.status = 'ON_DUTY')),
    (SELECT api.card('welfare', 'CRITICAL', 'WELFARE_MISSED', 'Welfare checks not answered', NULL, count(*), 'URGENT', 'live-posts')
       FROM security.welfare_ping w WHERE w.responded_at IS NULL AND w.sent_at < now() - interval '10 minutes' AND w.sent_at > now() - interval '12 hours'),
    (SELECT api.card('occurrences', 'NEEDS_YOU', 'OCCURRENCES', 'Open occurrences', string_agg(DISTINCT o.occurrence_type, ', '), count(*), 'ACTION', 'occurrences')
       FROM security.occurrence o WHERE o.status = 'OPEN'),
    (SELECT api.card('missed-rounds', 'NEEDS_YOU', 'PATROL_MISSED', 'Missed or late rounds today', NULL, count(*), 'ACTION', 'patrols')
       FROM security.patrol_round pr WHERE pr.due_at::date = current_date AND (pr.status IN ('MISSED', 'LATE')
                                                                             OR (pr.status = 'DUE' AND pr.due_at < now() - interval '30 minutes'))),
    (SELECT api.card('keys', 'NOW', 'KEYS_OUT', 'Keys overdue', string_agg(k.code, ', '), count(*), 'ACTION', 'keys')
       FROM security.key_movement m JOIN security.key k ON k.key_id = m.key_id WHERE m.returned_at IS NULL AND m.due_back_at < now()),
    (SELECT api.card('rounds', 'TODAY', 'PATROLS', 'Rounds completed today', NULL, count(*), 'INFO', 'patrols')
       FROM security.patrol_round pr WHERE pr.due_at::date = current_date AND pr.status = 'COMPLETED'));

-- name: listLivePosts
SELECT coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object('postId', p.post_id, 'post', p.code, 'guard', api.person(re.user_id),
       'punchedInAt', re.reported_at,
       'lastActivityAt', greatest(re.reported_at, (SELECT max(w.responded_at) FROM security.welfare_ping w WHERE w.roster_entry_id = re.roster_entry_id),
                                  (SELECT max(s.scanned_at) FROM security.patrol_scan s JOIN security.patrol_round pr ON pr.round_id = s.round_id
                                    WHERE pr.guard_user_id = re.user_id AND s.scanned_at::date = current_date)),
       'state', CASE WHEN re.roster_entry_id IS NULL THEN 'UNMANNED' WHEN re.status = 'PLANNED' THEN 'LATE' ELSE 'MANNED' END)) ORDER BY p.code), '[]'::jsonb)
FROM hr.post p
LEFT JOIN LATERAL (SELECT * FROM hr.roster_entry r WHERE r.post_id = p.post_id AND r.duty_date = current_date AND r.status IN ('ON_DUTY', 'PLANNED')
                    ORDER BY (r.status = 'ON_DUTY') DESC LIMIT 1) re ON true
WHERE p.post_type IN ('GATE', 'PATROL', 'CCTV', 'HOSTEL_NIGHT', 'HOSTEL_DAY');

-- name: getRoster
WITH w AS (SELECT coalesce(:weekStart::date, date_trunc('week', current_date)::date) AS s),
     days AS (SELECT (w.s + n) AS d FROM w, generate_series(0, 6) n),
     people AS (SELECT e.user_id FROM hr.employee_profile e WHERE e.status = 'ACTIVE' AND e.staff_category = 'SECURITY'),
     cells AS (SELECT r.*, sh.code AS shift_code, p.code AS post_code FROM hr.roster_entry r JOIN hr.shift sh ON sh.shift_id = r.shift_id
                 LEFT JOIN hr.post p ON p.post_id = r.post_id, w
                WHERE r.duty_date BETWEEN w.s AND w.s + 6 AND r.user_id IN (SELECT user_id FROM people) AND r.status <> 'CANCELLED')
SELECT jsonb_build_object('weekStart', (SELECT s FROM w),
    'people', coalesce((SELECT jsonb_agg(api.person(user_id) ORDER BY api.user_name(user_id)) FROM people), '[]'::jsonb),
    'cells', coalesce((SELECT jsonb_agg(jsonb_strip_nulls(jsonb_build_object('userId', user_id, 'date', duty_date, 'rosterEntryId', roster_entry_id,
                     'shiftCode', shift_code, 'postCode', post_code, 'status', status)) ORDER BY duty_date, user_id) FROM cells), '[]'::jsonb),
    'gaps', coalesce((SELECT jsonb_agg(jsonb_build_object('date', days.d, 'postCode', p.code, 'required', coalesce(p.required_per_shift, 1),
                     'assigned', (SELECT count(*) FROM cells c WHERE c.duty_date = days.d AND c.post_id = p.post_id)) ORDER BY days.d, p.code)
                FROM days, hr.post p WHERE p.post_type IN ('GATE', 'PATROL', 'CCTV')
                 AND (SELECT count(*) FROM cells c WHERE c.duty_date = days.d AND c.post_id = p.post_id) < coalesce(p.required_per_shift, 1)), '[]'::jsonb),
    'conflicts', '[]'::jsonb);

-- name: updateRoster write
WITH b AS (SELECT :body::jsonb AS j),
     s AS (SELECT (x ->> 'userId')::bigint AS uid, (x ->> 'date')::date AS d, (x ->> 'shiftId')::bigint AS shift, (x ->> 'postId')::bigint AS post
             FROM b, jsonb_array_elements(coalesce(b.j -> 'set', '[]'::jsonb)) x
            WHERE (x ->> 'userId')::bigint IN (SELECT user_id FROM hr.employee_profile WHERE staff_category = 'SECURITY')),
     rm AS (DELETE FROM hr.roster_entry r USING b WHERE r.status = 'PLANNED'
             AND r.user_id IN (SELECT user_id FROM hr.employee_profile WHERE staff_category = 'SECURITY')
             AND (r.roster_entry_id IN (SELECT jsonb_array_elements_text(coalesce(b.j -> 'remove', '[]'::jsonb))::bigint)
                  OR (r.user_id, r.duty_date) IN (SELECT uid, d FROM s)) RETURNING 1),
     ins AS (INSERT INTO hr.roster_entry (school_id, user_id, shift_id, post_id, duty_date, status)
             SELECT :school::bigint, s.uid, s.shift, s.post, s.d, 'PLANNED' FROM s
              WHERE NOT EXISTS (SELECT 1 FROM hr.roster_entry r WHERE r.user_id = s.uid AND r.duty_date = s.d AND r.status <> 'PLANNED') RETURNING 1)
SELECT coalesce((SELECT min(d) FROM s), current_date) AS result WHERE (SELECT count(*) FROM rm) + (SELECT count(*) FROM ins) >= 0;
-- then
WITH w AS (SELECT date_trunc('week', :result::date)::date AS s),
     cells AS (SELECT r.*, sh.code AS shift_code, p.code AS post_code FROM hr.roster_entry r JOIN hr.shift sh ON sh.shift_id = r.shift_id
                 LEFT JOIN hr.post p ON p.post_id = r.post_id, w
                WHERE r.duty_date BETWEEN w.s AND w.s + 6 AND r.status <> 'CANCELLED'
                  AND r.user_id IN (SELECT user_id FROM hr.employee_profile WHERE staff_category = 'SECURITY'))
SELECT jsonb_build_object('weekStart', (SELECT s FROM w),
    'people', coalesce((SELECT jsonb_agg(DISTINCT api.person(user_id)) FROM cells), '[]'::jsonb),
    'cells', coalesce((SELECT jsonb_agg(jsonb_strip_nulls(jsonb_build_object('userId', user_id, 'date', duty_date, 'rosterEntryId', roster_entry_id,
                     'shiftCode', shift_code, 'postCode', post_code, 'status', status)) ORDER BY duty_date, user_id) FROM cells), '[]'::jsonb),
    'gaps', '[]'::jsonb, 'conflicts', '[]'::jsonb);

-- name: getPatrolCompliance
WITH d AS (SELECT coalesce(:date::date, current_date) AS day),
     r AS (SELECT pr.*, rt.name AS route, (pr.status = 'DUE' AND pr.due_at < now() - make_interval(mins => coalesce(rt.max_round_minutes, 30))) AS overdue
             FROM security.patrol_round pr JOIN security.patrol_route rt ON rt.route_id = pr.route_id, d WHERE pr.due_at::date = d.day)
SELECT jsonb_build_object('date', (SELECT day FROM d), 'rounds', (SELECT count(*) FROM r),
    'completed', (SELECT count(*) FROM r WHERE status = 'COMPLETED'), 'late', (SELECT count(*) FROM r WHERE status = 'LATE'),
    'missed', (SELECT count(*) FROM r WHERE status = 'MISSED' OR overdue),
    'pct', (SELECT round(100.0 * count(*) FILTER (WHERE status = 'COMPLETED') / nullif(count(*) FILTER (WHERE status <> 'DUE' OR overdue), 0), 1) FROM r),
    'byRoute', coalesce((SELECT jsonb_object_agg(route, jsonb_build_object('rounds', n, 'completed', c)) FROM (
                   SELECT route, count(*) AS n, count(*) FILTER (WHERE status = 'COMPLETED') AS c FROM r GROUP BY route) x), '{}'::jsonb));

-- name: updateOccurrence write
WITH b AS (SELECT :body::jsonb AS j),
     up AS (UPDATE security.occurrence o SET status = coalesce(b.j ->> 'status', o.status),
                   escalated_to_user_id = coalesce((b.j ->> 'escalatedToUserId')::bigint, o.escalated_to_user_id),
                   description = CASE WHEN coalesce(b.j ->> 'note', '') <> '' THEN concat_ws(E'\n', o.description, b.j ->> 'note') ELSE o.description END
              FROM b WHERE o.occurrence_id = :occurrenceId::bigint AND o.status <> 'RESOLVED' RETURNING o.*)
SELECT api.camel(to_jsonb(up)) FROM up;

-- name: listKeys
SELECT coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object('key', api.camel(to_jsonb(k)), 'issuedTo', api.person(m.issued_to_user_id),
       'issuedAt', m.issued_at, 'dueBackAt', m.due_back_at, 'overdue', m.key_movement_id IS NOT NULL AND m.due_back_at < now()))
       ORDER BY (m.due_back_at < now()) DESC NULLS LAST, k.code), '[]'::jsonb)
FROM security.key k
LEFT JOIN LATERAL (SELECT * FROM security.key_movement km WHERE km.key_id = k.key_id AND km.returned_at IS NULL ORDER BY km.issued_at DESC LIMIT 1) m ON true;

-- name: setRouteCheckpoints write
-- The route's checkpoints become exactly the list (sequence and photo rule per checkpoint)
WITH r AS (SELECT * FROM security.patrol_route WHERE route_id = :routeId::bigint),
     c AS (SELECT (x ->> 'checkpointId')::bigint AS cp, coalesce((x ->> 'sequence')::int, o::int) AS seq, coalesce((x ->> 'photoRequired')::boolean, false) AS photo
             FROM jsonb_array_elements(coalesce(:body::jsonb -> 'checkpoints', '[]'::jsonb)) WITH ORDINALITY AS t(x, o)),
     del AS (DELETE FROM security.route_checkpoint rc USING r WHERE rc.route_id = r.route_id AND rc.checkpoint_id NOT IN (SELECT cp FROM c) RETURNING 1),
     up AS (INSERT INTO security.route_checkpoint (school_id, route_id, checkpoint_id, sequence, photo_required)
            SELECT r.school_id, r.route_id, c.cp, c.seq, c.photo FROM r, c
            ON CONFLICT (school_id, route_id, checkpoint_id) DO UPDATE SET sequence = EXCLUDED.sequence, photo_required = EXCLUDED.photo_required RETURNING 1)
SELECT r.route_id AS result FROM r WHERE (SELECT count(*) FROM del) + (SELECT count(*) FROM up) >= 0;
-- then
SELECT coalesce(jsonb_agg(api.camel(to_jsonb(rc)) ORDER BY rc.sequence), '[]'::jsonb) FROM security.route_checkpoint rc WHERE rc.route_id = :result::bigint;
