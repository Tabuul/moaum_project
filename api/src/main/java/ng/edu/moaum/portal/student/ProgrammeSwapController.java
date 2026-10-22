package ng.edu.moaum.portal.student;

import java.sql.Types;
import java.util.ArrayList;
import java.util.Base64;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;

import ng.edu.moaum.portal.shared.AuditContextHolder;
import ng.edu.moaum.portal.shared.DomainRuleViolation;
import ng.edu.moaum.portal.shared.FigureCache;
import ng.edu.moaum.portal.shared.FileObjects;
import ng.edu.moaum.portal.shared.NotFound;
import ng.edu.moaum.portal.shared.OfficeScope;

import org.springframework.dao.DataAccessException;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.transaction.PlatformTransactionManager;
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
 * Programme swap (V578): a migrated student's current programme, department, faculty and level corrected by an office, the old
 * placement kept. The desk reads the records whose placement looks wrong (people.programme_mismatches, through the figure cache:
 * the detector reads the whole register in a few seconds), and an officer makes a swap after the check (people.programme_swap_check):
 * since V633 the officer who initiates it decides it — people.prepare_programme_swap decides the swap at once, and the student is on
 * the new programme when the call returns. A swap left pending from before V633 is decided (/{id}/decide, /batches/{batch}/decide)
 * by any officer who may make one. The student's own scope rule (StudentReach) holds on every student named. Nothing here writes
 * to the student but people.decide_programme_swap.
 */
@RestController
@RequestMapping("/api/v1/programme-swaps")
class ProgrammeSwapController {

    private static final String READERS = "hasAnyAuthority('OFFICE_academic','OFFICE_ict','OFFICE_registrar','OFFICE_dregistrar','OFFICE_records',"
            + "'OFFICE_super','OFFICE_admin','OFFICE_audit','OFFICE_deputyaudit','OFFICE_vc','OFFICE_dvc')";
    private static final String PREPARERS = "hasAnyAuthority('OFFICE_academic','OFFICE_ict','OFFICE_registrar','OFFICE_dregistrar','OFFICE_super')";
    /** V633: who may make a swap decides one left pending — people.programme_swap_office_decides holds the rule */
    private static final String DECIDERS = "hasAnyAuthority('OFFICE_academic','OFFICE_ict','OFFICE_registrar','OFFICE_dregistrar','OFFICE_super')";
    static final Set<String> EVIDENCE_TYPES = Set.of("application/pdf", "image/jpeg", "image/png");
    static final Set<String> KINDS = Set.of("LEGACY_MIGRATION_CORRECTION", "PROGRAMME_CORRECTION", "ACADEMIC_TRANSFER");

    private final JdbcClient jdbc;
    private final OfficeScope scope;
    private final StudentReach reach;
    private final FileObjects files;
    private final FigureCache figures;
    private final TransactionTemplate tx;
    private final tools.jackson.databind.ObjectMapper json;
    /** the figure-cache keys this desk has used, forgotten together when a review or a swap changes what they count */
    private final Set<Object> cached = ConcurrentHashMap.newKeySet();

    ProgrammeSwapController(JdbcClient jdbc, OfficeScope scope, StudentReach reach, FileObjects files, FigureCache figures,
                            PlatformTransactionManager transactions, tools.jackson.databind.ObjectMapper json) {
        this.jdbc = jdbc;
        this.scope = scope;
        this.reach = reach;
        this.files = files;
        this.figures = figures;
        this.tx = new TransactionTemplate(transactions);
        this.json = json;
    }

    record Check(UUID studentId, String toProgramme, Integer toLevel, String session) { }
    record Prepare(UUID studentId, String toProgramme, Integer toLevel, String session, String kind, String reason) { }
    record Bulk(List<UUID> studentIds, String toProgramme, Integer toLevel, String session, String kind, String reason) { }
    record Decision(Boolean approve, String note) { }
    record Reason(String reason) { }
    record Review(String status, String note) { }
    record Evidence(String filename, String dataUrl) { }

    private static String office() {
        return AuditContextHolder.current().map(c -> c.actorOffice()).orElse("");
    }

    private Map<String, Object> jsonOf(String text) {
        return json.readValue(text, new tools.jackson.core.type.TypeReference<Map<String, Object>>() { });
    }

