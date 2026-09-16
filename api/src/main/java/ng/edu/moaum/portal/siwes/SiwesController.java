package ng.edu.moaum.portal.siwes;

import java.util.List;
import java.util.Map;
import java.util.UUID;

import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

import ng.edu.moaum.portal.shared.DomainRuleViolation;
import ng.edu.moaum.portal.shared.OfficeScope;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.Authentication;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * SIWES / industrial training: a supervisor is assigned to each student, and the supervisor records
 * that student's mark. The Head of Department and the SIWES Coordinator assign supervisors; the
 * supervisor enters one mark out of 100, on the offering's ordinary score sheet, through the results
 * pipeline (V155/V156).
 */
@RestController
@RequestMapping("/api/v1/siwes")
class SiwesController {

    /** the offices that assign supervisors: the department's own, plus the Registry */
    private static final String ASSIGNERS =
            "hasAnyAuthority('OFFICE_hod','OFFICE_siwes','OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar','OFFICE_admin','OFFICE_super')";

    private final JdbcClient jdbc;
    private final OfficeScope scope;

    SiwesController(JdbcClient jdbc, OfficeScope scope) {
        this.jdbc = jdbc;
        this.scope = scope;
    }

    public record AssignIn(@NotNull UUID supervisor) {
    }

    /** the supervisor's mark, out of 40 (the assessment of the student) */
    public record ScoreIn(@NotNull UUID offering, @NotNull @Min(0) @Max(40) Integer mark, @Size(max = 400) String reason) {
    }

    /** the coordinator's mark, out of 60 (the report of the practicals done during SIWES) */
    public record PracticalIn(@NotNull @Min(0) @Max(60) Integer mark, @Size(max = 400) String reason) {
    }

    private UUID actor(Authentication auth) {
        return UUID.fromString(auth.getName());
    }

    /* ── the coordinator / HOD side ── */

