package ng.edu.moaum.portal.platform;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;
import java.sql.Types;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import ng.edu.moaum.portal.shared.AuditContext;
import ng.edu.moaum.portal.shared.AuditContextHolder;
import ng.edu.moaum.portal.shared.DomainRuleViolation;
import ng.edu.moaum.portal.shared.NotFound;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * V426: a message to many — the NEW PORTAL MIGRATION welcome, an announcement to a faculty, a department, a level, a session,
 * the staff or the applicants. The recipients are read from the record by the filters the office sets, never typed; a preview
 * counts them and their addresses; a test goes to one address; the send is a notification job the scheduler drains in batches,
 * once per person and channel; a report counts what went. The database holds the office rule (ICT, the administrators, the
 * Registry, Student Affairs and the Academic Office address anyone; a Dean or Head their own students only).
 */
@RestController
@RequestMapping("/api/v1/notices/campaigns")
@PreAuthorize("hasAnyAuthority('OFFICE_ict','OFFICE_admin','OFFICE_super','OFFICE_registrar','OFFICE_dregistrar','OFFICE_dsa','OFFICE_academic','OFFICE_dean','OFFICE_facultyofficer','OFFICE_hod')")
class CampaignsController {

    private final JdbcClient jdbc;

    CampaignsController(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    private static final String ROW = """
            SELECT c.id, c.name, c.template_key, t.label AS template_label, c.audience::text AS audience, c.channels, c.vars::text AS vars, c.state,
                   c.created_at, c.created_office, c.sent_at, c.sent_office, c.finished_at, c.cancelled_at, c.cancel_reason, c.recipients, c.job_id,
                   j.state AS job_state, j.reached, j.queued AS job_queued, j.runs, j.error AS job_error,
                   (SELECT count(*) FROM platform.notice n WHERE n.event_key = 'campaign:' || c.id) AS messages,
                   (SELECT count(*) FROM platform.notice n WHERE n.event_key = 'campaign:' || c.id AND n.state = 'SENT') AS messages_sent,
                   (SELECT count(*) FROM platform.notice n WHERE n.event_key = 'campaign:' || c.id AND n.state = 'FAILED') AS messages_failed
              FROM platform.notice_campaign c
              JOIN platform.notice_template t ON t.key = c.template_key
              LEFT JOIN platform.notice_job j ON j.id = c.job_id
            """;

    @GetMapping
    @Transactional(readOnly = true)
    Map<String, Object> list() {
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("campaigns", jdbc.sql(ROW + " ORDER BY c.created_at DESC LIMIT 100").query().listOfRows());
        out.put("delivery", jdbc.sql("SELECT * FROM platform.delivery()").query().singleRow());   // V438: a campaign sent with delivery off waits
        out.put("templates", jdbc.sql("SELECT key, label, purpose, mandatory, email_body IS NOT NULL AS email, sms_body IS NOT NULL AS sms, portal_body IS NOT NULL AS portal FROM platform.notice_template WHERE enabled ORDER BY key").query().listOfRows());
        out.put("faculties", jdbc.sql("SELECT code, name FROM ref.faculty ORDER BY name").query().listOfRows());
        out.put("departments", jdbc.sql("SELECT code, name, faculty_code FROM ref.department WHERE ended_on IS NULL ORDER BY name").query().listOfRows());
        out.put("programmes", jdbc.sql("SELECT code, name, dept_code, faculty_code FROM ref.programme WHERE NOT coalesce(archived, false) ORDER BY name").query().listOfRows());
        out.put("sessions", jdbc.sql("SELECT name, state FROM policy.academic_session WHERE state IN ('CURRENT', 'PLANNED', 'CLOSED') ORDER BY name DESC LIMIT 8").query().listOfRows());
        out.put("offices", jdbc.sql("SELECT code, label FROM ref.office WHERE code NOT IN ('student', 'applicant') ORDER BY label").query().listOfRows());
        return out;
    }

    @GetMapping("/{id}")
    @Transactional(readOnly = true)
    Map<String, Object> one(@PathVariable UUID id) {
        Map<String, Object> row = jdbc.sql(ROW + " WHERE c.id = :id").param("id", id).query().listOfRows().stream().findFirst()
                .orElseThrow(() -> new NotFound("campaign", id));
        Map<String, Object> out = new LinkedHashMap<>(row);
        out.put("report", jdbc.sql("SELECT * FROM platform.campaign_report(:id)").param("id", id).query().listOfRows());
        return out;
    }

    record CampaignIn(@NotBlank @Size(max = 160) String name, @NotBlank @Size(max = 80) String templateKey,
                      Boolean students, Boolean staff, Boolean lecturers, Boolean applicants,
                      Map<String, Object> filters, List<String> channels, Map<String, Object> vars) {
    }

    @PostMapping
    @Transactional
    Map<String, Object> create(@Valid @RequestBody CampaignIn in) {
        return one(save(null, in));
    }

    @PutMapping("/{id}")
    @Transactional
    Map<String, Object> update(@PathVariable UUID id, @Valid @RequestBody CampaignIn in) {
        return one(save(id, in));
    }

    private UUID save(UUID id, CampaignIn in) {
        AuditContext ctx = AuditContextHolder.required();
        Map<String, Object> audience = new LinkedHashMap<>();
        audience.put("students", Boolean.TRUE.equals(in.students()));
        audience.put("staff", Boolean.TRUE.equals(in.staff()));
        audience.put("lecturers", Boolean.TRUE.equals(in.lecturers()));
        audience.put("applicants", Boolean.TRUE.equals(in.applicants()));
        Map<String, Object> filters = new LinkedHashMap<>();
        if (in.filters() != null) {
            in.filters().forEach((k, v) -> {
                if (v == null) {
                    return;
                }
                String s = String.valueOf(v).trim();
                if (s.isEmpty() || "false".equals(s)) {
                    return;
                }
                filters.put(k, v instanceof Boolean ? v : s);
            });
        }
        audience.put("filters", filters);
        String[] channels = in.channels() == null ? new String[0] : in.channels().stream().map(c -> c.trim().toUpperCase()).filter(c -> !c.isEmpty()).toArray(String[]::new);
        Map<String, Object> vars = new LinkedHashMap<>();
        if (in.vars() != null) {
            in.vars().forEach((k, v) -> {
                if (v != null && !String.valueOf(v).isBlank()) {
                    vars.put(k.trim().toUpperCase(), String.valueOf(v));
                }
            });
        }
        return jdbc.sql("SELECT platform.campaign_save(:id, :name, :t, :a::jsonb, :ch, :v::jsonb, :by, :office)")
                .param("id", id, Types.OTHER).param("name", in.name()).param("t", in.templateKey().trim().toUpperCase())
                .param("a", NoticeTemplatesController.jsonObject(audience)).param("ch", channels).param("v", NoticeTemplatesController.json(vars))
                .param("by", ctx.actorId(), Types.OTHER).param("office", ctx.actorOffice(), Types.VARCHAR)
                .query(UUID.class).single();
    }

    /** who the campaign would reach, by kind, with the addresses that are good, bad or missing, and who was already reached */
    @PostMapping("/{id}/preview")
    @Transactional(readOnly = true)
    Map<String, Object> preview(@PathVariable UUID id) {
        List<Map<String, Object>> rows = jdbc.sql("SELECT * FROM platform.campaign_preview(:id)").param("id", id).query().listOfRows();
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("kinds", rows);
        out.put("total", rows.stream().mapToLong(r -> ((Number) r.get("total")).longValue()).sum());
        out.put("emailOk", rows.stream().mapToLong(r -> ((Number) r.get("email_ok")).longValue()).sum());
        out.put("emailBad", rows.stream().mapToLong(r -> ((Number) r.get("email_bad")).longValue()).sum());
        out.put("emailMissing", rows.stream().mapToLong(r -> ((Number) r.get("email_missing")).longValue()).sum());
        out.put("phoneOk", rows.stream().mapToLong(r -> ((Number) r.get("phone_ok")).longValue()).sum());
        out.put("phoneBad", rows.stream().mapToLong(r -> ((Number) r.get("phone_bad")).longValue()).sum());
        out.put("phoneMissing", rows.stream().mapToLong(r -> ((Number) r.get("phone_missing")).longValue()).sum());
        out.put("already", rows.stream().mapToLong(r -> ((Number) r.get("already")).longValue()).sum());
        // V444: what the SMS will cost — pages each, times the recipients with a usable phone — against the balance last read
        int phones = (int) Math.min(Integer.MAX_VALUE, rows.stream().mapToLong(r -> ((Number) r.get("phone_ok")).longValue()).sum());
        out.put("sms", jdbc.sql("SELECT * FROM platform.campaign_sms_cost(:id, :n)").param("id", id).param("n", phones).query().listOfRows()
                .stream().findFirst().orElse(null));
        return out;
    }

    record TestIn(@Size(max = 320) String email, @Size(max = 40) String phone) {
    }

    @PostMapping("/{id}/test")
    @Transactional
    Map<String, Object> test(@PathVariable UUID id, @Valid @RequestBody TestIn in) {
        boolean email = in.email() != null && !in.email().isBlank();
        boolean phone = in.phone() != null && !in.phone().isBlank();
        if (!email && !phone) {
            throw new DomainRuleViolation("CAMPAIGN_TEST_ADDRESS", "A test message goes to an e-mail address or a phone number.",
                    new DomainRuleViolation.Remedy("Give the address to send the test to.", "Directorate of ICT"));
        }
        Integer n = jdbc.sql("SELECT platform.campaign_test(:id, :e, :p)").param("id", id)
                .param("e", email ? in.email().trim() : null, Types.VARCHAR).param("p", phone ? in.phone().trim() : null, Types.VARCHAR)
                .query(Integer.class).single();
        return Map.of("queued", n == null ? 0 : n);
    }

    record SendIn(Boolean acceptShortfall) {
    }

    /** the send: a job the scheduler drains; the first batch goes now so the office sees it move. V444: refused while the SMS
     *  balance last read does not cover the campaign's SMS, unless the office accepts the shortfall */
    @PostMapping("/{id}/send")
    @Transactional
    Map<String, Object> send(@PathVariable UUID id, @RequestBody(required = false) SendIn in) {
        AuditContext ctx = AuditContextHolder.required();
        boolean accept = in != null && Boolean.TRUE.equals(in.acceptShortfall());
        UUID job = jdbc.sql("SELECT platform.campaign_send(:id, :by, :office, :accept)").param("id", id)
                .param("by", ctx.actorId(), Types.OTHER).param("office", ctx.actorOffice(), Types.VARCHAR).param("accept", accept).query(UUID.class).single();
        jdbc.sql("SELECT * FROM platform.run_notice_job(500)").query().listOfRows();
        Map<String, Object> out = new LinkedHashMap<>(one(id));
        out.put("job", job);
        return out;
    }

    record CancelIn(@Size(max = 300) String reason) {
    }

    @PostMapping("/{id}/cancel")
    @Transactional
    Map<String, Object> cancel(@PathVariable UUID id, @Valid @RequestBody(required = false) CancelIn in) {
        AuditContext ctx = AuditContextHolder.required();
        jdbc.sql("SELECT platform.campaign_cancel(:id, :r, :by, :office)").param("id", id).param("r", in == null ? null : in.reason(), Types.VARCHAR)
                .param("by", ctx.actorId(), Types.OTHER).param("office", ctx.actorOffice(), Types.VARCHAR).query().listOfRows();
        return one(id);
    }
}
