package ng.edu.moaum.portal.catalogue;

import java.sql.Types;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

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

import ng.edu.moaum.portal.shared.DomainRuleViolation;
import ng.edu.moaum.portal.shared.NotFound;

/**
 * The course catalogue's administration (V338): the reset that clears the active catalogue of the University, a faculty, a
 * department or a programme without touching academic history; the catalogue upload that names each course's owner and the
 * programmes that offer it as CORE or ELECTIVE; and the change of a course's owner. A reset and an upload are central acts
 * (the Directorate of ICT and the Academic Office); no Head of Department or support officer resets the catalogue.
 */
@RestController
@RequestMapping("/api/v1/catalogue")
class CourseCatalogueAdminController {

    /** who resets the catalogue and uploads it: the Directorate of ICT and the Academic Office */
    private static final String CENTRAL = "hasAnyAuthority('OFFICE_ict','OFFICE_academic','OFFICE_super')";
    /** who changes a course's owner: the Academic Office, the Registry and the Directorate of ICT */
    private static final String OWNERSHIP = "hasAnyAuthority('OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar','OFFICE_ict','OFFICE_super')";

    private final JdbcClient jdbc;
    private final tools.jackson.databind.ObjectMapper json;

    CourseCatalogueAdminController(JdbcClient jdbc, tools.jackson.databind.ObjectMapper json) {
        this.jdbc = jdbc;
        this.json = json;
    }

    private Object parse(Object jsonb) {
        return jsonb == null ? null : json.readValue(jsonb.toString(), Object.class);
    }

    private static String blank(String s) {
        return s == null || s.isBlank() ? null : s.trim();
    }

    /* ── the reset ── */

    /** what a reset of a scope would do: courses, bindings, offerings removed and kept, courses archived and removed, what hangs on them */
    @GetMapping("/reset/preview")
    @PreAuthorize(CENTRAL)
    @Transactional(readOnly = true)
    Object resetPreview(@RequestParam String scope, @RequestParam(required = false) String ref) {
        return parse(jdbc.sql("SELECT catalogue.course_reset_preview(:s, :r)::text")
                .param("s", scope).param("r", blank(ref), Types.VARCHAR).query(String.class).single());
    }

    public record ResetIn(@NotBlank String scope, @Size(max = 200) String ref,
                          @NotBlank @Size(min = 5, max = 2000) String reason, @NotBlank String confirm) {
    }

    /** reset a scope of the catalogue: one transaction under one reference, history archived and never deleted */
    @PostMapping("/reset")
    @PreAuthorize(CENTRAL)
    @Transactional
    Object reset(@Valid @RequestBody ResetIn body) {
        return parse(jdbc.sql("SELECT catalogue.course_reset(:s, :r, :why, :confirm)::text")
                .param("s", body.scope()).param("r", blank(body.ref()), Types.VARCHAR)
                .param("why", body.reason()).param("confirm", body.confirm()).query(String.class).single());
    }

    /** the resets done, newest first */
    @GetMapping("/reset/history")
    @PreAuthorize(CENTRAL)
    @Transactional(readOnly = true)
    List<Map<String, Object>> resetHistory() {
        return jdbc.sql("""
                SELECT r.id, r.ref, r.scope, r.scope_ref, r.scope_label, r.reason, r.courses_in_scope, r.bindings_removed, r.offerings_removed,
                       r.offerings_kept, r.archived, r.deleted, r.proposals_cancelled, r.programmes_affected, r.departments_affected, r.status,
                       r.performed_at, r.performed_office, helpdesk.person_name(r.performed_by) AS performed_by
                  FROM catalogue.course_reset r ORDER BY r.performed_at DESC LIMIT 100
                """).query().listOfRows();
    }

