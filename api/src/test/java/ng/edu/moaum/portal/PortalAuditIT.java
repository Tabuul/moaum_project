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
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.transaction.PlatformTransactionManager;

/**
 * Portal gap audit (V429 and the fixes beside it), through the API: a Head of Department reads the HR record of their own department's
 * staff and of anyone teaching their courses, never another department's; the Registry reads the possible duplicate students and a
 * lecturer does not; two records under one JAMB number are refused at the student door by name; the Registry keeps one and ends the
 * other (V431), after which the door finds the one record. Runs again on the same database. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class PortalAuditIT {

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    ItSupport it;

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
    }

    @Test
    void staffRecordsKeepToTheDepartmentAndDuplicatesAreTheRegistrys() {
        int n = new Random().nextInt(8000) + 1000;
        String dept = "MTC";
        String other = jdbc.sql("SELECT code FROM ref.department WHERE code <> 'MTC' AND faculty_code IS NOT NULL AND faculty_code <> (SELECT faculty_code FROM ref.department WHERE code = 'MTC') ORDER BY code LIMIT 1")
                .query(String.class).single();
        // two members of staff: one at home in MTC, one at home elsewhere
        UUID ours = it.person("ZZAUDIT-OURS-" + n, "ZZAUDITOURS" + n);
        UUID theirs = it.person("ZZAUDIT-THEIRS-" + n, "ZZAUDITTHEIRS" + n);
        it.db(() -> {
            for (Object[] r : new Object[][] {{ours, dept}, {theirs, other}}) {
                jdbc.sql("""
                        INSERT INTO hrm.staff_record (person_id, home_department) VALUES (:p, :d)
                        ON CONFLICT (person_id) DO UPDATE SET home_department = EXCLUDED.home_department
                        """).param("p", r[0]).param("d", r[1]).update();
            }
            return null;
        });
        String hod = it.officer("hod", "department", dept);
        assertThat(it.get(hod, "/api/v1/hr/staff/" + ours).getStatusCode().value()).isEqualTo(200);
        assertThat(it.get(hod, "/api/v1/hr/staff/" + theirs).getStatusCode().value()).isEqualTo(403);
        assertThat(it.get(hod, "/api/v1/hr/staff/" + theirs + "/photo").getStatusCode().value()).isEqualTo(403);
        // the Registry reads every record, as before
        assertThat(it.get(ItSupport.token("registrar"), "/api/v1/hr/staff/" + theirs).getStatusCode().value()).isEqualTo(200);

        // the possible duplicates: two records under one JAMB number, read by the Registry, never by a lecturer
        String jamb = "8429" + String.format("%08d", n) + "DU";
        it.student("ZZDUPAUDITA" + n, "C00061", "MOAUM/ADM/29/8" + n + "0", null, 100);
        it.student("ZZDUPAUDITB" + n, "C00061", "MOAUM/ADM/29/9" + n + "0", null, 100);
        it.db(() -> jdbc.sql("UPDATE people.student SET jamb_reg_no = :j WHERE surname IN (:a, :b)")
                .param("j", jamb).param("a", "ZZDUPAUDITA" + n).param("b", "ZZDUPAUDITB" + n).update());
        List<Map<String, Object>> dups = (List<Map<String, Object>>) (List<?>) it.getList(ItSupport.token("registrar"), "/api/v1/student/duplicates").getBody();
        assertThat(dups).filteredOn(d -> jamb.equals(d.get("match_key"))).hasSize(2);
        assertThat(it.get(ItSupport.token("lecturer"), "/api/v1/student/duplicates").getStatusCode().value()).isEqualTo(403);

        // V431: two live records under one JAMB number are refused at the door by name, never a server error
        var shared = it.anon(HttpMethod.POST, "/api/v1/student-auth/sign-in", Map.of("matricNo", jamb, "password", "not the password " + n));
        assertThat(shared.getStatusCode().value()).isEqualTo(422);
        assertThat(shared.getBody().get("code")).isEqualTo("STUDENT_NUMBER_SHARED");
        // the Registry keeps A and ends B; a lecturer cannot
        UUID a = jdbc.sql("SELECT id FROM people.student WHERE surname = :s").param("s", "ZZDUPAUDITA" + n).query(UUID.class).single();
        UUID b = jdbc.sql("SELECT id FROM people.student WHERE surname = :s").param("s", "ZZDUPAUDITB" + n).query(UUID.class).single();
        Map<String, Object> resolve = Map.of("keep", a.toString(), "end", b.toString(), "reason", "The same candidate taken on twice");
        assertThat(it.call(ItSupport.token("lecturer"), HttpMethod.POST, "/api/v1/student/duplicates/resolve", resolve).getStatusCode().value()).isEqualTo(403);
        var done = it.call(ItSupport.token("registrar"), HttpMethod.POST, "/api/v1/student/duplicates/resolve", resolve);
        assertThat(done.getStatusCode().value()).as(String.valueOf(done.getBody())).isEqualTo(200);
        assertThat(done.getBody().get("ended_number")).isEqualTo("MOAUM/ADM/29/9" + n + "0");
        assertThat(jdbc.sql("SELECT status FROM people.student WHERE id = :b").param("b", b).query(String.class).single()).isEqualTo("WITHDRAWN");
        List<Map<String, Object>> after = (List<Map<String, Object>>) (List<?>) it.getList(ItSupport.token("registrar"), "/api/v1/student/duplicates").getBody();
        assertThat(after).filteredOn(d -> jamb.equals(d.get("match_key"))).isEmpty();
        // the door now finds the one record: a wrong password is a wrong password
        var single = it.anon(HttpMethod.POST, "/api/v1/student-auth/sign-in", Map.of("matricNo", jamb, "password", "not the password " + n));
        assertThat(single.getBody().get("code")).isNotEqualTo("STUDENT_NUMBER_SHARED");
        assertThat(single.getStatusCode().is5xxServerError()).isFalse();
        // a second decision on the same pair is refused
        var again = it.call(ItSupport.token("registrar"), HttpMethod.POST, "/api/v1/student/duplicates/resolve", resolve);
        assertThat(again.getStatusCode().value()).isEqualTo(422);
        assertThat(again.getBody().get("code")).isEqualTo("DUPLICATE_ALREADY_ENDED");
    }

    @Test
    void aPrintedDefermentOrCardVerifiesOnlyWithItsOwnCode() {
        int n = new Random().nextInt(80000) + 10000;
        UUID st = it.student("ZZQRVERIFY" + n, "C00061", "MOAUM/ADM/43/" + String.format("%06d", n), "MOAUM/QRV/43/" + n, 200);
        UUID issuer = it.person("ZZQRISSUER-" + n, "ZZQRISSUER" + n);
        String ref = "DEF-9431-" + String.format("%05d", n);
        String cardNo = "MOAUM/ID/43/" + n;   // the card number's own shape: five digits
        it.session("2093/2094", 2093);   // a deferment names a session on the calendar
        String defCode = it.db(() -> {
            jdbc.sql("INSERT INTO credentials.identity_card (student_id, card_no, issued_by, valid_to) VALUES (:s, :n, :p, current_date + 365)")
                    .param("s", st).param("n", cardNo).param("p", issuer).update();
            return jdbc.sql("""
                    INSERT INTO people.deferment (reference, student_id, kind, session, reason_code, state)
                    VALUES (:r, :s, 'SESSION', '2093/2094', (SELECT code FROM people.deferment_reason ORDER BY code LIMIT 1), 'APPROVED')
                    RETURNING verify_code
                    """).param("r", ref).param("s", st).query(String.class).single();
        });
        String any = ItSupport.token("lecturer");   // the verification doors are public; any caller is a stranger to them

        // V435: the deferment letter answers only with the code its QR carries
        Map<?, ?> bare = it.get(any, u -> u.path("/api/v1/verify/deferment/{r}").build(ref)).getBody();
        assertThat(bare.get("genuine")).isEqualTo(false);
        assertThat(bare.get("codeMissing")).isEqualTo(true);
        assertThat(bare.get("student_name")).isNull();
        Map<?, ?> wrong = it.get(any, u -> u.path("/api/v1/verify/deferment/{r}").queryParam("c", "0123456789abcdef01").build(ref)).getBody();
        assertThat(wrong.get("genuine")).isEqualTo(false);
        assertThat(wrong.get("student_name")).isNull();
        Map<?, ?> right = it.get(any, u -> u.path("/api/v1/verify/deferment/{r}").queryParam("c", defCode).build(ref)).getBody();
        assertThat(right.get("genuine")).isEqualTo(true);
        assertThat(right.get("reference")).isEqualTo(ref);
        assertThat(right.containsKey("verify_code")).isFalse();

        // the card desk is given the address the card's QR carries; the public page answers it, and nothing else
        List<Map<String, Object>> cards = (List<Map<String, Object>>) it.get(ItSupport.token("registrar"), "/api/v1/credentials/identity-cards").getBody().get("cards");
        String path = cards.stream().filter(c -> cardNo.equals(c.get("card_no"))).map(c -> String.valueOf(c.get("verify_path"))).findFirst().orElseThrow();
        String code = path.substring(path.indexOf("&c=") + 3);
        Map<?, ?> card = it.get(any, u -> u.path("/api/v1/verify/idcard").queryParam("no", "{n}").queryParam("c", "{c}").build(cardNo, code)).getBody();
        assertThat(card.get("genuine")).isEqualTo(true);
        assertThat(card.get("student_number")).isEqualTo("MOAUM/QRV/43/" + n);
        String altered = (code.charAt(0) == 'A' ? "B" : "A") + code.substring(1);
        Map<?, ?> forged = it.get(any, u -> u.path("/api/v1/verify/idcard").queryParam("no", "{n}").queryParam("c", "{c}").build(cardNo, altered)).getBody();
        assertThat(forged.get("genuine")).isEqualTo(false);
        assertThat(forged.get("student_name")).isNull();
        // another card's number under this card's code fails too
        Map<?, ?> swapped = it.get(any, u -> u.path("/api/v1/verify/idcard").queryParam("no", "{n}").queryParam("c", "{c}").build(cardNo + "1", code)).getBody();
        assertThat(swapped.get("genuine")).isEqualTo(false);
        // a card reported lost says so and names no one
        it.db(() -> jdbc.sql("UPDATE credentials.identity_card SET state = 'LOST', ended_at = now(), ended_reason = 'test' WHERE card_no = :n").param("n", cardNo).update());
        Map<?, ?> lost = it.get(any, u -> u.path("/api/v1/verify/idcard").queryParam("no", "{n}").queryParam("c", "{c}").build(cardNo, code)).getBody();
        assertThat(lost.get("genuine")).isEqualTo(false);
        assertThat(lost.get("state")).isEqualTo("LOST");
        assertThat(lost.get("student_name")).isNull();
    }
}
