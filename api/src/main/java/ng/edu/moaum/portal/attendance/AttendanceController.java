package ng.edu.moaum.portal.attendance;

import java.sql.Types;
import java.time.LocalDate;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import jakarta.validation.Valid;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

import ng.edu.moaum.portal.jupeb.JupebDocuments;
import ng.edu.moaum.portal.shared.DomainRuleViolation;
import ng.edu.moaum.portal.shared.FileObjects;
import ng.edu.moaum.portal.shared.NotFound;

import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.GrantedAuthority;
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
 * The University's attendance engine (V342), serving the JUPEB programme first. A register is one subject (and class, or
 * every class) on one day of a session and semester; its class list is drawn from the subject registrations, never typed.
 * An instructor assigned to the subject (and class) takes the register: marks every student at once (all present, then the
 * exceptions), corrects a saved mark only with a reason kept on its history, and locks it; the JUPEB Office takes and corrects
 * any register, unlocks one with a reason, assigns the instructors, sets the minimum attendance (never assumed) and reads the
 * reports. Every scope is decided here, on the server: an instructor sees only what they are assigned to.
 */
@RestController
@RequestMapping("/api/v1/attendance/jupeb")
class AttendanceController {

    static final String ANY = "hasAnyAuthority('OFFICE_jupeb','OFFICE_super','OFFICE_admin','OFFICE_lecturer')";
    static final String OFFICE = "hasAnyAuthority('OFFICE_jupeb','OFFICE_super')";
    static final String CONTEXT = "JUPEB";

    private final JdbcClient jdbc;
    private final FileObjects files;
    private final tools.jackson.databind.ObjectMapper json;
    private final String portalUrl;

    AttendanceController(JdbcClient jdbc, FileObjects files, tools.jackson.databind.ObjectMapper json,
                         @org.springframework.beans.factory.annotation.Value("${moaum.portal-url:https://moaum-portal-production.up.railway.app}") String portalUrl) {
        this.jdbc = jdbc;
        this.files = files;
        this.json = json;
        this.portalUrl = portalUrl == null ? "" : portalUrl.replaceAll("/+$", "");
    }

    private static boolean has(Authentication auth, String... authorities) {
        for (GrantedAuthority a : auth.getAuthorities()) for (String x : authorities) if (x.equals(a.getAuthority())) return true;
        return false;
    }

    /** the JUPEB Office (and Super): every register, every correction */
    private static boolean office(Authentication auth) {
        return has(auth, "OFFICE_jupeb", "OFFICE_super");
    }

    /** an office that reads everything without taking registers */
    private static boolean reader(Authentication auth) {
        return office(auth) || has(auth, "OFFICE_admin");
    }

    private static UUID me(Authentication auth) {
        return UUID.fromString(auth.getName());
    }

    private String sessionOr(String s) {
        return s == null || s.isBlank() ? jdbc.sql("SELECT jupeb.current_session()").query(String.class).single() : s.trim();
    }

    private Map<String, Object> register(UUID id) {
        return jdbc.sql("""
                SELECT r.id, r.session, r.semester, r.subject_ref, s.code AS subject_code, s.title AS subject_title, r.class_ref, cl.name AS class_name,
                       r.held_on::text AS held_on, r.topic, r.opened_at, r.saved_at, r.locked_at,
                       (SELECT p.surname || ', ' || p.given_names FROM iam.person p WHERE p.id = r.opened_by) AS opened_by,
                       (SELECT p.surname || ', ' || p.given_names FROM iam.person p WHERE p.id = r.locked_by) AS locked_by
                  FROM attendance.register r JOIN jupeb.subject s ON s.id = r.subject_ref LEFT JOIN jupeb.class cl ON cl.id = r.class_ref
                 WHERE r.id = :id AND r.context = 'JUPEB'
                """).param("id", id).query().listOfRows().stream().findFirst().orElseThrow(() -> new NotFound("attendance register", id));
    }

    /** whether this person may take a register of the subject and class: the office, or an instructor assigned */
    private boolean mayTake(Authentication auth, String session, UUID subject, UUID klass) {
        if (office(auth)) return true;
        if (!has(auth, "OFFICE_lecturer")) return false;
        return jdbc.sql("SELECT attendance.may_take(:p, 'JUPEB', :s, :sub, :c)").param("p", me(auth)).param("s", session).param("sub", subject)
                .param("c", klass, Types.OTHER).query(Boolean.class).single();
    }

