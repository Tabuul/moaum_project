package ng.edu.moaum.portal.cce;

import java.math.BigDecimal;
import java.sql.Types;
import java.time.LocalDate;
import java.time.LocalTime;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import jakarta.validation.Valid;
import jakarta.validation.constraints.DecimalMax;
import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

import ng.edu.moaum.portal.shared.AuditContextHolder;
import ng.edu.moaum.portal.shared.DomainRuleViolation;
import ng.edu.moaum.portal.shared.NotFound;

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
 * The CCE session in operation (V380): the CCE calendar, the Centre's classes in the CCE session and their lecturers, the
 * evening timetable and its periods, the CCE students' course registration, attendance on the register, and the CCE school
 * fees as the Bursary stated them. The Centre for Continuing Education and the Academic Office act; the Registry reads; the
 * Bursary reads the fees. Every rule — which session, which office, which clash — is the database's as well as this desk's.
 */
@RestController
@RequestMapping("/api/v1/cce")
class CceClassesController {

    private final JdbcClient jdbc;
    private final tools.jackson.databind.ObjectMapper json;

    CceClassesController(JdbcClient jdbc, tools.jackson.databind.ObjectMapper json) {
        this.jdbc = jdbc;
        this.json = json;
    }

    private String sessionOr(String s) {
        return s == null || s.isBlank() ? jdbc.sql("SELECT policy.route_session('CCE')").query(String.class).single() : s.trim();
    }

    private static String blank(String v) {
        return v == null || v.isBlank() ? null : v.trim();
    }

    /** the sessions the Centre works in: the CCE session, the one after it, and any its calendar or classes already name */
    private List<String> sessions() {
        return jdbc.sql("""
                SELECT s FROM (SELECT policy.route_session('CCE') AS s
                               UNION SELECT policy.session_after(policy.route_session('CCE'), 1)
                               UNION SELECT session FROM policy.route_semester WHERE route = 'CCE'
                               UNION SELECT session FROM catalogue.offering WHERE stream = 'CCE') x
                 WHERE s IS NOT NULL AND EXISTS (SELECT 1 FROM policy.academic_session a WHERE a.name = x.s)
                 ORDER BY s DESC
                """).query(String.class).list();
    }

    private List<Map<String, Object>> jsonList(Object v) {
        if (v == null) return List.of();
        return json.readValue(v.toString(), new tools.jackson.core.type.TypeReference<List<Map<String, Object>>>() { });
    }

    /** a class of the Centre's, or refused: the Centre's desk acts on its own classes only */
    private Map<String, Object> cceClass(UUID id) {
        Map<String, Object> o = jdbc.sql("SELECT id, course_code, session, semester, stream, lecturer_id FROM catalogue.offering WHERE id = :o")
                .param("o", id).query().listOfRows().stream().findFirst().orElseThrow(() -> new NotFound("class", id));
        if (!"CCE".equals(o.get("stream"))) {
            throw new DomainRuleViolation("CCE_CLASS_NOT_CCE", o.get("course_code") + " in " + o.get("session") + " is a full-time class; this desk acts on the Centre's classes only.",
                    new DomainRuleViolation.Remedy("Choose the CCE class of the course; a full-time class is the department's.", "Centre for Continuing Education"));
        }
        return o;
    }

    /* ── the CCE calendar ── */

    @GetMapping("/calendar")
    @PreAuthorize(CceDeskController.READ)
    @Transactional(readOnly = true)
    Map<String, Object> calendar(@RequestParam(required = false) String session) {
        String s = sessionOr(session);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("session", s);
        out.put("cceSession", jdbc.sql("SELECT policy.route_session('CCE')").query(String.class).single());
        out.put("undergraduateSession", jdbc.sql("SELECT policy.university_current_session()").query(String.class).optional().orElse(null));
        out.put("sessions", sessions());
        out.put("semesters", jdbc.sql("""
                SELECT n.number, rs.id, coalesce(rs.state, 'NOT_SET') AS state, rs.lectures_from, rs.lectures_to, rs.registration_opens, rs.registration_closes,
                       rs.late_registration_closes, rs.exams_from, rs.exams_to, rs.note, rs.updated_at, rs.updated_office,
                       nullif(btrim(coalesce(p.surname, '') || ', ' || coalesce(p.given_names, '')), ',') AS updated_by_name,
                       (SELECT count(*) FROM catalogue.offering o WHERE o.stream = 'CCE' AND o.session = :s AND o.semester = n.number) AS classes,
                       (SELECT count(*) FROM registration.course_registration r JOIN people.student st ON st.id = r.student_id
                         WHERE st.entry_mode = 'CCE' AND r.session = :s AND r.semester = n.number AND r.status IN ('SUBMITTED', 'APPROVED', 'LOCKED')) AS registered,
                       w.configured AS window_configured, w.state AS window_state, w.closes_at AS window_closes, w.reason AS window_reason
                  FROM generate_series(1, 3) n(number)
                  LEFT JOIN policy.route_semester rs ON rs.route = 'CCE' AND rs.session = :s AND rs.number = n.number
                  LEFT JOIN iam.person p ON p.id = rs.updated_by
                  CROSS JOIN LATERAL policy.window_state('CCE_COURSE_REGISTRATION', :s, n.number) w
                 ORDER BY n.number
                """).param("s", s).query().listOfRows());
        out.put("feesWindow", jdbc.sql("SELECT configured, state, closes_at, reason FROM policy.window_state('CCE_SCHOOL_FEES_PAYMENT', :s, NULL)").param("s", s).query().singleRow());
        return out;
    }

