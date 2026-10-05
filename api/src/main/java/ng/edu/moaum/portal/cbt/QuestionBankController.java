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

    /* ── the bank from a spreadsheet: every row judged, the valid ones written, nothing silently corrected ── */

    public record ImportRow(Integer row, @Size(max = 120) String topic, @Size(max = 4000) String stem, List<@Size(max = 500) String> options, @Size(max = 200) String answer,
                            @Size(max = 40) String kind, @Size(max = 20) String difficulty, @Size(max = 20) String marks, @Size(max = 2000) String explanation) {
    }

    public record ImportIn(@NotBlank @Size(max = 10) String course, Boolean dryRun, @Size(max = 200) String fileName, @NotNull @Size(max = 5000) List<@Valid ImportRow> rows) {
    }

    private static final java.util.regex.Pattern WS = java.util.regex.Pattern.compile("\\s+");

    private static String norm(String s) {
        return s == null ? "" : WS.matcher(s.trim().toLowerCase()).replaceAll(" ");
    }

    /** the kind the sheet names, or the kind the row implies: several answers is MULTI, True/False alone is TRUE_FALSE, else MCQ */
    private static String kindOf(String given, List<String> options, List<Integer> answers) {
        String k = given == null ? "" : given.trim().toUpperCase().replace('-', '_').replace('/', '_').replace(' ', '_');
        if (k.matches("MULTI.*|MULTIPLE_SELECT|MULTIPLE_ANSWER.*|MSQ|MANY")) return "MULTI";
        if (k.matches("TRUE_FALSE|TF|TRUEFALSE|BOOLEAN|YES_NO")) return "TRUE_FALSE";
        if (k.matches("MCQ|MULTIPLE_CHOICE|SINGLE|SINGLE_ANSWER|CHOICE")) return "MCQ";
        if (!k.isEmpty()) return "?" + given.trim();
        if (answers.size() > 1) return "MULTI";
        if (options.size() == 2 && options.get(0).equalsIgnoreCase("true") && options.get(1).equalsIgnoreCase("false")) return "TRUE_FALSE";
        return "MCQ";
    }

    /** the key as the sheet gives it: letters (B, b, "B,D"), 1-based numbers, or the option's own text */
    private static List<Integer> answersOf(String answer, List<String> options) {
        List<Integer> out = new java.util.ArrayList<>();
        if (answer == null || answer.isBlank()) return out;
        String a = answer.trim();
        // the whole text may be an option
        for (int i = 0; i < options.size(); i++) if (options.get(i).equalsIgnoreCase(a)) return List.of(i);
        for (String tok : a.split("\\s*(,|;|/|&|\\band\\b|\\s)\\s*")) {
            String t = tok.trim();
            if (t.isEmpty()) continue;
            if (t.matches("(?i)option\\s*[a-h]")) t = t.substring(t.length() - 1);
            if (t.length() == 1 && Character.isLetter(t.charAt(0))) { int i = Character.toUpperCase(t.charAt(0)) - 'A'; if (!out.contains(i)) out.add(i); continue; }
            if (t.matches("[1-9]")) { int i = Integer.parseInt(t) - 1; if (!out.contains(i)) out.add(i); continue; }
            int found = -1;
            for (int i = 0; i < options.size(); i++) if (options.get(i).equalsIgnoreCase(t)) found = i;
            if (found >= 0) { if (!out.contains(found)) out.add(found); continue; }
            return List.of(-1);   // something the sheet says that no option is
        }
        return out.stream().sorted().toList();
    }

    @PostMapping("/api/v1/cbt/questions/import")
    @PreAuthorize(AUTHORS)
    @Transactional
    Map<String, Object> importQuestions(@Valid @RequestBody ImportIn in) {
        String course = in.course().trim();
        scoped(course);
        if (!jdbc.sql("SELECT EXISTS (SELECT 1 FROM catalogue.course WHERE code = :c)").param("c", course).query(Boolean.class).single()) throw new NotFound("course", course);
        boolean dry = Boolean.TRUE.equals(in.dryRun());
        Set<String> inBank = new java.util.HashSet<>(jdbc.sql("SELECT lower(regexp_replace(btrim(stem), '\\s+', ' ', 'g')) FROM assessment.question WHERE course_code = :c").param("c", course).query(String.class).list());
        Set<String> seen = new java.util.HashSet<>();
        List<Map<String, Object>> findings = new java.util.ArrayList<>();
        int valid = 0, errors = 0, dupFile = 0, dupBank = 0, imported = 0;
        for (ImportRow r : in.rows()) {
            List<String> codes = new java.util.ArrayList<>();
            List<String> messages = new java.util.ArrayList<>();
            String stem = r.stem() == null ? "" : r.stem().trim();
            List<String> options = (r.options() == null ? List.<String>of() : r.options()).stream().map(o -> o == null ? "" : o.trim()).filter(o -> !o.isEmpty()).toList();
            List<Integer> answers = answersOf(r.answer(), options);
            String kind = kindOf(r.kind(), options, answers);
            if (stem.isEmpty()) { codes.add("STEM_REQUIRED"); messages.add("the question text is empty"); }
            if (options.size() < 2) { codes.add("OPTIONS_TOO_FEW"); messages.add("a question needs at least two options; " + options.size() + " given"); }
            if (options.size() > 8) { codes.add("OPTIONS_TOO_MANY"); messages.add("at most eight options; " + options.size() + " given"); }
            if (new java.util.HashSet<>(options.stream().map(String::toLowerCase).toList()).size() < options.size()) { codes.add("OPTIONS_REPEAT"); messages.add("two options read the same"); }
            if (r.answer() == null || r.answer().isBlank()) { codes.add("ANSWER_REQUIRED"); messages.add("no correct answer is given"); }
            else if (answers.isEmpty() || answers.contains(-1) || answers.stream().anyMatch(i -> i < 0 || i >= options.size())) { codes.add("ANSWER_INVALID"); messages.add("the answer \"" + r.answer().trim() + "\" names no option: use the letter (B), the number (2), letters for several (B, D) or the option's text"); }
            if (kind.startsWith("?")) { codes.add("KIND_INVALID"); messages.add("the kind \"" + kind.substring(1) + "\" is not MCQ, TRUE_FALSE or MULTI"); }
            else if ("TRUE_FALSE".equals(kind) && options.size() != 2) { codes.add("TRUE_FALSE_OPTIONS"); messages.add("a true/false question has exactly two options"); }
            else if ("MULTI".equals(kind) && answers.size() < 1) { codes.add("ANSWER_REQUIRED"); messages.add("a multiple-select question names at least one correct option"); }
            else if (!"MULTI".equals(kind) && answers.size() > 1) { codes.add("ANSWER_INVALID"); messages.add("one correct option for a " + (kind.equals("TRUE_FALSE") ? "true/false" : "multiple-choice") + " question; " + answers.size() + " given — set the kind to MULTI if several are right"); }
            String difficulty = r.difficulty() == null || r.difficulty().isBlank() ? "MEDIUM" : r.difficulty().trim().toUpperCase();
            if (!Set.of("EASY", "MEDIUM", "HARD").contains(difficulty)) { codes.add("DIFFICULTY_INVALID"); messages.add("difficulty is EASY, MEDIUM or HARD"); }
            int marks = 1;
            if (r.marks() != null && !r.marks().isBlank()) {
                try { marks = Integer.parseInt(r.marks().trim().replaceAll("[^0-9]", "")); } catch (NumberFormatException e) { marks = 0; }
                if (marks < 1 || marks > 100) { codes.add("MARKS_INVALID"); messages.add("marks are a whole number from 1 to 100"); }
            }
            String status;
            String key = norm(stem);
            if (!codes.isEmpty()) { status = "ERROR"; errors++; }
            else if (!key.isEmpty() && seen.contains(key)) { status = "DUPLICATE_IN_FILE"; dupFile++; messages.add("the same question appears earlier in the file"); }
            else if (!key.isEmpty() && inBank.contains(key)) { status = "ALREADY_IN_BANK"; dupBank++; messages.add("a question with this text is in the bank already; it is not added twice"); }
            else { status = "VALID"; valid++; }
            if (!key.isEmpty()) seen.add(key);
            if ("VALID".equals(status) && !dry) {
                jdbc.sql("""
                        INSERT INTO assessment.question (course_code, topic, stem, options, answer, answers, kind, difficulty, marks, explanation, authored_by)
                        VALUES (:c, :t, :s, :o::jsonb, :a, :as, :k, :d, :m, :x, nullif(current_setting('moaum.actor_id', true), '')::uuid)
                        """)
                        .param("c", course).param("t", blank(r.topic()), Types.VARCHAR).param("s", stem).param("o", mapper.writeValueAsString(options))
                        .param("a", answers.get(0)).param("as", answers.toArray(new Integer[0])).param("k", kind).param("d", difficulty).param("m", marks).param("x", blank(r.explanation()), Types.VARCHAR).update();
                status = "IMPORTED"; imported++;
            }
            Map<String, Object> f = new LinkedHashMap<>();
            f.put("row", r.row()); f.put("stem", stem); f.put("topic", blank(r.topic())); f.put("kind", kind.startsWith("?") ? kind.substring(1) : kind); f.put("options", options.size());
            f.put("answers", answers.contains(-1) ? List.of() : answers); f.put("answer", r.answer()); f.put("difficulty", difficulty); f.put("marks", marks);
            f.put("status", status); f.put("codes", codes); f.put("messages", messages);
            findings.add(f);
        }
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("course", course);
        out.put("dryRun", dry);
        out.put("summary", Map.of("total", in.rows().size(), "valid", valid, "errors", errors, "duplicatesInFile", dupFile, "alreadyInBank", dupBank, "imported", imported));
        out.put("rows", findings);
        return out;
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
