package ng.edu.moaum.portal.allocation;

import java.sql.Types;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

import ng.edu.moaum.portal.shared.AuditContextHolder;
import ng.edu.moaum.portal.shared.DomainRuleViolation;
import ng.edu.moaum.portal.shared.OfficeScope;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * Bulk course allocation (V321): a spreadsheet of staff numbers and course codes, validated row by row
 * against the register — the lecturer, their department, the course, its department, the programme and
 * level it is offered to, the session, the semester, the offering, duplicates in the file, allocations
 * already on record, the 12-unit load and the office's own scope — then written, the valid rows only,
 * through the same allocation every desk uses: {@code catalogue.allocate_offering} for a lead,
 * {@code offering_teacher} for a co-lecturer, the offering's second examiner. The spreadsheet never
 * creates or changes a lecturer, a course, a department, a programme, a session or a semester.
 */
@Service
public class AllocationImportService {

    public static final int MAX_ROWS = 50_000;
    public static final int MAX_UNITS = 12;

    public record RowIn(Integer row, String staffId, String lecturerName, String lecturerDept, String courseCode, String courseTitle,
                        String courseDept, String programme, String level, String session, String semester, String role, String crossDepartment) {
    }

    public record Options(Boolean allowOverload, Boolean replaceExisting) {
        boolean overload() { return Boolean.TRUE.equals(allowOverload); }
        boolean replace() { return Boolean.TRUE.equals(replaceExisting); }
    }

    /** one row as validated: what it resolved to, its status and every finding */
    public record Finding(int row, String staffId, String lecturer, String department, String courseCode, String course, String courseDepartment,
                          String programme, Integer level, String session, Integer semester, String role, String status,
                          List<String> codes, List<String> messages, String action) {
    }

    public record Summary(int total, int valid, int warnings, int errors, int duplicates, int existing, int willImport) {
    }

    public record Validation(Summary summary, List<Finding> rows) {
    }

    public record ImportResult(UUID id, String reference, String status, boolean repeated, int imported, Summary summary, List<Finding> rows) {
    }

    /* what the import step needs of a validated row */
    private record Plan(UUID offering, UUID person, String role, UUID keepSecond, boolean overload, String courseCode, String courseTitle,
                        String session, int semester, int units) {
    }

    private record Person(UUID id, String staffNumber, String surname, String givenNames, boolean ended) {
    }

    private record Course(String code, String title, int units, String dept, String kind, String state, int semester, int level, String generalOffice) {
    }

    private record Offering(UUID id, String courseCode, String session, int semester, UUID lecturer, UUID second) {
    }

    private final JdbcClient jdbc;
    private final OfficeScope scope;
    private final tools.jackson.databind.ObjectMapper json;

    AllocationImportService(JdbcClient jdbc, OfficeScope scope, tools.jackson.databind.ObjectMapper json) {
        this.jdbc = jdbc;
        this.scope = scope;
        this.json = json;
    }

    /* ── normalisation: trimmed, codes in capitals, nothing guessed ── */

    private static String t(String s) {
        return s == null ? "" : s.trim().replaceAll("\\s+", " ");
    }

    private static String up(String s) {
        return t(s).toUpperCase(Locale.ROOT);
    }

    private static String nospace(String s) {
        return up(s).replaceAll("\\s", "");
    }

    private static String sessionOf(String s) {
        String v = t(s).replace('-', '/');
        return v.matches("\\d{4}/\\d{4}") ? v : null;
    }

    private static Integer semesterOf(String s) {
        String v = up(s);
        if (v.isEmpty()) return null;
        if (v.matches("[123]")) return Integer.parseInt(v);
        if (v.startsWith("FIRST") || v.equals("1ST") || v.equals("I")) return 1;
        if (v.startsWith("SECOND") || v.equals("2ND") || v.equals("II")) return 2;
        if (v.startsWith("THIRD") || v.equals("3RD") || v.equals("III")) return 3;
        return -1;
    }

    private static Integer levelOf(String s) {
        String v = up(s).replaceAll("[^0-9]", "");
        if (v.isEmpty()) return null;
        try {
            int n = Integer.parseInt(v);
            return n >= 100 && n <= 900 && n % 100 == 0 ? n : -1;
        } catch (NumberFormatException bad) {
            return -1;
        }
    }

    private static String roleOf(String s) {
        String v = up(s);
        if (v.isEmpty() || v.equals("LECTURER") || v.equals("LEAD") || v.equals("LEAD LECTURER") || v.equals("PRIMARY") || v.equals("MAIN")) return "LECTURER";
        if (v.startsWith("CO") || v.contains("CO-LECT") || v.contains("ASSIST")) return "CO_LECTURER";
        if (v.contains("SECOND") || v.contains("EXAMINER") || v.contains("VERIF")) return "SECOND_EXAMINER";
        return null;
    }

    private static boolean yes(String s) {
        String v = up(s);
        return v.equals("YES") || v.equals("Y") || v.equals("TRUE") || v.equals("1") || v.equals("ALLOW") || v.equals("ALLOWED");
    }

    private static <T> List<List<T>> chunks(List<T> all, int size) {
        List<List<T>> out = new ArrayList<>();
        for (int i = 0; i < all.size(); i += size) out.add(all.subList(i, Math.min(all.size(), i + size)));
        return out;
    }

