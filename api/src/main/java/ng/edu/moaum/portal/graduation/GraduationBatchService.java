package ng.edu.moaum.portal.graduation;

import java.sql.Types;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

import tools.jackson.databind.ObjectMapper;

import ng.edu.moaum.portal.shared.AuditContext;
import ng.edu.moaum.portal.shared.DomainRuleViolation;
import ng.edu.moaum.portal.shared.OfficeScope;

import org.springframework.dao.DataAccessException;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Service;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionTemplate;

/**
 * V602: graduation batches — the Academic Office confirms the awards of chosen students on the Senate's minute: a preview that writes
 * nothing (each student's verdict from the register, the cohort engine, the lifecycle completion check and the degree audit), a batch
 * GRAD/YYYY/NNNNNN with its rows, then the execution one student at a time, each all or nothing through {@code records.graduate_one}
 * (the list entry approved, the status changed with its history, final clearance started, the student told), never twice. Also the
 * Registrar's correction of an erroneous graduation, the management figures and the reports. Everything reads the pieces that already
 * exist; nothing here is a second graduation, status, clearance or statistics system.
 */
@Service
public class GraduationBatchService {

    /** the rule's code in a database refusal — GRAD_CARRY_OVER, never the driver's leading "ERROR" — and its words */
    private static final Pattern CODED = Pattern.compile("([A-Z][A-Z0-9]*_[A-Z0-9_]{2,60}): ([^\\n]+)");
    private static final ObjectMapper JSON = new ObjectMapper();
    static final int MAX_SELECTED = 5000;
    static final int STEP = 200;

    private final JdbcClient jdbc;
    private final GraduationService graduation;
    private final TransactionTemplate tx;

    public record Filter(String entry, String level, String status, String q, List<UUID> students) {
    }

    public record Verdict(UUID studentId, String number, String jambNo, String name, String programmeCode, String programme, String faculty,
                          String department, Integer level, Integer finalLevel, Integer durationYears, String entrySession, String status,
                          String verdict, String confidence, String reason, String completion, String spilloverState, String graduandState,
                          String recommendation, String reviewState) {
    }

    GraduationBatchService(JdbcClient jdbc, GraduationService graduation, PlatformTransactionManager transactions) {
        this.jdbc = jdbc;
        this.graduation = graduation;
        this.tx = new TransactionTemplate(transactions);
    }

    /** the students a filter names within the office's bound, names A–Z, at most {@link #MAX_SELECTED}; given ids are kept to the bound too */
    @Transactional(readOnly = true)
    public List<UUID> select(Filter f, OfficeScope.Bound b) {
        Integer level = f.level() == null || f.level().isBlank() ? null : Integer.valueOf(f.level().trim());
        String entry = blank(f.entry());
        String entryYear = entry != null && entry.matches("\\d{4}") ? entry : null;
        String entrySession = entry != null && entry.matches("\\d{4}/\\d{4}") ? entry : null;
        String q = blank(f.q());
        List<UUID> ids = f.students() == null || f.students().isEmpty() ? null : f.students();
        return jdbc.sql("""
                SELECT s.id
                  FROM people.student s
                  LEFT JOIN ref.programme p ON p.code = s.programme_code
                 WHERE s.duplicate_of IS NULL
                   AND (CAST(:ids AS uuid[]) IS NULL OR s.id = ANY (CAST(:ids AS uuid[])))
                   AND (CAST(:fac AS text) IS NULL OR p.faculty_code = :fac)
                   AND (CAST(:dept AS text) IS NULL OR p.dept_code = :dept)
                   AND (CAST(:prog AS text) IS NULL OR p.code = :prog)
                   AND (CAST(:level AS int) IS NULL OR s.current_level = :level)
                   AND (CAST(:status AS text) IS NULL OR s.status = :status)
                   AND (CAST(:entrySession AS text) IS NULL OR s.entry_session = :entrySession)
                   AND (CAST(:entryYear AS text) IS NULL OR left(s.entry_session, 4) = :entryYear
                        OR coalesce(s.matric_no, '') ~ ('/' || right(CAST(:entryYear AS text), 2) || '/'))
                   AND (CAST(:q AS text) IS NULL OR s.matric_no ILIKE '%' || :q || '%' OR s.admission_no ILIKE '%' || :q || '%'
                        OR s.jamb_reg_no ILIKE '%' || :q || '%' OR (s.surname || ' ' || s.other_names) ILIKE '%' || :q || '%'
                        OR (s.other_names || ' ' || s.surname) ILIKE '%' || :q || '%')
                 ORDER BY s.surname, s.other_names
                 LIMIT :limit
                """)
                .param("ids", ids == null ? null : ids.toArray(UUID[]::new), Types.ARRAY)
                .param("fac", b.fac(), Types.VARCHAR).param("dept", b.dept(), Types.VARCHAR).param("prog", b.prog(), Types.VARCHAR)
                .param("level", level, Types.INTEGER).param("status", blank(f.status()), Types.VARCHAR)
                .param("entrySession", entrySession, Types.VARCHAR).param("entryYear", entryYear, Types.VARCHAR).param("q", q, Types.VARCHAR)
                .param("limit", MAX_SELECTED)
                .query(UUID.class).list();
    }

