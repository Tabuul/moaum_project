package ng.edu.moaum.portal.allocation;

import java.sql.Types;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

import ng.edu.moaum.portal.shared.DomainRuleViolation;
import ng.edu.moaum.portal.shared.NotFound;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * The course allocation desk of the Director of ICT and the ICT Support Desk (V408): the University's classes, held to the
 * acting office's reach (AllocationReach), with who teaches each; a lecturer found by name, staff number, email or department;
 * the checks before an allocation (catalogue.allocation_checks); the allocation itself through the one engine every desk uses
 * (catalogue.allocate_offering for the lead, catalogue.offering_teacher for a co-lecturer); the history every allocation
 * leaves (catalogue.allocation_event); a ticket named on an act, put on the ticket's timeline; the lecturer told. A course is
 * never created here, a fee never touched, a result never opened beyond what V041's allocation always opened.
 */
@RestController
@RequestMapping("/api/v1/allocation/desk")
class AllocationDeskController {

    static final String DESK = "hasAnyAuthority('OFFICE_ict','OFFICE_helpdeskhead','OFFICE_ictagent','OFFICE_admin','OFFICE_super')";
    private static final int MAX_UNITS = 12;

    private final JdbcClient jdbc;
    private final AllocationReach reach;

    AllocationDeskController(JdbcClient jdbc, AllocationReach reach) {
        this.jdbc = jdbc;
        this.reach = reach;
    }

    private static String blank(String s) {
        return s == null || s.isBlank() ? "" : s.trim();
    }

    private String sessionOr(String session) {
        String s = blank(session);
        return s.isEmpty() ? jdbc.sql("SELECT policy.university_current_session()").query(String.class).optional().orElse("") : s;
    }

    private int semesterOr(Integer semester, String session) {
        if (semester != null && semester >= 1 && semester <= 3) return semester;
        return jdbc.sql("SELECT coalesce(max(number), 1) FROM policy.semester WHERE session = :s AND state = 'OPEN'").param("s", session).query(Integer.class).single();
    }

    /* ── what the desk offers this office ── */

    /** the sessions, the current session and semester, the faculties, departments and programmes within reach, the capabilities held */
    @GetMapping("/options")
    @PreAuthorize(DESK)
    @Transactional(readOnly = true)
    Map<String, Object> options() {
        AllocationReach.Reach r = reach.require(AllocationReach.VIEW);
        String current = sessionOr(null);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("sessions", jdbc.sql("SELECT name, state, semesters FROM policy.academic_session WHERE state <> 'CANCELLED' ORDER BY starts_on DESC").query().listOfRows());
        out.put("currentSession", current);
        out.put("currentSemester", semesterOr(null, current));
        String inReach = reach.where(r, "d.code", "d.faculty_code");
        out.put("faculties", jdbc.sql("SELECT DISTINCT f.code, f.name FROM ref.faculty f JOIN ref.department d ON d.faculty_code = f.code WHERE d.ended_on IS NULL AND " + inReach + " ORDER BY f.name")
                .param("reach_depts", AllocationReach.depts(r)).param("reach_facs", AllocationReach.facs(r)).query().listOfRows());
        out.put("departments", jdbc.sql("SELECT d.code, d.name, d.faculty_code FROM ref.department d WHERE d.ended_on IS NULL AND " + inReach + " ORDER BY d.name")
                .param("reach_depts", AllocationReach.depts(r)).param("reach_facs", AllocationReach.facs(r)).query().listOfRows());
        out.put("programmes", jdbc.sql("SELECT p.code, p.name, p.dept_code FROM ref.programme p JOIN ref.department d ON d.code = p.dept_code WHERE d.ended_on IS NULL AND " + inReach + " ORDER BY p.name")
                .param("reach_depts", AllocationReach.depts(r)).param("reach_facs", AllocationReach.facs(r)).query().listOfRows());
        out.put("capabilities", reach.held());
        out.put("scope", r.words());
        return out;
    }

    /* ── the classes, held to the reach ── */

    private record Filter(String session, int semester, String faculty, String dept, String programme, Integer level, String q) {
    }

    private Filter filter(String session, Integer semester, String faculty, String dept, String programme, Integer level, String q) {
        String s = sessionOr(session);
        return new Filter(s, semesterOr(semester, s), blank(faculty).toUpperCase(), blank(dept).toUpperCase(), blank(programme).toUpperCase(), level, blank(q));
    }

    /** the classes of a semester in reach and the filters, as a CTE named cls (id, lecturer_id, co_count) */
    private String classes(AllocationReach.Reach r) {
        return """
                cls AS (
                    SELECT o.id, o.lecturer_id, (SELECT count(*) FROM catalogue.offering_teacher t WHERE t.offering_id = o.id) AS co_count,
                           c.level, o.course_code
                      FROM catalogue.offering o
                      JOIN catalogue.course c ON c.code = o.course_code
                      LEFT JOIN ref.department d ON d.code = c.dept_code
                      LEFT JOIN iam.person lp ON lp.id = o.lecturer_id
                     WHERE o.session = :s AND o.semester = :sem AND o.stream IN ('REGULAR', 'PG')
                       AND catalogue.runs_in(c.semester, c.both_semesters, :sem) AND c.state <> 'ENDED'
                       AND %s
                       AND (:fac = '' OR upper(d.faculty_code) = :fac) AND (:dept = '' OR upper(c.dept_code) = :dept)
                       AND (:prog = '' OR EXISTS (SELECT 1 FROM catalogue.course_offer co WHERE co.course_code = o.course_code AND upper(co.programme_code) = :prog))
                       AND (:level::int IS NULL OR c.level = :level)
                       AND (:q = '' OR o.course_code ILIKE '%%' || :q || '%%' OR replace(o.course_code, ' ', '') ILIKE '%%' || replace(:q, ' ', '') || '%%'
                            OR c.title ILIKE '%%' || :q || '%%' OR lp.surname ILIKE '%%' || :q || '%%' OR lp.given_names ILIKE '%%' || :q || '%%'
                            OR coalesce(lp.staff_number, '') ILIKE '%%' || :q || '%%'
                            OR EXISTS (SELECT 1 FROM catalogue.offering_teacher t JOIN iam.person tp ON tp.id = t.lecturer_id
                                        WHERE t.offering_id = o.id AND (tp.surname ILIKE '%%' || :q || '%%' OR coalesce(tp.staff_number, '') ILIKE '%%' || :q || '%%')))
                )
                """.formatted(reach.where(r, "c.dept_code", "d.faculty_code"));
    }

