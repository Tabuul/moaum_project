package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.List;
import java.util.Map;
import java.util.Random;
import java.util.UUID;

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
 * V599: a contact the sign-in help saved to a student record that held none (V596) reaches no notice until it is confirmed; the
 * desk lists it with its request, refuses it (emptied, kept as DESK_REFUSED) or confirms it (then notices reach it); anyone else
 * writing another value clears the sign-in mark. The student numbers checked on the sign-in page from a connection on a network are
 * logged, refused past the day's figure (429) and told to the Head of the desk at the alert figure; a check from the machine itself
 * is neither. The request is made as the sign-in help makes it (helpdesk.submit_public, people.contact_from_sign_in), not through
 * the public door, whose limit of five requests a connection every test in the run shares. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class SignInContactsIT {

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    private static final String BASE = "/api/v1/helpdesk/support/sign-in-contacts";

    /** the Head of the ICT Support Desk: a person in the office, with an e-mail, so the alert reaches someone */
    private String head(ItSupport it) {
        UUID p = it.person("MOAUM/IT/SIC01", "ZZSICHEAD");
        it.db(() -> {
            jdbc.sql("UPDATE iam.person SET email = 'zz-sic-head@example.edu' WHERE id = :p").param("p", p).update();
            return jdbc.sql("""
                    INSERT INTO iam.office_assignment (id, person_id, office_code, scope_kind, instrument, granted_by, valid_from)
                    SELECT gen_random_uuid(), :p, 'helpdeskhead', 'platform', 'integration test', :p, current_date
                     WHERE NOT EXISTS (SELECT 1 FROM iam.office_assignment a WHERE a.person_id = :p AND a.office_code = 'helpdeskhead'
                                         AND (a.valid_to IS NULL OR a.valid_to >= current_date))
                    """).param("p", p).update();
        });
        return TestTokens.token(p, List.of("helpdeskhead"));
    }

    /** a check of a student number on the sign-in page, from the address given (a connection on a network) or from the machine */
    private ResponseEntity<Map> check(String from, String number) {
        RestClient.RequestBodySpec spec = RestClient.builder().baseUrl("http://localhost:" + port).defaultStatusHandler(st -> true, (q, r) -> { }).build()
                .post().uri("/api/v1/helpdesk/sign-in-help/check").contentType(MediaType.APPLICATION_JSON);
        if (from != null) spec = spec.header("X-Forwarded-For", from);
        return spec.body(Map.of("accountType", "Student portal", "number", number)).retrieve().toEntity(Map.class);
    }

    private Map<String, Object> rowOf(List<Map<String, Object>> rows, UUID student, String field) {
        return rows.stream().filter(r -> student.toString().equals(String.valueOf(r.get("student_id"))) && field.equals(r.get("field"))).findFirst().orElse(null);
    }

    @Test
    void aContactTheSignInHelpSavedReachesNoNoticeUntilConfirmedAndTheDeskConfirmsOrRefusesIt() {
        ItSupport it = new ItSupport(port, jdbc, transactions);
        String head = head(it);
        String matric = it.freeNumber("MOAU/ZZ/SIC/26/", 5);
        UUID s = it.student(it.freeSurname("ZZSICONTACT"), "C00023", null, matric, 200);
        String email = "zz-sic-" + UUID.randomUUID().toString().substring(0, 8) + "@example.edu";
        it.db(() -> jdbc.sql("DELETE FROM people.student_contact WHERE student_id = :s").param("s", s).update());

        // the request as the sign-in help makes it, and the contact it saves to a record that holds none
        Map<String, Object> made = it.db(() -> {
            UUID t = jdbc.sql("SELECT helpdesk.submit_public(:n, :e, :p, CAST(:d AS jsonb), NULL)")
                    .param("n", "Zzsic Asker").param("e", email).param("p", "08035550199")
                    .param("d", "{\"account_type\": \"Student portal\", \"username\": \"" + matric + "\"}").query(UUID.class).single();
            String saved = jdbc.sql("SELECT people.contact_from_sign_in(:s, :e, :p, :t)").param("s", s).param("e", email).param("p", "+234 803 555 0199").param("t", t)
                    .query(String.class).single();
            return Map.of("ticket", t, "saved", saved, "number", jdbc.sql("SELECT number FROM helpdesk.ticket WHERE id = :t").param("t", t).query(String.class).single());
        });
        UUID ticket = (UUID) made.get("ticket");
        assertThat(made.get("saved")).isEqualTo("EMAIL,PHONE");
        assertThat(jdbc.sql("SELECT email || ':' || email_pending || ':' || email_from_sign_in || ':' || (email_sign_in_ticket = :t) || '|' || phone || ':' || phone_from_sign_in FROM people.student_contact WHERE student_id = :s")
                .param("s", s).param("t", ticket).query(String.class).single()).isEqualTo(email + ":true:true:true|08035550199:true");
        // no notice reaches it, and no reset link (V575): every notice reads people.student_reach
        assertThat(jdbc.sql("SELECT coalesce(email, '-') || '|' || coalesce(phone, '-') FROM people.student_reach(:s)").param("s", s).query(String.class).single()).isEqualTo("-|-");
        assertThat(jdbc.sql("SELECT unconfirmed_email FROM people.student_reset_reach(:s)").param("s", s).query(String.class).single()).isEqualTo(email);

        // the desk's list, with the request and who asked; the support profile says where the contact came from
        List<Map<String, Object>> rows = (List<Map<String, Object>>) it.get(head, BASE).getBody().get("rows");
        Map<String, Object> e = rowOf(rows, s, "EMAIL");
        assertThat(e).isNotNull().containsEntry("value", email).containsEntry("ticket_number", made.get("number")).containsEntry("asked_by", "Zzsic Asker");
        assertThat(rowOf(rows, s, "PHONE")).isNotNull().containsEntry("value", "08035550199");
        Map<String, Object> contact = (Map<String, Object>) it.get(head, "/api/v1/helpdesk/support/students/" + s).getBody().get("contact");
        assertThat(contact).containsEntry("email_from_sign_in", true).containsEntry("email_sign_in_ticket", made.get("number")).containsEntry("email_pending", true);

        // refused at the desk: the field emptied, the outcome kept with the request; refused again, there is nothing to refuse
        ResponseEntity<Map> refused = it.call(head, HttpMethod.POST, "/api/v1/helpdesk/support/students/" + s + "/contact/refuse",
                Map.of("field", "EMAIL", "reason", "The student came in person: the address is not theirs"));
        assertThat(refused.getStatusCode().value()).as(String.valueOf(refused.getBody())).isEqualTo(200);
        assertThat(jdbc.sql("SELECT email IS NULL AND NOT email_pending AND NOT email_from_sign_in AND email_sign_in_ticket IS NULL FROM people.student_contact WHERE student_id = :s")
                .param("s", s).query(Boolean.class).single()).isTrue();
        assertThat(jdbc.sql("SELECT outcome || ':' || (sign_in_ticket = :t) || ':' || value FROM people.contact_confirmation WHERE student_id = :s AND field = 'EMAIL' ORDER BY created_at DESC LIMIT 1")
                .param("s", s).param("t", ticket).query(String.class).single()).isEqualTo("DESK_REFUSED:true:" + email);
        assertThat(it.call(head, HttpMethod.POST, "/api/v1/helpdesk/support/students/" + s + "/contact/refuse",
                Map.of("field", "EMAIL", "reason", "The student came in person: the address is not theirs")).getBody()).containsEntry("code", "CONTACT_NOT_PENDING");

        // confirmed at the desk: notices reach it now
        ResponseEntity<Map> confirmed = it.call(head, HttpMethod.POST, "/api/v1/helpdesk/support/students/" + s + "/contact/confirm",
                Map.of("field", "PHONE", "reason", "Called the number with the student at the desk"));
        assertThat(confirmed.getStatusCode().value()).as(String.valueOf(confirmed.getBody())).isEqualTo(200);
        assertThat(jdbc.sql("SELECT phone FROM people.student_reach(:s)").param("s", s).query(String.class).single()).isEqualTo("08035550199");
        assertThat(jdbc.sql("SELECT outcome || ':' || (sign_in_ticket = :t) FROM people.contact_confirmation WHERE student_id = :s AND field = 'PHONE' ORDER BY created_at DESC LIMIT 1")
                .param("s", s).param("t", ticket).query(String.class).single()).isEqualTo("DESK:true");
        rows = (List<Map<String, Object>>) it.get(head, BASE).getBody().get("rows");
        assertThat(rowOf(rows, s, "EMAIL")).isNull();
        assertThat(rowOf(rows, s, "PHONE")).isNull();

        // saved again from the sign-in page, then the student's own e-mail written over it: no longer the sign-in help's, and reached
        it.db(() -> jdbc.sql("SELECT people.contact_from_sign_in(:s, :e, NULL, :t)").param("s", s).param("e", "x" + email).param("t", ticket).query(String.class).single());
        assertThat(jdbc.sql("SELECT email FROM people.student_reach(:s)").param("s", s).query(String.class).optional().orElse(null)).isNull();
        String own = "own-" + email;
        it.db(() -> jdbc.sql("UPDATE people.student_contact SET email = :e WHERE student_id = :s").param("e", own).param("s", s).update());
        assertThat(jdbc.sql("SELECT (NOT email_pending AND NOT email_from_sign_in AND email_sign_in_ticket IS NULL) FROM people.student_contact WHERE student_id = :s")
                .param("s", s).query(Boolean.class).single()).isTrue();
        assertThat(jdbc.sql("SELECT email FROM people.student_reach(:s)").param("s", s).query(String.class).single()).isEqualTo(own);
    }

    @Test
    void numberChecksFromAConnectionAreLoggedCappedADayAndToldToTheHead() {
        ItSupport it = new ItSupport(port, jdbc, transactions);
        String head = head(it);
        Map<String, Object> before = it.get(head, BASE + "/lookups").getBody();
        Random r = new Random();
        String from = "10." + r.nextInt(250) + "." + r.nextInt(250) + "." + (1 + r.nextInt(250));
        String matric = it.freeNumber("MOAU/ZZ/SIL/26/", 5);
        it.student(it.freeSurname("ZZSILOOKUP"), "C00023", null, matric, 200);
        try {
            // the figures are a Head's: a figure out of range refused, an agent refused the day's checks
            assertThat(it.call(head, HttpMethod.PUT, BASE + "/lookups/figures", Map.of("daily", 0)).getBody()).containsEntry("code", "SIGN_IN_LOOKUP_DAILY");
            assertThat(it.get(ItSupport.token("ictagent"), BASE + "/lookups").getStatusCode().value()).isEqualTo(403);
            ResponseEntity<Map> set = it.call(head, HttpMethod.PUT, BASE + "/lookups/figures", Map.of("daily", 3, "alert", 2));
            assertThat(set.getStatusCode().value()).as(String.valueOf(set.getBody())).isEqualTo(200);
            assertThat(set.getBody()).containsEntry("daily", 3).containsEntry("alert", 2);

            // three checks from the connection — a student's number (named) and two no student holds — then the day's figure is reached
            assertThat(check(from, matric).getBody()).containsEntry("found", true).containsKey("name");
            assertThat(check(from, it.freeNumber("MOAU/ZZ/SIL/26/", 5)).getBody()).containsEntry("found", false);
            assertThat(check(from, it.freeNumber("MOAU/ZZ/SIL/26/", 5)).getBody()).containsEntry("found", false);
            ResponseEntity<Map> refused = check(from, matric);
            assertThat(refused.getStatusCode().value()).as(String.valueOf(refused.getBody())).isEqualTo(429);
            assertThat(refused.getBody()).containsEntry("code", "HELPDESK_CHECK_DAY_LIMIT");
            assertThat(refused.getHeaders().getFirst("Retry-After")).isNotBlank();
            // the machine itself is neither logged nor capped
            long local = jdbc.sql("SELECT count(*) FROM helpdesk.sign_in_lookup WHERE source IN ('127.0.0.1', '0:0:0:0:0:0:0:1', '::1')").query(Long.class).single();
            assertThat(check(null, matric).getBody()).containsEntry("found", true);
            assertThat(jdbc.sql("SELECT count(*) FROM helpdesk.sign_in_lookup WHERE source IN ('127.0.0.1', '0:0:0:0:0:0:0:1', '::1')").query(Long.class).single()).isEqualTo(local);

            // logged, and the Head told once the connection's different numbers reached the alert figure
            assertThat(jdbc.sql("SELECT count(*) || ':' || count(*) FILTER (WHERE found) FROM helpdesk.sign_in_lookup WHERE source = :f").param("f", from)
                    .query(String.class).single()).isEqualTo("3:1");
            List<Map<String, Object>> rows = (List<Map<String, Object>>) it.get(head, BASE + "/lookups").getBody().get("rows");
            Map<String, Object> mine = rows.stream().filter(x -> from.equals(x.get("source"))).findFirst().orElseThrow();
            assertThat(((Number) mine.get("checks")).intValue()).isEqualTo(3);
            assertThat(((Number) mine.get("numbers")).intValue()).isEqualTo(3);
            assertThat(((Number) mine.get("found")).intValue()).isEqualTo(1);
            assertThat(mine).containsEntry("told", true).containsEntry("refused", true);
            assertThat(jdbc.sql("SELECT count(*) FROM platform.notice WHERE event_key LIKE 'sign-in-lookups:' || :f || ':%'").param("f", from).query(Long.class).single())
                    .isGreaterThanOrEqualTo(1L);
        } finally {
            Map<String, Object> back = new java.util.HashMap<>();
            back.put("daily", before.get("daily"));
            back.put("alert", before.get("alert"));
            it.call(head, HttpMethod.PUT, BASE + "/lookups/figures", back);
        }
    }
}
