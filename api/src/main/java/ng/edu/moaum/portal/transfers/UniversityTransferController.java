package ng.edu.moaum.portal.transfers;

import java.sql.Types;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

import ng.edu.moaum.portal.shared.NotFound;

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
 * V588: inter-university transfer, incoming and outgoing. The rows of a spreadsheet are checked (people.university_transfer_check:
 * the student found first — the matriculation, a former or the JAMB number, never the name — so no one is placed twice; an outgoing
 * row against the student's current record, an incoming one against its target programme; the other university on the list) and
 * previewed; prepared, they become a batch IUT/YYYY/NNNNNN of transfers that another officer of the Academic Office or the Registry
 * decides: an incoming student's record made as an admitted student's is (entry by TRANSFER, the applicant linked) or the existing
 * one named, an outgoing student TRANSFERRED_OUT with the record kept. The list of universities is kept here too. The rules are the
 * database's.
 */
@RestController
@RequestMapping("/api/v1/transfers/inter-university")
class UniversityTransferController {

    static final String READERS = "hasAnyAuthority('OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar','OFFICE_records','OFFICE_super')";
    static final String KEEPERS = "hasAnyAuthority('OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar','OFFICE_super')";

    private final JdbcClient jdbc;
    private final tools.jackson.databind.ObjectMapper json;

    UniversityTransferController(JdbcClient jdbc, tools.jackson.databind.ObjectMapper json) {
        this.jdbc = jdbc;
        this.json = json;
    }

    private static String blank(String s) {
        return s == null || s.isBlank() ? null : s.trim();
    }

    private Object parse(String text) {
        return text == null ? null : json.readValue(text, Object.class);
    }

    /** the other universities, the active first */
    @GetMapping("/universities")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> universities() {
        return jdbc.sql("""
                SELECT u.code, u.name, u.country, u.active,
                       (SELECT count(*) FROM people.university_transfer t WHERE t.university_code = u.code) AS transfers
                  FROM ref.university u ORDER BY u.active DESC, u.name""").query().listOfRows();
    }

    public record University(@NotNull @Size(min = 2, max = 16) String code, @NotNull @Size(min = 3, max = 200) String name, @Size(max = 80) String country,
                             Boolean active) {
    }

    /** a university added, or its name, country or standing put right (a code is never renamed) */
    @PostMapping("/universities")
    @PreAuthorize(KEEPERS)
    @Transactional
    Object saveUniversity(@Valid @RequestBody University body) {
        return parse(jdbc.sql("SELECT to_jsonb(u)::text FROM ref.save_university(:c, :n, :k, :a) u")
                .param("c", body.code().trim()).param("n", body.name().trim()).param("k", blank(body.country()), Types.VARCHAR)
                .param("a", body.active() == null || body.active()).query(String.class).single());
    }

    /** the students of a faculty, department or programme as they stand — an outgoing template's rows */
    @GetMapping("/template")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> template(@RequestParam(required = false) String faculty, @RequestParam(required = false) String department,
                                       @RequestParam(required = false) String programme, @RequestParam(required = false) Integer level) {
        return jdbc.sql("SELECT * FROM people.transfer_template(:f, :d, :p, :l)")
                .param("f", blank(faculty), Types.VARCHAR).param("d", blank(department), Types.VARCHAR).param("p", blank(programme), Types.VARCHAR)
                .param("l", level, Types.INTEGER).query().listOfRows();
    }

    public record Upload(@NotNull @Size(min = 1, max = 1000) List<Map<String, Object>> rows, @Size(max = 20) String session) {
    }

    /** each row checked: VALID, WARNING (review points) or INVALID (problems), never put right silently; and the counts */
    @PostMapping("/validate")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> validate(@Valid @RequestBody Upload body) {
        Object checked = parse(jdbc.sql("SELECT people.university_transfer_check(CAST(:r AS jsonb), :s)::text")
                .param("r", json.writeValueAsString(body.rows())).param("s", blank(body.session()), Types.VARCHAR).query(String.class).single());
        @SuppressWarnings("unchecked")
        List<Map<String, Object>> rows = checked instanceof List<?> l ? (List<Map<String, Object>>) l : List.of();
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("total", rows.size());
        out.put("valid", rows.stream().filter(r -> "VALID".equals(r.get("status"))).count());
        out.put("warnings", rows.stream().filter(r -> "WARNING".equals(r.get("status"))).count());
        out.put("invalid", rows.stream().filter(r -> "INVALID".equals(r.get("status"))).count());
        out.put("duplicates", rows.stream().filter(r -> String.valueOf(r.get("problems")).contains("DUPLICATE_ROW")).count());
        out.put("incoming", rows.stream().filter(r -> "INCOMING".equals(r.get("direction"))).count());
        out.put("outgoing", rows.stream().filter(r -> "OUTGOING".equals(r.get("direction"))).count());
        out.put("newRecords", rows.stream().filter(r -> !"INVALID".equals(r.get("status"))
                && ("CREATE".equals(r.get("action")) || "CREATE_FROM_APPLICANT".equals(r.get("action")))).count());
        out.put("rows", rows);
        return out;
    }

    public record Prepare(@NotNull @Size(min = 1, max = 1000) List<Map<String, Object>> rows, @Size(max = 20) String session,
                          @NotNull @Size(min = 10, max = 2000) String reason, @Size(max = 200) String approvalRef, @Size(max = 200) String filename,
                          Boolean validRowsOnly) {
    }

    /** the batch prepared: the rows checked again, a transfer awaiting a decision for each valid row, each invalid row kept with why */
    @PostMapping
    @PreAuthorize(KEEPERS)
    @Transactional
    Map<String, Object> prepare(@Valid @RequestBody Prepare body) {
        Object made = parse(jdbc.sql("SELECT people.prepare_university_transfers(CAST(:r AS jsonb), :s, :why, :ref, :f, :partial)::text")
                .param("r", json.writeValueAsString(body.rows())).param("s", blank(body.session()), Types.VARCHAR).param("why", body.reason().trim())
                .param("ref", blank(body.approvalRef()), Types.VARCHAR).param("f", blank(body.filename()), Types.VARCHAR)
                .param("partial", Boolean.TRUE.equals(body.validRowsOnly())).query(String.class).single());
        Object id = made instanceof Map<?, ?> m ? m.get("id") : null;
        return one(UUID.fromString(String.valueOf(id)));
    }

    /** the batches, the latest first, with how their transfers stand */
    @GetMapping
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Object batches() {
        return parse(jdbc.sql("SELECT coalesce(jsonb_agg(to_jsonb(x)), '[]')::text FROM people.university_transfer_batches(500) x").query(String.class).single());
    }

    /** one batch: its transfers as they stand and the rows left out with why */
    @GetMapping("/{id}")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> one(@PathVariable UUID id) {
        String batch = jdbc.sql("SELECT to_jsonb(x)::text FROM people.university_transfer_batches(2000) x WHERE x.id = :id").param("id", id).query(String.class).optional()
                .orElseThrow(() -> new NotFound("inter-university transfer", id));
        @SuppressWarnings("unchecked")
        Map<String, Object> out = new LinkedHashMap<>((Map<String, Object>) parse(batch));
        out.put("transfers", parse(jdbc.sql("SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.row_no), '[]')::text FROM people.university_transfers(:id, NULL, NULL, NULL, 5000) x")
                .param("id", id).query(String.class).single()));
        out.put("leftOut", parse(jdbc.sql("""
                SELECT coalesce(jsonb_agg(jsonb_build_object('row_no', l.row_no, 'uploaded', l.uploaded, 'messages', l.messages) ORDER BY l.row_no), '[]')::text
                  FROM people.university_transfer_left_out l WHERE l.batch_id = :id""").param("id", id).query(String.class).single()));
        return out;
    }

    public record Decision(@NotNull Boolean approve, @Size(max = 2000) String note) {
    }

    /** every transfer of the batch awaiting a decision decided, each on its own (another officer than the one who prepared it) */
    @PostMapping("/{id}/decide")
    @PreAuthorize(KEEPERS)
    @Transactional
    Object decideBatch(@PathVariable UUID id, @Valid @RequestBody Decision body) {
        return parse(jdbc.sql("SELECT people.decide_university_transfer_batch(:id, :a, :n)::text")
                .param("id", id).param("a", body.approve()).param("n", blank(body.note()), Types.VARCHAR).query(String.class).single());
    }

    /** one transfer decided */
    @PostMapping("/transfers/{id}/decide")
    @PreAuthorize(KEEPERS)
    @Transactional
    Object decideOne(@PathVariable UUID id, @Valid @RequestBody Decision body) {
        return parse(jdbc.sql("SELECT people.decide_university_transfer(:id, :a, :n)::text")
                .param("id", id).param("a", body.approve()).param("n", blank(body.note()), Types.VARCHAR).query(String.class).single());
    }

    /** the transfers, the latest first: by a search (a batch, a number, a name, a university), a direction or a student */
    @GetMapping("/transfers")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Object transfers(@RequestParam(required = false) String q, @RequestParam(required = false) String direction, @RequestParam(required = false) UUID student) {
        String dir = blank(direction) == null ? null : direction.trim().toUpperCase();
        return parse(jdbc.sql("SELECT coalesce(jsonb_agg(to_jsonb(x)), '[]')::text FROM people.university_transfers(NULL, :s, :q, :d, 2000) x")
                .param("s", student, Types.OTHER).param("q", blank(q), Types.VARCHAR).param("d", dir, Types.VARCHAR).query(String.class).single());
    }
}
