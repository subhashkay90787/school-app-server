package com.school.app.core.data;

import com.school.app.core.access.AccessDeniedProblem;
import com.school.app.core.data.TableRegistry.Table;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;

/**
 * Data scope inside a branch (UX v2 access matrix "S" and "O"): RLS already limits every query to the branch;
 * these rules narrow it to what the actor may see.
 * <ul>
 *   <li>parent: rows of their linked children (academics.student_parent)</li>
 *   <li>student: their own student record (student_user_id = me)</li>
 *   <li>teacher: their subjects (staff_subject), sections they teach or class-teach, their PTM slots</li>
 *   <li>warden, matron, chiefwarden: hostels they are assigned to (hostel.staff_assignment)</li>
 *   <li>driver: their trips</li>
 *   <li>"my" operations (/common/me/..., list-my-...): rows where the caller is the owner</li>
 * </ul>
 * All other actors work branch-wide; their limits come from permissions. SQL uses platform.current_user_id(), set
 * from the token for every transaction.
 */
@Service
public class ScopeService {

    static final String ME = "platform.current_user_id()";
    static final String MY_CHILDREN = "SELECT sp.student_id FROM academics.student_parent sp WHERE sp.user_id = " + ME;
    static final String MY_STUDENT = "SELECT s.student_id FROM academics.student s WHERE s.student_user_id = " + ME;
    static final String MY_SUBJECTS = "SELECT ss.staff_subject_id FROM academics.staff_subject ss WHERE ss.user_id = " + ME;
    static final String MY_SECTIONS = "SELECT cs.class_section_id FROM academics.class_section cs WHERE cs.teacher_user_id = " + ME
            + " UNION SELECT h.class_section_id FROM academics.class_section_period h JOIN academics.timetable tt"
            + " ON tt.class_section_period_id = h.class_section_period_id AND tt.school_id = h.school_id"
            + " JOIN academics.staff_subject ss ON ss.staff_subject_id = tt.staff_subject_id AND ss.school_id = tt.school_id"
            + " WHERE ss.user_id = " + ME
            + " UNION SELECT co.class_section_id FROM academics.course_offering co JOIN academics.staff_subject ss"
            + " ON ss.staff_subject_id = co.staff_subject_id AND ss.school_id = co.school_id WHERE ss.user_id = " + ME;
    static final String MY_HOSTELS = "SELECT sa.hostel_id FROM hostel.staff_assignment sa WHERE sa.user_id = " + ME
            + " AND (sa.to_date IS NULL OR sa.to_date >= current_date)";
    static final String HOSTEL_STUDENTS = "SELECT al.student_id FROM hostel.allocation al WHERE al.status = 'ACTIVE' AND al.hostel_id IN ("
            + MY_HOSTELS + ")";

    /** Owner columns for "my" operations, most specific first. */
    private static final List<String> OWNER_COLUMNS = List.of("user_id", "assigned_to_user_id", "reported_by_user_id",
            "raised_by_user_id", "teacher_user_id", "driver_user_id", "guard_user_id", "requested_by_user_id",
            "submitted_by_user_id", "author_user_id", "recipient_user_id", "created_by_user_id");

    private final TableRegistry registry;
    private final JdbcTemplate jdbc;

    public ScopeService(TableRegistry registry, JdbcTemplate jdbc) {
        this.registry = registry;
        this.jdbc = jdbc;
    }

    /** Row predicates for {@code actor} reading or changing rows of {@code table}. */
    public List<Pred> rows(String actor, String tableName, boolean mine) {
        Table t = registry.table(tableName);
        List<Pred> out = new ArrayList<>();
        if (mine) {
            OWNER_COLUMNS.stream().filter(t::has).findFirst()
                    .ifPresent(c -> out.add(Pred.of("\"" + c + "\" = " + ME)));
        }
        switch (actor) {
            case "parent" -> {
                if (tableName.equals("communication.ptm_slot")) {
                    // own bookings, and open slots of PTMs for the children's sections (to book)
                    out.add(Pred.of("\"student_id\" IN (" + MY_CHILDREN + ") OR (\"status\" = 'OPEN' AND \"ptm_id\" IN ("
                            + "SELECT ps.ptm_id FROM communication.ptm_session ps WHERE ps.class_section_id IS NULL OR ps.class_section_id IN ("
                            + "SELECT s.class_section_id FROM academics.student s WHERE s.student_id IN (" + MY_CHILDREN + "))))"));
                } else if (tableName.equals("academics.student") || t.has("student_id")) {
                    out.add(Pred.of("\"student_id\" IN (" + MY_CHILDREN + ")"));
                }
            }
            case "student" -> {
                if (tableName.equals("academics.student")) out.add(Pred.of("\"student_user_id\" = " + ME));
                else if (t.has("student_id")) out.add(Pred.of("\"student_id\" IN (" + MY_STUDENT + ")"));
                else if (t.has("class_section_id")) out.add(Pred.of("\"class_section_id\" IN (SELECT class_section_id FROM academics.student WHERE student_user_id = " + ME + ")"));
            }
            case "teacher" -> {
                if (tableName.equals("communication.ptm_slot")) out.add(Pred.of("\"teacher_user_id\" = " + ME));
                else if (tableName.equals("assessment.exams")) out.add(Pred.of("\"staff_subject_id\" IN (" + MY_SUBJECTS + ") OR \"class_section_id\" IN (SELECT class_section_id FROM academics.class_section WHERE teacher_user_id = " + ME + ") OR \"invigilated_by_user_id\" = " + ME));
                else if (t.has("staff_subject_id")) out.add(Pred.of("\"staff_subject_id\" IN (" + MY_SUBJECTS + ")"));
                else if (t.has("class_section_id")) out.add(Pred.of("\"class_section_id\" IN (" + MY_SECTIONS + ")"));
                else if (t.has("student_id")) out.add(Pred.of("\"student_id\" IN (SELECT student_id FROM academics.student WHERE class_section_id IN (" + MY_SECTIONS + "))"));
            }
            case "warden", "matron", "chiefwarden" -> {
                if (t.has("hostel_id") && !tableName.equals("hostel.hostel")) out.add(Pred.of("\"hostel_id\" IN (" + MY_HOSTELS + ")"));
                else if (tableName.equals("hostel.hostel")) out.add(Pred.of("\"hostel_id\" IN (" + MY_HOSTELS + ")"));
                else if (t.has("student_id")) out.add(Pred.of("\"student_id\" IN (" + HOSTEL_STUDENTS + ")"));
                else if (t.has("room_id")) out.add(Pred.of("\"room_id\" IN (SELECT room_id FROM hostel.room WHERE hostel_id IN (" + MY_HOSTELS + "))"));
            }
            case "driver" -> {
                if (t.has("driver_user_id")) out.add(Pred.of("\"driver_user_id\" = " + ME));
                else if (t.has("trip_id")) out.add(Pred.of("\"trip_id\" IN (SELECT trip_id FROM transport.trip WHERE driver_user_id = " + ME + ")"));
            }
            default -> { }
        }
        return out;
    }

