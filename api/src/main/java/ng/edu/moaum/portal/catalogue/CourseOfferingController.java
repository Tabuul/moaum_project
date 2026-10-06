package ng.edu.moaum.portal.catalogue;

import java.sql.Types;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

import jakarta.validation.Valid;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.prepost.PreAuthorize;
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

import ng.edu.moaum.portal.shared.DomainRuleViolation;
import ng.edu.moaum.portal.shared.NotFound;
import ng.edu.moaum.portal.shared.OfficeScope;

/**
 * One course, offered to many programmes across departments (V332): the course's details with every department and
 * programme that offers it, the offerings managed from the course's side (a programme of the owner's department bound
 * at once, another department's proposed and decided by that department), the course edited and its code renamed
 * without becoming another course, duplicate detection before a course is created, and every course within the
 * office's scope listed with its offerings. The structure itself is V013's catalogue.course_offer; nothing is duplicated.
 */
@RestController
@RequestMapping("/api/v1/catalogue")
class CourseOfferingController {

    private static final String OWNERS = "hasAnyAuthority('OFFICE_hod','OFFICE_dean','OFFICE_academic','OFFICE_dregistrar','OFFICE_registrar','OFFICE_admin','OFFICE_super')";
    private static final String READERS = "hasAnyAuthority('OFFICE_hod','OFFICE_dean','OFFICE_academic','OFFICE_dregistrar','OFFICE_registrar','OFFICE_admin','OFFICE_super','OFFICE_lecturer','OFFICE_exams','OFFICE_facultyexams','OFFICE_facultyofficer','OFFICE_records','OFFICE_dvc','OFFICE_vc','OFFICE_ict')";
    private static final Set<String> SORTS = Set.of("code", "title", "level", "dept", "programmes", "state");

    private final JdbcClient jdbc;
    private final tools.jackson.databind.ObjectMapper json;
    private final OfficeScope scope;
    private final OfferAuthority authority;

    CourseOfferingController(JdbcClient jdbc, tools.jackson.databind.ObjectMapper json, OfficeScope scope, OfferAuthority authority) {
        this.jdbc = jdbc;
        this.json = json;
        this.scope = scope;
        this.authority = authority;
    }

    private static String blank(String s) {
        return s == null || s.isBlank() ? null : s.trim();
    }

    /** a code as the catalogue keys it: upper case, and the space between the letters and the digits where it fits the standard form */
    private static String code(String c) {
        String u = c == null ? "" : c.trim().toUpperCase();
        java.util.regex.Matcher m = java.util.regex.Pattern.compile("^([A-Z]{3})\s*([0-9]{3})$").matcher(u);
        return m.matches() ? m.group(1) + " " + m.group(2) : u;
    }

    private List<Map<String, Object>> parsed(List<Map<String, Object>> rows, String... keys) {
        for (Map<String, Object> row : rows) {
            for (String k : keys) {
                Object v = row.get(k);
                row.put(k, json.readValue(v == null ? "[]" : v.toString(), new tools.jackson.core.type.TypeReference<List<Map<String, Object>>>() { }));
            }
        }
        return rows;
    }

    /* ── the pickers: every faculty, live department and active programme ── */

    @GetMapping("/directory")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> directory() {
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("faculties", jdbc.sql("SELECT code, name FROM ref.faculty ORDER BY name").query().listOfRows());
        out.put("departments", jdbc.sql("SELECT code, name, faculty_code FROM ref.department WHERE ended_on IS NULL ORDER BY name").query().listOfRows());
        out.put("programmes", jdbc.sql("""
                SELECT p.code, p.name, p.dept_code, p.faculty_code, p.category
                  FROM ref.programme p JOIN ref.department d ON d.code = p.dept_code
                 WHERE NOT coalesce(p.archived, false) AND d.ended_on IS NULL
                 ORDER BY p.name
                """).query().listOfRows());
        out.put("tracks", jdbc.sql("SELECT code, label AS name, framework FROM policy.curriculum_track ORDER BY ord, code").query().listOfRows());
        out.put("actingDept", authority.actingDept());
        out.put("central", authority.central());
        return out;
    }

