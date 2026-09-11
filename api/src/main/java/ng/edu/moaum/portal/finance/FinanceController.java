package ng.edu.moaum.portal.finance;

import java.math.BigDecimal;
import java.sql.Types;
import java.time.LocalDate;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import jakarta.validation.Valid;
import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

import ng.edu.moaum.portal.shared.DomainRuleViolation;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/** The Bursary's desk: the schedule, the scheme, the references waiting, the confirmations. */
@RestController
@RequestMapping("/api/v1/finance")
class FinanceController {

    private static final String READERS = "hasAnyAuthority('OFFICE_bursar','OFFICE_registrar','OFFICE_dregistrar','OFFICE_academic','OFFICE_audit','OFFICE_ict','OFFICE_admin','OFFICE_super','OFFICE_vc','OFFICE_dvc')";
    private static final String BURSARY = "hasAnyAuthority('OFFICE_bursar','OFFICE_super')";
    /** who may reconcile a transaction against the bank: the Bursary and the audit directorate */
    private static final String RECONCILERS = "hasAnyAuthority('OFFICE_bursar','OFFICE_audit','OFFICE_deputyaudit','OFFICE_super')";

    public record Item(@NotBlank @Size(max = 120) String item, @NotNull @DecimalMin("0") BigDecimal amount, Integer level,
                       @Size(max = 20) String entryMode, @Size(max = 12) String facultyCode, @Size(max = 12) String programmeCode,
                       @Size(max = 12) String feeGroup, Integer semester, Integer ord) {
    }

    public record Scheme(@NotBlank @Size(max = 200) String instrument, LocalDate from) {
    }

    public record Confirmation(@NotBlank @Size(max = 60) String channel, @Size(max = 400) String note) {
    }

    public record FeeRows(@NotNull List<Map<String, Object>> rows) {
    }

    private final JdbcClient jdbc;
    private final tools.jackson.databind.ObjectMapper json;

    FinanceController(JdbcClient jdbc, tools.jackson.databind.ObjectMapper json) {
        this.jdbc = jdbc;
        this.json = json;
    }

    /** upload the approved fees structure for a session — one row per faculty/level/semester/indigeneship cell;
     *  it replaces the session's structure. */
    @PostMapping("/sessions/{session}/{year}/fee-structure")
    @PreAuthorize(BURSARY)
    @Transactional
    Map<String, Object> importFeeStructure(@PathVariable String session, @PathVariable String year, @Valid @RequestBody FeeRows body) {
        if (body.rows() == null || body.rows().isEmpty()) {
            throw new DomainRuleViolation("FEE_ROWS", "The structure has no rows to read.",
                    new DomainRuleViolation.Remedy("Upload the approved fees spreadsheet.", "Bursary"));
        }
        return jdbc.sql("SELECT * FROM finance.import_fee_structure(:s, :j::jsonb)")
                .param("s", session + "/" + year).param("j", json.writeValueAsString(body.rows())).query().singleRow();
    }

    @GetMapping("/sessions/{session}/{year}/fee-structure")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> feeStructure(@PathVariable String session, @PathVariable String year) {
        return jdbc.sql("SELECT * FROM finance.fee_structure(:s)").param("s", session + "/" + year).query().listOfRows();
    }

    /** old students' school-fees history from the old portal — each row settles a past session (or semester)
     *  by amount paid, or in full against the fee schedule when the amount is left blank. */
    @PostMapping("/legacy-fees")
    @PreAuthorize(BURSARY)
    @Transactional
    Map<String, Object> importLegacyFees(@Valid @RequestBody FeeRows body) {
        if (body.rows() == null || body.rows().isEmpty()) {
            throw new DomainRuleViolation("FEE_ROWS", "The file has no rows to read.",
                    new DomainRuleViolation.Remedy("Upload the old-portal fees export.", "Bursary"));
        }
        return jdbc.sql("SELECT * FROM finance.import_legacy_payments(:j::jsonb)")
                .param("j", json.writeValueAsString(body.rows())).query().singleRow();
    }

    /* ── the schedule ── */

