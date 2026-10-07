package ng.edu.moaum.portal.jupeb;

import java.io.ByteArrayOutputStream;
import java.sql.Types;
import java.time.LocalDate;
import java.time.LocalTime;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.zip.ZipEntry;
import java.util.zip.ZipOutputStream;

import jakarta.validation.Valid;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

import ng.edu.moaum.portal.shared.AuditContextHolder;
import ng.edu.moaum.portal.shared.DomainRuleViolation;
import ng.edu.moaum.portal.shared.FileObjects;
import ng.edu.moaum.portal.shared.NotFound;

import org.springframework.http.CacheControl;
import org.springframework.http.ContentDisposition;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * The JUPEB Office's examination year (V355): registering the candidates with the Board (each record ready to send, exported with
 * the photographs, followed through the Board's stages, a record changed since it was sent flagged with what changed), the
 * continuous assessment (the session's parts and their maxima, each subject's sheet, locked for the Board, unlocked only with a
 * reason), and the examination timetable (its papers uploaded or entered, published to the students). The Board's own formats are
 * not invented: the exports carry every fact asked for. Reads for jupeb, super and admin; writes for jupeb and super.
 */
@RestController
@RequestMapping("/api/v1/jupeb/office")
class JupebExamYearController {

    private final JdbcClient jdbc;
    private final FileObjects files;
    private final tools.jackson.databind.ObjectMapper json;

    JupebExamYearController(JdbcClient jdbc, FileObjects files, tools.jackson.databind.ObjectMapper json) {
        this.jdbc = jdbc;
        this.files = files;
        this.json = json;
    }

    private static UUID actor() {
        return AuditContextHolder.required().actorId();
    }

    private static String office() {
        return AuditContextHolder.required().actorOffice();
    }

    private String sessionOr(String session) {
        return session == null || session.isBlank() ? jdbc.sql("SELECT jupeb.current_session()").query(String.class).single() : session.trim();
    }

    private Object marker(String s, String marker) {
        return jdbc.sql("""
                SELECT starts_on::text AS starts_on, ends_on::text AS ends_on, deadline_on::text AS deadline_on, title, deadline_note
                  FROM jupeb.calendar_event WHERE session = :s AND marker = :m AND removed_at IS NULL
                """).param("s", s).param("m", marker).query().listOfRows().stream().findFirst().orElse(null);
    }

    /* ── registering the candidates with the Board ── */

    @GetMapping("/board")
    @PreAuthorize(JupebOfficeController.READ)
    @Transactional(readOnly = true)
    Map<String, Object> board(@RequestParam(required = false) String session) {
        String s = sessionOr(session);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("session", s);
        out.put("registration", marker(s, "BOARD_REGISTRATION"));
        out.put("alignment", marker(s, "BOARD_DATA_ALIGNMENT"));
        out.put("penalty", marker(s, "BOARD_PENALTY_ALIGNMENT"));
        out.put("rows", jdbc.sql("""
                SELECT application_id, application_no, name, class_name, combination_code, exam_no, stage, board_ref, sent_at, updated_at, note,
                       array_to_json(problems)::text AS problems, ready, changed, array_to_json(changed_facts)::text AS changed_facts
                  FROM jupeb.board_status(:s)
                """).param("s", s).query().listOfRows().stream().map(r -> {
                    Map<String, Object> m = new LinkedHashMap<>(r);
                    m.put("problems", JupebView.readJson(String.valueOf(r.get("problems"))));
                    m.put("changed_facts", JupebView.readJson(String.valueOf(r.get("changed_facts"))));
                    return m;
                }).toList());
        return out;
    }

    public record MarkIn(@NotBlank @Pattern(regexp = "^\\d{4}/\\d{4}$") String session, @NotNull @Size(min = 1, max = 2000) List<UUID> applicationIds,
                         @NotBlank @Pattern(regexp = "SENT|CONFIRMED|CORRECTION_NEEDED|CORRECTED|WITHDRAWN") String stage, @Size(max = 500) String note,
                         @Size(max = 60) String boardRef) {
    }

