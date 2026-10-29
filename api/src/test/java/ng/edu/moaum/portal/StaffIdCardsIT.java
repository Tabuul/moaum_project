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
 * V698: the Chief Security Officer's staff identity cards. Made-up staff — a lecturer holding an office, a non-teaching member of staff
 * on the HR staff register with no portal office, and one with neither — are on the roster as in service (the first two) with what
 * the card prints; the dashboard's summary is the counts alone; HR reads the roster but issues nothing; the Security Unit issues a card
 * to everyone in service without one in one act, and prints them all — the register's member of staff with the unit and category the
 * register gives — while the Library prints nothing. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class StaffIdCardsIT {

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    ItSupport it;
    String security;
    final String hrm = ItSupport.token("hrm");
    final String library = ItSupport.token("library");

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
        security = TestTokens.token(it.person("ZZSIDC-CSO", "ZZSIDCCSO"), List.of("security"));
    }

    private Map<String, Object> roster(String token, String query) {
        ResponseEntity<Map> r = it.get(token, u -> u.path("/api/v1/credentials/identity-cards/staff/roster").query(query).build());
        assertThat(r.getStatusCode().value()).as(String.valueOf(r.getBody())).isEqualTo(200);
        return r.getBody();
    }

    @Test
    void theSecurityUnitIssuesAndPrintsEveryStaffCardTheRegisterAndTheOfficesHold() {
        java.util.concurrent.ThreadLocalRandom rnd = java.util.concurrent.ThreadLocalRandom.current();
        StringBuilder tag = new StringBuilder("ZZSIDC");
        for (int i = 0; i < 6; i++) tag.append((char) ('A' + rnd.nextInt(26)));
        String surname = tag.toString();
        String unit = jdbc.sql("SELECT code FROM ref.unit WHERE ended_on IS NULL ORDER BY code LIMIT 1").query(String.class).single();
        String unitName = jdbc.sql("SELECT name FROM ref.unit WHERE code = :u").param("u", unit).query(String.class).single();
        UUID lecturer = UUID.randomUUID(), register = UUID.randomUUID(), neither = UUID.randomUUID();
        String n = String.valueOf(rnd.nextInt(100000, 999999));
        it.db(() -> {
            jdbc.sql("INSERT INTO iam.person (id, staff_number, surname, given_names) VALUES (:a, :na, :s, 'Lecturer'), (:b, :nb, :s, 'Register'), (:c, :nc, :s, 'Neither')")
                    .param("a", lecturer).param("na", "ZZL" + n).param("b", register).param("nb", "ZZR" + n).param("c", neither).param("nc", "ZZN" + n).param("s", surname).update();
            jdbc.sql("""
                    INSERT INTO iam.office_assignment (id, person_id, office_code, scope_kind, scope_id, instrument, granted_by, valid_from)
                    VALUES (gen_random_uuid(), :p, 'lecturer', 'department', 'MTC', 'staff id cards test', :p, current_date)
                    """).param("p", lecturer).update();
            return jdbc.sql("INSERT INTO hrm.staff_record (person_id, present_rank, category, home_unit) VALUES (:p, 'SENIOR EXECUTIVE OFFICER', 'NON_ACADEMIC', :u)")
                    .param("p", register).param("u", unit).update();
        });

        // ── the roster: the two in service, not the one with neither; what the card prints ──
        Map<String, Object> mine = roster(security, "q=" + surname);
        List<Map<String, Object>> rows = (List<Map<String, Object>>) mine.get("rows");
        assertThat(rows).extracting(r -> r.get("given_names")).containsExactly("Lecturer", "Register");
        Map<String, Object> reg = rows.get(1);
        assertThat(reg).containsEntry("in_office", false).containsEntry("category", "NON_ACADEMIC").containsEntry("unit", unitName).containsEntry("unit_code", unit);
        assertThat(((Map<String, Object>) mine.get("counts"))).containsEntry("staff", 2).containsEntry("withoutCard", 2).containsEntry("registerOnly", 1);
        // the dashboard's summary is the counts alone
        Map<String, Object> summary = roster(security, "summary=true");
        assertThat(summary).containsKey("counts").doesNotContainKey("rows");
        // HR reads the roster; issuing and printing are the Security Unit's
        assertThat((List<?>) roster(hrm, "q=" + surname).get("rows")).hasSize(2);
        assertThat(it.call(hrm, HttpMethod.POST, "/api/v1/credentials/identity-cards/staff/issue-all", Map.of("q", surname)).getStatusCode().value()).isEqualTo(403);
        assertThat(it.get(library, u -> u.path("/api/v1/credentials/identity-cards/staff/print").queryParam("q", surname).build()).getStatusCode().value()).isEqualTo(403);
        // nothing to print before the cards are issued
        assertThat((List<?>) it.get(security, u -> u.path("/api/v1/credentials/identity-cards/staff/print").queryParam("q", surname).build()).getBody().get("cards")).isEmpty();

        // ── issued all at once ──
        ResponseEntity<Map> issued = it.call(security, HttpMethod.POST, "/api/v1/credentials/identity-cards/staff/issue-all", Map.of("q", surname, "reason", "staff id cards test"));
        assertThat(issued.getStatusCode().value()).as(String.valueOf(issued.getBody())).isEqualTo(200);
        assertThat(((Number) issued.getBody().get("issued")).intValue()).isEqualTo(2);
        assertThat(((Map<String, Object>) roster(security, "q=" + surname).get("counts"))).containsEntry("withCard", 2).containsEntry("withoutCard", 0);
        // again: everyone named already holds one
        assertThat(it.call(security, HttpMethod.POST, "/api/v1/credentials/identity-cards/staff/issue-all", Map.of("q", surname)).getBody())
                .containsEntry("code", "STAFF_CARDS_NONE_WAITING");
        // the one with neither an office nor the register is still refused alone
        assertThat(it.call(security, HttpMethod.POST, "/api/v1/credentials/identity-cards/staff/issue", Map.of("staffNumber", "ZZN" + n)).getBody())
                .containsEntry("code", "STAFF_CARD_NO_OFFICE");

        // ── printed all at once: each card with what it prints ──
        List<Map<String, Object>> cards = (List<Map<String, Object>>) it.get(security, u -> u.path("/api/v1/credentials/identity-cards/staff/print").queryParam("q", surname).build())
                .getBody().get("cards");
        assertThat(cards).hasSize(2);
        assertThat(cards).allSatisfy(c -> assertThat(String.valueOf(c.get("card_no"))).matches("MOAUM/SID/[0-9]{2}/[0-9]{5}"));
        Map<String, Object> face = (Map<String, Object>) cards.stream().filter(c -> register.toString().equals(String.valueOf(c.get("person_id")))).findFirst().orElseThrow().get("face");
        assertThat(face).containsEntry("department", unitName).containsEntry("category", "NON_ACADEMIC").containsEntry("rank", "SENIOR EXECUTIVE OFFICER");
        // narrowed to the unit, only the register's member of staff
        assertThat((List<?>) it.get(security, u -> u.path("/api/v1/credentials/identity-cards/staff/print").queryParam("q", surname).queryParam("unit", unit).build()).getBody().get("cards")).hasSize(1);
        // the single card prints the same face
        assertThat((Map<String, Object>) it.get(security, "/api/v1/credentials/identity-cards/staff/" + register + "/card").getBody().get("face")).containsEntry("department", unitName);
    }
}
