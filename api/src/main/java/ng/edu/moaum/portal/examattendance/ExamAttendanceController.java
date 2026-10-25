package ng.edu.moaum.portal.examattendance;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

import jakarta.validation.Valid;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotEmpty;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;
import ng.edu.moaum.portal.shared.AuditContextHolder;
import ng.edu.moaum.portal.shared.DomainRuleViolation;
import ng.edu.moaum.portal.shared.NotFound;
import ng.edu.moaum.portal.shared.OfficeScope;

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
 * V652: examination attendance through the API. The offices that keep it (the database checks again, assessment.attendance_office_check):
 * the Examinations Officer, the Faculty Examinations Officer, Exams and Records, the Head of Department, the GST and EPS offices
 * (their own courses), the Academic Office, the Registrar and the Deputy Registrar. The Dean, the Faculty Officer, ICT, the Database
 * Operator, the VC and the DVC read. Every office is held to its own bound (OfficeScope): a Head of Department issues, marks and
 * reconciles the students of their department only, whatever the course.
 */
@RestController
@RequestMapping("/api/v1/exams/attendance")
class ExamAttendanceController {

    static final String KEEPERS = "hasAnyAuthority('OFFICE_exams','OFFICE_facultyexams','OFFICE_records','OFFICE_hod','OFFICE_gst','OFFICE_eps',"
            + "'OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar','OFFICE_super')";
    static final String READERS = "hasAnyAuthority('OFFICE_exams','OFFICE_facultyexams','OFFICE_records','OFFICE_hod','OFFICE_gst','OFFICE_eps',"
            + "'OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar','OFFICE_super','OFFICE_dean','OFFICE_facultyofficer','OFFICE_ict',"
            + "'OFFICE_dbops','OFFICE_vc','OFFICE_dvc','OFFICE_admin')";

    private static final Set<String> SPLITS = Set.of("NONE", "FACULTY", "DEPARTMENT", "PROGRAMME");
    private static final Set<String> MARKS = Set.of("PRESENT", "ABSENT", "LATE", "EXCUSED", "INVALID_ATTENDANCE");
    private static final int BULK_MAX = 400;

    public record SheetsIn(@NotEmpty @Size(max = 200) List<@NotNull UUID> offerings, @Min(0) @Max(60) int manualLines,
                           @Size(max = 500) String reason, String fac, String dept, String prog, String split) {
    }

    public record Mark(@NotNull UUID student, @NotNull String status, @Size(max = 300) String reason) {
    }

    public record MarksIn(@NotEmpty @Size(max = 3000) List<@Valid Mark> marks, @Size(max = 80) String sheet, @Size(max = 120) String invigilator) {
    }

    public record ManualIn(@Size(max = 40) String number, @Size(max = 160) String name, @Size(max = 160) String programme, @Size(max = 10) String level,
                           @Size(max = 300) String reason, @Size(max = 80) String sheet, @Size(max = 120) String invigilator) {
    }

    public record DecideIn(@NotNull Boolean valid, UUID student, @Size(max = 40) String number, @Size(max = 500) String note) {
    }

    private final JdbcClient jdbc;
    private final OfficeScope scope;
    private final tools.jackson.databind.ObjectMapper json;

    ExamAttendanceController(JdbcClient jdbc, OfficeScope scope, tools.jackson.databind.ObjectMapper json) {
        this.jdbc = jdbc;
        this.scope = scope;
        this.json = json;
    }

    private static String blank(String s) {
        return s == null || s.isBlank() ? null : s.trim();
    }

    private static String acting() {
        return AuditContextHolder.current().map(c -> c.actorOffice()).orElse("");
    }

