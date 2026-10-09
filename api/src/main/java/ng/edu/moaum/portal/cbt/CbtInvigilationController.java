package ng.edu.moaum.portal.cbt;

import java.sql.Types;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

import ng.edu.moaum.portal.shared.AuditContext;
import ng.edu.moaum.portal.shared.AuditContextHolder;
import ng.edu.moaum.portal.shared.NotFound;
import ng.edu.moaum.portal.shared.OfficeScope;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.AccessDeniedException;
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
 * The invigilator's door (V374). The office that runs an examination names the staff who invigilate each sitting (one may be the
 * chief) and may set how late a candidate may still start on their own. An invigilator sees their sittings and, for each, the seats:
 * who has not come, who is writing and when they were last heard from, who has submitted. They mark a candidate absent (once the
 * sitting has begun, never one who has started) or admit one who came late, giving back at most the minutes lost. Every mark is the
 * database's to judge and stays on the record; who may make it is judged here, on the server — an invigilator of that sitting, or the
 * office that manages the examination. The board is read from the sitting's seats, never from the whole candidate list.
 */
@RestController
@RequestMapping("/api/v1/cbt")
class CbtInvigilationController {

    private static final String MANAGERS = "hasAnyAuthority('OFFICE_gst','OFFICE_eps','OFFICE_exams','OFFICE_facultyexams','OFFICE_records','OFFICE_super','OFFICE_jupeb')";
    /** the offices that read examinations (CbtExamController's readers) and so may look at a sitting's board without invigilating it */
    private static final Set<String> READ_OFFICES = Set.of("gst", "eps", "bursar", "financecontroller", "registrar", "dregistrar", "dvc", "vc", "academic", "records",
            "ict", "admin", "super", "exams", "facultyexams", "hod", "dean", "jupeb");
    /** a candidate's own token is never an invigilator's */
    private static final Set<String> CANDIDATES = Set.of("student", "applicant", "jupebstudent");

    private final JdbcClient jdbc;
    private final OfficeScope scope;

    CbtInvigilationController(JdbcClient jdbc, OfficeScope scope) {
        this.jdbc = jdbc;
        this.scope = scope;
    }

    public record LateEntryIn(Integer minutes) {
    }

    public record InvigilatorIn(@NotNull UUID personId, Boolean chief) {
    }

    public record MarkIn(@Size(max = 500) String note) {
    }

    public record LateIn(@NotNull Integer minutes, @Size(max = 500) String note) {
    }

    private static AuditContext ctx() {
        return AuditContextHolder.current().orElseThrow(() -> new AccessDeniedException("Sign in first."));
    }

    private Map<String, Object> exam(UUID id) {
        return jdbc.sql("SELECT id, office, course_code, reference, title, state, late_entry_minutes FROM assessment.cbt_exam WHERE id = :e").param("e", id)
                .query().listOfRows().stream().findFirst().orElseThrow(() -> new NotFound("examination", id.toString()));
    }

    /** the examination, for the office that manages it (CbtExamController's rule), within its scope */
    private Map<String, Object> managed(UUID id) {
        Map<String, Object> e = exam(id);
        CbtExamController.manage(CbtExamController.office((String) e.get("office")));
        if ("EXAMS".equals(e.get("office"))) scope.assertCourseInScope((String) e.get("course_code"));
        return e;
    }

    private Map<String, Object> sitting(UUID sitting) {
        return jdbc.sql("SELECT id, exam_id, label, venue, starts_at, ends_at, capacity FROM assessment.cbt_sitting WHERE id = :s").param("s", sitting)
                .query().listOfRows().stream().findFirst().orElseThrow(() -> new NotFound("sitting", sitting.toString()));
    }

    private boolean invigilates(UUID sitting) {
        return jdbc.sql("SELECT EXISTS (SELECT 1 FROM assessment.cbt_invigilator WHERE sitting_id = :s AND person_id = :p)")
                .param("s", sitting).param("p", ctx().actorId()).query(Boolean.class).single();
    }

    /** who may mark a sitting: one of its invigilators, or the office managing its examination */
    private Map<String, Object> markable(UUID sitting) {
        Map<String, Object> s = sitting(sitting);
        if (!invigilates(sitting)) managed((UUID) s.get("exam_id"));
        return s;
    }

    /* ── the office: late entry, the invigilators, the staff to choose from ── */

