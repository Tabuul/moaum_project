package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.ThreadLocalRandom;

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
 * V483: a postgraduate programme's specialisations on its one structure, over the API. The School's Secretary adds them (never
 * to an undergraduate programme, never a code twice), names a bound course for one, and gives the programme's students theirs
 * (never another programme's student or specialisation, never an ended one); the course is on the registration menu of that
 * specialisation's students only, a course for every student on everyone's; another department's Head of Department changes
 * nothing. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class PgSpecialisationsIT {

    static final String SESSION = "2153/2154";
    static final String BASE = "/api/v1/catalogue/structure/specialisations";

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    ItSupport it;
    final String academic = ItSupport.token("academic");
    String pg, pgDept, otherPg, ug, ugDept, tag, sec;

    static List<Map<String, Object>> l(Object o) { return (List<Map<String, Object>>) o; }

    private static String code(ResponseEntity<Map> r) { return r.getBody() == null ? null : String.valueOf(r.getBody().get("code")); }

    private Map<String, Object> ok(ResponseEntity<Map> r) {
        assertThat(r.getStatusCode().value()).as(String.valueOf(r.getBody())).isEqualTo(200);
        return r.getBody();
    }

    private static String newCode() {
        ThreadLocalRandom r = ThreadLocalRandom.current();
        return "Z" + (char) ('A' + r.nextInt(26)) + (char) ('A' + r.nextInt(26)) + " 8" + String.format("%02d", r.nextInt(100));
    }

    private String office(String office, String who) {
        UUID p = it.person("ZZ-PGSP-" + who, "ZZPGSP" + who);
        it.db(() -> jdbc.sql("""
                INSERT INTO iam.office_assignment (id, person_id, office_code, scope_kind, scope_id, instrument, granted_by, valid_from)
                SELECT gen_random_uuid(), :p, :o, 'platform', NULL, 'integration test', :p, current_date
                 WHERE NOT EXISTS (SELECT 1 FROM iam.office_assignment a WHERE a.person_id = :p AND a.office_code = :o AND (a.valid_to IS NULL OR a.valid_to >= current_date))
                """).param("p", p).param("o", office).update());
        return TestTokens.token(p, List.of(office));
    }

    /** a postgraduate student of the programme; n (1, 2) keeps the numbers apart within a run */
    private UUID pgStudent(int n) {
        UUID s = it.student("ZZPGSP" + n + "T" + tag, pg, "MOAUM/ADM/53/" + n + "0" + tag, "MOAUM/PGS/53/" + n + tag, 800);
        it.db(() -> jdbc.sql("UPDATE people.student SET entry_mode = 'POSTGRADUATE', entry_session = :s, entry_level = 800, current_level = 800 WHERE id = :id")
                .param("s", SESSION).param("id", s).update());
        return s;
    }

    private List<String> menu(UUID student) {
        ResponseEntity<Map> v = it.get(TestTokens.token(student, List.of("student")), "/api/v1/me/registration?session=" + SESSION + "&semester=1");
        assertThat(v.getStatusCode().value()).as(String.valueOf(v.getBody())).isEqualTo(200);
        return l(v.getBody().get("menu")).stream().map(m -> String.valueOf(m.get("course_code"))).toList();
    }

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
        it.session(SESSION, 2153);
        tag = Integer.toString(ThreadLocalRandom.current().nextInt(1000, 9999));
        List<Map<String, Object>> pgs = jdbc.sql("""
                SELECT p.code, p.dept_code FROM ref.programme p WHERE p.category = 'POST GRADUATE' AND NOT coalesce(p.archived, false) ORDER BY p.code LIMIT 2
                """).query().listOfRows();
        pg = String.valueOf(pgs.get(0).get("code"));
        pgDept = String.valueOf(pgs.get(0).get("dept_code"));
        otherPg = String.valueOf(pgs.get(1).get("code"));
        Map<String, Object> u = jdbc.sql("""
                SELECT p.code, p.dept_code FROM ref.programme p WHERE p.category = 'UNDER GRADUATE' AND NOT coalesce(p.archived, false) AND p.dept_code <> :d ORDER BY p.code LIMIT 1
                """).param("d", pgDept).query().singleRow();
        ug = String.valueOf(u.get("code"));
        ugDept = String.valueOf(u.get("dept_code"));
        sec = office("pgsecretary", "SEC" + tag);
    }

    @Test
    void aSpecialisationsCourseReachesOnlyItsStudents() {
        // added to the postgraduate programme; never to an undergraduate one, never a code twice
        String mon = "M" + tag;
        String dev = "D" + tag;
        UUID monId = UUID.fromString(String.valueOf(ok(it.call(sec, HttpMethod.POST, BASE, Map.of("programme", pg, "code", mon, "name", "Monetary " + tag))).get("id")));
        ok(it.call(sec, HttpMethod.POST, BASE, Map.of("programme", pg, "code", dev, "name", "Development " + tag)));
        assertThat(code(it.call(sec, HttpMethod.POST, BASE, Map.of("programme", ug, "code", "OPT", "name", "Undergraduate option")))).isEqualTo("STRUCTURE_PG_ONLY");
        assertThat(code(it.call(academic, HttpMethod.POST, BASE, Map.of("programme", ug, "code", "OPT", "name", "Undergraduate option")))).isEqualTo("PG_SPECIALISATION_PROGRAMME");
        assertThat(code(it.call(sec, HttpMethod.POST, BASE, Map.of("programme", pg, "code", mon, "name", "Another name " + tag)))).isEqualTo("PG_SPECIALISATION_TAKEN");
        UUID foreign = UUID.fromString(String.valueOf(ok(it.call(sec, HttpMethod.POST, BASE, Map.of("programme", otherPg, "code", mon, "name", "Monetary " + tag))).get("id")));

        // two courses bound at 800 level with a class this session: one for every student, one named for MON
        String general = newCode();
        String pickOption = newCode();
        while (pickOption.equals(general)) pickOption = newCode();
        String option = pickOption;
        for (String c : List.of(general, option)) {
            ok(it.call(sec, HttpMethod.POST, "/api/v1/catalogue/courses", Map.of("code", c, "title", "Specialisation check " + c, "units", 3, "semester", 1,
                    "level", 800, "dept", pgDept, "kind", "Core", "offers", List.of(Map.of("programme", pg, "level", 800, "basis", "Core")))));
            it.db(() -> jdbc.sql("INSERT INTO catalogue.offering (id, course_code, session, semester, stream) VALUES (gen_random_uuid(), :c, :s, 1, 'PG') ON CONFLICT DO NOTHING")
                    .param("c", c).param("s", SESSION).update());
        }
        ok(it.call(sec, HttpMethod.PUT, BASE + "/binding", Map.of("programme", pg, "course", option, "level", 800, "specialisations", List.of(monId))));
        assertThat(code(it.call(sec, HttpMethod.PUT, BASE + "/binding", Map.of("programme", pg, "course", option, "level", 800, "specialisations", List.of(foreign)))))
                .isEqualTo("PG_SPECIALISATION_OTHER");
        List<Map<String, Object>> rows = l(ok(it.get(sec, "/api/v1/catalogue/structure?prog=" + pg)).get("rows"));
        assertThat(rows).anySatisfy(r -> { assertThat(r.get("code")).isEqualTo(option); assertThat(r.get("specialisations")).isEqualTo(mon); });
        assertThat(rows).anySatisfy(r -> { assertThat(r.get("code")).isEqualTo(general); assertThat(r.get("specialisations")).isNull(); });

        // the programme's students given theirs; another programme's specialisation or student refused
        UUID a = pgStudent(1);
        UUID none = pgStudent(2);
        ok(it.call(sec, HttpMethod.PUT, BASE + "/students", Map.of("programme", pg, "specialisation", monId.toString(), "students", List.of(a))));
        assertThat(code(it.call(sec, HttpMethod.PUT, BASE + "/students", Map.of("programme", pg, "specialisation", foreign.toString(), "students", List.of(none)))))
                .isEqualTo("PG_SPECIALISATION_OTHER");
        UUID outsider = it.student("ZZPGSP3T" + tag, ug, "MOAUM/ADM/53/30" + tag, null, 100);
        assertThat(code(it.call(sec, HttpMethod.PUT, BASE + "/students", Map.of("programme", pg, "specialisation", monId.toString(), "students", List.of(outsider)))))
                .isEqualTo("PG_SPECIALISATION_OTHER");
        Map<String, Object> listed = ok(it.get(sec, BASE + "?prog=" + pg));
        assertThat(l(listed.get("specialisations"))).anySatisfy(s -> { assertThat(s.get("code")).isEqualTo(mon); assertThat(((Number) s.get("students")).intValue()).isEqualTo(1); });

        // the menu: MON's student sees both; a student without one sees the course for every student only
        assertThat(menu(a)).contains(general, option);
        assertThat(menu(none)).contains(general).doesNotContain(option);

        // ended: no longer given to a student, restored: given again
        ok(it.call(sec, HttpMethod.POST, BASE + "/" + monId + "/end", Map.of()));
        assertThat(code(it.call(sec, HttpMethod.PUT, BASE + "/students", Map.of("programme", pg, "specialisation", monId.toString(), "students", List.of(none)))))
                .isEqualTo("PG_SPECIALISATION_OTHER");
        ok(it.call(sec, HttpMethod.POST, BASE + "/" + monId + "/restore", Map.of()));

        // another department's Head of Department changes nothing here
        String hod = it.officer("hod", "department", ugDept);
        assertThat(code(it.call(hod, HttpMethod.PUT, BASE + "/binding", Map.of("programme", pg, "course", option, "level", 800, "specialisations", List.of()))))
                .isEqualTo("CAT_DEPT");
    }

    /** V488: the form's programme list carries the running specialisations; a file of students' specialisations is previewed
     *  (nothing kept), then set; the School's list counts each student's required courses passed */
    @Test
    void specialisationsReachTheFormAndAreUploadedForStudents() {
        String code = "U" + tag;
        UUID spec = UUID.fromString(String.valueOf(ok(it.call(sec, HttpMethod.POST, BASE, Map.of("programme", pg, "code", code, "name", "Upload " + tag))).get("id")));
        List<Map<String, Object>> progs = (List<Map<String, Object>>) (List<?>) it.getList(sec, "/api/v1/pg/programmes").getBody();
        assertThat(progs).anySatisfy(p -> {
            assertThat(p.get("code")).isEqualTo(pg);
            assertThat(l(p.get("specialisations"))).anySatisfy(sp -> assertThat(sp.get("code")).isEqualTo(code));
        });

        UUID st = pgStudent(3);
        String number = jdbc.sql("SELECT coalesce(matric_no, admission_no) FROM people.student WHERE id = :s").param("s", st).query(String.class).single();
        List<Map<String, Object>> rows = List.of(Map.of("number", number, "specialisation", code.toLowerCase()), Map.of("number", "MOAUM/ADM/53/999999", "specialisation", code));
        Map<String, Object> preview = ok(it.call(sec, HttpMethod.POST, BASE + "/students/upload/preview", Map.of("programme", pg, "rows", rows)));
        assertThat(l(preview.get("rows")).stream().map(r -> r.get("outcome")).toList()).containsExactly("SET", "NO_STUDENT");
        assertThat(jdbc.sql("SELECT count(*) FROM people.student_specialisation WHERE student_id = :s").param("s", st).query(Long.class).single()).isZero();
        Map<String, Object> set = ok(it.call(sec, HttpMethod.POST, BASE + "/students/upload", Map.of("programme", pg, "rows", rows)));
        assertThat(set.get("set")).isEqualTo(1);
        assertThat(jdbc.sql("SELECT specialisation_id FROM people.student_specialisation WHERE student_id = :s").param("s", st).query(UUID.class).single()).isEqualTo(spec);

        // the School's list: the student's required courses (the programme's Core at their level, theirs and their specialisation's)
        Map<String, Object> listed = ok(it.get(sec, BASE + "?prog=" + pg));
        assertThat(l(listed.get("students"))).anySatisfy(r -> {
            assertThat(r.get("id")).isEqualTo(st.toString());
            assertThat(((Number) r.get("required")).intValue()).isGreaterThanOrEqualTo(0);
        });
    }
}