    /** nothing written: each student's verdict for the session; the degree audit's judgement is added for the eligible (what the list would record as unmet) */
    @Transactional(readOnly = true)
    public List<Verdict> preview(String session, List<UUID> students) {
        if (students == null || students.isEmpty()) {
            return List.of();
        }
        if (students.size() > MAX_SELECTED) {
            throw new DomainRuleViolation("GRAD_BATCH_TOO_LARGE", "A graduation batch takes at most " + MAX_SELECTED + " students at a time.",
                    new DomainRuleViolation.Remedy("Narrow the filter — a programme, a level or a year of entry — and run the batch in parts.", "Academic Office"));
        }
        List<Verdict> out = new ArrayList<>();
        for (Map<String, Object> r : jdbc.sql("""
                SELECT s.id AS student_id, coalesce(s.matric_no, s.admission_no) AS number, s.jamb_reg_no, s.surname || ', ' || s.other_names AS name,
                       s.programme_code, p.name AS programme, f.name AS faculty, d.name AS department, s.current_level AS level,
                       v.final_level, p.duration_years, s.entry_session, v.status, v.verdict, v.confidence, v.reason, v.completion,
                       v.spillover_state, v.graduand_state, v.recommendation, v.review_state
                  FROM unnest(CAST(:ids AS uuid[])) WITH ORDINALITY AS x(id, ord)
                  JOIN people.student s ON s.id = x.id
                  LEFT JOIN ref.programme p ON p.code = s.programme_code
                  LEFT JOIN ref.department d ON d.code = p.dept_code
                  LEFT JOIN ref.faculty f ON f.code = p.faculty_code
                  CROSS JOIN LATERAL records.graduation_verdict(s.id, :session) v
                 ORDER BY x.ord
                """).param("ids", students.toArray(UUID[]::new), Types.ARRAY).param("session", session).query().listOfRows()) {
            String verdict = String.valueOf(r.get("verdict"));
            String reason = str(r.get("reason"));
            if ("ELIGIBLE".equals(verdict)) {
                // the degree audit: every registered course published, the CGPA threshold (or a postgraduate's required coursework)
                String unmet = graduation.judge((UUID) r.get("student_id"));
                if (unmet != null) {
                    verdict = "REQUIREMENT_UNMET";
                    reason = unmet;
                }
            }
            out.add(new Verdict((UUID) r.get("student_id"), str(r.get("number")), str(r.get("jamb_reg_no")), str(r.get("name")), str(r.get("programme_code")),
                    str(r.get("programme")), str(r.get("faculty")), str(r.get("department")), num(r.get("level")), num(r.get("final_level")),
                    num(r.get("duration_years")), str(r.get("entry_session")), str(r.get("status")), verdict, str(r.get("confidence")), reason,
                    str(r.get("completion")), str(r.get("spillover_state")), str(r.get("graduand_state")), str(r.get("recommendation")),
                    str(r.get("review_state"))));
        }
        return out;
    }