    /** how many minutes after a sitting begins a candidate may still start on their own; null = no limit (none is assumed) */
    @PutMapping("/exams/{id}/late-entry")
    @PreAuthorize(MANAGERS)
    @Transactional
    Map<String, Object> lateEntry(@PathVariable UUID id, @RequestBody LateEntryIn in) {
        managed(id);
        Integer m = jdbc.sql("SELECT late_entry_minutes FROM assessment.cbt_set_late_entry(:e, :m)").param("e", id).param("m", in.minutes(), Types.INTEGER)
                .query(Integer.class).optional().orElse(null);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("exam", id);
        out.put("late_entry_minutes", m);
        return out;
    }

    /** members of staff holding an office today, found by name or staff number, to name as invigilators */
    @GetMapping("/staff")
    @PreAuthorize(MANAGERS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> staff(@RequestParam String q) {
        String t = q == null ? "" : q.trim().toLowerCase();
        if (t.length() < 2) return List.of();
        return jdbc.sql("""
                SELECT p.id, p.staff_number, p.surname, p.given_names, string_agg(DISTINCT o.office_code, ', ' ORDER BY o.office_code) AS offices
                  FROM iam.person p
                  JOIN iam.office_assignment o ON o.person_id = p.id AND o.valid_from <= current_date AND (o.valid_to IS NULL OR o.valid_to >= current_date)
                 WHERE p.ended_on IS NULL
                   AND (lower(p.surname || ' ' || p.given_names) LIKE :q OR lower(p.given_names || ' ' || p.surname) LIKE :q OR lower(coalesce(p.staff_number, '')) LIKE :q)
                 GROUP BY p.id ORDER BY p.surname, p.given_names LIMIT 20
                """).param("q", "%" + t + "%").query().listOfRows();
    }

    @PostMapping("/exams/{id}/sittings/{sitting}/invigilators")
    @PreAuthorize(MANAGERS)
    @Transactional
    Map<String, Object> assign(@PathVariable UUID id, @PathVariable UUID sitting, @Valid @RequestBody InvigilatorIn in) {
        managed(id);
        if (!id.equals(sitting(sitting).get("exam_id"))) throw new NotFound("sitting", sitting.toString());
        return jdbc.sql("SELECT sitting_id, person_id, chief FROM assessment.cbt_assign_invigilator(:s, :p, :c)")
                .param("s", sitting).param("p", in.personId()).param("c", Boolean.TRUE.equals(in.chief())).query().singleRow();
    }

    @PostMapping("/exams/{id}/sittings/{sitting}/invigilators/{person}/remove")
    @PreAuthorize(MANAGERS)
    @Transactional
    Map<String, Object> unassign(@PathVariable UUID id, @PathVariable UUID sitting, @PathVariable UUID person) {
        managed(id);
        if (!id.equals(sitting(sitting).get("exam_id"))) throw new NotFound("sitting", sitting.toString());
        int n = jdbc.sql("SELECT assessment.cbt_unassign_invigilator(:s, :p)").param("s", sitting).param("p", person).query(Integer.class).single();
        return Map.of("removed", n);
    }

    /* ── the invigilator ── */

    /** the sittings the signed-in member of staff invigilates: those to come, and those of the last fortnight */
    @GetMapping("/invigilation")
    @PreAuthorize("isAuthenticated()")
    @Transactional(readOnly = true)
    List<Map<String, Object>> mine() {
        AuditContext c = ctx();
        if (CANDIDATES.contains(c.actorOffice())) throw new AccessDeniedException("Invigilation is for members of staff.");
        return jdbc.sql("""
                SELECT s.id AS sitting_id, s.label, s.venue, s.starts_at, s.ends_at, s.capacity, i.chief,
                       e.id AS exam_id, e.reference, e.title, coalesce(e.course_code, js.code) AS course_code, e.state, assessment.cbt_live_state(e) AS live_state,
                       e.duration_minutes, e.late_entry_minutes,
                       (SELECT count(*) FROM assessment.cbt_seat x WHERE x.sitting_id = s.id) AS seated,
                       CASE WHEN s.ends_at <= now() THEN 'ENDED' WHEN s.starts_at <= now() THEN 'NOW' ELSE 'TO_COME' END AS phase
                  FROM assessment.cbt_invigilator i
                  JOIN assessment.cbt_sitting s ON s.id = i.sitting_id
                  JOIN assessment.cbt_exam e ON e.id = s.exam_id
                  LEFT JOIN jupeb.subject js ON js.id = e.jupeb_subject_id
                 WHERE i.person_id = :me AND e.state <> 'CANCELLED' AND s.ends_at > now() - interval '14 days'
                 ORDER BY s.starts_at, s.label
                """).param("me", c.actorId()).query().listOfRows();
    }

    /** the sitting's seats as they stand: for its invigilators, the office managing it, and the offices that read examinations */
    @GetMapping("/sittings/{sitting}/board")
    @PreAuthorize("isAuthenticated()")
    @Transactional(readOnly = true)
    Map<String, Object> board(@PathVariable UUID sitting) {
        Map<String, Object> s = sitting(sitting);
        UUID examId = (UUID) s.get("exam_id");
        boolean invigilator = invigilates(sitting);
        boolean canMark = invigilator;
        if (!invigilator) {
            String acting = ctx().actorOffice();
            if (!READ_OFFICES.contains(acting)) throw new AccessDeniedException("A sitting's board is for its invigilators and the office running the examination.");
            Map<String, Object> e = exam(examId);
            String office = CbtExamController.office((String) e.get("office"));
            if ("EXAMS".equals(e.get("office"))) scope.assertCourseInScope((String) e.get("course_code"));
            try {
                CbtExamController.manage(office);
                canMark = true;
            } catch (AccessDeniedException readOnly) {
                canMark = false;
            }
        }
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("sitting", s);
        out.put("exam", jdbc.sql("""
                SELECT e.id, e.reference, e.title, coalesce(e.course_code, js.code) AS course_code, e.office, e.state, assessment.cbt_live_state(e) AS live_state,
                       e.duration_minutes, e.late_entry_minutes
                  FROM assessment.cbt_exam e LEFT JOIN jupeb.subject js ON js.id = e.jupeb_subject_id WHERE e.id = :e
                """).param("e", examId).query().singleRow());
        out.put("now", jdbc.sql("SELECT now()").query(java.time.OffsetDateTime.class).single());
        out.put("role", invigilator ? "INVIGILATOR" : canMark ? "OFFICE" : "READER");
        out.put("canMark", canMark);
        out.put("invigilators", jdbc.sql("""
                SELECT p.id AS person_id, p.surname || ', ' || p.given_names AS name, p.staff_number, i.chief
                  FROM assessment.cbt_invigilator i JOIN iam.person p ON p.id = i.person_id WHERE i.sitting_id = :s ORDER BY i.chief DESC, p.surname
                """).param("s", sitting).query().listOfRows());
        out.put("rows", jdbc.sql("SELECT * FROM assessment.cbt_sitting_board(:s)").param("s", sitting).query().listOfRows());
        return out;
    }

    @PostMapping("/sittings/{sitting}/candidates/{candidate}/absent")
    @PreAuthorize("isAuthenticated()")
    @Transactional
    Map<String, Object> absent(@PathVariable UUID sitting, @PathVariable UUID candidate, @Valid @RequestBody MarkIn in) {
        markable(sitting);
        jdbc.sql("SELECT status FROM assessment.cbt_mark_absent(:s, :c, :n)").param("s", sitting).param("c", candidate).param("n", in.note(), Types.VARCHAR).query(String.class).single();
        return board(sitting);
    }

    @PostMapping("/sittings/{sitting}/candidates/{candidate}/late")
    @PreAuthorize("isAuthenticated()")
    @Transactional
    Map<String, Object> late(@PathVariable UUID sitting, @PathVariable UUID candidate, @Valid @RequestBody LateIn in) {
        markable(sitting);
        jdbc.sql("SELECT status FROM assessment.cbt_admit_late(:s, :c, :m, :n)").param("s", sitting).param("c", candidate).param("m", in.minutes())
                .param("n", in.note(), Types.VARCHAR).query(String.class).single();
        return board(sitting);
    }

    @PostMapping("/sittings/{sitting}/candidates/{candidate}/clear")
    @PreAuthorize("isAuthenticated()")
    @Transactional
    Map<String, Object> clear(@PathVariable UUID sitting, @PathVariable UUID candidate) {
        markable(sitting);
        jdbc.sql("SELECT assessment.cbt_clear_mark(:s, :c)").param("s", sitting).param("c", candidate).query(Integer.class).single();
        return board(sitting);
    }

    /** everyone seated who has neither come nor been marked, marked absent — once the sitting has begun */
    @PostMapping("/sittings/{sitting}/rest-absent")
    @PreAuthorize("isAuthenticated()")
    @Transactional
    Map<String, Object> restAbsent(@PathVariable UUID sitting, @Valid @RequestBody MarkIn in) {
        markable(sitting);
        int n = jdbc.sql("SELECT assessment.cbt_mark_rest_absent(:s, :n)").param("s", sitting).param("n", in.note(), Types.VARCHAR).query(Integer.class).single();
        Map<String, Object> out = board(sitting);
        out.put("marked", n);
        return out;
    }
}
