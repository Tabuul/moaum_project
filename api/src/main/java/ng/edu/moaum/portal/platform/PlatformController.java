package ng.edu.moaum.portal.platform;

import java.time.Instant;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.Map;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.dao.DataAccessException;
import java.util.List;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;
import ng.edu.moaum.portal.shared.ApplicationWindows;
import ng.edu.moaum.portal.shared.Sessions;

/**
 * What is actually true about this service — the same questions
 * {@code web/server.js} answers on {@code /healthz}, so that the two can be
 * compared: which migrations are applied, and whether the admission settings
 * for the coming session are a draft or in force.
 */
@RestController
@RequestMapping("/api/v1/platform")
class PlatformController {

    private static final Instant STARTED = Instant.now();

    private final JdbcClient jdbc;
    private final String commit;
    private final tools.jackson.databind.ObjectMapper json;
    private final ApplicationWindows windows;
    private final ReadinessSnapshot readiness;

    PlatformController(JdbcClient jdbc, tools.jackson.databind.ObjectMapper json, ApplicationWindows windows, ReadinessSnapshot readiness,
                       @Value("${moaum.commit:${RAILWAY_GIT_COMMIT_SHA:}}") String commit) {
        this.jdbc = jdbc;
        this.json = json;
        this.windows = windows;
        this.readiness = readiness;
        this.commit = commit;
    }

    public record ResetIn(@NotBlank @Size(max = 20) String confirm, @NotBlank @Size(max = 400) String reason) {
    }

    /**
     * The Super Administrator's clean slate: clears operational data (admissions, students, results,
     * courses, fees, payments, wallets) while keeping reference data, configuration, staff logins and
     * the audit trail. Guarded by the word RESET and a reason; the database function runs it in one
     * transaction and records every deletion on the spine in the actor's name.
     */
    @PostMapping("/reset-data")
    @PreAuthorize("hasAnyAuthority('OFFICE_super','OFFICE_ict')")
    @Transactional
    Map<String, Object> resetData(@Valid @RequestBody ResetIn body) {
        String result = jdbc.sql("SELECT platform.reset_operational_data(:c, :r)")
                .param("c", body.confirm()).param("r", body.reason()).query(String.class).single();
        return json.readValue(result, new tools.jackson.core.type.TypeReference<Map<String, Object>>() { });
    }

    public record ConfirmIn(@NotBlank @Size(max = 20) String confirm) {
    }

    /** Remove only the demo (db/demo.sql) operational data — demo students, DMO courses and demo
     *  candidates — keeping the demo staff logins and every real upload. Guarded by the words REMOVE DEMO;
     *  the database function runs it in one transaction. */
    @PostMapping("/remove-demo")
    @PreAuthorize("hasAnyAuthority('OFFICE_super','OFFICE_ict')")
    @Transactional
    Map<String, Object> removeDemo(@Valid @RequestBody ConfirmIn body) {
        String result = jdbc.sql("SELECT platform.remove_demo_data(:c)").param("c", body.confirm()).query(String.class).single();
        return json.readValue(result, new tools.jackson.core.type.TypeReference<Map<String, Object>>() { });
    }

    /** Remove only the demo courses left in the catalogue — those coded DMO/DMC or titled 'Demo …' — with
     *  their offerings, materials, score sheets and registration entries. Touches no student or candidate.
     *  Guarded by the words REMOVE DEMO; the database function runs it in one transaction. */
    @PostMapping("/remove-demo-courses")
    @PreAuthorize("hasAnyAuthority('OFFICE_super','OFFICE_ict')")
    @Transactional
    Map<String, Object> removeDemoCourses(@Valid @RequestBody ConfirmIn body) {
        String result = jdbc.sql("SELECT platform.remove_demo_courses(:c)").param("c", body.confirm()).query(String.class).single();
        return json.readValue(result, new tools.jackson.core.type.TypeReference<Map<String, Object>>() { });
    }

    /** the three parts of the readiness: the admission exercise (the intake session, V378), the running session, and what
     *  holds across the University */
    static final String INTAKE = "intake";
    static final String RUNNING = "running";
    static final String INSTITUTION = "institution";
    /** V412: CCE admission, in the CCE session */
    static final String CCE = "cce";

