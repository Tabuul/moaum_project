package ng.edu.moaum.portal.catalogue;

import java.sql.Types;
import java.util.List;
import java.util.Map;

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

/**
 * The course catalogue's administration (V338): the catalogue upload that names each course's owner and the programmes that
 * offer it as CORE or ELECTIVE, and the change of a course's owner. The upload is a central act (the Directorate of ICT and the
 * Academic Office). The catalogue reset V338 also added was withdrawn by V340.
 */
@RestController
@RequestMapping("/api/v1/catalogue")
class CourseCatalogueAdminController {

    /** who uploads the catalogue: the Directorate of ICT and the Academic Office */
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
