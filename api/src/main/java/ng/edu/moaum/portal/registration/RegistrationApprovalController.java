package ng.edu.moaum.portal.registration;

import java.sql.Types;
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
import jakarta.validation.constraints.Size;

import ng.edu.moaum.portal.shared.AuditContext;
import ng.edu.moaum.portal.shared.AuditContextHolder;
import ng.edu.moaum.portal.shared.DomainRuleViolation;
import ng.edu.moaum.portal.shared.NotFound;

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
 * How course registration is approved (V491): HOD_APPROVAL_REQUIRED, the standing rule, or AUTO_APPROVAL, set by session (and
 * semester where it differs) with whether a student may reset the registration and whether the examination card is offered on
 * approval. The Academic Office, the Registry, the Directorate of ICT and super set it, with a reason, on the audit spine; setting
 * AUTO_APPROVAL judges the registrations already waiting on a Head by the submission's own rules — approved where they hold, kept
 * for review with the reason where they do not. The figures and lists show what was approved and how, what waits, what is held
 * for review, the resets and the registrations made again, and the examination cards issued.
 */
@RestController
@RequestMapping("/api/v1/registration/approval")
class RegistrationApprovalController {

    static final String SETTERS = "hasAnyAuthority('OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar','OFFICE_ict','OFFICE_super')";
    static final String READERS = "hasAnyAuthority('OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar','OFFICE_ict','OFFICE_admin','OFFICE_super')";
    static final Set<String> MODES = Set.of("HOD_APPROVAL_REQUIRED", "AUTO_APPROVAL");
    static final Set<String> KINDS = Set.of("ALL", "APPROVED", "AUTO_APPROVED", "HOD_APPROVED", "PENDING", "REVIEW", "RESET", "REREGISTERED", "CARDS_ISSUED", "DRAFT");

    private final JdbcClient jdbc;

