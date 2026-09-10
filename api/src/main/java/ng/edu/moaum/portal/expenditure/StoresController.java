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

/** Stores and the fixed-asset register (V076). */
@RestController
class StoresController {

    private static final String READERS = "hasAnyAuthority('OFFICE_bursar','OFFICE_audit','OFFICE_deputyaudit','OFFICE_admin','OFFICE_super','OFFICE_vc','OFFICE_ict')";
    private static final String WRITERS = "hasAnyAuthority('OFFICE_bursar','OFFICE_super')";

    private final JdbcClient jdbc;

    StoresController(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    public record Item(@NotBlank @Size(max = 40) String code, @NotBlank @Size(max = 200) String name, @Size(max = 20) String unit, BigDecimal quantity, BigDecimal reorderLevel, @Size(max = 120) String location) {
    }

    public record Adjust(@NotNull BigDecimal delta, @Size(max = 200) String note) {
    }

    public record Asset(@NotBlank @Size(max = 40) String tag, @NotBlank @Size(max = 200) String name, @Size(max = 80) String category, @Size(max = 120) String location, LocalDate acquiredOn, BigDecimal cost) {
    }

    public record Condition(@NotBlank @Size(max = 20) String condition) {
    }

    /* ── inventory ── */

    @GetMapping("/api/v1/stores/items")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> items() {
        return Map.of("rows", jdbc.sql("SELECT id, code, name, unit, quantity, reorder_level, location, note, (reorder_level IS NOT NULL AND quantity <= reorder_level) AS low FROM expenditure.store_item ORDER BY name").query().listOfRows());
    }

    @PostMapping("/api/v1/stores/items")
    @PreAuthorize(WRITERS)
    @Transactional
    Map<String, Object> addItem(@Valid @RequestBody Item body) {
        UUID id = jdbc.sql("""
                INSERT INTO expenditure.store_item (code, name, unit, quantity, reorder_level, location)
                VALUES (:c, :n, coalesce(:u, 'each'), coalesce(:q, 0), :rl, :loc) RETURNING id
                """)
                .param("c", body.code().trim()).param("n", body.name().trim())
                .param("u", body.unit() == null || body.unit().isBlank() ? null : body.unit().trim(), Types.VARCHAR)
                .param("q", body.quantity(), Types.NUMERIC).param("rl", body.reorderLevel(), Types.NUMERIC)
                .param("loc", body.location() == null || body.location().isBlank() ? null : body.location().trim(), Types.VARCHAR)
                .query(UUID.class).single();
        return Map.of("id", id);
    }

    @PostMapping("/api/v1/stores/items/{id}/adjust")
    @PreAuthorize(WRITERS)
    @Transactional
    Map<String, Object> adjust(@PathVariable UUID id, @Valid @RequestBody Adjust body) {
        jdbc.sql("UPDATE expenditure.store_item SET quantity = quantity + :d, note = coalesce(:n, note) WHERE id = :id")
                .param("d", body.delta()).param("n", body.note() == null || body.note().isBlank() ? null : body.note().trim(), Types.VARCHAR).param("id", id).update();
        return Map.of("id", id, "adjusted", true);
    }

    /* ── fixed assets ── */

    @GetMapping("/api/v1/stores/assets")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> assets() {
        return Map.of("rows", jdbc.sql("SELECT id, tag, name, category, location, acquired_on, cost, condition, last_verified_on FROM expenditure.asset ORDER BY name").query().listOfRows());
    }

    @PostMapping("/api/v1/stores/assets")
    @PreAuthorize(WRITERS)
    @Transactional
    Map<String, Object> addAsset(@Valid @RequestBody Asset body) {
        UUID id = jdbc.sql("""
                INSERT INTO expenditure.asset (tag, name, category, location, acquired_on, cost)
                VALUES (:t, :n, :cat, :loc, :aq, :cost) RETURNING id
                """)
                .param("t", body.tag().trim()).param("n", body.name().trim())
                .param("cat", body.category() == null || body.category().isBlank() ? null : body.category().trim(), Types.VARCHAR)
                .param("loc", body.location() == null || body.location().isBlank() ? null : body.location().trim(), Types.VARCHAR)
                .param("aq", body.acquiredOn(), Types.DATE).param("cost", body.cost(), Types.NUMERIC)
                .query(UUID.class).single();
        return Map.of("id", id);
    }

    @PostMapping("/api/v1/stores/assets/{id}/verify")
    @PreAuthorize("hasAnyAuthority('OFFICE_bursar','OFFICE_audit','OFFICE_deputyaudit','OFFICE_super')")
    @Transactional
    Map<String, Object> verify(@PathVariable UUID id) {
        jdbc.sql("UPDATE expenditure.asset SET last_verified_on = current_date WHERE id = :id").param("id", id).update();
        return Map.of("id", id, "verified_on", LocalDate.now().toString());
    }

    @PostMapping("/api/v1/stores/assets/{id}/condition")
    @PreAuthorize(WRITERS)
    @Transactional
    Map<String, Object> condition(@PathVariable UUID id, @Valid @RequestBody Condition body) {
        jdbc.sql("UPDATE expenditure.asset SET condition = :c WHERE id = :id").param("c", body.condition().toUpperCase()).param("id", id).update();
        return Map.of("id", id, "condition", body.condition().toUpperCase());
    }
}
