# School DB, transcribed from project doc "ER v5 - auth DB and school DB" (school database section).
# One table per "== schema.table"; every tenant table also gets school_id (added by the generator).
# Column: name type [pk|pkc] [uk|uk:col] [nn] [>schema.table|>U] [{A|B|C}] [=default]
#   types: i int, b bigint, s text, d date, dt timestamptz, tm time, n numeric(14,2), f double, bo boolean,
#          j jsonb, a text[], u uuid.  Columns named *_id are BIGINT.
#   pk = identity primary key, pkc = part of a composite primary key (with school_id), nn = NOT NULL
#   >U = directory.app_user (single-column FK); >schema.table = composite (school_id, col) FK to that table
#   uk = UNIQUE (school_id, col); uk:other = UNIQUE (school_id, other, col)
#   @key(a,b) = UNIQUE NULLS NOT DISTINCT (school_id, a, b) for tables without a primary key
# Tables marked "+" are additions beyond ER v5 named in Schema v5 / C4 v1 (columns are ours).

== hr.teacher_metadata
user_id b pkc >U
teacher_enrollment_number s uk
department_id b >academics.department
designation s
teacher_joined_date d
teacher_leaving_date d
qualification s

== academics.academic_year
academic_year_id b pk
name s nn uk
start_date d nn
end_date d nn
is_current bo nn =false

== academics.academic_term
term_id b pk
academic_year_id b nn >academics.academic_year
term_type s nn {TERM|SEMESTER|TRIMESTER|BATCH_CYCLE}
name s nn
sequence i
start_date d
end_date d

== academics.department
department_id b pk
department_code s nn uk
name s nn
head_user_id b >U

== academics.program
program_id b pk
department_id b >academics.department
program_code s nn uk
name s nn
program_kind s {GRADE|DEGREE|DIPLOMA|CERTIFICATE|COURSE}
level s {PRE_PRIMARY|PRIMARY|SECONDARY|UG|PG|DOCTORAL|NONE}
duration_terms i
total_credits n

== academics.student
student_id b pk
student_admission_number s nn uk
registration_number s
student_admission_date d
first_name s nn
last_name s
student_user_id b >U
class_section_id b >academics.class_section
fee_structure_id b >finance.fee_structure
previous_school_id b
previous_student_id b
apaar_id s uk
pen s
date_of_birth d
gender s
social_category s
is_cwsn bo =false
mother_tongue s
residency_type s nn {DAY_SCHOLAR|HOSTELLER} =DAY_SCHOLAR
photo_url s
status s nn {ACTIVE|ALUMNI|LEFT|TC_ISSUED|SUSPENDED}
admission_application_id b >admissions.application
aadhaar_last4 s

== academics.student_parent
student_id b nn >academics.student
user_id b nn >U
relationship_type s
is_primary_contact bo =false
@key(student_id,user_id)

== academics.class_section
class_section_id b pk
program_id b >academics.program
academic_year_id b nn >academics.academic_year
term_id b >academics.academic_term
section_kind s nn {SECTION|BATCH|COHORT}
stage_number i
section_name s nn uk:academic_year_id
capacity i
teacher_user_id b >U
room_location_id b >inventory.location
day_start_time tm
day_end_time tm
late_after_time tm

== academics.student_enrollment
enrollment_id b pk
student_id b nn >academics.student
program_id b >academics.program
class_section_id b >academics.class_section
academic_year_id b nn >academics.academic_year
term_id b >academics.academic_term
status s nn {ACTIVE|PROMOTED|COMPLETED|DROPPED|TRANSFERRED}
enrolled_on d
exited_on d

== academics.period
period_id b pk
period_time s nn

== academics.class_section_period
class_section_period_id b pk
class_section_id b nn >academics.class_section
period_id b nn >academics.period

== academics.timetable
timetable_id b pk
class_section_period_id b nn >academics.class_section_period
staff_subject_id b >academics.staff_subject
offering_id b >academics.course_offering
day_of_week s nn {MON|TUE|WED|THU|FRI|SAT|SUN}
timetable_version_id b >academics.timetable_version
room_location_id b >inventory.location

== academics.subject
subject_id b pk
department_id b >academics.department
subject_code s uk
subject_name s nn uk
subject_type s {CORE|ELECTIVE|LAB|PROJECT}
credits n

== academics.staff_subject
staff_subject_id b pk
user_id b nn >U
subject_id b nn >academics.subject

== academics.course_offering
offering_id b pk
subject_id b nn >academics.subject
term_id b nn >academics.academic_term
staff_subject_id b >academics.staff_subject
class_section_id b >academics.class_section
capacity i
is_elective bo =false

== academics.course_registration
registration_id b pk
offering_id b nn >academics.course_offering
student_id b nn >academics.student
status s nn {REGISTERED|DROPPED|COMPLETED|FAILED}
registered_on d
final_grade_id b >assessment.grade
grade_points n
@unique(offering_id,student_id)

== operations.staff_absences
staff_absence_id b pk
user_id b nn >U
date d nn
status s
leave_request_id b >hr.leave_request
reason s
absence_kind s {LEAVE|ON_DUTY|UNPLANNED}

== operations.substitution
substitution_id b pk
staff_absence_id b nn >operations.staff_absences
substitute_user_id b nn >U
class_section_period_id b nn >academics.class_section_period

== operations.student_absence
student_absence_id b pk
student_id b nn >academics.student
class_section_period_id b >academics.class_section_period
offering_id b >academics.course_offering
date d nn
reported_by_user_id b >U
absence_reason s {UNEXCUSED|EXCUSED|MEDICAL|ON_DUTY|HOSTEL_OUTING}
student_leave_request_id b >operations.student_leave_request

== operations.homework
homework_id b pk
class_section_id b nn >academics.class_section
staff_subject_id b >academics.staff_subject
assigned_date d nn
due_date d
title s nn
description s
attachment_urls a
submission_mode s {NONE|ONLINE|OFFLINE} =NONE
max_marks n

== operations.homework_exception
exception_id b pk
homework_id b nn >operations.homework
student_id b nn >academics.student
status s
logged_by_user_id b >U

== assessment.exams
exam_id b pk
staff_subject_id b >academics.staff_subject
class_section_id b >academics.class_section
term_id b >academics.academic_term
offering_id b >academics.course_offering
scheduled_by_user_id b >U
invigilated_by_user_id b >U
exam_name s nn
exam_type s {UNIT_TEST|MIDTERM|END_TERM|INTERNAL|PRACTICAL|MOCK}
max_marks n
weightage_pct n
exam_date d
exam_session_id b >assessment.exam_session
room_location_id b >inventory.location
start_time tm
duration_minutes i
status s nn {DRAFT|SCHEDULED|MARKS_ENTRY|LOCKED|PUBLISHED}

== assessment.grade_scale
grade_scale_id b pk
name s nn uk
scale_type s {PERCENT_BAND|LETTER|GPA_10|GPA_4}
program_id b >academics.program

== assessment.grade
grade_id b pk
grade_scale_id b nn >assessment.grade_scale
min_score n
max_score n
grade_point n
grade_name s nn uk:grade_scale_id

== assessment.marks
mark_id b pk
exam_id b nn >assessment.exams
student_id b nn >academics.student
mark_obtained f
grade_id b >assessment.grade
is_absent bo =false
entered_by_user_id b >U
entered_at dt
moderated_by_user_id b >U
@unique(exam_id,student_id)

== assessment.term_result
term_result_id b pk
student_id b nn >academics.student
term_id b nn >academics.academic_term
sgpa n
cgpa n
credits_earned n
result_status s {PASS|FAIL|PROMOTED|BACKLOG|WITHHELD}
@unique(student_id,term_id)

== assessment.student_behavior_log
log_id b pk
student_id b nn >academics.student
logged_by_user_id b >U
log_date d nn
category s
note s
severity s
incident_id b >discipline.incident

