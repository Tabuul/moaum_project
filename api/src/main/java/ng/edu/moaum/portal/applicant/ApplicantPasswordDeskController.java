package ng.edu.moaum.portal.applicant;

import java.security.SecureRandom;
import java.util.HexFormat;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

import ng.edu.moaum.portal.shared.DomainRuleViolation;
import ng.edu.moaum.portal.shared.NotFound;
import ng.edu.moaum.portal.shared.OfficeScope;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.ModelAttribute;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import tools.jackson.databind.ObjectMapper;

/**
 * V687 — Applicant Passwords: the Director of ICT, the Academic Office and ICT Support find a Post-UTME applicant (or a Direct Entry,
 * Centre or Preliminary Science one: the same account) and reset the password, saying why — a temporary password shown to the officer
 * once (good for 24 hours; the applicant chooses their own at the sign-in, ApplicantPasswordGate), or the applicant's own one-hour
 * link to the email and phone they registered. Never a password the officer chooses; never the hash; every reset written down
 * (admissions.applicant_password_reset) and the applicant told.
 */
@RestController
@RequestMapping("/api/v1/applicant-passwords")
class ApplicantPasswordDeskController {

    /* V688: and the Database Operators (one over the whole University: universityOperatorOnly) */
    static final String DESK = "hasAnyAuthority('OFFICE_ict','OFFICE_academic','OFFICE_ictagent','OFFICE_helpdeskhead','OFFICE_dbops','OFFICE_super')";
    private static final String TEMP_LETTERS = "ABCDEFGHJKMNPQRSTUVWXYZabcdefghjkmnpqrstuvwxyz23456789";

    private final JdbcClient jdbc;
    private final ApplicantRepository repo;
    private final ObjectMapper json;
    private final String portalUrl;
    private final OfficeScope scope;
    private final BCryptPasswordEncoder encoder = new BCryptPasswordEncoder(12);
    private final SecureRandom random = new SecureRandom();

    ApplicantPasswordDeskController(JdbcClient jdbc, ApplicantRepository repo, ObjectMapper json, OfficeScope scope,
                                    @Value("${moaum.portal-url:https://moaum-portal-production.up.railway.app}") String portalUrl) {
        this.jdbc = jdbc;
        this.repo = repo;
        this.json = json;
        this.scope = scope;
        this.portalUrl = portalUrl == null ? "" : portalUrl.replaceAll("/+$", "");
    }

    /** V688: an applicant belongs to no faculty, department or programme of the register yet, so a Database Operator resets one only
     *  on a grant over the whole University (SCOPE_UNIVERSITY otherwise); every other office passes. Asked before every request here. */
    @ModelAttribute
    void universityOperatorOnly() {
        scope.requireUniversityOperator("Resetting an applicant's password");
    }

    /** applicants by JAMB number, application number, email, phone or name (three characters or more) */
    @GetMapping("/search")
    @PreAuthorize(DESK)
    @Transactional(readOnly = true)
    List<Map<String, Object>> search(@RequestParam String q) {
        return jdbc.sql("SELECT * FROM admissions.applicant_password_find(:q, 50)").param("q", q).query().listOfRows();
    }

    /** one applicant's account as the desk sees it — never the hash — and every reset of it, newest first */
    @GetMapping("/{account}")
    @PreAuthorize(DESK)
    @Transactional(readOnly = true)
    Map<String, Object> account(@PathVariable UUID account) {
        ApplicantRepository.Account a = repo.byId(account).orElseThrow(() -> new NotFound("applicant account", account));
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("accountId", a.id());
        out.put("name", a.surname() + ", " + a.otherNames());
        out.put("jambKey", a.jambKey());
        out.put("applicationNo", a.applicationNo());
        out.put("session", a.session());
        out.put("email", a.email());
        out.put("phone", a.phone());
        out.put("failedAttempts", a.failedAttempts());
        out.put("locked", a.lockedUntil() != null && a.lockedUntil().isAfter(java.time.OffsetDateTime.now()));
        out.put("mustChange", a.mustChangePassword());
        out.put("temporaryUntil", a.mustChangePassword() && a.tempExpiresAt() != null ? a.tempExpiresAt().toString() : null);
        out.put("firstSignIn", "SET_ON_FIRST_LOGIN".equals(a.passwordHash()));
        out.put("lastSignedIn", jdbc.sql("SELECT last_signed_in_at FROM admissions.applicant_account WHERE id = :a").param("a", account)
                .query(java.time.OffsetDateTime.class).optional().map(Object::toString).orElse(null));
        out.put("resets", history(account, 50));
        return out;
    }

    /** the resets made, newest first — of one applicant, or of every applicant */
    @GetMapping("/history")
    @PreAuthorize(DESK)
    @Transactional(readOnly = true)
    List<Map<String, Object>> history(@RequestParam(required = false) UUID account, @RequestParam(defaultValue = "200") int limit) {
        return jdbc.sql("""
                SELECT r.id, r.account_id, r.method, r.reason, r.sent_to, r.expires_at, r.was_locked, r.sessions_ended, r.reset_at, r.reset_office,
                       coalesce(p.surname || ', ' || p.given_names, 'Unknown officer') AS reset_by_name,
                       c.surname || ', ' || c.other_names AS applicant, a.jamb_key, ap.application_no, a.session
                  FROM admissions.applicant_password_reset r
                  JOIN admissions.applicant_account a ON a.id = r.account_id
                  JOIN admissions.candidate c ON c.id = a.candidate_id
                  LEFT JOIN admissions.application ap ON ap.account_id = a.id
                  LEFT JOIN iam.person p ON p.id = r.reset_by
                 WHERE (:a::uuid IS NULL OR r.account_id = :a)
                 ORDER BY r.reset_at DESC
                 LIMIT :n
                """).param("a", account, java.sql.Types.OTHER).param("n", Math.max(1, Math.min(limit, 1000))).query().listOfRows();
    }

