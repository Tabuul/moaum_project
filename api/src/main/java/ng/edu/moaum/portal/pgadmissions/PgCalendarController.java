package ng.edu.moaum.portal.pgadmissions;

import java.time.LocalDate;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import jakarta.validation.Valid;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

import ng.edu.moaum.portal.shared.DomainRuleViolation;
import ng.edu.moaum.portal.shared.NotFound;

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
 * The Postgraduate School's own academic calendar (V224): its own sessions — the one it is currently
 * running — and its own semester windows for each, kept apart from the University's undergraduate
 * calendar. Read by the PG desks; written by the School (and the Super Administrator, so the platform
 * stays configurable). These are plain tables the School owns, like {@code admissions.pg_fee}, so the
 * writes are ordinary SQL. One session is CURRENT at a time (a partial unique index enforces it).
 */
@RestController
@RequestMapping("/api/v1/pg/calendar")
@PreAuthorize("isAuthenticated()")
class PgCalendarController {

    /* who may read the PG calendar — the same desks that read PG admissions */
    private static final String READERS =
            "hasAnyAuthority('OFFICE_pgschool','OFFICE_pgsecretary','OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar','OFFICE_dean','OFFICE_hod','OFFICE_dvc','OFFICE_vc','OFFICE_bursar','OFFICE_super')";
    /* the School of Postgraduate Studies sets it */
    private static final String WRITERS = "hasAnyAuthority('OFFICE_pgschool','OFFICE_pgsecretary','OFFICE_super')";

    private final JdbcClient jdbc;

