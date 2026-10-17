package ng.edu.moaum.portal.finance;

import java.sql.Types;
import java.util.ArrayList;
import java.util.Base64;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

import jakarta.validation.Valid;
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
 * School fees payment swap (V527): a verified school-fees payment credited to the wrong student is moved to the student it belongs
 * to as a controlled correction. The Students Account Officer (or the Bursar) finds the payment and the student it belongs to,
 * gives the reason, the evidence and the confirmation; a Bursar officer — never the one who
 * initiated it — rejects it, or approves it and it is executed at once in the database (finance.decide_payment_swap: the payment
 * locked and checked again, its student changed and nothing else, the accounts reconciled, or nothing). Internal Audit reads. The
 * server loads the payment, both students, the amount and the state itself: nothing the browser sends but the two ids, the reason
 * and the decision is believed.
 */
@RestController
@RequestMapping("/api/v1/finance/payment-swaps")
class PaymentSwapController {

    static final String READERS = "hasAnyAuthority('OFFICE_bursar','OFFICE_studentaccounts','OFFICE_audit','OFFICE_deputyaudit','OFFICE_super')";
    static final String INITIATORS = "hasAnyAuthority('OFFICE_bursar','OFFICE_studentaccounts')";
    static final String DECIDERS = "hasAnyAuthority('OFFICE_bursar')";
    static final Set<String> STATUSES = Set.of("PENDING_APPROVAL", "COMPLETED", "REJECTED", "CANCELLED", "FAILED", "REVERSED");
    static final Set<String> EVIDENCE_TYPES = Set.of("application/pdf", "image/jpeg", "image/png");
    static final int PAGE = 50;

    public record SwapIn(@NotNull UUID payment, @NotNull UUID to, @NotBlank @Size(max = 2000) String reason, @Size(max = 2000) String evidence,
                         Boolean confirmed) {
    }

    public record DecideIn(@NotNull Boolean approve, @Size(max = 2000) String note, Boolean confirmed) {
    }

    public record ReasonIn(@NotBlank @Size(max = 2000) String reason, Boolean confirmed) {
    }

    public record EvidenceIn(@NotBlank @Size(max = 200) String filename, @NotBlank String dataUrl) {
    }

    private static final tools.jackson.databind.ObjectMapper JSON = new tools.jackson.databind.ObjectMapper();

    private final JdbcClient jdbc;
    private final FileObjects files;

    PaymentSwapController(JdbcClient jdbc, FileObjects files) {
        this.jdbc = jdbc;
        this.files = files;
    }

    @SuppressWarnings("unchecked")
    private static Map<String, Object> json(String text) {
        return text == null ? Map.of() : JSON.readValue(text, Map.class);
    }

    /** a student as the swap screens show one: names, numbers, where they sit, the status */
    private Map<String, Object> profile(UUID student) {
        return jdbc.sql("""
                SELECT s.id, s.surname || ', ' || s.other_names AS name, s.matric_no, s.admission_no, s.jamb_reg_no, s.current_level, s.status,
                       s.duplicate_of IS NOT NULL AS merged, p.name AS programme, d.name AS department, f.name AS faculty, s.entry_session
                  FROM people.student s LEFT JOIN ref.programme p ON p.code = s.programme_code
                  LEFT JOIN ref.department d ON d.code = p.dept_code LEFT JOIN ref.faculty f ON f.code = coalesce(d.faculty_code, p.faculty_code)
                 WHERE s.id = :s
                """).param("s", student).query().listOfRows().stream().findFirst().orElse(null);
    }

    private Map<String, Object> account(UUID student, String session) {
        return json(jdbc.sql("SELECT finance.payment_swap_account(:s, :ses)::text").param("s", student).param("ses", session).query(String.class).single());
    }

