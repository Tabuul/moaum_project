package ng.edu.moaum.portal.transfers;

import java.math.BigDecimal;
import java.sql.Types;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.Set;

import jakarta.validation.Valid;
import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

import ng.edu.moaum.portal.shared.AuditContextHolder;
import ng.edu.moaum.portal.shared.NotFound;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * V766: the Bursary's side of the inter-university transfer application fee. The fee of a session is stated by the Bursary (bursar,
 * studentaccounts, super) as a draft beside the fee in force and published by the Bursar (bursar, super) — a fee of nothing is
 * published too, and the transfer window opens only once the session's fee is published (finance.iut_fee_state, iut_fee_publish,
 * iut_fee_view: the SIWES fee's pattern, V752). The payments report lists every reference drawn — paid, pending, expired — and the ones
 * owed back (a second payment of one application, or one after it was withdrawn or refused), with totals from the database over the
 * filtered rows (finance.iut_payments). A payment made at the bank is confirmed by hand by the Bursar against the bank's record
 * (admissions.iut_confirm_fee, channel MANUAL). A reference confirmed by hand takes no bank credit: one already proposed for it is
 * never posted by the portal, whatever the note says (finance.iut_bank_credit_already_paid refuses it, IUT_FEE_ALREADY_PAID); the
 * Bursary checks the bank's record and rejects the proposal, and refunds only money received twice.
 */
@RestController
@RequestMapping("/api/v1/finance/transfer-applications")
class TransferApplicationFeeController {

    /** SiwesRegistrationController's offices for its fee and its payments */
    static final String FEE_SETTERS = "hasAnyAuthority('OFFICE_bursar','OFFICE_studentaccounts','OFFICE_super')";
    static final String FEE_PUBLISHERS = "hasAnyAuthority('OFFICE_bursar','OFFICE_super')";
    static final String FEE_READERS = "hasAnyAuthority('OFFICE_bursar','OFFICE_studentaccounts','OFFICE_super','OFFICE_audit','OFFICE_deputyaudit',"
            + "'OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar','OFFICE_ict','OFFICE_admin','OFFICE_vc','OFFICE_dvc')";
    static final String PAYMENT_READERS = "hasAnyAuthority('OFFICE_bursar','OFFICE_studentaccounts','OFFICE_super','OFFICE_audit','OFFICE_deputyaudit')";
    static final Set<String> PAYMENT_READER_OFFICES = Set.of("bursar", "studentaccounts", "super", "audit", "deputyaudit");
    static final String SESSION = "^\\d{4}/\\d{4}$";
    static final int PAGE_MAX = 1000;

    private final JdbcClient jdbc;
    private final tools.jackson.databind.ObjectMapper json;

    TransferApplicationFeeController(JdbcClient jdbc, tools.jackson.databind.ObjectMapper json) {
        this.jdbc = jdbc;
        this.json = json;
    }

    @SuppressWarnings("unchecked")
    private Map<String, Object> parse(String text) {
        return text == null ? new LinkedHashMap<>() : new LinkedHashMap<>(json.readValue(text, Map.class));
    }

    private static String blank(String s) {
        return s == null || s.isBlank() ? null : s.trim();
    }

    /** the session asked, else the one the transfer desks open on (admissions.iut_desk_session: the open window's, else the latest
     *  session with applications on the desks' hands, else the latest window set open, else the University's current session) */
    private String sessionOr(String asked) {
        String s = blank(asked);
        return s != null ? s : jdbc.sql("SELECT admissions.iut_desk_session()").query(String.class).optional().orElse(null);
    }

    public record FeeIn(@NotBlank @Pattern(regexp = SESSION) String session, @NotNull @DecimalMin(value = "0") BigDecimal amount, @Size(max = 600) String note) {
    }

    public record ForSession(@NotBlank @Pattern(regexp = SESSION) String session) {
    }

    /** a session's fee: the figure in force and its state, who published it, the draft waiting for the Bursar (null when none) and
     *  every statement and publication */
    @GetMapping("/fee")
    @PreAuthorize(FEE_READERS)
    @Transactional(readOnly = true)
    Map<String, Object> fee(@RequestParam(required = false) String session) {
        return parse(jdbc.sql("SELECT finance.iut_fee_view(:s)::text").param("s", sessionOr(session), Types.VARCHAR).query(String.class).single());
    }

