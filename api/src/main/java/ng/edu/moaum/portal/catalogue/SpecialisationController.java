package ng.edu.moaum.portal.catalogue;

import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import jakarta.validation.Valid;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

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

import ng.edu.moaum.portal.shared.DomainRuleViolation;
import ng.edu.moaum.portal.shared.NotFound;
import ng.edu.moaum.portal.shared.OfficeScope;

/**
 * V483: a postgraduate programme's specialisations, on its one structure — added, renamed, ended; the bindings named for
 * them (a binding named for none is for every student); the students who read them. Kept by whoever keeps the programme's
 * structure (the School of Postgraduate Studies for a postgraduate programme, its department, the Academic Office, ICT
 * Support within its postings — StructureAccess), read by whoever reads it.
 */
@RestController
@RequestMapping("/api/v1/catalogue/structure/specialisations")
class SpecialisationController {

    private static final String STRUCTURE = "hasAnyAuthority('OFFICE_hod','OFFICE_dean','OFFICE_academic','OFFICE_dregistrar','OFFICE_registrar','OFFICE_admin','OFFICE_super','OFFICE_ict','OFFICE_pgschool','OFFICE_pgsecretary','OFFICE_ictagent','OFFICE_helpdeskhead')";
    private static final String READERS = "hasAnyAuthority('OFFICE_hod','OFFICE_dean','OFFICE_academic','OFFICE_dregistrar','OFFICE_registrar','OFFICE_admin','OFFICE_super','OFFICE_lecturer','OFFICE_exams','OFFICE_facultyexams','OFFICE_facultyofficer','OFFICE_records','OFFICE_dvc','OFFICE_vc','OFFICE_ict','OFFICE_pgschool','OFFICE_pgsecretary','OFFICE_ictagent','OFFICE_helpdeskhead')";

    private final JdbcClient jdbc;
    private final OfficeScope scope;
    private final StructureAccess access;

    SpecialisationController(JdbcClient jdbc, OfficeScope scope, StructureAccess access) {
        this.jdbc = jdbc;
        this.scope = scope;
        this.access = access;
    }

    public record SpecialisationIn(@NotBlank @Size(max = 12) String programme, @NotBlank @Size(max = 12) String code, @NotBlank @Size(max = 120) String name) {
    }

    public record BindingIn(@NotBlank @Size(max = 12) String programme, @NotBlank @Size(max = 24) String course,
                            @NotNull @Min(100) @Max(900) Integer level, List<UUID> specialisations) {
    }

    public record StudentsIn(@NotBlank @Size(max = 12) String programme, UUID specialisation, @NotNull @Size(min = 1, max = 2000) List<UUID> students) {
    }

    /** the programme's specialisations with their students and courses, and the programme's students with the one each reads */
    @GetMapping
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> list(@RequestParam String prog) {
        String p = prog.trim().toUpperCase();
        scope.bound(null, null, p);                        // a department office reads its own programmes only
        access.requireView();
        Map<String, Object> programme = jdbc.sql("SELECT code, name, category FROM ref.programme WHERE code = :p").param("p", p)
                .query().listOfRows().stream().findFirst().orElseThrow(() -> new NotFound("programme", prog));
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("programme", programme);
        out.put("postgraduate", "POST GRADUATE".equals(programme.get("category")));
        out.put("specialisations", jdbc.sql("""
                SELECT ps.id, ps.code, ps.name, ps.active, ps.created_at, ps.ended_at,
                       (SELECT count(*) FROM people.student_specialisation ss JOIN people.student st ON st.id = ss.student_id AND st.programme_code = ps.programme_code
                         WHERE ss.specialisation_id = ps.id) AS students,
                       (SELECT count(*) FROM catalogue.course_offer_specialisation x WHERE x.specialisation_id = ps.id) AS courses
                  FROM catalogue.programme_specialisation ps
                 WHERE ps.programme_code = :p
                 ORDER BY ps.active DESC, ps.code
                """).param("p", p).query().listOfRows());
        out.put("students", jdbc.sql("""
                SELECT st.id, st.matric_no, st.admission_no, st.surname || ', ' || st.other_names AS name, st.current_level AS level, st.status,
                       ss.specialisation_id
                  FROM people.student st
                  LEFT JOIN people.student_specialisation ss ON ss.student_id = st.id
                 WHERE st.programme_code = :p AND st.status IN ('ADMITTED', 'ACTIVE', 'PROBATION')
                 ORDER BY st.current_level, st.surname, st.other_names
                 LIMIT 2000
                """).param("p", p).query().listOfRows());
        out.put("may", Map.of("change", !StructureAccess.special() || access.mayProgramme(p), "ticket", StructureAccess.ticketOffice()));
        return out;
    }

    @PostMapping
    @PreAuthorize(STRUCTURE)
    @Transactional
    Map<String, Object> add(@Valid @RequestBody SpecialisationIn body, @RequestParam(required = false) String ticket) {
        String p = keep(body.programme());
        UUID on = access.ticket(ticket);
        UUID id = jdbc.sql("SELECT catalogue.save_specialisation(:p, :c, :n)").param("p", p).param("c", body.code()).param("n", body.name())
                .query(UUID.class).single();
        access.note(on, "Added the specialisation " + body.code().trim().toUpperCase() + " (" + body.name().trim() + ") to " + p);
        return Map.of("id", id, "programme", p);
    }