    /** the scope held to the office's bound, then made whole: a programme names its department and faculty, a department its faculty */
    private OfficeScope.Bound scoped(String fac, String dept, String prog) {
        OfficeScope.Bound b = scope.bound(blank(fac), blank(dept), blank(prog));
        String p = b.prog() == null ? null : b.prog().toUpperCase();
        String d = b.dept() == null ? null : b.dept().toUpperCase();
        String f = b.fac() == null ? null : b.fac().toUpperCase();
        if ("__NONE__".equals(f) || "__NONE__".equals(d) || "__NONE__".equals(p)) return new OfficeScope.Bound("__none__", "__none__", "__none__");
        if (p != null) {
            String pd = jdbc.sql("SELECT upper(dept_code) FROM ref.programme WHERE upper(code) = :p").param("p", p).query(String.class).optional().orElse(null);
            if (pd == null) throw new DomainRuleViolation("ATTENDANCE_PROGRAMME", "No programme " + p + ".");
            d = pd;
        }
        if (d != null) {
            String df = jdbc.sql("SELECT upper(faculty_code) FROM ref.department WHERE upper(code) = :d").param("d", d).query(String.class).optional().orElse(null);
            if (df == null) throw new DomainRuleViolation("ATTENDANCE_DEPARTMENT", "No department " + d + ".");
            f = df;
        }
        return new OfficeScope.Bound(f, d, p);
    }

    /** the class, refused to the GST and EPS offices unless it is one of their own courses */
    private Map<String, Object> offering(UUID id) {
        Map<String, Object> o = jdbc.sql("""
                SELECT o.id AS offering_id, o.session, o.semester, c.code AS course_code, catalogue.shown_code(c.code) AS shown_code, c.title AS course_title,
                       c.units, c.level, c.kind, c.general_office, c.dept_code AS course_dept, d.name AS course_department, d.faculty_code AS course_faculty,
                       f.name AS course_faculty_name, tt.held_on AS exam_on, tt.starts_at, tt.ends_at, tt.venue
                  FROM catalogue.offering o
                  JOIN catalogue.course c ON c.code = o.course_code
                  LEFT JOIN ref.department d ON d.code = c.dept_code
                  LEFT JOIN ref.faculty f ON f.code = d.faculty_code
                  LEFT JOIN assessment.exam_timetable tt ON tt.offering_id = o.id
                 WHERE o.id = :id
                """).param("id", id).query().listOfRows().stream().findFirst().orElseThrow(() -> new NotFound("class", id));
        String office = acting();
        if (("gst".equals(office) || "eps".equals(office))
                && !("GST".equals(o.get("kind")) && office.toUpperCase().equals(o.get("general_office")))) {
            throw new DomainRuleViolation("ATTENDANCE_NOT_OFFICE_COURSE", "The " + office.toUpperCase() + " office keeps the attendance of its own courses.");
        }
        return o;
    }

    /** the faculty, department and programme of each student, for the scope test */
    private Map<UUID, String[]> placeOf(java.util.Collection<UUID> students) {
        Map<UUID, String[]> out = new LinkedHashMap<>();
        if (students.isEmpty()) return out;
        jdbc.sql("""
                SELECT s.id, upper(d.faculty_code) AS fac, upper(p.dept_code) AS dept, upper(p.code) AS prog
                  FROM people.student s JOIN ref.programme p ON p.code = s.programme_code JOIN ref.department d ON d.code = p.dept_code
                 WHERE s.id = ANY (CAST(:ids AS uuid[]))
                """).param("ids", students.toArray(UUID[]::new)).query().listOfRows()
                .forEach(r -> out.put((UUID) r.get("id"), new String[] {(String) r.get("fac"), (String) r.get("dept"), (String) r.get("prog")}));
        return out;
    }

    private static boolean inside(OfficeScope.Bound b, String fac, String dept, String prog) {
        if ("__none__".equals(b.fac())) return false;
        return (b.fac() == null || b.fac().equalsIgnoreCase(fac)) && (b.dept() == null || b.dept().equalsIgnoreCase(dept))
                && (b.prog() == null || b.prog().equalsIgnoreCase(prog));
    }

    private static void refuseOutside() {
        throw new DomainRuleViolation("SCOPE_STUDENT", "That student is not within your office's scope.",
                new DomainRuleViolation.Remedy("The student's own department, faculty or the central examinations office records it.", "You"));
    }

    /** a sheet is within the bound when its own scope is no wider than the office's */
    private static boolean sheetInside(OfficeScope.Bound b, Map<String, Object> s) {
        if ("__none__".equals(b.fac())) return false;
        return (b.fac() == null || b.fac().equalsIgnoreCase((String) s.get("scope_fac")))
                && (b.dept() == null || b.dept().equalsIgnoreCase((String) s.get("scope_dept")))
                && (b.prog() == null || b.prog().equalsIgnoreCase((String) s.get("scope_prog")));
    }

