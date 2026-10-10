package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.time.LocalDate;
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
 * CCE examinations, progression and matriculation (V381), through the API: ICT sets a CCE examination session beside the
 * full-time one of the same session, semester and kind, and each releases score sheets to its own stream's classes only; the
 * Centre's desk reads its exam sessions and where each CCE sheet stands; the broadsheet and Senate read one stream at a time;
 * the CCE student's examination card lists the Centre's papers, and attendance bars a paper only when the Centre's policy
 * says so and against a minimum; the progression page reads the one academic position; the Registry sets the CCE series and
 * segment with a reason (the Centre cannot); a department's timetable and register are its own classes'. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class CceExamsIT {

    static final String SESSION = "2121/2122";
    static final String PROGRAMME = "C00023";

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    ItSupport it;
    final String academic = ItSupport.token("academic");
    final String registrar = ItSupport.token("registrar");
    final String centre = ItSupport.token("cce");
    final String ict = ItSupport.token("ict");
    Map<String, Object> route;

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
        it.session(SESSION, 2121);
        route = jdbc.sql("SELECT matric_series, matric_segment FROM policy.study_route WHERE code = 'CCE'").query().singleRow();
    }

    @AfterEach
    void tearDown() {
        it.call(academic, HttpMethod.PUT, "/api/v1/cce/session-mapping", Map.of("offset", -1, "reason", "integration test: back to one session behind"));
        // the CCE route's series and segment as they were: another test numbers CCE students
        Map<String, Object> back = new HashMap<>();
        back.put("matricSeries", route.get("matric_series"));
        back.put("matricSegment", route.get("matric_segment"));
        back.put("reason", "integration test: restored");
        it.call(registrar, HttpMethod.PUT, "/api/v1/matriculation/config/routes/CCE", back);
        it.db(() -> jdbc.sql("DELETE FROM attendance.policy WHERE context = 'CCE' AND session = :s").param("s", SESSION).update());
    }

    private Map<String, Object> ok(ResponseEntity<Map> r) {
        assertThat(r.getStatusCode().value()).as(String.valueOf(r.getBody())).isEqualTo(200);
        return r.getBody();
    }

    private static String code(ResponseEntity<Map> r) {
        return r.getBody() == null ? null : String.valueOf(r.getBody().get("code"));
    }

    /** the examination session of the stream, made once (a rerun finds it) and opened */
    private String examSession(String stream) {
        List<Map<String, Object>> all = it.callList(ict, HttpMethod.GET, "/api/v1/results/exam-sessions?session=" + SESSION, null).getBody();
        String id = all.stream().filter(e -> stream.equals(e.get("stream")) && Integer.valueOf(1).equals(e.get("semester")) && "MAIN".equals(e.get("kind")))
                .map(e -> String.valueOf(e.get("id"))).findFirst().orElse(null);
        if (id == null) {
            Map<String, Object> made = ok(it.call(ict, HttpMethod.POST, "/api/v1/results/exam-sessions", Map.of("session", SESSION, "semester", 1, "kind", "MAIN",
                    "examsFrom", "2122-02-01", "examsTo", "2122-02-20", "sheetsDue", "2122-03-10", "stream", stream)));
            assertThat(made.get("stream")).isEqualTo(stream);
            id = String.valueOf(made.get("id"));
            ok(it.call(ict, HttpMethod.POST, "/api/v1/results/exam-sessions/" + id + "/open", null));
            ok(it.call(ict, HttpMethod.POST, "/api/v1/results/exam-sessions/" + id + "/release-sheets", null));
            ok(it.call(ict, HttpMethod.POST, "/api/v1/results/exam-sessions/" + id + "/release-cards", null));
        }
        return id;
    }

    @Test
    void theCentresExaminationsRunOnTheOneChainItsStudentsProgressOnTheirOwnLengthAndTheRegistryNumbersThem() {
        String n = String.format("%06d", Math.abs(UUID.randomUUID().getMostSignificantBits() % 1_000_000L));
        // (0) the CCE session, the programme on the route, one course with a full-time class and a CCE class, a CCE student
        ok(it.call(academic, HttpMethod.PUT, "/api/v1/cce/session-mapping", Map.of("offset", -1, "override", SESSION, "reason", "integration test: the CCE session " + SESSION)));
        ok(it.call(academic, HttpMethod.PUT, "/api/v1/cce/programmes/" + PROGRAMME, Map.of("active", true)));
        UUID cceStudent = UUID.randomUUID();
        UUID lecturerId = it.person("ZZ-LECTURER-MTC", "ZZLECTURERMTC");
        String dept = it.db(() -> jdbc.sql("SELECT dept_code FROM ref.programme WHERE code = :p").param("p", PROGRAMME).query(String.class).single());
        UUID ftClass = it.db(() -> {
            jdbc.sql("""
                    INSERT INTO catalogue.course (code, title, units, semester, level, dept_code, kind, state)
                    SELECT 'CCX 101', 'Evening examinations', 3, 1, 100, p.dept_code, 'Core', 'LIVE' FROM ref.programme p WHERE p.code = :p ON CONFLICT (code) DO NOTHING
                    """).param("p", PROGRAMME).update();
            jdbc.sql("INSERT INTO catalogue.course_offer (course_code, programme_code, level, basis) VALUES ('CCX 101', :p, 100, 'Core') ON CONFLICT DO NOTHING")
                    .param("p", PROGRAMME).update();
            jdbc.sql("""
                    INSERT INTO people.student (id, admission_no, matric_no, surname, other_names, programme_code, entry_mode, study_mode, entry_session, entry_level, current_level, status, matriculated_at)
                    VALUES (:c, :ca, :cm, 'ZZEXAMEVENING', 'Invented', :p, 'CCE', 'PART_TIME', :s, 100, 100, 'ACTIVE', now())
                    """).param("c", cceStudent).param("ca", "MOAUM/ADM/21/" + n).param("cm", "MOAUM/CCE/21/" + n).param("p", PROGRAMME).param("s", SESSION).update();
            return jdbc.sql("""
                    INSERT INTO catalogue.offering (id, course_code, session, semester, lecturer_id) VALUES (gen_random_uuid(), 'CCX 101', :s, 1, :l)
                    ON CONFLICT (course_code, session, semester, stream) DO UPDATE SET lecturer_id = EXCLUDED.lecturer_id RETURNING id
                    """).param("s", SESSION).param("l", lecturerId).query(UUID.class).single();
        });
        String student = TestTokens.token(cceStudent, List.of("student"));
        String today = LocalDate.now().toString();
        ok(it.call(centre, HttpMethod.PUT, "/api/v1/cce/calendar/" + SESSION + "/1", Map.of("state", "OPEN",
                "registrationOpens", LocalDate.now().minusDays(1).toString(), "registrationCloses", LocalDate.now().plusDays(30).toString(), "lecturesFrom", today,
                "reason", "integration test: the semester opened")));
        Map<String, Object> opened = ok(it.call(centre, HttpMethod.POST, "/api/v1/cce/classes/open", Map.of("session", SESSION, "semester", 1)));
        String cceClass = ((List<Map<String, Object>>) opened.get("classes")).stream().filter(c -> "CCX 101".equals(c.get("course_code")))
                .map(c -> String.valueOf(c.get("id"))).findFirst().orElseThrow();
        ok(it.call(centre, HttpMethod.PUT, "/api/v1/cce/classes/" + cceClass + "/teaching", Map.of("lecturerId", lecturerId.toString())));
        ok(it.call(student, HttpMethod.PUT, "/api/v1/me/registration", Map.of("session", SESSION, "semester", 1, "offerings", List.of(cceClass))));
        it.db(() -> jdbc.sql("UPDATE registration.course_registration SET status = 'APPROVED', submitted_at = coalesce(submitted_at, now()), approved_at = now() WHERE student_id = :s AND session = :ses AND semester = 1")
                .param("s", cceStudent).param("ses", SESSION).update());

        // (1) a department reaches its own classes only: the Head of another department, and a lecturer not teaching it, are refused
        String ownHod = it.officer("hod", "department", dept);
        String otherDept = it.db(() -> jdbc.sql("SELECT code FROM ref.department WHERE code <> :d ORDER BY code LIMIT 1").param("d", dept).query(String.class).single());
        String otherHod = it.officer("hod", "department", otherDept);
        String stranger = it.officer("lecturer", "department", otherDept);
        assertThat(it.callList(ownHod, HttpMethod.GET, "/api/v1/registration/offerings/" + ftClass + "/slots", null).getStatusCode().value()).isEqualTo(200);
        assertThat(code(it.call(otherHod, HttpMethod.GET, "/api/v1/registration/offerings/" + ftClass + "/slots", null))).startsWith("SCOPE_");
        assertThat(code(it.call(otherHod, HttpMethod.POST, "/api/v1/registration/offerings/" + ftClass + "/slots",
                Map.of("weekday", 4, "startsAt", "08:00", "endsAt", "10:00", "venue", "Not theirs")))).startsWith("SCOPE_");
        assertThat(it.get(stranger, "/api/v1/registration/offerings/" + ftClass + "/attendance").getStatusCode().value()).isEqualTo(403);

        // (2) the examination sessions: one per stream; each releases its own stream's sheets
        String regular = examSession("REGULAR");
        String cce = examSession("CCE");
        assertThat(regular).isNotEqualTo(cce);
        Map<String, Object> exams = ok(it.get(centre, "/api/v1/cce/exams?session=" + SESSION));
        assertThat(((List<Map<String, Object>>) exams.get("examSessions")).stream().map(e -> String.valueOf(e.get("id")))).containsExactly(cce);
        List<Map<String, Object>> sheets = (List<Map<String, Object>>) exams.get("sheets");
        Map<String, Object> sheet = sheets.stream().filter(s -> cceClass.equals(String.valueOf(s.get("offering_id")))).findFirst().orElseThrow();
        assertThat(sheet.get("stage")).isEqualTo("ENTRY");
        assertThat(sheets.stream().map(s -> String.valueOf(s.get("offering_id")))).doesNotContain(ftClass.toString());
        String ftSheetSession = it.db(() -> jdbc.sql("SELECT exam_session_id::text FROM assessment.score_sheet WHERE offering_id = :o").param("o", ftClass).query(String.class).single());
        assertThat(ftSheetSession).isEqualTo(regular);
        assertThat(it.get(ownHod, "/api/v1/cce/exams").getStatusCode().value()).isEqualTo(403);

        // (3) the broadsheet and the Senate read one stream at a time
        assertThat(it.get(registrar, "/api/v1/results/broadsheet?prog=" + PROGRAMME + "&level=100&session=" + SESSION + "&sem=1&stream=CCE").getStatusCode().value()).isEqualTo(200);
        assertThat(it.get(registrar, "/api/v1/results/senate?session=" + SESSION + "&sem=1&stream=CCE").getStatusCode().value()).isEqualTo(200);
        assertThat(it.get(registrar, "/api/v1/results/senate?session=" + SESSION + "&sem=1&stream=EVENING").getStatusCode().value()).isEqualTo(400);

        // (4) the card: the CCE paper; attendance bars nobody until the Centre says so, and then only against a minimum
        Map<String, Object> card = ok(it.get(student, "/api/v1/me/docket"));
        assertThat(card.get("session")).isEqualTo(SESSION);
        List<Map<String, Object>> cardSessions = (List<Map<String, Object>>) card.get("examSessions");
        assertThat(cardSessions.stream().map(e -> String.valueOf(e.get("id")))).containsExactly(cce);
        Map<String, Object> paper = ((List<Map<String, Object>>) cardSessions.get(0).get("papers")).get(0);
        assertThat(paper.get("course_code")).isEqualTo("CCX 101");
        assertThat(paper.get("bar")).isNull();
        Map<String, Object> noMinimum = new HashMap<>(Map.of("session", SESSION, "minClasses", 1, "showStudents", true, "barsExams", true));
        assertThat(code(it.call(centre, HttpMethod.PUT, "/api/v1/cce/attendance/policy", noMinimum))).isEqualTo("CCE_ATTENDANCE_BAR");
        Map<String, Object> policy = ok(it.call(centre, HttpMethod.PUT, "/api/v1/cce/attendance/policy",
                Map.of("session", SESSION, "minPercent", 75, "warnBand", 10, "minClasses", 1, "showStudents", true, "barsExams", true)));
        assertThat(((Map) policy.get("policy")).get("bars_exams")).isEqualTo(true);
        String lecturer = it.officer("lecturer", "department", "MTC");
        Map<String, Object> reg = ok(it.call(lecturer, HttpMethod.POST, "/api/v1/cce/teaching/classes/" + cceClass + "/registers", Map.of("heldOn", today, "topic", "Revision")));
        ok(it.call(lecturer, HttpMethod.PUT, "/api/v1/cce/teaching/registers/" + reg.get("id") + "/marks",
                Map.of("marks", List.of(Map.of("student", cceStudent.toString(), "status", "ABSENT")))));
        Map<String, Object> barred = ((List<Map<String, Object>>) ((List<Map<String, Object>>) ok(it.get(student, "/api/v1/me/docket")).get("examSessions")).get(0).get("papers")).get(0);
        assertThat(String.valueOf(barred.get("bar"))).startsWith("CBT_ATTENDANCE");
        ok(it.call(centre, HttpMethod.PUT, "/api/v1/cce/attendance/policy",
                Map.of("session", SESSION, "minPercent", 75, "warnBand", 10, "minClasses", 1, "showStudents", true, "barsExams", false)));
        Map<String, Object> cleared = ((List<Map<String, Object>>) ((List<Map<String, Object>>) ok(it.get(student, "/api/v1/me/docket")).get("examSessions")).get(0).get("papers")).get(0);
        assertThat(cleared.get("bar")).isNull();

        // (5) progression: the CCE student in the CCE session, on the CCE programme length
        Map<String, Object> progression = ok(it.get(centre, "/api/v1/cce/progression?q=" + n));
        Map<String, Object> row = ((List<Map<String, Object>>) progression.get("rows")).stream().filter(r -> cceStudent.toString().equals(String.valueOf(r.get("id")))).findFirst().orElseThrow();
        assertThat(row.get("current_session")).isEqualTo(SESSION);
        assertThat(row.get("spillover_state")).isEqualTo("NORMAL");
        assertThat(row.get("expected_completion")).isNotNull();
        assertThat(((Map) progression.get("counts")).get("students")).isNotNull();

        // (6) the CCE series and segment: the Registry's, with a reason; an inactive series refused; the Centre cannot
        ok(it.call(registrar, HttpMethod.PUT, "/api/v1/matriculation/config/series/CCEIT", Map.of("name", "CCE integration test", "active", true)));
        assertThat(it.call(centre, HttpMethod.PUT, "/api/v1/matriculation/config/routes/CCE", Map.of("matricSeries", "CCEIT", "reason", "x")).getStatusCode().value()).isEqualTo(403);
        assertThat(it.call(registrar, HttpMethod.PUT, "/api/v1/matriculation/config/routes/CCE", Map.of("matricSeries", "CCEIT")).getStatusCode().value()).isEqualTo(400);
        assertThat(code(it.call(registrar, HttpMethod.PUT, "/api/v1/matriculation/config/routes/CCE", Map.of("matricSeries", "NOSUCH" + n, "reason", "a series that is not there")))).isEqualTo("CCE_MATRIC_SERIES");
        Map<String, Object> set = ok(it.call(registrar, HttpMethod.PUT, "/api/v1/matriculation/config/routes/CCE",
                Map.of("matricSeries", "CCEIT", "matricSegment", "cce", "reason", "integration test: the Centre's own run")));
        assertThat(set.get("matric_series")).isEqualTo("CCEIT");
        assertThat(set.get("matric_segment")).isEqualTo("CCE");
        Map<String, Object> config = ok(it.get(academic, "/api/v1/matriculation/config"));
        Map<String, Object> cceRoute = ((List<Map<String, Object>>) config.get("routes")).stream().filter(r -> "CCE".equals(r.get("code"))).findFirst().orElseThrow();
        assertThat(cceRoute.get("matric_series")).isEqualTo("CCEIT");
        assertThat(String.valueOf(cceRoute.get("last_change"))).contains("the Centre's own run");
    }
}
