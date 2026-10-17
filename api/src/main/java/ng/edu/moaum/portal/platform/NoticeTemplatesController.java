package ng.edu.moaum.portal.platform;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;
import java.sql.Types;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import ng.edu.moaum.portal.shared.AuditContext;
import ng.edu.moaum.portal.shared.AuditContextHolder;
import ng.edu.moaum.portal.shared.DomainRuleViolation;
import ng.edu.moaum.portal.shared.FigureCache;
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
 * V425: the notification engine's desk — the templates every module's messages come from (read by ICT, the Registry and the
 * administrators; edited by ICT and the administrators), a preview with sample values, a test message to one address, the
 * engine's settings (the portal address, the job batch, the biodata reminder switch and review period) and the jobs it ran.
 * Oct 2026: the page opened slower than the edge waits (a 504 from CloudFront on portal.moaum.edu.ng/notices/templates): the
 * settings worked out the biodata counts of every student on the register while the page waited (about 10 s on the live-shaped
 * copy), and each template counted its last 30 days' notices on its own. The counts are now their own read, kept a few minutes
 * and shared (FigureCache) and loaded after the page, and the templates' notices are counted in one pass.
 */
@RestController
@RequestMapping("/api/v1/notices")
class NoticeTemplatesController {

    private static final String READERS = "hasAnyAuthority('OFFICE_ict','OFFICE_admin','OFFICE_super','OFFICE_registrar','OFFICE_dregistrar')";
    private static final String EDITORS = "hasAnyAuthority('OFFICE_ict','OFFICE_admin','OFFICE_super')";

    private final JdbcClient jdbc;
    private final FigureCache figures;

    NoticeTemplatesController(JdbcClient jdbc, FigureCache figures) {
        this.jdbc = jdbc;
        this.figures = figures;
    }

    @GetMapping("/templates")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> templates() {
        return jdbc.sql("""
                SELECT t.key, t.label, t.purpose, t.email_subject, t.email_body, t.sms_body, t.portal_title, t.portal_body, t.variables,
                       t.mandatory, t.priority, t.enabled, t.updated_at, t.updated_office, coalesce(sent.n, 0) AS sent_30d
                  FROM platform.notice_template t
                  -- the last 30 days' notices counted once for every template, not once a template
                  LEFT JOIN (SELECT n.template_key, count(*) AS n FROM platform.notice n
                              WHERE n.created_at > now() - interval '30 days' GROUP BY n.template_key) sent ON sent.template_key = t.key
                 ORDER BY CASE WHEN position(':' IN t.key) > 0 THEN split_part(t.key, ':', 1) || '~' || t.key ELSE t.key END
                """).query().listOfRows();
    }

    record TemplateIn(@NotBlank @Size(max = 120) String label, @Size(max = 600) String purpose,
                      @Size(max = 300) String emailSubject, @Size(max = 8000) String emailBody, @Size(max = 320) String smsBody,
                      @Size(max = 200) String portalTitle, @Size(max = 2000) String portalBody,
                      List<String> variables, Boolean mandatory, @Size(max = 10) String priority, Boolean enabled) {
    }

    @PutMapping("/templates/{key}")
    @PreAuthorize(EDITORS)
    @Transactional
    Map<String, Object> save(@PathVariable String key, @Valid @RequestBody TemplateIn in) {
        AuditContext ctx = AuditContextHolder.required();
        String k = key.trim().toUpperCase();
        if (!k.matches("[A-Z][A-Z0-9_]*(:[A-Z][A-Z0-9_]*)?")) {
            throw new DomainRuleViolation("NOTICE_TEMPLATE_KEY", "A template key is capital letters, digits and underscores, with an optional :VARIANT.",
                    new DomainRuleViolation.Remedy("Use a key such as WINDOW_OPENED or WINDOW_OPENED:COURSE_REGISTRATION.", "Directorate of ICT"));
        }
        String[] vars = in.variables() == null ? new String[0] : in.variables().stream().map(v -> v.trim().toUpperCase()).filter(v -> !v.isEmpty()).toArray(String[]::new);
        jdbc.sql("""
                SELECT key FROM platform.save_template(:k, :label, :purpose, :es, :eb, :sms, :pt, :pb, :vars, :mandatory, :priority, :enabled, :by, :office)
                """)
                .param("k", k).param("label", in.label()).param("purpose", in.purpose(), Types.VARCHAR)
                .param("es", in.emailSubject(), Types.VARCHAR).param("eb", in.emailBody(), Types.VARCHAR).param("sms", in.smsBody(), Types.VARCHAR)
                .param("pt", in.portalTitle(), Types.VARCHAR).param("pb", in.portalBody(), Types.VARCHAR).param("vars", vars)
                .param("mandatory", in.mandatory(), Types.BOOLEAN).param("priority", in.priority(), Types.VARCHAR).param("enabled", in.enabled(), Types.BOOLEAN)
                .param("by", ctx.actorId(), Types.OTHER).param("office", ctx.actorOffice(), Types.VARCHAR)
                .query(String.class).single();
        return templates().stream().filter(t -> k.equals(t.get("key"))).findFirst().orElse(Map.of("key", k));
    }

