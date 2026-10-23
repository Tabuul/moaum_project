package ng.edu.moaum.portal.helpdesk;

import java.sql.Types;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.UUID;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

import ng.edu.moaum.portal.shared.AuditContext;
import ng.edu.moaum.portal.shared.AuditContextHolder;
import ng.edu.moaum.portal.shared.DomainRuleViolation;
import ng.edu.moaum.portal.shared.NotFound;
import ng.edu.moaum.portal.student.StudentReach;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * V642: "Report financial issue" on the Academic Office student edit page. The Academic Office reads a student's fees and payments
 * there and corrects none of them; what looks wrong goes to the Bursary and ICT Support as a Payment ticket for the student,
 * routed as every ticket is, the student told by the ticket's own notices. The report is kept on the student's change history
 * under its STU-EDIT reference.
 */
@RestController
@RequestMapping("/api/v1/student")
class StudentEditIssueController {

    private static final String HOLDERS = "hasAnyAuthority('OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar','OFFICE_super')";

    public record IssueIn(@NotBlank @Size(max = 200) String subject, @NotBlank @Size(max = 4000) String description) {
    }

    private final JdbcClient jdbc;
    private final StudentReach reach;
    private final TicketNotifier notifier;

    StudentEditIssueController(JdbcClient jdbc, StudentReach reach, TicketNotifier notifier) {
        this.jdbc = jdbc;
        this.reach = reach;
        this.notifier = notifier;
    }

    @PostMapping("/students/{id}/edit/financial-issue")
    @PreAuthorize(HOLDERS)
    @Transactional
    Map<String, Object> report(@PathVariable UUID id, @Valid @RequestBody IssueIn body) {
        String office = AuditContextHolder.current().map(AuditContext::actorOffice).orElse("");
        UUID actor = AuditContextHolder.current().map(AuditContext::actorId).orElse(null);
        if (!Boolean.TRUE.equals(jdbc.sql("SELECT people.student_edit_may(:o, 'EDIT_STUDENT_ACADEMIC_RECORD')").param("o", office).query(Boolean.class).single())) {
            throw new AccessDeniedException("Your office does not report financial issues from the student edit page.");
        }
        reach.check(id);
        String description = body.description().trim();
        if (description.length() < 15) {
            throw new DomainRuleViolation("STU_EDIT_ISSUE", "Describe what looks wrong: the payment, the session, and what you expected.",
                    new DomainRuleViolation.Remedy("Write it in a sentence or two.", "You"));
        }
        Map<String, Object> s = jdbc.sql("""
                SELECT upper(btrim(s.surname)) || coalesce(', ' || nullif(btrim(s.other_names), ''), '') AS name, coalesce(s.matric_no, s.admission_no) AS number,
                       r.email, r.phone, p.dept_code, p.faculty_code
                  FROM people.student s JOIN ref.programme p ON p.code = s.programme_code LEFT JOIN LATERAL people.student_reach(s.id) r ON true
                 WHERE s.id = :s
                """).param("s", id).query().listOfRows().stream().findFirst().orElseThrow(() -> new NotFound("student", id));
        String officer = actor == null ? "the Academic Office" : jdbc.sql("SELECT helpdesk.person_name(:p)").param("p", actor).query(String.class).optional().orElse("the Academic Office");
        String text = "Reported from the Academic Office student edit page by " + officer + " (" + office + "):\n\n" + description;
        UUID ticket = jdbc.sql("SELECT helpdesk.submit('STUDENT', :id, :n, :num, :e, :ph, :d, :f, 'PAYMENT', :s, :desc, '{}'::jsonb)")
                .param("id", id).param("n", s.get("name")).param("num", s.get("number"), Types.VARCHAR).param("e", s.get("email"), Types.VARCHAR)
                .param("ph", s.get("phone"), Types.VARCHAR).param("d", s.get("dept_code"), Types.VARCHAR).param("f", s.get("faculty_code"), Types.VARCHAR)
                .param("s", body.subject().trim()).param("desc", text).query(UUID.class).single();
        jdbc.sql("SELECT helpdesk.route(:t)").param("t", ticket).query(String.class).single();
        notifier.submitted(ticket);
        String number = jdbc.sql("SELECT number FROM helpdesk.ticket WHERE id = :t").param("t", ticket).query(String.class).single();
        String reference = jdbc.sql("SELECT people.student_edit_note(:s, 'FINANCE', 'financial issue', NULL, :n, :r, 'NORMAL', 'FINANCIAL_ISSUE', NULL, NULL, :ev, 'helpdesk_ticket', :t)")
                .param("s", id).param("n", "Ticket " + number + ": " + body.subject().trim()).param("r", description).param("ev", number).param("t", ticket)
                .query(String.class).single();
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("ticket", number);
        out.put("reference", reference);
        return out;
    }
}
