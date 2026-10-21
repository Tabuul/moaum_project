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
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.web.client.RestClient;

/**
 * V602: graduation batches over the API, and the graduated record closed. Three 400 Level students of a four-year programme in a
 * session of their own: one with every course passed and published, one owing a carry-over, one deferred. The preview writes
 * nothing and names the verdicts; a batch is opened on the Senate's minute, executed by the officer who opened it (another is
 * refused), graduates the eligible student only — status GRADUATED with its history, the list entry approved with the batch, final
 * clearance started — and leaves the other two with their reasons; executed again it graduates nobody twice. Afterwards the graduate
 * is refused a school-fee reference and a course registration for a later session, the register view reads closed with no menu and
 * no carry-over, the course search is refused, the old registration and results stay readable, the report counts the graduate, and
 * the Registrar's correction (refused to the Academic Office) puts the status back with the impact recorded. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class GraduationBatchIT {

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    ItSupport it;
    RestClient open;
    final String academic = ItSupport.token("academic");
    final String registrar = ItSupport.token("registrar");
    final String ict = ItSupport.token("ict");
    String session, later;
    UUID eligible, owing, deferred;

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
        open = RestClient.builder().baseUrl("http://localhost:" + port).defaultStatusHandler(st -> true, (q, r) -> { }).build();
    }

    private String signedIn(UUID student, String matric) {
        assertThat(it.call(registrar, HttpMethod.PUT, "/api/v1/student-auth/accounts/" + student, Map.of("password", "first password 6020")).getStatusCode().value()).isEqualTo(200);
        String t = String.valueOf(open.post().uri("/api/v1/student-auth/sign-in").contentType(MediaType.APPLICATION_JSON)
                .body(Map.of("matricNo", matric, "password", "first password 6020")).retrieve().toEntity(Map.class).getBody().get("token"));
        assertThat(it.call(t, HttpMethod.POST, "/api/v1/student-auth/change-password", Map.of("current", "first password 6020", "next", "Own-Password-6020")).getStatusCode().value()).isEqualTo(200);
        return t;
    }

    @Test
    void aBatchGraduatesTheEligibleStudentOnlyAndClosesTheRecordToNewFeesAndRegistration() {
        int y = it.freeYear(4100, 4190, 0, 1);
        session = y + "/" + (y + 1);
        later = (y + 1) + "/" + (y + 2);
        it.session(session, y);
        it.session(later, y + 1);
        String yy = String.format("%02d", y % 100);
        int n = it.freeDraw(1000, 9999, k -> List.of("MOAUM/GRB/" + yy + "/" + k, "MOAUM/ADM/" + yy + "/71" + k, "ZZGRB" + k));
        String matric = "MOAUM/GRB/" + yy + "/" + n;
        eligible = it.student("ZZGRB" + n, "C00023", "MOAUM/ADM/" + yy + "/71" + n, matric, 400);
        owing = it.student("ZZGRBOWE" + n, "C00023", "MOAUM/ADM/" + yy + "/72" + n, "MOAUM/GRB/" + yy + "/" + (n + 10000), 400);
        deferred = it.student("ZZGRBDEF" + n, "C00023", "MOAUM/ADM/" + yy + "/73" + n, "MOAUM/GRB/" + yy + "/" + (n + 20000), 400);
        String code = "ZGB " + (100 + n % 800);
        UUID offering = UUID.randomUUID();
        UUID sheet = UUID.randomUUID();
        it.db(() -> {
            jdbc.sql("UPDATE people.student SET status = 'DEFERRED', entry_session = :s WHERE id = :id").param("s", session).param("id", deferred).update();
            jdbc.sql("UPDATE people.student SET entry_session = :s WHERE id IN (:a, :b)").param("s", session).param("a", eligible).param("b", owing).update();
            String dept = jdbc.sql("SELECT dept_code FROM ref.programme WHERE code = 'C00023'").query(String.class).single();
            jdbc.sql("INSERT INTO catalogue.course (code, title, units, semester, level, dept_code, kind, state) VALUES (:c, 'Final-year course for the batch test', 3, 1, 400, :d, 'Core', 'LIVE') ON CONFLICT (code) DO NOTHING")
                    .param("c", code).param("d", dept).update();
            jdbc.sql("INSERT INTO catalogue.course_offer (course_code, programme_code, level, basis) VALUES (:c, 'C00023', 400, 'Core') ON CONFLICT DO NOTHING").param("c", code).update();
            jdbc.sql("INSERT INTO catalogue.offering (id, course_code, session, semester) VALUES (:o, :c, :s, 1)").param("o", offering).param("c", code).param("s", session).update();
            for (UUID st : List.of(eligible, owing)) {
                UUID reg = UUID.randomUUID();
                jdbc.sql("INSERT INTO people.enrolment (id, student_id, session, level) VALUES (gen_random_uuid(), :st, :s, 400) ON CONFLICT (student_id, session) DO NOTHING").param("st", st).param("s", session).update();
                jdbc.sql("INSERT INTO registration.course_registration (id, student_id, session, semester, level, status, submitted_at, approved_at) VALUES (:r, :st, :s, 1, 400, 'APPROVED', now(), now())")
                        .param("r", reg).param("st", st).param("s", session).update();
                jdbc.sql("INSERT INTO registration.entry (registration_id, offering_id, units, status) VALUES (:r, :o, 3, 'APPROVED')").param("r", reg).param("o", offering).update();
            }
            jdbc.sql("INSERT INTO assessment.score_sheet (id, offering_id, stage, senate_minute, published_at, submitted_at) VALUES (:id, :o, 'PUBLISHED', 'SEN/IT/602', now(), now())")
                    .param("id", sheet).param("o", offering).update();
            jdbc.sql("INSERT INTO assessment.score (sheet_id, student_id, ca, exam, outcome) VALUES (:sh, :a, 30, 45, 'GRADED'), (:sh, :b, 10, 15, 'GRADED')")
                    .param("sh", sheet).param("a", eligible).param("b", owing).update();
            // a fee line of the later session: the graduate is charged nothing for it afterwards
            return jdbc.sql("INSERT INTO finance.fee_schedule (session, item, amount, level) VALUES (:s, 'School fees', 100000, 400)").param("s", later).update();
        });
        String student = signedIn(eligible, matric);

        // TEST 1–2, 7, 10: the preview writes nothing and names the verdicts
        Map<String, Object> filter = Map.of("students", List.of(eligible.toString(), owing.toString(), deferred.toString()));
        ResponseEntity<Map> preview = it.call(academic, HttpMethod.POST, "/api/v1/graduation/batches/preview", Map.of("session", session, "filter", filter));
        assertThat(preview.getStatusCode().value()).as(String.valueOf(preview.getBody())).isEqualTo(200);
        Map<String, Object> verdicts = ((List<Map<String, Object>>) preview.getBody().get("rows")).stream()
                .collect(java.util.stream.Collectors.toMap(r -> String.valueOf(r.get("studentId")), r -> String.valueOf(r.get("verdict"))));
        assertThat(verdicts).containsEntry(eligible.toString(), "ELIGIBLE").containsEntry(owing.toString(), "CARRY_OVER").containsEntry(deferred.toString(), "DEFERRED");
        assertThat(jdbc.sql("SELECT count(*) FROM records.graduand WHERE student_id IN (:a, :b, :c)").param("a", eligible).param("b", owing).param("c", deferred).query(Long.class).single()).isZero();
        // ICT reads; it opens no batch
        assertThat(it.call(ict, HttpMethod.POST, "/api/v1/graduation/batches", Map.of("session", session, "senateMinute", "SEN/IT/602", "reason", "ICT tries a batch", "filter", filter)).getStatusCode().value()).isEqualTo(403);
        // a batch without a minute is refused
        assertThat(it.call(academic, HttpMethod.POST, "/api/v1/graduation/batches", Map.of("session", session, "senateMinute", " ", "reason", "Integration test: the batch", "filter", filter)).getStatusCode().value()).isNotEqualTo(200);

        // TEST 25: the batch opened on the minute, executed by its officer — the eligible student graduated, the others left with their reasons
        ResponseEntity<Map> opened = it.call(academic, HttpMethod.POST, "/api/v1/graduation/batches",
                Map.of("session", session, "senateMinute", "SEN/IT/602", "reason", "Integration test: the " + session + " graduands confirmed", "filter", filter));
        assertThat(opened.getStatusCode().value()).as(String.valueOf(opened.getBody())).isEqualTo(200);
        String ref = String.valueOf(opened.getBody().get("batch_ref"));
        assertThat(ref).matches("GRAD/\\d{4}/\\d{6}");
        assertThat(opened.getBody()).containsEntry("selected", 3).containsEntry("eligible", 1).containsEntry("graduated", 0);
        String path = "/api/v1/graduation/batches/" + ref.substring(5);
        assertThat(it.call(registrar, HttpMethod.POST, path + "/execute", null).getBody()).containsEntry("code", "GRAD_BATCH_OWNER");
        ResponseEntity<Map> run = it.call(academic, HttpMethod.POST, path + "/execute", null);
        assertThat(run.getStatusCode().value()).as(String.valueOf(run.getBody())).isEqualTo(200);
        assertThat(run.getBody()).containsEntry("graduated", 1).containsEntry("remaining", 0).containsEntry("done", true);
        assertThat(jdbc.sql("SELECT status FROM people.student WHERE id = :id").param("id", eligible).query(String.class).single()).isEqualTo("GRADUATED");
        assertThat(jdbc.sql("SELECT status FROM people.student WHERE id = :id").param("id", owing).query(String.class).single()).isEqualTo("ACTIVE");
        assertThat(jdbc.sql("SELECT status FROM people.student WHERE id = :id").param("id", deferred).query(String.class).single()).isEqualTo("DEFERRED");
        Map<String, Object> g = jdbc.sql("SELECT senate_state, senate_minute, batch_ref, graduated_at IS NOT NULL AS stamped, final_level FROM records.graduand WHERE student_id = :id AND session = :s")
                .param("id", eligible).param("s", session).query().singleRow();
        assertThat(g).containsEntry("senate_state", "APPROVED").containsEntry("senate_minute", "SEN/IT/602").containsEntry("batch_ref", ref).containsEntry("stamped", true).containsEntry("final_level", 400);
        assertThat(jdbc.sql("SELECT count(*) FROM people.status_change WHERE student_id = :id AND to_status = 'GRADUATED' AND instrument = 'SEN/IT/602'").param("id", eligible).query(Long.class).single()).isEqualTo(1L);
        assertThat(jdbc.sql("SELECT count(*) FROM clearance.process WHERE workflow = 'FINAL' AND student_id = :id AND cancelled_at IS NULL").param("id", eligible).query(Long.class).single()).isEqualTo(1L);
        assertThat(jdbc.sql("SELECT count(*) FROM platform.notice WHERE about_id = :id AND template_key = 'STUDENT_GRADUATED'").param("id", eligible).query(Long.class).single()).isGreaterThanOrEqualTo(1L);
        // TEST 56: executed again, nobody is graduated twice
        ResponseEntity<Map> again = it.call(academic, HttpMethod.POST, path + "/execute", null);
        assertThat(again.getBody()).containsEntry("graduated", 0).containsEntry("done", true);
        assertThat(jdbc.sql("SELECT count(*) FROM people.status_change WHERE student_id = :id AND to_status = 'GRADUATED'").param("id", eligible).query(Long.class).single()).isEqualTo(1L);
        Map<String, Object> detail = it.get(academic, path).getBody();
        assertThat(detail).containsEntry("graduated", 1).containsEntry("rejected", 2);
        assertThat((List<Map<String, Object>>) detail.get("rows")).extracting(r -> r.get("verdict")).containsExactlyInAnyOrder("ELIGIBLE", "CARRY_OVER", "DEFERRED");

        // TEST 12–16: the record is closed — no charge for the later session, no reference, no registration, no carry-over, the search refused
        assertThat(jdbc.sql("SELECT (finance.position(:id, :s)).due").param("id", eligible).param("s", later).query(java.math.BigDecimal.class).single()).isEqualByComparingTo("0");
        ResponseEntity<Map> reference = it.call(student, HttpMethod.POST, "/api/v1/me/fees/references", Map.of("session", later, "amount", 100000));
        assertThat(reference.getStatusCode().value()).isNotEqualTo(200);
        assertThat(String.valueOf(reference.getBody())).contains("SCHOOL_FEES_CLOSED_GRADUATED");
        ResponseEntity<Map> view = it.get(student, "/api/v1/me/registration?session=" + later + "&semester=1");
        assertThat(view.getStatusCode().value()).isEqualTo(200);
        assertThat((Map<String, Object>) view.getBody().get("closed")).containsEntry("code", "REG_STUDENT_GRADUATED");
        assertThat((List<?>) view.getBody().get("menu")).isEmpty();
        assertThat((List<?>) view.getBody().get("outstanding")).isEmpty();
        ResponseEntity<Map> save = it.call(student, HttpMethod.PUT, "/api/v1/me/registration", Map.of("session", later, "semester", 1, "offerings", List.of()));
        assertThat(save.getStatusCode().value()).isNotEqualTo(200);
        assertThat(save.getBody()).containsEntry("code", "REG_STUDENT_NOT_ELIGIBLE");
        assertThat(it.call(student, HttpMethod.POST, "/api/v1/me/registration/courses", Map.of("session", later, "semester", 1, "offering", offering)).getStatusCode().value()).isNotEqualTo(200);
        assertThat(it.get(student, "/api/v1/me/registration/courses?session=" + later + "&semester=1&q=" + code.replace(" ", "%20")).getBody()).containsEntry("code", "REG_STUDENT_NOT_ELIGIBLE");
        // TEST 17–18: the old registration and the results stay readable
        ResponseEntity<Map> old = it.get(student, "/api/v1/me/registration?session=" + session + "&semester=1");
        assertThat(((Map<String, Object>) old.getBody().get("registration"))).containsEntry("status", "APPROVED");
        assertThat(it.get(student, "/api/v1/me/results").getStatusCode().value()).isEqualTo(200);

        // the report counts the graduate; the verdict reads already graduated
        List<Map<String, Object>> report = (List<Map<String, Object>>) it.get(academic, "/api/v1/graduation/report?session=" + session + "&by=programme").getBody().get("rows");
        assertThat(report).anySatisfy(r -> assertThat(((Number) r.get("graduated")).intValue()).isGreaterThanOrEqualTo(1));
        assertThat(((Map<String, Object>) it.get(academic, "/api/v1/graduation/students/" + eligible + "/verdict?session=" + session).getBody().get("verdict"))).containsEntry("verdict", "ALREADY_GRADUATED");

        // TEST 61: the correction is the Registrar's, on a reason and evidence; a plain status change is refused
        assertThat(it.call(academic, HttpMethod.POST, "/api/v1/graduation/students/" + eligible + "/correct", Map.of("reason", "Graduated in error: results of another student", "evidence", "REG/IT/602")).getStatusCode().value()).isEqualTo(403);
        assertThat(it.call(registrar, HttpMethod.POST, "/api/v1/graduation/students/" + eligible + "/correct", Map.of("reason", "short", "evidence", "REG/IT/602")).getBody()).containsEntry("code", "GRAD_CORRECTION_REASON");
        ResponseEntity<Map> corrected = it.call(registrar, HttpMethod.POST, "/api/v1/graduation/students/" + eligible + "/correct",
                Map.of("reason", "Graduated in error: the published result belongs to another student", "evidence", "Registrar's memo REG/IT/602"));
        assertThat(corrected.getStatusCode().value()).as(String.valueOf(corrected.getBody())).isEqualTo(200);
        assertThat(corrected.getBody()).containsEntry("graduation_session", session).containsEntry("batch_ref", ref);
        assertThat(jdbc.sql("SELECT status FROM people.student WHERE id = :id").param("id", eligible).query(String.class).single()).isEqualTo("ACTIVE");
        assertThat(jdbc.sql("SELECT senate_state FROM records.graduand WHERE student_id = :id AND session = :s").param("id", eligible).param("s", session).query(String.class).single()).isEqualTo("AWAITING");
        assertThat(jdbc.sql("SELECT count(*) FROM records.graduation_correction WHERE student_id = :id").param("id", eligible).query(Long.class).single()).isEqualTo(1L);
        // the fee line of the later session is charged again now the record is in study
        assertThat(jdbc.sql("SELECT (finance.position(:id, :s)).due").param("id", eligible).param("s", later).query(java.math.BigDecimal.class).single()).isEqualByComparingTo("100000");
        it.db(() -> jdbc.sql("DELETE FROM finance.fee_schedule WHERE session = :s").param("s", later).update());
    }
}