    /** the Board's stage of the students given — sent and corrected take the record as it stands, and only when it is ready */
    @PostMapping("/board/mark")
    @PreAuthorize(JupebOfficeController.WRITE)
    @Transactional
    Map<String, Object> mark(@Valid @RequestBody MarkIn b) {
        int n = jdbc.sql("SELECT jupeb.board_mark(:a, :s, :st, :n, :r, :by, :o)").param("a", b.applicationIds().toArray(new UUID[0])).param("s", b.session())
                .param("st", b.stage()).param("n", b.note(), Types.VARCHAR).param("r", b.boardRef(), Types.VARCHAR).param("by", actor()).param("o", office(), Types.VARCHAR)
                .query(Integer.class).single();
        Map<String, Object> out = new LinkedHashMap<>(board(b.session()));
        out.put("marked", n);
        return out;
    }

    private List<Map<String, Object>> chosen(String s, String which) {
        String w = which == null ? "ready" : which.trim().toLowerCase();
        return jdbc.sql("""
                SELECT st.application_id, st.application_no, st.stage, st.changed, jupeb.board_facts(st.application_id)::text AS facts
                  FROM jupeb.board_status(:s) st
                 WHERE CASE :w WHEN 'ready' THEN st.stage = 'NOT_SENT' AND st.ready WHEN 'changed' THEN st.changed OR st.stage = 'CORRECTION_NEEDED'
                               WHEN 'sent' THEN st.stage <> 'NOT_SENT' AND st.stage <> 'WITHDRAWN' ELSE st.ready END
                """).param("s", s).param("w", w).query().listOfRows();
    }

    /** the records to send (ready and not sent; changed since sent; or every one sent), each with every fact the Board asks for */
    @GetMapping("/board/export")
    @PreAuthorize(JupebOfficeController.READ)
    @Transactional(readOnly = true)
    List<Map<String, Object>> export(@RequestParam(required = false) String session, @RequestParam(required = false) String which) {
        return chosen(sessionOr(session), which).stream().map(r -> {
            Map<String, Object> m = new LinkedHashMap<>();
            m.put("application_id", r.get("application_id"));
            m.put("application_no", r.get("application_no"));
            m.put("stage", r.get("stage"));
            m.put("changed", r.get("changed"));
            m.put("facts", JupebView.readJson(String.valueOf(r.get("facts"))));
            m.put("photo", photoName(String.valueOf(r.get("application_no"))));
            return m;
        }).toList();
    }

    private static String photoName(String applicationNo) {
        return applicationNo.replaceAll("[^A-Za-z0-9._-]+", "-") + ".jpg";
    }

    /** the same records' passport photographs, one JPEG each named by the application number, in a ZIP */
    @GetMapping("/board/photos.zip")
    @PreAuthorize(JupebOfficeController.READ)
    @Transactional(readOnly = true)
    ResponseEntity<byte[]> photos(@RequestParam(required = false) String session, @RequestParam(required = false) String which) {
        String s = sessionOr(session);
        ByteArrayOutputStream bytes = new ByteArrayOutputStream();
        int n = 0;
        try (ZipOutputStream zip = new ZipOutputStream(bytes)) {
            for (Map<String, Object> r : chosen(s, which)) {
                byte[] jpeg;
                try {
                    jpeg = JupebDocuments.stream(jdbc, files, (UUID) r.get("application_id"), "PASSPORT", null, true).getBody();
                } catch (NotFound none) {
                    continue;
                }
                if (jpeg == null) continue;
                zip.putNextEntry(new ZipEntry(photoName(String.valueOf(r.get("application_no")))));
                zip.write(jpeg);
                zip.closeEntry();
                n++;
            }
        } catch (java.io.IOException e) {
            throw new IllegalStateException("the photographs could not be bundled", e);
        }
        return ResponseEntity.ok().contentType(MediaType.parseMediaType("application/zip")).cacheControl(CacheControl.noStore())
                .header("Content-Disposition", ContentDisposition.attachment().filename("jupeb-board-photos-" + s.replace('/', '-') + ".zip").build().toString())
                .header("X-Photos", String.valueOf(n)).body(bytes.toByteArray());
    }

