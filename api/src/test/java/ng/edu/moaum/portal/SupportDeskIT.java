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
 * The support desk across the University (V328), over the API: the Head posts agents on queues within a scope — and only people who
 * hold the agent office; a ticket is routed on submission to the agent posted to its faculty; an agent reaches nothing outside their
 * scope (403), the Head everything; a transfer moves the one ticket and the old agent loses it; an escalation goes only to the queue's
 * office, which answers from its own door and nobody else can; a wait on the requester ends with their reply; a critical priority is
 * taken; the password reset goes through the portal's secure door and shows the desk nothing; an agent taken off the desk holds nothing;
 * an agent cannot administer the desk. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class SupportDeskIT {

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;
    ItSupport it;

    UUID headId, facultyAgentId, bursaryAgentId, bursarId, nobodyId;
    String head, facultyAgent, bursaryAgent, bursar;
    UUID student, otherStudent;
    String studentToken, otherToken;
    String faculty;

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
        headId = it.person("MOAUM/IT/SD01", "ZZSDHEAD");
        facultyAgentId = it.person("MOAUM/IT/SD02", "ZZSDFACULTY");
        bursaryAgentId = it.person("MOAUM/IT/SD03", "ZZSDBURSARY");
        bursarId = it.person("MOAUM/IT/SD04", "ZZSDBURSAR");
        nobodyId = it.person("MOAUM/IT/SD05", "ZZSDNOBODY");
        office(headId, "helpdeskhead");
        office(facultyAgentId, "ictagent");
        office(bursaryAgentId, "ictagent");
        office(bursarId, "bursar");
        head = TestTokens.token(headId, List.of("helpdeskhead"));
        facultyAgent = TestTokens.token(facultyAgentId, List.of("ictagent"));
        bursaryAgent = TestTokens.token(bursaryAgentId, List.of("ictagent"));
        bursar = TestTokens.token(bursarId, List.of("bursar"));
        // the first student's faculty, and a programme of another faculty for the second
        faculty = jdbc.sql("SELECT faculty_code FROM ref.programme WHERE code = 'C00023'").query(String.class).single();
        String otherProgramme = jdbc.sql("SELECT code FROM ref.programme WHERE faculty_code <> :f ORDER BY code LIMIT 1").param("f", faculty).query(String.class).single();
        student = it.student("ZZSDSTUDENT", "C00023", null, "MOAUM/MTC/95/9811", 300);
        otherStudent = it.student("ZZSDOTHER", otherProgramme, null, "MOAUM/MTC/95/9812", 300);
        studentToken = TestTokens.token(student, List.of("student"));
        otherToken = TestTokens.token(otherStudent, List.of("student"));
        // a clean slate for these people: earlier runs' postings ended, nothing held, and the invented students' earlier tickets
        // closed (a requester may hold ten open tickets at most — a shared database fills that over repeated runs)
        it.db(() -> {
            jdbc.sql("UPDATE iam.person SET email = lower(surname) || '@example.edu' WHERE id IN (:a, :b, :c, :d)").param("a", headId).param("b", facultyAgentId).param("c", bursaryAgentId).param("d", bursarId).update();
            jdbc.sql("UPDATE helpdesk.agent_assignment SET active = false WHERE person_id IN (:a, :b) AND active").param("a", facultyAgentId).param("b", bursaryAgentId).update();
            jdbc.sql("UPDATE helpdesk.ticket SET assigned_to = NULL WHERE assigned_to IN (:a, :b) AND status NOT IN ('RESOLVED','CLOSED')").param("a", facultyAgentId).param("b", bursaryAgentId).update();
            for (UUID s : List.of(student, otherStudent)) {
                for (UUID t : jdbc.sql("SELECT id FROM helpdesk.ticket WHERE requester_kind = 'STUDENT' AND requester_id = :s AND status <> 'CLOSED'").param("s", s).query(UUID.class).list()) {
                    jdbc.sql("SELECT helpdesk.transition(:t, 'CLOSED', 'REQUESTER', :s, 'Invented, Student', 'Closed before the next test run')").param("t", t).param("s", s).query().singleRow();
                }
            }
            return null;
        });
        // the Head posts the faculty agent on ICT Support for the student's faculty, and the Bursary agent University-wide on Bursary Support
        ResponseEntity<Map> p1 = it.call(head, HttpMethod.POST, "/api/v1/helpdesk/admin/agents", Map.of("personId", facultyAgentId.toString(), "queueCode", "ICT_SUPPORT", "scopeKind", "FACULTY", "scopeRef", faculty, "reason", "integration test"));
        assertThat(p1.getStatusCode().value()).as(String.valueOf(p1.getBody())).isEqualTo(200);
        ResponseEntity<Map> p2 = it.call(head, HttpMethod.POST, "/api/v1/helpdesk/admin/agents", Map.of("personId", bursaryAgentId.toString(), "queueCode", "BURSARY_SUPPORT", "scopeKind", "GLOBAL", "reason", "integration test"));
        assertThat(p2.getStatusCode().value()).as(String.valueOf(p2.getBody())).isEqualTo(200);
    }

    private void office(UUID person, String code) {
        it.db(() -> {
            jdbc.sql("""
                    INSERT INTO iam.office_assignment (id, person_id, office_code, scope_kind, instrument, granted_by, valid_from)
                    SELECT gen_random_uuid(), :p, :o, 'platform', 'integration test', :p, current_date
                     WHERE NOT EXISTS (SELECT 1 FROM iam.office_assignment a WHERE a.person_id = :p AND a.office_code = :o AND (a.valid_to IS NULL OR a.valid_to >= current_date))
                    """).param("p", person).param("o", code).update();
            return null;
        });
    }

    private static Object path(Map body, String key) {
        return body == null ? null : body.get(key);
    }

    private String login(String token, String username) {
        ResponseEntity<Map> made = it.call(token, HttpMethod.POST, "/api/v1/helpdesk/my/tickets", Map.of(
                "category", "LOGIN", "subject", "Cannot sign in", "description", "The portal refuses my password though I reset it this morning.",
                "email", username.toLowerCase().replaceAll("[^a-z0-9]", "") + "@example.edu",
                "details", Map.of("account_type", "Student", "username", username, "error", "Password refused")));
        assertThat(made.getStatusCode().value()).as(String.valueOf(made.getBody())).isEqualTo(200);
        return String.valueOf(path(made.getBody(), "id"));
    }

    @Test
    void aTicketIsRoutedToThePostedAgentWhoSeesOnlyTheirScopeAndATransferMovesTheOneTicket() {
        // routed on submission: the student's faculty has a posted agent, so the ticket is theirs at once
        String t1 = login(studentToken, "MOAUM/MTC/95/9811");
        ResponseEntity<Map> read = it.get(head, "/api/v1/helpdesk/tickets/" + t1);
        assertThat(read.getStatusCode().value()).as(String.valueOf(read.getBody())).isEqualTo(200);
        assertThat(path(read.getBody(), "queue_code")).isEqualTo("ICT_SUPPORT");
        assertThat(String.valueOf(path(read.getBody(), "assigned_to"))).isEqualTo(facultyAgentId.toString());
        List<Map> history = (List<Map>) path(read.getBody(), "timeline");
        assertThat(history).extracting(e -> e.get("action")).contains("ROUTED", "ASSIGNED");
        // the other faculty has no posted agent on ICT Support: queued for the Head, nobody's
        String t2 = login(otherToken, "MOAUM/MTC/95/9812");
        ResponseEntity<Map> read2 = it.get(head, "/api/v1/helpdesk/tickets/" + t2);
        assertThat(path(read2.getBody(), "assigned_to")).isNull();
        assertThat(((List<Map>) path(read2.getBody(), "timeline"))).extracting(e -> e.get("action")).contains("QUEUED");
        // scope, enforced on the server: the faculty agent reaches their faculty's ticket and not the other's; their queue lists only theirs; the Head sees both
        assertThat(it.get(facultyAgent, "/api/v1/helpdesk/tickets/" + t1).getStatusCode().value()).isEqualTo(200);
        assertThat(it.get(facultyAgent, "/api/v1/helpdesk/tickets/" + t2).getStatusCode().value()).isEqualTo(403);
        assertThat(it.call(facultyAgent, HttpMethod.POST, "/api/v1/helpdesk/tickets/" + t2 + "/comments", Map.of("body", "peeking", "internal", true)).getStatusCode().value()).isEqualTo(403);
        ResponseEntity<Map> mine = it.get(facultyAgent, "/api/v1/helpdesk/tickets?status=all&size=100");
        List<Map> rows = (List<Map>) path(mine.getBody(), "rows");
        assertThat(rows).extracting(r -> String.valueOf(r.get("id"))).contains(t1).doesNotContain(t2);
        ResponseEntity<Map> all = it.get(head, "/api/v1/helpdesk/tickets?status=all&size=100&queue=ICT_SUPPORT");
        assertThat(((List<Map>) path(all.getBody(), "rows"))).extracting(r -> String.valueOf(r.get("id"))).contains(t1, t2);
        // the agents list against the ticket says who the routing would choose
        ResponseEntity<List> agents = it.callList(head, HttpMethod.GET, "/api/v1/helpdesk/agents?ticket=" + t1, null);
        assertThat((List<Map>) agents.getBody()).anySatisfy(a -> { assertThat(String.valueOf(a.get("id"))).isEqualTo(facultyAgentId.toString()); assertThat(a.get("eligible")).isEqualTo(true); assertThat(a.get("posted")).isEqualTo(true); });
        // a transfer needs a reason (a blank one fails validation; a transfer to the queue the ticket is on already is refused by the desk's rule);
        // it moves the one ticket to the Bursary queue and its agent; the old agent loses it; the student still has one ticket of the kind
        assertThat(it.call(head, HttpMethod.POST, "/api/v1/helpdesk/tickets/" + t1 + "/transfer", Map.of("queue", "BURSARY_SUPPORT", "reason", "")).getStatusCode().value()).isEqualTo(400);
        ResponseEntity<Map> same = it.call(head, HttpMethod.POST, "/api/v1/helpdesk/tickets/" + t1 + "/transfer", Map.of("queue", "ICT_SUPPORT", "reason", "Nowhere to go"));
        assertThat(same.getStatusCode().value()).isEqualTo(422);
        assertThat(path(same.getBody(), "code")).isEqualTo("HELPDESK_TRANSFER_SAME");
        ResponseEntity<Map> moved = it.call(head, HttpMethod.POST, "/api/v1/helpdesk/tickets/" + t1 + "/transfer", Map.of("queue", "BURSARY_SUPPORT", "reason", "A payment lies under the login problem"));
        assertThat(moved.getStatusCode().value()).as(String.valueOf(moved.getBody())).isEqualTo(200);
        assertThat(path(moved.getBody(), "queue")).isEqualTo("BURSARY_SUPPORT");
        assertThat(String.valueOf(path(moved.getBody(), "assignedTo"))).isEqualTo(bursaryAgentId.toString());
        assertThat(it.get(facultyAgent, "/api/v1/helpdesk/tickets/" + t1).getStatusCode().value()).isEqualTo(403);
        assertThat(it.get(bursaryAgent, "/api/v1/helpdesk/tickets/" + t1).getStatusCode().value()).isEqualTo(200);
        ResponseEntity<List> theirs = it.callList(studentToken, HttpMethod.GET, "/api/v1/helpdesk/my/tickets", null);
        List<Map> same1 = ((List<Map>) theirs.getBody()).stream().filter(r -> t1.equals(String.valueOf(r.get("id")))).toList();
        assertThat(same1).hasSize(1);
        assertThat(same1.get(0).get("queue_code")).isEqualTo("BURSARY_SUPPORT");
        assertThat(jdbc.sql("SELECT count(*) FROM helpdesk.ticket WHERE number = (SELECT number FROM helpdesk.ticket WHERE id = :id)").param("id", UUID.fromString(t1)).query(Long.class).single()).isEqualTo(1L);
        // the student sees the transfer on the history but never the desk's routing business
        ResponseEntity<Map> seen = it.get(studentToken, "/api/v1/helpdesk/my/tickets/" + t1);
        assertThat(path(seen.getBody(), "queue")).isEqualTo("Bursary Support");
        assertThat(((List<Map>) path(seen.getBody(), "timeline"))).extracting(e -> e.get("action")).contains("TRANSFERRED").doesNotContain("ROUTED", "QUEUED");
        // the desk's counts (the ticket-first desk): within scope — the faculty agent's new tickets exclude the other faculty's; the Head's include both; the desk's questions filter the queue
        ResponseEntity<Map> headCounts = it.get(head, "/api/v1/helpdesk/counts");
        assertThat(headCounts.getStatusCode().value()).as(String.valueOf(headCounts.getBody())).isEqualTo(200);
        assertThat(((Number) path(headCounts.getBody(), "unassigned")).longValue()).isGreaterThanOrEqualTo(1L);
        assertThat(path(headCounts.getBody(), "head")).isEqualTo(true);
        ResponseEntity<Map> agentCounts = it.get(facultyAgent, "/api/v1/helpdesk/counts");
        assertThat(agentCounts.getStatusCode().value()).isEqualTo(200);
        assertThat(path(agentCounts.getBody(), "head")).isEqualTo(false);
        assertThat(((Number) path(agentCounts.getBody(), "open")).longValue()).isLessThan(((Number) path(headCounts.getBody(), "open")).longValue());
        ResponseEntity<Map> unassignedOnly = it.get(head, "/api/v1/helpdesk/tickets?status=open&agent=none&sort=priority&size=100");
        assertThat(((List<Map>) path(unassignedOnly.getBody(), "rows"))).allSatisfy(r -> assertThat(r.get("assigned_to")).isNull());
        assertThat(((List<Map>) path(unassignedOnly.getBody(), "rows"))).extracting(r -> String.valueOf(r.get("id"))).contains(t2);
        ResponseEntity<Map> escalatedOnly = it.get(head, "/api/v1/helpdesk/tickets?status=open&escalated=true&size=100");
        assertThat(((List<Map>) path(escalatedOnly.getBody(), "rows"))).allSatisfy(r -> assertThat(Boolean.TRUE.equals(r.get("escalated")) || r.get("escalated_office") != null).isTrue());
        assertThat(it.get(studentToken, "/api/v1/helpdesk/counts").getStatusCode().value()).isEqualTo(403);
        // the queues and the workload answer the Head; an agent reads only their own load
        ResponseEntity<List> queues = it.callList(head, HttpMethod.GET, "/api/v1/helpdesk/queues", null);
        assertThat((List<Map>) queues.getBody()).extracting(q -> q.get("code")).contains("ICT_SUPPORT", "BURSARY_SUPPORT");
        ResponseEntity<List> load = it.callList(bursaryAgent, HttpMethod.GET, "/api/v1/helpdesk/workload", null);
        assertThat((List<Map>) load.getBody()).allSatisfy(w -> assertThat(String.valueOf(w.get("person_id"))).isEqualTo(bursaryAgentId.toString()));
    }

    @Test
    void anEscalationGoesOnlyToTheQueuesOfficeWhichAloneAnswersAndAWaitEndsWithTheRequestersReply() {
        ResponseEntity<Map> made = it.call(studentToken, HttpMethod.POST, "/api/v1/helpdesk/my/tickets", Map.of(
                "category", "PAYMENT", "subject", "Payment not showing", "description", "I paid school fees on Monday and the portal still says unpaid.",
                "email", "zzsd@example.edu", "details", Map.of("payment_reference", "RRR-328", "payment_date", "2026-09-01", "payment_type", "School fees", "amount", "45000")));
        assertThat(made.getStatusCode().value()).as(String.valueOf(made.getBody())).isEqualTo(200);
        String id = String.valueOf(path(made.getBody(), "id"));
        ResponseEntity<Map> read = it.get(bursaryAgent, "/api/v1/helpdesk/tickets/" + id);
        assertThat(read.getStatusCode().value()).as(String.valueOf(read.getBody())).isEqualTo(200);
        assertThat(path(read.getBody(), "queue_code")).isEqualTo("BURSARY_SUPPORT");
        assertThat(String.valueOf(path(read.getBody(), "assigned_to"))).isEqualTo(bursaryAgentId.toString());
        assertThat(((List<Map>) path(read.getBody(), "escalation_offices"))).extracting(o -> o.get("code")).containsExactlyInAnyOrder("bursar", "ict");
        assertThat(it.call(bursaryAgent, HttpMethod.POST, "/api/v1/helpdesk/tickets/" + id + "/status", Map.of("status", "IN_PROGRESS")).getStatusCode().value()).isEqualTo(200);
        // the wrong office is refused; the queue's office takes it; the ticket waits
        ResponseEntity<Map> wrong = it.call(bursaryAgent, HttpMethod.POST, "/api/v1/helpdesk/tickets/" + id + "/escalate-office", Map.of("office", "academic", "reason", "Please decide this payment"));
        assertThat(wrong.getStatusCode().value()).isEqualTo(422);
        assertThat(path(wrong.getBody(), "code")).isEqualTo("HELPDESK_ESCALATION_OFFICE");
        ResponseEntity<Map> esc = it.call(bursaryAgent, HttpMethod.POST, "/api/v1/helpdesk/tickets/" + id + "/escalate-office", Map.of("office", "bursar", "reason", "The payment is on the bank statement but not on the ledger; the Bursary decides whether to post it"));
        assertThat(esc.getStatusCode().value()).as(String.valueOf(esc.getBody())).isEqualTo(200);
        ResponseEntity<Map> waiting = it.get(studentToken, "/api/v1/helpdesk/my/tickets/" + id);
        assertThat(path(waiting.getBody(), "status")).isEqualTo("WAITING_FOR_OFFICE");
        assertThat(path(waiting.getBody(), "office")).isEqualTo("Bursar");
        assertThat(((List<Map>) path(waiting.getBody(), "timeline"))).extracting(e -> e.get("action")).doesNotContain("ESCALATED_TO_OFFICE");
        // the Bursary was told; an agent who is not the Bursar cannot answer; the student cannot reach the office's door
        assertThat(jdbc.sql("SELECT count(*) FROM platform.notice WHERE recipient = 'zzsdbursar@example.edu' AND subject LIKE 'A support ticket awaits your decision%'").query(Long.class).single()).isGreaterThanOrEqualTo(1L);
        assertThat(it.call(facultyAgent, HttpMethod.POST, "/api/v1/helpdesk/office/tickets/" + id + "/answer", Map.of("body", "I am not the Bursar but here goes")).getStatusCode().value()).isEqualTo(403);
        assertThat(it.get(studentToken, "/api/v1/helpdesk/office/tickets").getStatusCode().value()).isEqualTo(403);
        ResponseEntity<Map> desk = it.get(bursar, "/api/v1/helpdesk/office/tickets");
        assertThat(desk.getStatusCode().value()).as(String.valueOf(desk.getBody())).isEqualTo(200);
        assertThat(((List<Map>) path(desk.getBody(), "waiting"))).extracting(r -> String.valueOf(r.get("id"))).contains(id);
        ResponseEntity<Map> answered = it.call(bursar, HttpMethod.POST, "/api/v1/helpdesk/office/tickets/" + id + "/answer", Map.of("body", "Confirmed on the bank statement; post it to the ledger and tell the student the receipt is reissued."));
        assertThat(answered.getStatusCode().value()).as(String.valueOf(answered.getBody())).isEqualTo(200);
        ResponseEntity<Map> back = it.get(bursaryAgent, "/api/v1/helpdesk/tickets/" + id);
        assertThat(path(back.getBody(), "status")).isEqualTo("IN_PROGRESS");
        assertThat(path(back.getBody(), "escalated_office")).isNull();
        assertThat(((List<Map>) path(back.getBody(), "comments"))).anySatisfy(c -> { assertThat(String.valueOf(c.get("body"))).startsWith("Confirmed on the bank statement"); assertThat(c.get("internal")).isEqualTo(true); });
        // the office's internal answer never reaches the student
        ResponseEntity<Map> seen = it.get(studentToken, "/api/v1/helpdesk/my/tickets/" + id);
        assertThat(((List<Map>) path(seen.getBody(), "comments"))).extracting(c -> String.valueOf(c.get("body"))).noneMatch(b -> b.startsWith("Confirmed on the bank statement"));
        // waiting on the requester needs a reason; the requester's reply resumes the work by itself
        assertThat(it.call(bursaryAgent, HttpMethod.POST, "/api/v1/helpdesk/tickets/" + id + "/status", Map.of("status", "WAITING_FOR_STUDENT")).getStatusCode().value()).isEqualTo(422);
        assertThat(it.call(bursaryAgent, HttpMethod.POST, "/api/v1/helpdesk/tickets/" + id + "/status", Map.of("status", "WAITING_FOR_STUDENT", "reason", "Send the bank's debit alert")).getStatusCode().value()).isEqualTo(200);
        assertThat(path(it.get(studentToken, "/api/v1/helpdesk/my/tickets/" + id).getBody(), "status")).isEqualTo("WAITING_FOR_STUDENT");
        assertThat(it.call(studentToken, HttpMethod.POST, "/api/v1/helpdesk/my/tickets/" + id + "/comments", Map.of("body", "Here is the debit alert, attached.")).getStatusCode().value()).isEqualTo(200);
        assertThat(path(it.get(bursaryAgent, "/api/v1/helpdesk/tickets/" + id).getBody(), "status")).isEqualTo("IN_PROGRESS");
        // a critical priority is taken, and the figures count it
        ResponseEntity<Map> critical = it.call(bursaryAgent, HttpMethod.POST, "/api/v1/helpdesk/tickets/" + id + "/priority", Map.of("priority", "CRITICAL"));
        assertThat(critical.getStatusCode().value()).as(String.valueOf(critical.getBody())).isEqualTo(200);
        ResponseEntity<Map> stats = it.get(head, "/api/v1/helpdesk/stats?queue=BURSARY_SUPPORT");
        assertThat(((Number) ((Map) path(stats.getBody(), "totals")).get("critical")).longValue()).isGreaterThanOrEqualTo(1L);
        // the password reset goes through the portal's own door: a reset is recorded for the student, the student is told, the desk sees no password.
        // V346: for a student, only a posting that carries RESET_PASSWORD and covers the student resets it
        ResponseEntity<Map> unauthorised = it.call(bursaryAgent, HttpMethod.POST, "/api/v1/helpdesk/tickets/" + id + "/password-reset", Map.of());
        assertThat(unauthorised.getStatusCode().value()).isEqualTo(422);
        assertThat(unauthorised.getBody().get("code")).isEqualTo("SUPPORT_CAPABILITY");
        UUID posting = jdbc.sql("SELECT id FROM helpdesk.agent_assignment WHERE person_id = :p AND active AND queue_code = 'BURSARY_SUPPORT'").param("p", bursaryAgentId).query(UUID.class).single();
        assertThat(it.call(head, HttpMethod.PUT, "/api/v1/helpdesk/admin/agents/" + posting, Map.of("capabilities", List.of("RESET_PASSWORD"))).getStatusCode().value()).isEqualTo(200);
        ResponseEntity<Map> reset = it.call(bursaryAgent, HttpMethod.POST, "/api/v1/helpdesk/tickets/" + id + "/password-reset", Map.of());
        assertThat(reset.getStatusCode().value()).as(String.valueOf(reset.getBody())).isEqualTo(200);
        assertThat(reset.getBody().keySet()).doesNotContain("password", "token", "link");
        assertThat(jdbc.sql("SELECT count(*) FROM iam.password_reset WHERE subject_id = :s AND used_at IS NULL AND expires_at > now()").param("s", student).query(Long.class).single()).isGreaterThanOrEqualTo(1L);
        assertThat(((List<Map>) path(it.get(studentToken, "/api/v1/helpdesk/my/tickets/" + id).getBody(), "comments"))).extracting(c -> String.valueOf(c.get("body"))).anyMatch(b -> b.startsWith("A password reset link has been sent"));
        assertThat(jdbc.sql("SELECT count(*) FROM helpdesk.support_action WHERE student_id = :s AND action = 'PASSWORD_RESET' AND method = 'RESET_LINK' AND ticket_id = :t AND new_value IS NULL")
                .param("s", student).param("t", UUID.fromString(String.valueOf(id))).query(Long.class).single()).isEqualTo(1L);
    }

    @Test
    void anAgentTakenOffTheDeskHoldsNothingAndAnAgentCannotAdministerTheDesk() {
        // support access is the office's: a person without it cannot be posted; an agent cannot reach the Head's doors
        ResponseEntity<Map> notAgent = it.call(head, HttpMethod.POST, "/api/v1/helpdesk/admin/agents", Map.of("personId", nobodyId.toString(), "queueCode", "ICT_SUPPORT", "scopeKind", "GLOBAL"));
        assertThat(notAgent.getStatusCode().value()).isEqualTo(422);
        assertThat(path(notAgent.getBody(), "code")).isEqualTo("HELPDESK_NOT_AN_AGENT");
        assertThat(it.get(facultyAgent, "/api/v1/helpdesk/admin/agents").getStatusCode().value()).isEqualTo(403);
        assertThat(it.call(facultyAgent, HttpMethod.POST, "/api/v1/helpdesk/admin/queues", Map.of("name", "Rogue")).getStatusCode().value()).isEqualTo(403);
        assertThat(it.call(facultyAgent, HttpMethod.POST, "/api/v1/helpdesk/admin/routing", Map.of("categoryCode", "LOGIN", "queueCode", "ICT_SUPPORT", "strategy", "MANUAL")).getStatusCode().value()).isEqualTo(403);
        // a scope that is not on the register is refused
        ResponseEntity<Map> badScope = it.call(head, HttpMethod.POST, "/api/v1/helpdesk/admin/agents", Map.of("personId", facultyAgentId.toString(), "queueCode", "LIBRARY_SUPPORT", "scopeKind", "FACULTY", "scopeRef", "NOPE"));
        assertThat(badScope.getStatusCode().value()).isEqualTo(422);
        assertThat(path(badScope.getBody(), "code")).isEqualTo("HELPDESK_SCOPE_UNKNOWN");
        // a ticket routed to the faculty agent; the Head takes them off the desk; the ticket is back on its queue with no agent, on the record
        String t = login(studentToken, "MOAUM/MTC/95/9811");
        assertThat(String.valueOf(path(it.get(head, "/api/v1/helpdesk/tickets/" + t).getBody(), "assigned_to"))).isEqualTo(facultyAgentId.toString());
        ResponseEntity<Map> off = it.call(head, HttpMethod.POST, "/api/v1/helpdesk/admin/agents/" + facultyAgentId + "/deactivate", Map.of("reason", "Transferred out of the Directorate"));
        assertThat(off.getStatusCode().value()).as(String.valueOf(off.getBody())).isEqualTo(200);
        assertThat(((Number) path(off.getBody(), "returned")).intValue()).isGreaterThanOrEqualTo(1);
        ResponseEntity<Map> after = it.get(head, "/api/v1/helpdesk/tickets/" + t);
        assertThat(path(after.getBody(), "assigned_to")).isNull();
        assertThat(path(after.getBody(), "queue_code")).isEqualTo("ICT_SUPPORT");
        assertThat(((List<Map>) path(after.getBody(), "timeline"))).extracting(e -> e.get("action")).contains("RETURNED");
        // the Head was told, once, with the number
        assertThat(jdbc.sql("SELECT count(*) FROM platform.notice WHERE recipient = 'zzsdhead@example.edu' AND subject LIKE '%returned to the queue'").query(Long.class).single()).isGreaterThanOrEqualTo(1L);
        // the agent whose every posting has ended sees nothing beyond what is with them
        assertThat(it.get(facultyAgent, "/api/v1/helpdesk/tickets/" + t).getStatusCode().value()).isEqualTo(403);
        // the Head keeps a queue and a rule
        ResponseEntity<Map> queue = it.call(head, HttpMethod.POST, "/api/v1/helpdesk/admin/queues", Map.of("code", "IT_" + UUID.randomUUID().toString().substring(0, 6).toUpperCase(), "name", "Test Queue " + UUID.randomUUID().toString().substring(0, 4), "officeCode", "registrar"));
        assertThat(queue.getStatusCode().value()).as(String.valueOf(queue.getBody())).isEqualTo(200);
        String code = String.valueOf(path(queue.getBody(), "code"));
        ResponseEntity<Map> rule = it.call(head, HttpMethod.POST, "/api/v1/helpdesk/admin/routing", Map.of("categoryCode", "GENERAL", "facultyCode", faculty, "queueCode", code, "strategy", "MANUAL"));
        assertThat(rule.getStatusCode().value()).as(String.valueOf(rule.getBody())).isEqualTo(200);
        ResponseEntity<Map> retired = it.call(head, HttpMethod.PUT, "/api/v1/helpdesk/admin/queues/" + code, Map.of("name", "Test Queue (retired)", "active", false));
        assertThat(retired.getStatusCode().value()).as(String.valueOf(retired.getBody())).isEqualTo(200);
        ResponseEntity<Map> badRule = it.call(head, HttpMethod.POST, "/api/v1/helpdesk/admin/routing", Map.of("categoryCode", "GENERAL", "queueCode", "ICT_SUPPORT", "strategy", "RANDOMLY"));
        assertThat(badRule.getStatusCode().value()).isEqualTo(422);
    }
}
