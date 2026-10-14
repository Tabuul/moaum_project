package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.time.LocalDate;
import java.util.List;
import java.util.Map;
import java.util.Random;
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
 * The journal book gives each journal's lines as a list and its date as the day it is: the lines came as the database's
 * jsonb wrapper, which the Accounting screen could not read (Lines on any journal failed), and the entry date as a
 * timestamp that a time zone east of Greenwich showed as the day before.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT,
        properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
class AccountingJournalsIT {

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    @SuppressWarnings("unchecked")
    @Test
    void aJournalReadsBackWithItsLinesAsAListAndItsDayAsTheDay() {
        ItSupport it = new ItSupport(port, jdbc, transactions);
        String tag = Integer.toString(new Random().nextInt(9_000) + 1_000);
        String bursar = TestTokens.token(it.person("ZZACCJ-BUR-" + tag, "ZZACCJBUR"), List.of("bursar"));
        // two postable accounts of the chart, one each side
        List<String> accounts = it.db(() -> jdbc.sql("SELECT code FROM finance.gl_account WHERE postable AND active ORDER BY code LIMIT 2")
                .query(String.class).list());
        assertThat(accounts).hasSize(2);
        LocalDate day = LocalDate.of(2026, 9, 22);
        String memo = "ZZ journal book check " + tag;
        ResponseEntity<Map> posted = it.call(bursar, HttpMethod.POST, "/api/v1/finance/accounting/journals", Map.of(
                "date", day.toString(), "memo", memo,
                "lines", List.of(Map.of("account", accounts.get(0), "debit", 12.50, "narration", "check"),
                        Map.of("account", accounts.get(1), "credit", 12.50, "narration", "check"))));
        assertThat(posted.getStatusCode().value()).as(String.valueOf(posted.getBody())).isEqualTo(200);
        String id = String.valueOf(posted.getBody().get("id"));

        ResponseEntity<List> book = it.getList(bursar, "/api/v1/finance/accounting/journals?from=" + day + "&to=" + day + "&limit=500");
        assertThat(book.getStatusCode().value()).isEqualTo(200);
        Map<String, Object> mine = ((List<Map<String, Object>>) book.getBody()).stream().filter(j -> id.equals(String.valueOf(j.get("id"))))
                .findFirst().orElseThrow();
        assertThat(mine.get("entry_date")).isEqualTo("2026-09-22");
        assertThat(mine.get("lines")).isInstanceOf(List.class);
        List<Map<String, Object>> lines = (List<Map<String, Object>>) mine.get("lines");
        assertThat(lines).extracting(l -> l.get("account")).containsExactly(accounts.get(0), accounts.get(1));

        ResponseEntity<Map> ledger = it.get(bursar, "/api/v1/finance/accounting/ledger?account=" + accounts.get(0) + "&from=" + day + "&to=" + day);
        assertThat(ledger.getStatusCode().value()).isEqualTo(200);
        assertThat((List<Map<String, Object>>) ledger.getBody().get("rows")).isNotEmpty()
                .allSatisfy(r -> assertThat(r.get("entry_date")).isEqualTo("2026-09-22"));
    }
}
