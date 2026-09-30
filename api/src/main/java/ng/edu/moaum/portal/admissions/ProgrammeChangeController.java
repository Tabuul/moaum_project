package ng.edu.moaum.portal.admissions;

import java.sql.Types;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
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
 * Programme Changes (V297): the register of every applicant now on a programme other than the one applied for — applied for,
 * held now, why, at what stage, who recommended and approved it — and the admission corrected after the Board's decision, even
 * after school fees: recommended by the Academic Office (or the Registrar's office) with the error described, decided by the
 * Registrar, the Deputy Registrar or the Vice-Chancellor's office and never by its recommender. Every rule is the database's
 * (admissions.recommend_admission_correction, admissions.decide_admission_correction); this door reads and passes them on.
 */
@RestController
class ProgrammeChangeController {

    private static final String READERS =
            "hasAnyAuthority('OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar','OFFICE_records','OFFICE_bursar','OFFICE_ict','OFFICE_admin','OFFICE_super','OFFICE_dvc','OFFICE_vc')";
    private static final String RECOMMENDERS = "hasAnyAuthority('OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar','OFFICE_super')";
    private static final String DECIDERS = "hasAnyAuthority('OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar','OFFICE_vc','OFFICE_super')";
    /** the ordinary change is decided by the Admissions offices (V266, V284) */
    static final Set<String> CHANGE_DECIDERS = Set.of("OFFICE_academic", "OFFICE_registrar", "OFFICE_dregistrar", "OFFICE_super");
    /** an admission correction is decided by the Registrar's offices and the Vice-Chancellor's (V297) */
    static final Set<String> CORRECTION_DECIDERS = Set.of("OFFICE_registrar", "OFFICE_dregistrar", "OFFICE_vc", "OFFICE_super");
    /** the offices that may recommend a programme the engine refuses (V284) */
    private static final Set<String> OVERRIDERS = Set.of("OFFICE_registrar", "OFFICE_dregistrar", "OFFICE_dvc", "OFFICE_vc", "OFFICE_super");

    private final JdbcClient jdbc;

    ProgrammeChangeController(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    private static UUID actor() {
        return AuditContextHolder.current().map(c -> c.actorId()).orElse(null);
    }

    private static String office() {
        return AuditContextHolder.current().map(c -> c.actorOffice()).orElse(null);
    }

    private static boolean holds(Authentication auth, Set<String> offices) {
        return auth.getAuthorities().stream().anyMatch(g -> offices.contains(g.getAuthority()));
    }

    private void inSession(UUID appId, String s) {
        long n = jdbc.sql("SELECT count(*) FROM admissions.application WHERE id = :a AND session = :s").param("a", appId).param("s", s).query(Long.class).single();
        if (n == 0) {
            throw new NotFound("application", appId);
        }
    }

    private static final String SESSIONS = """
            SELECT a.session AS name, count(*) AS applications,
                   (SELECT count(DISTINCT q.application_id) FROM admissions.programme_change_request q WHERE q.session = a.session AND q.state = 'APPROVED') AS changed
              FROM admissions.application a GROUP BY a.session ORDER BY a.session DESC
            """;

    /** the sessions with applications, the latest first: the screen opens on the first unless another is asked for */
    @GetMapping("/api/v1/admissions/programme-changes/sessions")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> sessions() {
        return jdbc.sql(SESSIONS).query().listOfRows();
    }

    /** the register, the queue awaiting a decision, and what the screen needs to recommend a correction */
    @GetMapping("/api/v1/admissions/sessions/{session}/{year}/programme-changes")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> register(@PathVariable String session, @PathVariable String year) {
        String s = session + "/" + year;
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("session", s);
        out.put("rows", jdbc.sql("SELECT * FROM admissions.programme_change_register(:s)").param("s", s).query().listOfRows());
        out.put("pending", jdbc.sql("""
                SELECT q.id, q.application_id, q.kind, q.from_programme, q.from_programme_code, q.to_programme, q.to_programme_code,
                       q.reason_code, coalesce(rs.label, q.reason_code) AS reason, q.note, q.requested_by_kind, q.recommended_office, q.requested_at,
                       q.override, q.override_reason, q.eligibility_at_request, q.admission_stage, q.screening_state_at_request,
                       a.application_no, c.surname, c.other_names, c.jamb_reg_no, c.entry_mode,
                       (SELECT p.surname || ', ' || p.given_names FROM iam.person p WHERE p.id = q.requested_by) AS recommended_by,
                       (q.requested_by IS NOT NULL AND q.requested_by = :me) AS mine
                  FROM admissions.programme_change_request q
                  JOIN admissions.application a ON a.id = q.application_id
                  JOIN admissions.candidate c ON c.id = q.candidate_id
                  LEFT JOIN admissions.programme_change_reason rs ON rs.code = q.reason_code
                 WHERE q.session = :s AND q.state = 'REQUESTED'
                 ORDER BY q.requested_at
                """).param("s", s).param("me", actor(), Types.OTHER).query().listOfRows());
        out.put("reasons", jdbc.sql("SELECT code, label, ord, requires_note FROM admissions.programme_change_reason WHERE active ORDER BY ord, label").query().listOfRows());
        out.put("programmes", jdbc.sql("""
                SELECT p.code, p.name, f.name AS faculty, d.name AS department
                  FROM ref.programme p LEFT JOIN ref.faculty f ON f.code = p.faculty_code LEFT JOIN ref.department d ON d.code = p.dept_code
                 WHERE NOT p.archived ORDER BY p.name
                """).query().listOfRows());
        out.put("sessions", jdbc.sql(SESSIONS).query().listOfRows());
        return out;
    }

    /** the applicants of the session matching a name, JAMB number or application number, each with the road a change would take */
    @GetMapping("/api/v1/admissions/sessions/{session}/{year}/programme-changes/find")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> find(@PathVariable String session, @PathVariable String year, @RequestParam(defaultValue = "") String q) {
        String needle = q.trim().toLowerCase();
        if (needle.length() < 3) {
            return List.of();
        }
        return jdbc.sql("""
                SELECT a.id, a.application_no, c.jamb_reg_no, c.surname, c.other_names, c.programme, c.entry_mode, a.decision, a.decision_released_at,
                       rt.route, rt.stage, rt.detail
                  FROM admissions.application a
                  JOIN admissions.candidate c ON c.id = a.candidate_id
                  CROSS JOIN LATERAL admissions.programme_change_route(a.id) rt
                 WHERE a.session = :s
                   AND (lower(c.surname || ' ' || c.other_names) LIKE :q OR lower(c.other_names || ' ' || c.surname) LIKE :q
                        OR lower(c.jamb_reg_no) LIKE :q OR lower(a.application_no) LIKE :q)
                 ORDER BY c.surname, c.other_names
                 LIMIT 25
                """).param("s", session + "/" + year).param("q", "%" + needle + "%").query().listOfRows();
    }

    /** what a correction to the programme named would do — the road, the eligibility, the fees before and after — before anybody does it */
    @GetMapping("/api/v1/admissions/sessions/{session}/{year}/programme-changes/{appId}/preview")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> preview(@PathVariable String session, @PathVariable String year, @PathVariable UUID appId, @RequestParam(required = false) String to) {
        inSession(appId, session + "/" + year);
        return read(appId, to);
    }

    private Map<String, Object> read(UUID appId, String to) {
        String text = jdbc.sql("SELECT admissions.correction_preview(:a, :to)::text").param("a", appId)
                .param("to", to == null || to.isBlank() ? null : to.trim().toUpperCase(), Types.VARCHAR).query(String.class).single();
        return CandidateDataController.Json.map(text);
    }

    public record CorrectionIn(@NotBlank String programmeCode, @NotBlank @Size(max = 40) String reasonCode, @Size(max = 1000) String note,
                               Boolean override, @Size(max = 1000) String overrideReason) {
    }

    /** the recommendation: a configured reason, the error described, eligibility read again on the server; the override only for the offices named */
    @PostMapping("/api/v1/admissions/sessions/{session}/{year}/programme-changes/{appId}/correct")
    @PreAuthorize(RECOMMENDERS)
    @Transactional
    Map<String, Object> correct(@PathVariable String session, @PathVariable String year, @PathVariable UUID appId, @Valid @RequestBody CorrectionIn body, Authentication auth) {
        inSession(appId, session + "/" + year);
        boolean override = Boolean.TRUE.equals(body.override());
        if (override && !holds(auth, OVERRIDERS)) {
            throw new AccessDeniedException("An eligibility override is reserved to the Registrar, the Deputy Registrar and the Vice-Chancellor's office.");
        }
        String code = body.programmeCode().trim().toUpperCase();
        jdbc.sql("SELECT admissions.recommend_admission_correction(:a, :p, :r, :n, :by, :o, :ov, :ovr)")
                .param("a", appId).param("p", code).param("r", body.reasonCode().trim().toUpperCase())
                .param("n", body.note(), Types.VARCHAR).param("by", actor(), Types.OTHER).param("o", office(), Types.VARCHAR)
                .param("ov", override).param("ovr", body.overrideReason(), Types.VARCHAR).query(UUID.class).single();
        return read(appId, code);
    }

    public record DecisionIn(@Size(max = 1000) String note) {
    }

    @PostMapping("/api/v1/admissions/sessions/{session}/{year}/programme-changes/requests/{id}/approve")
    @PreAuthorize(DECIDERS)
    @Transactional
    Map<String, Object> approve(@PathVariable String session, @PathVariable String year, @PathVariable UUID id, @RequestBody(required = false) DecisionIn body, Authentication auth) {
        return decide(session + "/" + year, id, "APPROVE", body == null ? null : body.note(), auth);
    }

    @PostMapping("/api/v1/admissions/sessions/{session}/{year}/programme-changes/requests/{id}/reject")
    @PreAuthorize(DECIDERS)
    @Transactional
    Map<String, Object> reject(@PathVariable String session, @PathVariable String year, @PathVariable UUID id, @RequestBody(required = false) DecisionIn body, Authentication auth) {
        return decide(session + "/" + year, id, "REJECT", body == null ? null : body.note(), auth);
    }

    private Map<String, Object> decide(String s, UUID id, String decision, String note, Authentication auth) {
        Map<String, Object> q = jdbc.sql("SELECT application_id, kind FROM admissions.programme_change_request WHERE id = :id AND session = :s")
                .param("id", id).param("s", s).query().listOfRows().stream().findFirst().orElseThrow(() -> new NotFound("programme change request", id));
        boolean correction = "CORRECTION".equals(q.get("kind"));
        guardDecision(correction, auth);
        if ("REJECT".equals(decision) && (note == null || note.isBlank())) {
            throw new DomainRuleViolation("CHANGE_REJECTION_REASON", "A rejection carries its reason.",
                    new DomainRuleViolation.Remedy("Write why the change is not approved; the recommending office is told.", "The deciding office"));
        }
        String state = jdbc.sql("SELECT admissions.decide_programme_change(:id, :d, :n, :by)").param("id", id).param("d", decision)
                .param("n", note, Types.VARCHAR).param("by", actor(), Types.OTHER).query(String.class).single();
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("state", state);
        out.put("request", jdbc.sql("""
                SELECT q.id, q.application_id, q.kind, q.state, q.from_programme, q.to_programme, q.decided_at, q.decided_office, q.decision_note,
                       q.fee_session, q.fees_paid, q.fees_due_before, q.fees_due_after, q.registrations_returned, q.courses_dropped, q.matric_rows_dropped,
                       q.letter_reissued, q.forms_reissued
                  FROM admissions.programme_change_request q WHERE q.id = :id
                """).param("id", id).query().singleRow());
        return out;
    }

    /** who decides which: an admission correction the Registrar's offices and the Vice-Chancellor's; the ordinary change the Admissions offices */
    static void guardDecision(boolean correction, Authentication auth) {
        if (correction && !holds(auth, CORRECTION_DECIDERS)) {
            throw new AccessDeniedException("An admission correction is decided by the Registrar, the Deputy Registrar or the Vice-Chancellor's office.");
        }
        if (!correction && !holds(auth, CHANGE_DECIDERS)) {
            throw new AccessDeniedException("A change of programme is decided by the Academic Office or the Registrar's office.");
        }
    }
}
