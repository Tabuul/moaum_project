package ng.edu.moaum.portal.jupeb;

import java.math.BigDecimal;
import java.sql.Types;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;

import jakarta.validation.Valid;
import jakarta.validation.constraints.DecimalMax;
import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

import ng.edu.moaum.portal.shared.AuditContextHolder;
import ng.edu.moaum.portal.shared.DomainRuleViolation;
import ng.edu.moaum.portal.shared.NotFound;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.core.Authentication;
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
 * The JUPEB fees are the Bursary's (V339): the application fee, the four school fees (Science or other, indigene or not), the
 * first semester's share, whether the whole fee may be paid at once, what activates a student, the indigene state, and which
 * faculties count as Science. A session without its own rule takes the default ('*'). A change reaches only references
 * generated after it: a candidate's school fee is frozen when first charged. The JUPEB Office and the auditors read; only the
 * Bursar sets, and confirms a bank payment by hand.
 */
@RestController
@RequestMapping("/api/v1/jupeb/fees")
class JupebFeesController {

    static final String READ = "hasAnyAuthority('OFFICE_bursar','OFFICE_jupeb','OFFICE_super','OFFICE_admin','OFFICE_audit')";
    static final String BURSAR = "hasAnyAuthority('OFFICE_bursar','OFFICE_super')";

    private final JdbcClient jdbc;

