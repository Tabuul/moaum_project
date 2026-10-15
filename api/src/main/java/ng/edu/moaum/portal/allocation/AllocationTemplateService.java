package ng.edu.moaum.portal.allocation;

import java.sql.Types;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

import ng.edu.moaum.portal.shared.AuditContextHolder;
import ng.edu.moaum.portal.shared.DomainRuleViolation;
import ng.edu.moaum.portal.shared.NotFound;
import ng.edu.moaum.portal.shared.OfficeScope;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * A department's course allocation template (V478), issued from the register as it stands: one department, one kind of
 * programme (undergraduate or postgraduate), one session and semester. It carries the department's classes for that
 * semester — the courses the department owns and teaches to programmes of that kind, the class in the session where one is
 * open — with whoever teaches each now, the department's lecturers to choose from, and its programmes of that kind. Each
 * template is recorded and numbered (CAT-2026-000123); an upload names it, and the import checks the file against the
 * template's own context — the department, the kind of programme, the session and semester — never against what the file
 * says, and only for an office that reaches the department: a Head of Department their own, a faculty office its faculty, an
 * ICT Support Agent where a posting carries the bulk allocation, the School of Postgraduate Studies the postgraduate
 * classes of any department, the Registry, the Academic Office and the Directorate of ICT every department.
 */
@Service
public class AllocationTemplateService {

    static final String UG = "UNDERGRADUATE";
    static final String PG = "POSTGRADUATE";
    /** the template format; a later format reads an earlier one or says it does not */
    static final int VERSION = 1;
    private static final Set<String> PG_OFFICES = Set.of("pgschool", "pgsecretary");

    /** what the file says it is, beside what the page has chosen; the reference is the template's */
    public record TemplateIn(String reference, String dept, String session, Integer semester, String programmeType,
                             String fileDept, String fileSession, Integer fileSemester, String fileProgrammeType) {
    }

    /** a template's context, checked: the department, the kind of programme, the session and semester the import holds the rows to */
    public record Context(UUID id, String reference, String dept, String deptName, String faculty, String type, String session, int semester,
                          String newer) {
        String category() {
            return PG.equals(type) ? "POST GRADUATE" : "UNDER GRADUATE";
        }

        String stream() {
            return PG.equals(type) ? "PG" : "REGULAR";
        }
    }

    private final JdbcClient jdbc;
    private final OfficeScope scope;
    private final AllocationReach reach;

    AllocationTemplateService(JdbcClient jdbc, OfficeScope scope, AllocationReach reach) {
        this.jdbc = jdbc;
        this.scope = scope;
        this.reach = reach;
    }

    static boolean pgOffice() {
        return PG_OFFICES.contains(AuditContextHolder.current().map(c -> c.actorOffice()).orElse(""));
    }

    /** the kind of programme named: postgraduate or undergraduate (the School's offices work the postgraduate only) */
    static String type(String t) {
        String v = t == null ? "" : t.trim().toUpperCase().replace('_', ' ');
        boolean pg = v.startsWith("P") || v.equals("PG");
        if (pgOffice() && !pg) {
            throw new DomainRuleViolation("ALLOC_TEMPLATE_PG_ONLY", "The School of Postgraduate Studies allocates the postgraduate classes; choose Postgraduate.",
                    new DomainRuleViolation.Remedy("An undergraduate class is allocated by its department.", "Head of Department"));
        }
        return pg ? PG : UG;
    }

    private static String clean(String s) {
        return s == null ? "" : s.trim();
    }

    /* ── who may issue and upload a department's template ── */

    private Map<String, Object> department(String dept) {
        return jdbc.sql("""
                SELECT d.code, d.name, d.faculty_code, f.name AS faculty_name FROM ref.department d LEFT JOIN ref.faculty f ON f.code = d.faculty_code
                 WHERE upper(d.code) = upper(:d) AND d.ended_on IS NULL
                """).param("d", clean(dept)).query().listOfRows().stream().findFirst().orElseThrow(() -> new NotFound("department", dept));
    }

