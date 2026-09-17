package ng.edu.moaum.portal.lms;

import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import ng.edu.moaum.portal.shared.AuditContextHolder;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * What a lecturer teaches this session — the offerings the department allocated
 * to them (as lead, co-lecturer or second examiner), each with its class slots,
 * so there is one place that answers "my allocation" and "my teaching timetable".
 * Read-only.
 */
@RestController
@RequestMapping("/api/v1/me")
class MeTeachingController {

    private final JdbcClient jdbc;

    MeTeachingController(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    @GetMapping("/teaching")
    @PreAuthorize("isAuthenticated()")
    @Transactional(readOnly = true)
    Map<String, Object> teaching(@RequestParam(required = false) String session) {
        UUID me = AuditContextHolder.required().actorId();
        String s = session != null && session.matches("\\d{4}/\\d{4}") ? session
                : jdbc.sql("SELECT name FROM policy.academic_session WHERE state = 'CURRENT'").query(String.class).optional().orElse("2026/2027");

        List<Map<String, Object>> offerings = jdbc.sql("""
                SELECT o.id, c.code, c.title, c.units, c.level, o.semester,
                       CASE WHEN o.lecturer_id = :me THEN 'Lecturer'
                            WHEN o.second_examiner_id = :me THEN 'Second examiner'
                            ELSE 'Co-lecturer' END AS role,
                       d.name AS dept_name,
                       (SELECT count(*) FROM registration.entry e
                          JOIN registration.course_registration r ON r.id = e.registration_id
                         WHERE e.offering_id = o.id AND e.status IN ('REGISTERED', 'APPROVED')
                           AND r.status IN ('APPROVED', 'LOCKED')) AS roll
                  FROM catalogue.offering o
                  JOIN catalogue.course c ON c.code = o.course_code
                  JOIN ref.department d ON d.code = c.dept_code
                 WHERE o.session = :s
                   AND (o.lecturer_id = :me OR o.second_examiner_id = :me
                        OR EXISTS (SELECT 1 FROM catalogue.offering_teacher t WHERE t.offering_id = o.id AND t.lecturer_id = :me))
                 ORDER BY o.semester, c.level, c.code
                """).param("me", me).param("s", s).query().listOfRows();

        for (Map<String, Object> o : offerings) {
            List<Map<String, Object>> slots = jdbc.sql("""
                    SELECT weekday, starts_at, ends_at, venue, kind
                      FROM catalogue.class_slot WHERE offering_id = :o AND ended_at IS NULL
                     ORDER BY weekday, starts_at
                    """).param("o", o.get("id")).query().listOfRows();
            o.put("slots", slots);
        }

        Map<String, Object> out = new LinkedHashMap<>();
        out.put("session", s);
        out.put("offerings", offerings);
        return out;
    }
}
