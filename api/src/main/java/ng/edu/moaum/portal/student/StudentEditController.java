package ng.edu.moaum.portal.student;

import java.sql.Types;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import jakarta.validation.Valid;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

import ng.edu.moaum.portal.shared.AuditContext;
import ng.edu.moaum.portal.shared.AuditContextHolder;
import ng.edu.moaum.portal.shared.DomainRuleViolation;
import ng.edu.moaum.portal.shared.NotFound;
import ng.edu.moaum.portal.studentportal.StudentPortalService;

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
 * V642: the Academic Office student edit page — one place to read a student's record and correct it, every correction made by the
 * workflow that owns it. The identity, admission and placement fields are corrected here, all checked then all written in one
 * transaction (people.student_edit_apply); the level and the spillover years through the level functions the support desk uses
 * (people.support_set_level, people.support_set_spillover); the status through people.change_status; a course registration through
 * the registration engine's own add, drop and submit, with an academic override only on a reason and a description of the rule set
 * aside. Each is kept on people.student_edit under its STU-EDIT reference. The programme (faculty, department), the classification,
 * the matriculation number and graduation are corrected by their own workflows from the page (programme swap, classification,
 * matriculation correction, graduation reconciliation) and appear in the record's change history beside the edits.
 * <p>
 * Every read and write is checked against the acting office's grants (people.student_edit_grant: EDIT_STUDENT_ACADEMIC_RECORD and
 * its parts) and the student's reach; a correction made on an older reading of the record is refused (STU_EDIT_STALE).
 */
@RestController
@RequestMapping("/api/v1/student")
class StudentEditController {

    /** the offices that hold any grant on the page; each act is then checked against the office's own grants */
    private static final String HOLDERS = "hasAnyAuthority('OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar','OFFICE_super',"
            + "'OFFICE_records','OFFICE_ict','OFFICE_admin','OFFICE_audit','OFFICE_deputyaudit')";

    private static final tools.jackson.databind.ObjectMapper JSON = new tools.jackson.databind.ObjectMapper();

    /** the statuses a student is set to from the page; GRADUATED is graduation's own, ADMITTED is the intake's */
    private static final List<String> STATUSES = List.of("ACTIVE", "PROBATION", "DEFERRED", "SUSPENDED", "RUSTICATED", "WITHDRAWN",
            "VOLUNTARY_WITHDRAWAL", "EXPELLED", "TRANSFERRED_OUT", "DECEASED", "DORMANT");

    private final JdbcClient jdbc;
    private final StudentReach reach;
    private final StudentPortalService portal;

    StudentEditController(JdbcClient jdbc, StudentReach reach, StudentPortalService portal) {
        this.jdbc = jdbc;
        this.reach = reach;
        this.portal = portal;
    }

    /* ── who may do what ── */

    private static String office() {
        return AuditContextHolder.current().map(AuditContext::actorOffice).orElse("");
    }

    private static UUID actor() {
        return AuditContextHolder.current().map(AuditContext::actorId).orElse(null);
    }

    private List<String> permissions() {
        return jdbc.sql("SELECT unnest(people.student_edit_permissions(:o))").param("o", office()).query(String.class).list();
    }

    private void need(String permission) {
        if (!Boolean.TRUE.equals(jdbc.sql("SELECT people.student_edit_may(:o, :p)").param("o", office()).param("p", permission).query(Boolean.class).single())) {
            throw new AccessDeniedException("Your office does not hold " + permission + " on the student edit page.");
        }
    }

    private void anyGrant() {
        if (permissions().isEmpty()) {
            throw new AccessDeniedException("Your office holds no grant on the student edit page.");
        }
    }

    private void fresh(UUID id, String version) {
        String now = jdbc.sql("SELECT people.student_edit_version(:s)").param("s", id).query(String.class).single();
        if (version == null || !version.equals(now)) {
            throw new DomainRuleViolation("STU_EDIT_STALE", "This student record was updated by another user. Refresh the record before saving your changes.",
                    new DomainRuleViolation.Remedy("Refresh the record, check what changed, and make your change again.", "You"));
        }
    }

    private void reasoned(String reason) {
        String refused = jdbc.sql("SELECT people.student_edit_reason_refused(:r)").param("r", reason, Types.VARCHAR).query(String.class).optional().orElse(null);
        if (refused != null) {
            throw new DomainRuleViolation("STU_EDIT_REASON", "The reason for the change is not enough: " + refused + ".",
                    new DomainRuleViolation.Remedy("Say what was wrong and where the right value comes from — the document, the list or the decision.", "You"));
        }
    }

    private static String blank(String s) {
        return s == null || s.isBlank() ? null : s.trim();
    }

