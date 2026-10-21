package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

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
 * V620 through the API: a course bound into a programme as an elective at the programme's own units; a student chooses it from the
 * menu. The binding's units changed leave the student's entry as registered (the desk's own tick carries the change); the binding
 * rebound as core leaves the entry the elective it was registered as; the binding removed while the student is registered on it is
 * not refused — the student's register still lists the course, as registered, the choice saved again keeps it, and unticked it goes.
 * Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT,
        properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
class BindingKeptForRegisteredIT {

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    ItSupport it;
    String session;
    String tag;
    String code;
    String prog;
    String ict;
    String bursar;

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
        int y = it.freeYear(2300, 2900);
        session = y + "/" + (y + 1);
        tag = Integer.toString(it.freeDraw(1_000, 10_000, k -> List.of("MOAUM/ADM/20/" + k + "61", "MOAUM/BKR/20/" + k + "1", "ZZBKR" + k)));
        code = "ZZB " + (600 + Integer.parseInt(tag) % 300);
        ict = TestTokens.token(it.person("ZZ-ICT-BIND-" + tag, "ZZICTBIND"), List.of("ict"));
        bursar = TestTokens.token(it.person("ZZBKR-BUR-" + tag, "ZZBKRBUR"), List.of("bursar"));
        it.session(session, y);
        prog = jdbc.sql("""
                SELECT p.code FROM ref.programme p
                 WHERE NOT coalesce(p.archived, false) AND coalesce(p.category, '') <> 'POST GRADUATE' AND finance.final_level(p.code) = 400
                   AND p.faculty_code NOT IN (SELECT faculty_code FROM finance.faculty_fee_source UNION SELECT source_faculty_code FROM finance.faculty_fee_source)
                 ORDER BY p.code DESC LIMIT 1
                """).query(String.class).single();
        it.db(() -> {
            jdbc.sql("""
                    INSERT INTO policy.semester (id, session, number, state) VALUES (gen_random_uuid(), :s, 1, 'OPEN'), (gen_random_uuid(), :s, 2, 'OPEN')
                    ON CONFLICT (session, number) DO UPDATE SET state = excluded.state
                    """).param("s", session).update();
            // a clearance scheme in force, releasing registration at the first instalment, where none is (as CourseRegistrationAutoApprovalIT)
            String instrument = "Integration test: BindingKeptForRegisteredIT " + tag;
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
            // a 200-Level course of the programme's department, taught in the first semester, with its class of the session
            String dept = jdbc.sql("SELECT dept_code FROM ref.programme WHERE code = :p").param("p", prog).query(String.class).single();
            jdbc.sql("""
                    INSERT INTO catalogue.course (code, title, units, semester, level, dept_code, kind, state)
                    VALUES (:c, :t, 3, 1, 200, :d, 'Core', 'LIVE') ON CONFLICT (code) DO UPDATE SET units = 3, state = 'LIVE', ended_on = NULL
                    """).param("c", code).param("t", "Binding kept " + tag).param("d", dept).update();
            jdbc.sql("DELETE FROM catalogue.course_offer WHERE course_code = :c").param("c", code).update();
            jdbc.sql("INSERT INTO catalogue.offering (id, course_code, session, semester) VALUES (gen_random_uuid(), :c, :s, 1) ON CONFLICT DO NOTHING").param("c", code).param("s", session).update();
            return null;
        });
    }

    @AfterEach
    void putBack() {
        if (it != null) it.db(() -> {
            jdbc.sql("DELETE FROM finance.fee_schedule WHERE session = :s").param("s", session).update();
            return null;
        });
    }

    @SuppressWarnings("unchecked")
    private static Map<String, Object> ok(ResponseEntity<Map> r) {
        assertThat(r.getStatusCode().value()).as(String.valueOf(r.getBody())).isEqualTo(200);
        return r.getBody();
    }

    @SuppressWarnings("unchecked")
    private Map<String, Object> entry(String token) {
        Map<String, Object> view = ok(it.get(token, "/api/v1/me/registration?session=" + session + "&semester=1"));
        Map<String, Object> reg = (Map<String, Object>) view.get("registration");
        List<Map<String, Object>> entries = reg == null ? List.of() : (List<Map<String, Object>>) reg.get("entries");
        return entries.stream().filter(e -> code.equals(e.get("courseCode"))).findFirst().orElse(null);
    }

    @SuppressWarnings("unchecked")
    private boolean onMenu(String token) {
        Map<String, Object> view = ok(it.get(token, "/api/v1/me/registration?session=" + session + "&semester=1"));
        return ((List<Map<String, Object>>) view.get("menu")).stream().anyMatch(m -> code.equals(m.get("course_code")));
    }

    @SuppressWarnings("unchecked")
    @Test
    void aBindingRemovedOrEditedNeverReachesARegisteredStudent() {
        UUID st = it.student("ZZBKR" + tag, prog, "MOAUM/ADM/20/" + tag + "61", "MOAUM/BKR/20/" + tag + "1", 200);
        String token = TestTokens.token(st, List.of("student"));
        // the session's fees stated for the level (the register opens on a stated semester, V461)
        List<Map<String, Object>> rows = List.of(
                Map.of("programmeCode", prog, "level", "200", "entryMode", "UTME", "semester", "1", "amount", "90000"),
                Map.of("programmeCode", prog, "level", "200", "entryMode", "UTME", "semester", "2", "amount", "80000"));
        assertThat(((Number) ok(it.call(bursar, HttpMethod.POST, "/api/v1/finance/sessions/" + session + "/fee-lines", Map.of("rows", rows))).get("added")).intValue()).isEqualTo(2);

        // bound as an elective of the programme at 200 Level, at the programme's own 2 units; the student chooses it from the menu
        ok(it.call(ict, HttpMethod.POST, "/api/v1/catalogue/structure/bind", Map.of("programme", prog, "course", code, "level", 200, "basis", "Elective", "units", 2)));
        assertThat(onMenu(token)).isTrue();
        Map<String, Object> view = ok(it.get(token, "/api/v1/me/registration?session=" + session + "&semester=1"));
        UUID offering = ((List<Map<String, Object>>) view.get("menu")).stream().filter(m -> code.equals(m.get("course_code")))
                .map(m -> UUID.fromString(String.valueOf(m.get("offering_id")))).findFirst().orElseThrow();
        ok(it.call(token, HttpMethod.PUT, "/api/v1/me/registration", Map.of("session", session, "semester", 1, "offerings", List.of(offering))));
        Map<String, Object> e = entry(token);
        assertThat(e).isNotNull();
        assertThat(e).containsEntry("units", 2).containsEntry("category", "ELECTIVE").containsEntry("basis", "Elective").containsEntry("entryType", "ELECTIVE");
        assertThat(jdbc.sql("SELECT basis FROM registration.entry WHERE offering_id = :o").param("o", offering).query(String.class).single()).isEqualTo("Elective");

        // the binding's units changed: the entry keeps its 2; the desk's own tick carries the change into the registrations not examined
        Map<String, Object> set = ok(it.call(ict, HttpMethod.POST, "/api/v1/catalogue/structure/units", Map.of("programme", prog, "course", code, "level", 200, "units", 1)));
        assertThat(set).containsEntry("units", 1).containsEntry("followed", 0).containsEntry("kept", 1).containsEntry("applied", false);
        assertThat(entry(token)).containsEntry("units", 2);
        Map<String, Object> carried = ok(it.call(ict, HttpMethod.POST, "/api/v1/catalogue/structure/units", Map.of("programme", prog, "course", code, "level", 200, "units", 1, "applyToRegistrations", true)));
        assertThat(carried).containsEntry("followed", 1).containsEntry("kept", 0).containsEntry("applied", true);
        assertThat(entry(token)).containsEntry("units", 1);

        // the binding rebound as core: the entry is still the elective it was registered as
        ok(it.call(ict, HttpMethod.POST, "/api/v1/catalogue/structure/bind", Map.of("programme", prog, "course", code, "level", 200, "basis", "Core")));
        e = entry(token);
        assertThat(e).containsEntry("category", "ELECTIVE").containsEntry("basis", "Elective").containsEntry("units", 1);
        assertThat(jdbc.sql("SELECT registration.is_elective_for(:s, :c)").param("s", st).param("c", code).query(Boolean.class).single()).isTrue();

        // the binding removed while the student is registered on it: not refused, on the record with the registration carried
        ResponseEntity<Map> removed = it.call(ict, HttpMethod.DELETE, b -> b.path("/api/v1/catalogue/structure/bind")
                .queryParam("programme", prog).queryParam("course", code).queryParam("level", 200).build(), null);
        assertThat(removed.getStatusCode().value()).as(String.valueOf(removed.getBody())).isEqualTo(200);
        assertThat(removed.getBody().get("outcome")).isEqualTo("ENDED");
        assertThat(jdbc.sql("SELECT registrations_carried FROM catalogue.course_offer_history WHERE course_code = :c AND programme_code = :p ORDER BY ended_at DESC LIMIT 1")
                .param("c", code).param("p", prog).query(Long.class).single()).isEqualTo(1L);
        // the student's register still lists the course as registered though it is on no menu; the choice saved again keeps it
        assertThat(onMenu(token)).isFalse();
        e = entry(token);
        assertThat(e).isNotNull();
        assertThat(e).containsEntry("category", "ELECTIVE").containsEntry("units", 1).containsEntry("status", "REGISTERED");
        ok(it.call(token, HttpMethod.PUT, "/api/v1/me/registration", Map.of("session", session, "semester", 1, "offerings", List.of(offering))));
        assertThat(entry(token)).isNotNull().containsEntry("units", 1).containsEntry("basis", "Elective");
        // unticked, it goes
        ok(it.call(token, HttpMethod.PUT, "/api/v1/me/registration", Map.of("session", session, "semester", 1, "offerings", List.of())));
        assertThat(entry(token)).isNull();
    }
}
