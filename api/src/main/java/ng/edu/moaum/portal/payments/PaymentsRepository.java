package ng.edu.moaum.portal.payments;

import java.math.BigDecimal;
import java.sql.Types;
import java.time.OffsetDateTime;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;

/** The fee references (V021) as a gateway sees them, and the one act a gateway performs: confirming one. */
@Repository
class PaymentsRepository {

    private final JdbcClient jdbc;

    PaymentsRepository(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    record Reference(UUID id, UUID applicationId, UUID accountId, String kind, String reference, BigDecimal amount,
                     OffsetDateTime expiresAt, OffsetDateTime confirmedAt, String email, String applicationNo) {
    }

    Optional<Reference> byReference(String reference) {
        return jdbc.sql("""
                SELECT f.id, f.application_id, a.account_id, f.kind, f.reference, f.amount, f.expires_at, f.confirmed_at, acc.email, a.application_no
                  FROM admissions.fee_reference f
                  JOIN admissions.application a ON a.id = f.application_id
                  JOIN admissions.applicant_account acc ON acc.id = a.account_id
                 WHERE f.reference = upper(btrim(:r))
                """).param("r", reference).query(Reference.class).optional();
    }

    /** V295: whether the application behind an admission checking reference may pay it now — a valid application, Admission
     *  Status Checking open for its session, the fee not yet paid (admissions.status_checking) */
    boolean checkingPayable(UUID applicationId) {
        return jdbc.sql("SELECT coalesce((SELECT k.may_pay FROM admissions.status_checking(:a) k), false)").param("a", applicationId).query(Boolean.class).single();
    }

    String confirm(String reference, String channel, String note) {
        return jdbc.sql("SELECT admissions.confirm_fee(:r, :c, :n)")
                .param("r", reference).param("c", channel).param("n", note, Types.VARCHAR).query(String.class).single();
    }

    /* ── a student's fee reference (V026): the same shape, the Bursary's ledger ── */

    Optional<Reference> studentReference(String reference) {
        return jdbc.sql("""
                SELECT r.id, NULL::uuid AS application_id, r.student_id AS account_id, 'FEES' AS kind, r.reference, r.amount, r.expires_at, r.confirmed_at,
                       reach.email, coalesce(s.matric_no, s.admission_no) AS application_no
                  FROM finance.payment_reference r
                  JOIN people.student s ON s.id = r.student_id
                  LEFT JOIN LATERAL people.student_reach(s.id) reach ON true
                 WHERE r.reference = upper(btrim(:r))
                """).param("r", reference).query(Reference.class).optional();
    }

    /** whether a student's reference is the GST fee (V314: purpose 'GST fee <session>') — paid like any student reference, named and returned to as the GST fee */
    boolean gstReference(String reference) {
        return jdbc.sql("SELECT EXISTS (SELECT 1 FROM finance.payment_reference WHERE reference = upper(btrim(:r)) AND purpose LIKE 'GST fee %')")
                .param("r", reference).query(Boolean.class).single();
    }

    String confirmStudent(String reference, String channel, String note) {
        return jdbc.sql("SELECT finance.confirm_payment(:r, :c, :n)")
                .param("r", reference).param("c", channel).param("n", note, Types.VARCHAR).query(String.class).single();
    }

    /* ── a postgraduate applicant's fee reference (V202): the same shape, a separate confirm ── */

    Optional<Reference> pgReference(String reference) {
        return jdbc.sql("""
                SELECT fr.id, fr.application_id, p.id AS account_id, 'PG_' || fr.kind AS kind, fr.reference, fr.amount,
                       fr.expires_at, fr.confirmed_at, p.email, a.application_no
                  FROM admissions.pg_fee_reference fr
                  JOIN admissions.pg_application a ON a.id = fr.application_id
                  JOIN admissions.pg_applicant p ON p.id = a.applicant_id
                 WHERE upper(fr.reference) = upper(btrim(:r))
                """).param("r", reference).query(Reference.class).optional();
    }

    /** confirms a postgraduate application-fee reference; idempotent (a second call finds it already confirmed) */
    String confirmPg(String reference, String channel) {
        boolean already = Boolean.TRUE.equals(jdbc.sql("SELECT confirmed_at IS NOT NULL FROM admissions.pg_fee_reference WHERE reference = :r")
                .param("r", reference).query(Boolean.class).optional().orElse(false));
        jdbc.sql("SELECT admissions.pg_confirm_fee(:r, :c)").param("r", reference).param("c", channel).query().singleRow();
        return already ? "already confirmed" : "confirmed";
    }

    /* ── a JUPEB candidate's fee reference (V339): the account is the candidate's application, a separate confirm ── */

    Optional<Reference> jupebReference(String reference) {
        return jdbc.sql("""
                SELECT fr.id, fr.application_id, a.id AS account_id, 'JUPEB_' || fr.kind AS kind, fr.reference, fr.amount,
                       fr.expires_at, fr.confirmed_at, a.email, a.application_no
                  FROM jupeb.fee_reference fr
                  JOIN jupeb.application a ON a.id = fr.application_id
                 WHERE upper(fr.reference) = upper(btrim(:r))
                """).param("r", reference).query(Reference.class).optional();
    }

    /** confirms a JUPEB fee reference; idempotent. A school fee may activate the candidate as a JUPEB student (jupeb.confirm_fee) */
    String confirmJupeb(String reference, String channel) {
        return jdbc.sql("SELECT jupeb.confirm_fee(:r, :c)").param("r", reference).param("c", channel).query(String.class).single();
    }

    /* ── V037: the gateway's words kept, the attempts, what stands for a reference ── */

    UUID logEvent(String gateway, String source, String event, String reference, String gatewayRef, BigDecimal amount, String status,
                  boolean signatureOk, String outcome, String payloadJson) {
        return jdbc.sql("SELECT finance.log_gateway_event(:g, :s, :e, :r, :gr, :a, :st, :ok, :o, :p::jsonb)")
                .param("g", gateway).param("s", source).param("e", event, Types.VARCHAR).param("r", reference, Types.VARCHAR).param("gr", gatewayRef, Types.VARCHAR)
                .param("a", amount, Types.NUMERIC).param("st", status, Types.VARCHAR).param("ok", signatureOk).param("o", outcome).param("p", payloadJson, Types.VARCHAR)
                .query(UUID.class).single();
    }

    void attempt(String reference, String gateway, String kind, UUID account) {
        jdbc.sql("INSERT INTO finance.gateway_attempt (reference, gateway, kind, account_id) VALUES (:r, :g, :k, :a)")
                .param("r", reference).param("g", gateway).param("k", kind).param("a", account).update();
    }

    /** a WebPAY attempt: the txn_ref rendered on the payment page for this reference */
    void quicktellerAttempt(String reference, String txnRef, String kind, UUID account) {
        jdbc.sql("INSERT INTO finance.gateway_attempt (reference, gateway, kind, account_id, txn_ref) VALUES (:r, 'quickteller', :k, :a, :t)")
                .param("r", reference).param("k", kind).param("a", account).param("t", txnRef).update();
    }

    /** the txn_refs rendered for a reference so far, oldest first */
    List<String> quicktellerAttempts(String reference) {
        return jdbc.sql("SELECT DISTINCT ON (txn_ref) txn_ref FROM finance.gateway_attempt WHERE reference = :r AND txn_ref IS NOT NULL ORDER BY txn_ref, opened_at")
                .param("r", reference).query(String.class).list().stream()
                .sorted(java.util.Comparator.comparing((String t) -> t.length()).thenComparing(t -> t)).toList();
    }

    /** the fee reference behind a txn_ref WebPAY names */
    Optional<String> referenceOfTxnRef(String txnRef) {
        return jdbc.sql("SELECT reference FROM finance.gateway_attempt WHERE txn_ref = :t ORDER BY opened_at DESC LIMIT 1")
                .param("t", txnRef).query(String.class).optional();
    }

    /**
     * The College a reference is paid under: CHS when the payer's programme is in a
     * faculty of the College of Health Sciences, else MAIN — an applicant's by the
     * programme offered, a student's by the programme on the register, a postgraduate
     * applicant's by the programme applied for.
     */
    String collegeOfReference(String reference) {
        return jdbc.sql("""
                SELECT CASE WHEN f.college_code = 'CHS' THEN 'CHS' ELSE 'MAIN' END
                  FROM (SELECT admissions.programme_code_of(c.programme) AS code
                          FROM admissions.fee_reference fr JOIN admissions.application a ON a.id = fr.application_id JOIN admissions.candidate c ON c.id = a.candidate_id
                         WHERE fr.reference = upper(btrim(:r))
                        UNION ALL
                        SELECT s.programme_code FROM finance.payment_reference pr JOIN people.student s ON s.id = pr.student_id WHERE pr.reference = upper(btrim(:r))
                        UNION ALL
                        SELECT pa.programme_code FROM admissions.pg_fee_reference fr JOIN admissions.pg_application pa ON pa.id = fr.application_id WHERE fr.reference = upper(btrim(:r))
                        UNION ALL
                        SELECT ja.programme_code FROM jupeb.fee_reference jf JOIN jupeb.application ja ON ja.id = jf.application_id WHERE jf.reference = upper(btrim(:r))) x
                  JOIN ref.programme p ON p.code = x.code
                  JOIN ref.faculty f ON f.code = p.faculty_code
                 LIMIT 1
                """).param("r", reference).query(String.class).optional().orElse("MAIN");
    }

    void checked(String reference) {
        jdbc.sql("UPDATE finance.gateway_attempt SET checked_at = now(), checks = checks + 1 WHERE reference = :r").param("r", reference).update();
    }

    /** attempts opened in the last day with nothing confirmed behind them: the hanging payments, oldest first */
    List<Map<String, Object>> hanging() {
        return jdbc.sql("""
                SELECT a.id, a.reference, a.gateway, a.kind, a.opened_at, a.checked_at, a.checks, st.amount, st.expires_at,
                       extract(epoch FROM now() - a.opened_at)::int / 60 AS minutes,
                       coalesce(s.surname || ', ' || s.other_names, c.surname || ', ' || c.other_names) AS payer,
                       coalesce(s.matric_no, s.admission_no, ap.application_no) AS number
                  FROM finance.gateway_attempt a
                  LEFT JOIN LATERAL finance.reference_state(a.reference) st ON true
                  LEFT JOIN finance.payment_reference pr ON pr.reference = a.reference
                  LEFT JOIN people.student s ON s.id = pr.student_id
                  LEFT JOIN admissions.fee_reference fr ON fr.reference = a.reference
                  LEFT JOIN admissions.application ap ON ap.id = fr.application_id
                  LEFT JOIN admissions.candidate c ON c.id = ap.candidate_id
                 WHERE a.opened_at > now() - interval '3 days' AND st.confirmed_at IS NULL
                   AND a.id = (SELECT x.id FROM finance.gateway_attempt x WHERE x.reference = a.reference ORDER BY x.opened_at DESC LIMIT 1)
                 ORDER BY a.opened_at
                """).query().listOfRows();
    }

    /** the events that concern money — Quickteller's reference checks (V299) are listed on their own */
    List<Map<String, Object>> events(int limit) {
        return jdbc.sql("""
                SELECT e.id, e.gateway, e.source, e.event, e.reference, e.gateway_ref, e.amount, e.status, e.signature_ok, e.outcome, e.received_at,
                       e.resolved_at, e.resolution, p.surname || ', ' || p.given_names AS resolved_by_name
                  FROM finance.gateway_event e LEFT JOIN iam.person p ON p.id = e.resolved_by
                 WHERE e.source <> 'VALIDATE'
                 ORDER BY e.received_at DESC LIMIT :n
                """).param("n", limit).query().listOfRows();
    }

    Map<String, Object> eventTiles() {
        return jdbc.sql("""
                SELECT count(*) FILTER (WHERE received_at::date = current_date) AS today,
                       count(*) FILTER (WHERE outcome = 'SETTLED') AS settled,
                       count(*) FILTER (WHERE outcome IN ('UNKNOWN_REFERENCE','SHORT_PAID','BAD_SIGNATURE','GATEWAY_ERROR','REVERSED') AND resolved_at IS NULL) AS exceptions,
                       count(*) FILTER (WHERE NOT signature_ok) AS bad_signatures,
                       coalesce(sum(amount) FILTER (WHERE outcome = 'SETTLED' AND received_at::date = current_date), 0) AS settled_today
                  FROM finance.gateway_event
                 WHERE source <> 'VALIDATE'
                """).query().singleRow();
    }

    /* ── Pay on Quickteller (V299): the biller page, the reference checks and the collections ── */

    record QuicktellerLink(String url, String reference, BigDecimal amount, String scope, String billerCode, String billerName, boolean withAmount) {
    }

    /** the Quickteller page a reference is paid on, when the portal sends its payer there */
    Optional<QuicktellerLink> quicktellerLink(String reference) {
        return jdbc.sql("SELECT url, reference, amount, scope, biller_code, biller_name, with_amount FROM finance.quickteller_link(:r)")
                .param("r", reference == null ? "" : reference).query(QuicktellerLink.class).optional();
    }

    boolean quicktellerRedirectOn() {
        return Boolean.TRUE.equals(jdbc.sql("SELECT finance.quickteller_redirect_on()").query(Boolean.class).single());
    }

    record Customer(boolean valid, String why, String reference, String surname, String otherNames, String number, BigDecimal amount,
                    String description, String scope, String billerCode) {
    }

    /** what Quickteller is told about a reference it asks after */
    Customer paydirectCustomer(String reference) {
        return jdbc.sql("SELECT * FROM finance.paydirect_customer(:r)").param("r", reference == null ? "" : reference).query(Customer.class).single();
    }

    /** Quickteller's reference checks, newest first */
    List<Map<String, Object>> validations(int limit) {
        return jdbc.sql("""
                SELECT e.id, e.reference, e.gateway_ref AS merchant_reference, e.amount, e.outcome, e.received_at, e.payload->>'why' AS why
                  FROM finance.gateway_event e
                 WHERE e.gateway = 'paydirect' AND e.source = 'VALIDATE'
                 ORDER BY e.received_at DESC LIMIT :n
                """).param("n", limit).query().listOfRows();
    }

    List<Map<String, Object>> paydirectBillers() {
        return jdbc.sql("SELECT scope, biller_code, name, pay_link, active, redirect, with_amount, updated_at FROM finance.paydirect_biller ORDER BY scope")
                .query().listOfRows();
    }

    Map<String, Object> setPaydirectBiller(String scope, String code, String name, String link, boolean active, boolean redirect, boolean withAmount) {
        return jdbc.sql("""
                SELECT scope, biller_code, name, pay_link, active, redirect, with_amount, updated_at
                  FROM finance.set_paydirect_biller(:sc, :c, :n, :l, :a, :re, :wa)
                """).param("sc", scope).param("c", code).param("n", name).param("l", link, Types.VARCHAR).param("a", active)
                .param("re", redirect).param("wa", withAmount).query().singleRow();
    }

    Map<String, Object> importPaydirect(String rowsJson) {
        return jdbc.sql("SELECT * FROM finance.import_paydirect(:j::jsonb)").param("j", rowsJson).query().singleRow();
    }

    List<Map<String, Object>> paydirectCollections(int limit) {
        return jdbc.sql("""
                SELECT biller_code, prn, amount, paid_at, channel, rrn, payer, state, reference, why, imported_at
                  FROM finance.paydirect_collection ORDER BY imported_at DESC LIMIT :n
                """).param("n", limit).query().listOfRows();
    }

    void resolve(UUID event, String resolution) {
        jdbc.sql("SELECT finance.resolve_gateway_event(:e, :r)").param("e", event).param("r", resolution).query().singleRow();
    }

    Optional<UUID> studentByNumber(String number) {
        return jdbc.sql("SELECT id FROM people.student WHERE upper(matric_no) = upper(:n) OR upper(admission_no) = upper(:n) LIMIT 1")
                .param("n", number).query(UUID.class).optional();
    }

    String testReference(UUID student, String session, BigDecimal amount) {
        return jdbc.sql("SELECT finance.new_purpose_reference(:s, :n, :a, 'Gateway test by the Bursary')").param("s", student).param("n", session).param("a", amount)
                .query(String.class).single();
    }

    String currentSession() {
        return jdbc.sql("SELECT name FROM policy.academic_session WHERE state = 'CURRENT'").query(String.class).optional().orElse("2026/2027");
    }

    /* ── gateway credentials (V039): set encrypted, read only into the process, config never carries the secret ── */

    String gatewaySecret(String gateway, String key) {
        return jdbc.sql("SELECT finance.gateway_secret(:g, :k)").param("g", gateway).param("k", key).query(String.class).optional().orElse(null);
    }

    String gatewayHash(String gateway, String key) {
        return jdbc.sql("SELECT finance.gateway_hash(:g, :k)").param("g", gateway).param("k", key).query(String.class).optional().orElse(null);
    }

    List<Map<String, Object>> gatewayConfig() {
        return jdbc.sql("SELECT * FROM finance.gateway_config()").query().listOfRows();
    }

    void setGatewaySecret(String gateway, String secret, String hash, String mode, String last4, String key) {
        jdbc.sql("SELECT finance.set_gateway_secret(:g, :s, :h, :m, :l, :k)")
                .param("g", gateway).param("s", secret).param("h", hash, Types.VARCHAR).param("m", mode).param("l", last4).param("k", key).query().singleRow();
    }

    void clearGatewaySecret(String gateway) {
        jdbc.sql("SELECT finance.clear_gateway_secret(:g)").param("g", gateway).query().singleRow();
    }
}
