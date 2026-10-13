package ng.edu.moaum.portal.student;

import java.sql.Types;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import ng.edu.moaum.portal.shared.AuditContext;
import ng.edu.moaum.portal.shared.AuditContextHolder;
import ng.edu.moaum.portal.shared.OfficeScope;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * V426: the offices' view of where every student's biodata stands — the counts (up to date, incomplete, to review, outdated;
 * who came over from the old portal and has reviewed; who has no address, a bad one, or has never signed in), the students
 * behind each count, filtered and searched, and the data-quality picture (missing, bad and shared addresses). Read from the
 * reading the scheduler takes every quarter of an hour (its time is shown), bound to the office's own faculty or department
 * for a Dean, a faculty officer or a Head (OfficeScope), University-wide for ICT, the Registry, the Academic Office, Records,
 * Student Affairs and the administrators.
 */
@RestController
@RequestMapping("/api/v1/biodata/compliance")
@PreAuthorize("hasAnyAuthority('OFFICE_ict','OFFICE_admin','OFFICE_super','OFFICE_registrar','OFFICE_dregistrar','OFFICE_academic','OFFICE_records','OFFICE_dsa','OFFICE_dean','OFFICE_facultyofficer','OFFICE_hod')")
class BiodataComplianceViewController {

    private final JdbcClient jdbc;
    private final OfficeScope scope;

    BiodataComplianceViewController(JdbcClient jdbc, OfficeScope scope) {
        this.jdbc = jdbc;
        this.scope = scope;
    }

    @GetMapping
    @Transactional(readOnly = true)
    Map<String, Object> summary(@RequestParam(required = false) String faculty, @RequestParam(required = false) String department) {
        OfficeScope.Bound b = scope.bound(blank(faculty), blank(department), null);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("faculty", b.fac());
        out.put("department", b.dept());
        out.put("summary", jdbc.sql("SELECT * FROM people.biodata_compliance_summary(:f, :d)").param("f", b.fac(), Types.VARCHAR).param("d", b.dept(), Types.VARCHAR).query().singleRow());
        out.put("quality", jdbc.sql("SELECT * FROM people.contact_quality(:f, :d)").param("f", b.fac(), Types.VARCHAR).param("d", b.dept(), Types.VARCHAR).query().singleRow());
        out.put("gate", jdbc.sql("SELECT coalesce((SELECT enabled FROM people.biodata_gate LIMIT 1), false) AS enabled, b.remind_enabled, b.review_days FROM people.biodata_setting b WHERE b.id").query().singleRow());
        out.put("requirements", jdbc.sql("SELECT r.item, coalesce(f.label, 'Passport photograph') AS label, r.required FROM people.biodata_requirement r LEFT JOIN ref.biodata_field f ON f.field = r.field ORDER BY r.item = 'PASSPORT' DESC, f.ord").query().listOfRows());
        out.put("faculties", jdbc.sql("SELECT code, name FROM ref.faculty ORDER BY name").query().listOfRows());
        out.put("departments", jdbc.sql("SELECT code, name, faculty_code FROM ref.department WHERE ended_on IS NULL ORDER BY name").query().listOfRows());
        // V434: what is missing, and the counts by faculty (by department within a faculty), from the same reading
        out.put("items", jdbc.sql("SELECT * FROM people.biodata_missing_items(:f, :d)").param("f", b.fac(), Types.VARCHAR).param("d", b.dept(), Types.VARCHAR).query().listOfRows());
        out.put("units", jdbc.sql("SELECT * FROM people.biodata_compliance_units(:f, :d)").param("f", b.fac(), Types.VARCHAR).param("d", b.dept(), Types.VARCHAR).query().listOfRows());
        return out;
    }

    /** the students behind a count: filtered, searched, paged; the page carries the total */
    @GetMapping("/students")
    @Transactional(readOnly = true)
    Map<String, Object> students(@RequestParam(required = false) String status, @RequestParam(required = false) String faculty,
                                 @RequestParam(required = false) String department, @RequestParam(required = false) String programme,
                                 @RequestParam(required = false) Integer level, @RequestParam(required = false) String session,
                                 @RequestParam(required = false) String entryMode, @RequestParam(required = false) Boolean migrated,
                                 @RequestParam(required = false) String q, @RequestParam(defaultValue = "1") int page, @RequestParam(defaultValue = "100") int size,
                                 @RequestParam(required = false) String missing, @RequestParam(required = false) String sex) {
        OfficeScope.Bound b = scope.bound(blank(faculty), blank(department), blank(programme));
        int limit = Math.max(1, Math.min(size, 2000));
        int offset = Math.max(0, page - 1) * limit;
        List<Map<String, Object>> rows = jdbc.sql("""
                SELECT * FROM people.biodata_status_list(:status, :f, :d, :p, :l, :s, :m, :mig, :q, :n, :o, :missing, :sex)
                """).param("status", blank(status) == null ? null : status.trim().toUpperCase(), Types.VARCHAR)
                .param("f", b.fac(), Types.VARCHAR).param("d", b.dept(), Types.VARCHAR).param("p", b.prog(), Types.VARCHAR)
                .param("l", level, Types.INTEGER).param("s", blank(session), Types.VARCHAR).param("m", blank(entryMode), Types.VARCHAR)
                .param("mig", migrated, Types.BOOLEAN).param("q", blank(q), Types.VARCHAR).param("n", limit).param("o", offset)
                .param("missing", blank(missing), Types.VARCHAR).param("sex", blank(sex) == null ? null : sex.trim().toUpperCase(), Types.VARCHAR)
                .query().listOfRows();
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("rows", rows);
        out.put("total", rows.isEmpty() ? 0 : ((Number) rows.get(0).get("total")).longValue());
        out.put("page", Math.max(1, page));
        out.put("size", limit);
        out.put("computedAt", jdbc.sql("SELECT computed_at FROM people.biodata_snapshot_run WHERE id").query(java.time.OffsetDateTime.class).optional().orElse(null));
        return out;
    }

