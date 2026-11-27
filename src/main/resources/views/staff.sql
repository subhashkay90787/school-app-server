-- Screen queries for /api/v1/staff (every employee: self-service, plus library counter for librarians).

-- name: getHome
SELECT api.feed('STAFF',
    (SELECT api.card('critical', 'CRITICAL', 'CRITICAL_ALERT', max(n.title), max(n.body), count(*), 'CRITICAL', 'alerts')
       FROM communication.notification_recipient r JOIN communication.notification n ON n.notification_id = r.notification_id
      WHERE r.recipient_user_id = :me::bigint AND n.severity = 'CRITICAL' AND r.acknowledged_at IS NULL AND n.sent_time > now() - interval '24 hours'),
    (SELECT api.card('acks', 'NEEDS_YOU', 'ACKNOWLEDGE', 'Notices to acknowledge', max(n.title), count(*), 'ACTION', 'inbox?unreadOnly=true')
       FROM communication.notification_recipient r JOIN communication.notification n ON n.notification_id = r.notification_id
      WHERE r.recipient_user_id = :me::bigint AND coalesce(n.requires_ack, false) AND r.acknowledged_at IS NULL),
    (SELECT api.card('tickets', 'NEEDS_YOU', 'TICKETS', 'Tickets assigned to you', NULL, count(*), 'ACTION', 'tickets')
       FROM facility.ticket t WHERE t.assigned_to_user_id = :me::bigint AND t.status IN ('ASSIGNED', 'IN_PROGRESS', 'REOPENED')),
    (SELECT api.card('keys', 'NEEDS_YOU', 'KEY_DUE', 'Return the key you hold', string_agg(k.code, ', '), count(*), 'ACTION', 'keys')
       FROM security.key_movement m JOIN security.key k ON k.key_id = m.key_id WHERE m.issued_to_user_id = :me::bigint AND m.returned_at IS NULL AND m.due_back_at < now()),
    (SELECT api.card('shift', 'NOW', 'MY_SHIFT', 'Today: ' || coalesce(dp.status, 'not punched in'),
                     CASE WHEN dp.first_in_at IS NOT NULL THEN 'In at ' || to_char(dp.first_in_at, 'HH24:MI') END, NULL, 'INFO', 'me/shift')
       FROM (SELECT 1) one LEFT JOIN operations.daily_presence dp ON dp.person_kind = 'STAFF' AND dp.person_id = :me::bigint AND dp.presence_date = current_date
      WHERE EXISTS (SELECT 1 FROM hr.employee_profile e WHERE e.user_id = :me::bigint)),
    (SELECT api.card('leave', 'TODAY', 'LEAVE_BALANCE', 'Leave balance', string_agg(t.code || ' ' || b.balance, ' · '), NULL, 'INFO', 'leave')
       FROM hr.leave_balance b JOIN hr.leave_type t ON t.leave_type_id = b.leave_type_id
      WHERE b.user_id = :me::bigint AND b.academic_year_id = (SELECT academic_year_id FROM academics.academic_year WHERE is_current LIMIT 1)),
    (SELECT api.card('payslip', 'FEED', 'PAYSLIP', 'Payslip ' || r.period || ' ready', NULL, NULL, 'INFO', 'me/payslips')
       FROM hr.payslip p JOIN hr.payroll_run r ON r.run_id = p.run_id WHERE p.user_id = :me::bigint AND r.status IN ('APPROVED', 'PAID')
        AND coalesce(r.paid_at, now()) > now() - interval '30 days' ORDER BY r.period DESC LIMIT 1));

-- name: issueBook write
-- A copy that is not out; due in 14 days unless given
WITH b AS (SELECT :body::jsonb AS j),
     c AS (SELECT bc.* FROM library.book_copy bc, b WHERE bc.barcode = b.j ->> 'copyBarcode'
             AND NOT EXISTS (SELECT 1 FROM library.library_borrowing lb WHERE lb.copy_id = bc.copy_id AND lb.returned_on IS NULL)),
     ins AS (INSERT INTO library.library_borrowing (school_id, copy_id, borrower_student_id, borrower_user_id, issued_by_user_id, issued_on, due_on)
             SELECT c.school_id, c.copy_id, (b.j ->> 'borrowerStudentId')::bigint, (b.j ->> 'borrowerUserId')::bigint, :me::bigint, current_date,
                    coalesce((b.j ->> 'dueOn')::date, current_date + 14)
               FROM c, b WHERE (b.j ->> 'borrowerStudentId') IS NOT NULL OR (b.j ->> 'borrowerUserId') IS NOT NULL RETURNING *)
SELECT api.camel(to_jsonb(ins)) FROM ins;

-- name: returnBook write
WITH b AS (SELECT :body::jsonb AS j),
     up AS (UPDATE library.library_borrowing lb SET returned_on = coalesce((b.j ->> 'returnedOn')::date, current_date)
              FROM b, library.book_copy bc WHERE bc.barcode = b.j ->> 'copyBarcode' AND lb.copy_id = bc.copy_id AND lb.returned_on IS NULL RETURNING lb.*)
SELECT api.camel(to_jsonb(up)) FROM up;
