package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.ArrayList;
import java.util.HashMap;
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
 * The student lifecycle reconciliation (V558) over the API. With a current session on the calendar (a far-future one made current
 * for the test when none is, put back afterwards), five invented students on a four-year programme stand where their entry session
 * puts them: spillover year 1 and 2, the maximum spillover twice, and the final year. The recommendations come from the cohort
 * engine with their confidence and an explanation; a planned next session does not move anyone further into spillover. Only the
 * Registry reviews and reconciles; a low-confidence record is verified on its own, never in bulk; a batch is previewed, then
 * reconciled step by step — the spillover confirmed ACTIVE with the level raised, the maximum kept ACTIVE or made DORMANT on the
 * officer's choice, the final-year student put on the graduation list and left ACTIVE (the Senate approves), a recommendation that
 * changed since it was verified left out with the reason, a student never reconciled twice — and no matriculation number moves.
 * Corrections put the status, the level and the graduation-list entry back, once. A Head of Department elsewhere sees none of it.
 * Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class LifecycleReconciliationIT {

    private static final String PATH = "/api/v1/cohorts/lifecycle";

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    ItSupport it;
    String registrar = ItSupport.token("registrar");
    String current;
    boolean madeCurrent;

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
        current = jdbc.sql("SELECT name FROM policy.academic_session WHERE state = 'CURRENT'").query(String.class).optional().orElse(null);
        if (current == null) {
            // the test's own current session, far in the future, and the one planned after it
            it.session("2961/2962", 2961);
            it.session("2962/2963", 2962);
            it.db(() -> jdbc.sql("UPDATE policy.academic_session SET state = 'CURRENT', senate_minute = 'SEN/TEST/2961/01' WHERE name = '2961/2962'").update());
            current = "2961/2962";
            madeCurrent = true;
        }
    }

    @AfterEach
    void putBack() {
        if (madeCurrent) {
            it.db(() -> jdbc.sql("UPDATE policy.academic_session SET state = 'PLANNED', senate_minute = NULL WHERE name = '2961/2962' AND state = 'CURRENT'").update());
        }
    }

    /** the session k before the current one, as the calendar's arithmetic counts */
    private String before(int k) {
        int y = Integer.parseInt(current.substring(0, 4)) - k;
        return y + "/" + (y + 1);
    }

    private UUID student(String tag, String suffix, int entryBack, int level, boolean registered) {
        // no two-digit year in the number: the test's far-future entry session is the only evidence of the cohort
        String matric = it.freeNumber("MOAUM/MTC/LC" + suffix + "/", 6);
        UUID id = it.student(tag + suffix, "C00023", null, matric, level);
        it.db(() -> {
            jdbc.sql("UPDATE people.student SET entry_session = :e, entry_level = 100 WHERE id = :s").param("e", before(entryBack)).param("s", id).update();
            if (registered) {
                jdbc.sql("""
                        INSERT INTO registration.course_registration (id, student_id, session, semester, level, status, submitted_at)
                        VALUES (gen_random_uuid(), :s, :ses, 1, :l, 'SUBMITTED', now())
                        ON CONFLICT (student_id, session, semester) DO NOTHING
                        """).param("s", id).param("ses", current).param("l", level).update();
            }
            return null;
        });
        return id;
    }

    private Map<String, Object> row(UUID student) {
        ResponseEntity<Map> r = it.get(registrar, PATH + "/students/" + student);
        assertThat(r.getStatusCode().value()).as(String.valueOf(r.getBody())).isEqualTo(200);
        return r.getBody();
    }

    private static List<String> ids(UUID... students) {
        List<String> out = new ArrayList<>();
        for (UUID s : students) out.add(s.toString());
        return out;
    }

    private String matric(UUID student) {
        return jdbc.sql("SELECT matric_no FROM people.student WHERE id = :s").param("s", student).query(String.class).single();
    }

    @Test
    void recommendationsAreReviewedVerifiedReconciledInBatchesAndCorrected() {
        String tag = it.freeSurname("ZZLC");
        UUID sp1 = student(tag, "A", 4, 300, true);      // expected to complete last session: spillover year 1, at 300 Level on the record
        UUID sp2 = student(tag, "B", 5, 400, false);     // two sessions beyond, no registration on record: low confidence
        UUID max1 = student(tag, "C", 6, 400, true);     // three beyond, the limit is two
        UUID max2 = student(tag, "E", 6, 400, true);
        UUID fin = student(tag, "D", 3, 400, true);      // the final year
        UUID moved = student(tag, "F", 4, 400, true);    // verified as spillover year 1, then its record changes
        List<UUID> all = List.of(sp1, sp2, max1, max2, fin, moved);
        Map<UUID, String> matrics = new HashMap<>();
        for (UUID s : all) matrics.put(s, matric(s));
        it.db(() -> jdbc.sql("SELECT people.refresh_academic_positions(CAST(:ids AS uuid[]))").param("ids", ids(all.toArray(UUID[]::new)).toArray(String[]::new), java.sql.Types.ARRAY)
                .query(Integer.class).single());

        // the completion checked for the students at or beyond their programme's length
        ResponseEntity<Map> refreshed = it.call(registrar, HttpMethod.POST, PATH + "/refresh", Map.of("prog", "C00023"));
        assertThat(refreshed.getStatusCode().value()).as(String.valueOf(refreshed.getBody())).isEqualTo(200);
        assertThat(((Number) refreshed.getBody().get("checked")).intValue()).isGreaterThanOrEqualTo(6);

        // the recommendations, from the engine, with confidence and an explanation; a planned next session moves nobody
        Map<String, Object> a = row(sp1);
        assertThat(a.get("recommendation")).isEqualTo("SPILLOVER_YEAR_1");
        assertThat(a.get("confidence")).isEqualTo("HIGH");
        assertThat(a.get("spillover_years")).isEqualTo(1);
        assertThat((String) a.get("explanation")).contains("Entry session " + before(4)).contains("expected to complete in " + before(1))
                .contains("current session " + current).contains("1 session beyond the programme's length (the limit is 2)").contains("registered for " + current);
        assertThat(a.get("review_state")).isEqualTo("PENDING");
        Map<String, Object> b = row(sp2);
        assertThat(b.get("recommendation")).isEqualTo("SPILLOVER_YEAR_2");
        assertThat(b.get("confidence")).isEqualTo("LOW");
        assertThat((String) b.get("confidence_reasons")).contains("No course registration on record");
        assertThat(row(max1).get("recommendation")).isEqualTo("MAXIMUM_SPILLOVER_REACHED");
        Map<String, Object> d = row(fin);
        assertThat(d.get("recommendation")).isEqualTo("GRADUATION_CANDIDATE");
        assertThat(d.get("candidate_basis")).isEqualTo("FINAL_YEAR");

        // the figures, and the students behind each, names A–Z
        Map<String, Object> summary = it.get(registrar, PATH + "/summary?q=" + tag).getBody();
        assertThat(((Number) summary.get("total")).intValue()).isEqualTo(6);
        Map<String, Object> list = it.get(registrar, PATH + "/students?rec=SPILLOVER&q=" + tag).getBody();
        assertThat(((Number) list.get("total")).intValue()).isEqualTo(3);
        assertThat(((List<Map<String, Object>>) list.get("rows")).stream().map(r -> (String) r.get("surname")).toList())
                .containsExactly(tag + "A", tag + "B", tag + "F");

        // reading is bounded by scope; acting is the Registry's
        String otherDept = jdbc.sql("SELECT code FROM ref.department WHERE code <> 'MTC' ORDER BY code LIMIT 1").query(String.class).single();
        String hod = it.officer("hod", "department", otherDept);
        assertThat(((Number) it.get(hod, PATH + "/students?q=" + tag).getBody().get("total")).intValue()).isZero();
        assertThat(it.get(hod, PATH + "/students/" + sp1).getStatusCode().value()).isEqualTo(404);
        Map<String, Object> verifyAll = Map.of("studentIds", ids(sp1, sp2, max1, max2, fin, moved), "state", "VERIFIED");
        assertThat(it.call(hod, HttpMethod.POST, PATH + "/mark", verifyAll).getStatusCode().value()).isEqualTo(403);
        assertThat(it.call(ItSupport.token("ict"), HttpMethod.POST, PATH + "/mark", verifyAll).getStatusCode().value()).isEqualTo(403);
        assertThat(it.get(ItSupport.token("ict"), PATH + "/summary?q=" + tag).getStatusCode().value()).isEqualTo(200);
        assertThat(it.call(registrar, HttpMethod.POST, PATH + "/mark", Map.of("studentIds", ids(sp1), "state", "REJECTED")).getStatusCode().value()).isEqualTo(422);

        // verified in bulk — the low-confidence record held back, then verified on its own
        Map<String, Object> marked = it.call(registrar, HttpMethod.POST, PATH + "/mark", verifyAll).getBody();
        assertThat(((Number) marked.get("marked")).intValue()).as(String.valueOf(marked)).isEqualTo(5);
        assertThat(((Number) marked.get("low")).intValue()).isEqualTo(1);
        assertThat(row(sp2).get("review_state")).isEqualTo("PENDING");
        assertThat(((Number) it.call(registrar, HttpMethod.POST, PATH + "/mark", Map.of("studentIds", ids(sp2), "state", "VERIFIED", "single", true))
                .getBody().get("marked")).intValue()).isEqualTo(1);
        assertThat(row(sp2).get("review_state")).isEqualTo("VERIFIED");

        // the preview writes nothing; at the maximum the officer must choose
        Map<String, Object> blind = it.call(registrar, HttpMethod.POST, PATH + "/preview", Map.of("studentIds", ids(sp1, sp2, max1, fin, moved))).getBody();
        assertThat(((Number) blind.get("eligible")).intValue()).isEqualTo(4);
        assertThat(((Map<String, Object>) blind.get("excluded")).get("LIMIT_OUTCOME_NOT_CHOSEN")).isEqualTo(1);
        Map<String, Object> preview = it.call(registrar, HttpMethod.POST, PATH + "/preview",
                Map.of("studentIds", ids(sp1, sp2, max1, fin, moved), "limitOutcome", "KEPT_ACTIVE_LIMIT_REACHED")).getBody();
        assertThat(((Number) preview.get("eligible")).intValue()).isEqualTo(5);
        assertThat(((Number) preview.get("toGraduationList")).intValue()).isEqualTo(1);
        assertThat(((Number) preview.get("levelsRaised")).intValue()).isEqualTo(1);
        assertThat(jdbc.sql("SELECT count(*) FROM people.lifecycle_reconciliation WHERE student_id = ANY (CAST(:ids AS uuid[]))")
                .param("ids", ids(all.toArray(UUID[]::new)).toArray(String[]::new), java.sql.Types.ARRAY).query(Long.class).single()).isZero();

        // the record of one student moves after it was verified: three sessions beyond now, not one
        it.db(() -> jdbc.sql("UPDATE people.student SET entry_session = :e WHERE id = :s").param("e", before(6)).param("s", moved).update());

        // a batch, reconciled in one step; the student whose recommendation changed is left out with the reason
        ResponseEntity<Map> opened = it.call(registrar, HttpMethod.POST, PATH + "/batches", Map.of("description", "Integration test: spillover and graduation candidates"));
        assertThat(opened.getStatusCode().value()).as(String.valueOf(opened.getBody())).isEqualTo(200);
        String ref = (String) opened.getBody().get("batch_ref");
        assertThat(ref).matches("RECON/[0-9]{4}/[0-9]{6}");
        String batchPath = PATH + "/batches/" + ref.substring("RECON/".length());
        assertThat(it.call(ItSupport.token("registrar"), HttpMethod.POST, batchPath + "/reconcile",
                Map.of("studentIds", ids(sp1), "reason", "not mine")).getBody().get("skipped").toString()).contains("LIFECYCLE_BATCH_OWNER");
        Map<String, Object> step = it.call(registrar, HttpMethod.POST, batchPath + "/reconcile", Map.of("studentIds", (List<String>) preview.get("studentIds"),
                "limitOutcome", "KEPT_ACTIVE_LIMIT_REACHED", "reason", "Registry review of the 2nd semester registrations")).getBody();
        assertThat(((Number) step.get("reconciled")).intValue()).as(String.valueOf(step)).isEqualTo(4);
        List<Map<String, Object>> skipped = (List<Map<String, Object>>) step.get("skipped");
        assertThat(skipped).hasSize(1);
        assertThat(skipped.get(0).get("id")).isEqualTo(moved.toString());
        assertThat(skipped.get(0).get("code")).isEqualTo("LIFECYCLE_CHANGED");

        // spillover confirmed: ACTIVE, the level raised to the final level, the decision on the history
        Map<String, Object> s1 = jdbc.sql("SELECT status, current_level FROM people.student WHERE id = :s").param("s", sp1).query().singleRow();
        assertThat(s1.get("status")).isEqualTo("ACTIVE");
        assertThat(s1.get("current_level")).isEqualTo(400);
        assertThat(jdbc.sql("SELECT rule || ':' || previous_level || '>' || new_level || ':' || batch_ref FROM people.cohort_decision WHERE student_id = :s ORDER BY decided_at DESC LIMIT 1")
                .param("s", sp1).query(String.class).single()).isEqualTo("LIFECYCLE_SPILLOVER_YEAR_1:300>400:" + ref);
        assertThat(row(sp1).get("review_state")).isEqualTo("RECONCILED");
        // the maximum kept ACTIVE, flagged by its outcome
        assertThat(jdbc.sql("SELECT outcome || ':' || new_status FROM people.lifecycle_reconciliation WHERE student_id = :s").param("s", max1).query(String.class).single())
                .isEqualTo("KEPT_ACTIVE_LIMIT_REACHED:ACTIVE");
        // the final-year student on the graduation list for the session, audited, still ACTIVE: the Senate approves
        Map<String, Object> g = jdbc.sql("SELECT senate_state, unmet FROM records.graduand WHERE student_id = :s AND session = :ses").param("s", fin).param("ses", current).query().singleRow();
        assertThat(g.get("senate_state")).isEqualTo("AWAITING");
        assertThat(g.get("unmet")).isEqualTo("No published result on the record");
        assertThat(jdbc.sql("SELECT status FROM people.student WHERE id = :s").param("s", fin).query(String.class).single()).isEqualTo("ACTIVE");
        assertThat(jdbc.sql("SELECT graduand_added FROM people.lifecycle_reconciliation WHERE student_id = :s").param("s", fin).query(Boolean.class).single()).isTrue();

        // never twice in a session
        Map<String, Object> again = it.call(registrar, HttpMethod.POST, batchPath + "/reconcile", Map.of("studentIds", ids(sp1), "reason", "again")).getBody();
        assertThat(((Map<String, Object>) ((List) again.get("skipped")).get(0)).get("code")).isEqualTo("LIFECYCLE_ALREADY");
        assertThat(((Number) it.call(registrar, HttpMethod.POST, batchPath + "/close", Map.of()).getBody().get("reconciled")).intValue()).isEqualTo(4);

        // a second batch: the officer chooses DORMANT for the other student at the maximum
        String ref2 = (String) it.call(registrar, HttpMethod.POST, PATH + "/batches", Map.of("description", "Integration test: dormant at the maximum")).getBody().get("batch_ref");
        Map<String, Object> step2 = it.call(registrar, HttpMethod.POST, PATH + "/batches/" + ref2.substring("RECON/".length()) + "/reconcile",
                Map.of("studentIds", ids(max2), "limitOutcome", "STATUS_CHANGED", "limitStatus", "DORMANT", "reason", "No registration since; Registry letter REG/TEST/1")).getBody();
        assertThat(((Number) step2.get("reconciled")).intValue()).as(String.valueOf(step2)).isEqualTo(1);
        assertThat(jdbc.sql("SELECT status FROM people.student WHERE id = :s").param("s", max2).query(String.class).single()).isEqualTo("DORMANT");
        assertThat(jdbc.sql("SELECT from_status || '>' || to_status FROM people.status_change WHERE student_id = :s ORDER BY effective_on DESC, id DESC LIMIT 1")
                .param("s", max2).query(String.class).single()).isEqualTo("ACTIVE>DORMANT");
        assertThat(it.call(registrar, HttpMethod.POST, PATH + "/preview", Map.of("studentIds", ids(max2), "limitOutcome", "STATUS_CHANGED", "limitStatus", "GRADUATED"))
                .getStatusCode().value()).isEqualTo(422);

        // no matriculation number moved, nobody graduated
        for (UUID s : all) assertThat(matric(s)).isEqualTo(matrics.get(s));
        assertThat(jdbc.sql("SELECT count(*) FROM people.student WHERE id = ANY (CAST(:ids AS uuid[])) AND status = 'GRADUATED'")
                .param("ids", ids(all.toArray(UUID[]::new)).toArray(String[]::new), java.sql.Types.ARRAY).query(Long.class).single()).isZero();

        // the history and the batches
        Map<String, Object> history = it.get(registrar, PATH + "/history?q=" + tag).getBody();
        assertThat(((Number) history.get("total")).intValue()).as(String.valueOf(history)).isEqualTo(5);
        List<Map<String, Object>> batches = it.getList(registrar, PATH + "/batches").getBody();
        assertThat(batches.stream().filter(x -> ref.equals(x.get("batch_ref"))).findFirst().orElseThrow().get("graduation_list")).isEqualTo(1);

        // corrections: the status, the level and the graduation-list entry put back — once
        UUID recDormant = jdbc.sql("SELECT id FROM people.lifecycle_reconciliation WHERE student_id = :s").param("s", max2).query(UUID.class).single();
        UUID recLevel = jdbc.sql("SELECT id FROM people.lifecycle_reconciliation WHERE student_id = :s").param("s", sp1).query(UUID.class).single();
        UUID recList = jdbc.sql("SELECT id FROM people.lifecycle_reconciliation WHERE student_id = :s").param("s", fin).query(UUID.class).single();
        assertThat(it.call(registrar, HttpMethod.POST, PATH + "/reconciliations/" + recDormant + "/correct", Map.of("reason", "")).getStatusCode().value()).isEqualTo(400);
        for (UUID r : List.of(recDormant, recLevel, recList)) {
            ResponseEntity<Map> c = it.call(registrar, HttpMethod.POST, PATH + "/reconciliations/" + r + "/correct", Map.of("reason", "Reconciled in error; the file was misread"));
            assertThat(c.getStatusCode().value()).as(String.valueOf(c.getBody())).isEqualTo(200);
        }
        assertThat(jdbc.sql("SELECT status FROM people.student WHERE id = :s").param("s", max2).query(String.class).single()).isEqualTo("ACTIVE");
        assertThat(jdbc.sql("SELECT current_level FROM people.student WHERE id = :s").param("s", sp1).query(Integer.class).single()).isEqualTo(300);
        assertThat(jdbc.sql("SELECT count(*) FROM records.graduand WHERE student_id = :s").param("s", fin).query(Long.class).single()).isZero();
        assertThat(jdbc.sql("SELECT corrected_at IS NOT NULL AND level_restored FROM people.lifecycle_reconciliation WHERE id = :r").param("r", recLevel).query(Boolean.class).single()).isTrue();
        assertThat(row(sp1).get("review_state")).isEqualTo("UNDER_REVIEW");
        ResponseEntity<Map> twice = it.call(registrar, HttpMethod.POST, PATH + "/reconciliations/" + recLevel + "/correct", Map.of("reason", "again"));
        assertThat(twice.getStatusCode().value()).isEqualTo(422);
        assertThat(twice.getBody().get("code")).isEqualTo("LIFECYCLE_CORRECTED");
        for (UUID s : all) assertThat(matric(s)).isEqualTo(matrics.get(s));
    }
}
