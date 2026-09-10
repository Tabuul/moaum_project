package ng.edu.moaum.portal.finance;

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

    public record Propose(UUID student, @NotBlank @Size(max = 200) String payer, @NotBlank @Size(max = 400) String reason,
                          @NotNull @DecimalMin("0.01") BigDecimal amount, @Size(max = 120) String bank,
                          @Size(max = 200) String accountName, @Size(max = 8) String accountLast4, @Size(max = 60) String source) {
    }

    public record Why(@NotBlank @Size(max = 2000) String why) {
    }

    @GetMapping
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> list(@RequestParam(required = false) String state) {
        return jdbc.sql("""
                SELECT r.id, r.reference, r.student_id, r.payer, r.reason, r.amount, r.bank_name, r.account_name, r.account_last4,
                       r.state, r.proposed_at, r.approved_at, r.rejected_why, r.paid_at, r.source_reference,
                       coalesce(st.matric_no, st.admission_no) AS number,
                       pp.surname || ', ' || pp.given_names AS proposed_by_name,
                       CASE WHEN ap.id IS NULL THEN NULL ELSE ap.surname || ', ' || ap.given_names END AS approved_by_name,
                       r.proposed_by = nullif(current_setting('moaum.actor_id', true), '')::uuid AS proposed_by_me
                  FROM finance.refund r
                  LEFT JOIN people.student st ON st.id = r.student_id
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
                       coalesce(stu.surname || ', ' || stu.other_names, cand.surname || ', ' || cand.other_names) AS payer,
                       coalesce(stu.matric_no, stu.admission_no, app.application_no) AS number,
                       stu.id AS student_id, pr.purpose
                  FROM finance.reference_state(:r) s
                  LEFT JOIN finance.payment_reference pr ON pr.reference = upper(btrim(:r))
                  LEFT JOIN people.student stu ON stu.id = pr.student_id
                  LEFT JOIN admissions.fee_reference fr ON fr.reference = upper(btrim(:r))
                  LEFT JOIN admissions.application app ON app.id = fr.application_id
                  LEFT JOIN admissions.candidate cand ON cand.id = app.candidate_id
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
        String ref = jdbc.sql("SELECT finance.propose_refund(:s, :p, :r, :a, :b, :an, :l, :src)")
                .param("s", body.student(), Types.OTHER).param("p", body.payer()).param("r", body.reason()).param("a", body.amount())
                .param("b", body.bank(), Types.VARCHAR).param("an", body.accountName(), Types.VARCHAR).param("l", body.accountLast4(), Types.VARCHAR)
                .param("src", body.source(), Types.VARCHAR)
                .query(String.class).single();
        return Map.of("reference", ref, "state", "PROPOSED");
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
    Map<String, Object> pay(@PathVariable UUID id) {
        jdbc.sql("SELECT finance.pay_refund(:id)").param("id", id).query().singleRow();
        return Map.of("id", id, "state", "PAID");
    }
}
