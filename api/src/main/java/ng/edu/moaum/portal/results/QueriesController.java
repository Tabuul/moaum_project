package ng.edu.moaum.portal.results;

import java.sql.Types;
import java.time.LocalDate;
import java.time.LocalTime;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

import ng.edu.moaum.portal.shared.DomainRuleViolation;

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
 * The department's desk for result queries (V027): what students said about
 * one mark in one course, routed here because the department owns the
 * course, answered on the record. And the Examinations Office's timetable
 * for an offering's paper, which the docket carries.
 */
@RestController
@RequestMapping("/api/v1/results")
class QueriesController {

    private static final String DEPARTMENT = "hasAnyAuthority('OFFICE_hod','OFFICE_lecturer','OFFICE_exams','OFFICE_dean','OFFICE_records','OFFICE_academic','OFFICE_registrar','OFFICE_super')";
    private static final String EXAMS = "hasAnyAuthority('OFFICE_exams','OFFICE_facultyexams','OFFICE_records','OFFICE_academic','OFFICE_registrar','OFFICE_super')";

    public record Answer(@NotBlank String state, @NotBlank @Size(max = 2000) String answer) {
    }

    public record Slot(@NotNull LocalDate heldOn, @NotNull LocalTime startsAt, @NotNull LocalTime endsAt, @NotBlank @Size(max = 200) String venue) {
    }

    private final JdbcClient jdbc;
    private final ng.edu.moaum.portal.shared.OfficeScope scope;

    QueriesController(JdbcClient jdbc, ng.edu.moaum.portal.shared.OfficeScope scope) {
        this.jdbc = jdbc;
        this.scope = scope;
    }

    @GetMapping("/queries")
    @PreAuthorize(DEPARTMENT)
    @Transactional(readOnly = true)
    List<Map<String, Object>> queries(@RequestParam(required = false) String dept, @RequestParam(defaultValue = "open") String state) {
        // a Head of Department sees only their own department's queries unless they pick one explicitly;
        // a wider office (records, academic, registrar, super) sees them all and may filter by department
        String d = (dept == null || dept.isBlank()) ? scope.actingHodDept() : dept;
        return jdbc.sql("""
                SELECT q.id, q.ref, q.part, q.said, q.routed_dept, d.name AS dept_name, q.raised_at, q.state, q.answer, q.answered_at,
                       s.matric_no, s.surname, s.other_names, c.code AS course_code, c.title, o.session, o.semester,
                       ls.ca, ls.exam, ls.total, ls.grade, ls.outcome
                  FROM assessment.result_query q
                  JOIN people.student s ON s.id = q.student_id
                  JOIN assessment.score_sheet sh ON sh.id = q.sheet_id
                  JOIN catalogue.offering o ON o.id = sh.offering_id
                  JOIN catalogue.course c ON c.code = o.course_code
                  JOIN ref.department d ON d.code = q.routed_dept
                  LEFT JOIN LATERAL (SELECT * FROM assessment.latest_scores(sh.id) x WHERE x.student_id = q.student_id) ls ON true
                 WHERE (:d::text IS NULL OR q.routed_dept = :d)
                   AND CASE :st WHEN 'open' THEN q.state = 'RAISED' WHEN 'answered' THEN q.state <> 'RAISED' ELSE true END
                 ORDER BY q.raised_at DESC LIMIT 500
                """).param("d", d, Types.VARCHAR).param("st", state).query().listOfRows();
    }

    @PostMapping("/queries/{id}/answer")
    @PreAuthorize(DEPARTMENT)
    @Transactional
    Map<String, Object> answer(@PathVariable UUID id, @Valid @RequestBody Answer body) {
        String st = body.state().trim().toUpperCase();
        if (!List.of("UPHELD", "CORRECTED", "CLOSED").contains(st)) {
            throw new DomainRuleViolation("RES_QUERY_STATE", "'" + body.state() + "' is not an answer to a query.",
                    new DomainRuleViolation.Remedy("UPHELD (the mark stands), CORRECTED (the mark is amended through the chain), or CLOSED (not a query).", "Head of Department"));
        }
        String outcome = jdbc.sql("SELECT assessment.answer_query(:id, :s, :a)").param("id", id).param("s", st).param("a", body.answer()).query(String.class).single();
        return Map.of("id", id, "state", outcome);
    }

    /** the paper's slot: day, time and venue, which the docket carries */
    @PutMapping("/offerings/{offeringId}/exam-slot")
    @PreAuthorize(EXAMS)
    @Transactional
    Map<String, Object> examSlot(@PathVariable UUID offeringId, @Valid @RequestBody Slot body) {
        jdbc.sql("""
                INSERT INTO assessment.exam_timetable (offering_id, held_on, starts_at, ends_at, venue) VALUES (:o, :d, :s, :e, :v)
                ON CONFLICT (offering_id) DO UPDATE SET held_on = EXCLUDED.held_on, starts_at = EXCLUDED.starts_at, ends_at = EXCLUDED.ends_at, venue = EXCLUDED.venue
                """).param("o", offeringId).param("d", body.heldOn()).param("s", body.startsAt()).param("e", body.endsAt()).param("v", body.venue().trim()).update();
        return Map.of("offeringId", offeringId, "heldOn", body.heldOn(), "venue", body.venue());
    }
}
