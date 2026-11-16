package ng.edu.moaum.portal.registration;

import java.sql.Types;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

import ng.edu.moaum.portal.shared.DomainRuleViolation;

import org.springframework.http.HttpStatus;
import org.springframework.http.ProblemDetail;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.ErrorResponseException;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * Course Registration Correction: the Director of ICT takes one student's wrongly counted course off one registration, with a reason
 * (the user's master prompt of 15 November 2026 — electives counted that the student never chose: an old-portal upload registered
 * every row it carried, a dropped course ticked again, an elective the record could not tell from a core course). The course, the
 * curriculum and every other student's registration are untouched; the entry is withdrawn and kept so, its snapshot on the
 * correction (RCR-YYYY-NNNNN) with how the course came onto the registration. A course that carries a result is held until the
 * Registrar or the Deputy Registrar — not the officer who asked — confirms it (the University's decision of 15 November 2026); the
 * mark then stays on its sheet as history. Only the Director of ICT's undo puts a course back. Every rule is the database's
 * (registration.request_entry_removal, decide_entry_removal, undo_entry_removal), which re-checks the acting office; nothing here
 * writes an entry.
 */
@RestController
@RequestMapping("/api/v1/registration/corrections")
class RegistrationCorrectionController {

    /** who reads the corrections: the Director of ICT, and the Registrar and the Deputy Registrar who decide the ones held for a result */
    static final String READERS = "hasAnyAuthority('OFFICE_ict','OFFICE_super','OFFICE_registrar','OFFICE_dregistrar')";
    /** who takes a course off a registration, and cancels or undoes it: the Director of ICT (and super) — the database says so too (RCR_OFFICE) */
    static final String CORRECTORS = "hasAnyAuthority('OFFICE_ict','OFFICE_super')";
    /** who confirms or declines a removal held for a result: the Registrar or the Deputy Registrar (and super) — the database says so too
     *  (RCR_DECIDER), and refuses the officer who asked (RCR_SAME_PERSON) */
    static final String DECIDERS = "hasAnyAuthority('OFFICE_registrar','OFFICE_dregistrar','OFFICE_super')";

    static final Set<String> STATES = Set.of("PENDING", "APPLIED", "DECLINED", "CANCELLED", "UNDONE");

    private final JdbcClient jdbc;
    private final tools.jackson.databind.ObjectMapper json;

    RegistrationCorrectionController(JdbcClient jdbc, tools.jackson.databind.ObjectMapper json) {
        this.jdbc = jdbc;
        this.json = json;
    }

    /** a refusal that names no student, as the portal words one: 404 with its code */
    private static ErrorResponseException notFound(String detail) {
        ProblemDetail p = ProblemDetail.forStatusAndDetail(HttpStatus.NOT_FOUND, detail);
        p.setTitle("No such student");
        p.setProperty("code", "RCR_NOT_FOUND");
        p.setProperty("remedy", Map.of("message", "Use the matriculation or admission number as it is on the student's record.", "office", "You"));
        return new ErrorResponseException(HttpStatus.NOT_FOUND, p, null);
    }

    private Map<String, Object> object(String text) {
        return json.readValue(text, new tools.jackson.core.type.TypeReference<Map<String, Object>>() { });
    }

    /* ── the student and the registration, as the Director of ICT reads them before a correction ── */

    /** the student by matriculation number (any case) — or, for a student not yet given one, by admission number, as the verification
     *  pages find a student — whether a Senate-approved graduate, and every registration with the courses counted on it. `matric` is the
     *  number the student goes by (the matriculation number, else the admission number) */
    @GetMapping("/student")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> student(@RequestParam String matric) {
        String no = matric == null ? "" : matric.trim().toUpperCase(Locale.ROOT);
        Map<String, Object> st = jdbc.sql("""
                SELECT s.id, coalesce(s.matric_no, s.admission_no) AS matric, s.matric_no AS "matricNo", s.admission_no AS "admissionNo",
                       upper(btrim(s.surname)) || coalesce(', ' || nullif(btrim(s.other_names), ''), '') AS name,
                       s.programme_code AS "programmeCode", p.name AS programme, s.current_level AS level, s.status,
                       EXISTS (SELECT 1 FROM records.graduand g WHERE g.student_id = s.id AND g.senate_state = 'APPROVED') AS graduate
                  FROM people.student s LEFT JOIN ref.programme p ON p.code = s.programme_code
                 WHERE :m <> '' AND (upper(btrim(s.matric_no)) = :m OR (s.matric_no IS NULL AND upper(btrim(s.admission_no)) = :m))
                 ORDER BY (s.duplicate_of IS NULL) DESC, (s.matric_no IS NOT NULL) DESC LIMIT 1
                """).param("m", no).query().listOfRows().stream().findFirst()
                .orElseThrow(() -> notFound("No student has the matriculation or admission number " + no + "."));
        Map<String, Object> out = new LinkedHashMap<>(st);
        out.put("registrations", jdbc.sql("""
                SELECT r.id AS "registrationId", r.session, r.semester, r.level, r.status,
                       (SELECT count(*) FROM registration.entry e WHERE e.registration_id = r.id AND e.status IN ('APPROVED', 'REGISTERED')) AS courses
                  FROM registration.course_registration r
                 WHERE r.student_id = :st
                 ORDER BY r.session DESC, r.semester DESC
                """).param("st", st.get("id")).query().listOfRows());
        return out;
    }

    /** one registration's courses: each as taken, its status and category, elective or not, how it came onto the registration, its
     *  result, any removal, and the same course on the student's other registrations */
    @GetMapping("/entries")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> entries(@RequestParam UUID student, @RequestParam String session, @RequestParam int semester) {
        if (session == null || !session.trim().matches("[0-9]{4}/[0-9]{4}")) {
            throw new DomainRuleViolation("RCR_SESSION", "A session is named YYYY/YYYY.", new DomainRuleViolation.Remedy("Choose the session.", "You"));
        }
        if (semester < 1 || semester > 3) {
            throw new DomainRuleViolation("RCR_SEMESTER", "A semester is 1, 2 or 3.", new DomainRuleViolation.Remedy("Choose the semester.", "You"));
        }
        String rows = jdbc.sql("""
                SELECT coalesce(jsonb_agg(jsonb_build_object(
                           'registrationId', x.registration_id, 'offeringId', x.offering_id, 'courseCode', x.course_code, 'codeAsTaken', x.code_as_taken,
                           'title', x.title, 'units', x.units, 'status', x.status, 'entryType', x.entry_type, 'basis', x.basis, 'category', x.category,
                           'isElective', x.is_elective, 'came', x.came, 'hasResult', x.has_result, 'resultWords', x.result_words,
                           'removalId', x.removal_id, 'removalRef', x.removal_ref, 'removalState', x.removal_state,
                           'registrationStatus', x.registration_status, 'level', x.level, 'elsewhere', x.elsewhere) ORDER BY x.course_code), '[]'::jsonb)::text
                  FROM registration.correction_entries(:st, :s, :m) x
                """).param("st", student).param("s", session.trim()).param("m", semester).query(String.class).single();
        return json.readValue(rows, new tools.jackson.core.type.TypeReference<List<Map<String, Object>>>() { });
    }

    /* ── a removal asked for, decided, undone ── */

    public record EntryIn(@NotNull UUID registrationId, @NotNull UUID offeringId) {
    }

    /** the courses to take off (one registration's, or the same course's later carry-overs with it) under one reason — ten characters
     *  or more, the database says (RCR_REASON); none named is RCR_NONE */
    public record RemovalIn(@NotNull UUID studentId, @Size(max = 50) List<@Valid EntryIn> entries, @Size(max = 2000) String reason) {
    }

    public record DecisionIn(@NotNull Boolean confirm, @Size(max = 2000) String note) {
    }

    public record UndoIn(@Size(max = 2000) String reason) {
    }

    /** the Director of ICT takes the courses off: one without a result is withdrawn at once (APPLIED), one with a result held for the
     *  Registry (PENDING) */
    @PostMapping
    @PreAuthorize(CORRECTORS)
    @Transactional
    Map<String, Object> request(@Valid @RequestBody RemovalIn body) {
        String entries = json.writeValueAsString(body.entries() == null ? List.of() : body.entries());
        return object(jdbc.sql("SELECT registration.request_entry_removal(:st, CAST(:e AS jsonb), :r)::text")
                .param("st", body.studentId()).param("e", entries).param("r", body.reason(), Types.VARCHAR).query(String.class).single());
    }

    /** the Registrar or the Deputy Registrar confirms a removal held for a result (the entry withdrawn, the mark kept on its sheet as
     *  history) or declines it with a note */
    @PostMapping("/{id}/decide")
    @PreAuthorize(DECIDERS)
    @Transactional
    Map<String, Object> decide(@PathVariable UUID id, @Valid @RequestBody DecisionIn body) {
        String state = jdbc.sql("SELECT registration.decide_entry_removal(:id, :c, :n)")
                .param("id", id).param("c", body.confirm()).param("n", body.note(), Types.VARCHAR).query(String.class).single();
        return Map.of("id", id, "state", state);
    }

    /** the Director of ICT cancels a removal still awaiting the Registry, or undoes an applied one (the entry back as it stood) */
    @PostMapping("/{id}/undo")
    @PreAuthorize(CORRECTORS)
    @Transactional
    Map<String, Object> undo(@PathVariable UUID id, @Valid @RequestBody UndoIn body) {
        String state = jdbc.sql("SELECT registration.undo_entry_removal(:id, :r)")
                .param("id", id).param("r", body.reason(), Types.VARCHAR).query(String.class).single();
        return Map.of("id", id, "state", state);
    }

    /* ── the corrections: the Registry's queue (PENDING) and the history ── */

    /** the corrections, newest first (500 at most): of one state, of one student, or all */
    @GetMapping
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> list(@RequestParam(required = false) String state, @RequestParam(required = false) UUID student) {
        String st = state == null || state.isBlank() ? null : state.trim().toUpperCase(Locale.ROOT);
        if (st != null && !STATES.contains(st)) {
            throw new DomainRuleViolation("RCR_LIST_STATE", "A correction is PENDING, APPLIED, DECLINED, CANCELLED or UNDONE.",
                    new DomainRuleViolation.Remedy("Choose one of the states, or none for all.", "You"));
        }
        return jdbc.sql("""
                SELECT x.id, x.ref, x.group_ref AS "groupRef", x.student_id AS "studentId", coalesce(s.matric_no, s.admission_no) AS matric,
                       upper(btrim(s.surname)) || coalesce(', ' || nullif(btrim(s.other_names), ''), '') AS name,
                       x.course_code AS "courseCode", x.code_as_taken AS "codeAsTaken", x.title, x.session, x.semester, x.level,
                       x.was_status AS "wasStatus", x.was_units AS "wasUnits", x.was_added AS "wasAdded", x.had_result AS "hadResult",
                       x.result_words AS "resultWords", x.graduate, x.reason, x.state,
                       helpdesk.person_name(x.requested_by) AS "requestedByName", x.requested_office AS "requestedOffice", x.requested_at AS "requestedAt",
                       helpdesk.person_name(x.decided_by) AS "decidedByName", x.decided_office AS "decidedOffice", x.decided_at AS "decidedAt",
                       x.decision_note AS "decisionNote",
                       helpdesk.person_name(x.undone_by) AS "undoneByName", x.undone_at AS "undoneAt", x.undo_reason AS "undoReason"
                  FROM registration.entry_removal x
                  JOIN people.student s ON s.id = x.student_id
                 WHERE (CAST(:st AS text) IS NULL OR x.state = :st) AND (CAST(:s AS uuid) IS NULL OR x.student_id = :s)
                 ORDER BY x.requested_at DESC, x.ref DESC
                 LIMIT 500
                """).param("st", st, Types.VARCHAR).param("s", student, Types.OTHER).query().listOfRows();
    }
}
