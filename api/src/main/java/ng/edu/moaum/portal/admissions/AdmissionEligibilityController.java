package ng.edu.moaum.portal.admissions;

import java.sql.Types;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

import ng.edu.moaum.portal.shared.AuditContextHolder;
import ng.edu.moaum.portal.shared.DomainRuleViolation;
import ng.edu.moaum.portal.shared.NotFound;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.Authentication;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * Admission eligibility and the course suggestion engine (V266). The database evaluates an application against the
 * session's admission settings — the applied programme first, and when it is refused on the rules, every other active,
 * stated, open programme — and keeps the run with every check explained. This door serves the Admissions Office (the
 * register, the details, the recalculation, the programme-change queue) and the applicant (their own verdict, the
 * eligible alternatives, a request to change). Nothing here admits anybody or changes a programme by itself.
 */
@RestController
class AdmissionEligibilityController {

    private static final String READERS =
            "hasAnyAuthority('OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar','OFFICE_records','OFFICE_bursar','OFFICE_ict','OFFICE_admin','OFFICE_super','OFFICE_dvc','OFFICE_vc')";
    private static final String OFFICE = "hasAnyAuthority('OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar','OFFICE_super')";
    private static final String APPLICANT = "hasAuthority('OFFICE_applicant')";

    private final JdbcClient jdbc;

