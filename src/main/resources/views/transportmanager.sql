-- Screen queries for /api/v1/transport.

-- name: getHome
SELECT api.feed('TRANSPORT_MANAGER',
    (SELECT api.card('stopped', 'CRITICAL', 'BUS_STOPPED', 'Bus not moving', string_agg(r.name, ', '), count(*), 'URGENT', 'live')
       FROM transport.trip t JOIN transport.route r ON r.route_id = t.route_id
      WHERE t.status = 'RUNNING' AND (SELECT max(l.recorded_at) FROM transport.trip_location l WHERE l.trip_id = t.trip_id) < now() - interval '10 minutes'),
    (SELECT api.card('expiring', 'NEEDS_YOU', 'COMPLIANCE', 'Vehicle papers expiring in 30 days', string_agg(DISTINCT v.registration_number, ', '), count(DISTINCT v.vehicle_id), 'ACTION', 'compliance/expiring')
       FROM transport.vehicle v WHERE v.status = 'ACTIVE' AND least(v.insurance_valid_till, v.fitness_valid_till, v.permit_valid_till, v.puc_valid_till) <= current_date + 30),
    (SELECT api.card('no-driver', 'NEEDS_YOU', 'TRIPS_NO_DRIVER', 'Trips today without a driver', NULL, count(*), 'ACTION', 'trips')
       FROM transport.trip t WHERE t.trip_date = current_date AND t.driver_user_id IS NULL AND t.status = 'PLANNED'),
    (SELECT api.card('running', 'NOW', 'TRIPS_RUNNING', 'Trips running', NULL, count(*), 'INFO', 'live')
       FROM transport.trip t WHERE t.status = 'RUNNING'),
    (SELECT api.card('no-shows', 'TODAY', 'NO_SHOWS', 'No-shows today', NULL, count(*), 'INFO', 'trips')
       FROM transport.boarding b JOIN transport.trip t ON t.trip_id = b.trip_id WHERE t.trip_date = current_date AND b.event = 'NO_SHOW'));

-- name: getLiveTrips
SELECT coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object('tripId', t.trip_id, 'route', r.name, 'driver', api.person(t.driver_user_id), 'status', t.status,
       'lat', l.lat, 'lng', l.lng, 'lastUpdateAt', l.recorded_at,
       'stoppedMinutes', CASE WHEN coalesce(l.speed_kmph, 0) < 2 AND l.recorded_at IS NOT NULL THEN (extract(epoch FROM now() - l.recorded_at) / 60)::int END,
       'onTime', NOT EXISTS (SELECT 1 FROM transport.stop s WHERE s.route_id = t.route_id
                               AND (current_date + CASE WHEN t.direction = 'DROP' THEN s.drop_time ELSE s.pickup_time END)::timestamp < localtimestamp - interval '10 minutes'
                               AND NOT EXISTS (SELECT 1 FROM transport.boarding b WHERE b.trip_id = t.trip_id AND b.stop_id = s.stop_id))))
       ORDER BY r.name), '[]'::jsonb)
FROM transport.trip t JOIN transport.route r ON r.route_id = t.route_id
LEFT JOIN LATERAL (SELECT * FROM transport.trip_location x WHERE x.trip_id = t.trip_id ORDER BY x.recorded_at DESC LIMIT 1) l ON true
WHERE t.trip_date = current_date AND t.status IN ('RUNNING', 'PLANNED');

-- name: listExpiringCompliance
WITH v AS (SELECT * FROM transport.vehicle WHERE status = 'ACTIVE'),
     d AS (SELECT vehicle_id, registration_number, 'INSURANCE' AS kind, insurance_valid_till AS till FROM v
           UNION ALL SELECT vehicle_id, registration_number, 'FITNESS', fitness_valid_till FROM v
           UNION ALL SELECT vehicle_id, registration_number, 'PERMIT', permit_valid_till FROM v
           UNION ALL SELECT vehicle_id, registration_number, 'PUC', puc_valid_till FROM v)
SELECT coalesce(jsonb_agg(jsonb_build_object('vehicleId', vehicle_id, 'registrationNumber', registration_number, 'kind', kind, 'validTill', till,
       'daysLeft', till - current_date) ORDER BY till), '[]'::jsonb)
FROM d WHERE till IS NOT NULL AND till <= current_date + coalesce(:days::int, 30);

-- name: listDrivers
SELECT coalesce(jsonb_agg(api.person(e.user_id, e.designation) ORDER BY api.user_name(e.user_id)), '[]'::jsonb)
FROM hr.employee_profile e WHERE e.status = 'ACTIVE' AND e.staff_category = 'TRANSPORT'
  AND (e.designation ILIKE '%driver%' OR EXISTS (SELECT 1 FROM transport.route r WHERE r.driver_user_id = e.user_id));

-- name: saveStops write
-- Stops by sequence: existing sequences are updated, new ones added (stops in use are never deleted here)
WITH r AS (SELECT * FROM transport.route WHERE route_id = :routeId::bigint),
     s AS (SELECT x ->> 'name' AS name, (x ->> 'lat')::numeric AS lat, (x ->> 'lng')::numeric AS lng, (x ->> 'sequence')::int AS seq,
                  (x ->> 'pickupTime')::time AS pt, (x ->> 'dropTime')::time AS dt, (x ->> 'feeStructureId')::bigint AS fs
             FROM jsonb_array_elements(coalesce(:body::jsonb -> 'stops', '[]'::jsonb)) x),
     up AS (UPDATE transport.stop t SET name = coalesce(s.name, t.name), lat = coalesce(s.lat, t.lat), lng = coalesce(s.lng, t.lng),
                   pickup_time = coalesce(s.pt, t.pickup_time), drop_time = coalesce(s.dt, t.drop_time), fee_structure_id = coalesce(s.fs, t.fee_structure_id)
              FROM s, r WHERE t.route_id = r.route_id AND t.sequence = s.seq RETURNING t.sequence),
     ins AS (INSERT INTO transport.stop (school_id, route_id, name, lat, lng, sequence, pickup_time, drop_time, fee_structure_id)
             SELECT r.school_id, r.route_id, s.name, s.lat, s.lng, s.seq, s.pt, s.dt, s.fs FROM r, s
              WHERE NOT EXISTS (SELECT 1 FROM transport.stop t WHERE t.route_id = r.route_id AND t.sequence = s.seq) RETURNING 1)
SELECT r.route_id AS result FROM r WHERE (SELECT count(*) FROM up) + (SELECT count(*) FROM ins) >= 0;
-- then
SELECT coalesce(jsonb_agg(api.camel(to_jsonb(t)) ORDER BY t.sequence), '[]'::jsonb) FROM transport.stop t WHERE t.route_id = :result::bigint;
