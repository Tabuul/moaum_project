package ng.edu.moaum.portal.matriculation;

import java.sql.Types;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

import ng.edu.moaum.portal.shared.DomainRuleViolation;
import ng.edu.moaum.portal.shared.NotFound;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * The matriculation number's configuration (V263): the format rule, the series with their last numbers, each faculty's
 * segment and series, each programme's code (or none), its faculty segment and series — and the number every programme
 * would give next, so the Registry sees the rule before a run spends it. Readers of matriculation read; the Registry
 * and the Academic Office change.
 */
@RestController
@RequestMapping("/api/v1/matriculation/config")
class MatricFormatController {

    private static final String READERS = "hasAnyAuthority('OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar','OFFICE_dvc','OFFICE_vc','OFFICE_records','OFFICE_facultyofficer','OFFICE_dean','OFFICE_ict','OFFICE_admin','OFFICE_super')";
    private static final String CONFIG = "hasAnyAuthority('OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar','OFFICE_super')";

    private final JdbcClient jdbc;

    MatricFormatController(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    private static String blank(String v) {
        return v == null || v.isBlank() ? null : v.trim();
    }

    private static String code(String v, String what) {
        String c = blank(v) == null ? null : v.trim().toUpperCase();
        if (c != null && !c.matches("[A-Z0-9]{2,6}")) throw new DomainRuleViolation("MATRIC_CODE", "A " + what + " code is two to six letters or digits.", new DomainRuleViolation.Remedy("Give the code as the schedule prints it, or leave it blank.", "The Registry"));
        return c;
    }

    @GetMapping
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> config() {
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("format", jdbc.sql("SELECT * FROM people.matric_format WHERE id = 'UNIVERSITY'").query().singleRow());
        out.put("series", jdbc.sql("""
                SELECT ms.*, (SELECT count(*) FROM people.matric_history h WHERE h.series_code = ms.code) AS issued,
                       (SELECT max(h.issued_at) FROM people.matric_history h WHERE h.series_code = ms.code) AS last_issued_at
                  FROM people.matric_series ms ORDER BY ms.code
                """).query().listOfRows());
        out.put("faculties", jdbc.sql("SELECT f.code, f.name, f.matric_code, f.matric_series, (SELECT count(*) FROM ref.programme p WHERE p.faculty_code = f.code AND NOT p.archived) AS programmes FROM ref.faculty f ORDER BY f.name").query().listOfRows());
        out.put("programmes", jdbc.sql("SELECT * FROM people.matric_config_rows() WHERE NOT archived").query().listOfRows());
        out.put("recent", jdbc.sql("""
                SELECT h.matric_no, h.series_code, h.sequence, h.issued_at, h.reason, s.surname || ', ' || s.other_names AS student_name, p.name AS programme
                  FROM people.matric_history h JOIN people.student s ON s.id = h.student_id LEFT JOIN ref.programme p ON p.code = s.programme_code ORDER BY h.issued_at DESC LIMIT 25
                """).query().listOfRows());
        return out;
    }

    public record FormatIn(@NotBlank @Size(max = 6) String universityCode, Boolean facultyCode, Boolean programmeCode, Boolean year, Integer sequenceDigits, String separator, @Size(max = 400) String note) {
    }

    @PutMapping("/format")
    @PreAuthorize(CONFIG)
    @Transactional
    Map<String, Object> format(@Valid @RequestBody FormatIn body) {
        String u = body.universityCode().trim().toUpperCase();
        if (!u.matches("[A-Z]{2,6}")) throw new DomainRuleViolation("MATRIC_UNIVERSITY", "The University code is two to six letters.", new DomainRuleViolation.Remedy("MOAU, as the schedule prints it.", "The Registry"));
        jdbc.sql("""
                UPDATE people.matric_format SET university_code = :u, faculty_code = coalesce(:f, faculty_code), programme_code = coalesce(:p, programme_code), year = coalesce(:y, year),
                       sequence_digits = coalesce(:d, sequence_digits), separator = coalesce(:s, separator), note = :n, updated_at = now() WHERE id = 'UNIVERSITY'
                """).param("u", u).param("f", body.facultyCode(), Types.BOOLEAN).param("p", body.programmeCode(), Types.BOOLEAN).param("y", body.year(), Types.BOOLEAN)
                .param("d", body.sequenceDigits(), Types.INTEGER).param("s", blank(body.separator()), Types.VARCHAR).param("n", blank(body.note()), Types.VARCHAR).update();
        return jdbc.sql("SELECT * FROM people.matric_format WHERE id = 'UNIVERSITY'").query().singleRow();
    }

    public record SeriesIn(@NotBlank @Size(max = 80) String name, Long lastIssued, Boolean active, @Size(max = 400) String note) {
    }

    /** a series' last number is moved only forward: a number issued is never reissued */
    @PutMapping("/series/{code}")
    @PreAuthorize(CONFIG)
    @Transactional
    Map<String, Object> series(@PathVariable String code, @Valid @RequestBody SeriesIn body) {
        String c = code.trim().toUpperCase();
        if (!c.matches("[A-Z][A-Z0-9_]{1,20}")) throw new DomainRuleViolation("MATRIC_SERIES", "A series code is letters, digits and underscores.", new DomainRuleViolation.Remedy("ADMIN, COLLEGE, PHARMACY, ARCHITECTURE, GENERAL, or a new one.", "The Registry"));
        Long current = jdbc.sql("SELECT last_issued FROM people.matric_series WHERE code = :c").param("c", c).query(Long.class).optional().orElse(null);
        if (current != null && body.lastIssued() != null && body.lastIssued() < current) {
            throw new DomainRuleViolation("MATRIC_SERIES_BACK", "Series " + c + " has issued up to " + current + "; it does not go back.", new DomainRuleViolation.Remedy("A sequence once spent is never reused. Move it forward, or leave it.", "The Registry"));
        }
        jdbc.sql("""
                INSERT INTO people.matric_series (code, name, last_issued, active, note) VALUES (:c, :n, coalesce(:l, 0), coalesce(:a, true), :t)
                ON CONFLICT (code) DO UPDATE SET name = EXCLUDED.name, last_issued = coalesce(:l, people.matric_series.last_issued), active = coalesce(:a, people.matric_series.active), note = EXCLUDED.note, updated_at = now()
                """).param("c", c).param("n", body.name().trim()).param("l", body.lastIssued(), Types.BIGINT).param("a", body.active(), Types.BOOLEAN).param("t", blank(body.note()), Types.VARCHAR).update();
        return jdbc.sql("SELECT * FROM people.matric_series WHERE code = :c").param("c", c).query().singleRow();
    }

    public record FacultyIn(String matricCode, String matricSeries) {
    }

    @PutMapping("/faculties/{code}")
    @PreAuthorize(CONFIG)
    @Transactional
    Map<String, Object> faculty(@PathVariable String code, @RequestBody FacultyIn body) {
        int n = jdbc.sql("UPDATE ref.faculty SET matric_code = :m, matric_series = :s WHERE code = :c").param("m", code(body.matricCode(), "faculty"), Types.VARCHAR).param("s", blank(body.matricSeries()) == null ? null : body.matricSeries().trim().toUpperCase(), Types.VARCHAR).param("c", code.trim().toUpperCase()).update();
        if (n == 0) throw new NotFound("faculty", code);
        return jdbc.sql("SELECT code, name, matric_code, matric_series FROM ref.faculty WHERE code = :c").param("c", code.trim().toUpperCase()).query().singleRow();
    }

    public record ProgrammeIn(String matricCode, Boolean matricUsesCode, String matricFacultyCode, String matricSeries) {
    }

    /** a programme's code is never invented here: blank means none, and "carries a code" with none is refused */
    @PutMapping("/programmes/{code}")
    @PreAuthorize(CONFIG)
    @Transactional
    Map<String, Object> programme(@PathVariable String code, @RequestBody ProgrammeIn body) {
        String mc = code(body.matricCode(), "programme");
        boolean uses = body.matricUsesCode() != null ? body.matricUsesCode() : mc != null;
        if (uses && mc == null) throw new DomainRuleViolation("MATRIC_NO_CODE", "The programme is set to carry a code but none is given.", new DomainRuleViolation.Remedy("Give the code the schedule prints, or set the programme to carry none — no code is invented.", "The Registry"));
        int n = jdbc.sql("UPDATE ref.programme SET matric_code = :m, matric_uses_code = :u, matric_faculty_code = :f, matric_series = :s WHERE code = :c")
                .param("m", mc, Types.VARCHAR).param("u", uses).param("f", code(body.matricFacultyCode(), "faculty segment"), Types.VARCHAR).param("s", blank(body.matricSeries()) == null ? null : body.matricSeries().trim().toUpperCase(), Types.VARCHAR).param("c", code.trim()).update();
        if (n == 0) throw new NotFound("programme", code);
        return jdbc.sql("SELECT * FROM people.matric_config_rows() WHERE programme_code = :c").param("c", code.trim()).query().singleRow();
    }

    @GetMapping("/preview/{studentId}")
    @PreAuthorize(READERS)
    Map<String, Object> preview(@PathVariable UUID studentId) {
        return jdbc.sql("SELECT * FROM people.matric_preview(:s)").param("s", studentId).query().listOfRows().stream().findFirst().orElseThrow(() -> new NotFound("student", studentId));
    }

    @GetMapping("/history")
    @PreAuthorize(READERS)
    List<Map<String, Object>> history(@org.springframework.web.bind.annotation.RequestParam(required = false) String q) {
        String needle = blank(q) == null ? null : "%" + q.trim().toLowerCase() + "%";
        return jdbc.sql("""
                SELECT h.matric_no, h.series_code, h.sequence, h.issued_at, h.reason, h.actor_office, h.components::text AS components, s.surname || ', ' || s.other_names AS student_name, p.name AS programme, r.ref AS run_ref
                  FROM people.matric_history h JOIN people.student s ON s.id = h.student_id LEFT JOIN ref.programme p ON p.code = s.programme_code LEFT JOIN people.matriculation_run r ON r.id = h.run_id
                 WHERE :q::text IS NULL OR lower(h.matric_no) LIKE :q OR lower(s.surname || ' ' || s.other_names) LIKE :q ORDER BY h.issued_at DESC LIMIT 500
                """).param("q", needle, Types.VARCHAR).query().listOfRows();
    }
}