    /* ── the register, loaded in batches for everything the file names ── */

    private final class Register {
        final Map<String, Person> personsByStaff = new HashMap<>();
        final Map<UUID, Set<String>> deptsOfPerson = new HashMap<>();
        final Map<String, Map<String, Object>> deptByCode = new HashMap<>();
        final Map<String, String> deptCodeByName = new HashMap<>();
        final Map<String, Map<String, Object>> progByCode = new HashMap<>();
        final Map<String, String> progCodeByName = new HashMap<>();
        final Map<String, Course> courseByCode = new HashMap<>();
        final Map<String, String> courseCodeByNoSpace = new HashMap<>();
        final Map<String, Map<String, Object>> sessions = new HashMap<>();
        final Map<String, Offering> offerings = new HashMap<>();              // course|session|semester
        final Map<UUID, Set<UUID>> teachers = new HashMap<>();
        final Map<String, Set<String>> offersOfCourse = new HashMap<>();      // course → programme|level
        final Map<String, Integer> load = new HashMap<>();                    // person|session|semester → units

        Register(List<RowIn> rows) {
            for (Map<String, Object> d : jdbc.sql("SELECT code, name, faculty_code FROM ref.department WHERE ended_on IS NULL").query().listOfRows()) {
                deptByCode.put(up((String) d.get("code")), d);
                deptCodeByName.put(up((String) d.get("name")), (String) d.get("code"));
            }
            for (Map<String, Object> p : jdbc.sql("SELECT code, name, dept_code, archived FROM ref.programme").query().listOfRows()) {
                progByCode.put(up((String) p.get("code")), p);
                progCodeByName.putIfAbsent(up((String) p.get("name")), (String) p.get("code"));
            }
            Set<String> staff = new HashSet<>(), codes = new HashSet<>(), nospaces = new HashSet<>(), sess = new HashSet<>();
            for (RowIn r : rows) {
                if (!up(r.staffId()).isEmpty()) staff.add(up(r.staffId()));
                if (!up(r.courseCode()).isEmpty()) { codes.add(up(r.courseCode())); nospaces.add(nospace(r.courseCode())); }
                String s = sessionOf(r.session());
                if (s != null) sess.add(s);
            }
            for (List<String> part : chunks(new ArrayList<>(staff), 2000)) {
                for (Map<String, Object> p : jdbc.sql("SELECT id, staff_number, surname, given_names, ended_on FROM iam.person WHERE upper(btrim(staff_number)) IN (:ids)")
                        .param("ids", part).query().listOfRows()) {
                    personsByStaff.put(up((String) p.get("staff_number")), new Person((UUID) p.get("id"), (String) p.get("staff_number"),
                            String.valueOf(p.get("surname")), String.valueOf(p.get("given_names")), p.get("ended_on") != null));
                }
            }
            List<UUID> pids = personsByStaff.values().stream().map(Person::id).toList();
            for (List<UUID> part : chunks(pids, 2000)) {
                for (Map<String, Object> g : jdbc.sql("""
                        SELECT a.person_id, a.scope_id FROM iam.office_assignment a
                         WHERE a.person_id IN (:p) AND a.office_code IN ('lecturer', 'hod') AND a.scope_kind = 'department'
                           AND nullif(btrim(a.scope_id), '') IS NOT NULL
                           AND a.valid_from <= current_date AND (a.valid_to IS NULL OR a.valid_to >= current_date)
                        """).param("p", part).query().listOfRows()) {
                    String code = deptCode((String) g.get("scope_id"));
                    if (code != null) deptsOfPerson.computeIfAbsent((UUID) g.get("person_id"), k -> new HashSet<>()).add(code);
                }
                for (Map<String, Object> h : jdbc.sql("SELECT person_id, home_department FROM hrm.staff_record WHERE person_id IN (:p) AND nullif(btrim(coalesce(home_department, '')), '') IS NOT NULL")
                        .param("p", part).query().listOfRows()) {
                    String code = deptCode((String) h.get("home_department"));
                    if (code != null) deptsOfPerson.computeIfAbsent((UUID) h.get("person_id"), k -> new HashSet<>()).add(code);
                }
            }
            for (List<String> part : chunks(new ArrayList<>(codes), 2000)) {
                List<String> ns = part.stream().map(x -> x.replaceAll("\\s", "")).toList();
                for (Map<String, Object> c : jdbc.sql("""
                        SELECT code, title, units, dept_code, kind, state, semester, level, general_office FROM catalogue.course
                         WHERE upper(code) IN (:c) OR regexp_replace(upper(code), '\\s', '', 'g') IN (:n)
                        """).param("c", part).param("n", ns).query().listOfRows()) {
                    Course course = new Course((String) c.get("code"), String.valueOf(c.get("title")), ((Number) c.get("units")).intValue(), (String) c.get("dept_code"),
                            String.valueOf(c.get("kind")), String.valueOf(c.get("state")), ((Number) c.get("semester")).intValue(), ((Number) c.get("level")).intValue(), (String) c.get("general_office"));
                    courseByCode.put(up(course.code()), course);
                    courseCodeByNoSpace.putIfAbsent(nospace(course.code()), course.code());
                }
            }
            if (!sess.isEmpty()) {
                for (Map<String, Object> s : jdbc.sql("SELECT name, semesters, state FROM policy.academic_session WHERE name IN (:s)").param("s", new ArrayList<>(sess)).query().listOfRows()) {
                    sessions.put((String) s.get("name"), s);
                }
            }
            List<String> realCodes = courseByCode.values().stream().map(Course::code).toList();
            if (!realCodes.isEmpty() && !sess.isEmpty()) {
                for (List<String> part : chunks(realCodes, 2000)) {
                    for (Map<String, Object> o : jdbc.sql("SELECT id, course_code, session, semester, lecturer_id, second_examiner_id FROM catalogue.offering WHERE session IN (:s) AND course_code IN (:c) AND stream = 'REGULAR'")
                            .param("s", new ArrayList<>(sess)).param("c", part).query().listOfRows()) {
                        Offering off = new Offering((UUID) o.get("id"), (String) o.get("course_code"), (String) o.get("session"), ((Number) o.get("semester")).intValue(),
                                (UUID) o.get("lecturer_id"), (UUID) o.get("second_examiner_id"));
                        offerings.put(key(off.courseCode(), off.session(), off.semester()), off);
                    }
                }
                List<UUID> oids = offerings.values().stream().map(Offering::id).toList();
                for (List<UUID> part : chunks(oids, 2000)) {
                    for (Map<String, Object> tr : jdbc.sql("SELECT offering_id, lecturer_id FROM catalogue.offering_teacher WHERE offering_id IN (:o)").param("o", part).query().listOfRows()) {
                        teachers.computeIfAbsent((UUID) tr.get("offering_id"), k -> new HashSet<>()).add((UUID) tr.get("lecturer_id"));
                    }
                }
            }
            for (List<String> part : chunks(realCodes, 2000)) {
                for (Map<String, Object> f : jdbc.sql("SELECT course_code, programme_code, level FROM catalogue.course_offer WHERE course_code IN (:c)").param("c", part).query().listOfRows()) {
                    offersOfCourse.computeIfAbsent(up((String) f.get("course_code")), k -> new HashSet<>()).add(up((String) f.get("programme_code")) + "|" + f.get("level"));
                }
            }
            if (!pids.isEmpty() && !sess.isEmpty()) {
                for (List<UUID> part : chunks(pids, 2000)) {
                    for (Map<String, Object> l : jdbc.sql("""
                            SELECT o.lecturer_id, o.session, o.semester, coalesce(sum(c.units), 0) AS units
                              FROM catalogue.offering o JOIN catalogue.course c ON c.code = o.course_code
                             WHERE o.lecturer_id IN (:p) AND o.session IN (:s) AND o.stream = 'REGULAR' GROUP BY 1, 2, 3
                            """).param("p", part).param("s", new ArrayList<>(sess)).query().listOfRows()) {
                        load.put(l.get("lecturer_id") + "|" + l.get("session") + "|" + l.get("semester"), ((Number) l.get("units")).intValue());
                    }
                }
            }
        }

