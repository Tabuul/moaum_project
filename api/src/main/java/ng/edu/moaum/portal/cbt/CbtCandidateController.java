package ng.edu.moaum.portal.cbt;

import java.sql.Types;
import java.time.OffsetDateTime;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

import ng.edu.moaum.portal.shared.AuditContext;
import ng.edu.moaum.portal.shared.AuditContextHolder;
import ng.edu.moaum.portal.shared.DomainRuleViolation;
import ng.edu.moaum.portal.shared.NotFound;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.Authentication;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * The candidate's door to the CBT engine (V322): the examinations on the signed-in student's registered courses, the
 * instructions, the start, the paper without its keys, the answers saved as they go, the browser's reports, the
 * submission, and the result once it is published. Every call is the student's own: the attempt must be theirs, and
 * the examination screen must hold the attempt's token — an examination URL is never the authorisation.
 */
@RestController
@RequestMapping("/api/v1/me/cbt")
@PreAuthorize("hasAuthority('OFFICE_student')")
class CbtCandidateController {

    private final JdbcClient jdbc;
    private final tools.jackson.databind.ObjectMapper mapper = new tools.jackson.databind.ObjectMapper();

    CbtCandidateController(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    public record AnswerIn(@NotNull UUID q, List<Integer> a) {
    }

    public record AnswersIn(@NotNull @Size(max = 500) List<@Valid AnswerIn> answers) {
    }

    public record EventIn(@NotBlank @Size(max = 40) String kind, @Size(max = 500) String detail) {
    }

    public record EventsIn(@NotNull @Size(max = 100) List<@Valid EventIn> events) {
    }

    private static UUID me(Authentication auth) {
        return UUID.fromString(auth.getName());
    }

    private static String ip() {
        return AuditContextHolder.current().map(AuditContext::sourceIp).orElse(null);
    }

    private static UUID token(String header) {
        try {
            if (header != null && !header.isBlank()) return UUID.fromString(header.trim());
        } catch (IllegalArgumentException ignored) {
            // fall through
        }
        throw new DomainRuleViolation("CBT_TOKEN_REQUIRED", "This examination screen does not hold the attempt.",
                new DomainRuleViolation.Remedy("Open the examination again from GST CBT Examinations.", "You"));
    }

    /** the attempt's examination, if the attempt is the signed-in student's */
    private UUID own(UUID attempt, UUID student) {
        return jdbc.sql("SELECT exam_id FROM assessment.cbt_attempt WHERE id = :a AND student_id = :s").param("a", attempt).param("s", student)
                .query(UUID.class).optional().orElseThrow(() -> new NotFound("attempt", attempt.toString()));
    }

    private String sessionFor(UUID student) {
        return jdbc.sql("""
                SELECT coalesce((SELECT cr.session FROM registration.course_registration cr WHERE cr.student_id = :s ORDER BY cr.session DESC LIMIT 1),
                                (SELECT name FROM policy.academic_session ORDER BY (state = 'CURRENT') DESC, (state = 'OPEN') DESC, name DESC LIMIT 1))
                """).param("s", student).query(String.class).optional().orElse(null);
    }

    /* ── the list and one examination ── */

    @GetMapping
    @Transactional(readOnly = true)
    Map<String, Object> list(Authentication auth, @RequestParam(required = false) String session) {
        UUID s = me(auth);
        String ses = session == null || session.isBlank() ? sessionFor(s) : session.trim();
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("session", ses);
        out.put("rows", jdbc.sql("SELECT * FROM assessment.cbt_student_exams(:s, :ses)").param("s", s).param("ses", ses, Types.VARCHAR).query().listOfRows());
        out.put("now", OffsetDateTime.now());
        return out;
    }

    @GetMapping("/exams/{id}")
    @Transactional(readOnly = true)
    Map<String, Object> one(Authentication auth, @PathVariable UUID id) {
        Map<String, Object> row = jdbc.sql("SELECT * FROM assessment.cbt_student_exams(:s, NULL) x WHERE x.exam_id = :e").param("s", me(auth)).param("e", id)
                .query().listOfRows().stream().findFirst().orElseThrow(() -> new NotFound("examination", id.toString()));
        Map<String, Object> out = new LinkedHashMap<>(row);
        out.put("now", OffsetDateTime.now());
        return out;
    }

    /* ── the attempt ── */

    /** start, or return to, the attempt: eligibility is the database's judgement; the token is the screen's key */
    @PostMapping("/exams/{id}/start")
    @Transactional
    Map<String, Object> start(Authentication auth, @PathVariable UUID id, @RequestHeader(value = "User-Agent", required = false) String agent) {
        UUID s = me(auth);
        // the examination must be one of the student's: a URL guessed for another course is not
        jdbc.sql("SELECT 1 FROM assessment.cbt_student_exams(:s, NULL) x WHERE x.exam_id = :e").param("s", s).param("e", id).query().listOfRows().stream().findFirst()
                .orElseThrow(() -> new NotFound("examination", id.toString()));
        Map<String, Object> a = jdbc.sql("SELECT * FROM assessment.cbt_start(:e, :s, :ip, :ua)")
                .param("e", id).param("s", s).param("ip", ip(), Types.VARCHAR).param("ua", agent == null ? null : agent.substring(0, Math.min(agent.length(), 300)), Types.VARCHAR)
                .query().singleRow();
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("attemptId", a.get("id"));
        out.put("token", a.get("token"));
        out.put("status", a.get("status"));
        out.put("endsAt", a.get("ends_at"));
        out.put("now", OffsetDateTime.now());
        return out;
    }

    /** the paper as the candidate sees it: the questions in this attempt's order, the options in its order, the answers so far — never a key */
    @GetMapping("/attempts/{id}")
    @Transactional
    Map<String, Object> attempt(Authentication auth, @PathVariable UUID id, @RequestHeader(value = "X-Attempt-Token", required = false) String token) {
        UUID s = me(auth);
        UUID exam = own(id, s);
        Map<String, Object> a = jdbc.sql("SELECT * FROM assessment.cbt_touch(:a, :t)").param("a", id).param("t", token(token)).query().singleRow();
        Map<String, Object> e = jdbc.sql("""
                SELECT e.id, e.reference, e.title, e.course_code, c.title AS course_title, e.session, e.semester, e.duration_minutes, e.randomize_options, e.security_mode, e.venue,
                       e.violation_limit, e.violation_action, e.instructions, assessment.cbt_live_state(e) AS live_state
                  FROM assessment.cbt_exam e JOIN catalogue.course c ON c.code = e.course_code WHERE e.id = :e
                """).param("e", exam).query().singleRow();
        Object[] idsObj = (Object[]) jdbcArray(a.get("question_ids"));
        UUID[] ids = new UUID[idsObj.length];
        for (int i = 0; i < idsObj.length; i++) ids[i] = idsObj[i] instanceof UUID u ? u : UUID.fromString(String.valueOf(idsObj[i]));
        List<Map<String, Object>> questions = jdbc.sql("""
                SELECT u.n, q.id, q.kind, q.stem, p.marks,
                       (SELECT jsonb_agg(jsonb_build_object('i', o.i - 1, 'text', o.t)
                                         ORDER BY CASE WHEN :rand THEN md5(:seed::text || q.id::text || o.i::text) ELSE lpad(o.i::text, 4, '0') END)
                          FROM jsonb_array_elements_text(q.options) WITH ORDINALITY o(t, i))::text AS options
                  FROM unnest(:ids::uuid[]) WITH ORDINALITY u(id, n)
                  JOIN assessment.question q ON q.id = u.id
                  JOIN assessment.cbt_pool(:e) p ON p.question_id = q.id
                 ORDER BY u.n
                """).param("rand", Boolean.TRUE.equals(e.get("randomize_options"))).param("seed", a.get("seed")).param("ids", ids).param("e", exam).query().listOfRows();
        for (Map<String, Object> q : questions) {
            // the options as a JSON array, never a database object; the key is not in the query at all
            q.put("options", mapper.readValue(String.valueOf(q.get("options")), new tools.jackson.core.type.TypeReference<List<Map<String, Object>>>() { }));
        }
        Map<String, Object> answers = new LinkedHashMap<>();
        for (Map<String, Object> r : jdbc.sql("SELECT question_id, chosen FROM assessment.cbt_answer WHERE attempt_id = :a").param("a", id).query().listOfRows()) {
            answers.put(String.valueOf(r.get("question_id")), jdbcArray(r.get("chosen")));
        }
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("attempt", attemptView(a));
        out.put("exam", e);
        out.put("questions", questions);
        out.put("answers", answers);
        out.put("now", OffsetDateTime.now());
        return out;
    }

    private static Object jdbcArray(Object v) {
        try {
            if (v instanceof java.sql.Array arr) return arr.getArray();
        } catch (java.sql.SQLException e) {
            throw new IllegalStateException(e);
        }
        return v;
    }

    private static Map<String, Object> attemptView(Map<String, Object> a) {
        Map<String, Object> v = new LinkedHashMap<>();
        v.put("id", a.get("id"));
        v.put("number", a.get("number"));
        v.put("status", a.get("status"));
        v.put("started_at", a.get("started_at"));
        v.put("ends_at", a.get("ends_at"));
        v.put("submitted_at", a.get("submitted_at"));
        v.put("answered", a.get("answered"));
        v.put("violations", a.get("violations"));
        v.put("max_marks", a.get("max_marks"));
        Object ids = jdbcArray(a.get("question_ids"));
        v.put("questions", ids instanceof Object[] arr ? arr.length : null);
        return v;
    }

    @PutMapping("/attempts/{id}/answers")
    @Transactional
    Map<String, Object> answers(Authentication auth, @PathVariable UUID id, @RequestHeader(value = "X-Attempt-Token", required = false) String token, @Valid @RequestBody AnswersIn in) {
        own(id, me(auth));
        List<Map<String, Object>> rows = in.answers().stream().map(x -> Map.<String, Object>of("q", x.q().toString(), "a", x.a() == null ? List.of() : x.a())).toList();
        Map<String, Object> a = jdbc.sql("SELECT * FROM assessment.cbt_save_answers(:a, :t, :j::jsonb)").param("a", id).param("t", token(token)).param("j", mapper.writeValueAsString(rows)).query().singleRow();
        return tick(a);
    }

    @PostMapping("/attempts/{id}/ping")
    @Transactional
    Map<String, Object> ping(Authentication auth, @PathVariable UUID id, @RequestHeader(value = "X-Attempt-Token", required = false) String token) {
        own(id, me(auth));
        return tick(jdbc.sql("SELECT * FROM assessment.cbt_touch(:a, :t)").param("a", id).param("t", token(token)).query().singleRow());
    }

    private static Map<String, Object> tick(Map<String, Object> a) {
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("status", a.get("status"));
        out.put("answered", a.get("answered"));
        out.put("violations", a.get("violations"));
        out.put("endsAt", a.get("ends_at"));
        out.put("submittedAt", a.get("submitted_at"));
        out.put("now", OffsetDateTime.now());
        return out;
    }

    /** what the browser saw: recorded, judged by the examination's policy, and the warning (or the end) returned */
    @PostMapping("/attempts/{id}/events")
    @Transactional
    Map<String, Object> events(Authentication auth, @PathVariable UUID id, @RequestHeader(value = "X-Attempt-Token", required = false) String token, @Valid @RequestBody EventsIn in) {
        own(id, me(auth));
        List<Map<String, Object>> rows = in.events().stream().map(x -> {
            Map<String, Object> m = new LinkedHashMap<>();
            m.put("kind", x.kind().trim().toUpperCase());
            m.put("detail", x.detail());
            return m;
        }).toList();
        String json = jdbc.sql("SELECT assessment.cbt_record_events(:a, :t, :j::jsonb, :ip)::text").param("a", id).param("t", token(token))
                .param("j", mapper.writeValueAsString(rows)).param("ip", ip(), Types.VARCHAR).query(String.class).single();
        return mapper.readValue(json, new tools.jackson.core.type.TypeReference<LinkedHashMap<String, Object>>() { });
    }

    @PostMapping("/attempts/{id}/submit")
    @Transactional
    Map<String, Object> submit(Authentication auth, @PathVariable UUID id, @RequestHeader(value = "X-Attempt-Token", required = false) String token) {
        own(id, me(auth));
        return tick(jdbc.sql("SELECT * FROM assessment.cbt_submit(:a, :t)").param("a", id).param("t", token(token)).query().singleRow());
    }

    /** the result — only once the office has published it */
    @GetMapping("/attempts/{id}/result")
    @Transactional(readOnly = true)
    Map<String, Object> result(Authentication auth, @PathVariable UUID id) {
        UUID exam = own(id, me(auth));
        Map<String, Object> r = jdbc.sql("""
                SELECT e.results_state, e.results_published_at, e.title, e.course_code, e.pass_mark, a.status, a.submitted_at, a.answered, cardinality(a.question_ids) AS questions,
                       a.score, a.max_marks, a.percentage, a.grade, a.passed, a.outcome
                  FROM assessment.cbt_attempt a JOIN assessment.cbt_exam e ON e.id = a.exam_id WHERE a.id = :a AND e.id = :e
                """).param("a", id).param("e", exam).query().singleRow();
        if (!"PUBLISHED".equals(r.get("results_state"))) {
            throw new DomainRuleViolation("CBT_RESULT_NOT_PUBLISHED", "The result of this examination is not yet published.",
                    new DomainRuleViolation.Remedy("The office reviews, approves and publishes the results; you are told when they are out.", "GST Office"));
        }
        return r;
    }
}
