package ng.edu.moaum.portal.finance;

import java.math.BigDecimal;
import java.sql.Types;
import java.time.LocalDate;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
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

/**
 * V561: old-portal payments the bank may have charged twice, and a payment the bank never received. Old Fees History lists the
 * records of one student, session, item, day and amount under two or more of the old portal's payment numbers; a Bursary officer
 * records what the bank statement shows — every payment received, or not all — and a payment that never arrived is withdrawn on
 * evidence, raised by one Bursary officer and approved by another (PNR/YYYY/NNNNNN). The database holds the office, the two people
 * and every refusal; the screen only asks.
 */
@RestController
@RequestMapping("/api/v1/finance")
class DoubleChargeController {

    private static final String READERS = "hasAnyAuthority('OFFICE_bursar','OFFICE_studentaccounts','OFFICE_registrar','OFFICE_dregistrar','OFFICE_academic','OFFICE_audit','OFFICE_deputyaudit','OFFICE_ict','OFFICE_admin','OFFICE_super','OFFICE_vc','OFFICE_dvc')";
    private static final String BURSARY = "hasAnyAuthority('OFFICE_bursar','OFFICE_super')";

    private final JdbcClient jdbc;
    private final tools.jackson.databind.ObjectMapper json;

    DoubleChargeController(JdbcClient jdbc, tools.jackson.databind.ObjectMapper json) {
        this.jdbc = jdbc;
        this.json = json;
    }

    private Map<String, Object> read(String text) {
        return json.readValue(text, new tools.jackson.core.type.TypeReference<Map<String, Object>>() { });
    }

    /** the session asked for, or the current one; "all" for every session */
    private String sessionOf(String session) {
        if (session != null && session.equalsIgnoreCase("all")) return null;
        return session != null && session.matches("^[0-9]{4}/[0-9]{4}$") ? session
                : jdbc.sql("SELECT policy.university_current_session()").query(String.class).single();
    }

    /** the possible double charges of a session (every session with ?session=all): the counts and every group, those not yet
     *  checked first, then by name */
    @GetMapping("/legacy-fees/double-charges")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> list(@RequestParam(required = false) String session) {
        String ses = sessionOf(session);
        String text = jdbc.sql("""
                WITH d AS MATERIALIZED (SELECT * FROM finance.possible_double_charges(:s))
                SELECT json_build_object(
                    'session', coalesce(:s, 'all'),
                    'sessions', (SELECT coalesce(json_agg(t.session ORDER BY t.session DESC), '[]'::json)
                                   FROM (SELECT DISTINCT r.session FROM finance.payment_reference r
                                          WHERE r.channel = 'Legacy' AND r.confirmed_at IS NOT NULL AND r.session ~ '^[0-9]{4}/[0-9]{4}$') t),
                    'count', (SELECT count(*) FROM d),
                    'unchecked', (SELECT count(*) FROM d WHERE verdict IS NULL),
                    'received', (SELECT count(*) FROM d WHERE verdict = 'RECEIVED'),
                    'notReceived', (SELECT count(*) FROM d WHERE verdict = 'NOT_RECEIVED'),
                    'waiting', (SELECT count(*) FROM d WHERE open_requests > 0),
                    'atStake', (SELECT coalesce(sum(amount * (payments - 1)), 0) FROM d WHERE verdict IS NULL),
                    'rows', (SELECT coalesce(json_agg(r ORDER BY (r.verdict IS NULL) DESC, r.name, r.paid_on), '[]'::json) FROM (
                        SELECT student_id, number, name, programme_code, session, purpose, paid_on::text AS paid_on, amount, payments, refs, payrefs,
                               check_id, verdict, evidence, checked_by, checked_at::text AS checked_at, open_requests
                          FROM d) r))::text
                """).param("s", ses, Types.VARCHAR).query(String.class).single();
        return read(text);
    }

    public record Check(@NotNull UUID studentId, @NotBlank @Pattern(regexp = "^[0-9]{4}/[0-9]{4}$") String session, @NotBlank @Size(max = 200) String purpose,
                        @NotNull LocalDate paidOn, @NotNull BigDecimal amount, @NotBlank @Pattern(regexp = "RECEIVED|NOT_RECEIVED") String verdict,
                        @NotBlank @Size(min = 5, max = 500) String evidence, @Size(max = 500) String note, List<@Size(max = 120) String> notReceived) { }