    /* ── duplicate detection before a course is created ── */

    /** the course that already carries this code (however it is spaced or punctuated), and live courses with the same title */
    @GetMapping("/courses/exists")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> exists(@RequestParam String code, @RequestParam(required = false) String title,
                               @RequestParam(required = false) Integer level, @RequestParam(required = false) Integer semester) {
        String head = """
                SELECT c.id, c.code, c.title, c.units, c.semester, c.level, c.kind, c.state, c.dept_code, d.name AS dept_name, f.name AS faculty_name,
                       (SELECT count(*) FROM catalogue.course_offer co WHERE co.course_code = c.code) AS programmes
                  FROM catalogue.course c LEFT JOIN ref.department d ON d.code = c.dept_code LEFT JOIN ref.faculty f ON f.code = d.faculty_code
                """;
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("byCode", jdbc.sql(head + " WHERE upper(regexp_replace(c.code, '[^A-Za-z0-9]', '', 'g')) = upper(regexp_replace(:c, '[^A-Za-z0-9]', '', 'g')) ORDER BY (c.state <> 'ENDED') DESC LIMIT 1")
                .param("c", code).query().listOfRows().stream().findFirst().orElse(null));
        String t = blank(title);
        out.put("byTitle", t == null ? List.of() : jdbc.sql(head + """
                 WHERE c.state <> 'ENDED'
                   AND lower(regexp_replace(btrim(c.title), '\\s+', ' ', 'g')) = lower(regexp_replace(btrim(:t), '\\s+', ' ', 'g'))
                   AND (:l::int IS NULL OR c.level = :l)
                 ORDER BY (c.semester = coalesce(:s::int, c.semester)) DESC, c.code
                 LIMIT 5
                """).param("t", t).param("l", level, Types.INTEGER).param("s", semester, Types.INTEGER).query().listOfRows());
        return out;
    }

    /* ── every course within the office's scope, with its offerings ── */