    @PutMapping("/{id}")
    @PreAuthorize(STRUCTURE)
    @Transactional
    Map<String, Object> rename(@PathVariable UUID id, @Valid @RequestBody SpecialisationIn body, @RequestParam(required = false) String ticket) {
        String p = keep(body.programme());
        UUID on = access.ticket(ticket);
        jdbc.sql("SELECT catalogue.save_specialisation(:p, :c, :n, :id)").param("p", p).param("c", body.code()).param("n", body.name()).param("id", id)
                .query(UUID.class).single();
        access.note(on, "Renamed a specialisation of " + p + ": " + body.code().trim().toUpperCase() + " (" + body.name().trim() + ")");
        return Map.of("id", id, "programme", p);
    }

    /** ended (no longer given to a student; its students and courses keep it) or restored */
    @PostMapping("/{id}/{verb:end|restore}")
    @PreAuthorize(STRUCTURE)
    @Transactional
    Map<String, Object> end(@PathVariable UUID id, @PathVariable String verb, @RequestParam(required = false) String ticket) {
        String p = jdbc.sql("SELECT programme_code FROM catalogue.programme_specialisation WHERE id = :id").param("id", id)
                .query(String.class).optional().orElseThrow(() -> new NotFound("specialisation", id));
        keep(p);
        UUID on = access.ticket(ticket);
        jdbc.sql("SELECT catalogue.end_specialisation(:id, :a)").param("id", id).param("a", "restore".equals(verb)).query().listOfRows();
        access.note(on, ("restore".equals(verb) ? "Restored" : "Ended") + " a specialisation of " + p);
        return Map.of("id", id, "active", "restore".equals(verb));
    }

    /** the specialisations a binding is for; none is every student of the programme */
    @PutMapping("/binding")
    @PreAuthorize(STRUCTURE)
    @Transactional
    Map<String, Object> binding(@Valid @RequestBody BindingIn body, @RequestParam(required = false) String ticket) {
        String p = keep(body.programme());
        String c = body.course().trim().toUpperCase();
        UUID on = access.ticket(ticket);
        List<UUID> ids = body.specialisations() == null ? List.of() : body.specialisations();
        int n = jdbc.sql("SELECT catalogue.set_offer_specialisations(:c, :p, :l, :ids)").param("c", c).param("p", p).param("l", body.level())
                .param("ids", ids.toArray(UUID[]::new)).query(Integer.class).single();
        access.note(on, c + " in " + p + " at " + body.level() + " level is now for " + (n == 0 ? "every student" : n + " specialisation" + (n == 1 ? "" : "s")));
        return Map.of("programme", p, "course", c, "level", body.level(), "specialisations", n);
    }

    /** the specialisation the students read (none clears it); each a student of the programme, the specialisation the programme's own */
    @PutMapping("/students")
    @PreAuthorize(STRUCTURE)
    @Transactional
    Map<String, Object> students(@Valid @RequestBody StudentsIn body, @RequestParam(required = false) String ticket) {
        String p = keep(body.programme());
        UUID on = access.ticket(ticket);
        long outside = jdbc.sql("SELECT count(*) FROM unnest(CAST(:ids AS uuid[])) x WHERE NOT EXISTS (SELECT 1 FROM people.student st WHERE st.id = x AND st.programme_code = :p)")
                .param("ids", body.students().toArray(UUID[]::new)).param("p", p).query(Long.class).single();
        if (outside > 0) {
            throw new DomainRuleViolation("PG_SPECIALISATION_OTHER", outside + " of the students named " + (outside == 1 ? "is" : "are") + " not a student of " + p + ".",
                    new DomainRuleViolation.Remedy("Choose the programme's own students.", "School of Postgraduate Studies"));
        }
        int changed = 0;
        for (UUID s : body.students()) {
            jdbc.sql("SELECT people.set_student_specialisation(:s, :sp)").param("s", s).param("sp", body.specialisation(), java.sql.Types.OTHER)
                    .query().listOfRows();
            changed++;
        }
        access.note(on, changed + " student" + (changed == 1 ? "" : "s") + " of " + p + (body.specialisation() == null ? ": specialisation cleared" : ": specialisation set"));
        return Map.of("programme", p, "students", changed);
    }

    /** the acting office keeps this programme's structure: an HOD their own department's, the School its postgraduate
     *  programmes, ICT Support within its postings (StructureAccess) */
    private String keep(String programme) {
        String p = programme.trim().toUpperCase();
        String dept = jdbc.sql("SELECT dept_code FROM ref.programme WHERE upper(code) = :p").param("p", p).query(String.class)
                .optional().orElseThrow(() -> new NotFound("programme", programme));
        if (scope.actingHod()) {
            String mine = scope.scopedDept(null);
            if (mine != null && !mine.equalsIgnoreCase(dept)) {
                throw new DomainRuleViolation("CAT_DEPT", "This programme belongs to another department.",
                        new DomainRuleViolation.Remedy("A Head of Department keeps their own department's programmes.", "Head of Department"));
            }
        }
        access.assertProgramme(p);
        return p;
    }
}
