package ng.edu.moaum.portal.student;

import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

import ng.edu.moaum.portal.shared.AuditContext;
import ng.edu.moaum.portal.shared.AuditContextHolder;
import ng.edu.moaum.portal.shared.OfficeScope;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.interceptor.TransactionAspectSupport;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * V572: student phone numbers and e-mail addresses uploaded by the Registry and the departments, under /api/v1/student-contacts —
 * the students missing a contact (the template), the file previewed row by row (nothing kept), then loaded: each row matched to one
 * student and filled only where the student holds no phone or no e-mail (people.load_contacts). The Registry reads and uploads for
 * the University (or a faculty or department it names); a Dean or Faculty Officer for their faculty; a Head of Department for their
 * department — held here, whatever the request names.
 */
@RestController
@RequestMapping("/api/v1/student-contacts")
class ContactUploadController {

    static final String UPLOADERS = "hasAnyAuthority('OFFICE_registrar','OFFICE_dregistrar','OFFICE_records','OFFICE_academic','OFFICE_super',"
            + "'OFFICE_hod','OFFICE_dean','OFFICE_facultyofficer')";

    private final JdbcClient jdbc;
    private final OfficeScope scope;

    ContactUploadController(JdbcClient jdbc, OfficeScope scope) {
        this.jdbc = jdbc;
        this.scope = scope;
    }

    /** the faculty and department the acting office reads: its own when it is bound to one, else what the request names */
    private record Reach(String faculty, String department, String label) {
    }

    private Reach reach(String faculty, String department) {
        if (scope.actingDepartmentOffice()) {
            String d = scope.actingDept();
            String name = d == null ? null : jdbc.sql("SELECT name FROM ref.department WHERE code = :d").param("d", d).query(String.class).optional().orElse(d);
            return new Reach(null, d == null ? "__none__" : d, name == null ? "your department" : "Department of " + name);
        }
        if (scope.actingFacultyOffice()) {
            String f = scope.actingFaculty();
            String name = f == null ? null : jdbc.sql("SELECT name FROM ref.faculty WHERE code = :f").param("f", f).query(String.class).optional().orElse(f);
            return new Reach(f == null ? "__none__" : f, blank(department), name == null ? "your faculty" : "Faculty of " + name);
        }
        return new Reach(blank(faculty), blank(department), blank(department) != null ? "Department " + department.trim() : blank(faculty) != null ? "Faculty " + faculty.trim() : "the University");
    }

    private static String blank(String s) {
        return s == null || s.isBlank() ? null : s.trim();
    }

    /** the counts of the students missing a contact within reach, and the uploads made within it */
    @GetMapping
    @PreAuthorize(UPLOADERS)
    @Transactional(readOnly = true)
    Map<String, Object> summary(@RequestParam(required = false) String faculty, @RequestParam(required = false) String department) {
        Reach r = reach(faculty, department);
        Map<String, Object> out = new LinkedHashMap<>(jdbc.sql("""
                SELECT count(*) AS missing, count(*) FILTER (WHERE no_phone AND no_email) AS neither, count(*) FILTER (WHERE no_phone) AS no_phone,
                       count(*) FILTER (WHERE no_email) AS no_email
                  FROM people.contacts_missing(:f, :d)
                """).param("f", r.faculty(), java.sql.Types.VARCHAR).param("d", r.department(), java.sql.Types.VARCHAR).query().singleRow());
        out.put("scope", r.label());
        out.put("faculty", r.faculty());
        out.put("department", r.department());
        out.put("uploads", jdbc.sql("""
                SELECT u.id, u.uploaded_at, u.file_name, u.office, f.name AS faculty, d.name AS department, u.rows_read, u.students_filled, u.phones_filled,
                       u.emails_filled, u.refused, u.reason, helpdesk.person_name(u.uploaded_by) AS uploaded_by
                  FROM people.contact_upload u
                  LEFT JOIN ref.faculty f ON f.code = u.faculty_code
                  LEFT JOIN ref.department d ON d.code = u.department_code
                 WHERE (CAST(:f AS text) IS NULL OR u.faculty_code = :f OR d.faculty_code = :f) AND (CAST(:d AS text) IS NULL OR u.department_code = :d)
                 ORDER BY u.uploaded_at DESC LIMIT 50
                """).param("f", r.faculty(), java.sql.Types.VARCHAR).param("d", r.department(), java.sql.Types.VARCHAR).query().listOfRows());
        return out;
    }

