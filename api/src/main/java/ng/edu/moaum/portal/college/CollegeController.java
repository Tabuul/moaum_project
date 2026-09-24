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
            + "'OFFICE_records','OFFICE_dean','OFFICE_hod','OFFICE_lecturer','OFFICE_exams','OFFICE_vc','OFFICE_dvc','OFFICE_admin','OFFICE_super','OFFICE_mbbscoordinator')";

    /** the desk, and the College's own teachers — a lecturer, Head of Department or examinations officer whose department is the College's */
    private static final String EXAMINERS = "hasAnyAuthority('OFFICE_provost','OFFICE_collegesecretary','OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar','OFFICE_admin','OFFICE_super','OFFICE_lecturer','OFFICE_hod','OFFICE_exams','OFFICE_mbbscoordinator')";
    /** the desk, and the MBBS Coordinator at their level: opening a student's year, the cohort list */
    private static final String DESK_OR_COORDINATOR = "hasAnyAuthority('OFFICE_provost','OFFICE_collegesecretary','OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar','OFFICE_admin','OFFICE_super','OFFICE_mbbscoordinator')";
    private static final String STUDENT = "hasAuthority('OFFICE_student')";

    private final JdbcClient jdbc;
    private final ng.edu.moaum.portal.shared.OfficeScope scope;
    private final org.springframework.transaction.PlatformTransactionManager transactions;

    CollegeController(JdbcClient jdbc, ng.edu.moaum.portal.shared.OfficeScope scope, org.springframework.transaction.PlatformTransactionManager transactions) {
        this.jdbc = jdbc;
        this.scope = scope;
        this.transactions = transactions;
    }

    /** the MBBS Coordinator acts at their level and no other (V250); every other office passes */
    private void assertLevel(Object level) {
        if (!scope.actingCoordinator()) return;
        Integer mine = scope.actingLevel();
        int asked = level instanceof Number n ? n.intValue() : Integer.parseInt(String.valueOf(level));
        if (mine == null || mine != asked) {
            throw new DomainRuleViolation("COLLEGE_NOT_YOUR_LEVEL", "The MBBS Coordinator acts at " + (mine == null ? "no level" : mine + " Level") + "; this is " + asked + " Level.",
                    new DomainRuleViolation.Remedy("Work at the level your coordinatorship names.", "College Secretary"));
        }
    }

    /** a department office (lecturer, HOD, examinations officer) examines only when its department is the College's */
    private void assertCollegeExaminer() {
        if (!scope.actingDepartmentOffice()) return;
        String dept = scope.actingDept();
        boolean chs = dept != null && jdbc.sql("""
                SELECT EXISTS (SELECT 1 FROM ref.programme p JOIN ref.faculty f ON f.code = p.faculty_code WHERE p.dept_code = :d AND f.college_code = 'CHS')
                """).param("d", dept).query(Boolean.class).single();
        if (!chs) throw new DomainRuleViolation("COLLEGE_NOT_EXAMINER", "The Professional examinations are examined by the College of Health Sciences' own departments.",
                new DomainRuleViolation.Remedy("A lecturer, Head of Department or examinations officer of a College department may enter results.", "College Secretary"));
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
    @PreAuthorize(DESK_OR_COORDINATOR)
    @Transactional(readOnly = true)
    List<Map<String, Object>> students(@RequestParam String session, @RequestParam int level) {
        assertLevel(level);
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

    /* ── the supervisor's logbook: what a posting asks of the student, verified by the one who supervises ── */

    private static final String SUPERVISORS = "hasAnyAuthority('OFFICE_lecturer','OFFICE_hod','OFFICE_exams','OFFICE_provost','OFFICE_collegesecretary','OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar','OFFICE_admin','OFFICE_super')";
    private static final java.util.Set<String> DESK_OFFICES = java.util.Set.of("provost", "collegesecretary", "academic", "registrar", "dregistrar", "admin", "super");

    private UUID actor(Authentication auth) {
        return UUID.fromString(auth.getName());
    }

    private String actingOffice() {
        return ng.edu.moaum.portal.shared.AuditContextHolder.current().map(c -> c.actorOffice()).orElse("");
    }

    /** the allocation's supervisor, or a College desk office, acts on its logbook; nobody else */
    private Map<String, Object> supervised(UUID allocation, Authentication auth) {
        Map<String, Object> a = jdbc.sql("""
                SELECT a.id, a.student_id, a.posting_id, a.session, a.supervisor_id, a.state, po.code AS posting, po.block_id,
                       coalesce(st.matric_no, st.admission_no) AS number, st.surname, st.other_names
                  FROM college.posting_allocation a JOIN college.posting po ON po.id = a.posting_id JOIN people.student st ON st.id = a.student_id
                 WHERE a.id = :id
                """).param("id", allocation).query().listOfRows().stream().findFirst().orElseThrow(() -> new NotFound("posting allocation", allocation));
        UUID me = actor(auth);
        if (!me.equals(a.get("supervisor_id")) && !DESK_OFFICES.contains(actingOffice())) {
            throw new DomainRuleViolation("COLLEGE_NOT_SUPERVISOR", "This posting is supervised by someone else; only the supervisor, or the College's desk, writes its logbook.",
                    new DomainRuleViolation.Remedy("Ask the College Secretary to name you the supervisor on the allocation.", "College Secretary"));
        }
        return a;
    }

    /** the postings the acting person supervises this session, each with its students and where each stands */
    @GetMapping("/my-supervision")
    @PreAuthorize(SUPERVISORS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> mySupervision(Authentication auth, @RequestParam String session, @RequestParam(defaultValue = "false") boolean all) {
        boolean desk = all && DESK_OFFICES.contains(actingOffice());
        return jdbc.sql("""
                SELECT a.id, a.student_id, coalesce(st.matric_no, st.admission_no) AS number, st.surname, st.other_names, st.programme_code,
                       a.posting_id, po.code AS posting, po.name AS posting_name, po.tier, po.duration_weeks, po.min_cases,
                       b.id AS block_id, b.code AS block_code, b.name AS block, g.label AS group_label, a.starts_on, a.ends_on, a.state,
                       CASE WHEN sp.id IS NULL THEN NULL ELSE sp.surname || ', ' || sp.given_names END AS supervisor,
                       (SELECT count(*) FROM college.posting_logbook(a.student_id, a.posting_id) l) AS requirements,
                       (SELECT count(*) FROM college.posting_logbook(a.student_id, a.posting_id) l WHERE l.met) AS requirements_met,
                       (SELECT count(*) FROM college.attendance_record r WHERE r.student_id = a.student_id AND r.posting_id = a.posting_id) AS sessions_recorded,
                       (SELECT count(*) FROM college.attendance_record r WHERE r.student_id = a.student_id AND r.posting_id = a.posting_id AND r.present) AS sessions_present,
                       (SELECT count(*) FROM college.case_clerking c WHERE c.student_id = a.student_id AND c.posting_id = a.posting_id) AS cases
                  FROM college.posting_allocation a
                  JOIN college.posting po ON po.id = a.posting_id JOIN college.block b ON b.id = po.block_id
                  JOIN people.student st ON st.id = a.student_id
                  LEFT JOIN college.rotation_group g ON g.id = a.group_id
                  LEFT JOIN iam.person sp ON sp.id = a.supervisor_id
                 WHERE a.session = :s AND (:all OR a.supervisor_id = :me)
                 ORDER BY b.ordinal, po.ordinal, g.label NULLS LAST, coalesce(st.matric_no, st.admission_no)
                """).param("s", session).param("me", actor(auth)).param("all", desk).query().listOfRows();
    }

    /** one student's logbook on one posting: requirements and what is logged, cases, attendance, the mandatory events */
    @GetMapping("/allocations/{id}/logbook")
    @PreAuthorize(SUPERVISORS)
    @Transactional(readOnly = true)
    Map<String, Object> logbook(@PathVariable UUID id, Authentication auth) {
        Map<String, Object> a = supervised(id, auth);
        UUID student = (UUID) a.get("student_id");
        UUID posting = (UUID) a.get("posting_id");
        List<Map<String, Object>> requirements = jdbc.sql("""
                SELECT pr.id, pr.name, pr.min_count, pr.mode,
                       (SELECT count(*) FROM college.procedure_log l WHERE l.student_id = :st AND l.requirement_id = pr.id AND l.verified_at IS NOT NULL AND (pr.mode = 'EITHER' OR l.mode = pr.mode)) AS done,
                       (SELECT count(*) FROM college.procedure_log l WHERE l.student_id = :st AND l.requirement_id = pr.id AND l.verified_at IS NULL) AS unverified
                  FROM college.procedure_requirement pr WHERE pr.posting_id = :p ORDER BY pr.name
                """).param("st", student).param("p", posting).query().listOfRows();
        List<Map<String, Object>> procedures = jdbc.sql("""
                SELECT l.id, l.requirement_id, pr.name, l.done_on, l.patient_ref, l.mode, l.verified_at,
                       CASE WHEN v.id IS NULL THEN NULL ELSE v.surname || ', ' || v.given_names END AS verified_by
                  FROM college.procedure_log l JOIN college.procedure_requirement pr ON pr.id = l.requirement_id LEFT JOIN iam.person v ON v.id = l.verified_by
                 WHERE l.student_id = :st AND pr.posting_id = :p ORDER BY l.done_on DESC, pr.name
                """).param("st", student).param("p", posting).query().listOfRows();
        List<Map<String, Object>> cases = jdbc.sql("""
                SELECT c.id, c.done_on, c.patient_ref, c.presented, CASE WHEN v.id IS NULL THEN NULL ELSE v.surname || ', ' || v.given_names END AS verified_by
                  FROM college.case_clerking c LEFT JOIN iam.person v ON v.id = c.verified_by
                 WHERE c.student_id = :st AND c.posting_id = :p ORDER BY c.done_on DESC
                """).param("st", student).param("p", posting).query().listOfRows();
        List<Map<String, Object>> attendance = jdbc.sql("""
                SELECT r.id, r.held_on, r.activity_type, r.present, t.starts_at, t.ends_at, t.slot_type, t.topic
                  FROM college.attendance_record r LEFT JOIN college.timetable_slot t ON t.id = r.slot_id
                 WHERE r.student_id = :st AND r.posting_id = :p ORDER BY r.held_on DESC, t.starts_at
                """).param("st", student).param("p", posting).query().listOfRows();
        List<Map<String, Object>> events = jdbc.sql("""
                SELECT e.id, e.name, e.weekday,
                       (SELECT count(*) FROM college.event_attendance x WHERE x.event_id = e.id AND x.student_id = :st) AS held,
                       (SELECT count(*) FROM college.event_attendance x WHERE x.event_id = e.id AND x.student_id = :st AND x.present) AS present
                  FROM college.mandatory_event e WHERE e.block_id = :b ORDER BY e.name
                """).param("st", student).param("b", a.get("block_id")).query().listOfRows();
        List<Map<String, Object>> slots = jdbc.sql("""
                SELECT id, week_no, weekday, starts_at, ends_at, slot_type, topic FROM college.timetable_slot WHERE posting_id = :p ORDER BY week_no, weekday, starts_at
                """).param("p", posting).query().listOfRows();
        Map<String, Object> out = new java.util.LinkedHashMap<>();
        out.put("allocation", a);
        out.put("requirements", requirements);
        out.put("procedures", procedures);
        out.put("cases", cases);
        out.put("attendance", attendance);
        out.put("events", events);
        out.put("slots", slots);
        out.put("minCases", jdbc.sql("SELECT min_cases FROM college.posting WHERE id = :p").param("p", posting).query(Integer.class).optional().orElse(null));
        return out;
    }

    public record ProcedureIn(@NotNull UUID requirementId, @NotNull LocalDate doneOn, @Size(max = 80) String patientRef, @NotBlank String mode, Boolean verified) {
    }

    /** a procedure the student observed or performed; verified at once by the supervisor unless said otherwise */
    @PostMapping("/allocations/{id}/procedures")
    @PreAuthorize(SUPERVISORS)
    @Transactional
    Map<String, Object> logProcedure(@PathVariable UUID id, @Valid @RequestBody ProcedureIn body, Authentication auth) {
        Map<String, Object> a = supervised(id, auth);
        String mode = body.mode().trim().toUpperCase();
        if (!List.of("OBSERVE", "PERFORM").contains(mode)) {
            throw new DomainRuleViolation("COLLEGE_PROC_MODE", "A procedure is observed or performed.", new DomainRuleViolation.Remedy("Say which.", "Supervisor"));
        }
        long belongs = jdbc.sql("SELECT count(*) FROM college.procedure_requirement WHERE id = :r AND posting_id = :p").param("r", body.requirementId()).param("p", a.get("posting_id")).query(Long.class).single();
        if (belongs == 0) throw new DomainRuleViolation("COLLEGE_PROC_POSTING", "That procedure is not one this posting asks for.", new DomainRuleViolation.Remedy("Choose from the posting's list.", "Supervisor"));
        boolean verified = body.verified() == null || body.verified();
        UUID logId = jdbc.sql("""
                INSERT INTO college.procedure_log (student_id, requirement_id, done_on, patient_ref, mode, verified_by, verified_at)
                VALUES (:st, :r, :d, :ref, :m, :vb, :va) RETURNING id
                """).param("st", a.get("student_id")).param("r", body.requirementId()).param("d", body.doneOn()).param("ref", body.patientRef(), Types.VARCHAR)
                .param("m", mode).param("vb", verified ? actor(auth) : null, Types.OTHER).param("va", verified ? java.time.OffsetDateTime.now() : null, Types.TIMESTAMP_WITH_TIMEZONE)
                .query(UUID.class).single();
        return Map.of("id", logId, "verified", verified);
    }

    /** verify a procedure the student logged */
    @PutMapping("/allocations/{id}/procedures/{log}/verify")
    @PreAuthorize(SUPERVISORS)
    @Transactional
    Map<String, Object> verifyProcedure(@PathVariable UUID id, @PathVariable UUID log, Authentication auth) {
        Map<String, Object> a = supervised(id, auth);
        int n = jdbc.sql("UPDATE college.procedure_log SET verified_by = :me, verified_at = now() WHERE id = :l AND student_id = :st AND verified_at IS NULL")
                .param("me", actor(auth)).param("l", log).param("st", a.get("student_id")).update();
        if (n == 0) throw new NotFound("unverified procedure", log);
        return Map.of("id", log, "verified", true);
    }

    public record CaseIn(@NotNull LocalDate doneOn, @Size(max = 80) String patientRef, Boolean presented) {
    }

    /** a case the student clerked, verified by the supervisor */
    @PostMapping("/allocations/{id}/cases")
    @PreAuthorize(SUPERVISORS)
    @Transactional
    Map<String, Object> logCase(@PathVariable UUID id, @Valid @RequestBody CaseIn body, Authentication auth) {
        Map<String, Object> a = supervised(id, auth);
        UUID caseId = jdbc.sql("INSERT INTO college.case_clerking (student_id, posting_id, done_on, patient_ref, presented, verified_by) VALUES (:st, :p, :d, :ref, :pr, :me) RETURNING id")
                .param("st", a.get("student_id")).param("p", a.get("posting_id")).param("d", body.doneOn()).param("ref", body.patientRef(), Types.VARCHAR)
                .param("pr", Boolean.TRUE.equals(body.presented())).param("me", actor(auth)).query(UUID.class).single();
        return Map.of("id", caseId);
    }

    public record AttendanceIn(@NotNull LocalDate heldOn, @NotBlank String activityType, @NotNull Boolean present, UUID slotId) {
    }

    /** the student's attendance at a session of the posting — a lecture, a ward round, a clinic, a test */
    @PostMapping("/allocations/{id}/attendance")
    @PreAuthorize(SUPERVISORS)
    @Transactional
    Map<String, Object> attendance(@PathVariable UUID id, @Valid @RequestBody AttendanceIn body, Authentication auth) {
        Map<String, Object> a = supervised(id, auth);
        String type = body.activityType().trim().toUpperCase();
        if (!List.of("LECTURE", "PRACTICAL", "CLINICAL", "TUTORIAL", "TEST", "OTHER").contains(type)) {
            throw new DomainRuleViolation("COLLEGE_ACTIVITY", "An attendance is at a lecture, a practical, a clinical session, a tutorial, a test or another activity.",
                    new DomainRuleViolation.Remedy("Choose one of the six.", "Supervisor"));
        }
        UUID recId = jdbc.sql("INSERT INTO college.attendance_record (student_id, activity_type, posting_id, slot_id, held_on, present, recorded_by) VALUES (:st, :t, :p, :sl, :d, :pr, :me) RETURNING id")
                .param("st", a.get("student_id")).param("t", type).param("p", a.get("posting_id")).param("sl", body.slotId(), Types.OTHER)
                .param("d", body.heldOn()).param("pr", body.present()).param("me", actor(auth)).query(UUID.class).single();
        return Map.of("id", recId);
    }

    public record EventIn(@NotNull UUID eventId, @NotNull LocalDate heldOn, @NotNull Boolean present) {
    }

    /** attendance at a mandatory event of the block — the Wednesday Grand Round */
    @PostMapping("/allocations/{id}/events")
    @PreAuthorize(SUPERVISORS)
    @Transactional
    Map<String, Object> eventAttendance(@PathVariable UUID id, @Valid @RequestBody EventIn body, Authentication auth) {
        Map<String, Object> a = supervised(id, auth);
        long belongs = jdbc.sql("SELECT count(*) FROM college.mandatory_event WHERE id = :e AND block_id = :b").param("e", body.eventId()).param("b", a.get("block_id")).query(Long.class).single();
        if (belongs == 0) throw new DomainRuleViolation("COLLEGE_EVENT", "That event is not one of this block's.", new DomainRuleViolation.Remedy("Choose from the block's events.", "Supervisor"));
        jdbc.sql("""
                INSERT INTO college.event_attendance (event_id, student_id, held_on, present) VALUES (:e, :st, :d, :pr)
                ON CONFLICT (event_id, student_id, held_on) DO UPDATE SET present = EXCLUDED.present
                """).param("e", body.eventId()).param("st", a.get("student_id")).param("d", body.heldOn()).param("pr", body.present()).update();
        return Map.of("event", body.eventId(), "heldOn", body.heldOn().toString(), "present", body.present());
    }


    /* ── the Professional examination desk: the subjects by attempt, the pass by the rule, the decision, the reconciliation ── */

    private Map<String, Object> exam(String code) {
        return jdbc.sql("SELECT id, code, name, level, papers, external_examiners, resit_allowed, resit_window_months, no_resit_if_all_failed, appeal_to_senate, min_attendance_pct, on_failure, ordinal FROM college.professional_exam WHERE code = :c")
                .param("c", code.trim().toUpperCase()).query().listOfRows().stream().findFirst().orElseThrow(() -> new NotFound("professional examination", code));
    }

    /** the CPE and the four Professionals, each with its subjects and their CA items */
    @GetMapping("/exams")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> exams() {
        List<Map<String, Object>> exams = jdbc.sql("SELECT id, code, name, level, papers, external_examiners, resit_allowed, resit_window_months, no_resit_if_all_failed, appeal_to_senate, min_attendance_pct, on_failure, ordinal FROM college.professional_exam ORDER BY ordinal").query().listOfRows();
        List<Map<String, Object>> subjects = jdbc.sql("SELECT id, exam_id, name, departments, ca_weight, exam_weight, pass_mark, clinical_component_min, conflict_note, ordinal FROM college.exam_subject ORDER BY exam_id, ordinal").query().listOfRows();
        List<Map<String, Object>> items = jdbc.sql("SELECT id, subject_id, posting_id, item_type, name, weight_within_ca, max_score, eligibility_gate, note FROM college.assessment_item ORDER BY subject_id, name").query().listOfRows();
        return Map.of("exams", exams, "subjects", subjects, "items", items);
    }

    /** the candidates for an examination in a session — the College's students at its level — with each subject's
     *  results by attempt and the progression decision, if any */
    @GetMapping("/exams/{code}/candidates")
    @PreAuthorize(EXAMINERS)
    @Transactional(readOnly = true)
    Map<String, Object> candidates(@PathVariable String code, @RequestParam String session) {
        assertCollegeExaminer();
        Map<String, Object> e = exam(code);
        assertLevel(e.get("level"));
        List<Map<String, Object>> rows = jdbc.sql("""
                SELECT st.id, coalesce(st.matric_no, st.admission_no) AS number, st.surname, st.other_names, st.programme_code, st.entry_mode, st.current_level,
                       coalesce((SELECT jsonb_agg(jsonb_build_object('id', r.id, 'subject_id', r.subject_id, 'attempt', r.attempt, 'ca', r.ca_score, 'exam', r.exam_score,
                                                                     'clinical', r.clinical_score, 'attendance', r.attendance_pct, 'barred', r.barred, 'total', r.total, 'passed', r.passed, 'decided_on', r.decided_on) ORDER BY r.subject_id, r.attempt)
                                   FROM college.exam_result r JOIN college.exam_subject s ON s.id = r.subject_id
                                  WHERE r.student_id = st.id AND r.session = :s AND s.exam_id = :e), '[]'::jsonb)::text AS results,
                       (SELECT row_to_json(d)::text FROM (SELECT d.id, d.outcome, d.state, d.carry_overs, d.rule_ref, d.minute, d.decided_on, d.confirmed_on, d.honours,
                                                                 (SELECT string_agg(s.name, ', ' ORDER BY s.ordinal) FROM college.exam_subject s WHERE s.id = ANY(d.resit_subjects)) AS resit_names
                                                            FROM college.progression_decision d WHERE d.student_id = st.id AND d.session = :s AND d.from_level = :l) d) AS decision,
                       college.attempt_of(st.id, :l, :s) AS attempt,
                       c.kind AS enrolment_kind, c.attempt_no, c.state AS enrolment_state, c.semesters, c.semesters_registered, c.fully_registered
                  FROM college.cohort(:l, :s) c
                  JOIN people.student st ON st.id = c.student_id
                 ORDER BY coalesce(st.matric_no, st.admission_no), st.surname
                """).param("s", session).param("e", e.get("id")).param("l", e.get("level")).query().listOfRows();
        List<Map<String, Object>> subjects = jdbc.sql("SELECT id, name, departments, ca_weight, exam_weight, pass_mark, clinical_component_min, conflict_note, ordinal FROM college.exam_subject WHERE exam_id = :e ORDER BY ordinal")
                .param("e", e.get("id")).query().listOfRows();
        boolean reached = jdbc.sql("SELECT college.year_reached_final(:l, :s)").param("l", e.get("level")).param("s", session).query(Boolean.class).single();
        List<Map<String, Object>> calendar = jdbc.sql("SELECT ordinal, length_weeks, starts_on, ends_on FROM college.semester WHERE level = :l AND session = :s ORDER BY ordinal")
                .param("l", e.get("level")).param("s", session).query().listOfRows();
        java.util.Map<String, Object> out = new java.util.LinkedHashMap<>();
        out.put("exam", e);
        out.put("subjects", subjects);
        out.put("candidates", rows);
        out.put("yearReached", reached);
        out.put("calendar", calendar);
        return out;
    }

    public record ResultIn(@NotBlank String session, @NotNull UUID studentId, @NotNull UUID subjectId, @NotBlank String attempt,
                           java.math.BigDecimal caScore, java.math.BigDecimal examScore, java.math.BigDecimal clinicalScore, java.math.BigDecimal attendancePct) {
    }

    /** one subject's result for one candidate at one attempt, with the attendance the examiner types; the pass is judged by
     *  the rule, never typed (below the examination's minimum attendance the candidate is barred); once every subject has a
     *  result the rule's decision is applied provisionally, for the Board to confirm */
    @PostMapping("/exams/{code}/results")
    @PreAuthorize(EXAMINERS)
    @Transactional
    Map<String, Object> result(@PathVariable String code, @Valid @RequestBody ResultIn body) {
        assertCollegeExaminer();
        Map<String, Object> e = exam(code);
        assertLevel(e.get("level"));
        if (body.attendancePct() != null && (body.attendancePct().signum() < 0 || body.attendancePct().compareTo(java.math.BigDecimal.valueOf(100)) > 0)) {
            throw new DomainRuleViolation("COLLEGE_ATTENDANCE_RANGE", "Attendance is a percentage, 0 to 100.", new DomainRuleViolation.Remedy("Enter it within 0 to 100.", "College Secretary"));
        }
        if (e.get("min_attendance_pct") != null && body.attendancePct() == null && (body.caScore() != null || body.examScore() != null)) {
            throw new DomainRuleViolation("COLLEGE_ATTENDANCE", e.get("name") + " requires attendance of " + e.get("min_attendance_pct") + "%; the candidate's attendance is entered with the marks.",
                    new DomainRuleViolation.Remedy("Enter the attendance percentage.", "College Secretary"));
        }
        String attempt = body.attempt().trim().toUpperCase();
        if (!List.of("FIRST", "RESIT", "REPEAT", "SENATE_APPEAL").contains(attempt)) {
            throw new DomainRuleViolation("COLLEGE_ATTEMPT", "An attempt is the first, a resit, a repeat or a Senate appeal.", new DomainRuleViolation.Remedy("Choose one of the four.", "College Secretary"));
        }
        Map<String, Object> subject = jdbc.sql("SELECT id, name, ca_weight, exam_weight, clinical_component_min FROM college.exam_subject WHERE id = :s AND exam_id = :e")
                .param("s", body.subjectId()).param("e", e.get("id")).query().listOfRows().stream().findFirst()
                .orElseThrow(() -> new DomainRuleViolation("COLLEGE_SUBJECT", "That subject is not one of this examination's.", new DomainRuleViolation.Remedy("Choose from the examination's subjects.", "College Secretary")));
        java.math.BigDecimal caMax = (java.math.BigDecimal) subject.get("ca_weight");
        java.math.BigDecimal exMax = (java.math.BigDecimal) subject.get("exam_weight");
        if (body.caScore() != null && (body.caScore().signum() < 0 || body.caScore().compareTo(caMax) > 0)) {
            throw new DomainRuleViolation("COLLEGE_CA_RANGE", subject.get("name") + ": CA is out of " + caMax.stripTrailingZeros().toPlainString() + ".", new DomainRuleViolation.Remedy("Enter the CA within its weight.", "College Secretary"));
        }
        if (body.examScore() != null && (body.examScore().signum() < 0 || body.examScore().compareTo(exMax) > 0)) {
            throw new DomainRuleViolation("COLLEGE_EXAM_RANGE", subject.get("name") + ": the examination is out of " + exMax.stripTrailingZeros().toPlainString() + ".", new DomainRuleViolation.Remedy("Enter the examination mark within its weight.", "College Secretary"));
        }
        if (subject.get("clinical_component_min") != null && body.clinicalScore() == null && body.examScore() != null) {
            throw new DomainRuleViolation("COLLEGE_CLINICAL", subject.get("name") + " has a clinical component; its mark out of 100 is entered with the examination.", new DomainRuleViolation.Remedy("Enter the clinical component's mark.", "College Secretary"));
        }
        if (body.clinicalScore() != null && (body.clinicalScore().signum() < 0 || body.clinicalScore().compareTo(java.math.BigDecimal.valueOf(100)) > 0)) {
            throw new DomainRuleViolation("COLLEGE_CLINICAL_RANGE", "The clinical component is out of 100.", new DomainRuleViolation.Remedy("Enter it within 0 to 100.", "College Secretary"));
        }
        // the candidate is a member of the cohort — a year at the examination's level in the session — and the cohort's year has reached its end
        long member = jdbc.sql("SELECT count(*) FROM college.cohort(:l, :s) c WHERE c.student_id = :st")
                .param("l", e.get("level")).param("s", body.session()).param("st", body.studentId()).query(Long.class).single();
        if (member == 0) throw new DomainRuleViolation("COLLEGE_NOT_MEMBER", "That student has no " + e.get("level") + " Level year in " + body.session() + ".",
                new DomainRuleViolation.Remedy("A candidate is a student enrolled at the examination's level in that session; open the enrolment from the desk if they registered on paper.", "College Secretary"));
        boolean reached = jdbc.sql("SELECT college.year_reached_final(:l, :s)").param("l", e.get("level")).param("s", body.session()).query(Boolean.class).single();
        if (!reached) throw new DomainRuleViolation("COLLEGE_YEAR_NOT_ENDED", "The " + e.get("level") + " Level year for " + body.session() + " has not reached its final semester; the College's students sit once, at the end of the year.",
                new DomainRuleViolation.Remedy("Results are entered when the final semester has begun, by the College's calendar.", "College Secretary"));
        Map<String, Object> judged = jdbc.sql("SELECT passed, barred FROM college.judge(:s, :ca, :ex, :cl, :at)").param("s", body.subjectId())
                .param("ca", body.caScore(), Types.NUMERIC).param("ex", body.examScore(), Types.NUMERIC).param("cl", body.clinicalScore(), Types.NUMERIC)
                .param("at", body.attendancePct(), Types.NUMERIC).query().singleRow();
        Boolean passed = (Boolean) judged.get("passed");
        boolean barred = Boolean.TRUE.equals(judged.get("barred"));
        UUID id = jdbc.sql("""
                INSERT INTO college.exam_result (student_id, subject_id, session, attempt, ca_score, exam_score, clinical_score, attendance_pct, barred, passed, decided_on)
                VALUES (:st, :s, :ses, :a, :ca, :ex, :cl, :at, :b, :p, CASE WHEN :p IS NULL THEN NULL ELSE current_date END)
                ON CONFLICT (student_id, subject_id, session, attempt) DO UPDATE SET
                       ca_score = EXCLUDED.ca_score, exam_score = EXCLUDED.exam_score, clinical_score = EXCLUDED.clinical_score,
                       attendance_pct = EXCLUDED.attendance_pct, barred = EXCLUDED.barred, passed = EXCLUDED.passed, decided_on = EXCLUDED.decided_on
                RETURNING id
                """).param("st", body.studentId()).param("s", body.subjectId()).param("ses", body.session()).param("a", attempt)
                .param("ca", body.caScore(), Types.NUMERIC).param("ex", body.examScore(), Types.NUMERIC).param("cl", body.clinicalScore(), Types.NUMERIC)
                .param("at", body.attendancePct(), Types.NUMERIC).param("b", barred).param("p", passed, Types.BOOLEAN).query(UUID.class).single();
        // the rule, applied provisionally the moment every subject has a result; a confirmed decision is left alone
        String outcome = jdbc.sql("SELECT college.apply_provisional(:st, :c, :ses)").param("st", body.studentId()).param("c", e.get("code")).param("ses", body.session())
                .query(String.class).optional().orElse(null);
        java.util.Map<String, Object> out = new java.util.LinkedHashMap<>();
        out.put("id", id);
        out.put("passed", passed);
        out.put("barred", barred);
        out.put("distinction", Boolean.TRUE.equals(passed) && body.caScore() != null && body.examScore() != null && body.caScore().add(body.examScore()).compareTo(java.math.BigDecimal.valueOf(70)) >= 0);
        out.put("outcome", outcome);
        return out;
    }

    public record DecisionIn(@NotBlank String session, @NotNull UUID studentId, @NotBlank String outcome, List<String> carryOvers, @Size(max = 200) String ruleRef, @Size(max = 200) String minute) {
    }

    /** the progression decision after an examination: what the rule recommends is shown; the College Academic Board decides */
    @PostMapping("/exams/{code}/decisions")
    @PreAuthorize(DESK)
    @Transactional
    Map<String, Object> decide(@PathVariable String code, @Valid @RequestBody DecisionIn body) {
        Map<String, Object> e = exam(code);
        String outcome = body.outcome().trim().toUpperCase();
        if (!List.of("PROMOTE", "RESIT", "REPEAT", "WITHDRAW_ADVISED", "WITHDRAW_REQUIRED", "APPEAL", "GRADUATE").contains(outcome)) {
            throw new DomainRuleViolation("COLLEGE_OUTCOME", "A decision is promote, resit, repeat, withdrawal advised, withdrawal required, appeal or graduate.", new DomainRuleViolation.Remedy("Choose one of the seven.", "College Secretary"));
        }
        long confirmed = jdbc.sql("SELECT count(*) FROM college.progression_decision WHERE student_id = :st AND session = :ses AND from_level = :l AND state = 'CONFIRMED'")
                .param("st", body.studentId()).param("ses", body.session()).param("l", e.get("level")).query(Long.class).single();
        if (confirmed > 0) {
            throw new DomainRuleViolation("COLLEGE_CONFIRMED", "The Board has confirmed this candidate's decision; it is not changed here.", new DomainRuleViolation.Remedy("A confirmed decision is revisited by the Board on a minute.", "College Secretary"));
        }
        long subjects = jdbc.sql("SELECT count(*) FROM college.exam_subject WHERE exam_id = :e").param("e", e.get("id")).query(Long.class).single();
        long decided = jdbc.sql("""
                SELECT count(DISTINCT r.subject_id) FROM college.exam_result r JOIN college.exam_subject s ON s.id = r.subject_id
                 WHERE r.student_id = :st AND r.session = :ses AND s.exam_id = :e AND r.passed IS NOT NULL
                """).param("st", body.studentId()).param("ses", body.session()).param("e", e.get("id")).query(Long.class).single();
        if (decided < subjects) {
            throw new DomainRuleViolation("COLLEGE_UNDECIDED", "The candidate has a result in " + decided + " of the examination's " + subjects + " subjects; a decision waits on all of them.",
                    new DomainRuleViolation.Remedy("Enter the remaining subjects' results first.", "College Secretary"));
        }
        String[] carry = body.carryOvers() == null ? new String[0] : body.carryOvers().stream().map(String::trim).filter(x -> !x.isEmpty()).toArray(String[]::new);
        UUID id = jdbc.sql("""
                INSERT INTO college.progression_decision (student_id, from_level, session, outcome, carry_overs, rule_ref, minute, state)
                VALUES (:st, :l, :ses, :o, :c, :r, :m, 'PROVISIONAL')
                ON CONFLICT (student_id, from_level, session) DO UPDATE SET outcome = EXCLUDED.outcome, carry_overs = EXCLUDED.carry_overs,
                       rule_ref = coalesce(EXCLUDED.rule_ref, college.progression_decision.rule_ref), minute = coalesce(EXCLUDED.minute, college.progression_decision.minute), decided_on = current_date
                RETURNING id
                """).param("st", body.studentId()).param("l", e.get("level")).param("ses", body.session()).param("o", outcome)
                .param("c", carry).param("r", body.ruleRef(), Types.VARCHAR).param("m", body.minute(), Types.VARCHAR).query(UUID.class).single();
        return Map.of("id", id, "outcome", outcome);
    }

    /** what the rule recommends for a candidate from their latest results: the next attempt, and the courses owed */
    @GetMapping("/exams/{code}/recommend")
    @PreAuthorize(DESK)
    @Transactional(readOnly = true)
    Map<String, Object> recommend(@PathVariable String code, @RequestParam String session, @RequestParam UUID student) {
        Map<String, Object> e = exam(code);
        Map<String, Object> d = jdbc.sql("SELECT outcome, failed, n_subjects, latest_attempt, failed_names, rule_ref FROM college.decide(:st, :c, :ses)")
                .param("st", student).param("c", e.get("code")).param("ses", session).query().listOfRows().stream().findFirst().orElse(Map.of());
        java.util.Map<String, Object> out = new java.util.LinkedHashMap<>();
        out.put("recommend", d.get("outcome") == null ? "INCOMPLETE" : d.get("outcome"));
        out.put("failed", d.getOrDefault("failed", 0));
        out.put("of", d.getOrDefault("n_subjects", 0));
        out.put("latestAttempt", d.getOrDefault("latest_attempt", "FIRST"));
        out.put("failedNames", d.get("failed_names"));
        out.put("ruleRef", d.get("rule_ref"));
        out.put("onFailure", String.valueOf(e.get("on_failure")));
        return out;
    }

    /** the reconciliation the crossing to Senate needs: every candidate accounted for in every subject, or named */
    @GetMapping("/exams/{code}/reconciliation")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> reconciliation(@PathVariable String code, @RequestParam String session) {
        Map<String, Object> e = exam(code);
        List<Map<String, Object>> missing = jdbc.sql("""
                SELECT coalesce(st.matric_no, st.admission_no) AS number, st.surname, st.other_names, s.name AS subject
                  FROM college.cohort(:l, :ses) c JOIN people.student st ON st.id = c.student_id
                  CROSS JOIN college.exam_subject s
                 WHERE c.fully_registered AND s.exam_id = :e
                   AND NOT EXISTS (SELECT 1 FROM college.exam_result r WHERE r.student_id = st.id AND r.subject_id = s.id AND r.session = :ses AND r.passed IS NOT NULL)
                 ORDER BY coalesce(st.matric_no, st.admission_no), s.ordinal
                """).param("l", e.get("level")).param("e", e.get("id")).param("ses", session).query().listOfRows();
        List<Map<String, Object>> undecided = jdbc.sql("""
                SELECT coalesce(st.matric_no, st.admission_no) AS number, st.surname, st.other_names
                  FROM college.cohort(:l, :ses) c JOIN people.student st ON st.id = c.student_id
                 WHERE c.fully_registered
                   AND NOT EXISTS (SELECT 1 FROM college.progression_decision d WHERE d.student_id = st.id AND d.session = :ses AND d.from_level = :l)
                 ORDER BY coalesce(st.matric_no, st.admission_no)
                """).param("l", e.get("level")).param("ses", session).query().listOfRows();
        Map<String, Object> counts = jdbc.sql("""
                SELECT count(DISTINCT r.student_id) AS candidates_with_results,
                       count(*) FILTER (WHERE r.passed) AS subject_passes, count(*) FILTER (WHERE r.passed = false) AS subject_fails,
                       count(*) FILTER (WHERE r.passed AND r.total >= 70) AS distinctions
                  FROM college.exam_result r JOIN college.exam_subject s ON s.id = r.subject_id
                 WHERE r.session = :ses AND s.exam_id = :e AND r.passed IS NOT NULL
                """).param("ses", session).param("e", e.get("id")).query().singleRow();
        Map<String, Object> decisions = jdbc.sql("""
                SELECT count(*) AS decided, count(*) FILTER (WHERE state = 'PROVISIONAL') AS provisional, count(*) FILTER (WHERE state = 'CONFIRMED') AS confirmed,
                       count(*) FILTER (WHERE outcome IN ('PROMOTE','GRADUATE')) AS promoted, count(*) FILTER (WHERE outcome = 'RESIT') AS resits,
                       count(*) FILTER (WHERE outcome = 'REPEAT') AS repeats, count(*) FILTER (WHERE outcome IN ('WITHDRAW_ADVISED','WITHDRAW_REQUIRED')) AS withdrawals, count(*) FILTER (WHERE outcome = 'APPEAL') AS appeals,
                       count(*) FILTER (WHERE outcome = 'GRADUATE' AND honours) AS honours
                  FROM college.progression_decision WHERE session = :ses AND from_level = :l
                """).param("ses", session).param("l", e.get("level")).query().singleRow();
        List<Map<String, Object>> unregistered = jdbc.sql("""
                SELECT coalesce(st.matric_no, st.admission_no) AS number, st.surname, st.other_names, c.semesters, c.semesters_registered
                  FROM college.cohort(:l, :ses) c JOIN people.student st ON st.id = c.student_id
                 WHERE NOT c.fully_registered ORDER BY coalesce(st.matric_no, st.admission_no)
                """).param("l", e.get("level")).param("ses", session).query().listOfRows();
        java.util.Map<String, Object> out = new java.util.LinkedHashMap<>();
        out.put("exam", e);
        out.put("missing", missing);
        out.put("undecided", undecided);
        out.put("unregistered", unregistered);
        out.put("cohort", jdbc.sql("SELECT count(*) FROM college.cohort(:l, :ses)").param("l", e.get("level")).param("ses", session).query(Long.class).single());
        out.put("yearReached", jdbc.sql("SELECT college.year_reached_final(:l, :s)").param("l", e.get("level")).param("s", session).query(Boolean.class).single());
        out.put("counts", counts);
        out.put("decisions", decisions);
        out.put("ready", missing.isEmpty() && undecided.isEmpty() && ((Number) decisions.get("provisional")).intValue() == 0);
        return out;
    }

    public record ConfirmIn(@NotBlank String session, @NotBlank @Size(max = 200) String minute) {
    }

    /** the College Academic Board's act: every provisional decision of the examination in the session confirmed on its minute,
     *  and each student moved — the next level, the resit, the repeat year, the withdrawal, graduation with or without Honours */
    @PostMapping("/exams/{code}/confirm")
    @PreAuthorize(DESK)
    @Transactional
    Map<String, Object> confirm(@PathVariable String code, @Valid @RequestBody ConfirmIn body) {
        Map<String, Object> e = exam(code);
        int n = jdbc.sql("SELECT college.confirm_decisions(:c, :ses, :m)").param("c", e.get("code")).param("ses", body.session()).param("m", body.minute().trim()).query(Integer.class).single();
        return Map.of("confirmed", n);
    }

    public record AppealIn(@NotBlank String session, @NotNull UUID studentId, @NotBlank @Size(max = 200) String minute) {
    }

    /** Senate's approval of an appeal after the Final: the fourth and final attempt at 600 Level opens for the session named */
    @PostMapping("/exams/{code}/appeals")
    @PreAuthorize(DESK)
    @Transactional
    Map<String, Object> grantAppeal(@PathVariable String code, @Valid @RequestBody AppealIn body) {
        Map<String, Object> e = exam(code);
        if (!Boolean.TRUE.equals(e.get("appeal_to_senate"))) {
            throw new DomainRuleViolation("COLLEGE_NO_APPEAL", e.get("name") + " carries no appeal to Senate.", new DomainRuleViolation.Remedy("An appeal follows the Final MBBS only.", "College Secretary"));
        }
        UUID id = jdbc.sql("SELECT college.grant_appeal(:st, :ses, :m)").param("st", body.studentId()).param("ses", body.session()).param("m", body.minute().trim()).query(UUID.class).single();
        return Map.of("enrolmentId", id);
    }

    public record EnrolIn(@NotBlank String number, @NotBlank String session, @NotNull Integer level) {
    }

    /** the desk opens a student's College year for a cohort — a paper registration, a transfer — so the candidate list is complete */
    @PostMapping("/enrol")
    @PreAuthorize(DESK_OR_COORDINATOR)
    @Transactional
    Map<String, Object> enrol(@Valid @RequestBody EnrolIn body) {
        assertLevel(body.level());
        UUID student = jdbc.sql("SELECT id FROM people.student WHERE upper(coalesce(matric_no, '')) = upper(:n) OR upper(admission_no) = upper(:n)")
                .param("n", body.number().trim()).query(UUID.class).optional()
                .orElseThrow(() -> new NotFound("student", body.number()));
        UUID id = jdbc.sql("SELECT college.open_enrolment(:st, :l, :s, :by)").param("st", student).param("l", body.level()).param("s", body.session().trim())
                .param("by", scope.actorId(), Types.OTHER).query(UUID.class).single();
        return Map.of("enrolmentId", id, "studentId", student);
    }

    /** the College's calendar for a session: each level's semesters, dated by the College (the prospectus gives lengths, never dates) */
    @GetMapping("/calendar")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> calendar(@RequestParam String session) {
        List<Map<String, Object>> rows = jdbc.sql("""
                SELECT l.level, l.phase, t.ordinal, coalesce(t.name, CASE t.ordinal WHEN 1 THEN l.level || ' Level, first half of the year' ELSE l.level || ' Level, second half of the year' END) AS name,
                       coalesce(s.length_weeks, t.length_weeks) AS length_weeks, s.starts_on, s.ends_on, t.subjects
                  FROM college.level l
                  CROSS JOIN LATERAL (SELECT t.ordinal, t.name, t.length_weeks, t.subjects FROM college.semester_template t WHERE t.level = l.level
                                      UNION ALL SELECT o, NULL, NULL, NULL FROM generate_series(1, 2) o WHERE NOT EXISTS (SELECT 1 FROM college.semester_template t2 WHERE t2.level = l.level)) t
                  LEFT JOIN college.semester s ON s.level = l.level AND s.session = :s AND s.ordinal = t.ordinal
                 WHERE l.level >= 200 ORDER BY l.level, t.ordinal
                """).param("s", session).query().listOfRows();
        return Map.of("session", session, "rows", rows);
    }

    public record CalendarIn(@NotBlank String session, @NotNull Integer level, @NotNull Integer ordinal, LocalDate startsOn, LocalDate endsOn, Integer lengthWeeks) {
    }

    /** one semester of one level dated for the session; cleared when both dates are blank */
    @PutMapping("/calendar")
    @PreAuthorize(DESK)
    @Transactional
    Map<String, Object> setCalendar(@Valid @RequestBody CalendarIn body) {
        if (body.startsOn() == null && body.endsOn() == null) {
            jdbc.sql("DELETE FROM college.semester WHERE session = :s AND level = :l AND ordinal = :o").param("s", body.session()).param("l", body.level()).param("o", body.ordinal()).update();
            return Map.of("cleared", true);
        }
        if (body.startsOn() != null && body.endsOn() != null && !body.endsOn().isAfter(body.startsOn())) {
            throw new DomainRuleViolation("COLLEGE_CALENDAR", "A semester ends after it starts.", new DomainRuleViolation.Remedy("Enter an end date after the start.", "College Secretary"));
        }
        Integer weeks = body.lengthWeeks() != null ? body.lengthWeeks()
                : jdbc.sql("SELECT length_weeks FROM college.semester_template WHERE level = :l AND ordinal = :o").param("l", body.level()).param("o", body.ordinal()).query(Integer.class).optional().orElse(17);
        jdbc.sql("""
                INSERT INTO college.semester (session, level, ordinal, length_weeks, starts_on, ends_on) VALUES (:s, :l, :o, :w, :a, :z)
                ON CONFLICT (session, level, ordinal) DO UPDATE SET length_weeks = EXCLUDED.length_weeks, starts_on = EXCLUDED.starts_on, ends_on = EXCLUDED.ends_on
                """).param("s", body.session()).param("l", body.level()).param("o", body.ordinal()).param("w", weeks).param("a", body.startsOn(), Types.DATE).param("z", body.endsOn(), Types.DATE).update();
        return Map.of("saved", true);
    }

    /** the CA collected during a year — course tests, end-of-posting scores — kept as they happen, graded never; the examiner composes the year's CA from them */
    @GetMapping("/assessments")
    @PreAuthorize(EXAMINERS)
    @Transactional(readOnly = true)
    Map<String, Object> assessments(@RequestParam UUID student, @RequestParam String exam) {
        Map<String, Object> e = exam(exam);
        assertLevel(e.get("level"));
        List<Map<String, Object>> items = jdbc.sql("""
                SELECT i.id, i.subject_id, s.name AS subject, i.item_type, i.name, i.max_score, i.eligibility_gate, i.note
                  FROM college.assessment_item i JOIN college.exam_subject s ON s.id = i.subject_id WHERE s.exam_id = :e ORDER BY s.ordinal, i.name
                """).param("e", e.get("id")).query().listOfRows();
        List<Map<String, Object>> scores = jdbc.sql("""
                SELECT sc.id, sc.item_id, sc.attempt_no, sc.score, sc.scored_on, i.name AS item, s.name AS subject, i.max_score
                  FROM college.assessment_score sc JOIN college.assessment_item i ON i.id = sc.item_id JOIN college.exam_subject s ON s.id = i.subject_id
                 WHERE sc.student_id = :st AND s.exam_id = :e ORDER BY s.ordinal, i.name, sc.attempt_no
                """).param("st", student).param("e", e.get("id")).query().listOfRows();
        return Map.of("items", items, "scores", scores);
    }

    public record AssessmentIn(@NotNull UUID studentId, @NotNull UUID itemId, @NotNull java.math.BigDecimal score, Integer attemptNo) {
    }

    @PostMapping("/assessments")
    @PreAuthorize(EXAMINERS)
    @Transactional
    Map<String, Object> assess(@Valid @RequestBody AssessmentIn body) {
        assertCollegeExaminer();
        java.math.BigDecimal max = jdbc.sql("SELECT max_score FROM college.assessment_item WHERE id = :i").param("i", body.itemId()).query(java.math.BigDecimal.class).optional()
                .orElseThrow(() -> new NotFound("assessment item", body.itemId().toString()));
        if (body.score().signum() < 0 || body.score().compareTo(max) > 0) {
            throw new DomainRuleViolation("COLLEGE_CA_RANGE", "The score is out of " + max.stripTrailingZeros().toPlainString() + ".", new DomainRuleViolation.Remedy("Enter it within the item's maximum.", "College Secretary"));
        }
        int attempt = body.attemptNo() == null ? 1 : body.attemptNo();
        UUID id = jdbc.sql("""
                INSERT INTO college.assessment_score (student_id, item_id, attempt_no, score, assessor_id) VALUES (:st, :i, :a, :sc, :by)
                ON CONFLICT (student_id, item_id, attempt_no) DO UPDATE SET score = EXCLUDED.score, assessor_id = EXCLUDED.assessor_id, scored_on = current_date
                RETURNING id
                """).param("st", body.studentId()).param("i", body.itemId()).param("a", attempt).param("sc", body.score()).param("by", scope.actorId(), Types.OTHER).query(UUID.class).single();
        return Map.of("id", id);
    }

    public record SheetMark(@NotNull UUID subjectId, java.math.BigDecimal caScore, java.math.BigDecimal examScore, java.math.BigDecimal clinicalScore, java.math.BigDecimal attendancePct) {
    }
    public record SheetRow(@NotBlank String number, @NotEmpty List<SheetMark> marks) {
    }
    public record SheetIn(@NotBlank String session, @NotEmpty @Size(max = 1000) List<SheetRow> rows) {
    }

    /** the level's score sheet, uploaded: every row a cohort member by number, every mark judged by the rule as it is saved, the
     *  rule's decision applied provisionally where a candidate's subjects are then all resulted; a row that cannot be saved is
     *  named and the rest go in — nothing is half-saved within a row */
    @PostMapping("/exams/{code}/results/bulk")
    @PreAuthorize(EXAMINERS)
    @Transactional
    Map<String, Object> bulk(@PathVariable String code, @Valid @RequestBody SheetIn body) {
        assertCollegeExaminer();
        Map<String, Object> e = exam(code);
        assertLevel(e.get("level"));
        boolean reached = jdbc.sql("SELECT college.year_reached_final(:l, :s)").param("l", e.get("level")).param("s", body.session()).query(Boolean.class).single();
        if (!reached) throw new DomainRuleViolation("COLLEGE_YEAR_NOT_ENDED", "The " + e.get("level") + " Level year for " + body.session() + " has not reached its final semester; the College's students sit once, at the end of the year.",
                new DomainRuleViolation.Remedy("Results are entered when the final semester has begun, by the College's calendar.", "College Secretary"));
        List<Map<String, Object>> cohort = jdbc.sql("""
                SELECT c.student_id, upper(coalesce(st.matric_no, st.admission_no)) AS number, c.fully_registered
                  FROM college.cohort(:l, :s) c JOIN people.student st ON st.id = c.student_id
                """).param("l", e.get("level")).param("s", body.session()).query().listOfRows();
        Map<String, Map<String, Object>> byNumber = new java.util.HashMap<>();
        for (Map<String, Object> c : cohort) byNumber.put(String.valueOf(c.get("number")), c);
        List<Map<String, Object>> problems = new java.util.ArrayList<>();
        List<Map<String, Object>> saved = new java.util.ArrayList<>();
        for (SheetRow row : body.rows()) {
            String number = row.number().trim().toUpperCase();
            Map<String, Object> c = byNumber.get(number);
            if (c == null) { problems.add(Map.of("number", number, "problem", "not in the " + e.get("level") + " Level cohort for " + body.session())); continue; }
            UUID student = (UUID) c.get("student_id");
            String attempt = jdbc.sql("SELECT college.attempt_of(:st, :l, :s)").param("st", student).param("l", e.get("level")).param("s", body.session()).query(String.class).single();
            // each row in its own savepoint: a refused mark undoes that row's marks alone, and the rest of the sheet goes in
            org.springframework.transaction.support.TransactionTemplate nested = new org.springframework.transaction.support.TransactionTemplate(transactions);
            nested.setPropagationBehavior(org.springframework.transaction.TransactionDefinition.PROPAGATION_NESTED);
            try {
                String outcome = nested.execute(status -> {
                    for (SheetMark m : row.marks()) {
                        if (m.caScore() == null && m.examScore() == null) continue;
                        result(code, new ResultIn(body.session(), student, m.subjectId(), attempt, m.caScore(), m.examScore(), m.clinicalScore(), m.attendancePct()));
                    }
                    return jdbc.sql("SELECT outcome FROM college.progression_decision WHERE student_id = :st AND from_level = :l AND session = :s")
                            .param("st", student).param("l", e.get("level")).param("s", body.session()).query(String.class).optional().orElse("");
                });
                saved.add(Map.of("number", number, "outcome", outcome == null ? "" : outcome, "registered", Boolean.TRUE.equals(c.get("fully_registered"))));
            } catch (DomainRuleViolation v) {
                problems.add(Map.of("number", number, "problem", v.getMessage()));
            } catch (org.springframework.dao.DataAccessException v) {
                problems.add(Map.of("number", number, "problem", v.getMostSpecificCause().getMessage()));
            }
        }
        if (saved.isEmpty() && !problems.isEmpty()) {
            throw new DomainRuleViolation("COLLEGE_SHEET_REFUSED", "No row of the sheet could be saved: " + problems.get(0).get("number") + " — " + problems.get(0).get("problem") + (problems.size() > 1 ? ", and " + (problems.size() - 1) + " more" : ""),
                    new DomainRuleViolation.Remedy("Correct the sheet and upload it again.", "College Secretary"));
        }
        java.util.Map<String, Object> out = new java.util.LinkedHashMap<>();
        out.put("saved", saved);
        out.put("problems", problems);
        return out;
    }

    /** the MBBS Coordinator's own summary: the level held, its examination, the cohorts with years open or closed, and what each waits on */
    @GetMapping("/coordinator")
    @PreAuthorize(EXAMINERS)
    @Transactional(readOnly = true)
    Map<String, Object> coordinator(@RequestParam(required = false) Integer level) {
        Integer mine = scope.actingLevel();
        Integer L = mine != null ? mine : level;
        if (L == null) throw new DomainRuleViolation("COLLEGE_NO_LEVEL", "No level: the coordinatorship names none, and none was asked for.", new DomainRuleViolation.Remedy("Ask the Registry to bound the grant to a level.", "Registry"));
        Map<String, Object> e = jdbc.sql("SELECT id, code, name, level, papers, min_attendance_pct, on_failure, resit_allowed, appeal_to_senate FROM college.professional_exam WHERE level = :l")
                .param("l", L).query().listOfRows().stream().findFirst().orElse(Map.of());
        List<Map<String, Object>> cohorts = jdbc.sql("""
                SELECT e.session, count(*) AS students, count(*) FILTER (WHERE e.registered_at IS NOT NULL) AS registered,
                       count(*) FILTER (WHERE e.state = 'OPEN') AS open, count(*) FILTER (WHERE e.state = 'RESIT') AS resit, count(*) FILTER (WHERE e.state = 'CLOSED') AS closed,
                       (SELECT count(DISTINCT r.student_id) FROM college.exam_result r JOIN college.exam_subject s ON s.id = r.subject_id JOIN college.professional_exam x ON x.id = s.exam_id
                         WHERE x.level = e.level AND r.session = e.session AND r.passed IS NOT NULL) AS with_results,
                       (SELECT count(*) FROM college.progression_decision d WHERE d.from_level = e.level AND d.session = e.session AND d.state = 'PROVISIONAL') AS provisional,
                       (SELECT count(*) FROM college.progression_decision d WHERE d.from_level = e.level AND d.session = e.session AND d.state = 'CONFIRMED') AS confirmed,
                       college.year_reached_final(e.level, e.session) AS year_reached_final,
                       (SELECT min(cs.starts_on) FROM college.semester cs WHERE cs.level = e.level AND cs.session = e.session) AS year_starts_on,
                       (SELECT max(cs.ends_on) FROM college.semester cs WHERE cs.level = e.level AND cs.session = e.session) AS year_ends_on
                  FROM college.enrolment e WHERE e.level = :l GROUP BY e.level, e.session ORDER BY e.session DESC
                """).param("l", L).query().listOfRows();
        String dept = jdbc.sql("SELECT iam.college_lecturer_dept(:p)").param("p", scope.actorId()).query(String.class).optional().orElse(null);
        java.util.Map<String, Object> out = new java.util.LinkedHashMap<>();
        out.put("level", L);
        out.put("exam", e);
        out.put("cohorts", cohorts);
        out.put("department", dept);
        out.put("nextSession", jdbc.sql("SELECT college.level_session(:l)").param("l", L).query(String.class).single());
        return out;
    }

    /** the College overview: every level with its students, open years and cohorts, its examination and where its decisions stand;
     *  the session's postings; the blocks — the live picture the College's officers open the module on */
    @GetMapping("/overview")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> overview() {
        String session = jdbc.sql("SELECT name FROM policy.academic_session WHERE state = 'CURRENT'").query(String.class).optional()
                .orElseGet(() -> jdbc.sql("SELECT name FROM policy.academic_session ORDER BY name DESC LIMIT 1").query(String.class).single());
        List<Map<String, Object>> levels = jdbc.sql("""
                SELECT l.level, l.phase, l.enrolment,
                       (SELECT count(*) FROM people.student st JOIN ref.programme p ON p.code = st.programme_code JOIN ref.faculty f ON f.code = p.faculty_code
                         WHERE f.college_code = 'CHS' AND st.current_level = l.level AND st.status IN ('ACTIVE','PROBATION','ADMITTED')) AS students,
                       (SELECT count(*) FROM college.enrolment e WHERE e.level = l.level AND e.state IN ('OPEN','RESIT')) AS open_years,
                       (SELECT string_agg(DISTINCT e.session, ', ' ORDER BY e.session) FROM college.enrolment e WHERE e.level = l.level AND e.state IN ('OPEN','RESIT')) AS cohorts,
                       x.code AS exam_code, x.name AS exam_name,
                       (SELECT count(*) FROM college.progression_decision d WHERE d.from_level = l.level AND d.state = 'PROVISIONAL') AS provisional,
                       (SELECT count(*) FROM college.progression_decision d WHERE d.from_level = l.level AND d.session = :s AND d.state = 'CONFIRMED') AS confirmed,
                       (SELECT count(*) FROM college.semester cs WHERE cs.level = l.level AND cs.session = :s AND cs.starts_on IS NOT NULL) AS dated
                  FROM college.level l LEFT JOIN college.professional_exam x ON x.level = l.level
                 ORDER BY l.level
                """).param("s", session).query().listOfRows();
        Map<String, Object> totals = jdbc.sql("""
                SELECT (SELECT count(*) FROM people.student st JOIN ref.programme p ON p.code = st.programme_code JOIN ref.faculty f ON f.code = p.faculty_code
                         WHERE f.college_code = 'CHS' AND st.status IN ('ACTIVE','PROBATION','ADMITTED')) AS students,
                       (SELECT count(*) FROM college.enrolment e WHERE e.state IN ('OPEN','RESIT')) AS open_years,
                       (SELECT count(*) FROM college.progression_decision d WHERE d.state = 'PROVISIONAL') AS provisional,
                       (SELECT count(*) FROM college.posting_allocation a WHERE a.session = :s) AS allocations,
                       (SELECT count(*) FROM college.block) AS blocks, (SELECT count(*) FROM college.posting) AS postings,
                       (SELECT count(*) FROM iam.office_assignment a WHERE a.office_code = 'mbbscoordinator' AND a.valid_from <= current_date AND (a.valid_to IS NULL OR a.valid_to >= current_date)) AS coordinators
                """).param("s", session).query().singleRow();
        List<Map<String, Object>> blocks = jdbc.sql("""
                SELECT b.code, b.name, b.total_weeks, b.ordinal, count(p.id) AS postings,
                       string_agg(p.code, ', ' ORDER BY p.ordinal) AS posting_codes,
                       (SELECT count(*) FROM college.posting_allocation a JOIN college.posting p2 ON p2.id = a.posting_id WHERE p2.block_id = b.id AND a.session = :s) AS allocated
                  FROM college.block b LEFT JOIN college.posting p ON p.block_id = b.id
                 GROUP BY b.id, b.code, b.name, b.total_weeks, b.ordinal ORDER BY b.ordinal
                """).param("s", session).query().listOfRows();
        java.util.Map<String, Object> out = new java.util.LinkedHashMap<>();
        out.put("session", session);
        out.put("levels", levels);
        out.put("totals", totals);
        out.put("blocks", blocks);
        return out;
    }

    /** the College officers' dashboard: what waits on the College — decisions for the Board, results at the end of a year, cohorts
     *  not fully registered, undated calendars, appeals with Senate, levels without a coordinator — the fees position by level
     *  this session, and the decisions confirmed most recently */
    @GetMapping("/dashboard")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> dashboard() {
        String session = jdbc.sql("SELECT name FROM policy.academic_session WHERE state = 'CURRENT'").query(String.class).optional()
                .orElseGet(() -> jdbc.sql("SELECT name FROM policy.academic_session ORDER BY name DESC LIMIT 1").query(String.class).single());
        List<Map<String, Object>> waiting = new java.util.ArrayList<>();
        for (Map<String, Object> r : jdbc.sql("""
                SELECT x.code AS exam, d.from_level AS level, d.session, count(*) AS n FROM college.progression_decision d JOIN college.professional_exam x ON x.level = d.from_level
                 WHERE d.state = 'PROVISIONAL' GROUP BY x.code, d.from_level, d.session ORDER BY d.session, d.from_level
                """).query().listOfRows()) {
            long n = ((Number) r.get("n")).longValue();
            waiting.add(Map.of("kind", "board", "level", r.get("level"), "session", r.get("session"), "exam", r.get("exam"), "count", n,
                    "text", n + " provisional decision" + (n == 1 ? "" : "s") + " on the " + r.get("exam") + " (" + r.get("session") + " cohort) await the College Academic Board",
                    "href", "/college/examinations?exam=" + r.get("exam") + "&session=" + r.get("session")));
        }
        for (Map<String, Object> r : jdbc.sql("""
                SELECT x.code AS exam, e.level, e.session, count(*) AS n
                  FROM college.enrolment e JOIN college.professional_exam x ON x.level = e.level
                 WHERE e.state IN ('OPEN','RESIT') AND e.registered_at IS NOT NULL AND college.year_reached_final(e.level, e.session)
                   AND EXISTS (SELECT 1 FROM college.exam_subject s WHERE s.exam_id = x.id
                                AND NOT EXISTS (SELECT 1 FROM college.exam_result r WHERE r.student_id = e.student_id AND r.subject_id = s.id AND r.session = e.session AND r.passed IS NOT NULL))
                 GROUP BY x.code, e.level, e.session ORDER BY e.session, e.level
                """).query().listOfRows()) {
            long n = ((Number) r.get("n")).longValue();
            waiting.add(Map.of("kind", "results", "level", r.get("level"), "session", r.get("session"), "exam", r.get("exam"), "count", n,
                    "text", n + " candidate" + (n == 1 ? "" : "s") + " at the end of the " + r.get("level") + " Level year (" + r.get("session") + ") still without a result in every subject of the " + r.get("exam"),
                    "href", "/college/scoresheets?session=" + r.get("session") + "&level=" + r.get("level")));
        }
        for (Map<String, Object> r : jdbc.sql("""
                SELECT e.level, e.session, count(*) AS n FROM college.enrolment e
                 WHERE e.state IN ('OPEN','RESIT') AND e.registered_at IS NULL GROUP BY e.level, e.session ORDER BY e.session, e.level
                """).query().listOfRows()) {
            long n = ((Number) r.get("n")).longValue();
            waiting.add(Map.of("kind", "registration", "level", r.get("level"), "session", r.get("session"), "count", n,
                    "text", n + " student" + (n == 1 ? "" : "s") + " at " + r.get("level") + " Level (" + r.get("session") + ") with a year open but not fully registered",
                    "href", "/college/examinations?session=" + r.get("session")));
        }
        for (Map<String, Object> r : jdbc.sql("""
                SELECT l.level FROM college.level l WHERE l.level >= 200
                   AND EXISTS (SELECT 1 FROM college.enrolment e WHERE e.level = l.level AND e.state IN ('OPEN','RESIT'))
                   AND NOT EXISTS (SELECT 1 FROM college.semester cs WHERE cs.level = l.level AND cs.session = :s AND cs.starts_on IS NOT NULL)
                 ORDER BY l.level
                """).param("s", session).query().listOfRows()) {
            waiting.add(Map.of("kind", "calendar", "level", r.get("level"), "session", session,
                    "text", r.get("level") + " Level has years open but no dated semester for " + session + "; the year's end and the results guard stay unknown",
                    "href", "/college/calendar?session=" + session));
        }
        long appeals = jdbc.sql("""
                SELECT count(*) FROM college.progression_decision d WHERE d.state = 'CONFIRMED' AND d.outcome = 'APPEAL'
                   AND NOT EXISTS (SELECT 1 FROM college.enrolment e WHERE e.student_id = d.student_id AND e.level = 600 AND e.kind = 'APPEAL')
                """).query(Long.class).single();
        if (appeals > 0) waiting.add(Map.of("kind", "appeal", "count", appeals, "text", appeals + " appeal" + (appeals == 1 ? "" : "s") + " after the Final MBBS with Senate, awaiting its minute", "href", "/college/examinations?exam=PE4"));
        for (Map<String, Object> r : jdbc.sql("""
                SELECT l.level FROM college.level l WHERE l.level >= 200
                   AND NOT EXISTS (SELECT 1 FROM iam.office_assignment a WHERE a.office_code = 'mbbscoordinator' AND a.scope_id = l.level::text
                                    AND a.valid_from <= current_date AND (a.valid_to IS NULL OR a.valid_to >= current_date))
                 ORDER BY l.level
                """).query().listOfRows()) {
            waiting.add(Map.of("kind", "coordinator", "level", r.get("level"), "text", r.get("level") + " Level has no MBBS Coordinator appointed", "href", "/people"));
        }
        List<Map<String, Object>> fees = jdbc.sql("""
                SELECT st.current_level AS level, count(*) AS students,
                       count(*) FILTER (WHERE finance.semester_cleared(st.id, :s, 1)) AS first_cleared,
                       count(*) FILTER (WHERE finance.semester_cleared(st.id, :s, 2)) AS second_cleared,
                       count(*) FILTER (WHERE EXISTS (SELECT 1 FROM college.enrolment e WHERE e.student_id = st.id AND e.state IN ('OPEN','RESIT') AND e.registered_at IS NOT NULL)) AS registered
                  FROM people.student st JOIN ref.programme p ON p.code = st.programme_code JOIN ref.faculty f ON f.code = p.faculty_code
                 WHERE f.college_code = 'CHS' AND st.status IN ('ACTIVE','PROBATION','ADMITTED') AND st.current_level >= 200
                 GROUP BY st.current_level ORDER BY st.current_level
                """).param("s", session).query().listOfRows();
        List<Map<String, Object>> recent = jdbc.sql("""
                SELECT coalesce(st.matric_no, st.admission_no) AS number, st.surname, st.other_names, d.from_level AS level, d.session, d.outcome, d.honours, d.confirmed_on, d.minute
                  FROM college.progression_decision d JOIN people.student st ON st.id = d.student_id
                 WHERE d.state = 'CONFIRMED' ORDER BY d.confirmed_on DESC NULLS LAST, d.decided_on DESC LIMIT 12
                """).query().listOfRows();
        Map<String, Object> totals = jdbc.sql("""
                SELECT (SELECT count(*) FROM people.student st JOIN ref.programme p ON p.code = st.programme_code JOIN ref.faculty f ON f.code = p.faculty_code
                         WHERE f.college_code = 'CHS' AND st.status IN ('ACTIVE','PROBATION','ADMITTED')) AS students,
                       (SELECT count(*) FROM college.enrolment e WHERE e.state IN ('OPEN','RESIT')) AS open_years,
                       (SELECT count(*) FROM college.progression_decision d WHERE d.state = 'PROVISIONAL') AS provisional,
                       (SELECT count(*) FROM college.posting_allocation a WHERE a.session = :s) AS allocations
                """).param("s", session).query().singleRow();
        java.util.Map<String, Object> out = new java.util.LinkedHashMap<>();
        out.put("session", session);
        out.put("totals", totals);
        out.put("waiting", waiting);
        out.put("fees", fees);
        out.put("recent", recent);
        return out;
    }

    /* ── the student's own record: the journey by level, the fees, the registration, the results, the decisions ── */

    @GetMapping("/my-record")
    @PreAuthorize(STUDENT)
    @Transactional(readOnly = true)
    Map<String, Object> myRecord(Authentication auth) {
        UUID me = UUID.fromString(auth.getName());
        Map<String, Object> st = jdbc.sql("""
                SELECT st.id, coalesce(st.matric_no, st.admission_no) AS number, st.surname, st.other_names, st.programme_code, p.name AS programme,
                       st.entry_mode, st.entry_session, st.entry_level, st.current_level, st.status, f.college_code
                  FROM people.student st JOIN ref.programme p ON p.code = st.programme_code JOIN ref.faculty f ON f.code = p.faculty_code
                 WHERE st.id = :me
                """).param("me", me).query().listOfRows().stream().findFirst().orElseThrow(() -> new NotFound("student", me.toString()));
        if (!"CHS".equals(st.get("college_code"))) {
            throw new DomainRuleViolation("COLLEGE_NOT_MEMBER", "This record is not the College of Health Sciences'.", new DomainRuleViolation.Remedy("The College's journey is the MBBS student's.", "College Secretary"));
        }
        String session = jdbc.sql("SELECT name FROM policy.academic_session WHERE state = 'CURRENT'").query(String.class).optional()
                .orElseGet(() -> jdbc.sql("SELECT name FROM policy.academic_session ORDER BY name DESC LIMIT 1").query(String.class).single());
        int level = ((Number) st.get("current_level")).intValue();
        List<Map<String, Object>> exams = jdbc.sql("SELECT id, code, name, level, papers, resit_allowed, resit_window_months, no_resit_if_all_failed, appeal_to_senate, min_attendance_pct, on_failure FROM college.professional_exam ORDER BY ordinal").query().listOfRows();
        List<Map<String, Object>> enrolments = jdbc.sql("""
                SELECT e.id, e.level, e.session, e.attempt_no, e.kind, e.state, e.registered_at, e.registered_items,
                       finance.semester_cleared(e.student_id, e.session, 1) AS first_cleared, finance.semester_cleared(e.student_id, e.session, 2) AS second_cleared,
                       (SELECT string_agg(s.name, ', ' ORDER BY s.ordinal) FROM college.exam_subject s WHERE s.id = ANY(e.resit_subjects)) AS resit_names,
                       coalesce((SELECT jsonb_agg(jsonb_build_object('ordinal', sm.ordinal, 'name', sm.name, 'length_weeks', sm.length_weeks, 'subjects', sm.subjects,
                                                                     'registered_at', sm.registered_at, 'cleared', finance.semester_cleared(e.student_id, e.session, sm.ordinal),
                                                                     'starts_on', cs.starts_on, 'ends_on', cs.ends_on) ORDER BY sm.ordinal)
                                   FROM college.enrolment_semester sm LEFT JOIN college.semester cs ON cs.session = e.session AND cs.level = e.level AND cs.ordinal = sm.ordinal
                                  WHERE sm.enrolment_id = e.id), '[]'::jsonb)::text AS semesters,
                       (SELECT max(cs.ends_on) FROM college.semester cs WHERE cs.session = e.session AND cs.level = e.level) AS year_ends_on,
                       college.year_reached_final(e.level, e.session) AS year_reached_final
                  FROM college.enrolment e WHERE e.student_id = :me ORDER BY e.session, e.level, e.attempt_no
                """).param("me", me).query().listOfRows();
        List<Map<String, Object>> results = jdbc.sql("""
                SELECT r.session, ex.level, ex.code AS exam, s.name AS subject, s.ordinal, r.attempt, r.ca_score AS ca, r.exam_score AS exam_score, r.clinical_score AS clinical,
                       r.attendance_pct AS attendance, r.barred, r.total, r.passed, r.total >= 70 AND r.passed AS distinction
                  FROM college.exam_result r JOIN college.exam_subject s ON s.id = r.subject_id JOIN college.professional_exam ex ON ex.id = s.exam_id
                 WHERE r.student_id = :me ORDER BY r.session, ex.level, CASE r.attempt WHEN 'FIRST' THEN 1 WHEN 'RESIT' THEN 2 WHEN 'REPEAT' THEN 3 ELSE 4 END, s.ordinal
                """).param("me", me).query().listOfRows();
        List<Map<String, Object>> decisions = jdbc.sql("""
                SELECT d.from_level AS level, d.session, d.outcome, d.state, d.rule_ref, d.minute, d.decided_on, d.confirmed_on, d.honours, d.carry_overs,
                       (SELECT string_agg(s.name, ', ' ORDER BY s.ordinal) FROM college.exam_subject s WHERE s.id = ANY(d.resit_subjects)) AS resit_names
                  FROM college.progression_decision d WHERE d.student_id = :me ORDER BY d.session, d.from_level
                """).param("me", me).query().listOfRows();
        Map<String, Object> level100 = jdbc.sql("SELECT outcome, failed, carried, published, registered FROM college.decide_100(:me)").param("me", me).query().listOfRows().stream().findFirst().orElse(Map.of());
        List<Map<String, Object>> carry = jdbc.sql("SELECT code, from_session, note, cleared_on FROM college.carry_over WHERE student_id = :me ORDER BY code").param("me", me).query().listOfRows();
        // the current year is the open enrolment, whatever the University's session; a new year opens in the session the College dated for the level
        Map<String, Object> current = enrolments.stream().filter(x -> List.of("OPEN", "RESIT").contains(String.valueOf(x.get("state")))).reduce((a, b) -> b).orElse(null);
        String nextSession = jdbc.sql("SELECT college.level_session(:l)").param("l", level).query(String.class).single();
        String feeSession = current != null ? String.valueOf(current.get("session")) : nextSession;
        Map<String, Object> fees = jdbc.sql("SELECT :s AS session, finance.semester_cleared(:me, :s, 1) AS first_cleared, finance.semester_cleared(:me, :s, 2) AS second_cleared")
                .param("me", me).param("s", feeSession).query().singleRow();
        boolean active = List.of("ACTIVE", "PROBATION", "ADMITTED").contains(String.valueOf(st.get("status")));
        // what the next registration is: the year's next semester, or a clinical year whole, or the year to open — and whether its fees are cleared
        java.util.Map<String, Object> next = null;
        if (active && level >= 200) {
            if (current == null) {
                boolean clinical = jdbc.sql("SELECT count(*) = 0 FROM college.semester_template WHERE level = :l").param("l", level).query(Boolean.class).single();
                String name = clinical ? level + " Level year" : jdbc.sql("SELECT name FROM college.semester_template WHERE level = :l AND ordinal = 1").param("l", level).query(String.class).single();
                next = new java.util.LinkedHashMap<>(Map.of("kind", clinical ? "year" : "semester", "ordinal", 1, "name", name, "session", nextSession, "cleared", Boolean.TRUE.equals(fees.get("first_cleared"))));
            } else if (((Number) current.get("level")).intValue() == level) {
                Map<String, Object> sem = jdbc.sql("""
                        SELECT sm.ordinal, sm.name, finance.semester_cleared(:me, :s, sm.ordinal) AS cleared FROM college.enrolment_semester sm
                         WHERE sm.enrolment_id = :e AND sm.registered_at IS NULL ORDER BY sm.ordinal LIMIT 1
                        """).param("me", me).param("s", feeSession).param("e", current.get("id")).query().listOfRows().stream().findFirst().orElse(null);
                if (sem != null) next = new java.util.LinkedHashMap<>(Map.of("kind", "semester", "ordinal", sem.get("ordinal"), "name", sem.get("name"), "session", feeSession, "cleared", Boolean.TRUE.equals(sem.get("cleared"))));
                else if (current.get("registered_at") == null) next = new java.util.LinkedHashMap<>(Map.of("kind", "year", "ordinal", 1, "name", level + " Level year", "session", feeSession, "cleared", Boolean.TRUE.equals(fees.get("first_cleared"))));
            }
        }
        java.util.Map<String, Object> out = new java.util.LinkedHashMap<>();
        out.put("student", st);
        out.put("session", session);
        out.put("exams", exams);
        out.put("enrolments", enrolments);
        out.put("results", results);
        out.put("decisions", decisions);
        out.put("level100", level100);
        out.put("carryOvers", carry);
        out.put("fees", fees);
        out.put("current", current);
        out.put("nextSession", nextSession);
        out.put("next", next);
        out.put("canRegister", next != null && Boolean.TRUE.equals(next.get("cleared")));
        return out;
    }

    public record RegisterIn(String session) {
    }

    /** the student's act: the level's fixed curriculum registered for the session, once the fees are cleared */
    @PostMapping("/register")
    @PreAuthorize(STUDENT)
    @Transactional
    Map<String, Object> register(Authentication auth, @RequestBody(required = false) RegisterIn body) {
        UUID me = UUID.fromString(auth.getName());
        // the session the year opens in is the College's (college.level_session) unless the student names one; a year already open registers its next semester
        String session = body != null && body.session() != null && !body.session().isBlank() ? body.session().trim() : null;
        String r = jdbc.sql("SELECT college.register_level(:me, :s)").param("me", me).param("s", session, Types.VARCHAR).query(String.class).single();
        return Map.of("result", r);
    }

}
