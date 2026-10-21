package ng.edu.moaum.portal.finance;

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
 * V607: an Old Fees History upload by the Students Account Officer, held for the Bursar's approval. The officer opens the upload
 * (with the item codes read from the file), sends its rows in parts, then sends it to the Bursar — nothing of it is on the records.
 * The Bursar reads it (summary and rows), checks what approving would do (the import run and undone), then approves it — loaded a
 * few parts at a time, as the Bursar's own upload is — or rejects it with the reason; the officer may withdraw one not yet decided.
 * The database holds every rule (the offices, the states, the uploader never deciding, the rows fixed once sent).
 */
@RestController
@RequestMapping("/api/v1/finance/legacy-fees/uploads")
class LegacyFeeUploadController {

    private static final String READERS = "hasAnyAuthority('OFFICE_bursar','OFFICE_studentaccounts','OFFICE_audit','OFFICE_deputyaudit','OFFICE_super')";
    private static final String UPLOADER = "hasAuthority('OFFICE_studentaccounts')";
    private static final String BURSAR = "hasAuthority('OFFICE_bursar')";

    private static final String ROW = """
            SELECT u.id, u.ref, u.state, u.file_name, u.note, u.parts, u.row_count, u.students, u.sessions, u.amount,
                   u.uploaded_by, u.uploaded_office, u.uploaded_at, u.submitted_at, u.decided_by, u.decided_office, u.decided_at, u.decision_note,
                   u.applied_parts, u.result::text AS result, u.completed_at, jsonb_array_length(coalesce(u.item_codes, '[]'::jsonb)) AS item_codes,
                   nullif(btrim(coalesce(up.surname, '') || ', ' || coalesce(up.given_names, ''), ', '), '') AS uploaded_by_name,
                   nullif(btrim(coalesce(dp.surname, '') || ', ' || coalesce(dp.given_names, ''), ', '), '') AS decided_by_name
              FROM finance.legacy_fee_upload u
              LEFT JOIN iam.person up ON up.id = u.uploaded_by
              LEFT JOIN iam.person dp ON dp.id = u.decided_by
            """;

    private final JdbcClient jdbc;
    private final tools.jackson.databind.ObjectMapper json;

    LegacyFeeUploadController(JdbcClient jdbc, tools.jackson.databind.ObjectMapper json) {
        this.jdbc = jdbc;
        this.json = json;
    }

    private Map<String, Object> shaped(Map<String, Object> r) {
        Map<String, Object> out = new LinkedHashMap<>(r);
        Object result = out.get("result");
        out.put("result", result == null ? null : json.readValue(result.toString(), Map.class));
        return out;
    }

    private Map<String, Object> one(UUID id) {
        return jdbc.sql(ROW + " WHERE u.id = :id").param("id", id).query().listOfRows().stream().findFirst().map(this::shaped)
                .orElseThrow(() -> new NotFound("Old fees upload", id));
    }

    /** the uploads, newest first (those waiting first), with how many stand in each state */
    @GetMapping
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> list(@RequestParam(required = false) String state, @RequestParam(defaultValue = "50") int size) {
        String st = state == null || state.isBlank() ? null : state.trim().toUpperCase();
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("counts", jdbc.sql("SELECT state, count(*) AS n FROM finance.legacy_fee_upload WHERE state <> 'DRAFT' GROUP BY state").query().listOfRows());
        out.put("rows", jdbc.sql(ROW + """
                 WHERE (:st::text IS NULL OR u.state = :st) AND (u.state <> 'DRAFT' OR u.uploaded_by = nullif(current_setting('moaum.actor_id', true), '')::uuid)
                 ORDER BY (u.state IN ('PENDING', 'APPROVING')) DESC, coalesce(u.submitted_at, u.uploaded_at) DESC
                 LIMIT :n
                """).param("st", st, Types.VARCHAR).param("n", Math.max(1, Math.min(size, 200))).query().listOfRows()
                .stream().map(this::shaped).toList());
        return out;
    }

    @GetMapping("/{id}")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> get(@PathVariable UUID id) {
        return one(id);
    }

    /** the rows as sent, in order (for the Bursar's reading and the Excel copy) */
    @GetMapping("/{id}/rows")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> rows(@PathVariable UUID id, @RequestParam(defaultValue = "0") int offset, @RequestParam(defaultValue = "200") int limit) {
        one(id);
        String text = jdbc.sql("""
                SELECT coalesce(json_agg(e ORDER BY p.seq, o), '[]'::json)::text
                  FROM (SELECT p.seq, e, o FROM finance.legacy_fee_upload_part p, jsonb_array_elements(p.rows) WITH ORDINALITY x(e, o)
                         WHERE p.upload_id = :id ORDER BY p.seq, o OFFSET :off LIMIT :n) p
                """).param("id", id).param("off", Math.max(0, offset)).param("n", Math.max(1, Math.min(limit, 5000))).query(String.class).single();
        return Map.of("offset", Math.max(0, offset), "rows", json.readValue(text, List.class));
    }

