package ng.edu.moaum.portal.registration;

import java.sql.Types;
import java.time.LocalDate;
import java.time.LocalTime;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import jakarta.validation.Valid;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * The department's registration desk (V027): the registrations students
 * submitted and who they are with, the attendance register marked over the
 * class list, and the slots the department gives an offering on the
 * timetable. Approval and return stay where they are (RegistrationController).
 */
@RestController
@RequestMapping("/api/v1/registration")
class DeskController {

    private static final String DEPARTMENT = "hasAnyAuthority('OFFICE_hod','OFFICE_lecturer','OFFICE_dean','OFFICE_facultyofficer','OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar','OFFICE_super')";

    public record Attendance(@NotNull LocalDate heldOn, @NotNull List<UUID> present) {
    }

    public record SlotIn(@Min(1) @Max(7) int weekday, @NotNull LocalTime startsAt, @NotNull LocalTime endsAt, @NotBlank @Size(max = 200) String venue, String kind) {
    }

    private final JdbcClient jdbc;
    private final ng.edu.moaum.portal.shared.OfficeScope scope;

    DeskController(JdbcClient jdbc, ng.edu.moaum.portal.shared.OfficeScope scope) {
        this.jdbc = jdbc;
        this.scope = scope;
    }

    /** the registrations students submitted, in a session and semester, for the department to approve or return */
    @GetMapping("/course-registrations")
    @PreAuthorize(DEPARTMENT)
    @Transactional(readOnly = true)
    List<Map<String, Object>> registrations(@RequestParam String session, @RequestParam(defaultValue = "0") int semester,
                                            @RequestParam(required = false) String deptParam, @RequestParam(defaultValue = "SUBMITTED") String status) {
        // a Head of Department (or lecturer) is confined to their own department server-side; a wider office
        // keeps the requested filter. This is the scoping, not the frontend's dept param, so it cannot be widened.
        String dept = scope.scopedDept(deptParam);
        // semester 0 means every semester — the approvals desk shows all pending registrations, so its list
        // matches the dashboard's session-wide count (a submitted second-semester registration is not hidden)
        return jdbc.sql("""
                SELECT r.id, r.status, r.level, r.semester, r.submitted_at, r.approved_at, registration.units_of(r.id) AS units,
                       s.matric_no, s.admission_no, s.surname, s.other_names, p.name AS programme, p.dept_code, d.name AS dept_name,
                       (SELECT string_agg(c.code || ' (' || e.units || CASE WHEN e.entry_type = 'CARRYOVER' THEN ', carryover' ELSE '' END || ')', ', ' ORDER BY c.code)
                          FROM registration.entry e JOIN catalogue.offering o ON o.id = e.offering_id JOIN catalogue.course c ON c.code = o.course_code
                         WHERE e.registration_id = r.id) AS courses,
                       coalesce(registration.siwes_units(s.programme_code, r.level, r.semester)::text,
                                (SELECT min_units || '–' || max_units FROM policy.level_limit l WHERE l.level = r.level)) AS range
                  FROM registration.course_registration r
                  JOIN people.student s ON s.id = r.student_id
                  JOIN ref.programme p ON p.code = s.programme_code
                  JOIN ref.department d ON d.code = p.dept_code
                 WHERE r.session = :s AND (:sem = 0 OR r.semester = :sem)
                   AND (:d::text IS NULL OR p.dept_code = :d)
                   AND CASE :st WHEN 'ALL' THEN true ELSE r.status = :st END
                 ORDER BY r.semester, r.submitted_at NULLS LAST, s.surname
                """).param("s", session).param("sem", semester).param("d", dept, Types.VARCHAR).param("st", status.toUpperCase()).query().listOfRows();
    }

