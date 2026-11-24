package ng.edu.moaum.portal.summer;

import static ng.edu.moaum.portal.summer.SummerAccess.READERS;
import static ng.edu.moaum.portal.summer.SummerAccess.SETTERS;
import static ng.edu.moaum.portal.summer.SummerAccess.json;
import static ng.edu.moaum.portal.summer.SummerAccess.nz;

import java.nio.charset.StandardCharsets;
import java.sql.Types;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import jakarta.servlet.http.HttpServletRequest;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotEmpty;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

import ng.edu.moaum.portal.shared.DeadlockRetry;
import ng.edu.moaum.portal.shared.NotFound;
import ng.edu.moaum.portal.shared.OfficeScope;

import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.RowCallbackHandler;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionTemplate;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * V779 — the Academic Office verifies what the students selected. The queue of selections (filtered, paged, scoped to a Head of
 * Department's department or a Dean's faculty by the server), one selection in full (its evidence, its history, the student's other
 * selections), the decisions (confirm, not outstanding, reject, reopen — a batch of up to 200, each id its own subtransaction in the
 * database, one refusal never stopping the rest), a question to the student, the reconciliation against the results now on the
 * portal, and the export of the queue. Every rule is the database's (registration.summer_queue, summer_verify, summer_clarify,
 * summer_reconcile); this class holds the offices, the scope, the transaction and the file.
 */
@RestController
class SummerReviewController {

    /** the rows the queue is made of: selections with a live course charge, or with a decision (the queue's own rule) */
    private static final String UNIVERSE = """
            (x.state IN ('NOT_OUTSTANDING', 'REJECTED')
             OR EXISTS (SELECT 1 FROM registration.summer_charge ch WHERE ch.student_id = x.student_id AND ch.session = x.session
                           AND ch.kind = 'COURSE' AND ch.course_code = x.course_code AND ch.state IN ('DUE', 'PAID')))
            """;

    /** at most this many rows in an export */
    private static final int EXPORT_ROWS = 100_000;

    private final JdbcClient jdbc;
    private final OfficeScope scope;
    private final TransactionTemplate tx;

    SummerReviewController(JdbcClient jdbc, OfficeScope scope, PlatformTransactionManager transactions) {
        this.jdbc = jdbc;
        this.scope = scope;
        this.tx = new TransactionTemplate(transactions);
    }

    /** a decision on selections: the ids (the database refuses more than 200 at once), the decision, the reason the student is shown
     *  (ten characters for NOT_OUTSTANDING and REJECT) and a note for the staff. The database holds every rule: the decision,
     *  the size of the batch and the reason are its to refuse, with its own codes */
    public record Decide(@NotEmpty @Size(max = 5000) List<@NotNull UUID> ids, @NotBlank @Size(max = 30) String decision,
                         @Size(max = 600) String reason, @Size(max = 600) String note) {
    }

    /** a question to the student about a selection (the database holds it to 10 to 500 characters) */
    public record Clarify(@NotNull @Size(max = 2000) String note) {
    }

    public record Reconcile(String since, Integer limit) {
    }

    /** what the queue is asked: the unit the server holds the office to, and the filters */
    private record Query(OfficeScope.Bound b, Integer level, String state, String evidence, String flag, String basis, String paid, String q) {
    }

    private Query query(String faculty, String dept, String programme, Integer level, String state, String evidence, String flag, String basis, String paid, String q) {
        OfficeScope.Bound b = SummerAccess.readerBound(scope, faculty, dept, programme);
        String st = SummerAccess.up(state);
        return new Query(b, level, st == null ? "ANY" : st, SummerAccess.up(evidence), SummerAccess.up(flag), SummerAccess.up(basis), SummerAccess.up(paid), nz(q));
    }

