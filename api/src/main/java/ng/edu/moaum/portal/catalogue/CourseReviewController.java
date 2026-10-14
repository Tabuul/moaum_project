package ng.edu.moaum.portal.catalogue;

import java.sql.Types;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.TreeMap;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotEmpty;
import jakarta.validation.constraints.Size;

import ng.edu.moaum.portal.shared.AuditContext;
import ng.edu.moaum.portal.shared.AuditContextHolder;
import ng.edu.moaum.portal.shared.DomainRuleViolation;
import ng.edu.moaum.portal.shared.OfficeScope;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * V445 — the ownership review of the course pool: the review's dashboard, a course's review status, the bulk owner correction
 * (previewed, then applied in one transaction), a course's field-level history, and possible duplicates by title. The owner
 * itself is changed only through V338's change_owner — here many at once — never by a flag.
 */
@RestController
@RequestMapping("/api/v1/catalogue")
class CourseReviewController {

    private static final String READERS = "hasAnyAuthority('OFFICE_hod','OFFICE_dean','OFFICE_academic','OFFICE_dregistrar','OFFICE_registrar','OFFICE_admin','OFFICE_super','OFFICE_audit','OFFICE_deputyaudit','OFFICE_ict')";
    private static final String REVIEWERS = "hasAnyAuthority('OFFICE_hod','OFFICE_dean','OFFICE_academic','OFFICE_dregistrar','OFFICE_registrar','OFFICE_admin','OFFICE_super')";
    private static final String CENTRAL = "hasAnyAuthority('OFFICE_academic','OFFICE_dregistrar','OFFICE_registrar','OFFICE_admin','OFFICE_super')";

    private final JdbcClient jdbc;
    private final OfficeScope scope;

    CourseReviewController(JdbcClient jdbc, OfficeScope scope) {
        this.jdbc = jdbc;
        this.scope = scope;
    }

    public record ReviewIn(@NotBlank @Size(max = 20) String status, @Size(max = 1000) String note) { }
    public record BulkOwnerIn(@NotEmpty @Size(max = 500) List<@NotBlank @Size(max = 24) String> codes, @NotBlank @Size(max = 120) String department,
                              @Size(max = 120) String programme, @Size(max = 400) String reason, Boolean dryRun) { }

    /** the review's dashboard: the pool by state, by review status, by issue; departments holding courses */
    @GetMapping("/review/summary")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> summary() {
        return jdbc.sql("SELECT * FROM catalogue.review_summary()").query().singleRow();
    }

    /** the review's word on a course: the central offices on any, a Head of Department or Dean on their own department's (faculty's) */
    @PostMapping("/courses/{code}/review")
    @PreAuthorize(REVIEWERS)
    @Transactional
    Map<String, Object> review(@PathVariable String code, @Valid @RequestBody ReviewIn body) {
        AuditContext ctx = AuditContextHolder.required();
        String office = ctx.actorOffice();
        String officeDept = scope.actingDepartmentOffice() ? scope.actingDept() : scope.actingFacultyOffice() ? scope.actingFaculty() : null;
        Map<String, Object> row = jdbc.sql("SELECT code, review_status, review_note, reviewed_office, reviewed_at FROM catalogue.set_course_review(:c, :s, :n, :a, :o, :d)")
                .param("c", code).param("s", body.status().trim().toUpperCase()).param("n", body.note(), Types.VARCHAR)
                .param("a", ctx.actorId()).param("o", office).param("d", officeDept, Types.VARCHAR).query().singleRow();
        return row;
    }

