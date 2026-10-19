package ng.edu.moaum.portal.finance;

import java.time.LocalDate;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotEmpty;
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

/** V570: Interswitch's per-transaction settlement report — uploaded and matched row by row, each day tied to the collections credit
 *  of its net with Interswitch's fees booked against 5250 Bank charges, a tie taken back, a row for a never-confirmed reference sent
 *  to the bank credits. The rules are the database's (finance.load_settlement_file and its neighbours). */
@RestController
@RequestMapping("/api/v1/finance/settlements")
class SettlementFilesController {

    private static final String READERS = "hasAnyAuthority('OFFICE_bursar','OFFICE_studentaccounts','OFFICE_audit','OFFICE_deputyaudit','OFFICE_admin','OFFICE_super')";
    /** the report is uploaded and matched by whoever matches the statements (V552) */
    private static final String RECONCILERS = "hasAnyAuthority('OFFICE_bursar','OFFICE_audit','OFFICE_deputyaudit','OFFICE_super')";
    /** a tie books the charges and a bank credit is proposed: the Bursary's */
    private static final String BURSARY = "hasAnyAuthority('OFFICE_bursar','OFFICE_super')";
    /** the rows sent with a report; the counts cover them all */
    static final int ITEM_ROWS = 5000;

    public record Upload(@NotBlank @Size(max = 200) String label, @Size(max = 300) String fileName, @NotEmpty @Size(max = 50_000) List<Map<String, Object>> rows) {
    }

    public record Tie(@NotNull UUID lineId) {
    }

    private final JdbcClient jdbc;
    private final tools.jackson.databind.ObjectMapper json;

    SettlementFilesController(JdbcClient jdbc, tools.jackson.databind.ObjectMapper json) {
        this.jdbc = jdbc;
        this.json = json;
    }

    /** the reports uploaded, the latest first, with how their rows matched and how many days are tied */
    @GetMapping
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> files() {
        return jdbc.sql("""
                SELECT f.id, f.label, f.file_name, f.rows, f.gross, f.fees, f.net, f.first_day::text AS first_day, f.last_day::text AS last_day, f.uploaded_at,
                       CASE WHEN p.id IS NULL THEN NULL ELSE p.surname || ', ' || p.given_names END AS uploaded_by_name,
                       (SELECT count(*) FROM finance.settlement_day d WHERE d.file_id = f.id) AS days,
                       (SELECT count(*) FROM finance.settlement_day d WHERE d.file_id = f.id AND d.line_id IS NOT NULL) AS tied_days,
                       (SELECT count(*) FROM finance.settlement_item i WHERE i.file_id = f.id AND i.state = 'NOT_CONFIRMED' AND i.bank_credit_id IS NULL) AS not_confirmed
                  FROM finance.settlement_file f LEFT JOIN iam.person p ON p.id = f.uploaded_by
                 ORDER BY f.uploaded_at DESC LIMIT 50
                """).query().listOfRows();
    }

