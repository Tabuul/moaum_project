package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

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
 * V694: a postgraduate applicant applies once a session, and the desk sees when each application was made, where its document
 * upload stands and any application made twice. The same person under another email — the name's words in another order, the
 * phone as +234… — is refused, naming the first email masked; a namesake with another date of birth and phone is taken; an
 * application made twice before V694 is flagged on the desk with the other's number, and once the one is paid the other is not
 * issued a fee reference. Paid with nothing uploaded, the application is on the "paid, not uploaded" list; with some uploaded it
 * is pending with the others named; with all, complete. The passport comes to the application form as a JPEG. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class PgOneApplicationIT {

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    ItSupport it;
    final String secretary = ItSupport.token("pgsecretary");
    String school;

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
        school = TestTokens.token(it.person("ZZPG-ONCE", "ZZPGONCESCHOOL"), List.of("pgschool"));
    }

    private static Map<String, Object> form(String surname, String otherNames, String dob, String phone, String email, String programme) {
        Map<String, Object> f = new LinkedHashMap<>();
        f.put("surname", surname); f.put("otherNames", otherNames); f.put("sex", "F");
        if (dob != null) f.put("dob", dob);
        f.put("email", email); f.put("phone", phone); f.put("password", "Candidate2026!"); f.put("programme", programme);
        f.put("nationality", "Nigerian"); f.put("contactAddress", "No. 1 Test Road, Makurdi");
        f.put("priorInstitution", "Benue State University"); f.put("priorAward", "B.Sc."); f.put("priorClass", "Second Class Upper");
        return f;
    }

    private static String email(String tag) {
        return "zzpg" + tag + "." + UUID.randomUUID().toString().substring(0, 8) + "@example.com";
    }

    private Map<String, Object> rowOf(List<Map<String, Object>> rows, UUID app) {
        return rows.stream().filter(r -> app.toString().equals(String.valueOf(r.get("id")))).findFirst().orElse(null);
    }

    private List<Map<String, Object>> desk(String session, String narrowing) {
        ResponseEntity<Map> r = it.get(school, u -> {
            org.springframework.web.util.UriBuilder b = u.path("/api/v1/pg/applications").queryParam("session", session);
            return (narrowing == null ? b : b.query(narrowing)).build();
        });
        assertThat(r.getStatusCode().value()).as(String.valueOf(r.getBody())).isEqualTo(200);
        return (List<Map<String, Object>>) r.getBody().get("rows");
    }

    private static String pdf() {
        try (org.apache.pdfbox.pdmodel.PDDocument d = new org.apache.pdfbox.pdmodel.PDDocument(); java.io.ByteArrayOutputStream out = new java.io.ByteArrayOutputStream()) {
            d.addPage(new org.apache.pdfbox.pdmodel.PDPage());
            d.save(out);
            return java.util.Base64.getEncoder().encodeToString(out.toByteArray());
        } catch (java.io.IOException e) {
            throw new IllegalStateException(e);
        }
    }

    private static String png() {
        try (java.io.ByteArrayOutputStream out = new java.io.ByteArrayOutputStream()) {
            javax.imageio.ImageIO.write(new java.awt.image.BufferedImage(30, 40, java.awt.image.BufferedImage.TYPE_INT_ARGB), "png", out);
            return java.util.Base64.getEncoder().encodeToString(out.toByteArray());
        } catch (java.io.IOException e) {
            throw new IllegalStateException(e);
        }
    }

    @Test
    void aPersonAppliesOnceASessionAndTheDeskSeesWhenTheDocumentsAndAnyApplicationMadeTwice() {
        String programme = jdbc.sql("""
                SELECT code FROM ref.programme WHERE category = 'POST GRADUATE' AND NOT archived AND admissions.pg_award_level(pg_award) = 800 ORDER BY code LIMIT 1
                """).query(String.class).single();
        ItSupport.PgPerson ada = ItSupport.pgPerson("ZZPGONCE");
        String first = email("once");
        ResponseEntity<Map> one = it.anon(HttpMethod.POST, "/api/v1/pg/apply", form(ada.surname(), ada.otherNames(), ada.dob(), ada.phone(), first, programme));
        assertThat(one.getStatusCode().value()).as(String.valueOf(one.getBody())).isEqualTo(200);
        UUID app1 = UUID.fromString(String.valueOf(one.getBody().get("application_id")));
        String ref1 = String.valueOf(one.getBody().get("reference"));
        String session = jdbc.sql("SELECT session FROM admissions.pg_application WHERE id = :a").param("a", app1).query(String.class).single();

        // ── the same person again under another email: the name's words in another order, the phone as +234… — refused, the first email masked ──
        String second = email("twice");
        ResponseEntity<Map> again = it.anon(HttpMethod.POST, "/api/v1/pg/apply",
                form(ada.otherNames().toUpperCase(), ada.surname().toLowerCase(), ada.dob(), "+234" + ada.phone().substring(1), second, programme));
        assertThat(again.getStatusCode().value()).as(String.valueOf(again.getBody())).isEqualTo(422);
        assertThat(again.getBody()).containsEntry("code", "PG_APP_DUPLICATE");
        String masked = first.charAt(0) + "***" + first.substring(first.indexOf('@') - 1);
        assertThat(String.valueOf(again.getBody().get("detail"))).contains(session).contains(masked).doesNotContain(first);
        assertThat(jdbc.sql("SELECT count(*) FROM admissions.pg_applicant WHERE email = :e").param("e", second).query(Long.class).single()).isZero();
        // the date of birth and the phone agree, the name spelt otherwise: still the same person
        ResponseEntity<Map> respelt = it.anon(HttpMethod.POST, "/api/v1/pg/apply", form(ada.surname(), "Zzsomeoneelse", ada.dob(), ada.phone(), email("respelt"), programme));
        assertThat(respelt.getBody()).containsEntry("code", "PG_APP_DUPLICATE");
        // without a date of birth the door does not take it
        ResponseEntity<Map> noDob = it.anon(HttpMethod.POST, "/api/v1/pg/apply", form(ada.surname(), ada.otherNames(), null, null, email("nodob"), programme));
        assertThat(noDob.getStatusCode().value()).isEqualTo(422);
        assertThat(noDob.getBody()).containsEntry("code", "PG_APPLY_DOB");

        // ── a namesake — the same name, another date of birth and phone — is another person, and is taken ──
        ItSupport.PgPerson other = ItSupport.pgPerson("ZZPGONCE");
        ResponseEntity<Map> namesake = it.anon(HttpMethod.POST, "/api/v1/pg/apply", form(ada.surname(), ada.otherNames(), other.dob(), other.phone(), email("namesake"), programme));
        assertThat(namesake.getStatusCode().value()).as(String.valueOf(namesake.getBody())).isEqualTo(200);
        UUID app3 = UUID.fromString(String.valueOf(namesake.getBody().get("application_id")));

        // ── the desk: when each was made, the fee unpaid so nothing to upload yet, each made once ──
        Map<String, Object> row = rowOf(desk(session, null), app1);
        assertThat(row).isNotNull();
        assertThat(row.get("applied_at")).isNotNull();
        assertThat(row.get("documents_state")).isEqualTo("FEE_UNPAID");
        assertThat(((Number) row.get("times_applied")).intValue()).isEqualTo(1);
        assertThat(row.get("also_applied")).isNull();

        // ── an application made twice before V694: a second account of Ada's, written in as the old door let it be ──
        UUID app2 = it.db(() -> {
            UUID applicant = jdbc.sql("""
                    INSERT INTO admissions.pg_applicant (session, surname, other_names, date_of_birth, email, phone, password_hash)
                    VALUES (:s, :sn, :on, :d::date, :e, :p, '$2a$12$' || repeat('x', 53)) RETURNING id
                    """).param("s", session).param("sn", ada.surname()).param("on", ada.otherNames()).param("d", ada.dob())
                    .param("e", email("before")).param("p", ada.phone()).query(UUID.class).single();
            return jdbc.sql("""
                    INSERT INTO admissions.pg_application (applicant_id, session, application_no, programme_code, entry_level, state, submitted_at)
                    VALUES (:a, :s, 'PG/' || substr(:s, 3, 2) || '/' || lpad(platform.next_number('PG_APPLICATION', 'UNIVERSITY', :s)::text, 6, '0'),
                            :g, 800, 'SUBMITTED', now()) RETURNING id
                    """).param("a", applicant).param("s", session).param("g", programme).query(UUID.class).single();
        });
        String no1 = jdbc.sql("SELECT application_no FROM admissions.pg_application WHERE id = :a").param("a", app1).query(String.class).single();
        String no2 = jdbc.sql("SELECT application_no FROM admissions.pg_application WHERE id = :a").param("a", app2).query(String.class).single();
        List<Map<String, Object>> twice = desk(session, "duplicates=true");
        assertThat(rowOf(twice, app3)).as("a namesake is not flagged").isNull();
        assertThat(rowOf(twice, app1)).containsEntry("also_applied", no2);
        assertThat(((Number) rowOf(twice, app1).get("times_applied")).intValue()).isEqualTo(2);
        assertThat(rowOf(twice, app2)).containsEntry("also_applied", no1);
        ResponseEntity<Map> detail = it.get(school, "/api/v1/pg/applications/" + app2);
        List<Map<String, Object>> also = (List<Map<String, Object>>) detail.getBody().get("alsoApplied");
        assertThat(also).extracting(m -> m.get("application_no")).containsExactly(no1);
        assertThat(also.get(0)).containsEntry("matched_on", "name, date of birth, phone").containsEntry("email", masked);

        // ── Ada's first application paid: the one made twice is issued no application-fee reference ──
        ResponseEntity<Map> paid = it.call(secretary, HttpMethod.POST, "/api/v1/pg/applications/" + app1 + "/confirm-fee", Map.of("reference", ref1));
        assertThat(paid.getStatusCode().value()).as(String.valueOf(paid.getBody())).isEqualTo(200);
        assertThatThrownBy(() -> it.db(() -> jdbc.sql("SELECT admissions.pg_new_fee_reference(:a, 'APPLICATION')").param("a", app2).query(String.class).single()))
                .hasMessageContaining("PG_APP_DUPLICATE_PAID");

        // ── paid, nothing uploaded: on the "paid, not uploaded" list ──
        assertThat(rowOf(desk(session, "documents=NONE"), app1)).isNotNull().containsEntry("documents_state", "NONE");
        assertThat(rowOf(desk(session, "documents=NONE"), app3)).as("the namesake has not paid").isNull();

        // ── Ada uploads the passport (a PNG) and one certificate: pending, the others named ──
        ResponseEntity<Map> signedIn = it.anon(HttpMethod.POST, "/api/v1/pg/sign-in", Map.of("identifier", first, "password", "Candidate2026!"));
        assertThat(signedIn.getStatusCode().value()).as(String.valueOf(signedIn.getBody())).isEqualTo(200);
        String applicant = String.valueOf(signedIn.getBody().get("token"));
        assertThat(it.call(applicant, HttpMethod.POST, "/api/v1/pg/passport", Map.of("filename", "me.png", "contentType", "image/png", "base64", png()))
                .getStatusCode().value()).isEqualTo(200);
        String doc = pdf();
        assertThat(it.call(applicant, HttpMethod.POST, "/api/v1/pg/documents",
                Map.of("kind", "UNDERGRAD_CERT", "filename", "degree.pdf", "contentType", "application/pdf", "base64", doc)).getStatusCode().value()).isEqualTo(200);
        Map<String, Object> pending = rowOf(desk(session, "documents=PENDING"), app1);
        assertThat(pending).isNotNull().containsEntry("documents_missing", "OLEVEL,BIRTH_CERTIFICATE,NYSC,LGA_CERTIFICATE");
        assertThat(((Number) pending.get("documents_uploaded")).intValue()).isEqualTo(2);
        assertThat(((Number) pending.get("documents_required")).intValue()).isEqualTo(6);

        // ── the rest uploaded: complete ──
        for (String kind : List.of("OLEVEL", "BIRTH_CERTIFICATE", "NYSC", "LGA_CERTIFICATE")) {
            ResponseEntity<Map> up = it.call(applicant, HttpMethod.POST, "/api/v1/pg/documents",
                    Map.of("kind", kind, "filename", kind.toLowerCase() + ".pdf", "contentType", "application/pdf", "base64", doc));
            assertThat(up.getStatusCode().value()).as(String.valueOf(up.getBody())).isEqualTo(200);
        }
        Map<String, Object> complete = rowOf(desk(session, "documents=COMPLETE"), app1);
        assertThat(complete).isNotNull();
        assertThat(complete.get("documents_missing")).isNull();
        Map<String, Object> counts = (Map<String, Object>) it.get(school, u -> u.path("/api/v1/pg/applications").queryParam("session", session).build()).getBody().get("counts");
        assertThat(((Number) counts.get("documents_complete")).intValue()).isGreaterThanOrEqualTo(1);
        assertThat(((Number) counts.get("duplicates")).intValue()).isGreaterThanOrEqualTo(2);

        // ── the passport comes to the application form as a JPEG; a Head of Department of no department reaches nothing ──
        ResponseEntity<byte[]> jpeg = it.getBytes(school, "/api/v1/pg/applications/" + app1 + "/passport.jpg");
        assertThat(jpeg.getStatusCode().value()).isEqualTo(200);
        assertThat(String.valueOf(jpeg.getHeaders().getContentType())).isEqualTo("image/jpeg");
        assertThat(jpeg.getBody()[0]).isEqualTo((byte) 0xFF);
        assertThat(jpeg.getBody()[1]).isEqualTo((byte) 0xD8);
        assertThat(it.getBytes(ItSupport.token("hod"), "/api/v1/pg/applications/" + app1 + "/passport.jpg").getStatusCode().value()).isEqualTo(403);
        // a filter the desk does not offer is refused
        assertThat(it.get(school, u -> u.path("/api/v1/pg/applications").queryParam("session", session).queryParam("documents", "SOME").build())
                .getBody()).containsEntry("code", "PG_DOCUMENTS_FILTER");
    }
}