== communication.notification
notification_id b pk
timetable_id b >academics.timetable
sent_by_user_id b >U
sent_time dt
title s nn
category s
attachment_urls a
body s
channel s {APP|WHATSAPP|EMAIL|ALL} =APP
audience_type s {USERS|SECTION|PROGRAM|HOSTEL|BLOCK|STAFF_TYPE|ALL}
requires_ack bo =false
scheduled_at dt
template_id b >communication.template
# + UX v2 section 8: alert severity for critical takeovers
severity s nn {INFO|ACTION|URGENT|CRITICAL} =INFO

== communication.notification_recipient
notification_id b nn >communication.notification
recipient_user_id b nn >U
student_id b >academics.student
delivery_status s
read_at dt
acknowledged_at dt
@key(notification_id,recipient_user_id,student_id)

== finance.fee_structure
fee_structure_id b pk
program_id b >academics.program
academic_year_id b >academics.academic_year
term_id b >academics.academic_term
fee_type s
billing_frequency s {ONE_TIME|MONTHLY|TERM|ANNUAL|PER_COURSE}
amount n nn
fee_head_id b >finance.fee_head
hostel_id b >hostel.hostel
room_type s
route_stop_id b >transport.stop

== finance.fee_installment
installment_id b pk
fee_structure_id b nn >finance.fee_structure
sequence i
due_date d
amount n nn

== finance.fee
fee_id b pk
student_id b nn >academics.student
fee_structure_id b >finance.fee_structure
installment_id b >finance.fee_installment
due_date d
remaining_due n
fee_head_id b >finance.fee_head
gross_amount n
concession_amount n =0
fine_amount n =0
net_amount n
paid_amount n =0
status s nn {DUE|PART_PAID|PAID|WAIVED|CANCELLED}
source_kind s {STRUCTURE|HOSTEL_DAMAGE|LIBRARY_FINE|DISCIPLINE_FINE|CUSTODY_LOSS|MANUAL} =STRUCTURE

== inventory.location
location_id b pk
room_name s nn
building_floor s
location_type s {CLASSROOM|LAB|STORE|OFFICE|HOSTEL_ROOM|MESS|MESS_STORE|LOCKER_ROOM|GATE|OTHER}
parent_location_id b >inventory.location

== inventory.item_catalog
item_catalog_id b pk
item_name s nn
item_type s
category_id b >inventory.item_category
unit_of_measure s
is_consumable bo =true
hsn_code s
gst_rate n
track_batch bo =false

== inventory.inventory_stock
stock_id b pk
item_catalog_id b nn >inventory.item_catalog
location_id b nn >inventory.location
quantity_on_hand n nn =0
reorder_level n
reorder_qty n
avg_unit_cost n
@unique(item_catalog_id,location_id)

== inventory.asset_item
asset_id b pk
item_catalog_id b nn >inventory.item_catalog
barcode_id s uk
purchase_date d
purchase_cost n
vendor_id b >inventory.vendor
grn_line_id b >inventory.grn_line
warranty_until d
amc_until d
status s nn {IN_STORE|ASSIGNED|IN_REPAIR|LOST|DISPOSED}
assigned_location_id b >inventory.location
assigned_user_id b >U
assigned_student_id b >academics.student
depreciation_method s
useful_life_months i
disposed_on d

== inventory.inventory_transaction
transaction_id b pk
item_catalog_id b nn >inventory.item_catalog
asset_id b >inventory.asset_item
issued_by_user_id b >U
issued_to_user_id b >U
txn_type s nn {RECEIPT|ISSUE|RETURN|TRANSFER|CONSUMPTION|ADJUSTMENT|WRITE_OFF}
quantity n nn
unit_cost n
from_location_id b >inventory.location
to_location_id b >inventory.location
issued_to_student_id b >academics.student
issued_to_department_id b >academics.department
cost_centre s
reference_kind s
reference_id b
batch_no s
txn_at dt nn =now()
note s

== library.library_book
book_id b pk
isbn s uk
title s nn
author s
publisher s
edition s

== library.book_copy
copy_id b pk
book_id b nn >library.library_book
location_id b >inventory.location
barcode s nn uk

== library.library_borrowing
borrowing_id b pk
copy_id b nn >library.book_copy
borrower_student_id b >academics.student
borrower_user_id b >U
issued_by_user_id b >U
issued_on d nn
due_on d
returned_on d
fine_fee_id b >finance.fee

== calendar.event
event_id b pk
academic_year_id b >academics.academic_year
event_type s nn {HOLIDAY|VACATION|EXAM|PTM|EVENT|WORKING_DAY|HOSTEL_VISITING_DAY}
title s nn
start_date d nn
end_date d
applies_to s {ALL|PROGRAM|SECTION|HOSTEL|STAFF} =ALL
program_id b >academics.program
class_section_id b >academics.class_section
hostel_id b >hostel.hostel
is_holiday bo =false
created_by_user_id b >U

== admissions.seat_plan
seat_plan_id b pk
academic_year_id b nn >academics.academic_year
program_id b nn >academics.program
total_seats i
rte_seats i
management_seats i
hostel_seats i
@unique(academic_year_id,program_id)

== admissions.enquiry
enquiry_id b pk
academic_year_id b >academics.academic_year
program_id b >academics.program
child_name s nn
child_dob d
guardian_name s
phone s nn
email s
source s {WALK_IN|WEBSITE|PHONE|WHATSAPP|SOCIAL|REFERRAL|CAMPAIGN|EVENT}
campaign s
stage s nn {NEW|CONTACTED|VISIT_SCHEDULED|VISITED|APPLIED|LOST}
owner_user_id b >U
next_follow_up_at dt
lost_reason s
created_at dt nn =now()

== admissions.enquiry_follow_up
follow_up_id b pk
enquiry_id b nn >admissions.enquiry
channel s {CALL|WHATSAPP|EMAIL|VISIT}
outcome s
note s
done_by_user_id b >U
done_at dt nn =now()

== admissions.application
application_id b pk
enquiry_id b >admissions.enquiry
academic_year_id b >academics.academic_year
program_id b >academics.program
application_number s nn uk
form_data j
residency_requested s {DAY_SCHOLAR|HOSTELLER}
transport_requested bo =false
quota s {GENERAL|RTE|MANAGEMENT|STAFF_WARD} =GENERAL
status s nn {DRAFT|SUBMITTED|UNDER_REVIEW|ASSESSMENT|OFFERED|WAITLISTED|REJECTED|ACCEPTED|ENROLLED|WITHDRAWN}
application_fee_id b >finance.fee
applicant_user_id b >U
decided_by_user_id b >U
submitted_at dt
decided_at dt
student_id b >academics.student

== admissions.assessment
assessment_id b pk
application_id b nn >admissions.application
kind s {ENTRANCE_TEST|INTERACTION|INTERVIEW}
scheduled_at dt
max_score n
score n
remarks s
assessed_by_user_id b >U

== admissions.reenrollment
reenrollment_id b pk
student_id b nn >academics.student
academic_year_id b nn >academics.academic_year
status s nn {INVITED|CONFIRMED|DECLINED|LEAVING}
responded_by_user_id b >U
responded_at dt
leaving_reason s

== finance.fee_head
fee_head_id b pk
code s nn uk
name s nn
is_refundable bo =false
gst_rate n
gl_account_code s

== finance.concession_type
concession_type_id b pk
code s nn uk
calc s nn {PERCENT|FIXED}
value n nn
fee_head_id b >finance.fee_head

== finance.student_concession
student_concession_id b pk
student_id b nn >academics.student
concession_type_id b nn >finance.concession_type
academic_year_id b >academics.academic_year
reason s
status s nn {REQUESTED|APPROVED|REJECTED|REVOKED}
approved_by_user_id b >U
approved_at dt

== finance.late_fee_rule
rule_id b pk
fee_structure_id b nn >finance.fee_structure
grace_days i =0
calc s nn {PER_DAY|FLAT|PERCENT}
amount n nn
cap n

== finance.payment
payment_id b pk
student_id b nn >academics.student
paid_by_user_id b >U
amount n nn
mode s nn {UPI|CARD|NETBANKING|CASH|CHEQUE|DD|BANK_TRANSFER|WALLET}
gateway s {RAZORPAY|PAYU|CCAVENUE|NONE} =NONE
gateway_txn_id s uk
idempotency_key s uk
cheque_number s
bank_name s
receipt_number s uk
status s nn {INITIATED|SUCCESS|FAILED|BOUNCED|REFUNDED|PARTIALLY_REFUNDED}
received_by_user_id b >U
paid_at dt