    /** where the acting office's templates reach: every department, a Head's own, a faculty office's faculty, an agent's bulk
     *  allocation postings (the School: every department, for the postgraduate classes type() holds it to) */
    private record Bound(boolean all, String hodDept, String faculty, AllocationReach.Reach agent) {
        boolean reaches(String code, String fac) {
            if (all) return true;
            if (hodDept != null) return code.equalsIgnoreCase(hodDept);
            if (faculty != null) return fac != null && fac.equalsIgnoreCase(faculty);
            return agent != null && agent.covers(fac, code);
        }
    }

    private Bound bound() {
        if (pgOffice()) return new Bound(true, null, null, null);
        if (scope.actingHod()) return new Bound(false, String.valueOf(scope.actingHodDept()), null, null);
        if (scope.actingFacultyOffice()) return new Bound(false, null, String.valueOf(scope.actingFaculty()), null);
        if (AllocationReach.agent()) return new Bound(false, null, null, reach.of(AllocationReach.BULK));
        return new Bound(true, null, null, null);
    }

    /** the department, when the acting office reaches it; refused (403) otherwise, whatever the page or the file asked for */
    Map<String, Object> reachable(String dept) {
        Map<String, Object> d = department(dept);
        if (AllocationReach.agent()) reach.require(AllocationReach.BULK);   // no posting carries the bulk allocation: said so, by name
        if (!bound().reaches((String) d.get("code"), (String) d.get("faculty_code"))) {
            throw new AccessDeniedException("The " + d.get("name") + " course allocation template is outside your allocation scope.");
        }
        return d;
    }

    private Map<String, Object> session(String session) {
        return jdbc.sql("SELECT name, coalesce(semesters, 2) AS semesters, state FROM policy.academic_session WHERE name = :s").param("s", clean(session))
                .query().listOfRows().stream().findFirst().orElseThrow(() -> new NotFound("academic session", session));
    }

    private static int semester(Map<String, Object> session, Integer semester) {
        int n = ((Number) session.get("semesters")).intValue();
        if (semester == null || semester < 1 || semester > n) {
            throw new DomainRuleViolation("ALLOC_TEMPLATE_SEMESTER", "Session " + session.get("name") + " has " + n + " semesters; choose one of them.",
                    new DomainRuleViolation.Remedy("Choose the first or the second semester.", "You"));
        }
        return semester;
    }

    /** the faculties and departments the acting office may issue templates for, the sessions, and the kinds of programme */
    @Transactional(readOnly = true)
    public Map<String, Object> options() {
        List<Map<String, Object>> depts = jdbc.sql("""
                SELECT d.code, d.name, d.faculty_code FROM ref.department d WHERE d.ended_on IS NULL ORDER BY d.name
                """).query().listOfRows();
        Bound b = bound();
        List<Map<String, Object>> reachable = depts.stream().filter(d -> b.reaches((String) d.get("code"), (String) d.get("faculty_code"))).toList();
        Set<String> facs = new java.util.HashSet<>();
        for (Map<String, Object> d : reachable) if (d.get("faculty_code") != null) facs.add(String.valueOf(d.get("faculty_code")));
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("faculties", jdbc.sql("SELECT code, name FROM ref.faculty ORDER BY name").query().listOfRows().stream().filter(f -> facs.contains(String.valueOf(f.get("code")))).toList());
        out.put("departments", reachable);
        out.put("sessions", jdbc.sql("SELECT name, state, coalesce(semesters, 2) AS semesters FROM policy.academic_session WHERE state <> 'CANCELLED' ORDER BY starts_on DESC").query().listOfRows());
        out.put("current", jdbc.sql("SELECT policy.university_current_session()").query(String.class).optional().orElse(null));
        out.put("types", pgOffice() ? List.of(PG) : List.of(UG, PG));
        return out;
    }

    /* ── what a template carries ── */

