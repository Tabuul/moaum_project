package ng.edu.moaum.portal.results;

import java.sql.Types;
import java.util.ArrayList;
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
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;
import ng.edu.moaum.portal.shared.AuditContext;
import ng.edu.moaum.portal.shared.AuditContextHolder;
import ng.edu.moaum.portal.shared.DomainRuleViolation;
import ng.edu.moaum.portal.shared.NotFound;
import ng.edu.moaum.portal.shared.OfficeScope;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.TransactionDefinition;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionTemplate;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * V700: result monitoring for the Director of ICT (the University's master prompt of 29 October 2026). One view of the results the
 * University holds — by faculty, department, programme, level, session and semester — read from the same records as the broadsheet
 * (the courses on approved registrations, each result through assessment.course_final), never a copy: the overview and drill-down,
 * the result records with their details and history, what needs a look (assessment.result_exceptions), the uploads of marks, and the
 * corrections — every amendment, and the correction requests the Director of ICT sends the course's desk of entry, which corrects
 * the mark on the sheet or raises the amendment (V358). Nothing here writes a mark.
 */
@RestController
@RequestMapping("/api/v1/results")
class ResultMonitorController {

    /** who monitors the University's results: the Director of ICT, and the offices that keep the results' record */
    static final String MONITORS = "hasAnyAuthority('OFFICE_ict','OFFICE_super','OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar','OFFICE_records')";
    /** who asks the desk of entry for a correction: the Director of ICT (and super) — the desk itself raises the amendment */
    static final String REQUESTERS = "hasAnyAuthority('OFFICE_ict','OFFICE_super')";
    /** a sheet's correction requests are read by every office that reads the sheet (ResultsController.READERS) */
    private static final String READERS =
            "hasAnyAuthority('OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar','OFFICE_dvc','OFFICE_vc','OFFICE_records',"
            + "'OFFICE_dean','OFFICE_hod','OFFICE_exams','OFFICE_facultyexams','OFFICE_facultyofficer','OFFICE_lecturer',"
            + "'OFFICE_ict','OFFICE_admin','OFFICE_super','OFFICE_gst','OFFICE_eps')";
    /** the desk of entry declines a request (as it raises an amendment: AmendmentsController.ENTRY) */
    private static final String ENTRY = "hasAnyAuthority('OFFICE_lecturer','OFFICE_exams','OFFICE_gst','OFFICE_eps')";
    /** V702: the exceptions (the missing marks among them) and a result's details are read by the department and faculty desks too,
     *  each within its own scope, to chase and export them */
    static final String EXCEPTION_READERS = "hasAnyAuthority('OFFICE_ict','OFFICE_super','OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar',"
            + "'OFFICE_records','OFFICE_dbops','OFFICE_hod','OFFICE_dean','OFFICE_exams','OFFICE_facultyexams','OFFICE_facultyofficer')";
    /** V702: who resolves a duplicate result (the University's choice of 29 October 2026: the Registry's side, and ICT University-wide) */
    static final String RESOLVERS = "hasAnyAuthority('OFFICE_records','OFFICE_registrar','OFFICE_dregistrar','OFFICE_academic','OFFICE_ict','OFFICE_dbops','OFFICE_super')";

    static final Set<String> STATES = Set.of("AWAITING", "MISSING", "ENTRY", "VERIFICATION", "APPROVAL", "PUBLISHED");
    static final List<String> KINDS = List.of("RESULT_WITHOUT_REGISTRATION", "DUPLICATE_RESULT", "MISSING_SCORE", "INVALID_SCORE", "COURSE_ABOVE_LEVEL",
            "COURSE_OTHER_SEMESTER", "COURSE_OUTSIDE_PROGRAMME", "PASSED_STILL_CARRIED", "RESULT_HELD_NO_STUDENT");

    private final JdbcClient jdbc;
    private final OfficeScope scope;
    private final ResultsService results;
    private final TransactionTemplate own;
    private final tools.jackson.databind.ObjectMapper json;

    ResultMonitorController(JdbcClient jdbc, OfficeScope scope, ResultsService results, PlatformTransactionManager transactions,
                            tools.jackson.databind.ObjectMapper json) {
        this.jdbc = jdbc;
        this.scope = scope;
        this.results = results;
        this.own = new TransactionTemplate(transactions);
        this.own.setPropagationBehavior(TransactionDefinition.PROPAGATION_REQUIRES_NEW);
        this.json = json;
    }

    /* ── the period and the scope ── */

    private record Period(String session, int sem) {
    }

    /** the session and semester asked for, else the University's current session and its open semester */
    private Period period(String session, Integer sem) {
        if (session != null && session.matches("[0-9]{4}/[0-9]{4}") && sem != null && sem >= 1 && sem <= 3) return new Period(session, sem);
        // the University's current session as the portal reads it everywhere (never a year written into the code), and its open semester
        Map<String, Object> p = jdbc.sql("""
                SELECT c.session,
                       coalesce((SELECT m.number FROM policy.semester m WHERE m.session = c.session AND m.state = 'OPEN' ORDER BY m.number DESC LIMIT 1), 1) AS sem
                  FROM (SELECT policy.university_current_session() AS session) c WHERE c.session IS NOT NULL
                """).query().listOfRows().stream().findFirst().orElse(Map.of());
        String s = session != null && session.matches("[0-9]{4}/[0-9]{4}") ? session : (String) p.get("session");
        int m = sem != null && sem >= 1 && sem <= 3 ? sem : p.get("sem") instanceof Number n ? n.intValue() : 1;
        if (s == null) throw new DomainRuleViolation("RESULT_SESSION", "No session is current; choose one.");
        return new Period(s, m);
    }

    private static String blank(String s) {
        return s == null || s.isBlank() ? null : s.trim();
    }

    private void customPlan() {
        jdbc.sql("SELECT set_config('plan_cache_mode', 'force_custom_plan', true)").query().singleRow();
    }

    /** a read written down (reporting.query_log, as the Database Operations' reports are), in its own transaction */
    private void logRead(String source, String title, Map<String, Object> filters, Integer rows) {
        AuditContext ctx = AuditContextHolder.current().orElse(null);
        if (ctx == null || ctx.actorId() == null) return;
        String def;
        try {
            def = json.writeValueAsString(filters);
        } catch (RuntimeException e) {
            def = null;
        }
        String definition = def;
        own.executeWithoutResult(st -> jdbc.sql("""
                INSERT INTO reporting.query_log (actor_id, actor_office, action, source, title, definition, scope, row_count, format)
                VALUES (:a, :o, 'RUN', :src, :t, CAST(:def AS jsonb), :sc, :n, 'SCREEN')
                """).param("a", ctx.actorId()).param("o", ctx.actorOffice()).param("src", source).param("t", title)
                .param("def", definition, Types.VARCHAR).param("sc", filters.toString(), Types.VARCHAR).param("n", rows, Types.INTEGER).update());
    }

    /* ── the overview: by faculty, by department of a faculty, by programme and level of a department ── */

    @GetMapping("/monitor/overview")
    @PreAuthorize(MONITORS)
    @Transactional(readOnly = true)
    Map<String, Object> overview(@RequestParam(required = false) String session, @RequestParam(required = false) Integer sem,
                                 @RequestParam(required = false) String fac, @RequestParam(required = false) String dept,
                                 @RequestParam(defaultValue = "true") boolean exceptions) {
        OfficeScope.Bound b = scope.bound(blank(fac), blank(dept), null);
        Period p = period(session, sem);
        customPlan();
        String by = b.dept() != null ? "PROGRAMME" : b.fac() != null ? "DEPARTMENT" : "FACULTY";
        List<Map<String, Object>> rows = jdbc.sql("""
                SELECT g.faculty_code AS "facultyCode", f.name AS "faculty", g.dept_code AS "deptCode", d.name AS "department",
                       g.programme_code AS "programmeCode", pr.name AS "programme", g.level,
                       g.students, g.results, g.with_result AS "withResult", g.awaiting, g.at_entry AS "atEntry", g.verification, g.approval,
                       g.published, g.missing
                  FROM assessment.result_monitor_groups(:s, :m, CAST(:f AS text), CAST(:d AS text)) g
                  LEFT JOIN ref.faculty f ON f.code = g.faculty_code
                  LEFT JOIN ref.department d ON d.code = g.dept_code
                  LEFT JOIN ref.programme pr ON pr.code = g.programme_code
                 ORDER BY f.name NULLS LAST, d.name NULLS LAST, pr.name NULLS LAST, g.level NULLS LAST
                """).param("s", p.session()).param("m", p.sem()).param("f", b.fac(), Types.VARCHAR).param("d", b.dept(), Types.VARCHAR)
                .query().listOfRows();
        long exceptionTotal = 0;
        if (exceptions) {
            // the exceptions of the scope, counted to each row the way the rows are grouped
            Map<String, Long> per = new LinkedHashMap<>();
            for (Map<String, Object> e : jdbc.sql("""
                    SELECT coalesce(p.faculty_code, '') || '|' || coalesce(p.dept_code, '') || '|' || coalesce(st.programme_code, '') || '|' || coalesce(x.level::text, '') AS k,
                           count(*) AS n
                      FROM assessment.result_exceptions(:s, :m, CAST(:f AS text), CAST(:d AS text), NULL, NULL) x
                      LEFT JOIN people.student st ON st.id = x.student_id
                      LEFT JOIN ref.programme p ON p.code = st.programme_code
                     GROUP BY 1
                    """).param("s", p.session()).param("m", p.sem()).param("f", b.fac(), Types.VARCHAR).param("d", b.dept(), Types.VARCHAR)
                    .query().listOfRows()) {
                String[] k = String.valueOf(e.get("k")).split("\\|", -1);
                long n = ((Number) e.get("n")).longValue();
                exceptionTotal += n;
                String key = switch (by) {
                    case "FACULTY" -> k[0];
                    case "DEPARTMENT" -> k[0] + "|" + k[1];
                    default -> k[0] + "|" + k[1] + "|" + k[2] + "|" + k[3];
                };
                per.merge(key, n, Long::sum);
            }
            for (Map<String, Object> r : rows) {
                String key = switch (by) {
                    case "FACULTY" -> String.valueOf(r.get("facultyCode"));
                    case "DEPARTMENT" -> r.get("facultyCode") + "|" + r.get("deptCode");
                    default -> r.get("facultyCode") + "|" + r.get("deptCode") + "|" + r.get("programmeCode") + "|" + r.get("level");
                };
                r.put("exceptions", per.getOrDefault(key, 0L));
            }
        }
        Map<String, Object> totals = new LinkedHashMap<>();
        for (String k : List.of("results", "withResult", "awaiting", "atEntry", "verification", "approval", "published", "missing")) {
            totals.put(k, rows.stream().mapToLong(r -> ((Number) r.get(k)).longValue()).sum());
        }
        // students counted once across the rows (a student is in one programme, so the rows' students do not overlap)
        totals.put("students", rows.stream().mapToLong(r -> ((Number) r.get("students")).longValue()).sum());
        totals.put("exceptions", exceptions ? exceptionTotal : null);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("session", p.session());
        out.put("semester", p.sem());
        out.put("by", by);
        out.put("fac", b.fac());
        out.put("dept", b.dept());
        out.put("rows", rows);
        out.put("totals", totals);
        out.put("corrections", corrections(p, b.fac(), b.dept()));
        out.put("broadsheets", jdbc.sql("""
                SELECT count(*) FROM (SELECT DISTINCT r.programme_code, r.level FROM assessment.result_records(:s, :m, CAST(:f AS text), CAST(:d AS text), NULL, NULL, NULL) r
                                       WHERE r.stage = 'PUBLISHED' AND r.has_score) x
                """).param("s", p.session()).param("m", p.sem()).param("f", b.fac(), Types.VARCHAR).param("d", b.dept(), Types.VARCHAR).query(Long.class).single());
        return out;
    }

    /** the corrections of the period in scope: amendments open and applied, requests open and resolved */
    private Map<String, Object> corrections(Period p, String fac, String dept) {
        return jdbc.sql("""
                WITH m AS (SELECT a.stage FROM assessment.amendment a JOIN assessment.score_sheet sh ON sh.id = a.sheet_id JOIN catalogue.offering o ON o.id = sh.offering_id
                            LEFT JOIN people.student st ON st.id = a.student_id LEFT JOIN ref.programme pr ON pr.code = coalesce(st.programme_code, a.programme_code)
                            WHERE o.session = :s AND o.semester = :m AND (CAST(:f AS text) IS NULL OR pr.faculty_code = :f) AND (CAST(:d AS text) IS NULL OR pr.dept_code = :d)),
                     q AS (SELECT q.state FROM assessment.correction_request q JOIN assessment.score_sheet sh ON sh.id = q.sheet_id JOIN catalogue.offering o ON o.id = sh.offering_id
                            JOIN people.student st ON st.id = q.student_id JOIN ref.programme pr ON pr.code = st.programme_code
                            WHERE o.session = :s AND o.semester = :m AND (CAST(:f AS text) IS NULL OR pr.faculty_code = :f) AND (CAST(:d AS text) IS NULL OR pr.dept_code = :d))
                SELECT (SELECT count(*) FROM m WHERE stage NOT IN ('APPLIED', 'REFUSED', 'WITHDRAWN')) AS "amendmentsOpen",
                       (SELECT count(*) FROM m WHERE stage = 'APPLIED') AS "amendmentsApplied",
                       (SELECT count(*) FROM q WHERE state IN ('OPEN', 'IN_AMENDMENT')) AS "requestsOpen",
                       (SELECT count(*) FROM q WHERE state = 'RESOLVED') AS "requestsResolved"
                """).param("s", p.session()).param("m", p.sem()).param("f", fac, Types.VARCHAR).param("d", dept, Types.VARCHAR).query().singleRow();
    }

    /* ── the result records ── */

    private static final String BASE = """
            SELECT r.*, assessment.result_state(r.stage, r.has_score) AS state,
                   CASE WHEN lp.id IS NULL THEN NULL ELSE lp.surname || ', ' || lp.given_names END AS lecturer
              FROM assessment.result_records(:s, :m, CAST(:f AS text), CAST(:d AS text), CAST(:p AS text), CAST(:l AS int), CAST(:c AS text)) r
              LEFT JOIN iam.person lp ON lp.id = r.lecturer_id
             WHERE (CAST(:q AS text) IS NULL OR r.surname ILIKE :q OR r.other_names ILIKE :q OR (r.surname || ' ' || r.other_names) ILIKE :q
                    OR r.number ILIKE :q OR r.jamb_reg_no ILIKE :q OR r.course_code ILIKE :q OR r.course_title ILIKE :q
                    OR (lp.surname || ' ' || lp.given_names) ILIKE :q)
            """;

    private JdbcClient.StatementSpec base(String tail, Period p, OfficeScope.Bound b, Integer level, String course, String q) {
        return jdbc.sql("WITH base AS (" + BASE + ") " + tail)
                .param("s", p.session()).param("m", p.sem()).param("f", b.fac(), Types.VARCHAR).param("d", b.dept(), Types.VARCHAR)
                .param("p", b.prog(), Types.VARCHAR).param("l", level, Types.INTEGER).param("c", course, Types.VARCHAR)
                .param("q", q == null ? null : "%" + q + "%", Types.VARCHAR);
    }

    @GetMapping("/monitor/records")
    @PreAuthorize(MONITORS)
    @Transactional(readOnly = true)
    Map<String, Object> records(@RequestParam(required = false) String session, @RequestParam(required = false) Integer sem,
                                @RequestParam(required = false) String fac, @RequestParam(required = false) String dept,
                                @RequestParam(required = false) String prog, @RequestParam(required = false) Integer level,
                                @RequestParam(required = false) String course, @RequestParam(required = false) String state,
                                @RequestParam(required = false) String q, @RequestParam(defaultValue = "1") int page,
                                @RequestParam(defaultValue = "50") int size) {
        OfficeScope.Bound b = scope.bound(blank(fac), blank(dept), blank(prog));
        Period p = period(session, sem);
        String st = blank(state) == null ? null : state.trim().toUpperCase();
        if (st != null && !STATES.contains(st)) {
            throw new DomainRuleViolation("RESULT_STATE", "A result is AWAITING, MISSING, ENTRY, VERIFICATION, APPROVAL or PUBLISHED.");
        }
        Integer lv = level != null && level >= 100 && level <= 900 ? level : null;
        String c = blank(course);
        String search = blank(q);
        int sz = Math.max(1, Math.min(size, 5000));
        int pg = Math.max(1, page);
        customPlan();
        Map<String, Object> summary = new LinkedHashMap<>(base("""
                SELECT count(DISTINCT student_id) AS students, count(*) AS results, count(*) FILTER (WHERE has_score) AS "withResult",
                       count(*) FILTER (WHERE state = 'AWAITING') AS awaiting, count(*) FILTER (WHERE state = 'ENTRY') AS "atEntry",
                       count(*) FILTER (WHERE state = 'VERIFICATION') AS verification, count(*) FILTER (WHERE state = 'APPROVAL') AS approval,
                       count(*) FILTER (WHERE state = 'PUBLISHED') AS published, count(*) FILTER (WHERE state = 'MISSING') AS missing
                  FROM base
                """, p, b, lv, c, search).query().singleRow());
        long total = st == null ? ((Number) summary.get("results")).longValue()
                : base("SELECT count(*) FROM base WHERE state = :st", p, b, lv, c, search).param("st", st).query(Long.class).single();
        List<Map<String, Object>> rows = base("""
                SELECT b.student_id AS "studentId", b.offering_id AS "offeringId", b.number, b.jamb_reg_no AS jamb, b.surname, b.other_names AS "otherNames",
                       b.programme_code AS "programmeCode", pr.name AS programme, d.name AS department, f.name AS faculty, b.level,
                       b.course_code AS "courseCode", b.course_title AS "courseTitle", b.units, b.entry_type AS "entryType", b.state, b.lecturer,
                       cf.sheet_id AS "sheetId", coalesce(cf.stage, b.stage) AS stage, cf.ca, cf.exam, cf.total, cf.grade, cf.points,
                       CASE WHEN cf.points IS NULL THEN NULL ELSE round(cf.points * b.units, 2) END AS "qualityPoints", cf.outcome, cf.sitting,
                       cf.published_at AS "publishedAt", v.versions, v.first_at AS "uploadedAt", v.last_at AS "lastModified", v.imported,
                       (SELECT q.ref || ' ' || q.state FROM assessment.correction_request q WHERE q.sheet_id = cf.sheet_id AND q.student_id = b.student_id
                          AND q.state IN ('OPEN', 'IN_AMENDMENT') LIMIT 1) AS "openRequest",
                       (SELECT a.ref || ' ' || a.stage FROM assessment.amendment a WHERE a.sheet_id = cf.sheet_id AND a.student_id = b.student_id
                          AND a.stage NOT IN ('APPLIED', 'REFUSED', 'WITHDRAWN') LIMIT 1) AS "openAmendment"
                  FROM (SELECT * FROM base WHERE CAST(:st AS text) IS NULL OR state = :st
                         ORDER BY surname, other_names, number, course_code LIMIT :n OFFSET :o) b
                  LEFT JOIN ref.programme pr ON pr.code = b.programme_code
                  LEFT JOIN ref.department d ON d.code = b.dept_code
                  LEFT JOIN ref.faculty f ON f.code = b.faculty_code
                  LEFT JOIN LATERAL assessment.course_final(b.student_id, b.offering_id) cf ON true
                  LEFT JOIN LATERAL (SELECT count(*) AS versions, min(sc.entered_at) AS first_at, max(sc.entered_at) AS last_at, bool_or(sc.imported) AS imported
                                       FROM assessment.score sc WHERE sc.sheet_id = cf.sheet_id AND sc.student_id = b.student_id) v ON true
                 ORDER BY b.surname, b.other_names, b.number, b.course_code
                """, p, b, lv, c, search).param("st", st, Types.VARCHAR).param("n", sz).param("o", (pg - 1) * sz).query().listOfRows();
        if (pg == 1) {
            summary.put("exceptions", jdbc.sql("""
                    SELECT count(*) FROM assessment.result_exceptions(:s, :m, CAST(:f AS text), CAST(:d AS text), CAST(:p AS text), CAST(:l AS int))
                    """).param("s", p.session()).param("m", p.sem()).param("f", b.fac(), Types.VARCHAR).param("d", b.dept(), Types.VARCHAR)
                    .param("p", b.prog(), Types.VARCHAR).param("l", lv, Types.INTEGER).query(Long.class).single());
            Map<String, Object> filters = new LinkedHashMap<>();
            filters.put("session", p.session());
            filters.put("semester", p.sem());
            if (b.fac() != null) filters.put("faculty", b.fac());
            if (b.dept() != null) filters.put("department", b.dept());
            if (b.prog() != null) filters.put("programme", b.prog());
            if (lv != null) filters.put("level", lv);
            if (c != null) filters.put("course", c);
            if (st != null) filters.put("state", st);
            if (search != null) filters.put("search", search);
            logRead("RESULT_VIEWER", "Result viewer", filters, (int) total);
        }
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("session", p.session());
        out.put("semester", p.sem());
        out.put("summary", summary);
        out.put("total", total);
        out.put("page", pg);
        out.put("size", sz);
        out.put("rows", rows);
        return out;
    }

    /** one student's result in one course: the student, the course, the result, the sittings, every version of the mark, the sheet's
     *  chain, the amendments and the correction requests */
    @GetMapping("/monitor/records/{offering}/{student}")
    @PreAuthorize(EXCEPTION_READERS)
    @Transactional(readOnly = true)
    Map<String, Object> record(@PathVariable UUID offering, @PathVariable UUID student) {
        Map<String, Object> st = jdbc.sql("""
                SELECT s.id, coalesce(s.matric_no, s.admission_no) AS number, s.jamb_reg_no AS jamb, s.surname, s.other_names AS "otherNames",
                       s.status, s.current_level AS "currentLevel", s.programme_code AS "programmeCode", pr.name AS programme,
                       pr.dept_code AS "deptCode", d.name AS department, pr.faculty_code AS "facultyCode", f.name AS faculty
                  FROM people.student s LEFT JOIN ref.programme pr ON pr.code = s.programme_code
                  LEFT JOIN ref.department d ON d.code = pr.dept_code LEFT JOIN ref.faculty f ON f.code = pr.faculty_code
                 WHERE s.id = :id
                """).param("id", student).query().listOfRows().stream().findFirst().orElseThrow(() -> new NotFound("student", student));
        scope.bound((String) st.get("facultyCode"), (String) st.get("deptCode"), (String) st.get("programmeCode"));
        Map<String, Object> course = jdbc.sql("""
                SELECT o.id, o.course_code AS "courseCode", coalesce(o.title, c.title) AS title, c.units AS "courseUnits", coalesce(c.kind, 'Core') AS kind,
                       coalesce(c.ca_max, 40) AS "caMax",
                       c.level AS "courseLevel", c.dept_code AS "deptCode", d.name AS department, o.session, o.semester, o.stream,
                       CASE WHEN lp.id IS NULL THEN NULL ELSE lp.surname || ', ' || lp.given_names END AS lecturer
                  FROM catalogue.offering o JOIN catalogue.course c ON c.code = o.course_code
                  LEFT JOIN ref.department d ON d.code = c.dept_code LEFT JOIN iam.person lp ON lp.id = o.lecturer_id
                 WHERE o.id = :id
                """).param("id", offering).query().listOfRows().stream().findFirst().orElseThrow(() -> new NotFound("class", offering));
        Map<String, Object> registration = jdbc.sql("""
                SELECT r.level, r.status, r.approved_at AS "approvedAt", e.units, e.entry_type AS "entryType", e.status AS "entryStatus", e.basis
                  FROM registration.course_registration r JOIN registration.entry e ON e.registration_id = r.id
                 WHERE r.student_id = :st AND e.offering_id = :o
                 ORDER BY (e.status = 'APPROVED') DESC LIMIT 1
                """).param("st", student).param("o", offering).query().listOfRows().stream().findFirst().orElse(null);
        Map<String, Object> result = jdbc.sql("SELECT * FROM assessment.course_final(:st, :o)").param("st", student).param("o", offering)
                .query().listOfRows().stream().findFirst().orElse(null);
        List<Map<String, Object>> sittings = jdbc.sql("""
                SELECT sh.id AS "sheetId", coalesce(es.kind, 'MAIN') AS sitting, sh.stage, sh.submitted_at AS "submittedAt", sh.published_at AS "publishedAt",
                       sh.senate_minute AS "senateMinute", l.ca, l.exam, l.total, l.grade, l.points, l.outcome, l.version
                  FROM assessment.score_sheet sh LEFT JOIN assessment.exam_session es ON es.id = sh.exam_session_id
                  LEFT JOIN LATERAL assessment.latest_scores(sh.id) l ON l.student_id = :st
                 WHERE sh.offering_id = :o ORDER BY (coalesce(es.kind, 'MAIN') = 'MAIN') DESC, sh.id
                """).param("st", student).param("o", offering).query().listOfRows();
        List<Map<String, Object>> versions = jdbc.sql("""
                SELECT sc.sheet_id AS "sheetId", coalesce(es.kind, 'MAIN') AS sitting, sc.version, sc.ca, sc.exam, sc.total, sc.outcome, sc.reason, sc.imported,
                       sc.entered_at AS "enteredAt", sc.entered_office AS "enteredOffice", sc.on_behalf AS "onBehalf", sc.on_behalf_reason AS "onBehalfReason",
                       CASE WHEN p.id IS NULL THEN NULL ELSE p.surname || ', ' || p.given_names END AS "enteredBy"
                  FROM assessment.score sc JOIN assessment.score_sheet sh ON sh.id = sc.sheet_id
                  LEFT JOIN assessment.exam_session es ON es.id = sh.exam_session_id LEFT JOIN iam.person p ON p.id = sc.entered_by
                 WHERE sh.offering_id = :o AND sc.student_id = :st ORDER BY sc.sheet_id, sc.version
                """).param("st", student).param("o", offering).query().listOfRows();
        List<Map<String, Object>> chain = jdbc.sql("""
                SELECT d.sheet_id AS "sheetId", d.from_stage AS "from", d.to_stage AS "to", d.kind, d.actor_office AS office, d.comment, d.decided_at AS at,
                       CASE WHEN p.id IS NULL THEN NULL ELSE p.surname || ', ' || p.given_names END AS actor
                  FROM assessment.decision d JOIN assessment.score_sheet sh ON sh.id = d.sheet_id LEFT JOIN iam.person p ON p.id = d.actor_id
                 WHERE sh.offering_id = :o ORDER BY d.decided_at
                """).param("o", offering).query().listOfRows();
        List<Map<String, Object>> amendments = jdbc.sql("""
                SELECT a.id, a.ref, a.kind, a.stage, a.was_ca AS "wasCa", a.was_exam AS "wasExam", a.was_outcome AS "wasOutcome", a.ca, a.exam, a.outcome,
                       a.reason, a.raised_office AS "raisedOffice", a.raised_at AS "raisedAt", a.applied_at AS "appliedAt", a.closed_reason AS "closedReason",
                       CASE WHEN p.id IS NULL THEN NULL ELSE p.surname || ', ' || p.given_names END AS "raisedBy"
                  FROM assessment.amendment a JOIN assessment.score_sheet sh ON sh.id = a.sheet_id LEFT JOIN iam.person p ON p.id = a.raised_by
                 WHERE sh.offering_id = :o AND a.student_id = :st ORDER BY a.raised_at
                """).param("st", student).param("o", offering).query().listOfRows();
        List<Map<String, Object>> requests = requestRows("sh.offering_id = :o AND q.student_id = :st", Map.of("o", offering, "st", student));
        Map<String, Object> filters = new LinkedHashMap<>();
        filters.put("student", st.get("number"));
        filters.put("course", course.get("courseCode"));
        filters.put("session", course.get("session"));
        filters.put("semester", course.get("semester"));
        logRead("RESULT_DETAIL", "Result of " + st.get("number") + " in " + course.get("courseCode"), filters, 1);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("student", st);
        out.put("course", course);
        out.put("registration", registration);
        out.put("result", result);
        out.put("sittings", sittings);
        out.put("versions", versions);
        out.put("chain", chain);
        out.put("amendments", amendments);
        out.put("requests", requests);
        out.put("mayRequest", List.of("ict", "super").contains(AuditContextHolder.current().map(AuditContext::actorOffice).orElse("")));
        return out;
    }

    /* ── what needs a look ── */

    @GetMapping("/monitor/exceptions")
    @PreAuthorize(EXCEPTION_READERS)
    @Transactional(readOnly = true)
    Map<String, Object> exceptions(@RequestParam(required = false) String session, @RequestParam(required = false) Integer sem,
                                   @RequestParam(required = false) String fac, @RequestParam(required = false) String dept,
                                   @RequestParam(required = false) String prog, @RequestParam(required = false) Integer level,
                                   @RequestParam(required = false) String kind, @RequestParam(required = false) String q,
                                   @RequestParam(defaultValue = "1") int page, @RequestParam(defaultValue = "50") int size) {
        OfficeScope.Bound b = scope.bound(blank(fac), blank(dept), blank(prog));
        Period p = period(session, sem);
        String k = blank(kind) == null ? null : kind.trim().toUpperCase();
        if (k != null && !KINDS.contains(k)) throw new DomainRuleViolation("RESULT_EXCEPTION_KIND", "No such exception: " + kind);
        Integer lv = level != null && level >= 100 && level <= 900 ? level : null;
        String search = blank(q) == null ? null : "%" + q.trim() + "%";
        int sz = Math.max(1, Math.min(size, 5000));
        int pg = Math.max(1, page);
        customPlan();
        // read once, then counted and paged here: the function is a set the planner cannot see into
        List<Map<String, Object>> all = jdbc.sql("""
                SELECT x.kind, x.student_id AS "studentId", x.offering_id AS "offeringId", x.sheet_id AS "sheetId", x.course_code AS "courseCode",
                       coalesce(o.title, c.title) AS "courseTitle", x.level, x.detail, coalesce(st.matric_no, st.admission_no) AS number, st.surname,
                       st.other_names AS "otherNames", st.programme_code AS "programmeCode", pr.name AS programme, sh.stage
                  FROM assessment.result_exceptions(:s, :m, CAST(:f AS text), CAST(:d AS text), CAST(:p AS text), CAST(:l AS int)) x
                  LEFT JOIN people.student st ON st.id = x.student_id
                  LEFT JOIN ref.programme pr ON pr.code = st.programme_code
                  LEFT JOIN catalogue.offering o ON o.id = x.offering_id
                  LEFT JOIN catalogue.course c ON c.code = x.course_code
                  LEFT JOIN assessment.score_sheet sh ON sh.id = x.sheet_id
                 WHERE CAST(:q AS text) IS NULL OR st.surname ILIKE :q OR st.other_names ILIKE :q OR st.matric_no ILIKE :q OR x.course_code ILIKE :q OR x.detail ILIKE :q
                 ORDER BY x.kind, st.surname NULLS LAST, st.other_names, x.course_code
                """).param("s", p.session()).param("m", p.sem()).param("f", b.fac(), Types.VARCHAR).param("d", b.dept(), Types.VARCHAR)
                .param("p", b.prog(), Types.VARCHAR).param("l", lv, Types.INTEGER).param("q", search, Types.VARCHAR).query().listOfRows();
        Map<String, Long> counts = new LinkedHashMap<>();
        KINDS.forEach(x -> counts.put(x, 0L));
        all.forEach(r -> counts.merge(String.valueOf(r.get("kind")), 1L, Long::sum));
        List<Map<String, Object>> chosen = k == null ? all : all.stream().filter(r -> k.equals(r.get("kind"))).toList();
        List<Map<String, Object>> rows = chosen.stream().skip((long) (pg - 1) * sz).limit(sz).toList();
        if (pg == 1) {
            Map<String, Object> filters = new LinkedHashMap<>();
            filters.put("session", p.session());
            filters.put("semester", p.sem());
            if (b.fac() != null) filters.put("faculty", b.fac());
            if (b.dept() != null) filters.put("department", b.dept());
            if (b.prog() != null) filters.put("programme", b.prog());
            if (lv != null) filters.put("level", lv);
            if (k != null) filters.put("kind", k);
            logRead("RESULT_EXCEPTIONS", "Result exceptions", filters, chosen.size());
        }
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("session", p.session());
        out.put("semester", p.sem());
        out.put("counts", counts);
        out.put("total", chosen.size());
        out.put("page", pg);
        out.put("size", sz);
        out.put("rows", rows);
        return out;
    }

    /* ── the uploads of marks ── */

    @GetMapping("/monitor/uploads")
    @PreAuthorize(MONITORS)
    @Transactional(readOnly = true)
    Map<String, Object> uploads(@RequestParam(required = false) String session, @RequestParam(required = false) Integer sem,
                                @RequestParam(required = false) String kind, @RequestParam(defaultValue = "1") int page,
                                @RequestParam(defaultValue = "50") int size) {
        String s = blank(session) != null && session.trim().matches("[0-9]{4}/[0-9]{4}") ? session.trim() : null;
        Integer m = sem != null && sem >= 1 && sem <= 3 ? sem : null;
        String k = blank(kind) == null ? null : kind.trim().toUpperCase();
        int sz = Math.max(1, Math.min(size, 5000));
        int pg = Math.max(1, page);
        customPlan();
        List<Map<String, Object>> all = jdbc.sql("""
                SELECT u.kind, u.uploaded_at AS "uploadedAt", u.office, u.session, u.semester, u.course_code AS "courseCode", u.sheet_id AS "sheetId",
                       u.records, u.replaced, u.sheets, u.students, u.reason, sh.stage,
                       CASE WHEN p.id IS NULL THEN NULL ELSE p.surname || ', ' || p.given_names END AS "uploadedBy"
                  FROM assessment.result_uploads(CAST(:s AS text), CAST(:m AS int)) u
                  LEFT JOIN iam.person p ON p.id = u.uploaded_by
                  LEFT JOIN assessment.score_sheet sh ON sh.id = u.sheet_id
                 WHERE CAST(:k AS text) IS NULL OR u.kind = :k
                 ORDER BY u.uploaded_at DESC
                """).param("s", s, Types.VARCHAR).param("m", m, Types.INTEGER).param("k", k, Types.VARCHAR).query().listOfRows();
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("session", s);
        out.put("semester", m);
        out.put("total", all.size());
        out.put("records", all.stream().mapToLong(r -> r.get("records") instanceof Number n ? n.longValue() : 0).sum());
        out.put("page", pg);
        out.put("size", sz);
        out.put("rows", all.stream().skip((long) (pg - 1) * sz).limit(sz).toList());
        return out;
    }

    /* ── the corrections ── */

    private List<Map<String, Object>> requestRows(String where, Map<String, Object> params) {
        JdbcClient.StatementSpec spec = jdbc.sql("""
                SELECT q.id, q.ref, q.state, q.reason_kind AS "reasonKind", q.note, q.sheet_id AS "sheetId", q.student_id AS "studentId", sh.offering_id AS "offeringId",
                       o.course_code AS "courseCode", o.session, o.semester, sh.stage, coalesce(st.matric_no, st.admission_no) AS number, st.surname,
                       st.other_names AS "otherNames", st.programme_code AS "programmeCode",
                       q.was_version AS "wasVersion", q.was_ca AS "wasCa", q.was_exam AS "wasExam", q.was_total AS "wasTotal", q.was_grade AS "wasGrade",
                       q.was_outcome AS "wasOutcome", q.was_stage AS "wasStage", q.ca, q.exam, q.outcome,
                       q.requested_office AS "requestedOffice", q.requested_at AS "requestedAt",
                       CASE WHEN rp.id IS NULL THEN NULL ELSE rp.surname || ', ' || rp.given_names END AS "requestedBy",
                       a.ref AS "amendmentRef", a.stage AS "amendmentStage", q.resolved_version AS "resolvedVersion",
                       q.closed_at AS "closedAt", q.closed_office AS "closedOffice", q.closed_note AS "closedNote",
                       CASE WHEN cp.id IS NULL THEN NULL ELSE cp.surname || ', ' || cp.given_names END AS "closedBy"
                  FROM assessment.correction_request q
                  JOIN assessment.score_sheet sh ON sh.id = q.sheet_id
                  JOIN catalogue.offering o ON o.id = sh.offering_id
                  JOIN people.student st ON st.id = q.student_id
                  LEFT JOIN assessment.amendment a ON a.id = q.amendment_id
                  LEFT JOIN iam.person rp ON rp.id = q.requested_by
                  LEFT JOIN iam.person cp ON cp.id = q.closed_by
                 WHERE""" + " " + where + " ORDER BY (q.state IN ('OPEN', 'IN_AMENDMENT')) DESC, q.requested_at DESC");
        for (Map.Entry<String, Object> e : params.entrySet()) spec = spec.param(e.getKey(), e.getValue());
        return spec.query().listOfRows();
    }

    @GetMapping("/monitor/corrections")
    @PreAuthorize(MONITORS)
    @Transactional(readOnly = true)
    Map<String, Object> correctionList(@RequestParam(required = false) String session, @RequestParam(required = false) Integer sem,
                                       @RequestParam(required = false) String fac, @RequestParam(required = false) String dept,
                                       @RequestParam(required = false, defaultValue = "OPEN") String state,
                                       @RequestParam(defaultValue = "1") int page, @RequestParam(defaultValue = "50") int size) {
        OfficeScope.Bound b = scope.bound(blank(fac), blank(dept), null);
        String s = blank(session) != null && session.trim().matches("[0-9]{4}/[0-9]{4}") ? session.trim() : null;
        Integer m = sem != null && sem >= 1 && sem <= 3 ? sem : null;
        String which = state == null ? "OPEN" : state.trim().toUpperCase();
        if (!List.of("OPEN", "CLOSED", "ALL").contains(which)) {
            throw new DomainRuleViolation("RESULT_CORRECTION_STATE", "Corrections are listed OPEN, CLOSED or ALL.");
        }
        int sz = Math.max(1, Math.min(size, 5000));
        int pg = Math.max(1, page);
        Map<String, Object> params = new LinkedHashMap<>();
        StringBuilder where = new StringBuilder("true");
        if (s != null) { where.append(" AND o.session = :s"); params.put("s", s); }
        if (m != null) { where.append(" AND o.semester = :m"); params.put("m", m); }
        if (b.fac() != null) { where.append(" AND EXISTS (SELECT 1 FROM ref.programme x WHERE x.code = st.programme_code AND x.faculty_code = :f)"); params.put("f", b.fac()); }
        if (b.dept() != null) { where.append(" AND EXISTS (SELECT 1 FROM ref.programme x WHERE x.code = st.programme_code AND x.dept_code = :d)"); params.put("d", b.dept()); }
        String reqWhere = where + switch (which) {
            case "OPEN" -> " AND q.state IN ('OPEN', 'IN_AMENDMENT')";
            case "CLOSED" -> " AND q.state NOT IN ('OPEN', 'IN_AMENDMENT')";
            default -> "";
        };
        List<Map<String, Object>> requests = requestRows(reqWhere, params);
        String amendWhere = where + switch (which) {
            case "OPEN" -> " AND a.stage NOT IN ('APPLIED', 'REFUSED', 'WITHDRAWN')";
            case "CLOSED" -> " AND a.stage IN ('APPLIED', 'REFUSED', 'WITHDRAWN')";
            default -> "";
        };
        JdbcClient.StatementSpec spec = jdbc.sql("""
                SELECT a.id, a.ref, a.kind, a.stage, a.sheet_id AS "sheetId", a.student_id AS "studentId", sh.offering_id AS "offeringId",
                       o.course_code AS "courseCode", o.session, o.semester, coalesce(st.matric_no, st.admission_no) AS number, st.surname,
                       st.other_names AS "otherNames", coalesce(st.programme_code, a.programme_code) AS "programmeCode",
                       a.was_ca AS "wasCa", a.was_exam AS "wasExam", a.was_outcome AS "wasOutcome", a.ca, a.exam, a.outcome, a.was_units AS "wasUnits", a.units,
                       a.reason, a.raised_office AS "raisedOffice", a.raised_at AS "raisedAt", a.applied_at AS "appliedAt", a.applied_version AS "appliedVersion",
                       a.closed_reason AS "closedReason", a.senate_minute AS "senateMinute",
                       CASE WHEN p.id IS NULL THEN NULL ELSE p.surname || ', ' || p.given_names END AS "raisedBy",
                       count(*) OVER () AS total
                  FROM assessment.amendment a
                  JOIN assessment.score_sheet sh ON sh.id = a.sheet_id
                  JOIN catalogue.offering o ON o.id = sh.offering_id
                  LEFT JOIN people.student st ON st.id = a.student_id
                  LEFT JOIN iam.person p ON p.id = a.raised_by
                 WHERE""" + " " + amendWhere + " ORDER BY a.raised_at DESC LIMIT :n OFFSET :off");
        for (Map.Entry<String, Object> e : params.entrySet()) spec = spec.param(e.getKey(), e.getValue());
        List<Map<String, Object>> amendments = new ArrayList<>(spec.param("n", sz).param("off", (pg - 1) * sz).query().listOfRows());
        long amendTotal = amendments.isEmpty() ? 0 : ((Number) amendments.get(0).get("total")).longValue();
        amendments.forEach(r -> r.remove("total"));
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("state", which);
        out.put("requests", requests);
        out.put("amendments", amendments);
        out.put("amendmentsTotal", amendTotal);
        out.put("page", pg);
        out.put("size", sz);
        return out;
    }

    public record RequestIn(@NotNull UUID sheetId, @NotNull UUID studentId,
                            @NotBlank @Pattern(regexp = "LECTURER_UPLOAD_ERROR|DATA_ENTRY_ERROR|INCORRECT_SCORE|MISSING_SCORE|WRONG_STUDENT|WRONG_COURSE|WRONG_SESSION|WRONG_SEMESTER|WRONG_PROGRAMME|APPROVED_ACADEMIC_CORRECTION|MIGRATION_CORRECTION|OTHER") String reasonKind,
                            @NotBlank @Size(min = 10, max = 2000) String note, @Min(0) @Max(100) Integer ca, @Min(0) @Max(100) Integer exam,
                            @Pattern(regexp = "GRADED|ABSENT|WITHHELD|INCOMPLETE|MALPRACTICE|EXEMPTED") String outcome) {
    }

    public record NoteIn(@NotBlank @Size(min = 10, max = 2000) String note) {
    }

    /** the Director of ICT asks the course's desk of entry to correct a result — the result as it stands kept, nothing changed yet */
    @PostMapping("/monitor/corrections")
    @PreAuthorize(REQUESTERS)
    @Transactional
    Map<String, Object> request(@Valid @RequestBody RequestIn body) {
        Map<String, Object> st = jdbc.sql("""
                SELECT pr.faculty_code AS fac, pr.dept_code AS dept, s.programme_code AS prog
                  FROM people.student s LEFT JOIN ref.programme pr ON pr.code = s.programme_code WHERE s.id = :id
                """).param("id", body.studentId()).query().listOfRows().stream().findFirst().orElseThrow(() -> new NotFound("student", body.studentId()));
        scope.bound((String) st.get("fac"), (String) st.get("dept"), (String) st.get("prog"));
        UUID id = jdbc.sql("SELECT assessment.request_correction(:sh, :st, :k, :n, :ca, :ex, :o)")
                .param("sh", body.sheetId()).param("st", body.studentId()).param("k", body.reasonKind()).param("n", body.note().trim())
                .param("ca", body.ca(), Types.INTEGER).param("ex", body.exam(), Types.INTEGER).param("o", body.outcome(), Types.VARCHAR)
                .query(UUID.class).single();
        return requestRows("q.id = :id", Map.of("id", id)).get(0);
    }

    @PostMapping("/monitor/corrections/{id}/withdraw")
    @PreAuthorize(REQUESTERS)
    @Transactional
    Map<String, Object> withdraw(@PathVariable UUID id, @Valid @RequestBody NoteIn body) {
        jdbc.sql("SELECT assessment.withdraw_correction_request(:id, :n)").param("id", id).param("n", body.note().trim()).query().singleRow();
        return requestRows("q.id = :id", Map.of("id", id)).get(0);
    }

    /* ── V702: duplicate results, resolved by the Registry's side ── */

    /** the students in scope with marks for one course on two classes, each class with its result, the registration and the decision */
    @GetMapping("/monitor/duplicates")
    @PreAuthorize(RESOLVERS)
    @Transactional(readOnly = true)
    Map<String, Object> duplicates(@RequestParam(required = false) String session, @RequestParam(required = false) Integer sem,
                                   @RequestParam(required = false) String fac, @RequestParam(required = false) String dept,
                                   @RequestParam(required = false) String prog, @RequestParam(required = false, defaultValue = "OPEN") String state,
                                   @RequestParam(required = false) String q, @RequestParam(defaultValue = "1") int page,
                                   @RequestParam(defaultValue = "50") int size) {
        OfficeScope.Bound b = scope.bound(blank(fac), blank(dept), blank(prog));
        Period p = period(session, sem);
        String which = state == null ? "OPEN" : state.trim().toUpperCase();
        if (!List.of("OPEN", "RESOLVED", "ALL").contains(which)) {
            throw new DomainRuleViolation("RESULT_DUPLICATE_STATE", "Duplicates are listed OPEN, RESOLVED or ALL.");
        }
        String search = blank(q) == null ? null : "%" + q.trim() + "%";
        int sz = Math.max(1, Math.min(size, 5000));
        int pg = Math.max(1, page);
        customPlan();
        List<Map<String, Object>> classes = jdbc.sql("""
                SELECT x.student_id AS "studentId", x.number, x.student_name AS "studentName", x.programme_code AS "programmeCode", x.level,
                       x.base_code AS "baseCode", x.offering_id AS "offeringId", x.course_code AS "courseCode", x.course_title AS "courseTitle",
                       x.sheet_id AS "sheetId", x.stage, x.ca, x.exam, x.total, x.grade, x.entry_status AS "entryStatus", x.decision,
                       x.resolution_id AS "resolutionId", x.decided_at AS "decidedAt", x.decided_office AS "decidedOffice",
                       x.decided_reason AS "decidedReason", x.standing
                  FROM assessment.result_duplicates(:s, :m, CAST(:f AS text), CAST(:d AS text), CAST(:p AS text)) x
                 WHERE CAST(:q AS text) IS NULL OR x.number ILIKE :q OR x.student_name ILIKE :q OR x.course_code ILIKE :q
                 ORDER BY x.programme_code, x.student_name, x.base_code, x.course_code
                """).param("s", p.session()).param("m", p.sem()).param("f", b.fac(), Types.VARCHAR).param("d", b.dept(), Types.VARCHAR)
                .param("p", b.prog(), Types.VARCHAR).param("q", search, Types.VARCHAR).query().listOfRows();
        // one row a student's course, its classes under it
        Map<String, Map<String, Object>> groups = new LinkedHashMap<>();
        for (Map<String, Object> c : classes) {
            String key = c.get("studentId") + "|" + c.get("baseCode");
            Map<String, Object> g = groups.computeIfAbsent(key, x -> {
                Map<String, Object> m = new LinkedHashMap<>();
                for (String f : List.of("studentId", "number", "studentName", "programmeCode", "level", "baseCode")) m.put(f, c.get(f));
                m.put("resolved", c.get("standing") instanceof Number n && n.intValue() <= 1);
                m.put("classes", new ArrayList<Map<String, Object>>());
                return m;
            });
            @SuppressWarnings("unchecked")
            List<Map<String, Object>> list = (List<Map<String, Object>>) g.get("classes");
            Map<String, Object> one = new LinkedHashMap<>(c);
            for (String f : List.of("studentId", "number", "studentName", "programmeCode", "level", "baseCode", "standing")) one.remove(f);
            list.add(one);
        }
        long open = groups.values().stream().filter(g -> !Boolean.TRUE.equals(g.get("resolved"))).count();
        List<Map<String, Object>> chosen = groups.values().stream()
                .filter(g -> "ALL".equals(which) || ("RESOLVED".equals(which) == Boolean.TRUE.equals(g.get("resolved")))).toList();
        if (pg == 1) {
            Map<String, Object> filters = new LinkedHashMap<>();
            filters.put("session", p.session());
            filters.put("semester", p.sem());
            if (b.fac() != null) filters.put("faculty", b.fac());
            if (b.dept() != null) filters.put("department", b.dept());
            if (b.prog() != null) filters.put("programme", b.prog());
            filters.put("state", which);
            logRead("RESULT_DUPLICATES", "Duplicate results", filters, chosen.size());
        }
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("session", p.session());
        out.put("semester", p.sem());
        out.put("state", which);
        out.put("open", open);
        out.put("resolved", groups.size() - open);
        out.put("total", chosen.size());
        out.put("page", pg);
        out.put("size", sz);
        out.put("rows", chosen.stream().skip((long) (pg - 1) * sz).limit(sz).toList());
        return out;
    }

    public record ResolveIn(@NotNull UUID studentId, @NotNull UUID keep, @NotNull UUID drop, @NotBlank @Size(min = 10, max = 2000) String reason) {
    }

    private void studentInScope(UUID student) {
        Map<String, Object> st = jdbc.sql("""
                SELECT pr.faculty_code AS fac, pr.dept_code AS dept, s.programme_code AS prog
                  FROM people.student s LEFT JOIN ref.programme pr ON pr.code = s.programme_code WHERE s.id = :id
                """).param("id", student).query().listOfRows().stream().findFirst().orElseThrow(() -> new NotFound("student", student));
        scope.bound((String) st.get("fac"), (String) st.get("dept"), (String) st.get("prog"));
    }

    /** the class that stands chosen; the other withdrawn from the registration, its mark kept on its sheet, the decision written down */
    @PostMapping("/monitor/duplicates/resolve")
    @PreAuthorize(RESOLVERS)
    @Transactional
    Map<String, Object> resolveDuplicate(@Valid @RequestBody ResolveIn body) {
        studentInScope(body.studentId());
        UUID id = jdbc.sql("SELECT assessment.resolve_duplicate(:st, :k, :d, :r)").param("st", body.studentId()).param("k", body.keep())
                .param("d", body.drop()).param("r", body.reason().trim()).query(UUID.class).single();
        return Map.of("id", id);
    }

    /** a decision put back: the withdrawn class's registration as it stood */
    @PostMapping("/monitor/duplicates/{id}/undo")
    @PreAuthorize(RESOLVERS)
    @Transactional
    Map<String, Object> undoDuplicate(@PathVariable UUID id, @Valid @RequestBody NoteIn body) {
        UUID student = jdbc.sql("SELECT student_id FROM assessment.duplicate_resolution WHERE id = :id").param("id", id).query(UUID.class)
                .optional().orElseThrow(() -> new NotFound("duplicate decision", id));
        studentInScope(student);
        jdbc.sql("SELECT assessment.undo_duplicate_resolution(:id, :n)").param("id", id).param("n", body.note().trim()).query().singleRow();
        return Map.of("id", id, "undone", true);
    }

    /* ── V702: the desk of entry's open requests, wherever its sheets are ── */

    /** the open correction requests on the sheets this desk reaches — the lecturer's own courses, a desk's scope */
    @GetMapping("/correction-requests/mine")
    @PreAuthorize(ENTRY)
    @Transactional(readOnly = true)
    List<Map<String, Object>> myRequests() {
        List<Map<String, Object>> open = requestRows("q.state IN ('OPEN', 'IN_AMENDMENT')", Map.of());
        Map<Object, Boolean> reached = new LinkedHashMap<>();
        return open.stream().filter(r -> reached.computeIfAbsent(r.get("sheetId"), sh -> {
            try {
                results.reach((UUID) sh);
                return true;
            } catch (org.springframework.security.access.AccessDeniedException | NotFound e) {
                return false;
            }
        })).limit(200).toList();
    }

    /* ── V702: late results for a published sheet, from one upload ── */

    public record LateRow(@Size(max = 60) String number, @Min(0) @Max(100) Integer ca, @Min(0) @Max(100) Integer exam,
                          @Pattern(regexp = "(?i)GRADED|ABSENT|WITHHELD|INCOMPLETE|MALPRACTICE|EXEMPTED|") String outcome) {
    }

    public record LateIn(@NotBlank @Size(min = 10, max = 2000) String reason, @NotNull @Size(min = 1, max = 2000) List<@Valid LateRow> rows) {
    }

    /** each candidate on the sheet's roll with no mark raised as a late result (V422), through the chain to Senate; each row answered */
    @PostMapping("/sheets/{id}/late-results")
    @PreAuthorize(ENTRY)
    @Transactional
    Map<String, Object> lateResults(@PathVariable UUID id, @Valid @RequestBody LateIn body) {
        Sheets.Row r = results.reach(id);
        ResultsService.requireStageDesk("ENTRY", r.courseCode(), "raised");
        String rows;
        try {
            rows = json.writeValueAsString(body.rows());
        } catch (RuntimeException e) {
            throw new DomainRuleViolation("LATE_ROWS", "The rows could not be read.");
        }
        List<Map<String, Object>> out = jdbc.sql("""
                SELECT x.row_no AS "row", x.number, x.outcome, x.detail, x.ref
                  FROM assessment.raise_late_results(:sh, CAST(:rows AS jsonb), :reason) x ORDER BY x.row_no
                """).param("sh", id).param("rows", rows).param("reason", body.reason().trim()).query().listOfRows();
        Map<String, Long> counts = new LinkedHashMap<>();
        for (String k : List.of("RAISED", "NOT_LATE", "REPEATED", "REFUSED")) counts.put(k, 0L);
        out.forEach(x -> counts.merge(String.valueOf(x.get("outcome")), 1L, Long::sum));
        Map<String, Object> res = new LinkedHashMap<>();
        res.put("courseCode", r.courseCode());
        res.put("counts", counts);
        res.put("rows", out);
        return res;
    }

    /* ── the desk of entry's side: a sheet's requests, and declining one ── */

    @GetMapping("/sheets/{id}/correction-requests")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> sheetRequests(@PathVariable UUID id) {
        results.reach(id);
        return requestRows("q.sheet_id = :id", Map.of("id", id));
    }

    @PostMapping("/correction-requests/{id}/decline")
    @PreAuthorize(ENTRY)
    @Transactional
    Map<String, Object> decline(@PathVariable UUID id, @Valid @RequestBody NoteIn body) {
        UUID sheet = jdbc.sql("SELECT sheet_id FROM assessment.correction_request WHERE id = :id").param("id", id).query(UUID.class)
                .optional().orElseThrow(() -> new NotFound("correction request", id));
        Sheets.Row r = results.reach(sheet);
        ResultsService.requireStageDesk("ENTRY", r.courseCode(), "declined");
        jdbc.sql("SELECT assessment.decline_correction_request(:id, :n)").param("id", id).param("n", body.note().trim()).query().singleRow();
        return requestRows("q.id = :id", Map.of("id", id)).get(0);
    }
}