    /** the batch opened on the minute and the reason, its rows the preview's verdicts as they stand now; nothing graduated yet */
    @Transactional
    public Map<String, Object> open(String session, String minute, String reason, List<UUID> students, Map<String, Object> scope, AuditContext ctx) {
        List<Verdict> rows = preview(session, students);
        if (rows.isEmpty()) {
            throw new DomainRuleViolation("GRAD_BATCH_EMPTY", "No student was chosen for the batch.",
                    new DomainRuleViolation.Remedy("Choose the students, or a filter that names some.", "Academic Office"));
        }
        String ref;
        try {
            ref = jdbc.sql("SELECT records.open_graduation_batch(:s, :m, :r, CAST(:scope AS jsonb), :a, :o)")
                    .param("s", session).param("m", minute, Types.VARCHAR).param("r", reason, Types.VARCHAR)
                    .param("scope", json(scope == null ? Map.of() : scope)).param("a", ctx.actorId()).param("o", ctx.actorOffice())
                    .query(String.class).single();
        } catch (DataAccessException e) {
            throw coded(e, "GRAD_BATCH_REFUSED", "Academic Office");
        }
        UUID batchId = jdbc.sql("SELECT id FROM records.graduation_batch WHERE batch_ref = :r").param("r", ref).query(UUID.class).single();
        for (Verdict v : rows) {
            jdbc.sql("INSERT INTO records.graduation_batch_row (batch_id, student_id, verdict, confidence, reason) VALUES (:b, :s, :v, :c, :r)")
                    .param("b", batchId).param("s", v.studentId()).param("v", v.verdict()).param("c", v.confidence(), Types.VARCHAR)
                    .param("r", v.reason(), Types.VARCHAR).update();
        }
        jdbc.sql("SELECT records.graduation_batch_tally(:r)").param("r", ref).query().listOfRows();
        Map<String, Object> out = new LinkedHashMap<>(batch(ref));
        out.put("opened", true);
        return out;
    }

    /** one step of the execution: up to {@link #STEP} eligible students graduated, each in its own transaction; the rest wait for the next step */
    public Map<String, Object> execute(String ref, AuditContext ctx) {
        Map<String, Object> b = batchRow(ref);
        if (b.get("closed_at") != null) {
            throw new DomainRuleViolation("GRAD_BATCH_CLOSED", "The batch " + ref + " is closed.",
                    new DomainRuleViolation.Remedy("Open a new batch for any student still to be graduated.", "Academic Office"));
        }
        if (!ctx.actorId().equals(b.get("created_by"))) {
            throw new DomainRuleViolation("GRAD_BATCH_OWNER", "The batch " + ref + " is executed by the officer who opened it.",
                    new DomainRuleViolation.Remedy("Ask the officer who opened it, or open a batch of your own.", "Academic Office"));
        }
        String session = String.valueOf(b.get("session"));
        String minute = String.valueOf(b.get("senate_minute"));
        String reason = "Graduation batch " + ref + ": " + b.get("reason");
        UUID batchId = (UUID) b.get("id");
        List<UUID> todo = jdbc.sql("""
                SELECT r.student_id FROM records.graduation_batch_row r JOIN people.student s ON s.id = r.student_id
                 WHERE r.batch_id = :b AND r.verdict = 'ELIGIBLE' AND r.outcome IS NULL
                 ORDER BY s.surname, s.other_names LIMIT :n
                """).param("b", batchId).param("n", STEP).query(UUID.class).list();
        int graduated = 0;
        int skipped = 0;
        List<Map<String, Object>> refused = new ArrayList<>();
        for (UUID student : todo) {
            try {
                Map<String, Object> r = tx.execute(st -> {
                    graduation.placeOnList(student, session);   // the degree audit, as the graduation list records it
                    String j = jdbc.sql("SELECT records.graduate_one(:s, :sess, :m, :ref, :reason, :a, :o)::text")
                            .param("s", student).param("sess", session).param("m", minute).param("ref", ref).param("reason", reason)
                            .param("a", ctx.actorId()).param("o", ctx.actorOffice()).query(String.class).single();
                    Map<String, Object> done = parse(j);
                    String outcome = String.valueOf(done.get("outcome"));
                    jdbc.sql("""
                            UPDATE records.graduation_batch_row SET outcome = :out, graduand_id = CAST(:g AS uuid),
                                   graduated_at = CASE WHEN :out = 'GRADUATED' THEN now() ELSE graduated_at END,
                                   reason = CASE WHEN :out = 'GRADUATED' THEN 'Graduated' || coalesce('; final clearance ' || :clear, '') ELSE 'Already graduated' END
                             WHERE batch_id = :b AND student_id = :s
                            """).param("out", outcome).param("g", str(done.get("graduand_id")), Types.VARCHAR).param("clear", str(done.get("clearance")), Types.VARCHAR)
                            .param("b", batchId).param("s", student).update();
                    return done;
                });
                if ("GRADUATED".equals(String.valueOf(r.get("outcome")))) {
                    graduated++;
                } else {
                    skipped++;
                }
            } catch (DataAccessException | DomainRuleViolation e) {
                String m = e instanceof DomainRuleViolation d ? d.code() + ": " + d.getMessage()
                        : String.valueOf(((DataAccessException) e).getMostSpecificCause() == null ? e.getMessage() : ((DataAccessException) e).getMostSpecificCause().getMessage());
                Matcher c = CODED.matcher(m);
                boolean coded = c.find();
                String code = coded ? c.group(1) : "GRAD_REFUSED";
                String why = coded ? c.group(2).trim() : "Refused";
                tx.executeWithoutResult(st -> jdbc.sql("UPDATE records.graduation_batch_row SET outcome = 'REFUSED', reason = :r WHERE batch_id = :b AND student_id = :s")
                        .param("r", code + ": " + why).param("b", batchId).param("s", student).update());
                refused.add(Map.of("student", student, "code", code, "why", why));
            }
        }
        int remaining = tx.execute(st -> {
            jdbc.sql("SELECT records.graduation_batch_tally(:r)").param("r", ref).query().listOfRows();
            int left = jdbc.sql("SELECT count(*) FROM records.graduation_batch_row WHERE batch_id = :b AND verdict = 'ELIGIBLE' AND outcome IS NULL")
                    .param("b", batchId).query(Integer.class).single();
            if (left == 0) {
                jdbc.sql("UPDATE records.graduation_batch SET executed_at = coalesce(executed_at, now()) WHERE id = :b").param("b", batchId).update();
                // the Bursary and the Students Account Office told once the batch has done its work
                jdbc.sql("SELECT records.tell_graduation_clearance(:r)").param("r", ref).query(Integer.class).single();
            }
            return left;
        });
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("batchRef", ref);
        out.put("graduated", graduated);
        out.put("skipped", skipped);
        out.put("refused", refused);
        out.put("remaining", remaining);
        out.put("done", remaining == 0);
        out.put("batch", batch(ref));
        return out;
    }