    private JdbcClient.StatementSpec bind(JdbcClient.StatementSpec q, AllocationReach.Reach r, Filter f) {
        return q.param("s", f.session()).param("sem", f.semester()).param("fac", f.faculty()).param("dept", f.dept()).param("prog", f.programme())
                .param("level", f.level(), Types.INTEGER).param("q", f.q()).param("reach_depts", AllocationReach.depts(r)).param("reach_facs", AllocationReach.facs(r));
    }

    /** the counts the dashboard opens with: classes, allocated, unallocated, with several lecturers, allocations, lecturers, conflicts */
    @GetMapping("/overview")
    @PreAuthorize(DESK)
    @Transactional(readOnly = true)
    Map<String, Object> overview(@RequestParam(required = false) String session, @RequestParam(required = false) Integer semester,
                                 @RequestParam(required = false) String faculty, @RequestParam(required = false) String dept,
                                 @RequestParam(required = false) String programme, @RequestParam(required = false) Integer level) {
        AllocationReach.Reach r = reach.require(AllocationReach.VIEW);
        Filter f = filter(session, semester, faculty, dept, programme, level, null);
        Map<String, Object> out = new LinkedHashMap<>(bind(jdbc.sql("WITH " + classes(r) + """
                SELECT count(*) AS classes,
                       count(*) FILTER (WHERE lecturer_id IS NOT NULL) AS allocated,
                       count(*) FILTER (WHERE lecturer_id IS NULL) AS unallocated,
                       count(*) FILTER (WHERE lecturer_id IS NOT NULL AND co_count > 0) AS several,
                       count(*) FILTER (WHERE lecturer_id IS NOT NULL) + coalesce(sum(co_count), 0) AS allocations,
                       (SELECT count(DISTINCT x) FROM (SELECT lecturer_id AS x FROM cls WHERE lecturer_id IS NOT NULL
                                                       UNION SELECT t.lecturer_id FROM catalogue.offering_teacher t WHERE t.offering_id IN (SELECT id FROM cls)) y) AS teaching,
                       (SELECT count(DISTINCT k.offering_id) FROM catalogue.allocation_conflicts(:s, :sem) k WHERE k.offering_id IN (SELECT id FROM cls)) AS conflicts
                  FROM cls
                """), r, f).query().singleRow());
        String inReach = reach.where(r, "upper(a.scope_id)", "d.faculty_code");
        out.put("lecturers", jdbc.sql("""
                SELECT count(DISTINCT a.person_id) FROM iam.office_assignment a JOIN iam.person p ON p.id = a.person_id AND p.ended_on IS NULL
                  LEFT JOIN ref.department d ON upper(d.code) = upper(a.scope_id)
                 WHERE a.office_code IN ('lecturer', 'hod') AND a.scope_kind = 'department'
                   AND a.valid_from <= current_date AND (a.valid_to IS NULL OR a.valid_to >= current_date)
                   AND (:fac = '' OR upper(d.faculty_code) = :fac) AND (:dept = '' OR upper(a.scope_id) = :dept) AND
                """ + inReach).param("fac", f.faculty()).param("dept", f.dept())
                .param("reach_depts", AllocationReach.depts(r)).param("reach_facs", AllocationReach.facs(r)).query(Long.class).single());
        out.put("session", f.session());
        out.put("semester", f.semester());
        out.put("scope", r.words());
        return out;
    }