    /** the state of the Summer credit a queue row's course fee became (OPEN, APPLIED or REFUNDED; NULL when none): a paid course the
     *  Academic Office found not outstanding or rejected has its charge cancelled by summer_verify and its money held as a DECISION
     *  credit keyed on that charge (source_charge_id), so the queue's charge_state is no longer PAID — read only for such a row */
    private static final String CREDIT_STATE = """
            CASE WHEN q.state IN ('NOT_OUTSTANDING', 'REJECTED') AND coalesce(q.charge_state, 'CANCELLED') NOT IN ('DUE', 'PAID') THEN
                 (SELECT cr.state FROM registration.summer_credit cr JOIN registration.summer_charge c ON c.id = cr.source_charge_id
                   WHERE cr.source = 'DECISION' AND c.kind = 'COURSE' AND c.student_id = q.student_id AND c.session = :s AND c.course_code = q.course_code
                   ORDER BY (cr.state = 'OPEN') DESC, (cr.state = 'APPLIED') DESC, cr.created_at DESC LIMIT 1) END""";

    private static final String QUEUE_ARGS = ":s, :fac, :dept, :prog, :level, :state, :evidence, :flag, :basis, :paid, :q";

    /**
     * The queue for the filters, a page at a time, each row summer_queue's with the credit_state of its course (CREDIT_STATE). Paid
     * (paid=PAID) is every course the student paid for: a live PAID charge, as summer_queue's own filter reads it, and a paid course a
     * decision took off whose money is a Summer credit (G1) — so the screen, "select all matching" and the CSV list the same rows. For
     * that filter summer_queue is read without its payment filter and the page, its order (the function's, by ordinality) and the total
     * are taken over the rows that remain; total is then paid_total, renamed by {@link #queue}. Every other filter is summer_queue's own.
     */
    private JdbcClient.StatementSpec queueSql(String s, Query f, int limit, int offset) {
        boolean paid = "PAID".equals(f.paid());
        String sql = paid
                ? "WITH q0 AS (SELECT q.*, " + CREDIT_STATE + " AS credit_state FROM registration.summer_queue(" + QUEUE_ARGS + ", " + Integer.MAX_VALUE
                  + ", 0) WITH ORDINALITY AS q) SELECT count(*) OVER () AS paid_total, q0.* FROM q0 WHERE q0.charge_state = 'PAID' OR q0.credit_state IS NOT NULL"
                  + " ORDER BY q0.ordinality LIMIT :limit OFFSET :offset"
                : "SELECT q.*, " + CREDIT_STATE + " AS credit_state FROM registration.summer_queue(" + QUEUE_ARGS + ", :limit, :offset) WITH ORDINALITY AS q"
                  + " ORDER BY q.ordinality";
        return jdbc.sql(sql)
                .param("s", s).param("fac", f.b().fac(), Types.VARCHAR).param("dept", f.b().dept(), Types.VARCHAR).param("prog", f.b().prog(), Types.VARCHAR)
                .param("level", f.level(), Types.INTEGER).param("state", f.state()).param("evidence", f.evidence(), Types.VARCHAR)
                .param("flag", f.flag(), Types.VARCHAR).param("basis", f.basis(), Types.VARCHAR).param("paid", paid ? null : f.paid(), Types.VARCHAR)
                .param("q", f.q(), Types.VARCHAR).param("limit", limit).param("offset", offset);
    }

    /** a page of the queue: every column summer_queue returns, under its own name — the money ones included (charge_amount,
     *  programme_fee_paid, courses_standing), from which the decision dialog previews what a decision holds as Summer credit — and
     *  credit_state, the state of the Summer credit a decided paid course's fee became (NULL when none) */
    private List<Map<String, Object>> queue(String s, Query f, int limit, int offset) {
        List<Map<String, Object>> rows = queueSql(s, f, limit, offset).query().listOfRows();
        for (Map<String, Object> r : rows) {
            r.remove("ordinality");
            Object paidTotal = r.remove("paid_total");
            if (paidTotal != null) r.put("total", paidTotal);
        }
        return rows;
    }

    private static Map<String, Object> filtersOf(Query f) {
        Map<String, Object> m = new LinkedHashMap<>();
        if (f.b().fac() != null) m.put("faculty", f.b().fac());
        if (f.b().dept() != null) m.put("dept", f.b().dept());
        if (f.b().prog() != null) m.put("programme", f.b().prog());
        if (f.level() != null) m.put("level", f.level());
        if (!"ANY".equals(f.state())) m.put("state", f.state());
        if (f.evidence() != null) m.put("evidence", f.evidence());
        if (f.flag() != null) m.put("flag", f.flag());
        if (f.basis() != null) m.put("basis", f.basis());
        if (f.paid() != null) m.put("paid", f.paid());
        if (f.q() != null) m.put("q", f.q());
        return m;
    }