    /* ── continuous assessment ── */

    @GetMapping("/ca/components")
    @PreAuthorize(JupebOfficeController.READ)
    @Transactional(readOnly = true)
    Map<String, Object> components(@RequestParam(required = false) String session) {
        String s = sessionOr(session);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("session", s);
        out.put("components", jdbc.sql("SELECT id, code, title, max_score, ord, active FROM jupeb.ca_component WHERE session = :s ORDER BY ord, code").param("s", s).query().listOfRows());
        out.put("due", marker(s, "CA_SUBMISSION"));
        out.put("progress", jdbc.sql("SELECT * FROM jupeb.ca_progress(:s)").param("s", s).query().listOfRows());
        out.put("classes", jdbc.sql("SELECT id, name FROM jupeb.class WHERE session = :s ORDER BY name").param("s", s).query().listOfRows());
        return out;
    }

    public record ComponentIn(@NotBlank @Pattern(regexp = "^[A-Za-z0-9_]{1,20}$") String code, @NotBlank @Size(min = 2, max = 80) String title,
                              @NotNull @jakarta.validation.constraints.DecimalMin("0.5") @jakarta.validation.constraints.DecimalMax("1000") java.math.BigDecimal maxScore,
                              @Min(1) @Max(50) int ord, boolean active) {
    }

    public record ComponentsIn(@NotBlank @Pattern(regexp = "^\\d{4}/\\d{4}$") String session, @NotNull @Size(max = 12) List<@Valid ComponentIn> components) {
    }

    /** the session's parts of the assessment, each with its maximum — never below a score already entered; a part not listed is set aside, its scores kept */
    @PutMapping("/ca/components")
    @PreAuthorize(JupebOfficeController.WRITE)
    @Transactional
    Map<String, Object> saveComponents(@Valid @RequestBody ComponentsIn b) {
        for (ComponentIn c : b.components()) {
            String code = c.code().trim().toUpperCase();
            boolean below = jdbc.sql("""
                    SELECT EXISTS (SELECT 1 FROM jupeb.ca_score x JOIN jupeb.ca_component k ON k.id = x.component_id WHERE k.session = :s AND k.code = :c AND x.score > :m)
                    """).param("s", b.session()).param("c", code).param("m", c.maxScore()).query(Boolean.class).single();
            if (below) throw new DomainRuleViolation("JUPEB_CA_MAX_BELOW", c.title() + ": a score already entered is above " + c.maxScore().stripTrailingZeros().toPlainString() + ".",
                    new DomainRuleViolation.Remedy("Keep the maximum at or above the scores entered, or correct those first.", "JUPEB Office"));
            jdbc.sql("""
                    INSERT INTO jupeb.ca_component (session, code, title, max_score, ord, active, created_by) VALUES (:s, :c, :t, :m, :o, :a, :by)
                    ON CONFLICT (session, code) DO UPDATE SET title = EXCLUDED.title, max_score = EXCLUDED.max_score, ord = EXCLUDED.ord, active = EXCLUDED.active
                    """).param("s", b.session()).param("c", code).param("t", c.title().trim()).param("m", c.maxScore()).param("o", c.ord()).param("a", c.active())
                    .param("by", actor()).update();
        }
        List<String> kept = b.components().stream().map(c -> c.code().trim().toUpperCase()).toList();
        jdbc.sql("UPDATE jupeb.ca_component SET active = false WHERE session = :s AND NOT (code = ANY (:k))").param("s", b.session()).param("k", kept.toArray(new String[0])).update();
        return components(b.session());
    }

    /** a subject's sheet: each student's score in each part, the total and whether it is complete; and whether the subject is locked */
    @GetMapping("/ca/sheet")
    @PreAuthorize(JupebOfficeController.READ)
    @Transactional(readOnly = true)
    Map<String, Object> sheet(@RequestParam(required = false) String session, @RequestParam UUID subject, @RequestParam(required = false) UUID klass) {
        return JupebView.caSheet(jdbc, sessionOr(session), subject, klass);
    }

