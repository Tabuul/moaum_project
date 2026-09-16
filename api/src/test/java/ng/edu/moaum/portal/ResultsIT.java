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

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
        it.session(SESSION, 2094);
    }

    @Test
    @SuppressWarnings("unchecked")
    void aSheetPassesEveryDeskAndNoDeskTwiceByOnePerson() {
        UUID lecturer = it.person("ZZR-LECT", "ZZRLECTURER");
        UUID s1 = it.student("ZZRONE", "C00023", null, "MOAUM/MTC/94/9001", 300);
        UUID s2 = it.student("ZZRTWO", "C00023", null, "MOAUM/MTC/94/9002", 300);

        // the catalogue and the offering, through the API
        ResponseEntity<Map> course = it.call(academic, HttpMethod.PUT, "/api/v1/registration/courses/ZZR 301",
                Map.of("title", "A course for the test", "units", 3, "semester", 1, "level", 300, "deptCode", "MTC", "kind", "Compulsory", "state", "LIVE"));
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
                ResponseEntity<Map> ok = it.call(academic, HttpMethod.POST,
                        "/api/v1/registration/course-registrations/" + reg.getBody().get("id") + "/approve", null);
                assertThat(ok.getStatusCode().value()).as(String.valueOf(ok.getBody())).isEqualTo(200);
            }
        }

        // the examination session generates the sheet
        ResponseEntity<Map> exam = it.call(academic, HttpMethod.POST, "/api/v1/results/exam-sessions",
                Map.of("session", SESSION, "semester", 1, "kind", "MAIN", "examsFrom", "2094-12-08", "examsTo", "2094-12-19", "sheetsDue", "2095-01-16"));
        if (exam.getStatusCode().value() == 200) {
            ResponseEntity<Map> opened = it.call(academic, HttpMethod.POST, "/api/v1/results/exam-sessions/" + exam.getBody().get("id") + "/open", null);
            assertThat(opened.getStatusCode().value()).as(String.valueOf(opened.getBody())).isEqualTo(200);
        }
        ResponseEntity<Map> listing = it.get(academic, "/api/v1/results/sheets?course=ZZR 301&session=2094/2095&sem=1");
        List<Map<String, Object>> sheets = (List<Map<String, Object>>) listing.getBody().get("sheets");
        assertThat(sheets).hasSize(1);
        String sheet = String.valueOf(sheets.get(0).get("id"));

        // the roll is both of them
        ResponseEntity<Map> roll = it.get(academic, "/api/v1/registration/class-list?course=ZZR 301&session=2094/2095&sem=1");
        assertThat(roll.getStatusCode().value()).isEqualTo(200);
        assertThat(roll.getBody().get("all")).isEqualTo(2);

        // one mark is not enough to leave the lecturer
        String lect = ItSupport.token("lecturer");
        assertThat(it.call(lect, HttpMethod.PUT, "/api/v1/results/sheets/" + sheet + "/scores",
                Map.of("scores", List.of(Map.of("studentId", s1.toString(), "ca", 30, "exam", 45)))).getStatusCode().value()).isEqualTo(200);
        assertThat(it.call(lect, HttpMethod.POST, "/api/v1/results/sheets/" + sheet + "/advance", Map.of()).getStatusCode().value()).isEqualTo(422);

        assertThat(it.call(lect, HttpMethod.PUT, "/api/v1/results/sheets/" + sheet + "/scores",
                Map.of("scores", List.of(Map.of("studentId", s2.toString(), "outcome", "ABSENT")))).getStatusCode().value()).isEqualTo(200);
        ResponseEntity<Map> submitted = it.call(lect, HttpMethod.POST, "/api/v1/results/sheets/" + sheet + "/advance", Map.of());
        assertThat(submitted.getStatusCode().value()).as(String.valueOf(submitted.getBody())).isEqualTo(200);
        assertThat(submitted.getBody().get("stage")).isEqualTo("VERIFICATION");

        // the same person does not take two consecutive stages
        assertThat(it.call(lect, HttpMethod.POST, "/api/v1/results/sheets/" + sheet + "/advance", Map.of()).getStatusCode().value()).isEqualTo(422);

        String exams = ItSupport.token("exams");
        assertThat(it.call(exams, HttpMethod.POST, "/api/v1/results/sheets/" + sheet + "/advance", Map.of()).getBody().get("stage")).isEqualTo("DEPT_BOARD");

        // returned, with the reason, back to entry
        ResponseEntity<Map> back = it.call(ItSupport.token("hod"), HttpMethod.POST, "/api/v1/results/sheets/" + sheet + "/return",
                Map.of("comment", "two candidates recorded as absent had sat the paper"));
        assertThat(back.getStatusCode().value()).isEqualTo(200);
        ResponseEntity<Map> detail = it.get(academic, "/api/v1/results/sheets/" + sheet);
        assertThat(((Map<?, ?>) detail.getBody().get("sheet")).get("returnedTimes")).isEqualTo(1);

        // the whole chain, a fresh desk each time
        for (String office : List.of("lecturer", "exams", "hod", "facultyexams", "facultyofficer", "dean", "records")) {
            ResponseEntity<Map> r = it.call(ItSupport.token(office), HttpMethod.POST, "/api/v1/results/sheets/" + sheet + "/advance", Map.of());
            assertThat(r.getStatusCode().value()).as(office + ": " + r.getBody()).isEqualTo(200);
        }
        String registrar = ItSupport.token("registrar");
        assertThat(it.call(registrar, HttpMethod.POST, "/api/v1/results/sheets/" + sheet + "/advance", Map.of()).getStatusCode().value()).isEqualTo(422);
        ResponseEntity<Map> published = it.call(ItSupport.token("registrar"), HttpMethod.POST, "/api/v1/results/sheets/" + sheet + "/advance",
                Map.of("minute", "SEN/2095/01"));
        assertThat(published.getStatusCode().value()).as(String.valueOf(published.getBody())).isEqualTo(200);
        assertThat(published.getBody().get("stage")).isEqualTo("PUBLISHED");

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

    private String examSessionId() {
        return jdbc.sql("SELECT id FROM assessment.exam_session WHERE session = :s AND semester = 1 AND kind = 'MAIN'")
                .param("s", SESSION).query(UUID.class).single().toString();
    }
}
