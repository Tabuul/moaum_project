package ng.edu.moaum.portal.apimgmt;

import java.util.List;
import java.util.Map;
import java.util.UUID;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/** API consumers and their keys (V047). */
@RestController
@RequestMapping("/api/v1/apimgmt")
class ApiKeysController {

    private static final String OPERATORS = "hasAnyAuthority('OFFICE_ict','OFFICE_admin','OFFICE_super')";

    private final JdbcClient jdbc;

    ApiKeysController(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    public record NewConsumer(@NotBlank @Size(max = 120) String name, @NotBlank @Size(max = 120) String owner,
                              @NotBlank @Size(max = 400) String scopes, Integer quotaDay) {
    }

    public record NewKey(Integer days) {
    }

    /** consumers, and the keys on each (metadata only — a key is never shown again after issue) */
    @GetMapping("/consumers")
    @PreAuthorize(OPERATORS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> consumers() {
        List<Map<String, Object>> consumers = jdbc.sql("""
                SELECT c.id, c.name, c.owner, c.scopes, c.quota_day, c.status, c.created_at
                  FROM apimgmt.consumer c ORDER BY c.status, c.name
                """).query().listOfRows();
        List<Map<String, Object>> keys = jdbc.sql("""
                SELECT id, consumer_id, last4, issued_at, expires_at, revoked_at,
                       (revoked_at IS NULL AND expires_at > now()) AS live,
                       (revoked_at IS NULL AND expires_at <= now() + interval '14 days' AND expires_at > now()) AS due
                  FROM apimgmt.key ORDER BY issued_at DESC
                """).query().listOfRows();
        for (Map<String, Object> c : consumers) {
            c.put("keys", keys.stream().filter(k -> c.get("id").equals(k.get("consumer_id"))).toList());
        }
        return consumers;
    }

    @PostMapping("/consumers")
    @PreAuthorize(OPERATORS)
    @Transactional
    Map<String, Object> register(@Valid @RequestBody NewConsumer body) {
        UUID id = jdbc.sql("SELECT apimgmt.register_consumer(:n, :o, :s, :q)")
                .param("n", body.name()).param("o", body.owner()).param("s", body.scopes())
                .param("q", body.quotaDay(), java.sql.Types.INTEGER).query(UUID.class).single();
        return Map.of("id", id);
    }

    /** issue a key; the plaintext is returned here and never again */
    @PostMapping("/consumers/{id}/keys")
    @PreAuthorize(OPERATORS)
    @Transactional
    Map<String, Object> issue(@PathVariable UUID id, @RequestBody(required = false) NewKey body) {
        String key = jdbc.sql("SELECT apimgmt.issue_key(:c, :d)")
                .param("c", id).param("d", body == null ? null : body.days(), java.sql.Types.INTEGER).query(String.class).single();
        return Map.of("key", key, "shownOnce", true);
    }

    @PostMapping("/keys/{id}/revoke")
    @PreAuthorize(OPERATORS)
    @Transactional
    Map<String, Object> revoke(@PathVariable UUID id) {
        jdbc.sql("SELECT apimgmt.revoke_key(:id)").param("id", id).query().singleRow();
        return Map.of("id", id, "revoked", true);
    }

    @PostMapping("/consumers/{id}/deprecate")
    @PreAuthorize(OPERATORS)
    @Transactional
    Map<String, Object> deprecate(@PathVariable UUID id) {
        jdbc.sql("SELECT apimgmt.deprecate_consumer(:id)").param("id", id).query().singleRow();
        return Map.of("id", id, "status", "DEPRECATED");
    }
}
