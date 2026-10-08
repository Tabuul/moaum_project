package ng.edu.moaum.portal.cbt;

import java.math.BigDecimal;
import java.sql.Types;
import java.time.OffsetDateTime;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

import ng.edu.moaum.portal.shared.AuditContext;
import ng.edu.moaum.portal.shared.AuditContextHolder;
import ng.edu.moaum.portal.shared.DomainRuleViolation;
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
 * The CBT examination engine's office door (V322): an office creates and configures an examination over one of its
 * course offerings, sets its paper, schedules and publishes it, watches it live, reads every score the moment it
 * exists, reviews, approves and publishes the results, amends with a reason, and sends the scores onto the course's
 * score sheet. GST first; EPS on the same engine; from V364 the University's examinations office (EXAMS) for every other CBT-enabled
 * course — a department's or faculty's Examinations Officer within their scope, Examinations and Records for any. Every figure is counted
 * in the database; nothing is loaded whole
 * into memory; the office never sees a candidate's answers while the examination runs.
 */
@RestController
@RequestMapping("/api/v1/cbt")
class CbtExamController {

    private static final String READERS =
            "hasAnyAuthority('OFFICE_gst','OFFICE_eps','OFFICE_bursar','OFFICE_financecontroller','OFFICE_registrar','OFFICE_dregistrar',"
            + "'OFFICE_dvc','OFFICE_vc','OFFICE_academic','OFFICE_records','OFFICE_ict','OFFICE_admin','OFFICE_super',"
            + "'OFFICE_exams','OFFICE_facultyexams','OFFICE_hod','OFFICE_dean','OFFICE_jupeb')";
    private static final String MANAGERS = "hasAnyAuthority('OFFICE_gst','OFFICE_eps','OFFICE_exams','OFFICE_facultyexams','OFFICE_records','OFFICE_super','OFFICE_jupeb')";
    /** after publication a result is changed, or withdrawn, only with stronger authority */
    private static final String STRONGER = "hasAnyAuthority('OFFICE_super','OFFICE_registrar')";
    private static final Set<String> OFFICES = Set.of("GST", "EPS", "EXAMS", "JUPEB");
    /** V364: the offices that run the University's own CBT examinations, and those that only read them within their scope */
    private static final Set<String> EXAMS_MANAGERS = Set.of("exams", "facultyexams", "records", "super");
    private static final Set<String> EXAMS_ONLY = Set.of("exams", "facultyexams", "hod", "dean");
    private static final Set<String> EXAM_ACTIONS = Set.of("schedule", "publish", "unpublish", "close", "complete", "cancel", "archive", "unarchive");
    private static final Set<String> RESULT_ACTIONS = Set.of("review", "approve", "publish", "unpublish");
    private static final Set<String> CANDIDATE_STATUS = Set.of("NOT_STARTED", "IN_PROGRESS", "SUBMITTED", "TIME_EXPIRED", "TERMINATED", "DISCONNECTED", "WARNED", "CRITICAL", "INELIGIBLE", "PASSED", "FAILED");

    private final JdbcClient jdbc;
    private final OfficeScope scope;
    private final tools.jackson.databind.ObjectMapper mapper = new tools.jackson.databind.ObjectMapper();

    CbtExamController(JdbcClient jdbc, OfficeScope scope) {
        this.jdbc = jdbc;
        this.scope = scope;
    }

    /** an examination over a course offering, or (V365, office JUPEB) over a JUPEB subject in a session and semester */
    public record ExamIn(@NotBlank String office, UUID offeringId, UUID jupebSubjectId, @Size(max = 9) String session, Integer semester,
                         @NotBlank @Size(max = 200) String title, @Size(max = 8000) String instructions,
                         Integer durationMinutes, Integer totalQuestions, String selection, Boolean randomizeQuestions, Boolean randomizeOptions,
                         BigDecimal passMark, Integer attemptLimit, String securityMode, String venue, Integer violationLimit, String violationAction,
                         String secondSession, OffsetDateTime startsAt, OffsetDateTime endsAt, Boolean partialCredit, Map<String, Object> settings) {
    }

    public record ExamEdit(@NotBlank @Size(max = 200) String title, @Size(max = 8000) String instructions, Integer durationMinutes, Integer totalQuestions,
                           String selection, Boolean randomizeQuestions, Boolean randomizeOptions, BigDecimal passMark, Integer attemptLimit,
                           String securityMode, String venue, Integer violationLimit, String violationAction, String secondSession,
                           OffsetDateTime startsAt, OffsetDateTime endsAt, Boolean partialCredit, Map<String, Object> settings) {
    }

    /** V364: how many questions of each difficulty or topic a random paper draws; no dimension = the whole pool */
    public record BlueprintRow(@NotBlank @Size(max = 200) String value, @NotNull Integer questions) {
    }

    public record BlueprintIn(@Size(max = 12) String dimension, List<@Valid BlueprintRow> rows) {
    }

    public record PaperQuestion(@NotNull UUID id, Integer marks) {
    }

    public record PaperIn(@NotNull List<@Valid PaperQuestion> questions) {
    }

    public record ActionIn(@Size(max = 1000) String reason) {
    }

    public record AmendIn(@NotNull BigDecimal score, String outcome, @NotBlank @Size(max = 1000) String reason) {
    }

    /* ── who may do what ── */

    private static String acting() {
        return AuditContextHolder.current().map(AuditContext::actorOffice).orElse("");
    }

    /** an office reads its own examinations; the readers read every office's; an examinations officer reads the University's own (V364) */
    private static String office(String o) {
        String office = o == null ? "" : o.trim().toUpperCase();
        if (!OFFICES.contains(office)) throw new NotFound("office", o);
        String acting = acting();
        if (("gst".equals(acting) && !"GST".equals(office)) || ("eps".equals(acting) && !"EPS".equals(office))) {
            throw new AccessDeniedException("The " + acting.toUpperCase() + " office reads its own examinations; " + office + " examinations are the other office's.");
        }
        if (EXAMS_ONLY.contains(acting) && !"EXAMS".equals(office)) {
            throw new AccessDeniedException("An examinations officer reads the University's own CBT examinations; " + office + " examinations are that office's.");
        }
        // V365: the JUPEB Office reads its own examinations, and the University's offices read no JUPEB examination but as readers
        if ("jupeb".equals(acting) && !"JUPEB".equals(office)) {
            throw new AccessDeniedException("The JUPEB Office reads its own examinations; " + office + " examinations are that office's.");
        }
        return office;
    }

