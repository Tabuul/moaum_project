package ng.edu.moaum.portal.results;

import java.sql.Types;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * Held scripts (V240): a mark from a candidate who sat the paper without being on the roll, held
 * against the sheet until an approved registration releases it, or the semester's late-registration
 * date passes and it lapses. The lecturer holds and withdraws; every desk on the chain reads; the
 * Bursary reads the list of students a held script is waiting on.
 */
@RestController
@RequestMapping("/api/v1/results")
class HeldScriptsController {

    private static final String READERS =
            "hasAnyAuthority('OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar','OFFICE_dvc','OFFICE_vc','OFFICE_records',"
            + "'OFFICE_dean','OFFICE_hod','OFFICE_exams','OFFICE_facultyexams','OFFICE_facultyofficer','OFFICE_lecturer',"
            + "'OFFICE_bursar','OFFICE_ict','OFFICE_admin','OFFICE_super')";
    private static final String ENTRY = "hasAnyAuthority('OFFICE_lecturer','OFFICE_exams','OFFICE_academic')";
    private static final String OWING_READERS =
            "hasAnyAuthority('OFFICE_bursar','OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar','OFFICE_exams','OFFICE_hod',"
            + "'OFFICE_dean','OFFICE_records','OFFICE_vc','OFFICE_dvc','OFFICE_admin','OFFICE_super')";

    private final JdbcClient jdbc;

