package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.math.BigDecimal;
import java.util.Base64;
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
 * A candidate of the intake session walked end to end while the session before it is still the University's current one
 * (V377, V378): the next session begins before the current one ends, and every door the candidate meets without naming a
 * session opens on the intake session — the public Post-UTME page, the registration, the application, checking and
 * acceptance fees, the clearance, the register, the student's portal, school fees, course registration and matriculation.
 * Nothing of theirs lands in the current session. The go-live readiness reads the admission exercise for the intake session
 * and the running session's gates for the current one. The calendar is put back as the test found it. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class IntakeJourneyIT {

    /** the University's current session in the test: it runs to 31 October 2196 */
    static final String CURRENT = "2195/2196";
    /** the intake session: planned, and begun on 1 September 2196 while the current one still runs */
    static final String INTAKE = "2196/2197";
    static final String PATH = "/api/v1/admissions/sessions/2196/2197";
    static final String PROGRAMME = "C00019";

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    ItSupport it;
    String academic = ItSupport.token("academic");
    String bursar = ItSupport.token("bursar");
    String registrar = ItSupport.token("registrar");
    String ict = ItSupport.token("ict");
    String hod = ItSupport.token("hod");
    /** the session that was current before the test, put back after it */
    String wasCurrent;

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
        wasCurrent = jdbc.sql("SELECT name FROM policy.academic_session WHERE state = 'CURRENT' AND name NOT IN (:own) ORDER BY name DESC LIMIT 1")
                .param("own", List.of(CURRENT, INTAKE)).query(String.class).optional().orElse(null);
        it.db(() -> {
            // the residue of an earlier run: the test's own sessions' charges and windows
            ownCharges();
            jdbc.sql("DELETE FROM policy.portal_window_event WHERE session IN (:own)").param("own", List.of(CURRENT, INTAKE)).update();
            jdbc.sql("DELETE FROM policy.portal_window WHERE session IN (:own)").param("own", List.of(CURRENT, INTAKE)).update();
            jdbc.sql("""
                    INSERT INTO policy.academic_session (id, name, starts_on, ends_on, state) VALUES
                      (gen_random_uuid(), :c, DATE '2195-10-01', DATE '2196-10-31', 'PLANNED'),
                      (gen_random_uuid(), :i, DATE '2196-09-01', DATE '2197-08-31', 'PLANNED')
                    ON CONFLICT (name) DO UPDATE SET starts_on = EXCLUDED.starts_on, ends_on = EXCLUDED.ends_on, state = 'PLANNED'
                    """).param("c", CURRENT).param("i", INTAKE).update();
            // the Registry's act, as StudentPortalIT stands in its session: the current session completed, the test's made current
            jdbc.sql("UPDATE policy.academic_session SET state = 'CLOSED' WHERE state = 'CURRENT' AND name <> :c").param("c", CURRENT).update();
            return jdbc.sql("UPDATE policy.academic_session SET state = 'CURRENT', senate_minute = coalesce(senate_minute, 'SEN/TEST/2195/001') WHERE name = :c")
                    .param("c", CURRENT).update();
        });
    }

    /** the calendar as the test found it: the test's sessions planned again, the one that was current current again */
    @AfterEach
    void restoreTheCalendar() {
        it.db(() -> {
            ownCharges();
            jdbc.sql("UPDATE policy.academic_session SET state = 'PLANNED' WHERE name IN (:own) AND state <> 'PLANNED'").param("own", List.of(CURRENT, INTAKE)).update();
            return wasCurrent == null ? 0
                    : jdbc.sql("UPDATE policy.academic_session SET state = 'CURRENT' WHERE name = :w AND state <> 'CURRENT'").param("w", wasCurrent).update();
        });
    }

    /** the test's sessions charge nothing outside the test: their fee lines ended (payments keep pointing at them) and their
     *  applicant fees taken out — with no session current, the portal falls back on the latest session with a charge, and an
     *  unstated session's applicant fees on the latest stated */
    private void ownCharges() {
        jdbc.sql("UPDATE finance.fee_schedule SET ended_at = now() WHERE session IN (:own) AND ended_at IS NULL").param("own", List.of(CURRENT, INTAKE)).update();
        jdbc.sql("DELETE FROM admissions.applicant_fee WHERE session IN (:own)").param("own", List.of(CURRENT, INTAKE)).update();
    }

    static Map<String, Object> m(Object o) { return (Map<String, Object>) o; }
    static List<Map<String, Object>> l(Object o) { return (List<Map<String, Object>>) o; }

    Map<String, Object> check(Map<String, Object> readiness, String key) {
        return l(readiness.get("checks")).stream().filter(c -> key.equals(c.get("key"))).findFirst().orElseThrow();
    }

    ResponseEntity<Map> ok(ResponseEntity<Map> r) {
        assertThat(r.getStatusCode().value()).as(String.valueOf(r.getBody())).isEqualTo(200);
        return r;
    }

    @Test
    void aCandidateOfTheIntakeSessionGoesFromThePostUtmePageToMatriculationWhileTheLastSessionIsCurrent() {
        int n = new Random().nextInt(100_000_000);
        String jamb = "2196" + String.format("%08d", n) + "IJ";

        // 1 · with no session named, the public Post-UTME page reads the intake session, not the current one
        ResponseEntity<Map> windows = it.anon(HttpMethod.GET, "/api/v1/public/application-windows", null);
        String session = String.valueOf(m(windows.getBody().get("postUtme")).get("session"));
        assertThat(session).isEqualTo(INTAKE);
        assertThat(m(windows.getBody().get("postUtme")).get("open")).isEqualTo(true);

        // 2 · the go-live readiness: the admission exercise is the intake session's, the running gates the current session's;
        //     the intake session's applicant fees are not set yet, and it says what candidates would be charged
        Map<String, Object> ready = ok(it.get(ict, "/api/v1/platform/readiness")).getBody();
        assertThat(ready.get("intakeSession")).isEqualTo(INTAKE);
        assertThat(ready.get("session")).isEqualTo(CURRENT);
        assertThat(check(ready, "intake_session").get("status")).isEqualTo("ok");
        assertThat(check(ready, "applicant_fee").get("status")).isEqualTo("bad");
        assertThat(String.valueOf(check(ready, "applicant_fee").get("detail"))).contains(INTAKE).contains("would be charged");
        assertThat(check(ready, "applicant_fee").get("group")).isEqualTo("intake");
        assertThat(check(ready, "post_utme_window").get("status")).isEqualTo("ok");
        assertThat(check(ready, "session").get("group")).isEqualTo("running");
        assertThat(check(ready, "session").get("status")).isEqualTo("ok");   // the current session is current
        assertThat(check(ready, "gateway").get("group")).isEqualTo("institution");
        long listedBefore = jdbc.sql("SELECT count(*) FROM admissions.caps_row_live WHERE session = :s").param("s", INTAKE).query(Long.class).single();
        assertThat(check(ready, "jamb_list").get("status")).isEqualTo(listedBefore > 0 ? "ok" : "bad");

        // the intake session's fees, stated; the readiness reads them at once
        ok(it.call(academic, HttpMethod.PUT, PATH + "/applicant-fees", Map.of("applicationFee", 2500, "portalCharge", 0, "acceptanceFee", 30000, "checkingFee", 3500)));
        assertThat(check(ok(it.get(ict, "/api/v1/platform/readiness")).getBody(), "applicant_fee").get("status")).isEqualTo("ok");

        // 3 · JAMB's Direct Entry list for the session the public page names; the readiness counts it
        ResponseEntity<Map> loaded = it.call(academic, HttpMethod.POST, "/api/v1/admissions/caps-batches", Map.of(
                "session", session, "source", "CAPS_DOWNLOAD", "filename", "CAPS-DE-intake-it.xlsx",
                "fileSha256", String.format("%064x", new Random().nextLong() & Long.MAX_VALUE), "listKind", "DIRECT_ENTRY", "downloadedOn", "2196-08-20",
                "rows", List.of(Map.of("jambRegNo", jamb, "surname", "ZZINTAKE", "otherNames", "Invented Entrant", "jambCode", PROGRAMME,
                        "entryMode", "DIRECT_ENTRY", "sex", "F", "stateOfOrigin", "Benue", "lga", "Makurdi", "raw", Map.of()))));
        assertThat(loaded.getStatusCode().value()).as(String.valueOf(loaded.getBody())).isEqualTo(201);
        assertThat(check(ok(it.get(ict, "/api/v1/platform/readiness")).getBody(), "jamb_list").get("status")).isEqualTo("ok");

        // 4 · found and registered under that session: the application number carries the intake year
        assertThat(it.anon(HttpMethod.POST, "/api/v1/applicant/lookup", Map.of("session", session, "jambKey", jamb)).getBody().get("state")).isEqualTo("found");
        ResponseEntity<Map> registered = ok(it.anon(HttpMethod.POST, "/api/v1/applicant/register", Map.of("session", session, "jambKey", jamb,
                "email", jamb.toLowerCase() + "@example.com", "phone", "08034117725", "password", "a long enough password")));
        String token = String.valueOf(registered.getBody().get("token"));
        String appNo = String.valueOf(registered.getBody().get("applicationNo"));
        assertThat(appNo).matches("APP/96/\\d{6}");
        UUID appId = jdbc.sql("SELECT id FROM admissions.application WHERE application_no = :no").param("no", appNo).query(UUID.class).single();
        assertThat(jdbc.sql("SELECT session FROM admissions.application WHERE id = :a").param("a", appId).query(String.class).single()).isEqualTo(INTAKE);

        // 4b · V401: under the Bursary's rule REFUSE, a session whose applicant fees are not stated issues no fee reference; the
        //      fees stated again (and the rule put back), the reference follows
        ok(it.call(bursar, HttpMethod.PUT, "/api/v1/finance/applicant-fee-policy", Map.of("policy", "REFUSE")));
        it.db(() -> jdbc.sql("DELETE FROM admissions.applicant_fee WHERE session = :s").param("s", INTAKE).update());
        try {
            ResponseEntity<Map> unstated = it.call(token, HttpMethod.POST, "/api/v1/applicant/me/fee-references", Map.of("kind", "APPLICATION"));
            assertThat(unstated.getStatusCode().value()).isEqualTo(422);
            assertThat(unstated.getBody().get("code")).isEqualTo("APPLICANT_FEE_NOT_STATED");
        } finally {
            ok(it.call(bursar, HttpMethod.PUT, "/api/v1/finance/applicant-fee-policy", Map.of("policy", "CARRY")));
        }
        ok(it.call(academic, HttpMethod.PUT, PATH + "/applicant-fees", Map.of("applicationFee", 2500, "portalCharge", 0, "acceptanceFee", 30000, "checkingFee", 3500)));

        // 5 · the application fee at the intake session's amount, confirmed by the Bursary; the form and its documents
        String appRef = String.valueOf(ok(it.call(token, HttpMethod.POST, "/api/v1/applicant/me/fee-references", Map.of("kind", "APPLICATION"))).getBody().get("reference"));
        Map<String, Object> appFee = jdbc.sql("SELECT a.session, f.amount FROM admissions.fee_reference f JOIN admissions.application a ON a.id = f.application_id WHERE f.reference = :r")
                .param("r", appRef).query().singleRow();
        assertThat(appFee.get("session")).isEqualTo(INTAKE);
        assertThat((BigDecimal) appFee.get("amount")).isEqualByComparingTo("2500");
        ok(it.call(bursar, HttpMethod.POST, PATH + "/fee-references/" + appRef + "/confirm", Map.of("channel", "Card")));
        it.call(token, HttpMethod.PUT, "/api/v1/applicant/me/next-of-kin", Map.of("nextOfKin", "ZZINTAKE, Terhemba · 0806 552 1180"));
        String pdf = Base64.getEncoder().encodeToString("%PDF-1.4 invented".getBytes());
        for (String kind : List.of("OLEVEL_STATEMENT", "BIRTH_CERT", "LGA_ID", "JAMB_SLIP", "PASSPORT")) {
            ok(it.call(token, HttpMethod.POST, "/api/v1/applicant/me/documents", Map.of("kind", kind, "filename", kind.toLowerCase() + ".pdf", "contentType", "application/pdf", "contentBase64", pdf)));
        }
        assertThat(ok(it.call(token, HttpMethod.POST, "/api/v1/applicant/me/submit", Map.of("declaration", true))).getBody().get("stage")).isEqualTo(2);

        // 6 · seated for the Post-UTME screening; the score, the Board's offer, both released
        String label = "J" + (n % 100);
        ResponseEntity<List> batches = it.callList(academic, HttpMethod.POST, PATH + "/screening-batches",
                Map.of("label", label, "heldOn", "2196-09-22", "startsAt", "11:00", "endsAt", "12:00", "venue", "CBT Hall B, ICT Directorate", "capacity", 500));
        assertThat(batches.getStatusCode().value()).as(String.valueOf(batches.getBody())).isEqualTo(200);
        String batchId = String.valueOf(((Map<?, ?>) batches.getBody().stream().filter(b -> label.equals(((Map<?, ?>) b).get("label"))).findFirst().orElseThrow()).get("id"));
        ok(it.call(academic, HttpMethod.POST, PATH + "/screening-batches/" + batchId + "/assign", Map.of()));
        ok(it.call(academic, HttpMethod.PUT, PATH + "/applications/" + appId + "/screening-score", Map.of("score", 64)));
        it.call(academic, HttpMethod.POST, PATH + "/screening-scores/release", Map.of());
        ok(it.call(academic, HttpMethod.PUT, PATH + "/applications/" + appId + "/decision", Map.of("decision", "OFFERED", "basis", "NM")));
        it.call(academic, HttpMethod.POST, PATH + "/decisions/release", Map.of());

        // 7 · the checking fee and the status read, the acceptance and its fee — each at the intake session's amount
        it.openChecking(INTAKE);
        String chk = String.valueOf(ok(it.call(token, HttpMethod.POST, "/api/v1/applicant/me/fee-references", Map.of("kind", "CHECKING"))).getBody().get("reference"));
        ok(it.call(bursar, HttpMethod.POST, PATH + "/fee-references/" + chk + "/confirm", Map.of("channel", "Card")));
        assertThat(ok(it.call(token, HttpMethod.POST, "/api/v1/applicant/me/admission/checked", Map.of())).getBody().get("status")).isEqualTo("ADMITTED");
        ok(it.call(token, HttpMethod.POST, "/api/v1/applicant/me/accept", Map.of("undertaking", true)));
        String acc = String.valueOf(ok(it.call(token, HttpMethod.POST, "/api/v1/applicant/me/fee-references", Map.of("kind", "ACCEPTANCE"))).getBody().get("reference"));
        ok(it.call(bursar, HttpMethod.POST, PATH + "/fee-references/" + acc + "/confirm", Map.of("channel", "Card")));
        Map<String, Object> amounts = jdbc.sql("""
                SELECT max(amount) FILTER (WHERE reference = :chk) AS checking, max(amount) FILTER (WHERE reference = :acc) AS acceptance
                  FROM admissions.fee_reference WHERE application_id = :a
                """).param("chk", chk).param("acc", acc).param("a", appId).query().singleRow();
        assertThat((BigDecimal) amounts.get("checking")).isEqualByComparingTo("3500");
        assertThat((BigDecimal) amounts.get("acceptance")).isEqualByComparingTo("30000");

        // 8 · the Registry clears the documents; the intake run brings the candidate onto the register of the intake session
        for (String item : List.of("OLEVEL_ORIGINAL", "BIRTH_CERT", "LGA_ID", "JAMB_LETTER", "MEDICAL", "PHOTOGRAPHS")) {
            ok(it.call(registrar, HttpMethod.PUT, PATH + "/applications/" + appId + "/clearance/" + item, Map.of("state", "VERIFIED")));
        }
        assertThat(it.get(token, "/api/v1/applicant/me").getBody().get("stage")).isEqualTo(7);
        ok(it.call(registrar, HttpMethod.POST, "/api/v1/student/intake/2196/2197", null));
        Map<String, Object> student = jdbc.sql("""
                SELECT s.id, s.entry_session, s.current_level FROM people.student s JOIN admissions.application a ON a.candidate_id = s.candidate_id WHERE a.id = :a
                """).param("a", appId).query().singleRow();
        UUID studentId = (UUID) student.get("id");
        int level = ((Number) student.get("current_level")).intValue();
        assertThat(student.get("entry_session")).isEqualTo(INTAKE);

        // 9 · the same account continues into the student portal, standing in the intake session while the other is current
        String studentToken = String.valueOf(ok(it.call(token, HttpMethod.POST, "/api/v1/student-auth/continue", Map.of())).getBody().get("token"));
        Map<String, Object> me = ok(it.get(studentToken, "/api/v1/me")).getBody();
        assertThat(me.get("session")).isEqualTo(INTAKE);
        assertThat(m(me.get("academic")).get("current_session")).isEqualTo(CURRENT);

        // 10 · school fees: the Bursar states the intake session's charge; the student's fees and reference are that session's
        ok(it.call(bursar, HttpMethod.POST, "/api/v1/finance/sessions/2196/2197/schedule", Map.of("item", "School fees", "amount", 120000, "level", level)));
        Map<String, Object> fees = ok(it.get(studentToken, "/api/v1/me/fees")).getBody();
        assertThat(fees.get("session")).isEqualTo(INTAKE);
        assertThat(new BigDecimal(String.valueOf(fees.get("due")))).isEqualByComparingTo("120000");
        String feeRef = String.valueOf(ok(it.call(studentToken, HttpMethod.POST, "/api/v1/me/fees/references", Map.of("amount", 120000))).getBody().get("reference"));
        assertThat(jdbc.sql("SELECT session FROM finance.payment_reference WHERE reference = :r").param("r", feeRef).query(String.class).single()).isEqualTo(INTAKE);
        ok(it.call(bursar, HttpMethod.POST, "/api/v1/finance/references/" + feeRef + "/confirm", Map.of("channel", "Bank transfer", "note", "intake journey")));
        it.db(() -> {
            // a clearance scheme in force, as StudentPortalIT puts one, where none is
            jdbc.sql("""
                    INSERT INTO policy.version (id, kind, scope, validity, instrument, decided_by)
                    SELECT gen_random_uuid(), 'clearance', 'UNIVERSITY',
                           daterange(current_date, (SELECT min(lower(validity)) FROM policy.version WHERE kind = 'clearance' AND scope = 'UNIVERSITY' AND lower(validity) > current_date)),
                           'BUR/IT/2196', 'bursar'
                     WHERE policy.in_force('clearance', 'UNIVERSITY', current_date) IS NULL
                    """).update();
            jdbc.sql("INSERT INTO policy.clearance_scheme SELECT id, true FROM policy.version WHERE instrument = 'BUR/IT/2196' ON CONFLICT DO NOTHING").update();
            jdbc.sql("""
                    INSERT INTO policy.clearance_rule SELECT v.id, p.code, CASE p.code WHEN 'HOSTEL' THEN 'NEVER_GATED'
                        WHEN 'REGISTRATION' THEN 'INSTALMENT_1' WHEN 'ID_CARD' THEN 'INSTALMENT_1' WHEN 'LIBRARY' THEN 'INSTALMENT_1' ELSE 'PAID_IN_FULL' END
                      FROM policy.version v, ref.clearance_purpose p WHERE v.instrument = 'BUR/IT/2196' ON CONFLICT DO NOTHING
                    """).update();
            return null;
        });
        assertThat(ok(it.get(studentToken, "/api/v1/me/fees")).getBody().get("clearsRegistration")).isEqualTo(true);

        // 11 · course registration opens on the intake session's first semester, with no session named
        String dept = jdbc.sql("SELECT dept_code FROM ref.programme WHERE code = :p").param("p", PROGRAMME).query(String.class).single();
        it.db(() -> {
            jdbc.sql("INSERT INTO catalogue.course (code, title, units, semester, level, dept_code, kind, state) VALUES ('ZZJ 201', 'Intake Journey Course One', 12, 1, :l, :d, 'Core', 'LIVE'), ('ZZJ 203', 'Intake Journey Course Two', 6, 1, :l, :d, 'Core', 'LIVE') ON CONFLICT (code) DO NOTHING")
                    .param("l", level).param("d", dept).update();
            jdbc.sql("INSERT INTO catalogue.course_offer (course_code, programme_code, level, basis) VALUES ('ZZJ 201', :p, :l, 'Core'), ('ZZJ 203', :p, :l, 'Core') ON CONFLICT DO NOTHING")
                    .param("p", PROGRAMME).param("l", level).update();
            jdbc.sql("INSERT INTO catalogue.offering (id, course_code, session, semester) VALUES (gen_random_uuid(), 'ZZJ 201', :s, 1), (gen_random_uuid(), 'ZZJ 203', :s, 1) ON CONFLICT (course_code, session, semester, stream) DO NOTHING")
                    .param("s", INTAKE).update();
            return null;
        });
        Map<String, Object> view = ok(it.get(studentToken, "/api/v1/me/registration?semester=1")).getBody();
        List<Map<String, Object>> menu = l(view.get("menu"));
        List<UUID> offerings = menu.stream().filter(x -> String.valueOf(x.get("course_code")).startsWith("ZZJ ")).map(x -> UUID.fromString(String.valueOf(x.get("offering_id")))).toList();
        assertThat(offerings).hasSize(2);
        assertThat(jdbc.sql("SELECT DISTINCT session FROM catalogue.offering WHERE id IN (:o)").param("o", offerings).query(String.class).list()).containsExactly(INTAKE);
        ok(it.call(studentToken, HttpMethod.PUT, "/api/v1/me/registration", Map.of("session", INTAKE, "semester", 1, "offerings", offerings)));
        Map<String, Object> reg = m(ok(it.call(studentToken, HttpMethod.POST, "/api/v1/me/registration/submit", Map.of("session", INTAKE, "semester", 1))).getBody().get("registration"));
        ok(it.call(hod, HttpMethod.POST, "/api/v1/registration/course-registrations/" + reg.get("id") + "/approve", Map.of()));

        // 12 · matriculation in the intake session: the number carries its year
        ok(it.call(registrar, HttpMethod.POST, "/api/v1/matriculation/sessions/2196/2197/students/" + studentId + "/matriculate", null));
        String matric = jdbc.sql("SELECT matric_no FROM people.student WHERE id = :s").param("s", studentId).query(String.class).single();
        assertThat(matric).matches("MOAU/.+/96/\\d+");

        // nothing of the entrant's landed in the session that is current
        long inCurrent = jdbc.sql("""
                SELECT (SELECT count(*) FROM finance.payment_reference WHERE student_id = :s AND session = :c)
                     + (SELECT count(*) FROM registration.course_registration WHERE student_id = :s AND session = :c)
                """).param("s", studentId).param("c", CURRENT).query(Long.class).single();
        assertThat(inCurrent).isZero();
        assertThat(ok(it.get(studentToken, "/api/v1/me")).getBody().get("session")).isEqualTo(INTAKE);
    }
}
