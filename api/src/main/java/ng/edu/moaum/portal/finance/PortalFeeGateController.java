package ng.edu.moaum.portal.finance;

import java.sql.Types;
import java.time.OffsetDateTime;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

import ng.edu.moaum.portal.shared.AuditContext;
import ng.edu.moaum.portal.shared.AuditContextHolder;
import ng.edu.moaum.portal.shared.DomainRuleViolation;
import ng.edu.moaum.portal.shared.NotFound;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * V724 — the student portal's fee gate (finance.portal_fee_gate, one row): whether a fresh UTME or Direct Entry admit is held
 * out of the student portal until the session's school fees are paid, from which entry session on, and what clears it — the
 * first semester's fees (as the University chose on 11 November 2026) or the session's in full. ON from deployment; the Bursar,
 * the Director of ICT or an administrator turns or re-rules it, with a reason, and every change is on the audit spine. The
 * Bursary (the Bursar or the Students Account Officer) lets a named student through for a stated time — on an approved
 * instalment arrangement, a waiver or its own decision — and revokes it; an exception is one at a time and at most 200 days.
 * The database decides every refusal (PORTAL_FEE_GATE_OFFICE, _RULE, _SESSION, _UNCHANGED, _BASIS, _REASON, _SPAN,
 * _EXCEPTION_ACTIVE, _EXCEPTION_ENDED), surfacing as 422 with its code. Nothing of the register, matriculation or the admission
 * number is touched here: the gate only reads them.
 */
@RestController
@RequestMapping("/api/v1/finance/portal-gate")
class PortalFeeGateController {

    /** who reads the gate and its exceptions: the Bursary, the Students Account Officer, the Directorate of ICT, the administrators */
    static final String READERS = "hasAnyAuthority('OFFICE_bursar','OFFICE_studentaccounts','OFFICE_ict','OFFICE_admin','OFFICE_super')";
    /** who turns or re-rules the gate (finance.set_portal_fee_gate refuses every other office) */
    static final String SETTERS = "hasAnyAuthority('OFFICE_bursar','OFFICE_ict','OFFICE_admin','OFFICE_super')";
    /** who lets a student through, and revokes it (finance.grant_portal_fee_exception refuses every other office) */
    static final String EXCEPTORS = "hasAnyAuthority('OFFICE_bursar','OFFICE_studentaccounts','OFFICE_admin','OFFICE_super')";

    /** a change of the gate: a field left null keeps its value; the reason is kept with the change */
    public record GateIn(Boolean enabled, @Pattern(regexp = "\\d{4}/\\d{4}") String fromSession,
                         @Pattern(regexp = "FIRST_SEMESTER|PAID_IN_FULL") String clearsOn, @NotBlank @Size(max = 400) String reason) {
    }

    /** an exception: the student by admission number (a fresh admit has no matriculation number yet) or by id; from when (now when
     *  null) until when, on which basis, and why */
    public record ExceptionIn(@Size(max = 40) String admissionNo, UUID studentId,
                              @NotBlank @Pattern(regexp = "INSTALMENT_POLICY|WAIVER|BURSARY_DECISION") String basis,
                              @NotBlank @Size(max = 2000) String reason, OffsetDateTime startsAt, @NotNull OffsetDateTime expiresAt) {
    }

    private static final String EXCEPTIONS = """
            SELECT e.id, e.student_id, s.admission_no, s.matric_no, s.surname || ', ' || s.other_names AS name, e.basis, e.reason,
                   e.starts_at, e.expires_at, e.granted_office, e.granted_at
              FROM finance.portal_fee_gate_exception e
              JOIN people.student s ON s.id = e.student_id
             WHERE e.revoked_at IS NULL AND e.expires_at > now()
            """;

    private final JdbcClient jdbc;