    /** the department's classes of the kind, session and semester; its lecturers and programmes of that kind; the counts */
    @Transactional(readOnly = true)
    public Map<String, Object> data(String dept, String programmeType, String sessionName, Integer semesterNo) {
        String type = type(programmeType);
        Map<String, Object> d = reachable(dept);
        Map<String, Object> sess = session(sessionName);
        int semester = semester(sess, semesterNo);
        String code = (String) d.get("code");
        String category = PG.equals(type) ? "POST GRADUATE" : "UNDER GRADUATE";
        String stream = PG.equals(type) ? "PG" : "REGULAR";
        String session = (String) sess.get("name");

        List<Map<String, Object>> programmes = jdbc.sql("""
                SELECT p.code, p.name, p.category, p.pg_award, d.code AS dept_code, d.name AS dept_name, f.name AS faculty_name, coalesce(p.archived, false) AS archived
                  FROM ref.programme p JOIN ref.department d ON d.code = p.dept_code LEFT JOIN ref.faculty f ON f.code = d.faculty_code
                 WHERE p.dept_code = :d AND p.category = :cat AND NOT coalesce(p.archived, false)
                 ORDER BY p.name
                """).param("d", code).param("cat", category).query().listOfRows();

        // the department's lecturers: a live lecturer's or Head's office over it, or it as their home department on the staff record
        List<Map<String, Object>> lecturers = jdbc.sql("""
                WITH mine AS (
                    SELECT a.person_id FROM iam.office_assignment a
                     WHERE a.office_code IN ('lecturer', 'hod') AND a.scope_kind = 'department' AND upper(btrim(a.scope_id)) = :d
                       AND a.valid_from <= current_date AND (a.valid_to IS NULL OR a.valid_to >= current_date)
                    UNION
                    SELECT h.person_id FROM hrm.staff_record h WHERE upper(btrim(h.home_department)) IN (:d, upper(:dn)))
                SELECT p.id, p.staff_number, concat_ws(', ', nullif(btrim(p.surname), ''), nullif(btrim(p.given_names), '')) AS name, p.email,
                       coalesce((SELECT sum(c.units) FROM catalogue.offering o JOIN catalogue.course c ON c.code = o.course_code
                                  WHERE o.lecturer_id = p.id AND o.session = :s AND o.semester = :sem AND o.stream IN ('REGULAR', 'PG')), 0) AS load
                  FROM mine JOIN iam.person p ON p.id = mine.person_id
                 WHERE p.ended_on IS NULL AND nullif(btrim(coalesce(p.staff_number, '')), '') IS NOT NULL
                 ORDER BY name
                """).param("d", code.toUpperCase()).param("dn", String.valueOf(d.get("name"))).param("s", session).param("sem", semester).query().listOfRows();

        // the department's classes: the courses it owns and teaches to programmes of the kind (or, offered to none yet, of the
        // kind's levels), taught in the semester, with the class of the session and stream where one is open and who teaches it
        List<Map<String, Object>> classes = jdbc.sql("""
                SELECT c.id AS course_id, c.code, c.title, c.units, c.kind, c.level, c.semester AS course_semester, c.both_semesters,
                       o.id AS offering_id, o.lecturer_id,
                       lp.staff_number AS lecturer_staff_number, concat_ws(', ', nullif(btrim(lp.surname), ''), nullif(btrim(lp.given_names), '')) AS lecturer,
                       o.second_examiner_id, sp.staff_number AS second_staff_number,
                       concat_ws(', ', nullif(btrim(sp.surname), ''), nullif(btrim(sp.given_names), '')) AS second_examiner,
                       coalesce((SELECT jsonb_agg(jsonb_build_object('staff_number', tp.staff_number,
                                                                     'name', concat_ws(', ', nullif(btrim(tp.surname), ''), nullif(btrim(tp.given_names), ''))) ORDER BY tp.surname)
                                   FROM catalogue.offering_teacher t JOIN iam.person tp ON tp.id = t.lecturer_id WHERE t.offering_id = o.id), '[]'::jsonb)::text AS co_lecturers,
                       coalesce((SELECT string_agg(DISTINCT co.programme_code, ', ' ORDER BY co.programme_code)
                                   FROM catalogue.course_offer co JOIN ref.programme pr ON pr.code = co.programme_code
                                  WHERE co.course_code = c.code AND pr.category = :cat), '') AS programme_codes,
                       coalesce((SELECT string_agg(DISTINCT pr.name, '; ' ORDER BY pr.name)
                                   FROM catalogue.course_offer co JOIN ref.programme pr ON pr.code = co.programme_code
                                  WHERE co.course_code = c.code AND pr.category = :cat), '') AS programme_names
                  FROM catalogue.course c
                  LEFT JOIN catalogue.offering o ON o.course_code = c.code AND o.session = :s AND o.semester = :sem AND o.stream = :stream
                  LEFT JOIN iam.person lp ON lp.id = o.lecturer_id
                  LEFT JOIN iam.person sp ON sp.id = o.second_examiner_id
                 WHERE c.dept_code = :d AND c.state <> 'ENDED' AND c.code NOT LIKE 'DMO %'
                   AND catalogue.runs_in(c.semester, c.both_semesters, :sem)
                   AND (EXISTS (SELECT 1 FROM catalogue.course_offer co JOIN ref.programme pr ON pr.code = co.programme_code
                                 WHERE co.course_code = c.code AND pr.category = :cat)
                        OR (NOT EXISTS (SELECT 1 FROM catalogue.course_offer co WHERE co.course_code = c.code)
                            AND CASE WHEN :cat = 'POST GRADUATE' THEN c.level >= 700 ELSE c.level < 700 END))
                 ORDER BY c.level, c.code
                """).param("d", code).param("cat", category).param("s", session).param("sem", semester).param("stream", stream).query().listOfRows();

        // the courses the department's programmes take from other departments: theirs to allocate, shown so the person filling
        // the template sees who teaches them (read only; an upload of one is refused as another department's course)
        List<Map<String, Object>> borrowed = jdbc.sql("""
                SELECT c.code, c.title, c.units, c.level, od.name AS owner_dept, c.dept_code AS owner_code,
                       string_agg(DISTINCT co.programme_code, ', ' ORDER BY co.programme_code) AS programme_codes,
                       (SELECT concat_ws(', ', nullif(btrim(lp.surname), ''), nullif(btrim(lp.given_names), ''))
                          FROM catalogue.offering o JOIN iam.person lp ON lp.id = o.lecturer_id
                         WHERE o.course_code = c.code AND o.session = :s AND o.semester = :sem AND o.stream = :stream LIMIT 1) AS lecturer
                  FROM catalogue.course_offer co
                  JOIN ref.programme pr ON pr.code = co.programme_code AND pr.dept_code = :d AND pr.category = :cat
                  JOIN catalogue.course c ON c.code = co.course_code AND c.dept_code IS DISTINCT FROM :d
                  LEFT JOIN ref.department od ON od.code = c.dept_code
                 WHERE c.state <> 'ENDED' AND c.code NOT LIKE 'DMO %' AND catalogue.runs_in(c.semester, c.both_semesters, :sem)
                 GROUP BY c.code, c.title, c.units, c.level, od.name, c.dept_code
                 ORDER BY c.level, c.code
                """).param("d", code).param("cat", category).param("s", session).param("sem", semester).param("stream", stream).query().listOfRows();

        int allocations = 0;
        for (Map<String, Object> c : classes) {
            if (c.get("lecturer_id") != null) allocations++;
            if (c.get("second_examiner_id") != null) allocations++;
            String co = String.valueOf(c.get("co_lecturers"));
            allocations += co.equals("[]") ? 0 : co.split("\"staff_number\"").length - 1;
        }
        Map<String, Object> context = new LinkedHashMap<>();
        context.put("facultyCode", d.get("faculty_code"));
        context.put("facultyName", d.get("faculty_name"));
        context.put("deptCode", code);
        context.put("deptName", d.get("name"));
        context.put("programmeType", type);
        context.put("session", session);
        context.put("semester", semester);
        context.put("stream", stream);
        context.put("version", VERSION);
        Map<String, Object> summary = new LinkedHashMap<>();
        summary.put("programmes", programmes.size());
        summary.put("classes", classes.size());
        summary.put("open", classes.stream().filter(c -> c.get("offering_id") != null).count());
        summary.put("lecturers", lecturers.size());
        summary.put("allocations", allocations);
        summary.put("unallocated", classes.stream().filter(c -> c.get("lecturer_id") == null).count());
        summary.put("borrowed", borrowed.size());
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("context", context);
        out.put("summary", summary);
        out.put("programmes", programmes);
        out.put("lecturers", lecturers);
        out.put("classes", classes);
        out.put("borrowed", borrowed);
        return out;
    }

