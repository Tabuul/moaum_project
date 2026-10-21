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
 * V590: every curriculum's courses open to every student, on the student's own door. Two invented students of one programme at
 * 100 Level, one on the BMAS track and one on CCMAS_MOAU, and two courses bound to the programme at that level, one for each track.
 * The Bursary may not change the rule; the Directorate of ICT keeps the curricula apart and each student's registration lists their
 * own track's course alone; it opens them again and both students list both courses. The run files everything under its own
 * session, and the rule is left open. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class CurriculumOpenIT {

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    ItSupport it;
    final String ict = ItSupport.token("ict");
    final String bursar = ItSupport.token("bursar");
    static final String FLEX = "/api/v1/registration/flex";

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
    }

    /** the curricula left open, as V590 leaves them */
    @AfterEach
    void clean() {
        it.call(ict, HttpMethod.PUT, FLEX + "/curriculum", Map.of("open", true, "reason", "Integration test: every curriculum open again"));
    }

    private List<String> listed(UUID student, String session) {
        ResponseEntity<Map> r = it.call(TestTokens.token(student, List.of("student")), HttpMethod.GET, "/api/v1/me/registration?session=" + session + "&semester=1", null);
        assertThat(r.getStatusCode().value()).as(String.valueOf(r.getBody())).isEqualTo(200);
        return ((List<Map<String, Object>>) r.getBody().get("menu")).stream().map(m -> String.valueOf(m.get("course_code"))).filter(c -> c.startsWith("ICV ")).sorted().toList();
    }

    @Test
    void eachStudentListsEveryCurriculumsCoursesWhileTheyAreOpenAndTheirOwnWhenKeptApart() {
        int y = it.freeYear(2600, 2850);
        String session = y + "/" + (y + 1);
        it.session(session, y);
        String yy = String.format("%02d", y % 100);
        int n = it.freeDraw(1000, 9999, k -> List.of("ZZCURA" + k, "ZZCURB" + k, "MOAUM/ADM/" + yy + "/59" + k, "MOAUM/ADM/" + yy + "/58" + k));
        UUID bmas = it.student("ZZCURA" + n, "C00061", "MOAUM/ADM/" + yy + "/59" + n, null, 100);
        UUID ccmas = it.student("ZZCURB" + n, "C00061", "MOAUM/ADM/" + yy + "/58" + n, null, 100);
        it.db(() -> {
            jdbc.sql("UPDATE people.student SET curriculum_track = 'BMAS' WHERE id = :s").param("s", bmas).update();
            jdbc.sql("UPDATE people.student SET curriculum_track = 'CCMAS_MOAU' WHERE id = :s").param("s", ccmas).update();
            String dept = jdbc.sql("SELECT dept_code FROM ref.programme WHERE code = 'C00061'").query(String.class).single();
            jdbc.sql("""
                    INSERT INTO catalogue.course (code, title, units, semester, level, dept_code, kind, state, curriculum) VALUES
                        ('ICV 101', 'Curriculum Open BMAS', 3, 1, 100, :d, 'Core', 'LIVE', 'BMAS'), ('ICV 102', 'Curriculum Open CCMAS', 3, 1, 100, :d, 'Core', 'LIVE', 'CCMAS')
                    ON CONFLICT (code) DO NOTHING
                    """).param("d", dept).update();
            jdbc.sql("""
                    INSERT INTO catalogue.course_offer (course_code, programme_code, level, basis, track) VALUES
                        ('ICV 101', 'C00061', 100, 'Core', 'BMAS'), ('ICV 102', 'C00061', 100, 'Core', 'CCMAS_MOAU')
                    ON CONFLICT DO NOTHING
                    """).update();
            return jdbc.sql("""
                    INSERT INTO catalogue.offering (id, course_code, session, semester)
                    SELECT gen_random_uuid(), c, :s, 1 FROM unnest(ARRAY['ICV 101', 'ICV 102']) c
                    ON CONFLICT (course_code, session, semester, stream) DO NOTHING
                    """).param("s", session).update();
        });
        assertThat(jdbc.sql("SELECT string_agg(curriculum_version, ',' ORDER BY surname) FROM people.student WHERE id IN (:a, :b)").param("a", bmas).param("b", ccmas)
                .query(String.class).single()).isEqualTo("BMAS,CCMAS");

        // the Bursary does not set the rule
        ResponseEntity<Map> refused = it.call(bursar, HttpMethod.PUT, FLEX + "/curriculum", Map.of("open", false, "reason", "the Bursary trying to change it"));
        assertThat(refused.getStatusCode().value()).isEqualTo(403);

        // kept apart: each student lists their own track's course alone
        ResponseEntity<Map> apart = it.call(ict, HttpMethod.PUT, FLEX + "/curriculum", Map.of("open", false, "reason", "Integration test: the curricula kept apart"));
        assertThat(apart.getStatusCode().value()).as(String.valueOf(apart.getBody())).isEqualTo(200);
        assertThat(apart.getBody()).containsEntry("curriculum_open", false).containsEntry("set_office", "ict");
        assertThat(listed(bmas, session)).containsExactly("ICV 101");
        assertThat(listed(ccmas, session)).containsExactly("ICV 102");

        // open: both students list both courses, whatever their cohort
        ResponseEntity<Map> opened = it.call(ict, HttpMethod.PUT, FLEX + "/curriculum", Map.of("open", true, "reason", "Integration test: every curriculum open"));
        assertThat(opened.getBody()).containsEntry("curriculum_open", true);
        assertThat(it.get(ict, FLEX).getBody()).containsEntry("curriculum_open", true);
        assertThat(listed(bmas, session)).containsExactly("ICV 101", "ICV 102");
        assertThat(listed(ccmas, session)).containsExactly("ICV 101", "ICV 102");
    }
}