    /** a register this person may read: any for an office, an assigned one for an instructor (a register they may not see does not exist for them) */
    private Map<String, Object> readable(Authentication auth, UUID id) {
        Map<String, Object> r = register(id);
        if (reader(auth)) return r;
        if (!mayTake(auth, String.valueOf(r.get("session")), (UUID) r.get("subject_ref"), (UUID) r.get("class_ref"))) throw new NotFound("attendance register", id);
        return r;
    }

    /* ── what this person may take ── */

    @GetMapping("/options")
    @PreAuthorize(ANY)
    @Transactional(readOnly = true)
    Map<String, Object> options(Authentication auth, @RequestParam(required = false) String session) {
        String s = sessionOr(session);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("session", s);
        out.put("sessions", jdbc.sql("""
                SELECT DISTINCT x.session FROM (SELECT session FROM jupeb.application UNION SELECT jupeb.current_session() UNION SELECT session FROM attendance.register) x
                 WHERE x.session IS NOT NULL ORDER BY x.session DESC
                """).query(String.class).list());
        out.put("office", office(auth));
        out.put("reader", reader(auth));
        if (reader(auth)) {
            out.put("subjects", jdbc.sql("SELECT id, code, title FROM jupeb.subject WHERE active ORDER BY title").query().listOfRows());
            out.put("classes", jdbc.sql("SELECT id, name, combination_id FROM jupeb.class WHERE session = :s ORDER BY name").param("s", s).query().listOfRows());
            out.put("assignments", List.of());
        } else {
            List<Map<String, Object>> mine = jdbc.sql("""
                    SELECT i.subject_ref AS subject_id, s.code, s.title, i.class_ref AS class_id, cl.name AS class_name
                      FROM attendance.instructor i JOIN jupeb.subject s ON s.id = i.subject_ref LEFT JOIN jupeb.class cl ON cl.id = i.class_ref
                     WHERE i.context = 'JUPEB' AND i.person_id = :p AND i.session = :s AND i.ended_at IS NULL ORDER BY s.title, cl.name
                    """).param("p", me(auth)).param("s", s).query().listOfRows();
            out.put("assignments", mine);
            out.put("subjects", mine.stream().map(m -> Map.of("id", m.get("subject_id"), "code", m.get("code"), "title", m.get("title"))).distinct().toList());
            out.put("classes", jdbc.sql("""
                    SELECT DISTINCT cl.id, cl.name, cl.combination_id FROM attendance.instructor i
                      JOIN jupeb.class cl ON cl.session = i.session AND (i.class_ref IS NULL OR cl.id = i.class_ref)
                     WHERE i.context = 'JUPEB' AND i.person_id = :p AND i.session = :s AND i.ended_at IS NULL ORDER BY cl.name
                    """).param("p", me(auth)).param("s", s).query().listOfRows());
        }
        Map<String, Object> pol = jdbc.sql("SELECT min_percent, warn_band, min_classes FROM attendance.policy_of('JUPEB', :s)").param("s", s)
                .query().listOfRows().stream().findFirst().orElse(Map.of());
        /* V354: the semester today by the JUPEB calendar, and today */
        out.put("semester", jdbc.sql("SELECT jupeb.current_semester(:s, NULL)").param("s", s).query(Integer.class).single());
        out.put("today", jdbc.sql("SELECT (now() AT TIME ZONE 'Africa/Lagos')::date::text").query(String.class).single());
        out.put("policy", pol.get("min_percent"));
        out.put("warnBand", pol.get("warn_band"));
        out.put("minClasses", pol.getOrDefault("min_classes", 3));
        return out;
    }

    /* ── the registers ── */

    @GetMapping("/registers")
    @PreAuthorize(ANY)
    @Transactional(readOnly = true)
    List<Map<String, Object>> registers(Authentication auth, @RequestParam(required = false) String session, @RequestParam(required = false) Integer semester,
                                        @RequestParam(required = false) UUID subject, @RequestParam(required = false) UUID klass) {
        return jdbc.sql("""
                SELECT r.id, r.session, r.semester, s.code AS subject_code, s.title AS subject_title, cl.name AS class_name, r.held_on::text AS held_on, r.topic,
                       r.saved_at, r.locked_at,
                       count(k.id) FILTER (WHERE k.status = 'PRESENT') AS present, count(k.id) FILTER (WHERE k.status = 'ABSENT') AS absent,
                       count(k.id) FILTER (WHERE k.status = 'LATE') AS late, count(k.id) FILTER (WHERE k.status = 'EXCUSED') AS excused, count(k.id) AS marked
                  FROM attendance.register r JOIN jupeb.subject s ON s.id = r.subject_ref LEFT JOIN jupeb.class cl ON cl.id = r.class_ref
                  LEFT JOIN attendance.mark k ON k.register_id = r.id
                 WHERE r.context = 'JUPEB' AND r.session = :s AND (:sem::int IS NULL OR r.semester = :sem::int)
                   AND (:sub::uuid IS NULL OR r.subject_ref = :sub::uuid) AND (:cls::uuid IS NULL OR r.class_ref = :cls::uuid)
                   AND (:all OR attendance.may_take(:p, 'JUPEB', r.session, r.subject_ref, r.class_ref))
                 GROUP BY r.id, s.code, s.title, cl.name
                 ORDER BY r.held_on DESC, s.title LIMIT 500
                """).param("s", sessionOr(session)).param("sem", semester, Types.INTEGER).param("sub", subject, Types.OTHER).param("cls", klass, Types.OTHER)
                .param("all", reader(auth)).param("p", me(auth)).query().listOfRows();
    }

