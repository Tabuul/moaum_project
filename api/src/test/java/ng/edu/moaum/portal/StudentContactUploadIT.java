package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.List;
import java.util.Map;
import java.util.Random;
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
 * V572 and V573, end to end: the Registry counts and lists the students missing a contact, previews a file (nothing written) and
 * loads it — only the empty contacts filled, the upload kept with its counts and reason; a Head of Department of another department
 * cannot fill one, an office that does not upload is refused; the spillover work waiting is read by the Academic Office and not by
 * the Bursary. V573: the Head of Department's carryover count is the per-student rule's, and the Post-UTME audit reads its programmes.
 * Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class StudentContactUploadIT {

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    private static final String CONTACTS = "/api/v1/student-contacts";

    @Test
    void theRegistryUploadsContactsAndOnlyTheEmptyOnesAreFilled() {
        ItSupport it = new ItSupport(port, jdbc, transactions);
        int n = 10000 + new Random().nextInt(89999);
        String matA = "MOAU/SC/CTU/26/" + n, admB = "MOAUM/ADM/86/" + (200000 + n);
        UUID a = it.student("ZZCTUA" + n, "C00023", "MOAUM/ADM/86/" + (100000 + n), matA, 200);
        UUID b = it.student("ZZCTUB" + n, "C00023", admB, "MOAU/SC/CTV/26/" + n, 300);
        String phoneB = String.format("0806%07d", n), phoneA = String.format("0803%07d", n);
        it.db(() -> jdbc.sql("INSERT INTO people.student_contact (student_id, phone, updated_at) VALUES (:s, :p, now())").param("s", b).param("p", phoneB).update());
        String registrar = TestTokens.token(it.person("ZZ-CTU-RG-" + n, "ZZCTURG" + n), List.of("registrar"));
        String lecturer = TestTokens.token(it.person("ZZ-CTU-LC-" + n, "ZZCTULC" + n), List.of("lecturer"));
        String other = jdbc.sql("SELECT code FROM ref.department WHERE code <> 'MTC' AND ended_on IS NULL ORDER BY code LIMIT 1").query(String.class).single();
        String otherHod = it.officer("hod", "department", other);

        // counted and listed as missing
        Map<String, Object> summary = it.get(registrar, CONTACTS).getBody();
        assertThat(summary).containsEntry("scope", "the University").containsKeys("missing", "neither", "no_phone", "no_email", "uploads");
        List<Map<String, Object>> missing = (List<Map<String, Object>>) it.get(registrar, CONTACTS + "/missing?neitherOnly=true").getBody().get("rows");
        assertThat(missing).anySatisfy(r -> assertThat(r).containsEntry("number", matA).containsEntry("no_phone", true).containsEntry("no_email", true));
        assertThat(missing).noneSatisfy(r -> assertThat(r.get("number")).isEqualTo("MOAU/SC/CTV/26/" + n));
        assertThat(it.get(lecturer, CONTACTS).getStatusCode().value()).isEqualTo(403);

        // previewed: A filled, B's phone kept; nothing written
        List<Map<String, Object>> rows = List.of(
                Map.of("number", matA, "phone", phoneA.substring(1), "email", "ZZCTU" + n + "@Example.com"),
                Map.of("number", admB.toLowerCase(), "phone", "08039999999"),
                Map.of("number", "MOAU/SC/NONE/26/" + n, "phone", "08039999998"));
        Map<String, Object> preview = it.call(registrar, HttpMethod.POST, CONTACTS + "/upload/preview", Map.of("fileName", "contacts.xlsx", "rows", rows)).getBody();
        assertThat((Map<String, Object>) preview.get("counts")).containsEntry("FILLED", 1).containsEntry("ALREADY", 1).containsEntry("NO_STUDENT", 1);
        assertThat((Map<String, Object>) preview.get("fields")).containsEntry("phones", 1).containsEntry("emails", 1);
        assertThat(jdbc.sql("SELECT count(*) FROM people.student_contact WHERE student_id = :s").param("s", a).query(Long.class).single()).isZero();

        // a Head of Department of another department fills nothing of this one's
        Map<String, Object> outside = it.call(otherHod, HttpMethod.POST, CONTACTS + "/upload/preview", Map.of("rows", rows.subList(0, 1))).getBody();
        assertThat((Map<String, Object>) outside.get("counts")).containsEntry("OUTSIDE_SCOPE", 1).containsEntry("FILLED", 0);

        // loaded: A's phone (its leading 0 put back) and e-mail filled, B's phone kept, the upload kept
        ResponseEntity<Map> loaded = it.call(registrar, HttpMethod.POST, CONTACTS + "/upload", Map.of("fileName", "contacts.xlsx", "rows", rows));
        assertThat(loaded.getStatusCode().value()).as(String.valueOf(loaded.getBody())).isEqualTo(200);
        assertThat(jdbc.sql("SELECT phone || ':' || email FROM people.student_contact WHERE student_id = :s").param("s", a).query(String.class).single())
                .isEqualTo(phoneA + ":zzctu" + n + "@example.com");
        assertThat(jdbc.sql("SELECT phone || ':' || coalesce(email, '-') FROM people.student_contact WHERE student_id = :s").param("s", b).query(String.class).single())
                .isEqualTo(phoneB + ":-");
        Map<String, Object> upload = jdbc.sql("SELECT office, file_name, rows_read, students_filled, phones_filled, emails_filled, refused, reason FROM people.contact_upload WHERE id = :id")
                .param("id", UUID.fromString(String.valueOf(loaded.getBody().get("uploadId")))).query().singleRow();
        assertThat(upload).containsEntry("office", "registrar").containsEntry("file_name", "contacts.xlsx").containsEntry("rows_read", 3)
                .containsEntry("students_filled", 1).containsEntry("phones_filled", 1).containsEntry("emails_filled", 1).containsEntry("refused", 1)
                .containsEntry("reason", "integration test");
        assertThat((List<Map<String, Object>>) it.get(registrar, CONTACTS).getBody().get("uploads")).anySatisfy(u -> assertThat(u.get("id")).isEqualTo(loaded.getBody().get("uploadId")));
        // loaded again: held already, nothing overwritten
        Map<String, Object> again = it.call(registrar, HttpMethod.POST, CONTACTS + "/upload/preview",
                Map.of("rows", List.of(Map.of("number", matA, "phone", "08030000001", "email", "another" + n + "@example.com")))).getBody();
        assertThat((Map<String, Object>) again.get("counts")).containsEntry("ALREADY", 1);
    }

    @Test
    void theSpilloverWorkIsReadByTheAcademicOfficeAndTheHodCountIsThePerStudentRule() {
        ItSupport it = new ItSupport(port, jdbc, transactions);
        int n = 10000 + new Random().nextInt(89999);
        String academic = TestTokens.token(it.person("ZZ-SPW-AC-" + n, "ZZSPWAC" + n), List.of("academic"));
        String bursar = TestTokens.token(it.person("ZZ-SPW-BU-" + n, "ZZSPWBU" + n), List.of("bursar"));
        Map<String, Object> work = (Map<String, Object>) it.get(academic, "/api/v1/cohorts/spillover-work").getBody().get("work");
        assertThat(work).containsKeys("levelCorrections", "spilloverCorrections", "toReconcile", "graduationCandidates", "limitReached", "lastReconciledAt");
        assertThat(it.get(bursar, "/api/v1/cohorts/spillover-work").getStatusCode().value()).isEqualTo(403);

        // the Head of Department's carryover count: the department read at once, the same as student by student
        long perStudent = jdbc.sql("""
                SELECT count(*) FROM people.student st JOIN ref.programme p ON p.code = st.programme_code
                 WHERE p.dept_code = 'MTC' AND st.status IN ('ACTIVE','PROBATION') AND EXISTS (SELECT 1 FROM registration.carryovers(st.id))
                """).query(Long.class).single();
        long atOnce = jdbc.sql("SELECT count(*) FROM registration.carryover_students('MTC')").query(Long.class).single();
        assertThat(atOnce).isEqualTo(perStudent);
        // the home reads it (kept a few minutes for the department, so another test's students may not be in it yet)
        Map<String, Object> home = it.get(it.officer("hod", "department", "MTC"), "/api/v1/hod/dashboard").getBody();
        assertThat(home.get("carryoverStudents")).isInstanceOf(Number.class);

        // the Post-UTME audit reads its programmes, counted once each
        ResponseEntity<List> audit = it.callList(academic, HttpMethod.GET, "/api/v1/admissions/sessions/2025/2026/post-utme-audit", null);
        assertThat(audit.getStatusCode().value()).isEqualTo(200);
        for (Map<String, Object> r : (List<Map<String, Object>>) audit.getBody()) {
            assertThat(r).containsKeys("programme", "programme_code", "index_programme", "applications", "submitted", "applied_paid");
            assertThat(((Number) r.get("applications")).longValue()).isGreaterThanOrEqualTo(((Number) r.get("submitted")).longValue());
        }
    }
}