    /** the school-fees payments a search finds — by the payment's reference, receipt or old-portal number, or the student's number or name */
    @GetMapping("/payments")
    @PreAuthorize(INITIATORS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> payments(@RequestParam String q) {
        String t = q == null ? "" : q.trim();
        if (t.length() < 3) {
            throw new DomainRuleViolation("SWAP_SEARCH", "Type three characters or more of a payment reference, receipt, matriculation or JAMB number, or a name.",
                    new DomainRuleViolation.Remedy("Search again.", "You"));
        }
        List<Map<String, Object>> rows = jdbc.sql("""
                WITH hit AS (
                    SELECT r.id FROM finance.payment_reference r WHERE upper(r.reference) = upper(:t) OR upper(r.receipt_no) = upper(:t)
                    UNION SELECT r.id FROM finance.legacy_payref lp JOIN finance.payment_reference r ON r.reference = lp.reference WHERE upper(lp.payref) = upper(:t)
                    UNION SELECT r.id FROM people.student s JOIN finance.payment_reference r ON r.student_id = s.id
                           WHERE upper(s.matric_no) = upper(:t) OR upper(s.jamb_reg_no) = upper(:t) OR upper(s.admission_no) = upper(:t)
                              OR (length(:t) >= 4 AND (s.surname || ' ' || s.other_names) ILIKE '%' || :t || '%'))
                SELECT r.id, r.reference, r.amount, r.session, r.purpose, r.channel, r.receipt_no, r.confirmed_at, s.id AS student_id,
                       s.matric_no, s.surname || ', ' || s.other_names AS name
                  FROM hit JOIN finance.payment_reference r ON r.id = hit.id JOIN people.student s ON s.id = r.student_id
                 WHERE r.purpose LIKE 'School fees%'
                 ORDER BY r.confirmed_at DESC NULLS LAST, r.reference LIMIT 30
                """).param("t", t).query().listOfRows();
        List<Map<String, Object>> out = new ArrayList<>();
        for (Map<String, Object> r : rows) {
            Map<String, Object> m = new LinkedHashMap<>(r);
            Map<String, Object> chk = json(jdbc.sql("SELECT finance.payment_swap_check(:p, NULL)::text").param("p", r.get("id")).query(String.class).single());
            m.put("eligible", chk.get("ok"));
            m.put("refusals", chk.get("refusals"));
            out.add(m);
        }
        return out;
    }

    /** the students a search finds, for the student the payment belongs to */
    @GetMapping("/students")
    @PreAuthorize(INITIATORS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> students(@RequestParam String q) {
        String t = q == null ? "" : q.trim();
        if (t.length() < 3) return List.of();
        return jdbc.sql("""
                SELECT s.id, s.surname || ', ' || s.other_names AS name, s.matric_no, s.jamb_reg_no, s.admission_no, s.current_level, s.status,
                       p.name AS programme, s.duplicate_of IS NOT NULL AS merged
                  FROM people.student s LEFT JOIN ref.programme p ON p.code = s.programme_code
                 WHERE upper(s.matric_no) = upper(:t) OR upper(s.jamb_reg_no) = upper(:t) OR upper(s.admission_no) = upper(:t)
                    OR (length(:t) >= 4 AND (s.surname || ' ' || s.other_names) ILIKE '%' || :t || '%')
                    OR s.candidate_id IN (SELECT a.candidate_id FROM admissions.application a WHERE upper(a.application_no) = upper(:t))
                 ORDER BY s.matric_no NULLS LAST, s.surname LIMIT 20
                """).param("t", t).query().listOfRows();
    }

    /** whether a payment may be swapped to a student, with both students and both accounts as they stand */
    @GetMapping("/check")
    @PreAuthorize(INITIATORS)
    @Transactional(readOnly = true)
    Map<String, Object> check(@RequestParam UUID payment, @RequestParam(required = false) UUID to) {
        Map<String, Object> chk = json(jdbc.sql("SELECT finance.payment_swap_check(:p, :t)::text").param("p", payment).param("t", to, Types.OTHER).query(String.class).single());
        Map<String, Object> out = new LinkedHashMap<>(chk);
        Object pay = chk.get("payment");
        if (pay instanceof Map<?, ?> p) {
            String session = String.valueOf(p.get("session"));
            Object fromId = ((Map<?, ?>) chk.get("from")).get("id");
            UUID from = UUID.fromString(String.valueOf(fromId));
            out.put("fromProfile", profile(from));
            out.put("fromAccount", account(from, session));
            if (to != null && chk.get("to") != null) {
                out.put("toProfile", profile(to));
                out.put("toAccount", account(to, session));
            }
        }
        return out;
    }

    /** initiated: the swap waits for another officer's decision */
    @PostMapping
    @PreAuthorize(INITIATORS)
    @Transactional
    Map<String, Object> initiate(@Valid @RequestBody SwapIn body) {
        UUID id = jdbc.sql("SELECT finance.initiate_payment_swap(:p, :t, :r, :e, :c)").param("p", body.payment()).param("t", body.to())
                .param("r", body.reason()).param("e", body.evidence(), Types.VARCHAR).param("c", Boolean.TRUE.equals(body.confirmed()))
                .query(UUID.class).single();
        return detail(id);
    }

    /** a file supporting the swap — PDF, JPEG or PNG, up to 5 MB — in the file store where there is one */
    @PostMapping("/{id}/evidence")
    @PreAuthorize(INITIATORS)
    @Transactional
    Map<String, Object> evidence(@PathVariable UUID id, @Valid @RequestBody EvidenceIn body) {
        Map<String, Object> s = swapRow(id);
        if (!"PENDING_APPROVAL".equals(s.get("status"))) {
            throw new DomainRuleViolation("SWAP_DECIDED", "Evidence is added while the swap waits for a decision.", new DomainRuleViolation.Remedy("Open a new swap if needed.", "Bursary"));
        }
        String u = body.dataUrl();
        int comma = u.indexOf(',');
        String meta = comma > 0 && u.startsWith("data:") ? u.substring(5, comma) : "";
        String type = meta.contains(";") ? meta.substring(0, meta.indexOf(';')) : meta;
        if (!EVIDENCE_TYPES.contains(type)) {
            throw new DomainRuleViolation("SWAP_EVIDENCE_TYPE", "Evidence is a PDF, JPEG or PNG file.", new DomainRuleViolation.Remedy("Scan or save it as one of those.", "You"));
        }
        byte[] bytes;
        try {
            bytes = Base64.getDecoder().decode(u.substring(comma + 1).replaceAll("\\s", ""));
        } catch (IllegalArgumentException bad) {
            throw new DomainRuleViolation("SWAP_EVIDENCE_FILE", "The file could not be read.", new DomainRuleViolation.Remedy("Choose the file again.", "You"));
        }
        if (bytes.length == 0 || bytes.length > 5 * 1024 * 1024) {
            throw new DomainRuleViolation("SWAP_EVIDENCE_SIZE", "Evidence is up to 5 MB.", new DomainRuleViolation.Remedy("Scan it at a lower resolution.", "You"));
        }
        UUID object = files.store("finance.payment_swap_evidence", id, body.filename(), type, bytes);
        jdbc.sql("""
                INSERT INTO finance.payment_swap_evidence (swap_id, filename, content_type, size_bytes, content, object_id, added_by)
                VALUES (:s, :f, :t, :n, :c, :o, nullif(current_setting('moaum.actor_id', true), '')::uuid)
                """).param("s", id).param("f", body.filename().trim()).param("t", type).param("n", (long) bytes.length)
                .param("c", object == null ? bytes : null, Types.BINARY).param("o", object, Types.OTHER).update();
        jdbc.sql("SELECT finance.payment_swap_note(:s, 'PAYMENT_SWAP_EVIDENCE_ADDED', NULL, :n)").param("s", id).param("n", body.filename().trim()).query().listOfRows();
        return detail(id);
    }

    @GetMapping("/{id}/evidence/{evidence}")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    ResponseEntity<byte[]> evidenceFile(@PathVariable UUID id, @PathVariable UUID evidence) {
        Map<String, Object> e = jdbc.sql("SELECT filename, content_type, content, object_id FROM finance.payment_swap_evidence WHERE id = :e AND swap_id = :s")
                .param("e", evidence).param("s", id).query().listOfRows().stream().findFirst().orElseThrow(() -> new NotFound("evidence", evidence));
        byte[] bytes = e.get("content") instanceof byte[] b ? b : files.load(UUID.fromString(String.valueOf(e.get("object_id"))));
        return ResponseEntity.ok().contentType(MediaType.parseMediaType(String.valueOf(e.get("content_type"))))
                .header(HttpHeaders.CONTENT_DISPOSITION, "inline; filename=\"" + String.valueOf(e.get("filename")).replaceAll("[^A-Za-z0-9._ -]", "_") + "\"")
                .body(bytes);
    }

    /** decided by another officer: rejected, or approved and executed at once */
    @PostMapping("/{id}/decide")
    @PreAuthorize(DECIDERS)
    @Transactional
    Map<String, Object> decide(@PathVariable UUID id, @Valid @RequestBody DecideIn body) {
        Map<String, Object> result = json(jdbc.sql("SELECT finance.decide_payment_swap(:s, :a, :n, :c)::text").param("s", id).param("a", body.approve())
                .param("n", body.note(), Types.VARCHAR).param("c", Boolean.TRUE.equals(body.confirmed())).query(String.class).single());
        Map<String, Object> out = new LinkedHashMap<>(detail(id));
        out.put("result", result);
        return out;
    }

    @PostMapping("/{id}/cancel")
    @PreAuthorize(INITIATORS)
    @Transactional
    Map<String, Object> cancel(@PathVariable UUID id, @Valid @RequestBody ReasonIn body) {
        jdbc.sql("SELECT finance.cancel_payment_swap(:s, :r)").param("s", id).param("r", body.reason()).query().listOfRows();
        return detail(id);
    }

    /** a completed swap reversed by a swap of its own — initiated by a Bursar officer, decided by another */
    @PostMapping("/{id}/reverse")
    @PreAuthorize(DECIDERS)
    @Transactional
    Map<String, Object> reverse(@PathVariable UUID id, @Valid @RequestBody ReasonIn body) {
        UUID rv = jdbc.sql("SELECT finance.initiate_payment_swap(NULL, NULL, :r, NULL, :c, :s)").param("r", body.reason())
                .param("c", Boolean.TRUE.equals(body.confirmed())).param("s", id).query(UUID.class).single();
        return detail(rv);
    }

    private Map<String, Object> swapRow(UUID id) {
        return jdbc.sql("""
                SELECT w.*, helpdesk.person_name(w.initiated_by) AS initiated_name, helpdesk.person_name(w.decided_by) AS decided_name,
                       w.initiated_by = nullif(current_setting('moaum.actor_id', true), '')::uuid AS initiated_by_me,
                       r.reference AS reference_now, r.student_id AS credited_now, (SELECT x.swap_ref FROM finance.payment_swap x WHERE x.id = w.reverses) AS reverses_ref,
                       (SELECT x.swap_ref FROM finance.payment_swap x WHERE x.reverses = w.id AND x.status = 'COMPLETED') AS reversed_by_ref
                  FROM finance.payment_swap w LEFT JOIN finance.payment_reference r ON r.id = w.payment_id
                 WHERE w.id = :s
                """).param("s", id).query().listOfRows().stream().findFirst().orElseThrow(() -> new NotFound("payment swap", id));
    }

    /** the swap with both students, the payment as it is now, the accounts, the timeline and the evidence */
    @GetMapping("/{id}")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> detail(@PathVariable UUID id) {
        Map<String, Object> s = new LinkedHashMap<>(swapRow(id));
        for (String k : List.of("before_state", "after_state")) {
            Object v = s.get(k);
            if (v != null) s.put(k, json(String.valueOf(v)));
        }
        Object flags = s.get("flags");
        if (flags instanceof java.sql.Array a) {
            try {
                s.put("flags", List.of((String[]) a.getArray()));
            } catch (java.sql.SQLException e) {
                throw new IllegalStateException(e);
            }
        }
        UUID from = (UUID) s.get("from_student");
        UUID to = (UUID) s.get("to_student");
        String session = String.valueOf(s.get("session"));
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("swap", s);
        out.put("from", profile(from));
        out.put("to", profile(to));
        out.put("fromAccount", account(from, session));
        out.put("toAccount", account(to, session));
        if ("PENDING_APPROVAL".equals(s.get("status"))) {
            Map<String, Object> chk = json(jdbc.sql("SELECT finance.payment_swap_check(:p, :t, :i)::text").param("p", s.get("payment_id")).param("t", to)
                    .param("i", "REVERSAL".equals(s.get("kind")) ? s.get("reverses") : null, Types.OTHER).query(String.class).single());
            List<Object> refusals = new ArrayList<>();
            if (chk.get("refusals") instanceof List<?> l) for (Object x : l) if (!String.valueOf(x).startsWith("SWAP_OPEN:")) refusals.add(x);
            out.put("refusalsNow", refusals);
        }
        out.put("events", jdbc.sql("""
                SELECT e.action, e.note, e.at, e.actor_office, helpdesk.person_name(e.actor_id) AS actor, st.matric_no AS student
                  FROM finance.payment_swap_event e LEFT JOIN people.student st ON st.id = e.student_id
                 WHERE e.swap_id = :s ORDER BY e.at, e.action
                """).param("s", id).query().listOfRows());
        out.put("evidence", jdbc.sql("SELECT id, filename, content_type, size_bytes, added_at, helpdesk.person_name(added_by) AS added_by FROM finance.payment_swap_evidence WHERE swap_id = :s ORDER BY added_at")
                .param("s", id).query().listOfRows());
        // the payment's own story: generated, confirmed, then every swap of it
        out.put("paymentHistory", jdbc.sql("""
                SELECT w.swap_ref, w.kind, w.status, w.initiated_at, w.executed_at, fs.matric_no AS from_matric, ts.matric_no AS to_matric
                  FROM finance.payment_swap w JOIN people.student fs ON fs.id = w.from_student JOIN people.student ts ON ts.id = w.to_student
                 WHERE w.payment_id = :p ORDER BY w.initiated_at
                """).param("p", s.get("payment_id")).query().listOfRows());
        return out;
    }

    /** the swaps, newest first, with the counts by status — filtered as the report asks */
    @GetMapping
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> list(@RequestParam(required = false) String status, @RequestParam(required = false) String q, @RequestParam(required = false) String session,
                             @RequestParam(required = false) String faculty, @RequestParam(required = false) String department,
                             @RequestParam(required = false) String from, @RequestParam(required = false) String to,
                             @RequestParam(defaultValue = "0") int page, @RequestParam(defaultValue = "false") boolean all) {
        String st = status == null || status.isBlank() ? null : status.trim().toUpperCase();
        if (st != null && !STATUSES.contains(st)) {
            throw new DomainRuleViolation("SWAP_STATUS", "A status is one of " + STATUSES + ".", new DomainRuleViolation.Remedy("Choose one.", "You"));
        }
        java.time.LocalDate d1 = from == null || from.isBlank() ? null : java.time.LocalDate.parse(from.trim());
        java.time.LocalDate d2 = to == null || to.isBlank() ? null : java.time.LocalDate.parse(to.trim());
        String where = """
                 WHERE (CAST(:st AS text) IS NULL OR w.status = :st)
                   AND (CAST(:ses AS text) IS NULL OR w.session = :ses)
                   AND (CAST(:q AS text) IS NULL OR upper(w.swap_ref) = upper(:q) OR upper(w.reference) = upper(:q) OR upper(coalesce(w.receipt_no, '')) = upper(:q)
                        OR upper(coalesce(fs.matric_no, '')) = upper(:q) OR upper(coalesce(ts.matric_no, '')) = upper(:q)
                        OR (fs.surname || ' ' || fs.other_names) ILIKE '%' || :q || '%' OR (ts.surname || ' ' || ts.other_names) ILIKE '%' || :q || '%')
                   AND (CAST(:fac AS text) IS NULL OR coalesce(td.faculty_code, tp.faculty_code) = :fac OR coalesce(fd.faculty_code, fp.faculty_code) = :fac)
                   AND (CAST(:dept AS text) IS NULL OR tp.dept_code = :dept OR fp.dept_code = :dept)
                   AND (CAST(:d1 AS date) IS NULL OR w.initiated_at >= CAST(:d1 AS date))
                   AND (CAST(:d2 AS date) IS NULL OR w.initiated_at < CAST(:d2 AS date) + 1)
                """;
        String joins = """
                  FROM finance.payment_swap w
                  JOIN people.student fs ON fs.id = w.from_student JOIN people.student ts ON ts.id = w.to_student
                  LEFT JOIN ref.programme fp ON fp.code = fs.programme_code LEFT JOIN ref.department fd ON fd.code = fp.dept_code
                  LEFT JOIN ref.programme tp ON tp.code = ts.programme_code LEFT JOIN ref.department td ON td.code = tp.dept_code
                """;
        String qq = q == null || q.isBlank() ? null : q.trim();
        String ses = session == null || session.isBlank() ? null : session.trim();
        String fac = faculty == null || faculty.isBlank() ? null : faculty.trim().toUpperCase();
        String dept = department == null || department.isBlank() ? null : department.trim().toUpperCase();
        List<Map<String, Object>> rows = jdbc.sql("""
                SELECT w.id, w.swap_ref, w.kind, w.reference, w.amount, w.session, w.purpose, w.payment_confirmed_at, w.legacy, w.status, w.reason, w.flags::text AS flags,
                       fs.matric_no AS from_matric, fs.surname || ', ' || fs.other_names AS from_name, ts.matric_no AS to_matric, ts.surname || ', ' || ts.other_names AS to_name,
                       w.initiated_at, helpdesk.person_name(w.initiated_by) AS initiated_by, w.initiated_office, w.decided_at, helpdesk.person_name(w.decided_by) AS decided_by,
                       w.executed_at, w.initiated_by = nullif(current_setting('moaum.actor_id', true), '')::uuid AS initiated_by_me, count(*) OVER () AS total
                """ + joins + where + " ORDER BY w.initiated_at DESC LIMIT :lim OFFSET :off")
                .param("st", st, Types.VARCHAR).param("ses", ses, Types.VARCHAR).param("q", qq, Types.VARCHAR).param("fac", fac, Types.VARCHAR).param("dept", dept, Types.VARCHAR)
                .param("d1", d1, Types.DATE).param("d2", d2, Types.DATE).param("lim", all ? 5000 : PAGE).param("off", all ? 0 : Math.max(0, page) * PAGE)
                .query().listOfRows();
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("total", rows.isEmpty() ? 0 : ((Number) rows.get(0).get("total")).longValue());
        out.put("page", page);
        out.put("size", all ? 5000 : PAGE);
        out.put("rows", rows.stream().map(r -> { Map<String, Object> m = new LinkedHashMap<>(r); m.remove("total"); return m; }).toList());
        out.put("counts", jdbc.sql("SELECT status, count(*) AS n FROM finance.payment_swap GROUP BY status").query().listOfRows());
        return out;
    }

    /** the swaps a student's account carries, either way — for the student record */
    @GetMapping("/of/{student}")
    @PreAuthorize(READERS + " or hasAnyAuthority('OFFICE_registrar','OFFICE_dregistrar','OFFICE_ict','OFFICE_admin')")
    @Transactional(readOnly = true)
    List<Map<String, Object>> of(@PathVariable UUID student) {
        return jdbc.sql("SELECT * FROM finance.payment_swaps_of(:s)").param("s", student).query().listOfRows();
    }
}