    private static Map<String, Object> chk(String group, String key, String label, String status, String detail, String fix) {
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("group", group);
        m.put("key", key);
        m.put("label", label);
        m.put("status", status);   // ok | warn | bad
        m.put("detail", detail);
        m.put("fix", fix);
        return m;
    }

    /** Go-live readiness: each configuration gate that silently blocks part of launch, checked live, so it is a screen and
     *  not a manual list. Read-only. Two sessions are checked at once: the admission exercise is the intake session's
     *  ({@code intake}; by default policy.intake_session(), the session candidates apply into — V378), and registration,
     *  school fees and clearance are the running session's ({@code session}; by default the University's current one), so
     *  the coming session's admissions are not read green from the last exercise, nor the running session's fees from the
     *  coming one. */
    @GetMapping("/readiness")
    @PreAuthorize("hasAnyAuthority('OFFICE_super','OFFICE_ict','OFFICE_admin','OFFICE_registrar','OFFICE_dregistrar','OFFICE_academic','OFFICE_bursar')")
    @Transactional(readOnly = true)
    Map<String, Object> readiness(@RequestParam(required = false) String session, @RequestParam(required = false) String intake) {
        String s = session != null && session.matches("\\d{4}/\\d{4}") ? session
                : jdbc.sql("SELECT policy.university_current_session()").query(String.class).optional().orElseGet(Sessions::byDate);
        String in = intake != null && intake.matches("\\d{4}/\\d{4}") ? intake
                : jdbc.sql("SELECT policy.intake_session()").query(String.class).optional().orElse(s);
        List<Map<String, Object>> checks = new ArrayList<>();

        // ── the admission exercise: the intake session ──
        Map<String, Object> inSes = jdbc.sql("SELECT state, policy.session_label(state) AS label FROM policy.academic_session WHERE name = :s")
                .param("s", in).query().listOfRows().stream().findFirst().orElse(null);
        String inState = inSes == null ? null : (String) inSes.get("state");
        checks.add(chk(INTAKE, "intake_session", "Admission session on the calendar",
                inState == null ? "bad" : "PLANNED".equals(inState) || "CURRENT".equals(inState) ? "ok" : "warn",
                inState == null ? in + " is not on the calendar" : in + " is " + String.valueOf(inSes.get("label")).toLowerCase(), "/calendar"));

        Map<String, Object> fee = jdbc.sql("SELECT stated, application_fee, acceptance_fee, carried_from FROM admissions.applicant_fee_rule(:s)")
                .param("s", in).query().singleRow();
        boolean feeStated = Boolean.TRUE.equals(fee.get("stated"));
        // V401: the Bursary's rule for a session whose applicant fees are not stated — carried forward, or refused until stated
        boolean refuse = "REFUSE".equals(jdbc.sql("SELECT admissions.applicant_fee_policy()").query(String.class).optional().orElse("CARRY"));
        checks.add(chk(INTAKE, "applicant_fee", "Applicant fees set", feeStated ? "ok" : "bad",
                feeStated ? "Application, acceptance and checking fees are set for " + in
                        : refuse ? "Not set for " + in + ": candidates are refused a fee reference until the Bursary states them (the Bursary's rule)"
                        : "Not set for " + in + ": candidates would be charged " + (fee.get("carried_from") == null ? "the built-in amounts" : fee.get("carried_from") + "'s amounts")
                                + " (application ₦" + naira(fee.get("application_fee")) + ", acceptance ₦" + naira(fee.get("acceptance_fee")) + ")",
                "/finance/fees?session=" + in));

        boolean policy = Boolean.TRUE.equals(jdbc.sql("SELECT EXISTS(SELECT 1 FROM admissions.session_policy WHERE session=:s AND state='IN_FORCE')").param("s", in).query(Boolean.class).single());
        checks.add(chk(INTAKE, "admission_policy", "Admission policy in force", policy ? "ok" : "bad",
                policy ? "Weights and quota are in force for " + in : "No in-force policy for " + in, "/admissions/settings?session=" + in));

        long listed = jdbc.sql("SELECT count(*) FROM admissions.caps_row_live WHERE session = :s").param("s", in).query(Long.class).single();
        checks.add(chk(INTAKE, "jamb_list", "JAMB's list uploaded", listed > 0 ? "ok" : "bad",
                listed > 0 ? String.format(java.util.Locale.ENGLISH, "%,d", listed) + " candidates on JAMB's list for " + in
                        : "No JAMB list for " + in + ": the Post-UTME page finds no candidate", "/admissions/caps?session=" + in));

        ApplicationWindows.Window putme = windows.read(ApplicationWindows.POST_UTME, in);
        checks.add(chk(INTAKE, "post_utme_window", "Post-UTME registration open", putme.open() ? "ok" : "warn",
                putme.open() ? "Open for " + in + (putme.closesAt() == null ? "" : " until " + day(putme.closesAt()))
                        : "SCHEDULED".equals(putme.state()) && putme.opensAt() != null ? "Opens " + day(putme.opensAt()) + " for " + in
                        : "Closed for " + in + ": candidates cannot register", "/ict/applications?session=" + in));

        long examProg = jdbc.sql("SELECT count(*) FROM admissions.screening_exam_programme WHERE session=:s").param("s", in).query(Long.class).single();
        long putmeExams = jdbc.sql("SELECT count(*) FROM assessment.cbt_exam WHERE office = 'POST_UTME' AND putme_session = :s AND cancelled_at IS NULL")
                .param("s", in).query(Long.class).single();
        checks.add(chk(INTAKE, "exam_programmes", "Post-UTME examination", examProg == 0 || putmeExams > 0 ? "ok" : "warn",
                examProg == 0 ? "No programme screens by examination for " + in + "; all screen on O'Level"
                        : putmeExams > 0 ? examProg + " programme(s) screen by examination; the Post-UTME CBT is set up for " + in
                        : examProg + " programme(s) screen by examination, but no Post-UTME CBT is set up for " + in,
                examProg == 0 ? "/admissions/settings?session=" + in : "/ict/cbt"));

        // ── the running session ──
        String sesState = jdbc.sql("SELECT state FROM policy.academic_session WHERE name=:s").param("s", s).query(String.class).optional().orElse(null);
        checks.add(chk(RUNNING, "session", "Session on the calendar", sesState == null ? "bad" : "CURRENT".equals(sesState) ? "ok" : "warn",
                sesState == null ? s + " is not on the calendar" : s + " is " + sesState.toLowerCase(), "/calendar"));

        List<Integer> open = jdbc.sql("SELECT number FROM policy.semester WHERE session=:s AND state='OPEN' ORDER BY number").param("s", s).query(Integer.class).list();
        checks.add(chk(RUNNING, "semester", "A semester is open", open.isEmpty() ? "warn" : "ok",
                open.isEmpty() ? "No semester is open for " + s + " — students cannot register" : "Semester " + open.stream().map(String::valueOf).reduce((a, b) -> a + " and " + b).orElse("") + " open", "/calendar"));

        boolean feeSchedule = Boolean.TRUE.equals(jdbc.sql("SELECT EXISTS(SELECT 1 FROM finance.fee_schedule WHERE session=:s AND ended_at IS NULL)").param("s", s).query(Boolean.class).single());
        checks.add(chk(RUNNING, "fee_schedule", "School-fee schedule set", feeSchedule ? "ok" : "bad",
                feeSchedule ? "A current fee schedule exists for " + s : "No fee schedule for " + s + " — students cannot pay or register", "/finance/fees"));
        // V451: the live undergraduates the stated lines do not reach — none at all, or none for an open semester
        if (feeSchedule) {
            Map<String, Object> gaps = jdbc.sql("""
                    SELECT coalesce(sum(students), 0) AS students, count(*) AS groups,
                           string_agg(DISTINCT replace(replace(initcap(lower(coalesce(faculty, faculty_code))), ' And ', ' and '), ' Of ', ' of '), ', ') AS faculties
                      FROM finance.fee_gaps(:s)
                    """).param("s", s).query().singleRow();
            long gapStudents = ((Number) gaps.get("students")).longValue();
            long gapGroups = ((Number) gaps.get("groups")).longValue();
            checks.add(chk(RUNNING, "fee_gaps", "Every undergraduate has a school fee stated", gapStudents == 0 ? "ok" : open.isEmpty() ? "warn" : "bad",
                    gapStudents == 0 ? "Every live undergraduate has a school fee stated for " + s + (open.isEmpty() ? "" : ", for every open semester")
                            : String.format(java.util.Locale.ENGLISH, "%,d", gapStudents) + " live undergraduate" + (gapStudents == 1 ? "" : "s") + " in " + gapGroups
                                    + " group" + (gapGroups == 1 ? "" : "s") + " have no school fee stated for " + s + (open.isEmpty() ? "" : " or an open semester")
                                    + " (" + gaps.get("faculties") + "): they are shown nothing to pay and cannot register",
                    "/finance/fees?session=" + s));
        }

        boolean clearance = Boolean.TRUE.equals(jdbc.sql("SELECT policy.in_force('clearance','UNIVERSITY',current_date) IS NOT NULL").query(Boolean.class).single());
        checks.add(chk(RUNNING, "clearance", "Clearance scheme in force", clearance ? "ok" : "warn",
                clearance ? "A clearance scheme is in force" : "No clearance scheme in force — clearance cannot run", "/clearance"));

        // ── across the University ──
        long demoStudents = jdbc.sql("SELECT count(*) FROM people.student WHERE surname='DEMO' AND matric_no ~ '^MOAUM/[A-Z]{2,6}/[0-9]{2}/990[1-6]$'").query(Long.class).single();
        long demoCourses = jdbc.sql("SELECT count(*) FROM catalogue.course WHERE code LIKE 'DMO %' OR code LIKE 'DMC %' OR title ILIKE 'Demo %'").query(Long.class).single();
        long demo = demoStudents + demoCourses;
        // ── V402/V405/V413: the code families and the classes of the running session — what an office must act on before it ──
        Map<String, Object> cf = jdbc.sql("SELECT moau_from_entry_session, stated_at FROM catalogue.code_family_setting WHERE id = 1")
                .query().listOfRows().stream().findFirst().orElse(Map.of());
        String cfFrom = cf.get("moau_from_entry_session") == null ? null : String.valueOf(cf.get("moau_from_entry_session"));
        boolean cfConfirmed = cf.get("stated_at") != null;
        checks.add(chk(RUNNING, "code_families", "BSU-/MOAU- code families stated",
                cfFrom == null ? "warn" : cfConfirmed ? "ok" : "warn",
                cfFrom == null ? "Not stated: both codes reach every student until it is."
                        : (cfConfirmed ? "" : "Seeded, not yet confirmed by an office: ") + "cohorts admitted from " + cfFrom + " register MOAU- codes; earlier cohorts BSU- until they graduate.",
                cfFrom == null || !cfConfirmed ? "Confirm or change it on All courses (BSU- and MOAU- codes)." : null));
        long mismatched = jdbc.sql("SELECT count(*) FROM catalogue.other_family_registrations(:s)").param("s", s).query(Long.class).single();
        checks.add(chk(RUNNING, "code_family_mismatches", "Registrations under the cohort's own code", mismatched == 0 ? "ok" : "warn",
                mismatched == 0 ? "No registration line of " + s + " holds the other family's code."
                        : mismatched + " registration line" + (mismatched == 1 ? "" : "s") + " of " + s + " hold" + (mismatched == 1 ? "s" : "") + " the other family's code.",
                mismatched == 0 ? null : "Move them on All courses (BSU- and MOAU- codes); a line with a score on it goes to the Examinations Office."));
        Map<String, Object> wc = jdbc.sql("""
                SELECT count(*) FILTER (WHERE w.reason = 'NO_CLASS') AS no_class, count(*) FILTER (WHERE w.reason = 'NOT_IN_STRUCTURE') AS no_structure
                  FROM ref.department d CROSS JOIN LATERAL catalogue.courses_without_class(d.code, :s) w
                 WHERE d.ended_on IS NULL
                """).param("s", s).query().singleRow();
        long noClass = ((Number) wc.get("no_class")).longValue();
        long noStructure = ((Number) wc.get("no_structure")).longValue();
        checks.add(chk(RUNNING, "classes_opened", "Every structure course has its class", noClass == 0 ? "ok" : "warn",
                (noClass == 0 ? "Every course in a programme's structure has its class in " + s + "'s opened semesters."
                        : noClass + " course" + (noClass == 1 ? " has" : "s have") + " no class in " + s + "'s opened semesters.")
                        + (noStructure > 0 ? " " + noStructure + " live course" + (noStructure == 1 ? " is" : "s are") + " in no programme's structure." : ""),
                noClass == 0 && noStructure == 0 ? null
                        : "Open the classes on the allocation desk (each department sees its own); a course in no structure is added on Department courses or in the structure upload."));

        checks.add(chk(INSTITUTION, "demo", "Demo data removed", demo == 0 ? "ok" : "warn",
                demo == 0 ? "No demo students or courses remain" : demoStudents + " demo student(s) and " + demoCourses + " demo course(s) still on the system", null));

        // ── institution-level gates (not session-scoped) ──
        Map<String, Object> gw = jdbc.sql("""
                SELECT count(*) FILTER (WHERE secret_enc IS NOT NULL) AS any,
                       count(*) FILTER (WHERE secret_enc IS NOT NULL AND mode = 'LIVE') AS live
                  FROM finance.gateway_credential
                """).query().singleRow();
        long gwAny = ((Number) gw.get("any")).longValue();
        long gwLive = ((Number) gw.get("live")).longValue();
        checks.add(chk(INSTITUTION, "gateway", "Payment gateway configured", gwLive > 0 ? "ok" : gwAny > 0 ? "warn" : "bad",
                gwLive > 0 ? "A live payment gateway key is set" : gwAny > 0 ? "Only a TEST gateway key is set — no live payments" : "No payment gateway key set — online payments cannot be taken", "/finance/gateways"));

        boolean mail = Boolean.TRUE.equals(jdbc.sql("SELECT EXISTS(SELECT 1 FROM platform.mail_settings WHERE coalesce(smtp_host,'') <> '')").query(Boolean.class).single());
        checks.add(chk(INSTITUTION, "email", "Email (SMTP) configured", mail ? "ok" : "warn",
                mail ? "Outgoing email is set up" : "No SMTP host set — receipts and notices reach applicants in-portal only, not by email", "/platform/mail"));

        boolean sms = Boolean.TRUE.equals(jdbc.sql("SELECT coalesce(bool_or(enabled AND api_key_enc IS NOT NULL), false) FROM platform.sms_settings").query(Boolean.class).single());
        checks.add(chk(INSTITUTION, "sms", "SMS configured", sms ? "ok" : "warn",
                sms ? "The SMS gateway is enabled and keyed" : "SMS is not enabled — applicants and students get no text alerts", "/platform/sms"));

        // V393: postgraduate registration, in the School of Postgraduate Studies' own session
        Map<String, Object> pg = pgReadiness();
        boolean pgReady = Boolean.TRUE.equals(pg.get("ready"));
        List<String> pgMissing = new ArrayList<>();
        String pgFix = null;   // where the first missing piece is put right
        if (!Boolean.TRUE.equals(pg.get("current"))) { pgMissing.add("no current session on the School's calendar"); pgFix = "/admissions/postgraduate/calendar"; }
        if (pg.get("semester") == null) { pgMissing.add("no semester open within its registration dates"); if (pgFix == null) pgFix = "/admissions/postgraduate/calendar"; }
        if (((Number) pg.get("classes")).longValue() == 0) { pgMissing.add("the School's classes are not set up"); if (pgFix == null) pgFix = "/admissions/postgraduate/courses"; }
        if (((Number) pg.get("unstated")).longValue() > 0) { pgMissing.add(pg.get("unstated") + " PG student(s) with no fee line stated"); if (pgFix == null) pgFix = "/finance/fees?session=" + pg.get("session"); }
        checks.add(chk(INSTITUTION, "pg_registration", "Postgraduate registration can open", pgReady ? "ok" : "warn",
                pgReady ? "The School's session " + pg.get("session") + " is ready for course registration"
                        : pg.get("session") + ": " + String.join("; ", pgMissing), pgFix));

        // V412: CCE admission, in the CCE session — blocking only where CCE is in use (a list, an open window or applications)
        Map<String, Object> cce = cceReadiness();
        String cs = String.valueOf(cce.get("session"));
        boolean cceInUse = Boolean.TRUE.equals(cce.get("inUse"));
        String cceFees = "application ₦" + naira(cce.get("applicationFee")) + ", admission checking ₦" + naira(cce.get("checkingFee"))
                + ", acceptance ₦" + naira(cce.get("acceptanceFee"));
        checks.add(chk(CCE, "cce_fees", "CCE applicant fees set", Boolean.TRUE.equals(cce.get("feesStated")) ? "ok" : cceInUse ? "bad" : "warn",
                Boolean.TRUE.equals(cce.get("feesStated")) ? "Set for " + cs + ": " + cceFees
                        : cce.get("applicationFee") == null ? "Not set for " + cs + ": CCE applicants cannot pay the application fee"
                        : !Boolean.TRUE.equals(cce.get("checkingStated")) ? "No admission checking fee set for " + cs + ": CCE applicants cannot read their published outcome"
                        : "Not set for " + cs + ": CCE applicants are charged " + cce.get("feesCarriedFrom") + "'s amounts (" + cceFees + ")",
                "/cce/fees?session=" + cs));
        long cceListed = ((Number) cce.get("listed")).longValue();
        checks.add(chk(CCE, "cce_list", "CCE list loaded", cceListed > 0 ? "ok" : "warn",
                cceListed > 0 ? String.format(java.util.Locale.ENGLISH, "%,d", cceListed) + " candidates on the CCE list for " + cs
                        : "No CCE list for " + cs + ": no CCE candidate can register", "/cce/upload?session=" + cs));
        long cceProgrammes = ((Number) cce.get("programmes")).longValue();
        checks.add(chk(CCE, "cce_programmes", "Programmes offered to CCE", cceProgrammes > 0 ? "ok" : "warn",
                cceProgrammes > 0 ? cceProgrammes + " programme(s) offered to CCE" : "No programme is offered to CCE", "/cce/programmes"));
        checks.add(chk(CCE, "cce_window", "CCE applications open", "OPEN".equals(cce.get("window")) ? "ok" : "warn",
                "OPEN".equals(cce.get("window")) ? "Open for " + cs : "The CCE application window is " + String.valueOf(cce.get("window")).toLowerCase() + " for " + cs,
                "/ict/applications?session=" + cs));

        // read live here: what was read replaces the reading the public status keeps
        this.readiness.offer(pg, cce);

        long bad = checks.stream().filter(c -> "bad".equals(c.get("status"))).count();
        long warn = checks.stream().filter(c -> "warn".equals(c.get("status"))).count();
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("session", s);              // the running session
        out.put("intakeSession", in);       // the admission exercise's
        out.put("cceSession", cce.get("session"));   // CCE's own (V412)
        out.put("ready", bad == 0);
        out.put("blocking", bad);
        out.put("warnings", warn);
        out.put("checks", checks);
        return out;
    }

