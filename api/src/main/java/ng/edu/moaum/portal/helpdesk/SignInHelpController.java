package ng.edu.moaum.portal.helpdesk;

import java.util.LinkedHashMap;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

import jakarta.servlet.http.HttpServletRequest;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

import ng.edu.moaum.portal.shared.AuditContext;
import ng.edu.moaum.portal.shared.AuditContextHolder;
import ng.edu.moaum.portal.shared.ClientAddress;
import ng.edu.moaum.portal.shared.DomainRuleViolation;
import ng.edu.moaum.portal.shared.Throttle;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * V363: help asked of the ICT Support Desk from the sign-in page, by a person who cannot sign in — the one the reset link
 * never reaches, whose account is locked, whose number the portal does not recognise. It becomes a Login Issues ticket
 * that names no account (helpdesk.submit_public); the desk confirms who the person is before it acts on any account, and
 * the person follows it on the public tracking page with its number and their email.
 *
 * <p>Open to anyone, so each connection is limited (Throttle, SIGN_IN_HELP) and an email address keeps at most three such
 * requests open. The answer is the ticket's number and nothing else.
 *
 * <p>Oct 2026: for the student portal, the number is checked against the register as it is typed (/check) and again when
 * the request is sent: a matriculation number — or the admission number a student signs in with before one is issued — that
 * no student holds is refused, so the desk is not sent numbers it cannot find. The check says only whether a student holds
 * the number, never whose it is, and each connection may check a limited number of times (Throttle, SIGN_IN_HELP_CHECK). An
 * email, or a staff or applicant name, is still never said to name an account.
 */
@RestController
@RequestMapping("/api/v1/helpdesk/sign-in-help")
class SignInHelpController {

    private static final UUID NOBODY = new UUID(0, 0);
    private static final tools.jackson.databind.ObjectMapper JSON = new tools.jackson.databind.ObjectMapper();

    private final JdbcClient jdbc;
    private final TransactionTemplate tx;
    private final TicketNotifier notifier;
    private final Throttle throttle;

    SignInHelpController(JdbcClient jdbc, PlatformTransactionManager transactions, TicketNotifier notifier, Throttle throttle) {
        this.jdbc = jdbc;
        this.tx = new TransactionTemplate(transactions);
        this.notifier = notifier;
        this.throttle = throttle;
    }

    /** the questions the request asks — the Login Issues category's own, as the desk keeps them */
    @GetMapping
    Map<String, Object> form() {
        Map<String, Object> c = jdbc.sql("SELECT active, fields::text AS fields, description FROM helpdesk.category WHERE code = 'LOGIN'").query().listOfRows()
                .stream().findFirst().orElse(Map.of("active", false, "fields", "[]"));
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("open", Boolean.TRUE.equals(c.get("active")));
        out.put("fields", JSON.readTree(String.valueOf(c.get("fields"))));
        return out;
    }

    public record Ask(@NotBlank @Size(max = 120) String name, @NotBlank @Size(max = 200) String email, @Size(max = 30) String phone,
                      @NotBlank @Size(max = 4000) String description, Map<String, String> details) {
    }

    /** the account type names the student portal ("Student portal", as the desk words it) */
    static boolean studentPortal(String accountType) {
        return accountType != null && accountType.toLowerCase(java.util.Locale.ROOT).contains("student");
    }

    /** a number as a student would type it, as the register keeps it: upper case, no spaces */
    static String normal(String number) {
        return number == null ? "" : number.replaceAll("\\s+", "").toUpperCase(java.util.Locale.ROOT);
    }

    /** whether a student holds the number — the matriculation number, or the admission number before one is issued */
    private boolean studentHolds(String number) {
        return Boolean.TRUE.equals(jdbc.sql("SELECT EXISTS (SELECT 1 FROM people.student WHERE upper(matric_no) = :n OR upper(admission_no) = :n)")
                .param("n", number).query(Boolean.class).single());
    }

    public record Check(@Size(max = 60) String accountType, @Size(max = 60) String number) {
    }

    /**
     * Oct 2026: the number checked as it is typed, for the student portal only — whether a student holds it, never whose; every
     * check counted against the connection (SIGN_IN_HELP_CHECK). A number in the body, not the address, so it is not logged.
     */
    @PostMapping("/check")
    Map<String, Object> check(@Valid @RequestBody Check body, HttpServletRequest request) {
        if (!studentPortal(body.accountType())) {
            return Map.of("applies", false);
        }
        String n = normal(body.number());
        if (n.length() < 4) {
            return Map.of("applies", true, "found", false);
        }
        throttle.take(Throttle.Door.SIGN_IN_HELP_CHECK, ClientAddress.of(request));
        return Map.of("applies", true, "found", studentHolds(n));
    }

    @PostMapping
    Map<String, Object> ask(@Valid @RequestBody Ask body, HttpServletRequest request) {
        String from = ClientAddress.of(request);
        throttle.take(Throttle.Door.SIGN_IN_HELP, from);
        Set<String> declared = declaredKeys();
        Map<String, String> details = new LinkedHashMap<>();
        if (body.details() != null) body.details().forEach((k, v) -> {
            if (k != null && declared.contains(k) && v != null && !v.isBlank() && details.size() < 30) details.put(k, v.trim().substring(0, Math.min(v.trim().length(), 500)));
        });
        // Oct 2026: a student's number is one the register holds
        if (studentPortal(details.get("account_type")) && !studentHolds(normal(details.get("username")))) {
            throw new DomainRuleViolation("HELPDESK_HELP_NUMBER_UNKNOWN",
                    "No student record holds the number " + (details.get("username") == null ? "given" : details.get("username")) + ".",
                    new DomainRuleViolation.Remedy("Type your matriculation number as it is on your identity card (or your admission number if you have no matriculation number yet). "
                            + "If it is right and still not found, visit the Registry with your admission letter.", "Registry"));
        }
        String number = AuditContextHolder.with(new AuditContext(NOBODY, "ict", "sign-in help asked from the sign-in page", null, from), () -> tx.execute(st -> {
            UUID id = jdbc.sql("SELECT helpdesk.submit_public(:n, :e, :p, :d::jsonb, :desc)")
                    .param("n", body.name()).param("e", body.email()).param("p", body.phone(), java.sql.Types.VARCHAR)
                    .param("d", JSON.writeValueAsString(details)).param("desc", body.description())
                    .query(UUID.class).single();
            // routed as any Login Issues ticket is; with no faculty or department, to the queue's general agents or the Head
            jdbc.sql("SELECT helpdesk.route(:t)").param("t", id).query(String.class).single();
            notifier.submitted(id);
            return jdbc.sql("SELECT number FROM helpdesk.ticket WHERE id = :id").param("id", id).query(String.class).single();
        }));
        return Map.of("number", number, "status", "SUBMITTED");
    }

    private Set<String> declaredKeys() {
        String fields = jdbc.sql("SELECT fields::text FROM helpdesk.category WHERE code = 'LOGIN'").query(String.class).optional().orElse("[]");
        Set<String> keys = new java.util.HashSet<>();
        for (var node : JSON.readTree(fields)) if (node.get("key") != null) keys.add(node.get("key").asText());
        return keys;
    }
}