    /** the SIWES offerings in scope (a department office sees only its own department) */
    @GetMapping("/offerings")
    @PreAuthorize(ASSIGNERS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> offerings(@RequestParam(required = false) String dept, @RequestParam String session,
                                        @RequestParam(defaultValue = "2") int semester) {
        String d = scope.scopedDept(dept);                  // a department office is bound to its department
        return jdbc.sql("""
                SELECT o.id, o.course_code, c.title, c.units, c.dept_code, dp.name AS dept_name, o.session, o.semester,
                       sh.id AS sheet_id, sh.stage AS sheet_stage,
                       (SELECT count(*) FROM registration.entry e JOIN registration.course_registration r ON r.id = e.registration_id
                         WHERE e.offering_id = o.id AND r.status = 'APPROVED') AS students,
                       (SELECT count(*) FROM assessment.siwes_supervisor s WHERE s.offering_id = o.id) AS assigned
                  FROM catalogue.offering o
                  JOIN catalogue.course c ON c.code = o.course_code AND c.industrial_training
                  JOIN ref.department dp ON dp.code = c.dept_code
                  LEFT JOIN assessment.score_sheet sh ON sh.offering_id = o.id
                 WHERE o.session = :session AND o.semester = :semester AND (:dept::text IS NULL OR c.dept_code = :dept)
                 ORDER BY dp.name, o.course_code
                """).param("session", session).param("semester", semester).param("dept", d).query().listOfRows();
    }

    /** the students on a SIWES offering, each with their supervisor and current mark */
    @GetMapping("/offerings/{offering}/students")
    @PreAuthorize(ASSIGNERS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> students(@PathVariable UUID offering) {
        return jdbc.sql("""
                SELECT st.id AS student_id, coalesce(st.matric_no, st.admission_no) AS number,
                       st.surname, st.other_names, pr.name AS programme, st.current_level AS level,
                       sup.supervisor_id,
                       CASE WHEN sp.id IS NULL THEN NULL ELSE sp.surname || ', ' || sp.given_names END AS supervisor,
                       latest.ca AS supervisor_mark, latest.exam AS practical_mark,
                       CASE WHEN latest.ca IS NOT NULL AND latest.exam IS NOT NULL THEN latest.ca + latest.exam END AS total,
                       latest.outcome
                  FROM registration.entry e
                  JOIN registration.course_registration r ON r.id = e.registration_id AND r.status = 'APPROVED'
                  JOIN people.student st ON st.id = r.student_id
                  LEFT JOIN ref.programme pr ON pr.code = st.programme_code
                  LEFT JOIN assessment.siwes_supervisor sup ON sup.offering_id = e.offering_id AND sup.student_id = st.id
                  LEFT JOIN iam.person sp ON sp.id = sup.supervisor_id
                  LEFT JOIN LATERAL (
                        SELECT sc.ca, sc.exam, sc.outcome FROM assessment.score sc
                          JOIN assessment.score_sheet sh ON sh.id = sc.sheet_id
                         WHERE sh.offering_id = :off AND sc.student_id = st.id
                         ORDER BY sc.version DESC LIMIT 1) latest ON true
                 WHERE e.offering_id = :off
                 ORDER BY st.surname, st.other_names
                """).param("off", offering).query().listOfRows();
    }

    /** the department's lecturers, who may be assigned as supervisors */
    @GetMapping("/offerings/{offering}/supervisors")
    @PreAuthorize(ASSIGNERS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> supervisorPool(@PathVariable UUID offering) {
        return jdbc.sql("""
                SELECT DISTINCT p.id, p.surname || ', ' || p.given_names AS name, p.staff_number
                  FROM catalogue.offering o
                  JOIN catalogue.course c ON c.code = o.course_code
                  JOIN iam.office_assignment a ON a.scope_id = c.dept_code
                  JOIN iam.person p ON p.id = a.person_id AND p.ended_on IS NULL
                 WHERE o.id = :off
                   AND a.office_code IN ('lecturer', 'hod') AND a.scope_kind = 'department'
                   AND a.valid_from <= current_date AND (a.valid_to IS NULL OR a.valid_to >= current_date)
                 ORDER BY name
                """).param("off", offering).query().listOfRows();
    }

    /** assign (or move) a supervisor to a student on a SIWES offering */
    @PutMapping("/offerings/{offering}/students/{student}/supervisor")
    @PreAuthorize(ASSIGNERS)
    @Transactional
    Map<String, Object> assign(@PathVariable UUID offering, @PathVariable UUID student, @RequestBody AssignIn body) {
        jdbc.sql("SELECT assessment.assign_siwes_supervisor(:o, :s, :sup)")
                .param("o", offering).param("s", student).param("sup", body.supervisor()).query().singleRow();
        return Map.of("offering", offering, "student", student, "supervisor", body.supervisor(), "assigned", true);
    }

    /* ── the supervisor side ── */

    /** the acting supervisor's SIWES students, across offerings, with the sheet's stage and current mark */
    @GetMapping("/mine")
    @PreAuthorize("isAuthenticated()")
    @Transactional(readOnly = true)
    List<Map<String, Object>> mine(Authentication auth) {
        return jdbc.sql("""
                SELECT o.id AS offering_id, o.course_code, c.title, o.session, o.semester,
                       st.id AS student_id, coalesce(st.matric_no, st.admission_no) AS number,
                       st.surname, st.other_names, pr.name AS programme,
                       sh.id AS sheet_id, sh.stage AS sheet_stage,
                       latest.ca AS supervisor_mark, latest.exam AS practical_mark,
                       CASE WHEN latest.ca IS NOT NULL AND latest.exam IS NOT NULL THEN latest.ca + latest.exam END AS total
                  FROM assessment.siwes_supervisor sup
                  JOIN catalogue.offering o ON o.id = sup.offering_id
                  JOIN catalogue.course c ON c.code = o.course_code
                  JOIN people.student st ON st.id = sup.student_id
                  LEFT JOIN ref.programme pr ON pr.code = st.programme_code
                  LEFT JOIN assessment.score_sheet sh ON sh.offering_id = o.id
                  LEFT JOIN LATERAL (
                        SELECT sc.ca, sc.exam FROM assessment.score sc
                         WHERE sc.sheet_id = sh.id AND sc.student_id = st.id
                         ORDER BY sc.version DESC LIMIT 1) latest ON true
                 WHERE sup.supervisor_id = :me
                 ORDER BY o.session DESC, o.course_code, st.surname
                """).param("me", actor(auth)).query().listOfRows();
    }

    /** the acting supervisor records a student's assessment mark, out of 40 (the ca part) */
    @PutMapping("/mine/students/{student}/score")
    @PreAuthorize("isAuthenticated()")
    @Transactional
    Map<String, Object> score(@PathVariable UUID student, @RequestBody ScoreIn body, Authentication auth) {
        boolean mine = Boolean.TRUE.equals(jdbc.sql("""
                SELECT EXISTS (SELECT 1 FROM assessment.siwes_supervisor
                                WHERE offering_id = :o AND student_id = :s AND supervisor_id = :me)
                """).param("o", body.offering()).param("s", student).param("me", actor(auth)).query(Boolean.class).single());
        if (!mine) {
            throw new DomainRuleViolation("SIWES_NOT_YOUR_STUDENT", "This student is not assigned to you for SIWES.",
                    new DomainRuleViolation.Remedy("You record the mark only for the students assigned to you.", "SIWES supervisor"));
        }
        return record(body.offering(), student, true, body.mark(), body.reason(), "SIWES supervisor");
    }

    /** the coordinator records a student's practical report mark, out of 60 (the exam part) */
    @PutMapping("/offerings/{offering}/students/{student}/practical")
    @PreAuthorize(ASSIGNERS)
    @Transactional
    Map<String, Object> practical(@PathVariable UUID offering, @PathVariable UUID student, @RequestBody PracticalIn body) {
        return record(offering, student, false, body.mark(), body.reason(), "SIWES Coordinator");
    }

    /**
     * Write one part of a SIWES mark onto the offering's score sheet. The supervisor sets the ca
     * (/40) and the coordinator the exam (/60); the other part is carried forward. Only when both
     * parts are present is the row GRADED (total = ca + exam); until then it stands as INCOMPLETE.
     * A reason is required only when the writer changes a part they had already entered.
     */
    private Map<String, Object> record(UUID offering, UUID student, boolean supervisorPart, int mark, String reason, String office) {
        Map<String, Object> sheet = jdbc.sql("SELECT id, stage FROM assessment.score_sheet WHERE offering_id = :o")
                .param("o", offering).query().listOfRows().stream().findFirst().orElse(null);
        if (sheet == null) {
            throw new DomainRuleViolation("SIWES_NO_SHEET", "The SIWES score sheet is not open yet.",
                    new DomainRuleViolation.Remedy("The coordinator opens the examination session for the SIWES course first.", "SIWES Coordinator"));
        }
        if (!"ENTRY".equals(sheet.get("stage"))) {
            throw new DomainRuleViolation("SIWES_SHEET_NOT_AT_ENTRY",
                    "The sheet is at " + String.valueOf(sheet.get("stage")).toLowerCase().replace('_', ' ') + "; a mark changes by amendment with a reason.",
                    new DomainRuleViolation.Remedy("Ask the desk holding the sheet to return it for a correction.", "SIWES Coordinator"));
        }
        UUID sheetId = (UUID) sheet.get("id");
        Map<String, Object> was = jdbc.sql("""
                SELECT version, ca, exam FROM assessment.score
                 WHERE sheet_id = :sh AND student_id = :s ORDER BY version DESC LIMIT 1
                """).param("sh", sheetId).param("s", student).query().listOfRows().stream().findFirst().orElse(null);
        Integer curCa = was == null ? null : (Integer) was.get("ca");
        Integer curExam = was == null ? null : (Integer) was.get("exam");
        Integer ca = supervisorPart ? mark : curCa;
        Integer exam = supervisorPart ? curExam : mark;
        if (java.util.Objects.equals(ca, curCa) && java.util.Objects.equals(exam, curExam)) {
            return Map.of("student", student, "written", false);
        }
        Integer priorOwn = supervisorPart ? curCa : curExam;
        if (priorOwn != null && (reason == null || reason.isBlank())) {
            throw new DomainRuleViolation("SIWES_AMENDMENT_SAYS_WHY", "A changed mark carries its reason.",
                    new DomainRuleViolation.Remedy("Say why the mark changes; the old value stays on the record.", office));
        }
        int version = was == null ? 1 : ((Number) was.get("version")).intValue() + 1;
        String outcome = ca != null && exam != null ? "GRADED" : "INCOMPLETE";
        jdbc.sql("""
                INSERT INTO assessment.score (sheet_id, student_id, version, ca, exam, outcome, reason)
                VALUES (:sh, :s, :v, :ca, :exam, :outcome, :reason)
                """).param("sh", sheetId).param("s", student).param("v", version)
                .param("ca", ca, java.sql.Types.INTEGER).param("exam", exam, java.sql.Types.INTEGER)
                .param("outcome", outcome)
                .param("reason", reason == null || reason.isBlank() ? null : reason.trim(), java.sql.Types.VARCHAR)
                .update();
        return Map.of("student", student, "outcome", outcome, "written", true);
    }
}
