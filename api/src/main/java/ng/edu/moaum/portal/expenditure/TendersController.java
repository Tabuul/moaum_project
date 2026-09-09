package ng.edu.moaum.portal.expenditure;

import java.math.BigDecimal;
import java.sql.Types;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import jakarta.validation.Valid;
import jakarta.validation.constraints.DecimalMin;
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
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/** Tenders: evaluation and award (V046). */
@RestController
@RequestMapping("/api/v1/expenditure/tenders")
class TendersController {

    private static final String READERS = "hasAnyAuthority('OFFICE_bursar','OFFICE_audit','OFFICE_deputyaudit','OFFICE_super','OFFICE_admin','OFFICE_vc')";
    private static final String PROCUREMENT = "hasAnyAuthority('OFFICE_bursar','OFFICE_super')";

    private final JdbcClient jdbc;

    TendersController(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    public record Open(@NotBlank @Size(max = 200) String subject, @Size(max = 120) String costCentre,
                       @NotNull @DecimalMin("0.01") BigDecimal estimate, Integer threshold) {
    }

    public record NewBid(@NotBlank @Size(max = 200) String bidder, @NotNull @DecimalMin("0.01") BigDecimal price) {
    }

    public record Score(Integer technical, Boolean responsive, @Size(max = 400) String reason) {
    }

    public record Award(@NotNull UUID bid, @Size(max = 2000) String why) {
    }

    public record Why(@NotBlank @Size(max = 2000) String why) {
    }

    @GetMapping
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> list(@RequestParam(required = false) String stage) {
        return jdbc.sql("""
                SELECT t.id, t.reference, t.subject, t.cost_centre, t.estimate, t.method, t.technical_threshold, t.stage,
                       t.opened_at, t.awarded_why, t.cancelled_why,
                       (SELECT count(*) FROM expenditure.bid b WHERE b.tender_id = t.id) AS bids,
                       (SELECT count(*) FROM expenditure.bid b WHERE b.tender_id = t.id AND b.responsive IS TRUE) AS responsive,
                       (SELECT b.bidder FROM expenditure.bid b WHERE b.id = t.awarded_bid) AS awarded_to,
                       (SELECT b.price FROM expenditure.bid b WHERE b.id = t.awarded_bid) AS awarded_price
                  FROM expenditure.tender t
                 WHERE (:stage::text IS NULL OR t.stage = :stage)
                 ORDER BY (t.stage NOT IN ('AWARDED','CANCELLED')) DESC, t.opened_at DESC LIMIT 300
                """).param("stage", stage == null || stage.isBlank() ? null : stage.toUpperCase(), Types.VARCHAR).query().listOfRows();
    }

    @GetMapping("/{id}")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> bids(@PathVariable UUID id) {
        return jdbc.sql("""
                SELECT b.id, b.bidder, b.price, b.technical_score, b.responsive, b.reason,
                       CASE WHEN b.responsive IS TRUE THEN rank() OVER (PARTITION BY b.responsive ORDER BY b.price) END AS rank
                  FROM expenditure.bid b WHERE b.tender_id = :id
                 ORDER BY b.responsive DESC NULLS LAST, b.price
                """).param("id", id).query().listOfRows();
    }

    @PostMapping
    @PreAuthorize(PROCUREMENT)
    @Transactional
    Map<String, Object> open(@Valid @RequestBody Open body) {
        String ref = jdbc.sql("SELECT expenditure.open_tender(:s, :c, :e, :t)")
                .param("s", body.subject()).param("c", body.costCentre(), Types.VARCHAR).param("e", body.estimate())
                .param("t", body.threshold(), Types.INTEGER).query(String.class).single();
        return Map.of("reference", ref, "stage", "ADVERTISED");
    }

    @PostMapping("/{id}/bids")
    @PreAuthorize(PROCUREMENT)
    @Transactional
    Map<String, Object> addBid(@PathVariable UUID id, @Valid @RequestBody NewBid body) {
        UUID bid = jdbc.sql("SELECT expenditure.add_bid(:t, :b, :p)").param("t", id).param("b", body.bidder()).param("p", body.price()).query(UUID.class).single();
        return Map.of("bid", bid);
    }

    @PostMapping("/bids/{bid}/score")
    @PreAuthorize(PROCUREMENT)
    @Transactional
    Map<String, Object> score(@PathVariable UUID bid, @Valid @RequestBody Score body) {
        jdbc.sql("SELECT expenditure.score_bid(:b, :t, :r, :why)")
                .param("b", bid).param("t", body.technical(), Types.INTEGER).param("r", body.responsive(), Types.BOOLEAN)
                .param("why", body.reason(), Types.VARCHAR).query().singleRow();
        return Map.of("bid", bid, "scored", true);
    }

    @PostMapping("/{id}/award")
    @PreAuthorize(PROCUREMENT)
    @Transactional
    Map<String, Object> award(@PathVariable UUID id, @Valid @RequestBody Award body) {
        jdbc.sql("SELECT expenditure.award_tender(:t, :b, :why)").param("t", id).param("b", body.bid()).param("why", body.why(), Types.VARCHAR).query().singleRow();
        return Map.of("id", id, "stage", "AWARDED");
    }

    @PostMapping("/{id}/cancel")
    @PreAuthorize(PROCUREMENT)
    @Transactional
    Map<String, Object> cancel(@PathVariable UUID id, @Valid @RequestBody Why body) {
        jdbc.sql("SELECT expenditure.cancel_tender(:t, :w)").param("t", id).param("w", body.why()).query().singleRow();
        return Map.of("id", id, "stage", "CANCELLED");
    }
}