    /** what the bank shows for a possible double charge: every payment received, or not all — naming those that did not arrive, each
     *  then raised for withdrawal on the same evidence */
    @PostMapping("/legacy-fees/double-charges/check")
    @PreAuthorize(BURSARY)
    @Transactional
    Map<String, Object> check(@Valid @RequestBody Check body) {
        String[] list = body.notReceived() == null ? new String[0] : body.notReceived().toArray(String[]::new);
        UUID id = jdbc.sql("SELECT finance.check_double_charge(:st, :s, :p, :d, :a, :v, :e, :n, CAST(:l AS text[]))")
                .param("st", body.studentId()).param("s", body.session()).param("p", body.purpose()).param("d", body.paidOn())
                .param("a", body.amount()).param("v", body.verdict()).param("e", body.evidence().trim()).param("n", body.note(), Types.VARCHAR)
                .param("l", list, Types.ARRAY).query(UUID.class).single();
        List<String> raised = jdbc.sql("SELECT request_ref FROM finance.payment_not_received WHERE check_id = :c AND state = 'PROPOSED' ORDER BY request_ref")
                .param("c", id).query(String.class).list();
        return Map.of("id", id, "verdict", body.verdict(), "raised", raised);
    }

    /** the withdrawals of payments the bank never received — waiting first, then the latest — with whether the reader raised each */
    @GetMapping("/payments-not-received")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> notReceived(@RequestParam(required = false) String state) {
        String st = state == null || state.isBlank() ? null : state.trim().toUpperCase();
        if (st != null && !st.matches("PROPOSED|APPROVED|REJECTED|CANCELLED")) st = null;
        String text = jdbc.sql("""
                SELECT json_build_object(
                    'counts', (SELECT coalesce(json_object_agg(t.state, t.n), '{}'::json) FROM (SELECT state, count(*) AS n FROM finance.payment_not_received GROUP BY state) t),
                    'withdrawn', (SELECT coalesce(sum(amount), 0) FROM finance.payment_not_received WHERE state = 'APPROVED'),
                    'rows', (SELECT coalesce(json_agg(r), '[]'::json) FROM (
                        SELECT w.request_ref, w.reference, w.kept_reference, w.student_id, coalesce(s.matric_no, s.admission_no) AS number,
                               s.surname || ', ' || s.other_names AS name, w.session, w.purpose, w.amount, w.paid_on::text AS paid_on, w.payref, w.evidence, w.reason,
                               w.state, helpdesk.person_name(w.raised_by) AS raised_by, w.raised_at::text AS raised_at,
                               w.raised_by = nullif(current_setting('moaum.actor_id', true), '')::uuid AS mine,
                               helpdesk.person_name(w.decided_by) AS decided_by, w.decided_at::text AS decided_at, w.decision_note, w.check_id IS NOT NULL AS from_check
                          FROM finance.payment_not_received w
                          JOIN people.student s ON s.id = w.student_id
                         WHERE (:st::text IS NULL OR w.state = :st)
                         ORDER BY (w.state = 'PROPOSED') DESC, w.raised_at DESC
                         LIMIT 500) r))::text
                """).param("st", st, Types.VARCHAR).query(String.class).single();
        return read(text);
    }

    public record Raise(@NotBlank @Size(max = 120) String reference, @NotBlank @Size(min = 5, max = 500) String evidence,
                        @NotBlank @Size(min = 10, max = 500) String reason) { }

    /** an old-portal payment record the bank shows never arrived, raised for withdrawal; another Bursary officer approves it */
    @PostMapping("/payments-not-received")
    @PreAuthorize(BURSARY)
    @Transactional
    Map<String, Object> raise(@Valid @RequestBody Raise body) {
        String ref = jdbc.sql("SELECT finance.propose_not_received(:r, :e, :w, NULL, NULL)")
                .param("r", body.reference().trim()).param("e", body.evidence().trim()).param("w", body.reason().trim()).query(String.class).single();
        return Map.of("requestRef", ref, "state", "PROPOSED");
    }

    public record Decide(@NotNull Boolean approve, @Size(max = 500) String note) { }

    @PostMapping("/payments-not-received/{year}/{seq}/decide")
    @PreAuthorize(BURSARY)
    @Transactional
    Map<String, Object> decide(@PathVariable String year, @PathVariable String seq, @Valid @RequestBody Decide body) {
        String ref = "PNR/" + year + "/" + seq;
        String state = jdbc.sql("SELECT finance.decide_not_received(:r, :a, :n)").param("r", ref).param("a", body.approve())
                .param("n", body.note(), Types.VARCHAR).query(String.class).single();
        return Map.of("requestRef", ref, "state", state);
    }

