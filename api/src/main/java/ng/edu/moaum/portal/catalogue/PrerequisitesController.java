package ng.edu.moaum.portal.catalogue;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.interceptor.TransactionAspectSupport;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import ng.edu.moaum.portal.shared.DomainRuleViolation;

/**
 * V487: prerequisites uploaded in bulk and the impact of enforcing them. A file of (course, requires) rows is previewed row by
 * row — the same write, rolled back — then imported; each row is written through catalogue.add_prerequisite, so a loop is
 * refused at the row that would close it. A row is the acting office's only where it may set that course's prerequisites on
 * the course page (its department's courses; the Academic Office and the Registry any; the School and the ICT Support Desk
 * within StructureAccess's reach); another is reported, never written. The impact lists the students in study whom enforcing
 * prerequisites stops, by course.
 */
@RestController
@RequestMapping("/api/v1/catalogue/prerequisites")
class PrerequisitesController {

    /** the offices that set prerequisites on the course page (V338, V471); the Director of ICT keeps the structure, not the courses (V460) */
    private static final String SETTERS = "hasAnyAuthority('OFFICE_hod','OFFICE_dean','OFFICE_academic','OFFICE_dregistrar','OFFICE_registrar','OFFICE_admin','OFFICE_super','OFFICE_pgschool','OFFICE_pgsecretary','OFFICE_ictagent','OFFICE_helpdeskhead')";
    /** whom enforcing stops is read by the offices that decide on it and those that support registration */
    private static final String IMPACT = "hasAnyAuthority('OFFICE_academic','OFFICE_dregistrar','OFFICE_registrar','OFFICE_admin','OFFICE_super','OFFICE_ict')";
    private static final int MAX_ROWS = 5000;

    private final JdbcClient jdbc;
    private final OfferAuthority authority;
    private final StructureAccess access;

    PrerequisitesController(JdbcClient jdbc, OfferAuthority authority, StructureAccess access) {
        this.jdbc = jdbc;
        this.authority = authority;
        this.access = access;
    }

    public record RowsIn(@NotNull @Size(min = 1, max = MAX_ROWS) List<Map<String, Object>> rows) {
    }

    /** what the upload would do, row by row; nothing is kept */
    @PostMapping("/upload/preview")
    @PreAuthorize(SETTERS)
    @Transactional
    Map<String, Object> preview(@Valid @RequestBody RowsIn body) {
        Map<String, Object> out = load(body.rows());
        TransactionAspectSupport.currentTransactionStatus().setRollbackOnly();
        return out;
    }

    /** the rows written; each row's outcome returned */
    @PostMapping("/upload")
    @PreAuthorize(SETTERS)
    @Transactional
    Map<String, Object> upload(@Valid @RequestBody RowsIn body) {
        return load(body.rows());
    }

    /** the students in study whom enforcing prerequisites stops: by course, and one course's students when asked */
    @GetMapping("/impact")
    @PreAuthorize(IMPACT)
    @Transactional(readOnly = true)
    Map<String, Object> impact(@RequestParam(required = false) String course) {
        String c = course == null || course.isBlank() ? null : course.trim().toUpperCase();
        List<Map<String, Object>> rows = jdbc.sql("SELECT * FROM registration.prerequisite_impact(:c)").param("c", c, java.sql.Types.VARCHAR).query().listOfRows();
        Map<String, Map<String, Object>> byCourse = new LinkedHashMap<>();
        java.util.Set<Object> students = new java.util.HashSet<>();
        int registered = 0;
        for (Map<String, Object> r : rows) {
            students.add(r.get("student_id"));
            boolean reg = Boolean.TRUE.equals(r.get("registered"));
            if (reg) registered++;
            Map<String, Object> k = byCourse.computeIfAbsent(String.valueOf(r.get("course_code")), x -> {
                Map<String, Object> m = new LinkedHashMap<>();
                m.put("course_code", r.get("course_code"));
                m.put("title", r.get("title"));
                m.put("unmet", r.get("unmet"));
                m.put("students", 0);
                m.put("registered", 0);
                m.put("programmes", new java.util.TreeSet<String>());
                return m;
            });
            k.put("students", (Integer) k.get("students") + 1);
            if (reg) k.put("registered", (Integer) k.get("registered") + 1);
            ((java.util.Set<String>) k.get("programmes")).add(String.valueOf(r.get("programme")));
        }
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("mode", jdbc.sql("SELECT registration.prerequisite_mode()").query(String.class).single());
        out.put("total", rows.size());
        out.put("students", students.size());
        out.put("registered", registered);
        out.put("courses", byCourse.values().stream().map(m -> { m.put("programmes", String.join(", ", (java.util.Set<String>) m.get("programmes"))); return m; }).toList());
        // one course's students in full; the whole University's as the first rows only (the courses carry the counts)
        out.put("rows", c != null ? rows : rows.subList(0, Math.min(rows.size(), 2000)));
        out.put("course", c);
        return out;
    }