    /** the register of one class on one day, over the class list; marking again on the same day replaces the day's register */
    @PostMapping("/offerings/{offeringId}/attendance")
    @PreAuthorize("hasAnyAuthority('OFFICE_lecturer','OFFICE_hod','OFFICE_dean','OFFICE_super')")
    @Transactional
    Map<String, Object> attendance(@PathVariable UUID offeringId, @Valid @RequestBody Attendance body) {
        int marked = jdbc.sql("SELECT registration.mark_attendance(:o, :d, :p)").param("o", offeringId).param("d", body.heldOn())
                .param("p", body.present().toArray(UUID[]::new)).query(Integer.class).single();
        return Map.of("offeringId", offeringId, "heldOn", body.heldOn(), "marked", marked, "present", body.present().size());
    }

    @GetMapping("/offerings/{offeringId}/attendance")
    @PreAuthorize(DEPARTMENT)
    @Transactional(readOnly = true)
    Map<String, Object> attendanceOf(@PathVariable UUID offeringId) {
        List<Map<String, Object>> days = jdbc.sql("""
                SELECT held_on, count(*) AS on_roll, count(*) FILTER (WHERE present) AS present FROM registration.attendance
                 WHERE offering_id = :o GROUP BY held_on ORDER BY held_on DESC
                """).param("o", offeringId).query().listOfRows();
        List<Map<String, Object>> students = jdbc.sql("""
                SELECT a.student_id, s.matric_no, s.surname, s.other_names, count(*) AS held, count(*) FILTER (WHERE a.present) AS attended,
                       round(100.0 * count(*) FILTER (WHERE a.present) / count(*))::int AS rate
                  FROM registration.attendance a JOIN people.student s ON s.id = a.student_id
                 WHERE a.offering_id = :o GROUP BY a.student_id, s.matric_no, s.surname, s.other_names ORDER BY s.surname
                """).param("o", offeringId).query().listOfRows();
        return Map.of("offeringId", offeringId, "days", days, "students", students);
    }

    /* ── the timetable slots ── */

    @GetMapping("/offerings/{offeringId}/slots")
    @PreAuthorize(DEPARTMENT)
    List<Map<String, Object>> slots(@PathVariable UUID offeringId) {
        return jdbc.sql("SELECT id, weekday, starts_at, ends_at, venue, kind FROM catalogue.class_slot WHERE offering_id = :o AND ended_at IS NULL ORDER BY weekday, starts_at")
                .param("o", offeringId).query().listOfRows();
    }

    @PostMapping("/offerings/{offeringId}/slots")
    @PreAuthorize("hasAnyAuthority('OFFICE_hod','OFFICE_lecturer','OFFICE_dean','OFFICE_super')")
    @Transactional
    List<Map<String, Object>> addSlot(@PathVariable UUID offeringId, @Valid @RequestBody SlotIn body) {
        String kind = body.kind() == null || body.kind().isBlank() ? "LECTURE" : body.kind().trim().toUpperCase();
        jdbc.sql("INSERT INTO catalogue.class_slot (offering_id, weekday, starts_at, ends_at, venue, kind) VALUES (:o, :w, :s, :e, :v, :k)")
                .param("o", offeringId).param("w", body.weekday()).param("s", body.startsAt()).param("e", body.endsAt()).param("v", body.venue().trim()).param("k", kind).update();
        return slots(offeringId);
    }

    @PostMapping("/offerings/{offeringId}/slots/{slotId}/end")
    @PreAuthorize("hasAnyAuthority('OFFICE_hod','OFFICE_lecturer','OFFICE_dean','OFFICE_super')")
    @Transactional
    List<Map<String, Object>> endSlot(@PathVariable UUID offeringId, @PathVariable UUID slotId) {
        jdbc.sql("UPDATE catalogue.class_slot SET ended_at = now() WHERE id = :id AND offering_id = :o AND ended_at IS NULL").param("id", slotId).param("o", offeringId).update();
        return slots(offeringId);
    }

    /** the paper's slot on the examination timetable, read beside the class list */
    @GetMapping("/offerings/{offeringId}/exam-slot")
    @PreAuthorize(DEPARTMENT)
    Map<String, Object> examSlot(@PathVariable UUID offeringId) {
        return jdbc.sql("SELECT held_on, starts_at, ends_at, venue FROM assessment.exam_timetable WHERE offering_id = :o").param("o", offeringId)
                .query().listOfRows().stream().findFirst().orElse(Map.of());
    }
}
