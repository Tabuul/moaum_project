package ng.edu.moaum.portal.clearance;

import java.util.List;
import java.util.Map;
import java.util.UUID;

import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/v1/clearance")
class ClearanceController {

    private static final String READERS =
            "hasAnyAuthority('OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar','OFFICE_dvc','OFFICE_vc','OFFICE_records',"
            + "'OFFICE_dean','OFFICE_hod','OFFICE_exams','OFFICE_facultyexams','OFFICE_facultyofficer','OFFICE_bursar',"
            + "'OFFICE_library','OFFICE_services','OFFICE_ict','OFFICE_admin','OFFICE_super')";
    private static final String SIGNERS =
            "hasAnyAuthority('OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar','OFFICE_dean','OFFICE_hod','OFFICE_bursar',"
            + "'OFFICE_library','OFFICE_services')";

    private final ClearanceService service;
    private final ng.edu.moaum.portal.shared.OfficeScope scope;

    ClearanceController(ClearanceService service, ng.edu.moaum.portal.shared.OfficeScope scope) {
        this.service = service;
        this.scope = scope;
    }

    @GetMapping
    @PreAuthorize(READERS)
    Clearance.Listing listing(@RequestParam(defaultValue = "CONVOCATION") String purpose,
                              @RequestParam(required = false) String fac, @RequestParam(required = false) String dept,
                              @RequestParam(required = false) String prog, @RequestParam(required = false) Integer level,
                              @RequestParam(required = false) String session) {
        ng.edu.moaum.portal.shared.OfficeScope.Bound b = scope.bound(fac, dept, prog);   // the office's bound, whatever the parameters say
        return service.listing(purpose, b.fac(), b.dept(), b.prog(), level, blank(session));
    }

    @GetMapping("/units")
    @PreAuthorize(READERS)
    List<Clearance.Unit> units() {
        return service.units();
    }

    @GetMapping("/students/{id}")
    @PreAuthorize(READERS)
    List<Clearance.Position> position(@PathVariable UUID id, @RequestParam(defaultValue = "CONVOCATION") String purpose) {
        return service.position(id, purpose);
    }

    @PostMapping("/students/{id}/{unit}/clear")
    @PreAuthorize(SIGNERS)
    Map<String, Object> clear(@PathVariable UUID id, @PathVariable String unit, @RequestBody(required = false) Map<String, String> body) {
        return service.clear(id, unit, purpose(body), body == null ? null : body.get("note"));
    }

    @PostMapping("/students/{id}/{unit}/hold")
    @PreAuthorize(SIGNERS)
    Map<String, Object> hold(@PathVariable UUID id, @PathVariable String unit, @RequestBody(required = false) Map<String, String> body) {
        return service.hold(id, unit, purpose(body), body == null ? null : body.get("item"), body == null ? null : body.get("note"));
    }

    /** No notification module yet: the notice is counted, not sent, and the answer says so. */
    @PostMapping("/notify-held")
    @PreAuthorize(SIGNERS)
    ResponseEntity<Map<String, Object>> notifyHeld(@RequestBody(required = false) Map<String, Object> body) {
        Object ids = body == null ? null : body.get("students");
        int n = ids instanceof List<?> l ? l.size() : 0;
        return ResponseEntity.status(HttpStatus.ACCEPTED).body(Map.of("wouldNotify", n,
                "note", "The notification module is not on the portal yet; nothing was sent."));
    }

    private static String purpose(Map<String, String> body) {
        String p = body == null ? null : body.get("purpose");
        return p == null || p.isBlank() ? "CONVOCATION" : p;
    }

    private static String blank(String s) {
        return s == null || s.isBlank() ? null : s;
    }
}