    public record Semester(@NotBlank @Pattern(regexp = "NOT_YET_OPEN|OPEN|CLOSED") String state, LocalDate lecturesFrom, LocalDate lecturesTo,
                           LocalDate registrationOpens, LocalDate registrationCloses, LocalDate lateRegistrationCloses, LocalDate examsFrom,
                           LocalDate examsTo, @Size(max = 600) String note, @Size(max = 500) String reason) {
    }

    @PutMapping("/calendar/{session}/{year}/{number}")
    @PreAuthorize(CceDeskController.DECIDE)
    @Transactional
    Map<String, Object> setSemester(@PathVariable String session, @PathVariable String year, @PathVariable @Min(1) @Max(3) int number,
                                    @Valid @RequestBody Semester body) {
        String s = session + "/" + year;
        jdbc.sql("SELECT policy.set_route_semester('CCE', :s, :n, :st, :lf, :lt, :ro, :rc, :lc, :ef, :et, :note, :r)")
                .param("s", s).param("n", number).param("st", body.state())
                .param("lf", body.lecturesFrom(), Types.DATE).param("lt", body.lecturesTo(), Types.DATE)
                .param("ro", body.registrationOpens(), Types.DATE).param("rc", body.registrationCloses(), Types.DATE).param("lc", body.lateRegistrationCloses(), Types.DATE)
                .param("ef", body.examsFrom(), Types.DATE).param("et", body.examsTo(), Types.DATE)
                .param("note", blank(body.note()), Types.VARCHAR).param("r", blank(body.reason()), Types.VARCHAR).query(UUID.class).single();
        return calendar(s);
    }

    /* ── the Centre's classes ── */

    @GetMapping("/classes")
    @PreAuthorize(CceDeskController.READ)
    @Transactional(readOnly = true)
    Map<String, Object> classes(@RequestParam(required = false) String session, @RequestParam(required = false) Integer semester,
                                @RequestParam(required = false) String q) {
        String s = sessionOr(session);
        String term = blank(q);
        List<Map<String, Object>> rows = jdbc.sql("""
                SELECT o.id, o.course_code, coalesce(o.title, c.title) AS title, coalesce(o.units, c.units) AS units, c.level, o.semester, c.kind,
                       c.dept_code, d.name AS department, f.name AS faculty, o.lecturer_id,
                       nullif(btrim(coalesce(lp.surname, '') || ', ' || coalesce(lp.given_names, '')), ',') AS lecturer,
                       o.second_examiner_id, nullif(btrim(coalesce(sp.surname, '') || ', ' || coalesce(sp.given_names, '')), ',') AS second_examiner,
                       (SELECT string_agg(DISTINCT co.programme_code || ' ' || co.level, ', ')
                          FROM catalogue.course_offer co JOIN ref.programme_route pr ON pr.programme_code = co.programme_code AND pr.route = 'CCE' AND pr.active
                         WHERE co.course_code = o.course_code) AS programmes,
                       (SELECT count(*) FROM registration.entry e JOIN registration.course_registration r ON r.id = e.registration_id
                         WHERE e.offering_id = o.id AND e.status IN ('REGISTERED', 'APPROVED') AND r.status IN ('SUBMITTED', 'APPROVED', 'LOCKED')) AS registered,
                       (SELECT count(*) FROM registration.entry e JOIN registration.course_registration r ON r.id = e.registration_id
                         WHERE e.offering_id = o.id AND e.status <> 'DROPPED' AND r.status IN ('DRAFT', 'RETURNED')) AS drafted,
                       coalesce((SELECT jsonb_agg(jsonb_build_object('id', sl.id, 'weekday', sl.weekday, 'starts_at', to_char(sl.starts_at, 'HH24:MI'),
                                                                     'ends_at', to_char(sl.ends_at, 'HH24:MI'), 'venue', sl.venue, 'kind', sl.kind) ORDER BY sl.weekday, sl.starts_at)
                                   FROM catalogue.class_slot sl WHERE sl.offering_id = o.id AND sl.ended_at IS NULL), '[]'::jsonb)::text AS slots,
                       (SELECT count(*) FROM attendance.register ar WHERE ar.context = 'COURSE' AND ar.subject_ref = o.id) AS registers
                  FROM catalogue.offering o
                  JOIN catalogue.course c ON c.code = o.course_code
                  LEFT JOIN ref.department d ON d.code = c.dept_code
                  LEFT JOIN ref.faculty f ON f.code = d.faculty_code
                  LEFT JOIN iam.person lp ON lp.id = o.lecturer_id
                  LEFT JOIN iam.person sp ON sp.id = o.second_examiner_id
                 WHERE o.stream = 'CCE' AND o.session = :s AND (:sem::int IS NULL OR o.semester = :sem)
                   AND (:q::text IS NULL OR o.course_code ILIKE '%' || :q || '%' OR c.title ILIKE '%' || :q || '%')
                 ORDER BY o.semester, c.level, o.course_code
                """).param("s", s).param("sem", semester, Types.INTEGER).param("q", term, Types.VARCHAR).query().listOfRows();
        List<Map<String, Object>> out = new ArrayList<>();
        for (Map<String, Object> r : rows) {
            Map<String, Object> m = new LinkedHashMap<>(r);
            m.put("slots", jsonList(r.get("slots")));
            out.add(m);
        }
        Map<String, Object> page = new LinkedHashMap<>();
        page.put("session", s);
        page.put("semester", semester);
        page.put("cceSession", jdbc.sql("SELECT policy.route_session('CCE')").query(String.class).single());
        page.put("sessions", sessions());
        page.put("programmesOnRoute", jdbc.sql("SELECT count(*) FROM ref.programme_route WHERE route = 'CCE' AND active").query(Long.class).single());
        page.put("classes", out);
        return page;
    }