== finance.payment_allocation
allocation_id b pk
payment_id b nn >finance.payment
fee_id b nn >finance.fee
amount n nn

== finance.refund
refund_id b pk
payment_id b nn >finance.payment
amount n nn
reason s {EXCESS|DEPOSIT|WITHDRAWAL|CANCELLED_SERVICE}
status s nn {REQUESTED|APPROVED|PAID|REJECTED}
approved_by_user_id b >U
gateway_refund_id s
refunded_at dt

== finance.student_wallet
wallet_id b pk
student_id b nn uk >academics.student
balance n nn =0
monthly_limit n
is_frozen bo =false

== finance.wallet_txn
wallet_txn_id b pk
wallet_id b nn >finance.student_wallet
txn_type s nn {TOP_UP|CASH_WITHDRAWAL|STORE_PURCHASE|REFUND|ADJUSTMENT}
amount n nn
payment_id b >finance.payment
store_sale_id b >store.sale
performed_by_user_id b >U
witnessed_by_user_id b >U
txn_at dt nn =now()
note s

== hostel.hostel
hostel_id b pk
code s nn uk
name s nn
gender s {BOYS|GIRLS|CO_ED}
hostel_type s {SCHOOL_BOARDING|COLLEGE|STAFF_QUARTERS}
location_id b >inventory.location
capacity i
curfew_weekday tm
curfew_weekend tm
status s nn {ACTIVE|CLOSED_FOR_VACATION|INACTIVE}

== hostel.block
block_id b pk
hostel_id b nn >hostel.hostel
name s nn
floor_count i

== hostel.room
room_id b pk
hostel_id b nn >hostel.hostel
block_id b >hostel.block
floor_number i
room_number s nn uk:hostel_id
room_type s {SINGLE|DOUBLE|TRIPLE|DORM}
capacity i
is_ac bo =false
has_attached_bath bo =false
location_id b >inventory.location
status s nn {AVAILABLE|FULL|MAINTENANCE|BLOCKED}

== hostel.bed
bed_id b pk
room_id b nn >hostel.room
bed_label s nn
status s nn {VACANT|OCCUPIED|BLOCKED|MAINTENANCE}

== hostel.fee_plan
fee_plan_id b pk
hostel_id b nn >hostel.hostel
room_type s
is_ac bo
fee_structure_id b >finance.fee_structure
caution_deposit n

== hostel.allocation_request
request_id b pk
student_id b nn >academics.student
academic_year_id b >academics.academic_year
kind s nn {NEW|ROOM_CHANGE|VACATE}
preferred_hostel_id b >hostel.hostel
preferred_room_type s
roommate_pref_student_id b >academics.student
reason s
status s nn {REQUESTED|APPROVED|WAITLISTED|REJECTED|DONE}
requested_by_user_id b >U
decided_by_user_id b >U

== hostel.allocation
allocation_id b pk
student_id b nn >academics.student
bed_id b nn >hostel.bed
room_id b nn >hostel.room
hostel_id b nn >hostel.hostel
academic_year_id b >academics.academic_year
fee_plan_id b >hostel.fee_plan
check_in_date d nn
check_out_date d
status s nn {ACTIVE|VACATED|TRANSFERRED|SUSPENDED}
is_room_leader bo =false
allocated_by_user_id b >U
request_id b >hostel.allocation_request

== hostel.staff_assignment
assignment_id b pk
hostel_id b nn >hostel.hostel
user_id b nn >U
duty s nn {CHIEF_WARDEN|BLOCK_WARDEN|FLOOR_WARDEN|ROOM_WARDEN|ASSISTANT_WARDEN|MATRON|MESS_INCHARGE}
scope_type s nn {HOSTEL|BLOCK|FLOOR|ROOMS}
block_id b >hostel.block
floor_number i
is_resident bo =false
from_date d nn
to_date d
assigned_by_user_id b >U

== hostel.staff_assignment_room
assignment_id b nn >hostel.staff_assignment
room_id b nn >hostel.room
@key(assignment_id,room_id)

== hostel.roll_call
roll_call_id b pk
hostel_id b nn >hostel.hostel
assignment_id b >hostel.staff_assignment
session s nn {MORNING|STUDY_HOUR|NIGHT|EMERGENCY|CUSTOM}
roll_date d nn
conducted_by_user_id b >U
roster_entry_id b >hr.roster_entry
started_at dt
submitted_at dt
status s nn {OPEN|SUBMITTED|ESCALATED}

== hostel.roll_call_entry
entry_id b pk
roll_call_id b nn >hostel.roll_call
student_id b nn >academics.student
status s nn {PRESENT|ABSENT|ON_OUTING|ON_LEAVE|SICK_BAY|EXCUSED}
outing_id b >hostel.outing_request
custody_pending bo =false
note s
@unique(roll_call_id,student_id)

== hostel.room_inspection
inspection_id b pk
room_id b nn >hostel.room
allocation_id b >hostel.allocation
kind s nn {CHECK_IN|CHECK_OUT|ROUTINE_HYGIENE|CONTRABAND}
inspected_by_user_id b >U
inspected_at dt nn =now()
hygiene_score i
findings s
photo_urls a
damage_charge n
charged_student_id b >academics.student
damage_fee_id b >finance.fee
incident_id b >discipline.incident

== hostel.laundry_batch
batch_id b pk
hostel_id b nn >hostel.hostel
student_id b nn >academics.student
given_at dt nn =now()
item_count i
returned_at dt
returned_count i
missing_count i
handled_by_user_id b >U

== hostel.outing_policy
policy_id b pk
hostel_id b nn >hostel.hostel
outing_type s nn {LOCAL_OUTING|DAY_OUT|WEEKEND_HOME|HOME_LEAVE|VACATION|MEDICAL|EMERGENCY|OFFICIAL}
min_level s {PRIMARY|SECONDARY|UG|PG}
allowed_days s
max_per_month i
max_hours i
requires_parent_approval bo =true
requires_pickup_person bo =false
approver_duty s {BLOCK_WARDEN|CHIEF_WARDEN}
allow_phone_release bo =false
phone_release_at s {GATE_EXIT|GROUP_RELEASE_TIME}
grace_minutes i =15

== hostel.outing_group
group_id b pk
hostel_id b nn >hostel.hostel
group_kind s nn {STATION_DROP|VACATION_DEPARTURE|FIELD_TRIP|MARKET_OUTING|EVENT}
title s nn
travel_mode s {TRAIN|BUS|SCHOOL_VEHICLE|FLIGHT|WALK}
carrier_ref s
station_or_stop s
campus_departure_at dt
carrier_departure_at dt
phone_release_at dt
escort_user_id b >U
vehicle_id b >transport.vehicle
status s nn {PLANNED|DEPARTED|COMPLETED|CANCELLED}

== hostel.outing_request
outing_id b pk
student_id b nn >academics.student
hostel_id b nn >hostel.hostel
policy_id b >hostel.outing_policy
group_id b >hostel.outing_group
outing_type s nn {LOCAL_OUTING|DAY_OUT|WEEKEND_HOME|HOME_LEAVE|VACATION|MEDICAL|EMERGENCY|OFFICIAL}
purpose s
destination s
depart_planned_at dt nn
return_planned_at dt nn
travel_mode s {SELF|PARENT_PICKUP|AUTHORISED_PICKUP|SCHOOL_VEHICLE|TRAIN|BUS|FLIGHT}
travel_ref s
travel_departure_at dt
pickup_person_id b >frontoffice.pickup_person
requested_by_kind s nn {PARENT|STUDENT|WARDEN}
requested_by_user_id b >U
parent_status s nn {NOT_REQUIRED|PENDING|APPROVED|DECLINED} =PENDING
parent_user_id b >U
parent_decided_at dt
warden_status s nn {PENDING|APPROVED|REJECTED}
warden_user_id b >U
warden_decided_at dt
confirmed_by_user_id b >U
release_custody_items bo =false
gate_pass_token s uk
status s nn {REQUESTED|APPROVED|REJECTED|CANCELLED|OUT|RETURNED|OVERDUE|CLOSED}
late_minutes i

