package ng.edu.moaum.portal.dbops;

import java.math.BigDecimal;
import java.sql.Types;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;

import ng.edu.moaum.portal.shared.DomainRuleViolation;

/**
 * V640: the Database Operations query engine — a query is a definition (a source, conditions, columns, a sort, a grouping), never
 * SQL. Every source, every field and its SQL expression, every operator is fixed here; the definition only names them, and is
 * refused when it names anything else. A condition's value is always a bound parameter, cast to the field's type after it has been
 * parsed in Java. The statement runs in a read-only transaction (PostgreSQL refuses any write in one), held to the acting office's
 * scope, under the API's statement timeout, a page at a time.
 *
 * <p>Definition → validated query (this class) → the authorised sources (the register, the classification, the course registration,
 * the payments, the readiness, the hostel, clearance, the GST and EPS permits, the published results) → parameterised SQL → rows.
 */
final class QueryEngine {

    enum Type { TEXT, ENUM, INT, NUM, DATE, BOOL }

    /** a field of a source: its key (the name a definition uses), label, type, SQL expression, options, and whether it is an amount */
    record Field(String key, String label, Type type, String expr, List<String> options, boolean money) {
        Field(String key, String label, Type type, String expr) {
            this(key, label, type, expr, null, false);
        }
    }

    /** a source: its SQL, the predicates that hold it to a scope, its fields, its default columns and sort, and who reads it */
    record Source(String key, String label, String note, String from, String where, String fac, String dept, String prog,
                  List<Field> fields, List<String> columns, String sort, String sortDir, boolean period, Set<String> offices, String reportKind,
                  String required) {
        Field field(String k) {
            for (Field f : fields) if (f.key().equals(k)) return f;
            return null;
        }
    }

    record Cond(String field, String op, String value, String value2, List<String> values) {
    }

    record Sort(String field, String dir) {
    }

    record Group(String field, String sum) {
    }

    record Definition(String source, String session, Integer semester, String rule, List<Cond> filters, List<String> columns, Sort sort, Group group) {
    }

    /** the statement built: the SQL and its parameters (name → value, SQL type), the columns returned with their labels */
    record Built(String sql, Map<String, Object[]> params, List<Field> columns, boolean grouped) {
    }

    static final Set<String> OPS = Set.of("eq", "ne", "in", "contains", "starts", "gt", "gte", "lt", "lte", "between", "empty", "notempty", "is");
    static final int MAX_CONDITIONS = 25;
    static final int MAX_COLUMNS = 40;

    private static final List<String> STATUSES = List.of("ADMITTED", "ACTIVE", "PROBATION", "DEFERRED", "SUSPENDED", "RUSTICATED", "DORMANT",
            "GRADUATED", "COMPLETED", "WITHDRAWN", "VOLUNTARY_WITHDRAWAL", "EXPELLED", "TRANSFERRED_OUT", "DECEASED", "PROGRESSED");
    private static final List<String> REG_STATUSES = List.of("DRAFT", "SUBMITTED", "RETURNED", "APPROVED", "LOCKED");

    /* ── the student's fields, read through the register (s), the programme (p), department (d), faculty (f), classification (sc) ── */
    private static List<Field> student(boolean full) {
        List<Field> out = new ArrayList<>(List.of(
                new Field("name", "Student name", Type.TEXT, "(s.surname || ', ' || s.other_names)"),
                new Field("matric_no", "Matric No", Type.TEXT, "s.matric_no"),
                new Field("jamb_no", "JAMB No", Type.TEXT, "s.jamb_reg_no"),
                new Field("programme_type", "Programme type", Type.ENUM, "sc.programme_type", List.of("@programme_type"), false),
                new Field("admission_route", "Admission route", Type.ENUM, "sc.admission_route", List.of("@admission_route"), false),
                new Field("faculty", "Faculty", Type.ENUM, "p.faculty_code", List.of("@faculty"), false),
                new Field("faculty_name", "Faculty name", Type.TEXT, "f.name"),
                new Field("department", "Department", Type.ENUM, "p.dept_code", List.of("@department"), false),
                new Field("department_name", "Department name", Type.TEXT, "d.name"),
                new Field("programme", "Programme", Type.ENUM, "s.programme_code", List.of("@programme"), false),
                new Field("programme_name", "Programme name", Type.TEXT, "p.name"),
                new Field("level", "Level", Type.INT, "s.current_level"),
                new Field("status", "Status", Type.ENUM, "s.status", STATUSES, false)));
        if (full) {
            out.addAll(List.of(
                    new Field("admission_no", "Admission No", Type.TEXT, "s.admission_no"),
                    new Field("sex", "Sex", Type.ENUM, "s.sex", List.of("M", "F"), false),
                    new Field("study_mode", "Study mode", Type.ENUM, "sc.study_mode", List.of("@study_mode"), false),
                    new Field("centre", "Centre", Type.ENUM, "sc.centre_code", List.of("@centre"), false),
                    new Field("entry_session", "Entry session", Type.TEXT, "s.entry_session"),
                    new Field("entry_year", "Entry year", Type.INT, "CASE WHEN s.entry_session ~ '^[0-9]{4}' THEN left(s.entry_session, 4)::int END"),
                    new Field("entry_level", "Entry level", Type.INT, "s.entry_level"),
                    new Field("academic_status", "Academic status", Type.TEXT,
                            "CASE WHEN ap.spillover_state ~ '^SPILLOVER_YEAR_[0-9]+$' THEN 'SP' || substr(ap.spillover_state, 16) "
                                    + "WHEN ap.spillover_state = 'SPILLOVER_LIMIT_REACHED' THEN 'BEYOND_MAXIMUM' ELSE s.status END"),
                    new Field("classification_status", "Classification", Type.ENUM, "sc.classification_status",
                            List.of("CLASSIFIED", "REQUIRES_CLASSIFICATION"), false),
                    new Field("matriculated", "Matriculated", Type.BOOL, "(s.matriculated_at IS NOT NULL)"),
                    new Field("matriculated_on", "Matriculated on", Type.DATE, "(s.matriculated_at AT TIME ZONE 'Africa/Lagos')::date"),
                    new Field("email", "E-mail", Type.TEXT, "c.email"),
                    new Field("phone", "Phone", Type.TEXT, "c.phone")));
        }
        return out;
    }