    private void forget() {
        for (Object k : cached) figures.forget(k);
        cached.clear();
    }

    /** a row's jsonb columns (the review points, the registration impact) as JSON values, not the driver's wrapper */
    private Map<String, Object> unwrapped(Map<String, Object> row) {
        Map<String, Object> out = new LinkedHashMap<>(row);
        for (Map.Entry<String, Object> e : out.entrySet()) {
            if (e.getValue() instanceof org.postgresql.util.PGobject pg && pg.getValue() != null && ("jsonb".equals(pg.getType()) || "json".equals(pg.getType()))) {
                e.setValue(json.readValue(pg.getValue(), Object.class));
            }
        }
        return out;
    }

    /* ── the desk: what needs doing ── */

    @GetMapping("/summary")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> summary(@RequestParam(required = false) String fac, @RequestParam(required = false) String dept,
                                @RequestParam(required = false) boolean refresh) {
        OfficeScope.Bound b = scope.bound(fac, dept, null);
        Object key = List.of("programme-swap-summary", String.valueOf(b.fac()), String.valueOf(b.dept()));
        cached.add(key);
        FigureCache.Answer<String> a = figures.get(key, refresh, () -> jdbc.sql("""
                WITH m AS (SELECT classification, review_status FROM people.programme_mismatches(:fac, :dept, NULL)),
                x AS (SELECT status, executed_at FROM people.programme_swap x
                       WHERE (:fac::text IS NULL OR :fac IN (x.from_faculty, x.to_faculty)) AND (:dept::text IS NULL OR :dept IN (x.from_dept, x.to_dept)))
                SELECT json_build_object(
                    'requiring', (SELECT count(*) FROM m WHERE review_status NOT IN ('SWAPPED', 'NO_ACTION_REQUIRED')),
                    'confirmed', (SELECT count(*) FROM m WHERE classification = 'CONFIRMED' AND review_status NOT IN ('SWAPPED', 'NO_ACTION_REQUIRED')),
                    'possible', (SELECT count(*) FROM m WHERE classification = 'POSSIBLE' AND review_status NOT IN ('SWAPPED', 'NO_ACTION_REQUIRED')),
                    'requiresReview', (SELECT count(*) FROM m WHERE (classification = 'REQUIRES_REVIEW' OR review_status IN ('REQUIRES_DOCUMENTATION', 'UNDER_REVIEW'))
                                                                 AND review_status NOT IN ('SWAPPED', 'NO_ACTION_REQUIRED')),
                    'swapRequired', (SELECT count(*) FROM m WHERE review_status = 'SWAP_REQUIRED'),
                    'noAction', (SELECT count(*) FROM m WHERE review_status = 'NO_ACTION_REQUIRED'),
                    'pending', (SELECT count(*) FROM x WHERE status = 'PENDING_APPROVAL'),
                    'completed', (SELECT count(*) FROM x WHERE status = 'COMPLETED'),
                    'rejected', (SELECT count(*) FROM x WHERE status = 'REJECTED'),
                    'failed', (SELECT count(*) FROM x WHERE status IN ('FAILED', 'CANCELLED')),
                    'recent', (SELECT count(*) FROM x WHERE status = 'COMPLETED' AND executed_at >= now() - interval '7 days'))::text
                """).param("fac", b.fac(), Types.VARCHAR).param("dept", b.dept(), Types.VARCHAR).query(String.class).single());
        Map<String, Object> out = new LinkedHashMap<>(jsonOf(a.value()));
        out.put("asOf", a.at());
        out.put("refreshing", a.refreshing());
        out.put("prepares", jdbc.sql("SELECT people.programme_swap_office_prepares(:o)").param("o", office()).query(Boolean.class).single());
        out.put("decides", jdbc.sql("SELECT people.programme_swap_office_decides(:o, 'PROGRAMME_CORRECTION')").param("o", office()).query(Boolean.class).single());
        return out;
    }