        String deptCode(String codeOrName) {
            if (codeOrName == null) return null;
            String u = up(codeOrName);
            if (u.isEmpty()) return null;
            Map<String, Object> d = deptByCode.get(u);
            if (d != null) return (String) d.get("code");
            return deptCodeByName.get(u);
        }

        String deptName(String code) {
            Map<String, Object> d = code == null ? null : deptByCode.get(up(code));
            return d == null ? code : (String) d.get("name");
        }

        String facultyOf(String code) {
            Map<String, Object> d = code == null ? null : deptByCode.get(up(code));
            return d == null ? null : (String) d.get("faculty_code");
        }

        String progCode(String codeOrName) {
            String u = up(codeOrName);
            if (u.isEmpty()) return null;
            Map<String, Object> p = progByCode.get(u);
            if (p != null) return (String) p.get("code");
            return progCodeByName.get(u);
        }

        Course course(String code) {
            Course c = courseByCode.get(up(code));
            if (c != null) return c;
            String real = courseCodeByNoSpace.get(nospace(code));
            return real == null ? null : courseByCode.get(up(real));
        }
    }

    private static String key(String course, String session, int semester) {
        return up(course) + "|" + session + "|" + semester;
    }

    /* ── the validation: every row judged against the register, nothing written ── */

    private record Judged(Finding finding, Plan plan) {
    }

