-- Screen queries for /api/v1/common (every role). See core.data.Views for the conventions:
-- one JSON value per statement, parameters as text (:x::type), :me = caller, :school = X-School-Id.

-- name: getProfile
SELECT jsonb_strip_nulls(jsonb_build_object(
    'userId', u.user_id, 'firstName', u.first_name, 'lastName', u.last_name, 'email', u.email,
    'phoneNumber', u.phone_number, 'userCategory', u.user_category,
    'photoUrl', (SELECT s.photo_url FROM academics.student s WHERE s.student_user_id = u.user_id LIMIT 1),
    'school', (SELECT jsonb_build_object('schoolId', d.school_id, 'schoolName', d.school_name, 'branchName', d.branch_name,
                      'organizationId', d.organization_id, 'institutionType', d.institution_type_code,
                      'timezone', d.timezone, 'terminology', d.terminology)
                 FROM directory.school d WHERE d.school_id = :school::bigint),
    'employee', (SELECT api.camel(to_jsonb(e) - 'pf_uan' - 'esi_number' - 'vault_ref') FROM hr.employee_profile e WHERE e.user_id = u.user_id),
    'teacher', (SELECT api.camel(to_jsonb(t)) FROM hr.teacher_metadata t WHERE t.user_id = u.user_id),
    'children', (SELECT jsonb_agg(api.child_summary(c) ORDER BY c) FROM api.my_children() c),
    'student', (SELECT api.camel(to_jsonb(s) - 'aadhaar_last4') FROM academics.student s WHERE s.student_user_id = u.user_id
                 ORDER BY s.student_id DESC LIMIT 1),
    'duties', api.my_duties()))
FROM directory.app_user u WHERE u.user_id = :me::bigint;

-- name: listMyDuties
SELECT api.my_duties();

-- name: search
-- Students, staff, receipts and classes in the branch matching q (at least 2 characters); what each actor may open
-- is enforced again when the hit is followed.
WITH q AS (SELECT '%' || btrim(coalesce(:q, '')) || '%' AS p, length(btrim(coalesce(:q, ''))) AS n)
SELECT coalesce(jsonb_agg(h ORDER BY ord, h ->> 'title'), '[]'::jsonb) FROM (
    SELECT 1 AS ord, jsonb_build_object('kind', 'STUDENT', 'id', s.student_id,
           'title', btrim(s.first_name || ' ' || coalesce(s.last_name, '')),
           'subtitle', coalesce(api.section_label(s.class_section_id), '') || ' · ' || s.student_admission_number,
           'deepLink', 'students/' || s.student_id) AS h
      FROM academics.student s, q
     WHERE q.n >= 2 AND s.status = 'ACTIVE' AND (s.first_name || ' ' || coalesce(s.last_name, '')) ILIKE q.p
        OR (q.n >= 2 AND s.student_admission_number ILIKE q.p)
    UNION ALL
    SELECT 2, jsonb_build_object('kind', 'STAFF', 'id', e.user_id, 'title', api.user_name(e.user_id),
           'subtitle', coalesce(e.designation, e.staff_category), 'deepLink', 'staff/' || e.user_id)
      FROM hr.employee_profile e, q
     WHERE q.n >= 2 AND e.status = 'ACTIVE' AND (api.user_name(e.user_id) ILIKE q.p OR e.employee_code ILIKE q.p)
    UNION ALL
    SELECT 3, jsonb_build_object('kind', 'RECEIPT', 'id', p.payment_id, 'title', p.receipt_number,
           'subtitle', api.student_ref(p.student_id) ->> 'name' || ' · ' || p.amount, 'deepLink', 'payments/' || p.payment_id)
      FROM finance.payment p, q
     WHERE q.n >= 3 AND p.receipt_number ILIKE q.p
    UNION ALL
    SELECT 4, jsonb_build_object('kind', 'CLASS', 'id', cs.class_section_id, 'title', cs.section_name,
           'subtitle', api.user_name(cs.teacher_user_id), 'deepLink', 'classes/' || cs.class_section_id)
      FROM academics.class_section cs, q
     WHERE q.n >= 1 AND cs.section_name ILIKE q.p
    LIMIT 30
) x;