    private static String key(String f, String d, String p) {
        return (f == null ? "" : f) + "|" + (d == null ? "" : d) + "|" + (p == null ? "" : p);
    }

    /* ── the sheets ────────────────────────────────────────────────────────────────────────────────────────────────── */

    /** issue attendance sheets: one a course within the scope, or one a faculty, department or programme of its students (split) */
    @PostMapping("/sheets")
    @PreAuthorize(KEEPERS)
    @Transactional
    Map<String, Object> issue(@Valid @RequestBody SheetsIn body) {
        String split = blank(body.split()) == null ? "NONE" : body.split().trim().toUpperCase();
        if (!SPLITS.contains(split)) throw new DomainRuleViolation("ATTENDANCE_SPLIT", "A sheet is split by NONE, FACULTY, DEPARTMENT or PROGRAMME.");
        OfficeScope.Bound b = scoped(body.fac(), body.dept(), body.prog());
        if ("__none__".equals(b.fac())) throw new DomainRuleViolation("SCOPE_NONE", "Your office has no scope to issue sheets in.");
        // the sheets the request would print: (course, faculty, department, programme)
        List<Object[]> plan = new ArrayList<>();
        for (UUID o : new LinkedHashSet<>(body.offerings())) {
            offering(o);
            if ("NONE".equals(split)) {
                plan.add(new Object[] {o, b.fac(), b.dept(), b.prog()});
                continue;
            }
            String group = switch (split) {
                case "FACULTY" -> "upper(l.faculty_code), NULL::text, NULL::text";
                case "DEPARTMENT" -> "upper(l.faculty_code), upper(l.dept_code), NULL::text";
                default -> "upper(l.faculty_code), upper(l.dept_code), upper(l.programme_code)";
            };
            jdbc.sql("SELECT DISTINCT " + group + " FROM assessment.attendance_list(:o, :f, :d, :p) l ORDER BY 1, 2, 3")
                    .param("o", o).param("f", b.fac()).param("d", b.dept()).param("p", b.prog()).query((rs, i) -> new Object[] {o, rs.getString(1), rs.getString(2), rs.getString(3)})
                    .list().forEach(x -> {
                        // a split never widens: the office's own department or programme stays when it is narrower than the split
                        plan.add(new Object[] {x[0], x[1], b.dept() != null ? b.dept() : x[2], b.prog() != null ? b.prog() : x[3]});
                    });
        }
        if (plan.isEmpty()) throw new DomainRuleViolation("ATTENDANCE_NO_STUDENTS", "No registered students in that scope to list.");
        if (plan.size() > BULK_MAX) throw new DomainRuleViolation("ATTENDANCE_BULK_MAX", "At most " + BULK_MAX + " sheets at a time; narrow the selection.");
        // a sheet already issued for a course and scope prints a new version, and says why — refused before anything is written
        String reason = blank(body.reason());
        if (reason == null || reason.length() < 5) {
            List<String> issued = new ArrayList<>();
            for (Object[] x : plan) {
                jdbc.sql("SELECT max(reference) FROM assessment.exam_attendance_sheet WHERE offering_id = :o AND scope_key = :k AND version = (SELECT max(version) FROM assessment.exam_attendance_sheet WHERE offering_id = :o AND scope_key = :k)")
                        .param("o", x[0]).param("k", key((String) x[1], (String) x[2], (String) x[3])).query(String.class).optional().ifPresent(issued::add);
            }
            if (!issued.isEmpty()) {
                throw new DomainRuleViolation("ATTENDANCE_REISSUE_REASON", issued.size() + (issued.size() == 1 ? " sheet is" : " sheets are")
                        + " already issued (" + String.join(", ", issued.subList(0, Math.min(5, issued.size()))) + (issued.size() > 5 ? ", …" : "")
                        + "); say why a new version is printed — late registration, a correction.",
                        new DomainRuleViolation.Remedy("Give the reason; the earlier version is kept as printed.", "You"));
            }
        }
        List<Map<String, Object>> sheets = new ArrayList<>();
        for (Object[] x : plan) {
            sheets.add(jdbc.sql("""
                    SELECT s.id, s.reference, s.version, s.students, s.manual_lines, s.scope_fac, s.scope_dept, s.scope_prog, s.offering_id
                      FROM assessment.issue_attendance_sheet(:o, :n, :r, :f, :d, :p) s
                    """).param("o", x[0]).param("n", body.manualLines()).param("r", reason).param("f", x[1]).param("d", x[2]).param("p", x[3])
                    .query().singleRow());
        }
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("issued", sheets.size());
        out.put("students", sheets.stream().mapToInt(s -> ((Number) s.get("students")).intValue()).sum());
        out.put("sheets", sheets);
        return out;
    }

