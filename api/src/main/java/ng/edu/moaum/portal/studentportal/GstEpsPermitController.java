package ng.edu.moaum.portal.studentportal;

import java.util.Map;
import java.util.UUID;

import jakarta.validation.Valid;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;
import ng.edu.moaum.portal.shared.DomainRuleViolation;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * V492: the signed-in student's own GST & EPS examination permit. The student comes from the session token and the session is
 * the one the student's examinations stand in, never one named by the browser; only the semester is chosen (the open one by
 * default). Another student's permit cannot be asked for: there is no id to change.
 */
@RestController
@RequestMapping("/api/v1/me/gst-eps-permit")
@PreAuthorize("hasAuthority('OFFICE_student')")
class GstEpsPermitController {

    public record IssueIn(@Min(1) @Max(3) Integer semester, @NotBlank @Pattern(regexp = "VIEW|DOWNLOAD|PRINT") String act) {
    }

    private final StudentPortalService portal;
    private final GstEpsPermits permits;

    GstEpsPermitController(StudentPortalService portal, GstEpsPermits permits) {
        this.portal = portal;
        this.permits = permits;
    }

    /** whether the permit may be issued for the semester, why not, and the GST and EPS courses it carries */
    @GetMapping
    Map<String, Object> permit(Authentication auth, @RequestParam(required = false) Integer semester) {
        if (semester != null && (semester < 1 || semester > 3)) throw new DomainRuleViolation("GST_EPS_PERMIT_SEMESTER", "A permit is issued for semester 1, 2 or 3.");
        UUID id = UUID.fromString(auth.getName());
        String session = portal.examSession(id);
        Map<String, Object> out = permits.state(id, session, semester == null ? portal.openSemester(id, session) : semester);
        out.put("openSemester", portal.openSemester(id, session));
        return out;
    }

    /** the permit issued for viewing, downloading or printing, with its check code */
    @PostMapping("/issue")
    Map<String, Object> issue(Authentication auth, @Valid @RequestBody IssueIn body) {
        UUID id = UUID.fromString(auth.getName());
        String session = portal.examSession(id);
        return permits.issue(id, session, body.semester() == null ? portal.openSemester(id, session) : body.semester(), body.act());
    }
}
