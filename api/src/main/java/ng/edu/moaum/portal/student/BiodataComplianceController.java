package ng.edu.moaum.portal.student;

import java.time.OffsetDateTime;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.UUID;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

import ng.edu.moaum.portal.shared.AuditContext;
import ng.edu.moaum.portal.shared.AuditContextHolder;
import ng.edu.moaum.portal.shared.DomainRuleViolation;
import ng.edu.moaum.portal.shared.OfficeScope;

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

/**
 * V423 — Biodata compliance, under Portal Management: the ICT Director's switch for mandatory student biodata
 * completion, the items it requires, the exceptions, and the figures and lists that show who is complete. The switch,
 * the requirements and the exceptions are the ICT Director's and an administrator's alone (the database refuses any
 * other office as well); the Registry, the Academic Office and Records read the figures, a Dean or a Head of Department
 * only within their own faculty or department, held on the server (OfficeScope).
 */
@RestController
@RequestMapping("/api/v1/biodata-compliance")
class BiodataComplianceController {

    static final String SETTERS = "hasAnyAuthority('OFFICE_ict','OFFICE_admin','OFFICE_super')";
    static final String READERS = "hasAnyAuthority('OFFICE_ict','OFFICE_admin','OFFICE_super','OFFICE_registrar','OFFICE_dregistrar',"
            + "'OFFICE_academic','OFFICE_records','OFFICE_dean','OFFICE_hod')";

    public record GateIn(@NotNull Boolean enabled, @Size(max = 500) String reason) {
    }

    public record RequirementIn(@NotNull Boolean required) {
    }

    public record ExceptionIn(UUID student, @Size(max = 60) String number, @NotBlank @Size(max = 1000) String reason,
                              OffsetDateTime startsAt, @NotNull OffsetDateTime expiresAt) {
    }

    public record RevokeIn(@Size(max = 1000) String reason) {
    }

    private final BiodataCompliance compliance;
    private final OfficeScope scope;
    private final JdbcClient jdbc;

    BiodataComplianceController(BiodataCompliance compliance, OfficeScope scope, JdbcClient jdbc) {
        this.compliance = compliance;
        this.scope = scope;
        this.jdbc = jdbc;
    }

    private static String blank(String s) {
        return s == null || s.isBlank() ? null : s.trim();
    }

    private BiodataCompliance.Filter filter(String fac, String dept, String prog, Integer level, String session, String sex,
                                            String status, String missing, String q, int page, int size) {
        OfficeScope.Bound b = scope.bound(fac, dept, prog);
        String st = blank(status) == null ? null : status.trim().toUpperCase();
        if (st != null && !st.equals("COMPLETE") && !st.equals("INCOMPLETE")) {
            st = null;
        }
        String sx = blank(sex) == null ? null : sex.trim().toUpperCase();
        return new BiodataCompliance.Filter(b.fac(), b.dept(), b.prog(), level, blank(session), sx, st, blank(missing), blank(q),
                Math.max(page, 0), Math.min(Math.max(size, 1), 5000));
    }

    /** the switch, the figures within the office's bound (and the filter), the required items, the exceptions and the history */
    @GetMapping
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> overview(@RequestParam(required = false) String fac, @RequestParam(required = false) String dept,
                                 @RequestParam(required = false) String prog, @RequestParam(required = false) Integer level,
                                 @RequestParam(required = false) String session, @RequestParam(required = false) String sex) {
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("gate", compliance.gate());
        out.put("summary", compliance.summary(filter(fac, dept, prog, level, session, sex, null, null, null, 0, 1)));
        out.put("requirements", compliance.requirements());
        String office = AuditContextHolder.current().map(AuditContext::actorOffice).orElse("");
        boolean setter = office.equals("ict") || office.equals("admin") || office.equals("super");
        out.put("canSet", setter);
        out.put("today", java.time.LocalDate.now(java.time.ZoneId.of("Africa/Lagos")).toString());
        if (setter) {
            out.put("exceptions", compliance.exceptions());
            out.put("history", compliance.history());
        }
        return out;
    }

    /** every item that can be required, and whether it is */
    @GetMapping("/requirements")
    @PreAuthorize(READERS)
    Object requirements() {
        return compliance.requirements();
    }

    /** V427: what requiring each item would do — who lacks it, whom it would hold, whom it alone holds — before it is ticked */
    @GetMapping("/requirements/impact")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Object impact() {
        return compliance.impact();
    }

