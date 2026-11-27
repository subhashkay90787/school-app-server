-- Screen queries for /api/v1/admissions.

-- name: getHome
SELECT api.feed('ADMISSION_OFFICER',
    (SELECT api.card('follow-ups', 'NEEDS_YOU', 'FOLLOW_UPS', 'Follow-ups due', string_agg(e.child_name, ', '), count(*), 'ACTION', 'enquiries?due=true')
       FROM admissions.enquiry e WHERE e.next_follow_up_at <= now() + interval '2 hours' AND e.stage NOT IN ('APPLIED', 'LOST')
        AND (e.owner_user_id IS NULL OR e.owner_user_id = :me::bigint)),
    (SELECT api.card('new', 'NEEDS_YOU', 'NEW_ENQUIRIES', 'New enquiries to call', NULL, count(*), 'ACTION', 'enquiries?stage=NEW')
       FROM admissions.enquiry e WHERE e.stage = 'NEW'),
    (SELECT api.card('review', 'NEEDS_YOU', 'APPLICATIONS', 'Applications to review', NULL, count(*), 'ACTION', 'applications?status=SUBMITTED')
       FROM admissions.application a WHERE a.status IN ('SUBMITTED', 'UNDER_REVIEW')),
    (SELECT api.card('offers', 'TODAY', 'OFFERS', 'Offers awaiting acceptance', NULL, count(*), 'INFO', 'applications?status=OFFERED')
       FROM admissions.application a WHERE a.status = 'OFFERED'),
    (SELECT api.card('visits', 'TODAY', 'VISITS', 'Campus visits scheduled', NULL, count(*), 'INFO', 'enquiries?stage=VISIT_SCHEDULED')
       FROM admissions.enquiry e WHERE e.stage = 'VISIT_SCHEDULED'));

-- name: createEnquiry write
-- Quick enquiry; same phone or same child name in the year comes back as possible duplicates (still created)
WITH b AS (SELECT :body::jsonb AS j),
     y AS (SELECT academic_year_id FROM academics.academic_year WHERE is_current LIMIT 1),
     ins AS (INSERT INTO admissions.enquiry (school_id, academic_year_id, program_id, child_name, guardian_name, phone, email, source, campaign, stage,
                                             owner_user_id, next_follow_up_at, created_at)
             SELECT :school::bigint, (SELECT academic_year_id FROM y), (b.j ->> 'programId')::bigint, b.j ->> 'childName', b.j ->> 'guardianName',
                    b.j ->> 'phone', b.j ->> 'email', coalesce(b.j ->> 'source', 'WALK_IN'), b.j ->> 'campaign', 'NEW', :me::bigint,
                    now() + interval '1 day', now() FROM b RETURNING enquiry_id)
SELECT enquiry_id AS result FROM ins;
-- then
SELECT jsonb_build_object('enquiry', api.camel(to_jsonb(e)),
    'possibleDuplicates', coalesce((SELECT jsonb_agg(api.camel(to_jsonb(d)) ORDER BY d.created_at DESC) FROM admissions.enquiry d
                                     WHERE d.enquiry_id <> e.enquiry_id AND (regexp_replace(d.phone, '\D', '', 'g') = regexp_replace(e.phone, '\D', '', 'g')
                                                                            OR lower(d.child_name) = lower(e.child_name))), '[]'::jsonb))
FROM admissions.enquiry e WHERE e.enquiry_id = :result::bigint;

-- name: getPipeline
WITH y AS (SELECT coalesce(:academicYearId::bigint, (SELECT academic_year_id FROM academics.academic_year WHERE is_current LIMIT 1)) AS id)
SELECT jsonb_build_object('stages', (SELECT jsonb_agg(jsonb_build_object('stage', st, 'count',
          (SELECT count(*) FROM admissions.enquiry e, y WHERE e.stage = st AND (e.academic_year_id = y.id OR e.academic_year_id IS NULL)),
          'items', coalesce((SELECT jsonb_agg(api.camel(to_jsonb(e)) ORDER BY e.next_follow_up_at NULLS LAST, e.created_at DESC)
                               FROM (SELECT e.* FROM admissions.enquiry e, y WHERE e.stage = st AND (e.academic_year_id = y.id OR e.academic_year_id IS NULL)
                                      ORDER BY e.next_follow_up_at NULLS LAST, e.created_at DESC LIMIT 50) e), '[]'::jsonb)) ORDER BY o)
     FROM unnest(ARRAY['NEW', 'CONTACTED', 'VISIT_SCHEDULED', 'VISITED', 'APPLIED', 'LOST']) WITH ORDINALITY AS s(st, o)));

