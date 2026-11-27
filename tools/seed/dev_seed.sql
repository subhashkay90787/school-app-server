-- Development seed for branch 1 (KPHB Campus): enough rows for every screen query to return something real.
-- Run as the database owner on an empty school DB:  psql -v ON_ERROR_STOP=1 -d school_app_db -f tools/seed/dev_seed.sql
-- Dates are relative to current_date so "today" screens stay alive. User ids match tools/seed/auth_dev_users.sql.
BEGIN;

-- ---------------------------------------------------------------- people (thin directory cache of auth users)
INSERT INTO directory.app_user (user_id, first_name, last_name, phone_number, email, user_category) VALUES
 (3, 'Priya', 'Rao', '+919100000002', 'principal@stm.com', 'STAFF'),
 (4, 'Ravi', 'Kumar', '+919100000003', 'teacher@stm.com', 'STAFF'),
 (5, 'Lab', 'Asst', '+919100000004', 'lab@stm.com', 'STAFF'),
 (6, 'Anita', 'Devi', '+919100000005', 'parent@x.com', 'PARENT'),
 (2, 'Office', 'Head', '+919100000001', 'office@stm.com', 'STAFF'),
 (7, 'Trustee', 'Org', '+919100000009', 'trustee@stm.com', 'STAFF'),
 (8, 'Kavya', 'Accounts', '+919100100008', 'accounts@stm.com', 'STAFF'),
 (9, 'Harish', 'HR', '+919100100009', 'hr@stm.com', 'STAFF'),
 (10, 'Neha', 'Admissions', '+919100100010', 'admissions@stm.com', 'STAFF'),
 (11, 'Lata', 'Front', '+919100100011', 'reception@stm.com', 'STAFF'),
 (12, 'Ramesh', 'Chief', '+919100100012', 'chiefwarden@stm.com', 'STAFF'),
 (13, 'Gopal', 'Warden', '+919100100013', 'warden@stm.com', 'STAFF'),
 (14, 'Sarala', 'Matron', '+919100100014', 'matron@stm.com', 'STAFF'),
 (15, 'Dr Asha', 'Nurse', '+919100100015', 'nurse@stm.com', 'STAFF'),
 (16, 'Mohan', 'Mess', '+919100100016', 'mess@stm.com', 'STAFF'),
 (17, 'Bhim', 'Guard', '+919100100017', 'guard@stm.com', 'STAFF'),
 (18, 'Vikram', 'Supervisor', '+919100100018', 'secsup@stm.com', 'STAFF'),
 (19, 'Store', 'Keeper', '+919100100019', 'store@stm.com', 'STAFF'),
 (20, 'Tarun', 'Transport', '+919100100020', 'transport@stm.com', 'STAFF'),
 (21, 'Raju', 'Driver', '+919100100021', 'driver@stm.com', 'NON_STAFF'),
 (22, 'Meena', 'Iyer', '+919100100022', 'meena@stm.com', 'STAFF'),
 (23, 'Arjun', 'Devi', '+919100100023', 'arjun@stm.com', 'STUDENT'),
 (24, 'Farhan', 'Ali', '+919100100024', 'farhan@x.com', 'PARENT'),
 (25, 'Org', 'Director', '+919100000025', 'director@stm.com', 'STAFF')
ON CONFLICT (user_id) DO UPDATE SET first_name = EXCLUDED.first_name, last_name = EXCLUDED.last_name,
  phone_number = EXCLUDED.phone_number, email = EXCLUDED.email, user_category = EXCLUDED.user_category;

-- ---------------------------------------------------------------- academics
INSERT INTO academics.academic_year (school_id, academic_year_id, name, start_date, end_date, is_current) VALUES
 (1, 1, '2026-27', date_trunc('year', current_date)::date + 151, date_trunc('year', current_date)::date + 515, true);
INSERT INTO academics.academic_term (school_id, term_id, academic_year_id, term_type, name, sequence, start_date, end_date) VALUES
 (1, 1, 1, 'TERM', 'Term 1', 1, current_date - 120, current_date + 20),
 (1, 2, 1, 'TERM', 'Term 2', 2, current_date + 21, current_date + 200);
INSERT INTO academics.department (school_id, department_id, department_code, name, head_user_id) VALUES
 (1, 1, 'SCI', 'Science & Maths', 4), (1, 2, 'LANG', 'Languages', 22), (1, 3, 'ADM', 'Administration', 7);
INSERT INTO academics.program (school_id, program_id, department_id, program_code, name, program_kind, level, duration_terms) VALUES
 (1, 1, NULL, 'G5', 'Grade 5', 'GRADE', 'PRIMARY', 2), (1, 2, NULL, 'G6', 'Grade 6', 'GRADE', 'SECONDARY', 2);
INSERT INTO inventory.location (school_id, location_id, room_name, building_floor, location_type) VALUES
 (1, 1, 'Room 101', 'Main / 1', 'CLASSROOM'), (1, 2, 'Room 102', 'Main / 1', 'CLASSROOM'),
 (1, 3, 'Exam Hall', 'Main / G', 'CLASSROOM'), (1, 4, 'Central Store', 'Annex / G', 'STORE'),
 (1, 5, 'Mess Store', 'Hostel / G', 'MESS_STORE'), (1, 6, 'Main Gate', 'Gate', 'GATE'),
 (1, 7, 'Locker Room', 'Hostel / G', 'LOCKER_ROOM'), (1, 8, 'Science Lab', 'Main / 2', 'LAB');
INSERT INTO academics.class_section (school_id, class_section_id, program_id, academic_year_id, term_id, section_kind, stage_number,
  section_name, capacity, teacher_user_id, room_location_id, day_start_time, day_end_time, late_after_time) VALUES
 (1, 1, 1, 1, 1, 'SECTION', 5, '5-A', 40, 4, 1, '08:45', '15:30', '09:00'),
 (1, 2, 2, 1, 1, 'SECTION', 6, '6-A', 40, 22, 2, '08:45', '15:30', '09:00');
INSERT INTO academics.subject (school_id, subject_id, department_id, subject_code, subject_name, subject_type, credits) VALUES
 (1, 1, 1, 'MAT', 'Mathematics', 'CORE', 4), (1, 2, 1, 'SCI', 'Science', 'CORE', 4), (1, 3, 2, 'ENG', 'English', 'CORE', 3);
INSERT INTO academics.staff_subject (school_id, staff_subject_id, user_id, subject_id) VALUES
 (1, 1, 4, 1), (1, 2, 4, 2), (1, 3, 22, 3), (1, 4, 22, 1);
INSERT INTO academics.period (school_id, period_id, period_time) VALUES
 (1, 1, '09:00-09:45'), (1, 2, '09:50-10:35'), (1, 3, '10:45-11:30'), (1, 4, '11:35-12:20');
INSERT INTO academics.class_section_period (school_id, class_section_period_id, class_section_id, period_id)
 SELECT 1, (cs - 1) * 4 + p, cs, p FROM generate_series(1, 2) cs, generate_series(1, 4) p;
INSERT INTO academics.timetable_version (school_id, timetable_version_id, academic_year_id, term_id, status, generated_at, published_by_user_id)
 VALUES (1, 1, 1, 1, 'PUBLISHED', now() - interval '60 days', 3);
-- 5-A: P1 Maths (Ravi), P2 Science (Ravi), P3 English (Meena), P4 Maths/Science alternating; 6-A: P1 English, P2 Maths (Meena), P3 Science (Ravi), P4 English
INSERT INTO academics.timetable (school_id, timetable_id, class_section_period_id, staff_subject_id, day_of_week, timetable_version_id, room_location_id)
 SELECT 1, row_number() OVER (), csp, ss, d, 1, CASE WHEN csp <= 4 THEN 1 ELSE 2 END
 FROM (VALUES ('MON'), ('TUE'), ('WED'), ('THU'), ('FRI'), ('SAT')) AS days(d),
      LATERAL (VALUES (1, 1), (2, 2), (3, 3), (4, CASE WHEN d IN ('MON', 'WED', 'FRI') THEN 1 ELSE 2 END),
                      (5, 3), (6, 4), (7, 2), (8, 3)) AS slots(csp, ss);
INSERT INTO academics.student (school_id, student_id, student_admission_number, student_admission_date, first_name, last_name,
  student_user_id, class_section_id, date_of_birth, gender, residency_type, photo_url, status) VALUES
 (1, 1, 'ADM-1001', current_date - 800, 'Arjun', 'Devi', 23, 1, '2016-04-12', 'M', 'DAY_SCHOLAR', NULL, 'ACTIVE'),
 (1, 2, 'ADM-1002', current_date - 800, 'Diya', 'Devi', NULL, 2, '2015-02-03', 'F', 'HOSTELLER', NULL, 'ACTIVE'),
 (1, 3, 'ADM-1003', current_date - 700, 'Kabir', 'Ali', NULL, 1, '2016-07-21', 'M', 'HOSTELLER', NULL, 'ACTIVE'),
 (1, 4, 'ADM-1004', current_date - 700, 'Meera', 'Nair', NULL, 1, '2016-01-30', 'F', 'DAY_SCHOLAR', NULL, 'ACTIVE'),
 (1, 5, 'ADM-1005', current_date - 600, 'Rohan', 'Shah', NULL, 1, '2016-09-02', 'M', 'HOSTELLER', NULL, 'ACTIVE'),
 (1, 6, 'ADM-1006', current_date - 600, 'Sara', 'Khan', NULL, 1, '2016-11-15', 'F', 'DAY_SCHOLAR', NULL, 'ACTIVE'),
 (1, 7, 'ADM-1007', current_date - 500, 'Vihaan', 'Reddy', NULL, 2, '2015-05-19', 'M', 'HOSTELLER', NULL, 'ACTIVE'),
 (1, 8, 'ADM-1008', current_date - 500, 'Isha', 'Gupta', NULL, 2, '2015-08-08', 'F', 'DAY_SCHOLAR', NULL, 'ACTIVE'),
 (1, 9, 'ADM-1009', current_date - 400, 'Aditya', 'Rao', NULL, 2, '2015-12-01', 'M', 'DAY_SCHOLAR', NULL, 'ACTIVE'),
 (1, 10, 'ADM-1010', current_date - 400, 'Zoya', 'Ali', NULL, 2, '2015-03-27', 'F', 'HOSTELLER', NULL, 'ACTIVE');
