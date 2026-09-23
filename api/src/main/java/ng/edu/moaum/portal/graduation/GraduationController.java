package ng.edu.moaum.portal.graduation;

import java.util.Map;

import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/v1/graduation")
class GraduationController {

    private static final String READERS =
            "hasAnyAuthority('OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar','OFFICE_dvc','OFFICE_vc','OFFICE_records',"
            + "'OFFICE_dean','OFFICE_hod','OFFICE_ict','OFFICE_admin','OFFICE_super')";
    private static final String OFFICE = "hasAnyAuthority('OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar','OFFICE_records')";

    private final GraduationService service;

    private final ng.edu.moaum.portal.shared.OfficeScope scope;

    GraduationController(GraduationService service, ng.edu.moaum.portal.shared.OfficeScope scope) {
        this.service = service;
        this.scope = scope;
    }

    @GetMapping("/sessions/{s}/{y}")
    @PreAuthorize(READERS)
    GraduationService.View view(@PathVariable String s, @PathVariable String y, @RequestParam(required = false) String fac,
                                @RequestParam(required = false) String dept, @RequestParam(required = false) String prog) {
        ng.edu.moaum.portal.shared.OfficeScope.Bound b = scope.bound(fac, dept, prog);   // the office's bound, whatever the parameters say
        return service.view(s + "/" + y, b.fac(), b.dept(), b.prog());
    }

    @PostMapping("/sessions/{s}/{y}/audit")
    @PreAuthorize(OFFICE)
    Map<String, Object> audit(@PathVariable String s, @PathVariable String y) {
        return service.audit(s + "/" + y);
    }

    @PostMapping("/sessions/{s}/{y}/approve")
    @PreAuthorize("hasAnyAuthority('OFFICE_registrar','OFFICE_dregistrar','OFFICE_academic')")
    Map<String, Object> approve(@PathVariable String s, @PathVariable String y, @RequestBody(required = false) Map<String, String> body) {
        return service.approve(s + "/" + y, body == null ? null : body.get("senateMinute"));
    }

    private static String blank(String v) {
        return v == null || v.isBlank() ? null : v;
    }
}