== hostel.outing_movement
movement_id b pk
outing_id b nn >hostel.outing_request
direction s nn {OUT|IN}
moved_at dt nn =now()
gate_user_id b >U
roster_entry_id b >hr.roster_entry
verified_pickup_person_id b >frontoffice.pickup_person
verification s {QR|PARENT_OTP|PHOTO_ID|FACE}
punch_id b >operations.attendance_punch

== frontoffice.pickup_person
pickup_person_id b pk
student_id b nn >academics.student
name s nn
relationship s
phone s
photo_url s
id_proof_last4 s
added_by_user_id b >U
requires_parent_otp bo =true
valid_from d
valid_to d
is_active bo =true

== hostel.mess
mess_id b pk
hostel_id b >hostel.hostel
name s nn
vendor_id b >inventory.vendor
store_location_id b >inventory.location
capacity i

== hostel.mess_plan
plan_id b pk
mess_id b nn >hostel.mess
name s nn {VEG|NON_VEG|JAIN|CUSTOM}
meals_included s
fee_structure_id b >finance.fee_structure
rebate_after_days i
rebate_per_day n

== hostel.mess_subscription
subscription_id b pk
plan_id b nn >hostel.mess_plan
student_id b >academics.student
user_id b >U
from_date d nn
to_date d
status s nn {ACTIVE|PAUSED|ENDED}

== hostel.mess_menu
menu_id b pk
mess_id b nn >hostel.mess
day_of_week s {MON|TUE|WED|THU|FRI|SAT|SUN}
menu_date d
meal s nn {BREAKFAST|LUNCH|SNACKS|DINNER}
items s nn
is_special bo =false

== hostel.meal_attendance
meal_attendance_id b pk
mess_id b nn >hostel.mess
subscription_id b nn >hostel.mess_subscription
meal_date d nn
meal s nn {BREAKFAST|LUNCH|SNACKS|DINNER}
status s nn {TAKEN|SKIPPED|ON_LEAVE}
source s {SCAN|MANUAL}
@unique(subscription_id,meal_date,meal)

== hostel.mess_rebate
rebate_id b pk
subscription_id b nn >hostel.mess_subscription
outing_id b >hostel.outing_request
days i nn
amount n nn
credit_fee_id b >finance.fee

== hostel.mess_feedback
feedback_id b pk
mess_id b nn >hostel.mess
student_id b >academics.student
meal_date d nn
meal s {BREAKFAST|LUNCH|SNACKS|DINNER}
rating i nn
comment s

== custody.storage_unit
unit_id b pk
location_id b >inventory.location
hostel_id b >hostel.hostel
code s nn uk
unit_type s nn {LOCKER|TRAY|SAFE|SHELF}
capacity i
assigned_student_id b >academics.student
status s nn {ACTIVE|FULL|OUT_OF_SERVICE}

== custody.item
item_id b pk
student_id b nn >academics.student
item_type s nn {MOBILE_PHONE|LAPTOP|TABLET|SMARTWATCH|CHARGER|ID_DOCUMENT|JEWELLERY|OTHER}
brand s
model s
serial_last4 s
colour s
description s
photo_urls a
declared_value n
tag_code s uk
storage_unit_id b >custody.storage_unit
status s nn {IN_CUSTODY|RELEASED_TEMP|RELEASED_TRAVEL|WITH_PARENT|CONFISCATED|LOST|DAMAGED|CLOSED}
due_back_at dt
registered_by_user_id b >U
registered_at dt nn =now()

== custody.release_window
window_id b pk
hostel_id b nn >hostel.hostel
name s nn
day_of_week s nn {MON|TUE|WED|THU|FRI|SAT|SUN}
start_time tm nn
end_time tm nn
item_types s
min_level s
is_active bo =true

== custody.event
event_id b pk
item_id b nn >custody.item
event_type s nn {DEPOSIT|RELEASE|RETURN|MOVE_UNIT|CONFISCATE|HANDOVER_PARENT|INSPECT|MARK_LOST|MARK_DAMAGED|CLOSE}
release_reason s {TRAVEL_HOME|OUTING|CALL_HOUR|ONLINE_EXAM|MEDICAL|PARENT_COLLECT|LEAVING_SCHOOL}
outing_id b >hostel.outing_request
group_id b >hostel.outing_group
window_id b >custody.release_window
incident_id b >discipline.incident
from_unit_id b >custody.storage_unit
to_unit_id b >custody.storage_unit
performed_by_user_id b nn >U
counterparty_kind s {STUDENT|PARENT|PICKUP_PERSON}
counterparty_user_id b >U
counterparty_pickup_person_id b >frontoffice.pickup_person
verification s {QR|STUDENT_OTP|PARENT_OTP|SIGNATURE|FACE}
condition_note s
photo_url s
due_back_at dt
occurred_at dt nn =now()

== inventory.item_category
category_id b pk
parent_category_id b >inventory.item_category
name s nn

== inventory.vendor
vendor_id b pk
name s nn
gstin s
phone s
email s
address s
payment_terms_days i
rating i
is_active bo =true

== inventory.requisition
requisition_id b pk
requisition_number s nn uk
requested_by_user_id b >U
department_id b >academics.department
cost_centre s {SCHOOL|HOSTEL|MESS|TRANSPORT|DEPARTMENT}
hostel_id b >hostel.hostel
needed_by d
justification s
estimated_total n
status s nn {DRAFT|SUBMITTED|APPROVED|REJECTED|ORDERED|ISSUED_FROM_STOCK|CLOSED}

== inventory.requisition_line
line_id b pk
requisition_id b nn >inventory.requisition
item_catalog_id b nn >inventory.item_catalog
quantity n nn
estimated_unit_cost n

== inventory.purchase_order
po_id b pk
po_number s nn uk
vendor_id b nn >inventory.vendor
requisition_id b >inventory.requisition
order_date d
expected_date d
subtotal n
tax_amount n
total_amount n
status s nn {DRAFT|PENDING_APPROVAL|APPROVED|SENT|PARTIALLY_RECEIVED|RECEIVED|CANCELLED|CLOSED}
created_by_user_id b >U

== inventory.po_line
po_line_id b pk
po_id b nn >inventory.purchase_order
item_catalog_id b nn >inventory.item_catalog
quantity n nn
unit_price n nn
gst_rate n
received_qty n nn =0

== inventory.goods_receipt
grn_id b pk
grn_number s nn uk
po_id b nn >inventory.purchase_order
location_id b nn >inventory.location
received_by_user_id b >U
received_at dt nn =now()
vendor_challan_no s
status s nn {DRAFT|POSTED}

== inventory.grn_line
grn_line_id b pk
grn_id b nn >inventory.goods_receipt
po_line_id b >inventory.po_line
item_catalog_id b nn >inventory.item_catalog
received_qty n nn
accepted_qty n
rejected_qty n
unit_cost n
batch_no s
expiry_date d

== inventory.vendor_invoice
invoice_id b pk
vendor_id b nn >inventory.vendor
po_id b >inventory.purchase_order
invoice_number s nn uk:vendor_id
invoice_date d
amount n nn
tax_amount n
due_date d
match_status s {UNMATCHED|MATCHED|MISMATCH} =UNMATCHED
status s nn {RECEIVED|APPROVED|PAID|DISPUTED}
document_id b >records.document

== inventory.stock_audit
audit_id b pk
location_id b nn >inventory.location
audit_date d nn
conducted_by_user_id b >U
approved_by_user_id b >U
status s nn {IN_PROGRESS|SUBMITTED|APPROVED}

== inventory.stock_audit_line
line_id b pk
audit_id b nn >inventory.stock_audit
item_catalog_id b nn >inventory.item_catalog
asset_id b >inventory.asset_item
system_qty n
counted_qty n
variance_reason s
adjustment_txn_id b >inventory.inventory_transaction

