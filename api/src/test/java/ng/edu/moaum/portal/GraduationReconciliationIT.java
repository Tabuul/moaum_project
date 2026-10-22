package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.List;
import java.util.Map;
import java.util.UUID;

import ng.edu.moaum.portal.graduation.GraduationReconciliationController;

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
 * V638: students outside the maximum academic period graduated by status reconciliation, over the API. A four-year programme of
 * the test's own (its length set) and three students: one admitted long enough ago to be past the programme's length plus the
 * configured spillover, with a final-year registration on record (HIGH); one the same with no registration (MEDIUM); one admitted
 * two sessions ago (not a candidate). The review reads the timeline; the preview writes nothing and counts identified, eligible and
 * requiring review; ICT is refused the act; the batch is executed by its officer only, graduates the HIGH student alone (MEDIUM left
 * for review unless included), never twice — status GRADUATED with its history, final clearance started, the student told, the
 * record closed to fees from the session after the last permitted one; the official date is confirmed afterwards; a dean of another
 * faculty cannot read the student; the report counts the graduate; the automatic setting is ICT's or the Registrar's, and the
 * nightly run does nothing while it is off; the Registrar's correction puts the status back and marks the reconciliation corrected.
 * Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class GraduationReconciliationIT {

    private static final String PATH = "/api/v1/graduation/reconciliation";
    private static final String PROGRAMME = "C96380";

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;
    @Autowired
    GraduationReconciliationController controller;

    ItSupport it;
    final String academic = ItSupport.token("academic");
    final String registrar = ItSupport.token("registrar");
    final String ict = ItSupport.token("ict");
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
        it.db(() -> jdbc.sql("UPDATE policy.progression_setting SET auto_graduation = false WHERE row_no").update());
        if (madeCurrent) {
            it.db(() -> jdbc.sql("UPDATE policy.academic_session SET state = 'PLANNED', senate_minute = NULL WHERE name = '2961/2962' AND state = 'CURRENT'").update());
        }
    }

    /** the session k before the current one, as the calendar's arithmetic counts */
    private String before(int k) {
        int y = Integer.parseInt(current.substring(0, 4)) - k;
        return y + "/" + (y + 1);
    }

    private UUID student(String tag, int entryBack, String finalYear) {
        // no two-digit year in the number: the test's far-future entry session is the only evidence of the cohort
        String matric = it.freeNumber("MOAUM/MTC/GR" + tag + "/", 6);
        UUID id = it.student("ZZGRADRECON" + tag, PROGRAMME, null, matric, 400);
        it.session(before(entryBack), Integer.parseInt(before(entryBack).substring(0, 4)));
        if (finalYear != null) it.session(finalYear, Integer.parseInt(finalYear.substring(0, 4)));
        it.db(() -> {
            jdbc.sql("UPDATE people.student SET entry_session = :e, entry_level = 100, status = 'ACTIVE' WHERE id = :s").param("e", before(entryBack)).param("s", id).update();
            if (finalYear != null) {
                jdbc.sql("""
                        INSERT INTO registration.course_registration (id, student_id, session, semester, level, status, submitted_at, approved_at)
                        VALUES (gen_random_uuid(), :s, :ses, 1, 400, 'APPROVED', now(), now())
                        ON CONFLICT (student_id, session, semester) DO NOTHING
                        """).param("s", id).param("ses", finalYear).update();
            }
            return jdbc.sql("SELECT people.refresh_academic_positions(ARRAY[CAST(:s AS uuid)])").param("s", id).query(Integer.class).single();
        });
        return id;
    }

    private String status(UUID id) {
        return jdbc.sql("SELECT status FROM people.student WHERE id = :id").param("id", id).query(String.class).single();
    }

    @Test
    void aStudentOutsideTheMaximumPeriodIsGraduatedByStatusReconciliationOnceAndTheRecordIsKept() {
        int max = jdbc.sql("SELECT max_spillover_years FROM policy.progression_setting WHERE row_no").query(Integer.class).single();
        it.db(() -> {
            String dept = jdbc.sql("SELECT dept_code FROM ref.programme WHERE code = 'C00023'").query(String.class).single();
            String fac = jdbc.sql("SELECT faculty_code FROM ref.programme WHERE code = 'C00023'").query(String.class).single();
            return jdbc.sql("""
                    INSERT INTO ref.programme (code, name, dept_code, faculty_code, category, min_score, final_level, duration_years)
                    VALUES (:c, 'B.Sc. Graduation Reconciliation Test', :d, :f, 'UNDER GRADUATE', 0, 400, 4)
                    ON CONFLICT (code) DO UPDATE SET final_level = 400, duration_years = 4, archived = false
                    """).param("c", PROGRAMME).param("d", dept).param("f", fac).update();
        });
        // admitted (3 + max + 2) sessions ago: expected completion 3 sessions after entry, then max + 2 sessions beyond it
        int back = 3 + max + 2;
        UUID high = student("H", back, before(back - 2));
        UUID medium = student("M", back, null);
        UUID within = student("W", 2, null);

        // the review: the timeline the engine computed, and the confidence for this rule
        ResponseEntity<Map> review = it.get(academic, PATH + "/students/" + high);
        assertThat(review.getStatusCode().value()).as(String.valueOf(review.getBody())).isEqualTo(200);
        Map<String, Object> cand = (Map<String, Object>) review.getBody().get("candidate");
        assertThat(cand).containsEntry("confidence", "HIGH").containsEntry("entry_session", before(back)).containsEntry("expected_completion", before(back - 3))
                .containsEntry("maximum_session", before(back - 3 - max)).containsEntry("current_session", current).containsEntry("duration_years", 4);
        assertThat(((Map<String, Object>) it.get(academic, PATH + "/students/" + medium).getBody().get("candidate"))).containsEntry("confidence", "MEDIUM");
        assertThat(it.get(academic, PATH + "/students/" + within).getBody().get("candidate")).isNull();
        // a dean of another faculty cannot read the student at all
        String otherFaculty = jdbc.sql("SELECT code FROM ref.faculty WHERE code <> (SELECT faculty_code FROM ref.programme WHERE code = :c) ORDER BY code LIMIT 1")
                .param("c", PROGRAMME).query(String.class).single();
        assertThat(it.get(it.officer("dean", "faculty", otherFaculty), PATH + "/students/" + high).getStatusCode().value()).isEqualTo(404);

        // the preview writes nothing: two identified, one eligible, one requiring review (MEDIUM not included)
        List<String> chosen = List.of(high.toString(), medium.toString(), within.toString());
        ResponseEntity<Map> preview = it.call(academic, HttpMethod.POST, PATH + "/preview", Map.of("studentIds", chosen, "includeMedium", false));
        assertThat(preview.getStatusCode().value()).as(String.valueOf(preview.getBody())).isEqualTo(200);
        assertThat(preview.getBody()).containsEntry("identified", 2).containsEntry("eligible", 1).containsEntry("review", 1).containsEntry("high", 1).containsEntry("medium", 1);
        assertThat(status(high)).isEqualTo("ACTIVE");
        // ICT reads; it does not reconcile
        assertThat(it.call(ict, HttpMethod.POST, PATH + "/preview", Map.of("studentIds", chosen)).getStatusCode().value()).isEqualTo(403);
        assertThat(it.call(ict, HttpMethod.POST, PATH + "/batches", Map.of("description", "ICT tries", "studentIds", chosen)).getStatusCode().value()).isEqualTo(403);

        // the batch, executed by its officer only
        ResponseEntity<Map> opened = it.call(academic, HttpMethod.POST, PATH + "/batches",
                Map.of("description", "Integration test: students outside the maximum academic period", "studentIds", chosen, "includeMedium", false));
        assertThat(opened.getStatusCode().value()).as(String.valueOf(opened.getBody())).isEqualTo(200);
        String ref = String.valueOf(opened.getBody().get("batch_ref"));
        assertThat(ref).matches("GRAD-RECON/[0-9]{4}/[0-9]{6}");
        assertThat(opened.getBody()).containsEntry("mode", "MANUAL").containsEntry("selected", 2).containsEntry("eligible", 1).containsEntry("review", 1).containsEntry("min_confidence", "HIGH");
        String batchPath = PATH + "/batches/" + ref.substring("GRAD-RECON/".length());
        assertThat(it.call(registrar, HttpMethod.POST, batchPath + "/run", Map.of()).getBody()).containsEntry("code", "GRADRECON_BATCH_OWNER");
        ResponseEntity<Map> run = it.call(academic, HttpMethod.POST, batchPath + "/run", Map.of("reason", "Integration test: exceeded the maximum academic period"));
        assertThat(run.getStatusCode().value()).as(String.valueOf(run.getBody())).isEqualTo(200);
        assertThat(run.getBody()).containsEntry("graduated", 1).containsEntry("remaining", 0).containsEntry("done", true);
        assertThat(status(high)).isEqualTo("GRADUATED");
        assertThat(status(medium)).isEqualTo("ACTIVE");
        assertThat(status(within)).isEqualTo("ACTIVE");
        assertThat(jdbc.sql("SELECT count(*) FROM people.status_change WHERE student_id = :id AND to_status = 'GRADUATED' AND instrument = :i")
                .param("id", high).param("i", "Graduation reconciliation " + ref).query(Long.class).single()).isEqualTo(1L);
        assertThat(jdbc.sql("SELECT count(*) FROM clearance.process WHERE workflow = 'FINAL' AND student_id = :id AND cancelled_at IS NULL").param("id", high).query(Long.class).single()).isEqualTo(1L);
        assertThat(jdbc.sql("SELECT count(*) FROM platform.notice WHERE about_id = :id AND template_key = 'STUDENT_GRADUATED_RECONCILED'").param("id", high).query(Long.class).single()).isEqualTo(1L);
        // the record closed to fees from the session after the last permitted one, open for that one
        String maximum = before(back - 3 - max);
        assertThat(jdbc.sql("SELECT records.graduation_session(:id)").param("id", high).query(String.class).single()).isEqualTo(maximum);
        assertThat(jdbc.sql("SELECT finance.closed_for_fees(:id, :s)").param("id", high).param("s", current).query(Boolean.class).single()).isTrue();
        assertThat(jdbc.sql("SELECT finance.closed_for_fees(:id, :s)").param("id", high).param("s", maximum).query(Boolean.class).single()).isFalse();
        // nothing deleted: the old registration stays
        assertThat(jdbc.sql("SELECT count(*) FROM registration.course_registration WHERE student_id = :id").param("id", high).query(Long.class).single()).isEqualTo(1L);
        // executed again it graduates nobody twice
        assertThat(it.call(academic, HttpMethod.POST, batchPath + "/run", Map.of()).getBody()).containsEntry("graduated", 0).containsEntry("done", true);
        assertThat(jdbc.sql("SELECT count(*) FROM people.status_change WHERE student_id = :id AND to_status = 'GRADUATED'").param("id", high).query(Long.class).single()).isEqualTo(1L);
        // no longer a candidate; the batch reads its rows
        ResponseEntity<Map> detail = it.get(academic, batchPath);
        assertThat(detail.getStatusCode().value()).isEqualTo(200);
        Map<String, Object> rowsByStudent = ((List<Map<String, Object>>) detail.getBody().get("rows")).stream()
                .collect(java.util.stream.Collectors.toMap(r -> String.valueOf(r.get("student_id")), r -> String.valueOf(r.get("outcome")) + "/" + r.get("verdict")));
        assertThat(rowsByStudent).containsEntry(high.toString(), "GRADUATED/ELIGIBLE").containsEntry(medium.toString(), "null/REVIEW");
        assertThat(it.get(academic, PATH + "/students/" + high).getBody().get("candidate")).isNull();

        // the official date confirmed by the Academic Office, never by ICT
        String date = (Integer.parseInt(maximum.substring(0, 4)) + 1) + "-11-15";
        assertThat(it.call(ict, HttpMethod.POST, PATH + "/students/" + high + "/graduation-date", Map.of("date", date)).getStatusCode().value()).isEqualTo(403);
        ResponseEntity<Map> confirmed = it.call(academic, HttpMethod.POST, PATH + "/students/" + high + "/graduation-date", Map.of("date", date, "note", "Convocation"));
        assertThat(confirmed.getStatusCode().value()).as(String.valueOf(confirmed.getBody())).isEqualTo(200);
        Map<String, Object> rec = ((List<Map<String, Object>>) it.get(academic, PATH + "/students/" + high).getBody().get("reconciliations")).get(0);
        assertThat(rec).containsEntry("batch_ref", ref).containsEntry("date_confirmed", true).containsEntry("graduation_session", maximum).containsEntry("previous_status", "ACTIVE");
        assertThat(String.valueOf(rec.get("graduation_date"))).startsWith(date);
        // the Student Full Record carries the reconciliation
        ResponseEntity<Map> full = it.get(registrar, "/api/v1/student/students/" + high + "/full/overview");
        assertThat(full.getStatusCode().value()).as(String.valueOf(full.getBody())).isEqualTo(200);
        assertThat((Map<String, Object>) full.getBody().get("reconciliation")).containsEntry("batch_ref", ref).containsEntry("graduation_session", maximum)
                .containsEntry("date_confirmed", true).containsEntry("mode", "MANUAL");

        // the report counts the graduate by batch; the figures read the engines
        List<Map<String, Object>> report = (List<Map<String, Object>>) it.get(academic, PATH + "/report?by=batch").getBody().get("rows");
        assertThat(report).anySatisfy(r -> assertThat(r).containsEntry("label", ref).containsEntry("graduated", 1).containsEntry("high", 1).containsEntry("date_confirmed", 1));
        ResponseEntity<Map> figures = it.get(academic, PATH + "/figures?prog=" + PROGRAMME);
        assertThat(figures.getStatusCode().value()).isEqualTo(200);
        assertThat(figures.getBody()).containsKeys("active", "current", "sp1", "sp2", "outsideMaximum", "requiresReview", "graduated", "dataIncomplete", "graduationCandidates");
        assertThat(((Number) figures.getBody().get("graduatedByReconciliation")).intValue()).isGreaterThanOrEqualTo(1);

        // the automatic setting: the Academic Office is refused, ICT switches it; the nightly run does nothing while it is off
        assertThat(it.call(academic, HttpMethod.POST, PATH + "/setting", Map.of("autoGraduation", true)).getStatusCode().value()).isEqualTo(403);
        ResponseEntity<Map> on = it.call(ict, HttpMethod.POST, PATH + "/setting", Map.of("autoGraduation", true));
        assertThat(on.getStatusCode().value()).as(String.valueOf(on.getBody())).isEqualTo(200);
        assertThat(on.getBody()).containsEntry("auto_graduation", true);
        assertThat(it.call(ict, HttpMethod.POST, PATH + "/setting", Map.of("autoGraduation", false)).getBody()).containsEntry("auto_graduation", false);
        long automatic = jdbc.sql("SELECT count(*) FROM people.graduation_reconciliation_batch WHERE mode = 'AUTOMATIC'").query(Long.class).single();
        assertThat(controller.nightlyNow()).isNull();
        assertThat(jdbc.sql("SELECT count(*) FROM people.graduation_reconciliation_batch WHERE mode = 'AUTOMATIC'").query(Long.class).single()).isEqualTo(automatic);

        // the Registrar's correction puts the status back and marks the reconciliation corrected
        ResponseEntity<Map> corrected = it.call(registrar, HttpMethod.POST, "/api/v1/graduation/students/" + high + "/correct",
                Map.of("reason", "Integration test: the student is still in study on the department's evidence", "evidence", "Registrar's memo REG/IT/638"));
        assertThat(corrected.getStatusCode().value()).as(String.valueOf(corrected.getBody())).isEqualTo(200);
        assertThat(status(high)).isEqualTo("ACTIVE");
        assertThat(jdbc.sql("SELECT corrected_at IS NOT NULL FROM people.graduation_reconciliation WHERE student_id = :id AND batch_ref = :b").param("id", high).param("b", ref)
                .query(Boolean.class).single()).isTrue();
        assertThat(jdbc.sql("SELECT corrected FROM people.graduation_reconciliation_batch WHERE batch_ref = :b").param("b", ref).query(Integer.class).single()).isEqualTo(1);
    }
}
