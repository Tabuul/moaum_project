package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.math.BigDecimal;
import java.time.OffsetDateTime;
import java.util.List;
import java.util.Map;
import java.util.Random;
import java.util.UUID;

import org.junit.jupiter.api.AfterEach;
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
 * V724 — the student portal's fee gate for a fresh admit, end to end through the API: an applicant accepted and on the register
 * (an admission number, no matriculation number) is held out of the student portal while the Bursary has not stated the session's
 * school fees, told so at the hand-off and at the sign-in on the admission number (only after the password has opened the record),
 * sees "not yet available" on the applicant dashboard; the fees stated, pays the first semester from the applicant dashboard on a
 * school-fee reference the applicant token owns (another applicant's token is refused it); paid, the portal opens; set to the session
 * in full, the student portal answers 403 on every path but the record, the notices and the fee paths; an exception from the Bursary
 * lets them through until revoked; a matriculated student and an earlier cohort are never held; the gate turned off, nobody is. The
 * monitors and the readiness check count the student. The gate row is put back as it was found.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT,
        properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
class PortalFeeGateIT {

    static final String CS = "C00023";

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    ItSupport it;
    final String bursar = ItSupport.token("bursar");
    final String ict = ItSupport.token("ict");
    final String academic = ItSupport.token("academic");
    String session;
    int year;
    Map<String, Object> gateBefore;

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
        year = it.freeYear(2066, 2072, 1, 0);
        session = year + "/" + (year + 1);
        it.session(session, year);
        it.session((year - 1) + "/" + year, year - 1);
        gateBefore = jdbc.sql("SELECT enabled, from_session, clears_on FROM finance.portal_fee_gate WHERE id = 1").query().singleRow();
    }

    @AfterEach
    void putTheGateBack() {
        // the fee lines this test stated end with it: a session with fees in force is the one a later test's student reads by default
        it.db(() -> jdbc.sql("UPDATE finance.fee_schedule SET ended_at = now() WHERE session = :s AND item LIKE 'PortalFeeGateIT:%' AND ended_at IS NULL")
                .param("s", session).update());
        it.db(() -> jdbc.sql("UPDATE finance.portal_fee_gate SET enabled = :e, from_session = :f, clears_on = :c, reason = 'PortalFeeGateIT: put back as found' WHERE id = 1")
                .param("e", gateBefore.get("enabled")).param("f", gateBefore.get("from_session")).param("c", gateBefore.get("clears_on")).update());
    }

    record Admit(UUID app, UUID account, UUID candidate, UUID student, String admissionNo, String token) { }

    /** an applicant offered a place in the session, the offer read and accepted (no screening for the session), and on the register */
    Admit admit(String ses, String tag) {
        int n = new Random().nextInt(90_000_000) + 10_000_000;
        String jamb = ses.substring(0, 4) + n + "PG";
        return it.db(() -> {
            UUID cand = UUID.randomUUID(), acct = UUID.randomUUID(), app = UUID.randomUUID(), batch = UUID.randomUUID();
            jdbc.sql("INSERT INTO admissions.caps_batch (id, session, source, filename, file_sha256, rows_read, list_kind, downloaded_on, uploaded_by, uploaded_office, committed_at) VALUES (:id, :s, 'CAPS_DOWNLOAD', 'gate.xlsx', decode(md5(random()::text) || md5(random()::text), 'hex'), 1, 'UTME', current_date, gen_random_uuid(), 'academic', now())")
                    .param("id", batch).param("s", ses).update();
            jdbc.sql("INSERT INTO admissions.caps_row (id, batch_id, session, jamb_reg_no, raw, surname, other_names, jamb_code, aggregate, entry_mode, sex) VALUES (gen_random_uuid(), :b, :s, :j, '{}'::jsonb, :sn, 'Gate Person', :p, 250, 'UTME', 'F')")
                    .param("b", batch).param("s", ses).param("j", jamb).param("sn", "ZZGATE-" + tag + "-" + n).param("p", CS).update();
            jdbc.sql("INSERT INTO admissions.candidate (id, session, jamb_reg_no, surname, other_names, programme, entry_mode, entry_level, offer_state, admitted_from) VALUES (:id, :s, :j, :sn, 'Gate Person', (SELECT name FROM ref.programme WHERE code = :p), 'UTME', 100, 'ADMITTED', (SELECT id FROM admissions.caps_row WHERE session = :s AND jamb_reg_no = :j))")
                    .param("id", cand).param("s", ses).param("j", jamb).param("sn", "ZZGATE-" + tag + "-" + n).param("p", CS).update();
            jdbc.sql("INSERT INTO admissions.applicant_account (id, session, candidate_id, jamb_key, email, phone, password_hash) VALUES (:id, :s, :c, :k, :e, '08030000000', crypt('gate-password-1', gen_salt('bf', 12)))")
                    .param("id", acct).param("s", ses).param("c", cand).param("k", jamb).param("e", jamb.toLowerCase() + "@example.com").update();
            jdbc.sql("INSERT INTO admissions.application (id, account_id, candidate_id, session, application_no, fee_confirmed_at, submitted_at, decision, decided_at, decision_released_at, status_checked_at, undertaking_at, acceptance_confirmed_at, accepted_at) VALUES (:id, :a, :c, :s, :no, now(), now(), 'OFFERED', now(), now(), now(), now(), now(), now())")
                    .param("id", app).param("a", acct).param("c", cand).param("s", ses).param("no", "APP/" + ses.substring(2, 4) + "/" + String.format("%06d", n % 1_000_000)).update();
            UUID student = jdbc.sql("SELECT people.intake_one(:c)").param("c", cand).query(UUID.class).single();
            String adm = jdbc.sql("SELECT admission_no FROM people.student WHERE id = :s").param("s", student).query(String.class).single();
            return new Admit(app, acct, cand, student, adm, TestTokens.token(acct, List.of("applicant")));
        });
    }

    void gate(Boolean enabled, String from, String clearsOn, String why) {
        Map<String, Object> body = new java.util.LinkedHashMap<>();
        if (enabled != null) body.put("enabled", enabled);
        if (from != null) body.put("fromSession", from);
        if (clearsOn != null) body.put("clearsOn", clearsOn);
        body.put("reason", why);
        ResponseEntity<Map> r = it.call(bursar, HttpMethod.PUT, "/api/v1/finance/portal-gate", body);
        assertThat(r.getStatusCode().value()).as(String.valueOf(r.getBody())).isEqualTo(200);
    }

    Map<String, Object> fees(Admit a) {
        ResponseEntity<Map> r = it.get(a.token(), "/api/v1/applicant/me/school-fees");
        assertThat(r.getStatusCode().value()).as(String.valueOf(r.getBody())).isEqualTo(200);
        return r.getBody();
    }

    String state(Admit a) {
        return jdbc.sql("SELECT finance.portal_access_state(:s)").param("s", a.student()).query(String.class).single();
    }

    void confirm(String reference) {
        it.db(() -> jdbc.sql("SELECT finance.confirm_payment(:r, 'Card', 'PortalFeeGateIT')").param("r", reference).query().singleRow());
    }

    @Test
    void aFreshAdmitIsHeldOutOfTheStudentPortalUntilTheFirstSemestersFeesArePaid() {
        // the gate on, from this session, cleared by the first semester's fees (as the University chose on 11 November 2026)
        assertThat(it.call(academic, HttpMethod.PUT, "/api/v1/finance/portal-gate", Map.of("enabled", true, "reason", "not mine")).getStatusCode().value()).isEqualTo(403);
        gate(true, session, "FIRST_SEMESTER", "PortalFeeGateIT: on for the test's session");
        Map<String, Object> view = it.get(bursar, "/api/v1/finance/portal-gate").getBody();
        assertThat(view.get("enabled")).isEqualTo(true);
        assertThat(view.get("fromSession")).isEqualTo(session);
        assertThat(view.get("clearsOn")).isEqualTo("FIRST_SEMESTER");

        Admit a = admit(session, "A");
        Admit other = admit(session, "B");
        // 1 · no fee stated: held, told so at the hand-off; the applicant dashboard says the fees are not yet available
        assertThat(state(a)).isEqualTo("HELD_FEES_NOT_AVAILABLE");
        ResponseEntity<Map> handOff = it.call(a.token(), HttpMethod.POST, "/api/v1/student-auth/continue", Map.of());
        assertThat(handOff.getStatusCode().value()).isEqualTo(422);
        assertThat(handOff.getBody().get("code")).isEqualTo("STUDENT_PORTAL_FEES_NOT_AVAILABLE");
        Map<String, Object> f = fees(a);
        assertThat(f.get("onRegister")).isEqualTo(true);
        assertThat(f.get("state")).isEqualTo("NOT_CONFIGURED");
        assertThat(f.get("portalState")).isEqualTo("HELD_FEES_NOT_AVAILABLE");
        assertThat(jdbc.sql("SELECT status FROM admissions.admission_status(:a)").param("a", a.app()).query(String.class).single()).isEqualTo("SCHOOL_FEES_NOT_AVAILABLE");
        // nothing is charged at a guess
        assertThat(it.call(a.token(), HttpMethod.POST, "/api/v1/applicant/me/school-fees/references", Map.of("amount", 1000)).getStatusCode().value()).isEqualTo(422);

        // 2 · the Bursary states the programme's fees by semester: payable from the applicant dashboard, still held
        it.db(() -> jdbc.sql("""
                INSERT INTO finance.fee_schedule (session, item, amount, level, programme_code, semester) VALUES
                    (:s, 'PortalFeeGateIT: school fees (semester 1)', 120000.00, 100, :p, 1),
                    (:s, 'PortalFeeGateIT: school fees (semester 2)', 60000.00, 100, :p, 2)
                """).param("s", session).param("p", CS).update());
        f = fees(a);
        assertThat(f.get("state")).isEqualTo("AVAILABLE");
        assertThat(new BigDecimal(String.valueOf(f.get("due")))).isEqualByComparingTo("180000");
        assertThat(new BigDecimal(String.valueOf(f.get("dueFirstSemester")))).isEqualByComparingTo("120000");
        assertThat(f.get("portalState")).isEqualTo("HELD_FEES_UNPAID");
        assertThat(m(f.get("gate")).get("clearsOn")).isEqualTo("FIRST_SEMESTER");
        ResponseEntity<Map> held = it.call(a.token(), HttpMethod.POST, "/api/v1/student-auth/continue", Map.of());
        assertThat(held.getStatusCode().value()).isEqualTo(422);
        assertThat(held.getBody().get("code")).isEqualTo("STUDENT_PORTAL_HELD_FEES");
        Map<String, Object> st = jdbc.sql("SELECT status, next_href FROM admissions.admission_status(:a)").param("a", a.app()).query().singleRow();
        assertThat(st.get("status")).isEqualTo("SCHOOL_FEES_PENDING");
        assertThat(st.get("next_href")).isEqualTo("/applicant/admission#fees");
        // the sign-in on the admission number: a wrong password learns nothing of the gate; the right one is told it
        ResponseEntity<Map> wrong = it.anon(HttpMethod.POST, "/api/v1/student-auth/sign-in", Map.of("matricNo", a.admissionNo(), "password", "not-the-password"));
        assertThat(wrong.getBody().get("code")).isEqualTo("AUTH_BAD_CREDENTIALS");
        ResponseEntity<Map> right = it.anon(HttpMethod.POST, "/api/v1/student-auth/sign-in", Map.of("matricNo", a.admissionNo(), "password", "gate-password-1"));
        assertThat(right.getStatusCode().value()).isEqualTo(422);
        assertThat(right.getBody().get("code")).isEqualTo("STUDENT_PORTAL_HELD_FEES");
        assertThat(jdbc.sql("SELECT count(*) FROM iam.student_account WHERE student_id = :s").param("s", a.student()).query(Long.class).single()).isZero();

        // 3 · the first semester paid from the applicant dashboard: a reference the applicant token owns, nobody else's
        assertThat(it.call(a.token(), HttpMethod.POST, "/api/v1/applicant/me/school-fees/references", Map.of("amount", 999999)).getStatusCode().value()).isEqualTo(422);
        ResponseEntity<Map> drawn = it.call(a.token(), HttpMethod.POST, "/api/v1/applicant/me/school-fees/references", Map.of("amount", 120000));
        assertThat(drawn.getStatusCode().value()).as(String.valueOf(drawn.getBody())).isEqualTo(200);
        String ref = String.valueOf(drawn.getBody().get("reference"));
        assertThat(ref).startsWith("MOAUM-FEE-");
        assertThat(jdbc.sql("SELECT student_id FROM finance.payment_reference WHERE reference = :r").param("r", ref).query(UUID.class).single()).isEqualTo(a.student());
        assertThat(it.call(other.token(), HttpMethod.POST, "/api/v1/payments/checkout", Map.of("reference", ref)).getStatusCode().value()).isEqualTo(404);
        assertThat(it.call(a.token(), HttpMethod.POST, "/api/v1/payments/checkout", Map.of("reference", ref)).getStatusCode().value()).isNotEqualTo(404);
        assertThat(fees(a).get("state")).isEqualTo("PAYMENT_PENDING");
        assertThat(state(a)).isEqualTo("HELD_FEES_UNPAID");   // pending is not paid
        confirm(ref);
        f = fees(a);
        assertThat(f.get("state")).isEqualTo("PART_PAID");
        assertThat(f.get("firstSemesterCleared")).isEqualTo(true);
        assertThat(f.get("portalState")).isEqualTo("CLEARED");
        assertThat(jdbc.sql("SELECT status FROM admissions.admission_status(:a)").param("a", a.app()).query(String.class).single()).isEqualTo("SCHOOL_FEES_PART_PAID");
        ResponseEntity<Map> crossed = it.call(a.token(), HttpMethod.POST, "/api/v1/student-auth/continue", Map.of());
        assertThat(crossed.getStatusCode().value()).as(String.valueOf(crossed.getBody())).isEqualTo(200);
        String student = String.valueOf(crossed.getBody().get("token"));
        ResponseEntity<Map> me = it.get(student, "/api/v1/me");
        assertThat(me.getStatusCode().value()).isEqualTo(200);
        assertThat(me.getHeaders().getFirst("X-Portal-Access")).isEqualTo("CLEARED");
        assertThat(it.get(student, "/api/v1/me/results").getStatusCode().value()).isNotEqualTo(403);

        // 4 · the Bursar sets the rule to the session in full: the student portal answers 403 but on the record, the notices and the fees
        gate(null, null, "PAID_IN_FULL", "PortalFeeGateIT: in full");
        ResponseEntity<Map> refused = it.get(student, "/api/v1/me/results");
        assertThat(refused.getStatusCode().value()).isEqualTo(403);
        assertThat(refused.getBody().get("code")).isEqualTo("STUDENT_PORTAL_HELD_FEES");
        assertThat(refused.getHeaders().getFirst("X-Portal-Access")).isEqualTo("HELD_FEES_UNPAID");
        ResponseEntity<Map> stillMe = it.get(student, "/api/v1/me");
        assertThat(stillMe.getStatusCode().value()).isEqualTo(200);
        assertThat(stillMe.getHeaders().getFirst("X-Portal-Access")).isEqualTo("HELD_FEES_UNPAID");
        // the record as every screen but the dashboard reads it says where the record stands too: the portal sends the student on
        ResponseEntity<Map> core = it.get(student, "/api/v1/me?view=core");
        assertThat(core.getStatusCode().value()).isEqualTo(200);
        assertThat(core.getBody().get("portalAccess")).isEqualTo("HELD_FEES_UNPAID");
        assertThat(core.getBody()).doesNotContainKey("fees");
        assertThat(it.get(student, "/api/v1/me/fees").getStatusCode().value()).isEqualTo(200);
        // an exception from the Bursary (not the Academic Office) lets the student through until it is revoked
        Map<String, Object> exc = Map.of("admissionNo", a.admissionNo(), "basis", "INSTALMENT_POLICY", "reason", "PortalFeeGateIT: the Bursar's instalment arrangement",
                "expiresAt", OffsetDateTime.now().plusDays(30).toString());
        assertThat(it.call(academic, HttpMethod.POST, "/api/v1/finance/portal-gate/exceptions", exc).getStatusCode().value()).isEqualTo(403);
        ResponseEntity<Map> granted = it.call(bursar, HttpMethod.POST, "/api/v1/finance/portal-gate/exceptions", exc);
        assertThat(granted.getStatusCode().value()).as(String.valueOf(granted.getBody())).isEqualTo(200);
        assertThat(it.get(student, "/api/v1/me/results").getStatusCode().value()).isNotEqualTo(403);
        assertThat(it.call(bursar, HttpMethod.DELETE, "/api/v1/finance/portal-gate/exceptions/" + granted.getBody().get("id") + "?reason=done", null).getStatusCode().value()).isEqualTo(200);
        assertThat(it.get(student, "/api/v1/me/results").getStatusCode().value()).isEqualTo(403);
        // the balance paid: cleared on the session in full
        String rest = String.valueOf(it.call(a.token(), HttpMethod.POST, "/api/v1/applicant/me/school-fees/references", Map.of("amount", 60000)).getBody().get("reference"));
        confirm(rest);
        assertThat(state(a)).isEqualTo("CLEARED");
        assertThat(it.get(student, "/api/v1/me/results").getStatusCode().value()).isNotEqualTo(403);

        // 5 · the monitors and the readiness check count the student and the programme
        Map<String, Object> summary = it.get(bursar, "/api/v1/finance/sessions/" + year + "/" + (year + 1) + "/intake-fees/summary").getBody();
        assertThat(((Number) summary.get("freshers")).intValue()).isGreaterThanOrEqualTo(2);
        Map<String, Object> coverage = it.get(bursar, "/api/v1/finance/sessions/" + year + "/" + (year + 1) + "/intake-fees/coverage").getBody();
        assertThat(l(coverage.get("rows")).stream().anyMatch(r -> CS.equals(r.get("programmeCode")) && "UTME".equals(r.get("entryMode")) && Boolean.TRUE.equals(r.get("covered")))).isTrue();
        assertThat(String.valueOf(it.get(ict, "/api/v1/platform/readiness").getBody())).contains("intake_fee_schedule");

        // 6 · an earlier cohort and a matriculated student are never held; the gate off, nobody is
        Admit before = admit((year - 1) + "/" + year, "E");
        assertThat(state(before)).isEqualTo("OPEN");
        it.db(() -> jdbc.sql("UPDATE people.student SET matric_no = 'MOAUM/CS/' || right(:y, 2) || '/9' || right(admission_no, 5), status = 'ACTIVE', matriculated_at = now() WHERE id = :s")
                .param("y", String.valueOf(year)).param("s", other.student()).update());
        assertThat(state(other)).isEqualTo("OPEN");
        Admit c = admit(session, "C");
        assertThat(state(c)).isEqualTo("HELD_FEES_UNPAID");
        gate(false, null, null, "PortalFeeGateIT: off");
        assertThat(state(c)).isEqualTo("OPEN");
        assertThat(it.call(c.token(), HttpMethod.POST, "/api/v1/student-auth/continue", Map.of()).getStatusCode().value()).isEqualTo(200);
    }

    @SuppressWarnings("unchecked")
    static Map<String, Object> m(Object o) { return (Map<String, Object>) o; }
    @SuppressWarnings("unchecked")
    static List<Map<String, Object>> l(Object o) { return (List<Map<String, Object>>) o; }
}