    public record Open(@NotBlank @Pattern(regexp = "\\d{4}/\\d{4}") String session, @NotNull @Min(1) @Max(3) Integer semester) {
    }

    /** every class the semester needs, opened at once */
    @PostMapping("/classes/open")
    @PreAuthorize(CceDeskController.DECIDE)
    @Transactional
    Map<String, Object> open(@Valid @RequestBody Open body) {
        int n = jdbc.sql("SELECT catalogue.cce_open_classes(:s, :sem)").param("s", body.session()).param("sem", body.semester()).query(Integer.class).single();
        Map<String, Object> out = new LinkedHashMap<>(classes(body.session(), body.semester(), null));
        out.put("opened", n);
        return out;
    }

    public record AddClass(@NotBlank @Size(max = 20) String course, @NotBlank @Pattern(regexp = "\\d{4}/\\d{4}") String session, @NotNull @Min(1) @Max(3) Integer semester) {
    }

    @PostMapping("/classes")
    @PreAuthorize(CceDeskController.DECIDE)
    @Transactional
    Map<String, Object> add(@Valid @RequestBody AddClass body) {
        UUID id = jdbc.sql("SELECT catalogue.cce_add_class(:c, :s, :sem)").param("c", body.course()).param("s", body.session()).param("sem", body.semester())
                .query(UUID.class).single();
        Map<String, Object> out = new LinkedHashMap<>(classes(body.session(), body.semester(), null));
        out.put("classId", id);
        return out;
    }

    @PostMapping("/classes/{id}/withdraw")
    @PreAuthorize(CceDeskController.DECIDE)
    @Transactional
    Map<String, Object> withdraw(@PathVariable UUID id, @Valid @RequestBody CceDeskController.Reason body) {
        Map<String, Object> o = cceClass(id);
        jdbc.sql("SELECT catalogue.cce_withdraw_class(:o, :r)").param("o", id).param("r", body.reason().trim()).query().listOfRows();
        return classes(String.valueOf(o.get("session")), ((Number) o.get("semester")).intValue(), null);
    }

    public record Teaching(@NotNull UUID lecturerId, UUID secondExaminerId, Boolean overload) {
    }

    /** the lecturer (and second examiner) of a CCE class: any lecturer of the University, allocated by the Centre */
    @PutMapping("/classes/{id}/teaching")
    @PreAuthorize(CceDeskController.DECIDE)
    @Transactional
    Map<String, Object> teaching(@PathVariable UUID id, @Valid @RequestBody Teaching body) {
        Map<String, Object> o = cceClass(id);
        if (!Boolean.TRUE.equals(jdbc.sql("""
                SELECT EXISTS (SELECT 1 FROM iam.office_assignment a JOIN iam.person p ON p.id = a.person_id
                                WHERE a.person_id = :p AND a.office_code IN ('lecturer', 'hod') AND p.ended_on IS NULL
                                  AND a.valid_from <= current_date AND (a.valid_to IS NULL OR a.valid_to >= current_date))
                """).param("p", body.lecturerId()).query(Boolean.class).single())) {
            throw new DomainRuleViolation("CCE_LECTURER", "That person holds no lecturer's post now; a class is taught by a lecturer of the University.",
                    new DomainRuleViolation.Remedy("Choose a lecturer from the list.", "Centre for Continuing Education"));
        }
        jdbc.sql("SELECT catalogue.allocate_offering(:o, :l, :x, :ov)").param("o", id).param("l", body.lecturerId())
                .param("x", body.secondExaminerId(), Types.OTHER).param("ov", Boolean.TRUE.equals(body.overload())).query().listOfRows();
        return classes(String.valueOf(o.get("session")), ((Number) o.get("semester")).intValue(), null);
    }

