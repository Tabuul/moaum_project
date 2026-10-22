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
 * V587: bulk inter-departmental transfer, on the programme swap. A department's students come out as a template; the filled file
 * is checked row by row against each student's current record and the target (people.transfer_upload_check: SOURCE PROGRAMME
 * MISMATCH, the new programme in its department and faculty, the level, the student twice, every check of the programme swap) and
 * previewed; made, it becomes a batch IDT/YYYY/NNNNNN of programme swaps (ACADEMIC_TRANSFER) that move the students at once, by the
 * officer who uploads the file (V633). A batch left pending from before V633 is decided on the swap screens' batch decision. The
 * rules are the database's.
 */
@RestController
@RequestMapping("/api/v1/transfers/bulk")
class TransferBatchController {

    static final String READERS = "hasAnyAuthority('OFFICE_academic','OFFICE_ict','OFFICE_registrar','OFFICE_dregistrar','OFFICE_records','OFFICE_super')";
    static final String PREPARERS = "hasAnyAuthority('OFFICE_academic','OFFICE_ict','OFFICE_registrar','OFFICE_dregistrar','OFFICE_super')";

    private final JdbcClient jdbc;
    private final tools.jackson.databind.ObjectMapper json;

    TransferBatchController(JdbcClient jdbc, tools.jackson.databind.ObjectMapper json) {
        this.jdbc = jdbc;
        this.json = json;
    }

    private static String blank(String s) {
        return s == null || s.isBlank() ? null : s.trim();
    }

    private Object parse(String text) {
        return text == null ? null : json.readValue(text, Object.class);
    }

    /** a department's students as they stand — the template's rows (a faculty, department or programme is named) */
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
        Object checked = parse(jdbc.sql("SELECT people.transfer_upload_check(CAST(:r AS jsonb), :s)::text")
                .param("r", json.writeValueAsString(body.rows())).param("s", blank(body.session()), Types.VARCHAR).query(String.class).single());
        @SuppressWarnings("unchecked")
        List<Map<String, Object>> rows = checked instanceof List<?> l ? (List<Map<String, Object>>) l : List.of();
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("total", rows.size());
        out.put("valid", rows.stream().filter(r -> "VALID".equals(r.get("status"))).count());
        out.put("warnings", rows.stream().filter(r -> "WARNING".equals(r.get("status"))).count());
        out.put("invalid", rows.stream().filter(r -> "INVALID".equals(r.get("status"))).count());
        out.put("duplicates", rows.stream().filter(r -> String.valueOf(r.get("problems")).contains("DUPLICATE_ROW")).count());
        out.put("rows", rows);
        return out;
    }

    public record Prepare(@NotNull @Size(min = 1, max = 1000) List<Map<String, Object>> rows, @Size(max = 20) String session,
                          @NotNull @Size(min = 10, max = 2000) String reason, @Size(max = 200) String approvalRef, @Size(max = 200) String filename,
                          Boolean validRowsOnly) {
    }

    /** the batch made: the rows checked again, a programme swap made at once for each valid row, every row kept with its result */
    @PostMapping
    @PreAuthorize(PREPARERS)
    @Transactional
    Map<String, Object> prepare(@Valid @RequestBody Prepare body) {
        Object made = parse(jdbc.sql("SELECT people.prepare_transfer_batch(CAST(:r AS jsonb), :s, :why, :ref, :f, :partial)::text")
                .param("r", json.writeValueAsString(body.rows())).param("s", blank(body.session()), Types.VARCHAR).param("why", body.reason().trim())
                .param("ref", blank(body.approvalRef()), Types.VARCHAR).param("f", blank(body.filename()), Types.VARCHAR)
                .param("partial", Boolean.TRUE.equals(body.validRowsOnly())).query(String.class).single());
        Object id = made instanceof Map<?, ?> m ? m.get("id") : null;
        return one(UUID.fromString(String.valueOf(id)));
    }

    /** the batches, the latest first, with how their swaps stand */
    @GetMapping
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Object batches() {
        return parse(jdbc.sql("SELECT coalesce(jsonb_agg(to_jsonb(x)), '[]')::text FROM people.transfer_batches(500) x").query(String.class).single());
    }

    /** one batch, and each row with its swap as it stands */
    @GetMapping("/{id}")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> one(@PathVariable UUID id) {
        String batch = jdbc.sql("SELECT to_jsonb(x)::text FROM people.transfer_batches(2000) x WHERE x.id = :id").param("id", id).query(String.class).optional()
                .orElseThrow(() -> new NotFound("bulk transfer", id));
        @SuppressWarnings("unchecked")
        Map<String, Object> out = new LinkedHashMap<>((Map<String, Object>) parse(batch));
        out.put("rows", parse(jdbc.sql("SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.row_no), '[]')::text FROM people.transfer_batch_rows(:id) x")
                .param("id", id).query(String.class).single()));
        return out;
    }
}
