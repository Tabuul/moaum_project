package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

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
 * Prerequisites at registration (V482), over the API. The rule starts advisory: the student's form names the prerequisite not
 * yet passed and registers the course. Only the Academic Office sets the rule, and with a reason; enforced, the form locks the
 * course and the engine refuses it with REG_PREREQUISITE. A published pass in the prerequisite meets it, and the course
 * registers. The rule is put back to advisory after each run. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class PrerequisitesIT {

    static final String SESSION = "2151/2152";
    static final String EARLIER = "2150/2151";
    static final String PROGRAMME = "C00023";

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;
    ItSupport it;
    String academic = ItSupport.token("academic");
    String hod = ItSupport.token("hod");
    UUID s;
    String student, before, target, third, dept;
    UUID targetOffering;

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
        it.session(SESSION, 2151);
        it.session(EARLIER, 2150);
        int pick;
        do {
            pick = new Random().nextInt(9000) + 1000;
        } while (jdbc.sql("SELECT count(*) FROM catalogue.course WHERE code IN (:a, :b, :c)").param("a", "ZQA " + pick).param("b", "ZQB " + pick).param("c", "ZQC " + pick).query(Long.class).single() > 0
                || jdbc.sql("SELECT count(*) FROM people.student WHERE matric_no = :m").param("m", "MOAUM/PRQ/51/" + pick).query(Long.class).single() > 0);
        int n = pick;
        before = "ZQA " + n;
        target = "ZQB " + n;
        third = "ZQC " + n;
        s = it.student("ZZPRQ" + n, PROGRAMME, "MOAUM/ADM/51/" + String.format("%06d", 510000 + n), "MOAUM/PRQ/51/" + n, 200);
        student = TestTokens.token(s, List.of("student"));
        dept = jdbc.sql("SELECT dept_code FROM ref.programme WHERE code = :p").param("p", PROGRAMME).query(String.class).single();
        targetOffering = it.db(() -> {
            jdbc.sql("UPDATE people.student SET entry_session = :e, entry_level = 100, current_level = 200 WHERE id = :id").param("e", EARLIER).param("id", s).update();
            jdbc.sql("""
                    INSERT INTO catalogue.course (code, title, units, semester, level, dept_code, kind, state)
                    VALUES (:a, 'Prerequisite test foundation', 2, 1, 100, :d, 'Core', 'LIVE'), (:b, 'Prerequisite test advanced', 2, 1, 200, :d, 'Core', 'LIVE')
                    """).param("a", before).param("b", target).param("d", dept).update();
            jdbc.sql("INSERT INTO catalogue.course_offer (course_code, programme_code, level, basis) VALUES (:a, :p, 100, 'Core'), (:b, :p, 200, 'Core')")
                    .param("a", before).param("b", target).param("p", PROGRAMME).update();
            jdbc.sql("INSERT INTO catalogue.course_prerequisite (course_code, requires_code) VALUES (:b, :a)").param("a", before).param("b", target).update();
            return jdbc.sql("INSERT INTO catalogue.offering (id, course_code, session, semester) VALUES (gen_random_uuid(), :b, :s, 1) RETURNING id")
                    .param("b", target).param("s", SESSION).query(UUID.class).single();
        });
    }

    @AfterEach
    void advisoryAgain() {
        it.call(academic, HttpMethod.PUT, "/api/v1/registration/prerequisite-policy", Map.of("mode", "ADVISORY", "reason", "integration test: as before"));
    }

    private Map<String, Object> menuRow() {
        ResponseEntity<Map> v = it.get(student, "/api/v1/me/registration?session=" + SESSION + "&semester=1");
        assertThat(v.getStatusCode().value()).as(String.valueOf(v.getBody())).isEqualTo(200);
        return ((List<Map<String, Object>>) v.getBody().get("menu")).stream().filter(m -> target.equals(m.get("course_code"))).findFirst().orElseThrow();
    }

    private ResponseEntity<Map> choose() {
        return it.call(student, HttpMethod.PUT, "/api/v1/me/registration", Map.of("session", SESSION, "semester", 1, "offerings", List.of(targetOffering)));
    }

    @Test
    void aPrerequisiteIsShownWhileAdvisoryRefusedWhenTheAcademicOfficeEnforcesItAndMetByAPublishedPass() {
        // advisory, as before: named on the form, and the course registers
        assertThat(it.get(student, "/api/v1/registration/prerequisite-policy").getBody().get("mode")).isEqualTo("ADVISORY");
        Map<String, Object> row = menuRow();
        assertThat(row.get("prerequisitesUnmet")).isEqualTo(before);
        assertThat(row.get("prerequisiteLocked")).isEqualTo(false);
        ResponseEntity<Map> advisory = choose();
        assertThat(advisory.getStatusCode().value()).as(String.valueOf(advisory.getBody())).isEqualTo(200);

        // only the Academic Office sets the rule, and with a reason
        assertThat(it.call(hod, HttpMethod.PUT, "/api/v1/registration/prerequisite-policy", Map.of("mode", "ENFORCED", "reason", "asked")).getStatusCode().value()).isEqualTo(403);
        ResponseEntity<Map> noReason = it.call(academic, HttpMethod.PUT, "/api/v1/registration/prerequisite-policy", Map.of("mode", "ENFORCED", "reason", " "));
        assertThat(noReason.getStatusCode().value()).as(String.valueOf(noReason.getBody())).isEqualTo(422);
        assertThat(noReason.getBody().get("code")).isEqualTo("PREREQUISITE_MODE_REASON");
        ResponseEntity<Map> enforced = it.call(academic, HttpMethod.PUT, "/api/v1/registration/prerequisite-policy", Map.of("mode", "ENFORCED", "reason", "Senate decision, integration test"));
        assertThat(enforced.getStatusCode().value()).as(String.valueOf(enforced.getBody())).isEqualTo(200);
        assertThat(enforced.getBody().get("mode")).isEqualTo("ENFORCED");
        assertThat(enforced.getBody().get("changed_office")).isEqualTo("academic");

        // enforced: the form locks it and the engine refuses it, naming the prerequisite
        row = menuRow();
        assertThat(row.get("prerequisiteLocked")).isEqualTo(true);
        ResponseEntity<Map> refused = choose();
        assertThat(refused.getStatusCode().value()).as(String.valueOf(refused.getBody())).isEqualTo(422);
        assertThat(refused.getBody().get("code")).isEqualTo("REG_PREREQUISITE");
        assertThat(String.valueOf(refused.getBody().get("detail"))).contains(target).contains(before);

        // a published pass in the prerequisite meets it
        it.db(() -> {
            UUID o = jdbc.sql("INSERT INTO catalogue.offering (id, course_code, session, semester) VALUES (gen_random_uuid(), :a, :e, 1) RETURNING id")
                    .param("a", before).param("e", EARLIER).query(UUID.class).single();
            UUID reg = jdbc.sql("""
                    INSERT INTO registration.course_registration (id, student_id, session, semester, level, status, submitted_at, approved_at)
                    VALUES (gen_random_uuid(), :s, :e, 1, 100, 'APPROVED', now(), now()) RETURNING id
                    """).param("s", s).param("e", EARLIER).query(UUID.class).single();
            jdbc.sql("INSERT INTO registration.entry (registration_id, offering_id, units, status) VALUES (:r, :o, 2, 'APPROVED')").param("r", reg).param("o", o).update();
            UUID sheet = UUID.randomUUID();
            jdbc.sql("INSERT INTO assessment.score_sheet (id, offering_id, stage, senate_minute, published_at, submitted_at) VALUES (:id, :o, 'PUBLISHED', 'SEN/2151/01', now(), now())")
                    .param("id", sheet).param("o", o).update();
            return jdbc.sql("INSERT INTO assessment.score (sheet_id, student_id, ca, exam, outcome) VALUES (:sh, :s, 25, 45, 'GRADED')").param("sh", sheet).param("s", s).update();
        });
        row = menuRow();
        assertThat(row.get("prerequisitesUnmet")).isNull();
        ResponseEntity<Map> met = choose();
        assertThat(met.getStatusCode().value()).as(String.valueOf(met.getBody())).isEqualTo(200);
    }

    /** V487: an upload previewed row by row (nothing kept), then imported; another department's row reported and not written;
     *  whom enforcing stops listed for the Academic Office, not for a Head of Department */
    @Test
    void prerequisitesAreUploadedAfterAPreviewAndWhomEnforcingStopsIsListed() {
        it.db(() -> jdbc.sql("INSERT INTO catalogue.course (code, title, units, semester, level, dept_code, kind, state) VALUES (:c, 'Prerequisite test third', 2, 1, 300, :d, 'Core', 'LIVE')")
                .param("c", third).param("d", dept).update());
        List<Map<String, Object>> rows = List.of(
                Map.of("course", third, "requires", target),            // new
                Map.of("course", third, "requires", third),             // itself
                Map.of("course", before, "requires", third),            // would close a loop: third → target → before
                Map.of("course", "ZQX 99999", "requires", before),      // no such course
                Map.of("course", target.toLowerCase(), "requires", before));   // recorded already (read as the pool reads codes)
        ResponseEntity<Map> preview = it.call(academic, HttpMethod.POST, "/api/v1/catalogue/prerequisites/upload/preview", Map.of("rows", rows));
        assertThat(preview.getStatusCode().value()).as(String.valueOf(preview.getBody())).isEqualTo(200);
        assertThat(((List<Map<String, Object>>) preview.getBody().get("rows")).stream().map(r -> r.get("outcome")).toList())
                .containsExactly("ADDED", "SELF", "CYCLE", "NO_COURSE", "ALREADY");
        assertThat(jdbc.sql("SELECT count(*) FROM catalogue.course_prerequisite WHERE course_code = :c").param("c", third).query(Long.class).single()).isZero();

        // another department's Head of Department: the row reported, nothing written
        String otherDept = jdbc.sql("SELECT code FROM ref.department WHERE code <> :d ORDER BY code LIMIT 1").param("d", dept).query(String.class).single();
        String otherHod = it.officer("hod", "department", otherDept);
        ResponseEntity<Map> outside = it.call(otherHod, HttpMethod.POST, "/api/v1/catalogue/prerequisites/upload", Map.of("rows", List.of(Map.of("course", third, "requires", target))));
        assertThat(outside.getStatusCode().value()).as(String.valueOf(outside.getBody())).isEqualTo(200);
        assertThat(((List<Map<String, Object>>) outside.getBody().get("rows")).get(0).get("outcome")).isEqualTo("OUTSIDE_SCOPE");
        assertThat(jdbc.sql("SELECT count(*) FROM catalogue.course_prerequisite WHERE course_code = :c").param("c", third).query(Long.class).single()).isZero();

        // imported: what the preview said is written
        ResponseEntity<Map> imported = it.call(academic, HttpMethod.POST, "/api/v1/catalogue/prerequisites/upload", Map.of("rows", rows));
        assertThat(imported.getStatusCode().value()).as(String.valueOf(imported.getBody())).isEqualTo(200);
        assertThat(imported.getBody().get("added")).isEqualTo(1);
        assertThat(jdbc.sql("SELECT requires_code FROM catalogue.course_prerequisite WHERE course_code = :c").param("c", third).query(String.class).list()).containsExactly(target);

        // whom enforcing stops: the student of the programme at 200 level who has not passed the prerequisite
        ResponseEntity<Map> impact = it.get(academic, u -> u.path("/api/v1/catalogue/prerequisites/impact").queryParam("course", target).build());
        assertThat(impact.getStatusCode().value()).as(String.valueOf(impact.getBody())).isEqualTo(200);
        assertThat((List<Map<String, Object>>) impact.getBody().get("rows")).anySatisfy(r -> {
            assertThat(r.get("student_id")).isEqualTo(s.toString());
            assertThat(r.get("unmet")).isEqualTo(before);
        });
        assertThat(it.get(hod, "/api/v1/catalogue/prerequisites/impact").getStatusCode().value()).isEqualTo(403);
    }
}