    /** the lecturers a CCE class may be given: anyone holding a lecturer's (or a Head of Department's) post today */
    @GetMapping("/lecturers")
    @PreAuthorize(CceDeskController.DECIDE)
    @Transactional(readOnly = true)
    List<Map<String, Object>> lecturers(@RequestParam(required = false) String q, @RequestParam(required = false) String session) {
        String term = blank(q);
        String s = sessionOr(session);
        return jdbc.sql("""
                SELECT p.id, p.surname || ', ' || p.given_names AS name, p.staff_number,
                       string_agg(DISTINCT a.scope_id, ', ' ORDER BY a.scope_id) AS departments,
                       (SELECT count(*) FROM catalogue.offering o WHERE o.stream = 'CCE' AND o.session = :s AND o.lecturer_id = p.id) AS cce_classes
                  FROM iam.person p
                  JOIN iam.office_assignment a ON a.person_id = p.id AND a.office_code IN ('lecturer', 'hod') AND a.scope_kind = 'department'
                                               AND a.valid_from <= current_date AND (a.valid_to IS NULL OR a.valid_to >= current_date)
                 WHERE p.ended_on IS NULL
                   AND (:q::text IS NULL OR p.surname ILIKE '%' || :q || '%' OR p.given_names ILIKE '%' || :q || '%' OR coalesce(p.staff_number, '') ILIKE '%' || :q || '%')
                 GROUP BY p.id, p.surname, p.given_names, p.staff_number
                 ORDER BY p.surname, p.given_names LIMIT 40
                """).param("q", term, Types.VARCHAR).param("s", s).query().listOfRows();
    }

    /** the courses a class may be added for, by code or title */
    @GetMapping("/courses")
    @PreAuthorize(CceDeskController.DECIDE)
    @Transactional(readOnly = true)
    List<Map<String, Object>> courses(@RequestParam String q) {
        String term = blank(q);
        if (term == null || term.length() < 2) return List.of();
        return jdbc.sql("""
                SELECT c.code, c.title, c.units, c.level, c.semester, c.dept_code, d.name AS department
                  FROM catalogue.course c LEFT JOIN ref.department d ON d.code = c.dept_code
                 WHERE c.state <> 'ENDED' AND c.code NOT LIKE 'DMO %'
                   AND (upper(c.code) LIKE upper(:p) OR upper(replace(c.code, ' ', '')) LIKE upper(replace(:p, ' ', '')) OR c.title ILIKE '%' || :q || '%')
                 ORDER BY c.code LIMIT 25
                """).param("p", term + "%").param("q", term).query().listOfRows();
    }

    /* ── the CCE course load ── */

    /** the unit range a CCE student registers within at each level: the CCE load where the Academic Office stated one, else the University's */
    @GetMapping("/course-load")
    @PreAuthorize(CceDeskController.READ)
    @Transactional(readOnly = true)
    List<Map<String, Object>> courseLoad() {
        return jdbc.sql("""
                SELECT l.level, l.applies_to, l.min_units AS university_min, l.max_units AS university_max, l.probation_max_units AS university_probation_max,
                       r.min_units AS cce_min, r.max_units AS cce_max, r.probation_max_units AS cce_probation_max, r.instrument, r.updated_at,
                       nullif(btrim(coalesce(p.surname, '') || ', ' || coalesce(p.given_names, '')), ',') AS updated_by_name
                  FROM policy.level_limit l
                  LEFT JOIN policy.route_level_limit r ON r.route = 'CCE' AND r.level = l.level
                  LEFT JOIN iam.person p ON p.id = r.updated_by
                 WHERE l.level <= 600 ORDER BY l.level
                """).query().listOfRows();
    }

    public record Load(@Min(0) @Max(60) Integer minUnits, @Min(0) @Max(60) Integer maxUnits, @Min(0) @Max(60) Integer probationMaxUnits, @Size(max = 200) String instrument) {
    }

    /** the Academic Office states a level's CCE load; a blank range withdraws it (the University's applies again) */
    @PutMapping("/course-load/{level}")
    @PreAuthorize(CceDeskController.ACADEMIC)
    @Transactional
    List<Map<String, Object>> setCourseLoad(@PathVariable int level, @Valid @RequestBody Load body) {
        jdbc.sql("SELECT policy.set_route_level_limit('CCE', :l, :min, :max, :p, :i)").param("l", level).param("min", body.minUnits(), Types.INTEGER)
                .param("max", body.maxUnits(), Types.INTEGER).param("p", body.probationMaxUnits(), Types.INTEGER).param("i", blank(body.instrument()), Types.VARCHAR)
                .query().listOfRows();
        return courseLoad();
    }

