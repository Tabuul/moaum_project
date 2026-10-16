package ng.edu.moaum.portal.studentportal;

import java.util.Map;
import java.util.UUID;

import ng.edu.moaum.portal.shared.DomainRuleViolation;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * V501: the signed-in student's own examination card — whether it may be issued for a semester and why not, with every course on
 * the approved registration (departmental, GST and EPS, carry-overs). The rule is the database's (registration.exam_card_state),
 * the same order as the GST & EPS permit's without the GST's own; the student comes from the token, never from the browser.
 */
@RestController
@RequestMapping("/api/v1/me/exam-card")
@PreAuthorize("hasAuthority('OFFICE_student')")
class ExamCardController {

    private final StudentPortalService portal;

    ExamCardController(StudentPortalService portal) {
        this.portal = portal;
    }

    @GetMapping
    Map<String, Object> card(Authentication auth, @RequestParam(required = false) String session, @RequestParam(required = false) Integer semester) {
        if (semester != null && (semester < 1 || semester > 3)) throw new DomainRuleViolation("EXAM_CARD_SEMESTER", "An examination card is issued for semester 1, 2 or 3.");
        if (session != null && !session.matches("^[0-9]{4}/[0-9]{4}$")) throw new DomainRuleViolation("EXAM_CARD_SESSION", "A session is named YYYY/YYYY.");
        UUID id = UUID.fromString(auth.getName());
        String s = session == null ? portal.examSession(id) : session;
        int sem = semester == null ? portal.openSemester(id, s) : semester;
        Map<String, Object> out = portal.examCard(id, s, sem);
        out.put("openSemester", portal.openSemester(id, s));
        return out;
    }
}
