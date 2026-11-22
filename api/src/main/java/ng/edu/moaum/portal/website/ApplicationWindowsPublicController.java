package ng.edu.moaum.portal.website;

import java.time.OffsetDateTime;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.concurrent.TimeUnit;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.CacheControl;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import ng.edu.moaum.portal.shared.ApplicationWindows;

/**
 * Whether Post-UTME registration and the postgraduate application are open (V312), for the University's
 * public website and the portal's own login and apply pages: the state of each window for the session an
 * application would be filed under today, its dates, the Director of ICT's closure message while it is not
 * open, and the address to send an applicant to. Unauthenticated and cross-origin like the statistics beside
 * it; nothing personal, and cached for a minute so a change by the Director reaches the website within one.
 *
 * <pre>
 * GET /api/v1/public/application-windows[?session=2026/2027]
 * {
 *   "postUtme":     { "type": "POST_UTME_REGISTRATION",   "label": "Post-UTME registration",   "session": "2026/2027",
 *                     "status": "OPEN", "open": true, "opensAt": null, "closesAt": "2026-11-30T22:59:00Z", "message": null,
 *                     "applicationPath": "/apply", "applicationUrl": "https://portal.example/apply" },
 *   "postgraduate": { "type": "POSTGRADUATE_APPLICATION", "label": "Postgraduate application", ... "applicationPath": "/pg/apply" },
 *   "interUniversityTransfer": { "type": "INTER_UNIVERSITY_TRANSFER_APPLICATION", "label": "Inter-university transfer application",
 *                     "session": "2026/2027", "status": "OPEN", "open": true, "opensAt": "2026-11-20T00:00+01:00",
 *                     "closesAt": "2027-01-15T23:59:59+01:00", "message": null, "applicationPath": "/transfer/apply", ... },
 *   "now": "2026-10-04T09:00:00Z"
 * }
 * </pre>
 * {@code status} is OPEN, CLOSED, SCHEDULED or EXPIRED; {@code message} is set only while the window is not open. V766: the
 * inter-university transfer application's window is the Academic Office's (admissions.iut_window, not the Director's): its session is
 * the one whose window is open, else the latest opened; its programmes, fee and documents are at /api/v1/public/inter-university-transfer.
 */
@RestController
@RequestMapping("/api/v1/public")
class ApplicationWindowsPublicController {

    private final ApplicationWindows windows;
    private final JdbcClient jdbc;
    private final String portalUrl;

    ApplicationWindowsPublicController(ApplicationWindows windows, JdbcClient jdbc,
                                       @Value("${moaum.portal-url:https://moaum-portal-production.up.railway.app}") String portalUrl) {
        this.windows = windows;
        this.jdbc = jdbc;
        this.portalUrl = portalUrl == null ? "" : portalUrl.replaceAll("/+$", "");
    }

    @GetMapping("/application-windows")
    @Transactional(readOnly = true)
    public ResponseEntity<Map<String, Object>> applicationWindows(@RequestParam(required = false) String session) {
        String s = session != null && session.trim().matches("^\\d{4}/\\d{4}$") ? session.trim() : null;
        Map<String, ApplicationWindows.Window> all = windows.readAll(s);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("postUtme", view(all.get(ApplicationWindows.POST_UTME), "/apply"));
        out.put("postgraduate", view(all.get(ApplicationWindows.POSTGRADUATE), "/pg/apply"));
        out.put("jupeb", view(all.get(ApplicationWindows.JUPEB), "/jupeb/apply"));
        // V379: the CCE application — only those on JAMB's CCE list may apply
        out.put("cce", view(all.get(ApplicationWindows.CCE), "/cce/apply"));
        // V701: the preliminary and proficiency programmes, each on its own window
        out.put("preliminaryScience", view(all.get(ApplicationWindows.PRELIMINARY_SCIENCE), "/preliminary-science"));
        out.put("preliminaryTechnology", view(all.get(ApplicationWindows.PRELIMINARY_TECHNOLOGY), "/preliminary-technology"));
        out.put("proficiencyCertificate", view(all.get(ApplicationWindows.PROFICIENCY_CERTIFICATE), "/proficiency-certificate"));
        // V385: the Post-UTME CBT door and the result-checking page, each on the Director's own window for the Post-UTME session
        String putme = all.get(ApplicationWindows.POST_UTME).session();
        out.put("postUtmeCbt", view(windows.read(ApplicationWindows.POST_UTME_CBT, putme), "/post-utme/cbt"));
        out.put("postUtmeResults", view(windows.read(ApplicationWindows.POST_UTME_RESULTS, putme), "/post-utme/results"));
        // V766: the inter-university transfer application, on the Academic Office's own window (admissions.iut_public)
        out.put("interUniversityTransfer", transfer());
        out.put("now", OffsetDateTime.now());
        return ResponseEntity.ok().cacheControl(CacheControl.maxAge(60, TimeUnit.SECONDS).cachePublic()).body(out);
    }

    /** V766: the inter-university transfer application's window in the shape of the others: the session iut_public names (the one
     *  open, else the latest opened), opensAt from the opening day's start in Lagos, closesAt at the closing day's end */
    private Map<String, Object> transfer() {
        Map<String, Object> w = jdbc.sql("""
                SELECT x->>'session' AS session, coalesce(x->'window'->>'status', 'CLOSED') AS status,
                       ((x->'window'->>'opensOn')::date::timestamp AT TIME ZONE 'Africa/Lagos') AS opens_at,
                       (((x->'window'->>'closesOn')::date + time '23:59:59') AT TIME ZONE 'Africa/Lagos') AS closes_at,
                       x->'window'->>'message' AS message
                  FROM (SELECT admissions.iut_public(NULL) AS x) p
                """).query().singleRow();
        boolean open = "OPEN".equals(w.get("status"));
        Map<String, Object> v = new LinkedHashMap<>();
        v.put("type", "INTER_UNIVERSITY_TRANSFER_APPLICATION");
        v.put("label", "Inter-university transfer application");
        v.put("session", w.get("session"));
        v.put("status", w.get("status"));
        v.put("open", open);
        v.put("opensAt", at(w.get("opens_at")));
        v.put("closesAt", at(w.get("closes_at")));
        v.put("message", open ? null : w.get("message"));
        v.put("applicationPath", "/transfer/apply");
        v.put("applicationUrl", portalUrl + "/transfer/apply");
        return v;
    }

    /** a timestamp as the other doors give theirs (ApplicationWindows.at) */
    private static OffsetDateTime at(Object v) {
        if (v instanceof OffsetDateTime o) return o;
        if (v instanceof java.sql.Timestamp ts) return ts.toInstant().atOffset(java.time.ZoneOffset.UTC);
        if (v instanceof java.time.Instant i) return i.atOffset(java.time.ZoneOffset.UTC);
        return null;
    }

    private Map<String, Object> view(ApplicationWindows.Window w, String path) {
        Map<String, Object> v = new LinkedHashMap<>();
        v.put("type", w.type());
        v.put("label", ApplicationWindows.word(w.type()));
        v.put("session", w.session());
        v.put("status", w.state());
        v.put("open", w.open());
        v.put("opensAt", w.opensAt());
        v.put("closesAt", w.closesAt());
        v.put("message", w.open() ? null : w.message());
        v.put("applicationPath", path);
        v.put("applicationUrl", portalUrl + path);
        return v;
    }
}