INSERT INTO academics.student_parent (school_id, student_id, user_id, relationship_type, is_primary_contact) VALUES
 (1, 1, 6, 'MOTHER', true), (1, 2, 6, 'MOTHER', true), (1, 3, 24, 'FATHER', true), (1, 10, 24, 'FATHER', true);
INSERT INTO academics.student_enrollment (school_id, enrollment_id, student_id, program_id, class_section_id, academic_year_id, term_id, status, enrolled_on)
 SELECT 1, student_id, student_id, CASE WHEN class_section_id = 1 THEN 1 ELSE 2 END, class_section_id, 1, 1, 'ACTIVE', current_date - 120
 FROM academics.student;

-- attendance: last 10 school days daily presence; today 5-A taken (Meera absent, Rohan late), 6-A not yet
INSERT INTO operations.daily_presence (school_id, person_kind, person_id, presence_date, first_in_at, late_minutes, status, computed_by)
 SELECT 1, 'STUDENT', s.student_id, d::date, d::date + time '08:50' + (CASE WHEN (s.student_id + extract(day FROM d)::int) % 9 = 0 THEN interval '20 min' ELSE interval '0' END),
        CASE WHEN (s.student_id + extract(day FROM d)::int) % 9 = 0 THEN 20 ELSE 0 END,
        CASE WHEN (s.student_id * 3 + extract(day FROM d)::int) % 11 = 0 THEN 'ABSENT'
             WHEN (s.student_id + extract(day FROM d)::int) % 9 = 0 THEN 'LATE' ELSE 'PRESENT' END, 'MANUAL'
 FROM academics.student s, generate_series(current_date - 14, current_date - 1, interval '1 day') d
 WHERE extract(isodow FROM d) < 7;
INSERT INTO operations.daily_presence (school_id, person_kind, person_id, presence_date, first_in_at, late_minutes, status, computed_by)
 SELECT 1, 'STUDENT', student_id, current_date, CASE WHEN student_id = 4 THEN NULL ELSE current_date + time '08:52' + CASE WHEN student_id = 5 THEN interval '25 min' ELSE interval '0' END END,
        CASE WHEN student_id = 5 THEN 25 ELSE 0 END,
        CASE WHEN student_id = 4 THEN 'ABSENT' WHEN student_id = 5 THEN 'LATE' ELSE 'PRESENT' END, 'MANUAL'
 FROM academics.student WHERE class_section_id = 1;
INSERT INTO operations.student_absence (school_id, student_id, class_section_period_id, date, reported_by_user_id, absence_reason) VALUES
 (1, 4, NULL, current_date, 4, 'UNEXCUSED'), (1, 6, 3, current_date - 1, 22, 'MEDICAL');

-- homework
INSERT INTO operations.homework (school_id, homework_id, class_section_id, staff_subject_id, assigned_date, due_date, title, description, submission_mode, max_marks) VALUES
 (1, 1, 1, 1, current_date - 2, current_date + 1, 'Fractions worksheet', 'Exercise 4.2, questions 1-10', 'ONLINE', 10),
 (1, 2, 1, 2, current_date - 1, current_date + 3, 'Plant cell diagram', 'Draw and label a plant cell', 'OFFLINE', 5),
 (1, 3, 2, 3, current_date, current_date + 2, 'Essay: My favourite festival', '200 words', 'ONLINE', 10);
INSERT INTO operations.homework_submission (school_id, submission_id, homework_id, student_id, submitted_at, text_answer, status, marks, feedback, graded_by_user_id) VALUES
 (1, 1, 1, 1, now() - interval '3 hours', 'Answers attached', 'GRADED', 9, 'Well done', 4),
 (1, 2, 1, 3, now() - interval '1 hour', 'Done', 'SUBMITTED', NULL, NULL, NULL);

-- exams and marks
INSERT INTO assessment.grade_scale (school_id, grade_scale_id, name, scale_type) VALUES (1, 1, 'Primary bands', 'PERCENT_BAND');
INSERT INTO assessment.grade (school_id, grade_id, grade_scale_id, min_score, max_score, grade_point, grade_name) VALUES
 (1, 1, 1, 90, 100, 10, 'A1'), (1, 2, 1, 75, 89.99, 8, 'A2'), (1, 3, 1, 60, 74.99, 6, 'B1'), (1, 4, 1, 33, 59.99, 4, 'C'), (1, 5, 1, 0, 32.99, 0, 'E');
INSERT INTO assessment.exam_session (school_id, exam_session_id, term_id, name, start_date, end_date, block_on_dues, status) VALUES
 (1, 1, 1, 'Term 1 exams', current_date + 5, current_date + 12, true, 'PUBLISHED');
INSERT INTO assessment.exams (school_id, exam_id, staff_subject_id, class_section_id, term_id, scheduled_by_user_id, invigilated_by_user_id, exam_name, exam_type,
  max_marks, weightage_pct, exam_date, exam_session_id, room_location_id, start_time, duration_minutes, status) VALUES
 (1, 1, 1, 1, 1, 3, 22, 'Unit Test 1 - Maths', 'UNIT_TEST', 25, 10, current_date - 20, NULL, 1, '09:00', 45, 'PUBLISHED'),
 (1, 2, 2, 1, 1, 3, 22, 'Unit Test 1 - Science', 'UNIT_TEST', 25, 10, current_date - 3, NULL, 1, '09:00', 45, 'MARKS_ENTRY'),
 (1, 3, 3, 2, 1, 3, 4, 'Unit Test 1 - English', 'UNIT_TEST', 25, 10, current_date - 18, NULL, 2, '09:00', 45, 'PUBLISHED'),
 (1, 4, 1, 1, 1, 3, 4, 'Term 1 - Maths', 'END_TERM', 80, 40, current_date + 5, 1, 3, '09:30', 120, 'SCHEDULED');
INSERT INTO assessment.marks (school_id, exam_id, student_id, mark_obtained, grade_id, is_absent, entered_by_user_id, entered_at)
 SELECT 1, e.exam_id, s.student_id, CASE WHEN s.student_id = 6 AND e.exam_id = 1 THEN NULL ELSE 12 + (s.student_id * 7 + e.exam_id * 3) % 13 END, NULL,
        s.student_id = 6 AND e.exam_id = 1, 4, now() - interval '10 days'
 FROM assessment.exams e JOIN academics.student s ON s.class_section_id = e.class_section_id WHERE e.exam_id IN (1, 3);
INSERT INTO assessment.marks (school_id, exam_id, student_id, mark_obtained, is_absent, entered_by_user_id, entered_at)
 SELECT 1, 2, student_id, 15 + student_id % 9, false, 4, now() - interval '1 day' FROM academics.student WHERE class_section_id = 1 AND student_id <= 4;
INSERT INTO assessment.seating (school_id, exam_id, student_id, room_location_id, seat_label)
 SELECT 1, 4, student_id, 3, 'S' || student_id FROM academics.student WHERE class_section_id = 1;
INSERT INTO assessment.invigilation_duty (school_id, exam_id, room_location_id, user_id, duty_role) VALUES (1, 4, 3, 22, 'INVIGILATOR'), (1, 4, 3, 4, 'CHIEF');
INSERT INTO assessment.report_card (school_id, report_card_id, student_id, term_id, attendance_pct, teacher_remark, status, published_at) VALUES
 (1, 1, 1, 1, 94.5, 'Attentive and curious', 'PUBLISHED', now() - interval '5 days'),
 (1, 2, 2, 1, 91.0, NULL, 'WITHHELD', NULL);
INSERT INTO assessment.student_behavior_log (school_id, student_id, logged_by_user_id, log_date, category, note, severity) VALUES
 (1, 5, 4, current_date - 2, 'CONDUCT', 'Disturbing class', 'LOW');

-- syllabus, lesson plans
INSERT INTO learning.syllabus (school_id, syllabus_id, program_id, subject_id, academic_year_id, board) VALUES (1, 1, 1, 1, 1, 'CBSE'), (1, 2, 1, 2, 1, 'CBSE');
INSERT INTO learning.syllabus_unit (school_id, unit_id, syllabus_id, parent_unit_id, title, sequence, planned_periods, term_id) VALUES
 (1, 1, 1, NULL, 'Numbers', 1, 12, 1), (1, 2, 1, NULL, 'Fractions', 2, 10, 1), (1, 3, 1, 2, 'Adding fractions', 1, 4, 1),
 (1, 4, 2, NULL, 'Living things', 1, 8, 1);