    @GetMapping("/sessions/{session}/{year}/schedule")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> schedule(@PathVariable String session, @PathVariable String year) {
        String s = session + "/" + year;
        List<Map<String, Object>> items = jdbc.sql("""
                SELECT f.id, f.item, f.amount, f.level, f.entry_mode, f.faculty_code, fa.name AS faculty_name,
                       f.programme_code, p.name AS programme_name, f.fee_group, g.name AS fee_group_name, f.semester, f.ord, f.spillover
                  FROM finance.fee_schedule f
                  LEFT JOIN ref.faculty fa ON fa.code = f.faculty_code
                  LEFT JOIN ref.programme p ON p.code = f.programme_code
                  LEFT JOIN ref.fee_group g ON g.code = f.fee_group
                 WHERE f.session = :s AND f.ended_at IS NULL ORDER BY f.ord, f.item
                """).param("s", s).query().listOfRows();
        Map<String, Object> scheme = jdbc.sql("""
                SELECT v.id, v.instrument, lower(v.validity) AS from_date, upper(v.validity) AS until_date, v.decided_by,
                       (SELECT json_object_agg(r.purpose, r.releases_at)::text FROM policy.clearance_rule r WHERE r.version_id = v.id) AS rules
                  FROM policy.version v WHERE v.kind = 'clearance' AND v.scope = 'UNIVERSITY' AND v.validity @> current_date
                """).query().listOfRows().stream().findFirst().orElse(null);
        Map<String, Object> position = jdbc.sql("""
                SELECT count(DISTINCT r.student_id) AS students_paying, coalesce(sum(r.amount) FILTER (WHERE r.confirmed_at IS NOT NULL), 0) AS confirmed,
                       count(*) FILTER (WHERE r.confirmed_at IS NULL AND r.expires_at > now()) AS references_open
                  FROM finance.payment_reference r WHERE r.session = :s
                """).param("s", s).query().singleRow();
        return Map.of("session", s, "items", items, "scheme", scheme == null ? Map.of() : scheme, "schemeInForce", scheme != null, "position", position);
    }

    /** the fee groups a charge can be scoped to — data, not code, so the set can grow */
    @GetMapping("/fee-groups")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> feeGroups() {
        return jdbc.sql("SELECT code, name, applies_category FROM ref.fee_group ORDER BY ord, name").query().listOfRows();
    }

    /** the payment categories a charge can be named from — data, so the set can grow */
    @GetMapping("/fee-items")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> feeItems() {
        return jdbc.sql("SELECT code, name FROM ref.fee_item ORDER BY ord, name").query().listOfRows();
    }

    /** every programme, for the fee-setup programme select */
    @GetMapping("/programmes")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> programmes() {
        return jdbc.sql("SELECT code, name, category, faculty_code FROM ref.programme WHERE NOT archived ORDER BY name").query().listOfRows();
    }

    @PostMapping("/sessions/{session}/{year}/schedule")
    @PreAuthorize(BURSARY)
    @Transactional
    Map<String, Object> addItem(@PathVariable String session, @PathVariable String year, @Valid @RequestBody Item body) {
        String s = session + "/" + year;
        if (body.level() != null && !List.of(100, 200, 300, 400, 500, 600).contains(body.level())) {
            throw new DomainRuleViolation("FEE_LEVEL", "A level is 100 to 600.", new DomainRuleViolation.Remedy("Leave it blank for every level.", "Bursary"));
        }
        if (body.semester() != null && !List.of(1, 2, 3).contains(body.semester())) {
            throw new DomainRuleViolation("FEE_SEMESTER", "A semester is 1 or 2.", new DomainRuleViolation.Remedy("Leave it blank for the whole session.", "Bursary"));
        }
        jdbc.sql("""
                INSERT INTO finance.fee_schedule (session, item, amount, level, entry_mode, faculty_code, programme_code, fee_group, semester, ord)
                VALUES (:s, :i, :a, :l, :m, :f, :p, :g, :sem, :o)
                """).param("s", s).param("i", body.item().trim()).param("a", body.amount()).param("l", body.level(), Types.INTEGER)
                .param("m", blank(body.entryMode()), Types.VARCHAR).param("f", blank(body.facultyCode()), Types.VARCHAR)
                .param("p", blank(body.programmeCode()), Types.VARCHAR).param("g", blank(body.feeGroup()), Types.VARCHAR)
                .param("sem", body.semester(), Types.INTEGER)
                .param("o", body.ord() == null ? 0 : body.ord()).update();
        return schedule(session, year);
    }

