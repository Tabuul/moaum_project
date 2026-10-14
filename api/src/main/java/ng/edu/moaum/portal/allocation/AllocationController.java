package ng.edu.moaum.portal.allocation;

import org.springframework.security.core.Authentication;
import java.sql.Types;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

import ng.edu.moaum.portal.shared.DomainRuleViolation;
import ng.edu.moaum.portal.shared.OfficeScope;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/** Teaching allocation, worked by the Head of Department (V041). */
@RestController
@RequestMapping("/api/v1/allocation")
class AllocationController {

    private static final String ALLOCATORS = "hasAnyAuthority('OFFICE_hod','OFFICE_dean','OFFICE_academic','OFFICE_dregistrar','OFFICE_registrar','OFFICE_admin','OFFICE_super')";
    /** V408: the bulk import and the lecturers list it reads are open to the course allocation desk of the Director of ICT and the
     *  ICT Support Desk as well — an agent's rows held to the reach of their BULK_ALLOCATE postings (AllocationImportService); the
     *  department desk's own acts below stay the academic offices' */
    private static final String IMPORTERS = "hasAnyAuthority('OFFICE_hod','OFFICE_dean','OFFICE_academic','OFFICE_dregistrar','OFFICE_registrar','OFFICE_admin','OFFICE_super',"
            + "'OFFICE_ict','OFFICE_helpdeskhead','OFFICE_ictagent')";

    private final JdbcClient jdbc;
    private final OfficeScope scope;
    private final AllocationImportService imports;
    private final AllocationRecord record;

    AllocationController(JdbcClient jdbc, OfficeScope scope, AllocationImportService imports, AllocationRecord record) {
        this.jdbc = jdbc;
        this.scope = scope;
        this.imports = imports;
        this.record = record;
    }

    /* ── V321: bulk course allocation from a spreadsheet — validated first, imported on confirmation ── */

    public record ImportIn(@NotNull List<AllocationImportService.RowIn> rows, AllocationImportService.Options options, String fileName, UUID importKey) {
    }

    /** every row judged against the register; nothing written */
    @PostMapping("/import/validate")
    @PreAuthorize(IMPORTERS)
    AllocationImportService.Validation validateImport(@Valid @RequestBody ImportIn body) {
        return imports.validate(body.rows(), body.options());
    }

    /** the valid rows written in one transaction through the same allocation every desk uses; a repeated key answers
     *  with the record already made */
    @PostMapping("/import")
    @PreAuthorize(IMPORTERS)
    AllocationImportService.ImportResult doImport(@Valid @RequestBody ImportIn body) {
        return imports.importRows(body.importKey(), body.fileName(), body.rows(), body.options());
    }

    @GetMapping("/imports")
    @PreAuthorize(IMPORTERS)
    List<Map<String, Object>> importHistory(@RequestParam(defaultValue = "100") int limit) {
        return imports.history(limit);
    }

    @GetMapping("/imports/{id}")
    @PreAuthorize(IMPORTERS)
    Map<String, Object> importRecord(@PathVariable UUID id) {
        return imports.one(id);
    }

    /** V408: a reason, required when the class's lead is replaced, goes on the allocation history */
    public record Assign(@NotNull UUID lecturer, UUID secondExaminer, Boolean overload, String reason) {
    }

    private static final String HISTORY_READERS = "hasAnyAuthority('OFFICE_lecturer','OFFICE_hod','OFFICE_exams','OFFICE_facultyexams','OFFICE_dean',"
            + "'OFFICE_facultyofficer','OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar','OFFICE_records','OFFICE_admin','OFFICE_super')";