    /** the three texts rendered with sample values (the caller's values win over the samples) */
    @PostMapping("/templates/{key}/preview")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> preview(@PathVariable String key, @RequestBody(required = false) Map<String, Object> vars) {
        String k = key.trim().toUpperCase();
        String base = k.contains(":") ? k.substring(0, k.indexOf(':')) : k;
        String variant = k.contains(":") ? k.substring(k.indexOf(':') + 1) : null;
        Map<String, Object> out = new LinkedHashMap<>();
        for (String channel : List.of("EMAIL", "SMS", "PORTAL")) {
            out.put(channel.toLowerCase(), jdbc.sql("SELECT subject, body FROM platform.render(:k, :v, :c, :vars::jsonb)")
                    .param("k", base).param("v", variant, Types.VARCHAR).param("c", channel).param("vars", json(sample(vars, currentSession())))
                    .query().listOfRows().stream().findFirst().orElse(null));
        }
        return out;
    }

    record TestIn(@Size(max = 320) String email, @Size(max = 40) String phone, Map<String, Object> vars) {
    }

    /** the template sent to one address, as a real message through the outbox; nothing is recorded against any student */
    @PostMapping("/templates/{key}/test")
    @PreAuthorize(EDITORS)
    @Transactional
    Map<String, Object> test(@PathVariable String key, @Valid @RequestBody TestIn in) {
        String k = key.trim().toUpperCase();
        String base = k.contains(":") ? k.substring(0, k.indexOf(':')) : k;
        String variant = k.contains(":") ? k.substring(k.indexOf(':') + 1) : null;
        boolean email = in.email() != null && !in.email().isBlank();
        boolean phone = in.phone() != null && !in.phone().isBlank();
        if (!email && !phone) {
            throw new DomainRuleViolation("NOTICE_TEST_ADDRESS", "A test message goes to an e-mail address or a phone number.",
                    new DomainRuleViolation.Remedy("Give the address to send the test to.", "Directorate of ICT"));
        }
        Integer n = jdbc.sql("SELECT platform.notify(:k, :v, :vars::jsonb, 'test', NULL, :e, :p, NULL)")
                .param("k", base).param("v", variant, Types.VARCHAR).param("vars", json(sample(in.vars(), currentSession())))
                .param("e", email ? in.email().trim() : null, Types.VARCHAR).param("p", phone ? in.phone().trim() : null, Types.VARCHAR)
                .query(Integer.class).single();
        return Map.of("queued", n == null ? 0 : n);
    }

    /** the preview names the University's current session, never a year written here */
    private String currentSession() {
        return jdbc.sql("SELECT policy.university_current_session()").query(String.class).optional().orElse("");
    }

    private static Map<String, Object> sample(Map<String, Object> given, String session) {
        Map<String, Object> v = new LinkedHashMap<>();
        v.put("FIRST_NAME", "Adaeze");
        v.put("LAST_NAME", "Okafor");
        v.put("FULL_NAME", "Okafor, Adaeze Chioma");
        v.put("MATRIC_NUMBER", "MOAUM/SC/23/1234");
        v.put("JAMB_NUMBER", "23456789AB");
        v.put("LOGIN_ID", "MOAUM/SC/23/1234");
        v.put("STAFF_NUMBER", "PF/1234");
        v.put("PROGRAMME", "B.Sc. Computer Science");
        v.put("DEPARTMENT", "Computer Science");
        v.put("FACULTY", "Science");
        v.put("LEVEL", "200");
        v.put("SESSION", session);
        v.put("SEMESTER", ", semester 1");
        v.put("WINDOW", "Course registration");
        v.put("END_DATE", "30 November 2026 23:59");
        v.put("CLOSES_NOTE", "It closes on 30 November 2026 23:59.");
        v.put("LATE_NOTE", "");
        v.put("PHASE_NOTE", "");
        v.put("REASON", "");
        v.put("STATUS_NOTE", "2 required items still missing: Mobile number, Next of kin name.");
        v.put("FIELD_LIST", "Mobile number, Next of kin name");
        v.put("MISSING_COUNT", "2");
        v.put("TITLE", "Resumption date");
        v.put("MESSAGE", "The University resumes on Monday 5 January 2027.");
        v.put("SMS_MESSAGE", "The University resumes on Monday 5 January 2027.");
        v.put("SIGNATURE", "Office of the Registrar");
        if (given != null) {
            given.forEach((key, value) -> {
                if (value != null && !String.valueOf(value).isBlank()) {
                    v.put(key.trim().toUpperCase(), String.valueOf(value));
                }
            });
        }
        return v;
    }