-- name: decideApplication write
WITH b AS (SELECT :body::jsonb AS j),
     up AS (UPDATE admissions.application a SET status = b.j ->> 'decision', decided_by_user_id = :me::bigint, decided_at = now()
              FROM b WHERE a.application_id = :applicationId::bigint AND b.j ->> 'decision' IN ('OFFERED', 'WAITLISTED', 'REJECTED')
               AND a.status IN ('SUBMITTED', 'UNDER_REVIEW', 'ASSESSMENT', 'WAITLISTED')
            RETURNING a.*)
SELECT api.camel(to_jsonb(up)) FROM up;

-- name: previewConversion
-- What converting the application would create (student, parents, enrollment, first dues, hostel / transport asks)
WITH a AS (SELECT * FROM admissions.application WHERE application_id = :applicationId::bigint),
     y AS (SELECT * FROM academics.academic_year WHERE academic_year_id = (SELECT academic_year_id FROM a))
SELECT jsonb_build_object('applicationId', a.application_id,
    'student', coalesce(a.form_data -> 'child', '{}'::jsonb) || jsonb_build_object('residencyType', coalesce(a.residency_requested, 'DAY_SCHOLAR')),
    'parents', coalesce(a.form_data -> 'parents', '[]'::jsonb),
    'enrollment', jsonb_build_object('programId', a.program_id, 'academicYearId', a.academic_year_id,
                    'program', (SELECT name FROM academics.program WHERE program_id = a.program_id), 'year', (SELECT name FROM y)),
    'firstFees', coalesce((SELECT jsonb_agg(jsonb_build_object('feeStructureId', fs.fee_structure_id, 'feeType', fs.fee_type, 'amount', fs.amount,
                              'billingFrequency', fs.billing_frequency))
                             FROM finance.fee_structure fs WHERE fs.academic_year_id = a.academic_year_id
                              AND (fs.program_id = a.program_id OR (fs.program_id IS NULL AND fs.hostel_id IS NULL AND a.residency_requested = 'HOSTELLER'))), '[]'::jsonb),
    'hostelRequest', a.residency_requested = 'HOSTELLER', 'transportRequest', coalesce(a.transport_requested, false),
    'warnings', to_jsonb(array_remove(ARRAY[
        CASE WHEN a.status NOT IN ('OFFERED', 'ACCEPTED') THEN 'Application is ' || lower(a.status) || ', not accepted' END,
        CASE WHEN a.student_id IS NOT NULL THEN 'Already converted' END,
        CASE WHEN a.form_data -> 'child' ->> 'firstName' IS NULL THEN 'Child name missing in the form' END,
        CASE WHEN (SELECT total_seats FROM admissions.seat_plan sp WHERE sp.program_id = a.program_id AND sp.academic_year_id = a.academic_year_id)
                  <= (SELECT count(*) FROM admissions.application x WHERE x.program_id = a.program_id AND x.academic_year_id = a.academic_year_id AND x.status = 'ENROLLED')
             THEN 'No seats left in the program' END], NULL)))
FROM a;

-- name: getSeatMatrix
WITH y AS (SELECT coalesce(:academicYearId::bigint, (SELECT academic_year_id FROM academics.academic_year WHERE is_current LIMIT 1)) AS id)
SELECT coalesce(jsonb_agg(jsonb_build_object('programId', p.program_id, 'program', p.name, 'total', coalesce(sp.total_seats, 0),
       'rte', coalesce(sp.rte_seats, 0), 'management', coalesce(sp.management_seats, 0), 'hostel', coalesce(sp.hostel_seats, 0),
       'offered', (SELECT count(*) FROM admissions.application a, y WHERE a.program_id = p.program_id AND a.academic_year_id = y.id AND a.status IN ('OFFERED', 'ACCEPTED')),
       'enrolled', (SELECT count(*) FROM admissions.application a, y WHERE a.program_id = p.program_id AND a.academic_year_id = y.id AND a.status = 'ENROLLED'),
       'remaining', coalesce(sp.total_seats, 0) - (SELECT count(*) FROM admissions.application a, y WHERE a.program_id = p.program_id AND a.academic_year_id = y.id
                                                     AND a.status IN ('OFFERED', 'ACCEPTED', 'ENROLLED'))) ORDER BY p.name), '[]'::jsonb)
