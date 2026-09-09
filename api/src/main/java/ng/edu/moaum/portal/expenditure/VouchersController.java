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

/** Payment vouchers and the pre-payment gate (V044). */
@RestController
@RequestMapping("/api/v1/expenditure/vouchers")
class VouchersController {

    private static final String READERS = "hasAnyAuthority('OFFICE_bursar','OFFICE_audit','OFFICE_deputyaudit','OFFICE_super','OFFICE_admin','OFFICE_vc')";
    private static final String BURSARY = "hasAnyAuthority('OFFICE_bursar','OFFICE_super')";
    private static final String AUDIT = "hasAnyAuthority('OFFICE_audit','OFFICE_deputyaudit','OFFICE_super')";
    private static final String ANSWERERS = "hasAnyAuthority('OFFICE_bursar','OFFICE_audit','OFFICE_deputyaudit','OFFICE_super')";

    private final JdbcClient jdbc;

    VouchersController(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    public record Raise(@NotBlank @Size(max = 200) String title, @NotBlank @Size(max = 40) String kind, @NotBlank @Size(max = 40) String source,
                        @Size(max = 120) String costCentre, @NotBlank @Size(max = 200) String payee, @NotNull @DecimalMin("0.01") BigDecimal amount) {
    }

    public record Note(@Size(max = 2000) String note) {
    }

    public record Query(@NotBlank @Size(max = 2000) String finding, @NotBlank @Size(max = 120) String sentTo) {
    }

    public record Answer(@NotBlank @Size(max = 2000) String answer) {
    }

    public record Why(@NotBlank @Size(max = 2000) String why) {
    }

    @GetMapping
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> list(@RequestParam(required = false) String stage) {
        return jdbc.sql("""
                SELECT v.id, v.reference, v.title, v.kind, v.source, v.cost_centre, v.payee, v.amount, v.stage,
                       v.raised_at, v.paid_at, v.rejected_why,
                       rp.surname || ', ' || rp.given_names AS raised_by_name,
                       v.raised_by = nullif(current_setting('moaum.actor_id', true), '')::uuid AS raised_by_me,
                       EXISTS (SELECT 1 FROM expenditure.voucher_query q WHERE q.voucher_id = v.id AND q.answer IS NULL) AS query_open,
                       (SELECT q2.id FROM expenditure.voucher_query q2 WHERE q2.voucher_id = v.id AND q2.answer IS NULL ORDER BY q2.raised_at LIMIT 1) AS open_query_id,
                       (SELECT q3.finding FROM expenditure.voucher_query q3 WHERE q3.voucher_id = v.id AND q3.answer IS NULL ORDER BY q3.raised_at LIMIT 1) AS open_query_finding,
                       (SELECT q4.sent_to FROM expenditure.voucher_query q4 WHERE q4.voucher_id = v.id AND q4.answer IS NULL ORDER BY q4.raised_at LIMIT 1) AS open_query_to,
                       EXISTS (SELECT 1 FROM expenditure.voucher_act a WHERE a.voucher_id = v.id
                                AND a.actor_id = nullif(current_setting('moaum.actor_id', true), '')::uuid) AS i_acted
                  FROM expenditure.voucher v
                  LEFT JOIN iam.person rp ON rp.id = v.raised_by
                 WHERE (:stage::text IS NULL OR v.stage = :stage)
                 ORDER BY (v.stage NOT IN ('PAID','REJECTED')) DESC, v.raised_at DESC LIMIT 300
                """).param("stage", stage == null || stage.isBlank() ? null : stage.toUpperCase(), Types.VARCHAR).query().listOfRows();
    }

    @GetMapping("/{id}")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> one(@PathVariable UUID id) {
        List<Map<String, Object>> acts = jdbc.sql("""
                SELECT a.act, a.from_stage, a.to_stage, a.office, a.note, a.at, p.surname || ', ' || p.given_names AS by_name
                  FROM expenditure.voucher_act a LEFT JOIN iam.person p ON p.id = a.actor_id
                 WHERE a.voucher_id = :id ORDER BY a.at
                """).param("id", id).query().listOfRows();
        List<Map<String, Object>> queries = jdbc.sql("""
                SELECT q.id, q.finding, q.sent_to, q.raised_at, q.answer, q.answered_at,
                       rp.surname || ', ' || rp.given_names AS raised_by_name
                  FROM expenditure.voucher_query q LEFT JOIN iam.person rp ON rp.id = q.raised_by
                 WHERE q.voucher_id = :id ORDER BY q.raised_at
                """).param("id", id).query().listOfRows();
        return Map.of("acts", acts, "queries", queries);
    }

    @PostMapping
    @PreAuthorize(BURSARY)
    @Transactional
    Map<String, Object> raise(@Valid @RequestBody Raise body) {
        String ref = jdbc.sql("SELECT expenditure.raise_voucher(:t, :k, :s, :c, :p, :a)")
                .param("t", body.title()).param("k", body.kind()).param("s", body.source())
                .param("c", body.costCentre(), Types.VARCHAR).param("p", body.payee()).param("a", body.amount())
                .query(String.class).single();
        return Map.of("reference", ref, "stage", "WITH_DIRECTOR");
    }

    @PostMapping("/{id}/advance")
    @PreAuthorize(AUDIT)
    @Transactional
    Map<String, Object> advance(@PathVariable UUID id, @RequestBody(required = false) Note body) {
        String next = jdbc.sql("SELECT expenditure.advance_voucher(:id, :n)")
                .param("id", id).param("n", body == null ? null : body.note(), Types.VARCHAR).query(String.class).single();
        return Map.of("id", id, "stage", next);
    }

    @PostMapping("/{id}/query")
    @PreAuthorize(AUDIT)
    @Transactional
    Map<String, Object> query(@PathVariable UUID id, @Valid @RequestBody Query body) {
        UUID q = jdbc.sql("SELECT expenditure.query_voucher(:id, :f, :s)")
                .param("id", id).param("f", body.finding()).param("s", body.sentTo()).query(UUID.class).single();
        return Map.of("query", q, "open", true);
    }

    @PostMapping("/queries/{query}/answer")
    @PreAuthorize(ANSWERERS)
    @Transactional
    Map<String, Object> answer(@PathVariable UUID query, @Valid @RequestBody Answer body) {
        jdbc.sql("SELECT expenditure.answer_query(:q, :a)").param("q", query).param("a", body.answer()).query().singleRow();
        return Map.of("query", query, "answered", true);
    }

    @PostMapping("/{id}/pay")
    @PreAuthorize(BURSARY)
    @Transactional
    Map<String, Object> pay(@PathVariable UUID id) {
        jdbc.sql("SELECT expenditure.pay_voucher(:id)").param("id", id).query().singleRow();
        return Map.of("id", id, "stage", "PAID");
    }

    @PostMapping("/{id}/reject")
    @PreAuthorize(AUDIT)
    @Transactional
    Map<String, Object> reject(@PathVariable UUID id, @Valid @RequestBody Why body) {
        jdbc.sql("SELECT expenditure.reject_voucher(:id, :w)").param("id", id).param("w", body.why()).query().singleRow();
        return Map.of("id", id, "stage", "REJECTED");
    }
}
