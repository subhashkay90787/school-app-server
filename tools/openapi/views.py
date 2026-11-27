"""View models: what screens need that isn't a single table row (Role-based UX v2)."""


def define(r):
    v = r.view
    # ------------------------------------------------------------ shared patterns
    v("HomeCard", {"id": "s", "section": "{CRITICAL|NEEDS_YOU|NOW|TODAY|FEED}", "kind": "s", "title": "s",
                   "subtitle": "s", "count": "i", "severity": "{INFO|ACTION|URGENT|CRITICAL}", "dueAt": "dt",
                   "roleTag": "s", "deepLink": "s", "payload": "j"},
      "One home card; cards with nothing in them are not returned", required=["id", "section", "kind", "title"])
    v("HomeFeed", {"generatedAt": "dt", "role": "s", "cards": "[HomeCard]", "allCaughtUp": "bo", "nextScheduled": "HomeCard"},
      "Home in card order: Critical -> Needs you -> Now -> Today -> Feed (UX v2 section 3)")
    v("Kpi", {"code": "s", "label": "s", "value": "n", "unit": "s", "delta": "n", "target": "n", "trend": "[n]"})
    v("Dashboard", {"asOf": "dt", "scope": "{BRANCH|ALL_BRANCHES}", "kpis": "[Kpi]", "branches": "[BranchKpis]"})
    v("BranchKpis", {"schoolId": "b", "branchName": "s", "kpis": "[Kpi]"})
    v("PolicyCheck", {"code": "s", "label": "s", "passed": "bo", "detail": "s"})
    v("ApprovalStep", {"sequence": "i", "approverRoleCode": "s", "approverName": "s",
                       "decision": "{PENDING|APPROVED|REJECTED|SENT_BACK}", "note": "s", "decidedAt": "dt"})
    v("ApprovalItem", {"flowInstanceId": "b", "kind": "s", "refId": "b", "title": "s", "requestedBy": "PersonRef",
                       "amount": "n", "fromDate": "d", "toDate": "d", "dueBy": "dt",
                       "urgency": "{SAFETY|MONEY|OTHER}", "checks": "[PolicyCheck]", "history": "[ApprovalStep]",
                       "status": "{OPEN|APPROVED|REJECTED|CANCELLED|SENT_BACK}", "waitingFor": "s",
                       "aboveYourBand": "bo", "forwardedTo": "s"},
      "Approvals inbox card (UX v2 4.1); your own requests never appear here")
    v("DecisionRequest", {"decision": "{APPROVE|REJECT|SEND_BACK}", "note": "s"},
      "Reject and send back need a note", required=["decision"])
    v("BulkDecisionRequest", {"flowInstanceIds": "[b]", "note": "s"}, required=["flowInstanceIds"])
    v("BulkResult", {"requested": "i", "succeeded": "i", "failed": "i", "errors": "[RowError]"})
    v("RowError", {"row": "i", "refId": "b", "code": "s", "message": "s"})
    v("PersonRef", {"userId": "b", "studentId": "b", "name": "s", "photoUrl": "s", "label": "s"})
    v("IdList", {"ids": "[b]"}, required=["ids"])
    v("ReasonInput", {"reason": "s"}, required=["reason"])
    v("FileRef", {"documentId": "b", "url": "s", "mimeType": "s", "sizeBytes": "b"})
    v("ScanRequest", {"code": "s", "context": "{GATE|CUSTODY|LIBRARY|STORE|PATROL|MESS|BOARDING|ANY}", "scannedAt": "dt"},
      required=["code"])
    v("ScanAction", {"action": "s", "label": "s", "requiresPin": "bo"})
    v("ScanResult", {"codeType": "{GATE_PASS|ID_CARD|CUSTODY_TAG|BOOK_COPY|ASSET|STOCK_ITEM|CHECKPOINT|MESS_CARD|BUS_BOARDING|UNKNOWN}",
                     "verdict": "{ALLOWED|STOP|UNVERIFIED|INFO}", "headline": "s", "reason": "s", "person": "PersonRef",
                     "refId": "b", "actions": "[ScanAction]", "clearAfterSeconds": "i"},
      "Scan hub result (UX v2 4.2): colour + icon + word; STOP shows a 3-word reason")
    v("SearchHit", {"kind": "{STUDENT|STAFF|RECEIPT|SCREEN|CLASS}", "id": "b", "title": "s", "subtitle": "s", "deepLink": "s"})
    v("NavEntry", {"key": "s", "label": "s", "icon": "s", "feature": "s", "locked": "bo", "lockReason": "s",
                   "group": "s", "children": "[NavEntry]"})
    v("Navigation", {"roleCode": "s", "baseRoleCode": "s", "mobileTabs": "[NavEntry]", "webSidebar": "[NavEntry]",
                     "duties": "[Duty]"},
      "Navigation = token.features ∩ role permissions, plus duty entries (UX v2 section 3)")
    v("Duty", {"kind": "{CLASS_TEACHER|SUBJECT_TEACHER|INVIGILATOR|ESCORT|ROOM_WARDEN|BLOCK_WARDEN|FLOOR_WARDEN|NIGHT_WARDEN|ASSISTANT_WARDEN}",
               "refId": "b", "label": "s", "from": "dt", "to": "dt"})
    v("SchoolContext", {"schoolId": "b", "schoolName": "s", "branchName": "s", "organizationId": "b",
                        "institutionType": "s", "timezone": "s", "terminology": "j", "roles": "[s]", "baseRoles": "[s]",
                        "permissions": "[s]", "features": "[s]", "orgWide": "bo", "permVersion": "b"})
    v("MeContext", {"userId": "b", "firstName": "s", "lastName": "s", "userCategory": "s", "currentSchoolId": "b",
                    "schools": "[SchoolContext]", "pendingConsents": "i", "unreadInbox": "i"})
    v("ProfileView", {"userId": "b", "firstName": "s", "lastName": "s", "email": "s", "phoneNumber": "s",
                      "userCategory": "s", "photoUrl": "s", "school": "SchoolContext",
                      "employee": "E:hr.employee_profile", "teacher": "E:hr.teacher_metadata",
                      "children": "[ChildSummary]", "student": "E:academics.student", "duties": "[Duty]"},
      "Name, phone and email are owned by school-auth (edit them at PATCH /api/v1/users/me on the auth server)")
    v("InboxItem", {"notificationId": "b", "title": "s", "body": "s", "category": "s",
                    "severity": "{INFO|ACTION|URGENT|CRITICAL}", "roleTag": "s", "student": "PersonRef",
                    "sentAt": "dt", "readAt": "dt", "requiresAck": "bo", "acknowledgedAt": "dt", "deepLink": "s",
                    "attachmentUrls": "[s]"})
    v("EscalationStep", {"step": "i", "label": "s", "person": "PersonRef", "notifiedAt": "dt", "acknowledgedAt": "dt"})
    v("CriticalAlert", {"notificationId": "b", "title": "s", "body": "s", "student": "PersonRef", "raisedAt": "dt",
                        "ladder": "[EscalationStep]"})
    v("NewsPostView", {"postId": "b", "author": "PersonRef", "title": "s", "body": "s", "createdAt": "dt",
                       "expiresAt": "dt", "pinned": "bo", "media": "[NewsMediaView]", "reactions": "j", "myReaction": "s"})
    v("NewsMediaView", {"mediaId": "b", "mimeType": "s", "width": "i", "height": "i", "durationSeconds": "i",
                        "streamUrl": "s"})
    v("NewsPostInput", {"title": "s", "body": "s", "audienceType": "{ALL|SECTION|PROGRAM|HOSTEL|STAFF}",
                        "classSectionId": "b", "programId": "b", "hostelId": "b", "pinned": "bo"}, required=["audienceType"])
    v("ReactionInput", {"reaction": "{LIKE|LOVE|CLAP|CELEBRATE}"}, required=["reaction"])
    v("ConsentFormStatus", {"formId": "b", "featureCode": "s", "version": "i", "title": "s", "purpose": "s",
                            "dataUsed": "[s]", "sharedWith": "s", "retention": "s", "ifDeclined": "s",
                            "required": "bo", "subject": "PersonRef", "decision": "{GRANTED|DECLINED|WITHDRAWN|PENDING}",
                            "decidedAt": "dt"})
    v("ConsentDecisionInput", {"subjectKind": "{STUDENT|STAFF}", "subjectId": "b", "decision": "{GRANTED|DECLINED|WITHDRAWN}"},
      required=["subjectKind", "subjectId", "decision"])
    v("ConversationSummary", {"conversationId": "b", "kind": "s", "title": "s", "student": "PersonRef",
                              "lastMessage": "s", "lastMessageAt": "dt", "unread": "i", "locked": "bo",
                              "withinChatHours": "bo", "deliverAt": "dt"})
    v("MessageView", {"messageId": "b", "sender": "PersonRef", "body": "s", "attachmentUrls": "[s]", "sentAt": "dt",
                      "mine": "bo", "deleted": "bo"})
    v("MessageInput", {"body": "s", "attachmentUrls": "[s]"}, required=["body"])
    v("NewConversationInput", {"kind": "{PARENT_TEACHER|HELPDESK}", "studentId": "b", "staffUserId": "b", "firstMessage": "s"},
      "Parent <-> staff only; no parent-to-parent chat", required=["kind", "firstMessage"])

    # ------------------------------------------------------------ Me (every employee)
    v("RosterDay", {"date": "d", "shiftCode": "s", "start": "tm", "end": "tm", "postCode": "s", "status": "s"})
    v("MyShift", {"today": "RosterDay", "punchInAt": "dt", "punchOutAt": "dt", "lateMinutes": "i", "week": "[RosterDay]"})
    v("PresenceCorrectionInput", {"presenceDate": "d", "requestedStatus": "{PRESENT|LATE|HALF_DAY|ON_DUTY}",
                                  "firstInAt": "dt", "lastOutAt": "dt", "reason": "s"}, required=["presenceDate", "reason"])
    v("ShiftSwapInput", {"rosterEntryId": "b", "withUserId": "b", "withRosterEntryId": "b", "reason": "s"},
      "Both people must agree before it goes to the approver", required=["rosterEntryId", "withUserId"])
    v("PayslipSummary", {"payslipId": "b", "period": "s", "net": "n", "gross": "n", "status": "s"})

    # ------------------------------------------------------------ academics & classroom
    v("ClassSummary", {"classSectionId": "b", "sectionName": "s", "programName": "s", "isClassTeacher": "bo",
                       "subjects": "[s]", "studentCount": "i", "registerTakenToday": "bo"})
    v("PeriodSlot", {"timetableId": "b", "periodLabel": "s", "start": "tm", "end": "tm", "subject": "s",
                     "classSection": "s", "room": "s", "topic": "s", "isSubstitution": "bo", "taught": "bo"})
    v("RegisterRow", {"studentId": "b", "rollNo": "s", "name": "s", "photoUrl": "s",
                      "status": "{PRESENT|ABSENT|LATE|EXCUSED|ON_LEAVE|ON_OUTING}", "locked": "bo", "lockReason": "s"})
    v("RegisterSheet", {"classSectionId": "b", "offeringId": "b", "date": "d", "periodId": "b", "submitted": "bo",
                        "submittedAt": "dt", "rows": "[RegisterRow]", "presentCount": "i", "absentCount": "i"},
      "All present by default; approved leave rows are locked (UX v2 4.3)")
    v("AbsenteeInput", {"studentId": "b", "reason": "{UNEXCUSED|EXCUSED|MEDICAL|ON_DUTY}", "late": "bo"}, required=["studentId"])
    v("RegisterSubmission", {"date": "d", "periodId": "b", "absentees": "[AbsenteeInput]"},
      "Only the exceptions are sent; everyone else is present", required=["date"])
    v("TaughtInput", {"lessonPlanId": "b", "status": "{DELIVERED|PARTIAL|SKIPPED}", "note": "s"}, required=["status"])
    v("MarksRow", {"studentId": "b", "rollNo": "s", "name": "s", "markObtained": "n", "absent": "bo", "exempt": "bo",
                   "grade": "s", "locked": "bo"})
    v("MarksSheet", {"examId": "b", "examName": "s", "maxMarks": "n", "status": "s", "rows": "[MarksRow]",
                     "average": "n"})
    v("MarkEntry", {"studentId": "b", "markObtained": "n", "absent": "bo", "exempt": "bo"}, required=["studentId"])
    v("MarksEntryInput", {"entries": "[MarkEntry]", "reason": "s"}, "reason is required when editing after lock",
      required=["entries"])
    v("GradeInput", {"marks": "n", "feedback": "s", "status": "{GRADED|RETURNED}"}, required=["status"])
    v("SyllabusNode", {"unitId": "b", "title": "s", "sequence": "i", "plannedPeriods": "i", "deliveredPeriods": "i",
                       "children": "[SyllabusNode]"})
    v("SyllabusTree", {"syllabusId": "b", "subject": "s", "coveragePct": "n", "units": "[SyllabusNode]"})
    v("ClassMessageInput", {"audience": "{ONE_STUDENT|GROUP|WHOLE_CLASS}", "studentIds": "[b]", "templateId": "b",
                            "body": "s", "attachmentUrls": "[s]"}, required=["audience", "body"])
    v("BehaviorNoteInput", {"studentId": "b", "category": "{POSITIVE|CONCERN|WELFARE}", "note": "s",
                            "severity": "{LOW|MEDIUM|HIGH}"}, required=["studentId", "category", "note"])
    v("PtmSlotsInput", {"startAt": "dt", "endAt": "dt", "slotMinutes": "i"}, required=["startAt", "endAt"])
    v("PtmNotesInput", {"status": "{DONE|NO_SHOW|CANCELLED}", "teacherNotes": "s"})
    v("StudentCard", {"studentId": "b", "name": "s", "rollNo": "s", "photoUrl": "s", "classSection": "s",
                      "residency": "s", "alerts": "[s]", "duesHold": "bo", "parents": "[PersonRef]"},
      "Health shows alert flags only (allergy, asthma, inhaler location), with consent")
    v("InvigilationCard", {"examId": "b", "examName": "s", "room": "s", "start": "tm", "durationMinutes": "i",
                           "candidates": "[RegisterRow]", "seating": "[SeatView]"})
    v("SeatView", {"studentId": "b", "name": "s", "seatLabel": "s"})
    v("RemarkInput", {"teacherRemark": "s"}, required=["teacherRemark"])
    v("Heatmap", {"rows": "[s]", "columns": "[s]", "values": "[[n]]", "termId": "b"})
    v("MarksDistribution", {"examId": "b", "buckets": "[Bucket]", "average": "n", "median": "n", "passPct": "n"})
    v("Bucket", {"label": "s", "count": "i"})
    v("CoverageRow", {"classSection": "s", "subject": "s", "teacher": "s", "coveragePct": "n", "behindBy": "i"})
    v("CoverBoard", {"date": "d", "absentTeachers": "[PersonRef]", "uncovered": "[UncoveredPeriod]"},
      "Absent teachers, uncovered periods and suggested substitutes (free and on shift)")
    v("UncoveredPeriod", {"classSectionPeriodId": "b", "staffAbsenceId": "b", "period": "s", "classSection": "s",
                          "subject": "s", "suggestions": "[PersonRef]"})
    v("SubstitutionInput", {"staffAbsenceId": "b", "classSectionPeriodId": "b", "substituteUserId": "b"},
      required=["staffAbsenceId", "classSectionPeriodId", "substituteUserId"])
    v("StaffPresenceRow", {"userId": "b", "name": "s", "department": "s", "shift": "s",
                           "status": "s", "firstInAt": "dt", "lateMinutes": "i", "onLeave": "bo", "locked": "bo"})
    v("PresenceCorrection", {"status": "{PRESENT|LATE|HALF_DAY|ABSENT|ON_LEAVE|ON_DUTY}", "reason": "s"},
      "Never your own row", required=["status", "reason"])
    v("CircularInput", {"title": "s", "body": "s", "audienceType": "{USERS|SECTION|PROGRAM|HOSTEL|BLOCK|STAFF_TYPE|ALL}",
                        "audienceIds": "[b]", "roleCodes": "[s]", "channel": "{APP|WHATSAPP|EMAIL|ALL}",
                        "requiresAck": "bo", "severity": "{INFO|ACTION|URGENT}", "scheduledAt": "dt",
                        "attachmentUrls": "[s]"}, required=["title", "body", "audienceType"])
    v("ReadReceiptSummary", {"notificationId": "b", "recipients": "i", "read": "i", "acknowledged": "i",
                             "pending": "[PersonRef]"})
    v("TimetableCell", {"day": "s", "periodId": "b", "subject": "s", "teacher": "s", "room": "s", "timetableId": "b"})
    v("TimetableGrid", {"classSectionId": "b", "versionId": "b", "periods": "[s]", "cells": "[TimetableCell]"})
    v("TimetableSlotInput", {"classSectionPeriodId": "b", "dayOfWeek": "{MON|TUE|WED|THU|FRI|SAT|SUN}",
                             "staffSubjectId": "b", "offeringId": "b", "roomLocationId": "b"},
      required=["classSectionPeriodId", "dayOfWeek"])
    v("TimetableSlotsInput", {"slots": "[TimetableSlotInput]"}, required=["slots"])
    v("Clash", {"kind": "{TEACHER_DOUBLE_BOOKED|ROOM_DOUBLE_BOOKED|OUTSIDE_SHIFT|MAX_PER_DAY|PERIODS_PER_WEEK}",
                "message": "s", "cells": "[s]"})
    v("TimetableValidation", {"versionId": "b", "saved": "i", "clashes": "[Clash]"})
    v("SetupStep", {"key": "s", "label": "s", "done": "i", "total": "i", "complete": "bo", "deepLink": "s"})
    v("SetupChecklist", {"steps": "[SetupStep]", "percent": "n"},
      "New branch: sections, subjects, staff, students & parents, fees, timetable, gate devices, consents, invites")
    v("StudentProfile", {"student": "E:academics.student", "parents": "[PersonRef]", "enrollments": "[E:academics.student_enrollment]",
                         "documents": "[E:records.document]", "hostel": "HostelCard", "dues": "n", "alerts": "[s]"})
    v("ParentLinkInput", {"userId": "b", "inviteEmail": "s", "invitePhone": "s", "relationshipType": "s",
                          "primaryContact": "bo"}, "Link an existing user, or invite one through school-auth",
      required=["relationshipType"])
    v("ImportUpload", {"entity": "{STUDENT|PARENT|STAFF|SECTION|SUBJECT|FEE_DUE|MARKS|BOOK|INVENTORY_ITEM|HOSTEL_ROOM|TRANSPORT_STOP}",
                       "file": "binary", "dryRun": "bo"}, required=["entity", "file"])
    v("FileUpload", {"file": "binary", "ownerKind": "s", "ownerId": "b", "docType": "s"}, required=["file"])
    v("DeviceBinding", {"deviceId": "b", "kioskIdleMinutes": "i"}, required=["deviceId"])

    # ------------------------------------------------------------ finance
    v("DueLine", {"feeId": "b", "student": "PersonRef", "head": "s", "dueDate": "d", "net": "n", "paid": "n",
                  "remaining": "n", "fine": "n", "status": "s"})
    v("FamilyDues", {"students": "[PersonRef]", "lines": "[DueLine]", "totalDue": "n", "overdue": "n",
                     "walletBalances": "j"}, "Dues across siblings")
    v("AllocationInput", {"feeId": "b", "amount": "n"}, required=["feeId", "amount"])
    v("CounterPaymentInput", {"studentId": "b", "mode": "{CASH|CHEQUE|DD|UPI|CARD|BANK_TRANSFER}", "amount": "n",
                              "allocations": "[AllocationInput]", "chequeNumber": "s", "bankName": "s",
                              "referenceNo": "s"}, required=["studentId", "mode", "amount", "allocations"])
    v("PaymentReceipt", {"payment": "E:finance.payment", "allocations": "[E:finance.payment_allocation]",
                         "receiptUrl": "s", "sentOnWhatsapp": "bo"})
    v("ReceiptNumberPreview", {"next": "s", "financialYear": "s"})
    v("BounceInput", {"bouncedOn": "d", "reason": "s", "charge": "n"}, required=["bouncedOn"])
    v("OnlinePaymentInit", {"feeIds": "[b]", "amount": "n", "gateway": "{RAZORPAY|PAYU|CCAVENUE}"},
      required=["feeIds", "amount"])
    v("PaymentIntent", {"paymentId": "b", "gateway": "s", "gatewayOrderId": "s", "amount": "n", "upiIntent": "s",
                        "checkoutUrl": "s", "expiresAt": "dt"})
    v("GatewayConfirmation", {"gatewayPaymentId": "s", "signature": "s"}, required=["gatewayPaymentId"])
    v("PayExpenseInput", {"paymentMode": "{BANK_TRANSFER|CHEQUE|UPI|CASH|CARD}", "paidFrom": "{BANK|PETTY_CASH}",
                          "pettyCashId": "b", "referenceNo": "s", "paidAt": "dt"}, required=["paymentMode", "paidFrom"])
    v("BudgetUtilization", {"budgetId": "b", "head": "s", "costCentre": "s", "budget": "n", "spent": "n",
                            "committed": "n", "pct": "n", "alert": "bo"})
    v("DayClose", {"date": "d", "systemCash": "n", "byMode": "j", "receipts": "i", "counted": "n", "difference": "n",
                   "closed": "bo"})
    v("DayCloseInput", {"date": "d", "countedCash": "n", "differenceReason": "s", "depositSlipNo": "s"},
      required=["date", "countedCash"])
    v("DefaulterRow", {"student": "PersonRef", "classSection": "s", "due": "n", "oldestDueDate": "d",
                       "bucket": "{D0_30|D31_60|D60_PLUS}", "parentPhone": "s"})
    v("ThreeWayMatch", {"invoiceId": "b", "poTotal": "n", "received": "n", "invoiced": "n",
                        "status": "{MATCHED|MISMATCH}", "lines": "j"})
    v("CollectionSummary", {"from": "d", "to": "d", "total": "n", "byMode": "j", "byHead": "j", "target": "n",
                            "daily": "[Kpi]"})
    v("DuesAging", {"d0to30": "n", "d31to60": "n", "d60plus": "n", "students": "i"})
    v("TallyExportInput", {"from": "d", "to": "d"}, required=["from", "to"])
    v("WalletStatement", {"wallet": "E:finance.student_wallet", "transactions": "[E:finance.wallet_txn]"})
    v("TopUpInit", {"amount": "n"}, required=["amount"])

    # ------------------------------------------------------------ HR
    v("VaultReveal", {"field": "{BANK_ACCOUNT|PAN|DRIVING_LICENCE}", "value": "s", "revealedAt": "dt"},
      "Revealing a vault value is logged")
    v("RosterCell", {"userId": "b", "date": "d", "rosterEntryId": "b", "shiftCode": "s", "postCode": "s", "status": "s"})
    v("RosterWeek", {"weekStart": "d", "people": "[PersonRef]", "cells": "[RosterCell]", "gaps": "[RosterGap]",
                     "conflicts": "[Clash]"})
    v("RosterUpdate", {"set": "[RosterCellInput]", "remove": "[b]"})
    v("RosterCellInput", {"userId": "b", "date": "d", "shiftId": "b", "postId": "b"}, required=["userId", "date", "shiftId"])
    v("RosterGap", {"date": "d", "postCode": "s", "shiftCode": "s", "required": "i", "assigned": "i"})
    v("PresenceException", {"person": "PersonRef", "date": "d", "kind": "{LATE|ABSENT_NO_LEAVE|NO_PUNCH_OUT|SHORT_HOURS}",
                            "minutes": "i"})
    v("PayrollRunInput", {"period": "s"}, required=["period"])
    v("PayrollException", {"user": "PersonRef", "kind": "s", "message": "s"})

    # ------------------------------------------------------------ admissions & front office
    v("QuickEnquiryInput", {"phone": "s", "childName": "s", "programId": "b", "source": "{WALK_IN|WEBSITE|PHONE|WHATSAPP|SOCIAL|REFERRAL|CAMPAIGN|EVENT}",
                            "guardianName": "s", "email": "s", "campaign": "s"}, "20-second capture",
      required=["phone", "childName"])
    v("EnquiryWithDuplicates", {"enquiry": "E:admissions.enquiry", "possibleDuplicates": "[E:admissions.enquiry]"})
    v("EnquiryUpdate", {"stage": "{NEW|CONTACTED|VISIT_SCHEDULED|VISITED|APPLIED|LOST}", "lostReason": "s",
                        "ownerUserId": "b", "nextFollowUpAt": "dt"}, "LOST needs lostReason")
    v("PipelineStage", {"stage": "s", "count": "i", "items": "[E:admissions.enquiry]"})
    v("Pipeline", {"stages": "[PipelineStage]"})
    v("AdmissionDecision", {"decision": "{OFFERED|WAITLISTED|REJECTED}", "note": "s"}, required=["decision"])
    v("ConversionPreview", {"applicationId": "b", "student": "j", "parents": "[j]", "enrollment": "j",
                            "firstFees": "[j]", "hostelRequest": "bo", "transportRequest": "bo", "warnings": "[s]"})
    v("ConversionResult", {"studentId": "b", "enrollmentId": "b", "feeIds": "[b]", "parentInvites": "i"})
    v("SeatMatrixRow", {"programId": "b", "program": "s", "total": "i", "rte": "i", "management": "i", "hostel": "i",
                        "offered": "i", "enrolled": "i", "remaining": "i"})
    v("ReenrollmentInvite", {"academicYearId": "b", "classSectionIds": "[b]"}, required=["academicYearId"])
    v("ReenrollmentResponse", {"status": "{CONFIRMED|DECLINED|LEAVING}", "leavingReason": "s"}, required=["status"])
    v("FunnelSummary", {"academicYearId": "b", "stages": "[Kpi]", "conversionPct": "n", "bySource": "j"})
    v("VisitCheckIn", {"phone": "s", "name": "s", "photoUrl": "s", "idProofType": "s", "idProofLast4": "s",
                       "purpose": "{PARENT_MEETING|ADMISSION|VENDOR|INTERVIEW|HOSTEL_VISIT|OFFICIAL|OTHER}",
                       "hostUserId": "b", "studentId": "b", "pickupPersonId": "b", "badgeNumber": "s"},
      "Blacklisted visitors are refused with a reason code only", required=["phone", "name", "purpose"])
    v("EarlyLeaveInput", {"studentId": "b", "pickupPersonId": "b", "reason": "s"}, required=["studentId", "pickupPersonId"])
    v("OtpVerifyInput", {"otp": "s", "photoMatched": "bo"}, required=["otp"])
    v("HandoverInput", {"toUserId": "b", "toPickupPersonId": "b", "signatureUrl": "s", "note": "s"})
    v("FrontOfficeLogEntry", {"at": "dt", "kind": "{VISIT_IN|VISIT_OUT|GATE_PASS|PARCEL_IN|PARCEL_OUT|ENQUIRY}",
                              "title": "s", "refId": "b"})

    # ------------------------------------------------------------ parent & student
    v("ChildSummary", {"studentId": "b", "name": "s", "photoUrl": "s", "classSection": "s", "branchName": "s",
                       "schoolId": "b", "residency": "{DAY_SCHOLAR|HOSTELLER}",
                       "statusDot": "{GREEN|AMBER|RED}", "statusText": "s"},
      "Green = in school/hostel, amber = on outing or late, red = absent or missing")
    v("AttendanceDay", {"date": "d", "status": "s", "arrivedAt": "dt", "note": "s"})
    v("AttendanceCalendar", {"studentId": "b", "month": "s", "days": "[AttendanceDay]", "presentPct": "n"})
    v("SubjectAttendance", {"subject": "s", "held": "i", "attended": "i", "pct": "n", "minimumPct": "n",
                            "canMiss": "i", "shortfall": "bo"}, "College warning: 'You can miss 2 more Physics classes'")
    v("HomeworkView", {"homeworkId": "b", "subject": "s", "title": "s", "description": "s", "assignedDate": "d",
                       "dueDate": "d", "attachmentUrls": "[s]", "submissionMode": "s", "submissionStatus": "s",
                       "marks": "n", "feedback": "s"})
    v("ExamResult", {"examId": "b", "examName": "s", "subject": "s", "maxMarks": "n", "markObtained": "n",
                     "grade": "s", "absent": "bo", "publishedAt": "dt"})
    v("ReportCardStatus", {"reportCardId": "b", "term": "s", "status": "{READY|DUES_HOLD|WITHHELD|NOT_PUBLISHED}",
                           "message": "s", "publishedAt": "dt"},
      "DUES_HOLD: 'Report card is ready. It will open once fees are cleared, or contact the office.'")
    v("HostelCard", {"studentId": "b", "hostel": "s", "room": "s", "bed": "s",
                     "status": "{IN_HOSTEL|ON_OUTING|SICK_BAY|ON_LEAVE|MISSING}", "expectedBackAt": "dt",
                     "lastRollCall": "dt", "phoneCustody": "s", "walletBalance": "n", "todayMenu": "[E:hostel.mess_menu]"})
    v("OutingRequestInput", {"outingType": "{LOCAL_OUTING|DAY_OUT|WEEKEND_HOME|HOME_LEAVE|VACATION}", "purpose": "s",
                             "destination": "s", "departPlannedAt": "dt", "returnPlannedAt": "dt",
                             "travelMode": "{SELF|PARENT_PICKUP|AUTHORISED_PICKUP|SCHOOL_VEHICLE|TRAIN|BUS|FLIGHT}",
                             "travelRef": "s", "travelDepartureAt": "dt", "pickupPersonId": "b",
                             "releaseCustodyItems": "bo"}, required=["outingType", "departPlannedAt", "returnPlannedAt"])
    v("OutingView", {"outing": "E:hostel.outing_request", "student": "PersonRef", "policyChecks": "[PolicyCheck]",
                     "timeline": "[TimelineStep]", "gatePassQr": "s"})
    v("TimelineStep", {"step": "s", "at": "dt", "by": "s", "done": "bo"})
    v("ParentDecision", {"decision": "{APPROVED|DECLINED}", "pickupPersonId": "b", "note": "s"},
      "Confirmed on the device with app PIN / Face ID", required=["decision"])
    v("PickupPersonInput", {"name": "s", "relationship": "s", "phone": "s", "photoUrl": "s", "idProofLast4": "s",
                            "validFrom": "d", "validTo": "d"}, "The phone gets an OTP to confirm",
      required=["name", "relationship", "phone"])
    v("CustodyItemView", {"itemId": "b", "itemType": "s", "description": "s", "status": "s", "unit": "s",
                          "since": "dt", "dueBackAt": "dt"})
    v("BookSlot", {"studentId": "b"}, required=["studentId"])
    v("PollResponseInput", {"optionKey": "s", "studentId": "b"}, required=["optionKey"])
    v("BusStatus", {"tripId": "b", "route": "s", "status": "s", "lat": "n", "lng": "n", "etaMinutes": "i",
                    "boardedAt": "dt", "alightedAt": "dt"})
    v("SubmissionInput", {"textAnswer": "s", "attachmentUrls": "[s]"})
    v("QuizAnswersInput", {"answers": "j", "submit": "bo"}, required=["answers"])
    v("CourseRegistrationInput", {"offeringId": "b"}, required=["offeringId"])
    v("IdCardView", {"cardNumber": "s", "name": "s", "photoUrl": "s", "validTill": "d", "qrToken": "s",
                     "gateEntryEnabled": "bo"})

    # ------------------------------------------------------------ hostel
    v("BlockRollStatus", {"blockId": "b", "block": "s", "expected": "i", "present": "i", "absentWithPass": "i",
                          "absentNoPass": "i", "submitted": "bo"})
    v("HostelNow", {"hostelId": "b", "asOf": "dt", "rollCall": "[BlockRollStatus]", "onOuting": "i", "overdue": "[OutingView]",
                    "sickBay": "i", "occupancy": "n", "phonesHeld": "i", "phonesPending": "i", "wardensOnDuty": "[PersonRef]"})
    v("BedCell", {"bedId": "b", "label": "s", "status": "s", "student": "PersonRef", "allocationId": "b"})
    v("RoomCell", {"roomId": "b", "roomNumber": "s", "floor": "i", "roomType": "s", "isAc": "bo", "beds": "[BedCell]"})
    v("AllocationBoard", {"hostelId": "b", "floor": "i", "rooms": "[RoomCell]", "waitlist": "[E:hostel.allocation_request]"})
    v("AllocationCreate", {"studentId": "b", "bedId": "b", "checkInDate": "d", "feePlanId": "b", "requestId": "b"},
      "One active bed per student and per bed", required=["studentId", "bedId", "checkInDate"])
    v("VacateInput", {"checkOutDate": "d", "reason": "s"}, "Blocked while custody items are held", required=["checkOutDate"])
    v("TransferInput", {"toBedId": "b", "date": "d", "reason": "s"}, required=["toBedId", "date"])
    v("TravelGroupBoard", {"group": "E:hostel.outing_group", "students": "[TravelGroupStudent]"})
    v("TravelGroupStudent", {"student": "PersonRef", "outingId": "b", "parentConfirmed": "bo", "scannedOut": "bo",
                             "phoneReleased": "bo", "arrivedAt": "dt"})
    v("ArrivalCheckIn", {"studentIds": "[b]", "arrivedAt": "dt", "note": "s"}, required=["studentIds"])
    v("HostelMonthlyReport", {"hostelId": "b", "month": "s", "occupancy": "n", "outings": "i", "lateReturns": "i",
                              "incidents": "i", "inspections": "i", "avgHygiene": "n", "messRating": "n",
                              "comments": "s", "submittedAt": "dt"})
    v("ReportComments", {"comments": "s"})
    v("DamageChargeInput", {"studentId": "b", "amount": "n", "description": "s"}, required=["studentId", "amount"])
    v("ResidentCard", {"student": "PersonRef", "room": "s", "bed": "s", "status": "s", "phoneCustody": "s",
                       "alerts": "[s]"})
    v("RollCallStart", {"hostelId": "b", "session": "{MORNING|STUDY_HOUR|NIGHT|EMERGENCY|CUSTOM}", "assignmentId": "b"},
      required=["hostelId", "session"])
    v("RollCallRow", {"entryId": "b", "student": "PersonRef", "room": "s",
                      "status": "{PRESENT|ABSENT|ON_OUTING|ON_LEAVE|SICK_BAY|EXCUSED}", "prefilled": "bo",
                      "custodyPending": "bo", "note": "s"})
    v("RollCallSheet", {"rollCallId": "b", "session": "s", "rollDate": "d", "status": "s", "rows": "[RollCallRow]",
                        "escalations": "[CriticalAlert]"},
      "Pre-filled from passes; submitting with anyone absent without a pass starts the escalation ladder")
    v("RollCallMark", {"studentId": "b", "status": "{PRESENT|ABSENT|ON_OUTING|ON_LEAVE|SICK_BAY|EXCUSED}", "note": "s"},
      required=["studentId", "status"])
    v("RollCallEntriesInput", {"marks": "[RollCallMark]"}, required=["marks"])
    v("CustodyEventInput", {"eventType": "{DEPOSIT|RELEASE|RETURN|MOVE_UNIT|CONFISCATE|HANDOVER_PARENT|INSPECT|MARK_LOST|MARK_DAMAGED|CLOSE}",
                            "releaseReason": "{TRAVEL_HOME|OUTING|CALL_HOUR|ONLINE_EXAM|MEDICAL|PARENT_COLLECT|LEAVING_SCHOOL}",
                            "outingId": "b", "groupId": "b", "windowId": "b", "incidentId": "b", "toUnitId": "b",
                            "counterpartyKind": "{STUDENT|PARENT|PICKUP_PERSON}", "counterpartyUserId": "b",
                            "counterpartyPickupPersonId": "b", "verification": "{QR|STUDENT_OTP|PARENT_OTP|SIGNATURE|FACE}",
                            "conditionNote": "s", "photoUrl": "s"},
      "Release only after gate OUT / in a call-hour window; confiscation needs an incident (enforced by the database)",
      required=["eventType"])
    v("ReleaseCheck", {"itemId": "b", "allowed": "bo", "reason": "s", "dueBackAt": "dt", "windowId": "b", "outingId": "b"})
    v("WardenOutingInput", {"studentId": "b", "outingType": "{MEDICAL|EMERGENCY|OFFICIAL}", "purpose": "s",
                            "destination": "s", "departPlannedAt": "dt", "returnPlannedAt": "dt", "travelMode": "s"},
      required=["studentId", "outingType", "departPlannedAt", "returnPlannedAt"])
    v("EmergencyApproval", {"confirmedByUserId": "b", "confirmedByName": "s", "callAt": "dt", "note": "s"},
      "Night warden's provisional approval, recording who confirmed by phone", required=["callAt"])
    v("HandoverDraft", {"openItems": "[s]", "sickStudents": "[PersonRef]", "lateReturns": "[OutingView]",
                        "openIncidents": "[E:discipline.incident]"})
    v("WardenHandoverInput", {"toUserId": "b", "notes": "s", "openItems": "[s]"}, required=["notes"])
    v("MedicationDue", {"doseId": "b", "student": "PersonRef", "medicine": "s", "dose": "s", "dueAt": "dt"})
    v("DoseRecordInput", {"status": "{GIVEN|MISSED|REFUSED}", "givenAt": "dt", "reason": "s"}, required=["status"])
    v("SickBayAdmitInput", {"studentId": "b", "complaint": "s", "vitals": "j"}, required=["studentId"])
    v("DischargeInput", {"disposition": "{BACK_TO_CLASS|SENT_HOME|HOSPITAL_REFERRAL}", "note": "s"}, required=["disposition"])
    v("PatientCard", {"student": "PersonRef", "medicalProfile": "E:wellbeing.medical_profile",
                      "vaccinations": "[E:wellbeing.vaccination]", "checkups": "[E:wellbeing.health_checkup]",
                      "recentVisits": "[E:wellbeing.infirmary_visit]", "consentGranted": "bo"})
    v("VisitUpdate", {"treatment": "s", "vitals": "j", "disposition": "{BACK_TO_CLASS|SICK_BAY|SENT_HOME|HOSPITAL_REFERRAL}"})
    v("CheckupEntry", {"studentId": "b", "heightCm": "n", "weightKg": "n", "vision": "s", "dental": "s", "notes": "s"},
      required=["studentId"])
    v("CheckupBatchInput", {"checkupDate": "d", "entries": "[CheckupEntry]"}, required=["checkupDate", "entries"])
    v("VaccinationDue", {"student": "PersonRef", "vaccine": "s", "dose": "i", "dueOn": "d"})
    v("MealNow", {"messId": "b", "meal": "s", "date": "d", "expected": "i", "scanned": "i", "onOuting": "i",
                  "onLeave": "i", "sickBay": "i"}, "Expected = subscribers minus on outing, on leave, in sick bay")
    v("MenuEntryInput", {"dayOfWeek": "{MON|TUE|WED|THU|FRI|SAT|SUN}", "menuDate": "d",
                         "meal": "{BREAKFAST|LUNCH|SNACKS|DINNER}", "items": "s", "special": "bo"}, required=["meal", "items"])
    v("MenuInput", {"entries": "[MenuEntryInput]"}, required=["entries"])
    v("MealScanInput", {"subscriptionId": "b", "studentId": "b", "mealDate": "d", "meal": "{BREAKFAST|LUNCH|SNACKS|DINNER}"},
      required=["mealDate", "meal"])
    v("FeedbackSummary", {"messId": "b", "from": "d", "average": "n", "byMeal": "j", "comments": "[s]"})
    v("StockRow", {"stockId": "b", "itemCatalogId": "b", "item": "s", "location": "s", "onHand": "n", "reorderLevel": "n",
                   "avgUnitCost": "n", "low": "bo"})
    v("CostReport", {"messId": "b", "month": "s", "meals": "i", "provisionsCost": "n", "costPerMeal": "n"})

    # ------------------------------------------------------------ security
    v("GuardHome", {"post": "s", "shift": "s", "onDutyFrom": "dt", "onDutyTo": "dt", "nextCheckpoint": "s",
                    "nextCheckpointDueAt": "dt", "welfarePingDueAt": "dt", "expected": "[ExpectedMovement]",
                    "cards": "[HomeCard]"})
    v("ExpectedMovement", {"kind": "{OUTING_RETURN|TRAVEL_GROUP_DEPARTURE|VISITOR|VEHICLE}", "title": "s", "at": "dt",
                           "refId": "b", "count": "i"})
    v("GateScanInput", {"code": "s", "direction": "{OUT|IN}"}, required=["code"])
    v("GateVerdict", {"verdict": "{ALLOWED|STOP|UNVERIFIED}", "reason": "s", "student": "PersonRef",
                      "classSection": "s", "passType": "s", "outingId": "b", "gatePassId": "b",
                      "pickupPerson": "PersonRef", "requiresParentOtp": "bo"},
      "Guards see name, photo, class and pass status only")
    v("GateMovementInput", {"outingId": "b", "direction": "{OUT|IN}", "verifiedPickupPersonId": "b",
                            "verification": "{QR|PARENT_OTP|PHOTO_ID|FACE}", "parentOtp": "s", "movedAt": "dt"},
      required=["outingId", "direction", "verification"])
    v("GroupOutInput", {"studentIds": "[b]", "movedAt": "dt"}, required=["studentIds"])
    v("PatrolCheckpointView", {"checkpointId": "b", "name": "s", "sequence": "i", "scannedAt": "dt",
                               "state": "{PENDING|DONE|LATE|MISSED}", "photoRequired": "bo"})
    v("PatrolRoundSheet", {"roundId": "b", "route": "s", "dueAt": "dt", "status": "s", "checkpoints": "[PatrolCheckpointView]"})
    v("PatrolScanInput", {"tagUid": "s", "checkpointId": "b", "method": "{NFC|QR|MANUAL_WITH_REASON}", "lat": "n", "lng": "n",
                          "photoUrl": "s", "note": "s", "scannedAt": "dt"}, required=["method"])
    v("OccurrenceUpdate", {"status": "{ACKNOWLEDGED|RESOLVED}", "escalatedToUserId": "b", "note": "s"})
    v("KeyIssueInput", {"issuedToUserId": "b", "dueBackAt": "dt"}, required=["issuedToUserId"])
    v("ShiftHandoverInput", {"postId": "b", "toRosterEntryId": "b", "notes": "s", "equipment": "s"}, required=["postId"])
    v("OfflineAction", {"idempotencyKey": "s", "kind": "{GATE_MOVEMENT|PATROL_SCAN|PUNCH|VISIT|VEHICLE|OCCURRENCE|ROLL_CALL_MARK|CUSTODY_EVENT|BOARDING}",
                        "occurredAt": "dt", "payload": "j"}, required=["idempotencyKey", "kind", "occurredAt", "payload"])
    v("OfflineBatch", {"deviceId": "s", "actions": "[OfflineAction]"}, required=["actions"])
    v("OfflineResult", {"idempotencyKey": "s", "status": "{APPLIED|DUPLICATE|REJECTED}", "message": "s"})
    v("OfflineBatchResult", {"results": "[OfflineResult]"})
    v("LivePost", {"postId": "b", "post": "s", "guard": "PersonRef", "punchedInAt": "dt", "lastActivityAt": "dt",
                   "state": "{MANNED|LATE|UNMANNED}"})
    v("PatrolCompliance", {"date": "d", "rounds": "i", "completed": "i", "late": "i", "missed": "i", "pct": "n",
                           "byRoute": "j"})
    v("CheckpointOrderInput", {"checkpoints": "[RouteCheckpointInput]"}, required=["checkpoints"])
    v("RouteCheckpointInput", {"checkpointId": "b", "sequence": "i", "photoRequired": "bo"},
      required=["checkpointId", "sequence"])
    v("KeyStatus", {"key": "E:security.key", "issuedTo": "PersonRef", "issuedAt": "dt", "dueBackAt": "dt", "overdue": "bo"})

    # ------------------------------------------------------------ operations / store / library / transport
    v("IssueBookInput", {"copyBarcode": "s", "borrowerStudentId": "b", "borrowerUserId": "b", "dueOn": "d"},
      required=["copyBarcode"])
    v("ReturnBookInput", {"copyBarcode": "s", "returnedOn": "d"}, "Fines (if enabled) post a fee demand",
      required=["copyBarcode"])
    v("TicketUpdate", {"status": "{ASSIGNED|IN_PROGRESS|RESOLVED|CLOSED|REOPENED}", "assignedToUserId": "b",
                       "resolutionNote": "s"})
    v("IssueLine", {"itemCatalogId": "b", "assetId": "b", "quantity": "n", "batchNo": "s"}, required=["itemCatalogId", "quantity"])
    v("StockIssueInput", {"fromLocationId": "b", "issuedToUserId": "b", "issuedToStudentId": "b",
                          "issuedToDepartmentId": "b", "costCentre": "{SCHOOL|HOSTEL|MESS|TRANSPORT|DEPARTMENT}",
                          "requisitionId": "b", "lines": "[IssueLine]", "note": "s"},
      "Can't issue more than on hand (database rule)", required=["fromLocationId", "lines"])
    v("PurchaseOrderLineInput", {"itemCatalogId": "b", "quantity": "n", "unitPrice": "n", "gstRate": "n"},
      required=["itemCatalogId", "quantity", "unitPrice"])
    v("PurchaseOrderCreate", {"vendorId": "b", "requisitionId": "b", "expectedDate": "d", "lines": "[PurchaseOrderLineInput]"},
      required=["vendorId", "lines"])
    v("GrnLineInput", {"poLineId": "b", "itemCatalogId": "b", "receivedQty": "n", "acceptedQty": "n", "rejectedQty": "n",
                       "unitCost": "n", "batchNo": "s", "expiryDate": "d"}, required=["itemCatalogId", "receivedQty"])
    v("GoodsReceiptCreate", {"poId": "b", "locationId": "b", "vendorChallanNo": "s", "invoicePhotoUrl": "s",
                             "lines": "[GrnLineInput]"}, required=["poId", "locationId", "lines"])
    v("AssetAssignInput", {"assignedLocationId": "b", "assignedUserId": "b", "assignedStudentId": "b"})
    v("StockAuditCreate", {"locationId": "b", "auditDate": "d"}, required=["locationId"])
    v("StockAuditSheet", {"auditId": "b", "location": "s", "status": "s", "blind": "bo", "lines": "[StockAuditLineView]"},
      "Blind count: system quantity hidden until submitted")
    v("StockAuditLineView", {"lineId": "b", "itemCatalogId": "b", "item": "s", "assetId": "b", "systemQty": "n",
                             "countedQty": "n", "varianceReason": "s"})
    v("CountInput", {"lineId": "b", "countedQty": "n", "varianceReason": "s"}, required=["lineId", "countedQty"])
    v("CountsInput", {"counts": "[CountInput]"}, required=["counts"])
    v("KitIssueInput", {"studentId": "b", "kitCode": "s", "fromLocationId": "b"}, required=["studentId", "kitCode"])
    v("LiveTrip", {"tripId": "b", "route": "s", "driver": "PersonRef", "status": "s", "lat": "n", "lng": "n",
                   "onTime": "bo", "stoppedMinutes": "i", "lastUpdateAt": "dt"})
    v("ComplianceItem", {"vehicleId": "b", "registrationNumber": "s", "kind": "{INSURANCE|FITNESS|PERMIT|PUC|DRIVING_LICENCE}",
                         "validTill": "d", "daysLeft": "i"})
    v("StopInput", {"name": "s", "lat": "n", "lng": "n", "sequence": "i", "pickupTime": "tm", "dropTime": "tm",
                    "feeStructureId": "b"}, required=["name", "sequence"])
    v("StopsInput", {"stops": "[StopInput]"}, required=["stops"])
    v("MaskedCallLog", {"callId": "s", "tripId": "b", "driver": "PersonRef", "student": "PersonRef", "startedAt": "dt",
                        "endedAt": "dt", "durationSeconds": "i"})
    v("TripStopView", {"stopId": "b", "name": "s", "sequence": "i", "eta": "dt",
                       "students": "[TripStudent]", "reached": "bo"})
    v("TripStudent", {"studentId": "b", "name": "s", "event": "{PENDING|BOARDED|ALIGHTED|NO_SHOW}"},
      "Names only; drivers never see phone numbers")
    v("TripSheet", {"trip": "E:transport.trip", "nextStop": "TripStopView", "stops": "[TripStopView]"})
    v("LocationPoint", {"recordedAt": "dt", "lat": "n", "lng": "n", "speedKmph": "n"}, required=["recordedAt", "lat", "lng"])
    v("LocationBatch", {"points": "[LocationPoint]"}, required=["points"])
    v("BoardingMark", {"studentId": "b", "stopId": "b", "event": "{BOARDED|ALIGHTED|NO_SHOW}", "source": "{RFID|QR|MANUAL}",
                       "eventAt": "dt"}, required=["studentId", "event"])
    v("EmergencyInput", {"kind": "{BREAKDOWN|ACCIDENT|MEDICAL|SECURITY|OTHER}", "lat": "n", "lng": "n", "note": "s"},
      required=["kind"])
    v("MaskedCallRequest", {"studentId": "b"}, "Only during an active trip; the call is logged", required=["studentId"])
    v("MaskedCall", {"callId": "s", "dialNumber": "s", "expiresAt": "dt"})

    # ------------------------------------------------------------ admin / management
    v("BranchComparison", {"metric": "s", "rows": "[BranchKpis]"})
    v("AcademicSummary", {"termId": "b", "averagePct": "n", "passPct": "n", "byProgram": "[Kpi]", "coveragePct": "n"},
      "Aggregates only: no marks entry, no student names")
    v("OccupancySummary", {"capacity": "i", "occupied": "i", "pct": "n", "byHostel": "[Kpi]"})
    v("SavedReportRun", {"reportId": "b", "exportJobId": "b", "status": "s"})

    # ------------------------------------------------------------ assistant (MCP, read-only)
    v("AssistantContext", {"userId": "b", "role": "s", "categories": "[s]", "children": "[ChildSummary]",
                           "pinRequiredFor": "[s]"})
    v("AttendanceToday", {"studentId": "b", "date": "d", "status": "s", "arrivedAt": "dt", "periodsAbsent": "[s]"})
    v("FeeSummary", {"studentId": "b", "totalDue": "n", "nextDueDate": "d", "overdue": "n"})
    v("HostelStatus", {"studentId": "b", "status": "s", "expectedBackAt": "dt", "lastRollCall": "dt"})
    v("NoticeView", {"notificationId": "b", "title": "s", "body": "s", "sentAt": "dt"})
    v("ClassAttendanceSummary", {"classSectionId": "b", "date": "d", "present": "i", "absent": "i", "late": "i",
                                 "notTaken": "bo"})
