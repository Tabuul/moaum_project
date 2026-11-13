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
 * V749, the University's brief of 12 November 2026 ("UPDATE YOUR BLOOD GROUP INFORMATION"), end to end: a student whose blood group
 * is missing is asked on the first screen (iam/me) until it is confirmed; a value that is not one of the eight, or without the
 * confirmation ticked, is refused and nothing is saved; the student's own is saved with the time, the confirmation and an event, and
 * no other student's can be reached; a value written as free text on the biodata form is kept as the card reads it but is not
 * confirmed, and words the card cannot print are refused there too; the card desk's entry counts as confirmed; the identity card
 * waits on the confirmed blood group, then prints. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class StudentBloodGroupIT {

    static final String WAITS = "Blood group not yet confirmed — the student confirms it on their dashboard, or the card desk records it";

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    ItSupport it;
    final String security = ItSupport.token("security");

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
    }

    private Map<String, Object> eligibility(UUID student) {
        return it.get(security, "/api/v1/credentials/identity-cards/students/" + student + "/eligibility").getBody();
    }

    private Map<String, Object> put(String token, Object bloodGroup, Object confirmed) {
        Map<String, Object> body = new java.util.HashMap<>();
        body.put("bloodGroup", bloodGroup);
        body.put("confirmed", confirmed);
        return it.call(token, HttpMethod.PUT, "/api/v1/me/blood-group", body).getBody();
    }

    @Test
    void aStudentConfirmsTheirOwnBloodGroupAndTheCardWaitsOnIt() {
        String tag = it.freeSurname("ZZBLD");
        UUID a = it.student(tag, "C00023", it.freeNumber("MOAUM/ADM/26/", 6), it.freeNumber("MOAUM/BLD/26/", 5), 200);
        UUID b = it.student(tag + "B", "C00023", it.freeNumber("MOAUM/ADM/26/", 6), it.freeNumber("MOAUM/BLD/26/", 5), 200);
        it.db(() -> jdbc.sql("INSERT INTO people.student_photo (student_id, content, content_type, bytes, replaced_at, reason) VALUES (:s, :c, 'image/jpeg', 4, now(), 'integration test') ON CONFLICT (student_id) DO NOTHING")
                .param("s", a).param("c", new byte[] {(byte) 0xFF, (byte) 0xD8, (byte) 0xFF, (byte) 0xD9}).update());
        String studentA = TestTokens.token(a, List.of("student"));
        String studentB = TestTokens.token(b, List.of("student"));

        // asked on the first screen while the blood group is missing; the card waits on it
        assertThat(it.get(studentA, "/api/v1/iam/me").getBody()).containsKey("bloodGroupPrompt");
        assertThat(it.get(studentA, "/api/v1/me/blood-group").getBody()).containsEntry("confirmed", false);
        Map<String, Object> before = eligibility(a);
        assertThat(before).containsEntry("eligible", false);
        assertThat((List<String>) before.get("reasons")).contains(WAITS);
        assertThat((Map<String, Object>) before.get("checks")).containsEntry("blood_group", false);
        assertThat(it.call(security, HttpMethod.POST, "/api/v1/credentials/identity-cards/students/" + a + "/print", Map.of()).getBody())
                .containsEntry("code", "ID_CARD_NOT_ELIGIBLE");

        // refused, and nothing saved: not one of the eight exactly (the common spellings are the desk's), not ticked, nothing chosen
        assertThat(put(studentA, "O positive", true)).containsEntry("code", "IDENTITY_BLOOD_GROUP");
        assertThat(put(studentA, "Z+", true)).containsEntry("code", "IDENTITY_BLOOD_GROUP");
        assertThat(put(studentA, null, true)).containsEntry("code", "IDENTITY_BLOOD_GROUP");
        assertThat(put(studentA, "O+", false)).containsEntry("code", "IDENTITY_BLOOD_UNCONFIRMED");
        assertThat(put(studentA, "O+", null)).containsEntry("code", "IDENTITY_BLOOD_UNCONFIRMED");
        assertThat(jdbc.sql("SELECT count(*) FROM credentials.blood_group_event WHERE holder_id = :s").param("s", a).query(Long.class).single()).isZero();
        assertThat(jdbc.sql("SELECT count(*) FROM people.biodata WHERE student_id = :s AND field = 'blood_group'").param("s", a).query(Long.class).single()).isZero();

        // no other student's is reached: the student's door takes no id, the desk's and the staff's are not the student's
        assertThat(it.call(studentA, HttpMethod.PUT, "/api/v1/credentials/identity-cards/students/" + b + "/blood-group", Map.of("bloodGroup", "O+"))
                .getStatusCode().value()).isEqualTo(403);
        assertThat(it.call(studentA, HttpMethod.PUT, "/api/v1/staff/identity/blood-group", Map.of("bloodGroup", "O+", "confirmed", true))
                .getStatusCode().value()).isEqualTo(403);
        assertThat(it.call(ItSupport.token("registrar"), HttpMethod.PUT, "/api/v1/me/blood-group", Map.of("bloodGroup", "O+", "confirmed", true))
                .getStatusCode().value()).isEqualTo(403);

        // saved and confirmed: the student's own, with the time, the confirmation and an event
        ResponseEntity<Map> saved = it.call(studentA, HttpMethod.PUT, "/api/v1/me/blood-group", Map.of("bloodGroup", " ab- ", "confirmed", true));
        assertThat(saved.getStatusCode().value()).as(String.valueOf(saved.getBody())).isEqualTo(200);
        assertThat(saved.getBody()).containsEntry("bloodGroup", "AB-").containsEntry("kind", "STUDENT").containsEntry("confirmed", true).containsKey("confirmedAt");
        assertThat(it.get(studentA, "/api/v1/me/blood-group").getBody()).containsEntry("bloodGroup", "AB-").containsEntry("confirmed", true)
                .containsEntry("source", "SELF");
        assertThat(it.get(studentA, "/api/v1/iam/me").getBody()).doesNotContainKey("bloodGroupPrompt");
        assertThat(jdbc.sql("SELECT value FROM people.biodata WHERE student_id = :s AND field = 'blood_group'").param("s", a).query(String.class).single()).isEqualTo("AB-");
        Map<String, Object> event = jdbc.sql("SELECT kind, holder_number, previous_value, new_value, confirmed, source, office, by FROM credentials.blood_group_event WHERE holder_id = :s")
                .param("s", a).query().singleRow();
        assertThat(event).containsEntry("kind", "STUDENT").containsEntry("new_value", "AB-").containsEntry("confirmed", true).containsEntry("source", "SELF")
                .containsEntry("office", "student").containsEntry("by", a);
        assertThat(event.get("previous_value")).isNull();
        assertThat(jdbc.sql("SELECT count(*) FROM audit.entries WHERE subject_type = 'credentials.blood_group_confirmation' AND actor_id = :s").param("s", a)
                .query(Long.class).single()).isPositive();
        assertThat(jdbc.sql("SELECT blood_group FROM credentials.blood_group_confirmation WHERE kind = 'STUDENT' AND holder_id = :s").param("s", b)
                .query(String.class).optional()).isEmpty();

        // the card no longer waits on it, and prints
        Map<String, Object> after = eligibility(a);
        assertThat(after).as(String.valueOf(after)).containsEntry("eligible", true).containsEntry("bloodGroup", "AB-");
        assertThat((Map<String, Object>) after.get("checks")).containsEntry("blood_group", true);
        ResponseEntity<Map> printed = it.call(security, HttpMethod.POST, "/api/v1/credentials/identity-cards/students/" + a + "/print", Map.of());
        assertThat(printed.getStatusCode().value()).as(String.valueOf(printed.getBody())).isEqualTo(200);
        assertThat(printed.getBody()).containsEntry("state", "PRINTED");
        assertThat(it.get(security, "/api/v1/credentials/identity-cards/students/" + a + "/card").getBody()).containsEntry("blood_group", "AB-");

        // free text on the biodata form: kept as the card reads it, not confirmed — the student is asked again, the card waits again
        ResponseEntity<Map> typed = it.call(studentB, HttpMethod.PUT, "/api/v1/me/biodata/blood_group", Map.of("value", "o positive"));
        assertThat(typed.getStatusCode().value()).as(String.valueOf(typed.getBody())).isEqualTo(200);
        assertThat(typed.getBody()).containsEntry("value", "O+");
        assertThat(it.get(studentB, "/api/v1/me/blood-group").getBody()).containsEntry("bloodGroup", "O+").containsEntry("confirmed", false);
        assertThat((Map<String, Object>) it.get(studentB, "/api/v1/iam/me").getBody().get("bloodGroupPrompt")).containsEntry("current", "O+");
        assertThat((List<String>) eligibility(b).get("reasons")).contains(WAITS);
        assertThat(it.call(studentB, HttpMethod.PUT, "/api/v1/me/biodata/blood_group", Map.of("value", "type O, I think")).getBody())
                .containsEntry("code", "STU_BLOOD_GROUP");
        // a change of the free text after confirming is not confirmed either
        assertThat(it.call(studentA, HttpMethod.PUT, "/api/v1/me/biodata/blood_group", Map.of("value", "B+")).getStatusCode().value()).isEqualTo(200);
        assertThat(it.get(studentA, "/api/v1/me/blood-group").getBody()).containsEntry("bloodGroup", "B+").containsEntry("confirmed", false);
        assertThat((Map<String, Object>) it.get(studentA, "/api/v1/iam/me").getBody().get("bloodGroupPrompt")).containsEntry("current", "B+");
        assertThat(put(studentA, "B+", true)).containsEntry("bloodGroup", "B+").containsEntry("previous", "B+");
        assertThat(it.get(studentA, "/api/v1/iam/me").getBody()).doesNotContainKey("bloodGroupPrompt");

        // the card desk's entry counts as confirmed (the University's decision): the student is no longer asked, the card no longer waits
        ResponseEntity<Map> desk = it.call(security, HttpMethod.PUT, "/api/v1/credentials/identity-cards/students/" + b + "/blood-group", Map.of("bloodGroup", "O+"));
        assertThat(desk.getStatusCode().value()).as(String.valueOf(desk.getBody())).isEqualTo(200);
        assertThat(it.get(studentB, "/api/v1/me/blood-group").getBody()).containsEntry("confirmed", true).containsEntry("source", "DESK");
        assertThat(it.get(studentB, "/api/v1/iam/me").getBody()).doesNotContainKey("bloodGroupPrompt");
        assertThat((List<String>) eligibility(b).get("reasons")).doesNotContain(WAITS);
        assertThat(jdbc.sql("SELECT source || ':' || previous_value || ':' || new_value FROM credentials.blood_group_event WHERE holder_id = :s").param("s", b)
                .query(String.class).single()).isEqualTo("DESK:O+:O+");
    }
}
