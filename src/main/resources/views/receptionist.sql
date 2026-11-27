-- Screen queries for /api/v1/front-office (visitors, early leave, parcels, enquiries).

-- name: getHome
SELECT api.feed('RECEPTIONIST',
    (SELECT api.card('blacklisted', 'CRITICAL', 'BLACKLISTED_VISITOR', 'Blacklisted visitor on campus', string_agg(v.name, ', '), count(*), 'CRITICAL', 'visits')
       FROM frontoffice.visit vi JOIN frontoffice.visitor v ON v.visitor_id = vi.visitor_id WHERE vi.check_out_at IS NULL AND coalesce(v.is_blacklisted, false)),
    (SELECT api.card('early-leave', 'NEEDS_YOU', 'EARLY_LEAVE', 'Early-leave pickups waiting', NULL, count(*), 'ACTION', 'gate-passes')
       FROM frontoffice.gate_pass g WHERE g.approved_by_user_id IS NOT NULL AND g.out_at IS NULL),
    (SELECT api.card('parcels', 'NEEDS_YOU', 'PARCELS', 'Parcels to hand over', NULL, count(*), 'ACTION', 'parcels')
       FROM frontoffice.parcel p WHERE p.direction = 'IN' AND p.handed_over_at IS NULL),
    (SELECT api.card('on-campus', 'NOW', 'VISITORS_IN', 'Visitors on campus', string_agg(v.name, ', '), count(*), 'INFO', 'visits')
       FROM frontoffice.visit vi JOIN frontoffice.visitor v ON v.visitor_id = vi.visitor_id WHERE vi.check_out_at IS NULL),
    (SELECT api.card('enquiries', 'TODAY', 'ENQUIRIES', 'Enquiries today', NULL, count(*), 'INFO', 'enquiries')
       FROM admissions.enquiry e WHERE e.created_at::date = current_date));

-- name: checkInVisitor write
-- Finds the visitor by phone (or registers them); blacklisted visitors are refused (409)
WITH b AS (SELECT :body::jsonb AS j),
     found AS (SELECT v.* FROM frontoffice.visitor v, b WHERE regexp_replace(v.phone, '\D', '', 'g') = regexp_replace(b.j ->> 'phone', '\D', '', 'g') LIMIT 1),
     newv AS (INSERT INTO frontoffice.visitor (school_id, name, phone, photo_url, id_proof_type, id_proof_last4)
              SELECT :school::bigint, b.j ->> 'name', b.j ->> 'phone', b.j ->> 'photoUrl', b.j ->> 'idProofType', b.j ->> 'idProofLast4'
                FROM b WHERE NOT EXISTS (SELECT 1 FROM found) RETURNING visitor_id),
     vis AS (SELECT visitor_id FROM found WHERE NOT coalesce(is_blacklisted, false) UNION ALL SELECT visitor_id FROM newv),
     ins AS (INSERT INTO frontoffice.visit (school_id, visitor_id, purpose, host_user_id, student_id, pickup_person_id, badge_number, check_in_at)
             SELECT :school::bigint, vis.visitor_id, coalesce(b.j ->> 'purpose', 'OTHER'), (b.j ->> 'hostUserId')::bigint, (b.j ->> 'studentId')::bigint,
                    (b.j ->> 'pickupPersonId')::bigint, b.j ->> 'badgeNumber', now() FROM vis, b RETURNING *)
SELECT api.camel(to_jsonb(ins)) FROM ins;

-- name: checkOutVisitor write
WITH up AS (UPDATE frontoffice.visit SET check_out_at = now() WHERE visit_id = :visitId::bigint AND check_out_at IS NULL RETURNING *)
SELECT api.camel(to_jsonb(up)) FROM up;

-- name: handOverParcel write
WITH up AS (UPDATE frontoffice.parcel p SET handed_over_at = now(), handed_over_by_user_id = :me::bigint
             WHERE p.parcel_id = :parcelId::bigint AND p.handed_over_at IS NULL RETURNING p.*)
