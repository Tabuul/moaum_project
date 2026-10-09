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
import ng.edu.moaum.portal.shared.OfficeScope;

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
 * A question is retired or archived, never deleted, so a paper that used it can still be explained. From V364 every
 * change of a question's wording, options, key or marks is a new version, kept whole, and each attempt reads the
 * version it drew — so a question may be corrected after it is sat, but never while an examination drawing it is open.
 * From V374 a question written or changed waits for moderation: someone other than the person who set that version — a Head of
 * Department, an Examinations Officer, a Dean, the GST, EPS or JUPEB office in its own banks — approves it, or returns it with a note,
 * and only approved questions go on a paper. The rule is the database's (assessment.question_moderate); the screen only asks.
 * V375: the moderator's queue (the banks with questions waiting, within the acting office's scope, and the setter's returned
 * questions), and moderation by sample — a random sample of a bank's waiting questions, every one approved, approves the rest.
 */
@RestController
class QuestionBankController {

    private static final String READERS = "hasAnyAuthority('OFFICE_lecturer','OFFICE_hod','OFFICE_exams','OFFICE_facultyexams','OFFICE_dean','OFFICE_academic',"
            + "'OFFICE_registrar','OFFICE_dregistrar','OFFICE_gst','OFFICE_eps','OFFICE_ict','OFFICE_admin','OFFICE_super','OFFICE_jupeb')";
    private static final String AUTHORS = "hasAnyAuthority('OFFICE_lecturer','OFFICE_hod','OFFICE_exams','OFFICE_dean','OFFICE_gst','OFFICE_eps','OFFICE_super','OFFICE_jupeb')";
    /** V365: a JUPEB subject's bank is named "JUPEB:<subject code>" wherever a course's is named by its code */
    static final String JUPEB_PREFIX = "JUPEB:";
    private static final Set<String> KINDS = Set.of("MCQ", "TRUE_FALSE", "MULTI");
    /** V374: who moderates — never the person who set the version (the database refuses that, CBT_MODERATE_OWN) */
    private static final String MODERATORS = "hasAnyAuthority('OFFICE_hod','OFFICE_exams','OFFICE_facultyexams','OFFICE_dean','OFFICE_gst','OFFICE_eps','OFFICE_super','OFFICE_jupeb')";
    private static final Set<String> MODERATION = Set.of("PENDING", "APPROVED", "RETURNED");

    private final JdbcClient jdbc;
    private final OfficeScope scope;
    private final tools.jackson.databind.ObjectMapper mapper = new tools.jackson.databind.ObjectMapper();

    QuestionBankController(JdbcClient jdbc, OfficeScope scope) {
        this.jdbc = jdbc;
        this.scope = scope;
    }

    public record Question(@NotBlank @Size(max = 30) String course, @Size(max = 120) String topic, @NotBlank @Size(max = 4000) String stem,
                           @NotNull List<@Size(max = 500) String> options, Integer answer, List<Integer> answers, @Size(max = 12) String kind,
                           @Size(max = 10) String difficulty, Integer marks, @Size(max = 2000) String explanation) {
    }

    public record QuestionEdit(@Size(max = 120) String topic, @NotBlank @Size(max = 4000) String stem, @NotNull List<@Size(max = 500) String> options,
                               Integer answer, List<Integer> answers, @Size(max = 12) String kind, @Size(max = 10) String difficulty, Integer marks,
                               @Size(max = 2000) String explanation) {
    }

    public record Active(boolean active) {
    }

    public record Archived(boolean archived) {
    }

    /** the GST and EPS offices see and author only their own courses; everyone else, every course */
    private static String actingOffice() {
        String acting = AuditContextHolder.current().map(AuditContext::actorOffice).orElse("");
        return "gst".equals(acting) ? "GST" : "eps".equals(acting) ? "EPS" : null;
    }

    /** V365: a bank — a course's (course) or a JUPEB subject's (subject) — and the name it goes by */
    record Bank(String course, UUID subject, String label) {
    }

    private static String acting() {
        return AuditContextHolder.current().map(AuditContext::actorOffice).orElse("");
    }

    /** the bank a name means, held to the acting office: a JUPEB subject's is the JUPEB Office's alone, and the JUPEB Office works in no other */
    private Bank bank(String key) {
        String k = key == null ? "" : key.trim();
        if (k.toUpperCase().startsWith(JUPEB_PREFIX)) {
            if (!Set.of("jupeb", "super").contains(acting())) throw new AccessDeniedException("A JUPEB subject's question bank is the JUPEB Office's.");
            String code = k.substring(JUPEB_PREFIX.length()).trim();
            UUID sid = jdbc.sql("SELECT id FROM jupeb.subject WHERE upper(code) = upper(:c)").param("c", code).query(UUID.class).optional()
                    .orElseThrow(() -> new NotFound("JUPEB subject", code));
            return new Bank(null, sid, JUPEB_PREFIX + code.toUpperCase());
        }
        if ("jupeb".equals(acting())) throw new AccessDeniedException("The JUPEB Office works in its own subjects' question banks.");
        scoped(k);
        return new Bank(k, null, k);
    }