    /** a template issued: the same data, recorded and numbered, on the ticket named */
    @Transactional
    public Map<String, Object> issue(String dept, String programmeType, String session, Integer semester, String ticketRef) {
        Map<String, Object> out = new LinkedHashMap<>(data(dept, programmeType, session, semester));
        @SuppressWarnings("unchecked") Map<String, Object> ctx = (Map<String, Object>) out.get("context");
        @SuppressWarnings("unchecked") Map<String, Object> sum = (Map<String, Object>) out.get("summary");
        UUID ticket = reach.ticket(ticketRef);
        Map<String, Object> rec = jdbc.sql("SELECT id, reference, version, issued_at FROM catalogue.issue_allocation_template(:d, :t, :s, :sem, :c, :l, :p, :a, :tk)")
                .param("d", ctx.get("deptCode")).param("t", ctx.get("programmeType")).param("s", ctx.get("session")).param("sem", ctx.get("semester"))
                .param("c", ((Number) sum.get("classes")).intValue()).param("l", ((Number) sum.get("lecturers")).intValue())
                .param("p", ((Number) sum.get("programmes")).intValue()).param("a", ((Number) sum.get("allocations")).intValue())
                .param("tk", ticket, Types.OTHER).query().singleRow();
        Map<String, Object> issued = new LinkedHashMap<>(ctx);
        issued.put("reference", rec.get("reference"));
        issued.put("version", rec.get("version"));
        issued.put("issuedAt", String.valueOf(rec.get("issued_at")));
        issued.put("issuedBy", jdbc.sql("SELECT helpdesk.person_name(:p)").param("p", AllocationReach.actor()).query(String.class).optional().orElse(null));
        issued.put("issuedOffice", AuditContextHolder.current().map(c -> c.actorOffice()).orElse(""));
        out.put("context", issued);
        if (ticket != null) {
            jdbc.sql("SELECT helpdesk.note_allocation(:t, :s, :r)").param("t", ticket, Types.OTHER)
                    .param("s", "Course allocation template " + rec.get("reference") + " downloaded: " + ctx.get("deptName") + ", " + ctx.get("session") + " semester " + ctx.get("semester"))
                    .param("r", AuditContextHolder.current().map(c -> c.reason()).orElse(null), Types.VARCHAR).query().listOfRows();
        }
        return out;
    }