    @GetMapping("/courses/list")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> list(@RequestParam(required = false) String fac, @RequestParam(required = false) String dept,
                             @RequestParam(required = false) String prog, @RequestParam(required = false) Integer level,
                             @RequestParam(required = false) Integer semester, @RequestParam(required = false) String kind,
                             @RequestParam(required = false) String state, @RequestParam(required = false) String session,
                             @RequestParam(required = false) String q, @RequestParam(defaultValue = "code") String sort,
                             @RequestParam(defaultValue = "asc") String dir, @RequestParam(defaultValue = "1") int page,
                             @RequestParam(defaultValue = "50") int size) {
        OfficeScope.Bound b = scope.bound(fac, dept, prog);          // a department office within its department, a faculty office within its faculty
        String scopeDept = scope.actingDepartmentOffice() ? b.dept() : null;
        String scopeFac = scope.actingFacultyOffice() ? b.fac() : null;
        int sz = Math.max(1, Math.min(size, 2000));
        int pg = Math.max(1, page);
        String order = switch (SORTS.contains(sort) ? sort : "code") {
            case "title" -> "c.title";
            case "level" -> "c.level, c.semester, c.code";
            case "dept" -> "d.name, c.code";
            case "programmes" -> "programme_count";
            case "state" -> "c.state, c.code";
            default -> "c.code";
        };
        String where = """
                  FROM catalogue.course c
                  LEFT JOIN ref.department d ON d.code = c.dept_code
                  LEFT JOIN ref.faculty f ON f.code = d.faculty_code
                 WHERE (:sd::text IS NULL OR c.dept_code = :sd
                        OR EXISTS (SELECT 1 FROM catalogue.course_offer co JOIN ref.programme p ON p.code = co.programme_code WHERE co.course_code = c.code AND p.dept_code = :sd))
                   AND (:sf::text IS NULL OR d.faculty_code = :sf
                        OR EXISTS (SELECT 1 FROM catalogue.course_offer co JOIN ref.programme p ON p.code = co.programme_code WHERE co.course_code = c.code AND p.faculty_code = :sf))
                   AND (:fac::text IS NULL OR d.faculty_code = :fac
                        OR EXISTS (SELECT 1 FROM catalogue.course_offer co JOIN ref.programme p ON p.code = co.programme_code WHERE co.course_code = c.code AND p.faculty_code = :fac))
                   AND (:dept::text IS NULL OR c.dept_code = :dept
                        OR EXISTS (SELECT 1 FROM catalogue.course_offer co JOIN ref.programme p ON p.code = co.programme_code WHERE co.course_code = c.code AND p.dept_code = :dept))
                   AND (:prog::text IS NULL OR EXISTS (SELECT 1 FROM catalogue.course_offer co WHERE co.course_code = c.code AND co.programme_code = :prog))
                   AND (:level::int IS NULL OR c.level = :level)
                   AND (:sem::int IS NULL OR c.semester = :sem)
                   AND (:kind::text IS NULL OR c.kind = :kind)
                   AND (:state::text IS NULL OR c.state = :state)
                   AND (:session::text IS NULL OR EXISTS (SELECT 1 FROM catalogue.offering o WHERE o.course_code = c.code AND o.session = :session))
                   AND (:q::text IS NULL OR c.code ILIKE :q OR c.title ILIKE :q)
                   AND c.code NOT LIKE 'DMO %'
                """;
        var params = new LinkedHashMap<String, Object>();
        params.put("sd", scopeDept);
        params.put("sf", scopeFac);
        params.put("fac", blank(fac) == null ? null : fac.trim().toUpperCase());
        params.put("dept", blank(dept) == null ? null : dept.trim().toUpperCase());
        params.put("prog", blank(prog) == null ? null : prog.trim().toUpperCase());
        params.put("level", level);
        params.put("sem", semester);
        params.put("kind", blank(kind));
        params.put("state", blank(state) == null ? null : state.trim().toUpperCase());
        params.put("session", blank(session));
        params.put("q", blank(q) == null ? null : "%" + q.trim() + "%");
        var count = jdbc.sql("SELECT count(*) " + where);
        var rows = jdbc.sql("""
                SELECT c.id, c.code, c.title, c.units, c.level, c.semester, c.kind, c.state, c.ended_on, c.curriculum, c.general_office,
                       c.dept_code, d.name AS dept_name, f.name AS faculty_name,
                       c.owner_programme, (SELECT p.name FROM ref.programme p WHERE p.code = c.owner_programme) AS owner_programme_name,
                       (SELECT count(*) FROM catalogue.course_offer co WHERE co.course_code = c.code) AS programme_count,
                       coalesce((SELECT jsonb_agg(jsonb_build_object('code', co.programme_code, 'name', p.name, 'dept', p.dept_code, 'deptName', pd.name, 'faculty', pf.name,
                                                                     'level', co.level, 'basis', co.basis) ORDER BY p.name, co.level)
                                   FROM catalogue.course_offer co JOIN ref.programme p ON p.code = co.programme_code
                                   LEFT JOIN ref.department pd ON pd.code = p.dept_code LEFT JOIN ref.faculty pf ON pf.code = p.faculty_code
                                  WHERE co.course_code = c.code), '[]'::jsonb) AS programmes,
                       (SELECT max(o.session) FROM catalogue.offering o WHERE o.course_code = c.code) AS last_session,
                       (SELECT count(*) FROM catalogue.offer_proposal pr WHERE pr.course_code = c.code AND pr.state = 'PENDING') AS pending
                """ + where + " ORDER BY " + order + ("desc".equalsIgnoreCase(dir) ? " DESC" : " ASC") + ", c.code LIMIT :lim OFFSET :off");
        for (var e : params.entrySet()) {
            Object v = e.getValue();
            int type = "level".equals(e.getKey()) || "sem".equals(e.getKey()) ? Types.INTEGER : Types.VARCHAR;   // a null level is still an integer
            count = count.param(e.getKey(), v, type);
            rows = rows.param(e.getKey(), v, type);
        }
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("total", count.query(Long.class).single());
        out.put("page", pg);
        out.put("size", sz);
        out.put("rows", parsed(rows.param("lim", sz).param("off", (long) (pg - 1) * sz).query().listOfRows(), "programmes"));
        out.put("scope", Map.of("dept", scopeDept == null ? "" : scopeDept, "fac", scopeFac == null ? "" : scopeFac));
        return out;
    }