    /* ── the queue ── */

    @GetMapping("/api/v1/summer/{session}/{year}/selections")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> selections(@PathVariable String session, @PathVariable String year,
                                   @RequestParam(required = false) String faculty, @RequestParam(required = false) String dept, @RequestParam(required = false) String programme,
                                   @RequestParam(required = false) Integer level, @RequestParam(required = false) String state, @RequestParam(required = false) String evidence,
                                   @RequestParam(required = false) String flag, @RequestParam(required = false) String basis, @RequestParam(required = false) String paid,
                                   @RequestParam(required = false) String q, @RequestParam(required = false) Integer page, @RequestParam(required = false) Integer size) {
        String s = session + "/" + year;
        Query f = query(faculty, dept, programme, level, state, evidence, flag, basis, paid, q);
        SummerAccess.noJit(jdbc);
        int n = SummerAccess.size(size, 50, 200);
        int p = SummerAccess.page(page);
        List<Map<String, Object>> rows = queue(s, f, n, p * n);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("session", s);
        out.put("total", rows.isEmpty() ? 0 : ((Number) rows.get(0).get("total")).longValue());
        out.put("page", p);
        out.put("size", n);
        out.put("rows", rows);
        out.put("facets", facets(s, f.b()));
        out.put("counts", counts(s, f.b()));
        return out;
    }

    /** the faculties, departments, programmes and Summer levels of the selections in the caller's scope (not narrowed by the filters) */
    private Map<String, Object> facets(String s, OfficeScope.Bound b) {
        List<Map<String, Object>> rows = jdbc.sql("""
                WITH sc AS (
                  SELECT DISTINCT x.student_id, p.code AS programme_code, p.name AS programme, d.code AS dept_code, d.name AS dept,
                                  f.code AS faculty_code, f.name AS faculty
                    FROM registration.summer_selection x
                    JOIN people.student st ON st.id = x.student_id
                    LEFT JOIN ref.programme p ON p.code = st.programme_code
                    LEFT JOIN ref.department d ON d.code = p.dept_code
                    LEFT JOIN ref.faculty f ON f.code = d.faculty_code
                   WHERE x.session = :s AND
                """ + UNIVERSE + """
                     AND (CAST(:fac AS text) IS NULL OR upper(f.code) = upper(:fac))
                     AND (CAST(:dept AS text) IS NULL OR upper(d.code) = upper(:dept))
                     AND (CAST(:prog AS text) IS NULL OR upper(p.code) = upper(:prog)))
                SELECT DISTINCT 'F' AS k, faculty_code AS code, faculty AS name FROM sc WHERE faculty_code IS NOT NULL
                UNION ALL SELECT DISTINCT 'D', dept_code, dept FROM sc WHERE dept_code IS NOT NULL
                UNION ALL SELECT DISTINCT 'P', programme_code, programme FROM sc WHERE programme_code IS NOT NULL
                UNION ALL SELECT DISTINCT 'L', registration.summer_level(student_id)::text, NULL::text FROM (SELECT DISTINCT student_id FROM sc) z
                ORDER BY 1, 3, 2
                """).param("s", s).param("fac", b.fac(), Types.VARCHAR).param("dept", b.dept(), Types.VARCHAR).param("prog", b.prog(), Types.VARCHAR)
                .query().listOfRows();
        List<Map<String, Object>> faculties = new ArrayList<>();
        List<Map<String, Object>> departments = new ArrayList<>();
        List<Map<String, Object>> programmes = new ArrayList<>();
        List<Integer> levels = new ArrayList<>();
        for (Map<String, Object> r : rows) {
            String k = String.valueOf(r.get("k"));
            if ("L".equals(k)) {
                if (r.get("code") != null) levels.add(Integer.valueOf(String.valueOf(r.get("code"))));
                continue;
            }
            Map<String, Object> item = new LinkedHashMap<>();
            item.put("code", r.get("code"));
            item.put("name", r.get("name"));
            ("F".equals(k) ? faculties : "D".equals(k) ? departments : programmes).add(item);
        }
        levels.sort(Integer::compare);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("faculties", faculties);
        out.put("departments", departments);
        out.put("programmes", programmes);
        out.put("levels", levels);
        return out;
    }

