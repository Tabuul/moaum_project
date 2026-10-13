package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

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
 * V444 through the API: a campaign's SMS is costed in pages against the balance last read; the send is refused on a known
 * shortfall and goes when the office accepts it. Before the JUPEB and postgraduate application windows close, their drafts are
 * reminded on the addresses their own modules hold, the submitted never.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT,
        properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
class SmsCostAndApplicationDeadlinesIT {

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    ItSupport it;
    String ict;
    String tag;
    String ses;

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
        tag = Integer.toString(new Random().nextInt(900_000) + 100_000);
        ict = TestTokens.token(it.person("ZZSMS-ICT-" + tag, "ZZSMSICT"), List.of("ict"));
        ses = "2093/2094";
        it.session(ses, 2093);
    }

    @SuppressWarnings("unchecked")
    private static Map<String, Object> body(ResponseEntity<Map> r) {
        assertThat(r.getStatusCode().value()).as(String.valueOf(r.getBody())).isEqualTo(200);
        return r.getBody();
    }

    @SuppressWarnings("unchecked")
    @Test
    void aCampaignsSmsIsCostedAndASendBeyondTheBalanceIsAskedFirst() {
        int n = new Random().nextInt(9000) + 1000;
        UUID s = it.student("ITSMS" + n, "C00023", "MOAUM/ADM/93/1" + n + "0", null, 100);
        it.db(() -> {
            jdbc.sql("UPDATE people.student SET entry_session = :ses WHERE id = :s").param("ses", ses).param("s", s).update();
            jdbc.sql("INSERT INTO people.student_contact (student_id, phone, email) VALUES (:s, :p, :e) ON CONFLICT (student_id) DO UPDATE SET phone = EXCLUDED.phone")
                    .param("s", s).param("p", "08031" + n + "00").param("e", "sms-" + n + "@example.test").update();
            return null;
        });
        String sms = "Lectures resume on Monday at eight in the main auditorium. ".repeat(5);
        Map<String, Object> created = body(it.call(ict, HttpMethod.POST, "/api/v1/notices/campaigns", Map.of(
                "name", "IT SMS cost " + tag, "templateKey", "ANNOUNCEMENT", "students", true,
                "filters", Map.of("session", ses, "programme", "C00023"), "channels", List.of("SMS"),
                "vars", Map.of("TITLE", "Resumption", "MESSAGE", "Lectures resume.", "SMS_MESSAGE", sms, "SIGNATURE", "Registry"))));
        String id = String.valueOf(created.get("id"));
        try {
            // a balance too small for the campaign
            it.db(() -> jdbc.sql("UPDATE platform.provider_health SET balance = 1, balance_raw = '1', balance_at = now() WHERE channel = 'SMS'").update());
            Map<String, Object> preview = body(it.call(ict, HttpMethod.POST, "/api/v1/notices/campaigns/" + id + "/preview", Map.of()));
            Map<String, Object> cost = (Map<String, Object>) preview.get("sms");
            assertThat(cost.get("sms_on")).isEqualTo(true);
            assertThat(((Number) cost.get("units_each")).intValue()).isGreaterThanOrEqualTo(2);
            assertThat(((Number) cost.get("recipients")).intValue()).isEqualTo(((Number) preview.get("phoneOk")).intValue());
            assertThat(cost.get("covers")).isEqualTo(false);
            // refused with the figures, then sent when the shortfall is accepted
            ResponseEntity<Map> refused = it.call(ict, HttpMethod.POST, "/api/v1/notices/campaigns/" + id + "/send", Map.of());
            assertThat(refused.getStatusCode().value()).isEqualTo(422);
            assertThat(refused.getBody().get("code")).isEqualTo("CAMPAIGN_SMS_CREDIT");
            assertThat(String.valueOf(refused.getBody().get("detail"))).contains("units");
            assertThat(it.db(() -> jdbc.sql("SELECT state FROM platform.notice_campaign WHERE id = :id::uuid").param("id", id).query(String.class).single())).isEqualTo("DRAFT");
            Map<String, Object> sent = body(it.call(ict, HttpMethod.POST, "/api/v1/notices/campaigns/" + id + "/send", Map.of("acceptShortfall", true)));
            assertThat(sent.get("job")).isNotNull();
        } finally {
            it.db(() -> jdbc.sql("UPDATE platform.provider_health SET balance = NULL, balance_raw = NULL, balance_at = NULL WHERE channel = 'SMS'").update());
            it.call(ict, HttpMethod.POST, "/api/v1/notices/campaigns/" + id + "/cancel", Map.of("reason", "IT"));
        }
    }

    private UUID window(String type, int daysAhead) {
        return it.db(() -> {
            jdbc.sql("UPDATE policy.portal_window SET superseded_at = now() WHERE window_type = :t AND session = :ses AND superseded_at IS NULL").param("t", type).param("ses", ses).update();
            return jdbc.sql("INSERT INTO policy.portal_window (window_type, session, semester, opens_at, closes_at, created_office) VALUES (:t, :ses, NULL, now() - interval '1 day', "
                    + "(((now() AT TIME ZONE 'Africa/Lagos')::date + :d)::timestamp + interval '12 hours') AT TIME ZONE 'Africa/Lagos', 'ict') RETURNING id")
                    .param("t", type).param("ses", ses).param("d", daysAhead).query(UUID.class).single();
        });
    }

    private void drain() {
        for (int i = 0; i < 30; i++) {
            int ran = it.db(() -> jdbc.sql("SELECT count(*) FROM platform.run_notice_job(100000)").query(Integer.class).single());
            if (ran == 0) {
                return;
            }
        }
    }

    private int told(String kind, UUID id, String template) {
        return it.db(() -> jdbc.sql("SELECT count(*) FROM platform.notice WHERE about_kind = :k AND about_id = :id AND template_key = :t")
                .param("k", kind).param("id", id).param("t", template).query(Integer.class).single());
    }

    @Test
    void theJupebAndPostgraduateDraftsAreRemindedBeforeTheirWindowsClose() {
        int n = new Random().nextInt(900_000) + 100_000;
        UUID acc = UUID.randomUUID();
        UUID acc2 = UUID.randomUUID();
        UUID draft = UUID.randomUUID();
        UUID submitted = UUID.randomUUID();
        UUID pgApplicant = UUID.randomUUID();
        UUID pgDraft = UUID.randomUUID();
        it.db(() -> {
            jdbc.sql("INSERT INTO jupeb.account (id, email, password_hash) VALUES (:id, :e, crypt('x', gen_salt('bf', 12))), (:id2, :e2, crypt('x', gen_salt('bf', 12)))")
                    .param("id", acc).param("e", "jupeb-" + n + "@example.test").param("id2", acc2).param("e2", "jupeb2-" + n + "@example.test").update();
            jdbc.sql("""
                    INSERT INTO jupeb.application (id, account_id, session, application_no, surname, first_name, email, phone, state, submitted_at) VALUES
                        (:a, :acc, :s, :na, 'ZZSMSJUPEB', 'Draft', :ea, :pa, 'DRAFT', NULL),
                        (:b, :acc2, :s, :nb, 'ZZSMSJUPEB', 'Submitted', :eb, :pb, 'SUBMITTED', now())
                    """).param("a", draft).param("b", submitted).param("acc", acc).param("acc2", acc2).param("s", ses)
                    .param("na", "IT/JUPEB/" + n + "A").param("nb", "IT/JUPEB/" + n + "B")
                    .param("ea", "jupeb-a-" + n + "@example.test").param("eb", "jupeb-b-" + n + "@example.test")
                    .param("pa", "0805" + n + "1").param("pb", "0805" + n + "2").update();
            jdbc.sql("INSERT INTO admissions.pg_applicant (id, session, surname, other_names, email, phone, password_hash) VALUES (:id, :s, 'ZZSMSPG', 'Draft Applicant', :e, :p, crypt('x', gen_salt('bf', 12)))")
                    .param("id", pgApplicant).param("s", ses).param("e", "pg-" + n + "@example.test").param("p", "0806" + n + "1").update();
            jdbc.sql("INSERT INTO admissions.pg_application (id, applicant_id, session, application_no, programme_code, entry_level, state) VALUES (:id, :ap, :s, :no, 'C00023', 800, 'DRAFT')")
                    .param("id", pgDraft).param("ap", pgApplicant).param("s", ses).param("no", "PG/93/" + n).update();
            return null;
        });
        window("JUPEB_APPLICATION", 3);
        window("POSTGRADUATE_APPLICATION", 1);
        assertThat(((Number) body(it.call(ict, HttpMethod.POST, "/api/v1/notices/closing-reminders/run", Map.of())).get("queued")).intValue()).isGreaterThanOrEqualTo(2);
        drain();
        assertThat(told("jupeb_application", draft, "WINDOW_CLOSING:JUPEB_APPLICATION")).isEqualTo(3);
        assertThat(told("jupeb_application", submitted, "WINDOW_CLOSING:JUPEB_APPLICATION")).isEqualTo(0);
        assertThat(told("pg_application", pgDraft, "WINDOW_CLOSING:POSTGRADUATE_APPLICATION")).isEqualTo(3);
        assertThat(it.db(() -> jdbc.sql("SELECT recipient FROM platform.notice WHERE about_id = :id AND channel = 'EMAIL' AND template_key = 'WINDOW_CLOSING:JUPEB_APPLICATION'")
                .param("id", draft).query(String.class).single())).isEqualTo("jupeb-a-" + n + "@example.test");
        assertThat(it.db(() -> jdbc.sql("SELECT body FROM platform.notice WHERE about_id = :id AND channel = 'SMS' AND template_key = 'WINDOW_CLOSING:POSTGRADUATE_APPLICATION'")
                .param("id", pgDraft).query(String.class).single())).contains("close tomorrow");
        // the same day again: nothing more
        body(it.call(ict, HttpMethod.POST, "/api/v1/notices/closing-reminders/run", Map.of()));
        drain();
        assertThat(told("jupeb_application", draft, "WINDOW_CLOSING:JUPEB_APPLICATION")).isEqualTo(3);
    }
}
