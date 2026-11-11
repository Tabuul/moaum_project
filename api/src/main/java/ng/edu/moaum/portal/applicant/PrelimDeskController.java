package ng.edu.moaum.portal.applicant;

import java.math.BigDecimal;
import java.sql.Types;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

import ng.edu.moaum.portal.shared.AuditContextHolder;
import ng.edu.moaum.portal.shared.DomainRuleViolation;
import ng.edu.moaum.portal.shared.NotFound;
import ng.edu.moaum.portal.shared.OfficeScope;

import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
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
 * V446: the Preliminary Science desk. The Preliminary Science Office reviews (documents, O'Level verification, corrections,
 * recommendation, remediation); the Academic Office approves, publishes and configures the programme (its rule, targets and
 * documents); the Bursary states its fees. The Registry and the institution's administrators read. A Head of Department or a
 * Dean reads, without acting, only the applications whose target programme is in their department or faculty — the backend
 * holds that scope on every read, and every act is checked again by the database function that performs it.
 */
@RestController
@RequestMapping("/api/v1/admissions/preliminary")
class PrelimDeskController {

    private static final String CENTRAL = "'OFFICE_prelim','OFFICE_prelimtech','OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar','OFFICE_super','OFFICE_admin'";
    private static final String READERS = "hasAnyAuthority(" + CENTRAL + ",'OFFICE_hod','OFFICE_dean')";
    private static final String CENTRAL_READERS = "hasAnyAuthority(" + CENTRAL + ")";
    private static final String REVIEWERS = "hasAnyAuthority('OFFICE_prelim','OFFICE_prelimtech','OFFICE_academic','OFFICE_super')";
    /** V701: the offices that review a route of their own — each reads and acts on its own routes only */
    private static final Set<String> ROUTE_OFFICES = Set.of("prelim", "prelimtech");
    private static final String DECIDERS = "hasAnyAuthority('OFFICE_academic','OFFICE_super')";
    private static final String FEE_SETTERS = "hasAnyAuthority('OFFICE_bursar','OFFICE_super')";
    /** the settings are read by the desk's readers and by the Bursary, which states the fees on them */
    private static final String CONFIG_READERS = "hasAnyAuthority(" + CENTRAL + ",'OFFICE_bursar','OFFICE_hod','OFFICE_dean')";
    private static final Set<String> SCOPED = Set.of("hod", "dean");
    private static final Set<String> VIEWS = Set.of("total", "paid", "submitted", "incomplete", "pendingReview", "underReview", "correction", "eligible",
            "notEligible", "remediationRequired", "admitted", "notAdmitted", "withdrawn");
    private static final Map<String, String> SORTS = Map.of("name", "x.surname, x.other_names", "number", "x.application_no", "submitted", "x.submitted_at DESC NULLS LAST, x.application_no",
            "credits", "x.total_credits DESC NULLS LAST, x.core_credits DESC NULLS LAST, x.application_no", "target", "x.target_name NULLS LAST, x.surname");

    private final JdbcClient jdbc;
    private final OfficeScope scope;
    private final PrelimApplicantService prelim;
    private final ApplicantService applicants;

    PrelimDeskController(JdbcClient jdbc, OfficeScope scope, PrelimApplicantService prelim, ApplicantService applicants) {
        this.jdbc = jdbc;
        this.scope = scope;
        this.prelim = prelim;
        this.applicants = applicants;
    }

    /* ── the scope ── */

    private String office() {
        return AuditContextHolder.current().map(c -> c.actorOffice()).orElse("");
    }

    /** a Head of Department reads their department's targets, a Dean their faculty's; the central offices read every application */
    private record Bound(String dept, String faculty) {
    }

    private Bound bound() {
        String o = office();
        if (!SCOPED.contains(o)) return new Bound(null, null);
        if (scope.actingDepartmentOffice()) return new Bound(scope.actingDept() == null ? "__none__" : scope.actingDept(), null);
        if (scope.actingFacultyOffice()) return new Bound(null, scope.actingFaculty() == null ? "__none__" : scope.actingFaculty());
        return new Bound("__none__", null);
    }

    /** V701: the route a request is about — Preliminary Science unless another is named (a route's own office: its first route); a route's own office reads and acts on
     *  its routes only (the Preliminary Science Office on Preliminary Science, the Vocational and Technical Office on Preliminary
     *  Technology and the proficiency courses) */
    private String route(String requested) {
        String o = office();
        if ((requested == null || requested.isBlank()) && ROUTE_OFFICES.contains(o)) {
            // V721: the office's first route by the routes' own rank — a preliminary, remedial or foundation programme before a proficiency course, then the
            // fee types' order, then the name — never by the fee types' order alone, which the Bursary's desk (and a test before this
            // one in the same suite) may change; the nightly suite-twice run found the Vocational office opening on the proficiency courses
            requested = jdbc.sql("""
                    SELECT p.route FROM admissions.prelim_programme p LEFT JOIN finance.programme_type pt ON pt.code = p.programme_type
                     WHERE p.office_code = :o ORDER BY (p.programme_type NOT IN ('PRELIMINARY', 'REMEDIAL', 'FOUNDATION')), pt.ord, p.name LIMIT 1
                    """).param("o", o).query(String.class).optional().orElse(null);
        }
        String r = prelim.routeOf(requested);
        if (ROUTE_OFFICES.contains(o) && !o.equals(officeOf(r))) {
            throw new org.springframework.security.access.AccessDeniedException("The " + o + " office does not read the applications of " + r);
        }
        return r;
    }

