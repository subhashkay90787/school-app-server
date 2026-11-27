-- Screen queries for /api/v1/accountant (fee counter, defaulters, day close, budgets).

-- name: getHome
SELECT api.feed('ACCOUNTANT',
    (SELECT api.card('approvals', 'NEEDS_YOU', 'APPROVALS', 'Approvals waiting', NULL, count(*), 'ACTION', 'approvals')
       FROM platform.flow_instance fi WHERE fi.status = 'OPEN' AND fi.current_step = 'ACCOUNTANT' AND coalesce(fi.submitted_by_user_id, -1) <> :me::bigint),
    (SELECT api.card('cheques', 'NEEDS_YOU', 'CHEQUES', 'Cheques to clear', NULL, count(*), 'ACTION', 'payments?mode=CHEQUE&status=INITIATED')
       FROM finance.payment p WHERE p.mode IN ('CHEQUE', 'DD') AND p.status = 'INITIATED'),
    (SELECT api.card('refunds', 'NEEDS_YOU', 'REFUNDS', 'Refunds to pay', NULL, count(*), 'ACTION', 'refunds?status=APPROVED')
       FROM finance.refund r WHERE r.status = 'APPROVED'),
    (SELECT api.card('collected', 'NOW', 'COLLECTED_TODAY', 'Collected today', '₹' || to_char(coalesce(sum(p.amount), 0), 'FM99,99,99,990') || ' · ' || count(*) || ' receipts',
                     NULL, 'INFO', 'day-close')
       FROM finance.payment p WHERE p.status = 'SUCCESS' AND p.paid_at::date = current_date),
    (SELECT api.card('defaulters', 'TODAY', 'DEFAULTERS', 'Students with overdue fees', '₹' || to_char(sum(f.remaining_due), 'FM99,99,99,990'),
                     count(DISTINCT f.student_id), 'INFO', 'defaulters')
       FROM finance.fee f WHERE f.status IN ('DUE', 'PART_PAID') AND f.due_date < current_date),
    (SELECT api.card('budget', 'FEED', 'BUDGET_ALERT', 'Budgets near their limit', NULL, count(*), 'INFO', 'budgets')
       FROM accounts.budget b WHERE (SELECT coalesce(sum(e.amount), 0) FROM accounts.expense e WHERE e.expense_head_id = b.expense_head_id
                                       AND coalesce(e.cost_centre, '') = coalesce(b.cost_centre, '') AND e.status IN ('APPROVED', 'PAID', 'SUBMITTED'))
                                    >= b.amount * coalesce(b.alert_at_pct, 80) / 100));

-- name: searchFamilies
-- Students by name / admission number, and parents by name / phone (returning each child), for the counter
WITH q AS (SELECT '%' || btrim(coalesce(:q, '')) || '%' AS p, length(btrim(coalesce(:q, ''))) AS n)
SELECT coalesce(jsonb_agg(DISTINCT x.ref), '[]'::jsonb) FROM (
    SELECT api.student_ref(s.student_id) AS ref FROM academics.student s, q
     WHERE q.n >= 2 AND s.status = 'ACTIVE' AND ((s.first_name || ' ' || coalesce(s.last_name, '')) ILIKE q.p OR s.student_admission_number ILIKE q.p)
    UNION ALL
    SELECT api.student_ref(sp.student_id, 'Parent: ' || api.user_name(u.user_id)) FROM directory.app_user u
      JOIN academics.student_parent sp ON sp.user_id = u.user_id, q
     WHERE q.n >= 3 AND ((u.first_name || ' ' || coalesce(u.last_name, '')) ILIKE q.p OR u.phone_number ILIKE q.p)
    LIMIT 30) x;

-- name: getFamilyDues
-- The student and their siblings (children of the same parents), so the counter can collect for the family
SELECT api.family_dues(ARRAY(
    SELECT DISTINCT s FROM (SELECT :studentId::bigint AS s
                            UNION SELECT sp2.student_id FROM academics.student_parent sp JOIN academics.student_parent sp2 ON sp2.user_id = sp.user_id
                                   WHERE sp.student_id = :studentId::bigint) x ORDER BY s))
WHERE EXISTS (SELECT 1 FROM academics.student WHERE student_id = :studentId::bigint);