    /** only the office itself (or the Super Administrator) changes its examinations; the University's are its examinations offices' (V364) */
    private static void manage(String office) {
        String acting = acting();
        boolean ok = "super".equals(acting) || ("EXAMS".equals(office) ? EXAMS_MANAGERS.contains(acting) : acting.equalsIgnoreCase(office));
        if (!ok) {
            throw new AccessDeniedException("EXAMS".equals(office) ? "The University's CBT examinations are managed by an Examinations Officer or by Examinations and Records."
                    : "Only the " + office + " office manages " + office + " examinations.");
        }
    }

    /** V364: an examination of the University's own is read and changed only within the acting office's scope — the department's or faculty's courses */
    private void inScope(Map<String, Object> e) {
        if ("EXAMS".equals(e.get("office"))) scope.assertCourseInScope((String) e.get("course_code"));
    }

    private Map<String, Object> examRow(UUID id) {
        return jdbc.sql("""
                SELECT e.*, assessment.cbt_live_state(e) AS live_state, coalesce(c.title, js.title) AS course_title, c.units, c.level AS course_level, c.ca_max,
                       js.code AS subject_code,
                       (SELECT count(*) FROM assessment.cbt_pool(e.id)) AS pool_size,
                       (SELECT coalesce(sum(marks), 0) FROM assessment.cbt_pool(e.id)) AS pool_marks,
                       assessment.cbt_paper_ready(e.id) AS paper_problem,
                       CASE WHEN p.id IS NULL THEN NULL ELSE p.surname || ', ' || p.given_names END AS created_by_name,
                       (SELECT count(*) FROM assessment.score_sheet s WHERE s.offering_id = e.offering_id) > 0 AS has_sheet,
                       (SELECT s.stage FROM assessment.score_sheet s WHERE s.offering_id = e.offering_id) AS sheet_stage
                  FROM assessment.cbt_exam e LEFT JOIN catalogue.course c ON c.code = e.course_code LEFT JOIN jupeb.subject js ON js.id = e.jupeb_subject_id
                  LEFT JOIN iam.person p ON p.id = e.created_by
                 WHERE e.id = :id
                """).param("id", id).query().listOfRows().stream().findFirst().map(CbtExamController::plain).map(CbtExamController::named)
                .orElseThrow(() -> new NotFound("examination", id.toString()));
    }

    /** V365: a JUPEB examination is named by its subject's code where a University one is by its course's */
    static Map<String, Object> named(Map<String, Object> row) {
        if (row.get("course_code") == null && row.get("subject_code") != null) row.put("course_code", row.get("subject_code"));
        return row;
    }

    /** a row as the screen reads it: a database array (the detectors, the counted events) becomes a JSON list */
    static Map<String, Object> plain(Map<String, Object> row) {
        Map<String, Object> out = new LinkedHashMap<>(row);
        for (Map.Entry<String, Object> en : out.entrySet()) {
            if (en.getValue() instanceof java.sql.Array arr) {
                try {
                    en.setValue(List.of((Object[]) arr.getArray()));
                } catch (java.sql.SQLException ex) {
                    throw new IllegalStateException(ex);
                }
            }
        }
        return out;
    }

    /** the examination, checked against the acting office for reading */
    private Map<String, Object> readable(UUID id) {
        Map<String, Object> e = examRow(id);
        office((String) e.get("office"));
        inScope(e);
        return e;
    }

    /** the examination, checked against the acting office for changing */
    private Map<String, Object> managed(UUID id) {
        Map<String, Object> e = examRow(id);
        String o = office((String) e.get("office"));
        manage(o);
        inScope(e);
        return e;
    }

    /* ── the office's summary and list ── */

    @GetMapping("/summary")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> summary(@RequestParam String office, @RequestParam(required = false) String session) {
        String o = office(office);
        String s = session(session);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("office", o);
        out.put("session", s);
        out.put("summary", jdbc.sql("SELECT * FROM assessment.cbt_office_summary(:o, :s)").param("o", o).param("s", s).query().singleRow());
        out.put("next", jdbc.sql("""
                SELECT e.id, e.reference, e.title, e.course_code, e.starts_at, e.ends_at, e.state, e.results_state, assessment.cbt_live_state(e) AS live_state,
                       (SELECT count(*) FROM assessment.cbt_attempt a WHERE a.exam_id = e.id AND a.status = 'IN_PROGRESS') AS writing
                  FROM assessment.cbt_exam e WHERE e.office = :o AND e.session = :s AND e.state IN ('SCHEDULED', 'PUBLISHED', 'CLOSED')
                 ORDER BY e.starts_at NULLS LAST LIMIT 8
                """).param("o", o).param("s", s).query().listOfRows());
        out.put("now", OffsetDateTime.now());
        return out;
    }

