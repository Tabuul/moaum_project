package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.nio.charset.StandardCharsets;
import java.util.Base64;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.ThreadLocalRandom;

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
 * Fresh and final clearance as workflows on the one clearance engine (V415), end to end through the API: a student
 * not eligible is started only past the check by the Registrar with a reason; each office decides only its own stage,
 * only for students in its faculty or department, only in its turn and only against the record (the Bursary is refused
 * while the session's fees are not stated); a hold names what to do; the student sees their own clearance — never an
 * office's internal note, never another student's — uploads what is asked, and downloads the certificate once every
 * office has cleared; the certificate is checked by its QR code; the hostel stage is not applicable without a hostel;
 * a support agent reads only within a posting; final clearance never changes the student's status. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class ClearanceWorkflowIT {

    static final String S = "2137/2138";
    static final String C = "/api/v1/clearance";

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    ItSupport it;
    String registrar;
    String bursar;
    String hodOwn;
    String hodOther;
    String dean;
    String library;
    String services;
    UUID fresh;
    UUID hostel;
    UUID other;
    UUID finalist;

    static Map<String, Object> m(Object o) { return (Map<String, Object>) o; }
    static List<Map<String, Object>> l(Object o) { return (List<Map<String, Object>>) o; }
    static int status(ResponseEntity<?> r) { return r.getStatusCode().value(); }

    private String officer(String staff, String office, String scopeKind, String scopeId) {
        UUID p = it.person(staff, "ZZCLR" + office.toUpperCase());
        if (scopeKind != null) {
            it.db(() -> jdbc.sql("""
                    INSERT INTO iam.office_assignment (id, person_id, office_code, scope_kind, scope_id, instrument, granted_by, valid_from)
                    SELECT gen_random_uuid(), :p, :o, :k, :s, 'integration test', :p, current_date
                     WHERE NOT EXISTS (SELECT 1 FROM iam.office_assignment a WHERE a.person_id = :p AND a.office_code = :o AND a.scope_id = :s
                                         AND (a.valid_to IS NULL OR a.valid_to >= current_date))
                    """).param("p", p).param("o", office).param("k", scopeKind).param("s", scopeId).update());
        }
        return TestTokens.token(p, List.of(office));
    }

    private UUID student(String programme, String status, int level, String other, boolean contact) {
        UUID id = UUID.randomUUID();
        String adm = String.format("MOAUM/ADM/37/%06d", ThreadLocalRandom.current().nextInt(1, 999999));
        String matric = "ACTIVE".equals(status) ? "MOAUM/ZCL/37/" + ThreadLocalRandom.current().nextInt(100000, 999999) : null;
        it.db(() -> {
            jdbc.sql("""
                    INSERT INTO people.student (id, admission_no, matric_no, surname, other_names, sex, programme_code, entry_mode, entry_session,
                                                entry_level, current_level, status, study_mode, matriculated_at)
                    VALUES (:id, :adm, :mat, 'ZZCLEARANCE', :o, 'F', :p, 'UTME', :s, 100, :lvl, :st, 'FULL_TIME', CASE WHEN :mat::text IS NULL THEN NULL ELSE now() END)
                    """).param("id", id).param("adm", adm).param("mat", matric).param("o", other).param("p", programme).param("s", S)
                    .param("lvl", level).param("st", status).update();
            if (contact) {
                jdbc.sql("INSERT INTO people.student_contact (student_id, phone, email) VALUES (:id, '08000000000', 'zzclr@example.test')").param("id", id).update();
            }
            return null;
        });
        return id;
    }

    private UUID start(String workflow, UUID student, String basis, String reason) {
        ResponseEntity<Map> r = it.call(registrar, HttpMethod.POST, C + "/start", reason == null
                ? Map.of("workflow", workflow, "session", S, "student", student.toString(), "basis", basis)
                : Map.of("workflow", workflow, "session", S, "student", student.toString(), "basis", basis, "reason", reason));
        assertThat(status(r)).as(String.valueOf(r.getBody())).isEqualTo(200);
        assertThat(String.valueOf(r.getBody().get("reference"))).matches("^[A-Z]{2,6}/[0-9]{4}/[0-9]{6,}$");
        return UUID.fromString(String.valueOf(r.getBody().get("process")));
    }

    private ResponseEntity<Map> decide(String tok, UUID process, String unit, Map<String, Object> body) {
        return it.call(tok, HttpMethod.POST, C + "/processes/" + process + "/stages/" + unit, body);
    }

    private Map<String, Object> stage(String tok, UUID process, String unit) {
        return l(it.get(tok, C + "/processes/" + process).getBody().get("stages")).stream().filter(s -> unit.equals(s.get("unit"))).findFirst().orElseThrow();
    }

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
        it.session(S, 2137);
        registrar = officer("ZZ-CLR-REG", "registrar", null, null);
        bursar = officer("ZZ-CLR-BUR", "bursar", null, null);
        hodOwn = officer("ZZ-CLR-HOD1", "hod", "department", "MTC");
        hodOther = officer("ZZ-CLR-HOD2", "hod", "department", "ASS");
        dean = officer("ZZ-CLR-DEAN", "dean", "faculty", "SC");
        library = officer("ZZ-CLR-LIB", "library", null, null);
        services = officer("ZZ-CLR-SVC", "services", null, null);
        fresh = student("C00023", "ADMITTED", 100, "Fresh", true);
        hostel = student("C00023", "ADMITTED", 100, "Hostel", false);
        other = student("C00001", "ADMITTED", 100, "Elsewhere", false);
        finalist = student("C00023", "ACTIVE", 400, "Finalist", false);
        it.db(() -> jdbc.sql("INSERT INTO hostel.application (id, student_id, session, applied_at, state) VALUES (gen_random_uuid(), :s, :sess, now(), 'APPLIED')")
                .param("s", hostel).param("sess", S).update());
    }

    @Test
    void aFreshStudentIsClearedOfficeByOfficeAgainstTheRecordAndHoldsACertificateTheQrChecks() {
        // not eligible (no admission on the portal): refused, then started past the check with a reason
        ResponseEntity<Map> refused = it.call(registrar, HttpMethod.POST, C + "/start", Map.of("workflow", "FRESH", "session", S, "student", fresh.toString()));
        assertThat(refused.getBody().get("code")).isEqualTo("CLR_NOT_ELIGIBLE");
        assertThat(status(it.call(bursar, HttpMethod.POST, C + "/start", Map.of("workflow", "FRESH", "session", S, "student", fresh.toString())))).isEqualTo(403);
        UUID p = start("FRESH", fresh, "OVERRIDE", "Admitted before the portal kept admissions");

        // the student's own view: the hostel stage is not applicable, the Bursary is open, the rest wait
        String me = TestTokens.token(fresh, List.of("student"));
        Map<String, Object> mine = l(it.get(me, "/api/v1/me/clearance").getBody().get("processes")).get(0);
        assertThat(l(mine.get("stages"))).extracting(s -> s.get("unit") + "=" + s.get("state"))
                .containsExactly("BURSARY=PENDING", "DEPARTMENT=WAITING", "FACULTY=WAITING", "LIBRARY=WAITING", "HEALTH=WAITING", "HOSTEL=NOT_APPLICABLE");

        // the Bursary's desk opens on its own stage; it clears only against the record, and never by override
        Map<String, Object> desk = it.get(bursar, C + "/desk?workflow=FRESH&session=" + S + "&q=ZZCLEARANCE&size=200").getBody();
        assertThat(desk.get("unit")).isEqualTo("BURSARY");
        assertThat(l(desk.get("rows"))).extracting(r -> r.get("process_id")).contains(p.toString());
        assertThat(decide(bursar, p, "BURSARY", Map.of("state", "CLEARED")).getBody().get("code")).isEqualTo("CLR_OUTSTANDING");
        assertThat(status(decide(bursar, p, "BURSARY", Map.of("state", "CLEARED", "item", "trust me", "override", true)))).isEqualTo(403);
        assertThat(decide(bursar, p, "BURSARY", Map.of("state", "NOT_CLEARED")).getBody().get("code")).isEqualTo("CLR_REASON");
        assertThat(status(decide(registrar, p, "BURSARY", Map.of("state", "CLEARED", "item", "Paid on the old ledger, seen by the Bursar", "override", true)))).isEqualTo(200);

        // another department's Head sees nothing; the Library may not give the Department's word; the Department asks for action
        assertThat(status(it.get(hodOther, C + "/processes/" + p))).isEqualTo(404);
        assertThat(status(decide(hodOther, p, "DEPARTMENT", Map.of("state", "CLEARED")))).isEqualTo(404);
        assertThat(status(decide(library, p, "DEPARTMENT", Map.of("state", "CLEARED")))).isEqualTo(403);
        assertThat(decide(library, p, "LIBRARY", Map.of("state", "CLEARED")).getBody().get("code")).isEqualTo("CLR_STAGE_WAITING");
        ResponseEntity<Map> asked = decide(hodOwn, p, "DEPARTMENT", Map.of("state", "REQUIRES_ACTION", "item", "Upload your O'Level result",
                "note", "Bring the original on Monday", "internalNote", "checked against the list"));
        assertThat(asked.getBody().get("overall")).isEqualTo("PENDING_ACTION");

        // the student sees what to do and the official remark, never the internal note; uploads the document
        Map<String, Object> dept = l(l(it.get(me, "/api/v1/me/clearance").getBody().get("processes")).get(0).get("stages")).stream()
                .filter(s -> "DEPARTMENT".equals(s.get("unit"))).findFirst().orElseThrow();
        assertThat(dept).containsEntry("state", "REQUIRES_ACTION").containsEntry("item", "Upload your O'Level result").containsEntry("note", "Bring the original on Monday");
        assertThat(String.valueOf(it.get(me, "/api/v1/me/clearance").getBody())).doesNotContain("checked against the list");
        String pdf = Base64.getEncoder().encodeToString("%PDF-1.4\n% clearance test\n".getBytes(StandardCharsets.UTF_8));
        ResponseEntity<Map> up = it.call(me, HttpMethod.POST, "/api/v1/me/clearance/" + p + "/documents",
                Map.of("unit", "DEPARTMENT", "label", "O'Level result", "fileName", "olevel.pdf", "contentBase64", pdf));
        assertThat(status(up)).as(String.valueOf(up.getBody())).isEqualTo(200);
        UUID doc = UUID.fromString(String.valueOf(up.getBody().get("document")));
        assertThat(status(it.call(me, HttpMethod.POST, "/api/v1/me/clearance/" + p + "/documents",
                Map.of("unit", "DEPARTMENT", "label", "Not a PDF", "fileName", "x.pdf", "contentBase64", Base64.getEncoder().encodeToString("hello".getBytes()))))).isEqualTo(422);
        // another student reaches neither the clearance nor the document
        String them = TestTokens.token(hostel, List.of("student"));
        assertThat(status(it.call(them, HttpMethod.POST, "/api/v1/me/clearance/" + p + "/documents",
                Map.of("unit", "DEPARTMENT", "label", "x", "fileName", "x.pdf", "contentBase64", pdf)))).isEqualTo(404);
        assertThat(status(it.getBytesWith(them, "/api/v1/me/clearance/documents/" + doc + "/file", Map.of()))).isEqualTo(404);
        assertThat(status(it.getBytesWith(me, "/api/v1/me/clearance/documents/" + doc + "/file", Map.of()))).isEqualTo(200);

        // the Head reviews: a rejection needs its reason; approved, the Department clears
        assertThat(it.call(hodOwn, HttpMethod.POST, C + "/documents/" + doc + "/review", Map.of("state", "REJECTED")).getBody().get("code")).isEqualTo("CLR_REASON");
        assertThat(status(it.call(hodOwn, HttpMethod.POST, C + "/documents/" + doc + "/review", Map.of("state", "APPROVED")))).isEqualTo(200);
        assertThat(status(decide(hodOwn, p, "DEPARTMENT", Map.of("state", "CLEARED")))).isEqualTo(200);
        assertThat(status(decide(dean, p, "FACULTY", Map.of("state", "CLEARED")))).isEqualTo(200);
        assertThat(status(decide(library, p, "LIBRARY", Map.of("state", "CLEARED")))).isEqualTo(200);
        ResponseEntity<Map> last = decide(services, p, "HEALTH", Map.of("state", "CLEARED"));
        assertThat(last.getBody().get("overall")).isEqualTo("CLEARED");

        // the certificate, and its QR's check: genuine with the code, nothing without it
        Map<String, Object> cert = it.call(me, HttpMethod.POST, "/api/v1/me/clearance/" + p + "/certificate", Map.of()).getBody();
        String code = String.valueOf(cert.get("verify_code"));
        String ref = String.valueOf(cert.get("reference"));
        assertThat(code).matches("^[0-9a-f]{18}$");
        Map<String, Object> genuine = it.anon(HttpMethod.GET, "/api/v1/verify/clearance?ref=" + ref + "&c=" + code, null).getBody();
        assertThat(genuine).containsEntry("genuine", true).containsEntry("status", "CLEARED");
        assertThat(it.anon(HttpMethod.GET, "/api/v1/verify/clearance?ref=" + ref + "&c=000000000000000000", null).getBody()).containsEntry("genuine", false);

        // the student was told along the way
        Long told = jdbc.sql("SELECT count(*) FROM platform.notice WHERE about_id = :s").param("s", fresh).query(Long.class).single();
        assertThat(told).isGreaterThanOrEqualTo(6);
    }

    @Test
    void theHostelStageAppliesOnlyToAStudentWhoAppliedAndAnAgentReadsOnlyWithinAPosting() {
        UUID ph = start("FRESH", hostel, "OVERRIDE", "Admitted before the portal kept admissions");
        UUID po = start("FRESH", other, "OVERRIDE", "Admitted before the portal kept admissions");
        assertThat(stage(registrar, ph, "HOSTEL")).containsEntry("applies", true).containsEntry("state", "WAITING");
        assertThat(stage(registrar, po, "HOSTEL")).containsEntry("applies", false).containsEntry("state", "NOT_APPLICABLE");
        // the Dean of another faculty reads nothing of this one
        assertThat(status(it.get(dean, C + "/processes/" + po))).isEqualTo(404);
        // a support agent with no posting reaches nobody; the Head of the Support Desk reads the stages, no internal note
        String agent = TestTokens.token(it.person("ZZ-CLR-AGENT", "ZZCLRAGENT"), List.of("ictagent"));
        assertThat(status(it.get(agent, C + "/support/students/" + hostel))).isEqualTo(404);
        String head = TestTokens.token(it.person("ZZ-CLR-HEAD", "ZZCLRHEAD"), List.of("helpdeskhead"));
        Map<String, Object> seen = it.get(head, C + "/support/students/" + hostel).getBody();
        assertThat(l(seen.get("processes"))).hasSize(1);
        assertThat(String.valueOf(seen)).doesNotContain("internal_note");
        // nor may the agent decide anything
        ResponseEntity<Map> agentTried = decide(agent, ph, "BURSARY", Map.of("state", "CLEARED"));
        assertThat(status(agentTried)).as(String.valueOf(agentTried.getBody())).isEqualTo(403);
    }

    /** V416: what waits on an office, on its own stage and within its own department */
    private long awaiting(String tok, String workflow, String unit) {
        List<Map<String, Object>> lines = it.getList(tok, C + "/awaiting").getBody();
        return lines.stream().filter(x -> workflow.equals(x.get("workflow")) && unit.equals(x.get("unit")))
                .mapToLong(x -> ((Number) x.get("awaiting")).longValue()).sum();
    }

    @Test
    void anOfficeSeesWhatWaitsOnItsOwnStageWithinItsOwnDepartment() {
        long own = awaiting(hodOwn, "FRESH", "DEPARTMENT");
        long other = awaiting(hodOther, "FRESH", "DEPARTMENT");
        UUID p = start("FRESH", hostel, "OVERRIDE", "Admitted before the portal kept admissions");
        // waiting on the Bursary first: not yet the Department's
        assertThat(awaiting(hodOwn, "FRESH", "DEPARTMENT")).isEqualTo(own);
        assertThat(status(decide(registrar, p, "BURSARY", Map.of("state", "CLEARED", "item", "Paid on the old ledger", "override", true)))).isEqualTo(200);
        // the Bursary cleared: the student now waits on the Head over their department, and on no other Head
        assertThat(awaiting(hodOwn, "FRESH", "DEPARTMENT")).isEqualTo(own + 1);
        assertThat(awaiting(hodOther, "FRESH", "DEPARTMENT")).isEqualTo(other);
        // an office sees only its own stages
        List<Map<String, Object>> library = it.getList(this.library, C + "/awaiting").getBody();
        assertThat(library).extracting(x -> x.get("unit")).doesNotContain("DEPARTMENT", "BURSARY");
    }

    @Test
    void finalClearanceIsTheConvocationGateAndNeverGraduatesAnyone() {
        UUID pf = start("FINAL", finalist, "MANUAL", null);
        // the gate lists only the stages that apply: no hostel for a student who never had one
        List<String> gate = jdbc.sql("SELECT unit FROM clearance.position(:s, 'CONVOCATION') ORDER BY ord").param("s", finalist).query(String.class).list();
        assertThat(gate).containsExactly("BURSARY", "DEPARTMENT", "FACULTY", "LIBRARY", "HEALTH", "WORKS", "ALUMNI");
        // the alumni details: confirmed only with an e-mail and a phone on the record
        String me = TestTokens.token(finalist, List.of("student"));
        assertThat(it.get(me, "/api/v1/me/clearance").getBody().get("alumni")).isNotNull();
        ResponseEntity<Map> noContact = it.call(me, HttpMethod.PUT, "/api/v1/me/clearance/alumni", Map.of("country", "Nigeria", "confirm", true));
        assertThat(noContact.getBody().get("code")).as(String.valueOf(noContact.getBody())).isEqualTo("CLR_CONTACT");
        it.db(() -> jdbc.sql("INSERT INTO people.student_contact (student_id, phone, email) VALUES (:id, '08000000001', 'zzfinal@example.test')").param("id", finalist).update());
        Map<String, Object> confirmed = it.call(me, HttpMethod.PUT, "/api/v1/me/clearance/alumni", Map.of("country", "Nigeria", "employmentStatus", "SEEKING", "confirm", true)).getBody();
        assertThat(confirmed.get("confirmed_at")).isNotNull();
        // starting it changed nothing of the student's standing
        assertThat(jdbc.sql("SELECT status FROM people.student WHERE id = :s").param("s", finalist).query(String.class).single()).isEqualTo("ACTIVE");
        assertThat(m(it.get(registrar, C + "/processes/" + pf).getBody().get("process")).get("overall")).isEqualTo("IN_PROGRESS");
    }
}
