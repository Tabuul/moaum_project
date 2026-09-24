package ng.edu.moaum.portal.college;

import java.sql.Types;
import java.time.LocalDate;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotEmpty;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

import ng.edu.moaum.portal.shared.DomainRuleViolation;
import ng.edu.moaum.portal.shared.NotFound;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.Authentication;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * The postings desk (V245): the College's blocks and postings, the students of the College at a level,
 * and their allocation to a posting for a session — with rotation group, supervisor and dates. The
 * College Secretary and the Provost allocate; the Academic Office and the Registry may; the College's
 * students read their own postings.
 */
@RestController
@RequestMapping("/api/v1/college")
class CollegeController {

    private static final String DESK = "hasAnyAuthority('OFFICE_provost','OFFICE_collegesecretary','OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar','OFFICE_admin','OFFICE_super')";
    private static final String READERS = "hasAnyAuthority('OFFICE_provost','OFFICE_collegesecretary','OFFICE_financecontroller','OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar',"
            + "'OFFICE_records','OFFICE_dean','OFFICE_hod','OFFICE_lecturer','OFFICE_exams','OFFICE_vc','OFFICE_dvc','OFFICE_admin','OFFICE_super')";

    private final JdbcClient jdbc;

    CollegeController(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    /** the College's blocks with their postings, courses and rotation groups; and the levels with their phase */
    @GetMapping("/structure")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> structure() {
        List<Map<String, Object>> blocks = jdbc.sql("""
                SELECT b.id, b.code, b.name, b.dept_code, b.total_weeks, b.weeks_note, b.note, b.ordinal FROM college.block b ORDER BY b.ordinal
                """).query().listOfRows();
        List<Map<String, Object>> postings = jdbc.sql("""
                SELECT p.id, p.block_id, p.code, p.name, p.tier, p.level, p.level_note, p.duration_weeks, p.ordinal, p.min_cases, p.note,
                       (SELECT string_agg(pc.course_code || coalesce(' ' || pc.title, ''), ' · ' ORDER BY pc.course_code) FROM college.posting_course pc WHERE pc.posting_id = p.id) AS courses,
                       (SELECT count(*) FROM college.procedure_requirement pr WHERE pr.posting_id = p.id) AS procedures,
                       (SELECT count(*) FROM college.timetable_slot t WHERE t.posting_id = p.id) AS slots
                  FROM college.posting p ORDER BY p.block_id, p.ordinal
                """).query().listOfRows();
        List<Map<String, Object>> groups = jdbc.sql("SELECT id, posting_id, label FROM college.rotation_group ORDER BY posting_id, label").query().listOfRows();
        List<Map<String, Object>> levels = jdbc.sql("SELECT level, phase, clinical_year, enrolment FROM college.level ORDER BY level").query().listOfRows();
        return Map.of("blocks", blocks, "postings", postings, "groups", groups, "levels", levels);
    }

    /** the College's students at a level, each with their allocations for the session */
    @GetMapping("/students")
    @PreAuthorize(DESK)
    @Transactional(readOnly = true)
    List<Map<String, Object>> students(@RequestParam String session, @RequestParam int level) {
        return jdbc.sql("""
                SELECT st.id, coalesce(st.matric_no, st.admission_no) AS number, st.surname, st.other_names, st.programme_code, p.name AS programme,
                       st.current_level, st.entry_mode, st.status,
                       coalesce((SELECT jsonb_agg(jsonb_build_object('id', a.id, 'posting_id', a.posting_id, 'posting', po.code, 'block', b.code, 'group', g.label,
                                                                     'supervisor', CASE WHEN sp.id IS NULL THEN NULL ELSE sp.surname || ', ' || sp.given_names END,
                                                                     'starts_on', a.starts_on, 'ends_on', a.ends_on, 'state', a.state) ORDER BY b.ordinal, po.ordinal)
                                   FROM college.posting_allocation a
                                   JOIN college.posting po ON po.id = a.posting_id JOIN college.block b ON b.id = po.block_id
                                   LEFT JOIN college.rotation_group g ON g.id = a.group_id
                                   LEFT JOIN iam.person sp ON sp.id = a.supervisor_id
                                  WHERE a.student_id = st.id AND a.session = :s), '[]'::jsonb)::text AS allocations
                  FROM people.student st
                  JOIN ref.programme p ON p.code = st.programme_code
                  JOIN ref.faculty f ON f.code = p.faculty_code
                 WHERE f.college_code = 'CHS' AND st.current_level = :l
                   AND st.status NOT IN ('WITHDRAWN','EXPELLED','TRANSFERRED_OUT','DECEASED','GRADUATED')
                 ORDER BY coalesce(st.matric_no, st.admission_no), st.surname
                """).param("s", session).param("l", level).query().listOfRows();
    }

    /** the allocations to one posting in a session */
    @GetMapping("/postings/{id}/allocations")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> allocations(@PathVariable UUID id, @RequestParam String session) {
        return jdbc.sql("""
                SELECT a.id, a.student_id, coalesce(st.matric_no, st.admission_no) AS number, st.surname, st.other_names, st.programme_code,
                       g.id AS group_id, g.label AS group_label, a.supervisor_id,
                       CASE WHEN sp.id IS NULL THEN NULL ELSE sp.surname || ', ' || sp.given_names END AS supervisor,
                       a.starts_on, a.ends_on, a.state, a.allocated_at
                  FROM college.posting_allocation a
                  JOIN people.student st ON st.id = a.student_id
                  LEFT JOIN college.rotation_group g ON g.id = a.group_id
                  LEFT JOIN iam.person sp ON sp.id = a.supervisor_id
                 WHERE a.posting_id = :p AND a.session = :s
                 ORDER BY g.label NULLS LAST, coalesce(st.matric_no, st.admission_no)
                """).param("p", id).param("s", session).query().listOfRows();
    }

    /** the College's academic staff who may supervise a posting: anyone holding a lecturer, HOD or examinations office
     *  scoped to a department of the College's faculties */
    @GetMapping("/supervisors")
    @PreAuthorize(DESK)
    @Transactional(readOnly = true)
    List<Map<String, Object>> supervisors() {
        return jdbc.sql("""
                SELECT DISTINCT p.id, p.surname, p.given_names, p.staff_number, d.code AS dept_code, d.name AS dept_name
                  FROM iam.office_assignment a
                  JOIN iam.person p ON p.id = a.person_id AND p.ended_on IS NULL
                  JOIN ref.department d ON upper(d.code) = upper(btrim(a.scope_id)) OR lower(d.name) = lower(btrim(a.scope_id))
                  JOIN ref.faculty f ON f.code = d.faculty_code AND f.college_code = 'CHS'
                 WHERE a.office_code IN ('lecturer','hod','exams') AND a.scope_kind = 'department'
                   AND a.valid_from <= current_date AND (a.valid_to IS NULL OR a.valid_to >= current_date)
                 ORDER BY p.surname, p.given_names
                """).query().listOfRows();
    }

    public record AllocateIn(@NotBlank String session, @NotNull UUID postingId, @NotEmpty @Size(max = 500) List<UUID> studentIds,
                             UUID groupId, UUID supervisorId, LocalDate startsOn, LocalDate endsOn) {
    }

    /** allocate students to a posting for a session; a student already on it has their group, supervisor and dates set */
    @PostMapping("/allocations")
    @PreAuthorize(DESK)
    @Transactional
    Map<String, Object> allocate(@Valid @RequestBody AllocateIn body) {
        Map<String, Object> posting = jdbc.sql("SELECT p.id, p.code, p.level, b.code AS block FROM college.posting p JOIN college.block b ON b.id = p.block_id WHERE p.id = :p")
                .param("p", body.postingId()).query().listOfRows().stream().findFirst().orElseThrow(() -> new NotFound("posting", body.postingId()));
        if (body.startsOn() != null && body.endsOn() != null && !body.endsOn().isAfter(body.startsOn())) {
            throw new DomainRuleViolation("COLLEGE_DATES", "A posting ends after it starts.",
                    new DomainRuleViolation.Remedy("Give an end date after the start date, or leave both blank until the College dates the posting.", "College Secretary"));
        }
        if (body.groupId() != null) {
            long ok = jdbc.sql("SELECT count(*) FROM college.rotation_group WHERE id = :g AND posting_id = :p").param("g", body.groupId()).param("p", body.postingId()).query(Long.class).single();
            if (ok == 0) throw new DomainRuleViolation("COLLEGE_GROUP", "That rotation group is not one of this posting's.",
                    new DomainRuleViolation.Remedy("Choose a group of the posting, or none.", "College Secretary"));
        }
        // every student must be the College's; a student of another faculty is refused by name
        List<Map<String, Object>> outside = jdbc.sql("""
                SELECT st.id, coalesce(st.matric_no, st.admission_no) AS number FROM people.student st
                  JOIN ref.programme p ON p.code = st.programme_code JOIN ref.faculty f ON f.code = p.faculty_code
                 WHERE st.id IN (:ids) AND coalesce(f.college_code, '') <> 'CHS'
                """).param("ids", body.studentIds()).query().listOfRows();
        if (!outside.isEmpty()) {
            throw new DomainRuleViolation("COLLEGE_NOT_MEMBER", outside.size() + " of the students are not the College's: "
                    + String.join(", ", outside.stream().map(r -> String.valueOf(r.get("number"))).toList()),
                    new DomainRuleViolation.Remedy("A posting is allocated to the College's students only.", "College Secretary"));
        }
        int n = 0;
        for (UUID student : body.studentIds()) {
            n += jdbc.sql("""
                    INSERT INTO college.posting_allocation (student_id, posting_id, session, group_id, supervisor_id, starts_on, ends_on)
                    VALUES (:st, :p, :s, :g, :sv, :from, :to)
                    ON CONFLICT (student_id, posting_id, session) DO UPDATE SET
                           group_id = coalesce(EXCLUDED.group_id, college.posting_allocation.group_id),
                           supervisor_id = coalesce(EXCLUDED.supervisor_id, college.posting_allocation.supervisor_id),
                           starts_on = coalesce(EXCLUDED.starts_on, college.posting_allocation.starts_on),
                           ends_on = coalesce(EXCLUDED.ends_on, college.posting_allocation.ends_on)
                    """).param("st", student).param("p", body.postingId()).param("s", body.session())
                    .param("g", body.groupId(), Types.OTHER).param("sv", body.supervisorId(), Types.OTHER)
                    .param("from", body.startsOn(), Types.DATE).param("to", body.endsOn(), Types.DATE).update();
        }
        return Map.of("posting", posting.get("code"), "block", posting.get("block"), "session", body.session(), "allocated", n);
    }

    public record AllocationEdit(@Size(max = 12) String state, UUID groupId, UUID supervisorId, LocalDate startsOn, LocalDate endsOn) {
    }

    /** change one allocation: its state (allocated, in progress, completed, incomplete), group, supervisor or dates */
    @PutMapping("/allocations/{id}")
    @PreAuthorize(DESK)
    @Transactional
    Map<String, Object> edit(@PathVariable UUID id, @Valid @RequestBody AllocationEdit body) {
        String state = body.state() == null || body.state().isBlank() ? null : body.state().trim().toUpperCase();
        if (state != null && !List.of("ALLOCATED", "IN_PROGRESS", "COMPLETED", "INCOMPLETE").contains(state)) {
            throw new DomainRuleViolation("COLLEGE_STATE", "A posting allocation is allocated, in progress, completed or incomplete.",
                    new DomainRuleViolation.Remedy("Choose one of the four.", "College Secretary"));
        }
        int n = jdbc.sql("""
                UPDATE college.posting_allocation SET
                       state = coalesce(cast(:state as text), state),
                       group_id = coalesce(:g, group_id),
                       supervisor_id = coalesce(:sv, supervisor_id),
                       starts_on = coalesce(:from, starts_on),
                       ends_on = coalesce(:to, ends_on)
                 WHERE id = :id
                """).param("id", id).param("state", state, Types.VARCHAR).param("g", body.groupId(), Types.OTHER).param("sv", body.supervisorId(), Types.OTHER)
                .param("from", body.startsOn(), Types.DATE).param("to", body.endsOn(), Types.DATE).update();
        if (n == 0) throw new NotFound("posting allocation", id);
        return Map.of("id", id, "updated", n);
    }

    /** withdraw an allocation made in error — only while it is still merely allocated */
    @DeleteMapping("/allocations/{id}")
    @PreAuthorize(DESK)
    @Transactional
    Map<String, Object> withdraw(@PathVariable UUID id) {
        String state = jdbc.sql("SELECT state FROM college.posting_allocation WHERE id = :id").param("id", id).query(String.class).optional()
                .orElseThrow(() -> new NotFound("posting allocation", id));
        if (!"ALLOCATED".equals(state)) {
            throw new DomainRuleViolation("COLLEGE_ALLOC_STARTED", "The posting is " + state.toLowerCase().replace('_', ' ') + "; an allocation that has begun is not withdrawn, it is marked incomplete.",
                    new DomainRuleViolation.Remedy("Set its state to incomplete instead.", "College Secretary"));
        }
        jdbc.sql("DELETE FROM college.posting_allocation WHERE id = :id").param("id", id).update();
        return Map.of("id", id, "withdrawn", true);
    }

    /** the signed-in student's own postings, every session, with the logbook standing of each */
    @GetMapping("/my-postings")
    @PreAuthorize("hasAuthority('OFFICE_student')")
    @Transactional(readOnly = true)
    List<Map<String, Object>> myPostings(Authentication auth) {
        UUID me = UUID.fromString(auth.getName());
        return jdbc.sql("""
                SELECT a.id, a.session, a.state, a.starts_on, a.ends_on, po.code AS posting, po.name AS posting_name, po.tier, po.duration_weeks,
                       b.code AS block_code, b.name AS block, g.label AS group_label,
                       CASE WHEN sp.id IS NULL THEN NULL ELSE sp.surname || ', ' || sp.given_names END AS supervisor,
                       (SELECT count(*) FROM college.posting_logbook(a.student_id, a.posting_id) l) AS requirements,
                       (SELECT count(*) FROM college.posting_logbook(a.student_id, a.posting_id) l WHERE l.met) AS requirements_met
                  FROM college.posting_allocation a
                  JOIN college.posting po ON po.id = a.posting_id JOIN college.block b ON b.id = po.block_id
                  LEFT JOIN college.rotation_group g ON g.id = a.group_id
                  LEFT JOIN iam.person sp ON sp.id = a.supervisor_id
                 WHERE a.student_id = :me
                 ORDER BY a.session DESC, b.ordinal, po.ordinal
                """).param("me", me).query().listOfRows();
    }
}
