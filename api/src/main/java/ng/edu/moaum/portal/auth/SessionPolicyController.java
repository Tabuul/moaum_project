package ng.edu.moaum.portal.auth;

import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

import ng.edu.moaum.portal.shared.AuditContext;
import ng.edu.moaum.portal.shared.AuditContextHolder;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * V437 — the session timeout, under Security on the ICT Director's screen: read by anyone signed in (the browser draws its
 * countdown from it), set by the Directorate of ICT or an administrator (the database refuses any other office, and keeps
 * every change on the audit spine with who and why); and for the offices that read the security posture, the history of
 * the setting and the sessions open now — who, acting as what, active or idle. Changing the setting changes what the
 * server enforces on the next request: nothing is redeployed.
 */
@RestController
@RequestMapping("/api/v1/auth/session-policy")
class SessionPolicyController {

    static final String SETTERS = "hasAnyAuthority('OFFICE_ict','OFFICE_admin','OFFICE_super')";
    static final String MONITORS = "hasAnyAuthority('OFFICE_ict','OFFICE_audit','OFFICE_deputyaudit','OFFICE_security','OFFICE_registrar',"
            + "'OFFICE_vc','OFFICE_dvc','OFFICE_admin','OFFICE_super')";

    public record PolicyIn(@NotNull Boolean enabled, @NotNull Integer idleSeconds, @NotNull Integer warningSeconds, Boolean allowContinue,
                           @Size(max = 500) String reason) {
    }

    private final JdbcClient jdbc;

    SessionPolicyController(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    private Map<String, Object> policy() {
        Map<String, Object> row = jdbc.sql("""
                SELECT p.idle_enabled AS enabled, p.idle_seconds, p.warning_seconds, p.allow_continue, p.updated_at, p.updated_office, p.reason,
                       coalesce(x.surname || ', ' || x.given_names, CASE WHEN p.updated_by IS NULL THEN NULL ELSE 'Unknown' END) AS updated_by
                  FROM platform.session_policy p LEFT JOIN iam.person x ON x.id = p.updated_by
                 WHERE p.scope = 'GLOBAL'
                """).query().singleRow();
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("enabled", row.get("enabled"));
        out.put("idleSeconds", row.get("idle_seconds"));
        out.put("warningSeconds", row.get("warning_seconds"));
        out.put("allowContinue", row.get("allow_continue"));
        out.put("updatedAt", row.get("updated_at"));
        out.put("updatedBy", row.get("updated_by"));
        out.put("updatedOffice", row.get("updated_office"));
        out.put("reason", row.get("reason"));
        return out;
    }

    /** the policy in force — what the browser counts down from */
    @GetMapping
    @PreAuthorize("isAuthenticated()")
    @Transactional(readOnly = true)
    Map<String, Object> read() {
        return policy();
    }

    /** the policy set: the database validates (at least 30 s; the warning shorter than the timeout) and records who and why */
    @PutMapping
    @PreAuthorize(SETTERS)
    @Transactional
    Map<String, Object> set(@Valid @RequestBody PolicyIn body) {
        AuditContext ctx = AuditContextHolder.required();
        jdbc.sql("SELECT platform.set_session_policy(:e, :i, :w, :a, :r, :actor, :office)")
                .param("e", body.enabled()).param("i", body.idleSeconds()).param("w", body.warningSeconds())
                .param("a", body.allowContinue(), java.sql.Types.BOOLEAN).param("r", body.reason(), java.sql.Types.VARCHAR)
                .param("actor", ctx.actorId()).param("office", ctx.actorOffice()).query().listOfRows();
        return policy();
    }

    /** every change to the setting, from the audit spine: when, by whom, from what to what, and why */
    @GetMapping("/history")
    @PreAuthorize(MONITORS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> history() {
        return jdbc.sql("""
                SELECT e.occurred_at, e.actor_office, e.reason,
                       coalesce(p.surname || ', ' || p.given_names, 'Unknown') AS actor,
                       e.before_state->>'idle_enabled' AS was_enabled, e.after_state->>'idle_enabled' AS now_enabled,
                       e.before_state->>'idle_seconds' AS was_idle, e.after_state->>'idle_seconds' AS now_idle,
                       e.before_state->>'warning_seconds' AS was_warning, e.after_state->>'warning_seconds' AS now_warning,
                       e.after_state->>'allow_continue' AS now_continue, e.after_state->>'reason' AS why
                  FROM audit.entries e LEFT JOIN iam.person p ON p.id = e.actor_id
                 WHERE e.subject_type = 'platform.session_policy' AND e.action <> 'INSERT'
                 ORDER BY e.occurred_at DESC
                 LIMIT 100
                """).query().listOfRows();
    }

    /** the sessions open now and today's ends, for the security screen: names and offices, nothing more */
    @GetMapping("/monitor")
    @PreAuthorize(MONITORS)
    @Transactional(readOnly = true)
    Map<String, Object> monitor() {
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("counts", jdbc.sql("SELECT * FROM platform.session_monitor()").query().singleRow());
        out.put("sessions", jdbc.sql("SELECT session_id, person_id, name, office, issued_at, last_seen_at, status FROM platform.open_sessions(300)").query().listOfRows());
        return out;
    }
}
