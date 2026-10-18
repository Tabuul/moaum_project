package ng.edu.moaum.portal.student;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;
import java.sql.Types;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.stream.Collectors;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * V536: the Registry's records check — the live students whose record is at odds with itself or the register (a level beyond
 * the programme, the postgraduate entry mode on an undergraduate programme, no state of origin…), by what is wrong, each naming
 * the office that corrects it. Read in one pass (about 0.6 s for the 54,571 live students of the live-shaped copy); nothing
 * is changed here.
 *
 * <p>V548: the students with no state of origin are told from here (at most once a week each) and their progress read; a
 * postgraduate record on an undergraduate programme is moved to a postgraduate programme here, with the reason.
 */
@RestController
@RequestMapping("/api/v1/records/issues")
@PreAuthorize("hasAnyAuthority('OFFICE_records','OFFICE_registrar','OFFICE_dregistrar','OFFICE_academic','OFFICE_pgschool','OFFICE_pgsecretary','OFFICE_ict','OFFICE_admin','OFFICE_super')")
class RecordIssuesController {

    /** the rows sent at most; the counts are always whole */
    static final int MAX_ROWS = 20_000;

    /** V548: who tells the students of an issue that is theirs to correct */
    static final String TELLERS = "hasAnyAuthority('OFFICE_records','OFFICE_registrar','OFFICE_dregistrar','OFFICE_ict','OFFICE_super')";
    /** V548: who moves a postgraduate record to its programme */
    static final String MOVERS = "hasAnyAuthority('OFFICE_records','OFFICE_registrar','OFFICE_dregistrar','OFFICE_pgschool','OFFICE_pgsecretary','OFFICE_super')";

    private final JdbcClient jdbc;
    private final tools.jackson.databind.ObjectMapper json;

    RecordIssuesController(JdbcClient jdbc, tools.jackson.databind.ObjectMapper json) {
        this.jdbc = jdbc;
        this.json = json;
    }

    @SuppressWarnings("unchecked")
    private Map<String, Object> read(String text) {
        return text == null ? null : json.readValue(text, Map.class);
    }

    @GetMapping
    @Transactional(readOnly = true)
    Map<String, Object> issues(@RequestParam(required = false) String issue, @RequestParam(required = false) String faculty) {
        String fac = faculty == null || faculty.isBlank() ? null : faculty.trim();
        String only = issue == null || issue.isBlank() ? null : issue.trim().toUpperCase();
        List<Map<String, Object>> all = jdbc.sql("SELECT * FROM people.record_issues(NULL, :f)").param("f", fac, Types.VARCHAR).query().listOfRows();
        Map<Object, Long> counts = all.stream().collect(Collectors.groupingBy(r -> r.get("issue"), Collectors.counting()));
        List<Map<String, Object>> kinds = jdbc.sql("SELECT code, title, why, corrects, offices, how FROM people.record_issue_kind ORDER BY ord").query().listOfRows()
                .stream().map(k -> {
                    Map<String, Object> m = new LinkedHashMap<>(k);
                    Object offices = m.get("offices");
                    if (offices instanceof java.sql.Array a) {
                        try { m.put("offices", List.of((Object[]) a.getArray())); } catch (java.sql.SQLException e) { m.put("offices", List.of()); }
                    }
                    m.put("students", counts.getOrDefault(k.get("code"), 0L));
                    return m;
                }).toList();
        List<Map<String, Object>> rows = all.stream().filter(r -> only == null || only.equals(r.get("issue"))).limit(MAX_ROWS).toList();
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("issue", only);
        out.put("faculty", fac);
        out.put("students", all.stream().map(r -> r.get("student_id")).distinct().count());
        out.put("total", all.stream().filter(r -> only == null || only.equals(r.get("issue"))).count());
        out.put("kinds", kinds);
        out.put("rows", rows);
        out.put("faculties", jdbc.sql("SELECT code, name FROM ref.faculty ORDER BY name").query().listOfRows());
        return out;
    }

    /** V548: of the students told about an issue — listed, told, given since, still missing, never told, the notices' delivery */
    @GetMapping("/notices")
    @Transactional(readOnly = true)
    Map<String, Object> progress(@RequestParam(defaultValue = "NO_STATE_OF_ORIGIN") String issue, @RequestParam(required = false) String faculty) {
        String fac = faculty == null || faculty.isBlank() ? null : faculty.trim();
        return read(jdbc.sql("SELECT people.record_issue_progress(:i, :f)::text").param("i", issue.trim().toUpperCase()).param("f", fac, Types.VARCHAR)
                .query(String.class).single());
    }

    public record TellIn(@NotBlank String issue, String faculty) {
    }

    /** V548: tell the students with no state of origin (of a faculty, or all) to give it — at most once a week each */
    @PostMapping("/notices")
    @PreAuthorize(TELLERS)
    @Transactional
    Map<String, Object> tell(@Valid @RequestBody TellIn body) {
        String fac = body.faculty() == null || body.faculty().isBlank() ? null : body.faculty().trim();
        Map<String, Object> out = new LinkedHashMap<>(read(jdbc.sql("SELECT people.tell_record_issue(:i, :f)::text")
                .param("i", body.issue().trim().toUpperCase()).param("f", fac, Types.VARCHAR).query(String.class).single()));
        out.put("progress", progress(body.issue(), fac));
        return out;
    }

    /** V548: a student's record, whether it may be moved to a postgraduate programme here, and the programmes (the department's first) */
    @GetMapping("/move/{student}")
    @Transactional(readOnly = true)
    Map<String, Object> moveOptions(@PathVariable UUID student) {
        return read(jdbc.sql("SELECT people.record_move_options(s.id)::text FROM people.student s WHERE s.id = :s").param("s", student)
                .query(String.class).optional().orElseThrow(() -> new ng.edu.moaum.portal.shared.NotFound("student", student)));
    }

    public record MoveIn(@NotBlank String programme, @NotNull Integer level, @NotBlank @Size(min = 10, max = 500) String reason) {
    }

    /** V548: a postgraduate record on an undergraduate programme moved to a postgraduate programme, with the reason */
    @PostMapping("/move/{student}")
    @PreAuthorize(MOVERS)
    @Transactional
    Map<String, Object> move(@PathVariable UUID student, @Valid @RequestBody MoveIn body) {
        return read(jdbc.sql("SELECT people.move_record_to_programme(:s, :p, :l, :r)::text").param("s", student)
                .param("p", body.programme().trim()).param("l", body.level()).param("r", body.reason().trim()).query(String.class).single());
    }
}