    /** an amount as the readiness writes it: 25000 → 25,000 */
    private static String naira(Object amount) {
        return amount == null ? "—" : String.format(java.util.Locale.ENGLISH, "%,.0f", new java.math.BigDecimal(amount.toString()));
    }

    /** a window's date as the readiness writes it, in Lagos: 30 Nov 2026 */
    private static String day(java.time.OffsetDateTime at) {
        return at.atZoneSameInstant(java.time.ZoneId.of("Africa/Lagos"))
                .format(java.time.format.DateTimeFormatter.ofPattern("d MMM yyyy", java.util.Locale.ENGLISH));
    }

    @GetMapping("/status")
    Map<String, Object> status() {
        Map<String, Object> body = new LinkedHashMap<>();
        body.put("service", "portal-api");
        body.put("commit", commit == null || commit.isBlank() ? null : commit);
        body.put("startedAt", STARTED.toString());
        body.put("database", database());
        // the PG and CCE readiness as last read (ReadinessSnapshot): at most five minutes old, never read on every probe
        ReadinessSnapshot.Reading kept = readiness.get();
        body.put("readinessReadAt", kept == null ? null : kept.at().toString());
        // V393: whether postgraduate registration can open — the School's session and yes/no answers only, nothing personal
        try {
            Map<String, Object> pg = kept == null ? null : kept.postgraduate();
            if (pg == null) throw new IllegalStateException("the PG readiness has not been read");
            Map<String, Object> pub = new LinkedHashMap<>();
            pub.put("session", pg.get("session"));
            pub.put("current", pg.get("current"));
            pub.put("semesterOpen", pg.get("semester") != null);
            pub.put("classes", ((Number) pg.get("classes")).longValue() > 0);
            pub.put("feesStated", pg.get("feesStated"));
            pub.put("ready", pg.get("ready"));
            body.put("postgraduate", pub);
        } catch (RuntimeException e) {
            body.put("postgraduate", null);
        }
        // V412: whether CCE admission can run — the CCE session and yes/no answers only
        try {
            Map<String, Object> cce = kept == null ? null : kept.cce();
            if (cce == null) throw new IllegalStateException("the CCE readiness has not been read");
            Map<String, Object> pub = new LinkedHashMap<>();
            pub.put("session", cce.get("session"));
            pub.put("feesStated", cce.get("feesStated"));
            pub.put("checkingFeeStated", cce.get("checkingStated"));
            pub.put("listLoaded", ((Number) cce.get("listed")).longValue() > 0);
            pub.put("programmesOffered", ((Number) cce.get("programmes")).longValue() > 0);
            pub.put("windowOpen", "OPEN".equals(cce.get("window")));
            pub.put("ready", cce.get("ready"));
            body.put("cce", pub);
        } catch (RuntimeException e) {
            body.put("cce", null);
        }
        return body;
    }

