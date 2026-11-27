-- Screen queries for /api/v1/admin (organisation administrator). On GET with scope=ALL_BRANCHES and on
-- /branches/comparison, RLS covers every org-wide branch in the token (TenantFilter.readBranches); otherwise the
-- branch in X-School-Id. Queries use directory.school for branch names and group by school_id.

-- name: getHome
SELECT api.feed('ADMINISTRATOR',
    (SELECT api.card('critical', 'CRITICAL', 'CRITICAL_ALERT', max(n.title), max(n.body), count(*), 'CRITICAL', 'alerts')
       FROM communication.notification_recipient r JOIN communication.notification n ON n.notification_id = r.notification_id
      WHERE r.recipient_user_id = :me::bigint AND n.severity = 'CRITICAL' AND r.acknowledged_at IS NULL AND n.sent_time > now() - interval '24 hours'),
    (SELECT api.card('approvals', 'NEEDS_YOU', 'APPROVALS', 'Approvals waiting', NULL, count(*), 'ACTION', 'approvals')
       FROM platform.flow_instance fi WHERE fi.status = 'OPEN' AND fi.current_step IN ('ADMINISTRATOR', 'DIRECTOR', 'MANAGEMENT')),
    (SELECT api.card('budget-alerts', 'NEEDS_YOU', 'BUDGET_ALERT', 'Budgets past their alert level', string_agg(x.head, ', '), count(*), 'ACTION', 'finance/budgets')
       FROM (SELECT eh.name AS head FROM accounts.budget b JOIN accounts.expense_head eh ON eh.expense_head_id = b.expense_head_id
              WHERE (SELECT coalesce(sum(e.amount), 0) FROM accounts.expense e WHERE e.expense_head_id = b.expense_head_id
                       AND coalesce(e.cost_centre, '') = coalesce(b.cost_centre, '') AND e.status IN ('APPROVED', 'PAID'))
                    >= b.amount * coalesce(b.alert_at_pct, 80) / 100) x),
    (SELECT api.card('attendance', 'NOW', 'ATTENDANCE', 'Attendance today', coalesce(api.student_attendance_pct(:school::bigint, current_date)::text || '%', 'Not taken yet'),
                     NULL, 'INFO', 'overview')),
    (SELECT api.card('collections', 'TODAY', 'COLLECTIONS', 'Collected today', '₹' || to_char(coalesce(sum(p.amount), 0), 'FM99,99,99,990'), NULL, 'INFO', 'finance/collections')
       FROM finance.payment p WHERE p.status = 'SUCCESS' AND p.paid_at::date = current_date),
    (SELECT api.card('enquiries', 'FEED', 'ADMISSIONS', 'New enquiries this week', NULL, count(*), 'INFO', 'admissions/funnel')
       FROM admissions.enquiry e WHERE e.created_at > now() - interval '7 days'));

-- name: getOverview
SELECT jsonb_build_object('asOf', now(), 'scope', coalesce(:scope, 'BRANCH'),
    'kpis', CASE WHEN coalesce(:scope, 'BRANCH') = 'BRANCH' THEN api.branch_kpis(:school::bigint)
                 ELSE (SELECT jsonb_agg(api.kpi(code, label, v, unit) ORDER BY ord)
                         FROM (SELECT k ->> 'code' AS code, k ->> 'label' AS label, k ->> 'unit' AS unit, min(o) AS ord,
                                      CASE WHEN k ->> 'unit' = '%' THEN round(avg((k ->> 'value')::numeric), 1) ELSE sum((k ->> 'value')::numeric) END AS v
                                 FROM directory.school ds, jsonb_array_elements(api.branch_kpis(ds.school_id)) WITH ORDINALITY AS x(k, o)
                                WHERE ds.school_id = ANY (platform.current_school_ids())
                                GROUP BY k ->> 'code', k ->> 'label', k ->> 'unit') agg) END,
    'branches', (SELECT coalesce(jsonb_agg(jsonb_build_object('schoolId', ds.school_id, 'branchName', ds.branch_name, 'kpis', api.branch_kpis(ds.school_id))
                                 ORDER BY ds.branch_name), '[]'::jsonb)
                   FROM directory.school ds WHERE ds.school_id = ANY (platform.current_school_ids())));