    @PostMapping("/sessions/{session}/{year}/schedule/{id}/end")
    @PreAuthorize(BURSARY)
    @Transactional
    Map<String, Object> endItem(@PathVariable String session, @PathVariable String year, @PathVariable UUID id) {
        jdbc.sql("UPDATE finance.fee_schedule SET ended_at = now() WHERE id = :id AND session = :s AND ended_at IS NULL")
                .param("id", id).param("s", session + "/" + year).update();
        return schedule(session, year);
    }

    /** edit a standing fee line in place — its amount and the filters it carries */
    @PutMapping("/sessions/{session}/{year}/schedule/{id}")
    @PreAuthorize(BURSARY)
    @Transactional
    Map<String, Object> editItem(@PathVariable String session, @PathVariable String year, @PathVariable UUID id, @Valid @RequestBody Item body) {
        if (body.level() != null && !List.of(100, 200, 300, 400, 500, 600).contains(body.level())) {
            throw new DomainRuleViolation("FEE_LEVEL", "A level is 100 to 600.", new DomainRuleViolation.Remedy("Leave it blank for every level.", "Bursary"));
        }
        if (body.semester() != null && !List.of(1, 2, 3).contains(body.semester())) {
            throw new DomainRuleViolation("FEE_SEMESTER", "A semester is 1 or 2.", new DomainRuleViolation.Remedy("Leave it blank for the whole session.", "Bursary"));
        }
        int n = jdbc.sql("""
                UPDATE finance.fee_schedule SET item = :i, amount = :a, level = :l, entry_mode = :m, faculty_code = :f,
                       programme_code = :p, fee_group = :g, semester = :sem, ord = :o
                 WHERE id = :id AND session = :s AND ended_at IS NULL
                """).param("id", id).param("s", session + "/" + year)
                .param("i", body.item().trim()).param("a", body.amount()).param("l", body.level(), Types.INTEGER)
                .param("m", blank(body.entryMode()), Types.VARCHAR).param("f", blank(body.facultyCode()), Types.VARCHAR)
                .param("p", blank(body.programmeCode()), Types.VARCHAR).param("g", blank(body.feeGroup()), Types.VARCHAR)
                .param("sem", body.semester(), Types.INTEGER).param("o", body.ord() == null ? 0 : body.ord()).update();
        if (n == 0) {
            throw new DomainRuleViolation("FEE_GONE", "That fee line is not on the current schedule.",
                    new DomainRuleViolation.Remedy("Refresh the schedule.", "Bursary"));
        }
        return schedule(session, year);
    }

    /* ── the scheme ── */

    @PostMapping("/clearance-scheme")
    @PreAuthorize(BURSARY)
    @Transactional
    Map<String, Object> scheme(@Valid @RequestBody Scheme body) {
        UUID id = jdbc.sql("SELECT finance.put_scheme_in_force(:i, :d)").param("i", body.instrument())
                .param("d", body.from() == null ? LocalDate.now() : body.from()).query(UUID.class).single();
        return Map.of("versionId", id, "inForceFrom", body.from() == null ? LocalDate.now() : body.from());
    }

    /* ── the references ── */

    @GetMapping("/references")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> references(@RequestParam(required = false) String session, @RequestParam(defaultValue = "open") String state) {
        return jdbc.sql("""
                SELECT r.id, r.reference, r.session, r.purpose, r.amount, r.generated_at, r.expires_at, r.confirmed_at, r.channel, r.note, r.receipt_no,
                       s.matric_no, s.admission_no, s.surname, s.other_names, p.name AS programme, s.current_level
                  FROM finance.payment_reference r JOIN people.student s ON s.id = r.student_id JOIN ref.programme p ON p.code = s.programme_code
                 WHERE (:s::text IS NULL OR r.session = :s)
                   AND CASE :st WHEN 'open' THEN r.confirmed_at IS NULL AND r.expires_at > now() WHEN 'confirmed' THEN r.confirmed_at IS NOT NULL ELSE true END
                 ORDER BY r.generated_at DESC LIMIT 500
                """).param("s", session, Types.VARCHAR).param("st", state).query().listOfRows();
    }

    @PostMapping("/references/{reference}/confirm")
    @PreAuthorize("hasAnyAuthority('OFFICE_bursar','OFFICE_super')")
    @Transactional
    Map<String, Object> confirm(@PathVariable String reference, @Valid @RequestBody Confirmation body) {
        String outcome = jdbc.sql("SELECT finance.confirm_payment(:r, :c, :n)").param("r", reference).param("c", body.channel())
                .param("n", body.note(), Types.VARCHAR).query(String.class).single();
        return Map.of("reference", reference, "outcome", outcome);
    }

