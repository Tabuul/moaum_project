package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.math.BigDecimal;
import java.sql.Types;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import org.junit.jupiter.api.AfterEach;
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
 * V734 — College Deans as inter-departmental transfer approving authorities (the University's master prompt of 12 November 2026, part B),
 * through the API: at a department of a College the Dean of its faculty is that department's approving authority beside an HOD; a Dean
 * reads only the applications from or into the faculty and acts only on a College's; the payment rules stand (nothing paid, no desk acts;
 * the final approval waits for the whole fee); an approval carries a comment and the state it was read at; every decision is in the
 * history; the next desk and the student are told; transfers between other faculties move as before.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class TransferDeanIT {

    static final BigDecimal FEE = new BigDecimal("20000");

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    ItSupport it;
    final UUID bursarId = UUID.randomUUID();
    final String bursar = TestTokens.token(bursarId, List.of("bursar"));
    final String academic = ItSupport.token("academic");
    final String registrar = ItSupport.token("registrar");
    Object feeBefore;

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
        feeBefore = jdbc.sql("SELECT transfer_fee FROM finance.fee_setting WHERE id = 1").query().singleRow().get("transfer_fee");
        ResponseEntity<Map> set = it.call(bursar, HttpMethod.PUT, "/api/v1/finance/transfer-fee", Map.of("amount", FEE));
        assertThat(set.getStatusCode().value()).as(String.valueOf(set.getBody())).isEqualTo(200);
    }

    @AfterEach
    void putTheFeeBack() {
        it.db(() -> jdbc.sql("UPDATE finance.fee_setting SET transfer_fee = :f WHERE id = 1").param("f", feeBefore, Types.NUMERIC).update());
    }

    String student(UUID id) {
        return TestTokens.token(id, List.of("student"));
    }

    List<Map<String, Object>> rows(String token) {
        ResponseEntity<Map> r = it.get(token, "/api/v1/transfers");
        assertThat(r.getStatusCode().value()).as(String.valueOf(r.getBody())).isEqualTo(200);
        return (List<Map<String, Object>>) r.getBody().get("rows");
    }

    Map<String, Object> row(String token, String application) {
        return rows(token).stream().filter(x -> application.equals(x.get("id"))).findFirst().orElseThrow(() -> new AssertionError("no row for " + application));
    }

    ResponseEntity<Map> approve(String token, String application, String expected, String note) {
        java.util.Map<String, Object> body = new java.util.HashMap<>();
        if (expected != null) body.put("expectedState", expected);
        if (note != null) body.put("note", note);
        return it.call(token, HttpMethod.POST, "/api/v1/transfers/" + application + "/approve", body);
    }

    /** the whole fee paid on this portal: the student's reference, confirmed by the Bursary */
    void payInFull(UUID student, String application) {
        ResponseEntity<Map> drawn = it.call(student(student), HttpMethod.POST, "/api/v1/me/transfer/" + application + "/fee", Map.of());
        assertThat(drawn.getStatusCode().value()).as(String.valueOf(drawn.getBody())).isEqualTo(200);
        ResponseEntity<Map> confirmed = it.call(bursar, HttpMethod.POST, "/api/v1/finance/references/" + drawn.getBody().get("reference") + "/confirm",
                Map.of("channel", "Bank transfer", "note", "V734 test"));
        assertThat(confirmed.getStatusCode().value()).as(String.valueOf(confirmed.getBody())).isEqualTo(200);
    }

    long noticesTo(String email, String subject) {
        return jdbc.sql("SELECT count(*) FROM platform.notice WHERE recipient = :e AND subject = :s")
                .param("e", email).param("s", subject).query(Long.class).single();
    }

    @Test
    void aCollegeDeanActsAtTheCollegesDepartmentDesksAndNoWhereElse() {
        // ── a programme of the test's own in a department of a College, two in departments of a faculty in no College ──
        String[] place = it.db(() -> {
            String college = jdbc.sql("""
                    SELECT d.code || ',' || d.faculty_code FROM ref.department d JOIN ref.faculty f ON f.code = d.faculty_code
                     WHERE f.college_code IS NOT NULL AND d.ended_on IS NULL ORDER BY d.code LIMIT 1
                    """).query(String.class).single();
            String plain = jdbc.sql("""
                    SELECT p1.dept_code || ',' || p2.dept_code || ',' || p1.faculty_code
                      FROM ref.programme p1 JOIN ref.programme p2 ON p2.faculty_code = p1.faculty_code AND p2.dept_code > p1.dept_code
                      JOIN ref.faculty f ON f.code = p1.faculty_code
                      JOIN ref.department d1 ON d1.code = p1.dept_code AND d1.ended_on IS NULL AND d1.faculty_code = p1.faculty_code
                      JOIN ref.department d2 ON d2.code = p2.dept_code AND d2.ended_on IS NULL AND d2.faculty_code = p2.faculty_code
                     WHERE p1.category = 'UNDER GRADUATE' AND p2.category = 'UNDER GRADUATE' AND NOT p1.archived AND NOT p2.archived
                       AND f.college_code IS NULL
                     ORDER BY p1.faculty_code, p1.dept_code, p2.dept_code LIMIT 1
                    """).query(String.class).single();
            List<String> codes = jdbc.sql("SELECT 'C' || x FROM generate_series(96000, 96499) x WHERE NOT EXISTS (SELECT 1 FROM ref.programme p WHERE p.code = 'C' || x) ORDER BY random() LIMIT 3")
                    .query(String.class).list();
            String[] c = college.split(","), p = plain.split(",");
            jdbc.sql("""
                    INSERT INTO ref.programme (code, name, dept_code, faculty_code, category, min_score, final_level, duration_years) VALUES
                        (:a, 'B.Sc. Dean Transfer College ' || :a, :ca, :cf, 'UNDER GRADUATE', 0, 400, 4),
                        (:b, 'B.Sc. Dean Transfer Plain ' || :b, :pa, :pf, 'UNDER GRADUATE', 0, 400, 4),
                        (:c, 'B.Sc. Dean Transfer Plain ' || :c, :pb, :pf, 'UNDER GRADUATE', 0, 400, 4)
                    """).param("a", codes.get(0)).param("b", codes.get(1)).param("c", codes.get(2)).param("ca", c[0]).param("cf", c[1])
                    .param("pa", p[0]).param("pb", p[1]).param("pf", p[2]).update();
            return new String[] {c[0], c[1], p[0], p[1], p[2], codes.get(0), codes.get(1), codes.get(2)};
        });
        String collegeDept = place[0], collegeFac = place[1], plainA = place[2], plainB = place[3], plainFac = place[4];
        String pc = place[5], pa = place[6], pb = place[7];
        String collegeDean = it.officer("dean", "faculty", collegeFac);
        String plainDean = it.officer("dean", "faculty", plainFac);
        String hodA = it.officer("hod", "department", plainA), hodB = it.officer("hod", "department", plainB);
        String deanEmail = "dean.v734." + collegeFac.toLowerCase() + "@example.test", hodAEmail = "hod.v734." + plainA.toLowerCase() + "@example.test";
        it.db(() -> {
            jdbc.sql("UPDATE iam.person SET email = :e WHERE staff_number = :n").param("e", deanEmail).param("n", "ZZ-DEAN-" + collegeFac.replaceAll("[^A-Za-z0-9]", "")).update();
            return jdbc.sql("UPDATE iam.person SET email = :e WHERE staff_number = :n").param("e", hodAEmail).param("n", "ZZ-HOD-" + plainA.replaceAll("[^A-Za-z0-9]", "")).update();
        });
        int n = it.freeDraw(1000, 9000, k -> List.of("ZZDEANOUT" + k, "ZZDEANIN" + k, "ZZDEANPLAIN" + k, "MOAU/V734/" + k, "MOAU/V734/" + (k + 1), "MOAU/V734/" + (k + 2)));
        UUID out = it.student("ZZDEANOUT" + n, pc, null, "MOAU/V734/" + n, 300);
        UUID in = it.student("ZZDEANIN" + n, pa, null, "MOAU/V734/" + (n + 1), 200);
        UUID plain = it.student("ZZDEANPLAIN" + n, pa, null, "MOAU/V734/" + (n + 2), 200);

        // ── three applications: out of the College, into it, and between two departments of a faculty in no College ──
        String a1 = String.valueOf(it.call(student(out), HttpMethod.POST, "/api/v1/me/transfer", Map.of("toProgramme", pa, "reason", "Out of the College")).getBody().get("id"));
        String a2 = String.valueOf(it.call(student(in), HttpMethod.POST, "/api/v1/me/transfer", Map.of("toProgramme", pc, "reason", "Into the College")).getBody().get("id"));
        String a3 = String.valueOf(it.call(student(plain), HttpMethod.POST, "/api/v1/me/transfer", Map.of("toProgramme", pb, "reason", "Within the faculty")).getBody().get("id"));

        // ── each Dean reads the applications from or into the faculty, no other; the College's names each side's unit ──
        List<Object> mine = rows(collegeDean).stream().map(x -> x.get("id")).toList();
        assertThat(mine).contains(a1, a2).doesNotContain(a3);
        assertThat(rows(plainDean).stream().map(x -> x.get("id")).toList()).contains(a1, a2, a3);
        Map<String, Object> r1 = row(collegeDean, a1);
        assertThat(r1).containsEntry("from_faculty", collegeFac).containsEntry("to_faculty", plainFac).containsEntry("desk", "FROM_DEPARTMENT");
        assertThat(r1.get("from_college")).isNotNull();
        assertThat(r1.get("to_college")).isNull();
        assertThat(it.get(collegeDean, "/api/v1/transfers/" + a3).getStatusCode().value()).isEqualTo(404);

        // ── nothing paid: no desk acts, the Dean's included ──
        assertThat(r1).containsEntry("canApprove", false).containsEntry("canDecline", true);
        assertThat(approve(collegeDean, a1, "APPLIED", null).getStatusCode().value()).isEqualTo(422);

        // ── paid: the College's Dean releases it with a comment; a Dean of a faculty in no College never acts ──
        payInFull(out, a1);
        assertThat(row(collegeDean, a1)).containsEntry("canApprove", true);
        assertThat(row(plainDean, a1)).containsEntry("canApprove", false).containsEntry("canDecline", false);
        ResponseEntity<Map> wrongDean = approve(plainDean, a1, "APPLIED", null);
        assertThat(wrongDean.getStatusCode().value()).as(String.valueOf(wrongDean.getBody())).isEqualTo(422);
        assertThat(wrongDean.getBody().get("code")).isEqualTo("TR_NOT_YOUR_STAGE");
        long hodToldBefore = noticesTo(hodAEmail, "A transfer application awaits you");
        ResponseEntity<Map> released = approve(collegeDean, a1, "APPLIED", "Released by the College: the student's case is sound");
        assertThat(released.getStatusCode().value()).as(String.valueOf(released.getBody())).isEqualTo(200);
        assertThat(released.getBody()).containsEntry("state", "FROM_OK");
        // a second press, read at the old state, never approves the next stage
        ResponseEntity<Map> again = approve(collegeDean, a1, "APPLIED", null);
        assertThat(again.getStatusCode().value()).isEqualTo(422);
        assertThat(again.getBody().get("code")).isEqualTo("TR_STATE_MOVED");
        // the receiving department's HOD is told it awaits them
        assertThat(noticesTo(hodAEmail, "A transfer application awaits you")).isEqualTo(hodToldBefore + 1);

        // ── the review: the profile, both sides' units, the history with the Dean's decision and comment, the desk now ──
        ResponseEntity<Map> rv = it.get(collegeDean, "/api/v1/transfers/" + a1);
        assertThat(rv.getStatusCode().value()).as(String.valueOf(rv.getBody())).isEqualTo(200);
        Map<String, Object> app = (Map<String, Object>) rv.getBody().get("application");
        assertThat(app).containsEntry("state", "FROM_OK").containsEntry("desk", "TO_DEPARTMENT").containsEntry("canApprove", false);
        assertThat(((Map<String, Object>) rv.getBody().get("student"))).containsEntry("matric_no", "MOAU/V734/" + n);
        List<Map<String, Object>> history = (List<Map<String, Object>>) rv.getBody().get("history");
        assertThat(history).extracting(h -> h.get("decision"), h -> h.get("desk"), h -> h.get("office"))
                .containsExactly(org.assertj.core.groups.Tuple.tuple("APPLIED", "STUDENT", "student"),
                        org.assertj.core.groups.Tuple.tuple("APPROVED", "FROM_DEPARTMENT", "dean"));
        assertThat(history.get(1)).containsEntry("note", "Released by the College: the student's case is sound");
        assertThat(String.valueOf(history.get(1).get("next_desk"))).startsWith("the new department");

        // ── the rest of the chain as before: the receiving HOD, the Registry, the Academic Office's final approval (paid in full) ──
        assertThat(approve(hodA, a1, "FROM_OK", null).getBody()).containsEntry("state", "TO_OK");
        assertThat(approve(registrar, a1, "TO_OK", null).getBody()).containsEntry("state", "REG_OK");
        assertThat(approve(academic, a1, "REG_OK", null).getBody()).containsEntry("state", "EFFECTED");
        assertThat(jdbc.sql("SELECT programme_code FROM people.student WHERE id = :s").param("s", out).query(String.class).single()).isEqualTo(pa);

        // ── into the College: the releasing HOD, then the College's Dean receives it; the Dean is told it awaits them ──
        payInFull(in, a2);
        long deanToldBefore = noticesTo(deanEmail, "A transfer application awaits you");
        assertThat(approve(hodA, a2, "APPLIED", null).getBody()).containsEntry("state", "FROM_OK");
        assertThat(noticesTo(deanEmail, "A transfer application awaits you")).isEqualTo(deanToldBefore + 1);
        assertThat(row(collegeDean, a2)).containsEntry("canApprove", true).containsEntry("desk", "TO_DEPARTMENT");
        // a decline needs its reason
        assertThat(it.call(collegeDean, HttpMethod.POST, "/api/v1/transfers/" + a2 + "/decline", Map.of("why", " ")).getStatusCode().value()).isEqualTo(400);
        ResponseEntity<Map> declined = it.call(collegeDean, HttpMethod.POST, "/api/v1/transfers/" + a2 + "/decline", Map.of("why", "No place in the College this session"));
        assertThat(declined.getStatusCode().value()).as(String.valueOf(declined.getBody())).isEqualTo(200);
        List<Map<String, Object>> h2 = (List<Map<String, Object>>) it.get(collegeDean, "/api/v1/transfers/" + a2).getBody().get("history");
        assertThat(h2.get(h2.size() - 1)).containsEntry("decision", "DECLINED").containsEntry("office", "dean").containsEntry("note", "No place in the College this session");

        // ── between departments of a faculty in no College: the HODs as before, no Dean ──
        payInFull(plain, a3);
        assertThat(row(plainDean, a3)).containsEntry("canApprove", false);
        assertThat(approve(hodA, a3, "APPLIED", null).getBody()).containsEntry("state", "FROM_OK");
        assertThat(approve(hodB, a3, "FROM_OK", null).getBody()).containsEntry("state", "TO_OK");

        // ── the student reads who holds it now ──
        Map<String, Object> view = it.get(student(plain), "/api/v1/me/transfer").getBody();
        Map<String, Object> live = ((List<Map<String, Object>>) view.get("applications")).get(0);
        assertThat(live).containsEntry("desk_label", "the Registry");
    }
}
