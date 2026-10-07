package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.HashMap;
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
 * ICT Support resolving a student's problem (V346), over the API. Course registration: the agent reads the registration
 * and every rule the engine applies; adds an eligible course and drops a current one through the engine, on the ledger
 * and the ticket; an unknown course, a course outside the programme, a course of another semester, the unit ceiling,
 * the fees and the window are refused as the engine refuses them; the override sets aside only the window and the menu,
 * only for a posting that carries it, only on the ticket with a description, and is written with the rule it set aside;
 * a closed semester's registration and its results are not touched. Password: a reset link through the portal's own
 * reset, a temporary password at the desk that is random, hashed, good for one sign-in and forced to change, never on the
 * ledger; refused without the capability. Payments: found by reference, receipt and matriculation number, diagnosed,
 * verified through the gateway service, the entitlement refreshed only for a confirmed payment and without a new payment,
 * the receipt, the student told. Security: another faculty's student is not found by changing the id; results, refunds,
 * fees and admission decisions stay closed to an agent. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class SupportResolutionIT {

    static final String S = "2073/2074";
    static final String P = "2072/2073";
    static final String MATRIC = "MOAUM/MTC/73/0001";

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;
    ItSupport it;
    UUID cpo, senior, student, outside;
    String cpoTok, seniorTok, headTok;
    final Map<String, UUID> offering = new HashMap<>();

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
        it.session(S, 2073);
        it.session(P, 2072);
        cpo = it.person("ZZ-RES-CPO", "ZZRESCPO");
        senior = it.person("ZZ-RES-SENIOR", "ZZRESSENIOR");
        UUID head = it.person("ZZ-RES-HEAD", "ZZRESHEAD");
        cpoTok = TestTokens.token(cpo, List.of("ictagent"));
        seniorTok = TestTokens.token(senior, List.of("ictagent"));
        headTok = TestTokens.token(head, List.of("helpdeskhead"));
        student = it.student("ZZRESIN", "C00023", "MOAUM/ADM/73/730001", MATRIC, 100);      // Mathematics and Computer Science · Science
        outside = it.student("ZZRESOUT", "C00001", "MOAUM/ADM/73/730002", "MOAUM/ASS/73/0002", 100);   // Education
        it.db(() -> {
            String otherDept = jdbc.sql("SELECT dept_code FROM ref.programme WHERE code = 'C00001'").query(String.class).single();
            jdbc.sql("""
                    INSERT INTO policy.semester (id, session, number, state) VALUES (gen_random_uuid(), :s, 1, 'OPEN'), (gen_random_uuid(), :s, 2, 'NOT_YET_OPEN'), (gen_random_uuid(), :p, 1, 'CLOSED')
                    ON CONFLICT (session, number) DO UPDATE SET state = EXCLUDED.state, registration_closes = NULL, late_registration_closes = NULL
                    """).param("s", S).param("p", P).update();
            for (String[] c : new String[][] {{"ZZR 101", "3", "1", "100", "MTC"}, {"ZZR 102", "3", "1", "100", "MTC"}, {"ZZR 103", "12", "1", "100", "MTC"},
                                              {"ZZR 104", "12", "1", "100", "MTC"}, {"ZZR 105", "3", "2", "100", "MTC"}, {"ZZR 301", "3", "1", "300", otherDept}}) {
                jdbc.sql("INSERT INTO catalogue.course (code, title, units, semester, level, dept_code, state) VALUES (:c, :t, :u, :sem, :l, :d, 'LIVE') ON CONFLICT (code) DO NOTHING")
                        .param("c", c[0]).param("t", "Support test course " + c[0]).param("u", Integer.parseInt(c[1])).param("sem", Integer.parseInt(c[2]))
                        .param("l", Integer.parseInt(c[3])).param("d", c[4]).update();
            }
            for (String c : List.of("ZZR 101", "ZZR 102", "ZZR 103", "ZZR 104", "ZZR 105")) {
                jdbc.sql("INSERT INTO catalogue.course_offer (course_code, programme_code, level) VALUES (:c, 'C00023', 100) ON CONFLICT DO NOTHING").param("c", c).update();
            }
            for (String[] o : new String[][] {{"ZZR 101", S, "1"}, {"ZZR 102", S, "1"}, {"ZZR 103", S, "1"}, {"ZZR 104", S, "1"}, {"ZZR 301", S, "1"}, {"ZZR 105", S, "2"}, {"ZZR 101", P, "1"}}) {
                UUID id = jdbc.sql("""
                        INSERT INTO catalogue.offering (id, course_code, session, semester) VALUES (gen_random_uuid(), :c, :s, :sem)
                        ON CONFLICT (course_code, session, semester) DO UPDATE SET semester = EXCLUDED.semester RETURNING id
                        """).param("c", o[0]).param("s", o[1]).param("sem", Integer.parseInt(o[2])).query(UUID.class).single();
                offering.put(o[0] + "@" + o[1], id);
            }
            jdbc.sql("UPDATE people.student SET entry_session = :s, current_level = 100, status = 'ACTIVE' WHERE id = :id").param("s", S).param("id", student).update();
            jdbc.sql("""
                    INSERT INTO people.student_contact (student_id, phone, email, updated_at) VALUES (:s, '08022223333', 'zzresin@example.com', now())
                    ON CONFLICT (student_id) DO UPDATE SET email = EXCLUDED.email, phone = EXCLUDED.phone
                    """).param("s", student).update();
            // a clean slate for the student's support and registration
            jdbc.sql("DELETE FROM helpdesk.support_action WHERE student_id IN (:a, :b)").param("a", student).param("b", outside).update();
            jdbc.sql("DELETE FROM registration.entry WHERE registration_id IN (SELECT id FROM registration.course_registration WHERE student_id = :s)").param("s", student).update();
            jdbc.sql("DELETE FROM registration.course_registration WHERE student_id = :s").param("s", student).update();
            jdbc.sql("DELETE FROM iam.student_account WHERE student_id = :s").param("s", student).update();
            jdbc.sql("DELETE FROM finance.payment_reference WHERE student_id = :s").param("s", student).update();
            jdbc.sql("DELETE FROM helpdesk.agent_assignment WHERE person_id IN (:a, :b)").param("a", cpo).param("b", senior).update();
            // the student's earlier tickets closed, so the open-ticket limit never trips a rerun
            jdbc.sql("UPDATE helpdesk.ticket SET status = 'CLOSED', closed_at = now(), closed_by_kind = 'SYSTEM', closure_reason = 'test reset' WHERE requester_id = :s AND status <> 'CLOSED'")
                    .param("s", student).update();
            // the earlier session's registration, examined: history
            UUID old = jdbc.sql("INSERT INTO registration.course_registration (id, student_id, session, semester, level, status, submitted_at, approved_at) VALUES (gen_random_uuid(), :s, :p, 1, 100, 'APPROVED', now(), now()) RETURNING id")
                    .param("s", student).param("p", P).query(UUID.class).single();
            jdbc.sql("INSERT INTO registration.entry (registration_id, offering_id, units, status) VALUES (:r, :o, 3, 'APPROVED')").param("r", old).param("o", offering.get("ZZR 101@" + P)).update();
            // a CPO who manages registration; a senior CPO who may also override, reset passwords and work payments
            jdbc.sql("INSERT INTO helpdesk.agent_assignment (person_id, queue_code, scope_kind, scope_ref, capabilities) VALUES (:p, 'COURSE_REGISTRATION_SUPPORT', 'FACULTY', 'SC', ARRAY['VIEW_STUDENT','MANAGE_REGISTRATION'])")
                    .param("p", cpo).update();
            for (String q : List.of("COURSE_REGISTRATION_SUPPORT", "BURSARY_SUPPORT", "ICT_SUPPORT")) {
                jdbc.sql("""
                        INSERT INTO helpdesk.agent_assignment (person_id, queue_code, scope_kind, scope_ref, capabilities)
                        VALUES (:p, :q, 'FACULTY', 'SC', ARRAY['VIEW_STUDENT','MANAGE_REGISTRATION','OVERRIDE_REGISTRATION','RESET_PASSWORD','VIEW_PAYMENTS','INVESTIGATE_PAYMENT',
                                                            'VERIFY_PAYMENT','SYNC_ENTITLEMENT','REGENERATE_RECEIPT','CREATE_TICKET','VIEW_SUPPORT_AUDIT'])
                        """).param("p", senior).param("q", q).update();
            }
            return null;
        });
    }

    private String base() {
        return "/api/v1/helpdesk/support/students/" + student;
    }

    private Map<String, Object> reg(Map<String, Object> extra) {
        Map<String, Object> m = new HashMap<>(Map.of("session", S, "semester", 1, "reason", "The portal returned an error when the student registered"));
        m.putAll(extra);
        return m;
    }

    private UUID ticket(String category, Map<String, String> details) {
        ResponseEntity<Map> t = it.call(seniorTok, HttpMethod.POST, base() + "/tickets",
                Map.of("category", category, "subject", "Raised at the desk", "description", "The student came to the desk", "details", details));
        assertThat(t.getStatusCode().value()).as(String.valueOf(t.getBody())).isEqualTo(200);
        return UUID.fromString(String.valueOf(t.getBody().get("id")));
    }

    private long ledger(String action) {
        return jdbc.sql("SELECT count(*) FROM helpdesk.support_action WHERE student_id = :s AND action = :a").param("s", student).param("a", action).query(Long.class).single();
    }

    @Test
    void courseRegistrationIsCorrectedThroughTheEngineAndTheOverrideIsRecorded() {
        UUID tkt = ticket("REGISTRATION", Map.of("session", S, "semester", "1", "level", "100"));
        // 1 · the registration and the rules are read
        ResponseEntity<Map> view = it.get(cpoTok, base() + "/registration?session=" + S + "&semester=1");
        assertThat(view.getStatusCode().value()).as(String.valueOf(view.getBody())).isEqualTo(200);
        assertThat(view.getBody()).containsKeys("view", "current", "issues", "history", "manage", "override");
        assertThat(view.getBody().get("override")).isEqualTo(false);
        ResponseEntity<Map> checks = it.get(cpoTok, base() + "/registration/checks?session=" + S + "&semester=1&offering=" + offering.get("ZZR 101@" + S));
        assertThat(((List) checks.getBody().get("rules"))).hasSize(16);
        assertThat(checks.getBody().get("allowed")).isEqualTo(true);
        // 2 · an eligible course is added through the engine, on the ledger and the ticket
        ResponseEntity<Map> added = it.call(cpoTok, HttpMethod.POST, base() + "/registration/add", reg(Map.of("offering", offering.get("ZZR 101@" + S).toString(), "ticket", tkt.toString())));
        assertThat(added.getStatusCode().value()).as(String.valueOf(added.getBody())).isEqualTo(200);
        assertThat(added.getBody().get("overridden")).isEqualTo(false);
        assertThat(jdbc.sql("SELECT count(*) FROM registration.entry e JOIN registration.course_registration r ON r.id = e.registration_id WHERE r.student_id = :s AND r.session = :ses AND e.offering_id = :o AND e.status <> 'DROPPED'")
                .param("s", student).param("ses", S).param("o", offering.get("ZZR 101@" + S)).query(Long.class).single()).isEqualTo(1L);
        // 14, 15 · audited with the ticket, and the ticket's timeline says what was done
        assertThat(jdbc.sql("SELECT count(*) FROM helpdesk.support_action WHERE student_id = :s AND action = 'COURSE_ADDED' AND ticket_id = :t AND before_state IS NOT NULL AND after_state IS NOT NULL")
                .param("s", student).param("t", tkt).query(Long.class).single()).isEqualTo(1L);
        assertThat(jdbc.sql("SELECT detail FROM helpdesk.ticket_event WHERE ticket_id = :t AND action = 'SUPPORT_COURSE_ADDED'").param("t", tkt).query(String.class).single())
                .startsWith("Action taken: ZZR 101 added to the " + S + " first semester registration");
        // 4 · an invalid course is not added
        ResponseEntity<Map> invalid = it.call(cpoTok, HttpMethod.POST, base() + "/registration/add", reg(Map.of("offering", UUID.randomUUID().toString())));
        assertThat(invalid.getStatusCode().value()).isEqualTo(422);
        assertThat(invalid.getBody().get("code")).isEqualTo("REG_RULE");
        // 5 · a course outside the programme is not added — the engine's menu does not carry it
        ResponseEntity<Map> outsideProgramme = it.call(cpoTok, HttpMethod.POST, base() + "/registration/add", reg(Map.of("offering", offering.get("ZZR 301@" + S).toString())));
        assertThat(outsideProgramme.getStatusCode().value()).isEqualTo(422);
        assertThat(outsideProgramme.getBody().get("code")).isEqualTo("REG_BLOCKED");
        // 6 · a course of another semester is not added, override or not
        ResponseEntity<Map> wrongSemester = it.call(seniorTok, HttpMethod.POST, base() + "/registration/add",
                reg(Map.of("offering", offering.get("ZZR 105@" + S).toString(), "override", true, "description", "asked", "ticket", tkt.toString())));
        assertThat(wrongSemester.getStatusCode().value()).isEqualTo(422);
        assertThat(wrongSemester.getBody().get("code")).isEqualTo("REG_RULE");
        // 11 · an override by a posting that does not carry it is refused
        ResponseEntity<Map> unauthorised = it.call(cpoTok, HttpMethod.POST, base() + "/registration/add",
                reg(Map.of("offering", offering.get("ZZR 301@" + S).toString(), "override", true, "description", "Mapped wrongly", "ticket", tkt.toString())));
        assertThat(unauthorised.getStatusCode().value()).isEqualTo(422);
        assertThat(unauthorised.getBody().get("code")).isEqualTo("SUPPORT_CAPABILITY");
        // an override needs the ticket
        ResponseEntity<Map> noTicket = it.call(seniorTok, HttpMethod.POST, base() + "/registration/add",
                reg(Map.of("offering", offering.get("ZZR 301@" + S).toString(), "override", true, "description", "Mapped wrongly")));
        assertThat(noTicket.getBody().get("code")).isEqualTo("SUPPORT_TICKET_REQUIRED");
        // 10 · the authorised override sets the menu aside, on the ticket, written with the rule it set aside
        ResponseEntity<Map> override = it.call(seniorTok, HttpMethod.POST, base() + "/registration/add",
                reg(Map.of("offering", offering.get("ZZR 301@" + S).toString(), "override", true, "ticket", tkt.toString(),
                        "description", "The course is approved for the student but the programme-course mapping omits it", "reason", "Mapping error confirmed by the department")));
        assertThat(override.getStatusCode().value()).as(String.valueOf(override.getBody())).isEqualTo(200);
        assertThat(override.getBody().get("overridden")).isEqualTo(true);
        Map<String, Object> led = jdbc.sql("SELECT override, normal_rule, description, reason FROM helpdesk.support_action WHERE student_id = :s AND override").param("s", student).query().singleRow();
        assertThat(String.valueOf(led.get("normal_rule"))).contains("not on the engine's menu");
        assertThat(jdbc.sql("SELECT detail FROM helpdesk.ticket_event WHERE ticket_id = :t AND action = 'SUPPORT_COURSE_ADDED' AND detail LIKE 'NORMAL RULE:%'").param("t", tkt).query(String.class).single())
                .contains("NORMAL RULE: Registration blocked because").contains("SUPPORT ACTION: Override approved because Mapping error confirmed by the department");
        // 7 · the unit ceiling stands, even for the override
        it.db(() -> {
            UUID r = jdbc.sql("SELECT id FROM registration.course_registration WHERE student_id = :s AND session = :ses AND semester = 1").param("s", student).param("ses", S).query(UUID.class).single();
            return jdbc.sql("INSERT INTO registration.entry (registration_id, offering_id, units, status) VALUES (:r, :a, 12, 'REGISTERED'), (:r, :b, 12, 'REGISTERED')")
                    .param("r", r).param("a", offering.get("ZZR 103@" + S)).param("b", offering.get("ZZR 104@" + S)).update();
        });
        ResponseEntity<Map> heavy = it.call(seniorTok, HttpMethod.POST, base() + "/registration/add",
                reg(Map.of("offering", offering.get("ZZR 102@" + S).toString(), "override", true, "description", "asked", "ticket", tkt.toString())));
        assertThat(heavy.getStatusCode().value()).isEqualTo(422);
        assertThat(heavy.getBody().get("code")).isEqualTo("REG_RULE");
        assertThat(String.valueOf(heavy.getBody().get("detail"))).contains("maximum");
        // 3 · a current course is dropped, after the confirmation's rules — kept as DROPPED, never deleted
        assertThat(it.call(cpoTok, HttpMethod.POST, base() + "/registration/drop", reg(Map.of("offering", offering.get("ZZR 104@" + S).toString(), "ticket", tkt.toString())))
                .getStatusCode().value()).isEqualTo(200);
        ResponseEntity<Map> dropChecks = it.get(cpoTok, base() + "/registration/checks?verb=drop&session=" + S + "&semester=1&offering=" + offering.get("ZZR 103@" + S));
        assertThat(dropChecks.getBody().get("allowed")).isEqualTo(true);
        ResponseEntity<Map> dropped = it.call(cpoTok, HttpMethod.POST, base() + "/registration/drop", reg(Map.of("offering", offering.get("ZZR 103@" + S).toString(), "ticket", tkt.toString())));
        assertThat(dropped.getStatusCode().value()).as(String.valueOf(dropped.getBody())).isEqualTo(200);
        assertThat(jdbc.sql("SELECT e.status FROM registration.entry e JOIN registration.course_registration r ON r.id = e.registration_id WHERE r.student_id = :s AND r.session = :ses AND e.offering_id = :o")
                .param("s", student).param("ses", S).param("o", offering.get("ZZR 103@" + S)).query(String.class).single()).isEqualTo("DROPPED");
        assertThat(ledger("COURSE_DROPPED")).isEqualTo(2L);
        // a dropped course is restored through the same engine
        ResponseEntity<Map> restored = it.call(cpoTok, HttpMethod.POST, base() + "/registration/restore", reg(Map.of("offering", offering.get("ZZR 103@" + S).toString(), "ticket", tkt.toString())));
        assertThat(restored.getStatusCode().value()).as(String.valueOf(restored.getBody())).isEqualTo(200);
        assertThat(ledger("COURSE_RESTORED")).isEqualTo(1L);
        // 9 · the window: the second semester is not yet open — refused, and only the override sets it aside
        ResponseEntity<Map> shut = it.call(cpoTok, HttpMethod.POST, base() + "/registration/add", reg(Map.of("semester", 2, "offering", offering.get("ZZR 105@" + S).toString())));
        assertThat(shut.getStatusCode().value()).isEqualTo(422);
        assertThat(shut.getBody().get("code")).isEqualTo("REG_BLOCKED");
        assertThat(String.valueOf(shut.getBody().get("detail"))).contains("not yet open");
        ResponseEntity<Map> opened = it.call(seniorTok, HttpMethod.POST, base() + "/registration/add",
                reg(Map.of("semester", 2, "offering", offering.get("ZZR 105@" + S).toString(), "override", true, "ticket", tkt.toString(), "description", "Registration interrupted by a portal outage")));
        assertThat(opened.getStatusCode().value()).as(String.valueOf(opened.getBody())).isEqualTo(200);
        // 8 · the fees are never set aside: a submitted registration, a fee stated and unpaid
        it.db(() -> {
            jdbc.sql("UPDATE registration.course_registration SET status = 'SUBMITTED', submitted_at = now() WHERE student_id = :s AND session = :ses AND semester = 2").param("s", student).param("ses", S).update();
            return jdbc.sql("INSERT INTO finance.fee_schedule (session, item, amount, level, programme_code) VALUES (:s, 'School fees', 120000, 100, 'C00023')").param("s", S).update();
        });
        ResponseEntity<Map> unpaid = it.call(seniorTok, HttpMethod.POST, base() + "/registration/drop",
                reg(Map.of("semester", 2, "offering", offering.get("ZZR 105@" + S).toString(), "override", true, "ticket", tkt.toString(), "description", "asked")));
        assertThat(unpaid.getStatusCode().value()).as("a drop does not need the fees").isEqualTo(200);
        ResponseEntity<Map> unpaidAdd = it.call(seniorTok, HttpMethod.POST, base() + "/registration/add",
                reg(Map.of("semester", 2, "offering", offering.get("ZZR 105@" + S).toString(), "override", true, "ticket", tkt.toString(), "description", "asked")));
        assertThat(unpaidAdd.getStatusCode().value()).isEqualTo(422);
        assertThat(unpaidAdd.getBody().get("code")).isEqualTo("REG_RULE");
        // 12, 13 · the earlier session's registration and its result are history: not dropped, override or not
        ResponseEntity<Map> history = it.call(seniorTok, HttpMethod.POST, base() + "/registration/drop",
                Map.of("session", P, "semester", 1, "offering", offering.get("ZZR 101@" + P).toString(), "override", true, "ticket", tkt.toString(), "description", "asked", "reason", "asked"));
        assertThat(history.getStatusCode().value()).isEqualTo(422);
        assertThat(history.getBody().get("code")).isEqualTo("REG_RULE");
        assertThat(jdbc.sql("SELECT e.status FROM registration.entry e JOIN registration.course_registration r ON r.id = e.registration_id WHERE r.student_id = :s AND r.session = :p")
                .param("s", student).param("p", P).query(String.class).single()).isEqualTo("APPROVED");
        // the student is told, without anything sensitive
        assertThat(jdbc.sql("SELECT count(*) FROM platform.notice WHERE about_id = :s AND subject LIKE 'Your course ZZR %'").param("s", student).query(Long.class).single()).isGreaterThanOrEqualTo(2L);
        // the desk's audit lists the override
        ResponseEntity<Map> audit = it.get(seniorTok, "/api/v1/helpdesk/support/actions?overrides=true");
        assertThat(audit.getStatusCode().value()).isEqualTo(200);
        assertThat(((Number) audit.getBody().get("total")).longValue()).isGreaterThanOrEqualTo(2L);
        assertThat(it.get(cpoTok, "/api/v1/helpdesk/support/actions").getBody().get("code")).isEqualTo("SUPPORT_CAPABILITY");
    }

    @Test
    void thePasswordIsResetThroughThePortalsOwnResetAndNeverSeen() {
        // 21 · without the capability, refused
        ResponseEntity<Map> refused = it.call(cpoTok, HttpMethod.POST, base() + "/password", Map.of("method", "LINK", "reason", "Locked out"));
        assertThat(refused.getStatusCode().value()).isEqualTo(422);
        assertThat(refused.getBody().get("code")).isEqualTo("SUPPORT_CAPABILITY");
        // 16 · the reset link, through iam.password_reset to the address on the record
        long before = jdbc.sql("SELECT count(*) FROM iam.password_reset WHERE subject_kind = 'STUDENT' AND subject_id = :s").param("s", student).query(Long.class).single();
        ResponseEntity<Map> link = it.call(seniorTok, HttpMethod.POST, base() + "/password", Map.of("method", "LINK", "reason", "The student forgot the password"));
        assertThat(link.getStatusCode().value()).as(String.valueOf(link.getBody())).isEqualTo(200);
        assertThat(String.valueOf(link.getBody().get("sentTo"))).contains("***");
        assertThat(jdbc.sql("SELECT count(*) FROM iam.password_reset WHERE subject_kind = 'STUDENT' AND subject_id = :s AND used_at IS NULL AND expires_at <= now() + interval '1 hour'")
                .param("s", student).query(Long.class).single()).isEqualTo(before + 1);
        // 17 · the current password is never shown: nothing the desk reads carries a hash or a password
        String profile = String.valueOf(it.get(seniorTok, base()).getBody());
        assertThat(profile).doesNotContain("$2a$").doesNotContain("password_hash");
        // the temporary password needs the ticket
        ResponseEntity<Map> noTicket = it.call(seniorTok, HttpMethod.POST, base() + "/password", Map.of("method", "TEMPORARY", "reason", "At the desk"));
        assertThat(noTicket.getBody().get("code")).isEqualTo("SUPPORT_TICKET_REQUIRED");
        UUID tkt = ticket("LOGIN", Map.of("account_type", "Student portal", "username", MATRIC, "error", "Wrong password"));
        ResponseEntity<Map> temp = it.call(seniorTok, HttpMethod.POST, base() + "/password", Map.of("method", "TEMPORARY", "reason", "Identity checked at the desk", "ticket", tkt.toString()));
        assertThat(temp.getStatusCode().value()).as(String.valueOf(temp.getBody())).isEqualTo(200);
        String pw = String.valueOf(temp.getBody().get("temporaryPassword"));
        // 18, 19 · random, never stored readable, never the matriculation number, forced to change, time-limited
        assertThat(pw).hasSize(12).isNotEqualToIgnoringCase(MATRIC);
        Map<String, Object> acc = jdbc.sql("SELECT password_hash, must_change, temp_expires_at IS NOT NULL AS temp, temp_expires_at <= now() + interval '24 hours' AS limited FROM iam.student_account WHERE student_id = :s")
                .param("s", student).query().singleRow();
        assertThat(String.valueOf(acc.get("password_hash"))).startsWith("$2").doesNotContain(pw);
        assertThat(acc.get("must_change")).isEqualTo(true);
        assertThat(acc.get("temp")).isEqualTo(true);
        assertThat(acc.get("limited")).isEqualTo(true);
        // the matriculation number opens nothing while the temporary password stands
        assertThat(it.anon(HttpMethod.POST, "/api/v1/student-auth/sign-in", Map.of("matricNo", MATRIC, "password", MATRIC)).getStatusCode().value()).isNotEqualTo(200);
        // it opens one session, which must change it; a second sign-in with it is refused
        ResponseEntity<Map> first = it.anon(HttpMethod.POST, "/api/v1/student-auth/sign-in", Map.of("matricNo", MATRIC, "password", pw));
        assertThat(first.getStatusCode().value()).as(String.valueOf(first.getBody())).isEqualTo(200);
        assertThat(first.getBody().get("mustChange")).isEqualTo(true);
        ResponseEntity<Map> second = it.anon(HttpMethod.POST, "/api/v1/student-auth/sign-in", Map.of("matricNo", MATRIC, "password", pw));
        assertThat(second.getStatusCode().value()).isEqualTo(422);
        assertThat(second.getBody().get("code")).isEqualTo("AUTH_TEMP_PASSWORD_SPENT");
        // 20 · the resets are audited — how, never what
        List<Map<String, Object>> resets = jdbc.sql("SELECT method, old_value, new_value, auth_event_id, ticket_id FROM helpdesk.support_action WHERE student_id = :s AND action = 'PASSWORD_RESET' ORDER BY at")
                .param("s", student).query().listOfRows();
        assertThat(resets).hasSize(2);
        assertThat(resets).extracting(r -> r.get("method")).containsExactly("RESET_LINK", "TEMPORARY_PASSWORD");
        assertThat(resets).allSatisfy(r -> { assertThat(r.get("old_value")).isNull(); assertThat(r.get("new_value")).isNull(); assertThat(r.get("auth_event_id")).isNotNull(); });
        assertThat(jdbc.sql("SELECT count(*) FROM helpdesk.support_action WHERE student_id = :s AND (coalesce(new_value, '') || coalesce(summary, '') || reason) LIKE '%' || :pw || '%'")
                .param("s", student).param("pw", pw).query(Long.class).single()).isEqualTo(0L);
        assertThat(jdbc.sql("SELECT count(*) FROM platform.notice WHERE about_id = :s AND body LIKE '%' || :pw || '%'").param("s", student).param("pw", pw).query(Long.class).single()).isEqualTo(0L);
    }

    @Test
    void aPaymentIsDiagnosedAndResolvedThroughTheExistingServicesAndNeverMarkedPaid() {
        String ref = it.db(() -> jdbc.sql("SELECT finance.new_purpose_reference(:s, :ses, 50000, 'School fees ' || :ses)").param("s", student).param("ses", S).query(String.class).single());
        // 22 · found by the reference, and by the matriculation number
        ResponseEntity<Map> byRef = it.get(seniorTok, "/api/v1/helpdesk/support/payments?q=" + ref);
        assertThat(byRef.getStatusCode().value()).as(String.valueOf(byRef.getBody())).isEqualTo(200);
        assertThat((List<Map>) byRef.getBody().get("rows")).extracting(r -> r.get("reference")).containsExactly(ref);
        assertThat(((List) it.get(seniorTok, "/api/v1/helpdesk/support/payments?q=" + MATRIC).getBody().get("rows"))).isNotEmpty();
        assertThat(it.get(cpoTok, "/api/v1/helpdesk/support/payments?q=" + ref).getBody().get("code")).isEqualTo("SUPPORT_CAPABILITY");
        // 23 · the diagnosis: gateway, finance, entitlement, verification, and what to do
        ResponseEntity<Map> d = it.get(seniorTok, "/api/v1/helpdesk/support/payments/" + ref);
        assertThat(d.getStatusCode().value()).as(String.valueOf(d.getBody())).isEqualTo(200);
        Map<String, Object> status = (Map<String, Object>) d.getBody().get("status");
        assertThat(status).containsEntry("finance", "NOT_CONFIRMED").containsEntry("gateway", "NOT_STARTED").containsEntry("entitlement", "NOT_APPLICABLE");
        assertThat((List<Map>) d.getBody().get("advice")).extracting(a -> a.get("code")).contains("NO_GATEWAY_ATTEMPT");
        // 26 · an unconfirmed payment cannot be made to count from the desk — no refresh, and no "mark as paid" exists
        ResponseEntity<Map> notPaid = it.call(seniorTok, HttpMethod.POST, "/api/v1/helpdesk/support/payments/" + ref + "/refresh", Map.of("reason", "The student says it is paid"));
        assertThat(notPaid.getStatusCode().value()).isEqualTo(422);
        assertThat(notPaid.getBody().get("code")).isEqualTo("PAY_NOT_CONFIRMED");
        assertThat(it.call(seniorTok, HttpMethod.POST, "/api/v1/helpdesk/support/payments/" + ref + "/confirm", Map.of()).getStatusCode().value()).isIn(404, 405);
        // the gateway is asked through the payment service; with none answering, nothing changes
        ResponseEntity<Map> verified = it.call(seniorTok, HttpMethod.POST, "/api/v1/helpdesk/support/payments/" + ref + "/verify", Map.of("reason", "Hanging payment"));
        assertThat(verified.getStatusCode().value()).as(String.valueOf(verified.getBody())).isEqualTo(200);
        assertThat(verified.getBody().get("confirmed")).isEqualTo(false);
        assertThat(jdbc.sql("SELECT confirmed_at IS NULL FROM finance.payment_reference WHERE reference = :r").param("r", ref).query(Boolean.class).single()).isTrue();
        // the Bursary's confirmation — the authoritative record — then 24, 25 · the entitlement refreshed, 27 · without a new payment
        it.db(() -> jdbc.sql("SELECT finance.confirm_payment(:r, 'BANK_BRANCH', 'teller for the support test')").param("r", ref).query(String.class).single());
        long refs = jdbc.sql("SELECT count(*) FROM finance.payment_reference WHERE student_id = :s").param("s", student).query(Long.class).single();
        UUID tkt = ticket("PAYMENT", Map.of("payment_reference", ref, "payment_date", "2026-10-07", "payment_type", "School fees", "amount", "50000"));
        ResponseEntity<Map> refreshed = it.call(seniorTok, HttpMethod.POST, "/api/v1/helpdesk/support/payments/" + ref + "/refresh", Map.of("reason", "Paid but the portal showed unpaid", "ticket", tkt.toString()));
        assertThat(refreshed.getStatusCode().value()).as(String.valueOf(refreshed.getBody())).isEqualTo(200);
        assertThat(String.valueOf(refreshed.getBody().get("applied"))).contains("academic position");
        assertThat(jdbc.sql("SELECT count(*) FROM finance.payment_reference WHERE student_id = :s").param("s", student).query(Long.class).single()).isEqualTo(refs);
        assertThat(((Map) ((Map) refreshed.getBody().get("diagnosis")).get("status")).get("finance")).isEqualTo("VERIFIED");
        // the receipt: read, and the student told it is ready
        ResponseEntity<Map> receipt = it.get(seniorTok, "/api/v1/helpdesk/support/payments/" + ref + "/receipt");
        assertThat(receipt.getStatusCode().value()).as(String.valueOf(receipt.getBody())).isEqualTo(200);
        assertThat(receipt.getBody().get("receipt_no")).isNotNull();
        assertThat(it.call(seniorTok, HttpMethod.POST, "/api/v1/helpdesk/support/payments/" + ref + "/receipt", Map.of("reason", "Could not print it")).getStatusCode().value()).isEqualTo(200);
        // 29 · every payment act audited; 30 · the student told, without the amount
        assertThat(ledger("PAYMENT_VERIFIED")).isEqualTo(1L);
        assertThat(ledger("ENTITLEMENT_REFRESHED")).isEqualTo(1L);
        assertThat(ledger("RECEIPT_REGENERATED")).isEqualTo(1L);
        assertThat(jdbc.sql("SELECT count(*) FROM helpdesk.ticket_event WHERE ticket_id = :t AND action = 'SUPPORT_ENTITLEMENT_REFRESHED'").param("t", tkt).query(Long.class).single()).isEqualTo(1L);
        assertThat(jdbc.sql("SELECT body FROM platform.notice WHERE about_id = :s AND subject = 'Your payment issue has been resolved' ORDER BY created_at DESC LIMIT 1").param("s", student).query(String.class).single())
                .contains("synchronized with your student portal").doesNotContain("50000").doesNotContain("50,000");
        // a financial decision goes to the Bursary on the ticket
        ResponseEntity<Map> escalated = it.call(seniorTok, HttpMethod.POST, base() + "/escalate", Map.of("ticket", tkt.toString(), "office", "bursar", "reason", "Possible duplicate payment", "paymentReference", ref));
        assertThat(escalated.getStatusCode().value()).as(String.valueOf(escalated.getBody())).isEqualTo(200);
        assertThat(jdbc.sql("SELECT escalated_office FROM helpdesk.ticket WHERE id = :t").param("t", tkt).query(String.class).single()).isEqualTo("bursar");
    }

    @Test
    void theDeskReachesOnlyItsScopeAndNeverResultsRefundsFeesOrAdmissions() {
        // 31, 32 · another faculty's student is not found by changing the id — read or write
        assertThat(it.get(seniorTok, "/api/v1/helpdesk/support/students/" + outside).getStatusCode().value()).isEqualTo(404);
        assertThat(it.get(seniorTok, "/api/v1/helpdesk/support/students/" + outside + "/registration").getStatusCode().value()).isEqualTo(404);
        assertThat(it.call(seniorTok, HttpMethod.POST, "/api/v1/helpdesk/support/students/" + outside + "/registration/add",
                Map.of("session", S, "semester", 1, "offering", offering.get("ZZR 101@" + S).toString(), "reason", "asked")).getStatusCode().value()).isEqualTo(404);
        assertThat(it.call(seniorTok, HttpMethod.POST, "/api/v1/helpdesk/support/students/" + outside + "/password", Map.of("method", "LINK", "reason", "asked")).getStatusCode().value()).isEqualTo(404);
        String outsideRef = it.db(() -> jdbc.sql("SELECT finance.new_purpose_reference(:s, :ses, 1000, 'School fees ' || :ses)").param("s", outside).param("ses", S).query(String.class).single());
        assertThat(it.get(seniorTok, "/api/v1/helpdesk/support/payments/" + outsideRef).getStatusCode().value()).isEqualTo(404);
        assertThat(((List) it.get(seniorTok, "/api/v1/helpdesk/support/payments?q=" + outsideRef).getBody().get("rows"))).isEmpty();
        // a student's token is refused at the desk
        assertThat(it.get(TestTokens.token(student, List.of("student")), base()).getStatusCode().value()).isEqualTo(403);
        // 33 · results, 35 · refunds, 34 · fees and amounts, 36 · admission decisions: closed to an agent, by the server
        assertThat(it.call(seniorTok, HttpMethod.POST, "/api/v1/results/legacy/students", Map.of("rows", List.of())).getStatusCode().value()).isEqualTo(403);
        assertThat(it.call(seniorTok, HttpMethod.POST, "/api/v1/finance/refunds/" + UUID.randomUUID() + "/approve", Map.of()).getStatusCode().value()).isEqualTo(403);
        assertThat(it.call(seniorTok, HttpMethod.POST, "/api/v1/finance/sessions/2073/2074/fee-structure", Map.of("rows", List.of(Map.of("amount", 1)))).getStatusCode().value()).isEqualTo(403);
        assertThat(it.call(seniorTok, HttpMethod.PUT, "/api/v1/admissions/sessions/2073/2074/applications/" + UUID.randomUUID() + "/decision", Map.of("decision", "ADMIT")).getStatusCode().value()).isEqualTo(403);
        // 37 · RBAC on the server: a capability the desk does not define is refused on the posting; the Head reaches the outside student
        UUID posting = jdbc.sql("SELECT id FROM helpdesk.agent_assignment WHERE person_id = :p LIMIT 1").param("p", cpo).query(UUID.class).single();
        for (String forbidden : List.of("EDIT_RESULTS", "DELETE_RESULTS", "APPROVE_REFUND", "CHANGE_FEES", "CHANGE_PAYMENT_AMOUNT", "ISSUE_MATRICULATION", "CHANGE_ADMISSION_DECISION")) {
            assertThat(it.call(headTok, HttpMethod.PUT, "/api/v1/helpdesk/admin/agents/" + posting, Map.of("capabilities", List.of(forbidden))).getStatusCode().value()).as(forbidden).isIn(400, 422);
        }
        assertThat(it.get(headTok, "/api/v1/helpdesk/support/students/" + outside).getStatusCode().value()).isEqualTo(200);
        // the Support Action Center offers only what the postings carry
        List<Map> centre = (List<Map>) it.get(cpoTok, base()).getBody().get("center");
        assertThat(centre).extracting(c -> c.get("code")).contains("ADD_COURSE", "DROP_COURSE").doesNotContain("RESET_PASSWORD", "OVERRIDE_REGISTRATION", "VERIFY_PAYMENT", "REFRESH_ENTITLEMENT");
    }
}