    private String officeOf(String route) {
        return jdbc.sql("SELECT office_code FROM admissions.prelim_programme WHERE route = :r").param("r", route).query(String.class).single();
    }

    private String session(String requested, String route) {
        if (requested != null && requested.matches("\\d{4}/\\d{4}")) return requested;
        return jdbc.sql("SELECT policy.route_session(:r)").param("r", route).query(String.class).single();
    }

    /** the application, if it is a preliminary or proficiency application within the reader's scope (a route's own office reads its
     *  own routes'); otherwise not found */
    private UUID within(UUID id) {
        Bound b = bound();
        String o = office();
        boolean ok = jdbc.sql("""
                SELECT EXISTS (SELECT 1 FROM admissions.prelim_review r JOIN admissions.prelim_programme pp ON pp.route = r.route
                                 LEFT JOIN ref.programme p ON p.code = r.target_programme
                                WHERE r.application_id = :a AND (NOT :own OR pp.office_code = :o)
                                  AND (:bd::text IS NULL OR p.dept_code = :bd) AND (:bf::text IS NULL OR p.faculty_code = :bf))
                """).param("a", id).param("own", ROUTE_OFFICES.contains(o)).param("o", o)
                .param("bd", b.dept(), Types.VARCHAR).param("bf", b.faculty(), Types.VARCHAR).query(Boolean.class).single();
        if (!ok) throw new NotFound("preliminary or proficiency application", id);
        return id;
    }

    /* ── V701: the routes the desk serves ── */