    /** the classes, a page at a time: status ALLOCATED, UNALLOCATED, SEVERAL (more than one lecturer) or CONFLICT; q finds a code, a title or a lecturer */
    @GetMapping("/classes")
    @PreAuthorize(DESK)
    @Transactional(readOnly = true)
    Map<String, Object> classes(@RequestParam(required = false) String session, @RequestParam(required = false) Integer semester,
                                @RequestParam(required = false) String faculty, @RequestParam(required = false) String dept,
                                @RequestParam(required = false) String programme, @RequestParam(required = false) Integer level,
                                @RequestParam(required = false) String status, @RequestParam(required = false) String q,
                                @RequestParam(defaultValue = "1") int page, @RequestParam(defaultValue = "50") int size) {
        AllocationReach.Reach r = reach.require(AllocationReach.VIEW);
        Filter f = filter(session, semester, faculty, dept, programme, level, q);
        int n = Math.max(1, Math.min(size, 5000));
        int p = Math.max(1, page);
        String st = blank(status).toUpperCase();
        String statusWhere = switch (st) {
            case "ALLOCATED" -> "lecturer_id IS NOT NULL";
            case "UNALLOCATED" -> "lecturer_id IS NULL";
            case "SEVERAL" -> "lecturer_id IS NOT NULL AND co_count > 0";
            case "CONFLICT" -> "id IN (SELECT k.offering_id FROM catalogue.allocation_conflicts(:s, :sem) k)";
            default -> "TRUE";
        };
        List<Map<String, Object>> rows = bind(jdbc.sql("WITH " + classes(r) + ", pick AS (SELECT id, count(*) OVER () AS total FROM cls WHERE " + statusWhere
                + " ORDER BY level, course_code LIMIT :n OFFSET :off)" + """
                SELECT o.id, o.course_code, c.title, c.units, c.level, c.dept_code, d.name AS department, d.faculty_code, f.name AS faculty,
                       (SELECT string_agg(DISTINCT pr.name, '; ') FROM catalogue.course_offer co JOIN ref.programme pr ON pr.code = co.programme_code WHERE co.course_code = o.course_code) AS programmes,
                       o.lecturer_id, concat_ws(', ', nullif(btrim(lp.surname), ''), nullif(btrim(lp.given_names), '')) AS lecturer, lp.staff_number AS lecturer_staff_number,
                       (SELECT string_agg(concat_ws(', ', nullif(btrim(tp.surname), ''), nullif(btrim(tp.given_names), '')), '; ' ORDER BY tp.surname)
                          FROM catalogue.offering_teacher t JOIN iam.person tp ON tp.id = t.lecturer_id WHERE t.offering_id = o.id) AS co_lecturers,
                       CASE WHEN sp.id IS NULL THEN NULL ELSE concat_ws(', ', nullif(btrim(sp.surname), ''), nullif(btrim(sp.given_names), '')) END AS second_examiner,
                       (SELECT count(*) FROM registration.entry e JOIN registration.course_registration cr ON cr.id = e.registration_id
                         WHERE e.offering_id = o.id AND e.status IN ('REGISTERED', 'APPROVED') AND cr.status IN ('APPROVED', 'LOCKED')) AS registered,
                       (SELECT sh.stage FROM assessment.score_sheet sh WHERE sh.offering_id = o.id ORDER BY (sh.stage = 'ENTRY') LIMIT 1) AS stage,
                       o.allocated_on, (SELECT max(ev.at) FROM catalogue.allocation_event ev WHERE ev.offering_id = o.id) AS updated_at,
                       pick.total
                  FROM pick
                  JOIN catalogue.offering o ON o.id = pick.id
                  JOIN catalogue.course c ON c.code = o.course_code
                  LEFT JOIN ref.department d ON d.code = c.dept_code
                  LEFT JOIN ref.faculty f ON f.code = d.faculty_code
                  LEFT JOIN iam.person lp ON lp.id = o.lecturer_id
                  LEFT JOIN iam.person sp ON sp.id = o.second_examiner_id
                 ORDER BY c.level, o.course_code
                """), r, f).param("n", n).param("off", (p - 1) * n).query().listOfRows();
        long total = rows.isEmpty() ? 0 : ((Number) rows.get(0).get("total")).longValue();
        rows.forEach(m -> m.remove("total"));
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("rows", rows);
        out.put("total", total);
        out.put("page", p);
        out.put("size", n);
        out.put("session", f.session());
        out.put("semester", f.semester());
        return out;
    }

    /** one class: the course, its programmes, who teaches it, the class list's size, the score sheet, the history */
    @GetMapping("/classes/{offering}")
    @PreAuthorize(DESK)
    @Transactional(readOnly = true)
    Map<String, Object> one(@PathVariable UUID offering) {
        Map<String, Object> c = new LinkedHashMap<>(reach.onClass(offering, AllocationReach.VIEW));
        c.put("programmes", jdbc.sql("""
                SELECT DISTINCT pr.code, pr.name, co.level FROM catalogue.course_offer co JOIN ref.programme pr ON pr.code = co.programme_code
                 WHERE co.course_code = :c ORDER BY pr.name
                """).param("c", c.get("course_code")).query().listOfRows());
        c.put("lecturer", person((UUID) c.get("lecturer_id")));
        c.put("second_examiner", person((UUID) c.get("second_examiner_id")));
        c.put("co_lecturers", jdbc.sql("""
                SELECT t.lecturer_id AS id, concat_ws(', ', nullif(btrim(p.surname), ''), nullif(btrim(p.given_names), '')) AS name, p.staff_number,
                       t.programme_code, pr.name AS programme, t.added_at
                  FROM catalogue.offering_teacher t JOIN iam.person p ON p.id = t.lecturer_id LEFT JOIN ref.programme pr ON pr.code = t.programme_code
                 WHERE t.offering_id = :o ORDER BY p.surname
                """).param("o", offering).query().listOfRows());
        c.put("registered", jdbc.sql("""
                SELECT count(*) FROM registration.entry e JOIN registration.course_registration cr ON cr.id = e.registration_id
                 WHERE e.offering_id = :o AND e.status IN ('REGISTERED', 'APPROVED') AND cr.status IN ('APPROVED', 'LOCKED')
                """).param("o", offering).query(Long.class).single());
        c.put("stage", jdbc.sql("SELECT stage FROM assessment.score_sheet WHERE offering_id = :o ORDER BY (stage = 'ENTRY') LIMIT 1").param("o", offering).query(String.class).optional().orElse(null));
        c.put("twin", jdbc.sql("SELECT string_agg(o.course_code, ', ') FROM catalogue.offering_family(:o) f JOIN catalogue.offering o ON o.id = f WHERE f <> :o")
                .param("o", offering).query(String.class).optional().orElse(null));
        c.put("conflicts", jdbc.sql("SELECT kind, words FROM catalogue.allocation_conflicts(:s, :sem) WHERE offering_id = :o")
                .param("s", c.get("session")).param("sem", c.get("semester")).param("o", offering).query().listOfRows());
        c.put("history", history(" WHERE ev.offering_id = :o", Map.of("o", offering), 200));
        return c;
    }