    @GetMapping("/exams")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> exams(@RequestParam String office, @RequestParam(required = false) String session, @RequestParam(required = false) Integer semester,
                              @RequestParam(required = false) String state, @RequestParam(defaultValue = "false") boolean archived) {
        String o = office(office);
        String s = session(session);
        String st = state == null || state.isBlank() ? null : state.trim().toUpperCase();
        // V364: an examinations officer's list is their department's or faculty's courses
        OfficeScope.Bound b = "EXAMS".equals(o) ? scope.bound(null, null, null) : new OfficeScope.Bound(null, null, null);
        List<Map<String, Object>> rows = jdbc.sql("""
                SELECT e.id, e.reference, e.title, coalesce(e.course_code, js.code) AS course_code, coalesce(c.title, js.title) AS course_title, e.session, e.semester, e.state, e.results_state, assessment.cbt_live_state(e) AS live_state,
                       e.starts_at, e.ends_at, e.duration_minutes, e.selection, e.total_questions, e.security_mode, e.venue, e.pass_mark, e.published_at, e.completed_at,
                       (SELECT count(*) FROM assessment.cbt_pool(e.id)) AS pool_size,
                       (SELECT count(DISTINCT cr.student_id) FROM registration.entry en JOIN registration.course_registration cr ON cr.id = en.registration_id
                         WHERE en.offering_id = e.offering_id AND en.status IN ('REGISTERED', 'APPROVED') AND cr.status IN ('SUBMITTED', 'APPROVED', 'LOCKED'))
                       + (SELECT count(DISTINCT r.application_id) FROM jupeb.subject_registration r WHERE r.subject_id = e.jupeb_subject_id AND r.session = e.session) AS candidates,
                       (SELECT count(DISTINCT a.candidate_id) FROM assessment.cbt_attempt a WHERE a.exam_id = e.id) AS started,
                       (SELECT count(*) FROM assessment.cbt_attempt a WHERE a.exam_id = e.id AND a.status = 'IN_PROGRESS') AS writing,
                       (SELECT count(DISTINCT a.candidate_id) FROM assessment.cbt_attempt a WHERE a.exam_id = e.id AND a.score IS NOT NULL) AS scored
                  FROM assessment.cbt_exam e LEFT JOIN catalogue.course c ON c.code = e.course_code LEFT JOIN jupeb.subject js ON js.id = e.jupeb_subject_id
                 WHERE e.office = :o AND e.session = :s AND (:sem::int IS NULL OR e.semester = :sem)
                   AND (:st::text IS NULL OR e.state = :st OR assessment.cbt_live_state(e) = :st)
                   AND ((e.archived_at IS NOT NULL) = :arch)
                   AND (:dept::text IS NULL OR c.dept_code = :dept)
                   AND (:fac::text IS NULL OR EXISTS (SELECT 1 FROM ref.department d WHERE d.code = c.dept_code AND d.faculty_code = :fac))
                 ORDER BY e.starts_at DESC NULLS FIRST, e.created_at DESC
                """).param("o", o).param("s", s).param("sem", semester, Types.INTEGER).param("st", st, Types.VARCHAR).param("arch", archived)
                .param("dept", b.dept(), Types.VARCHAR).param("fac", b.fac(), Types.VARCHAR).query().listOfRows();
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("office", o);
        out.put("session", s);
        out.put("semester", semester);
        out.put("archived", archived);
        if ("JUPEB".equals(o)) {
            // V365: the JUPEB Office examines its subjects, each only once allowed CBT
            out.put("subjects", jdbc.sql("""
                    SELECT s.id, s.code, s.title, s.cbt_enabled,
                           (SELECT count(*) FROM assessment.question q WHERE q.jupeb_subject_id = s.id AND q.active) AS questions,
                           (SELECT count(DISTINCT r.application_id) FROM jupeb.subject_registration r WHERE r.subject_id = s.id AND r.session = :s) AS registered
                      FROM jupeb.subject s WHERE s.active ORDER BY s.code
                    """).param("s", s).query().listOfRows());
        }
        out.put("rows", rows);
        out.put("sessions", jdbc.sql("SELECT name, state FROM policy.academic_session ORDER BY name DESC").query().listOfRows());
        out.put("offerings", jdbc.sql("""
                SELECT o.id, o.course_code, c.title, c.units, c.level, o.semester, o.session,
                       (SELECT count(*) FROM assessment.question q WHERE q.course_code = c.code AND q.active) AS questions
                  FROM catalogue.offering o JOIN catalogue.course c ON c.code = o.course_code
                 WHERE o.session = :s AND c.state <> 'ENDED' AND c.cbt_enabled
                   AND ((:o = 'EXAMS' AND c.kind <> 'GST') OR (:o <> 'EXAMS' AND c.kind = 'GST' AND coalesce(c.general_office, 'GST') = :o))
                   AND (:dept::text IS NULL OR c.dept_code = :dept)
                   AND (:fac::text IS NULL OR EXISTS (SELECT 1 FROM ref.department d WHERE d.code = c.dept_code AND d.faculty_code = :fac))
                 ORDER BY o.semester, c.code
                """).param("s", s).param("o", o).param("dept", b.dept(), Types.VARCHAR).param("fac", b.fac(), Types.VARCHAR).query().listOfRows());
        out.put("now", OffsetDateTime.now());
        return out;
    }

    private String session(String session) {
        if (session != null && !session.isBlank()) return session.trim();
        if ("jupeb".equals(acting())) {
            String j = jdbc.sql("SELECT jupeb.current_session()").query(String.class).optional().orElse(null);
            if (j != null) return j;
        }
        return jdbc.sql("""
                SELECT name FROM policy.academic_session ORDER BY (state = 'CURRENT') DESC, (state = 'OPEN') DESC, name DESC LIMIT 1
                """).query(String.class).optional().orElse("");
    }

    /* ── one examination ── */

    @PostMapping("/exams")
    @PreAuthorize(MANAGERS)
    @Transactional
    Map<String, Object> create(@Valid @RequestBody ExamIn in) {
        String o = office(in.office());
        manage(o);
        if ("JUPEB".equals(o)) {
            if (in.jupebSubjectId() == null) {
                throw new DomainRuleViolation("CBT_SUBJECT_REQUIRED", "A JUPEB examination names its subject.", new DomainRuleViolation.Remedy("Choose the subject.", "You"));
            }
            UUID jid = jdbc.sql("""
                    SELECT (assessment.cbt_new_jupeb_exam(:sub, :ses, :sem, :t, :i, :d, :n, :sel, :rq, :ro, :pm, :al, :sec, :v, :vl, :va, :ss, :sa, :ea)).id
                    """)
                    .param("sub", in.jupebSubjectId()).param("ses", session(in.session())).param("sem", in.semester() == null ? 1 : in.semester()).param("t", in.title())
                    .param("i", in.instructions(), Types.VARCHAR).param("d", in.durationMinutes(), Types.INTEGER).param("n", in.totalQuestions(), Types.INTEGER)
                    .param("sel", in.selection(), Types.VARCHAR).param("rq", in.randomizeQuestions(), Types.BOOLEAN).param("ro", in.randomizeOptions(), Types.BOOLEAN)
                    .param("pm", in.passMark(), Types.NUMERIC).param("al", in.attemptLimit(), Types.INTEGER).param("sec", in.securityMode(), Types.VARCHAR)
                    .param("v", in.venue(), Types.VARCHAR).param("vl", in.violationLimit(), Types.INTEGER).param("va", in.violationAction(), Types.VARCHAR)
                    .param("ss", in.secondSession(), Types.VARCHAR).param("sa", in.startsAt(), Types.TIMESTAMP_WITH_TIMEZONE).param("ea", in.endsAt(), Types.TIMESTAMP_WITH_TIMEZONE)
                    .query(UUID.class).single();
            if (in.partialCredit() != null) jdbc.sql("UPDATE assessment.cbt_exam SET partial_credit = :pc WHERE id = :id").param("pc", in.partialCredit()).param("id", jid).update();
            configure(jid, in.settings());
            return exam(jid);
        }
        if (in.offeringId() == null) {
            throw new DomainRuleViolation("CBT_OFFERING_REQUIRED", "An examination is created over a course offering.", new DomainRuleViolation.Remedy("Choose the offering.", "You"));
        }
        if ("EXAMS".equals(o)) {
            jdbc.sql("SELECT course_code FROM catalogue.offering WHERE id = :o").param("o", in.offeringId()).query(String.class).optional().ifPresent(scope::assertCourseInScope);
        }
        UUID id = jdbc.sql("""
                SELECT (assessment.cbt_new_exam(:o, :off, :t, :i, :d, :n, :sel, :rq, :ro, :pm, :al, :sec, :v, :vl, :va, :ss, :sa, :ea, :pc)).id
                """)
                .param("o", o).param("off", in.offeringId()).param("t", in.title()).param("i", in.instructions(), Types.VARCHAR)
                .param("d", in.durationMinutes(), Types.INTEGER).param("n", in.totalQuestions(), Types.INTEGER).param("sel", in.selection(), Types.VARCHAR)
                .param("rq", in.randomizeQuestions(), Types.BOOLEAN).param("ro", in.randomizeOptions(), Types.BOOLEAN).param("pm", in.passMark(), Types.NUMERIC)
                .param("al", in.attemptLimit(), Types.INTEGER).param("sec", in.securityMode(), Types.VARCHAR).param("v", in.venue(), Types.VARCHAR)
                .param("vl", in.violationLimit(), Types.INTEGER).param("va", in.violationAction(), Types.VARCHAR).param("ss", in.secondSession(), Types.VARCHAR)
                .param("sa", in.startsAt(), Types.TIMESTAMP_WITH_TIMEZONE).param("ea", in.endsAt(), Types.TIMESTAMP_WITH_TIMEZONE).param("pc", in.partialCredit(), Types.BOOLEAN)
                .query(UUID.class).single();
        configure(id, in.settings());
        return exam(id);
    }

