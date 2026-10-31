package ng.edu.moaum.portal.catalogue;

import java.sql.Types;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
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

import tools.jackson.databind.ObjectMapper;

/**
 * V716 — a programme's code corrected by the Director of ICT and the ICT Support Desk (an agent with EDIT_PROGRAMME_CODE within its
 * posting's faculties and departments; the Head anywhere), as a course's is (V713): the impact first, a reason from the list, against
 * the version the person read, on a ticket where there is one. The database does the work (ref.correct_programme_code: the new code a
 * copy of the programme, the programme merged into it — V574 — the old code an alias) and keeps the trail (ref.programme_code_change);
 * a correction is undone from its record. The trail is read by the Registry, the Academic Office, Audit and ICT.
 */
@RestController
@RequestMapping("/api/v1/catalogue")
class ProgrammeCodeController {

    static final String CORRECTORS = "hasAnyAuthority('OFFICE_ict','OFFICE_ictagent','OFFICE_helpdeskhead','OFFICE_super')";
    static final String READERS = "hasAnyAuthority('OFFICE_ict','OFFICE_ictagent','OFFICE_helpdeskhead','OFFICE_super','OFFICE_academic','OFFICE_dregistrar','OFFICE_registrar',"
            + "'OFFICE_records','OFFICE_admin','OFFICE_audit','OFFICE_deputyaudit','OFFICE_dbops','OFFICE_pgschool','OFFICE_pgsecretary')";

    public record CheckIn(@Size(max = 20) String newCode) {
    }

    public record CorrectIn(@NotBlank @Size(max = 20) String newCode, @NotBlank @Size(max = 40) String reasonKind, @Size(max = 2000) String remarks,
                            @NotBlank @Size(max = 64) String version) {
    }

    public record UndoIn(@NotBlank @Size(max = 2000) String reason) {
    }

    private final JdbcClient jdbc;
    private final StructureAccess access;
    private final ObjectMapper json;

    ProgrammeCodeController(JdbcClient jdbc, StructureAccess access, ObjectMapper json) {
        this.jdbc = jdbc;
        this.access = access;
        this.json = json;
    }

    private static String code(String code) {
        return code == null ? "" : code.trim().toUpperCase();
    }

    private Map<String, Object> jsonMap(String text) {
        return json.readValue(text, new tools.jackson.core.type.TypeReference<LinkedHashMap<String, Object>>() { });
    }

    /** what the correction would be — the programme as it reads, its version, what hangs on it (students, applications, fee lines,
     *  bindings, the codes merged into it), why it would be refused — and whether the acting office may make it; changing nothing */
    @PostMapping("/programmes/{code}/code-correction/check")
    @PreAuthorize(CORRECTORS)
    @Transactional(readOnly = true)
    Map<String, Object> check(@PathVariable String code, @RequestBody(required = false) CheckIn body) {
        String c = code(code);
        Map<String, Object> out = jsonMap(jdbc.sql("SELECT ref.programme_code_check(:c, :n)::text").param("c", c)
                .param("n", body == null ? null : body.newCode(), Types.VARCHAR).query(String.class).single());
        out.put("may", access.mayProgrammeCode(c));
        return out;
    }

    /** the correction: the same programme under the new code — every student, application, fee line, binding and specialisation
     *  following; the old code kept as an alias so anything written with it lands on the programme — for the reason given, against the
     *  version the person read; written down, and on the ticket where there is one */
    @PostMapping("/programmes/{code}/code-correction")
    @PreAuthorize(CORRECTORS)
    @Transactional
    Map<String, Object> correct(@PathVariable String code, @Valid @RequestBody CorrectIn body, @RequestParam(required = false) String ticket) {
        String c = code(code);
        access.assertProgrammeCode(c);
        UUID on = access.ticket(ticket);
        Map<String, Object> out = jsonMap(jdbc.sql("SELECT ref.correct_programme_code(:c, :n, :k, :r, :v, :t)::text").param("c", c)
                .param("n", body.newCode().trim()).param("k", body.reasonKind().trim())
                .param("r", body.remarks() == null || body.remarks().isBlank() ? null : body.remarks().trim(), Types.VARCHAR)
                .param("v", body.version().trim()).param("t", on, Types.OTHER).query(String.class).single());
        access.note(on, "Corrected programme code " + out.get("was") + " to " + out.get("code") + " (" + out.get("name") + "; the same programme, "
                + out.get("students") + " student(s) and every record following, the old code an alias): " + out.get("reason")
                + (out.get("remarks") == null ? "" : " — " + out.get("remarks")));
        return out;
    }