    AdmissionEligibilityController(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    private static String blank(String v) {
        return v == null || v.isBlank() ? null : v.trim();
    }

    private static UUID actor() {
        return AuditContextHolder.current().map(c -> c.actorId()).orElse(null);
    }

    /* ── the office ─────────────────────────────────────────────────────── */

    private static final String LIST = """
            SELECT a.id, a.application_no, a.submitted_at, a.decision, a.decision_released_at,
                   c.surname, c.other_names, c.jamb_reg_no, c.programme, c.entry_mode,
                   pc.code AS programme_code, pc.faculty_code, f.name AS faculty, d.name AS department,
                   r.id AS run_id, r.applied_result, r.alternatives, r.evaluated_at, r.rules_version, r.policy_state, r.stale,
                   (SELECT x.reasons FROM admissions.eligibility_result x WHERE x.run_id = r.id AND x.kind = 'APPLIED' LIMIT 1) AS reasons,
                   (SELECT string_agg(y.programme, ' · ' ORDER BY y.ord, y.programme)
                      FROM (SELECT x.programme, x.ord FROM admissions.eligibility_result x WHERE x.run_id = r.id AND x.kind = 'ALTERNATIVE' AND x.result IN ('ELIGIBLE','ELIGIBLE_SCREENING') ORDER BY x.ord, x.programme LIMIT 3) y) AS top_alternatives,
                   q.id AS change_id, q.to_programme AS change_to, q.to_programme_code AS change_to_code, q.state AS change_state, q.requested_at AS change_requested_at
              FROM admissions.application a
              JOIN admissions.candidate c ON c.id = a.candidate_id
              LEFT JOIN ref.programme pc ON pc.code = admissions.programme_code_of(c.programme)
              LEFT JOIN ref.faculty f ON f.code = pc.faculty_code
              LEFT JOIN ref.department d ON d.code = pc.dept_code
              LEFT JOIN admissions.eligibility_run r ON r.application_id = a.id AND r.superseded_at IS NULL
              LEFT JOIN admissions.programme_change_request q ON q.application_id = a.id AND q.state = 'REQUESTED'
            """;

    @GetMapping("/api/v1/admissions/sessions/{session}/{year}/eligibility")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> list(@PathVariable String session, @PathVariable String year, @RequestParam(required = false) String q,
                             @RequestParam(required = false) String fac, @RequestParam(required = false) String dept, @RequestParam(required = false) String prog,
                             @RequestParam(required = false) String status, @RequestParam(required = false) String recommended, @RequestParam(required = false) String mode,
                             @RequestParam(defaultValue = "0") int page, @RequestParam(defaultValue = "200") int size) {
        String s = session + "/" + year;
        String st = blank(status) == null ? null : status.trim().toUpperCase();
        String pred = st == null ? "" : switch (st) {
            case "ELIGIBLE" -> " AND r.applied_result IN ('ELIGIBLE','ELIGIBLE_SCREENING')";
            case "NOT_ELIGIBLE" -> " AND r.applied_result = 'NOT_ELIGIBLE'";
            case "UNVERIFIED" -> " AND r.applied_result = 'UNVERIFIED'";
            case "ALTERNATIVES" -> " AND r.applied_result = 'NOT_ELIGIBLE' AND r.alternatives > 0";
            case "NO_ALTERNATIVES" -> " AND r.applied_result = 'NOT_ELIGIBLE' AND r.alternatives = 0";
            case "PENDING_CHANGE" -> " AND q.id IS NOT NULL";
            case "NOT_EVALUATED" -> " AND r.id IS NULL";
            default -> "";
        };
        String needle = blank(q) == null ? null : "%" + q.trim().toLowerCase() + "%";
        int sz = Math.max(1, Math.min(size, 1000)), pg = Math.max(0, page);
        List<Map<String, Object>> rows = jdbc.sql(LIST + """
                 WHERE a.session = :s AND a.submitted_at IS NOT NULL
                   AND (:fac::text IS NULL OR pc.faculty_code = :fac)
                   AND (:dept::text IS NULL OR pc.dept_code = :dept)
                   AND (:prog::text IS NULL OR pc.code = :prog)
                   AND (:mode::text IS NULL OR c.entry_mode = :mode)
                   AND (:rec::text IS NULL OR EXISTS (SELECT 1 FROM admissions.eligibility_result x WHERE x.run_id = r.id AND x.kind = 'ALTERNATIVE' AND x.programme_code = :rec AND x.result IN ('ELIGIBLE','ELIGIBLE_SCREENING')))
                   AND (:q::text IS NULL OR lower(c.surname || ' ' || c.other_names) LIKE :q OR lower(c.other_names || ' ' || c.surname) LIKE :q OR lower(c.jamb_reg_no) LIKE :q
                        OR lower(a.application_no) LIKE :q OR lower(c.programme) LIKE :q OR lower(coalesce(f.name, '')) LIKE :q OR lower(coalesce(d.name, '')) LIKE :q)
                """ + pred + " ORDER BY c.surname, c.other_names LIMIT :n OFFSET :o")
                .param("s", s).param("fac", blank(fac), Types.VARCHAR).param("dept", blank(dept), Types.VARCHAR).param("prog", blank(prog), Types.VARCHAR)
                .param("mode", blank(mode) == null ? null : mode.trim().toUpperCase(), Types.VARCHAR).param("rec", blank(recommended), Types.VARCHAR)
                .param("q", needle, Types.VARCHAR).param("n", sz).param("o", pg * sz).query().listOfRows();
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("session", s);
        out.put("rows", rows);
        out.put("page", pg);
        out.put("size", sz);
        out.put("stats", stats(s));
        out.put("options", jdbc.sql("""
                SELECT DISTINCT pc.faculty_code, f.name AS faculty, pc.dept_code, d.name AS department, pc.code AS programme_code, pc.name AS programme
                  FROM admissions.application a JOIN admissions.candidate c ON c.id = a.candidate_id
                  JOIN ref.programme pc ON pc.code = admissions.programme_code_of(c.programme) JOIN ref.faculty f ON f.code = pc.faculty_code LEFT JOIN ref.department d ON d.code = pc.dept_code
                 WHERE a.session = :s AND a.submitted_at IS NOT NULL ORDER BY f.name, d.name, pc.name
                """).param("s", s).query().listOfRows());
        out.put("recommendable", jdbc.sql("""
                SELECT DISTINCT x.programme_code, x.programme FROM admissions.eligibility_result x JOIN admissions.eligibility_run r ON r.id = x.run_id
                 WHERE r.session = :s AND r.superseded_at IS NULL AND x.kind = 'ALTERNATIVE' AND x.result IN ('ELIGIBLE','ELIGIBLE_SCREENING') ORDER BY x.programme
                """).param("s", s).query().listOfRows());
        return out;
    }

    private Map<String, Object> stats(String s) {
        Map<String, Object> m = new LinkedHashMap<>(jdbc.sql("SELECT * FROM admissions.eligibility_stats(:s)").param("s", s).query().singleRow());
        m.put("not_evaluated", jdbc.sql("""
                SELECT count(*) FROM admissions.application a WHERE a.session = :s AND a.submitted_at IS NOT NULL
                   AND NOT EXISTS (SELECT 1 FROM admissions.eligibility_run r WHERE r.application_id = a.id AND r.superseded_at IS NULL)
                """).param("s", s).query(Long.class).single());
        m.put("stale", jdbc.sql("SELECT count(*) FROM admissions.eligibility_run r WHERE r.session = :s AND r.superseded_at IS NULL AND r.stale").param("s", s).query(Long.class).single());
        return m;
    }

    @GetMapping("/api/v1/admissions/sessions/{session}/{year}/eligibility/stats")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> statsOnly(@PathVariable String session, @PathVariable String year) {
        return stats(session + "/" + year);
    }

    /** one application, evaluated afresh when nothing current stands, the record changed or the rules moved on; every reading on the trail */
    @GetMapping("/api/v1/admissions/sessions/{session}/{year}/eligibility/{appId}")
    @PreAuthorize(READERS)
    @Transactional
    Map<String, Object> one(@PathVariable String session, @PathVariable String year, @PathVariable UUID appId) {
        String s = session + "/" + year;
        inSession(appId, s);
        UUID run = jdbc.sql("SELECT admissions.eligibility_current(:a, :by)").param("a", appId).param("by", actor(), Types.OTHER).query(UUID.class).single();
        jdbc.sql("SELECT admissions.eligibility_log(:a, :r, 'RECOMMENDATION_VIEWED', NULL, NULL, :d)").param("a", appId).param("r", run)
                .param("d", "Viewed by the " + AuditContextHolder.current().map(c -> c.actorOffice()).orElse("desk")).query().listOfRows();
        return detail(appId, run, true);
    }

    private void inSession(UUID appId, String s) {
        long n = jdbc.sql("SELECT count(*) FROM admissions.application WHERE id = :a AND session = :s").param("a", appId).param("s", s).query(Long.class).single();
        if (n == 0) throw new NotFound("application", appId);
    }

    private Map<String, Object> detail(UUID appId, UUID run, boolean everything) {
        Map<String, Object> d = new LinkedHashMap<>();
        d.put("application", jdbc.sql(LIST + " WHERE a.id = :a").param("a", appId).query().singleRow());
        d.put("run", jdbc.sql("SELECT * FROM admissions.eligibility_run WHERE id = :r").param("r", run).query().singleRow());
        d.put("applied", jdbc.sql("SELECT programme_code, programme, faculty, department, result, checks::text AS checks, reasons FROM admissions.eligibility_result WHERE run_id = :r AND kind = 'APPLIED' LIMIT 1")
                .param("r", run).query().listOfRows().stream().findFirst().orElse(null));
        d.put("alternatives", jdbc.sql("SELECT programme_code, programme, faculty_code, faculty, department, result, checks::text AS checks, reasons, ord FROM admissions.eligibility_result WHERE run_id = :r AND kind = 'ALTERNATIVE'"
                + (everything ? "" : " AND result IN ('ELIGIBLE','ELIGIBLE_SCREENING')") + " ORDER BY ord, programme").param("r", run).query().listOfRows());
        d.put("changes", jdbc.sql("""
                SELECT q.*, CASE WHEN p.id IS NULL THEN NULL ELSE p.surname || ', ' || p.given_names END AS decided_officer
                  FROM admissions.programme_change_request q LEFT JOIN iam.person p ON p.id = q.decided_by WHERE q.application_id = :a ORDER BY q.requested_at DESC
                """).param("a", appId).query().listOfRows());
        if (everything) {
            d.put("events", jdbc.sql("""
                    SELECT e.action, e.programme_code, e.result, e.detail, e.actor_office, e.at, CASE WHEN p.id IS NULL THEN NULL ELSE p.surname || ', ' || p.given_names END AS actor
                      FROM admissions.eligibility_event e LEFT JOIN iam.person p ON p.id = e.actor_id WHERE e.application_id = :a ORDER BY e.at DESC LIMIT 200
                    """).param("a", appId).query().listOfRows());
            d.put("olevel", jdbc.sql("""
                    SELECT st.exam_body, st.exam_year, st.exam_number,
                           (SELECT json_agg(json_build_object('subject', g.subject, 'grade', g.grade) ORDER BY g.subject)::text FROM admissions.olevel_grade g WHERE g.sitting_id = st.id) AS subjects
                      FROM admissions.olevel_sitting st JOIN admissions.application a ON a.session = st.session JOIN admissions.candidate c ON c.id = a.candidate_id AND c.jamb_key = st.jamb_key
                     WHERE a.id = :a ORDER BY st.exam_year NULLS LAST, st.ord
                    """).param("a", appId).query().listOfRows());
            d.put("utme", jdbc.sql("""
                    SELECT x.aggregate, (SELECT string_agg(e.value, ', ' ORDER BY e.key) FROM jsonb_each_text(x.raw) e WHERE regexp_replace(lower(e.key), '[^a-z0-9]', '', 'g') IN ('subject1','subject2','subject3','subject4') AND nullif(btrim(e.value), '') IS NOT NULL) AS subjects
                      FROM admissions.caps_row_live x JOIN admissions.application a ON a.session = x.session JOIN admissions.candidate c ON c.id = a.candidate_id AND c.jamb_key = x.jamb_key
                     WHERE a.id = :a ORDER BY x.aggregate DESC NULLS LAST LIMIT 1
                    """).param("a", appId).query().listOfRows().stream().findFirst().orElse(null));
        }
        return d;
    }

    @PostMapping("/api/v1/admissions/sessions/{session}/{year}/eligibility/{appId}/recalculate")
    @PreAuthorize(OFFICE)
    @Transactional
    Map<String, Object> recalculate(@PathVariable String session, @PathVariable String year, @PathVariable UUID appId) {
        inSession(appId, session + "/" + year);
        UUID run = jdbc.sql("SELECT admissions.evaluate_application(:a, 'OFFICER', :by)").param("a", appId).param("by", actor(), Types.OTHER).query(UUID.class).single();
        return detail(appId, run, true);
    }

    /** every submitted application of the session evaluated (again); the office runs it after a policy or data load */
    @PostMapping("/api/v1/admissions/sessions/{session}/{year}/eligibility/recalculate-all")
    @PreAuthorize(OFFICE)
    @Transactional
    Map<String, Object> recalculateAll(@PathVariable String session, @PathVariable String year, @RequestParam(defaultValue = "false") boolean onlyMissing) {
        String s = session + "/" + year;
        List<UUID> apps = jdbc.sql("SELECT a.id FROM admissions.application a WHERE a.session = :s AND a.submitted_at IS NOT NULL"
                + (onlyMissing ? " AND NOT EXISTS (SELECT 1 FROM admissions.eligibility_run r WHERE r.application_id = a.id AND r.superseded_at IS NULL AND NOT r.stale)" : "")
                + " ORDER BY a.submitted_at").param("s", s).query(UUID.class).list();
        // catching up the unevaluated is the system's first reading (the applicant is told); a full re-run is the officer's own act
        String trigger = onlyMissing ? "SYSTEM" : "OFFICER";
        for (UUID a : apps) {
            jdbc.sql("SELECT admissions.evaluate_application(:a, :t, :by)").param("a", a).param("t", trigger).param("by", actor(), Types.OTHER).query(UUID.class).single();
        }
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("evaluated", apps.size());
        out.put("stats", stats(s));
        return out;
    }

    public record ChangeIn(@NotBlank String programmeCode, @Size(max = 1000) String note) {
    }

    /** the office asks for a change on the applicant's behalf; the same eligibility gate as the applicant's own request */
    @PostMapping("/api/v1/admissions/sessions/{session}/{year}/eligibility/{appId}/change")
    @PreAuthorize(OFFICE)
    @Transactional
    Map<String, Object> officeRequest(@PathVariable String session, @PathVariable String year, @PathVariable UUID appId, @Valid @RequestBody ChangeIn body) {
        inSession(appId, session + "/" + year);
        jdbc.sql("SELECT admissions.request_programme_change(:a, :p, :n, 'OFFICE', :by)").param("a", appId).param("p", body.programmeCode().trim().toUpperCase())
                .param("n", body.note(), Types.VARCHAR).param("by", actor(), Types.OTHER).query(UUID.class).single();
        UUID run = jdbc.sql("SELECT admissions.eligibility_current(:a, :by)").param("a", appId).param("by", actor(), Types.OTHER).query(UUID.class).single();
        return detail(appId, run, true);
    }

    @GetMapping("/api/v1/admissions/sessions/{session}/{year}/eligibility/changes")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> changes(@PathVariable String session, @PathVariable String year, @RequestParam(required = false) String state) {
        return jdbc.sql("""
                SELECT q.*, a.application_no, c.surname, c.other_names, c.jamb_reg_no, c.entry_mode,
                       CASE WHEN p.id IS NULL THEN NULL ELSE p.surname || ', ' || p.given_names END AS decided_officer
                  FROM admissions.programme_change_request q JOIN admissions.application a ON a.id = q.application_id JOIN admissions.candidate c ON c.id = q.candidate_id
                  LEFT JOIN iam.person p ON p.id = q.decided_by
                 WHERE q.session = :s AND (:st::text IS NULL OR q.state = :st) ORDER BY (q.state = 'REQUESTED') DESC, q.requested_at DESC
                """).param("s", session + "/" + year).param("st", blank(state) == null ? null : state.trim().toUpperCase(), Types.VARCHAR).query().listOfRows();
    }

    public record DecisionIn(@Size(max = 1000) String note) {
    }

    @PostMapping("/api/v1/admissions/sessions/{session}/{year}/eligibility/changes/{id}/approve")
    @PreAuthorize(OFFICE)
    @Transactional
    Map<String, Object> approve(@PathVariable String session, @PathVariable String year, @PathVariable UUID id, @RequestBody(required = false) DecisionIn body) {
        return decide(session + "/" + year, id, "APPROVE", body == null ? null : body.note());
    }

    @PostMapping("/api/v1/admissions/sessions/{session}/{year}/eligibility/changes/{id}/reject")
    @PreAuthorize(OFFICE)
    @Transactional
    Map<String, Object> reject(@PathVariable String session, @PathVariable String year, @PathVariable UUID id, @RequestBody(required = false) DecisionIn body) {
        return decide(session + "/" + year, id, "REJECT", body == null ? null : body.note());
    }

    private Map<String, Object> decide(String s, UUID id, String decision, String note) {
        UUID app = jdbc.sql("SELECT application_id FROM admissions.programme_change_request WHERE id = :id AND session = :s").param("id", id).param("s", s)
                .query(UUID.class).optional().orElseThrow(() -> new NotFound("programme change request", id));
        jdbc.sql("SELECT admissions.decide_programme_change(:id, :d, :n, :by)").param("id", id).param("d", decision).param("n", note, Types.VARCHAR).param("by", actor(), Types.OTHER).query(String.class).single();
        UUID run = jdbc.sql("SELECT admissions.eligibility_current(:a, :by)").param("a", app).param("by", actor(), Types.OTHER).query(UUID.class).single();
        return detail(app, run, true);
    }

    /* ── the applicant's own ────────────────────────────────────────────── */

    private UUID myApplication(Authentication a) {
        UUID account;
        try {
            account = UUID.fromString(a.getName());
        } catch (IllegalArgumentException e) {
            throw new AccessDeniedException("Not an applicant session.");
        }
        return jdbc.sql("SELECT id FROM admissions.application WHERE account_id = :acc").param("acc", account).query(UUID.class).optional()
                .orElseThrow(() -> new AccessDeniedException("No application for this account."));
    }

    /** the applicant's verdict on the programme they applied for and the alternatives they qualify for — never another's */
    @GetMapping("/api/v1/applicant/me/eligibility")
    @PreAuthorize(APPLICANT)
    @Transactional
    Map<String, Object> mine(Authentication a) {
        UUID app = myApplication(a);
        Map<String, Object> out = new LinkedHashMap<>();
        boolean submitted = jdbc.sql("SELECT submitted_at IS NOT NULL FROM admissions.application WHERE id = :a").param("a", app).query(Boolean.class).single();
        out.put("available", submitted);
        if (!submitted) {
            out.put("note", "Your eligibility is read once you submit the application form.");
            return out;
        }
        UUID run = jdbc.sql("SELECT admissions.eligibility_current(:a, NULL)").param("a", app).query(UUID.class).single();
        out.putAll(detail(app, run, false));
        out.put("canRequestChange", jdbc.sql("SELECT decision_released_at IS NULL FROM admissions.application WHERE id = :a").param("a", app).query(Boolean.class).single()
                && jdbc.sql("SELECT count(*) FROM admissions.programme_change_request WHERE application_id = :a AND state = 'REQUESTED'").param("a", app).query(Long.class).single() == 0);
        return out;
    }

    @PostMapping("/api/v1/applicant/me/eligibility/recalculate")
    @PreAuthorize(APPLICANT)
    @Transactional
    Map<String, Object> myRecalculate(Authentication a) {
        UUID app = myApplication(a);
        jdbc.sql("SELECT admissions.evaluate_application(:a, 'APPLICANT', NULL)").param("a", app).query(UUID.class).single();
        return mine(a);
    }

    @PostMapping("/api/v1/applicant/me/eligibility/change")
    @PreAuthorize(APPLICANT)
    @Transactional
    Map<String, Object> myChange(Authentication a, @Valid @RequestBody ChangeIn body) {
        UUID app = myApplication(a);
        String code = body.programmeCode().trim().toUpperCase();
        // the applicant may ask only for a programme the current run found them eligible for
        UUID run = jdbc.sql("SELECT admissions.eligibility_current(:a, NULL)").param("a", app).query(UUID.class).single();
        long ok = jdbc.sql("SELECT count(*) FROM admissions.eligibility_result WHERE run_id = :r AND kind = 'ALTERNATIVE' AND programme_code = :p AND result IN ('ELIGIBLE','ELIGIBLE_SCREENING')")
                .param("r", run).param("p", code).query(Long.class).single();
        if (ok == 0) {
            throw new DomainRuleViolation("ELIG_NOT_SUGGESTED", "That programme is not among the programmes you are eligible for on the current admission policy.",
                    new DomainRuleViolation.Remedy("Choose one of the programmes listed under Programme eligibility.", "You"));
        }
        jdbc.sql("SELECT admissions.request_programme_change(:a, :p, :n, 'APPLICANT', NULL)").param("a", app).param("p", code).param("n", body.note(), Types.VARCHAR).query(UUID.class).single();
        return mine(a);
    }
}