    private Map<String, Object> person(UUID id) {
        if (id == null) return null;
        return jdbc.sql("""
                SELECT p.id, concat_ws(', ', nullif(btrim(p.surname), ''), nullif(btrim(p.given_names), '')) AS name, p.staff_number, p.email, p.ended_on,
                       array_to_string(catalogue.teaching_departments(p.id), ', ') AS departments
                  FROM iam.person p WHERE p.id = :p
                """).param("p", id).query().listOfRows().stream().findFirst().orElse(null);
    }

    /* ── the lecturers ── */

    /** teaching staff found by name, staff number, email or department — the University's, since a course may be taught across departments */
    @GetMapping("/lecturers")
    @PreAuthorize(DESK)
    @Transactional(readOnly = true)
    List<Map<String, Object>> lecturers(@RequestParam(required = false) String q, @RequestParam(required = false) String session,
                                        @RequestParam(required = false) Integer semester, @RequestParam(defaultValue = "25") int limit) {
        reach.require(AllocationReach.VIEW);
        String s = sessionOr(session);
        int sem = semesterOr(semester, s);
        String needle = blank(q);
        return jdbc.sql("""
                WITH teach AS (
                    SELECT a.person_id, array_agg(DISTINCT upper(a.scope_id)) AS depts
                      FROM iam.office_assignment a
                     WHERE a.office_code IN ('lecturer', 'hod') AND a.scope_kind = 'department'
                       AND a.valid_from <= current_date AND (a.valid_to IS NULL OR a.valid_to >= current_date)
                     GROUP BY a.person_id)
                SELECT p.id, concat_ws(', ', nullif(btrim(p.surname), ''), nullif(btrim(p.given_names), '')) AS name, p.staff_number, p.email,
                       (SELECT string_agg(d.name, ', ' ORDER BY d.name) FROM ref.department d WHERE upper(d.code) = ANY (t.depts)) AS department,
                       (SELECT string_agg(DISTINCT f.name, ', ') FROM ref.department d JOIN ref.faculty f ON f.code = d.faculty_code WHERE upper(d.code) = ANY (t.depts)) AS faculty,
                       catalogue.teaching_load(p.id, :s, :sem) AS load
                  FROM teach t JOIN iam.person p ON p.id = t.person_id
                 WHERE p.ended_on IS NULL
                   AND (:q = '' OR p.surname ILIKE '%' || :q || '%' OR p.given_names ILIKE '%' || :q || '%'
                        OR concat_ws(' ', p.given_names, p.surname) ILIKE '%' || :q || '%' OR concat_ws(', ', p.surname, p.given_names) ILIKE '%' || :q || '%'
                        OR coalesce(p.staff_number, '') ILIKE '%' || :q || '%' OR coalesce(p.email, '') ILIKE '%' || :q || '%'
                        OR EXISTS (SELECT 1 FROM ref.department d WHERE upper(d.code) = ANY (t.depts) AND (d.name ILIKE '%' || :q || '%' OR d.code ILIKE :q)))
                 ORDER BY p.surname, p.given_names
                 LIMIT :n
                """).param("q", needle).param("s", s).param("sem", sem).param("n", Math.max(1, Math.min(limit, 100))).query().listOfRows();
    }

