package ng.edu.moaum.portal.applicant;

import java.time.LocalDate;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;

import ng.edu.moaum.portal.shared.ApplicationWindows;
import ng.edu.moaum.portal.shared.AuditContext;
import ng.edu.moaum.portal.shared.AuditContextHolder;
import ng.edu.moaum.portal.shared.DomainRuleViolation;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionTemplate;

/**
 * V446: the Preliminary Science applicant — on the shared applicant stack (the ordinary candidate, account and application;
 * the ordinary fee references, documents and sign-in), with the programme's own form, O'Level, target programme and review.
 * Everything the applicant changes goes through the database's functions (admissions.prelim_*), which hold the rules: the fee
 * before the form, no awaiting result, a configured target only, the window at submission. The eligibility is the backend's.
 */
@Service
public class PrelimApplicantService {

    static final String ROUTE = "PRELIMINARY_SCIENCE";
    private static final UUID NOBODY = new UUID(0L, 0L);
    private static final tools.jackson.databind.ObjectMapper JSON = new tools.jackson.databind.ObjectMapper();

    private final JdbcClient jdbc;
    private final ApplicantService applicants;
    private final ApplicationWindows windows;
    private final TransactionTemplate tx;
    private final BCryptPasswordEncoder encoder = new BCryptPasswordEncoder(12);

    PrelimApplicantService(JdbcClient jdbc, ApplicantService applicants, ApplicationWindows windows, PlatformTransactionManager transactions) {
        this.jdbc = jdbc;
        this.applicants = applicants;
        this.windows = windows;
        this.tx = new TransactionTemplate(transactions);
    }

    public record Register(String surname, String firstName, String middleName, String sex, String dateOfBirth, String email, String phone, String password) {
    }

    /** the application started: the window open, an address and a person once; the applicant signed in at once */
    public ApplicantService.SignedIn register(Register r, String ip) {
        String mail = r.email() == null ? "" : r.email().trim();
        String phone = ApplicantService.phone(r.phone());
        LocalDate dob = ApplicantService.isoDate(r.dateOfBirth());
        if (r.surname() == null || r.surname().isBlank() || r.firstName() == null || r.firstName().isBlank()) {
            throw new DomainRuleViolation("PRELIM_NAME", "The surname and first name are given.",
                    new DomainRuleViolation.Remedy("As they appear on your O'Level certificate.", "You"));
        }
        if (dob == null) {
            throw new DomainRuleViolation("PRELIM_DATE_OF_BIRTH", "The date of birth was not given.", new DomainRuleViolation.Remedy("Give it as YYYY-MM-DD.", "You"));
        }
        if (!ApplicantService.EMAIL_SHAPE.matcher(mail).matches()) {
            throw new DomainRuleViolation("APP_EMAIL", "That is not a complete email address.",
                    new DomainRuleViolation.Remedy("It needs a name, an @, and a domain with a dot in it — you@example.com.", "You"));
        }
        if (!phone.matches("^0\\d{10}$")) {
            throw new DomainRuleViolation("APP_PHONE", "A Nigerian mobile number is eleven digits beginning with a zero.",
                    new DomainRuleViolation.Remedy("Written as +234 or without the zero is fine; " + phone.length() + " digits were read.", "You"));
        }
        if (r.password() == null || r.password().length() < ApplicantService.MIN_PASSWORD) {
            throw new DomainRuleViolation("APP_PASSWORD_SHORT", "Eight characters at the very least.",
                    new DomainRuleViolation.Remedy("Choose a longer password.", "You"));
        }
        // the window first, with the Director's own message; the database refuses once more behind it
        windows.requireOpen(ApplicationWindows.PRELIMINARY_SCIENCE, null);
        String hash = encoder.encode(r.password());
        AuditContextHolder.with(new AuditContext(NOBODY, "applicant", "Preliminary Science application started", null, ip), () -> tx.execute(status ->
                jdbc.sql("SELECT admissions.prelim_register(:route, :s, :f, :m, :sex, :dob, :e, :p, :h)")
                        .param("route", ROUTE).param("s", r.surname().trim()).param("f", r.firstName().trim())
                        .param("m", r.middleName() == null ? null : r.middleName().trim(), java.sql.Types.VARCHAR)
                        .param("sex", r.sex() == null ? null : r.sex().trim().toUpperCase(), java.sql.Types.VARCHAR)
                        .param("dob", dob).param("e", mail).param("p", phone).param("h", hash)
                        .query(UUID.class).single()));
        return applicants.signIn(mail, r.password(), ip);
    }

