package ng.edu.moaum.portal.admissions;

import java.util.LinkedHashMap;
import java.util.Map;

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
import org.springframework.web.bind.annotation.RestController;

/**
 * V420: an applicant fee confirmed by hand in error, reversed by the Bursary on Payment Investigation — the reference read
 * first (what it is, whether it may be reversed and why not), then reversed with a reason. The rules are the database's
 * (admissions.reverse_fee_confirmation): never a payment the gateway settled, never a fee already relied upon.
 */
@RestController
@RequestMapping("/api/v1/admissions/fee-references")
class FeeReversalController {

    private static final String BURSARY = "hasAnyAuthority('OFFICE_bursar','OFFICE_super')";

    private final JdbcClient jdbc;
    private final tools.jackson.databind.ObjectMapper json;

    FeeReversalController(JdbcClient jdbc, tools.jackson.databind.ObjectMapper json) {
        this.jdbc = jdbc;
        this.json = json;
    }

    /** the reference as the Bursary sees it before reversing it, with any earlier reversal of it */
    @GetMapping("/{reference}")
    @PreAuthorize(BURSARY)
    @Transactional(readOnly = true)
    Map<String, Object> reference(@PathVariable String reference) {
        Map<String, Object> out = new LinkedHashMap<>(jdbc.sql("SELECT * FROM admissions.fee_reversal_check(:r)").param("r", reference).query().listOfRows()
                .stream().findFirst().orElseThrow(() -> new NotFound("applicant fee reference", reference)));
        out.put("reversals", jdbc.sql("""
                SELECT v.reversed_at, v.reason, v.amount, v.receipt_no, v.reversed_office,
                       nullif(btrim(coalesce(p.surname, '') || ', ' || coalesce(p.given_names, '')), ',') AS reversed_by_name
                  FROM admissions.fee_reversal v LEFT JOIN iam.person p ON p.id = v.reversed_by
                 WHERE v.reference = upper(btrim(:r)) ORDER BY v.reversed_at DESC
                """).param("r", reference).query().listOfRows());
        return out;
    }

    public record Reversal(@NotBlank @Size(min = 10, max = 500) String reason) {
    }

    @PostMapping("/{reference}/reverse")
    @PreAuthorize(BURSARY)
    @Transactional
    Map<String, Object> reverse(@PathVariable String reference, @Valid @RequestBody Reversal body) {
        String text = jdbc.sql("SELECT admissions.reverse_fee_confirmation(:r, :why)::text").param("r", reference).param("why", body.reason().trim())
                .query(String.class).single();
        Map<String, Object> out = new LinkedHashMap<>(reference(reference));
        out.put("reversed", json.readValue(text, Map.class));
        return out;
    }

    /** the latest reversals, for the Bursary's record */
    @GetMapping("/reversals")
    @PreAuthorize(BURSARY)
    @Transactional(readOnly = true)
    Map<String, Object> reversals() {
        return Map.of("rows", jdbc.sql("""
                SELECT v.reversed_at, v.reference, v.kind, v.amount, v.receipt_no, v.reason, a.application_no, c.surname || ', ' || c.other_names AS applicant,
                       v.ledger_journal IS NOT NULL AS ledger_reversed,
                       nullif(btrim(coalesce(p.surname, '') || ', ' || coalesce(p.given_names, '')), ',') AS reversed_by_name
                  FROM admissions.fee_reversal v JOIN admissions.application a ON a.id = v.application_id
                  JOIN admissions.candidate c ON c.id = a.candidate_id LEFT JOIN iam.person p ON p.id = v.reversed_by
                 ORDER BY v.reversed_at DESC LIMIT 100
                """).query().listOfRows());
    }
}
