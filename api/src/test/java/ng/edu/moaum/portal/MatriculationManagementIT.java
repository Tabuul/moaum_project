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
 * Matriculation Management (V267), end to end: the faculty's eligible students grouped by programme; numbers
 * proposed from the configured series and reserved but NOT written to any student; a correction validated and
 * recorded with its reason; a duplicate detected and issuance refused while it stands; the batch marked ready;
 * the all-faculties view for the Registry and refused to a faculty officer; issuance only on an explicit
 * confirmation — one transaction that assigns the number, moves the series, marks the student ACTIVE, makes
 * the number the sign-in username on the same account with the same password, writes the histories and the
 * notice; the old admission number no longer opening the portal; the separation of duties when it is on; a
 * cancelled batch releasing its reservations; an issued batch never cancelled; the doors.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT,
        properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
class MatriculationManagementIT {

    static final String SESSION = "2085/2086";
    static final String BASE = "/api/v1/matriculation/sessions/2085/2086/management";

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    ItSupport it;
    final String academic = ItSupport.token("academic");
    final String registrar = ItSupport.token("registrar");
    final String officer = ItSupport.token("facultyofficer");
    final String housing = ItSupport.token("housing");

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
        it.session(SESSION, 2085);
        it.db(() -> {
            jdbc.sql("UPDATE people.matric_format SET separate_duties = false WHERE id = 'UNIVERSITY'").update();
            // residue of an earlier run on this database: open batches cancelled, the invented students taken out of the session
            jdbc.sql("SELECT people.matric_batch_cancel(b.id, 'Test residue', NULL) FROM people.matric_batch b WHERE b.session = :s AND b.state NOT IN ('ISSUED', 'CANCELLED')").param("s", SESSION).query().listOfRows();
            jdbc.sql("DELETE FROM registration.entry WHERE registration_id IN (SELECT r.id FROM registration.course_registration r JOIN people.student s ON s.id = r.student_id WHERE r.session = :s AND s.surname LIKE 'ZZMM%' AND s.matric_no IS NULL)").param("s", SESSION).update();
            jdbc.sql("DELETE FROM registration.course_registration r USING people.student s WHERE s.id = r.student_id AND r.session = :s AND s.surname LIKE 'ZZMM%' AND s.matric_no IS NULL").param("s", SESSION).update();
            jdbc.sql("UPDATE people.student SET entry_session = '2020/2021' WHERE surname LIKE 'ZZMM%' AND matric_no IS NULL AND entry_session = :s").param("s", SESSION).update();
            return null;
        });
    }

    private UUID offering() {
        return it.db(() -> {
            jdbc.sql("INSERT INTO catalogue.course (code, title, units, semester, level, dept_code, state) VALUES ('ZZT 102', 'A course for the management test', 3, 1, 100, 'MTC', 'LIVE') ON CONFLICT (code) DO NOTHING").update();
            return jdbc.sql("INSERT INTO catalogue.offering (id, course_code, session, semester) VALUES (gen_random_uuid(), 'ZZT 102', :s, 1) ON CONFLICT (course_code, session, semester) DO UPDATE SET semester = EXCLUDED.semester RETURNING id")
                    .param("s", SESSION).query(UUID.class).single();
        });
    }

    private void registered(UUID student, UUID offering) {
        it.db(() -> {
            UUID reg = jdbc.sql("""
                    INSERT INTO registration.course_registration (id, student_id, session, semester, level, status, approved_at)
                    VALUES (gen_random_uuid(), :s, :sess, 1, 100, 'APPROVED', now()) ON CONFLICT (student_id, session, semester) DO UPDATE SET status = 'APPROVED' RETURNING id
                    """).param("s", student).param("sess", SESSION).query(UUID.class).single();
            jdbc.sql("INSERT INTO registration.entry (registration_id, offering_id, units, status) VALUES (:r, :o, 3, 'APPROVED') ON CONFLICT DO NOTHING").param("r", reg).param("o", offering).update();
            return null;
        });
    }

    /** an admitted student of the session with no number, fresh each run (the surname carries a random tag) */
    private UUID fresh(String tag, String programme) {
        int n = (int) (Math.random() * 900_000) + 100_000;
        UUID id = it.student("ZZMM" + tag + "-" + n, programme, "MOAUM/ADM/85/" + n, null, 100);
        it.db(() -> jdbc.sql("UPDATE people.student SET entry_session = :s WHERE id = :id").param("s", SESSION).param("id", id).update());
        return id;
    }

    @SuppressWarnings("unchecked")
    private static Map<String, Object> m(Object o) {
        return (Map<String, Object>) o;
    }

    @SuppressWarnings("unchecked")
    private static List<Map<String, Object>> l(Object o) {
        return (List<Map<String, Object>>) o;
    }

    private String matric(UUID student) {
        return jdbc.sql("SELECT matric_no FROM people.student WHERE id = :id").param("id", student).query(String.class).optional().orElse(null);
    }

    @Test
    void theExerciseFromEligibleStudentsToIssuedNumbersAndTheNewSignIn() {
        UUID off = offering();
        UUID acc1 = fresh("ACC", "C00019");     // Accounting — MOAU/AD/ACC/85/n, series ADMIN
        UUID acc2 = fresh("ACC", "C00019");
        UUID bus = fresh("BUS", "C00021");      // Business — MOAU/AD/BUS/85/n, same faculty and series
        UUID pendingOne = fresh("PEND", "C00019");   // admitted, not registered → pending with the reason
        UUID sci = fresh("SCI", "C00023");      // another faculty, GENERAL series
        for (UUID s : List.of(acc1, acc2, bus, sci)) registered(s, off);
        // the student has a portal account already, opened on the admission number, with a password of their own
        UUID accountId = it.db(() -> jdbc.sql("INSERT INTO iam.student_account (id, student_id, password_hash) VALUES (gen_random_uuid(), :s, crypt('a password of my own', gen_salt('bf', 12))) RETURNING id")
                .param("s", acc1).query(UUID.class).single());
        // somewhere to send the notice
        it.db(() -> jdbc.sql("INSERT INTO people.student_contact (student_id, email, phone) VALUES (:s, :e, '08031234567') ON CONFLICT (student_id) DO UPDATE SET email = EXCLUDED.email, phone = EXCLUDED.phone")
                .param("s", acc1).param("e", "zzmm" + acc1.toString().substring(0, 8) + "@example.com").update());
        String admissionNo = jdbc.sql("SELECT admission_no FROM people.student WHERE id = :id").param("id", acc1).query(String.class).single();
        assertThat(it.anon(HttpMethod.POST, "/api/v1/student-auth/sign-in", Map.of("matricNo", admissionNo, "password", "a password of my own")).getStatusCode().value()).isEqualTo(200);

        // 1 · the faculty view: eligible students grouped by programme, the pending one named with its reason
        ResponseEntity<Map> page = it.get(academic, BASE + "?fac=MS");
        assertThat(page.getStatusCode().value()).as(String.valueOf(page.getBody())).isEqualTo(200);
        Map<String, Object> fac = m(page.getBody().get("faculty"));
        assertThat(((Number) m(fac.get("kpis")).get("eligible")).intValue()).isGreaterThanOrEqualTo(3);
        List<Map<String, Object>> programmes = l(fac.get("programmes"));
        assertThat(programmes.stream().map(p -> p.get("code"))).contains("C00019", "C00021");
        Map<String, Object> pendingRow = l(fac.get("students")).stream().filter(s -> pendingOne.toString().equals(String.valueOf(s.get("student_id")))).findFirst().orElseThrow();
        assertThat(pendingRow.get("eligible")).isEqualTo(false);
        assertThat(String.valueOf(pendingRow.get("reason"))).contains("No approved course registration");
        assertThat(l(it.get(academic, BASE + "?fac=MS&status=PENDING").getBody().get("faculty") == null ? List.of() : m(it.get(academic, BASE + "?fac=MS&status=PENDING").getBody().get("faculty")).get("students")))
                .anyMatch(s -> pendingOne.toString().equals(String.valueOf(s.get("student_id"))));
        // the search finds one by name
        String surname = jdbc.sql("SELECT surname FROM people.student WHERE id = :id").param("id", bus).query(String.class).single();
        assertThat(l(m(it.get(academic, BASE + "?fac=MS&q=" + surname).getBody().get("faculty")).get("students"))).hasSize(1);

        // 2 · generate: numbers proposed from the series and reserved — and nothing written to any student
        long adminBefore = jdbc.sql("SELECT last_issued FROM people.matric_series WHERE code = 'ADMIN'").query(Long.class).single();
        ResponseEntity<Map> gen = it.call(academic, HttpMethod.POST, BASE + "/faculties/MS/generate", Map.of());
        assertThat(gen.getStatusCode().value()).as(String.valueOf(gen.getBody())).isEqualTo(200);
        Map<String, Object> batch = m(gen.getBody().get("batch"));
        String batchId = String.valueOf(batch.get("id"));
        String ref = String.valueOf(batch.get("ref"));
        assertThat(ref).matches("MAT/2085/\\d{3}");
        assertThat(batch.get("state")).isEqualTo("GENERATED");
        List<Map<String, Object>> rows = l(gen.getBody().get("rows"));
        Map<String, Object> rAcc1 = rows.stream().filter(r -> acc1.toString().equals(String.valueOf(r.get("student_id")))).findFirst().orElseThrow();
        Map<String, Object> rAcc2 = rows.stream().filter(r -> acc2.toString().equals(String.valueOf(r.get("student_id")))).findFirst().orElseThrow();
        Map<String, Object> rBus = rows.stream().filter(r -> bus.toString().equals(String.valueOf(r.get("student_id")))).findFirst().orElseThrow();
        assertThat(rows.stream().map(r -> r.get("student_id"))).doesNotContain(pendingOne.toString());
        assertThat(String.valueOf(rAcc1.get("proposed_no"))).matches("MOAU/AD/ACC/85/\\d+");
        assertThat(String.valueOf(rBus.get("proposed_no"))).matches("MOAU/AD/BUS/85/\\d+");
        assertThat(((Number) rAcc2.get("sequence")).longValue()).isNotEqualTo(((Number) rAcc1.get("sequence")).longValue());
        assertThat(l(gen.getBody().get("rows")).stream().allMatch(r -> ((List<?>) r.get("problems")).isEmpty())).isTrue();
        assertThat(matric(acc1)).isNull();
        assertThat(matric(bus)).isNull();
        assertThat(jdbc.sql("SELECT last_issued FROM people.matric_series WHERE code = 'ADMIN'").query(Long.class).single()).isEqualTo(adminBefore);
        assertThat(jdbc.sql("SELECT count(*) FROM people.matric_reservation WHERE batch_id = :b AND released_at IS NULL").param("b", UUID.fromString(batchId)).query(Long.class).single()).isEqualTo(3);
        // generating again adds nothing and proposes nothing twice
        assertThat(l(it.call(academic, HttpMethod.POST, BASE + "/faculties/MS/generate", Map.of()).getBody().get("rows"))).hasSize(3);
        // another faculty's batch takes the next free numbers of its own series and never one of these
        ResponseEntity<Map> genSci = it.call(academic, HttpMethod.POST, BASE + "/faculties/SC/generate", Map.of());
        assertThat(genSci.getStatusCode().value()).as(String.valueOf(genSci.getBody())).isEqualTo(200);
        String sciBatch = String.valueOf(m(genSci.getBody().get("batch")).get("id"));
        String sciNo = String.valueOf(l(genSci.getBody().get("rows")).get(0).get("proposed_no"));
        assertThat(sciNo).matches("MOAU/SC/[A-Z]+/85/\\d+");
        // the old single act passes over a reserved number: the straggler path reads the reservations
        assertThat(jdbc.sql("SELECT people.matric_number_taken(:n, r.series_code, r.sequence, NULL) FROM people.matric_reservation r WHERE r.matric_no = :n AND r.released_at IS NULL").param("n", sciNo).query(String.class).single()).contains("reserved by batch");

        // 3 · a correction: validated, reasoned, recorded — never bypassing validation
        String rowAcc2 = String.valueOf(rAcc2.get("id"));
        assertThat(it.call(academic, HttpMethod.PUT, BASE + "/batches/" + batchId + "/rows/" + rowAcc2, Map.of("matricNo", "MOAU/SC/ACC/85/999", "reason", "wrong faculty on purpose")).getStatusCode().value()).isEqualTo(422);
        assertThat(it.call(academic, HttpMethod.PUT, BASE + "/batches/" + batchId + "/rows/" + rowAcc2, Map.of("matricNo", "MOAU/AD/ACC/85/777777", "reason", "")).getStatusCode().value()).isIn(400, 422);
        assertThat(it.call(academic, HttpMethod.PUT, BASE + "/batches/" + batchId + "/rows/" + rowAcc2, Map.of("matricNo", String.valueOf(rAcc1.get("proposed_no")), "reason", "a number another row holds")).getStatusCode().value()).isIn(409, 422);
        long corrected = ((Number) rAcc2.get("sequence")).longValue() + 50;
        String correctedNo = "MOAU/AD/ACC/85/" + corrected;
        ResponseEntity<Map> edited = it.call(academic, HttpMethod.PUT, BASE + "/batches/" + batchId + "/rows/" + rowAcc2, Map.of("matricNo", correctedNo, "reason", "Registrar's instruction: the number reserved on the manual schedule"));
        assertThat(edited.getStatusCode().value()).as(String.valueOf(edited.getBody())).isEqualTo(200);
        Map<String, Object> afterEdit = l(edited.getBody().get("rows")).stream().filter(r -> rowAcc2.equals(String.valueOf(r.get("id")))).findFirst().orElseThrow();
        assertThat(afterEdit.get("proposed_no")).isEqualTo(correctedNo);
        assertThat(afterEdit.get("edited")).isEqualTo(true);
        assertThat(afterEdit.get("previous_no")).isEqualTo(rAcc2.get("proposed_no"));
        assertThat(l(edited.getBody().get("edits"))).hasSize(1);
        assertThat(((List<?>) afterEdit.get("problems"))).isEmpty();
        assertThat(((Number) m(edited.getBody().get("batch")).get("conflicts")).intValue()).isZero();

        // 4 · a duplicate slipped in behind the door is detected, and the batch is neither marked ready nor issued while it stands
        it.db(() -> jdbc.sql("UPDATE people.matric_batch_row SET proposed_no = :n WHERE id = :r").param("n", String.valueOf(rAcc1.get("proposed_no"))).param("r", UUID.fromString(rowAcc2)).update());
        ResponseEntity<Map> validated = it.call(academic, HttpMethod.POST, BASE + "/batches/" + batchId + "/validate", Map.of());
        assertThat(validated.getStatusCode().value()).as(String.valueOf(validated.getBody())).isEqualTo(200);
        assertThat(((Number) m(validated.getBody().get("batch")).get("conflicts")).intValue()).isEqualTo(2);
        assertThat(String.valueOf(l(validated.getBody().get("rows")).stream().filter(r -> rowAcc2.equals(String.valueOf(r.get("id")))).findFirst().orElseThrow().get("problems"))).contains("Duplicate within this batch");
        assertThat(it.call(academic, HttpMethod.POST, BASE + "/batches/" + batchId + "/ready", Map.of()).getStatusCode().value()).isEqualTo(422);
        // put right through the door
        assertThat(it.call(academic, HttpMethod.PUT, BASE + "/batches/" + batchId + "/rows/" + rowAcc2, Map.of("matricNo", correctedNo, "reason", "Duplicate removed")).getStatusCode().value()).isEqualTo(200);

        // 5 · not issued before it is ready; ready; the all-faculties view for the Registry, not the faculty officer
        assertThat(it.call(academic, HttpMethod.POST, BASE + "/batches/" + batchId + "/issue", Map.of("confirm", true)).getStatusCode().value()).isEqualTo(422);
        ResponseEntity<Map> ready = it.call(academic, HttpMethod.POST, BASE + "/batches/" + batchId + "/ready", Map.of());
        assertThat(ready.getStatusCode().value()).as(String.valueOf(ready.getBody())).isEqualTo(200);
        assertThat(m(ready.getBody().get("batch")).get("state")).isEqualTo("READY_FOR_ISSUANCE");
        assertThat(matric(acc1)).isNull();
        ResponseEntity<Map> overview = it.get(registrar, BASE + "/overview");
        assertThat(overview.getStatusCode().value()).as(String.valueOf(overview.getBody())).isEqualTo(200);
        Map<String, Object> msLine = l(overview.getBody().get("faculties")).stream().filter(f -> "MS".equals(f.get("faculty_code"))).findFirst().orElseThrow();
        assertThat(((Number) msLine.get("prepared")).intValue()).isEqualTo(3);
        assertThat(msLine.get("batch_state")).isEqualTo("READY_FOR_ISSUANCE");
        assertThat(((Number) m(overview.getBody().get("totals")).get("ready")).intValue()).isGreaterThanOrEqualTo(1);
        assertThat(it.get(officer, BASE + "/overview").getStatusCode().value()).isEqualTo(422);        // bound to a faculty it does not have
        assertThat(it.get(officer, BASE + "?fac=MS").getStatusCode().value()).isEqualTo(422);
        assertThat(it.get(housing, BASE + "?fac=MS").getStatusCode().value()).isEqualTo(403);
        assertThat(it.call(officer, HttpMethod.POST, BASE + "/batches/" + batchId + "/issue", Map.of("confirm", true)).getStatusCode().value()).isEqualTo(403);
        assertThat(it.call(academic, HttpMethod.POST, BASE + "/batches/" + batchId + "/issue", Map.of()).getStatusCode().value()).isEqualTo(422);   // no confirmation

        // 6 · duties separated: the preparer does not issue; another authorised officer does
        assertThat(it.call(registrar, HttpMethod.PUT, "/api/v1/matriculation/config/duties", Map.of("separateDuties", true)).getStatusCode().value()).isEqualTo(200);
        ResponseEntity<Map> refused = it.call(academic, HttpMethod.POST, BASE + "/batches/" + batchId + "/issue", Map.of("confirm", true));
        assertThat(refused.getStatusCode().value()).as(String.valueOf(refused.getBody())).isEqualTo(422);
        assertThat(matric(acc1)).isNull();

        // 7 · the official act: one transaction — number, series, status, sign-in, histories, notice
        ResponseEntity<Map> issued = it.call(registrar, HttpMethod.POST, BASE + "/batches/" + batchId + "/issue", Map.of("confirm", true));
        assertThat(issued.getStatusCode().value()).as(String.valueOf(issued.getBody())).isEqualTo(200);
        Map<String, Object> result = m(issued.getBody().get("result"));
        assertThat(((Number) result.get("issued")).intValue()).isEqualTo(3);
        assertThat(((Number) result.get("username_updates")).intValue()).isEqualTo(3);
        Map<String, Object> verification = m(issued.getBody().get("verification"));
        assertThat(((Number) verification.get("failed")).intValue()).isZero();
        assertThat(((Number) verification.get("unique_numbers")).intValue()).isEqualTo(3);
        assertThat(m(issued.getBody().get("batch")).get("state")).isEqualTo("ISSUED");
        assertThat(matric(acc1)).isEqualTo(String.valueOf(rAcc1.get("proposed_no")));
        assertThat(matric(acc2)).isEqualTo(correctedNo);
        assertThat(matric(bus)).isEqualTo(String.valueOf(rBus.get("proposed_no")));
        assertThat(matric(pendingOne)).isNull();
        Map<String, Object> s1 = jdbc.sql("SELECT status, matriculated_at, matriculation_run, id FROM people.student WHERE id = :id").param("id", acc1).query().singleRow();
        assertThat(s1.get("status")).isEqualTo("ACTIVE");
        assertThat(s1.get("matriculated_at")).isNotNull();
        assertThat(String.valueOf(s1.get("matriculation_run"))).isEqualTo(batchId);
        assertThat(String.valueOf(s1.get("id"))).isEqualTo(acc1.toString());
        assertThat(jdbc.sql("SELECT last_issued FROM people.matric_series WHERE code = 'ADMIN'").query(Long.class).single()).isEqualTo(corrected);
        assertThat(jdbc.sql("SELECT count(*) FROM people.matric_history WHERE run_id = :b").param("b", UUID.fromString(batchId)).query(Long.class).single()).isEqualTo(3);
        assertThat(jdbc.sql("SELECT ref FROM people.matriculation_run WHERE id = :b").param("b", UUID.fromString(batchId)).query(String.class).single()).isEqualTo(ref);
        assertThat(jdbc.sql("SELECT count(*) FROM people.matric_reservation WHERE batch_id = :b AND released_at IS NULL").param("b", UUID.fromString(batchId)).query(Long.class).single()).isZero();
        Map<String, Object> uc = jdbc.sql("SELECT previous_username, new_username, reason FROM people.student_username_change WHERE student_id = :s").param("s", acc1).query().singleRow();
        assertThat(uc.get("previous_username")).isEqualTo(admissionNo);
        assertThat(uc.get("new_username")).isEqualTo(matric(acc1));
        assertThat(jdbc.sql("SELECT count(*) FROM people.status_change WHERE student_id = :s AND to_status = 'ACTIVE' AND instrument = :r").param("s", acc1).param("r", ref).query(Long.class).single()).isEqualTo(1);
        assertThat(jdbc.sql("SELECT count(*) FROM platform.notice WHERE about_kind = 'student' AND about_id = :s AND subject ILIKE '%matriculat%'").param("s", acc1).query(Long.class).single()).isGreaterThanOrEqualTo(1);

        // 8 · the sign-in: the matriculation number opens the portal on the same account with the same password; the admission number no longer does
        ResponseEntity<Map> signed = it.anon(HttpMethod.POST, "/api/v1/student-auth/sign-in", Map.of("matricNo", matric(acc1), "password", "a password of my own"));
        assertThat(signed.getStatusCode().value()).as(String.valueOf(signed.getBody())).isEqualTo(200);
        assertThat(signed.getBody().get("studentId")).isEqualTo(acc1.toString());
        assertThat(jdbc.sql("SELECT id FROM iam.student_account WHERE student_id = :s").param("s", acc1).query(UUID.class).single()).isEqualTo(accountId);
        assertThat(it.anon(HttpMethod.POST, "/api/v1/student-auth/sign-in", Map.of("matricNo", admissionNo, "password", "a password of my own")).getStatusCode().value()).isIn(401, 422);

        // 9 · the registers and the student's before-and-after
        List<Map<String, Object>> list = it.getList(academic, BASE + "/issued?fac=MS&batch=" + ref).getBody();
        assertThat(list).hasSize(3);
        assertThat(list.stream().map(r -> r.get("previous_username"))).contains(admissionNo);
        ResponseEntity<Map> record = it.get(academic, "/api/v1/matriculation/students/" + acc1 + "/record");
        assertThat(record.getBody().get("matriculation_status")).isEqualTo("MATRICULATED");
        assertThat(record.getBody().get("username")).isEqualTo(matric(acc1));
        assertThat(l(record.getBody().get("usernameHistory"))).hasSize(1);
        assertThat(l(it.getList(academic, BASE + "/pending?fac=MS").getBody()).stream().map(r -> r.get("student_id"))).contains(pendingOne.toString());
        assertThat(l(it.get(academic, BASE + "?fac=MS").getBody().get("batches")).stream().map(b -> b.get("ref"))).contains(ref);

        // 10 · an issued batch is permanent; a prepared one is cancelled with its reason and its numbers released
        assertThat(it.call(registrar, HttpMethod.POST, BASE + "/batches/" + batchId + "/cancel", Map.of("reason", "try")).getStatusCode().value()).isEqualTo(422);
        assertThat(it.call(registrar, HttpMethod.PUT, BASE + "/batches/" + batchId + "/rows/" + rowAcc2, Map.of("matricNo", correctedNo, "reason", "late")).getStatusCode().value()).isEqualTo(422);
        assertThat(it.call(registrar, HttpMethod.POST, BASE + "/batches/" + sciBatch + "/cancel", Map.of("reason", "")).getStatusCode().value()).isIn(400, 422);
        ResponseEntity<Map> cancelled = it.call(registrar, HttpMethod.POST, BASE + "/batches/" + sciBatch + "/cancel", Map.of("reason", "The Faculty of Science list is not yet confirmed"));
        assertThat(cancelled.getStatusCode().value()).as(String.valueOf(cancelled.getBody())).isEqualTo(200);
        assertThat(m(cancelled.getBody().get("batch")).get("state")).isEqualTo("CANCELLED");
        assertThat(matric(sci)).isNull();
        assertThat(jdbc.sql("SELECT count(*) FROM people.matric_reservation WHERE batch_id = :b AND released_at IS NULL").param("b", UUID.fromString(sciBatch)).query(Long.class).single()).isZero();
        assertThat(jdbc.sql("SELECT status FROM people.student WHERE id = :id").param("id", sci).query(String.class).single()).isEqualTo("ADMITTED");
        // a released number is free again for the next batch of that faculty
        ResponseEntity<Map> again = it.call(academic, HttpMethod.POST, BASE + "/faculties/SC/generate", Map.of());
        assertThat(again.getStatusCode().value()).isEqualTo(200);
        assertThat(l(again.getBody().get("rows")).get(0).get("proposed_no")).isEqualTo(sciNo);
        it.call(registrar, HttpMethod.POST, BASE + "/batches/" + m(again.getBody().get("batch")).get("id") + "/cancel", Map.of("reason", "Test residue"));
    }
}
