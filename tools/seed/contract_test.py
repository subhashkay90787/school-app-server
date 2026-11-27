#!/usr/bin/env python3
"""Contract smoke test against a running school-app-server + school-auth with the dev seed loaded
(tools/seed/dev_seed.sql, tools/seed/auth_dev_users.sql).

Logs every actor in with an OTP (codes read from the auth server's dev log), then calls each operation of that
actor's spec with sample ids. GETs always; writes too with --writes (they change the seeded data). Prints a
table of status codes per actor and lists every 5xx (501 is reported separately: flows not built yet).

    python3 tools/seed/contract_test.py [--writes] [--actor teacher] [--verbose]
"""
import argparse
import json
import os
import re
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
AUTH = os.environ.get("AUTH", "http://localhost:8080")
APP = os.environ.get("APP", "http://localhost:8081")
AUTH_LOG = os.environ.get("AUTH_LOG", "/tmp/run/auth.log")
OPS = json.load(open(os.path.join(ROOT, "tools/openapi/operations.json")))
ROUTES = json.load(open(os.path.join(ROOT, "src/main/resources/openapi/role-routes.json")))

PHONES = {2: "+919100000001", 3: "+919100000002", 4: "+919100000003", 5: "+919100000004", 6: "+919100000005", 7: "+919100000009"}
PHONES.update({i: f"+9191001000{i:02d}" for i in range(8, 25)})
USERS = {"common": 4, "admin": 7, "principal": 3, "schooladmin": 2, "accountant": 8, "hrmanager": 9, "admissionofficer": 10,
         "receptionist": 11, "teacher": 4, "parent": 6, "student": 23, "chiefwarden": 12, "warden": 13, "matron": 14, "nurse": 15,
         "messmanager": 16, "security": 17, "securitysupervisor": 18, "staff": 5, "storekeeper": 19, "transportmanager": 20,
         "driver": 21, "assistant": 6}

# sample ids by path parameter (seed data); per-actor overrides below
IDS = {"studentId": 3, "classSectionId": 1, "examId": 2, "homeworkId": 1, "submissionId": 2, "hostelId": 1, "messId": 1, "groupId": 1,
       "rollCallId": 2, "itemId": 1, "doseId": 2, "visitId": 1, "outingId": 2, "notificationId": 1, "conversationId": 1, "postId": 1,
       "formId": 1, "flowInstanceId": 1, "tripId": 2, "routeId": 1, "allocationId": 2, "applicationId": 1, "enquiryId": 1,
       "subscriptionId": 1, "presenceId": 1, "timetableVersionId": 1, "runId": 2, "feeId": 4, "paymentId": 1, "userId": 24,
       "documentId": 1, "requisitionId": 1, "grnId": 1, "auditId": 1, "poId": 1, "vehicleId": 1, "stopId": 1, "ptmId": 1, "slotId": 2,
       "pollId": 1, "reenrollmentId": 1, "planId": 1, "logId": 1, "timetableId": 1, "keyMovementId": 1, "occurrenceId": 1,
       "pingId": 1, "roundId": 2, "checkpointId": 1, "vehicleEntryId": 1, "gatePassId": 1, "parcelId": 1, "pickupPersonId": 1,
       "reportCardId": 1, "termId": 1, "academicYearId": 1, "departmentId": 1, "programId": 1, "subjectId": 1, "periodId": 1,
       "expenseId": 1, "budgetId": 1, "vendorId": 1, "locationId": 5, "incidentId": 1, "ticketId": 1, "leaveRequestId": 2,
       "staffAbsenceId": 1, "offeringId": 1, "assignmentId": 3, "windowId": 1, "keyId": 1, "patrolRouteId": 1, "bedId": 4,
       "roomId": 1, "blockId": 1, "policyId": 1, "pickupId": 1, "inspectionId": 1, "batchId": 1, "importJobId": 1,
       "exportJobId": 1, "reportId": 1, "templateId": 1, "questionId": 1, "quizId": 1, "attemptId": 1, "driveId": 1,
       "contentId": 1, "copyId": 1, "bookId": 1, "borrowingId": 1, "certificateId": 1, "clearanceId": 1, "cardId": 1,
       "vaccinationId": 1, "checkupId": 1, "scheduleId": 1, "feeStructureId": 1, "feeHeadId": 1, "concessionId": 1,
       "refundId": 1, "walletId": 1, "itemCatalogId": 2, "stockId": 1, "assetId": 1, "invoiceId": 1, "examSessionId": 1,
       "ptmSlotId": 2, "eventId": 1, "shiftId": 1, "postIdHr": 1, "rosterEntryId": 1, "payslipId": 1, "componentId": 1,
       "structureId": 1, "openingId": 1, "candidateId": 1, "followUpId": 1, "assessmentId": 1, "seatPlanId": 1, "field": "pf_uan",
       "mediaId": 1, "unitId": 1, "syllabusId": 1, "visitorId": 1, "messPlanId": 1, "menuId": 1, "rebateId": 1, "feedbackId": 1,
       "unitIdCustody": 1, "storageUnitId": 1, "laundryId": 1, "handoverId": 1, "fuelLogId": 1, "saleId": 1, "categoryId": 1}