== inventory.asset_maintenance
maintenance_id b pk
asset_id b nn >inventory.asset_item
kind s nn {PREVENTIVE|REPAIR|AMC_VISIT|CALIBRATION}
vendor_id b >inventory.vendor
ticket_id b >facility.ticket
reported_at dt
completed_at dt
cost n
expense_id b >accounts.expense

== accounts.expense_head
expense_head_id b pk
parent_head_id b >accounts.expense_head
code s nn uk
name s nn
gl_account_code s

== accounts.budget
budget_id b pk
academic_year_id b nn >academics.academic_year
expense_head_id b nn >accounts.expense_head
cost_centre s {SCHOOL|HOSTEL|MESS|TRANSPORT|DEPARTMENT}
hostel_id b >hostel.hostel
department_id b >academics.department
amount n nn
alert_at_pct n =80

== accounts.expense
expense_id b pk
voucher_number s nn uk
expense_head_id b nn >accounts.expense_head
cost_centre s
hostel_id b >hostel.hostel
department_id b >academics.department
vendor_id b >inventory.vendor
vendor_invoice_id b >inventory.vendor_invoice
payroll_run_id b >hr.payroll_run
expense_date d nn
amount n nn
tax_amount n
payment_mode s {BANK_TRANSFER|CHEQUE|UPI|CASH|CARD}
paid_from s {BANK|PETTY_CASH}
petty_cash_id b >accounts.petty_cash_account
reference_no s
description s
bill_document_id b >records.document
status s nn {DRAFT|SUBMITTED|APPROVED|REJECTED|PAID|CANCELLED}
submitted_by_user_id b >U
paid_at dt

== accounts.approval_rule
rule_id b pk
ref_kind s nn {EXPENSE|REQUISITION|PURCHASE_ORDER|REFUND|CONCESSION|PAYROLL}
cost_centre s
min_amount n
max_amount n
sequence i nn =1
approver_role_code s nn

== accounts.approval
approval_id b pk
ref_kind s nn
ref_id b nn
rule_id b >accounts.approval_rule
sequence i nn =1
approver_user_id b >U
decision s nn {PENDING|APPROVED|REJECTED|SENT_BACK}
note s
decided_at dt

== accounts.petty_cash_account
petty_cash_id b pk
name s nn
custodian_user_id b >U
cost_centre s
hostel_id b >hostel.hostel
float_limit n
balance n nn =0

== accounts.petty_cash_txn
txn_id b pk
petty_cash_id b nn >accounts.petty_cash_account
txn_type s nn {TOP_UP|SPEND|RETURN|SETTLEMENT}
amount n nn
expense_id b >accounts.expense
performed_by_user_id b >U
txn_at dt nn =now()

== accounts.other_income
income_id b pk
income_type s nn {DONATION|RENT|CANTEEN|SCRAP_SALE|GRANT|OTHER}
amount n nn
received_on d nn
payer s
mode s
document_id b >records.document
recorded_by_user_id b >U

== hr.employee_profile
user_id b pkc >U
employee_code s uk
staff_category s {TEACHING|NON_TEACHING|SECURITY|HOSTEL|TRANSPORT|CONTRACT}
department_id b >academics.department
designation s
employment_type s {PERMANENT|PROBATION|CONTRACT|PART_TIME|GUEST|OUTSOURCED}
reporting_manager_user_id b >U
date_of_joining d
date_of_leaving d
pf_uan s
esi_number s
vault_ref s
police_verification_on d
status s nn {ACTIVE|ON_NOTICE|LEFT}

== hr.shift
shift_id b pk
code s nn uk
name s nn
start_time tm nn
end_time tm nn
crosses_midnight bo =false
grace_minutes i =10
break_minutes i
half_day_after_minutes i
min_work_minutes i
overtime_after_minutes i
night_allowance n
applies_to s {TEACHING|NON_TEACHING|SECURITY|HOSTEL|TRANSPORT|ANY} =ANY

== hr.shift_assignment
shift_assignment_id b pk
user_id b nn >U
shift_id b nn >hr.shift
weekdays s
weekly_off s
from_date d nn
to_date d
rotation s {FIXED|WEEKLY|FORTNIGHTLY} =FIXED

== hr.post
post_id b pk
code s nn uk
post_type s nn {GATE|PATROL|CCTV|HOSTEL_NIGHT|HOSTEL_DAY|MESS|EXAM|FRONT_DESK|LIBRARY_COUNTER|SICK_BAY|OTHER}
location_id b >inventory.location
hostel_id b >hostel.hostel
required_per_shift i =1
device_id b

== hr.roster_entry
roster_entry_id b pk
user_id b nn >U
shift_id b nn >hr.shift
post_id b >hr.post
duty_date d nn
status s nn {PLANNED|ON_DUTY|COMPLETED|ABSENT|SWAPPED|CANCELLED}
swapped_with_user_id b >U
approved_by_user_id b >U
reported_at dt

== operations.attendance_punch
punch_id b pk
person_kind s nn {STUDENT|STAFF|VISITOR}
person_id b nn
source s nn {FINGERPRINT|FACE|RFID|QR|MANUAL|APP_GEOFENCE_OFF}
direction s nn {IN|OUT}
punched_at dt nn =now()
device_id b
post_id b >hr.post
marked_by_user_id b >U

== operations.daily_presence
presence_id b pk
person_kind s nn {STUDENT|STAFF}
person_id b nn
presence_date d nn
shift_id b >hr.shift
roster_entry_id b >hr.roster_entry
first_in_at dt
last_out_at dt
on_campus_minutes i
late_minutes i
early_leave_minutes i
overtime_minutes i
status s nn {PRESENT|LATE|HALF_DAY|ABSENT|ON_LEAVE|ON_DUTY|WEEKLY_OFF|HOLIDAY|ON_OUTING}
computed_by s {SYSTEM|MANUAL} =SYSTEM
corrected_by_user_id b >U
recomputed_at dt
@unique(person_kind,person_id,presence_date)

== hr.leave_type
leave_type_id b pk
code s nn uk
name s nn
annual_quota n
carry_forward_max n
is_paid bo =true
document_after_days i
applies_to s

== hr.leave_balance
user_id b pkc >U
leave_type_id b pkc >hr.leave_type
academic_year_id b pkc >academics.academic_year
opening n =0
accrued n =0
used n =0
balance n =0

== hr.leave_request
leave_request_id b pk
user_id b nn >U
leave_type_id b nn >hr.leave_type
from_date d nn
to_date d nn
half_day bo =false
days n
reason s
document_id b >records.document
status s nn {PENDING|APPROVED|REJECTED|CANCELLED}
approver_user_id b >U
decided_at dt

== hr.salary_component
component_id b pk
code s nn uk
kind s nn {EARNING|DEDUCTION|EMPLOYER_CONTRIBUTION}
calc s nn {FIXED|PERCENT_OF_BASIC|PER_DAY|PER_HOUR|FORMULA}
formula s

== hr.salary_structure
structure_id b pk
user_id b nn >U
effective_from d nn
ctc_annual n

== hr.salary_structure_line
line_id b pk
structure_id b nn >hr.salary_structure
component_id b nn >hr.salary_component
amount_or_pct n nn

== hr.payroll_run
run_id b pk
period s nn uk
status s nn {DRAFT|COMPUTED|APPROVED|PAID|LOCKED}
computed_by_user_id b >U
approved_by_user_id b >U
paid_at dt

== hr.payslip
payslip_id b pk
run_id b nn >hr.payroll_run
user_id b nn >U
working_days n
present_days n
lop_days n
overtime_minutes i
night_shifts i
gross n
deductions n
net n
document_id b >records.document
@unique(run_id,user_id)

== hr.payslip_line
line_id b pk
payslip_id b nn >hr.payslip
component_id b nn >hr.salary_component
amount n nn

== security.checkpoint
checkpoint_id b pk
code s nn uk
name s nn
location_id b >inventory.location
tag_uid s uk
lat n
lng n

