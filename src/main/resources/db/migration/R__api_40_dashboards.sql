-- KPI builders for the leadership dashboards (administrator, principal). Repeatable; SECURITY INVOKER.

CREATE OR REPLACE FUNCTION api.kpi(p_code TEXT, p_label TEXT, p_value NUMERIC, p_unit TEXT DEFAULT NULL,
                                   p_delta NUMERIC DEFAULT NULL, p_target NUMERIC DEFAULT NULL, p_trend JSONB DEFAULT NULL) RETURNS JSONB
    LANGUAGE sql IMMUTABLE AS $$
    SELECT jsonb_strip_nulls(jsonb_build_object('code', p_code, 'label', p_label, 'value', coalesce(p_value, 0), 'unit', p_unit,
                                                'delta', p_delta, 'target', p_target, 'trend', p_trend))
$$;

-- Student attendance % for a branch on a day (present + late over marked)
CREATE OR REPLACE FUNCTION api.student_attendance_pct(p_school_id BIGINT, p_date DATE) RETURNS NUMERIC
    LANGUAGE sql STABLE AS $$
    SELECT round(100.0 * count(*) FILTER (WHERE dp.status IN ('PRESENT', 'LATE', 'ON_DUTY')) / nullif(count(*) FILTER (WHERE dp.status NOT IN ('HOLIDAY', 'WEEKLY_OFF')), 0), 1)
    FROM operations.daily_presence dp WHERE dp.school_id = p_school_id AND dp.person_kind = 'STUDENT' AND dp.presence_date = p_date
$$;

-- Branch KPI row: students, attendance today (+ 7-day trend), collections this month, overdue, staff present, hostel occupancy
CREATE OR REPLACE FUNCTION api.branch_kpis(p_school_id BIGINT) RETURNS JSONB
    LANGUAGE sql STABLE AS $$
    SELECT jsonb_build_array(
        api.kpi('STUDENTS', 'Students', (SELECT count(*) FROM academics.student s WHERE s.school_id = p_school_id AND s.status = 'ACTIVE')),
        api.kpi('ATTENDANCE_TODAY', 'Attendance today', api.student_attendance_pct(p_school_id, current_date), '%',
                api.student_attendance_pct(p_school_id, current_date) - api.student_attendance_pct(p_school_id, current_date - 1), 95,
                (SELECT jsonb_agg(coalesce(api.student_attendance_pct(p_school_id, d::date), 0) ORDER BY d)
                   FROM generate_series(current_date - 6, current_date, interval '1 day') d)),
        api.kpi('COLLECTED_MTD', 'Collected this month',
                (SELECT coalesce(sum(p.amount), 0) FROM finance.payment p WHERE p.school_id = p_school_id AND p.status = 'SUCCESS'
                    AND p.paid_at >= date_trunc('month', now())), 'INR'),
        api.kpi('OVERDUE', 'Fees overdue',
                (SELECT coalesce(sum(f.remaining_due), 0) FROM finance.fee f WHERE f.school_id = p_school_id AND f.status IN ('DUE', 'PART_PAID')
                    AND f.due_date < current_date), 'INR'),
        api.kpi('STAFF_PRESENT', 'Staff present',
                (SELECT round(100.0 * count(*) FILTER (WHERE dp.status IN ('PRESENT', 'LATE', 'ON_DUTY')) / nullif(count(*), 0), 1)
                   FROM operations.daily_presence dp WHERE dp.school_id = p_school_id AND dp.person_kind = 'STAFF' AND dp.presence_date = current_date), '%'),
        api.kpi('HOSTEL_OCCUPANCY', 'Hostel occupancy',
                (SELECT round(100.0 * count(*) FILTER (WHERE b.status = 'OCCUPIED') / nullif(count(*) FILTER (WHERE b.status <> 'MAINTENANCE'), 0), 1)
                   FROM hostel.bed b WHERE b.school_id = p_school_id), '%'))
$$;

GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA api TO schoolcrm_app;