INSERT INTO learning.lesson_plan (school_id, plan_id, staff_subject_id, class_section_id, unit_id, planned_date, objectives, status, delivered_on) VALUES
 (1, 1, 1, 1, 1, current_date - 30, 'Place value', 'DELIVERED', current_date - 30),
 (1, 2, 1, 1, 2, current_date - 5, 'Intro to fractions', 'DELIVERED', current_date - 5),
 (1, 3, 1, 1, 3, current_date, 'Adding like fractions', 'PLANNED', NULL),
 (1, 4, 2, 1, 4, current_date - 3, 'Plant and animal cells', 'DELIVERED', current_date - 3);

-- ---------------------------------------------------------------- staff
INSERT INTO hr.employee_profile (school_id, user_id, employee_code, staff_category, department_id, designation, employment_type, reporting_manager_user_id, date_of_joining, status)
 SELECT 1, u, 'EMP-' || u, c, d, des, 'PERMANENT', CASE WHEN u = 3 THEN NULL ELSE 3 END, current_date - 900 + u * 10, 'ACTIVE'
 FROM (VALUES (3, 'TEACHING', 3, 'Principal'), (4, 'TEACHING', 1, 'TGT Maths'), (5, 'NON_TEACHING', 1, 'Lab assistant'),
              (7, 'NON_TEACHING', 3, 'Office admin'), (8, 'NON_TEACHING', 3, 'Accountant'), (9, 'NON_TEACHING', 3, 'HR manager'),
              (10, 'NON_TEACHING', 3, 'Admission officer'), (11, 'NON_TEACHING', 3, 'Receptionist'), (12, 'HOSTEL', NULL, 'Chief warden'),
              (13, 'HOSTEL', NULL, 'Warden'), (14, 'HOSTEL', NULL, 'Matron'), (15, 'NON_TEACHING', NULL, 'Nurse'),
              (16, 'HOSTEL', NULL, 'Mess manager'), (17, 'SECURITY', NULL, 'Guard'), (18, 'SECURITY', NULL, 'Security supervisor'),
              (19, 'NON_TEACHING', 3, 'Store keeper'), (20, 'TRANSPORT', NULL, 'Transport manager'), (21, 'TRANSPORT', NULL, 'Driver'),
              (22, 'TEACHING', 2, 'TGT English')) AS e(u, c, d, des);
INSERT INTO hr.teacher_metadata (school_id, user_id, teacher_enrollment_number, department_id, designation, teacher_joined_date, qualification) VALUES
 (1, 4, 'T-104', 1, 'TGT Maths', current_date - 860, 'M.Sc, B.Ed'), (1, 22, 'T-122', 2, 'TGT English', current_date - 680, 'M.A, B.Ed');
INSERT INTO hr.shift (school_id, shift_id, code, name, start_time, end_time, crosses_midnight, grace_minutes, applies_to) VALUES
 (1, 1, 'GEN', 'General', '08:30', '16:30', false, 10, 'ANY'), (1, 2, 'SEC-D', 'Security day', '06:00', '18:00', false, 5, 'SECURITY'),
 (1, 3, 'SEC-N', 'Security night', '18:00', '06:00', true, 5, 'SECURITY'), (1, 4, 'HOS-N', 'Hostel night', '20:00', '07:00', true, 10, 'HOSTEL');
INSERT INTO hr.shift_assignment (school_id, user_id, shift_id, weekdays, weekly_off, from_date, rotation)
 SELECT 1, user_id, CASE WHEN user_id IN (17, 18) THEN 2 WHEN user_id = 13 THEN 4 ELSE 1 END, 'MON,TUE,WED,THU,FRI,SAT', 'SUN', current_date - 120, 'FIXED'
 FROM hr.employee_profile;
INSERT INTO hr.post (school_id, post_id, code, post_type, location_id, required_per_shift) VALUES
 (1, 1, 'GATE-1', 'GATE', 6, 1), (1, 2, 'PATROL-1', 'PATROL', NULL, 1), (1, 3, 'HOSTEL-N', 'HOSTEL_NIGHT', NULL, 1);
INSERT INTO hr.roster_entry (school_id, roster_entry_id, user_id, shift_id, post_id, duty_date, status, reported_at)
 SELECT 1, row_number() OVER (), u, s, p, d::date, CASE WHEN d::date = current_date THEN 'ON_DUTY' WHEN d::date < current_date THEN 'COMPLETED' ELSE 'PLANNED' END,
        CASE WHEN d::date <= current_date THEN d::date + time '05:55' END
 FROM generate_series(current_date - 3, current_date + 6, interval '1 day') d, (VALUES (17, 2, 1), (18, 2, 2), (13, 4, 3)) AS r(u, s, p);
INSERT INTO operations.daily_presence (school_id, person_kind, person_id, presence_date, shift_id, first_in_at, last_out_at, late_minutes, status, computed_by)
 SELECT 1, 'STAFF', user_id, current_date, 1, current_date + time '08:25' + CASE WHEN user_id = 5 THEN interval '35 min' ELSE interval '0' END,
        NULL, CASE WHEN user_id = 5 THEN 25 ELSE 0 END, CASE WHEN user_id = 5 THEN 'LATE' WHEN user_id = 22 THEN 'ON_LEAVE' ELSE 'PRESENT' END, 'SYSTEM'
 FROM hr.employee_profile WHERE user_id NOT IN (21);
INSERT INTO operations.attendance_punch (school_id, person_kind, person_id, source, direction, punched_at, post_id) VALUES
 (1, 'STAFF', 17, 'FINGERPRINT', 'IN', current_date + time '05:55', 1), (1, 'STAFF', 4, 'FACE', 'IN', current_date + time '08:25', NULL);
INSERT INTO hr.leave_type (school_id, leave_type_id, code, name, annual_quota, carry_forward_max, is_paid, applies_to) VALUES
 (1, 1, 'CL', 'Casual leave', 12, 0, true, 'ANY'), (1, 2, 'SL', 'Sick leave', 10, 5, true, 'ANY'), (1, 3, 'EL', 'Earned leave', 15, 30, true, 'ANY');
INSERT INTO hr.leave_balance (school_id, user_id, leave_type_id, academic_year_id, opening, accrued, used, balance)
 SELECT 1, e.user_id, t.leave_type_id, 1, 0, t.annual_quota, CASE WHEN e.user_id = 22 AND t.leave_type_id = 1 THEN 2 ELSE 0 END,
        t.annual_quota - CASE WHEN e.user_id = 22 AND t.leave_type_id = 1 THEN 2 ELSE 0 END
 FROM hr.employee_profile e, hr.leave_type t;
INSERT INTO hr.leave_request (school_id, leave_request_id, user_id, leave_type_id, from_date, to_date, days, reason, status, approver_user_id, decided_at) VALUES
 (1, 1, 22, 1, current_date, current_date + 1, 2, 'Family function', 'APPROVED', 3, now() - interval '2 days'),
 (1, 2, 4, 2, current_date + 4, current_date + 4, 1, 'Medical appointment', 'PENDING', NULL, NULL),
 (1, 3, 5, 1, current_date + 7, current_date + 8, 2, 'Travel', 'PENDING', NULL, NULL);
INSERT INTO operations.staff_absences (school_id, staff_absence_id, user_id, date, status, leave_request_id, reason, absence_kind) VALUES
 (1, 1, 22, current_date, 'APPROVED', 1, 'Family function', 'LEAVE');
INSERT INTO operations.substitution (school_id, staff_absence_id, substitute_user_id, class_section_period_id) VALUES (1, 1, 4, 5);
INSERT INTO hr.salary_component (school_id, component_id, code, kind, calc) VALUES (1, 1, 'BASIC', 'EARNING', 'FIXED'), (1, 2, 'HRA', 'EARNING', 'PERCENT_OF_BASIC'), (1, 3, 'PF', 'DEDUCTION', 'PERCENT_OF_BASIC');
INSERT INTO hr.payroll_run (school_id, run_id, period, status, computed_by_user_id, approved_by_user_id, paid_at) VALUES
 (1, 1, to_char(current_date - interval '1 month', 'YYYY-MM'), 'PAID', 9, 3, now() - interval '20 days'),
 (1, 2, to_char(current_date, 'YYYY-MM'), 'COMPUTED', 9, NULL, NULL);
INSERT INTO hr.payslip (school_id, run_id, user_id, working_days, present_days, lop_days, gross, deductions, net)
 SELECT 1, r.run_id, e.user_id, 26, 26 - (e.user_id % 3), e.user_id % 3 * CASE WHEN r.run_id = 2 THEN 1 ELSE 0 END, 40000 + e.user_id * 500, 4800, 35200 + e.user_id * 500
 FROM hr.payroll_run r, hr.employee_profile e;

-- ---------------------------------------------------------------- finance
INSERT INTO finance.fee_head (school_id, fee_head_id, code, name, is_refundable) VALUES
 (1, 1, 'TUI', 'Tuition', false), (1, 2, 'HOS', 'Hostel', false), (1, 3, 'BUS', 'Transport', false), (1, 4, 'DEP', 'Caution deposit', true);
