package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.LinkedHashMap;
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
 * The migration of the applicants who applied and paid on the old portal, with their email and phone (V296), through the
 * desk's endpoints: the file's JAMB number, email and phone number; the applicant verified on the JAMB CAPS list and imported
 * with the contacts as written (+234, spaces, the first of two); a missing or unusable contact, or an email already on another
 * applicant's account, leaving a placeholder and a note that says why; the contacts report and the list of those still without;
 * the same upload giving the applicants already migrated their email and phone, and changing nothing where nothing changed; the
 * migrated applicant then signing in, and reset by, the real email; only the admissions offices and ICT may import. Needs
 * DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class ApplicantImportIT {

    static final String SESSION = "2113/2114";
    static final String PATH = "/api/v1/admissions/sessions/2113/2114";

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    ItSupport it;
    final String academic = ItSupport.token("academic");
    final String bursar = ItSupport.token("bursar");

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
    }

    static Map<String, Object> m(Object o) { return (Map<String, Object>) o; }
    static List<Map<String, Object>> l(Object o) { return (List<Map<String, Object>>) o; }

    /** four applicants on a committed JAMB CAPS list for the session, with numbers of this run's own */
    List<String> caps() {
        int n = new Random().nextInt(9_000_000) + 1_000_000;
        List<String> keys = List.of("2113" + n + "1AB", "2113" + n + "2AB", "2113" + n + "3AB", "2113" + n + "4AB");
        it.db(() -> {
            UUID b = UUID.randomUUID();
            jdbc.sql("INSERT INTO admissions.caps_batch (id, session, source, filename, file_sha256, rows_read, list_kind, downloaded_on, uploaded_by, uploaded_office, committed_at) VALUES (:id, :s, 'CAPS_DOWNLOAD', 'import.xlsx', decode(md5(:id::text), 'hex'), 4, 'UTME', current_date, gen_random_uuid(), 'academic', now())")
                    .param("id", b).param("s", SESSION).update();
            int i = 0;
            for (String k : keys) {
                i++;
                jdbc.sql("INSERT INTO admissions.caps_row (id, batch_id, session, jamb_reg_no, raw, surname, other_names, jamb_code, aggregate, entry_mode, sex, state_of_origin, lga) VALUES (gen_random_uuid(), :b, :s, :j, '{}'::jsonb, :sn, 'Import Person', 'C00023', 215, 'UTME', 'M', 'Benue', 'Otukpo')")
                        .param("b", b).param("s", SESSION).param("j", k).param("sn", "ZZIMPORT-" + n + "-" + i).update();
            }
            return null;
        });
        return keys;
    }

    static Map<String, Object> row(String jamb, String email, String phone) {
        Map<String, Object> r = new LinkedHashMap<>();
        r.put("jambKey", jamb);
        r.put("email", email);
        r.put("phone", phone);
        return r;
    }

    ResponseEntity<Map> upload(String token, List<Map<String, Object>> rows) {
        return it.call(token, HttpMethod.POST, PATH + "/import-applicants", Map.of("rows", rows));
    }

    @Test
    void theOldPortalApplicantsComeWithTheirEmailAndPhoneAndThoseAlreadyMigratedTakeThem() {
        List<String> k = caps();
        int n = new Random().nextInt(9_000_000) + 1_000_000;
        String emailA = "ada." + n + "@example.com", emailB = "bem." + n + "@example.com", emailC = "chidi." + n + "@example.com";

        // only the admissions offices and ICT import
        assertThat(upload(bursar, List.of(row(k.get(0), emailA, "08031234567"))).getStatusCode().value()).isEqualTo(403);
        assertThat(it.get(bursar, PATH + "/import-applicants/contacts").getStatusCode().value()).isEqualTo(403);

        // the first upload: A with contacts (+234, spaces); B with none; C with A's email and two numbers; a number not on CAPS
        ResponseEntity<Map> first = upload(academic, List.of(
                row(k.get(0), "  Ada Okafor <" + emailA.toUpperCase() + ">", "+234 803 123 4567"),
                row(k.get(1), "", ""),
                row(k.get(2), emailA, "0706 555 1234 / 0805 000 1111"),
                row("2113" + n + "9ZZ", "zed." + n + "@example.com", "08030000000")));
        assertThat(first.getStatusCode().value()).as(String.valueOf(first.getBody())).isEqualTo(200);
        Map<String, Object> t = first.getBody();
        assertThat(t.get("imported")).isEqualTo(3);
        assertThat(t.get("updated")).isEqualTo(0);
        assertThat(t.get("skipped")).isEqualTo(1);
        assertThat(t.get("placeholders")).isEqualTo(2);   // B without either, C without an email of its own
        assertThat(String.valueOf(l(t.get("problems")).get(0).get("status"))).contains("not on the JAMB CAPS list");
        Map<String, Object> noteB = l(t.get("notes")).stream().filter(x -> k.get(1).equals(x.get("jambKey"))).findFirst().orElseThrow();
        assertThat(noteB.get("emailNote")).isEqualTo("no email in the file");
        assertThat(noteB.get("phoneNote")).isEqualTo("no phone number in the file");
        Map<String, Object> noteC = l(t.get("notes")).stream().filter(x -> k.get(2).equals(x.get("jambKey"))).findFirst().orElseThrow();
        assertThat(String.valueOf(noteC.get("emailNote"))).startsWith("already on another applicant's account");
        assertThat(noteC.get("phoneNote")).isNull();
        assertThat(noteC.get("phoneNow")).isEqualTo("07065551234");
        assertThat(l(t.get("notes")).stream().map(x -> x.get("jambKey"))).doesNotContain(k.get(0));
        Map<String, Object> accountA = jdbc.sql("SELECT email, phone, password_hash FROM admissions.applicant_account WHERE session = :s AND jamb_key = :k")
                .param("s", SESSION).param("k", k.get(0)).query().singleRow();
        assertThat(accountA.get("email")).isEqualTo(emailA);
        assertThat(accountA.get("phone")).isEqualTo("08031234567");
        assertThat(accountA.get("password_hash")).isEqualTo("SET_ON_FIRST_LOGIN");

        // the contacts report, and the applicants still without, in the template's shape
        Map<String, Object> contacts = m(it.get(academic, PATH + "/import-applicants/contacts").getBody());
        assertThat(((Number) contacts.get("migrated")).intValue()).isGreaterThanOrEqualTo(3);
        List<Map<String, Object>> missing = l(m(it.get(academic, PATH + "/import-applicants/contacts?missing=true").getBody()).get("rows"));
        assertThat(missing.stream().filter(x -> k.get(1).equals(x.get("jambKey"))).findFirst().orElseThrow().get("missing")).isEqualTo("email and phone");
        assertThat(missing.stream().filter(x -> k.get(2).equals(x.get("jambKey"))).findFirst().orElseThrow().get("missing")).isEqualTo("email");
        assertThat(missing.stream().map(x -> x.get("jambKey"))).doesNotContain(k.get(0));

        // the same upload again, with the contacts the office now holds: B and C take theirs, A has nothing to change
        ResponseEntity<Map> second = upload(academic, List.of(
                row(k.get(0), emailA, "08031234567"),
                row(k.get(1), emailB, "8061112222"),
                row(k.get(2), emailC, "07065551234")));
        assertThat(second.getStatusCode().value()).as(String.valueOf(second.getBody())).isEqualTo(200);
        assertThat(second.getBody().get("imported")).isEqualTo(0);
        assertThat(second.getBody().get("updated")).isEqualTo(2);
        assertThat(second.getBody().get("existed")).isEqualTo(1);
        assertThat(second.getBody().get("placeholders")).isEqualTo(0);
        assertThat(l(second.getBody().get("notes"))).isEmpty();
        assertThat(jdbc.sql("SELECT count(*) FROM admissions.applicant_account WHERE session = :s AND jamb_key IN (:k)").param("s", SESSION).param("k", k).query(Long.class).single()).isEqualTo(3);
        assertThat(jdbc.sql("SELECT count(*) FROM admissions.application a JOIN admissions.applicant_account x ON x.id = a.account_id WHERE x.session = :s AND x.jamb_key IN (:k)").param("s", SESSION).param("k", k).query(Long.class).single()).isEqualTo(3);
        List<Map<String, Object>> stillMissing = l(m(it.get(academic, PATH + "/import-applicants/contacts?missing=true").getBody()).get("rows"));
        assertThat(stillMissing.stream().map(x -> x.get("jambKey"))).doesNotContain(k.get(0), k.get(1), k.get(2));
        assertThat(jdbc.sql("SELECT count(*) FROM admissions.applicant_event WHERE identifier IN (:k) AND outcome LIKE 'CONTACTS_UPDATED%'").param("k", k).query(Long.class).single()).isEqualTo(2);

        // B signs in with the email now on the account (the first password is still the JAMB number), and a reset reaches it
        ResponseEntity<Map> signIn = it.anon(HttpMethod.POST, "/api/v1/applicant/sign-in", Map.of("identifier", emailB, "password", k.get(1)));
        assertThat(signIn.getStatusCode().value()).as(String.valueOf(signIn.getBody())).isEqualTo(200);
        Map<String, Object> me = it.get(String.valueOf(signIn.getBody().get("token")), "/api/v1/applicant/me").getBody();
        assertThat(me.get("email")).isEqualTo(emailB);
        assertThat(me.get("phone")).isEqualTo("08061112222");
        assertThat(it.anon(HttpMethod.POST, "/api/v1/applicant/forgot", Map.of("identifier", emailB)).getStatusCode().value()).isEqualTo(202);
        assertThat(jdbc.sql("SELECT count(*) FROM platform.notice WHERE channel = 'EMAIL' AND recipient = :e AND subject LIKE 'Reset%'").param("e", emailB).query(Long.class).single()).isEqualTo(1);
    }
}