    /** one report: its days with the credit each is tied to (or the credits that could be it), its rows and how they matched */
    @GetMapping("/{id}")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> file(@PathVariable UUID id) {
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("file", jdbc.sql("""
                SELECT f.id, f.label, f.file_name, f.rows, f.gross, f.fees, f.net, f.first_day::text AS first_day, f.last_day::text AS last_day, f.uploaded_at,
                       CASE WHEN p.id IS NULL THEN NULL ELSE p.surname || ', ' || p.given_names END AS uploaded_by_name
                  FROM finance.settlement_file f LEFT JOIN iam.person p ON p.id = f.uploaded_by WHERE f.id = :id
                """).param("id", id).query().singleRow());
        out.put("days", jdbc.sql("""
                SELECT d.settled_on::text AS settled_on, d.payments, d.gross, d.fees, d.net, d.line_id, d.tied_at,
                       s.label AS statement, l.line_no, l.value_date::text AS value_date,
                       CASE WHEN tp.id IS NULL THEN NULL ELSE tp.surname || ', ' || tp.given_names END AS tied_by_name,
                       (SELECT j.journal_no FROM finance.gl_journal j WHERE j.id = l.ledger_journal) AS journal_no
                  FROM finance.settlement_day d
                  LEFT JOIN finance.bank_statement_line l ON l.id = d.line_id
                  LEFT JOIN finance.bank_statement s ON s.id = l.statement_id
                  LEFT JOIN iam.person tp ON tp.id = d.tied_by
                 WHERE d.file_id = :id ORDER BY d.settled_on
                """).param("id", id).query().listOfRows());
        out.put("candidates", jdbc.sql("""
                SELECT settled_on::text AS settled_on, line_id, statement, line_no, value_date::text AS value_date, credit, description
                  FROM finance.settlement_candidates(:id)
                """).param("id", id).query().listOfRows());
        out.put("counts", jdbc.sql("""
                SELECT i.state, count(*) AS rows, sum(i.amount) AS amount FROM finance.settlement_item i WHERE i.file_id = :id GROUP BY i.state ORDER BY i.state
                """).param("id", id).query().listOfRows());
        out.put("items", jdbc.sql("""
                SELECT i.id, i.row_no, i.settled_on::text AS settled_on, i.paid_on::text AS paid_on, i.reference, i.txn_ref, i.log_id, i.channel, i.payer,
                       i.amount, i.fee, i.net, i.state, i.matched_reference, i.matched_by, i.expected, i.bank_credit_id, c.state AS bank_credit_state,
                       nullif(btrim(coalesce(y.surname, '') || ', ' || coalesce(y.other_names, ''), ', '), '') AS portal_payer, y.number
                  FROM finance.settlement_item i
                  LEFT JOIN finance.bank_credit c ON c.id = i.bank_credit_id
                  LEFT JOIN LATERAL (SELECT p.surname, p.other_names, p.number FROM reporting.payments p WHERE p.reference = i.matched_reference LIMIT 1) y
                         ON i.matched_reference IS NOT NULL
                 WHERE i.file_id = :id
                 ORDER BY (i.state IN ('NOT_CONFIRMED', 'UNKNOWN', 'AMOUNT_DIFFERS', 'DUPLICATE')) DESC, i.row_no
                 LIMIT :n
                """).param("id", id).param("n", ITEM_ROWS).query().listOfRows());
        return out;
    }

    /** the report uploaded and matched */
    @PostMapping
    @PreAuthorize(RECONCILERS)
    @Transactional
    Map<String, Object> upload(@Valid @RequestBody Upload body) {
        UUID id = jdbc.sql("SELECT finance.load_settlement_file(:l, :f, :r::jsonb)").param("l", body.label().trim())
                .param("f", body.fileName() == null ? "" : body.fileName()).param("r", json.writeValueAsString(body.rows())).query(UUID.class).single();
        return file(id);
    }

    /** every day with one candidate credit only tied to it, the charges booked */
    @PostMapping("/{id}/tie-all")
    @PreAuthorize(BURSARY)
    @Transactional
    Map<String, Object> tieAll(@PathVariable UUID id) {
        Integer n = jdbc.sql("SELECT finance.tie_settlement_days(:id)").param("id", id).query(Integer.class).single();
        Map<String, Object> out = new LinkedHashMap<>(file(id));
        out.put("tied", n);
        return out;
    }

    /** a day tied to the credit the Bursary chose */
    @PostMapping("/{id}/days/{day}/tie")
    @PreAuthorize(BURSARY)
    @Transactional
    Map<String, Object> tie(@PathVariable UUID id, @PathVariable LocalDate day, @Valid @RequestBody Tie body) {
        jdbc.sql("SELECT finance.tie_settlement_day(:id, :d, :l)::text").param("id", id).param("d", day).param("l", body.lineId()).query(String.class).single();
        return file(id);
    }

    /** a day's tie taken back, its charges reversed */
    @PostMapping("/{id}/days/{day}/untie")
    @PreAuthorize(BURSARY)
    @Transactional
    Map<String, Object> untie(@PathVariable UUID id, @PathVariable LocalDate day) {
        jdbc.sql("SELECT finance.untie_settlement_day(:id, :d)").param("id", id).param("d", day).query().singleRow();
        return file(id);
    }

    /** a row Interswitch settled for a reference the portal never confirmed, proposed as a bank credit against it */
    @PostMapping("/items/{itemId}/bank-credit")
    @PreAuthorize(BURSARY)
    @Transactional
    Map<String, Object> bankCredit(@PathVariable UUID itemId) {
        UUID credit = jdbc.sql("SELECT finance.settlement_item_to_bank_credit(:i)").param("i", itemId).query(UUID.class).single();
        return Map.of("item", itemId, "bankCredit", credit);
    }
}