    /* ── one course, with everything that offers it ── */

    @GetMapping("/courses/{code}/detail")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> detail(@PathVariable String code) {
        String c = code(code);
        Map<String, Object> course = jdbc.sql("""
                SELECT c.id, c.code, c.title, c.units, c.semester, c.level, c.kind, c.state, c.ended_on, c.curriculum, c.ca_max, c.general_office,
                       c.lecture_hours, c.practical_hours, c.industrial_training, c.dept_code, d.name AS dept_name, d.faculty_code, f.name AS faculty_name,
                       c.owner_programme, op.name AS owner_programme_name, c.description,
                       (SELECT r.ref FROM catalogue.course_reset r WHERE r.id = c.reset_batch_id) AS reset_ref
                  FROM catalogue.course c LEFT JOIN ref.department d ON d.code = c.dept_code LEFT JOIN ref.faculty f ON f.code = d.faculty_code
                  LEFT JOIN ref.programme op ON op.code = c.owner_programme
                 WHERE c.code = :c
                """).param("c", c).query().listOfRows().stream().findFirst().orElseThrow(() -> new NotFound("course", code));
        String dept = (String) course.get("dept_code");
        List<Map<String, Object>> offers = jdbc.sql("""
                WITH cur AS (SELECT name FROM policy.academic_session WHERE state = 'CURRENT' LIMIT 1)
                SELECT co.programme_code, p.name AS programme, p.dept_code, d.name AS dept, p.faculty_code, f.name AS faculty, co.level, co.basis, co.track,
                       co.added_at, helpdesk.person_name(co.added_by) AS added_by, co.source,
                       (SELECT count(*) FROM registration.entry e JOIN registration.course_registration r ON r.id = e.registration_id
                          JOIN catalogue.offering o ON o.id = e.offering_id JOIN people.student st ON st.id = r.student_id
                         WHERE o.course_code = co.course_code AND st.programme_code = co.programme_code AND r.level = co.level
                           AND r.status IN ('APPROVED','LOCKED') AND r.session = (SELECT name FROM cur)) AS registered_now,
                       (SELECT count(*) FROM registration.entry e JOIN registration.course_registration r ON r.id = e.registration_id
                          JOIN catalogue.offering o ON o.id = e.offering_id JOIN people.student st ON st.id = r.student_id
                         WHERE o.course_code = co.course_code AND st.programme_code = co.programme_code AND r.level = co.level) AS registered_ever
                  FROM catalogue.course_offer co
                  JOIN ref.programme p ON p.code = co.programme_code
                  LEFT JOIN ref.department d ON d.code = p.dept_code
                  LEFT JOIN ref.faculty f ON f.code = p.faculty_code
                 WHERE co.course_code = :c
                 ORDER BY (p.dept_code = :d) DESC, f.name, d.name, p.name, co.level
                """).param("c", c).param("d", dept, Types.VARCHAR).query().listOfRows();
        for (Map<String, Object> o : offers) {
            o.put("may_remove", authority.mayBindInto((String) o.get("dept_code")));
        }
        List<Map<String, Object>> departments = jdbc.sql("""
                SELECT d.code, d.name, f.name AS faculty, count(DISTINCT co.programme_code) AS programmes, (d.code = :d) AS owner
                  FROM catalogue.course_offer co JOIN ref.programme p ON p.code = co.programme_code
                  JOIN ref.department d ON d.code = p.dept_code LEFT JOIN ref.faculty f ON f.code = d.faculty_code
                 WHERE co.course_code = :c
                 GROUP BY d.code, d.name, f.name ORDER BY (d.code = :d) DESC, f.name, d.name
                """).param("c", c).param("d", dept, Types.VARCHAR).query().listOfRows();
        List<Map<String, Object>> sessions = parsed(jdbc.sql("""
                SELECT o.id, o.session, o.semester, o.allocated_on,
                       CASE WHEN lp.id IS NULL THEN NULL ELSE concat_ws(', ', nullif(btrim(lp.surname), ''), nullif(btrim(lp.given_names), '')) END AS lecturer,
                       CASE WHEN sp.id IS NULL THEN NULL ELSE concat_ws(', ', nullif(btrim(sp.surname), ''), nullif(btrim(sp.given_names), '')) END AS second_examiner,
                       coalesce((SELECT jsonb_agg(jsonb_build_object('name', concat_ws(', ', nullif(btrim(tp.surname), ''), nullif(btrim(tp.given_names), '')), 'programme_code', t.programme_code, 'programme', pr.name) ORDER BY tp.surname)
                                   FROM catalogue.offering_teacher t JOIN iam.person tp ON tp.id = t.lecturer_id LEFT JOIN ref.programme pr ON pr.code = t.programme_code
                                  WHERE t.offering_id = o.id), '[]'::jsonb) AS co_lecturers,
                       (SELECT count(*) FROM registration.entry e JOIN registration.course_registration r ON r.id = e.registration_id
                         WHERE e.offering_id = o.id AND r.status IN ('APPROVED','LOCKED')) AS registered,
                       (SELECT sh.stage FROM assessment.score_sheet sh WHERE sh.offering_id = o.id LIMIT 1) AS sheet_stage
                  FROM catalogue.offering o
                  LEFT JOIN iam.person lp ON lp.id = o.lecturer_id
                  LEFT JOIN iam.person sp ON sp.id = o.second_examiner_id
                 WHERE o.course_code = :c
                 ORDER BY o.session DESC, o.semester DESC
                 LIMIT 40
                """).param("c", c).query().listOfRows(), "co_lecturers");
        List<Map<String, Object>> proposals = jdbc.sql("""
                SELECT pr.id, pr.programme_code, p.name AS programme, p.dept_code, d.name AS dept, pr.level, pr.basis, pr.track, pr.reason, pr.state,
                       helpdesk.person_name(pr.proposed_by) AS proposed_by, pr.proposed_office, pr.proposed_dept, pr.proposed_at,
                       helpdesk.person_name(pr.decided_by) AS decided_by, pr.decided_office, pr.decided_at, pr.decision_note
                  FROM catalogue.offer_proposal pr JOIN ref.programme p ON p.code = pr.programme_code LEFT JOIN ref.department d ON d.code = p.dept_code
                 WHERE pr.course_code = :c
                 ORDER BY (pr.state = 'PENDING') DESC, pr.proposed_at DESC
                 LIMIT 60
                """).param("c", c).query().listOfRows();
        String mine = authority.actingDept();
        for (Map<String, Object> p : proposals) {
            boolean pending = "PENDING".equals(p.get("state"));
            p.put("may_decide", pending && authority.mayBindInto((String) p.get("dept_code")));
            p.put("may_cancel", pending && (authority.central() || (mine != null && mine.equalsIgnoreCase(String.valueOf(p.get("proposed_dept"))))));
        }
        List<Map<String, Object>> history = jdbc.sql("""
                SELECT h.programme_code, p.name AS programme, d.name AS dept, h.level, h.basis, h.track, h.added_at, h.source, h.ended_at,
                       helpdesk.person_name(h.ended_by) AS ended_by, h.ended_office, h.reason, h.registrations_carried
                  FROM catalogue.course_offer_history h JOIN ref.programme p ON p.code = h.programme_code LEFT JOIN ref.department d ON d.code = p.dept_code
                 WHERE h.course_code = :c ORDER BY h.ended_at DESC LIMIT 60
                """).param("c", c).query().listOfRows();
        Map<String, Object> usage = jdbc.sql("SELECT * FROM catalogue.course_usage(:c)").param("c", c).query().singleRow();
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("course", course);
        out.put("offers", offers);
        out.put("departments", departments);
        out.put("sessions", sessions);
        out.put("proposals", proposals);
        out.put("history", history);
        out.put("usage", usage);
        // V338: what the course requires first, and every change of its owner
        out.put("prerequisites", jdbc.sql("""
                SELECT q.requires_code AS code, c.title FROM catalogue.course_prerequisite q JOIN catalogue.course c ON c.code = q.requires_code
                 WHERE q.course_code = :c ORDER BY q.requires_code
                """).param("c", c).query().listOfRows());
        out.put("ownerHistory", jdbc.sql("""
                SELECT h.from_dept, fd.name AS from_dept_name, h.to_dept, td.name AS to_dept_name, h.from_programme, h.to_programme,
                       tp.name AS to_programme_name, h.source, h.reason, h.changed_at, h.changed_office, helpdesk.person_name(h.changed_by) AS changed_by
                  FROM catalogue.course_owner_history h
                  LEFT JOIN ref.department fd ON fd.code = h.from_dept LEFT JOIN ref.department td ON td.code = h.to_dept
                  LEFT JOIN ref.programme tp ON tp.code = h.to_programme
                 WHERE h.course_id = (SELECT id FROM catalogue.course WHERE code = :c) ORDER BY h.changed_at DESC LIMIT 40
                """).param("c", c).query().listOfRows());
        String office = ng.edu.moaum.portal.shared.AuditContextHolder.current().map(ng.edu.moaum.portal.shared.AuditContext::actorOffice).orElse("");
        out.put("may", Map.of("edit", authority.owns(dept), "offer", authority.owns(dept), "central", authority.central(), "actingDept", mine == null ? "" : mine,
                "changeOwner", Set.of("academic", "registrar", "dregistrar", "ict", "super").contains(office)));
        return out;
    }