-- name: compareBranches
SELECT jsonb_build_object('metric', coalesce(:metric, 'ATTENDANCE_TODAY'),
    'rows', coalesce((SELECT jsonb_agg(jsonb_build_object('schoolId', ds.school_id, 'branchName', ds.branch_name,
                         'kpis', (SELECT jsonb_agg(k) FROM jsonb_array_elements(api.branch_kpis(ds.school_id)) k
                                   WHERE :metric IS NULL OR k ->> 'code' = :metric)) ORDER BY ds.branch_name)
                       FROM directory.school ds WHERE ds.school_id = ANY (platform.current_school_ids())), '[]'::jsonb));

-- name: getCollections
WITH r AS (SELECT coalesce(:from::date, date_trunc('month', current_date)::date) AS f, coalesce(:to::date, current_date) AS t),
     p AS (SELECT p.* FROM finance.payment p, r WHERE p.status = 'SUCCESS' AND p.paid_at::date BETWEEN r.f AND r.t)
SELECT jsonb_build_object('from', r.f, 'to', r.t, 'total', coalesce((SELECT sum(amount) FROM p), 0),
    'byMode', coalesce((SELECT jsonb_object_agg(mode, s) FROM (SELECT mode, sum(amount) AS s FROM p GROUP BY mode) x), '{}'::jsonb),
    'byHead', coalesce((SELECT jsonb_object_agg(coalesce(h.name, 'Other'), s) FROM (
                 SELECT f.fee_head_id, sum(pa.amount) AS s FROM finance.payment_allocation pa JOIN p ON p.payment_id = pa.payment_id
                   JOIN finance.fee f ON f.fee_id = pa.fee_id GROUP BY f.fee_head_id) x LEFT JOIN finance.fee_head h ON h.fee_head_id = x.fee_head_id), '{}'::jsonb),
    'target', (SELECT sum(f.net_amount) FROM finance.fee f, r WHERE f.due_date BETWEEN r.f AND r.t AND f.status <> 'CANCELLED'),
    'daily', coalesce((SELECT jsonb_agg(api.kpi(to_char(d, 'YYYY-MM-DD'), to_char(d, 'DD Mon'),
                          (SELECT coalesce(sum(amount), 0) FROM p WHERE p.paid_at::date = d::date), 'INR') ORDER BY d)
                        FROM generate_series(r.f, r.t, interval '1 day') d), '[]'::jsonb))
FROM r;

-- name: getDuesAging
WITH f AS (SELECT f.*, current_date - f.due_date AS age FROM finance.fee f WHERE f.status IN ('DUE', 'PART_PAID') AND f.due_date < current_date)
SELECT jsonb_build_object(
    'd0to30', coalesce((SELECT sum(remaining_due) FROM f WHERE age <= 30), 0),
    'd31to60', coalesce((SELECT sum(remaining_due) FROM f WHERE age BETWEEN 31 AND 60), 0),
    'd60plus', coalesce((SELECT sum(remaining_due) FROM f WHERE age > 60), 0),
    'students', (SELECT count(DISTINCT student_id) FROM f));

-- name: getBudgetUtilization
SELECT coalesce(jsonb_agg(jsonb_build_object('budgetId', b.budget_id, 'head', eh.name, 'costCentre', b.cost_centre, 'budget', b.amount,
       'spent', u.spent, 'committed', u.committed, 'pct', round(100.0 * (u.spent + u.committed) / nullif(b.amount, 0), 1),
       'alert', (u.spent + u.committed) >= b.amount * coalesce(b.alert_at_pct, 80) / 100) ORDER BY eh.name), '[]'::jsonb)
FROM accounts.budget b
JOIN accounts.expense_head eh ON eh.expense_head_id = b.expense_head_id
CROSS JOIN LATERAL (SELECT coalesce(sum(e.amount) FILTER (WHERE e.status IN ('APPROVED', 'PAID')), 0) AS spent,
                           coalesce(sum(e.amount) FILTER (WHERE e.status = 'SUBMITTED'), 0) AS committed
                      FROM accounts.expense e WHERE e.expense_head_id = b.expense_head_id AND coalesce(e.cost_centre, '') = coalesce(b.cost_centre, '')) u
WHERE b.academic_year_id = coalesce(:academicYearId::bigint, (SELECT academic_year_id FROM academics.academic_year WHERE is_current LIMIT 1));

-- name: getAcademicSummary
WITH t AS (SELECT coalesce(:termId::bigint, (SELECT term_id FROM academics.academic_term WHERE start_date <= current_date
                                               ORDER BY start_date DESC LIMIT 1)) AS term_id),
     m AS (SELECT m.*, e.max_marks, cs.program_id FROM assessment.marks m JOIN assessment.exams e ON e.exam_id = m.exam_id
             JOIN academics.class_section cs ON cs.class_section_id = e.class_section_id, t
            WHERE e.term_id = t.term_id AND e.status IN ('LOCKED', 'PUBLISHED') AND NOT coalesce(m.is_absent, false) AND e.max_marks > 0)