    private List<Judged> judge(List<RowIn> rows, Options opts) {
        if (rows == null || rows.isEmpty()) {
            throw new DomainRuleViolation("ALLOC_IMPORT_EMPTY", "The file has no allocation rows.", new DomainRuleViolation.Remedy("Fill the template's Allocations sheet and upload it again.", "You"));
        }
        if (rows.size() > MAX_ROWS) {
            throw new DomainRuleViolation("ALLOC_IMPORT_TOO_LARGE", "The file has " + rows.size() + " rows; the limit is " + MAX_ROWS + " in one import.",
                    new DomainRuleViolation.Remedy("Split the file by department or semester and upload each part.", "You"));
        }
        Register reg = new Register(rows);
        boolean hod = scope.actingHod();
        String hodDept = hod ? scope.actingHodDept() : null;
        boolean facultyOffice = scope.actingFacultyOffice();
        String faculty = facultyOffice ? scope.actingFaculty() : null;
        Map<String, Integer> projected = new HashMap<>(reg.load);
        Map<String, Integer> seen = new HashMap<>();
        List<Judged> out = new ArrayList<>(rows.size());
        int n = 0;
        for (RowIn r : rows) {
            n++;
            int rowNo = r.row() == null ? n + 1 : r.row();
            List<String> codes = new ArrayList<>();
            List<String> messages = new ArrayList<>();
            String action = null;
            boolean fatal = false;
            String status = "VALID";

            // the required fields
            if (up(r.staffId()).isEmpty()) { codes.add("INVALID_REQUIRED_FIELD"); messages.add("Staff ID is blank"); fatal = true; }
            if (up(r.courseCode()).isEmpty()) { codes.add("INVALID_REQUIRED_FIELD"); messages.add("Course code is blank"); fatal = true; }
            String session = sessionOf(r.session());
            if (session == null) {
                if (up(r.session()).isEmpty()) { codes.add("INVALID_REQUIRED_FIELD"); messages.add("Session is blank"); }
                else { codes.add("INVALID_FORMAT"); messages.add("Session \"" + t(r.session()) + "\" is not of the form 2026/2027"); }
                fatal = true;
            }
            Integer semester = semesterOf(r.semester());
            if (semester == null) { codes.add("INVALID_REQUIRED_FIELD"); messages.add("Semester is blank"); fatal = true; }
            else if (semester < 0) { codes.add("INVALID_FORMAT"); messages.add("Semester \"" + t(r.semester()) + "\" is not 1, 2, First or Second"); fatal = true; semester = null; }
            Integer level = levelOf(r.level());
            if (level != null && level < 0) { codes.add("INVALID_FORMAT"); messages.add("Level \"" + t(r.level()) + "\" is not 100, 200 … 900"); fatal = true; level = null; }
            String role = roleOf(r.role());
            if (role == null) { codes.add("INVALID_FORMAT"); messages.add("Role \"" + t(r.role()) + "\" is not Lecturer, Co-lecturer or Second examiner"); fatal = true; role = "LECTURER"; }

            // the session and the semester
            Map<String, Object> sess = session == null ? null : reg.sessions.get(session);
            if (session != null && sess == null) { codes.add("SESSION_NOT_FOUND"); messages.add("Academic session " + session + " is not on the calendar"); action = "Choose a session the University has opened; a session is created on the academic calendar, never from a file."; fatal = true; }
            else if (sess != null && semester != null) {
                int semesters = sess.get("semesters") == null ? 2 : ((Number) sess.get("semesters")).intValue();
                if (semester > semesters) { codes.add("SEMESTER_NOT_FOUND"); messages.add("Session " + session + " has " + semesters + " semesters; semester " + semester + " is not one of them"); fatal = true; }
            }

            // the lecturer
            Person person = up(r.staffId()).isEmpty() ? null : reg.personsByStaff.get(up(r.staffId()));
            if (!up(r.staffId()).isEmpty() && person == null) { codes.add("STAFF_ID_NOT_FOUND"); messages.add("No member of staff holds the number " + t(r.staffId())); action = "Check the staff number on the teaching staff register; a lecturer is added there, never from this file."; fatal = true; }
            Set<String> lecturerDepts = person == null ? Set.of() : reg.deptsOfPerson.getOrDefault(person.id(), Set.of());
            if (person != null) {
                if (person.ended()) { codes.add("LECTURER_INACTIVE"); messages.add(person.surname() + ", " + person.givenNames() + " has left the University"); fatal = true; }
                else if (lecturerDepts.isEmpty()) { codes.add("LECTURER_NOT_FOUND"); messages.add(person.surname() + ", " + person.givenNames() + " holds no lecturer's office at present"); action = "Grant the lecturer's office over their department on Users & Roles, or on the teaching staff register."; fatal = true; }
                String wantName = up(r.lecturerName());
                if (!wantName.isEmpty() && !wantName.contains(up(person.surname())) && !up(person.surname()).contains(wantName.split(" ")[0])) {
                    codes.add("LECTURER_NAME_MISMATCH"); messages.add("The file says \"" + t(r.lecturerName()) + "\"; staff number " + t(r.staffId()) + " is " + person.surname() + ", " + person.givenNames());
                    status = "WARNING";
                }
            }
            String sheetLecturerDept = reg.deptCode(r.lecturerDept());
            if (!up(r.lecturerDept()).isEmpty() && sheetLecturerDept == null) { codes.add("DEPARTMENT_NOT_FOUND"); messages.add("Department \"" + t(r.lecturerDept()) + "\" is not on the register"); fatal = true; }
            else if (sheetLecturerDept != null && person != null && !lecturerDepts.isEmpty() && !lecturerDepts.contains(sheetLecturerDept)) {
                codes.add("LECTURER_DEPARTMENT_MISMATCH");
                messages.add("The file puts the lecturer in " + reg.deptName(sheetLecturerDept) + "; the register has " + String.join(", ", lecturerDepts.stream().map(reg::deptName).sorted().toList()));
                action = "Correct the department in the file, or choose the lecturer the register has in that department."; fatal = true;
            }

            // the course
            Course course = up(r.courseCode()).isEmpty() ? null : reg.course(r.courseCode());
            if (!up(r.courseCode()).isEmpty() && course == null) { codes.add("COURSE_NOT_FOUND"); messages.add("No course " + up(r.courseCode()) + " is on the catalogue"); action = "Create the course on the department's catalogue first; an allocation never creates a course."; fatal = true; }
            if (course != null) {
                if ("ENDED".equals(course.state())) { codes.add("COURSE_ENDED"); messages.add(course.code() + " has ended and is not allocated"); fatal = true; }
                String wantTitle = up(r.courseTitle());
                if (!wantTitle.isEmpty() && !wantTitle.equals(up(course.title()))) {
                    codes.add("COURSE_TITLE_MISMATCH"); messages.add("The file calls " + course.code() + " \"" + t(r.courseTitle()) + "\"; the catalogue has \"" + course.title() + "\" — the catalogue stands");
                    if (!"ERROR".equals(status)) status = "WARNING";
                }
                String sheetCourseDept = reg.deptCode(r.courseDept());
                if (!up(r.courseDept()).isEmpty() && sheetCourseDept == null) { codes.add("DEPARTMENT_NOT_FOUND"); messages.add("Course department \"" + t(r.courseDept()) + "\" is not on the register"); fatal = true; }
                else if (sheetCourseDept != null && !sheetCourseDept.equalsIgnoreCase(course.dept())) {
                    codes.add("COURSE_DEPARTMENT_MISMATCH"); messages.add("The file puts " + course.code() + " in " + reg.deptName(sheetCourseDept) + "; the catalogue has it in " + reg.deptName(course.dept()));
                    action = "Correct the course department in the file; a course's department is changed on the catalogue, never from a file."; fatal = true;
                }
                // the lecturer's department against the course's: strict, unless the course is a service course (GST) or the
                // row says so, as the allocation desk's "lecturers from other departments" does
                boolean service = "GST".equalsIgnoreCase(course.kind()) || course.generalOffice() != null;
                if (person != null && !lecturerDepts.isEmpty() && !lecturerDepts.contains(course.dept()) && !service && !yes(r.crossDepartment())) {
                    codes.add("CROSS_DEPARTMENT_NOT_ALLOWED");
                    messages.add(course.code() + " belongs to " + reg.deptName(course.dept()) + "; " + person.surname() + " is in " + String.join(", ", lecturerDepts.stream().map(reg::deptName).sorted().toList()));
                    action = "Put YES in Cross-department to allocate across departments, as the allocation desk's option does, or choose a lecturer of the course's department."; fatal = true;
                }
                // the office's own scope: a Head of Department allocates their department's courses, a faculty office its faculty's
                if (hod && (hodDept == null || !hodDept.equalsIgnoreCase(course.dept()))) {
                    codes.add("OUT_OF_SCOPE"); messages.add(course.code() + " belongs to " + reg.deptName(course.dept()) + ", not your department"); action = "A Head of Department allocates only the department's own courses."; fatal = true;
                } else if (facultyOffice && (faculty == null || !faculty.equalsIgnoreCase(reg.facultyOf(course.dept())))) {
                    codes.add("OUT_OF_SCOPE"); messages.add(course.code() + " belongs to a department outside your faculty"); fatal = true;
                }
                // the programme and the level: the course must be offered to the programme, at the level, on the structure
                String prog = reg.progCode(r.programme());
                if (!up(r.programme()).isEmpty() && prog == null) { codes.add("PROGRAMME_NOT_FOUND"); messages.add("Programme \"" + t(r.programme()) + "\" is not on the register"); fatal = true; }
                if (prog != null) {
                    Map<String, Object> p = reg.progByCode.get(up(prog));
                    if (Boolean.TRUE.equals(p.get("archived"))) { codes.add("PROGRAMME_ARCHIVED"); messages.add("Programme " + prog + " is archived"); fatal = true; }
                    Set<String> offers = reg.offersOfCourse.getOrDefault(up(course.code()), Set.of());
                    boolean toProg = offers.stream().anyMatch(x -> x.startsWith(up(prog) + "|"));
                    if (!toProg) { codes.add("COURSE_NOT_OFFERED_TO_PROGRAMME"); messages.add(course.code() + " is not on the structure of " + p.get("name")); action = "Bind the course into the programme's structure on the catalogue, or leave the programme blank."; fatal = true; }
                    else if (level != null && !offers.contains(up(prog) + "|" + level)) { codes.add("INVALID_LEVEL"); messages.add(course.code() + " is not offered to " + p.get("name") + " at " + level + " level"); fatal = true; }
                } else if (level != null && course.level() != level && !reg.offersOfCourse.getOrDefault(up(course.code()), Set.of()).stream().map(x -> x.substring(x.indexOf('|') + 1)).toList().contains(String.valueOf(level))) {
                    codes.add("INVALID_LEVEL"); messages.add(course.code() + " is a " + course.level() + " level course and is offered to no programme at " + level + " level"); fatal = true;
                }
            }

            // the offering: the course must be offered in that session and semester
            Offering off = (course == null || session == null || semester == null) ? null : reg.offerings.get(key(course.code(), session, semester));
            if (course != null && session != null && semester != null && sess != null && off == null) {
                codes.add("COURSE_NOT_OFFERED"); messages.add(course.code() + " is not offered in " + session + " semester " + semester + (course.semester() != semester ? " (it is a semester " + course.semester() + " course)" : ""));
                action = "The offering opens when course registration is opened for the semester, or the Academic Office adds it; an allocation never creates one."; fatal = true;
            }

            // duplicates in the file: the same lecturer, course, session, semester and role twice
            if (!fatal && person != null && course != null) {
                String dup = person.id() + "|" + up(course.code()) + "|" + session + "|" + semester + "|" + role;
                Integer first = seen.get(dup);
                if (first != null) { codes.add("DUPLICATE_IN_FILE"); messages.add("The same allocation is on row " + first); status = "DUPLICATE"; }
                else seen.put(dup, rowNo);
            }

            // what is already on record, and the load
            Plan plan = null;
            if (!fatal && !"DUPLICATE".equals(status) && off != null && person != null && course != null) {
                Set<UUID> co = reg.teachers.getOrDefault(off.id(), Set.of());
                switch (role) {
                    case "LECTURER" -> {
                        if (person.id().equals(off.lecturer())) { codes.add("ALLOCATION_ALREADY_EXISTS"); messages.add(person.surname() + " already leads " + course.code() + " in " + session + " semester " + semester); status = "EXISTING"; }
                        else if (off.lecturer() != null && !opts.replace()) {
                            codes.add("ALLOCATION_EXISTS_OTHER"); messages.add(course.code() + " already has a lead lecturer on record"); action = "Tick \"Replace existing leads\" to change the lead from this file, or change it on the allocation desk."; fatal = true;
                        } else {
                            if (off.lecturer() != null) { codes.add("WILL_REPLACE_LEAD"); messages.add("The lead of " + course.code() + " on record is replaced by " + person.surname()); status = "WARNING"; }
                            String lk = person.id() + "|" + session + "|" + semester;
                            int have = projected.getOrDefault(lk, 0);
                            boolean overload = have + course.units() > MAX_UNITS;
                            if (overload) {
                                codes.add("LECTURER_WORKLOAD_EXCEEDED"); messages.add(person.surname() + " carries " + have + " units in " + session + " semester " + semester + "; " + course.code() + " makes " + (have + course.units()) + ", over the maximum of " + MAX_UNITS);
                                if (opts.overload()) status = "WARNING";
                                else { action = "Tick \"Allow overloads\" to allocate above " + MAX_UNITS + " units — the overload is on the record and reported to the Dean — or lighten the load."; fatal = true; }
                            }
                            if (!fatal) {
                                projected.put(lk, have + course.units());
                                UUID keep = off.second() != null && off.second().equals(person.id()) ? null : off.second();
                                plan = new Plan(off.id(), person.id(), role, keep, overload, course.code(), course.title(), session, semester, course.units());
                            }
                        }
                    }
                    case "CO_LECTURER" -> {
                        if (co.contains(person.id())) { codes.add("ALLOCATION_ALREADY_EXISTS"); messages.add(person.surname() + " is already a co-lecturer of " + course.code()); status = "EXISTING"; }
                        else if (person.id().equals(off.lecturer())) { codes.add("CO_LECTURER_IS_LEAD"); messages.add(person.surname() + " leads " + course.code() + " already"); fatal = true; }
                        else plan = new Plan(off.id(), person.id(), role, null, false, course.code(), course.title(), session, semester, course.units());
                    }
                    default -> {
                        if (person.id().equals(off.second())) { codes.add("ALLOCATION_ALREADY_EXISTS"); messages.add(person.surname() + " is already the second examiner of " + course.code()); status = "EXISTING"; }
                        else if (person.id().equals(off.lecturer())) { codes.add("SECOND_EXAMINER_IS_LEAD"); messages.add("The second examiner cannot be the lead lecturer of " + course.code()); fatal = true; }
                        else if (off.second() != null && !opts.replace()) { codes.add("ALLOCATION_EXISTS_OTHER"); messages.add(course.code() + " already has a second examiner on record"); action = "Tick \"Replace existing leads\" to change it from this file."; fatal = true; }
                        else plan = new Plan(off.id(), person.id(), role, null, false, course.code(), course.title(), session, semester, course.units());
                    }
                }
            }
            if (fatal) status = "ERROR";
            if (action == null && "ERROR".equals(status)) action = "Correct the row and upload the file again; nothing on it was written.";
            Finding f = new Finding(rowNo, t(r.staffId()), person == null ? t(r.lecturerName()) : person.surname() + ", " + person.givenNames(),
                    person == null ? t(r.lecturerDept()) : String.join(", ", lecturerDepts.stream().map(reg::deptName).sorted().toList()),
                    course == null ? up(r.courseCode()) : course.code(), course == null ? t(r.courseTitle()) : course.title(), course == null ? t(r.courseDept()) : reg.deptName(course.dept()),
                    t(r.programme()), level, session == null ? t(r.session()) : session, semester, role, status, codes, messages, action);
            out.add(new Judged(f, "ERROR".equals(status) || "DUPLICATE".equals(status) || "EXISTING".equals(status) ? null : plan));
        }
        return out;
    }

