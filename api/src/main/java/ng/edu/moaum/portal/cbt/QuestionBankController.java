package ng.edu.moaum.portal.cbt;

import java.sql.Types;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
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
import org.springframework.security.access.AccessDeniedException;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * The CBT question bank (V077, extended by V322): authoring and blueprints per course, in three kinds — one correct
 * option, true/false, several correct options — with an explanation for the marker and the author on record. The
 * GST and EPS offices author in their own courses; a lecturer, Head of Department or Examinations Officer in any.
 * A question is retired, not deleted, so a paper that used it can still be explained.
 */
@RestController
class QuestionBankController {

    private static final String READERS = "hasAnyAuthority('OFFICE_lecturer','OFFICE_hod','OFFICE_exams','OFFICE_facultyexams','OFFICE_dean','OFFICE_academic',"
            + "'OFFICE_registrar','OFFICE_dregistrar','OFFICE_gst','OFFICE_eps','OFFICE_ict','OFFICE_admin','OFFICE_super')";
    private static final String AUTHORS = "hasAnyAuthority('OFFICE_lecturer','OFFICE_hod','OFFICE_exams','OFFICE_dean','OFFICE_gst','OFFICE_eps','OFFICE_super')";
    private static final Set<String> KINDS = Set.of("MCQ", "TRUE_FALSE", "MULTI");

    private final JdbcClient jdbc;
    private final tools.jackson.databind.ObjectMapper mapper = new tools.jackson.databind.ObjectMapper();