    HeldScriptsController(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    public record HoldIn(@NotBlank @Size(max = 40) String number, Integer ca, Integer exam,
                         @Size(max = 20) String outcome, @Size(max = 400) String note) {
    }

    private List<Map<String, Object>> list(UUID sheet) {
        return jdbc.sql("SELECT * FROM assessment.held_scripts(:s)").param("s", sheet).query().listOfRows();
    }

    /** the student is told, by email and by SMS where the register can reach them, that a script is held for
     *  them and what releases it — the most persuasive fees reminder the University can send (V240) */
    private void tellStudents(UUID sheet, List<UUID> heldIds) {
        if (heldIds.isEmpty()) return;
        List<Map<String, Object>> rows = jdbc.sql("""
                SELECT h.id, h.student_id, st.surname, st.other_names, coalesce(st.matric_no, st.admission_no) AS number,
                       o.course_code, c.title, o.session, o.semester, rc.email, rc.phone,
                       assessment.held_scripts_close(h.sheet_id) AS closes_on
                  FROM assessment.held_script h
                  JOIN people.student st ON st.id = h.student_id
                  JOIN assessment.score_sheet s ON s.id = h.sheet_id
                  JOIN catalogue.offering o ON o.id = s.offering_id
                  JOIN catalogue.course c ON c.code = o.course_code
                  LEFT JOIN LATERAL people.student_reach(h.student_id) rc ON true
                 WHERE h.sheet_id = :s AND h.id IN (:ids)
                """).param("s", sheet).param("ids", heldIds).query().listOfRows();
        for (Map<String, Object> r : rows) {
            String course = r.get("course_code") + " — " + r.get("title");
            Object close = r.get("closes_on");
            String by = close == null ? "before late registration for the semester closes" : "on or before " + close;
            String subject = "Your " + r.get("course_code") + " script is held until you register";
            String body = "Dear " + r.get("surname") + ", " + r.get("other_names") + " (" + r.get("number") + "),\n\n"
                    + "You sat the paper in " + course + " (" + r.get("session") + ", semester " + r.get("semester") + ") without registering the course. "
                    + "Your lecturer has held your script and its mark on the portal. The mark is not on any result yet.\n\n"
                    + "To have it counted: pay your fees, register the course on the portal, and have the registration approved by your Head of Department " + by + ". "
                    + "The moment the registration is approved, the register releases the mark into the score sheet on its own. "
                    + "A script not released by then lapses and the result is lost.\n\n"
                    + "Rev. Fr. Moses Orshio Adasu University, Makurdi — the Registry";
            String sms = "MOAUM: your " + r.get("course_code") + " script (" + r.get("session") + ") is HELD - you sat without registering. Pay fees, register the course and get it approved " + by + " or the mark lapses.";
            UUID about = (UUID) r.get("id");
            Object email = r.get("email");
            Object phone = r.get("phone");
            if (email != null && !String.valueOf(email).isBlank()) {
                jdbc.sql("SELECT platform.queue_notice('EMAIL', :r, :s, :b, 'held_script', :a)")
                        .param("r", String.valueOf(email)).param("s", subject).param("b", body).param("a", about).query().singleRow();
            }
            if (phone != null && !String.valueOf(phone).isBlank()) {
                jdbc.sql("SELECT platform.queue_notice('SMS', :r, :s, :b, 'held_script', :a)")
                        .param("r", String.valueOf(phone)).param("s", subject).param("b", sms).param("a", about).query().singleRow();
            }
        }
    }

    /** the sheet's held scripts, after any past the closing date have lapsed */
    @GetMapping("/sheets/{id}/held")
    @PreAuthorize(READERS)
    @Transactional
    List<Map<String, Object>> held(@PathVariable UUID id) {
        jdbc.sql("SELECT assessment.lapse_held_scripts()").query(Integer.class).single();
        return list(id);
    }

    /** hold a script: the candidate by number, the two marks (or the outcome), a note */
    @PostMapping("/sheets/{id}/held")
    @PreAuthorize(ENTRY)
    @Transactional
    Map<String, Object> hold(@PathVariable UUID id, @Valid @RequestBody HoldIn body) {
        UUID held = jdbc.sql("SELECT assessment.hold_script(:s, :n, :ca, :ex, :o, :note)")
                .param("s", id).param("n", body.number().trim())
                .param("ca", body.ca(), Types.INTEGER).param("ex", body.exam(), Types.INTEGER)
                .param("o", body.outcome(), Types.VARCHAR).param("note", body.note(), Types.VARCHAR)
                .query(UUID.class).single();
        tellStudents(id, List.of(held));
        return Map.of("id", held, "held", list(id));
    }

    public record BulkIn(@jakarta.validation.constraints.NotNull @Size(max = 2000) List<Map<String, Object>> rows) {
    }

    /** hold many at once from the uploaded template: every line holds, or none does and each refusal is named */
    @PostMapping("/sheets/{id}/held/bulk")
    @PreAuthorize(ENTRY)
    @Transactional
    Map<String, Object> holdBulk(@PathVariable UUID id, @Valid @RequestBody BulkIn body) throws tools.jackson.core.JacksonException {
        String json = new tools.jackson.databind.ObjectMapper().writeValueAsString(body.rows());
        List<UUID> before = jdbc.sql("SELECT id FROM assessment.held_script WHERE sheet_id = :s").param("s", id).query(UUID.class).list();
        int n = jdbc.sql("SELECT assessment.hold_scripts_bulk(:s, cast(:rows as jsonb))")
                .param("s", id).param("rows", json).query(Integer.class).single();
        List<UUID> now = jdbc.sql("SELECT id FROM assessment.held_script WHERE sheet_id = :s AND state = 'HELD'").param("s", id).query(UUID.class).list();
        tellStudents(id, now.stream().filter(x -> !before.contains(x)).toList());
        return Map.of("held", n, "list", list(id));
    }

    /** withdraw a held script entered wrongly; only a script still held */
    @DeleteMapping("/sheets/{id}/held/{held}")
    @PreAuthorize(ENTRY)
    @Transactional
    Map<String, Object> withdraw(@PathVariable UUID id, @PathVariable UUID held) {
        jdbc.sql("SELECT assessment.withdraw_held_script(:h)").param("h", held).update();
        return Map.of("id", held, "held", list(id));
    }

    /** the students a held script is waiting on, with what they owe — the Bursary's list */
    @GetMapping("/held/owing")
    @PreAuthorize(OWING_READERS)
    @Transactional
    List<Map<String, Object>> owing() {
        jdbc.sql("SELECT assessment.lapse_held_scripts()").query(Integer.class).single();
        return jdbc.sql("SELECT * FROM assessment.held_scripts_owing()").query().listOfRows();
    }
}