    public record OpenIn(@NotBlank String session, @Min(1) @Max(3) int semester, @NotNull UUID subjectId, UUID classId, @NotNull LocalDate heldOn,
                         @Size(max = 300) String topic) {
    }

    /** the register of a subject (and class) on a day — opened once, found again after */
    @PostMapping("/registers")
    @PreAuthorize(ANY)
    @Transactional
    Map<String, Object> open(Authentication auth, @Valid @RequestBody OpenIn body) {
        if (!mayTake(auth, body.session().trim(), body.subjectId(), body.classId())) {
            throw new AccessDeniedException("You are not assigned to take this subject's attendance.");
        }
        UUID id = jdbc.sql("SELECT attendance.open_register('JUPEB', :s, :sem, :sub, :cls, :d, :t, :by)")
                .param("s", body.session().trim()).param("sem", body.semester()).param("sub", body.subjectId()).param("cls", body.classId(), Types.OTHER)
                .param("d", body.heldOn()).param("t", body.topic(), Types.VARCHAR).param("by", me(auth)).query(UUID.class).single();
        return detail(auth, id, null, 0, 200);
    }

    /** the register with its class list: each student once, their photograph, their mark if any — a page at a time */
    @GetMapping("/registers/{id}")
    @PreAuthorize(ANY)
    @Transactional(readOnly = true)
    Map<String, Object> detail(Authentication auth, @PathVariable UUID id, @RequestParam(required = false) String q,
                               @RequestParam(defaultValue = "0") int page, @RequestParam(defaultValue = "200") int size) {
        Map<String, Object> r = readable(auth, id);
        int n = Math.max(1, Math.min(size, 500));
        String term = q == null ? "" : q.trim();
        List<Map<String, Object>> rows = jdbc.sql("""
                SELECT x.member_ref, x.name, x.application_no, x.exam_no, x.combination_code, x.class_name, x.stream,
                       k.status, k.marked_time::text AS marked_time, k.remarks, k.marked_at,
                       EXISTS (SELECT 1 FROM jupeb.document d WHERE d.application_id = x.member_ref AND d.kind = 'PASSPORT') AS has_photo,
                       count(*) OVER () AS total_rows
                  FROM attendance.roster(:id) x LEFT JOIN attendance.mark k ON k.register_id = :id AND k.member_ref = x.member_ref
                 WHERE :q = '' OR x.name ILIKE '%' || :q || '%' OR x.application_no ILIKE '%' || :q || '%' OR coalesce(x.exam_no, '') ILIKE '%' || :q || '%'
                 ORDER BY x.name LIMIT :n OFFSET :o
                """).param("id", id).param("q", term).param("n", n).param("o", Math.max(0, page) * n).query().listOfRows();
        Map<String, Object> out = new LinkedHashMap<>(r);
        out.put("rows", rows);
        out.put("total", rows.isEmpty() ? 0 : ((Number) rows.get(0).get("total_rows")).longValue());
        out.put("page", page);
        out.put("size", n);
        out.put("counts", jdbc.sql("""
                SELECT (SELECT count(*) FROM attendance.roster(:id)) AS roster,
                       count(*) FILTER (WHERE status = 'PRESENT') AS present, count(*) FILTER (WHERE status = 'ABSENT') AS absent,
                       count(*) FILTER (WHERE status = 'LATE') AS late, count(*) FILTER (WHERE status = 'EXCUSED') AS excused
                  FROM attendance.mark WHERE register_id = :id
                """).param("id", id).query().singleRow());
        out.put("mayMark", r.get("locked_at") == null ? mayTake(auth, String.valueOf(r.get("session")), (UUID) r.get("subject_ref"), (UUID) r.get("class_ref")) : office(auth));
        out.put("mayUnlock", office(auth));
        return out;
    }