    /** the figures on the chips: the whole session within the caller's scope, whatever else is filtered */
    private Map<String, Object> counts(String s, OfficeScope.Bound b) {
        Map<String, Object> r = jdbc.sql("""
                SELECT count(*) FILTER (WHERE x.state = 'PENDING_VERIFICATION') AS pending_verification,
                       count(*) FILTER (WHERE x.state = 'CONFIRMED_OUTSTANDING') AS confirmed_outstanding,
                       count(*) FILTER (WHERE x.state = 'NOT_OUTSTANDING') AS not_outstanding,
                       count(*) FILTER (WHERE x.state = 'REJECTED') AS rejected,
                       count(*) FILTER (WHERE x.needs_review) AS review,
                       count(*) FILTER (WHERE x.clarification_open) AS clarification
                  FROM registration.summer_selection x
                  JOIN people.student st ON st.id = x.student_id
                  LEFT JOIN ref.programme p ON p.code = st.programme_code
                  LEFT JOIN ref.department d ON d.code = p.dept_code
                 WHERE x.session = :s AND
                """ + UNIVERSE + """
                   AND (CAST(:fac AS text) IS NULL OR upper(d.faculty_code) = upper(:fac))
                   AND (CAST(:dept AS text) IS NULL OR upper(d.code) = upper(:dept))
                   AND (CAST(:prog AS text) IS NULL OR upper(p.code) = upper(:prog))
                """).param("s", s).param("fac", b.fac(), Types.VARCHAR).param("dept", b.dept(), Types.VARCHAR).param("prog", b.prog(), Types.VARCHAR)
                .query().singleRow();
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("PENDING_VERIFICATION", num(r.get("pending_verification")));
        out.put("CONFIRMED_OUTSTANDING", num(r.get("confirmed_outstanding")));
        out.put("NOT_OUTSTANDING", num(r.get("not_outstanding")));
        out.put("REJECTED", num(r.get("rejected")));
        out.put("review", num(r.get("review")));
        out.put("clarification", num(r.get("clarification")));
        return out;
    }

    private static long num(Object o) {
        return o == null ? 0 : ((Number) o).longValue();
    }

    /** every id of the queue for the filters (the first 5,000, with the full count), for "select all matching" */
    @GetMapping("/api/v1/summer/{session}/{year}/selections/ids")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> ids(@PathVariable String session, @PathVariable String year,
                            @RequestParam(required = false) String faculty, @RequestParam(required = false) String dept, @RequestParam(required = false) String programme,
                            @RequestParam(required = false) Integer level, @RequestParam(required = false) String state, @RequestParam(required = false) String evidence,
                            @RequestParam(required = false) String flag, @RequestParam(required = false) String basis, @RequestParam(required = false) String paid,
                            @RequestParam(required = false) String q) {
        Query f = query(faculty, dept, programme, level, state, evidence, flag, basis, paid, q);
        if ("PAID".equals(f.paid())) {
            // Paid takes in a paid course a decision credited (queueSql), which summer_queue_ids's own payment filter leaves out
            SummerAccess.noJit(jdbc);
            List<Map<String, Object>> paidRows = queue(session + "/" + year, f, 5000, 0);
            Map<String, Object> out = new LinkedHashMap<>();
            out.put("ids", paidRows.stream().map(r -> r.get("selection_id")).toList());
            out.put("total", paidRows.isEmpty() ? 0 : ((Number) paidRows.get(0).get("total")).longValue());
            return out;
        }
        List<Map<String, Object>> rows = jdbc.sql("SELECT * FROM registration.summer_queue_ids(:s, :fac, :dept, :prog, :level, :state, :evidence, :flag, :basis, :paid, :q)")
                .param("s", session + "/" + year).param("fac", f.b().fac(), Types.VARCHAR).param("dept", f.b().dept(), Types.VARCHAR)
                .param("prog", f.b().prog(), Types.VARCHAR).param("level", f.level(), Types.INTEGER).param("state", f.state())
                .param("evidence", f.evidence(), Types.VARCHAR).param("flag", f.flag(), Types.VARCHAR).param("basis", f.basis(), Types.VARCHAR)
                .param("paid", f.paid(), Types.VARCHAR).param("q", f.q(), Types.VARCHAR).query().listOfRows();
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("ids", rows.stream().map(r -> r.get("selection_id")).toList());
        out.put("total", rows.isEmpty() ? 0 : ((Number) rows.get(0).get("total")).longValue());
        return out;
    }

