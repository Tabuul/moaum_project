package ng.edu.moaum.portal.pgadmissions;

import java.security.SecureRandom;
import java.time.Duration;
import java.time.Instant;
import java.time.OffsetDateTime;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import jakarta.servlet.http.HttpServletRequest;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

import ng.edu.moaum.portal.auth.TokenIssuer;
import ng.edu.moaum.portal.shared.AuditContext;
import ng.edu.moaum.portal.shared.AuditContextHolder;
import ng.edu.moaum.portal.shared.DomainRuleViolation;
import ng.edu.moaum.portal.shared.NotFound;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.Authentication;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * The postgraduate applicant's own door and portal. Applying (V205) creates an account in
 * {@code admissions.pg_applicant} with the password the applicant chose; this signs them back in on
 * that email (or their application number), issues the same session token every other door issues, and
 * lets them see their application and pay the application fee online. The office is {@code applicant} —
 * the same audit office the public apply already writes under, and a real {@code ref.office} — so the
 * applicant's writes are attributed and the session is a proper {@code platform.session}. Every read is
 * scoped to the signed-in applicant's own id, so nothing here reaches another applicant's application.
 */
@RestController
@RequestMapping("/api/v1/pg")
class PgPortalController {

    static final Duration SESSION_LENGTH = Duration.ofHours(12);
    static final int LOCK_AFTER = 5;
    static final Duration LOCK_FOR = Duration.ofMinutes(15);
    static final UUID NOBODY = new UUID(0, 0);

    private final JdbcClient jdbc;
    private final TransactionTemplate tx;
    private final TokenIssuer issuer;
    private final BCryptPasswordEncoder encoder = new BCryptPasswordEncoder(12);
    private final SecureRandom random = new SecureRandom();

    PgPortalController(JdbcClient jdbc, PlatformTransactionManager transactions, TokenIssuer issuer) {
        this.jdbc = jdbc;
        this.tx = new TransactionTemplate(transactions);
        this.issuer = issuer;
    }

    private static Map<String, Object> firstOrNull(List<Map<String, Object>> rows) {
        return rows.isEmpty() ? null : rows.get(0);
    }

    public record SignIn(@NotBlank @Size(max = 160) String identifier, @NotBlank @Size(max = 100) String password) {
    }

    public record SignedIn(String token, Instant expiresAt, UUID applicantId, String applicationNo, String surname, String otherNames) {
    }

    private static DomainRuleViolation badCredentials() {
        return new DomainRuleViolation("AUTH_BAD_CREDENTIALS", "That email and password do not match a postgraduate application account.",
                new DomainRuleViolation.Remedy("Use the email you applied with (or your PG application number) and the password you chose; five failures lock the account for fifteen minutes.", "School of Postgraduate Studies"));
    }

    /** sign in on the email the applicant applied with, or their PG application number, and their password (public) */
    @PostMapping("/sign-in")
    SignedIn signIn(@Valid @RequestBody SignIn body, HttpServletRequest request) {
        String id = body.identifier().trim();
        Map<String, Object> a = firstOrNull(jdbc.sql("""
                SELECT p.id, p.surname, p.other_names, p.password_hash, p.failed_attempts, p.locked_until,
                       (SELECT ap.application_no FROM admissions.pg_application ap WHERE ap.applicant_id = p.id) AS application_no
                  FROM admissions.pg_applicant p
                 WHERE lower(p.email) = lower(:id)
                    OR EXISTS (SELECT 1 FROM admissions.pg_application ap WHERE ap.applicant_id = p.id AND ap.application_no = upper(:id))
                 LIMIT 1
                """).param("id", id).query().listOfRows());
        if (a == null) {
            throw badCredentials();
        }
        UUID applicantId = (UUID) a.get("id");
        OffsetDateTime lockedUntil = (OffsetDateTime) a.get("locked_until");
        if (lockedUntil != null && lockedUntil.isAfter(OffsetDateTime.now())) {
            throw new DomainRuleViolation("AUTH_LOCKED", "This account is locked after repeated failures; try again after "
                    + lockedUntil.toLocalTime().withNano(0) + ".", new DomainRuleViolation.Remedy("Wait fifteen minutes.", "You"));
        }
        int attempts = ((Number) a.get("failed_attempts")).intValue();
        if (!encoder.matches(body.password(), String.valueOf(a.get("password_hash")))) {
            int next = attempts + 1;
            OffsetDateTime lock = next >= LOCK_AFTER ? OffsetDateTime.now().plus(LOCK_FOR) : null;
            tx.execute(st -> jdbc.sql("UPDATE admissions.pg_applicant SET failed_attempts = :n, locked_until = :l WHERE id = :id")
                    .param("n", next).param("l", lock).param("id", applicantId).update());
            throw badCredentials();
        }
        byte[] sid = new byte[32];
        random.nextBytes(sid);
        Instant end = Instant.now().plus(SESSION_LENGTH);
        tx.execute(st -> {
            jdbc.sql("UPDATE admissions.pg_applicant SET failed_attempts = 0, locked_until = NULL, last_signed_in_at = now() WHERE id = :id")
                    .param("id", applicantId).update();
            jdbc.sql("INSERT INTO platform.session (id, person_id, active_office, absolute_end) VALUES (:id, :p, 'applicant', :end)")
                    .param("id", sid).param("p", applicantId).param("end", java.sql.Timestamp.from(end)).update();
            return null;
        });
        String surname = String.valueOf(a.get("surname"));
        String otherNames = String.valueOf(a.get("other_names"));
        String token = issuer.issue(applicantId, surname + ", " + otherNames, List.of("applicant"), sid, end);
        return new SignedIn(token, end, applicantId, (String) a.get("application_no"), surname, otherNames);
    }

