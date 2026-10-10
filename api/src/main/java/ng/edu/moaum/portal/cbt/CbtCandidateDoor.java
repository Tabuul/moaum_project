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
import ng.edu.moaum.portal.shared.CheckCodes;
import ng.edu.moaum.portal.shared.DomainRuleViolation;
import ng.edu.moaum.portal.shared.FileObjects;
import ng.edu.moaum.portal.shared.NotFound;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Component;

/**
 * The candidate's side of the CBT engine (V322; both kinds of candidate from V365): the examinations of a candidate, the start, the paper
 * without its keys, the answers saved as they go, the browser's reports, the camera's consent, the submission, and the result once it is
 * released. One implementation behind two doors — the University student's (/api/v1/me/cbt) and the JUPEB student's (/api/v1/jupeb/me/cbt)
 * — each of which settles who the candidate is before it calls here. Every call is the candidate's own: the attempt must be theirs, and the
 * examination screen must hold the attempt's token — an examination URL is never the authorisation.
 */
@Component
class CbtCandidateDoor {

    /** the kind of candidate: where their attempts are owned, and which list names their examinations */
    enum Kind {
        STUDENT("student_id", "assessment.cbt_student_exams"),
        JUPEB("jupeb_application_id", "assessment.cbt_jupeb_exams"),
        /** V385: a Post-UTME applicant (admissions.application), through the public JAMB-number door */
        PUTME("application_id", "assessment.cbt_putme_exams");

        final String owner;
        final String list;

        Kind(String owner, String list) {
            this.owner = owner;
            this.list = list;
        }
    }

    /** an answer as the screen sends it: the options chosen (absent = unchanged), the screen's own count of its saves of the question, and the review mark (V364) */
    public record AnswerIn(@NotNull UUID q, List<Integer> a, Long seq, Boolean flag) {
    }

    public record AnswersIn(@NotNull @Size(max = 500) List<@Valid AnswerIn> answers) {
    }

    /** what the screen saw, the question it was on and how long it lasted (V364) */
    public record EventIn(@NotBlank @Size(max = 40) String kind, @Size(max = 500) String detail, Integer n, Long ms) {
    }

    public record EventsIn(@NotNull @Size(max = 100) List<@Valid EventIn> events) {
    }

    public record CameraIn(@NotNull Boolean consent) {
    }

    private final JdbcClient jdbc;
    private final CheckCodes codes;
    private final FileObjects files;
    private final tools.jackson.databind.ObjectMapper mapper = new tools.jackson.databind.ObjectMapper();

    CbtCandidateDoor(JdbcClient jdbc, CheckCodes codes, FileObjects files) {
        this.jdbc = jdbc;
        this.codes = codes;
        this.files = files;
    }

    /** V376: an image on the candidate's paper — only inside their own running attempt, held by this screen, that drew it */
    org.springframework.http.ResponseEntity<byte[]> image(Kind kind, UUID me, UUID attempt, String token, UUID image) {
        own(kind, attempt, me);
        boolean ok = jdbc.sql("""
                SELECT EXISTS (SELECT 1 FROM assessment.cbt_attempt a WHERE a.id = :a AND a.token = :t AND a.status = 'IN_PROGRESS')
                       AND assessment.cbt_attempt_shows_image(:a, :i)
                """).param("a", attempt).param("t", token(token)).param("i", image).query(Boolean.class).single();
        if (!ok) throw new NotFound("image", image.toString());
        return CbtQuestionImages.stream(jdbc, files, image);
    }

    /** V375: what a CBT slip's QR carries — the examination, the candidate, and the check code the API signs for the pair */
    static String slipToken(CheckCodes codes, UUID exam, UUID candidate) {
        return exam + "." + candidate + "." + codes.sign(CheckCodes.Kind.CBT_SLIP, exam.toString(), candidate.toString());
    }

