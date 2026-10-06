package ng.edu.moaum.portal.jupeb;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.SecureRandom;
import java.time.Duration;
import java.time.Instant;
import java.time.OffsetDateTime;
import java.util.ArrayDeque;
import java.util.HexFormat;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;

import jakarta.servlet.http.HttpServletRequest;
import jakarta.validation.Valid;
import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

import ng.edu.moaum.portal.auth.TokenIssuer;
import ng.edu.moaum.portal.shared.ApplicationWindows;
import ng.edu.moaum.portal.shared.AuditContext;
import ng.edu.moaum.portal.shared.AuditContextHolder;
import ng.edu.moaum.portal.shared.DomainRuleViolation;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.Authentication;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * The JUPEB programme's public door (V339): what the application form offers, the application itself — taken only while
 * the Director of ICT has the JUPEB application window open — and the candidate's sign-in, on the email or the application
 * number, with the same session token every other door issues. The office is {@code applicant}, as for the postgraduate
 * applicant, and the token's subject is the candidate's JUPEB application, so every portal read is scoped to it.
 * These endpoints are whitelisted in SecurityConfig; everything else under /api/v1/jupeb needs a token.
 */
@RestController
@RequestMapping("/api/v1/jupeb")
class JupebPublicController {

    static final Duration SESSION_LENGTH = Duration.ofHours(12);
    static final int LOCK_AFTER = 5;
    static final Duration LOCK_FOR = Duration.ofMinutes(15);
    static final int SOURCE_FAILURES = 20;
    static final int MIN_PASSWORD = 8;
    private static final UUID NOBODY = new UUID(0, 0);

    private final JdbcClient jdbc;
    private final TransactionTemplate tx;
    private final TokenIssuer issuer;
    private final ApplicationWindows windows;
    private final JupebView view;
    private final tools.jackson.databind.ObjectMapper json;
    private final BCryptPasswordEncoder encoder = new BCryptPasswordEncoder(12);
    private final SecureRandom random = new SecureRandom();
    private final String portalUrl;
    private final ConcurrentHashMap<String, ArrayDeque<Instant>> sourceFailures = new ConcurrentHashMap<>();

    JupebPublicController(JdbcClient jdbc, PlatformTransactionManager transactions, TokenIssuer issuer, ApplicationWindows windows, JupebView view,
                          tools.jackson.databind.ObjectMapper json,
                          @Value("${moaum.portal-url:https://moaum-portal-production.up.railway.app}") String portalUrl) {
        this.jdbc = jdbc;
        this.tx = new TransactionTemplate(transactions);
        this.issuer = issuer;
        this.windows = windows;
        this.view = view;
        this.json = json;
        this.portalUrl = portalUrl == null ? "" : portalUrl.replaceAll("/+$", "");
    }

    /** what the application form offers: the window, the fee, the undergraduate programmes, the approved combinations, the documents asked for */
    @GetMapping("/options")
    Map<String, Object> options() {
        ApplicationWindows.Window w = windows.read(ApplicationWindows.JUPEB, null);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("session", w.session());
        out.put("window", Map.of("state", w.state(), "open", w.open(), "message", w.open() || w.message() == null ? "" : w.message(),
                "opensAt", w.opensAt() == null ? "" : w.opensAt().toString(), "closesAt", w.closesAt() == null ? "" : w.closesAt().toString()));
        out.put("applicationFee", jdbc.sql("SELECT application_fee FROM jupeb.fee_setting_of(:s)").param("s", w.session()).query(java.math.BigDecimal.class).single());
        out.put("programmes", jdbc.sql("""
                SELECT g.code, g.name, f.code AS faculty_code, f.name AS faculty_name, d.name AS department_name
                  FROM ref.programme g JOIN ref.faculty f ON f.code = g.faculty_code JOIN ref.department d ON d.code = g.dept_code
                 WHERE g.category = 'UNDER GRADUATE' AND NOT g.archived
                 ORDER BY f.name, g.name
                """).query().listOfRows());
        out.put("combinations", view.combinations(true));
        out.put("documents", jdbc.sql("SELECT code, label, required, image FROM jupeb.document_kind WHERE active ORDER BY ord, label").query().listOfRows());
        return out;
    }