    PgCalendarController(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    public record SessionIn(@NotNull LocalDate startsOn, @NotNull LocalDate endsOn,
                            @NotNull @Min(1) @Max(3) Integer semesters,
                            @Size(max = 400) String note,
                            @Pattern(regexp = "PLANNED|CURRENT|CLOSED") String state) {
    }

    public record SemesterIn(LocalDate registrationOpens, LocalDate registrationCloses,
                             LocalDate lecturesFrom, LocalDate lecturesTo,
                             LocalDate examsFrom, LocalDate examsTo, LocalDate resultsDue,
                             @Pattern(regexp = "NOT_YET_OPEN|OPEN|CLOSED") String state) {
    }

    /** Every PG session, which one is current, and the semesters of the session asked for (else the current). */
    @GetMapping
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> read(@RequestParam(required = false) String session) {
        String current = jdbc.sql("SELECT admissions.pg_current_session()").query(String.class).single();
        List<Map<String, Object>> sessions = jdbc.sql("""
                SELECT name, starts_on, ends_on, semesters, state, note
                  FROM admissions.pg_academic_session ORDER BY name DESC
                """).query().listOfRows();
        String looking = session == null || session.isBlank() ? current : session.trim();
        List<Map<String, Object>> semesters = looking == null ? List.of() : jdbc.sql("""
                SELECT number, registration_opens, registration_closes, lectures_from, lectures_to,
                       exams_from, exams_to, results_due, state
                  FROM admissions.pg_semester WHERE session = :s ORDER BY number
                """).param("s", looking).query().listOfRows();
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("sessions", sessions);
        out.put("current", current);
        out.put("looking", looking);
        out.put("semesters", semesters);
        return out;
    }

    @PutMapping("/sessions/{session}/{year}")
    @PreAuthorize(WRITERS)
    @Transactional
    Map<String, Object> saveSession(@PathVariable String session, @PathVariable String year,
                                    @Valid @RequestBody SessionIn body) {
        String name = session + "/" + year;
        String state = body.state() == null || body.state().isBlank() ? "PLANNED" : body.state().trim();
        String note = body.note() == null || body.note().isBlank() ? null : body.note().trim();
        if ("CURRENT".equals(state)) {
            jdbc.sql("UPDATE admissions.pg_academic_session SET state = 'CLOSED', updated_at = now() WHERE state = 'CURRENT' AND name <> :n")
                    .param("n", name).update();
        }
        jdbc.sql("""
                INSERT INTO admissions.pg_academic_session (name, starts_on, ends_on, semesters, state, note)
                VALUES (:n, :s, :e, :sem, :st, :note)
                ON CONFLICT (name) DO UPDATE SET
                    starts_on = EXCLUDED.starts_on, ends_on = EXCLUDED.ends_on,
                    semesters = EXCLUDED.semesters, state = EXCLUDED.state,
                    note = EXCLUDED.note, updated_at = now()
                """)
                .param("n", name).param("s", body.startsOn()).param("e", body.endsOn())
                .param("sem", body.semesters()).param("st", state).param("note", note).update();
        return read(name);
    }

    @PostMapping("/sessions/{session}/{year}/make-current")
    @PreAuthorize(WRITERS)
    @Transactional
    Map<String, Object> makeCurrent(@PathVariable String session, @PathVariable String year) {
        String name = session + "/" + year;
        mustExist(name);
        jdbc.sql("UPDATE admissions.pg_academic_session SET state = 'CLOSED', updated_at = now() WHERE state = 'CURRENT' AND name <> :n")
                .param("n", name).update();
        jdbc.sql("UPDATE admissions.pg_academic_session SET state = 'CURRENT', updated_at = now() WHERE name = :n")
                .param("n", name).update();
        return read(name);
    }

    @PostMapping("/sessions/{session}/{year}/close")
    @PreAuthorize(WRITERS)
    @Transactional
    Map<String, Object> close(@PathVariable String session, @PathVariable String year) {
        String name = session + "/" + year;
        mustExist(name);
        jdbc.sql("UPDATE admissions.pg_academic_session SET state = 'CLOSED', updated_at = now() WHERE name = :n")
                .param("n", name).update();
        return read(name);
    }

    @PutMapping("/sessions/{session}/{year}/semesters/{number}")
    @PreAuthorize(WRITERS)
    @Transactional
    Map<String, Object> saveSemester(@PathVariable String session, @PathVariable String year,
                                     @PathVariable int number, @Valid @RequestBody SemesterIn body) {
        String name = session + "/" + year;
        mustExist(name);
        if (number < 1 || number > 3) {
            throw new DomainRuleViolation("PG_CAL_SEMESTER", "A session has at most three semesters.",
                    new DomainRuleViolation.Remedy("Set semester 1, 2 or 3.", "School of Postgraduate Studies"));
        }
        String state = body.state() == null || body.state().isBlank() ? "NOT_YET_OPEN" : body.state().trim();
        jdbc.sql("""
                INSERT INTO admissions.pg_semester (session, number, registration_opens, registration_closes,
                        lectures_from, lectures_to, exams_from, exams_to, results_due, state)
                VALUES (:s, :n, :ro, :rc, :lf, :lt, :ef, :et, :rd, :st)
                ON CONFLICT (session, number) DO UPDATE SET
                    registration_opens = EXCLUDED.registration_opens, registration_closes = EXCLUDED.registration_closes,
                    lectures_from = EXCLUDED.lectures_from, lectures_to = EXCLUDED.lectures_to,
                    exams_from = EXCLUDED.exams_from, exams_to = EXCLUDED.exams_to,
                    results_due = EXCLUDED.results_due, state = EXCLUDED.state
                """)
                .param("s", name).param("n", number)
                .param("ro", body.registrationOpens()).param("rc", body.registrationCloses())
                .param("lf", body.lecturesFrom()).param("lt", body.lecturesTo())
                .param("ef", body.examsFrom()).param("et", body.examsTo())
                .param("rd", body.resultsDue()).param("st", state).update();
        return read(name);
    }

    private void mustExist(String name) {
        Integer n = jdbc.sql("SELECT count(*) FROM admissions.pg_academic_session WHERE name = :n")
                .param("n", name).query(Integer.class).single();
        if (n == null || n == 0) {
            throw new NotFound("postgraduate session", name);
        }
    }
}