    /** the account's application, which must be a Preliminary Science one */
    UUID application(UUID account) {
        UUID app = applicants.applicationOf(account);
        if (route(app).isEmpty()) {
            throw new DomainRuleViolation("PRELIM_NOT_APPLICATION", "This is not a Preliminary Science application.",
                    new DomainRuleViolation.Remedy("Use the applicant pages of your own application.", "You"));
        }
        return app;
    }

    Optional<String> route(UUID app) {
        return jdbc.sql("SELECT route FROM admissions.prelim_review WHERE application_id = :a").param("a", app).query(String.class).optional();
    }

    /** the application as the applicant works through it: the ordinary view, and the programme's own form, rule, targets and history */
    @Transactional(readOnly = true)
    public Map<String, Object> view(UUID account) {
        UUID app = application(account);
        Map<String, Object> v = new LinkedHashMap<>(applicants.view(app, false));
        v.put("preliminary", block(app, false));
        return v;
    }

    /** the programme's part of an application: for the applicant (no officer notes on unpublished steps) or for the Office */
    Map<String, Object> block(UUID app, boolean forOffice) {
        Map<String, Object> r = jdbc.sql("""
                SELECT r.*, p.name AS target_name, pr.name AS programme_name, a.session, a.application_no, c.sex,
                       admissions.prelim_fee_settled(r.application_id) AS fee_settled
                  FROM admissions.prelim_review r JOIN admissions.application a ON a.id = r.application_id
                  JOIN admissions.candidate c ON c.id = a.candidate_id
                  JOIN admissions.prelim_programme pr ON pr.route = r.route
                  LEFT JOIN ref.programme p ON p.code = r.target_programme
                 WHERE r.application_id = :a
                """).param("a", app).query().singleRow();
        Map<String, Object> b = new LinkedHashMap<>();
        String state = String.valueOf(r.get("state"));
        boolean published = r.get("published_at") != null;
        b.put("route", r.get("route"));
        b.put("programme", r.get("programme_name"));
        // the applicant reads their own steps; a decision not yet published reads as under review
        b.put("state", forOffice || published || List.of("DRAFT", "SUBMITTED", "CORRECTION_REQUIRED", "WITHDRAWN").contains(state) ? state : "UNDER_REVIEW");
        b.put("editable", List.of("DRAFT", "CORRECTION_REQUIRED").contains(state));
        b.put("feeSettled", r.get("fee_settled"));
        b.put("sex", r.get("sex"));
        b.put("targetProgramme", r.get("target_programme"));
        b.put("targetName", r.get("target_name"));
        b.put("submittedAt", r.get("submitted_at"));
        b.put("requestNote", "CORRECTION_REQUIRED".equals(state) || forOffice ? r.get("request_note") : null);
        b.put("eligibility", Map.of(
                "status", String.valueOf(r.get("eligibility_status")),
                "totalCredits", r.get("total_credits") == null ? -1 : r.get("total_credits"),
                "coreCredits", r.get("core_credits") == null ? -1 : r.get("core_credits"),
                "sittings", r.get("sittings") == null ? 0 : r.get("sittings"),
                "creditedCore", strings(r.get("credited_core")),
                "checks", json(r.get("eligibility_checks")),
                "reasons", strings(r.get("eligibility_reasons"))));
        Map<String, Object> rem = new LinkedHashMap<>();
        rem.put("status", r.get("remediation_status"));
        rem.put("subjects", strings(r.get("remediation_subjects")));
        rem.put("creditsShort", r.get("remediation_credits_short"));
        rem.put("note", forOffice ? r.get("remediation_note") : null);
        b.put("remediation", rem);
        b.put("olevelVerification", forOffice || published ? r.get("olevel_verification") : null);
        b.put("fields", jdbc.sql("""
                SELECT f.field, f.required, bf.label, x.value FROM admissions.prelim_form_fields() WITH ORDINALITY f(field, required, ord)
                  LEFT JOIN ref.biodata_field bf ON bf.field = f.field
                  LEFT JOIN admissions.screening_answer x ON x.application_id = :a AND x.field = f.field
                 ORDER BY f.ord
                """).param("a", app).query().listOfRows());
        b.put("olevel", jdbc.sql("""
                SELECT sitting, exam_body, exam_type, exam_number, exam_year, subject, grade FROM admissions.screening_olevel
                 WHERE application_id = :a AND active ORDER BY sitting, ord
                """).param("a", app).query().listOfRows());
        b.put("problems", jdbc.sql("SELECT step, field, message FROM admissions.prelim_problems(:a)").param("a", app).query().listOfRows());
        b.put("events", jdbc.sql("""
                SELECT e.at, e.action, e.from_state, e.to_state, e.note, e.office FROM admissions.prelim_review_event e
                 WHERE e.application_id = :a AND (:office OR e.action IN ('REGISTERED', 'SUBMITTED', 'CORRECTED', 'REQUEST_CORRECTION', 'WITHDRAWN', 'PUBLISHED', 'TARGET_SET'))
                 ORDER BY e.at
                """).param("a", app).param("office", forOffice).query().listOfRows());
        b.put("programmeInfo", json(jdbc.sql("SELECT admissions.prelim_public(:r)::text").param("r", r.get("route")).query(String.class).single()));
        return b;
    }