    public record ScoreIn(@NotNull UUID applicationId, @NotNull UUID componentId, java.math.BigDecimal score) {
    }

    public record ScoresIn(@NotNull UUID subjectId, @NotNull @Size(max = 3000) List<@Valid ScoreIn> scores) {
    }

    @PutMapping("/ca/scores")
    @PreAuthorize(JupebOfficeController.WRITE)
    @Transactional
    Map<String, Object> saveScores(@Valid @RequestBody ScoresIn b) {
        for (ScoreIn x : b.scores()) {
            jdbc.sql("SELECT jupeb.ca_save(:a, :s, :c, :v, :by, :o)").param("a", x.applicationId()).param("s", b.subjectId()).param("c", x.componentId())
                    .param("v", x.score(), Types.NUMERIC).param("by", actor()).param("o", office(), Types.VARCHAR).query().listOfRows();
        }
        String s = jdbc.sql("SELECT session FROM jupeb.application WHERE id = :a").param("a", b.scores().isEmpty() ? new UUID(0, 0) : b.scores().get(0).applicationId())
                .query(String.class).optional().orElse(sessionOr(null));
        return JupebView.caSheet(jdbc, s, b.subjectId(), null);
    }

    public record LockIn(@NotBlank @Pattern(regexp = "^\\d{4}/\\d{4}$") String session, @NotNull UUID subjectId, @Size(max = 500) String reason) {
    }

    /** a subject's assessment locked — its scores final for the Board */
    @PostMapping("/ca/lock")
    @PreAuthorize(JupebOfficeController.WRITE)
    @Transactional
    Map<String, Object> lock(@Valid @RequestBody LockIn b) {
        try {
            jdbc.sql("INSERT INTO jupeb.ca_lock (session, subject_id, locked_by) VALUES (:s, :sub, :by)").param("s", b.session()).param("sub", b.subjectId()).param("by", actor()).update();
        } catch (org.springframework.dao.DuplicateKeyException twice) {
            throw new DomainRuleViolation("JUPEB_CA_LOCKED", "The subject's assessment is already locked.", new DomainRuleViolation.Remedy("Nothing more is needed.", "JUPEB Office"));
        }
        return JupebView.caSheet(jdbc, b.session(), b.subjectId(), null);
    }

    /** unlocked, only with the reason, kept with who and when */
    @PostMapping("/ca/unlock")
    @PreAuthorize(JupebOfficeController.WRITE)
    @Transactional
    Map<String, Object> unlock(@Valid @RequestBody LockIn b) {
        if (b.reason() == null || b.reason().trim().length() < 5) {
            throw new DomainRuleViolation("JUPEB_CA_UNLOCK_REASON", "Say why the subject's assessment is unlocked.", new DomainRuleViolation.Remedy("Give the reason in a few words.", "JUPEB Office"));
        }
        int n = jdbc.sql("UPDATE jupeb.ca_lock SET unlocked_at = now(), unlocked_by = :by, unlock_reason = :r WHERE session = :s AND subject_id = :sub AND unlocked_at IS NULL")
                .param("by", actor()).param("r", b.reason().trim()).param("s", b.session()).param("sub", b.subjectId()).update();
        if (n == 0) throw new NotFound("locked assessment", b.subjectId());
        return JupebView.caSheet(jdbc, b.session(), b.subjectId(), null);
    }

    /* ── the examination timetable ── */

