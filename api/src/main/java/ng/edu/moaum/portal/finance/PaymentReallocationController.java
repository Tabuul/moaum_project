package ng.edu.moaum.portal.finance;

import java.math.BigDecimal;
import java.sql.Types;
import java.util.ArrayList;
import java.util.Base64;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

import jakarta.validation.Valid;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

import ng.edu.moaum.portal.shared.DomainRuleViolation;
import ng.edu.moaum.portal.shared.FileObjects;
import ng.edu.moaum.portal.shared.NotFound;

import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
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

/**
 * Bursary payment reallocation and correction (V649): a verified payment applied to the wrong purpose, session or semester is
 * moved to the obligation it was meant for, as a controlled correction. The Students Account Officer (or the Bursar) finds the
 * payment, chooses the purpose, session and semester from what the finance engine offers, sees the destination's fee, what is
 * already paid towards it and the balance or surplus the move leaves, and gives what was wrong, the reason and the confirmation;
 * a Bursar officer — never the one who initiated it — returns it for correction, rejects it, or approves it, and an approval is
 * executed at once in the database (finance.decide_payment_reallocation: the payment locked and checked again, its purpose and
 * session changed and nothing else, the ledger reclassified with no bank line, the accounts reconciled — or nothing). Internal
 * Audit reads. The server loads the payment, the student, the fee and every figure itself: nothing the browser sends but the
 * ids, the destination, the reason and the decision is believed.
 *
 * The University's permissions of the brief, as the portal grants them (an endpoint names its offices; there is no permission
 * table): view and history — the Bursar, the Students Account Officer, Internal Audit and Deputy Audit, the platform; initiate,
 * edit (a returned one), cancel and export — the Bursar and the Students Account Officer; review, approve, execute, return, reject
 * and reverse — the Bursar, another officer than the one who initiated it (the database refuses the initiator and the Students
 * Account Officer whatever the screen shows).
 */
@RestController
@RequestMapping("/api/v1/finance/payment-reallocations")
class PaymentReallocationController {

    static final String READERS = "hasAnyAuthority('OFFICE_bursar','OFFICE_studentaccounts','OFFICE_audit','OFFICE_deputyaudit','OFFICE_super')";
    static final String INITIATORS = "hasAnyAuthority('OFFICE_bursar','OFFICE_studentaccounts')";
    static final String DECIDERS = "hasAnyAuthority('OFFICE_bursar')";
    static final Set<String> STATUSES = Set.of("PENDING_APPROVAL", "RETURNED", "COMPLETED", "REJECTED", "CANCELLED", "FAILED", "REVERSED");
    static final Set<String> REASONS = Set.of("WRONG_PURPOSE", "WRONG_SESSION", "WRONG_SEMESTER", "WRONG_LEVEL", "LEGACY_MIGRATION", "RECONCILIATION", "OTHER");
    static final Set<String> EVIDENCE_TYPES = Set.of("application/pdf", "image/jpeg", "image/png");
    static final int PAGE = 50;

    public record ReallocationIn(@NotNull UUID payment, @NotBlank @Size(max = 40) String purpose, @NotBlank @Size(max = 9) String session,
                                 @Min(1) @Max(3) Integer semester, @NotBlank @Size(max = 40) String reasonCode, @NotBlank @Size(max = 2000) String reason,
                                 @Size(max = 2000) String evidence, Boolean confirmed) {
    }

    public record ResubmitIn(@NotBlank @Size(max = 40) String purpose, @NotBlank @Size(max = 9) String session, @Min(1) @Max(3) Integer semester,
                             @NotBlank @Size(max = 40) String reasonCode, @NotBlank @Size(max = 2000) String reason, @Size(max = 2000) String evidence,
                             Boolean confirmed) {
    }

    public record DecideIn(@NotBlank @Size(max = 10) String decision, @Size(max = 2000) String note, Boolean confirmed) {
    }

    public record ReasonIn(@NotBlank @Size(max = 2000) String reason, Boolean confirmed) {
    }

    public record EvidenceIn(@NotBlank @Size(max = 200) String filename, @NotBlank String dataUrl) {
    }

