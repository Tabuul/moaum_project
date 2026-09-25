package ng.edu.moaum.portal.examiners;

import java.time.LocalDate;
import java.time.format.DateTimeFormatter;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import ng.edu.moaum.portal.platform.NoticeRepository;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Component;

/**
 * What the module says, and to whom, through the portal's one outbox (V025): the examiner at each turn of an
 * appointment and an assignment, and the desk — whoever assigned, and the Academic Office — when an examiner
 * activates, submits, or falls overdue. University-branded, queued in the caller's transaction.
 */
@Component
class ExaminerNotifier {

    static final String UNIVERSITY = "Rev. Fr. Moses Orshio Adasu University, Makurdi";
    private static final DateTimeFormatter DAY = DateTimeFormatter.ofPattern("d MMMM yyyy");

    private final NoticeRepository notices;
    private final JdbcClient jdbc;
    private final String portalUrl;

    ExaminerNotifier(NoticeRepository notices, JdbcClient jdbc, @Value("${moaum.portal-url:https://moaum-portal-production.up.railway.app}") String portalUrl) {
        this.notices = notices;
        this.jdbc = jdbc;
        this.portalUrl = portalUrl.endsWith("/") ? portalUrl.substring(0, portalUrl.length() - 1) : portalUrl;
    }

    record Ex(UUID id, UUID personId, String name, String email, String institution) {
    }

    record Asg(UUID id, UUID examinerId, UUID projectId, String title, String student, String number, String programme, String department, String session,
               LocalDate deadline, UUID assignedBy) {
    }

    Ex examiner(UUID id) {
        Map<String, Object> r = jdbc.sql("SELECT e.id, e.person_id, extexam.examiner_name(e.id) AS name, e.email, e.institution FROM extexam.examiner e WHERE e.id = :id")
                .param("id", id).query().singleRow();
        return new Ex((UUID) r.get("id"), (UUID) r.get("person_id"), (String) r.get("name"), (String) r.get("email"), (String) r.get("institution"));
    }

    Asg assignment(UUID id) {
        Map<String, Object> r = jdbc.sql("""
                SELECT a.id, a.examiner_id, a.project_id, p.title, st.surname || ', ' || st.other_names AS student, coalesce(st.matric_no, st.admission_no) AS number,
                       pr.name AS programme, d.name AS department, p.session, a.deadline, a.assigned_by
                  FROM extexam.assignment a JOIN extexam.project p ON p.id = a.project_id JOIN people.student st ON st.id = p.student_id
                  JOIN ref.programme pr ON pr.code = st.programme_code JOIN ref.department d ON d.code = pr.dept_code
                 WHERE a.id = :id
                """).param("id", id).query().singleRow();
        return new Asg((UUID) r.get("id"), (UUID) r.get("examiner_id"), (UUID) r.get("project_id"), (String) r.get("title"), (String) r.get("student"), (String) r.get("number"),
                (String) r.get("programme"), (String) r.get("department"), (String) r.get("session"), r.get("deadline") == null ? null : ((java.sql.Date) r.get("deadline")).toLocalDate(),
                (UUID) r.get("assigned_by"));
    }

    private static String sign() {
        return "\n\nAcademic Office\n" + UNIVERSITY + "\n";
    }

    private void toExaminer(Ex e, String subject, String body) {
        if (e.email() == null || e.email().isBlank()) return;
        notices.queueEmail(e.email(), subject, "Dear " + e.name() + ",\n\n" + body + sign(), "person", e.personId(), List.of());
    }

    /** whoever assigned the project, and the Academic Office; each once */
    private void toDesk(UUID assignedBy, String subject, String body) {
        List<Map<String, Object>> people = jdbc.sql("""
                SELECT DISTINCT p.id, p.email FROM iam.person p
                 WHERE p.ended_on IS NULL AND p.email IS NOT NULL AND btrim(p.email) <> ''
                   AND (p.id = :by OR EXISTS (SELECT 1 FROM iam.office_assignment a WHERE a.person_id = p.id AND a.office_code = 'academic'
                                                AND a.valid_from <= current_date AND (a.valid_to IS NULL OR a.valid_to >= current_date)))
                """).param("by", assignedBy, java.sql.Types.OTHER).query().listOfRows();
        for (Map<String, Object> p : people) notices.queueEmail((String) p.get("email"), subject, body + sign(), "person", (UUID) p.get("id"), List.of());
    }

    private String describe(Asg a) {
        return "Project: " + a.title() + "\nCandidate: " + a.student() + " (" + a.number() + ")\nProgramme: " + a.programme() + ", " + a.department() + "\nSession: " + a.session()
                + (a.deadline() == null ? "" : "\nReview deadline: " + a.deadline().format(DAY));
    }

    private String workspace() {
        return "Sign in at " + portalUrl + "/login with your email address to open your examiner workspace.";
    }

    /* ── the events ── */

    void invited(UUID examinerId, String link, LocalDate expires, String appointment) {
        Ex e = examiner(examinerId);
        toExaminer(e, "External Examiner Appointment — " + UNIVERSITY,
                "The University invites you to serve as an External Examiner" + (appointment == null ? "" : " for " + appointment) + ", to assess final-year projects independently on the University's assessment form.\n\n"
                        + "Please activate your examiner account through this link, which works once and expires on " + expires.format(DAY) + ":\n\n" + link + "\n\n"
                        + "You will choose a password on that page; the University never sends passwords by email. Your username is this email address. "
                        + "Once active, the projects assigned to you, their documents and the assessment form are in your workspace.");
    }