    /* ── the evening timetable ── */

    @GetMapping("/timetable")
    @PreAuthorize(CceDeskController.READ)
    @Transactional(readOnly = true)
    Map<String, Object> timetable(@RequestParam(required = false) String session, @RequestParam(defaultValue = "1") @Min(1) @Max(3) int semester) {
        String s = sessionOr(session);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("session", s);
        out.put("semester", semester);
        out.put("sessions", sessions());
        out.put("slots", jdbc.sql("""
                SELECT sl.id, sl.offering_id, sl.weekday, to_char(sl.starts_at, 'HH24:MI') AS starts_at, to_char(sl.ends_at, 'HH24:MI') AS ends_at, sl.venue, sl.kind,
                       o.course_code, coalesce(o.title, c.title) AS title, coalesce(o.units, c.units) AS units, c.level, c.dept_code, d.name AS department,
                       f.name AS faculty, nullif(btrim(coalesce(lp.surname, '') || ', ' || coalesce(lp.given_names, '')), ',') AS lecturer,
                       (SELECT string_agg(DISTINCT co.programme_code || ' ' || co.level, ', ')
                          FROM catalogue.course_offer co JOIN ref.programme_route pr ON pr.programme_code = co.programme_code AND pr.route = 'CCE' AND pr.active
                         WHERE co.course_code = o.course_code) AS programmes
                  FROM catalogue.class_slot sl
                  JOIN catalogue.offering o ON o.id = sl.offering_id
                  JOIN catalogue.course c ON c.code = o.course_code
                  LEFT JOIN ref.department d ON d.code = c.dept_code
                  LEFT JOIN ref.faculty f ON f.code = d.faculty_code
                  LEFT JOIN iam.person lp ON lp.id = o.lecturer_id
                 WHERE sl.ended_at IS NULL AND o.stream = 'CCE' AND o.session = :s AND o.semester = :sem
                 ORDER BY sl.weekday, sl.starts_at, o.course_code
                """).param("s", s).param("sem", semester).query().listOfRows());
        out.put("unscheduled", jdbc.sql("""
                SELECT o.id, o.course_code, coalesce(o.title, c.title) AS title, c.level FROM catalogue.offering o JOIN catalogue.course c ON c.code = o.course_code
                 WHERE o.stream = 'CCE' AND o.session = :s AND o.semester = :sem
                   AND NOT EXISTS (SELECT 1 FROM catalogue.class_slot sl WHERE sl.offering_id = o.id AND sl.ended_at IS NULL)
                 ORDER BY c.level, o.course_code
                """).param("s", s).param("sem", semester).query().listOfRows());
        out.put("clashes", jdbc.sql("""
                SELECT kind, weekday, to_char(starts_at, 'HH24:MI') AS starts_at, to_char(ends_at, 'HH24:MI') AS ends_at, first_course, second_course, detail
                  FROM catalogue.cce_clashes(:s, :sem) ORDER BY weekday, starts_at, kind
                """).param("s", s).param("sem", semester).query().listOfRows());
        out.put("periods", periods(false));
        return out;
    }

    public record SlotIn(@Min(1) @Max(7) int weekday, @NotNull LocalTime startsAt, @NotNull LocalTime endsAt, @NotBlank @Size(max = 200) String venue,
                         @Pattern(regexp = "LECTURE|PRACTICAL|TUTORIAL") String kind) {
    }

    @PostMapping("/classes/{id}/slots")
    @PreAuthorize(CceDeskController.DECIDE)
    @Transactional
    Map<String, Object> addSlot(@PathVariable UUID id, @Valid @RequestBody SlotIn body) {
        Map<String, Object> o = cceClass(id);
        if (!body.endsAt().isAfter(body.startsAt())) {
            throw new DomainRuleViolation("CCE_SLOT_TIMES", "A lecture ends after it starts.", new DomainRuleViolation.Remedy("Correct the times.", "Centre for Continuing Education"));
        }
        jdbc.sql("INSERT INTO catalogue.class_slot (offering_id, weekday, starts_at, ends_at, venue, kind) VALUES (:o, :w, :s, :e, :v, :k)")
                .param("o", id).param("w", body.weekday()).param("s", body.startsAt()).param("e", body.endsAt()).param("v", body.venue().trim())
                .param("k", body.kind() == null ? "LECTURE" : body.kind()).update();
        return timetable(String.valueOf(o.get("session")), ((Number) o.get("semester")).intValue());
    }

    @PostMapping("/classes/{id}/slots/{slot}/end")
    @PreAuthorize(CceDeskController.DECIDE)
    @Transactional
    Map<String, Object> endSlot(@PathVariable UUID id, @PathVariable UUID slot) {
        Map<String, Object> o = cceClass(id);
        jdbc.sql("UPDATE catalogue.class_slot SET ended_at = now() WHERE id = :id AND offering_id = :o AND ended_at IS NULL").param("id", slot).param("o", id).update();
        return timetable(String.valueOf(o.get("session")), ((Number) o.get("semester")).intValue());
    }