== security.patrol_route
route_id b pk
post_id b >hr.post
name s nn
active_from tm
active_to tm
round_every_minutes i
max_round_minutes i

== security.route_checkpoint
route_id b nn >security.patrol_route
checkpoint_id b nn >security.checkpoint
sequence i nn
photo_required bo =false
@key(route_id,checkpoint_id)

== security.patrol_round
round_id b pk
route_id b nn >security.patrol_route
roster_entry_id b >hr.roster_entry
guard_user_id b >U
due_at dt nn
started_at dt
completed_at dt
missed_checkpoints i
status s nn {DUE|IN_PROGRESS|COMPLETED|LATE|MISSED}

== security.patrol_scan
scan_id b pk
round_id b nn >security.patrol_round
checkpoint_id b nn >security.checkpoint
scanned_at dt nn =now()
lat n
lng n
method s {NFC|QR|MANUAL_WITH_REASON}
photo_url s
note s

== security.welfare_ping
ping_id b pk
roster_entry_id b nn >hr.roster_entry
sent_at dt nn =now()
responded_at dt
status s {OK|NO_RESPONSE|ESCALATED}

== security.occurrence
occurrence_id b pk
occurrence_type s nn {INTRUDER|FIRE_ALARM|POWER_CUT|MEDICAL|SUSPICIOUS_VEHICLE|GATE_BREACH|ANIMAL|THEFT|OTHER}
severity s nn {LOW|MEDIUM|HIGH|CRITICAL}
occurred_at dt nn =now()
location_id b >inventory.location
checkpoint_id b >security.checkpoint
description s
photo_urls a
reported_by_user_id b >U
roster_entry_id b >hr.roster_entry
escalated_to_user_id b >U
ticket_id b >facility.ticket
incident_id b >discipline.incident
status s nn {OPEN|ACKNOWLEDGED|RESOLVED}

== security.shift_handover
handover_id b pk
post_id b nn >hr.post
from_roster_entry_id b >hr.roster_entry
to_roster_entry_id b >hr.roster_entry
handed_over_at dt nn =now()
notes s
equipment s
accepted bo =false

== security.key
key_id b pk
code s nn uk
location_id b >inventory.location
is_master bo =false

== security.key_movement
key_movement_id b pk
key_id b nn >security.key
issued_to_user_id b >U
issued_by_user_id b >U
issued_at dt nn =now()
due_back_at dt
returned_at dt

== security.vehicle_entry
vehicle_entry_id b pk
post_id b >hr.post
vehicle_number s nn
purpose s {VENDOR|PARENT|STAFF|DELIVERY|OTHER}
visit_id b >frontoffice.visit
in_at dt nn =now()
out_at dt
logged_by_user_id b >U

== transport.vehicle
vehicle_id b pk
registration_number s nn uk
vehicle_type s {BUS|VAN|CAR}
capacity i
gps_device_id s
insurance_valid_till d
fitness_valid_till d
permit_valid_till d
puc_valid_till d
asset_id b >inventory.asset_item
status s nn {ACTIVE|IN_REPAIR|RETIRED}

== transport.route
route_id b pk
code s nn uk
name s nn
shift s {MORNING|AFTERNOON|BOTH}
vehicle_id b >transport.vehicle
driver_user_id b >U
attendant_user_id b >U

== transport.stop
stop_id b pk
route_id b nn >transport.route
name s nn
lat n
lng n
sequence i
pickup_time tm
drop_time tm
fee_structure_id b >finance.fee_structure

== transport.student_route
student_id b nn >academics.student
route_id b nn >transport.route
pickup_stop_id b >transport.stop
drop_stop_id b >transport.stop
from_date d nn
to_date d
status s nn {ACTIVE|ENDED}
@key(student_id,route_id,from_date)

== transport.trip
trip_id b pk
route_id b nn >transport.route
vehicle_id b >transport.vehicle
driver_user_id b >U
roster_entry_id b >hr.roster_entry
trip_date d nn
direction s nn {PICKUP|DROP|HOSTEL_STATION_DROP}
group_id b >hostel.outing_group
started_at dt
ended_at dt
status s nn {PLANNED|RUNNING|COMPLETED|CANCELLED}

== transport.trip_location
trip_id b nn >transport.trip
recorded_at dt nn
lat n nn
lng n nn
speed_kmph n
@key(trip_id,recorded_at)

== transport.boarding
boarding_id b pk
trip_id b nn >transport.trip
student_id b nn >academics.student
stop_id b >transport.stop
event s nn {BOARDED|ALIGHTED|NO_SHOW}
event_at dt nn =now()
source s {RFID|QR|MANUAL}
marked_by_user_id b >U

== transport.fuel_log
fuel_log_id b pk
vehicle_id b nn >transport.vehicle
filled_on d nn
litres n
amount n
odometer_km i
expense_id b >accounts.expense

== communication.conversation
conversation_id b pk
kind s nn {PARENT_TEACHER|CLASS_GROUP|HOSTEL_GROUP|HELPDESK}
student_id b >academics.student
class_section_id b >academics.class_section
hostel_id b >hostel.hostel
created_by_user_id b >U
parents_can_reply bo =true
is_locked bo =false
created_at dt nn =now()

== communication.conversation_member
conversation_id b nn >communication.conversation
user_id b nn >U
member_role s nn {STAFF|PARENT|STUDENT|MODERATOR}
last_read_at dt
muted bo =false
@key(conversation_id,user_id)

== communication.message
message_id b pk
conversation_id b nn >communication.conversation
sender_user_id b nn >U
body s
attachment_urls a
sent_at dt nn =now()
deleted_at dt
flagged bo =false

== communication.messaging_policy
parent_can_start_chat bo =true
office_hours_start tm
office_hours_end tm
show_staff_phone bo =false
retention_days i
@pkschool

== communication.template ?tenant
template_id b pk
event_code s nn {FEE_DUE|ABSENT|LATE_ARRIVAL|OUTING_APPROVED|LATE_RETURN|PHONE_RELEASED|PHONE_DEPOSITED|MISSING_AT_ROLL_CALL|BUS_NEAR}
channel s nn {WHATSAPP|EMAIL|PUSH}
language s nn =en
whatsapp_template_name s
body s nn

== communication.poll
poll_id b pk
notification_id b >communication.notification
question s nn
options j nn
is_anonymous bo =false
one_per_child bo =false
closes_at dt

== communication.poll_response
poll_id b nn >communication.poll
user_id b nn >U
student_id b >academics.student
option_key s nn
responded_at dt nn =now()
@key(poll_id,user_id,student_id)

== communication.ptm_session
ptm_id b pk
event_id b >calendar.event
class_section_id b >academics.class_section
slot_minutes i
mode s {IN_PERSON|VIDEO}

== communication.ptm_slot
slot_id b pk
ptm_id b nn >communication.ptm_session
teacher_user_id b nn >U
start_at dt nn
booked_by_user_id b >U
student_id b >academics.student
status s nn {OPEN|BOOKED|DONE|NO_SHOW|CANCELLED}
teacher_notes s

== operations.student_leave_request
request_id b pk
student_id b nn >academics.student
from_date d nn
to_date d nn
reason s
document_id b >records.document
requested_by_user_id b >U
status s nn {PENDING|APPROVED|REJECTED|CANCELLED}
decided_by_user_id b >U

== frontoffice.visitor
visitor_id b pk
name s nn
phone s
photo_url s
id_proof_type s
id_proof_last4 s
is_blacklisted bo =false

== frontoffice.visit
visit_id b pk
visitor_id b nn >frontoffice.visitor
purpose s {PARENT_MEETING|ADMISSION|VENDOR|INTERVIEW|HOSTEL_VISIT|OFFICIAL|OTHER}
host_user_id b >U
student_id b >academics.student
pickup_person_id b >frontoffice.pickup_person
approved_by_user_id b >U
badge_number s
check_in_at dt nn =now()
check_out_at dt

== frontoffice.gate_pass
gate_pass_id b pk
student_id b nn >academics.student
reason s
requested_by_user_id b >U
approved_by_user_id b >U
pickup_person_id b >frontoffice.pickup_person
verification s {PARENT_OTP|PHOTO_ID}
out_at dt
verified_by_user_id b >U