INSERT INTO finance.fee_structure (school_id, fee_structure_id, program_id, academic_year_id, term_id, fee_type, billing_frequency, amount, fee_head_id) VALUES
 (1, 1, 1, 1, NULL, 'TUITION', 'TERM', 30000, 1), (1, 2, 2, 1, NULL, 'TUITION', 'TERM', 32000, 1), (1, 3, NULL, 1, NULL, 'HOSTEL', 'TERM', 45000, 2);
INSERT INTO finance.fee (school_id, fee_id, student_id, fee_structure_id, due_date, remaining_due, fee_head_id, gross_amount, concession_amount, fine_amount, net_amount, paid_amount, status, source_kind)
 SELECT 1, row_number() OVER (ORDER BY s.student_id, k), s.student_id, CASE WHEN k = 1 THEN s.class_section_id ELSE 3 END,
        CASE WHEN k = 1 THEN current_date - 40 ELSE current_date + 15 END,
        CASE WHEN k = 1 AND s.student_id IN (2, 5, 7) THEN 30000 WHEN k = 1 AND s.student_id = 3 THEN 10000 WHEN k = 1 THEN 0 ELSE 45000 END,
        CASE WHEN k = 1 THEN 1 ELSE 2 END, CASE WHEN k = 1 THEN 30000 ELSE 45000 END, 0, 0, CASE WHEN k = 1 THEN 30000 ELSE 45000 END,
        CASE WHEN k = 1 AND s.student_id IN (2, 5, 7) THEN 0 WHEN k = 1 AND s.student_id = 3 THEN 20000 WHEN k = 1 THEN 30000 ELSE 0 END,
        CASE WHEN k = 1 AND s.student_id IN (2, 5, 7) THEN 'DUE' WHEN k = 1 AND s.student_id = 3 THEN 'PART_PAID' WHEN k = 1 THEN 'PAID' ELSE 'DUE' END, 'STRUCTURE'
 FROM academics.student s, generate_series(1, 2) k WHERE k = 1 OR s.residency_type = 'HOSTELLER';
INSERT INTO finance.payment (school_id, payment_id, student_id, paid_by_user_id, amount, mode, gateway, receipt_number, status, received_by_user_id, paid_at)
 SELECT 1, row_number() OVER (ORDER BY f.fee_id), f.student_id, CASE WHEN f.student_id IN (1, 2) THEN 6 WHEN f.student_id IN (3, 10) THEN 24 END, f.paid_amount,
        CASE WHEN f.student_id % 2 = 0 THEN 'UPI' ELSE 'CASH' END, CASE WHEN f.student_id % 2 = 0 THEN 'RAZORPAY' ELSE 'NONE' END,
        'RCT/26-27/' || lpad((row_number() OVER (ORDER BY f.fee_id))::text, 5, '0'), 'SUCCESS', 8,
        CASE WHEN f.student_id = 4 THEN now() - interval '2 hours' ELSE now() - (f.fee_id || ' days')::interval END
 FROM finance.fee f WHERE f.paid_amount > 0;
INSERT INTO finance.payment_allocation (school_id, payment_id, fee_id, amount)
 SELECT 1, p.payment_id, f.fee_id, p.amount FROM finance.payment p JOIN finance.fee f ON f.student_id = p.student_id AND f.paid_amount > 0;
INSERT INTO finance.student_wallet (school_id, wallet_id, student_id, balance, monthly_limit, is_frozen) VALUES
 (1, 1, 2, 750, 2000, false), (1, 2, 3, 120, 1500, false), (1, 3, 5, 0, 1500, false), (1, 4, 7, 300, 1500, false), (1, 5, 10, 900, 2000, false);
INSERT INTO finance.wallet_txn (school_id, wallet_id, txn_type, amount, performed_by_user_id, txn_at, note) VALUES
 (1, 1, 'TOP_UP', 1000, 6, now() - interval '9 days', 'Monthly top-up'), (1, 1, 'STORE_PURCHASE', -250, 13, now() - interval '3 days', 'Stationery');
INSERT INTO accounts.expense_head (school_id, expense_head_id, code, name) VALUES (1, 1, 'MAINT', 'Maintenance'), (1, 2, 'PROV', 'Mess provisions'), (1, 3, 'FUEL', 'Fuel');
INSERT INTO accounts.budget (school_id, budget_id, academic_year_id, expense_head_id, cost_centre, amount, alert_at_pct) VALUES
 (1, 1, 1, 1, 'SCHOOL', 500000, 80), (1, 2, 1, 2, 'MESS', 1200000, 80), (1, 3, 1, 3, 'TRANSPORT', 300000, 80);
INSERT INTO accounts.expense (school_id, expense_id, voucher_number, expense_head_id, cost_centre, expense_date, amount, payment_mode, paid_from, description, status, submitted_by_user_id) VALUES
 (1, 1, 'EXP-0001', 1, 'SCHOOL', current_date - 30, 120000, 'BANK_TRANSFER', 'BANK', 'Painting', 'PAID', 7),
 (1, 2, 'EXP-0002', 2, 'MESS', current_date - 10, 980000, 'BANK_TRANSFER', 'BANK', 'Provisions Q1', 'PAID', 16),
 (1, 3, 'EXP-0003', 3, 'TRANSPORT', current_date - 2, 18000, 'UPI', 'BANK', 'Diesel', 'SUBMITTED', 20);
INSERT INTO accounts.petty_cash_account (school_id, petty_cash_id, name, custodian_user_id, cost_centre, float_limit, balance) VALUES (1, 1, 'Office petty cash', 8, 'SCHOOL', 20000, 8400);

-- ---------------------------------------------------------------- hostel
INSERT INTO hostel.hostel (school_id, hostel_id, code, name, gender, hostel_type, capacity, curfew_weekday, curfew_weekend, status) VALUES
 (1, 1, 'BH', 'Boys Hostel', 'BOYS', 'SCHOOL_BOARDING', 40, '19:00', '20:00', 'ACTIVE'),
 (1, 2, 'GH', 'Girls Hostel', 'GIRLS', 'SCHOOL_BOARDING', 40, '19:00', '20:00', 'ACTIVE');
INSERT INTO hostel.block (school_id, block_id, hostel_id, name, floor_count) VALUES (1, 1, 1, 'A Block', 2), (1, 2, 2, 'Rose Block', 2);
INSERT INTO hostel.room (school_id, room_id, hostel_id, block_id, floor_number, room_number, room_type, capacity, is_ac, status) VALUES
 (1, 1, 1, 1, 1, 'A101', 'DOUBLE', 2, false, 'FULL'), (1, 2, 1, 1, 1, 'A102', 'TRIPLE', 3, false, 'AVAILABLE'),
 (1, 3, 2, 2, 1, 'R101', 'DOUBLE', 2, true, 'FULL'), (1, 4, 2, 2, 2, 'R201', 'DOUBLE', 2, true, 'AVAILABLE');
INSERT INTO hostel.bed (school_id, bed_id, room_id, bed_label, status) VALUES
 (1, 1, 1, 'A101-1', 'OCCUPIED'), (1, 2, 1, 'A101-2', 'OCCUPIED'), (1, 3, 2, 'A102-1', 'OCCUPIED'), (1, 4, 2, 'A102-2', 'VACANT'), (1, 5, 2, 'A102-3', 'BLOCKED'),
 (1, 6, 3, 'R101-1', 'OCCUPIED'), (1, 7, 3, 'R101-2', 'OCCUPIED'), (1, 8, 4, 'R201-1', 'VACANT'), (1, 9, 4, 'R201-2', 'VACANT');
INSERT INTO hostel.allocation (school_id, allocation_id, student_id, bed_id, room_id, hostel_id, academic_year_id, check_in_date, status, allocated_by_user_id) VALUES
 (1, 1, 3, 1, 1, 1, 1, current_date - 110, 'ACTIVE', 12), (1, 2, 5, 2, 1, 1, 1, current_date - 110, 'ACTIVE', 12),
 (1, 3, 7, 3, 2, 1, 1, current_date - 100, 'ACTIVE', 12), (1, 4, 2, 6, 3, 2, 1, current_date - 110, 'ACTIVE', 12),
 (1, 5, 10, 7, 3, 2, 1, current_date - 90, 'ACTIVE', 12);
INSERT INTO hostel.allocation_request (school_id, request_id, student_id, academic_year_id, kind, preferred_hostel_id, preferred_room_type, reason, status, requested_by_user_id) VALUES
 (1, 1, 9, 1, 'NEW', 1, 'DOUBLE', 'Parents relocating', 'WAITLISTED', 10);
INSERT INTO hostel.staff_assignment (school_id, assignment_id, hostel_id, user_id, duty, scope_type, block_id, is_resident, from_date, assigned_by_user_id) VALUES
 (1, 1, 1, 12, 'CHIEF_WARDEN', 'HOSTEL', NULL, true, current_date - 200, 3), (1, 2, 2, 12, 'CHIEF_WARDEN', 'HOSTEL', NULL, true, current_date - 200, 3),
 (1, 3, 1, 13, 'BLOCK_WARDEN', 'BLOCK', 1, true, current_date - 200, 12), (1, 4, 2, 14, 'MATRON', 'HOSTEL', NULL, true, current_date - 200, 12),
 (1, 5, 1, 14, 'MATRON', 'HOSTEL', NULL, false, current_date - 200, 12), (1, 6, 1, 16, 'MESS_INCHARGE', 'HOSTEL', NULL, false, current_date - 200, 12);
