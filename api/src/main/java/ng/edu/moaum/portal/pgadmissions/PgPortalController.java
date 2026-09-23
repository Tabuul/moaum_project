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

import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.Authentication;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionTemplate;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
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
    /** failures one connection may make in a window before it is refused, whatever accounts it names — so a
     *  stranger cannot keep an applicant locked out by feeding five wrong passwords every quarter hour */
    static final int SOURCE_FAILURES = 20;
    private final java.util.concurrent.ConcurrentHashMap<String, java.util.ArrayDeque<Instant>> sourceFailures = new java.util.concurrent.ConcurrentHashMap<>();

    private static String sourceOf(HttpServletRequest request) {
        String xf = request.getHeader("X-Forwarded-For");
        return xf != null && !xf.isBlank() ? xf.split(",")[0].trim() : String.valueOf(request.getRemoteAddr());
    }

    /** true when this source has failed too often in the last window; a failure is recorded by noteFailure */
    private boolean sourceThrottled(String source) {
        java.util.ArrayDeque<Instant> q = sourceFailures.get(source);
        if (q == null) return false;
        Instant floor = Instant.now().minus(LOCK_FOR);
        synchronized (q) {
            while (!q.isEmpty() && q.peekFirst().isBefore(floor)) q.pollFirst();
            return q.size() >= SOURCE_FAILURES;
        }
    }

    private void noteFailure(String source) {
        java.util.ArrayDeque<Instant> q = sourceFailures.computeIfAbsent(source, k -> new java.util.ArrayDeque<>());
        synchronized (q) { q.addLast(Instant.now()); }
        if (sourceFailures.size() > 10_000) sourceFailures.clear();   // a bound, not a policy: the window is fifteen minutes
    }
    static final UUID NOBODY = new UUID(0, 0);

    private final JdbcClient jdbc;
    private final TransactionTemplate tx;
    private final TokenIssuer issuer;
    private final BCryptPasswordEncoder encoder = new BCryptPasswordEncoder(12);
    private final SecureRandom random = new SecureRandom();
    private final String portalUrl;

    PgPortalController(JdbcClient jdbc, PlatformTransactionManager transactions, TokenIssuer issuer,
                       @org.springframework.beans.factory.annotation.Value("${moaum.portal-url:https://moaum-portal-production.up.railway.app}") String portalUrl) {
        this.jdbc = jdbc;
        this.tx = new TransactionTemplate(transactions);
        this.issuer = issuer;
        this.portalUrl = portalUrl == null ? "" : portalUrl.replaceAll("/+$", "");
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
        String source = sourceOf(request);
        if (sourceThrottled(source)) {
            throw new DomainRuleViolation("AUTH_THROTTLED", "Too many failed sign-ins from this connection; try again in fifteen minutes.",
                    new DomainRuleViolation.Remedy("Wait fifteen minutes, or reset your password with the email you applied with.", "You"));
        }
        Map<String, Object> a = firstOrNull(jdbc.sql("""
                SELECT p.id, p.surname, p.other_names, p.password_hash, p.failed_attempts, p.locked_until,
                       (SELECT ap.application_no FROM admissions.pg_application ap WHERE ap.applicant_id = p.id) AS application_no
                  FROM admissions.pg_applicant p
                 WHERE lower(p.email) = lower(:id)
                    OR EXISTS (SELECT 1 FROM admissions.pg_application ap WHERE ap.applicant_id = p.id AND ap.application_no = upper(:id))
                 LIMIT 1
                """).param("id", id).query().listOfRows());
        if (a == null) {
            noteFailure(source);
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
            noteFailure(source);
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
    Map<String, Object> feeReference(Authentication authentication, @RequestParam(required = false) String kind) {
        UUID me = UUID.fromString(authentication.getName());
        String k = kind == null || kind.isBlank() ? "APPLICATION" : kind.trim().toUpperCase();
        if (!java.util.Set.of("APPLICATION", "CHECKING", "ACCEPTANCE").contains(k)) {
            throw new DomainRuleViolation("PG_FEE_KIND", "Unknown fee.", new DomainRuleViolation.Remedy("Reload the page.", "You"));
        }
        Map<String, Object> app = firstOrNull(jdbc.sql("""
                SELECT id, fee_confirmed_at, checking_confirmed_at, acceptance_confirmed_at FROM admissions.pg_application
                 WHERE applicant_id = :me
                """).param("me", me).query().listOfRows());
        if (app == null) {
            throw new NotFound("postgraduate application", me);
        }
        String paidCol = switch (k) { case "CHECKING" -> "checking_confirmed_at"; case "ACCEPTANCE" -> "acceptance_confirmed_at"; default -> "fee_confirmed_at"; };
        if (app.get(paidCol) != null) {
            throw new DomainRuleViolation("PG_FEE_PAID", "That fee is already confirmed for this application.",
                    new DomainRuleViolation.Remedy("Nothing more to pay for it; track the application on this page.", "School of Postgraduate Studies"));
        }
        UUID appId = (UUID) app.get("id");
        Map<String, Object> live = firstOrNull(jdbc.sql("""
                SELECT reference, amount FROM admissions.pg_fee_reference
                 WHERE application_id = :app AND kind = :k AND confirmed_at IS NULL AND expires_at > now()
                 ORDER BY expires_at DESC LIMIT 1
                """).param("app", appId).param("k", k).query().listOfRows());
        Map<String, Object> ref = live != null ? live
                : AuditContextHolder.with(new AuditContext(me, "applicant", "postgraduate " + k.toLowerCase() + " fee reference", null, null),
                        () -> tx.execute(st -> {
                            String r = jdbc.sql("SELECT admissions.pg_new_fee_reference(:app, :k)")
                                    .param("app", appId).param("k", k).query(String.class).single();
                            return jdbc.sql("SELECT reference, amount FROM admissions.pg_fee_reference WHERE reference = :r")
                                    .param("r", r).query().singleRow();
                        }));
        return Map.of("reference", ref.get("reference"), "amount", ref.get("amount"), "kind", k);
    }

    private Map<String, Object> view(UUID me) {
        Map<String, Object> a = firstOrNull(jdbc.sql("""
                SELECT a.id AS application_id, a.application_no, a.state, a.entry_level, a.submitted_at, a.fee_confirmed_at,
                       a.checking_confirmed_at, a.acceptance_confirmed_at,
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
                SELECT name, email, phone, institution, position, submitted_at, verdict FROM admissions.pg_referee
                 WHERE application_id = :app ORDER BY id
                """).param("app", a.get("application_id")).query().listOfRows();
        List<Map<String, Object>> priorDegrees = jdbc.sql("""
                SELECT kind, institution, award, field, class_of_degree, cgpa, year FROM admissions.pg_prior_degree
                 WHERE application_id = :app ORDER BY CASE kind WHEN 'FIRST' THEN 0 ELSE 1 END, year
                """).param("app", a.get("application_id")).query().listOfRows();
        List<Map<String, Object>> documents = jdbc.sql("""
                SELECT id, kind, filename, content_type, uploaded_at FROM admissions.pg_document
                 WHERE application_id = :app ORDER BY uploaded_at DESC
                """).param("app", a.get("application_id")).query().listOfRows();
        Map<String, Object> feeRule = jdbc.sql("SELECT application_fee, acceptance_fee, checking_fee FROM admissions.pg_fee_rule(:s)")
                .param("s", String.valueOf(a.get("session"))).query().singleRow();
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
        // the admission decision is released only after the checking fee is paid
        boolean decisionLocked = a.get("spgs_decided_at") != null && a.get("checking_confirmed_at") == null;
        out.put("state", decisionLocked ? "DECISION_LOCKED" : a.get("state"));
        out.put("decisionLocked", decisionLocked);
        out.put("checkingConfirmedAt", a.get("checking_confirmed_at"));
        out.put("acceptanceConfirmedAt", a.get("acceptance_confirmed_at"));
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
        out.put("applicationFee", feeRule.get("application_fee"));
        out.put("acceptanceFee", feeRule.get("acceptance_fee"));
        out.put("checkingFee", feeRule.get("checking_fee"));
        out.put("liveReference", live == null ? null : live.get("reference"));
        out.put("deptNote", a.get("dept_note"));
        out.put("deptDecidedAt", a.get("dept_decided_at"));
        out.put("spgsNote", decisionLocked ? null : a.get("spgs_note"));
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
        out.put("priorDegrees", priorDegrees);
        out.put("documents", documents);
        return out;
    }

    /* ── the credentials document (one combined PDF: O'Level, A'Level, birth certificate) ── */

    static final int MAX_DOC = 8 * 1024 * 1024;
    static final int MAX_IMG = 4 * 1024 * 1024;

    public record DocumentIn(@NotBlank @Size(max = 200) String filename, @NotBlank @Size(max = 100) String contentType,
                             @NotBlank String base64, @Size(max = 40) String kind) {
    }

    /* the documents an applicant uploads, each on its own (CREDENTIALS is the old single combined PDF) */
    private static final java.util.Set<String> APPLICANT_DOC_KINDS = java.util.Set.of(
            "HIGHER_DEGREE", "UNDERGRAD_CERT", "OLEVEL", "BIRTH_CERTIFICATE", "NYSC", "LGA_CERTIFICATE", "NAME_CHANGE", "CREDENTIALS");

    /** documents and the passport are uploaded only after the application fee is confirmed */
    private void requireFeePaid(UUID appId) {
        Map<String, Object> r = firstOrNull(jdbc.sql("SELECT fee_confirmed_at FROM admissions.pg_application WHERE id = :id")
                .param("id", appId).query().listOfRows());
        if (r == null || r.get("fee_confirmed_at") == null) {
            throw new DomainRuleViolation("PG_FEE_UNPAID", "Pay the application fee before uploading your documents.",
                    new DomainRuleViolation.Remedy("Pay the application fee, then upload your credentials and passport.", "You"));
        }
    }

    /** the applicant uploads (or replaces) their combined credentials PDF (after payment) */
    @PostMapping("/documents")
    @PreAuthorize("hasAuthority('OFFICE_applicant')")
    @Transactional
    Map<String, Object> uploadDocument(Authentication authentication, @Valid @RequestBody DocumentIn body) {
        UUID me = UUID.fromString(authentication.getName());
        UUID appId = applicationOf(me);
        requireFeePaid(appId);
        String kind = body.kind() == null || body.kind().isBlank() ? "CREDENTIALS" : body.kind().trim().toUpperCase();
        if (!APPLICANT_DOC_KINDS.contains(kind)) {
            throw new DomainRuleViolation("PG_DOC_KIND", "That is not a document the application takes.",
                    new DomainRuleViolation.Remedy("Upload the document under one of the listed types.", "You"));
        }
        if (!"application/pdf".equals(body.contentType())) {
            throw new DomainRuleViolation("PG_DOC_TYPE", "Each document is a single PDF file.",
                    new DomainRuleViolation.Remedy("Scan the certificate to PDF and upload it.", "You"));
        }
        byte[] content;
        try {
            content = java.util.Base64.getDecoder().decode(body.base64());
        } catch (IllegalArgumentException notBase64) {
            throw new DomainRuleViolation("PG_DOC_ENCODING", "The file did not arrive intact.",
                    new DomainRuleViolation.Remedy("Try the upload again.", "You"));
        }
        if (content.length == 0 || content.length > MAX_DOC) {
            throw new DomainRuleViolation("PG_DOC_SIZE", "A document is between 1 byte and 8 MB; this one is " + content.length + " bytes.",
                    new DomainRuleViolation.Remedy("Reduce the scan's resolution and upload it again.", "You"));
        }
        // a higher-degree certificate may be more than one (a candidate can hold several); every other
        // kind is one document per application, so a new upload replaces the earlier one of that kind
        if (!"HIGHER_DEGREE".equals(kind)) {
            jdbc.sql("DELETE FROM admissions.pg_document WHERE application_id = :app AND kind = :k").param("app", appId).param("k", kind).update();
        }
        jdbc.sql("INSERT INTO admissions.pg_document (application_id, kind, filename, content_type, bytes) VALUES (:app, :k, :fn, :ct, :b)")
                .param("app", appId).param("k", kind).param("fn", body.filename().trim()).param("ct", body.contentType()).param("b", content)
                .update();
        return view(me);
    }

    /** the applicant removes one of their uploaded documents (not the passport) — after payment */
    @org.springframework.web.bind.annotation.DeleteMapping("/documents/{docId}")
    @PreAuthorize("hasAuthority('OFFICE_applicant')")
    @Transactional
    Map<String, Object> deleteDocument(Authentication authentication, @org.springframework.web.bind.annotation.PathVariable UUID docId) {
        UUID me = UUID.fromString(authentication.getName());
        UUID appId = applicationOf(me);
        requireFeePaid(appId);
        int n = jdbc.sql("DELETE FROM admissions.pg_document WHERE id = :d AND application_id = :app AND kind <> 'PASSPORT'")
                .param("d", docId).param("app", appId).update();
        if (n == 0) {
            throw new NotFound("document", docId);
        }
        return view(me);
    }

    /** the applicant uploads (or replaces) their passport photograph (after payment) */
    @PostMapping("/passport")
    @PreAuthorize("hasAuthority('OFFICE_applicant')")
    @Transactional
    Map<String, Object> uploadPassport(Authentication authentication, @Valid @RequestBody DocumentIn body) {
        UUID me = UUID.fromString(authentication.getName());
        UUID appId = applicationOf(me);
        requireFeePaid(appId);
        if (!"image/jpeg".equals(body.contentType()) && !"image/png".equals(body.contentType())) {
            throw new DomainRuleViolation("PG_PASSPORT_TYPE", "The passport must be a JPEG or PNG photo.",
                    new DomainRuleViolation.Remedy("Upload a clear passport photograph (JPEG or PNG).", "You"));
        }
        byte[] content;
        try {
            content = java.util.Base64.getDecoder().decode(body.base64());
        } catch (IllegalArgumentException notBase64) {
            throw new DomainRuleViolation("PG_PASSPORT_ENCODING", "The photo did not arrive intact.",
                    new DomainRuleViolation.Remedy("Try the upload again.", "You"));
        }
        if (content.length == 0 || content.length > MAX_IMG) {
            throw new DomainRuleViolation("PG_PASSPORT_SIZE", "A passport photo is between 1 byte and 4 MB; this one is " + content.length + " bytes.",
                    new DomainRuleViolation.Remedy("Reduce the photo's size and upload it again.", "You"));
        }
        jdbc.sql("DELETE FROM admissions.pg_document WHERE application_id = :app AND kind = 'PASSPORT'").param("app", appId).update();
        jdbc.sql("INSERT INTO admissions.pg_document (application_id, kind, filename, content_type, bytes) VALUES (:app, 'PASSPORT', :fn, :ct, :b)")
                .param("app", appId).param("fn", body.filename().trim()).param("ct", body.contentType()).param("b", content)
                .update();
        return view(me);
    }

    /** the applicant's own passport photograph, so it can be shown on their summary and printout */
    @GetMapping("/passport/image")
    @PreAuthorize("hasAuthority('OFFICE_applicant')")
    @Transactional(readOnly = true)
    ResponseEntity<byte[]> passportImage(Authentication authentication, @RequestParam(required = false) String format) {
        UUID me = UUID.fromString(authentication.getName());
        UUID appId = applicationOf(me);
        Map<String, Object> r = firstOrNull(jdbc.sql("""
                SELECT content_type, bytes FROM admissions.pg_document
                 WHERE application_id = :id AND kind = 'PASSPORT'
                """).param("id", appId).query().listOfRows());
        if (r == null || r.get("bytes") == null) {
            throw new NotFound("passport", appId);
        }
        byte[] bytes = (byte[]) r.get("bytes");
        String ct = String.valueOf(r.getOrDefault("content_type", "image/jpeg"));
        // the application-summary PDF can only embed JPEG, so re-encode a PNG passport to JPEG on request
        if ("jpeg".equalsIgnoreCase(format) && !ct.contains("jpeg")) {
            try {
                java.awt.image.BufferedImage src = javax.imageio.ImageIO.read(new java.io.ByteArrayInputStream(bytes));
                if (src != null) {
                    java.awt.image.BufferedImage rgb = new java.awt.image.BufferedImage(src.getWidth(), src.getHeight(), java.awt.image.BufferedImage.TYPE_INT_RGB);
                    java.awt.Graphics2D g = rgb.createGraphics();
                    g.setColor(java.awt.Color.WHITE);
                    g.fillRect(0, 0, src.getWidth(), src.getHeight());
                    g.drawImage(src, 0, 0, null);
                    g.dispose();
                    java.io.ByteArrayOutputStream baos = new java.io.ByteArrayOutputStream();
                    if (javax.imageio.ImageIO.write(rgb, "jpg", baos)) { bytes = baos.toByteArray(); ct = "image/jpeg"; }
                }
            } catch (java.io.IOException reencodeFailed) { /* fall back to the stored bytes and type */ }
        }
        return ResponseEntity.ok().contentType(MediaType.parseMediaType(ct))
                .header(HttpHeaders.CACHE_CONTROL, "private, max-age=600")
                .header(HttpHeaders.CONTENT_DISPOSITION, "inline").body(bytes);
    }

    /** email the applicant a link to sign in and download their application summary (PDF) */
    @PostMapping("/email-summary")
    @PreAuthorize("hasAuthority('OFFICE_applicant')")
    @Transactional
    Map<String, Object> emailSummary(Authentication authentication) {
        UUID me = UUID.fromString(authentication.getName());
        UUID appId = applicationOf(me);
        Map<String, Object> r = firstOrNull(jdbc.sql("""
                SELECT p.email, a.application_no FROM admissions.pg_application a
                  JOIN admissions.pg_applicant p ON p.id = a.applicant_id WHERE a.id = :id
                """).param("id", appId).query().listOfRows());
        String email = r == null ? null : (String) r.get("email");
        String no = r == null ? "" : String.valueOf(r.get("application_no"));
        if (email == null || email.isBlank()) {
            throw new DomainRuleViolation("PG_NO_EMAIL", "No email is on record for this application.",
                    new DomainRuleViolation.Remedy("Add an email to your application, then try again.", "You"));
        }
        String body = "Your MOAUM postgraduate application " + no + " summary is ready.\n\n"
                + "Sign in to view and download it as a PDF:\n" + portalUrl + "/pg/portal\n\n"
                + "Keep your application number safe — you will need it to accept an offer.";
        jdbc.sql("SELECT platform.queue_notice('EMAIL', :r, :sub, :b, 'pg_application', :ai)")
                .param("r", email).param("sub", "Your MOAUM postgraduate application summary")
                .param("b", body).param("ai", appId).query().listOfRows();
        return Map.of("ok", true, "email", email);
    }

    /* ── the academic record, supplied in the portal after payment ── */

    public record FirstDegreeIn(@Size(max = 200) String institution, @Size(max = 120) String award, @Size(max = 120) String field,
                                @Size(max = 60) String classOfDegree, @Size(max = 8) String cgpa, @Size(max = 8) String year) {
    }

    /** the applicant states (or amends) the first degree the admission rests on (after payment) */
    @PostMapping("/first-degree")
    @PreAuthorize("hasAuthority('OFFICE_applicant')")
    Map<String, Object> firstDegree(Authentication authentication, @Valid @RequestBody FirstDegreeIn body) {
        UUID me = UUID.fromString(authentication.getName());
        UUID appId = applicationOf(me);
        requireFeePaid(appId);
        String inst = trimToNull(body.institution()), award = trimToNull(body.award()), field = trimToNull(body.field()),
                cls = trimToNull(body.classOfDegree()), cgpa = trimToNull(body.cgpa()), year = trimToNull(body.year());
        AuditContextHolder.with(new AuditContext(me, "applicant", "postgraduate first degree", null, null),
                () -> tx.execute(st -> {
                    jdbc.sql("""
                            UPDATE admissions.pg_application
                               SET prior_institution = :i, prior_award = :a, prior_class = :c,
                                   prior_cgpa = nullif(regexp_replace(coalesce(:g,''), '[^0-9.]','','g'),'')::numeric,
                                   prior_year = nullif(regexp_replace(coalesce(:y,''), '[^0-9]','','g'),'')::int
                             WHERE id = :app
                            """).param("i", inst).param("a", award).param("c", cls).param("g", cgpa).param("y", year)
                            .param("app", appId).update();
                    int upd = jdbc.sql("""
                            UPDATE admissions.pg_prior_degree
                               SET institution = :i, award = :a, field = :fld, class_of_degree = :c,
                                   cgpa = nullif(regexp_replace(coalesce(:g,''), '[^0-9.]','','g'),'')::numeric,
                                   year = nullif(regexp_replace(coalesce(:y,''), '[^0-9]','','g'),'')::int
                             WHERE application_id = :app AND kind = 'FIRST'
                            """).param("i", inst).param("a", award).param("fld", field).param("c", cls)
                            .param("g", cgpa).param("y", year).param("app", appId).update();
                    if (upd == 0) {
                        jdbc.sql("""
                                INSERT INTO admissions.pg_prior_degree (application_id, kind, institution, award, field, class_of_degree, cgpa, year)
                                VALUES (:app, 'FIRST', :i, :a, :fld, :c,
                                        nullif(regexp_replace(coalesce(:g,''), '[^0-9.]','','g'),'')::numeric,
                                        nullif(regexp_replace(coalesce(:y,''), '[^0-9]','','g'),'')::int)
                                """).param("app", appId).param("i", inst).param("a", award).param("fld", field)
                                .param("c", cls).param("g", cgpa).param("y", year).update();
                    }
                    return null;
                }));
        return view(me);
    }

    public record QualIn(@Size(max = 20) String kind, @Size(max = 200) String institution, @Size(max = 120) String award,
                         @Size(max = 120) String field, @Size(max = 60) String classOfDegree, @Size(max = 8) String cgpa, @Size(max = 8) String year) {
    }

    private static final java.util.Set<String> QUAL_KINDS = java.util.Set.of("NCE", "ND", "HND", "PGD", "MASTERS", "PHD", "OTHER");

    /** the applicant states (or amends) their other qualifications — everything but the first degree (after payment) */
    @PostMapping("/qualifications")
    @PreAuthorize("hasAuthority('OFFICE_applicant')")
    Map<String, Object> qualifications(Authentication authentication, @Valid @RequestBody List<QualIn> body) {
        UUID me = UUID.fromString(authentication.getName());
        UUID appId = applicationOf(me);
        requireFeePaid(appId);
        List<QualIn> quals = body == null ? List.of() : body;
        AuditContextHolder.with(new AuditContext(me, "applicant", "postgraduate qualifications", null, null),
                () -> tx.execute(st -> {
                    jdbc.sql("DELETE FROM admissions.pg_prior_degree WHERE application_id = :app AND kind <> 'FIRST'").param("app", appId).update();
                    for (QualIn q : quals) {
                        String inst = trimToNull(q.institution()), award = trimToNull(q.award()), field = trimToNull(q.field());
                        if (inst == null && award == null && field == null) {
                            continue;
                        }
                        String kind = q.kind() == null ? "OTHER" : q.kind().trim().toUpperCase();
                        if (!QUAL_KINDS.contains(kind)) {
                            kind = "OTHER";
                        }
                        jdbc.sql("""
                                INSERT INTO admissions.pg_prior_degree (application_id, kind, institution, award, field, class_of_degree, cgpa, year)
                                VALUES (:app, :k, :i, :a, :fld, :c,
                                        nullif(regexp_replace(coalesce(:g,''), '[^0-9.]','','g'),'')::numeric,
                                        nullif(regexp_replace(coalesce(:y,''), '[^0-9]','','g'),'')::int)
                                """).param("app", appId).param("k", kind).param("i", inst).param("a", award).param("fld", field)
                                .param("c", trimToNull(q.classOfDegree())).param("g", trimToNull(q.cgpa())).param("y", trimToNull(q.year())).update();
                    }
                    return null;
                }));
        return view(me);
    }

    public record RefereeIn(@Size(max = 160) String name, @Size(max = 160) String email, @Size(max = 40) String phone,
                            @Size(max = 200) String institution, @Size(max = 120) String position) {
    }

    /** the applicant sets (or amends) their referees; each new referee with an email is sent a reference request (after payment) */
    @PostMapping("/referees")
    @PreAuthorize("hasAuthority('OFFICE_applicant')")
    Map<String, Object> referees(Authentication authentication, @Valid @RequestBody List<RefereeIn> body) {
        UUID me = UUID.fromString(authentication.getName());
        UUID appId = applicationOf(me);
        requireFeePaid(appId);
        List<RefereeIn> in = body == null ? List.of() : body;
        String applicantName = String.valueOf(jdbc.sql("""
                SELECT p.surname || ' ' || p.other_names FROM admissions.pg_application a
                  JOIN admissions.pg_applicant p ON p.id = a.applicant_id WHERE a.id = :app
                """).param("app", appId).query(String.class).single());
        AuditContextHolder.with(new AuditContext(me, "applicant", "postgraduate referees", null, null),
                () -> tx.execute(st -> {
                    // keep referees who have already given their reference; replace the rest
                    jdbc.sql("DELETE FROM admissions.pg_referee WHERE application_id = :app AND submitted_at IS NULL").param("app", appId).update();
                    for (RefereeIn r : in) {
                        String name = trimToNull(r.name());
                        if (name == null) {
                            continue;
                        }
                        String email = trimToNull(r.email());
                        // do not duplicate a referee whose reference is already in
                        if (email != null) {
                            Integer dup = jdbc.sql("SELECT count(*) FROM admissions.pg_referee WHERE application_id = :app AND lower(email) = lower(:e) AND submitted_at IS NOT NULL")
                                    .param("app", appId).param("e", email).query(Integer.class).single();
                            if (dup != null && dup > 0) {
                                continue;
                            }
                        }
                        Map<String, Object> row = jdbc.sql("""
                                INSERT INTO admissions.pg_referee (application_id, name, email, phone, institution, position)
                                VALUES (:app, :n, :e, :ph, :i, :po) RETURNING token
                                """).param("app", appId).param("n", name).param("e", email).param("ph", trimToNull(r.phone()))
                                .param("i", trimToNull(r.institution())).param("po", trimToNull(r.position())).query().singleRow();
                        if (email != null) {
                            String link = portalUrl + "/pg/referee/" + row.get("token");
                            String msg = "Dear " + name + ",\n\n" + applicantName
                                    + " has named you as a referee for a postgraduate application to the Rev. Fr. Moses Orshio Adasu University, Makurdi.\n\n"
                                    + "Please complete a short, confidential reference here:\n" + link + "\n\n"
                                    + "It asks how you know the applicant, for how long, and your academic assessment and recommendation. Thank you for your assistance.";
                            jdbc.sql("SELECT platform.queue_notice('EMAIL', :r, :sub, :b, 'pg_application', :ai)")
                                    .param("r", email).param("sub", "Reference request — " + applicantName + " (MOAUM Postgraduate)")
                                    .param("b", msg).param("ai", appId).query().listOfRows();
                        }
                    }
                    return null;
                }));
        return view(me);
    }

    private static String trimToNull(String s) {
        return s == null || s.isBlank() ? null : s.trim();
    }

    private UUID applicationOf(UUID applicant) {
        Map<String, Object> row = firstOrNull(jdbc.sql("SELECT id FROM admissions.pg_application WHERE applicant_id = :me")
                .param("me", applicant).query().listOfRows());
        if (row == null) {
            throw new NotFound("postgraduate application", applicant);
        }
        return (UUID) row.get("id");
    }
}
