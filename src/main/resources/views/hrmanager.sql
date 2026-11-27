-- Screen queries for /api/v1/hr (people, presence, roster, payroll).

-- name: getHome
SELECT api.feed('HR_MANAGER',
    (SELECT api.card('approvals', 'NEEDS_YOU', 'APPROVALS', 'Leave and corrections waiting', NULL, count(*), 'ACTION', 'approvals')
       FROM platform.flow_instance fi WHERE fi.status = 'OPEN' AND fi.current_step IN ('HR', 'HR_MANAGER')),
    (SELECT api.card('exceptions', 'NEEDS_YOU', 'PRESENCE_EXCEPTIONS', 'Presence exceptions today', NULL, count(*), 'ACTION', 'presence/exceptions')
       FROM operations.daily_presence dp WHERE dp.person_kind = 'STAFF' AND dp.presence_date = current_date AND dp.status IN ('LATE', 'ABSENT')),
    (SELECT api.card('payroll', 'NEEDS_YOU', 'PAYROLL', 'Payroll ' || r.period || ' is ' || lower(r.status), NULL, NULL, 'ACTION', 'payroll/runs/' || r.run_id)
       FROM hr.payroll_run r WHERE r.status IN ('DRAFT', 'COMPUTED') ORDER BY r.period DESC LIMIT 1),
    (SELECT api.card('on-leave', 'NOW', 'ON_LEAVE', 'On leave today', string_agg(api.user_name(lr.user_id), ', '), count(*), 'INFO', 'leave')
       FROM hr.leave_request lr WHERE lr.status = 'APPROVED' AND current_date BETWEEN lr.from_date AND lr.to_date),
    (SELECT api.card('expiring', 'TODAY', 'POLICE_VERIFICATION', 'Police verification missing', NULL, count(*), 'INFO', 'people')
       FROM hr.employee_profile e WHERE e.status = 'ACTIVE' AND e.staff_category IN ('SECURITY', 'TRANSPORT', 'HOSTEL') AND e.police_verification_on IS NULL),
    (SELECT api.card('openings', 'FEED', 'RECRUITMENT', 'Open positions', NULL, sum(o.positions), 'INFO', 'recruitment')
       FROM hr.job_opening o WHERE o.status = 'OPEN'));

-- name: getRoster
WITH w AS (SELECT coalesce(:weekStart::date, date_trunc('week', current_date)::date) AS s),
     days AS (SELECT (w.s + n) AS d FROM w, generate_series(0, 6) n),
     people AS (SELECT e.user_id FROM hr.employee_profile e LEFT JOIN academics.department dep ON dep.department_id = e.department_id
                 WHERE e.status = 'ACTIVE' AND (:department IS NULL OR dep.name = :department OR dep.department_code = :department OR e.staff_category = :department)),
     cells AS (SELECT r.*, sh.code AS shift_code, p.code AS post_code FROM hr.roster_entry r JOIN hr.shift sh ON sh.shift_id = r.shift_id
                 LEFT JOIN hr.post p ON p.post_id = r.post_id, w
                WHERE r.duty_date BETWEEN w.s AND w.s + 6 AND r.user_id IN (SELECT user_id FROM people) AND r.status <> 'CANCELLED')
SELECT jsonb_build_object('weekStart', (SELECT s FROM w),
    'people', coalesce((SELECT jsonb_agg(api.person(user_id) ORDER BY api.user_name(user_id)) FROM people), '[]'::jsonb),
    'cells', coalesce((SELECT jsonb_agg(jsonb_strip_nulls(jsonb_build_object('userId', user_id, 'date', duty_date, 'rosterEntryId', roster_entry_id,
                     'shiftCode', shift_code, 'postCode', post_code, 'status', status)) ORDER BY duty_date, user_id) FROM cells), '[]'::jsonb),
    'gaps', coalesce((SELECT jsonb_agg(jsonb_build_object('date', days.d, 'postCode', p.code, 'shiftCode', NULL, 'required', coalesce(p.required_per_shift, 1),
                     'assigned', (SELECT count(*) FROM cells c WHERE c.duty_date = days.d AND c.post_id = p.post_id)) ORDER BY days.d, p.code)
                FROM days, hr.post p WHERE (SELECT count(*) FROM cells c WHERE c.duty_date = days.d AND c.post_id = p.post_id) < coalesce(p.required_per_shift, 1)), '[]'::jsonb),
    'conflicts', coalesce((SELECT jsonb_agg(jsonb_build_object('kind', 'MAX_PER_DAY', 'message', api.user_name(c.user_id) || ' has ' || c.n || ' shifts on ' || c.duty_date,
                     'cells', jsonb_build_array(c.user_id || ':' || c.duty_date)))
                FROM (SELECT user_id, duty_date, count(*) AS n FROM cells GROUP BY user_id, duty_date HAVING count(*) > 1) c), '[]'::jsonb));