    @PostMapping("/payments-not-received/{year}/{seq}/cancel")
    @PreAuthorize(BURSARY)
    @Transactional
    Map<String, Object> cancel(@PathVariable String year, @PathVariable String seq) {
        String ref = "PNR/" + year + "/" + seq;
        String state = jdbc.sql("SELECT finance.cancel_not_received(:r)").param("r", ref).query(String.class).single();
        return Map.of("requestRef", ref, "state", state);
    }

    // ── V684: the bank's list of payments received, set against every possible double charge of the days it covers ───────────

    /** one payment number on the bank's or the gateway's list, with the amount the list shows where it shows one */
    public record BankNumber(@Size(max = 80) String n, @Size(max = 40) String a) { }

    public record BankList(@Pattern(regexp = "^([0-9]{4}/[0-9]{4}|all)?$") String session, @NotNull LocalDate from, @NotNull LocalDate to,
                           @NotNull @Size(min = 1, max = 300_000) List<BankNumber> numbers, @Size(max = 500) String evidence, @Size(max = 500) String note,
                           @Size(max = 200) String fileName, Integer rowsRead) { }

    private String numbersJson(BankList body) {
        return json.writeValueAsString(body.numbers());
    }

    /** what recording the list would do: each possible double charge of the days it covers, judged — nothing written */
    @PostMapping("/legacy-fees/double-charges/bank-list/preview")
    @PreAuthorize(BURSARY)
    @Transactional(readOnly = true)
    Map<String, Object> bankListPreview(@Valid @RequestBody BankList body) {
        String text = jdbc.sql("""
                WITH m AS MATERIALIZED (SELECT * FROM finance.bank_list_preview(:s, :f, :t, CAST(:j AS jsonb)))
                SELECT json_build_object(
                    'session', coalesce(:s, 'all'),
                    'numbers', (SELECT count(DISTINCT n) FROM finance.bank_list_numbers(CAST(:j AS jsonb))),
                    'counts', (SELECT coalesce(json_object_agg(o.outcome, o.n), '{}'::json) FROM (SELECT outcome, count(*) AS n FROM m GROUP BY outcome) o),
                    'toWithdraw', (SELECT coalesce(sum(cardinality(missing)), 0) FROM m WHERE outcome = 'NOT_RECEIVED'),
                    'toWithdrawAmount', (SELECT coalesce(sum(amount * cardinality(missing)), 0) FROM m WHERE outcome = 'NOT_RECEIVED'),
                    'rows', (SELECT coalesce(json_agg(r ORDER BY r.ord, r.name, r.paid_on), '[]'::json) FROM (
                        SELECT student_id, number, name, session, purpose, paid_on::text AS paid_on, amount, payments, refs, payrefs, outcome, found, missing,
                               array_position(ARRAY['NOT_RECEIVED', 'RECEIVED', 'AMOUNT_SHORT', 'NONE_FOUND', 'NO_NUMBER', 'CHECKED'], outcome) AS ord
                          FROM m WHERE outcome NOT IN ('OUTSIDE_PERIOD', 'CHECKED')) r))::text
                """).param("s", sessionOf(body.session()), Types.VARCHAR).param("f", body.from()).param("t", body.to())
                .param("j", numbersJson(body)).query(String.class).single();
        return read(text);
    }

    /** the list recorded (BLC/YYYY/NNNNNN): every payment received, or not all — the records not on it raised for withdrawal for
     *  another Bursary officer to approve; the rest left for a check by hand */
    @PostMapping("/legacy-fees/double-charges/bank-list")
    @PreAuthorize(BURSARY)
    @Transactional
    Map<String, Object> bankListRecord(@Valid @RequestBody BankList body) {
        String ref = jdbc.sql("SELECT finance.bank_list_apply(:s, :f, :t, CAST(:j AS jsonb), :e, :n, :fn, :rr)")
                .param("s", sessionOf(body.session()), Types.VARCHAR).param("f", body.from()).param("t", body.to()).param("j", numbersJson(body))
                .param("e", body.evidence() == null ? "" : body.evidence().trim()).param("n", body.note(), Types.VARCHAR)
                .param("fn", body.fileName(), Types.VARCHAR).param("rr", body.rowsRead(), Types.INTEGER).query(String.class).single();
        String outcomes = jdbc.sql("SELECT outcomes::text FROM finance.bank_list_check WHERE list_ref = :r").param("r", ref).query(String.class).single();
        return Map.of("listRef", ref, "outcomes", read(outcomes));
    }