    /** the sheets of a course (every version) within the office's bound */
    @GetMapping("/sheets")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> sheets(@RequestParam UUID offering) {
        Map<String, Object> o = offering(offering);
        OfficeScope.Bound b = scoped(null, null, null);
        List<Map<String, Object>> rows = jdbc.sql("""
                SELECT s.id, s.reference, s.series, s.version, s.students, s.manual_lines, s.scope_fac, s.scope_dept, s.scope_prog, s.reason,
                       s.generated_office, s.generated_at, coalesce(nullif(btrim(concat_ws(' ', st.surname, st.given_names)), ''), s.generated_office) AS generated_by_name,
                       f.name AS faculty, d.name AS department, p.name AS programme
                  FROM assessment.exam_attendance_sheet s
                  LEFT JOIN iam.person st ON st.id = s.generated_by
                  LEFT JOIN ref.faculty f ON f.code = s.scope_fac
                  LEFT JOIN ref.department d ON d.code = s.scope_dept
                  LEFT JOIN ref.programme p ON p.code = s.scope_prog
                 WHERE s.offering_id = :o
                 ORDER BY s.generated_at DESC, s.version DESC
                """).param("o", offering).query().listOfRows().stream().filter(s -> sheetInside(b, s)).toList();
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("offering", o);
        out.put("sheets", rows);
        return out;
    }

    /** one sheet as printed, for its PDF: the course, the scope named, the students as listed, the manual lines */
    @GetMapping("/sheets/by-reference")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> sheet(@RequestParam String reference) {
        Map<String, Object> s = jdbc.sql("""
                SELECT s.*, f.name AS faculty, d.name AS department, p.name AS programme,
                       coalesce(nullif(btrim(concat_ws(' ', st.surname, st.given_names)), ''), s.generated_office) AS generated_by_name
                  FROM assessment.exam_attendance_sheet s
                  LEFT JOIN iam.person st ON st.id = s.generated_by
                  LEFT JOIN ref.faculty f ON f.code = s.scope_fac
                  LEFT JOIN ref.department d ON d.code = s.scope_dept
                  LEFT JOIN ref.programme p ON p.code = s.scope_prog
                 WHERE s.reference = :r
                """).param("r", reference.trim()).query().listOfRows().stream().findFirst().orElseThrow(() -> new NotFound("attendance sheet", reference));
        Map<String, Object> o = offering((UUID) s.get("offering_id"));
        if (!sheetInside(scoped(null, null, null), s)) {
            throw new DomainRuleViolation("SCOPE_SHEET", "That sheet lists students outside your office's scope.");
        }
        Map<String, Object> out = new LinkedHashMap<>(s);
        out.put("list", readJson(s.get("list")));
        out.put("offering", o);
        // the latest official version of the series: an earlier one prints as superseded
        out.put("latest_reference", jdbc.sql("SELECT reference FROM assessment.exam_attendance_sheet WHERE series = :s ORDER BY version DESC LIMIT 1")
                .param("s", s.get("series")).query(String.class).single());
        return out;
    }

    private Object readJson(Object pg) {
        if (pg == null) return List.of();
        String text = pg instanceof org.postgresql.util.PGobject g ? g.getValue() : pg.toString();
        return json.readValue(text == null ? "[]" : text, List.class);
    }

    /* ── marking the list ──────────────────────────────────────────────────────────────────────────────────────────── */