FROM academics.program p CROSS JOIN y LEFT JOIN admissions.seat_plan sp ON sp.program_id = p.program_id AND sp.academic_year_id = y.id;

-- name: upsertSeatPlan write
WITH b AS (SELECT :body::jsonb AS j),
     up AS (INSERT INTO admissions.seat_plan (school_id, academic_year_id, program_id, total_seats, rte_seats, management_seats, hostel_seats)
            SELECT :school::bigint, (j ->> 'academicYearId')::bigint, (j ->> 'programId')::bigint, (j ->> 'totalSeats')::int, (j ->> 'rteSeats')::int,
                   (j ->> 'managementSeats')::int, (j ->> 'hostelSeats')::int FROM b
            ON CONFLICT (school_id, academic_year_id, program_id) DO UPDATE SET
                total_seats = coalesce(EXCLUDED.total_seats, admissions.seat_plan.total_seats), rte_seats = coalesce(EXCLUDED.rte_seats, admissions.seat_plan.rte_seats),
                management_seats = coalesce(EXCLUDED.management_seats, admissions.seat_plan.management_seats),
                hostel_seats = coalesce(EXCLUDED.hostel_seats, admissions.seat_plan.hostel_seats)
            RETURNING *)
SELECT api.camel(to_jsonb(up)) FROM up;

-- name: inviteReenrollment write
-- An INVITED row for every active student of the sections (all sections when none are named) for the year
WITH b AS (SELECT :body::jsonb AS j),
     sec AS (SELECT jsonb_array_elements_text(coalesce(b.j -> 'classSectionIds', '[]'::jsonb))::bigint AS id FROM b),
     st AS (SELECT s.student_id FROM academics.student s WHERE s.status = 'ACTIVE'
              AND (NOT EXISTS (SELECT 1 FROM sec) OR s.class_section_id IN (SELECT id FROM sec))),
     ins AS (INSERT INTO admissions.reenrollment (school_id, student_id, academic_year_id, status)
             SELECT :school::bigint, st.student_id, (b.j ->> 'academicYearId')::bigint, 'INVITED' FROM st, b
              WHERE NOT EXISTS (SELECT 1 FROM admissions.reenrollment r WHERE r.student_id = st.student_id AND r.academic_year_id = (b.j ->> 'academicYearId')::bigint)
             RETURNING 1)
SELECT jsonb_build_object('requested', (SELECT count(*) FROM st), 'succeeded', (SELECT count(*) FROM ins),
                          'failed', 0, 'errors', '[]'::jsonb);

-- name: getFunnel
WITH y AS (SELECT coalesce(:academicYearId::bigint, (SELECT academic_year_id FROM academics.academic_year WHERE is_current LIMIT 1)) AS id),
     e AS (SELECT e.* FROM admissions.enquiry e, y WHERE e.academic_year_id = y.id OR e.academic_year_id IS NULL),
     a AS (SELECT a.* FROM admissions.application a, y WHERE a.academic_year_id = y.id)
SELECT jsonb_build_object('academicYearId', (SELECT id FROM y),
    'stages', jsonb_build_array(
        api.kpi('ENQUIRIES', 'Enquiries', (SELECT count(*) FROM e)),
        api.kpi('CONTACTED', 'Contacted', (SELECT count(*) FROM e WHERE stage <> 'NEW')),
        api.kpi('VISITED', 'Visited', (SELECT count(*) FROM e WHERE stage IN ('VISITED', 'APPLIED'))),
        api.kpi('APPLIED', 'Applied', (SELECT count(*) FROM a WHERE status <> 'DRAFT')),
        api.kpi('OFFERED', 'Offered', (SELECT count(*) FROM a WHERE status IN ('OFFERED', 'ACCEPTED', 'ENROLLED'))),
        api.kpi('ENROLLED', 'Enrolled', (SELECT count(*) FROM a WHERE status = 'ENROLLED'))),
    'conversionPct', (SELECT round(100.0 * (SELECT count(*) FROM a WHERE status = 'ENROLLED') / nullif(count(*), 0), 1) FROM e),
    'bySource', coalesce((SELECT jsonb_object_agg(coalesce(source, 'UNKNOWN'), n) FROM (SELECT source, count(*) AS n FROM e GROUP BY source) x), '{}'::jsonb));
