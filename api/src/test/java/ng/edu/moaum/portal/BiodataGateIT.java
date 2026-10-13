package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.time.OffsetDateTime;
import java.util.Base64;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.ThreadLocalRandom;

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
 * The student biodata completion gate (V423), end to end through the API: OFF, an incomplete student uses the portal as
 * before; only the ICT Director (or an administrator) turns it ON; then that student is refused everywhere — the
 * dashboard's figures, registration, results, the timetable, transcripts, whatever the address — with
 * BIODATA_COMPLETION_REQUIRED, while their record, the biodata, the photograph and the completion stay open; staff are
 * never read by the gate; the ICT Director's list names the student and what is missing; a JAMB or health field cannot
 * be required; an exception (never a CPO's) lets the student through until revoked; completing the fields and giving a
 * first photograph unlocks the portal at once, with no approval, and a second photograph is ICT Support's to give.
 * The gate is turned OFF again whatever happens. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class BiodataGateIT {

    static final String B = "/api/v1/biodata-compliance";
    static final String GATED = "BIODATA_COMPLETION_REQUIRED";

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    static Map<String, Object> m(Object o) { return (Map<String, Object>) o; }
    static List<Map<String, Object>> l(Object o) { return (List<Map<String, Object>>) o; }
    static int status(ResponseEntity<?> r) { return r.getStatusCode().value(); }
    static boolean gated(ResponseEntity<Map> r) { return status(r) == 403 && r.getBody() != null && GATED.equals(r.getBody().get("code")); }

    private void off(ItSupport it) {
        it.db(() -> jdbc.sql("UPDATE people.biodata_gate SET enabled = false, changed_at = now(), reason = 'integration test: back off' WHERE enabled").update());
    }

    @Test
    void anIncompleteStudentReachesOnlyTheBiodataWhileTheGateIsOnAndCompletingItUnlocksThePortal() {
        ItSupport it = new ItSupport(port, jdbc, transactions);
        off(it);
        String run = Integer.toString(ThreadLocalRandom.current().nextInt(100000, 999999));
        String surname = "ZZBIOGATE" + run;
        String programme = jdbc.sql("SELECT code FROM ref.programme WHERE NOT archived ORDER BY code LIMIT 1").query(String.class).single();
        String entry = jdbc.sql("SELECT name FROM policy.academic_session ORDER BY starts_on DESC LIMIT 1").query(String.class).single();
        UUID s = UUID.randomUUID();
        it.db(() -> {
            jdbc.sql("""
                    INSERT INTO people.student (id, admission_no, surname, other_names, sex, programme_code, entry_mode, entry_session,
                                                entry_level, current_level, status, study_mode)
                    VALUES (:id, :adm, :sn, 'Gate', 'F', :p, 'UTME', :e, 100, 100, 'ADMITTED', 'FULL_TIME')
                    """).param("id", s).param("adm", String.format("MOAUM/ADM/38/%06d", ThreadLocalRandom.current().nextInt(1, 999999)))
                    .param("sn", surname).param("p", programme).param("e", entry).update();
            jdbc.sql("INSERT INTO people.student_contact (student_id, phone, email) VALUES (:id, '08000000423', 'zzbiogate@example.test')").param("id", s).update();
            return null;
        });
        String student = TestTokens.token(s, List.of("student"));
        String ict = ItSupport.token("ict");
        String registrar = ItSupport.token("registrar");
        String bursar = ItSupport.token("bursar");
        String cpo = ItSupport.token("cpo");

        // OFF: the incomplete student uses the portal as before
        assertThat(gated(it.get(student, "/api/v1/me/fees"))).isFalse();
        assertThat(it.get(student, "/api/v1/me/biodata/completion").getBody().get("gate")).isEqualTo("OFF");
        // only the ICT Director or an administrator turns it on
        assertThat(status(it.call(bursar, HttpMethod.PUT, B + "/gate", Map.of("enabled", true)))).isEqualTo(403);
        try {
            ResponseEntity<Map> on = it.call(ict, HttpMethod.PUT, B + "/gate", Map.of("enabled", true, "reason", "integration test go-live"));
            assertThat(status(on)).as(String.valueOf(on.getBody())).isEqualTo(200);
            assertThat(on.getBody().get("enabled")).isEqualTo(true);

            // ON: refused everywhere but what completing the biodata needs, whatever the address
            for (String path : List.of("/api/v1/me/fees", "/api/v1/me/registration", "/api/v1/me/results", "/api/v1/me/timetable",
                    "/api/v1/me/transcripts", "/api/v1/me/gst", "/api/v1/me/id-card")) {
                assertThat(gated(it.get(student, path))).as(path).isTrue();
            }
            assertThat(gated(it.call(student, HttpMethod.POST, "/api/v1/me/fees/references", Map.of()))).isTrue();
            ResponseEntity<Map> me = it.get(student, "/api/v1/me");
            assertThat(status(me)).isEqualTo(200);
            assertThat(me.getHeaders().getFirst("X-Biodata-Gate")).isEqualTo("REQUIRED");
            assertThat(status(it.get(student, "/api/v1/me/biodata"))).isEqualTo(200);
            Map<String, Object> c = it.get(student, "/api/v1/me/biodata/completion").getBody();
            assertThat(c.get("gate")).isEqualTo("REQUIRED");
            assertThat(l(m(c.get("completion")).get("missing")).stream().map(x -> x.get("item")).toList())
                    .contains("PASSPORT", "kin_mobile").doesNotContain("mobile", "personal_email");   // the contact counts

            // staff are never read by the gate
            assertThat(it.get(registrar, "/api/v1/iam/me").getHeaders().getFirst("X-Biodata-Gate")).isNull();
            assertThat(status(it.get(registrar, B))).isEqualTo(200);
            // V434: the one compliance screen — the reading taken, the student listed by the item they miss
            assertThat(status(it.call(ict, HttpMethod.POST, "/api/v1/biodata/compliance/refresh", Map.of()))).isEqualTo(200);
            Map<String, Object> list = it.get(ict, "/api/v1/biodata/compliance/students?status=INCOMPLETE&missing=PASSPORT&q=" + surname).getBody();
            assertThat(((Number) list.get("total")).intValue()).isEqualTo(1);
            assertThat(String.valueOf(l(list.get("rows")).getFirst().get("missing_labels"))).contains("Passport photograph");
            assertThat(((Number) it.get(ict, "/api/v1/biodata/compliance/students?status=INCOMPLETE&missing=PASSPORT&sex=M&q=" + surname).getBody().get("total")).intValue()).isZero();
            assertThat(l(it.get(ict, "/api/v1/biodata/compliance").getBody().get("items"))).anyMatch(x -> "PASSPORT".equals(x.get("item")));
            // V427: what requiring each item would do, counted over the register — the student lacks the next of kin's phone
            List<Map> impact = it.getList(ict, B + "/requirements/impact").getBody();
            assertThat(impact).anyMatch(x -> "kin_mobile".equals(x.get("item")) && ((Number) x.get("missing")).intValue() >= 1
                    && ((Number) x.get("students")).intValue() >= 1);
            // a health field is never required
            ResponseEntity<Map> health = it.call(ict, HttpMethod.PUT, B + "/requirements/genotype", Map.of("required", true));
            assertThat(status(health)).isEqualTo(422);
            assertThat(health.getBody().get("code")).isEqualTo("BIO_REQ_HEALTH");

            // an exception lets the student through until revoked; a CPO cannot grant one
            Map<String, Object> ex = Map.of("student", s.toString(), "reason", "integration test: an examination tomorrow",
                    "expiresAt", OffsetDateTime.now().plusDays(2).toString());
            assertThat(status(it.call(cpo, HttpMethod.POST, B + "/exceptions", ex))).isEqualTo(403);
            ResponseEntity<Map> granted = it.call(ict, HttpMethod.POST, B + "/exceptions", ex);
            assertThat(status(granted)).as(String.valueOf(granted.getBody())).isEqualTo(200);
            assertThat(gated(it.get(student, "/api/v1/me/fees"))).isFalse();
            assertThat(status(it.call(ict, HttpMethod.POST, B + "/exceptions/" + granted.getBody().get("id") + "/revoke", Map.of("reason", "integration test")))).isEqualTo(200);
            assertThat(gated(it.get(student, "/api/v1/me/fees"))).isTrue();

            // the student completes the fields: still held while the photograph is missing
            for (String[] fv : new String[][] {{"nationality", "Nigeria"}, {"home_address", "No 1, Integration Street, Makurdi"}, {"state_of_origin", "Benue"},
                    {"lga", "Makurdi"}, {"kin_name", "Integration Kin"}, {"kin_relationship", "Mother"}, {"kin_mobile", "08000000424"}}) {
                ResponseEntity<Map> w = it.call(student, HttpMethod.PUT, "/api/v1/me/biodata/" + fv[0], Map.of("value", fv[1]));
                assertThat(status(w)).as(fv[0] + " " + w.getBody()).isEqualTo(200);
            }
            assertThat(gated(it.get(student, "/api/v1/me/results"))).isTrue();
            assertThat(l(m(it.get(student, "/api/v1/me/biodata/completion").getBody().get("completion")).get("missing")).stream().map(x -> x.get("item")).toList())
                    .containsExactly("PASSPORT");
            // a first photograph unlocks the portal at once; a second is ICT Support's to give
            String jpeg = "data:image/jpeg;base64," + Base64.getEncoder().encodeToString(new byte[] {(byte) 0xFF, (byte) 0xD8, (byte) 0xFF, (byte) 0xE0, 0, 0x10, (byte) 0xFF, (byte) 0xD9});
            ResponseEntity<Map> photo = it.call(student, HttpMethod.PUT, "/api/v1/me/passport", Map.of("dataUrl", jpeg));
            assertThat(status(photo)).as(String.valueOf(photo.getBody())).isEqualTo(200);
            ResponseEntity<Map> again = it.call(student, HttpMethod.PUT, "/api/v1/me/passport", Map.of("dataUrl", jpeg));
            assertThat(status(again)).isEqualTo(422);
            assertThat(again.getBody().get("code")).isEqualTo("PHOTO_ON_RECORD");
            assertThat(gated(it.get(student, "/api/v1/me/results"))).isFalse();
            assertThat(it.get(student, "/api/v1/me/biodata/completion").getBody().get("gate")).isEqualTo("COMPLETE");
            // the history keeps who turned the gate on
            Map<String, Object> overview = it.get(ict, B).getBody();
            assertThat(l(overview.get("history")).stream().anyMatch(h -> "true".equals(h.get("now_enabled")))).isTrue();
        } finally {
            off(it);
        }
        // OFF again: nothing is refused
        assertThat(it.get(student, "/api/v1/me/biodata/completion").getBody().get("gate")).isEqualTo("OFF");
    }
}
