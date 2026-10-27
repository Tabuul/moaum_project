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
 * Payments archived for review (V670): Bursary → Students Account → Payment reconciliation → Archived payments. A payment that
 * appears twice, sits on a student who did not make it, or is not verified is archived — kept as it stood, counted nowhere — and
 * settled through the controlled finance workflow: the Students Account Officer (or the Bursar) archives it, records the
 * investigation and proposes how it is settled (restored to the student it stands on, reallocated to its true owner through the
 * payment swap, confirmed a duplicate, or confirmed never received); a Bursar officer other than the proposer approves, returns or
 * rejects, and an approval is executed at once in the database. Internal Audit reads. The server loads the payment, the students
 * and every figure itself: nothing the browser sends but the ids, the reason, the evidence and the decision is believed.
 *
 * The University's permissions of the brief, as the portal grants them (an endpoint names its offices): view archived payments,
 * view ownership and the history, export — the Bursar, the Students Account Officer, Internal Audit and Deputy Audit, the
 * platform; archive, verify ownership (record the investigation), initiate the reconciliation or reallocation — the Bursar and the
 * Students Account Officer; review, approve, execute — the Bursar, never the officer who proposed it (the database refuses the
 * proposer and the Students Account Officer whatever the screen shows).
 */
@RestController
@RequestMapping("/api/v1/finance/payment-archive")
class PaymentArchiveController {

    static final String READERS = "hasAnyAuthority('OFFICE_bursar','OFFICE_studentaccounts','OFFICE_audit','OFFICE_deputyaudit','OFFICE_super')";
    static final String INITIATORS = "hasAnyAuthority('OFFICE_bursar','OFFICE_studentaccounts')";
    static final String DECIDERS = "hasAnyAuthority('OFFICE_bursar')";
    static final Set<String> STATES = Set.of("ARCHIVED", "UNDER_REVIEW", "PENDING_BURSAR_APPROVAL", "RETURNED", "RECONCILED", "DUPLICATE_CONFIRMED", "NOT_RECEIVED", "OPEN");
    static final Set<String> SOURCES = Set.of("DESK", "DUPLICATE_WITHDRAWAL", "NOT_RECEIVED_WITHDRAWAL");
    static final Set<String> FILE_TYPES = Set.of("application/pdf", "image/jpeg", "image/png");
    static final int PAGE = 50;

    public record Item(@NotBlank @Size(max = 40) String kind, @NotBlank @Size(max = 500) String value) {
    }

    public record ArchiveIn(@NotNull UUID payment, @NotBlank @Size(max = 40) String reason, UUID related, @NotBlank @Size(max = 2000) String note,
                            Boolean confirmed) {
    }

    public record InvestigationIn(@Size(max = 2000) String note, @Size(max = 30) List<@Valid Item> items) {
    }

    public record ProposalIn(@NotBlank @Size(max = 20) String outcome, UUID owner, @NotBlank @Size(max = 2000) String note,
                             @Size(max = 30) List<@Valid Item> items, Boolean confirmed) {
    }

    public record DecisionIn(@NotBlank @Size(max = 10) String decision, @Size(max = 2000) String note, Boolean confirmed) {
    }

    public record FileIn(@NotBlank @Size(max = 200) String filename, @NotBlank String dataUrl) {
    }

    private static final tools.jackson.databind.ObjectMapper JSON = new tools.jackson.databind.ObjectMapper();

    private final JdbcClient jdbc;
    private final FileObjects files;

    PaymentArchiveController(JdbcClient jdbc, FileObjects files) {
        this.jdbc = jdbc;
        this.files = files;
    }

    private static Object json(Object text) {
        if (text == null) return null;
        String s = String.valueOf(text);
        return s.startsWith("[") ? JSON.readValue(s, List.class) : JSON.readValue(s, Map.class);
    }

    private static String blank(String s) {
        return s == null || s.isBlank() ? null : s.trim();
    }

    private static String items(List<Item> items) {
        if (items == null || items.isEmpty()) return "[]";
        List<Map<String, String>> out = new ArrayList<>();
        for (Item i : items) out.add(Map.of("kind", i.kind().trim().toUpperCase(), "value", i.value().trim()));
        return JSON.writeValueAsString(out);
    }

