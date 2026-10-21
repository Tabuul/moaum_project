package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.ArrayList;
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
 * V503: the industrial-training (SIWES) semester, end to end on the student's own door. The screen asks for exactly the SIWES
 * course's units; the submission now reads the same: the SIWES course alone is approved at once (automatic approval), the SIWES
 * course with another course is refused with the SIWES words, never with the curriculum's minimum. Each run files everything under
 * its own session, and takes its SIWES course off the programme afterwards. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class SiwesLoadIT {

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    ItSupport it;
    final String academic = ItSupport.token("academic");
    final String instrument = "BUR/IT/SIWES503";
    static final String PROGRAMME = "C00061";
    static final int LEVEL = 500;
    String session;

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
    }

    /** the run's fee line and clearance scheme taken away, and the SIWES course off the programme — or every student of the
     *  programme at the level would be in a SIWES semester for the tests that follow */
    @AfterEach
    void clean() {
        it.db(() -> {
            if (session != null) jdbc.sql("DELETE FROM finance.fee_schedule WHERE session = :s").param("s", session).update();
            // off the programme, the SIWES course makes no semester a SIWES one (registration.siwes_units reads the programme's offers)
            jdbc.sql("DELETE FROM catalogue.course_offer WHERE course_code IN ('IWT 591', 'IWN 591') AND programme_code = :p AND level = :l").param("p", PROGRAMME).param("l", LEVEL).update();
            jdbc.sql("DELETE FROM policy.clearance_rule WHERE version_id IN (SELECT id FROM policy.version WHERE instrument = :i)").param("i", instrument).update();
            jdbc.sql("DELETE FROM policy.clearance_scheme WHERE version_id IN (SELECT id FROM policy.version WHERE instrument = :i)").param("i", instrument).update();
            return jdbc.sql("DELETE FROM policy.version WHERE instrument = :i").param("i", instrument).update();
        });
    }

    private ResponseEntity<Map> submit(String token, Map<String, UUID> menu, String... codes) {
        List<UUID> chosen = new ArrayList<>();
        for (String c : codes) chosen.add(menu.get(c));
        ResponseEntity<Map> saved = it.call(token, HttpMethod.PUT, "/api/v1/me/registration", Map.of("session", session, "semester", 1, "offerings", chosen));
        assertThat(saved.getStatusCode().value()).as(String.valueOf(saved.getBody())).isEqualTo(200);
        return it.call(token, HttpMethod.POST, "/api/v1/me/registration/submit", Map.of("session", session, "semester", 1));
    }

    @Test
    void theSiwesCourseAloneIsSubmittedAndApprovedAndAnythingMoreIsRefusedWithTheSiwesWords() {
        int y = it.freeYear(4500, 4950);
        session = y + "/" + (y + 1);
        it.session(session, y);
        String yy = String.format("%02d", y % 100);
        int n = 1000 + new Random().nextInt(8999);
        UUID student = it.student("ZZSIWES" + n, PROGRAMME, "MOAUM/ADM/" + yy + "/71" + n, "MOAUM/SIW/" + yy + "/" + n, LEVEL);
        it.db(() -> {
            jdbc.sql("UPDATE people.student SET curriculum_version = 'CCMAS', current_level = :l WHERE id = :s").param("l", LEVEL).param("s", student).update();
            String dept = jdbc.sql("SELECT dept_code FROM ref.programme WHERE code = :p").param("p", PROGRAMME).query(String.class).single();
            jdbc.sql("""
                    INSERT INTO catalogue.course (code, title, units, semester, level, dept_code, kind, state, industrial_training) VALUES
                        ('IWT 591', 'Industrial Training (test)', 6, 1, :l, :d, 'Core', 'LIVE', true), ('IWN 591', 'Ordinary Course (test)', 3, 1, :l, :d, 'Elective', 'LIVE', false)
                    ON CONFLICT (code) DO UPDATE SET industrial_training = EXCLUDED.industrial_training, units = EXCLUDED.units, semester = 1
                    """).param("l", LEVEL).param("d", dept).update();
            jdbc.sql("INSERT INTO catalogue.course_offer (course_code, programme_code, level, basis) VALUES ('IWT 591', :p, :l, 'Core'), ('IWN 591', :p, :l, 'Elective') ON CONFLICT DO NOTHING")
                    .param("p", PROGRAMME).param("l", LEVEL).update();
            jdbc.sql("INSERT INTO catalogue.offering (id, course_code, session, semester) SELECT gen_random_uuid(), c, :s, 1 FROM unnest(ARRAY['IWT 591', 'IWN 591']) c ON CONFLICT (course_code, session, semester, stream) DO NOTHING")
                    .param("s", session).update();
            // the session's school fees stated and paid, and a clearance scheme in force where none is
            jdbc.sql("INSERT INTO finance.fee_schedule (session, item, amount, level, programme_code) VALUES (:s, 'School fees', 100000, :l, :p)")
                    .param("s", session).param("l", LEVEL).param("p", PROGRAMME).update();
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
            String ref = jdbc.sql("SELECT finance.new_purpose_reference(:s, :ses, 100000, 'School fees ' || :ses)").param("s", student).param("ses", session).query(String.class).single();
            return jdbc.sql("SELECT finance.confirm_payment(:r, 'BANK_BRANCH', 'teller for the SIWES test')").param("r", ref).query(String.class).single();
        });
        assertThat(it.call(academic, HttpMethod.PUT, "/api/v1/registration/approval/rules", Map.of("session", session, "mode", "AUTO_APPROVAL", "allowStudentReset", true,
                "cardOnApproval", true, "reason", "Integration test: automatic approval")).getStatusCode().value()).isEqualTo(200);
        String token = TestTokens.token(student, List.of("student"));

        // the screen: exactly the SIWES course's units
        Map<String, Object> view = it.get(token, "/api/v1/me/registration?session=" + session + "&semester=1").getBody();
        assertThat(view).as(String.valueOf(view)).containsEntry("siwes", true);
        assertThat((Map<String, Object>) view.get("limit")).containsEntry("min_units", 6).containsEntry("max_units", 6);
        Map<String, UUID> menu = new java.util.HashMap<>();
        for (Map<String, Object> m : (List<Map<String, Object>>) view.get("menu")) {
            String code = String.valueOf(m.get("course_code"));
            if (code.equals("IWT 591") || code.equals("IWN 591")) menu.put(code, UUID.fromString(String.valueOf(m.get("offering_id"))));
        }
        assertThat(menu).containsKeys("IWT 591", "IWN 591");

        // the SIWES course and another: refused with the SIWES words, not the curriculum's minimum
        ResponseEntity<Map> more = submit(token, menu, "IWT 591", "IWN 591");
        assertThat(more.getStatusCode().value()).as(String.valueOf(more.getBody())).isEqualTo(422);
        assertThat(more.getBody().get("code")).isEqualTo("REG_SIWES_UNITS");
        assertThat(String.valueOf(more.getBody().get("detail"))).contains("exactly 6 credit units").contains("carries 9 credit units");

        // the SIWES course alone (6 units, under the CCMAS minimum of 15): submitted and approved at once
        ResponseEntity<Map> alone = submit(token, menu, "IWT 591");
        assertThat(alone.getStatusCode().value()).as(String.valueOf(alone.getBody())).isEqualTo(200);
        assertThat(alone.getBody().get("result")).isEqualTo("approved");
    }
}
