package ng.edu.moaum.portal.pgadmissions;

import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

import ng.edu.moaum.portal.shared.AuditContext;
import ng.edu.moaum.portal.shared.AuditContextHolder;
import ng.edu.moaum.portal.shared.DomainRuleViolation;
import ng.edu.moaum.portal.shared.NotFound;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * The postgraduate referee's own door — public, reached by the unguessable token emailed to the referee
 * when the applicant named them (V225). The referee sees who named them and for what programme, and
 * gives a short reference: their relationship to the applicant, how long they have known them, an
 * academic attestation and a recommendation. Written under the applicant office, like the public apply,
 * because the referee is not a signed-in member of the University. Whitelisted in SecurityConfig.
 */
@RestController
@RequestMapping("/api/v1/pg/referee")
class PgRefereeController {

    private static final UUID NOBODY = new UUID(0, 0);
    private final JdbcClient jdbc;
    private final TransactionTemplate tx;

    PgRefereeController(JdbcClient jdbc, PlatformTransactionManager transactions) {
        this.jdbc = jdbc;
        this.tx = new TransactionTemplate(transactions);
    }

    /** the reference request behind a token: who named the referee, for what, and whether it is done (public) */
    @GetMapping("/{token}")
    Map<String, Object> view(@PathVariable String token) {
        Map<String, Object> r = firstOrNull(jdbc.sql("""
                SELECT r.name AS referee_name, r.position, r.institution, r.submitted_at,
                       p.surname, p.other_names, a.application_no, a.session,
                       g.name AS programme_name, g.pg_award
                  FROM admissions.pg_referee r
                  JOIN admissions.pg_application a ON a.id = r.application_id
                  JOIN admissions.pg_applicant p ON p.id = a.applicant_id
                  JOIN ref.programme g ON g.code = a.programme_code
                 WHERE r.token = :t
                """).param("t", token).query().listOfRows());
        if (r == null) {
            throw new NotFound("reference request", token);
        }
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("found", true);
        out.put("refereeName", r.get("referee_name"));
        out.put("position", r.get("position"));
        out.put("institution", r.get("institution"));
        out.put("applicant", r.get("surname") + ", " + r.get("other_names"));
        out.put("applicationNo", r.get("application_no"));
        out.put("session", r.get("session"));
        out.put("programme", r.get("programme_name"));
        out.put("award", r.get("pg_award"));
        out.put("submitted", r.get("submitted_at") != null);
        return out;
    }

    public record RefIn(@NotBlank @Size(max = 200) String relationship, @NotBlank @Size(max = 120) String knownDuration,
                        @NotBlank @Size(max = 4000) String attestation, @Size(max = 4000) String recommendation,
                        @NotBlank @Pattern(regexp = "RECOMMEND|RECOMMEND_WITH_RESERVATION|DO_NOT_RECOMMEND") String verdict) {
    }

    /** the referee submits their reference (public, once) */
    @PostMapping("/{token}")
    Map<String, Object> submit(@PathVariable String token, @Valid @RequestBody RefIn body) {
        Map<String, Object> r = firstOrNull(jdbc.sql("SELECT id, submitted_at FROM admissions.pg_referee WHERE token = :t")
                .param("t", token).query().listOfRows());
        if (r == null) {
            throw new NotFound("reference request", token);
        }
        if (r.get("submitted_at") != null) {
            throw new DomainRuleViolation("PG_REF_DONE", "This reference has already been submitted.",
                    new DomainRuleViolation.Remedy("Thank you — no further action is needed.", "School of Postgraduate Studies"));
        }
        AuditContextHolder.with(new AuditContext(NOBODY, "applicant", "postgraduate reference submitted", null, null),
                () -> tx.execute(st -> jdbc.sql("""
                        UPDATE admissions.pg_referee
                           SET relationship = :rel, known_duration = :kd, attestation = :att,
                               recommendation = :rec, reference_text = :rec, verdict = :v, submitted_at = now()
                         WHERE token = :t AND submitted_at IS NULL
                        """).param("rel", body.relationship().trim()).param("kd", body.knownDuration().trim())
                        .param("att", body.attestation().trim())
                        .param("rec", body.recommendation() == null || body.recommendation().isBlank() ? null : body.recommendation().trim())
                        .param("v", body.verdict()).param("t", token).update()));
        return Map.of("ok", true);
    }

    private static Map<String, Object> firstOrNull(List<Map<String, Object>> rows) {
        return rows.isEmpty() ? null : rows.get(0);
    }
}