    @Transactional
    public Map<String, Object> close(String ref, AuditContext ctx) {
        Map<String, Object> b = batchRow(ref);
        jdbc.sql("SELECT records.graduation_batch_tally(:r)").param("r", ref).query().listOfRows();
        jdbc.sql("UPDATE records.graduation_batch SET closed_at = coalesce(closed_at, now()), closed_by = coalesce(closed_by, :a) WHERE id = :b")
                .param("a", ctx.actorId()).param("b", b.get("id")).update();
        return batch(ref);
    }

    @Transactional(readOnly = true)
    public List<Map<String, Object>> batches(String session, OfficeScope.Bound b) {
        return jdbc.sql("""
                SELECT b.batch_ref, b.session, b.senate_minute, b.reason, b.scope::text AS scope, b.selected, b.eligible, b.graduated, b.rejected, b.review,
                       b.created_at, b.executed_at, b.closed_at, b.actor_office,
                       coalesce(p.surname || ', ' || p.given_names, b.created_by::text) AS created_by_name,
                       (SELECT count(*) FROM records.graduation_batch_row r WHERE r.batch_id = b.id AND r.verdict = 'ELIGIBLE' AND r.outcome IS NULL) AS waiting
                  FROM records.graduation_batch b
                  LEFT JOIN iam.person p ON p.id = b.created_by
                 WHERE (CAST(:s AS text) IS NULL OR b.session = :s)
                   AND (CAST(:fac AS text) IS NULL OR b.scope->>'fac' = :fac)
                   AND (CAST(:dept AS text) IS NULL OR b.scope->>'dept' = :dept)
                   AND (CAST(:prog AS text) IS NULL OR b.scope->>'prog' = :prog)
                 ORDER BY b.created_at DESC
                 LIMIT 200
                """).param("s", blank(session), Types.VARCHAR).param("fac", b.fac(), Types.VARCHAR).param("dept", b.dept(), Types.VARCHAR)
                .param("prog", b.prog(), Types.VARCHAR).query().listOfRows();
    }

