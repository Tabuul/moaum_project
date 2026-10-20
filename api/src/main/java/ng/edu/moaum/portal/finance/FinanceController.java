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
import jakarta.validation.constraints.Pattern;
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
import ng.edu.moaum.portal.shared.Sessions;

/** The Bursary's desk: the schedule, the scheme, the references waiting, the confirmations. */
@RestController
@RequestMapping("/api/v1/finance")
class FinanceController {

    private static final String READERS = "hasAnyAuthority('OFFICE_bursar','OFFICE_studentaccounts','OFFICE_registrar','OFFICE_dregistrar','OFFICE_academic','OFFICE_audit','OFFICE_deputyaudit','OFFICE_ict','OFFICE_admin','OFFICE_super','OFFICE_vc','OFFICE_dvc')";
    private static final String BURSARY = "hasAnyAuthority('OFFICE_bursar','OFFICE_super')";
    /** V520: the school fees setup and binding — the fee schedule, its lines, copies and fee sources — the Bursary's and the Students
     *  Account Officer's; the officer holds none of the Bursary's other writes (confirmations, bank credits, old fees, clearance) */
    private static final String FEE_SETTERS = "hasAnyAuthority('OFFICE_bursar','OFFICE_studentaccounts','OFFICE_super')";
    /** V591: the Old Fees History desk's import — the old portal's fees history loaded, what is loaded, the item codes, records put
     *  right and doubles withdrawn — the Bursary's and the Students Account Officer's; what needs the bank's word or moves money
     *  (double charges, payments never received, an excess carried or refunded), the ledger and the go-live reset stay the Bursar's */
    private static final String OLD_FEES_DESK = "hasAnyAuthority('OFFICE_bursar','OFFICE_studentaccounts','OFFICE_super')";
    /** who may reconcile a transaction against the bank: the Bursary and the audit directorate */
    private static final String RECONCILERS = "hasAnyAuthority('OFFICE_bursar','OFFICE_audit','OFFICE_deputyaudit','OFFICE_super')";
    private static final String MIGRATORS = "hasAnyAuthority('OFFICE_bursar','OFFICE_super','OFFICE_ict','OFFICE_admin')";

    public record Item(@NotBlank @Size(max = 120) String item, @NotNull @DecimalMin("0") BigDecimal amount, Integer level,
                       @Size(max = 20) String entryMode, @Size(max = 12) String facultyCode, @Size(max = 12) String programmeCode,
                       @Size(max = 12) String feeGroup, Integer semester, Integer ord,
                       /** V288: FEE, or LATE_PAYMENT / LATE_REGISTRATION charged only in the window's late period */
                       @Pattern(regexp = "FEE|LATE_PAYMENT|LATE_REGISTRATION") String kind) {
    }

    public record Scheme(@NotBlank @Size(max = 200) String instrument, LocalDate from) {
    }

    public record Confirmation(@NotBlank @Size(max = 60) String channel, @Size(max = 400) String note) {
    }

    public record TransferFee(@NotNull @DecimalMin("0") BigDecimal amount) {
    }

    public record FeeRows(@NotNull List<Map<String, Object>> rows) {
    }

    /** V535: the structure upload says what it replaces — LISTED, only the faculties and programmes the file names; SESSION, the
     *  whole session's structure, refused when the file leaves out a faculty with lines in force unless confirmWhole */
    public record StructureRows(@NotNull List<Map<String, Object>> rows, @Pattern(regexp = "SESSION|LISTED") String scope, Boolean confirmWhole) {
    }

    private final JdbcClient jdbc;
    private final tools.jackson.databind.ObjectMapper json;

    FinanceController(JdbcClient jdbc, tools.jackson.databind.ObjectMapper json) {
        this.jdbc = jdbc;
        this.json = json;
    }

    /** bulk-load past students' confirmed payment (school-fees) history from the old portal (V120); retired by V498 — the
     *  database refuses (PAYMENT_HISTORY_RETIRED): old payments come in on Old Fees History alone */
    @PostMapping("/payments/import")
    @PreAuthorize(MIGRATORS)
    @Transactional
    Map<String, Object> importPayments(@Valid @RequestBody FeeRows body) {
        if (body.rows() == null || body.rows().isEmpty()) {
            throw new DomainRuleViolation("PAYMENT_ROWS", "The file has no rows to read.",
                    new DomainRuleViolation.Remedy("Upload the payment-history spreadsheet.", "Bursary"));
        }
        return jdbc.sql("SELECT * FROM finance.import_payments(:j::jsonb)")
                .param("j", json.writeValueAsString(body.rows())).query().singleRow();
    }

    /** upload the approved fees structure for a session — one row per faculty/level/semester/indigeneship cell; V535: it
     *  replaces only the faculties and programmes the file names (scope LISTED) or, on purpose, the whole session (SESSION) */
    @PostMapping("/sessions/{session}/{year}/fee-structure")
    @PreAuthorize(FEE_SETTERS)
    @Transactional
    Map<String, Object> importFeeStructure(@PathVariable String session, @PathVariable String year, @Valid @RequestBody StructureRows body) {
        if (body.rows() == null || body.rows().isEmpty()) {
            throw new DomainRuleViolation("FEE_ROWS", "The structure has no rows to read.",
                    new DomainRuleViolation.Remedy("Upload the approved fees spreadsheet.", "Bursary"));
        }
        return jdbc.sql("SELECT * FROM finance.import_fee_structure(:s, :j::jsonb, :scope, :whole)")
                .param("s", session + "/" + year).param("j", json.writeValueAsString(body.rows()))
                .param("scope", body.scope() == null ? "SESSION" : body.scope())
                .param("whole", Boolean.TRUE.equals(body.confirmWhole())).query().singleRow();
    }

    /** V535: what the structure upload would do — the lines new, changed, the same and ended for each faculty or programme, the
     *  faculties left with no line, the amounts that change and the students with no fee stated before and after; nothing kept */
    @PostMapping("/sessions/{session}/{year}/fee-structure/preview")
    @PreAuthorize(FEE_SETTERS)
    @Transactional
    Map<String, Object> previewFeeStructure(@PathVariable String session, @PathVariable String year, @Valid @RequestBody StructureRows body) {
        if (body.rows() == null || body.rows().isEmpty()) {
            throw new DomainRuleViolation("FEE_ROWS", "The structure has no rows to read.",
                    new DomainRuleViolation.Remedy("Upload the approved fees spreadsheet.", "Bursary"));
        }
        return effect(jdbc.sql("SELECT finance.fee_upload_effect(:s, :j::jsonb, 'STRUCTURE', :scope)::text")
                .param("s", session + "/" + year).param("j", json.writeValueAsString(body.rows()))
                .param("scope", body.scope() == null ? "LISTED" : body.scope()).query(String.class).single());
    }