    /* ── one selection in full ── */

    /** the selection, its student, the evidence on record for the course (and its twin), the history of what was done to it, the
     *  student's other selections of the Summer and the charge of the course; 404 outside the caller's scope. The selection carries
     *  the three money keys of a queue row (summer_queue's charge_amount, programme_fee_paid, courses_standing, with the same
     *  meaning), so the decision dialog opened from here previews what a decision holds exactly as it does from the queue: the
     *  course's own fee, and the programme fee as well when this is the student's last course standing (summer_verify) */
    @GetMapping("/api/v1/summer/{session}/{year}/selections/{id}")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> one(@PathVariable String session, @PathVariable String year, @PathVariable UUID id) {
        String s = session + "/" + year;
        OfficeScope.Bound b = SummerAccess.readerBound(scope);
        SummerAccess.noJit(jdbc);
        List<Map<String, Object>> found = jdbc.sql("""
                SELECT x.id AS selection_id, x.student_id, coalesce(st.matric_no, st.admission_no) AS matric_no, st.surname || ', ' || st.other_names AS name,
                       p.name AS programme, p.code AS programme_code, d.code AS dept_code, d.name AS department, d.faculty_code, f.name AS faculty,
                       st.current_level AS level, registration.summer_level(st.id) AS summer_level, cand.category,
                       x.course_code, k.title, x.units, k.semester AS course_semester, x.original_session, x.original_semester, x.original_source,
                       x.basis, x.state, x.verified_via, x.decision_reason, ev.evidence, ev.evidence_at, x.needs_review, x.review_flag,
                       x.clarification_open, x.clarification_note, x.student_note, ch.state AS charge_state,
                       EXISTS (SELECT 1 FROM registration.course_registration r
                                 JOIN registration.entry e ON e.registration_id = r.id AND e.status NOT IN ('DROPPED', 'WITHDRAWN')
                                 JOIN catalogue.offering o ON o.id = e.offering_id
                                WHERE r.student_id = x.student_id AND r.session = x.session AND r.semester = 3 AND o.course_code = x.course_code) AS entry_live,
                       x.created_at AS selected_at, x.decided_office, x.decided_at, x.removal_ref,
                       CASE WHEN ch.state IN ('DUE', 'PAID') THEN ch.amount END AS charge_amount,
                       (SELECT pc.amount FROM registration.summer_charge pc
                         WHERE pc.student_id = x.student_id AND pc.session = x.session AND pc.kind = 'PROGRAMME' AND pc.state = 'PAID') AS programme_fee_paid,
                       (SELECT count(*)::int FROM registration.summer_selection o
                         WHERE o.student_id = x.student_id AND o.session = x.session
                           AND EXISTS (SELECT 1 FROM registration.summer_charge oc
                                        WHERE oc.student_id = o.student_id AND oc.session = o.session AND oc.kind = 'COURSE'
                                          AND oc.course_code = o.course_code AND oc.state IN ('DUE', 'PAID'))) AS courses_standing
                  FROM registration.summer_selection x
                  JOIN people.student st ON st.id = x.student_id
                  JOIN catalogue.course k ON k.code = x.course_code
                  LEFT JOIN ref.programme p ON p.code = st.programme_code
                  LEFT JOIN ref.department d ON d.code = p.dept_code
                  LEFT JOIN ref.faculty f ON f.code = d.faculty_code
                  LEFT JOIN registration.summer_candidate cand ON cand.session = x.session AND cand.student_id = x.student_id
                  LEFT JOIN registration.summer_selection_evidence ev ON ev.selection_id = x.id
                  LEFT JOIN LATERAL (SELECT c.state, c.amount, c.paid_reference_id FROM registration.summer_charge c
                                      WHERE c.student_id = x.student_id AND c.session = x.session AND c.kind = 'COURSE' AND c.course_code = x.course_code
                                      ORDER BY (c.state <> 'CANCELLED') DESC, c.created_at DESC LIMIT 1) ch ON true
                 WHERE x.id = :id AND x.session = :s
                   AND (CAST(:fac AS text) IS NULL OR upper(d.faculty_code) = upper(:fac))
                   AND (CAST(:dept AS text) IS NULL OR upper(d.code) = upper(:dept))
                   AND (CAST(:prog AS text) IS NULL OR upper(p.code) = upper(:prog))
                """).param("id", id).param("s", s).param("fac", b.fac(), Types.VARCHAR).param("dept", b.dept(), Types.VARCHAR).param("prog", b.prog(), Types.VARCHAR)
                .query().listOfRows();
        if (found.isEmpty()) {
            throw new NotFound("Summer selection", id);
        }
        Map<String, Object> row = found.get(0);
        UUID student = (UUID) row.get("student_id");
        String course = String.valueOf(row.get("course_code"));
        Map<String, Object> studentOut = new LinkedHashMap<>();
        studentOut.put("id", student);
        studentOut.put("number", row.get("matric_no"));
        studentOut.put("name", row.get("name"));
        studentOut.put("programme", row.get("programme"));
        studentOut.put("department", row.get("department"));
        studentOut.put("faculty", row.get("faculty"));
        studentOut.put("level", row.get("level"));
        studentOut.put("summerLevel", row.get("summer_level"));
        studentOut.put("category", row.get("category"));
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("selection", row);
        out.put("student", studentOut);
        out.put("evidenceRows", jdbc.sql("""
                SELECT r.course_code, r.session, r.semester, r.outcome, r.points
                  FROM assessment.student_results(:st) r
                 WHERE r.published
                   AND (r.course_code = :c
                        OR r.course_code IN (SELECT CASE WHEN t.bsu_code = :c THEN t.moau_code ELSE t.bsu_code END
                                               FROM catalogue.course_twin t WHERE t.unlinked_at IS NULL AND :c IN (t.bsu_code, t.moau_code)))
                 ORDER BY r.session, r.semester, r.course_code
                """).param("st", student).param("c", course).query().listOfRows());
        out.put("history", jdbc.sql("""
                SELECT h.id, h.batch_ref, h.action, h.from_state, h.to_state, h.via, h.evidence, h.reason, h.note, h.money_effect, h.credit_amount,
                       h.removal_ref, h.actor_office, h.at,
                       CASE WHEN h.actor_id IS NULL THEN 'System'
                            ELSE coalesce((SELECT trim(coalesce(p.given_names, '') || ' ' || p.surname) FROM iam.person p WHERE p.id = h.actor_id),
                                          (SELECT s2.surname || ', ' || s2.other_names FROM people.student s2 WHERE s2.id = h.actor_id)) END AS actor_name
                  FROM registration.summer_selection_review h WHERE h.selection_id = :id ORDER BY h.at, h.id
                """).param("id", id).query().listOfRows());
        out.put("others", jdbc.sql("""
                SELECT o.id AS selection_id, o.course_code, k.title, o.units, o.basis, o.state, ev.evidence, o.needs_review
                  FROM registration.summer_selection o JOIN catalogue.course k ON k.code = o.course_code
                  LEFT JOIN registration.summer_selection_evidence ev ON ev.selection_id = o.id
                 WHERE o.student_id = :st AND o.session = :s AND o.id <> :id ORDER BY o.course_code
                """).param("st", student).param("s", s).param("id", id).query().listOfRows());
        Map<String, Object> charge = new LinkedHashMap<>();
        List<Map<String, Object>> c = jdbc.sql("""
                SELECT c.state, c.amount, pr.reference, pr.receipt_no
                  FROM registration.summer_charge c LEFT JOIN finance.payment_reference pr ON pr.id = c.paid_reference_id
                 WHERE c.student_id = :st AND c.session = :s AND c.kind = 'COURSE' AND c.course_code = :c
                 ORDER BY (c.state <> 'CANCELLED') DESC, c.created_at DESC LIMIT 1
                """).param("st", student).param("s", s).param("c", course).query().listOfRows();
        charge.put("state", c.isEmpty() ? null : c.get(0).get("state"));
        charge.put("amount", c.isEmpty() ? null : c.get(0).get("amount"));
        charge.put("paidReference", c.isEmpty() ? null : c.get(0).get("reference"));
        charge.put("receiptNo", c.isEmpty() ? null : c.get(0).get("receipt_no"));
        out.put("charge", charge);
        return out;
    }

