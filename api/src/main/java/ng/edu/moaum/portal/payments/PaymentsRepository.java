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

    List<Map<String, Object>> events(int limit) {
        return jdbc.sql("""
                SELECT e.id, e.gateway, e.source, e.event, e.reference, e.gateway_ref, e.amount, e.status, e.signature_ok, e.outcome, e.received_at,
                       e.resolved_at, e.resolution, p.surname || ', ' || p.given_names AS resolved_by_name
                  FROM finance.gateway_event e LEFT JOIN iam.person p ON p.id = e.resolved_by
                 ORDER BY e.received_at DESC LIMIT :n
                """).param("n", limit).query().listOfRows();
    }

    Map<String, Object> eventTiles() {
        return jdbc.sql("""
                SELECT count(*) FILTER (WHERE received_at::date = current_date) AS today,
                       count(*) FILTER (WHERE outcome = 'SETTLED') AS settled,
                       count(*) FILTER (WHERE outcome IN ('UNKNOWN_REFERENCE','SHORT_PAID','BAD_SIGNATURE','GATEWAY_ERROR') AND resolved_at IS NULL) AS exceptions,
                       count(*) FILTER (WHERE NOT signature_ok) AS bad_signatures,
                       coalesce(sum(amount) FILTER (WHERE outcome = 'SETTLED' AND received_at::date = current_date), 0) AS settled_today
                  FROM finance.gateway_event
                """).query().singleRow();
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

    /* ── Quickteller PayDirect billers (V080): routing by College, and the collections import ── */

    List<Map<String, Object>> paydirectBillers() {
        return jdbc.sql("SELECT scope, biller_code, name, pay_link, active, updated_at FROM finance.paydirect_biller ORDER BY scope").query().listOfRows();
    }

    boolean paydirectActive() {
        return Boolean.TRUE.equals(jdbc.sql("SELECT EXISTS (SELECT 1 FROM finance.paydirect_biller WHERE scope = 'MAIN' AND active)").query(Boolean.class).single());
    }

    Map<String, Object> paydirectBillerFor(UUID student) {
        return jdbc.sql("SELECT scope, biller_code, name, pay_link FROM finance.paydirect_biller_for(:s)").param("s", student).query().singleRow();
    }

    Map<String, Object> paydirectMain() {
        return jdbc.sql("SELECT scope, biller_code, name, pay_link FROM finance.paydirect_biller WHERE scope = 'MAIN'").query().singleRow();
    }

    Map<String, Object> setPaydirectBiller(String scope, String code, String name, String link, boolean active) {
        return jdbc.sql("SELECT scope, biller_code, name, pay_link, active, updated_at FROM finance.set_paydirect_biller(:sc, :c, :n, :l, :a)")
                .param("sc", scope).param("c", code).param("n", name).param("l", link, Types.VARCHAR).param("a", active).query().singleRow();
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
}
