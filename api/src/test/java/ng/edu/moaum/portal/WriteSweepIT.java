package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.List;
import java.util.Map;
import java.util.UUID;

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
 * What the write sweep found (every write endpoint sent for real on a copy of the demo data): a write is answered with what
 * happened, never a server error and never "done" when nothing changed. A missing record is 404; an input the request's record
 * limits (a mark out of 60, a note too long) is refused before anything runs; a date that is not a date is refused with a
 * reason; an act on a record not in the state it needs says so. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class WriteSweepIT {

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    private static int status(ResponseEntity<Map> r) {
        return r.getStatusCode().value();
    }

    @Test
    void writesAnswerWhatHappened() {
        ItSupport it = new ItSupport(port, jdbc, transactions);
        String tag = UUID.randomUUID().toString().substring(0, 6).toUpperCase();
        UUID person = it.person("ZZ-SWEEP-" + tag, "ZZSWEEP");
        String bursar = TestTokens.token(person, List.of("bursar"));
        String hrm = TestTokens.token(person, List.of("hrm"));
        String nobody = UUID.randomUUID().toString();

        // a session id that is not a session id at all names none of the person's sessions
        assertThat(status(it.call(TestTokens.token(person, List.of("registrar")), HttpMethod.POST, "/api/v1/auth/sessions/not-hex/end", null))).isEqualTo(404);

        // a workstation, store item, asset, applicant, request or consumer that is not there is 404 — the act did nothing
        assertThat(status(it.call(TestTokens.token(person, List.of("academic")), HttpMethod.PUT,
                "/api/v1/admissions/sessions/2079/2080/putme/workstations/" + nobody, Map.of("operational", true)))).isEqualTo(404);
        assertThat(status(it.call(bursar, HttpMethod.POST, "/api/v1/stores/items/" + nobody + "/adjust", Map.of("delta", 1)))).isEqualTo(404);
        assertThat(status(it.call(bursar, HttpMethod.POST, "/api/v1/stores/assets/" + nobody + "/verify", null))).isEqualTo(404);
        assertThat(status(it.call(hrm, HttpMethod.POST, "/api/v1/hr/applicants/" + nobody + "/assess", Map.of("score", 50)))).isEqualTo(404);
        assertThat(status(it.call(TestTokens.token(person, List.of("registrar")), HttpMethod.POST, "/api/v1/governance/dsr/" + nobody + "/advance",
                Map.of("state", "IN_PROGRESS")))).isEqualTo(404);
        assertThat(status(it.call(TestTokens.token(person, List.of("ict")), HttpMethod.POST, "/api/v1/apimgmt/consumers/" + nobody + "/deprecate", null))).isEqualTo(404);
        assertThat(status(it.call(bursar, HttpMethod.POST, "/api/v1/expenditure/requisitions/" + nobody + "/po", null))).isEqualTo(404);

        // a requisition not yet approved has no purchase order raised on it — said, and it stays as it was
        UUID rq = UUID.randomUUID();
        it.db(() -> jdbc.sql("INSERT INTO expenditure.requisition (id, reference, item, cost_centre, value) VALUES (:id, :r, 'Chalk', 'ZZ', 100)")
                .param("id", rq).param("r", "ZZ-RQ-" + tag).update());
        ResponseEntity<Map> po = it.call(bursar, HttpMethod.POST, "/api/v1/expenditure/requisitions/" + rq + "/po", null);
        assertThat(status(po)).isEqualTo(422);
        assertThat(String.valueOf(po.getBody().get("code"))).isEqualTo("REQUISITION_STATE");
        assertThat(jdbc.sql("SELECT state FROM expenditure.requisition WHERE id = :id").param("id", rq).query(String.class).single()).isEqualTo("RAISED");

        // a closing date that is not a date is refused with its reason, not a server error
        ResponseEntity<Map> vacancy = it.call(hrm, HttpMethod.POST, "/api/v1/hr/vacancies",
                Map.of("title", "ZZ Lecturer " + tag, "department", "ZZ", "requirements", "ZZ", "closesOn", "soon"));
        assertThat(status(vacancy)).isEqualTo(422);
        assertThat(String.valueOf(vacancy.getBody().get("code"))).isEqualTo("HR_VACANCY_CLOSING_DATE");

        // the SIWES practical is a mark out of 60: none, or 99, is refused before anything runs
        String hod = TestTokens.token(person, List.of("hod"));
        String practical = "/api/v1/siwes/offerings/" + nobody + "/students/" + nobody + "/practical";
        assertThat(status(it.call(hod, HttpMethod.PUT, practical, Map.of()))).isEqualTo(400);
        assertThat(status(it.call(hod, HttpMethod.PUT, practical, Map.of("mark", 99)))).isEqualTo(400);

        // a note longer than its record allows is refused, never cut or stored whole
        assertThat(status(it.call(TestTokens.token(person, List.of("ict")), HttpMethod.POST, "/api/v1/notices/campaigns/" + nobody + "/cancel",
                Map.of("reason", "x".repeat(301))))).isEqualTo(400);

        // a student's share link asked for without its days is no server error
        UUID student = it.student("ZZSWEEP" + tag, "C00023", null, null, 100);
        assertThat(status(it.call(TestTokens.token(student, List.of("student")), HttpMethod.POST, "/api/v1/me/documents/" + nobody + "/link", Map.of())))
                .isBetween(400, 499);
    }
}
