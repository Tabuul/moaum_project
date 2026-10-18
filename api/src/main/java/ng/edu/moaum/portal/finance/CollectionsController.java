package ng.edu.moaum.portal.finance;

import java.time.LocalDate;
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
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/** V552: the collections account's bank statement matched to what the portal received — confirmed payments, references never
 *  confirmed, NELFUND remittances and a gateway's settlement of a day — and what was confirmed and not seen in the bank. */
@RestController
@RequestMapping("/api/v1/finance/collections")
class CollectionsController {

    private static final String READERS = "hasAnyAuthority('OFFICE_bursar','OFFICE_audit','OFFICE_deputyaudit','OFFICE_admin','OFFICE_super')";
    /** who may reconcile a transaction against the bank (V068): matching a statement records the reconciliations */
    private static final String RECONCILERS = "hasAnyAuthority('OFFICE_bursar','OFFICE_audit','OFFICE_deputyaudit','OFFICE_super')";
    /** a bank credit is recorded and proposed by the Bursary (V037) */
    private static final String BURSARY = "hasAnyAuthority('OFFICE_bursar','OFFICE_super')";
    /** the payments confirmed and not seen in the bank sent with a statement; the rest are counted */
    static final int NOT_RECEIVED_ROWS = 500;

    /** a credit marked the settlement of a channel's day */
    public record Settle(@NotBlank @Size(max = 120) String channel, @NotNull LocalDate day) {
    }

    private final JdbcClient jdbc;
    private final tools.jackson.databind.ObjectMapper json;

    CollectionsController(JdbcClient jdbc, tools.jackson.databind.ObjectMapper json) {
        this.jdbc = jdbc;
        this.json = json;
    }

    /** a collections statement uploaded and matched at once; returns its result */
    @PostMapping("/statements")
    @PreAuthorize(RECONCILERS)
    @Transactional
    Map<String, Object> upload(@Valid @RequestBody RefundsController.Statement body) {
        UUID id = jdbc.sql("SELECT finance.load_collections_statement(:l, :f, :j::jsonb)")
                .param("l", body.label()).param("f", body.fileName(), java.sql.Types.VARCHAR).param("j", json.writeValueAsString(body.rows()))
                .query(UUID.class).single();
        return statement(id);
    }

    /** the collections statements uploaded, newest first, with how their lines matched */
    @GetMapping("/statements")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> statements() {
        return jdbc.sql("""
                SELECT s.id, s.label, s.file_name, s.period_from::text AS period_from, s.period_to::text AS period_to, s.lines, s.uploaded_at,
                       CASE WHEN p.id IS NULL THEN NULL ELSE p.surname || ', ' || p.given_names END AS uploaded_by_name, s.uploaded_office,
                       count(l.id) FILTER (WHERE l.status IN ('MATCHED', 'SETTLEMENT')) AS matched,
                       count(l.id) FILTER (WHERE l.status IN ('AMOUNT_DIFFERS', 'DUPLICATE')) AS amount_differs,
                       count(l.id) FILTER (WHERE l.status = 'RECEIVED_NOT_CONFIRMED') AS not_confirmed,
                       count(l.id) FILTER (WHERE l.status = 'UNMATCHED') AS unmatched
                  FROM finance.bank_statement s
                  LEFT JOIN finance.bank_statement_line l ON l.statement_id = s.id
                  LEFT JOIN iam.person p ON p.id = s.uploaded_by
                 WHERE s.account_kind = 'COLLECTIONS'
                 GROUP BY s.id, p.id ORDER BY s.uploaded_at DESC LIMIT 50
                """).query().listOfRows();
    }