SELECT jsonb_build_object('termId', (SELECT term_id FROM t),
    'averagePct', (SELECT round(avg(100.0 * mark_obtained / max_marks)::numeric, 1) FROM m),
    'passPct', (SELECT round(100.0 * count(*) FILTER (WHERE 100.0 * mark_obtained / max_marks >= 33) / nullif(count(*), 0), 1) FROM m),
    'byProgram', coalesce((SELECT jsonb_agg(api.kpi(code, name, v, '%') ORDER BY name)
                             FROM (SELECT p.program_code AS code, p.name, round(avg(100.0 * m.mark_obtained / m.max_marks)::numeric, 1) AS v
                                     FROM m JOIN academics.program p ON p.program_id = m.program_id GROUP BY p.program_id, p.program_code, p.name) x), '[]'::jsonb),
    'coveragePct', (SELECT round(100.0 * count(*) FILTER (WHERE lp.status IN ('DELIVERED', 'PARTIAL')) / nullif(count(*) FILTER (WHERE lp.planned_date <= current_date), 0), 1)
                      FROM learning.lesson_plan lp));

-- name: getOccupancy
SELECT jsonb_build_object(
    'capacity', (SELECT count(*) FROM hostel.bed WHERE status <> 'MAINTENANCE'),
    'occupied', (SELECT count(*) FROM hostel.bed WHERE status = 'OCCUPIED'),
    'pct', (SELECT round(100.0 * count(*) FILTER (WHERE status = 'OCCUPIED') / nullif(count(*) FILTER (WHERE status <> 'MAINTENANCE'), 0), 1) FROM hostel.bed),
    'byHostel', coalesce((SELECT jsonb_agg(api.kpi(h.code, h.name,
                    (SELECT round(100.0 * count(*) FILTER (WHERE b.status = 'OCCUPIED') / nullif(count(*) FILTER (WHERE b.status <> 'MAINTENANCE'), 0), 1)
                       FROM hostel.bed b JOIN hostel.room r ON r.room_id = b.room_id WHERE r.hostel_id = h.hostel_id), '%') ORDER BY h.name)
                    FROM hostel.hostel h WHERE h.status = 'ACTIVE'), '[]'::jsonb));

-- name: getAdmissionsFunnel
WITH y AS (SELECT coalesce(:academicYearId::bigint, (SELECT academic_year_id FROM academics.academic_year WHERE is_current LIMIT 1)) AS id),
     e AS (SELECT e.* FROM admissions.enquiry e, y WHERE e.academic_year_id = y.id OR e.academic_year_id IS NULL),
     a AS (SELECT a.* FROM admissions.application a, y WHERE a.academic_year_id = y.id)
SELECT jsonb_build_object('academicYearId', (SELECT id FROM y),
    'stages', jsonb_build_array(
        api.kpi('ENQUIRIES', 'Enquiries', (SELECT count(*) FROM e)),
        api.kpi('VISITED', 'Visited', (SELECT count(*) FROM e WHERE stage IN ('VISITED', 'APPLIED'))),
        api.kpi('APPLIED', 'Applied', (SELECT count(*) FROM a WHERE status <> 'DRAFT')),
        api.kpi('OFFERED', 'Offered', (SELECT count(*) FROM a WHERE status IN ('OFFERED', 'ACCEPTED', 'ENROLLED'))),
        api.kpi('ENROLLED', 'Enrolled', (SELECT count(*) FROM a WHERE status = 'ENROLLED'))),
    'conversionPct', (SELECT round(100.0 * (SELECT count(*) FROM a WHERE status = 'ENROLLED') / nullif(count(*), 0), 1) FROM e),
    'bySource', coalesce((SELECT jsonb_object_agg(coalesce(source, 'UNKNOWN'), n) FROM (SELECT source, count(*) AS n FROM e GROUP BY source) x), '{}'::jsonb));

-- name: publishConsentForm write
WITH up AS (UPDATE compliance.consent_form SET published_at = now(), published_by_user_id = :me::bigint
             WHERE form_id = :formId::bigint AND published_at IS NULL RETURNING *)
SELECT api.camel(to_jsonb(up)) FROM up;