    /** the bank a question is in, held to the acting office as bank() holds a name */
    private Bank bankOf(UUID question) {
        Map<String, Object> q = jdbc.sql("""
                SELECT q.course_code, s.code AS subject FROM assessment.question q LEFT JOIN jupeb.subject s ON s.id = q.jupeb_subject_id WHERE q.id = :id
                """).param("id", question).query().listOfRows().stream().findFirst().orElseThrow(() -> new NotFound("question", question.toString()));
        return bank(q.get("course_code") != null ? (String) q.get("course_code") : JUPEB_PREFIX + q.get("subject"));
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
        if ("jupeb".equals(acting()) || "JUPEB".equalsIgnoreCase(office == null ? "" : office.trim())) {
            if (!Set.of("jupeb", "super").contains(acting())) throw new AccessDeniedException("JUPEB subjects' question banks are the JUPEB Office's.");
            // V365: the JUPEB Office's banks are its subjects'
            return jdbc.sql("""
                    SELECT 'JUPEB:' || s.code AS code, s.title, 'JUPEB' AS kind, 'JUPEB' AS general_office, NULL::int AS level, NULL::int AS semester, NULL::int AS units,
                           CASE WHEN s.active THEN 'LIVE' ELSE 'ENDED' END AS state, s.cbt_enabled,
                           (SELECT count(*) FROM assessment.question q WHERE q.jupeb_subject_id = s.id AND q.active) AS questions,
                           (SELECT count(*) FROM assessment.question q WHERE q.jupeb_subject_id = s.id) AS total,
                           (SELECT count(*) FROM assessment.question q WHERE q.jupeb_subject_id = s.id AND q.moderation <> 'APPROVED' AND q.archived_at IS NULL) AS awaiting
                      FROM jupeb.subject s WHERE s.active ORDER BY s.code
                    """).query().listOfRows();
        }
        String o = actingOffice() != null ? actingOffice() : office == null || office.isBlank() ? null : office.trim().toUpperCase();
        return jdbc.sql("""
                SELECT c.code, c.title, c.kind, c.general_office, c.level, c.semester, c.units, c.state, c.cbt_enabled,
                       (SELECT count(*) FROM assessment.question q WHERE q.course_code = c.code AND q.active) AS questions,
                       (SELECT count(*) FROM assessment.question q WHERE q.course_code = c.code) AS total,
                       (SELECT count(*) FROM assessment.question q WHERE q.course_code = c.code AND q.moderation <> 'APPROVED' AND q.archived_at IS NULL) AS awaiting
                  FROM catalogue.course c
                 WHERE (:o::text IS NULL OR c.general_office = :o)
                 ORDER BY c.code
                """).param("o", o, Types.VARCHAR).query().listOfRows();
    }

