package ng.edu.moaum.portal.allocation;

import org.springframework.security.core.Authentication;
import java.sql.Types;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import jakarta.validation.constraints.NotNull;

import ng.edu.moaum.portal.shared.DomainRuleViolation;
import ng.edu.moaum.portal.shared.OfficeScope;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/** Teaching allocation, worked by the Head of Department (V041). */
@RestController
@RequestMapping("/api/v1/allocation")
class AllocationController {

    private static final String ALLOCATORS = "hasAnyAuthority('OFFICE_hod','OFFICE_dean','OFFICE_academic','OFFICE_dregistrar','OFFICE_registrar','OFFICE_admin','OFFICE_super')";

    private final JdbcClient jdbc;
    private final OfficeScope scope;

    AllocationController(JdbcClient jdbc, OfficeScope scope) {
        this.jdbc = jdbc;
        this.scope = scope;
    }

    public record Assign(@NotNull UUID lecturer, UUID secondExaminer, Boolean overload) {
    }

    private static final String HISTORY_READERS = "hasAnyAuthority('OFFICE_lecturer','OFFICE_hod','OFFICE_exams','OFFICE_facultyexams','OFFICE_dean',"
            + "'OFFICE_facultyofficer','OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar','OFFICE_records','OFFICE_admin','OFFICE_super')";

