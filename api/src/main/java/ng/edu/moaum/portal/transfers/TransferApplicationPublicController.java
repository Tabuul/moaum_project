package ng.edu.moaum.portal.transfers;

import java.security.SecureRandom;
import java.sql.Types;
import java.time.Duration;
import java.time.Instant;
import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.time.ZoneId;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.TimeUnit;

import jakarta.servlet.http.HttpServletRequest;
import jakarta.validation.Valid;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

import ng.edu.moaum.portal.auth.TokenIssuer;
import ng.edu.moaum.portal.shared.AuditContext;
import ng.edu.moaum.portal.shared.AuditContextHolder;
import ng.edu.moaum.portal.shared.ClientAddress;
import ng.edu.moaum.portal.shared.DomainRuleViolation;
import ng.edu.moaum.portal.shared.Throttle;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.CacheControl;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionTemplate;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * V766: the public link a student of another university applies at, on their own, for an inter-university transfer into the
 * University (the University's request of 15 November 2026). What the public reads — the window of the session, its fee, the
 * programmes and levels taking transfer students (only while it is open; never the places), the universities on the list and the
 * documents asked for — is the database's (admissions.iut_public), cached for a minute and open to any origin like the
 * application-windows feed beside it. Applying makes the applicant's own account (admissions.iut_account: an e-mail, a phone and the
 * password's bcrypt hash; never a Post-UTME, postgraduate or JUPEB account) and the application (IUT/APP/YYYY/NNNNNN), checked by
 * admissions.iut_apply — the window open, the programme and level on its list, the particulars, one live application under a JAMB
 * number — and signs the applicant in at once under the applicant office. The door is throttled by connection (IUT_APPLY, every call;
 * IUT_SIGN_IN, every failure on an account that exists) and a field no person fills (website2) refuses a robot; the house has no captcha.
 */
@RestController
class TransferApplicationPublicController {

    static final Duration SESSION_LENGTH = Duration.ofHours(12);
    static final int LOCK_AFTER = 5;
    static final Duration LOCK_FOR = Duration.ofMinutes(15);
    static final UUID NOBODY = new UUID(0, 0);
    static final ZoneId LAGOS = ZoneId.of("Africa/Lagos");
    static final String PATH = "/transfer/apply";
    static final String TYPE = "INTER_UNIVERSITY_TRANSFER_APPLICATION";
    static final String LABEL = "Inter-university transfer application";

    private final JdbcClient jdbc;
    private final TransactionTemplate tx;
    private final TokenIssuer issuer;
    private final Throttle throttle;
    private final tools.jackson.databind.ObjectMapper json;
    private final BCryptPasswordEncoder encoder = new BCryptPasswordEncoder(12);
    private final SecureRandom random = new SecureRandom();
    private final String portalUrl;

    TransferApplicationPublicController(JdbcClient jdbc, PlatformTransactionManager transactions, TokenIssuer issuer, Throttle throttle,
                                        tools.jackson.databind.ObjectMapper json,
                                        @Value("${moaum.portal-url:https://moaum-portal-production.up.railway.app}") String portalUrl) {
        this.jdbc = jdbc;
        this.tx = new TransactionTemplate(transactions);
        this.issuer = issuer;
        this.throttle = throttle;
        this.json = json;
        this.portalUrl = portalUrl == null ? "" : portalUrl.replaceAll("/+$", "");
    }

    @SuppressWarnings("unchecked")
    private Map<String, Object> parse(String text) {
        return text == null ? new LinkedHashMap<>() : new LinkedHashMap<>(json.readValue(text, Map.class));
    }

    /* ── what the public reads ── */

    /** the options of the public form and the window as the University's website reads it: admissions.iut_public, with the window's
     *  keys in the shape of every other door of GET /api/v1/public/application-windows (type, label, session, open, opensAt from the
     *  opening day's start in Lagos, closesAt at the closing day's end, applicationPath and applicationUrl) */
    @GetMapping("/api/v1/public/inter-university-transfer")
    @Transactional(readOnly = true)
    ResponseEntity<Map<String, Object>> options(@RequestParam(required = false) String session) {
        return ResponseEntity.ok().cacheControl(CacheControl.maxAge(60, TimeUnit.SECONDS).cachePublic()).body(publicView(session));
    }

    /** the same, for the application-windows feed (ApplicationWindowsPublicController) */
    Map<String, Object> publicView(String session) {
        String s = session != null && session.trim().matches("^\\d{4}/\\d{4}$") ? session.trim() : null;
        Map<String, Object> out = parse(jdbc.sql("SELECT admissions.iut_public(:s)::text").param("s", s, Types.VARCHAR).query(String.class).single());
        @SuppressWarnings("unchecked")
        Map<String, Object> w = out.get("window") instanceof Map<?, ?> m ? new LinkedHashMap<>((Map<String, Object>) m) : new LinkedHashMap<>();
        out.put("window", window(w, (String) out.get("session")));
        return out;
    }

    /** iut_public's window with the keys every door of the feed carries */
    Map<String, Object> window(Map<String, Object> w, String session) {
        Map<String, Object> v = new LinkedHashMap<>();
        v.put("type", TYPE);
        v.put("label", LABEL);
        v.put("session", session);
        String status = w.get("status") == null ? "CLOSED" : String.valueOf(w.get("status"));
        v.put("status", status);
        v.put("open", "OPEN".equals(status));
        v.put("opensOn", w.get("opensOn"));
        v.put("closesOn", w.get("closesOn"));
        v.put("opensAt", at(w.get("opensOn"), false));
        v.put("closesAt", at(w.get("closesOn"), true));
        v.put("message", "OPEN".equals(status) ? null : w.get("message"));
        v.put("applicationPath", PATH);
        v.put("applicationUrl", portalUrl + PATH);
        return v;
    }

    /** a Lagos day as the instant it begins, or ends (23:59:59) */
    private static OffsetDateTime at(Object day, boolean end) {
        if (day == null) return null;
        LocalDate d = LocalDate.parse(String.valueOf(day));
        // given in UTC, as the application-windows feed gives every door's
        return (end ? d.atTime(23, 59, 59) : d.atStartOfDay()).atZone(LAGOS).toInstant().atOffset(java.time.ZoneOffset.UTC);
    }

    /* ── applying ── */

    /** the public form: the particulars, the programme and level from the open list, the password, and a field no person fills */
    public record Apply(@NotBlank @Size(max = 60) String surname, @NotBlank @Size(max = 120) String otherNames, @Pattern(regexp = "M|F") String sex,
                        @NotBlank @Size(max = 10) String dateOfBirth, @NotBlank @Size(max = 200) String email, @NotBlank @Size(max = 20) String phone,
                        @NotBlank @Size(max = 20) String jambRegNo, @NotBlank @Size(max = 200) String password,
                        @Size(max = 16) String universityCode, @Size(max = 200) String universityNamed, @NotBlank @Size(max = 40) String otherMatricNo,
                        @NotBlank @Size(max = 200) String otherProgramme, @NotNull @Min(100) @Max(900) Integer otherLevel,
                        @NotBlank @Size(max = 9) String otherEntrySession, @NotBlank @Size(max = 4) String otherCgpa,
                        @NotNull @Min(4) @Max(5) Integer otherCgpaScale, @NotBlank @Size(max = 20) String programme,
                        @NotNull @Min(100) @Max(900) Integer level, @NotBlank @Size(max = 2000) String reason, @Size(max = 200) String website2) {

        /** the particulars as admissions.iut_apply reads them (camelCase); the password and the honeypot never reach SQL */
        Map<String, Object> particulars() {
            Map<String, Object> p = new LinkedHashMap<>();
            p.put("surname", surname); p.put("otherNames", otherNames); p.put("sex", sex); p.put("dateOfBirth", dateOfBirth);
            p.put("email", email); p.put("phone", phone); p.put("jambRegNo", jambRegNo);
            p.put("universityCode", universityCode); p.put("universityNamed", universityNamed);
            p.put("otherMatricNo", otherMatricNo); p.put("otherProgramme", otherProgramme); p.put("otherLevel", otherLevel);
            p.put("otherEntrySession", otherEntrySession); p.put("otherCgpa", otherCgpa); p.put("otherCgpaScale", otherCgpaScale);
            p.put("programme", programme); p.put("level", level); p.put("reason", reason);
            p.values().removeIf(java.util.Objects::isNull);
            return p;
        }
    }

    public record Applied(String token, Instant expiresAt, UUID accountId, String applicationNo, String surname, String otherNames) {
    }

    /** a number or a password without its spaces */
    static String bare(String v) {
        return v == null ? "" : v.replaceAll("\\s+", "");
    }

    /** IUT_PASSWORD: eight characters or more, and not the applicant's own number (the JAMB number, or the application number) */
    static void checkPassword(String password, List<String> numbers) {
        if (password == null || password.length() < 8 || password.length() > 200) {
            throw new DomainRuleViolation("IUT_PASSWORD", "A password is eight characters or more.",
                    new DomainRuleViolation.Remedy("Choose a password of eight characters or more.", "You"));
        }
        String p = bare(password);
        if (numbers.stream().anyMatch(n -> n != null && !n.isBlank() && p.equalsIgnoreCase(bare(n)))) {
            throw new DomainRuleViolation("IUT_PASSWORD", "Your JAMB registration number or your application number cannot be your password.",
                    new DomainRuleViolation.Remedy("Choose a password that is not one of your numbers.", "You"));
        }
    }

    /** apply: the account and the application made (admissions.iut_apply, as the public door: nobody, office applicant — the window's
     *  guard holds the door), then signed in at once — a 12-hour session under the applicant office */
    @PostMapping("/api/v1/transfer-applications/apply")
    Applied apply(@Valid @RequestBody Apply body, HttpServletRequest request) {
        String source = ClientAddress.of(request);
        // every call counts, refused or made: a connection makes a handful of applications, never a run of them
        throttle.take(Throttle.Door.IUT_APPLY, source);
        if (body.website2() != null && !body.website2().isBlank()) {
            throw new DomainRuleViolation("IUT_APPLY_REFUSED", "The application could not be taken.",
                    new DomainRuleViolation.Remedy("Fill in the form on the University's page and submit it again.", "You"));
        }
        checkPassword(body.password(), List.of(body.jambRegNo()));
        String hash = encoder.encode(body.password());
        String p = json.writeValueAsString(body.particulars());
        byte[] sid = new byte[32];
        random.nextBytes(sid);
        Instant end = Instant.now().plus(SESSION_LENGTH);
        Map<String, Object> made = AuditContextHolder.with(new AuditContext(NOBODY, "applicant", "inter-university transfer application", null, null),
                () -> tx.execute(st -> {
                    Map<String, Object> m = parse(jdbc.sql("SELECT admissions.iut_apply(CAST(:p AS jsonb), :h, NULL)::text").param("p", p).param("h", hash)
                            .query(String.class).single());
                    UUID account = UUID.fromString(String.valueOf(m.get("accountId")));
                    jdbc.sql("UPDATE admissions.iut_account SET last_signed_in_at = now() WHERE id = :id").param("id", account).update();
                    jdbc.sql("INSERT INTO platform.session (id, person_id, active_office, absolute_end) VALUES (:id, :p, 'applicant', :end)")
                            .param("id", sid).param("p", account).param("end", java.sql.Timestamp.from(end)).update();
                    m.putAll(jdbc.sql("SELECT surname, other_names FROM admissions.iut_application WHERE id = :a")
                            .param("a", UUID.fromString(String.valueOf(m.get("applicationId")))).query().singleRow());
                    return m;
                }));
        UUID account = UUID.fromString(String.valueOf(made.get("accountId")));
        String surname = String.valueOf(made.get("surname"));
        String otherNames = String.valueOf(made.get("other_names"));
        String token = issuer.issue(account, surname + ", " + otherNames, List.of("applicant"), sid, end);
        return new Applied(token, end, account, String.valueOf(made.get("applicationNo")), surname, otherNames);
    }

    /* ── signing in ── */

    public record SignIn(@NotBlank @Size(max = 200) String identifier, @NotBlank @Size(max = 200) String password) {
    }

    /** the answer has the shape of the postgraduate door's (PgPortalController.SignedIn), the account's id for the applicant's */
    public record SignedIn(String token, Instant expiresAt, UUID accountId, String applicationNo, String surname, String otherNames, boolean mustChange) {
    }

    private static DomainRuleViolation badCredentials() {
        return new DomainRuleViolation("AUTH_BAD_CREDENTIALS", "That e-mail or application number and password do not match a transfer application account.",
                new DomainRuleViolation.Remedy("Use the e-mail you applied with, or your application number (IUT/APP/…), and the password you chose; five failures lock the account for fifteen minutes.", "You"));
    }

    /** sign in on the e-mail the applicant applied with, or an application number of theirs, and the password (PgPortalController.signIn's
     *  rules: an unknown name is not counted — the sign-in page tries this door for every e-mail — and five failures lock the account) */
    @PostMapping("/api/v1/transfer-applications/sign-in")
    SignedIn signIn(@Valid @RequestBody SignIn body, HttpServletRequest request) {
        String id = body.identifier().trim();
        String source = ClientAddress.of(request);
        throttle.refuse(Throttle.Door.IUT_SIGN_IN, source);
        Map<String, Object> a = jdbc.sql("""
                SELECT acc.id, acc.password_hash, acc.failed_attempts,
                       coalesce(acc.locked_until > now(), false) AS locked, to_char(acc.locked_until AT TIME ZONE 'Africa/Lagos', 'HH24:MI') AS locked_until_text,
                       ap.application_no, ap.surname, ap.other_names
                  FROM admissions.iut_account acc
                  JOIN LATERAL (SELECT x.application_no, x.surname, x.other_names FROM admissions.iut_application x
                                 WHERE x.account_id = acc.id ORDER BY x.created_at DESC LIMIT 1) ap ON true
                 WHERE lower(acc.email) = lower(:id)
                    OR EXISTS (SELECT 1 FROM admissions.iut_application x WHERE x.account_id = acc.id AND x.application_no = upper(:id))
                 LIMIT 1
                """).param("id", id).query().listOfRows().stream().findFirst().orElse(null);
        if (a == null) {
            throw badCredentials();
        }
        UUID account = (UUID) a.get("id");
        if (Boolean.TRUE.equals(a.get("locked"))) {
            throttle.count(Throttle.Door.IUT_SIGN_IN, source);
            throw new DomainRuleViolation("AUTH_LOCKED", "This account is locked after repeated failures; try again after " + a.get("locked_until_text") + ".",
                    new DomainRuleViolation.Remedy("Wait fifteen minutes, or choose Forgot password and give your transfer application number (IUT/APP/…).", "You"));
        }
        if (!encoder.matches(body.password(), String.valueOf(a.get("password_hash")))) {
            int next = ((Number) a.get("failed_attempts")).intValue() + 1;
            OffsetDateTime lock = next >= LOCK_AFTER ? OffsetDateTime.now().plus(LOCK_FOR) : null;
            tx.execute(st -> jdbc.sql("UPDATE admissions.iut_account SET failed_attempts = :n, locked_until = :l WHERE id = :id")
                    .param("n", next).param("l", lock).param("id", account).update());
            throttle.count(Throttle.Door.IUT_SIGN_IN, source);
            throw badCredentials();
        }
        byte[] sid = new byte[32];
        random.nextBytes(sid);
        Instant end = Instant.now().plus(SESSION_LENGTH);
        tx.execute(st -> {
            jdbc.sql("UPDATE admissions.iut_account SET failed_attempts = 0, locked_until = NULL, last_signed_in_at = now() WHERE id = :id").param("id", account).update();
            jdbc.sql("INSERT INTO platform.session (id, person_id, active_office, absolute_end) VALUES (:id, :p, 'applicant', :end)")
                    .param("id", sid).param("p", account).param("end", java.sql.Timestamp.from(end)).update();
            return null;
        });
        String surname = String.valueOf(a.get("surname"));
        String otherNames = String.valueOf(a.get("other_names"));
        String token = issuer.issue(account, surname + ", " + otherNames, List.of("applicant"), sid, end);
        return new SignedIn(token, end, account, (String) a.get("application_no"), surname, otherNames, false);
    }
}