    private static final String STUDENT_FROM = """
            people.student s
              JOIN ref.programme p ON p.code = s.programme_code
              LEFT JOIN ref.department d ON d.code = p.dept_code
              LEFT JOIN ref.faculty f ON f.code = p.faculty_code
              LEFT JOIN people.student_classification sc ON sc.student_id = s.id
            """;

    private static List<Field> concat(List<Field> a, List<Field> b) {
        List<Field> out = new ArrayList<>(a);
        out.addAll(b);
        return out;
    }

    static final Set<String> READERS_ALL = Set.of("dbops", "ict", "registrar", "dregistrar", "academic", "records", "admin", "super");
    /** individual payments: the offices that open transactions (AnalyticsScope.MONEY) among the query engine's readers */
    static final Set<String> MONEY_READERS = Set.of("dbops", "registrar", "dregistrar", "admin", "super");
    static final Set<String> RESULT_READERS = Set.of("dbops", "registrar", "dregistrar", "academic", "records", "ict", "admin", "super");

    static final Map<String, Source> SOURCES = new LinkedHashMap<>();

    static {
        List<String> stuCols = List.of("name", "matric_no", "jamb_no", "programme_type", "admission_route", "faculty_name", "department_name",
                "programme_name", "level", "status");
        SOURCES.put("STUDENTS", new Source("STUDENTS", "Students", "Every student on the register, classified once by the classification engine.",
                STUDENT_FROM + " LEFT JOIN people.academic_position ap ON ap.student_id = s.id LEFT JOIN people.student_contact c ON c.student_id = s.id",
                "s.duplicate_of IS NULL", "p.faculty_code", "p.dept_code", "p.code", student(true), stuCols, "name", "asc", false, READERS_ALL, "STUDENT", null));

        List<Field> regFields = concat(student(false), List.of(
                new Field("session", "Session", Type.TEXT, "r.session", List.of("@session"), false),
                new Field("semester", "Semester", Type.INT, "r.semester", List.of("1", "2", "3"), false),
                new Field("reg_level", "Registration level", Type.INT, "r.level"),
                new Field("reg_status", "Registration status", Type.ENUM, "r.status", REG_STATUSES, false),
                new Field("approval_mode", "Approved by", Type.ENUM, "r.approval_mode", List.of("HOD", "AUTO"), false),
                new Field("submitted_on", "Submitted on", Type.DATE, "(r.submitted_at AT TIME ZONE 'Africa/Lagos')::date"),
                new Field("approved_on", "Approved on", Type.DATE, "(r.approved_at AT TIME ZONE 'Africa/Lagos')::date"),
                new Field("courses", "Courses", Type.INT, "x.courses"),
                new Field("units", "Total CU", Type.INT, "x.units"),
                new Field("carryovers", "Carry-overs", Type.INT, "x.carryovers")));
        SOURCES.put("REGISTRATIONS", new Source("REGISTRATIONS", "Course registrations", "Each student's course registration of a session and semester, as the registration engine holds it.",
                "registration.course_registration r JOIN (" + STUDENT_FROM + ") ON s.id = r.student_id " + """
                  LEFT JOIN LATERAL (SELECT count(*) FILTER (WHERE e.status NOT IN ('DROPPED', 'WITHDRAWN'))::int AS courses,
                                            coalesce(sum(e.units) FILTER (WHERE e.status NOT IN ('DROPPED', 'WITHDRAWN')), 0)::int AS units,
                                            count(*) FILTER (WHERE e.status NOT IN ('DROPPED', 'WITHDRAWN') AND e.entry_type = 'CARRYOVER')::int AS carryovers
                                       FROM registration.entry e WHERE e.registration_id = r.id) x ON true
                """,
                "s.duplicate_of IS NULL", "p.faculty_code", "p.dept_code", "p.code", regFields,
                List.of("name", "matric_no", "programme_name", "level", "session", "semester", "reg_status", "courses", "units"), "name", "asc", false,
                READERS_ALL, "REG", null));

        List<Field> entryFields = concat(student(false), List.of(
                new Field("session", "Session", Type.TEXT, "r.session", List.of("@session"), false),
                new Field("semester", "Semester", Type.INT, "r.semester", List.of("1", "2", "3"), false),
                new Field("reg_status", "Registration status", Type.ENUM, "r.status", REG_STATUSES, false),
                new Field("course_code", "Course code", Type.TEXT, "o.course_code"),
                new Field("course_title", "Course title", Type.TEXT, "cr.title"),
                new Field("course_units", "Credit units", Type.INT, "e.units"),
                new Field("course_department", "Course department", Type.ENUM, "cr.dept_code", List.of("@department"), false),
                new Field("course_level", "Course level", Type.INT, "cr.level"),
                new Field("entry_type", "Registered as", Type.ENUM, "e.entry_type", List.of("CURRENT", "CARRYOVER", "REPEAT", "ELECTIVE", "GST", "BORROWED", "DEFERRED"), false),
                new Field("entry_status", "Course status", Type.ENUM, "e.status", List.of("REGISTERED", "APPROVED", "DEFERRED", "DROPPED", "WITHDRAWN"), false)));
        SOURCES.put("COURSE_REGISTRATIONS", new Source("COURSE_REGISTRATIONS", "Courses registered", "Each course on each student's registration.",
                "registration.entry e JOIN registration.course_registration r ON r.id = e.registration_id JOIN catalogue.offering o ON o.id = e.offering_id "
                        + "JOIN catalogue.course cr ON cr.code = o.course_code JOIN (" + STUDENT_FROM + ") ON s.id = r.student_id",
                "s.duplicate_of IS NULL", "p.faculty_code", "p.dept_code", "p.code", entryFields,
                List.of("name", "matric_no", "programme_name", "level", "session", "semester", "course_code", "course_title", "course_units", "entry_type", "reg_status"),
                "name", "asc", false, READERS_ALL, "REG", null));

        List<Field> payFields = List.of(
                new Field("name", "Student name", Type.TEXT, "(x.surname || ', ' || x.other_names)"),
                new Field("number", "Matric/Admission No", Type.TEXT, "x.number"),
                new Field("jamb_no", "JAMB No", Type.TEXT, "x.jamb_reg_no"),
                new Field("programme_type", "Programme type", Type.ENUM, "x.programme_type", List.of("@programme_type"), false),
                new Field("faculty", "Faculty", Type.ENUM, "x.faculty_code", List.of("@faculty"), false),
                new Field("faculty_name", "Faculty name", Type.TEXT, "x.faculty"),
                new Field("department", "Department", Type.ENUM, "x.dept_code", List.of("@department"), false),
                new Field("department_name", "Department name", Type.TEXT, "x.department"),
                new Field("programme", "Programme", Type.ENUM, "x.programme_code", List.of("@programme"), false),
                new Field("programme_name", "Programme name", Type.TEXT, "x.programme"),
                new Field("level", "Level", Type.INT, "x.level"),
                new Field("session", "Payment session", Type.TEXT, "x.session", List.of("@session"), false),
                new Field("semester", "Payment semester", Type.INT, "x.semester", List.of("1", "2"), false),
                new Field("purpose_code", "Payment type", Type.ENUM, "x.purpose_code",
                        List.of("SCHOOL_FEES", "ACCEPTANCE", "GST", "HOSTEL", "TRANSCRIPT", "OTHER"), false),
                new Field("purpose", "Purpose", Type.TEXT, "x.purpose"),
                new Field("reference", "Payment reference", Type.TEXT, "x.reference"),
                new Field("receipt_no", "Receipt No", Type.TEXT, "x.receipt_no"),
                new Field("amount", "Amount", Type.NUM, "x.amount", null, true),
                new Field("channel", "Channel", Type.TEXT, "x.channel"),
                new Field("payment_status", "Payment status", Type.ENUM, "x.ledger_status", List.of("PAID", "PENDING", "EXPIRED"), false),
                new Field("generated_on", "Generated on", Type.DATE, "(x.generated_at AT TIME ZONE 'Africa/Lagos')::date"),
                new Field("paid_on", "Payment date", Type.DATE, "(x.confirmed_at AT TIME ZONE 'Africa/Lagos')::date"));
        SOURCES.put("PAYMENTS", new Source("PAYMENTS", "Payments", "Every student payment reference and its confirmation, as the central finance records them; paid means confirmed, never a pending or expired reference.",
                "reporting.payments x", "x.student_id IS NOT NULL", "x.faculty_code", "x.dept_code", "x.programme_code", payFields,
                List.of("name", "number", "programme_name", "level", "session", "purpose", "reference", "amount", "channel", "payment_status", "paid_on"),
                "paid_on", "desc", false, MONEY_READERS, "PAYMENT", null));

        List<Field> readyFields = List.of(
                new Field("name", "Student name", Type.TEXT, "(r.surname || ', ' || r.other_names)"),
                new Field("matric_no", "Matric No", Type.TEXT, "r.matric_no"),
                new Field("jamb_no", "JAMB No", Type.TEXT, "r.jamb_no"),
                new Field("programme_type", "Programme type", Type.ENUM, "r.programme_type", List.of("@programme_type"), false),
                new Field("admission_route", "Admission route", Type.ENUM, "r.admission_route", List.of("@admission_route"), false),
                new Field("faculty", "Faculty", Type.ENUM, "r.faculty_code", List.of("@faculty"), false),
                new Field("faculty_name", "Faculty name", Type.TEXT, "r.faculty"),
                new Field("department", "Department", Type.ENUM, "r.dept_code", List.of("@department"), false),
                new Field("department_name", "Department name", Type.TEXT, "r.department"),
                new Field("programme", "Programme", Type.ENUM, "r.programme_code", List.of("@programme"), false),
                new Field("programme_name", "Programme name", Type.TEXT, "r.programme"),
                new Field("level", "Level", Type.INT, "r.level"),
                new Field("status", "Status", Type.ENUM, "r.status", STATUSES, false),
                new Field("academic_status", "Academic status", Type.TEXT, "r.academic_status"),
                new Field("fee_status", "Fee status", Type.ENUM, "r.fee_status", List.of("FULLY_PAID", "PART_PAYMENT", "NOT_PAID", "NO_CHARGE"), false),
                new Field("payable", "Amount required", Type.NUM, "r.payable", null, true),
                new Field("paid_amount", "Amount paid", Type.NUM, "r.paid_amount", null, true),
                new Field("outstanding", "Outstanding", Type.NUM, "r.outstanding", null, true),
                new Field("school_fees_paid", "School fees paid (card rule)", Type.BOOL, "r.school_fees_paid"),
                new Field("fully_paid", "Paid in full", Type.BOOL, "r.fully_paid"),
                new Field("registration_stream", "Register", Type.ENUM, "r.registration_stream", List.of("UNIVERSITY", "COLLEGE", "POSTGRADUATE"), false),
                new Field("registration_status", "Registration status", Type.ENUM, "r.registration_status",
                        List.of("NONE", "DRAFT", "SUBMITTED", "RETURNED", "APPROVED", "LOCKED", "ENDORSED", "REGISTERED", "OPEN"), false),
                new Field("courses", "Courses registered", Type.INT, "r.courses"),
                new Field("units", "Total CU", Type.INT, "r.units"),
                new Field("carryovers", "Carry-overs", Type.INT, "r.carryovers"),
                new Field("registered", "Registered", Type.BOOL, "r.registered"),
                new Field("exam_card", "Examination card", Type.BOOL, "r.exam_card"),
                new Field("readiness", "Readiness", Type.ENUM, "r.readiness", List.of("PAID_REGISTERED", "PAID_NOT_REGISTERED", "NOT_PAID", "NO_FEE_STATED"), false),
                new Field("exception", "Exception", Type.ENUM, "r.exception", List.of("REGISTRATION_NOT_SUBMITTED", "REGISTRATION_RETURNED",
                        "REGISTRATION_WITHOUT_COURSES", "REGISTERED_NOT_PAID", "REGISTERED_NO_FEE_STATED", "FEES_SETTLED_NO_SCHOOL_FEES_PAYMENT",
                        "REGISTRATION_AWAITING_APPROVAL", "PART_PAYMENT"), false));
        SOURCES.put("EXAM_READINESS", new Source("EXAM_READINESS", "Examination readiness", "Each student of a session and semester: paid, registered, the examination card.",
                "reporting.exam_readiness(CAST(:qs AS text), CAST(:qsem AS int), CAST(:qbf AS text), CAST(:qbd AS text), CAST(:qbp AS text), NULL, NULL, NULL, CAST(:qrule AS text)) r",
                "true", "r.faculty_code", "r.dept_code", "r.programme_code", readyFields,
                List.of("name", "matric_no", "faculty_name", "department_name", "programme_name", "level", "fee_status", "registration_status", "courses", "units", "readiness"),
                "name", "asc", true, READERS_ALL, "EXAM", null));

        List<Field> hostelFields = concat(student(false), List.of(
                new Field("session", "Session", Type.TEXT, "a.session", List.of("@session"), false),
                new Field("allocation_state", "Allocation state", Type.TEXT, "a.state"),
                new Field("hall", "Hall", Type.TEXT, "h.name"),
                new Field("room", "Room", Type.TEXT, "rm.room_no"),
                new Field("bed", "Bed", Type.INT, "a.bed"),
                new Field("category", "Category", Type.TEXT, "a.category"),
                new Field("hostel_fee_status", "Hostel fee", Type.TEXT, "a.fee_status"),
                new Field("allocation_no", "Allocation No", Type.TEXT, "a.reference_no"),
                new Field("allocated_on", "Allocated on", Type.DATE, "(a.allocated_at AT TIME ZONE 'Africa/Lagos')::date"),
                new Field("checked_in_on", "Checked in on", Type.DATE, "(a.checked_in_at AT TIME ZONE 'Africa/Lagos')::date")));
        SOURCES.put("HOSTEL", new Source("HOSTEL", "Hostel allocations", "Each student's hostel allocation.",
                "hostel.allocation a JOIN (" + STUDENT_FROM + ") ON s.id = a.student_id LEFT JOIN hostel.room rm ON rm.id = a.room_id LEFT JOIN hostel.hall h ON h.code = rm.hall_code",
                "s.duplicate_of IS NULL", "p.faculty_code", "p.dept_code", "p.code", hostelFields,
                List.of("name", "matric_no", "programme_name", "level", "session", "hall", "room", "bed", "allocation_state", "hostel_fee_status"),
                "name", "asc", false, READERS_ALL, "QUERY", null));

        List<Field> clearFields = concat(student(false), List.of(
                new Field("workflow", "Clearance", Type.ENUM, "q.workflow", List.of("FINAL", "STUDENT_ID", "TRANSFER", "WITHDRAWAL", "HOSTEL", "NYSC"), false),
                new Field("clearance_reference", "Clearance reference", Type.TEXT, "q.reference"),
                new Field("session", "Session", Type.TEXT, "q.session", List.of("@session"), false),
                new Field("clearance_state", "Clearance state", Type.ENUM,
                        "CASE WHEN q.cancelled_at IS NOT NULL THEN 'CANCELLED' WHEN q.completed_at IS NOT NULL THEN 'COMPLETED' ELSE 'UNDER_WAY' END",
                        List.of("UNDER_WAY", "COMPLETED", "CANCELLED"), false),
                new Field("started_on", "Started on", Type.DATE, "(q.started_at AT TIME ZONE 'Africa/Lagos')::date"),
                new Field("completed_on", "Completed on", Type.DATE, "(q.completed_at AT TIME ZONE 'Africa/Lagos')::date")));
        SOURCES.put("CLEARANCE", new Source("CLEARANCE", "Clearance", "Each clearance process of each student and where it stands.",
                "clearance.process q JOIN (" + STUDENT_FROM + ") ON s.id = q.student_id", "s.duplicate_of IS NULL", "p.faculty_code", "p.dept_code", "p.code",
                clearFields, List.of("name", "matric_no", "programme_name", "level", "workflow", "clearance_reference", "session", "clearance_state", "started_on", "completed_on"),
                "name", "asc", false, READERS_ALL, "QUERY", null));

        List<Field> gstFields = concat(student(false), List.of(
                new Field("permit_reference", "Permit reference", Type.TEXT, "g.reference"),
                new Field("session", "Session", Type.TEXT, "g.session", List.of("@session"), false),
                new Field("semester", "Semester", Type.INT, "g.semester", List.of("1", "2"), false),
                new Field("generated_on", "Issued on", Type.DATE, "(g.generated_at AT TIME ZONE 'Africa/Lagos')::date"),
                new Field("permit_courses", "Courses on the permit", Type.INT, "CASE WHEN jsonb_typeof(g.courses) = 'array' THEN jsonb_array_length(g.courses) END"),
                new Field("downloaded", "Downloads", Type.INT, "g.downloaded"),
                new Field("revoked", "Revoked", Type.BOOL, "(g.revoked_at IS NOT NULL)")));
        SOURCES.put("GST_EPS", new Source("GST_EPS", "GST and EPS permits", "Each GST and EPS examination permit issued.",
                "registration.gst_eps_permit g JOIN (" + STUDENT_FROM + ") ON s.id = g.student_id", "s.duplicate_of IS NULL", "p.faculty_code", "p.dept_code", "p.code",
                gstFields, List.of("name", "matric_no", "programme_name", "level", "permit_reference", "session", "semester", "permit_courses", "revoked"),
                "name", "asc", false, READERS_ALL, "QUERY", null));

        List<Field> resultFields = concat(student(false), List.of(
                new Field("session", "Session", Type.TEXT, "rs.session", List.of("@session"), false),
                new Field("semester", "Semester", Type.INT, "rs.semester", List.of("1", "2", "3"), false),
                new Field("course_code", "Course code", Type.TEXT, "rs.course_code"),
                new Field("course_title", "Course title", Type.TEXT, "rs.title"),
                new Field("units", "Credit units", Type.INT, "rs.units"),
                new Field("registered_as", "Registered as", Type.TEXT, "rs.entry_type"),
                new Field("total", "Total", Type.INT, "rs.total"),
                new Field("grade", "Grade", Type.ENUM, "rs.grade", List.of("A", "B", "C", "D", "E", "F"), false),
                new Field("points", "Grade points", Type.NUM, "rs.points"),
                new Field("outcome", "Outcome", Type.TEXT, "rs.outcome"),
                new Field("published_on", "Published on", Type.DATE, "(rs.published_at AT TIME ZONE 'Africa/Lagos')::date")));
        SOURCES.put("RESULTS", new Source("RESULTS", "Published results", "Each published result of each student, as the result system holds it; ask by programme, department and level, or a student.",
                STUDENT_FROM + " CROSS JOIN LATERAL assessment.student_results(s.id) rs", "s.duplicate_of IS NULL AND rs.published", "p.faculty_code", "p.dept_code", "p.code",
                resultFields, List.of("name", "matric_no", "programme_name", "level", "session", "semester", "course_code", "course_title", "units", "total", "grade"),
                "name", "asc", false, RESULT_READERS, "QUERY", "programme|matric_no|jamb_no|name|department+level"));
    }