-- name: listInbox
SELECT api.page(coalesce(jsonb_agg(i ORDER BY sent_at DESC NULLS LAST, id DESC), '[]'::jsonb), :page, :size) FROM (
    SELECT n.sent_time AS sent_at, n.notification_id AS id, jsonb_strip_nulls(jsonb_build_object(
           'notificationId', n.notification_id, 'title', n.title, 'body', n.body, 'category', n.category,
           'severity', n.severity, 'student', api.student_ref(r.student_id), 'sentAt', n.sent_time,
           'readAt', r.read_at, 'requiresAck', coalesce(n.requires_ack, false), 'acknowledgedAt', r.acknowledged_at,
           'deepLink', 'inbox/' || n.notification_id, 'attachmentUrls', to_jsonb(n.attachment_urls))) AS i
      FROM communication.notification_recipient r
      JOIN communication.notification n ON n.notification_id = r.notification_id
     WHERE r.recipient_user_id = :me::bigint
       AND (coalesce(:unreadOnly::boolean, false) = false OR r.read_at IS NULL)
       AND (:severity IS NULL OR n.severity = :severity)
       AND (n.scheduled_at IS NULL OR n.scheduled_at <= now())
) x;

-- name: markRead write
WITH u AS (
    UPDATE communication.notification_recipient SET read_at = coalesce(read_at, now())
     WHERE notification_id = :notificationId::bigint AND recipient_user_id = :me::bigint RETURNING 1)
SELECT CASE WHEN EXISTS (SELECT 1 FROM u) THEN '{}' END;

-- name: acknowledge write
WITH u AS (
    UPDATE communication.notification_recipient
       SET read_at = coalesce(read_at, now()), acknowledged_at = coalesce(acknowledged_at, now())
     WHERE notification_id = :notificationId::bigint AND recipient_user_id = :me::bigint RETURNING 1)
SELECT CASE WHEN EXISTS (SELECT 1 FROM u) THEN '{}' END;

-- name: listCriticalAlerts
-- CRITICAL notifications to me from the last 24 h that I haven't acknowledged, with who else was told (the ladder)
SELECT coalesce(jsonb_agg(a ORDER BY a ->> 'raisedAt' DESC), '[]'::jsonb) FROM (
    SELECT jsonb_strip_nulls(jsonb_build_object(
           'notificationId', n.notification_id, 'title', n.title, 'body', n.body,
           'student', api.student_ref(r.student_id), 'raisedAt', n.sent_time,
           'ladder', (SELECT jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
                             'step', o.rn, 'label', coalesce(ep.designation, 'Recipient'),
                             'person', api.person(o.recipient_user_id), 'notifiedAt', n.sent_time,
                             'acknowledgedAt', o.acknowledged_at)) ORDER BY o.rn)
                        FROM (SELECT r2.*, row_number() OVER (ORDER BY r2.recipient_user_id) AS rn
                                FROM communication.notification_recipient r2 WHERE r2.notification_id = n.notification_id) o
                        LEFT JOIN hr.employee_profile ep ON ep.user_id = o.recipient_user_id))) AS a
      FROM communication.notification_recipient r
      JOIN communication.notification n ON n.notification_id = r.notification_id
     WHERE r.recipient_user_id = :me::bigint AND n.severity = 'CRITICAL' AND r.acknowledged_at IS NULL
       AND n.sent_time > now() - interval '24 hours'
) x;