    private static String blank(String s) {
        return s == null || s.isBlank() ? null : s.trim().toUpperCase();
    }

    /* ── V037: the Bursar's dashboard, the day book, the bank credits ── */

    public record Credit(LocalDate receivedOn, @NotBlank @Size(max = 80) String bank, @NotBlank @Size(max = 80) String instrument,
                         @NotNull @DecimalMin("0.01") BigDecimal amount, @Size(max = 200) String payer, @Size(max = 400) String note) {
    }

    public record Proposal(@NotBlank @Size(max = 60) String reference, @NotBlank @Size(max = 600) String why) {
    }

    public record Why(@NotBlank @Size(max = 400) String why) {
    }

    @GetMapping("/bursary")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> bursary(@RequestParam(required = false) String session) {
        String s = session == null || session.isBlank() ? jdbc.sql("SELECT name FROM policy.academic_session WHERE state = 'CURRENT'").query(String.class).optional().orElse("2026/2027") : session;
        Map<String, Object> out = new java.util.LinkedHashMap<>();
        out.put("session", s);
        out.put("tiles", jdbc.sql("""
                SELECT (SELECT coalesce(sum(amount), 0) FROM finance.payment_reference WHERE session = :s AND confirmed_at IS NOT NULL AND purpose LIKE 'School fees%') AS fees_collected,
                       (SELECT coalesce(sum(amount), 0) FROM finance.payment_reference WHERE confirmed_at::date = current_date) AS today,
                       (SELECT count(*) FROM finance.payment_reference WHERE confirmed_at::date = current_date) AS today_count,
                       (SELECT count(*) FROM finance.payment_reference WHERE confirmed_at IS NULL AND expires_at > now()) AS references_open,
                       (SELECT count(*) FROM finance.bank_credit WHERE state IN ('UNMATCHED','PROPOSED')) AS credits_open,
                       (SELECT coalesce(sum(amount), 0) FROM finance.bank_credit WHERE state IN ('UNMATCHED','PROPOSED')) AS credits_open_amount,
                       (SELECT count(*) FROM finance.gateway_event WHERE outcome IN ('UNKNOWN_REFERENCE','SHORT_PAID','BAD_SIGNATURE','GATEWAY_ERROR') AND resolved_at IS NULL) AS gateway_exceptions,
                       (SELECT count(*) FROM finance.gateway_attempt a LEFT JOIN LATERAL finance.reference_state(a.reference) st ON true
                         WHERE a.opened_at > now() - interval '3 days' AND st.confirmed_at IS NULL) AS hanging,
                       (SELECT policy.in_force('clearance', 'UNIVERSITY', current_date) IS NOT NULL) AS scheme_in_force,
                       (SELECT count(*) FROM finance.fee_schedule WHERE session = :s AND ended_at IS NULL) AS schedule_items
                """).param("s", s).query().singleRow());
        out.put("byFaculty", jdbc.sql("SELECT * FROM finance.collection_by_faculty(:s)").param("s", s).query().listOfRows());
        out.put("recent", jdbc.sql("SELECT * FROM finance.day_book(current_date - 7, current_date) LIMIT 12").query().listOfRows());
        return out;
    }

    @GetMapping("/ledger")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> ledger(@RequestParam(required = false) LocalDate from, @RequestParam(required = false) LocalDate to) {
        LocalDate f = from == null ? LocalDate.now().minusDays(30) : from;
        LocalDate t = to == null ? LocalDate.now() : to;
        List<Map<String, Object>> rows = jdbc.sql("SELECT * FROM finance.day_book(:f, :t)").param("f", f).param("t", t).query().listOfRows();
        return Map.of("from", f, "to", t, "rows", rows);
    }

    /* ── V068: reconciliation of confirmed payments against the bank ── */

    public record Check(@NotBlank @Size(max = 20) String result, @Size(max = 120) String bankReference, @Size(max = 400) String note) {
    }

    @GetMapping("/reconciliation")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> reconciliation(@RequestParam(required = false) LocalDate from, @RequestParam(required = false) LocalDate to) {
        LocalDate f = from == null ? LocalDate.now().minusDays(30) : from;
        LocalDate t = to == null ? LocalDate.now() : to;
        List<Map<String, Object>> rows = jdbc.sql("SELECT * FROM finance.reconciliation_list(:f, :t)").param("f", f).param("t", t).query().listOfRows();
        return Map.of("from", f, "to", t, "rows", rows);
    }