    /** the reasons a payment is archived (the Bursary's list) and the kinds of evidence an investigation records */
    @GetMapping("/catalogue")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> catalogue() {
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("reasons", jdbc.sql("SELECT code, label, explanation, needs_related FROM finance.payment_archive_reason WHERE active ORDER BY ord, code").query().listOfRows());
        out.put("evidenceKinds", jdbc.sql("SELECT * FROM finance.payment_evidence_kinds()").query().listOfRows());
        out.put("sessions", jdbc.sql("SELECT name FROM policy.academic_session ORDER BY name DESC").query(String.class).list());
        out.put("channels", jdbc.sql("SELECT DISTINCT channel FROM finance.payment_archive WHERE channel IS NOT NULL ORDER BY 1").query(String.class).list());
        return out;
    }

    /** the archive in figures — open, duplicate, wrong student, ownership pending, awaiting the Bursar, reconciled, reallocated, never
     *  received, unresolved, each with its value — and verified active revenue against what is archived, for a session or all */
    @GetMapping("/figures")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Object figures(@RequestParam(required = false) String session) {
        return json(jdbc.sql("SELECT finance.payment_archive_figures(:s)::text").param("s", blank(session), Types.VARCHAR).query(String.class).single());
    }

    /**
     * a payment to archive, found by its reference, receipt, old-portal number, the gateway's or a transaction reference, or the
     * student's matriculation, JAMB, admission or application number or name; thirty at most, newest first, each with whether it may
     * be archived and why not
     */
    @GetMapping("/payments")
    @PreAuthorize(INITIATORS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> payments(@RequestParam String q) {
        String t = q == null ? "" : q.trim();
        if (t.length() < 3) {
            throw new DomainRuleViolation("PAR_SEARCH", "Type three characters or more of a payment reference, receipt, gateway reference, matriculation, JAMB or application number, or a name.",
                    new DomainRuleViolation.Remedy("Search again.", "You"));
        }
        List<Map<String, Object>> rows = jdbc.sql("""
                WITH who AS (
                    SELECT s.id FROM people.student s
                     WHERE upper(s.matric_no) = upper(:t) OR upper(s.jamb_reg_no) = upper(:t) OR upper(s.admission_no) = upper(:t)
                        OR s.candidate_id IN (SELECT a.candidate_id FROM admissions.application a WHERE upper(a.application_no) = upper(:t))
                        OR (length(:t) >= 4 AND (s.surname || ' ' || s.other_names) ILIKE '%' || :t || '%')),
                hit AS (
                    SELECT r.id FROM finance.payment_reference r WHERE upper(r.reference) = upper(:t) OR upper(r.receipt_no) = upper(:t)
                    UNION SELECT r.id FROM finance.legacy_payref lp JOIN finance.payment_reference r ON r.reference = lp.reference WHERE upper(lp.payref) = upper(:t)
                    UNION SELECT r.id FROM finance.gateway_event e JOIN finance.payment_reference r ON r.reference = e.reference WHERE upper(e.gateway_ref) = upper(:t)
                    UNION SELECT r.id FROM finance.gateway_attempt g JOIN finance.payment_reference r ON r.reference = g.reference WHERE upper(g.txn_ref) = upper(:t)
                    UNION SELECT r.id FROM finance.payment_reference r WHERE r.student_id IN (SELECT id FROM who))
                SELECT r.id, r.reference, r.amount, r.session, r.purpose, finance.payment_category(r.purpose) AS category, r.channel, r.receipt_no,
                       r.generated_at, r.confirmed_at, r.archived_at, s.id AS student_id, s.matric_no, s.admission_no, s.surname || ', ' || s.other_names AS name,
                       (SELECT k.payref FROM finance.legacy_payref k WHERE k.reference = r.reference ORDER BY k.recorded_at LIMIT 1) AS legacy_payref,
                       finance.payment_archive_refusals(r.id) AS refusals
                  FROM hit JOIN finance.payment_reference r ON r.id = hit.id JOIN people.student s ON s.id = r.student_id
                 WHERE r.confirmed_at IS NOT NULL
                 ORDER BY r.confirmed_at DESC NULLS LAST, r.reference LIMIT 30
                """).param("t", t).query().listOfRows();
        List<Map<String, Object>> out = new ArrayList<>();
        for (Map<String, Object> r : rows) {
            Map<String, Object> m = new LinkedHashMap<>(r);
            List<String> refusals = textArray(r.get("refusals"));
            m.put("refusals", refusals);
            m.put("eligible", refusals.isEmpty());
            out.add(m);
        }
        return out;
    }

    private static List<String> textArray(Object v) {
        if (v instanceof java.sql.Array a) {
            try {
                Object[] xs = (Object[]) a.getArray();
                List<String> out = new ArrayList<>();
                for (Object x : xs) out.add(String.valueOf(x));
                return out;
            } catch (java.sql.SQLException e) {
                throw new IllegalStateException(e);
            }
        }
        return v == null ? List.of() : List.of(String.valueOf(v));
    }

    /** the student a payment belongs to, found by matriculation, JAMB, admission or application number, or name — for a reallocation */
    @GetMapping("/students")
    @PreAuthorize(INITIATORS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> students(@RequestParam String q) {
        String t = q == null ? "" : q.trim();
        if (t.length() < 3) {
            throw new DomainRuleViolation("PAR_SEARCH", "Type three characters or more of a matriculation, JAMB, admission or application number, or a name.",
                    new DomainRuleViolation.Remedy("Search again.", "You"));
        }
        return jdbc.sql("""
                SELECT s.id, s.matric_no, s.admission_no, s.jamb_reg_no, s.surname || ', ' || s.other_names AS name, p.name AS programme, s.current_level, s.status,
                       s.duplicate_of IS NOT NULL AS merged
                  FROM people.student s LEFT JOIN ref.programme p ON p.code = s.programme_code
                 WHERE upper(s.matric_no) = upper(:t) OR upper(s.jamb_reg_no) = upper(:t) OR upper(s.admission_no) = upper(:t)
                    OR s.candidate_id IN (SELECT a.candidate_id FROM admissions.application a WHERE upper(a.application_no) = upper(:t))
                    OR (length(:t) >= 4 AND (s.surname || ' ' || s.other_names) ILIKE '%' || :t || '%')
                 ORDER BY s.surname, s.other_names LIMIT 20
                """).param("t", t).query().listOfRows();
    }

    /** payment records that may be one payment recorded twice: by an authoritative identifier they share, and apart, by the
     *  supporting signals alone (for an officer to check before anything is archived) */
    @GetMapping("/suspects")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> suspects(@RequestParam(required = false) String session, @RequestParam(defaultValue = "200") int limit) {
        return jdbc.sql("""
                SELECT x.*, s.matric_no, s.admission_no, s.surname || ', ' || s.other_names AS name,
                       (SELECT o.student_id FROM finance.payment_reference o WHERE o.id = x.related_id) AS related_student_id,
                       (SELECT coalesce(os.matric_no, os.admission_no) FROM finance.payment_reference o JOIN people.student os ON os.id = o.student_id WHERE o.id = x.related_id) AS related_number
                  FROM finance.payment_duplicate_suspects(:s, :n) x JOIN people.student s ON s.id = x.student_id
                """).param("s", blank(session), Types.VARCHAR).param("n", Math.max(1, Math.min(limit, 2000))).query().listOfRows();
    }

    /** archived: the payment kept as it stood and counted nowhere until the Bursary settles it */
    @PostMapping
    @PreAuthorize(INITIATORS)
    @Transactional
    Map<String, Object> archive(@Valid @RequestBody ArchiveIn body) {
        UUID id = jdbc.sql("SELECT finance.archive_payment(:p, :r, :rel, :n, :ok)").param("p", body.payment()).param("r", body.reason().trim().toUpperCase())
                .param("rel", body.related(), Types.OTHER).param("n", body.note()).param("ok", Boolean.TRUE.equals(body.confirmed()))
                .query(UUID.class).single();
        return detail(id);
    }

    /** the investigation recorded: a note and evidence items, each strong or supporting */
    @PostMapping("/{id}/investigation")
    @PreAuthorize(INITIATORS)
    @Transactional
    Map<String, Object> investigation(@PathVariable UUID id, @Valid @RequestBody InvestigationIn body) {
        jdbc.sql("SELECT finance.payment_archive_record(:x, :n, CAST(:i AS jsonb))").param("x", id).param("n", blank(body.note()), Types.VARCHAR)
                .param("i", items(body.items())).query().listOfRows();
        return detail(id);
    }

    /** a file supporting the investigation — PDF, JPEG or PNG, up to 5 MB — in the file store where there is one */
    @PostMapping("/{id}/files")
    @PreAuthorize(INITIATORS)
    @Transactional
    Map<String, Object> file(@PathVariable UUID id, @Valid @RequestBody FileIn body) {
        Map<String, Object> a = row(id);
        String state = String.valueOf(a.get("state"));
        if (!Set.of("ARCHIVED", "UNDER_REVIEW", "RETURNED", "PENDING_BURSAR_APPROVAL").contains(state)) {
            throw new DomainRuleViolation("PAR_SETTLED", "Evidence is added while the archive is open.", new DomainRuleViolation.Remedy("The archive is settled.", "Bursary"));
        }
        String u = body.dataUrl();
        int comma = u.indexOf(',');
        String meta = comma > 0 && u.startsWith("data:") ? u.substring(5, comma) : "";
        String type = meta.contains(";") ? meta.substring(0, meta.indexOf(';')) : meta;
        if (!FILE_TYPES.contains(type)) {
            throw new DomainRuleViolation("PAR_FILE_TYPE", "Evidence is a PDF, JPEG or PNG file.", new DomainRuleViolation.Remedy("Scan or save it as one of those.", "You"));
        }
        byte[] bytes;
        try {
            bytes = Base64.getDecoder().decode(u.substring(comma + 1).replaceAll("\\s", ""));
        } catch (IllegalArgumentException bad) {
            throw new DomainRuleViolation("PAR_FILE", "The file could not be read.", new DomainRuleViolation.Remedy("Choose the file again.", "You"));
        }
        if (bytes.length == 0 || bytes.length > 5 * 1024 * 1024) {
            throw new DomainRuleViolation("PAR_FILE_SIZE", "Evidence is up to 5 MB.", new DomainRuleViolation.Remedy("Scan it at a lower resolution.", "You"));
        }
        UUID object = files.store("finance.payment_archive_file", id, body.filename(), type, bytes);
        jdbc.sql("""
                INSERT INTO finance.payment_archive_file (archive_id, filename, content_type, size_bytes, content, object_id, added_by)
                VALUES (:x, :f, :t, :n, :c, :o, nullif(current_setting('moaum.actor_id', true), '')::uuid)
                """).param("x", id).param("f", body.filename().trim()).param("t", type).param("n", (long) bytes.length)
                .param("c", object == null ? bytes : null, Types.BINARY).param("o", object, Types.OTHER).update();
        jdbc.sql("SELECT finance.payment_archive_note(:x, 'EVIDENCE_ADDED', :n)").param("x", id).param("n", body.filename().trim()).query().listOfRows();
        return detail(id);
    }

    @GetMapping("/{id}/files/{file}")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    ResponseEntity<byte[]> fileContent(@PathVariable UUID id, @PathVariable UUID file) {
        Map<String, Object> e = jdbc.sql("SELECT filename, content_type, content, object_id FROM finance.payment_archive_file WHERE id = :e AND archive_id = :x")
                .param("e", file).param("x", id).query().listOfRows().stream().findFirst().orElseThrow(() -> new NotFound("evidence", file));
        byte[] bytes = e.get("content") instanceof byte[] b ? b : files.load(UUID.fromString(String.valueOf(e.get("object_id"))));
        return ResponseEntity.ok().contentType(MediaType.parseMediaType(String.valueOf(e.get("content_type"))))
                .header(HttpHeaders.CONTENT_DISPOSITION, "inline; filename=\"" + String.valueOf(e.get("filename")).replaceAll("[^A-Za-z0-9._ -]", "_") + "\"")
                .body(bytes);
    }

    /** proposed: restore, reallocate to its true owner (a payment swap opened), duplicate, or never received — for the Bursar */
    @PostMapping("/{id}/proposal")
    @PreAuthorize(INITIATORS)
    @Transactional
    Map<String, Object> propose(@PathVariable UUID id, @Valid @RequestBody ProposalIn body) {
        Object result = json(jdbc.sql("SELECT finance.payment_archive_propose(:x, :o, :w, :n, CAST(:i AS jsonb), :ok)::text").param("x", id)
                .param("o", body.outcome().trim().toUpperCase()).param("w", body.owner(), Types.OTHER).param("n", body.note())
                .param("i", items(body.items())).param("ok", Boolean.TRUE.equals(body.confirmed())).query(String.class).single());
        Map<String, Object> out = new LinkedHashMap<>(detail(id));
        out.put("result", result);
        return out;
    }

    /** decided by a Bursar officer other than the proposer: returned, rejected, or approved and executed at once */
    @PostMapping("/{id}/decision")
    @PreAuthorize(DECIDERS)
    @Transactional
    Map<String, Object> decide(@PathVariable UUID id, @Valid @RequestBody DecisionIn body) {
        Object result = json(jdbc.sql("SELECT finance.payment_archive_decide(:x, :d, :n, :c)::text").param("x", id)
                .param("d", body.decision().trim().toUpperCase()).param("n", blank(body.note()), Types.VARCHAR).param("c", Boolean.TRUE.equals(body.confirmed()))
                .query(String.class).single());
        Map<String, Object> out = new LinkedHashMap<>(detail(id));
        out.put("result", result);
        return out;
    }

    private Map<String, Object> row(UUID id) {
        return jdbc.sql("""
                SELECT a.*, rs.label AS reason, rs.explanation AS reason_explanation,
                       helpdesk.person_name(a.archived_by) AS archived_by_name, helpdesk.person_name(a.proposed_by) AS proposed_by_name,
                       helpdesk.person_name(a.decided_by) AS decided_by_name, helpdesk.person_name(a.returned_by) AS returned_by_name,
                       a.proposed_by = nullif(current_setting('moaum.actor_id', true), '')::uuid AS proposed_by_me,
                       a.archived_by = nullif(current_setting('moaum.actor_id', true), '')::uuid AS archived_by_me,
                       finance.payment_category(a.purpose) AS category, finance.purpose_semester(a.purpose) AS semester,
                       (SELECT j.journal_no FROM finance.gl_journal j WHERE j.id = a.archive_journal) AS archive_journal_no,
                       (SELECT j.journal_no FROM finance.gl_journal j WHERE j.id = a.settle_journal) AS settle_journal_no,
                       (SELECT j.journal_no FROM finance.gl_journal j WHERE j.id = a.payment_journal) AS payment_journal_no,
                       (SELECT j.journal_no FROM finance.gl_journal j WHERE j.id = a.payment_reversal) AS payment_reversal_no
                  FROM finance.payment_archive a JOIN finance.payment_archive_reason rs ON rs.code = a.reason_code
                 WHERE a.id = :x
                """).param("x", id).query().listOfRows().stream().findFirst().orElseThrow(() -> new NotFound("archived payment", id));
    }

    private Map<String, Object> student(Object id) {
        if (id == null) return null;
        return jdbc.sql("""
                SELECT s.id, s.matric_no, s.admission_no, s.jamb_reg_no, s.surname || ', ' || s.other_names AS name, p.name AS programme,
                       p.dept_code, d.name AS department, p.faculty_code, f.name AS faculty, s.current_level, s.status, s.entry_mode
                  FROM people.student s LEFT JOIN ref.programme p ON p.code = s.programme_code
                  LEFT JOIN ref.department d ON d.code = p.dept_code LEFT JOIN ref.faculty f ON f.code = p.faculty_code
                 WHERE s.id = :s
                """).param("s", id, Types.OTHER).query().listOfRows().stream().findFirst().orElse(null);
    }

    /**
     * the archive with the original payment (as it stood and as it is now), its gateway and old-portal identifiers, the archive
     * information, the verification status, the payment it repeats and what the two share, the students (the one it stood on, the
     * one it stands on now, the owner proposed) with their fees, the swap it opened, the evidence, the files and the timeline
     */
    @GetMapping("/{id}")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> detail(@PathVariable UUID id) {
        Map<String, Object> a = new LinkedHashMap<>(row(id));
        for (String k : List.of("signals", "held", "evidence", "before_state", "after_state")) {
            if (a.get(k) != null) a.put(k, json(a.get(k)));
        }
        UUID payment = (UUID) a.get("payment_id");
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("archive", a);
        Map<String, Object> pay = jdbc.sql("""
                SELECT r.id, r.reference, r.amount, r.purpose, r.session, r.channel, r.receipt_no, r.generated_at, r.confirmed_at, r.archived_at, r.note, r.student_id,
                       finance.purpose_semester(r.purpose) AS semester,
                       (SELECT pi.original_identifier_type || ' ' || pi.original_identifier FROM finance.payment_identity pi WHERE pi.payment_id = r.id LIMIT 1) AS paid_as,
                       (SELECT pi.batch_ref FROM finance.payment_identity pi WHERE pi.payment_id = r.id LIMIT 1) AS batch_ref
                  FROM finance.payment_reference r WHERE r.id = :p
                """).param("p", payment).query().singleRow();
        out.put("payment", pay);
        out.put("gateway", jdbc.sql("""
                SELECT 'EVENT' AS kind, e.gateway, e.gateway_ref AS ref, e.outcome, e.amount, e.received_at AS at FROM finance.gateway_event e WHERE e.reference = :r
                UNION ALL
                SELECT 'ATTEMPT', g.gateway, g.txn_ref, NULL, NULL, g.opened_at FROM finance.gateway_attempt g WHERE g.reference = :r AND g.txn_ref IS NOT NULL
                UNION ALL
                SELECT 'PAYDIRECT', 'paydirect', x.payment_log_id, x.outcome, x.amount, x.received_at FROM finance.paydirect_inbox x WHERE x.reference = :r
                 ORDER BY 6 DESC LIMIT 50
                """).param("r", a.get("reference")).query().listOfRows());
        out.put("legacyNumbers", jdbc.sql("SELECT k.payref, k.amount, k.recorded_at FROM finance.legacy_payref k WHERE k.reference = :r ORDER BY k.recorded_at")
                .param("r", a.get("reference")).query().listOfRows());
        out.put("student", student(a.get("student_id")));
        out.put("currentStudent", student(pay.get("student_id")));
        out.put("owner", student(a.get("owner_student_id")));
        String session = String.valueOf(a.get("session"));
        out.put("account", json(jdbc.sql("SELECT finance.payment_archive_account(:s, :ses)::text").param("s", pay.get("student_id")).param("ses", session)
                .query(String.class).single()));
        if (a.get("owner_student_id") != null) {
            out.put("ownerAccount", json(jdbc.sql("SELECT finance.payment_archive_account(:s, :ses)::text").param("s", a.get("owner_student_id")).param("ses", session)
                    .query(String.class).single()));
        }
        if (a.get("related_payment_id") != null) {
            out.put("related", jdbc.sql("""
                    SELECT r.id, r.reference, r.amount, r.purpose, r.session, r.channel, r.receipt_no, r.confirmed_at, r.archived_at,
                           coalesce(s.matric_no, s.admission_no) AS number, s.surname || ', ' || s.other_names AS name, r.student_id
                      FROM finance.payment_reference r JOIN people.student s ON s.id = r.student_id WHERE r.id = :p
                    """).param("p", a.get("related_payment_id")).query().listOfRows().stream().findFirst().orElse(null));
            out.put("signalsNow", json(jdbc.sql("SELECT finance.payment_duplicate_signals(:p, :r)::text").param("p", payment).param("r", a.get("related_payment_id"))
                    .query(String.class).single()));
        }
        if (a.get("swap_id") != null) {
            out.put("swap", jdbc.sql("""
                    SELECT w.id, w.swap_ref, w.status, w.initiated_at, w.decided_at, w.executed_at, w.failure, coalesce(fs.matric_no, fs.admission_no) AS from_number,
                           coalesce(ts.matric_no, ts.admission_no) AS to_number
                      FROM finance.payment_swap w JOIN people.student fs ON fs.id = w.from_student JOIN people.student ts ON ts.id = w.to_student WHERE w.id = :w
                    """).param("w", a.get("swap_id")).query().listOfRows().stream().findFirst().orElse(null));
        }
        // what else the payment is tied to: the request it paid for, kept as it was (a bed or a transcript is the office's own decision)
        out.put("linked", jdbc.sql("""
                SELECT 'HOSTEL' AS kind, h.id::text AS ref, h.state AS state FROM hostel.allocation h WHERE h.reference = :r
                UNION ALL SELECT 'TRANSCRIPT', t.ref, t.stage FROM credentials.transcript_request t WHERE t.reference = :r
                UNION ALL SELECT 'DEFERMENT_FEE', f.id::text, f.state FROM people.deferment_fee f WHERE f.reference = :r
                UNION ALL SELECT 'REFUND', f.reference, f.state FROM finance.refund f WHERE f.source_reference = :r
                """).param("r", a.get("reference")).query().listOfRows());
        out.put("events", jdbc.sql("""
                SELECT e.action, e.note, e.at, e.actor_office, helpdesk.person_name(e.actor_id) AS actor
                  FROM finance.payment_archive_event e WHERE e.archive_id = :x ORDER BY e.at, e.action
                """).param("x", id).query().listOfRows());
        out.put("files", jdbc.sql("SELECT id, filename, content_type, size_bytes, added_at, helpdesk.person_name(added_by) AS added_by FROM finance.payment_archive_file WHERE archive_id = :x ORDER BY added_at")
                .param("x", id).query().listOfRows());
        // the payment's own story: every archive, swap and correction of it
        out.put("paymentHistory", jdbc.sql("""
                SELECT a.archive_ref AS ref, 'ARCHIVE' AS kind, a.state AS status, a.reason_code AS what, a.archived_at AS at FROM finance.payment_archive a WHERE a.payment_id = :p
                UNION ALL
                SELECT w.swap_ref, 'SWAP', w.status, coalesce(fs.matric_no, fs.admission_no) || ' → ' || coalesce(ts.matric_no, ts.admission_no), w.initiated_at
                  FROM finance.payment_swap w JOIN people.student fs ON fs.id = w.from_student JOIN people.student ts ON ts.id = w.to_student WHERE w.payment_id = :p
                UNION ALL
                SELECT y.realloc_ref, 'CORRECTION', y.status, y.from_purpose || ' → ' || y.to_purpose, y.initiated_at FROM finance.payment_reallocation y WHERE y.payment_id = :p
                 ORDER BY 5
                """).param("p", payment).query().listOfRows());
        return out;
    }

    /** the archive, newest first, with the counts by state — searched and filtered on the server, fifty a page (all for an export) */
    @GetMapping
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> list(@RequestParam(required = false) String state, @RequestParam(required = false) String q, @RequestParam(required = false) String reason,
                             @RequestParam(required = false) String session, @RequestParam(required = false) Integer semester,
                             @RequestParam(required = false) String category, @RequestParam(required = false) String channel,
                             @RequestParam(required = false) String source, @RequestParam(required = false) String from, @RequestParam(required = false) String to,
                             @RequestParam(required = false) String paidFrom, @RequestParam(required = false) String paidTo,
                             @RequestParam(required = false) BigDecimal amount, @RequestParam(required = false) UUID student,
                             @RequestParam(defaultValue = "0") int page, @RequestParam(defaultValue = "false") boolean all) {
        String st = blank(state) == null ? null : state.trim().toUpperCase();
        if (st != null && !STATES.contains(st)) {
            throw new DomainRuleViolation("PAR_STATE", "A state is one of " + STATES + ".", new DomainRuleViolation.Remedy("Choose one.", "You"));
        }
        String src = blank(source) == null ? null : source.trim().toUpperCase();
        if (src != null && !SOURCES.contains(src)) {
            throw new DomainRuleViolation("PAR_SOURCE", "A source is one of " + SOURCES + ".", new DomainRuleViolation.Remedy("Choose one.", "You"));
        }
        java.time.LocalDate d1 = date(from), d2 = date(to), p1 = date(paidFrom), p2 = date(paidTo);
        String where = """
                 WHERE (CAST(:st AS text) IS NULL OR a.state = :st
                        OR (:st = 'OPEN' AND a.state IN ('ARCHIVED', 'UNDER_REVIEW', 'PENDING_BURSAR_APPROVAL', 'RETURNED')))
                   AND (CAST(:rc AS text) IS NULL OR a.reason_code = :rc)
                   AND (CAST(:ses AS text) IS NULL OR a.session = :ses)
                   AND (CAST(:sem AS int) IS NULL OR finance.purpose_semester(a.purpose) = :sem)
                   AND (CAST(:cat AS text) IS NULL OR finance.payment_category(a.purpose) = :cat)
                   AND (CAST(:ch AS text) IS NULL OR a.channel = :ch)
                   AND (CAST(:src AS text) IS NULL OR a.source = :src)
                   AND (CAST(:d1 AS date) IS NULL OR a.archived_at >= CAST(:d1 AS date))
                   AND (CAST(:d2 AS date) IS NULL OR a.archived_at < CAST(:d2 AS date) + 1)
                   AND (CAST(:p1 AS date) IS NULL OR a.payment_confirmed_at >= CAST(:p1 AS date))
                   AND (CAST(:p2 AS date) IS NULL OR a.payment_confirmed_at < CAST(:p2 AS date) + 1)
                   AND (CAST(:amt AS numeric) IS NULL OR a.amount = CAST(:amt AS numeric))
                   AND (CAST(:stu AS uuid) IS NULL OR a.student_id = CAST(:stu AS uuid) OR r.student_id = CAST(:stu AS uuid) OR a.owner_student_id = CAST(:stu AS uuid))
                   AND (CAST(:q AS text) IS NULL OR upper(a.archive_ref) = upper(:q) OR upper(a.reference) = upper(:q) OR upper(coalesce(a.receipt_no, '')) = upper(:q)
                        OR upper(coalesce(a.related_reference, '')) = upper(:q)
                        OR EXISTS (SELECT 1 FROM finance.legacy_payref k WHERE k.reference = a.reference AND upper(k.payref) = upper(:q))
                        OR EXISTS (SELECT 1 FROM finance.gateway_event e WHERE e.reference = a.reference AND upper(e.gateway_ref) = upper(:q))
                        OR EXISTS (SELECT 1 FROM finance.gateway_attempt g WHERE g.reference = a.reference AND upper(g.txn_ref) = upper(:q))
                        OR EXISTS (SELECT 1 FROM finance.payment_identity i WHERE i.payment_id = a.payment_id AND (upper(i.batch_ref) = upper(:q) OR upper(i.original_identifier) = upper(:q)))
                        OR upper(coalesce(s.matric_no, '')) = upper(:q) OR upper(coalesce(s.jamb_reg_no, '')) = upper(:q) OR upper(coalesce(s.admission_no, '')) = upper(:q)
                        OR upper(coalesce(cs.matric_no, '')) = upper(:q) OR upper(coalesce(cs.admission_no, '')) = upper(:q)
                        OR s.candidate_id IN (SELECT ap.candidate_id FROM admissions.application ap WHERE upper(ap.application_no) = upper(:q))
                        OR (length(:q) >= 4 AND ((s.surname || ' ' || s.other_names) ILIKE '%' || :q || '%' OR (cs.surname || ' ' || cs.other_names) ILIKE '%' || :q || '%')))
                """;
        String from_ = """
                  FROM finance.payment_archive a
                  JOIN finance.payment_archive_reason rs ON rs.code = a.reason_code
                  JOIN people.student s ON s.id = a.student_id
                  JOIN finance.payment_reference r ON r.id = a.payment_id
                  JOIN people.student cs ON cs.id = r.student_id
                  LEFT JOIN people.student os ON os.id = a.owner_student_id
                """;
        int size = all ? 20000 : PAGE;
        int pg = Math.max(0, page);
        List<Map<String, Object>> rows = bind(jdbc.sql("""
                SELECT a.id, a.archive_ref, a.reference, a.amount, a.purpose, finance.payment_category(a.purpose) AS category, finance.purpose_semester(a.purpose) AS semester,
                       a.session, a.channel, a.receipt_no, a.payment_confirmed_at, a.legacy, a.source, a.reason_code, rs.label AS reason, a.state, a.outcome,
                       a.related_reference, a.archived_at, helpdesk.person_name(a.archived_by) AS archived_by, a.archived_office, a.proposed_at,
                       helpdesk.person_name(a.proposed_by) AS proposed_by, a.decided_at, helpdesk.person_name(a.decided_by) AS decided_by, a.settled_at,
                       s.id AS student_id, coalesce(s.matric_no, s.admission_no) AS number, s.jamb_reg_no, s.surname || ', ' || s.other_names AS name,
                       cs.id AS current_student_id, coalesce(cs.matric_no, cs.admission_no) AS current_number,
                       coalesce(os.matric_no, os.admission_no) AS owner_number,
                       (SELECT k.payref FROM finance.legacy_payref k WHERE k.reference = a.reference ORDER BY k.recorded_at LIMIT 1) AS legacy_payref,
                       a.proposed_by = nullif(current_setting('moaum.actor_id', true), '')::uuid AS proposed_by_me,
                       count(*) OVER () AS total
                """ + from_ + where + " ORDER BY a.archived_at DESC, a.archive_ref DESC LIMIT :lim OFFSET :off"),
                st, blank(reason), blank(session), semester, blank(category), blank(channel), src, d1, d2, p1, p2, amount, student, blank(q))
                .param("lim", size).param("off", all ? 0 : pg * size).query().listOfRows();
        long total = rows.isEmpty() ? 0 : ((Number) rows.get(0).get("total")).longValue();
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("rows", rows);
        out.put("total", total);
        out.put("page", all ? 0 : pg);
        out.put("size", size);
        out.put("counts", jdbc.sql("SELECT state, count(*) AS n, coalesce(sum(amount), 0) AS amount FROM finance.payment_archive GROUP BY state ORDER BY state")
                .query().listOfRows());
        return out;
    }

    private static java.time.LocalDate date(String s) {
        if (blank(s) == null) return null;
        try {
            return java.time.LocalDate.parse(s.trim());
        } catch (java.time.format.DateTimeParseException bad) {
            throw new DomainRuleViolation("PAR_DATE", "A date is written 2026-10-27.", new DomainRuleViolation.Remedy("Choose the date again.", "You"));
        }
    }

    private static JdbcClient.StatementSpec bind(JdbcClient.StatementSpec q, String st, String reason, String session, Integer semester, String category,
                                                 String channel, String source, java.time.LocalDate d1, java.time.LocalDate d2, java.time.LocalDate p1,
                                                 java.time.LocalDate p2, BigDecimal amount, UUID student, String text) {
        return q.param("st", st, Types.VARCHAR).param("rc", reason == null ? null : reason.toUpperCase(), Types.VARCHAR).param("ses", session, Types.VARCHAR)
                .param("sem", semester, Types.INTEGER).param("cat", category, Types.VARCHAR).param("ch", channel, Types.VARCHAR).param("src", source, Types.VARCHAR)
                .param("d1", d1, Types.DATE).param("d2", d2, Types.DATE).param("p1", p1, Types.DATE).param("p2", p2, Types.DATE)
                .param("amt", amount, Types.NUMERIC).param("stu", student, Types.OTHER).param("q", text, Types.VARCHAR);
    }

    /** one student's archived payments, apart from the verified ones — those that stood on their account and those on it now */
    @GetMapping("/students/{id}/archives")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> ofStudent(@PathVariable UUID id) {
        return jdbc.sql("SELECT * FROM finance.payment_archives_of(:s)").param("s", id).query().listOfRows();
    }
}