    /** V364: the further settings, each applied only when sent */
    private void configure(UUID id, Map<String, Object> settings) {
        if (settings == null || settings.isEmpty()) return;
        jdbc.sql("SELECT (assessment.cbt_configure(:id, :j::jsonb)).id").param("id", id).param("j", mapper.writeValueAsString(settings)).query(UUID.class).single();
    }

    @GetMapping("/exams/{id}")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> exam(@PathVariable UUID id) {
        Map<String, Object> e = readable(id);
        Map<String, Object> out = new LinkedHashMap<>(e);
        out.put("paper", jdbc.sql("""
                SELECT q.id, q.topic, q.kind, q.stem, q.difficulty, q.marks AS bank_marks, eq.marks AS paper_marks, coalesce(eq.marks, q.marks) AS marks, eq.ordinal, q.active,
                       jsonb_array_length(q.options) AS options
                  FROM assessment.cbt_exam_question eq JOIN assessment.question q ON q.id = eq.question_id
                 WHERE eq.exam_id = :id ORDER BY eq.ordinal, q.stem
                """).param("id", id).query().listOfRows());
        boolean jupeb = "JUPEB".equals(e.get("office"));
        out.put("bank", jdbc.sql("""
                SELECT coalesce(topic, 'Untitled topic') AS topic, count(*) FILTER (WHERE active) AS active, count(*) AS total, coalesce(sum(marks) FILTER (WHERE active), 0) AS marks
                  FROM assessment.question WHERE CASE WHEN :sub::uuid IS NULL THEN course_code = :c ELSE jupeb_subject_id = :sub::uuid END GROUP BY topic ORDER BY topic NULLS FIRST
                """).param("c", e.get("course_code")).param("sub", jupeb ? e.get("jupeb_subject_id") : null, Types.OTHER).query().listOfRows());
        if (jupeb) {
            out.put("caComponents", jdbc.sql("SELECT id, code, title, max_score FROM jupeb.ca_component WHERE session = :s AND active ORDER BY ord, code")
                    .param("s", e.get("session")).query().listOfRows());
        }
        out.put("blueprintRows", jdbc.sql("SELECT value, questions FROM assessment.cbt_blueprint WHERE exam_id = :id ORDER BY CASE value WHEN 'EASY' THEN 1 WHEN 'MEDIUM' THEN 2 WHEN 'HARD' THEN 3 ELSE 4 END, value")
                .param("id", id).query().listOfRows());
        out.put("topics", jdbc.sql("""
                SELECT btrim(q.topic) AS topic, count(*) AS questions FROM assessment.cbt_pool(:id) p JOIN assessment.question q ON q.id = p.question_id
                 WHERE q.topic IS NOT NULL AND btrim(q.topic) <> '' GROUP BY btrim(q.topic) ORDER BY 1
                """).param("id", id).query().listOfRows());
        out.put("counts", jdbc.sql("SELECT * FROM assessment.cbt_monitor_counts(:id)").param("id", id).query().singleRow());
        out.put("stats", jdbc.sql("SELECT * FROM assessment.cbt_exam_stats(:id)").param("id", id).query().singleRow());
        out.put("results", jdbc.sql("""
                SELECT count(*) AS versions, count(*) FILTER (WHERE version > 1) AS amendments FROM assessment.cbt_result r
                  JOIN assessment.cbt_attempt a ON a.id = r.attempt_id WHERE a.exam_id = :id
                """).param("id", id).query().singleRow());
        out.put("now", OffsetDateTime.now());
        return out;
    }

