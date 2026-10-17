package ng.edu.moaum.portal.platform;

import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import ng.edu.moaum.portal.shared.AuditContext;
import ng.edu.moaum.portal.shared.AuditContextHolder;
import ng.edu.moaum.portal.shared.DomainRuleViolation;

/** The outbox as the platform's offices see it: what waits, what went, and whether a provider is wired at all. */
@RestController
@RequestMapping("/api/v1/platform/notices")
class NoticesController {

    private final NoticeRepository notices;
    private final NoticeDispatcher dispatcher;
    private final ng.edu.moaum.portal.shared.JobLock lock;
    private final org.springframework.transaction.support.TransactionTemplate tx;
    private final ProviderWatch providers;
    private final MailService mail;
    private final SmsService sms;

    NoticesController(NoticeRepository notices, NoticeDispatcher dispatcher, ng.edu.moaum.portal.shared.JobLock lock,
                      org.springframework.transaction.PlatformTransactionManager transactions, ProviderWatch providers,
                      MailService mail, SmsService sms) {
        this.notices = notices;
        this.dispatcher = dispatcher;
        this.lock = lock;
        this.tx = new org.springframework.transaction.support.TransactionTemplate(transactions);
        this.providers = providers;
        this.mail = mail;
        this.sms = sms;
    }

    private static String text(Object o) {
        return o == null ? "" : String.valueOf(o).trim();
    }

    /**
     * V532: what e-mail goes through, in words — the account on the Mail server screen (the dispatcher's first choice), else the
     * relay; null when neither is set. The password is never read here.
     */
    private String emailVia() {
        Map<String, Object> m = mail.config();
        String host = text(m.get("smtp_host"));
        String user = text(m.get("username"));
        if (!host.isEmpty() && !user.isEmpty() && Boolean.TRUE.equals(m.get("password_set")) && Boolean.TRUE.equals(m.get("configKeyPresent"))) {
            String from = text(m.get("from_address"));
            return "SMTP " + host + ":" + (m.get("smtp_port") == null ? 587 : m.get("smtp_port")) + " " + (text(m.get("smtp_encryption")).isEmpty() ? "STARTTLS" : text(m.get("smtp_encryption")))
                    + ", signed in as " + user + (from.isEmpty() || from.equalsIgnoreCase(user) ? "" : ", sending as " + from) + " (the Mail server screen)";
        }
        if (dispatcher.emailConfigured()) {
            return "An HTTP relay (MOAUM_NOTICES_EMAIL_URL)";
        }
        return null;
    }

    /** V532: what SMS goes through, in words — the account on the SMS gateway screen, else the relay; null when neither */
    private String smsVia() {
        Map<String, Object> m = sms.config();
        if (Boolean.TRUE.equals(m.get("enabled")) && Boolean.TRUE.equals(m.get("api_key_set")) && !text(m.get("username")).isEmpty()
                && Boolean.TRUE.equals(m.get("configKeyPresent"))) {
            return (text(m.get("provider")).isEmpty() ? "eBulkSMS" : text(m.get("provider"))) + ", as " + text(m.get("username"))
                    + (text(m.get("sender")).isEmpty() ? "" : ", sender " + text(m.get("sender"))) + " (the SMS gateway screen)";
        }
        if (dispatcher.smsConfigured()) {
            return "An HTTP relay (MOAUM_NOTICES_SMS_URL)";
        }
        return null;
    }

