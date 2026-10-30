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
 * Centre or Preliminary Science one: the same account) and reset the password, saying why — V706: back to the JAMB number (the
 * application number for an applicant with none), the applicant choosing their own at the sign-in (ApplicantPasswordGate), or the
 * applicant's own one-hour link to the email and phone they registered. Never a password the officer chooses; never the hash; every
 * reset written down (admissions.applicant_password_reset) and the applicant told.
 */
@RestController
@RequestMapping("/api/v1/applicant-passwords")
class ApplicantPasswordDeskController {

    /* V688: and the Database Operators (one over the whole University: universityOperatorOnly) */
    static final String DESK = "hasAnyAuthority('OFFICE_ict','OFFICE_academic','OFFICE_ictagent','OFFICE_helpdeskhead','OFFICE_dbops','OFFICE_super')";

    private final JdbcClient jdbc;
    private final ApplicantRepository repo;
    private final ObjectMapper json;
    private final String portalUrl;
    private final OfficeScope scope;
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
        /* V706: the first password an account is reset to — the JAMB number, or the application number where there is none */
        out.put("defaultNumber", a.jambKey() != null && !a.jambKey().isBlank() ? a.jambKey() : a.applicationNo());
        out.put("defaultKind", a.jambKey() != null && !a.jambKey().isBlank() ? "JAMB" : "APPLICATION");
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
                       (SELECT b.reference FROM admissions.applicant_password_bulk b WHERE b.id = r.bulk_id) AS bulk_ref,
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

    /** the reset: back to the JAMB number (V706), or the applicant's own link sent to them; the applicant is told either way */
    @PostMapping("/{account}/reset")
    @PreAuthorize(DESK)
    @Transactional
    Map<String, Object> reset(@PathVariable UUID account, @Valid @RequestBody ResetIn body) {
        ApplicantRepository.Account a = repo.byId(account).orElseThrow(() -> new NotFound("applicant account", account));
        String method = body.method().trim().toUpperCase();
        Map<String, Object> out = new LinkedHashMap<>();
        switch (method) {
            /* V706: back to the first password — the JAMB number, or the application number where there is none — and the applicant
               chooses their own at the sign-in; the University no longer gives a random temporary password */
            case "DEFAULT", "DEFAULT_NUMBER" -> {
                String done = jdbc.sql("SELECT admissions.applicant_password_default(:a, :r)::text")
                        .param("a", account).param("r", body.reason()).query(String.class).single();
                @SuppressWarnings("unchecked")
                Map<String, Object> r = json.readValue(done, Map.class);
                boolean jamb = "JAMB".equals(r.get("numberKind"));
                String number = jamb ? "JAMB registration number" : "application number";
                // V710: the applicant is told by email and SMS in the database (admissions.applicant_password_default), the desk and the bulk alike
                out.put("method", "DEFAULT_NUMBER");
                out.put("number", r.get("number"));
                out.put("numberKind", r.get("numberKind"));
                out.put("wasLocked", r.get("wasLocked"));
                out.put("sessionsEnded", r.get("sessionsEnded"));
                out.put("note", "The applicant signs in with their " + number + " as the password, and chooses their own password at once.");
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
            default -> throw new DomainRuleViolation("APW_METHOD", "A reset puts the password back to the applicant's JAMB number (or application number), or sends a link to their email and phone; "
                    + "a random temporary password is no longer given.", new DomainRuleViolation.Remedy("Choose DEFAULT or LINK.", "You"));
        }
        return out;
    }

    public record BulkIn(@jakarta.validation.constraints.NotNull @Size(max = 2000) List<@Size(max = 200) String> numbers, @NotBlank @Size(max = 1000) String reason,
                         Boolean commit) {
    }

    /**
     * V710: passwords reset in bulk back to the default number — the JAMB numbers, application numbers or emails given, one each, checked
     * first (commit false: what would be reset and what would not, and why) and then reset under one reference, each written down as the
     * desk's own reset is and the applicant told (admissions.applicant_password_bulk_reset).
     */
    @PostMapping("/bulk")
    @PreAuthorize(DESK)
    @Transactional
    Map<String, Object> bulk(@Valid @RequestBody BulkIn body) {
        return bulkReset(jdbc, "UNDERGRADUATE", body.numbers(), body.reason(), Boolean.TRUE.equals(body.commit()));
    }

    /** the bulk reset, undergraduate or postgraduate: the rows, the outcomes counted, the reference once committed */
    static Map<String, Object> bulkReset(JdbcClient jdbc, String kind, List<String> numbers, String reason, boolean commit) {
        // one number to a line: the list goes to the database as one text, split there
        String joined = String.join("\n", numbers.stream().map(n -> n == null ? "" : n.replaceAll("[\\r\\n]+", " ")).toList());
        List<Map<String, Object>> rows = jdbc.sql("SELECT * FROM admissions.applicant_password_bulk_reset(:k, string_to_array(:n, chr(10)), :r, :c)")
                .param("k", kind).param("n", joined).param("r", reason).param("c", commit).query().listOfRows();
        Map<String, Long> counts = new java.util.TreeMap<>();
        rows.forEach(r -> counts.merge(String.valueOf(r.get("outcome")), 1L, Long::sum));
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("committed", commit);
        out.put("bulkRef", rows.stream().map(r -> r.get("bulk_ref")).filter(java.util.Objects::nonNull).findFirst().orElse(null));
        out.put("counts", counts);
        out.put("rows", rows);
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