    private List<Map<String, Object>> periods(boolean all) {
        return jdbc.sql("""
                SELECT id, label, to_char(starts_at, 'HH24:MI') AS starts_at, to_char(ends_at, 'HH24:MI') AS ends_at, active, ord
                  FROM policy.route_period WHERE route = 'CCE' AND (:all OR active) ORDER BY ord, starts_at
                """).param("all", all).query().listOfRows();
    }

    @GetMapping("/periods")
    @PreAuthorize(CceDeskController.READ)
    @Transactional(readOnly = true)
    List<Map<String, Object>> periodsList() {
        return periods(true);
    }

    public record PeriodIn(UUID id, @NotBlank @Size(max = 60) String label, @NotNull LocalTime startsAt, @NotNull LocalTime endsAt, Boolean active, Integer ord) {
    }

    @PutMapping("/periods")
    @PreAuthorize(CceDeskController.DECIDE)
    @Transactional
    List<Map<String, Object>> setPeriod(@Valid @RequestBody PeriodIn body) {
        jdbc.sql("SELECT policy.set_route_period(:id, 'CCE', :l, :s, :e, :a, :o)").param("id", body.id(), Types.OTHER).param("l", body.label().trim())
                .param("s", body.startsAt()).param("e", body.endsAt()).param("a", body.active() == null || body.active()).param("o", body.ord(), Types.INTEGER)
                .query(UUID.class).single();
        return periods(true);
    }

    /* ── course registration ── */

    /** each CCE student and where their registration for the semester stands, with the fees that clear it */
    @GetMapping("/registrations")
    @PreAuthorize(CceDeskController.READ)
    @Transactional(readOnly = true)
    Map<String, Object> registrations(@RequestParam(required = false) String session, @RequestParam(defaultValue = "1") @Min(1) @Max(3) int semester,
                                      @RequestParam(required = false) String status, @RequestParam(required = false) String q) {
        String s = sessionOr(session);
        String st = blank(status) == null ? null : status.trim().toUpperCase();
        List<Map<String, Object>> rows = jdbc.sql("""
                WITH pop AS (
                    SELECT x.id, coalesce(x.matric_no, x.admission_no) AS number, x.surname || ', ' || x.other_names AS name, x.programme_code, p.name AS programme,
                           x.current_level AS level, x.status AS student_status, r.id AS registration_id, coalesce(r.status, 'NONE') AS registration,
                           r.submitted_at, r.approved_at, CASE WHEN r.id IS NULL THEN 0 ELSE registration.units_of(r.id) END AS units,
                           finance.fee_stated(x.id, :s) AS fees_stated, finance.semester_cleared(x.id, :s, :sem) AS fees_cleared
                      FROM people.student x
                      JOIN ref.programme p ON p.code = x.programme_code
                      LEFT JOIN registration.course_registration r ON r.student_id = x.id AND r.session = :s AND r.semester = :sem
                     WHERE x.entry_mode = 'CCE' AND x.status IN ('ADMITTED', 'ACTIVE', 'PROBATION')
                       AND (:q::text IS NULL OR x.surname ILIKE '%' || :q || '%' OR x.other_names ILIKE '%' || :q || '%'
                            OR coalesce(x.matric_no, x.admission_no, '') ILIKE '%' || :q || '%'))
                SELECT * FROM pop WHERE (:st::text IS NULL OR registration = :st)
                 ORDER BY programme, level, name LIMIT 2000
                """).param("s", s).param("sem", semester).param("q", blank(q), Types.VARCHAR).param("st", st, Types.VARCHAR).query().listOfRows();
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("session", s);
        out.put("semester", semester);
        out.put("sessions", sessions());
        out.put("counts", jdbc.sql("""
                SELECT count(*) AS students,
                       count(*) FILTER (WHERE r.status IS NULL) AS none, count(*) FILTER (WHERE r.status IN ('DRAFT', 'RETURNED')) AS drafting,
                       count(*) FILTER (WHERE r.status = 'SUBMITTED') AS submitted, count(*) FILTER (WHERE r.status IN ('APPROVED', 'LOCKED')) AS approved
                  FROM people.student x
                  LEFT JOIN registration.course_registration r ON r.student_id = x.id AND r.session = :s AND r.semester = :sem
                 WHERE x.entry_mode = 'CCE' AND x.status IN ('ADMITTED', 'ACTIVE', 'PROBATION')
                """).param("s", s).param("sem", semester).query().singleRow());
        out.put("gate", jdbc.sql("""
                SELECT registration.cce_gate(x.id, :s, :sem) FROM people.student x WHERE x.entry_mode = 'CCE' AND x.status IN ('ADMITTED', 'ACTIVE', 'PROBATION') LIMIT 1
                """).param("s", s).param("sem", semester).query(String.class).optional().orElse(null));
        out.put("rows", rows);
        return out;
    }