    /* ── offering the course from its own side: bound where the office may, proposed where it may not ── */

    public record OfferIn(@NotBlank @Size(max = 12) String programme, @NotNull @Min(100) @Max(900) Integer level,
                          @Size(max = 12) String basis, @Size(max = 12) String track, @Size(max = 2000) String reason) {
    }

    @PostMapping("/courses/{code}/offers")
    @PreAuthorize(OWNERS)
    @Transactional
    Map<String, Object> addOffer(@PathVariable String code, @Valid @RequestBody OfferIn body) {
        String c = code(code);
        String dept = authority.deptOfCourse(c);
        return authority.offer(c, dept, body.programme(), body.level(), body.basis(), body.track(), body.reason());
    }

    /** end a binding — the programme's department (or its Dean, or a central office) decides what its programme offers */
    @DeleteMapping("/courses/{code}/offers")
    @PreAuthorize(OWNERS)
    @Transactional
    Map<String, Object> removeOffer(@PathVariable String code, @RequestParam String programme, @RequestParam int level,
                                    @RequestParam(required = false) String reason) {
        String c = code(code);
        String prog = code(programme);
        String progDept = authority.deptOfProgramme(prog);
        if (!authority.mayBindInto(progDept)) {
            throw new DomainRuleViolation("CAT_OFFER_DEPT", "What " + prog + " offers is decided by its own department.",
                    new DomainRuleViolation.Remedy("Ask that department's Head to remove the course from the programme's structure.", "Head of Department"));
        }
        String outcome = jdbc.sql("SELECT catalogue.unbind_offer(:c, :p, :l, :r)").param("c", c).param("p", prog).param("l", level)
                .param("r", blank(reason), Types.VARCHAR).query(String.class).single();
        return Map.of("course", c, "programme", prog, "level", level, "outcome", outcome);
    }

