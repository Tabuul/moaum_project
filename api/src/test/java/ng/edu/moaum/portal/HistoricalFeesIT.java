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
}
