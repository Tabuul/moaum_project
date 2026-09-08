package ng.edu.moaum.portal.platform;

import java.util.LinkedHashMap;
import java.util.Map;

import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
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

    @GetMapping
    @PreAuthorize("hasAnyAuthority('OFFICE_ict','OFFICE_admin','OFFICE_super','OFFICE_registrar')")
    Map<String, Object> outbox() {
        Map<String, Object> out = new LinkedHashMap<>();
        Map<String, Object> c = notices.counts();
        out.put("queued", c.get("queued"));
        out.put("sent", c.get("sent"));
        out.put("failed", c.get("failed"));
        out.put("sentToday", c.get("sent_today"));
        out.put("emailProvider", dispatcher.emailConfigured());
        out.put("smsProvider", dispatcher.smsConfigured());
        out.put("recent", notices.recent(50));
        return out;
    }
}