INSERT INTO hostel.outing_policy (school_id, policy_id, hostel_id, outing_type, allowed_days, max_per_month, max_hours, requires_parent_approval, requires_pickup_person, approver_duty, allow_phone_release, phone_release_at, grace_minutes) VALUES
 (1, 1, 1, 'LOCAL_OUTING', 'SAT,SUN', 4, 4, true, false, 'BLOCK_WARDEN', false, NULL, 15),
 (1, 2, 1, 'WEEKEND_HOME', 'FRI,SAT', 2, 60, true, true, 'CHIEF_WARDEN', true, 'GATE_EXIT', 30),
 (1, 3, 2, 'WEEKEND_HOME', 'FRI,SAT', 2, 60, true, true, 'CHIEF_WARDEN', true, 'GATE_EXIT', 30);
INSERT INTO frontoffice.pickup_person (school_id, pickup_person_id, student_id, name, relationship, phone, id_proof_last4, added_by_user_id, requires_parent_otp, is_active) VALUES
 (1, 1, 2, 'Sunil Devi', 'UNCLE', '+919800000001', '4321', 6, true, true), (1, 2, 3, 'Farhan Ali', 'FATHER', '+919100000024', '1111', 24, false, true);
INSERT INTO hostel.outing_group (school_id, group_id, hostel_id, group_kind, title, travel_mode, station_or_stop, campus_departure_at, carrier_departure_at, phone_release_at, escort_user_id, status) VALUES
 (1, 1, 1, 'STATION_DROP', 'Friday station drop', 'BUS', 'MGBS', date_trunc('day', now()) + interval '2 days 15 hours', date_trunc('day', now()) + interval '2 days 17 hours', date_trunc('day', now()) + interval '2 days 15 hours', 4, 'PLANNED');
INSERT INTO hostel.outing_request (school_id, outing_id, student_id, hostel_id, policy_id, group_id, outing_type, purpose, destination, depart_planned_at, return_planned_at, travel_mode,
  pickup_person_id, requested_by_kind, requested_by_user_id, parent_status, parent_user_id, parent_decided_at, warden_status, warden_user_id, warden_decided_at, gate_pass_token, status, late_minutes) VALUES
 (1, 1, 3, 1, 1, NULL, 'LOCAL_OUTING', 'Haircut', 'KPHB market', now() - interval '5 hours', now() - interval '1 hour', 'SELF', NULL, 'STUDENT', NULL, 'APPROVED', 24, now() - interval '1 day', 'APPROVED', 13, now() - interval '20 hours', 'GP-0001', 'OVERDUE', 60),
 (1, 2, 2, 2, 3, NULL, 'WEEKEND_HOME', 'Weekend at home', 'Home', now() + interval '2 days', now() + interval '4 days', 'AUTHORISED_PICKUP', 1, 'PARENT', 6, 'APPROVED', 6, now() - interval '3 hours', 'PENDING', NULL, NULL, NULL, 'REQUESTED', NULL),
 (1, 3, 7, 1, 2, 1, 'WEEKEND_HOME', 'Going home', 'Vijayawada', date_trunc('day', now()) + interval '2 days 15 hours', date_trunc('day', now()) + interval '4 days 18 hours', 'BUS', NULL, 'WARDEN', 13, 'PENDING', NULL, NULL, 'APPROVED', 13, now() - interval '2 hours', NULL, 'REQUESTED', NULL),
 (1, 4, 5, 1, 1, NULL, 'LOCAL_OUTING', 'Stationery', 'Market', now() - interval '8 days', now() - interval '8 days' + interval '3 hours', 'SELF', NULL, 'STUDENT', NULL, 'APPROVED', NULL, now() - interval '9 days', 'APPROVED', 13, now() - interval '9 days', 'GP-0002', 'CLOSED', 0);
INSERT INTO hostel.outing_movement (school_id, outing_id, direction, moved_at, gate_user_id, verification) VALUES
 (1, 1, 'OUT', now() - interval '5 hours', 17, 'QR'), (1, 4, 'OUT', now() - interval '8 days', 17, 'QR'), (1, 4, 'IN', now() - interval '8 days' + interval '2 hours 50 min', 17, 'QR');
INSERT INTO hostel.roll_call (school_id, roll_call_id, hostel_id, assignment_id, session, roll_date, conducted_by_user_id, started_at, submitted_at, status) VALUES
 (1, 1, 1, 3, 'MORNING', current_date, 13, current_date + time '06:30', current_date + time '06:45', 'SUBMITTED'),
 (1, 2, 1, 3, 'NIGHT', current_date, 13, NULL, NULL, 'OPEN');
INSERT INTO hostel.roll_call_entry (school_id, roll_call_id, student_id, status, outing_id, custody_pending) VALUES
 (1, 1, 3, 'PRESENT', NULL, false), (1, 1, 5, 'PRESENT', NULL, false), (1, 1, 7, 'PRESENT', NULL, false),
 (1, 2, 3, 'ON_OUTING', 1, true), (1, 2, 5, 'PRESENT', NULL, false), (1, 2, 7, 'PRESENT', NULL, false);
INSERT INTO hostel.room_inspection (school_id, room_id, kind, inspected_by_user_id, inspected_at, hygiene_score, findings) VALUES
 (1, 1, 'ROUTINE_HYGIENE', 13, now() - interval '3 days', 4, 'Clean'), (1, 2, 'ROUTINE_HYGIENE', 13, now() - interval '3 days', 3, 'Shoes on the floor');
INSERT INTO hostel.laundry_batch (school_id, hostel_id, student_id, given_at, item_count, handled_by_user_id) VALUES (1, 1, 3, now() - interval '1 day', 8, 14);
INSERT INTO custody.storage_unit (school_id, unit_id, location_id, hostel_id, code, unit_type, capacity, status) VALUES (1, 1, 7, 1, 'TRAY-A', 'TRAY', 30, 'ACTIVE'), (1, 2, 7, 2, 'TRAY-R', 'TRAY', 30, 'ACTIVE');
INSERT INTO custody.item (school_id, item_id, student_id, item_type, brand, model, serial_last4, colour, tag_code, storage_unit_id, status, due_back_at, registered_by_user_id, registered_at) VALUES
 (1, 1, 3, 'MOBILE_PHONE', 'Samsung', 'M14', '7781', 'Blue', 'CT-0001', 1, 'RELEASED_TEMP', now() - interval '1 hour', 13, now() - interval '100 days'),
 (1, 2, 5, 'MOBILE_PHONE', 'Redmi', 'Note 12', '2210', 'Black', 'CT-0002', 1, 'IN_CUSTODY', NULL, 13, now() - interval '100 days'),
 (1, 3, 2, 'MOBILE_PHONE', 'Apple', 'iPhone 12', '0099', 'White', 'CT-0003', 2, 'IN_CUSTODY', NULL, 14, now() - interval '100 days'),
 (1, 4, 7, 'LAPTOP', 'Lenovo', 'IdeaPad', '5512', 'Grey', 'CT-0004', 1, 'IN_CUSTODY', NULL, 13, now() - interval '60 days');
INSERT INTO custody.release_window (school_id, window_id, hostel_id, name, day_of_week, start_time, end_time, item_types, is_active) VALUES
 (1, 1, 1, 'Sunday call hour', 'SUN', '17:00', '18:00', 'MOBILE_PHONE', true), (1, 2, 2, 'Sunday call hour', 'SUN', '17:00', '18:00', 'MOBILE_PHONE', true);
INSERT INTO custody.event (school_id, item_id, event_type, release_reason, outing_id, performed_by_user_id, counterparty_kind, verification, due_back_at, occurred_at) VALUES
 (1, 1, 'DEPOSIT', NULL, NULL, 13, 'STUDENT', 'QR', NULL, now() - interval '100 days'),
 (1, 1, 'RELEASE', 'OUTING', 1, 13, 'STUDENT', 'QR', now() - interval '1 hour', now() - interval '5 hours');
INSERT INTO hostel.mess (school_id, mess_id, hostel_id, name, store_location_id, capacity) VALUES (1, 1, 1, 'Central Mess', 5, 120);
INSERT INTO hostel.mess_plan (school_id, plan_id, mess_id, name, meals_included, rebate_after_days, rebate_per_day) VALUES (1, 1, 1, 'VEG', 'BREAKFAST,LUNCH,SNACKS,DINNER', 3, 150);
INSERT INTO hostel.mess_subscription (school_id, subscription_id, plan_id, student_id, from_date, status)
 SELECT 1, row_number() OVER (), 1, student_id, current_date - 110, 'ACTIVE' FROM hostel.allocation WHERE status = 'ACTIVE';
INSERT INTO hostel.mess_menu (school_id, mess_id, day_of_week, meal, items, is_special)
 SELECT 1, 1, d, m, CASE m WHEN 'BREAKFAST' THEN 'Idli, sambar, chutney' WHEN 'LUNCH' THEN 'Rice, dal, sabzi, curd' WHEN 'SNACKS' THEN 'Tea, biscuits' ELSE 'Chapati, paneer curry, rice' END, d = 'SUN' AND m = 'LUNCH'
 FROM unnest(ARRAY['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN']) d, unnest(ARRAY['BREAKFAST', 'LUNCH', 'SNACKS', 'DINNER']) m;