    @PostMapping("/reconciliation/{reference}/check")
    @PreAuthorize(RECONCILERS)
    @Transactional
    Map<String, Object> reconcile(@PathVariable String reference, @Valid @RequestBody Check body) {
        UUID id = jdbc.sql("SELECT finance.reconcile_payment(:r, :res, :b, :n)")
                .param("r", reference).param("res", body.result())
                .param("b", body.bankReference(), Types.VARCHAR).param("n", body.note(), Types.VARCHAR)
                .query(UUID.class).single();
        return Map.of("id", id, "reference", reference.toUpperCase(), "result", body.result().toUpperCase());
    }

    @GetMapping("/bank-credits")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> bankCredits(@RequestParam(defaultValue = "open") String state) {
        return jdbc.sql("""
                SELECT c.id, c.received_on, c.bank, c.instrument, c.amount, c.payer, c.note, c.recorded_at, c.state, c.proposed_reference, c.proposed_why, c.proposed_at,
                       c.approved_at, c.posted_reference, c.rejected_why,
                       pr.surname || ', ' || pr.given_names AS proposed_by_name, ap.surname || ', ' || ap.given_names AS approved_by_name, rc.surname || ', ' || rc.given_names AS recorded_by_name,
                       c.proposed_by = nullif(current_setting('moaum.actor_id', true), '')::uuid AS proposed_by_me,
                       st.amount AS reference_amount, st.confirmed_at AS reference_confirmed_at
                  FROM finance.bank_credit c
                  LEFT JOIN iam.person pr ON pr.id = c.proposed_by LEFT JOIN iam.person ap ON ap.id = c.approved_by LEFT JOIN iam.person rc ON rc.id = c.recorded_by
                  LEFT JOIN LATERAL finance.reference_state(c.proposed_reference) st ON c.proposed_reference IS NOT NULL
                 WHERE CASE :st WHEN 'open' THEN c.state IN ('UNMATCHED','PROPOSED') WHEN 'posted' THEN c.state = 'POSTED' ELSE true END
                 ORDER BY (c.state = 'PROPOSED') DESC, c.received_on, c.recorded_at LIMIT 300
                """).param("st", state).query().listOfRows();
    }

    @PostMapping("/bank-credits")
    @PreAuthorize(BURSARY)
    @Transactional
    Map<String, Object> recordCredit(@Valid @RequestBody Credit body) {
        UUID id = jdbc.sql("SELECT finance.record_bank_credit(:d, :b, :i, :a, :p, :n)").param("d", body.receivedOn(), Types.DATE).param("b", body.bank())
                .param("i", body.instrument()).param("a", body.amount()).param("p", body.payer(), Types.VARCHAR).param("n", body.note(), Types.VARCHAR).query(UUID.class).single();
        return Map.of("id", id, "state", "UNMATCHED");
    }

    @PostMapping("/bank-credits/{id}/propose")
    @PreAuthorize(BURSARY)
    @Transactional
    Map<String, Object> propose(@PathVariable UUID id, @Valid @RequestBody Proposal body) {
        jdbc.sql("SELECT finance.propose_bank_credit(:id, :r, :w)").param("id", id).param("r", body.reference()).param("w", body.why()).query().singleRow();
        return Map.of("id", id, "state", "PROPOSED");
    }

    @PostMapping("/bank-credits/{id}/approve")
    @PreAuthorize(BURSARY)
    @Transactional
    Map<String, Object> approve(@PathVariable UUID id) {
        String outcome = jdbc.sql("SELECT finance.approve_bank_credit(:id)").param("id", id).query(String.class).single();
        return Map.of("id", id, "state", "POSTED", "outcome", outcome);
    }

    @PostMapping("/bank-credits/{id}/reject")
    @PreAuthorize(BURSARY)
    @Transactional
    Map<String, Object> reject(@PathVariable UUID id, @Valid @RequestBody Why body) {
        jdbc.sql("SELECT finance.reject_bank_credit(:id, :w)").param("id", id).param("w", body.why()).query().singleRow();
        return Map.of("id", id, "state", "UNMATCHED");
    }
}