-- name: updateRoster write
-- set: one cell per person and day (replaces that day's planned entry); remove: roster entry ids (planned only)
WITH b AS (SELECT :body::jsonb AS j),
     s AS (SELECT (x ->> 'userId')::bigint AS uid, (x ->> 'date')::date AS d, (x ->> 'shiftId')::bigint AS shift, (x ->> 'postId')::bigint AS post
             FROM b, jsonb_array_elements(coalesce(b.j -> 'set', '[]'::jsonb)) x),
     rm AS (DELETE FROM hr.roster_entry r USING b WHERE r.status = 'PLANNED'
             AND (r.roster_entry_id IN (SELECT jsonb_array_elements_text(coalesce(b.j -> 'remove', '[]'::jsonb))::bigint)
                  OR (r.user_id, r.duty_date) IN (SELECT uid, d FROM s)) RETURNING 1),
     ins AS (INSERT INTO hr.roster_entry (school_id, user_id, shift_id, post_id, duty_date, status)
             SELECT :school::bigint, s.uid, s.shift, s.post, s.d, 'PLANNED' FROM s
              WHERE NOT EXISTS (SELECT 1 FROM hr.roster_entry r WHERE r.user_id = s.uid AND r.duty_date = s.d AND r.status <> 'PLANNED')
             RETURNING 1)
SELECT coalesce((SELECT min(d) FROM s), current_date) AS result WHERE (SELECT count(*) FROM rm) + (SELECT count(*) FROM ins) >= 0;
-- then
WITH w AS (SELECT date_trunc('week', :result::date)::date AS s),
     cells AS (SELECT r.*, sh.code AS shift_code, p.code AS post_code FROM hr.roster_entry r JOIN hr.shift sh ON sh.shift_id = r.shift_id
                 LEFT JOIN hr.post p ON p.post_id = r.post_id, w WHERE r.duty_date BETWEEN w.s AND w.s + 6 AND r.status <> 'CANCELLED')
SELECT jsonb_build_object('weekStart', (SELECT s FROM w),
    'people', coalesce((SELECT jsonb_agg(DISTINCT api.person(user_id)) FROM cells), '[]'::jsonb),
    'cells', coalesce((SELECT jsonb_agg(jsonb_strip_nulls(jsonb_build_object('userId', user_id, 'date', duty_date, 'rosterEntryId', roster_entry_id,
                     'shiftCode', shift_code, 'postCode', post_code, 'status', status)) ORDER BY duty_date, user_id) FROM cells), '[]'::jsonb),
    'gaps', '[]'::jsonb, 'conflicts', '[]'::jsonb);

-- name: listPresenceExceptions
WITH d AS (SELECT coalesce(:date::date, current_date) AS day)
SELECT coalesce(jsonb_agg(jsonb_build_object('person', api.person(e.user_id), 'date', d.day,
       'kind', CASE WHEN dp.status IS NULL OR dp.status = 'ABSENT' THEN 'ABSENT_NO_LEAVE'
                    WHEN dp.status = 'LATE' THEN 'LATE'
                    WHEN dp.last_out_at IS NULL AND d.day < current_date THEN 'NO_PUNCH_OUT' ELSE 'SHORT_HOURS' END,
       'minutes', coalesce(dp.late_minutes, 0)) ORDER BY api.user_name(e.user_id)), '[]'::jsonb)
FROM hr.employee_profile e CROSS JOIN d
LEFT JOIN operations.daily_presence dp ON dp.person_kind = 'STAFF' AND dp.person_id = e.user_id AND dp.presence_date = d.day
WHERE e.status = 'ACTIVE'
  AND extract(isodow FROM d.day) < 7
  AND NOT EXISTS (SELECT 1 FROM hr.leave_request lr WHERE lr.user_id = e.user_id AND lr.status = 'APPROVED' AND d.day BETWEEN lr.from_date AND lr.to_date)
  AND (dp.status IS NULL OR dp.status IN ('ABSENT', 'LATE') OR (dp.last_out_at IS NULL AND d.day < current_date AND dp.status = 'PRESENT'));

-- name: listPayrollExceptions
-- Payslips that need a look before approval: no salary structure, loss of pay, zero / negative net
SELECT coalesce(jsonb_agg(x.v ORDER BY x.v -> 'user' ->> 'name'), '[]'::jsonb) FROM (
    SELECT jsonb_build_object('user', api.person(p.user_id), 'kind', 'NO_STRUCTURE', 'message', 'No salary structure on file') AS v
      FROM hr.payslip p WHERE p.run_id = :runId::bigint AND NOT EXISTS (SELECT 1 FROM hr.salary_structure s WHERE s.user_id = p.user_id)
    UNION ALL
    SELECT jsonb_build_object('user', api.person(p.user_id), 'kind', 'LOSS_OF_PAY', 'message', p.lop_days || ' day(s) loss of pay')
      FROM hr.payslip p WHERE p.run_id = :runId::bigint AND coalesce(p.lop_days, 0) > 0
    UNION ALL
    SELECT jsonb_build_object('user', api.person(p.user_id), 'kind', 'NET_NOT_POSITIVE', 'message', 'Net pay is ' || coalesce(p.net, 0))
      FROM hr.payslip p WHERE p.run_id = :runId::bigint AND coalesce(p.net, 0) <= 0
) x
WHERE EXISTS (SELECT 1 FROM hr.payroll_run WHERE run_id = :runId::bigint);