    @SuppressWarnings("unchecked")
    private static Map<String, Object> json(String text) {
        return text == null ? Map.of() : JSON.readValue(text, Map.class);
    }

    /* ── finding the student ── */

    /** the student by name, matriculation, JAMB, admission or application number, the record's id, phone or e-mail — twenty at most, read on the server */
    @GetMapping("/edit/search")
    @PreAuthorize(HOLDERS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> search(@RequestParam String q) {
        anyGrant();
        String t = q == null ? "" : q.trim();
        if (t.length() < 3) return List.of();
        String digits = t.replaceAll("[\\s()+-]", "");
        if (digits.startsWith("234") && digits.length() == 13) digits = "0" + digits.substring(3);
        return jdbc.sql("""
                SELECT s.id, upper(btrim(s.surname)) || coalesce(', ' || nullif(btrim(s.other_names), ''), '') AS name, s.matric_no, s.jamb_reg_no,
                       s.admission_no, p.name AS programme, s.current_level, s.status, pt.label AS programme_type,
                       (SELECT ap.application_no FROM admissions.application ap WHERE ap.candidate_id = s.candidate_id ORDER BY ap.application_no LIMIT 1) AS application_no
                  FROM people.student s
                  LEFT JOIN ref.programme p ON p.code = s.programme_code
                  LEFT JOIN people.student_classification c ON c.student_id = s.id
                  LEFT JOIN finance.programme_type pt ON pt.code = c.programme_type
                 WHERE s.duplicate_of IS NULL AND (
                         s.id::text = lower(:q)
                      OR upper(s.matric_no) LIKE upper(:q) || '%' OR upper(s.jamb_reg_no) = upper(:q) OR upper(s.admission_no) = upper(:q)
                      OR EXISTS (SELECT 1 FROM admissions.application ap WHERE ap.candidate_id = s.candidate_id AND upper(ap.application_no) = upper(:q))
                      OR EXISTS (SELECT 1 FROM people.student_contact k WHERE k.student_id = s.id AND (k.phone = :d OR lower(k.email) = lower(:q)))
                      OR (upper(s.surname) || ' ' || upper(coalesce(s.other_names, ''))) LIKE '%' || upper(:q) || '%'
                      OR (upper(coalesce(s.other_names, '')) || ' ' || upper(s.surname)) LIKE '%' || upper(:q) || '%')
                 ORDER BY (upper(s.matric_no) = upper(:q) OR upper(s.jamb_reg_no) = upper(:q)) DESC, s.surname, s.other_names
                 LIMIT 20
                """).param("q", t).param("d", digits).query().listOfRows();
    }

    /* ── the page: the record, its enrolments, the engine's reading, and what the office may do ── */

    @GetMapping("/students/{id}/edit")
    @PreAuthorize(HOLDERS)
    @Transactional(readOnly = true)
    Map<String, Object> page(@PathVariable UUID id) {
        anyGrant();
        reach.check(id);
        Map<String, Object> s = jdbc.sql("""
                SELECT s.id, s.person_id, s.surname, s.other_names, s.sex, s.date_of_birth, s.matric_no, s.matriculated_at, s.jamb_reg_no, s.admission_no,
                       s.programme_code, p.name AS programme, p.category AS programme_category, p.final_level, p.dept_code, d.name AS department,
                       coalesce(d.faculty_code, p.faculty_code) AS faculty_code, f.name AS faculty, s.entry_mode, s.entry_session, s.entry_level,
                       s.current_level, s.status, s.study_mode, s.centre_code, ce.name AS centre, s.curriculum_track, s.curriculum_version,
                       c.programme_type, pt.label AS programme_type_label, c.admission_route, coalesce(s.study_mode, c.study_mode) AS effective_study_mode,
                       c.classification_status,
                       (SELECT ap.application_no FROM admissions.application ap WHERE ap.candidate_id = s.candidate_id ORDER BY ap.application_no LIMIT 1) AS application_no,
                       cd.session AS admission_list_session, cd.programme AS admitted_programme, cd.offer_state AS admission_status,
                       (SELECT ap.decision_released_at FROM admissions.application ap WHERE ap.candidate_id = s.candidate_id ORDER BY ap.application_no LIMIT 1) AS admitted_on,
                       mr.label AS matriculation_run
                  FROM people.student s
                  LEFT JOIN ref.programme p ON p.code = s.programme_code
                  LEFT JOIN ref.department d ON d.code = p.dept_code
                  LEFT JOIN ref.faculty f ON f.code = coalesce(d.faculty_code, p.faculty_code)
                  LEFT JOIN ref.centre ce ON ce.code = s.centre_code
                  LEFT JOIN people.student_classification c ON c.student_id = s.id
                  LEFT JOIN finance.programme_type pt ON pt.code = c.programme_type
                  LEFT JOIN admissions.candidate cd ON cd.id = s.candidate_id
                  LEFT JOIN LATERAL (SELECT coalesce(r.ref, r.session) || ' · ' || r.session || coalesce(' · ' || to_char(r.run_at AT TIME ZONE 'Africa/Lagos', 'DD Mon YYYY'), '') AS label
                                       FROM people.matriculation_run r WHERE r.id = s.matriculation_run) mr ON true
                 WHERE s.id = :s
                """).param("s", id).query().listOfRows().stream().findFirst().orElseThrow(() -> new NotFound("student", id));
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("student", s);
        out.put("version", jdbc.sql("SELECT people.student_edit_version(:s)").param("s", id).query(String.class).single());
        out.put("permissions", permissions());
        out.put("contact", jdbc.sql("SELECT phone, email, address FROM people.student_contact WHERE student_id = :s").param("s", id).query().listOfRows().stream().findFirst().orElse(null));
        // one person, every enrolment: an undergraduate record and a postgraduate one are corrected apart
        out.put("enrolments", s.get("person_id") == null ? List.of() : jdbc.sql("""
                SELECT s.id, p.name AS programme, pt.label AS programme_type, s.status, s.current_level, s.entry_session, s.matric_no
                  FROM people.student s
                  LEFT JOIN ref.programme p ON p.code = s.programme_code
                  LEFT JOIN people.student_classification c ON c.student_id = s.id
                  LEFT JOIN finance.programme_type pt ON pt.code = c.programme_type
                 WHERE s.person_id = :p AND s.duplicate_of IS NULL ORDER BY s.entry_session, p.name
                """).param("p", s.get("person_id")).query().listOfRows());
        String session = portal.sessionFor(id);
        out.put("session", session);
        out.put("semester", portal.openSemester(id, session));
        // the cohort engine's reading — stored against calculated, and what it recommends
        out.put("position", jdbc.sql("""
                SELECT ap.jamb_year, ap.matric_year, ap.entry_session, ap.effective_cohort, ap.current_session, ap.current_level, ap.computed_level,
                       ap.final_level, ap.duration_years, ap.expected_completion, ap.spillover_years, ap.spillover_state, ap.graduation_state,
                       ap.graduation_session, ap.existing_status, ap.classification, ap.proposed_status, ap.rule, ap.confidence, ap.issues, ap.last_session,
                       (SELECT g.max_spillover_years FROM policy.progression_setting g LIMIT 1) AS max_spillover
                  FROM people.academic_position ap WHERE ap.student_id = :s
                """).param("s", id).query().listOfRows().stream().findFirst().orElse(null));
        out.put("levelOptions", json(jdbc.sql("SELECT people.level_options(:s)::text").param("s", id).query(String.class).single()));
        out.put("carryovers", jdbc.sql("SELECT course_code, title, units, failed_in FROM registration.carryovers(:s) ORDER BY course_code").param("s", id).query().listOfRows());
        out.put("registrations", jdbc.sql("""
                SELECT r.session, r.semester, r.level, r.status, registration.units_of(r.id) AS units,
                       (SELECT count(*) FROM registration.entry e WHERE e.registration_id = r.id AND e.status NOT IN ('DROPPED', 'WITHDRAWN')) AS courses
                  FROM registration.course_registration r WHERE r.student_id = :s ORDER BY r.session DESC, r.semester DESC
                """).param("s", id).query().listOfRows());
        out.put("statusHistory", jdbc.sql("SELECT from_status, to_status, instrument, effective_on, reason FROM people.status_change WHERE student_id = :s ORDER BY effective_on DESC, id")
                .param("s", id).query().listOfRows());
        out.put("programmeHistory", jdbc.sql("SELECT at, session, kind, programme_code, programme, level, from_programme, reference FROM people.programme_history(:s)")
                .param("s", id).query().listOfRows());
        out.put("finance", jdbc.sql("SELECT * FROM finance.position(:s, :ses)").param("s", id).param("ses", session).query().listOfRows().stream().findFirst().orElse(null));
        // the lists the page chooses from — the University's own
        out.put("lists", lists());
        out.put("statuses", STATUSES);
        return out;
    }

    private Map<String, Object> lists() {
        Map<String, Object> l = new LinkedHashMap<>();
        l.put("sessions", jdbc.sql("SELECT name, state FROM policy.academic_session WHERE archived_at IS NULL AND merged_into IS NULL ORDER BY name DESC").query().listOfRows());
        l.put("entryModes", List.of("UTME", "DIRECT_ENTRY", "TRANSFER", "POSTGRADUATE", "JUPEB", "SANDWICH", "CCE"));
        l.put("studyModes", List.of("FULL_TIME", "PART_TIME", "SANDWICH", "EVENING", "WEEKEND", "DISTANCE_LEARNING", "OTHER"));
        l.put("centres", jdbc.sql("SELECT code, name FROM ref.centre ORDER BY name").query().listOfRows());
        l.put("tracks", jdbc.sql("SELECT code FROM policy.curriculum_track ORDER BY code").query(String.class).list());
        l.put("programmeTypes", jdbc.sql("SELECT code, label FROM finance.programme_type ORDER BY label").query().listOfRows());
        l.put("faculties", jdbc.sql("SELECT code, name FROM ref.faculty ORDER BY name").query().listOfRows());
        l.put("departments", jdbc.sql("SELECT code, name, faculty_code FROM ref.department ORDER BY name").query().listOfRows());
        l.put("programmes", jdbc.sql("""
                SELECT p.code, p.name, p.dept_code, coalesce(d.faculty_code, p.faculty_code) AS faculty_code, p.category, p.final_level
                  FROM ref.programme p LEFT JOIN ref.department d ON d.code = p.dept_code
                 WHERE NOT coalesce(p.archived, false) ORDER BY p.name
                """).query().listOfRows());
        return l;
    }

    /* ── identity, admission and placement: corrected here, in one transaction ── */

    public record Edit(Map<String, String> changes, @Size(max = 2000) String reason, @NotBlank String version, Boolean confirmCritical,
                       @Size(max = 9) String effectiveSession, Integer effectiveSemester, @Size(max = 500) String evidence) {
    }

    @PutMapping("/students/{id}/edit")
    @PreAuthorize(HOLDERS)
    @Transactional
    Map<String, Object> edit(@PathVariable UUID id, @Valid @RequestBody Edit body) {
        anyGrant();
        reach.check(id);
        if (body.changes() == null || body.changes().isEmpty()) {
            throw new DomainRuleViolation("STU_EDIT_NOTHING", "Nothing was changed.", new DomainRuleViolation.Remedy("Change a value, then save.", "You"));
        }
        return json(jdbc.sql("SELECT people.student_edit_apply(:s, CAST(:c AS jsonb), :r, :v, :k, :es, :em, :ev)::text")
                .param("s", id).param("c", JSON.writeValueAsString(body.changes())).param("r", blank(body.reason()), Types.VARCHAR)
                .param("v", body.version()).param("k", Boolean.TRUE.equals(body.confirmCritical()))
                .param("es", blank(body.effectiveSession()), Types.VARCHAR).param("em", body.effectiveSemester(), Types.INTEGER)
                .param("ev", blank(body.evidence()), Types.VARCHAR).query(String.class).single());
    }

    /* ── the level and the spillover years: the level functions the support desk uses ── */

    public record LevelIn(@NotBlank String action, Integer level, Integer spilloverYear, Integer expected, @NotBlank @Size(max = 2000) String reason,
                          Boolean acknowledgeRegistration, @NotBlank String version) {
    }

    @PostMapping("/students/{id}/edit/level")
    @PreAuthorize(HOLDERS)
    @Transactional
    Map<String, Object> level(@PathVariable UUID id, @Valid @RequestBody LevelIn body) {
        String action = body.action().trim().toUpperCase();
        if (!List.of("PROGRESS", "CORRECTION", "SPILLOVER").contains(action)) {
            throw new DomainRuleViolation("LEVEL_ACTION", "A level is progressed (PROGRESS), corrected (CORRECTION) or set to a spillover year (SPILLOVER).");
        }
        need("SPILLOVER".equals(action) ? "EDIT_STUDENT_SPILLOVER" : "EDIT_STUDENT_LEVEL");
        reach.check(id);
        fresh(id, body.version());
        String reason = body.reason().trim();
        reasoned(reason);
        String session = portal.sessionFor(id);
        int semester = portal.openSemester(id, session);
        List<Map<String, Object>> registered = jdbc.sql("""
                SELECT r.semester, r.level, r.status FROM registration.course_registration r WHERE r.student_id = :s AND r.session = :ses ORDER BY r.semester
                """).param("s", id).param("ses", session).query().listOfRows();
        if (!registered.isEmpty() && !Boolean.TRUE.equals(body.acknowledgeRegistration())) {
            Map<String, Object> r = registered.get(registered.size() - 1);
            throw new DomainRuleViolation("LEVEL_REGISTRATION_ACK", "This student already has a course registration for " + session + " semester " + r.get("semester")
                    + " (" + String.valueOf(r.get("status")).toLowerCase() + ", " + r.get("level") + " Level). "
                    + ("PROGRESS".equals(action) ? "Progressing the level leaves it as it is; the courses the student may choose follow the new level."
                       : "Correcting the level sets the session's registration and enrolment to the corrected level, so the examination card, the GST & EPS permit and the receipt print it; the courses registered stay as they are."),
                    new DomainRuleViolation.Remedy("Confirm that you have seen this, then save again.", "You"));
        }
        Map<String, Object> done;
        if ("SPILLOVER".equals(action)) {
            if (body.spilloverYear() == null) throw new DomainRuleViolation("LEVEL_SPILLOVER_YEAR", "Say which spillover year: SP1, SP2, or the final year again.");
            done = json(jdbc.sql("SELECT people.support_set_spillover(:s, :y, :e, :r, :ses, :sem, NULL)::text")
                    .param("s", id).param("y", body.spilloverYear()).param("e", body.expected(), Types.INTEGER).param("r", reason)
                    .param("ses", session, Types.VARCHAR).param("sem", semester).query(String.class).single());
        } else {
            done = json(jdbc.sql("SELECT people.support_set_level(:s, :a, :l, :e, :r, :ses, :sem, NULL)::text")
                    .param("s", id).param("a", action).param("l", body.level(), Types.INTEGER).param("e", body.expected(), Types.INTEGER).param("r", reason)
                    .param("ses", session, Types.VARCHAR).param("sem", semester).query(String.class).single());
        }
        Map<String, Object> out = new LinkedHashMap<>(done);
        if (!Boolean.TRUE.equals(done.get("alreadyDone"))) {
            UUID decision = jdbc.sql("SELECT id FROM people.cohort_decision WHERE student_id = :s ORDER BY decided_at DESC LIMIT 1").param("s", id).query(UUID.class).optional().orElse(null);
            String to = String.valueOf(done.get("newLevel"));
            if ("SPILLOVER".equals(action)) to = to + (body.spilloverYear() == 0 ? " (final year)" : " (SP" + body.spilloverYear() + ")");
            out.put("reference", note(id, "LEVEL", "current_level", String.valueOf(done.get("previousLevel")), to, reason, "IMPORTANT",
                    "SPILLOVER".equals(action) ? "SPILLOVER" : "LEVEL", session, semester, null, "cohort_decision", decision));
        }
        return out;
    }

    private String note(UUID id, String section, String field, String from, String to, String reason, String severity, String type, String session,
                        Integer semester, String evidence, String relatedKind, UUID related) {
        return jdbc.sql("SELECT people.student_edit_note(:s, :sec, :f, :o, :n, :r, :sev, :t, :ses, :sem, :ev, :rk, :ri)")
                .param("s", id).param("sec", section).param("f", field).param("o", from, Types.VARCHAR).param("n", to, Types.VARCHAR)
                .param("r", reason, Types.VARCHAR).param("sev", severity).param("t", type).param("ses", session, Types.VARCHAR)
                .param("sem", semester, Types.INTEGER).param("ev", evidence, Types.VARCHAR).param("rk", relatedKind, Types.VARCHAR)
                .param("ri", related, Types.OTHER).query(String.class).single();
    }

    /* ── the status: people.change_status, on its instrument; graduation is graduation's own ── */

    public record StatusIn(@NotBlank @Size(max = 40) String to, @NotBlank @Size(max = 200) String instrument, LocalDate effectiveOn,
                           @Size(max = 9) String effectiveSession, Integer effectiveSemester, @NotBlank @Size(max = 2000) String reason,
                           Boolean confirmCritical, @NotBlank String version) {
    }

    @PostMapping("/students/{id}/edit/status")
    @PreAuthorize(HOLDERS)
    @Transactional
    Map<String, Object> status(@PathVariable UUID id, @Valid @RequestBody StatusIn body) {
        need("EDIT_STUDENT_STATUS");
        reach.check(id);
        String to = body.to().trim().toUpperCase();
        if ("GRADUATED".equals(to)) {
            throw new DomainRuleViolation("STU_EDIT_GRADUATION", "A student is graduated through graduation management, not by changing the status.",
                    new DomainRuleViolation.Remedy("Use the Graduation section of this page, which applies the graduation reconciliation.", "Academic Office"));
        }
        if (!STATUSES.contains(to)) {
            throw new DomainRuleViolation("STU_EDIT_STATUS", to + " is not a status set from this page.", new DomainRuleViolation.Remedy("Choose one of the statuses offered.", "You"));
        }
        if (!Boolean.TRUE.equals(body.confirmCritical())) {
            throw new DomainRuleViolation("STU_EDIT_CONFIRM", "A change of status is a critical change; confirm it to go on.", new DomainRuleViolation.Remedy("Tick the confirmation and save again.", "You"));
        }
        fresh(id, body.version());
        String reason = body.reason().trim();
        reasoned(reason);
        String session = blank(body.effectiveSession());
        if (session != null && !Boolean.TRUE.equals(jdbc.sql("SELECT EXISTS (SELECT 1 FROM policy.academic_session WHERE name = :s)").param("s", session).query(Boolean.class).single())) {
            throw new DomainRuleViolation("STU_EDIT_SESSION", session + " is not a session on the calendar.");
        }
        String from = jdbc.sql("SELECT status FROM people.student WHERE id = :s").param("s", id).query(String.class).single();
        if (to.equals(from)) {
            throw new DomainRuleViolation("STU_EDIT_NOTHING", "The student's status is " + to.toLowerCase() + " already.");
        }
        jdbc.sql("SELECT people.change_status(:s, :to, :i, :e, :r)").param("s", id).param("to", to).param("i", body.instrument().trim())
                .param("e", body.effectiveOn() == null ? LocalDate.now() : body.effectiveOn()).param("r", reason).query().singleRow();
        UUID change = jdbc.sql("SELECT id FROM people.status_change WHERE student_id = :s AND to_status = :to ORDER BY effective_on DESC, id DESC LIMIT 1")
                .param("s", id).param("to", to).query(UUID.class).optional().orElse(null);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("from", from);
        out.put("to", to);
        out.put("reference", note(id, "STATUS", "status", from, to, reason, "CRITICAL", "STATUS", session, body.effectiveSemester(), body.instrument().trim(),
                "status_change", change));
        return out;
    }

    /* ── course registration: the registration engine's own add, drop and submit; an academic override only on its reasons ── */

    @GetMapping("/students/{id}/edit/registration")
    @PreAuthorize(HOLDERS)
    @Transactional(readOnly = true)
    Map<String, Object> registration(@PathVariable UUID id, @RequestParam(required = false) String session, @RequestParam(defaultValue = "0") int semester) {
        anyGrant();
        reach.check(id);
        String ses = blank(session) == null ? portal.sessionFor(id) : session.trim();
        int sem = semester < 1 || semester > 3 ? portal.openSemester(id, ses) : semester;
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("view", portal.registrationView(id, ses, sem));
        out.put("current", current(id, ses, sem));
        out.put("manage", permissions().contains("EDIT_STUDENT_REGISTRATION"));
        out.put("override", permissions().contains("OVERRIDE_STUDENT_REGISTRATION"));
        return out;
    }

    private Map<String, Object> current(UUID id, String session, int semester) {
        Map<String, Object> out = new LinkedHashMap<>();
        Map<String, Object> reg = jdbc.sql("""
                SELECT r.id, r.status, r.level, r.submitted_at, r.approved_at, r.returned_comment, registration.units_of(r.id) AS units
                  FROM registration.course_registration r WHERE r.student_id = :s AND r.session = :ses AND r.semester = :sem
                """).param("s", id).param("ses", session).param("sem", semester).query().listOfRows().stream().findFirst().orElse(null);
        out.put("registration", reg);
        out.put("courses", reg == null ? List.of() : jdbc.sql("""
                SELECT e.offering_id, o.course_code, c.title, e.units, e.entry_type, coalesce(e.basis, c.kind) AS basis, c.level, o.semester, e.status,
                       e.support_override_at, e.support_override_reason
                  FROM registration.entry e
                  JOIN catalogue.offering o ON o.id = e.offering_id
                  JOIN catalogue.course c ON c.code = o.course_code
                 WHERE e.registration_id = :r
                 ORDER BY (e.status = 'DROPPED'), o.course_code
                """).param("r", reg.get("id")).query().listOfRows());
        return out;
    }

    private String snapshot(UUID id, String session, int semester) {
        Map<String, Object> c = current(id, session, semester);
        String status = c.get("registration") instanceof Map<?, ?> r ? String.valueOf(r.get("status")) : "NONE";
        List<String> courses = new ArrayList<>();
        for (Object o : (List<?>) c.get("courses")) if (o instanceof Map<?, ?> e && !"DROPPED".equals(e.get("status"))) courses.add(String.valueOf(e.get("course_code")));
        return status + (courses.isEmpty() ? "" : ": " + String.join(", ", courses));
    }

    @GetMapping("/students/{id}/edit/registration/checks")
    @PreAuthorize(HOLDERS)
    @Transactional(readOnly = true)
    Map<String, Object> checks(@PathVariable UUID id, @RequestParam String session, @RequestParam @Min(1) @Max(3) int semester, @RequestParam UUID offering,
                               @RequestParam(defaultValue = "add") String verb) {
        anyGrant();
        reach.check(id);
        String fn = "drop".equalsIgnoreCase(verb) ? "registration.support_drop_checks" : "registration.support_add_checks";
        List<Map<String, Object>> rules = jdbc.sql("SELECT * FROM " + fn + "(:s, :ses, :sem, :o) ORDER BY ord")
                .param("s", id).param("ses", session.trim()).param("sem", semester).param("o", offering).query().listOfRows();
        boolean hard = rules.stream().anyMatch(r -> !Boolean.TRUE.equals(r.get("passed")) && !Boolean.TRUE.equals(r.get("overridable")));
        boolean soft = rules.stream().anyMatch(r -> !Boolean.TRUE.equals(r.get("passed")) && Boolean.TRUE.equals(r.get("overridable")));
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("rules", rules);
        out.put("allowed", !hard && !soft);
        out.put("overridable", !hard && soft);
        out.put("mayOverride", permissions().contains("OVERRIDE_STUDENT_REGISTRATION"));
        return out;
    }

    /** the courses offered this session and semester beyond the student's menu, by code or title — what an override may add when the mapping is wrong */
    @GetMapping("/students/{id}/edit/registration/offerings")
    @PreAuthorize(HOLDERS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> offerings(@PathVariable UUID id, @RequestParam String session, @RequestParam @Min(1) @Max(3) int semester, @RequestParam String q) {
        anyGrant();
        reach.check(id);
        String t = q == null ? "" : q.trim();
        if (t.length() < 2) return List.of();
        return jdbc.sql("""
                SELECT o.id AS offering_id, o.course_code, c.title, coalesce(o.units, c.units) AS units, c.level, o.semester
                  FROM catalogue.offering o JOIN catalogue.course c ON c.code = o.course_code
                 WHERE o.session = :ses AND o.semester = :sem AND o.stream = 'REGULAR'
                   AND (upper(o.course_code) LIKE '%' || upper(:q) || '%' OR upper(c.title) LIKE '%' || upper(:q) || '%')
                 ORDER BY o.course_code LIMIT 30
                """).param("ses", session.trim()).param("sem", semester).param("q", t).query().listOfRows();
    }

    public record RegIn(@NotBlank String session, @Min(1) @Max(3) int semester, UUID offering, @NotBlank @Size(max = 2000) String reason,
                        Boolean override, @Size(max = 4000) String description) {
    }

    @PostMapping("/students/{id}/edit/registration/{verb}")
    @PreAuthorize(HOLDERS)
    @Transactional
    Map<String, Object> registrationAct(@PathVariable UUID id, @PathVariable String verb, @Valid @RequestBody RegIn body) {
        need("EDIT_STUDENT_REGISTRATION");
        reach.check(id);
        String v = verb.toLowerCase();
        String reason = body.reason().trim();
        reasoned(reason);
        boolean override = Boolean.TRUE.equals(body.override());
        if (override) {
            need("OVERRIDE_STUDENT_REGISTRATION");
            if (blank(body.description()) == null || body.description().trim().length() < 15) {
                throw new DomainRuleViolation("STU_EDIT_OVERRIDE", "An academic override says which rule is set aside and why — the migration, the historical record or the decision behind it.",
                        new DomainRuleViolation.Remedy("Describe the rule that fails and the justification for setting it aside.", "You"));
            }
        }
        String session = body.session().trim();
        int sem = body.semester();
        String before = snapshot(id, session, sem);
        Map<String, Object> result;
        String field;
        switch (v) {
            case "add", "restore" -> {
                if (body.offering() == null) throw new DomainRuleViolation("REG_OFFERING", "Name the course to add.", new DomainRuleViolation.Remedy("Choose it from the eligible courses.", "You"));
                result = json(jdbc.sql("SELECT registration.support_add(:s, :ses, :sem, :o, :ov, :by, :r)::text").param("s", id).param("ses", session).param("sem", sem)
                        .param("o", body.offering()).param("ov", override).param("by", actor(), Types.OTHER).param("r", reason).query(String.class).single());
                field = "course " + courseOf(body.offering()) + (Boolean.TRUE.equals(result.get("restored")) ? " restored" : " added");
            }
            case "drop" -> {
                if (body.offering() == null) throw new DomainRuleViolation("REG_OFFERING", "Name the course to drop.", new DomainRuleViolation.Remedy("Choose it from the registration.", "You"));
                result = json(jdbc.sql("SELECT registration.support_drop(:s, :ses, :sem, :o, :ov, :by, :r)::text").param("s", id).param("ses", session).param("sem", sem)
                        .param("o", body.offering()).param("ov", override).param("by", actor(), Types.OTHER).param("r", reason).query(String.class).single());
                field = "course " + courseOf(body.offering()) + " dropped";
            }
            case "submit" -> {
                result = json(jdbc.sql("SELECT registration.support_submit(:s, :ses, :sem, :ov, :by, :r)::text").param("s", id).param("ses", session).param("sem", sem)
                        .param("ov", override).param("by", actor(), Types.OTHER).param("r", reason).query(String.class).single());
                field = "registration submitted";
            }
            default -> throw new NotFound("registration act", verb);
        }
        boolean overridden = Boolean.TRUE.equals(result.get("overridden"));
        String evidence = overridden ? "Rule set aside: " + result.get("normalRule") + ". Justification: " + body.description().trim() : null;
        Map<String, Object> out = new LinkedHashMap<>(result);
        out.put("reference", note(id, "REGISTRATION", field, before, snapshot(id, session, sem), reason, overridden ? "CRITICAL" : "IMPORTANT",
                overridden ? "REGISTRATION_OVERRIDE" : "REGISTRATION", session, sem, evidence, null, null));
        out.put("view", portal.registrationView(id, session, sem));
        out.put("current", current(id, session, sem));
        return out;
    }

    private String courseOf(UUID offering) {
        return jdbc.sql("SELECT course_code FROM catalogue.offering WHERE id = :o").param("o", offering).query(String.class).optional().orElse("the course");
    }

    /* ── the record's change history, from every workflow that changes it, filtered ── */

    @GetMapping("/students/{id}/edit/history")
    @PreAuthorize(HOLDERS)
    @Transactional(readOnly = true)
    Map<String, Object> history(@PathVariable UUID id, @RequestParam(required = false) LocalDate from, @RequestParam(required = false) LocalDate to,
                                @RequestParam(required = false) String user, @RequestParam(required = false) String field,
                                @RequestParam(required = false) String type, @RequestParam(required = false) String q,
                                @RequestParam(defaultValue = "0") int page, @RequestParam(defaultValue = "50") int size) {
        need("VIEW_STUDENT_EDIT_HISTORY");
        reach.check(id);
        int sz = Math.min(Math.max(size, 1), 200);
        int pg = Math.max(page, 0);
        String where = """
                FROM people.student_edit_history(:s) h
                WHERE (CAST(:from AS date) IS NULL OR h.at >= (CAST(:from AS date)::timestamp AT TIME ZONE 'Africa/Lagos'))
                  AND (CAST(:to AS date) IS NULL OR h.at < ((CAST(:to AS date) + 1)::timestamp AT TIME ZONE 'Africa/Lagos'))
                  AND (CAST(:u AS text) IS NULL OR h.by_name ILIKE '%' || CAST(:u AS text) || '%' OR h.office ILIKE CAST(:u AS text))
                  AND (CAST(:f AS text) IS NULL OR h.field ILIKE '%' || CAST(:f AS text) || '%' OR h.section ILIKE CAST(:f AS text))
                  AND (CAST(:t AS text) IS NULL OR h.change_type = upper(CAST(:t AS text)))
                  AND (CAST(:q AS text) IS NULL OR h.old_value ILIKE '%' || CAST(:q AS text) || '%' OR h.new_value ILIKE '%' || CAST(:q AS text) || '%'
                       OR h.reason ILIKE '%' || CAST(:q AS text) || '%' OR h.reference ILIKE '%' || CAST(:q AS text) || '%')
                """;
        Map<String, Object> p = new LinkedHashMap<>();
        p.put("s", id);
        p.put("from", from);
        p.put("to", to);
        p.put("u", blank(user));
        p.put("f", blank(field));
        p.put("t", blank(type));
        p.put("q", blank(q));
        var count = jdbc.sql("SELECT count(*) " + where);
        var rows = jdbc.sql("SELECT h.* " + where + " ORDER BY h.at DESC NULLS LAST LIMIT :n OFFSET :o");
        for (var e : p.entrySet()) {
            int type0 = e.getValue() instanceof LocalDate ? Types.DATE : e.getValue() instanceof UUID ? Types.OTHER : Types.VARCHAR;
            count = count.param(e.getKey(), e.getValue(), type0);
            rows = rows.param(e.getKey(), e.getValue(), type0);
        }
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("total", count.query(Long.class).single());
        out.put("rows", rows.param("n", sz).param("o", pg * sz).query().listOfRows());
        out.put("page", pg);
        out.put("size", sz);
        out.put("types", jdbc.sql("SELECT DISTINCT change_type FROM people.student_edit_history(:s) ORDER BY 1").param("s", id).query(String.class).list());
        return out;
    }
}