ACTOR_IDS = {"parent": {"studentId": 2, "outingId": 2}, "student": {"studentId": 1}, "teacher": {"studentId": 3, "classSectionId": 1},
             "assistant": {"studentId": 1, "classSectionId": 1}, "driver": {"tripId": 2}}
QUERY = {"date": None, "from": None, "to": None, "q": "ar", "month": None, "page": "0", "size": "20"}


def http(method, url, token=None, body=None, form=None, school=1):
    headers = {"Accept": "application/json"}
    data = None
    if token:
        headers["Authorization"] = "Bearer " + token
        headers["X-School-Id"] = str(school)
    if form is not None:
        data = urllib.parse.urlencode(form).encode()
        headers["Content-Type"] = "application/x-www-form-urlencoded"
    elif body is not None:
        data = json.dumps(body).encode()
        headers["Content-Type"] = "application/json"
    req = urllib.request.Request(url, data=data, method=method, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return r.status, r.read().decode()
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()


def login(user_id):
    phone = PHONES[user_id]
    time.sleep(1.2)
    http("POST", AUTH + "/api/v1/otp/send", body={"phone": phone})
    code = None
    for _ in range(20):
        time.sleep(0.3)
        m = re.findall(r"to=" + re.escape(phone) + r" code=(\d+)", open(AUTH_LOG).read())
        if m:
            code = m[-1]
            break
    if not code:
        sys.exit(f"no OTP for {phone} in {AUTH_LOG}")
    st, out = http("POST", AUTH + "/oauth2/token", form={
        "grant_type": "urn:ietf:params:oauth:grant-type:otp", "client_id": "school-mobile-app", "phone": phone, "otp": code,
        "device_id": f"ct-{user_id}", "platform": "ANDROID", "app_version": "1.0.0"})
    if st != 200:
        sys.exit(f"login {user_id} failed: {st} {out[:300]}")
    return json.loads(out)["access_token"]


def sample_body(op):
    """Small body from the field names (enough for the request to bind; rules may still refuse it)."""
    if not op["body"]:
        return None
    vals = {"studentId": 3, "classSectionId": 1, "hostelId": 1, "date": None, "reason": "contract test", "note": "contract test",
            "title": "Contract test", "body": "Contract test", "name": "Contract test", "status": None, "amount": 100}
    fields = op["bodyFields"] or []
    out = {f: vals[f] for f in fields if f in vals and vals[f] is not None}
    return [out] if op["bodyKind"] == "array" else out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--writes", action="store_true")
    ap.add_argument("--actor")
    ap.add_argument("--verbose", action="store_true")
    args = ap.parse_args()
    tokens = {}
    summary, failures = [], []
    for actor, spec in OPS.items():
        if args.actor and actor != args.actor:
            continue
        uid = USERS[actor]
        if uid not in tokens:
            tokens[uid] = login(uid)
        token = tokens[uid]
        base = next(p for p in ROUTES if p.rstrip("/").endswith("/" + actor))
        counts = {}
        for op in spec["ops"]:
            if op["method"] != "get" and not args.writes:
                continue
            if op["binary"] or op["multipart"]:
                continue
            ids = dict(IDS, **ACTOR_IDS.get(actor, {}))
            path = re.sub(r"\{(\w+)\}", lambda m: str(ids.get(m.group(1), 1)), op["path"])
            qs = {k: v for k, v in QUERY.items() if k in op["query"] and v is not None}
            url = APP + base + path + ("?" + urllib.parse.urlencode(qs) if qs else "")
            st, out = http(op["method"].upper(), url, token, body=sample_body(op))
            counts[st] = counts.get(st, 0) + 1
            if st >= 500 and st != 501:
                failures.append((actor, op["method"].upper(), op["path"], op["opId"], st, out[:400]))
            if args.verbose:
                print(f"{st} {actor} {op['method'].upper()} {path} {op['opId']} {out[:160] if st >= 400 else ''}")
        summary.append((actor, counts))
    print("\nactor               " + "  ".join(f"{c:>4}" for c in (200, 201, 204, 400, 403, 404, 409, 501, 500)))
    for actor, counts in summary:
        print(f"{actor:20}" + "  ".join(f"{counts.get(c, 0):>4}" for c in (200, 201, 204, 400, 403, 404, 409, 501, 500))
              + ("  other: " + str({k: v for k, v in counts.items() if k not in (200, 201, 204, 400, 403, 404, 409, 501, 500)})
                 if any(k not in (200, 201, 204, 400, 403, 404, 409, 501, 500) for k in counts) else ""))
    if failures:
        print(f"\n{len(failures)} server errors:")
        for f in failures:
            print(" ", *f[:5], "\n     ", f[5].replace("\n", " "))
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