    /* ── proposals: what waits for my department, and what my department proposed ── */

    @GetMapping("/offer-proposals")
    @PreAuthorize(OWNERS)
    @Transactional(readOnly = true)
    Map<String, Object> proposals(@RequestParam(required = false) String dept, @RequestParam(defaultValue = "PENDING") String state) {
        String d = scope.deptWithin(blank(dept));
        String st = blank(state) == null || "ALL".equalsIgnoreCase(state) ? null : state.trim().toUpperCase();
        String sql = """
                SELECT pr.id, pr.course_code, c.title AS course_title, c.units, c.dept_code AS course_dept, cd.name AS course_dept_name,
                       pr.programme_code, p.name AS programme, p.dept_code, d.name AS dept, pr.level, pr.basis, pr.track, pr.reason, pr.state,
                       helpdesk.person_name(pr.proposed_by) AS proposed_by, pr.proposed_office, pr.proposed_dept, pr.proposed_at,
                       helpdesk.person_name(pr.decided_by) AS decided_by, pr.decided_at, pr.decision_note
                  FROM catalogue.offer_proposal pr
                  JOIN catalogue.course c ON c.code = pr.course_code LEFT JOIN ref.department cd ON cd.code = c.dept_code
                  JOIN ref.programme p ON p.code = pr.programme_code LEFT JOIN ref.department d ON d.code = p.dept_code
                 WHERE (:st::text IS NULL OR pr.state = :st)
                """;
        List<Map<String, Object>> toDecide = jdbc.sql(sql + " AND (:d::text IS NULL OR p.dept_code = :d) ORDER BY pr.proposed_at DESC LIMIT 300")
                .param("st", st, Types.VARCHAR).param("d", d, Types.VARCHAR).query().listOfRows();
        toDecide.removeIf(p -> !authority.mayBindInto((String) p.get("dept_code")));
        List<Map<String, Object>> mine = jdbc.sql(sql + " AND (:d::text IS NULL OR pr.proposed_dept = :d OR c.dept_code = :d) ORDER BY pr.proposed_at DESC LIMIT 300")
                .param("st", st, Types.VARCHAR).param("d", d, Types.VARCHAR).query().listOfRows();
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("toDecide", toDecide);
        out.put("mine", mine);
        out.put("dept", d == null ? "" : d);
        return out;
    }

