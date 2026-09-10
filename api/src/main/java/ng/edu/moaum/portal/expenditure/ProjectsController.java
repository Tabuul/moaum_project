package ng.edu.moaum.portal.expenditure;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.sql.Types;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;

/** Research grants and projects (V076): the money the University administers for a sponsor. */
@RestController
class ProjectsController {

    private static final String READERS = "hasAnyAuthority('OFFICE_bursar','OFFICE_audit','OFFICE_deputyaudit','OFFICE_admin','OFFICE_super','OFFICE_vc','OFFICE_dvc')";
    private static final String WRITERS = "hasAnyAuthority('OFFICE_bursar','OFFICE_dvc','OFFICE_super')";

    private final JdbcClient jdbc;

    ProjectsController(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    public record Grant(@NotBlank @Size(max = 300) String title, @NotBlank @Size(max = 200) String principalInvestigator,
                        @NotBlank @Size(max = 200) String sponsor, @NotNull BigDecimal amount, @Size(max = 8) String currency,
                        LocalDate startsOn, LocalDate endsOn) {
    }

    public record State(@NotBlank @Size(max = 20) String state) {
    }

    @GetMapping("/api/v1/research/grants")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> list() {
        List<Map<String, Object>> rows = jdbc.sql("SELECT id, reference, title, principal_investigator, sponsor, amount, currency, starts_on, ends_on, state, note FROM expenditure.research_grant ORDER BY (state = 'ACTIVE') DESC, starts_on DESC NULLS LAST").query().listOfRows();
        return Map.of("rows", rows);
    }

    @PostMapping("/api/v1/research/grants")
    @PreAuthorize(WRITERS)
    @Transactional
    Map<String, Object> add(@Valid @RequestBody Grant body) {
        String ref = jdbc.sql("SELECT 'GR-' || to_char(current_date, 'YYYY') || '-' || lpad(platform.next_number('GRANT', 'UNIVERSITY', to_char(current_date, 'YYYY'))::text, 4, '0')").query(String.class).single();
        jdbc.sql("""
                INSERT INTO expenditure.research_grant (reference, title, principal_investigator, sponsor, amount, currency, starts_on, ends_on)
                VALUES (:r, :t, :pi, :sp, :a, coalesce(:cur, 'NGN'), :s, :e)
                """)
                .param("r", ref).param("t", body.title().trim()).param("pi", body.principalInvestigator().trim()).param("sp", body.sponsor().trim())
                .param("a", body.amount()).param("cur", body.currency() == null || body.currency().isBlank() ? null : body.currency().trim().toUpperCase(), Types.VARCHAR)
                .param("s", body.startsOn(), Types.DATE).param("e", body.endsOn(), Types.DATE)
                .update();
        return Map.of("reference", ref);
    }

    @PostMapping("/api/v1/research/grants/{id}/state")
    @PreAuthorize(WRITERS)
    @Transactional
    Map<String, Object> state(@PathVariable UUID id, @Valid @RequestBody State body) {
        jdbc.sql("UPDATE expenditure.research_grant SET state = :s WHERE id = :id").param("s", body.state().toUpperCase()).param("id", id).update();
        return Map.of("id", id, "state", body.state().toUpperCase());
    }
}