    /** each row's course resolved as the pool reads it, held to the acting office's reach, the rest written row by row */
    private Map<String, Object> load(List<Map<String, Object>> in) {
        List<Map<String, Object>> rows = new ArrayList<>();
        for (Map<String, Object> r : in) {
            Map<String, Object> m = new HashMap<>();
            m.put("course", str(r.get("course")));
            m.put("requires", str(r.get("requires")));
            rows.add(m);
        }
        // the course each row names, as the pool reads it, and its department
        List<Map<String, Object>> resolved = jdbc.sql("""
                SELECT t.ord::int AS ord, coalesce(catalogue.resolve_course_code(t.x->>'course'), upper(regexp_replace(btrim(t.x->>'course'), '\\s+', ' ', 'g'))) AS code,
                       c.dept_code
                  FROM jsonb_array_elements(CAST(:rows AS jsonb)) WITH ORDINALITY AS t(x, ord)
                  LEFT JOIN catalogue.course c ON c.code = coalesce(catalogue.resolve_course_code(t.x->>'course'), upper(regexp_replace(btrim(t.x->>'course'), '\\s+', ' ', 'g')))
                 ORDER BY t.ord
                """).param("rows", json(rows)).query().listOfRows();
        Map<String, Boolean> may = new HashMap<>();
        List<Map<String, Object>> allowed = new ArrayList<>();
        Map<Integer, Map<String, Object>> refused = new HashMap<>();
        boolean special = StructureAccess.special();
        for (int i = 0; i < rows.size(); i++) {
            Map<String, Object> rs = resolved.get(i);
            String code = (String) rs.get("code");
            String dept = (String) rs.get("dept_code");
            boolean ok = code == null || code.isBlank() || dept == null
                    || may.computeIfAbsent(code, x -> special ? access.mayCourse(x, StructureAccess.PREREQ) : authority.owns(dept));
            if (ok) {
                allowed.add(rows.get(i));
            } else {
                Map<String, Object> o = new LinkedHashMap<>();
                o.put("row_no", i + 1);
                o.put("course_in", rows.get(i).get("course"));
                o.put("requires_in", rows.get(i).get("requires"));
                o.put("course_code", code);
                o.put("requires_code", null);
                o.put("outcome", "OUTSIDE_SCOPE");
                o.put("message", code + " is another department's course; its own department or the Academic Office sets its prerequisites.");
                refused.put(i + 1, o);
            }
        }
        List<Map<String, Object>> written = allowed.isEmpty() ? List.of()
                : jdbc.sql("SELECT * FROM catalogue.load_prerequisites(CAST(:rows AS jsonb))").param("rows", json(allowed)).query().listOfRows();
        // the outcomes back in the file's order (the function numbers the rows it was given)
        List<Map<String, Object>> out = new ArrayList<>();
        int w = 0;
        for (int i = 1; i <= rows.size(); i++) {
            if (refused.containsKey(i)) {
                out.add(refused.get(i));
            } else {
                Map<String, Object> o = new LinkedHashMap<>(written.get(w++));
                o.put("row_no", i);
                out.add(o);
            }
        }
        Map<String, Integer> counts = new LinkedHashMap<>();
        for (String k : List.of("ADDED", "ALREADY", "NO_COURSE", "NO_REQUIRED", "SELF", "CYCLE", "REFUSED", "INCOMPLETE", "OUTSIDE_SCOPE")) counts.put(k, 0);
        for (Map<String, Object> o : out) counts.merge(String.valueOf(o.get("outcome")), 1, Integer::sum);
        Map<String, Object> result = new LinkedHashMap<>();
        result.put("total", out.size());
        result.put("counts", counts);
        result.put("added", counts.get("ADDED"));
        result.put("rows", out);
        if (out.isEmpty()) {
            throw new DomainRuleViolation("PREREQ_ROWS", "The file has no rows to read.",
                    new DomainRuleViolation.Remedy("Download the template, fill it and upload it.", "Academic Office"));
        }
        return result;
    }

    private static String str(Object o) {
        return o == null ? "" : String.valueOf(o).trim();
    }

    private static String json(Object o) {
        try {
            return new tools.jackson.databind.ObjectMapper().writeValueAsString(o);
        } catch (RuntimeException e) {
            throw new IllegalArgumentException("the rows could not be read", e);
        }
    }
}