    @PutMapping("/exams/{id}")
    @PreAuthorize(MANAGERS)
    @Transactional
    Map<String, Object> edit(@PathVariable UUID id, @Valid @RequestBody ExamEdit in) {
        Map<String, Object> e = managed(id);
        String state = (String) e.get("state");
        if ("PUBLISHED".equals(state)) {
            // a published examination keeps its paper and its rules; only its closing time, instructions and title move
            jdbc.sql("UPDATE assessment.cbt_exam SET title = :t, instructions = :i, ends_at = coalesce(:ea, ends_at) WHERE id = :id")
                    .param("t", in.title().trim()).param("i", blank(in.instructions()), Types.VARCHAR).param("ea", in.endsAt(), Types.TIMESTAMP_WITH_TIMEZONE).param("id", id).update();
            return exam(id);
        }
        if (!"DRAFT".equals(state) && !"SCHEDULED".equals(state)) {
            throw new DomainRuleViolation("CBT_STATE", "A " + state.toLowerCase() + " examination is not edited.", new DomainRuleViolation.Remedy("Create a new examination for another sitting.", "You"));
        }
        jdbc.sql("""
                UPDATE assessment.cbt_exam
                   SET title = :t, instructions = :i, duration_minutes = coalesce(:d, duration_minutes), total_questions = coalesce(:n, total_questions),
                       selection = coalesce(upper(:sel), selection), randomize_questions = coalesce(:rq, randomize_questions), randomize_options = coalesce(:ro, randomize_options),
                       pass_mark = coalesce(:pm, pass_mark), attempt_limit = coalesce(:al, attempt_limit), security_mode = coalesce(upper(:sec), security_mode),
                       venue = coalesce(upper(:v), venue), violation_limit = coalesce(:vl, violation_limit), violation_action = coalesce(upper(:va), violation_action),
                       second_session = coalesce(upper(:ss), second_session), starts_at = :sa, ends_at = :ea, partial_credit = coalesce(:pc, partial_credit)
                 WHERE id = :id
                """)
                .param("t", in.title().trim()).param("i", blank(in.instructions()), Types.VARCHAR)
                .param("d", in.durationMinutes(), Types.INTEGER).param("n", in.totalQuestions(), Types.INTEGER).param("sel", in.selection(), Types.VARCHAR)
                .param("rq", in.randomizeQuestions(), Types.BOOLEAN).param("ro", in.randomizeOptions(), Types.BOOLEAN).param("pm", in.passMark(), Types.NUMERIC)
                .param("al", in.attemptLimit(), Types.INTEGER).param("sec", in.securityMode(), Types.VARCHAR).param("v", in.venue(), Types.VARCHAR)
                .param("vl", in.violationLimit(), Types.INTEGER).param("va", in.violationAction(), Types.VARCHAR).param("ss", in.secondSession(), Types.VARCHAR)
                .param("sa", in.startsAt(), Types.TIMESTAMP_WITH_TIMEZONE).param("ea", in.endsAt(), Types.TIMESTAMP_WITH_TIMEZONE).param("pc", in.partialCredit(), Types.BOOLEAN).param("id", id).update();
        configure(id, in.settings());
        return exam(id);
    }

    /** V364: the blueprint of a random paper, replaced whole; refused when the pool cannot satisfy it, saying what is short */
    @PutMapping("/exams/{id}/blueprint")
    @PreAuthorize(MANAGERS)
    @Transactional
    Map<String, Object> blueprint(@PathVariable UUID id, @Valid @RequestBody BlueprintIn in) {
        managed(id);
        List<Map<String, Object>> rows = in.rows() == null ? List.of() : in.rows().stream().map(r -> Map.<String, Object>of("value", r.value().trim(), "questions", r.questions())).toList();
        jdbc.sql("SELECT (assessment.cbt_set_blueprint(:id, :d, :j::jsonb)).id").param("id", id).param("d", blank(in.dimension()), Types.VARCHAR)
                .param("j", mapper.writeValueAsString(rows)).query(UUID.class).single();
        return exam(id);
    }

    /** the paper: the fixed questions in the order given, or the pool a random paper draws from; replaced whole */
    @PutMapping("/exams/{id}/paper")
    @PreAuthorize(MANAGERS)
    @Transactional
    Map<String, Object> paper(@PathVariable UUID id, @Valid @RequestBody PaperIn in) {
        Map<String, Object> e = managed(id);
        String state = (String) e.get("state");
        if (!"DRAFT".equals(state) && !"SCHEDULED".equals(state)) {
            throw new DomainRuleViolation("CBT_STATE", "The paper of a " + state.toLowerCase() + " examination is not changed.", new DomainRuleViolation.Remedy("Withdraw the examination first if nobody has sat it.", "You"));
        }
        String course = (String) e.get("course_code");
        Object subject = "JUPEB".equals(e.get("office")) ? e.get("jupeb_subject_id") : null;
        jdbc.sql("DELETE FROM assessment.cbt_exam_question WHERE exam_id = :id").param("id", id).update();
        int ordinal = 0;
        for (PaperQuestion q : in.questions()) {
            boolean ok = jdbc.sql("SELECT EXISTS (SELECT 1 FROM assessment.question WHERE id = :q AND CASE WHEN :sub::uuid IS NULL THEN course_code = :c ELSE jupeb_subject_id = :sub::uuid END)")
                    .param("q", q.id()).param("c", course).param("sub", subject, Types.OTHER).query(Boolean.class).single();
            if (!ok) throw new DomainRuleViolation("CBT_QUESTION_NOT_OF_COURSE", "A question on the paper is not in " + course + "'s bank.", new DomainRuleViolation.Remedy("Pick questions from the course's own bank.", "You"));
            jdbc.sql("INSERT INTO assessment.cbt_exam_question (exam_id, question_id, ordinal, marks) VALUES (:e, :q, :o, :m) ON CONFLICT (exam_id, question_id) DO UPDATE SET ordinal = EXCLUDED.ordinal, marks = EXCLUDED.marks")
                    .param("e", id).param("q", q.id()).param("o", ++ordinal).param("m", q.marks(), Types.INTEGER).update();
        }
        if ("FIXED".equals(e.get("selection"))) {
            jdbc.sql("UPDATE assessment.cbt_exam SET total_questions = :n WHERE id = :id").param("n", ordinal).param("id", id).update();
        }
        return exam(id);
    }

    @PostMapping("/exams/{id}/{action}")
    @PreAuthorize(MANAGERS)
    @Transactional
    Map<String, Object> act(@PathVariable UUID id, @PathVariable String action, @RequestBody(required = false) ActionIn in) {
        String a = action == null ? "" : action.trim().toLowerCase();
        if (!EXAM_ACTIONS.contains(a)) throw new NotFound("action", action);
        managed(id);
        jdbc.sql("SELECT (assessment.cbt_exam_action(:id, :a, :r)).state").param("id", id).param("a", a).param("r", in == null ? null : in.reason(), Types.VARCHAR).query(String.class).single();
        return exam(id);
    }

    /* ── the candidates and the live monitor ── */

