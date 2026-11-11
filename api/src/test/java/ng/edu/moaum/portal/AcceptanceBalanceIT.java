package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.math.BigDecimal;
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
 * V724 — the acceptance fee revised after part of it was paid, through the API: an applicant pays the acceptance fee as stated
 * (₦25,000) and prints the letter; the Bursary revises the fee to ₦35,000 (kept, with the figure before and the reason); the
 * applicant owes ₦10,000 — the entitlement and the applicant view say so, the letter is withheld (the API and the documents
 * centre), and the reference drawn is for the balance alone, the same one on a second request; paid, the acceptance is settled,
 * the same letter opens again and no further acceptance reference is drawn. An applicant who pays after the revision pays ₦35,000
 * once. The acceptance fee monitor bands both and the one who has paid nothing.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT,
        properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
class AcceptanceBalanceIT {

    static final String CS = "C00023";

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    ItSupport it;
    final String bursar = ItSupport.token("bursar");
    final String housing = ItSupport.token("housing");
    String session;
    String path;
    int year;
    Map<String, Object> gateBefore;

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
        year = it.freeYear(2066, 2072);
        session = year + "/" + (year + 1);
        path = "/api/v1/admissions/sessions/" + year + "/" + (year + 1);
        it.session(session, year);
        gateBefore = jdbc.sql("SELECT enabled, from_session, clears_on FROM finance.portal_fee_gate WHERE id = 1").query().singleRow();
        it.db(() -> jdbc.sql("INSERT INTO admissions.applicant_fee (session, application_fee, portal_charge, acceptance_fee, checking_fee) VALUES (:s, 2000, 0, 25000, 3000) ON CONFLICT (session) DO UPDATE SET acceptance_fee = 25000")
                .param("s", session).update());
    }

    @AfterEach
    void putTheGateBack() {
        it.db(() -> jdbc.sql("UPDATE finance.portal_fee_gate SET enabled = :e, from_session = :f, clears_on = :c, reason = 'AcceptanceBalanceIT: put back as found' WHERE id = 1")
                .param("e", gateBefore.get("enabled")).param("f", gateBefore.get("from_session")).param("c", gateBefore.get("clears_on")).update());
    }

    String portalState(UUID student) {
        return jdbc.sql("SELECT finance.portal_access_state(:s)").param("s", student).query(String.class).single();
    }

    record Applicant(UUID app, String applicationNo, String token) { }

    /** an applicant offered a place, the offer read through Admission Status Checking (the checking fee paid) */
    Applicant offered(String tag) {
        int n = new Random().nextInt(90_000_000) + 10_000_000;
        String jamb = session.substring(0, 4) + n + "AB";
        String no = "APP/" + session.substring(2, 4) + "/" + String.format("%06d", n % 1_000_000);
        return it.db(() -> {
            UUID cand = UUID.randomUUID(), acct = UUID.randomUUID(), app = UUID.randomUUID(), batch = UUID.randomUUID();
            jdbc.sql("INSERT INTO admissions.caps_batch (id, session, source, filename, file_sha256, rows_read, list_kind, downloaded_on, uploaded_by, uploaded_office, committed_at) VALUES (:id, :s, 'CAPS_DOWNLOAD', 'balance.xlsx', decode(md5(random()::text) || md5(random()::text), 'hex'), 1, 'UTME', current_date, gen_random_uuid(), 'academic', now())")
                    .param("id", batch).param("s", session).update();
            jdbc.sql("INSERT INTO admissions.caps_row (id, batch_id, session, jamb_reg_no, raw, surname, other_names, jamb_code, aggregate, entry_mode, sex) VALUES (gen_random_uuid(), :b, :s, :j, '{}'::jsonb, :sn, 'Balance Person', :p, 250, 'UTME', 'M')")
                    .param("b", batch).param("s", session).param("j", jamb).param("sn", "ZZBAL-" + tag + "-" + n).param("p", CS).update();
            jdbc.sql("INSERT INTO admissions.candidate (id, session, jamb_reg_no, surname, other_names, programme, entry_mode, entry_level, offer_state, admitted_from) VALUES (:id, :s, :j, :sn, 'Balance Person', (SELECT name FROM ref.programme WHERE code = :p), 'UTME', 100, 'ADMITTED', (SELECT id FROM admissions.caps_row WHERE session = :s AND jamb_reg_no = :j))")
                    .param("id", cand).param("s", session).param("j", jamb).param("sn", "ZZBAL-" + tag + "-" + n).param("p", CS).update();
            jdbc.sql("INSERT INTO admissions.applicant_account (id, session, candidate_id, jamb_key, email, phone, password_hash) VALUES (:id, :s, :c, :k, :e, '08030000000', crypt('x', gen_salt('bf', 12)))")
                    .param("id", acct).param("s", session).param("c", cand).param("k", jamb).param("e", jamb.toLowerCase() + "@example.com").update();
            jdbc.sql("INSERT INTO admissions.application (id, account_id, candidate_id, session, application_no, fee_confirmed_at, submitted_at, decision, decided_at, decision_released_at, checking_confirmed_at, status_checked_at) VALUES (:id, :a, :c, :s, :no, now(), now(), 'OFFERED', now(), now(), now(), now())")
                    .param("id", app).param("a", acct).param("c", cand).param("s", session).param("no", no).update();
            return new Applicant(app, no, TestTokens.token(acct, List.of("applicant")));
        });
    }

    String reference(Applicant a) {
        ResponseEntity<Map> r = it.call(a.token(), HttpMethod.POST, "/api/v1/applicant/me/fee-references", Map.of("kind", "ACCEPTANCE"));
        assertThat(r.getStatusCode().value()).as(String.valueOf(r.getBody())).isEqualTo(200);
        return String.valueOf(r.getBody().get("reference"));
    }

    BigDecimal amount(String reference) {
        return jdbc.sql("SELECT amount FROM admissions.fee_reference WHERE reference = :r").param("r", reference).query(BigDecimal.class).single();
    }

    void confirm(String reference) {
        ResponseEntity<Map> c = it.call(bursar, HttpMethod.POST, path + "/fee-references/" + reference + "/confirm", Map.of("channel", "Card"));
        assertThat(c.getStatusCode().value()).as(String.valueOf(c.getBody())).isEqualTo(200);
    }

    Map<String, Object> entitlement(Applicant a) {
        return m(m(it.get(a.token(), "/api/v1/applicant/me/admission").getBody()).get("entitlement"));
    }

    @Test
    void aFeeRevisedAfterAPartPaymentLeavesTheBalanceOwedNeverTheWholeFeeAgain() {
        Applicant a = offered("A");
        Applicant b = offered("B");
        Applicant c = offered("C");

        // the acceptance as the fee stood: ₦25,000, the undertaking, the letter
        assertThat(it.call(a.token(), HttpMethod.POST, "/api/v1/applicant/me/accept", Map.of("undertaking", true)).getStatusCode().value()).isEqualTo(200);
        String first = reference(a);
        assertThat(amount(first)).isEqualByComparingTo("25000");
        confirm(first);
        Map<String, Object> letter = m(it.get(a.token(), "/api/v1/applicant/me/letter").getBody());
        assertThat(String.valueOf(letter.get("number"))).matches("ADM/\\d{4}/\\d{6}");
        assertThat(it.call(a.token(), HttpMethod.POST, "/api/v1/applicant/me/fee-references", Map.of("kind", "ACCEPTANCE")).getBody().get("code")).isEqualTo("ACCEPTANCE_SETTLED");

        // the Bursary revises the acceptance fee to ₦35,000: the statement kept, with the figure before and the request's reason (X-Reason;
        // the test client sends "integration test")
        ResponseEntity<Map> revised = it.call(bursar, HttpMethod.PUT, path + "/applicant-fees",
                Map.of("applicationFee", 2000, "portalCharge", 0, "acceptanceFee", 35000, "checkingFee", 3000));
        assertThat(revised.getStatusCode().value()).as(String.valueOf(revised.getBody())).isEqualTo(200);
        Map<String, Object> kept = jdbc.sql("SELECT count(*) AS n, max(previous_acceptance_fee) AS before, max(reason) FILTER (WHERE previous_acceptance_fee IS NOT NULL) AS why FROM admissions.applicant_fee_revision WHERE session = :s")
                .param("s", session).query().singleRow();
        assertThat(((Number) kept.get("n")).intValue()).isEqualTo(2);
        assertThat((BigDecimal) kept.get("before")).isEqualByComparingTo("25000");
        assertThat(kept.get("why")).isEqualTo("integration test");

        // ₦10,000 owed: the entitlement, the applicant view, the letter withheld (the API and the documents centre)
        Map<String, Object> e = entitlement(a);
        assertThat(e.get("paid")).isEqualTo(true);
        assertThat(e.get("settled")).isEqualTo(false);
        assertThat(e.get("balance_due")).isEqualTo(true);
        assertThat(new BigDecimal(String.valueOf(e.get("fee_due")))).isEqualByComparingTo("35000");
        assertThat(new BigDecimal(String.valueOf(e.get("paid_total")))).isEqualByComparingTo("25000");
        assertThat(new BigDecimal(String.valueOf(e.get("balance")))).isEqualByComparingTo("10000");
        Map<String, Object> acceptance = m(it.get(a.token(), "/api/v1/applicant/me").getBody().get("acceptance"));
        assertThat(new BigDecimal(String.valueOf(acceptance.get("balance")))).isEqualByComparingTo("10000");
        ResponseEntity<Map> withheld = it.get(a.token(), "/api/v1/applicant/me/letter");
        assertThat(withheld.getStatusCode().value()).isEqualTo(422);
        assertThat(withheld.getBody().get("code")).isEqualTo("ACCEPTANCE_BALANCE_DUE");
        Map<String, Object> offerLetter = l(it.get(a.token(), "/api/v1/applicant/me/documents-centre").getBody().get("rows")).stream()
                .filter(x -> "OFFER_LETTER".equals(x.get("key"))).findFirst().orElseThrow();
        assertThat(offerLetter.get("status")).isEqualTo("PENDING");

        // the student portal's fee gate on for the session: the acceptance balance holds the student before the school fees (the brief's
        // "acceptance fee partially paid: pay the outstanding balance; no access") — the hand-off says so, the status says so, no school-fee
        // reference is drawn, and the letter is withheld at the student's own documents door too
        ResponseEntity<Map> on = it.call(bursar, HttpMethod.PUT, "/api/v1/finance/portal-gate", Map.of("enabled", true, "fromSession", session, "clearsOn", "FIRST_SEMESTER", "reason", "AcceptanceBalanceIT: on for the session"));
        assertThat(on.getStatusCode().value()).as(String.valueOf(on.getBody())).isEqualTo(200);
        UUID student = jdbc.sql("SELECT s.id FROM people.student s JOIN admissions.application ap ON ap.candidate_id = s.candidate_id WHERE ap.id = :a").param("a", a.app()).query(UUID.class).single();
        assertThat(portalState(student)).isEqualTo("HELD_ACCEPTANCE_BALANCE");
        assertThat(jdbc.sql("SELECT status FROM admissions.admission_status(:a)").param("a", a.app()).query(String.class).single()).isEqualTo("ACCEPTANCE_BALANCE_PENDING");
        ResponseEntity<Map> held = it.call(a.token(), HttpMethod.POST, "/api/v1/student-auth/continue", Map.of());
        assertThat(held.getStatusCode().value()).isEqualTo(422);
        assertThat(held.getBody().get("code")).isEqualTo("STUDENT_PORTAL_ACCEPTANCE_BALANCE");
        assertThat(it.get(a.token(), "/api/v1/applicant/me/school-fees").getBody().get("acceptanceBalanceDue")).isEqualTo(true);
        assertThat(it.call(a.token(), HttpMethod.POST, "/api/v1/applicant/me/school-fees/references", Map.of("amount", 1000)).getBody().get("code")).isEqualTo("ACCEPTANCE_BALANCE_DUE");
        UUID issued = jdbc.sql("SELECT id FROM credentials.issued WHERE application_id = :a AND kind = 'ADMISSION_LETTER' ORDER BY version DESC LIMIT 1").param("a", a.app()).query(UUID.class).single();
        ResponseEntity<Map> through = it.call(bursar, HttpMethod.POST, "/api/v1/finance/portal-gate/exceptions", Map.of("studentId", student, "basis", "BURSARY_DECISION",
                "reason", "AcceptanceBalanceIT: past the gate to read the letter", "expiresAt", java.time.OffsetDateTime.now().plusDays(2).toString()));
        assertThat(through.getStatusCode().value()).as(String.valueOf(through.getBody())).isEqualTo(200);
        ResponseEntity<Map> doc = it.get(TestTokens.token(student, List.of("student")), "/api/v1/me/documents/" + issued);
        assertThat(doc.getStatusCode().value()).isEqualTo(422);
        assertThat(doc.getBody().get("code")).isEqualTo("ACCEPTANCE_BALANCE_DUE");
        assertThat(it.call(bursar, HttpMethod.DELETE, "/api/v1/finance/portal-gate/exceptions/" + through.getBody().get("id") + "?reason=done", null).getStatusCode().value()).isEqualTo(200);

        // the balance alone, on one reference: the same again on a second request
        String balance = reference(a);
        assertThat(amount(balance)).isEqualByComparingTo("10000");
        assertThat(jdbc.sql("SELECT stated_fee FROM admissions.fee_reference WHERE reference = :r").param("r", balance).query(BigDecimal.class).single()).isEqualByComparingTo("35000");
        assertThat(reference(a)).isEqualTo(balance);
        confirm(balance);
        e = entitlement(a);
        assertThat(e.get("settled")).isEqualTo(true);
        assertThat(new BigDecimal(String.valueOf(e.get("balance")))).isEqualByComparingTo("0");
        assertThat(((Number) e.get("payments")).intValue()).isEqualTo(2);
        assertThat(m(it.get(a.token(), "/api/v1/applicant/me/letter").getBody()).get("number")).isEqualTo(letter.get("number"));
        assertThat(it.call(a.token(), HttpMethod.POST, "/api/v1/applicant/me/fee-references", Map.of("kind", "ACCEPTANCE")).getBody().get("code")).isEqualTo("ACCEPTANCE_SETTLED");
        // the balance paid, the gate moves on to the school fees (none stated for the session); the balance, had it been confirmed in error,
        // could be reversed by the Bursary — the payment the acceptance rests on cannot
        assertThat(portalState(student)).isEqualTo("HELD_FEES_NOT_AVAILABLE");
        assertThat(jdbc.sql("SELECT reversible FROM admissions.fee_reversal_check(:r)").param("r", balance).query(Boolean.class).single()).isTrue();
        assertThat(jdbc.sql("SELECT reversible FROM admissions.fee_reversal_check(:r)").param("r", first).query(Boolean.class).single()).isFalse();

        // an applicant who pays after the revision pays ₦35,000, once
        assertThat(it.call(b.token(), HttpMethod.POST, "/api/v1/applicant/me/accept", Map.of("undertaking", true)).getStatusCode().value()).isEqualTo(200);
        String full = reference(b);
        assertThat(amount(full)).isEqualByComparingTo("35000");
        confirm(full);
        assertThat(entitlement(b).get("settled")).isEqualTo(true);
        assertThat(it.get(b.token(), "/api/v1/applicant/me/letter").getStatusCode().value()).isEqualTo(200);

        // the acceptance fee monitor: one settled in parts, one paid in full, one not paid; ₦35,000 outstanding; the Bursary reads it, housing does not
        assertThat(it.get(housing, path + "/acceptance-fees/summary").getStatusCode().value()).isEqualTo(403);
        ResponseEntity<Map> summary = it.get(bursar, path + "/acceptance-fees/summary");
        assertThat(summary.getStatusCode().value()).as(String.valueOf(summary.getBody())).isEqualTo(200);
        Map<String, Object> s = summary.getBody();
        assertThat(((Number) s.get("offers")).intValue()).isEqualTo(3);
        assertThat(((Number) s.get("settledInParts")).intValue()).isEqualTo(1);
        assertThat(((Number) s.get("paidInFull")).intValue()).isEqualTo(1);
        assertThat(((Number) s.get("notPaid")).intValue()).isEqualTo(1);
        assertThat(new BigDecimal(String.valueOf(s.get("outstanding")))).isEqualByComparingTo("35000");
        List<Map<String, Object>> parts = l(it.get(bursar, path + "/acceptance-fees?band=SETTLED_IN_PARTS").getBody().get("rows"));
        assertThat(parts).extracting(r -> r.get("applicationNo")).containsExactly(a.applicationNo());
        List<Map<String, Object>> owing = l(it.get(bursar, path + "/acceptance-fees?band=NOT_PAID").getBody().get("rows"));
        assertThat(owing).extracting(r -> r.get("applicationNo")).containsExactly(c.applicationNo());
    }

    @SuppressWarnings("unchecked")
    static Map<String, Object> m(Object o) { return (Map<String, Object>) o; }
    @SuppressWarnings("unchecked")
    static List<Map<String, Object>> l(Object o) { return (List<Map<String, Object>>) o; }
}