    /* ── attendance ── */

    @GetMapping("/attendance")
    @PreAuthorize(CceDeskController.READ)
    @Transactional(readOnly = true)
    Map<String, Object> attendance(@RequestParam(required = false) String session, @RequestParam(required = false) Integer semester,
                                   @RequestParam(required = false) String faculty, @RequestParam(required = false) String dept,
                                   @RequestParam(required = false) String programme, @RequestParam(required = false) String course,
                                   @RequestParam(required = false) LocalDate from, @RequestParam(required = false) LocalDate to) {
        String s = sessionOr(session);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("session", s);
        out.put("semester", semester);
        out.put("sessions", sessions());
        out.put("policy", jdbc.sql("""
                SELECT p.session, p.min_percent, p.warn_band, p.min_classes, p.show_students, p.updated_at
                  FROM attendance.policy p WHERE p.context = 'CCE' AND p.session IN (:s, '*') ORDER BY (p.session = '*') LIMIT 1
                """).param("s", s).query().listOfRows().stream().findFirst().orElse(null));
        out.put("rows", jdbc.sql("SELECT * FROM attendance.course_report('CCE', :s, :sem, :f, :d, :p, :c, :from, :to)")
                .param("s", s).param("sem", semester, Types.INTEGER).param("f", blank(faculty), Types.VARCHAR).param("d", blank(dept), Types.VARCHAR)
                .param("p", blank(programme), Types.VARCHAR).param("c", blank(course), Types.VARCHAR)
                .param("from", from, Types.DATE).param("to", to, Types.DATE).query().listOfRows());
        out.put("classes", jdbc.sql("""
                SELECT o.id, o.course_code, coalesce(o.title, c.title) AS title, o.semester,
                       nullif(btrim(coalesce(lp.surname, '') || ', ' || coalesce(lp.given_names, '')), ',') AS lecturer,
                       count(DISTINCT r.id) AS registers, count(DISTINCT r.id) FILTER (WHERE r.locked_at IS NOT NULL) AS locked, max(r.held_on) AS last_held,
                       count(k.id) FILTER (WHERE k.status IN ('PRESENT', 'LATE')) AS attended, count(k.id) FILTER (WHERE k.status <> 'EXCUSED') AS counted
                  FROM catalogue.offering o
                  JOIN catalogue.course c ON c.code = o.course_code
                  LEFT JOIN iam.person lp ON lp.id = o.lecturer_id
                  LEFT JOIN attendance.register r ON r.context = 'COURSE' AND r.subject_ref = o.id
                                                 AND (:from::date IS NULL OR r.held_on >= :from) AND (:to::date IS NULL OR r.held_on <= :to)
                  LEFT JOIN attendance.mark k ON k.register_id = r.id
                 WHERE o.stream = 'CCE' AND o.session = :s AND (:sem::int IS NULL OR o.semester = :sem)
                   AND (:c::text IS NULL OR o.course_code = upper(:c))
                 GROUP BY o.id, o.course_code, coalesce(o.title, c.title), o.semester, lp.surname, lp.given_names
                 ORDER BY o.semester, o.course_code
                """).param("s", s).param("sem", semester, Types.INTEGER).param("c", blank(course), Types.VARCHAR)
                .param("from", from, Types.DATE).param("to", to, Types.DATE).query().listOfRows());
        out.put("faculties", jdbc.sql("SELECT code, name FROM ref.faculty ORDER BY name").query().listOfRows());
        out.put("programmes", jdbc.sql("""
                SELECT p.code, p.name, p.dept_code, p.faculty_code FROM ref.programme p JOIN ref.programme_route pr ON pr.programme_code = p.code AND pr.route = 'CCE' AND pr.active ORDER BY p.name
                """).query().listOfRows());
        return out;
    }

    public record Policy(@NotBlank @Pattern(regexp = "\\*|\\d{4}/\\d{4}") String session, @DecimalMin("0") @DecimalMax("100") BigDecimal minPercent,
                         @DecimalMin("0") @DecimalMax("50") BigDecimal warnBand, @Min(1) @Max(50) Integer minClasses, Boolean showStudents) {
    }

    @PutMapping("/attendance/policy")
    @PreAuthorize(CceDeskController.DECIDE)
    @Transactional
    Map<String, Object> setPolicy(@Valid @RequestBody Policy body) {
        jdbc.sql("SELECT attendance.set_cce_policy(:s, :m, :w, :n, :show)").param("s", body.session()).param("m", body.minPercent(), Types.NUMERIC)
                .param("w", body.warnBand(), Types.NUMERIC).param("n", body.minClasses(), Types.INTEGER).param("show", body.showStudents(), Types.BOOLEAN)
                .query().listOfRows();
        return attendance("*".equals(body.session()) ? null : body.session(), null, null, null, null, null, null, null);
    }