    /** the candidate's name, number and (a student's) level, each named, so the candidate and the invigilator see whose paper it is */
    private Map<String, Object> candidate(Kind kind, UUID me) {
        if (kind == Kind.PUTME) {
            // V385: the Post-UTME candidate by JAMB registration number — the one identifier the examination knows them by
            return jdbc.sql("""
                    SELECT upper(c.surname) AS surname, c.other_names, c.jamb_reg_no AS number, 'JAMB Reg. No.' AS number_label, c.programme, a.application_no
                      FROM admissions.application a JOIN admissions.candidate c ON c.id = a.candidate_id WHERE a.id = :s
                    """).param("s", me).query().singleRow();
        }
        return kind == Kind.JUPEB
                ? jdbc.sql("""
                        SELECT upper(surname) AS surname, first_name || coalesce(' ' || middle_name, '') AS other_names, coalesce(exam_no, application_no) AS number,
                               CASE WHEN exam_no IS NOT NULL THEN 'JUPEB No.' ELSE 'Application No.' END AS number_label
                          FROM jupeb.application WHERE id = :s
                        """).param("s", me).query().singleRow()
                : jdbc.sql("""
                        SELECT s.surname, s.other_names, coalesce(s.matric_no, s.admission_no) AS number,
                               CASE WHEN s.matric_no IS NOT NULL THEN 'Matric No.' ELSE 'Admission No.' END AS number_label, s.current_level AS level, p.name AS programme
                          FROM people.student s LEFT JOIN ref.programme p ON p.code = s.programme_code WHERE s.id = :s
                        """).param("s", me).query().singleRow();
    }

