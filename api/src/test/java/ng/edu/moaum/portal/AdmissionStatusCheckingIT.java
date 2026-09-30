package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.sql.Types;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Random;
import java.util.UUID;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.HttpMethod;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.transaction.PlatformTransactionManager;

/**
 * Admission Status Checking (V295), end to end through the API: every applicant with a valid Post-UTME application — the fee
 * confirmed and the application submitted — may pay the admission checking fee once and check their status while the Director
 * of ICT has checking open, admitted, not admitted and not yet decided alike; the decision is the output of a check, never its
 * condition. The six cases of the brief — admitted, not admitted, pending (then admitted later without paying again), no valid
 * application, checking closed, paid and open — and the regressions around them: closed by default; only the Director opens
 * and closes it; nothing of an offer is learned or acted on before it is checked (the acceptance fee, the undertaking, the
 * decline and the document list answer alike); one reference reused and the fee never charged twice; an unconfirmed payment
 * does not count; each check kept with its result; the release notice neutral; the applicants told when checking opens and
 * closes; an admission already read continues after closing; the gateway refuses a checking fee while closed; the report and
 * its filters for the Director and the admissions offices, refused to others. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class AdmissionStatusCheckingIT {

    static final String SESSION = "2111/2112";
    static final String PATH = "/api/v1/admissions/sessions/2111/2112";
    static final String WINDOW = "/api/v1/portal-windows/ADMISSION_STATUS_CHECKING";
    static final String DESK = "/api/v1/portal-windows/admission-checking";

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    ItSupport it;
    final String ict = ItSupport.token("ict");
    final String academic = ItSupport.token("academic");
    final String registrar = ItSupport.token("registrar");
    final String bursar = ItSupport.token("bursar");

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
        it.session(SESSION, 2111);
        it.db(() -> {
            jdbc.sql("INSERT INTO admissions.applicant_fee (session, application_fee, portal_charge, acceptance_fee, checking_fee) VALUES (:s, 2000, 0, 25000, 3000) ON CONFLICT (session) DO UPDATE SET acceptance_fee = 25000, checking_fee = 3000")
                    .param("s", SESSION).update();
            // the residue of an earlier run: the session's checking window starts unconfigured, closed by default
            jdbc.sql("DELETE FROM policy.portal_window_event WHERE session = :s").param("s", SESSION).update();
            jdbc.sql("DELETE FROM policy.portal_window WHERE session = :s").param("s", SESSION).update();
            return null;
        });
    }

    record Applicant(UUID app, UUID account, UUID candidate, String jamb, String token) { }

    /** an applicant of the session: on JAMB's list, an account, the application paid for and (when valid) submitted, the score
     *  released, and the decision as given — released or not; an offer released makes the candidate ADMITTED, as the release does */
    Applicant applicant(String decision, boolean released, boolean valid, String sex) {
        int n = new Random().nextInt(90_000_000) + 10_000_000;
        String jamb = "2111" + n + "SC";
        return it.db(() -> {
            UUID cand = UUID.randomUUID(), acct = UUID.randomUUID(), app = UUID.randomUUID(), batch = UUID.randomUUID(), row = UUID.randomUUID();
            jdbc.sql("INSERT INTO admissions.caps_batch (id, session, source, filename, file_sha256, rows_read, list_kind, downloaded_on, uploaded_by, uploaded_office, committed_at) VALUES (:id, :s, 'CAPS_DOWNLOAD', 'checking.xlsx', decode(md5(:id::text), 'hex'), 1, 'UTME', current_date, gen_random_uuid(), 'academic', now())")
                    .param("id", batch).param("s", SESSION).update();
            jdbc.sql("INSERT INTO admissions.caps_row (id, batch_id, session, jamb_reg_no, raw, surname, other_names, jamb_code, aggregate, entry_mode, sex, state_of_origin, lga) VALUES (:id, :b, :s, :j, '{}'::jsonb, :sn, 'Check Person', 'C00023', 230, 'UTME', :sex, 'Benue', 'Makurdi')")
                    .param("id", row).param("b", batch).param("s", SESSION).param("j", jamb).param("sn", "ZZCHECK-" + n).param("sex", sex).update();
            jdbc.sql("INSERT INTO admissions.candidate (id, session, jamb_reg_no, surname, other_names, programme, entry_mode, entry_level, offer_state, admitted_from) VALUES (:id, :s, :j, :sn, 'Check Person', (SELECT name FROM ref.programme WHERE code = 'C00023'), 'UTME', 100, :st, :r)")
                    .param("id", cand).param("s", SESSION).param("j", jamb).param("sn", "ZZCHECK-" + n)
                    .param("st", "OFFERED".equals(decision) && released ? "ADMITTED" : "PROPOSED").param("r", row).update();
            jdbc.sql("INSERT INTO admissions.applicant_account (id, session, candidate_id, jamb_key, email, phone, password_hash) VALUES (:id, :s, :c, :k, :e, '08030000000', crypt('x', gen_salt('bf', 12)))")
                    .param("id", acct).param("s", SESSION).param("c", cand).param("k", jamb).param("e", jamb.toLowerCase() + "@example.com").update();
            jdbc.sql("""
                    INSERT INTO admissions.application (id, account_id, candidate_id, session, application_no, fee_confirmed_at, submitted_at, score_released_at,
                                                        decision, decision_basis, decided_at, decision_released_at)
                    VALUES (:id, :a, :c, :s, :no, now(), CASE WHEN :valid THEN now() END, now(),
                            :d, CASE WHEN :d = 'OFFERED' THEN 'NM' END, CASE WHEN :d::text IS NOT NULL THEN now() END, CASE WHEN :rel THEN now() END)
                    """).param("id", app).param("a", acct).param("c", cand).param("s", SESSION).param("no", "APP/11/" + String.format("%06d", n % 1_000_000))
                    .param("valid", valid).param("d", decision, Types.VARCHAR).param("rel", released).update();
            return new Applicant(app, acct, cand, jamb, TestTokens.token(acct, List.of("applicant")));
        });
    }

    static Map<String, Object> m(Object o) { return (Map<String, Object>) o; }
    static List<Map<String, Object>> l(Object o) { return (List<Map<String, Object>>) o; }
    static String code(ResponseEntity<Map> r) { return r.getBody() == null ? null : String.valueOf(r.getBody().get("code")); }

    Map<String, Object> admission(Applicant a) { return m(it.get(a.token(), "/api/v1/applicant/me/admission").getBody()); }
    Map<String, Object> me(Applicant a) { return m(it.get(a.token(), "/api/v1/applicant/me").getBody()); }
    ResponseEntity<Map> reference(Applicant a, String kind) { return it.call(a.token(), HttpMethod.POST, "/api/v1/applicant/me/fee-references", Map.of("kind", kind)); }
    ResponseEntity<Map> checkStatus(Applicant a) { return it.call(a.token(), HttpMethod.POST, "/api/v1/applicant/me/admission/checked", Map.of()); }
    ResponseEntity<Map> confirm(String reference) { return it.call(bursar, HttpMethod.POST, PATH + "/fee-references/" + reference + "/confirm", Map.of("channel", "Card")); }

    ResponseEntity<Map> act(String token, String action, String reason) {
        Map<String, Object> body = new LinkedHashMap<>();
        body.put("session", SESSION);
        body.put("action", action);
        if (reason != null) body.put("reason", reason);
        return it.call(token, HttpMethod.POST, WINDOW, body);
    }

    /** the checking fee, generated and confirmed: the reference it was paid on */
    String pay(Applicant a) {
        ResponseEntity<Map> ref = reference(a, "CHECKING");
        assertThat(ref.getStatusCode().value()).as(String.valueOf(ref.getBody())).isEqualTo(200);
        String r = String.valueOf(ref.getBody().get("reference"));
        assertThat(r).startsWith("MOAUM-CHK-");
        ResponseEntity<Map> c = confirm(r);
        assertThat(c.getStatusCode().value()).as(String.valueOf(c.getBody())).isEqualTo(200);
        return r;
    }

    long notices(Applicant a, String subjectLike) {
        return jdbc.sql("SELECT count(*) FROM platform.notice WHERE about_kind = 'application' AND about_id = :a AND channel = 'EMAIL' AND subject ILIKE :s")
                .param("a", a.app()).param("s", subjectLike).query(Long.class).single();
    }

    long checks(Applicant a) {
        return jdbc.sql("SELECT count(*) FROM admissions.status_check WHERE application_id = :a").param("a", a.app()).query(Long.class).single();
    }

    long checkingReferences(Applicant a) {
        return jdbc.sql("SELECT count(*) FROM admissions.fee_reference WHERE application_id = :a AND kind = 'CHECKING'").param("a", a.app()).query(Long.class).single();
    }

    @Test
    void everyValidApplicantPaysOnceAndChecksWhileTheDirectorHasCheckingOpen() {
        Applicant admitted = applicant("OFFERED", true, true, "F");       // 1 · admitted
        Applicant refused = applicant("NOT_OFFERED", true, true, "M");    // 2 · not admitted
        Applicant pending = applicant(null, false, true, "F");            // 3 · no decision yet
        Applicant incomplete = applicant(null, false, false, "M");        // 4 · paid for, never submitted: no valid application
        Applicant late = applicant(null, false, true, "M");               // a reference taken while open, not paid before closing

        // ── 5 · closed until the Director of ICT first opens it: nobody pays, nobody checks, nothing of the decision shows ──
        Map<String, Object> st = admission(admitted);
        assertThat(st.get("status")).isEqualTo("CHECKING_CLOSED");
        assertThat(m(st.get("checking")).get("windowOpen")).isEqualTo(false);
        assertThat(m(st.get("checking")).get("applicationValid")).isEqualTo(true);
        assertThat(m(st.get("offer")).get("decision")).isNull();
        assertThat(m(st.get("offer")).get("faculty")).isNull();
        assertThat(me(admitted).get("decision")).isNull();
        assertThat(me(admitted).get("offerState")).isEqualTo("PROPOSED");   // ADMITTED on the record; not the applicant's to read yet
        assertThat(String.valueOf(st.get("tracker"))).contains("\"key\": \"ADMISSION\", \"label\": \"JAMB admission\", \"state\": \"now\"");
        assertThat(code(reference(pending, "CHECKING"))).isEqualTo("ADMISSION_CHECKING_CLOSED");
        ResponseEntity<Map> closedCheck = checkStatus(pending);
        assertThat(closedCheck.getStatusCode().value()).isEqualTo(422);
        assertThat(code(closedCheck)).isEqualTo("ADMISSION_CHECKING_CLOSED");
        // no bypass: before a check, the acceptance fee, the undertaking and the decline answer the admitted as the not admitted
        for (Applicant x : List.of(admitted, refused)) {
            assertThat(code(reference(x, "ACCEPTANCE"))).as("acceptance fee").isEqualTo("ADMISSION_STATUS_NOT_CHECKED");
            assertThat(code(it.call(x.token(), HttpMethod.POST, "/api/v1/applicant/me/accept", Map.of("undertaking", true)))).as("undertaking").isEqualTo("ADMISSION_STATUS_NOT_CHECKED");
            assertThat(code(it.call(x.token(), HttpMethod.POST, "/api/v1/applicant/me/decline", Map.of()))).as("decline").isEqualTo("ADMISSION_STATUS_NOT_CHECKED");
        }
        assertThat(jdbc.sql("SELECT undertaking_at IS NULL AND declined_at IS NULL FROM admissions.application WHERE id = :a").param("a", admitted.app()).query(Boolean.class).single()).isTrue();
        // the document list says nothing of an offer either: the letter waits "after an offer of admission", no school-fees row
        List<Map<String, Object>> centre = l(it.get(admitted.token(), "/api/v1/applicant/me/documents-centre").getBody().get("rows"));
        assertThat(centre.stream().filter(x -> "OFFER_LETTER".equals(x.get("key"))).findFirst().orElseThrow().get("availableAfter")).isEqualTo("after an offer of admission");
        assertThat(centre.stream().map(x -> x.get("key"))).doesNotContain("SCHOOL_FEES_RECEIPT");

        // ── the window is the Director of ICT's alone; the admissions offices read it; it has no semester and no late period ──
        assertThat(act(academic, "OPEN", null).getStatusCode().value()).isEqualTo(403);
        assertThat(act(registrar, "OPEN", null).getStatusCode().value()).isEqualTo(403);
        ResponseEntity<Map> withSemester = it.call(ict, HttpMethod.POST, WINDOW, Map.of("session", SESSION, "action", "OPEN", "semester", 1));
        assertThat(withSemester.getStatusCode().value()).isEqualTo(422);
        assertThat(code(withSemester)).isEqualTo("WINDOW_CHECKING_SESSION");
        Map<String, Object> desk = m(it.get(academic, DESK + "?session=" + SESSION).getBody());
        assertThat(m(desk.get("window")).get("state")).isEqualTo("CLOSED");
        assertThat(m(desk.get("window")).get("configured")).isEqualTo(false);
        assertThat(it.get(bursar, DESK + "?session=" + SESSION).getStatusCode().value()).isEqualTo(403);
        assertThat(it.get(admitted.token(), DESK + "?session=" + SESSION).getStatusCode().value()).isEqualTo(403);

        // ── opened: the session's valid applicants are told ──
        ResponseEntity<Map> opened = act(ict, "OPEN", "Admission status checking for the " + SESSION + " exercise");
        assertThat(opened.getStatusCode().value()).as(String.valueOf(opened.getBody())).isEqualTo(200);
        assertThat(((Number) opened.getBody().get("told")).intValue()).isGreaterThanOrEqualTo(4);   // admitted, refused, pending, late — never the incomplete
        assertThat(m(m(opened.getBody()).get("window")).get("state")).isEqualTo("OPEN");
        assertThat(notices(pending, "Admission Status Checking is now open")).isEqualTo(1);
        assertThat(notices(incomplete, "Admission Status Checking is now open")).isZero();

        // ── 4 · no valid application: neither pays nor checks, and is told why ──
        assertThat(admission(incomplete).get("status")).isEqualTo("APPLICATION_INCOMPLETE");
        assertThat(code(reference(incomplete, "CHECKING"))).isEqualTo("ADMISSION_CHECKING_NOT_ELIGIBLE");
        assertThat(code(checkStatus(incomplete))).isEqualTo("ADMISSION_CHECKING_NOT_ELIGIBLE");

        // ── open, not paid: the fee is owed, whatever the decision; the check is refused until it is confirmed ──
        st = admission(pending);
        assertThat(st.get("status")).isEqualTo("CHECKING_FEE_PENDING");
        assertThat(m(st.get("checking")).get("mayPay")).isEqualTo(true);
        assertThat(m(st.get("checking")).get("mayCheck")).isEqualTo(false);
        assertThat(code(checkStatus(pending))).isEqualTo("ADMISSION_CHECKING_FEE_UNPAID");
        // one reference, reused while it is open: the service is never charged twice; an unconfirmed payment is no payment
        String r1 = String.valueOf(reference(pending, "CHECKING").getBody().get("reference"));
        String r2 = String.valueOf(reference(pending, "CHECKING").getBody().get("reference"));
        assertThat(r2).isEqualTo(r1);
        assertThat(checkingReferences(pending)).isEqualTo(1);
        assertThat(jdbc.sql("SELECT amount FROM admissions.fee_reference WHERE reference = :r").param("r", r1).query(java.math.BigDecimal.class).single()).isEqualByComparingTo("3000");
        assertThat(code(checkStatus(pending))).isEqualTo("ADMISSION_CHECKING_FEE_UNPAID");
        assertThat(confirm(r1).getStatusCode().value()).isEqualTo(200);
        assertThat(notices(pending, "Your payment receipt%")).isGreaterThanOrEqualTo(1);
        assertThat(jdbc.sql("SELECT count(*) FROM platform.notice WHERE about_id = :a AND channel = 'EMAIL' AND body LIKE '%Admission Checking Fee payment has been verified%'").param("a", pending.app()).query(Long.class).single()).isEqualTo(1);
        ResponseEntity<Map> again = reference(pending, "CHECKING");
        assertThat(code(again)).isEqualTo("ADMISSION_CHECKING_PAID");   // paid once

        // ── 3 · pending: the check returns PENDING, is kept, and shows no offer ──
        ResponseEntity<Map> checked = checkStatus(pending);
        assertThat(checked.getStatusCode().value()).as(String.valueOf(checked.getBody())).isEqualTo(200);
        assertThat(checked.getBody().get("status")).isEqualTo("PENDING");
        assertThat(String.valueOf(checked.getBody().get("detail"))).contains("not yet been finalised");
        assertThat(m(checked.getBody().get("offer")).get("decision")).isNull();
        assertThat(checks(pending)).isEqualTo(1);
        assertThat(l(checked.getBody().get("checks")).get(0).get("result")).isEqualTo("PENDING");

        // ── 2 · not admitted: pays, checks, reads NOT ADMITTED; there is nothing to accept ──
        pay(refused);
        ResponseEntity<Map> no = checkStatus(refused);
        assertThat(no.getStatusCode().value()).isEqualTo(200);
        assertThat(no.getBody().get("status")).isEqualTo("NOT_ADMITTED");
        assertThat(no.getBody().get("label")).isEqualTo("Not admitted");
        assertThat(m(no.getBody().get("offer")).get("decision")).isEqualTo("NOT_OFFERED");
        assertThat(reference(refused, "ACCEPTANCE").getStatusCode().value()).isEqualTo(422);
        assertThat(notices(refused, "Congratulations%")).isZero();

        // ── 1 · admitted: pays, checks, is congratulated, and continues to the acceptance ──
        pay(admitted);
        ResponseEntity<Map> yes = checkStatus(admitted);
        assertThat(yes.getStatusCode().value()).isEqualTo(200);
        assertThat(yes.getBody().get("status")).isEqualTo("ADMITTED");
        assertThat(String.valueOf(yes.getBody().get("next_action"))).contains("acceptance fee");
        assertThat(m(yes.getBody().get("offer")).get("decision")).isEqualTo("OFFERED");
        assertThat(m(yes.getBody().get("offer")).get("faculty")).isNotNull();
        assertThat(m(yes.getBody().get("checking")).get("past")).isEqualTo(true);
        assertThat(me(admitted).get("offerState")).isEqualTo("ADMITTED");
        assertThat(notices(admitted, "Congratulations! You have been offered admission")).isEqualTo(1);
        assertThat(checkStatus(admitted).getStatusCode().value()).isEqualTo(200);   // checked again: kept as a check, congratulated once
        assertThat(notices(admitted, "Congratulations! You have been offered admission")).isEqualTo(1);
        assertThat(checks(admitted)).isEqualTo(2);

        // ── the report: every application with its fee, its checks and the authoritative result, filtered ──
        Map<String, Object> report = m(it.get(ict, DESK + "/report?session=" + SESSION).getBody());
        List<Map<String, Object>> rows = l(report.get("rows"));
        assertThat(rows.stream().map(x -> x.get("jamb_reg_no"))).contains(admitted.jamb(), refused.jamb(), pending.jamb(), incomplete.jamb(), late.jamb());
        Map<String, Object> adm = rows.stream().filter(x -> admitted.jamb().equals(x.get("jamb_reg_no"))).findFirst().orElseThrow();
        assertThat(adm.get("result")).isEqualTo("ADMITTED");
        assertThat(adm.get("paid")).isEqualTo(true);
        assertThat(adm.get("checked")).isEqualTo(true);
        assertThat(rows.stream().filter(x -> incomplete.jamb().equals(x.get("jamb_reg_no"))).findFirst().orElseThrow().get("valid")).isEqualTo(false);
        assertThat(l(m(it.get(registrar, DESK + "/report?session=" + SESSION + "&payment=PAID").getBody()).get("rows")).stream().map(x -> x.get("jamb_reg_no")))
                .contains(admitted.jamb(), refused.jamb(), pending.jamb()).doesNotContain(late.jamb(), incomplete.jamb());
        assertThat(l(m(it.get(academic, DESK + "/report?session=" + SESSION + "&result=NOT_ADMITTED").getBody()).get("rows")).stream().map(x -> x.get("jamb_reg_no")))
                .containsExactly(refused.jamb());
        assertThat(l(m(it.get(ict, DESK + "/report?session=" + SESSION + "&payment=NOT_ELIGIBLE").getBody()).get("rows")).stream().map(x -> x.get("jamb_reg_no")))
                .containsExactly(incomplete.jamb());
        assertThat(l(m(it.get(ict, DESK + "/report?session=" + SESSION + "&sex=F&checked=CHECKED").getBody()).get("rows")).stream().map(x -> x.get("jamb_reg_no")))
                .contains(admitted.jamb(), pending.jamb()).doesNotContain(refused.jamb());
        Map<String, Object> summary = m(m(it.get(ict, DESK + "?session=" + SESSION).getBody()).get("summary"));
        assertThat(((Number) summary.get("paid")).intValue()).isGreaterThanOrEqualTo(3);
        assertThat(new java.math.BigDecimal(String.valueOf(summary.get("revenue")))).isGreaterThanOrEqualTo(new java.math.BigDecimal("9000"));
        assertThat(it.get(bursar, DESK + "/report?session=" + SESSION).getStatusCode().value()).isEqualTo(403);

        // ── 6 · closed after the admission: the admitted continues; nobody else pays or checks; the gateway refuses ──
        String lateRef = String.valueOf(reference(late, "CHECKING").getBody().get("reference"));
        assertThat(act(ict, "CLOSE", null).getStatusCode().value()).isEqualTo(422);   // the reason is recorded
        ResponseEntity<Map> closed = act(ict, "CLOSE", "The checking exercise has ended");
        assertThat(closed.getStatusCode().value()).as(String.valueOf(closed.getBody())).isEqualTo(200);
        assertThat(notices(late, "Admission Status Checking is closed")).isEqualTo(1);
        assertThat(notices(admitted, "Admission Status Checking is closed")).isZero();   // on the way to acceptance, it no longer concerns them
        assertThat(it.call(admitted.token(), HttpMethod.POST, "/api/v1/applicant/me/accept", Map.of("undertaking", true)).getStatusCode().value()).isEqualTo(200);
        ResponseEntity<Map> acc = reference(admitted, "ACCEPTANCE");
        assertThat(acc.getStatusCode().value()).as(String.valueOf(acc.getBody())).isEqualTo(200);
        assertThat(String.valueOf(acc.getBody().get("reference"))).startsWith("MOAUM-ACC-");
        assertThat(admission(admitted).get("status")).isEqualTo("ACCEPTANCE_PENDING");
        assertThat(code(checkStatus(refused))).isEqualTo("ADMISSION_CHECKING_CLOSED");
        assertThat(admission(refused).get("status")).isEqualTo("CHECKING_CLOSED");
        assertThat(code(reference(late, "CHECKING"))).isEqualTo("ADMISSION_CHECKING_CLOSED");
        ResponseEntity<Map> gateway = it.call(late.token(), HttpMethod.POST, "/api/v1/payments/checkout", Map.of("reference", lateRef));
        assertThat(gateway.getStatusCode().value()).isEqualTo(422);
        assertThat(code(gateway)).isEqualTo("ADMISSION_CHECKING_NOT_PAYABLE");

        // ── 3 (continued) · decided and released later: the notice names no decision; checked again when reopened, admitted, not charged again ──
        assertThat(it.call(academic, HttpMethod.PUT, PATH + "/applications/" + pending.app() + "/decision", Map.of("decision", "OFFERED", "basis", "NM")).getStatusCode().value()).isEqualTo(200);
        assertThat(it.call(academic, HttpMethod.POST, PATH + "/decisions/release", Map.of()).getStatusCode().value()).isEqualTo(200);
        String releaseNotice = jdbc.sql("SELECT body FROM platform.notice WHERE about_id = :a AND channel = 'EMAIL' AND subject = :s ORDER BY created_at DESC LIMIT 1")
                .param("a", pending.app()).param("s", "Your admission status for " + SESSION).query(String.class).single();
        assertThat(releaseNotice).doesNotContainIgnoringCase("offered").doesNotContainIgnoringCase("congratulations");
        assertThat(me(pending).get("decision")).isNull();                       // closed: the release opens nothing by itself
        assertThat(admission(pending).get("status")).isEqualTo("CHECKING_CLOSED");
        ResponseEntity<Map> reopened = act(ict, "REOPEN", "Supplementary admission list released");
        assertThat(reopened.getStatusCode().value()).as(String.valueOf(reopened.getBody())).isEqualTo(200);
        ResponseEntity<Map> later = checkStatus(pending);
        assertThat(later.getStatusCode().value()).isEqualTo(200);
        assertThat(later.getBody().get("status")).isEqualTo("ADMITTED");
        assertThat(checkingReferences(pending)).isEqualTo(1);                  // paid once, checked twice
        assertThat(checks(pending)).isEqualTo(2);
        assertThat(jdbc.sql("SELECT string_agg(result, ',' ORDER BY checked_at) FROM admissions.status_check WHERE application_id = :a").param("a", pending.app()).query(String.class).single())
                .isEqualTo("PENDING,ADMITTED");
        // the not admitted checks again after the reopening, for nothing
        assertThat(checkStatus(refused).getStatusCode().value()).isEqualTo(200);
        assertThat(checkingReferences(refused)).isEqualTo(1);

        // ── the history keeps every act with its reason and the Director ──
        List<Map<String, Object>> events = l(m(it.get(ict, DESK + "?session=" + SESSION).getBody()).get("events"));
        assertThat(events.stream().map(e -> e.get("action"))).contains("OPEN", "CLOSE", "REOPEN");
        assertThat(events.stream().filter(e -> "CLOSE".equals(e.get("action"))).findFirst().orElseThrow().get("reason")).isEqualTo("The checking exercise has ended");
        assertThat(events.stream().map(e -> e.get("window_type")).distinct()).containsExactly("ADMISSION_STATUS_CHECKING");
    }
}