    QuestionBankController(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    public record Question(@NotBlank @Size(max = 10) String course, @Size(max = 120) String topic, @NotBlank @Size(max = 4000) String stem,
                           @NotNull List<@Size(max = 500) String> options, Integer answer, List<Integer> answers, @Size(max = 12) String kind,
                           @Size(max = 10) String difficulty, Integer marks, @Size(max = 2000) String explanation) {
    }

    public record QuestionEdit(@Size(max = 120) String topic, @NotBlank @Size(max = 4000) String stem, @NotNull List<@Size(max = 500) String> options,
                               Integer answer, List<Integer> answers, @Size(max = 12) String kind, @Size(max = 10) String difficulty, Integer marks,
                               @Size(max = 2000) String explanation) {
    }

    public record Active(boolean active) {
    }

    /** the GST and EPS offices see and author only their own courses; everyone else, every course */
    private static String actingOffice() {
        String acting = AuditContextHolder.current().map(AuditContext::actorOffice).orElse("");
        return "gst".equals(acting) ? "GST" : "eps".equals(acting) ? "EPS" : null;
    }

    private void scoped(String course) {
        String o = actingOffice();
        if (o == null) return;
        String owner = jdbc.sql("SELECT general_office FROM catalogue.course WHERE code = :c").param("c", course).query(String.class).optional()
                .orElseThrow(() -> new NotFound("course", course));
        if (!o.equals(owner)) throw new AccessDeniedException("The " + o + " office works in its own courses' banks; " + course + " is not one of them.");
    }

    @GetMapping("/api/v1/cbt/courses")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> courses(@RequestParam(required = false) String office) {
        String o = actingOffice() != null ? actingOffice() : office == null || office.isBlank() ? null : office.trim().toUpperCase();
        return jdbc.sql("""
                SELECT c.code, c.title, c.kind, c.general_office, c.level, c.semester, c.units, c.state,
                       (SELECT count(*) FROM assessment.question q WHERE q.course_code = c.code AND q.active) AS questions,
                       (SELECT count(*) FROM assessment.question q WHERE q.course_code = c.code) AS total
                  FROM catalogue.course c
                 WHERE (:o::text IS NULL OR (c.kind = 'GST' AND coalesce(c.general_office, 'GST') = :o))
                 ORDER BY c.code
                """).param("o", o, Types.VARCHAR).query().listOfRows();
    }

    @GetMapping("/api/v1/cbt/questions")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> questions(@RequestParam String course) {
        scoped(course);
        List<Map<String, Object>> rows = jdbc.sql("""
                SELECT q.id, q.course_code, q.topic, q.stem, q.options::text AS options, q.answer, to_jsonb(q.answers)::text AS answers, q.kind, q.difficulty, q.marks, q.active,
                       q.explanation, q.authored_at, q.updated_at,
                       CASE WHEN p.id IS NULL THEN NULL ELSE p.surname || ', ' || p.given_names END AS authored_by,
                       (SELECT count(*) FROM assessment.cbt_exam_question eq WHERE eq.question_id = q.id) AS on_papers
                  FROM assessment.question q LEFT JOIN iam.person p ON p.id = q.authored_by
                 WHERE q.course_code = :c ORDER BY q.topic NULLS FIRST, q.authored_at DESC
                """).param("c", course).query().listOfRows();
        for (Map<String, Object> r : rows) {
            // JSON arrays for the screen, not database objects
            r.put("options", mapper.readValue(String.valueOf(r.get("options")), new tools.jackson.core.type.TypeReference<List<String>>() { }));
            r.put("answers", r.get("answers") == null ? List.of() : mapper.readValue(String.valueOf(r.get("answers")), new tools.jackson.core.type.TypeReference<List<Integer>>() { }));
        }
        List<Map<String, Object>> blueprint = jdbc.sql("""
                SELECT coalesce(topic, 'Untitled topic') AS topic,
                       count(*) FILTER (WHERE difficulty = 'EASY' AND active) AS easy,
                       count(*) FILTER (WHERE difficulty = 'MEDIUM' AND active) AS medium,
                       count(*) FILTER (WHERE difficulty = 'HARD' AND active) AS hard,
                       count(*) FILTER (WHERE active) AS total,
                       coalesce(sum(marks) FILTER (WHERE active), 0) AS marks
                  FROM assessment.question WHERE course_code = :c GROUP BY topic ORDER BY topic NULLS FIRST
                """).param("c", course).query().listOfRows();
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("rows", rows);
        out.put("blueprint", blueprint);
        return out;
    }

    private record Checked(String kind, List<String> options, int answer, List<Integer> answers) {
    }

    private static Checked check(String kindIn, List<String> optionsIn, Integer answer, List<Integer> answers) {
        String kind = kindIn == null || kindIn.isBlank() ? "MCQ" : kindIn.trim().toUpperCase();
        if (!KINDS.contains(kind)) {
            throw new DomainRuleViolation("CBT_KIND", "A question is MCQ, TRUE_FALSE or MULTI.", new DomainRuleViolation.Remedy("Choose one of the three kinds.", "You"));
        }
        List<String> options = optionsIn.stream().map(o -> o == null ? "" : o.trim()).filter(o -> !o.isEmpty()).toList();
        if ("TRUE_FALSE".equals(kind) && options.isEmpty()) options = List.of("True", "False");
        if (options.size() < 2) {
            throw new DomainRuleViolation("CBT_OPTIONS", "A question needs at least two options.", new DomainRuleViolation.Remedy("Add the options a candidate chooses between.", "You"));
        }
        if ("TRUE_FALSE".equals(kind) && options.size() != 2) {
            throw new DomainRuleViolation("CBT_TRUE_FALSE_OPTIONS", "A true/false question has exactly two options.", new DomainRuleViolation.Remedy("Keep True and False.", "You"));
        }
        List<Integer> key;
        if ("MULTI".equals(kind)) {
            key = answers == null ? List.of() : answers.stream().filter(x -> x != null).distinct().sorted().toList();
            if (key.isEmpty()) throw new DomainRuleViolation("CBT_KEY_REQUIRED", "A multiple-select question names at least one correct option.", new DomainRuleViolation.Remedy("Tick every correct option.", "You"));
        } else {
            Integer a = answer != null ? answer : answers != null && !answers.isEmpty() ? answers.get(0) : null;
            if (a == null) throw new DomainRuleViolation("CBT_KEY_REQUIRED", "Point to the correct option.", new DomainRuleViolation.Remedy("Select the radio beside the correct option.", "You"));
            key = List.of(a);
        }
        for (Integer k : key) {
            if (k < 0 || k >= options.size()) {
                throw new DomainRuleViolation("CBT_ANSWER", "The correct-answer position is outside the options.", new DomainRuleViolation.Remedy("Point to one of the options you listed.", "You"));
            }
        }
        return new Checked(kind, options, key.get(0), key);
    }

    @PostMapping("/api/v1/cbt/questions")
    @PreAuthorize(AUTHORS)
    @Transactional
    Map<String, Object> add(@Valid @RequestBody Question body) {
        String course = body.course().trim();
        scoped(course);
        Checked c = check(body.kind(), body.options(), body.answer(), body.answers());
        UUID id = jdbc.sql("""
                INSERT INTO assessment.question (course_code, topic, stem, options, answer, answers, kind, difficulty, marks, explanation, authored_by)
                VALUES (:c, :t, :s, :o::jsonb, :a, :as, :k, coalesce(:d, 'MEDIUM'), coalesce(:m, 1), :x, nullif(current_setting('moaum.actor_id', true), '')::uuid)
                RETURNING id
                """)
                .param("c", course).param("t", blank(body.topic()), Types.VARCHAR).param("s", body.stem().trim()).param("o", mapper.writeValueAsString(c.options()))
                .param("a", c.answer()).param("as", c.answers().toArray(new Integer[0])).param("k", c.kind())
                .param("d", body.difficulty() == null || body.difficulty().isBlank() ? null : body.difficulty().toUpperCase(), Types.VARCHAR)
                .param("m", body.marks(), Types.INTEGER).param("x", blank(body.explanation()), Types.VARCHAR)
                .query(UUID.class).single();
        return Map.of("id", id, "kind", c.kind());
    }

    /** an edit: the question on a paper already sat keeps its options' meaning — the stem, topic, difficulty, marks and explanation may change, the key and options may not */
    @PutMapping("/api/v1/cbt/questions/{id}")
    @PreAuthorize(AUTHORS)
    @Transactional
    Map<String, Object> edit(@PathVariable UUID id, @Valid @RequestBody QuestionEdit body) {
        Map<String, Object> q = jdbc.sql("""
                SELECT q.course_code, (SELECT count(*) FROM assessment.cbt_attempt a WHERE q.id = ANY (a.question_ids)) AS sat FROM assessment.question q WHERE q.id = :id
                """).param("id", id).query().listOfRows().stream().findFirst().orElseThrow(() -> new NotFound("question", id.toString()));
        scoped((String) q.get("course_code"));
        Checked c = check(body.kind(), body.options(), body.answer(), body.answers());
        if (((Number) q.get("sat")).longValue() > 0) {
            Map<String, Object> current = jdbc.sql("SELECT (options = :o::jsonb) AS same_options, kind FROM assessment.question WHERE id = :id")
                    .param("o", mapper.writeValueAsString(c.options())).param("id", id).query().singleRow();
            if (!Boolean.TRUE.equals(current.get("same_options")) || !c.kind().equals(current.get("kind"))) {
                throw new DomainRuleViolation("CBT_QUESTION_SAT", "This question has been sat; its options and key are kept so the papers can be explained.",
                        new DomainRuleViolation.Remedy("Retire it and author a corrected question, or amend the affected results with a reason.", "You"));
            }
        }
        jdbc.sql("""
                UPDATE assessment.question SET topic = :t, stem = :s, options = :o::jsonb, answer = :a, answers = :as, kind = :k,
                       difficulty = coalesce(:d, difficulty), marks = coalesce(:m, marks), explanation = :x
                 WHERE id = :id
                """)
                .param("t", blank(body.topic()), Types.VARCHAR).param("s", body.stem().trim()).param("o", mapper.writeValueAsString(c.options()))
                .param("a", c.answer()).param("as", c.answers().toArray(new Integer[0])).param("k", c.kind())
                .param("d", body.difficulty() == null || body.difficulty().isBlank() ? null : body.difficulty().toUpperCase(), Types.VARCHAR)
                .param("m", body.marks(), Types.INTEGER).param("x", blank(body.explanation()), Types.VARCHAR).param("id", id).update();
        return Map.of("id", id, "kind", c.kind());
    }

    @PostMapping("/api/v1/cbt/questions/{id}/active")
    @PreAuthorize(AUTHORS)
    @Transactional
    Map<String, Object> setActive(@PathVariable UUID id, @RequestBody Active body) {
        String course = jdbc.sql("SELECT course_code FROM assessment.question WHERE id = :id").param("id", id).query(String.class).optional()
                .orElseThrow(() -> new NotFound("question", id.toString()));
        scoped(course);
        jdbc.sql("UPDATE assessment.question SET active = :a WHERE id = :id").param("a", body.active()).param("id", id).update();
        return Map.of("id", id, "active", body.active());
    }

    private static String blank(String s) {
        return s == null || s.isBlank() ? null : s.trim();
    }
}
