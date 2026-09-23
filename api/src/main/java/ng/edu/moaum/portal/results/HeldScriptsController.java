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
        return Map.of("id", held, "held", list(id));
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
