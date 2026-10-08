package ng.edu.moaum.portal.cbt;

import java.sql.Types;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotNull;

import ng.edu.moaum.portal.shared.AuditContext;
import ng.edu.moaum.portal.shared.AuditContextHolder;
import ng.edu.moaum.portal.shared.NotFound;
import ng.edu.moaum.portal.shared.OfficeScope;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * V364: which courses the University examines by CBT. No course is assumed to be one: the Academic Office, the Registry
 * or Examinations and Records allows a course (the GST and EPS offices their own General Studies courses), and an
 * examination is created, published and sat only on an allowed course. Read by the examinations offices within their
 * scope; a course's switch is on the audited catalogue.
 */
@RestController
@RequestMapping("/api/v1/cbt/catalogue")
class CbtCourseController {

    private static final String READERS = "hasAnyAuthority('OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar','OFFICE_records','OFFICE_super','OFFICE_admin',"
            + "'OFFICE_exams','OFFICE_facultyexams','OFFICE_hod','OFFICE_dean','OFFICE_gst','OFFICE_eps')";
    private static final String SETTERS = "hasAnyAuthority('OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar','OFFICE_records','OFFICE_super','OFFICE_gst','OFFICE_eps')";

    private final JdbcClient jdbc;
    private final OfficeScope scope;

    CbtCourseController(JdbcClient jdbc, OfficeScope scope) {
        this.jdbc = jdbc;
        this.scope = scope;
    }

    public record Switch(@NotNull Boolean enabled) {
    }

    private static String acting() {
        return AuditContextHolder.current().map(AuditContext::actorOffice).orElse("");
    }

    /** the courses, searched and paged on the server, within the acting office's scope; the GST and EPS offices see their own */
    @GetMapping
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> list(@RequestParam(required = false) String q, @RequestParam(required = false) String enabled, @RequestParam(required = false) String dept,
                             @RequestParam(required = false) Integer level, @RequestParam(defaultValue = "1") int page, @RequestParam(defaultValue = "50") int size) {
        OfficeScope.Bound b = scope.bound(null, dept, null);
        String acting = acting();
        String office = "gst".equals(acting) ? "GST" : "eps".equals(acting) ? "EPS" : null;
        Boolean on = enabled == null || enabled.isBlank() ? null : Boolean.valueOf(enabled.trim());
        int sz = Math.max(1, Math.min(size, 200)), pg = Math.max(1, page);
        String where = """
                 WHERE c.state <> 'ENDED'
                   AND (:q::text IS NULL OR lower(c.code) LIKE :q OR lower(c.title) LIKE :q)
                   AND (:on::boolean IS NULL OR c.cbt_enabled = :on)
                   AND (:dept::text IS NULL OR c.dept_code = :dept)
                   AND (:fac::text IS NULL OR d.faculty_code = :fac)
                   AND (:level::int IS NULL OR c.level = :level)
                   AND (:office::text IS NULL OR c.general_office = :office)
                """;
        java.util.function.UnaryOperator<JdbcClient.StatementSpec> bind = spec -> spec
                .param("q", q == null || q.isBlank() ? null : "%" + q.trim().toLowerCase() + "%", Types.VARCHAR).param("on", on, Types.BOOLEAN)
                .param("dept", b.dept(), Types.VARCHAR).param("fac", b.fac(), Types.VARCHAR).param("level", level, Types.INTEGER).param("office", office, Types.VARCHAR);
        long total = bind.apply(jdbc.sql("SELECT count(*) FROM catalogue.course c LEFT JOIN ref.department d ON d.code = c.dept_code" + where)).query(Long.class).single();
        List<Map<String, Object>> rows = bind.apply(jdbc.sql("""
                SELECT c.code, c.title, c.kind, c.general_office, c.level, c.semester, c.units, c.dept_code, d.name AS department, c.cbt_enabled,
                       (SELECT count(*) FROM assessment.question x WHERE x.course_code = c.code AND x.active) AS questions,
                       (SELECT count(*) FROM assessment.cbt_exam e WHERE e.course_code = c.code) AS exams,
                       (SELECT count(*) FROM assessment.cbt_exam e WHERE e.course_code = c.code AND e.state IN ('DRAFT', 'SCHEDULED', 'PUBLISHED', 'CLOSED')) AS open_exams
                  FROM catalogue.course c LEFT JOIN ref.department d ON d.code = c.dept_code
                """ + where + " ORDER BY c.code LIMIT :lim OFFSET :off")).param("lim", sz).param("off", (long) (pg - 1) * sz).query().listOfRows();
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("rows", rows);
        out.put("total", total);
        out.put("page", pg);
        out.put("size", sz);
        out.put("canSet", List.of("academic", "registrar", "dregistrar", "records", "super", "gst", "eps").contains(acting));
        return out;
    }

    /** V365: allow a JUPEB subject to be examined by CBT, or withdraw it — the JUPEB Office's own subjects */
    @PutMapping("/jupeb/{id}")
    @PreAuthorize("hasAnyAuthority('OFFICE_jupeb','OFFICE_super')")
    @Transactional
    Map<String, Object> setJupeb(@PathVariable java.util.UUID id, @Valid @RequestBody Switch in) {
        return jdbc.sql("SELECT id, code, title, cbt_enabled FROM jupeb.set_subject_cbt(:id, :on)").param("id", id).param("on", in.enabled()).query().singleRow();
    }

    /** allow a course to be examined by CBT, or withdraw it (refused while an examination of it is still to be completed) */
    @PutMapping("/{code}")
    @PreAuthorize(SETTERS)
    @Transactional
    Map<String, Object> set(@PathVariable String code, @Valid @RequestBody Switch in) {
        Map<String, Object> c = jdbc.sql("SELECT code, kind, general_office FROM catalogue.course WHERE upper(code) = upper(:c)").param("c", code.trim())
                .query().listOfRows().stream().findFirst().orElseThrow(() -> new NotFound("course", code));
        String acting = acting();
        if ("gst".equals(acting) || "eps".equals(acting)) {
            String own = "gst".equals(acting) ? "GST" : "EPS";
            // V367: a course is the office's only when it is classified the office's (a course marked general by an upload but in no office's family is not)
            if (!own.equals(c.get("general_office"))) {
                throw new AccessDeniedException("The " + own + " office allows CBT for its own General Studies courses; " + c.get("code") + " is not one of them.");
            }
        }
        return jdbc.sql("SELECT code, title, cbt_enabled FROM catalogue.set_cbt_enabled(:c, :on)").param("c", c.get("code")).param("on", in.enabled()).query().singleRow();
    }
}