    public record Mark(@NotNull UUID member, @NotBlank @Pattern(regexp = "PRESENT|ABSENT|LATE|EXCUSED") String status,
                       @Pattern(regexp = "^(\\d{2}:\\d{2}(:\\d{2})?)?$") String time, @Size(max = 300) String remarks) {
    }

    public record MarksIn(@NotNull @Size(max = 2000) List<@Valid Mark> marks, @Size(max = 600) String reason) {
    }

    /** the marks of a register, in one batch; a saved mark is corrected only with a reason; a locked register only by the office */
    @PostMapping("/registers/{id}/marks")
    @PreAuthorize(ANY)
    @Transactional
    Map<String, Object> save(Authentication auth, @PathVariable UUID id, @Valid @RequestBody MarksIn body) {
        Map<String, Object> r = readable(auth, id);
        boolean override = office(auth);
        if (!override && !mayTake(auth, String.valueOf(r.get("session")), (UUID) r.get("subject_ref"), (UUID) r.get("class_ref"))) {
            throw new AccessDeniedException("You are not assigned to take this subject's attendance.");
        }
        String result = jdbc.sql("SELECT attendance.save_marks(:id, :m::jsonb, :why, :by, :ov)::text").param("id", id)
                .param("m", json.writeValueAsString(body.marks())).param("why", body.reason(), Types.VARCHAR).param("by", me(auth)).param("ov", override)
                .query(String.class).single();
        Map<String, Object> out = new LinkedHashMap<>(detail(auth, id, null, 0, 200));
        out.put("saved", json.readValue(result, Object.class));
        return out;
    }

    public record Lock(@Size(max = 600) String reason) {
    }

    @PostMapping("/registers/{id}/lock")
    @PreAuthorize(ANY)
    @Transactional
    Map<String, Object> lock(Authentication auth, @PathVariable UUID id) {
        Map<String, Object> r = readable(auth, id);
        if (!office(auth) && !mayTake(auth, String.valueOf(r.get("session")), (UUID) r.get("subject_ref"), (UUID) r.get("class_ref"))) {
            throw new AccessDeniedException("You are not assigned to this register.");
        }
        jdbc.sql("SELECT attendance.lock_register(:id, :by, true, NULL)").param("id", id).param("by", me(auth)).query().listOfRows();
        return detail(auth, id, null, 0, 200);
    }

    @PostMapping("/registers/{id}/unlock")
    @PreAuthorize(OFFICE)
    @Transactional
    Map<String, Object> unlock(Authentication auth, @PathVariable UUID id, @Valid @RequestBody Lock body) {
        register(id);
        jdbc.sql("SELECT attendance.lock_register(:id, :by, false, :why)").param("id", id).param("by", me(auth)).param("why", body.reason(), Types.VARCHAR).query().listOfRows();
        return detail(auth, id, null, 0, 200);
    }

    /** every correction of a register's marks: who, from what, to what, when and why */
    @GetMapping("/registers/{id}/changes")
    @PreAuthorize(ANY)
    @Transactional(readOnly = true)
    List<Map<String, Object>> changes(Authentication auth, @PathVariable UUID id) {
        readable(auth, id);
        return jdbc.sql("""
                SELECT c.changed_at, a.surname || ', ' || a.first_name AS name, a.application_no, a.exam_no, c.old_status, c.new_status, c.old_remarks, c.new_remarks, c.reason,
                       c.changed_office, (SELECT p.surname || ', ' || p.given_names FROM iam.person p WHERE p.id = c.changed_by) AS changed_by
                  FROM attendance.mark_change c JOIN jupeb.application a ON a.id = c.member_ref
                 WHERE c.register_id = :id ORDER BY c.changed_at DESC
                """).param("id", id).query().listOfRows();
    }

    /** a student's photograph, for an office or an instructor of a subject the student is registered for — the authoritative passport, not a copy */
    @GetMapping("/photo/{member}")
    @PreAuthorize(ANY)
    @Transactional(readOnly = true)
    ResponseEntity<byte[]> photo(Authentication auth, @PathVariable UUID member) {
        if (!reader(auth)) {
            boolean taught = jdbc.sql("""
                    SELECT EXISTS (SELECT 1 FROM attendance.instructor i
                                     JOIN jupeb.application a ON a.id = :m AND a.session = i.session AND (i.class_ref IS NULL OR a.class_id = i.class_ref)
                                     JOIN jupeb.subject_registration sr ON sr.application_id = a.id AND sr.subject_id = i.subject_ref
                                    WHERE i.context = 'JUPEB' AND i.person_id = :p AND i.ended_at IS NULL)
                    """).param("m", member).param("p", me(auth)).query(Boolean.class).single();
            if (!taught) throw new NotFound("photograph", member);
        }
        return JupebDocuments.stream(jdbc, files, member, "PASSPORT", null, true);
    }

