package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.List;
import java.util.Map;
import java.util.Random;
import java.util.UUID;

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
 * A BSU- course and its MOAU- twin taught once (V396), on a department and session of the test's own: the pair is suggested
 * from the duplicates rule and linked by a central office (a Head of another department may not); allocating either class
 * allocates both; a slot entered on one class is the slot of both; one register marks both codes' students, each on their
 * own class; unlinked with a reason. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class CourseTwinsIT {

    static final String SESSION = "2188/2189";

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    ItSupport it;
    String academic;
    String dept;
    String other;
    String bsu;
    String moau;
    UUID ob;
    UUID om;

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
        academic = TestTokens.token(it.person("ZZTWINS-ACAD", "ZZTWINSACAD"), List.of("academic"));
        it.session(SESSION, 2188);
        String tag = Long.toString(Math.abs(new Random().nextLong()), 36).toUpperCase().replaceAll("[^A-Z]", "") + "QWERTY";
        dept = "Z" + tag.substring(0, 4);
        other = "Z" + tag.substring(1, 5) + "B";
        String letters = "Z" + tag.substring(0, 2);
        bsu = "BSU-" + letters + " 113";
        moau = "MOAU-" + letters + " 113";
        ob = UUID.randomUUID();
        om = UUID.randomUUID();
        it.db(() -> {
            for (String d : List.of(dept, other)) {
                jdbc.sql("INSERT INTO ref.department (code, name, faculty_code) VALUES (:c, 'TWINS IT ' || :c, 'SC')").param("c", d).update();
            }
            jdbc.sql("""
                    INSERT INTO catalogue.course (code, title, units, semester, level, dept_code, state) VALUES
                      (:b, 'Twins Check Course', 3, 1, 100, :d, 'LIVE'), (:m, 'Twins Check Course', 3, 1, 100, :d, 'LIVE')
                    """).param("b", bsu).param("m", moau).param("d", dept).update();
            jdbc.sql("INSERT INTO catalogue.offering (id, course_code, session, semester) VALUES (:ob, :b, :s, 1), (:om, :m, :s, 1)")
                    .param("ob", ob).param("om", om).param("b", bsu).param("m", moau).param("s", SESSION).update();
            return null;
        });
    }

    UUID student(String surname, int level, UUID offering) {
        int n = new Random().nextInt(900_000) + 100_000;
        UUID s = it.student(surname + n, "C00023", "MOAUM/ADM/88/" + n, null, level);
        it.db(() -> {
            UUID reg = UUID.randomUUID();
            jdbc.sql("INSERT INTO registration.course_registration (id, student_id, session, semester, level, status, approved_at) VALUES (:r, :s, :ses, 1, :l, 'APPROVED', now())")
                    .param("r", reg).param("s", s).param("ses", SESSION).param("l", level).update();
            return jdbc.sql("INSERT INTO registration.entry (registration_id, offering_id, units, status) VALUES (:r, :o, 3, 'APPROVED')").param("r", reg).param("o", offering).update();
        });
        return s;
    }

    Map<String, Object> twins() {
        ResponseEntity<Map> r = it.get(academic, "/api/v1/catalogue/twins?dept=" + dept);
        assertThat(r.getStatusCode().value()).as(String.valueOf(r.getBody())).isEqualTo(200);
        return r.getBody();
    }

    @Test
    void aBsuCourseAndItsMoauTwinAreAllocatedTimetabledAndRegisteredOnce() {
        // suggested from the duplicates rule
        List<Map<String, Object>> suggested = (List<Map<String, Object>>) twins().get("suggested");
        assertThat(suggested).anySatisfy(s -> { assertThat(s.get("bsu_code")).isEqualTo(bsu); assertThat(s.get("moau_code")).isEqualTo(moau); });

        // a Head of another department may not link them; the Academic Office does
        String otherHod = it.officer("hod", "department", other);
        ResponseEntity<Map> notTheirs = it.call(otherHod, HttpMethod.POST, "/api/v1/catalogue/twins", Map.of("bsuCode", bsu, "moauCode", moau));
        assertThat(notTheirs.getStatusCode().value()).isEqualTo(422);
        assertThat(String.valueOf(notTheirs.getBody().get("code"))).startsWith("SCOPE_");
        ResponseEntity<Map> linked = it.call(academic, HttpMethod.POST, "/api/v1/catalogue/twins", Map.of("bsuCode", bsu, "moauCode", moau));
        assertThat(linked.getStatusCode().value()).as(String.valueOf(linked.getBody())).isEqualTo(200);
        String pair = String.valueOf(linked.getBody().get("linkedId"));
        assertThat((List<Map<String, Object>>) linked.getBody().get("linked")).anySatisfy(t -> assertThat(t.get("id")).isEqualTo(pair));
        assertThat((List<Map<String, Object>>) linked.getBody().get("suggested")).noneSatisfy(s -> assertThat(s.get("bsu_code")).isEqualTo(bsu));

        // allocating the MOAU- class allocates the BSU- class too
        UUID lecturer = it.person("ZZTWINS-LEC-" + dept, "ZZTWINSLECTURER");
        ResponseEntity<Map> assigned = it.call(academic, HttpMethod.POST, "/api/v1/allocation/" + om, Map.of("lecturer", lecturer.toString()));
        assertThat(assigned.getStatusCode().value()).as(String.valueOf(assigned.getBody())).isEqualTo(200);
        assertThat(jdbc.sql("SELECT lecturer_id FROM catalogue.offering WHERE id = :o").param("o", ob).query(UUID.class).single()).isEqualTo(lecturer);

        // a slot entered on the BSU- class is on the MOAU- class's desk, and on both students' timetables
        UUID sb = student("ZZTWINSB", 300, ob);
        UUID sm = student("ZZTWINSM", 100, om);
        String hod = it.officer("hod", "department", dept);
        ResponseEntity<List> slot = it.callList(hod, HttpMethod.POST, "/api/v1/registration/offerings/" + ob + "/slots",
                Map.of("weekday", 3, "startsAt", "10:00", "endsAt", "12:00", "venue", "LT 9, Twins", "kind", "LECTURE"));
        assertThat(slot.getStatusCode().value()).as(String.valueOf(slot.getBody())).isEqualTo(200);
        List<Map<String, Object>> moauSlots = it.getList(hod, "/api/v1/registration/offerings/" + om + "/slots").getBody();
        assertThat(moauSlots).singleElement().satisfies(s -> assertThat(s.get("venue")).isEqualTo("LT 9, Twins"));
        assertThat(jdbc.sql("SELECT count(*) FROM registration.student_timetable(:s, :ses, 1)").param("s", sm).param("ses", SESSION).query(Long.class).single()).isEqualTo(1);
        assertThat(jdbc.sql("SELECT count(*) FROM registration.student_timetable(:s, :ses, 1)").param("s", sb).param("ses", SESSION).query(Long.class).single()).isEqualTo(1);

        // V398: the paper's slot the Examinations Office sets on the BSU- class is the slot of both
        String exams = ItSupport.token("exams");
        ResponseEntity<Map> slotSet = it.call(exams, HttpMethod.PUT, "/api/v1/results/offerings/" + ob + "/exam-slot", Map.of("heldOn", "2026-12-10", "startsAt", "09:00", "endsAt", "11:00", "venue", "CBT Hall T"));
        assertThat(slotSet.getStatusCode().value()).as(String.valueOf(slotSet.getBody())).isEqualTo(200);
        assertThat(it.get(hod, "/api/v1/registration/offerings/" + om + "/exam-slot").getBody().get("venue")).isEqualTo("CBT Hall T");

        // the desk names the twin class, and one register marks both codes' students, each on their own class
        assertThat(it.get(hod, "/api/v1/registration/offerings/" + ob + "/twin").getBody().get("course_code")).isEqualTo(moau);
        ResponseEntity<Map> marked = it.call(hod, HttpMethod.POST, "/api/v1/registration/offerings/" + ob + "/attendance",
                Map.of("heldOn", "2026-10-05", "present", List.of(sm.toString())));
        assertThat(marked.getStatusCode().value()).as(String.valueOf(marked.getBody())).isEqualTo(200);
        assertThat(((Number) marked.getBody().get("marked")).intValue()).isEqualTo(2);
        List<Map<String, Object>> onMoau = (List<Map<String, Object>>) it.get(hod, "/api/v1/registration/offerings/" + om + "/attendance").getBody().get("students");
        assertThat(onMoau).anySatisfy(s -> { assertThat(s.get("student_id")).isEqualTo(sm.toString()); assertThat(s.get("course_code")).isEqualTo(moau); assertThat(((Number) s.get("attended")).intValue()).isEqualTo(1); });
        assertThat(onMoau).anySatisfy(s -> { assertThat(s.get("student_id")).isEqualTo(sb.toString()); assertThat(s.get("course_code")).isEqualTo(bsu); assertThat(((Number) s.get("attended")).intValue()).isZero(); });

        // unlinked with a reason: each code is its own class again, keeping what it has
        assertThat(it.call(academic, HttpMethod.POST, "/api/v1/catalogue/twins/" + pair + "/unlink", Map.of("reason", " ")).getStatusCode().value()).isIn(400, 422);
        ResponseEntity<Map> unlinked = it.call(academic, HttpMethod.POST, "/api/v1/catalogue/twins/" + pair + "/unlink", Map.of("reason", "IT: taught apart from now"));
        assertThat(unlinked.getStatusCode().value()).as(String.valueOf(unlinked.getBody())).isEqualTo(200);
        assertThat((List<Map<String, Object>>) unlinked.getBody().get("linked")).isEmpty();
        assertThat(it.get(hod, "/api/v1/registration/offerings/" + ob + "/twin").getBody()).isEmpty();
        assertThat(jdbc.sql("SELECT lecturer_id FROM catalogue.offering WHERE id = :o").param("o", ob).query(UUID.class).single()).isEqualTo(lecturer);
    }

    @Test
    void aCentralOfficeSeesEveryDepartmentsTwinsAndLinksThemInBulk() {
        // the Head of a department reads their own department's; the whole University's list is a central office's
        String hod = it.officer("hod", "department", dept);
        assertThat(it.get(hod, "/api/v1/catalogue/twins/all").getStatusCode().value()).isEqualTo(403);
        ResponseEntity<Map> all = it.get(academic, "/api/v1/catalogue/twins/all");
        assertThat(all.getStatusCode().value()).as(String.valueOf(all.getBody())).isEqualTo(200);
        assertThat(all.getBody().get("session")).isNotNull(); // the University's current session, whichever the suite has left current
        assertThat((List<Map<String, Object>>) all.getBody().get("suggested"))
                .anySatisfy(s -> { assertThat(s.get("dept")).isEqualTo(dept); assertThat(s.get("bsu_code")).isEqualTo(bsu); assertThat(s.get("moau_code")).isEqualTo(moau); });

        // linked in bulk: the pair once; the same pair again in the one act is refused by its code, and the rest stand linked
        ResponseEntity<Map> bulk = it.call(academic, HttpMethod.POST, "/api/v1/catalogue/twins/link-all", Map.of("pairs", List.of(
                Map.of("bsuCode", bsu, "moauCode", moau), Map.of("bsuCode", bsu, "moauCode", moau))));
        assertThat(bulk.getStatusCode().value()).as(String.valueOf(bulk.getBody())).isEqualTo(200);
        assertThat(((Number) bulk.getBody().get("linkedNow")).intValue()).isEqualTo(1);
        assertThat((List<Map<String, Object>>) bulk.getBody().get("refused"))
                .singleElement().satisfies(r -> { assertThat(r.get("bsuCode")).isEqualTo(bsu); assertThat(String.valueOf(r.get("code"))).startsWith("COURSE_TWIN_"); });
        List<Map<String, Object>> linked = (List<Map<String, Object>>) bulk.getBody().get("linked");
        assertThat(linked).anySatisfy(t -> { assertThat(t.get("dept")).isEqualTo(dept); assertThat(t.get("bsu_code")).isEqualTo(bsu); });
        // the allocation is read off a session's classes — this test's session, whatever the suite has left current
        List<Map<String, Object>> inSession = (List<Map<String, Object>>) it.get(academic, "/api/v1/catalogue/twins/all?session=" + SESSION).getBody().get("linked");
        assertThat(inSession).anySatisfy(t -> { assertThat(t.get("bsu_code")).isEqualTo(bsu); assertThat(t.get("allocation")).isEqualTo("UNALLOCATED"); });
        assertThat((List<Map<String, Object>>) bulk.getBody().get("suggested")).noneSatisfy(s -> assertThat(s.get("bsu_code")).isEqualTo(bsu));

        // once allocated (the twin's class with it), the list says the pair is taught together and by whom
        UUID lecturer = it.person("ZZTWINS-LEC-" + dept, "ZZTWINSLECTURER");
        assertThat(it.call(academic, HttpMethod.POST, "/api/v1/allocation/" + ob, Map.of("lecturer", lecturer.toString())).getStatusCode().value()).isEqualTo(200);
        List<Map<String, Object>> again = (List<Map<String, Object>>) it.get(academic, "/api/v1/catalogue/twins/all?session=" + SESSION).getBody().get("linked");
        assertThat(again).anySatisfy(t -> { assertThat(t.get("bsu_code")).isEqualTo(bsu); assertThat(t.get("allocation")).isEqualTo("TOGETHER"); assertThat(String.valueOf(t.get("lecturer"))).contains("ZZTWINSLECTURER"); });

        // the Head of the department links nothing in bulk
        assertThat(it.call(hod, HttpMethod.POST, "/api/v1/catalogue/twins/link-all", Map.of("pairs", List.of(Map.of("bsuCode", bsu, "moauCode", moau)))).getStatusCode().value()).isEqualTo(403);
    }
}
