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
    String letters;
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
        // four letters of the run's own: two collided on CI once in four set-ups of one run
        letters = "Z" + tag.substring(0, 4);
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

    /** a lecturer of the department: the allocation desks give a class only to a person who holds a lecturer office (V408) */
    private UUID teacher(String dept) {
        UUID id = it.person("ZZTWINS-LEC-" + dept, "ZZTWINSLECTURER");
        it.db(() -> jdbc.sql("""
                INSERT INTO iam.office_assignment (id, person_id, office_code, scope_kind, scope_id, instrument, granted_by, valid_from)
                SELECT gen_random_uuid(), :p, 'lecturer', 'department', :d, 'integration test', :p, current_date
                 WHERE NOT EXISTS (SELECT 1 FROM iam.office_assignment a WHERE a.person_id = :p AND a.office_code = 'lecturer' AND a.scope_id = :d
                                     AND (a.valid_to IS NULL OR a.valid_to >= current_date))
                """).param("p", id).param("d", dept).update());
        return id;
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
        UUID lecturer = teacher(dept);
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
        UUID lecturer = teacher(dept);
        assertThat(it.call(academic, HttpMethod.POST, "/api/v1/allocation/" + ob, Map.of("lecturer", lecturer.toString())).getStatusCode().value()).isEqualTo(200);
        List<Map<String, Object>> again = (List<Map<String, Object>>) it.get(academic, "/api/v1/catalogue/twins/all?session=" + SESSION).getBody().get("linked");
        assertThat(again).anySatisfy(t -> { assertThat(t.get("bsu_code")).isEqualTo(bsu); assertThat(t.get("allocation")).isEqualTo("TOGETHER"); assertThat(String.valueOf(t.get("lecturer"))).contains("ZZTWINSLECTURER"); });

        // the Head of the department links nothing in bulk
        assertThat(it.call(hod, HttpMethod.POST, "/api/v1/catalogue/twins/link-all", Map.of("pairs", List.of(Map.of("bsuCode", bsu, "moauCode", moau)))).getStatusCode().value()).isEqualTo(403);
    }

    /** V402: both codes are offered and a student is shown their cohort's — MOAU- from the stated entry session, BSU- before it */
    @Test
    void aStudentIsOfferedTheirCohortsCode() {
        it.db(() -> jdbc.sql("INSERT INTO catalogue.course_offer (course_code, programme_code, level, basis) VALUES (:b, 'C00023', 100, 'Core'), (:m, 'C00023', 100, 'Core') ON CONFLICT DO NOTHING")
                .param("b", bsu).param("m", moau).update());
        String before = jdbc.sql("SELECT moau_from_entry_session FROM catalogue.code_family_setting WHERE id = 1").query(String.class).optional().orElse(null);
        try {
            ResponseEntity<Map> set = it.call(academic, HttpMethod.PUT, "/api/v1/catalogue/code-families", Map.of("moauFromEntrySession", SESSION));
            assertThat(set.getStatusCode().value()).as(String.valueOf(set.getBody())).isEqualTo(200);
            assertThat(set.getBody().get("moau_from_entry_session")).isEqualTo(SESSION);
            assertThat(((Number) set.getBody().get("pairs")).intValue()).isGreaterThanOrEqualTo(1);
            UUID newer = cohortStudent("ZZCOHORTM", SESSION);
            UUID older = cohortStudent("ZZCOHORTB", "2000/2001");
            assertThat(menu(newer)).contains(moau).doesNotContain(bsu);
            assertThat(menu(older)).contains(bsu).doesNotContain(moau);
            // unstated, both codes reach both
            ResponseEntity<Map> cleared = it.call(academic, HttpMethod.PUT, "/api/v1/catalogue/code-families", java.util.Collections.singletonMap("moauFromEntrySession", null));
            assertThat(cleared.getStatusCode().value()).as(String.valueOf(cleared.getBody())).isEqualTo(200);
            assertThat(menu(older)).contains(bsu, moau);
            // a Head of Department does not state the University's rule
            assertThat(it.call(it.officer("hod", "department", dept), HttpMethod.PUT, "/api/v1/catalogue/code-families", Map.of("moauFromEntrySession", SESSION)).getStatusCode().value()).isEqualTo(403);
        } finally {
            it.call(academic, HttpMethod.PUT, "/api/v1/catalogue/code-families", java.util.Collections.singletonMap("moauFromEntrySession", before));
        }
    }

    /** a 100-level student of the programme admitted in the entry session given */
    private UUID cohortStudent(String surname, String entry) {
        int n = new Random().nextInt(900_000) + 100_000;
        UUID s = UUID.randomUUID();
        it.db(() -> jdbc.sql("""
                INSERT INTO people.student (id, admission_no, matric_no, surname, other_names, programme_code, entry_mode, entry_session, entry_level, current_level, status, matriculated_at)
                VALUES (:id, :adm, :mat, :s, 'Invented', 'C00023', 'UTME', :e, 100, 100, 'ACTIVE', now())
                """).param("id", s).param("adm", "MOAUM/ADM/88/" + n).param("mat", "MOAUM/MTC/88/" + (1000 + n % 9000)).param("s", surname + n).param("e", entry).update());
        return s;
    }

    private List<String> menu(UUID student) {
        return jdbc.sql("SELECT course_code FROM registration.student_menu(:s, :ses, 1)").param("s", student).param("ses", SESSION).query(String.class).list();
    }

    /** V405/V406: a course that joins the structure after the semester's classes were opened has no class until the desk opens it;
     *  the desk lists it (and a course in no structure, as such) and opens what is owed */
    @Test
    void aCourseAddedToTheStructureLaterGetsItsClass() {
        String later = "MOAU-" + letters + " 114";   // the twins' letters, a code of its own
        String lone = "BSU-" + letters + " 115";
        it.db(() -> {
            jdbc.sql("INSERT INTO catalogue.course (code, title, units, semester, level, dept_code, state) VALUES (:a, 'Course added later', 2, 1, 100, :d, 'LIVE'), (:b, 'Course in no structure', 2, 1, 100, :d, 'LIVE')")
                    .param("a", later).param("b", lone).param("d", dept).update();
            return jdbc.sql("INSERT INTO catalogue.course_offer (course_code, programme_code, level, basis) VALUES (:a, 'C00023', 100, 'Core')").param("a", later).update();
        });
        // nothing opens unasked: the desk lists the course as in the structure with no class, and the lone one as in no structure
        String hod = it.officer("hod", "department", dept);
        List<Map<String, Object>> missing = it.getList(hod, "/api/v1/allocation/without-class?dept=" + dept + "&session=" + SESSION).getBody();
        assertThat(missing).anySatisfy(r -> { assertThat(r.get("code")).isEqualTo(later); assertThat(r.get("reason")).isEqualTo("NO_CLASS"); });
        assertThat(missing).anySatisfy(r -> { assertThat(r.get("code")).isEqualTo(lone); assertThat(r.get("reason")).isEqualTo("NOT_IN_STRUCTURE"); });
        // the desk opens what is owed in the session's opened semesters (the first has classes: the twins'); the lone course stays listed
        ResponseEntity<Map> opened = it.call(hod, HttpMethod.POST, "/api/v1/allocation/open-classes?session=" + SESSION, Map.of());
        assertThat(opened.getStatusCode().value()).as(String.valueOf(opened.getBody())).isEqualTo(200);
        assertThat((List<Integer>) opened.getBody().get("semesters")).contains(1);
        assertThat(jdbc.sql("SELECT count(*) FROM catalogue.offering WHERE course_code = :c AND session = :s AND semester = 1 AND stream = 'REGULAR'")
                .param("c", later).param("s", SESSION).query(Long.class).single()).isEqualTo(1L);
        List<Map<String, Object>> after = it.getList(hod, "/api/v1/allocation/without-class?dept=" + dept + "&session=" + SESSION).getBody();
        assertThat(after).noneSatisfy(r -> assertThat(r.get("code")).isEqualTo(later));
        assertThat(after).anySatisfy(r -> assertThat(r.get("code")).isEqualTo(lone));
    }
}
