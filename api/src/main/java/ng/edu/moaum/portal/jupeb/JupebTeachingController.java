package ng.edu.moaum.portal.jupeb;

import java.sql.Types;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

import ng.edu.moaum.portal.shared.DomainRuleViolation;
import ng.edu.moaum.portal.shared.NotFound;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.Authentication;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * A lecturer's JUPEB workspace (V354): the subjects (and classes) the JUPEB Office assigned them for the current session, their
 * week from the timetable, today's lectures and those gone unrecorded, the courses and syllabus of their subjects, how their
 * students are doing in attendance and practice, and notices to the students of the subjects they teach. Everything is the
 * lecturer's own: a subject or class they are not assigned to is not found, and a notice reaches only the students of a subject
 * they teach. Attendance itself is taken on the attendance engine (/api/v1/attendance/jupeb), where the same assignment decides.
 */
@RestController
@RequestMapping("/api/v1/jupeb/teaching")
@PreAuthorize("hasAuthority('OFFICE_lecturer')")
class JupebTeachingController {

    private final JdbcClient jdbc;

    JupebTeachingController(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    private static UUID me(Authentication auth) {
        return UUID.fromString(auth.getName());
    }

    private String session() {
        return jdbc.sql("SELECT jupeb.current_session()").query(String.class).single();
    }

    /** whether this lecturer teaches the subject — in the class given, or (no class) in every class */
    private boolean teaches(UUID person, String session, UUID subject, UUID klass) {
        return jdbc.sql("""
                SELECT EXISTS (SELECT 1 FROM attendance.instructor i WHERE i.context = 'JUPEB' AND i.person_id = :p AND i.session = :s AND i.subject_ref = :sub
                                  AND i.ended_at IS NULL AND (i.class_ref IS NULL OR i.class_ref = :k))
                """).param("p", person).param("s", session).param("sub", subject).param("k", klass, Types.OTHER).query(Boolean.class).single();
    }

    /** the workspace: the assignments, the week, today's lectures, those gone unrecorded, the courses, the dates coming up */
    @GetMapping
    @Transactional(readOnly = true)
    Map<String, Object> workspace(Authentication auth) {
        UUID p = me(auth);
        String s = session();
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("session", s);
        out.put("semester", jdbc.sql("SELECT jupeb.current_semester(:s, NULL)").param("s", s).query(Integer.class).single());
        out.put("today", jdbc.sql("SELECT (now() AT TIME ZONE 'Africa/Lagos')::date::text").query(String.class).single());
        out.put("assignments", jdbc.sql("""
                SELECT i.subject_ref AS subject_id, s.code, s.title, i.class_ref AS class_id, k.name AS class_name,
                       (SELECT count(*) FROM jupeb.subject_registration r JOIN jupeb.application a ON a.id = r.application_id
                         WHERE r.subject_id = i.subject_ref AND a.session = i.session AND a.state IN ('STUDENT', 'COMPLETED')
                           AND (i.class_ref IS NULL OR a.class_id = i.class_ref)) AS students
                  FROM attendance.instructor i JOIN jupeb.subject s ON s.id = i.subject_ref LEFT JOIN jupeb.class k ON k.id = i.class_ref
                 WHERE i.context = 'JUPEB' AND i.person_id = :p AND i.session = :s AND i.ended_at IS NULL
                 ORDER BY s.title, k.name NULLS FIRST
                """).param("p", p).param("s", s).query().listOfRows());
        String mine = """
                EXISTS (SELECT 1 FROM attendance.instructor i WHERE i.context = 'JUPEB' AND i.person_id = :p AND i.session = t.session AND i.subject_ref = t.subject_id
                           AND i.ended_at IS NULL AND (t.class_id IS NULL OR i.class_ref IS NULL OR i.class_ref = t.class_id))
                """;
        out.put("week", jdbc.sql("""
                SELECT t.id, t.semester, t.weekday, to_char(t.starts_at, 'HH24:MI') AS starts_at, to_char(t.ends_at, 'HH24:MI') AS ends_at, t.venue, t.note,
                       s.code, s.title, k.name AS class_name, t.class_id, t.subject_id, t.course_code, t.practical, t.unit_id,
                       (SELECT u.title FROM jupeb.subject_unit u WHERE u.id = t.unit_id) AS unit_title
                  FROM jupeb.timetable_slot t JOIN jupeb.subject s ON s.id = t.subject_id LEFT JOIN jupeb.class k ON k.id = t.class_id
                 WHERE t.active AND t.session = :s AND
                """ + mine + " ORDER BY t.semester, t.weekday, t.starts_at").param("s", s).param("p", p).query().listOfRows());
        out.put("lectures", jdbc.sql("""
                SELECT d.*, d.day::text AS held_on FROM jupeb.lectures_due(:s, (now() AT TIME ZONE 'Africa/Lagos')::date, (now() AT TIME ZONE 'Africa/Lagos')::date) d
                 WHERE attendance.may_take(:p, 'JUPEB', :s, d.subject_id, d.class_id)
                """).param("s", s).param("p", p).query().listOfRows());
        out.put("missed", jdbc.sql("""
                SELECT d.*, d.day::text AS held_on FROM jupeb.lectures_due(:s,
                         greatest(coalesce(CASE jupeb.current_semester(:s, NULL) WHEN 2 THEN jupeb.calendar_date(:s, 'SEMESTER_2_STARTS') ELSE jupeb.calendar_date(:s, 'TEACHING_STARTS') END,
                                           (now() AT TIME ZONE 'Africa/Lagos')::date - 30), (now() AT TIME ZONE 'Africa/Lagos')::date - 120),
                         (now() AT TIME ZONE 'Africa/Lagos')::date - 1) d
                 WHERE d.state IN ('MISSED', 'OPEN') AND attendance.may_take(:p, 'JUPEB', :s, d.subject_id, d.class_id)
                 ORDER BY d.day DESC LIMIT 60
                """).param("s", s).param("p", p).query().listOfRows());
        out.put("units", jdbc.sql("""
                SELECT u.id, u.subject_id, u.code, u.title, u.semester, u.credit_units, b.title AS board_title, b.prefix,
                       (SELECT count(*) FROM jupeb.unit_topic x WHERE x.unit_id = u.id) AS topics
                  FROM jupeb.subject_unit u LEFT JOIN jupeb.board_subject b ON b.id = u.board_subject_id
                 WHERE u.subject_id IN (SELECT i.subject_ref FROM attendance.instructor i WHERE i.context = 'JUPEB' AND i.person_id = :p AND i.session = :s AND i.ended_at IS NULL)
                 ORDER BY u.semester NULLS LAST, b.code NULLS LAST, u.ord, u.code
                """).param("s", s).param("p", p).query().listOfRows());
        out.put("calendar", jdbc.sql("""
                SELECT starts_on::text AS starts_on, ends_on::text AS ends_on, title, deadline_on::text AS deadline_on, marker
                  FROM jupeb.calendar_event WHERE session = :s AND removed_at IS NULL AND coalesce(ends_on, starts_on) >= (now() AT TIME ZONE 'Africa/Lagos')::date
                 ORDER BY starts_on, ord LIMIT 6
                """).param("s", s).query().listOfRows());
        return out;
    }

    /** the students of a subject this lecturer teaches (in their classes): attendance in the subject and practice in it */
    @GetMapping("/subjects/{subject}/students")
    @Transactional(readOnly = true)
    List<Map<String, Object>> students(Authentication auth, @PathVariable UUID subject) {
        UUID p = me(auth);
        String s = session();
        if (!jdbc.sql("SELECT EXISTS (SELECT 1 FROM attendance.instructor WHERE context = 'JUPEB' AND person_id = :p AND session = :s AND subject_ref = :sub AND ended_at IS NULL)")
                .param("p", p).param("s", s).param("sub", subject).query(Boolean.class).single()) {
            throw new NotFound("subject", subject);
        }
        return jdbc.sql("""
                SELECT a.id, a.application_no, upper(a.surname) || ', ' || a.first_name || coalesce(' ' || a.middle_name, '') AS name, k.name AS class_name, a.exam_no,
                       st.total AS classes, st.rate AS attendance_rate, st.verdict,
                       (SELECT count(*) FROM jupeb.practice_attempt x JOIN jupeb.practice_test pt ON pt.id = x.test_id
                         WHERE x.application_id = a.id AND pt.subject_id = :sub AND x.submitted_at IS NOT NULL) AS attempts,
                       (SELECT round(avg(x.percentage), 1) FROM jupeb.practice_attempt x JOIN jupeb.practice_test pt ON pt.id = x.test_id
                         WHERE x.application_id = a.id AND pt.subject_id = :sub AND x.submitted_at IS NOT NULL) AS practice_average,
                       (SELECT max(x.percentage) FROM jupeb.practice_attempt x JOIN jupeb.practice_test pt ON pt.id = x.test_id
                         WHERE x.application_id = a.id AND pt.subject_id = :sub AND x.submitted_at IS NOT NULL) AS practice_best
                  FROM jupeb.subject_registration r JOIN jupeb.application a ON a.id = r.application_id LEFT JOIN jupeb.class k ON k.id = a.class_id
                  LEFT JOIN LATERAL (SELECT sum(m.total)::int AS total, round(avg(m.rate), 1) AS rate, min(m.verdict) AS verdict
                                       FROM attendance.member_summary('JUPEB', a.id, :s) m WHERE m.subject_ref = :sub) st ON true
                 WHERE r.subject_id = :sub AND a.session = :s AND a.state IN ('STUDENT', 'COMPLETED')
                   AND EXISTS (SELECT 1 FROM attendance.instructor i WHERE i.context = 'JUPEB' AND i.person_id = :p AND i.session = :s AND i.subject_ref = :sub
                                 AND i.ended_at IS NULL AND (i.class_ref IS NULL OR i.class_ref = a.class_id))
                 ORDER BY a.surname, a.first_name
                """).param("sub", subject).param("s", s).param("p", p).query().listOfRows();
    }

    /** a course's syllabus — of a subject this lecturer teaches */
    @GetMapping("/units/{id}/syllabus")
    @Transactional(readOnly = true)
    Map<String, Object> syllabus(Authentication auth, @PathVariable UUID id) {
        boolean mine = jdbc.sql("""
                SELECT EXISTS (SELECT 1 FROM jupeb.subject_unit u JOIN attendance.instructor i ON i.subject_ref = u.subject_id
                                WHERE u.id = :u AND i.context = 'JUPEB' AND i.person_id = :p AND i.session = jupeb.current_session() AND i.ended_at IS NULL)
                """).param("u", id).param("p", me(auth)).query(Boolean.class).single();
        if (!mine) throw new NotFound("course unit", id);
        return JupebView.unitSyllabus(jdbc, id);
    }

    /* ── V355: the continuous assessment of the subjects this lecturer teaches, and their practice by topic ── */

    /** the assessment sheet of a subject this lecturer teaches — their class's students (every class's when they teach every class) */
    @GetMapping("/ca")
    @Transactional(readOnly = true)
    Map<String, Object> assessment(Authentication auth, @RequestParam UUID subject) {
        UUID p = me(auth);
        String s = session();
        List<UUID> classes = myClasses(p, s, subject);
        Map<String, Object> out = new LinkedHashMap<>(JupebView.caSheet(jdbc, s, subject, null));
        if (!classes.contains(null)) {
            out.put("rows", ((List<Map<String, Object>>) out.get("rows")).stream()
                    .filter(r -> jdbc.sql("SELECT class_id FROM jupeb.application WHERE id = :a").param("a", r.get("application_id")).query(UUID.class).optional().map(classes::contains).orElse(false))
                    .toList());
        }
        out.put("due", jdbc.sql("""
                SELECT coalesce(deadline_on, starts_on)::text FROM jupeb.calendar_event WHERE session = :s AND marker = 'CA_SUBMISSION' AND removed_at IS NULL
                """).param("s", s).query(String.class).optional().orElse(null));
        return out;
    }

    /** the classes of the subject this lecturer teaches this session (a null: every class); not theirs, not found */
    private List<UUID> myClasses(UUID p, String s, UUID subject) {
        List<UUID> classes = jdbc.sql("SELECT class_ref FROM attendance.instructor WHERE context = 'JUPEB' AND person_id = :p AND session = :s AND subject_ref = :sub AND ended_at IS NULL")
                .param("p", p).param("s", s).param("sub", subject).query((rs, i) -> (UUID) rs.getObject(1)).list();
        if (classes.isEmpty()) throw new NotFound("subject", subject);
        return classes;
    }

    public record ScoreIn(@NotNull UUID applicationId, @NotNull UUID componentId, java.math.BigDecimal score) {
    }

    public record ScoresIn(@NotNull UUID subjectId, @NotNull @Size(max = 3000) List<@Valid ScoreIn> scores) {
    }

    /** scores entered for students of this lecturer's classes in the subject; the subject not locked */
    @org.springframework.web.bind.annotation.PutMapping("/ca")
    @Transactional
    Map<String, Object> saveAssessment(Authentication auth, @Valid @RequestBody ScoresIn b) {
        UUID p = me(auth);
        String s = session();
        List<UUID> classes = myClasses(p, s, b.subjectId());
        for (ScoreIn x : b.scores()) {
            if (!classes.contains(null)) {
                UUID k = jdbc.sql("SELECT class_id FROM jupeb.application WHERE id = :a").param("a", x.applicationId()).query(UUID.class).optional().orElse(null);
                if (k == null || !classes.contains(k)) throw new AccessDeniedException("That student is not in a class you teach.");
            }
            jdbc.sql("SELECT jupeb.ca_save(:a, :s, :c, :v, :by, 'lecturer')").param("a", x.applicationId()).param("s", b.subjectId()).param("c", x.componentId())
                    .param("v", x.score(), Types.NUMERIC).param("by", p).query().listOfRows();
        }
        return assessment(auth, b.subjectId());
    }

    /** a subject this lecturer teaches: its students' practice by syllabus topic, weakest first */
    @GetMapping("/topics")
    @Transactional(readOnly = true)
    List<Map<String, Object>> topics(Authentication auth, @RequestParam UUID subject) {
        UUID p = me(auth);
        String s = session();
        List<UUID> classes = myClasses(p, s, subject);
        if (classes.contains(null)) {
            return jdbc.sql("SELECT * FROM jupeb.practice_topics_class(:s, :sub, NULL)").param("s", s).param("sub", subject).query().listOfRows();
        }
        /* V356: of the classes this lecturer teaches only */
        return jdbc.sql("SELECT * FROM jupeb.practice_topics_classes(:s, :sub, :k)").param("s", s).param("sub", subject)
                .param("k", classes.toArray(new UUID[0])).query().listOfRows();
    }

    /** the notices this lecturer published, with how many they reach and have read */
    @GetMapping("/notices")
    @Transactional(readOnly = true)
    List<Map<String, Object>> notices(Authentication auth) {
        return jdbc.sql("""
                SELECT n.id, n.title, n.body, n.send_email, n.published_at, n.withdrawn_at, n.withdrawn_reason,
                       (SELECT s.title FROM jupeb.subject s WHERE s.id::text = split_part(n.audience_ref, '/', 1))
                         || coalesce(' · ' || (SELECT k.name FROM jupeb.class k WHERE k.id::text = nullif(split_part(n.audience_ref, '/', 2), '')), '') AS audience_name,
                       (SELECT count(*) FROM jupeb.application a WHERE jupeb.audience_reaches(n.session, n.audience, n.audience_ref, a)) AS reach,
                       (SELECT count(*) FROM jupeb.announcement_read r WHERE r.announcement_id = n.id) AS reads
                  FROM jupeb.announcement n WHERE n.created_by = :p AND n.audience = 'SUBJECT' ORDER BY n.published_at DESC LIMIT 200
                """).param("p", me(auth)).query().listOfRows();
    }

    public record NoticeIn(@NotNull UUID subjectId, UUID classId, @jakarta.validation.constraints.NotBlank @Size(min = 3, max = 160) String title,
                           @jakarta.validation.constraints.NotBlank @Size(min = 3, max = 5000) String body, Boolean email) {
    }

    /** a notice to the students of a subject this lecturer teaches — on their dashboards, and by email when asked (never by text) */
    @PostMapping("/notices")
    @Transactional
    Map<String, Object> post(Authentication auth, @Valid @RequestBody NoticeIn b) {
        UUID p = me(auth);
        String s = session();
        if (!teaches(p, s, b.subjectId(), b.classId())) {
            throw new AccessDeniedException(b.classId() == null ? "You do not teach this subject in every class; choose your class." : "You do not teach this subject in that class.");
        }
        String ref = b.classId() == null ? b.subjectId().toString() : b.subjectId() + "/" + b.classId();
        UUID n = jdbc.sql("""
                INSERT INTO jupeb.announcement (session, audience, audience_ref, title, body, send_email, created_by, created_office)
                VALUES (:s, 'SUBJECT', :r, :t, :b, :e, :by, 'lecturer') RETURNING id
                """).param("s", s).param("r", ref).param("t", b.title().trim()).param("b", b.body().trim()).param("e", Boolean.TRUE.equals(b.email())).param("by", p)
                .query(UUID.class).single();
        int notified = jdbc.sql("SELECT jupeb.announcement_notify(:n)").param("n", n).query(Integer.class).single();
        int reach = jdbc.sql("SELECT jupeb.announcement_reach(:s, 'SUBJECT', :r)").param("s", s).param("r", ref).query(Integer.class).single();
        return Map.of("id", n, "reach", reach, "notified", notified);
    }

    public record WithdrawIn(@jakarta.validation.constraints.NotBlank @Size(min = 5, max = 300) String reason) {
    }

    /** a notice of this lecturer's withdrawn, with the reason */
    @PostMapping("/notices/{id}/withdraw")
    @Transactional
    Map<String, Object> withdraw(Authentication auth, @PathVariable UUID id, @Valid @RequestBody WithdrawIn b) {
        int n = jdbc.sql("UPDATE jupeb.announcement SET withdrawn_at = now(), withdrawn_by = :p, withdrawn_reason = :r WHERE id = :id AND created_by = :p AND withdrawn_at IS NULL")
                .param("p", me(auth)).param("r", b.reason().trim()).param("id", id).update();
        if (n == 0) throw new DomainRuleViolation("JUPEB_NOTICE_NOT_YOURS", "That is not a live notice of yours.", new DomainRuleViolation.Remedy("Withdraw only your own notices.", "You"));
        return Map.of("id", id, "withdrawn", true);
    }
}