    /* ── V354: the lectures due, from the timetable ── */

    /** the timetabled lectures from one day to another (today by default), each recorded, open, not held, due, missed or to come —
     *  an instructor's own subjects (and classes) only */
    @GetMapping("/lectures")
    @PreAuthorize(ANY)
    @Transactional(readOnly = true)
    Map<String, Object> lectures(Authentication auth, @RequestParam(required = false) String session, @RequestParam(required = false) LocalDate from,
                                 @RequestParam(required = false) LocalDate to, @RequestParam(required = false) String scope) {
        String s = sessionOr(session);
        LocalDate today = jdbc.sql("SELECT (now() AT TIME ZONE 'Africa/Lagos')::date").query(LocalDate.class).single();
        LocalDate f = from == null ? today : from;
        LocalDate t = to == null ? f : to;
        if ("semester".equals(scope)) {
            /* the semester so far: from the day it started by the calendar (or the last 30 days when the calendar does not say) to today */
            f = jdbc.sql("""
                    SELECT coalesce(CASE jupeb.current_semester(:s, NULL) WHEN 2 THEN jupeb.calendar_date(:s, 'SEMESTER_2_STARTS') ELSE jupeb.calendar_date(:s, 'TEACHING_STARTS') END,
                                    (now() AT TIME ZONE 'Africa/Lagos')::date - 30)
                    """).param("s", s).query(LocalDate.class).single();
            if (f.isAfter(today)) f = today;
            t = today;
        }
        if (t.isBefore(f) || t.isAfter(f.plusDays(400))) throw new DomainRuleViolation("ATT_RANGE", "Choose a range of at most 400 days, ending after it begins.",
                new DomainRuleViolation.Remedy("Narrow the dates.", "You"));
        List<Map<String, Object>> rows = jdbc.sql("""
                SELECT d.*, d.day::text AS held_on FROM jupeb.lectures_due(:s, :f, :t) d
                 WHERE :all OR attendance.may_take(:p, 'JUPEB', :s, d.subject_id, d.class_id)
                """).param("s", s).param("f", f).param("t", t).param("all", reader(auth)).param("p", me(auth)).query().listOfRows();
        Map<String, Long> counts = new LinkedHashMap<>();
        for (Map<String, Object> r : rows) counts.merge(String.valueOf(r.get("state")), 1L, Long::sum);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("session", s);
        out.put("from", f.toString());
        out.put("to", t.toString());
        out.put("today", today.toString());
        out.put("teachingStarts", jdbc.sql("SELECT jupeb.calendar_date(:s, 'TEACHING_STARTS')::text").param("s", s).query(String.class).single());
        out.put("semesterStarts", jdbc.sql("""
                SELECT (CASE jupeb.current_semester(:s, NULL) WHEN 2 THEN jupeb.calendar_date(:s, 'SEMESTER_2_STARTS') ELSE jupeb.calendar_date(:s, 'TEACHING_STARTS') END)::text
                """).param("s", s).query(String.class).single());
        out.put("counts", counts);
        out.put("rows", rows);
        return out;
    }

    private Map<String, Object> slot(UUID id) {
        return jdbc.sql("SELECT session, subject_id, class_id FROM jupeb.timetable_slot WHERE id = :id AND active").param("id", id).query().listOfRows().stream().findFirst()
                .orElseThrow(() -> new NotFound("timetable lecture", id));
    }

    public record DayIn(@NotNull LocalDate day, @Size(max = 300) String reason) {
    }

    /** the register of a timetabled lecture on its day — by its instructor or the office; the lecture's own register, found again after */
    @PostMapping("/slots/{id}/register")
    @PreAuthorize(ANY)
    @Transactional
    Map<String, Object> openLecture(Authentication auth, @PathVariable UUID id, @Valid @RequestBody DayIn body) {
        Map<String, Object> t = slot(id);
        if (!mayTake(auth, String.valueOf(t.get("session")), (UUID) t.get("subject_id"), (UUID) t.get("class_id"))) {
            throw new AccessDeniedException("You are not assigned to take this subject's attendance.");
        }
        UUID reg = jdbc.sql("SELECT jupeb.open_lecture_register(:s, :d, :by)").param("s", id).param("d", body.day()).param("by", me(auth)).query(UUID.class).single();
        return detail(auth, reg, null, 0, 200);
    }