    /** a course's class within the office's bound: the students, eligibility, the attendance recorded, the sheets */
    @GetMapping("/{offering}")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> marking(@PathVariable UUID offering, @RequestParam(required = false) String fac, @RequestParam(required = false) String dept,
                                @RequestParam(required = false) String prog) {
        Map<String, Object> o = offering(offering);
        OfficeScope.Bound b = scoped(fac, dept, prog);
        List<Map<String, Object>> students = jdbc.sql("""
                SELECT l.*, a.status AS attendance, a.source, a.sheet_reference, a.invigilator, a.reason, a.recorded_at, a.verified_at
                  FROM assessment.attendance_list(:o, :f, :d, :p) l
                  LEFT JOIN assessment.exam_attendance a ON a.offering_id = :o AND a.student_id = l.student_id
                """).param("o", offering).param("f", b.fac()).param("d", b.dept()).param("p", b.prog()).query().listOfRows();
        // handwritten students recorded within the bound who are not registered for the class
        List<Map<String, Object>> manual = jdbc.sql("""
                SELECT a.student_id, s.matric_no, upper(btrim(s.surname)) || coalesce(', ' || nullif(btrim(s.other_names), ''), '') AS full_name,
                       p.name AS programme, s.current_level AS level, a.status AS attendance, a.source, a.sheet_reference, a.reason, a.recorded_at, a.verified_at,
                       upper(d.faculty_code) AS fac, upper(p.dept_code) AS dept, upper(p.code) AS prog
                  FROM assessment.exam_attendance a
                  JOIN people.student s ON s.id = a.student_id JOIN ref.programme p ON p.code = s.programme_code JOIN ref.department d ON d.code = p.dept_code
                 WHERE a.offering_id = :o AND a.source = 'MANUAL'
                   AND NOT EXISTS (SELECT 1 FROM assessment.attendance_list(:o) l WHERE l.student_id = a.student_id)
                """).param("o", offering).query().listOfRows().stream()
                .filter(r -> inside(b, (String) r.get("fac"), (String) r.get("dept"), (String) r.get("prog"))).toList();
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("offering", o);
        Map<String, Object> sc = new LinkedHashMap<>();
        sc.put("fac", b.fac());
        sc.put("dept", b.dept());
        sc.put("prog", b.prog());
        // the scope by name, as the screen says it
        sc.put("faculty", b.fac() == null ? null : jdbc.sql("SELECT name FROM ref.faculty WHERE upper(code) = :c").param("c", b.fac()).query(String.class).optional().orElse(null));
        sc.put("department", b.dept() == null ? null : jdbc.sql("SELECT name FROM ref.department WHERE upper(code) = :c").param("c", b.dept()).query(String.class).optional().orElse(null));
        sc.put("programme", b.prog() == null ? null : jdbc.sql("SELECT name FROM ref.programme WHERE upper(code) = :c").param("c", b.prog()).query(String.class).optional().orElse(null));
        out.put("scope", sc);
        out.put("students", students);
        out.put("manual", manual);
        out.put("keeper", Set.of("exams", "facultyexams", "records", "hod", "gst", "eps", "academic", "registrar", "dregistrar", "super").contains(acting()));
        return out;
    }

    /** the list marked: PRESENT, ABSENT, LATE, EXCUSED or INVALID_ATTENDANCE for students of the bound */
    @PostMapping("/{offering}/marks")
    @PreAuthorize(KEEPERS)
    @Transactional
    Map<String, Object> mark(@PathVariable UUID offering, @Valid @RequestBody MarksIn body) {
        offering(offering);
        OfficeScope.Bound b = scoped(null, null, null);
        for (Mark m : body.marks()) {
            if (!MARKS.contains(m.status().trim().toUpperCase())) {
                throw new DomainRuleViolation("ATTENDANCE_STATUS", m.status() + " is not an attendance of the list (PRESENT, ABSENT, LATE, EXCUSED, INVALID_ATTENDANCE).");
            }
        }
        Map<UUID, String[]> places = placeOf(body.marks().stream().map(Mark::student).toList());
        for (Mark m : body.marks()) {
            String[] at = places.get(m.student());
            if (at == null) throw new NotFound("student", m.student());
            if (!inside(b, at[0], at[1], at[2])) refuseOutside();
        }
        List<Map<String, Object>> marks = body.marks().stream().map(m -> {
            Map<String, Object> x = new LinkedHashMap<>();
            x.put("student", m.student().toString());
            x.put("status", m.status().trim().toUpperCase());
            if (blank(m.reason()) != null) x.put("reason", m.reason().trim());
            return x;
        }).toList();
        Integer n = jdbc.sql("SELECT assessment.record_attendance(:o, CAST(:m AS jsonb), :s, :i)")
                .param("o", offering).param("m", json.writeValueAsString(marks)).param("s", blank(body.sheet())).param("i", blank(body.invigilator()))
                .query(Integer.class).single();
        return Map.of("recorded", n);
    }