-- name: listApprovals
-- Open flow instances waiting at a step one of my roles can act on (until the flow engine assigns approvers, the
-- step code is matched against the role codes in my token by the caller's permission; my own requests excluded)
SELECT api.page(coalesce(jsonb_agg(a ORDER BY (a ->> 'dueBy') NULLS LAST, (a ->> 'flowInstanceId')::bigint), '[]'::jsonb), :page, :size) FROM (
    SELECT jsonb_strip_nulls(jsonb_build_object(
           'flowInstanceId', fi.instance_id, 'kind', fi.ref_kind, 'refId', fi.ref_id, 'title', fd.name,
           'requestedBy', api.person(fi.submitted_by_user_id), 'amount', fi.amount,
           'fromDate', lr.from_date, 'toDate', lr.to_date, 'dueBy', fi.due_by,
           'urgency', CASE WHEN fi.ref_kind IN ('OUTING', 'GATE_PASS', 'INCIDENT') THEN 'SAFETY'
                           WHEN fi.amount IS NOT NULL THEN 'MONEY' ELSE 'OTHER' END,
           'status', fi.status, 'waitingFor', fi.current_step,
           'history', (SELECT jsonb_agg(jsonb_strip_nulls(jsonb_build_object('sequence', l.rn, 'approverRoleCode', l.actor_role_code,
                               'approverName', api.user_name(l.actor_user_id),
                               'decision', CASE l.action WHEN 'APPROVE' THEN 'APPROVED' WHEN 'REJECT' THEN 'REJECTED'
                                                         WHEN 'SEND_BACK' THEN 'SENT_BACK' ELSE 'PENDING' END,
                               'note', l.note, 'decidedAt', l.occurred_at)) ORDER BY l.rn)
                         FROM (SELECT t.*, row_number() OVER (ORDER BY t.occurred_at) AS rn FROM platform.flow_transition_log t
                                WHERE t.instance_id = fi.instance_id) l))) AS a
      FROM platform.flow_instance fi
      JOIN platform.flow_definition fd ON fd.flow_id = fi.flow_id
      LEFT JOIN hr.leave_request lr ON fi.ref_kind = 'LEAVE_REQUEST' AND lr.leave_request_id = fi.ref_id
     WHERE fi.status = 'OPEN' AND coalesce(fi.submitted_by_user_id, -1) <> :me::bigint
       AND (:kind IS NULL OR fi.ref_kind = :kind)
       AND (:branchId IS NULL OR fi.school_id = :branchId::bigint)
       AND fi.current_step NOT IN ('PARENT')
) x
WHERE :urgency IS NULL OR a ->> 'urgency' = :urgency;

-- name: getApproval
SELECT jsonb_strip_nulls(jsonb_build_object(
       'flowInstanceId', fi.instance_id, 'kind', fi.ref_kind, 'refId', fi.ref_id, 'title', fd.name,
       'requestedBy', api.person(fi.submitted_by_user_id), 'amount', fi.amount,
       'fromDate', lr.from_date, 'toDate', lr.to_date, 'dueBy', fi.due_by,
       'urgency', CASE WHEN fi.ref_kind IN ('OUTING', 'GATE_PASS', 'INCIDENT') THEN 'SAFETY'
                       WHEN fi.amount IS NOT NULL THEN 'MONEY' ELSE 'OTHER' END,
       'status', fi.status, 'waitingFor', fi.current_step,
       'checks', CASE WHEN lr.leave_request_id IS NOT NULL THEN jsonb_build_array(
                   jsonb_build_object('code', 'BALANCE', 'label', 'Leave balance',
                     'passed', coalesce((SELECT b.balance >= coalesce(lr.days, 1) FROM hr.leave_balance b
                                          WHERE b.user_id = lr.user_id AND b.leave_type_id = lr.leave_type_id
                                          ORDER BY b.academic_year_id DESC LIMIT 1), false),
                     'detail', (SELECT 'Balance ' || b.balance FROM hr.leave_balance b WHERE b.user_id = lr.user_id
                                   AND b.leave_type_id = lr.leave_type_id ORDER BY b.academic_year_id DESC LIMIT 1))) END,
       'history', (SELECT jsonb_agg(jsonb_strip_nulls(jsonb_build_object('sequence', l.rn, 'approverRoleCode', l.actor_role_code,
                           'approverName', api.user_name(l.actor_user_id),
                           'decision', CASE l.action WHEN 'APPROVE' THEN 'APPROVED' WHEN 'REJECT' THEN 'REJECTED'
                                                     WHEN 'SEND_BACK' THEN 'SENT_BACK' ELSE 'PENDING' END,
                           'note', l.note, 'decidedAt', l.occurred_at)) ORDER BY l.rn)
                     FROM (SELECT t.*, row_number() OVER (ORDER BY t.occurred_at) AS rn FROM platform.flow_transition_log t
                            WHERE t.instance_id = fi.instance_id) l)))
FROM platform.flow_instance fi
JOIN platform.flow_definition fd ON fd.flow_id = fi.flow_id
LEFT JOIN hr.leave_request lr ON fi.ref_kind = 'LEAVE_REQUEST' AND lr.leave_request_id = fi.ref_id
WHERE fi.instance_id = :flowInstanceId::bigint;

-- name: listMyRequests
SELECT api.page(coalesce(jsonb_agg(a ORDER BY (a ->> 'flowInstanceId')::bigint DESC), '[]'::jsonb), :page, :size) FROM (
    SELECT jsonb_strip_nulls(jsonb_build_object(
           'flowInstanceId', fi.instance_id, 'kind', fi.ref_kind, 'refId', fi.ref_id, 'title', fd.name,
           'requestedBy', api.person(fi.submitted_by_user_id), 'amount', fi.amount,
           'fromDate', lr.from_date, 'toDate', lr.to_date, 'dueBy', fi.due_by, 'status', fi.status,
           'waitingFor', CASE WHEN fi.status = 'OPEN' THEN fi.current_step END)) AS a
      FROM platform.flow_instance fi
      JOIN platform.flow_definition fd ON fd.flow_id = fi.flow_id
      LEFT JOIN hr.leave_request lr ON fi.ref_kind = 'LEAVE_REQUEST' AND lr.leave_request_id = fi.ref_id
     WHERE fi.submitted_by_user_id = :me::bigint
) x;

-- name: listNews
-- Posts not expired whose audience includes me: everyone; my children's / my sections / my hostels; staff
WITH me AS (SELECT u.user_category AS cat FROM directory.app_user u WHERE u.user_id = :me::bigint),
     my_sections AS (SELECT s.class_section_id FROM academics.student s WHERE s.student_id IN (SELECT api.my_children())
                        OR s.student_user_id = :me::bigint
                     UNION SELECT api.my_sections()),
     my_hostels AS (SELECT a.hostel_id FROM hostel.allocation a WHERE a.status = 'ACTIVE' AND a.student_id IN (
                        SELECT api.my_children() UNION SELECT api.my_student())
                    UNION SELECT api.my_hostels())
SELECT api.page(coalesce(jsonb_agg(v ORDER BY pinned DESC, created DESC), '[]'::jsonb), :page, :size) FROM (
    SELECT coalesce(p.is_pinned, false) AS pinned, p.created_at AS created, jsonb_strip_nulls(jsonb_build_object(
           'postId', p.post_id, 'author', api.person(p.author_user_id), 'title', p.title, 'body', p.body,
           'createdAt', p.created_at, 'expiresAt', p.expires_at, 'pinned', coalesce(p.is_pinned, false),
           'media', (SELECT jsonb_agg(jsonb_strip_nulls(jsonb_build_object('mediaId', m.media_id, 'mimeType', m.mime_type,
                            'width', m.width, 'height', m.height, 'durationSeconds', m.duration_seconds,
                            'streamUrl', '/api/v1/common/news/' || p.post_id || '/media/' || m.media_id)) ORDER BY m.sort_order, m.media_id)
                       FROM communication.news_media m WHERE m.post_id = p.post_id AND m.purged_at IS NULL),
           'reactions', (SELECT jsonb_object_agg(r.reaction, r.n) FROM (SELECT reaction, count(*) AS n FROM communication.news_reaction
                           WHERE post_id = p.post_id GROUP BY reaction) r),
           'myReaction', (SELECT r.reaction FROM communication.news_reaction r WHERE r.post_id = p.post_id AND r.user_id = :me::bigint))) AS v
      FROM communication.news_post p, me
     WHERE p.deleted_at IS NULL AND p.expires_at > now()
       AND (p.audience_type = 'ALL'
            OR (p.audience_type = 'STAFF' AND me.cat IN ('STAFF', 'NON_STAFF'))
            OR (p.audience_type = 'SECTION' AND p.class_section_id IN (SELECT class_section_id FROM my_sections))
            OR (p.audience_type = 'PROGRAM' AND p.program_id IN (SELECT cs.program_id FROM academics.class_section cs
                                                                 WHERE cs.class_section_id IN (SELECT class_section_id FROM my_sections)))
            OR (p.audience_type = 'HOSTEL' AND p.hostel_id IN (SELECT hostel_id FROM my_hostels))
            OR p.author_user_id = :me::bigint)
) x;

-- name: createNewsPost write
WITH b AS (SELECT :body::jsonb AS j),
     ins AS (
    INSERT INTO communication.news_post (school_id, author_user_id, title, body, audience_type, class_section_id, program_id, hostel_id,
                                         is_pinned, created_at, expires_at)
    SELECT :school::bigint, :me::bigint, j ->> 'title', j ->> 'body', coalesce(j ->> 'audienceType', 'ALL'),
           (j ->> 'classSectionId')::bigint, (j ->> 'programId')::bigint, (j ->> 'hostelId')::bigint,
           coalesce((j ->> 'pinned')::boolean, false), now(), now() + interval '30 days'
      FROM b RETURNING *)
SELECT jsonb_strip_nulls(jsonb_build_object('postId', post_id, 'author', api.person(author_user_id), 'title', title, 'body', body,
       'createdAt', created_at, 'expiresAt', expires_at, 'pinned', is_pinned, 'media', '[]'::jsonb, 'reactions', '{}'::jsonb))
FROM ins;

-- name: react write
WITH up AS (
    INSERT INTO communication.news_reaction (school_id, post_id, user_id, reaction, reacted_at)
    SELECT p.school_id, p.post_id, :me::bigint, :body::jsonb ->> 'reaction', now()
      FROM communication.news_post p WHERE p.post_id = :postId::bigint AND p.deleted_at IS NULL
    ON CONFLICT (school_id, post_id, user_id) DO UPDATE SET reaction = EXCLUDED.reaction, reacted_at = EXCLUDED.reacted_at
    RETURNING 1)
SELECT CASE WHEN EXISTS (SELECT 1 FROM up) THEN '{}' END;

-- name: listConsents
-- Published forms I sign: as parent for each child, as staff for myself; latest decision per subject
WITH subjects AS (
    SELECT 'STUDENT' AS kind, c AS id FROM api.my_children() c
    UNION ALL
    SELECT 'STAFF', e.user_id FROM hr.employee_profile e WHERE e.user_id = :me::bigint
)
SELECT coalesce(jsonb_agg(v ORDER BY v ->> 'decision' = 'PENDING' DESC, v ->> 'title'), '[]'::jsonb) FROM (
    SELECT jsonb_strip_nulls(jsonb_build_object(
           'formId', f.form_id, 'featureCode', f.feature_code, 'version', f.version, 'title', f.title, 'purpose', f.purpose,
           'dataUsed', to_jsonb(f.data_used), 'sharedWith', f.shared_with, 'retention', f.retention, 'ifDeclined', f.if_declined,
           'required', coalesce(f.is_required, false),
           'subject', CASE WHEN s.kind = 'STUDENT' THEN api.student_ref(s.id) ELSE api.person(s.id) END,
           'decision', coalesce(cr.decision, 'PENDING'), 'decidedAt', cr.decided_at)) AS v
      FROM compliance.consent_form f
      JOIN subjects s ON (s.kind = 'STUDENT' AND coalesce(f.signer_parent, false)) OR (s.kind = 'STAFF' AND coalesce(f.signer_staff, false))
      LEFT JOIN LATERAL (SELECT r.decision, r.decided_at FROM compliance.consent_record r
                          WHERE r.form_id = f.form_id AND r.form_version = f.version AND r.subject_kind = s.kind AND r.subject_id = s.id
                          ORDER BY r.decided_at DESC LIMIT 1) cr ON true
     WHERE f.published_at IS NOT NULL
) x;

-- name: decideConsent write
-- Parents decide for their children, staff for themselves (anything else: no row -> 404)
WITH b AS (SELECT :body::jsonb AS j),
     f AS (SELECT * FROM compliance.consent_form WHERE form_id = :formId::bigint AND published_at IS NOT NULL),
     ok AS (SELECT b.j FROM b, f
             WHERE (b.j ->> 'subjectKind' = 'STUDENT' AND coalesce(f.signer_parent, false)
                    AND (b.j ->> 'subjectId')::bigint IN (SELECT api.my_children()))
                OR (b.j ->> 'subjectKind' = 'STAFF' AND coalesce(f.signer_staff, false) AND (b.j ->> 'subjectId')::bigint = :me::bigint)),
     ins AS (
    INSERT INTO compliance.consent_record (school_id, form_id, form_version, subject_kind, subject_id, signer_user_id, decision, method, decided_at)
    SELECT :school::bigint, f.form_id, f.version, ok.j ->> 'subjectKind', (ok.j ->> 'subjectId')::bigint, :me::bigint,
           ok.j ->> 'decision', 'IN_APP', now()
      FROM f, ok RETURNING *)
SELECT jsonb_strip_nulls(jsonb_build_object(
       'formId', f.form_id, 'featureCode', f.feature_code, 'version', f.version, 'title', f.title, 'purpose', f.purpose,
       'dataUsed', to_jsonb(f.data_used), 'sharedWith', f.shared_with, 'retention', f.retention, 'ifDeclined', f.if_declined,
       'required', coalesce(f.is_required, false),
       'subject', CASE WHEN ins.subject_kind = 'STUDENT' THEN api.student_ref(ins.subject_id) ELSE api.person(ins.subject_id) END,
       'decision', ins.decision, 'decidedAt', ins.decided_at))
FROM ins, f;

-- name: listConversations
WITH pol AS (SELECT * FROM communication.messaging_policy LIMIT 1)
SELECT api.page(coalesce(jsonb_agg(v ORDER BY (v ->> 'lastMessageAt') DESC NULLS LAST), '[]'::jsonb), :page, :size) FROM (
    SELECT jsonb_strip_nulls(jsonb_build_object(
           'conversationId', c.conversation_id, 'kind', c.kind,
           'title', CASE c.kind
                        WHEN 'PARENT_TEACHER' THEN coalesce((SELECT string_agg(api.user_name(o.user_id), ', ')
                                                               FROM communication.conversation_member o
                                                              WHERE o.conversation_id = c.conversation_id AND o.user_id <> :me::bigint), 'Conversation')
                        WHEN 'CLASS_GROUP' THEN coalesce(api.section_label(c.class_section_id), 'Class') || ' group'
                        WHEN 'HOSTEL_GROUP' THEN coalesce((SELECT h.name FROM hostel.hostel h WHERE h.hostel_id = c.hostel_id), 'Hostel') || ' group'
                        ELSE 'Help desk' END,
           'student', api.student_ref(c.student_id),
           'lastMessage', lm.body, 'lastMessageAt', lm.sent_at,
           'unread', (SELECT count(*) FROM communication.message m WHERE m.conversation_id = c.conversation_id AND m.deleted_at IS NULL
                         AND m.sender_user_id <> :me::bigint AND m.sent_at > coalesce(me.last_read_at, '-infinity')),
           'locked', coalesce(c.is_locked, false),
           'withinChatHours', CASE WHEN pol.office_hours_start IS NULL THEN true
                                   ELSE localtime BETWEEN pol.office_hours_start AND pol.office_hours_end END)) AS v
      FROM communication.conversation c
      JOIN communication.conversation_member me ON me.conversation_id = c.conversation_id AND me.user_id = :me::bigint
      LEFT JOIN LATERAL (SELECT m.body, m.sent_at FROM communication.message m WHERE m.conversation_id = c.conversation_id
                          AND m.deleted_at IS NULL ORDER BY m.sent_at DESC LIMIT 1) lm ON true
      LEFT JOIN pol ON true
) x;

-- name: createConversation write
-- Parent -> a teacher of the child (or the class teacher when staffUserId is absent); staff -> the parents of a student
WITH b AS (SELECT :body::jsonb AS j),
     pol AS (SELECT coalesce((SELECT parent_can_start_chat FROM communication.messaging_policy LIMIT 1), true) AS parent_can_start),
     me AS (SELECT user_category FROM directory.app_user WHERE user_id = :me::bigint),
     st AS (SELECT s.* FROM academics.student s, b WHERE s.student_id = (b.j ->> 'studentId')::bigint),
     staff AS (SELECT coalesce((b.j ->> 'staffUserId')::bigint, st.class_teacher) AS uid FROM b,
                      (SELECT (SELECT cs.teacher_user_id FROM academics.class_section cs WHERE cs.class_section_id = st.class_section_id) AS class_teacher FROM st) st),
     allowed AS (
        SELECT 1 FROM me, st, pol WHERE me.user_category = 'PARENT' AND pol.parent_can_start AND st.student_id IN (SELECT api.my_children())
        UNION ALL
        SELECT 1 FROM me, st WHERE me.user_category IN ('STAFF', 'NON_STAFF')),
     conv AS (
        INSERT INTO communication.conversation (school_id, kind, student_id, class_section_id, created_by_user_id, parents_can_reply, is_locked, created_at)
        SELECT :school::bigint, coalesce(b.j ->> 'kind', 'PARENT_TEACHER'), st.student_id, st.class_section_id, :me::bigint, true, false, now()
          FROM b, st WHERE EXISTS (SELECT 1 FROM allowed) RETURNING *),
     mem AS (
        INSERT INTO communication.conversation_member (school_id, conversation_id, user_id, member_role, last_read_at)
        SELECT conv.school_id, conv.conversation_id, x.uid, x.role, CASE WHEN x.uid = :me::bigint THEN now() END
          FROM conv, (SELECT :me::bigint AS uid, CASE WHEN (SELECT user_category FROM me) = 'PARENT' THEN 'PARENT' ELSE 'STAFF' END AS role
                      UNION SELECT staff.uid, 'STAFF' FROM staff WHERE (SELECT user_category FROM me) = 'PARENT' AND staff.uid IS NOT NULL
                      UNION SELECT sp.user_id, 'PARENT' FROM academics.student_parent sp, st
                             WHERE sp.student_id = st.student_id AND (SELECT user_category FROM me) <> 'PARENT') x
        ON CONFLICT DO NOTHING RETURNING 1),
     msg AS (
        INSERT INTO communication.message (school_id, conversation_id, sender_user_id, body, sent_at)
        SELECT conv.school_id, conv.conversation_id, :me::bigint, b.j ->> 'firstMessage', now()
          FROM conv, b WHERE coalesce(b.j ->> 'firstMessage', '') <> '' RETURNING body, sent_at)
SELECT jsonb_strip_nulls(jsonb_build_object('conversationId', conv.conversation_id, 'kind', conv.kind,
       'title', coalesce(api.user_name((SELECT uid FROM staff)), 'Conversation'),
       'student', api.student_ref(conv.student_id), 'lastMessage', (SELECT body FROM msg), 'lastMessageAt', (SELECT sent_at FROM msg),
       'unread', 0, 'locked', false, 'withinChatHours', true))
FROM conv;

-- name: listMessages
SELECT api.page(coalesce(jsonb_agg(v ORDER BY (v ->> 'messageId')::bigint DESC), '[]'::jsonb), :page, :size) FROM (
    SELECT jsonb_strip_nulls(jsonb_build_object(
           'messageId', m.message_id, 'sender', api.person(m.sender_user_id),
           'body', CASE WHEN m.deleted_at IS NULL THEN m.body END,
           'attachmentUrls', CASE WHEN m.deleted_at IS NULL THEN to_jsonb(m.attachment_urls) END,
           'sentAt', m.sent_at, 'mine', m.sender_user_id = :me::bigint, 'deleted', m.deleted_at IS NOT NULL)) AS v
      FROM communication.message m
     WHERE m.conversation_id = :conversationId::bigint
       AND EXISTS (SELECT 1 FROM communication.conversation_member cm WHERE cm.conversation_id = m.conversation_id AND cm.user_id = :me::bigint)
) x
WHERE EXISTS (SELECT 1 FROM communication.conversation_member cm WHERE cm.conversation_id = :conversationId::bigint AND cm.user_id = :me::bigint);

-- name: sendMessage write
-- Members only; parents only where the conversation lets them reply; locked conversations take no messages
WITH c AS (SELECT c.* FROM communication.conversation c
             JOIN communication.conversation_member cm ON cm.conversation_id = c.conversation_id AND cm.user_id = :me::bigint
            WHERE c.conversation_id = :conversationId::bigint AND NOT coalesce(c.is_locked, false)
              AND (cm.member_role <> 'PARENT' OR coalesce(c.parents_can_reply, true))),
     ins AS (
    INSERT INTO communication.message (school_id, conversation_id, sender_user_id, body, attachment_urls, sent_at)
    SELECT c.school_id, c.conversation_id, :me::bigint, :body::jsonb ->> 'body',
           (SELECT array_agg(x) FROM jsonb_array_elements_text(coalesce(:body::jsonb -> 'attachmentUrls', '[]'::jsonb)) x), now()
      FROM c RETURNING *),
     rd AS (UPDATE communication.conversation_member SET last_read_at = now()
             WHERE conversation_id = :conversationId::bigint AND user_id = :me::bigint AND EXISTS (SELECT 1 FROM ins) RETURNING 1)
SELECT jsonb_strip_nulls(jsonb_build_object('messageId', message_id, 'sender', api.person(sender_user_id), 'body', body,
       'attachmentUrls', to_jsonb(attachment_urls), 'sentAt', sent_at, 'mine', true, 'deleted', false))
FROM ins;

-- name: markConversationRead write
WITH u AS (UPDATE communication.conversation_member SET last_read_at = now()
            WHERE conversation_id = :conversationId::bigint AND user_id = :me::bigint RETURNING 1)
SELECT CASE WHEN EXISTS (SELECT 1 FROM u) THEN '{}' END;

-- name: getMyShift
WITH days AS (SELECT d::date AS d FROM generate_series(date_trunc('week', current_date), date_trunc('week', current_date) + interval '6 days', interval '1 day') d),
     cell AS (
    SELECT days.d, coalesce(r.shift_code, sa.code) AS shift_code, coalesce(r.start_time, sa.start_time) AS start_t,
           coalesce(r.end_time, sa.end_time) AS end_t, r.post_code,
           coalesce(r.status, CASE WHEN sa.code IS NULL THEN NULL
                                   WHEN position(api.dow(days.d) IN coalesce(sa.weekly_off, '')) > 0 THEN 'WEEKLY_OFF' ELSE 'PLANNED' END) AS status
      FROM days
      LEFT JOIN LATERAL (SELECT sh.code AS shift_code, sh.start_time, sh.end_time, p.code AS post_code, re.status
                           FROM hr.roster_entry re JOIN hr.shift sh ON sh.shift_id = re.shift_id LEFT JOIN hr.post p ON p.post_id = re.post_id
                          WHERE re.user_id = :me::bigint AND re.duty_date = days.d ORDER BY re.roster_entry_id LIMIT 1) r ON true
      LEFT JOIN LATERAL (SELECT sh.code, sh.start_time, sh.end_time, a.weekly_off FROM hr.shift_assignment a JOIN hr.shift sh ON sh.shift_id = a.shift_id
                          WHERE a.user_id = :me::bigint AND a.from_date <= days.d AND (a.to_date IS NULL OR a.to_date >= days.d)
                          ORDER BY a.from_date DESC LIMIT 1) sa ON true),
     j AS (SELECT d, jsonb_strip_nulls(jsonb_build_object('date', d, 'shiftCode', shift_code, 'start', start_t, 'end', end_t,
                                                          'postCode', post_code, 'status', status)) AS v FROM cell)
SELECT jsonb_strip_nulls(jsonb_build_object(
       'today', (SELECT v FROM j WHERE d = current_date),
       'punchInAt', (SELECT min(p.punched_at) FROM operations.attendance_punch p WHERE p.person_kind = 'STAFF' AND p.person_id = :me::bigint
                       AND p.direction = 'IN' AND p.punched_at::date = current_date),
       'punchOutAt', (SELECT max(p.punched_at) FROM operations.attendance_punch p WHERE p.person_kind = 'STAFF' AND p.person_id = :me::bigint
                        AND p.direction = 'OUT' AND p.punched_at::date = current_date),
       'lateMinutes', (SELECT dp.late_minutes FROM operations.daily_presence dp WHERE dp.person_kind = 'STAFF' AND dp.person_id = :me::bigint
                         AND dp.presence_date = current_date LIMIT 1),
       'week', (SELECT jsonb_agg(v ORDER BY d) FROM j)));

-- name: listMyPayslips
SELECT coalesce(jsonb_agg(jsonb_build_object('payslipId', p.payslip_id, 'period', r.period, 'net', p.net, 'gross', p.gross,
                          'status', r.status) ORDER BY r.period DESC), '[]'::jsonb)
FROM hr.payslip p JOIN hr.payroll_run r ON r.run_id = p.run_id
WHERE p.user_id = :me::bigint AND r.status IN ('APPROVED', 'PAID', 'LOCKED');

-- name: unreact write
WITH d AS (DELETE FROM communication.news_reaction WHERE post_id = :postId::bigint AND user_id = :me::bigint RETURNING 1)
SELECT '{}' WHERE EXISTS (SELECT 1 FROM communication.news_post WHERE post_id = :postId::bigint) AND (SELECT count(*) FROM d) >= 0;

-- name: deleteNewsPost write
-- Soft delete by the author (the media purge job removes files later)
WITH up AS (UPDATE communication.news_post SET deleted_at = now()
             WHERE post_id = :postId::bigint AND author_user_id = :me::bigint AND deleted_at IS NULL RETURNING 1)
SELECT CASE WHEN EXISTS (SELECT 1 FROM up) THEN '{}' END;

-- name: cancelLeave write
-- My own pending (or approved, not yet started) leave becomes CANCELLED
WITH up AS (UPDATE hr.leave_request SET status = 'CANCELLED'
             WHERE leave_request_id = :leaveRequestId::bigint AND user_id = :me::bigint
               AND (status = 'PENDING' OR (status = 'APPROVED' AND from_date > current_date)) RETURNING 1)
SELECT CASE WHEN EXISTS (SELECT 1 FROM up) THEN '{}' END;
