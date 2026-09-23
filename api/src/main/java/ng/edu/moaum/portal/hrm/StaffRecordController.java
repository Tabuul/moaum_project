package ng.edu.moaum.portal.hrm;

import java.time.Duration;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import org.springframework.http.CacheControl;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.server.ResponseStatusException;

/**
 * One member of staff, whole, for the record pop-up an office opens from a list: the person and their
 * contact, what HR holds (rank, step, home department, first appointment; the employment's grade,
 * category and status — not the pay), the offices they hold, their academic profile as they keep it
 * (research interests, publications, grants and the rest), the courses they teach this session, and
 * their leave. Read by the offices that read the staff register.
 */
@RestController
@RequestMapping("/api/v1/hr/staff")
class StaffRecordController {

    private static final String READERS =
            "hasAnyAuthority('OFFICE_vc','OFFICE_dvc','OFFICE_registrar','OFFICE_dregistrar','OFFICE_academic','OFFICE_records',"
            + "'OFFICE_bursar','OFFICE_audit','OFFICE_deputyaudit','OFFICE_hrm','OFFICE_ict','OFFICE_admin','OFFICE_super',"
            + "'OFFICE_pgschool','OFFICE_pgsecretary','OFFICE_dean','OFFICE_facultyofficer','OFFICE_hod')";

    private final JdbcClient jdbc;

    StaffRecordController(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    @GetMapping("/{id}")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> one(@PathVariable UUID id) {
        Map<String, Object> person = jdbc.sql("""
                SELECT pe.id, pe.staff_number, pe.surname, pe.given_names, pe.email, pe.phone, pe.ended_on, pe.ended_reason,
                       sr.pno, sr.sex, sr.present_rank AS rank, sr.conuass_step, sr.date_first_appointment,
                       sr.home_department AS department_code, dp.name AS department, f.code AS faculty_code, f.name AS faculty,
                       e.grade, e.step, e.category, e.appointment_date, e.status AS employment_status, e.ended_on AS employment_ended_on,
                       CASE WHEN pe.ended_on IS NOT NULL THEN 'ENDED' ELSE coalesce(e.status, 'ACTIVE') END AS status,
                       EXISTS (SELECT 1 FROM hrm.staff_photo ph WHERE ph.person_id = pe.id) AS has_photo,
                       EXISTS (SELECT 1 FROM iam.credential c WHERE c.person_id = pe.id) AS has_account
                  FROM iam.person pe
                  LEFT JOIN hrm.staff_record sr ON sr.person_id = pe.id
                  LEFT JOIN hrm.employment e ON e.person_id = pe.id AND e.status <> 'ENDED'
                  LEFT JOIN ref.department dp ON dp.code = sr.home_department
                  LEFT JOIN ref.faculty f ON f.code = dp.faculty_code
                 WHERE pe.id = :id
                """).param("id", id).query().listOfRows().stream().findFirst()
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "No such member of staff"));

        List<Map<String, Object>> offices = jdbc.sql("""
                SELECT a.office_code, o.label AS office, a.scope_kind, a.scope_id, a.instrument, a.valid_from, a.valid_to,
                       (a.valid_from <= current_date AND (a.valid_to IS NULL OR a.valid_to >= current_date)) AS live,
                       CASE a.scope_kind
                         WHEN 'faculty' THEN (SELECT name FROM ref.faculty WHERE code = a.scope_id)
                         WHEN 'department' THEN (SELECT name FROM ref.department WHERE code = a.scope_id)
                         ELSE NULL END AS scope_name
                  FROM iam.office_assignment a JOIN ref.office o ON o.code = a.office_code
                 WHERE a.person_id = :id
                 ORDER BY live DESC, a.valid_from DESC
                """).param("id", id).query().listOfRows();

        Map<String, Object> profile = jdbc.sql("""
                SELECT sp.email, sp.phone, sp.department, sp.faculty, sp.responsibility, sp.scholar_url, sp.orcid, sp.research_interests,
                       sp.masters_graduated, sp.phd_graduated,
                       sp.publications::text AS publications, sp.grants::text AS grants, sp.collaborations::text AS collaborations,
                       sp.conferences::text AS conferences, sp.assignments::text AS assignments, sp.innovations::text AS innovations,
                       sp.patents::text AS patents, sp.achievements::text AS achievements, sp.contributions::text AS contributions,
                       sp.updated_at
                  FROM hrm.staff_profile sp WHERE sp.person_id = :id
                """).param("id", id).query().listOfRows().stream().findFirst().orElse(null);

        List<Map<String, Object>> teaching = jdbc.sql("""
                SELECT o.session, o.semester, o.course_code, c.title, c.units,
                       CASE WHEN o.lecturer_id = :id THEN 'Lecturer' ELSE 'Co-lecturer' END AS role,
                       (SELECT count(*) FROM registration.entry en JOIN registration.course_registration r ON r.id = en.registration_id
                         WHERE en.offering_id = o.id AND en.status IN ('REGISTERED','APPROVED') AND r.status IN ('APPROVED','LOCKED')) AS students
                  FROM catalogue.offering o JOIN catalogue.course c ON c.code = o.course_code
                 WHERE o.lecturer_id = :id
                    OR EXISTS (SELECT 1 FROM catalogue.offering_teacher t WHERE t.offering_id = o.id AND t.lecturer_id = :id)
                 ORDER BY o.session DESC, o.semester DESC, o.course_code
                 LIMIT 40
                """).param("id", id).query().listOfRows();

        List<Map<String, Object>> leave = jdbc.sql("""
                SELECT l.leave_type, t.name AS leave_name, l.from_date, l.to_date, l.days, l.state, l.requested_at, l.decided_at
                  FROM hrm.leave_request l LEFT JOIN hrm.leave_type t ON t.code = l.leave_type
                 WHERE l.person_id = :id ORDER BY l.from_date DESC LIMIT 20
                """).param("id", id).query().listOfRows();

        Map<String, Object> out = new LinkedHashMap<>();
        out.put("person", person);
        out.put("offices", offices);
        out.put("profile", profile);
        out.put("teaching", teaching);
        out.put("leave", leave);
        return out;
    }

    /** the photograph HR holds for the person (JPEG or PNG), else 404 */
    @GetMapping("/{id}/photo")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    ResponseEntity<byte[]> photo(@PathVariable UUID id) {
        return jdbc.sql("SELECT content_type, content FROM hrm.staff_photo WHERE person_id = :id").param("id", id)
                .query().listOfRows().stream().findFirst()
                .map(r -> ResponseEntity.ok()
                        .contentType(MediaType.parseMediaType(String.valueOf(r.get("content_type"))))
                        .cacheControl(CacheControl.maxAge(Duration.ofMinutes(10)).cachePrivate())
                        .body((byte[]) r.get("content")))
                .orElseGet(() -> ResponseEntity.notFound().build());
    }
}