    PortalFeeGateController(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    /** the gate as it stands, the sessions it may start from, and the exceptions that stand */
    @GetMapping
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> read() {
        return view();
    }

    /** turn the gate, move its first session or change what clears it; refused unchanged (PORTAL_FEE_GATE_UNCHANGED) */
    @PutMapping
    @PreAuthorize(SETTERS)
    @Transactional
    Map<String, Object> set(@Valid @RequestBody GateIn body) {
        AuditContext who = AuditContextHolder.required();
        jdbc.sql("SELECT finance.set_portal_fee_gate(:e, :from, :on, :r, :actor, :office)")
                .param("e", body.enabled(), Types.BOOLEAN).param("from", body.fromSession(), Types.VARCHAR).param("on", body.clearsOn(), Types.VARCHAR)
                .param("r", body.reason(), Types.VARCHAR).param("actor", who.actorId(), Types.OTHER).param("office", who.actorOffice(), Types.VARCHAR)
                .query().singleRow();
        return view();
    }

    /** let a named student through the gate for a stated time */
    @PostMapping("/exceptions")
    @PreAuthorize(EXCEPTORS)
    @Transactional
    Map<String, Object> grant(@Valid @RequestBody ExceptionIn body) {
        UUID student = student(body.studentId(), body.admissionNo());
        AuditContext who = AuditContextHolder.required();
        UUID id = jdbc.sql("SELECT finance.grant_portal_fee_exception(:s, :b, :r, :from, :until, :actor, :office)")
                .param("s", student, Types.OTHER).param("b", body.basis()).param("r", body.reason())
                .param("from", body.startsAt(), Types.TIMESTAMP_WITH_TIMEZONE).param("until", body.expiresAt(), Types.TIMESTAMP_WITH_TIMEZONE)
                .param("actor", who.actorId(), Types.OTHER).param("office", who.actorOffice(), Types.VARCHAR)
                .query(UUID.class).single();
        return jdbc.sql(EXCEPTIONS + " AND e.id = :id").param("id", id, Types.OTHER).query().listOfRows().stream().findFirst()
                .map(PortalFeeGateController::exception).orElseThrow(() -> new NotFound("portal fee gate exception", id));
    }

    /** revoke an exception that stands: the gate applies again on the student's next request */
    @DeleteMapping("/exceptions/{id}")
    @PreAuthorize(EXCEPTORS)
    @Transactional
    Map<String, Object> revoke(@PathVariable UUID id, @RequestParam(required = false) String reason) {
        AuditContext who = AuditContextHolder.required();
        jdbc.sql("SELECT finance.revoke_portal_fee_exception(:id, :r, :actor, :office)")
                .param("id", id, Types.OTHER).param("r", reason == null ? null : reason.trim(), Types.VARCHAR)
                .param("actor", who.actorId(), Types.OTHER).param("office", who.actorOffice(), Types.VARCHAR)
                .query().singleRow();
        return Map.of("id", id, "revoked", true);
    }

    private Map<String, Object> view() {
        Map<String, Object> g = jdbc.sql("SELECT enabled, from_session, clears_on, changed_at, changed_office, reason FROM finance.portal_fee_gate WHERE id = 1")
                .query().singleRow();
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("enabled", g.get("enabled"));
        out.put("fromSession", g.get("from_session"));
        out.put("clearsOn", g.get("clears_on"));
        out.put("changedAt", g.get("changed_at"));
        out.put("changedOffice", g.get("changed_office"));
        out.put("reason", g.get("reason"));
        out.put("sessions", jdbc.sql("SELECT name FROM policy.academic_session ORDER BY name DESC").query(String.class).list());
        out.put("exceptions", jdbc.sql(EXCEPTIONS + " ORDER BY e.granted_at DESC").query().listOfRows().stream().map(PortalFeeGateController::exception).toList());
        return out;
    }

    private static Map<String, Object> exception(Map<String, Object> r) {
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("id", r.get("id"));
        m.put("studentId", r.get("student_id"));
        m.put("admissionNo", r.get("admission_no"));
        m.put("matricNo", r.get("matric_no"));
        m.put("name", r.get("name"));
        m.put("basis", r.get("basis"));
        m.put("reason", r.get("reason"));
        m.put("startsAt", r.get("starts_at"));
        m.put("expiresAt", r.get("expires_at"));
        m.put("grantedOffice", r.get("granted_office"));
        m.put("grantedAt", r.get("granted_at"));
        return m;
    }

    /** the student named: by id, or by the admission number; a record the Registry ended as a duplicate opens nothing, and a number
     *  two live records carry is refused by name, never guessed */
    private UUID student(UUID id, String admissionNo) {
        if (id != null) {
            return jdbc.sql("SELECT id FROM people.student WHERE id = :id AND duplicate_of IS NULL").param("id", id).query(UUID.class).optional()
                    .orElseThrow(() -> new NotFound("student", id));
        }
        String no = admissionNo == null ? "" : admissionNo.trim();
        if (no.isEmpty()) {
            throw new DomainRuleViolation("PORTAL_FEE_GATE_STUDENT", "Name the student the exception is for.",
                    new DomainRuleViolation.Remedy("Give the student's admission number.", "You"));
        }
        List<UUID> found = jdbc.sql("SELECT id FROM people.student WHERE duplicate_of IS NULL AND upper(admission_no) = upper(:n)")
                .param("n", no).query(UUID.class).list();
        if (found.size() > 1) {
            throw new DomainRuleViolation("STUDENT_NUMBER_SHARED", "Two records on the register carry this admission number.",
                    new DomainRuleViolation.Remedy("Name the student by id from the student record; the Registry is settling the two records.", "Registry"));
        }
        if (found.isEmpty()) {
            throw new NotFound("student", no);
        }
        return found.get(0);
    }
}