    void activated(UUID examinerId, UUID invitedBy) {
        Ex e = examiner(examinerId);
        toDesk(invitedBy, "External examiner account activated — " + e.name(),
                e.name() + " (" + e.institution() + ") has activated their examiner account and can now receive project assignments.\n\nOpen the register: " + portalUrl + "/examiners/" + e.id());
    }

    void appointed(UUID examinerId, String appointment, LocalDate from, LocalDate to) {
        Ex e = examiner(examinerId);
        toExaminer(e, "External Examiner Appointment — " + UNIVERSITY,
                "You have been appointed External Examiner for " + appointment + ", from " + from.format(DAY) + " to " + to.format(DAY) + ".\n\n" + workspace());
    }

    void assigned(UUID assignmentId) {
        Asg a = assignment(assignmentId);
        toExaminer(examiner(a.examinerId()), "New Project Assigned for Review — " + UNIVERSITY,
                "A final-year project has been assigned to you for independent assessment.\n\n" + describe(a) + "\n\n" + workspace());
    }

    void reassignedAway(UUID oldAssignmentId, String reason) {
        Asg a = assignment(oldAssignmentId);
        toExaminer(examiner(a.examinerId()), "Project Assignment Withdrawn — " + UNIVERSITY,
                "The project below is no longer assigned to you; it has been passed to another examiner.\n\n" + describe(a) + "\n\nReason: " + reason + "\n\nNo further action is needed from you on it.");
    }

    void withdrawn(UUID assignmentId, String reason) {
        Asg a = assignment(assignmentId);
        toExaminer(examiner(a.examinerId()), "Project Assignment Withdrawn — " + UNIVERSITY,
                "The project below has been withdrawn from your list.\n\n" + describe(a) + "\n\nReason: " + reason);
    }

    void deadlineChanged(UUID assignmentId, LocalDate was, String reason) {
        Asg a = assignment(assignmentId);
        toExaminer(examiner(a.examinerId()), "Review Deadline Changed — " + UNIVERSITY,
                "The review deadline for the project below has changed" + (was == null ? "" : " from " + was.format(DAY)) + ".\n\n" + describe(a) + (reason == null || reason.isBlank() ? "" : "\n\nReason: " + reason) + "\n\n" + workspace());
    }

    void reminder(UUID assignmentId, long daysLeft) {
        Asg a = assignment(assignmentId);
        toExaminer(examiner(a.examinerId()), "Reminder: Project Review Deadline — " + UNIVERSITY,
                "The review deadline for the project below is " + (daysLeft <= 0 ? "today" : "in " + daysLeft + " day" + (daysLeft == 1 ? "" : "s")) + ".\n\n" + describe(a) + "\n\n" + workspace());
    }

    void overdue(UUID assignmentId) {
        Asg a = assignment(assignmentId);
        Ex e = examiner(a.examinerId());
        toExaminer(e, "Project Review Overdue — " + UNIVERSITY,
                "The review deadline for the project below has passed and the assessment has not been submitted.\n\n" + describe(a) + "\n\nPlease submit it as soon as you can, or write to the Academic Office if you need more time.\n\n" + workspace());
        toDesk(a.assignedBy(), "External examiner review overdue — " + a.number(),
                e.name() + " (" + e.institution() + ") has not submitted the assessment below by its deadline.\n\n" + describe(a) + "\n\nOpen it: " + portalUrl + "/examiners/assignments/" + a.id());
    }

    void submitted(UUID assignmentId, boolean again) {
        Asg a = assignment(assignmentId);
        Ex e = examiner(a.examinerId());
        toDesk(a.assignedBy(), "External Examiner Assessment " + (again ? "Resubmitted" : "Submitted") + " — " + a.number(),
                e.name() + " (" + e.institution() + ") has " + (again ? "resubmitted" : "submitted") + " the assessment below.\n\n" + describe(a) + "\n\nOpen it: " + portalUrl + "/examiners/assignments/" + a.id());
        toExaminer(e, "Assessment Received — " + UNIVERSITY,
                "Thank you. Your assessment of the project below has been received and is now read-only.\n\n" + describe(a) + "\n\nIf the University needs a correction, the desk will reopen it and you will be told.");
    }

    void reopened(UUID assignmentId, String reason) {
        Asg a = assignment(assignmentId);
        toExaminer(examiner(a.examinerId()), "Assessment Reopened for Revision — " + UNIVERSITY,
                "Your assessment of the project below has been reopened by the University so that you can revise it.\n\n" + describe(a) + "\n\nReason: " + reason + "\n\nYour earlier scores and comments are kept; revise what is needed and submit again.\n\n" + workspace());
    }

    void locked(UUID assignmentId) {
        Asg a = assignment(assignmentId);
        toExaminer(examiner(a.examinerId()), "Assessment Approved and Locked — " + UNIVERSITY,
                "Your assessment of the project below has been approved by the University and is now locked.\n\n" + describe(a) + "\n\nThank you for your service as External Examiner.");
    }
}