    /** V412: admissions.cce_readiness(), read live */
    private Map<String, Object> cceReadiness() {
        return ReadinessSnapshot.read(jdbc, json, "admissions.cce_readiness()");
    }

    /** V393: admissions.pg_readiness(), read live */
    private Map<String, Object> pgReadiness() {
        return ReadinessSnapshot.read(jdbc, json, "admissions.pg_readiness()");
    }

    /** the migration ledger: what has been applied to this database, in order */
    @GetMapping("/migrations")
    @PreAuthorize("hasAnyAuthority('OFFICE_ict','OFFICE_admin','OFFICE_super')")
    Map<String, Object> migrations() {
        List<Map<String, Object>> rows = jdbc.sql("""
                SELECT filename, sha256, applied_at, applied_by FROM public.schema_migration ORDER BY filename
                """).query().listOfRows();
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("count", rows.size());
        out.put("latest", rows.isEmpty() ? null : rows.get(rows.size() - 1).get("filename"));
        out.put("commit", commit == null || commit.isBlank() ? null : commit);
        out.put("startedAt", STARTED.toString());
        out.put("migrations", rows);
        return out;
    }

    private Map<String, Object> database() {
        Map<String, Object> db = new LinkedHashMap<>();
        try {
            Map<String, Object> row = jdbc.sql("""
                    SELECT (SELECT count(*) FROM public.schema_migration)            AS applied,
                           (SELECT max(filename) FROM public.schema_migration)       AS latest,
                           (SELECT state FROM admissions.session_policy
                             WHERE session = '2025/2026')                            AS admission_settings
                    """).query().singleRow();
            db.put("reachable", true);
            db.put("migrationsApplied", row.get("applied"));
            db.put("latestMigration", row.get("latest"));
            db.put("admissionSettings2025_2026", row.get("admission_settings") == null ? "absent" : row.get("admission_settings"));
        } catch (DataAccessException e) {
            db.put("reachable", false);
            db.put("why", e.getMostSpecificCause().getMessage());
        }
        return db;
    }
}
