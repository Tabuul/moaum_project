package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

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
 * V428 — a person's own number is never their password, at any door. A migrated student's matriculation number no longer opens the
 * account, whether offered as the old default or stored as a hash; the migration desk's "default passwords" are retired; the reset
 * link sets the first password, never the number; the Registry's first password is never the number, and the student then chooses
 * one without a current password; a lecturer's staff number opens nothing, and the teaching-staff upload gives a password nobody
 * knows; a migrated applicant's JAMB number opens nothing. Runs again on the same database. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class FirstSignInIT {

    static final String SESSION = "2086/2087";

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
        it.session(SESSION, 2086);
    }

    private static void refused(ResponseEntity<Map> r, String code) {
        assertThat(r.getStatusCode().value()).as(String.valueOf(r.getBody())).isEqualTo(422);
        assertThat(r.getBody().get("code")).isEqualTo(code);
    }

    private static Map<String, Object> ok(ResponseEntity<Map> r) {
        assertThat(r.getStatusCode().is2xxSuccessful()).as(String.valueOf(r.getBody())).isTrue();
        return r.getBody();
    }

    @Test
    void aPersonsOwnNumberOpensNoDoorAndTheFirstPasswordIsChosen() {
        int n = new Random().nextInt(8000) + 1000;
        String matric = "MOAUM/OWN/86/" + n;
        UUID student = it.student("ITOWNNUMBER" + n, "C00061", "MOAUM/ADM/86/7" + n + "0", matric, 100);
        // a migrated account on a password nobody knows, still to be changed — as the import leaves it
        it.db(() -> jdbc.sql("""
                INSERT INTO iam.student_account (id, student_id, password_hash, must_change) VALUES (gen_random_uuid(), :s, crypt(gen_random_uuid()::text, gen_salt('bf', 12)), true)
                ON CONFLICT (student_id) DO UPDATE SET password_hash = EXCLUDED.password_hash, must_change = true, failed_attempts = 0, locked_until = NULL,
                    temp_expires_at = NULL, temp_issued_by = NULL, temp_used_at = NULL
                """).param("s", student).update());

        // (1) the first sign-in (V178, V122): while the account is still on its first password, the matriculation number is that
        //     password — not the admission number once one is issued, nor anything else — with the change forced before anything else;
        //     the number opens it again while the change is pending, and the change takes the number, or nothing, as the current one
        refused(it.anon(HttpMethod.POST, "/api/v1/student-auth/sign-in", Map.of("matricNo", matric, "password", "not the password " + n)), "AUTH_BAD_CREDENTIALS");
        refused(it.anon(HttpMethod.POST, "/api/v1/student-auth/sign-in", Map.of("matricNo", matric, "password", "MOAUM/ADM/86/7" + n + "0")), "AUTH_FIRST_PASSWORD_RETIRED");
        Map<String, Object> first = ok(it.anon(HttpMethod.POST, "/api/v1/student-auth/sign-in", Map.of("matricNo", matric, "password", matric)));
        assertThat(first.get("mustChange")).isEqualTo(true);
        ok(it.anon(HttpMethod.POST, "/api/v1/student-auth/sign-in", Map.of("matricNo", matric, "password", matric.toLowerCase())));
        String firstToken = String.valueOf(first.get("token"));
        refused(it.call(firstToken, HttpMethod.POST, "/api/v1/student-auth/change-password", Map.of("current", matric, "next", matric)), "AUTH_PASSWORD_IS_NUMBER");
        ok(it.call(firstToken, HttpMethod.POST, "/api/v1/student-auth/change-password", Map.of("current", matric, "next", "chosen at the door " + n)));
        // chosen, the number opens nothing more — and the chosen password does
        refused(it.anon(HttpMethod.POST, "/api/v1/student-auth/sign-in", Map.of("matricNo", matric, "password", matric)), "AUTH_FIRST_PASSWORD_RETIRED");
        Map<String, Object> chosen = ok(it.anon(HttpMethod.POST, "/api/v1/student-auth/sign-in", Map.of("matricNo", matric, "password", "chosen at the door " + n)));
        assertThat(chosen.get("mustChange")).isEqualTo(false);
        // (2) the number stored as a hash by the migration desk's old default on an account whose password was chosen: refused in any case
        it.db(() -> jdbc.sql("UPDATE iam.student_account SET password_hash = crypt(:m, gen_salt('bf', 12)) WHERE student_id = :s")
                .param("m", matric).param("s", student).update());
        refused(it.anon(HttpMethod.POST, "/api/v1/student-auth/sign-in", Map.of("matricNo", matric, "password", matric.toLowerCase())), "AUTH_FIRST_PASSWORD_RETIRED");
        // (3) the migration desk's "default passwords": the endpoint is gone (GAP-014) and the function refuses (check.sql, V428)
        assertThat(it.call(ItSupport.token("records"), HttpMethod.POST, "/api/v1/results/legacy/default-passwords", Map.of()).getStatusCode().is2xxSuccessful()).isFalse();

        // (4) the reset link sets the first password — never the number
        String token = "it-first-sign-in-" + UUID.randomUUID();
        it.db(() -> jdbc.sql("""
                INSERT INTO iam.password_reset (subject_kind, subject_id, token_hash, expires_at)
                VALUES ('STUDENT', :s, encode(sha256(convert_to(:t, 'UTF8')), 'hex'), now() + interval '1 hour')
                """).param("s", student).param("t", token).update());
        refused(it.anon(HttpMethod.POST, "/api/v1/auth/reset", Map.of("token", token, "password", matric)), "AUTH_PASSWORD_IS_NUMBER");
        ok(it.anon(HttpMethod.POST, "/api/v1/auth/reset", Map.of("token", token, "password", "my own password " + n)));
        ok(it.anon(HttpMethod.POST, "/api/v1/student-auth/sign-in", Map.of("matricNo", matric, "password", "my own password " + n)));

        // (5) the Registry's first password is never the number; the student then chooses one without a current password
        String registrar = ItSupport.token("registrar");
        refused(it.call(registrar, HttpMethod.PUT, "/api/v1/student-auth/accounts/" + student, Map.of("password", matric)), "AUTH_PASSWORD_IS_NUMBER");
        ok(it.call(registrar, HttpMethod.PUT, "/api/v1/student-auth/accounts/" + student, Map.of("password", "first password " + n)));
        Map<String, Object> signed = ok(it.anon(HttpMethod.POST, "/api/v1/student-auth/sign-in", Map.of("matricNo", matric, "password", "first password " + n)));
        assertThat(signed.get("mustChange")).isEqualTo(true);
        String studentToken = String.valueOf(signed.get("token"));
        refused(it.call(studentToken, HttpMethod.POST, "/api/v1/student-auth/change-password", Map.of("current", "", "next", matric)), "AUTH_PASSWORD_IS_NUMBER");
        ok(it.call(studentToken, HttpMethod.POST, "/api/v1/student-auth/change-password", Map.of("current", "", "next", "chosen password " + n)));
        ok(it.anon(HttpMethod.POST, "/api/v1/student-auth/sign-in", Map.of("matricNo", matric, "password", "chosen password " + n)));

        // (6) a lecturer's staff number is the first password until one is chosen (the University's decision, 13 Oct 2026): it opens
        //     the account must-change, stands for the current password at the change, is never the password chosen, and opens nothing
        //     once one is; the teaching-staff upload stores a password nobody knows
        String staffNo = "P9" + n;
        UUID person = it.person(staffNo, "ZZOWNSTAFF" + n);
        it.db(() -> jdbc.sql("""
                INSERT INTO iam.credential (person_id, username, password_hash, must_change, set_by) VALUES (:p, lower(:u), crypt(gen_random_uuid()::text, gen_salt('bf', 12)), true, :p)
                ON CONFLICT (person_id) DO UPDATE SET password_hash = EXCLUDED.password_hash, must_change = true, failed_attempts = 0, locked_until = NULL
                """).param("p", person).param("u", staffNo).update());
        it.db(() -> jdbc.sql("""
                INSERT INTO iam.office_assignment (id, person_id, office_code, scope_kind, scope_id, instrument, granted_by, valid_from)
                VALUES (gen_random_uuid(), :p, 'lecturer', 'department', 'MTC', 'integration test', :p, current_date)
                """).param("p", person).update());
        Map<String, Object> staffFirst = ok(it.anon(HttpMethod.POST, "/api/v1/auth/sign-in", Map.of("username", staffNo, "password", staffNo)));
        assertThat(staffFirst.get("mustChange")).isEqualTo(true);
        String staffToken = String.valueOf(staffFirst.get("token"));
        Map<String, String> asLecturer = Map.of("X-Active-Office", "lecturer");
        assertThat(it.callWith(staffToken, HttpMethod.POST, "/api/v1/auth/change-password", Map.of("current", staffNo, "next", staffNo), asLecturer).getStatusCode().value()).isEqualTo(422);
        ok(it.callWith(staffToken, HttpMethod.POST, "/api/v1/auth/change-password", Map.of("current", staffNo, "next", "chosen staff password " + n), asLecturer));
        refused(it.anon(HttpMethod.POST, "/api/v1/auth/sign-in", Map.of("username", staffNo, "password", staffNo)), "AUTH_FIRST_PASSWORD_RETIRED");
        ok(it.anon(HttpMethod.POST, "/api/v1/auth/sign-in", Map.of("username", staffNo, "password", "chosen staff password " + n)));
        String pno = "8" + n;
        String dept = jdbc.sql("SELECT dept_code FROM ref.programme WHERE code = 'C00061'").query(String.class).single();
        it.db(() -> jdbc.sql("SELECT * FROM iam.import_lecturers(:j::jsonb)")
                .param("j", "[{\"pno\":\"" + pno + "\",\"full_names\":\"Dr Invented Uploaded" + n + "\",\"department\":\"" + dept + "\",\"sex\":\"F\"}]")
                .query().listOfRows());
        Boolean ownNumberHash = jdbc.sql("SELECT crypt('P' || :p, c.password_hash) = c.password_hash FROM iam.credential c WHERE c.username = lower('P' || :p)")
                .param("p", pno).query(Boolean.class).optional().orElse(null);
        assertThat(ownNumberHash).as("the upload's credential for P" + pno).isFalse();

        // (7) a migrated applicant on the first-login sentinel signs in with the JAMB number (V178); a chosen password ends that
        String jamb = "8086" + String.format("%08d", n) + "OW";
        it.db(() -> {
            UUID cand = UUID.randomUUID();
            jdbc.sql("""
                    INSERT INTO admissions.candidate (id, session, jamb_reg_no, surname, other_names, programme, entry_mode, entry_level, offer_state)
                    VALUES (:id, :s, :j, :sn, 'Invented', (SELECT name FROM ref.programme WHERE code = 'C00061'), 'UTME', 100, 'PROPOSED')
                    ON CONFLICT DO NOTHING
                    """).param("id", cand).param("s", SESSION).param("j", jamb).param("sn", "ZZOWNAPP" + n).update();
            UUID c = jdbc.sql("SELECT id FROM admissions.candidate WHERE session = :s AND jamb_reg_no = :j").param("s", SESSION).param("j", jamb).query(UUID.class).single();
            UUID acct = UUID.randomUUID();
            jdbc.sql("""
                    INSERT INTO admissions.applicant_account (id, session, candidate_id, jamb_key, email, phone, password_hash)
                    VALUES (:id, :s, :c, :k, :e, '08030000000', 'SET_ON_FIRST_LOGIN')
                    """).param("id", acct).param("s", SESSION).param("c", c).param("k", jamb).param("e", jamb.toLowerCase() + "@example.com").update();
            // the door finds an account through its application, as every migrated applicant has one
            jdbc.sql("INSERT INTO admissions.application (id, account_id, candidate_id, session, application_no) VALUES (gen_random_uuid(), :a, :c, :s, :no)")
                    .param("a", acct).param("c", c).param("s", SESSION).param("no", "APP/86/97" + n).update();
            return null;
        });
        ok(it.anon(HttpMethod.POST, "/api/v1/applicant/sign-in", Map.of("identifier", jamb, "password", jamb)));
        it.db(() -> jdbc.sql("UPDATE admissions.applicant_account SET password_hash = crypt('chosen applicant password', gen_salt('bf', 12)) WHERE jamb_key = :k")
                .param("k", jamb).update());
        refused(it.anon(HttpMethod.POST, "/api/v1/applicant/sign-in", Map.of("identifier", jamb, "password", jamb)), "AUTH_FIRST_PASSWORD_RETIRED");
    }
}
