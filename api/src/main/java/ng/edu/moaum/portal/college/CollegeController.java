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

}