    /** V375: the candidate's CBT slip — the examination, their sitting and seat, who they are, and the signed code its QR carries — once they have a seat */
    Map<String, Object> slip(Kind kind, UUID me, UUID exam) {
        Map<String, Object> row = one(kind, me, exam);
        if (row.get("sitting") == null) {
            throw new DomainRuleViolation("CBT_NO_SITTING", "You have no seat in this examination's sittings yet, so there is no slip to print.",
                    new DomainRuleViolation.Remedy("The examination office seats every candidate; your slip is here once you have a seat.", "The examining office"));
        }
        Map<String, Object> out = new LinkedHashMap<>();
        for (String k : List.of("exam_id", "reference", "course_code", "course_title", "title", "session", "semester", "duration_minutes", "starts_at", "ends_at",
                "sitting", "sitting_venue", "sitting_starts_at", "sitting_ends_at", "seat_no", "late_entry_until", "extra_minutes")) {
            out.put(k, row.get(k));
        }
        out.put("candidate", candidate(kind, me));
        out.put("token", slipToken(codes, exam, me));
        return out;
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
                new DomainRuleViolation.Remedy("Open the examination again from CBT Examinations.", "You"));
    }

    /** the attempt's examination, if the attempt is the candidate's */
    UUID own(Kind kind, UUID attempt, UUID me) {
        return jdbc.sql("SELECT exam_id FROM assessment.cbt_attempt WHERE id = :a AND " + kind.owner + " = :s").param("a", attempt).param("s", me)
                .query(UUID.class).optional().orElseThrow(() -> new NotFound("attempt", attempt.toString()));
    }

    private String sessionFor(Kind kind, UUID me) {
        if (kind == Kind.JUPEB) {
            return jdbc.sql("SELECT session FROM jupeb.application WHERE id = :s").param("s", me).query(String.class).optional().orElse(null);
        }
        if (kind == Kind.PUTME) {
            return jdbc.sql("SELECT session FROM admissions.application WHERE id = :s").param("s", me).query(String.class).optional().orElse(null);
        }
        return jdbc.sql("""
                SELECT coalesce((SELECT cr.session FROM registration.course_registration cr WHERE cr.student_id = :s ORDER BY cr.session DESC LIMIT 1),
                                (SELECT name FROM policy.academic_session ORDER BY (state = 'CURRENT') DESC, (state = 'OPEN') DESC, name DESC LIMIT 1))
                """).param("s", me).query(String.class).optional().orElse(null);
    }

    /* ── the list and one examination ── */

    Map<String, Object> list(Kind kind, UUID me, String session) {
        String ses = session == null || session.isBlank() ? sessionFor(kind, me) : session.trim();
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("session", ses);
        out.put("rows", jdbc.sql("SELECT * FROM " + kind.list + "(:s, :ses)").param("s", me).param("ses", ses, Types.VARCHAR).query().listOfRows()
                .stream().map(r -> placed(new LinkedHashMap<>(r), me)).toList());
        out.put("now", OffsetDateTime.now());
        return out;
    }

    Map<String, Object> one(Kind kind, UUID me, UUID exam) {
        Map<String, Object> row = jdbc.sql("SELECT * FROM " + kind.list + "(:s, NULL) x WHERE x.exam_id = :e").param("s", me).param("e", exam)
                .query().listOfRows().stream().findFirst().orElseThrow(() -> new NotFound("examination", exam.toString()));
        Map<String, Object> out = placed(new LinkedHashMap<>(row), me);
        out.put("now", OffsetDateTime.now());
        return out;
    }

    /** V373: where and when the candidate sits the examination (their sitting and seat), and any extra time they were given;
     *  V374: until when they may still start on their own, and the invigilator's mark (absent, or admitted late with minutes given back) */
    private Map<String, Object> placed(Map<String, Object> row, UUID me) {
        Object exam = row.get("exam_id");
        if (exam == null) return row;
        jdbc.sql("""
                SELECT s.label AS sitting, s.venue AS sitting_venue, s.starts_at AS sitting_starts_at, s.ends_at AS sitting_ends_at, x.seat_no,
                       CASE WHEN e.late_entry_minutes IS NULL THEN NULL ELSE s.starts_at + make_interval(mins => e.late_entry_minutes) END AS late_entry_until,
                       m.status AS attendance, m.minutes_given AS late_minutes_given
                  FROM assessment.cbt_seat x JOIN assessment.cbt_sitting s ON s.id = x.sitting_id JOIN assessment.cbt_exam e ON e.id = x.exam_id
                  LEFT JOIN assessment.cbt_attendance m ON m.sitting_id = s.id AND m.candidate_id = x.candidate_id
                 WHERE x.exam_id = :e AND x.candidate_id = :c
                """).param("e", exam).param("c", me).query().listOfRows().stream().findFirst().ifPresent(row::putAll);
        jdbc.sql("SELECT minutes FROM assessment.cbt_extra_time WHERE exam_id = :e AND candidate_id = :c").param("e", exam).param("c", me)
                .query(Integer.class).optional().ifPresent(m -> row.put("extra_minutes", m));
        return row;
    }

    /* ── the attempt ── */

    /** start, or return to, the attempt: eligibility is the database's judgement; the token is the screen's key */
    Map<String, Object> start(Kind kind, UUID me, UUID exam, String agent) {
        // the examination must be one of the candidate's: a URL guessed for another course or subject is not
        jdbc.sql("SELECT 1 FROM " + kind.list + "(:s, NULL) x WHERE x.exam_id = :e").param("s", me).param("e", exam).query().listOfRows().stream().findFirst()
                .orElseThrow(() -> new NotFound("examination", exam.toString()));
        Map<String, Object> a = jdbc.sql("SELECT * FROM assessment.cbt_start(:e, :s, :ip, :ua)")
                .param("e", exam).param("s", me).param("ip", ip(), Types.VARCHAR).param("ua", agent == null ? null : agent.substring(0, Math.min(agent.length(), 300)), Types.VARCHAR)
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
    Map<String, Object> attempt(Kind kind, UUID me, UUID id, String token) {
        UUID exam = own(kind, id, me);
        Map<String, Object> a = jdbc.sql("SELECT * FROM assessment.cbt_touch(:a, :t)").param("a", id).param("t", token(token)).query().singleRow();
        Map<String, Object> e = CbtExamController.plain(jdbc.sql("""
                SELECT e.id, e.reference, e.title, coalesce(e.course_code, js.code) AS course_code, coalesce(c.title, js.title) AS course_title, e.session, e.semester,
                       e.duration_minutes, e.randomize_options, e.security_mode, e.venue,
                       e.violation_limit, e.violation_action, e.instructions, e.partial_credit, assessment.cbt_live_state(e) AS live_state,
                       e.exam_type, e.negative_marks, e.allow_back, e.allow_review, e.fullscreen_required, e.detectors, e.proctoring, e.office,
                       coalesce(e.warn_at, 1) AS warn_at, coalesce(e.final_warn_at, e.violation_limit) AS final_warn_at, e.disconnect_minutes
                  FROM assessment.cbt_exam e LEFT JOIN catalogue.course c ON c.code = e.course_code LEFT JOIN jupeb.subject js ON js.id = e.jupeb_subject_id
                 WHERE e.id = :e
                """).param("e", exam).query().singleRow());
        // V364: the paper as it was drawn and frozen — the questions' own versions; the function selects neither key nor explanation
        List<Map<String, Object>> questions = jdbc.sql("SELECT n, id, kind, stem, marks, options::text AS options, image FROM assessment.cbt_candidate_paper(:a)")
                .param("a", id).query().listOfRows();
        for (Map<String, Object> q : questions) {
            q.put("options", mapper.readValue(String.valueOf(q.get("options")), new tools.jackson.core.type.TypeReference<List<Map<String, Object>>>() { }));
        }
        Map<String, Object> answers = new LinkedHashMap<>();
        List<String> flagged = new java.util.ArrayList<>();
        Map<String, Object> seqs = new LinkedHashMap<>();
        for (Map<String, Object> r : jdbc.sql("SELECT question_id, chosen, flagged, seq FROM assessment.cbt_answer WHERE attempt_id = :a").param("a", id).query().listOfRows()) {
            String q = String.valueOf(r.get("question_id"));
            Object chosen = jdbcArray(r.get("chosen"));
            if (chosen instanceof Object[] arr && arr.length > 0) answers.put(q, chosen);
            if (Boolean.TRUE.equals(r.get("flagged"))) flagged.add(q);
            if (r.get("seq") != null) seqs.put(q, r.get("seq"));
        }
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("attempt", attemptView(a));
        // V373: the candidate's sitting and seat, and extra time, for the entry screen
        out.put("placement", placed(new LinkedHashMap<>(Map.of("exam_id", exam)), me));
        out.put("exam", e);
        out.put("questions", questions);
        out.put("answers", answers);
        out.put("flagged", flagged);
        out.put("seqs", seqs);
        // V364: the candidate the screen names in its header
        out.put("candidate", candidate(kind, me));
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
        v.put("camera_consent_at", a.get("camera_consent_at"));
        v.put("camera_declined_at", a.get("camera_declined_at"));
        Object ids = jdbcArray(a.get("question_ids"));
        v.put("questions", ids instanceof Object[] arr ? arr.length : null);
        return v;
    }

    Map<String, Object> answers(Kind kind, UUID me, UUID id, String token, AnswersIn in) {
        own(kind, id, me);
        List<Map<String, Object>> rows = in.answers().stream().map(x -> {
            Map<String, Object> m = new LinkedHashMap<>();
            m.put("q", x.q().toString());
            if (x.a() != null) m.put("a", x.a());
            if (x.seq() != null) m.put("seq", x.seq());
            if (x.flag() != null) m.put("flag", x.flag());
            if (x.a() == null && x.flag() == null) m.put("a", List.of());
            return m;
        }).toList();
        Map<String, Object> a = jdbc.sql("SELECT * FROM assessment.cbt_save_answers(:a, :t, :j::jsonb)").param("a", id).param("t", token(token)).param("j", mapper.writeValueAsString(rows)).query().singleRow();
        return tick(a);
    }

    Map<String, Object> ping(Kind kind, UUID me, UUID id, String token) {
        own(kind, id, me);
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
    Map<String, Object> events(Kind kind, UUID me, UUID id, String token, EventsIn in) {
        own(kind, id, me);
        List<Map<String, Object>> rows = in.events().stream().map(x -> {
            Map<String, Object> m = new LinkedHashMap<>();
            m.put("kind", x.kind().trim().toUpperCase());
            m.put("detail", x.detail());
            if (x.n() != null) m.put("n", x.n());
            if (x.ms() != null) m.put("ms", x.ms());
            return m;
        }).toList();
        String json = jdbc.sql("SELECT assessment.cbt_record_events(:a, :t, :j::jsonb, :ip)::text").param("a", id).param("t", token(token))
                .param("j", mapper.writeValueAsString(rows)).param("ip", ip(), Types.VARCHAR).query(String.class).single();
        return mapper.readValue(json, new tools.jackson.core.type.TypeReference<LinkedHashMap<String, Object>>() { });
    }

    /** V364: a proctored examination's consent to the camera, or its refusal — recorded; without consent no answer is saved */
    Map<String, Object> camera(Kind kind, UUID me, UUID id, String token, CameraIn in) {
        own(kind, id, me);
        Map<String, Object> a = jdbc.sql("SELECT * FROM assessment.cbt_camera(:a, :t, :c, :ip)").param("a", id).param("t", token(token)).param("c", in.consent())
                .param("ip", ip(), Types.VARCHAR).query().singleRow();
        Map<String, Object> out = tick(a);
        out.put("cameraConsentAt", a.get("camera_consent_at"));
        out.put("cameraDeclinedAt", a.get("camera_declined_at"));
        return out;
    }

    Map<String, Object> submit(Kind kind, UUID me, UUID id, String token) {
        own(kind, id, me);
        return tick(jdbc.sql("SELECT * FROM assessment.cbt_submit(:a, :t)").param("a", id).param("t", token(token)).query().singleRow());
    }

    /** the result — once the office has published it, or on submission where the examination's release policy says so (V364) */
    Map<String, Object> result(Kind kind, UUID me, UUID id) {
        UUID exam = own(kind, id, me);
        if (kind == Kind.PUTME) {
            // V385: a Post-UTME score never leaves the engine through the examination door; the result-checking page reads what the Academic Office released
            throw new DomainRuleViolation("CBT_PUTME_NO_RESULT_HERE", "Your examination has been submitted. Post-UTME scores are released by the University, not shown here.",
                    new DomainRuleViolation.Remedy("Check your result on the Post-UTME result-checking page once the University opens it.", "Academic Office"));
        }
        Map<String, Object> r = jdbc.sql("""
                SELECT e.results_state, e.results_published_at, e.title, coalesce(e.course_code, js.code) AS course_code, e.pass_mark, a.status, a.submitted_at, a.answered,
                       cardinality(a.question_ids) AS questions, a.score, a.max_marks, a.percentage, a.grade, a.passed, a.outcome, e.score_on_submit
                  FROM assessment.cbt_attempt a JOIN assessment.cbt_exam e ON e.id = a.exam_id LEFT JOIN jupeb.subject js ON js.id = e.jupeb_subject_id
                 WHERE a.id = :a AND e.id = :e
                """).param("a", id).param("e", exam).query().singleRow();
        boolean released = "PUBLISHED".equals(r.get("results_state")) || (Boolean.TRUE.equals(r.get("score_on_submit")) && !"IN_PROGRESS".equals(r.get("status")));
        if (!released) {
            throw new DomainRuleViolation("CBT_RESULT_NOT_PUBLISHED", "The result of this examination is not yet published.",
                    new DomainRuleViolation.Remedy("The office reviews, approves and publishes the results; you are told when they are out.", "The examining office"));
        }
        return r;
    }
}