    @GetMapping("/exams")
    @PreAuthorize(JupebOfficeController.READ)
    @Transactional(readOnly = true)
    Map<String, Object> exams(@RequestParam(required = false) String session) {
        String s = sessionOr(session);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("session", s);
        out.put("published", jdbc.sql("SELECT published_at FROM jupeb.exam_timetable WHERE session = :s").param("s", s).query().listOfRows().stream().findFirst()
                .map(r -> r.get("published_at")).orElse(null));
        out.put("release", marker(s, "EXAM_TIMETABLE"));
        out.put("examinations", marker(s, "EXAMINATIONS"));
        out.put("papers", jdbc.sql("""
                SELECT p.id, p.subject_id, s.code, s.title AS subject, p.board_subject_id, b.title AS option_title, b.prefix, p.title, p.kind, p.sits_on::text AS sits_on,
                       to_char(p.starts_at, 'HH24:MI') AS starts_at, to_char(p.ends_at, 'HH24:MI') AS ends_at, p.centre, p.note,
                       (SELECT count(*) FROM jupeb.subject_registration r JOIN jupeb.application a ON a.id = r.application_id
                         WHERE r.subject_id = p.subject_id AND a.session = p.session AND a.state = 'STUDENT'
                           AND (p.board_subject_id IS NULL OR r.board_subject_id IS NULL OR r.board_subject_id = p.board_subject_id)) AS candidates
                  FROM jupeb.exam_paper p JOIN jupeb.subject s ON s.id = p.subject_id LEFT JOIN jupeb.board_subject b ON b.id = p.board_subject_id
                 WHERE p.session = :s AND p.active ORDER BY p.sits_on, p.starts_at, s.title
                """).param("s", s).query().listOfRows());
        out.put("subjects", jdbc.sql("""
                SELECT s.id, s.code, s.title, NULL::uuid AS board_subject_id FROM jupeb.subject s WHERE s.active
                UNION ALL
                SELECT b.subject_id, b.prefix, b.title, b.id FROM jupeb.board_subject b WHERE (SELECT count(*) FROM jupeb.board_subject y WHERE y.subject_id = b.subject_id) > 1
                 ORDER BY 3
                """).query().listOfRows());
        return out;
    }

    public record UploadIn(@NotBlank @Pattern(regexp = "^\\d{4}/\\d{4}$") String session, @NotNull @Size(max = 500) List<Map<String, Object>> rows, boolean replace) {
    }

    @PostMapping("/exams/upload")
    @PreAuthorize(JupebOfficeController.WRITE)
    @Transactional
    Map<String, Object> upload(@Valid @RequestBody UploadIn b) {
        String r = jdbc.sql("SELECT jupeb.exam_paper_upload(:s, :r::jsonb, :rep, :by)::text").param("s", b.session()).param("r", json.writeValueAsString(b.rows()))
                .param("rep", b.replace()).param("by", actor()).query(String.class).single();
        Map<String, Object> out = new LinkedHashMap<>(exams(b.session()));
        out.put("result", JupebView.readJson(r));
        return out;
    }

    public record PaperIn(@NotBlank @Pattern(regexp = "^\\d{4}/\\d{4}$") String session, @NotNull UUID subjectId, UUID boardSubjectId,
                          @NotBlank @Size(min = 2, max = 160) String title, @Pattern(regexp = "CBT|PAPER|PRACTICAL|ORAL") String kind, @NotNull LocalDate sitsOn,
                          @NotNull LocalTime startsAt, @NotNull LocalTime endsAt, @Size(max = 160) String centre, @Size(max = 300) String note) {
    }

    @PostMapping("/exams")
    @PreAuthorize(JupebOfficeController.WRITE)
    @Transactional
    Map<String, Object> addPaper(@Valid @RequestBody PaperIn b) {
        if (!b.endsAt().isAfter(b.startsAt())) throw new DomainRuleViolation("JUPEB_EXAM_TIME", "A paper ends after it starts.", new DomainRuleViolation.Remedy("Correct the times.", "JUPEB Office"));
        jdbc.sql("""
                INSERT INTO jupeb.exam_paper (session, subject_id, board_subject_id, title, kind, sits_on, starts_at, ends_at, centre, note, created_by)
                VALUES (:s, :sub, :b, :t, coalesce(:k, 'PAPER'), :d, :st, :en, :c, :n, :by)
                """).param("s", b.session()).param("sub", b.subjectId()).param("b", b.boardSubjectId(), Types.OTHER).param("t", b.title().trim()).param("k", b.kind(), Types.VARCHAR)
                .param("d", b.sitsOn()).param("st", b.startsAt()).param("en", b.endsAt()).param("c", b.centre(), Types.VARCHAR).param("n", b.note(), Types.VARCHAR).param("by", actor()).update();
        return exams(b.session());
    }