    public record ApplyIn(@NotBlank @Size(max = 80) String surname, @NotBlank @Size(max = 80) String firstName, @Size(max = 80) String middleName,
                          @NotBlank @Pattern(regexp = "^(F|M|Female|Male|FEMALE|MALE)$", message = "female or male") String sex,
                          @NotBlank @Pattern(regexp = "^\\d{4}-\\d{2}-\\d{2}$", message = "a date, YYYY-MM-DD") String dob,
                          @NotBlank @Pattern(regexp = "^[0-9]{11}$", message = "eleven digits") String nin,
                          @NotBlank @Email @Size(max = 160) String email,
                          @NotBlank @Pattern(regexp = "^0[0-9]{10}$", message = "an eleven-digit Nigerian number, e.g. 08012345678") String phone,
                          @NotBlank @Size(min = MIN_PASSWORD, max = 100) String password,
                          @NotBlank @Size(max = 10) String programme, @NotBlank @Size(max = 40) String combination) {
    }

    /** apply: the account, the application numbered for life, and the application fee's reference */
    @PostMapping("/apply")
    Map<String, Object> apply(@Valid @RequestBody ApplyIn body) {
        // the Director of ICT's window decides; the database refuses once more behind this
        windows.requireOpen(ApplicationWindows.JUPEB, null);
        java.time.LocalDate dob = java.time.LocalDate.parse(body.dob());
        int age = java.time.Period.between(dob, java.time.LocalDate.now()).getYears();
        if (age < 12 || age > 70) {
            throw new DomainRuleViolation("JUPEB_DOB", "That date of birth gives an age of " + age + ".",
                    new DomainRuleViolation.Remedy("Enter your date of birth as it is on your birth certificate.", "You"));
        }
        Map<String, Object> form = new LinkedHashMap<>();
        form.put("surname", body.surname());
        form.put("firstName", body.firstName());
        form.put("middleName", body.middleName());
        form.put("sex", body.sex());
        form.put("dob", body.dob());
        form.put("nin", body.nin());
        form.put("email", body.email());
        form.put("phone", body.phone());
        form.put("passwordHash", encoder.encode(body.password()));
        form.put("programme", body.programme());
        form.put("combination", body.combination());
        String j = json.writeValueAsString(form);
        try {
            return AuditContextHolder.with(new AuditContext(NOBODY, "applicant", "JUPEB application", null, null),
                    () -> tx.execute(st -> jdbc.sql("SELECT * FROM jupeb.apply(:j::jsonb)").param("j", j).query().singleRow()));
        } catch (org.springframework.dao.DuplicateKeyException raced) {
            throw new DomainRuleViolation("JUPEB_APP_EXISTS", "A JUPEB application already exists for this email.",
                    new DomainRuleViolation.Remedy("Sign in with this email to continue it.", "You"));
        }
    }

    /* ── signing in ── */

    public record SignIn(@NotBlank @Size(max = 160) String identifier, @NotBlank @Size(max = 100) String password) {
    }

    public record SignedIn(String token, Instant expiresAt, UUID applicationId, String applicationNo, String surname, String otherNames) {
    }

    private static String sourceOf(HttpServletRequest request) {
        String xf = request.getHeader("X-Forwarded-For");
        return xf != null && !xf.isBlank() ? xf.split(",")[0].trim() : String.valueOf(request.getRemoteAddr());
    }

    private boolean sourceThrottled(String source) {
        ArrayDeque<Instant> q = sourceFailures.get(source);
        if (q == null) return false;
        Instant floor = Instant.now().minus(LOCK_FOR);
        synchronized (q) {
            while (!q.isEmpty() && q.peekFirst().isBefore(floor)) q.pollFirst();
            return q.size() >= SOURCE_FAILURES;
        }
    }

    private void noteFailure(String source) {
        ArrayDeque<Instant> q = sourceFailures.computeIfAbsent(source, k -> new ArrayDeque<>());
        synchronized (q) { q.addLast(Instant.now()); }
        if (sourceFailures.size() > 10_000) sourceFailures.clear();
    }