INSERT INTO hostel.meal_attendance (school_id, mess_id, subscription_id, meal_date, meal, status, source)
 SELECT 1, 1, subscription_id, current_date, 'BREAKFAST', 'TAKEN', 'SCAN' FROM hostel.mess_subscription WHERE subscription_id <> 1;
INSERT INTO hostel.mess_feedback (school_id, mess_id, student_id, meal_date, meal, rating, comment) VALUES
 (1, 1, 3, current_date - 1, 'DINNER', 4, 'Paneer was good'), (1, 1, 5, current_date - 1, 'LUNCH', 2, 'Dal too salty'), (1, 1, 7, current_date, 'BREAKFAST', 5, NULL);

-- ---------------------------------------------------------------- wellbeing, discipline
INSERT INTO wellbeing.medical_profile (school_id, student_id, blood_group, allergies, conditions, regular_medicines, doctor_name, doctor_phone, updated_by_user_id, updated_at) VALUES
 (1, 3, 'B+', 'Peanuts', 'Asthma', 'Inhaler as needed', 'Dr. Rao', '+919811111111', 24, now() - interval '30 days'),
 (1, 2, 'O+', NULL, NULL, NULL, 'Dr. Mehta', '+919822222222', 6, now() - interval '60 days');
INSERT INTO wellbeing.vaccination (school_id, student_id, vaccine, dose, given_on) VALUES (1, 3, 'Typhoid', 1, current_date - 400), (1, 2, 'HPV', 1, current_date - 200);
INSERT INTO wellbeing.health_checkup (school_id, student_id, checkup_date, height_cm, weight_kg, vision, dental, conducted_by_user_id) VALUES
 (1, 3, current_date - 60, 138, 31, '6/6', 'OK', 15), (1, 2, current_date - 60, 146, 38, '6/9', 'Cavity', 15);
INSERT INTO wellbeing.infirmary_visit (school_id, person_kind, person_id, visited_at, complaint, vitals, treatment, attended_by_user_id, disposition, parent_notified_at, discharged_at) VALUES
 (1, 'STUDENT', 7, now() - interval '3 hours', 'Fever', '{"tempC": 38.6}', 'Paracetamol', 15, 'SICK_BAY', now() - interval '2 hours 50 min', NULL),
 (1, 'STUDENT', 1, now() - interval '6 days', 'Scraped knee', NULL, 'Dressing', 15, 'BACK_TO_CLASS', NULL, now() - interval '6 days');
INSERT INTO wellbeing.medication_schedule (school_id, schedule_id, student_id, medicine, dose, times, from_date, to_date) VALUES
 (1, 1, 7, 'Paracetamol 250mg', '1 tablet', '08:00,14:00,20:00', current_date, current_date + 2),
 (1, 2, 3, 'Salbutamol inhaler', '2 puffs', '21:00', current_date - 30, NULL);
INSERT INTO wellbeing.medication_dose (school_id, schedule_id, due_at, given_at, given_by_user_id, status) VALUES
 (1, 1, current_date + time '08:00', current_date + time '08:05', 14, 'GIVEN'),
 (1, 1, current_date + time '14:00', NULL, NULL, NULL), (1, 1, current_date + time '20:00', NULL, NULL, NULL),
 (1, 2, current_date + time '21:00', NULL, NULL, NULL);
INSERT INTO discipline.incident (school_id, incident_id, occurred_at, hostel_id, category, severity, description, reported_by_user_id, status) VALUES
 (1, 1, now() - interval '1 hour', 1, 'LATE_RETURN', 'MODERATE', 'Kabir not back from local outing', 13, 'REPORTED');
INSERT INTO discipline.incident_student (school_id, incident_id, student_id, involvement) VALUES (1, 1, 3, 'PRIMARY');

-- ---------------------------------------------------------------- transport
INSERT INTO transport.vehicle (school_id, vehicle_id, registration_number, vehicle_type, capacity, gps_device_id, insurance_valid_till, fitness_valid_till, permit_valid_till, puc_valid_till, status) VALUES
 (1, 1, 'TS09 UB 1234', 'BUS', 40, 'GPS-1', current_date + 20, current_date + 200, current_date + 300, current_date + 10, 'ACTIVE'),
 (1, 2, 'TS09 UB 5678', 'VAN', 14, 'GPS-2', current_date + 120, current_date - 5, current_date + 300, current_date + 90, 'ACTIVE');
INSERT INTO transport.route (school_id, route_id, code, name, shift, vehicle_id, driver_user_id, attendant_user_id) VALUES (1, 1, 'R1', 'KPHB - Miyapur', 'BOTH', 1, 21, NULL);
INSERT INTO transport.stop (school_id, stop_id, route_id, name, lat, lng, sequence, pickup_time, drop_time) VALUES
 (1, 1, 1, 'Miyapur X Roads', 17.4968, 78.3614, 1, '07:30', '16:10'), (1, 2, 1, 'Nizampet', 17.5149, 78.3854, 2, '07:45', '15:55'),
 (1, 3, 1, 'KPHB Phase 1', 17.4933, 78.3990, 3, '08:05', '15:40');
INSERT INTO transport.student_route (school_id, student_id, route_id, pickup_stop_id, drop_stop_id, from_date, status) VALUES
 (1, 1, 1, 2, 2, current_date - 120, 'ACTIVE'), (1, 4, 1, 1, 1, current_date - 120, 'ACTIVE'), (1, 6, 1, 3, 3, current_date - 120, 'ACTIVE');
INSERT INTO transport.trip (school_id, trip_id, route_id, vehicle_id, driver_user_id, trip_date, direction, started_at, ended_at, status) VALUES
 (1, 1, 1, 1, 21, current_date, 'PICKUP', current_date + time '07:20', current_date + time '08:20', 'COMPLETED'),
 (1, 2, 1, 1, 21, current_date, 'DROP', NULL, NULL, 'PLANNED');
INSERT INTO transport.trip_location (school_id, trip_id, recorded_at, lat, lng, speed_kmph) VALUES
 (1, 1, current_date + time '07:40', 17.5050, 78.3700, 32), (1, 1, current_date + time '08:15', 17.4940, 78.3985, 5);
INSERT INTO transport.boarding (school_id, trip_id, student_id, stop_id, event, event_at, source, marked_by_user_id) VALUES
 (1, 1, 1, 2, 'BOARDED', current_date + time '07:46', 'RFID', 21), (1, 1, 1, 3, 'ALIGHTED', current_date + time '08:18', 'RFID', 21),
 (1, 1, 6, 3, 'NO_SHOW', current_date + time '08:06', 'MANUAL', 21);
INSERT INTO transport.fuel_log (school_id, vehicle_id, filled_on, litres, amount, odometer_km) VALUES (1, 1, current_date - 2, 180, 18000, 45210);

-- ---------------------------------------------------------------- communication
INSERT INTO communication.messaging_policy (school_id, parent_can_start_chat, office_hours_start, office_hours_end, show_staff_phone, retention_days) VALUES (1, true, '08:00', '18:00', false, 365);
INSERT INTO communication.notification (school_id, notification_id, sent_by_user_id, sent_time, title, category, body, channel, audience_type, requires_ack, severity) VALUES
 (1, 1, 3, now() - interval '2 days', 'PTM on Saturday', 'CIRCULAR', 'Parent-teacher meeting this Saturday 10am-1pm.', 'APP', 'ALL', true, 'ACTION'),
 (1, 2, 4, now() - interval '3 hours', 'Meera absent today', 'ATTENDANCE', 'Meera was marked absent in the morning register.', 'APP', 'USERS', false, 'URGENT'),
 (1, 3, 13, now() - interval '50 minutes', 'Kabir not back from outing', 'HOSTEL', 'Kabir was due back 1 hour ago. Escalated to chief warden.', 'APP', 'USERS', true, 'CRITICAL'),
 (1, 4, 8, now() - interval '1 day', 'Fee reminder', 'FEES', 'Term 1 tuition is overdue.', 'APP', 'USERS', false, 'ACTION');
INSERT INTO communication.notification_recipient (school_id, notification_id, recipient_user_id, student_id, delivery_status, read_at, acknowledged_at) VALUES
 (1, 1, 6, 1, 'DELIVERED', now() - interval '1 day', NULL), (1, 1, 24, 3, 'DELIVERED', NULL, NULL), (1, 1, 4, NULL, 'DELIVERED', now() - interval '1 day', now() - interval '1 day'),
 (1, 1, 22, NULL, 'DELIVERED', NULL, NULL), (1, 3, 12, 3, 'DELIVERED', NULL, NULL), (1, 3, 24, 3, 'DELIVERED', now() - interval '40 minutes', NULL),
 (1, 3, 3, 3, 'DELIVERED', NULL, NULL), (1, 4, 6, 2, 'DELIVERED', NULL, NULL), (1, 4, 24, 3, 'DELIVERED', NULL, NULL);
INSERT INTO communication.conversation (school_id, conversation_id, kind, student_id, class_section_id, created_by_user_id, parents_can_reply, is_locked, created_at) VALUES
 (1, 1, 'PARENT_TEACHER', 1, 1, 6, true, false, now() - interval '5 days'),
 (1, 2, 'CLASS_GROUP', NULL, 1, 4, false, false, now() - interval '60 days');
