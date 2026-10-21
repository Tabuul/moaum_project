package ng.edu.moaum.portal.finance;

import java.math.BigDecimal;
import java.sql.Types;
import java.time.LocalDate;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import jakarta.validation.Valid;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

import ng.edu.moaum.portal.shared.DomainRuleViolation;
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
 * V609: Old Fees History's upload history. The Bursary's own file is loaded as an upload — opened with the file's name and what it
 * states, then each part (the import as ever, what the part did kept) — and every upload is listed and queried: the Bursary's loads
 * (rebuilt from the records for those before V609), the Students Account Officer's uploads for the Bursar's approval (V607, once
 * sent) and the start overs; each with its parts and the payments it recorded or deleted. The database holds the rules (the
 * Bursary's office, the person who opened the upload loading its parts, the history kept).
 */
@RestController
@RequestMapping("/api/v1/finance/legacy-fees")
class LegacyFeeHistoryController {

    /** the desk and the audit directorate read the history */
    private static final String READERS = "hasAnyAuthority('OFFICE_bursar','OFFICE_studentaccounts','OFFICE_audit','OFFICE_deputyaudit','OFFICE_super')";
    private static final String BURSARY = "hasAnyAuthority('OFFICE_bursar','OFFICE_super')";
    private static final List<String> KINDS = List.of("DIRECT", "FOR_APPROVAL", "RESET");
    private static final List<String> STATES = List.of("LOADING", "STOPPED", "LOADED", "PENDING", "APPROVING", "APPROVED", "REJECTED", "WITHDRAWN", "DONE");

    /** the history with the names of the people, filtered */
    private static final String FILTERED = """
            SELECT h.*, nullif(btrim(coalesce(bp.surname, '') || ', ' || coalesce(bp.given_names, ''), ', '), '') AS by_name,
                   nullif(btrim(coalesce(dp.surname, '') || ', ' || coalesce(dp.given_names, ''), ', '), '') AS decided_by_name
              FROM finance.legacy_upload_history h
              LEFT JOIN iam.person bp ON bp.id = h.by_person
              LEFT JOIN iam.person dp ON dp.id = h.decided_by
             WHERE (:from::date IS NULL OR (h.at AT TIME ZONE 'Africa/Lagos')::date >= :from::date)
               AND (:to::date IS NULL OR (h.at AT TIME ZONE 'Africa/Lagos')::date <= :to::date)
               AND (:kind::text IS NULL OR h.kind = :kind)
               AND (:state::text IS NULL OR h.state = :state)
               AND (:person::uuid IS NULL OR h.by_person = :person::uuid)
               AND (:office::text IS NULL OR h.office = :office)
               AND (:session::text IS NULL OR (', ' || coalesce(h.sessions, '') || ',') LIKE '%, ' || :session || ',%')
               AND (:q::text IS NULL OR h.ref ILIKE '%' || :q || '%' OR h.file_name ILIKE '%' || :q || '%'
                    OR coalesce(bp.surname, '') || ' ' || coalesce(bp.given_names, '') ILIKE '%' || :q || '%')
            """;

    private final JdbcClient jdbc;
    private final tools.jackson.databind.ObjectMapper json;

    LegacyFeeHistoryController(JdbcClient jdbc, tools.jackson.databind.ObjectMapper json) {
        this.jdbc = jdbc;
        this.json = json;
    }

    private static String blank(String s) {
        return s == null || s.isBlank() ? null : s.trim();
    }

    private static String oneOf(String value, List<String> allowed, String what) {
        String v = blank(value);
        if (v == null) return null;
        v = v.toUpperCase();
        if (!allowed.contains(v)) {
            throw new DomainRuleViolation("LEGACY_HISTORY_FILTER", "No such " + what + ": " + value + ".",
                    new DomainRuleViolation.Remedy("Choose one of " + String.join(", ", allowed) + ".", "Bursary"));
        }
        return v;
    }

    @SuppressWarnings("unchecked")
    private Map<String, Object> map(String text) {
        return json.readValue(text, Map.class);
    }

    // ── the Bursary's load ───────────────────────────────────────────────────────────────────────────────────────────────

    /** what the file states, read in the browser: its rows (required), students, sessions and the amount stated */
    public record Open(@NotNull @Min(1) Integer rows, @Size(max = 200) String fileName, Integer students, @Size(max = 500) String sessions,
                       BigDecimal amount) {
    }

    /** a part of the file: its first row (0 for the first) and its rows */
    public record Part(@Min(0) Integer from, @NotNull @Size(min = 1, max = 2000) List<Map<String, Object>> rows) {
    }

    /** the Bursary opens an upload of its own file; the parts follow */
    @PostMapping("/loads")
    @PreAuthorize(BURSARY)
    @Transactional
    Map<String, Object> open(@Valid @RequestBody Open body) {
        return jdbc.sql("SELECT * FROM finance.legacy_load_open(:f, :r, :st, :ses, :amt)")
                .param("f", body.fileName(), Types.VARCHAR).param("r", body.rows()).param("st", body.students(), Types.INTEGER)
                .param("ses", body.sessions(), Types.VARCHAR).param("amt", body.amount(), Types.NUMERIC).query().singleRow();
    }

    /** a part loaded: what the import did (as the direct door answers) with the upload's reference and how far it is */
    @PostMapping("/loads/{id}/rows")
    @PreAuthorize(BURSARY)
    @Transactional
    Map<String, Object> part(@PathVariable UUID id, @Valid @RequestBody Part body) {
        return map(jdbc.sql("SELECT finance.legacy_load_part(:id, :from, :j::jsonb)::text")
                .param("id", id).param("from", body.from(), Types.INTEGER).param("j", json.writeValueAsString(body.rows()))
                .query(String.class).single());
    }

    // ── the history ──────────────────────────────────────────────────────────────────────────────────────────────────────

    /** every upload the filters find, newest first, a page at a time (size up to 100,000 for every one, as the Excel reads it),
     *  with the totals of all of them, how many of each kind, and the people, offices and sessions to filter by */
    @GetMapping("/history")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> history(@RequestParam(required = false) LocalDate from, @RequestParam(required = false) LocalDate to,
                                @RequestParam(required = false) String kind, @RequestParam(required = false) String state,
                                @RequestParam(required = false) UUID person, @RequestParam(required = false) String office,
                                @RequestParam(required = false) String session, @RequestParam(required = false) String q,
                                @RequestParam(defaultValue = "1") int page, @RequestParam(defaultValue = "10") int size) {
        int n = Math.max(1, Math.min(size, 100_000));
        int pg = Math.max(1, page);
        String text = jdbc.sql("WITH h AS MATERIALIZED (" + FILTERED + """
                ), everything AS MATERIALIZED (SELECT * FROM finance.legacy_upload_history)
                SELECT json_build_object(
                    'total', (SELECT count(*) FROM h),
                    'page', :page, 'size', :size,
                    'totals', (SELECT json_build_object(
                        'uploads', count(*) FILTER (WHERE kind <> 'RESET'),
                        -- null where no upload of the set kept them (those rebuilt from the records)
                        'file_rows', sum(file_rows) FILTER (WHERE kind <> 'RESET'),
                        'rows_read', sum(rows_read) FILTER (WHERE kind <> 'RESET'),
                        'recorded', coalesce(sum(recorded) FILTER (WHERE kind <> 'RESET'), 0),
                        'already', sum(already) FILTER (WHERE kind <> 'RESET'),
                        'no_student', sum(no_student) FILTER (WHERE kind <> 'RESET'),
                        'amount', coalesce(sum(amount) FILTER (WHERE kind = 'DIRECT'), 0),
                        'pending', count(*) FILTER (WHERE kind = 'FOR_APPROVAL' AND state IN ('PENDING', 'APPROVING')),
                        'resets', count(*) FILTER (WHERE kind = 'RESET'),
                        'deleted', coalesce(sum(deleted), 0),
                        'deleted_amount', coalesce(sum(amount) FILTER (WHERE kind = 'RESET'), 0)) FROM h),
                    'by_kind', (SELECT coalesce(json_object_agg(kind, n), '{}'::json) FROM (SELECT kind, count(*) AS n FROM h GROUP BY kind) k),
                    'rows', (SELECT coalesce(json_agg(r ORDER BY r.at DESC, r.ref DESC), '[]'::json)
                               FROM (SELECT * FROM h ORDER BY at DESC, ref DESC OFFSET :off LIMIT :n) r),
                    'people', (SELECT coalesce(json_agg(json_build_object('id', e.by_person, 'name',
                                          coalesce(nullif(btrim(coalesce(p.surname, '') || ', ' || coalesce(p.given_names, ''), ', '), ''), 'Unnamed'))
                                          ORDER BY p.surname NULLS LAST, p.given_names, e.by_person), '[]'::json)
                                 FROM (SELECT DISTINCT by_person FROM everything WHERE by_person IS NOT NULL) e
                                 LEFT JOIN iam.person p ON p.id = e.by_person),
                    'offices', (SELECT coalesce(json_agg(DISTINCT office ORDER BY office), '[]'::json) FROM everything WHERE office IS NOT NULL),
                    'sessions', (SELECT coalesce(json_agg(DISTINCT s ORDER BY s), '[]'::json)
                                   FROM everything, unnest(string_to_array(coalesce(sessions, ''), ', ')) s WHERE s <> ''),
                    'since', (SELECT min(at) FROM everything))::text
                """)
                .param("from", from, Types.DATE).param("to", to, Types.DATE)
                .param("kind", oneOf(kind, KINDS, "kind of upload"), Types.VARCHAR).param("state", oneOf(state, STATES, "state"), Types.VARCHAR)
                .param("person", person, Types.OTHER).param("office", blank(office), Types.VARCHAR)
                .param("session", blank(session), Types.VARCHAR).param("q", blank(q), Types.VARCHAR)
                .param("page", pg).param("size", n).param("off", (pg - 1) * n).param("n", n)
                .query(String.class).single();
        return map(text);
    }

    private Map<String, Object> entry(UUID id) {
        return jdbc.sql("WITH h AS (" + FILTERED + ") SELECT row_to_json(h)::text FROM h WHERE h.id = :id")
                .param("from", null, Types.DATE).param("to", null, Types.DATE).param("kind", null, Types.VARCHAR).param("state", null, Types.VARCHAR)
                .param("person", null, Types.OTHER).param("office", null, Types.VARCHAR).param("session", null, Types.VARCHAR).param("q", null, Types.VARCHAR)
                .param("id", id).query(String.class).optional().map(this::map)
                .orElseThrow(() -> new NotFound("Old fees upload", id));
    }

    /** one upload: what it is, and its parts as they were loaded (an upload for approval: its parts as sent) */
    @GetMapping("/history/{id}")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> one(@PathVariable UUID id) {
        Map<String, Object> out = new LinkedHashMap<>(entry(id));
        String parts = "FOR_APPROVAL".equals(out.get("kind"))
                ? jdbc.sql("""
                        SELECT coalesce(json_agg(json_build_object('seq', p.seq, 'rows_read', p.row_count) ORDER BY p.seq), '[]'::json)::text
                          FROM finance.legacy_fee_upload_part p WHERE p.upload_id = :id
                        """).param("id", id).query(String.class).single()
                : jdbc.sql("""
                        SELECT coalesce(json_agg(json_build_object('seq', p.seq, 'from_row', p.from_row, 'at', p.at, 'rows_read', p.rows_read,
                                   'recorded', p.recorded, 'duplicates', p.duplicates, 'matched', p.matched, 'no_student', p.no_student,
                                   'no_due', p.no_due, 'separate', p.separate, 'taken_over', p.taken_over, 'corrected', p.corrected,
                                   'undated', p.undated, 'deleted', p.deleted, 'amount', p.amount, 'resent', p.resent,
                                   'duplicate_sample', p.duplicate_sample) ORDER BY p.seq), '[]'::json)::text
                          FROM finance.legacy_fee_load_part p WHERE p.load_id = :id
                        """).param("id", id).query(String.class).single();
        out.put("part_list", json.readValue(parts, List.class));
        return out;
    }

    /** the payments an upload of the Bursary's recorded (those still on record) or a start over deleted, a page at a time (size up
     *  to 200,000 for the Excel), with the student's number and name */
    @GetMapping("/history/{id}/payments")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> payments(@PathVariable UUID id, @RequestParam(defaultValue = "1") int page, @RequestParam(defaultValue = "10") int size) {
        Map<String, Object> e = entry(id);
        if ("FOR_APPROVAL".equals(e.get("kind"))) {
            throw new DomainRuleViolation("LEGACY_HISTORY_PAYMENTS", "An upload for the Bursar's approval is read under Uploads for the Bursar's approval.",
                    new DomainRuleViolation.Remedy("Open it there (Review or Open) for its rows.", "Bursary"));
        }
        int n = Math.max(1, Math.min(size, 200_000));
        int pg = Math.max(1, page);
        String text = jdbc.sql("""
                WITH p AS MATERIALIZED (SELECT * FROM finance.legacy_load_payments(:id))
                SELECT json_build_object(
                    'total', (SELECT count(*) FROM p),
                    'amount', (SELECT coalesce(sum(amount), 0) FROM p),
                    'page', :page, 'size', :size,
                    'rows', (SELECT coalesce(json_agg(r ORDER BY r.part, r.reference), '[]'::json) FROM (
                        SELECT pg.part, pg.at, s.matric_no AS number, btrim(coalesce(s.surname, '') || ', ' || coalesce(s.other_names, ''), ', ') AS name,
                               pg.session, pg.purpose, pg.amount, pg.paid_on, pg.reference, pg.receipt_no,
                               (SELECT min(lp.payref) FROM finance.legacy_payref lp WHERE lp.reference = pg.reference) AS payref
                          FROM (SELECT * FROM p ORDER BY p.part, p.reference OFFSET :off LIMIT :n) pg
                          LEFT JOIN people.student s ON s.id = pg.student_id) r))::text
                """).param("id", id).param("page", pg).param("size", n).param("off", (pg - 1) * n).param("n", n).query(String.class).single();
        return map(text);
    }
}