    /** a handwritten row entered: matched by the number written to the student (within the bound), or held pending verification */
    @PostMapping("/{offering}/manual")
    @PreAuthorize(KEEPERS)
    @Transactional
    Map<String, Object> manual(@PathVariable UUID offering, @Valid @RequestBody ManualIn body) {
        offering(offering);
        OfficeScope.Bound b = scoped(null, null, null);
        String number = blank(body.number());
        if (number != null) {
            // the student the number names must be within the office's own scope before anything is written
            UUID found = jdbc.sql("SELECT student_id FROM people.resolve_student(:n, true) WHERE status = 'MATCHED'").param("n", number)
                    .query(UUID.class).optional().orElse(null);
            if (found != null) {
                String[] at = placeOf(List.of(found)).get(found);
                if (at == null || !inside(b, at[0], at[1], at[2])) refuseOutside();
            }
        }
        String text = jdbc.sql("SELECT assessment.manual_attendance(:o, :n, :name, :p, :l, :r, :s, :i)::text")
                .param("o", offering).param("n", number).param("name", blank(body.name())).param("p", blank(body.programme()))
                .param("l", blank(body.level())).param("r", blank(body.reason())).param("s", blank(body.sheet())).param("i", blank(body.invigilator()))
                .query(String.class).single();
        @SuppressWarnings("unchecked")
        Map<String, Object> out = json.readValue(text, Map.class);
        return out;
    }

    /** the handwritten rows of a course pending verification — those the office entered or printed on a sheet of its bound */
    @GetMapping("/{offering}/pending")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> pending(@PathVariable UUID offering, @RequestParam(defaultValue = "PENDING") String state) {
        offering(offering);
        String st = state.trim().toUpperCase();
        if (!Set.of("PENDING", "MATCHED", "INVALID", "ALL").contains(st)) throw new DomainRuleViolation("ATTENDANCE_STATE", "A state is PENDING, MATCHED, INVALID or ALL.");
        OfficeScope.Bound b = scoped(null, null, null);
        UUID me = scope.actorId();
        List<Map<String, Object>> rows = jdbc.sql("""
                SELECT pe.*, s.scope_fac, s.scope_dept, s.scope_prog, st.matric_no AS matched_matric,
                       upper(btrim(st.surname)) || coalesce(', ' || nullif(btrim(st.other_names), ''), '') AS matched_name
                  FROM assessment.exam_attendance_pending pe
                  LEFT JOIN assessment.exam_attendance_sheet s ON s.reference = pe.sheet_reference
                  LEFT JOIN people.student st ON st.id = pe.student_id
                 WHERE pe.offering_id = :o AND (:st = 'ALL' OR pe.state = :st)
                 ORDER BY pe.entered_at DESC
                """).param("o", offering).param("st", st).query().listOfRows().stream()
                .filter(r -> (me != null && me.equals(r.get("entered_by"))) || sheetInside(b, r))
                .toList();
        return Map.of("rows", rows);
    }

