package ng.edu.moaum.portal.platform;

import java.util.LinkedHashMap;
import java.util.Map;

import jakarta.validation.Valid;
import jakarta.validation.constraints.Size;

import ng.edu.moaum.portal.shared.AuditContext;
import ng.edu.moaum.portal.shared.AuditContextHolder;
import ng.edu.moaum.portal.shared.DomainRuleViolation;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * The mail server settings, set by the Directorate of ICT and the Super
 * Administrator: IMAP, POP and SMTP for Microsoft 365. The password is written
 * once, encrypted, and never read back — the screen sees only that one is set.
 * V532: the settings tested from the screen — the server reached and the account
 * signed in, or a test e-mail sent — with what a failure means in words.
 */
@RestController
@RequestMapping("/api/v1/platform")
class MailController {

    private static final Logger LOG = LoggerFactory.getLogger(MailController.class);
    private static final String KEEPERS = "hasAnyAuthority('OFFICE_ict','OFFICE_admin','OFFICE_super')";
    private static final java.util.regex.Pattern EMAIL = java.util.regex.Pattern.compile("^[^@\\s]{1,64}@[^@\\s]+\\.[^@\\s]{2,}$");

    private final MailService mail;
    private final SmtpMailer smtp;
    private final NoticeRepository notices;
    private final TransactionTemplate tx;

    MailController(MailService mail, SmtpMailer smtp, NoticeRepository notices, PlatformTransactionManager transactions,
                   tools.jackson.databind.ObjectMapper json) {
        this.mail = mail;
        this.smtp = smtp;
        this.notices = notices;
        this.tx = new TransactionTemplate(transactions);
        this.json = json;
    }

    private final tools.jackson.databind.ObjectMapper json;

    @SuppressWarnings("unchecked")
    @GetMapping("/mail")
    @PreAuthorize(KEEPERS)
    Map<String, Object> config() {
        Map<String, Object> out = new LinkedHashMap<>(mail.config());
        // V556: whether e-mail is held after the server refused the portal, until when and why
        out.put("hold", tx.execute(st -> json.readValue(notices.smtpPauseState(), Map.class)));
        return out;
    }

    @PutMapping("/mail")
    @PreAuthorize(KEEPERS)
    Map<String, Object> save(@Valid @RequestBody MailService.Settings body) {
        Map<String, Object> out = mail.save(body);
        resume();   // V556: the settings changed: e-mail is tried again at once
        return out;
    }

    /** V556: a hold on e-mail ended, in its own transaction */
    private void resume() {
        AuditContext ctx = AuditContextHolder.required();
        AuditContextHolder.with(ctx, () -> tx.execute(st -> notices.smtpResume()));
    }

    @PostMapping("/mail/clear-password")
    @PreAuthorize(KEEPERS)
    Map<String, Object> clearPassword() {
        return mail.clearPassword();
    }

    public record TestIn(@Size(max = 200) String smtpHost, Integer smtpPort, @Size(max = 12) String smtpEncryption, @Size(max = 320) String username,
                         @Size(max = 320) String fromAddress, @Size(max = 400) String password, @Size(max = 320) String sendTo) {
    }

    /**
     * V532: the SMTP settings on the screen (saved or not) tried: without sendTo, the server reached and the account signed in, nothing
     * sent; with it, a short test e-mail sent to that address from the From address — which also shows whether the mailbox may send as
     * it. Not a transaction: the server's answer can take seconds. The answer says how far it got and what a failure means.
     */
    @PostMapping("/mail/test")
    @PreAuthorize(KEEPERS)
    Map<String, Object> test(@Valid @RequestBody TestIn in) {
        AuditContext ctx = AuditContextHolder.required();
        String to = in.sendTo() == null || in.sendTo().isBlank() ? null : in.sendTo().trim();
        if (to != null && !EMAIL.matcher(to).matches()) {
            throw new DomainRuleViolation("MAIL_TEST_ADDRESS", "Send the test to an e-mail address.", new DomainRuleViolation.Remedy("Type a full address, such as your own.", "You"));
        }
        MailService.Smtp s = mail.smtpForTest(in.smtpHost(), in.smtpPort(), in.smtpEncryption(), in.username(), in.fromAddress(), in.password());
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("host", s.host());
        out.put("port", s.port());
        out.put("encryption", s.encryption());
        out.put("username", s.username());
        out.put("from", s.from());
        out.put("sendTo", to);
        long started = System.nanoTime();
        try {
            if (to == null) {
                smtp.test(s);
                out.put("ok", true);
                out.put("stage", "SIGN_IN");
                out.put("words", "Reached " + s.host() + " on port " + s.port() + " and signed in as " + s.username() + ". Nothing was sent.");
            } else {
                smtp.send(s, to, "MOAUM portal: test e-mail from the Mail server screen",
                        "This is a test from the Mail server screen of the portal, sent by the Directorate of ICT to check that e-mail can be sent from "
                                + s.from() + " through " + s.host() + ".\n\nNo action is needed.", java.util.List.of());
                out.put("ok", true);
                out.put("stage", "SEND");
                out.put("words", "Sent to " + to + " from " + s.from() + " through " + s.host() + ". If it does not arrive within a few minutes, look in the junk folder.");
            }
        } catch (Exception e) {
            SmtpFailure.Kind kind = SmtpFailure.of(e);
            out.put("ok", false);
            out.put("stage", SmtpFailure.stage(kind));
            out.put("kind", kind.name());
            out.put("words", SmtpFailure.words(kind, s.host(), s.port(), s.from()));
            out.put("detail", SmtpFailure.detail(e));
        }
        out.put("ms", (System.nanoTime() - started) / 1_000_000);
        if (Boolean.TRUE.equals(out.get("ok"))) {
            resume();   // V556: the settings work: e-mail goes again at once
        }
        if (to != null) {
            // a test e-mail counts against the pace like any other
            boolean ok = Boolean.TRUE.equals(out.get("ok"));
            AuditContextHolder.with(ctx, () -> tx.execute(st -> {
                notices.smtpAttempted(ok);
                return null;
            }));
        }
        LOG.info("mail test by {} ({}): {} {}:{} as {}{} -> {} {}", ctx.actorId(), ctx.actorOffice(), to == null ? "sign-in" : "send", s.host(), s.port(),
                s.username(), to == null ? "" : " to " + to, out.get("ok"), out.getOrDefault("kind", ""));
        return out;
    }
}
