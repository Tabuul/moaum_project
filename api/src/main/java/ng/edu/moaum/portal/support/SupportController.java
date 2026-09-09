package ng.edu.moaum.portal.support;

import java.sql.Types;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

import ng.edu.moaum.portal.shared.AuditContextHolder;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.Authentication;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/** The student's requests under /api/v1/me/requests; the office's desk under /api/v1/support/requests. */
@RestController
class SupportController {

    private static final String OFFICES = "hasAnyAuthority('OFFICE_registrar','OFFICE_dregistrar','OFFICE_bursar','OFFICE_ict','OFFICE_library','OFFICE_services','OFFICE_academic','OFFICE_hod','OFFICE_housing','OFFICE_admin','OFFICE_super')";
    private static final String REQUEST = """
            SELECT r.id, r.ref, r.office_code, o.label AS office, r.subject, r.detail, r.raised_at, r.state, r.answer, r.answered_at,
                   st.surname || ', ' || st.other_names AS student, coalesce(st.matric_no, st.admission_no) AS number,
                   CASE WHEN p.id IS NULL THEN NULL ELSE p.surname || ', ' || p.given_names END AS answered_by_name
              FROM platform.service_request r
              JOIN ref.office o ON o.code = r.office_code
              JOIN people.student st ON st.id = r.student_id
              LEFT JOIN iam.person p ON p.id = r.answered_by
            """;

    public record Raise(@NotBlank @Size(max = 20) String office, @NotBlank @Size(max = 200) String subject, @Size(max = 4000) String detail) {
    }

    public record Answer(@NotBlank @Size(max = 4000) String answer, Boolean resolved) {
    }

    private final JdbcClient jdbc;

    SupportController(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    private static UUID student(Authentication auth) {
        return UUID.fromString(auth.getName());
    }

    @GetMapping("/api/v1/me/requests")
    @PreAuthorize("hasAuthority('OFFICE_student')")
    @Transactional(readOnly = true)
    List<Map<String, Object>> mine(Authentication auth) {
        return jdbc.sql(REQUEST + " WHERE r.student_id = :s ORDER BY r.raised_at DESC LIMIT 50").param("s", student(auth)).query().listOfRows();
    }

    @PostMapping("/api/v1/me/requests")
    @PreAuthorize("hasAuthority('OFFICE_student')")
    @Transactional
    Map<String, Object> raise(Authentication auth, @Valid @RequestBody Raise body) {
        String ref = jdbc.sql("SELECT platform.raise_request(:s, :o, :j, :d)").param("s", student(auth)).param("o", body.office().trim().toLowerCase())
                .param("j", body.subject()).param("d", body.detail(), Types.VARCHAR).query(String.class).single();
        return Map.of("ref", ref, "state", "OPEN");
    }

    /** the office's queue: its own requests, the oldest open first — or every office's for the platform */
    @GetMapping("/api/v1/support/requests")
    @PreAuthorize(OFFICES)
    @Transactional(readOnly = true)
    List<Map<String, Object>> desk(@RequestParam(required = false) String state) {
        String office = AuditContextHolder.required().actorOffice();
        boolean all = List.of("admin", "super", "ict").contains(office);
        return jdbc.sql(REQUEST + """
                 WHERE (:all OR r.office_code = :o)
                   AND (:state::text IS NULL OR r.state = :state)
                 ORDER BY (r.state IN ('OPEN','WITH_OFFICE')) DESC, r.raised_at LIMIT 300
                """).param("all", all).param("o", office).param("state", state == null || state.isBlank() ? null : state.toUpperCase(), Types.VARCHAR)
                .query().listOfRows();
    }

    @PostMapping("/api/v1/support/requests/{id}/answer")
    @PreAuthorize(OFFICES)
    @Transactional
    Map<String, Object> answer(@PathVariable UUID id, @Valid @RequestBody Answer body) {
        jdbc.sql("SELECT platform.answer_request(:id, :a, :r)").param("id", id).param("a", body.answer()).param("r", body.resolved() == null || body.resolved()).query().singleRow();
        return Map.of("id", id, "state", body.resolved() == null || body.resolved() ? "RESOLVED" : "WITH_OFFICE");
    }
}