    RegistrationApprovalController(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    private static String session(String s) {
        if (s == null || !s.trim().matches("\\d{4}/\\d{4}")) {
            throw new DomainRuleViolation("REG_APPROVAL_SESSION", "A session is named YYYY/YYYY.", new DomainRuleViolation.Remedy("Choose the session.", "Academic Office"));
        }
        return s.trim();
    }

    private static Integer semester(Integer m) {
        if (m != null && (m < 1 || m > 3)) {
            throw new DomainRuleViolation("REG_APPROVAL_SEMESTER", "A semester is 1, 2 or 3.", new DomainRuleViolation.Remedy("Choose the semester, or none for the whole session.", "Academic Office"));
        }
        return m;
    }

    private Map<String, Object> rule(String session, int semester) {
        return jdbc.sql("""
                SELECT r.session, r.semester, coalesce(r.mode, 'HOD_APPROVAL_REQUIRED') AS mode, coalesce(r.allow_student_reset, false) AS allow_student_reset,
                       coalesce(r.card_on_approval, true) AS card_on_approval, r.reason, r.set_at, helpdesk.person_name(r.set_by) AS set_by, r.set_office,
                       CASE WHEN r.semester IS NOT NULL THEN 'SEMESTER' WHEN r.session IS NOT NULL THEN 'SESSION' WHEN r.id IS NOT NULL THEN 'STANDING' ELSE 'DEFAULT' END AS applies_as
                  FROM (SELECT 1) one LEFT JOIN LATERAL (SELECT * FROM registration.approval_rule(:s, :m) x WHERE x.id IS NOT NULL) r ON true
                """).param("s", session).param("m", semester).query().singleRow();
    }

    /** the rule in force for a session and semester — read by any signed-in office and the student portal */
    @GetMapping("/rule")
    @PreAuthorize("isAuthenticated()")
    @Transactional(readOnly = true)
    Map<String, Object> ruleFor(@RequestParam String session, @RequestParam(defaultValue = "1") int semester) {
        return rule(session(session), semester(semester));
    }

    /** every rule set, the sessions it may be set for, and the current session */
    @GetMapping("/rules")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> rules() {
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("rules", jdbc.sql("""
                SELECT p.id, p.session, p.semester, p.mode, p.allow_student_reset, p.card_on_approval, p.reason, p.set_at,
                       helpdesk.person_name(p.set_by) AS set_by, p.set_office
                  FROM registration.approval_policy p ORDER BY p.session NULLS FIRST, p.semester NULLS FIRST
                """).query().listOfRows());
        out.put("sessions", jdbc.sql("SELECT name FROM policy.academic_session ORDER BY name DESC LIMIT 12").query(String.class).list());
        out.put("current", jdbc.sql("SELECT policy.university_current_session()").query(String.class).optional().orElse(null));
        return out;
    }

    public record RuleIn(@Size(max = 9) String session, Integer semester, @NotBlank String mode, @NotNull Boolean allowStudentReset,
                         @NotNull Boolean cardOnApproval, @NotBlank @Size(min = 10, max = 2000) String reason) {
    }

    /** set the rule for a session (and semester), or the standing rule (no session); AUTO_APPROVAL then judges the registrations
     *  already waiting on a Head */
    @PutMapping("/rules")
    @PreAuthorize(SETTERS)
    @Transactional
    Map<String, Object> setRule(@Valid @RequestBody RuleIn body) {
        String mode = body.mode().trim().toUpperCase();
        if (!MODES.contains(mode)) {
            throw new DomainRuleViolation("REG_APPROVAL_MODE", "The approval is HOD_APPROVAL_REQUIRED or AUTO_APPROVAL.", new DomainRuleViolation.Remedy("Choose one.", "Academic Office"));
        }
        String session = body.session() == null || body.session().isBlank() ? null : session(body.session());
        Integer semester = semester(body.semester());
        if (semester != null && session == null) {
            throw new DomainRuleViolation("REG_APPROVAL_SEMESTER", "A semester's rule is set within a session.", new DomainRuleViolation.Remedy("Choose the session too.", "Academic Office"));
        }
        AuditContext ctx = AuditContextHolder.required();
        jdbc.sql("""
                INSERT INTO registration.approval_policy (session, semester, mode, allow_student_reset, card_on_approval, reason, set_by, set_office)
                VALUES (:s, :m, :mode, :reset, :card, :r, :by, (SELECT o.code FROM ref.office o WHERE o.code = :o))
                ON CONFLICT ON CONSTRAINT uq_reg_policy DO UPDATE SET mode = EXCLUDED.mode, allow_student_reset = EXCLUDED.allow_student_reset,
                    card_on_approval = EXCLUDED.card_on_approval, reason = EXCLUDED.reason, set_by = EXCLUDED.set_by, set_office = EXCLUDED.set_office, set_at = now()
                """).param("s", session, Types.VARCHAR).param("m", semester, Types.INTEGER).param("mode", mode).param("reset", body.allowStudentReset())
                .param("card", body.cardOnApproval()).param("r", body.reason().trim()).param("by", ctx.actorId()).param("o", ctx.actorOffice(), Types.VARCHAR).update();
        Map<String, Object> out = new LinkedHashMap<>(rules());
        if ("AUTO_APPROVAL".equals(mode)) out.put("processed", process(session, semester));
        return out;
    }

    private Map<String, Object> process(String session, Integer semester) {
        return jdbc.sql("SELECT * FROM registration.auto_approve_pending(:s, :m)").param("s", session, Types.VARCHAR).param("m", semester, Types.INTEGER).query().singleRow();
    }

    public record ProcessIn(@NotBlank String session, @Min(1) @Max(3) Integer semester) {
    }

    /** the registrations waiting on a Head in a session (and semester) under AUTO_APPROVAL, judged again now */
    @PostMapping("/process")
    @PreAuthorize(SETTERS)
    @Transactional
    Map<String, Object> processPending(@Valid @RequestBody ProcessIn body) {
        return process(session(body.session()), body.semester());
    }

    /** one registration held for review, judged again (after the fees are stated, the course offered, the student corrected) */
    @PostMapping("/registrations/{id}/revalidate")
    @PreAuthorize(SETTERS)
    @Transactional
    Map<String, Object> revalidate(@PathVariable UUID id) {
        Map<String, Object> r = jdbc.sql("SELECT session, semester, status FROM registration.course_registration WHERE id = :id").param("id", id)
                .query().listOfRows().stream().findFirst().orElseThrow(() -> new NotFound("course registration", id));
        if (!"SUBMITTED".equals(r.get("status"))) {
            throw new DomainRuleViolation("REG_REVALIDATE_STATUS", "Only a submitted registration is judged again; this one is " + String.valueOf(r.get("status")).toLowerCase() + ".",
                    new DomainRuleViolation.Remedy("Refresh the list.", "Academic Office"));
        }
        if (!"AUTO_APPROVAL".equals(jdbc.sql("SELECT registration.approval_mode(:s, :m)").param("s", r.get("session")).param("m", r.get("semester")).query(String.class).single())) {
            throw new DomainRuleViolation("REG_REVALIDATE_MODE", "Course registration for this semester is approved by the Head of Department.",
                    new DomainRuleViolation.Remedy("The Head of Department approves it on the approvals screen.", "Head of Department"));
        }
        String v = jdbc.sql("SELECT registration.auto_approve_checked(:id)").param("id", id).query(String.class).single();
        return Map.of("id", id, "approved", "approved".equals(v), "result", v);
    }

    private static final String SEARCH = "(CAST(:q AS text) IS NULL OR upper(v.full_name) LIKE CAST(:q AS text) OR upper(coalesce(v.matric_no, '')) LIKE CAST(:q AS text))";

    /** the figures: registered, approved (automatically or by a Head), waiting, held for review, reset, registered again, cards issued */
    @GetMapping("/overview")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> overview(@RequestParam String session, @RequestParam(required = false) Integer semester) {
        String s = session(session);
        Integer m = semester(semester);
        Map<String, Object> out = new LinkedHashMap<>(jdbc.sql("""
                SELECT count(*) FILTER (WHERE v.status <> 'DRAFT' OR v.courses > 0) AS registered,
                       count(*) FILTER (WHERE v.status IN ('APPROVED', 'LOCKED')) AS approved,
                       count(*) FILTER (WHERE v.status IN ('APPROVED', 'LOCKED') AND v.approval_mode = 'AUTO') AS auto_approved,
                       count(*) FILTER (WHERE v.status IN ('APPROVED', 'LOCKED') AND v.approval_mode = 'HOD') AS hod_approved,
                       count(*) FILTER (WHERE v.status = 'SUBMITTED') AS pending,
                       count(*) FILTER (WHERE v.review_reason IS NOT NULL) AS review,
                       count(*) FILTER (WHERE v.resets > 0) AS reset,
                       count(*) FILTER (WHERE v.reregistered) AS reregistered,
                       count(*) FILTER (WHERE v.status = 'DRAFT') AS draft,
                       count(*) FILTER (WHERE v.card_times IS NOT NULL) AS cards_issued
                  FROM registration.approval_overview(:s, :m) v
                """).param("s", s).param("m", m, Types.INTEGER).query().singleRow());
        out.put("session", s);
        out.put("semester", m);
        out.put("rule", rule(s, m == null ? 1 : m));
        return out;
    }

    /** the examination cards available (an approved registration the student is cleared for) — read apart, it asks the Bursary's
     *  clearance of each student */
    @GetMapping("/overview/cards")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> cards(@RequestParam String session, @RequestParam(required = false) Integer semester) {
        return jdbc.sql("""
                SELECT count(*) FILTER (WHERE policy.in_force('clearance', 'UNIVERSITY', current_date) IS NULL OR finance.clears(r.student_id, r.session, 'EXAMINATION')) AS available,
                       count(*) AS approved
                  FROM registration.course_registration r
                 WHERE r.session = :s AND (CAST(:m AS integer) IS NULL OR r.semester = CAST(:m AS integer)) AND r.status IN ('APPROVED', 'LOCKED')
                """).param("s", session(session)).param("m", semester(semester), Types.INTEGER).query().singleRow();
    }

    /** the registrations behind a figure, names A–Z, a page at a time */
    @GetMapping("/overview/list")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> list(@RequestParam String session, @RequestParam(required = false) Integer semester, @RequestParam(defaultValue = "ALL") String kind,
                             @RequestParam(required = false) String q, @RequestParam(defaultValue = "0") int page, @RequestParam(defaultValue = "50") int size) {
        String k = kind.trim().toUpperCase();
        if (!KINDS.contains(k)) k = "ALL";
        String filter = switch (k) {
            case "APPROVED" -> "v.status IN ('APPROVED', 'LOCKED')";
            case "AUTO_APPROVED" -> "v.status IN ('APPROVED', 'LOCKED') AND v.approval_mode = 'AUTO'";
            case "HOD_APPROVED" -> "v.status IN ('APPROVED', 'LOCKED') AND v.approval_mode = 'HOD'";
            case "PENDING" -> "v.status = 'SUBMITTED'";
            case "REVIEW" -> "v.review_reason IS NOT NULL";
            case "RESET" -> "v.resets > 0";
            case "REREGISTERED" -> "v.reregistered";
            case "CARDS_ISSUED" -> "v.card_times IS NOT NULL";
            case "DRAFT" -> "v.status = 'DRAFT'";
            default -> "(v.status <> 'DRAFT' OR v.courses > 0)";
        };
        int sz = Math.max(1, Math.min(size, 200)), pg = Math.max(0, page);
        String term = q == null || q.isBlank() ? null : "%" + q.trim().toUpperCase().replace("%", "") + "%";
        List<Map<String, Object>> rows = jdbc.sql("SELECT count(*) OVER () AS total_rows, v.* FROM registration.approval_overview(:s, :m) v WHERE " + filter + " AND " + SEARCH
                        + " ORDER BY v.full_name, v.semester LIMIT :n OFFSET :o")
                .param("s", session(session)).param("m", semester(semester), Types.INTEGER).param("q", term, Types.VARCHAR).param("n", sz).param("o", (long) pg * sz)
                .query().listOfRows();
        long total = rows.isEmpty() ? 0 : ((Number) rows.get(0).get("total_rows")).longValue();
        rows.forEach(r -> r.remove("total_rows"));
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("kind", k);
        out.put("total", total);
        out.put("page", pg);
        out.put("size", sz);
        out.put("rows", rows);
        return out;
    }
}