    /* ── the engine's settings ── */

    @GetMapping("/settings")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> settings() {
        Map<String, Object> out = new LinkedHashMap<>(jdbc.sql("SELECT portal_url, job_batch, staff_contact_remind, closing_reminders, updated_at, updated_office FROM platform.notice_setting WHERE id").query().singleRow());
        out.putAll(jdbc.sql("""
                SELECT b.remind_enabled, b.review_days, b.updated_at AS biodata_updated_at,
                       coalesce((SELECT enabled FROM people.biodata_gate LIMIT 1), false) AS gate_enabled
                  FROM people.biodata_setting b WHERE b.id
                """).query().singleRow());
        return out;
    }

    /** the register's biodata counts — every student's status worked out, about 10 s on the live-shaped copy — kept a few minutes
     *  and shared (FigureCache), with when they were counted; the page asks for them after it opens */
    @GetMapping("/settings/counts")
    @PreAuthorize(READERS)
    Map<String, Object> counts(@RequestParam(defaultValue = "false") boolean refresh) {
        FigureCache.Answer<Map<String, Object>> a = figures.get("biodata-status-counts", refresh,
                () -> jdbc.sql("SELECT * FROM people.biodata_status_counts()").query().singleRow());
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("counts", a.value());
        out.put("computedAt", a.at());
        out.put("refreshing", a.refreshing());
        return out;
    }

    record SettingsIn(@Size(max = 300) String portalUrl, Integer jobBatch, Boolean remindEnabled, Integer reviewDays, Boolean staffContactRemind,
                      Boolean closingReminders) {
    }

    @PutMapping("/settings")
    @PreAuthorize(EDITORS)
    @Transactional
    Map<String, Object> saveSettings(@Valid @RequestBody SettingsIn in) {
        AuditContext ctx = AuditContextHolder.required();
        if (in.staffContactRemind() != null) {
            jdbc.sql("UPDATE platform.notice_setting SET staff_contact_remind = :on, updated_by = :by, updated_office = :office, updated_at = now() WHERE id")
                    .param("on", in.staffContactRemind()).param("by", ctx.actorId(), Types.OTHER).param("office", ctx.actorOffice(), Types.VARCHAR).update();
        }
        if (in.closingReminders() != null) {
            jdbc.sql("UPDATE platform.notice_setting SET closing_reminders = :on, updated_by = :by, updated_office = :office, updated_at = now() WHERE id")
                    .param("on", in.closingReminders()).param("by", ctx.actorId(), Types.OTHER).param("office", ctx.actorOffice(), Types.VARCHAR).update();
        }
        if (in.portalUrl() != null) {
            jdbc.sql("SELECT platform.set_portal_url(:u, :by, :office)").param("u", in.portalUrl(), Types.VARCHAR)
                    .param("by", ctx.actorId(), Types.OTHER).param("office", ctx.actorOffice(), Types.VARCHAR).query().listOfRows();
        }
        if (in.jobBatch() != null) {
            if (in.jobBatch() < 100 || in.jobBatch() > 20000) {
                throw new DomainRuleViolation("NOTICE_JOB_BATCH", "A job reaches between 100 and 20,000 people a run.",
                        new DomainRuleViolation.Remedy("Choose a batch in that range.", "Directorate of ICT"));
            }
            jdbc.sql("UPDATE platform.notice_setting SET job_batch = :b, updated_by = :by, updated_office = :office, updated_at = now() WHERE id")
                    .param("b", in.jobBatch()).param("by", ctx.actorId(), Types.OTHER).param("office", ctx.actorOffice(), Types.VARCHAR).update();
        }
        if (in.remindEnabled() != null || in.reviewDays() != null) {
            Map<String, Object> cur = jdbc.sql("SELECT remind_enabled, review_days FROM people.biodata_setting WHERE id").query().singleRow();
            jdbc.sql("SELECT people.set_biodata_setting(:r, :d, :by, :office)")
                    .param("r", in.remindEnabled() == null ? cur.get("remind_enabled") : in.remindEnabled(), Types.BOOLEAN)
                    .param("d", in.reviewDays() == null ? cur.get("review_days") : (in.reviewDays() <= 0 ? null : in.reviewDays()), Types.INTEGER)
                    .param("by", ctx.actorId(), Types.OTHER).param("office", ctx.actorOffice(), Types.VARCHAR).query().listOfRows();
        }
        return settings();
    }