    private static DomainRuleViolation refused(String code, String message) {
        return new DomainRuleViolation(code, message, new DomainRuleViolation.Remedy("Choose from what the query builder offers.", "You"));
    }

    static Source source(String key, String office) {
        Source s = key == null ? null : SOURCES.get(key.trim().toUpperCase());
        if (s == null) throw refused("QUERY_SOURCE", "There is no data source " + key + ".");
        if (!s.offices().contains(office)) {
            throw new DomainRuleViolation("QUERY_SOURCE_OFFICE", "Your office does not read " + s.label().toLowerCase() + ".",
                    new DomainRuleViolation.Remedy("Ask the Database Operations office for this report.", "Database Operations"));
        }
        return s;
    }

    /** a value parsed in Java for its type before it is bound — a value that does not parse is refused, never sent */
    private static Object parse(Field f, String raw) {
        if (raw == null) throw refused("QUERY_VALUE", "Give a value for " + f.label() + ".");
        String v = raw.trim();
        if (v.length() > 200) throw refused("QUERY_VALUE", "The value for " + f.label() + " is too long.");
        try {
            return switch (f.type()) {
                case INT -> Integer.valueOf(v);
                case NUM -> new BigDecimal(v);
                case DATE -> LocalDate.parse(v);
                case BOOL -> {
                    if (!v.equalsIgnoreCase("true") && !v.equalsIgnoreCase("false")) throw new IllegalArgumentException();
                    yield Boolean.valueOf(v);
                }
                default -> v;
            };
        } catch (RuntimeException e) {
            throw refused("QUERY_VALUE", "\"" + v + "\" is not a " + switch (f.type()) {
                case INT -> "whole number";
                case NUM -> "number";
                case DATE -> "date (YYYY-MM-DD)";
                case BOOL -> "yes or no";
                default -> "value";
            } + " for " + f.label() + ".");
        }
    }