    /** the preliminary and proficiency routes the office reads, with the session of each */
    @GetMapping("/routes")
    @PreAuthorize(CONFIG_READERS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> routes() {
        String o = office();
        return jdbc.sql("""
                SELECT p.route, p.name, p.programme_type, pt.label AS programme_type_label, p.office_code, o.label AS office, policy.route_session(p.route) AS session,
                       (SELECT cm.name FROM ref.campus cm WHERE cm.code = p.campus_code) AS campus, p.target_word, p.group_word
                  FROM admissions.prelim_programme p LEFT JOIN finance.programme_type pt ON pt.code = p.programme_type LEFT JOIN ref.office o ON o.code = p.office_code
                 WHERE NOT :own OR p.office_code = :o
                 ORDER BY (p.programme_type NOT IN ('PRELIMINARY', 'REMEDIAL', 'FOUNDATION')), pt.ord, p.name
                """).param("own", ROUTE_OFFICES.contains(o)).param("o", o).query().listOfRows();   // V721: the same rank as the default route
    }

    /* ── the dashboard ── */

    @GetMapping("/summary")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> summary(@RequestParam(required = false) String session, @RequestParam(required = false) String route) {
        String ROUTE = route(route);
        String s = session(session, ROUTE);
        Bound b = bound();
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("session", s);
        out.put("route", ROUTE);
        out.put("routeSession", session(null, ROUTE));
        out.put("sessions", jdbc.sql("""
                SELECT DISTINCT a.session FROM admissions.prelim_review r JOIN admissions.application a ON a.id = r.application_id WHERE r.route = :route
                UNION SELECT policy.route_session(:route) ORDER BY 1 DESC
                """).param("route", ROUTE).query(String.class).list());
        out.put("scope", Map.of("office", office(), "department", b.dept() == null ? "" : b.dept(), "faculty", b.faculty() == null ? "" : b.faculty(),
                "scoped", b.dept() != null || b.faculty() != null));
        out.put("stats", PrelimApplicantService.json(jdbc.sql("SELECT admissions.prelim_stats(:route, :s, :bd, :bf)::text")
                .param("route", ROUTE).param("s", s).param("bd", b.dept(), Types.VARCHAR).param("bf", b.faculty(), Types.VARCHAR).query(String.class).single()));
        out.put("window", jdbc.sql("SELECT state, opens_at, closes_at FROM policy.window_state((SELECT window_type FROM admissions.prelim_programme WHERE route = :route), :s, NULL)")
                .param("s", s).param("route", ROUTE).query().singleRow());
        out.put("fee", jdbc.sql("SELECT * FROM admissions.route_fee_rule(:s, :route)").param("s", s).param("route", ROUTE).query().listOfRows().stream().findFirst().orElse(null));
        out.put("missingTargets", jdbc.sql("SELECT count(*) FROM admissions.prelim_target WHERE route = :route AND state = 'MISSING'").param("route", ROUTE).query(Long.class).single());
        out.put("toPublish", jdbc.sql("""
                SELECT count(*) FROM admissions.prelim_review r JOIN admissions.application a ON a.id = r.application_id
                 WHERE r.route = :route AND a.session = :s AND r.published_at IS NULL AND r.state IN ('APPROVED', 'NOT_ADMITTED', 'REJECTED')
                """).param("route", ROUTE).param("s", s).query(Long.class).single());
        String own = officeOf(ROUTE);
        out.put("may", Map.of("review", Set.of(own, "academic", "super").contains(office()), "decide", Set.of("academic", "super").contains(office()),
                "recommend", Set.of(own, "super").contains(office()), "configure", Set.of("academic", "super").contains(office()),
                "fees", Set.of("bursar", "super").contains(office())));
        return out;
    }

    /* ── the applications ── */

    private static final String ROWS = """
            SELECT r.application_id AS id, a.application_no, c.surname, c.other_names, c.sex, r.target_programme, coalesce(p.name, t.requested_name) AS target_name,
                   p.dept_code, p.faculty_code, r.target_id, t.kind AS target_kind, t.group_name AS target_group, sp.name AS specialisation_name,
                   r.total_credits, r.core_credits, r.sittings, r.eligibility_status, r.remediation_status, r.remediation_subjects, r.olevel_verification,
                   a.fee_confirmed_at IS NOT NULL AS paid, a.fee_confirmed_at, r.state, r.published_at, r.submitted_at, a.session, a.created_at,
                   so.value AS state_of_origin, lg.value AS lga, acc.email, acc.phone
              FROM admissions.prelim_review r JOIN admissions.application a ON a.id = r.application_id
              JOIN admissions.candidate c ON c.id = a.candidate_id JOIN admissions.applicant_account acc ON acc.id = a.account_id
              LEFT JOIN admissions.prelim_target t ON t.id = r.target_id
              LEFT JOIN admissions.prelim_specialisation sp ON sp.id = r.specialisation_id
              LEFT JOIN ref.programme p ON p.code = r.target_programme
              LEFT JOIN admissions.screening_answer so ON so.application_id = a.id AND so.field = 'state_of_origin'
              LEFT JOIN admissions.screening_answer lg ON lg.application_id = a.id AND lg.field = 'lga'
             WHERE r.route = :route AND a.session = :s
               AND (:bd::text IS NULL OR p.dept_code = :bd) AND (:bf::text IS NULL OR p.faculty_code = :bf)
            """;

    private static final String FILTERS = """
             WHERE (:view::text IS NULL
                    OR (:view = 'total')
                    OR (:view = 'paid' AND x.paid)
                    OR (:view = 'submitted' AND x.submitted_at IS NOT NULL AND x.state <> 'WITHDRAWN')
                    OR (:view = 'incomplete' AND x.state = 'DRAFT')
                    OR (:view = 'pendingReview' AND x.state = 'SUBMITTED')
                    OR (:view = 'underReview' AND (x.state IN ('UNDER_REVIEW', 'CORRECTION_REQUIRED', 'RECOMMENDED', 'APPROVED')
                                                   OR (x.state IN ('NOT_ADMITTED', 'REJECTED') AND x.published_at IS NULL)))
                    OR (:view = 'correction' AND x.state = 'CORRECTION_REQUIRED')
                    OR (:view = 'eligible' AND x.submitted_at IS NOT NULL AND x.state <> 'WITHDRAWN' AND x.eligibility_status IN ('ELIGIBLE', 'ELIGIBLE_WITH_REMEDIATION'))
                    OR (:view = 'notEligible' AND x.submitted_at IS NOT NULL AND x.state <> 'WITHDRAWN' AND x.eligibility_status IN ('NOT_ELIGIBLE', 'RESULT_REQUIRED', 'INVALID_RESULT'))
                    OR (:view = 'remediationRequired' AND x.submitted_at IS NOT NULL AND x.state <> 'WITHDRAWN' AND x.remediation_status IN ('REQUIRED', 'IN_PROGRESS', 'NOT_COMPLETED', 'REQUIRES_REVIEW'))
                    OR (:view = 'admitted' AND x.state = 'ADMITTED')
                    OR (:view = 'notAdmitted' AND x.state IN ('NOT_ADMITTED', 'REJECTED') AND x.published_at IS NOT NULL)
                    OR (:view = 'withdrawn' AND x.state = 'WITHDRAWN'))
               AND (:q::text IS NULL OR lower(x.surname || ' ' || x.other_names) LIKE :q OR lower(x.other_names || ' ' || x.surname) LIKE :q
                    OR lower(x.application_no) LIKE :q OR lower(x.email) LIKE :q OR x.phone LIKE :q)
               AND (:target::text IS NULL OR x.target_programme = :target OR x.target_id::text = lower(:target))
               AND (:grp::text IS NULL OR x.target_group = :grp)
               AND (:sittings::int IS NULL OR coalesce(x.sittings, 0) = :sittings)
               AND (:eligibility::text IS NULL OR x.eligibility_status = :eligibility)
               AND (:remediation::text IS NULL OR x.remediation_status = :remediation)
               AND (:state::text IS NULL OR x.state = :state)
               AND (:paid::boolean IS NULL OR x.paid = :paid)
               AND (:sex::text IS NULL OR x.sex = :sex)
               AND (:origin::text IS NULL OR lower(x.state_of_origin) = lower(:origin))
               AND (:lga::text IS NULL OR lower(x.lga) = lower(:lga))
               AND (:from::date IS NULL OR x.submitted_at >= :from::date) AND (:to::date IS NULL OR x.submitted_at < (:to::date + 1))
            """;

    private static String code(String v, String pattern) {
        return v == null || v.isBlank() || !v.trim().toUpperCase().matches(pattern) ? null : v.trim().toUpperCase();
    }

    private static LocalDate day(String v) {
        try {
            return v == null || v.isBlank() ? null : LocalDate.parse(v.trim());
        } catch (java.time.format.DateTimeParseException e) {
            throw new DomainRuleViolation("PRELIM_DATE", "'" + v + "' is not a date.", new DomainRuleViolation.Remedy("Dates are YYYY-MM-DD.", "You"));
        }
    }

    @GetMapping("/applications")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> applications(@RequestParam(required = false) String session, @RequestParam(required = false) String view,
                                     @RequestParam(required = false) String q, @RequestParam(required = false) String target,
                                     @RequestParam(required = false) Integer sittings, @RequestParam(required = false) String eligibility,
                                     @RequestParam(required = false) String remediation, @RequestParam(required = false) String state,
                                     @RequestParam(required = false) Boolean paid, @RequestParam(required = false) String sex,
                                     @RequestParam(required = false) String origin, @RequestParam(required = false) String lga,
                                     @RequestParam(required = false) String from, @RequestParam(required = false) String to,
                                     @RequestParam(defaultValue = "0") int page, @RequestParam(defaultValue = "50") int size,
                                     @RequestParam(defaultValue = "number") String sort, @RequestParam(required = false) String route,
                                     @RequestParam(required = false) String group) {
        String ROUTE = route(route);
        String s = session(session, ROUTE);
        Bound b = bound();
        int sz = Math.max(1, Math.min(size, 5000));
        int pg = Math.max(0, page);
        String order = SORTS.getOrDefault(sort, SORTS.get("number"));
        String v = view != null && VIEWS.contains(view) ? view : null;
        String query = q == null || q.isBlank() ? null : "%" + q.trim().toLowerCase().replace("%", "") + "%";
        List<Map<String, Object>> rows = jdbc.sql("WITH x AS (" + ROWS + ") SELECT x.*, count(*) OVER () AS total_rows FROM x " + FILTERS
                        + " ORDER BY " + order + " LIMIT :n OFFSET :o")
                .param("route", ROUTE).param("s", s).param("bd", b.dept(), Types.VARCHAR).param("bf", b.faculty(), Types.VARCHAR)
                .param("view", v, Types.VARCHAR).param("q", query, Types.VARCHAR).param("target", code(target, "C[0-9]{5}|[0-9A-F-]{36}"), Types.VARCHAR)
                .param("grp", group == null || group.isBlank() ? null : group.trim(), Types.VARCHAR)
                .param("sittings", sittings, Types.INTEGER).param("eligibility", code(eligibility, "[A-Z_]{3,40}"), Types.VARCHAR)
                .param("remediation", code(remediation, "[A-Z_]{3,40}"), Types.VARCHAR).param("state", code(state, "[A-Z_]{3,40}"), Types.VARCHAR)
                .param("paid", paid, Types.BOOLEAN).param("sex", code(sex, "[MF]"), Types.VARCHAR)
                .param("origin", origin == null || origin.isBlank() ? null : origin.trim(), Types.VARCHAR).param("lga", lga == null || lga.isBlank() ? null : lga.trim(), Types.VARCHAR)
                .param("from", day(from), Types.DATE).param("to", day(to), Types.DATE)
                .param("n", sz).param("o", pg * sz).query().listOfRows();
        long total = rows.isEmpty() ? 0 : ((Number) rows.get(0).get("total_rows")).longValue();
        List<Map<String, Object>> out = new ArrayList<>();
        for (Map<String, Object> r : rows) {
            Map<String, Object> m = new LinkedHashMap<>(r);
            m.remove("total_rows");
            m.put("remediation_subjects", PrelimApplicantService.strings(r.get("remediation_subjects")));
            // the scoped readers see who applied and how they stand, never how to reach them
            if (b.dept() != null || b.faculty() != null) { m.remove("email"); m.remove("phone"); }
            out.add(m);
        }
        return Map.of("session", s, "total", total, "page", pg, "size", sz, "rows", out);
    }

    @GetMapping("/applications/{id}")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> application(@PathVariable UUID id) {
        within(id);
        Map<String, Object> out = new LinkedHashMap<>();
        Map<String, Object> a = jdbc.sql("""
                SELECT a.id, a.application_no, a.session, c.surname, c.other_names, c.sex, acc.email, acc.phone, a.created_at, a.fee_confirmed_at,
                       a.decision, a.decision_note, a.decision_released_at, a.next_of_kin
                  FROM admissions.application a JOIN admissions.candidate c ON c.id = a.candidate_id JOIN admissions.applicant_account acc ON acc.id = a.account_id
                 WHERE a.id = :a
                """).param("a", id).query().singleRow();
        Map<String, Object> app = new LinkedHashMap<>(a);
        if (!bound().equals(new Bound(null, null))) { app.remove("email"); app.remove("phone"); app.remove("next_of_kin"); }
        out.put("application", app);
        out.put("preliminary", prelim.block(id, true));
        out.put("documents", jdbc.sql("""
                SELECT d.id, d.kind, coalesce(q.label, d.kind) AS label, d.filename, d.content_type, d.bytes, d.uploaded_at, d.status, d.review_note, d.reviewed_at
                  FROM admissions.application_document d JOIN admissions.prelim_review r ON r.application_id = d.application_id
                  LEFT JOIN admissions.prelim_document q ON q.route = r.route AND q.kind = d.kind
                 WHERE d.application_id = :a AND d.superseded_at IS NULL ORDER BY coalesce(q.ord, 999), d.uploaded_at
                """).param("a", id).query().listOfRows());
        out.put("payments", jdbc.sql("""
                SELECT f.reference, f.kind, f.amount, f.generated_at, f.expires_at, f.confirmed_at, f.receipt_no, f.channel
                  FROM admissions.fee_reference f WHERE f.application_id = :a ORDER BY f.generated_at
                """).param("a", id).query().listOfRows());
        out.put("letter", jdbc.sql("""
                SELECT i.number, i.version, i.issued_on, i.verification_code FROM credentials.issued i
                 WHERE i.application_id = :a AND i.kind = 'ADMISSION_LETTER' ORDER BY i.version DESC LIMIT 1
                """).param("a", id).query().listOfRows().stream().findFirst().orElse(null));
        return out;
    }

    @GetMapping("/applications/{id}/documents/{documentId}/content")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    ResponseEntity<byte[]> documentContent(@PathVariable UUID id, @PathVariable UUID documentId) {
        within(id);
        boolean mine = jdbc.sql("SELECT EXISTS (SELECT 1 FROM admissions.application_document WHERE id = :d AND application_id = :a)")
                .param("d", documentId).param("a", id).query(Boolean.class).single();
        if (!mine) throw new NotFound("document", documentId);
        DocumentContent c = applicants.anyDocumentContent(documentId);
        return ResponseEntity.ok().contentType(MediaType.parseMediaType(c.contentType()))
                .header(HttpHeaders.CONTENT_DISPOSITION, "inline; filename=\"" + c.filename().replaceAll("[\"\\\\\\r\\n]", "_") + "\"")
                .header(HttpHeaders.CACHE_CONTROL, "no-store").body(c.content());
    }

    /* ── the review: every step checked again by the database function that performs it ── */

    record Act(@NotBlank @Size(max = 30) String action, @Size(max = 2000) String note) {
    }

    record Outcome(@NotBlank @Size(max = 20) String outcome, @Size(max = 2000) String note) {
    }

    record Review(@NotBlank @Size(max = 20) String status, @Size(max = 2000) String note) {
    }

    record Target(@Size(max = 20) String programmeCode, UUID targetId, UUID specialisationId, @NotBlank @Size(max = 2000) String note) {
    }

    record Publish(@Size(max = 20) String session, List<UUID> applicationIds, @Size(max = 40) String route) {
    }

    @PostMapping("/applications/{id}/act")
    @PreAuthorize(REVIEWERS)
    @Transactional
    Map<String, Object> act(@PathVariable UUID id, @Valid @RequestBody Act body) {
        AuditContextHolder.required();
        jdbc.sql("SELECT admissions.prelim_act(:a, :x, :n)").param("a", within(id)).param("x", body.action().trim().toUpperCase())
                .param("n", body.note(), Types.VARCHAR).query(String.class).single();
        return application(id);
    }

    @PostMapping("/applications/{id}/verify-olevel")
    @PreAuthorize(REVIEWERS)
    @Transactional
    Map<String, Object> verifyOlevel(@PathVariable UUID id, @Valid @RequestBody Outcome body) {
        AuditContextHolder.required();
        jdbc.sql("SELECT admissions.prelim_verify_olevel(:a, :o, :n)").param("a", within(id)).param("o", body.outcome().trim().toUpperCase())
                .param("n", body.note(), Types.VARCHAR).query(String.class).single();
        return application(id);
    }

    @PostMapping("/applications/{id}/documents/{documentId}/review")
    @PreAuthorize(REVIEWERS)
    @Transactional
    Map<String, Object> reviewDocument(@PathVariable UUID id, @PathVariable UUID documentId, @Valid @RequestBody Review body) {
        AuditContextHolder.required();
        within(id);
        boolean mine = jdbc.sql("SELECT EXISTS (SELECT 1 FROM admissions.application_document WHERE id = :d AND application_id = :a)")
                .param("d", documentId).param("a", id).query(Boolean.class).single();
        if (!mine) throw new NotFound("document", documentId);
        jdbc.sql("SELECT admissions.prelim_review_document(:d, :s, :n)").param("d", documentId).param("s", body.status().trim().toUpperCase())
                .param("n", body.note(), Types.VARCHAR).query(String.class).single();
        return application(id);
    }

    @PostMapping("/applications/{id}/target")
    @PreAuthorize(REVIEWERS)
    @Transactional
    Map<String, Object> target(@PathVariable UUID id, @Valid @RequestBody Target body) {
        AuditContextHolder.required();
        if (body.targetId() != null) {
            jdbc.sql("SELECT admissions.prelim_choose(:a, :t, :sp, :n)").param("a", within(id)).param("t", body.targetId())
                    .param("sp", body.specialisationId(), Types.OTHER).param("n", body.note()).query(String.class).single();
        } else {
            if (body.programmeCode() == null || body.programmeCode().isBlank()) {
                throw new DomainRuleViolation("PRELIM_TARGET_REQUIRED", "Name the target.", new DomainRuleViolation.Remedy("Choose a target programme or course.", "You"));
            }
            jdbc.sql("SELECT admissions.prelim_set_target(:a, :p, :n)").param("a", within(id)).param("p", body.programmeCode().trim().toUpperCase())
                    .param("n", body.note()).query(String.class).single();
        }
        return application(id);
    }

    @PostMapping("/applications/{id}/remediation")
    @PreAuthorize(REVIEWERS)
    @Transactional
    Map<String, Object> remediation(@PathVariable UUID id, @Valid @RequestBody Review body) {
        AuditContextHolder.required();
        jdbc.sql("SELECT admissions.prelim_set_remediation(:a, :s, :n)").param("a", within(id)).param("s", body.status().trim().toUpperCase())
                .param("n", body.note(), Types.VARCHAR).query(String.class).single();
        return application(id);
    }

    @PostMapping("/publish")
    @PreAuthorize(DECIDERS)
    @Transactional
    Map<String, Object> publish(@Valid @RequestBody Publish body) {
        AuditContextHolder.required();
        String ROUTE = route(body.route());
        String s = session(body.session(), ROUTE);
        boolean all = body.applicationIds() == null || body.applicationIds().isEmpty();
        var q = jdbc.sql("SELECT admissions.prelim_publish(:route, :s, " + (all ? "NULL::uuid[]" : ":ids") + ")::text").param("route", ROUTE).param("s", s);
        if (!all) q = q.param("ids", body.applicationIds().toArray(UUID[]::new));
        String result = q.query(String.class).single();
        return PrelimApplicantService.json(result);
    }

    /* ── the payments, the analysis ── */

    @GetMapping("/payments")
    @PreAuthorize(CENTRAL_READERS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> payments(@RequestParam(required = false) String session, @RequestParam(required = false) String status,
                                       @RequestParam(required = false) String route) {
        String ROUTE = route(route);
        String s = session(session, ROUTE);
        String st = status == null ? null : status.trim().toUpperCase();
        return jdbc.sql("""
                SELECT a.application_no, c.surname, c.other_names, f.reference, f.kind, f.amount, f.generated_at, f.expires_at, f.confirmed_at, f.receipt_no, f.channel,
                       CASE WHEN f.confirmed_at IS NOT NULL THEN 'PAID' WHEN f.expires_at <= now() THEN 'EXPIRED' ELSE 'PENDING' END AS status
                  FROM admissions.fee_reference f JOIN admissions.application a ON a.id = f.application_id
                  JOIN admissions.candidate c ON c.id = a.candidate_id JOIN admissions.prelim_review r ON r.application_id = a.id
                 WHERE r.route = :route AND a.session = :s
                   AND (:st::text IS NULL OR (:st = 'PAID' AND f.confirmed_at IS NOT NULL) OR (:st = 'PENDING' AND f.confirmed_at IS NULL AND f.expires_at > now())
                        OR (:st = 'EXPIRED' AND f.confirmed_at IS NULL AND f.expires_at <= now()))
                 ORDER BY f.generated_at DESC LIMIT 5000
                """).param("route", ROUTE).param("s", s).param("st", st, Types.VARCHAR).query().listOfRows();
    }

    /** the analysis behind the reports: by target programme, by sitting, by sex and by state of origin — counts only */
    @GetMapping("/analysis")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> analysis(@RequestParam(required = false) String session, @RequestParam(required = false) String route) {
        String ROUTE = route(route);
        String s = session(session, ROUTE);
        Bound b = bound();
        String base = "WITH x AS (" + ROWS + ") ";
        String measures = """
                count(*) FILTER (WHERE x.submitted_at IS NOT NULL AND x.state <> 'WITHDRAWN') AS submitted,
                count(*) FILTER (WHERE x.submitted_at IS NOT NULL AND x.state <> 'WITHDRAWN' AND x.eligibility_status IN ('ELIGIBLE', 'ELIGIBLE_WITH_REMEDIATION')) AS eligible,
                count(*) FILTER (WHERE x.submitted_at IS NOT NULL AND x.state <> 'WITHDRAWN' AND x.eligibility_status IN ('NOT_ELIGIBLE', 'RESULT_REQUIRED', 'INVALID_RESULT')) AS not_eligible,
                count(*) FILTER (WHERE x.submitted_at IS NOT NULL AND x.state <> 'WITHDRAWN' AND x.remediation_status IN ('REQUIRED', 'IN_PROGRESS', 'NOT_COMPLETED', 'REQUIRES_REVIEW')) AS remediation,
                count(*) FILTER (WHERE x.state = 'ADMITTED') AS admitted
                """;
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("session", s);
        for (String[] g : new String[][] {{"byTarget", "coalesce(x.target_programme, x.target_id::text) AS code, x.target_name AS label", "coalesce(x.target_programme, x.target_id::text), x.target_name"},
                                          {"byGroup", "x.target_group AS code, x.target_group AS label", "x.target_group"},
                                          {"bySpecialisation", "x.specialisation_name AS code, x.specialisation_name AS label", "x.specialisation_name"},
                                          {"bySittings", "coalesce(x.sittings, 0)::text AS code, coalesce(x.sittings, 0)::text AS label", "coalesce(x.sittings, 0)"},
                                          {"bySex", "x.sex AS code, x.sex AS label", "x.sex"},
                                          {"byState", "x.state_of_origin AS code, x.state_of_origin AS label", "x.state_of_origin"}}) {
            out.put(g[0], jdbc.sql(base + "SELECT " + g[1] + ", " + measures + " FROM x GROUP BY " + g[2] + " ORDER BY submitted DESC, 1")
                    .param("route", ROUTE).param("s", s).param("bd", b.dept(), Types.VARCHAR).param("bf", b.faculty(), Types.VARCHAR).query().listOfRows());
        }
        return out;
    }

    /* ── the configuration: the Academic Office's, the fee the Bursary's ── */

    @GetMapping("/config")
    @PreAuthorize(CONFIG_READERS)
    @Transactional(readOnly = true)
    Map<String, Object> config(@RequestParam(required = false) String route) {
        String ROUTE = route(route);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("route", ROUTE);
        Map<String, Object> p = new LinkedHashMap<>(jdbc.sql("SELECT * FROM admissions.prelim_programme WHERE route = :r").param("r", ROUTE).query().singleRow());
        for (String k : List.of("procedure", "core_subjects", "completion_subjects", "required_subjects", "qualification_types")) p.put(k, PrelimApplicantService.strings(p.get(k)));
        out.put("programme", p);
        String s = session(null, ROUTE);
        out.put("session", s);
        out.put("targets", jdbc.sql("""
                SELECT t.id, t.kind, t.group_name, t.ord, t.requested_name, t.programme_code, t.state, t.note, t.added_at, t.updated_at,
                       t.core_subjects, t.min_core_credits, t.description, t.duration_months,
                       p.name AS register_name, d.name AS department, f.name AS faculty, p.archived,
                       (SELECT count(*) FROM admissions.prelim_review r WHERE r.route = t.route AND r.target_id = t.id) AS applications,
                       (SELECT coalesce(jsonb_agg(jsonb_build_object('id', sp.id, 'code', sp.code, 'name', sp.name, 'ord', sp.ord, 'active', sp.active) ORDER BY sp.ord, sp.name), '[]'::jsonb)::text
                          FROM admissions.prelim_specialisation sp WHERE sp.target_id = t.id) AS specialisations
                  FROM admissions.prelim_target t LEFT JOIN ref.programme p ON p.code = t.programme_code
                  LEFT JOIN ref.department d ON d.code = p.dept_code LEFT JOIN ref.faculty f ON f.code = p.faculty_code
                 WHERE t.route = :r ORDER BY t.ord, t.requested_name
                """).param("r", ROUTE).query().listOfRows().stream().map(t -> {
                    Map<String, Object> m = new LinkedHashMap<>(t);
                    m.put("core_subjects", t.get("core_subjects") == null ? null : PrelimApplicantService.strings(t.get("core_subjects")));
                    m.put("specialisations", PrelimApplicantService.json(t.get("specialisations")));
                    return m;
                }).toList());
        out.put("qualificationTypes", jdbc.sql("SELECT code, label, active FROM admissions.qualification_type ORDER BY ord").query().listOfRows());
        out.put("documents", jdbc.sql("SELECT kind, label, hint, required, second_sitting_only, ord FROM admissions.prelim_document WHERE route = :r ORDER BY ord").param("r", ROUTE).query().listOfRows());
        out.put("fee", jdbc.sql("SELECT * FROM admissions.route_fee_rule(:s, :r)").param("s", s).param("r", ROUTE).query().listOfRows().stream().findFirst().orElse(null));
        out.put("window", jdbc.sql("SELECT state, opens_at, closes_at, configured FROM policy.window_state((SELECT window_type FROM admissions.prelim_programme WHERE route = :r), :s, NULL)")
                .param("s", s).param("r", ROUTE).query().singleRow());
        return out;
    }

    record Rules(@NotNull Map<String, Object> settings, @NotBlank @Size(max = 500) String reason) {
    }

    record NewTarget(@NotBlank @Size(max = 20) String programmeCode, @Size(max = 80) String group, Integer ord, @NotBlank @Size(max = 500) String reason) {
    }

    record ChangeTarget(@NotBlank @Size(max = 20) String action, @Size(max = 20) String programmeCode, @NotBlank @Size(max = 500) String reason) {
    }

    record Doc(@NotBlank @Size(max = 120) String label, @Size(max = 400) String hint, Boolean required, Boolean secondSittingOnly, Integer ord,
               @NotBlank @Size(max = 500) String reason) {
    }

    record Fee(@Size(max = 20) String session, @NotNull BigDecimal applicationFee, BigDecimal acceptanceFee, BigDecimal checkingFee) {
    }

    @PutMapping("/config/rules")
    @PreAuthorize(DECIDERS)
    @Transactional
    Map<String, Object> rules(@Valid @RequestBody Rules body, @RequestParam(required = false) String route) {
        AuditContextHolder.required();
        String ROUTE = route(route);
        int n = jdbc.sql("SELECT admissions.prelim_set_rules(:r, :s::jsonb, :why)").param("r", ROUTE)
                .param("s", new tools.jackson.databind.ObjectMapper().writeValueAsString(body.settings())).param("why", body.reason()).query(Integer.class).single();
        Map<String, Object> out = config(ROUTE);
        out.put("reevaluated", n);
        return out;
    }

    @PostMapping("/config/targets")
    @PreAuthorize(DECIDERS)
    @Transactional
    Map<String, Object> addTarget(@Valid @RequestBody NewTarget body, @RequestParam(required = false) String route) {
        AuditContextHolder.required();
        String ROUTE = route(route);
        jdbc.sql("SELECT admissions.prelim_add_target(:r, :p, :g, :o, :why)").param("r", ROUTE).param("p", body.programmeCode().trim().toUpperCase())
                .param("g", body.group(), Types.VARCHAR).param("o", body.ord(), Types.INTEGER).param("why", body.reason()).query(UUID.class).single();
        return config(ROUTE);
    }

    @PostMapping("/config/targets/{id}")
    @PreAuthorize(DECIDERS)
    @Transactional
    Map<String, Object> changeTarget(@PathVariable UUID id, @Valid @RequestBody ChangeTarget body) {
        AuditContextHolder.required();
        String ROUTE = targetRoute(id);
        jdbc.sql("SELECT admissions.prelim_change_target(:t, :a, :p, :why)").param("t", id).param("a", body.action().trim().toUpperCase())
                .param("p", body.programmeCode() == null ? null : body.programmeCode().trim().toUpperCase(), Types.VARCHAR).param("why", body.reason()).query(String.class).single();
        return config(ROUTE);
    }

    @PutMapping("/config/documents/{kind}")
    @PreAuthorize(DECIDERS)
    @Transactional
    Map<String, Object> document(@PathVariable String kind, @Valid @RequestBody Doc body, @RequestParam(required = false) String route) {
        AuditContextHolder.required();
        String ROUTE = route(route);
        jdbc.sql("SELECT admissions.prelim_set_document(:r, :k, :l, :h, :req, :two, :o, :why)").param("r", ROUTE).param("k", kind.trim().toUpperCase())
                .param("l", body.label()).param("h", body.hint(), Types.VARCHAR).param("req", body.required(), Types.BOOLEAN)
                .param("two", body.secondSittingOnly(), Types.BOOLEAN).param("o", body.ord(), Types.INTEGER).param("why", body.reason()).query().singleRow();
        return config(ROUTE);
    }

    @PutMapping("/config/fee")
    @PreAuthorize(FEE_SETTERS)
    @Transactional
    Map<String, Object> fee(@Valid @RequestBody Fee body, @RequestParam(required = false) String route) {
        AuditContextHolder.required();
        String ROUTE = route(route);
        jdbc.sql("SELECT admissions.set_route_fee(:s, :r, :a, 0, :acc, :chk)").param("s", session(body.session(), ROUTE)).param("r", ROUTE)
                .param("a", body.applicationFee()).param("acc", body.acceptanceFee(), Types.NUMERIC).param("chk", body.checkingFee(), Types.NUMERIC).query().singleRow();
        return config(ROUTE);
    }

    /** the undergraduate programmes a target may be chosen from, searched on the server */
    @GetMapping("/programmes")
    @PreAuthorize(DECIDERS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> programmes(@RequestParam(required = false) String q, @RequestParam(required = false) String route) {
        String ROUTE = route(route);
        String query = q == null || q.isBlank() ? null : "%" + q.trim().toLowerCase().replace("%", "") + "%";
        return jdbc.sql("""
                SELECT p.code, p.name, d.name AS department, f.name AS faculty,
                       EXISTS (SELECT 1 FROM admissions.prelim_target t WHERE t.route = :r AND t.programme_code = p.code AND t.state = 'MAPPED') AS target
                  FROM ref.programme p JOIN ref.department d ON d.code = p.dept_code AND d.ended_on IS NULL JOIN ref.faculty f ON f.code = p.faculty_code
                 WHERE NOT p.archived AND p.category = 'UNDER GRADUATE'
                   AND (:q::text IS NULL OR lower(p.name) LIKE :q OR lower(p.code) LIKE :q OR lower(d.name) LIKE :q OR lower(f.name) LIKE :q)
                 ORDER BY f.name, d.name, p.name LIMIT 200
                """).param("r", ROUTE).param("q", query, Types.VARCHAR).query().listOfRows();
    }

    /* ── V701: certificate courses, an area's own subjects, a target programme's options ── */

    private String targetRoute(UUID target) {
        String r = jdbc.sql("SELECT route FROM admissions.prelim_target WHERE id = :t").param("t", target).query(String.class).optional()
                .orElseThrow(() -> new NotFound("target", target));
        return route(r);
    }

    record NewCourse(@NotBlank @Size(max = 150) String name, @NotBlank @Size(max = 80) String category, Integer ord, @Size(max = 2000) String description,
                     Integer durationMonths, @NotBlank @Size(max = 500) String reason) {
    }

    record TargetRule(List<@Size(max = 60) String> coreSubjects, Integer minCoreCredits, @NotBlank @Size(max = 500) String reason) {
    }

    record Option(@Size(max = 120) String name, Integer ord, Boolean active, @NotBlank @Size(max = 500) String reason) {
    }

    @PostMapping("/config/courses")
    @PreAuthorize(DECIDERS)
    @Transactional
    Map<String, Object> addCourse(@Valid @RequestBody NewCourse body, @RequestParam(required = false) String route) {
        AuditContextHolder.required();
        String ROUTE = route(route);
        jdbc.sql("SELECT admissions.prelim_add_course(:r, :n, :g, :o, :d, :m, :why)").param("r", ROUTE).param("n", body.name()).param("g", body.category())
                .param("o", body.ord(), Types.INTEGER).param("d", body.description(), Types.VARCHAR).param("m", body.durationMonths(), Types.INTEGER)
                .param("why", body.reason()).query(UUID.class).single();
        return config(ROUTE);
    }

    @PutMapping("/config/targets/{id}/rule")
    @PreAuthorize(DECIDERS)
    @Transactional
    Map<String, Object> targetRule(@PathVariable UUID id, @Valid @RequestBody TargetRule body) {
        AuditContextHolder.required();
        String ROUTE = targetRoute(id);
        String[] subjects = body.coreSubjects() == null || body.coreSubjects().isEmpty() ? null : body.coreSubjects().toArray(String[]::new);
        int n = jdbc.sql("SELECT admissions.prelim_set_target_rule(:t, :c, :m, :why)").param("t", id).param("c", subjects, Types.ARRAY)
                .param("m", body.minCoreCredits(), Types.INTEGER).param("why", body.reason()).query(Integer.class).single();
        Map<String, Object> out = config(ROUTE);
        out.put("reevaluated", n);
        return out;
    }

    @PutMapping("/config/targets/{id}/specialisations/{code}")
    @PreAuthorize(DECIDERS)
    @Transactional
    Map<String, Object> option(@PathVariable UUID id, @PathVariable String code, @Valid @RequestBody Option body) {
        AuditContextHolder.required();
        String ROUTE = targetRoute(id);
        jdbc.sql("SELECT admissions.prelim_save_specialisation(:t, :c, :n, :o, :a, :why)").param("t", id).param("c", code.trim().toUpperCase())
                .param("n", body.name(), Types.VARCHAR).param("o", body.ord(), Types.INTEGER).param("a", body.active(), Types.BOOLEAN)
                .param("why", body.reason()).query(UUID.class).single();
        return config(ROUTE);
    }
}