    @PostMapping("/sign-out")
    @PreAuthorize("hasAuthority('OFFICE_applicant')")
    Map<String, Object> signOut(Authentication authentication) {
        String sid = authentication instanceof JwtAuthenticationToken t ? t.getToken().getClaimAsString("sid") : null;
        if (sid != null) {
            byte[] id = java.util.HexFormat.of().parseHex(sid);
            tx.execute(st -> jdbc.sql("UPDATE platform.session SET ended_at = now(), ended_reason = 'signed out' WHERE id = :id AND ended_at IS NULL")
                    .param("id", id).update());
        }
        return Map.of("signedOut", true);
    }

    /** the signed-in applicant's own application, with the application fee and whether it is paid */
    @GetMapping("/me")
    @PreAuthorize("hasAuthority('OFFICE_applicant')")
    Map<String, Object> me(Authentication authentication) {
        UUID me = UUID.fromString(authentication.getName());
        return view(me);
    }

    /**
     * The reference to pay the application fee against, ready for checkout. A live unpaid reference is
     * reused; a missing or expired one is minted afresh (the mint is an applicant-attributed write, since
     * admissions.pg_fee_reference is on the audit spine). Refused once the fee is already confirmed.
     */
    @PostMapping("/fee-reference")
    @PreAuthorize("hasAuthority('OFFICE_applicant')")
    Map<String, Object> feeReference(Authentication authentication) {
        UUID me = UUID.fromString(authentication.getName());
        Map<String, Object> app = firstOrNull(jdbc.sql("SELECT id, session, fee_confirmed_at FROM admissions.pg_application WHERE applicant_id = :me")
                .param("me", me).query().listOfRows());
        if (app == null) {
            throw new NotFound("postgraduate application", me);
        }
        if (app.get("fee_confirmed_at") != null) {
            throw new DomainRuleViolation("PG_FEE_PAID", "The application fee is already confirmed for this application.",
                    new DomainRuleViolation.Remedy("Nothing more to pay; track the application on this page.", "School of Postgraduate Studies"));
        }
        UUID appId = (UUID) app.get("id");
        Map<String, Object> live = firstOrNull(jdbc.sql("""
                SELECT reference, amount FROM admissions.pg_fee_reference
                 WHERE application_id = :app AND kind = 'APPLICATION' AND confirmed_at IS NULL AND expires_at > now()
                 ORDER BY expires_at DESC LIMIT 1
                """).param("app", appId).query().listOfRows());
        Map<String, Object> ref = live != null ? live
                : AuditContextHolder.with(new AuditContext(me, "applicant", "postgraduate application fee reference", null, null),
                        () -> tx.execute(st -> {
                            String r = jdbc.sql("SELECT admissions.pg_new_fee_reference(:app, 'APPLICATION')")
                                    .param("app", appId).query(String.class).single();
                            return jdbc.sql("SELECT reference, amount FROM admissions.pg_fee_reference WHERE reference = :r")
                                    .param("r", r).query().singleRow();
                        }));
        return Map.of("reference", ref.get("reference"), "amount", ref.get("amount"));
    }

