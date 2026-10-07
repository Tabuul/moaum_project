package ng.edu.moaum.portal.results;

import java.sql.Types;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import jakarta.validation.Valid;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

import ng.edu.moaum.portal.shared.AuditContext;
import ng.edu.moaum.portal.shared.AuditContextHolder;
import ng.edu.moaum.portal.shared.NotFound;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * Amendments of a published result (V358): one student's mark on a published sheet corrected — raised by the desk of entry
 * (the course's lecturer, or the Programme Examinations Officer on the lecturer's behalf, or the GST / EPS office for its own
 * courses) with the reason, approved by each desk of the chain in turn (V357's rule: the stage's own office, never the person
 * who took the previous step), and applied by the Registrar on the Senate minute as a new version of the mark. A desk may
 * refuse it with the reason; the person who raised it may withdraw it. Everything keeps to the sheet's own scope.
 */
@RestController
@RequestMapping("/api/v1/results")
class AmendmentsController {

    private static final String READERS =
            "hasAnyAuthority('OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar','OFFICE_dvc','OFFICE_vc','OFFICE_records',"
            + "'OFFICE_dean','OFFICE_hod','OFFICE_exams','OFFICE_facultyexams','OFFICE_facultyofficer','OFFICE_lecturer',"
            + "'OFFICE_ict','OFFICE_admin','OFFICE_super','OFFICE_gst','OFFICE_eps')";
    private static final String ENTRY = "hasAnyAuthority('OFFICE_lecturer','OFFICE_exams','OFFICE_gst','OFFICE_eps')";
    private static final String DESKS =
            "hasAnyAuthority('OFFICE_exams','OFFICE_hod','OFFICE_facultyexams','OFFICE_facultyofficer','OFFICE_dean','OFFICE_records',"
            + "'OFFICE_registrar','OFFICE_dregistrar')";

    private final JdbcClient jdbc;
    private final ResultsService results;
    private final tools.jackson.databind.ObjectMapper json;

    AmendmentsController(JdbcClient jdbc, ResultsService results, tools.jackson.databind.ObjectMapper json) {
        this.jdbc = jdbc;
        this.results = results;
        this.json = json;
    }

    private List<Map<String, Object>> of(UUID sheet) {
        List<Map<String, Object>> out = new ArrayList<>();
        for (Map<String, Object> r : jdbc.sql("SELECT *, decisions::text AS decisions_text FROM assessment.amendments_of(:s)").param("s", sheet).query().listOfRows()) {
            Map<String, Object> m = new LinkedHashMap<>(r);
            m.remove("decisions_text");
            m.put("decisions", json.readValue(String.valueOf(r.get("decisions_text")), new tools.jackson.core.type.TypeReference<List<Map<String, Object>>>() { }));
            out.add(m);
        }
        return out;
    }

    /** the amendment as its sheet's scope allows: its stage, its sheet and the course */
    private Map<String, Object> amendment(UUID id) {
        Map<String, Object> a = jdbc.sql("""
                SELECT m.id, m.ref, m.stage, m.sheet_id, o.course_code FROM assessment.amendment m
                  JOIN assessment.score_sheet s ON s.id = m.sheet_id JOIN catalogue.offering o ON o.id = s.offering_id WHERE m.id = :id
                """).param("id", id).query().listOfRows().stream().findFirst().orElseThrow(() -> new NotFound("amendment", id));
        results.reach((UUID) a.get("sheet_id"));
        return a;
    }

    @GetMapping("/sheets/{id}/amendments")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> list(@PathVariable UUID id) {
        results.reach(id);
        return of(id);
    }

    public record RaiseIn(@NotNull UUID studentId, @Min(0) @Max(100) Integer ca, @Min(0) @Max(100) Integer exam,
                          @Pattern(regexp = "GRADED|ABSENT|WITHHELD|INCOMPLETE|MALPRACTICE|EXEMPTED") String outcome,
                          @NotBlank @Size(min = 10, max = 2000) String reason, UUID queryId) {
    }

    /** raised on a published sheet by the desk of entry, within the sheet's scope */
    @PostMapping("/sheets/{id}/amendments")
    @PreAuthorize(ENTRY)
    @Transactional
    List<Map<String, Object>> raise(@PathVariable UUID id, @Valid @RequestBody RaiseIn b) {
        Sheets.Row r = results.reach(id);
        ResultsService.requireStageDesk("ENTRY", r.courseCode(), "raised");
        jdbc.sql("SELECT assessment.raise_amendment(:s, :st, :ca, :ex, :o, :r, :q)").param("s", id).param("st", b.studentId())
                .param("ca", b.ca(), Types.INTEGER).param("ex", b.exam(), Types.INTEGER).param("o", b.outcome(), Types.VARCHAR)
                .param("r", b.reason().trim()).param("q", b.queryId(), Types.OTHER).query().singleRow();
        return of(id);
    }