    /** the templates the acting office may see, the latest first, with the imports made from each */
    @Transactional(readOnly = true)
    public List<Map<String, Object>> recent(int limit) {
        List<Map<String, Object>> rows = jdbc.sql("""
                SELECT t.id, t.reference, t.version, t.dept_code, d.name AS dept_name, t.faculty_code, t.programme_type, t.session, t.semester,
                       t.issued_at, t.issued_office, helpdesk.person_name(t.issued_by) AS issued_by, t.classes, t.lecturers, t.programmes, t.allocations,
                       (SELECT number FROM helpdesk.ticket k WHERE k.id = t.ticket_id) AS ticket,
                       (SELECT count(*) FROM catalogue.allocation_import i WHERE i.template_id = t.id) AS uploads,
                       (SELECT coalesce(sum(i.imported), 0) FROM catalogue.allocation_import i WHERE i.template_id = t.id) AS imported
                  FROM catalogue.allocation_template t LEFT JOIN ref.department d ON d.code = t.dept_code
                 ORDER BY t.issued_at DESC LIMIT 1000
                """).query().listOfRows();
        int n = Math.max(1, Math.min(limit, 200));
        Bound b = bound();
        boolean pg = pgOffice();
        return rows.stream().filter(r -> (!pg || PG.equals(r.get("programme_type"))) && b.reaches((String) r.get("dept_code"), (String) r.get("faculty_code")))
                .limit(n).toList();
    }

    /* ── an upload of a template: its context checked against the record, the page and the file ── */