    /** a handwritten row decided: matched to its student (by id or by a number) or invalid with a reason */
    @PostMapping("/pending/{id}/decide")
    @PreAuthorize(KEEPERS)
    @Transactional
    Map<String, Object> decide(@PathVariable UUID id, @Valid @RequestBody DecideIn body) {
        Map<String, Object> pe = jdbc.sql("SELECT pe.offering_id, pe.entered_by, s.scope_fac, s.scope_dept, s.scope_prog FROM assessment.exam_attendance_pending pe "
                        + "LEFT JOIN assessment.exam_attendance_sheet s ON s.reference = pe.sheet_reference WHERE pe.id = :id")
                .param("id", id).query().listOfRows().stream().findFirst().orElseThrow(() -> new NotFound("handwritten row", id));
        offering((UUID) pe.get("offering_id"));
        OfficeScope.Bound b = scoped(null, null, null);
        UUID me = scope.actorId();
        boolean visible = (me != null && me.equals(pe.get("entered_by"))) || sheetInside(b, pe);
        if (!visible) throw new DomainRuleViolation("SCOPE_SHEET", "That handwritten row is on a sheet outside your office's scope.");
        UUID student = body.student();
        if (Boolean.TRUE.equals(body.valid()) && student == null && blank(body.number()) != null) {
            Map<String, Object> m = jdbc.sql("SELECT student_id, status FROM people.resolve_student(:n, true)").param("n", body.number().trim()).query().singleRow();
            if (!"MATCHED".equals(m.get("status"))) {
                throw new DomainRuleViolation("ATTENDANCE_STUDENT", "The number " + body.number().trim() + " names "
                        + ("AMBIGUOUS".equals(m.get("status")) ? "more than one student" : "no student") + "; give the student's matriculation number.");
            }
            student = (UUID) m.get("student_id");
        }
        if (Boolean.TRUE.equals(body.valid()) && student != null) {
            String[] at = placeOf(List.of(student)).get(student);
            if (at == null) throw new NotFound("student", student);
            if (!inside(b, at[0], at[1], at[2])) refuseOutside();
        }
        String text = jdbc.sql("SELECT assessment.decide_manual_attendance(:id, :s, :v, :n)::text")
                .param("id", id).param("s", student).param("v", body.valid()).param("n", blank(body.note())).query(String.class).single();
        @SuppressWarnings("unchecked")
        Map<String, Object> out = json.readValue(text, Map.class);
        return out;
    }

    /** the course reconciled within the bound: each student with the finding, and the counts by finding */
    @GetMapping("/{offering}/reconciliation")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> reconciliation(@PathVariable UUID offering, @RequestParam(required = false) String fac, @RequestParam(required = false) String dept,
                                       @RequestParam(required = false) String prog) {
        Map<String, Object> o = offering(offering);
        OfficeScope.Bound b = scoped(fac, dept, prog);
        List<Map<String, Object>> rows = jdbc.sql("SELECT * FROM assessment.attendance_reconciliation(:o, :f, :d, :p)")
                .param("o", offering).param("f", b.fac()).param("d", b.dept()).param("p", b.prog()).query().listOfRows();
        Map<String, Integer> counts = new LinkedHashMap<>();
        for (String k : List.of("OK", "REGISTERED_NOT_ON_LIST", "ON_LIST_NOT_REGISTERED", "PRESENT_NOT_REGISTERED", "PRESENT_NOT_ELIGIBLE", "MANUAL_NOT_REGISTERED", "NOT_MARKED")) counts.put(k, 0);
        rows.forEach(r -> counts.merge((String) r.get("finding"), 1, Integer::sum));
        Map<String, Object> figures = new LinkedHashMap<>();
        figures.put("registered", rows.stream().filter(r -> Boolean.TRUE.equals(r.get("registered"))).count());
        figures.put("eligible", rows.stream().filter(r -> Boolean.TRUE.equals(r.get("eligible"))).count());
        figures.put("listed", rows.stream().filter(r -> Boolean.TRUE.equals(r.get("on_list"))).count());
        figures.put("present", rows.stream().filter(r -> Set.of("PRESENT", "LATE", "MANUAL_PRESENT").contains(String.valueOf(r.get("status")))).count());
        figures.put("absent", rows.stream().filter(r -> "ABSENT".equals(r.get("status"))).count());
        figures.put("manual", rows.stream().filter(r -> "MANUAL".equals(r.get("source"))).count());
        figures.put("pending", jdbc.sql("SELECT count(*) FROM assessment.exam_attendance_pending WHERE offering_id = :o AND state = 'PENDING'").param("o", offering).query(Long.class).single());
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("offering", o);
        out.put("figures", figures);
        out.put("findings", counts);
        out.put("rows", rows);
        return out;
    }
}
