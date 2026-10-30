package ng.edu.moaum.portal.pgadmissions;

import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

import ng.edu.moaum.portal.shared.NotFound;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import tools.jackson.databind.ObjectMapper;

/**
 * V706 — Postgraduate Applicant Passwords: the Dean of the School of Postgraduate Studies, its Secretary, the Director of ICT and ICT
 * Support find a postgraduate applicant (by the application number, the old portal's, the email, the phone or a name) and reset the
 * password, saying why: it becomes the applicant's application number, and the applicant chooses their own at the sign-in before anything
 * else (the API's ApplicantPasswordGate). Never a password the officer chooses; never the hash; every reset written down
 * (admissions.pg_applicant_password_reset) and the applicant told by email and SMS (admissions.pg_tell_applicant).
 */
@RestController
@RequestMapping("/api/v1/pg/applicant-passwords")
class PgApplicantPasswordDeskController {

    static final String DESK = "hasAnyAuthority('OFFICE_pgschool','OFFICE_pgsecretary','OFFICE_ict','OFFICE_ictagent','OFFICE_helpdeskhead','OFFICE_super')";

    private final JdbcClient jdbc;
    private final ObjectMapper json;

    PgApplicantPasswordDeskController(JdbcClient jdbc, ObjectMapper json) {
        this.jdbc = jdbc;
        this.json = json;
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
                SELECT r.id, r.applicant_id, r.method, r.application_no, r.reason, r.was_locked, r.sessions_ended, r.reset_at, r.reset_office,
                       coalesce(o.surname || ', ' || o.given_names, 'Unknown officer') AS reset_by_name,
                       p.surname || ', ' || p.other_names AS applicant, p.email, coalesce(a.session, p.session) AS session
                  FROM admissions.pg_applicant_password_reset r
                  JOIN admissions.pg_applicant p ON p.id = r.applicant_id
                  LEFT JOIN admissions.pg_application a ON a.applicant_id = p.id
                  LEFT JOIN iam.person o ON o.id = r.reset_by
                 WHERE (:p::uuid IS NULL OR r.applicant_id = :p)
                 ORDER BY r.reset_at DESC
                 LIMIT :n
                """).param("p", applicant, java.sql.Types.OTHER).param("n", Math.max(1, Math.min(limit, 1000))).query().listOfRows();
    }

    public record ResetIn(@NotBlank @Size(max = 1000) String reason) {
    }

    /** the reset: the password becomes the application number; the applicant is told and chooses their own at the sign-in */
    @PostMapping("/{applicant}/reset")
    @PreAuthorize(DESK)
    @Transactional
    Map<String, Object> reset(@PathVariable UUID applicant, @Valid @RequestBody ResetIn body) {
        String done = jdbc.sql("SELECT admissions.pg_applicant_password_default(:p, :r)::text")
                .param("p", applicant).param("r", body.reason()).query(String.class).single();
        @SuppressWarnings("unchecked")
        Map<String, Object> r = json.readValue(done, Map.class);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("method", "DEFAULT_NUMBER");
        out.put("applicationNo", r.get("applicationNo"));
        out.put("wasLocked", r.get("wasLocked"));
        out.put("sessionsEnded", r.get("sessionsEnded"));
        out.put("note", "The applicant signs in with their email or application number, and the application number as the password, then chooses their own password at once.");
        return out;
    }
}
