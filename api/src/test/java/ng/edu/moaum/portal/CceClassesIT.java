package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.time.LocalDate;
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
 * CCE phase 2 (V380), through the API: the Centre sets the CCE calendar and opens its classes in the CCE session beside the
 * full-time class of the same course; it allocates the lecturer and puts the class on the evening timetable (a department
 * cannot, and a venue is not taken twice); the CCE student's registration screen is the CCE session's, its menu the Centre's
 * classes only, and the CCE window closes it where the full-time window does not; the lecturer keeps the register (late, a
 * correction with its reason, locked; another lecturer is refused); the Centre reopens a locked register; the student reads
 * the attendance; the CCE school fees are the lines the Bursary states for CCE. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class CceClassesIT {

    static final String SESSION = "2117/2118";
    static final String PROGRAMME = "C00023";

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    ItSupport it;
    final String academic = ItSupport.token("academic");
    final String centre = ItSupport.token("cce");
    final String bursar = ItSupport.token("bursar");
    final String ict = ItSupport.token("ict");

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
        it.session(SESSION, 2117);
    }

    @AfterEach
    void tearDown() {
        it.call(academic, HttpMethod.PUT, "/api/v1/cce/session-mapping", Map.of("offset", -1, "reason", "integration test: back to one session behind"));
        // the fee lines of the test's far-future session go: another test reads "the latest session charged"
        it.db(() -> jdbc.sql("DELETE FROM finance.fee_schedule WHERE session = :s").param("s", SESSION).update());
    }

    private Map<String, Object> ok(ResponseEntity<Map> r) {
        assertThat(r.getStatusCode().value()).as(String.valueOf(r.getBody())).isEqualTo(200);
        return r.getBody();
    }

    private static String code(ResponseEntity<Map> r) {
        return r.getBody() == null ? null : String.valueOf(r.getBody().get("code"));
    }

    private static Map<String, Object> classOf(Map<String, Object> page, String course) {
        return ((List<Map<String, Object>>) page.get("classes")).stream().filter(c -> course.equals(c.get("course_code"))).findFirst().orElseThrow();
    }

    @Test
    void theCentresClassesRunInTheCceSessionAndItsStudentsRegisterAttendAndPayOnTheirOwn() {
        String n = String.format("%06d", Math.abs(UUID.randomUUID().getMostSignificantBits() % 1_000_000L));
        // (0) the session, the programme on the route, two first-semester courses offered to it, the full-time class of one, and two students
        ok(it.call(academic, HttpMethod.PUT, "/api/v1/cce/session-mapping", Map.of("offset", -1, "override", SESSION, "reason", "integration test: the CCE session " + SESSION)));
        ok(it.call(academic, HttpMethod.PUT, "/api/v1/cce/programmes/" + PROGRAMME, Map.of("active", true)));
        UUID cceStudent = UUID.randomUUID();
        UUID ftStudent = UUID.randomUUID();
        UUID ftClass = it.db(() -> {
            jdbc.sql("""
                    INSERT INTO catalogue.course (code, title, units, semester, level, dept_code, kind, state)
                    SELECT x.code, x.title, 3, 1, 100, p.dept_code, 'Core', 'LIVE' FROM ref.programme p, (VALUES ('CCY 101', 'Evening one'), ('CCY 102', 'Evening two')) x(code, title)
                     WHERE p.code = :p ON CONFLICT (code) DO NOTHING
                    """).param("p", PROGRAMME).update();
            jdbc.sql("INSERT INTO catalogue.course_offer (course_code, programme_code, level, basis) VALUES ('CCY 101', :p, 100, 'Core'), ('CCY 102', :p, 100, 'Core') ON CONFLICT DO NOTHING")
                    .param("p", PROGRAMME).update();
            jdbc.sql("""
                    INSERT INTO people.student (id, admission_no, matric_no, surname, other_names, programme_code, entry_mode, study_mode, entry_session, entry_level, current_level, status, matriculated_at)
                    VALUES (:c, :ca, :cm, 'ZZEVENING', 'Invented', :p, 'CCE', 'PART_TIME', :s, 100, 100, 'ACTIVE', now()),
                           (:f, :fa, :fm, 'ZZDAYTIME', 'Invented', :p, 'UTME', 'FULL_TIME', :s, 100, 100, 'ACTIVE', now())
                    """).param("c", cceStudent).param("ca", "MOAUM/ADM/17/" + n).param("cm", "MOAUM/CCE/17/" + n)
                    .param("f", ftStudent).param("fa", "MOAUM/ADM/18/" + n).param("fm", "MOAUM/FT/17/" + n).param("p", PROGRAMME).param("s", SESSION).update();
            return jdbc.sql("""
                    INSERT INTO catalogue.offering (id, course_code, session, semester) VALUES (gen_random_uuid(), 'CCY 101', :s, 1)
                    ON CONFLICT (course_code, session, semester, stream) DO UPDATE SET semester = EXCLUDED.semester RETURNING id
                    """).param("s", SESSION).query(UUID.class).single();
        });
        String lecturer = it.officer("lecturer", "department", "MTC");
        UUID lecturerId = it.person("ZZ-LECTURER-MTC", "ZZLECTURERMTC");
        String otherLecturer = it.officer("lecturer", "department", "CHM");
        String hod = it.officer("hod", "department", "MTC");
        String student = TestTokens.token(cceStudent, List.of("student"));
        String fullTime = TestTokens.token(ftStudent, List.of("student"));

        // (1) the CCE calendar: the Centre's; a lecturer reads nothing of the desk
        assertThat(it.get(lecturer, "/api/v1/cce/classes").getStatusCode().value()).isEqualTo(403);
        String today = LocalDate.now().toString();
        Map<String, Object> cal = ok(it.call(centre, HttpMethod.PUT, "/api/v1/cce/calendar/" + SESSION + "/1", Map.of("state", "OPEN",
                "registrationOpens", LocalDate.now().minusDays(1).toString(), "registrationCloses", LocalDate.now().plusDays(30).toString(), "lecturesFrom", today,
                "reason", "integration test: the semester opened for registration")));
        assertThat(((List<Map>) cal.get("semesters")).get(0).get("state")).isEqualTo("OPEN");

        // (2) the classes: opened in the CCE session beside the full-time class; the Centre allocates the lecturer
        Map<String, Object> opened = ok(it.call(centre, HttpMethod.POST, "/api/v1/cce/classes/open", Map.of("session", SESSION, "semester", 1)));
        Map<String, Object> c101 = classOf(opened, "CCY 101");
        Map<String, Object> c102 = classOf(opened, "CCY 102");
        assertThat(c101.get("id")).isNotEqualTo(ftClass.toString());
        ok(it.call(centre, HttpMethod.PUT, "/api/v1/cce/classes/" + c101.get("id") + "/teaching", Map.of("lecturerId", lecturerId.toString())));
        assertThat(code(it.call(centre, HttpMethod.PUT, "/api/v1/cce/classes/" + ftClass + "/teaching", Map.of("lecturerId", lecturerId.toString())))).isEqualTo("CCE_CLASS_NOT_CCE");

        // (3) the evening timetable: the Centre's; a department cannot set it; a venue is not taken twice
        assertThat(it.call(hod, HttpMethod.POST, "/api/v1/registration/offerings/" + c101.get("id") + "/slots",
                Map.of("weekday", 2, "startsAt", "16:00", "endsAt", "18:00", "venue", "CCE Hall")).getStatusCode().value()).isEqualTo(422);
        Map<String, Object> tt = ok(it.call(centre, HttpMethod.POST, "/api/v1/cce/classes/" + c101.get("id") + "/slots",
                Map.of("weekday", 2, "startsAt", "16:00", "endsAt", "18:00", "venue", "CCE Hall " + n)));
        assertThat(((List<Map<String, Object>>) tt.get("slots")).stream().map(s -> s.get("venue"))).contains("CCE Hall " + n);
        assertThat(code(it.call(centre, HttpMethod.POST, "/api/v1/cce/classes/" + c102.get("id") + "/slots",
                Map.of("weekday", 2, "startsAt", "17:00", "endsAt", "19:00", "venue", "cce hall " + n)))).isEqualTo("CCE_SLOT_VENUE_CLASH");
        String slotId = ((List<Map<String, Object>>) tt.get("slots")).stream().filter(s -> ("CCE Hall " + n).equals(s.get("venue"))).map(s -> String.valueOf(s.get("id"))).findFirst().orElseThrow();

        // (4) the CCE student registers in the CCE session on the Centre's classes only; the full-time student sees the full-time class
        Map<String, Object> view = ok(it.get(student, "/api/v1/me/registration?semester=1"));
        assertThat(view.get("session")).isEqualTo(SESSION);
        assertThat(((Map) view.get("window")).get("gate")).isNull();
        assertThat(((Map) view.get("window")).get("cce")).isEqualTo(true);
        List<String> menu = ((List<Map<String, Object>>) view.get("menu")).stream().map(m -> String.valueOf(m.get("offering_id"))).toList();
        assertThat(menu).contains(String.valueOf(c101.get("id")), String.valueOf(c102.get("id"))).doesNotContain(ftClass.toString());
        Map<String, Object> ftView = ok(it.get(fullTime, "/api/v1/me/registration?session=" + SESSION + "&semester=1"));
        assertThat(((List<Map<String, Object>>) ftView.get("menu")).stream().map(m -> String.valueOf(m.get("offering_id"))).toList())
                .contains(ftClass.toString()).doesNotContain(String.valueOf(c101.get("id")));
        Map<String, Object> chosen = ok(it.call(student, HttpMethod.PUT, "/api/v1/me/registration",
                Map.of("session", SESSION, "semester", 1, "offerings", List.of(c101.get("id"), c102.get("id"), ftClass.toString()))));
        assertThat((List) ((Map) chosen.get("registration")).get("entries")).hasSize(2);
        // the CCE window closes the Centre's registration; the full-time window of the same session does not reach it
        it.db(() -> jdbc.sql("SELECT policy.window_act('COURSE_REGISTRATION', :s, 1, 'CLOSE', NULL, NULL, NULL, NULL, 'full-time semester over', gen_random_uuid(), 'ict')")
                .param("s", SESSION).query().listOfRows());
        ok(it.call(student, HttpMethod.PUT, "/api/v1/me/registration", Map.of("session", SESSION, "semester", 1, "offerings", List.of(c101.get("id"), c102.get("id")))));
        ok(it.call(ict, HttpMethod.POST, "/api/v1/portal-windows/CCE_COURSE_REGISTRATION", Map.of("session", SESSION, "semester", 1, "action", "CLOSE", "reason", "the Centre pauses registration")));
        assertThat(code(it.call(student, HttpMethod.PUT, "/api/v1/me/registration", Map.of("session", SESSION, "semester", 1, "offerings", List.of(c101.get("id")))))).isEqualTo("COURSE_REGISTRATION_CLOSED");
        ok(it.call(ict, HttpMethod.POST, "/api/v1/portal-windows/CCE_COURSE_REGISTRATION", Map.of("session", SESSION, "semester", 1, "action", "REOPEN", "reason", "resumed")));
        it.db(() -> jdbc.sql("UPDATE registration.course_registration SET status = 'SUBMITTED', submitted_at = now() WHERE student_id = :s AND session = :ses AND semester = 1")
                .param("s", cceStudent).param("ses", SESSION).update());
        Map<String, Object> regs = ok(it.get(centre, "/api/v1/cce/registrations?session=" + SESSION + "&semester=1"));
        assertThat(((Number) ((Map) regs.get("counts")).get("submitted")).intValue()).isGreaterThanOrEqualTo(1);

        // (5) the register: the lecturer's; late, then a correction needs its reason; locked; another lecturer is refused; the Centre reopens it
        Map<String, Object> mine = ok(it.get(lecturer, "/api/v1/cce/teaching"));
        assertThat(((List<Map<String, Object>>) mine.get("classes")).stream().map(c -> String.valueOf(c.get("id")))).contains(String.valueOf(c101.get("id")));
        assertThat(it.get(otherLecturer, "/api/v1/cce/teaching/classes/" + c101.get("id")).getStatusCode().value()).isEqualTo(403);
        Map<String, Object> reg = ok(it.call(lecturer, HttpMethod.POST, "/api/v1/cce/teaching/classes/" + c101.get("id") + "/registers",
                Map.of("heldOn", today, "slotId", slotId, "topic", "Week one")));
        assertThat(((List<Map<String, Object>>) reg.get("marks")).stream().map(m -> String.valueOf(m.get("student_id")))).contains(cceStudent.toString());
        String rid = String.valueOf(reg.get("id"));
        Map<String, Object> saved = ok(it.call(lecturer, HttpMethod.PUT, "/api/v1/cce/teaching/registers/" + rid + "/marks",
                Map.of("marks", List.of(Map.of("student", cceStudent.toString(), "status", "LATE")))));
        assertThat(((Map) saved.get("result")).get("marked")).isEqualTo(1);
        assertThat(code(it.call(lecturer, HttpMethod.PUT, "/api/v1/cce/teaching/registers/" + rid + "/marks",
                Map.of("marks", List.of(Map.of("student", cceStudent.toString(), "status", "PRESENT")))))).isEqualTo("ATT_REASON");
        ok(it.call(lecturer, HttpMethod.POST, "/api/v1/cce/teaching/registers/" + rid + "/lock", null));
        assertThat(code(it.call(lecturer, HttpMethod.PUT, "/api/v1/cce/teaching/registers/" + rid + "/marks",
                Map.of("marks", List.of(Map.of("student", cceStudent.toString(), "status", "ABSENT")), "reason", "wrong")))).isEqualTo("ATT_LOCKED");
        assertThat(it.call(lecturer, HttpMethod.POST, "/api/v1/cce/attendance/registers/" + rid + "/unlock", Map.of("reason", "x")).getStatusCode().value()).isEqualTo(403);
        ok(it.call(centre, HttpMethod.POST, "/api/v1/cce/attendance/registers/" + rid + "/unlock", Map.of("reason", "the lecturer marked one student late in error")));
        Map<String, Object> timetable = ok(it.get(student, "/api/v1/me/timetable?semester=1"));
        assertThat(timetable.get("session")).isEqualTo(SESSION);
        assertThat((List) timetable.get("slots")).isNotEmpty();
        Map<String, Object> att = ((List<Map<String, Object>>) timetable.get("attendance")).stream().filter(a -> "CCY 101".equals(a.get("course_code"))).findFirst().orElseThrow();
        assertThat(att.get("late")).isEqualTo(1);
        Map<String, Object> report = ok(it.get(centre, "/api/v1/cce/attendance?session=" + SESSION + "&semester=1"));
        assertThat((List) report.get("rows")).isNotEmpty();

        // (6) the CCE school fees: none stated yet, so nothing clears; the CCE line the Bursary states is the student's alone
        Map<String, Object> me = ok(it.get(student, "/api/v1/me"));
        assertThat(((Map) me.get("fees")).get("stated")).isEqualTo(false);
        assertThat(((Map) ((Map) me.get("windows")).get("schoolFees")).get("state")).isEqualTo("OPEN");
        it.db(() -> jdbc.sql("""
                INSERT INTO finance.fee_schedule (session, item, amount, level, entry_mode, ord, spillover, kind)
                VALUES (:s, 'School fees (full-time)', 99000, 100, NULL, 1, false, 'FEE'), (:s, 'School fees (CCE)', 45000, 100, 'CCE', 1, false, 'FEE')
                """).param("s", SESSION).update());
        Map<String, Object> fees = ok(it.get(student, "/api/v1/me/fees?session=" + SESSION));
        assertThat(fees.get("stated")).isEqualTo(true);
        assertThat(((Number) fees.get("due")).intValue()).isEqualTo(45000);
        Map<String, Object> desk = ok(it.get(bursar, "/api/v1/cce/school-fees?session=" + SESSION));
        assertThat((List) desk.get("lines")).hasSize(1);
        assertThat(it.get(lecturer, "/api/v1/cce/school-fees").getStatusCode().value()).isEqualTo(403);
    }
}