    /** a timetabled lecture recorded as not held on a day, with the reason — by its instructor or the office */
    @PostMapping("/slots/{id}/not-held")
    @PreAuthorize(ANY)
    @Transactional
    Map<String, Object> notHeld(Authentication auth, @PathVariable UUID id, @Valid @RequestBody DayIn body) {
        Map<String, Object> t = slot(id);
        if (!mayTake(auth, String.valueOf(t.get("session")), (UUID) t.get("subject_id"), (UUID) t.get("class_id"))) {
            throw new AccessDeniedException("You are not assigned to this subject.");
        }
        String office = auth.getAuthorities().stream().map(GrantedAuthority::getAuthority).filter(a -> a.startsWith("OFFICE_")).map(a -> a.substring(7)).findFirst().orElse(null);
        UUID n = jdbc.sql("SELECT jupeb.record_not_held(:s, :d, :r, :by, :o)").param("s", id).param("d", body.day()).param("r", body.reason(), Types.VARCHAR)
                .param("by", me(auth)).param("o", office, Types.VARCHAR).query(UUID.class).single();
        return Map.of("id", n, "slot", id, "day", body.day().toString(), "notHeld", true);
    }

    /** a lecture recorded as not held, withdrawn — the JUPEB Office's */
    @PostMapping("/slots/{id}/not-held/withdraw")
    @PreAuthorize(OFFICE)
    @Transactional
    Map<String, Object> withdrawNotHeld(Authentication auth, @PathVariable UUID id, @Valid @RequestBody DayIn body) {
        int n = jdbc.sql("UPDATE jupeb.lecture_not_held SET withdrawn_at = now(), withdrawn_by = :by WHERE slot_id = :s AND held_on = :d AND withdrawn_at IS NULL")
                .param("by", me(auth)).param("s", id).param("d", body.day()).update();
        if (n == 0) throw new NotFound("lecture recorded as not held", id);
        return Map.of("slot", id, "day", body.day().toString(), "notHeld", false);
    }

    /* ── the reports ── */

    /** attendance by student, subject, class or date, for a session (and semester, subject, class); an instructor's own subjects only */
    @GetMapping("/reports")
    @PreAuthorize(ANY)
    @Transactional(readOnly = true)
    Map<String, Object> reports(Authentication auth, @RequestParam(required = false) String session, @RequestParam(required = false) Integer semester,
                                @RequestParam(required = false) UUID subject, @RequestParam(required = false) UUID klass,
                                @RequestParam(defaultValue = "student") String by, @RequestParam(defaultValue = "false") boolean below,
                                @RequestParam(required = false) Integer absences) {
        String s = sessionOr(session);
        String scope = """
                FROM attendance.register r JOIN attendance.mark k ON k.register_id = r.id
                 WHERE r.context = 'JUPEB' AND r.session = :s AND (:sem::int IS NULL OR r.semester = :sem::int)
                   AND (:sub::uuid IS NULL OR r.subject_ref = :sub::uuid) AND (:cls::uuid IS NULL OR r.class_ref = :cls::uuid)
                   AND (:all OR attendance.may_take(:p, 'JUPEB', r.session, r.subject_ref, r.class_ref))
                """;
        String rate = "round(100.0 * count(*) FILTER (WHERE k.status IN ('PRESENT', 'LATE')) / nullif(count(*) FILTER (WHERE k.status <> 'EXCUSED'), 0), 2)";
        String counts = "count(*) AS total, count(*) FILTER (WHERE k.status = 'PRESENT') AS present, count(*) FILTER (WHERE k.status = 'ABSENT') AS absent, "
                + "count(*) FILTER (WHERE k.status = 'LATE') AS late, count(*) FILTER (WHERE k.status = 'EXCUSED') AS excused, " + rate + " AS rate";
        Object min = jdbc.sql("SELECT min_percent FROM attendance.policy WHERE context = 'JUPEB' AND session IN (:s, '*') ORDER BY (session = '*') LIMIT 1")
                .param("s", s).query().listOfRows().stream().findFirst().map(m -> m.get("min_percent")).orElse(null);
        String sql = switch (by) {
            case "subject" -> "SELECT sj.code, sj.title, count(DISTINCT r.id) AS registers, count(DISTINCT k.member_ref) AS students, " + counts + " " + scope
                    + " GROUP BY sj.code, sj.title ORDER BY sj.title";
            case "class" -> "SELECT coalesce(cl.name, 'All classes') AS class_name, count(DISTINCT r.id) AS registers, count(DISTINCT k.member_ref) AS students, " + counts + " " + scope
                    + " GROUP BY cl.name ORDER BY cl.name NULLS FIRST";
            case "date" -> "SELECT r.held_on::text AS held_on, sj.code, sj.title, coalesce(cl.name, 'All classes') AS class_name, r.locked_at IS NOT NULL AS locked, " + counts + " " + scope
                    + " GROUP BY r.id, r.held_on, sj.code, sj.title, cl.name ORDER BY r.held_on DESC, sj.title";
            default -> "SELECT a.id AS member_ref, a.surname || ', ' || a.first_name || coalesce(' ' || a.middle_name, '') AS name, a.application_no, a.exam_no, sj.code, sj.title, "
                    + counts + ", " + "max(streak.run) AS longest_absence_run " + scope
                    + " GROUP BY a.id, a.surname, a.first_name, a.middle_name, a.application_no, a.exam_no, sj.code, sj.title"
                    + " HAVING (NOT :below OR (:min::numeric IS NOT NULL AND " + rate + " < :min::numeric))"
                    + " AND (:abs::int IS NULL OR count(*) FILTER (WHERE k.status = 'ABSENT') >= :abs::int)"
                    + " ORDER BY name, sj.title";
        };
        sql = sql.replace("FROM attendance.register r JOIN attendance.mark k ON k.register_id = r.id",
                "FROM attendance.register r JOIN attendance.mark k ON k.register_id = r.id JOIN jupeb.subject sj ON sj.id = r.subject_ref"
                        + " LEFT JOIN jupeb.class cl ON cl.id = r.class_ref JOIN jupeb.application a ON a.id = k.member_ref"
                        + ("student".equals(by) || !List.of("subject", "class", "date").contains(by)
                            ? " LEFT JOIN LATERAL (SELECT max(g.n) AS run FROM (SELECT count(*) AS n FROM (SELECT k2.status, r2.held_on,"
                              + " row_number() OVER (ORDER BY r2.held_on) - row_number() OVER (PARTITION BY k2.status ORDER BY r2.held_on) AS grp"
                              + " FROM attendance.mark k2 JOIN attendance.register r2 ON r2.id = k2.register_id"
                              + " WHERE k2.member_ref = k.member_ref AND r2.subject_ref = r.subject_ref AND r2.session = r.session) z"
                              + " WHERE z.status = 'ABSENT' GROUP BY z.grp) g) streak ON true"
                            : ""));
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("session", s);
        out.put("by", by);
        out.put("minPercent", min);
        out.put("rows", jdbc.sql(sql).param("s", s).param("sem", semester, Types.INTEGER).param("sub", subject, Types.OTHER).param("cls", klass, Types.OTHER)
                .param("all", reader(auth)).param("p", me(auth)).param("below", below).param("min", min, Types.NUMERIC).param("abs", absences, Types.INTEGER)
                .query().listOfRows());
        return out;
    }