    @Transactional(readOnly = true)
    public Map<String, Object> batch(String ref) {
        Map<String, Object> b = new LinkedHashMap<>(batchRow(ref));
        b.remove("created_by");
        b.put("rows", jdbc.sql("""
                SELECT r.student_id, coalesce(s.matric_no, s.admission_no) AS number, s.surname || ', ' || s.other_names AS name, p.name AS programme,
                       s.current_level AS level, s.status, r.verdict, r.confidence, r.reason, r.outcome, r.graduated_at, r.graduand_id
                  FROM records.graduation_batch_row r
                  JOIN people.student s ON s.id = r.student_id
                  LEFT JOIN ref.programme p ON p.code = s.programme_code
                 WHERE r.batch_id = :b
                 ORDER BY s.surname, s.other_names
                """).param("b", b.get("id")).query().listOfRows());
        return b;
    }

    /** the Registrar's correction of an erroneous graduation: the status back on the evidence, the impact recorded */
    @Transactional
    public Map<String, Object> correct(UUID student, String reason, String evidence, AuditContext ctx) {
        try {
            String j = jdbc.sql("SELECT records.correct_graduation(:s, :r, :e, :a, :o)::text")
                    .param("s", student).param("r", reason, Types.VARCHAR).param("e", evidence, Types.VARCHAR)
                    .param("a", ctx.actorId()).param("o", ctx.actorOffice()).query(String.class).single();
            return parse(j);
        } catch (DataAccessException e) {
            throw coded(e, "GRAD_CORRECTION_REFUSED", "Registrar");
        }
    }

    /** the figures Graduation Management opens on, within the office's bound */
    @Transactional(readOnly = true)
    public Map<String, Object> management(String session, OfficeScope.Bound b) {
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("session", session);
        out.put("figures", jdbc.sql("""
                WITH st AS (SELECT s.id, s.status FROM people.student s LEFT JOIN ref.programme p ON p.code = s.programme_code
                             WHERE s.duplicate_of IS NULL
                               AND (CAST(:fac AS text) IS NULL OR p.faculty_code = :fac) AND (CAST(:dept AS text) IS NULL OR p.dept_code = :dept)
                               AND (CAST(:prog AS text) IS NULL OR p.code = :prog)),
                     lr AS (SELECT r.recommendation, r.confidence, r.review_state FROM people.lifecycle_recommendation r JOIN st ON st.id = r.student_id),
                     lc AS (SELECT c.completion FROM people.lifecycle_completion c JOIN st ON st.id = c.student_id),
                     g AS (SELECT gr.* FROM records.graduand gr JOIN st ON st.id = gr.student_id WHERE gr.session = :s),
                     grad AS (SELECT gr.student_id FROM records.graduand gr JOIN st ON st.id = gr.student_id
                               WHERE gr.session = :s AND gr.senate_state = 'APPROVED' AND st.status = 'GRADUATED'),
                     cl AS (SELECT grad.student_id, q.completed_at FROM grad
                             LEFT JOIN LATERAL (SELECT q.completed_at FROM clearance.process q WHERE q.workflow = 'FINAL' AND q.student_id = grad.student_id
                                                  AND q.cancelled_at IS NULL ORDER BY q.started_at DESC LIMIT 1) q ON true)
                SELECT (SELECT count(*) FROM st) AS students,
                       (SELECT count(*) FROM st WHERE status IN ('ACTIVE', 'PROBATION')) AS in_study,
                       (SELECT count(*) FROM st WHERE status = 'GRADUATED') AS graduated_all,
                       (SELECT count(*) FROM grad) AS graduated_session,
                       (SELECT count(*) FROM lr WHERE recommendation = 'GRADUATION_CANDIDATE') AS candidates,
                       (SELECT count(*) FROM lr WHERE recommendation = 'GRADUATION_CANDIDATE' AND confidence = 'HIGH') AS candidates_high,
                       (SELECT count(*) FROM lr WHERE recommendation = 'GRADUATION_CANDIDATE' AND confidence = 'LOW') AS candidates_low,
                       (SELECT count(*) FROM lr WHERE recommendation = 'SPILLOVER_YEAR_1') AS sp1,
                       (SELECT count(*) FROM lr WHERE recommendation = 'SPILLOVER_YEAR_2') AS sp2,
                       (SELECT count(*) FROM lr WHERE recommendation = 'MAXIMUM_SPILLOVER_REACHED') AS maximum,
                       (SELECT count(*) FROM lr WHERE recommendation = 'REQUIRES_REVIEW') AS requires_review,
                       (SELECT count(*) FROM lr WHERE recommendation = 'DATA_INCOMPLETE') AS data_incomplete,
                       (SELECT count(*) FROM st WHERE status = 'DEFERRED') AS deferred,
                       (SELECT count(*) FROM lc WHERE completion = 'OUTSTANDING_COURSES') AS carry_over,
                       (SELECT count(*) FROM lc WHERE completion = 'AWAITING_RESULT') AS outstanding_result,
                       (SELECT count(*) FROM lc WHERE completion = 'COMPLETED') AS completed,
                       (SELECT count(*) FROM g WHERE senate_state = 'AWAITING' AND unmet IS NULL) AS listed_met,
                       (SELECT count(*) FROM g WHERE senate_state = 'AWAITING' AND unmet IS NOT NULL) AS listed_unmet,
                       (SELECT count(*) FROM g WHERE senate_state = 'APPROVED') AS approved,
                       (SELECT count(*) FROM g WHERE senate_state = 'REFERRED') AS referred,
                       (SELECT count(*) FROM cl WHERE completed_at IS NOT NULL) AS clearance_completed,
                       (SELECT count(*) FROM cl WHERE completed_at IS NULL) AS clearance_pending,
                       (SELECT max(checked_at) FROM people.lifecycle_completion) AS completion_checked_at,
                       (SELECT max(computed_at) FROM people.lifecycle_recommendation) AS recommendation_computed_at
                """).param("s", session).param("fac", b.fac(), Types.VARCHAR).param("dept", b.dept(), Types.VARCHAR).param("prog", b.prog(), Types.VARCHAR)
                .query().singleRow());
        out.put("batches", batches(session, b));
        return out;
    }

