"""Endpoints per actor (Role-based UX v2 section 5). One Actor = one Java package com.school.app.role.<key>
and one spec file openapi/<key>.yaml. Permission codes are the auth seed's <MODULE>_<ACTION> codes."""
from spec import Actor, ref as V


def arr(r):
    return {"type": "array", "items": r}


def P(*perms):
    return list(perms)


def build(reg):
    E, I = reg.entity, reg.entity_input
    actors = []

    def actor(*a, **kw):
        x = Actor(*a, **kw)
        actors.append(x)
        return x

    # ===================================================================== common (every role)
    c = actor("common", "Common", ["*"], "Shared across roles: context, navigation, inbox, approvals, news feed, "
              "calendar, consents, messages, scan hub, search, files and the employee Me area")
    c.get("/me", "getMe", "Who I am and my access in each branch (from the token)", V("MeContext"), header_school=False)
    c.get("/me/navigation", "getNavigation", "Mobile tabs and web sidebar for the current role", V("Navigation"),
          query=[("role", "s", "Role code when the user holds several")])
    c.get("/me/duties", "listMyDuties", "Duty overlays (class teacher, invigilator, escort, warden duties)", arr(V("Duty")))
    c.get("/search", "search", "Ctrl-K: screens, students, staff, receipts you may see", arr(V("SearchHit")), query=[("q", "s")])
    c.get("/inbox", "listInbox", "Notifications for all my roles, each with a role tag", V("InboxItem"), paged=True,
          query=[("unreadOnly", "bo"), ("severity", "{INFO|ACTION|URGENT|CRITICAL}")])
    c.post("/inbox/{notificationId}/read", "markRead", "Mark read")
    c.post("/inbox/{notificationId}/acknowledge", "acknowledge", "Acknowledge (circulars, critical alerts)")
    c.get("/alerts/critical", "listCriticalAlerts", "Open critical alerts with their escalation ladder", arr(V("CriticalAlert")))
    c.get("/approvals", "listApprovals", "Approvals inbox: everything I may decide, sorted safety > money > rest",
          V("ApprovalItem"), paged=True, query=[("kind", "s"), ("urgency", "{SAFETY|MONEY|OTHER}"), ("branchId", "b")])
    c.get("/approvals/{flowInstanceId}", "getApproval", "One request with policy checks and history", V("ApprovalItem"))
    c.post("/approvals/{flowInstanceId}/decision", "decide", "Approve, reject (note required) or send back",
           V("ApprovalItem"), body=V("DecisionRequest"))
    c.post("/approvals/bulk-approve", "bulkApprove", "Approve several when every check passes (web)", V("BulkResult"),
           body=V("BulkDecisionRequest"))
    c.get("/my-requests", "listMyRequests", "My own requests and who they are waiting for", V("ApprovalItem"), paged=True)
    c.get("/news", "listNews", "News feed (last 30 days)", V("NewsPostView"), paged=True, feature="NEWS_FEED")
    c.post("/news", "createNewsPost", "Post to the feed", V("NewsPostView"), body=V("NewsPostInput"), feature="NEWS_FEED",
           perms=P("COMMUNICATION_MANAGE", "COMMUNICATION_SCOPED"))
    c.post("/news/{postId}/media", "uploadNewsMedia", "Attach a photo (<= 2 MB) or video (<= 50 MB); stored in the branch's Drive/Dropbox",
           V("NewsMediaView"), multipart=V("FileUpload"), feature="NEWS_FEED", perms=P("COMMUNICATION_MANAGE", "COMMUNICATION_SCOPED"))
    c.get("/news/{postId}/media/{mediaId}", "streamNewsMedia", "Stream media through the app server", binary=True, feature="NEWS_FEED")
    c.put("/news/{postId}/reaction", "react", "Set my reaction", body=V("ReactionInput"), feature="NEWS_FEED")
    c.delete("/news/{postId}/reaction", "unreact", "Remove my reaction", feature="NEWS_FEED")
    c.delete("/news/{postId}", "deleteNewsPost", "Delete a post (author or manager)", feature="NEWS_FEED")
    c.get("/calendar", "listCalendar", "Holidays, events, PTMs, exams in a date range", arr(E("calendar.event")),
          feature="CALENDAR", query=[("from", "d"), ("to", "d")])
    c.get("/consents", "listConsents", "Consent forms waiting for me or answered by me", arr(V("ConsentFormStatus")),
          feature="CONSENT")
    c.post("/consents/{formId}/decision", "decideConsent", "Grant, decline or withdraw consent", V("ConsentFormStatus"),
           body=V("ConsentDecisionInput"), feature="CONSENT")
    c.get("/conversations", "listConversations", "My conversations (parent <-> staff, class groups, helpdesk)",
          V("ConversationSummary"), paged=True, feature="COMMUNICATION")
    c.post("/conversations", "createConversation", "Start a parent <-> staff conversation (within chat hours)",
           V("ConversationSummary"), body=V("NewConversationInput"), feature="COMMUNICATION")
    c.get("/conversations/{conversationId}/messages", "listMessages", "Messages, newest first", V("MessageView"),
          paged=True, feature="COMMUNICATION")
    c.post("/conversations/{conversationId}/messages", "sendMessage", "Send a message", V("MessageView"),
           body=V("MessageInput"), feature="COMMUNICATION")
    c.post("/conversations/{conversationId}/read", "markConversationRead", "Mark read", feature="COMMUNICATION")
    c.post("/scan", "resolveScan", "Scan hub: one scanner for every code, routed by code type and my role",
           V("ScanResult"), body=V("ScanRequest"))
    c.post("/files", "uploadFile", "Upload an attachment (bill photo, document, homework file)", V("FileRef"),
           multipart=V("FileUpload"))
    c.get("/me/shift", "getMyShift", "My shift, post, punch-in time and week roster", V("MyShift"), feature="STAFF_PRESENCE")
    c.get("/me/presence", "listMyPresence", "My month of presence", arr(E("operations.daily_presence")),
          feature="STAFF_PRESENCE", perms=P("STAFF_PRESENCE_SELF", "STAFF_PRESENCE_VIEW", "STAFF_PRESENCE_MANAGE"),
          query=[("month", "s", "yyyy-MM")])
    c.post("/me/presence/corrections", "requestPresenceCorrection", "Request a correction (goes to School Admin or Principal)",
           V("ApprovalItem"), body=V("PresenceCorrectionInput"), feature="STAFF_PRESENCE")
    c.post("/me/shift-swaps", "requestShiftSwap", "Request a shift swap", V("ApprovalItem"), body=V("ShiftSwapInput"),
           feature="STAFF_PRESENCE")
    c.get("/me/leave/balances", "listMyLeaveBalances", "Leave balances", arr(E("hr.leave_balance")), feature="HR_PAYROLL")
    c.get("/me/leave", "listMyLeave", "My leave requests", E("hr.leave_request"), paged=True, feature="HR_PAYROLL")
    c.post("/me/leave", "applyLeave", "Apply for leave", E("hr.leave_request"),
           body=I("hr.leave_request", drop=("user_id", "approver_user_id", "decided_at", "days")), feature="HR_PAYROLL")
    c.delete("/me/leave/{leaveRequestId}", "cancelLeave", "Cancel a pending leave request", feature="HR_PAYROLL")
    c.get("/me/payslips", "listMyPayslips", "My payslips", arr(V("PayslipSummary")), feature="HR_PAYROLL")
    c.get("/me/payslips/{payslipId}/pdf", "downloadMyPayslip", "Payslip PDF (behind the app PIN)", binary=True,
          feature="HR_PAYROLL")

    # ===================================================================== Administrator
    a = actor("admin", "Administrator", ["ADMIN"], "Management / correspondent: governance, money above the Principal's band, "
              "branch comparisons (org-wide when granted at organization level)")
    a.get("/home", "getHome", "Critical incidents, approvals above band, today's KPIs, 30-day trends", V("HomeFeed"))
    a.get("/overview", "getOverview", "KPI tiles for this branch or all branches", V("Dashboard"),
          query=[("scope", "{BRANCH|ALL_BRANCHES}")])
    a.get("/branches/comparison", "compareBranches", "Fees, attendance, admissions funnel, expenses, occupancy by branch",
          V("BranchComparison"), query=[("metric", "{FEES|ATTENDANCE|ADMISSIONS|EXPENSES|OCCUPANCY}")])
    a.get("/finance/collections", "getCollections", "Collections vs target", V("CollectionSummary"),
          feature="FEE_MANAGEMENT", perms=P("FEE_MANAGEMENT_REPORT"), query=[("from", "d"), ("to", "d")])
    a.get("/finance/dues-aging", "getDuesAging", "Dues aging", V("DuesAging"), feature="FEE_MANAGEMENT", perms=P("FEE_MANAGEMENT_REPORT"))
    a.get("/finance/budgets", "getBudgetUtilization", "Expense vs budget by cost centre", arr(V("BudgetUtilization")),
          feature="EXPENSES", perms=P("EXPENSES_REPORT"), query=[("academicYearId", "b")])
    a.get("/academics/summary", "getAcademicSummary", "Academic aggregates (no marks entry, no names)", V("AcademicSummary"),
          feature="ACADEMICS", perms=P("ACADEMICS_REPORT"), query=[("termId", "b")])
    a.get("/hostel/occupancy", "getOccupancy", "Hostel occupancy", V("OccupancySummary"), feature="HOSTEL", perms=P("HOSTEL_REPORT"))
    a.get("/admissions/funnel", "getAdmissionsFunnel", "Admissions funnel", V("FunnelSummary"), feature="ADMISSIONS",
          perms=P("ADMISSIONS_REPORT"), query=[("academicYearId", "b")])
    a.get("/incidents", "listIncidents", "Incidents by severity (any branch in scope)", E("discipline.incident"), paged=True,
          feature="DISCIPLINE", query=[("severity", "{MINOR|MODERATE|MAJOR|CRITICAL}"), ("status", "s")])
    a.get("/consent-forms", "listConsentForms", "Consent forms and versions", arr(E("compliance.consent_form")), feature="CONSENT")
    a.post("/consent-forms", "createConsentForm", "Draft a consent form version", E("compliance.consent_form"),
           body=I("compliance.consent_form", drop=("published_at",)), feature="CONSENT", perms=P("CONSENT_FORM_MANAGE"))
    a.post("/consent-forms/{formId}/publish", "publishConsentForm", "Publish (asks everyone affected to sign)",
           E("compliance.consent_form"), feature="CONSENT", perms=P("CONSENT_FORM_MANAGE"))
    a.get("/reports", "listReports", "Saved reports (branch and org-wide)", arr(E("platform.saved_report")), feature="REPORTS")
    a.post("/reports", "createReport", "Save a report definition", E("platform.saved_report"), body=I("platform.saved_report"),
           feature="REPORTS")
    a.post("/reports/{reportId}/run", "runReport", "Run a report now (export job)", V("SavedReportRun"), feature="REPORTS")
    a.get("/approval-rules", "listApprovalRules", "Approval bands (fixed in phase 1)", arr(E("accounts.approval_rule")),
          feature="EXPENSES")

    # ===================================================================== Principal
    p = actor("principal", "Principal", ["PRINCIPAL"], "Runs the branch day to day: pulse, cover board, presence, academics, "
              "incidents, circulars")
    p.get("/home", "getHome", "07:30 view: missing students, uncovered periods, staff not punched in, approvals", V("HomeFeed"))
    p.get("/pulse", "getPulse", "Live attendance %, staff present/late/on leave, hostellers in/out", V("Dashboard"))
    p.get("/cover-board", "getCoverBoard", "Absent teachers, uncovered periods, suggested substitutes", V("CoverBoard"),
          feature="TIMETABLE", perms=P("STAFF_PRESENCE_MANAGE", "ACADEMICS_MANAGE"), query=[("date", "d")])
    p.post("/substitutions", "createSubstitution", "Assign a substitute (they are notified)", E("operations.substitution"),
           body=V("SubstitutionInput"), feature="TIMETABLE", perms=P("ACADEMICS_MANAGE"))
    p.delete("/substitutions/{substitutionId}", "deleteSubstitution", "Remove a substitution", feature="TIMETABLE",
             perms=P("ACADEMICS_MANAGE"))
    p.get("/staff-presence", "listStaffPresence", "Staff presence register (own row locked)", V("StaffPresenceRow"),
          paged=True, feature="STAFF_PRESENCE", perms=P("STAFF_PRESENCE_VIEW", "STAFF_PRESENCE_MANAGE"),
          query=[("date", "d"), ("department", "s"), ("status", "s")])
    p.patch("/staff-presence/{presenceId}", "correctStaffPresence", "Correct a presence row (never your own)",
            E("operations.daily_presence"), body=V("PresenceCorrection"), feature="STAFF_PRESENCE", perms=P("STAFF_PRESENCE_MANAGE"))
    p.get("/academics/heatmap", "getHeatmap", "Class x subject averages", V("Heatmap"), feature="ACADEMICS",
          perms=P("ACADEMICS_VIEW", "ACADEMICS_REPORT"), query=[("termId", "b")])
    p.get("/exams/{examId}/distribution", "getMarksDistribution", "Marks distribution of an exam", V("MarksDistribution"),
          feature="EXAMS", perms=P("ACADEMICS_VIEW"))
    p.get("/syllabus-coverage", "getSyllabusCoverage", "Coverage % from lesson plans", arr(V("CoverageRow")),
          feature="LESSON_PLANS", perms=P("ACADEMICS_VIEW", "ACADEMICS_REPORT"))
    p.get("/incidents", "listIncidents", "Incidents by severity", E("discipline.incident"), paged=True, feature="DISCIPLINE",
          query=[("severity", "s"), ("status", "s")])
    p.post("/incidents", "createIncident", "Open an incident", E("discipline.incident"), body=I("discipline.incident"),
           feature="DISCIPLINE")
    p.patch("/incidents/{incidentId}", "updateIncident", "Assign, change status, close", E("discipline.incident"),
            body=I("discipline.incident"), feature="DISCIPLINE")
    p.post("/incidents/{incidentId}/actions", "addDisciplineAction", "Record an action (warning, outing ban, meeting ...)",
           E("discipline.action"), body=I("discipline.action", drop=("incident_id", "parent_notified_at")), feature="DISCIPLINE")
    p.get("/circulars", "listCirculars", "Circulars sent", E("communication.notification"), paged=True, feature="COMMUNICATION")
    p.post("/circulars", "sendCircular", "Compose a circular with audience and acknowledgement", E("communication.notification"),
           body=V("CircularInput"), feature="COMMUNICATION", perms=P("COMMUNICATION_MANAGE"))
    p.get("/circulars/{notificationId}/reads", "getReadReceipts", "Who has read / acknowledged", V("ReadReceiptSummary"),
          feature="COMMUNICATION")
    p.get("/report-cards", "listReportCards", "Report cards by status", E("assessment.report_card"), paged=True,
          feature="REPORT_CARDS", query=[("termId", "b"), ("status", "{DRAFT|APPROVED|PUBLISHED|WITHHELD}"), ("classSectionId", "b")])
    p.post("/report-cards/publish", "publishReportCards", "Publish approved report cards", V("BulkResult"), body=V("IdList"),
           feature="REPORT_CARDS", perms=P("ACADEMICS_MANAGE", "RECORDS_APPROVE"))
    p.post("/calendar/events", "createEvent", "Add a holiday / event / PTM day", E("calendar.event"), body=I("calendar.event"),
           feature="CALENDAR", perms=P("COMMUNICATION_MANAGE", "ACADEMICS_MANAGE"))
    p.patch("/calendar/events/{eventId}", "updateEvent", "Change an event", E("calendar.event"), body=I("calendar.event"),
            feature="CALENDAR", perms=P("COMMUNICATION_MANAGE", "ACADEMICS_MANAGE"))
    p.delete("/calendar/events/{eventId}", "deleteEvent", "Delete an event", feature="CALENDAR",
             perms=P("COMMUNICATION_MANAGE", "ACADEMICS_MANAGE"))
    p.get("/timetable/versions", "listTimetableVersions", "Timetable versions", arr(E("academics.timetable_version")),
          feature="TIMETABLE")
    p.post("/timetable/versions/{timetableVersionId}/publish", "publishTimetable", "Publish a timetable version",
           E("academics.timetable_version"), feature="TIMETABLE", perms=P("ACADEMICS_MANAGE"))

    # ===================================================================== School Admin
    s = actor("schooladmin", "SchoolAdmin", ["SCHOOL_ADMIN"], "Office head: setup checklist, students, staff, sections & "
              "subjects, timetable, exams, fee setup, records, imports, devices & posts")
    s.get("/home", "getHome", "Setup checklist (new branch) or office queue (running branch)", V("HomeFeed"))
    s.get("/setup-checklist", "getSetupChecklist", "Branch setup progress", V("SetupChecklist"))
    s.get("/students", "listStudents", "Students", E("academics.student"), paged=True, feature="ACADEMICS",
          perms=P("ACADEMICS_VIEW", "ACADEMICS_MANAGE"), query=[("q", "s"), ("classSectionId", "b"), ("status", "s")])
    s.post("/students", "createStudent", "Admit a student (then link or invite parents)", E("academics.student"),
           body=I("academics.student"), feature="ACADEMICS", perms=P("ACADEMICS_MANAGE"))
    s.get("/students/{studentId}", "getStudentProfile", "Student profile", V("StudentProfile"), feature="ACADEMICS",
          perms=P("ACADEMICS_VIEW", "ACADEMICS_MANAGE"))
    s.patch("/students/{studentId}", "updateStudent", "Update a student", E("academics.student"), body=I("academics.student"),
            feature="ACADEMICS", perms=P("ACADEMICS_MANAGE"))
    s.post("/students/{studentId}/parents", "linkParent", "Link a parent (existing user or invite)", E("academics.student_parent"),
           body=V("ParentLinkInput"), feature="ACADEMICS", perms=P("ACADEMICS_MANAGE"))
    s.delete("/students/{studentId}/parents/{userId}", "unlinkParent", "Unlink a parent", feature="ACADEMICS",
             perms=P("ACADEMICS_MANAGE"))
    s.post("/students/{studentId}/enrollments", "enrollStudent", "Enroll / promote / transfer", E("academics.student_enrollment"),
           body=I("academics.student_enrollment", drop=("student_id",)), feature="ACADEMICS", perms=P("ACADEMICS_MANAGE"))
    s.get("/staff", "listStaff", "Employees", E("hr.employee_profile"), paged=True, feature="HR_PAYROLL",
          perms=P("HR_PAYROLL_VIEW", "HR_PAYROLL_REPORT", "STAFF_PRESENCE_MANAGE"), query=[("q", "s"), ("category", "s")])
    s.put("/staff/{userId}", "upsertEmployee", "Create or update an employee profile", E("hr.employee_profile"),
          body=I("hr.employee_profile", drop=("user_id", "vault_ref")), feature="HR_PAYROLL", perms=P("STAFF_PRESENCE_MANAGE", "HR_PAYROLL_MANAGE"))
    s.put("/staff/{userId}/teacher-metadata", "upsertTeacherMetadata", "Teaching-only details", E("hr.teacher_metadata"),
          body=I("hr.teacher_metadata", drop=("user_id",)), feature="ACADEMICS", perms=P("ACADEMICS_MANAGE"))
    for path, op, table, label in [("/academic-years", "AcademicYear", "academics.academic_year", "Academic years"),
                                   ("/departments", "Department", "academics.department", "Departments"),
                                   ("/programs", "Program", "academics.program", "Programs / grades"),
                                   ("/class-sections", "ClassSection", "academics.class_section", "Sections / batches"),
                                   ("/subjects", "Subject", "academics.subject", "Subjects"),
                                   ("/periods", "Period", "academics.period", "Period timings"),
                                   ("/grade-scales", "GradeScale", "assessment.grade_scale", "Grading scales"),
                                   ("/exam-sessions", "ExamSession", "assessment.exam_session", "Exam sessions"),
                                   ("/fee-heads", "FeeHead", "finance.fee_head", "Fee heads"),
                                   ("/fee-structures", "FeeStructure", "finance.fee_structure", "Fee structures")]:
        feat = {"academics": "ACADEMICS", "assessment": "EXAMS", "finance": "FEE_MANAGEMENT"}[table.split(".")[0]]
        if table == "academics.period":
            feat = "TIMETABLE"
        # Fee setup needs FEE_MANAGEMENT_MANAGE: the UX v2 matrix gives School Admin only R on fees,
        # so a branch grants it to School Admin (role override) if the office sets up fees
        perm = "FEE_MANAGEMENT_MANAGE" if feat == "FEE_MANAGEMENT" else "ACADEMICS_MANAGE"
        s.get(path, "list" + op + "s", label, arr(E(table)), feature=feat)
        s.post(path, "create" + op, "Add: " + label.lower(), E(table), body=I(table), feature=feat, perms=P(perm))
        s.patch(path + "/{id}", "update" + op, "Change: " + label.lower(), E(table), body=I(table), feature=feat, perms=P(perm))
    s.post("/academic-years/{academicYearId}/terms", "createTerm", "Add a term / semester", E("academics.academic_term"),
           body=I("academics.academic_term", drop=("academic_year_id",)), feature="ACADEMICS", perms=P("ACADEMICS_MANAGE"))
    s.post("/staff-subjects", "assignSubject", "Assign a subject to a teacher", E("academics.staff_subject"),
           body=I("academics.staff_subject"), feature="ACADEMICS", perms=P("ACADEMICS_MANAGE"))
    s.post("/timetable/versions", "createTimetableVersion", "New timetable version", E("academics.timetable_version"),
           body=I("academics.timetable_version"), feature="TIMETABLE", perms=P("ACADEMICS_MANAGE"))
    s.get("/timetable", "getTimetableGrid", "Period x day grid of a section", V("TimetableGrid"), feature="TIMETABLE",
          query=[("classSectionId", "b"), ("timetableVersionId", "b")])
    s.put("/timetable/versions/{timetableVersionId}/slots", "saveTimetableSlots",
          "Save slots; returns clashes (teacher shift, double booking, room)", V("TimetableValidation"),
          body=V("TimetableSlotsInput"), feature="TIMETABLE", perms=P("ACADEMICS_MANAGE"))
    s.post("/exams", "createExam", "Schedule an exam paper", E("assessment.exams"), body=I("assessment.exams"),
           feature="EXAMS", perms=P("ACADEMICS_MANAGE"))
    s.post("/exam-sessions/{examSessionId}/hall-tickets", "generateHallTickets", "Generate hall tickets (dues hold applies)",
           V("BulkResult"), feature="EXAMS", perms=P("ACADEMICS_MANAGE"))
    s.post("/exams/{examId}/seating", "generateSeating", "Generate seating", arr(E("assessment.seating")), feature="EXAMS",
           perms=P("ACADEMICS_MANAGE"))
    s.post("/fee-structures/{feeStructureId}/installments", "addInstallment", "Add an installment", E("finance.fee_installment"),
           body=I("finance.fee_installment", drop=("fee_structure_id",)), feature="FEE_MANAGEMENT", perms=P("FEE_MANAGEMENT_MANAGE"))
    s.post("/fee-structures/{feeStructureId}/generate-demands", "generateDemands", "Create fee demands for assigned students",
           V("BulkResult"), feature="FEE_MANAGEMENT", perms=P("FEE_MANAGEMENT_MANAGE"))
    s.get("/certificates", "listCertificates", "Certificate requests and issued certificates", E("records.certificate"),
          paged=True, feature="RECORDS", query=[("studentId", "b"), ("status", "s")])
    s.post("/certificates", "requestCertificate", "Generate from template and send for approval", E("records.certificate"),
           body=I("records.certificate", drop=("serial_number", "verification_code", "issued_on", "document_id", "revoked_at")),
           feature="RECORDS", perms=P("RECORDS_MANAGE"))
    s.post("/certificates/{certificateId}/revoke", "revokeCertificate", "Revoke a certificate", E("records.certificate"),
           body=V("ReasonInput"), feature="RECORDS", perms=P("RECORDS_MANAGE"))
    s.get("/clearances", "listClearances", "No-dues clearance desks for a student", arr(E("records.clearance")),
          feature="RECORDS", query=[("studentId", "b"), ("purpose", "s")])
    s.get("/documents", "listDocuments", "Documents of a student / staff / application", arr(E("records.document")),
          feature="RECORDS", query=[("ownerKind", "s"), ("ownerId", "b")])
    s.post("/documents/{documentId}/verify", "verifyDocument", "Mark a document verified", E("records.document"),
           feature="RECORDS", perms=P("RECORDS_MANAGE"))
    s.get("/imports", "listImports", "Import jobs", E("platform.import_job"), paged=True, feature="BULK_IMPORT")
    s.post("/imports", "createImport", "Upload a spreadsheet (dry run first)", E("platform.import_job"),
           multipart=V("ImportUpload"), feature="BULK_IMPORT")
    s.get("/imports/{importJobId}", "getImport", "Import status and error report", E("platform.import_job"), feature="BULK_IMPORT")
    s.post("/imports/{importJobId}/run", "runImport", "Import for real (or re-run the failed rows)", E("platform.import_job"),
           feature="BULK_IMPORT")
    s.get("/posts", "listPosts", "Posts (gate, front desk, library counter, sick bay, mess ...)", arr(E("hr.post")))
    s.post("/posts", "createPost", "Add a post", E("hr.post"), body=I("hr.post", drop=("device_id",)),
           perms=P("SECURITY_MANAGE", "STAFF_PRESENCE_MANAGE"))
    s.put("/posts/{postId}/device", "bindDevice", "Bind a gate reader / kiosk tablet to a post", E("hr.post"),
          body=V("DeviceBinding"), perms=P("SECURITY_MANAGE", "STAFF_PRESENCE_MANAGE"))
    s.post("/notifications", "sendNotification", "Send a notification / circular", E("communication.notification"),
           body=V("CircularInput"), feature="COMMUNICATION", perms=P("COMMUNICATION_MANAGE"))
    s.get("/templates", "listTemplates", "Message templates (platform defaults + branch)", arr(E("communication.template")),
          feature="COMMUNICATION")
    s.post("/templates", "createTemplate", "Add a branch template", E("communication.template"),
           body=I("communication.template"), feature="COMMUNICATION", perms=P("COMMUNICATION_MANAGE"))
    s.get("/messaging-policy", "getMessagingPolicy", "Chat hours and messaging rules", E("communication.messaging_policy"),
          feature="COMMUNICATION")
    s.put("/messaging-policy", "setMessagingPolicy", "Set chat hours and messaging rules", E("communication.messaging_policy"),
          body=I("communication.messaging_policy"), feature="COMMUNICATION", perms=P("COMMUNICATION_MANAGE"))

    # ===================================================================== Accountant
    ac = actor("accountant", "Accountant", ["ACCOUNTANT"], "Fee counter and books: collections, demands, concessions, refunds, "
               "expenses, petty cash, budgets, payroll processing, vendor invoices, Tally export")
    F = "FEE_MANAGEMENT"
    ac.get("/home", "getHome", "Bounces, unmatched gateway payments, petty cash due, collections today, defaulters", V("HomeFeed"))
    ac.get("/counter/search", "searchFamilies", "Find a family by name, admission no., phone or ID card", arr(V("PersonRef")),
           feature=F, perms=P("FEE_MANAGEMENT_MANAGE"), query=[("q", "s")])
    ac.get("/students/{studentId}/dues", "getFamilyDues", "Dues of the student and siblings", V("FamilyDues"), feature=F,
           perms=P("FEE_MANAGEMENT_MANAGE", "FEE_MANAGEMENT_VIEW"))
    ac.get("/receipts/next-number", "previewReceiptNumber", "Next gap-free receipt number", V("ReceiptNumberPreview"),
           feature=F, perms=P("FEE_MANAGEMENT_MANAGE"))
    ac.post("/payments", "receivePayment", "Receive at the counter; prints and sends the receipt", V("PaymentReceipt"),
            body=V("CounterPaymentInput"), feature=F, perms=P("FEE_MANAGEMENT_MANAGE"))
    ac.get("/payments", "listPayments", "Payments", E("finance.payment"), paged=True, feature=F,
           perms=P("FEE_MANAGEMENT_MANAGE", "FEE_MANAGEMENT_VIEW"), query=[("from", "d"), ("to", "d"), ("mode", "s"), ("status", "s")])
    ac.get("/payments/{paymentId}/receipt", "downloadReceipt", "Receipt PDF", binary=True, feature=F)
    ac.post("/payments/{paymentId}/bounce", "markBounced", "Cheque bounced: reverse allocations, add a charge",
            E("finance.payment"), body=V("BounceInput"), feature=F, perms=P("FEE_MANAGEMENT_MANAGE"))
    ac.get("/gateway/unmatched", "listUnmatchedGatewayPayments", "Gateway payments not matched to demands",
           arr(E("finance.payment")), feature=F, perms=P("FEE_MANAGEMENT_MANAGE"))
    ac.get("/demands", "listDemands", "Fee demands", E("finance.fee"), paged=True, feature=F,
           perms=P("FEE_MANAGEMENT_MANAGE", "FEE_MANAGEMENT_VIEW"), query=[("status", "s"), ("classSectionId", "b"), ("headId", "b")])
    ac.post("/demands", "createDemand", "Manual demand", E("finance.fee"), body=I("finance.fee", drop=("paid_amount", "remaining_due")),
            feature=F, perms=P("FEE_MANAGEMENT_MANAGE"))
    ac.post("/demands/{feeId}/waive", "requestWaiver", "Request a waiver (approval)", V("ApprovalItem"), body=V("ReasonInput"),
            feature=F, perms=P("FEE_MANAGEMENT_MANAGE"))
    ac.get("/defaulters", "listDefaulters", "Defaulters by aging bucket", V("DefaulterRow"), paged=True, feature=F,
           query=[("bucket", "{D0_30|D31_60|D60_PLUS}"), ("classSectionId", "b")])
    ac.get("/concessions", "listConcessions", "Concessions", E("finance.student_concession"), paged=True, feature=F)
    ac.post("/concessions", "requestConcession", "Request a concession (Principal approves)", E("finance.student_concession"),
            body=I("finance.student_concession", drop=("approved_at",)), feature=F, perms=P("FEE_MANAGEMENT_MANAGE"))
    ac.get("/refunds", "listRefunds", "Refunds", E("finance.refund"), paged=True, feature=F)
    ac.post("/refunds", "requestRefund", "Request a refund (approval)", E("finance.refund"),
            body=I("finance.refund", drop=("gateway_refund_id", "refunded_at")), feature=F, perms=P("FEE_MANAGEMENT_MANAGE"))
    ac.get("/day-close", "getDayClose", "Cash count vs system for a day", V("DayClose"), feature=F, query=[("date", "d")])
    ac.post("/day-close", "closeDay", "Close the day with counted cash and deposit slip", V("DayClose"),
            body=V("DayCloseInput"), feature=F, perms=P("FEE_MANAGEMENT_MANAGE"))
    X = "EXPENSES"
    ac.get("/expenses", "listExpenses", "Expenses", E("accounts.expense"), paged=True, feature=X,
           query=[("status", "s"), ("costCentre", "s"), ("from", "d"), ("to", "d")])
    ac.post("/expenses", "createExpense", "Expense with bill photo; routed to an approver by band", E("accounts.expense"),
            body=I("accounts.expense", drop=("paid_at", "voucher_number")), feature=X, perms=P("EXPENSES_MANAGE"))
    ac.patch("/expenses/{expenseId}", "updateExpense", "Edit a draft expense", E("accounts.expense"),
             body=I("accounts.expense", drop=("paid_at", "voucher_number")), feature=X, perms=P("EXPENSES_MANAGE"))
    ac.post("/expenses/{expenseId}/submit", "submitExpense", "Submit for approval", V("ApprovalItem"), feature=X,
            perms=P("EXPENSES_MANAGE"))
    ac.post("/expenses/{expenseId}/pay", "payExpense", "Record payment of an approved expense", E("accounts.expense"),
            body=V("PayExpenseInput"), feature=X, perms=P("EXPENSES_MANAGE"))
    ac.get("/petty-cash", "listPettyCash", "Petty cash accounts", arr(E("accounts.petty_cash_account")), feature=X)
    ac.post("/petty-cash/{pettyCashId}/transactions", "recordPettyCash", "Top up, spend, return or settle",
            E("accounts.petty_cash_txn"), body=I("accounts.petty_cash_txn", drop=("petty_cash_id", "txn_at")), feature=X,
            perms=P("EXPENSES_MANAGE"))
    ac.get("/budgets", "listBudgets", "Budgets with utilization", arr(V("BudgetUtilization")), feature=X, query=[("academicYearId", "b")])
    ac.post("/budgets", "createBudget", "Add a budget line", E("accounts.budget"), body=I("accounts.budget"), feature=X,
            perms=P("EXPENSES_MANAGE"))
    ac.get("/vendor-invoices", "listVendorInvoices", "Vendor invoices", E("inventory.vendor_invoice"), paged=True, feature=X)
    ac.post("/vendor-invoices", "createVendorInvoice", "Record a vendor invoice", E("inventory.vendor_invoice"),
            body=I("inventory.vendor_invoice", drop=("match_status",)), feature=X, perms=P("EXPENSES_MANAGE"))
    ac.post("/vendor-invoices/{invoiceId}/match", "matchInvoice", "3-way match against PO and GRN", V("ThreeWayMatch"),
            feature=X, perms=P("EXPENSES_MANAGE"))
    ac.get("/payroll/runs", "listPayrollRuns", "Payroll runs", arr(E("hr.payroll_run")), feature="HR_PAYROLL",
           perms=P("HR_PAYROLL_SCOPED", "HR_PAYROLL_VIEW"))
    ac.post("/payroll/runs/{runId}/process", "processPayroll", "Process an approved run (bank file); can't approve it",
            E("hr.payroll_run"), feature="HR_PAYROLL", perms=P("HR_PAYROLL_SCOPED"))
    ac.post("/exports/tally", "exportTally", "Tally export", E("platform.export_job"), body=V("TallyExportInput"), feature="REPORTS")

    # ===================================================================== HR Manager
    h = actor("hrmanager", "HrManager", ["HR_MANAGER"], "People, leave, shifts & roster, presence exceptions, payroll, recruitment")
    HR = "HR_PAYROLL"
    h.get("/home", "getHome", "Leave and swap requests, corrections, missing payroll inputs, roster gaps", V("HomeFeed"))
    h.get("/people", "listPeople", "Employees", E("hr.employee_profile"), paged=True, feature=HR,
          perms=P("HR_PAYROLL_VIEW", "HR_PAYROLL_MANAGE"), query=[("q", "s"), ("department", "b"), ("status", "s")])
    h.get("/people/{userId}", "getPerson", "Employee profile (vault data masked)", E("hr.employee_profile"), feature=HR)
    h.put("/people/{userId}", "upsertPerson", "Create / update an employee profile", E("hr.employee_profile"),
          body=I("hr.employee_profile", drop=("user_id",)), feature=HR, perms=P("HR_PAYROLL_MANAGE"))
    h.post("/people/{userId}/vault/{field}", "revealVaultField", "Reveal a masked field (logged)", V("VaultReveal"),
           feature=HR, perms=P("HR_PAYROLL_MANAGE"))
    h.get("/leave-types", "listLeaveTypes", "Leave types", arr(E("hr.leave_type")), feature=HR)
    h.post("/leave-types", "createLeaveType", "Add a leave type", E("hr.leave_type"), body=I("hr.leave_type"), feature=HR,
           perms=P("HR_PAYROLL_MANAGE"))
    h.get("/leave-requests", "listLeaveRequests", "Leave requests (decide in Approvals)", E("hr.leave_request"), paged=True,
          feature=HR, query=[("status", "s"), ("from", "d"), ("to", "d")])
    h.get("/shifts", "listShifts", "Shifts", arr(E("hr.shift")), feature="STAFF_PRESENCE")
    h.post("/shifts", "createShift", "Add a shift", E("hr.shift"), body=I("hr.shift"), feature="STAFF_PRESENCE",
           perms=P("STAFF_PRESENCE_MANAGE", "HR_PAYROLL_MANAGE"))
    h.patch("/shifts/{shiftId}", "updateShift", "Change a shift", E("hr.shift"), body=I("hr.shift"), feature="STAFF_PRESENCE",
            perms=P("STAFF_PRESENCE_MANAGE", "HR_PAYROLL_MANAGE"))
    h.get("/shift-assignments", "listShiftAssignments", "Shift patterns per person", arr(E("hr.shift_assignment")),
          feature="STAFF_PRESENCE", query=[("userId", "b")])
    h.post("/shift-assignments", "createShiftAssignment", "Assign a shift pattern", E("hr.shift_assignment"),
           body=I("hr.shift_assignment"), feature="STAFF_PRESENCE", perms=P("STAFF_PRESENCE_MANAGE", "HR_PAYROLL_MANAGE"))
    h.get("/roster", "getRoster", "Roster week grid with gaps and conflicts", V("RosterWeek"), feature="STAFF_PRESENCE",
          query=[("weekStart", "d"), ("department", "b")])
    h.put("/roster", "updateRoster", "Assign / remove roster cells (rest-hour and double-shift checks)", V("RosterWeek"),
          body=V("RosterUpdate"), feature="STAFF_PRESENCE", perms=P("STAFF_PRESENCE_MANAGE", "HR_PAYROLL_MANAGE"))
    h.get("/presence/exceptions", "listPresenceExceptions", "Late, absent without leave, no punch-out", arr(V("PresenceException")),
          feature="STAFF_PRESENCE", query=[("date", "d")])
    h.get("/salary-components", "listSalaryComponents", "Salary components", arr(E("hr.salary_component")), feature=HR)
    h.post("/salary-components", "createSalaryComponent", "Add a component", E("hr.salary_component"),
           body=I("hr.salary_component"), feature=HR, perms=P("HR_PAYROLL_MANAGE"))
    h.get("/people/{userId}/salary-structure", "getSalaryStructure", "Current salary structure", E("hr.salary_structure"), feature=HR)
    h.post("/people/{userId}/salary-structure", "createSalaryStructure", "New salary structure (effective date)",
           E("hr.salary_structure"), body=I("hr.salary_structure", drop=("user_id",)), feature=HR, perms=P("HR_PAYROLL_MANAGE"))
    h.get("/payroll/runs", "listPayrollRuns", "Payroll runs", arr(E("hr.payroll_run")), feature=HR)
    h.post("/payroll/runs", "createPayrollRun", "Start a run for a period", E("hr.payroll_run"), body=V("PayrollRunInput"),
           feature=HR, perms=P("HR_PAYROLL_MANAGE"))
    h.post("/payroll/runs/{runId}/compute", "computePayroll", "Pull LOP / overtime from presence and compute payslips",
           E("hr.payroll_run"), feature=HR, perms=P("HR_PAYROLL_MANAGE"))
    h.get("/payroll/runs/{runId}/exceptions", "listPayrollExceptions", "Exceptions to review", arr(V("PayrollException")), feature=HR)
    h.post("/payroll/runs/{runId}/submit", "submitPayroll", "Send for approval (Principal -> Administrator)", V("ApprovalItem"),
           feature=HR, perms=P("HR_PAYROLL_MANAGE"))
    h.get("/job-openings", "listJobOpenings", "Job openings", arr(E("hr.job_opening")), feature=HR)
    h.post("/job-openings", "createJobOpening", "Open a position", E("hr.job_opening"), body=I("hr.job_opening"), feature=HR,
           perms=P("HR_PAYROLL_MANAGE"))
    h.get("/job-openings/{openingId}/candidates", "listCandidates", "Candidates", arr(E("hr.candidate")), feature=HR)
    h.post("/job-openings/{openingId}/candidates", "addCandidate", "Add a candidate", E("hr.candidate"),
           body=I("hr.candidate", drop=("opening_id",)), feature=HR, perms=P("HR_PAYROLL_MANAGE"))
    h.patch("/candidates/{candidateId}", "updateCandidate", "Move a candidate between stages", E("hr.candidate"),
            body=I("hr.candidate"), feature=HR, perms=P("HR_PAYROLL_MANAGE"))

    # ===================================================================== Admission Officer
    ad = actor("admissionofficer", "AdmissionOfficer", ["ADMISSION_OFFICER"], "Enquiry and admission pipeline, tests, seat matrix, conversion")
    AD = "ADMISSIONS"
    ad.get("/home", "getHome", "Follow-ups due, new web enquiries, applications missing documents, test slots", V("HomeFeed"))
    ad.post("/enquiries", "createEnquiry", "Quick enquiry with duplicate check by phone", V("EnquiryWithDuplicates"),
            body=V("QuickEnquiryInput"), feature=AD, perms=P("ADMISSIONS_MANAGE", "ADMISSIONS_SCOPED"))
    ad.get("/enquiries", "listEnquiries", "Enquiries", E("admissions.enquiry"), paged=True, feature=AD,
           query=[("stage", "s"), ("q", "s"), ("ownerUserId", "b"), ("source", "s")])
    ad.get("/enquiries/{enquiryId}", "getEnquiry", "Enquiry with follow-ups", E("admissions.enquiry"), feature=AD)
    ad.patch("/enquiries/{enquiryId}", "updateEnquiry", "Move stage (LOST needs a reason), owner, next follow-up",
             E("admissions.enquiry"), body=V("EnquiryUpdate"), feature=AD, perms=P("ADMISSIONS_MANAGE"))
    ad.post("/enquiries/{enquiryId}/follow-ups", "addFollowUp", "Log a call / WhatsApp / visit", E("admissions.enquiry_follow_up"),
            body=I("admissions.enquiry_follow_up", drop=("enquiry_id", "done_at")), feature=AD, perms=P("ADMISSIONS_MANAGE"))
    ad.get("/follow-ups/due", "listDueFollowUps", "Follow-ups due", arr(E("admissions.enquiry")), feature=AD, query=[("date", "d")])
    ad.get("/pipeline", "getPipeline", "Kanban by stage", V("Pipeline"), feature=AD, query=[("academicYearId", "b")])
    ad.get("/applications", "listApplications", "Applications", E("admissions.application"), paged=True, feature=AD,
           query=[("status", "s"), ("programId", "b")])
    ad.post("/applications", "createApplication", "Create an application", E("admissions.application"),
            body=I("admissions.application", drop=("application_number", "decided_at", "submitted_at", "student_id", "application_fee_id")),
            feature=AD, perms=P("ADMISSIONS_MANAGE"))
    ad.get("/applications/{applicationId}", "getApplication", "Application", E("admissions.application"), feature=AD)
    ad.patch("/applications/{applicationId}", "updateApplication", "Edit form data", E("admissions.application"),
             body=I("admissions.application", drop=("application_number", "decided_at", "submitted_at", "student_id", "application_fee_id")),
             feature=AD, perms=P("ADMISSIONS_MANAGE"))
    ad.post("/applications/{applicationId}/decision", "decideApplication", "Offer / waitlist / reject", E("admissions.application"),
            body=V("AdmissionDecision"), feature=AD, perms=P("ADMISSIONS_MANAGE"))
    ad.post("/applications/{applicationId}/assessments", "scheduleAssessment", "Schedule a test or interview",
            E("admissions.assessment"), body=I("admissions.assessment", drop=("application_id",)), feature=AD, perms=P("ADMISSIONS_MANAGE"))
    ad.patch("/assessments/{assessmentId}", "recordAssessment", "Record score and remarks", E("admissions.assessment"),
             body=I("admissions.assessment"), feature=AD, perms=P("ADMISSIONS_MANAGE"))
    ad.get("/applications/{applicationId}/conversion-preview", "previewConversion",
           "What conversion will create: student, parents, enrollment, first fee demand, hostel/transport requests",
           V("ConversionPreview"), feature=AD)
    ad.post("/applications/{applicationId}/convert", "convertApplication", "Confirm conversion", V("ConversionResult"),
            feature=AD, perms=P("ADMISSIONS_MANAGE"))
    ad.get("/seat-matrix", "getSeatMatrix", "Seats per program incl. RTE 25%; live remaining", arr(V("SeatMatrixRow")),
           feature=AD, query=[("academicYearId", "b")])
    ad.put("/seat-plans", "upsertSeatPlan", "Set seats for a program", E("admissions.seat_plan"), body=I("admissions.seat_plan"),
           feature=AD, perms=P("ADMISSIONS_MANAGE"))
    ad.get("/reenrollments", "listReenrollments", "Re-enrollment responses", E("admissions.reenrollment"), paged=True,
           feature=AD, query=[("academicYearId", "b"), ("status", "s")])
    ad.post("/reenrollments/invite", "inviteReenrollment", "Invite parents to confirm next year", V("BulkResult"),
            body=V("ReenrollmentInvite"), feature=AD, perms=P("ADMISSIONS_MANAGE"))
    ad.get("/reports/funnel", "getFunnel", "Funnel by source and stage", V("FunnelSummary"), feature=AD, query=[("academicYearId", "b")])

    # ===================================================================== Receptionist
    rc = actor("receptionist", "Receptionist", ["RECEPTIONIST"], "Front office (tablet kiosk): visitors, early leave and pickups, parcels, walk-in enquiries")
    G = "GATE"
    rc.get("/home", "getHome", "Visitors on campus, expected visitors, parcels waiting, early-leave requests", V("HomeFeed"))
    rc.get("/visitors/lookup", "lookupVisitor", "Returning visitor by phone", E("frontoffice.visitor"), feature=G, query=[("phone", "s")])
    rc.post("/visits", "checkInVisitor", "Check in (host approves on their phone; badge printed)", E("frontoffice.visit"),
            body=V("VisitCheckIn"), feature=G, perms=P("GATE_MANAGE", "GATE_SCOPED"))
    rc.get("/visits/on-campus", "listOnCampus", "Visitors on campus now", arr(E("frontoffice.visit")), feature=G)
    rc.get("/visits", "listVisits", "Visit log", E("frontoffice.visit"), paged=True, feature=G, query=[("date", "d")])
    rc.post("/visits/{visitId}/check-out", "checkOutVisitor", "Check out by badge scan", E("frontoffice.visit"), feature=G,
            perms=P("GATE_MANAGE", "GATE_SCOPED"))
    rc.get("/students/{studentId}/pickup-people", "listPickupPeople", "Authorised pickup list", arr(E("frontoffice.pickup_person")),
           feature=G)
    rc.post("/gate-passes", "createEarlyLeavePass", "Early leave: pick the pickup person, then photo match + parent OTP",
            E("frontoffice.gate_pass"), body=V("EarlyLeaveInput"), feature=G, perms=P("GATE_MANAGE"))
    rc.post("/gate-passes/{gatePassId}/verify", "verifyEarlyLeave", "Verify parent OTP; the guard then sees the pass",
            E("frontoffice.gate_pass"), body=V("OtpVerifyInput"), feature=G, perms=P("GATE_MANAGE"))
    rc.get("/gate-passes", "listGatePasses", "Gate passes of the day", arr(E("frontoffice.gate_pass")), feature=G, query=[("date", "d")])
    rc.post("/parcels", "logParcel", "Log a parcel and notify the recipient (warden for hostellers)", E("frontoffice.parcel"),
            body=I("frontoffice.parcel", drop=("received_at", "handed_over_at")), feature=G, perms=P("GATE_MANAGE"))
    rc.get("/parcels", "listParcels", "Parcels", arr(E("frontoffice.parcel")), feature=G, query=[("waitingOnly", "bo")])
    rc.post("/parcels/{parcelId}/handover", "handOverParcel", "Hand over with signature", E("frontoffice.parcel"),
            body=V("HandoverInput"), feature=G, perms=P("GATE_MANAGE"))
    rc.post("/enquiries", "createEnquiry", "Walk-in enquiry", V("EnquiryWithDuplicates"), body=V("QuickEnquiryInput"),
            feature="ADMISSIONS", perms=P("ADMISSIONS_SCOPED", "ADMISSIONS_MANAGE"))
    rc.get("/log", "getLog", "Front-office log of the day", arr(V("FrontOfficeLogEntry")), feature=G, query=[("date", "d")])

    # ===================================================================== Teacher
    t = actor("teacher", "Teacher", ["TEACHER"], "{Teacher} with duty overlays (class teacher, invigilator, escort): register, "
              "marks, homework, lesson plans, messages, PTM")
    A_ = P("ACADEMICS_SCOPED", "ACADEMICS_MANAGE")
    t.get("/home", "getHome", "Now card (current/next period), registers to take, marks due, homework to grade", V("HomeFeed"))
    t.get("/today", "getToday", "Period timeline with substitutions highlighted", arr(V("PeriodSlot")), feature="TIMETABLE",
          query=[("date", "d")])
    t.post("/timetable/{timetableId}/taught", "markTaught", "Mark a period taught (updates the lesson plan)", V("PeriodSlot"),
           body=V("TaughtInput"), feature="LESSON_PLANS", perms=A_)
    t.get("/classes", "listMyClasses", "My sections and subjects", arr(V("ClassSummary")), feature="ACADEMICS", perms=A_)
    t.get("/classes/{classSectionId}/students", "listClassStudents", "Students with alert flags", arr(V("StudentCard")),
          feature="ACADEMICS", perms=A_)
    t.get("/classes/{classSectionId}/register", "getRegister", "Register for a day (class teacher)", V("RegisterSheet"),
          feature="ATTENDANCE", perms=P("ATTENDANCE_SCOPED", "ATTENDANCE_MANAGE"), query=[("date", "d"), ("periodId", "b")])
    t.post("/classes/{classSectionId}/register", "submitRegister", "Submit: everyone present except the absentees sent",
           V("RegisterSheet"), body=V("RegisterSubmission"), feature="ATTENDANCE", perms=P("ATTENDANCE_SCOPED", "ATTENDANCE_MANAGE"))
    t.get("/offerings/{offeringId}/attendance", "getLectureAttendance", "Lecture attendance (college)", V("RegisterSheet"),
          feature="ATTENDANCE", perms=P("ATTENDANCE_SCOPED"), query=[("date", "d")])
    t.post("/offerings/{offeringId}/attendance", "submitLectureAttendance", "Submit lecture attendance", V("RegisterSheet"),
           body=V("RegisterSubmission"), feature="ATTENDANCE", perms=P("ATTENDANCE_SCOPED"))
    t.get("/exams", "listMyExams", "Exams I enter marks for", arr(E("assessment.exams")), feature="EXAMS", perms=A_,
          query=[("status", "s")])
    t.get("/exams/{examId}/marks", "getMarksSheet", "Marks grid", V("MarksSheet"), feature="EXAMS", perms=A_)
    t.put("/exams/{examId}/marks", "saveMarks", "Save marks (after lock: reason required, audited)", V("MarksSheet"),
          body=V("MarksEntryInput"), feature="EXAMS", perms=A_)
    t.post("/exams/{examId}/lock", "lockMarks", "Lock marks", V("MarksSheet"), feature="EXAMS", perms=A_)
    t.get("/homework", "listHomework", "Homework I set", E("operations.homework"), paged=True, feature="HOMEWORK", perms=A_,
          query=[("classSectionId", "b"), ("from", "d")])
    t.post("/homework", "createHomework", "Set homework for one or more sections", E("operations.homework"),
           body=I("operations.homework"), feature="HOMEWORK", perms=A_)
    t.patch("/homework/{homeworkId}", "updateHomework", "Edit homework", E("operations.homework"), body=I("operations.homework"),
            feature="HOMEWORK", perms=A_)
    t.delete("/homework/{homeworkId}", "deleteHomework", "Delete homework", feature="HOMEWORK", perms=A_)
    t.get("/homework/{homeworkId}/submissions", "listSubmissions", "Submissions", arr(E("operations.homework_submission")),
          feature="HOMEWORK", perms=A_)
    t.patch("/homework/{homeworkId}/submissions/{submissionId}", "gradeSubmission", "Grade or return a submission",
            E("operations.homework_submission"), body=V("GradeInput"), feature="HOMEWORK", perms=A_)
    t.post("/homework/{homeworkId}/exceptions", "logHomeworkException", "Log incomplete / not submitted",
           E("operations.homework_exception"), body=I("operations.homework_exception", drop=("homework_id",)),
           feature="HOMEWORK", perms=A_)
    t.get("/syllabus", "getSyllabus", "Units and coverage for a subject in a section", V("SyllabusTree"),
          feature="LESSON_PLANS", perms=A_, query=[("subjectId", "b"), ("classSectionId", "b")])
    t.get("/lesson-plans", "listLessonPlans", "My lesson plans", E("learning.lesson_plan"), paged=True, feature="LESSON_PLANS",
          perms=A_, query=[("classSectionId", "b"), ("from", "d"), ("to", "d")])
    t.post("/lesson-plans", "createLessonPlan", "Plan a lesson", E("learning.lesson_plan"), body=I("learning.lesson_plan"),
           feature="LESSON_PLANS", perms=A_)
    t.patch("/lesson-plans/{planId}", "updateLessonPlan", "Change a lesson plan", E("learning.lesson_plan"),
            body=I("learning.lesson_plan"), feature="LESSON_PLANS", perms=A_)
    t.get("/student-leave-requests", "listStudentLeaveRequests", "Parent leave requests (decide in Approvals)",
          arr(E("operations.student_leave_request")), feature="ATTENDANCE", perms=P("ATTENDANCE_SCOPED"), query=[("status", "s")])
    t.post("/classes/{classSectionId}/messages", "messageParents", "Message parents of one student, a group or the class",
           V("ConversationSummary"), body=V("ClassMessageInput"), feature="COMMUNICATION", perms=P("COMMUNICATION_SCOPED"))
    t.post("/behavior-notes", "addBehaviorNote", "Quick positive / concern note", E("assessment.student_behavior_log"),
           body=V("BehaviorNoteInput"), feature="ACADEMICS", perms=A_)
    t.post("/behavior-notes/{logId}/escalate", "escalateToIncident", "Escalate a note to an incident", E("discipline.incident"),
           feature="DISCIPLINE", perms=A_)
    t.get("/ptm/slots", "listMyPtmSlots", "My PTM slots and bookings", arr(E("communication.ptm_slot")), feature="PTM")
    t.post("/ptm/{ptmId}/slots", "publishPtmSlots", "Publish slots", arr(E("communication.ptm_slot")), body=V("PtmSlotsInput"),
           feature="PTM", perms=P("COMMUNICATION_SCOPED"))
    t.patch("/ptm/slots/{slotId}", "updatePtmSlot", "Notes after the meeting", E("communication.ptm_slot"), body=V("PtmNotesInput"),
            feature="PTM")
    t.get("/invigilation", "listInvigilation", "Exam-day cards (hall, seating, candidates)", arr(V("InvigilationCard")),
          feature="EXAMS", query=[("date", "d")])
    t.get("/escort/groups/{groupId}", "getEscortGroup", "Travel group card on departure day", V("TravelGroupBoard"), feature="HOSTEL")
    t.post("/escort/groups/{groupId}/arrival", "checkInArrival", "Check-in on arrival", V("TravelGroupBoard"),
           body=V("ArrivalCheckIn"), feature="HOSTEL")
    t.get("/report-cards", "listReportCardsForRemarks", "Report cards needing my remarks", arr(E("assessment.report_card")),
          feature="REPORT_CARDS", perms=A_, query=[("termId", "b"), ("classSectionId", "b")])
    t.patch("/report-cards/{reportCardId}", "addRemark", "Class teacher remark", E("assessment.report_card"), body=V("RemarkInput"),
            feature="REPORT_CARDS", perms=A_)
    t.post("/report-cards/submit", "submitReportCards", "Send remarks done for Principal approval", V("BulkResult"),
           body=V("IdList"), feature="REPORT_CARDS", perms=A_)
    t.post("/quizzes", "createQuiz", "Create a quiz", E("learning.quiz"), body=I("learning.quiz"), feature="ONLINE_QUIZ", perms=A_)
    t.post("/questions", "createQuestion", "Add to the question bank", E("learning.question"), body=I("learning.question"),
           feature="ONLINE_QUIZ", perms=A_)

    # ===================================================================== Parent
    pa = actor("parent", "Parent", ["PARENT"], "Guardian (hosteller and day-scholar variants): child switcher, attendance, fees, "
               "outings, pickups, wallet, messages. Sees only linked children")
    PS = P("ATTENDANCE_SCOPED")
    pa.get("/children", "listChildren", "Linked children with status dots", arr(V("ChildSummary")))
    pa.get("/home", "getHome", "Home for one child (day scholar or hosteller variant)", V("HomeFeed"), query=[("studentId", "b")])
    pa.get("/children/{studentId}/attendance", "getAttendance", "Month calendar", V("AttendanceCalendar"), feature="ATTENDANCE",
           perms=PS, query=[("month", "s", "yyyy-MM")])
    pa.get("/children/{studentId}/leave", "listLeave", "Leave requests (day scholar)", arr(E("operations.student_leave_request")),
           feature="ATTENDANCE", perms=PS)
    pa.post("/children/{studentId}/leave", "applyLeave", "Apply leave (goes to the class teacher)", E("operations.student_leave_request"),
            body=I("operations.student_leave_request", drop=("student_id", "decided_by_user_id")), feature="ATTENDANCE", perms=PS)
    pa.get("/children/{studentId}/timetable", "getTimetable", "Timetable", V("TimetableGrid"), feature="TIMETABLE",
           perms=P("ACADEMICS_SCOPED"))
    pa.get("/children/{studentId}/homework", "listHomework", "Homework", V("HomeworkView"), paged=True, feature="HOMEWORK",
           perms=P("ACADEMICS_SCOPED"), query=[("from", "d")])
    pa.get("/children/{studentId}/results", "listResults", "Published results", arr(V("ExamResult")), feature="EXAMS",
           perms=P("ACADEMICS_SCOPED"))
    pa.get("/children/{studentId}/report-cards", "listReportCards", "Report cards (dues hold message if any)",
           arr(V("ReportCardStatus")), feature="REPORT_CARDS", perms=P("ACADEMICS_SCOPED"))
    pa.get("/children/{studentId}/report-cards/{reportCardId}/pdf", "downloadReportCard", "Report card PDF (403 DUES_HOLD when held)",
           binary=True, feature="REPORT_CARDS", perms=P("ACADEMICS_SCOPED"))
    pa.get("/fees", "getFees", "Dues of all my children together", V("FamilyDues"), feature="FEE_MANAGEMENT",
           perms=P("FEE_MANAGEMENT_SCOPED"))
    pa.post("/payments", "startPayment", "Start a UPI / card payment", V("PaymentIntent"), body=V("OnlinePaymentInit"),
            feature="FEE_MANAGEMENT", perms=P("FEE_MANAGEMENT_SCOPED"))
    pa.post("/payments/{paymentId}/confirm", "confirmPayment", "Confirm with the gateway result; receipt on WhatsApp",
            V("PaymentReceipt"), body=V("GatewayConfirmation"), feature="FEE_MANAGEMENT", perms=P("FEE_MANAGEMENT_SCOPED"))
    pa.get("/payments", "listPayments", "Payment history", E("finance.payment"), paged=True, feature="FEE_MANAGEMENT",
           perms=P("FEE_MANAGEMENT_SCOPED"))
    pa.get("/payments/{paymentId}/receipt", "downloadReceipt", "Receipt PDF", binary=True, feature="FEE_MANAGEMENT",
           perms=P("FEE_MANAGEMENT_SCOPED"))
    HS = P("HOSTEL_SCOPED")
    pa.get("/children/{studentId}/hostel", "getHostelCard", "In hostel / on outing / sick bay, last roll call, phone tray, wallet, menu",
           V("HostelCard"), feature="HOSTEL", perms=HS)
    pa.get("/children/{studentId}/outings", "listOutings", "Outings with status timeline", V("OutingView"), paged=True,
           feature="HOSTEL", perms=HS)
    pa.post("/children/{studentId}/outings", "requestOuting", "Request home leave / day out (goes to the warden)", V("OutingView"),
            body=V("OutingRequestInput"), feature="HOSTEL", perms=HS)
    pa.post("/outings/{outingId}/decision", "decideOuting", "Approve or decline an outing the child or warden raised", V("OutingView"),
            body=V("ParentDecision"), feature="HOSTEL", perms=HS)
    pa.post("/outings/{outingId}/cancel", "cancelOuting", "Cancel before departure", V("OutingView"), feature="HOSTEL", perms=HS)
    pa.get("/children/{studentId}/pickup-people", "listPickupPeople", "Authorised pickup people", arr(E("frontoffice.pickup_person")),
           feature="GATE", perms=P("GATE_SCOPED"))
    pa.post("/children/{studentId}/pickup-people", "addPickupPerson", "Add a pickup person (OTP to their phone)",
            E("frontoffice.pickup_person"), body=V("PickupPersonInput"), feature="GATE", perms=P("GATE_SCOPED"))
    pa.delete("/pickup-people/{pickupPersonId}", "removePickupPerson", "Remove a pickup person", feature="GATE", perms=P("GATE_SCOPED"))
    pa.get("/children/{studentId}/wallet", "getWallet", "Wallet balance and statement (cash with witness)", V("WalletStatement"),
           feature="STORE_WALLET", perms=P("FEE_MANAGEMENT_SCOPED"))
    pa.post("/children/{studentId}/wallet/top-ups", "topUpWallet", "Top up by UPI", V("PaymentIntent"), body=V("TopUpInit"),
            feature="STORE_WALLET", perms=P("FEE_MANAGEMENT_SCOPED"))
    pa.get("/children/{studentId}/custody", "listCustody", "Items in custody (phone in tray B-14 since ...)", arr(V("CustodyItemView")),
           feature="CUSTODY", perms=P("CUSTODY_SCOPED"))
    pa.get("/ptm/slots", "listPtmSlots", "Open PTM slots for my child", arr(E("communication.ptm_slot")), feature="PTM",
           query=[("studentId", "b")])
    pa.post("/ptm/slots/{slotId}/book", "bookPtmSlot", "Book a slot", E("communication.ptm_slot"), body=V("BookSlot"), feature="PTM")
    pa.post("/polls/{pollId}/responses", "answerPoll", "Answer a poll", body=V("PollResponseInput"), feature="COMMUNICATION")
    pa.get("/children/{studentId}/bus", "getBusStatus", "Bus position and boarding (phase 2)", V("BusStatus"), feature="TRANSPORT",
           perms=P("TRANSPORT_SCOPED"))
    pa.get("/children/{studentId}/health", "getMedicalProfile", "Medical profile (consent required)", E("wellbeing.medical_profile"),
           feature="HEALTH", perms=P("HEALTH_SCOPED"))
    pa.put("/children/{studentId}/health", "updateMedicalProfile", "Update allergies, conditions, doctor", E("wellbeing.medical_profile"),
           body=I("wellbeing.medical_profile", drop=("student_id", "updated_at")), feature="HEALTH", perms=P("HEALTH_SCOPED"))
    pa.get("/reenrollments", "listReenrollments", "Re-enrollment invitations", arr(E("admissions.reenrollment")), feature="ADMISSIONS")
    pa.post("/reenrollments/{reenrollmentId}/response", "respondReenrollment", "Confirm / decline next year",
            E("admissions.reenrollment"), body=V("ReenrollmentResponse"), feature="ADMISSIONS")

    # ===================================================================== Student (adults only)
    st = actor("student", "Student", ["STUDENT"], "Adult / college students only (no app for minors): classwork, results, "
               "attendance shortfall, fees, hostel self-service")
    SELF = P("ACADEMICS_SELF")
    st.get("/home", "getHome", "Next class, assignments due, quiz open, outing status, attendance shortfall", V("HomeFeed"))
    st.get("/timetable", "getTimetable", "My timetable", V("TimetableGrid"), feature="TIMETABLE", perms=SELF)
    st.get("/attendance", "getAttendance", "Attendance % per subject with shortfall warning", arr(V("SubjectAttendance")),
           feature="ATTENDANCE", perms=P("ATTENDANCE_SELF"))
    st.get("/assignments", "listAssignments", "Assignments", V("HomeworkView"), paged=True, feature="HOMEWORK", perms=SELF)
    st.post("/assignments/{homeworkId}/submission", "submitAssignment", "Submit an assignment", E("operations.homework_submission"),
            body=V("SubmissionInput"), feature="HOMEWORK", perms=SELF)
    st.get("/quizzes", "listQuizzes", "Open quizzes", arr(E("learning.quiz")), feature="ONLINE_QUIZ", perms=SELF)
    st.post("/quizzes/{quizId}/attempts", "startQuiz", "Start an attempt", E("learning.quiz_attempt"), feature="ONLINE_QUIZ", perms=SELF)
    st.put("/quiz-attempts/{attemptId}", "saveQuizAnswers", "Save / submit answers", E("learning.quiz_attempt"),
           body=V("QuizAnswersInput"), feature="ONLINE_QUIZ", perms=SELF)
    st.get("/results", "listResults", "My results", arr(V("ExamResult")), feature="EXAMS", perms=SELF)
    st.get("/term-results", "listTermResults", "SGPA / CGPA per term", arr(E("assessment.term_result")), feature="EXAMS", perms=SELF)
    st.get("/course-offerings", "listCourseOfferings", "Electives open for registration", arr(E("academics.course_offering")),
           feature="COURSE_REGISTRATION", perms=SELF, query=[("termId", "b")])
    st.post("/course-registrations", "registerCourse", "Register for a course", E("academics.course_registration"),
            body=V("CourseRegistrationInput"), feature="COURSE_REGISTRATION", perms=SELF)
    st.delete("/course-registrations/{registrationId}", "dropCourse", "Drop a course", feature="COURSE_REGISTRATION", perms=SELF)
    st.get("/fees", "getFees", "My dues", V("FamilyDues"), feature="FEE_MANAGEMENT", perms=P("FEE_MANAGEMENT_SELF"))
    st.post("/payments", "startPayment", "Pay (if the institution allows students to pay)", V("PaymentIntent"),
            body=V("OnlinePaymentInit"), feature="FEE_MANAGEMENT", perms=P("FEE_MANAGEMENT_SELF"))
    st.get("/hostel", "getHostelCard", "My hostel card", V("HostelCard"), feature="HOSTEL", perms=P("HOSTEL_SELF"))
    st.get("/outings", "listOutings", "My outings", V("OutingView"), paged=True, feature="HOSTEL", perms=P("HOSTEL_SELF"))
    st.post("/outings", "requestOuting", "Self-request an outing (no parent step unless policy says so)", V("OutingView"),
            body=V("OutingRequestInput"), feature="HOSTEL", perms=P("HOSTEL_SELF"))
    st.get("/custody", "listCustody", "My items in custody", arr(V("CustodyItemView")), feature="CUSTODY", perms=P("CUSTODY_SELF"))
    st.get("/id-card", "getIdCard", "Digital ID", V("IdCardView"), feature="RECORDS", perms=P("RECORDS_SELF"))
    st.get("/placements/drives", "listPlacementDrives", "Open drives I'm eligible for", arr(E("placement.drive")),
           feature="PLACEMENTS", perms=SELF)
    st.post("/placements/drives/{driveId}/applications", "applyToDrive", "Apply to a drive", E("placement.application"),
            feature="PLACEMENTS", perms=SELF)

    # ===================================================================== Chief Warden
    cw = actor("chiefwarden", "ChiefWarden", ["CHIEF_WARDEN"], "Hostel head: allocation board, travel groups, policies, duty roster, monthly report")
    H = "HOSTEL"
    HM = P("HOSTEL_MANAGE")
    cw.get("/home", "getHome", "Missing students, leave/room/damage approvals, roll-call completion, occupancy", V("HomeFeed"))
    cw.get("/hostels", "listHostels", "Hostels", arr(E("hostel.hostel")), feature=H)
    cw.patch("/hostels/{hostelId}", "updateHostel", "Curfews and status", E("hostel.hostel"), body=I("hostel.hostel"), feature=H, perms=HM)
    cw.get("/hostels/{hostelId}/now", "getHostelNow", "Roll-call by block, on outing, overdue, sick bay, phones", V("HostelNow"), feature=H)
    cw.get("/hostels/{hostelId}/allocation-board", "getAllocationBoard", "Rooms and beds by floor with the waitlist",
           V("AllocationBoard"), feature=H, query=[("floor", "i"), ("gender", "s"), ("roomType", "s")])
    cw.post("/allocations", "allocateBed", "Allocate a bed (one active bed per student)", E("hostel.allocation"),
            body=V("AllocationCreate"), feature=H, perms=HM)
    cw.post("/allocations/{allocationId}/vacate", "vacate", "Vacate (blocked while custody items are held)", E("hostel.allocation"),
            body=V("VacateInput"), feature=H, perms=HM)
    cw.post("/allocations/{allocationId}/transfer", "transferBed", "Move to another bed", E("hostel.allocation"),
            body=V("TransferInput"), feature=H, perms=HM)
    cw.get("/allocation-requests", "listAllocationRequests", "New / room change / vacate requests", E("hostel.allocation_request"),
           paged=True, feature=H, query=[("status", "s")])
    cw.get("/hostels/{hostelId}/rooms", "listRooms", "Rooms", arr(E("hostel.room")), feature=H)
    cw.post("/hostels/{hostelId}/rooms", "createRoom", "Add a room", E("hostel.room"), body=I("hostel.room", drop=("hostel_id",)),
            feature=H, perms=HM)
    cw.post("/rooms/{roomId}/beds", "createBed", "Add a bed", E("hostel.bed"), body=I("hostel.bed", drop=("room_id",)), feature=H, perms=HM)
    cw.get("/travel-groups", "listTravelGroups", "Travel groups", E("hostel.outing_group"), paged=True, feature=H, query=[("status", "s")])
    cw.post("/travel-groups", "createTravelGroup", "Vacation departure / station drop group", E("hostel.outing_group"),
            body=I("hostel.outing_group"), feature=H, perms=HM)
    cw.get("/travel-groups/{groupId}", "getTravelGroup", "Day-of board", V("TravelGroupBoard"), feature=H)
    cw.patch("/travel-groups/{groupId}", "updateTravelGroup", "Change times, escort, vehicle", E("hostel.outing_group"),
             body=I("hostel.outing_group"), feature=H, perms=HM)
    cw.post("/travel-groups/{groupId}/students", "addStudentsToGroup", "Add students (bulk by class / block); parents confirm",
            V("TravelGroupBoard"), body=V("IdList"), feature=H, perms=HM)
    cw.get("/hostels/{hostelId}/policies", "listOutingPolicies", "Outing rules and quotas", arr(E("hostel.outing_policy")), feature=H)
    cw.put("/hostels/{hostelId}/policies", "saveOutingPolicies", "Replace outing rules (effective from a date)",
           arr(E("hostel.outing_policy")), body=arr(I("hostel.outing_policy", drop=("hostel_id",))), feature=H, perms=HM)
    cw.get("/hostels/{hostelId}/release-windows", "listReleaseWindows", "Phone release windows", arr(E("custody.release_window")),
           feature="CUSTODY")
    cw.put("/hostels/{hostelId}/release-windows", "saveReleaseWindows", "Replace phone release windows", arr(E("custody.release_window")),
           body=arr(I("custody.release_window", drop=("hostel_id",))), feature="CUSTODY", perms=P("CUSTODY_MANAGE"))
    cw.get("/hostels/{hostelId}/staff-assignments", "listStaffAssignments", "Warden duty roster", arr(E("hostel.staff_assignment")), feature=H)
    cw.post("/hostels/{hostelId}/staff-assignments", "assignWarden", "Assign a warden to a block, floor or rooms",
            E("hostel.staff_assignment"), body=I("hostel.staff_assignment", drop=("hostel_id",),
                                                 extra={"roomIds": {"type": "array", "items": {"type": "integer", "format": "int64"}}}),
            feature=H, perms=HM)
    cw.delete("/staff-assignments/{assignmentId}", "endAssignment", "End a duty assignment", feature=H, perms=HM)
    cw.get("/outings", "listOutings", "Outings (decide in Approvals)", V("OutingView"), paged=True, feature=H,
           query=[("status", "s"), ("from", "d")])
    cw.get("/hostels/{hostelId}/reports/monthly", "getMonthlyReport", "Auto-built monthly report", V("HostelMonthlyReport"),
           feature=H, query=[("month", "s")])
    cw.post("/hostels/{hostelId}/reports/monthly/submit", "submitMonthlyReport", "Send to the Principal with comments",
            V("HostelMonthlyReport"), body=V("ReportComments"), feature=H, perms=HM, query=[("month", "s")])
    cw.post("/inspections/{inspectionId}/damage-charge", "chargeDamage", "Raise a damage charge (fee demand)", E("finance.fee"),
            body=V("DamageChargeInput"), feature=H, perms=HM)

    # ===================================================================== Warden
    w = actor("warden", "Warden", ["WARDEN"], "Room / block / night / assistant warden: roll call, residents, custody, outings, inspections, handover")
    WS = P("HOSTEL_SCOPED", "HOSTEL_MANAGE")
    w.get("/home", "getHome", "Shaped by duty and time of day (21:00 opens the night roll call)", V("HomeFeed"))
    w.get("/residents", "listResidents", "Residents in my scope with status dots", arr(V("ResidentCard")), feature=H, perms=WS)
    w.post("/roll-calls", "startRollCall", "Start a roll call for my rooms (pre-filled from passes)", V("RollCallSheet"),
           body=V("RollCallStart"), feature=H, perms=WS)
    w.get("/roll-calls/{rollCallId}", "getRollCall", "Roll call sheet", V("RollCallSheet"), feature=H, perms=WS)
    w.put("/roll-calls/{rollCallId}/entries", "markRollCall", "Mark entries", V("RollCallSheet"), body=V("RollCallEntriesInput"),
          feature=H, perms=WS)
    w.post("/roll-calls/{rollCallId}/submit", "submitRollCall", "Submit; absent without a pass starts the escalation ladder",
           V("RollCallSheet"), feature=H, perms=WS)
    CS = P("CUSTODY_SCOPED", "CUSTODY_MANAGE")
    w.get("/custody/items", "listCustodyItems", "Items in custody", arr(E("custody.item")), feature="CUSTODY", perms=CS,
          query=[("studentId", "b"), ("status", "s")])
    w.post("/custody/items", "registerCustodyItem", "Register an item (photo, sealed pouch tag)", E("custody.item"),
           body=I("custody.item", drop=("registered_at", "due_back_at")), feature="CUSTODY", perms=CS)
    w.get("/custody/items/{itemId}/release-check", "checkRelease", "Is a release allowed now, and why", V("ReleaseCheck"),
          feature="CUSTODY", perms=CS)
    w.post("/custody/items/{itemId}/events", "recordCustodyEvent", "Deposit / release / return / confiscate (chain of custody)",
           E("custody.item"), body=V("CustodyEventInput"), feature="CUSTODY", perms=CS)
    w.get("/outings", "listOutings", "Outings in my scope", V("OutingView"), paged=True, feature=H, perms=WS, query=[("status", "s")])
    w.post("/outings", "raiseOuting", "Raise a medical / emergency / official outing", V("OutingView"), body=V("WardenOutingInput"),
           feature=H, perms=WS)
    w.post("/outings/{outingId}/provisional-approval", "approveEmergencyProvisionally",
           "Night duty: provisional emergency approval with the confirming call recorded", V("OutingView"),
           body=V("EmergencyApproval"), feature=H, perms=WS)
    w.get("/inspections", "listInspections", "Inspections", E("hostel.room_inspection"), paged=True, feature=H, perms=WS)
    w.post("/inspections", "recordInspection", "Room checklist, hygiene score, photos", E("hostel.room_inspection"),
           body=I("hostel.room_inspection", drop=("inspected_at", "damage_fee_id")), feature=H, perms=WS)
    w.post("/tickets", "raiseTicket", "Raise a maintenance ticket", E("facility.ticket"),
           body=I("facility.ticket", drop=("sla_due_at", "resolved_at", "resolution_note", "expense_id", "assigned_to_user_id")),
           feature="FACILITY")
    w.get("/tickets", "listTickets", "Tickets I raised", arr(E("facility.ticket")), feature="FACILITY", query=[("status", "s")])
    w.post("/laundry", "giveLaundry", "Laundry batch given", E("hostel.laundry_batch"),
           body=I("hostel.laundry_batch", drop=("returned_at", "returned_count", "missing_count")), feature=H, perms=WS)
    w.post("/laundry/{batchId}/return", "returnLaundry", "Laundry returned (count, missing)", E("hostel.laundry_batch"),
           body=I("hostel.laundry_batch", drop=("hostel_id", "student_id", "given_at", "item_count")), feature=H, perms=WS)
    w.get("/handover/draft", "getHandoverDraft", "Open items that carry over (sick, late returns, incidents)", V("HandoverDraft"),
          feature=H, perms=WS)
    w.post("/handover", "submitHandover", "Write the handover note", body=V("WardenHandoverInput"), feature=H, perms=WS)

    # ===================================================================== Matron
    m = actor("matron", "Matron", ["MATRON"], "Sick bay, medication rounds, laundry, welfare notes")
    m.get("/home", "getHome", "Medication due, sick-bay occupants, laundry due back", V("HomeFeed"))
    m.get("/medication/due", "listMedicationDue", "Doses due", arr(V("MedicationDue")), feature="HEALTH", perms=P("HEALTH_MANAGE"),
          query=[("from", "dt"), ("to", "dt")])
    m.post("/medication/doses/{doseId}", "recordDose", "Given / missed / refused", E("wellbeing.medication_dose"),
           body=V("DoseRecordInput"), feature="HEALTH", perms=P("HEALTH_MANAGE"))
    m.get("/sick-bay", "listSickBay", "In sick bay now", arr(E("wellbeing.infirmary_visit")), feature="HEALTH", perms=P("HEALTH_MANAGE"))
    m.post("/sick-bay/admissions", "admitToSickBay", "Admit (parent notified)", E("wellbeing.infirmary_visit"),
           body=V("SickBayAdmitInput"), feature="HEALTH", perms=P("HEALTH_MANAGE"))
    m.post("/sick-bay/{visitId}/discharge", "discharge", "Discharge", E("wellbeing.infirmary_visit"), body=V("DischargeInput"),
           feature="HEALTH", perms=P("HEALTH_MANAGE"))
    m.get("/laundry", "listLaundry", "Laundry batches", arr(E("hostel.laundry_batch")), feature=H, query=[("dueBackOnly", "bo")])
    m.post("/laundry", "giveLaundry", "Laundry batch given", E("hostel.laundry_batch"),
           body=I("hostel.laundry_batch", drop=("returned_at", "returned_count", "missing_count")), feature=H)
    m.post("/laundry/{batchId}/return", "returnLaundry", "Laundry returned", E("hostel.laundry_batch"),
           body=I("hostel.laundry_batch", drop=("hostel_id", "student_id", "given_at", "item_count")), feature=H)
    m.post("/welfare-notes", "addWelfareNote", "Welfare note (younger children)", E("assessment.student_behavior_log"),
           body=V("BehaviorNoteInput"), feature=H, perms=P("HOSTEL_SCOPED"))
    m.get("/residents", "listResidents", "Residents", arr(V("ResidentCard")), feature=H, perms=P("HOSTEL_SCOPED"))

    # ===================================================================== Nurse
    n = actor("nurse", "Nurse", ["NURSE"], "Infirmary (sick-bay tablet): visits, medical profiles, vaccinations, check-up drives")
    HN = P("HEALTH_MANAGE")
    n.get("/home", "getHome", "In sick bay, visits today, follow-ups, vaccinations due", V("HomeFeed"))
    n.post("/visits", "recordVisit", "Visit: complaint, vitals, treatment, disposition", E("wellbeing.infirmary_visit"),
           body=I("wellbeing.infirmary_visit", drop=("visited_at", "parent_notified_at", "discharged_at")), feature="HEALTH", perms=HN)
    n.get("/visits", "listVisits", "Visits", E("wellbeing.infirmary_visit"), paged=True, feature="HEALTH", perms=HN, query=[("date", "d")])
    n.patch("/visits/{visitId}", "updateVisit", "Update treatment / disposition", E("wellbeing.infirmary_visit"),
            body=V("VisitUpdate"), feature="HEALTH", perms=HN)
    n.post("/visits/{visitId}/notify-parent", "notifyParent", "Call / notify the parent", E("wellbeing.infirmary_visit"),
           feature="HEALTH", perms=HN)
    n.get("/patients/{studentId}", "getPatient", "Medical profile, vaccinations, check-ups, recent visits", V("PatientCard"),
          feature="HEALTH", perms=HN)
    n.put("/patients/{studentId}/medical-profile", "updateMedicalProfile", "Update the medical profile (consent required)",
          E("wellbeing.medical_profile"), body=I("wellbeing.medical_profile", drop=("student_id", "updated_at")), feature="HEALTH", perms=HN)
    n.post("/patients/{studentId}/vaccinations", "addVaccination", "Record a vaccination", E("wellbeing.vaccination"),
           body=I("wellbeing.vaccination", drop=("student_id",)), feature="HEALTH", perms=HN)
    n.get("/vaccinations/due", "listVaccinationsDue", "Vaccinations due", arr(V("VaccinationDue")), feature="HEALTH", perms=HN)
    n.post("/checkup-drives/{classSectionId}", "recordCheckups", "Annual check-up drive, batch entry by class", V("BulkResult"),
           body=V("CheckupBatchInput"), feature="HEALTH", perms=HN)
    n.get("/medication-schedules", "listMedicationSchedules", "Medication schedules", arr(E("wellbeing.medication_schedule")),
          feature="HEALTH", perms=HN, query=[("studentId", "b")])
    n.post("/medication-schedules", "createMedicationSchedule", "Add a medication schedule (generates doses)",
           E("wellbeing.medication_schedule"), body=I("wellbeing.medication_schedule"), feature="HEALTH", perms=HN)

    # ===================================================================== Mess Manager
    mm = actor("messmanager", "MessManager", ["MESS_MANAGER"], "Menus, subscriptions, meal counts, provisions, rebates")
    MS = P("MESS_MANAGE")
    mm.get("/home", "getHome", "Next meal with expected vs scanned count, requisitions, low stock, yesterday's rating", V("HomeFeed"))
    mm.get("/messes", "listMesses", "Messes", arr(E("hostel.mess")), feature="MESS")
    mm.get("/messes/{messId}/now", "getMealNow", "Expected vs scanned for the current meal", V("MealNow"), feature="MESS")
    mm.get("/messes/{messId}/menu", "getMenu", "Weekly menu and date overrides", arr(E("hostel.mess_menu")), feature="MESS",
           query=[("weekStart", "d")])
    mm.put("/messes/{messId}/menu", "saveMenu", "Plan the menu (veg / non-veg / Jain)", arr(E("hostel.mess_menu")),
           body=V("MenuInput"), feature="MESS", perms=MS)
    mm.get("/messes/{messId}/subscriptions", "listSubscriptions", "Subscriptions", E("hostel.mess_subscription"), paged=True,
           feature="MESS", query=[("status", "s")])
    mm.post("/subscriptions", "createSubscription", "Subscribe a student / staff diner", E("hostel.mess_subscription"),
            body=I("hostel.mess_subscription"), feature="MESS", perms=MS)
    mm.patch("/subscriptions/{subscriptionId}", "updateSubscription", "Pause / end", E("hostel.mess_subscription"),
             body=I("hostel.mess_subscription"), feature="MESS", perms=MS)
    mm.post("/meal-attendance", "recordMeal", "Count a meal (manual; scans go through /common/scan)", E("hostel.meal_attendance"),
            body=V("MealScanInput"), feature="MESS", perms=MS)
    mm.get("/messes/{messId}/feedback", "getFeedback", "Ratings and comments", V("FeedbackSummary"), feature="MESS", query=[("from", "d")])
    mm.post("/requisitions", "requisitionProvisions", "Requisition provisions from the mess store", E("inventory.requisition"),
            body=I("inventory.requisition", drop=("requisition_number",), extra={"lines": {"type": "array", "items": {"$ref": "#/components/schemas/RequisitionLineInput"}}}),
            feature="INVENTORY", perms=P("INVENTORY_SCOPED", "MESS_MANAGE"))
    reg.entity_input("inventory.requisition_line", drop=("requisition_id",))
    mm.get("/stores/low-stock", "listLowStock", "Low-stock provisions", arr(V("StockRow")), feature="INVENTORY")
    mm.post("/rebates/compute", "computeRebates", "Rebates for long leave in a month", arr(E("hostel.mess_rebate")),
            feature="MESS", perms=MS, query=[("month", "s")])
    mm.get("/messes/{messId}/reports/cost-per-meal", "getCostPerMeal", "Cost per meal", V("CostReport"), feature="MESS",
           query=[("month", "s")])

    # ===================================================================== Security guard
    g = actor("security", "Security", ["SECURITY"], "Guard (any phone or gate kiosk; everything works offline): gate, patrol, welfare, occurrences, handover")
    SG = P("GATE_SCOPED", "GATE_MANAGE")
    SP = P("SECURITY_SCOPED", "SECURITY_MANAGE")
    g.get("/home", "getHome", "On post, next checkpoint countdown, welfare ping, expected movements", V("GuardHome"))
    g.post("/gate/scan", "scanGatePass", "Full-screen ALLOWED / STOP verdict", V("GateVerdict"), body=V("GateScanInput"),
           feature="GATE", perms=SG)
    g.post("/gate/movements", "recordGateMovement", "OUT / IN for an outing (pickup verified by photo + parent OTP)",
           E("hostel.outing_movement"), body=V("GateMovementInput"), feature="GATE", perms=SG)
    g.post("/gate/passes/{gatePassId}/out", "releaseDayScholar", "Day-scholar early leave out", E("frontoffice.gate_pass"),
           feature="GATE", perms=SG)
    g.get("/gate/expected", "listExpected", "Outing returns due, travel groups departing", arr(V("ExpectedMovement")), feature="GATE")
    g.get("/travel-groups/{groupId}/gate", "getGroupGate", "Group scan-out list", V("TravelGroupBoard"), feature="GATE")
    g.post("/travel-groups/{groupId}/out", "groupOut", "Group out when everyone has scanned", V("TravelGroupBoard"),
           body=V("GroupOutInput"), feature="GATE", perms=SG)
    g.get("/patrol/current", "getCurrentRound", "Current patrol round with ordered checkpoints", V("PatrolRoundSheet"),
          feature="SECURITY", perms=SP)
    g.post("/patrol/rounds/{roundId}/start", "startRound", "Start a round", V("PatrolRoundSheet"), feature="SECURITY", perms=SP)
    g.post("/patrol/rounds/{roundId}/scans", "scanCheckpoint", "Scan a checkpoint (NFC / QR; photo or note optional)",
           V("PatrolRoundSheet"), body=V("PatrolScanInput"), feature="SECURITY", perms=SP)
    g.get("/welfare/pending", "getPendingWelfarePing", "Pending 'Are you OK?' ping", E("security.welfare_ping"), feature="SECURITY")
    g.post("/welfare/{pingId}/ok", "answerWelfarePing", "One huge YES", E("security.welfare_ping"), feature="SECURITY")
    g.post("/occurrences", "reportOccurrence", "Intruder, fire, power, medical, vehicle, gate breach ...", E("security.occurrence"),
           body=I("security.occurrence", drop=("ticket_id", "incident_id", "escalated_to_user_id")), feature="SECURITY", perms=SP)
    g.get("/occurrences", "listMyOccurrences", "My occurrences", E("security.occurrence"), paged=True, feature="SECURITY")
    g.post("/vehicles", "logVehicleIn", "Vehicle in", E("security.vehicle_entry"), body=I("security.vehicle_entry", drop=("in_at", "out_at")),
           feature="GATE", perms=SG)
    g.post("/vehicles/{vehicleEntryId}/out", "logVehicleOut", "Vehicle out", E("security.vehicle_entry"), feature="GATE", perms=SG)
    g.post("/visits", "checkInVisitor", "Quick visitor log (post without a receptionist)", E("frontoffice.visit"),
           body=V("VisitCheckIn"), feature="GATE", perms=SG)
    g.post("/visits/{visitId}/check-out", "checkOutVisitor", "Visitor out", E("frontoffice.visit"), feature="GATE", perms=SG)
    g.post("/keys/{keyId}/issue", "issueKey", "Issue a key", E("security.key_movement"), body=V("KeyIssueInput"),
           feature="SECURITY", perms=SP)
    g.post("/key-movements/{keyMovementId}/return", "returnKey", "Key returned", E("security.key_movement"), feature="SECURITY", perms=SP)
    g.post("/handover", "handOverShift", "Shift handover: keys, equipment, open occurrences, note", E("security.shift_handover"),
           body=V("ShiftHandoverInput"), feature="SECURITY", perms=SP)
    g.get("/handover/pending", "getPendingHandover", "Handover waiting for me", E("security.shift_handover"), feature="SECURITY")
    g.post("/handover/{handoverId}/accept", "acceptHandover", "Accept the handover", E("security.shift_handover"), feature="SECURITY")
    g.post("/offline/batch", "syncOffline", "Replay actions queued offline (idempotent per action)", V("OfflineBatchResult"),
           body=V("OfflineBatch"))

    # ===================================================================== Security Supervisor
    ss = actor("securitysupervisor", "SecuritySupervisor", ["SECURITY_SUPERVISOR"], "Guard roster, live posts, patrol routes and compliance, occurrences, keys")
    SM = P("SECURITY_MANAGE")
    ss.get("/home", "getHome", "Missed welfare pings, unmanned posts, patrol compliance tonight", V("HomeFeed"))
    ss.get("/live-posts", "listLivePosts", "Each post with the guard on duty and last activity", arr(V("LivePost")), feature="SECURITY")
    ss.get("/roster", "getRoster", "Guard roster (A/B/C rotation)", V("RosterWeek"), feature="SECURITY", query=[("weekStart", "d")])
    ss.put("/roster", "updateRoster", "Change the guard roster", V("RosterWeek"), body=V("RosterUpdate"), feature="SECURITY", perms=SM)
    ss.get("/posts", "listPosts", "Posts", arr(E("hr.post")), feature="SECURITY")
    ss.post("/posts", "createPost", "Add a post", E("hr.post"), body=I("hr.post", drop=("device_id",)), feature="SECURITY", perms=SM)
    ss.get("/checkpoints", "listCheckpoints", "Checkpoints", arr(E("security.checkpoint")), feature="SECURITY")
    ss.post("/checkpoints", "createCheckpoint", "Add a checkpoint (NFC / QR tag)", E("security.checkpoint"),
            body=I("security.checkpoint"), feature="SECURITY", perms=SM)
    ss.get("/patrol-routes", "listPatrolRoutes", "Patrol routes", arr(E("security.patrol_route")), feature="SECURITY")
    ss.post("/patrol-routes", "createPatrolRoute", "Add a route", E("security.patrol_route"), body=I("security.patrol_route"),
            feature="SECURITY", perms=SM)
    ss.put("/patrol-routes/{routeId}/checkpoints", "setRouteCheckpoints", "Ordered checkpoints of a route",
           arr(E("security.route_checkpoint")), body=V("CheckpointOrderInput"), feature="SECURITY", perms=SM)
    ss.get("/patrols", "getPatrolCompliance", "Patrol compliance for a night", V("PatrolCompliance"), feature="SECURITY",
           query=[("date", "d")])
    ss.get("/occurrences", "listOccurrences", "Occurrences", E("security.occurrence"), paged=True, feature="SECURITY",
           query=[("status", "s"), ("severity", "s")])
    ss.patch("/occurrences/{occurrenceId}", "updateOccurrence", "Acknowledge, escalate, resolve", E("security.occurrence"),
             body=V("OccurrenceUpdate"), feature="SECURITY", perms=SM)
    ss.get("/keys", "listKeys", "Key register", arr(V("KeyStatus")), feature="SECURITY")
    ss.post("/keys", "createKey", "Add a key", E("security.key"), body=I("security.key"), feature="SECURITY", perms=SM)
    ss.get("/welfare", "listWelfarePings", "Welfare pings for a night", arr(E("security.welfare_ping")), feature="SECURITY",
           query=[("date", "d")])

    # ===================================================================== Staff (librarian / general)
    sf = actor("staff", "Staff", ["STAFF"], "Librarian and general staff: scan-first library counter, tasks")
    L = "LIBRARY"
    LM = P("LIBRARY_MANAGE")
    sf.get("/home", "getHome", "Overdue books, reservations ready, tickets assigned to me", V("HomeFeed"))
    sf.get("/library/books", "listBooks", "Catalog", E("library.library_book"), paged=True, feature=L, query=[("q", "s")])
    sf.post("/library/books", "createBook", "Add a title (photo-first, ISBN optional)", E("library.library_book"),
            body=I("library.library_book"), feature=L, perms=LM)
    sf.post("/library/books/{bookId}/copies", "addCopy", "Add a copy with barcode", E("library.book_copy"),
            body=I("library.book_copy", drop=("book_id",)), feature=L, perms=LM)
    sf.post("/library/issues", "issueBook", "Issue by scan", E("library.library_borrowing"), body=V("IssueBookInput"), feature=L, perms=LM)
    sf.post("/library/returns", "returnBook", "Return by scan (fine posted as a fee demand if enabled)", E("library.library_borrowing"),
            body=V("ReturnBookInput"), feature=L, perms=LM)
    sf.get("/library/overdue", "listOverdue", "Overdue borrowings", arr(E("library.library_borrowing")), feature=L)
    sf.post("/library/overdue/reminders", "sendOverdueReminders", "Send overdue reminders", V("BulkResult"), feature=L, perms=LM)
    sf.get("/tasks", "listMyTasks", "Tickets assigned to me", arr(E("facility.ticket")), feature="FACILITY")
    sf.patch("/tasks/{ticketId}", "updateTask", "Progress / resolve a ticket", E("facility.ticket"), body=V("TicketUpdate"),
             feature="FACILITY")

    # ===================================================================== Store Keeper
    sk = actor("storekeeper", "StoreKeeper", ["STORE_KEEPER"], "Stock, GRN, issues, assets, stock audits, hostel kits")
    IV = "INVENTORY"
    IM = P("INVENTORY_MANAGE")
    sk.get("/home", "getHome", "Approved requisitions to issue, POs arriving, low stock, maintenance due", V("HomeFeed"))
    sk.get("/stock", "listStock", "Stock on hand", V("StockRow"), paged=True, feature=IV, query=[("locationId", "b"), ("lowOnly", "bo"), ("q", "s")])
    for path, op, table, label in [("/items", "Item", "inventory.item_catalog", "Item catalog"),
                                   ("/item-categories", "ItemCategory", "inventory.item_category", "Categories"),
                                   ("/locations", "Location", "inventory.location", "Locations / rooms"),
                                   ("/vendors", "Vendor", "inventory.vendor", "Vendors")]:
        sk.get(path, "list" + op + "s", label, arr(E(table)), feature=IV)
        sk.post(path, "create" + op, "Add: " + label.lower(), E(table), body=I(table), feature=IV, perms=IM)
        sk.patch(path + "/{id}", "update" + op, "Change: " + label.lower(), E(table), body=I(table), feature=IV, perms=IM)
    sk.get("/requisitions", "listRequisitions", "Requisitions", E("inventory.requisition"), paged=True, feature=IV, query=[("status", "s")])
    sk.post("/requisitions/{requisitionId}/issue", "issueRequisition", "Issue an approved requisition from stock",
            arr(E("inventory.inventory_transaction")), body=V("StockIssueInput"), feature=IV, perms=IM)
    sk.post("/issues", "issueStock", "Issue to a person, department, hostel or mess", arr(E("inventory.inventory_transaction")),
            body=V("StockIssueInput"), feature=IV, perms=IM)
    sk.post("/returns", "returnStock", "Return to stock", arr(E("inventory.inventory_transaction")), body=V("StockIssueInput"),
            feature=IV, perms=IM)
    sk.get("/purchase-orders", "listPurchaseOrders", "Purchase orders", E("inventory.purchase_order"), paged=True, feature=IV,
           query=[("status", "s")])
    sk.post("/purchase-orders", "createPurchaseOrder", "Draft a PO", E("inventory.purchase_order"), body=V("PurchaseOrderCreate"),
            feature=IV, perms=IM)
    sk.post("/purchase-orders/{poId}/submit", "submitPurchaseOrder", "Send for approval by band", V("ApprovalItem"), feature=IV, perms=IM)
    sk.post("/goods-receipts", "createGoodsReceipt", "GRN: accepted / rejected, batch / expiry, invoice photo",
            E("inventory.goods_receipt"), body=V("GoodsReceiptCreate"), feature=IV, perms=IM)
    sk.post("/goods-receipts/{grnId}/post", "postGoodsReceipt", "Post to stock (moving-average cost)", E("inventory.goods_receipt"),
            feature=IV, perms=IM)
    sk.get("/assets", "listAssets", "Assets", E("inventory.asset_item"), paged=True, feature=IV, query=[("status", "s"), ("q", "s")])
    sk.post("/assets/{assetId}/assign", "assignAsset", "Assign to a room, person or student", E("inventory.asset_item"),
            body=V("AssetAssignInput"), feature=IV, perms=IM)
    sk.post("/assets/{assetId}/maintenance", "logMaintenance", "Log maintenance / AMC visit", E("inventory.asset_maintenance"),
            body=I("inventory.asset_maintenance", drop=("asset_id",)), feature=IV, perms=IM)
    sk.post("/stock-audits", "startStockAudit", "Start a blind count for a location", V("StockAuditSheet"), body=V("StockAuditCreate"),
            feature=IV, perms=IM)
    sk.put("/stock-audits/{auditId}/counts", "saveCounts", "Save counted quantities", V("StockAuditSheet"), body=V("CountsInput"),
           feature=IV, perms=IM)
    sk.post("/stock-audits/{auditId}/submit", "submitStockAudit", "Submit variances for Principal approval", V("ApprovalItem"),
            feature=IV, perms=IM)
    sk.post("/kits/hostel-check-in", "issueHostelKit", "Hostel kit at check-in (bundle in one scan)", V("BulkResult"),
            body=V("KitIssueInput"), feature=IV, perms=IM)

    # ===================================================================== Transport Manager (phase 2)
    tm = actor("transportmanager", "TransportManager", ["TRANSPORT_MANAGER"], "Routes, stops, vehicles, drivers, live map, fuel", phase="phase 2")
    T = "TRANSPORT"
    TMM = P("TRANSPORT_MANAGE")
    tm.get("/home", "getHome", "Unexpected stops, panic button, compliance expiring", V("HomeFeed"))
    tm.get("/live", "getLiveTrips", "All trips with on-time status", arr(V("LiveTrip")), feature=T)
    tm.get("/routes", "listRoutes", "Routes", arr(E("transport.route")), feature=T)
    tm.post("/routes", "createRoute", "Add a route", E("transport.route"), body=I("transport.route"), feature=T, perms=TMM)
    tm.patch("/routes/{routeId}", "updateRoute", "Change vehicle, driver, attendant", E("transport.route"), body=I("transport.route"),
             feature=T, perms=TMM)
    tm.get("/routes/{routeId}/stops", "listStops", "Stops", arr(E("transport.stop")), feature=T)
    tm.put("/routes/{routeId}/stops", "saveStops", "Route builder: stops, order, times", arr(E("transport.stop")), body=V("StopsInput"),
           feature=T, perms=TMM)
    tm.get("/routes/{routeId}/students", "listRouteStudents", "Riders", arr(E("transport.student_route")), feature=T)
    tm.post("/student-routes", "assignStudentRoute", "Assign a student to a route and stops", E("transport.student_route"),
            body=I("transport.student_route"), feature=T, perms=TMM)
    tm.get("/vehicles", "listVehicles", "Vehicles", arr(E("transport.vehicle")), feature=T)
    tm.post("/vehicles", "createVehicle", "Add a vehicle", E("transport.vehicle"), body=I("transport.vehicle"), feature=T, perms=TMM)
    tm.patch("/vehicles/{vehicleId}", "updateVehicle", "Update documents and status", E("transport.vehicle"),
             body=I("transport.vehicle"), feature=T, perms=TMM)
    tm.get("/compliance/expiring", "listExpiringCompliance", "Insurance, fitness, permit, PUC, licences expiring",
           arr(V("ComplianceItem")), feature=T, query=[("days", "i")])
    tm.get("/drivers", "listDrivers", "Drivers and attendants", arr(V("PersonRef")), feature=T)
    tm.get("/trips", "listTrips", "Trips", E("transport.trip"), paged=True, feature=T, query=[("date", "d"), ("routeId", "b")])
    tm.get("/trips/{tripId}/track", "getTripTrack", "GPS track", arr(E("transport.trip_location")), feature=T)
    tm.post("/fuel-logs", "logFuel", "Fuel log (books an expense)", E("transport.fuel_log"), body=I("transport.fuel_log", drop=("expense_id",)),
            feature=T, perms=TMM)
    tm.get("/fuel-logs", "listFuelLogs", "Fuel logs", E("transport.fuel_log"), paged=True, feature=T, query=[("vehicleId", "b")])
    tm.get("/call-logs", "listMaskedCalls", "Masked call log (who, student, time, duration)", V("MaskedCallLog"), paged=True,
           feature=T, perms=TMM)

    # ===================================================================== Driver (phase 2)
    d = actor("driver", "Driver", ["DRIVER"], "Driving-safe trip screen: next stop, boarding, emergency, masked calls; works offline", phase="phase 2")
    DS = P("TRANSPORT_SCOPED")
    d.get("/trips/today", "listTodayTrips", "My trips today", arr(E("transport.trip")), feature=T, perms=DS)
    d.post("/trips/{tripId}/start", "startTrip", "Start a trip", V("TripSheet"), feature=T, perms=DS)
    d.get("/trips/{tripId}", "getTrip", "Trip sheet (next stop large; names only)", V("TripSheet"), feature=T, perms=DS)
    d.post("/trips/{tripId}/locations", "pushLocations", "GPS points (batched)", body=V("LocationBatch"), feature=T, perms=DS)
    d.post("/trips/{tripId}/boardings", "markBoarding", "Boarded / not here (parents notified 'bus near')", V("TripSheet"),
           body=V("BoardingMark"), feature=T, perms=DS)
    d.post("/trips/{tripId}/end", "endTrip", "End the trip", V("TripSheet"), feature=T, perms=DS)
    d.post("/trips/{tripId}/emergency", "raiseEmergency", "Emergency button", body=V("EmergencyInput"), feature=T, perms=DS)
    d.post("/trips/{tripId}/calls", "callParent", "Masked call to a parent (active trip only, logged)", V("MaskedCall"),
           body=V("MaskedCallRequest"), feature=T, perms=DS)
    d.get("/history", "listTripHistory", "Past trips", E("transport.trip"), paged=True, feature=T, perms=DS)
    d.post("/offline/batch", "syncOffline", "Replay boardings / locations queued offline", V("OfflineBatchResult"), body=V("OfflineBatch"),
           feature=T, perms=DS)

    # ===================================================================== Assistant (MCP, read-only)
    asst = actor("assistant", "Assistant", ["*"], "Read-only contract for school-mcp (voice and AI assistants act as the signed-in user). "
                 "GET only; every write happens in the app (parental control)")
    pin = {"x-assistant-pin": True}
    asst.get("/context", "getAssistantContext", "Categories this user's assistant link may read", V("AssistantContext"))
    asst.get("/notices", "listNotices", "Latest notices", arr(V("NoticeView")), feature="COMMUNICATION", x={"x-assistant-category": "NOTICES"})
    asst.get("/children/{studentId}/attendance/today", "getChildAttendanceToday", "Child's attendance today", V("AttendanceToday"),
             feature="ATTENDANCE", perms=P("ATTENDANCE_SCOPED"), x={"x-assistant-category": "ATTENDANCE"})
    asst.get("/children/{studentId}/homework", "getChildHomework", "Homework due", arr(V("HomeworkView")), feature="HOMEWORK",
             perms=P("ACADEMICS_SCOPED"), x={"x-assistant-category": "HOMEWORK"})
    asst.get("/children/{studentId}/timetable/today", "getChildTimetableToday", "Today's timetable", arr(V("PeriodSlot")),
             feature="TIMETABLE", perms=P("ACADEMICS_SCOPED"), x={"x-assistant-category": "TIMETABLE"})
    asst.get("/children/{studentId}/results", "getChildResults", "Published results (PIN)", arr(V("ExamResult")), feature="EXAMS",
             perms=P("ACADEMICS_SCOPED"), x=dict(pin, **{"x-assistant-category": "RESULTS"}))
    asst.get("/children/{studentId}/fees", "getChildFees", "Fee summary (PIN)", V("FeeSummary"), feature="FEE_MANAGEMENT",
             perms=P("FEE_MANAGEMENT_SCOPED"), x=dict(pin, **{"x-assistant-category": "FEES"}))
    asst.get("/children/{studentId}/hostel-status", "getChildHostelStatus", "Is my child back from the outing? (PIN)",
             V("HostelStatus"), feature="HOSTEL", perms=P("HOSTEL_SCOPED"), x=dict(pin, **{"x-assistant-category": "HOSTEL_STATUS"}))
    asst.get("/me/timetable/today", "getMyTimetableToday", "My timetable today (staff)", arr(V("PeriodSlot")), feature="TIMETABLE",
             x={"x-assistant-category": "MY_TIMETABLE"})
    asst.get("/classes/{classSectionId}/attendance-summary", "getClassAttendanceSummary", "Class attendance summary (class teacher)",
             V("ClassAttendanceSummary"), feature="ATTENDANCE", perms=P("ATTENDANCE_SCOPED", "ATTENDANCE_MANAGE"),
             x={"x-assistant-category": "CLASS_ATTENDANCE"})
    asst.get("/school/overview", "getSchoolOverview", "School overview (Principal, Administrator, School Admin; PIN)", V("Dashboard"),
             x=dict(pin, **{"x-assistant-category": "SCHOOL_OVERVIEW"}))
    for o in asst.ops:
        assert o["method"] == "get", o
    return actors