    /* ── the decisions ── */

    /** confirm, not outstanding, reject or reopen up to 200 selections at once; the answer is the database's (the batch, what was
     *  decided and left as it was, the money credited, the entries withdrawn, and each id it refused with its code and message): 200
     *  even when some ids were refused. Run again in a fresh transaction on a passing clash with a late payment (DeadlockRetry) */
    @PostMapping("/api/v1/summer/{session}/{year}/selections/decide")
    @PreAuthorize(SETTERS)
    Map<String, Object> decide(@PathVariable String session, @PathVariable String year, @Valid @RequestBody Decide body) {
        String[] ids = body.ids().stream().map(UUID::toString).toArray(String[]::new);
        String decision = body.decision().trim().toUpperCase();
        String reason = body.reason() == null ? null : body.reason().trim();
        String note = body.note() == null || body.note().isBlank() ? null : body.note().trim();
        return DeadlockRetry.inTransaction(tx, () -> json(jdbc.sql("SELECT registration.summer_verify(CAST(:ids AS uuid[]), :d, :r, :n)::text")
                .param("ids", ids, Types.ARRAY).param("d", decision).param("r", reason, Types.VARCHAR).param("n", note, Types.VARCHAR)
                .query(String.class).single()));
    }

    /** a question to the student about one selection (they answer on the page with a note; the state does not change) */
    @PostMapping("/api/v1/summer/{session}/{year}/selections/{id}/clarify")
    @PreAuthorize(SETTERS)
    @Transactional
    Map<String, Object> clarify(@PathVariable String session, @PathVariable String year, @PathVariable UUID id, @Valid @RequestBody Clarify body) {
        jdbc.sql("SELECT registration.summer_clarify(:id, :n)").param("id", id).param("n", body.note().trim()).query().listOfRows();
        return Map.of("ok", true);
    }

