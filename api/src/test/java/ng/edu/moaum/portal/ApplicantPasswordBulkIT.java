package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.LinkedHashMap;
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
 * V710: the follow-ups to V706. Made-up undergraduate applicants are reset in bulk back to the JAMB number — the list checked first
 * (nothing changed), the Registry refused, then reset under one reference — and one signs in on the number, held on Change password,
 * yet reading the session policy and the manual's help. A made-up postgraduate applicant is sent the applicant's own link by the
 * Academic Office (the address masked; the link sets a new password at the sign-in page's reset and ends the change); a Database Operator
 * held to a department is refused, one over the University may; the School resets many at once by the application number. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class ApplicantPasswordBulkIT {

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
    }

    private ResponseEntity<Map> post(String path, Object body) {
        return it.anon(HttpMethod.POST, path, body);
    }

    /** a made-up applicant with a JAMB number, on a password of their own */
    private UUID applicant(String session, String jamb, String email) {
        return it.db(() -> {
            UUID cand = UUID.randomUUID();
            UUID acct = UUID.randomUUID();
            jdbc.sql("""
                    INSERT INTO admissions.candidate (id, session, jamb_reg_no, surname, other_names, programme, entry_mode, entry_level, offer_state)
                    VALUES (:c, :s, :j, 'ZZBULKAPW', 'Made Up', 'B.Sc. IT V710', 'UTME', 100, 'PROPOSED')
                    """).param("c", cand).param("s", session).param("j", jamb).update();
            jdbc.sql("""
                    INSERT INTO admissions.applicant_account (id, session, candidate_id, jamb_key, email, phone, password_hash)
                    VALUES (:a, :s, :c, :j, :e, '08037109999', crypt('A chosen password', gen_salt('bf', 12)))
                    """).param("a", acct).param("s", session).param("c", cand).param("j", jamb).param("e", email).update();
            jdbc.sql("INSERT INTO admissions.application (id, account_id, candidate_id, session, application_no) VALUES (gen_random_uuid(), :a, :c, :s, :n)")
                    .param("a", acct).param("c", cand).param("s", session).param("n", it.freeNumber("APP/" + jamb.substring(2, 4) + "/", 6)).update();
            return acct;
        });
    }

    @Test
    void undergraduatesAreResetInBulkBackToTheJambNumberAndHeldOnChangePasswordReadTheFrame() {
        int y = it.freeYear(4100, 4800);
        String session = y + "/" + (y + 1);
        it.session(session, y);
        String tag = UUID.randomUUID().toString().substring(0, 6);
        String j1 = (y + "71000001").substring(0, 12) + "ZZ";
        String j2 = (y + "71000002").substring(0, 12) + "ZZ";
        UUID a1 = applicant(session, j1, "zzbulk1." + tag + "@example.com");
        applicant(session, j2, "zzbulk2." + tag + "@example.com");
        String desk = "/api/v1/applicant-passwords/bulk";
        String support = ItSupport.token("ictagent");
        List<String> numbers = List.of(j1.toLowerCase(), "zzbulk2." + tag + "@example.com", "NOBODY-" + tag, j1);

        // checked first: nothing changed
        ResponseEntity<Map> checked = it.call(support, HttpMethod.POST, desk, Map.of("numbers", numbers, "reason", "Applicants at the screening desk could not sign in", "commit", false));
        assertThat(checked.getStatusCode().value()).as(String.valueOf(checked.getBody())).isEqualTo(200);
        assertThat((Map) checked.getBody().get("counts")).containsEntry("WILL_RESET", 2).containsEntry("NOT_FOUND", 1).containsEntry("REPEATED", 1);
        assertThat(checked.getBody().get("bulkRef")).isNull();
        assertThat(jdbc.sql("SELECT password_hash <> 'SET_ON_FIRST_LOGIN' FROM admissions.applicant_account WHERE id = :a").param("a", a1).query(Boolean.class).single()).isTrue();
        // the Registry may not; a short reason may not
        assertThat(it.call(ItSupport.token("registrar"), HttpMethod.POST, desk, Map.of("numbers", numbers, "reason", "Applicants could not sign in", "commit", true))
                .getStatusCode().value()).isEqualTo(403);
        assertThat(it.call(support, HttpMethod.POST, desk, Map.of("numbers", numbers, "reason", "short", "commit", true)).getBody().get("code")).isEqualTo("APW_REASON");

        // reset under one reference
        ResponseEntity<Map> done = it.call(support, HttpMethod.POST, desk, Map.of("numbers", numbers, "reason", "Applicants at the screening desk could not sign in", "commit", true));
        assertThat(done.getStatusCode().value()).as(String.valueOf(done.getBody())).isEqualTo(200);
        assertThat((Map) done.getBody().get("counts")).containsEntry("RESET", 2);
        String ref = String.valueOf(done.getBody().get("bulkRef"));
        assertThat(ref).matches("APW-BULK/\\d{4}/\\d{6}");
        assertThat((List<Map<String, Object>>) it.getList(support, "/api/v1/applicant-passwords/history?account=" + a1).getBody())
                .extracting(h -> h.get("bulk_ref")).containsExactly(ref);
        // V714: the bulk is listed with its counts, and opens on every row it was given
        Map<String, Object> run = ((List<Map<String, Object>>) it.getList(support, "/api/v1/applicant-passwords/bulk-runs").getBody()).stream()
                .filter(r -> ref.equals(r.get("reference"))).findFirst().orElseThrow();
        assertThat(run).containsEntry("asked", 4).containsEntry("reset", 2).containsEntry("passed_over", 2).containsEntry("kind", "UNDERGRADUATE");
        assertThat((List<Map<String, Object>>) it.get(support, "/api/v1/applicant-passwords/bulk-runs/" + run.get("id")).getBody().get("rows"))
                .extracting(r -> r.get("outcome")).containsExactly("RESET", "RESET", "NOT_FOUND", "REPEATED");
        assertThat((List<Map<String, Object>>) it.getList(support, "/api/v1/pg/applicant-passwords/bulk-runs").getBody())
                .noneMatch(r -> ref.equals(r.get("reference")));

        // the applicant signs in on the JAMB number, held on Change password — yet the frame reads the session policy and the manual
        ResponseEntity<Map> signed = post("/api/v1/applicant/sign-in", Map.of("identifier", j1, "password", j1.toLowerCase()));
        assertThat(signed.getStatusCode().value()).as(String.valueOf(signed.getBody())).isEqualTo(200);
        assertThat(signed.getBody().get("mustChange")).isEqualTo(true);
        String token = String.valueOf(signed.getBody().get("token"));
        assertThat(it.get(token, "/api/v1/applicant/me").getBody().get("code")).isEqualTo("PASSWORD_CHANGE_REQUIRED");
        assertThat(it.get(token, "/api/v1/auth/session-policy").getStatusCode().value()).isEqualTo(200);
        assertThat(it.getList(token, "/api/v1/manual/context?route=a%2Fmypassword").getStatusCode().value()).isEqualTo(200);

        // V714: the desk's link is on the one reset table — the sign-in page's reset (the general one) takes it
        ResponseEntity<Map> link = it.call(support, HttpMethod.POST, "/api/v1/applicant-passwords/" + a1 + "/reset", Map.of("method", "LINK", "reason", "The applicant asked by telephone for a link"));
        assertThat(link.getStatusCode().value()).as(String.valueOf(link.getBody())).isEqualTo(200);
        String body = jdbc.sql("SELECT n.body FROM platform.notice n WHERE n.recipient = :e AND n.channel = 'EMAIL' AND n.subject = 'Reset your MOAUM application password' ORDER BY n.created_at DESC LIMIT 1")
                .param("e", "zzbulk1." + tag + "@example.com").query(String.class).single();
        String resetToken = body.replaceAll("(?s).*token=([0-9a-f]+).*", "$1");
        assertThat(jdbc.sql("SELECT count(*) FROM iam.password_reset WHERE subject_kind = 'APPLICANT' AND subject_id = :a").param("a", a1).query(Long.class).single()).isEqualTo(1L);
        assertThat(post("/api/v1/auth/reset", Map.of("token", resetToken, "password", "A brand new password")).getStatusCode().value()).isEqualTo(200);
        ResponseEntity<Map> chosen = post("/api/v1/applicant/sign-in", Map.of("identifier", j1, "password", "A brand new password"));
        assertThat(chosen.getStatusCode().value()).isEqualTo(200);
        assertThat(chosen.getBody().get("mustChange")).isEqualTo(false);
    }

    @Test
    void thePostgraduateDeskSendsALinkTakesTheAcademicOfficeAndTheOperatorsAndResetsInBulk() {
        String programme = jdbc.sql("""
                SELECT code FROM ref.programme WHERE category = 'POST GRADUATE' AND NOT archived AND admissions.pg_award_level(pg_award) = 800 ORDER BY code LIMIT 1
                """).query(String.class).single();
        String email = "zzpgbulk." + UUID.randomUUID().toString().substring(0, 8) + "@example.com";
        ItSupport.PgPerson person = ItSupport.pgPerson("ZZPGBULK");
        Map<String, Object> f = new LinkedHashMap<>();
        f.put("surname", person.surname()); f.put("otherNames", person.otherNames()); f.put("sex", "F");
        if (person.dob() != null) f.put("dob", person.dob());
        f.put("email", email); f.put("phone", person.phone()); f.put("password", "Candidate2026!"); f.put("programme", programme);
        f.put("nationality", "Nigerian"); f.put("contactAddress", "No. 1 Test Road, Makurdi");
        f.put("priorInstitution", "Benue State University"); f.put("priorAward", "B.Sc."); f.put("priorClass", "Second Class Upper");
        ResponseEntity<Map> applied = it.anon(HttpMethod.POST, "/api/v1/pg/apply", f);
        assertThat(applied.getStatusCode().value()).as(String.valueOf(applied.getBody())).isEqualTo(200);
        UUID application = UUID.fromString(String.valueOf(applied.getBody().get("application_id")));
        Map<String, Object> row = jdbc.sql("SELECT applicant_id, application_no FROM admissions.pg_application WHERE id = :a").param("a", application).query().singleRow();
        UUID applicant = (UUID) row.get("applicant_id");
        String appNo = String.valueOf(row.get("application_no"));
        String desk = "/api/v1/pg/applicant-passwords";

        // the Academic Office sends the applicant's own link: the address masked, the link at the sign-in page's reset
        String academic = ItSupport.token("academic");
        ResponseEntity<Map> link = it.call(academic, HttpMethod.POST, desk + "/" + applicant + "/reset", Map.of("method", "LINK", "reason", "The applicant asked by telephone for a link"));
        assertThat(link.getStatusCode().value()).as(String.valueOf(link.getBody())).isEqualTo(200);
        assertThat(String.valueOf(link.getBody().get("sentTo"))).contains("@example.com").doesNotContain(email.substring(1, email.indexOf('@')));
        String body = jdbc.sql("""
                SELECT n.body FROM platform.notice n WHERE n.about_id = :a AND n.channel = 'EMAIL' AND n.subject = 'Reset your MOAUM postgraduate application password'
                 ORDER BY n.created_at DESC LIMIT 1
                """).param("a", application).query(String.class).single();
        String resetToken = body.replaceAll("(?s).*token=([0-9a-f]+).*", "$1");
        assertThat(resetToken).hasSize(48);
        assertThat(post("/api/v1/auth/reset", Map.of("token", resetToken, "password", "A brand new password")).getStatusCode().value()).isEqualTo(200);
        ResponseEntity<Map> signed = it.anon(HttpMethod.POST, "/api/v1/pg/sign-in", Map.of("identifier", email, "password", "A brand new password"));
        assertThat(signed.getStatusCode().value()).isEqualTo(200);
        assertThat(signed.getBody().get("mustChange")).isEqualTo(false);
        assertThat((List<Map<String, Object>>) it.getList(academic, desk + "/history?applicant=" + applicant).getBody())
                .extracting(h -> h.get("method")).containsExactly("RESET_LINK");

        // a Database Operator held to a department is refused; one over the University may
        String heldOperator = it.officer("dbops", "department", jdbc.sql("SELECT code FROM ref.department ORDER BY code LIMIT 1").query(String.class).single());
        assertThat(it.get(heldOperator, desk + "/search?q=" + appNo).getBody().get("code")).isEqualTo("SCOPE_UNIVERSITY");
        assertThat((List<Map<String, Object>>) it.getList(it.officer("dbops", "institution", "University"), desk + "/search?q=" + appNo).getBody())
                .extracting(h -> h.get("application_no")).containsExactly(appNo);

        // the School resets many at once by the application number: the applicant signs in on it, held to change it
        ResponseEntity<Map> bulk = it.call(ItSupport.token("pgsecretary"), HttpMethod.POST, desk + "/bulk",
                Map.of("numbers", List.of(appNo.toLowerCase(), "nobody." + UUID.randomUUID() + "@example.com"), "reason", "Applicants at the School could not sign in", "commit", true));
        assertThat(bulk.getStatusCode().value()).as(String.valueOf(bulk.getBody())).isEqualTo(200);
        assertThat((Map) bulk.getBody().get("counts")).containsEntry("RESET", 1).containsEntry("NOT_FOUND", 1);
        assertThat(it.anon(HttpMethod.POST, "/api/v1/pg/sign-in", Map.of("identifier", email, "password", "A brand new password")).getStatusCode().value()).isEqualTo(422);
        ResponseEntity<Map> onNumber = it.anon(HttpMethod.POST, "/api/v1/pg/sign-in", Map.of("identifier", email, "password", appNo.toLowerCase()));
        assertThat(onNumber.getStatusCode().value()).as(String.valueOf(onNumber.getBody())).isEqualTo(200);
        assertThat(onNumber.getBody().get("mustChange")).isEqualTo(true);
    }
}
