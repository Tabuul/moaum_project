package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.List;
import java.util.Map;
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
 * A course, an offering, two registrations, an examination session that
 * generates the sheet, and the chain the sheet passes: no blank outcome, no
 * two consecutive desks by one person, a return to entry, publication on the
 * Senate minute and nothing before it. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT,
        properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
class ResultsIT {

    static final String SESSION = "2094/2095";

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    ItSupport it;
    String academic = ItSupport.token("academic");
    /* V318: every desk bound to a scope acts from within it — the Head of Department over MTC, the Programme Examinations
       Officer over the students' programme, the faculty desks over MTC's faculty; a desk with no scope reaches no sheet */
    String hod;
    String exams;
    String dean;
    String facultyExams;
    String facultyOfficer;

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
        it.session(SESSION, 2094);
        String faculty = jdbc.sql("SELECT faculty_code FROM ref.department WHERE code = 'MTC'").query(String.class).single();
        hod = it.officer("hod", "department", "MTC");
        exams = it.officer("exams", "programme", "C00023");
        dean = it.officer("dean", "faculty", faculty);
        facultyExams = it.officer("facultyexams", "faculty", faculty);
        facultyOfficer = it.officer("facultyofficer", "faculty", faculty);
    }

    @Test
    @SuppressWarnings("unchecked")
    void aSheetPassesEveryDeskAndNoDeskTwiceByOnePerson() {
        UUID lecturer = it.person("ZZR-LECT", "ZZRLECTURER");
        UUID s1 = it.student("ZZRONE", "C00023", null, "MOAUM/MTC/94/9001", 300);
        UUID s2 = it.student("ZZRTWO", "C00023", null, "MOAUM/MTC/94/9002", 300);

        // the catalogue and the offering, through the API
        ResponseEntity<Map> course = it.call(academic, HttpMethod.PUT, "/api/v1/registration/courses/ZZR 301",
                Map.of("title", "A course for the test", "units", 3, "semester", 1, "level", 300, "deptCode", "MTC", "kind", "Core", "state", "LIVE"));
        assertThat(course.getStatusCode().value()).as(String.valueOf(course.getBody())).isEqualTo(200);
        ResponseEntity<Map> offering = it.call(academic, HttpMethod.PUT, "/api/v1/registration/offerings",
                Map.of("courseCode", "ZZR 301", "session", SESSION, "semester", 1, "lecturerId", lecturer.toString()));
        assertThat(offering.getStatusCode().value()).as(String.valueOf(offering.getBody())).isEqualTo(200);
        String offeringId = String.valueOf(offering.getBody().get("id"));

        // a sheet already published by an earlier run on this database: the journey was taken
        ResponseEntity<Map> before = it.get(academic, "/api/v1/results/sheets?course=ZZR 301&session=2094/2095&sem=1");
        List<Map<String, Object>> sheetsBefore = (List<Map<String, Object>>) before.getBody().get("sheets");
        if (!sheetsBefore.isEmpty() && "PUBLISHED".equals(sheetsBefore.get(0).get("stage"))) {
            return;
        }

        // registrations for both, approved (eighteen units satisfies the 300-level minimum)
        for (UUID s : List.of(s1, s2)) {
            ResponseEntity<Map> reg = it.call(academic, HttpMethod.POST, "/api/v1/registration/course-registrations",
                    Map.of("studentId", s.toString(), "session", SESSION, "semester", 1, "level", 300,
                            "entries", List.of(Map.of("offeringId", offeringId, "units", 18, "entryType", "CURRENT"))));
            if (reg.getStatusCode().value() == 200) {
                // approval is the Head of Department's, one step
                ResponseEntity<Map> ok = it.call(hod, HttpMethod.POST,
                        "/api/v1/registration/course-registrations/" + reg.getBody().get("id") + "/approve", null);
                assertThat(ok.getStatusCode().value()).as(String.valueOf(ok.getBody())).isEqualTo(200);
            }
        }

        // the examination session generates the sheet: set up and opened by the Director of ICT (Portal Management); the Academic
        // Office and Exams & Records no longer may
        Map<String, Object> examIn = Map.of("session", SESSION, "semester", 1, "kind", "MAIN", "examsFrom", "2094-12-08", "examsTo", "2094-12-19", "sheetsDue", "2095-01-16");
        assertThat(it.call(academic, HttpMethod.POST, "/api/v1/results/exam-sessions", examIn).getStatusCode().value()).isEqualTo(403);
        assertThat(it.call(ItSupport.token("records"), HttpMethod.POST, "/api/v1/results/exam-sessions", examIn).getStatusCode().value()).isEqualTo(403);
        String ict = ItSupport.token("ict");
        ResponseEntity<Map> exam = it.call(ict, HttpMethod.POST, "/api/v1/results/exam-sessions", examIn);
        if (exam.getStatusCode().value() == 200) {
            ResponseEntity<Map> opened = it.call(ict, HttpMethod.POST, "/api/v1/results/exam-sessions/" + exam.getBody().get("id") + "/open", null);
            assertThat(opened.getStatusCode().value()).as(String.valueOf(opened.getBody())).isEqualTo(200);
            // V335: opening releases nothing; the score sheets are released to the lecturers by their own act
            ResponseEntity<Map> released = it.call(ict, HttpMethod.POST, "/api/v1/results/exam-sessions/" + exam.getBody().get("id") + "/release-sheets", null);
            assertThat(released.getStatusCode().value()).as(String.valueOf(released.getBody())).isEqualTo(200);
        }
        ResponseEntity<Map> listing = it.get(academic, "/api/v1/results/sheets?course=ZZR 301&session=2094/2095&sem=1");
        List<Map<String, Object>> sheets = (List<Map<String, Object>>) listing.getBody().get("sheets");
        assertThat(sheets).hasSize(1);
        String sheet = String.valueOf(sheets.get(0).get("id"));

        // the roll is both of them
        ResponseEntity<Map> roll = it.get(academic, "/api/v1/registration/class-list?course=ZZR 301&session=2094/2095&sem=1");
        assertThat(roll.getStatusCode().value()).isEqualTo(200);
        assertThat(roll.getBody().get("all")).isEqualTo(2);

        // a lecturer reaches only the sheets of courses allocated to them: a stranger in the lecturer's office is
        // refused the sheet, its roll, its class list and score entry alike, whatever the sheet id they typed
        String stranger = ItSupport.token("lecturer");
        assertThat(it.get(stranger, "/api/v1/results/sheets/" + sheet).getStatusCode().value()).isEqualTo(403);
        assertThat(it.get(stranger, "/api/v1/results/sheets/" + sheet + "/roll").getStatusCode().value()).isEqualTo(403);
        assertThat(it.get(stranger, "/api/v1/registration/class-list?course=ZZR 301&session=2094/2095&sem=1").getStatusCode().value()).isEqualTo(403);
        assertThat(it.call(stranger, HttpMethod.PUT, "/api/v1/results/sheets/" + sheet + "/scores",
                Map.of("scores", List.of(Map.of("studentId", s1.toString(), "ca", 30, "exam", 45)))).getStatusCode().value()).isEqualTo(403);
        // the lecturer the offering names reads and enters their own
        String lect = TestTokens.token(lecturer, List.of("lecturer"));
        assertThat(it.get(lect, "/api/v1/results/sheets/" + sheet).getStatusCode().value()).isEqualTo(200);
        assertThat(it.get(lect, "/api/v1/registration/class-list?course=ZZR 301&session=2094/2095&sem=1").getStatusCode().value()).isEqualTo(200);
        assertThat(it.get(lect, "/api/v1/me/teaching?session=" + SESSION).getStatusCode().value()).isEqualTo(200);

        // one mark is not enough to leave the lecturer
        assertThat(it.call(lect, HttpMethod.PUT, "/api/v1/results/sheets/" + sheet + "/scores",
                Map.of("scores", List.of(Map.of("studentId", s1.toString(), "ca", 30, "exam", 45)))).getStatusCode().value()).isEqualTo(200);
        assertThat(it.call(lect, HttpMethod.POST, "/api/v1/results/sheets/" + sheet + "/advance", Map.of()).getStatusCode().value()).isEqualTo(422);

        assertThat(it.call(lect, HttpMethod.PUT, "/api/v1/results/sheets/" + sheet + "/scores",
                Map.of("scores", List.of(Map.of("studentId", s2.toString(), "outcome", "ABSENT")))).getStatusCode().value()).isEqualTo(200);
        ResponseEntity<Map> submitted = it.call(lect, HttpMethod.POST, "/api/v1/results/sheets/" + sheet + "/advance", Map.of());
        assertThat(submitted.getStatusCode().value()).as(String.valueOf(submitted.getBody())).isEqualTo(200);
        assertThat(submitted.getBody().get("stage")).isEqualTo("VERIFICATION");

        // the lecturer does not take the next stage: it is not theirs (V357; the same person twice in a row is refused too — BR-006,
        // ResultPipelineIT's officer who submitted on the lecturer's behalf and may not verify)
        assertThat(it.call(lect, HttpMethod.POST, "/api/v1/results/sheets/" + sheet + "/advance", Map.of()).getStatusCode().value()).isEqualTo(403);
        // V357: a stage is taken only by its own desk, on the server — the Head of Department may not verify the sheet
        assertThat(it.call(hod, HttpMethod.POST, "/api/v1/results/sheets/" + sheet + "/advance", Map.of()).getStatusCode().value()).isEqualTo(403);
        // V357: held scripts keep to the sheet's scope, and a script is held only while the sheet is at entry
        String held = "/api/v1/results/sheets/" + sheet + "/held";
        assertThat(it.call(stranger, HttpMethod.GET, held, null).getStatusCode().value()).isEqualTo(403);
        assertThat(it.call(stranger, HttpMethod.POST, held, Map.of("number", "MOAUM/MTC/94/9999", "ca", 10, "exam", 20)).getStatusCode().value()).isEqualTo(403);
        ResponseEntity<Map> pastEntry = it.call(lect, HttpMethod.POST, held, Map.of("number", "MOAUM/MTC/94/9999", "ca", 10, "exam", 20));
        assertThat(pastEntry.getStatusCode().value()).as(String.valueOf(pastEntry.getBody())).isEqualTo(422);
        assertThat(pastEntry.getBody().get("code")).isEqualTo("HELD_SHEET_NOT_AT_ENTRY");
        assertThat(it.getList(lect, held).getStatusCode().value()).isEqualTo(200);

        // V318: a desk outside the sheet's scope does not reach it — a Head of Department of another department, an Examinations
        // Officer of another programme, and an officer whose grant names no scope at all
        String otherProg = jdbc.sql("SELECT code FROM ref.programme WHERE dept_code <> 'MTC' AND NOT archived ORDER BY code LIMIT 1").query(String.class).single();
        String otherDept = jdbc.sql("SELECT dept_code FROM ref.programme WHERE code = :p").param("p", otherProg).query(String.class).single();
        assertThat(it.get(it.officer("hod", "department", otherDept), "/api/v1/results/sheets/" + sheet).getStatusCode().value()).isEqualTo(403);
        assertThat(it.get(it.officer("exams", "programme", otherProg), "/api/v1/results/sheets/" + sheet).getStatusCode().value()).isEqualTo(403);
        assertThat(it.get(ItSupport.token("hod"), "/api/v1/results/sheets/" + sheet).getStatusCode().value()).isEqualTo(403);
        assertThat(it.call(ItSupport.token("exams"), HttpMethod.POST, "/api/v1/results/sheets/" + sheet + "/advance", Map.of()).getStatusCode().value()).isEqualTo(403);

        assertThat(it.call(exams, HttpMethod.POST, "/api/v1/results/sheets/" + sheet + "/advance", Map.of()).getBody().get("stage")).isEqualTo("DEPT_BOARD");
        // V357: at the Head of Department's desk, the Faculty Examinations Officer may not take it on, nor the Programme
        // Examinations Officer return it
        assertThat(it.call(facultyExams, HttpMethod.POST, "/api/v1/results/sheets/" + sheet + "/advance", Map.of()).getStatusCode().value()).isEqualTo(403);
        assertThat(it.call(exams, HttpMethod.POST, "/api/v1/results/sheets/" + sheet + "/return", Map.of("comment", "not this desk's to return")).getStatusCode().value())
                .isEqualTo(403);

        // returned, with the reason, back to entry
        ResponseEntity<Map> back = it.call(hod, HttpMethod.POST, "/api/v1/results/sheets/" + sheet + "/return",
                Map.of("comment", "two candidates recorded as absent had sat the paper"));
        assertThat(back.getStatusCode().value()).isEqualTo(200);
        ResponseEntity<Map> detail = it.get(academic, "/api/v1/results/sheets/" + sheet);
        assertThat(((Map<?, ?>) detail.getBody().get("sheet")).get("returnedTimes")).isEqualTo(1);

        // the whole chain, a fresh desk each time, each from within its own scope
        Map<String, String> desks = Map.of("lecturer", lect, "exams", exams, "hod", hod, "facultyexams", facultyExams,
                "facultyofficer", facultyOfficer, "dean", dean, "records", ItSupport.token("records"));
        for (String office : List.of("lecturer", "exams", "hod", "facultyexams", "facultyofficer", "dean", "records")) {
            ResponseEntity<Map> r = it.call(desks.get(office), HttpMethod.POST, "/api/v1/results/sheets/" + sheet + "/advance", Map.of());
            assertThat(r.getStatusCode().value()).as(office + ": " + r.getBody()).isEqualTo(200);
        }
        String registrar = ItSupport.token("registrar");
        // V357: Exams & Records may not publish; the Registrar does, on the minute
        assertThat(it.call(ItSupport.token("records"), HttpMethod.POST, "/api/v1/results/sheets/" + sheet + "/advance", Map.of("minute", "SEN/2095/01")).getStatusCode().value())
                .isEqualTo(403);
        it.db(() -> jdbc.sql("INSERT INTO people.student_contact (student_id, email, phone) VALUES (:s, 'zz.results.9001@example.com', '08012349001') "
                + "ON CONFLICT (student_id) DO UPDATE SET email = EXCLUDED.email, phone = EXCLUDED.phone").param("s", s1).update());
        assertThat(it.call(registrar, HttpMethod.POST, "/api/v1/results/sheets/" + sheet + "/advance", Map.of()).getStatusCode().value()).isEqualTo(422);
        ResponseEntity<Map> published = it.call(ItSupport.token("registrar"), HttpMethod.POST, "/api/v1/results/sheets/" + sheet + "/advance",
                Map.of("minute", "SEN/2095/01"));
        assertThat(published.getStatusCode().value()).as(String.valueOf(published.getBody())).isEqualTo(200);
        assertThat(published.getBody().get("stage")).isEqualTo("PUBLISHED");
        // V357: each student is told the result is published — by email, with no mark in it — and by a text
        List<Map<String, Object>> told = jdbc.sql("SELECT channel, subject, body FROM platform.notice WHERE about_kind = 'student' AND about_id = :s AND created_at > now() - interval '1 hour'")
                .param("s", s1).query().listOfRows();
        assertThat(told).anySatisfy(n -> {
            assertThat(n.get("channel")).isEqualTo("EMAIL");
            assertThat(n.get("subject")).isEqualTo("Your result in ZZR 301 is published");
            assertThat(String.valueOf(n.get("body"))).doesNotContain("75").doesNotContain("Grade");
        });
        assertThat(told).anySatisfy(n -> assertThat(n.get("subject")).isEqualTo("Results published"));

        // V358: a published mark is corrected only by an amendment — raised by the course's lecturer (not a stranger), approved by
        // each desk in turn (another desk refused), applied by the Registrar on the minute as a new version of the mark
        String amend = "/api/v1/results/sheets/" + sheet + "/amendments";
        Map<String, Object> raise = Map.of("studentId", s1.toString(), "ca", 32, "exam", 45, "reason", "The CA script found after the result query");
        assertThat(it.call(stranger, HttpMethod.POST, amend, raise).getStatusCode().value()).isEqualTo(403);
        ResponseEntity<List> raised = it.callList(lect, HttpMethod.POST, amend, raise);
        assertThat(raised.getStatusCode().value()).as(String.valueOf(raised.getBody())).isEqualTo(200);
        Map<String, Object> am = (Map<String, Object>) raised.getBody().get(0);
        assertThat(am.get("stage")).isEqualTo("VERIFICATION");
        String amId = String.valueOf(am.get("id"));
        assertThat((List<Map<String, Object>>) (List<?>) it.getList(exams, "/api/v1/results/amendments").getBody()).extracting(x -> String.valueOf(x.get("id"))).contains(amId);
        assertThat(it.call(hod, HttpMethod.POST, "/api/v1/results/amendments/" + amId + "/advance", Map.of()).getStatusCode().value()).isEqualTo(403);
        for (String desk : List.of("exams", "hod", "facultyexams", "facultyofficer", "dean", "records")) {
            ResponseEntity<List> r = it.callList(desks.get(desk), HttpMethod.POST, "/api/v1/results/amendments/" + amId + "/advance", Map.of("comment", "seen"));
            assertThat(r.getStatusCode().value()).as(desk + ": " + r.getBody()).isEqualTo(200);
        }
        assertThat(it.call(registrar, HttpMethod.POST, "/api/v1/results/amendments/" + amId + "/advance", Map.of()).getStatusCode().value()).isEqualTo(422);
        ResponseEntity<List> applied = it.callList(registrar, HttpMethod.POST, "/api/v1/results/amendments/" + amId + "/advance", Map.of("minute", "SEN/2095/02"));
        assertThat(applied.getStatusCode().value()).as(String.valueOf(applied.getBody())).isEqualTo(200);
        assertThat(((Map<String, Object>) applied.getBody().get(0)).get("stage")).isEqualTo("APPLIED");
        List<Map<String, Object>> marksAfter = (List<Map<String, Object>>) it.get(academic, "/api/v1/results/sheets/" + sheet).getBody().get("marks");
        assertThat(marksAfter).anySatisfy(m -> {
            assertThat(String.valueOf(m.get("studentId"))).isEqualTo(s1.toString());
            assertThat(((Number) m.get("total")).intValue()).isEqualTo(77);
            assertThat(m.get("amended")).isEqualTo(true);
        });

        ResponseEntity<Map> after = it.get(academic, "/api/v1/results/sheets/" + sheet);
        List<Map<String, Object>> marks = (List<Map<String, Object>>) after.getBody().get("marks");
        assertThat(marks).extracting(m -> m.get("grade")).contains("A");
        assertThat((List<?>) after.getBody().get("chain")).hasSizeGreaterThanOrEqualTo(10);

        ResponseEntity<Map> monitor = it.get(academic, "/api/v1/results/exam-sessions/" + examSessionId() + "/monitor");
        assertThat(monitor.getStatusCode().value()).isEqualTo(200);
        assertThat((List<?>) monitor.getBody().get("faculties")).isNotEmpty();

        // the institutional overview read model — every statistical structure the screen draws
        ResponseEntity<Map> ov = it.get(academic, "/api/v1/reporting/overview?session=" + SESSION + "&semester=1");
        assertThat(ov.getStatusCode().value()).as(String.valueOf(ov.getBody())).isEqualTo(200);
        Map<String, Object> body = ov.getBody();
        assertThat(((Map<?, ?>) body.get("uni")).get("faculties")).isNotNull();
        List<Map<String, Object>> ovResults = (List<Map<String, Object>>) body.get("results");
        assertThat(ovResults).anySatisfy(r -> {
            assertThat(((Number) r.get("expected")).intValue()).isGreaterThan(0);
            assertThat(((Number) r.get("submitted")).intValue()).isGreaterThanOrEqualTo(((Number) r.get("approved")).intValue());
        });
        assertThat((List<?>) body.get("grades")).anySatisfy(g -> assertThat(((Map<?, ?>) g).get("grade")).isEqualTo("A"));
        assertThat((List<?>) body.get("weeks")).as("a submitted sheet gives at least one week").isNotEmpty();
    }

    /** V357: the server's rule of who takes each stage is the table the screens read */
    @Test
    void theServersStageDesksAreTheScreens() {
        for (Map.Entry<String, List<String>> e : ng.edu.moaum.portal.results.Sheets.DESK.entrySet()) {
            List<String> server = jdbc.sql("SELECT unnest(assessment.stage_offices(:s))").param("s", e.getKey()).query(String.class).list();
            assertThat(server).as(e.getKey()).containsExactlyInAnyOrderElementsOf(e.getValue());
        }
    }

    private String examSessionId() {
        return jdbc.sql("SELECT id FROM assessment.exam_session WHERE session = :s AND semester = 1 AND kind = 'MAIN'")
                .param("s", SESSION).query(UUID.class).single().toString();
    }
}