    /** one tranche of the reconciliation of the selections against the results now on the portal (a pass taken back or flagged, a
     *  failure confirmed, a result rolled back): the desk asks again until `left` is 0; `since` is taken once, on the first call, and
     *  sent back. Run again in a fresh transaction on a passing clash */
    @PostMapping("/api/v1/summer/{session}/{year}/reconcile")
    @PreAuthorize(SETTERS)
    Map<String, Object> reconcile(@PathVariable String session, @PathVariable String year, @RequestBody(required = false) Reconcile body) {
        String s = session + "/" + year;
        String since = body == null || body.since() == null || body.since().isBlank() ? null : body.since();
        int limit = body == null || body.limit() == null ? 400 : Math.max(1, Math.min(body.limit(), 2000));
        return DeadlockRetry.inTransaction(tx, () -> {
            String started = since != null ? since : jdbc.sql("SELECT now()::text").query(String.class).single();
            String r = jdbc.sql("SELECT registration.summer_reconcile(:s, CAST(:since AS timestamptz), :l)::text")
                    .param("s", s).param("since", started).param("l", limit).query(String.class).single();
            Map<String, Object> out = new LinkedHashMap<>(json(r));
            out.put("since", started);
            return out;
        });
    }

    /* ── the export ── */

    private static final Map<String, String> VERIFICATION = Map.of(
            "PENDING_VERIFICATION", "Student selected – pending verification",
            "CONFIRMED_OUTSTANDING", "Academically confirmed outstanding",
            "NOT_OUTSTANDING", "Not outstanding – result verified",
            "REJECTED", "Rejected – incorrect course selection");
    private static final Map<String, String> EVIDENCE = Map.of(
            "RESULT_FAILED", "Confirmed by results (failed)",
            "RESULT_PASSED", "Result on record: passed",
            "RESULT_AWAITED", "Result awaited",
            "NO_RESULT", "No result on record");
    private static final Map<String, String> BASIS = Map.of(
            "CARRY_OVER", "Carry-over",
            "AUTHORISED", "Authorised course",
            "STUDENT_SELECTED", "Student-selected course");

