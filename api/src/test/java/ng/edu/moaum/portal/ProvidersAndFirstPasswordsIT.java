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

import ng.edu.moaum.portal.platform.NoticeRepository;

/**
 * V442 through the API: the dispatcher's attempts are counted by provider; the offices read each channel's health and set the
 * watch, run it now; the accounts still on their first password are counted and listed within the office's scope, the staff
 * by the offices that read the whole University; a campaign's filter reaches exactly them.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT,
        properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
class ProvidersAndFirstPasswordsIT {

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;
    @Autowired
    NoticeRepository notices;

    ItSupport it;
    String ict;
    String tag;
    String ses;

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
        tag = Integer.toString(new Random().nextInt(900_000) + 100_000);
        ict = TestTokens.token(it.person("ZZPFP-ICT-" + tag, "ZZPFPICT"), List.of("ict"));
        ses = "2091/2092";
        it.session(ses, 2091);
    }

    @SuppressWarnings("unchecked")
    private static Map<String, Object> body(ResponseEntity<Map> r) {
        assertThat(r.getStatusCode().value()).as(String.valueOf(r.getBody())).isEqualTo(200);
        return r.getBody();
    }

    private static String code(ResponseEntity<Map> r) {
        assertThat(r.getStatusCode().value()).as(String.valueOf(r.getBody())).isEqualTo(422);
        return String.valueOf(r.getBody().get("code"));
    }

    @SuppressWarnings("unchecked")
    @Test
    void theProvidersAreCountedReadSetAndCheckedNow() {
        int before = it.db(() -> jdbc.sql("SELECT coalesce(sum(failed), 0) FROM platform.dispatch_tally WHERE channel = 'SMS' AND provider = 'it-" + tag + "'").query(Integer.class).single());
        it.db(() -> {
            notices.recordAttempt("SMS", "it-" + tag, false, "IT: credit exhausted");
            notices.recordAttempt("SMS", "it-" + tag, true, null);
            return null;
        });
        Map<String, Object> tally = it.db(() -> jdbc.sql("SELECT sum(tried) AS tried, sum(failed) AS failed, max(last_error) AS last_error FROM platform.dispatch_tally WHERE channel = 'SMS' AND provider = :p")
                .param("p", "it-" + tag).query().singleRow());
        assertThat(((Number) tally.get("tried")).intValue()).isEqualTo(2);
        assertThat(((Number) tally.get("failed")).intValue()).isEqualTo(before + 1);
        assertThat(tally.get("last_error")).isEqualTo("IT: credit exhausted");
        // the outbox carries each channel's health and the settings
        Map<String, Object> outbox = body(it.get(ict, "/api/v1/platform/notices"));
        List<Map<String, Object>> providers = (List<Map<String, Object>>) outbox.get("providers");
        assertThat(providers).extracting(p -> p.get("channel")).containsExactly("EMAIL", "SMS");
        assertThat(providers).allSatisfy(p -> assertThat(p.get("state")).isIn("OK", "IDLE", "OFF", "FAILING", "STUCK", "LOW_BALANCE"));
        assertThat(((Map<String, Object>) outbox.get("providerSettings")).get("provider_watch")).isNotNull();
        // the settings: a number of units, 0 switches the warning off, nothing else
        Map<String, Object> set = body(it.call(ict, HttpMethod.PUT, "/api/v1/platform/notices/providers", Map.of("lowBalance", "250", "watch", true)));
        assertThat(((Number) set.get("sms_low_balance")).intValue()).isEqualTo(250);
        assertThat(code(it.call(ict, HttpMethod.PUT, "/api/v1/platform/notices/providers", Map.of("lowBalance", "plenty")))).isEqualTo("PROVIDER_LOW_BALANCE");
        assertThat(code(it.call(ict, HttpMethod.PUT, "/api/v1/platform/notices/providers", Map.of("lowBalance", -5)))).isEqualTo("PROVIDER_LOW_BALANCE");
        // checked now: the reading and the messages told; no eBulkSMS account here, so no balance read
        Map<String, Object> checked = body(it.call(ict, HttpMethod.POST, "/api/v1/platform/notices/providers/check", Map.of()));
        assertThat(checked.get("told")).isInstanceOf(Number.class);
        assertThat((List<?>) checked.get("providers")).hasSize(2);
        // the settings are ICT's, not a lecturer's
        assertThat(it.call(TestTokens.token(it.person("ZZPFP-LEC-" + tag, "ZZPFPLEC"), List.of("lecturer")), HttpMethod.PUT, "/api/v1/platform/notices/providers", Map.of("watch", false))
                .getStatusCode().value()).isEqualTo(403);
        body(it.call(ict, HttpMethod.PUT, "/api/v1/platform/notices/providers", Map.of("lowBalance", "500", "watch", true)));
    }

    private UUID studentWithAccount(String surname, String adm, boolean mustChange, boolean signedIn) {
        UUID s = it.student(surname, "C00023", adm, null, 100);
        it.db(() -> {
            jdbc.sql("UPDATE people.student SET entry_session = :ses WHERE id = :s").param("ses", ses).param("s", s).update();
            jdbc.sql("INSERT INTO people.student_contact (student_id, phone, email) VALUES (:s, :p, :e) ON CONFLICT (student_id) DO UPDATE SET email = EXCLUDED.email")
                    .param("s", s).param("p", "0803" + adm.replaceAll("[^0-9]", "").substring(2) + "1").param("e", surname.toLowerCase() + "@example.test").update();
            jdbc.sql("""
                    INSERT INTO iam.student_account (id, student_id, password_hash, must_change, last_signed_in_at)
                    VALUES (gen_random_uuid(), :s, crypt(gen_random_uuid()::text, gen_salt('bf', 12)), :m, CASE WHEN :in THEN now() END)
                    ON CONFLICT (student_id) DO UPDATE SET must_change = EXCLUDED.must_change, last_signed_in_at = EXCLUDED.last_signed_in_at,
                        temp_expires_at = NULL, temp_issued_by = NULL, temp_used_at = NULL
                    """).param("s", s).param("m", mustChange).param("in", signedIn).update();
            return null;
        });
        return s;
    }

    @SuppressWarnings("unchecked")
    @Test
    void theFirstPasswordsAreCountedListedScopedAndReachedByACampaign() {
        int n = new Random().nextInt(9000) + 1000;
        UUID a = studentWithAccount("ITFPW" + n + "A", "MOAUM/ADM/91/1" + n + "0", true, false);
        UUID b = studentWithAccount("ITFPW" + n + "B", "MOAUM/ADM/91/2" + n + "0", true, true);
        UUID c = studentWithAccount("ITFPW" + n + "C", "MOAUM/ADM/91/3" + n + "0", false, true);
        // ICT reads the whole University: the students listed, the staff and applicants counted
        Map<String, Object> all = body(it.get(ict, "/api/v1/biodata/compliance/first-passwords?q=ITFPW" + n));
        assertThat(((List<Map<String, Object>>) all.get("rows")).stream().map(r -> String.valueOf(r.get("student_id")))).containsExactlyInAnyOrder(a.toString(), b.toString());
        assertThat(((Number) ((Map<String, Object>) all.get("summary")).get("students_first")).longValue()).isGreaterThanOrEqualTo(2);
        assertThat(all.get("others")).isNotNull();
        assertThat((List<?>) all.get("units")).isNotEmpty();
        Map<String, Object> never = body(it.get(ict, "/api/v1/biodata/compliance/first-passwords?never=true&q=ITFPW" + n));
        assertThat(((List<Map<String, Object>>) never.get("rows")).stream().map(r -> String.valueOf(r.get("student_id")))).containsExactly(a.toString());
        // a Dean reads their own faculty, never another's, and not the staff
        String facA = it.db(() -> jdbc.sql("SELECT faculty_code FROM ref.programme WHERE code = 'C00023'").query(String.class).single());
        String facOther = it.db(() -> jdbc.sql("SELECT faculty_code FROM ref.programme WHERE faculty_code <> :f AND NOT coalesce(archived, false) ORDER BY code LIMIT 1").param("f", facA).query(String.class).single());
        UUID deanPerson = it.person("ZZPFP-DEAN-" + tag, "ZZPFPDEAN");
        it.db(() -> jdbc.sql("INSERT INTO iam.office_assignment (id, person_id, office_code, scope_kind, scope_id, instrument, granted_by, valid_from) VALUES (gen_random_uuid(), :p, 'dean', 'faculty', :f, 'IT', :p, current_date)")
                .param("p", deanPerson).param("f", facA).update());
        String dean = TestTokens.token(deanPerson, List.of("dean"));
        Map<String, Object> mine = body(it.get(dean, "/api/v1/biodata/compliance/first-passwords?q=ITFPW" + n));
        assertThat(mine.get("faculty")).isEqualTo(facA);
        assertThat(mine.get("others")).isNull();
        assertThat(((List<Map<String, Object>>) mine.get("rows"))).hasSize(2);
        assertThat(it.get(dean, "/api/v1/biodata/compliance/first-passwords?faculty=" + facOther).getStatusCode().value()).isEqualTo(422);
        assertThat(it.get(dean, "/api/v1/biodata/compliance/first-passwords/staff").getStatusCode().value()).isEqualTo(403);
        // a member of staff still on their first password is listed for ICT
        UUID staff = it.person("ZZPFP-STF-" + tag, "ZZPFPSTF" + n);
        it.db(() -> {
            jdbc.sql("INSERT INTO iam.office_assignment (id, person_id, office_code, scope_kind, scope_id, instrument, granted_by, valid_from) VALUES (gen_random_uuid(), :p, 'lecturer', 'department', (SELECT dept_code FROM ref.programme WHERE code = 'C00023'), 'IT', :p, current_date)")
                    .param("p", staff).update();
            jdbc.sql("INSERT INTO iam.credential (person_id, username, password_hash, must_change, set_by) VALUES (:p, :u, crypt(gen_random_uuid()::text, gen_salt('bf', 12)), true, :p) ON CONFLICT (person_id) DO UPDATE SET must_change = true")
                    .param("p", staff).param("u", "zzpfp-stf-" + tag).update();
            return null;
        });
        Map<String, Object> staffList = body(it.get(ict, "/api/v1/biodata/compliance/first-passwords/staff?q=ZZPFPSTF" + n));
        assertThat(((List<Map<String, Object>>) staffList.get("rows")).stream().map(r -> String.valueOf(r.get("person_id")))).containsExactly(staff.toString());
        // the campaign's filter: of the session's students, only those still on their first password
        Map<String, Object> created = body(it.call(ict, HttpMethod.POST, "/api/v1/notices/campaigns", Map.of(
                "name", "IT first passwords " + tag, "templateKey", "FIRST_PASSWORD_REMINDER", "students", true,
                "filters", Map.of("session", ses, "first_password", true), "channels", List.of("EMAIL"))));
        String id = String.valueOf(created.get("id"));
        List<UUID> reached = it.db(() -> jdbc.sql("SELECT id FROM platform.campaign_recipients(:c::uuid, 'student', NULL, 1000)").param("c", id).query(UUID.class).list());
        assertThat(reached).contains(a, b).doesNotContain(c);
    }
}