    /** the fee stated, nothing or more: a draft beside the published fee, which stays in force until the Bursar publishes the draft */
    @PutMapping("/fee")
    @PreAuthorize(FEE_SETTERS)
    @Transactional
    Map<String, Object> stateFee(@Valid @RequestBody FeeIn body) {
        return parse(jdbc.sql("SELECT finance.iut_fee_state(:s, :a, :n)::text").param("s", body.session()).param("a", body.amount())
                .param("n", blank(body.note()), Types.VARCHAR).query(String.class).single());
    }

    /** the draft put in force; a reference already drawn keeps the figure it was drawn at */
    @PostMapping("/fee/publish")
    @PreAuthorize(FEE_PUBLISHERS)
    @Transactional
    Map<String, Object> publishFee(@Valid @RequestBody ForSession body) {
        return parse(jdbc.sql("SELECT finance.iut_fee_publish(:s)::text").param("s", body.session()).query(String.class).single());
    }

    /** the references drawn (every session when none is named): PAID, PENDING, EXPIRED or OWED_BACK, searched by the reference, the
     *  receipt, the application and JAMB numbers and the name, a page at a time; the totals over every row the filters select */
    @GetMapping("/payments")
    @PreAuthorize(PAYMENT_READERS)
    @Transactional(readOnly = true)
    Map<String, Object> payments(@RequestParam(required = false) String session, @RequestParam(required = false) String state,
                                 @RequestParam(required = false) String q, @RequestParam(defaultValue = "0") int page,
                                 @RequestParam(defaultValue = "100") int size) {
        String o = AuditContextHolder.current().map(c -> c.actorOffice()).orElse(null);
        if (o == null || !PAYMENT_READER_OFFICES.contains(o)) {
            throw new AccessDeniedException("The transfer application payments are read in an office that reads them.");
        }
        int sz = Math.max(1, Math.min(size, PAGE_MAX));
        int pg = Math.max(0, page);
        Map<String, Object> out = parse(jdbc.sql("SELECT finance.iut_payments(:s, :st, :q, :n, :off)::text").param("s", blank(session), Types.VARCHAR)
                .param("st", blank(state), Types.VARCHAR).param("q", blank(q), Types.VARCHAR).param("n", sz).param("off", pg * sz).query(String.class).single());
        out.put("page", pg);
        out.put("size", sz);
        return out;
    }

    public record ManualIn(@NotBlank @Size(min = 5, max = 600) String note) {
    }

    /** a payment made at the bank, confirmed by the Bursar from the bank's record: a receipt in the University's series; the first
     *  payment of an application in progress settles it, any other is owed back */
    @PostMapping("/payments/{reference}/confirm")
    @PreAuthorize(FEE_PUBLISHERS)
    @Transactional
    Map<String, Object> confirm(@PathVariable String reference, @Valid @RequestBody ManualIn body) {
        String ref = reference.trim().toUpperCase();
        if (!Boolean.TRUE.equals(jdbc.sql("SELECT EXISTS (SELECT 1 FROM admissions.iut_fee_reference WHERE reference = :r)").param("r", ref).query(Boolean.class).single())) {
            throw new NotFound("transfer application fee reference", ref);
        }
        jdbc.sql("SELECT set_config('moaum.reason', :r, true)").param("r", "Bank payment confirmed: " + body.note().trim()).query().listOfRows();
        String outcome = jdbc.sql("SELECT admissions.iut_confirm_fee(:r, 'MANUAL', :n)").param("r", ref).param("n", body.note().trim()).query(String.class).single();
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("reference", ref);
        out.put("outcome", outcome);
        out.putAll(jdbc.sql("SELECT receipt_no AS \"receiptNo\", settles, confirmed_at AS \"confirmedAt\" FROM admissions.iut_fee_reference WHERE reference = :r")
                .param("r", ref).query().singleRow());
        return out;
    }
}