SELECT api.camel(to_jsonb(up)) FROM up;

-- name: createEnquiry write
WITH b AS (SELECT :body::jsonb AS j),
     y AS (SELECT academic_year_id FROM academics.academic_year WHERE is_current LIMIT 1),
     ins AS (INSERT INTO admissions.enquiry (school_id, academic_year_id, program_id, child_name, guardian_name, phone, email, source, campaign, stage,
                                             next_follow_up_at, created_at)
             SELECT :school::bigint, (SELECT academic_year_id FROM y), (b.j ->> 'programId')::bigint, b.j ->> 'childName', b.j ->> 'guardianName',
                    b.j ->> 'phone', b.j ->> 'email', coalesce(b.j ->> 'source', 'WALK_IN'), b.j ->> 'campaign', 'NEW', now() + interval '1 day', now()
               FROM b RETURNING enquiry_id)
SELECT enquiry_id AS result FROM ins;
-- then
SELECT jsonb_build_object('enquiry', api.camel(to_jsonb(e)),
    'possibleDuplicates', coalesce((SELECT jsonb_agg(api.camel(to_jsonb(d)) ORDER BY d.created_at DESC) FROM admissions.enquiry d
                                     WHERE d.enquiry_id <> e.enquiry_id AND (regexp_replace(d.phone, '\D', '', 'g') = regexp_replace(e.phone, '\D', '', 'g')
                                                                            OR lower(d.child_name) = lower(e.child_name))), '[]'::jsonb))
FROM admissions.enquiry e WHERE e.enquiry_id = :result::bigint;

-- name: getLog
WITH d AS (SELECT coalesce(:date::date, current_date) AS day)
SELECT coalesce(jsonb_agg(x ORDER BY x ->> 'at' DESC), '[]'::jsonb) FROM (
    SELECT jsonb_build_object('at', vi.check_in_at, 'kind', 'VISIT_IN', 'title', v.name || ' · ' || initcap(replace(vi.purpose, '_', ' ')), 'refId', vi.visit_id) AS x
      FROM frontoffice.visit vi JOIN frontoffice.visitor v ON v.visitor_id = vi.visitor_id, d WHERE vi.check_in_at::date = d.day
    UNION ALL
    SELECT jsonb_build_object('at', vi.check_out_at, 'kind', 'VISIT_OUT', 'title', v.name, 'refId', vi.visit_id)
      FROM frontoffice.visit vi JOIN frontoffice.visitor v ON v.visitor_id = vi.visitor_id, d WHERE vi.check_out_at::date = d.day
    UNION ALL
    SELECT jsonb_build_object('at', g.out_at, 'kind', 'GATE_PASS', 'title', (api.student_ref(g.student_id) ->> 'name') || coalesce(' · ' || g.reason, ''), 'refId', g.gate_pass_id)
      FROM frontoffice.gate_pass g, d WHERE g.out_at::date = d.day
    UNION ALL
    SELECT jsonb_build_object('at', p.received_at, 'kind', 'PARCEL_IN', 'title', coalesce(p.courier, 'Parcel') || ' for ' ||
                              coalesce(api.student_ref(p.for_student_id) ->> 'name', api.user_name(p.for_user_id), 'office'), 'refId', p.parcel_id)
      FROM frontoffice.parcel p, d WHERE p.received_at::date = d.day
    UNION ALL
    SELECT jsonb_build_object('at', p.handed_over_at, 'kind', 'PARCEL_OUT', 'title', coalesce(p.courier, 'Parcel') || ' handed over', 'refId', p.parcel_id)
      FROM frontoffice.parcel p, d WHERE p.handed_over_at::date = d.day
    UNION ALL
    SELECT jsonb_build_object('at', e.created_at, 'kind', 'ENQUIRY', 'title', e.child_name || ' · ' || coalesce(e.guardian_name, e.phone), 'refId', e.enquiry_id)
      FROM admissions.enquiry e, d WHERE e.created_at::date = d.day
) y;
