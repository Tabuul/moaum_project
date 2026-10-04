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
            + "'OFFICE_library','OFFICE_services','OFFICE_housing')";

    private final ClearanceService service;
    private final ng.edu.moaum.portal.shared.OfficeScope scope;
    private final org.springframework.jdbc.core.simple.JdbcClient jdbc;

    ClearanceController(ClearanceService service, ng.edu.moaum.portal.shared.OfficeScope scope, org.springframework.jdbc.core.simple.JdbcClient jdbc) {
        this.service = service;
        this.scope = scope;
        this.jdbc = jdbc;
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

    /** the held candidates told what holds them and by which unit (V286): one notice each, by email and SMS, on the notice queue */
    @PostMapping("/notify-held")
    @PreAuthorize(SIGNERS)
    @org.springframework.transaction.annotation.Transactional
    ResponseEntity<Map<String, Object>> notifyHeld(@RequestBody(required = false) Map<String, Object> body) {
        Object ids = body == null ? null : body.get("students");
        String purpose = body == null || body.get("purpose") == null ? "CONVOCATION" : String.valueOf(body.get("purpose"));
        int sent = 0, none = 0;
        if (ids instanceof List<?> l) {
            for (Object o : l) {
                UUID id;
                try { id = UUID.fromString(String.valueOf(o)); } catch (IllegalArgumentException e) { continue; }
                List<Clearance.Position> holds = service.position(id, purpose).stream().filter(p -> "HELD".equalsIgnoreCase(p.state())).toList();
                if (holds.isEmpty()) { none++; continue; }
                StringBuilder lines = new StringBuilder();
                for (Clearance.Position p : holds) lines.append("\n- ").append(p.label()).append(": ").append(p.item() == null ? "outstanding" : p.item()).append(p.note() == null ? "" : " (" + p.note() + ")");
                String subject = "Clearance held: " + holds.size() + " unit" + (holds.size() == 1 ? "" : "s") + " outstanding";
                String text = "Your clearance for " + purpose.toLowerCase() + " is held by the following unit" + (holds.size() == 1 ? "" : "s") + ":" + lines
                        + "\n\nSettle each with the unit named; the hold is lifted on the portal the moment the unit clears you.\n\nOffice of the Registrar, " + ng.edu.moaum.portal.platform.Branding.name() + "";
                int q = jdbc.sql("""
                        SELECT count(*) FROM (
                            SELECT platform.queue_notice('EMAIL', r.email, :s, :b, 'student', :id) AS n FROM people.student_reach(:id) r
                            UNION ALL SELECT platform.queue_notice('SMS', r.phone, :s, :sms, 'student', :id) FROM people.student_reach(:id) r) x WHERE x.n IS NOT NULL
                        """).param("s", subject).param("b", text).param("sms", "MOAUM: your clearance is held by " + holds.size() + " unit(s). See the portal for what is outstanding.")
                        .param("id", id).query(Integer.class).single();
                if (q > 0) sent++; else none++;
            }
        }
        return ResponseEntity.ok(Map.of("notified", sent, "unreached", none, "note", sent == 0 ? "Nobody could be reached: no hold stands, or no contact is on the record." : "Each held candidate was told what holds them, by email and SMS where the record has them."));
    }

    private static String purpose(Map<String, String> body) {
        String p = body == null ? null : body.get("purpose");
        return p == null || p.isBlank() ? "CONVOCATION" : p;
    }

    private static String blank(String s) {
        return s == null || s.isBlank() ? null : s;
    }
}