    /** addresses shared by more than one student — an e-mail or a phone on several records */
    @GetMapping("/duplicates")
    @Transactional(readOnly = true)
    List<Map<String, Object>> duplicates(@RequestParam(defaultValue = "EMAIL") String kind, @RequestParam(required = false) String faculty,
                                         @RequestParam(required = false) String department) {
        OfficeScope.Bound b = scope.bound(blank(faculty), blank(department), null);
        return jdbc.sql("SELECT * FROM people.duplicate_contacts(:k, :f, :d, 300)").param("k", "PHONE".equalsIgnoreCase(kind) ? "PHONE" : "EMAIL")
                .param("f", b.fac(), Types.VARCHAR).param("d", b.dept(), Types.VARCHAR).query().listOfRows();
    }

    /** V430: staff reach — for every active person with an office, whether the e-mail and the phone are present and usable;
     *  the counts, and the people behind a status, filtered by office and searched; never bound to a faculty (staff are the
     *  University's) */
    @GetMapping("/staff")
    @PreAuthorize("hasAnyAuthority('OFFICE_ict','OFFICE_admin','OFFICE_super','OFFICE_registrar','OFFICE_dregistrar','OFFICE_hrm','OFFICE_records')")
    @Transactional(readOnly = true)
    Map<String, Object> staff(@RequestParam(required = false) String status, @RequestParam(required = false) String office,
                              @RequestParam(required = false) String q, @RequestParam(defaultValue = "1") int page, @RequestParam(defaultValue = "100") int size) {
        int limit = Math.max(1, Math.min(size, 2000));
        int offset = Math.max(0, page - 1) * limit;
        List<Map<String, Object>> rows = jdbc.sql("SELECT * FROM iam.staff_reach_list(:st, :o, :q, :n, :off)")
                .param("st", blank(status) == null ? null : status.trim().toUpperCase(), Types.VARCHAR).param("o", blank(office), Types.VARCHAR)
                .param("q", blank(q), Types.VARCHAR).param("n", limit).param("off", offset).query().listOfRows();
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("summary", jdbc.sql("SELECT * FROM iam.staff_reach_summary(:o)").param("o", blank(office), Types.VARCHAR).query().singleRow());
        out.put("rows", rows);
        out.put("total", rows.isEmpty() ? 0 : ((Number) rows.get(0).get("total")).longValue());
        out.put("page", Math.max(1, page));
        out.put("size", limit);
        out.put("remindEnabled", jdbc.sql("SELECT staff_contact_remind FROM platform.notice_setting WHERE id").query(Boolean.class).single());
        out.put("offices", jdbc.sql("SELECT code, label FROM ref.office WHERE code NOT IN ('student', 'applicant') ORDER BY label").query().listOfRows());
        return out;
    }

    /** the reading taken now, by hand (ICT and the administrators); the scheduler takes it every quarter of an hour regardless */
    @PostMapping("/refresh")
    @PreAuthorize("hasAnyAuthority('OFFICE_ict','OFFICE_admin','OFFICE_super','OFFICE_registrar')")
    @Transactional
    Map<String, Object> refresh() {
        AuditContext ctx = AuditContextHolder.required();
        Integer n = jdbc.sql("SELECT people.refresh_biodata_snapshot(NULL)").query(Integer.class).single();
        return Map.of("students", n == null ? 0 : n, "by", String.valueOf(ctx.actorOffice()),
                "computedAt", String.valueOf(jdbc.sql("SELECT computed_at FROM people.biodata_snapshot_run WHERE id").query(java.time.OffsetDateTime.class).optional().orElse(null)));
    }

    private static String blank(String s) {
        return s == null || s.isBlank() ? null : s.trim();
    }
}