INSERT INTO communication.conversation_member (school_id, conversation_id, user_id, member_role, last_read_at) VALUES
 (1, 1, 6, 'PARENT', now() - interval '1 day'), (1, 1, 4, 'STAFF', now() - interval '2 hours'),
 (1, 2, 4, 'MODERATOR', now()), (1, 2, 6, 'PARENT', now() - interval '3 days'), (1, 2, 24, 'PARENT', NULL);
INSERT INTO communication.message (school_id, conversation_id, sender_user_id, body, sent_at) VALUES
 (1, 1, 6, 'Arjun found the fractions homework hard. Any tips?', now() - interval '5 days'),
 (1, 1, 4, 'Sure, I will do a revision on Monday.', now() - interval '4 days'),
 (1, 1, 6, 'Thank you!', now() - interval '3 hours'),
 (1, 2, 4, 'Reminder: Science project due Friday.', now() - interval '2 days');
INSERT INTO communication.news_post (school_id, post_id, author_user_id, title, body, audience_type, is_pinned, created_at, expires_at) VALUES
 (1, 1, 3, 'Sports day winners', 'Congratulations to Red House!', 'ALL', true, now() - interval '1 day', now() + interval '29 days'),
 (1, 2, 4, 'Science lab visit', 'Grade 5 visited the lab today.', 'SECTION', false, now() - interval '4 hours', now() + interval '30 days');
UPDATE communication.news_post SET class_section_id = 1 WHERE post_id = 2;
INSERT INTO communication.news_media (school_id, media_id, post_id, provider, file_id, mime_type, size_bytes, width, height, sort_order) VALUES (1, 1, 1, 'LOCAL', 'sports-1.jpg', 'image/jpeg', 204800, 1280, 720, 1);
INSERT INTO communication.news_reaction (school_id, post_id, user_id, reaction, reacted_at) VALUES (1, 1, 6, 'CLAP', now() - interval '20 hours'), (1, 1, 4, 'LIKE', now() - interval '22 hours');
INSERT INTO communication.ptm_session (school_id, ptm_id, event_id, class_section_id, slot_minutes, mode) VALUES (1, 1, NULL, 1, 10, 'IN_PERSON');
INSERT INTO communication.ptm_slot (school_id, ptm_id, teacher_user_id, start_at, booked_by_user_id, student_id, status)
 SELECT 1, 1, 4, date_trunc('day', now()) + interval '3 days 10 hours' + (n * 10 || ' min')::interval, CASE WHEN n = 0 THEN 6 END, CASE WHEN n = 0 THEN 1 END, CASE WHEN n = 0 THEN 'BOOKED' ELSE 'OPEN' END
 FROM generate_series(0, 5) n;
INSERT INTO communication.poll (school_id, poll_id, notification_id, question, options, is_anonymous, one_per_child, closes_at) VALUES
 (1, 1, 1, 'Will you attend the PTM?', '[{"key":"YES","label":"Yes"},{"key":"NO","label":"No"}]', false, true, now() + interval '2 days');
INSERT INTO calendar.event (school_id, academic_year_id, event_type, title, start_date, end_date, applies_to, is_holiday, created_by_user_id) VALUES
 (1, 1, 'PTM', 'Parent-teacher meeting', current_date + 3, current_date + 3, 'ALL', false, 3),
 (1, 1, 'HOLIDAY', 'Festival holiday', current_date + 9, current_date + 9, 'ALL', true, 3),
 (1, 1, 'EXAM', 'Term 1 exams', current_date + 5, current_date + 12, 'ALL', false, 3);
INSERT INTO compliance.consent_form (school_id, form_id, feature_code, version, title, purpose, data_used, shared_with, retention, if_declined, signer_parent, signer_staff, is_required, published_at, published_by_user_id) VALUES
 (1, 1, 'BIOMETRIC_ATTENDANCE', 1, 'Face attendance', 'Mark attendance with a face scan at the gate', ARRAY['Face template', 'Entry time'], 'No one outside the school', 'Until the student leaves', 'Attendance is marked by the teacher', true, true, false, now() - interval '30 days', 7),
 (1, 2, 'GPS_TRANSPORT', 1, 'Live bus location', 'Show the bus location to parents', ARRAY['Bus location', 'Boarding time'], 'GPS vendor', '90 days', 'No live tracking for your child', true, false, false, now() - interval '30 days', 7);
INSERT INTO compliance.consent_record (school_id, form_id, form_version, subject_kind, subject_id, signer_user_id, decision, method, decided_at) VALUES
 (1, 1, 1, 'STUDENT', 1, 6, 'GRANTED', 'IN_APP', now() - interval '20 days'), (1, 2, 1, 'STUDENT', 1, 6, 'GRANTED', 'IN_APP', now() - interval '20 days'),
 (1, 1, 1, 'STAFF', 4, 4, 'GRANTED', 'IN_APP', now() - interval '25 days');
INSERT INTO records.id_card (school_id, holder_kind, holder_id, card_number, qr_token, issued_on, valid_till, status) VALUES
 (1, 'STUDENT', 1, 'STU-2026-0001', 'qr-stu-1', current_date - 120, current_date + 245, 'ACTIVE'),
 (1, 'STAFF', 4, 'STF-2026-0004', 'qr-stf-4', current_date - 120, current_date + 245, 'ACTIVE');
INSERT INTO records.clearance (school_id, student_id, purpose, department, status, blocking_note) VALUES (1, 9, 'TC', 'LIBRARY', 'BLOCKED', 'Book not returned');
INSERT INTO records.document (school_id, document_id, owner_kind, owner_id, doc_type, file_url, mime_type, size_bytes, uploaded_by_user_id, uploaded_at) VALUES
 (1, 1, 'STUDENT', 1, 'BIRTH_CERT', 'local://docs/1-birth.pdf', 'application/pdf', 120000, 10, now() - interval '800 days');

-- ---------------------------------------------------------------- front office, admissions, security, inventory, facility, library
INSERT INTO frontoffice.visitor (school_id, visitor_id, name, phone, id_proof_type, id_proof_last4) VALUES (1, 1, 'Kiran Vendor', '+919833333333', 'AADHAAR', '9876'), (1, 2, 'Anita Devi', '+919100000005', 'AADHAAR', '5555');
INSERT INTO frontoffice.visit (school_id, visit_id, visitor_id, purpose, host_user_id, student_id, badge_number, check_in_at, check_out_at) VALUES
 (1, 1, 1, 'VENDOR', 19, NULL, 'V-01', now() - interval '2 hours', NULL), (1, 2, 2, 'PARENT_MEETING', 4, 1, 'V-02', now() - interval '1 day', now() - interval '23 hours');
INSERT INTO frontoffice.parcel (school_id, direction, for_student_id, for_user_id, courier, tracking_number, received_at) VALUES (1, 'IN', 2, NULL, 'BlueDart', 'BD123', now() - interval '4 hours'), (1, 'IN', NULL, 4, 'India Post', 'IP777', now() - interval '1 day');
INSERT INTO frontoffice.gate_pass (school_id, student_id, reason, requested_by_user_id, approved_by_user_id, verification, out_at, verified_by_user_id) VALUES (1, 6, 'Doctor visit', 6, 4, 'PARENT_OTP', now() - interval '1 day', 11);
INSERT INTO admissions.seat_plan (school_id, academic_year_id, program_id, total_seats, rte_seats, management_seats, hostel_seats) VALUES (1, 1, 1, 40, 10, 4, 10), (1, 1, 2, 40, 10, 4, 10);
INSERT INTO admissions.enquiry (school_id, enquiry_id, academic_year_id, program_id, child_name, guardian_name, phone, source, stage, owner_user_id, next_follow_up_at, created_at) VALUES
 (1, 1, 1, 1, 'Ananya S', 'Srinivas', '+919844444441', 'WEBSITE', 'NEW', 10, now() + interval '2 hours', now() - interval '1 day'),
 (1, 2, 1, 2, 'Karthik M', 'Mahesh', '+919844444442', 'WALK_IN', 'VISIT_SCHEDULED', 10, now() - interval '1 hour', now() - interval '6 days'),
 (1, 3, 1, 1, 'Riya P', 'Prakash', '+919844444443', 'REFERRAL', 'APPLIED', 10, NULL, now() - interval '15 days'),
 (1, 4, 1, 2, 'Sam T', 'Thomas', '+919844444444', 'SOCIAL', 'LOST', 10, NULL, now() - interval '30 days');
INSERT INTO admissions.application (school_id, application_id, enquiry_id, academic_year_id, program_id, application_number, form_data, residency_requested, transport_requested, quota, status, submitted_at) VALUES
 (1, 1, 3, 1, 1, 'APP-26-0001', '{"child": {"firstName": "Riya", "lastName": "P", "dob": "2016-05-05"}, "parents": [{"name": "Prakash", "phone": "+919844444443"}]}', 'HOSTELLER', true, 'GENERAL', 'OFFERED', now() - interval '10 days');