    private static DomainRuleViolation badCredentials() {
        return new DomainRuleViolation("AUTH_BAD_CREDENTIALS", "That email or application number and password do not match a JUPEB application.",
                new DomainRuleViolation.Remedy("Use the email you applied with (or your JUPEB application number) and the password you chose; five failures lock the account for fifteen minutes.", "JUPEB Office"));
    }

    /** the account behind an email or an application number, with its latest application */
    private Map<String, Object> accountOf(String identifier) {
        return jdbc.sql("""
                SELECT acc.id, acc.email, acc.password_hash, acc.failed_attempts, acc.locked_until,
                       a.id AS application_id, a.application_no, a.surname, a.first_name, a.middle_name, a.phone
                  FROM jupeb.account acc
                  JOIN LATERAL (SELECT * FROM jupeb.application x WHERE x.account_id = acc.id
                                 ORDER BY (upper(x.application_no) = upper(:id)) DESC, x.created_at DESC LIMIT 1) a ON true
                 WHERE lower(acc.email) = lower(:id)
                    OR EXISTS (SELECT 1 FROM jupeb.application x WHERE x.account_id = acc.id AND upper(x.application_no) = upper(:id))
                 LIMIT 1
                """).param("id", identifier.trim()).query().listOfRows().stream().findFirst().orElse(null);
    }

    @PostMapping("/sign-in")
    SignedIn signIn(@Valid @RequestBody SignIn body, HttpServletRequest request) {
        String source = sourceOf(request);
        if (sourceThrottled(source)) {
            throw new DomainRuleViolation("AUTH_THROTTLED", "Too many failed sign-ins from this connection; try again in fifteen minutes.",
                    new DomainRuleViolation.Remedy("Wait fifteen minutes, or reset your password with the email you applied with.", "You"));
        }
        Map<String, Object> a = accountOf(body.identifier());
        if (a == null) {
            noteFailure(source);
            throw badCredentials();
        }
        UUID account = (UUID) a.get("id");
        OffsetDateTime lockedUntil = (OffsetDateTime) a.get("locked_until");
        if (lockedUntil != null && lockedUntil.isAfter(OffsetDateTime.now())) {
            throw new DomainRuleViolation("AUTH_LOCKED", "This account is locked after repeated failures; try again after "
                    + lockedUntil.toLocalTime().withNano(0) + ".", new DomainRuleViolation.Remedy("Wait fifteen minutes.", "You"));
        }
        if (!encoder.matches(body.password(), String.valueOf(a.get("password_hash")))) {
            int next = ((Number) a.get("failed_attempts")).intValue() + 1;
            OffsetDateTime lock = next >= LOCK_AFTER ? OffsetDateTime.now().plus(LOCK_FOR) : null;
            tx.execute(st -> jdbc.sql("UPDATE jupeb.account SET failed_attempts = :n, locked_until = :l WHERE id = :id")
                    .param("n", next).param("l", lock).param("id", account).update());
            noteFailure(source);
            throw badCredentials();
        }
        return issue(a);
    }

    private SignedIn issue(Map<String, Object> a) {
        UUID account = (UUID) a.get("id");
        UUID app = (UUID) a.get("application_id");
        byte[] sid = new byte[32];
        random.nextBytes(sid);
        Instant end = Instant.now().plus(SESSION_LENGTH);
        tx.execute(st -> {
            jdbc.sql("UPDATE jupeb.account SET failed_attempts = 0, locked_until = NULL, last_signed_in_at = now() WHERE id = :id").param("id", account).update();
            jdbc.sql("INSERT INTO platform.session (id, person_id, active_office, absolute_end) VALUES (:id, :p, 'applicant', :end)")
                    .param("id", sid).param("p", app).param("end", java.sql.Timestamp.from(end)).update();
            return null;
        });
        String surname = String.valueOf(a.get("surname"));
        String otherNames = a.get("first_name") + (a.get("middle_name") == null ? "" : " " + a.get("middle_name"));
        String token = issuer.issue(app, surname + ", " + otherNames, List.of("applicant"), sid, end);
        return new SignedIn(token, end, app, (String) a.get("application_no"), surname, otherNames);
    }