    /** many courses to one owner: a dry run answers what would move (by current department) and what hangs on them; the real
     *  act moves them in one transaction with one reason, each on the owner trail — all or none */
    @PostMapping("/courses/bulk-owner")
    @PreAuthorize(CENTRAL)
    @Transactional
    Map<String, Object> bulkOwner(@Valid @RequestBody BulkOwnerIn body) {
        AuditContextHolder.required();
        List<String> codes = body.codes().stream().map(c -> c.trim().toUpperCase().replaceAll("\\s+", " ")).distinct().toList();
        String[] arr = codes.toArray(String[]::new);
        List<Map<String, Object>> current = jdbc.sql("""
                SELECT c.code, c.title, c.dept_code, d.name AS dept_name, c.state,
                       (SELECT count(*) FROM registration.entry e JOIN catalogue.offering o ON o.id = e.offering_id WHERE o.course_code = c.code) AS registrations,
                       (SELECT count(*) FROM assessment.score_sheet sh JOIN catalogue.offering o ON o.id = sh.offering_id WHERE o.course_code = c.code) AS sheets,
                       (SELECT count(*) FROM catalogue.offering o WHERE o.course_code = c.code AND o.lecturer_id IS NOT NULL) AS allocations
                  FROM catalogue.course c LEFT JOIN ref.department d ON d.code = c.dept_code
                 WHERE c.code = ANY (:codes) ORDER BY c.code
                """).param("codes", arr).query().listOfRows();
        if (current.size() != codes.size()) {
            List<String> found = current.stream().map(r -> String.valueOf(r.get("code"))).toList();
            String missing = String.join(", ", codes.stream().filter(c -> !found.contains(c)).toList());
            throw new DomainRuleViolation("CAT_OWNER_BULK_UNKNOWN", "No course is coded " + missing + ".",
                    new DomainRuleViolation.Remedy("Choose courses from the list.", "You"));
        }
        Map<String, Long> byDept = new TreeMap<>();
        long registrations = 0, sheets = 0, allocations = 0;
        for (Map<String, Object> r : current) {
            byDept.merge(String.valueOf(r.get("dept_name") == null ? r.get("dept_code") : r.get("dept_name")), 1L, Long::sum);
            registrations += ((Number) r.get("registrations")).longValue();
            sheets += ((Number) r.get("sheets")).longValue();
            allocations += ((Number) r.get("allocations")).longValue();
        }
        Map<String, Object> target = jdbc.sql("SELECT d.code, d.name, f.name AS faculty FROM ref.department d LEFT JOIN ref.faculty f ON f.code = d.faculty_code WHERE d.ended_on IS NULL AND (upper(d.code) = upper(:d) OR upper(d.name) = upper(:d)) LIMIT 1")
                .param("d", body.department().trim()).query().listOfRows().stream().findFirst()
                .orElseThrow(() -> new DomainRuleViolation("CAT_OWNER_DEPT", "No live department is coded or named " + body.department().trim() + ".",
                        new DomainRuleViolation.Remedy("Choose a department on the register.", "You")));
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("courses", current.size());
        out.put("byDepartment", byDept);
        out.put("target", target);
        out.put("impact", Map.of("registrations", registrations, "scoreSheets", sheets, "allocations", allocations));
        out.put("alreadyOwned", current.stream().filter(r -> String.valueOf(target.get("code")).equals(r.get("dept_code"))).count());
        if (body.dryRun() == null || body.dryRun()) {   // a preview unless the act is asked for in so many words
            out.put("dryRun", true);
            return out;
        }
        if (body.reason() == null || body.reason().trim().length() < 5) {
            throw new DomainRuleViolation("CAT_OWNER_REASON", "Say why the courses change owner.",
                    new DomainRuleViolation.Remedy("A sentence will do: 'uploaded under the wrong department'.", "You"));
        }
        List<Map<String, Object>> moved = jdbc.sql("SELECT code, from_dept, to_dept FROM catalogue.change_owner_bulk(:codes, :d, :p, :r)")
                .param("codes", arr).param("d", String.valueOf(target.get("code"))).param("p", body.programme(), Types.VARCHAR).param("r", body.reason().trim())
                .query().listOfRows();
        out.put("dryRun", false);
        out.put("moved", moved);
        return out;
    }

    /** what changed on a course and when: every field from the audit spine, each owner change, each binding added or ended */
    @GetMapping("/courses/{code}/history")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> history(@PathVariable String code, @RequestParam(defaultValue = "200") int limit) {
        String c = jdbc.sql("SELECT coalesce(catalogue.resolve_course_code(:c), :c)").param("c", code.trim().toUpperCase().replaceAll("\\s+", " ")).query(String.class).single();
        List<Map<String, Object>> rows = jdbc.sql("SELECT at, action, field, old_value, new_value, actor, actor_office, reason, source FROM catalogue.course_history(:c, :n)")
                .param("c", c).param("n", Math.max(1, Math.min(limit, 1000))).query().listOfRows();
        Map<String, Object> stamps = jdbc.sql("""
                SELECT c.created_at, helpdesk.person_name(c.created_by) AS created_by, c.updated_at, helpdesk.person_name(c.updated_by) AS updated_by,
                       c.review_status, c.review_note, c.reviewed_at, c.reviewed_office, helpdesk.person_name(c.reviewed_by) AS reviewed_by,
                       catalogue.course_issues(c.code) AS issues
                  FROM catalogue.course c WHERE c.code = :c
                """).param("c", c).query().listOfRows().stream().findFirst().orElse(Map.of());
        Map<String, Object> out = new LinkedHashMap<>(stamps);
        out.put("code", c);
        out.put("rows", rows);
        return out;
    }

    /** possible duplicates by title — the same title under two codes at the same level and semester; for a person to investigate */
    @GetMapping("/possible-duplicates")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> possibleDuplicates() {
        List<Map<String, Object>> rows = new ArrayList<>(jdbc.sql("SELECT * FROM catalogue.possible_duplicates()").query().listOfRows());
        return rows;
    }
}
