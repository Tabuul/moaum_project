package ng.edu.moaum.portal.student;

import java.sql.Types;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * V536: the Registry's records check — the live students whose record is at odds with itself or the register (a level beyond
 * the programme, the postgraduate entry mode on an undergraduate programme, no state of origin…), by what is wrong, each naming
 * the office that corrects it. Read in one pass (about 0.6 s for the 54,571 live students of the live-shaped copy); nothing
 * is changed here.
 */
@RestController
@RequestMapping("/api/v1/records/issues")
@PreAuthorize("hasAnyAuthority('OFFICE_records','OFFICE_registrar','OFFICE_dregistrar','OFFICE_academic','OFFICE_pgschool','OFFICE_pgsecretary','OFFICE_ict','OFFICE_admin','OFFICE_super')")
class RecordIssuesController {

    /** the rows sent at most; the counts are always whole */
    static final int MAX_ROWS = 20_000;

    private final JdbcClient jdbc;

    RecordIssuesController(JdbcClient jdbc) {
        this.jdbc = jdbc;
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
}
