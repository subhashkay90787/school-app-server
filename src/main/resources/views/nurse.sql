-- Screen queries for /api/v1/nurse (infirmary: whole branch).

-- name: getHome
SELECT api.feed('NURSE',
    (SELECT api.card('hospital', 'CRITICAL', 'REFERRALS', 'Hospital referrals today', NULL, count(*), 'URGENT', 'visits')
       FROM wellbeing.infirmary_visit v WHERE v.disposition = 'HOSPITAL_REFERRAL' AND v.visited_at::date = current_date),
    (SELECT api.card('notify', 'NEEDS_YOU', 'NOTIFY_PARENT', 'Parents not yet told', NULL, count(*), 'ACTION', 'visits?notified=false')
       FROM wellbeing.infirmary_visit v WHERE v.person_kind = 'STUDENT' AND v.parent_notified_at IS NULL AND v.visited_at > now() - interval '1 day'
        AND v.disposition IN ('SICK_BAY', 'SENT_HOME', 'HOSPITAL_REFERRAL')),
    (SELECT api.card('sick-bay', 'NOW', 'SICK_BAY', 'In sick bay', string_agg(api.student_ref(v.person_id) ->> 'name', ', '), count(*), 'INFO', 'sick-bay')
       FROM wellbeing.infirmary_visit v WHERE v.person_kind = 'STUDENT' AND v.disposition = 'SICK_BAY' AND v.discharged_at IS NULL),
    (SELECT api.card('visits', 'TODAY', 'VISITS', 'Visits today', NULL, count(*), 'INFO', 'visits')
       FROM wellbeing.infirmary_visit v WHERE v.visited_at::date = current_date),
    (SELECT api.card('vaccines', 'FEED', 'VACCINATIONS', 'Vaccination doses due', NULL, count(*), 'INFO', 'vaccinations/due')
       FROM academics.student s WHERE s.status = 'ACTIVE' AND NOT EXISTS (SELECT 1 FROM wellbeing.vaccination v WHERE v.student_id = s.student_id)));

-- name: notifyParent write
-- Marks the parents as told (the message itself is sent by the notification flow)
WITH up AS (UPDATE wellbeing.infirmary_visit SET parent_notified_at = coalesce(parent_notified_at, now())
             WHERE visit_id = :visitId::bigint AND person_kind = 'STUDENT' RETURNING *)
SELECT api.camel(to_jsonb(up)) FROM up;

-- name: getPatient
-- Health details are shown only with the parents' consent for health records (when such a form is published)
WITH s AS (SELECT * FROM academics.student WHERE student_id = :studentId::bigint),
     consent AS (SELECT CASE WHEN NOT EXISTS (SELECT 1 FROM compliance.consent_form f WHERE f.feature_code = 'HEALTH' AND f.published_at IS NOT NULL) THEN true
                             ELSE coalesce((SELECT r.decision = 'GRANTED' FROM compliance.consent_record r JOIN compliance.consent_form f ON f.form_id = r.form_id
                                             WHERE f.feature_code = 'HEALTH' AND r.subject_kind = 'STUDENT' AND r.subject_id = :studentId::bigint
                                             ORDER BY r.decided_at DESC LIMIT 1), false) END AS ok)
SELECT jsonb_strip_nulls(jsonb_build_object('student', api.student_ref(s.student_id), 'consentGranted', consent.ok,
    'medicalProfile', CASE WHEN consent.ok THEN (SELECT api.camel(to_jsonb(mp)) FROM wellbeing.medical_profile mp WHERE mp.student_id = s.student_id) END,
    'vaccinations', CASE WHEN consent.ok THEN coalesce((SELECT jsonb_agg(api.camel(to_jsonb(v)) ORDER BY v.given_on DESC NULLS LAST) FROM wellbeing.vaccination v WHERE v.student_id = s.student_id), '[]'::jsonb) END,
    'checkups', CASE WHEN consent.ok THEN coalesce((SELECT jsonb_agg(api.camel(to_jsonb(c)) ORDER BY c.checkup_date DESC) FROM wellbeing.health_checkup c WHERE c.student_id = s.student_id), '[]'::jsonb) END,
    'recentVisits', coalesce((SELECT jsonb_agg(api.camel(to_jsonb(v)) ORDER BY v.visited_at DESC) FROM (SELECT * FROM wellbeing.infirmary_visit v
                               WHERE v.person_kind = 'STUDENT' AND v.person_id = s.student_id ORDER BY v.visited_at DESC LIMIT 10) v), '[]'::jsonb)))
FROM s, consent;

-- name: listVaccinationsDue
-- Next dose per vaccine already started (yearly boosters after 12 months); students with no record at all
SELECT coalesce(jsonb_agg(x ORDER BY x ->> 'dueOn' NULLS FIRST), '[]'::jsonb) FROM (
    SELECT jsonb_strip_nulls(jsonb_build_object('student', api.student_ref(v.student_id), 'vaccine', v.vaccine, 'dose', v.dose + 1,
           'dueOn', (v.given_on + interval '12 months')::date)) AS x
      FROM (SELECT DISTINCT ON (student_id, vaccine) * FROM wellbeing.vaccination ORDER BY student_id, vaccine, dose DESC) v
     WHERE v.given_on + interval '12 months' <= current_date + 30
    UNION ALL
    SELECT jsonb_build_object('student', api.student_ref(s.student_id), 'vaccine', 'Record missing', 'dose', 1)
      FROM academics.student s WHERE s.status = 'ACTIVE' AND NOT EXISTS (SELECT 1 FROM wellbeing.vaccination v WHERE v.student_id = s.student_id)
) y;

-- name: recordCheckups write
WITH b AS (SELECT :body::jsonb AS j),
     e AS (SELECT (x ->> 'studentId')::bigint AS sid, x FROM b, jsonb_array_elements(coalesce(b.j -> 'entries', '[]'::jsonb)) x),
     ok AS (SELECT e.* FROM e JOIN academics.student s ON s.student_id = e.sid AND s.class_section_id = :classSectionId::bigint),
     ins AS (INSERT INTO wellbeing.health_checkup (school_id, student_id, checkup_date, height_cm, weight_kg, vision, dental, notes, conducted_by_user_id)
             SELECT :school::bigint, ok.sid, coalesce((b.j ->> 'checkupDate')::date, current_date), (ok.x ->> 'heightCm')::numeric, (ok.x ->> 'weightKg')::numeric,
                    ok.x ->> 'vision', ok.x ->> 'dental', ok.x ->> 'notes', :me::bigint FROM ok, b RETURNING student_id)
SELECT jsonb_build_object('requested', (SELECT count(*) FROM e), 'succeeded', (SELECT count(*) FROM ins),
    'failed', (SELECT count(*) FROM e) - (SELECT count(*) FROM ins),
    'errors', coalesce((SELECT jsonb_agg(jsonb_build_object('refId', e.sid, 'code', 'NOT_IN_SECTION', 'message', 'Student is not in this section'))
                          FROM e WHERE e.sid NOT IN (SELECT sid FROM ok)), '[]'::jsonb));