    /* ── the instructors and the minimum: the JUPEB Office's ── */

    @GetMapping("/instructors")
    @PreAuthorize(OFFICE + " or hasAuthority('OFFICE_admin')")
    @Transactional(readOnly = true)
    List<Map<String, Object>> instructors(@RequestParam(required = false) String session) {
        return jdbc.sql("""
                SELECT i.id, i.session, s.code AS subject_code, s.title AS subject_title, cl.name AS class_name, p.surname || ', ' || p.given_names AS name,
                       p.staff_number, p.email, i.assigned_at
                  FROM attendance.instructor i JOIN jupeb.subject s ON s.id = i.subject_ref LEFT JOIN jupeb.class cl ON cl.id = i.class_ref
                  JOIN iam.person p ON p.id = i.person_id
                 WHERE i.context = 'JUPEB' AND i.session = :s AND i.ended_at IS NULL ORDER BY s.title, cl.name NULLS FIRST, p.surname
                """).param("s", sessionOr(session)).query().listOfRows();
    }

    public record InstructorIn(@NotBlank String session, @NotNull UUID subjectId, UUID classId, @NotBlank @Size(max = 160) String staff) {
    }

    /** a member of staff, by staff number or email, takes a subject's attendance (in a class, or every class) for the session */
    @PostMapping("/instructors")
    @PreAuthorize(OFFICE)
    @Transactional
    List<Map<String, Object>> assign(Authentication auth, @Valid @RequestBody InstructorIn body) {
        UUID person = jdbc.sql("SELECT id FROM iam.person WHERE upper(staff_number) = upper(btrim(:x)) OR lower(email) = lower(btrim(:x)) LIMIT 1")
                .param("x", body.staff()).query(UUID.class).optional()
                .orElseThrow(() -> new DomainRuleViolation("ATT_STAFF", "No member of staff has the staff number or email " + body.staff().trim() + ".",
                        new DomainRuleViolation.Remedy("Use the staff number or email on the staff record.", "JUPEB Office")));
        try {
            jdbc.sql("INSERT INTO attendance.instructor (context, session, subject_ref, class_ref, person_id, assigned_by) VALUES ('JUPEB', :s, :sub, :cls, :p, :by)")
                    .param("s", body.session().trim()).param("sub", body.subjectId()).param("cls", body.classId(), Types.OTHER).param("p", person).param("by", me(auth)).update();
        } catch (org.springframework.dao.DuplicateKeyException twice) {
            throw new DomainRuleViolation("ATT_INSTRUCTOR_EXISTS", "That member of staff already takes this subject's attendance.",
                    new DomainRuleViolation.Remedy("Nothing more is needed.", "JUPEB Office"));
        }
        return instructors(body.session());
    }