    /**
     * The template an upload came from, checked: issued by this portal; for the department, kind of programme, session and
     * semester the page has chosen; its context in the file as issued (a department or session written over in the file is
     * refused, not followed); a department the acting office reaches. A newer template for the same context is named, not
     * refused: an older template's rows are judged against the register as it stands now.
     */
    @Transactional(readOnly = true)
    public Context check(TemplateIn in) {
        if (in == null || clean(in.reference()).isEmpty()) {
            throw new DomainRuleViolation("ALLOC_TEMPLATE_UNNAMED", "The file names no course allocation template.",
                    new DomainRuleViolation.Remedy("Download the department's template, fill it and upload that file.", "You"));
        }
        Map<String, Object> t = jdbc.sql("""
                SELECT t.id, t.reference, t.version, t.dept_code, d.name AS dept_name, t.faculty_code, t.programme_type, t.session, t.semester, t.issued_at
                  FROM catalogue.allocation_template t JOIN ref.department d ON d.code = t.dept_code WHERE upper(t.reference) = upper(:r)
                """).param("r", clean(in.reference())).query().listOfRows().stream().findFirst()
                .orElseThrow(() -> new DomainRuleViolation("ALLOC_TEMPLATE_UNKNOWN", "This portal issued no course allocation template " + clean(in.reference()) + ".",
                        new DomainRuleViolation.Remedy("Download the department's template from this page and upload that file.", "You")));
        String dept = (String) t.get("dept_code");
        String deptName = (String) t.get("dept_name");
        String type = (String) t.get("programme_type");
        String session = (String) t.get("session");
        int semester = ((Number) t.get("semester")).intValue();
        if (((Number) t.get("version")).intValue() > VERSION) {
            throw new DomainRuleViolation("ALLOC_TEMPLATE_VERSION", "Template " + t.get("reference") + " is of a newer format than this portal reads.",
                    new DomainRuleViolation.Remedy("Download the template again and upload that file.", "You"));
        }
        // the page's choice: the department and context being uploaded for
        if (!clean(in.dept()).isEmpty() && !dept.equalsIgnoreCase(clean(in.dept()))) {
            String chosen = jdbc.sql("SELECT name FROM ref.department WHERE upper(code) = upper(:d)").param("d", clean(in.dept())).query(String.class).optional().orElse(clean(in.dept()));
            throw new DomainRuleViolation("ALLOC_TEMPLATE_DEPARTMENT", "Template department mismatch: this template was generated for " + deptName
                    + " but you are uploading for " + chosen + ".",
                    new DomainRuleViolation.Remedy("Choose " + deptName + " on this page, or upload the " + chosen + " template.", "You"));
        }
        if ((!clean(in.programmeType()).isEmpty() && !type.equals(type(in.programmeType())))
                || (!clean(in.session()).isEmpty() && !session.equals(clean(in.session())))
                || (in.semester() != null && in.semester() != semester)) {
            throw new DomainRuleViolation("ALLOC_TEMPLATE_CONTEXT", "Template " + t.get("reference") + " was generated for " + (PG.equals(type) ? "postgraduate" : "undergraduate")
                    + " classes of " + session + " semester " + semester + ", not for the session, semester or programme type chosen on this page.",
                    new DomainRuleViolation.Remedy("Choose the template's own session, semester and programme type, or download a template for the ones you need.", "You"));
        }
        // the file's own context: as issued, or the file was altered
        if ((!clean(in.fileDept()).isEmpty() && !dept.equalsIgnoreCase(clean(in.fileDept())))
                || (!clean(in.fileProgrammeType()).isEmpty() && !type.equalsIgnoreCase(clean(in.fileProgrammeType())))
                || (!clean(in.fileSession()).isEmpty() && !session.equals(clean(in.fileSession())))
                || (in.fileSemester() != null && in.fileSemester() != semester)) {
            throw new DomainRuleViolation("ALLOC_TEMPLATE_ALTERED", "The template's context was changed in the file: template " + t.get("reference")
                    + " was issued for " + deptName + ", " + session + " semester " + semester + ". The portal reads the template's own context, never the file's.",
                    new DomainRuleViolation.Remedy("Download a fresh template for the department you mean and fill that.", "You"));
        }
        reachable(dept);
        if (pgOffice() && !PG.equals(type)) {
            throw new AccessDeniedException("The School of Postgraduate Studies uploads postgraduate allocation templates only.");
        }
        String newer = jdbc.sql("""
                SELECT reference FROM catalogue.allocation_template
                 WHERE dept_code = :d AND programme_type = :t AND session = :s AND semester = :sem AND issued_at > :at
                 ORDER BY issued_at DESC LIMIT 1
                """).param("d", dept).param("t", type).param("s", session).param("sem", semester).param("at", t.get("issued_at"))
                .query(String.class).optional().orElse(null);
        return new Context((UUID) t.get("id"), (String) t.get("reference"), dept, deptName, (String) t.get("faculty_code"), type, session, semester, newer);
    }
}
