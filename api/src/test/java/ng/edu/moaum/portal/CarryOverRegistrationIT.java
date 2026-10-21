package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.List;
import java.util.Map;
import java.util.Random;
import java.util.UUID;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.HttpMethod;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.web.client.RestClient;

/**
 * V597: the minimum credit load binds a registration with a current course of the programme, not one of carry-overs or of GST/EPS
 * courses alone. A 400-Level student on the CCMAS minimum (15) with one 3-unit carry-over from a published failure: the carry-over is
 * on the menu and the draft at once; a registration of the carry-over alone is submitted and approved; one with a 3-unit current
 * course beside it is refused REG_UNITS_BELOW_MINIMUM as before; one of the carry-over and a 2-unit GST course is submitted, and the
 * GST & EPS permit follows; a course the menu does not offer is refused however it is named; the Academic Office's below-minimum
 * list does not carry the waived kinds. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class CarryOverRegistrationIT {

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    ItSupport it;
    RestClient open;
    final String registrar = ItSupport.token("registrar");
    final String bursar = ItSupport.token("bursar");
    final String academic = ItSupport.token("academic");
    String before;
    String session;
    UUID s;
    String carryCode, coreCode, gstCode;
    UUID carryOffering, coreOffering, gstOffering;

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
        open = RestClient.builder().baseUrl("http://localhost:" + port).defaultStatusHandler(st -> true, (q, r) -> { }).build();
    }

    @AfterEach
    void clean() {
        it.db(() -> {
            if (session != null) {
                jdbc.sql("DELETE FROM finance.fee_schedule WHERE session = :s").param("s", session).update();
                jdbc.sql("DELETE FROM registration.approval_policy WHERE session = :s").param("s", session).update();
            }
            return null;
        });
    }

    private ResponseEntity<Map> post(String path, Object body) {
        return open.post().uri(path).contentType(MediaType.APPLICATION_JSON).body(body).retrieve().toEntity(Map.class);
    }

    private String signedIn(UUID student, String matric) {
        assertThat(it.call(registrar, HttpMethod.PUT, "/api/v1/student-auth/accounts/" + student, Map.of("password", "first password 5970")).getStatusCode().value()).isEqualTo(200);
        String t = String.valueOf(post("/api/v1/student-auth/sign-in", Map.of("matricNo", matric, "password", "first password 5970")).getBody().get("token"));
        assertThat(it.call(t, HttpMethod.POST, "/api/v1/student-auth/change-password", Map.of("current", "first password 5970", "next", "Own-Password-5970")).getStatusCode().value()).isEqualTo(200);
        return t;
    }

    private Map<String, Object> view(String token) {
        return it.get(token, "/api/v1/me/registration?session=" + session + "&semester=1").getBody();
    }

    private ResponseEntity<Map> save(String token, List<UUID> offerings) {
        return it.call(token, HttpMethod.PUT, "/api/v1/me/registration", Map.of("session", session, "semester", 1, "offerings", offerings));
    }

    private ResponseEntity<Map> submit(String token) {
        return it.call(token, HttpMethod.POST, "/api/v1/me/registration/submit", Map.of("session", session, "semester", 1));
    }

    private void reset(String token) {
        ResponseEntity<Map> r = it.call(token, HttpMethod.POST, "/api/v1/me/registration/reset", Map.of("session", session, "semester", 1));
        assertThat(r.getStatusCode().value()).as(String.valueOf(r.getBody())).isEqualTo(200);
    }

    @Test
    void aCarryOverAloneOrGstAloneIsSubmittedBelowTheMinimumWhileACurrentCourseBelowItIsRefused() {
        int y = 3900 + new Random().nextInt(90);
        before = (y - 1) + "/" + y;
        session = y + "/" + (y + 1);
        it.session(before, y - 1);
        it.session(session, y);
        String yy = String.format("%02d", y % 100);
        int n = 1000 + new Random().nextInt(8999);
        String matric = "MOAUM/ITC/" + yy + "/" + n;
        s = it.student("ZZCARRY" + n, "C00023", "MOAUM/ADM/" + yy + "/61" + n, matric, 400);
        int c = 600 + n % 199;
        for (int tries = 0; tries < 199; tries++, c = 600 + (c - 600 + 1) % 199) {
            if (jdbc.sql("SELECT count(*) FROM catalogue.course WHERE code = :g").param("g", "GST " + c).query(Long.class).single() == 0) break;
        }
        gstCode = "GST " + c;
        carryCode = "ZZC " + c;
        coreCode = "ZZD " + c;
        UUID earlier = UUID.randomUUID();
        carryOffering = UUID.randomUUID();
        coreOffering = UUID.randomUUID();
        gstOffering = UUID.randomUUID();
        it.db(() -> {
            jdbc.sql("UPDATE people.student SET curriculum_version = 'CCMAS' WHERE id = :s").param("s", s).update();
            String dept = jdbc.sql("SELECT dept_code FROM ref.programme WHERE code = 'C00023'").query(String.class).single();
            jdbc.sql("""
                    INSERT INTO catalogue.course (code, title, units, semester, level, dept_code, kind, state, general_office) VALUES
                        (:k, 'Carried core course', 3, 1, 300, :d, 'Core', 'LIVE', NULL), (:c, 'Final-year core course', 3, 1, 400, :d, 'Core', 'LIVE', NULL),
                        (:g, 'General studies course', 2, 1, 400, :d, 'GST', 'LIVE', 'GST')
                    """).param("k", carryCode).param("c", coreCode).param("g", gstCode).param("d", dept).update();
            jdbc.sql("INSERT INTO catalogue.course_offer (course_code, programme_code, level, basis) VALUES (:k, 'C00023', 300, 'Core'), (:c, 'C00023', 400, 'Core'), (:g, 'C00023', 400, 'GST')")
                    .param("k", carryCode).param("c", coreCode).param("g", gstCode).update();
            jdbc.sql("INSERT INTO catalogue.offering (id, course_code, session, semester) VALUES (:e, :k, :b, 1), (:o, :k, :s, 1), (:p, :c, :s, 1), (:q, :g, :s, 1)")
                    .param("e", earlier).param("k", carryCode).param("b", before).param("o", carryOffering).param("p", coreOffering).param("c", coreCode)
                    .param("q", gstOffering).param("g", gstCode).param("s", session).update();
            // last session: the core course failed, the result published — a carry-over by the published result alone
            UUID reg = UUID.randomUUID();
            UUID sheet = UUID.randomUUID();
            jdbc.sql("INSERT INTO registration.course_registration (id, student_id, session, semester, level, status, approved_at) VALUES (:r, :s, :b, 1, 300, 'APPROVED', now())")
                    .param("r", reg).param("s", s).param("b", before).update();
            jdbc.sql("INSERT INTO registration.entry (registration_id, offering_id, units, status) VALUES (:r, :o, 3, 'APPROVED')").param("r", reg).param("o", earlier).update();
            jdbc.sql("INSERT INTO assessment.score_sheet (id, offering_id, stage, senate_minute, published_at, submitted_at) VALUES (:id, :o, 'PUBLISHED', 'SEN/IT/597', now(), now())")
                    .param("id", sheet).param("o", earlier).update();
            return jdbc.sql("INSERT INTO assessment.score (sheet_id, student_id, ca, exam, outcome) VALUES (:sh, :s, 10, 15, 'GRADED')").param("sh", sheet).param("s", s).update();
        });
        String token = signedIn(s, matric);
        assertThat(it.call(bursar, HttpMethod.POST, "/api/v1/finance/sessions/" + session + "/schedule", Map.of("item", "School fees", "amount", 100000, "level", 400)).getStatusCode().value()).isEqualTo(200);
        Map<String, Object> ref = it.call(token, HttpMethod.POST, "/api/v1/me/fees/references", Map.of("session", session, "amount", 100000)).getBody();
        assertThat(it.call(bursar, HttpMethod.POST, "/api/v1/finance/references/" + ref.get("reference") + "/confirm", Map.of("channel", "Bank transfer", "note", "carry-over test")).getStatusCode().value()).isEqualTo(200);
        assertThat(it.call(academic, HttpMethod.PUT, "/api/v1/registration/approval/rules", Map.of("session", session, "mode", "AUTO_APPROVAL", "allowStudentReset", true,
                "cardOnApproval", true, "reason", "Integration test: automatic approval")).getStatusCode().value()).isEqualTo(200);

        // TEST 1: the carry-over is on the menu, by the published failure, for a student at 400 Level (not SP1 or SP2)
        Map<String, Object> v0 = view(token);
        assertThat((Map<String, Object>) v0.get("limit")).containsEntry("min_units", 15);
        List<Map<String, Object>> menu = (List<Map<String, Object>>) v0.get("menu");
        assertThat(menu.stream().filter(m -> carryCode.equals(m.get("course_code")))).singleElement().satisfies(m -> assertThat(m).containsEntry("carryover", true));

        // TEST 2, 12, 33: the carry-over alone (3 units, the minimum 15) is saved, submitted and approved; its kind is CARRY_OVER
        assertThat(save(token, List.of()).getStatusCode().value()).isEqualTo(200);
        ResponseEntity<Map> alone = submit(token);
        assertThat(alone.getStatusCode().value()).as(String.valueOf(alone.getBody())).isEqualTo(200);
        assertThat(alone.getBody()).containsEntry("result", "approved").containsEntry("loadKind", "CARRY_OVER");
        Map<String, Object> r1 = (Map<String, Object>) alone.getBody().get("registration");
        assertThat(r1).containsEntry("status", "APPROVED").containsEntry("units", 3);
        assertThat(jdbc.sql("SELECT count(*) FROM registration.below_minimum(:s, 1) b WHERE b.student_id = :st").param("s", session).param("st", s).query(Long.class).single()).isZero();

        // TEST 11, 35: the carry-over beside one 3-unit current course is a normal registration of 6 units — refused as before
        reset(token);
        assertThat(save(token, List.of(coreOffering)).getStatusCode().value()).isEqualTo(200);
        ResponseEntity<Map> beside = submit(token);
        assertThat(beside.getStatusCode().value()).as(String.valueOf(beside.getBody())).isEqualTo(422);
        assertThat(beside.getBody()).containsEntry("code", "REG_UNITS_BELOW_MINIMUM");
        assertThat(view(token)).containsEntry("loadKind", "NORMAL");
        assertThat(jdbc.sql("SELECT count(*) FROM registration.below_minimum(:s, 1) b WHERE b.student_id = :st").param("s", session).param("st", s).query(Long.class).single()).isEqualTo(1);

        // TEST 13-15, 20: the carry-over and a 2-unit GST course (5 units) are submitted and approved, and the GST & EPS permit follows
        reset(token);
        assertThat(save(token, List.of(gstOffering)).getStatusCode().value()).isEqualTo(200);
        ResponseEntity<Map> gst = submit(token);
        assertThat(gst.getStatusCode().value()).as(String.valueOf(gst.getBody())).isEqualTo(200);
        assertThat(gst.getBody()).containsEntry("result", "approved").containsEntry("loadKind", "GST_EPS");
        assertThat(((Map<String, Object>) gst.getBody().get("registration"))).containsEntry("units", 5);
        String permit = jdbc.sql("SELECT registration.gst_eps_permit_state(:s, :ses, 1)::text").param("s", s).param("ses", session).query(String.class).single();
        assertThat(permit).contains("\"available\": true").contains(gstCode);
        assertThat(jdbc.sql("SELECT (registration.exam_card_state(:s, :ses, 1)->>'available')::boolean").param("s", s).param("ses", session).query(Boolean.class).single()).isTrue();

        // TEST 22: an offering the menu does not hold is left out of the save however the request names it (registration.student_choose
        // keeps only this session and semester's offerings, and takes the carry-overs from the menu, never from the request): the draft
        // holds the carry-over alone, which the student can neither name nor remove
        reset(token);
        ResponseEntity<Map> named = save(token, List.of(UUID.randomUUID()));
        assertThat(named.getStatusCode().value()).as(String.valueOf(named.getBody())).isEqualTo(200);
        List<Map<String, Object>> entries = (List<Map<String, Object>>) ((Map<String, Object>) named.getBody().get("registration")).get("entries");
        assertThat(entries).hasSize(1);
        assertThat(entries.get(0)).containsEntry("entryType", "CARRYOVER").containsEntry("courseCode", carryCode);
        assertThat(named.getBody()).containsEntry("loadKind", "CARRY_OVER");
    }
}