    @PutMapping("/exams/{id}")
    @PreAuthorize(JupebOfficeController.WRITE)
    @Transactional
    Map<String, Object> editPaper(@PathVariable UUID id, @Valid @RequestBody PaperIn b) {
        if (!b.endsAt().isAfter(b.startsAt())) throw new DomainRuleViolation("JUPEB_EXAM_TIME", "A paper ends after it starts.", new DomainRuleViolation.Remedy("Correct the times.", "JUPEB Office"));
        int n = jdbc.sql("""
                UPDATE jupeb.exam_paper SET subject_id = :sub, board_subject_id = :b, title = :t, kind = coalesce(:k, kind), sits_on = :d, starts_at = :st, ends_at = :en,
                       centre = :c, note = :n WHERE id = :id AND active
                """).param("sub", b.subjectId()).param("b", b.boardSubjectId(), Types.OTHER).param("t", b.title().trim()).param("k", b.kind(), Types.VARCHAR).param("d", b.sitsOn())
                .param("st", b.startsAt()).param("en", b.endsAt()).param("c", b.centre(), Types.VARCHAR).param("n", b.note(), Types.VARCHAR).param("id", id).update();
        if (n == 0) throw new NotFound("examination paper", id);
        return exams(b.session());
    }

    @PostMapping("/exams/{id}/remove")
    @PreAuthorize(JupebOfficeController.WRITE)
    @Transactional
    Map<String, Object> removePaper(@PathVariable UUID id) {
        String s = jdbc.sql("UPDATE jupeb.exam_paper SET active = false WHERE id = :id AND active RETURNING session").param("id", id).query(String.class).optional()
                .orElseThrow(() -> new NotFound("examination paper", id));
        return exams(s);
    }

    public record PublishIn(@NotBlank @Pattern(regexp = "^\\d{4}/\\d{4}$") String session, boolean published) {
    }

    /** the timetable shown to the students (their own papers, and admit cards to those cleared), or held back again */
    @PostMapping("/exams/publish")
    @PreAuthorize(JupebOfficeController.WRITE)
    @Transactional
    Map<String, Object> publish(@Valid @RequestBody PublishIn b) {
        if (b.published() && !jdbc.sql("SELECT EXISTS (SELECT 1 FROM jupeb.exam_paper WHERE session = :s AND active)").param("s", b.session()).query(Boolean.class).single()) {
            throw new DomainRuleViolation("JUPEB_EXAM_EMPTY", "The timetable has no papers yet.", new DomainRuleViolation.Remedy("Upload the Board's timetable first.", "JUPEB Office"));
        }
        jdbc.sql("""
                INSERT INTO jupeb.exam_timetable (session, published_at, published_by) VALUES (:s, CASE WHEN :p THEN now() END, :by)
                ON CONFLICT (session) DO UPDATE SET published_at = CASE WHEN :p THEN now() END, published_by = :by, updated_at = now()
                """).param("s", b.session()).param("p", b.published()).param("by", actor()).update();
        return exams(b.session());
    }

    /** a student's own papers, as the office sees them (published or not) */
    @GetMapping("/applications/{id}/exams")
    @PreAuthorize(JupebOfficeController.READ)
    @Transactional(readOnly = true)
    List<Map<String, Object>> schedule(@PathVariable UUID id) {
        return jdbc.sql("SELECT *, sits_on::text AS day FROM jupeb.exam_schedule(:a, true)").param("a", id).query().listOfRows();
    }

    /** a subject's practice by syllabus topic across the session's students (one class, or all) */
    @GetMapping("/practice-topics")
    @PreAuthorize(JupebOfficeController.READ)
    @Transactional(readOnly = true)
    List<Map<String, Object>> practiceTopics(@RequestParam(required = false) String session, @RequestParam UUID subject, @RequestParam(required = false) UUID klass) {
        return jdbc.sql("SELECT * FROM jupeb.practice_topics_class(:s, :sub, :k)").param("s", sessionOr(session)).param("sub", subject).param("k", klass, Types.OTHER)
                .query().listOfRows();
    }
}