    /** a lecturer and the classes they teach in a session (and semester, if named) — those within the office's reach, and how many lie outside */
    @GetMapping("/lecturers/{id}")
    @PreAuthorize(DESK)
    @Transactional(readOnly = true)
    Map<String, Object> lecturer(@PathVariable UUID id, @RequestParam(required = false) String session, @RequestParam(required = false) Integer semester) {
        AllocationReach.Reach r = reach.require(AllocationReach.VIEW);
        Map<String, Object> p = person(id);
        if (p == null) throw new NotFound("staff member", id);
        Map<String, Object> out = new LinkedHashMap<>(p);
        out.put("faculty", jdbc.sql("SELECT string_agg(DISTINCT f.name, ', ') FROM ref.department d JOIN ref.faculty f ON f.code = d.faculty_code WHERE upper(d.code) = ANY (catalogue.teaching_departments(:p))")
                .param("p", id).query(String.class).optional().orElse(null));
        String s = sessionOr(session);
        Integer sem = semester != null && semester >= 1 && semester <= 3 ? semester : null;
        List<Map<String, Object>> classes = jdbc.sql("""
                SELECT o.id, o.course_code, c.title, c.units, c.level, o.session, o.semester, c.dept_code, d.name AS department, d.faculty_code,
                       (SELECT string_agg(DISTINCT pr.name, '; ') FROM catalogue.course_offer co JOIN ref.programme pr ON pr.code = co.programme_code WHERE co.course_code = o.course_code) AS programmes,
                       CASE WHEN o.lecturer_id = :p THEN 'LECTURER' WHEN o.second_examiner_id = :p AND NOT EXISTS (SELECT 1 FROM catalogue.offering_teacher t WHERE t.offering_id = o.id AND t.lecturer_id = :p)
                            THEN 'SECOND_EXAMINER' ELSE 'CO_LECTURER' END AS role,
                       (SELECT sh.stage FROM assessment.score_sheet sh WHERE sh.offering_id = o.id ORDER BY (sh.stage = 'ENTRY') LIMIT 1) AS stage,
                       (%s) AS in_reach
                  FROM catalogue.offering o
                  JOIN catalogue.course c ON c.code = o.course_code
                  LEFT JOIN ref.department d ON d.code = c.dept_code
                 WHERE o.session = :s AND (:sem::int IS NULL OR o.semester = :sem)
                   AND (o.lecturer_id = :p OR o.second_examiner_id = :p OR EXISTS (SELECT 1 FROM catalogue.offering_teacher t WHERE t.offering_id = o.id AND t.lecturer_id = :p))
                 ORDER BY o.semester, c.level, o.course_code
                """.formatted(reach.where(r, "c.dept_code", "d.faculty_code"))).param("p", id).param("s", s).param("sem", sem, Types.INTEGER)
                .param("reach_depts", AllocationReach.depts(r)).param("reach_facs", AllocationReach.facs(r)).query().listOfRows();
        List<Map<String, Object>> shown = new ArrayList<>();
        int outside = 0;
        for (Map<String, Object> c : classes) {
            if (Boolean.TRUE.equals(c.remove("in_reach"))) shown.add(c);
            else outside++;
        }
        out.put("session", s);
        out.put("semester", sem);
        out.put("classes", shown);
        out.put("outside", outside);
        out.put("load", sem == null ? null : jdbc.sql("SELECT catalogue.teaching_load(:p, :s, :sem)").param("p", id).param("s", s).param("sem", sem).query(Integer.class).single());
        out.put("maxUnits", MAX_UNITS);
        return out;
    }

    /* ── before an allocation: the checks ── */

    /** whether the lecturer may take the class as lead (LECTURER) or co-lecturer (CO_LECTURER) — each check said; nothing written */
    @GetMapping("/check")
    @PreAuthorize(DESK)
    @Transactional(readOnly = true)
    Map<String, Object> check(@RequestParam UUID offering, @RequestParam UUID lecturer, @RequestParam(defaultValue = "LECTURER") String role) {
        reach.onClass(offering, AllocationReach.VIEW);
        return checks(offering, lecturer, role);
    }

    private Map<String, Object> checks(UUID offering, UUID lecturer, String role) {
        String rl = "CO_LECTURER".equalsIgnoreCase(role) ? "CO_LECTURER" : "LECTURER";
        List<Map<String, Object>> list = jdbc.sql("SELECT code, level, words FROM catalogue.allocation_checks(:o, :p, :r)")
                .param("o", offering).param("p", lecturer).param("r", rl).query().listOfRows();
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("checks", list);
        out.put("ok", list.stream().noneMatch(c -> "ERROR".equals(c.get("level"))));
        out.put("overload", list.stream().anyMatch(c -> "LOAD".equals(c.get("code")) && "WARNING".equals(c.get("level"))));
        return out;
    }

    /** the checks again on the server, as the act is made: an ERROR refuses with its own words, an overload only when meant */
    private void enforce(UUID offering, UUID lecturer, String role, boolean overloadMeant) {
        Map<String, Object> c = checks(offering, lecturer, role);
        @SuppressWarnings("unchecked")
        List<Map<String, Object>> list = (List<Map<String, Object>>) c.get("checks");
        for (Map<String, Object> x : list) {
            if ("ERROR".equals(x.get("level"))) {
                throw new DomainRuleViolation("ALLOC_" + x.get("code"), String.valueOf(x.get("words")),
                        new DomainRuleViolation.Remedy("DUPLICATE".equals(x.get("code")) ? "Nothing was changed." : "Correct this, then allocate again.", "You"));
            }
        }
        if (Boolean.TRUE.equals(c.get("overload")) && !overloadMeant) {
            String words = list.stream().filter(x -> "LOAD".equals(x.get("code"))).map(x -> String.valueOf(x.get("words"))).findFirst().orElse("Over the approved load.");
            throw new DomainRuleViolation("ALLOC_OVERLOAD", words, new DomainRuleViolation.Remedy("Tick “Allocate as an overload” if that is meant.", "You"));
        }
    }

    /* ── the acts, through the one engine ── */

    public record LecturerIn(@NotNull UUID lecturer, Boolean overload, @Size(max = 1000) String reason, @Size(max = 60) String ticket) {
    }

    public record CoLecturerIn(@NotNull UUID lecturer, @Size(max = 40) String programme, @Size(max = 1000) String reason, @Size(max = 60) String ticket) {
    }

    public record SecondIn(UUID person, @Size(max = 1000) String reason, @Size(max = 60) String ticket) {
    }

    public record RemoveIn(@Size(max = 1000) String reason, @Size(max = 60) String ticket) {
    }

