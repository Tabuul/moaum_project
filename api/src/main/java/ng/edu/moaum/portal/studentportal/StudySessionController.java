package ng.edu.moaum.portal.studentportal;

import java.sql.Types;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

import ng.edu.moaum.portal.shared.NotFound;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.Authentication;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * V733 — an MBBS student's own academic session (the University's master prompt of 12 November 2026, part A). The College runs MBBS a
 * session behind the University's calendar: the student reads the session they stand in, their level and the approved sessions they
 * may choose (people.study_session_options), and changes it, confirmed (people.choose_study_session); the Academic Office, the Registry
 * and the College read every change and set a session the rules do not let the student choose (a repeated year), with a reason
 * (people.set_study_session). Every reader of a student's session — the /me pages through StudentPortalService.sessionFor, the database
 * through people.student_current_session — follows the choice. Neither path changes the level, a registration, a result or a payment.
 */
@RestController
class StudySessionController {

    /** who reads every change: the Academic Office, the Registry, the College (Provost, College Secretary, MBBS Coordinator), ICT and the
     *  Super Administrator — the administrators the University named; a faculty's Dean is not among them */
    private static final String READERS = "hasAnyAuthority('OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar','OFFICE_provost',"
            + "'OFFICE_collegesecretary','OFFICE_mbbscoordinator','OFFICE_ict','OFFICE_super')";
    /** who sets a student's session (the database checks the office again): the Academic Office, the Registry, the Provost, the College
     *  Secretary, the MBBS Coordinator, the Super Administrator */
    private static final String SETTERS = "hasAnyAuthority('OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar','OFFICE_provost',"
            + "'OFFICE_collegesecretary','OFFICE_mbbscoordinator','OFFICE_super')";

    private final JdbcClient jdbc;
    private final StudentPortalService portal;

    StudySessionController(JdbcClient jdbc, StudentPortalService portal) {
        this.jdbc = jdbc;
        this.portal = portal;
    }

    public record Choose(@NotBlank @Size(max = 9) String session) {
    }

    public record SetFor(@Size(max = 9) String session, @NotBlank @Size(min = 10, max = 600) String reason) {
    }

    private static UUID id(Authentication auth) {
        return UUID.fromString(auth.getName());
    }

    /** a student's page: may they choose, the session they stand in and the University's, their level, the approved sessions (each
     *  selectable or why not) and every change so far */
    private Map<String, Object> page(UUID student) {
        Map<String, Object> s = jdbc.sql("""
                SELECT s.id, s.matric_no, s.surname || ', ' || s.other_names AS name, s.current_level, s.status, s.entry_session,
                       p.code AS programme_code, p.name AS programme, people.study_session_refusal(s.id) AS refusal,
                       people.own_session(s.id) AS own, policy.university_current_session() AS university,
                       (SELECT r.sessions_behind_max FROM college.programme_rule r WHERE r.programme_code = s.programme_code) AS behind_max
                  FROM people.student s LEFT JOIN ref.programme p ON p.code = s.programme_code WHERE s.id = :s
                """).param("s", student).query().listOfRows().stream().findFirst()
                .orElseThrow(() -> new NotFound("student", student.toString()));
        boolean eligible = s.get("refusal") == null;
        Map<String, Object> out = new java.util.LinkedHashMap<>();
        out.put("eligible", eligible);
        out.put("refusal", s.get("refusal"));
        out.put("student", s);
        out.put("session", s.get("own") != null ? s.get("own") : s.get("university"));
        out.put("own", s.get("own") != null);
        out.put("university", s.get("university"));
        out.put("options", eligible ? jdbc.sql("SELECT * FROM people.study_session_options(:s) ORDER BY starts_on DESC").param("s", student).query().listOfRows() : List.of());
        out.put("history", history(student));
        return out;
    }

    private List<Map<String, Object>> history(UUID student) {
        return jdbc.sql("""
                SELECT e.at, e.from_session, e.to_session, e.level, e.office, e.approval, e.reason,
                       coalesce((SELECT trim(coalesce(pe.given_names, '') || ' ' || pe.surname) FROM iam.person pe WHERE pe.id = e.by_person),
                                CASE WHEN e.office = 'student' THEN 'The student' END) AS by_name
                  FROM people.study_session_event e WHERE e.student_id = :s ORDER BY e.at DESC, e.id
                """).param("s", student).query().listOfRows();
    }

    /* ── the student's own ── */

    @GetMapping("/api/v1/me/study-session")
    @PreAuthorize("hasAuthority('OFFICE_student')")
    @Transactional(readOnly = true)
    Map<String, Object> mine(Authentication auth) {
        Map<String, Object> out = page(id(auth));
        // the session every /me page opens on, as the portal reads it (between sessions, or an entrant of a planned session, it is not
        // the calendar's current one) — the one the student is shown as standing in
        out.put("session", portal.sessionFor(id(auth)));
        return out;
    }