    /** the records whose placement looks wrong, within the scope; filtered and paged here from the cached detector run */
    @GetMapping("/mismatches")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> mismatches(@RequestParam(required = false) String fac, @RequestParam(required = false) String dept,
                                   @RequestParam(required = false) String prog, @RequestParam(required = false, name = "class") String klass,
                                   @RequestParam(required = false) String review, @RequestParam(required = false) String q,
                                   @RequestParam(required = false) Integer level, @RequestParam(required = false) String status,
                                   @RequestParam(defaultValue = "0") int page, @RequestParam(defaultValue = "50") int size,
                                   @RequestParam(required = false) boolean refresh) {
        OfficeScope.Bound b = scope.bound(fac, dept, prog);
        Object key = List.of("programme-swap-mismatches", String.valueOf(b.fac()), String.valueOf(b.dept()), String.valueOf(b.prog()));
        cached.add(key);
        FigureCache.Answer<String> a = figures.get(key, refresh, () -> jdbc.sql("""
                SELECT coalesce(json_agg(m ORDER BY CASE m.classification WHEN 'CONFIRMED' THEN 0 WHEN 'REQUIRES_REVIEW' THEN 1 ELSE 2 END, m.surname, m.other_names), '[]'::json)::text
                  FROM people.programme_mismatches(:fac, :dept, :prog) m
                """).param("fac", b.fac(), Types.VARCHAR).param("dept", b.dept(), Types.VARCHAR).param("prog", b.prog(), Types.VARCHAR).query(String.class).single());
        List<Map<String, Object>> all = json.readValue(a.value(), new tools.jackson.core.type.TypeReference<List<Map<String, Object>>>() { });
        String needle = q == null ? "" : q.trim().toLowerCase();
        List<Map<String, Object>> rows = all.stream()
                .filter(r -> klass == null || klass.isBlank() || klass.equals(r.get("classification")))
                .filter(r -> review == null || review.isBlank() || review.equals(r.get("review_status")))
                .filter(r -> level == null || level.equals(r.get("current_level")))
                .filter(r -> status == null || status.isBlank() || status.equals(r.get("status")))
                .filter(r -> needle.isEmpty() || String.join(" ", String.valueOf(r.get("surname")), String.valueOf(r.get("other_names")), String.valueOf(r.get("matric_no")),
                        String.valueOf(r.get("jamb_reg_no")), String.valueOf(r.get("programme"))).toLowerCase().contains(needle))
                .toList();
        int per = Math.max(1, Math.min(size, 500));
        int from = Math.max(0, page) * per;
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("rows", from >= rows.size() ? List.of() : rows.subList(from, Math.min(rows.size(), from + per)));
        out.put("total", rows.size());
        out.put("page", page);
        out.put("size", per);
        out.put("asOf", a.at());
        out.put("refreshing", a.refreshing());
        return out;
    }

    @PostMapping("/mismatches/{id}/review")
    @PreAuthorize(PREPARERS)
    @Transactional
    Map<String, Object> review(@PathVariable UUID id, @RequestBody Review body) {
        reach.check(id);
        jdbc.sql("SELECT people.set_programme_mismatch_review(:s, :st, :n)").param("s", id).param("st", body.status(), Types.VARCHAR)
                .param("n", body.note(), Types.VARCHAR).query().listOfRows();
        forget();
        return jdbc.sql("SELECT student_id, status, note, reviewed_office, reviewed_at, helpdesk.person_name(reviewed_by) AS reviewed_by FROM people.programme_mismatch_review WHERE student_id = :s")
                .param("s", id).query().singleRow();
    }

    /** the structure to choose from: every faculty, its departments, their programmes on the register with their own levels */
    @GetMapping("/structure")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> structure() {
        return jsonOf(jdbc.sql("""
                SELECT json_build_object('faculties', coalesce(json_agg(f ORDER BY f.name), '[]'::json))::text FROM (
                    SELECT f.code, f.name,
                           (SELECT coalesce(json_agg(d ORDER BY d.name), '[]'::json) FROM (
                               SELECT d.code, d.name,
                                      (SELECT coalesce(json_agg(p ORDER BY p.name), '[]'::json) FROM (
                                          SELECT p.code, p.name, p.category, people.programme_levels(p.code) AS levels
                                            FROM ref.programme p WHERE p.dept_code = d.code AND NOT p.archived) p) AS programmes
                                 FROM ref.department d WHERE d.faculty_code = f.code) d) AS departments
                      FROM ref.faculty f) f
                """).query(String.class).single());
    }

    /* ── one student ── */