    /** the queue for the filters as a spreadsheet's CSV (at most 100,000 rows), recorded on the export log in the same transaction
     *  as every report handed out is; a text cell that begins like a formula is made plain */
    @GetMapping("/api/v1/summer/{session}/{year}/selections/export")
    @PreAuthorize(READERS)
    @Transactional
    ResponseEntity<byte[]> export(@PathVariable String session, @PathVariable String year, HttpServletRequest request,
                                  @RequestParam(required = false) String faculty, @RequestParam(required = false) String dept, @RequestParam(required = false) String programme,
                                  @RequestParam(required = false) Integer level, @RequestParam(required = false) String state, @RequestParam(required = false) String evidence,
                                  @RequestParam(required = false) String flag, @RequestParam(required = false) String basis, @RequestParam(required = false) String paid,
                                  @RequestParam(required = false) String q) {
        String s = session + "/" + year;
        Query f = query(faculty, dept, programme, level, state, evidence, flag, basis, paid, q);
        SummerAccess.noJit(jdbc);
        Map<String, String> faculties = names("ref.faculty");
        Map<String, String> departments = names("ref.department");
        SummerAccess.Csv csv = new SummerAccess.Csv("Matriculation number", "Name", "Faculty", "Department", "Programme", "Level", "Category", "Course", "Title",
                "Units", "Course semester", "Original session", "Original semester", "Registration category", "Verification status", "Verified by",
                "Result evidence", "Needs review", "Clarification", "Payment", "Reason", "Decided on");
        queueSql(s, f, EXPORT_ROWS, 0)
                .query((RowCallbackHandler) rs -> {
                    String note = rs.getString("clarification_note");
                    csv.row(rs.getString("matric_no"), rs.getString("name"), faculties.get(rs.getString("faculty_code")), departments.get(rs.getString("dept_code")),
                            rs.getString("programme"), rs.getObject("level"), rs.getString("category"), rs.getString("course_code"), rs.getString("title"),
                            rs.getObject("units"), rs.getObject("course_semester"), rs.getString("original_session"), rs.getObject("original_semester"),
                            BASIS.getOrDefault(rs.getString("basis"), rs.getString("basis")),
                            VERIFICATION.getOrDefault(rs.getString("state"), rs.getString("state")),
                            SummerAccess.verifiedByWord(rs.getString("verified_via")),
                            EVIDENCE.getOrDefault(rs.getString("evidence"), rs.getString("evidence")),
                            rs.getBoolean("needs_review") ? "Yes" + (rs.getString("review_flag") == null ? "" : ": " + rs.getString("review_flag")) : "No",
                            rs.getBoolean("clarification_open") ? "Asked" + (note == null ? "" : ": " + note) : "No",
                            SummerAccess.paymentWord(rs.getString("charge_state"), rs.getBoolean("entry_live"), rs.getString("credit_state")),
                            rs.getString("decision_reason"), rs.getObject("decided_at"));
                });
        jdbc.sql("SELECT platform.log_export(:r, 'CSV', :n, CAST(:f AS jsonb), :s, NULL)")
                .param("r", "Summer selections").param("n", csv.rows())
                .param("f", SummerAccess.JSON.writeValueAsString(withSession(filtersOf(f), s))).param("s", request.getRequestURI())
                .query(Object.class).single();
        return ResponseEntity.ok().contentType(new MediaType("text", "csv", StandardCharsets.UTF_8))
                .header(HttpHeaders.CONTENT_DISPOSITION, "attachment; filename=\"summer-" + SummerAccess.fileSession(s) + "-selections.csv\"")
                .header("Cache-Control", "no-store").body(csv.bytes());
    }

    private static Map<String, Object> withSession(Map<String, Object> filters, String s) {
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("session", s);
        m.putAll(filters);
        return m;
    }

    /** a register's codes and names, for the words of a CSV */
    private Map<String, String> names(String table) {
        Map<String, String> m = new java.util.HashMap<>();
        jdbc.sql("SELECT code, name FROM " + table).query((RowCallbackHandler) rs -> m.put(rs.getString("code"), rs.getString("name")));
        return m;
    }
}