    /**
     * The history of teaching allocation, every session on record: with scope=me, the courses the acting
     * person has carried (as lecturer or co-lecturer); with scope=department, every course of the acting
     * office's department — the Head of Department's own, or the department an Examinations Officer's grant
     * names (else their home department) — with who carried it, the second examiner, the class size and
     * where its score sheet reached. Newest session first.
     */
    @GetMapping("/history")
    @PreAuthorize(HISTORY_READERS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> history(Authentication authentication, @RequestParam(defaultValue = "me") String scope) {
        UUID me = UUID.fromString(authentication.getName());
        String where;
        Map<String, Object> params = new java.util.HashMap<>();
        if ("department".equalsIgnoreCase(scope)) {
            String dept = this.scope.actingDept();
            if (dept == null) {
                String office = ng.edu.moaum.portal.shared.AuditContextHolder.current().map(c -> c.actorOffice()).orElse("");
                dept = jdbc.sql("""
                        SELECT d.code FROM ref.department d
                         WHERE d.ended_on IS NULL AND upper(d.code) = upper(coalesce(
                            (SELECT a.scope_id FROM iam.office_assignment a
                              WHERE a.person_id = :p AND a.office_code = :o AND a.scope_kind = 'department'
                                AND a.valid_from <= current_date AND (a.valid_to IS NULL OR a.valid_to >= current_date)
                              ORDER BY a.valid_from DESC LIMIT 1),
                            (SELECT sr.home_department FROM hrm.staff_record sr WHERE sr.person_id = :p), ''))
                        """).param("p", me).param("o", office).query(String.class).optional().orElse(null);
            }
            if (dept == null) return List.of();
            where = " WHERE c.dept_code = :d";
            params.put("d", dept);
        } else {
            where = " WHERE (o.lecturer_id = :me OR EXISTS (SELECT 1 FROM catalogue.offering_teacher t WHERE t.offering_id = o.id AND t.lecturer_id = :me))";
            params.put("me", me);
        }
        var q = jdbc.sql("""
                SELECT o.id, o.session, o.semester, o.course_code, c.title, c.units, c.level, o.allocated_on,
                       o.lecturer_id, CASE WHEN lp.id IS NULL THEN NULL ELSE concat_ws(', ', nullif(btrim(lp.surname), ''), nullif(btrim(lp.given_names), '')) END AS lecturer,
                       CASE WHEN sp.id IS NULL THEN NULL ELSE concat_ws(', ', nullif(btrim(sp.surname), ''), nullif(btrim(sp.given_names), '')) END AS second_examiner,
                       (SELECT string_agg(concat_ws(', ', nullif(btrim(tp.surname), ''), nullif(btrim(tp.given_names), '')), '; ' ORDER BY tp.surname)
                          FROM catalogue.offering_teacher t JOIN iam.person tp ON tp.id = t.lecturer_id WHERE t.offering_id = o.id) AS co_lecturers,
                       (SELECT count(*) FROM registration.entry e JOIN registration.course_registration r ON r.id = e.registration_id
                         WHERE e.offering_id = o.id AND e.status IN ('REGISTERED','APPROVED') AND r.status IN ('APPROVED','LOCKED')) AS students,
                       (SELECT sh.stage FROM assessment.score_sheet sh WHERE sh.offering_id = o.id LIMIT 1) AS stage,
                       CASE WHEN o.lecturer_id = :actor THEN 'Lecturer'
                            WHEN EXISTS (SELECT 1 FROM catalogue.offering_teacher t WHERE t.offering_id = o.id AND t.lecturer_id = :actor) THEN 'Co-lecturer'
                            WHEN o.second_examiner_id = :actor THEN 'Second examiner' END AS role
                  FROM catalogue.offering o
                  JOIN catalogue.course c ON c.code = o.course_code
                  LEFT JOIN iam.person lp ON lp.id = o.lecturer_id
                  LEFT JOIN iam.person sp ON sp.id = o.second_examiner_id
                """ + where + " ORDER BY o.session DESC, o.semester DESC, o.course_code LIMIT 600").param("actor", me);
        for (var e : params.entrySet()) q = q.param(e.getKey(), e.getValue());
        return q.query().listOfRows();
    }

    /** the departments a lecturer can be allocated in (reference data, any signed-in staff) */
    @GetMapping("/departments")
    @PreAuthorize("isAuthenticated()")
    @Transactional(readOnly = true)
    List<Map<String, Object>> departments() {
        if (scope.actingHod()) {                            // an HOD sees only their own department
            return jdbc.sql("SELECT code, name, faculty_code FROM ref.department WHERE ended_on IS NULL AND code = :d")
                    .param("d", scope.scopedDept(null)).query().listOfRows();
        }
        return jdbc.sql("SELECT code, name, faculty_code FROM ref.department WHERE ended_on IS NULL ORDER BY name").query().listOfRows();
    }

    /** the department's offerings for a session and semester, with who is on each and how many are registered */
    @GetMapping
    @PreAuthorize(ALLOCATORS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> offerings(@RequestParam String dept, @RequestParam String session,
                                        @RequestParam(defaultValue = "1") int semester,
                                        @RequestParam(required = false) Integer level) {
        dept = scope.scopedDept(dept);                      // an HOD's allocation is limited to their department
        List<Map<String, Object>> rows = jdbc.sql("""
                SELECT o.id, o.course_code, c.title, c.units, c.level, o.allocated_on,
                       (SELECT count(*) FROM registration.entry e JOIN registration.course_registration r ON r.id = e.registration_id
                         WHERE e.offering_id = o.id AND r.status = 'APPROVED') AS registered,
                       o.lecturer_id,
                       CASE WHEN lp.id IS NULL THEN NULL ELSE concat_ws(', ', nullif(btrim(lp.surname), ''), nullif(btrim(lp.given_names), '')) END AS lecturer,
                       o.second_examiner_id,
                       CASE WHEN sp.id IS NULL THEN NULL ELSE concat_ws(', ', nullif(btrim(sp.surname), ''), nullif(btrim(sp.given_names), '')) END AS second_examiner,
                       coalesce((SELECT jsonb_agg(jsonb_build_object('id', t.lecturer_id, 'name', concat_ws(', ', nullif(btrim(tp.surname), ''), nullif(btrim(tp.given_names), ''))) ORDER BY tp.surname)
                                   FROM catalogue.offering_teacher t JOIN iam.person tp ON tp.id = t.lecturer_id
                                  WHERE t.offering_id = o.id), '[]'::jsonb) AS co_lecturers,
                       EXISTS (SELECT 1 FROM assessment.score_sheet sh WHERE sh.offering_id = o.id) AS sheet
                  FROM catalogue.offering o
                  JOIN catalogue.course c ON c.code = o.course_code
                  LEFT JOIN iam.person lp ON lp.id = o.lecturer_id
                  LEFT JOIN iam.person sp ON sp.id = o.second_examiner_id
                 WHERE o.session = :session AND o.semester = :semester AND c.dept_code = :dept
                   AND c.semester = :semester                 -- only courses actually offered in this semester
                   AND c.state <> 'ENDED'                     -- an ended course is not allocated to a lecturer
                   AND (:level::int IS NULL OR c.level = :level)
                 ORDER BY c.level, o.course_code
                """).param("session", session).param("semester", semester).param("dept", dept)
                .param("level", level, java.sql.Types.INTEGER).query().listOfRows();
        // co_lecturers comes back as a jsonb string over JDBC; parse it to a real array so the client gets one
        for (Map<String, Object> row : rows) {
            Object cl = row.get("co_lecturers");
            row.put("co_lecturers", CO.readValue(cl == null ? "[]" : cl.toString(),
                    new tools.jackson.core.type.TypeReference<List<Map<String, Object>>>() { }));
        }
        return rows;
    }

    private static final tools.jackson.databind.ObjectMapper CO = new tools.jackson.databind.ObjectMapper();

    /**
     * The lecturers a course can be allocated to, with their current teaching load. By default the
     * department's own lecturers; with all=true, every lecturer in the University (each labelled with
     * their home department) so a department can assign its course to a lecturer from another
     * department — the cross-department teaching case. The lecturer keeps one dashboard and enters the
     * scores there, whatever department the course belongs to.
     */
    @GetMapping("/lecturers")
    @PreAuthorize(ALLOCATORS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> lecturers(@RequestParam String dept, @RequestParam String session,
                                        @RequestParam(defaultValue = "1") int semester,
                                        @RequestParam(defaultValue = "false") boolean all) {
        dept = scope.scopedDept(dept);                      // an HOD's own-department list stays within their department
        String live = "a.office_code IN ('lecturer', 'hod') AND a.scope_kind = 'department'"
                + " AND a.valid_from <= current_date AND (a.valid_to IS NULL OR a.valid_to >= current_date)";
        String load = "coalesce((SELECT sum(c.units) FROM catalogue.offering o JOIN catalogue.course c ON c.code = o.course_code"
                + " WHERE o.lecturer_id = p.id AND o.session = :session AND o.semester = :semester), 0) AS load";
        if (all) {
            return jdbc.sql("""
                    SELECT p.id, concat_ws(', ', nullif(btrim(p.surname), ''), nullif(btrim(p.given_names), '')) AS name, p.staff_number,
                           (SELECT string_agg(DISTINCT a.scope_id, ', ' ORDER BY a.scope_id) FROM iam.office_assignment a
                             WHERE a.person_id = p.id AND %s) AS department,
                           %s
                      FROM iam.person p
                     WHERE p.ended_on IS NULL
                       AND EXISTS (SELECT 1 FROM iam.office_assignment a WHERE a.person_id = p.id AND %s)
                     ORDER BY name
                    """.formatted(live, load, live))
                    .param("session", session).param("semester", semester).query().listOfRows();
        }
        return jdbc.sql("""
                SELECT DISTINCT p.id, concat_ws(', ', nullif(btrim(p.surname), ''), nullif(btrim(p.given_names), '')) AS name, p.staff_number, :dept AS department,
                       %s
                  FROM iam.person p
                  JOIN iam.office_assignment a ON a.person_id = p.id
                 WHERE %s AND a.scope_id = :dept
                 ORDER BY load, name
                """.formatted(load, live))
                .param("session", session).param("semester", semester).param("dept", dept).query().listOfRows();
    }

    /** a HOD allocates only courses that belong to their own department */
    private void assertHodOwnsOffering(UUID offering) {
        if (!scope.actingHod()) {
            return;
        }
        String hodDept = scope.actingHodDept();
        String offDept = jdbc.sql("SELECT c.dept_code FROM catalogue.offering o JOIN catalogue.course c ON c.code = o.course_code WHERE o.id = :o")
                .param("o", offering).query(String.class).optional().orElse(null);
        if (hodDept == null || !hodDept.equals(offDept)) {
            throw new DomainRuleViolation("ALLOC_DEPT", "A Head of Department allocates only courses that belong to their own department.",
                    new DomainRuleViolation.Remedy("Choose a course in your department; another department allocates its own.", "Head of Department"));
        }
    }

    /** an ended course is off the catalogue and is not allocated to a lecturer (restore it first) */
    private void assertOfferingLive(UUID offering) {
        String state = jdbc.sql("SELECT c.state FROM catalogue.offering o JOIN catalogue.course c ON c.code = o.course_code WHERE o.id = :o")
                .param("o", offering).query(String.class).optional().orElse(null);
        if ("ENDED".equals(state)) {
            throw new DomainRuleViolation("ALLOC_ENDED", "This course has ended, so it cannot be allocated to a lecturer.",
                    new DomainRuleViolation.Remedy("Restore the course on the Department courses page before allocating it.", "Head of Department"));
        }
    }

    /** assign the lead lecturer and a second examiner to an offering */
    @PostMapping("/{offering}")
    @PreAuthorize(ALLOCATORS)
    @Transactional
    Map<String, Object> assign(@PathVariable UUID offering, @RequestBody Assign body) {
        assertHodOwnsOffering(offering);
        assertOfferingLive(offering);
        // an allocation is two small writes; if the offerings table is held by someone opening registration or
        // loading a structure, say so in seconds rather than hang the desk for the length of that work
        jdbc.sql("SET LOCAL lock_timeout = '8s'").update();
        jdbc.sql("SET LOCAL statement_timeout = '25s'").update();
        try {
        jdbc.sql("SELECT catalogue.allocate_offering(:o, :lec, :sec, :ov)")
                .param("o", offering).param("lec", body.lecturer())
                .param("sec", body.secondExaminer(), Types.OTHER)
                .param("ov", Boolean.TRUE.equals(body.overload()))
                .query().singleRow();
        } catch (org.springframework.dao.DataAccessException e) {
            String m = String.valueOf(e.getMostSpecificCause() == null ? e.getMessage() : e.getMostSpecificCause().getMessage());
            if (m.contains("lock timeout") || m.contains("55P03") || m.contains("statement timeout") || m.contains("57014")) {
                throw new ng.edu.moaum.portal.shared.DomainRuleViolation("ALLOC_BUSY",
                        "The offerings are held by another act at the moment — someone is opening registration or loading a course structure.",
                        new ng.edu.moaum.portal.shared.DomainRuleViolation.Remedy("Nothing was saved. Wait a minute and press Save again.", "You"));
            }
            throw e;
        }
        return Map.of("offering", offering, "allocated", true);
    }

    public record Teacher(@NotNull UUID lecturer) {
    }

    /** add a co-lecturer who also teaches the course and enters scores on the shared sheet */
    @PostMapping("/{offering}/teachers")
    @PreAuthorize(ALLOCATORS)
    @Transactional
    Map<String, Object> addTeacher(@PathVariable UUID offering, @RequestBody Teacher body) {
        assertHodOwnsOffering(offering);
        assertOfferingLive(offering);
        Integer n = jdbc.sql("""
                INSERT INTO catalogue.offering_teacher (offering_id, lecturer_id, added_by)
                SELECT :o, :lec, :by
                 WHERE NOT EXISTS (SELECT 1 FROM catalogue.offering WHERE id = :o AND lecturer_id = :lec)
                ON CONFLICT (offering_id, lecturer_id) DO NOTHING
                RETURNING 1
                """).param("o", offering).param("lec", body.lecturer())
                .param("by", scope.actorId(), Types.OTHER).query(Integer.class).optional().orElse(0);
        return Map.of("offering", offering, "lecturer", body.lecturer(), "added", n > 0);
    }

    /** remove a co-lecturer (the lead is changed by re-assigning, not here) */
    @DeleteMapping("/{offering}/teachers/{lecturer}")
    @PreAuthorize(ALLOCATORS)
    @Transactional
    Map<String, Object> removeTeacher(@PathVariable UUID offering, @PathVariable UUID lecturer) {
        assertHodOwnsOffering(offering);
        jdbc.sql("DELETE FROM catalogue.offering_teacher WHERE offering_id = :o AND lecturer_id = :lec")
                .param("o", offering).param("lec", lecturer).update();
        return Map.of("offering", offering, "lecturer", lecturer, "removed", true);
    }
}