    /** the student's choice, confirmed on the dashboard (the confirmation names the previous and the new session and the level) */
    @PostMapping("/api/v1/me/study-session")
    @PreAuthorize("hasAuthority('OFFICE_student')")
    @Transactional
    Map<String, Object> choose(Authentication auth, @Valid @RequestBody Choose body) {
        String result = jdbc.sql("SELECT people.choose_study_session(:s, :ses)::text").param("s", id(auth)).param("ses", body.session().trim())
                .query(String.class).single();
        Map<String, Object> out = page(id(auth));
        out.put("session", portal.sessionFor(id(auth)));
        out.put("changed", result);
        return out;
    }

    /* ── the offices' ── */

    /** every MBBS student standing in a session of their own, and every change, newest first — searchable by name or number */
    @GetMapping("/api/v1/study-sessions")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> list(@RequestParam(required = false) String search, @RequestParam(required = false) String session) {
        String q = search == null || search.isBlank() ? null : "%" + search.trim().toUpperCase() + "%";
        String ses = session == null || session.isBlank() ? null : session.trim();
        List<Map<String, Object>> standing = jdbc.sql("""
                SELECT s.id, s.matric_no, s.surname || ', ' || s.other_names AS name, p.name AS programme, s.current_level, ss.session,
                       ss.level AS level_when_set, ss.set_at, ss.set_office, ss.approval, ss.reason
                  FROM people.study_session ss JOIN people.student s ON s.id = ss.student_id LEFT JOIN ref.programme p ON p.code = s.programme_code
                 WHERE (CAST(:q AS text) IS NULL OR upper(s.surname || ' ' || s.other_names) LIKE :q OR upper(coalesce(s.matric_no, '')) LIKE :q)
                   AND (CAST(:ses AS text) IS NULL OR ss.session = :ses)
                 ORDER BY ss.session, s.current_level, s.surname LIMIT 2000
                """).param("q", q, Types.VARCHAR).param("ses", ses, Types.VARCHAR).query().listOfRows();
        List<Map<String, Object>> changes = jdbc.sql("""
                SELECT e.at, e.student_id, e.matric_no, s.surname || ', ' || s.other_names AS name, p.name AS programme, e.from_session, e.to_session,
                       e.level, e.office, e.approval, e.reason,
                       coalesce((SELECT trim(coalesce(pe.given_names, '') || ' ' || pe.surname) FROM iam.person pe WHERE pe.id = e.by_person),
                                CASE WHEN e.office = 'student' THEN 'The student' END) AS by_name
                  FROM people.study_session_event e JOIN people.student s ON s.id = e.student_id LEFT JOIN ref.programme p ON p.code = e.programme_code
                 WHERE (CAST(:q AS text) IS NULL OR upper(s.surname || ' ' || s.other_names) LIKE :q OR upper(coalesce(e.matric_no, '')) LIKE :q)
                 ORDER BY e.at DESC LIMIT 500
                """).param("q", q, Types.VARCHAR).query().listOfRows();
        List<Map<String, Object>> bySession = jdbc.sql("""
                SELECT ss.session, count(*) AS students FROM people.study_session ss GROUP BY ss.session ORDER BY ss.session DESC
                """).query().listOfRows();
        Map<String, Object> out = new java.util.LinkedHashMap<>();
        out.put("university", jdbc.sql("SELECT policy.university_current_session()").query(String.class).optional().orElse(null));
        out.put("bySession", bySession);
        out.put("standing", standing);
        out.put("changes", changes);
        return out;
    }

    /** one student's page for an office, found by matriculation or admission number */
    @GetMapping("/api/v1/study-sessions/student")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> student(@RequestParam String number) {
        UUID id = jdbc.sql("SELECT id FROM people.student WHERE upper(matric_no) = upper(:n) OR upper(admission_no) = upper(:n) LIMIT 1")
                .param("n", number == null ? "" : number.trim()).query(UUID.class).optional()
                .orElseThrow(() -> new NotFound("student", number));
        return page(id);
    }

    /** an office sets a student's session — any approved session on the calendar's rules (a repeated year included), or the University's
     *  (no session given), with the reason */
    @PostMapping("/api/v1/study-sessions/{student}")
    @PreAuthorize(SETTERS)
    @Transactional
    Map<String, Object> set(@PathVariable UUID student, @Valid @RequestBody SetFor body) {
        String ses = body.session() == null || body.session().isBlank() ? null : body.session().trim();
        String result = jdbc.sql("SELECT people.set_study_session(:s, :ses, :r)::text").param("s", student).param("ses", ses, Types.VARCHAR)
                .param("r", body.reason().trim()).query(String.class).single();
        Map<String, Object> out = page(student);
        out.put("changed", result);
        return out;
    }
}