    /** graduates by faculty, department, programme, year of entry, matriculation year, graduation session or spillover state, within the bound */
    @Transactional(readOnly = true)
    public List<Map<String, Object>> report(String session, String by, OfficeScope.Bound b) {
        String key = switch (by == null ? "faculty" : by) {
            case "department" -> "coalesce(d.name, p.dept_code, '—')";
            case "programme" -> "coalesce(p.name, s.programme_code, '—')";
            case "entry" -> "coalesce(s.entry_session, '—')";
            case "matric" -> "coalesce(substring(s.matric_no from '/([0-9]{2})/[0-9]+$'), '—')";
            case "session" -> "g.session";
            case "spillover" -> "coalesce(g.spillover_state, 'NORMAL')";
            case "faculty" -> "coalesce(f.name, p.faculty_code, '—')";
            default -> throw new DomainRuleViolation("GRAD_REPORT_BY", "The report is by faculty, department, programme, entry, matric, session or spillover.",
                    new DomainRuleViolation.Remedy("Choose one of them.", "Academic Office"));
        };
        return jdbc.sql("""
                SELECT %s AS label,
                       count(*) AS graduated,
                       count(*) FILTER (WHERE g.spillover_state = 'SPILLOVER_YEAR_1') AS sp1,
                       count(*) FILTER (WHERE g.spillover_state = 'SPILLOVER_YEAR_2') AS sp2,
                       count(*) FILTER (WHERE coalesce(g.spillover_state, 'NORMAL') NOT LIKE 'SPILLOVER%%') AS normal,
                       count(*) FILTER (WHERE q.completed_at IS NOT NULL) AS cleared,
                       count(*) FILTER (WHERE q.id IS NOT NULL AND q.completed_at IS NULL) AS clearance_pending,
                       count(*) FILTER (WHERE q.id IS NULL) AS clearance_not_started,
                       count(*) FILTER (WHERE g.batch_ref IS NOT NULL) AS by_batch
                  FROM records.graduand g
                  JOIN people.student s ON s.id = g.student_id
                  LEFT JOIN ref.programme p ON p.code = s.programme_code
                  LEFT JOIN ref.department d ON d.code = p.dept_code
                  LEFT JOIN ref.faculty f ON f.code = p.faculty_code
                  LEFT JOIN LATERAL (SELECT q.id, q.completed_at FROM clearance.process q WHERE q.workflow = 'FINAL' AND q.student_id = s.id AND q.cancelled_at IS NULL
                                      ORDER BY q.started_at DESC LIMIT 1) q ON true
                 WHERE g.senate_state = 'APPROVED' AND s.status = 'GRADUATED'
                   AND (CAST(:s AS text) IS NULL OR g.session = :s)
                   AND (CAST(:fac AS text) IS NULL OR p.faculty_code = :fac) AND (CAST(:dept AS text) IS NULL OR p.dept_code = :dept)
                   AND (CAST(:prog AS text) IS NULL OR p.code = :prog)
                 GROUP BY 1
                 ORDER BY 1
                """.formatted(key)).param("s", blank(session), Types.VARCHAR).param("fac", b.fac(), Types.VARCHAR).param("dept", b.dept(), Types.VARCHAR)
                .param("prog", b.prog(), Types.VARCHAR).query().listOfRows();
    }

