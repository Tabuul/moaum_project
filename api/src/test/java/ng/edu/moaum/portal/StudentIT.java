package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.List;
import java.util.Map;
import java.util.UUID;

import ng.edu.moaum.portal.shared.AuditContext;
import ng.edu.moaum.portal.shared.AuditContextHolder;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;
import org.springframework.web.client.RestClient;

/**
 * The register, and the three kinds of field.
 *
 * <p>One invented student is put on the register directly, as the intake run
 * would put them there, and then everything else happens through the API: the
 * list in scope finds them, the record reads whole, an open field is written
 * where it stands, a field that changes only on evidence becomes a request the
 * Registry decides, and a field read from JAMB is refused with the remedy that
 * says where it is actually corrected. A search for the surname finds them and
 * leaves a row in the search log, because looking somebody up is processing
 * their personal data whether or not anything changes.
 *
 * <p>Needs a database the migrations have been applied to: set DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT,
        properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
class StudentIT {

    /** A session of the test's own, which no candidate was ever admitted into. */
    static final String SESSION = "2097/2098";
    static final UUID STUDENT = UUID.fromString("d0000000-0000-0000-0000-000000002097");
    static final String SURNAME = "TESTSURNAME2097";

    @Value("${local.server.port}")
    int port;

    @Autowired
    JdbcClient jdbc;

    @Autowired
    PlatformTransactionManager transactions;

    RestClient client;
    UUID academic = UUID.randomUUID();
    String token = TestTokens.token(academic, List.of("academic"));
    String programme;
    String faculty;
    String department;

    @BeforeEach
    void setUp() {
        client = RestClient.builder()
                .baseUrl("http://localhost:" + port)
                .defaultStatusHandler(status -> true, (request, response) -> { })
                .build();
        onTheRegister();
    }

    /**
     * The student, put on the register with an admission number as the intake
     * run puts one there. Idempotent, so the test can run again on the same
     * database: the row is written once and its names restored on every run.
     */
    void onTheRegister() {
        Map<String, Object> p = jdbc.sql("""
                SELECT code, faculty_code, dept_code FROM ref.programme
                 WHERE archived = false ORDER BY code LIMIT 1
                """).query().singleRow();
        programme = String.valueOf(p.get("code"));
        faculty = String.valueOf(p.get("faculty_code"));
        department = String.valueOf(p.get("dept_code"));

        TransactionTemplate tx = new TransactionTemplate(transactions);
        AuditContext context = new AuditContext(academic, "academic",
                "StudentIT: one invented student on the register for " + SESSION, null, null);
        AuditContextHolder.with(context, () -> tx.execute(status -> {
            jdbc.sql("""
                    INSERT INTO people.student (id, admission_no, surname, other_names, sex, programme_code,
                                                entry_mode, entry_session, entry_level, current_level, status)
                    VALUES (:id, 'MOAUM/ADM/97/990001', :surname, 'Invented Name', 'F', :prog,
                            'UTME', :session, 100, 100, 'ADMITTED')
                    ON CONFLICT (id) DO UPDATE SET surname = EXCLUDED.surname, other_names = EXCLUDED.other_names,
                                                   programme_code = EXCLUDED.programme_code
                    """)
                    .param("id", STUDENT).param("surname", SURNAME)
                    .param("prog", programme).param("session", SESSION)
                    .update();
            return null;
        }));
    }

    @Test
    void theRegisterInScopeFindsTheStudentAndTheRecordReadsWhole() {
        ResponseEntity<Map> list = get("/api/v1/student/students?fac=" + faculty + "&dept=" + department + "&q=" + SURNAME);
        assertThat(list.getStatusCode().value()).as(String.valueOf(list.getBody())).isEqualTo(200);
        List<?> rows = (List<?>) list.getBody().get("rows");
        assertThat(rows).hasSize(1);
        Map<?, ?> row = (Map<?, ?>) rows.get(0);
        assertThat(row.get("id")).isEqualTo(STUDENT.toString());
        assertThat(row.get("admissionNo")).isEqualTo("MOAUM/ADM/97/990001");
        assertThat(row.get("facultyCode")).isEqualTo(faculty);
        assertThat(row.get("status")).isEqualTo("ADMITTED");
        assertThat((Integer) list.getBody().get("total")).isGreaterThanOrEqualTo(1);

        ResponseEntity<Map> record = get("/api/v1/student/students/" + STUDENT + "?session=" + SESSION);
        assertThat(record.getStatusCode().value()).as(String.valueOf(record.getBody())).isEqualTo(200);
        assertThat(((Map<?, ?>) record.getBody().get("student")).get("surname")).isEqualTo(SURNAME);
        assertThat((List<?>) record.getBody().get("biodata")).isNotEmpty();
        assertThat((List<?>) record.getBody().get("convocationClearance")).hasSize(8);
        assertThat((List<?>) record.getBody().get("registrationClearance")).hasSize(8);
        assertThat(record.getBody().get("approvedUnits")).isEqualTo(0);
    }

    @Test
    void anOpenFieldIsWrittenWhereItStands() {
        ResponseEntity<Map> put = put("/api/v1/student/students/" + STUDENT + "/biodata/preferred_name",
                Map.of("value", "Invented"));
        assertThat(put.getStatusCode().value()).as(String.valueOf(put.getBody())).isEqualTo(200);
        assertThat(put.getBody().get("tier")).isEqualTo("open");
        assertThat(put.getBody().get("pending")).isEqualTo(false);
        assertThat(field("preferred_name").get("value")).isEqualTo("Invented");
    }

    @Test
    void aFieldReadFromJambIsRefusedWithTheRemedy() {
        ResponseEntity<Map> put = put("/api/v1/student/students/" + STUDENT + "/biodata/university_email",
                Map.of("value", "somebody@example.com"));
        assertThat(put.getStatusCode().value()).as(String.valueOf(put.getBody())).isEqualTo(422);
        assertThat(put.getBody().get("code")).isEqualTo("STU_FIELD_LOCKED");
        Map<?, ?> remedy = (Map<?, ?>) put.getBody().get("remedy");
        assertThat(remedy.get("message")).isEqualTo("Corrected with JAMB, not here");
        assertThat(remedy.get("office")).isEqualTo("Academic Office");
    }

    @Test
    void aFieldOnApprovalBecomesARequestTheRegistryDecides() {
        String wanted = "Testlandish " + System.currentTimeMillis() % 100000;
        ResponseEntity<Map> put = put("/api/v1/student/students/" + STUDENT + "/biodata/nationality",
                Map.of("value", wanted, "evidence", "Passport sighted (StudentIT)"));
        assertThat(put.getStatusCode().value()).as(String.valueOf(put.getBody())).isEqualTo(200);
        assertThat(put.getBody().get("tier")).isEqualTo("approval");
        assertThat(put.getBody().get("pending")).isEqualTo(true);
        String change = String.valueOf(put.getBody().get("changeId"));

        ResponseEntity<Map> queue = get("/api/v1/student/biodata-changes?state=PENDING");
        assertThat(queue.getStatusCode().value()).as(String.valueOf(queue.getBody())).isEqualTo(200);
        List<?> rows = (List<?>) queue.getBody().get("rows");
        assertThat(rows).anyMatch(r -> change.equals(((Map<?, ?>) r).get("id")));
        Map<?, ?> mine = (Map<?, ?>) rows.stream()
                .filter(r -> change.equals(((Map<?, ?>) r).get("id"))).findFirst().orElseThrow();
        assertThat(mine.get("surname")).isEqualTo(SURNAME);
        assertThat(mine.get("label")).isEqualTo("Nationality");
        assertThat(mine.get("toValue")).isEqualTo(wanted);
        assertThat((Integer) ((Map<?, ?>) queue.getBody().get("counts")).get("pending")).isGreaterThanOrEqualTo(1);

        // approved, and only then is the value on the record
        ResponseEntity<Map> approve = post("/api/v1/student/biodata-changes/" + change + "/approve",
                Map.of("decision", "Evidence seen (StudentIT)"));
        assertThat(approve.getStatusCode().value()).as(String.valueOf(approve.getBody())).isEqualTo(200);
        assertThat(approve.getBody().get("state")).isEqualTo("APPROVED");
        assertThat(field("nationality").get("value")).isEqualTo(wanted);

        // and a decision is made once
        ResponseEntity<Map> again = post("/api/v1/student/biodata-changes/" + change + "/approve",
                Map.of("decision", "Again (StudentIT)"));
        assertThat(again.getStatusCode().value()).isEqualTo(422);
        assertThat(again.getBody().get("code")).isEqualTo("STU_CHANGE_DECIDED");
    }

    @Test
    void aRefusalWithoutAReasonIsRefused() {
        ResponseEntity<Map> put = put("/api/v1/student/students/" + STUDENT + "/biodata/state_of_origin",
                Map.of("value", "Inventedstate"));
        assertThat(put.getStatusCode().value()).as(String.valueOf(put.getBody())).isEqualTo(200);
        String change = String.valueOf(put.getBody().get("changeId"));

        ResponseEntity<Map> blank = post("/api/v1/student/biodata-changes/" + change + "/refuse",
                Map.of("decision", "  "));
        assertThat(blank.getStatusCode().value()).as(String.valueOf(blank.getBody())).isEqualTo(422);
        assertThat(blank.getBody().get("code")).isEqualTo("STU_DECISION_REQUIRED");

        ResponseEntity<Map> asked = post("/api/v1/student/biodata-changes/" + change + "/ask-evidence", Map.of());
        assertThat(asked.getStatusCode().value()).as(String.valueOf(asked.getBody())).isEqualTo(200);
        assertThat(asked.getBody().get("state")).isEqualTo("EVIDENCE_ASKED");

        ResponseEntity<Map> refused = post("/api/v1/student/biodata-changes/" + change + "/refuse",
                Map.of("decision", "No local government identification supplied (StudentIT)"));
        assertThat(refused.getStatusCode().value()).as(String.valueOf(refused.getBody())).isEqualTo(200);
        assertThat(refused.getBody().get("state")).isEqualTo("REFUSED");
    }

    @Test
    void everySearchIsWrittenDownAndTheSurnameFindsTheStudent() {
        long before = jdbc.sql("SELECT count(*) FROM people.search_log WHERE term = :t")
                .param("t", SURNAME).query(Long.class).single();

        ResponseEntity<Map> found = get("/api/v1/student/search?q=" + SURNAME + "&kind=students");
        assertThat(found.getStatusCode().value()).as(String.valueOf(found.getBody())).isEqualTo(200);
        List<?> hits = (List<?>) found.getBody().get("hits");
        assertThat(hits).anyMatch(h -> STUDENT.toString().equals(((Map<?, ?>) h).get("id")));

        long after = jdbc.sql("SELECT count(*) FROM people.search_log WHERE term = :t")
                .param("t", SURNAME).query(Long.class).single();
        assertThat(after).isEqualTo(before + 1);
    }

    @Test
    void theRecordsViewsAnswerInScopeAndTwoOfThemSayWhyTheyAreEmpty() {
        ResponseEntity<Map> students = get("/api/v1/student/records/students?fac=" + faculty + "&dept=" + department
                + "&session=" + SESSION);
        assertThat(students.getStatusCode().value()).as(String.valueOf(students.getBody())).isEqualTo(200);
        assertThat((List<?>) students.getBody().get("rows"))
                .anyMatch(r -> SURNAME.equals(String.valueOf(((Map<?, ?>) r).get("name")).split(",")[0]));
        assertThat((Integer) students.getBody().get("total")).isGreaterThanOrEqualTo(1);
        assertThat(students.getBody().get("notServed")).isNull();

        ResponseEntity<Map> fees = get("/api/v1/student/records/fees?fac=" + faculty + "&session=" + SESSION);
        assertThat(fees.getStatusCode().value()).isEqualTo(200);
        assertThat((List<?>) fees.getBody().get("rows")).isEmpty();
        assertThat(String.valueOf(fees.getBody().get("notServed"))).contains("Bursary");

        for (String view : List.of("registration", "results", "exams", "allocation", "clearance", "attendance")) {
            ResponseEntity<Map> r = get("/api/v1/student/records/" + view + "?fac=" + faculty + "&session=" + SESSION);
            assertThat(r.getStatusCode().value()).as(view + ": " + r.getBody()).isEqualTo(200);
        }
    }

    @Test
    void anIntakeOnASessionWithNoCandidatesBringsNobodyOnto() {
        ResponseEntity<Map> r = post("/api/v1/student/intake/2097/2098", Map.of());
        assertThat(r.getStatusCode().value()).as(String.valueOf(r.getBody())).isEqualTo(200);
        assertThat(r.getBody().get("session")).isEqualTo(SESSION);
        assertThat(r.getBody().get("broughtOnto")).isEqualTo(0);
    }

    // ── helpers ─────────────────────────────────────────────────────────

    Map<?, ?> field(String field) {
        ResponseEntity<Map> record = get("/api/v1/student/students/" + STUDENT);
        assertThat(record.getStatusCode().value()).as(String.valueOf(record.getBody())).isEqualTo(200);
        return (Map<?, ?>) ((List<?>) record.getBody().get("biodata")).stream()
                .filter(f -> field.equals(((Map<?, ?>) f).get("field")))
                .findFirst().orElseThrow();
    }

    ResponseEntity<Map> get(String path) {
        return client.get().uri(path).header(HttpHeaders.AUTHORIZATION, "Bearer " + token)
                .retrieve().toEntity(Map.class);
    }

    ResponseEntity<Map> put(String path, Map<String, Object> body) {
        return client.put().uri(path).header(HttpHeaders.AUTHORIZATION, "Bearer " + token)
                .header("X-Reason", "StudentIT").contentType(MediaType.APPLICATION_JSON).body(body)
                .retrieve().toEntity(Map.class);
    }

    ResponseEntity<Map> post(String path, Map<String, Object> body) {
        return client.post().uri(path).header(HttpHeaders.AUTHORIZATION, "Bearer " + token)
                .header("X-Reason", "StudentIT").contentType(MediaType.APPLICATION_JSON).body(body)
                .retrieve().toEntity(Map.class);
    }
}
