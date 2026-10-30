package ng.edu.moaum.portal.pgadmissions;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.SecureRandom;
import java.util.HexFormat;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
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
 * V706 — Postgraduate Applicant Passwords: the Dean of the School of Postgraduate Studies, its Secretary, the Director of ICT and ICT
 * Support — V710: and the Academic Office and the Database Operators (one over the whole University) — find a postgraduate applicant (by
 * the application number, the old portal's, the email, the phone or a name) and reset the password, saying why: back to the application
 * number, the applicant choosing their own at the sign-in before anything else (the API's ApplicantPasswordGate), or (V710) the applicant's
 * own one-hour link to the email and phone they applied with; or many at once from a list (V710). Never a password the officer chooses;
 * never the hash; every reset written down (admissions.pg_applicant_password_reset) and the applicant told.
 */
@RestController
@RequestMapping("/api/v1/pg/applicant-passwords")
class PgApplicantPasswordDeskController {

    static final String DESK = "hasAnyAuthority('OFFICE_pgschool','OFFICE_pgsecretary','OFFICE_ict','OFFICE_ictagent','OFFICE_helpdeskhead','OFFICE_academic','OFFICE_dbops','OFFICE_super')";

    private final JdbcClient jdbc;
    private final ObjectMapper json;
    private final OfficeScope scope;
    private final String portalUrl;
    private final SecureRandom random = new SecureRandom();

    PgApplicantPasswordDeskController(JdbcClient jdbc, ObjectMapper json, OfficeScope scope,
                                      @Value("${moaum.portal-url:https://moaum-portal-production.up.railway.app}") String portalUrl) {
        this.jdbc = jdbc;
        this.json = json;
        this.scope = scope;
        this.portalUrl = portalUrl == null ? "" : portalUrl.replaceAll("/+$", "");
    }

    /** V710: an applicant belongs to no faculty, department or programme of the register, so a Database Operator resets one only on a
     *  grant over the whole University (SCOPE_UNIVERSITY otherwise), as on the undergraduate desk (V688); every other office passes */
    @ModelAttribute
    void universityOperatorOnly() {
        scope.requireUniversityOperator("Resetting a postgraduate applicant's password");
    }

    /** applicants by application number (or the old portal's), email, phone or name (three characters or more) */
    @GetMapping("/search")
    @PreAuthorize(DESK)
    @Transactional(readOnly = true)
    List<Map<String, Object>> search(@RequestParam String q) {
        return jdbc.sql("SELECT * FROM admissions.pg_applicant_password_find(:q, 50)").param("q", q).query().listOfRows();
    }

    /** one applicant's account as the desk sees it — never the hash — and every reset of it, newest first */
    @GetMapping("/{applicant}")
    @PreAuthorize(DESK)
    @Transactional(readOnly = true)
    Map<String, Object> account(@PathVariable UUID applicant) {
        List<Map<String, Object>> rows = jdbc.sql("""
                SELECT p.id AS "applicantId", p.surname || ', ' || p.other_names AS name, a.application_no AS "applicationNo",
                       lg.legacy_application_no AS "legacyApplicationNo", coalesce(a.session, p.session) AS session, p.email, p.phone,
                       pr.name AS programme, a.state, p.failed_attempts AS "failedAttempts", coalesce(p.locked_until > now(), false) AS locked,
                       p.must_change_password AS "mustChange", p.last_signed_in_at AS "lastSignedIn", p.password_reset_at AS "resetAt"
                  FROM admissions.pg_applicant p
                  LEFT JOIN admissions.pg_application a ON a.applicant_id = p.id
                  LEFT JOIN admissions.pg_legacy_application lg ON lg.application_id = a.id
                  LEFT JOIN ref.programme pr ON pr.code = a.programme_code
                 WHERE p.id = :p
                 LIMIT 1
                """).param("p", applicant).query().listOfRows();
        if (rows.isEmpty()) {
            throw new NotFound("postgraduate applicant", applicant);
        }
        Map<String, Object> out = new LinkedHashMap<>(rows.get(0));
        out.put("resets", history(applicant, 50));
        return out;
    }

    /** the resets made, newest first — of one applicant, or of every postgraduate applicant */
    @GetMapping("/history")
    @PreAuthorize(DESK)
    @Transactional(readOnly = true)
    List<Map<String, Object>> history(@RequestParam(required = false) UUID applicant, @RequestParam(defaultValue = "200") int limit) {
        return jdbc.sql("""
                SELECT r.id, r.applicant_id, r.method, r.application_no, r.reason, r.sent_to, r.expires_at, r.was_locked, r.sessions_ended, r.reset_at,
                       r.reset_office, b.reference AS bulk_ref,
                       coalesce(o.surname || ', ' || o.given_names, 'Unknown officer') AS reset_by_name,
                       p.surname || ', ' || p.other_names AS applicant, p.email, coalesce(a.session, p.session) AS session
                  FROM admissions.pg_applicant_password_reset r
                  JOIN admissions.pg_applicant p ON p.id = r.applicant_id
                  LEFT JOIN admissions.pg_application a ON a.applicant_id = p.id
                  LEFT JOIN admissions.applicant_password_bulk b ON b.id = r.bulk_id
                  LEFT JOIN iam.person o ON o.id = r.reset_by
                 WHERE (:p::uuid IS NULL OR r.applicant_id = :p)
                 ORDER BY r.reset_at DESC
                 LIMIT :n
                """).param("p", applicant, java.sql.Types.OTHER).param("n", Math.max(1, Math.min(limit, 1000))).query().listOfRows();
    }

    public record ResetIn(@Size(max = 20) String method, @NotBlank @Size(max = 1000) String reason) {
    }

    /** the reset: back to the application number (the applicant chooses their own at the sign-in), or the applicant's own link sent to them
     *  (V710); the applicant is told either way */
    @PostMapping("/{applicant}/reset")
    @PreAuthorize(DESK)
    @Transactional
    Map<String, Object> reset(@PathVariable UUID applicant, @Valid @RequestBody ResetIn body) {
        String method = body.method() == null || body.method().isBlank() ? "DEFAULT" : body.method().trim().toUpperCase();
        Map<String, Object> out = new LinkedHashMap<>();
        switch (method) {
            case "DEFAULT", "DEFAULT_NUMBER" -> {
                String done = jdbc.sql("SELECT admissions.pg_applicant_password_default(:p, :r)::text")
                        .param("p", applicant).param("r", body.reason()).query(String.class).single();
                @SuppressWarnings("unchecked")
                Map<String, Object> r = json.readValue(done, Map.class);
                out.put("method", "DEFAULT_NUMBER");
                out.put("applicationNo", r.get("applicationNo"));
                out.put("wasLocked", r.get("wasLocked"));
                out.put("sessionsEnded", r.get("sessionsEnded"));
                out.put("note", "The applicant signs in with their email or application number, and the application number as the password, then chooses their own password at once.");
            }
            case "LINK", "RESET_LINK" -> {
                Map<String, Object> who = jdbc.sql("SELECT email, phone FROM admissions.pg_applicant WHERE id = :p").param("p", applicant).query().listOfRows()
                        .stream().findFirst().orElseThrow(() -> new NotFound("postgraduate applicant", applicant));
                String email = (String) who.get("email");
                String phone = (String) who.get("phone");
                byte[] raw = new byte[24];
                random.nextBytes(raw);
                String token = HexFormat.of().formatHex(raw);
                String to = String.join(" and ", java.util.stream.Stream.of(mask(email, true), mask(phone, false)).filter(java.util.Objects::nonNull).toList());
                String done = jdbc.sql("SELECT admissions.pg_applicant_password_link(:p, :h, :r, :to)::text")
                        .param("p", applicant).param("h", sha256(token)).param("r", body.reason()).param("to", to).query(String.class).single();
                @SuppressWarnings("unchecked")
                Map<String, Object> r = json.readValue(done, Map.class);
                // the sign-in page's own reset (/login/reset, iam.password_reset: PGAPPLICANT)
                String link = portalUrl + "/login/reset?token=" + token;
                String subject = "Reset your MOAUM postgraduate application password";
                UUID app = r.get("applicationId") == null ? null : UUID.fromString(String.valueOf(r.get("applicationId")));
                if (email != null && !email.isBlank()) {
                    jdbc.sql("SELECT platform.queue_notice('EMAIL', :to, :s, :b, 'pg_application', :a)").param("to", email).param("s", subject)
                            .param("b", "The University started a password reset for your postgraduate application " + r.get("applicationNo") + " at your request. "
                                    + "Open this link within the hour to choose a new password: " + link
                                    + " The link works once. If you did not ask for this, ignore it and contact the School of Postgraduate Studies; your password is unchanged.")
                            .param("a", app, java.sql.Types.OTHER).query().singleRow();
                }
                if (phone != null && !phone.isBlank()) {
                    jdbc.sql("SELECT platform.queue_notice('SMS', :to, :s, :b, 'pg_application', :a)").param("to", phone).param("s", subject)
                            .param("b", "MOAUM PG: choose a new application password within the hour at " + link).param("a", app, java.sql.Types.OTHER).query().singleRow();
                }
                out.put("method", "RESET_LINK");
                out.put("applicationNo", r.get("applicationNo"));
                out.put("sentTo", to);
                out.put("expiresAt", r.get("expiresAt"));
                out.put("note", "The link went to the applicant's email and phone. It works once, within the hour.");
            }
            default -> throw new DomainRuleViolation("PGPW_METHOD", "A reset puts the password back to the application number, or sends a link to the applicant's email and phone.",
                    new DomainRuleViolation.Remedy("Choose DEFAULT or LINK.", "You"));
        }
        return out;
    }

    public record BulkIn(@NotNull @Size(max = 2000) List<@Size(max = 200) String> numbers, @NotBlank @Size(max = 1000) String reason, Boolean commit) {
    }

    /** V710: passwords reset in bulk back to the application number — the application numbers (or the old portal's) or emails given,
     *  checked first and then reset under one reference, each written down and the applicant told */
    @PostMapping("/bulk")
    @PreAuthorize(DESK)
    @Transactional
    Map<String, Object> bulk(@Valid @RequestBody BulkIn body) {
        String joined = String.join("\n", body.numbers().stream().map(n -> n == null ? "" : n.replaceAll("[\\r\\n]+", " ")).toList());
        boolean commit = Boolean.TRUE.equals(body.commit());
        List<Map<String, Object>> rows = jdbc.sql("SELECT * FROM admissions.applicant_password_bulk_reset('POSTGRADUATE', string_to_array(:n, chr(10)), :r, :c)")
                .param("n", joined).param("r", body.reason()).param("c", commit).query().listOfRows();
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

    static String sha256(String s) {
        try {
            return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(s.getBytes(StandardCharsets.UTF_8)));
        } catch (Exception e) {
            throw new IllegalStateException(e);
        }
    }
}
