package ng.edu.moaum.portal.transfers;

import java.sql.Types;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

import ng.edu.moaum.portal.shared.AuditContextHolder;
import ng.edu.moaum.portal.shared.DomainRuleViolation;
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

/** Inter-departmental transfer (V070): the student's application and the office's queue. */
@RestController
class TransferController {

    private static final String READERS = "hasAnyAuthority('OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar','OFFICE_dvc','OFFICE_vc','OFFICE_ict','OFFICE_admin','OFFICE_super')";
    private static final String SAIC = "hasAnyAuthority('OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar','OFFICE_dvc','OFFICE_super')";
    private static final String SENATE = "hasAnyAuthority('OFFICE_registrar','OFFICE_dregistrar','OFFICE_vc','OFFICE_dvc','OFFICE_super')";
    private static final String OFFICERS = "hasAnyAuthority('OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar','OFFICE_super')";
    private static final String EFFECT = "hasAnyAuthority('OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar','OFFICE_ict','OFFICE_super')";

    private final JdbcClient jdbc;

    TransferController(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    public record Apply(@NotBlank @Size(max = 6) String toProgramme, @NotBlank @Size(max = 600) String reason, Integer utme) {
    }

    public record Record(@NotBlank @Size(max = 40) String number, @NotBlank @Size(max = 6) String toProgramme, @NotBlank @Size(max = 600) String reason, Integer utme) {
    }

    public record Review(boolean recommend, Integer level, @Size(max = 600) String note) {
    }

    public record Senate(boolean approve, @Size(max = 600) String note) {
    }

    public record Why(@NotBlank @Size(max = 600) String why) {
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

    private UUID studentByNumber(String number) {
        return jdbc.sql("SELECT id FROM people.student WHERE upper(matric_no) = upper(:n) OR upper(admission_no) = upper(:n) LIMIT 1")
                .param("n", number == null ? "" : number.trim()).query(UUID.class).optional()
                .orElseThrow(() -> new NotFound("student", number));
    }

    /* ── the student's side ── */

    @GetMapping("/api/v1/me/transfer")
    @PreAuthorize("hasAuthority('OFFICE_student')")
    @Transactional(readOnly = true)
    Map<String, Object> mine(Authentication auth) {
        UUID student = me(auth);
        Map<String, Object> me = jdbc.sql("""
                SELECT s.surname || ', ' || s.other_names AS name, s.matric_no, s.current_level, s.entry_mode, s.status,
                       p.name AS programme, p.code AS programme_code
                  FROM people.student s LEFT JOIN ref.programme p ON p.code = s.programme_code WHERE s.id = :s
                """).param("s", student).query().singleRow();
        List<Map<String, Object>> apps = jdbc.sql("""
                SELECT * FROM people.transfer_list(NULL, NULL) WHERE student_id = :s ORDER BY applied_at DESC
                """).param("s", student).query().listOfRows();
        List<Map<String, Object>> programmes = jdbc.sql("""
                SELECT p.code, p.name, f.name AS faculty FROM ref.programme p JOIN ref.faculty f ON f.code = p.faculty_code
                 WHERE NOT p.archived AND p.code <> (SELECT programme_code FROM people.student WHERE id = :s) ORDER BY f.name, p.name
                """).param("s", student).query().listOfRows();
        return Map.of("student", me, "applications", apps, "programmes", programmes, "fee", jdbc.sql("SELECT people.transfer_fee()").query(java.math.BigDecimal.class).single());
    }

    @PostMapping("/api/v1/me/transfer")
    @PreAuthorize("hasAuthority('OFFICE_student')")
    @Transactional
    Map<String, Object> apply(Authentication auth, @Valid @RequestBody Apply body) {
        UUID id = jdbc.sql("SELECT people.apply_transfer(:s, :p, :r, :u)")
                .param("s", me(auth)).param("p", body.toProgramme()).param("r", body.reason()).param("u", body.utme(), Types.INTEGER)
                .query(UUID.class).single();
        return Map.of("id", id, "state", "APPLIED");
    }

    @PostMapping("/api/v1/me/transfer/{id}/fee")
    @PreAuthorize("hasAuthority('OFFICE_student')")
    @Transactional
    Map<String, Object> myFee(Authentication auth, @PathVariable UUID id) {
        boolean mine = Boolean.TRUE.equals(jdbc.sql("SELECT EXISTS (SELECT 1 FROM people.transfer_application WHERE id = :id AND student_id = :s)")
                .param("id", id).param("s", me(auth)).query(Boolean.class).single());
        if (!mine) {
            throw new NotFound("transfer application", id.toString());
        }
        String ref = jdbc.sql("SELECT people.transfer_fee_reference(:id)").param("id", id).query(String.class).single();
        return Map.of("reference", ref);
    }

    /* ── the office's side ── */

    @GetMapping("/api/v1/transfers")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> list(@RequestParam(required = false) String session, @RequestParam(required = false) String state) {
        List<Map<String, Object>> rows = jdbc.sql("SELECT * FROM people.transfer_list(:s, :st)")
                .param("s", session == null || session.isBlank() ? null : session, Types.VARCHAR)
                .param("st", state == null || state.isBlank() ? null : state.toUpperCase(), Types.VARCHAR)
                .query().listOfRows();
        return Map.of("rows", rows);
    }

    @GetMapping("/api/v1/transfers/programmes")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> programmes() {
        return jdbc.sql("SELECT p.code, p.name, f.name AS faculty FROM ref.programme p JOIN ref.faculty f ON f.code = p.faculty_code WHERE NOT p.archived ORDER BY f.name, p.name").query().listOfRows();
    }

    @PostMapping("/api/v1/transfers")
    @PreAuthorize(OFFICERS)
    @Transactional
    Map<String, Object> record(@Valid @RequestBody Record body) {
        UUID student = studentByNumber(body.number());
        UUID id = jdbc.sql("SELECT people.apply_transfer(:s, :p, :r, :u)")
                .param("s", student).param("p", body.toProgramme()).param("r", body.reason()).param("u", body.utme(), Types.INTEGER)
                .query(UUID.class).single();
        return Map.of("id", id, "state", "APPLIED");
    }

    @PostMapping("/api/v1/transfers/{id}/review")
    @PreAuthorize(SAIC)
    @Transactional
    Map<String, Object> review(@PathVariable UUID id, @RequestBody Review body) {
        if (body.recommend() && (body.level() == null)) {
            throw new DomainRuleViolation("TR_LEVEL", "A recommendation names the level to admit into.", new DomainRuleViolation.Remedy("Choose the level.", "Academic Office"));
        }
        jdbc.sql("SELECT people.review_transfer(:id, :rec, :lvl, :note)")
                .param("id", id).param("rec", body.recommend()).param("lvl", body.level(), Types.INTEGER).param("note", body.note(), Types.VARCHAR)
                .query().singleRow();
        return Map.of("id", id, "state", body.recommend() ? "RECOMMENDED" : "NOT_RECOMMENDED");
    }

    @PostMapping("/api/v1/transfers/{id}/senate")
    @PreAuthorize(SENATE)
    @Transactional
    Map<String, Object> senate(@PathVariable UUID id, @RequestBody Senate body) {
        jdbc.sql("SELECT people.senate_transfer(:id, :ap, :note)")
                .param("id", id).param("ap", body.approve()).param("note", body.note(), Types.VARCHAR)
                .query().singleRow();
        return Map.of("id", id, "state", body.approve() ? "APPROVED" : "DECLINED");
    }

    @PostMapping("/api/v1/transfers/{id}/withdraw")
    @PreAuthorize(OFFICERS)
    @Transactional
    Map<String, Object> withdraw(@PathVariable UUID id, @Valid @RequestBody Why body) {
        jdbc.sql("SELECT people.withdraw_transfer(:id, :w)").param("id", id).param("w", body.why()).query().singleRow();
        return Map.of("id", id, "state", "WITHDRAWN");
    }

    @PostMapping("/api/v1/transfers/{id}/effect")
    @PreAuthorize(EFFECT)
    @Transactional
    Map<String, Object> effect(@PathVariable UUID id) {
        jdbc.sql("SELECT people.effect_transfer(:id)").param("id", id).query().singleRow();
        return Map.of("id", id, "state", "EFFECTED");
    }
}
