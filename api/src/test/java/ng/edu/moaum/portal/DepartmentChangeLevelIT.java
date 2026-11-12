package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

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
 * V730: the department-change hold of V696 released — the University's word of 12 November 2026: a student who changed department
 * continues from the level reached; a step down for weak results is an office's decision, and every reader follows it. Four sessions
 * of the test's own, the last made CURRENT (an IT database has none) and put back. Two programmes in two departments. X entered two
 * sessions before the current one and is at 300 Level, the level the entry cohort reaches; Y entered three before and is at 300, a
 * level behind it. An academic transfer moves each into the other department at 300: X keeps 300 and no cohort is set; Y keeps 300
 * and is given the cohort that reaches it (COHORT_LEVEL_REACHED), so the receipt reads 300, not the 400 counted from entry. The level
 * desk offers X the next level and carries no hold; a step down the desk makes for X (300 to 200) sets the cohort for the level
 * reached, and the receipt and the level in the session read 200; raised back to 300, the cohort is lifted; progressed to 400, the
 * level stands. Nothing writes a hold's decision. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class DepartmentChangeLevelIT {

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    ItSupport it;
    final String registrar = ItSupport.token("registrar");

    /** an ICT support agent on the level desk (as StudentLevelSupportIT makes one) */
    private String agent(String tag) {
        UUID p = it.person("ZZ-DCLV-" + tag, "ZZDCLV" + tag);
        it.db(() -> jdbc.sql("""
                INSERT INTO iam.office_assignment (id, person_id, office_code, scope_kind, scope_id, instrument, granted_by, valid_from)
                VALUES (gen_random_uuid(), :p, 'ictagent', 'platform', NULL, 'integration test', :p, current_date)
                """).param("p", p).update());
        return TestTokens.token(p, List.of("ictagent"));
    }

    private Map<String, Object> options(String agent, UUID student) {
        ResponseEntity<Map> read = it.get(agent, "/api/v1/helpdesk/support/students/" + student + "/level");
        assertThat(read.getStatusCode().value()).as(String.valueOf(read.getBody())).isEqualTo(200);
        return (Map<String, Object>) read.getBody().get("options");
    }

    private Map<String, Object> change(String agent, UUID student, Map<String, Object> body) {
        ResponseEntity<Map> r = it.call(agent, HttpMethod.POST, "/api/v1/helpdesk/support/students/" + student + "/level", body);
        assertThat(r.getStatusCode().value()).as(String.valueOf(r.getBody())).isEqualTo(200);
        return r.getBody();
    }

    /** the cohort desk's view of the student: the effective cohort, its source, the override and the decisions */
    private Map<String, Object> cohort(UUID student) {
        ResponseEntity<Map> r = it.get(registrar, "/api/v1/cohorts/students/" + student);
        assertThat(r.getStatusCode().value()).as(String.valueOf(r.getBody())).isEqualTo(200);
        return r.getBody();
    }

    private static List<Object> rules(Map<String, Object> cohortView) {
        return ((List<Map<String, Object>>) cohortView.get("decisions")).stream().map(d -> d.get("rule")).toList();
    }

    private int record(UUID student) {
        return jdbc.sql("SELECT current_level FROM people.student WHERE id = :s").param("s", student).query(Integer.class).single();
    }

    private int receiptLevel(UUID student, String session) {
        return jdbc.sql("SELECT people.receipt_level(:s, :ses)").param("s", student).param("ses", session).query(Integer.class).single();
    }

    private int levelIn(UUID student, String session) {
        return jdbc.sql("SELECT people.level_in(:s, :ses)").param("s", student).param("ses", session).query(Integer.class).single();
    }

    /** the hold's decisions (V696, V702): none is written any more */
    private long holdDecisions(UUID student) {
        return jdbc.sql("""
                SELECT count(*) FROM people.cohort_decision
                 WHERE student_id = :s AND rule IN ('COHORT_DEPARTMENT_CHANGE', 'LEVEL_DEPARTMENT_CHANGE', 'LEVEL_HELD_DEPARTMENT_CHANGE')
                """).param("s", student).query(Long.class).single();
    }

    private long overrides(UUID student) {
        return jdbc.sql("SELECT count(*) FROM people.cohort_override WHERE student_id = :s").param("s", student).query(Long.class).single();
    }

    @Test
    void aStudentWhoChangedDepartmentContinuesFromTheLevelReachedAndAStepDownIsTheOfficesDecision() {
        it = new ItSupport(port, jdbc, transactions);
        int y = it.freeYear(9800, 9960, 0, 3);
        String s0 = y + "/" + (y + 1), s1 = (y + 1) + "/" + (y + 2), s2 = (y + 2) + "/" + (y + 3), s3 = (y + 3) + "/" + (y + 4);
        for (int i = 0; i <= 3; i++) {
            it.session((y + i) + "/" + (y + i + 1), y + i);
        }
        String s3State = jdbc.sql("SELECT state FROM policy.academic_session WHERE name = :n").param("n", s3).query(String.class).single();
        String previousCurrent = jdbc.sql("SELECT name FROM policy.academic_session WHERE state = 'CURRENT' ORDER BY starts_on DESC LIMIT 1")
                .query(String.class).optional().orElse(null);
        try {
            it.db(() -> {
                jdbc.sql("UPDATE policy.academic_session SET state = 'CLOSED' WHERE state = 'CURRENT'").update();
                return jdbc.sql("UPDATE policy.academic_session SET state = 'CURRENT', senate_minute = coalesce(senate_minute, 'SEN/IT/730') WHERE name = :n")
                        .param("n", s3).update();
            });

            // ── two programmes of the test's own, in two live departments of a faculty ──
            String[] place = it.db(() -> {
                String[] one = jdbc.sql("""
                        SELECT p1.dept_code || ',' || p2.dept_code || ',' || p1.faculty_code
                          FROM ref.programme p1 JOIN ref.programme p2 ON p2.faculty_code = p1.faculty_code AND p2.dept_code > p1.dept_code
                          JOIN ref.faculty f ON f.code = p1.faculty_code
                          JOIN ref.department d1 ON d1.code = p1.dept_code AND d1.ended_on IS NULL
                          JOIN ref.department d2 ON d2.code = p2.dept_code AND d2.ended_on IS NULL
                         WHERE p1.category = 'UNDER GRADUATE' AND p2.category = 'UNDER GRADUATE' AND NOT p1.archived AND NOT p2.archived
                           AND coalesce(f.college_code, '') <> 'CHS'
                         ORDER BY p1.faculty_code, p1.dept_code, p2.dept_code LIMIT 1
                        """).query(String.class).single().split(",");
                List<String> codes = jdbc.sql("SELECT 'C' || x FROM generate_series(95500, 95999) x WHERE NOT EXISTS (SELECT 1 FROM ref.programme p WHERE p.code = 'C' || x) ORDER BY random() LIMIT 2")
                        .query(String.class).list();
                jdbc.sql("""
                        INSERT INTO ref.programme (code, name, dept_code, faculty_code, category, min_score, final_level, duration_years) VALUES
                            (:a, 'B.Sc. Department Change Test A ' || :a, :da, :f, 'UNDER GRADUATE', 0, 400, 4),
                            (:b, 'B.Sc. Department Change Test B ' || :b, :db, :f, 'UNDER GRADUATE', 0, 400, 4)
                        """).param("a", codes.get(0)).param("b", codes.get(1)).param("da", one[0]).param("db", one[1]).param("f", one[2]).update();
                return new String[] {codes.get(0), codes.get(1)};
            });
            String pa = place[0], pb = place[1];

            // ── X entered s1 and Y s0, both at 300 Level in s3; a matric that names no department ──
            int n = it.freeDraw(1000, 9999, k -> List.of("MOAUM/DCL/86/1" + k, "MOAUM/DCL/86/2" + k, "MOAUM/ADM/86/61" + k, "MOAUM/ADM/86/62" + k,
                    "ZZDCLVX" + k, "ZZDCLVY" + k));
            UUID x = it.student("ZZDCLVX" + n, pa, "MOAUM/ADM/86/61" + n, "MOAUM/DCL/86/1" + n, 300);
            UUID yy = it.student("ZZDCLVY" + n, pa, "MOAUM/ADM/86/62" + n, "MOAUM/DCL/86/2" + n, 300);
            String ref = "MOAUM-FEE-" + n + "-0730";
            it.db(() -> {
                jdbc.sql("UPDATE people.student SET entry_session = :e WHERE id = :s").param("e", s1).param("s", x).update();
                jdbc.sql("UPDATE people.student SET entry_session = :e WHERE id = :s").param("e", s0).param("s", yy).update();
                // X's school fees for s3, paid: the receipt the student prints
                return jdbc.sql("""
                        INSERT INTO finance.payment_reference (student_id, session, reference, purpose, amount, expires_at, confirmed_at, confirmed_by, channel, receipt_no, note)
                        VALUES (:s, :ses, :r, 'School fees', 28605, now() + interval '1 day', now(), gen_random_uuid(), 'INTERSWITCH', 'RCT-' || :r, 'V730 test')
                        """).param("s", x).param("ses", s3).param("r", ref).update();
            });
            for (UUID s : List.of(x, yy)) {
                jdbc.sql("SELECT people.refresh_academic_position(:s)").param("s", s).query().listOfRows();
            }
            String studentTok = TestTokens.token(x, List.of("student"));
            String academic = TestTokens.token(it.person("ZZ-DCLV-AC" + n, "ZZDCLVAC" + n), List.of("academic"));
            String agent = agent("A" + n);

            // ── (c) an academic transfer into the other department at the student's level: the level kept ──
            for (UUID s : List.of(x, yy)) {
                Map<String, Object> body = new HashMap<>(Map.of("studentId", s.toString(), "toProgramme", pb, "toLevel", 300, "session", s3,
                        "kind", "ACADEMIC_TRANSFER", "reason", "Transfer approved by the Senate Admissions Committee (integration test)"));
                ResponseEntity<Map> moved = it.call(academic, HttpMethod.POST, "/api/v1/programme-swaps", body);
                assertThat(moved.getStatusCode().value()).as(String.valueOf(moved.getBody())).isEqualTo(200);
                assertThat(moved.getBody()).containsEntry("status", "COMPLETED").containsEntry("to_programme", pb);
                assertThat(jdbc.sql("SELECT programme_code || '/' || current_level FROM people.student WHERE id = :s").param("s", s).query(String.class).single())
                        .isEqualTo(pb + "/300");
                assertThat(holdDecisions(s)).isZero();
            }
            assertThat(jdbc.sql("SELECT people.department_changed(:s)").param("s", x).query(Boolean.class).single()).isTrue();
            // X is at the level the entry cohort reaches: no cohort set
            Map<String, Object> cx = cohort(x);
            assertThat(cx.get("override")).isNull();
            assertThat(cx).containsEntry("cohort_source", "ENTRY").containsEntry("effective_cohort", s1);
            assertThat(rules(cx)).doesNotContain("COHORT_LEVEL_REACHED", "COHORT_DEPARTMENT_CHANGE");
            assertThat(receiptLevel(x, s3)).isEqualTo(300);
            assertThat(it.get(studentTok, "/api/v1/me/fees/receipts/" + ref).getBody()).containsEntry("session", s3).containsEntry("level", 300);
            // Y is a level behind it: the cohort that reaches the record, so no reader adds the year the count from entry would
            Map<String, Object> cy = cohort(yy);
            assertThat((Map<String, Object>) cy.get("override")).containsEntry("effective_cohort", s1);
            assertThat(cy).containsEntry("cohort_source", "OVERRIDE").containsEntry("effective_cohort", s1);
            assertThat(rules(cy)).contains("COHORT_LEVEL_REACHED");
            assertThat(receiptLevel(yy, s3)).isEqualTo(300);
            assertThat(levelIn(yy, s3)).isEqualTo(300);

            // ── (a) the level desk offers X the next level; no hold is read ──
            Map<String, Object> ox = options(agent, x);
            assertThat(ox).doesNotContainKey("heldAt");
            assertThat(ox).containsEntry("currentLevel", 300).containsEntry("nextLevel", 400).containsEntry("currentSession", s3);
            assertThat(ox.get("progressRefusal")).isNull();
            assertThat(ox.get("otherLevels")).isEqualTo(List.of(100, 200, 400));

            // ── (d) a step down the desk decides for weak results: the cohort set for the level reached, every reader reads 200 ──
            Map<String, Object> down = change(agent, x, Map.of("action", "CORRECTION", "level", 200, "expected", 300,
                    "reason", "Results not good enough to continue at 300 Level in the new department (integration test)"));
            assertThat(down).containsEntry("previousLevel", 300).containsEntry("newLevel", 200).containsEntry("action", "LEVEL_CORRECTION");
            assertThat(record(x)).isEqualTo(200);
            Map<String, Object> after = (Map<String, Object>) ((Map<String, Object>) down.get("view")).get("options");
            assertThat(after).containsEntry("currentLevel", 200).containsEntry("nextLevel", 300).doesNotContainKey("heldAt");
            Map<String, Object> stepped = cohort(x);
            assertThat((Map<String, Object>) stepped.get("override")).containsEntry("effective_cohort", s2);
            assertThat(stepped).containsEntry("cohort_source", "OVERRIDE").containsEntry("effective_cohort", s2);
            assertThat(((List<Map<String, Object>>) stepped.get("decisions"))).anySatisfy(d ->
                    assertThat(d).containsEntry("rule", "COHORT_LEVEL_REACHED").containsEntry("effective_cohort", s2));
            assertThat(receiptLevel(x, s3)).isEqualTo(200);
            assertThat(levelIn(x, s3)).isEqualTo(200);
            assertThat(it.get(studentTok, "/api/v1/me/fees/receipts/" + ref).getBody()).containsEntry("level", 200);

            // ── (e) raised back: the cohort lifted, the count from entry stands again ──
            Map<String, Object> back = change(agent, x, Map.of("action", "CORRECTION", "level", 300, "expected", 200,
                    "reason", "Passed the resit: the Board restores 300 Level (integration test)"));
            assertThat(back).containsEntry("newLevel", 300);
            assertThat(overrides(x)).isZero();
            Map<String, Object> lifted = cohort(x);
            assertThat(lifted.get("override")).isNull();
            assertThat(lifted).containsEntry("cohort_source", "ENTRY").containsEntry("effective_cohort", s1);
            assertThat(rules(lifted)).contains("COHORT_LEVEL_REACHED_LIFTED");
            assertThat(receiptLevel(x, s3)).isEqualTo(300);
            assertThat(levelIn(x, s3)).isEqualTo(300);
            assertThat(it.get(studentTok, "/api/v1/me/fees/receipts/" + ref).getBody()).containsEntry("level", 300);

            // ── (b) the desk progresses X to 400: it stands, nothing clamps it ──
            Map<String, Object> up = change(agent, x, Map.of("action", "PROGRESS", "expected", 300, "reason", "Promoted on the session's results (integration test)"));
            assertThat(up).containsEntry("previousLevel", 300).containsEntry("newLevel", 400).containsEntry("action", "LEVEL_PROGRESS");
            assertThat(record(x)).isEqualTo(400);
            assertThat(overrides(x)).isZero();
            // Y progressed to 400: a progression is the next session's level (V673), so this session stays at 300 and Y stays a session
            // behind the entry cohort — the cohort set for the level reached stands, aligned against the session the level is for
            assertThat(options(agent, yy)).containsEntry("nextLevel", 400).doesNotContainKey("heldAt");
            change(agent, yy, Map.of("action", "PROGRESS", "expected", 300, "reason", "Promoted on the session's results (integration test)"));
            assertThat(record(yy)).isEqualTo(400);
            assertThat(overrides(yy)).isEqualTo(1L);
            assertThat(cohort(yy)).containsEntry("cohort_source", "OVERRIDE").containsEntry("effective_cohort", s1);
            assertThat(rules(cohort(yy))).doesNotContain("COHORT_LEVEL_REACHED_LIFTED");
            assertThat(receiptLevel(yy, s3)).isEqualTo(300);
            for (UUID s : List.of(x, yy)) {
                assertThat(holdDecisions(s)).isZero();
            }
        } finally {
            it.db(() -> {
                jdbc.sql("UPDATE policy.academic_session SET state = :st WHERE name = :n").param("st", s3State).param("n", s3).update();
                if (previousCurrent != null && !previousCurrent.equals(s3)) {
                    jdbc.sql("UPDATE policy.academic_session SET state = 'CURRENT' WHERE name = :n").param("n", previousCurrent).update();
                }
                return null;
            });
        }
    }
}