    @GetMapping("/students/{id}")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> student(@PathVariable UUID id) {
        reach.check(id);
        String text = jdbc.sql("""
                SELECT json_build_object(
                    'student', (SELECT row_to_json(x) FROM (
                        SELECT s.id, s.surname, s.other_names, s.matric_no, s.jamb_reg_no, s.admission_no, s.status, s.entry_mode, s.study_mode, s.entry_session,
                               s.entry_level, s.current_level, s.centre_code, s.programme_code, p.name AS programme, p.category, p.dept_code, d.name AS department,
                               p.faculty_code, f.name AS faculty, people.programme_levels(p.code) AS levels,
                               (SELECT pt.label FROM finance.programme_type pt WHERE pt.code = finance.programme_type_for(s.entry_mode, p.category)) AS programme_type
                          FROM people.student s LEFT JOIN ref.programme p ON p.code = s.programme_code
                          LEFT JOIN ref.department d ON d.code = p.dept_code LEFT JOIN ref.faculty f ON f.code = p.faculty_code WHERE s.id = :s) x),
                    'session', policy.university_current_session(),
                    'sessions', (SELECT coalesce(json_agg(a.name ORDER BY a.starts_on DESC), '[]'::json) FROM policy.academic_session a
                                  WHERE a.state NOT IN ('DRAFT', 'CANCELLED') AND a.name ~ '^[0-9]{4}/[0-9]{4}$'),
                    'history', (SELECT coalesce(json_agg(h ORDER BY h.at NULLS FIRST), '[]'::json) FROM people.programme_history(:s) h),
                    'openTransfer', (SELECT row_to_json(t) FROM (SELECT ta.state, ta.to_programme_code, ta.applied_at FROM people.transfer_application ta
                                                                   WHERE ta.student_id = :s AND ta.state IN ('APPLIED', 'FROM_OK', 'TO_OK', 'REG_OK', 'APPROVED', 'RECOMMENDED')
                                                                   ORDER BY ta.applied_at DESC LIMIT 1) t),
                    'pendingSwap', (SELECT row_to_json(t) FROM (SELECT x.id, x.swap_ref, x.to_programme, x.to_level, x.prepared_at FROM people.programme_swap x
                                                                  WHERE x.student_id = :s AND x.status = 'PENDING_APPROVAL') t),
                    'swaps', (SELECT coalesce(json_agg(t ORDER BY t.prepared_at DESC), '[]'::json) FROM (
                                  SELECT x.id, x.swap_ref, x.status, x.kind, x.from_programme, x.from_level, x.to_programme, x.to_level, x.prepared_at, x.decided_at
                                    FROM people.programme_swap x WHERE x.student_id = :s) t),
                    'signals', (SELECT row_to_json(t) FROM (
                        SELECT CASE WHEN s.matric_no ~ '^[A-Z]+/[A-Z]+/[A-Z]+/' THEN split_part(s.matric_no, '/', 3) END AS matric_segment,
                               coalesce(p.matric_code, (SELECT split_part(s2.matric_no, '/', 3) FROM people.student s2
                                                          WHERE s2.programme_code = s.programme_code AND s2.status IN ('ACTIVE', 'PROBATION', 'ADMITTED') AND s2.matric_no ~ '^[A-Z]+/[A-Z]+/[A-Z]+/'
                                                          GROUP BY 1 ORDER BY count(*) DESC, 1 LIMIT 1)) AS programme_segment,
                               (SELECT json_build_object('dept', q.dept_code, 'department', dd.name, 'share', round(q.share, 2)) FROM (
                                    SELECT c.dept_code, count(*)::numeric / sum(count(*)) OVER () AS share
                                      FROM registration.course_registration r JOIN registration.entry e ON e.registration_id = r.id AND e.status IN ('REGISTERED', 'APPROVED')
                                      JOIN catalogue.offering o ON o.id = e.offering_id JOIN catalogue.course c ON c.code = o.course_code
                                     WHERE r.id = (SELECT r2.id FROM registration.course_registration r2 WHERE r2.student_id = s.id AND r2.status IN ('APPROVED', 'LOCKED')
                                                    ORDER BY r2.session DESC, r2.semester DESC LIMIT 1)
                                       AND c.kind NOT IN ('GST', 'EPS') AND c.dept_code IS NOT NULL
                                     GROUP BY c.dept_code ORDER BY count(*) DESC, c.dept_code LIMIT 1) q LEFT JOIN ref.department dd ON dd.code = q.dept_code) AS registration,
                               (SELECT json_build_object('code', c.programme, 'name', ap.name) FROM admissions.candidate c LEFT JOIN ref.programme ap ON ap.code = c.programme
                                 WHERE c.id = s.candidate_id) AS admitted
                          FROM people.student s LEFT JOIN ref.programme p ON p.code = s.programme_code WHERE s.id = :s) t),
                    'review', (SELECT row_to_json(t) FROM (SELECT rv.status, rv.note, rv.reviewed_at, rv.reviewed_office, helpdesk.person_name(rv.reviewed_by) AS reviewed_by
                                                              FROM people.programme_mismatch_review rv WHERE rv.student_id = :s) t)
                )::text
                """).param("s", id).query(String.class).optional().orElseThrow(() -> new NotFound("student", id));
        Map<String, Object> out = jsonOf(text);
        if (out.get("student") == null) throw new NotFound("student", id);
        return out;
    }