    @PostMapping("/instructors/{id}/end")
    @PreAuthorize(OFFICE)
    @Transactional
    List<Map<String, Object>> end(Authentication auth, @PathVariable UUID id) {
        String session = jdbc.sql("UPDATE attendance.instructor SET ended_at = now(), ended_by = :by WHERE id = :id AND ended_at IS NULL RETURNING session")
                .param("id", id).param("by", me(auth)).query(String.class).optional().orElseThrow(() -> new NotFound("instructor", id));
        return instructors(session);
    }

    public record PolicyIn(@NotBlank String session, @Min(0) @Max(100) Double minPercent, @Min(0) @Max(50) Double warnBand, @Min(1) @Max(50) Integer minClasses) {
    }

    /** the minimum attendance (a percentage of the classes not excused), for a session or every session ('*'); blank means none is set */
    @PutMapping("/policy")
    @PreAuthorize(OFFICE)
    @Transactional
    Map<String, Object> policy(Authentication auth, @Valid @RequestBody PolicyIn body) {
        String s = body.session().trim();
        if (!"*".equals(s) && !s.matches("^\\d{4}/\\d{4}$")) throw new NotFound("session", s);
        jdbc.sql("""
                INSERT INTO attendance.policy (context, session, min_percent, warn_band, min_classes, updated_by) VALUES ('JUPEB', :s, :m, :w, coalesce(:c, 3), :by)
                ON CONFLICT (context, session) DO UPDATE SET min_percent = EXCLUDED.min_percent, warn_band = EXCLUDED.warn_band, min_classes = EXCLUDED.min_classes,
                       updated_by = EXCLUDED.updated_by, updated_at = now()
                """).param("s", s).param("m", body.minPercent(), Types.NUMERIC).param("w", body.warnBand(), Types.NUMERIC).param("c", body.minClasses(), Types.INTEGER)
                .param("by", me(auth)).update();
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("session", s);
        out.put("minPercent", body.minPercent());
        out.put("warnBand", body.warnBand());
        out.put("minClasses", body.minClasses() == null ? 3 : body.minClasses());
        return out;
    }

    /* ── acting on the minimum (V344) ── */

    /** every JUPEB student of the session, subject by subject: below the minimum, at risk above it, or all; the minimum and its refinements with them */
    @GetMapping("/standing")
    @PreAuthorize(OFFICE + " or hasAuthority('OFFICE_admin')")
    @Transactional(readOnly = true)
    Map<String, Object> standing(@RequestParam(required = false) String session, @RequestParam(defaultValue = "below") String only) {
        String s = sessionOr(session);
        String o = only.trim().toLowerCase();
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("session", s);
        out.put("policy", jdbc.sql("SELECT min_percent, warn_band, min_classes FROM attendance.policy_of('JUPEB', :s)").param("s", s).query().listOfRows().stream().findFirst().orElse(null));
        out.put("rows", jdbc.sql("""
                SELECT st.*, (SELECT max(l.sent_at) FROM jupeb.reminder_log l WHERE l.application_id = st.member_ref AND l.kind = 'ATTENDANCE_LOW') AS last_warned
                  FROM attendance.jupeb_standing(:s) st
                 WHERE CASE :o WHEN 'below' THEN st.verdict = 'NOT_ELIGIBLE' WHEN 'risk' THEN st.at_risk ELSE true END
                 ORDER BY st.name, st.title, st.semester
                """).param("s", s).param("o", o).query().listOfRows());
        return out;
    }

    /** warn, now, every student below the minimum with enough classes counted — on the reminder's own rule (spacing, cap, one a day) */
    @PostMapping("/warn")
    @PreAuthorize(OFFICE)
    @Transactional
    Map<String, Object> warn() {
        String r = jdbc.sql("SELECT jupeb.send_reminders(now(), :p, 1000, 'OFFICE', 'ATTENDANCE_LOW')::text").param("p", portalUrl).query(String.class).single();
        return Map.of("result", json.readValue(r, Object.class));
    }
}