    /** the outbox, and (V425) the history searched: channel, state, what it is about, words, a day range; the picture by channel */
    @GetMapping
    @PreAuthorize("hasAnyAuthority('OFFICE_ict','OFFICE_admin','OFFICE_super','OFFICE_registrar','OFFICE_dregistrar')")
    @Transactional(readOnly = true)
    Map<String, Object> outbox(@RequestParam(required = false) String channel, @RequestParam(required = false) String state,
                               @RequestParam(required = false) String kind, @RequestParam(required = false) String q,
                               @RequestParam(required = false) java.time.LocalDate from, @RequestParam(required = false) java.time.LocalDate to,
                               @RequestParam(defaultValue = "100") int limit,
                               org.springframework.security.core.Authentication auth) {
        Map<String, Object> out = new LinkedHashMap<>();
        // V438: the providers' delivery reports, and the receipt door's token for those who set it
        out.put("receipts", notices.receipts(20));
        // V442: each channel's health, and the watch's settings
        out.put("providers", notices.providerStatus());
        out.put("providerSettings", notices.providerSettings());
        boolean operator = auth != null && auth.getAuthorities().stream().map(Object::toString)
                .anyMatch(a -> a.equals("OFFICE_ict") || a.equals("OFFICE_admin") || a.equals("OFFICE_super"));
        out.put("receiptToken", operator ? notices.receiptToken() : null);
        Map<String, Object> c = notices.counts();
        out.put("queued", c.get("queued"));
        out.put("sent", c.get("sent"));
        out.put("failed", c.get("failed"));
        out.put("cancelled", c.get("cancelled"));
        out.put("sentToday", c.get("sent_today"));
        // V436: the switches, what waits now, the jobs that would still write to the queue, the last clearance
        out.put("delivery", notices.deliveryRow());
        out.put("pending", notices.pending());
        out.put("jobs", notices.openJobs());
        List<Map<String, Object>> clearances = notices.clearances(1);
        out.put("lastClearance", clearances.isEmpty() ? null : clearances.get(0));
        // V532: the provider in use named (the Mail server and SMS gateway screens counted, not only the relays), and the SMTP pace
        String emailVia = emailVia();
        String smsVia = smsVia();
        out.put("emailProvider", emailVia != null);
        out.put("smsProvider", smsVia != null);
        out.put("emailVia", emailVia);
        out.put("smsVia", smsVia);
        out.put("smtpPace", notices.smtpPace());
        out.put("byChannel", notices.byChannel());
        boolean filtered = channel != null || state != null || kind != null || (q != null && !q.isBlank()) || from != null || to != null;
        out.put("recent", filtered
                ? notices.search(blank(channel), blank(state), blank(kind), blank(q), from, to, Math.max(1, Math.min(limit, 1000)))
                : notices.recent(Math.max(1, Math.min(limit, 1000))));
        return out;
    }

    private static String blank(String s) {
        return s == null || s.isBlank() ? null : s.trim();
    }

    private static final String OPERATORS = "hasAnyAuthority('OFFICE_ict','OFFICE_admin','OFFICE_super')";

    /** put one failed notice back in the queue; the dispatcher tries it again within the minute */
    @PostMapping("/{id}/retry")
    @PreAuthorize(OPERATORS)
    @Transactional
    Map<String, Object> retry(@PathVariable UUID id) {
        return Map.of("requeued", notices.requeue(id));
    }

    /** put every failed notice back in the queue */
    @PostMapping("/retry-failed")
    @PreAuthorize(OPERATORS)
    @Transactional
    Map<String, Object> retryFailed() {
        return Map.of("requeued", notices.requeueAllFailed());
    }

    // ── V436: the delivery switches, the clearance, the jobs ──

    private static final String CLEARERS = "hasAnyAuthority('OFFICE_ict','OFFICE_super')";

    private static Boolean bool(Object o) {
        return o instanceof Boolean b ? b : null;
    }

    /** the switches: queue processing, e-mail delivery, SMS delivery, portal notices — delivery only; the modules go on generating */
    @PutMapping("/delivery")
    @PreAuthorize(OPERATORS)
    @Transactional
    Map<String, Object> setDelivery(@RequestBody Map<String, Object> body) {
        AuditContext ctx = AuditContextHolder.required();
        notices.setDelivery(bool(body.get("dispatch")), bool(body.get("email")), bool(body.get("sms")), bool(body.get("portal")), ctx.actorId(), ctx.actorOffice());
        return notices.deliveryRow();
    }

    record PaceIn(Integer perMinute, Integer perDay) { }

    /** V532: how fast e-mail goes over SMTP — a minute's and a day's most (empty: no limit); Microsoft 365 allows one mailbox 30 and 10,000 */
    @PutMapping("/smtp-pace")
    @PreAuthorize(OPERATORS)
    @Transactional
    NoticeRepository.SmtpPace setSmtpPace(@RequestBody PaceIn in) {
        AuditContext ctx = AuditContextHolder.required();
        notices.setSmtpPace(in.perMinute(), in.perDay(), ctx.actorId(), ctx.actorOffice());
        return notices.smtpPace();
    }

    record ClearIn(List<String> channels, String reason) { }