    /** the ticket an act is made on: by its number (or id), one the agent's postings reach; the head and the Director reach every ticket */
    private UUID ticket(String ref) {
        String t = blank(ref);
        if (t.isEmpty()) return null;
        UUID id = jdbc.sql("SELECT id FROM helpdesk.ticket WHERE upper(number) = upper(:n) OR id::text = lower(:n)").param("n", t).query(UUID.class).optional()
                .orElseThrow(() -> new DomainRuleViolation("ALLOC_TICKET", "No support ticket has the number " + t + ".",
                        new DomainRuleViolation.Remedy("Check the ticket number, or leave it blank.", "You")));
        if (AllocationReach.agent() && !Boolean.TRUE.equals(jdbc.sql("SELECT helpdesk.can_view(:me, :t)").param("me", AllocationReach.actor()).param("t", id).query(Boolean.class).single())) {
            throw new DomainRuleViolation("ALLOC_TICKET_SCOPE", "Ticket " + t + " is outside your support scope.",
                    new DomainRuleViolation.Remedy("Work it from a queue you are posted to, or ask the Head of the Support Desk to assign it to you.", "Head of ICT Support Desk"));
        }
        return id;
    }

    /** the reason and ticket the history and the ticket's timeline carry (the triggers read them from the transaction) */
    private void context(String reason, UUID ticket) {
        if (!blank(reason).isEmpty()) jdbc.sql("SELECT set_config('moaum.reason', :r, true)").param("r", blank(reason)).query().listOfRows();
        jdbc.sql("SELECT set_config('moaum.allocation_ticket', :t, true)").param("t", ticket == null ? "" : ticket.toString()).query().listOfRows();
    }

    private static String need(String reason, String what) {
        String r = blank(reason);
        if (r.length() < 5) {
            throw new DomainRuleViolation("ALLOC_REASON", "Give the reason for " + what + ".",
                    new DomainRuleViolation.Remedy("Say why, in a few words: the history and the lecturer's notice carry it.", "You"));
        }
        return r;
    }

    private static String semesterWord(Object n) {
        int s = n instanceof Number x ? x.intValue() : 1;
        return s == 1 ? "First" : s == 2 ? "Second" : "Third";
    }

    private void tell(UUID person, UUID offering, String subject, String body) {
        jdbc.sql("""
                SELECT platform.queue_notice('EMAIL', p.email, :subj, :body, 'offering', :o)
                  FROM iam.person p WHERE p.id = :p AND nullif(btrim(coalesce(p.email, '')), '') IS NOT NULL
                """).param("subj", subject).param("body", body).param("o", offering).param("p", person).query().listOfRows();
    }

    private String nameOf(UUID person) {
        return jdbc.sql("SELECT concat_ws(' ', nullif(btrim(given_names), ''), nullif(btrim(surname), '')) FROM iam.person WHERE id = :p").param("p", person)
                .query(String.class).optional().orElse("the lecturer");
    }

    /** the lead lecturer: allocated where there is none, reassigned (with a reason) where there is; the second examiner stays */
    @PostMapping("/classes/{offering}/lecturer")
    @PreAuthorize(DESK)
    @Transactional
    Map<String, Object> allocate(@PathVariable UUID offering, @Valid @RequestBody LecturerIn body) {
        Map<String, Object> c = reach.onClass(offering, AllocationReach.ALLOCATE);
        UUID previous = (UUID) c.get("lecturer_id");
        boolean reassign = previous != null;
        enforce(offering, body.lecturer(), "LECTURER", Boolean.TRUE.equals(body.overload()));
        String reason = reassign ? need(body.reason(), "the reassignment") : blank(body.reason());
        UUID ticket = ticket(body.ticket());
        context(reason.isEmpty() ? "Course allocated on the allocation desk" : reason, ticket);
        jdbc.sql("SET LOCAL lock_timeout = '8s'").update();
        UUID second = (UUID) c.get("second_examiner_id");
        // the lead becomes the lead only: a co-lecturer row of theirs on this class is folded into the lead
        jdbc.sql("DELETE FROM catalogue.offering_teacher WHERE offering_id IN (SELECT catalogue.offering_family(:o)) AND lecturer_id = :p")
                .param("o", offering).param("p", body.lecturer()).update();
        jdbc.sql("SELECT catalogue.allocate_offering(:o, :lec, :sec, :ov)").param("o", offering).param("lec", body.lecturer())
                .param("sec", second, Types.OTHER).param("ov", Boolean.TRUE.equals(body.overload())).query().listOfRows();
        String course = c.get("course_code") + " — " + c.get("title");
        String when = c.get("session") + ", " + semesterWord(c.get("semester")) + " Semester";
        String name = nameOf(body.lecturer());
        String summary = (reassign ? "Reassigned " : "Allocated ") + c.get("course_code") + " (" + when + ") to " + name + (reassign ? " in place of " + nameOf(previous) : "");
        jdbc.sql("SELECT helpdesk.note_allocation(:t, :s, :r)").param("t", ticket, Types.OTHER).param("s", summary).param("r", reason).query().listOfRows();
        tell(body.lecturer(), offering, "Course allocation: " + course,
                "Course " + course + " has been allocated to you for " + when + ", as the lead lecturer. It is on your teaching page.");
        if (reassign) {
            tell(previous, offering, "Course allocation changed: " + c.get("course_code"),
                    "You are no longer the lead lecturer of " + course + " for " + when + ". The class has been allocated to another lecturer.");
        }
        return Map.of("offering", offering, "lecturer", body.lecturer(), "reassigned", reassign,
                "message", "Course successfully allocated to " + name + ".");
    }