    @PostMapping("/check")
    @PreAuthorize(PREPARERS)
    @Transactional(readOnly = true)
    Map<String, Object> check(@RequestBody Check body) {
        if (body.studentId() == null) throw new DomainRuleViolation("PSW_STUDENT", "Name the student.", new DomainRuleViolation.Remedy("Choose a student.", "You"));
        reach.check(body.studentId());
        return jsonOf(jdbc.sql("SELECT people.programme_swap_check(:s, :p, :l, :ses, NULL)::text")
                .param("s", body.studentId()).param("p", body.toProgramme(), Types.VARCHAR).param("l", body.toLevel(), Types.INTEGER)
                .param("ses", body.session(), Types.VARCHAR).query(String.class).single());
    }

    @PostMapping
    @PreAuthorize(PREPARERS)
    @Transactional
    Map<String, Object> prepare(@RequestBody Prepare body) {
        if (body.studentId() == null) throw new DomainRuleViolation("PSW_STUDENT", "Name the student.", new DomainRuleViolation.Remedy("Choose a student.", "You"));
        reach.check(body.studentId());
        UUID id = jdbc.sql("SELECT people.prepare_programme_swap(:s, :p, :l, :ses, :k, :r, NULL)")
                .param("s", body.studentId()).param("p", body.toProgramme(), Types.VARCHAR).param("l", body.toLevel(), Types.INTEGER)
                .param("ses", body.session(), Types.VARCHAR).param("k", body.kind(), Types.VARCHAR).param("r", body.reason(), Types.VARCHAR)
                .query(UUID.class).single();
        forget();
        return detail(id);
    }

    /** many students onto one programme and level, each checked and made on its own, at once (a refusal skips that student alone) */
    @PostMapping("/bulk")
    @PreAuthorize(PREPARERS)
    @Transactional
    Map<String, Object> bulk(@RequestBody Bulk body) {
        if (body.studentIds() == null || body.studentIds().isEmpty()) {
            throw new DomainRuleViolation("PSW_STUDENT", "Choose the students to swap.", new DomainRuleViolation.Remedy("Tick at least one.", "You"));
        }
        if (body.studentIds().size() > 500) {
            throw new DomainRuleViolation("PSW_BULK_SIZE", "A bulk swap takes up to 500 students at once.", new DomainRuleViolation.Remedy("Split the list.", "You"));
        }
        UUID batch = UUID.randomUUID();
        List<UUID> ids = body.studentIds().stream().distinct().toList();
        return tx.execute(st -> {
            List<Map<String, Object>> done = new ArrayList<>();
            List<Map<String, Object>> skipped = new ArrayList<>();
            for (UUID student : ids) {
                Object sp = st.createSavepoint();
                try {
                    reach.check(student);
                    UUID id = jdbc.sql("SELECT people.prepare_programme_swap(:s, :p, :l, :ses, :k, :r, :b)")
                            .param("s", student).param("p", body.toProgramme(), Types.VARCHAR).param("l", body.toLevel(), Types.INTEGER)
                            .param("ses", body.session(), Types.VARCHAR).param("k", body.kind(), Types.VARCHAR).param("r", body.reason(), Types.VARCHAR)
                            .param("b", batch).query(UUID.class).single();
                    st.releaseSavepoint(sp);
                    Map<String, Object> row = jdbc.sql("SELECT id, swap_ref, student_id, from_programme, from_level, to_programme, to_level, review, status, failure FROM people.programme_swap WHERE id = :id")
                            .param("id", id).query().singleRow();
                    done.add(unwrapped(row));
                } catch (DataAccessException | DomainRuleViolation | AccessDeniedException e) {
                    st.rollbackToSavepoint(sp);
                    skipped.add(skip(student, e));
                }
            }
            forget();
            Map<String, Object> out = new LinkedHashMap<>();
            out.put("batchId", batch);
            out.put("prepared", done);
            out.put("skipped", skipped);
            return out;
        });
    }

