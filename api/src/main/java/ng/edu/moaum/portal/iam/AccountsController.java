package ng.edu.moaum.portal.iam;

import java.time.LocalDate;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;

import ng.edu.moaum.portal.auth.AuthService;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/** Users & roles: the people, the offices they hold under instruments, and the credential that signs them in. */
@RestController
@RequestMapping("/api/v1/iam")
class AccountsController {

    private static final String READERS = "hasAnyAuthority('OFFICE_registrar','OFFICE_dregistrar','OFFICE_hrm','OFFICE_ict','OFFICE_admin','OFFICE_super','OFFICE_audit')";
    private static final String CREDENTIALS = "hasAnyAuthority('OFFICE_registrar','OFFICE_dregistrar','OFFICE_ict','OFFICE_admin','OFFICE_super')";
    private static final String GRANTORS = "hasAnyAuthority('OFFICE_registrar','OFFICE_dregistrar','OFFICE_vc','OFFICE_super','OFFICE_ict','OFFICE_admin')";

    public record PersonRow(UUID id, String staffNumber, String surname, String givenNames, LocalDate endedOn, String username,
                            boolean mustChange, java.time.OffsetDateTime lastSignInAt, java.time.OffsetDateTime lockedUntil, long liveOffices) {
    }

    public record GrantRow(UUID id, UUID personId, String surname, String givenNames, String staffNumber, String officeCode, String label,
                           String scopeKind, String scopeId, String instrument, UUID grantedBy, String grantedByName, LocalDate validFrom, LocalDate validTo) {
    }

    public record SetCredential(@NotBlank String username, @NotBlank String password) {
    }

    public record EndGrant(LocalDate on, @NotBlank String reason) {
    }

    private final JdbcClient jdbc;
    private final AuthService auth;

    AccountsController(JdbcClient jdbc, AuthService auth) {
        this.jdbc = jdbc;
        this.auth = auth;
    }

    @GetMapping("/persons")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    List<PersonRow> persons(@RequestParam(required = false) String q) {
        return jdbc.sql("""
                SELECT p.id, p.staff_number, p.surname, p.given_names, p.ended_on, c.username, coalesce(c.must_change, false) AS must_change,
                       c.last_sign_in_at, c.locked_until, (SELECT count(*) FROM iam.live_offices(p.id)) AS live_offices
                  FROM iam.person p LEFT JOIN iam.credential c ON c.person_id = p.id
                 WHERE :q::text IS NULL OR p.surname ILIKE '%' || :q || '%' OR p.given_names ILIKE '%' || :q || '%'
                       OR p.staff_number ILIKE '%' || :q || '%' OR c.username ILIKE '%' || :q || '%'
                 ORDER BY p.surname, p.given_names
                """).param("q", q == null || q.isBlank() ? null : q.trim()).query(PersonRow.class).list();
    }

    /** every grant, newest first, as the prototype's table shows them */
    @GetMapping("/office-assignments")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    List<GrantRow> grants(@RequestParam(defaultValue = "false") boolean ended) {
        return jdbc.sql("""
                SELECT a.id, a.person_id, p.surname, p.given_names, p.staff_number, a.office_code, o.label, a.scope_kind, a.scope_id,
                       a.instrument, a.granted_by,
                       (SELECT g.surname || ', ' || g.given_names FROM iam.person g WHERE g.id = a.granted_by) AS granted_by_name,
                       a.valid_from, a.valid_to
                  FROM iam.office_assignment a JOIN iam.person p ON p.id = a.person_id JOIN ref.office o ON o.code = a.office_code
                 WHERE :ended OR a.valid_to IS NULL OR a.valid_to >= current_date
                 ORDER BY a.valid_from DESC, p.surname
                """).param("ended", ended).query(GrantRow.class).list();
    }

    @PutMapping("/persons/{id}/credential")
    @PreAuthorize(CREDENTIALS)
    Map<String, Object> credential(@PathVariable UUID id, @Valid @RequestBody SetCredential body) {
        return auth.setCredential(id, body.username(), body.password());
    }

    @PostMapping("/persons/{id}/office-assignments/{grant}/end")
    @PreAuthorize(GRANTORS)
    @Transactional
    Map<String, Object> end(@PathVariable UUID id, @PathVariable UUID grant, @Valid @RequestBody EndGrant body) {
        jdbc.sql("SELECT iam.end_grant(:g, :on, :r)").param("g", grant).param("on", body.on() == null ? LocalDate.now() : body.on())
                .param("r", body.reason()).query().singleRow();
        return Map.of("grant", grant, "endedOn", body.on() == null ? LocalDate.now() : body.on());
    }

    @GetMapping("/offices")
    @PreAuthorize("isAuthenticated()")
    List<Map<String, Object>> offices() {
        return jdbc.sql("SELECT code, label, scope_kind FROM ref.office ORDER BY label").query().listOfRows();
    }
}