    private static final String CANDIDATE_WHERE = """
             WHERE (:fac::text IS NULL OR c.faculty_code = :fac) AND (:dept::text IS NULL OR c.dept_code = :dept) AND (:prog::text IS NULL OR c.programme_code = :prog)
               AND (:level::int IS NULL OR c.level = :level)
               AND (:q::text IS NULL OR lower(c.surname || ' ' || c.other_names) LIKE :q OR lower(coalesce(c.number, '')) LIKE :q)
               AND (:st::text IS NULL
                    OR (:st = 'DISCONNECTED' AND c.connection = 'DISCONNECTED')
                    OR (:st = 'WARNED' AND c.violations > 0)
                    OR (:st = 'CRITICAL' AND c.violations >= :limit)
                    OR (:st = 'INELIGIBLE' AND NOT c.eligible)
                    OR (:st = 'PASSED' AND c.passed)
                    OR (:st = 'FAILED' AND c.percentage IS NOT NULL AND NOT c.passed)
                    OR (:st NOT IN ('DISCONNECTED', 'WARNED', 'CRITICAL', 'INELIGIBLE', 'PASSED', 'FAILED') AND c.attempt_status = :st))
            """;

    private JdbcClient.StatementSpec candidateFilters(JdbcClient.StatementSpec spec, UUID id, Map<String, Object> e, String fac, String dept, String prog, Integer level, String q, String status) {
        String st = status == null || status.isBlank() ? null : status.trim().toUpperCase();
        if (st != null && !CANDIDATE_STATUS.contains(st)) st = null;
        return spec.param("id", id).param("fac", blank(fac), Types.VARCHAR).param("dept", blank(dept), Types.VARCHAR).param("prog", blank(prog), Types.VARCHAR)
                .param("level", level, Types.INTEGER).param("q", q == null || q.isBlank() ? null : "%" + q.trim().toLowerCase() + "%", Types.VARCHAR)
                .param("st", st, Types.VARCHAR).param("limit", ((Number) e.get("violation_limit")).intValue());
    }

    @GetMapping("/exams/{id}/candidates")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> candidates(@PathVariable UUID id, @RequestParam(required = false) String status, @RequestParam(required = false) String fac,
                                   @RequestParam(required = false) String dept, @RequestParam(required = false) String prog, @RequestParam(required = false) Integer level,
                                   @RequestParam(required = false) String q, @RequestParam(defaultValue = "1") int page, @RequestParam(defaultValue = "50") int size,
                                   @RequestParam(defaultValue = "name") String sort) {
        Map<String, Object> e = readable(id);
        int sz = Math.max(1, Math.min(size, 500)), pg = Math.max(1, page);
        String order = switch (sort) {
            case "score" -> "c.percentage DESC NULLS LAST, c.surname, c.other_names";
            case "status" -> "c.attempt_status, c.surname, c.other_names";
            case "started" -> "c.started_at DESC NULLS LAST, c.surname";
            case "violations" -> "c.violations DESC, c.surname";
            default -> "c.surname, c.other_names";
        };
        long total = candidateFilters(jdbc.sql("SELECT count(*) FROM assessment.cbt_candidates(:id) c" + CANDIDATE_WHERE), id, e, fac, dept, prog, level, q, status).query(Long.class).single();
        List<Map<String, Object>> rows = candidateFilters(jdbc.sql("SELECT c.* FROM assessment.cbt_candidates(:id) c" + CANDIDATE_WHERE + " ORDER BY " + order + " LIMIT :lim OFFSET :off"),
                id, e, fac, dept, prog, level, q, status).param("lim", sz).param("off", (long) (pg - 1) * sz).query().listOfRows();
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("exam", Map.of("id", id, "title", e.get("title"), "course_code", e.get("course_code"), "live_state", e.get("live_state"), "violation_limit", e.get("violation_limit")));
        out.put("total", total);
        out.put("page", pg);
        out.put("size", sz);
        out.put("rows", rows);
        out.put("options", options(id));
        out.put("now", OffsetDateTime.now());
        return out;
    }

    private Map<String, Object> options(UUID id) {
        Map<String, Object> o = new LinkedHashMap<>();
        o.put("faculties", jdbc.sql("SELECT DISTINCT faculty_code AS code, faculty AS name FROM assessment.cbt_candidates(:id) ORDER BY faculty").param("id", id).query().listOfRows());
        o.put("departments", jdbc.sql("SELECT DISTINCT dept_code AS code, department AS name, faculty_code FROM assessment.cbt_candidates(:id) ORDER BY department").param("id", id).query().listOfRows());
        o.put("programmes", jdbc.sql("SELECT DISTINCT programme_code AS code, programme AS name, dept_code FROM assessment.cbt_candidates(:id) ORDER BY programme").param("id", id).query().listOfRows());
        o.put("levels", jdbc.sql("SELECT DISTINCT level FROM assessment.cbt_candidates(:id) ORDER BY level").param("id", id).query(Integer.class).list());
        return o;
    }

