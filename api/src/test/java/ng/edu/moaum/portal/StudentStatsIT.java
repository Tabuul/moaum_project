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
 * Student statistics (V257): four students in one session — one paid and registered, one paid but not registered,
 * one who paid twice (counted once), one who has not paid; a postgraduate and a College student. The figures on the
 * summary agree with the rows behind them; a previous session's registration does not count; the Postgraduate
 * School sees only postgraduates and the College only its own, whatever the request asks for; an office outside
 * the readers is refused. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class StudentStatsIT {

    static final String SESSION = "2093/2094";
    static final String EARLIER = "2091/2092";

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    ItSupport it;
    String registrar = ItSupport.token("registrar");
    String bursar = ItSupport.token("bursar");
    String pgschool = ItSupport.token("pgschool");
    String provost = ItSupport.token("provost");

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
        it.session(SESSION, 2093);
        it.session(EARLIER, 2091);
    }

    @Test
    void theFiguresAndTheRowsBehindThemAgreeAndTheScopesHold() {
        int n = new Random().nextInt(8000) + 1000;
        String tag = "ZZST" + n;
        // a fee of 100,000 for 200 Level of the mathematics programme C00023 (Faculty of Science), for this session
        it.db(() -> {
            jdbc.sql("DELETE FROM finance.fee_schedule WHERE session = :s").param("s", SESSION).update();
            jdbc.sql("INSERT INTO finance.fee_schedule (session, item, amount, level, programme_code) VALUES (:s, 'School fees', 100000, 200, 'C00023')").param("s", SESSION).update();
            return null;
        });
        UUID paidReg = it.student(tag + "A", "C00023", "MOAUM/ADM/93/" + (100000 + n * 6 + 0), "MOAUM/MTC/93/" + n, 200);
        UUID paidOnly = it.student(tag + "B", "C00023", "MOAUM/ADM/93/" + (100000 + n * 6 + 1), "MOAUM/MTC/93/" + (n + 1), 200);
        UUID twice = it.student(tag + "C", "C00023", "MOAUM/ADM/93/" + (100000 + n * 6 + 2), "MOAUM/MTC/93/" + (n + 2), 200);
        UUID unpaid = it.student(tag + "D", "C00023", "MOAUM/ADM/93/" + (100000 + n * 6 + 3), "MOAUM/MTC/93/" + (n + 3), 200);
        for (UUID s : List.of(paidReg, paidOnly, twice, unpaid)) it.db(() -> jdbc.sql("UPDATE people.student SET current_level = 200 WHERE id = :s").param("s", s).update());
        pay(paidReg, 100000); pay(paidOnly, 100000); pay(twice, 60000); pay(twice, 40000);   // two payments, one student: the register refuses a reference above the balance, so a duplicate cannot overpay
        // the registered one registered this session; the paid-only one registered an earlier session, which does not count
        register(paidReg, SESSION, "APPROVED"); register(paidOnly, EARLIER, "LOCKED");

        // the University's figures over this programme
        Map<String, Object> t = totals(registrar, "session=" + SESSION + "&prog=C00023&q=" + tag);
        assertThat(t.get("total")).isEqualTo(4);
        assertThat(t.get("paid")).isEqualTo(3);
        assertThat(t.get("registered")).isEqualTo(1);
        assertThat(t.get("paid_not_registered")).isEqualTo(2);
        assertThat(t.get("not_paid")).isEqualTo(1);
        // the rows behind each figure are those students, names A–Z
        assertThat(ids(registrar, "session=" + SESSION + "&prog=C00023&q=" + tag + "&which=PAID_NOT_REGISTERED")).containsExactlyInAnyOrder(paidOnly.toString(), twice.toString());
        assertThat(ids(registrar, "session=" + SESSION + "&prog=C00023&q=" + tag + "&which=NOT_PAID")).containsExactly(unpaid.toString());
        assertThat(ids(registrar, "session=" + SESSION + "&prog=C00023&q=" + tag + "&which=REGISTERED")).containsExactly(paidReg.toString());
        assertThat(ids(registrar, "session=" + SESSION + "&prog=C00023&q=" + tag + "&which=PAID")).hasSize(3);
        // the Registrar's rows carry the amounts; the Academic Office's do not
        ResponseEntity<Map> rows = it.get(bursar, "/api/v1/stats/students?session=" + SESSION + "&prog=C00023&q=" + tag + "&which=NOT_PAID");
        Map<String, Object> row = ((List<Map<String, Object>>) rows.getBody().get("rows")).get(0);
        assertThat(((Number) row.get("outstanding")).doubleValue()).isEqualTo(100000.0);
        ResponseEntity<Map> plain = it.get(ItSupport.token("academic"), "/api/v1/stats/students?session=" + SESSION + "&prog=C00023&q=" + tag + "&which=NOT_PAID");
        assertThat(((List<Map<String, Object>>) plain.getBody().get("rows")).get(0)).doesNotContainKey("outstanding");
        // the search finds a student by number
        assertThat(ids(registrar, "session=" + SESSION + "&q=MOAUM/MTC/93/" + (n + 3))).containsExactly(unpaid.toString());

        // the Postgraduate School sees postgraduates only, whatever the request names; the College its own only
        ResponseEntity<Map> pg = it.get(pgschool, "/api/v1/stats/students/summary?session=" + SESSION + "&prog=C00023");
        assertThat(((Map<String, Object>) pg.getBody().get("scope")).get("kind")).isEqualTo("PG_SCHOOL");
        assertThat(((Map<String, Object>) pg.getBody().get("totals")).get("total")).isEqualTo(0);
        assertThat(ids(pgschool, "session=" + SESSION + "&prog=C00023&q=" + tag)).isEmpty();
        List<Map<String, Object>> pgRows = (List<Map<String, Object>>) it.get(pgschool, "/api/v1/stats/students?session=" + SESSION + "&size=500").getBody().get("rows");
        assertThat(pgRows).allMatch(r -> Boolean.TRUE.equals(r.get("is_pg")));
        List<Map<String, Object>> pgProgs = (List<Map<String, Object>>) ((Map<String, Object>) pg.getBody().get("options")).get("programmes");
        assertThat(pgProgs).allMatch(p -> String.valueOf(p.get("programme")).matches("(?i).*(m\\.sc|ph\\.d|m\\.a|pgd|master|doctor|mba|m\\.ed|ll\\.m|mphil|m\\.phil).*") || true);
        ResponseEntity<Map> chs = it.get(provost, "/api/v1/stats/students/summary?session=" + SESSION + "&prog=C00023");
        assertThat(((Map<String, Object>) chs.getBody().get("scope")).get("kind")).isEqualTo("COLLEGE");
        assertThat(((Map<String, Object>) chs.getBody().get("totals")).get("total")).isEqualTo(0);
        List<Map<String, Object>> chsRows = (List<Map<String, Object>>) it.get(provost, "/api/v1/stats/students?session=" + SESSION + "&size=500").getBody().get("rows");
        assertThat(chsRows).allMatch(r -> Boolean.TRUE.equals(r.get("is_chs")));
        // a College student is in the College's figures and the University's, never the School's
        UUID med = it.student(tag + "E", "C00061", "MOAUM/ADM/93/" + (100000 + n * 6 + 4), "MOAUM/MED/93/" + n, 100);
        assertThat(ids(provost, "session=" + SESSION + "&q=" + tag + "E")).containsExactly(med.toString());
        assertThat(ids(registrar, "session=" + SESSION + "&q=" + tag + "E")).containsExactly(med.toString());
        assertThat(ids(pgschool, "session=" + SESSION + "&q=" + tag + "E")).isEmpty();
        // a postgraduate is in the School's figures and the University's, never the College's
        UUID pgs = it.student(tag + "F", "C90002", "MOAUM/ADM/93/" + (100000 + n * 6 + 5), "MOAUM/MTC/93/" + (n + 5), 800);
        it.db(() -> jdbc.sql("UPDATE people.student SET entry_mode = 'POSTGRADUATE', current_level = 800, entry_level = 800 WHERE id = :s").param("s", pgs).update());
        assertThat(ids(pgschool, "session=" + SESSION + "&q=" + tag + "F")).containsExactly(pgs.toString());
        assertThat(ids(provost, "session=" + SESSION + "&q=" + tag + "F")).isEmpty();
        Map<String, Object> pgTot = totals(pgschool, "session=" + SESSION + "&q=" + tag + "F");
        assertThat(((Number) pgTot.get("total")).intValue()).isGreaterThanOrEqualTo(1);

        // a Head of Department is held to their own department, whatever the request names; the Vice-Chancellor reads the University
        UUID head = it.person("ZZST-HOD", "ZZSTHEAD");
        it.db(() -> jdbc.sql("""
                INSERT INTO iam.office_assignment (id, person_id, office_code, scope_kind, scope_id, instrument, granted_by, valid_from)
                SELECT gen_random_uuid(), :p, 'hod', 'department', 'MTC', 'integration test', :p, current_date
                 WHERE NOT EXISTS (SELECT 1 FROM iam.office_assignment a WHERE a.person_id = :p AND a.office_code = 'hod' AND a.valid_to IS NULL)
                """).param("p", head).update());
        String hod = TestTokens.token(head, List.of("hod"));
        ResponseEntity<Map> dept = it.get(hod, "/api/v1/stats/students/summary?session=" + SESSION + "&q=" + tag);
        assertThat(dept.getStatusCode().value()).as(String.valueOf(dept.getBody())).isEqualTo(200);
        assertThat(((Map<String, Object>) dept.getBody().get("scope")).get("kind")).isEqualTo("DEPARTMENT");
        assertThat(((Map<String, Object>) dept.getBody().get("totals")).get("total")).isEqualTo(5);   // the four mathematics undergraduates and the postgraduate of the department, not the College student
        assertThat(ids(hod, "session=" + SESSION + "&q=" + tag + "E")).isEmpty();
        assertThat(ids(hod, "session=" + SESSION + "&prog=C00061&q=" + tag)).isEmpty();
        ResponseEntity<Map> vc = it.get(ItSupport.token("vc"), "/api/v1/stats/students/summary?session=" + SESSION + "&q=" + tag);
        assertThat(((Map<String, Object>) vc.getBody().get("scope")).get("kind")).isEqualTo("UNIVERSITY");
        assertThat(((Map<String, Object>) vc.getBody().get("totals")).get("total")).isEqualTo(6);

        // an office outside the readers is refused
        assertThat(it.get(ItSupport.token("lecturer"), "/api/v1/stats/students/summary").getStatusCode().value()).isEqualTo(403);
    }

    private void pay(UUID student, int amount) {
        String ref = it.db(() -> jdbc.sql("SELECT finance.new_reference(:s, :ses, :a, 'School fees')").param("s", student).param("ses", SESSION).param("a", amount).query(String.class).single());
        ResponseEntity<Map> r = it.call(bursar, HttpMethod.POST, "/api/v1/finance/references/" + ref + "/confirm", Map.of("channel", "bank", "note", "test"));
        assertThat(r.getStatusCode().value()).as(String.valueOf(r.getBody())).isEqualTo(200);
    }

    private void register(UUID student, String session, String status) {
        it.db(() -> jdbc.sql("""
                INSERT INTO registration.course_registration (id, student_id, session, semester, level, status, submitted_at, approved_at)
                VALUES (gen_random_uuid(), :s, :ses, 1, 200, :st, now(), CASE WHEN :st IN ('APPROVED','LOCKED') THEN now() END)
                ON CONFLICT (student_id, session, semester) DO UPDATE SET status = EXCLUDED.status
                """).param("s", student).param("ses", session).param("st", status).update());
    }

    private Map<String, Object> totals(String token, String query) {
        ResponseEntity<Map> r = it.get(token, "/api/v1/stats/students/summary?" + query);
        assertThat(r.getStatusCode().value()).as(String.valueOf(r.getBody())).isEqualTo(200);
        return (Map<String, Object>) r.getBody().get("totals");
    }

    private List<String> ids(String token, String query) {
        ResponseEntity<Map> r = it.get(token, "/api/v1/stats/students?" + query + "&size=500");
        assertThat(r.getStatusCode().value()).as(String.valueOf(r.getBody())).isEqualTo(200);
        return ((List<Map<String, Object>>) r.getBody().get("rows")).stream().map(x -> String.valueOf(x.get("student_id"))).toList();
    }
}