-- name: previewReceiptNumber
WITH fy AS (SELECT CASE WHEN extract(month FROM current_date) >= 4 THEN extract(year FROM current_date)::int ELSE extract(year FROM current_date)::int - 1 END AS y)
SELECT jsonb_build_object('financialYear', y || '-' || lpad(((y + 1) % 100)::text, 2, '0'),
    'next', 'RCT/' || lpad((y % 100)::text, 2, '0') || '-' || lpad(((y + 1) % 100)::text, 2, '0') || '/'
            || lpad((coalesce((SELECT max(nullif(regexp_replace(split_part(p.receipt_number, '/', 3), '\D', '', 'g'), '')::int) FROM finance.payment p
                                WHERE p.receipt_number LIKE 'RCT/' || lpad((y % 100)::text, 2, '0') || '-%'), 0) + 1)::text, 5, '0'))
FROM fy;

-- name: receivePayment write
-- Counter payment: cash / UPI / card are SUCCESS at once, cheque / DD start INITIATED until cleared. Allocations
-- go to the named dues (oldest first when none are named) and update each due's paid and remaining amounts.
WITH b AS (SELECT :body::jsonb AS j),
     fy AS (SELECT CASE WHEN extract(month FROM current_date) >= 4 THEN extract(year FROM current_date)::int ELSE extract(year FROM current_date)::int - 1 END AS y),
     num AS (SELECT 'RCT/' || lpad((y % 100)::text, 2, '0') || '-' || lpad(((y + 1) % 100)::text, 2, '0') || '/'
                    || lpad((coalesce((SELECT max(nullif(regexp_replace(split_part(p.receipt_number, '/', 3), '\D', '', 'g'), '')::int) FROM finance.payment p
                                        WHERE p.receipt_number LIKE 'RCT/' || lpad((y % 100)::text, 2, '0') || '-%'), 0) + 1)::text, 5, '0') AS rn FROM fy),
     st AS (SELECT s.* FROM academics.student s, b WHERE s.student_id = (b.j ->> 'studentId')::bigint),
     named AS (SELECT (x ->> 'feeId')::bigint AS fee_id, (x ->> 'amount')::numeric AS amount FROM b, jsonb_array_elements(coalesce(b.j -> 'allocations', '[]'::jsonb)) x),
     dues AS (SELECT f.fee_id, f.remaining_due, sum(f.remaining_due) OVER (ORDER BY f.due_date NULLS LAST, f.fee_id) AS running
                FROM finance.fee f, st WHERE f.student_id = st.student_id AND f.status IN ('DUE', 'PART_PAID') AND NOT EXISTS (SELECT 1 FROM named)),
     auto AS (SELECT d.fee_id, least(d.remaining_due, (b.j ->> 'amount')::numeric - (d.running - d.remaining_due)) AS amount
                FROM dues d, b WHERE d.running - d.remaining_due < (b.j ->> 'amount')::numeric),
     alloc AS (SELECT * FROM named UNION ALL SELECT * FROM auto),
     valid AS (SELECT a.* FROM alloc a JOIN finance.fee f ON f.fee_id = a.fee_id
                WHERE f.student_id IN (SELECT student_id FROM st UNION SELECT sp2.student_id FROM academics.student_parent sp
                                         JOIN academics.student_parent sp2 ON sp2.user_id = sp.user_id WHERE sp.student_id = (SELECT student_id FROM st))
                  AND a.amount > 0 AND a.amount <= f.remaining_due),
     ok AS (SELECT 1 FROM b WHERE (b.j ->> 'amount')::numeric > 0
              AND (SELECT count(*) FROM valid) = (SELECT count(*) FROM alloc)
              AND coalesce((SELECT sum(amount) FROM valid), 0) <= (b.j ->> 'amount')::numeric),
     pay AS (INSERT INTO finance.payment (school_id, student_id, amount, mode, gateway, cheque_number, bank_name, gateway_txn_id, receipt_number,
                                          status, received_by_user_id, paid_at)
             SELECT st.school_id, st.student_id, (b.j ->> 'amount')::numeric, b.j ->> 'mode', 'NONE', b.j ->> 'chequeNumber', b.j ->> 'bankName',
                    b.j ->> 'referenceNo', (SELECT rn FROM num),
                    CASE WHEN b.j ->> 'mode' IN ('CHEQUE', 'DD') THEN 'INITIATED' ELSE 'SUCCESS' END, :me::bigint, now()
               FROM st, b WHERE EXISTS (SELECT 1 FROM ok) RETURNING payment_id, school_id, status),
     pa AS (INSERT INTO finance.payment_allocation (school_id, payment_id, fee_id, amount)
            SELECT pay.school_id, pay.payment_id, v.fee_id, v.amount FROM pay, valid v RETURNING fee_id, amount),
     upd AS (UPDATE finance.fee f SET paid_amount = coalesce(f.paid_amount, 0) + v.amount, remaining_due = f.remaining_due - v.amount,
                    status = CASE WHEN f.remaining_due - v.amount <= 0 THEN 'PAID' ELSE 'PART_PAID' END
               FROM valid v, pay WHERE f.fee_id = v.fee_id AND pay.status = 'SUCCESS' RETURNING 1)
