-- Shared write helpers for screen operations. Repeatable; SECURITY INVOKER (RLS applies to every insert).

-- In-app notification with its recipients resolved from the audience (CircularInput). Delivery over push /
-- WhatsApp / email is the notification flow's job (outbox), not this function's.
--   USERS: audienceIds are user ids · SECTION / PROGRAM / HOSTEL / BLOCK: parents and student users of the
--   active students there · STAFF_TYPE: active staff whose staff_category is in roleCodes · ALL: every parent
--   of an active student and all active staff
CREATE OR REPLACE FUNCTION api.create_notification(p_body JSONB, p_sender BIGINT, p_school BIGINT) RETURNS BIGINT
    LANGUAGE plpgsql VOLATILE AS $$
DECLARE
    v_id BIGINT;
    v_type TEXT := coalesce(p_body ->> 'audienceType', 'ALL');
    v_ids BIGINT[] := ARRAY(SELECT jsonb_array_elements_text(coalesce(p_body -> 'audienceIds', '[]'::jsonb))::bigint);
    v_roles TEXT[] := ARRAY(SELECT jsonb_array_elements_text(coalesce(p_body -> 'roleCodes', '[]'::jsonb)));
BEGIN
    IF coalesce(p_body ->> 'title', '') = '' THEN
        RAISE EXCEPTION 'title is required' USING ERRCODE = '23502';
    END IF;
    INSERT INTO communication.notification (school_id, sent_by_user_id, sent_time, title, category, attachment_urls, body, channel,
                                            audience_type, requires_ack, scheduled_at, severity)
    VALUES (p_school, p_sender, coalesce((p_body ->> 'scheduledAt')::timestamptz, now()), p_body ->> 'title', 'CIRCULAR',
            ARRAY(SELECT jsonb_array_elements_text(coalesce(p_body -> 'attachmentUrls', '[]'::jsonb))), p_body ->> 'body',
            coalesce(p_body ->> 'channel', 'APP'), v_type, coalesce((p_body ->> 'requiresAck')::boolean, false),
            (p_body ->> 'scheduledAt')::timestamptz, coalesce(p_body ->> 'severity', 'INFO'))
    RETURNING notification_id INTO v_id;

    WITH students AS (
        SELECT s.student_id, s.student_user_id FROM academics.student s
         WHERE s.status = 'ACTIVE' AND (
               v_type = 'ALL'
            OR (v_type = 'SECTION' AND s.class_section_id = ANY (v_ids))
            OR (v_type = 'PROGRAM' AND s.class_section_id IN (SELECT cs.class_section_id FROM academics.class_section cs WHERE cs.program_id = ANY (v_ids)))
            OR (v_type = 'HOSTEL' AND s.student_id IN (SELECT a.student_id FROM hostel.allocation a WHERE a.status = 'ACTIVE' AND a.hostel_id = ANY (v_ids)))
            OR (v_type = 'BLOCK' AND s.student_id IN (SELECT a.student_id FROM hostel.allocation a JOIN hostel.room r ON r.room_id = a.room_id
                                                       WHERE a.status = 'ACTIVE' AND r.block_id = ANY (v_ids))))),
         rcpt AS (
        SELECT sp.user_id AS uid, st.student_id AS sid FROM students st JOIN academics.student_parent sp ON sp.student_id = st.student_id
        UNION SELECT st.student_user_id, st.student_id FROM students st WHERE st.student_user_id IS NOT NULL AND v_type <> 'ALL'
        UNION SELECT e.user_id, NULL FROM hr.employee_profile e
               WHERE e.status = 'ACTIVE' AND (v_type = 'ALL' OR (v_type = 'STAFF_TYPE' AND e.staff_category = ANY (v_roles)))
        UNION SELECT u.user_id, NULL FROM directory.app_user u WHERE v_type = 'USERS' AND u.user_id = ANY (v_ids))
    INSERT INTO communication.notification_recipient (school_id, notification_id, recipient_user_id, student_id, delivery_status)
    SELECT p_school, v_id, rcpt.uid, rcpt.sid, 'QUEUED' FROM rcpt WHERE rcpt.uid IS NOT NULL
    ON CONFLICT DO NOTHING;
    RETURN v_id;
END $$;

GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA api TO schoolcrm_app;