    /** a locked register of a CCE class reopened for correction, with the reason; the lecturer corrects and locks it again */
    @PostMapping("/attendance/registers/{id}/unlock")
    @PreAuthorize(CceDeskController.DECIDE)
    @Transactional
    Map<String, Object> unlock(@PathVariable UUID id, @Valid @RequestBody CceDeskController.Reason body) {
        Map<String, Object> r = jdbc.sql("""
                SELECT r.id, o.stream FROM attendance.register r JOIN catalogue.offering o ON o.id = r.subject_ref WHERE r.id = :id AND r.context = 'COURSE'
                """).param("id", id).query().listOfRows().stream().findFirst().orElseThrow(() -> new NotFound("register", id));
        if (!"CCE".equals(r.get("stream"))) {
            throw new DomainRuleViolation("CCE_CLASS_NOT_CCE", "That register is of a full-time class.", new DomainRuleViolation.Remedy("The department corrects its own registers.", "Head of Department"));
        }
        jdbc.sql("SELECT attendance.lock_register(:r, :a, false, :why)").param("r", id).param("a", AuditContextHolder.required().actorId())
                .param("why", body.reason().trim()).query().listOfRows();
        return Map.of("registerId", id, "locked", false);
    }

    /* ── the CCE school fees ── */

    /** the school-fee lines the Bursary stated for CCE in the session, the CCE students' standing against them, and every CCE payment by purpose */
    @GetMapping("/school-fees")
    @PreAuthorize(CceDeskController.FEES_READ)
    @Transactional(readOnly = true)
    Map<String, Object> schoolFees(@RequestParam(required = false) String session) {
        String s = sessionOr(session);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("session", s);
        out.put("sessions", sessions());
        out.put("lines", jdbc.sql("""
                SELECT f.id, f.item, f.amount, f.level, f.semester, f.kind, f.indigene, f.spillover, f.faculty_code, fa.name AS faculty, f.programme_code, p.name AS programme
                  FROM finance.fee_schedule f LEFT JOIN ref.faculty fa ON fa.code = f.faculty_code LEFT JOIN ref.programme p ON p.code = f.programme_code
                 WHERE f.session = :s AND f.ended_at IS NULL AND f.entry_mode = 'CCE'
                 ORDER BY f.kind, f.level NULLS FIRST, f.semester NULLS FIRST, f.ord, f.item
                """).param("s", s).query().listOfRows());
        out.put("fullTimeLines", jdbc.sql("SELECT count(*) FROM finance.fee_schedule WHERE session = :s AND ended_at IS NULL AND entry_mode IS DISTINCT FROM 'CCE'")
                .param("s", s).query(Long.class).single());
        out.put("window", jdbc.sql("SELECT configured, state, phase, closes_at, late_until, reason FROM policy.window_state('CCE_SCHOOL_FEES_PAYMENT', :s, NULL)").param("s", s).query().singleRow());
        out.put("students", jdbc.sql("""
                SELECT count(*) AS students, count(*) FILTER (WHERE x.stated) AS stated, count(*) FILTER (WHERE x.stated AND x.paid_in_full) AS paid_in_full,
                       count(*) FILTER (WHERE x.stated AND NOT x.paid_in_full AND x.paid > 0) AS part_paid, count(*) FILTER (WHERE x.stated AND x.paid = 0) AS unpaid,
                       coalesce(sum(x.due) FILTER (WHERE x.stated), 0) AS due, coalesce(sum(x.paid), 0) AS paid, coalesce(sum(x.balance) FILTER (WHERE x.stated), 0) AS balance
                  FROM (SELECT finance.fee_stated(st.id, :s) AS stated, pos.due, pos.paid, pos.balance, pos.paid_in_full
                          FROM people.student st CROSS JOIN LATERAL finance.position(st.id, :s) pos
                         WHERE st.entry_mode = 'CCE' AND st.status IN ('ADMITTED', 'ACTIVE', 'PROBATION')) x
                """).param("s", s).query().singleRow());
        out.put("payments", jdbc.sql("""
                SELECT 'STUDENT' AS payer, CASE WHEN r.purpose LIKE 'School fees%' THEN 'School fees' ELSE r.purpose END AS purpose,
                       count(*) AS payments, sum(r.amount) AS amount
                  FROM finance.payment_reference r JOIN people.student st ON st.id = r.student_id AND st.entry_mode = 'CCE'
                 WHERE r.session = :s AND r.confirmed_at IS NOT NULL
                 GROUP BY 2
                UNION ALL
                SELECT 'APPLICANT', initcap(lower(replace(f.kind, '_', ' '))) || ' fee', count(*), sum(f.amount)
                  FROM admissions.fee_reference f JOIN admissions.application a ON a.id = f.application_id
                  JOIN admissions.candidate c ON c.id = a.candidate_id AND c.entry_mode = 'CCE'
                 WHERE a.session = :s AND f.confirmed_at IS NOT NULL
                 GROUP BY f.kind
                 ORDER BY 1 DESC, 2
                """).param("s", s).query().listOfRows());
        return out;
    }
}
