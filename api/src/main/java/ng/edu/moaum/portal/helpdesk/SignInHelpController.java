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
 * requests open. The answer is the ticket's number and nothing else: whether a number or an email names an account is
 * never said here.
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

    @PostMapping
    Map<String, Object> ask(@Valid @RequestBody Ask body, HttpServletRequest request) {
        String from = ClientAddress.of(request);
        throttle.take(Throttle.Door.SIGN_IN_HELP, from);
        Set<String> declared = declaredKeys();
        Map<String, String> details = new LinkedHashMap<>();
        if (body.details() != null) body.details().forEach((k, v) -> {
            if (k != null && declared.contains(k) && v != null && !v.isBlank() && details.size() < 30) details.put(k, v.trim().substring(0, Math.min(v.trim().length(), 500)));
        });
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
