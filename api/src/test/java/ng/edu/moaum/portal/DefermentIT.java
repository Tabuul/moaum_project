package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

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
 * Deferment (V259), end to end: a student asks to defer a semester, the department, the faculty and the Registry
 * decide in turn, the period comes into force, the register refuses a registration for it, the student's status
 * reads DEFERRED, the return is listed and confirmed and the status restored. A second request for the same period
 * is refused; another student, another department's Head and a lecturer are refused; a session deferment covers
 * both semesters. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class DefermentIT {

    static final String SESSION = "2095/2096";

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    ItSupport it;
    String registrar, hodMtc, hodEco, deanSc;

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
        it.session(SESSION, 2095);
        // the first semester of the test session has begun, so an approved deferment of it comes into force at once
        it.db(() -> jdbc.sql("""
                INSERT INTO policy.semester (id, session, number, lectures_from, state)
                SELECT gen_random_uuid(), :s, 1, current_date - 1, 'OPEN' WHERE NOT EXISTS (SELECT 1 FROM policy.semester WHERE session = :s AND number = 1)
                """).param("s", SESSION).update());
        registrar = TestTokens.token(it.person("ZZDF-REG", "ZZDFREGISTRAR"), List.of("registrar"));
        hodMtc = TestTokens.token(head("ZZDF-HOD-MTC", "MTC"), List.of("hod"));
        hodEco = TestTokens.token(head("ZZDF-HOD-ECO", "ECO"), List.of("hod"));
        UUID dean = it.person("ZZDF-DEAN", "ZZDFDEAN");
        grant(dean, "dean", "faculty", "SC");
        deanSc = TestTokens.token(dean, List.of("dean"));
    }

    private UUID head(String staffNo, String dept) {
        UUID p = it.person(staffNo, "ZZDFHEAD" + dept);
        grant(p, "hod", "department", dept);
        return p;
    }

    private void grant(UUID person, String office, String scopeKind, String scopeId) {
        it.db(() -> jdbc.sql("""
                INSERT INTO iam.office_assignment (id, person_id, office_code, scope_kind, scope_id, instrument, granted_by, valid_from)
                SELECT gen_random_uuid(), :p, :o, :k, :sid, 'integration test', :p, current_date
                 WHERE NOT EXISTS (SELECT 1 FROM iam.office_assignment a WHERE a.person_id = :p AND a.office_code = :o AND a.valid_to IS NULL)
                """).param("p", person).param("o", office).param("k", scopeKind).param("sid", scopeId).update());
    }

    @Test
    void aSemesterDeferredFromRequestToReturn() {
        int n = new Random().nextInt(8000) + 1000;
        UUID student = it.student("ZZDF" + n + "A", "C00023", "MOAUM/ADM/95/" + (100000 + n), "MOAUM/MTC/95/" + n, 200);
        UUID other = it.student("ZZDF" + n + "B", "C00023", "MOAUM/ADM/95/" + (200000 + n), "MOAUM/MTC/95/" + (n + 1), 200);
        // the students have an email and a phone, so the notices have somewhere to go
        for (UUID s : List.of(student, other)) it.db(() -> jdbc.sql("""
                INSERT INTO people.student_contact (student_id, phone, email, updated_at) VALUES (:s, '08011112222', 'zzdf' || :n || '@example.com', now())
                ON CONFLICT (student_id) DO UPDATE SET email = EXCLUDED.email, phone = EXCLUDED.phone
                """).param("s", s).param("n", s.toString().substring(0, 8)).update());
        String me = TestTokens.token(student, List.of("student"));
        String stranger = TestTokens.token(other, List.of("student"));

        // TEST 1 — eligible, opens and submits a semester deferment
        ResponseEntity<Map> home = it.get(me, "/api/v1/me/deferments");
        assertThat(home.getStatusCode().value()).as(String.valueOf(home.getBody())).isEqualTo(200);
        assertThat(((Map<String, Object>) home.getBody().get("eligibility")).get("eligible")).isEqualTo(true);
        ResponseEntity<Map> opened = it.call(me, HttpMethod.POST, "/api/v1/me/deferments", Map.of("kind", "SEMESTER", "session", SESSION, "semester", 1,
                "reason", "PERSONAL", "explanation", "I must attend to a family matter away from Makurdi for the semester.", "declared", true));
        assertThat(opened.getStatusCode().value()).as(String.valueOf(opened.getBody())).isEqualTo(200);
        UUID id = UUID.fromString(String.valueOf(opened.getBody().get("id")));
        assertThat(String.valueOf(opened.getBody().get("reference"))).matches("DEF-\\d{4}-\\d{5}");
        assertThat(opened.getBody().get("return_session")).isEqualTo(SESSION);
        assertThat(opened.getBody().get("return_semester")).isEqualTo(2);
        ResponseEntity<Map> submitted = it.call(me, HttpMethod.POST, "/api/v1/me/deferments/" + id + "/submit", null);
        assertThat(submitted.getStatusCode().value()).as(String.valueOf(submitted.getBody())).isEqualTo(200);
        assertThat(submitted.getBody().get("state")).isEqualTo("SUBMITTED");
        assertThat(jdbc.sql("SELECT count(*) FROM platform.notice WHERE about_kind = 'student' AND about_id = :s").param("s", student).query(Long.class).single()).isGreaterThanOrEqualTo(1);

        // TEST 5 — a second request while one is in review is refused
        ResponseEntity<Map> again = it.call(me, HttpMethod.POST, "/api/v1/me/deferments", Map.of("kind", "SESSION", "session", SESSION, "reason", "MEDICAL", "declared", true));
        assertThat(again.getStatusCode().value()).isEqualTo(422);

        // TEST 11 — another student cannot read it; TEST 12 — another department's Head cannot; TEST 10 — a lecturer cannot decide
        assertThat(it.get(stranger, "/api/v1/me/deferments/" + id).getStatusCode().value()).isEqualTo(403);
        assertThat(it.get(hodEco, "/api/v1/deferments/" + id).getStatusCode().value()).isEqualTo(403);
        assertThat(it.call(ItSupport.token("lecturer"), HttpMethod.POST, "/api/v1/deferments/" + id + "/action", Map.of("action", "APPROVE")).getStatusCode().value()).isEqualTo(403);
        assertThat(it.call(hodMtc, HttpMethod.POST, "/api/v1/deferments/" + id + "/action", Map.of("action", "APPROVE")).getStatusCode().value()).isEqualTo(422);

        // TEST 2 — the department reviews: a rejection without a reason is refused; the recommendation goes through
        assertThat(it.get(hodMtc, "/api/v1/deferments/" + id).getStatusCode().value()).isEqualTo(200);
        assertThat(it.call(hodMtc, HttpMethod.POST, "/api/v1/deferments/" + id + "/action", Map.of("action", "REJECT")).getStatusCode().value()).isEqualTo(422);
        assertThat(act(hodMtc, id, "RECOMMEND", "Genuine")).isEqualTo("DEPT_RECOMMENDED");
        assertThat(act(deanSc, id, "FAC_RECOMMEND", null)).isEqualTo("FAC_RECOMMENDED");

        // TEST 3 — approved; the semester has begun, so the deferment is in force and the status reads DEFERRED
        assertThat(act(registrar, id, "APPROVE", "Approved by the Registrar")).isEqualTo("ACTIVE");
        assertThat(jdbc.sql("SELECT status FROM people.student WHERE id = :s").param("s", student).query(String.class).single()).isEqualTo("DEFERRED");
        assertThat(jdbc.sql("SELECT expires_on FROM people.status_change WHERE student_id = :s ORDER BY effective_on DESC, id DESC LIMIT 1").param("s", student).query(java.sql.Date.class).optional()).isPresent();

        // TEST 4 — the register refuses a registration for the deferred period, on the record
        assertThatThrownBy(() -> it.db(() -> jdbc.sql("SELECT registration.student_draft(:s, :ses, 1)").param("s", student).param("ses", SESSION).query(UUID.class).single()))
                .hasMessageContaining("REGISTRATION UNAVAILABLE");
        // the other semester is not held
        it.db(() -> jdbc.sql("SELECT registration.student_draft(:s, :ses, 2)").param("s", student).param("ses", SESSION).query(UUID.class).single());

        // TEST 6 — the student sees the request and its history; the letter's data is theirs to read
        ResponseEntity<Map> mine = it.get(me, "/api/v1/me/deferments/" + id);
        assertThat(mine.getStatusCode().value()).isEqualTo(200);
        assertThat((List<?>) mine.getBody().get("history")).hasSizeGreaterThanOrEqualTo(5);
        assertThat(((List<Map<String, Object>>) it.get(me, "/api/v1/me/deferments").getBody().get("requests"))).hasSize(1);

        // TEST 8 — due to return: the return date brought forward, the student is listed as DUE
        it.db(() -> jdbc.sql("UPDATE people.deferment SET return_on = current_date WHERE id = :id").param("id", id).update());
        List<Map<String, Object>> due = (List<Map<String, Object>>) it.get(hodMtc, "/api/v1/deferments/returns?status=DUE").getBody().get("rows");
        assertThat(due.stream().map(r -> String.valueOf(r.get("id")))).contains(id.toString());
        assertThat(((List<Map<String, Object>>) it.get(hodEco, "/api/v1/deferments/returns").getBody().get("rows")).stream().map(r -> String.valueOf(r.get("id")))).doesNotContain(id.toString());

        // TEST 9 — the return confirmed: the status restored, the register open again
        ResponseEntity<Map> back = it.call(hodMtc, HttpMethod.POST, "/api/v1/deferments/" + id + "/return", Map.of("note", "Presented at the department"));
        assertThat(back.getStatusCode().value()).as(String.valueOf(back.getBody())).isEqualTo(200);
        assertThat(back.getBody().get("state")).isEqualTo("COMPLETED");
        assertThat(jdbc.sql("SELECT status FROM people.student WHERE id = :s").param("s", student).query(String.class).single()).isEqualTo("ACTIVE");
        it.db(() -> jdbc.sql("SELECT registration.student_draft(:s, :ses, 1)").param("s", student).param("ses", SESSION).query(UUID.class).single());

        // TEST 7 — a whole session deferred covers both semesters; the dashboard counts it within the department
        ResponseEntity<Map> whole = it.call(stranger, HttpMethod.POST, "/api/v1/me/deferments", Map.of("kind", "SESSION", "session", SESSION, "reason", "FINANCIAL",
                "explanation", "I cannot raise the fees this session and will return next session.", "declared", true));
        assertThat(whole.getStatusCode().value()).as(String.valueOf(whole.getBody())).isEqualTo(200);
        UUID wid = UUID.fromString(String.valueOf(whole.getBody().get("id")));
        assertThat(whole.getBody().get("return_session")).isEqualTo(jdbc.sql("SELECT people.next_session(:s)").param("s", SESSION).query(String.class).single());
        assertThat(it.call(stranger, HttpMethod.POST, "/api/v1/me/deferments/" + wid + "/submit", null).getBody().get("state")).isEqualTo("SUBMITTED");
        act(hodMtc, wid, "RECOMMEND", null); act(deanSc, wid, "FAC_RECOMMEND", null);
        assertThat(act(registrar, wid, "APPROVE", null)).isIn("APPROVED", "ACTIVE");
        assertThat(jdbc.sql("SELECT people.deferment_covers(:s, :ses, 2)").param("s", other).param("ses", SESSION).query(Boolean.class).single()).isTrue();
        Map<String, Object> totals = (Map<String, Object>) it.get(hodMtc, "/api/v1/deferments/dashboard?session=" + SESSION).getBody().get("totals");
        assertThat(((Number) totals.get("approved")).intValue()).isGreaterThanOrEqualTo(2);
        assertThat(((Number) ((Map<String, Object>) it.get(hodEco, "/api/v1/deferments/dashboard?session=" + SESSION).getBody().get("totals")).get("total")).intValue()).isEqualTo(0);
    }

    private String act(String token, UUID id, String action, String note) {
        Map<String, Object> body = note == null ? Map.of("action", action) : Map.of("action", action, "note", note);
        ResponseEntity<Map> r = it.call(token, HttpMethod.POST, "/api/v1/deferments/" + id + "/action", body);
        assertThat(r.getStatusCode().value()).as(action + ": " + r.getBody()).isEqualTo(200);
        return String.valueOf(r.getBody().get("state"));
    }
}
