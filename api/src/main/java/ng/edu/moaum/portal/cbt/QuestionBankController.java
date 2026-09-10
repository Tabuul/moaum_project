package ng.edu.moaum.portal.cbt;

import java.util.List;
import java.util.Map;
import java.util.UUID;

import jakarta.validation.Valid;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

import ng.edu.moaum.portal.shared.DomainRuleViolation;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/** The CBT question bank (V077): authoring and blueprints, per course. */
@RestController
class QuestionBankController {

    private static final String READERS = "hasAnyAuthority('OFFICE_lecturer','OFFICE_hod','OFFICE_exams','OFFICE_facultyexams','OFFICE_dean','OFFICE_academic','OFFICE_registrar','OFFICE_admin','OFFICE_super')";
    private static final String AUTHORS = "hasAnyAuthority('OFFICE_lecturer','OFFICE_hod','OFFICE_exams','OFFICE_dean','OFFICE_super')";

    private final JdbcClient jdbc;
    private final tools.jackson.databind.ObjectMapper mapper = new tools.jackson.databind.ObjectMapper();

    QuestionBankController(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    public record Question(@NotBlank @Size(max = 10) String course, @Size(max = 120) String topic, @NotBlank @Size(max = 2000) String stem,
                           @NotNull List<@Size(max = 500) String> options, @NotNull @Min(0) Integer answer, @Size(max = 10) String difficulty, Integer marks) {
    }

    public record Active(boolean active) {
    }

    @GetMapping("/api/v1/cbt/courses")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> courses() {
        return jdbc.sql("""
                SELECT c.code, c.title, (SELECT count(*) FROM assessment.question q WHERE q.course_code = c.code AND q.active) AS questions
                  FROM catalogue.course c ORDER BY c.code
                """).query().listOfRows();
    }

    @GetMapping("/api/v1/cbt/questions")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> questions(@RequestParam String course) {
        List<Map<String, Object>> rows = jdbc.sql("""
                SELECT id, course_code, topic, stem, options, answer, difficulty, marks, active
                  FROM assessment.question WHERE course_code = :c ORDER BY topic NULLS FIRST, authored_at DESC
                """).param("c", course).query().listOfRows();
        List<Map<String, Object>> blueprint = jdbc.sql("""
                SELECT coalesce(topic, 'Untitled topic') AS topic,
                       count(*) FILTER (WHERE difficulty = 'EASY' AND active) AS easy,
                       count(*) FILTER (WHERE difficulty = 'MEDIUM' AND active) AS medium,
                       count(*) FILTER (WHERE difficulty = 'HARD' AND active) AS hard,
                       count(*) FILTER (WHERE active) AS total
                  FROM assessment.question WHERE course_code = :c GROUP BY topic ORDER BY topic NULLS FIRST
                """).param("c", course).query().listOfRows();
        return Map.of("rows", rows, "blueprint", blueprint);
    }

    @PostMapping("/api/v1/cbt/questions")
    @PreAuthorize(AUTHORS)
    @Transactional
    Map<String, Object> add(@Valid @RequestBody Question body) {
        if (body.options().size() < 2) {
            throw new DomainRuleViolation("CBT_OPTIONS", "A question needs at least two options.", new DomainRuleViolation.Remedy("Add the options a candidate chooses between.", "You"));
        }
        if (body.answer() >= body.options().size()) {
            throw new DomainRuleViolation("CBT_ANSWER", "The correct-answer position is outside the options.", new DomainRuleViolation.Remedy("Point to one of the options you listed.", "You"));
        }
        String optionsJson = mapper.writeValueAsString(body.options());
        UUID id = jdbc.sql("""
                INSERT INTO assessment.question (course_code, topic, stem, options, answer, difficulty, marks, authored_by)
                VALUES (:c, :t, :s, :o::jsonb, :a, coalesce(:d, 'MEDIUM'), coalesce(:m, 1), nullif(current_setting('moaum.actor_id', true), '')::uuid)
                RETURNING id
                """)
                .param("c", body.course().trim()).param("t", body.topic() == null || body.topic().isBlank() ? null : body.topic().trim(), java.sql.Types.VARCHAR)
                .param("s", body.stem().trim()).param("o", optionsJson).param("a", body.answer())
                .param("d", body.difficulty() == null || body.difficulty().isBlank() ? null : body.difficulty().toUpperCase(), java.sql.Types.VARCHAR)
                .param("m", body.marks(), java.sql.Types.INTEGER)
                .query(UUID.class).single();
        return Map.of("id", id);
    }

    @PostMapping("/api/v1/cbt/questions/{id}/active")
    @PreAuthorize(AUTHORS)
    @Transactional
    Map<String, Object> setActive(@PathVariable UUID id, @RequestBody Active body) {
        jdbc.sql("UPDATE assessment.question SET active = :a WHERE id = :id").param("a", body.active()).param("id", id).update();
        return Map.of("id", id, "active", body.active());
    }
}