    @Transactional
    public Map<String, Object> biodata(UUID account, Map<String, String> fields, String sex) {
        UUID app = application(account);
        jdbc.sql("SELECT admissions.prelim_save_biodata(:a, :f::jsonb, :s)").param("a", app)
                .param("f", JSON.writeValueAsString(fields == null ? Map.of() : fields)).param("s", sex, java.sql.Types.VARCHAR).query(Integer.class).single();
        return view(account);
    }

    @Transactional
    public Map<String, Object> olevel(UUID account, List<Map<String, Object>> sittings) {
        UUID app = application(account);
        jdbc.sql("SELECT admissions.prelim_save_olevel(:a, :s::jsonb)").param("a", app)
                .param("s", JSON.writeValueAsString(sittings == null ? List.of() : sittings)).query(Integer.class).single();
        return view(account);
    }

    @Transactional
    public Map<String, Object> target(UUID account, String programmeCode) {
        UUID app = application(account);
        jdbc.sql("SELECT admissions.prelim_set_target(:a, :p, NULL)").param("a", app).param("p", programmeCode).query(String.class).single();
        return view(account);
    }

    @Transactional
    public Map<String, Object> withdraw(UUID account, String note) {
        UUID app = application(account);
        jdbc.sql("SELECT admissions.prelim_withdraw(:a, :n)").param("a", app).param("n", note, java.sql.Types.VARCHAR).query(String.class).single();
        return view(account);
    }

    /** the programme as the public reads it */
    @Transactional(readOnly = true)
    public Map<String, Object> publicInfo() {
        return json(jdbc.sql("SELECT admissions.prelim_public(:r)::text").param("r", ROUTE).query(String.class).single());
    }

    /** a text[] column as a list of strings (empty for none) */
    static List<String> strings(Object pgArray) {
        Object[] items;
        try {
            items = pgArray instanceof java.sql.Array a ? (Object[]) a.getArray() : pgArray instanceof Object[] o ? o : new Object[0];
        } catch (java.sql.SQLException e) {
            throw new IllegalStateException(e);
        }
        return java.util.Arrays.stream(items).map(String::valueOf).toList();
    }

    @SuppressWarnings("unchecked")
    static <T> T json(Object pg) {
        if (pg == null) return null;
        return (T) JSON.readValue(pg.toString(), Object.class);
    }
}