    /** a correction undone from its record: every record back on the old code, the alias ended, the new code removed when nothing
     *  names it any more (else archived) */
    @PostMapping("/programme-code-changes/{id}/undo")
    @PreAuthorize(CORRECTORS)
    @Transactional
    Map<String, Object> undo(@PathVariable UUID id, @Valid @RequestBody UndoIn body) {
        String newCode = jdbc.sql("SELECT new_code FROM ref.programme_code_change WHERE id = :i").param("i", id).query(String.class).optional().orElse("");
        access.assertProgrammeCode(newCode.isBlank() ? "" : newCode);
        return jsonMap(jdbc.sql("SELECT ref.undo_programme_code_correction(:i, :r)::text").param("i", id).param("r", body.reason().trim()).query(String.class).single());
    }

    /** every correction of a programme's code, newest first — searchable by either code, the name, the ticket or the remarks */
    @GetMapping("/programme-code-changes")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> changes(@RequestParam(required = false) String q, @RequestParam(defaultValue = "1") int page, @RequestParam(defaultValue = "50") int size) {
        int pg = Math.max(1, page);
        int sz = Math.max(1, Math.min(size, 2000));
        String like = q == null || q.isBlank() ? null : "%" + q.trim() + "%";
        String where = """
                 FROM ref.programme_code_change c
                 LEFT JOIN ref.programme n ON n.code = c.new_code
                 LEFT JOIN ref.department d ON d.code = coalesce(n.dept_code, (SELECT o.dept_code FROM ref.programme o WHERE o.code = c.old_code))
                 LEFT JOIN helpdesk.ticket t ON t.id = c.ticket_id
                 LEFT JOIN iam.person by ON by.id = c.changed_by
                 LEFT JOIN iam.person un ON un.id = c.undone_by
                WHERE (:q::text IS NULL OR c.old_code ILIKE :q OR c.new_code ILIKE :q OR c.name ILIKE :q OR coalesce(c.remarks, '') ILIKE :q
                       OR coalesce(t.number, '') ILIKE :q OR coalesce(d.name, '') ILIKE :q)
                """;
        long total = jdbc.sql("SELECT count(*)" + where).param("q", like, Types.VARCHAR).query(Long.class).single();
        List<Map<String, Object>> rows = jdbc.sql("""
                SELECT c.id, c.old_code, c.new_code, c.name, c.category, c.reason_kind, ref.programme_change_reason_words(c.reason_kind) AS reason_words,
                       c.remarks, t.number AS ticket, c.students, c.moved, c.changed_at, c.changed_office,
                       coalesce(by.surname || ', ' || by.given_names, 'Unknown officer') AS changed_by,
                       c.undone_at, c.undone_office, un.surname || ', ' || un.given_names AS undone_by, c.undo_reason, c.new_code_kept,
                       d.name AS dept_name, n.archived AS new_archived,
                       (SELECT count(*) FROM people.student s WHERE s.programme_code = c.new_code) AS students_now
                """ + where + " ORDER BY c.changed_at DESC LIMIT :n OFFSET :o")
                .param("q", like, Types.VARCHAR).param("n", sz).param("o", (long) (pg - 1) * sz).query().listOfRows();
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("total", total);
        out.put("page", pg);
        out.put("size", sz);
        out.put("rows", rows);
        out.put("may", access.mayProgrammeCode(""));   // the Director of ICT, the Head and super undo anywhere; an agent is checked on the programme
        return out;
    }
}
