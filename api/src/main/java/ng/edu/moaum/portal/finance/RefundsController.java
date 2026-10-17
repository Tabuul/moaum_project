package ng.edu.moaum.portal.finance;

import java.math.BigDecimal;
import java.sql.Types;
import java.time.LocalDate;
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

/** Refunds and credits (V043), maker–checker controlled. */
@RestController
@RequestMapping("/api/v1/finance/refunds")
class RefundsController {

    private static final String READERS = "hasAnyAuthority('OFFICE_bursar','OFFICE_super','OFFICE_audit','OFFICE_admin')";
    private static final String BURSARY = "hasAnyAuthority('OFFICE_bursar','OFFICE_super')";

    private final JdbcClient jdbc;

    RefundsController(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    /** V533: accountNumber is the full ten-digit account, checked against the bank and recorded for the refund; accountLast4 is
     *  read only when it is not given */
    public record Propose(UUID student, @NotBlank @Size(max = 200) String payer, @NotBlank @Size(max = 400) String reason,
                          @NotNull @DecimalMin("0.01") BigDecimal amount, @Size(max = 120) String bank,
                          @Size(max = 200) String accountName, @Size(max = 8) String accountLast4, @Size(max = 60) String source,
                          @Size(max = 20) String accountNumber) {
    }

    /** V533: the account a refund is paid into, recorded at the desk */
    public record Account(@NotBlank @Size(max = 120) String bank, @NotBlank @Size(max = 200) String accountName,
                          @NotBlank @Size(max = 20) String accountNumber) {
    }

    /** V533: a bank on the list refunds are paid into */
    public record Bank(@NotBlank @Size(max = 8) String code, @NotBlank @Size(max = 120) String name, @Size(max = 40) String kind,
                       List<@Size(max = 60) String> aliases, Boolean nubanCheck, Boolean active) {
    }

    public record Why(@NotBlank @Size(max = 2000) String why) {
    }

    /** V534: the evidence a refund is marked paid with — the bank transfer reference and the date the money left */
    public record Paid(@NotBlank @Size(max = 60) String reference, @NotNull LocalDate paidOn) {
    }

    @GetMapping
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> list(@RequestParam(required = false) String state) {
        return jdbc.sql("""
                SELECT r.id, r.reference, r.student_id, r.payer, r.reason, r.amount, r.bank_name, r.account_name, r.account_last4,
                       r.state, r.proposed_at, r.approved_at, r.rejected_why, r.paid_at, r.source_reference,
                       coalesce(st.matric_no, st.admission_no, ja.application_no) AS number,
                       pp.surname || ', ' || pp.given_names AS proposed_by_name,
                       CASE WHEN ap.id IS NULL THEN NULL ELSE ap.surname || ', ' || ap.given_names END AS approved_by_name,
                       r.proposed_by = nullif(current_setting('moaum.actor_id', true), '')::uuid AS proposed_by_me,
                       -- V528: the account the student gave for a refund of overpaid fees, and whether one is awaited from them
                       ra.account_number, ra.given_at AS account_given_at,
                       EXISTS (SELECT 1 FROM finance.overpayment_decision d
                                WHERE d.reference = r.reference AND d.decision = 'REFUND' AND d.superseded_at IS NULL) AS from_overpayment,
                       -- V533: where the account came from (STUDENT, DESK, JUPEB), and whether its name shares a word with the person's
                       ra.bank_code, ra.source AS account_source,
                       -- V534: the evidence of the payment, and how many other refunds carry the same transfer reference
                       r.paid_reference, r.paid_on::text AS paid_on,
                       CASE WHEN r.paid_reference IS NULL THEN NULL
                            ELSE (SELECT count(*) FROM finance.refund o WHERE o.paid_reference = r.paid_reference AND o.id <> r.id) END AS paid_reference_others,
                       CASE WHEN r.account_name IS NULL THEN NULL
                            ELSE finance.names_share(r.account_name, coalesce(st.surname || ' ' || st.other_names,
                                                     ja.surname || ' ' || ja.first_name || coalesce(' ' || ja.middle_name, ''), r.payer)) END AS account_name_matches
                  FROM finance.refund r
                  LEFT JOIN finance.refund_account ra ON ra.refund_id = r.id
                  LEFT JOIN people.student st ON st.id = r.student_id
                  LEFT JOIN jupeb.fee_reference jf ON jf.reference = r.source_reference
                  LEFT JOIN jupeb.application ja ON ja.id = jf.application_id
                  LEFT JOIN iam.person pp ON pp.id = r.proposed_by
                  LEFT JOIN iam.person ap ON ap.id = r.approved_by
                 WHERE (:state::text IS NULL OR r.state = :state)
                 ORDER BY (r.state = 'PROPOSED') DESC, r.proposed_at DESC LIMIT 300
                """).param("state", state == null || state.isBlank() ? null : state.toUpperCase(), Types.VARCHAR).query().listOfRows();
    }

    /** look a transaction up by its reference, to raise a refund against it — payer, number, amount, purpose */
    @GetMapping("/transaction")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> transaction(@RequestParam String reference) {
        List<Map<String, Object>> rows = jdbc.sql("""
                SELECT s.kind, s.amount, s.confirmed_at, s.channel, s.receipt_no,
                       coalesce(stu.surname || ', ' || stu.other_names, cand.surname || ', ' || cand.other_names,
                                upper(ja.surname) || ', ' || ja.first_name || coalesce(' ' || ja.middle_name, '')) AS payer,
                       coalesce(stu.matric_no, stu.admission_no, app.application_no, ja.application_no) AS number,
                       stu.id AS student_id, pr.purpose
                  FROM finance.reference_state(:r) s
                  LEFT JOIN finance.payment_reference pr ON pr.reference = upper(btrim(:r))
                  LEFT JOIN people.student stu ON stu.id = pr.student_id
                  LEFT JOIN admissions.fee_reference fr ON fr.reference = upper(btrim(:r))
                  LEFT JOIN admissions.application app ON app.id = fr.application_id
                  LEFT JOIN admissions.candidate cand ON cand.id = app.candidate_id
                  LEFT JOIN jupeb.fee_reference jf ON jf.reference = upper(btrim(:r))
                  LEFT JOIN jupeb.application ja ON ja.id = jf.application_id
                 WHERE s.amount IS NOT NULL
                """).param("r", reference).query().listOfRows();
        if (rows.isEmpty()) {
            throw new ng.edu.moaum.portal.shared.NotFound("transaction", reference);
        }
        return rows.get(0);
    }

    @PostMapping
    @PreAuthorize(BURSARY)
    @Transactional
    Map<String, Object> propose(@Valid @RequestBody Propose body) {
        // V533: with the full account, the refund is raised bare and the account recorded on it (checked against the bank)
        boolean full = body.accountNumber() != null && !body.accountNumber().isBlank();
        String ref = jdbc.sql("SELECT finance.propose_refund(:s, :p, :r, :a, :b, :an, :l, :src)")
                .param("s", body.student(), Types.OTHER).param("p", body.payer()).param("r", body.reason()).param("a", body.amount())
                .param("b", full ? null : body.bank(), Types.VARCHAR).param("an", full ? null : body.accountName(), Types.VARCHAR)
                .param("l", full ? null : body.accountLast4(), Types.VARCHAR)
                .param("src", body.source(), Types.VARCHAR)
                .query(String.class).single();
        if (full) {
            jdbc.sql("SELECT finance.desk_refund_account((SELECT id FROM finance.refund WHERE reference = :ref), :b, :n, :a)")
                    .param("ref", ref).param("b", body.bank(), Types.VARCHAR).param("n", body.accountName(), Types.VARCHAR)
                    .param("a", body.accountNumber()).query().singleRow();
        }
        return Map.of("reference", ref, "state", "PROPOSED");
    }

    /** V533: the desk records (or changes) the account a refund is paid into; on an approved refund it goes back for another
     *  officer's approval unless it completes the account the approver saw */
    @PostMapping("/{id}/account")
    @PreAuthorize(BURSARY)
    @Transactional
    Map<String, Object> account(@PathVariable UUID id, @Valid @RequestBody Account body) {
        String state = jdbc.sql("SELECT finance.desk_refund_account(:id, :b, :n, :a)")
                .param("id", id).param("b", body.bank()).param("n", body.accountName()).param("a", body.accountNumber())
                .query(String.class).single();
        return Map.of("id", id, "state", state);
    }

    /** V533: the banks a refund is paid into, with whether a number at each is checked (the Bursary keeps the list) */
    @GetMapping("/banks")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> banks() {
        return jdbc.sql("SELECT code, name, array_to_string(aliases, ', ') AS aliases, kind, nuban_check, active FROM finance.bank ORDER BY active DESC, kind, name")
                .query().listOfRows();
    }

    /** V533: a bank added to the list, or one on it renamed, its check switched or set aside */
    @PostMapping("/banks")
    @PreAuthorize(BURSARY)
    @Transactional
    List<Map<String, Object>> saveBank(@Valid @RequestBody Bank body) {
        // the other names in lower case; none given keeps those the bank has
        String aliases = body.aliases() == null ? null
                : String.join("|", body.aliases().stream().map(x -> x == null ? "" : x.trim().toLowerCase()).filter(x -> !x.isEmpty()).distinct().toList());
        jdbc.sql("""
                INSERT INTO finance.bank (code, name, aliases, kind, nuban_check, active)
                VALUES (upper(btrim(:c)), btrim(:n), coalesce(string_to_array(nullif(:al, ''), '|'), '{}'), coalesce(:k, 'COMMERCIAL'), coalesce(:chk, false), coalesce(:act, true))
                ON CONFLICT (code) DO UPDATE SET name = EXCLUDED.name,
                       aliases = coalesce(string_to_array(nullif(:al, ''), '|'), finance.bank.aliases),
                       kind = coalesce(:k, finance.bank.kind), nuban_check = coalesce(:chk, finance.bank.nuban_check),
                       active = coalesce(:act, finance.bank.active)
                """).param("c", body.code()).param("n", body.name()).param("al", aliases, Types.VARCHAR)
                .param("k", body.kind() == null || body.kind().isBlank() ? null : body.kind().trim().toUpperCase(), Types.VARCHAR)
                .param("chk", body.nubanCheck(), Types.BOOLEAN).param("act", body.active(), Types.BOOLEAN).update();
        return banks();
    }

    @PostMapping("/{id}/approve")
    @PreAuthorize(BURSARY)
    @Transactional
    Map<String, Object> approve(@PathVariable UUID id) {
        jdbc.sql("SELECT finance.approve_refund(:id)").param("id", id).query().singleRow();
        return Map.of("id", id, "state", "APPROVED");
    }

    @PostMapping("/{id}/reject")
    @PreAuthorize(BURSARY)
    @Transactional
    Map<String, Object> reject(@PathVariable UUID id, @Valid @RequestBody Why body) {
        jdbc.sql("SELECT finance.reject_refund(:id, :w)").param("id", id).param("w", body.why()).query().singleRow();
        return Map.of("id", id, "state", "REJECTED");
    }

    @PostMapping("/{id}/pay")
    @PreAuthorize(BURSARY)
    @Transactional
    Map<String, Object> pay(@PathVariable UUID id, @Valid @RequestBody Paid body) {
        jdbc.sql("SELECT finance.pay_refund(:id, :r, :d)").param("id", id).param("r", body.reference()).param("d", body.paidOn())
                .query().singleRow();
        return Map.of("id", id, "state", "PAID");
    }
}
