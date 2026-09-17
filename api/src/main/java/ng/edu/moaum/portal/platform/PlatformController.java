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

    PlatformController(JdbcClient jdbc, tools.jackson.databind.ObjectMapper json, @Value("${moaum.commit:${RAILWAY_GIT_COMMIT_SHA:}}") String commit) {
        this.jdbc = jdbc;
        this.json = json;
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

    private static Map<String, Object> chk(String key, String label, String status, String detail, String fix) {
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("key", key);
        m.put("label", label);
        m.put("status", status);   // ok | warn | bad
        m.put("detail", detail);
        m.put("fix", fix);
        return m;
    }

    /** Go-live readiness for a session: each configuration gate that silently blocks part of launch,
     *  checked live, so it is a screen and not a manual list. Read-only. */
    @GetMapping("/readiness")
    @PreAuthorize("hasAnyAuthority('OFFICE_super','OFFICE_ict','OFFICE_admin','OFFICE_registrar','OFFICE_dregistrar','OFFICE_academic','OFFICE_bursar')")
    @Transactional(readOnly = true)
    Map<String, Object> readiness(@RequestParam(required = false) String session) {
        String s = session != null && session.matches("\\d{4}/\\d{4}") ? session : "2026/2027";
        List<Map<String, Object>> checks = new ArrayList<>();

        boolean fee = Boolean.TRUE.equals(jdbc.sql("SELECT stated FROM admissions.applicant_fee_rule(:s)").param("s", s).query(Boolean.class).single());
        checks.add(chk("applicant_fee", "Applicant fee set", fee ? "ok" : "bad",
                fee ? "Application, portal and acceptance fees are stated for " + s : "Not stated for " + s + " — receipts use fallback amounts", "/admissions/settings"));

        boolean policy = Boolean.TRUE.equals(jdbc.sql("SELECT EXISTS(SELECT 1 FROM admissions.session_policy WHERE session=:s AND state='IN_FORCE')").param("s", s).query(Boolean.class).single());
        checks.add(chk("admission_policy", "Admission policy in force", policy ? "ok" : "bad",
                policy ? "Weights and quota are in force for " + s : "No in-force policy for " + s + " — it is still a draft", "/admissions/settings"));

        String sesState = jdbc.sql("SELECT state FROM policy.academic_session WHERE name=:s").param("s", s).query(String.class).optional().orElse(null);
        checks.add(chk("session", "Session on the calendar", sesState == null ? "bad" : "CURRENT".equals(sesState) ? "ok" : "warn",
                sesState == null ? s + " is not on the calendar" : s + " is " + sesState.toLowerCase(), "/calendar"));

        List<Integer> open = jdbc.sql("SELECT number FROM policy.semester WHERE session=:s AND state='OPEN' ORDER BY number").param("s", s).query(Integer.class).list();
        checks.add(chk("semester", "A semester is open", open.isEmpty() ? "warn" : "ok",
                open.isEmpty() ? "No semester is open for " + s + " — students cannot register" : "Semester " + open.stream().map(String::valueOf).reduce((a, b) -> a + " and " + b).orElse("") + " open", "/calendar"));

        boolean feeSchedule = Boolean.TRUE.equals(jdbc.sql("SELECT EXISTS(SELECT 1 FROM finance.fee_schedule WHERE session=:s AND ended_at IS NULL)").param("s", s).query(Boolean.class).single());
        checks.add(chk("fee_schedule", "School-fee schedule set", feeSchedule ? "ok" : "bad",
                feeSchedule ? "A current fee schedule exists for " + s : "No fee schedule for " + s + " — students cannot pay or register", "/finance/fees"));

        boolean clearance = Boolean.TRUE.equals(jdbc.sql("SELECT policy.in_force('clearance','UNIVERSITY',current_date) IS NOT NULL").query(Boolean.class).single());
        checks.add(chk("clearance", "Clearance scheme in force", clearance ? "ok" : "warn",
                clearance ? "A clearance scheme is in force" : "No clearance scheme in force — clearance cannot run", "/clearance"));

        long demoStudents = jdbc.sql("SELECT count(*) FROM people.student WHERE surname='DEMO' AND matric_no ~ '^MOAUM/[A-Z]{2,6}/[0-9]{2}/990[1-6]$'").query(Long.class).single();
        long demoCourses = jdbc.sql("SELECT count(*) FROM catalogue.course WHERE code LIKE 'DMO %' OR code LIKE 'DMC %' OR title ILIKE 'Demo %'").query(Long.class).single();
        long demo = demoStudents + demoCourses;
        checks.add(chk("demo", "Demo data removed", demo == 0 ? "ok" : "warn",
                demo == 0 ? "No demo students or courses remain" : demoStudents + " demo student(s) and " + demoCourses + " demo course(s) still on the system", null));

        long examProg = jdbc.sql("SELECT count(*) FROM admissions.screening_exam_programme WHERE session=:s").param("s", s).query(Long.class).single();
        checks.add(chk("exam_programmes", "Exam-screened programmes set", "ok",
                examProg + " programme(s) screened by Post-UTME examination for " + s + " — the rest screen on O'Level", "/admissions/settings"));

        long bad = checks.stream().filter(c -> "bad".equals(c.get("status"))).count();
        long warn = checks.stream().filter(c -> "warn".equals(c.get("status"))).count();
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("session", s);
        out.put("ready", bad == 0);
        out.put("blocking", bad);
        out.put("warnings", warn);
        out.put("checks", checks);
        return out;
    }

    @GetMapping("/status")
    Map<String, Object> status() {
        Map<String, Object> body = new LinkedHashMap<>();
        body.put("service", "portal-api");
        body.put("commit", commit == null || commit.isBlank() ? null : commit);
        body.put("startedAt", STARTED.toString());
        body.put("database", database());
        return body;
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