    private Map<String, Object> skip(UUID student, Exception e) {
        String message = e.getMessage() == null ? e.getClass().getSimpleName() : e.getMessage();
        if (e instanceof DataAccessException dae && dae.getMostSpecificCause() != null && dae.getMostSpecificCause().getMessage() != null) {
            message = dae.getMostSpecificCause().getMessage();
        }
        Map<String, Object> row = jdbc.sql("SELECT s.id AS student_id, s.surname || ', ' || s.other_names AS student, s.matric_no FROM people.student s WHERE s.id = :s")
                .param("s", student).query().listOfRows().stream().findFirst().orElse(new LinkedHashMap<>(Map.of("student_id", student)));
        Map<String, Object> out = new LinkedHashMap<>(row);
        out.put("why", message.replaceFirst("^[A-Z][A-Z0-9_]{3,60}: ", "").split("\n")[0]);
        return out;
    }

    /* ── the swaps ── */

    @GetMapping
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> list(@RequestParam(required = false) String status, @RequestParam(required = false) String session,
                                   @RequestParam(required = false) String fac, @RequestParam(required = false) String dept,
                                   @RequestParam(required = false) String from, @RequestParam(required = false) String to,
                                   @RequestParam(required = false) Integer level, @RequestParam(required = false) String kind,
                                   @RequestParam(required = false) String fromDate, @RequestParam(required = false) String toDate,
                                   @RequestParam(required = false) String q, @RequestParam(required = false) Integer limit) {
        OfficeScope.Bound b = scope.bound(fac, dept, null);
        return jdbc.sql("SELECT * FROM people.programme_swaps(:status, :session, :fac, :dept, :from, :to, :level, :kind, :fd, :td, :q, :limit)")
                .param("status", blank(status), Types.VARCHAR).param("session", blank(session), Types.VARCHAR)
                .param("fac", b.fac(), Types.VARCHAR).param("dept", b.dept(), Types.VARCHAR)
                .param("from", blank(from), Types.VARCHAR).param("to", blank(to), Types.VARCHAR).param("level", level, Types.INTEGER)
                .param("kind", blank(kind), Types.VARCHAR).param("fd", date(fromDate), Types.DATE).param("td", date(toDate), Types.DATE)
                .param("q", blank(q), Types.VARCHAR).param("limit", limit == null ? 500 : limit).query().listOfRows().stream().map(this::unwrapped).toList();
    }

    @GetMapping("/{id}")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> one(@PathVariable UUID id) {
        return detail(id);
    }

    private Map<String, Object> detail(UUID id) {
        Map<String, Object> row = jdbc.sql("SELECT * FROM people.programme_swaps(NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 5000) x WHERE x.id = :id")
                .param("id", id).query().listOfRows().stream().findFirst().orElseThrow(() -> new NotFound("programme swap", id));
        UUID student = (UUID) row.get("student_id");
        reach.check(student);
        Map<String, Object> out = unwrapped(row);
        out.put("evidence", jdbc.sql("SELECT id, filename, content_type, size_bytes, added_at, helpdesk.person_name(added_by) AS added_by FROM people.programme_swap_evidence WHERE swap_id = :s ORDER BY added_at")
                .param("s", id).query().listOfRows());
        out.put("history", jdbc.sql("SELECT * FROM people.programme_history(:s)").param("s", student).query().listOfRows());
        if ("PENDING_APPROVAL".equals(row.get("status"))) {
            // what the swap would do on the record as it stands now, for the deciding officer
            out.put("now", jsonOf(jdbc.sql("SELECT people.programme_swap_check(:s, :p, :l, :ses, :id)::text")
                    .param("s", student).param("p", row.get("to_programme")).param("l", row.get("to_level")).param("ses", row.get("effective_session")).param("id", id)
                    .query(String.class).single()));
        }
        // V633: who may make a swap decides one left pending, the officer who prepared it included
        out.put("mayDecide", jdbc.sql("SELECT people.programme_swap_office_decides(:o, :k)").param("o", office()).param("k", String.valueOf(row.get("kind"))).query(Boolean.class).single());
        return out;
    }