    public record Decision(@Size(max = 2000) String note) {
    }

    private Map<String, Object> proposal(UUID id) {
        return jdbc.sql("""
                SELECT pr.id, pr.course_code, pr.programme_code, p.dept_code, pr.proposed_dept, pr.state
                  FROM catalogue.offer_proposal pr JOIN ref.programme p ON p.code = pr.programme_code WHERE pr.id = :id
                """).param("id", id).query().listOfRows().stream().findFirst().orElseThrow(() -> new NotFound("proposal", id.toString()));
    }

    private void assertDecides(Map<String, Object> pr) {
        if (!authority.mayBindInto((String) pr.get("dept_code"))) {
            throw new DomainRuleViolation("CAT_PROPOSAL_DEPT", "A proposal to " + pr.get("programme_code") + " is decided by its own department, its Dean or the Academic Office.",
                    new DomainRuleViolation.Remedy("The department that owns the programme decides what it offers.", "Head of Department"));
        }
    }

    @PostMapping("/offer-proposals/{id}/approve")
    @PreAuthorize(OWNERS)
    @Transactional
    Map<String, Object> approve(@PathVariable UUID id, @RequestBody(required = false) Decision body) {
        Map<String, Object> pr = proposal(id);
        assertDecides(pr);
        String outcome = jdbc.sql("SELECT catalogue.decide_offer_proposal(:id, true, :n)").param("id", id).param("n", body == null ? null : blank(body.note()), Types.VARCHAR).query(String.class).single();
        return Map.of("id", id, "state", outcome, "course", pr.get("course_code"), "programme", pr.get("programme_code"));
    }

    @PostMapping("/offer-proposals/{id}/reject")
    @PreAuthorize(OWNERS)
    @Transactional
    Map<String, Object> reject(@PathVariable UUID id, @RequestBody(required = false) Decision body) {
        Map<String, Object> pr = proposal(id);
        assertDecides(pr);
        String outcome = jdbc.sql("SELECT catalogue.decide_offer_proposal(:id, false, :n)").param("id", id).param("n", body == null ? null : blank(body.note()), Types.VARCHAR).query(String.class).single();
        return Map.of("id", id, "state", outcome, "course", pr.get("course_code"), "programme", pr.get("programme_code"));
    }

