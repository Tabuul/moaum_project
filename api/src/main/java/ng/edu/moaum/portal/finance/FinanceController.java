package ng.edu.moaum.portal.finance;

import java.math.BigDecimal;
import java.sql.Types;
import java.time.LocalDate;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import jakarta.validation.Valid;
import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

import ng.edu.moaum.portal.shared.DomainRuleViolation;

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

/** The Bursary's desk: the schedule, the scheme, the references waiting, the confirmations. */
@RestController
@RequestMapping("/api/v1/finance")
class FinanceController {

    private static final String READERS = "hasAnyAuthority('OFFICE_bursar','OFFICE_registrar','OFFICE_dregistrar','OFFICE_academic','OFFICE_audit','OFFICE_ict','OFFICE_admin','OFFICE_super','OFFICE_vc','OFFICE_dvc')";
    private static final String BURSARY = "hasAnyAuthority('OFFICE_bursar','OFFICE_super')";

    public record Item(@NotBlank @Size(max = 120) String item, @NotNull @DecimalMin("0") BigDecimal amount, Integer level,
                       @Size(max = 20) String entryMode, @Size(max = 12) String facultyCode, @Size(max = 12) String programmeCode, Integer ord) {
    }

    public record Scheme(@NotBlank @Size(max = 200) String instrument, LocalDate from) {
    }

    public record Confirmation(@NotBlank @Size(max = 60) String channel, @Size(max = 400) String note) {
    }

    private final JdbcClient jdbc;

    FinanceController(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    /* ── the schedule ── */

    @GetMapping("/sessions/{session}/{year}/schedule")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> schedule(@PathVariable String session, @PathVariable String year) {
        String s = session + "/" + year;
        List<Map<String, Object>> items = jdbc.sql("""
                SELECT f.id, f.item, f.amount, f.level, f.entry_mode, f.faculty_code, fa.name AS faculty_name, f.programme_code, p.name AS programme_name, f.ord
                  FROM finance.fee_schedule f LEFT JOIN ref.faculty fa ON fa.code = f.faculty_code LEFT JOIN ref.programme p ON p.code = f.programme_code
                 WHERE f.session = :s AND f.ended_at IS NULL ORDER BY f.ord, f.item
                """).param("s", s).query().listOfRows();
        Map<String, Object> scheme = jdbc.sql("""
                SELECT v.id, v.instrument, lower(v.validity) AS from_date, upper(v.validity) AS until_date, v.decided_by,
                       (SELECT json_object_agg(r.purpose, r.releases_at)::text FROM policy.clearance_rule r WHERE r.version_id = v.id) AS rules
                  FROM policy.version v WHERE v.kind = 'clearance' AND v.scope = 'UNIVERSITY' AND v.validity @> current_date
                """).query().listOfRows().stream().findFirst().orElse(null);
        Map<String, Object> position = jdbc.sql("""
                SELECT count(DISTINCT r.student_id) AS students_paying, coalesce(sum(r.amount) FILTER (WHERE r.confirmed_at IS NOT NULL), 0) AS confirmed,
                       count(*) FILTER (WHERE r.confirmed_at IS NULL AND r.expires_at > now()) AS references_open
                  FROM finance.payment_reference r WHERE r.session = :s
                """).param("s", s).query().singleRow();
        return Map.of("session", s, "items", items, "scheme", scheme == null ? Map.of() : scheme, "schemeInForce", scheme != null, "position", position);
    }

    @PostMapping("/sessions/{session}/{year}/schedule")
    @PreAuthorize(BURSARY)
    @Transactional
    Map<String, Object> addItem(@PathVariable String session, @PathVariable String year, @Valid @RequestBody Item body) {
        String s = session + "/" + year;
        if (body.level() != null && !List.of(100, 200, 300, 400, 500, 600).contains(body.level())) {
            throw new DomainRuleViolation("FEE_LEVEL", "A level is 100 to 600.", new DomainRuleViolation.Remedy("Leave it blank for every level.", "Bursary"));
        }
        jdbc.sql("""
                INSERT INTO finance.fee_schedule (session, item, amount, level, entry_mode, faculty_code, programme_code, ord)
                VALUES (:s, :i, :a, :l, :m, :f, :p, :o)
                """).param("s", s).param("i", body.item().trim()).param("a", body.amount()).param("l", body.level(), Types.INTEGER)
                .param("m", blank(body.entryMode()), Types.VARCHAR).param("f", blank(body.facultyCode()), Types.VARCHAR)
                .param("p", blank(body.programmeCode()), Types.VARCHAR).param("o", body.ord() == null ? 0 : body.ord()).update();
        return schedule(session, year);
    }

    @PostMapping("/sessions/{session}/{year}/schedule/{id}/end")
    @PreAuthorize(BURSARY)
    @Transactional
    Map<String, Object> endItem(@PathVariable String session, @PathVariable String year, @PathVariable UUID id) {
        jdbc.sql("UPDATE finance.fee_schedule SET ended_at = now() WHERE id = :id AND session = :s AND ended_at IS NULL")
                .param("id", id).param("s", session + "/" + year).update();
        return schedule(session, year);
    }

    /* ── the scheme ── */

    @PostMapping("/clearance-scheme")
    @PreAuthorize(BURSARY)
    @Transactional
    Map<String, Object> scheme(@Valid @RequestBody Scheme body) {
        UUID id = jdbc.sql("SELECT finance.put_scheme_in_force(:i, :d)").param("i", body.instrument())
                .param("d", body.from() == null ? LocalDate.now() : body.from()).query(UUID.class).single();
        return Map.of("versionId", id, "inForceFrom", body.from() == null ? LocalDate.now() : body.from());
    }

    /* ── the references ── */

    @GetMapping("/references")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> references(@RequestParam(required = false) String session, @RequestParam(defaultValue = "open") String state) {
        return jdbc.sql("""
                SELECT r.id, r.reference, r.session, r.purpose, r.amount, r.generated_at, r.expires_at, r.confirmed_at, r.channel, r.note, r.receipt_no,
                       s.matric_no, s.admission_no, s.surname, s.other_names, p.name AS programme, s.current_level
                  FROM finance.payment_reference r JOIN people.student s ON s.id = r.student_id JOIN ref.programme p ON p.code = s.programme_code
                 WHERE (:s::text IS NULL OR r.session = :s)
                   AND CASE :st WHEN 'open' THEN r.confirmed_at IS NULL AND r.expires_at > now() WHEN 'confirmed' THEN r.confirmed_at IS NOT NULL ELSE true END
                 ORDER BY r.generated_at DESC LIMIT 500
                """).param("s", session, Types.VARCHAR).param("st", state).query().listOfRows();
    }

    @PostMapping("/references/{reference}/confirm")
    @PreAuthorize("hasAnyAuthority('OFFICE_bursar','OFFICE_super')")
    @Transactional
    Map<String, Object> confirm(@PathVariable String reference, @Valid @RequestBody Confirmation body) {
        String outcome = jdbc.sql("SELECT finance.confirm_payment(:r, :c, :n)").param("r", reference).param("c", body.channel())
                .param("n", body.note(), Types.VARCHAR).query(String.class).single();
        return Map.of("reference", reference, "outcome", outcome);
    }

    private static String blank(String s) {
        return s == null || s.isBlank() ? null : s.trim().toUpperCase();
    }
}