    @PostMapping("/sign-out")
    @PreAuthorize("hasAuthority('OFFICE_applicant')")
    Map<String, Object> signOut(Authentication authentication) {
        String sid = authentication instanceof JwtAuthenticationToken t ? t.getToken().getClaimAsString("sid") : null;
        if (sid != null) {
            byte[] id = HexFormat.of().parseHex(sid);
            tx.execute(st -> jdbc.sql("UPDATE platform.session SET ended_at = now(), ended_reason = 'signed out' WHERE id = :id AND ended_at IS NULL")
                    .param("id", id).update());
        }
        return Map.of("signedOut", true);
    }

    /* ── a forgotten password: a one-hour, single-use link to the email applied with ── */

    public record Forgot(@NotBlank @Size(max = 160) String identifier) {
    }

    @PostMapping("/forgot")
    ResponseEntity<Map<String, Object>> forgot(@Valid @RequestBody Forgot body) {
        Map<String, Object> a = accountOf(body.identifier());
        if (a != null) {
            byte[] raw = new byte[24];
            random.nextBytes(raw);
            String token = HexFormat.of().formatHex(raw);
            String link = portalUrl + "/jupeb/reset?token=" + token;
            UUID app = (UUID) a.get("application_id");
            AuditContextHolder.with(new AuditContext(app, "applicant", "JUPEB password reset requested", null, null), () -> tx.execute(st -> {
                jdbc.sql("INSERT INTO jupeb.password_reset (account_id, token_hash, expires_at) VALUES (:a, :h, now() + interval '1 hour')")
                        .param("a", a.get("id")).param("h", sha256(token)).update();
                jdbc.sql("SELECT platform.queue_notice('EMAIL', :to, :s, :b, 'jupeb_application', :id)").param("to", a.get("email"))
                        .param("s", "Reset your JUPEB application password")
                        .param("b", "Somebody — we hope you — asked to reset the password of JUPEB application " + a.get("application_no")
                                + ". Open this link within the hour to choose a new one: " + link + "\n\nIf you did not ask, ignore this; nothing changes until the link is used.")
                        .param("id", app).query().listOfRows();
                return null;
            }));
        }
        // the same answer whether or not the account exists
        return ResponseEntity.accepted().body(Map.of("accepted", true));
    }

    public record Reset(@NotBlank @Size(max = 100) String token, @NotBlank @Size(min = MIN_PASSWORD, max = 100) String password) {
    }

    @PostMapping("/reset")
    SignedIn reset(@Valid @RequestBody Reset body) {
        Map<String, Object> r = jdbc.sql("SELECT id, account_id, expires_at, used_at FROM jupeb.password_reset WHERE token_hash = :h")
                .param("h", sha256(body.token().trim())).query().listOfRows().stream().findFirst().orElse(null);
        if (r == null || r.get("used_at") != null || ((OffsetDateTime) r.get("expires_at")).isBefore(OffsetDateTime.now())) {
            throw new DomainRuleViolation("AUTH_RESET_TOKEN", "This reset link has expired or was already used.",
                    new DomainRuleViolation.Remedy("Ask for a new one from the JUPEB sign-in page; it is good for an hour and used once.", "You"));
        }
        String hash = encoder.encode(body.password());
        UUID account = (UUID) r.get("account_id");
        AuditContextHolder.with(new AuditContext(NOBODY, "applicant", "JUPEB password reset", null, null), () -> tx.execute(st -> {
            jdbc.sql("UPDATE jupeb.password_reset SET used_at = now() WHERE id = :id").param("id", r.get("id")).update();
            jdbc.sql("UPDATE jupeb.account SET password_hash = :h, failed_attempts = 0, locked_until = NULL WHERE id = :id").param("h", hash).param("id", account).update();
            return null;
        }));
        String email = jdbc.sql("SELECT email FROM jupeb.account WHERE id = :id").param("id", account).query(String.class).single();
        return issue(accountOf(email));
    }

    private static String sha256(String s) {
        try {
            return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(s.getBytes(StandardCharsets.UTF_8)));
        } catch (java.security.NoSuchAlgorithmException e) {
            throw new IllegalStateException(e);
        }
    }
}
