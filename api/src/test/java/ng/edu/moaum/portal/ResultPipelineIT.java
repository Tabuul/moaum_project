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
 * V318 — the pipeline monitor and an upload on behalf. A Programme Examinations Officer who does not teach a course
 * enters its marks only with a reason, and the record names them as the actual uploader beside the lecturer of record;
 * an officer of another programme is refused the sheet; the sheet enters the chain at entry and is submitted on the
 * lecturer's behalf with the reason, after which the same person cannot verify it (BR-006). The monitor counts the
 * stages, the coverage, the missing results and the timeline from the record, in the Head of Department's own
 * department; the broadsheet reads its live coverage. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class ResultPipelineIT {

    static final String SESSION = "2112/2113";
    static final String PROGRAMME = "C00023";
    static final String COURSE = "ZZP 301";

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    ItSupport it;
    String academic = ItSupport.token("academic");
    String ict = ItSupport.token("ict");
    String hod;
    String officer;
    UUID officerId;
    String otherOfficer;
    String otherProg;

    static Map<String, Object> m(Object o) { return (Map<String, Object>) o; }
    static List<Map<String, Object>> l(Object o) { return (List<Map<String, Object>>) o; }

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
        it.session(SESSION, 2112);
        hod = it.officer("hod", "department", "MTC");
        officer = it.officer("exams", "programme", PROGRAMME);
        officerId = jdbc.sql("SELECT id FROM iam.person WHERE staff_number = 'ZZ-EXAMS-" + PROGRAMME + "'").query(UUID.class).single();
        otherProg = jdbc.sql("SELECT code FROM ref.programme WHERE dept_code <> 'MTC' AND NOT archived ORDER BY code LIMIT 1").query(String.class).single();
        otherOfficer = it.officer("exams", "programme", otherProg);
    }

    @Test
    void anOfficerUploadsOnBehalfWithAReasonAndTheMonitorCountsIt() {
        UUID lecturer = it.person("ZZP-LECT", "ZZPLECTURER");
        it.db(() -> jdbc.sql("UPDATE iam.person SET email = coalesce(email, 'zzp-lect@example.invalid') WHERE id = :id").param("id", lecturer).update());
        UUID s1 = it.student("ZZPONE", PROGRAMME, null, "MOAUM/MTC/12/9101", 300);
        UUID s2 = it.student("ZZPTWO", PROGRAMME, null, "MOAUM/MTC/12/9102", 300);

        ResponseEntity<Map> course = it.call(academic, HttpMethod.PUT, "/api/v1/registration/courses/" + COURSE,
                Map.of("title", "A course for the pipeline monitor", "units", 3, "semester", 1, "level", 300, "deptCode", "MTC", "kind", "Core", "state", "LIVE"));
        assertThat(course.getStatusCode().value()).as(String.valueOf(course.getBody())).isEqualTo(200);
        ResponseEntity<Map> offering = it.call(academic, HttpMethod.PUT, "/api/v1/registration/offerings",
                Map.of("courseCode", COURSE, "session", SESSION, "semester", 1, "lecturerId", lecturer.toString()));
        assertThat(offering.getStatusCode().value()).as(String.valueOf(offering.getBody())).isEqualTo(200);
        UUID offeringId = UUID.fromString(String.valueOf(offering.getBody().get("id")));

        for (UUID s : List.of(s1, s2)) {
            ResponseEntity<Map> reg = it.call(academic, HttpMethod.POST, "/api/v1/registration/course-registrations",
                    Map.of("studentId", s.toString(), "session", SESSION, "semester", 1, "level", 300,
                            "entries", List.of(Map.of("offeringId", offeringId.toString(), "units", 18, "entryType", "CURRENT"))));
            if (reg.getStatusCode().value() == 200) {
                ResponseEntity<Map> ok = it.call(hod, HttpMethod.POST, "/api/v1/registration/course-registrations/" + reg.getBody().get("id") + "/approve", null);
                assertThat(ok.getStatusCode().value()).as(String.valueOf(ok.getBody())).isEqualTo(200);
            }
        }

        // the examination session the Director of ICT opens generates the sheet; on a database that has run this before, the
        // session is open already and the sheet is made the same way the opening makes it
        Map<String, Object> examIn = Map.of("session", SESSION, "semester", 1, "kind", "MAIN", "examsFrom", "2112-12-07", "examsTo", "2112-12-18", "sheetsDue", "2113-01-15");
        ResponseEntity<Map> exam = it.call(ict, HttpMethod.POST, "/api/v1/results/exam-sessions", examIn);
        if (exam.getStatusCode().value() == 200) {
            assertThat(it.call(ict, HttpMethod.POST, "/api/v1/results/exam-sessions/" + exam.getBody().get("id") + "/open", null).getStatusCode().value()).isEqualTo(200);
        }
        it.db(() -> jdbc.sql("""
                INSERT INTO assessment.score_sheet (id, offering_id, exam_session_id, due_on)
                SELECT gen_random_uuid(), :o, es.id, es.sheets_due FROM assessment.exam_session es
                 WHERE es.session = :s AND es.semester = 1 AND es.kind = 'MAIN'
                   AND NOT EXISTS (SELECT 1 FROM assessment.score_sheet x WHERE x.offering_id = :o)
                """).param("o", offeringId).param("s", SESSION).update());
        UUID sheet = jdbc.sql("SELECT id FROM assessment.score_sheet WHERE offering_id = :o").param("o", offeringId).query(UUID.class).single();
        // an earlier run on this database left the sheet with marks and decisions: the test's own sheet is put back to a
        // blank entry so the journey is taken again in full
        it.db(() -> {
            jdbc.sql("DELETE FROM assessment.sheet_upload WHERE sheet_id = :id").param("id", sheet).update();
            jdbc.sql("DELETE FROM assessment.score WHERE sheet_id = :id").param("id", sheet).update();
            jdbc.sql("DELETE FROM assessment.decision WHERE sheet_id = :id").param("id", sheet).update();
            return jdbc.sql("UPDATE assessment.score_sheet SET stage = 'ENTRY', returned_times = 0, submitted_at = NULL WHERE id = :id").param("id", sheet).update();
        });

        // an Examinations Officer of another programme is refused the sheet, its roll and score entry alike
        assertThat(it.get(otherOfficer, "/api/v1/results/sheets/" + sheet).getStatusCode().value()).isEqualTo(403);
        assertThat(it.get(otherOfficer, "/api/v1/results/sheets/" + sheet + "/roll").getStatusCode().value()).isEqualTo(403);
        assertThat(it.call(otherOfficer, HttpMethod.PUT, "/api/v1/results/sheets/" + sheet + "/scores",
                Map.of("scores", List.of(Map.of("studentId", s1.toString(), "ca", 30, "exam", 45)), "onBehalfReason", "lecturer away")).getStatusCode().value()).isEqualTo(403);

        // the programme's own officer does not teach the course: an entry without a reason is refused, and nothing is written
        ResponseEntity<Map> noReason = it.call(officer, HttpMethod.PUT, "/api/v1/results/sheets/" + sheet + "/scores",
                Map.of("scores", List.of(Map.of("studentId", s1.toString(), "ca", 30, "exam", 45))));
        assertThat(noReason.getStatusCode().value()).as(String.valueOf(noReason.getBody())).isEqualTo(422);
        assertThat(String.valueOf(noReason.getBody())).contains("RES_UPLOAD_ON_BEHALF_SAYS_WHY");
        assertThat(jdbc.sql("SELECT count(*) FROM assessment.score WHERE sheet_id = :id").param("id", sheet).query(Long.class).single()).isZero();

        // with the reason it is written on the lecturer's behalf: the officer is the actual uploader, the lecturer the owner
        ResponseEntity<Map> withReason = it.call(officer, HttpMethod.PUT, "/api/v1/results/sheets/" + sheet + "/scores",
                Map.of("scores", List.of(Map.of("studentId", s1.toString(), "ca", 30, "exam", 45)), "onBehalfReason", "Lecturer on medical leave; marks from the signed paper sheet"));
        assertThat(withReason.getStatusCode().value()).as(String.valueOf(withReason.getBody())).isEqualTo(200);
        assertThat(withReason.getBody().get("onBehalf")).isEqualTo(true);
        assertThat(withReason.getBody().get("written")).isEqualTo(1);
        Map<String, Object> score = jdbc.sql("SELECT entered_by::text AS by, entered_office, on_behalf, on_behalf_reason FROM assessment.score WHERE sheet_id = :id AND student_id = :s")
                .param("id", sheet).param("s", s1).query().singleRow();
        assertThat(score.get("by")).isEqualTo(officerId.toString());
        assertThat(score.get("entered_office")).isEqualTo("exams");
        assertThat(score.get("on_behalf")).isEqualTo(true);
        assertThat(String.valueOf(score.get("on_behalf_reason"))).contains("medical leave");
        Map<String, Object> upload = jdbc.sql("SELECT uploaded_by::text AS by, uploader_office, owner_id::text AS owner, rows_written FROM assessment.sheet_upload WHERE sheet_id = :id ORDER BY uploaded_at DESC LIMIT 1")
                .param("id", sheet).query().singleRow();
        assertThat(upload.get("by")).isEqualTo(officerId.toString());
        assertThat(upload.get("owner")).isEqualTo(lecturer.toString());
        assertThat(upload.get("rows_written")).isEqualTo(1);
        // the lecturer, who has an address, is told of the upload that wrote a mark — and not of one that wrote none
        long toldBefore = jdbc.sql("SELECT count(*) FROM platform.notice WHERE about_kind = 'score_sheet' AND about_id = :id").param("id", sheet).query(Long.class).single();
        assertThat(toldBefore).as("a notice to the lecturer is queued for the upload on their behalf").isGreaterThanOrEqualTo(1L);
        assertThat(it.call(officer, HttpMethod.PUT, "/api/v1/results/sheets/" + sheet + "/scores",
                Map.of("scores", List.of(Map.of("studentId", s1.toString(), "ca", 30, "exam", 45)), "onBehalfReason", "no change")).getBody().get("written")).isEqualTo(0);
        long toldAfter = jdbc.sql("SELECT count(*) FROM platform.notice WHERE about_kind = 'score_sheet' AND about_id = :id").param("id", sheet).query(Long.class).single();
        assertThat(toldAfter).as("an upload that wrote nothing tells nobody").isEqualTo(toldBefore);

        // the sheet says so: the upload is on it, the officer does not teach, the lecturer does
        ResponseEntity<Map> detail = it.get(officer, "/api/v1/results/sheets/" + sheet);
        assertThat(detail.getStatusCode().value()).isEqualTo(200);
        assertThat(detail.getBody().get("youTeach")).isEqualTo(false);
        assertThat(l(detail.getBody().get("uploads"))).hasSize(1);
        assertThat(l(detail.getBody().get("marks")).get(0).get("onBehalf")).isEqualTo(true);
        String lect = TestTokens.token(lecturer, List.of("lecturer"));
        assertThat(it.get(lect, "/api/v1/results/sheets/" + sheet).getBody().get("youTeach")).isEqualTo(true);

        // the monitor, in the Head of Department's own department: the sheet sits at entry, one of two results is in, the
        // course is listed as partly entered, and the upload on behalf is on the timeline
        ResponseEntity<Map> monitor = it.get(hod, "/api/v1/results/pipeline?session=" + SESSION + "&sem=1");
        assertThat(monitor.getStatusCode().value()).as(String.valueOf(monitor.getBody())).isEqualTo(200);
        assertThat(monitor.getBody().get("dept")).isEqualTo("MTC");
        Map<String, Object> entry = l(monitor.getBody().get("stages")).stream().filter(x -> "ENTRY".equals(x.get("stage"))).findFirst().orElseThrow();
        assertThat(((Number) entry.get("sheets")).intValue()).isGreaterThanOrEqualTo(1);
        Map<String, Object> ours = l(monitor.getBody().get("sheets")).stream().filter(x -> COURSE.equals(x.get("courseCode"))).findFirst().orElseThrow();
        assertThat(ours.get("stage")).isEqualTo("ENTRY");
        assertThat(ours.get("candidates")).isEqualTo(2);
        assertThat(ours.get("received")).isEqualTo(1);
        assertThat(ours.get("missing")).isEqualTo(1);
        assertThat((List<String>) ours.get("flags")).contains("PARTIAL", "ON_BEHALF");
        Map<String, Object> missing = l(monitor.getBody().get("missing")).stream().filter(x -> COURSE.equals(x.get("courseCode"))).findFirst().orElseThrow();
        assertThat(missing.get("why")).isEqualTo("PARTIAL");
        assertThat(l(monitor.getBody().get("timeline"))).anySatisfy(e -> {
            assertThat(e.get("courseCode")).isEqualTo(COURSE);
            assertThat(e.get("kind")).isEqualTo("UPLOAD_ON_BEHALF");
        });
        Map<String, Object> cov = m(monitor.getBody().get("coverage"));
        assertThat(((Number) cov.get("expected")).intValue()).isGreaterThanOrEqualTo(2);
        assertThat(((Number) cov.get("missing")).intValue()).isGreaterThanOrEqualTo(1);
        assertThat(l(monitor.getBody().get("programmes"))).anySatisfy(p -> {
            assertThat(p.get("programmeCode")).isEqualTo(PROGRAMME);
            assertThat(p.get("level")).isEqualTo(300);
        });
        // the other programme's officer reads a monitor without this sheet in it
        ResponseEntity<Map> other = it.get(otherOfficer, "/api/v1/results/pipeline?session=" + SESSION + "&sem=1");
        assertThat(other.getStatusCode().value()).isEqualTo(200);
        assertThat(other.getBody().get("prog")).isEqualTo(otherProg);
        assertThat(l(other.getBody().get("sheets"))).noneMatch(x -> COURSE.equals(x.get("courseCode")));
        // and the HOD of MTC is refused another department's monitor, whatever the parameters say
        assertThat(it.get(hod, "/api/v1/results/pipeline?session=" + SESSION + "&sem=1&dept=" + jdbc.sql("SELECT dept_code FROM ref.programme WHERE code = :p").param("p", otherProg).query(String.class).single())
                .getStatusCode().value()).isEqualTo(422);

        // the second candidate, then submission on the lecturer's behalf: refused without a reason, recorded with one, and
        // the officer who submitted cannot take verification (BR-006)
        assertThat(it.call(officer, HttpMethod.PUT, "/api/v1/results/sheets/" + sheet + "/scores",
                Map.of("scores", List.of(Map.of("studentId", s2.toString(), "outcome", "ABSENT")), "onBehalfReason", "Lecturer on medical leave")).getStatusCode().value()).isEqualTo(200);
        ResponseEntity<Map> submitBlank = it.call(officer, HttpMethod.POST, "/api/v1/results/sheets/" + sheet + "/advance", Map.of());
        assertThat(submitBlank.getStatusCode().value()).as(String.valueOf(submitBlank.getBody())).isEqualTo(422);
        assertThat(String.valueOf(submitBlank.getBody())).contains("RES_SUBMIT_ON_BEHALF_SAYS_WHY");
        ResponseEntity<Map> submitted = it.call(officer, HttpMethod.POST, "/api/v1/results/sheets/" + sheet + "/advance", Map.of("comment", "Lecturer on medical leave"));
        assertThat(submitted.getStatusCode().value()).as(String.valueOf(submitted.getBody())).isEqualTo(200);
        assertThat(submitted.getBody().get("stage")).isEqualTo("VERIFICATION");
        assertThat(it.call(officer, HttpMethod.POST, "/api/v1/results/sheets/" + sheet + "/advance", Map.of()).getStatusCode().value()).isEqualTo(422);
        ResponseEntity<Map> after = it.get(hod, "/api/v1/results/sheets/" + sheet);
        assertThat(l(after.getBody().get("chain"))).anySatisfy(d -> {
            assertThat(d.get("kind")).isEqualTo("SUBMIT");
            assertThat(String.valueOf(d.get("comment"))).startsWith("Submitted on behalf of");
        });

        // the broadsheet's live coverage: the course column is complete — two expected, two in, none missing
        ResponseEntity<Map> broadsheet = it.get(hod, "/api/v1/results/broadsheet?prog=" + PROGRAMME + "&level=300&session=" + SESSION + "&sem=1");
        assertThat(broadsheet.getStatusCode().value()).as(String.valueOf(broadsheet.getBody())).isEqualTo(200);
        Map<String, Object> coverage = m(broadsheet.getBody().get("coverage"));
        Map<String, Object> col = l(coverage.get("courses")).stream().filter(x -> COURSE.equals(x.get("courseCode"))).findFirst().orElseThrow();
        assertThat(col.get("expected")).isEqualTo(2);
        assertThat(col.get("received")).isEqualTo(2);
        assertThat(col.get("missing")).isEqualTo(0);
        assertThat(col.get("stage")).isEqualTo("VERIFICATION");
        assertThat(l(broadsheet.getBody().get("rows"))).allSatisfy(r -> assertThat(r.get("missing")).isEqualTo(0));
    }
}