== frontoffice.parcel
parcel_id b pk
direction s nn {IN|OUT}
for_student_id b >academics.student
for_user_id b >U
courier s
tracking_number s
opened_before_warden bo =false
received_at dt nn =now()
handed_over_at dt
handed_over_by_user_id b >U

== facility.ticket
ticket_id b pk
category s nn {ELECTRICAL|PLUMBING|CARPENTRY|CLEANING|IT|MESS|SECURITY|ROOMMATE|OTHER}
location_id b >inventory.location
room_id b >hostel.room
asset_id b >inventory.asset_item
raised_by_user_id b >U
raised_for_student_id b >academics.student
description s nn
photo_urls a
priority s {LOW|MEDIUM|HIGH|URGENT} =MEDIUM
assigned_to_user_id b >U
sla_due_at dt
status s nn {OPEN|ASSIGNED|IN_PROGRESS|RESOLVED|CLOSED|REOPENED}
resolved_at dt
resolution_note s
expense_id b >accounts.expense

== wellbeing.medical_profile
student_id b pkc >academics.student
blood_group s
allergies s
conditions s
regular_medicines s
dietary_restrictions s
doctor_name s
doctor_phone s
insurance_ref s
updated_by_user_id b >U
updated_at dt

== wellbeing.vaccination
vaccination_id b pk
student_id b nn >academics.student
vaccine s nn
dose i
given_on d
document_id b >records.document

== wellbeing.health_checkup
checkup_id b pk
student_id b nn >academics.student
checkup_date d nn
height_cm n
weight_kg n
vision s
dental s
notes s
conducted_by_user_id b >U

== wellbeing.infirmary_visit
visit_id b pk
person_kind s nn {STUDENT|STAFF}
person_id b nn
visited_at dt nn =now()
complaint s
vitals j
treatment s
attended_by_user_id b >U
disposition s {BACK_TO_CLASS|SICK_BAY|SENT_HOME|HOSPITAL_REFERRAL}
parent_notified_at dt
discharged_at dt

== wellbeing.medication_schedule
schedule_id b pk
student_id b nn >academics.student
medicine s nn
dose s
times s
from_date d nn
to_date d
prescription_document_id b >records.document
stock_item_catalog_id b >inventory.item_catalog

== wellbeing.medication_dose
dose_id b pk
schedule_id b nn >wellbeing.medication_schedule
due_at dt nn
given_at dt
given_by_user_id b >U
status s {GIVEN|MISSED|REFUSED}

== discipline.incident
incident_id b pk
occurred_at dt nn
location_id b >inventory.location
hostel_id b >hostel.hostel
category s nn {BULLYING|CONTRABAND|MISSING|LATE_RETURN|DAMAGE|FIGHT|ACADEMIC|OTHER}
severity s nn {MINOR|MODERATE|MAJOR|CRITICAL}
description s
reported_by_user_id b >U
status s nn {REPORTED|UNDER_REVIEW|ACTION_TAKEN|CLOSED|APPEALED}

== discipline.incident_student
incident_id b nn >discipline.incident
student_id b nn >academics.student
involvement s nn {PRIMARY|INVOLVED|WITNESS|AFFECTED}
@key(incident_id,student_id)

== discipline.action
action_id b pk
incident_id b nn >discipline.incident
student_id b nn >academics.student
action_type s nn {WARNING|PARENT_MEETING|DETENTION|OUTING_BAN|PHONE_CONFISCATION|SUSPENSION|FINE|COUNSELLING}
from_date d
to_date d
fine_fee_id b >finance.fee
decided_by_user_id b >U
parent_notified_at dt

== learning.syllabus
syllabus_id b pk
program_id b >academics.program
subject_id b nn >academics.subject
academic_year_id b >academics.academic_year
board s

== learning.syllabus_unit
unit_id b pk
syllabus_id b nn >learning.syllabus
parent_unit_id b >learning.syllabus_unit
title s nn
sequence i
planned_periods i
term_id b >academics.academic_term

== learning.lesson_plan
plan_id b pk
staff_subject_id b nn >academics.staff_subject
class_section_id b nn >academics.class_section
unit_id b >learning.syllabus_unit
planned_date d
objectives s
activities s
resources s
status s nn {PLANNED|DELIVERED|PARTIAL|SKIPPED}
delivered_on d
timetable_id b >academics.timetable
reviewed_by_user_id b >U

== learning.content
content_id b pk
subject_id b >academics.subject
unit_id b >learning.syllabus_unit
title s nn
kind s nn {VIDEO|PDF|LINK|SLIDES|AUDIO}
url s nn
visibility s {STAFF|SECTION|PROGRAM|ALL} =SECTION
uploaded_by_user_id b >U

== operations.homework_submission
submission_id b pk
homework_id b nn >operations.homework
student_id b nn >academics.student
submitted_at dt
text_answer s
attachment_urls a
status s nn {SUBMITTED|LATE|RETURNED|GRADED}
marks n
feedback s
graded_by_user_id b >U
@unique(homework_id,student_id)

== learning.question
question_id b pk
subject_id b >academics.subject
unit_id b >learning.syllabus_unit
question_type s nn {MCQ|MSQ|NUMERIC|SHORT|LONG}
body s nn
options j
answer j
marks n
difficulty s {EASY|MEDIUM|HARD}
created_by_user_id b >U

== learning.quiz
quiz_id b pk
staff_subject_id b >academics.staff_subject
class_section_id b >academics.class_section
title s nn
opens_at dt
closes_at dt
duration_minutes i
max_marks n
shuffle bo =false

== learning.quiz_question
quiz_id b nn >learning.quiz
question_id b nn >learning.question
sequence i
@key(quiz_id,question_id)

== learning.quiz_attempt
attempt_id b pk
quiz_id b nn >learning.quiz
student_id b nn >academics.student
started_at dt
submitted_at dt
answers j
score n

== academics.timetable_version
timetable_version_id b pk
academic_year_id b >academics.academic_year
term_id b >academics.academic_term
status s nn {DRAFT|GENERATED|PUBLISHED|ARCHIVED}
generated_at dt
published_by_user_id b >U

== academics.timetable_constraint
constraint_id b pk
timetable_version_id b >academics.timetable_version
kind s nn {TEACHER_UNAVAILABLE|TEACHER_MAX_PER_DAY|SUBJECT_PERIODS_PER_WEEK|CONSECUTIVE_REQUIRED|ROOM_REQUIRED|NOT_LAST_PERIOD|WITHIN_SHIFT}
user_id b >U
subject_id b >academics.subject
class_section_id b >academics.class_section
room_location_id b >inventory.location
value j
weight s {HARD|SOFT} =HARD

== assessment.exam_session
exam_session_id b pk
term_id b >academics.academic_term
name s nn
start_date d
end_date d
block_on_dues bo =false
status s nn {DRAFT|PUBLISHED|IN_PROGRESS|RESULTS_PUBLISHED}

== assessment.hall_ticket
hall_ticket_id b pk
exam_session_id b nn >assessment.exam_session
student_id b nn >academics.student
ticket_number s nn uk
is_blocked bo =false
blocked_reason s
document_id b >records.document

== assessment.seating
seating_id b pk
exam_id b nn >assessment.exams
student_id b nn >academics.student
room_location_id b >inventory.location
seat_label s

== assessment.invigilation_duty
duty_id b pk
exam_id b nn >assessment.exams
room_location_id b >inventory.location
user_id b nn >U
duty_role s {CHIEF|INVIGILATOR|RELIEVER|SQUAD}

== assessment.co_scholastic_area
area_id b pk
name s nn
grade_scale_id b >assessment.grade_scale

== assessment.co_scholastic_grade
id b pk
student_id b nn >academics.student
term_id b nn >academics.academic_term
area_id b nn >assessment.co_scholastic_area
grade_id b >assessment.grade
remark s
entered_by_user_id b >U

== assessment.report_card_template
template_id b pk
program_id b >academics.program
board s
layout j
version i =1