    /**
     * Checks an id the caller names (path parameter or body field) against their scope; 404 when it is outside,
     * so other families' records are not even confirmed to exist.
     */
    @Transactional(readOnly = true)
    public void check(String actor, String field, Object value) {
        if (value == null) return;
        String sql = switch (actor + ":" + field) {
            case "parent:studentId" -> "SELECT EXISTS (" + MY_CHILDREN + " AND sp.student_id = ?)";
            case "parent:outingId" -> "SELECT EXISTS (SELECT 1 FROM hostel.outing_request WHERE outing_id = ? AND student_id IN (" + MY_CHILDREN + "))";
            case "parent:pickupPersonId" -> "SELECT EXISTS (SELECT 1 FROM frontoffice.pickup_person WHERE pickup_person_id = ? AND student_id IN (" + MY_CHILDREN + "))";
            case "parent:paymentId" -> "SELECT EXISTS (SELECT 1 FROM finance.payment WHERE payment_id = ? AND (student_id IN (" + MY_CHILDREN + ") OR paid_by_user_id = " + ME + "))";
            case "parent:reportCardId" -> "SELECT EXISTS (SELECT 1 FROM assessment.report_card WHERE report_card_id = ? AND student_id IN (" + MY_CHILDREN + "))";
            case "student:studentId" -> "SELECT EXISTS (" + MY_STUDENT + " AND s.student_id = ?)";
            case "assistant:studentId" -> "SELECT EXISTS (" + MY_CHILDREN + " AND sp.student_id = ?)";
            case "assistant:classSectionId" -> "SELECT ? IN (" + MY_SECTIONS + ")";
            case "teacher:classSectionId" -> "SELECT ? IN (" + MY_SECTIONS + ")";
            case "teacher:homeworkId" -> "SELECT EXISTS (SELECT 1 FROM operations.homework WHERE homework_id = ? AND (staff_subject_id IN (" + MY_SUBJECTS + ") OR class_section_id IN (" + MY_SECTIONS + ")))";
            case "teacher:studentId" -> "SELECT EXISTS (SELECT 1 FROM academics.student WHERE student_id = ? AND class_section_id IN (" + MY_SECTIONS + "))";
            case "teacher:examId" -> "SELECT EXISTS (SELECT 1 FROM assessment.exams WHERE exam_id = ? AND (staff_subject_id IN (" + MY_SUBJECTS + ") OR class_section_id IN (" + MY_SECTIONS + ") OR invigilated_by_user_id = " + ME + "))";
            case "warden:hostelId", "matron:hostelId", "chiefwarden:hostelId" -> "SELECT ? IN (" + MY_HOSTELS + ")";
            case "warden:studentId", "matron:studentId" -> "SELECT ? IN (" + HOSTEL_STUDENTS + ")";
            case "driver:tripId" -> "SELECT EXISTS (SELECT 1 FROM transport.trip WHERE trip_id = ? AND driver_user_id = " + ME + ")";
            default -> null;
        };
        if (sql == null) return;
        Boolean ok = jdbc.queryForObject(sql, Boolean.class, value instanceof Number n ? n.longValue() : value);
        if (!Boolean.TRUE.equals(ok)) {
            throw new java.util.NoSuchElementException("Not found: " + field + " " + value);
        }
    }

    /** Checks the scope-relevant fields of a request body (e.g. a teacher creating homework for a section). */
    @Transactional(readOnly = true)
    public void checkBody(String actor, Map<String, Object> fields) {
        for (String f : List.of("studentId", "classSectionId", "hostelId", "tripId")) {
            Object v = fields.get(f);
            if (v != null) check(actor, f, v);
        }
    }

    /** Parent / student endpoints that act on one child, when no studentId is given and there is exactly one. */
    public void requireAny(boolean condition, String message) {
        if (!condition) throw new AccessDeniedProblem("OUT_OF_SCOPE", message);
    }
}