    private static final tools.jackson.databind.ObjectMapper JSON = new tools.jackson.databind.ObjectMapper();

    private final JdbcClient jdbc;
    private final FileObjects files;

    PaymentReallocationController(JdbcClient jdbc, FileObjects files) {
        this.jdbc = jdbc;
        this.files = files;
    }

    @SuppressWarnings("unchecked")
    private static Map<String, Object> json(String text) {
        return text == null ? Map.of() : JSON.readValue(text, Map.class);
    }

    private static String blank(String s) {
        return s == null || s.isBlank() ? null : s.trim();
    }

    private Map<String, Object> check(UUID payment, String purpose, String session, Integer semester, UUID ignore) {
        return json(jdbc.sql("SELECT finance.payment_reallocation_check(:p, :c, :s, :m, :i)::text").param("p", payment)
                .param("c", blank(purpose), Types.VARCHAR).param("s", blank(session), Types.VARCHAR).param("m", semester, Types.INTEGER)
                .param("i", ignore, Types.OTHER).query(String.class).single());
    }

    /** the purposes of the University's catalogue, each saying whether a payment may be moved onto it and how it then counts */
    @GetMapping("/destinations")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> destinations() {
        return jdbc.sql("SELECT * FROM finance.reallocation_destinations()").query().listOfRows();
    }

