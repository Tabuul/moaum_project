package ng.edu.moaum.portal.hrm;

import java.time.LocalDate;
import java.sql.Types;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

import ng.edu.moaum.portal.shared.AuditContextHolder;
import ng.edu.moaum.portal.shared.NotFound;

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

/** Staff leave (V071): a member of staff's own requests, and the office's approval queue. */
@RestController
class LeaveController {

    private static final String APPROVERS = "hasAnyAuthority('OFFICE_hrm','OFFICE_hod','OFFICE_dean','OFFICE_dregistrar','OFFICE_registrar','OFFICE_audit','OFFICE_admin','OFFICE_super')";

    private final JdbcClient jdbc;

    LeaveController(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    public record Request(@NotBlank @Size(max = 20) String type, @NotNull LocalDate from, @NotNull LocalDate to, @Size(max = 200) String cover, @Size(max = 600) String note) {
    }

    public record Decide(boolean approve, @Size(max = 600) String note) {
    }

    private static UUID me(Authentication auth) {
        return AuditContextHolder.current().map(c -> c.actorId()).orElseGet(() -> {
            if (auth == null || auth.getName() == null) {
                return null;
            }
            try {
                return UUID.fromString(auth.getName());
            } catch (IllegalArgumentException notUuid) {
                return null;
            }
        });
    }

    /* ── the member of staff ── */

    @GetMapping("/api/v1/me/leave")
    @PreAuthorize("isAuthenticated()")
    @Transactional(readOnly = true)
    Map<String, Object> mine(Authentication auth) {
        UUID p = me(auth);
        List<Map<String, Object>> rows = jdbc.sql("SELECT * FROM hrm.leave_list(NULL) WHERE person_id = :p ORDER BY requested_at DESC").param("p", p).query().listOfRows();
        List<Map<String, Object>> types = jdbc.sql("SELECT code, name, max_days, paid FROM hrm.leave_type ORDER BY (code = 'ANNUAL') DESC, name").query().listOfRows();
        boolean isStaff = Boolean.TRUE.equals(jdbc.sql("SELECT EXISTS (SELECT 1 FROM hrm.employment WHERE person_id = :p AND status = 'ACTIVE')").param("p", p).query(Boolean.class).single());
        Integer balance = isStaff ? jdbc.sql("SELECT hrm.leave_balance(:p)").param("p", p).query(Integer.class).single() : null;
        return Map.of("requests", rows, "types", types, "balance", balance == null ? "" : balance, "isStaff", isStaff);
    }

    @PostMapping("/api/v1/me/leave")
    @PreAuthorize("isAuthenticated()")
    @Transactional
    Map<String, Object> request(Authentication auth, @Valid @RequestBody Request body) {
        UUID id = jdbc.sql("SELECT hrm.request_leave(:p, :t, :f, :to, :c, :n)")
                .param("p", me(auth)).param("t", body.type()).param("f", body.from()).param("to", body.to())
                .param("c", body.cover(), Types.VARCHAR).param("n", body.note(), Types.VARCHAR)
                .query(UUID.class).single();
        return Map.of("id", id, "state", "REQUESTED");
    }

    @PostMapping("/api/v1/me/leave/{id}/cancel")
    @PreAuthorize("isAuthenticated()")
    @Transactional
    Map<String, Object> cancel(Authentication auth, @PathVariable UUID id) {
        boolean mine = Boolean.TRUE.equals(jdbc.sql("SELECT EXISTS (SELECT 1 FROM hrm.leave_request WHERE id = :id AND person_id = :p)")
                .param("id", id).param("p", me(auth)).query(Boolean.class).single());
        if (!mine) {
            throw new NotFound("leave request", id.toString());
        }
        jdbc.sql("SELECT hrm.cancel_leave(:id)").param("id", id).query().singleRow();
        return Map.of("id", id, "state", "CANCELLED");
    }

    /* ── the office ── */

    @GetMapping("/api/v1/hr/leave")
    @PreAuthorize(APPROVERS)
    @Transactional(readOnly = true)
    Map<String, Object> list(@RequestParam(required = false) String state) {
        List<Map<String, Object>> rows = jdbc.sql("SELECT * FROM hrm.leave_list(:st)")
                .param("st", state == null || state.isBlank() ? null : state.toUpperCase(), Types.VARCHAR).query().listOfRows();
        return Map.of("rows", rows);
    }

    @PostMapping("/api/v1/hr/leave/{id}/decide")
    @PreAuthorize(APPROVERS)
    @Transactional
    Map<String, Object> decide(@PathVariable UUID id, @RequestBody Decide body) {
        jdbc.sql("SELECT hrm.decide_leave(:id, :ap, :n)").param("id", id).param("ap", body.approve()).param("n", body.note(), Types.VARCHAR).query().singleRow();
        return Map.of("id", id, "state", body.approve() ? "APPROVED" : "DECLINED");
    }
}