    @PostMapping("/{id}/evidence")
    @PreAuthorize(PREPARERS)
    @Transactional
    Map<String, Object> evidence(@PathVariable UUID id, @RequestBody Evidence body) {
        String status = jdbc.sql("SELECT status FROM people.programme_swap WHERE id = :id").param("id", id).query(String.class).optional()
                .orElseThrow(() -> new NotFound("programme swap", id));
        // V633: a swap is made at once, so its evidence (the letter, the approval) is added to the completed swap as well
        if (!"PENDING_APPROVAL".equals(status) && !"COMPLETED".equals(status)) {
            throw new DomainRuleViolation("PSW_DECIDED", "Evidence is added to a swap that was made or awaits a decision; this one is " + status.toLowerCase() + ".",
                    new DomainRuleViolation.Remedy("Make a new swap if more is needed.", "You"));
        }
        if (body.filename() == null || body.filename().isBlank() || body.dataUrl() == null) {
            throw new DomainRuleViolation("PSW_EVIDENCE_FILE", "Choose a file.", new DomainRuleViolation.Remedy("Choose the file again.", "You"));
        }
        String u = body.dataUrl();
        int comma = u.indexOf(',');
        if (!u.startsWith("data:") || comma < 0) {
            throw new DomainRuleViolation("PSW_EVIDENCE_FILE", "The file could not be read.", new DomainRuleViolation.Remedy("Choose the file again.", "You"));
        }
        String meta = u.substring(5, comma);
        String type = meta.contains(";") ? meta.substring(0, meta.indexOf(';')) : meta;
        if (!EVIDENCE_TYPES.contains(type)) {
            throw new DomainRuleViolation("PSW_EVIDENCE_TYPE", "Evidence is a PDF, JPEG or PNG file.", new DomainRuleViolation.Remedy("Scan or save it as one of those.", "You"));
        }
        byte[] bytes;
        try {
            bytes = Base64.getDecoder().decode(u.substring(comma + 1).replaceAll("\\s", ""));
        } catch (IllegalArgumentException bad) {
            throw new DomainRuleViolation("PSW_EVIDENCE_FILE", "The file could not be read.", new DomainRuleViolation.Remedy("Choose the file again.", "You"));
        }
        if (bytes.length == 0 || bytes.length > 5 * 1024 * 1024) {
            throw new DomainRuleViolation("PSW_EVIDENCE_SIZE", "Evidence is up to 5 MB.", new DomainRuleViolation.Remedy("Scan it at a lower resolution.", "You"));
        }
        UUID object = files.store("people.programme_swap_evidence", id, body.filename(), type, bytes);
        jdbc.sql("""
                INSERT INTO people.programme_swap_evidence (swap_id, filename, content_type, size_bytes, content, object_id, added_by)
                VALUES (:s, :f, :t, :n, :c, :o, nullif(current_setting('moaum.actor_id', true), '')::uuid)
                """).param("s", id).param("f", body.filename().trim()).param("t", type).param("n", (long) bytes.length)
                .param("c", object == null ? bytes : null, Types.BINARY).param("o", object, Types.OTHER).update();
        return detail(id);
    }

    @GetMapping("/{id}/evidence/{evidence}")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    ResponseEntity<byte[]> evidenceFile(@PathVariable UUID id, @PathVariable UUID evidence) {
        UUID student = jdbc.sql("SELECT student_id FROM people.programme_swap WHERE id = :id").param("id", id).query(UUID.class).optional()
                .orElseThrow(() -> new NotFound("programme swap", id));
        reach.check(student);
        Map<String, Object> e = jdbc.sql("SELECT filename, content_type, content, object_id FROM people.programme_swap_evidence WHERE id = :e AND swap_id = :s")
                .param("e", evidence).param("s", id).query().listOfRows().stream().findFirst().orElseThrow(() -> new NotFound("evidence", evidence));
        byte[] bytes = e.get("content") instanceof byte[] b ? b : files.load(UUID.fromString(String.valueOf(e.get("object_id"))));
        return ResponseEntity.ok().contentType(MediaType.parseMediaType(String.valueOf(e.get("content_type"))))
                .header(HttpHeaders.CONTENT_DISPOSITION, "inline; filename=\"" + String.valueOf(e.get("filename")).replaceAll("[^A-Za-z0-9._ -]", "_") + "\"")
                .body(bytes);
    }

