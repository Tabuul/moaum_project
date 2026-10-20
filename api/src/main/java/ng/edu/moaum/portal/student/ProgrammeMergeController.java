package ng.edu.moaum.portal.student;

import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotEmpty;
import jakarta.validation.constraints.Size;

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

/** V574: duplicate programmes merged into one, with their students — the merges proposed, what a set of them would do, the merges
 *  made (by the Registry, and the School of Postgraduate Studies for postgraduate programmes) and undone. The rules are the
 *  database's (ref.merge_programme and its neighbours). */
@RestController
@RequestMapping("/api/v1/records/programme-merge")
class ProgrammeMergeController {

    static final String READERS = "hasAnyAuthority('OFFICE_records','OFFICE_registrar','OFFICE_dregistrar','OFFICE_academic','OFFICE_pgschool','OFFICE_pgsecretary','OFFICE_ict','OFFICE_admin','OFFICE_super')";
    static final String MERGERS = "hasAnyAuthority('OFFICE_records','OFFICE_registrar','OFFICE_dregistrar','OFFICE_pgschool','OFFICE_pgsecretary','OFFICE_super')";

    public record Pair(@NotBlank @Size(max = 20) String from, @NotBlank @Size(max = 20) String to) {
    }

    public record Preview(@NotEmpty @Size(max = 500) List<@Valid Pair> pairs) {
    }

    public record Merge(@NotEmpty @Size(max = 500) List<@Valid Pair> pairs, @NotBlank @Size(min = 10, max = 2000) String reason) {
    }

    public record Undo(@NotBlank @Size(min = 10, max = 2000) String reason) {
    }

    private final JdbcClient jdbc;
    private final tools.jackson.databind.ObjectMapper json;

    ProgrammeMergeController(JdbcClient jdbc, tools.jackson.databind.ObjectMapper json) {
        this.jdbc = jdbc;
        this.json = json;
    }

    private static String category(String c) {
        return "UNDER GRADUATE".equalsIgnoreCase(c == null ? "" : c.trim()) ? "UNDER GRADUATE" : "POST GRADUATE";
    }

    /** the merges proposed for a category, and every programme of it a code may be merged into */
    @GetMapping("/suggestions")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> suggestions(@RequestParam(defaultValue = "POST GRADUATE") String category) {
        String c = category(category);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("category", c);
        out.put("suggestions", jdbc.sql("""
                SELECT step, kind, from_code, from_name, from_students, to_code, to_name, why, choices::text AS choices
                  FROM ref.programme_merge_suggestions(:c)
                """).param("c", c).query().listOfRows());
        out.put("programmes", jdbc.sql("""
                SELECT p.code, p.name, p.pg_award AS award, p.dept_code, p.faculty_code,
                       (SELECT count(*) FROM people.student s WHERE s.programme_code = p.code) AS students
                  FROM ref.programme p
                 WHERE p.category = :c AND NOT coalesce(p.archived, false)
                 ORDER BY p.pg_award IS NULL, p.name, p.code
                """).param("c", c).query().listOfRows());
        return out;
    }

    /** what the merges would do, in order, done and undone: each one's students, the rows moved and kept, or why it is refused */
    @PostMapping("/preview")
    @PreAuthorize(READERS)
    @Transactional
    Object preview(@Valid @RequestBody Preview body) {
        return json.readValue(jdbc.sql("SELECT ref.programme_merge_effect(:p::jsonb)::text").param("p", json.writeValueAsString(body.pairs())).query(String.class).single(), Object.class);
    }

    /** the merges made, in order, in one act */
    @PostMapping
    @PreAuthorize(MERGERS)
    @Transactional
    Object merge(@Valid @RequestBody Merge body) {
        return json.readValue(jdbc.sql("SELECT ref.merge_programmes(:p::jsonb, :r)::text").param("p", json.writeValueAsString(body.pairs())).param("r", body.reason().trim())
                .query(String.class).single(), Object.class);
    }

    /** the merges made, the latest first, with who made each and its undoing */
    @GetMapping("/history")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> history() {
        return jdbc.sql("""
                SELECT m.id, m.from_code, m.from_name, m.to_code, m.to_name, m.reason, m.students, m.moved::text AS moved, m.kept::text AS kept, m.merged_at,
                       m.merged_office, m.undone_at, m.undo_reason,
                       CASE WHEN mp.id IS NULL THEN NULL ELSE mp.surname || ', ' || mp.given_names END AS merged_by_name,
                       CASE WHEN up.id IS NULL THEN NULL ELSE up.surname || ', ' || up.given_names END AS undone_by_name,
                       m.undone_at IS NULL AND NOT EXISTS (SELECT 1 FROM ref.programme_alias a WHERE a.alias_code = m.to_code AND a.ended_at IS NULL) AS may_undo
                  FROM ref.programme_merge m
                  LEFT JOIN iam.person mp ON mp.id = m.merged_by
                  LEFT JOIN iam.person up ON up.id = m.undone_by
                 ORDER BY m.merged_at DESC LIMIT 400
                """).query().listOfRows();
    }

    /** a merge undone from its record */
    @PostMapping("/{id}/undo")
    @PreAuthorize(MERGERS)
    @Transactional
    Object undo(@PathVariable UUID id, @Valid @RequestBody Undo body) {
        return json.readValue(jdbc.sql("SELECT ref.undo_programme_merge(:m, :r)::text").param("m", id).param("r", body.reason().trim()).query(String.class).single(), Object.class);
    }
}
