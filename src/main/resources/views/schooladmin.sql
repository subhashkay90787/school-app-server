-- Screen queries for /api/v1/school-admin (branch office: setup, records, timetable, fee set-up, messaging).

-- name: getHome
SELECT api.feed('SCHOOL_ADMIN',
    (SELECT api.card('setup', 'NEEDS_YOU', 'SETUP', 'Finish setting up the branch', NULL,
                     NULLIF((SELECT count(*) FROM jsonb_array_elements(api_setup.steps) s WHERE NOT (s ->> 'complete')::boolean), 0), 'ACTION', 'setup-checklist')
       FROM (SELECT (SELECT jsonb_build_array(
                 jsonb_build_object('complete', EXISTS (SELECT 1 FROM academics.academic_year WHERE is_current)),
                 jsonb_build_object('complete', EXISTS (SELECT 1 FROM academics.class_section)),
                 jsonb_build_object('complete', EXISTS (SELECT 1 FROM academics.student)),
                 jsonb_build_object('complete', EXISTS (SELECT 1 FROM academics.timetable)),
                 jsonb_build_object('complete', EXISTS (SELECT 1 FROM finance.fee_structure)))) AS steps) api_setup),
    (SELECT api.card('docs', 'NEEDS_YOU', 'DOCUMENTS', 'Documents to verify', NULL, count(*), 'ACTION', 'documents?unverified=true')
       FROM records.document d WHERE d.verified_by_user_id IS NULL AND d.owner_kind IN ('STUDENT', 'APPLICATION', 'STAFF')),
    (SELECT api.card('no-parent', 'NEEDS_YOU', 'PARENT_LINKS', 'Students without a parent login', NULL, count(*), 'ACTION', 'students?noParent=true')
       FROM academics.student s WHERE s.status = 'ACTIVE' AND NOT EXISTS (SELECT 1 FROM academics.student_parent sp WHERE sp.student_id = s.student_id)),
    (SELECT api.card('clearances', 'NEEDS_YOU', 'CLEARANCES', 'Clearances blocked', NULL, count(*), 'INFO', 'clearances')
       FROM records.clearance c WHERE c.status = 'BLOCKED'),
    (SELECT api.card('imports', 'NOW', 'IMPORTS', 'Imports running', NULL, count(*), 'INFO', 'imports')
       FROM platform.import_job j WHERE j.status IN ('VALIDATING', 'IMPORTING')),
    (SELECT api.card('events', 'TODAY', 'CALENDAR', e.title, to_char(e.start_date, 'Dy DD Mon'), NULL, 'INFO', 'calendar')
       FROM calendar.event e WHERE e.start_date BETWEEN current_date AND current_date + 7 ORDER BY e.start_date LIMIT 1));

-- name: getSetupChecklist
WITH s AS (SELECT * FROM (VALUES
     (1, 'YEAR', 'Academic year and terms', (SELECT count(*) FROM academics.academic_term), 2, 'academic-years'),
     (2, 'SECTIONS', 'Classes and sections', (SELECT count(*) FROM academics.class_section), 1, 'class-sections'),
     (3, 'SUBJECTS', 'Subjects and teachers', (SELECT count(*) FROM academics.staff_subject), 1, 'subjects'),
     (4, 'STUDENTS', 'Students imported', (SELECT count(*) FROM academics.student WHERE status = 'ACTIVE'), 1, 'imports'),
     (5, 'PARENTS', 'Parents linked', (SELECT count(DISTINCT student_id) FROM academics.student_parent),
                   greatest((SELECT count(*) FROM academics.student WHERE status = 'ACTIVE'), 1), 'students'),
     (6, 'TIMETABLE', 'Timetable published', (SELECT count(*) FROM academics.timetable_version WHERE status = 'PUBLISHED'), 1, 'timetable'),
     (7, 'FEES', 'Fee structures', (SELECT count(*) FROM finance.fee_structure), 1, 'fee-structures'),
     (8, 'CALENDAR', 'Holiday calendar', (SELECT count(*) FROM calendar.event WHERE is_holiday), 1, 'calendar'),
     (9, 'CONSENTS', 'Consent forms published', (SELECT count(*) FROM compliance.consent_form WHERE published_at IS NOT NULL), 1, 'consent-forms')
   ) v(ord, key, label, done, total, link))
SELECT jsonb_build_object(
    'steps', (SELECT jsonb_agg(jsonb_build_object('key', key, 'label', label, 'done', least(done, total), 'total', total,
                                                  'complete', done >= total, 'deepLink', link) ORDER BY ord) FROM s),
    'percent', (SELECT round(100.0 * count(*) FILTER (WHERE done >= total) / count(*), 0) FROM s));