    /** the live monitor: the counters, and only the attempts that changed since the cursor the browser holds — never the answers */
    @GetMapping("/exams/{id}/monitor")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> monitor(@PathVariable UUID id, @RequestParam(required = false) OffsetDateTime since) {
        Map<String, Object> e = readable(id);
        Map<String, Object> out = new LinkedHashMap<>();
        Map<String, Object> head = new LinkedHashMap<>();
        for (String k : List.of("id", "reference", "title", "course_code", "live_state", "state", "starts_at", "ends_at", "duration_minutes", "violation_limit", "violation_action")) {
            head.put(k, e.get(k));
        }
        out.put("exam", head);
        out.put("counts", jdbc.sql("SELECT * FROM assessment.cbt_monitor_counts(:id)").param("id", id).query().singleRow());
        List<Map<String, Object>> rows = jdbc.sql("""
                SELECT a.id AS attempt_id, a.candidate_id AS student_id, coalesce(s.matric_no, s.admission_no, ja.exam_no, ja.application_no) AS number,
                       coalesce(s.surname, upper(ja.surname)) AS surname, coalesce(s.other_names, ja.first_name || coalesce(' ' || ja.middle_name, '')) AS other_names, a.number AS attempt_no,
                       a.status AS attempt_status, a.started_at, a.ends_at, a.submitted_at, a.last_activity_at, a.violations, a.answered, cardinality(a.question_ids) AS questions,
                       a.score, a.max_marks, a.percentage, a.grade, a.passed, a.outcome, a.updated_at, a.finished_reason
                  FROM assessment.cbt_attempt a LEFT JOIN people.student s ON s.id = a.student_id LEFT JOIN jupeb.application ja ON ja.id = a.jupeb_application_id
                 WHERE a.exam_id = :id AND (:since::timestamptz IS NULL OR a.updated_at > :since)
                 ORDER BY a.updated_at LIMIT 5000
                """).param("id", id).param("since", since, Types.TIMESTAMP_WITH_TIMEZONE).query().listOfRows();
        out.put("rows", rows);
        out.put("events", jdbc.sql("""
                SELECT ev.id, ev.attempt_id, ev.kind, ev.violation, ev.at, ev.detail, coalesce(ev.severity, assessment.cbt_event_severity(ev.kind)) AS severity,
                       ev.question_no, ev.duration_ms, coalesce(s.matric_no, s.admission_no, ja.exam_no, ja.application_no) AS number,
                       coalesce(s.surname, upper(ja.surname)) AS surname, coalesce(s.other_names, ja.first_name) AS other_names
                  FROM assessment.cbt_event ev JOIN assessment.cbt_attempt a ON a.id = ev.attempt_id LEFT JOIN people.student s ON s.id = a.student_id
                  LEFT JOIN jupeb.application ja ON ja.id = a.jupeb_application_id
                 WHERE ev.exam_id = :id AND (ev.violation OR ev.kind IN ('TERMINATED', 'AUTO_SUBMITTED', 'MULTIPLE_LOGIN', 'NETWORK_DISCONNECT', 'DISCONNECT_TIMEOUT',
                                                                         'CAMERA_DECLINED', 'MULTIPLE_FACES', 'TIME_MANIPULATION_ATTEMPT', 'FACE_NOT_DETECTED'))
                   AND (:since::timestamptz IS NULL OR ev.at > :since)
                 ORDER BY ev.at DESC LIMIT 200
                """).param("id", id).param("since", since, Types.TIMESTAMP_WITH_TIMEZONE).query().listOfRows());
        OffsetDateTime now = jdbc.sql("SELECT now()").query(OffsetDateTime.class).single();
        out.put("cursor", now);
        out.put("now", now);
        return out;
    }

    @GetMapping("/exams/{id}/candidates/{student}")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> candidate(@PathVariable UUID id, @PathVariable UUID student) {
        readable(id);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("candidate", jdbc.sql("SELECT * FROM assessment.cbt_candidates(:id) c WHERE c.student_id = :s").param("id", id).param("s", student).query().listOfRows().stream().findFirst()
                .orElseThrow(() -> new NotFound("candidate", student.toString())));
        out.put("attempts", jdbc.sql("""
                SELECT a.id, a.number, a.status, a.started_at, a.ends_at, a.submitted_at, a.last_activity_at, a.violations, a.answered, cardinality(a.question_ids) AS questions,
                       a.score, a.max_marks, a.percentage, a.grade, a.passed, a.outcome, a.ip, a.user_agent, a.finished_reason, a.finished_office,
                       a.camera_consent_at, a.camera_declined_at
                  FROM assessment.cbt_attempt a WHERE a.exam_id = :id AND a.candidate_id = :s ORDER BY a.number
                """).param("id", id).param("s", student).query().listOfRows());
        out.put("events", jdbc.sql("""
                SELECT ev.attempt_id, ev.kind, ev.violation, ev.at, ev.detail, ev.ip, coalesce(ev.severity, assessment.cbt_event_severity(ev.kind)) AS severity, ev.question_no, ev.duration_ms
                  FROM assessment.cbt_event ev JOIN assessment.cbt_attempt a ON a.id = ev.attempt_id
                 WHERE a.exam_id = :id AND a.candidate_id = :s ORDER BY ev.at
                """).param("id", id).param("s", student).query().listOfRows());
        out.put("versions", jdbc.sql("""
                SELECT r.attempt_id, r.version, r.score, r.max_marks, r.percentage, r.grade, r.passed, r.outcome, r.reason, r.changed_at, r.changed_office,
                       CASE WHEN p.id IS NULL THEN NULL ELSE p.surname || ', ' || p.given_names END AS changed_by
                  FROM assessment.cbt_result r JOIN assessment.cbt_attempt a ON a.id = r.attempt_id LEFT JOIN iam.person p ON p.id = r.changed_by
                 WHERE a.exam_id = :id AND a.candidate_id = :s ORDER BY r.attempt_id, r.version
                """).param("id", id).param("s", student).query().listOfRows());
        return out;
    }

    @PostMapping("/exams/{id}/attempts/{attempt}/terminate")
    @PreAuthorize(MANAGERS)
    @Transactional
    Map<String, Object> terminate(@PathVariable UUID id, @PathVariable UUID attempt, @Valid @RequestBody ActionIn in) {
        managed(id);
        UUID student = attemptOf(id, attempt);
        jdbc.sql("SELECT (assessment.cbt_terminate(:a, :r)).status").param("a", attempt).param("r", in.reason(), Types.VARCHAR).query(String.class).single();
        return candidate(id, student);
    }

    private UUID attemptOf(UUID exam, UUID attempt) {
        return jdbc.sql("SELECT candidate_id FROM assessment.cbt_attempt WHERE id = :a AND exam_id = :e").param("a", attempt).param("e", exam)
                .query(UUID.class).optional().orElseThrow(() -> new NotFound("attempt", attempt.toString()));
    }

    /* ── the results ── */

    @GetMapping("/exams/{id}/results")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> results(@PathVariable UUID id, @RequestParam(required = false) String status, @RequestParam(required = false) String fac,
                                @RequestParam(required = false) String dept, @RequestParam(required = false) String prog, @RequestParam(required = false) Integer level,
                                @RequestParam(required = false) String q, @RequestParam(defaultValue = "1") int page, @RequestParam(defaultValue = "100") int size,
                                @RequestParam(defaultValue = "name") String sort) {
        Map<String, Object> out = new LinkedHashMap<>(candidates(id, status, fac, dept, prog, level, q, page, size, sort));
        out.put("stats", jdbc.sql("SELECT * FROM assessment.cbt_exam_stats(:id)").param("id", id).query().singleRow());
        out.putAll(analytics(id));
        return out;
    }

