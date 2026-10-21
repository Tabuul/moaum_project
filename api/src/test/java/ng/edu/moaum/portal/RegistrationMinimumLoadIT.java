package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.ArrayList;
import java.util.HashMap;
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
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.web.client.RestClient;

/**
 * The minimum course registration load by curriculum (V495), end to end on the student's own door: under the standing rules a
 * CCMAS student submits 15 units and is refused at 14, a BMAS student submits 18 and 20 and is refused at 15 and 17; the
 * automatic approval (V491) never approves below the minimum and the examination card follows only an approved registration; the
 * Directorate of ICT raises a session's minimum (CCMAS 16, BMAS 20) and the next submission reads it at once while the
 * registrations already approved stay as they are; the reset and the registration made again read the new minimum; another
 * session keeps its own; the maximum still binds; a student, a Head of Department and the Academic Office cannot set it; a value
 * of 0, -5, "abc" or above the maximum is refused; each change is logged; the browser cannot name a curriculum; the registrations
 * below the minimum are listed; the calendar keeps a level's maximum at or above it. Each run files everything under its own
 * session. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class RegistrationMinimumLoadIT {

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    ItSupport it;
    RestClient open;
    final String registrar = ItSupport.token("registrar");
    final String bursar = ItSupport.token("bursar");
    final String academic = ItSupport.token("academic");
    final String ict = ItSupport.token("ict");
    final String instrument = "BUR/IT/LOAD495";
    String session;
    String next;

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
        open = RestClient.builder().baseUrl("http://localhost:" + port).defaultStatusHandler(s -> true, (q, r) -> { }).build();
    }

    /** the run's own rules, fee lines and clearance scheme taken away, so a later test reads the standing rules */
    @AfterEach
    void clean() {
        it.db(() -> {
            jdbc.sql("DELETE FROM registration.unit_minimum WHERE session IN (:a, :b)").param("a", String.valueOf(session)).param("b", String.valueOf(next)).update();
            if (session != null) jdbc.sql("DELETE FROM finance.fee_schedule WHERE session = :s").param("s", session).update();
            jdbc.sql("DELETE FROM policy.clearance_rule WHERE version_id IN (SELECT id FROM policy.version WHERE instrument = :i)").param("i", instrument).update();
            jdbc.sql("DELETE FROM policy.clearance_scheme WHERE version_id IN (SELECT id FROM policy.version WHERE instrument = :i)").param("i", instrument).update();
            return jdbc.sql("DELETE FROM policy.version WHERE instrument = :i").param("i", instrument).update();
        });
    }

    private ResponseEntity<Map> post(String path, Object body) {
        return open.post().uri(path).contentType(MediaType.APPLICATION_JSON).body(body).retrieve().toEntity(Map.class);
    }

    private String signedIn(UUID student, String matric) {
        assertThat(it.call(registrar, HttpMethod.PUT, "/api/v1/student-auth/accounts/" + student, Map.of("password", "first password 4950")).getStatusCode().value()).isEqualTo(200);
        String t = String.valueOf(post("/api/v1/student-auth/sign-in", Map.of("matricNo", matric, "password", "first password 4950")).getBody().get("token"));
        assertThat(it.call(t, HttpMethod.POST, "/api/v1/student-auth/change-password", Map.of("current", "first password 4950", "next", "Own-Password-4950")).getStatusCode().value()).isEqualTo(200);
        return t;
    }

    private void payInFull(String token) {
        Map<String, Object> ref = it.call(token, HttpMethod.POST, "/api/v1/me/fees/references", Map.of("session", session, "amount", 100000)).getBody();
        ResponseEntity<Map> ok = it.call(bursar, HttpMethod.POST, "/api/v1/finance/references/" + ref.get("reference") + "/confirm", Map.of("channel", "Bank transfer", "note", "minimum load test"));
        assertThat(ok.getStatusCode().value()).as(String.valueOf(ok.getBody())).isEqualTo(200);
    }

    /** the student's courses of this test by code: IMU 101–107 carry 3 units, IMU 108–109 carry 2 */
    private Map<String, UUID> menu(String token) {
        Map<String, Object> view = it.get(token, "/api/v1/me/registration?session=" + session + "&semester=1").getBody();
        Map<String, UUID> out = new HashMap<>();
        for (Map<String, Object> m : (List<Map<String, Object>>) view.get("menu")) {
            String code = String.valueOf(m.get("course_code"));
            if (code.startsWith("IMU ")) out.put(code, UUID.fromString(String.valueOf(m.get("offering_id"))));
        }
        return out;
    }

    /** choose threes three-unit courses and twos two-unit courses, then submit */
    private ResponseEntity<Map> submit(String token, Map<String, UUID> menu, int threes, int twos) {
        List<UUID> chosen = new ArrayList<>();
        for (int i = 1; i <= threes; i++) chosen.add(menu.get("IMU 10" + i));
        for (int i = 0; i < twos; i++) chosen.add(menu.get("IMU 10" + (8 + i)));
        ResponseEntity<Map> saved = it.call(token, HttpMethod.PUT, "/api/v1/me/registration", Map.of("session", session, "semester", 1, "offerings", chosen));
        assertThat(saved.getStatusCode().value()).as(String.valueOf(saved.getBody())).isEqualTo(200);
        return it.call(token, HttpMethod.POST, "/api/v1/me/registration/submit", Map.of("session", session, "semester", 1));
    }

    private void refused(ResponseEntity<Map> r, int minimum, int units, String curriculum) {
        assertThat(r.getStatusCode().value()).as(String.valueOf(r.getBody())).isEqualTo(422);
        assertThat(r.getBody().get("code")).isEqualTo("REG_UNITS_BELOW_MINIMUM");
        assertThat(String.valueOf(r.getBody().get("detail")))
                .contains("minimum required credit load for your curriculum (" + curriculum + ") is " + minimum + " credit units")
                .contains("You currently have " + units + " credit units");
    }

    private void approved(ResponseEntity<Map> r) {
        assertThat(r.getStatusCode().value()).as(String.valueOf(r.getBody())).isEqualTo(200);
        assertThat(r.getBody().get("result")).isEqualTo("approved");
    }

    private Map<String, Object> registration(String token) {
        return (Map<String, Object>) it.get(token, "/api/v1/me/registration?session=" + session + "&semester=1").getBody().get("registration");
    }

    private void reset(String token) {
        ResponseEntity<Map> r = it.call(token, HttpMethod.POST, "/api/v1/me/registration/reset", Map.of("session", session, "semester", 1));
        assertThat(r.getStatusCode().value()).as(String.valueOf(r.getBody())).isEqualTo(200);
    }

    private ResponseEntity<Map> setMinimum(String token, String curriculum, String inSession, Object units) {
        Map<String, Object> body = new HashMap<>();
        body.put("curriculum", curriculum);
        body.put("session", inSession);
        body.put("minUnits", units);
        body.put("reason", "Integration test: the minimum course load for " + curriculum);
        return it.call(token, HttpMethod.PUT, "/api/v1/registration/load/rules", body);
    }

    private Map<String, Object> inForce(String inSession, String curriculum) {
        Map<String, Object> rules = it.get(ict, "/api/v1/registration/load/rules?session=" + inSession).getBody();
        return ((List<Map<String, Object>>) rules.get("inForce")).stream().filter(f -> curriculum.equals(f.get("curriculum"))).findFirst().orElseThrow();
    }

    @Test
    void theMinimumOfEachCurriculumBindsEverySubmissionAndTheDirectorateChangesItWithoutCode() {
        int y = it.freeYear(2400, 2900, 0, 1);
        session = y + "/" + (y + 1);
        next = (y + 1) + "/" + (y + 2);
        it.session(session, y);
        it.session(next, y + 1);
        int n = 1000 + new Random().nextInt(8999);
        String yy = String.format("%02d", y % 100);
        String ccmasMatric = "MOAUM/IMU/" + yy + "/1" + n;
        String bmasMatric = "MOAUM/IMU/" + yy + "/2" + n;
        UUID ccmas = it.student("ZZLOADC" + n, "C00061", "MOAUM/ADM/" + yy + "/51" + n, ccmasMatric, 100);
        UUID bmas = it.student("ZZLOADB" + n, "C00061", "MOAUM/ADM/" + yy + "/52" + n, bmasMatric, 100);
        it.db(() -> jdbc.sql("UPDATE people.student SET curriculum_version = CASE WHEN id = :c THEN 'CCMAS' ELSE 'BMAS' END WHERE id IN (:c, :b)")
                .param("c", ccmas).param("b", bmas).update());
        String ct = signedIn(ccmas, ccmasMatric);
        String bt = signedIn(bmas, bmasMatric);

        assertThat(it.call(bursar, HttpMethod.POST, "/api/v1/finance/sessions/" + session + "/schedule", Map.of("item", "School fees", "amount", 100000, "level", 100)).getStatusCode().value()).isEqualTo(200);
        it.db(() -> {
            jdbc.sql("""
                    INSERT INTO policy.version (id, kind, scope, validity, instrument, decided_by)
                    SELECT gen_random_uuid(), 'clearance', 'UNIVERSITY',
                           daterange(current_date, (SELECT min(lower(validity)) FROM policy.version WHERE kind = 'clearance' AND scope = 'UNIVERSITY' AND lower(validity) > current_date)),
                           :i, 'bursar'
                     WHERE policy.in_force('clearance', 'UNIVERSITY', current_date) IS NULL
                    """).param("i", instrument).update();
            jdbc.sql("INSERT INTO policy.clearance_scheme SELECT id, true FROM policy.version WHERE instrument = :i ON CONFLICT DO NOTHING").param("i", instrument).update();
            jdbc.sql("""
                    INSERT INTO policy.clearance_rule SELECT v.id, p.code, CASE p.code WHEN 'HOSTEL' THEN 'NEVER_GATED' ELSE 'INSTALMENT_1' END
                      FROM policy.version v, ref.clearance_purpose p WHERE v.instrument = :i ON CONFLICT DO NOTHING
                    """).param("i", instrument).update();
            String dept = jdbc.sql("SELECT dept_code FROM ref.programme WHERE code = 'C00061'").query(String.class).single();
            for (int i = 1; i <= 9; i++) {
                String code = "IMU 10" + i;
                jdbc.sql("INSERT INTO catalogue.course (code, title, units, semester, level, dept_code, kind, state) VALUES (:c, :t, :u, 1, 100, :d, 'Elective', 'LIVE') ON CONFLICT (code) DO NOTHING")
                        .param("c", code).param("t", "Minimum Load Course " + i).param("u", i <= 7 ? 3 : 2).param("d", dept).update();
                jdbc.sql("INSERT INTO catalogue.course_offer (course_code, programme_code, level, basis) VALUES (:c, 'C00061', 100, 'Elective') ON CONFLICT DO NOTHING").param("c", code).update();
                jdbc.sql("INSERT INTO catalogue.offering (id, course_code, session, semester) VALUES (gen_random_uuid(), :c, :s, 1) ON CONFLICT (course_code, session, semester, stream) DO NOTHING")
                        .param("c", code).param("s", session).update();
            }
            return 0;
        });
        payInFull(ct);
        payInFull(bt);
        assertThat(it.call(academic, HttpMethod.PUT, "/api/v1/registration/approval/rules", Map.of("session", session, "mode", "AUTO_APPROVAL", "allowStudentReset", true,
                "cardOnApproval", true, "reason", "Integration test: automatic approval")).getStatusCode().value()).isEqualTo(200);

        // the standing rules, as the Directorate reads them, and as each student's registration screen says them
        assertThat(inForce(session, "CCMAS")).containsEntry("min_units", 15).containsEntry("applies_as", "STANDING");
        assertThat(inForce(session, "BMAS")).containsEntry("min_units", 18).containsEntry("applies_as", "STANDING");
        Map<String, Object> limit = (Map<String, Object>) it.get(ct, "/api/v1/me/registration?session=" + session + "&semester=1").getBody().get("limit");
        assertThat(limit).containsEntry("min_units", 15).containsEntry("curriculum", "CCMAS").containsEntry("basis", "CURRICULUM");
        assertThat((Map<String, Object>) it.get(bt, "/api/v1/me/registration?session=" + session + "&semester=1").getBody().get("limit")).containsEntry("min_units", 18);

        Map<String, UUID> cm = menu(ct);
        Map<String, UUID> bm = menu(bt);
        assertThat(cm).hasSize(9);

        // TEST 2, 1: CCMAS 14 refused, 15 approved at once (automatic approval never passes the minimum by)
        refused(submit(ct, cm, 4, 1), 15, 14, "CCMAS");
        assertThat(registration(ct)).containsEntry("status", "DRAFT");
        approved(submit(ct, cm, 5, 0));
        // TEST 5, 17: BMAS 17 refused, and no examination card for a registration not approved; TEST 13: the browser cannot name a curriculum
        refused(submit(bt, bm, 5, 1), 18, 17, "BMAS");
        assertThat(it.get(bt, "/api/v1/me/check-code?kind=EXAM&session=" + session + "&semester=1").getStatusCode().value()).isNotEqualTo(200);
        ResponseEntity<Map> named = it.call(bt, HttpMethod.POST, "/api/v1/me/registration/submit", Map.of("session", session, "semester", 1, "curriculum", "CCMAS", "minUnits", 1));
        assertThat(named.getStatusCode().value()).isNotEqualTo(200);
        assertThat(registration(bt)).containsEntry("status", "DRAFT");
        // the registrations below the minimum are listed for the offices: the BMAS draft of 17
        Map<String, Object> below = it.get(academic, "/api/v1/registration/load/below-minimum?session=" + session + "&semester=1").getBody();
        assertThat((List<Map<String, Object>>) below.get("rows")).anySatisfy(r -> {
            assertThat(r.get("student_id")).isEqualTo(bmas.toString());
            assertThat(r).containsEntry("curriculum", "BMAS").containsEntry("min_units", 18).containsEntry("units", 17).containsEntry("status", "DRAFT");
        });
        // TEST 24: the maximum still binds (25 units over the level's 24)
        ResponseEntity<Map> over = submit(bt, bm, 7, 2);
        assertThat(over.getStatusCode().value()).isEqualTo(422);
        assertThat(String.valueOf(over.getBody().get("detail"))).contains("range");
        // TEST 4: BMAS 18 approved
        approved(submit(bt, bm, 6, 0));

        // TEST 14, 15: a student, a Head of Department and the Academic Office cannot set the minimum
        String hod = it.officer("hod", "department", jdbc.sql("SELECT dept_code FROM ref.programme WHERE code = 'C00061'").query(String.class).single());
        assertThat(setMinimum(ct, "CCMAS", session, 1).getStatusCode().value()).isEqualTo(403);
        assertThat(setMinimum(hod, "CCMAS", session, 1).getStatusCode().value()).isEqualTo(403);
        assertThat(setMinimum(academic, "CCMAS", session, 1).getStatusCode().value()).isEqualTo(403);
        // TEST 21: 0, -5, "abc" and a minimum above the maximum are refused
        assertThat(setMinimum(ict, "CCMAS", session, 0).getBody().get("code")).isEqualTo("REG_MIN_UNITS_POSITIVE");
        assertThat(setMinimum(ict, "CCMAS", session, -5).getBody().get("code")).isEqualTo("REG_MIN_UNITS_POSITIVE");
        assertThat(setMinimum(ict, "CCMAS", session, "abc").getStatusCode().value()).isEqualTo(400);
        assertThat(setMinimum(ict, "CCMAS", session, 99).getBody().get("code")).isEqualTo("REG_MIN_UNITS_OVER_MAXIMUM");
        assertThat(inForce(session, "CCMAS")).containsEntry("min_units", 15);

        // TEST 7, 9: the Directorate raises the session's minimum: CCMAS 15 → 16, BMAS 18 → 20
        ResponseEntity<Map> raised = setMinimum(ict, "CCMAS", session, 16);
        assertThat(raised.getStatusCode().value()).as(String.valueOf(raised.getBody())).isEqualTo(200);
        assertThat(setMinimum(ict, "BMAS", session, 20).getStatusCode().value()).isEqualTo(200);
        assertThat(inForce(session, "CCMAS")).containsEntry("min_units", 16).containsEntry("applies_as", "SESSION");
        // TEST 27: the same scope set again is the one rule, not a second
        assertThat(setMinimum(ict, "CCMAS", session, 16).getStatusCode().value()).isEqualTo(200);
        assertThat(jdbc.sql("SELECT count(*) FROM registration.unit_minimum WHERE curriculum = 'CCMAS' AND session = :s").param("s", session).query(Long.class).single()).isEqualTo(1L);
        // TEST 22: each change logged with the value before and after
        List<Map<String, Object>> history = (List<Map<String, Object>>) it.get(ict, "/api/v1/registration/load/rules?session=" + session).getBody().get("history");
        assertThat(history).anySatisfy(h -> {
            assertThat(h).containsEntry("curriculum", "BMAS").containsEntry("session", session).containsEntry("after_units", 20)
                    .containsEntry("event", "COURSE_REGISTRATION_MIN_CREDIT_SET").containsEntry("changed_office", "ict");
        });
        // TEST 11: the registrations already approved are not rewritten
        assertThat(registration(ct)).containsEntry("status", "APPROVED");
        assertThat(jdbc.sql("SELECT registration.units_of(id) FROM registration.course_registration WHERE student_id = :s AND session = :ses AND semester = 1")
                .param("s", ccmas).param("ses", session).query(Integer.class).single()).isEqualTo(15);

        // TEST 8, 18, 19: reset and registered again: the new minimum at once — CCMAS 15 refused, 16 approved (TEST 3)
        reset(ct);
        assertThat((Map<String, Object>) it.get(ct, "/api/v1/me/registration?session=" + session + "&semester=1").getBody().get("limit")).containsEntry("min_units", 16);
        refused(submit(ct, cm, 5, 0), 16, 15, "CCMAS");
        approved(submit(ct, cm, 4, 2));
        // TEST 10: BMAS 18 refused now, 20 approved (TEST 6); the examination card follows the approved registration
        reset(bt);
        refused(submit(bt, bm, 6, 0), 20, 18, "BMAS");
        approved(submit(bt, bm, 6, 1));
        assertThat(it.get(bt, "/api/v1/me/check-code?kind=EXAM&session=" + session + "&semester=1").getStatusCode().value()).isEqualTo(200);

        // TEST 12: another session keeps its own: the next session reads the standing rule until the Directorate sets its own
        assertThat(inForce(next, "CCMAS")).containsEntry("min_units", 15).containsEntry("applies_as", "STANDING");
        assertThat(setMinimum(ict, "CCMAS", next, 17).getStatusCode().value()).isEqualTo(200);
        assertThat(inForce(next, "CCMAS")).containsEntry("min_units", 17);
        assertThat(inForce(session, "CCMAS")).containsEntry("min_units", 16);
        ResponseEntity<Map> removed = it.call(ict, HttpMethod.POST, "/api/v1/registration/load/rules/remove",
                Map.of("curriculum", "CCMAS", "session", next, "reason", "Integration test: the next session follows the standing rule"));
        assertThat(removed.getStatusCode().value()).as(String.valueOf(removed.getBody())).isEqualTo(200);
        assertThat(inForce(next, "CCMAS")).containsEntry("min_units", 15).containsEntry("applies_as", "STANDING");

        // the calendar keeps an undergraduate level's maximum at or above the highest curriculum minimum
        Map<String, Object> l100 = jdbc.sql("SELECT applies_to, min_units, max_units, carryover_counts FROM policy.level_limit WHERE level = 100").query().singleRow();
        ResponseEntity<Map> low = it.call(ict, HttpMethod.PUT, "/api/v1/calendar/levels/100", Map.of("appliesTo", l100.get("applies_to"), "minUnits", 1, "maxUnits", 14,
                "carryoverCounts", l100.get("carryover_counts")));
        assertThat(low.getBody().get("code")).isEqualTo("CAL_UNIT_RANGE_CURRICULUM");
        assertThat(jdbc.sql("SELECT max_units FROM policy.level_limit WHERE level = 100").query(Integer.class).single()).isEqualTo(((Number) l100.get("max_units")).intValue());
    }
}