== assessment.report_card
report_card_id b pk
student_id b nn >academics.student
term_id b nn >academics.academic_term
template_id b >assessment.report_card_template
attendance_pct n
teacher_remark s
principal_remark s
status s nn {DRAFT|APPROVED|PUBLISHED|WITHHELD}
withheld_reason s
published_at dt
document_id b >records.document

== records.document
document_id b pk
owner_kind s nn {STUDENT|STAFF|APPLICATION|VENDOR|EXPENSE|ASSET|INCIDENT|OUTING|CUSTODY_ITEM}
owner_id b nn
doc_type s nn {BIRTH_CERT|PREVIOUS_TC|PHOTO|ADDRESS_PROOF|MEDICAL|BILL|INVOICE|PAYSLIP|REPORT_CARD|CERTIFICATE|OTHER}
file_url s nn
mime_type s
size_bytes b
sha256 s
is_sensitive bo =false
uploaded_by_user_id b >U
uploaded_at dt nn =now()
verified_by_user_id b >U
expires_on d

== records.certificate_template
template_id b pk
cert_type s nn {TC|BONAFIDE|CHARACTER|STUDY|MIGRATION|FEE_PAID|CUSTOM}
body_template s nn
version i =1

== records.certificate
certificate_id b pk
student_id b nn >academics.student
template_id b >records.certificate_template
serial_number s nn uk
verification_code s nn uk
reason s
issued_on d
issued_by_user_id b >U
document_id b >records.document
revoked_at dt

== records.clearance
clearance_id b pk
student_id b nn >academics.student
purpose s nn {TC|HOSTEL_VACATE|YEAR_END}
department s nn {FEES|LIBRARY|HOSTEL|CUSTODY|INVENTORY|TRANSPORT|LAB}
status s nn {PENDING|CLEARED|BLOCKED}
blocking_note s
cleared_by_user_id b >U
cleared_at dt

== records.id_card
card_id b pk
holder_kind s nn {STUDENT|STAFF}
holder_id b nn
card_number s nn uk
qr_token s uk
rfid_uid s uk
issued_on d
valid_till d
status s nn {ACTIVE|LOST|REPLACED|REVOKED}

== compliance.consent_form
form_id b pk
feature_code s nn
version i nn =1
title s nn
purpose s
data_used a
shared_with s
retention s
if_declined s
signer_parent bo =true
signer_staff bo =false
signer_student bo =false
is_required bo =false
published_at dt
published_by_user_id b >U
@unique(feature_code,version)

== compliance.consent_record
record_id b pk
form_id b nn >compliance.consent_form
form_version i nn
subject_kind s nn {STUDENT|STAFF}
subject_id b nn
signer_user_id b >U
decision s nn {GRANTED|DECLINED|WITHDRAWN}
method s {IN_APP|PAPER} =IN_APP
decided_at dt nn =now()
recorded_by_user_id b >U

== platform.import_job
import_job_id b pk
entity s nn {STUDENT|PARENT|STAFF|SECTION|SUBJECT|FEE_DUE|MARKS|BOOK|INVENTORY_ITEM|HOSTEL_ROOM|TRANSPORT_STOP}
source_document_id b >records.document
column_mapping j
dry_run bo =true
status s nn {UPLOADED|VALIDATING|VALIDATED|IMPORTING|COMPLETED|FAILED}
total_rows i
ok_rows i
error_rows i
error_report_document_id b >records.document
requested_by_user_id b >U
created_at dt nn =now()

== platform.export_job
export_job_id b pk
kind s nn {UDISE|APAAR|BOARD_REGISTRATION|TALLY|SAVED_REPORT|PAYROLL_BANK_FILE}
params j
status s nn {QUEUED|RUNNING|DONE|FAILED}
file_document_id b >records.document
requested_by_user_id b >U
created_at dt nn =now()

== platform.saved_report ?tenant
report_id b pk
organization_id b
name s nn
base_entity s nn
columns j
filters j
schedule_cron s
recipient_user_ids a
created_by_user_id b >U

== audit.audit_log
audit_id b pk
table_name s nn
row_pk s
action s nn {INSERT|UPDATE|DELETE}
before_data j
after_data j
changed_by_user_id b >U
via s {APP|IMPORT|SYSTEM|DEVICE}
request_id s
ip_address s
changed_at dt nn =now()

== alumni.profile
student_id b pkc >academics.student
passing_year i
higher_education s
current_organization s
city s
contact_consent bo =false

== placement.company
company_id b pk
name s nn
sector s
contact_email s

== placement.drive
drive_id b pk
company_id b nn >placement.company
role_title s nn
ctc_lpa n
eligibility j
drive_date d
status s nn {OPEN|CLOSED|COMPLETED}

== placement.application
application_id b pk
drive_id b nn >placement.drive
student_id b nn >academics.student
stage s nn {APPLIED|SHORTLISTED|INTERVIEW|OFFERED|REJECTED|ACCEPTED}
offered_ctc_lpa n

== store.sale
sale_id b pk
location_id b >inventory.location
student_id b >academics.student
wallet_txn_id b >finance.wallet_txn
payment_id b >finance.payment
total n nn
sold_by_user_id b >U
sold_at dt nn =now()

== store.sale_line
line_id b pk
sale_id b nn >store.sale
item_catalog_id b nn >inventory.item_catalog
quantity n nn
unit_price n nn

== hr.job_opening
opening_id b pk
title s nn
department_id b >academics.department
positions i =1
status s nn {OPEN|ON_HOLD|CLOSED}

== hr.candidate
candidate_id b pk
opening_id b nn >hr.job_opening
name s nn
phone s
email s
resume_document_id b >records.document
stage s nn {APPLIED|SCREENED|DEMO_CLASS|INTERVIEW|OFFERED|JOINED|REJECTED}

# ---------------------------------------------------------------- additions (Schema v5 / C4 v1)

== communication.news_post +
post_id b pk
author_user_id b nn >U
title s
body s
audience_type s nn {ALL|SECTION|PROGRAM|HOSTEL|STAFF} =ALL
class_section_id b >academics.class_section
program_id b >academics.program
hostel_id b >hostel.hostel
is_pinned bo =false
created_at dt nn =now()
expires_at dt nn =now()+30d
deleted_at dt

== communication.news_media +
media_id b pk
post_id b nn >communication.news_post
provider s nn {DRIVE|DROPBOX|LOCAL}
file_id s nn
mime_type s nn
size_bytes b nn
width i
height i
duration_seconds i
sort_order i =0
purged_at dt

== communication.news_reaction +
post_id b nn >communication.news_post
user_id b nn >U
reaction s nn {LIKE|LOVE|CLAP|CELEBRATE}
reacted_at dt nn =now()
@key(post_id,user_id)

== platform.idempotency_key +
idempotency_key s nn
user_id b nn >U
request_hash s nn
response_status i
response_body j
created_at dt nn =now()
@key(idempotency_key)

== platform.outbox_event +
event_id b pk
event_type s nn
channel s nn {PUSH|WHATSAPP|EMAIL|INTERNAL}
recipient_user_id b >U
payload j nn
status s nn {PENDING|SENT|FAILED|DEAD}
attempts i nn =0
next_attempt_at dt nn =now()
created_at dt nn =now()
sent_at dt
last_error s

== platform.flow_definition + ?tenant
flow_id b pk
flow_code s nn
version i nn =1
name s nn
definition j nn
is_active bo =true
created_at dt nn =now()
@unique(flow_code,version)

== platform.flow_instance +
instance_id b pk
flow_id b nn >platform.flow_definition
ref_kind s nn
ref_id b nn
current_step s nn
status s nn {OPEN|APPROVED|REJECTED|CANCELLED|SENT_BACK}
submitted_by_user_id b >U
amount n
due_by dt
created_at dt nn =now()
closed_at dt

== platform.flow_transition_log +
log_id b pk
instance_id b nn >platform.flow_instance
from_step s
to_step s nn
action s nn {SUBMIT|APPROVE|REJECT|SEND_BACK|ESCALATE|CANCEL|AUTO}
actor_user_id b >U
actor_role_code s
note s
occurred_at dt nn =now()