    /** a statement's lines as they matched (a payment's payer, a credit sent to the bank credits and where it stands), the
     *  payments confirmed in its period and not seen in the bank by channel and day, and the first of them one by one */
    @GetMapping("/statements/{id}")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> statement(@PathVariable UUID id) {
        Map<String, Object> head = jdbc.sql("""
                SELECT s.id, s.label, s.file_name, s.period_from::text AS period_from, s.period_to::text AS period_to, s.lines, s.uploaded_at
                  FROM finance.bank_statement s WHERE s.id = :id AND s.account_kind = 'COLLECTIONS'
                """).param("id", id).query().listOfRows().stream().findFirst()
                .orElseThrow(() -> new ng.edu.moaum.portal.shared.NotFound("collections statement", id));
        Map<String, Object> out = new java.util.LinkedHashMap<>(head);
        List<Map<String, Object>> lines = jdbc.sql("""
                SELECT l.id, l.line_no, l.value_date::text AS value_date, l.description, l.reference, l.debit, l.credit, l.status, l.matched_kind,
                       l.matched_reference, l.expected_amount, l.matched_payouts, l.settlement_channel, l.settlement_day::text AS settlement_day,
                       l.bank_credit_id, bc.state AS bank_credit_state
                  FROM finance.bank_statement_line l LEFT JOIN finance.bank_credit bc ON bc.id = l.bank_credit_id
                 WHERE l.statement_id = :id ORDER BY l.line_no
                """).param("id", id).query().listOfRows();
        // the payer of each payment a line found, in one read of the payments by their references (a lookup line by line is slow)
        String refs = String.join(",", lines.stream().filter(l -> "PAYMENT".equals(l.get("matched_kind")))
                .map(l -> (String) l.get("matched_reference")).distinct().toList());
        Map<String, Map<String, Object>> payers = new java.util.HashMap<>();
        if (!refs.isEmpty()) {
            jdbc.sql("""
                    SELECT upper(p.reference) AS reference, nullif(btrim(coalesce(p.surname, '') || ' ' || coalesce(p.other_names, '')), '') AS payer,
                           p.number, p.confirmed_at IS NOT NULL AS confirmed_now
                      FROM reporting.payments p WHERE p.reference = ANY (string_to_array(:refs, ','))
                    """).param("refs", refs).query().listOfRows().forEach(r -> payers.put((String) r.get("reference"), r));
        }
        for (Map<String, Object> l : lines) {
            Map<String, Object> who = payers.get((String) l.get("matched_reference"));
            l.put("payer", who == null ? null : who.get("payer"));
            l.put("number", who == null ? null : who.get("number"));
            l.put("confirmed_now", who == null ? null : who.get("confirmed_now"));
        }
        out.put("lines", lines);
        out.put("unmatchedDays", jdbc.sql("SELECT channel, day::text AS day, payments, total FROM finance.collections_unmatched(:id)")
                .param("id", id).query().listOfRows());
        List<Map<String, Object>> rows = jdbc.sql("""
                SELECT reference, channel, day::text AS day, amount, purpose, payer, number, confirmed_at
                  FROM finance.collections_not_received(:id) LIMIT :n
                """).param("id", id).param("n", NOT_RECEIVED_ROWS + 1).query().listOfRows();
        out.put("notReceivedMore", rows.size() > NOT_RECEIVED_ROWS);
        out.put("notReceived", rows.size() > NOT_RECEIVED_ROWS ? rows.subList(0, NOT_RECEIVED_ROWS) : rows);
        return out;
    }

    /** an unmatched credit marked the settlement of a channel's day: the day's payments reconciled against it */
    @PostMapping("/lines/{id}/settle")
    @PreAuthorize(RECONCILERS)
    @Transactional
    Map<String, Object> settle(@PathVariable UUID id, @Valid @RequestBody Settle body) {
        String result = jdbc.sql("SELECT finance.settle_collections_line(:id, :c, :d)::text")
                .param("id", id).param("c", body.channel().trim()).param("d", body.day()).query(String.class).single();
        UUID statement = jdbc.sql("SELECT statement_id FROM finance.bank_statement_line WHERE id = :id").param("id", id).query(UUID.class).single();
        Map<String, Object> out = statement(statement);
        out.put("settled", json.readValue(result, Map.class));
        return out;
    }

    /** a credit for a reference the portal issued and never confirmed, sent to the bank credits proposed against that reference;
     *  a second officer approves it there (V037) */
    @PostMapping("/lines/{id}/bank-credit")
    @PreAuthorize(BURSARY)
    @Transactional
    Map<String, Object> toBankCredit(@PathVariable UUID id) {
        UUID credit = jdbc.sql("SELECT finance.collections_line_to_bank_credit(:id)").param("id", id).query(UUID.class).single();
        UUID statement = jdbc.sql("SELECT statement_id FROM finance.bank_statement_line WHERE id = :id").param("id", id).query(UUID.class).single();
        Map<String, Object> out = statement(statement);
        out.put("bankCredit", credit);
        return out;
    }
}