    private static Summary summarise(List<Judged> judged) {
        int valid = 0, warnings = 0, errors = 0, duplicates = 0, existing = 0, will = 0;
        for (Judged j : judged) {
            switch (j.finding().status()) {
                case "VALID" -> valid++;
                case "WARNING" -> warnings++;
                case "ERROR" -> errors++;
                case "DUPLICATE" -> duplicates++;
                default -> existing++;
            }
            if (j.plan() != null) will++;
        }
        return new Summary(judged.size(), valid, warnings, errors, duplicates, existing, will);
    }

    @Transactional(readOnly = true)
    public Validation validate(List<RowIn> rows, Options opts) {
        List<Judged> judged = judge(rows, opts == null ? new Options(false, false) : opts);
        return new Validation(summarise(judged), judged.stream().map(Judged::finding).toList());
    }

    /* ── the import: the valid rows, in one transaction, through the same allocation every desk uses ── */

    @SuppressWarnings("unchecked")
    @Transactional
    public ImportResult importRows(UUID importKey, String fileName, List<RowIn> rows, Options opts) {
        if (importKey == null) {
            throw new DomainRuleViolation("ALLOC_IMPORT_KEY", "An import carries the key its validation was given, so a repeated press cannot allocate twice.",
                    new DomainRuleViolation.Remedy("Validate the file again and import from the preview.", "You"));
        }
        Map<String, Object> already = jdbc.sql("SELECT id, reference, status, imported, findings::text AS findings, total_rows, valid_rows, warnings, errors, existing, skipped FROM catalogue.allocation_import WHERE import_key = :k")
                .param("k", importKey).query().listOfRows().stream().findFirst().orElse(null);
        if (already != null) {
            List<Finding> findings = readFindings(already.get("findings"));
            int imported = ((Number) already.get("imported")).intValue();
            return new ImportResult((UUID) already.get("id"), (String) already.get("reference"), (String) already.get("status"), true, imported,
                    new Summary(((Number) already.get("total_rows")).intValue(), ((Number) already.get("valid_rows")).intValue(), ((Number) already.get("warnings")).intValue(),
                            ((Number) already.get("errors")).intValue(), 0, ((Number) already.get("existing")).intValue(), imported), findings);
        }
        Options o = opts == null ? new Options(false, false) : opts;
        List<Judged> judged = judge(rows, o);
        UUID me = scope.actorId();
        int imported = 0;
        String session = null;
        Integer semester = null;
        boolean mixedSemester = false;
        for (Judged j : judged) {
            Plan p = j.plan();
            if (p == null) continue;
            if (session == null) session = p.session();
            if (semester == null) semester = p.semester();
            else if (semester != p.semester()) mixedSemester = true;
            switch (p.role()) {
                case "LECTURER" -> {
                    // the second examiner on record stays — the one the register had, or the one an earlier row of this file just set —
                    // unless it is the new lead, who cannot verify their own marks
                    UUID second = jdbc.sql("SELECT second_examiner_id FROM catalogue.offering WHERE id = :o").param("o", p.offering()).query(UUID.class).optional().orElse(null);
                    if (second != null && second.equals(p.person())) second = null;
                    jdbc.sql("SELECT catalogue.allocate_offering(:o, :lec, :sec, :ov)").param("o", p.offering()).param("lec", p.person())
                            .param("sec", second, Types.OTHER).param("ov", p.overload()).query().listOfRows();
                }
                case "CO_LECTURER" -> jdbc.sql("INSERT INTO catalogue.offering_teacher (offering_id, lecturer_id, added_by) VALUES (:o, :lec, :by) ON CONFLICT (offering_id, lecturer_id) DO NOTHING")
                        .param("o", p.offering()).param("lec", p.person()).param("by", me, Types.OTHER).update();
                default -> jdbc.sql("UPDATE catalogue.offering SET second_examiner_id = :p WHERE id = :o AND (lecturer_id IS NULL OR lecturer_id <> :p)")
                        .param("p", p.person()).param("o", p.offering()).update();
            }
            if (!"SECOND_EXAMINER".equals(p.role())) tell(p);
            imported++;
        }
        if (session == null) {
            // nothing imported: the record is filed under the session the file names, or the session in progress
            session = judged.stream().map(x -> x.finding().session()).filter(s -> s != null && s.matches("\\d{4}/\\d{4}")).findFirst().orElse(null);
            if (session == null || !jdbc.sql("SELECT EXISTS (SELECT 1 FROM policy.academic_session WHERE name = :s)").param("s", session).query(Boolean.class).single()) {
                session = jdbc.sql("SELECT name FROM policy.academic_session ORDER BY (state = 'CURRENT') DESC, starts_on DESC LIMIT 1").query(String.class).single();
            }
        }
        Summary s = summarise(judged);
        String status = imported == 0 ? "NOTHING_TO_IMPORT" : s.errors() + s.duplicates() > 0 ? "COMPLETED_WITH_ERRORS" : "COMPLETED";
        String scopeDept = scope.actingHod() ? scope.actingHodDept() : null;
        List<Finding> findings = judged.stream().map(Judged::finding).toList();
        String findingsJson, optionsJson;
        try {
            findingsJson = json.writeValueAsString(findings);
            optionsJson = json.writeValueAsString(Map.of("allowOverload", o.overload(), "replaceExisting", o.replace()));
        } catch (RuntimeException bad) {
            findingsJson = "[]";
            optionsJson = "{}";
        }
        Map<String, Object> rec = jdbc.sql("""
                SELECT id, reference, status FROM catalogue.record_allocation_import(:k, :f, :s, :sem, :d, :total, :valid, :imported, :existing, :skipped, :errors, :warnings, :status, :opts::jsonb, :findings::jsonb)
                """).param("k", importKey).param("f", fileName, Types.VARCHAR).param("s", session).param("sem", mixedSemester ? null : semester, Types.INTEGER)
                .param("d", scopeDept, Types.VARCHAR).param("total", s.total()).param("valid", s.valid() + s.warnings()).param("imported", imported)
                .param("existing", s.existing()).param("skipped", s.total() - imported).param("errors", s.errors() + s.duplicates()).param("warnings", s.warnings())
                .param("status", status).param("opts", optionsJson).param("findings", findingsJson).query().singleRow();
        return new ImportResult((UUID) rec.get("id"), (String) rec.get("reference"), (String) rec.get("status"), false, imported, s, findings);
    }