    /** a co-lecturer added, posted to one programme's group where the class has several */
    @PostMapping("/classes/{offering}/co-lecturers")
    @PreAuthorize(DESK)
    @Transactional
    Map<String, Object> addCoLecturer(@PathVariable UUID offering, @Valid @RequestBody CoLecturerIn body) {
        Map<String, Object> c = reach.onClass(offering, AllocationReach.ALLOCATE);
        UUID ticket = ticket(body.ticket());
        enforce(offering, body.lecturer(), "CO_LECTURER", true);
        String group = blank(body.programme()).isEmpty() ? null : blank(body.programme()).toUpperCase();
        if (group != null && jdbc.sql("SELECT count(*) FROM catalogue.course_offer WHERE course_code = :c AND upper(programme_code) = :p")
                .param("c", c.get("course_code")).param("p", group).query(Long.class).single() == 0) {
            throw new DomainRuleViolation("ALLOC_GROUP", "That programme does not offer " + c.get("course_code") + ".",
                    new DomainRuleViolation.Remedy("Choose a programme that carries the course, or post the co-lecturer to every programme.", "You"));
        }
        String reason = blank(body.reason());
        context(reason.isEmpty() ? "Co-lecturer added on the allocation desk" : reason, ticket);
        jdbc.sql("""
                INSERT INTO catalogue.offering_teacher (offering_id, lecturer_id, added_by, programme_code) VALUES (:o, :p, :by, :g)
                ON CONFLICT (offering_id, lecturer_id) DO NOTHING
                """).param("o", offering).param("p", body.lecturer()).param("by", AllocationReach.actor(), Types.OTHER).param("g", group, Types.VARCHAR).update();
        String course = c.get("course_code") + " — " + c.get("title");
        String when = c.get("session") + ", " + semesterWord(c.get("semester")) + " Semester";
        String name = nameOf(body.lecturer());
        jdbc.sql("SELECT helpdesk.note_allocation(:t, :s, :r)").param("t", ticket, Types.OTHER)
                .param("s", "Added " + name + " as a co-lecturer of " + c.get("course_code") + " (" + when + ")").param("r", reason).query().listOfRows();
        tell(body.lecturer(), offering, "Course allocation: " + course,
                "Course " + course + " has been allocated to you for " + when + ", as a co-lecturer. It is on your teaching page.");
        return Map.of("offering", offering, "lecturer", body.lecturer(), "message", name + " added as a co-lecturer of " + c.get("course_code") + ".");
    }

    /** a co-lecturer taken off the class, with the reason; the history keeps that they taught it */
    @PostMapping("/classes/{offering}/co-lecturers/{lecturer}/remove")
    @PreAuthorize(DESK)
    @Transactional
    Map<String, Object> removeCoLecturer(@PathVariable UUID offering, @PathVariable UUID lecturer, @Valid @RequestBody RemoveIn body) {
        Map<String, Object> c = reach.onClass(offering, AllocationReach.REMOVE);
        String reason = need(body.reason(), "removing the co-lecturer");
        UUID ticket = ticket(body.ticket());
        if (jdbc.sql("SELECT count(*) FROM catalogue.offering_teacher WHERE offering_id = :o AND lecturer_id = :p").param("o", offering).param("p", lecturer).query(Long.class).single() == 0) {
            throw new DomainRuleViolation("ALLOC_NOT_CO_LECTURER", nameOf(lecturer) + " is not a co-lecturer of " + c.get("course_code") + ".",
                    new DomainRuleViolation.Remedy("Nothing was changed. The lead lecturer is changed by reassigning the class.", "You"));
        }
        context(reason, ticket);
        jdbc.sql("DELETE FROM catalogue.offering_teacher WHERE offering_id = :o AND lecturer_id = :p").param("o", offering).param("p", lecturer).update();
        String when = c.get("session") + ", " + semesterWord(c.get("semester")) + " Semester";
        String name = nameOf(lecturer);
        jdbc.sql("SELECT helpdesk.note_allocation(:t, :s, :r)").param("t", ticket, Types.OTHER)
                .param("s", "Removed " + name + " as a co-lecturer of " + c.get("course_code") + " (" + when + ")").param("r", reason).query().listOfRows();
        tell(lecturer, offering, "Course allocation changed: " + c.get("course_code"),
                "You are no longer a co-lecturer of " + c.get("course_code") + " — " + c.get("title") + " for " + when + ".");
        return Map.of("offering", offering, "lecturer", lecturer, "message", name + " removed as a co-lecturer of " + c.get("course_code") + ".");
    }

    /** the second examiner, who verifies the lead's marks: set or changed (never the lead), with the class's lead kept */
    @PostMapping("/classes/{offering}/second-examiner")
    @PreAuthorize(DESK)
    @Transactional
    Map<String, Object> secondExaminer(@PathVariable UUID offering, @Valid @RequestBody SecondIn body) {
        Map<String, Object> c = reach.onClass(offering, AllocationReach.ALLOCATE);
        UUID lead = (UUID) c.get("lecturer_id");
        if (lead == null) {
            throw new DomainRuleViolation("ALLOC_NO_LEAD", "Allocate the lead lecturer first; the second examiner verifies the lead's marks.",
                    new DomainRuleViolation.Remedy("Allocate the class, then name its second examiner.", "You"));
        }
        if (body.person() != null && body.person().equals(lead)) {
            throw new DomainRuleViolation("ALLOC_SECOND_IS_LEAD", "The second examiner cannot be the lecturer: the person who enters the marks may not verify them.",
                    new DomainRuleViolation.Remedy("Choose another member of staff.", "You"));
        }
        if (body.person() != null && !jdbc.sql("""
                SELECT coalesce(cardinality(catalogue.teaching_departments(:p)) > 0 AND (SELECT p.ended_on IS NULL FROM iam.person p WHERE p.id = :p), false)
                """).param("p", body.person()).query(Boolean.class).single()) {
            throw new DomainRuleViolation("ALLOC_SECOND_NOT_TEACHING", nameOf(body.person()) + " is not an active lecturer, so cannot be a second examiner.",
                    new DomainRuleViolation.Remedy("Choose an active lecturer.", "You"));
        }
        UUID ticket = ticket(body.ticket());
        String reason = c.get("second_examiner_id") == null ? blank(body.reason()) : need(body.reason(), "changing the second examiner");
        context(reason.isEmpty() ? "Second examiner named on the allocation desk" : reason, ticket);
        jdbc.sql("SELECT catalogue.allocate_offering(:o, :lec, :sec, true)").param("o", offering).param("lec", lead).param("sec", body.person(), Types.OTHER).query().listOfRows();
        String summary = (body.person() == null ? "Removed the second examiner of " : "Named " + nameOf(body.person()) + " second examiner of ") + c.get("course_code");
        jdbc.sql("SELECT helpdesk.note_allocation(:t, :s, :r)").param("t", ticket, Types.OTHER).param("s", summary).param("r", reason).query().listOfRows();
        return Map.of("offering", offering, "message", summary + ".");
    }

