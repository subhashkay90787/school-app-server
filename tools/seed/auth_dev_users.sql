-- Development users on school-auth (school_platform_db, schema identity) for every school-side actor in branch 1,
-- with the same user ids as tools/seed/dev_seed.sql. Users 2-7 come from the auth server's own dev setup
-- (2 Office = SCHOOL_ADMIN, 3 Priya = PRINCIPAL, 4 Ravi = TEACHER, 5 Lab = LAB_ASSISTANT (base STAFF),
-- 6 Anita = PARENT, 7 Trustee = ADMIN, org-wide); user 5 also gets the plain STAFF role. Phones are +9191001000NN (NN = user id) for OTP logins.
-- Run as the owner:  psql -v ON_ERROR_STOP=1 -d school_platform_db -f tools/seed/auth_dev_users.sql
BEGIN;
SET LOCAL search_path = identity, public;
INSERT INTO identity.app_user (user_id, first_name, last_name, phone_number, email, user_category)
SELECT u.id, u.first, u.last, '+9191001000' || lpad(u.id::text, 2, '0'), u.email, u.cat
FROM (VALUES (8, 'Kavya', 'Accounts', 'accounts@stm.com', 'STAFF'), (9, 'Harish', 'HR', 'hr@stm.com', 'STAFF'),
             (10, 'Neha', 'Admissions', 'admissions@stm.com', 'STAFF'), (11, 'Lata', 'Front', 'reception@stm.com', 'STAFF'),
             (12, 'Ramesh', 'Chief', 'chiefwarden@stm.com', 'STAFF'), (13, 'Gopal', 'Warden', 'warden@stm.com', 'STAFF'),
             (14, 'Sarala', 'Matron', 'matron@stm.com', 'STAFF'), (15, 'Asha', 'Nurse', 'nurse@stm.com', 'STAFF'),
             (16, 'Mohan', 'Mess', 'mess@stm.com', 'STAFF'), (17, 'Bhim', 'Guard', 'guard@stm.com', 'STAFF'),
             (18, 'Vikram', 'Supervisor', 'secsup@stm.com', 'STAFF'), (19, 'Store', 'Keeper', 'store@stm.com', 'STAFF'),
             (20, 'Tarun', 'Transport', 'transport@stm.com', 'STAFF'), (21, 'Raju', 'Driver', 'driver@stm.com', 'NON_STAFF'),
             (22, 'Meena', 'Iyer', 'meena@stm.com', 'STAFF'), (23, 'Arjun', 'Devi', 'arjun@stm.com', 'STUDENT'),
             (24, 'Farhan', 'Ali', 'farhan@x.com', 'PARENT')) AS u(id, first, last, email, cat)
ON CONFLICT (user_id) DO NOTHING;
SELECT setval('identity.app_user_user_id_seq', greatest((SELECT max(user_id) FROM identity.app_user), 1));

INSERT INTO identity.user_school_staff_type (user_id, school_id, staff_type_id)
SELECT a.uid, 1, st.staff_type_id
FROM (VALUES (8, 'ACCOUNTANT'), (9, 'HR_MANAGER'), (10, 'ADMISSION_OFFICER'), (11, 'RECEPTIONIST'), (12, 'CHIEF_WARDEN'),
             (13, 'WARDEN'), (14, 'MATRON'), (15, 'NURSE'), (16, 'MESS_MANAGER'), (17, 'SECURITY'), (18, 'SECURITY_SUPERVISOR'),
             (19, 'STORE_KEEPER'), (20, 'TRANSPORT_MANAGER'), (21, 'DRIVER'), (22, 'TEACHER'), (23, 'STUDENT'), (24, 'PARENT'),
             (5, 'STAFF')) AS a(uid, code)
JOIN identity.staff_type st ON st.type_code = a.code AND st.school_id IS NULL
WHERE NOT EXISTS (SELECT 1 FROM identity.user_school_staff_type x WHERE x.user_id = a.uid AND x.school_id = 1 AND x.staff_type_id = st.staff_type_id);
-- the branch runs school buses (TRANSPORT is off by default for a new branch): organisation entitlement, then branch
INSERT INTO identity.organization_feature (organization_id, feature_id)
SELECT 1, f.feature_id FROM identity.feature f WHERE f.feature_code = 'TRANSPORT' ON CONFLICT DO NOTHING;
INSERT INTO identity.school_feature (school_id, feature_id)
SELECT 1, f.feature_id FROM identity.feature f WHERE f.feature_code = 'TRANSPORT' ON CONFLICT DO NOTHING;
COMMIT;