    /**
     * The pending e-mail and/or SMS queue cancelled — never deleted. Queue processing is paused first, in a transaction of its own,
     * so no instance starts a batch; the clearance then runs under the dispatcher's own lock, so a batch in flight finishes before
     * it and none starts during it. Processing stays paused afterwards: the office verifies the counts and resumes it.
     */
    @PostMapping("/clear")
    @PreAuthorize(CLEARERS)
    Map<String, Object> clear(@RequestBody ClearIn in) {
        AuditContext ctx = AuditContextHolder.required();
        List<String> channels = in.channels() == null ? List.of() : in.channels();
        AuditContextHolder.with(ctx, () -> tx.execute(st -> {
            notices.setDelivery(false, null, null, null, ctx.actorId(), ctx.actorOffice());
            return null;
        }));
        java.util.concurrent.atomic.AtomicReference<Map<String, Object>> done = new java.util.concurrent.atomic.AtomicReference<>();
        boolean ran = false;
        for (int attempt = 0; attempt < 12 && !ran; attempt++) {
            ran = lock.runExclusively("notice-dispatcher", () -> done.set(AuditContextHolder.with(ctx, () ->
                    tx.execute(st -> notices.clear(channels, in.reason(), ctx.actorId(), ctx.actorOffice())))));
            if (!ran) {
                try {
                    Thread.sleep(500);
                } catch (InterruptedException e) {
                    Thread.currentThread().interrupt();
                    break;
                }
            }
        }
        if (!ran) {
            throw new DomainRuleViolation("NOTICE_DISPATCH_BUSY",
                    "A batch is being sent at this moment. Queue processing is now paused, so no further batch starts: try again within the minute.");
        }
        Map<String, Object> out = new LinkedHashMap<>(done.get());
        Map<String, Object> verification = new LinkedHashMap<>();
        verification.put("pending", notices.pending());
        verification.put("processing", 0);
        verification.put("dispatch_enabled", false);
        out.put("verification", verification);
        return out;
    }

    /** V442: the provider watch — on or off, and the SMS balance below which ICT is warned (0: no warning) */
    @PutMapping("/providers")
    @PreAuthorize(OPERATORS)
    @Transactional
    Map<String, Object> setProviderWatch(@RequestBody Map<String, Object> body) {
        AuditContext ctx = AuditContextHolder.required();
        Object low = body.get("lowBalance");
        java.math.BigDecimal threshold = null;
        if (low instanceof Number n) {
            threshold = new java.math.BigDecimal(n.toString());
        } else if (low instanceof String s && !s.isBlank()) {
            try {
                threshold = new java.math.BigDecimal(s.trim());
            } catch (NumberFormatException e) {
                throw new DomainRuleViolation("PROVIDER_LOW_BALANCE", "The balance to warn below is a number of SMS units; 0 switches the warning off.");
            }
        }
        if (threshold != null && threshold.signum() < 0) {
            throw new DomainRuleViolation("PROVIDER_LOW_BALANCE", "The balance to warn below is a number of SMS units; 0 switches the warning off.");
        }
        notices.setProviderWatch(bool(body.get("watch")), threshold, ctx.actorId(), ctx.actorOffice());
        return notices.providerSettings();
    }

    /** V442: the SMS balance read and the providers judged now; what was found, and the messages told to ICT */
    @PostMapping("/providers/check")
    @PreAuthorize(OPERATORS)
    Map<String, Object> checkProviders() {
        return providers.check(AuditContextHolder.required());
    }

    /** V438: a new token for the receipt door; the providers' delivery reports must carry it */
    @PostMapping("/receipt-token")
    @PreAuthorize(OPERATORS)
    @Transactional
    Map<String, Object> newReceiptToken() {
        AuditContext ctx = AuditContextHolder.required();
        return Map.of("token", notices.newReceiptToken(ctx.actorId(), ctx.actorOffice()));
    }

    @GetMapping("/clearances")
    @PreAuthorize("hasAnyAuthority('OFFICE_ict','OFFICE_admin','OFFICE_super','OFFICE_registrar','OFFICE_dregistrar')")
    @Transactional(readOnly = true)
    List<Map<String, Object>> clearances() {
        return notices.clearances(50);
    }

    record CancelIn(String reason) { }

    /** a job still running (a window's messages, a campaign) ended, so it does not refill the queue */
    @PostMapping("/jobs/{id}/cancel")
    @PreAuthorize(CLEARERS)
    @Transactional
    Map<String, Object> cancelJob(@PathVariable UUID id, @RequestBody(required = false) CancelIn in) {
        AuditContext ctx = AuditContextHolder.required();
        return Map.of("kind", notices.cancelJob(id, in == null ? null : in.reason(), ctx.actorId(), ctx.actorOffice()), "jobs", notices.openJobs());
    }
}
