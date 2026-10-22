package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.math.BigDecimal;
import java.time.OffsetDateTime;
import java.util.List;
import java.util.Map;
import java.util.Random;
import java.util.UUID;

import org.junit.jupiter.api.AfterEach;
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
 * V635 through the student's own door: an expired school-fees reference is regenerated — the payment state says it expired and may
 * be regenerated; another student cannot; the same reference is reopened for another day while the fees it pays are owed, and asked
 * again it is answered as open; once part of the fees is paid against another reference, the expired one is replaced by a new
 * reference for what is owed now; a paid reference is not regenerated. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class PaymentReferenceRenewIT {

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    ItSupport it;
    RestClient open;
    final String registrar = ItSupport.token("registrar");
    final String bursar = ItSupport.token("bursar");
    /** the run's own session: its fee lines apply to every student at the level, so they are taken away after the test */
    String session;

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
        open = RestClient.builder().baseUrl("http://localhost:" + port).defaultStatusHandler(s -> true, (q, r) -> { }).build();
    }

    @AfterEach
    void clean() {
        if (session != null) it.db(() -> jdbc.sql("DELETE FROM finance.fee_schedule WHERE session = :s").param("s", session).update());
    }

    private ResponseEntity<Map> post(String path, Object body) {
        return open.post().uri(path).contentType(MediaType.APPLICATION_JSON).body(body).retrieve().toEntity(Map.class);
    }

    /** a student with an account of their own, signed in: the Registry's first password changed at once */
    private String signedIn(UUID student, String matric) {
        assertThat(it.call(registrar, HttpMethod.PUT, "/api/v1/student-auth/accounts/" + student, Map.of("password", "first password 6350")).getStatusCode().value()).isEqualTo(200);
        String t = String.valueOf(post("/api/v1/student-auth/sign-in", Map.of("matricNo", matric, "password", "first password 6350")).getBody().get("token"));
        assertThat(it.call(t, HttpMethod.POST, "/api/v1/student-auth/change-password", Map.of("current", "first password 6350", "next", "Own-Password-6350")).getStatusCode().value()).isEqualTo(200);
        return t;
    }

    private void expire(String reference) {
        it.db(() -> jdbc.sql("UPDATE finance.payment_reference SET generated_at = now() - interval '26 hours', expires_at = now() - interval '2 hours' WHERE reference = :r")
                .param("r", reference).update());
    }

    private ResponseEntity<Map> renew(String token, String reference) {
        return it.call(token, HttpMethod.POST, "/api/v1/me/fees/references/" + reference + "/renew", Map.of());
    }

    @Test
    void anExpiredSchoolFeesReferenceIsRegeneratedTheSameReferenceWhileOwedAndANewOneForWhatIsOwedNow() {
        int y = it.freeYear(2300, 2900);
        session = y + "/" + (y + 1);
        it.session(session, y);
        int n = 1000 + new Random().nextInt(8999);
        String yy = String.format("%02d", y % 100);
        String matric = "MOAUM/RNW/" + yy + "/" + n;
        String otherMatric = "MOAUM/RNW/" + yy + "/9" + n;
        UUID student = it.student("ZZRENEW" + n, "C00061", "MOAUM/ADM/" + yy + "/47" + n, matric, 100);
        UUID other = it.student("ZZRENEWOTHER" + n, "C00061", "MOAUM/ADM/" + yy + "/46" + n, otherMatric, 100);
        String token = signedIn(student, matric);
        String otherToken = signedIn(other, otherMatric);
        assertThat(it.call(bursar, HttpMethod.POST, "/api/v1/finance/sessions/" + session + "/schedule", Map.of("item", "School fees", "amount", 100000, "level", 100))
                .getStatusCode().value()).isEqualTo(200);

        // a reference for the session's fees, left to expire
        String ref1 = String.valueOf(it.call(token, HttpMethod.POST, "/api/v1/me/fees/references", Map.of("session", session, "amount", 100000)).getBody().get("reference"));
        assertThat(ref1).startsWith("MOAUM-FEE-");
        expire(ref1);
        Map<String, Object> state = it.get(token, "/api/v1/payments/state?reference=" + ref1).getBody();
        assertThat(state).containsEntry("expired", true).containsEntry("renewable", true).containsEntry("confirmed", false);

        // another student cannot regenerate it
        ResponseEntity<Map> others = renew(otherToken, ref1);
        assertThat(others.getStatusCode().value()).isEqualTo(422);
        assertThat(others.getBody().get("code")).isEqualTo("REFERENCE_NOT_FOUND");

        // regenerated: the same reference, payable for another day; asked again, it is open
        ResponseEntity<Map> renewed = renew(token, ref1);
        assertThat(renewed.getStatusCode().value()).as(String.valueOf(renewed.getBody())).isEqualTo(200);
        assertThat(renewed.getBody()).containsEntry("reference", ref1).containsEntry("outcome", "REOPENED");
        assertThat(OffsetDateTime.parse(String.valueOf(renewed.getBody().get("expiresAt")))).isAfter(OffsetDateTime.now().plusHours(23));
        assertThat(it.get(token, "/api/v1/payments/state?reference=" + ref1).getBody()).containsEntry("expired", false);
        assertThat(renew(token, ref1).getBody()).containsEntry("reference", ref1).containsEntry("outcome", "OPEN");

        // expired again, and part of the fees paid since against another reference: the expired one is replaced by a new one for what is owed now
        expire(ref1);
        String ref2 = String.valueOf(it.call(token, HttpMethod.POST, "/api/v1/me/fees/references", Map.of("session", session, "amount", 40000)).getBody().get("reference"));
        ResponseEntity<Map> confirmed = it.call(bursar, HttpMethod.POST, "/api/v1/finance/references/" + ref2 + "/confirm", Map.of("channel", "Bank transfer", "note", "renew test"));
        assertThat(confirmed.getStatusCode().value()).as(String.valueOf(confirmed.getBody())).isEqualTo(200);
        ResponseEntity<Map> replaced = renew(token, ref1);
        assertThat(replaced.getStatusCode().value()).as(String.valueOf(replaced.getBody())).isEqualTo(200);
        assertThat(replaced.getBody()).containsEntry("outcome", "NEW");
        String ref3 = String.valueOf(replaced.getBody().get("reference"));
        assertThat(ref3).isNotEqualTo(ref1).startsWith("MOAUM-FEE-");
        assertThat(new BigDecimal(String.valueOf(replaced.getBody().get("amount")))).isEqualByComparingTo("60000");
        List<Map<String, Object>> refs = (List<Map<String, Object>>) it.get(token, "/api/v1/me/fees?session=" + session).getBody().get("references");
        assertThat(refs).anySatisfy(r -> assertThat(r).containsEntry("reference", ref3));

        // a paid reference is not regenerated
        ResponseEntity<Map> paid = renew(token, ref2);
        assertThat(paid.getStatusCode().value()).isEqualTo(422);
        assertThat(paid.getBody().get("code")).isEqualTo("REFERENCE_PAID");
    }
}