    /** the lecturer is told of the course they now carry: an e-mail through the queue, when they have an address */
    private void tell(Plan p) {
        String semester = p.semester() == 1 ? "First" : p.semester() == 2 ? "Second" : "Third";
        jdbc.sql("""
                SELECT platform.queue_notice('EMAIL', person.email, :subj, :body, 'offering', :o)
                  FROM iam.person person WHERE person.id = :p AND nullif(btrim(coalesce(person.email, '')), '') IS NOT NULL
                """).param("subj", "Course allocation: " + p.courseCode() + " — " + p.courseTitle())
                .param("body", "You have been allocated " + p.courseCode() + " — " + p.courseTitle() + " (" + p.units() + " units) for " + p.session() + ", " + semester
                        + " semester" + ("CO_LECTURER".equals(p.role()) ? ", as a co-lecturer" : ", as the lead lecturer") + ". The course is on your teaching page on the portal; its score sheet opens there once the examination session is open.")
                .param("o", p.offering()).param("p", p.person()).query().listOfRows();
    }

    @SuppressWarnings("unchecked")
    List<Finding> readFindings(Object text) {
        if (text == null) return List.of();
        try {
            List<Map<String, Object>> raw = json.readValue(String.valueOf(text), List.class);
            List<Finding> out = new ArrayList<>(raw.size());
            for (Map<String, Object> m : raw) {
                out.add(new Finding(((Number) m.getOrDefault("row", 0)).intValue(), (String) m.get("staffId"), (String) m.get("lecturer"), (String) m.get("department"),
                        (String) m.get("courseCode"), (String) m.get("course"), (String) m.get("courseDepartment"), (String) m.get("programme"),
                        m.get("level") == null ? null : ((Number) m.get("level")).intValue(), (String) m.get("session"),
                        m.get("semester") == null ? null : ((Number) m.get("semester")).intValue(), (String) m.get("role"), (String) m.get("status"),
                        (List<String>) m.getOrDefault("codes", List.of()), (List<String>) m.getOrDefault("messages", List.of()), (String) m.get("action")));
            }
            return out;
        } catch (RuntimeException bad) {
            return List.of();
        }
    }

