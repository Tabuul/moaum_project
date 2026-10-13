package ng.edu.moaum.portal.platform;

import java.util.LinkedHashMap;
import java.util.Map;
import java.util.UUID;

import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/** The outbox as the platform's offices see it: what waits, what went, and whether a provider is wired at all. */
@RestController
@RequestMapping("/api/v1/platform/notices")
class NoticesController {

    private final NoticeRepository notices;
    private final NoticeDispatcher dispatcher;

    NoticesController(NoticeRepository notices, NoticeDispatcher dispatcher) {
        this.notices = notices;
        this.dispatcher = dispatcher;
    }

    /** the outbox, and (V425) the history searched: channel, state, what it is about, words, a day range; the picture by channel */
    @GetMapping
    @PreAuthorize("hasAnyAuthority('OFFICE_ict','OFFICE_admin','OFFICE_super','OFFICE_registrar','OFFICE_dregistrar')")
    @Transactional(readOnly = true)
    Map<String, Object> outbox(@RequestParam(required = false) String channel, @RequestParam(required = false) String state,
                               @RequestParam(required = false) String kind, @RequestParam(required = false) String q,
                               @RequestParam(required = false) java.time.LocalDate from, @RequestParam(required = false) java.time.LocalDate to,
                               @RequestParam(defaultValue = "100") int limit) {
        Map<String, Object> out = new LinkedHashMap<>();
        Map<String, Object> c = notices.counts();
        out.put("queued", c.get("queued"));
        out.put("sent", c.get("sent"));
        out.put("failed", c.get("failed"));
        out.put("sentToday", c.get("sent_today"));
        out.put("emailProvider", dispatcher.emailConfigured());
        out.put("smsProvider", dispatcher.smsConfigured());
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
}