    JupebFeesController(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    @GetMapping
    @PreAuthorize(READ)
    @Transactional(readOnly = true)
    Map<String, Object> read(@RequestParam(required = false) String session) {
        String current = jdbc.sql("SELECT jupeb.current_session()").query(String.class).single();
        String s = session == null || session.isBlank() ? current : session.trim();
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("session", s);
        out.put("currentSession", current);
        out.put("sessions", jdbc.sql("SELECT name FROM policy.academic_session ORDER BY name DESC").query(String.class).list());
        out.put("own", jdbc.sql("SELECT EXISTS (SELECT 1 FROM jupeb.fee_setting WHERE session = :s)").param("s", s).query(Boolean.class).single());
        out.put("rule", jdbc.sql("""
                SELECT f.session, f.application_fee, f.checking_fee, f.acceptance_fee, f.first_percent, f.allow_full, f.activation, f.indigene_state, f.updated_at, f.updated_office,
                       p.surname || ', ' || p.given_names AS updated_by
                  FROM jupeb.fee_setting_of(:s) f LEFT JOIN iam.person p ON p.id = f.updated_by
                """).param("s", s).query().singleRow());
        out.put("schoolFees", jdbc.sql("""
                SELECT c.category, c.indigene, jupeb.school_fee_amount(:s, c.category, c.indigene) AS amount,
                       EXISTS (SELECT 1 FROM jupeb.school_fee x WHERE x.session = :s AND x.category = c.category AND x.indigene = c.indigene) AS own
                  FROM (VALUES ('OTHER', true), ('SCIENCE', true), ('OTHER', false), ('SCIENCE', false)) c(category, indigene)
                """).param("s", s).query().listOfRows());
        out.put("faculties", jdbc.sql("""
                SELECT f.code, f.name, coalesce(fc.category, 'OTHER') AS category, fc.id IS NOT NULL AS stated
                  FROM ref.faculty f LEFT JOIN jupeb.fee_category fc ON fc.faculty_code = f.code ORDER BY f.name
                """).query().listOfRows());
        out.put("history", jdbc.sql("""
                SELECT session, application_fee, checking_fee, acceptance_fee, first_percent, allow_full, activation, indigene_state, updated_at, updated_office FROM jupeb.fee_setting ORDER BY session DESC
                """).query().listOfRows());
        return out;
    }

    public record SchoolFee(@NotBlank @Pattern(regexp = "SCIENCE|OTHER") String category, boolean indigene,
                            @NotNull @DecimalMin("1") @DecimalMax("100000000") BigDecimal amount) {
    }

    public record Rule(@NotBlank String session, @NotNull @DecimalMin("0") @DecimalMax("10000000") BigDecimal applicationFee,
                       @NotNull @DecimalMin("0") @DecimalMax("10000000") BigDecimal checkingFee, @NotNull @DecimalMin("0") @DecimalMax("10000000") BigDecimal acceptanceFee,
                       @NotNull @DecimalMin("1") @DecimalMax("100") BigDecimal firstPercent, boolean allowFull,
                       @NotBlank @Pattern(regexp = "FIRST_INSTALMENT|FULL") String activation, @NotBlank @Size(max = 60) String indigeneState,
                       @NotNull @Size(min = 4, max = 4) List<@Valid SchoolFee> schoolFees) {
    }

    /** the Bursar states the rule for a session ('*' for the default every session without its own takes) */
    @PutMapping
    @PreAuthorize(BURSAR)
    @Transactional
    Map<String, Object> save(@Valid @RequestBody Rule b) {
        String s = b.session().trim();
        if (!"*".equals(s) && jdbc.sql("SELECT NOT EXISTS (SELECT 1 FROM policy.academic_session WHERE name = :s)").param("s", s).query(Boolean.class).single()) {
            throw new NotFound("academic session", s);
        }
        Set<String> seen = new java.util.HashSet<>();
        for (SchoolFee f : b.schoolFees()) {
            if (!seen.add(f.category() + f.indigene())) {
                throw new DomainRuleViolation("JUPEB_FEE_TWICE", "Each of the four school fees is stated once.",
                        new DomainRuleViolation.Remedy("State Science and Other, for indigenes and non-indigenes.", "Bursary"));
            }
        }
        var ctx = AuditContextHolder.required();
        jdbc.sql("""
                INSERT INTO jupeb.fee_setting (session, application_fee, checking_fee, acceptance_fee, first_percent, allow_full, activation, indigene_state, updated_by, updated_office)
                VALUES (:s, :af, :cf, :acf, :fp, :full, :act, :st, :by, :office)
                ON CONFLICT (session) DO UPDATE SET application_fee = EXCLUDED.application_fee, checking_fee = EXCLUDED.checking_fee, acceptance_fee = EXCLUDED.acceptance_fee,
                       first_percent = EXCLUDED.first_percent, allow_full = EXCLUDED.allow_full,
                       activation = EXCLUDED.activation, indigene_state = EXCLUDED.indigene_state, updated_by = EXCLUDED.updated_by,
                       updated_office = EXCLUDED.updated_office, updated_at = now()
                """).param("s", s).param("af", b.applicationFee()).param("cf", b.checkingFee()).param("acf", b.acceptanceFee()).param("fp", b.firstPercent()).param("full", b.allowFull()).param("act", b.activation())
                .param("st", b.indigeneState().trim()).param("by", ctx.actorId()).param("office", ctx.actorOffice(), Types.VARCHAR).update();
        for (SchoolFee f : b.schoolFees()) {
            jdbc.sql("""
                    INSERT INTO jupeb.school_fee (session, category, indigene, amount, updated_by, updated_office) VALUES (:s, :c, :i, :a, :by, :office)
                    ON CONFLICT (session, category, indigene) DO UPDATE SET amount = EXCLUDED.amount, updated_by = EXCLUDED.updated_by,
                           updated_office = EXCLUDED.updated_office, updated_at = now()
                    """).param("s", s).param("c", f.category()).param("i", f.indigene()).param("a", f.amount()).param("by", ctx.actorId())
                    .param("office", ctx.actorOffice(), Types.VARCHAR).update();
        }
        return read("*".equals(s) ? null : s);
    }

    public record Category(@NotBlank String faculty, @NotBlank @Pattern(regexp = "SCIENCE|OTHER") String category) {
    }

    public record Categories(@NotNull @Size(max = 200) List<@Valid Category> faculties) {
    }

    /** which faculties' programmes pay the Science fee */
    @PutMapping("/categories")
    @PreAuthorize(BURSAR)
    @Transactional
    Map<String, Object> categories(@Valid @RequestBody Categories b) {
        var ctx = AuditContextHolder.required();
        for (Category c : b.faculties()) {
            int n = jdbc.sql("""
                    INSERT INTO jupeb.fee_category (faculty_code, category, updated_by) SELECT code, :c, :by FROM ref.faculty WHERE code = :f
                    ON CONFLICT (faculty_code) DO UPDATE SET category = EXCLUDED.category, updated_by = EXCLUDED.updated_by, updated_at = now()
                    """).param("f", c.faculty().trim()).param("c", c.category()).param("by", ctx.actorId()).update();
            if (n == 0) throw new NotFound("faculty", c.faculty());
        }
        return read(null);
    }

    /** the JUPEB payments of a session: what was charged, what is confirmed — for the Bursary and the JUPEB Office to read */
    @GetMapping("/payments")
    @PreAuthorize(READ)
    @Transactional(readOnly = true)
    List<Map<String, Object>> payments(@RequestParam(required = false) String session, @RequestParam(required = false) String status) {
        String s = session == null || session.isBlank() ? jdbc.sql("SELECT jupeb.current_session()").query(String.class).single() : session.trim();
        String st = status == null ? "" : status.trim().toUpperCase();
        return jdbc.sql("""
                SELECT fr.reference, fr.kind, fr.amount, fr.semester, fr.created_at, fr.expires_at, fr.confirmed_at, fr.channel,
                       a.application_no, a.surname || ', ' || a.first_name || coalesce(' ' || a.middle_name, '') AS name, a.state, a.exam_no
                  FROM jupeb.fee_reference fr JOIN jupeb.application a ON a.id = fr.application_id
                 WHERE fr.session = :s AND (:st = '' OR (:st = 'CONFIRMED') = (fr.confirmed_at IS NOT NULL))
                 ORDER BY coalesce(fr.confirmed_at, fr.created_at) DESC LIMIT 20000
                """).param("s", s).param("st", st).query().listOfRows();
    }

    public record Manual(@NotBlank @Size(max = 120) String channel, @NotBlank @Size(max = 600) String reason) {
    }

    /* ── V350: the refund claims of withdrawn JUPEB candidates, decided by the Bursary through its own refund workflow ── */

    /** the claims, with the payments, the refunds raised on them and where each stands; the account number whole only to the Bursary */
    @GetMapping("/refund-claims")
    @PreAuthorize(READ)
    @Transactional(readOnly = true)
    List<Map<String, Object>> refundClaims(Authentication auth, @RequestParam(required = false) String status) {
        boolean bursary = auth.getAuthorities().stream().anyMatch(g -> Set.of("OFFICE_bursar", "OFFICE_super").contains(g.getAuthority()));
        List<Map<String, Object>> rows = jdbc.sql("""
                SELECT c.id, c.application_id, a.application_no, upper(a.surname) || ', ' || a.first_name || coalesce(' ' || a.middle_name, '') AS name, a.session,
                       a.email, a.phone, c.opened_at, c.payments::text AS payments, c.paid_total, c.bank_name, c.account_name, c.account_number, c.details_at,
                       c.declined_at, c.declined_reason, (SELECT p.surname || ', ' || p.given_names FROM iam.person p WHERE p.id = c.declined_by) AS declined_by_name,
                       jupeb.refund_claim_state(c.id)::text AS state,
                       (SELECT coalesce(jsonb_agg(jsonb_build_object('id', f.id, 'reference', f.reference, 'source', x.reference, 'amount', f.amount, 'state', f.state,
                                                                     'proposedAt', f.proposed_at, 'approvedAt', f.approved_at, 'paidAt', f.paid_at, 'rejectedWhy', f.rejected_why)
                                                  ORDER BY f.proposed_at), '[]'::jsonb)::text
                          FROM jupeb.refund_claim_refund x JOIN finance.refund f ON f.id = x.refund_id WHERE x.claim_id = c.id) AS refunds
                  FROM jupeb.refund_claim c JOIN jupeb.application a ON a.id = c.application_id
                 ORDER BY c.declined_at IS NOT NULL, c.opened_at DESC LIMIT 500
                """).query().listOfRows();
        String want = status == null || status.isBlank() ? null : status.trim().toUpperCase();
        List<Map<String, Object>> out = new java.util.ArrayList<>();
        for (Map<String, Object> r : rows) {
            Map<String, Object> m = new LinkedHashMap<>(r);
            m.put("state", JupebView.readJson(String.valueOf(r.get("state"))));
            m.put("payments", JupebView.readJson(String.valueOf(r.get("payments"))));
            m.put("refunds", JupebView.readJson(String.valueOf(r.get("refunds"))));
            Object n = r.get("account_number");
            if (!bursary && n != null) m.put("account_number", "••••••" + String.valueOf(n).substring(6));
            if (want != null && !want.equals(String.valueOf(((Map<?, ?>) m.get("state")).get("status")))) continue;
            out.add(m);
        }
        return out;
    }

    public record ClaimRefundIn(@NotBlank @Size(max = 60) String reference, @NotNull @DecimalMin("0.01") BigDecimal amount, @NotBlank @Size(min = 5, max = 400) String reason) {
    }

    /** a refund raised on a claim against one of the candidate's payments: it then waits in Refunds for a second officer's approval */
    @PostMapping("/refund-claims/{id}/refunds")
    @PreAuthorize(BURSAR)
    @Transactional
    Map<String, Object> proposeClaimRefund(@PathVariable java.util.UUID id, @Valid @RequestBody ClaimRefundIn b) {
        java.util.UUID refund = jdbc.sql("SELECT jupeb.propose_claim_refund(:c, :r, :a, :w)").param("c", id).param("r", b.reference()).param("a", b.amount())
                .param("w", b.reason()).query(java.util.UUID.class).single();
        return jdbc.sql("SELECT id, reference, amount, state FROM finance.refund WHERE id = :id").param("id", refund).query().singleRow();
    }

    public record DeclineIn(@NotBlank @Size(min = 5, max = 1000) String reason) {
    }

    @PostMapping("/refund-claims/{id}/decline")
    @PreAuthorize(BURSAR)
    @Transactional
    Map<String, Object> declineClaim(@PathVariable java.util.UUID id, @Valid @RequestBody DeclineIn b) {
        jdbc.sql("SELECT jupeb.decline_refund_claim(:c, :r, :by)").param("c", id).param("r", b.reason()).param("by", AuditContextHolder.required().actorId()).query().listOfRows();
        return Map.of("id", id, "declined", true);
    }

    /** a payment made at the bank, confirmed by the Bursar from the teller: the reason is kept on the spine */
    @PostMapping("/payments/{reference}/confirm")
    @PreAuthorize(BURSAR)
    @Transactional
    Map<String, Object> confirm(@PathVariable String reference, @Valid @RequestBody Manual b) {
        if (!jdbc.sql("SELECT EXISTS (SELECT 1 FROM jupeb.fee_reference WHERE upper(reference) = upper(btrim(:r)))").param("r", reference).query(Boolean.class).single()) {
            throw new NotFound("JUPEB fee reference", reference);
        }
        jdbc.sql("SELECT set_config('moaum.reason', :r, true)").param("r", "Bank payment confirmed: " + b.reason().trim()).query().listOfRows();
        String outcome = jdbc.sql("SELECT jupeb.confirm_fee(:r, :c)").param("r", reference).param("c", b.channel().trim()).query(String.class).single();
        return Map.of("reference", reference.trim().toUpperCase(), "outcome", outcome);
    }
}