    private Map<String, Object> view(UUID me) {
        Map<String, Object> a = firstOrNull(jdbc.sql("""
                SELECT a.id AS application_id, a.application_no, a.state, a.entry_level, a.submitted_at, a.fee_confirmed_at,
                       a.dept_note, a.dept_decided_at, a.spgs_note, a.spgs_decided_at, a.accepted_at, a.admitted_at, a.created_at,
                       a.prior_institution, a.prior_award, a.prior_class, a.prior_cgpa, a.prior_year,
                       a.proposal_title, a.proposal_text,
                       p.surname, p.other_names, p.email, p.phone, p.sex, p.date_of_birth, p.state_of_origin, p.lga,
                       g.code AS programme_code, g.name AS programme_name, g.pg_award, g.pg_research,
                       f.name AS faculty_name, d.name AS department_name, a.session
                  FROM admissions.pg_application a
                  JOIN admissions.pg_applicant p ON p.id = a.applicant_id
                  JOIN ref.programme g ON g.code = a.programme_code
                  JOIN ref.faculty f ON f.code = g.faculty_code
                  JOIN ref.department d ON d.code = g.dept_code
                 WHERE p.id = :me
                """).param("me", me).query().listOfRows());
        if (a == null) {
            throw new NotFound("postgraduate application", me);
        }
        List<Map<String, Object>> referees = jdbc.sql("""
                SELECT name, email, institution, position FROM admissions.pg_referee
                 WHERE application_id = :app ORDER BY id
                """).param("app", a.get("application_id")).query().listOfRows();
        Number appFee = jdbc.sql("SELECT application_fee FROM admissions.pg_fee_rule(:s)")
                .param("s", String.valueOf(a.get("session"))).query(Number.class).optional().orElse(null);
        Map<String, Object> live = firstOrNull(jdbc.sql("""
                SELECT reference, amount, expires_at FROM admissions.pg_fee_reference
                 WHERE application_id = (SELECT id FROM admissions.pg_application WHERE applicant_id = :me)
                   AND kind = 'APPLICATION' AND confirmed_at IS NULL AND expires_at > now()
                 ORDER BY expires_at DESC LIMIT 1
                """).param("me", me).query().listOfRows());
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("applicationNo", a.get("application_no"));
        out.put("session", a.get("session"));
        out.put("name", a.get("surname") + ", " + a.get("other_names"));
        out.put("surname", a.get("surname"));
        out.put("otherNames", a.get("other_names"));
        out.put("email", a.get("email"));
        out.put("phone", a.get("phone"));
        out.put("state", a.get("state"));
        out.put("entryLevel", a.get("entry_level"));
        out.put("programme", a.get("programme_name"));
        out.put("programmeCode", a.get("programme_code"));
        out.put("award", a.get("pg_award"));
        out.put("research", a.get("pg_research"));
        out.put("faculty", a.get("faculty_name"));
        out.put("department", a.get("department_name"));
        out.put("submittedAt", a.get("submitted_at"));
        out.put("createdAt", a.get("created_at"));
        out.put("feeConfirmedAt", a.get("fee_confirmed_at"));
        out.put("applicationFee", appFee);
        out.put("liveReference", live == null ? null : live.get("reference"));
        out.put("deptNote", a.get("dept_note"));
        out.put("deptDecidedAt", a.get("dept_decided_at"));
        out.put("spgsNote", a.get("spgs_note"));
        out.put("spgsDecidedAt", a.get("spgs_decided_at"));
        out.put("acceptedAt", a.get("accepted_at"));
        out.put("admittedAt", a.get("admitted_at"));
        Map<String, Object> bio = new LinkedHashMap<>();
        bio.put("sex", a.get("sex"));
        bio.put("dateOfBirth", a.get("date_of_birth"));
        bio.put("stateOfOrigin", a.get("state_of_origin"));
        bio.put("lga", a.get("lga"));
        out.put("biodata", bio);
        Map<String, Object> prior = new LinkedHashMap<>();
        prior.put("institution", a.get("prior_institution"));
        prior.put("award", a.get("prior_award"));
        prior.put("classOfDegree", a.get("prior_class"));
        prior.put("cgpa", a.get("prior_cgpa"));
        prior.put("year", a.get("prior_year"));
        out.put("prior", prior);
        Map<String, Object> proposal = new LinkedHashMap<>();
        proposal.put("title", a.get("proposal_title"));
        proposal.put("text", a.get("proposal_text"));
        out.put("proposal", proposal);
        out.put("referees", referees);
        return out;
    }
}