    /** one student's verdict for a session, as the preview would show it */
    @Transactional(readOnly = true)
    public Map<String, Object> verdict(UUID student, String session) {
        List<Verdict> v = preview(session, List.of(student));
        if (v.isEmpty()) {
            throw new DomainRuleViolation("GRAD_NO_STUDENT", "No such student.", new DomainRuleViolation.Remedy("Check the student.", "Academic Office"));
        }
        Map<String, Object> out = new LinkedHashMap<>();
        Verdict x = v.get(0);
        out.put("verdict", x);
        out.put("graduation", jdbc.sql("SELECT row_to_json(x)::text FROM records.student_graduation(:s) x").param("s", student).query(String.class).optional().map(this::parse).orElse(null));
        out.put("corrections", jdbc.sql("""
                SELECT c.id, c.reason, c.evidence, c.impact::text AS impact, c.previous_status, c.new_status, c.decided_at, c.actor_office, c.batch_ref
                  FROM records.graduation_correction c WHERE c.student_id = :s ORDER BY c.decided_at DESC
                """).param("s", student).query().listOfRows());
        return out;
    }

    private Map<String, Object> batchRow(String ref) {
        return jdbc.sql("""
                SELECT b.id, b.batch_ref, b.session, b.senate_minute, b.reason, b.scope::text AS scope, b.selected, b.eligible, b.graduated, b.rejected, b.review,
                       b.created_by, b.actor_office, b.created_at, b.executed_at, b.closed_at
                  FROM records.graduation_batch b WHERE b.batch_ref = :r
                """).param("r", ref).query().listOfRows().stream().findFirst()
                .orElseThrow(() -> new DomainRuleViolation("GRAD_BATCH_NOT_FOUND", "No graduation batch " + ref + ".",
                        new DomainRuleViolation.Remedy("Check the reference.", "Academic Office")));
    }

    private static DomainRuleViolation coded(DataAccessException e, String fallback, String office) {
        String m = String.valueOf(e.getMostSpecificCause() == null ? e.getMessage() : e.getMostSpecificCause().getMessage());
        Matcher c = CODED.matcher(m);
        boolean coded = c.find();
        return new DomainRuleViolation(coded ? c.group(1) : fallback, coded ? c.group(2).trim() : m,
                new DomainRuleViolation.Remedy("Read the reason and put the record right first.", office));
    }

    @SuppressWarnings("unchecked")
    private Map<String, Object> parse(String json) {
        return JSON.readValue(json, Map.class);
    }

    private static String json(Map<String, Object> m) {
        return JSON.writeValueAsString(m);
    }

    private static String blank(String v) {
        return v == null || v.isBlank() ? null : v.trim();
    }

    private static String str(Object o) {
        return o == null ? null : String.valueOf(o);
    }

    private static Integer num(Object o) {
        return o == null ? null : ((Number) o).intValue();
    }
}
