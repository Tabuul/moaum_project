package ng.edu.moaum.portal.website;

import java.time.OffsetDateTime;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.concurrent.TimeUnit;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.CacheControl;
import org.springframework.http.ResponseEntity;
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
 *   "now": "2026-10-04T09:00:00Z"
 * }
 * </pre>
 * {@code status} is OPEN, CLOSED, SCHEDULED or EXPIRED; {@code message} is set only while the window is not open.
 */
@RestController
@RequestMapping("/api/v1/public")
class ApplicationWindowsPublicController {

    private final ApplicationWindows windows;
    private final String portalUrl;

    ApplicationWindowsPublicController(ApplicationWindows windows,
                                       @Value("${moaum.portal-url:https://moaum-portal-production.up.railway.app}") String portalUrl) {
        this.windows = windows;
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
        // V385: the Post-UTME CBT door and the result-checking page, each on the Director's own window for the Post-UTME session
        String putme = all.get(ApplicationWindows.POST_UTME).session();
        out.put("postUtmeCbt", view(windows.read(ApplicationWindows.POST_UTME_CBT, putme), "/post-utme/cbt"));
        out.put("postUtmeResults", view(windows.read(ApplicationWindows.POST_UTME_RESULTS, putme), "/post-utme/results"));
        out.put("now", OffsetDateTime.now());
        return ResponseEntity.ok().cacheControl(CacheControl.maxAge(60, TimeUnit.SECONDS).cachePublic()).body(out);
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