    private static int sqlType(Type t) {
        return switch (t) {
            case INT -> Types.INTEGER;
            case NUM -> Types.NUMERIC;
            case DATE -> Types.DATE;
            case BOOL -> Types.BOOLEAN;
            default -> Types.VARCHAR;
        };
    }

    private static String cast(Type t) {
        return switch (t) {
            case INT -> "int";
            case NUM -> "numeric";
            case DATE -> "date";
            case BOOL -> "boolean";
            default -> "text";
        };
    }

    private static String like(String v) {
        return v.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_");
    }

    /**
     * The statement for a definition: the source's SQL, its scope predicates (the bound the caller passes, from the server's own
     * record of the office), the conditions as bound parameters, the columns and the sort from the source's own fields; a page,
     * or the grouping's counts. Amount fields are left out for an office that does not read amounts.
     */
    static Built build(Definition def, String office, boolean amounts, String[] bound, int limit, int offset) {
        Source src = source(def.source(), office);
        Map<String, Object[]> params = new LinkedHashMap<>();
        params.put("qbf", new Object[] {bound[0], Types.VARCHAR});
        params.put("qbd", new Object[] {bound[1], Types.VARCHAR});
        params.put("qbp", new Object[] {bound[2], Types.VARCHAR});
        StringBuilder where = new StringBuilder(src.where());
        where.append(" AND (CAST(:qbf AS text) IS NULL OR ").append(src.fac()).append(" = CAST(:qbf AS text))");
        where.append(" AND (CAST(:qbd AS text) IS NULL OR ").append(src.dept()).append(" = CAST(:qbd AS text))");
        where.append(" AND (CAST(:qbp AS text) IS NULL OR ").append(src.prog()).append(" = CAST(:qbp AS text))");
        if (src.period()) {
            String session = def.session() != null && def.session().matches("[0-9]{4}/[0-9]{4}") ? def.session() : null;
            if (session == null) throw refused("QUERY_PERIOD", "Choose the session the report is for.");
            int sem = def.semester() == null ? 0 : def.semester();
            if (sem < 1 || sem > 3) throw refused("QUERY_PERIOD", "Choose the semester the report is for.");
            params.put("qs", new Object[] {session, Types.VARCHAR});
            params.put("qsem", new Object[] {sem, Types.INTEGER});
            params.put("qrule", new Object[] {"FULL".equalsIgnoreCase(def.rule()) ? "FULL" : "CARD", Types.VARCHAR});
        }
        List<Cond> conds = def.filters() == null ? List.of() : def.filters();
        if (conds.size() > MAX_CONDITIONS) throw refused("QUERY_SIZE", "At most " + MAX_CONDITIONS + " conditions.");
        int n = 0;
        java.util.Set<String> asked = new java.util.HashSet<>();
        for (Cond c : conds) {
            Field f = c == null ? null : src.field(c.field());
            if (f == null) throw refused("QUERY_FIELD", (src.label() + " has no field " + (c == null ? "" : c.field())).trim() + ".");
            if (f.money() && !amounts) throw refused("QUERY_FIELD", "Your office does not read amounts.");
            String op = c.op() == null ? "eq" : c.op().trim().toLowerCase();
            if (!OPS.contains(op)) throw refused("QUERY_OPERATOR", "There is no operator " + op + ".");
            String e = f.expr();
            String p = "q" + n++;
            switch (op) {
                case "empty" -> where.append(" AND (").append(e).append(" IS NULL OR ").append(e).append("::text = '')");
                case "notempty" -> where.append(" AND (").append(e).append(" IS NOT NULL AND ").append(e).append("::text <> '')");
                case "contains", "starts" -> {
                    if (f.type() != Type.TEXT && f.type() != Type.ENUM) throw refused("QUERY_OPERATOR", f.label() + " is not text.");
                    String v = String.valueOf(parse(f, c.value()));
                    params.put(p, new Object[] {("contains".equals(op) ? "%" : "") + like(v) + "%", Types.VARCHAR});
                    where.append(" AND ").append(e).append(" ILIKE CAST(:").append(p).append(" AS text)");
                }
                case "in" -> {
                    List<String> vals = c.values() == null ? List.of() : c.values();
                    if (vals.isEmpty() || vals.size() > 500) throw refused("QUERY_VALUE", "Choose between one and 500 values for " + f.label() + ".");
                    String[] arr = vals.stream().map(v -> String.valueOf(parse(f, v))).toArray(String[]::new);
                    params.put(p, new Object[] {arr, Types.ARRAY});
                    where.append(" AND ").append(e).append("::text = ANY (CAST(:").append(p).append(" AS text[]))");
                }
                case "between" -> {
                    if (f.type() == Type.TEXT || f.type() == Type.ENUM || f.type() == Type.BOOL) throw refused("QUERY_OPERATOR", f.label() + " is not a number or a date.");
                    params.put(p, new Object[] {parse(f, c.value()), sqlType(f.type())});
                    params.put(p + "b", new Object[] {parse(f, c.value2()), sqlType(f.type())});
                    where.append(" AND ").append(e).append(" BETWEEN CAST(:").append(p).append(" AS ").append(cast(f.type())).append(") AND CAST(:")
                            .append(p).append("b AS ").append(cast(f.type())).append(")");
                }
                case "gt", "gte", "lt", "lte" -> {
                    if (f.type() == Type.TEXT || f.type() == Type.ENUM || f.type() == Type.BOOL) throw refused("QUERY_OPERATOR", f.label() + " is not a number or a date.");
                    params.put(p, new Object[] {parse(f, c.value()), sqlType(f.type())});
                    String sym = switch (op) { case "gt" -> ">"; case "gte" -> ">="; case "lt" -> "<"; default -> "<="; };
                    where.append(" AND ").append(e).append(' ').append(sym).append(" CAST(:").append(p).append(" AS ").append(cast(f.type())).append(")");
                }
                case "ne" -> {
                    params.put(p, new Object[] {parse(f, c.value()), sqlType(f.type())});
                    where.append(" AND ").append(e).append(" IS DISTINCT FROM CAST(:").append(p).append(" AS ").append(cast(f.type())).append(")");
                }
                default -> {
                    // eq, is
                    Object v = parse(f, c.value());
                    params.put(p, new Object[] {v, sqlType(f.type())});
                    if (f.type() == Type.TEXT) {
                        where.append(" AND lower(").append(e).append(") = lower(CAST(:").append(p).append(" AS text))");
                    } else {
                        where.append(" AND ").append(e).append(" = CAST(:").append(p).append(" AS ").append(cast(f.type())).append(")");
                    }
                }
            }
            if (!"empty".equals(op) && !"notempty".equals(op) && !"ne".equals(op)) asked.add(f.key());
        }
        if (src.required() != null) {
            boolean ok = false;
            for (String alt : src.required().split("\\|")) {
                boolean all = true;
                for (String k : alt.split("\\+")) all &= asked.contains(k);
                ok |= all;
            }
            if (!ok) {
                throw new DomainRuleViolation("QUERY_NARROW", src.label() + " are read for a programme, a department and level, or a student.",
                        new DomainRuleViolation.Remedy("Add a condition on the programme, the department and the level, or the student.", "You"));
            }
        }

        if (def.group() != null && def.group().field() != null && !def.group().field().isBlank()) {
            Field g = src.field(def.group().field());
            if (g == null || g.money()) throw refused("QUERY_FIELD", "There is no field " + def.group().field() + " to group by.");
            Field sum = def.group().sum() == null || def.group().sum().isBlank() ? null : src.field(def.group().sum());
            if (sum != null && (sum.type() != Type.NUM && sum.type() != Type.INT)) throw refused("QUERY_FIELD", sum.label() + " is not a number to add up.");
            if (sum != null && sum.money() && !amounts) throw refused("QUERY_FIELD", "Your office does not read amounts.");
            String sql = "SELECT " + g.expr() + " AS \"key\", count(*) AS \"count\"" + (sum == null ? "" : ", sum(" + sum.expr() + ") AS \"sum\"")
                    + " FROM " + src.from() + " WHERE " + where + " GROUP BY 1 ORDER BY 2 DESC, 1 LIMIT 2000";
            List<Field> cols = new ArrayList<>(List.of(new Field("key", g.label(), g.type(), g.expr()), new Field("count", "Number", Type.INT, "")));
            if (sum != null) cols.add(new Field("sum", "Total " + sum.label().toLowerCase(), sum.type(), "", null, sum.money()));
            return new Built(sql, params, cols, true);
        }

        List<String> want = def.columns() == null || def.columns().isEmpty() ? src.columns() : def.columns();
        if (want.size() > MAX_COLUMNS) throw refused("QUERY_SIZE", "At most " + MAX_COLUMNS + " columns.");
        List<Field> cols = new ArrayList<>();
        StringBuilder select = new StringBuilder();
        for (String k : want) {
            Field f = src.field(k);
            if (f == null) throw refused("QUERY_FIELD", src.label() + " has no column " + k + ".");
            if (f.money() && !amounts) continue;
            if (cols.contains(f)) continue;
            cols.add(f);
            select.append(f.expr()).append(" AS \"").append(f.key()).append("\", ");
        }
        if (cols.isEmpty()) throw refused("QUERY_FIELD", "Choose a column.");
        Field sortField = def.sort() == null || def.sort().field() == null ? src.field(src.sort()) : src.field(def.sort().field());
        if (sortField == null || (sortField.money() && !amounts)) throw refused("QUERY_FIELD", "There is no field to sort by " + (def.sort() == null ? "" : def.sort().field()) + ".");
        String dir = def.sort() == null || def.sort().dir() == null ? src.sortDir() : "desc".equalsIgnoreCase(def.sort().dir()) ? "desc" : "asc";
        // the person's name breaks a tie, A to Z, then the source's own order, so a page never shuffles
        Field name = src.field("name");
        String order = sortField.expr() + " " + dir + " NULLS LAST" + (name != null && name != sortField ? ", " + name.expr() + " asc" : "");
        params.put("qlimit", new Object[] {limit, Types.INTEGER});
        params.put("qoffset", new Object[] {offset, Types.INTEGER});
        String sql = "SELECT " + select + "count(*) OVER () AS \"__total\" FROM " + src.from() + " WHERE " + where
                + " ORDER BY " + order + " LIMIT CAST(:qlimit AS int) OFFSET CAST(:qoffset AS int)";
        return new Built(sql, params, cols, false);
    }

    /** what the query builder offers an office: its sources, each with its fields (amounts left out where they are not read) */
    static List<Map<String, Object>> describe(String office, boolean amounts) {
        List<Map<String, Object>> out = new ArrayList<>();
        for (Source s : SOURCES.values()) {
            if (!s.offices().contains(office)) continue;
            List<Map<String, Object>> fields = new ArrayList<>();
            for (Field f : s.fields()) {
                if (f.money() && !amounts) continue;
                Map<String, Object> m = new LinkedHashMap<>();
                m.put("key", f.key());
                m.put("label", f.label());
                m.put("type", f.type().name());
                if (f.options() != null) m.put("options", f.options());
                m.put("money", f.money());
                fields.add(m);
            }
            Map<String, Object> m = new LinkedHashMap<>();
            m.put("key", s.key());
            m.put("label", s.label());
            m.put("note", s.note());
            m.put("period", s.period());
            m.put("columns", s.columns().stream().filter(c -> amounts || !s.field(c).money()).toList());
            m.put("sort", s.sort());
            m.put("sortDir", s.sortDir());
            m.put("required", s.required());
            m.put("fields", fields);
            out.add(m);
        }
        return out;
    }

    private QueryEngine() {
    }
}