    /** the students missing a phone or an e-mail within reach, each with what is missing: the template's rows */
    @GetMapping("/missing")
    @PreAuthorize(UPLOADERS)
    @Transactional(readOnly = true)
    Map<String, Object> missing(@RequestParam(required = false) String faculty, @RequestParam(required = false) String department,
                                @RequestParam(defaultValue = "false") boolean neitherOnly) {
        Reach r = reach(faculty, department);
        List<Map<String, Object>> rows = jdbc.sql("""
                SELECT number, name, faculty, department, programme, level, no_phone, no_email FROM people.contacts_missing(:f, :d)
                 WHERE NOT :neither OR (no_phone AND no_email)
                """).param("f", r.faculty(), java.sql.Types.VARCHAR).param("d", r.department(), java.sql.Types.VARCHAR).param("neither", neitherOnly)
                .query().listOfRows();
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("scope", r.label());
        out.put("rows", rows);
        return out;
    }

    public record UploadIn(@Size(max = 255) String fileName, String faculty, String department,
                           @NotNull @Size(min = 1, max = 20000) List<Map<String, Object>> rows) {
    }

    /** the file as the upload would load it, row by row; nothing is kept */
    @PostMapping("/upload/preview")
    @PreAuthorize(UPLOADERS)
    @Transactional
    Map<String, Object> preview(@Valid @RequestBody UploadIn body) {
        Map<String, Object> out = load(body, reach(body.faculty(), body.department()));
        TransactionAspectSupport.currentTransactionStatus().setRollbackOnly();
        return out;
    }

    /** the same rows loaded — the empty contacts filled — and the upload kept with its counts and reason */
    @PostMapping("/upload")
    @PreAuthorize(UPLOADERS)
    @Transactional
    Map<String, Object> upload(@Valid @RequestBody UploadIn body) {
        Reach r = reach(body.faculty(), body.department());
        Map<String, Object> out = load(body, r);
        AuditContext ctx = AuditContextHolder.current().orElse(null);
        @SuppressWarnings("unchecked") Map<String, Integer> fields = (Map<String, Integer>) out.get("fields");
        @SuppressWarnings("unchecked") Map<String, Integer> counts = (Map<String, Integer>) out.get("counts");
        Object id = jdbc.sql("""
                INSERT INTO people.contact_upload (file_name, office, faculty_code, department_code, rows_read, students_filled, phones_filled, emails_filled,
                                                   refused, reason, uploaded_by)
                VALUES (:file, :office, :f, :d, :n, :students, :phones, :emails, :refused, :reason, :by) RETURNING id
                """).param("file", blank(body.fileName()), java.sql.Types.VARCHAR).param("office", ctx == null ? "registrar" : ctx.actorOffice())
                .param("f", r.faculty(), java.sql.Types.VARCHAR).param("d", r.department(), java.sql.Types.VARCHAR)
                .param("n", out.get("total")).param("students", counts.get("FILLED")).param("phones", fields.get("phones")).param("emails", fields.get("emails"))
                .param("refused", (Integer) out.get("total") - counts.get("FILLED") - counts.get("ALREADY"))
                .param("reason", ctx == null || ctx.reason() == null || ctx.reason().isBlank() ? "Student contacts uploaded" : ctx.reason())
                .param("by", ctx == null ? null : ctx.actorId(), java.sql.Types.OTHER)
                .query().singleValue();
        out.put("uploadId", id);
        return out;
    }

    private Map<String, Object> load(UploadIn body, Reach r) {
        List<Map<String, String>> rows = body.rows().stream().map(m -> Map.of(
                "number", text(m.get("number")), "phone", text(m.get("phone")), "email", text(m.get("email")))).toList();
        String json;
        try {
            json = new tools.jackson.databind.ObjectMapper().writeValueAsString(rows);
        } catch (RuntimeException e) {
            throw new IllegalArgumentException("the rows could not be read", e);
        }
        List<Map<String, Object>> loaded = jdbc.sql("SELECT * FROM people.load_contacts(CAST(:rows AS jsonb), :f, :d)")
                .param("rows", json).param("f", r.faculty(), java.sql.Types.VARCHAR).param("d", r.department(), java.sql.Types.VARCHAR)
                .query().listOfRows();
        Map<String, Integer> counts = new LinkedHashMap<>();
        for (String k : List.of("FILLED", "ALREADY", "REFUSED", "NO_STUDENT", "AMBIGUOUS", "OUTSIDE_SCOPE", "DUPLICATE_ROW", "INCOMPLETE")) counts.put(k, 0);
        int phones = 0, emails = 0;
        for (Map<String, Object> o : loaded) {
            counts.merge(String.valueOf(o.get("outcome")), 1, Integer::sum);
            if ("FILL".equals(o.get("phone_outcome"))) phones++;
            if ("FILL".equals(o.get("email_outcome"))) emails++;
        }
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("scope", r.label());
        out.put("total", loaded.size());
        out.put("counts", counts);
        out.put("fields", Map.of("phones", phones, "emails", emails));
        out.put("rows", loaded);
        return out;
    }

    private static String text(Object v) {
        return v == null ? "" : String.valueOf(v).trim();
    }
}