INSERT INTO admissions.reenrollment (school_id, student_id, academic_year_id, status) VALUES (1, 1, 1, 'INVITED'), (1, 2, 1, 'CONFIRMED');
INSERT INTO security.checkpoint (school_id, checkpoint_id, code, name, location_id, tag_uid) VALUES (1, 1, 'CP-GATE', 'Main gate', 6, 'NFC-1'), (1, 2, 'CP-HOS', 'Hostel back', NULL, 'NFC-2'), (1, 3, 'CP-LAB', 'Lab block', 8, 'NFC-3');
INSERT INTO security.patrol_route (school_id, route_id, post_id, name, active_from, active_to, round_every_minutes, max_round_minutes) VALUES (1, 1, 2, 'Perimeter', '18:00', '06:00', 120, 30);
INSERT INTO security.route_checkpoint (school_id, route_id, checkpoint_id, sequence, photo_required) VALUES (1, 1, 1, 1, false), (1, 1, 2, 2, true), (1, 1, 3, 3, false);
INSERT INTO security.patrol_round (school_id, round_id, route_id, roster_entry_id, guard_user_id, due_at, started_at, completed_at, missed_checkpoints, status) VALUES
 (1, 1, 1, NULL, 17, now() - interval '3 hours', now() - interval '3 hours', now() - interval '2 hours 40 min', 0, 'COMPLETED'),
 (1, 2, 1, NULL, 17, now() - interval '1 hour', now() - interval '50 min', NULL, 0, 'IN_PROGRESS'),
 (1, 3, 1, NULL, 17, now() + interval '1 hour', NULL, NULL, 0, 'DUE');
INSERT INTO security.patrol_scan (school_id, round_id, checkpoint_id, scanned_at, method) VALUES
 (1, 1, 1, now() - interval '3 hours', 'NFC'), (1, 1, 2, now() - interval '2 hours 50 min', 'NFC'), (1, 1, 3, now() - interval '2 hours 42 min', 'NFC'), (1, 2, 1, now() - interval '48 min', 'NFC');
INSERT INTO security.key (school_id, key_id, code, location_id, is_master) VALUES (1, 1, 'K-LAB', 8, false), (1, 2, 'K-STORE', 4, false), (1, 3, 'K-MASTER', NULL, true);
INSERT INTO security.key_movement (school_id, key_id, issued_to_user_id, issued_by_user_id, issued_at, due_back_at, returned_at) VALUES
 (1, 1, 5, 18, now() - interval '5 hours', now() - interval '1 hour', NULL), (1, 2, 19, 18, now() - interval '2 hours', now() + interval '4 hours', NULL);
INSERT INTO security.welfare_ping (school_id, roster_entry_id, sent_at, responded_at, status) SELECT 1, roster_entry_id, now() - interval '30 min', now() - interval '29 min', 'OK' FROM hr.roster_entry WHERE user_id = 17 AND duty_date = current_date;
INSERT INTO security.vehicle_entry (school_id, post_id, vehicle_number, purpose, in_at, logged_by_user_id) VALUES (1, 1, 'TS07 AB 1111', 'DELIVERY', now() - interval '1 hour', 17);
INSERT INTO security.occurrence (school_id, occurrence_type, severity, occurred_at, location_id, description, reported_by_user_id, status) VALUES (1, 'POWER_CUT', 'LOW', now() - interval '6 hours', 8, 'Lab block power cut, 10 min', 17, 'RESOLVED');
INSERT INTO inventory.item_category (school_id, category_id, name) VALUES (1, 1, 'Stationery'), (1, 2, 'Provisions'), (1, 3, 'Electronics');
INSERT INTO inventory.item_catalog (school_id, item_catalog_id, item_name, item_type, category_id, unit_of_measure, is_consumable) VALUES
 (1, 1, 'A4 paper ream', 'CONSUMABLE', 1, 'ream', true), (1, 2, 'Rice', 'CONSUMABLE', 2, 'kg', true), (1, 3, 'Toor dal', 'CONSUMABLE', 2, 'kg', true), (1, 4, 'Projector', 'ASSET', 3, 'unit', false);
INSERT INTO inventory.inventory_stock (school_id, item_catalog_id, location_id, quantity_on_hand, reorder_level, reorder_qty, avg_unit_cost) VALUES
 (1, 1, 4, 12, 20, 50, 280), (1, 2, 5, 400, 200, 500, 52), (1, 3, 5, 60, 80, 100, 140), (1, 4, 4, 2, 0, 0, 42000);
INSERT INTO inventory.vendor (school_id, vendor_id, name, gstin, phone, payment_terms_days, rating, is_active) VALUES (1, 1, 'Sri Sai Provisions', '36ABCDE1234F1Z5', '+919855555555', 30, 4, true), (1, 2, 'Office Mart', NULL, '+919866666666', 15, 3, true);
UPDATE hostel.mess SET vendor_id = 1 WHERE mess_id = 1;
INSERT INTO inventory.inventory_transaction (school_id, item_catalog_id, issued_by_user_id, txn_type, quantity, unit_cost, from_location_id, cost_centre, txn_at, note) VALUES
 (1, 2, 19, 'CONSUMPTION', 40, 52, 5, 'MESS', now() - interval '1 day', 'Mess daily issue'), (1, 3, 19, 'CONSUMPTION', 8, 140, 5, 'MESS', now() - interval '1 day', 'Mess daily issue');
INSERT INTO inventory.requisition (school_id, requisition_id, requisition_number, requested_by_user_id, cost_centre, needed_by, justification, estimated_total, status) VALUES (1, 1, 'REQ-0001', 16, 'MESS', current_date + 3, 'Dal running low', 14000, 'SUBMITTED');
INSERT INTO inventory.requisition_line (school_id, requisition_id, item_catalog_id, quantity, estimated_unit_cost) VALUES (1, 1, 3, 100, 140);
INSERT INTO facility.ticket (school_id, ticket_id, category, room_id, raised_by_user_id, raised_for_student_id, description, priority, assigned_to_user_id, sla_due_at, status) VALUES
 (1, 1, 'PLUMBING', 2, 13, NULL, 'Tap leaking in A102', 'MEDIUM', NULL, now() + interval '20 hours', 'OPEN'),
 (1, 2, 'ELECTRICAL', NULL, 4, NULL, 'Projector not working in Room 101', 'HIGH', 5, now() + interval '4 hours', 'ASSIGNED');
INSERT INTO library.library_book (school_id, book_id, isbn, title, author) VALUES (1, 1, '9780000000001', 'Charlotte''s Web', 'E. B. White');
INSERT INTO library.book_copy (school_id, copy_id, book_id, barcode) VALUES (1, 1, 1, 'LIB-0001');
INSERT INTO library.library_borrowing (school_id, copy_id, borrower_student_id, issued_by_user_id, issued_on, due_on) VALUES (1, 1, 9, 5, current_date - 30, current_date - 16);

-- ---------------------------------------------------------------- approvals (flow engine comes later; instances only)
INSERT INTO platform.flow_definition (school_id, flow_id, flow_code, version, name, definition, is_active, created_at) VALUES
 (1, 1, 'STAFF_LEAVE', 1, 'Staff leave', '{"steps": ["PRINCIPAL"]}', true, now() - interval '100 days'),
 (1, 2, 'EXPENSE', 1, 'Expense approval', '{"steps": ["ACCOUNTANT", "PRINCIPAL"]}', true, now() - interval '100 days'),
 (1, 3, 'OUTING', 1, 'Hostel outing', '{"steps": ["PARENT", "WARDEN"]}', true, now() - interval '100 days');
INSERT INTO platform.flow_instance (school_id, instance_id, flow_id, ref_kind, ref_id, current_step, status, submitted_by_user_id, amount, due_by, created_at) VALUES
 (1, 1, 1, 'LEAVE_REQUEST', 2, 'PRINCIPAL', 'OPEN', 4, NULL, now() + interval '1 day', now() - interval '5 hours'),
 (1, 2, 1, 'LEAVE_REQUEST', 3, 'PRINCIPAL', 'OPEN', 5, NULL, now() + interval '2 days', now() - interval '2 hours'),
 (1, 3, 2, 'EXPENSE', 3, 'ACCOUNTANT', 'OPEN', 20, 18000, now() + interval '2 days', now() - interval '1 day'),
 (1, 4, 3, 'OUTING', 3, 'PARENT', 'OPEN', 13, NULL, now() + interval '1 day', now() - interval '2 hours');
INSERT INTO platform.flow_transition_log (school_id, instance_id, from_step, to_step, action, actor_user_id, actor_role_code, occurred_at) VALUES
 (1, 1, NULL, 'PRINCIPAL', 'SUBMIT', 4, 'TEACHER', now() - interval '5 hours'), (1, 3, NULL, 'ACCOUNTANT', 'SUBMIT', 20, 'TRANSPORT_MANAGER', now() - interval '1 day');

-- identity sequences past the explicit ids
DO $$
DECLARE r RECORD;
BEGIN
  FOR r IN SELECT n.nspname AS s, c.relname AS t, a.attname AS col
             FROM pg_attribute a JOIN pg_class c ON c.oid = a.attrelid JOIN pg_namespace n ON n.oid = c.relnamespace
            WHERE a.attidentity IN ('a', 'd') AND c.relkind = 'r' AND n.nspname NOT IN ('pg_catalog', 'information_schema')
  LOOP
    EXECUTE format('SELECT setval(pg_get_serial_sequence(%L, %L), coalesce((SELECT max(%I) FROM %I.%I), 0) + 1, false)',
                   r.s || '.' || r.t, r.col, r.col, r.s, r.t);
  END LOOP;
END $$;

COMMIT;