    /** a swap left pending from before V633, decided by any officer who may make one: rejected, or approved and executed at once */
    @PostMapping("/{id}/decide")
    @PreAuthorize(DECIDERS)
    @Transactional
    Map<String, Object> decide(@PathVariable UUID id, @RequestBody Decision body) {
        if (body.approve() == null) throw new DomainRuleViolation("PSW_DECISION", "Say whether the swap is approved or rejected.", new DomainRuleViolation.Remedy("Choose one.", "You"));
        UUID student = jdbc.sql("SELECT student_id FROM people.programme_swap WHERE id = :id").param("id", id).query(UUID.class).optional()
                .orElseThrow(() -> new NotFound("programme swap", id));
        reach.check(student);
        jdbc.sql("SELECT people.decide_programme_swap(:id, :a, :n)").param("id", id).param("a", body.approve()).param("n", body.note(), Types.VARCHAR).query().listOfRows();
        forget();
        return detail(id);
    }

    @PostMapping("/{id}/cancel")
    @PreAuthorize(PREPARERS)
    @Transactional
    Map<String, Object> cancel(@PathVariable UUID id, @RequestBody Reason body) {
        jdbc.sql("SELECT people.cancel_programme_swap(:id, :r)").param("id", id).param("r", body.reason(), Types.VARCHAR).query().listOfRows();
        forget();
        return detail(id);
    }

    /** a batch's swaps left pending from before V633, decided swap by swap: each on its own savepoint, so one refused (a record changed since) leaves the rest decided */
    @PostMapping("/batches/{batch}/decide")
    @PreAuthorize(DECIDERS)
    @Transactional
    Map<String, Object> decideBatch(@PathVariable UUID batch, @RequestBody Decision body) {
        if (body.approve() == null) throw new DomainRuleViolation("PSW_DECISION", "Say whether the batch is approved or rejected.", new DomainRuleViolation.Remedy("Choose one.", "You"));
        List<UUID> ids = jdbc.sql("SELECT id FROM people.programme_swap WHERE batch_id = :b AND status = 'PENDING_APPROVAL' ORDER BY prepared_at").param("b", batch).query(UUID.class).list();
        return tx.execute(st -> {
            List<Map<String, Object>> done = new ArrayList<>();
            List<Map<String, Object>> skipped = new ArrayList<>();
            for (UUID id : ids) {
                Object sp = st.createSavepoint();
                try {
                    UUID student = jdbc.sql("SELECT student_id FROM people.programme_swap WHERE id = :id").param("id", id).query(UUID.class).single();
                    reach.check(student);
                    String text = jdbc.sql("SELECT people.decide_programme_swap(:id, :a, :n)::text").param("id", id).param("a", body.approve()).param("n", body.note(), Types.VARCHAR)
                            .query(String.class).single();
                    st.releaseSavepoint(sp);
                    done.add(jsonOf(text));
                } catch (DataAccessException | DomainRuleViolation | AccessDeniedException e) {
                    st.rollbackToSavepoint(sp);
                    UUID student = jdbc.sql("SELECT student_id FROM people.programme_swap WHERE id = :id").param("id", id).query(UUID.class).single();
                    Map<String, Object> row = skip(student, e);
                    row.put("id", id);
                    skipped.add(row);
                }
            }
            forget();
            Map<String, Object> out = new LinkedHashMap<>();
            out.put("batchId", batch);
            out.put("decided", done);
            out.put("skipped", skipped);
            return out;
        });
    }

    private static String blank(String s) {
        return s == null || s.isBlank() ? null : s.trim();
    }

    private static java.sql.Date date(String s) {
        if (s == null || s.isBlank()) return null;
        try {
            return java.sql.Date.valueOf(s.trim());
        } catch (IllegalArgumentException e) {
            throw new DomainRuleViolation("PSW_DATE", "A date is YYYY-MM-DD.", new DomainRuleViolation.Remedy("Pick the date again.", "You"));
        }
    }
}
