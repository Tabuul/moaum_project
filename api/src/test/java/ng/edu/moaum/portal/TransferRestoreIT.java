package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.HashMap;
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
 * V669: a transfer approved on the old portal restored without a new application, through the API. Two programmes of the test's own
 * in two departments of a faculty; a student who moved A → B on the old portal and was put back on A at 200 Level, whom the Academic
 * Office had sent into the transfer queue again; another on B rightly. The student is found by number and the restoration checked (the
 * application to be withdrawn, nothing made), then made: on B at 300, the number unchanged, the application withdrawn, the transfer and
 * the restoration in the programme history, no application made. A plain swap of that kind is refused. An old-portal upload naming A at
 * 200 again leaves the record on B and puts a placement conflict to the Academic Office, kept with the reason. A third student is
 * restored in bulk (TRR/…). A genuine new transfer still goes to the queue. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class TransferRestoreIT {

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    ItSupport it;
    final String academic = ItSupport.token("academic");
    final String ict = ItSupport.token("ict");

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
    }

    private static Object code(ResponseEntity<Map> r) {
        return r.getBody() == null ? null : r.getBody().get("code");
    }

    @Test
    void aTransferApprovedOnTheOldPortalIsRestoredWithoutANewApplication() {
        int y = it.freeYear(5600, 5990, 1, 0);
        String earlier = (y - 1) + "/" + y, session = y + "/" + (y + 1);
        it.session(earlier, y - 1);
        it.session(session, y);
        int n = 1000 + new Random().nextInt(8999);
        String yy = String.format("%02d", y % 100);
        String hex = UUID.randomUUID().toString().replaceAll("[^a-f]", "").toUpperCase() + "ABCDEFABCDEF";
        String segA = "Z" + hex.substring(0, 2), segB = "Y" + hex.substring(2, 4);
        String[] place = it.db(() -> {
            String[] one = jdbc.sql("""
                    SELECT p1.dept_code || ',' || p2.dept_code || ',' || p1.faculty_code
                      FROM ref.programme p1 JOIN ref.programme p2 ON p2.faculty_code = p1.faculty_code AND p2.dept_code > p1.dept_code
                      JOIN ref.faculty f ON f.code = p1.faculty_code
                     WHERE p1.category = 'UNDER GRADUATE' AND p2.category = 'UNDER GRADUATE' AND NOT p1.archived AND NOT p2.archived
                       AND coalesce(f.college_code, '') <> 'CHS' AND p1.dept_code IS NOT NULL
                     ORDER BY p1.faculty_code, p1.dept_code, p2.dept_code LIMIT 1
                    """).query(String.class).single().split(",");
            List<String> codes = jdbc.sql("SELECT 'C' || x FROM generate_series(96500, 96999) x WHERE NOT EXISTS (SELECT 1 FROM ref.programme p WHERE p.code = 'C' || x) ORDER BY random() LIMIT 2")
                    .query(String.class).list();
            jdbc.sql("""
                    INSERT INTO ref.programme (code, name, dept_code, faculty_code, category, min_score, final_level, duration_years, matric_code) VALUES
                        (:a, 'B.Sc. Transfer Restore Test A ' || :a, :da, :f, 'UNDER GRADUATE', 0, 400, 4, :sa),
                        (:b, 'B.Sc. Transfer Restore Test B ' || :b, :db, :f, 'UNDER GRADUATE', 0, 400, 4, :sb)
                    """).param("a", codes.get(0)).param("b", codes.get(1)).param("da", one[0]).param("db", one[1]).param("f", one[2])
                    .param("sa", segA).param("sb", segB).update();
            return new String[] {one[0], one[1], one[2], codes.get(0), codes.get(1)};
        });
        String deptA = place[0], deptB = place[1], fac = place[2], pa = place[3], pb = place[4];
        String m1 = "MOAU/" + fac + "/" + segA + "/" + yy + "/" + n, m2 = "MOAU/" + fac + "/" + segA + "/" + yy + "/" + (n + 1), m3 = "MOAU/" + fac + "/" + segA + "/" + yy + "/" + (n + 2);
        UUID s1 = it.student("ZZRESTORE" + n, pa, "MOAUM/ADM/" + yy + "/69" + n, m1, 200);
        UUID s2 = it.student("ZZPLACED" + n, pb, "MOAUM/ADM/" + yy + "/68" + n, m2, 300);
        UUID s3 = it.student("ZZBULK" + n, pa, "MOAUM/ADM/" + yy + "/67" + n, m3, 200);

        // ── the mistake: the Academic Office records a transfer application for a student the old portal transferred already ──
        ResponseEntity<Map> queued = it.call(academic, HttpMethod.POST, "/api/v1/transfers", Map.of("number", m1, "toProgramme", pb, "reason", "Put back by the migration"));
        assertThat(queued.getStatusCode().value()).as(String.valueOf(queued.getBody())).isEqualTo(200);

        // ── found by number, checked: the application to be withdrawn, nothing made ──
        ResponseEntity<Map> found = it.get(academic, u -> u.path("/api/v1/programme-swaps/find").queryParam("number", m1).build());
        assertThat(found.getStatusCode().value()).as(String.valueOf(found.getBody())).isEqualTo(200);
        assertThat(found.getBody()).containsEntry("id", s1.toString());
        Map<String, Object> restoreBody = new HashMap<>(Map.of("studentId", s1.toString(), "toProgramme", pb, "toLevel", 300, "session", session,
                "transferSession", earlier, "approvedOn", "2025-03-14"));
        ResponseEntity<Map> checked = it.call(academic, HttpMethod.POST, "/api/v1/programme-swaps/restore-transfer/check", restoreBody);
        assertThat(checked.getStatusCode().value()).as(String.valueOf(checked.getBody())).isEqualTo(200);
        assertThat(checked.getBody()).containsEntry("ok", true);
        assertThat((List<Map<String, Object>>) checked.getBody().get("warnings")).extracting(w -> w.get("code")).contains("APPLICATION_WITHDRAWN");
        assertThat((Map<String, Object>) checked.getBody().get("creates")).containsEntry("transferApplications", 0).containsEntry("matriculationNumbers", 0);

        // ── restored: on B at 300, the number unchanged, the application withdrawn, the history kept, no application made ──
        restoreBody.put("transferSemester", 1);
        restoreBody.put("reference", "TRF/IT/669");
        restoreBody.put("reason", "Transfer approved by Senate on the old portal; restored after the migration");
        ResponseEntity<Map> restored = it.call(academic, HttpMethod.POST, "/api/v1/programme-swaps/restore-transfer", restoreBody);
        assertThat(restored.getStatusCode().value()).as(String.valueOf(restored.getBody())).isEqualTo(200);
        assertThat(String.valueOf(restored.getBody().get("swapRef"))).startsWith("PSW/");
        assertThat(restored.getBody()).containsEntry("transferApplicationsCreated", 0).containsEntry("matricNo", m1).containsEntry("recordOnly", false);
        ResponseEntity<Map> view = it.call(academic, HttpMethod.GET, "/api/v1/programme-swaps/students/" + s1, null);
        assertThat(view.getStatusCode().value()).isEqualTo(200);
        assertThat((Map<String, Object>) view.getBody().get("student")).containsEntry("programme_code", pb).containsEntry("current_level", 300).containsEntry("matric_no", m1);
        assertThat(view.getBody().get("openTransfer")).isNull();
        assertThat((List<Map<String, Object>>) view.getBody().get("history")).extracting(h -> h.get("kind"))
                .contains("TRANSFER_APPROVED_OLD_PORTAL", "PROGRAMME_SWAP_APPROVED_TRANSFER_RESTORED");
        assertThat(it.db(() -> jdbc.sql("SELECT string_agg(state, ',') FROM people.transfer_application WHERE student_id = :s").param("s", s1).query(String.class).single()))
                .isEqualTo("WITHDRAWN");

        // ── never as a plain swap ──
        ResponseEntity<Map> plain = it.call(academic, HttpMethod.POST, "/api/v1/programme-swaps", Map.of("studentId", s2.toString(), "toProgramme", pa, "toLevel", 300,
                "session", session, "kind", "APPROVED_TRANSFER_RESTORED", "reason", "A plain swap of the restoration kind"));
        assertThat(plain.getStatusCode().value()).as(String.valueOf(plain.getBody())).isEqualTo(422);
        assertThat(code(plain)).isEqualTo("PSW_KIND");

        // ── an old-portal upload naming A at 200 again: the record stays on B at 300, the file's put to the Academic Office ──
        ResponseEntity<Map> uploaded = it.call(ict, HttpMethod.POST, "/api/v1/results/legacy/students",
                Map.of("rows", List.of(Map.of("matric", m1, "name", "ZZRESTORE" + n + ", Invented", "programme", pa, "level", "200"))));
        assertThat(uploaded.getStatusCode().value()).as(String.valueOf(uploaded.getBody())).isEqualTo(200);
        assertThat(it.db(() -> jdbc.sql("SELECT programme_code || ' ' || current_level FROM people.student WHERE id = :s").param("s", s1).query(String.class).single()))
                .isEqualTo(pb + " 300");
        ResponseEntity<Map> conflicts = it.get(academic, u -> u.path("/api/v1/programme-swaps/placement-conflicts").queryParam("status", "REQUIRES_REVIEW").build());
        assertThat(conflicts.getStatusCode().value()).as(String.valueOf(conflicts.getBody())).isEqualTo(200);
        Map<String, Object> conflict = ((List<Map<String, Object>>) conflicts.getBody().get("rows")).stream().filter(c -> s1.toString().equals(c.get("student_id")))
                .findFirst().orElseThrow(() -> new AssertionError("no conflict for the student in " + conflicts.getBody()));
        assertThat(conflict).containsEntry("file_programme", pa).containsEntry("file_level", 200).containsEntry("kept_programme", pb).containsEntry("kept_level", 300);
        ResponseEntity<Map> kept = it.call(academic, HttpMethod.POST, "/api/v1/programme-swaps/placement-conflicts/" + conflict.get("id") + "/decide",
                Map.of("decision", "KEEP", "note", "The old file predates the approved transfer"));
        assertThat(kept.getStatusCode().value()).as(String.valueOf(kept.getBody())).isEqualTo(200);
        assertThat(kept.getBody()).containsEntry("status", "KEPT");

        // ── in bulk: the restoration's batch (TRR/…) ──
        Map<String, Object> row = new HashMap<>();
        row.putAll(Map.of("matric_no", m3, "old_faculty", fac, "old_dept", deptA, "old_programme", pa, "old_level", "200", "new_faculty", fac, "new_dept", deptB,
                "new_programme", pb, "new_level", "300", "effective_session", earlier));
        row.putAll(Map.of("effective_semester", "2", "approval_ref", "TRF/IT/670", "approved_on", "14/03/2025"));
        ResponseEntity<Map> validated = it.call(academic, HttpMethod.POST, "/api/v1/transfers/bulk/validate",
                Map.of("rows", List.of(row), "session", session, "kind", "APPROVED_TRANSFER_RESTORED"));
        assertThat(validated.getStatusCode().value()).as(String.valueOf(validated.getBody())).isEqualTo(200);
        assertThat(validated.getBody()).containsEntry("valid", 1).containsEntry("kind", "APPROVED_TRANSFER_RESTORED");
        ResponseEntity<Map> batch = it.call(academic, HttpMethod.POST, "/api/v1/transfers/bulk", Map.of("rows", List.of(row), "session", session,
                "reason", "Transfers approved by Senate on the old portal, restored in bulk", "approvalRef", "SEN/IT/669", "filename", "restore.xlsx",
                "validRowsOnly", false, "kind", "APPROVED_TRANSFER_RESTORED"));
        assertThat(batch.getStatusCode().value()).as(String.valueOf(batch.getBody())).isEqualTo(200);
        assertThat(String.valueOf(batch.getBody().get("ref"))).startsWith("TRR/");
        assertThat(batch.getBody()).containsEntry("kind", "APPROVED_TRANSFER_RESTORED");
        assertThat(it.db(() -> jdbc.sql("""
                SELECT s.programme_code || ' ' || s.current_level || ' ' || s.matric_no || ' ' || pt.reference || ' ' || pt.effective_semester
                  FROM people.student s JOIN people.prior_transfer pt ON pt.student_id = s.id WHERE s.id = :s
                """).param("s", s3).query(String.class).single())).isEqualTo(pb + " 300 " + m3 + " TRF/IT/670 2");

        // ── no application was made for the restorations; a genuine new transfer still goes to the queue ──
        assertThat(it.db(() -> jdbc.sql("SELECT count(*) FROM people.transfer_application WHERE student_id IN (:a, :b)").param("a", s1).param("b", s3)
                .query(Long.class).single())).isEqualTo(1L);
        ResponseEntity<Map> genuine = it.call(academic, HttpMethod.POST, "/api/v1/transfers", Map.of("number", m2, "toProgramme", pa, "reason", "Asks to move to A"));
        assertThat(genuine.getStatusCode().value()).as(String.valueOf(genuine.getBody())).isEqualTo(200);
        assertThat(genuine.getBody()).containsEntry("state", "APPLIED");
    }
}
