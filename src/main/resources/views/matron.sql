-- Screen queries for /api/v1/matron: medication, sick bay and residents of the caller's hostels.

-- name: getHome
WITH h AS (SELECT api.my_hostels() AS id),
     res AS (SELECT a.student_id FROM hostel.allocation a WHERE a.status = 'ACTIVE' AND a.hostel_id IN (SELECT id FROM h))
SELECT api.feed('MATRON',
    (SELECT api.card('missed', 'CRITICAL', 'DOSE_MISSED', 'Doses overdue by an hour', NULL, count(*), 'URGENT', 'medication/due')
       FROM wellbeing.medication_dose d JOIN wellbeing.medication_schedule s ON s.schedule_id = d.schedule_id
      WHERE d.given_at IS NULL AND d.status IS NULL AND d.due_at < now() - interval '1 hour' AND d.due_at::date = current_date AND s.student_id IN (SELECT student_id FROM res)),
    (SELECT api.card('due', 'NEEDS_YOU', 'DOSES_DUE', 'Medication due in the next 2 hours', NULL, count(*), 'ACTION', 'medication/due')
       FROM wellbeing.medication_dose d JOIN wellbeing.medication_schedule s ON s.schedule_id = d.schedule_id
      WHERE d.given_at IS NULL AND d.status IS NULL AND d.due_at BETWEEN now() - interval '1 hour' AND now() + interval '2 hours' AND s.student_id IN (SELECT student_id FROM res)),
    (SELECT api.card('sick-bay', 'NOW', 'SICK_BAY', 'In sick bay', string_agg(api.student_ref(v.person_id) ->> 'name', ', '), count(*), 'INFO', 'sick-bay')
       FROM wellbeing.infirmary_visit v WHERE v.person_kind = 'STUDENT' AND v.disposition = 'SICK_BAY' AND v.discharged_at IS NULL AND v.person_id IN (SELECT student_id FROM res)),
    (SELECT api.card('laundry', 'TODAY', 'LAUNDRY', 'Laundry batches out', NULL, count(*), 'INFO', 'laundry')
       FROM hostel.laundry_batch l WHERE l.returned_at IS NULL AND l.hostel_id IN (SELECT id FROM h)));

-- name: listMedicationDue
SELECT coalesce(jsonb_agg(jsonb_build_object('doseId', d.dose_id, 'student', api.student_ref(s.student_id), 'medicine', s.medicine, 'dose', s.dose, 'dueAt', d.due_at)
       ORDER BY d.due_at), '[]'::jsonb)
FROM wellbeing.medication_dose d JOIN wellbeing.medication_schedule s ON s.schedule_id = d.schedule_id
JOIN hostel.allocation a ON a.student_id = s.student_id AND a.status = 'ACTIVE'
WHERE d.given_at IS NULL AND d.status IS NULL AND a.hostel_id IN (SELECT api.my_hostels())
  AND d.due_at >= coalesce(:from::timestamptz, current_date::timestamptz) AND d.due_at < coalesce(:to::timestamptz, (current_date + 1)::timestamptz);

-- name: recordDose write
WITH b AS (SELECT :body::jsonb AS j),
     up AS (UPDATE wellbeing.medication_dose d SET status = coalesce(b.j ->> 'status', 'GIVEN'),
                   given_at = CASE WHEN coalesce(b.j ->> 'status', 'GIVEN') = 'GIVEN' THEN coalesce((b.j ->> 'givenAt')::timestamptz, now()) END,
                   given_by_user_id = :me::bigint
              FROM b, wellbeing.medication_schedule s, hostel.allocation a
             WHERE d.dose_id = :doseId::bigint AND s.schedule_id = d.schedule_id AND a.student_id = s.student_id AND a.status = 'ACTIVE'
               AND a.hostel_id IN (SELECT api.my_hostels()) AND d.given_at IS NULL
               AND (coalesce(b.j ->> 'status', 'GIVEN') = 'GIVEN' OR coalesce(b.j ->> 'reason', '') <> '')
            RETURNING d.*)
SELECT api.camel(to_jsonb(up)) FROM up;

-- name: admitToSickBay write
WITH b AS (SELECT :body::jsonb AS j),
     st AS (SELECT a.* FROM hostel.allocation a, b WHERE a.student_id = (b.j ->> 'studentId')::bigint AND a.status = 'ACTIVE' AND a.hostel_id IN (SELECT api.my_hostels())),
     ins AS (INSERT INTO wellbeing.infirmary_visit (school_id, person_kind, person_id, visited_at, complaint, vitals, attended_by_user_id, disposition)
             SELECT st.school_id, 'STUDENT', st.student_id, now(), b.j ->> 'complaint', b.j -> 'vitals', :me::bigint, 'SICK_BAY'
               FROM st, b WHERE NOT EXISTS (SELECT 1 FROM wellbeing.infirmary_visit v WHERE v.person_kind = 'STUDENT' AND v.person_id = st.student_id
                                              AND v.disposition = 'SICK_BAY' AND v.discharged_at IS NULL)
             RETURNING *)
SELECT api.camel(to_jsonb(ins)) FROM ins;

-- name: discharge write
WITH b AS (SELECT :body::jsonb AS j),
     up AS (UPDATE wellbeing.infirmary_visit v SET disposition = coalesce(b.j ->> 'disposition', 'BACK_TO_CLASS'), discharged_at = now(),
                   treatment = concat_ws(E'\n', v.treatment, b.j ->> 'note')
              FROM b WHERE v.visit_id = :visitId::bigint AND v.discharged_at IS NULL AND v.person_kind = 'STUDENT'
               AND v.person_id IN (SELECT a.student_id FROM hostel.allocation a WHERE a.status = 'ACTIVE' AND a.hostel_id IN (SELECT api.my_hostels()))
            RETURNING v.*)
SELECT api.camel(to_jsonb(up)) FROM up;

-- name: listResidents
SELECT coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object('student', api.student_ref(a.student_id), 'room', r.room_number, 'bed', b.bed_label,
       'status', api.hostel_status(a.student_id), 'alerts', api.student_alerts(a.student_id))) ORDER BY r.room_number, b.bed_label), '[]'::jsonb)
FROM hostel.allocation a JOIN hostel.room r ON r.room_id = a.room_id JOIN hostel.bed b ON b.bed_id = a.bed_id
WHERE a.status = 'ACTIVE' AND a.hostel_id IN (SELECT api.my_hostels());