    public record ResetIn(@NotBlank String method, @NotBlank @Size(max = 1000) String reason) {
    }

    /** the reset: a temporary password shown here once, or the applicant's own link sent to them; the applicant is told either way */
    @PostMapping("/{account}/reset")
    @PreAuthorize(DESK)
    @Transactional
    Map<String, Object> reset(@PathVariable UUID account, @Valid @RequestBody ResetIn body) {
        ApplicantRepository.Account a = repo.byId(account).orElseThrow(() -> new NotFound("applicant account", account));
        String method = body.method().trim().toUpperCase();
        Map<String, Object> out = new LinkedHashMap<>();
        switch (method) {
            case "TEMPORARY", "TEMPORARY_PASSWORD" -> {
                String pw;
                do {
                    StringBuilder b = new StringBuilder(12);
                    for (int i = 0; i < 12; i++) b.append(TEMP_LETTERS.charAt(random.nextInt(TEMP_LETTERS.length())));
                    pw = b.toString();
                } while (pw.equalsIgnoreCase(a.jambKey() == null ? "" : a.jambKey()) || pw.equalsIgnoreCase(a.applicationNo() == null ? "" : a.applicationNo()));
                String done = jdbc.sql("SELECT admissions.applicant_password_temporary(:a, :h, :r, 24)::text")
                        .param("a", account).param("h", encoder.encode(pw)).param("r", body.reason()).query(String.class).single();
                @SuppressWarnings("unchecked")
                Map<String, Object> r = json.readValue(done, Map.class);
                String subject = "Your MOAUM application password was reset";
                repo.queueNotice("EMAIL", a.email(), subject, "The password of your application " + a.applicationNo() + " was reset by the University at your request. "
                        + "Sign in with the temporary password you were given; it works within 24 hours, and you will choose your own password at once. "
                        + "If you did not ask for this, contact ICT Support.", a.applicationId());
                repo.queueNotice("SMS", a.phone(), subject, "MOAUM: your application password was reset. Sign in with the temporary password you were given "
                        + "within 24 hours and choose your own.", a.applicationId());
                out.put("method", "TEMPORARY_PASSWORD");
                out.put("temporaryPassword", pw);
                out.put("expiresAt", r.get("expiresAt"));
                out.put("wasLocked", r.get("wasLocked"));
                out.put("sessionsEnded", r.get("sessionsEnded"));
                out.put("signInWith", a.jambKey() != null ? a.jambKey() : a.applicationNo());
                out.put("note", "Give it to the applicant now; it is not shown again. It works within 24 hours, and the applicant must choose their own password at the sign-in.");
            }
            case "LINK", "RESET_LINK" -> {
                byte[] raw = new byte[24];
                random.nextBytes(raw);
                String token = HexFormat.of().formatHex(raw);
                String to = String.join(" and ", java.util.stream.Stream.of(mask(a.email(), true), mask(a.phone(), false)).filter(java.util.Objects::nonNull).toList());
                String done = jdbc.sql("SELECT admissions.applicant_password_link(:a, :h, :r, :to)::text")
                        .param("a", account).param("h", ApplicantService.sha256(token)).param("r", body.reason()).param("to", to).query(String.class).single();
                @SuppressWarnings("unchecked")
                Map<String, Object> r = json.readValue(done, Map.class);
                String link = portalUrl + "/login/reset?token=" + token;
                String subject = "Reset your MOAUM application password";
                repo.queueNotice("EMAIL", a.email(), subject, "The University started a password reset for your application " + a.applicationNo()
                        + " at your request. Open this link within the hour to choose a new password: " + link
                        + " The link works once. If you did not ask for this, ignore it and contact ICT Support; your password is unchanged.", a.applicationId());
                repo.queueNotice("SMS", a.phone(), subject, "MOAUM: choose a new application password within the hour at " + link, a.applicationId());
                out.put("method", "RESET_LINK");
                out.put("sentTo", to);
                out.put("expiresAt", r.get("expiresAt"));
                out.put("note", "The link went to the applicant's email and phone. It works once, within the hour.");
            }
            default -> throw new DomainRuleViolation("APW_METHOD", "A reset is a temporary password given to the applicant, or a link sent to their email and phone.",
                    new DomainRuleViolation.Remedy("Choose TEMPORARY or LINK.", "You"));
        }
        return out;
    }

    /** an address as the desk is told it: enough to recognise, never the whole */
    static String mask(String v, boolean email) {
        if (v == null || v.isBlank()) return null;
        String t = v.trim();
        if (email) {
            int at = t.indexOf('@');
            return at <= 1 ? "***" + (at >= 0 ? t.substring(at) : "") : t.charAt(0) + "***" + t.substring(at - 1);
        }
        return t.length() <= 4 ? "****" : "*".repeat(t.length() - 4) + t.substring(t.length() - 4);
    }
}
