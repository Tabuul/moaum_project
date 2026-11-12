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
    /** V701: the routes of the preliminary stack, and the slugs their public pages go by */
    static final Map<String, String> SLUGS = Map.of("preliminary-science", "PRELIMINARY_SCIENCE", "preliminary-technology", "PRELIMINARY_TECHNOLOGY",
                                                    "proficiency-certificate", "PROFICIENCY_CERTIFICATE");
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

    public record Register(String surname, String firstName, String middleName, String sex, String dateOfBirth, String email, String phone, String password, String route) {
    }

    /** V701: a route by its code or its page's slug, one the stack holds; none named is Preliminary Science (V446's door) */
    String routeOf(String raw) {
        String r = raw == null || raw.isBlank() ? ROUTE : SLUGS.getOrDefault(raw.trim().toLowerCase(), raw.trim().toUpperCase());
        Optional<String> found = jdbc.sql("SELECT route FROM admissions.prelim_programme WHERE route = :r").param("r", r).query(String.class).optional();
        return found.orElseThrow(() -> new DomainRuleViolation("PRELIM_NO_PROGRAMME", "There is no such programme to apply to.",
                new DomainRuleViolation.Remedy("Choose one of the programmes on the application page.", "You")));
    }

    /** V701: the window a route's applications come through */
    String windowOf(String route) {
        return jdbc.sql("SELECT window_type FROM admissions.prelim_programme WHERE route = :r").param("r", route).query(String.class).single();
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
        String route = routeOf(r.route());
        windows.requireOpen(windowOf(route), null);
        String hash = encoder.encode(r.password());
        AuditContextHolder.with(new AuditContext(NOBODY, "applicant", "Application started (" + route + ")", null, ip), () -> tx.execute(status ->
                jdbc.sql("SELECT admissions.prelim_register(:route, :s, :f, :m, :sex, :dob, :e, :p, :h)")
                        .param("route", route).param("s", r.surname().trim()).param("f", r.firstName().trim())
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
            throw new DomainRuleViolation("PRELIM_NOT_APPLICATION", "This is not a preliminary or proficiency programme application.",
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
                SELECT r.*, coalesce(p.name, t.requested_name) AS target_name, pr.name AS programme_name, a.session, a.application_no, c.sex,
                       admissions.prelim_fee_settled(r.application_id) AS fee_settled, t.kind AS target_kind, t.group_name AS target_group,
                       t.requested_name AS target_requested, sp.name AS specialisation_name, sp.code AS specialisation_code
                  FROM admissions.prelim_review r JOIN admissions.application a ON a.id = r.application_id
                  JOIN admissions.candidate c ON c.id = a.candidate_id
                  JOIN admissions.prelim_programme pr ON pr.route = r.route
                  LEFT JOIN admissions.prelim_target t ON t.id = r.target_id
                  LEFT JOIN admissions.prelim_specialisation sp ON sp.id = r.specialisation_id
                  LEFT JOIN ref.programme p ON p.code = t.programme_code
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
        // V701: the target by id (a programme or a certificate course), its area or category, and the option chosen
        b.put("targetId", r.get("target_id"));
        b.put("targetKind", r.get("target_kind"));
        b.put("targetGroup", r.get("target_group"));
        b.put("targetRequestedName", r.get("target_requested"));
        b.put("specialisationId", r.get("specialisation_id"));
        b.put("specialisationName", r.get("specialisation_name"));
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
        // V737: an application brought from the old portal — its old number and the day it was made there (the Office reads where it came from too)
        b.put("legacy", legacy(app, forOffice));
        // V737: a fee paid on the old portal, held until the Bursary verifies it — the applicant is not asked to pay it again (only while
        // the fee is not otherwise settled: one paid here meanwhile, or a fee of nothing, needs no word of a payment being verified)
        boolean held = jdbc.sql("SELECT EXISTS (SELECT 1 FROM admissions.prelim_legacy_fee f WHERE f.application_id = :a AND f.state = 'REQUIRES_REVIEW')"
                        + " AND NOT admissions.prelim_fee_settled(:a)")
                .param("a", app).query(Boolean.class).single();
        b.put("feeHeld", held ? FEE_HELD : null);
        b.put("events", jdbc.sql("""
                SELECT e.at, e.action, e.from_state, e.to_state, e.note, e.office FROM admissions.prelim_review_event e
                 WHERE e.application_id = :a AND (:office OR e.action IN ('REGISTERED', 'SUBMITTED', 'CORRECTED', 'REQUEST_CORRECTION', 'WITHDRAWN', 'PUBLISHED', 'TARGET_SET',
                                                                          'MIGRATED', 'ROUTE_CHANGED', 'OLD_FEE_VERIFIED', 'OLD_FEE_REJECTED', 'OLD_FEE_REVERSED'))
                 ORDER BY e.at
                """).param("a", app).param("office", forOffice).query().listOfRows());
        b.put("programmeInfo", json(jdbc.sql("SELECT admissions.prelim_public(:r)::text").param("r", r.get("route")).query(String.class).single()));
        return b;
    }

    /** V737: what the applicant reads while a fee paid on the old portal waits for the Bursary */
    static final String FEE_HELD = "Your application fee paid on the old portal is being verified by the Bursary. You will not be asked to pay it again.";

    /** V737: the old portal's facts of an application brought across, or null for one made here: the old number and the day it was made
     *  for the applicant; for the Office also where it came from, the batch, who brought it and when, and the old portal's words as written */
    Map<String, Object> legacy(UUID app, boolean forOffice) {
        Map<String, Object> l = jdbc.sql("""
                SELECT l.legacy_application_no, l.applied_on::text AS applied_on, l.legacy_source, l.legacy_jamb_reg_no, l.legacy_exam_number, l.legacy_programme,
                       l.legacy_target, l.legacy_status, l.legacy_admission, l.route_at_import, l.migrated_at, l.migrated_office, l.told_at,
                       (SELECT b.reference FROM admissions.prelim_migration_batch b WHERE b.id = l.batch_id) AS batch_reference,
                       (SELECT p.surname || ', ' || p.given_names FROM iam.person p WHERE p.id = l.migrated_by) AS migrated_by
                  FROM admissions.prelim_legacy_application l WHERE l.application_id = :a
                """).param("a", app).query().listOfRows().stream().findFirst().orElse(null);
        if (l == null) return null;
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("number", l.get("legacy_application_no"));
        out.put("appliedOn", l.get("applied_on"));
        if (forOffice) {
            out.put("source", l.get("legacy_source"));
            out.put("batchReference", l.get("batch_reference"));
            out.put("migratedAt", l.get("migrated_at"));
            out.put("migratedBy", l.get("migrated_by"));
            out.put("migratedOffice", l.get("migrated_office"));
            out.put("routeAtImport", l.get("route_at_import"));
            out.put("jambRegNo", l.get("legacy_jamb_reg_no"));
            out.put("examNumber", l.get("legacy_exam_number"));
            out.put("programmeAsWritten", l.get("legacy_programme"));
            out.put("targetAsWritten", l.get("legacy_target"));
            out.put("status", l.get("legacy_status"));
            out.put("admission", l.get("legacy_admission"));
            out.put("toldAt", l.get("told_at"));
        }
        return out;
    }

    /** V737: the application fees an application holds from the old portal, with the Bursary's decision on each */
    List<Map<String, Object>> legacyFees(UUID app) {
        return jdbc.sql("""
                SELECT f.id, f.legacy_reference, f.gateway_reference, f.amount, f.paid_on, f.stated_status, f.state,
                       f.decided_at, f.decided_office, f.decision_note, f.created_at,
                       (SELECT p.surname || ', ' || p.given_names FROM iam.person p WHERE p.id = f.decided_by) AS decided_by,
                       (SELECT b.reference FROM admissions.prelim_migration_batch b WHERE b.id = f.batch_id) AS batch_reference,
                       (SELECT x.reference FROM admissions.fee_reference x WHERE x.id = f.fee_reference_id) AS posted_reference
                  FROM admissions.prelim_legacy_fee f WHERE f.application_id = :a ORDER BY f.created_at
                """).param("a", app).query().listOfRows();
    }

    /** V737: the programme changes of an application between the two preliminary routes, applied and refused, oldest first */
    List<Map<String, Object>> routeChanges(UUID app) {
        return jdbc.sql("""
                SELECT c.id, c.reference, c.from_route, (SELECT p.name FROM admissions.prelim_programme p WHERE p.route = c.from_route) AS from_name,
                       c.to_route, (SELECT p.name FROM admissions.prelim_programme p WHERE p.route = c.to_route) AS to_name,
                       c.from_target_name, c.from_specialisation_name, c.from_state, c.to_state, c.reason, c.fee_status, c.fee_amount, c.fee_references,
                       c.missing::text AS missing, c.result, c.refusal_code, c.refusal_message, c.actor_office, c.at,
                       (SELECT p.surname || ', ' || p.given_names FROM iam.person p WHERE p.id = c.actor) AS actor
                  FROM admissions.prelim_route_change c WHERE c.application_id = :a ORDER BY c.at
                """).param("a", app).query().listOfRows().stream().map(r -> {
                    Map<String, Object> m = new LinkedHashMap<>(r);
                    m.put("missing", json(r.get("missing")));
                    return m;
                }).toList();
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

    /** the target and its option: by id (V701: a programme or a certificate course), or by programme code as V446 */
    @Transactional
    public Map<String, Object> target(UUID account, String programmeCode, UUID targetId, UUID specialisationId) {
        UUID app = application(account);
        if (targetId != null) {
            jdbc.sql("SELECT admissions.prelim_choose(:a, :t, :s, NULL)").param("a", app).param("t", targetId)
                    .param("s", specialisationId, java.sql.Types.OTHER).query(String.class).single();
        } else {
            jdbc.sql("SELECT admissions.prelim_set_target(:a, :p, NULL)").param("a", app).param("p", programmeCode).query(String.class).single();
        }
        return view(account);
    }

    @Transactional
    public Map<String, Object> withdraw(UUID account, String note) {
        UUID app = application(account);
        jdbc.sql("SELECT admissions.prelim_withdraw(:a, :n)").param("a", app).param("n", note, java.sql.Types.VARCHAR).query(String.class).single();
        return view(account);
    }

    /** the programme as the public reads it (V701: any route, by code or slug) */
    @Transactional(readOnly = true)
    public Map<String, Object> publicInfo(String route) {
        return json(jdbc.sql("SELECT admissions.prelim_public(:r)::text").param("r", routeOf(route)).query(String.class).single());
    }

    /** V701: the preliminary and proficiency programmes the public application page offers, by programme type */
    @Transactional(readOnly = true)
    public List<Map<String, Object>> routes() {
        List<Map<String, Object>> v = json(jdbc.sql("SELECT admissions.prelim_routes_public()::text").query(String.class).single());
        return v == null ? List.of() : v;
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
