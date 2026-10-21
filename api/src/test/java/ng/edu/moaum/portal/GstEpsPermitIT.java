package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.Random;
import java.util.UUID;

import ng.edu.moaum.portal.shared.CheckCodes;
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
 * The GST & EPS examination permit card (V492; V589: issued on the examination card's own terms — a registration submitted and
 * the school fees paid — and the GST fee, with no approval, clearance scheme or release switch between, and read without a count
 * from ICT Support's view of the student's portal): a permit carries only the GST and EPS courses on the student's submitted
 * registration for the semester — GST only, EPS only, both, none (no permit), never a departmental course, never a course of
 * another semester, never one the student did not register; a reset takes the courses off, a new registration puts the new ones
 * on, under the same permit number; the GST fee the gate asks for holds it; the student's own door names no student; the GST and
 * EPS offices read and withdraw only the permits of their own courses; the public verification says VALID, REVOKED, INVALID or
 * NOT_FOUND. The rules are read for the run's own session through the database's functions (the student's door always stands in
 * the University's current session). Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class GstEpsPermitIT {

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;
    @Autowired
    CheckCodes codes;

    ItSupport it;
    RestClient open;
    final String registrar = ItSupport.token("registrar");
    final String bursar = ItSupport.token("bursar");
    final String gst = ItSupport.token("gst");
    final String eps = ItSupport.token("eps");
    final String instrument = "BUR/IT/PERMIT492";
    String session;
    Map<String, Object> setting;

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
        open = RestClient.builder().baseUrl("http://localhost:" + port).defaultStatusHandler(s -> true, (q, r) -> { }).build();
        setting = jdbc.sql("SELECT required_for_gst_eps, required_for_all, covers_eps FROM finance.gst_setting WHERE id = 1").query().singleRow();
    }

    /** the run's fee lines, GST fee and clearance scheme go, and the GST rule is as it was */
    @AfterEach
    void clean() {
        it.db(() -> {
            if (session != null) {
                jdbc.sql("DELETE FROM finance.fee_schedule WHERE session = :s").param("s", session).update();
                jdbc.sql("DELETE FROM finance.gst_fee WHERE session = :s").param("s", session).update();
                jdbc.sql("DELETE FROM registration.approval_policy WHERE session = :s").param("s", session).update();
            }
            jdbc.sql("UPDATE finance.gst_setting SET required_for_gst_eps = :a, required_for_all = :b, covers_eps = :c WHERE id = 1")
                    .param("a", setting.get("required_for_gst_eps")).param("b", setting.get("required_for_all")).param("c", setting.get("covers_eps")).update();
            jdbc.sql("DELETE FROM policy.clearance_rule WHERE version_id IN (SELECT id FROM policy.version WHERE instrument = :i)").param("i", instrument).update();
            jdbc.sql("DELETE FROM policy.clearance_scheme WHERE version_id IN (SELECT id FROM policy.version WHERE instrument = :i)").param("i", instrument).update();
            return jdbc.sql("DELETE FROM policy.version WHERE instrument = :i").param("i", instrument).update();
        });
    }

    private ResponseEntity<Map> post(String path, Object body) {
        return open.post().uri(path).contentType(MediaType.APPLICATION_JSON).body(body).retrieve().toEntity(Map.class);
    }

    private String signedIn(UUID student, String matric) {
        assertThat(it.call(registrar, HttpMethod.PUT, "/api/v1/student-auth/accounts/" + student, Map.of("password", "first password 4920")).getStatusCode().value()).isEqualTo(200);
        String t = String.valueOf(post("/api/v1/student-auth/sign-in", Map.of("matricNo", matric, "password", "first password 4920")).getBody().get("token"));
        assertThat(it.call(t, HttpMethod.POST, "/api/v1/student-auth/change-password", Map.of("current", "first password 4920", "next", "Own-Password-4920")).getStatusCode().value()).isEqualTo(200);
        return t;
    }

    private void payInFull(String token, String s) {
        pay(token, s, 100000);
    }

    private void pay(String token, String s, int amount) {
        Map<String, Object> ref = it.call(token, HttpMethod.POST, "/api/v1/me/fees/references", Map.of("session", s, "amount", amount)).getBody();
        ResponseEntity<Map> ok = it.call(bursar, HttpMethod.POST, "/api/v1/finance/references/" + ref.get("reference") + "/confirm", Map.of("channel", "Bank transfer", "note", "permit test"));
        assertThat(ok.getStatusCode().value()).as(String.valueOf(ok.getBody())).isEqualTo(200);
    }

    /** V589: a registration submitted and waiting for the Head, never approved, with the courses given */
    private void submitted(UUID student, int semester, String... courses) {
        it.db(() -> {
            UUID reg = jdbc.sql("""
                    INSERT INTO registration.course_registration (id, student_id, session, semester, level, status, submitted_at)
                    VALUES (gen_random_uuid(), :st, :s, :sem, 100, 'SUBMITTED', now()) RETURNING id
                    """).param("st", student).param("s", session).param("sem", semester).query(UUID.class).single();
            for (String c : courses) {
                jdbc.sql("""
                        INSERT INTO registration.entry (registration_id, offering_id, units, entry_type, status)
                        SELECT :r, o.id, c.units, 'CURRENT', 'REGISTERED' FROM catalogue.offering o JOIN catalogue.course c ON c.code = o.course_code
                         WHERE o.course_code = :c AND o.session = :s AND o.semester = :sem AND o.stream = 'REGULAR'
                        """).param("r", reg).param("c", c).param("s", session).param("sem", semester).update();
            }
            return reg;
        });
    }

    /** an approved registration (as the old portal's were brought over: no approver, no approval mode) with the courses given */
    private void approved(UUID student, int semester, String... courses) {
        it.db(() -> {
            UUID reg = jdbc.sql("""
                    INSERT INTO registration.course_registration (id, student_id, session, semester, level, status, submitted_at, approved_at)
                    VALUES (gen_random_uuid(), :st, :s, :sem, 100, 'APPROVED', now(), now()) RETURNING id
                    """).param("st", student).param("s", session).param("sem", semester).query(UUID.class).single();
            for (String c : courses) {
                jdbc.sql("""
                        INSERT INTO registration.entry (registration_id, offering_id, units, entry_type, status)
                        SELECT :r, o.id, c.units, 'CURRENT', 'APPROVED' FROM catalogue.offering o JOIN catalogue.course c ON c.code = o.course_code
                         WHERE o.course_code = :c AND o.session = :s AND o.semester = :sem AND o.stream = 'REGULAR'
                        """).param("r", reg).param("c", c).param("s", session).param("sem", semester).update();
            }
            return reg;
        });
    }

    private Map<String, Object> state(UUID student, int semester) {
        String json = jdbc.sql("SELECT registration.gst_eps_permit_state(:st, :s, :sem)::text").param("st", student).param("s", session).param("sem", semester).query(String.class).single();
        return new tools.jackson.databind.ObjectMapper().readValue(json, Map.class);
    }

    private static List<String> codesOf(Map<String, Object> state) {
        List<String> out = new ArrayList<>();
        for (Object o : (List<?>) state.get("courses")) out.add(((Map<?, ?>) o).get("course_code") + "/" + ((Map<?, ?>) o).get("course_type"));
        return out;
    }

    private Map<String, Object> issue(UUID student, int semester, String act) {
        String json = it.db(() -> jdbc.sql("SELECT registration.issue_gst_eps_permit(:st, :s, :sem, :a)::text")
                .param("st", student).param("s", session).param("sem", semester).param("a", act).query(String.class).single());
        return new tools.jackson.databind.ObjectMapper().readValue(json, Map.class);
    }

    private ResponseEntity<Map> verify(String reference, String code) {
        return open.get().uri(b -> b.path("/api/v1/verify/gst-eps-permit").queryParam("r", reference).queryParam("c", code).build()).retrieve().toEntity(Map.class);
    }

    @Test
    void aPermitCarriesOnlyTheGstAndEpsCoursesTheStudentRegisteredForTheSemester() {
        int y = it.freeYear(3100, 3700);
        session = y + "/" + (y + 1);
        it.session(session, y);
        String yy = String.format("%02d", y % 100);
        int n = 1000 + new Random().nextInt(8999);
        it.db(() -> {
            String dept = jdbc.sql("SELECT dept_code FROM ref.programme WHERE code = 'C00061'").query(String.class).single();
            jdbc.sql("""
                    INSERT INTO catalogue.course (code, title, units, semester, level, dept_code, kind, state) VALUES
                        ('GST 497', 'Permit Use of English', 2, 1, 100, :d, 'GST', 'LIVE'), ('GST 498', 'Permit Nigerian Peoples', 2, 1, 100, :d, 'GST', 'LIVE'),
                        ('GST 499', 'Permit Logic', 2, 1, 100, :d, 'GST', 'LIVE'), ('EPS 497', 'Permit Entrepreneurship', 2, 1, 100, :d, 'GST', 'LIVE'),
                        ('ITP 497', 'Permit Departmental Course', 3, 1, 100, :d, 'Core', 'LIVE')
                    ON CONFLICT (code) DO NOTHING
                    """).param("d", dept).update();
            return jdbc.sql("""
                    INSERT INTO catalogue.offering (id, course_code, session, semester)
                    SELECT gen_random_uuid(), c, :s, sem FROM unnest(ARRAY['GST 497', 'GST 498', 'GST 499', 'EPS 497', 'ITP 497']) c, unnest(ARRAY[1, 2]) sem
                    ON CONFLICT (course_code, session, semester, stream) DO NOTHING
                    """).param("s", session).update();
        });
        assertThat(jdbc.sql("SELECT string_agg(code || ':' || coalesce(general_office, '-'), ',' ORDER BY code) FROM catalogue.course WHERE code IN ('GST 497', 'EPS 497', 'ITP 497')")
                .query(String.class).single()).isEqualTo("EPS 497:EPS,GST 497:GST,ITP 497:-");

        UUID a = it.student("ZZPERMA" + n, "C00061", "MOAUM/ADM/" + yy + "/51" + n, "MOAUM/ITP/" + yy + "/" + n, 100);
        UUID b = it.student("ZZPERMB" + n, "C00061", "MOAUM/ADM/" + yy + "/52" + n, null, 100);
        UUID c = it.student("ZZPERMC" + n, "C00061", "MOAUM/ADM/" + yy + "/53" + n, null, 100);
        UUID d = it.student("ZZPERMD" + n, "C00061", "MOAUM/ADM/" + yy + "/54" + n, null, 100);
        UUID e = it.student("ZZPERME" + n, "C00061", "MOAUM/ADM/" + yy + "/55" + n, null, 100);
        UUID f = it.student("ZZPERMF" + n, "C00061", "MOAUM/ADM/" + yy + "/56" + n, null, 100);
        UUID g = it.student("ZZPERMG" + n, "C00061", "MOAUM/ADM/" + yy + "/57" + n, null, 100);
        UUID h = it.student("ZZPERMH" + n, "C00061", "MOAUM/ADM/" + yy + "/58" + n, "MOAUM/ITQ/" + yy + "/" + n, 100);
        approved(a, 1, "GST 497");                    // A: GST only
        approved(b, 1, "EPS 497");                    // B: EPS only
        approved(c, 1, "GST 497", "EPS 497");         // C: both
        approved(d, 1, "ITP 497");                    // D: neither
        approved(e, 1, "GST 497", "ITP 497");         // E: GST and a departmental course
        approved(f, 1, "EPS 497", "ITP 497");         // F: EPS and a departmental course
        approved(g, 1, "GST 498");                    // G: GST in the first semester only
        approved(g, 2, "ITP 497");
        approved(h, 1, "GST 497", "GST 498", "ITP 497");   // H then I: reset, and registered again with other courses

        // TESTS A-F, K, L: exactly the GST and EPS courses registered, the departmental ones never, GST 499 (offered, registered by
        // nobody) never; the registrations were brought over approved with no approver, as the old portal's were
        assertThat(codesOf(state(a, 1))).containsExactly("GST 497/GST");
        assertThat(codesOf(state(b, 1))).containsExactly("EPS 497/EPS");
        assertThat(codesOf(state(c, 1))).containsExactly("GST 497/GST", "EPS 497/EPS");
        assertThat(codesOf(state(e, 1))).containsExactly("GST 497/GST");
        assertThat(codesOf(state(f, 1))).containsExactly("EPS 497/EPS");
        Map<String, Object> none = state(d, 1);
        assertThat(none).containsEntry("available", false).containsEntry("code", "GST_EPS_PERMIT_NO_COURSES");
        assertThat((List<?>) none.get("courses")).isEmpty();
        for (UUID s : List.of(a, b, c, e, f, g, h)) assertThat(codesOf(state(s, 1))).noneMatch(x -> x.startsWith("GST 499") || x.startsWith("ITP 497"));
        assertThat(state(c, 1)).containsEntry("gstCount", 1).containsEntry("epsCount", 1).containsEntry("units", 4);
        // TEST G: a course of the first semester is not on the second semester's permit
        assertThat(state(g, 2)).containsEntry("code", "GST_EPS_PERMIT_NO_COURSES");
        // TEST D: no permit is made for a student with no GST or EPS course
        String refusal = "";
        try {
            jdbc.sql("SELECT registration.issue_gst_eps_permit(:d, :s, 1, 'VIEW')::text").param("d", d).param("s", session).query(String.class).single();
        } catch (org.springframework.dao.DataAccessException expected) {
            refusal = String.valueOf(expected.getMessage());
        }
        assertThat(refusal).contains("GST_EPS_PERMIT_NO_COURSES");
        assertThat(jdbc.sql("SELECT count(*) FROM registration.gst_eps_permit WHERE student_id = :d").param("d", d).query(Long.class).single()).isZero();

        // the school fees stated and the scheme in force (the examination released only when paid in full); the cards neither
        // offered on approval nor released; H pays in full, so H's permit may be issued
        assertThat(it.call(bursar, HttpMethod.POST, "/api/v1/finance/sessions/" + session + "/schedule", Map.of("item", "School fees", "amount", 100000, "level", 100)).getStatusCode().value()).isEqualTo(200);
        it.db(() -> {
            jdbc.sql("""
                    INSERT INTO policy.version (id, kind, scope, validity, instrument, decided_by)
                    SELECT gen_random_uuid(), 'clearance', 'UNIVERSITY',
                           daterange(current_date, (SELECT min(lower(validity)) FROM policy.version WHERE kind = 'clearance' AND scope = 'UNIVERSITY' AND lower(validity) > current_date)),
                           :i, 'bursar'
                     WHERE policy.in_force('clearance', 'UNIVERSITY', current_date) IS NULL
                    """).param("i", instrument).update();
            jdbc.sql("INSERT INTO policy.clearance_scheme SELECT id, true FROM policy.version WHERE instrument = :i ON CONFLICT DO NOTHING").param("i", instrument).update();
            jdbc.sql("""
                    INSERT INTO policy.clearance_rule SELECT v.id, p.code, CASE p.code WHEN 'HOSTEL' THEN 'NEVER_GATED' WHEN 'EXAMINATION' THEN 'PAID_IN_FULL' ELSE 'INSTALMENT_1' END
                      FROM policy.version v, ref.clearance_purpose p WHERE v.instrument = :i ON CONFLICT DO NOTHING
                    """).param("i", instrument).update();
            return jdbc.sql("""
                    INSERT INTO registration.approval_policy (session, semester, mode, allow_student_reset, card_on_approval, reason, set_by, set_office)
                    VALUES (:s, 1, 'HOD_APPROVAL_REQUIRED', false, false, 'Integration test: the cards are released with the timetable', gen_random_uuid(), 'academic')
                    """).param("s", session).update();
        });
        // V589: the school fees unpaid hold the permit as they hold the examination card (NOT_PAID), nothing else does
        assertThat(state(a, 1)).containsEntry("available", false).containsEntry("code", "GST_EPS_PERMIT_NOT_PAID");
        assertThat(codesOf(state(a, 1))).containsExactly("GST 497/GST");   // the courses are still listed
        String th = signedIn(h, "MOAUM/ITQ/" + yy + "/" + n);
        payInFull(th, session);
        assertThat(state(h, 1)).containsEntry("available", true);

        // V589 (the University's instruction): a student whose registration is submitted and waiting for the Head, who has paid
        // part of the school fees, prints the permit as the examination card — the scheme refusing the examination, the cards
        // neither offered on approval nor released; what the card issues on, the permit issues on
        UUID k = it.student("ZZPERMK" + n, "C00061", "MOAUM/ADM/" + yy + "/59" + n, "MOAUM/ITR/" + yy + "/" + n, 100);
        submitted(k, 1, "GST 497", "EPS 497");
        assertThat(state(k, 1)).containsEntry("available", false).containsEntry("code", "GST_EPS_PERMIT_NOT_PAID");
        pay(signedIn(k, "MOAUM/ITR/" + yy + "/" + n), session, 40000);
        assertThat(jdbc.sql("SELECT finance.clears_or_null(:k, :s, 'EXAMINATION')").param("k", k).param("s", session).query(Boolean.class).single()).isFalse();
        Map<String, Object> waiting = state(k, 1);
        assertThat(waiting).as(String.valueOf(waiting)).containsEntry("available", true).containsEntry("cleared", true);
        assertThat(((Map) waiting.get("registration")).get("status")).isEqualTo("SUBMITTED");
        assertThat(codesOf(waiting)).containsExactly("GST 497/GST", "EPS 497/EPS");
        assertThat(jdbc.sql("SELECT (registration.exam_card_state(:k, :s, 1)->>'available')::boolean").param("k", k).param("s", session).query(Boolean.class).single()).isTrue();
        assertThat(((Map) issue(k, 1, "PRINT").get("permit")).get("reference")).asString().matches("GST-EPS/" + y + "/\\d{6,}");
        // on the offices' roster beside the approved ones
        assertThat(jdbc.sql("SELECT reg_status FROM registration.gst_eps_permit_roster(:s, 1, 'EPS') WHERE student_id = :k").param("s", session).param("k", k).query(String.class).single()).isEqualTo("SUBMITTED");

        // issued: one permit, made once, counted each time, its courses logged
        Map<String, Object> first = issue(h, 1, "VIEW");
        Map<String, Object> second = issue(h, 1, "PRINT");
        String reference = String.valueOf(((Map) first.get("permit")).get("reference"));
        assertThat(reference).matches("GST-EPS/" + y + "/\\d{6,}");
        assertThat(((Map) second.get("permit")).get("reference")).isEqualTo(reference);
        assertThat(second.get("permit")).asInstanceOf(org.assertj.core.api.InstanceOfAssertFactories.MAP).containsEntry("viewed", 1).containsEntry("printed", 1).containsEntry("status", "PRINTED");
        assertThat(codesOf(second)).containsExactly("GST 497/GST", "GST 498/GST");
        assertThat(jdbc.sql("SELECT string_agg(action, ',' ORDER BY at, action) FROM registration.gst_eps_permit_event e JOIN registration.gst_eps_permit p ON p.id = e.permit_id WHERE p.student_id = :h")
                .param("h", h).query(String.class).single()).contains("GST_EPS_PERMIT_GENERATED").contains("GST_EPS_PERMIT_VIEWED").contains("GST_EPS_PERMIT_PRINTED");
        assertThat(jdbc.sql("SELECT count(*) FROM registration.gst_eps_permit WHERE student_id = :h").param("h", h).query(Long.class).single()).isEqualTo(1);

        // the public verification: VALID with only the GST courses; a code that does not match is NOT_FOUND
        String code = codes.sign(CheckCodes.Kind.GST_EPS_PERMIT, reference);
        Map<String, Object> valid = verify(reference, code).getBody();
        assertThat(valid).containsEntry("genuine", true).containsEntry("status", "VALID");
        assertThat(((List<Map<String, Object>>) valid.get("courses")).stream().map(x -> x.get("course_code"))).containsExactly("GST 497", "GST 498");
        assertThat(verify(reference, "000000000000").getBody()).containsEntry("genuine", false).containsEntry("status", "NOT_FOUND");
        assertThat(verify("GST-EPS/" + y + "/999999999", code).getBody()).containsEntry("status", "NOT_FOUND");

        // the offices: the GST desk lists its students with the permit; the EPS office neither reads a GST-only student nor withdraws
        // their permit; the GST office withdraws it with a reason, the student is told without the reason, the QR says REVOKED
        Map<String, Object> desk = it.call(gst, HttpMethod.GET, "/api/v1/gst/GST/permits?session=" + session + "&semester=1&q=ZZPERMH" + n, null).getBody();
        assertThat(((List<Map<String, Object>>) desk.get("rows"))).singleElement().satisfies(r -> {
            assertThat(r.get("reference")).isEqualTo(reference);
            assertThat(r.get("courses")).isEqualTo("GST 497, GST 498");
        });
        assertThat(it.call(gst, HttpMethod.GET, "/api/v1/gst/EPS/permits?session=" + session, null).getStatusCode().value()).isEqualTo(403);
        assertThat(it.call(eps, HttpMethod.GET, "/api/v1/gst/EPS/permits/students/" + h + "?session=" + session + "&semester=1", null).getStatusCode().value()).isEqualTo(404);
        UUID permit = jdbc.sql("SELECT id FROM registration.gst_eps_permit WHERE reference = :r").param("r", reference).query(UUID.class).single();
        ResponseEntity<Map> epsRevoke = it.call(eps, HttpMethod.POST, "/api/v1/gst/EPS/permits/" + permit + "/revoke", Map.of("reason", "the EPS office trying a GST permit"));
        assertThat(epsRevoke.getStatusCode().value()).isEqualTo(422);
        assertThat(epsRevoke.getBody()).containsEntry("code", "GST_EPS_PERMIT_OTHER_OFFICE");
        assertThat(it.call(gst, HttpMethod.POST, "/api/v1/gst/GST/permits/" + permit + "/revoke", Map.of("reason", "short")).getStatusCode().value()).isEqualTo(400);
        ResponseEntity<Map> revoked = it.call(gst, HttpMethod.POST, "/api/v1/gst/GST/permits/" + permit + "/revoke", Map.of("reason", "Integration test: the permit was presented by another candidate"));
        assertThat(revoked.getStatusCode().value()).as(String.valueOf(revoked.getBody())).isEqualTo(200);
        assertThat(revoked.getBody()).containsEntry("code", "GST_EPS_PERMIT_REVOKED");
        assertThat(verify(reference, code).getBody()).containsEntry("status", "REVOKED").doesNotContainKey("courses");
        assertThat(jdbc.sql("SELECT count(*) FROM platform.notice WHERE about_id = :h AND template_key = 'GST_EPS_PERMIT_REVOKED'").param("h", h).query(Long.class).single()).isPositive();
        assertThat(it.call(gst, HttpMethod.POST, "/api/v1/gst/GST/permits/" + permit + "/restore", Map.of("reason", "Integration test: the office confirmed the candidate")).getStatusCode().value()).isEqualTo(200);
        assertThat(verify(reference, code).getBody()).containsEntry("status", "VALID");

        // V589/V521: ICT Support, viewing the student's portal read-only, reads the examination card's check code (the card was
        // refused the view — "try again" — because the code counted an issue) and the permit the student issued, and counts nothing
        UUID agentId = it.person("ZZ-PERMIT-AGENT" + n, "ZZPERMITAGENT" + n);
        it.db(() -> jdbc.sql("""
                INSERT INTO iam.office_assignment (id, person_id, office_code, scope_kind, scope_id, instrument, granted_by, valid_from)
                VALUES (gen_random_uuid(), :p, 'ictagent', 'platform', NULL, 'integration test', :p, current_date)
                """).param("p", agentId).update());
        ResponseEntity<Map> opened = it.call(TestTokens.token(agentId, List.of("ictagent")), HttpMethod.POST, "/api/v1/helpdesk/support/students/" + h + "/portal-view",
                Map.of("reason", "The student says the examination card will not print"));
        assertThat(opened.getStatusCode().value()).as(String.valueOf(opened.getBody())).isEqualTo(200);
        String view = String.valueOf(opened.getBody().get("token"));
        long cardsBefore = jdbc.sql("SELECT coalesce(sum(times), 0) FROM registration.exam_card_issue WHERE student_id = :h").param("h", h).query(Long.class).single();
        ResponseEntity<Map> viewedCode = it.get(view, "/api/v1/me/check-code?kind=EXAM&session=" + session + "&semester=1");
        assertThat(viewedCode.getStatusCode().value()).as(String.valueOf(viewedCode.getBody())).isEqualTo(200);
        assertThat(viewedCode.getBody()).containsEntry("number", "MOAUM/ITQ/" + yy + "/" + n);
        assertThat(jdbc.sql("SELECT coalesce(sum(times), 0) FROM registration.exam_card_issue WHERE student_id = :h").param("h", h).query(Long.class).single()).isEqualTo(cardsBefore);
        assertThat(it.call(view, HttpMethod.POST, "/api/v1/me/gst-eps-permit/issue", Map.of("semester", 1, "act", "PRINT")).getBody()).containsEntry("code", "SUPPORT_VIEW_READ_ONLY");
        ResponseEntity<Map> document = it.get(view, "/api/v1/me/gst-eps-permit/document?semester=1");
        assertThat(document.getStatusCode().value()).as(String.valueOf(document.getBody())).isEqualTo(200);
        assertThat(document.getBody()).containsEntry("available", true).containsEntry("checkCode", code);   // the permit as the student issued it
        assertThat(((Map) document.getBody().get("permit")).get("reference")).isEqualTo(reference);
        assertThat(jdbc.sql("SELECT viewed + downloaded + printed FROM registration.gst_eps_permit WHERE id = :p").param("p", permit).query(Integer.class).single()).isEqualTo(2);
        // the student's own card is counted
        assertThat(it.get(th, "/api/v1/me/check-code?kind=EXAM&session=" + session + "&semester=1").getStatusCode().value()).isEqualTo(200);
        assertThat(jdbc.sql("SELECT coalesce(sum(times), 0) FROM registration.exam_card_issue WHERE student_id = :h").param("h", h).query(Long.class).single()).isEqualTo(cardsBefore + 1);

        // TEST H: a reset takes the courses off — the permit is not issued, and the QR says INVALID; nothing is kept from before
        it.db(() -> jdbc.sql("SELECT registration.student_reset(:h, :s, 1, 'Integration test: wrong courses', 'ICT_SUPPORT')::text").param("h", h).param("s", session).query(String.class).single());
        Map<String, Object> afterReset = state(h, 1);
        assertThat(afterReset).containsEntry("available", false).containsEntry("code", "GST_EPS_PERMIT_NOT_SUBMITTED");
        assertThat((List<?>) afterReset.get("courses")).isEmpty();
        assertThat(verify(reference, code).getBody()).containsEntry("status", "INVALID");
        // TEST I: registered again with other courses and approved: the same permit number, the new courses only
        it.db(() -> {
            UUID reg = jdbc.sql("SELECT id FROM registration.course_registration WHERE student_id = :h AND session = :s AND semester = 1").param("h", h).param("s", session).query(UUID.class).single();
            jdbc.sql("""
                    INSERT INTO registration.entry (registration_id, offering_id, units, entry_type, status)
                    SELECT :r, o.id, 2, 'CURRENT', 'APPROVED' FROM catalogue.offering o WHERE o.course_code IN ('GST 497', 'EPS 497') AND o.session = :s AND o.semester = 1 AND o.stream = 'REGULAR'
                    """).param("r", reg).param("s", session).update();
            return jdbc.sql("UPDATE registration.course_registration SET status = 'APPROVED', submitted_at = now(), approved_at = now() WHERE id = :r").param("r", reg).update();
        });
        Map<String, Object> again = issue(h, 1, "DOWNLOAD");
        assertThat(((Map) again.get("permit")).get("reference")).isEqualTo(reference);
        assertThat(codesOf(again)).containsExactly("GST 497/GST", "EPS 497/EPS");
        assertThat(((List<Map<String, Object>>) verify(reference, code).getBody().get("courses")).stream().map(x -> x.get("course_code"))).containsExactly("GST 497", "EPS 497");

        // TEST 13: the GST fee the gate asks for holds the permit: the Bursar states it and the student has not paid
        assertThat(it.call(bursar, HttpMethod.PUT, "/api/v1/gst/setting", Map.of("requiredForGstEps", true, "requiredForAll", false, "coversEps", true)).getStatusCode().value()).isEqualTo(200);
        assertThat(it.call(bursar, HttpMethod.PUT, "/api/v1/gst/fee", Map.of("session", session, "amount", 4000)).getStatusCode().value()).isEqualTo(200);
        assertThat(state(h, 1)).containsEntry("available", false).containsEntry("code", "GST_EPS_PERMIT_GST_PAYMENT");

        // TEST J: the student's own door names no student: it answers for the signed-in student only, in the University's current
        // session (no registration there), and a made-up act is refused
        Map<String, Object> mine = it.get(th, "/api/v1/me/gst-eps-permit").getBody();
        assertThat(((Map) mine.get("student")).get("matricNo")).isEqualTo("MOAUM/ITQ/" + yy + "/" + n);
        assertThat(mine).containsEntry("available", false);
        assertThat(it.call(th, HttpMethod.POST, "/api/v1/me/gst-eps-permit/issue", Map.of("semester", 1, "act", "STEAL")).getStatusCode().value()).isEqualTo(400);
        ResponseEntity<Map> notMine = it.call(th, HttpMethod.POST, "/api/v1/me/gst-eps-permit/issue", Map.of("semester", 1, "act", "VIEW"));
        assertThat(notMine.getStatusCode().value()).isEqualTo(422);
        assertThat(String.valueOf(notMine.getBody().get("code"))).startsWith("GST_EPS_PERMIT_");
        assertThat(it.call(th, HttpMethod.GET, "/api/v1/gst/GST/permits?session=" + session, null).getStatusCode().value()).isEqualTo(403);
    }
}
