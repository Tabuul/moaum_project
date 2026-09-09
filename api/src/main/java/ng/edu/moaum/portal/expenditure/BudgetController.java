package ng.edu.moaum.portal.expenditure;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.List;
import java.util.Map;

import jakarta.validation.Valid;
import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/** The budget and commitment accounting (V045). */
@RestController
@RequestMapping("/api/v1/expenditure/budget")
class BudgetController {

    private static final String READERS = "hasAnyAuthority('OFFICE_bursar','OFFICE_audit','OFFICE_deputyaudit','OFFICE_super','OFFICE_admin','OFFICE_vc','OFFICE_dvc')";
    private static final String BURSARY = "hasAnyAuthority('OFFICE_bursar','OFFICE_super')";

    private final JdbcClient jdbc;

    BudgetController(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    public record Set(@NotBlank @Size(max = 120) String costCentre, @NotNull Integer year, @NotNull @DecimalMin("0") BigDecimal amount) {
    }

    @GetMapping
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> performance(@RequestParam(required = false) Integer year) {
        int y = year != null ? year : LocalDate.now().getYear();
        List<Map<String, Object>> rows = jdbc.sql("SELECT * FROM expenditure.budget_performance(:y)").param("y", y).query().listOfRows();
        return Map.of("year", y, "rows", rows);
    }

    @PostMapping
    @PreAuthorize(BURSARY)
    @Transactional
    Map<String, Object> set(@Valid @RequestBody Set body) {
        jdbc.sql("SELECT expenditure.set_budget(:c, :y, :a)").param("c", body.costCentre()).param("y", body.year()).param("a", body.amount()).query().singleRow();
        return Map.of("costCentre", body.costCentre(), "year", body.year(), "amount", body.amount());
    }
}