    /** by faculty, department, programme, level and grade in one pass, and the score distribution */
    @GetMapping("/exams/{id}/analytics")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> analytics(@PathVariable UUID id) {
        readable(id);
        List<Map<String, Object>> groups = jdbc.sql("""
                WITH c AS (SELECT * FROM assessment.cbt_candidates(:id))
                SELECT grouping(faculty_code) AS g_f, grouping(dept_code) AS g_d, grouping(programme_code) AS g_p, grouping(level) AS g_l, grouping(grade) AS g_g,
                       faculty_code, faculty, dept_code, department, programme_code, programme, level, grade,
                       count(*) AS candidates, count(*) FILTER (WHERE eligible) AS eligible, count(*) FILTER (WHERE attempt_id IS NOT NULL) AS started,
                       count(*) FILTER (WHERE attempt_status IN ('SUBMITTED', 'TIME_EXPIRED', 'TERMINATED')) AS completed,
                       count(*) FILTER (WHERE attempt_status = 'SUBMITTED') AS submitted, count(*) FILTER (WHERE attempt_status = 'TIME_EXPIRED') AS time_expired,
                       count(*) FILTER (WHERE attempt_status = 'TERMINATED') AS terminated, count(*) FILTER (WHERE attempt_status = 'IN_PROGRESS') AS in_progress,
                       count(*) FILTER (WHERE attempt_id IS NULL) AS not_started, count(*) FILTER (WHERE connection = 'DISCONNECTED') AS disconnected,
                       count(*) FILTER (WHERE percentage IS NOT NULL) AS scored, round(avg(percentage) FILTER (WHERE outcome = 'SCORED'), 2) AS average,
                       max(percentage) FILTER (WHERE outcome = 'SCORED') AS highest, min(percentage) FILTER (WHERE outcome = 'SCORED') AS lowest,
                       count(*) FILTER (WHERE passed) AS passed, count(*) FILTER (WHERE percentage IS NOT NULL AND NOT passed AND outcome = 'SCORED') AS failed,
                       count(*) FILTER (WHERE outcome = 'VOID') AS void
                  FROM c
                 GROUP BY GROUPING SETS ((), (faculty_code, faculty), (faculty_code, faculty, dept_code, department),
                                         (faculty_code, faculty, dept_code, department, programme_code, programme), (level), (grade))
                 ORDER BY faculty, department, programme, level, grade
                """).param("id", id).query().listOfRows();
        List<Map<String, Object>> byFaculty = new ArrayList<>(), byDepartment = new ArrayList<>(), byProgramme = new ArrayList<>(), byLevel = new ArrayList<>(), byGrade = new ArrayList<>();
        Map<String, Object> totals = null;
        for (Map<String, Object> g : groups) {
            int gf = n(g, "g_f"), gd = n(g, "g_d"), gp = n(g, "g_p"), gl = n(g, "g_l"), gg = n(g, "g_g");
            if (gg == 0) { if (g.get("grade") != null) byGrade.add(g); continue; }
            if (gl == 0) { byLevel.add(g); continue; }
            if (gf == 1 && gd == 1 && gp == 1) { totals = g; continue; }
            if (gp == 0) byProgramme.add(g); else if (gd == 0) byDepartment.add(g); else byFaculty.add(g);
        }
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("totals", totals == null ? Map.of() : totals);
        out.put("byFaculty", byFaculty);
        out.put("byDepartment", byDepartment);
        out.put("byProgramme", byProgramme);
        out.put("byLevel", byLevel);
        out.put("byGrade", byGrade);
        out.put("buckets", jdbc.sql("""
                SELECT b AS bucket, (b - 1) * 10 AS low, CASE WHEN b = 10 THEN 100 ELSE b * 10 - 1 END AS high, count(*) AS n
                  FROM (SELECT least(width_bucket(percentage, 0, 100, 10), 10) AS b FROM assessment.cbt_candidates(:id) WHERE percentage IS NOT NULL AND outcome = 'SCORED') x
                 GROUP BY b ORDER BY b
                """).param("id", id).query().listOfRows());
        return out;
    }

    @PostMapping("/exams/{id}/results/{action}")
    @PreAuthorize(MANAGERS + " or " + STRONGER)
    @Transactional
    Map<String, Object> resultsAction(@PathVariable UUID id, @PathVariable String action) {
        String a = action == null ? "" : action.trim().toLowerCase();
        if (!RESULT_ACTIONS.contains(a)) throw new NotFound("action", action);
        if ("unpublish".equals(a)) {
            readable(id);
            stronger("Withdrawing published results");
        } else {
            managed(id);
        }
        jdbc.sql("SELECT (assessment.cbt_results_action(:id, :a)).results_state").param("id", id).param("a", a).query(String.class).single();
        return exam(id);
    }

    private static void stronger(String what) {
        String acting = acting();
        if (!("super".equals(acting) || "registrar".equals(acting))) {
            throw new AccessDeniedException(what + " needs the Registrar or the Super Administrator.");
        }
    }

    /** a score corrected: a new version with its reason; once published, only with stronger authority */
    @PutMapping("/exams/{id}/attempts/{attempt}/result")
    @PreAuthorize(MANAGERS + " or " + STRONGER)
    @Transactional
    Map<String, Object> amend(@PathVariable UUID id, @PathVariable UUID attempt, @Valid @RequestBody AmendIn in) {
        Map<String, Object> e = readable(id);
        if ("PUBLISHED".equals(e.get("results_state"))) stronger("Changing a published result");
        else manage((String) e.get("office"));
        UUID student = attemptOf(id, attempt);
        jdbc.sql("SELECT (assessment.cbt_amend_result(:a, :s, :o, :r)).version").param("a", attempt).param("s", in.score()).param("o", in.outcome(), Types.VARCHAR).param("r", in.reason()).query(Integer.class).single();
        return candidate(id, student);
    }

    /** the scores onto the course's score sheet as its examination component — the result pipeline carries them from there */
    @PostMapping("/exams/{id}/results/to-sheet")
    @PreAuthorize(MANAGERS)
    @Transactional
    Map<String, Object> toSheet(@PathVariable UUID id) {
        managed(id);
        int n = jdbc.sql("SELECT assessment.cbt_to_sheet(:id)").param("id", id).query(Integer.class).single();
        Map<String, Object> out = new LinkedHashMap<>(exam(id));
        out.put("written", n);
        return out;
    }

    /* ── small helpers ── */

    private static String blank(String s) {
        return s == null || s.isBlank() ? null : s.trim();
    }

    private static int n(Map<String, Object> m, String k) {
        Object v = m.get(k);
        return v == null ? 1 : ((Number) v).intValue();
    }

    @SuppressWarnings("unused")
    private String json(Object o) {
        return mapper.writeValueAsString(o);
    }
}
