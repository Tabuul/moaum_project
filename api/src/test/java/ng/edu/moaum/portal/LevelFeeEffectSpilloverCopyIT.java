package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.List;
import java.util.Map;
import java.util.Random;
import java.util.UUID;

import ng.edu.moaum.portal.shared.AuditContext;
import ng.edu.moaum.portal.shared.AuditContextHolder;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.HttpMethod;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;

/**
 * V580, end to end: the Bursary works out what correcting every waiting level does to the current session's charges — behind the
 * screens, the level left as it was — and reads it by faculty and programme and student by student; a session's spillover lines
 * are copied from another on their own, previewed first, and the transition's readiness says what its spillover students are
 * charged without holding it; the person who uploaded a contact is told when the student says it is not theirs, and once a week
 * while an upload a month old still waits; the GST pages read after the kept population is worked out. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class LevelFeeEffectSpilloverCopyIT {

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    /** the two invented sessions whose fee lines the test states, taken off again so no later test's student reads them */
    String a, b;

    @AfterEach
    void clean() {
        ItSupport it = new ItSupport(port, jdbc, transactions);
        for (String s : new String[] {a, b}) {
            if (s != null) it.db(() -> jdbc.sql("DELETE FROM finance.fee_schedule WHERE session = :s").param("s", s).update());
        }
    }

    private Map<String, Object> latestWhenSettled(ItSupport it, String token) throws InterruptedException {
        for (int i = 0; i < 300; i++) {
            Map<String, Object> latest = it.get(token, "/api/v1/finance/level-fee-effect").getBody();
            Map<String, Object> run = (Map<String, Object>) latest.get("run");
            if (run == null || !"RUNNING".equals(run.get("state"))) {
                return latest;
            }
            Thread.sleep(1000);
        }
        throw new AssertionError("the fee effect did not finish within five minutes");
    }

    @Test
    void theFeeEffectOfEveryCorrectionSpilloverLinesCopiedAndUploadersTold() throws InterruptedException {
        ItSupport it = new ItSupport(port, jdbc, transactions);
        int n = it.freeDraw(10000, 99999, k -> List.of("ZZLFEA" + k, "ZZ-LFE-BU-" + k, "MOAU/SC/LFE/26/" + k));
        String bursar = TestTokens.token(it.person("ZZ-LFE-BU-" + n, "ZZLFEBU" + n), List.of("bursar"));
        String gst = TestTokens.token(it.person("ZZ-LFE-GS-" + n, "ZZLFEGS" + n), List.of("gst"));
        UUID registrarId = it.person("ZZ-LFE-RG-" + n, "ZZLFERG" + n);
        String uploaderMail = "zzlferg" + n + "@example.com";
        it.db(() -> jdbc.sql("UPDATE iam.person SET email = :e WHERE id = :p").param("e", uploaderMail).param("p", registrarId).update());
        String registrar = TestTokens.token(registrarId, List.of("registrar"));

        // a spillover student at 100 Level whom the engine places at 400
        UUID s = it.student("ZZLFEA" + n, "C00023", "MOAUM/ADM/87/" + (100000 + n), "MOAU/SC/LFE/26/" + n, 100);
        it.db(() -> jdbc.sql("""
                UPDATE people.academic_position SET computed_level = 400, final_level = 400, spillover_years = 1, spillover_state = 'SPILLOVER_YEAR_1'
                 WHERE student_id = :s
                """).param("s", s).update());

        // the fee effect of every waiting correction: started, read behind the screens, nothing changed
        latestWhenSettled(it, bursar);
        assertThat(it.call(gst, HttpMethod.POST, "/api/v1/finance/level-fee-effect", Map.of("bases", List.of("SPILLOVER"))).getStatusCode().value()).isEqualTo(403);
        ResponseEntity<Map> started = it.call(bursar, HttpMethod.POST, "/api/v1/finance/level-fee-effect", Map.of("bases", List.of("SPILLOVER")));
        assertThat(started.getStatusCode().value()).as(String.valueOf(started.getBody())).isEqualTo(200);
        String runId = String.valueOf(started.getBody().get("id"));
        Map<String, Object> latest = latestWhenSettled(it, bursar);
        Map<String, Object> run = (Map<String, Object>) latest.get("run");
        assertThat(run).containsEntry("id", runId).containsEntry("state", "DONE");
        assertThat(((Number) run.get("done")).intValue()).isEqualTo(((Number) run.get("students")).intValue()).isPositive();
        List<Map<String, Object>> report = (List<Map<String, Object>>) latest.get("report");
        assertThat(report).filteredOn(r -> "UNIVERSITY".equals(r.get("scope"))).singleElement()
                .satisfies(u -> assertThat(((Number) u.get("students")).intValue()).isEqualTo(((Number) run.get("students")).intValue()));
        assertThat(report).anySatisfy(r -> assertThat(r).containsEntry("scope", "PROGRAMME").containsEntry("programme_code", "C00023"));
        List<Map<String, Object>> rows = (List<Map<String, Object>>) it.getList(bursar, "/api/v1/finance/level-fee-effect/" + runId + "/rows").getBody();
        assertThat(rows).filteredOn(r -> s.toString().equals(String.valueOf(r.get("student_id")))).singleElement()
                .satisfies(r -> assertThat(r).containsEntry("basis", "SPILLOVER").containsEntry("current_level", 100).containsEntry("new_level", 400));
        assertThat(jdbc.sql("SELECT current_level FROM people.student WHERE id = :x").param("x", s).query(Integer.class).single()).isEqualTo(100);

        // a session's spillover lines copied from another on their own, previewed first
        Random random = new Random();
        int year = 3100 + random.nextInt(85);
        for (int i = 0; i < 50 && jdbc.sql("SELECT EXISTS (SELECT 1 FROM finance.fee_schedule WHERE session IN (:a, :b))")
                .param("a", year + "/" + (year + 1)).param("b", (year + 1) + "/" + (year + 2)).query(Boolean.class).single(); i++) {
            year = 3100 + random.nextInt(85);
        }
        a = year + "/" + (year + 1);
        b = (year + 1) + "/" + (year + 2);
        it.session(a, year);
        it.session(b, year + 1);
        it.db(() -> jdbc.sql("""
                INSERT INTO finance.fee_schedule (session, item, amount, level, programme_code, spillover) VALUES
                    (:a, 'School fees', 100000, NULL, 'C00023', false),
                    (:a, 'Spillover fees', 60000, NULL, 'C00023', true),
                    (:a, 'Spillover fees', 65000, NULL, 'C00024', true),
                    (:b, 'Spillover fees', 70000, NULL, 'C00024', true)
                """).param("a", a).param("b", b).update());
        String copyPath = "/api/v1/finance/sessions/" + b + "/schedule/copy-spillover";
        ResponseEntity<Map> preview = it.get(registrar, copyPath + "?from=" + a);
        assertThat(preview.getStatusCode().value()).as(String.valueOf(preview.getBody())).isEqualTo(200);
        assertThat(preview.getBody()).containsEntry("copy", 1).containsEntry("kept", 1).containsEntry("applied", false);
        assertThat((List<Map>) preview.getBody().get("lines")).allSatisfy(l -> assertThat(l).containsEntry("spillover", true));
        assertThat(it.call(registrar, HttpMethod.POST, copyPath, Map.of("from", a)).getStatusCode().value()).isEqualTo(403);
        ResponseEntity<Map> copied = it.call(bursar, HttpMethod.POST, copyPath, Map.of("from", a));
        assertThat(copied.getStatusCode().value()).as(String.valueOf(copied.getBody())).isEqualTo(200);
        assertThat(copied.getBody()).containsEntry("copy", 1).containsEntry("applied", true);
        assertThat(jdbc.sql("SELECT string_agg(programme_code || ':' || amount::int || ':' || spillover, ',' ORDER BY programme_code) FROM finance.fee_schedule WHERE session = :b AND ended_at IS NULL")
                .param("b", b).query(String.class).single()).isEqualTo("C00023:60000:true,C00024:70000:true");
        assertThat(it.get(registrar, copyPath + "?from=" + a).getBody()).as("copied once").containsEntry("copy", 0).containsEntry("kept", 2);

        // the transition's readiness says what the spillover students are charged, never holding it
        Map<String, Object> line = jdbc.sql("SELECT ok, blocking, detail FROM policy.transition_readiness(:b) WHERE code = 'SPILLOVER_FEE_LINES'").param("b", b)
                .query().singleRow();
        assertThat(line).containsEntry("ok", true).containsEntry("blocking", false);
        assertThat(String.valueOf(line.get("detail"))).contains("2 stated");

        // a contact the student says is not theirs: the uploader told at once
        UUID c = it.student("ZZLFEC" + n, "C00023", "MOAUM/ADM/87/" + (200000 + n), "MOAU/SC/LFF/26/" + n, 200);
        String phone = String.format("0809%07d", n);
        ResponseEntity<Map> up = it.call(registrar, HttpMethod.POST, "/api/v1/student-contacts/upload", Map.of("fileName", "class-list-" + n + ".csv", "rows", List.of(
                Map.of("number", "MOAU/SC/LFF/26/" + n, "phone", phone))));
        assertThat(up.getStatusCode().value()).as(String.valueOf(up.getBody())).isEqualTo(200);
        String student = TestTokens.token(c, List.of("student"));
        assertThat(it.call(student, HttpMethod.POST, "/api/v1/me/contact/not-mine", Map.of("field", "PHONE")).getBody()).containsEntry("outcome", "REFUSED");
        String told = jdbc.sql("""
                SELECT body FROM platform.notice WHERE lower(recipient) = lower(:r) AND template_key = 'CONTACT_UPLOAD_REJECTED' ORDER BY created_at DESC LIMIT 1
                """).param("r", uploaderMail).query(String.class).single();
        assertThat(told).contains(phone).contains("class-list-" + n + ".csv").contains("ZZLFEC" + n);

        // a month on, contacts still waiting: the uploader told once that week
        UUID d = it.student("ZZLFED" + n, "C00023", "MOAUM/ADM/87/" + (300000 + n), "MOAU/SC/LFG/26/" + n, 200);
        ResponseEntity<Map> old = it.call(registrar, HttpMethod.POST, "/api/v1/student-contacts/upload", Map.of("fileName", "old-list-" + n + ".csv", "rows", List.of(
                Map.of("number", "MOAU/SC/LFG/26/" + n, "phone", String.format("0705%07d", n)))));
        assertThat(old.getStatusCode().value()).as(String.valueOf(old.getBody())).isEqualTo(200);
        assertThat(jdbc.sql("SELECT phone_pending FROM people.student_contact WHERE student_id = :d").param("d", d).query(Boolean.class).single()).isTrue();
        it.db(() -> jdbc.sql("UPDATE people.contact_upload SET uploaded_at = now() - interval '31 days' WHERE id = :u")
                .param("u", UUID.fromString(String.valueOf(old.getBody().get("uploadId")))).update());
        String waitingSql = "SELECT count(*) FROM platform.notice WHERE lower(recipient) = lower(:r) AND template_key = 'CONTACT_UPLOAD_WAITING' AND body LIKE :f";
        TransactionTemplate tx = new TransactionTemplate(transactions);
        for (int i = 0; i < 2; i++) {
            AuditContextHolder.with(new AuditContext(new UUID(0, 0), "registrar", "integration test", null, null),
                    () -> tx.execute(st -> jdbc.sql("SELECT people.chase_unconfirmed_contacts(30)").query(Integer.class).single()));
        }
        assertThat(jdbc.sql(waitingSql).param("r", uploaderMail).param("f", "%old-list-" + n + ".csv%").query(Long.class).single()).as("once a week").isEqualTo(1);
        assertThat(jdbc.sql(waitingSql).param("r", uploaderMail).param("f", "%class-list-" + n + ".csv%").query(Long.class).single()).as("nothing waits from it").isZero();

        // the GST pages read once the kept population is worked out, outside their read
        Map<String, Object> fee = it.get(bursar, "/api/v1/gst/fee?refresh=true").getBody();
        assertThat(fee.get("keptAt")).isNotNull();
        assertThat(fee).containsKeys("standing", "rules");
        ResponseEntity<Map> dash = it.get(gst, "/api/v1/gst/GST/dashboard");
        assertThat(dash.getStatusCode().value()).as(String.valueOf(dash.getBody())).isEqualTo(200);
        assertThat(dash.getBody().get("keptAt")).isNotNull();
        assertThat(it.get(bursar, "/api/v1/gst/fee/review").getBody().get("keptAt")).isNotNull();
    }
}