    /** the bank lists recorded, the latest first, with what each judged and where its withdrawals stand */
    @GetMapping("/legacy-fees/bank-lists")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> bankLists() {
        String text = jdbc.sql("""
                SELECT json_build_object('rows', (SELECT coalesce(json_agg(r ORDER BY r.at DESC), '[]'::json) FROM (
                    SELECT l.list_ref, l.session, l.covers_from::text AS covers_from, l.covers_to::text AS covers_to, l.file_name, l.rows_read, l.numbers_read,
                           l.with_amounts, l.evidence, l.note, l.outcomes, helpdesk.person_name(l.checked_by) AS checked_by, l.checked_at::text AS checked_at,
                           l.checked_at AS at, l.checked_by = nullif(current_setting('moaum.actor_id', true), '')::uuid AS mine,
                           (SELECT coalesce(json_object_agg(t.state, t.n), '{}'::json) FROM (
                               SELECT w.state, count(*) AS n FROM finance.payment_not_received w
                                WHERE w.request_ref IN (SELECT unnest(g.raised) FROM finance.bank_list_group g WHERE g.list_id = l.id)
                                GROUP BY w.state) t) AS withdrawals
                      FROM finance.bank_list_check l
                     ORDER BY l.checked_at DESC
                     LIMIT 200) r))::text
                """).query(String.class).single();
        return read(text);
    }

    /** one list: each possible double charge it judged, what the list showed and the withdrawals it raised */
    @GetMapping("/legacy-fees/bank-lists/{year}/{seq}")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> bankList(@PathVariable String year, @PathVariable String seq) {
        String ref = "BLC/" + year + "/" + seq;
        String text = jdbc.sql("""
                SELECT json_build_object('listRef', l.list_ref, 'rows', (SELECT coalesce(json_agg(r ORDER BY r.ord, r.name, r.paid_on), '[]'::json) FROM (
                    SELECT g.student_id, coalesce(s.matric_no, s.admission_no) AS number, s.surname || ', ' || s.other_names AS name, g.session, g.purpose,
                           g.paid_on::text AS paid_on, g.amount, g.refs, g.payrefs, g.outcome, g.found, g.missing, g.refusal,
                           array_position(ARRAY['NOT_RECEIVED', 'RECEIVED', 'REFUSED', 'AMOUNT_SHORT', 'NONE_FOUND', 'NO_NUMBER', 'CHECKED'], g.outcome) AS ord,
                           (SELECT coalesce(json_agg(json_build_object('requestRef', w.request_ref, 'reference', w.reference, 'state', w.state) ORDER BY w.request_ref), '[]'::json)
                              FROM finance.payment_not_received w WHERE w.request_ref = ANY (g.raised)) AS withdrawals
                      FROM finance.bank_list_group g
                      LEFT JOIN people.student s ON s.id = g.student_id
                     WHERE g.list_id = l.id) r))::text
                  FROM finance.bank_list_check l WHERE l.list_ref = :r
                """).param("r", ref).query(String.class).optional()
                .orElseThrow(() -> new org.springframework.web.server.ResponseStatusException(org.springframework.http.HttpStatus.NOT_FOUND, "No bank list " + ref));
        return read(text);
    }

    public record BankListDecision(@NotBlank @Pattern(regexp = "APPROVE|REJECT|CANCEL") String action, @Size(max = 500) String note) { }

    /** every withdrawal the list raised that still waits: approved or rejected by another Bursary officer, or cancelled by the one
     *  who recorded the list — each through the withdrawal's own decision */
    @PostMapping("/legacy-fees/bank-lists/{year}/{seq}/decide")
    @PreAuthorize(BURSARY)
    @Transactional
    Map<String, Object> bankListDecide(@PathVariable String year, @PathVariable String seq, @Valid @RequestBody BankListDecision body) {
        String ref = "BLC/" + year + "/" + seq;
        return jdbc.sql("SELECT done, refused, refusals FROM finance.decide_bank_list(:r, :a, :n)")
                .param("r", ref).param("a", body.action()).param("n", body.note(), Types.VARCHAR)
                .query((rs, i) -> Map.<String, Object>of("listRef", ref, "action", body.action(), "done", rs.getInt("done"), "refused", rs.getInt("refused"),
                        "refusals", List.of((String[]) rs.getArray("refusals").getArray())))
                .single();
    }
}
