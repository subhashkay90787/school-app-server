-- Screen queries for /api/v1/driver: the caller's own trips only.

-- name: getTrip
SELECT jsonb_build_object('trip', api.camel(to_jsonb(t)),
    'nextStop', (SELECT jsonb_build_object('stopId', s.stop_id, 'name', s.name, 'sequence', s.sequence,
                         'eta', (t.trip_date + CASE WHEN t.direction = 'DROP' THEN s.drop_time ELSE s.pickup_time END)::timestamptz, 'reached', false, 'students', '[]'::jsonb)
                   FROM transport.stop s WHERE s.route_id = t.route_id AND NOT EXISTS (SELECT 1 FROM transport.boarding b WHERE b.trip_id = t.trip_id AND b.stop_id = s.stop_id)
                  ORDER BY CASE WHEN t.direction = 'DROP' THEN -s.sequence ELSE s.sequence END LIMIT 1),
    'stops', coalesce((SELECT jsonb_agg(jsonb_build_object('stopId', s.stop_id, 'name', s.name, 'sequence', s.sequence,
                     'eta', (t.trip_date + CASE WHEN t.direction = 'DROP' THEN s.drop_time ELSE s.pickup_time END)::timestamptz,
                     'reached', EXISTS (SELECT 1 FROM transport.boarding b WHERE b.trip_id = t.trip_id AND b.stop_id = s.stop_id),
                     'students', coalesce((SELECT jsonb_agg(jsonb_build_object('studentId', sr.student_id, 'name', api.student_ref(sr.student_id) ->> 'name',
                                     'event', coalesce((SELECT b.event FROM transport.boarding b WHERE b.trip_id = t.trip_id AND b.student_id = sr.student_id
                                                         ORDER BY b.event_at DESC LIMIT 1), 'PENDING')) ORDER BY sr.student_id)
                                   FROM transport.student_route sr WHERE sr.route_id = t.route_id AND sr.status = 'ACTIVE'
                                    AND s.stop_id = CASE WHEN t.direction = 'DROP' THEN sr.drop_stop_id ELSE sr.pickup_stop_id END), '[]'::jsonb))
                   ORDER BY CASE WHEN t.direction = 'DROP' THEN -s.sequence ELSE s.sequence END)
                 FROM transport.stop s WHERE s.route_id = t.route_id), '[]'::jsonb))
FROM transport.trip t WHERE t.trip_id = :tripId::bigint AND t.driver_user_id = :me::bigint;

-- name: startTrip write
WITH up AS (UPDATE transport.trip SET status = 'RUNNING', started_at = now()
             WHERE trip_id = :tripId::bigint AND driver_user_id = :me::bigint AND status = 'PLANNED' AND trip_date = current_date RETURNING trip_id)
SELECT trip_id AS result FROM up;
-- then
SELECT jsonb_build_object('trip', api.camel(to_jsonb(t)), 'stops', '[]'::jsonb) FROM transport.trip t WHERE t.trip_id = :result::bigint;

-- name: pushLocations write
WITH t AS (SELECT * FROM transport.trip WHERE trip_id = :tripId::bigint AND driver_user_id = :me::bigint AND status = 'RUNNING'),
     ins AS (INSERT INTO transport.trip_location (school_id, trip_id, recorded_at, lat, lng, speed_kmph)
             SELECT t.school_id, t.trip_id, coalesce((x ->> 'recordedAt')::timestamptz, now()), (x ->> 'lat')::numeric, (x ->> 'lng')::numeric, (x ->> 'speedKmph')::numeric
               FROM t, jsonb_array_elements(coalesce(:body::jsonb -> 'points', '[]'::jsonb)) x
              WHERE (x ->> 'lat') IS NOT NULL AND (x ->> 'lng') IS NOT NULL RETURNING 1)
SELECT CASE WHEN EXISTS (SELECT 1 FROM t) AND (SELECT count(*) FROM ins) >= 0 THEN '{}' END;

-- name: markBoarding write
-- Students on this route only
WITH b AS (SELECT :body::jsonb AS j),
     t AS (SELECT * FROM transport.trip WHERE trip_id = :tripId::bigint AND driver_user_id = :me::bigint AND status = 'RUNNING'),
     ins AS (INSERT INTO transport.boarding (school_id, trip_id, student_id, stop_id, event, event_at, source, marked_by_user_id)
             SELECT t.school_id, t.trip_id, (b.j ->> 'studentId')::bigint, (b.j ->> 'stopId')::bigint, b.j ->> 'event',
                    coalesce((b.j ->> 'eventAt')::timestamptz, now()), coalesce(b.j ->> 'source', 'MANUAL'), :me::bigint
               FROM t, b WHERE (b.j ->> 'studentId')::bigint IN (SELECT sr.student_id FROM transport.student_route sr WHERE sr.route_id = t.route_id AND sr.status = 'ACTIVE')
             RETURNING trip_id)
SELECT trip_id AS result FROM ins;
-- then
SELECT jsonb_build_object('trip', api.camel(to_jsonb(t)),
    'stops', coalesce((SELECT jsonb_agg(jsonb_build_object('stopId', s.stop_id, 'name', s.name, 'sequence', s.sequence,
                     'reached', EXISTS (SELECT 1 FROM transport.boarding b WHERE b.trip_id = t.trip_id AND b.stop_id = s.stop_id),
                     'students', coalesce((SELECT jsonb_agg(jsonb_build_object('studentId', sr.student_id, 'name', api.student_ref(sr.student_id) ->> 'name',
                                     'event', coalesce((SELECT b.event FROM transport.boarding b WHERE b.trip_id = t.trip_id AND b.student_id = sr.student_id
                                                         ORDER BY b.event_at DESC LIMIT 1), 'PENDING')))
                                   FROM transport.student_route sr WHERE sr.route_id = t.route_id AND sr.status = 'ACTIVE'
                                    AND s.stop_id = CASE WHEN t.direction = 'DROP' THEN sr.drop_stop_id ELSE sr.pickup_stop_id END), '[]'::jsonb))
                   ORDER BY s.sequence) FROM transport.stop s WHERE s.route_id = t.route_id), '[]'::jsonb))
FROM transport.trip t WHERE t.trip_id = :result::bigint;

-- name: endTrip write
WITH up AS (UPDATE transport.trip SET status = 'COMPLETED', ended_at = now()
             WHERE trip_id = :tripId::bigint AND driver_user_id = :me::bigint AND status = 'RUNNING' RETURNING trip_id)
SELECT trip_id AS result FROM up;
-- then
SELECT jsonb_build_object('trip', api.camel(to_jsonb(t)), 'stops', '[]'::jsonb) FROM transport.trip t WHERE t.trip_id = :result::bigint;