    @SuppressWarnings("unchecked")
    private Map<String, Object> effect(String text) {
        return json.readValue(text, Map.class);
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
    @PreAuthorize(OLD_FEES_DESK)
    @Transactional
    Map<String, Object> importLegacyFees(@Valid @RequestBody FeeRows body) {
        if (body.rows() == null || body.rows().isEmpty()) {
            throw new DomainRuleViolation("FEE_ROWS", "The file has no rows to read.",
                    new DomainRuleViolation.Remedy("Upload the old-portal fees export.", "Bursary"));
        }
        return jdbc.sql("SELECT * FROM finance.import_legacy_payments(:j::jsonb)")
                .param("j", json.writeValueAsString(body.rows())).query().singleRow();
    }

    /** what the old-portal fees import has loaded (all sessions, or one) — shown before a reset */
    @GetMapping("/legacy-fees/loaded")
    @PreAuthorize(OLD_FEES_DESK)
    @Transactional(readOnly = true)
    Map<String, Object> legacyFeesLoaded(@RequestParam(required = false) String session) {
        return jdbc.sql("SELECT * FROM finance.legacy_payment_count((:s)::text)")
                .param("s", session == null || session.isBlank() ? null : session).query().singleRow();
    }

    /** V498: every old-portal payment on record twice — what the retired Payment History Upload wrote that repeats a record, and
     *  the Old Fees History records earlier uploads left twice: the count and amount (by kind), those something points at, and
     *  the first rows (all of them, up to 100,000, for the Excel list) */
    @GetMapping("/legacy-fees/doubles")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> paymentHistoryDoubles(@RequestParam(defaultValue = "200") int limit) {
        int n = Math.max(1, Math.min(limit, 100_000));
        String text = jdbc.sql("""
                WITH d AS MATERIALIZED (SELECT * FROM finance.old_payment_doubles())
                SELECT json_build_object(
                    'count', (SELECT count(*) FROM d),
                    'amount', (SELECT coalesce(sum(amount), 0) FROM d),
                    'linked', (SELECT count(*) FROM d WHERE linked IS NOT NULL),
                    'students', (SELECT count(DISTINCT student_id) FROM d),
                    'kinds', (SELECT coalesce(json_object_agg(t.double_kind, t.n), '{}'::json) FROM (SELECT double_kind, count(*) AS n FROM d GROUP BY double_kind) t),
                    'withdrawn', (SELECT count(*) FROM finance.old_payment_withdrawn),
                    'rows', (SELECT coalesce(json_agg(r), '[]'::json) FROM (
                        SELECT double_reference, double_kind, kept_reference, kept_kind, number, name, session, amount, paid_on::text AS paid_on, purpose, kept_purpose, linked
                          FROM d ORDER BY session DESC, number, double_reference LIMIT :n) r))::text
                """).param("n", n).query(String.class).single();
        return json.readValue(text, new tools.jackson.core.type.TypeReference<Map<String, Object>>() { });
    }

    public record WithdrawDoubles(@NotBlank @Size(min = 10, max = 500) String reason, Integer limit) { }

    /** V498: withdraws a batch of those doubles (the screen asks again until none is left): each one's ledger posting reversed,
     *  the record kept on the register, then removed (a whole-session record's payment number moving to the per-semester record
     *  that stands for it); one a deferment fee, a refund or the GST reconciliation points at is left */
    @PostMapping("/legacy-fees/doubles/withdraw")
    @PreAuthorize(OLD_FEES_DESK)
    @Transactional
    Map<String, Object> withdrawPaymentHistoryDoubles(@Valid @RequestBody WithdrawDoubles body) {
        int n = body.limit() == null ? 5000 : Math.max(1, Math.min(body.limit(), 20_000));
        return jdbc.sql("SELECT * FROM finance.withdraw_old_payment_doubles(:r, :n)").param("r", body.reason().trim()).param("n", n).query().singleRow();
    }

    /** V498: the old portal's payment-item codes (the export's payment_type sheet: pcode, description, school), kept so the import
     *  reads a code as the item it names and what was recorded under a code can be put right */
    @PostMapping("/legacy-fees/item-codes")
    @PreAuthorize(OLD_FEES_DESK)
    @Transactional
    Map<String, Object> legacyItemCodes(@Valid @RequestBody FeeRows body) {
        int n = jdbc.sql("SELECT finance.legacy_item_codes_set(:j::jsonb)").param("j", json.writeValueAsString(body.rows())).query(Integer.class).single();
        return Map.of("loaded", n);
    }

    /** V498: the records earlier uploads made under the old portal's item code ("10048 (legacy)"), or under a label the rules now read
     *  otherwise, with what each is and what putting it right does; the codes the list does not name yet */
    @GetMapping("/legacy-fees/mislabelled")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> legacyMislabelled(@RequestParam(defaultValue = "200") int limit) {
        int n = Math.max(1, Math.min(limit, 100_000));
        String text = jdbc.sql("""
                WITH m AS MATERIALIZED (SELECT * FROM finance.legacy_mislabelled())
                SELECT json_build_object(
                    'count', (SELECT count(*) FROM m),
                    'amount', (SELECT coalesce(sum(amount), 0) FROM m),
                    'students', (SELECT count(DISTINCT student_id) FROM m),
                    'actions', (SELECT coalesce(json_object_agg(t.action, t.n), '{}'::json) FROM (SELECT action, count(*) AS n FROM m GROUP BY action) t),
                    'unknownCodes', (SELECT coalesce(json_agg(DISTINCT regexp_replace(stored_purpose, ' \\(legacy\\).*$', '')), '[]'::json) FROM m WHERE action = 'UNKNOWN_CODE'),
                    'codes', (SELECT count(*) FROM finance.legacy_item_code),
                    'rows', (SELECT coalesce(json_agg(r), '[]'::json) FROM (
                        SELECT reference, number, name, session, amount, paid_on::text AS paid_on, stored_purpose, item, target_reference, target_purpose, action
                          FROM m ORDER BY CASE action WHEN 'RENAME' THEN 0 WHEN 'DOUBLE' THEN 1 WHEN 'RELABEL' THEN 2 ELSE 3 END, session DESC, number, reference
                         LIMIT :n) r))::text
                """).param("n", n).query(String.class).single();
        return json.readValue(text, new tools.jackson.core.type.TypeReference<Map<String, Object>>() { });
    }

    /** V498: puts a batch of them right (the screen asks again until none is left): renamed or relabelled so school fees count, or
     *  withdrawn where the same payment is on record under its item; each kept on its register with the reason */
    @PostMapping("/legacy-fees/mislabelled/put-right")
    @PreAuthorize(OLD_FEES_DESK)
    @Transactional
    Map<String, Object> putRightLegacyItems(@Valid @RequestBody WithdrawDoubles body) {
        int n = body.limit() == null ? 5000 : Math.max(1, Math.min(body.limit(), 20_000));
        return jdbc.sql("SELECT * FROM finance.put_right_legacy_items(:r, :n)").param("r", body.reason().trim()).param("n", n).query().singleRow();
    }

    /** V502: what the retired Payment History Upload recorded that nothing has matched (not taken over by Old Fees History, not a
     *  repeat of another record), with what each counts as now: the counts, then the first rows (up to 100,000 for the Excel list) */
    @GetMapping("/legacy-fees/payment-history-left")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> paymentHistoryLeft(@RequestParam(defaultValue = "200") int limit) {
        int n = Math.max(1, Math.min(limit, 100_000));
        String text = jdbc.sql("""
                WITH l AS MATERIALIZED (SELECT * FROM finance.payment_history_left())
                SELECT json_build_object(
                    'count', (SELECT count(*) FROM l),
                    'amount', (SELECT coalesce(sum(amount), 0) FROM l),
                    'students', (SELECT count(DISTINCT student_id) FROM l),
                    'countsAs', (SELECT coalesce(json_object_agg(t.counts_as, t.n), '{}'::json) FROM (SELECT counts_as, count(*) AS n FROM l GROUP BY counts_as) t),
                    'rows', (SELECT coalesce(json_agg(r), '[]'::json) FROM (
                        SELECT reference, number, name, session, amount, paid_on::text AS paid_on, number_day::text AS number_day, purpose, counts_as
                          FROM l ORDER BY session DESC, number, reference LIMIT :n) r))::text
                """).param("n", n).query(String.class).single();
        return json.readValue(text, new tools.jackson.core.type.TypeReference<Map<String, Object>>() { });
    }

    /** V498: the old-portal school-fees payments of a session reconciled against the fee setup — the states counted, then the
     *  students, those under or over first; filtered by state and by number or name */
    @GetMapping("/legacy-fees/reconciliation")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> oldFeesReconciliation(@RequestParam(required = false) String session, @RequestParam(required = false) String state,
                                              @RequestParam(required = false) String q, @RequestParam(defaultValue = "1") int page,
                                              @RequestParam(defaultValue = "50") int size) {
        String ses = session != null && session.matches("^[0-9]{4}/[0-9]{4}$") ? session
                : jdbc.sql("SELECT policy.university_current_session()").query(String.class).single();
        String st = state == null || state.isBlank() ? null : state.trim().toUpperCase();
        String term = q == null || q.isBlank() ? null : "%" + q.trim().toUpperCase() + "%";
        int sz = Math.max(1, Math.min(size, 100_000));
        int pg = Math.max(1, page);
        String text = jdbc.sql("""
                WITH x AS MATERIALIZED (SELECT * FROM finance.old_fees_reconciliation(:s)),
                f AS (SELECT * FROM x WHERE (:st::text IS NULL OR x.state = :st) AND (:q::text IS NULL OR upper(x.number) LIKE :q OR upper(x.name) LIKE :q))
                SELECT json_build_object(
                    'session', :s::text,
                    'sessions', (SELECT coalesce(json_agg(t.session ORDER BY t.session DESC), '[]'::json)
                                   FROM (SELECT DISTINCT r.session FROM finance.payment_reference r
                                          WHERE (r.reference LIKE 'MOAUM-LEG-%' OR r.reference NOT LIKE 'MOAUM-%') AND r.purpose LIKE 'School fees%'
                                            AND r.session ~ '^[0-9]{4}/[0-9]{4}$') t),
                    'summary', (SELECT coalesce(json_agg(t ORDER BY t.state), '[]'::json)
                                  FROM (SELECT state, count(*) AS students, sum(due) AS due, sum(paid) AS paid, sum(difference) AS difference FROM x GROUP BY state) t),
                    'total', (SELECT count(*) FROM f),
                    'rows', (SELECT coalesce(json_agg(r), '[]'::json) FROM (
                        SELECT student_id, number, name, programme_code, faculty_code, level, due, paid, paid_old_s1, paid_old_s2, paid_old_session,
                               paid_payment_history, paid_portal, old_payments, difference, state, carried_in, settled, decision
                          FROM f ORDER BY CASE f.state WHEN 'UNDER' THEN 0 WHEN 'OVER' THEN 1 WHEN 'NO_FEE_STATED' THEN 2 WHEN 'OVER_SETTLED' THEN 3 ELSE 4 END, abs(f.difference) DESC, f.number
                         LIMIT :n OFFSET :o) r))::text
                """).param("s", ses).param("st", st, Types.VARCHAR).param("q", term, Types.VARCHAR).param("n", sz).param("o", (long) (pg - 1) * sz)
                .query(String.class).single();
        Map<String, Object> out = new java.util.LinkedHashMap<>(json.readValue(text, new tools.jackson.core.type.TypeReference<Map<String, Object>>() { }));
        out.put("page", pg);
        out.put("size", sz);
        return out;
    }

    /** V506, V519: every student overpaid in a session (old-portal or portal payments) — due, paid, the excess — with the decision that stands
     *  (carried into the next session, or a refund raised), the counts, and the first rows (up to 100,000 for the Excel list). V561: and
     *  whether a possible bank double charge of the student's school fees waits for the Bursary's check (they are held from deciding) */
    @GetMapping("/legacy-fees/overpaid")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> overpaid(@RequestParam(required = false) String session, @RequestParam(defaultValue = "200") int limit) {
        String ses = session != null && session.matches("^[0-9]{4}/[0-9]{4}$") ? session
                : jdbc.sql("SELECT policy.university_current_session()").query(String.class).single();
        int n = Math.max(1, Math.min(limit, 100_000));
        String text = jdbc.sql("""
                WITH o AS MATERIALIZED (SELECT * FROM finance.overpaid(:s)),
                -- V561: a student whose school fees the bank may have charged twice waits for the Bursary's check with the bank
                dc AS MATERIALIZED (SELECT d.student_id, bool_or(d.verdict IS NULL OR d.open_requests > 0) AS waiting
                                      FROM finance.possible_double_charges(:s) d WHERE d.purpose LIKE 'School fees%' GROUP BY d.student_id)
                SELECT json_build_object(
                    'session', :s::text,
                    'sessions', (SELECT coalesce(json_agg(t.session ORDER BY t.session DESC), '[]'::json)
                                   FROM (SELECT DISTINCT r.session FROM finance.payment_reference r
                                          WHERE r.confirmed_at IS NOT NULL AND r.purpose LIKE 'School fees%'
                                            AND r.session ~ '^[0-9]{4}/[0-9]{4}$') t),
                    'nextSession', finance.next_session(:s),
                    'count', (SELECT count(*) FROM o),
                    'excess', (SELECT coalesce(sum(excess), 0) FROM o),
                    'undecided', (SELECT count(*) FROM o WHERE decision IS NULL),
                    'undecidedExcess', (SELECT coalesce(sum(excess), 0) FROM o WHERE decision IS NULL),
                    'oldPortal', (SELECT count(*) FROM o WHERE old_portal),
                    'heldForBank', (SELECT count(*) FROM o JOIN dc ON dc.student_id = o.student_id WHERE o.decision IS NULL AND dc.waiting),
                    'decided', (SELECT coalesce(json_object_agg(t.decision, t.n), '{}'::json) FROM (SELECT decision, count(*) AS n FROM o WHERE decision IS NOT NULL GROUP BY decision) t),
                    'rows', (SELECT coalesce(json_agg(r), '[]'::json) FROM (
                        SELECT o.student_id, number, name, programme_code, faculty_code, level, due, paid, excess, decision, decided, reference, to_session,
                               decided_at::text AS decided_at, refund_state, old_portal,
                               CASE WHEN dc.student_id IS NULL THEN NULL WHEN dc.waiting THEN 'CHECK_WITH_BANK' ELSE 'BANK_CHECKED' END AS double_charge
                          FROM o LEFT JOIN dc ON dc.student_id = o.student_id
                         ORDER BY (decision IS NULL) DESC, excess DESC, number LIMIT :n) r))::text
                """).param("s", ses).param("n", n).query(String.class).single();
        return json.readValue(text, new tools.jackson.core.type.TypeReference<Map<String, Object>>() { });
    }

    public record DecideOverpaid(@NotBlank @Pattern(regexp = "^[0-9]{4}/[0-9]{4}$") String session,
                                 @NotBlank @Pattern(regexp = "CARRY|REFUND") String decision, List<UUID> students,
                                 @NotBlank @Size(min = 10, max = 500) String reason, Integer limit) { }

    /** V506: the Bursary's decision for the overpaid of a session not yet decided — all of them, or the students named — in batches
     *  the screen asks for until none is left: carried into the next session (a CARRIED record there, its journal moving the
     *  income across) or refunded (a refund raised on the Refunds & Credits desk) */
    @PostMapping("/legacy-fees/overpaid/decide")
    @PreAuthorize(BURSARY)
    @Transactional
    Map<String, Object> decideOverpaid(@Valid @RequestBody DecideOverpaid body) {
        int n = body.limit() == null ? 2000 : Math.max(1, Math.min(body.limit(), 5000));
        boolean all = body.students() == null || body.students().isEmpty();
        var q = jdbc.sql("SELECT * FROM finance.decide_overpayments(:s, :d, " + (all ? "NULL::uuid[]" : "CAST(:w AS uuid[])") + ", :r, :n)")
                .param("s", body.session()).param("d", body.decision()).param("r", body.reason().trim()).param("n", n);
        if (!all) q = q.param("w", body.students().toArray(UUID[]::new));
        return q.query().singleRow();
    }

    public record ResetLegacy(String session, String confirm) { }

    /** start the old-portal fees import over: deletes only the import's own records, and only on the word RESET */
    @PostMapping("/legacy-fees/reset")
    @PreAuthorize(BURSARY)
    @Transactional
    Map<String, Object> resetLegacyFees(@RequestBody ResetLegacy body) {
        return jdbc.sql("SELECT * FROM finance.reset_legacy_payments((:s)::text, (:c)::text)")
                .param("s", body.session() == null || body.session().isBlank() ? null : body.session())
                .param("c", body.confirm()).query().singleRow();
    }

    /* ── the schedule ── */

    @GetMapping("/sessions/{session}/{year}/schedule")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> schedule(@PathVariable String session, @PathVariable String year) {
        String s = session + "/" + year;
        List<Map<String, Object>> items = jdbc.sql("""
                SELECT f.id, f.item, f.amount, f.level, f.entry_mode, f.faculty_code, fa.name AS faculty_name,
                       f.programme_code, p.name AS programme_name, f.fee_group, g.name AS fee_group_name, f.semester, f.indigene, f.ord, f.spillover, f.kind
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
    /* ── V393: postgraduate fees after V391, read only ── */

    /** the PG students whose confirmed school-fee payments of the session exceed what they owe under the School's lines, with
     *  the references paid; the Bursary decides each case by its own refund process, and nothing is refunded here */
    @GetMapping("/sessions/{session}/{year}/postgraduate/review")
    @PreAuthorize(RECONCILERS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> pgFeeReview(@PathVariable String session, @PathVariable String year) {
        return jdbc.sql("""
                SELECT student_id, admission_no, matric_no, surname, other_names, status, programme_code, programme, level, due, paid, excess, payments::text AS payments
                  FROM finance.pg_fee_review(:s)
                """).param("s", session + "/" + year).query().listOfRows();
    }

    /** the live PG students with no fee line stated for the session, by level and programme */
    @GetMapping("/sessions/{session}/{year}/postgraduate/unstated")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> pgUnstated(@PathVariable String session, @PathVariable String year) {
        return jdbc.sql("SELECT level, programme_code, programme, students FROM finance.pg_unstated(:s)").param("s", session + "/" + year).query().listOfRows();
    }

    /** V451: the live undergraduates with no school fee stated for the session — no line at all, or none for an open
     *  semester — by group of alike students, with what the watch last told the Bursary */
    @GetMapping("/sessions/{session}/{year}/fee-gaps")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> feeGaps(@PathVariable String session, @PathVariable String year) {
        String s = session + "/" + year;
        List<Map<String, Object>> rows = jdbc.sql("""
                SELECT faculty_code, faculty, programme_code, programme, level, entry_mode, indigene, spillover, students, charged_as, stated,
                       array_to_string(missing, ',') AS missing
                  FROM finance.fee_gaps(:s)
                """).param("s", s).query().listOfRows();
        Map<String, Object> out = new java.util.LinkedHashMap<>();
        out.put("session", s);
        out.put("students", rows.stream().mapToLong(r -> ((Number) r.get("students")).longValue()).sum());
        out.put("groups", rows.size());
        out.put("openSemesters", jdbc.sql("SELECT number FROM policy.semester WHERE session = :s AND state = 'OPEN' ORDER BY number")
                .param("s", s).query(Integer.class).list());
        // V461: every semester of the session's calendar, for the sheet the Bursary fills (the first and second where none is dated)
        List<Integer> semesters = jdbc.sql("SELECT number FROM policy.semester WHERE session = :s ORDER BY number").param("s", s).query(Integer.class).list();
        out.put("semesters", semesters.isEmpty() ? List.of(1, 2) : semesters);
        out.put("scheduleLines", jdbc.sql("SELECT count(*) FROM finance.fee_schedule WHERE session = :s AND ended_at IS NULL AND kind = 'FEE'")
                .param("s", s).query(Long.class).single());
        out.put("watch", jdbc.sql("SELECT told_at, told, students, groups, checked_at FROM finance.fee_gap_watch WHERE session = :s")
                .param("s", s).query().listOfRows().stream().findFirst().orElse(null));
        out.put("rows", rows);
        return out;
    }

    /** V461: the Bursary's filled-in gap sheet, added as new lines of the session's schedule — never replacing the structure;
     *  a row with no amount is left out, one the schedule already holds is not added twice */
    @PostMapping("/sessions/{session}/{year}/fee-lines")
    @PreAuthorize(FEE_SETTERS)
    @Transactional
    Map<String, Object> addFeeLines(@PathVariable String session, @PathVariable String year, @Valid @RequestBody FeeRows body) {
        if (body.rows() == null || body.rows().isEmpty()) {
            throw new DomainRuleViolation("FEE_LINES_ROWS", "The sheet has no rows to read.",
                    new DomainRuleViolation.Remedy("Fill the amounts in the sheet downloaded from Students with no school fee stated.", "Bursary"));
        }
        return jdbc.sql("SELECT * FROM finance.add_fee_lines(:s, :j::jsonb)")
                .param("s", session + "/" + year).param("j", json.writeValueAsString(body.rows())).query().singleRow();
    }

    /** V535: what the "fees to state" sheet would add, and the students still with no fee stated afterwards; nothing kept */
    @PostMapping("/sessions/{session}/{year}/fee-lines/preview")
    @PreAuthorize(FEE_SETTERS)
    @Transactional
    Map<String, Object> previewFeeLines(@PathVariable String session, @PathVariable String year, @Valid @RequestBody FeeRows body) {
        if (body.rows() == null || body.rows().isEmpty()) {
            throw new DomainRuleViolation("FEE_LINES_ROWS", "The sheet has no rows to read.",
                    new DomainRuleViolation.Remedy("Fill the amounts in the sheet downloaded from Students with no school fee stated.", "Bursary"));
        }
        return effect(jdbc.sql("SELECT finance.fee_upload_effect(:s, :j::jsonb, 'LINES', NULL)::text")
                .param("s", session + "/" + year).param("j", json.writeValueAsString(body.rows())).query(String.class).single());
    }

    public record FeeSource(@NotBlank @Size(max = 12) String source, @Pattern(regexp = "\\d{4}/\\d{4}") String fromSession, @Size(max = 300) String note) {
    }

    /** V451: the standing "charged as" rules — a faculty charged another's lines while it has none of its own in a session —
     *  and whether each is in force for the session asked about */
    @GetMapping("/fee-sources")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> feeSources(@RequestParam(required = false) String session) {
        String s = session != null && session.matches("\\d{4}/\\d{4}") ? session
                : jdbc.sql("SELECT policy.university_current_session()").query(String.class).optional().orElseGet(Sessions::byDate);
        return jdbc.sql("""
                SELECT r.faculty_code, f.name AS faculty, r.source_faculty_code, sf.name AS source_faculty, r.from_session, r.note,
                       r.set_at, r.set_office, nullif(btrim(coalesce(p.given_names, '') || ' ' || coalesce(p.surname, '')), '') AS set_by_name,
                       (r.from_session IS NULL OR :s >= r.from_session) AS from_reached,
                       finance.fee_source_of(r.faculty_code, :s) IS NOT NULL AS in_force
                  FROM finance.faculty_fee_source r
                  JOIN ref.faculty f ON f.code = r.faculty_code
                  JOIN ref.faculty sf ON sf.code = r.source_faculty_code
                  LEFT JOIN iam.person p ON p.id = r.set_by
                 ORDER BY f.name
                """).param("s", s).query().listOfRows();
    }

    @PutMapping("/fee-sources/{faculty}")
    @PreAuthorize(FEE_SETTERS)
    @Transactional
    Map<String, Object> setFeeSource(@PathVariable String faculty, @Valid @RequestBody FeeSource body) {
        jdbc.sql("SELECT finance.set_faculty_fee_source(:f, :src, :from, :note)")
                .param("f", faculty).param("src", body.source().trim().toUpperCase())
                .param("from", body.fromSession(), Types.VARCHAR).param("note", body.note(), Types.VARCHAR).query().singleRow();
        return Map.of("faculty", faculty, "source", body.source().trim().toUpperCase());
    }

    @org.springframework.web.bind.annotation.DeleteMapping("/fee-sources/{faculty}")
    @PreAuthorize(FEE_SETTERS)
    @Transactional
    Map<String, Object> endFeeSource(@PathVariable String faculty) {
        jdbc.sql("SELECT finance.set_faculty_fee_source(:f, NULL, NULL, NULL)").param("f", faculty).query().singleRow();
        return Map.of("faculty", faculty, "ended", true);
    }

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

    /** V520: an active line of the session that already states this item for the same scope (the scope finance.fee_line_same_scope
     *  compares: item, kind, level, entry mode, faculty, programme, group, semester; a line set by hand has no indigeneship and is not a
     *  spill-over line) — the line added or edited by hand would charge it twice */
    private void refuseDuplicateLine(String session, Item body, UUID except) {
        String kind = body.kind() == null || body.kind().isBlank() ? "FEE" : body.kind();
        java.util.Optional<Map<String, Object>> dup = jdbc.sql("""
                SELECT x.id, x.item, x.amount FROM finance.fee_schedule x
                 WHERE x.session = :s AND x.ended_at IS NULL AND (CAST(:id AS uuid) IS NULL OR x.id <> CAST(:id AS uuid))
                   AND lower(btrim(x.item)) = lower(btrim(:i)) AND x.kind = :k
                   AND x.level IS NOT DISTINCT FROM CAST(:l AS integer) AND x.entry_mode IS NOT DISTINCT FROM CAST(:m AS text)
                   AND x.faculty_code IS NOT DISTINCT FROM CAST(:f AS text) AND x.programme_code IS NOT DISTINCT FROM CAST(:p AS text)
                   AND x.fee_group IS NOT DISTINCT FROM CAST(:g AS text) AND x.semester IS NOT DISTINCT FROM CAST(:sem AS integer)
                   AND x.indigene IS NULL AND NOT x.spillover
                 LIMIT 1
                """).param("s", session).param("id", except, Types.OTHER).param("i", body.item().trim()).param("k", kind)
                .param("l", body.level(), Types.INTEGER).param("m", blank(body.entryMode()), Types.VARCHAR).param("f", blank(body.facultyCode()), Types.VARCHAR)
                .param("p", blank(body.programmeCode()), Types.VARCHAR).param("g", blank(body.feeGroup()), Types.VARCHAR).param("sem", body.semester(), Types.INTEGER)
                .query().listOfRows().stream().findFirst();
        if (dup.isPresent()) {
            throw new DomainRuleViolation("FEE_LINE_DUPLICATE", "The schedule already states " + dup.get().get("item") + " (" + dup.get().get("amount")
                    + ") for the same session, level, entry mode, faculty, programme, group and semester; a second active line would charge it twice.",
                    new DomainRuleViolation.Remedy("Edit that line, or end it first.", "Bursary"));
        }
    }

    /** V520: the fee history of a session — every line added, changed or ended, from the audit trail (who, when, why, and the line
     *  before and after); never rewritten, so an earlier amount is always on record */
    @GetMapping("/sessions/{session}/{year}/schedule/history")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> scheduleHistory(@PathVariable String session, @PathVariable String year) {
        return jdbc.sql("""
                SELECT e.occurred_at AS at, e.action, e.actor_office AS office, e.reason,
                       (SELECT btrim(pe.surname || ', ' || pe.given_names) FROM iam.person pe WHERE pe.id = e.actor_id) AS by_name,
                       coalesce(e.after_state ->> 'item', e.before_state ->> 'item') AS item,
                       (e.before_state ->> 'amount')::numeric AS amount_before, (e.after_state ->> 'amount')::numeric AS amount_after,
                       coalesce(e.after_state ->> 'level', e.before_state ->> 'level') AS level,
                       coalesce(e.after_state ->> 'programme_code', e.before_state ->> 'programme_code') AS programme_code,
                       coalesce(e.after_state ->> 'faculty_code', e.before_state ->> 'faculty_code') AS faculty_code,
                       coalesce(e.after_state ->> 'entry_mode', e.before_state ->> 'entry_mode') AS entry_mode,
                       coalesce(e.after_state ->> 'semester', e.before_state ->> 'semester') AS semester,
                       (e.before_state ->> 'ended_at') IS NULL AND (e.after_state ->> 'ended_at') IS NOT NULL AS ended
                  FROM audit.entries e
                 WHERE e.subject_type = 'finance.fee_schedule'
                   AND coalesce(e.after_state ->> 'session', e.before_state ->> 'session') = :s
                 ORDER BY e.occurred_at DESC
                 LIMIT 1000
                """).param("s", session + "/" + year).query().listOfRows();
    }

    @PostMapping("/sessions/{session}/{year}/schedule")
    @PreAuthorize(FEE_SETTERS)
    @Transactional
    Map<String, Object> addItem(@PathVariable String session, @PathVariable String year, @Valid @RequestBody Item body) {
        String s = session + "/" + year;
        if (body.level() != null && !List.of(100, 200, 300, 400, 500, 600, 700, 800, 900).contains(body.level())) {
            throw new DomainRuleViolation("FEE_LEVEL", "A level is 100 to 900 (700–900 are postgraduate).", new DomainRuleViolation.Remedy("Leave it blank for every level.", "Bursary"));
        }
        if (body.semester() != null && !List.of(1, 2, 3).contains(body.semester())) {
            throw new DomainRuleViolation("FEE_SEMESTER", "A semester is 1 or 2.", new DomainRuleViolation.Remedy("Leave it blank for the whole session.", "Bursary"));
        }
        refuseDuplicateLine(s, body, null);
        jdbc.sql("""
                INSERT INTO finance.fee_schedule (session, item, amount, level, entry_mode, faculty_code, programme_code, fee_group, semester, ord, kind)
                VALUES (:s, :i, :a, :l, :m, :f, :p, :g, :sem, :o, :k)
                """).param("s", s).param("k", body.kind() == null || body.kind().isBlank() ? "FEE" : body.kind()).param("i", body.item().trim()).param("a", body.amount()).param("l", body.level(), Types.INTEGER)
                .param("m", blank(body.entryMode()), Types.VARCHAR).param("f", blank(body.facultyCode()), Types.VARCHAR)
                .param("p", blank(body.programmeCode()), Types.VARCHAR).param("g", blank(body.feeGroup()), Types.VARCHAR)
                .param("sem", body.semester(), Types.INTEGER)
                .param("o", body.ord() == null ? 0 : body.ord()).update();
        return schedule(session, year);
    }

    @PostMapping("/sessions/{session}/{year}/schedule/{id}/end")
    @PreAuthorize(FEE_SETTERS)
    @Transactional
    Map<String, Object> endItem(@PathVariable String session, @PathVariable String year, @PathVariable UUID id) {
        jdbc.sql("UPDATE finance.fee_schedule SET ended_at = now() WHERE id = :id AND session = :s AND ended_at IS NULL")
                .param("id", id).param("s", session + "/" + year).update();
        return schedule(session, year);
    }

    /** clear the whole schedule for a session — ends every standing line, so the Bursar can upload a clean
     *  structure (the same soft-end an upload does before it re-inserts). Charges ignore ended lines at once. */
    @PostMapping("/sessions/{session}/{year}/schedule/clear")
    @PreAuthorize(FEE_SETTERS)
    @Transactional
    Map<String, Object> clearSchedule(@PathVariable String session, @PathVariable String year,
                                      @RequestParam(required = false) @Pattern(regexp = "ALL|FULL_TIME|CCE") String kind) {
        // V380: the CCE lines (entry mode CCE) or the full-time lines (every other) alone, when the Bursar names one; every line otherwise
        String k = kind == null ? "ALL" : kind;
        jdbc.sql("UPDATE finance.fee_schedule SET ended_at = now() WHERE session = :s AND ended_at IS NULL"
                        + ("CCE".equals(k) ? " AND entry_mode = 'CCE'" : "FULL_TIME".equals(k) ? " AND entry_mode IS DISTINCT FROM 'CCE'" : ""))
                .param("s", session + "/" + year).update();
        return schedule(session, year);
    }

    /** V547: what clearing the schedule would end — the lines of each faculty and programme, the faculties left with no fee, the
     *  live students who would owe nothing — applied and undone, nothing kept */
    @PostMapping("/sessions/{session}/{year}/schedule/clear/preview")
    @PreAuthorize(FEE_SETTERS)
    @Transactional
    Map<String, Object> clearPreview(@PathVariable String session, @PathVariable String year,
                                     @RequestParam(required = false) @Pattern(regexp = "ALL|FULL_TIME|CCE") String kind) {
        return effect(jdbc.sql("SELECT finance.fee_upload_effect(:s, '[]'::jsonb, 'CLEAR', :k)::text")
                .param("s", session + "/" + year).param("k", kind == null ? "ALL" : kind).query(String.class).single());
    }

    /** V506: what copying another session's live fee lines into this one would do — each line COPY (this session states none
     *  of the same scope) or KEPT (it does, never overwritten; its amount shown) — the preview the Bursary reads first */
    @GetMapping("/sessions/{session}/{year}/schedule/copy")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> copyPreview(@PathVariable String session, @PathVariable String year,
                                    @RequestParam @Pattern(regexp = "^[0-9]{4}/[0-9]{4}$") String from) {
        return copied(from, session + "/" + year, false);
    }

    public record CopyFees(@NotBlank @Pattern(regexp = "^[0-9]{4}/[0-9]{4}$") String from) { }

    /** V506: another session's live fee lines copied into this one, where this one states none of the same scope; the Bursary
     *  adjusts the amounts afterwards as for any line */
    @PostMapping("/sessions/{session}/{year}/schedule/copy")
    @PreAuthorize(FEE_SETTERS)
    @Transactional
    Map<String, Object> copyFees(@PathVariable String session, @PathVariable String year, @Valid @RequestBody CopyFees body) {
        return copied(body.from(), session + "/" + year, true);
    }

    /** V580: what copying another session's spillover lines alone into this one would do, each line COPY or KEPT as above */
    @GetMapping("/sessions/{session}/{year}/schedule/copy-spillover")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> copySpilloverPreview(@PathVariable String session, @PathVariable String year,
                                             @RequestParam @Pattern(regexp = "^[0-9]{4}/[0-9]{4}$") String from) {
        return copied(from, session + "/" + year, false, true);
    }

    /** V580: another session's spillover lines copied into this one on their own, where this one states none of the same scope */
    @PostMapping("/sessions/{session}/{year}/schedule/copy-spillover")
    @PreAuthorize(FEE_SETTERS)
    @Transactional
    Map<String, Object> copySpillover(@PathVariable String session, @PathVariable String year, @Valid @RequestBody CopyFees body) {
        return copied(body.from(), session + "/" + year, true, true);
    }

    private Map<String, Object> copied(String from, String to, boolean apply) {
        return copied(from, to, apply, false);
    }

    private Map<String, Object> copied(String from, String to, boolean apply, boolean spilloverOnly) {
        List<Map<String, Object>> lines = jdbc.sql(spilloverOnly ? "SELECT * FROM finance.copy_spillover_lines(:f, :t, :a)" : "SELECT * FROM finance.copy_session_fees(:f, :t, :a)")
                .param("f", from).param("t", to).param("a", apply).query().listOfRows();
        Map<String, Object> out = new java.util.LinkedHashMap<>();
        out.put("from", from);
        out.put("to", to);
        out.put("copy", lines.stream().filter(l -> "COPY".equals(l.get("action"))).count());
        out.put("kept", lines.stream().filter(l -> "KEPT".equals(l.get("action"))).count());
        out.put("applied", apply);
        out.put("lines", lines);
        return out;
    }

    /** edit a standing fee line in place — its amount and the filters it carries */
    @PutMapping("/sessions/{session}/{year}/schedule/{id}")
    @PreAuthorize(FEE_SETTERS)
    @Transactional
    Map<String, Object> editItem(@PathVariable String session, @PathVariable String year, @PathVariable UUID id, @Valid @RequestBody Item body) {
        if (body.level() != null && !List.of(100, 200, 300, 400, 500, 600, 700, 800, 900).contains(body.level())) {
            throw new DomainRuleViolation("FEE_LEVEL", "A level is 100 to 900 (700–900 are postgraduate).", new DomainRuleViolation.Remedy("Leave it blank for every level.", "Bursary"));
        }
        if (body.semester() != null && !List.of(1, 2, 3).contains(body.semester())) {
            throw new DomainRuleViolation("FEE_SEMESTER", "A semester is 1 or 2.", new DomainRuleViolation.Remedy("Leave it blank for the whole session.", "Bursary"));
        }
        refuseDuplicateLine(session + "/" + year, body, id);
        int n = jdbc.sql("""
                UPDATE finance.fee_schedule SET item = :i, amount = :a, level = :l, entry_mode = :m, faculty_code = :f,
                       programme_code = :p, fee_group = :g, semester = :sem, ord = :o, kind = coalesce(:k, kind)
                 WHERE id = :id AND session = :s AND ended_at IS NULL
                """).param("id", id).param("k", body.kind() == null || body.kind().isBlank() ? null : body.kind(), Types.VARCHAR).param("s", session + "/" + year)
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

    /* ── the inter-departmental transfer processing fee (Bursary-set) ── */

    @GetMapping("/transfer-fee")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> transferFee() {
        BigDecimal amount = jdbc.sql("SELECT people.transfer_fee()").query(BigDecimal.class).optional().orElse(null);
        Boolean stated = jdbc.sql("SELECT transfer_fee IS NOT NULL FROM finance.fee_setting WHERE id = 1").query(Boolean.class).optional().orElse(false);
        java.util.Map<String, Object> out = new java.util.HashMap<>();
        out.put("amount", amount);   // null until the Bursary sets it (no default)
        out.put("stated", stated);
        return out;
    }

    @PutMapping("/transfer-fee")
    @PreAuthorize(BURSARY)
    @Transactional
    Map<String, Object> setTransferFee(@Valid @RequestBody TransferFee body) {
        jdbc.sql("UPDATE finance.fee_setting SET transfer_fee = :a WHERE id = 1").param("a", body.amount()).update();
        return Map.of("amount", body.amount(), "stated", true);
    }

    /* ── V571: who is charged the spillover fee lines — a level above the programme's final level (V088), or the cohort engine's
          spillover (SP1, SP2 … and the limit reached); the Bursary's choice, with a preview of who would move and what they would owe ── */

    @GetMapping("/spillover-basis")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> spillBasis() {
        Map<String, Object> out = new java.util.LinkedHashMap<>(jdbc.sql("""
                SELECT g.spillover_basis AS basis, g.spillover_basis_set_at AS set_at, helpdesk.person_name(g.spillover_basis_set_by) AS set_by,
                       g.spillover_basis_reason AS reason,
                       g.spill_lines_hold_start AS hold_start, g.spill_hold_set_at AS hold_set_at, helpdesk.person_name(g.spill_hold_set_by) AS hold_set_by
                  FROM finance.fee_setting g WHERE g.id = 1
                """).query().singleRow());
        out.putAll(jdbc.sql("""
                SELECT count(*) FILTER (WHERE by_cohort AND NOT by_level) AS into_spill, count(*) FILTER (WHERE by_level AND NOT by_cohort) AS out_of_spill
                  FROM finance.spill_basis_moves()
                """).query().singleRow());
        out.put("spillLines", jdbc.sql("SELECT count(*) FROM finance.fee_schedule WHERE spillover").query(Long.class).single());
        return out;
    }

    /**
     * what changing the basis would do, for a session (the current one when none is named): each current student whose spillover
     * differs between the two bases, with the session's charges under each — read in one transaction with the basis set for it
     * (moaum.spill_basis), nothing changed. The first 200 by programme and name, or every one for the Excel.
     */
    @GetMapping("/spillover-basis/preview")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> spillBasisPreview(@RequestParam(required = false) String session, @RequestParam(defaultValue = "false") boolean all) {
        String s = session != null && session.matches("\\d{4}/\\d{4}") ? session
                : jdbc.sql("SELECT policy.university_current_session()").query(String.class).optional().orElseGet(ng.edu.moaum.portal.shared.Sessions::byDate);
        List<Map<String, Object>> moves = jdbc.sql("""
                SELECT m.student_id, m.by_level, m.by_cohort, upper(btrim(st.surname)) || coalesce(', ' || nullif(btrim(st.other_names), ''), '') AS name,
                       coalesce(st.matric_no, st.admission_no) AS number, p.name AS programme, f.name AS faculty, st.current_level AS level, ap.spillover_state
                  FROM finance.spill_basis_moves() m
                  JOIN people.student st ON st.id = m.student_id
                  LEFT JOIN ref.programme p ON p.code = st.programme_code
                  LEFT JOIN ref.faculty f ON f.code = p.faculty_code
                  LEFT JOIN people.academic_position ap ON ap.student_id = m.student_id
                 ORDER BY f.name, p.name, name
                """).query().listOfRows();
        Map<Object, Object> byLevel = new java.util.HashMap<>();
        Map<Object, Object> byCohort = new java.util.HashMap<>();
        for (String basis : List.of("LEVEL", "COHORT")) {
            jdbc.sql("SELECT set_config('moaum.spill_basis', :b, true)").param("b", basis).query().singleRow();
            Map<Object, Object> into = "LEVEL".equals(basis) ? byLevel : byCohort;
            jdbc.sql("SELECT ch.student_id, ch.total FROM finance.session_charges(:s) ch WHERE ch.student_id IN (SELECT m.student_id FROM finance.spill_basis_moves() m)")
                    .param("s", s).query().listOfRows().forEach(r -> into.put(r.get("student_id"), r.get("total")));
        }
        jdbc.sql("SELECT set_config('moaum.spill_basis', '', true)").query().singleRow();
        BigDecimal before = BigDecimal.ZERO, after = BigDecimal.ZERO;
        long nothing = 0;
        for (Map<String, Object> m : moves) {
            BigDecimal l = byLevel.get(m.get("student_id")) instanceof BigDecimal v ? v : BigDecimal.ZERO;
            BigDecimal c = byCohort.get(m.get("student_id")) instanceof BigDecimal v ? v : BigDecimal.ZERO;
            m.put("by_level_due", l);
            m.put("by_cohort_due", c);
            before = before.add(l);
            after = after.add(c);
            if (c.signum() == 0) nothing++;
        }
        Map<String, Object> out = new java.util.LinkedHashMap<>();
        out.put("session", s);
        out.put("students", moves.size());
        out.put("intoSpill", moves.stream().filter(m -> Boolean.TRUE.equals(m.get("by_cohort"))).count());
        out.put("outOfSpill", moves.stream().filter(m -> Boolean.TRUE.equals(m.get("by_level"))).count());
        out.put("dueByLevel", before);
        out.put("dueByCohort", after);
        out.put("nothingStatedByCohort", nothing);
        out.put("rows", all ? moves : moves.subList(0, Math.min(200, moves.size())));
        return out;
    }

    /** V576: for the current session and the next, the spillover students with no fee line stated — by the level and by the cohort —
     *  so the Bursary sees, before choosing the basis or uploading the next session's fees, who would be charged nothing */
    @GetMapping("/spillover-basis/readiness")
    @PreAuthorize(READERS)
    @Transactional
    List<Map<String, Object>> spillReadiness() {
        String current = jdbc.sql("SELECT policy.university_current_session()").query(String.class).optional().orElseGet(ng.edu.moaum.portal.shared.Sessions::byDate);
        List<String> sessions = new java.util.ArrayList<>(List.of(current));
        jdbc.sql("SELECT name FROM policy.academic_session WHERE name > :c AND state = 'PLANNED' ORDER BY name LIMIT 1").param("c", current)
                .query(String.class).optional().ifPresent(sessions::add);
        List<Map<String, Object>> out = new java.util.ArrayList<>();
        for (String s : sessions) {
            Map<String, Object> m = new java.util.LinkedHashMap<>();
            m.put("session", s);
            m.put("lines", jdbc.sql("SELECT count(*) FROM finance.fee_schedule WHERE session = :s AND spillover AND ended_at IS NULL").param("s", s).query(Long.class).single());
            // V580: the last earlier session that states spillover lines, and how many of them this one does not state yet
            jdbc.sql("SELECT max(session) FROM finance.fee_schedule WHERE session < :s AND spillover AND ended_at IS NULL").param("s", s).query(String.class).optional()
                    .ifPresent(from -> {
                        m.put("copyFrom", from);
                        m.put("toCopy", jdbc.sql("SELECT count(*) FROM finance.copy_spillover_lines(:f, :s, false) WHERE action = 'COPY'").param("f", from).param("s", s)
                                .query(Long.class).single());
                    });
            jdbc.sql("SELECT basis, students, groups FROM finance.spill_readiness(:s)").param("s", s).query().listOfRows()
                    .forEach(r -> m.put("LEVEL".equals(r.get("basis")) ? "byLevel" : "byCohort", Map.of("students", r.get("students"), "groups", r.get("groups"))));
            out.add(m);
        }
        return out;
    }

    public record SpillBasis(@jakarta.validation.constraints.NotBlank @jakarta.validation.constraints.Pattern(regexp = "LEVEL|COHORT") String basis,
                             @jakarta.validation.constraints.NotBlank @jakarta.validation.constraints.Size(min = 10, max = 2000) String reason) {
    }

    @PutMapping("/spillover-basis")
    @PreAuthorize(BURSARY)
    @Transactional
    Map<String, Object> setSpillBasis(@Valid @RequestBody SpillBasis body) {
        jdbc.sql("SELECT finance.set_spill_basis(:b, :r)").param("b", body.basis()).param("r", body.reason().trim()).query(String.class).single();
        return spillBasis();
    }

    public record SpillHold(@jakarta.validation.constraints.NotNull Boolean hold) {
    }

    /** V585: whether spillover students with no spillover line hold a session's automatic start (the transition readiness's
     *  SPILLOVER_FEE_LINES check is then not met until they are stated); the Bursar's choice, off by default */
    @PutMapping("/spillover-basis/hold-start")
    @PreAuthorize(BURSARY)
    @Transactional
    Map<String, Object> setSpillHold(@Valid @RequestBody SpillHold body) {
        jdbc.sql("SELECT finance.set_spill_hold_start(:h)").param("h", body.hold()).query(Boolean.class).single();
        return spillBasis();
    }

    /* ── V401: the Bursary's rule for a session whose applicant fees are not stated: CARRY the last stated session's forward, or
          REFUSE a fee reference until they are stated ── */

    public record FeePolicy(@jakarta.validation.constraints.NotBlank @jakarta.validation.constraints.Pattern(regexp = "CARRY|REFUSE") String policy) {
    }

    @GetMapping("/applicant-fee-policy")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> applicantFeePolicy() {
        return Map.of("policy", jdbc.sql("SELECT admissions.applicant_fee_policy()").query(String.class).single());
    }

    @PutMapping("/applicant-fee-policy")
    @PreAuthorize(BURSARY)
    @Transactional
    Map<String, Object> setApplicantFeePolicy(@Valid @RequestBody FeePolicy body) {
        jdbc.sql("UPDATE finance.fee_setting SET applicant_fee_unstated = :p WHERE id = 1").param("p", body.policy()).update();
        return Map.of("policy", body.policy());
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
        String s = session == null || session.isBlank() ? jdbc.sql("SELECT policy.university_current_session()").query(String.class).optional().orElseGet(Sessions::byDate) : session;
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
    Map<String, Object> ledger(@RequestParam(required = false) LocalDate from, @RequestParam(required = false) LocalDate to,
                               @RequestParam(defaultValue = "false") boolean all) {
        LocalDate f = from == null ? LocalDate.now().minusDays(30) : from;
        LocalDate t = to == null ? LocalDate.now() : to;
        List<Map<String, Object>> rows = jdbc.sql("SELECT * FROM finance.day_book(:f, :t)").param("f", f).param("t", t).query().listOfRows();
        // V541: the totals of every confirmation, and the newest DAY_BOOK_SHOWN of them for the screen — thirty days of the
        // live-shaped copy are 18,037 rows (4 MB), which the screen took 12 s to draw; the journal's export asks for all
        Map<String, BigDecimal> byChannel = new java.util.LinkedHashMap<>();
        BigDecimal total = BigDecimal.ZERO;
        for (Map<String, Object> r : rows) {
            BigDecimal amount = r.get("amount") instanceof BigDecimal b ? b : new BigDecimal(String.valueOf(r.get("amount")));
            total = total.add(amount);
            byChannel.merge(String.valueOf(r.get("channel")), amount, BigDecimal::add);
        }
        Map<String, Object> out = new java.util.LinkedHashMap<>();
        out.put("from", f);
        out.put("to", t);
        out.put("count", rows.size());
        out.put("total", total);
        out.put("byChannel", byChannel.entrySet().stream().map(e -> Map.of("channel", e.getKey(), "amount", e.getValue())).toList());
        out.put("rows", all || rows.size() <= DAY_BOOK_SHOWN ? rows : rows.subList(0, DAY_BOOK_SHOWN));
        return out;
    }

    /** the confirmations the day book screen draws; the totals and the export cover every one */
    static final int DAY_BOOK_SHOWN = 500;

    /** A well-defined payments query for the Bursary: confirmed student payments, newest first, sliced by
     *  session, faculty, department, programme, level, payment category and channel. Returns the page, the
     *  full-match count and total, and the option lists for the filters. */
    @GetMapping("/payments")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> payments(@RequestParam(required = false) String session, @RequestParam(required = false) String faculty,
            @RequestParam(required = false) String dept, @RequestParam(required = false) String programme,
            @RequestParam(required = false) Integer level, @RequestParam(required = false) String category,
            @RequestParam(required = false) String channel, @RequestParam(required = false) LocalDate from,
            @RequestParam(required = false) LocalDate to, @RequestParam(defaultValue = "500") int limit) {
        List<Map<String, Object>> rows = jdbc.sql("""
                SELECT * FROM finance.payments_query(:session, :faculty, :dept, :programme, :level, :category, :channel, :from, :to, :limit)
                """)
                .param("session", blank(session), Types.VARCHAR).param("faculty", blank(faculty), Types.VARCHAR)
                .param("dept", blank(dept), Types.VARCHAR).param("programme", blank(programme), Types.VARCHAR)
                .param("level", level, Types.INTEGER)
                .param("category", category == null || category.isBlank() ? null : category.trim(), Types.VARCHAR)
                .param("channel", channel == null || channel.isBlank() ? null : channel.trim(), Types.VARCHAR)
                .param("from", from, Types.DATE)
                .param("to", to, Types.DATE).param("limit", limit)
                .query().listOfRows();
        long count = rows.isEmpty() ? 0 : ((Number) rows.getFirst().get("match_count")).longValue();
        Object total = rows.isEmpty() ? BigDecimal.ZERO : rows.getFirst().get("match_total");

        List<Map<String, Object>> breakdown = jdbc.sql("""
                SELECT * FROM finance.payments_breakdown(:session, :faculty, :dept, :programme, :level, :category, :channel, :from, :to)
                """)
                .param("session", blank(session), Types.VARCHAR).param("faculty", blank(faculty), Types.VARCHAR)
                .param("dept", blank(dept), Types.VARCHAR).param("programme", blank(programme), Types.VARCHAR)
                .param("level", level, Types.INTEGER)
                .param("category", category == null || category.isBlank() ? null : category.trim(), Types.VARCHAR)
                .param("channel", channel == null || channel.isBlank() ? null : channel.trim(), Types.VARCHAR)
                .param("from", from, Types.DATE).param("to", to, Types.DATE)
                .query().listOfRows();
        List<Map<String, Object>> byCategory = breakdown.stream().filter(b -> "category".equals(b.get("dim"))).toList();
        List<Map<String, Object>> byFaculty = breakdown.stream().filter(b -> "faculty".equals(b.get("dim"))).toList();

        Map<String, Object> options = new java.util.LinkedHashMap<>();
        // V549: the sessions, channels and categories paid in, from one pass over the confirmed payments — each purpose's category
        // worked out once (some eighty), not once a payment; three passes took about 0.8 s on the live-shaped copy, one about 0.3 s
        List<Map<String, Object>> paidIn = jdbc.sql("""
                WITH c AS MATERIALIZED (SELECT session, channel, coalesce(purpose, '') AS purpose FROM finance.payment_reference
                                         WHERE confirmed_at IS NOT NULL GROUP BY 1, 2, 3)
                SELECT 'session' AS k, session AS v FROM c GROUP BY session
                UNION ALL SELECT 'channel', channel FROM c WHERE channel IS NOT NULL GROUP BY channel
                UNION ALL SELECT 'category', finance.payment_category(purpose) FROM c GROUP BY 2
                """).query().listOfRows();
        java.util.function.Function<String, List<String>> of = k -> paidIn.stream().filter(r -> k.equals(r.get("k"))).map(r -> (String) r.get("v"))
                .filter(java.util.Objects::nonNull).sorted().toList();
        options.put("sessions", of.apply("session").reversed());
        options.put("faculties", jdbc.sql("SELECT code, name FROM ref.faculty ORDER BY name").query().listOfRows());
        options.put("departments", jdbc.sql("SELECT code, name, faculty_code FROM ref.department ORDER BY name").query().listOfRows());
        options.put("programmes", jdbc.sql("SELECT code, name, faculty_code, dept_code FROM ref.programme WHERE NOT archived ORDER BY name").query().listOfRows());
        options.put("categories", of.apply("category"));
        options.put("channels", of.apply("channel"));

        Map<String, Object> out = new java.util.LinkedHashMap<>();
        out.put("rows", rows);
        out.put("count", count);
        out.put("total", total);
        out.put("byCategory", byCategory);
        out.put("byFaculty", byFaculty);
        out.put("options", options);
        return out;
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