    /** the open amendments at a stage this office takes, within its scope — the desk's own list */
    @GetMapping("/amendments")
    @PreAuthorize(DESKS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> mine() {
        String office = AuditContextHolder.current().map(AuditContext::actorOffice).orElse("");
        List<String> stages = Sheets.DESK.entrySet().stream().filter(e -> e.getValue().contains(office)).map(Map.Entry::getKey).toList();
        if (stages.isEmpty()) return List.of();
        List<Map<String, Object>> out = new ArrayList<>();
        for (Map<String, Object> r : jdbc.sql("""
                SELECT m.id, m.ref, m.stage, m.sheet_id, m.raised_at, m.reason, m.outcome, m.ca, m.exam, m.was_ca, m.was_exam, m.was_outcome,
                       o.course_code, o.session, o.semester, coalesce(st.matric_no, st.admission_no) AS number, upper(st.surname) || ', ' || st.other_names AS name,
                       (SELECT d.actor_id FROM assessment.amendment_decision d WHERE d.amendment_id = m.id AND d.kind IN ('RAISE', 'ADVANCE') ORDER BY d.decided_at DESC LIMIT 1) AS last_actor
                  FROM assessment.amendment m JOIN assessment.score_sheet s ON s.id = m.sheet_id JOIN catalogue.offering o ON o.id = s.offering_id
                  JOIN people.student st ON st.id = m.student_id
                 WHERE m.stage = ANY (:stages) ORDER BY m.raised_at
                """).param("stages", stages.toArray(new String[0])).query().listOfRows()) {
            try {
                results.reach((UUID) r.get("sheet_id"));
                out.add(r);
            } catch (AccessDeniedException | NotFound outside) {
                // outside this desk's scope: not theirs to see
            }
        }
        return out;
    }

    public record StepIn(@Size(max = 2000) String comment, @Size(max = 80) String minute) {
    }

    /** approved by the desk of its stage; at Senate, applied on the minute */
    @PostMapping("/amendments/{id}/advance")
    @PreAuthorize(DESKS)
    @Transactional
    List<Map<String, Object>> advance(@PathVariable UUID id, @Valid @RequestBody(required = false) StepIn b) {
        Map<String, Object> a = amendment(id);
        String stage = String.valueOf(a.get("stage"));
        if (!List.of("APPLIED", "REFUSED", "WITHDRAWN").contains(stage)) ResultsService.requireStageDesk(stage, "Amendment " + a.get("ref"), "approved");
        jdbc.sql("SELECT assessment.advance_amendment(:a, :c, :m)").param("a", id).param("c", b == null ? null : b.comment(), Types.VARCHAR)
                .param("m", b == null ? null : b.minute(), Types.VARCHAR).query().singleRow();
        return of((UUID) a.get("sheet_id"));
    }

    public record ReasonIn(@NotBlank @Size(min = 5, max = 2000) String reason) {
    }

    /** refused by the desk of its stage, with the reason */
    @PostMapping("/amendments/{id}/refuse")
    @PreAuthorize(DESKS)
    @Transactional
    List<Map<String, Object>> refuse(@PathVariable UUID id, @Valid @RequestBody ReasonIn b) {
        Map<String, Object> a = amendment(id);
        String stage = String.valueOf(a.get("stage"));
        if (!List.of("APPLIED", "REFUSED", "WITHDRAWN").contains(stage)) ResultsService.requireStageDesk(stage, "Amendment " + a.get("ref"), "refused");
        jdbc.sql("SELECT assessment.refuse_amendment(:a, :r)").param("a", id).param("r", b.reason().trim()).query().singleRow();
        return of((UUID) a.get("sheet_id"));
    }

    /** withdrawn by the person who raised it */
    @PostMapping("/amendments/{id}/withdraw")
    @PreAuthorize(ENTRY)
    @Transactional
    List<Map<String, Object>> withdraw(@PathVariable UUID id, @Valid @RequestBody ReasonIn b) {
        Map<String, Object> a = amendment(id);
        jdbc.sql("SELECT assessment.withdraw_amendment(:a, :r)").param("a", id).param("r", b.reason().trim()).query().singleRow();
        return of((UUID) a.get("sheet_id"));
    }
}
