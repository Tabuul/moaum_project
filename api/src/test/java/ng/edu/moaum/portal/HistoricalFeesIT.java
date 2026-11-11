package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.math.BigDecimal;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
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
 * V654: historical school fees and the graduate's financial clearance, through the API. An invented graduate of Computer Science
 * (today 400 Level) admitted three far-future sessions back: the first session states 100 Level lines and a 400 Level line never
 * theirs then, the second a 200 Level whole-session line, the third nothing; part paid. The account reads each session at its level;
 * the third session is for review. The Students Account Officer assesses it from the fee circular and submits it, with evidence;
 * the officer cannot decide it, nor can the same person acting as Bursar; another Bursar approves it. The graduate sees the official
 * amounts (a semester still being assessed never as a debt) and pays part online, never more than owed. Audit and the Registry read,
 * a lecturer does not; the Registry cannot assess. The final clearance's Bursary stage is refused over the balance; the student stays
 * GRADUATED. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class HistoricalFeesIT {

    private static final String PATH = "/api/v1/finance/historical";

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    ItSupport it;
    final List<String> sessions = new ArrayList<>();

    /** the lines the test states are taken away (FeeLineLeakGuard) */
    @AfterEach
    void takeAwayFeeLines() {
        if (it != null && !sessions.isEmpty()) {
            it.db(() -> jdbc.sql("DELETE FROM finance.fee_schedule WHERE session = ANY (string_to_array(:s, ','))").param("s", String.join(",", sessions)).update());
        }
    }

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
    }

    private static Map<String, Object> period(List<Map<String, Object>> periods, String session, int semester) {
        return periods.stream().filter(p -> session.equals(p.get("session")) && Integer.valueOf(semester).equals(p.get("semester"))).findFirst().orElseThrow();
    }

    private static BigDecimal money(Object o) {
        return o == null ? null : new BigDecimal(String.valueOf(o));
    }

    @Test
    void aGraduatesHistoricalFeesAreAssessedApprovedPaidAndHoldTheFinancialClearance() {
        int y = it.freeYear(7000, 7400, 0, 3);
        for (int i = 0; i < 4; i++) {
            String s = (y + i) + "/" + (y + i + 1);
            it.session(s, y + i);
            sessions.add(s);
        }
        String s0 = sessions.get(0), s1 = sessions.get(1), s2 = sessions.get(2);
        String surname = it.freeSurname("ZZHISTFEES");
        UUID st = it.student(surname, "C00023", it.freeNumber("MOAUM/ADM/70/", 6), it.freeNumber("MOAUM/HFA/70/", 6), 400);
        UUID officerId = UUID.randomUUID();
        it.db(() -> {
            jdbc.sql("UPDATE people.student SET status = 'GRADUATED', entry_session = :e, entry_level = 100 WHERE id = :s").param("e", s0).param("s", st).update();
            jdbc.sql("""
                    INSERT INTO people.enrolment (id, student_id, session, level) VALUES (gen_random_uuid(), :s, :a, 100), (gen_random_uuid(), :s, :b, 200), (gen_random_uuid(), :s, :c, 300)
                    """).param("s", st).param("a", s0).param("b", s1).param("c", s2).update();
            jdbc.sql("""
                    INSERT INTO finance.fee_schedule (session, item, amount, level, programme_code, semester) VALUES
                        (:a, 'V654 IT fees', 50000, 100, 'C00023', 1), (:a, 'V654 IT fees', 50000, 100, 'C00023', 2),
                        (:a, 'V654 IT 400 Level fees', 999999, 400, 'C00023', 1), (:b, 'V654 IT fees', 80000, 200, 'C00023', NULL)
                    """).param("a", s0).param("b", s1).update();
            return jdbc.sql("""
                    INSERT INTO finance.payment_reference (student_id, session, reference, purpose, amount, expires_at, confirmed_at, confirmed_by, channel, receipt_no) VALUES
                        (:s, :a, :r1, 'School fees ' || :a, 70000, now(), now(), gen_random_uuid(), 'Bank branch', :r1),
                        (:s, :b, :r2, 'School fees ' || :b, 80000, now(), now(), gen_random_uuid(), 'Bank branch', :r2)
                    """).param("s", st).param("a", s0).param("b", s1).param("r1", "MOAUM-FEE-HFIT-" + y + "A").param("r2", "MOAUM-FEE-HFIT-" + y + "B").update();
        });
        String bursar = ItSupport.token("bursar");
        String officer = TestTokens.token(officerId, List.of("studentaccounts"));
        String sameAsBursar = TestTokens.token(officerId, List.of("bursar"));

        // the account: each session at the level of its session; the third for review
        Map<String, Object> acct = it.get(bursar, PATH + "/students/" + st).getBody();
        List<Map<String, Object>> periods = (List<Map<String, Object>>) acct.get("periods");
        assertThat(period(periods, s0, 1)).containsEntry("level", 100).containsEntry("status", "CLEARED");
        assertThat(money(period(periods, s0, 2).get("outstanding"))).isEqualByComparingTo("30000");
        assertThat(period(periods, s1, 1)).containsEntry("status", "CLEARED");
        assertThat(period(periods, s2, 1)).containsEntry("status", "REQUIRES_REVIEW").containsEntry("source", "NONE");
        assertThat(it.get(bursar, PATH + "/students?q=" + st).getBody().get("total")).isEqualTo(1);
        // owing and for review at once: counted with the outstanding (the overview's tile opens this list), its status the review
        assertThat(it.get(bursar, PATH + "/students?filter=OUTSTANDING&q=" + st).getBody().get("total")).isEqualTo(1);
        assertThat(it.get(bursar, PATH + "/students?filter=GRADUATED_OWING&q=" + st).getBody().get("total")).isEqualTo(1);
        assertThat(it.get(bursar, PATH + "/students?financial=HISTORICAL_FEE_REVIEW_REQUIRED&q=" + st).getBody().get("total")).isEqualTo(1);
        assertThat(it.get(bursar, PATH + "/students?filter=NO_OUTSTANDING&q=" + st).getBody().get("total")).isEqualTo(0);

        // who may: the Registry and Audit read, a lecturer does not; the Registry cannot assess; the officer cannot set the start
        assertThat(it.get(ItSupport.token("registrar"), PATH + "/figures").getStatusCode().value()).isEqualTo(200);
        assertThat(it.get(ItSupport.token("audit"), PATH + "/students/" + st).getStatusCode().value()).isEqualTo(200);
        assertThat(it.get(ItSupport.token("lecturer"), PATH + "/figures").getStatusCode().value()).isEqualTo(403);
        Map<String, Object> body = new HashMap<>(Map.of("studentId", st, "session", s2, "semester", 1, "amount", 90000, "source", "OFFICIAL_FEE_DOCUMENT",
                "sourceReference", "BUR/" + y + "/14 fee circular", "reason", "The fee circular for the session, the 300 Level rate", "submit", true));
        body.put("components", List.of(Map.of("item", "Tuition", "amount", 70000), Map.of("item", "Levies", "amount", 20000)));
        assertThat(it.call(ItSupport.token("registrar"), HttpMethod.POST, PATH + "/assessments", body).getStatusCode().value()).isEqualTo(403);
        assertThat(it.call(officer, HttpMethod.PUT, PATH + "/setting", Map.of("session", s0, "reason", "Officer tries to move the start")).getStatusCode().value()).isEqualTo(403);

        // the officer assesses and submits; a short reason is refused
        Map<String, Object> shortReason = new HashMap<>(body);
        shortReason.put("reason", "too short");
        ResponseEntity<Map> refused = it.call(officer, HttpMethod.POST, PATH + "/assessments", shortReason);
        assertThat(refused.getStatusCode().value()).isEqualTo(422);
        assertThat(refused.getBody()).containsEntry("code", "HFA_REASON");
        ResponseEntity<Map> made = it.call(officer, HttpMethod.POST, PATH + "/assessments", body);
        assertThat(made.getStatusCode().value()).as(String.valueOf(made.getBody())).isEqualTo(200);
        assertThat(made.getBody()).containsEntry("state", "PENDING_BURSAR_APPROVAL");
        String id = String.valueOf(made.getBody().get("id"));
        String reference = String.valueOf(made.getBody().get("reference"));
        assertThat(reference).matches("HFA/[0-9]{4}/[0-9]{6}");
        ResponseEntity<Map> ev = it.call(officer, HttpMethod.POST, PATH + "/assessments/" + id + "/evidence",
                Map.of("filename", "circular.png", "dataUrl", "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="));
        assertThat(ev.getStatusCode().value()).as(String.valueOf(ev.getBody())).isEqualTo(200);
        assertThat((List<?>) ev.getBody().get("evidence")).hasSize(1);
        assertThat((List<Map<String, Object>>) it.get(bursar, PATH + "/assessments?state=PENDING_BURSAR_APPROVAL").getBody().get("rows"))
                .anySatisfy(r -> assertThat(r).containsEntry("reference", reference));

        // the officer cannot decide; the same person acting as Bursar cannot; another Bursar approves
        assertThat(it.call(officer, HttpMethod.POST, PATH + "/assessments/" + id + "/decide", Map.of("decision", "APPROVE")).getStatusCode().value()).isEqualTo(403);
        ResponseEntity<Map> same = it.call(sameAsBursar, HttpMethod.POST, PATH + "/assessments/" + id + "/decide", Map.of("decision", "APPROVE"));
        assertThat(same.getStatusCode().value()).isEqualTo(422);
        assertThat(same.getBody()).containsEntry("code", "HFA_SAME_OFFICER");
        ResponseEntity<Map> approved = it.call(bursar, HttpMethod.POST, PATH + "/assessments/" + id + "/decide", Map.of("decision", "APPROVE", "note", "From the circular"));
        assertThat(approved.getStatusCode().value()).as(String.valueOf(approved.getBody())).isEqualTo(200);
        assertThat(approved.getBody()).containsEntry("state", "APPROVED");
        assertThat((List<?>) approved.getBody().get("events")).hasSizeGreaterThanOrEqualTo(4);
        periods = (List<Map<String, Object>>) it.get(bursar, PATH + "/students/" + st).getBody().get("periods");
        assertThat(period(periods, s2, 1)).containsEntry("source", "ASSESSMENT").containsEntry("status", "OUTSTANDING");

        // the graduate: the official amounts, a semester still being assessed never a debt; pays part online, never more than owed
        String student = TestTokens.token(st, List.of("student"));
        Map<String, Object> mine = it.get(student, "/api/v1/me/historical-fees").getBody();
        assertThat(mine).containsEntry("graduated", true);
        List<Map<String, Object>> my = (List<Map<String, Object>>) mine.get("periods");
        assertThat(period(my, s2, 2)).containsEntry("status", "BEING_ASSESSED");
        assertThat(period(my, s2, 2).get("assessed")).isNull();
        assertThat(money(period(my, s2, 1).get("outstanding"))).isEqualByComparingTo("90000");
        ResponseEntity<Map> above = it.call(student, HttpMethod.POST, "/api/v1/me/historical-fees/references", Map.of("session", s2, "amount", 999999));
        assertThat(above.getStatusCode().value()).isEqualTo(422);
        assertThat(above.getBody()).containsEntry("code", "HFA_PAY_AMOUNT");
        ResponseEntity<Map> ref = it.call(student, HttpMethod.POST, "/api/v1/me/historical-fees/references", Map.of("session", s2, "amount", 40000));
        assertThat(ref.getStatusCode().value()).as(String.valueOf(ref.getBody())).isEqualTo(200);
        String paying = String.valueOf(ref.getBody().get("reference"));
        assertThat(jdbc.sql("SELECT purpose FROM finance.payment_reference WHERE reference = :r").param("r", paying).query(String.class).single())
                .isEqualTo("School fees " + s2 + " (historical)");

        // the final clearance's Bursary stage is refused over the balance; the student stays GRADUATED
        UUID process = it.db(() -> jdbc.sql("SELECT clearance.start('FINAL', :s, :ses, 'OVERRIDE', 'V654 IT: the final clearance', gen_random_uuid(), 'registrar')")
                .param("s", st).param("ses", s2).query(UUID.class).single());
        String blocker = jdbc.sql("SELECT clearance.blocker(:p, 'BURSARY', clearance.evidence(:p, 'BURSARY'))").param("p", process).query(String.class).single();
        assertThat(blocker).startsWith("Not cleared — outstanding school fees");
        assertThat(jdbc.sql("SELECT status FROM people.student WHERE id = :s").param("s", st).query(String.class).single()).isEqualTo("GRADUATED");
    }

    /**
     * V665: an approved graduand's account before the Bursar's final clearance. The officer's waiver above what is owed is refused; one
     * within it, with its evidence, awaits the Bursar, who alone approves it — the period owes less. A reconciliation run over the
     * graduand's programme and session reads them owing. The Bursary's clearance is refused over the balance; paid in full, another
     * Bursar officer's clearance graduates the graduand in the same act, and the student sees the waiver in their own account.
     */
    @Test
    void aWaiverAndAReconciliationRunBeforeTheBursarsFinalClearanceGraduatesTheGraduand() {
        int y = it.freeYear(7400, 7800, 0, 1);
        String s0 = y + "/" + (y + 1);
        it.session(s0, y);
        sessions.add(s0);
        String surname = it.freeSurname("ZZHFWAIVE");
        UUID st = it.student(surname, "C00023", it.freeNumber("MOAUM/ADM/74/", 6), it.freeNumber("MOAUM/HFW/74/", 6), 400);
        String approved = it.db(() -> {
            jdbc.sql("UPDATE people.student SET entry_session = :e, entry_level = 400 WHERE id = :s").param("e", s0).param("s", st).update();
            jdbc.sql("INSERT INTO people.enrolment (id, student_id, session, level) VALUES (gen_random_uuid(), :s, :a, 400)").param("s", st).param("a", s0).update();
            jdbc.sql("INSERT INTO finance.fee_schedule (session, item, amount, level, programme_code, semester) VALUES (:a, 'V665 IT fees', 100000, 400, 'C00023', NULL)")
                    .param("a", s0).update();
            jdbc.sql("""
                    INSERT INTO finance.payment_reference (student_id, session, reference, purpose, amount, expires_at, confirmed_at, confirmed_by, channel, receipt_no)
                    VALUES (:s, :a, :r, 'School fees ' || :a, 60000, now(), now(), gen_random_uuid(), 'Bank branch', :r)
                    """).param("s", st).param("a", s0).param("r", "MOAUM-FEE-HFW-" + y + "A").update();
            jdbc.sql("INSERT INTO records.graduand (id, student_id, session, cgpa, award, unmet) VALUES (gen_random_uuid(), :s, :a, 3.50, 'B.Sc.', NULL)")
                    .param("s", st).param("a", s0).update();
            return jdbc.sql("SELECT records.graduate_one(:s, :a, 'SEN/IT/665', NULL, 'V665 IT: the award', gen_random_uuid(), 'academic')->>'outcome'")
                    .param("s", st).param("a", s0).query(String.class).single();
        });
        assertThat(approved).isEqualTo("APPROVED");
        UUID process = jdbc.sql("SELECT id FROM clearance.process WHERE workflow = 'FINAL' AND student_id = :s AND cancelled_at IS NULL").param("s", st).query(UUID.class).single();
        String officer = ItSupport.token("studentaccounts");
        String bursar = ItSupport.token("bursar");
        String bursar2 = ItSupport.token("bursar");

        Map<String, Object> account = it.get(bursar, PATH + "/students/" + st).getBody();
        assertThat(account).containsEntry("awaitingFinalClearance", true);
        assertThat(money(period((List<Map<String, Object>>) account.get("periods"), s0, 1).get("outstanding"))).isEqualByComparingTo("40000");

        // the waiver: above what is owed refused; within it, with its evidence, awaiting the Bursar; the officer cannot decide it
        Map<String, Object> waiver = new HashMap<>(Map.of("studentId", st, "session", s0, "semester", 1, "kind", "WAIVER", "amount", 50000,
                "reason", "A Council concession on the final-year school fees", "authority", "Council minute IT/664"));
        ResponseEntity<Map> above = it.call(officer, HttpMethod.POST, PATH + "/waivers", waiver);
        assertThat(above.getStatusCode().value()).isEqualTo(422);
        assertThat(above.getBody()).containsEntry("code", "HFW_AMOUNT");
        waiver.put("amount", 15000);
        waiver.put("evidence", Map.of("filename", "minute.png", "dataUrl", "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="));
        ResponseEntity<Map> made = it.call(officer, HttpMethod.POST, PATH + "/waivers", waiver);
        assertThat(made.getStatusCode().value()).as(String.valueOf(made.getBody())).isEqualTo(200);
        assertThat(made.getBody()).containsEntry("state", "PENDING_BURSAR_APPROVAL");
        assertThat(String.valueOf(made.getBody().get("reference"))).matches("HFW/[0-9]{4}/[0-9]{6}");
        assertThat((List<?>) made.getBody().get("evidence")).hasSize(1);
        String wid = String.valueOf(made.getBody().get("id"));
        assertThat((List<Map<String, Object>>) it.get(bursar, PATH + "/waivers").getBody().get("rows")).anySatisfy(r -> assertThat(r).containsEntry("id", wid));
        assertThat(it.call(officer, HttpMethod.POST, PATH + "/waivers/" + wid + "/decide", Map.of("decision", "APPROVE")).getStatusCode().value()).isEqualTo(403);
        ResponseEntity<Map> decided = it.call(bursar, HttpMethod.POST, PATH + "/waivers/" + wid + "/decide", Map.of("decision", "APPROVE", "note", "The Council minute seen"));
        assertThat(decided.getStatusCode().value()).as(String.valueOf(decided.getBody())).isEqualTo(200);
        assertThat(decided.getBody()).containsEntry("state", "APPROVED");
        Map<String, Object> now = (Map<String, Object>) decided.getBody().get("period");
        assertThat(money(now.get("waived"))).isEqualByComparingTo("15000");
        assertThat(money(now.get("outstanding"))).isEqualByComparingTo("25000");

        // a reconciliation run over the graduand's programme and session reads them owing
        ResponseEntity<Map> run = it.call(officer, HttpMethod.POST, PATH + "/recon-runs", Map.of("population", "AWAITING_GRADUATION", "programme", "C00023", "graduation", s0));
        assertThat(run.getStatusCode().value()).as(String.valueOf(run.getBody())).isEqualTo(200);
        assertThat(String.valueOf(((Map<String, Object>) run.getBody().get("run")).get("reference"))).matches("CLEARANCE-RECON/[0-9]{4}/[0-9]{6}");
        assertThat((List<Map<String, Object>>) run.getBody().get("rows")).anySatisfy(r -> {
            assertThat(r).containsEntry("student_id", st.toString()).containsEntry("status", "OWING").containsEntry("awaiting_graduation", true);
            assertThat(money(r.get("outstanding"))).isEqualByComparingTo("25000");
            assertThat(money(r.get("waived"))).isEqualByComparingTo("15000");
        });

        // the other offices clear (here the Registry's override); the Bursary's clearance is refused over the balance
        it.db(() -> jdbc.sql("""
                SELECT count(clearance.decide(:p, r.unit, 'CLEARED', 'IT: cleared by the Registry', NULL, NULL, true, gen_random_uuid(), 'registrar'))
                  FROM clearance.stage_rows('CONVOCATION', :s, ARRAY[CAST(:st AS uuid)]) r WHERE r.unit <> 'BURSARY' AND r.applies AND r.required
                """).param("p", process).param("s", s0).param("st", st).query(Long.class).single());
        String clr = "/api/v1/clearance/processes/" + process;
        Map<String, Object> check = it.get(bursar, clr + "/final-check").getBody();
        assertThat(check).containsEntry("graduates", true).containsEntry("ready", false);
        assertThat(money(check.get("waived"))).isEqualByComparingTo("15000");
        assertThat(money(check.get("outstanding"))).isEqualByComparingTo("25000");
        assertThat(it.call(bursar, HttpMethod.POST, clr + "/stages/BURSARY", Map.of("state", "CLEARED")).getBody()).containsEntry("code", "CLR_OUTSTANDING");

        // paid in full, another Bursar officer's clearance graduates the graduand in the same act
        it.db(() -> jdbc.sql("""
                INSERT INTO finance.payment_reference (student_id, session, reference, purpose, amount, expires_at, confirmed_at, confirmed_by, channel, receipt_no)
                VALUES (:s, :a, :r, 'School fees ' || :a, 25000, now(), now(), gen_random_uuid(), 'Bank branch', :r)
                """).param("s", st).param("a", s0).param("r", "MOAUM-FEE-HFW-" + y + "B").update());
        assertThat(it.get(bursar2, clr + "/final-check").getBody()).containsEntry("ready", true);
        ResponseEntity<Map> cleared = it.call(bursar2, HttpMethod.POST, clr + "/stages/BURSARY", Map.of("state", "CLEARED"));
        assertThat(cleared.getStatusCode().value()).as(String.valueOf(cleared.getBody())).isEqualTo(200);
        assertThat(cleared.getBody()).containsEntry("graduated", true);
        assertThat(jdbc.sql("SELECT status FROM people.student WHERE id = :s").param("s", st).query(String.class).single()).isEqualTo("GRADUATED");

        // the student sees the waiver in their own account
        Map<String, Object> mine = it.get(TestTokens.token(st, List.of("student")), "/api/v1/me/historical-fees").getBody();
        assertThat(mine).containsEntry("awaitingFinalClearance", false);
        Map<String, Object> mineS1 = period((List<Map<String, Object>>) mine.get("periods"), s0, 1);
        assertThat(money(mineS1.get("waived"))).isEqualByComparingTo("15000");
        assertThat(money(mineS1.get("outstanding"))).isEqualByComparingTo("0");
    }

    private static final String PNG = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==";

    /**
     * V683: payment evidence a graduate submits for a past semester, through the API. An invented graduate paid the first semester's
     * school fees; ₦50,000 of theirs in the session stands under "Outstanding fees". Their second semester reads owing, under review
     * (the other-purpose payment). They submit evidence naming that payment's number (not a second at once, not for the settled
     * semester) with a file (a text file refused); another student cannot open the file. The Students Account Officer finds it in the
     * queue, the payment among its candidates; a lecturer cannot decide; more is asked, the graduate sends it again; verified against
     * that payment, it answers NOT_SCHOOL_FEES and the semester still owes ₦50,000 — the evidence never counts by itself. The graduate
     * sees it verified.
     */
    @Test
    void aGraduatesPaymentEvidenceIsReviewedAgainstAPaymentOnRecordAndNeverCountsByItself() {
        int y = it.freeYear(7800, 8200, 0, 1);
        String s0 = y + "/" + (y + 1);
        it.session(s0, y);
        sessions.add(s0);
        UUID st = it.student(it.freeSurname("ZZHPEVID"), "C00023", it.freeNumber("MOAUM/ADM/78/", 6), it.freeNumber("MOAUM/HPE/78/", 6), 100);
        UUID other = it.student(it.freeSurname("ZZHPEOTHER"), "C00023", it.freeNumber("MOAUM/ADM/78/", 6), it.freeNumber("MOAUM/HPE/78/", 6), 100);
        String legacy = "MOAUM-OLD-HPEIT-" + y;
        it.db(() -> {
            jdbc.sql("UPDATE people.student SET status = 'GRADUATED', entry_session = :e, entry_level = 100 WHERE id = :s").param("e", s0).param("s", st).update();
            jdbc.sql("INSERT INTO people.enrolment (id, student_id, session, level) VALUES (gen_random_uuid(), :s, :a, 100)").param("s", st).param("a", s0).update();
            jdbc.sql("""
                    INSERT INTO finance.fee_schedule (session, item, amount, level, programme_code, semester) VALUES
                        (:a, 'V683 IT fees', 50000, 100, 'C00023', 1), (:a, 'V683 IT fees', 50000, 100, 'C00023', 2)
                    """).param("a", s0).update();
            return jdbc.sql("""
                    INSERT INTO finance.payment_reference (student_id, session, reference, purpose, amount, expires_at, confirmed_at, confirmed_by, channel, receipt_no) VALUES
                        (:s, :a, :r1, 'School fees ' || :a, 50000, now(), now(), gen_random_uuid(), 'Bank branch', :r1),
                        (:s, :a, :r2, 'Outstanding fees ' || :a, 50000, now(), now(), gen_random_uuid(), 'Legacy', :r2)
                    """).param("s", st).param("a", s0).param("r1", "MOAUM-FEE-HPEIT-" + y).param("r2", legacy).update();
        });
        String student = TestTokens.token(st, List.of("student"));
        String officer = ItSupport.token("studentaccounts");
        String bursar = ItSupport.token("bursar");

        // the second semester owes, under review: a payment of the session stands under another purpose
        Map<String, Object> mine = it.get(student, "/api/v1/me/historical-fees").getBody();
        Map<String, Object> second = period((List<Map<String, Object>>) mine.get("periods"), s0, 2);
        assertThat(second).containsEntry("status", "OUTSTANDING").containsEntry("review", "PAYMENT_UNDER_REVIEW");
        assertThat(money(second.get("other_amount"))).isEqualByComparingTo("50000");
        assertThat(period((List<Map<String, Object>>) mine.get("periods"), s0, 1).get("review")).isNull();

        // the evidence: not for the settled semester, not a second at once
        Map<String, Object> said = new HashMap<>(Map.of("session", s0, "semester", 1, "amount", 50000, "paidOn", "2020-03-02", "channel", "OLD_PORTAL",
                "reference", legacy.toLowerCase(), "note", "Paid on the old portal; the receipt is attached"));
        ResponseEntity<Map> settled = it.call(student, HttpMethod.POST, "/api/v1/me/historical-evidence", said);
        assertThat(settled.getStatusCode().value()).isEqualTo(422);
        assertThat(settled.getBody()).containsEntry("code", "HPE_SETTLED");
        said.put("semester", 2);
        ResponseEntity<Map> made = it.call(student, HttpMethod.POST, "/api/v1/me/historical-evidence", said);
        assertThat(made.getStatusCode().value()).as(String.valueOf(made.getBody())).isEqualTo(200);
        assertThat(made.getBody()).containsEntry("state", "SUBMITTED");
        assertThat(String.valueOf(made.getBody().get("reference"))).matches("HPE/[0-9]{4}/[0-9]{6}");
        String id = String.valueOf(made.getBody().get("id"));
        ResponseEntity<Map> twice = it.call(student, HttpMethod.POST, "/api/v1/me/historical-evidence", said);
        assertThat(twice.getStatusCode().value()).isEqualTo(422);
        assertThat(twice.getBody()).containsEntry("code", "HPE_OPEN");

        // a file: a PNG taken, a text file refused; another student cannot open it
        ResponseEntity<Map> text = it.call(student, HttpMethod.POST, "/api/v1/me/historical-evidence/" + id + "/files", Map.of("filename", "note.txt", "dataUrl", "data:text/plain;base64,aGVsbG8="));
        assertThat(text.getStatusCode().value()).isEqualTo(422);
        assertThat(text.getBody()).containsEntry("code", "HPE_FILE_TYPE");
        assertThat(it.call(student, HttpMethod.POST, "/api/v1/me/historical-evidence/" + id + "/files", Map.of("filename", "receipt.png", "dataUrl", PNG))
                .getStatusCode().value()).isEqualTo(200);
        List<Map<String, Object>> evidence = (List<Map<String, Object>>) it.get(student, "/api/v1/me/historical-fees").getBody().get("evidence");
        String file = String.valueOf(((List<Map<String, Object>>) evidence.get(0).get("files")).get(0).get("id"));
        assertThat(it.getBytes(TestTokens.token(other, List.of("student")), "/api/v1/me/historical-evidence/" + id + "/files/" + file).getStatusCode().value()).isEqualTo(404);
        assertThat(it.getBytes(student, "/api/v1/me/historical-evidence/" + id + "/files/" + file).getBody()).isNotEmpty();
        assertThat(it.getBytes(officer, PATH + "/evidence/" + id + "/files/" + file).getStatusCode().value()).isEqualTo(200);

        // the officer's queue and the payment among the candidates; a lecturer cannot decide
        Map<String, Object> queue = it.get(officer, u -> u.path(PATH + "/evidence").queryParam("state", "SUBMITTED").queryParam("q", String.valueOf(made.getBody().get("reference"))).build()).getBody();
        assertThat(queue.get("total")).isEqualTo(1);
        Map<String, Object> one = it.get(officer, PATH + "/evidence/" + id).getBody();
        Map<String, Object> cand = ((List<Map<String, Object>>) one.get("candidates")).stream().filter(c -> legacy.equals(c.get("reference"))).findFirst().orElseThrow();
        assertThat(cand).containsEntry("why", "NUMBER").containsEntry("state", "NOT_SCHOOL_FEES");
        assertThat((List<?>) one.get("files")).hasSize(1);
        assertThat(it.call(ItSupport.token("lecturer"), HttpMethod.POST, PATH + "/evidence/" + id + "/decide", Map.of("decision", "REJECT", "note", "Not a receipt of ours"))
                .getStatusCode().value()).isEqualTo(403);

        // more is asked; the graduate sends it again
        ResponseEntity<Map> asked = it.call(officer, HttpMethod.POST, PATH + "/evidence/" + id + "/decide", Map.of("decision", "MORE_INFORMATION", "note", "Attach the bank teller too, please"));
        assertThat(asked.getStatusCode().value()).as(String.valueOf(asked.getBody())).isEqualTo(200);
        assertThat(asked.getBody()).containsEntry("state", "MORE_INFORMATION_REQUIRED");
        ResponseEntity<Map> again = it.call(student, HttpMethod.POST, "/api/v1/me/historical-evidence/" + id + "/resubmit",
                Map.of("amount", 50000, "paidOn", "2020-03-02", "channel", "OLD_PORTAL", "reference", legacy, "note", "The teller is attached"));
        assertThat(again.getStatusCode().value()).as(String.valueOf(again.getBody())).isEqualTo(200);
        assertThat(again.getBody()).containsEntry("state", "SUBMITTED");

        // verified against the payment on record: it is not school fees, so the semester still owes — the evidence never counts by itself
        ResponseEntity<Map> verified = it.call(officer, HttpMethod.POST, PATH + "/evidence/" + id + "/decide",
                Map.of("decision", "VERIFY", "note", "The old-portal receipt matches", "payment", cand.get("payment_id")));
        assertThat(verified.getStatusCode().value()).as(String.valueOf(verified.getBody())).isEqualTo(200);
        assertThat(verified.getBody()).containsEntry("state", "VERIFIED").containsEntry("payment", legacy).containsEntry("payment_state", "NOT_SCHOOL_FEES");
        Map<String, Object> account = it.get(bursar, PATH + "/students/" + st).getBody();
        assertThat(money(period((List<Map<String, Object>>) account.get("periods"), s0, 2).get("outstanding"))).isEqualByComparingTo("50000");
        assertThat((List<Map<String, Object>>) account.get("evidence")).anySatisfy(e -> assertThat(e).containsEntry("state", "VERIFIED").containsEntry("payment_state", "NOT_SCHOOL_FEES"));
        List<Map<String, Object>> seen = (List<Map<String, Object>>) it.get(student, "/api/v1/me/historical-fees").getBody().get("evidence");
        assertThat(seen.get(0)).containsEntry("state", "VERIFIED");
    }

    /**
     * V720: every outstanding school fee of a record, shown to and paid by every student. Three sessions made up, the last made
     * CURRENT. An undergraduate still studying at 300 Level never paid their 100 Level session (a whole-session line) and paid the
     * rest; a graduate paid the first semester of a per-semester session only; a postgraduate student still studying owes the second
     * semester of their first stage. Each reads the balance on /me/outstanding-fees (the session, the period, due, paid, balance, the
     * status words), the student studying pays the past session through the historical door (the reference's purpose names the
     * session; the same reference on a second click; the current session paid by its own door), a pending reference makes the row
     * PAYMENT_PENDING and is never counted as paid; the desk lists the student studying under scope=ACTIVE and the postgraduate under
     * type=PG with the sessions owed in whole and in part, the School of Postgraduate Studies reading postgraduate students only, and
     * the report takes the same scope.
     */
    @Test
    void outstandingFeesOfPastSessionsAreShownToAndPaidByEveryStudent() {
        int y = it.freeYear(8300, 8700, 0, 3);
        String s0 = y + "/" + (y + 1), s1 = (y + 1) + "/" + (y + 2), cur = (y + 2) + "/" + (y + 3);
        for (int i = 0; i < 3; i++) { it.session((y + i) + "/" + (y + i + 1), y + i); }
        sessions.addAll(List.of(s0, s1, cur));
        String wasCurrent = jdbc.sql("SELECT name FROM policy.academic_session WHERE state = 'CURRENT' ORDER BY name DESC LIMIT 1").query(String.class).optional().orElse(null);
        String pgWasCurrent = jdbc.sql("SELECT name FROM admissions.pg_academic_session WHERE state = 'CURRENT' ORDER BY name DESC LIMIT 1").query(String.class).optional().orElse(null);
        UUID active = it.student(it.freeSurname("ZZOSFACT"), "C00023", it.freeNumber("MOAUM/ADM/83/", 6), it.freeNumber("MOAUM/OSF/83/", 6), 300);
        UUID grad = it.student(it.freeSurname("ZZOSFGRAD"), "C00023", it.freeNumber("MOAUM/ADM/83/", 6), it.freeNumber("MOAUM/OSF/83/", 6), 400);
        UUID pg = it.student(it.freeSurname("ZZOSFPG"), "C90002", it.freeNumber("MOAUM/ADM/83/", 6), it.freeNumber("MOAUM/OSF/83/", 6), 800);
        try {
            it.db(() -> {
                jdbc.sql("UPDATE policy.academic_session SET state = 'CLOSED' WHERE state = 'CURRENT'").update();
                jdbc.sql("UPDATE policy.academic_session SET state = 'CURRENT', senate_minute = coalesce(senate_minute, 'SEN/TEST/V720') WHERE name = :c").param("c", cur).update();
                jdbc.sql("UPDATE admissions.pg_academic_session SET state = 'CLOSED' WHERE state = 'CURRENT'").update();
                jdbc.sql("INSERT INTO admissions.pg_academic_session (name, state) VALUES (:c, 'CURRENT') ON CONFLICT (name) DO UPDATE SET state = 'CURRENT'").param("c", cur).update();
                jdbc.sql("UPDATE people.student SET entry_session = :e, entry_level = 100 WHERE id IN (:a, :g)").param("e", s0).param("a", active).param("g", grad).update();
                jdbc.sql("UPDATE people.student SET status = 'GRADUATED' WHERE id = :g").param("g", grad).update();
                jdbc.sql("UPDATE people.student SET entry_session = :e, entry_mode = 'POSTGRADUATE', entry_level = 800 WHERE id = :p").param("e", s0).param("p", pg).update();
                jdbc.sql("""
                        INSERT INTO people.enrolment (id, student_id, session, level) VALUES
                            (gen_random_uuid(), :a, :s0, 100), (gen_random_uuid(), :a, :s1, 200), (gen_random_uuid(), :a, :c, 300),
                            (gen_random_uuid(), :g, :s0, 100), (gen_random_uuid(), :g, :s1, 200),
                            (gen_random_uuid(), :p, :s0, 800), (gen_random_uuid(), :p, :s1, 800), (gen_random_uuid(), :p, :c, 800)
                        """).param("a", active).param("g", grad).param("p", pg).param("s0", s0).param("s1", s1).param("c", cur).update();
                jdbc.sql("""
                        INSERT INTO records.graduand (id, student_id, session, cgpa, award, senate_state, senate_minute, graduated_at, approved_at, final_level, duration_years, entry_session)
                        VALUES (gen_random_uuid(), :g, :s1, 3.50, 'Second Class Upper', 'APPROVED', 'SEN/TEST/V720', now(), now(), 400, 4, :s0)
                        """).param("g", grad).param("s1", s1).param("s0", s0).update();
                jdbc.sql("""
                        INSERT INTO finance.fee_schedule (session, item, amount, level, programme_code, semester) VALUES
                            (:s0, 'V720 IT fees', 50000, 100, 'C00023', NULL), (:s1, 'V720 IT fees', 30000, 200, 'C00023', 1), (:s1, 'V720 IT fees', 20000, 200, 'C00023', 2),
                            (:c, 'V720 IT fees', 35000, 300, 'C00023', 1), (:c, 'V720 IT fees', 25000, 300, 'C00023', 2)
                        """).param("s0", s0).param("s1", s1).param("c", cur).update();
                jdbc.sql("INSERT INTO finance.fee_schedule (session, item, amount, pg_stage, semester) VALUES (:s0, 'V720 IT PG fees', 100000, '800A', 1), (:s0, 'V720 IT PG fees', 50000, '800A', 2), (:s1, 'V720 IT PG fees', 80000, '800B', 1)")
                        .param("s0", s0).param("s1", s1).update();
                return jdbc.sql("""
                        INSERT INTO finance.payment_reference (student_id, session, reference, purpose, amount, expires_at, confirmed_at, confirmed_by, channel, receipt_no) VALUES
                            (:a, :s1, :r1, 'School fees ' || :s1, 50000, now(), now(), gen_random_uuid(), 'Bank branch', :r1),
                            (:g, :s0, :r2, 'School fees ' || :s0, 50000, now(), now(), gen_random_uuid(), 'Bank branch', :r2),
                            (:g, :s1, :r3, 'School fees ' || :s1, 30000, now(), now(), gen_random_uuid(), 'Bank branch', :r3),
                            (:p, :s0, :r4, 'School fees ' || :s0, 100000, now(), now(), gen_random_uuid(), 'Bank branch', :r4),
                            (:p, :s1, :r5, 'School fees ' || :s1, 80000, now(), now(), gen_random_uuid(), 'Bank branch', :r5)
                        """).param("a", active).param("g", grad).param("p", pg).param("s0", s0).param("s1", s1)
                        .param("r1", "MOAUM-FEE-OSF-" + y + "A").param("r2", "MOAUM-FEE-OSF-" + y + "B").param("r3", "MOAUM-FEE-OSF-" + y + "C")
                        .param("r4", "MOAUM-FEE-OSF-" + y + "D").param("r5", "MOAUM-FEE-OSF-" + y + "E").update();
            });
            String tActive = TestTokens.token(active, List.of("student"));
            String tGrad = TestTokens.token(grad, List.of("student"));
            String tPg = TestTokens.token(pg, List.of("student"));

            // the student studying: the 100 Level session owed in whole (the historical engine, at the level then), the current session by semester
            Map<String, Object> mine = it.get(tActive, "/api/v1/me/outstanding-fees").getBody();
            assertThat(mine).containsEntry("graduated", false).containsEntry("session", cur);
            List<Map<String, Object>> rows = (List<Map<String, Object>>) mine.get("rows");
            Map<String, Object> owed = rows.stream().filter(r -> s0.equals(r.get("session"))).findFirst().orElseThrow();
            assertThat(owed).containsEntry("kind", "PAST").containsEntry("period", "Entire session").containsEntry("level", 100).containsEntry("status", "UNPAID")
                    .containsEntry("payable", true).containsEntry("door", "HISTORICAL");
            assertThat(money(owed.get("balance"))).isEqualByComparingTo("50000");
            assertThat(rows.stream().filter(r -> s1.equals(r.get("session"))).map(r -> r.get("status"))).containsOnly("PAID");
            assertThat(rows.stream().filter(r -> cur.equals(r.get("session"))).map(r -> r.get("period") + "/" + r.get("status"))).containsExactly("First semester/UNPAID", "Second semester/UNPAID");
            Map<String, Object> summary = (Map<String, Object>) mine.get("summary");
            assertThat(money(summary.get("outstanding"))).isEqualByComparingTo("110000");
            assertThat(summary).containsEntry("sessions", 2).containsEntry("periods", 3);

            // pays the past session through the historical door: the purpose names the session; a second click, the same reference
            ResponseEntity<Map> ref = it.call(tActive, HttpMethod.POST, "/api/v1/me/outstanding-fees/references", Map.of("session", s0, "amount", 50000));
            assertThat(ref.getStatusCode().value()).as(String.valueOf(ref.getBody())).isEqualTo(200);
            String paying = String.valueOf(ref.getBody().get("reference"));
            assertThat(jdbc.sql("SELECT purpose FROM finance.payment_reference WHERE reference = :r").param("r", paying).query(String.class).single()).isEqualTo("School fees " + s0 + " (historical)");
            assertThat(it.call(tActive, HttpMethod.POST, "/api/v1/me/outstanding-fees/references", Map.of("session", s0, "amount", 50000)).getBody().get("reference")).isEqualTo(paying);
            // the pending reference makes the row PAYMENT_PENDING, never paid
            Map<String, Object> pendingRow = ((List<Map<String, Object>>) ref.getBody().get("rows")).stream().filter(r -> s0.equals(r.get("session"))).findFirst().orElseThrow();
            assertThat(pendingRow).containsEntry("status", "PAYMENT_PENDING");
            assertThat(((Map<String, Object>) pendingRow.get("reference")).get("reference")).isEqualTo(paying);
            assertThat(money(pendingRow.get("balance"))).isEqualByComparingTo("50000");
            assertThat(money(((Map<String, Object>) ref.getBody().get("summary")).get("pending"))).isEqualByComparingTo("50000");
            // more than the balance is refused; the current session goes through the fees page's own door
            ResponseEntity<Map> above = it.call(tActive, HttpMethod.POST, "/api/v1/me/outstanding-fees/references", Map.of("session", s0, "amount", 60000));
            assertThat(above.getStatusCode().value()).isEqualTo(422);
            assertThat(above.getBody()).containsEntry("code", "HFA_PAY_AMOUNT");
            ResponseEntity<Map> now = it.call(tActive, HttpMethod.POST, "/api/v1/me/outstanding-fees/references", Map.of("session", cur, "amount", 35000));
            assertThat(now.getStatusCode().value()).as(String.valueOf(now.getBody())).isEqualTo(200);
            assertThat(jdbc.sql("SELECT purpose FROM finance.payment_reference WHERE reference = :r").param("r", String.valueOf(now.getBody().get("reference"))).query(String.class).single())
                    .startsWith("School fees " + cur);

            // the graduate: the second semester owed, nothing else; the fees page's historical read serves them as before
            Map<String, Object> g = it.get(tGrad, "/api/v1/me/outstanding-fees").getBody();
            assertThat(g).containsEntry("graduated", true);
            List<Map<String, Object>> gOwed = ((List<Map<String, Object>>) g.get("rows")).stream().filter(r -> money(r.get("balance")).signum() > 0).toList();
            assertThat(gOwed).hasSize(1);
            assertThat(gOwed.get(0)).containsEntry("session", s1).containsEntry("period", "Second semester").containsEntry("status", "UNPAID");
            assertThat(money(gOwed.get(0).get("balance"))).isEqualByComparingTo("20000");

            // the postgraduate student studying: the first stage's second semester owed, from the stage's lines; their past ends at the School's own calendar
            Map<String, Object> p = it.get(tPg, "/api/v1/me/outstanding-fees").getBody();
            List<Map<String, Object>> pOwed = ((List<Map<String, Object>>) p.get("rows")).stream().filter(r -> money(r.get("balance")).signum() > 0).toList();
            assertThat(pOwed).hasSize(1);
            assertThat(pOwed.get(0)).containsEntry("session", s0).containsEntry("period", "Second semester").containsEntry("kind", "PAST");
            assertThat(money(pOwed.get(0).get("balance"))).isEqualByComparingTo("50000");

            // the desk: the student studying under scope=ACTIVE (the sessions owed in whole), the postgraduate under type=PG; the School reads PG only
            String bursar = ItSupport.token("bursar");
            Map<String, Object> listed = it.get(bursar, u -> u.path(PATH + "/students").queryParam("scope", "ACTIVE").queryParam("filter", "WHOLE_SESSION").queryParam("q", active.toString()).build()).getBody();
            assertThat(listed.get("total")).isEqualTo(1);
            assertThat(((List<Map<String, Object>>) listed.get("rows")).get(0)).containsEntry("whole_sessions", 1).containsEntry("postgraduate", false);
            assertThat(it.get(bursar, u -> u.path(PATH + "/students").queryParam("scope", "GRADUATES").queryParam("q", active.toString()).build()).getBody().get("total")).isEqualTo(0);
            assertThat(it.get(bursar, u -> u.path(PATH + "/students").queryParam("scope", "ALL").queryParam("type", "PG").queryParam("filter", "PART_SESSION").queryParam("q", pg.toString()).build()).getBody().get("total")).isEqualTo(1);
            String school = ItSupport.token("pgschool");
            assertThat(it.get(school, u -> u.path(PATH + "/students").queryParam("scope", "ALL").queryParam("q", pg.toString()).build()).getBody().get("total")).isEqualTo(1);
            assertThat(it.get(school, u -> u.path(PATH + "/students").queryParam("scope", "ALL").queryParam("q", active.toString()).build()).getBody().get("total")).isEqualTo(0);
            Map<String, Object> figures = it.get(bursar, PATH + "/figures").getBody();
            assertThat((List<Map<String, Object>>) figures.get("population")).anySatisfy(x -> assertThat(x).containsEntry("standing", "ACTIVE").containsEntry("type", "UG"));
            Map<String, Object> report = it.get(bursar, u -> u.path(PATH + "/report").queryParam("scope", "ACTIVE").queryParam("session", s0).build()).getBody();
            assertThat((List<Map<String, Object>>) report.get("rows")).anySatisfy(r -> assertThat(r).containsEntry("academic_status", "ACTIVE").containsEntry("programme_type", "UG").containsEntry("status", "OUTSTANDING"));
        } finally {
            // the calendar as the test found it: the test's session planned again (a closed far-future session would become every
            // returning student's "latest run" between sessions, as StudentPortalIT reads it), the one that was current current again
            it.db(() -> {
                jdbc.sql("UPDATE policy.academic_session SET state = 'PLANNED' WHERE name = :c AND name IS DISTINCT FROM :w AND state <> 'PLANNED'")
                        .param("c", cur).param("w", wasCurrent, java.sql.Types.VARCHAR).update();
                if (wasCurrent != null) jdbc.sql("UPDATE policy.academic_session SET state = 'CURRENT' WHERE name = :w AND state <> 'CURRENT'").param("w", wasCurrent).update();
                jdbc.sql("DELETE FROM admissions.pg_academic_session WHERE name = :c").param("c", cur).update();
                if (pgWasCurrent != null) jdbc.sql("UPDATE admissions.pg_academic_session SET state = 'CURRENT' WHERE name = :w").param("w", pgWasCurrent).update();
                return 0;
            });
        }
    }
}
