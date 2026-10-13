package ng.edu.moaum.portal.platform;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import tools.jackson.databind.JsonNode;
import tools.jackson.databind.ObjectMapper;
import jakarta.servlet.http.HttpServletRequest;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import ng.edu.moaum.portal.shared.AuditContext;
import ng.edu.moaum.portal.shared.AuditContextHolder;

/**
 * V438: the receipt door — a provider's delivery report on a message the portal sent. Behind the token the Directorate of
 * ICT generated (as {@code ?token=} or {@code X-Receipt-Token}); each report is read by the provider's own shape (Resend's
 * events, eBulkSMS's delivery reports, or a plain {id, status, detail}), matched to the message by the provider's id or the
 * notice's own, and written on it as DELIVERED, BOUNCED or UNDELIVERED — never changing its state. Every report is kept as it
 * came, matched or not.
 */
@RestController
@RequestMapping("/api/v1/notices/receipts")
public class NoticeReceiptsController {

    private static final Logger LOG = LoggerFactory.getLogger(NoticeReceiptsController.class);
    static final UUID NOBODY = new UUID(0, 0);

    private final NoticeRepository notices;
    private final ObjectMapper json;
    private final TransactionTemplate tx;

    NoticeReceiptsController(NoticeRepository notices, ObjectMapper json, PlatformTransactionManager transactions) {
        this.notices = notices;
        this.json = json;
        this.tx = new TransactionTemplate(transactions);
    }

    @PostMapping(value = "/{provider}", consumes = MediaType.ALL_VALUE)
    ResponseEntity<Map<String, Object>> receive(@PathVariable String provider, @RequestParam(required = false) String token,
                                                @RequestHeader(value = "X-Receipt-Token", required = false) String headerToken,
                                                @RequestBody(required = false) String body, HttpServletRequest request) {
        String t = token != null && !token.isBlank() ? token : headerToken;
        if (!notices.receiptTokenOk(t)) {
            return ResponseEntity.status(403).body(Map.of("outcome", "REFUSED", "why", "the receipt door takes reports with the token the Directorate of ICT generated"));
        }
        String p = provider == null ? "generic" : provider.trim().toLowerCase();
        List<Map<String, Object>> items = items(body, request);
        List<Map<String, Object>> outcomes = new ArrayList<>();
        for (Map<String, Object> item : items) {
            String[] read = read(p, item);
            String payload;
            try {
                payload = json.writeValueAsString(item);
            } catch (Exception e) {
                payload = null;
            }
            final String pl = payload;
            Map<String, Object> r = AuditContextHolder.with(new AuditContext(NOBODY, "ict", "delivery receipt", null, null),
                    () -> tx.execute(st -> notices.recordReceipt(p, read[0], read[1], read[2], pl)));
            outcomes.add(r);
        }
        if (LOG.isDebugEnabled()) {
            LOG.debug("notices: {} delivery receipt(s) from {}", outcomes.size(), p);
        }
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("received", outcomes.size());
        out.put("outcomes", outcomes);
        return ResponseEntity.ok(out);
    }

    /** the report's items: a JSON object, a JSON array of them, or form fields */
    @SuppressWarnings("unchecked")
    List<Map<String, Object>> items(String body, HttpServletRequest request) {
        String b = body == null ? "" : body.trim();
        if (b.startsWith("{") || b.startsWith("[")) {
            try {
                JsonNode node = json.readTree(b);
                List<Map<String, Object>> out = new ArrayList<>();
                if (node.isArray()) {
                    for (JsonNode n : node) {
                        out.add(json.convertValue(n, Map.class));
                    }
                } else {
                    out.add(json.convertValue(node, Map.class));
                }
                return out;
            } catch (Exception unreadable) {
                // fall through: kept as a single text item below
            }
        }
        Map<String, Object> one = new LinkedHashMap<>();
        request.getParameterMap().forEach((k, v) -> {
            if (!"token".equals(k) && v != null && v.length > 0) {
                one.put(k, v[0]);
            }
        });
        if (one.isEmpty() && !b.isEmpty()) {
            one.put("text", b.length() > 2000 ? b.substring(0, 2000) : b);
        }
        return List.of(one);
    }

    /** {id, status, detail} as the provider names them */
    @SuppressWarnings("unchecked")
    static String[] read(String provider, Map<String, Object> item) {
        if ("resend".equals(provider)) {
            Object data = item.get("data");
            Map<String, Object> d = data instanceof Map ? (Map<String, Object>) data : Map.of();
            String detail = null;
            Object bounce = d.get("bounce");
            if (bounce instanceof Map) {
                detail = text(((Map<String, Object>) bounce).get("message"));
            }
            return new String[] { text(d.get("email_id")), text(item.get("type")), detail };
        }
        if ("ebulksms".equals(provider)) {
            return new String[] { first(item, "msgid", "messageid", "message_id", "id"), first(item, "status", "dlr", "state", "deliverystatus", "delivery_status"),
                    first(item, "reason", "description", "error", "detail") };
        }
        return new String[] { first(item, "id", "msgid", "message_id", "email_id", "notice_id", "provider_id"),
                first(item, "status", "state", "event", "type"), first(item, "detail", "reason", "message", "description") };
    }

    private static String first(Map<String, Object> item, String... keys) {
        for (String k : keys) {
            String v = text(item.get(k));
            if (v != null) {
                return v;
            }
        }
        return null;
    }

    private static String text(Object o) {
        if (o == null) {
            return null;
        }
        String s = String.valueOf(o).trim();
        return s.isEmpty() ? null : (s.length() > 400 ? s.substring(0, 400) : s);
    }
}
