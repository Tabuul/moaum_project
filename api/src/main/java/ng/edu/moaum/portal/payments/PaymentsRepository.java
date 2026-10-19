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
import ng.edu.moaum.portal.shared.Sessions;

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

    /* ── V474: each notified PAYDirect payment recorded before it is settled ── */

    UUID paydirectReceive(String logId, boolean reversal, String reference, BigDecimal amount, String paymentJson) {
        return jdbc.sql("SELECT finance.paydirect_receive(:l, :v, :r, :a, :p::jsonb)")
                .param("l", logId, Types.VARCHAR).param("v", reversal).param("r", reference, Types.VARCHAR).param("a", amount, Types.NUMERIC)
                .param("p", paymentJson == null ? "{}" : paymentJson).query(UUID.class).single();
    }

    /** the payment Interswitch reported, taken for settling; empty when another settler holds it */
    Optional<String> paydirectClaim(UUID id) {
        return jdbc.sql("SELECT finance.paydirect_claim(:i)::text").param("i", id).query(String.class).optional().filter(s -> s != null && !s.isBlank());
    }

    void paydirectDone(UUID id, boolean settled, String outcome, String error) {
        jdbc.sql("SELECT finance.paydirect_done(:i, :s, :o, :e)").param("i", id).param("s", settled)
                .param("o", outcome, Types.VARCHAR).param("e", error, Types.VARCHAR).query().listOfRows();
    }

    List<UUID> paydirectOpen(int quietSeconds, int limit) {
        return jdbc.sql("SELECT * FROM finance.paydirect_open(make_interval(secs => :q), :n)").param("q", quietSeconds).param("n", limit).query(UUID.class).list();
    }

    /** the notifications' standing for the Bursary's desk: how many wait to be settled, failed, and the oldest waiting */
    Map<String, Object> paydirectInboxStatus() {
        return jdbc.sql("""
                SELECT count(*) FILTER (WHERE state = 'RECEIVED') AS waiting, count(*) FILTER (WHERE state = 'FAILED') AS failed,
                       count(*) FILTER (WHERE state = 'SETTLED' AND received_at > now() - interval '1 day') AS settled_today,
                       min(received_at) FILTER (WHERE state <> 'SETTLED') AS oldest_open,
                       (SELECT last_error FROM finance.paydirect_inbox WHERE state = 'FAILED' ORDER BY last_received_at DESC LIMIT 1) AS last_error
                  FROM finance.paydirect_inbox
                """).query().singleRow();
    }

    UUID logEvent(String gateway, String source, String event, String reference, String gatewayRef, BigDecimal amount, String status,
                  boolean signatureOk, String outcome, String payloadJson) {
        return jdbc.sql("SELECT finance.log_gateway_event(:g, :s, :e, :r, :gr, :a, :st, :ok, :o, :p::jsonb)")
                .param("g", gateway).param("s", source).param("e", event, Types.VARCHAR).param("r", reference, Types.VARCHAR).param("gr", gatewayRef, Types.VARCHAR)
                .param("a", amount, Types.NUMERIC).param("st", status, Types.VARCHAR).param("ok", signatureOk).param("o", outcome).param("p", payloadJson, Types.VARCHAR)
                .query(UUID.class).single();
    }

    /** V417: a stored secret shown to the person acting, with their reason, as a row the audit spine carries */
    UUID noteSecretView(String gateway, String what, String reason) {
        return jdbc.sql("SELECT finance.note_secret_view(:g, :w, :r)").param("g", gateway).param("w", what).param("r", reason).query(UUID.class).single();
    }

    /** V413: true when the sweep's answer repeated the open row's for the reference and was counted on it */
    boolean collapseSweepRepeat(String gateway, String reference, String status, String payloadJson) {
        return Boolean.TRUE.equals(jdbc.sql("SELECT finance.collapse_sweep_repeat(:g, :r, :st, :p::jsonb)")
                .param("g", gateway).param("r", reference).param("st", status, Types.VARCHAR).param("p", payloadJson, Types.VARCHAR).query(Boolean.class).single());
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

    /** attempts opened in the last three days with nothing confirmed behind them: the hanging payments, oldest first — every one, as
     *  the sweep asks after them */
    List<Map<String, Object>> hanging() {
        return jdbc.sql(HANGING.formatted("")).query().listOfRows();
    }

    /** V568: the hanging payments the desk shows — without the checkouts nobody went on to pay (finance.abandoned_checkouts) */
    List<Map<String, Object>> deskHanging() {
        return jdbc.sql("WITH ab AS MATERIALIZED (SELECT b.reference FROM finance.abandoned_checkouts(now(), 14) b) "
                + HANGING.formatted("AND NOT EXISTS (SELECT 1 FROM ab WHERE ab.reference = a.reference)")).query().listOfRows();
    }

    private static final String HANGING = """
                SELECT a.id, a.reference, a.gateway, a.kind, a.opened_at, a.checked_at, a.checks, st.amount, st.expires_at,
                       extract(epoch FROM now() - a.opened_at)::int / 60 AS minutes,
                       coalesce(s.surname || ', ' || s.other_names, c.surname || ', ' || c.other_names) AS payer,
                       coalesce(s.matric_no, s.admission_no, ap.application_no) AS number,
                       cl.payment_log_id AS receipt_log_id, cl.paid_on::text AS receipt_paid_on, cl.amount AS receipt_amount, cl.channel AS receipt_channel
                  FROM finance.gateway_attempt a
                  LEFT JOIN LATERAL finance.reference_state(a.reference) st ON true
                  LEFT JOIN finance.payment_reference pr ON pr.reference = a.reference
                  LEFT JOIN people.student s ON s.id = pr.student_id
                  LEFT JOIN admissions.fee_reference fr ON fr.reference = a.reference
                  LEFT JOIN admissions.application ap ON ap.id = fr.application_id
                  LEFT JOIN admissions.candidate c ON c.id = ap.candidate_id
                  LEFT JOIN finance.paydirect_claim cl ON cl.reference = a.reference
                 WHERE a.opened_at > now() - interval '3 days' AND st.confirmed_at IS NULL
                   AND a.id = (SELECT x.id FROM finance.gateway_attempt x WHERE x.reference = a.reference ORDER BY x.opened_at DESC LIMIT 1)
                   %s
                 ORDER BY a.opened_at
                """;

    /** V568: the checkouts of the last fortnight nobody went on to pay, counted by why */
    Map<String, Object> abandonedCount() {
        return jdbc.sql("""
                SELECT count(*) AS total, count(*) FILTER (WHERE rule = 'NEVER_ASKED') AS never_asked,
                       count(*) FILTER (WHERE rule = 'NOT_PAID') AS not_paid, count(*) FILTER (WHERE rule = 'TOLD_NO_ANSWER') AS told_no_answer
                  FROM finance.abandoned_checkouts(now(), 14)
                """).query().singleRow();
    }

    /** V568: who the desk would tell now, counted by case */
    Map<String, Object> tellable() {
        return jdbc.sql("""
                SELECT count(*) FILTER (WHERE case_code = 'SHORT_PAID') AS short_paid, count(*) FILTER (WHERE case_code = 'REVERSED') AS reversed,
                       count(*) FILTER (WHERE case_code = 'HANGING') AS hanging, count(*) AS total
                  FROM finance.payers_to_tell()
                """).query().singleRow();
    }

    /** V568: the payers of one case (or every case) told; the answer as the database counts it */
    String tellPayers(String caseCode) {
        return jdbc.sql("SELECT finance.tell_payers(:c::text)::text").param("c", caseCode, Types.VARCHAR).query(String.class).single();
    }

    /** V568: the desk's clocks */
    Map<String, Object> hangingSetting() {
        return jdbc.sql("""
                SELECT h.abandon_hours, h.tell_after_hours, h.set_at, h.set_office, p.surname || ', ' || p.given_names AS set_by_name
                  FROM finance.hanging_setting h LEFT JOIN iam.person p ON p.id = h.set_by WHERE h.id
                """).query().singleRow();
    }

    void setHangingSetting(int abandonHours, int tellAfterHours) {
        jdbc.sql("SELECT finance.set_hanging_setting(:a, :t)").param("a", abandonHours).param("t", tellAfterHours).query().singleRow();
    }

    /** the payments settled with no one's hand in the last three days (the window "Hanging now" counts): a Pay on Quickteller payment
     *  by Interswitch's own notification (the portal cannot ask about one, so every such payment hung until it came), a card checkout
     *  by the sweep, or on a request to the gateway — each reference once. A payment confirmed by the collections report or a bank
     *  credit is a person's act and is not counted. */
    Map<String, Object> resolvedWithoutPerson() {
        return jdbc.sql("""
                SELECT count(DISTINCT e.reference) FILTER (WHERE e.gateway = 'paydirect' AND e.source = 'WEBHOOK') AS by_notification,
                       count(DISTINCT e.reference) FILTER (WHERE e.source = 'SWEEP') AS by_sweep,
                       count(DISTINCT e.reference) FILTER (WHERE e.source = 'VERIFY') AS on_request,
                       count(DISTINCT e.reference) AS total
                  FROM finance.gateway_event e
                 WHERE e.outcome = 'SETTLED' AND e.reference IS NOT NULL AND e.received_at > now() - interval '3 days'
                   AND ((e.gateway = 'paydirect' AND e.source = 'WEBHOOK') OR e.source IN ('SWEEP', 'VERIFY'))
                """).query().singleRow();
    }

    /* ── the hanging desk's figures, each with the transactions behind it and who paid ── */

    /** the transactions behind the figure of one tile: what hangs now, what settled with no one's hand, what needs a person */
    private static final Map<String, String> TILE_ROWS = Map.of(
            // a checkout opened in the last three days and nothing confirmed (the latest checkout of a reference); V568: not one nobody
            // went on to pay
            "hanging", """
                WITH ab AS MATERIALIZED (SELECT b.reference FROM finance.abandoned_checkouts(now(), 14) b)
                SELECT a.reference, a.opened_at AS at, a.gateway, 'HANGING'::text AS how,
                       CASE WHEN a.gateway = 'paydirect' THEN 'Opened on Pay on Quickteller; Interswitch reports it, the portal cannot ask'
                            WHEN a.checks > 0 THEN 'Asked ' || a.checks || ' times, last ' || to_char(a.checked_at AT TIME ZONE 'Africa/Lagos', 'DD Mon HH24:MI')
                            ELSE 'Not asked yet' END AS why,
                       st.amount, NULL::uuid AS event_id
                  FROM finance.gateway_attempt a
                  LEFT JOIN LATERAL finance.reference_state(a.reference) st ON true
                 WHERE a.opened_at > now() - interval '3 days' AND st.confirmed_at IS NULL
                   AND a.id = (SELECT x.id FROM finance.gateway_attempt x WHERE x.reference = a.reference ORDER BY x.opened_at DESC LIMIT 1)
                   AND NOT EXISTS (SELECT 1 FROM ab WHERE ab.reference = a.reference)
                """,
            // V568: the checkouts of the last fortnight nobody went on to pay, and why
            "abandoned", """
                SELECT b.reference, b.opened_at AS at, b.gateway, 'ABANDONED_' || b.rule AS how, b.why, st.amount, NULL::uuid AS event_id
                  FROM finance.abandoned_checkouts(now(), 14) b
                  LEFT JOIN LATERAL (SELECT r.amount FROM finance.reference_state(b.reference) r LIMIT 1) st ON true
                """,
            // settled with no one's hand in the last three days, each reference once: by Interswitch's notification, the sweep, a request
            "resolved", """
                SELECT DISTINCT ON (e.reference) e.reference, e.received_at AS at, e.gateway,
                       CASE WHEN e.gateway = 'paydirect' AND e.source = 'WEBHOOK' THEN 'NOTIFICATION' WHEN e.source = 'SWEEP' THEN 'SWEEP' ELSE 'REQUEST' END AS how,
                       NULL::text AS why, e.amount, e.id AS event_id
                  FROM finance.gateway_event e
                 WHERE e.outcome = 'SETTLED' AND e.reference IS NOT NULL AND e.received_at > now() - interval '3 days'
                   AND ((e.gateway = 'paydirect' AND e.source = 'WEBHOOK') OR e.source IN ('SWEEP', 'VERIFY'))
                 ORDER BY e.reference, e.received_at DESC
                """,
            // what waits on a person, whatever its age until it is resolved: money against no reference or short, a reversal, a gateway
            // silent about a checkout of the last three days, a notification the portal could not settle, a payer's receipt to settle
            "needs", """
                SELECT * FROM (
                    SELECT DISTINCT ON (coalesce(e.reference, e.id::text), e.outcome) e.reference, e.received_at AS at, e.gateway, e.outcome AS how,
                           CASE e.outcome WHEN 'UNKNOWN_REFERENCE' THEN 'Paid against a reference the portal did not issue'
                                          WHEN 'SHORT_PAID' THEN 'Less than the reference asks; left open'
                                          WHEN 'REVERSED' THEN 'Interswitch reversed the payment; kept for the Bursary'
                                          ELSE 'The gateway did not answer for this checkout' END AS why,
                           e.amount, e.id AS event_id
                      FROM finance.gateway_event e
                      LEFT JOIN LATERAL finance.reference_state(e.reference) st ON e.reference IS NOT NULL
                     WHERE e.resolved_at IS NULL
                       AND (e.outcome IN ('UNKNOWN_REFERENCE', 'REVERSED')
                            OR e.outcome = 'SHORT_PAID' AND st.confirmed_at IS NULL
                            OR e.outcome = 'GATEWAY_ERROR' AND st.confirmed_at IS NULL AND e.received_at > now() - interval '3 days')
                     ORDER BY coalesce(e.reference, e.id::text), e.outcome, e.received_at DESC) ev
                UNION ALL
                SELECT i.reference, i.last_received_at, 'paydirect', 'NOT_SETTLED',
                       'Interswitch reported it; the portal could not settle it' || coalesce(': ' || left(i.last_error, 160), ''), i.amount, NULL::uuid
                  FROM finance.paydirect_inbox i
                 WHERE NOT i.is_reversal AND (i.state = 'FAILED' OR i.state = 'RECEIVED' AND i.last_received_at < now() - interval '1 hour')
                UNION ALL
                SELECT c.reference, c.claimed_at, 'paydirect', 'RECEIPT_' || c.state,
                       CASE c.state WHEN 'SEEN' THEN 'The payer''s receipt: Interswitch reported it here, ' || lower(replace(coalesce(c.seen_outcome, ''), '_', ' '))
                                    ELSE 'The payer''s receipt: Interswitch reported it against ' || coalesce(c.seen_reference, 'another reference') || '; settle it to this payer' END,
                       c.amount, NULL::uuid
                  FROM finance.paydirect_claims(30) c WHERE c.state IN ('SEEN', 'ELSEWHERE')
                """);

    /** the transactions behind a tile with who paid: name, number, faculty, department, programme, level, session, purpose and the
     *  phone and e-mail on record (a student's contact, or an applicant's account) — the payer read once for all the references */
    List<Map<String, Object>> tileRows(String kind) {
        String rows = TILE_ROWS.get(kind);
        if (rows == null) {
            throw new IllegalArgumentException(kind);
        }
        return jdbc.sql("WITH t AS MATERIALIZED (" + rows + """
                ),
                p AS (SELECT DISTINCT ON (upper(p.reference)) upper(p.reference) AS ref, p.surname, p.other_names, p.number, p.faculty, p.department, p.programme,
                             p.level, p.session, p.purpose, p.amount AS due, p.confirmed_at, p.channel, p.student_id, p.application_id, p.pg_application_id,
                             p.jupeb_application_id, p.source AS payer_kind
                        FROM reporting.payments p
                       WHERE p.reference = ANY ((SELECT array_agg(DISTINCT t.reference) FROM t WHERE t.reference IS NOT NULL)::text[])
                       ORDER BY upper(p.reference), p.confirmed_at DESC NULLS LAST)
                SELECT t.reference, t.at, t.gateway, t.how, t.why, coalesce(t.amount, p.due) AS amount, p.due, t.event_id,
                       nullif(btrim(coalesce(p.surname, '') || ', ' || coalesce(p.other_names, ''), ', '), '') AS payer, p.number, p.faculty, p.department,
                       p.programme, p.level, p.session, p.purpose, p.confirmed_at, p.channel, p.payer_kind,
                       coalesce(sc.phone, aa.phone, pa.phone, ja.phone) AS phone, coalesce(sc.email, aa.email, pa.email, ja.email) AS email,
                       told.told_at, told.told_case
                  FROM t
                  LEFT JOIN p ON p.ref = upper(t.reference)
                  LEFT JOIN LATERAL (SELECT pt.told_at, pt.case_code AS told_case FROM finance.payer_told pt WHERE pt.reference = upper(t.reference)
                                      ORDER BY pt.told_at DESC LIMIT 1) told ON t.reference IS NOT NULL
                  LEFT JOIN people.student_contact sc ON sc.student_id = p.student_id
                  LEFT JOIN admissions.application ap ON ap.id = p.application_id
                  LEFT JOIN LATERAL (SELECT a.phone, a.email FROM admissions.applicant_account a WHERE a.candidate_id = ap.candidate_id
                                      ORDER BY a.created_at DESC LIMIT 1) aa ON p.application_id IS NOT NULL
                  LEFT JOIN admissions.pg_application pga ON pga.id = p.pg_application_id
                  LEFT JOIN admissions.pg_applicant pa ON pa.id = pga.applicant_id
                  LEFT JOIN jupeb.application ja ON ja.id = p.jupeb_application_id
                 ORDER BY t.at DESC
                """).query().listOfRows();
    }

    /** the events that concern money — Quickteller's reference checks (V299) are listed on their own */
    List<Map<String, Object>> events(int limit) {
        return jdbc.sql("""
                SELECT e.id, e.gateway, e.source, e.event, e.reference, e.gateway_ref, e.amount, e.status, e.signature_ok, e.outcome, e.received_at,
                       e.resolved_at, e.resolution, p.surname || ', ' || p.given_names AS resolved_by_name, e.times, e.last_at
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

    /** Oct 2026: when Quickteller last asked after the reference and was told it may be paid — the payer pressed Continue on
     *  Quickteller's page or at a bank. Not a payment: the payment is Interswitch's notification. */
    java.util.Optional<java.time.Instant> quicktellerStartedAt(String reference) {
        return jdbc.sql("""
                SELECT e.received_at FROM finance.gateway_event e
                 WHERE e.reference = :r AND e.gateway = 'paydirect' AND e.source = 'VALIDATE' AND e.outcome = 'VALID'
                 ORDER BY e.received_at DESC LIMIT 1
                """).param("r", reference).query(java.sql.Timestamp.class).optional().map(java.sql.Timestamp::toInstant);
    }

    /** what Quickteller is told about a reference it asks after */
    Customer paydirectCustomer(String reference) {
        return jdbc.sql("SELECT * FROM finance.paydirect_customer(:r)").param("r", reference == null ? "" : reference).query(Customer.class).single();
    }

    /** Quickteller's reference checks, newest first */
    /** Oct 2026: the facts the Interswitch certification checklist is read from — the latest validation, the latest believed
     *  notification, what was discarded since, the latest reversal */
    Map<String, Object> paydirectCertification() {
        return jdbc.sql("""
                SELECT (SELECT max(e.received_at) FROM finance.gateway_event e WHERE e.gateway = 'paydirect' AND e.source = 'VALIDATE') AS validation_at,
                       (SELECT e.outcome FROM finance.gateway_event e WHERE e.gateway = 'paydirect' AND e.source = 'VALIDATE' ORDER BY e.received_at DESC LIMIT 1) AS validation_outcome,
                       b.received_at AS believed_at, b.outcome AS believed_outcome, b.reference AS believed_reference,
                       (SELECT count(*) FROM finance.gateway_event e
                         WHERE e.gateway = 'paydirect' AND e.source = 'WEBHOOK' AND e.event = 'notification' AND e.outcome IN ('NO_CREDENTIALS', 'BAD_SIGNATURE')
                           AND e.received_at > coalesce(b.received_at, now() - interval '30 days')) AS discarded_since,
                       (SELECT max(e.received_at) FROM finance.gateway_event e
                         WHERE e.gateway = 'paydirect' AND e.source = 'WEBHOOK' AND e.event = 'notification' AND e.outcome IN ('NO_CREDENTIALS', 'BAD_SIGNATURE')) AS discarded_at,
                       r.received_at AS reversal_at, r.reference AS reversal_reference
                  FROM (SELECT 1) one
                  LEFT JOIN LATERAL (SELECT e.received_at, e.outcome, e.reference FROM finance.gateway_event e
                                      WHERE e.gateway = 'paydirect' AND e.source = 'WEBHOOK' AND e.event = 'notification' AND e.signature_ok
                                      ORDER BY e.received_at DESC LIMIT 1) b ON true
                  LEFT JOIN LATERAL (SELECT e.received_at, e.reference FROM finance.gateway_event e
                                      WHERE e.gateway = 'paydirect' AND e.source = 'WEBHOOK' AND e.event = 'reversal'
                                      ORDER BY e.received_at DESC LIMIT 1) r ON true
                """).query().singleRow();
    }

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

    /* ── V383: a test reference for Interswitch's testers, payable for the days the Bursar chooses ── */

    String gatewayTestReference(UUID student, String session, BigDecimal amount, int days) {
        return jdbc.sql("SELECT finance.new_gateway_test_reference(:s, :n, :a, :d)").param("s", student).param("n", session).param("a", amount).param("d", days)
                .query(String.class).single();
    }

    void withdrawGatewayTestReference(String reference) {
        jdbc.sql("SELECT finance.withdraw_gateway_test_reference(:r)").param("r", reference).query().singleRow();
    }

    /** the test references of the last thirty days (or the one named), open ones first: the payer, the expiry, and what Quickteller was last told about each */
    List<Map<String, Object>> gatewayTestReferences(String reference) {
        return jdbc.sql("""
                SELECT t.reference, pr.amount, pr.session, pr.generated_at, pr.expires_at, t.days, pr.confirmed_at, pr.receipt_no, pr.channel, t.withdrawn_at,
                       CASE WHEN pr.confirmed_at IS NOT NULL THEN 'PAID' WHEN t.withdrawn_at IS NOT NULL THEN 'WITHDRAWN'
                            WHEN pr.expires_at < now() THEN 'EXPIRED' ELSE 'OPEN' END AS state,
                       s.surname || ', ' || s.other_names AS payer, coalesce(s.matric_no, s.admission_no) AS number,
                       p.surname || ', ' || p.given_names AS issued_by_name, t.issued_office,
                       v.checks, v.last_check_at, v.last_outcome
                  FROM finance.gateway_test_reference t
                  JOIN finance.payment_reference pr ON pr.reference = t.reference
                  JOIN people.student s ON s.id = pr.student_id
                  LEFT JOIN iam.person p ON p.id = t.issued_by
                  LEFT JOIN LATERAL (SELECT count(*) AS checks, max(e.received_at) AS last_check_at,
                                            (array_agg(e.outcome ORDER BY e.received_at DESC))[1] AS last_outcome
                                       FROM finance.gateway_event e
                                      WHERE e.gateway = 'paydirect' AND e.source = 'VALIDATE' AND e.reference = t.reference) v ON true
                 WHERE CASE WHEN :r::text IS NULL THEN t.issued_at > now() - interval '30 days' ELSE t.reference = upper(btrim(:r)) END
                 ORDER BY (pr.confirmed_at IS NULL AND t.withdrawn_at IS NULL AND pr.expires_at >= now()) DESC, t.issued_at DESC
                 LIMIT 100
                """).param("r", reference, Types.VARCHAR).query().listOfRows();
    }

    String currentSession() {
        return jdbc.sql("SELECT policy.university_current_session()").query(String.class).optional().orElseGet(Sessions::byDate);
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

    // ── V433: the PAYDirect door counted by address, kept to its list, and watched for silence ──

    /** every call counted by its address; false when the door is kept to its list and the address is not on it */
    boolean paydirectDoorAdmit(String address, String kind) {
        return Boolean.TRUE.equals(jdbc.sql("SELECT finance.paydirect_door_admit(:a, :k)")
                .param("a", address, Types.VARCHAR).param("k", kind).query(Boolean.class).single());
    }

    Map<String, Object> paydirectDoorStatus() {
        return jdbc.sql("SELECT * FROM finance.paydirect_door_status()").query().singleRow();
    }

    List<Map<String, Object>> paydirectAllowedAddresses() {
        return jdbc.sql("""
                SELECT CASE WHEN masklen(x.address) = CASE WHEN family(x.address) = 4 THEN 32 ELSE 128 END THEN host(x.address) ELSE x.address::text END AS address, x.label, x.added_at, p.surname || ', ' || p.given_names AS added_by_name
                  FROM finance.paydirect_allowed_address x LEFT JOIN iam.person p ON p.id = x.added_by
                 ORDER BY x.added_at
                """).query().listOfRows();
    }

    List<Map<String, Object>> paydirectAddressesSeen(int days) {
        return jdbc.sql("SELECT * FROM finance.paydirect_addresses_seen(:d)").param("d", days).query().listOfRows();
    }

    Map<String, Object> setPaydirectDoor(Boolean restrict, Boolean watch, Integer silenceHours) {
        return jdbc.sql("SELECT restrict_addresses, watch_enabled, silence_hours, last_alert_at FROM finance.set_paydirect_door(:r, :w, :h)")
                .param("r", restrict, Types.BOOLEAN).param("w", watch, Types.BOOLEAN).param("h", silenceHours, Types.INTEGER).query().singleRow();
    }

    Map<String, Object> addPaydirectAddress(String address, String label) {
        return jdbc.sql("SELECT CASE WHEN masklen(address) = CASE WHEN family(address) = 4 THEN 32 ELSE 128 END THEN host(address) ELSE address::text END AS address, label, added_at FROM finance.add_paydirect_address(:a, :l)")
                .param("a", address, Types.VARCHAR).param("l", label, Types.VARCHAR).query().singleRow();
    }

    int removePaydirectAddress(String address) {
        return jdbc.sql("SELECT finance.remove_paydirect_address(:a)").param("a", address, Types.VARCHAR).query(Integer.class).single();
    }

    /** the messages queued to the Directorate of ICT and the Bursary; 0 while the door keeps its rhythm or the silence is told */
    int watchPaydirect() {
        return jdbc.sql("SELECT finance.watch_paydirect()").query(Integer.class).single();
    }

    /** V477: the Bursary told, once a day, of the Pay on Quickteller payments Interswitch has not reported after a day */
    int watchPaydirectUnreported() {
        return jdbc.sql("SELECT finance.watch_paydirect_unreported()").query(Integer.class).single();
    }

    /** V480: the payer's receipt for a Pay on Quickteller payment, kept against the reference (the latest replaces the last) */
    Map<String, Object> claimPaydirect(String reference, UUID account, String logId, java.time.LocalDate paidOn, BigDecimal amount, String channel, String note) {
        return jdbc.sql("""
                SELECT reference, payment_log_id, paid_on::text AS paid_on, amount, channel, note, claimed_at
                  FROM finance.paydirect_claim_set(:r, :a::uuid, :l, :d::date, :m::numeric, :c::text, :n::text)
                """).param("r", reference).param("a", account).param("l", logId).param("d", paidOn).param("m", amount)
                .param("c", channel).param("n", note).query().singleRow();
    }

    /** the columns of a reported receipt as the screens read it (V480, V490: its state, where its Payment Log Id was seen, the Bursary's word) */
    private static final String CLAIM_COLUMNS = """
            reference, payer, number, due, payment_log_id, paid_on::text AS paid_on, amount, channel, note, claimed_at, claimed_office, confirmed_at,
            state, seen_reference, seen_in, seen_outcome, seen_at, not_found_at, not_found_note, not_found_office
            """;

    /** V480, V490: the receipt reported against a reference, if any, whatever its age */
    Optional<Map<String, Object>> paydirectClaim(String reference) {
        return jdbc.sql("SELECT " + CLAIM_COLUMNS + " FROM finance.paydirect_claims(30, :r)")
                .param("r", reference).query().listOfRows().stream().findFirst();
    }

    /** V480: the receipts payers reported in the period, those needing the Bursary first */
    List<Map<String, Object>> paydirectClaims(int days) {
        return jdbc.sql("SELECT " + CLAIM_COLUMNS + " FROM finance.paydirect_claims(:d)").param("d", days).query().listOfRows();
    }

    /** V490: the Bursary's word on a reported receipt — not found at Interswitch, with a note the payer is told; or reopened */
    void markPaydirectClaim(String reference, boolean notFound, String note) {
        jdbc.sql("SELECT reference FROM finance.paydirect_claim_mark(:r, :f, :n::text)").param("r", reference).param("f", notFound).param("n", note)
                .query().singleRow();
    }

    /** V480: what the Bursary sends Interswitch to re-send */
    List<Map<String, Object>> paydirectAskList(int days) {
        return jdbc.sql("""
                SELECT reference, payer, number, due, opened_at, payment_log_id, paid_on::text AS paid_on, paid_amount, channel
                  FROM finance.paydirect_ask_list(:d)
                """).param("d", days).query().listOfRows();
    }

    /** the gateways a reference was opened on — a reference opened only on Pay on Quickteller is Interswitch's to report */
    java.util.List<String> attemptGateways(String reference) {
        return jdbc.sql("SELECT DISTINCT gateway FROM finance.gateway_attempt WHERE reference = :r").param("r", reference).query(String.class).list();
    }
}
