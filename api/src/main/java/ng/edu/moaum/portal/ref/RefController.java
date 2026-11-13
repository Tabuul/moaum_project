package ng.edu.moaum.portal.ref;

import java.util.List;
import java.util.Map;

import org.springframework.jdbc.core.simple.JdbcClient;
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
    private final JdbcClient jdbc;

    RefController(RefRepository ref, ng.edu.moaum.portal.shared.OfficeScope scope, JdbcClient jdbc) {
        this.ref = ref;
        this.scope = scope;
        this.jdbc = jdbc;
    }

    /** the structure with the sessions that had a Summer Semester (V756) */
    public record StructureOut(List<Structure.College> colleges, List<Structure.Faculty> faculties, List<String> summerSessions) {
    }

    /** Colleges, faculties, departments and programmes — the scope bar's ladder. V756: and the sessions that had a Summer Semester
     *  (registration.summer_period), whose semester 3 is the Summer on an undergraduate screen; a CCE or postgraduate semester 3 in
     *  one of them is still the third semester */
    @GetMapping("/structure")
    StructureOut structure() {
        Structure s = ref.structure();
        return new StructureOut(s.colleges(), s.faculties(),
                jdbc.sql("SELECT session FROM registration.summer_period ORDER BY session").query(String.class).list());
    }

    /** the thirty-six states and the FCT, each with its local government areas (V273): the lists the forms choose from */
    @GetMapping("/states")
    List<Map<String, Object>> states() {
        return ref.states();
    }

    /** the countries, Nigeria first (V273) */
    @GetMapping("/countries")
    List<String> countries() {
        return ref.countries();
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
