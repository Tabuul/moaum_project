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
 * Programme swap (V578, V633) over the API: a swap made by one officer moves the student's current programme and level at once and
 * nothing else (the matriculation number, the registrations and their courses, the payments stay), the same officer its preparer
 * and decider, the old placement stays in the programme history the full record reads, and the register finds the student under
 * the new programme; a completed swap is not decided again, the Director of ICT makes a programme correction in bulk, a transfer
 * under way blocks a swap, a bulk swap reports the student it skipped, a Head of Department elsewhere and a student are refused,
 * and the mismatch detector flags a record whose matriculation number and registration both name another department. Needs
 * DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = {"moaum.auth.hmac-secret=" + TestTokens.SECRET})
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"unchecked", "rawtypes"})
class ProgrammeSwapIT {

    static final String PATH = "/api/v1/programme-swaps";

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    ItSupport it;
    String dept;      // the department of C00023
    String target;    // an undergraduate programme of another department
    String targetDept;

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
        dept = jdbc.sql("SELECT dept_code FROM ref.programme WHERE code = 'C00023'").query(String.class).single();
        Map<String, Object> t = jdbc.sql("""
                SELECT code, dept_code FROM ref.programme WHERE category = 'UNDER GRADUATE' AND NOT archived AND dept_code IS NOT NULL AND dept_code <> :d
                 ORDER BY code LIMIT 1
                """).param("d", dept).query().singleRow();
        target = (String) t.get("code");
        targetDept = (String) t.get("dept_code");
    }

    private String officer(String office, String tag) {
        return TestTokens.token(it.person("ZZ-PSW-" + tag, "ZZPSW" + tag), List.of(office));
    }

    private Map<String, Object> prepareBody(UUID student, String programme, int level, String kind) {
        Map<String, Object> b = new HashMap<>();
        b.put("studentId", student.toString());
        b.put("toProgramme", programme);
        b.put("toLevel", level);
        b.put("kind", kind);
        b.put("reason", "Legacy record kept the old programme after the approved change (integration test)");
        return b;
    }

    private long count(String sql, UUID student) {
        return jdbc.sql(sql).param("s", student).query(Long.class).single();
    }

    @Test
    void aSwapMadeByOneOfficerMovesThePlacementAtOnceAndNothingElse() {
        String surname = it.freeSurname("ZZPSWA");
        UUID student = it.student(surname, "C00023", null, it.freeNumber("MOAUM/PSA/86/", 6), 200);
        String matric = jdbc.sql("SELECT matric_no FROM people.student WHERE id = :s").param("s", student).query(String.class).single();
        // a registration with a course and a payment, to be left as they are
        String session = "3351/3352";
        it.session(session, 3351);
        UUID reg = UUID.randomUUID();
        it.db(() -> {
            jdbc.sql("INSERT INTO registration.course_registration (id, student_id, session, semester, level, status, submitted_at, approved_at) VALUES (:r, :s, :ses, 1, 200, 'APPROVED', now(), now())")
                    .param("r", reg).param("s", student).param("ses", session).update();
            jdbc.sql("""
                    INSERT INTO finance.payment_reference (student_id, session, reference, purpose, amount, expires_at, confirmed_at, confirmed_by, channel, receipt_no, note)
                    VALUES (:s, :ses, 'MOAUM-ITPS-' || upper(left(replace(:s::text, '-', ''), 12)), 'School fees ' || :ses, 50000, now(), now(), gen_random_uuid(), 'INTERSWITCH', 'RCT-PSW-' || upper(left(replace(:s::text, '-', ''), 10)), 'programme swap test')
                    """).param("s", student).param("ses", session).update();
            return null;
        });
        long payments = count("SELECT count(*) FROM finance.payment_reference WHERE student_id = :s", student);

        String one = officer("academic", "A1");
        String two = officer("academic", "A2");

        // the check says what would change and what stays
        ResponseEntity<Map> chk = it.call(one, HttpMethod.POST, PATH + "/check", Map.of("studentId", student.toString(), "toProgramme", target, "toLevel", 200));
        assertThat(chk.getStatusCode().value()).as(String.valueOf(chk.getBody())).isEqualTo(200);
        assertThat(chk.getBody()).containsEntry("ok", true).containsEntry("change", "PROGRAMME");
        assertThat((List<String>) chk.getBody().get("unchanged")).contains("Matriculation number", "Results");

        ResponseEntity<Map> prepared = it.call(one, HttpMethod.POST, PATH, prepareBody(student, target, 200, "PROGRAMME_CORRECTION"));
        assertThat(prepared.getStatusCode().value()).as(String.valueOf(prepared.getBody())).isEqualTo(200);
        String id = String.valueOf(prepared.getBody().get("id"));
        assertThat(String.valueOf(prepared.getBody().get("swap_ref"))).matches("PSW/[0-9]{4}/[0-9]{6}");
        // V633: made at once by the officer who initiates it — the same officer its preparer and decider, the student moved on return
        assertThat(prepared.getBody()).containsEntry("status", "COMPLETED").containsEntry("from_programme", "C00023").containsEntry("to_programme", target);
        assertThat(prepared.getBody().get("executed_at")).isNotNull();
        assertThat(prepared.getBody().get("decided_by")).isNotNull().isEqualTo(prepared.getBody().get("prepared_by"));
        assertThat(jdbc.sql("SELECT programme_code FROM people.student WHERE id = :s").param("s", student).query(String.class).single()).isEqualTo(target);

        // evidence kept with the swap, after it is made as well
        ResponseEntity<Map> ev = it.call(one, HttpMethod.POST, PATH + "/" + id + "/evidence", Map.of("filename", "approval.png", "dataUrl", "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=="));
        assertThat(ev.getStatusCode().value()).as(String.valueOf(ev.getBody())).isEqualTo(200);
        assertThat((List<?>) ev.getBody().get("evidence")).hasSize(1);

        // a completed swap is not decided again, by anyone
        ResponseEntity<Map> twice = it.call(two, HttpMethod.POST, PATH + "/" + id + "/decide", Map.of("approve", true, "note", "Approved on the department's letter"));
        assertThat(twice.getStatusCode().value()).isEqualTo(422);
        assertThat(twice.getBody()).containsEntry("code", "PSW_DECIDED");
        ResponseEntity<Map> done = it.get(two, PATH + "/" + id);
        assertThat(done.getStatusCode().value()).as(String.valueOf(done.getBody())).isEqualTo(200);
        assertThat(done.getBody()).containsEntry("status", "COMPLETED");

        Map<String, Object> after = jdbc.sql("SELECT programme_code, current_level, matric_no FROM people.student WHERE id = :s").param("s", student).query().singleRow();
        assertThat(after).containsEntry("programme_code", target).containsEntry("current_level", 200).containsEntry("matric_no", matric);
        assertThat(count("SELECT count(*) FROM registration.course_registration WHERE student_id = :s", student)).isEqualTo(1);
        assertThat(count("SELECT count(*) FROM finance.payment_reference WHERE student_id = :s", student)).isEqualTo(payments);
        // the cohort engine reads the new programme
        assertThat(jdbc.sql("SELECT programme_code FROM people.academic_position WHERE student_id = :s").param("s", student).query(String.class).single()).isEqualTo(target);

        // the history keeps the old placement; the full record reads it; the register finds the student under the new programme
        ResponseEntity<Map> rec = it.get(two, PATH + "/students/" + student);
        assertThat(rec.getStatusCode().value()).isEqualTo(200);
        List<Map<String, Object>> history = (List<Map<String, Object>>) rec.getBody().get("history");
        assertThat(history).extracting(h -> h.get("kind")).contains("ORIGINAL_ADMISSION", "PROGRAMME_SWAP_PROGRAMME_CORRECTION");
        assertThat(history).filteredOn(h -> "ORIGINAL_ADMISSION".equals(h.get("kind"))).first().extracting(h -> h.get("programme_code")).isEqualTo("C00023");
        assertThat(history).filteredOn(h -> "PROGRAMME_SWAP_PROGRAMME_CORRECTION".equals(h.get("kind"))).first()
                .satisfies(h -> { assertThat(h.get("programme_code")).isEqualTo(target); assertThat(h.get("from_programme")).isEqualTo("C00023"); assertThat(h.get("current")).isEqualTo(true); });
        ResponseEntity<Map> full = it.get(two, "/api/v1/student/students/" + student + "/full/admission");
        assertThat(full.getStatusCode().value()).isEqualTo(200);
        assertThat((List<?>) full.getBody().get("programmeHistory")).hasSizeGreaterThanOrEqualTo(2);
        ResponseEntity<Map> register = it.get(two, "/api/v1/student/students?prog=" + target + "&q=" + surname);
        assertThat(register.getStatusCode().value()).isEqualTo(200);
        assertThat((List<Map<String, Object>>) register.getBody().get("rows")).anyMatch(r -> student.toString().equals(String.valueOf(r.get("id"))));
        // the finding, where one was recorded, reads swapped
        assertThat(jdbc.sql("SELECT status FROM people.programme_mismatch_review WHERE student_id = :s").param("s", student).query(String.class).single()).isEqualTo("SWAPPED");

        // the same placement again changes nothing, so it is refused; a swap listed and found by its reference
        ResponseEntity<Map> again = it.call(one, HttpMethod.POST, PATH, prepareBody(student, target, 200, "PROGRAMME_CORRECTION"));
        assertThat(again.getStatusCode().value()).isEqualTo(422);
        assertThat(again.getBody()).containsEntry("code", "PSW_SAME");
        ResponseEntity<List> listed = it.getList(two, PATH + "?status=COMPLETED&q=" + prepared.getBody().get("swap_ref"));
        assertThat(listed.getStatusCode().value()).isEqualTo(200);
        assertThat((List<Map<String, Object>>) listed.getBody()).hasSize(1);
    }

    @Test
    void aTransferUnderWayBlocksASwapAndABulkSwapReportsTheStudentItSkipped() {
        UUID clear = it.student(it.freeSurname("ZZPSWB"), "C00023", null, it.freeNumber("MOAUM/PSB/86/", 6), 100);
        UUID blocked = it.student(it.freeSurname("ZZPSWC"), "C00023", null, it.freeNumber("MOAUM/PSC/86/", 6), 100);
        it.db(() -> jdbc.sql("""
                INSERT INTO people.transfer_application (student_id, session, from_programme_code, from_level, to_programme_code, reason, mode_of_entry, state)
                VALUES (:s, '2020/2021', 'C00023', 100, :t, 'transfer under way (integration test)', 'UTME', 'APPLIED')
                """).param("s", blocked).param("t", target).update());
        String ict = officer("ict", "I2");
        String ict2 = officer("ict", "I3");
        String academic = officer("academic", "A3");

        ResponseEntity<Map> refused = it.call(academic, HttpMethod.POST, PATH, prepareBody(blocked, target, 100, "PROGRAMME_CORRECTION"));
        assertThat(refused.getStatusCode().value()).isEqualTo(422);
        assertThat(refused.getBody()).containsEntry("code", "PSW_TRANSFER_OPEN");

        // the Director of ICT makes a programme correction in bulk (any kind is theirs since V633); the blocked student is skipped and said
        Map<String, Object> body = new HashMap<>(prepareBody(clear, target, 100, "PROGRAMME_CORRECTION"));
        body.remove("studentId");
        body.put("studentIds", List.of(clear.toString(), blocked.toString()));
        ResponseEntity<Map> bulk = it.call(ict, HttpMethod.POST, PATH + "/bulk", body);
        assertThat(bulk.getStatusCode().value()).as(String.valueOf(bulk.getBody())).isEqualTo(200);
        List<Map<String, Object>> swapped = (List<Map<String, Object>>) bulk.getBody().get("prepared");
        assertThat(swapped).hasSize(1);
        assertThat(swapped.get(0)).containsEntry("status", "COMPLETED");
        List<Map<String, Object>> skipped = (List<Map<String, Object>>) bulk.getBody().get("skipped");
        assertThat(skipped).hasSize(1);
        assertThat(String.valueOf(skipped.get(0).get("why"))).contains("transfer");
        String batch = String.valueOf(bulk.getBody().get("batchId"));

        // the student moved at once; the batch has nothing left for another officer to decide
        assertThat(jdbc.sql("SELECT programme_code FROM people.student WHERE id = :s").param("s", clear).query(String.class).single()).isEqualTo(target);
        assertThat(jdbc.sql("SELECT programme_code FROM people.student WHERE id = :s").param("s", blocked).query(String.class).single()).isEqualTo("C00023");
        ResponseEntity<Map> decided = it.call(ict2, HttpMethod.POST, PATH + "/batches/" + batch + "/decide", Map.of("approve", true));
        assertThat(decided.getStatusCode().value()).as(String.valueOf(decided.getBody())).isEqualTo(200);
        assertThat((List<?>) decided.getBody().get("decided")).isEmpty();
        assertThat((List<?>) decided.getBody().get("skipped")).isEmpty();

        // a Head of Department elsewhere reads none of it; a student none at all
        String other = jdbc.sql("SELECT code FROM ref.department WHERE code NOT IN (:a, :b) ORDER BY code LIMIT 1").param("a", dept).param("b", targetDept).query(String.class).single();
        String hod = it.officer("hod", "department", other);
        assertThat(it.get(hod, PATH + "/students/" + clear).getStatusCode().value()).isEqualTo(403);
        assertThat(it.call(hod, HttpMethod.POST, PATH, prepareBody(clear, "C00023", 100, "PROGRAMME_CORRECTION")).getStatusCode().value()).isEqualTo(403);
        assertThat(it.get(TestTokens.token(clear, List.of("student")), PATH + "/summary").getStatusCode().value()).isEqualTo(403);
    }

    @Test
    void theDetectorFlagsARecordWhoseNumberAndRegistrationNameAnotherDepartment() {
        String seg = jdbc.sql("SELECT coalesce(matric_code, 'ZPS') FROM ref.programme WHERE code = :p").param("p", target).query(String.class).single();
        // the target programme's students carry its segment (where it has no code of its own), and C00023's carry theirs
        if (!jdbc.sql("SELECT matric_code IS NOT NULL FROM ref.programme WHERE code = :p").param("p", target).query(Boolean.class).single()) {
            for (int i = 0; i < 3; i++) it.student(it.freeSurname("ZZPSWT"), target, null, it.freeNumber("MOAUM/ZZ/" + seg + "/86/", 6), 100);
        }
        String own = jdbc.sql("SELECT coalesce(matric_code, 'ZPC') FROM ref.programme WHERE code = 'C00023'").query(String.class).single();
        for (int i = 0; i < 6; i++) it.student(it.freeSurname("ZZPSWO"), "C00023", null, it.freeNumber("MOAUM/ZZ/" + own + "/86/", 6), 100);
        // the flagged student: on C00023, numbered in the target's series, registered on the target department's course
        String surname = it.freeSurname("ZZPSWF");
        UUID flagged = it.student(surname, "C00023", null, it.freeNumber("MOAUM/ZZ/" + seg + "/86/", 6), 200);
        String session = "3361/3362";
        it.session(session, 3361);
        String code = "ZPS " + (200 + new Random().nextInt(99));
        it.db(() -> {
            jdbc.sql("""
                    INSERT INTO catalogue.course (code, title, units, semester, level, dept_code, kind, state)
                    SELECT :c, 'Programme swap check course', 3, 1, 200, :d, 'Core', 'LIVE' WHERE NOT EXISTS (SELECT 1 FROM catalogue.course WHERE code = :c)
                    """).param("c", code).param("d", targetDept).update();
            UUID offering = UUID.randomUUID();
            jdbc.sql("INSERT INTO catalogue.offering (id, course_code, session, semester) VALUES (:o, :c, :s, 1)").param("o", offering).param("c", code).param("s", session).update();
            UUID reg = UUID.randomUUID();
            jdbc.sql("INSERT INTO registration.course_registration (id, student_id, session, semester, level, status, submitted_at, approved_at) VALUES (:r, :st, :s, 1, 200, 'APPROVED', now(), now())")
                    .param("r", reg).param("st", flagged).param("s", session).update();
            jdbc.sql("INSERT INTO registration.entry (registration_id, offering_id, units, entry_type, status) VALUES (:r, :o, 3, 'CURRENT', 'REGISTERED')").param("r", reg).param("o", offering).update();
            return null;
        });

        String academic = officer("academic", "A4");
        ResponseEntity<Map> found = it.get(academic, PATH + "/mismatches?prog=C00023&class=CONFIRMED&refresh=true&size=500");
        assertThat(found.getStatusCode().value()).as(String.valueOf(found.getBody())).isEqualTo(200);
        List<Map<String, Object>> rows = (List<Map<String, Object>>) found.getBody().get("rows");
        assertThat(rows).filteredOn(r -> flagged.toString().equals(String.valueOf(r.get("student_id")))).first().satisfies(r -> {
            assertThat(r.get("classification")).isEqualTo("CONFIRMED");
            assertThat(r.get("suggested_dept")).isEqualTo(targetDept);
            assertThat(r.get("registration_dept")).isEqualTo(targetDept);
            assertThat(r.get("review_status")).isEqualTo("NOT_REVIEWED");
        });
        // the officer's reading of it is kept and shown; the summary counts it
        ResponseEntity<Map> reviewed = it.call(academic, HttpMethod.POST, PATH + "/mismatches/" + flagged + "/review", Map.of("status", "UNDER_REVIEW", "note", "Letter requested from the department"));
        assertThat(reviewed.getStatusCode().value()).as(String.valueOf(reviewed.getBody())).isEqualTo(200);
        assertThat(reviewed.getBody()).containsEntry("status", "UNDER_REVIEW");
        ResponseEntity<Map> again = it.get(academic, PATH + "/mismatches?prog=C00023&review=UNDER_REVIEW&size=500");
        assertThat((List<Map<String, Object>>) again.getBody().get("rows")).anyMatch(r -> flagged.toString().equals(String.valueOf(r.get("student_id"))));
        ResponseEntity<Map> summary = it.get(academic, PATH + "/summary?refresh=true");
        assertThat(summary.getStatusCode().value()).isEqualTo(200);
        assertThat(((Number) summary.getBody().get("confirmed")).longValue()).isGreaterThanOrEqualTo(1);
        assertThat(summary.getBody()).containsEntry("prepares", true).containsEntry("decides", true);
        // the student's own screen shows the signals
        ResponseEntity<Map> one = it.get(academic, PATH + "/students/" + flagged);
        assertThat(one.getStatusCode().value()).isEqualTo(200);
        Map<String, Object> signals = (Map<String, Object>) one.getBody().get("signals");
        assertThat(signals).containsEntry("matric_segment", seg);
        assertThat((Map<String, Object>) signals.get("registration")).containsEntry("dept", targetDept);
    }
}