    /** the students within the bound and the filter, paged (up to 5,000 rows for an export), searched on the server */
    @GetMapping("/students")
    @PreAuthorize(READERS)
    @Transactional
    Map<String, Object> students(@RequestParam(required = false) String fac, @RequestParam(required = false) String dept,
                                 @RequestParam(required = false) String prog, @RequestParam(required = false) Integer level,
                                 @RequestParam(required = false) String session, @RequestParam(required = false) String sex,
                                 @RequestParam(required = false) String status, @RequestParam(required = false) String missing,
                                 @RequestParam(required = false) String q, @RequestParam(defaultValue = "0") int page,
                                 @RequestParam(defaultValue = "50") int size) {
        return compliance.list(filter(fac, dept, prog, level, session, sex, status, missing, q, page, size));
    }

    /** the switch turned ON or OFF — the ICT Director's or an administrator's, on the audit spine with who, the office and why */
    @PutMapping("/gate")
    @PreAuthorize(SETTERS)
    @Transactional
    Map<String, Object> gate(@Valid @RequestBody GateIn body) {
        AuditContext ctx = AuditContextHolder.required();
        jdbc.sql("SELECT people.set_biodata_gate(:on, :r, :a, :o)").param("on", body.enabled()).param("r", blank(body.reason()), java.sql.Types.VARCHAR)
                .param("a", ctx.actorId()).param("o", ctx.actorOffice()).query(Boolean.class).single();
        return compliance.gate();
    }

    /** an item required or not; a JAMB field or a health field is refused by the database */
    @PutMapping("/requirements/{item}")
    @PreAuthorize(SETTERS)
    @Transactional
    Object requirement(@PathVariable String item, @Valid @RequestBody RequirementIn body) {
        AuditContext ctx = AuditContextHolder.required();
        jdbc.sql("SELECT people.set_biodata_requirement(:i, :r, :a, :o)").param("i", item).param("r", body.required())
                .param("a", ctx.actorId()).param("o", ctx.actorOffice()).query().listOfRows();
        return compliance.requirements();
    }

    /** a named student let past the gate for a stated reason until a date (30 days at most) */
    @PostMapping("/exceptions")
    @PreAuthorize(SETTERS)
    @Transactional
    Map<String, Object> grant(@Valid @RequestBody ExceptionIn body) {
        AuditContext ctx = AuditContextHolder.required();
        UUID student = body.student();
        if (student == null) {
            String n = blank(body.number());
            if (n == null) {
                throw new DomainRuleViolation("BIO_GATE_STUDENT", "Name the student: their matriculation, JAMB or admission number.",
                        new DomainRuleViolation.Remedy("Type the student's number.", "You"));
            }
            student = jdbc.sql("""
                    SELECT id FROM people.student
                     WHERE upper(matric_no) = upper(:n) OR upper(btrim(jamb_reg_no)) = upper(:n) OR upper(admission_no) = upper(:n)
                     LIMIT 1
                    """).param("n", n).query(UUID.class).optional()
                    .orElseThrow(() -> new DomainRuleViolation("BIO_GATE_STUDENT", "No student on the register has that number.",
                            new DomainRuleViolation.Remedy("Check the number and try again.", "You")));
        }
        UUID id = jdbc.sql("SELECT people.grant_biodata_exception(:s, :r, :from::timestamptz, :to::timestamptz, :a, :o)")
                .param("s", student).param("r", body.reason().trim())
                .param("from", body.startsAt(), java.sql.Types.TIMESTAMP_WITH_TIMEZONE).param("to", body.expiresAt(), java.sql.Types.TIMESTAMP_WITH_TIMEZONE)
                .param("a", ctx.actorId()).param("o", ctx.actorOffice()).query(UUID.class).single();
        return Map.of("id", id, "student", student);
    }

    @PostMapping("/exceptions/{id}/revoke")
    @PreAuthorize(SETTERS)
    @Transactional
    Map<String, Object> revoke(@PathVariable UUID id, @Valid @RequestBody RevokeIn body) {
        AuditContext ctx = AuditContextHolder.required();
        jdbc.sql("SELECT people.revoke_biodata_exception(:id, :r, :a, :o)").param("id", id).param("r", blank(body.reason()), java.sql.Types.VARCHAR)
                .param("a", ctx.actorId()).param("o", ctx.actorOffice()).query().listOfRows();
        return Map.of("id", id, "revoked", true);
    }
}