    @GetMapping("/api/v1/cbt/questions")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> questions(@RequestParam String course, @RequestParam(required = false) String q, @RequestParam(required = false) String topic,
                                  @RequestParam(required = false) String difficulty, @RequestParam(required = false) String kind,
                                  @RequestParam(required = false) String status, @RequestParam(required = false) String moderation, @RequestParam(defaultValue = "1") int page,
                                  @RequestParam(defaultValue = "1000") int size) {
        Bank b = bank(course);
        // V364: searched and paged on the server — the text, the topic, the difficulty, the kind, the status (ACTIVE, INACTIVE, ARCHIVED; default every one not archived)
        String st = status == null || status.isBlank() ? null : status.trim().toUpperCase();
        // V374: PENDING, APPROVED or RETURNED; AWAITING = not approved
        String m = moderation == null || moderation.isBlank() ? null : moderation.trim().toUpperCase();
        String mod = m != null && (MODERATION.contains(m) || "AWAITING".equals(m)) ? m : null;
        int sz = Math.max(1, Math.min(size, 1000)), pg = Math.max(1, page);
        String where = """
                 WHERE CASE WHEN :sub::uuid IS NULL THEN q.course_code = :c ELSE q.jupeb_subject_id = :sub::uuid END
                   AND (:q::text IS NULL OR lower(q.stem) LIKE :q OR lower(coalesce(q.topic, '')) LIKE :q OR lower(coalesce(q.explanation, '')) LIKE :q)
                   AND (:topic::text IS NULL OR lower(btrim(coalesce(q.topic, ''))) = lower(btrim(:topic)))
                   AND (:diff::text IS NULL OR q.difficulty = upper(:diff)) AND (:kind::text IS NULL OR q.kind = upper(:kind))
                   AND CASE coalesce(:st, 'CURRENT') WHEN 'ACTIVE' THEN q.active WHEN 'INACTIVE' THEN NOT q.active AND q.archived_at IS NULL
                        WHEN 'ARCHIVED' THEN q.archived_at IS NOT NULL WHEN 'ALL' THEN true ELSE q.archived_at IS NULL END
                   AND (:mod::text IS NULL OR CASE WHEN :mod = 'AWAITING' THEN q.moderation <> 'APPROVED' ELSE q.moderation = :mod END)
                """;
        java.util.function.UnaryOperator<JdbcClient.StatementSpec> bind = spec -> spec.param("c", b.course(), Types.VARCHAR).param("sub", b.subject(), Types.OTHER)
                .param("q", q == null || q.isBlank() ? null : "%" + q.trim().toLowerCase() + "%", Types.VARCHAR).param("topic", blank(topic), Types.VARCHAR)
                .param("diff", blank(difficulty), Types.VARCHAR).param("kind", blank(kind), Types.VARCHAR).param("st", st, Types.VARCHAR).param("mod", mod, Types.VARCHAR);
        long total = bind.apply(jdbc.sql("SELECT count(*) FROM assessment.question q" + where)).query(Long.class).single();
        List<Map<String, Object>> rows = bind.apply(jdbc.sql("""
                SELECT q.id, q.course_code, q.topic, q.stem, q.options::text AS options, q.answer, to_jsonb(q.answers)::text AS answers, q.kind, q.difficulty, q.marks, q.active,
                       q.explanation, q.authored_at, q.updated_at, q.version, q.archived_at,
                       CASE WHEN p.id IS NULL THEN NULL ELSE p.surname || ', ' || p.given_names END AS authored_by,
                       (SELECT count(*) FROM assessment.cbt_exam_question eq WHERE eq.question_id = q.id) AS on_papers,
                       (SELECT count(*) FROM assessment.cbt_attempt a WHERE q.id = ANY (a.question_ids)) AS sat,
                       q.moderation, q.moderated_version, q.moderated_at, q.moderation_note,
                       CASE WHEN mp.id IS NULL THEN NULL ELSE mp.surname || ', ' || mp.given_names END AS moderated_by,
                       CASE WHEN sp.id IS NULL THEN NULL ELSE sp.surname || ', ' || sp.given_names END AS set_by,
                       assessment.question_setter(q.id, q.version) IS NOT DISTINCT FROM nullif(current_setting('moaum.actor_id', true), '')::uuid AS mine
                  FROM assessment.question q LEFT JOIN iam.person p ON p.id = q.authored_by LEFT JOIN iam.person mp ON mp.id = q.moderated_by
                  LEFT JOIN iam.person sp ON sp.id = assessment.question_setter(q.id, q.version)
                """ + where + " ORDER BY q.topic NULLS FIRST, q.authored_at DESC LIMIT :lim OFFSET :off"))
                .param("lim", sz).param("off", (long) (pg - 1) * sz).query().listOfRows();
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
                  FROM assessment.question WHERE CASE WHEN :sub::uuid IS NULL THEN course_code = :c ELSE jupeb_subject_id = :sub::uuid END GROUP BY topic ORDER BY topic NULLS FIRST
                """).param("c", b.course(), Types.VARCHAR).param("sub", b.subject(), Types.OTHER).query().listOfRows();
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("rows", rows);
        out.put("total", total);
        out.put("page", pg);
        out.put("size", sz);
        out.put("blueprint", blueprint);
        out.put("awaiting", jdbc.sql("SELECT count(*) FROM assessment.question WHERE CASE WHEN :sub::uuid IS NULL THEN course_code = :c ELSE jupeb_subject_id = :sub::uuid END AND moderation <> 'APPROVED' AND archived_at IS NULL")
                .param("c", b.course(), Types.VARCHAR).param("sub", b.subject(), Types.OTHER).query(Long.class).single());
        return out;
    }

    /* ── V374: moderation ── */

    public record ModerationIn(@NotBlank @Size(max = 10) String decision, @Size(max = 1000) String note) {
    }

    public record ModerationAllIn(@NotNull @Size(min = 1, max = 500) List<@NotNull UUID> ids, @NotBlank @Size(max = 10) String decision, @Size(max = 1000) String note) {
    }

    /** a question approved, or returned with a note, by someone other than the person who set its version */
    @PostMapping("/api/v1/cbt/questions/{id}/moderation")
    @PreAuthorize(MODERATORS)
    @Transactional
    Map<String, Object> moderate(@PathVariable UUID id, @Valid @RequestBody ModerationIn in) {
        bankOf(id);
        return jdbc.sql("SELECT id, version, moderation, moderated_at, moderation_note FROM assessment.question_moderate(:q, :d, :n)")
                .param("q", id).param("d", in.decision()).param("n", blank(in.note()), Types.VARCHAR).query().singleRow();
    }

    /** several questions decided at once — each judged on its own; one the actor set, or one already decided, is left as it is and said so */
    @PostMapping("/api/v1/cbt/questions/moderation")
    @PreAuthorize(MODERATORS)
    @Transactional
    Map<String, Object> moderateAll(@Valid @RequestBody ModerationAllIn in) {
        int done = 0;
        String want = "APPROVE".equalsIgnoreCase(in.decision().trim()) ? "APPROVED" : "RETURNED";
        List<Map<String, Object>> left = new java.util.ArrayList<>();
        for (UUID id : new java.util.LinkedHashSet<>(in.ids())) {
            bankOf(id);
            String state = jdbc.sql("SELECT moderation FROM assessment.question WHERE id = :q").param("q", id).query(String.class).single();
            if (want.equals(state)) {
                left.add(Map.of("id", id, "code", "CBT_ALREADY_" + want, "detail", "already " + want.toLowerCase()));
                continue;
            }
            String problem = jdbc.sql("SELECT assessment.question_moderation_problem(:q, :d, :n)").param("q", id).param("d", in.decision()).param("n", blank(in.note()), Types.VARCHAR)
                    .query(String.class).optional().orElse(null);
            if (problem != null) {
                int c = problem.indexOf(':');
                left.add(Map.of("id", id, "code", c > 0 ? problem.substring(0, c) : "CBT_MODERATION", "detail", c > 0 ? problem.substring(c + 1).trim() : problem));
                continue;
            }
            jdbc.sql("SELECT (assessment.question_moderate(:q, :d, :n)).id").param("q", id).param("d", in.decision()).param("n", blank(in.note()), Types.VARCHAR).query(UUID.class).single();
            done++;
        }
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("decided", done);
        out.put("left", left);
        return out;
    }

    /* ── V375: the moderator's queue, and moderation by sample ── */

    /**
     * The banks with questions waiting, within the acting office's scope: the GST and EPS offices their own courses, the JUPEB Office its
     * subjects, a department or faculty office its department's or faculty's, every other reader every course — with how many wait, how
     * many of those the signed-in person may decide (they did not set them), how many were returned, and which are theirs.
     */
    @GetMapping("/api/v1/cbt/moderation/queue")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> queue() {
        UUID me = AuditContextHolder.current().map(AuditContext::actorId).orElse(null);
        String counts = """
                count(*) FILTER (WHERE q.moderation = 'PENDING') AS pending,
                count(*) FILTER (WHERE q.moderation = 'PENDING' AND assessment.question_setter(q.id, q.version) IS DISTINCT FROM :me) AS for_me,
                count(*) FILTER (WHERE q.moderation = 'PENDING' AND assessment.question_setter(q.id, q.version) = :me) AS mine_waiting,
                count(*) FILTER (WHERE q.moderation = 'RETURNED') AS returned,
                count(*) FILTER (WHERE q.moderation = 'RETURNED' AND assessment.question_setter(q.id, q.version) = :me) AS returned_to_me,
                min(coalesce(q.updated_at, q.authored_at)) FILTER (WHERE q.moderation = 'PENDING') AS waiting_since
                """;
        if ("jupeb".equals(acting())) {
            return jdbc.sql("SELECT 'JUPEB:' || js.code AS bank, js.title, 'JUPEB' AS office, " + counts + """
                      FROM assessment.question q JOIN jupeb.subject js ON js.id = q.jupeb_subject_id
                     WHERE q.moderation <> 'APPROVED' AND q.archived_at IS NULL
                     GROUP BY js.code, js.title ORDER BY waiting_since NULLS LAST, js.code
                    """).param("me", me, Types.OTHER).query().listOfRows();
        }
        String o = actingOffice();
        OfficeScope.Bound b = o != null ? new OfficeScope.Bound(null, null, null) : scope.bound(null, null, null);
        return jdbc.sql("SELECT c.code AS bank, c.title, c.general_office AS office, " + counts + """
                  FROM assessment.question q JOIN catalogue.course c ON c.code = q.course_code LEFT JOIN ref.department d ON d.code = c.dept_code
                 WHERE q.moderation <> 'APPROVED' AND q.archived_at IS NULL
                   AND (:go::text IS NULL OR c.general_office = :go) AND (:dept::text IS NULL OR c.dept_code = :dept) AND (:fac::text IS NULL OR d.faculty_code = :fac)
                 GROUP BY c.code, c.title, c.general_office ORDER BY waiting_since NULLS LAST, c.code
                """).param("me", me, Types.OTHER).param("go", o, Types.VARCHAR).param("dept", b.dept(), Types.VARCHAR).param("fac", b.fac(), Types.VARCHAR)
                .query().listOfRows();
    }

    public record SampleIn(@NotBlank @Size(max = 30) String course, @NotNull Integer size) {
    }

    /** a sample, with each sampled question as it now stands (its key included: a moderator reads the key) */
    private Map<String, Object> sampleView(UUID id) {
        Map<String, Object> x = jdbc.sql("""
                SELECT s.id, coalesce(s.course_code, 'JUPEB:' || js.code) AS bank, s.state, s.drawn_at, s.decided_at, s.approved, s.left_as_they_were,
                       cardinality(s.population) AS population, cardinality(s.sample) AS size, s.drawn_by
                  FROM assessment.question_moderation_sample s LEFT JOIN jupeb.subject js ON js.id = s.jupeb_subject_id WHERE s.id = :id
                """).param("id", id).query().listOfRows().stream().findFirst().map(LinkedHashMap::new).orElseThrow(() -> new NotFound("sample", id.toString()));
        List<Map<String, Object>> rows = jdbc.sql("""
                SELECT q.id, q.topic, q.stem, q.options::text AS options, to_jsonb(q.answers)::text AS answers, q.kind, q.difficulty, q.marks, q.explanation,
                       q.version, pv.v AS drawn_version, q.moderation, q.moderated_version, q.moderation_note,
                       CASE WHEN p.id IS NULL THEN NULL ELSE p.surname || ', ' || p.given_names END AS set_by
                  FROM assessment.question_moderation_sample s
                  CROSS JOIN LATERAL unnest(s.population, s.population_versions) pv(id, v)
                  JOIN assessment.question q ON q.id = pv.id
                  LEFT JOIN iam.person p ON p.id = assessment.question_setter(q.id, q.version)
                 WHERE s.id = :id AND pv.id = ANY (s.sample)
                 ORDER BY array_position(s.sample, pv.id)
                """).param("id", id).query().listOfRows();
        for (Map<String, Object> r : rows) {
            r.put("options", mapper.readValue(String.valueOf(r.get("options")), new tools.jackson.core.type.TypeReference<List<String>>() { }));
            r.put("answers", r.get("answers") == null ? List.of() : mapper.readValue(String.valueOf(r.get("answers")), new tools.jackson.core.type.TypeReference<List<Integer>>() { }));
        }
        x.put("questions", rows);
        return x;
    }

    /** the signed-in moderator's open sample of a bank (or none), and how many of its questions wait for them to moderate */
    @GetMapping("/api/v1/cbt/questions/samples")
    @PreAuthorize(MODERATORS)
    @Transactional(readOnly = true)
    Map<String, Object> sample(@RequestParam String course) {
        Bank b = bank(course);
        UUID me = AuditContextHolder.current().map(AuditContext::actorId).orElse(null);
        Map<String, Object> out = new LinkedHashMap<>();
        // what waits in the bank, and how much of it the signed-in moderator may decide (never what they set themselves)
        Map<String, Object> w = jdbc.sql("""
                SELECT count(*) FILTER (WHERE q.moderation = 'PENDING' AND assessment.question_setter(q.id, q.version) IS DISTINCT FROM :me) AS for_me,
                       count(*) FILTER (WHERE q.moderation = 'PENDING' AND assessment.question_setter(q.id, q.version) IS NOT DISTINCT FROM :me) AS mine,
                       count(*) FILTER (WHERE q.moderation = 'RETURNED') AS returned,
                       count(*) FILTER (WHERE q.moderation = 'APPROVED') AS approved
                  FROM assessment.question q
                 WHERE CASE WHEN :sub::uuid IS NULL THEN q.course_code = :c ELSE q.jupeb_subject_id = :sub::uuid END AND q.archived_at IS NULL
                """).param("c", b.course(), Types.VARCHAR).param("sub", b.subject(), Types.OTHER).param("me", me, Types.OTHER).query().singleRow();
        out.put("waitingForMe", w.get("for_me"));
        out.put("waitingMine", w.get("mine"));
        out.put("returned", w.get("returned"));
        out.put("approved", w.get("approved"));
        UUID open = jdbc.sql("""
                SELECT id FROM assessment.question_moderation_sample
                 WHERE state = 'OPEN' AND drawn_by = :me AND coalesce(course_code, jupeb_subject_id::text) = coalesce(:c, :sub::uuid::text)
                """).param("me", me, Types.OTHER).param("c", b.course(), Types.VARCHAR).param("sub", b.subject(), Types.OTHER).query(UUID.class).optional().orElse(null);
        out.put("open", open == null ? null : sampleView(open));
        out.put("recent", jdbc.sql("""
                SELECT id, state, drawn_at, decided_at, cardinality(sample) AS size, cardinality(population) AS population, approved, left_as_they_were
                  FROM assessment.question_moderation_sample
                 WHERE drawn_by = :me AND state <> 'OPEN' AND coalesce(course_code, jupeb_subject_id::text) = coalesce(:c, :sub::uuid::text)
                 ORDER BY drawn_at DESC LIMIT 5
                """).param("me", me, Types.OTHER).param("c", b.course(), Types.VARCHAR).param("sub", b.subject(), Types.OTHER).query().listOfRows());
        return out;
    }

    @PostMapping("/api/v1/cbt/questions/samples")
    @PreAuthorize(MODERATORS)
    @Transactional
    Map<String, Object> drawSample(@Valid @RequestBody SampleIn in) {
        Bank b = bank(in.course());
        UUID id = jdbc.sql("SELECT id FROM assessment.question_sample_draw(:c, :sub, :n)").param("c", b.course(), Types.VARCHAR).param("sub", b.subject(), Types.OTHER)
                .param("n", in.size()).query(UUID.class).single();
        return sampleView(id);
    }

    /** the sample's bank, held to the acting office as a bank's name is */
    private void sampleBank(UUID id) {
        Map<String, Object> r = jdbc.sql("""
                SELECT s.course_code, js.code AS subject FROM assessment.question_moderation_sample s LEFT JOIN jupeb.subject js ON js.id = s.jupeb_subject_id WHERE s.id = :id
                """).param("id", id).query().listOfRows().stream().findFirst().orElseThrow(() -> new NotFound("sample", id.toString()));
        bank(r.get("course_code") != null ? (String) r.get("course_code") : JUPEB_PREFIX + r.get("subject"));
    }

    /** every sampled question approved: the rest approve together; one returned: the sample fails and the rest wait */
    @PostMapping("/api/v1/cbt/questions/samples/{id}/close")
    @PreAuthorize(MODERATORS)
    @Transactional
    Map<String, Object> closeSample(@PathVariable UUID id) {
        sampleBank(id);
        jdbc.sql("SELECT state FROM assessment.question_sample_close(:id)").param("id", id).query(String.class).single();
        return sampleView(id);
    }

    @PostMapping("/api/v1/cbt/questions/samples/{id}/withdraw")
    @PreAuthorize(MODERATORS)
    @Transactional
    Map<String, Object> withdrawSample(@PathVariable UUID id) {
        sampleBank(id);
        jdbc.sql("SELECT state FROM assessment.question_sample_withdraw(:id)").param("id", id).query(String.class).single();
        return sampleView(id);
    }

    /** every moderation decision on a question, newest first */
    @GetMapping("/api/v1/cbt/questions/{id}/moderation")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> moderationHistory(@PathVariable UUID id) {
        bankOf(id);
        return jdbc.sql("""
                SELECT m.version, m.decision, m.note, m.decided_at, m.decided_office,
                       CASE WHEN p.id IS NULL THEN NULL ELSE p.surname || ', ' || p.given_names END AS decided_by
                  FROM assessment.question_moderation m LEFT JOIN iam.person p ON p.id = m.decided_by
                 WHERE m.question_id = :id ORDER BY m.decided_at DESC
                """).param("id", id).query().listOfRows();
    }

    /** V364: every version of a question, as candidates were examined on it, and the attempts that drew each */
    @GetMapping("/api/v1/cbt/questions/{id}/versions")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> versions(@PathVariable UUID id) {
        bankOf(id);
        List<Map<String, Object>> rows = jdbc.sql("""
                SELECT v.version, v.kind, v.stem, v.options::text AS options, to_jsonb(v.answers)::text AS answers, v.explanation, v.marks, v.topic, v.difficulty, v.created_at,
                       CASE WHEN p.id IS NULL THEN NULL ELSE p.surname || ', ' || p.given_names END AS created_by,
                       (SELECT count(*) FROM assessment.cbt_attempt a, LATERAL unnest(a.question_ids, a.question_versions) u(qid, ver) WHERE u.qid = v.question_id AND u.ver = v.version) AS attempts
                  FROM assessment.question_version v LEFT JOIN iam.person p ON p.id = v.created_by
                 WHERE v.question_id = :id ORDER BY v.version DESC
                """).param("id", id).query().listOfRows();
        for (Map<String, Object> r : rows) {
            r.put("options", mapper.readValue(String.valueOf(r.get("options")), new tools.jackson.core.type.TypeReference<List<String>>() { }));
            r.put("answers", mapper.readValue(String.valueOf(r.get("answers")), new tools.jackson.core.type.TypeReference<List<Integer>>() { }));
        }
        return rows;
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
        Bank b = bank(body.course());
        Checked c = check(body.kind(), body.options(), body.answer(), body.answers());
        UUID id = jdbc.sql("""
                INSERT INTO assessment.question (course_code, jupeb_subject_id, topic, stem, options, answer, answers, kind, difficulty, marks, explanation, authored_by)
                VALUES (:c, :sub, :t, :s, :o::jsonb, :a, :as, :k, coalesce(:d, 'MEDIUM'), coalesce(:m, 1), :x, nullif(current_setting('moaum.actor_id', true), '')::uuid)
                RETURNING id
                """)
                .param("c", b.course(), Types.VARCHAR).param("sub", b.subject(), Types.OTHER).param("t", blank(body.topic()), Types.VARCHAR).param("s", body.stem().trim()).param("o", mapper.writeValueAsString(c.options()))
                .param("a", c.answer()).param("as", c.answers().toArray(new Integer[0])).param("k", c.kind())
                .param("d", body.difficulty() == null || body.difficulty().isBlank() ? null : body.difficulty().toUpperCase(), Types.VARCHAR)
                .param("m", body.marks(), Types.INTEGER).param("x", blank(body.explanation()), Types.VARCHAR)
                .query(UUID.class).single();
        return Map.of("id", id, "kind", c.kind(), "moderation", "PENDING");
    }

    /** an edit: a new version of the question (V364) — the attempts already sat keep the version they drew; refused while an examination drawing it is open */
    @PutMapping("/api/v1/cbt/questions/{id}")
    @PreAuthorize(AUTHORS)
    @Transactional
    Map<String, Object> edit(@PathVariable UUID id, @Valid @RequestBody QuestionEdit body) {
        Map<String, Object> q = jdbc.sql("""
                SELECT q.course_code, q.archived_at, assessment.question_in_live_exam(q.id) AS live FROM assessment.question q WHERE q.id = :id
                """).param("id", id).query().listOfRows().stream().findFirst().orElseThrow(() -> new NotFound("question", id.toString()));
        bankOf(id);
        Checked c = check(body.kind(), body.options(), body.answer(), body.answers());
        if (q.get("live") != null) {
            throw new DomainRuleViolation("CBT_QUESTION_IN_LIVE_EXAM", "This question is on the paper of " + q.get("live") + ", which is published to candidates; its paper is fixed until it closes.",
                    new DomainRuleViolation.Remedy("Correct it once the examination closes (or withdraw the examination if nobody has started it); the attempts already sat keep the version they drew, and a result is amended with a reason.", "You"));
        }
        if (q.get("archived_at") != null) {
            throw new DomainRuleViolation("CBT_QUESTION_ARCHIVED", "An archived question is kept as it was.", new DomainRuleViolation.Remedy("Restore it from the archive first.", "You"));
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
                            @Size(max = 40) String kind, @Size(max = 20) String difficulty, @Size(max = 20) String marks, @Size(max = 2000) String explanation,
                            @Size(max = 20) String courseCode, @Size(max = 20) String status) {
    }

    /** V364: allOrNothing (the default) imports nothing while any row has an error; false imports the valid rows and reports the rest */
    public record ImportIn(@NotBlank @Size(max = 30) String course, Boolean dryRun, @Size(max = 200) String fileName, Boolean allOrNothing, @NotNull @Size(max = 5000) List<@Valid ImportRow> rows) {
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
        Bank b = bank(in.course());
        String course = b.label();
        Map<String, Object> courseRow = (b.subject() != null
                ? jdbc.sql("SELECT code, cbt_enabled, CASE WHEN active THEN 'LIVE' ELSE 'ENDED' END AS state FROM jupeb.subject WHERE id = :s").param("s", b.subject())
                : jdbc.sql("SELECT code, cbt_enabled, state FROM catalogue.course WHERE code = :c").param("c", b.course()))
                .query().listOfRows().stream().findFirst().orElseThrow(() -> new NotFound("course", course));
        // V364: the CBT bank is filled for a course the University examines by CBT
        if (!Boolean.TRUE.equals(courseRow.get("cbt_enabled"))) {
            throw new DomainRuleViolation("CBT_COURSE_NOT_ENABLED", course + " is not a CBT course, so its CBT bank is not imported.",
                    new DomainRuleViolation.Remedy(b.subject() != null ? "The JUPEB Office allows a subject to be examined by CBT." : "The Academic Office, the Registry or Examinations and Records allows a course to be examined by CBT.",
                            b.subject() != null ? "JUPEB Office" : "Academic Office"));
        }
        if ("ENDED".equals(courseRow.get("state"))) {
            throw new DomainRuleViolation("CBT_COURSE_ENDED", course + " has ended.", new DomainRuleViolation.Remedy("Import into a running course.", "You"));
        }
        boolean dry = Boolean.TRUE.equals(in.dryRun());
        boolean allOrNothing = !Boolean.FALSE.equals(in.allOrNothing());
        Set<String> inBank = new java.util.HashSet<>(jdbc.sql("SELECT lower(regexp_replace(btrim(stem), '\\s+', ' ', 'g')) FROM assessment.question WHERE CASE WHEN :sub::uuid IS NULL THEN course_code = :c ELSE jupeb_subject_id = :sub::uuid END")
                .param("c", b.course(), Types.VARCHAR).param("sub", b.subject(), Types.OTHER).query(String.class).list());
        Set<String> seen = new java.util.HashSet<>();
        List<Map<String, Object>> findings = new java.util.ArrayList<>();
        int valid = 0, errors = 0, dupFile = 0, dupBank = 0, imported = 0;
        java.util.Map<String, Integer> tally = new java.util.TreeMap<>();
        // V364: judged whole first; written only when the batch may be written
        List<Object[]> toWrite = new java.util.ArrayList<>();
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
            // V364: the row's own course, when the sheet names one, is this course; never another, and never one created on the way
            if (r.courseCode() != null && !r.courseCode().isBlank()
                    && !norm(r.courseCode()).replace(" ", "").replaceFirst("^jupeb:", "").equals(norm(course).replace(" ", "").replaceFirst("^jupeb:", ""))) {
                codes.add("COURSE_MISMATCH"); messages.add("the row names " + r.courseCode().trim() + "; this import is for " + course);
            }
            boolean active = true;
            if (r.status() != null && !r.status().isBlank()) {
                String sv = r.status().trim().toUpperCase();
                if (Set.of("ACTIVE", "YES", "Y", "1", "LIVE").contains(sv)) active = true;
                else if (Set.of("INACTIVE", "NO", "N", "0", "RETIRED", "DRAFT").contains(sv)) active = false;
                else { codes.add("STATUS_INVALID"); messages.add("status is ACTIVE or INACTIVE"); }
            }
            for (String code : codes) tally.merge(code, 1, Integer::sum);
            String status;
            String key = norm(stem);
            if (!codes.isEmpty()) { status = "ERROR"; errors++; }
            else if (!key.isEmpty() && seen.contains(key)) { status = "DUPLICATE_IN_FILE"; dupFile++; messages.add("the same question appears earlier in the file"); }
            else if (!key.isEmpty() && inBank.contains(key)) { status = "ALREADY_IN_BANK"; dupBank++; messages.add("a question with this text is in the bank already; it is not added twice"); }
            else { status = "VALID"; valid++; }
            if (!key.isEmpty()) seen.add(key);
            Map<String, Object> f = new LinkedHashMap<>();
            if ("VALID".equals(status)) toWrite.add(new Object[] {f, r, stem, options, answers, kind, difficulty, marks, active});
            f.put("row", r.row()); f.put("stem", stem); f.put("topic", blank(r.topic())); f.put("kind", kind.startsWith("?") ? kind.substring(1) : kind); f.put("options", options.size());
            f.put("answers", answers.contains(-1) ? List.of() : answers); f.put("answer", r.answer()); f.put("difficulty", difficulty); f.put("marks", marks);
            f.put("active", active); f.put("status", status); f.put("codes", codes); f.put("messages", messages);
            findings.add(f);
        }
        boolean blocked = allOrNothing && errors > 0;
        if (!dry && !blocked) {
            for (Object[] w : toWrite) {
                @SuppressWarnings("unchecked") Map<String, Object> f = (Map<String, Object>) w[0];
                ImportRow r = (ImportRow) w[1];
                @SuppressWarnings("unchecked") List<Integer> answers = (List<Integer>) w[4];
                jdbc.sql("""
                        INSERT INTO assessment.question (course_code, jupeb_subject_id, topic, stem, options, answer, answers, kind, difficulty, marks, explanation, authored_by, active)
                        VALUES (:c, :sub, :t, :s, :o::jsonb, :a, :as, :k, :d, :m, :x, nullif(current_setting('moaum.actor_id', true), '')::uuid, :act)
                        """)
                        .param("c", b.course(), Types.VARCHAR).param("sub", b.subject(), Types.OTHER).param("t", blank(r.topic()), Types.VARCHAR).param("s", (String) w[2]).param("o", mapper.writeValueAsString(w[3]))
                        .param("a", answers.get(0)).param("as", answers.toArray(new Integer[0])).param("k", (String) w[5]).param("d", (String) w[6]).param("m", (int) w[7])
                        .param("x", blank(r.explanation()), Types.VARCHAR).param("act", (boolean) w[8]).update();
                f.put("status", "IMPORTED");
                imported++;
            }
        }
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("course", course);
        out.put("dryRun", dry);
        Map<String, Object> summary = new LinkedHashMap<>();
        summary.put("total", in.rows().size());
        summary.put("valid", valid);
        summary.put("errors", errors);
        summary.put("duplicatesInFile", dupFile);
        summary.put("alreadyInBank", dupBank);
        summary.put("imported", imported);
        summary.put("updated", 0);   // an import adds; a question already in the bank is edited on the bank, never overwritten by a sheet
        summary.put("byCode", tally);
        out.put("summary", summary);
        out.put("allOrNothing", allOrNothing);
        out.put("blocked", !dry && blocked);
        out.put("rows", findings);
        return out;
    }

    @PostMapping("/api/v1/cbt/questions/{id}/active")
    @PreAuthorize(AUTHORS)
    @Transactional
    Map<String, Object> setActive(@PathVariable UUID id, @RequestBody Active body) {
        bankOf(id);
        if (body.active() && jdbc.sql("SELECT archived_at IS NOT NULL FROM assessment.question WHERE id = :id").param("id", id).query(Boolean.class).single()) {
            throw new DomainRuleViolation("CBT_QUESTION_ARCHIVED", "An archived question is not made active.", new DomainRuleViolation.Remedy("Restore it from the archive first.", "You"));
        }
        jdbc.sql("UPDATE assessment.question SET active = :a WHERE id = :id").param("a", body.active()).param("id", id).update();
        return Map.of("id", id, "active", body.active());
    }

    /** V364: archived — retired and out of the bank's lists, never deleted; restored to the bank inactive */
    @PostMapping("/api/v1/cbt/questions/{id}/archive")
    @PreAuthorize(AUTHORS)
    @Transactional
    Map<String, Object> archive(@PathVariable UUID id, @RequestBody Archived body) {
        bankOf(id);
        if (body.archived()) {
            String live = jdbc.sql("SELECT assessment.question_in_live_exam(:id)").param("id", id).query(String.class).optional().orElse(null);
            if (live != null) {
                throw new DomainRuleViolation("CBT_QUESTION_IN_LIVE_EXAM", "This question is on the paper of " + live + ", which is published to candidates; its paper is fixed until it closes.",
                        new DomainRuleViolation.Remedy("Archive it once the examination closes.", "You"));
            }
        }
        jdbc.sql("UPDATE assessment.question SET active = CASE WHEN :a THEN false ELSE active END, archived_at = CASE WHEN :a THEN coalesce(archived_at, now()) ELSE NULL END WHERE id = :id")
                .param("a", body.archived()).param("id", id).update();
        return Map.of("id", id, "archived", body.archived());
    }

    private static String blank(String s) {
        return s == null || s.isBlank() ? null : s.trim();
    }
}