    /** the jobs the engine ran or is running: what, for whom, how far */
    @GetMapping("/jobs")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> jobs() {
        return jdbc.sql("""
                SELECT j.id, j.kind, j.payload::text AS payload, j.state, j.created_at, j.created_office, j.started_at, j.finished_at, j.reached, j.queued, j.runs, j.error
                  FROM platform.notice_job j ORDER BY j.created_at DESC LIMIT 100
                """).query().listOfRows();
    }

    /** V430: the weekly staff contact reminder run now by hand (ICT): how many staff were reminded; the HR office told once a week */
    @PostMapping("/staff-contact-reminders/run")
    @PreAuthorize(EDITORS)
    @Transactional
    Map<String, Object> remindStaffNow() {
        Integer n = jdbc.sql("SELECT iam.remind_staff_contact(2000)").query(Integer.class).single();
        return Map.of("reminded", n == null ? 0 : n);
    }

    /** V438: the daily pass for the windows closing in three days or tomorrow, run now: returns the jobs queued; the scheduler drains them */
    @PostMapping("/closing-reminders/run")
    @PreAuthorize(EDITORS)
    @Transactional
    Map<String, Object> closingRemindersNow() {
        Integer n = jdbc.sql("SELECT platform.queue_closing_reminders()").query(Integer.class).single();
        return Map.of("queued", n == null ? 0 : n);
    }

    /** the weekly biodata reminder run now by hand (ICT), for the students due: returns how many were reminded */
    @PostMapping("/biodata-reminders/run")
    @PreAuthorize(EDITORS)
    @Transactional
    Map<String, Object> remindNow() {
        Integer n = jdbc.sql("SELECT people.remind_biodata(3000)").query(Integer.class).single();
        return Map.of("reminded", n == null ? 0 : n);
    }

    /** a flat JSON object of the values given: every token's value is text */
    static String json(Map<String, Object> vars) {
        StringBuilder b = new StringBuilder("{");
        boolean first = true;
        for (Map.Entry<String, Object> e : vars.entrySet()) {
            if (e.getValue() == null) {
                continue;
            }
            if (!first) {
                b.append(',');
            }
            first = false;
            b.append(quote(e.getKey())).append(':').append(quote(String.valueOf(e.getValue())));
        }
        return b.append('}').toString();
    }

    /** a JSON object of the values given, nested maps and booleans kept as such (a campaign's audience) */
    static String jsonObject(Map<String, Object> m) {
        StringBuilder b = new StringBuilder("{");
        boolean first = true;
        for (Map.Entry<String, Object> e : m.entrySet()) {
            if (!first) {
                b.append(',');
            }
            first = false;
            b.append(quote(e.getKey())).append(':').append(jsonValue(e.getValue()));
        }
        return b.append('}').toString();
    }

    @SuppressWarnings("unchecked")
    private static String jsonValue(Object v) {
        if (v == null) {
            return "null";
        }
        if (v instanceof Boolean || v instanceof Number) {
            return String.valueOf(v);
        }
        if (v instanceof Map<?, ?> m) {
            return jsonObject((Map<String, Object>) m);
        }
        if (v instanceof List<?> l) {
            StringBuilder b = new StringBuilder("[");
            for (int i = 0; i < l.size(); i++) {
                if (i > 0) {
                    b.append(',');
                }
                b.append(jsonValue(l.get(i)));
            }
            return b.append(']').toString();
        }
        return quote(String.valueOf(v));
    }

    private static final char BACKSLASH = (char) 92;

    private static String quote(String s) {
        StringBuilder b = new StringBuilder();
        b.append('"');
        for (char c : s.toCharArray()) {
            if (c == '"') {
                b.append(BACKSLASH).append('"');
            } else if (c == BACKSLASH) {
                b.append(BACKSLASH).append(BACKSLASH);
            } else if (c == (char) 10) {
                b.append(BACKSLASH).append('n');
            } else if (c == (char) 13) {
                b.append(BACKSLASH).append('r');
            } else if (c == (char) 9) {
                b.append(BACKSLASH).append('t');
            } else if (c < 0x20) {
                b.append(BACKSLASH).append('u').append(String.format("%04x", (int) c));
            } else {
                b.append(c);
            }
        }
        return b.append('"').toString();
    }
}