    /**
     * The history of teaching allocation, every session on record: with scope=me, the courses the acting
     * person has carried (as lecturer or co-lecturer); with scope=department, every course of the acting
     * office's department — the Head of Department's own, or the department an Examinations Officer's grant
     * names (else their home department) — with who carried it, the second examiner, the class size and
     * where its score sheet reached. Newest session first.
     */
    @GetMapping("/history")
    @PreAuthorize(HISTORY_READERS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> history(Authentication authentication, @RequestParam(defaultValue = "me") String scope) {
        UUID me = UUID.fromString(authentication.getName());
        String where;
        Map<String, Object> params = new java.util.HashMap<>();
        if ("department".equalsIgnoreCase(scope)) {
            String dept = this.scope.actingDept();
            if (dept == null) {
                String office = ng.edu.moaum.portal.shared.AuditContextHolder.current().map(c -> c.actorOffice()).orElse("");
                dept = jdbc.sql("""
                        SELECT d.code FROM ref.department d
                         WHERE d.ended_on IS NULL AND upper(d.code) = upper(coalesce(
                            (SELECT a.scope_id FROM iam.office_assignment a
                              WHERE a.person_id = :p AND a.office_code = :o AND a.scope_kind = 'department'
                                AND a.valid_from <= current_date AND (a.valid_to IS NULL OR a.valid_to >= current_date)
                              ORDER BY a.valid_from DESC LIMIT 1),
                            (SELECT sr.home_department FROM hrm.staff_record sr WHERE sr.person_id = :p), ''))
                        """).param("p", me).param("o", office).query(String.class).optional().orElse(null);
            }
            if (dept == null) return List.of();
            where = " WHERE c.dept_code = :d";
            params.put("d", dept);
        } else {
            where = " WHERE (o.lecturer_id = :me OR EXISTS (SELECT 1 FROM catalogue.offering_teacher t WHERE t.offering_id = o.id AND t.lecturer_id = :me))";
            params.put("me", me);
        }
        var q = jdbc.sql("""
                SELECT o.id, o.session, o.semester, o.course_code, c.title, c.units, c.level, o.allocated_on,
                       o.lecturer_id, CASE WHEN lp.id IS NULL THEN NULL ELSE concat_ws(', ', nullif(btrim(lp.surname), ''), nullif(btrim(lp.given_names), '')) END AS lecturer,
                       CASE WHEN sp.id IS NULL THEN NULL ELSE concat_ws(', ', nullif(btrim(sp.surname), ''), nullif(btrim(sp.given_names), '')) END AS second_examiner,
                       (SELECT string_agg(concat_ws(', ', nullif(btrim(tp.surname), ''), nullif(btrim(tp.given_names), '')), '; ' ORDER BY tp.surname)
                          FROM catalogue.offering_teacher t JOIN iam.person tp ON tp.id = t.lecturer_id WHERE t.offering_id = o.id) AS co_lecturers,
                       (SELECT count(*) FROM registration.entry e JOIN registration.course_registration r ON r.id = e.registration_id
                         WHERE e.offering_id = o.id AND e.status IN ('REGISTERED','APPROVED') AND r.status IN ('APPROVED','LOCKED')) AS students,
                       (SELECT sh.stage FROM assessment.score_sheet sh WHERE sh.offering_id = o.id LIMIT 1) AS stage,
                       CASE WHEN o.lecturer_id = :actor THEN 'Lecturer'
                            WHEN EXISTS (SELECT 1 FROM catalogue.offering_teacher t WHERE t.offering_id = o.id AND t.lecturer_id = :actor) THEN 'Co-lecturer'
                            WHEN o.second_examiner_id = :actor THEN 'Second examiner' END AS role
                  FROM catalogue.offering o
                  JOIN catalogue.course c ON c.code = o.course_code
                  LEFT JOIN iam.person lp ON lp.id = o.lecturer_id
                  LEFT JOIN iam.person sp ON sp.id = o.second_examiner_id
                """ + where + " ORDER BY o.session DESC, o.semester DESC, o.course_code LIMIT 600").param("actor", me);
        for (var e : params.entrySet()) q = q.param(e.getKey(), e.getValue());
        return q.query().listOfRows();
    }

    /** the departments a lecturer can be allocated in (reference data, any signed-in staff) */
    @GetMapping("/departments")
    @PreAuthorize("isAuthenticated()")
    @Transactional(readOnly = true)
    List<Map<String, Object>> departments() {
        if (scope.actingHod()) {                            // an HOD sees only their own department
            return jdbc.sql("SELECT code, name, faculty_code FROM ref.department WHERE ended_on IS NULL AND code = :d")
                    .param("d", scope.scopedDept(null)).query().listOfRows();
        }
        return jdbc.sql("SELECT code, name, faculty_code FROM ref.department WHERE ended_on IS NULL ORDER BY name").query().listOfRows();
    }

    /** the department's offerings for a session and semester, with who is on each and how many are registered */
    @GetMapping
    @PreAuthorize(ALLOCATORS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> offerings(@RequestParam String dept, @RequestParam String session,
                                        @RequestParam(defaultValue = "1") int semester,
                                        @RequestParam(required = false) Integer level) {
        dept = scope.scopedDept(dept);                      // an HOD's allocation is limited to their department
        List<Map<String, Object>> rows = jdbc.sql("""
                SELECT o.id, c.code AS course_code, c.title, c.units, c.level, o.allocated_on,
                       (SELECT count(*) FROM registration.entry e JOIN registration.course_registration r ON r.id = e.registration_id
                         WHERE e.offering_id = o.id AND r.status = 'APPROVED') AS registered,
                       o.lecturer_id,
                       CASE WHEN lp.id IS NULL THEN NULL ELSE concat_ws(', ', nullif(btrim(lp.surname), ''), nullif(btrim(lp.given_names), '')) END AS lecturer,
                       o.second_examiner_id,
                       CASE WHEN sp.id IS NULL THEN NULL ELSE concat_ws(', ', nullif(btrim(sp.surname), ''), nullif(btrim(sp.given_names), '')) END AS second_examiner,
                       coalesce((SELECT jsonb_agg(jsonb_build_object('id', t.lecturer_id, 'name', concat_ws(', ', nullif(btrim(tp.surname), ''), nullif(btrim(tp.given_names), '')), 'programme_code', t.programme_code, 'programme', pr.name) ORDER BY tp.surname)
                                   FROM catalogue.offering_teacher t JOIN iam.person tp ON tp.id = t.lecturer_id LEFT JOIN ref.programme pr ON pr.code = t.programme_code
                                  WHERE t.offering_id = o.id), '[]'::jsonb) AS co_lecturers,
                       coalesce((SELECT jsonb_agg(DISTINCT jsonb_build_object('code', co.programme_code, 'name', pr.name))
                                   FROM catalogue.course_offer co JOIN ref.programme pr ON pr.code = co.programme_code
                                  WHERE co.course_code = c.code), '[]'::jsonb) AS programmes,
                       EXISTS (SELECT 1 FROM assessment.score_sheet sh WHERE sh.offering_id = o.id) AS sheet,
                       o.id IS NULL AS no_class,
                       NOT EXISTS (SELECT 1 FROM catalogue.course_offer co WHERE co.course_code = c.code) AS not_in_structure
                  FROM catalogue.course c
                  -- V443: the department's COURSES for the semester, each with its class in the session if one exists — a course is never
                  -- tied to a session; a class is opened when the course is allocated (POST /open), not by the calendar alone
                  LEFT JOIN catalogue.offering o ON o.course_code = c.code AND o.session = :session AND o.semester = :semester
                                                 AND o.stream IN ('REGULAR', 'PG')          -- V380: the full-time classes; the Centre allocates its own (V389: and the School's)
                  LEFT JOIN iam.person lp ON lp.id = o.lecturer_id
                  LEFT JOIN iam.person sp ON sp.id = o.second_examiner_id
                 WHERE c.dept_code = :dept
                   AND catalogue.runs_in(c.semester, c.both_semesters, :semester)   -- only courses taught in this semester (V386: or in both)
                   AND c.state <> 'ENDED'                     -- an ended course is not allocated to a lecturer
                   AND c.code NOT LIKE 'DMO %'
                   AND (:level::int IS NULL OR c.level = :level)
                 ORDER BY c.level, c.code, o.stream
                """).param("session", session).param("semester", semester).param("dept", dept)
                .param("level", level, java.sql.Types.INTEGER).query().listOfRows();
        // co_lecturers comes back as a jsonb string over JDBC; parse it to a real array so the client gets one
        for (Map<String, Object> row : rows) {
            Object cl = row.get("co_lecturers");
            row.put("co_lecturers", CO.readValue(cl == null ? "[]" : cl.toString(),
                    new tools.jackson.core.type.TypeReference<List<Map<String, Object>>>() { }));
            Object pg = row.get("programmes");
            row.put("programmes", CO.readValue(pg == null ? "[]" : pg.toString(),
                    new tools.jackson.core.type.TypeReference<List<Map<String, Object>>>() { }));
        }
        return rows;
    }

    public record Open(@NotBlank @Size(max = 24) String courseCode, @NotBlank @Size(max = 9) String session, @NotNull Integer semester) { }

    /** V443: the class of a course in a session and semester — the one there is, or one opened now, so a course of the pool is
     *  allocated in any session on the register; a Head of Department opens classes of their own department's courses only */
    @PostMapping("/open")
    @PreAuthorize(ALLOCATORS)
    @Transactional
    Map<String, Object> open(@Valid @RequestBody Open body) {
        String code = body.courseCode().trim().toUpperCase().replaceAll("\\s+", " ");
        if (scope.actingHod()) {
            String hodDept = scope.actingHodDept();
            String owner = jdbc.sql("SELECT dept_code FROM catalogue.course WHERE code = :c").param("c", code).query(String.class).optional().orElse(null);
            if (hodDept == null || !hodDept.equals(owner)) {
                throw new DomainRuleViolation("ALLOC_DEPT", "A Head of Department allocates only courses that belong to their own department.",
                        new DomainRuleViolation.Remedy("Choose a course in your department; another department allocates its own.", "Head of Department"));
            }
        }
        UUID id = jdbc.sql("SELECT catalogue.open_class(:c, :s, :n, NULL)").param("c", code).param("s", body.session().trim()).param("n", body.semester())
                .query(UUID.class).single();
        return Map.of("id", id, "courseCode", code, "session", body.session().trim(), "semester", body.semester());
    }

    /** V405: the department's courses with no class in the session's opened semesters, and why — a course added to a programme's
     *  structure after the semester opened (from V405 its class opens with the structure row; here the desk opens what is still
     *  owed), or a course in no programme's structure at all, which no opening reaches */
    @GetMapping("/without-class")
    @PreAuthorize(ALLOCATORS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> withoutClass(@RequestParam String dept, @RequestParam String session) {
        dept = scope.scopedDept(dept);
        return jdbc.sql("SELECT * FROM catalogue.courses_without_class(:d, :s)").param("d", dept).param("s", session).query().listOfRows();
    }

    /** every structure course still without a class in the session's opened semesters gets one, as the calendar gave the others
     *  when it opened the semester (registration.open_course_registration, idempotent); nothing is opened for a semester not yet open */
    @PostMapping("/open-classes")
    @PreAuthorize(ALLOCATORS)
    @Transactional
    Map<String, Object> openClasses(@RequestParam String session) {
        List<Integer> semesters = jdbc.sql("SELECT DISTINCT semester FROM catalogue.offering WHERE session = :s AND stream = 'REGULAR' ORDER BY semester")
                .param("s", session).query(Integer.class).list();
        int opened = 0;
        for (Integer semester : semesters) {
            opened += jdbc.sql("SELECT registration.open_course_registration(:s, :n)").param("s", session).param("n", semester).query(Integer.class).single();
        }
        return Map.of("session", session, "semesters", semesters, "opened", opened);
    }

    private static final tools.jackson.databind.ObjectMapper CO = new tools.jackson.databind.ObjectMapper();

    /**
     * The lecturers a course can be allocated to, with their current teaching load. By default the
     * department's own lecturers; with all=true, every lecturer in the University (each labelled with
     * their home department) so a department can assign its course to a lecturer from another
     * department — the cross-department teaching case. The lecturer keeps one dashboard and enters the
     * scores there, whatever department the course belongs to.
     */
    @GetMapping("/lecturers")
    @PreAuthorize(IMPORTERS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> lecturers(@RequestParam String dept, @RequestParam String session,
                                        @RequestParam(defaultValue = "1") int semester,
                                        @RequestParam(defaultValue = "false") boolean all) {
        dept = scope.scopedDept(dept);                      // an HOD's own-department list stays within their department
        String live = "a.office_code IN ('lecturer', 'hod') AND a.scope_kind = 'department'"
                + " AND a.valid_from <= current_date AND (a.valid_to IS NULL OR a.valid_to >= current_date)";
        // V396: a linked BSU-/MOAU- pair the lecturer teaches is one class, counted once (as catalogue.allocate_offering counts it)
        String load = "coalesce((SELECT sum(c.units) FROM catalogue.offering o JOIN catalogue.course c ON c.code = o.course_code"
                + " WHERE o.lecturer_id = p.id AND o.session = :session AND o.semester = :semester AND o.stream IN ('REGULAR', 'PG')"
                + " AND NOT (c.code ~ '^MOAU-' AND EXISTS (SELECT 1 FROM catalogue.offering_family(o.id) f JOIN catalogue.offering o2 ON o2.id = f WHERE f <> o.id AND o2.lecturer_id = p.id))), 0) AS load";
        if (all) {
            return jdbc.sql("""
                    SELECT p.id, concat_ws(', ', nullif(btrim(p.surname), ''), nullif(btrim(p.given_names), '')) AS name, p.staff_number,
                           (SELECT string_agg(DISTINCT a.scope_id, ', ' ORDER BY a.scope_id) FROM iam.office_assignment a
                             WHERE a.person_id = p.id AND %s) AS department,
                           %s
                      FROM iam.person p
                     WHERE p.ended_on IS NULL
                       AND EXISTS (SELECT 1 FROM iam.office_assignment a WHERE a.person_id = p.id AND %s)
                     ORDER BY name
                    """.formatted(live, load, live))
                    .param("session", session).param("semester", semester).query().listOfRows();
        }
        return jdbc.sql("""
                SELECT DISTINCT p.id, concat_ws(', ', nullif(btrim(p.surname), ''), nullif(btrim(p.given_names), '')) AS name, p.staff_number, :dept AS department,
                       %s
                  FROM iam.person p
                  JOIN iam.office_assignment a ON a.person_id = p.id
                 WHERE %s AND a.scope_id = :dept
                 ORDER BY load, name
                """.formatted(load, live))
                .param("session", session).param("semester", semester).param("dept", dept).query().listOfRows();
    }

    /** a HOD allocates only courses that belong to their own department */
    private void assertHodOwnsOffering(UUID offering) {
        if (!scope.actingHod()) {
            return;
        }
        String hodDept = scope.actingHodDept();
        String offDept = jdbc.sql("SELECT c.dept_code FROM catalogue.offering o JOIN catalogue.course c ON c.code = o.course_code WHERE o.id = :o")
                .param("o", offering).query(String.class).optional().orElse(null);
        if (hodDept == null || !hodDept.equals(offDept)) {
            throw new DomainRuleViolation("ALLOC_DEPT", "A Head of Department allocates only courses that belong to their own department.",
                    new DomainRuleViolation.Remedy("Choose a course in your department; another department allocates its own.", "Head of Department"));
        }
    }

    /** an ended course is off the catalogue and is not allocated to a lecturer (restore it first) */
    private void assertOfferingLive(UUID offering) {
        // V380: a class of the Centre for Continuing Education is allocated on the Centre's desk, not the department's
        if (Boolean.TRUE.equals(jdbc.sql("SELECT EXISTS (SELECT 1 FROM catalogue.offering WHERE id = :o AND stream = 'CCE')").param("o", offering).query(Boolean.class).single())) {
            throw new DomainRuleViolation("ALLOC_CCE", "This is a class of the Centre for Continuing Education; the Centre allocates its lecturer.",
                    new DomainRuleViolation.Remedy("Ask the Centre for Continuing Education, or allocate the full-time class of the course.", "Centre for Continuing Education"));
        }
        String state = jdbc.sql("SELECT c.state FROM catalogue.offering o JOIN catalogue.course c ON c.code = o.course_code WHERE o.id = :o")
                .param("o", offering).query(String.class).optional().orElse(null);
        if ("ENDED".equals(state)) {
            throw new DomainRuleViolation("ALLOC_ENDED", "This course has ended, so it cannot be allocated to a lecturer.",
                    new DomainRuleViolation.Remedy("Restore the course on the Department courses page before allocating it.", "Head of Department"));
        }
    }

    /** assign the lead lecturer and a second examiner to an offering */
    @PostMapping("/{offering}")
    @PreAuthorize(ALLOCATORS)
    @Transactional
    Map<String, Object> assign(@PathVariable UUID offering, @Valid @RequestBody Assign body) {
        assertHodOwnsOffering(offering);
        assertOfferingLive(offering);
        // V408: the same checks as the ICT desk — a person who has left or holds no lecturer office takes no class, as lead or
        // as second examiner; replacing the lead says why, and the history keeps it
        record.refuseIneligible(offering, body.lecturer(), "LECTURER");
        if (body.secondExaminer() != null) record.refuseIneligible(offering, body.secondExaminer(), "CO_LECTURER");
        UUID lead = jdbc.sql("SELECT lecturer_id FROM catalogue.offering WHERE id = :o").param("o", offering).query(UUID.class).optional().orElse(null);
        if (lead != null && !lead.equals(body.lecturer())) record.reason(AllocationRecord.need(body.reason(), "replacing the lead lecturer"));
        else record.reason(body.reason());
        // an allocation is two small writes; if the offerings table is held by someone opening registration or
        // loading a structure, say so in seconds rather than hang the desk for the length of that work
        jdbc.sql("SET LOCAL lock_timeout = '8s'").update();
        jdbc.sql("SET LOCAL statement_timeout = '25s'").update();
        try {
        // a co-lecturer made the lead is the lead only (as the ICT desk does)
        jdbc.sql("DELETE FROM catalogue.offering_teacher WHERE offering_id IN (SELECT catalogue.offering_family(:o)) AND lecturer_id = :p")
                .param("o", offering).param("p", body.lecturer()).update();
        jdbc.sql("SELECT catalogue.allocate_offering(:o, :lec, :sec, :ov)")
                .param("o", offering).param("lec", body.lecturer())
                .param("sec", body.secondExaminer(), Types.OTHER)
                .param("ov", Boolean.TRUE.equals(body.overload()))
                .query().singleRow();
        } catch (org.springframework.dao.DataAccessException e) {
            String m = String.valueOf(e.getMostSpecificCause() == null ? e.getMessage() : e.getMostSpecificCause().getMessage());
            if (m.contains("lock timeout") || m.contains("55P03") || m.contains("statement timeout") || m.contains("57014")) {
                throw new ng.edu.moaum.portal.shared.DomainRuleViolation("ALLOC_BUSY",
                        "The offerings are busy: registration is being opened or a course structure loaded.",
                        new ng.edu.moaum.portal.shared.DomainRuleViolation.Remedy("Nothing was saved. Wait a minute and press Save again.", "You"));
            }
            throw e;
        }
        return Map.of("offering", offering, "allocated", true);
    }

    /** V332: a co-lecturer may be posted to one programme's group of the offering (the programme must carry the course) */
    public record Teacher(@NotNull UUID lecturer, String programme, String reason) {
    }

    /** add a co-lecturer who also teaches the course and enters scores on the shared sheet */
    @PostMapping("/{offering}/teachers")
    @PreAuthorize(ALLOCATORS)
    @Transactional
    Map<String, Object> addTeacher(@PathVariable UUID offering, @Valid @RequestBody Teacher body) {
        assertHodOwnsOffering(offering);
        assertOfferingLive(offering);
        record.refuseIneligible(offering, body.lecturer(), "CO_LECTURER");   // V408
        record.reason(body.reason());
        String group = body.programme() == null || body.programme().isBlank() ? null : body.programme().trim().toUpperCase();
        if (group != null && jdbc.sql("""
                SELECT count(*) FROM catalogue.offering o JOIN catalogue.course_offer co ON co.course_code = o.course_code
                 WHERE o.id = :o AND co.programme_code = :p
                """).param("o", offering).param("p", group).query(Long.class).single() == 0) {
            throw new ng.edu.moaum.portal.shared.DomainRuleViolation("ALLOC_GROUP", "That programme does not offer this course.",
                    new ng.edu.moaum.portal.shared.DomainRuleViolation.Remedy("Offer the course to the programme first, or post the co-lecturer to every programme.", "Head of Department"));
        }
        Integer n = jdbc.sql("""
                INSERT INTO catalogue.offering_teacher (offering_id, lecturer_id, added_by, programme_code)
                SELECT :o, :lec, :by, :g
                 WHERE NOT EXISTS (SELECT 1 FROM catalogue.offering WHERE id = :o AND lecturer_id = :lec)
                ON CONFLICT (offering_id, lecturer_id) DO UPDATE SET programme_code = EXCLUDED.programme_code
                RETURNING 1
                """).param("o", offering).param("lec", body.lecturer())
                .param("by", scope.actorId(), Types.OTHER).param("g", group, Types.VARCHAR).query(Integer.class).optional().orElse(0);
        return Map.of("offering", offering, "lecturer", body.lecturer(), "added", n > 0, "programme", group == null ? "" : group);
    }

    /** remove a co-lecturer (the lead is changed by re-assigning, not here) */
    @DeleteMapping("/{offering}/teachers/{lecturer}")
    @PreAuthorize(ALLOCATORS)
    @Transactional
    Map<String, Object> removeTeacher(@PathVariable UUID offering, @PathVariable UUID lecturer, @RequestParam(required = false) String reason) {
        assertHodOwnsOffering(offering);
        record.reason(AllocationRecord.need(reason, "removing the co-lecturer"));   // V408: the history keeps that they taught it, and why they stopped
        jdbc.sql("DELETE FROM catalogue.offering_teacher WHERE offering_id = :o AND lecturer_id = :lec")
                .param("o", offering).param("lec", lecturer).update();
        return Map.of("offering", offering, "lecturer", lecturer, "removed", true);
    }

    /* ── V408: the checks before an allocation and the history after it, as the ICT desk reads them ── */

    /** whether a person may take the class as lead (LECTURER) or co-lecturer (CO_LECTURER), each check said; nothing written */
    @GetMapping("/{offering}/check")
    @PreAuthorize(ALLOCATORS)
    @Transactional(readOnly = true)
    Map<String, Object> check(@PathVariable UUID offering, @RequestParam UUID lecturer, @RequestParam(defaultValue = "LECTURER") String role) {
        assertHodOwnsOffering(offering);
        return record.checks(offering, lecturer, role);
    }

    /** the class's allocation history, newest first */
    @GetMapping("/{offering}/history")
    @PreAuthorize(ALLOCATORS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> classHistory(@PathVariable UUID offering) {
        assertHodOwnsOffering(offering);
        return record.events(" WHERE ev.offering_id = :o", Map.of("o", offering), 200);
    }

    /** the department's allocation history for a session (and semester): a Head of Department's own department only */
    @GetMapping("/events")
    @PreAuthorize(ALLOCATORS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> events(@RequestParam String dept, @RequestParam String session, @RequestParam(required = false) Integer semester,
                                     @RequestParam(defaultValue = "200") int limit) {
        String d = scope.scopedDept(dept);
        return record.events(" WHERE c.dept_code = :d AND ev.session = :s AND (:sem = 0 OR ev.semester = :sem)",
                Map.of("d", d, "s", session, "sem", semester == null ? 0 : semester), limit);
    }
}