    public record Open(@Size(max = 200) String fileName, @Size(max = 500) String note, List<Map<String, Object>> itemCodes) {
    }

    /** the officer opens an upload for the Bursar's approval */
    @PostMapping
    @PreAuthorize(UPLOADER)
    @Transactional
    Map<String, Object> open(@Valid @RequestBody Open body) {
        Map<String, Object> r = jdbc.sql("SELECT * FROM finance.legacy_upload_open(:f, :n, CAST(:c AS jsonb))")
                .param("f", body.fileName(), Types.VARCHAR).param("n", body.note(), Types.VARCHAR)
                .param("c", body.itemCodes() == null || body.itemCodes().isEmpty() ? null : json.writeValueAsString(body.itemCodes()), Types.VARCHAR)
                .query().singleRow();
        return one((UUID) r.get("id"));
    }

    public record Part(@NotNull @Size(min = 1, max = 2000) List<Map<String, Object>> rows) {
    }

    /** a part of the rows (1 to 2,000), before the upload is sent */
    @PostMapping("/{id}/rows")
    @PreAuthorize(UPLOADER)
    @Transactional
    Map<String, Object> add(@PathVariable UUID id, @Valid @RequestBody Part body) {
        int held = jdbc.sql("SELECT finance.legacy_upload_add(:id, CAST(:r AS jsonb))").param("id", id).param("r", json.writeValueAsString(body.rows()))
                .query(Integer.class).single();
        return Map.of("rows", held);
    }

    /** sent to the Bursar: its rows fixed, the Bursar told */
    @PostMapping("/{id}/submit")
    @PreAuthorize(UPLOADER)
    @Transactional
    Map<String, Object> submit(@PathVariable UUID id) {
        jdbc.sql("SELECT finance.legacy_upload_submit(:id)").param("id", id).query().singleRow();
        return one(id);
    }

    public record Reason(@Size(max = 500) String reason) {
    }

    /** the officer withdraws an upload not yet decided */
    @PostMapping("/{id}/withdraw")
    @PreAuthorize(UPLOADER)
    @Transactional
    Map<String, Object> withdraw(@PathVariable UUID id, @Valid @RequestBody Reason body) {
        jdbc.sql("SELECT finance.legacy_upload_withdraw(:id, :r)").param("id", id).param("r", body.reason(), Types.VARCHAR).query().singleRow();
        return one(id);
    }

    public record Batch(Integer fromPart, Integer parts, @Size(max = 500) String note) {
    }

    /** what approving would do — the import run on the parts given and undone; nothing is written */
    @PostMapping("/{id}/check")
    @PreAuthorize(BURSAR)
    @Transactional
    Map<String, Object> check(@PathVariable UUID id, @RequestBody Batch body) {
        Map<String, Object> r = jdbc.sql("SELECT checked_parts, totals::text AS totals FROM finance.legacy_upload_check(:id, :f, :n)")
                .param("id", id).param("f", body.fromPart() == null ? 1 : body.fromPart()).param("n", body.parts() == null ? 2 : body.parts())
                .query().singleRow();
        return Map.of("checkedParts", r.get("checked_parts"), "totals", json.readValue(r.get("totals").toString(), Map.class));
    }

    /** the Bursar approves: the item codes set, then a few parts loaded (the screen asks again until none is left) */
    @PostMapping("/{id}/approve")
    @PreAuthorize(BURSAR)
    @Transactional
    Map<String, Object> approve(@PathVariable UUID id, @Valid @RequestBody Batch body) {
        Map<String, Object> r = jdbc.sql("SELECT state, parts, applied_parts, remaining, result::text AS result FROM finance.legacy_upload_approve(:id, :note, :n)")
                .param("id", id).param("note", body.note(), Types.VARCHAR).param("n", body.parts() == null ? 2 : body.parts())
                .query().singleRow();
        Map<String, Object> out = new LinkedHashMap<>(r);
        out.put("result", r.get("result") == null ? null : json.readValue(r.get("result").toString(), Map.class));
        return out;
    }

    /** the Bursar rejects an upload waiting for approval, with the reason; the officer is told */
    @PostMapping("/{id}/reject")
    @PreAuthorize(BURSAR)
    @Transactional
    Map<String, Object> reject(@PathVariable UUID id, @Valid @RequestBody Reason body) {
        jdbc.sql("SELECT finance.legacy_upload_reject(:id, :r)").param("id", id).param("r", body.reason(), Types.VARCHAR).query().singleRow();
        return one(id);
    }
}
