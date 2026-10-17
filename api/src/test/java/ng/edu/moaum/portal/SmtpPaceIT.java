package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.List;
import java.util.Map;
import java.util.UUID;

import ng.edu.moaum.portal.platform.NoticeRepository;

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
 * V532: e-mail over SMTP at the mail provider's pace — the Directorate of ICT sets a minute's and a day's most (Microsoft 365's 30
 * and 10,000 by default; within range, or empty for none), another office does not; the batch takes no more e-mail than the pace
 * allows; a message held by the account's failure keeps its attempts; the notices screen names the pace; and the Mail server
 * screen's test says how far it got (a server that cannot be reached is CONNECTION) — for ICT only, to a real address. Needs
 * DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class SmtpPaceIT {

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;
    @Autowired
    NoticeRepository notices;

    @Test
    void emailOverSmtpGoesAtThePaceIctSets() {
        ItSupport it = new ItSupport(port, jdbc, transactions);
        String ict = TestTokens.token(it.person(it.freeNumber("ZZ-PACE-", 6), "ZZPACEICT"), List.of("ict"));
        String registrar = ItSupport.token("registrar");
        Map before = jdbc.sql("SELECT smtp_per_minute, smtp_per_day FROM platform.notice_setting WHERE id").query().singleRow();
        UUID queued = it.db(() -> jdbc.sql("SELECT platform.queue_notice('EMAIL', 'zz.pace.it@example.test', 'ZZ pace', 'body', NULL, NULL)").query(UUID.class).single());
        try {
            // set by ICT, within range; never by another office
            Map<String, Object> pace = Map.of("perMinute", 20, "perDay", 5000);
            assertThat(it.call(registrar, HttpMethod.PUT, "/api/v1/platform/notices/smtp-pace", pace).getStatusCode().value()).isEqualTo(403);
            assertThat(it.call(ict, HttpMethod.PUT, "/api/v1/platform/notices/smtp-pace", Map.of("perMinute", 0, "perDay", 5000)).getBody())
                    .containsEntry("code", "NOTICE_PACE_RANGE");
            ResponseEntity<Map> set = it.call(ict, HttpMethod.PUT, "/api/v1/platform/notices/smtp-pace", pace);
            assertThat(set.getStatusCode().value()).as(String.valueOf(set.getBody())).isEqualTo(200);
            assertThat(set.getBody()).containsEntry("perMinute", 20).containsEntry("perDay", 5000);
            Map smtpPace = (Map) it.get(ict, "/api/v1/platform/notices?limit=1").getBody().get("smtpPace");
            assertThat(smtpPace).containsEntry("perMinute", 20);
            assertThat(((Number) smtpPace.get("allowance")).intValue()).isBetween(0, 20);

            // the batch takes no more e-mail than the pace allows now
            NoticeRepository.Delivery on = new NoticeRepository.Delivery(true, true, true, true);
            assertThat(notices.sendable(200, on, 0)).noneMatch(n -> "EMAIL".equals(n.channel()));
            assertThat(notices.sendable(200, on, 1).stream().filter(n -> "EMAIL".equals(n.channel())).count()).isLessThanOrEqualTo(1);

            // the account's failure holds a message without charging it an attempt
            it.db(() -> {
                notices.held(queued, "SEND_AS: not allowed to send as");
                return null;
            });
            Map row = jdbc.sql("SELECT state, attempts, last_error FROM platform.notice WHERE id = :n").param("n", queued).query().singleRow();
            assertThat(row).containsEntry("state", "QUEUED").containsEntry("attempts", 0).containsEntry("last_error", "SEND_AS: not allowed to send as");

            // the Mail server screen's test: ICT only, to a real address, and a server that cannot be reached is said so
            Map<String, Object> unreachable = Map.of("smtpHost", "127.0.0.1", "smtpPort", 1, "smtpEncryption", "NONE",
                    "username", "zz.pace.it@example.test", "password", "not a real password");
            assertThat(it.call(ItSupport.token("bursar"), HttpMethod.POST, "/api/v1/platform/mail/test", unreachable).getStatusCode().value()).isEqualTo(403);
            Map<String, Object> badAddress = new java.util.HashMap<>(unreachable);
            badAddress.put("sendTo", "not an address");
            assertThat(it.call(ict, HttpMethod.POST, "/api/v1/platform/mail/test", badAddress).getBody()).containsEntry("code", "MAIL_TEST_ADDRESS");
            ResponseEntity<Map> tested = it.call(ict, HttpMethod.POST, "/api/v1/platform/mail/test", unreachable);
            assertThat(tested.getStatusCode().value()).as(String.valueOf(tested.getBody())).isEqualTo(200);
            assertThat(tested.getBody()).containsEntry("ok", false).containsEntry("stage", "CONNECTION").containsEntry("kind", "UNREACHABLE")
                    .containsEntry("host", "127.0.0.1").doesNotContainKey("password");
            assertThat(String.valueOf(tested.getBody().get("words"))).contains("smtp.office365.com");
        } finally {
            it.db(() -> {
                jdbc.sql("UPDATE platform.notice_setting SET smtp_per_minute = :m, smtp_per_day = :d WHERE id")
                        .param("m", before.get("smtp_per_minute"), java.sql.Types.INTEGER).param("d", before.get("smtp_per_day"), java.sql.Types.INTEGER).update();
                jdbc.sql("DELETE FROM platform.notice WHERE id = :n").param("n", queued).update();
                return null;
            });
        }
    }
}