    /** one reset, item by item */
    @GetMapping("/reset/{id}")
    @PreAuthorize(CENTRAL)
    @Transactional(readOnly = true)
    Map<String, Object> resetOne(@PathVariable UUID id) {
        Map<String, Object> head = jdbc.sql("SELECT * FROM catalogue.course_reset WHERE id = :id").param("id", id)
                .query().listOfRows().stream().findFirst().orElseThrow(() -> new NotFound("course reset", id));
        List<Map<String, Object>> items = jdbc.sql("""
                SELECT i.course_code, i.action, i.programme_code, p.name AS programme, i.level, i.detail::text AS detail, i.at
                  FROM catalogue.course_reset_item i LEFT JOIN ref.programme p ON p.code = i.programme_code
                 WHERE i.reset_id = :id ORDER BY i.action, i.course_code, i.programme_code
                """).param("id", id).query().listOfRows();
        for (Map<String, Object> i : items) {
            i.put("detail", parse(i.get("detail")));
        }
        Map<String, Object> out = new LinkedHashMap<>(head);
        out.put("items", items);
        return out;
    }

    /* ── the catalogue upload with owners and offerings ── */

    public record ImportIn(@NotNull @Size(max = 20000) List<Map<String, Object>> rows, @Size(max = 300) String fileName) {
    }

    /** judge a catalogue upload (commit=false), or write it (commit=true) — only a file with no invalid row is written */
    @PostMapping("/catalogue-import")
    @PreAuthorize(CENTRAL)
    @Transactional
    Object importCatalogue(@Valid @RequestBody ImportIn body, @RequestParam(defaultValue = "false") boolean commit) {
        if (body.rows().isEmpty()) {
            throw new DomainRuleViolation("CAT_IMPORT_EMPTY", "The file has no rows to read.",
                    new DomainRuleViolation.Remedy("Download the template, fill one row per programme that offers each course, and upload it.", "Directorate of ICT"));
        }
        return parse(jdbc.sql("SELECT catalogue.import_catalogue(:rows::jsonb, :commit, :file)::text")
                .param("rows", json.writeValueAsString(body.rows())).param("commit", commit)
                .param("file", blank(body.fileName()), Types.VARCHAR).query(String.class).single());
    }

    /** the catalogue uploads committed, newest first */
    @GetMapping("/catalogue-import/history")
    @PreAuthorize(CENTRAL)
    @Transactional(readOnly = true)
    List<Map<String, Object>> importHistory() {
        return jdbc.sql("""
                SELECT i.id, i.ref, i.file_name, i.rows, i.courses_created, i.courses_updated, i.courses_revived, i.owner_changes,
                       i.offerings_created, i.offerings_updated, i.prerequisites, i.imported_at, i.imported_office,
                       helpdesk.person_name(i.imported_by) AS imported_by
                  FROM catalogue.course_import i ORDER BY i.imported_at DESC LIMIT 100
                """).query().listOfRows();
    }

    /* ── the owner ── */

    public record OwnerIn(@NotBlank @Size(max = 200) String department, @Size(max = 200) String programme,
                          @NotBlank @Size(max = 2000) String reason) {
    }

    /** move a course to its rightful owner: the same course, every binding, offering, registration and result still on it */
    @PostMapping("/courses/{code}/owner")
    @PreAuthorize(OWNERSHIP)
    @Transactional
    Map<String, Object> changeOwner(@PathVariable String code, @Valid @RequestBody OwnerIn body) {
        String c = code.trim().toUpperCase().replaceAll("\\s+", " ");
        jdbc.sql("SELECT catalogue.change_owner(:c, :d, :p, :why)")
                .param("c", c).param("d", body.department()).param("p", blank(body.programme()), Types.VARCHAR)
                .param("why", body.reason()).query().listOfRows();
        return jdbc.sql("""
                SELECT c.code, c.dept_code, d.name AS dept_name, c.owner_programme, p.name AS owner_programme_name
                  FROM catalogue.course c LEFT JOIN ref.department d ON d.code = c.dept_code LEFT JOIN ref.programme p ON p.code = c.owner_programme
                 WHERE c.code = :c
                """).param("c", c).query().singleRow();
    }
}
