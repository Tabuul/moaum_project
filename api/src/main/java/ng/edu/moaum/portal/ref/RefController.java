package ng.edu.moaum.portal.ref;

import java.util.List;

import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/** The University's structure and calendar, readable by every office that signs in. */
@RestController
@RequestMapping("/api/v1/ref")
@PreAuthorize("isAuthenticated()")
class RefController {

    private final RefRepository ref;
    private final ng.edu.moaum.portal.shared.OfficeScope scope;

    RefController(RefRepository ref, ng.edu.moaum.portal.shared.OfficeScope scope) {
        this.ref = ref;
        this.scope = scope;
    }

    /** Colleges, faculties, departments and programmes — the scope bar's ladder. */
    @GetMapping("/structure")
    Structure structure() {
        return ref.structure();
    }

    @GetMapping("/sessions")
    List<Session> sessions() {
        return ref.sessions();
    }

    @GetMapping("/courses")
    List<Course> courses(@RequestParam(required = false) String dept,
                         @RequestParam(required = false) Integer semester,
                         @RequestParam(required = false) Integer level) {
        return ref.courses(scope.deptWithin(dept), semester, level);   // a department office reads its own courses only
    }
}