-- name: getStudentProfile
SELECT jsonb_strip_nulls(jsonb_build_object(
    'student', api.camel(to_jsonb(s)),
    'parents', coalesce((SELECT jsonb_agg(api.person(sp.user_id, sp.relationship_type) ORDER BY sp.is_primary_contact DESC NULLS LAST)
                           FROM academics.student_parent sp WHERE sp.student_id = s.student_id), '[]'::jsonb),
    'enrollments', coalesce((SELECT jsonb_agg(api.camel(to_jsonb(e)) ORDER BY e.enrolled_on DESC NULLS LAST)
                               FROM academics.student_enrollment e WHERE e.student_id = s.student_id), '[]'::jsonb),
    'documents', coalesce((SELECT jsonb_agg(api.camel(to_jsonb(d) - 'sha256') ORDER BY d.uploaded_at DESC)
                             FROM records.document d WHERE d.owner_kind = 'STUDENT' AND d.owner_id = s.student_id), '[]'::jsonb),
    'hostel', api.hostel_card(s.student_id), 'dues', api.overdue(s.student_id), 'alerts', api.student_alerts(s.student_id)))
FROM academics.student s WHERE s.student_id = :studentId::bigint;

-- name: linkParent write
-- Links an existing user (userId). Invitations by email / phone go through school-auth (PARENT_INVITE) and
-- link on acceptance, so without userId nothing is linked here.
WITH b AS (SELECT :body::jsonb AS j),
     ins AS (INSERT INTO academics.student_parent (school_id, student_id, user_id, relationship_type, is_primary_contact)
             SELECT s.school_id, s.student_id, (b.j ->> 'userId')::bigint, b.j ->> 'relationshipType', coalesce((b.j ->> 'primaryContact')::boolean, false)
               FROM academics.student s, b
              WHERE s.student_id = :studentId::bigint AND (b.j ->> 'userId') IS NOT NULL
                AND EXISTS (SELECT 1 FROM directory.app_user u WHERE u.user_id = (b.j ->> 'userId')::bigint)
             ON CONFLICT (school_id, student_id, user_id) DO UPDATE
                SET relationship_type = coalesce(EXCLUDED.relationship_type, academics.student_parent.relationship_type),
                    is_primary_contact = EXCLUDED.is_primary_contact
             RETURNING *)
SELECT api.camel(to_jsonb(ins)) FROM ins;

-- name: unlinkParent write
WITH d AS (DELETE FROM academics.student_parent WHERE student_id = :studentId::bigint AND user_id = :userId::bigint RETURNING 1)
SELECT CASE WHEN EXISTS (SELECT 1 FROM d) THEN '{}' END;

-- name: getTimetableGrid
SELECT api.timetable_grid(coalesce(:classSectionId::bigint, (SELECT min(class_section_id) FROM academics.class_section)))
WHERE coalesce(:classSectionId::bigint, (SELECT min(class_section_id) FROM academics.class_section)) IS NOT NULL;

-- name: verifyDocument write
WITH up AS (UPDATE records.document SET verified_by_user_id = :me::bigint
             WHERE document_id = :documentId::bigint AND verified_by_user_id IS NULL AND coalesce(uploaded_by_user_id, -1) <> :me::bigint RETURNING *)
SELECT api.camel(to_jsonb(up) - 'sha256') FROM up;

-- name: sendNotification write
SELECT api.create_notification(:body::jsonb, :me::bigint, :school::bigint) AS result;
-- then
SELECT api.camel(to_jsonb(n)) FROM communication.notification n WHERE n.notification_id = :result::bigint;

-- name: setMessagingPolicy write
WITH b AS (SELECT :body::jsonb AS j),
     up AS (INSERT INTO communication.messaging_policy (school_id, parent_can_start_chat, office_hours_start, office_hours_end, show_staff_phone, retention_days)
            SELECT :school::bigint, (j ->> 'parentCanStartChat')::boolean, (j ->> 'officeHoursStart')::time, (j ->> 'officeHoursEnd')::time,
                   (j ->> 'showStaffPhone')::boolean, (j ->> 'retentionDays')::int FROM b
            ON CONFLICT (school_id) DO UPDATE SET
                parent_can_start_chat = coalesce(EXCLUDED.parent_can_start_chat, communication.messaging_policy.parent_can_start_chat),
                office_hours_start = coalesce(EXCLUDED.office_hours_start, communication.messaging_policy.office_hours_start),
                office_hours_end = coalesce(EXCLUDED.office_hours_end, communication.messaging_policy.office_hours_end),
                show_staff_phone = coalesce(EXCLUDED.show_staff_phone, communication.messaging_policy.show_staff_phone),
                retention_days = coalesce(EXCLUDED.retention_days, communication.messaging_policy.retention_days)
            RETURNING *)
SELECT api.camel(to_jsonb(up)) FROM up;