    /**
     * a student's payments a search finds — by the payment's reference, receipt or old-portal number, the student's matriculation,
     * JAMB, admission or application number, the record's id, or a name — narrowed by purpose, session, status, dates and amount;
     * thirty at most, newest first, each with whether it may be corrected
     */
    @GetMapping("/payments")
    @PreAuthorize(INITIATORS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> payments(@RequestParam String q, @RequestParam(required = false) String session, @RequestParam(required = false) String purpose,
                                       @RequestParam(required = false) String status, @RequestParam(required = false) String from,
                                       @RequestParam(required = false) String to, @RequestParam(required = false) BigDecimal amount) {
        String t = q == null ? "" : q.trim();
        if (t.length() < 3) {
            throw new DomainRuleViolation("REALLOC_SEARCH", "Type three characters or more of a payment reference, receipt, matriculation, JAMB, admission or application number, or a name.",
                    new DomainRuleViolation.Remedy("Search again.", "You"));
        }
        UUID asId = null;
        try {
            asId = UUID.fromString(t);
        } catch (IllegalArgumentException notAnId) {
            // a reference, a number or a name
        }
        String st = blank(status) == null ? null : status.trim().toUpperCase();
        java.time.LocalDate d1 = blank(from) == null ? null : java.time.LocalDate.parse(from.trim());
        java.time.LocalDate d2 = blank(to) == null ? null : java.time.LocalDate.parse(to.trim());
        List<Map<String, Object>> rows = jdbc.sql("""
                WITH who AS (
                    SELECT s.id FROM people.student s
                     WHERE upper(s.matric_no) = upper(:t) OR upper(s.jamb_reg_no) = upper(:t) OR upper(s.admission_no) = upper(:t)
                        OR s.id = CAST(:sid AS uuid)
                        OR s.candidate_id IN (SELECT a.candidate_id FROM admissions.application a WHERE upper(a.application_no) = upper(:t))
                        OR (length(:t) >= 4 AND (s.surname || ' ' || s.other_names) ILIKE '%' || :t || '%')),
                hit AS (
                    SELECT r.id FROM finance.payment_reference r WHERE upper(r.reference) = upper(:t) OR upper(r.receipt_no) = upper(:t)
                    UNION SELECT r.id FROM finance.legacy_payref lp JOIN finance.payment_reference r ON r.reference = lp.reference WHERE upper(lp.payref) = upper(:t)
                    UNION SELECT r.id FROM finance.payment_reference r WHERE r.student_id IN (SELECT id FROM who))
                SELECT r.id, r.reference, r.amount, r.session, r.purpose, finance.purpose_code_of(r.purpose) AS purpose_code, r.channel, r.receipt_no,
                       r.generated_at, r.confirmed_at, s.id AS student_id, s.matric_no, s.admission_no, s.surname || ', ' || s.other_names AS name
                  FROM hit JOIN finance.payment_reference r ON r.id = hit.id JOIN people.student s ON s.id = r.student_id
                 WHERE (CAST(:ses AS text) IS NULL OR r.session = :ses)
                   AND (CAST(:pc AS text) IS NULL OR finance.purpose_code_of(r.purpose) = :pc)
                   AND (CAST(:st AS text) IS NULL OR (:st = 'VERIFIED' AND r.confirmed_at IS NOT NULL) OR (:st = 'UNVERIFIED' AND r.confirmed_at IS NULL))
                   AND (CAST(:d1 AS date) IS NULL OR coalesce(r.confirmed_at, r.generated_at) >= CAST(:d1 AS date))
                   AND (CAST(:d2 AS date) IS NULL OR coalesce(r.confirmed_at, r.generated_at) < CAST(:d2 AS date) + 1)
                   AND (CAST(:amt AS numeric) IS NULL OR r.amount = CAST(:amt AS numeric))
                 ORDER BY r.confirmed_at DESC NULLS LAST, r.generated_at DESC, r.reference LIMIT 30
                """).param("t", t).param("sid", asId, Types.OTHER).param("ses", blank(session), Types.VARCHAR)
                .param("pc", blank(purpose) == null ? null : purpose.trim().toUpperCase(), Types.VARCHAR).param("st", st, Types.VARCHAR)
                .param("d1", d1, Types.DATE).param("d2", d2, Types.DATE).param("amt", amount, Types.NUMERIC).query().listOfRows();
        List<Map<String, Object>> out = new ArrayList<>();
        for (Map<String, Object> r : rows) {
            Map<String, Object> m = new LinkedHashMap<>(r);
            Map<String, Object> chk = check((UUID) r.get("id"), null, null, null, null);
            m.put("eligible", chk.get("ok"));
            m.put("refusals", chk.get("refusals"));
            out.add(m);
        }
        return out;
    }

    /** the sessions a payment of this student may be moved to: the calendar's, each with the student's level in it, its semesters and
     *  whether school fees are stated for the student there — the level is the student's own in the session, never a list */
    @GetMapping("/periods")
    @PreAuthorize(INITIATORS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> periods(@RequestParam UUID payment) {
        UUID student = jdbc.sql("SELECT student_id FROM finance.payment_reference WHERE id = :p").param("p", payment).query(UUID.class).optional()
                .orElseThrow(() -> new NotFound("payment", payment));
        return jdbc.sql("""
                SELECT a.name AS session, a.state, people.level_in(s.id, a.name, 1) AS level,
                       (SELECT array_agg(m.number ORDER BY m.number) FROM policy.semester m WHERE m.session = a.name)::text AS semesters,
                       finance.fee_stated(s.id, a.name) AS fees_stated
                  FROM people.student s CROSS JOIN policy.academic_session a
                 WHERE s.id = :s AND a.name >= coalesce(s.entry_session, a.name)
                 ORDER BY a.name DESC
                """).param("s", student).query().listOfRows();
    }

    /** whether a payment may be moved there, with the student, the obligation it leaves and the one it meets — fee, paid, balance */
    @GetMapping("/check")
    @PreAuthorize(INITIATORS)
    @Transactional(readOnly = true)
    Map<String, Object> checkPayment(@RequestParam UUID payment, @RequestParam(required = false) String purpose, @RequestParam(required = false) String session,
                                     @RequestParam(required = false) Integer semester) {
        return check(payment, purpose, session, semester, null);
    }

    /** initiated: the correction waits for another officer's decision */
    @PostMapping
    @PreAuthorize(INITIATORS)
    @Transactional
    Map<String, Object> initiate(@Valid @RequestBody ReallocationIn body) {
        reasonCode(body.reasonCode());
        UUID id = jdbc.sql("SELECT finance.initiate_payment_reallocation(:p, :c, :s, :m, :rc, :r, :e, :ok)").param("p", body.payment())
                .param("c", body.purpose().trim().toUpperCase()).param("s", body.session().trim()).param("m", body.semester(), Types.INTEGER)
                .param("rc", body.reasonCode().trim().toUpperCase()).param("r", body.reason()).param("e", body.evidence(), Types.VARCHAR)
                .param("ok", Boolean.TRUE.equals(body.confirmed())).query(UUID.class).single();
        return detail(id);
    }

    private static void reasonCode(String code) {
        if (code == null || !REASONS.contains(code.trim().toUpperCase())) {
            throw new DomainRuleViolation("REALLOC_REASON", "Say what was wrong: one of " + REASONS + ".", new DomainRuleViolation.Remedy("Choose one.", "You"));
        }
    }

    /** a correction returned for correction, changed and sent again */
    @PostMapping("/{id}/resubmit")
    @PreAuthorize(INITIATORS)
    @Transactional
    Map<String, Object> resubmit(@PathVariable UUID id, @Valid @RequestBody ResubmitIn body) {
        reasonCode(body.reasonCode());
        jdbc.sql("SELECT finance.resubmit_payment_reallocation(:x, :c, :s, :m, :rc, :r, :e, :ok)").param("x", id)
                .param("c", body.purpose().trim().toUpperCase()).param("s", body.session().trim()).param("m", body.semester(), Types.INTEGER)
                .param("rc", body.reasonCode().trim().toUpperCase()).param("r", body.reason()).param("e", body.evidence(), Types.VARCHAR)
                .param("ok", Boolean.TRUE.equals(body.confirmed())).query().listOfRows();
        return detail(id);
    }

    /** a file supporting the correction — PDF, JPEG or PNG, up to 5 MB — in the file store where there is one */
    @PostMapping("/{id}/evidence")
    @PreAuthorize(INITIATORS)
    @Transactional
    Map<String, Object> evidence(@PathVariable UUID id, @Valid @RequestBody EvidenceIn body) {
        Map<String, Object> x = row(id);
        if (!"PENDING_APPROVAL".equals(x.get("status")) && !"RETURNED".equals(x.get("status"))) {
            throw new DomainRuleViolation("REALLOC_DECIDED", "Evidence is added while the correction is open.", new DomainRuleViolation.Remedy("Open a new correction if needed.", "Bursary"));
        }
        String u = body.dataUrl();
        int comma = u.indexOf(',');
        String meta = comma > 0 && u.startsWith("data:") ? u.substring(5, comma) : "";
        String type = meta.contains(";") ? meta.substring(0, meta.indexOf(';')) : meta;
        if (!EVIDENCE_TYPES.contains(type)) {
            throw new DomainRuleViolation("REALLOC_EVIDENCE_TYPE", "Evidence is a PDF, JPEG or PNG file.", new DomainRuleViolation.Remedy("Scan or save it as one of those.", "You"));
        }
        byte[] bytes;
        try {
            bytes = Base64.getDecoder().decode(u.substring(comma + 1).replaceAll("\\s", ""));
        } catch (IllegalArgumentException bad) {
            throw new DomainRuleViolation("REALLOC_EVIDENCE_FILE", "The file could not be read.", new DomainRuleViolation.Remedy("Choose the file again.", "You"));
        }
        if (bytes.length == 0 || bytes.length > 5 * 1024 * 1024) {
            throw new DomainRuleViolation("REALLOC_EVIDENCE_SIZE", "Evidence is up to 5 MB.", new DomainRuleViolation.Remedy("Scan it at a lower resolution.", "You"));
        }
        UUID object = files.store("finance.payment_reallocation_evidence", id, body.filename(), type, bytes);
        jdbc.sql("""
                INSERT INTO finance.payment_reallocation_evidence (reallocation_id, filename, content_type, size_bytes, content, object_id, added_by)
                VALUES (:x, :f, :t, :n, :c, :o, nullif(current_setting('moaum.actor_id', true), '')::uuid)
                """).param("x", id).param("f", body.filename().trim()).param("t", type).param("n", (long) bytes.length)
                .param("c", object == null ? bytes : null, Types.BINARY).param("o", object, Types.OTHER).update();
        jdbc.sql("SELECT finance.payment_reallocation_note(:x, 'REALLOCATION_EVIDENCE_ADDED', :n)").param("x", id).param("n", body.filename().trim()).query().listOfRows();
        return detail(id);
    }

    @GetMapping("/{id}/evidence/{evidence}")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    ResponseEntity<byte[]> evidenceFile(@PathVariable UUID id, @PathVariable UUID evidence) {
        Map<String, Object> e = jdbc.sql("SELECT filename, content_type, content, object_id FROM finance.payment_reallocation_evidence WHERE id = :e AND reallocation_id = :x")
                .param("e", evidence).param("x", id).query().listOfRows().stream().findFirst().orElseThrow(() -> new NotFound("evidence", evidence));
        byte[] bytes = e.get("content") instanceof byte[] b ? b : files.load(UUID.fromString(String.valueOf(e.get("object_id"))));
        return ResponseEntity.ok().contentType(MediaType.parseMediaType(String.valueOf(e.get("content_type"))))
                .header(HttpHeaders.CONTENT_DISPOSITION, "inline; filename=\"" + String.valueOf(e.get("filename")).replaceAll("[^A-Za-z0-9._ -]", "_") + "\"")
                .body(bytes);
    }

    /** decided by another officer: returned for correction, rejected, or approved and executed at once */
    @PostMapping("/{id}/decide")
    @PreAuthorize(DECIDERS)
    @Transactional
    Map<String, Object> decide(@PathVariable UUID id, @Valid @RequestBody DecideIn body) {
        Map<String, Object> result = json(jdbc.sql("SELECT finance.decide_payment_reallocation(:x, :d, :n, :c)::text").param("x", id)
                .param("d", body.decision().trim().toUpperCase()).param("n", body.note(), Types.VARCHAR).param("c", Boolean.TRUE.equals(body.confirmed()))
                .query(String.class).single());
        Map<String, Object> out = new LinkedHashMap<>(detail(id));
        out.put("result", result);
        return out;
    }

    @PostMapping("/{id}/cancel")
    @PreAuthorize(INITIATORS)
    @Transactional
    Map<String, Object> cancel(@PathVariable UUID id, @Valid @RequestBody ReasonIn body) {
        jdbc.sql("SELECT finance.cancel_payment_reallocation(:x, :r)").param("x", id).param("r", body.reason()).query().listOfRows();
        return detail(id);
    }

    /** a completed correction reversed by one of its own — initiated by a Bursar officer, decided by another */
    @PostMapping("/{id}/reverse")
    @PreAuthorize(DECIDERS)
    @Transactional
    Map<String, Object> reverse(@PathVariable UUID id, @Valid @RequestBody ReasonIn body) {
        UUID rv = jdbc.sql("SELECT finance.initiate_payment_reallocation(NULL, NULL, NULL, NULL, 'OTHER', :r, NULL, :c, :x)").param("r", body.reason())
                .param("c", Boolean.TRUE.equals(body.confirmed())).param("x", id).query(UUID.class).single();
        return detail(rv);
    }

    private Map<String, Object> row(UUID id) {
        return jdbc.sql("""
                SELECT x.*, helpdesk.person_name(x.initiated_by) AS initiated_name, helpdesk.person_name(x.decided_by) AS decided_name,
                       helpdesk.person_name(x.returned_by) AS returned_name,
                       x.initiated_by = nullif(current_setting('moaum.actor_id', true), '')::uuid AS initiated_by_me,
                       r.purpose AS purpose_now, r.session AS session_now,
                       (SELECT y.realloc_ref FROM finance.payment_reallocation y WHERE y.id = x.reverses) AS reverses_ref,
                       (SELECT y.realloc_ref FROM finance.payment_reallocation y WHERE y.reverses = x.id AND y.status = 'COMPLETED') AS reversed_by_ref,
                       (SELECT j.journal_no FROM finance.gl_journal j WHERE j.id = x.gl_journal) AS journal_no
                  FROM finance.payment_reallocation x LEFT JOIN finance.payment_reference r ON r.id = x.payment_id
                 WHERE x.id = :x
                """).param("x", id).query().listOfRows().stream().findFirst().orElseThrow(() -> new NotFound("payment correction", id));
    }

    /** the correction with the student, the payment as it is now, both obligations, the timeline, the evidence and the payment's history */
    @GetMapping("/{id}")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> detail(@PathVariable UUID id) {
        Map<String, Object> x = new LinkedHashMap<>(row(id));
        for (String k : List.of("before_state", "after_state")) {
            Object v = x.get(k);
            if (v != null) x.put(k, json(String.valueOf(v)));
        }
        Object flags = x.get("flags");
        if (flags instanceof java.sql.Array a) {
            try {
                x.put("flags", List.of((String[]) a.getArray()));
            } catch (java.sql.SQLException e) {
                throw new IllegalStateException(e);
            }
        }
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("reallocation", x);
        boolean open = "PENDING_APPROVAL".equals(x.get("status")) || "RETURNED".equals(x.get("status"));
        UUID payment = (UUID) x.get("payment_id");
        Map<String, Object> chk = "REVERSAL".equals(x.get("kind"))
                ? json(jdbc.sql("SELECT finance.payment_reallocation_check(:p, NULL, :s, NULL, :i, :t)::text").param("p", payment).param("s", x.get("to_session"))
                        .param("i", id).param("t", x.get("to_purpose")).query(String.class).single())
                : check(payment, String.valueOf(x.get("to_purpose_code")), String.valueOf(x.get("to_session")), (Integer) x.get("to_semester"), id);
        out.put("student", chk.get("student"));
        out.put("source", chk.get("source"));
        out.put("destination", chk.get("destination"));
        if (open) {
            out.put("refusalsNow", chk.get("refusals"));
        }
        out.put("events", jdbc.sql("""
                SELECT e.action, e.note, e.at, e.actor_office, helpdesk.person_name(e.actor_id) AS actor
                  FROM finance.payment_reallocation_event e WHERE e.reallocation_id = :x ORDER BY e.at, e.action
                """).param("x", id).query().listOfRows());
        out.put("evidence", jdbc.sql("SELECT id, filename, content_type, size_bytes, added_at, helpdesk.person_name(added_by) AS added_by FROM finance.payment_reallocation_evidence WHERE reallocation_id = :x ORDER BY added_at")
                .param("x", id).query().listOfRows());
        // the payment's own story: confirmed, then every correction and swap of it
        out.put("paymentHistory", jdbc.sql("""
                SELECT y.realloc_ref AS ref, y.kind, y.status, y.from_purpose || ' (' || y.from_session || ')' AS from_what, y.to_purpose || ' (' || y.to_session || ')' AS to_what,
                       y.initiated_at, y.executed_at
                  FROM finance.payment_reallocation y WHERE y.payment_id = :p
                UNION ALL
                SELECT w.swap_ref, 'SWAP', w.status, fs.matric_no, ts.matric_no, w.initiated_at, w.executed_at
                  FROM finance.payment_swap w JOIN people.student fs ON fs.id = w.from_student JOIN people.student ts ON ts.id = w.to_student
                 WHERE w.payment_id = :p
                 ORDER BY 6
                """).param("p", payment).query().listOfRows());
        return out;
    }

    /** the corrections, newest first, with the counts by status — filtered as the report asks */
    @GetMapping
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> list(@RequestParam(required = false) String status, @RequestParam(required = false) String q, @RequestParam(required = false) String session,
                             @RequestParam(required = false) String purpose, @RequestParam(required = false) String faculty,
                             @RequestParam(required = false) String department, @RequestParam(required = false) String programme,
                             @RequestParam(required = false) Integer level, @RequestParam(required = false) String from, @RequestParam(required = false) String to,
                             @RequestParam(defaultValue = "0") int page, @RequestParam(defaultValue = "false") boolean all) {
        String st = blank(status) == null ? null : status.trim().toUpperCase();
        if (st != null && !STATUSES.contains(st)) {
            throw new DomainRuleViolation("REALLOC_STATUS", "A status is one of " + STATUSES + ".", new DomainRuleViolation.Remedy("Choose one.", "You"));
        }
        java.time.LocalDate d1 = blank(from) == null ? null : java.time.LocalDate.parse(from.trim());
        java.time.LocalDate d2 = blank(to) == null ? null : java.time.LocalDate.parse(to.trim());
        String where = """
                 WHERE (CAST(:st AS text) IS NULL OR x.status = :st)
                   AND (CAST(:ses AS text) IS NULL OR x.from_session = :ses OR x.to_session = :ses)
                   AND (CAST(:pc AS text) IS NULL OR x.from_purpose_code = :pc OR x.to_purpose_code = :pc)
                   AND (CAST(:q AS text) IS NULL OR upper(x.realloc_ref) = upper(:q) OR upper(x.reference) = upper(:q) OR upper(coalesce(x.receipt_no, '')) = upper(:q)
                        OR upper(coalesce(s.matric_no, '')) = upper(:q) OR (s.surname || ' ' || s.other_names) ILIKE '%' || :q || '%'
                        OR helpdesk.person_name(x.initiated_by) ILIKE '%' || :q || '%' OR helpdesk.person_name(x.decided_by) ILIKE '%' || :q || '%')
                   AND (CAST(:fac AS text) IS NULL OR x.faculty_code = :fac)
                   AND (CAST(:dept AS text) IS NULL OR x.dept_code = :dept)
                   AND (CAST(:prog AS text) IS NULL OR x.programme_code = :prog)
                   AND (CAST(:lvl AS int) IS NULL OR x.from_level = :lvl OR x.to_level = :lvl)
                   AND (CAST(:d1 AS date) IS NULL OR x.initiated_at >= CAST(:d1 AS date))
                   AND (CAST(:d2 AS date) IS NULL OR x.initiated_at < CAST(:d2 AS date) + 1)
                """;
        List<Map<String, Object>> rows = jdbc.sql("""
                SELECT x.id, x.realloc_ref, x.kind, x.reference, x.amount, x.from_purpose, x.from_purpose_code, x.from_session, x.from_semester, x.from_level,
                       x.to_purpose, x.to_purpose_code, x.to_session, x.to_semester, x.to_level, x.destination_fee, x.balance_after, x.surplus, x.legacy,
                       x.status, x.reason_code, x.reason, x.flags::text AS flags, s.matric_no, s.surname || ', ' || s.other_names AS name,
                       x.initiated_at, helpdesk.person_name(x.initiated_by) AS initiated_by, x.initiated_office, x.decided_at,
                       helpdesk.person_name(x.decided_by) AS decided_by, x.executed_at,
                       x.initiated_by = nullif(current_setting('moaum.actor_id', true), '')::uuid AS initiated_by_me, count(*) OVER () AS total
                  FROM finance.payment_reallocation x JOIN people.student s ON s.id = x.student_id
                """ + where + " ORDER BY x.initiated_at DESC LIMIT :lim OFFSET :off")
                .param("st", st, Types.VARCHAR).param("ses", blank(session), Types.VARCHAR)
                .param("pc", blank(purpose) == null ? null : purpose.trim().toUpperCase(), Types.VARCHAR).param("q", blank(q), Types.VARCHAR)
                .param("fac", blank(faculty) == null ? null : faculty.trim().toUpperCase(), Types.VARCHAR)
                .param("dept", blank(department) == null ? null : department.trim().toUpperCase(), Types.VARCHAR)
                .param("prog", blank(programme) == null ? null : programme.trim().toUpperCase(), Types.VARCHAR).param("lvl", level, Types.INTEGER)
                .param("d1", d1, Types.DATE).param("d2", d2, Types.DATE).param("lim", all ? 5000 : PAGE).param("off", all ? 0 : Math.max(0, page) * PAGE)
                .query().listOfRows();
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("total", rows.isEmpty() ? 0 : ((Number) rows.get(0).get("total")).longValue());
        out.put("page", page);
        out.put("size", all ? 5000 : PAGE);
        out.put("rows", rows.stream().map(r -> { Map<String, Object> m = new LinkedHashMap<>(r); m.remove("total"); return m; }).toList());
        out.put("counts", jdbc.sql("SELECT status, count(*) AS n FROM finance.payment_reallocation GROUP BY status").query().listOfRows());
        return out;
    }
}