    /* ── the history ── */

    private List<Map<String, Object>> history(String where, Map<String, Object> params, int limit) {
        var q = jdbc.sql("""
                SELECT ev.id, ev.offering_id, ev.course_code, ev.session, ev.semester, ev.action, ev.role, ev.reason, ev.source, ev.actor_office, ev.at,
                       concat_ws(', ', nullif(btrim(lp.surname), ''), nullif(btrim(lp.given_names), '')) AS lecturer, lp.staff_number AS lecturer_staff_number,
                       concat_ws(', ', nullif(btrim(pp.surname), ''), nullif(btrim(pp.given_names), '')) AS previous_lecturer,
                       concat_ws(', ', nullif(btrim(ap.surname), ''), nullif(btrim(ap.given_names), '')) AS performed_by,
                       tk.number AS ticket, c.dept_code, d.name AS department
                  FROM catalogue.allocation_event ev
                  JOIN catalogue.course c ON c.code = ev.course_code
                  LEFT JOIN ref.department d ON d.code = c.dept_code
                  LEFT JOIN iam.person lp ON lp.id = ev.lecturer_id
                  LEFT JOIN iam.person pp ON pp.id = ev.previous_lecturer_id
                  LEFT JOIN iam.person ap ON ap.id = ev.actor_id
                  LEFT JOIN helpdesk.ticket tk ON tk.id = ev.ticket_id
                """ + where + " ORDER BY ev.at DESC, ev.id LIMIT :lim").param("lim", limit);
        for (var e : params.entrySet()) q = q.param(e.getKey(), e.getValue());
        return q.query().listOfRows();
    }

    /** the allocation history within reach: a session and semester, a department, a lecturer, a ticket's number */
    @GetMapping("/history")
    @PreAuthorize(DESK)
    @Transactional(readOnly = true)
    List<Map<String, Object>> history(@RequestParam(required = false) String session, @RequestParam(required = false) Integer semester,
                                      @RequestParam(required = false) String dept, @RequestParam(required = false) UUID lecturer,
                                      @RequestParam(required = false) String ticket, @RequestParam(defaultValue = "500") int limit) {
        AllocationReach.Reach r = reach.require(AllocationReach.VIEW);
        Map<String, Object> params = new LinkedHashMap<>();
        params.put("s", blank(session));
        params.put("sem", semester == null ? 0 : semester);
        params.put("dept", blank(dept).toUpperCase());
        params.put("lec", lecturer == null ? "" : lecturer.toString());
        params.put("tk", blank(ticket));
        params.put("reach_depts", AllocationReach.depts(r));
        params.put("reach_facs", AllocationReach.facs(r));
        String where = " WHERE " + reach.where(r, "c.dept_code", "d.faculty_code")
                + " AND (:s = '' OR ev.session = :s) AND (:sem = 0 OR ev.semester = :sem) AND (:dept = '' OR upper(c.dept_code) = :dept)"
                + " AND (:lec = '' OR ev.lecturer_id::text = :lec OR ev.previous_lecturer_id::text = :lec) AND (:tk = '' OR upper(tk.number) = upper(:tk))";
        return history(where, params, Math.max(1, Math.min(limit, 5000)));
    }

    /** what needs a look in a semester's allocations, within reach */
    @GetMapping("/conflicts")
    @PreAuthorize(DESK)
    @Transactional(readOnly = true)
    List<Map<String, Object>> conflicts(@RequestParam(required = false) String session, @RequestParam(required = false) Integer semester) {
        AllocationReach.Reach r = reach.require(AllocationReach.VIEW);
        String s = sessionOr(session);
        int sem = semesterOr(semester, s);
        return jdbc.sql("""
                SELECT k.offering_id, k.course_code, c.title, k.dept_code, d.name AS department, k.kind, k.words
                  FROM catalogue.allocation_conflicts(:s, :sem) k
                  JOIN catalogue.course c ON c.code = k.course_code
                  LEFT JOIN ref.department d ON d.code = k.dept_code
                 WHERE %s
                 ORDER BY k.course_code, k.kind
                """.formatted(reach.where(r, "k.dept_code", "d.faculty_code"))).param("s", s).param("sem", sem)
                .param("reach_depts", AllocationReach.depts(r)).param("reach_facs", AllocationReach.facs(r)).query().listOfRows();
    }
}