    @PostMapping("/offer-proposals/{id}/cancel")
    @PreAuthorize(OWNERS)
    @Transactional
    Map<String, Object> cancel(@PathVariable UUID id, @RequestBody(required = false) Decision body) {
        Map<String, Object> pr = proposal(id);
        String mine = authority.actingDept();
        boolean proposer = authority.central() || (mine != null && mine.equalsIgnoreCase(String.valueOf(pr.get("proposed_dept"))))
                || authority.owns(authority.deptOfCourse((String) pr.get("course_code")));
        if (!proposer) {
            throw new DomainRuleViolation("CAT_PROPOSAL_DEPT", "A proposal is withdrawn by the department that made it.",
                    new DomainRuleViolation.Remedy("Reject it instead, if it is yours to decide.", "Head of Department"));
        }
        jdbc.sql("SELECT catalogue.cancel_offer_proposal(:id, :n)").param("id", id).param("n", body == null ? null : blank(body.note()), Types.VARCHAR).query().singleRow();
        return Map.of("id", id, "state", "CANCELLED");
    }

    /* ── codes written without the hyphen after their prefix (V333) ── */

    /** a department's codes written without the hyphen, each with the code it should read */
    @GetMapping("/code-fixes")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> codeFixes(@RequestParam(required = false) String dept) {
        return jdbc.sql("SELECT * FROM catalogue.code_fixes(:d) ORDER BY code").param("d", scope.deptWithin(blank(dept)), Types.VARCHAR).query().listOfRows();
    }

    /** rename every one whose corrected code is free; one whose corrected code is another course already is left for the duplicates desk */
    @PostMapping("/code-fixes/apply")
    @PreAuthorize(OWNERS)
    @Transactional
    Map<String, Object> applyCodeFixes(@RequestParam(required = false) String dept) {
        String d = scope.deptWithin(blank(dept));
        if (d == null) {
            throw new DomainRuleViolation("CAT_DEPT", "Codes are corrected a department at a time.",
                    new DomainRuleViolation.Remedy("Choose the department whose codes to correct.", "Head of Department"));
        }
        List<Map<String, Object>> outcomes = jdbc.sql("SELECT * FROM catalogue.apply_code_fixes(:d)").param("d", d).query().listOfRows();
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("dept", d);
        out.put("renamed", outcomes.stream().filter(o -> "RENAMED".equals(o.get("outcome"))).count());
        out.put("twins", outcomes.stream().filter(o -> "TWIN_EXISTS".equals(o.get("outcome"))).count());
        out.put("outcomes", outcomes);
        return out;
    }

    /* ── editing the course keeps it the same course ── */

    public record Edit(@NotBlank @Size(max = 120) String title, @NotNull @Min(0) @Max(12) Integer units, @NotNull @Min(1) @Max(3) Integer semester,
                       @NotNull @Min(100) @Max(900) Integer level, @Size(max = 20) String kind) {
    }

    @PutMapping("/courses/{code}")
    @PreAuthorize(OWNERS)
    @Transactional
    Map<String, Object> edit(@PathVariable String code, @Valid @RequestBody Edit body) {
        String c = code(code);
        authority.assertOwns(authority.deptOfCourse(c), c);
        jdbc.sql("SELECT catalogue.update_course(:c, :t, :u, :s, :l, :k)").param("c", c).param("t", body.title().trim()).param("u", body.units())
                .param("s", body.semester()).param("l", body.level()).param("k", blank(body.kind()), Types.VARCHAR).query().singleRow();
        Map<String, Object> out = new LinkedHashMap<>(jdbc.sql("SELECT id, code, title, units, semester, level, kind, state FROM catalogue.course WHERE code = :c").param("c", c).query().singleRow());
        out.put("usage", jdbc.sql("SELECT * FROM catalogue.course_usage(:c)").param("c", c).query().singleRow());
        return out;
    }

    public record Rename(@NotBlank @Size(max = 20) String code) {
    }

    @PostMapping("/courses/{code}/rename")
    @PreAuthorize(OWNERS)
    @Transactional
    Map<String, Object> rename(@PathVariable String code, @Valid @RequestBody Rename body) {
        String c = code(code);
        authority.assertOwns(authority.deptOfCourse(c), c);
        String n = jdbc.sql("SELECT catalogue.rename_course(:o, :n)").param("o", c).param("n", body.code().trim()).query(String.class).single();
        Map<String, Object> out = new LinkedHashMap<>(jdbc.sql("SELECT id, code, title FROM catalogue.course WHERE code = :c").param("c", n).query().singleRow());
        out.put("was", c);
        return out;
    }
}