SELECT payment_id AS result FROM pay WHERE (SELECT count(*) FROM pa) + (SELECT count(*) FROM upd) >= 0;
-- then
SELECT jsonb_build_object('payment', api.camel(to_jsonb(p)),
    'allocations', coalesce((SELECT jsonb_agg(api.camel(to_jsonb(a)) ORDER BY a.allocation_id) FROM finance.payment_allocation a WHERE a.payment_id = p.payment_id), '[]'::jsonb),
    'receiptUrl', '/api/v1/accountant/payments/' || p.payment_id || '/receipt', 'sentOnWhatsapp', false)
FROM finance.payment p WHERE p.payment_id = :result::bigint;

-- name: listDefaulters
SELECT api.page(coalesce(jsonb_agg(v ORDER BY (v ->> 'due')::numeric DESC), '[]'::jsonb), :page, :size) FROM (
    SELECT jsonb_strip_nulls(jsonb_build_object('student', api.student_ref(s.student_id), 'classSection', api.section_label(s.class_section_id),
           'due', x.due, 'oldestDueDate', x.oldest,
           'bucket', CASE WHEN current_date - x.oldest <= 30 THEN 'D0_30' WHEN current_date - x.oldest <= 60 THEN 'D31_60' ELSE 'D60_PLUS' END,
           'parentPhone', (SELECT u.phone_number FROM academics.student_parent sp JOIN directory.app_user u ON u.user_id = sp.user_id
                            WHERE sp.student_id = s.student_id ORDER BY sp.is_primary_contact DESC NULLS LAST LIMIT 1))) AS v
      FROM (SELECT f.student_id, sum(f.remaining_due) AS due, min(f.due_date) AS oldest FROM finance.fee f
             WHERE f.status IN ('DUE', 'PART_PAID') AND f.due_date < current_date AND f.remaining_due > 0 GROUP BY f.student_id) x
      JOIN academics.student s ON s.student_id = x.student_id
     WHERE (:classSectionId IS NULL OR s.class_section_id = :classSectionId::bigint)
) y
WHERE :bucket IS NULL OR v ->> 'bucket' = :bucket;

-- name: getDayClose
-- System totals for the day by mode; counted cash and closing come with the day-close flow
WITH d AS (SELECT coalesce(:date::date, current_date) AS day),
     p AS (SELECT p.* FROM finance.payment p, d WHERE p.status = 'SUCCESS' AND p.paid_at::date = d.day)
SELECT jsonb_strip_nulls(jsonb_build_object('date', (SELECT day FROM d),
    'systemCash', coalesce((SELECT sum(amount) FROM p WHERE mode = 'CASH'), 0),
    'byMode', coalesce((SELECT jsonb_object_agg(mode, s) FROM (SELECT mode, sum(amount) AS s FROM p GROUP BY mode) x), '{}'::jsonb),
    'receipts', (SELECT count(*) FROM p), 'closed', false));

-- name: listBudgets
SELECT coalesce(jsonb_agg(jsonb_build_object('budgetId', b.budget_id, 'head', eh.name, 'costCentre', b.cost_centre, 'budget', b.amount,
       'spent', u.spent, 'committed', u.committed, 'pct', round(100.0 * (u.spent + u.committed) / nullif(b.amount, 0), 1),
       'alert', (u.spent + u.committed) >= b.amount * coalesce(b.alert_at_pct, 80) / 100) ORDER BY eh.name), '[]'::jsonb)
FROM accounts.budget b
JOIN accounts.expense_head eh ON eh.expense_head_id = b.expense_head_id
CROSS JOIN LATERAL (SELECT coalesce(sum(e.amount) FILTER (WHERE e.status IN ('APPROVED', 'PAID')), 0) AS spent,
                           coalesce(sum(e.amount) FILTER (WHERE e.status = 'SUBMITTED'), 0) AS committed
                      FROM accounts.expense e WHERE e.expense_head_id = b.expense_head_id AND coalesce(e.cost_centre, '') = coalesce(b.cost_centre, '')) u
WHERE b.academic_year_id = coalesce(:academicYearId::bigint, (SELECT academic_year_id FROM academics.academic_year WHERE is_current LIMIT 1));
