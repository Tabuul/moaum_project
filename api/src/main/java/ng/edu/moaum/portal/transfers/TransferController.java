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

    private static final String READERS = "hasAnyAuthority('OFFICE_hod','OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar','OFFICE_dvc','OFFICE_vc','OFFICE_ict','OFFICE_admin','OFFICE_super')";
    private static final String SAIC = "hasAnyAuthority('OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar','OFFICE_dvc','OFFICE_super')";
    private static final String SENATE = "hasAnyAuthority('OFFICE_registrar','OFFICE_dregistrar','OFFICE_vc','OFFICE_dvc','OFFICE_super')";
    private static final String OFFICERS = "hasAnyAuthority('OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar','OFFICE_super')";
    private static final String EFFECT = "hasAnyAuthority('OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar','OFFICE_ict','OFFICE_super')";
    /** the offices in the approval chain: the department HODs, the Registrar and the Academic office */
    private static final String APPROVERS = "hasAnyAuthority('OFFICE_hod','OFFICE_registrar','OFFICE_dregistrar','OFFICE_academic','OFFICE_super')";

    private final JdbcClient jdbc;
    private final ng.edu.moaum.portal.shared.OfficeScope scope;

    TransferController(JdbcClient jdbc, ng.edu.moaum.portal.shared.OfficeScope scope) {
        this.jdbc = jdbc;
        this.scope = scope;
    }

    private static String actingOffice() {
        return AuditContextHolder.current().map(c -> c.actorOffice()).orElse(null);
    }

    /** the human-readable stage: which desk the application is sitting with (or its terminal state).
     *  While it is APPLIED it is with the current department once paid, or awaiting the student's payment. */
    private static String stageLabel(String state, boolean paid) {
        return switch (state == null ? "" : state) {
            case "APPLIED" -> paid ? "With current department" : "Awaiting payment";
            case "FROM_OK" -> "With new department";
            case "TO_OK" -> "With Registrar";
            case "REG_OK" -> "With Academic office";
            case "APPROVED" -> "Approved — awaiting fee";
            case "EFFECTED" -> "Completed";
            case "DECLINED" -> "Declined";
            case "WITHDRAWN" -> "Withdrawn";
            case "RECOMMENDED" -> "Recommended";
            case "NOT_RECOMMENDED" -> "Not recommended";
            default -> state;
        };
    }

    /** whether the acting office (and department, for an HOD) may approve an application at this stage.
     *  The current department cannot approve until the fee is paid (pay-first). */
    private static boolean mayApprove(String office, String myDept, String state, String fromDept, String toDept, boolean paid) {
        boolean isSuper = "super".equals(office);
        return switch (state == null ? "" : state) {
            case "APPLIED" -> paid && (isSuper || ("hod".equals(office) && fromDept != null && fromDept.equalsIgnoreCase(myDept)));
            case "FROM_OK" -> isSuper || ("hod".equals(office) && toDept != null && toDept.equalsIgnoreCase(myDept));
            case "TO_OK" -> isSuper || "registrar".equals(office) || "dregistrar".equals(office);
            case "REG_OK" -> isSuper || "academic".equals(office);
            default -> false;
        };
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
        String office = actingOffice();
        String myDept = scope.actingDept();
        for (Map<String, Object> r : rows) {
            String st = String.valueOf(r.get("state"));
            boolean paid = r.get("fee_confirmed_at") != null;
            r.put("stageLabel", stageLabel(st, paid));
            r.put("canApprove", mayApprove(office, myDept,
                    st, str(r.get("from_dept")), str(r.get("to_dept")), paid));
        }
        return Map.of("rows", rows);
    }

    private static String str(Object o) {
        return o == null ? null : String.valueOf(o);
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

    /** one desk's Approve, moving the application to the next office in the chain. The stage decides which
     *  office may act: the current-department HOD, then the new-department HOD, then the Registrar, then
     *  the Academic office. */
    private Map<String, Object> stageOf(UUID id) {
        List<Map<String, Object>> rows = jdbc.sql("""
                SELECT t.state, fp.dept_code AS from_dept, tp.dept_code AS to_dept,
                       CASE WHEN t.fee_reference IS NULL THEN false
                            ELSE (SELECT fs.confirmed_at IS NOT NULL FROM finance.reference_state(t.fee_reference) fs) END AS paid
                  FROM people.transfer_application t
                  LEFT JOIN ref.programme fp ON fp.code = t.from_programme_code
                  LEFT JOIN ref.programme tp ON tp.code = t.to_programme_code
                 WHERE t.id = :id
                """).param("id", id).query().listOfRows();
        if (rows.isEmpty()) {
            throw new NotFound("transfer application", id.toString());
        }
        return rows.get(0);
    }

    @PostMapping("/api/v1/transfers/{id}/approve")
    @PreAuthorize(APPROVERS)
    @Transactional
    Map<String, Object> approve(@PathVariable UUID id) {
        Map<String, Object> row = stageOf(id);
        String state = str(row.get("state"));
        boolean paid = Boolean.TRUE.equals(row.get("paid"));
        if (!mayApprove(actingOffice(), scope.actingDept(), state, str(row.get("from_dept")), str(row.get("to_dept")), paid)) {
            throw new DomainRuleViolation("TR_NOT_YOUR_STAGE",
                    "This application is not ready at your desk. " + stageLabel(state, paid) + ".",
                    new DomainRuleViolation.Remedy("The current department approves only after the student has paid; each later office approves in turn.", "Registry"));
        }
        String next = jdbc.sql("SELECT people.approve_transfer(:id)").param("id", id).query(String.class).single();
        return Map.of("id", id, "state", next);
    }

    /** any desk currently holding the application may decline it, with the reason on the record (payment not required) */
    @PostMapping("/api/v1/transfers/{id}/decline")
    @PreAuthorize(APPROVERS)
    @Transactional
    Map<String, Object> decline(@PathVariable UUID id, @Valid @RequestBody Why body) {
        Map<String, Object> row = stageOf(id);
        String state = str(row.get("state"));
        boolean paid = Boolean.TRUE.equals(row.get("paid"));
        if (!mayApprove(actingOffice(), scope.actingDept(), state, str(row.get("from_dept")), str(row.get("to_dept")), true)) {
            throw new DomainRuleViolation("TR_NOT_YOUR_STAGE",
                    "This application is not at your desk. " + stageLabel(state, paid) + ".",
                    new DomainRuleViolation.Remedy("Only the office holding the application at this stage may decline it.", "Registry"));
        }
        jdbc.sql("SELECT people.decline_transfer(:id, :w)").param("id", id).param("w", body.why()).query().singleRow();
        return Map.of("id", id, "state", "DECLINED");
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