    /** the imports the acting office may see: a Head of Department their department's and their own, a faculty office its
     *  faculty's, every other allocator the University's */
    @Transactional(readOnly = true)
    public List<Map<String, Object>> history(int limit) {
        UUID me = scope.actorId();
        String where = "";
        Map<String, Object> params = new LinkedHashMap<>();
        if (scope.actingHod()) {
            where = " WHERE (i.scope_dept = :d OR i.uploaded_by = :me)";
            params.put("d", scope.actingHodDept() == null ? "__none__" : scope.actingHodDept());
            params.put("me", me);
        } else if (scope.actingFacultyOffice()) {
            where = " WHERE (i.uploaded_by = :me OR i.scope_dept IN (SELECT code FROM ref.department WHERE faculty_code = :f))";
            params.put("f", scope.actingFaculty() == null ? "__none__" : scope.actingFaculty());
            params.put("me", me);
        }
        var q = jdbc.sql("""
                SELECT i.id, i.reference, i.file_name, i.session, i.semester, i.scope_dept, i.uploader_office, i.uploaded_at,
                       concat_ws(', ', nullif(btrim(p.surname), ''), nullif(btrim(p.given_names), '')) AS uploaded_by,
                       i.total_rows, i.valid_rows, i.imported, i.existing, i.skipped, i.errors, i.warnings, i.status
                  FROM catalogue.allocation_import i LEFT JOIN iam.person p ON p.id = i.uploaded_by
                """ + where + " ORDER BY i.uploaded_at DESC LIMIT :n").param("n", Math.max(1, Math.min(limit, 500)));
        for (var e : params.entrySet()) q = q.param(e.getKey(), e.getValue());
        return q.query().listOfRows();
    }

    @Transactional(readOnly = true)
    public Map<String, Object> one(UUID id) {
        Map<String, Object> row = history(500).stream().filter(x -> id.equals(x.get("id"))).findFirst()
                .orElseThrow(() -> new ng.edu.moaum.portal.shared.NotFound("allocation import", id));
        String findings = jdbc.sql("SELECT findings::text FROM catalogue.allocation_import WHERE id = :id").param("id", id).query(String.class).optional().orElse(null);
        Map<String, Object> out = new LinkedHashMap<>(row);
        out.put("findings", readFindings(findings));
        return out;
    }

    /** the actor, for the record */
    UUID actor() {
        return AuditContextHolder.current().map(c -> c.actorId()).orElse(null);
    }
}
