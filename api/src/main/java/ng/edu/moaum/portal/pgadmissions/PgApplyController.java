package ng.edu.moaum.portal.pgadmissions;

import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import jakarta.validation.Valid;
import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

import ng.edu.moaum.portal.shared.AuditContext;
import ng.edu.moaum.portal.shared.AuditContextHolder;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * The public postgraduate application — open to the world, like the undergraduate post-UTME apply
 * (V021). A prospective postgraduate registers, states their first degree and (for a research degree)
 * a proposal, names referees, and gets an application number and a fee reference to pay. The writes are
 * attributed to the applicant at the door, exactly as the undergraduate applicant registration is.
 * These four endpoints are whitelisted in SecurityConfig; the rest of /api/v1/pg is office-only.
 */
@RestController
@RequestMapping("/api/v1/pg")
class PgApplyController {

    private static final UUID NOBODY = new UUID(0, 0);
    private final JdbcClient jdbc;
    private final TransactionTemplate tx;
    private final tools.jackson.databind.ObjectMapper json;
    private final BCryptPasswordEncoder encoder = new BCryptPasswordEncoder(12);

    PgApplyController(JdbcClient jdbc, PlatformTransactionManager transactions, tools.jackson.databind.ObjectMapper json) {
        this.jdbc = jdbc;
        this.tx = new TransactionTemplate(transactions);
        this.json = json;
    }

    /** the postgraduate programmes to apply into, for the form's picker (public) */
    @GetMapping("/programmes")
    List<Map<String, Object>> programmes() {
        return jdbc.sql("""
                SELECT g.code, g.name, f.name AS faculty_name, d.name AS department_name, g.pg_award, g.pg_research
                  FROM ref.programme g
                  JOIN ref.faculty f ON f.code = g.faculty_code
                  JOIN ref.department d ON d.code = g.dept_code
                 WHERE g.category = 'POST GRADUATE' AND NOT g.archived
                 ORDER BY f.name, g.name
                """).query().listOfRows();
    }

    public record RefereeIn(String name, String email, String institution, String position) {
    }

    public record ApplyIn(@NotBlank @Size(max = 80) String surname, @Size(max = 120) String otherNames,
                          @Size(max = 10) String sex, @Size(max = 10) String dob,
                          @Size(max = 80) String state, @Size(max = 80) String lga,
                          @NotBlank @Email @Size(max = 160) String email, @Size(max = 20) String phone,
                          @NotBlank @Size(min = 6, max = 100) String password, @NotBlank String programme,
                          @Size(max = 200) String priorInstitution, @Size(max = 120) String priorAward,
                          @Size(max = 60) String priorClass, @Size(max = 8) String priorCgpa, @Size(max = 8) String priorYear,
                          @Size(max = 300) String proposalTitle, @Size(max = 5000) String proposalText,
                          List<RefereeIn> referees) {
    }

    /** apply: creates the applicant account and a submitted application, and returns the fee reference to pay */
    @PostMapping("/apply")
    Map<String, Object> apply(@Valid @RequestBody ApplyIn body) {
        Map<String, Object> form = new LinkedHashMap<>();
        form.put("surname", body.surname());
        form.put("otherNames", body.otherNames());
        form.put("sex", body.sex());
        form.put("dob", body.dob());
        form.put("state", body.state());
        form.put("lga", body.lga());
        form.put("email", body.email());
        form.put("phone", body.phone());
        form.put("passwordHash", encoder.encode(body.password()));
        form.put("programme", body.programme());
        form.put("priorInstitution", body.priorInstitution());
        form.put("priorAward", body.priorAward());
        form.put("priorClass", body.priorClass());
        form.put("priorCgpa", body.priorCgpa());
        form.put("priorYear", body.priorYear());
        form.put("proposalTitle", body.proposalTitle());
        form.put("proposalText", body.proposalText());
        form.put("referees", body.referees() == null ? List.of() : body.referees());
        String j = json.writeValueAsString(form);
        return AuditContextHolder.with(new AuditContext(NOBODY, "applicant", "postgraduate application", null, null),
                () -> tx.execute(st -> jdbc.sql("SELECT * FROM admissions.pg_apply(:j::jsonb)").param("j", j).query().singleRow()));
    }

    /** check an application's status, by its number and the email it was made with (public) */
    @GetMapping("/status")
    Map<String, Object> status(@RequestParam String applicationNo, @RequestParam String email) {
        List<Map<String, Object>> rows = jdbc.sql("""
                SELECT a.application_no, a.state, a.entry_level, g.name AS programme_name, g.pg_award,
                       p.surname, p.other_names, a.fee_confirmed_at, a.submitted_at, a.spgs_note, a.spgs_decided_at
                  FROM admissions.pg_application a
                  JOIN admissions.pg_applicant p ON p.id = a.applicant_id
                  JOIN ref.programme g ON g.code = a.programme_code
                 WHERE a.application_no = :no AND lower(p.email) = lower(:email)
                """).param("no", applicationNo.trim()).param("email", email.trim()).query().listOfRows();
        return rows.isEmpty() ? Map.of("found", false) : Map.of("found", true, "application", rows.get(0));
    }

    public record AcceptIn(@NotBlank String applicationNo, @NotBlank String email) {
    }

    /** accept the offer, by application number and email (public) */
    @PostMapping("/accept")
    Map<String, Object> accept(@Valid @RequestBody AcceptIn body) {
        List<Map<String, Object>> rows = jdbc.sql("""
                SELECT a.id, a.state FROM admissions.pg_application a
                  JOIN admissions.pg_applicant p ON p.id = a.applicant_id
                 WHERE a.application_no = :no AND lower(p.email) = lower(:email)
                """).param("no", body.applicationNo().trim()).param("email", body.email().trim()).query().listOfRows();
        if (rows.isEmpty()) {
            return Map.of("ok", false, "reason", "No application matches that number and email.");
        }
        String state = String.valueOf(rows.get(0).get("state"));
        if (!"OFFERED".equals(state)) {
            return Map.of("ok", false, "reason", "Only an offer can be accepted; this application is " + state.toLowerCase() + ".");
        }
        UUID id = (UUID) rows.get(0).get("id");
        AuditContextHolder.with(new AuditContext(NOBODY, "applicant", "postgraduate offer accepted", null, null),
                () -> tx.execute(st -> { jdbc.sql("SELECT admissions.pg_accept(:id)").param("id", id).query().listOfRows(); return null; }));
        return Map.of("ok", true);
    }
}
