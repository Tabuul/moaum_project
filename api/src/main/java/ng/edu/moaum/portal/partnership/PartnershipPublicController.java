package ng.edu.moaum.portal.partnership;

import java.security.SecureRandom;
import java.util.Base64;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import jakarta.servlet.http.HttpServletRequest;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpHeaders;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import ng.edu.moaum.portal.shared.AuditContext;
import ng.edu.moaum.portal.shared.AuditContextHolder;
import ng.edu.moaum.portal.shared.ClientAddress;
import ng.edu.moaum.portal.shared.DomainRuleViolation;
import ng.edu.moaum.portal.shared.Throttle;

/**
 * The public collaboration enquiry (V658), under /api/v1/public (a public door: no session, no token read). A draft is reached only
 * by its unguessable private link (32 random bytes; its SHA-256 is what the database keeps), never by an id; the same link follows
 * the enquiry once submitted — its status, the University's messages and requests, the applicant's answers and documents — and
 * shows nothing internal. Every request is counted against the connection; a filled hidden field (the honeypot) is refused; the
 * answers are checked by the database on submission whatever the browser checked.
 */
@RestController
@RequestMapping("/api/v1/public/partnerships")
class PartnershipPublicController {

    private static final UUID NOBODY = new UUID(0, 0);
    private static final SecureRandom RANDOM = new SecureRandom();

    private final JdbcClient jdbc;
    private final TransactionTemplate tx;
    private final Throttle throttle;
    private final PartnershipFiles files;
    private final String portalUrl;
    private final tools.jackson.databind.ObjectMapper mapper;

    PartnershipPublicController(JdbcClient jdbc, PlatformTransactionManager transactions, Throttle throttle, PartnershipFiles files,
                                tools.jackson.databind.ObjectMapper mapper,
                                @Value("${moaum.portal-url:https://moaum-portal-production.up.railway.app}") String portalUrl) {
        this.jdbc = jdbc;
        this.mapper = mapper;
        this.tx = new TransactionTemplate(transactions);
        this.throttle = throttle;
        this.files = files;
        this.portalUrl = portalUrl == null ? "" : portalUrl.replaceAll("/+$", "");
    }

    private static String newToken() {
        byte[] b = new byte[32];
        RANDOM.nextBytes(b);
        return Base64.getUrlEncoder().withoutPadding().encodeToString(b);
    }

    private static void honeypot(String hp) {
        if (hp != null && !hp.isBlank()) {
            throw new DomainRuleViolation("PTN_REFUSED", "The enquiry could not be accepted.",
                    new DomainRuleViolation.Remedy("Reload the page and fill in the form again.", "Directorate of Linkages & Partnerships"));
        }
    }

    private <T> T asPublic(String why, java.util.function.Supplier<T> work) {
        return AuditContextHolder.with(new AuditContext(NOBODY, "applicant", why, null, null), () -> tx.execute(st -> work.get()));
    }

    private Map<String, Object> links(String token) {
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("STATUS_URL", portalUrl + "/partnerships/status/" + token);
        m.put("PRIVACY_URL", portalUrl + "/privacy-policy");
        return m;
    }

    private String json(Object o) {
        try {
            return mapper.writeValueAsString(o == null ? Map.of() : o);
        } catch (RuntimeException e) {
            throw new DomainRuleViolation("PTN_ANSWER", "The answers could not be read.", new DomainRuleViolation.Remedy("Reload the page and try again.", "You"));
        }
    }

    /* ── what the form offers ── */

    @GetMapping("/options")
    Map<String, Object> options() {
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("settings", jdbc.sql("""
                SELECT public_open, acknowledge_days, screening_days, review_days, complex_review_days, info_days, summary_max, text_max, benefits_max,
                       max_files, max_file_mb, draft_days, contact_email, contact_phone
                  FROM partnership.setting WHERE id = 1
                """).query().singleRow());
        out.put("groups", jdbc.sql("SELECT code, label FROM partnership.category_group WHERE active ORDER BY sort, label").query().listOfRows());
        out.put("categories", jdbc.sql("""
                SELECT c.code, c.grp, c.label FROM partnership.category c JOIN partnership.category_group g ON g.code = c.grp AND g.active
                 WHERE c.active ORDER BY g.sort, c.sort, c.label
                """).query().listOfRows());
        out.put("faculties", jdbc.sql("SELECT code, name FROM ref.faculty ORDER BY name").query().listOfRows());
        out.put("departments", jdbc.sql("SELECT code, name, faculty_code FROM ref.department WHERE ended_on IS NULL ORDER BY name").query().listOfRows());
        out.put("privacyPublished", jdbc.sql("SELECT EXISTS (SELECT 1 FROM platform.legal_document WHERE kind = 'PRIVACY_POLICY' AND status = 'PUBLISHED')")
                .query(Boolean.class).single());
        return out;
    }

    /* ── the draft, by its private link ── */

    public record DraftIn(Map<String, Object> answers, @Size(max = 200) String website2) {
    }

    @PostMapping("/drafts")
    Map<String, Object> create(@RequestBody(required = false) DraftIn body, HttpServletRequest request) {
        throttle.take(Throttle.Door.PARTNERSHIP_FORM, ClientAddress.of(request));
        honeypot(body == null ? null : body.website2());
        String token = newToken();
        UUID id = asPublic("collaboration enquiry: a draft made",
                () -> jdbc.sql("SELECT partnership.draft_create(:t, CAST(:a AS jsonb))").param("t", token).param("a", json(body == null ? null : body.answers()))
                        .query(UUID.class).single());
        return Map.of("token", token, "saved", id != null);
    }

    private UUID draft(String token) {
        return jdbc.sql("SELECT partnership.draft_id(:t)").param("t", token).query(UUID.class).single();
    }

    @GetMapping("/drafts/{token}")
    Map<String, Object> read(@PathVariable String token, HttpServletRequest request) {
        throttle.take(Throttle.Door.PARTNERSHIP_FORM, ClientAddress.of(request));
        UUID id = draft(token);
        Map<String, Object> p = jdbc.sql("""
                SELECT status, reference, first_name, last_name, job_title, org_name, org_type, org_type_other, email, phone, country, city, address, website,
                       profile_url, language, contact_method, time_zone, proposal_kind, previous_reference, has_contact, contact_name, contact_unit, contact_email,
                       collaborated_before, previous_collaboration, category, secondary_category, title, summary, description, objectives, activities,
                       expected_results, why_university, faculty_code, dept_code, unit_text, expertise, staff_contact, start_date::text AS start_date, duration,
                       collaboration_format, benefits_university, benefits_partner, funding_status, budget::text AS budget, currency, funder, joint_grant,
                       funding_deadline::text AS funding_deadline, resources_requested, resources_other, partner_contribution, international, countries,
                       international_aspects, agreement_types, personal_data, sensitive_data, sensitive_kinds, ethics, high_risk::text AS high_risk, coi, coi_detail,
                       own_due_diligence, consent_marketing
                  FROM partnership.proposal WHERE id = :id
                """).param("id", id).query().singleRow();
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("submitted", !"DRAFT".equals(p.get("status")));
        out.put("reference", p.get("reference"));
        out.put("answers", p);
        out.put("attachments", files.list(id, true));
        return out;
    }

    @PutMapping("/drafts/{token}")
    Map<String, Object> save(@PathVariable String token, @RequestBody DraftIn body, HttpServletRequest request) {
        throttle.take(Throttle.Door.PARTNERSHIP_FORM, ClientAddress.of(request));
        honeypot(body.website2());
        asPublic("collaboration enquiry: a draft saved",
                () -> jdbc.sql("SELECT partnership.draft_save(:t, CAST(:a AS jsonb))").param("t", token).param("a", json(body.answers())).query(UUID.class).single());
        return Map.of("saved", true);
    }

    /** the answers saved and every problem with them, field by field (the form's error summary reads it) */
    @PostMapping("/drafts/{token}/check")
    Map<String, Object> check(@PathVariable String token, @RequestBody DraftIn body, HttpServletRequest request) {
        throttle.take(Throttle.Door.PARTNERSHIP_FORM, ClientAddress.of(request));
        honeypot(body.website2());
        List<Map<String, Object>> problems = asPublic("collaboration enquiry: a draft checked", () -> {
            UUID id = jdbc.sql("SELECT partnership.draft_save(:t, CAST(:a AS jsonb))").param("t", token).param("a", json(body.answers())).query(UUID.class).single();
            return jdbc.sql("SELECT step, field, message FROM partnership.problems(:id)").param("id", id).query().listOfRows();
        });
        return Map.of("problems", problems);
    }

    public record FileIn(@NotBlank @Size(max = 40) String kind, @NotBlank @Size(max = 200) String filename, @NotBlank String dataUrl) {
    }

    @PostMapping("/drafts/{token}/attachments")
    Map<String, Object> attach(@PathVariable String token, @Valid @RequestBody FileIn body, HttpServletRequest request) {
        throttle.take(Throttle.Door.PARTNERSHIP_FORM, ClientAddress.of(request));
        UUID id = draft(token);
        String status = jdbc.sql("SELECT status FROM partnership.proposal WHERE id = :id").param("id", id).query(String.class).single();
        if (!"DRAFT".equals(status)) {
            throw new DomainRuleViolation("PTN_SUBMITTED", "This enquiry has been submitted; add documents from its status page.",
                    new DomainRuleViolation.Remedy("Open the private link in your acknowledgement e-mail.", "You"));
        }
        if ("REQUESTED_DOCUMENT".equalsIgnoreCase(body.kind()) || "AGREEMENT".equalsIgnoreCase(body.kind()) || "INTERNAL".equalsIgnoreCase(body.kind())) {
            throw new DomainRuleViolation("PTN_FILE_KIND", "Attachment: choose what the document is (concept note, proposal, profile …).",
                    new DomainRuleViolation.Remedy("Pick one of the kinds the form lists.", "You"));
        }
        PartnershipFiles.Decoded f = files.decode(body.filename(), body.dataUrl());
        asPublic("collaboration enquiry: a document attached", () -> files.keep(id, body.kind(), f, true, null, null));
        return Map.of("attachments", files.list(id, true));
    }

    @DeleteMapping("/drafts/{token}/attachments/{attachment}")
    Map<String, Object> detach(@PathVariable String token, @PathVariable UUID attachment, HttpServletRequest request) {
        throttle.take(Throttle.Door.PARTNERSHIP_FORM, ClientAddress.of(request));
        UUID id = draft(token);
        asPublic("collaboration enquiry: a document removed", () -> jdbc.sql("""
                DELETE FROM partnership.attachment a USING partnership.proposal p
                 WHERE a.id = :a AND a.proposal_id = :p AND p.id = a.proposal_id AND p.status = 'DRAFT'
                """).param("a", attachment).param("p", id).update());
        return Map.of("attachments", files.list(id, true));
    }

    public record SubmitIn(Map<String, Object> answers, @Size(max = 200) String website2) {
    }

    /** submitted: checked again by the database, the reference issued, the applicant acknowledged; the same link a second time answers the same */
    @PostMapping("/drafts/{token}/submit")
    Map<String, Object> submit(@PathVariable String token, @RequestBody SubmitIn body, HttpServletRequest request) {
        throttle.take(Throttle.Door.PARTNERSHIP_FORM, ClientAddress.of(request));
        honeypot(body.website2());
        Map<String, Object> r = asPublic("collaboration enquiry submitted", () -> jdbc.sql("SELECT * FROM partnership.submit(:t, CAST(:a AS jsonb), CAST(:l AS jsonb))")
                .param("t", token).param("a", body.answers() == null ? null : json(body.answers())).param("l", json(links(token))).query().singleRow());
        Map<String, Object> out = new LinkedHashMap<>(r);
        out.remove("id");
        out.put("statusPath", "/partnerships/status/" + token);
        return out;
    }

    /* ── the submitted enquiry, followed by its private link ── */

    @GetMapping("/status/{token}")
    ResponseEntity<Map<String, Object>> status(@PathVariable String token, HttpServletRequest request) {
        throttle.take(Throttle.Door.PARTNERSHIP_STATUS, ClientAddress.of(request));
        UUID id = draft(token);
        Map<String, Object> p = jdbc.sql("""
                SELECT p.reference, p.title, p.org_name, p.status, partnership.public_status(p.status) AS status_words, p.received_at, p.email,
                       (SELECT c.label FROM partnership.category c WHERE c.code = p.category) AS category,
                       partnership.terminal(p.status) AS closed
                  FROM partnership.proposal p WHERE p.id = :id
                """).param("id", id).query().singleRow();
        if ("DRAFT".equals(p.get("status"))) {
            throw new DomainRuleViolation("PTN_DRAFT", "This enquiry has not been submitted yet.",
                    new DomainRuleViolation.Remedy("Continue it on the collaboration form with the same link.", "You"));
        }
        Map<String, Object> out = new LinkedHashMap<>(p);
        out.remove("status");
        out.put("timeline", jdbc.sql("""
                SELECT e.at, e.action, partnership.public_status(e.to_status) AS to_words
                  FROM partnership.event e WHERE e.proposal_id = :id AND e.applicant_visible ORDER BY e.at
                """).param("id", id).query().listOfRows());
        out.put("messages", jdbc.sql("""
                SELECT m.kind, m.body, m.at FROM partnership.message m WHERE m.proposal_id = :id AND m.kind IN ('APPLICANT_MESSAGE', 'APPLICANT_REPLY') ORDER BY m.at
                """).param("id", id).query().listOfRows());
        out.put("request", jdbc.sql("""
                SELECT r.question, r.documents, r.deadline FROM partnership.info_request r
                 WHERE r.proposal_id = :id AND r.answered_at IS NULL AND r.withdrawn_at IS NULL
                """).param("id", id).query().listOfRows().stream().findFirst().orElse(null));
        out.put("attachments", files.list(id, true));
        out.put("maxFileMb", jdbc.sql("SELECT max_file_mb FROM partnership.setting WHERE id = 1").query(Integer.class).single());
        return ResponseEntity.ok().header(HttpHeaders.CACHE_CONTROL, "no-store").body(out);
    }

    public record ReplyIn(@NotBlank @Size(max = 8000) String answer) {
    }

    @PostMapping("/status/{token}/reply")
    Map<String, Object> reply(@PathVariable String token, @Valid @RequestBody ReplyIn body, HttpServletRequest request) {
        throttle.take(Throttle.Door.PARTNERSHIP_FORM, ClientAddress.of(request));
        String to = asPublic("collaboration enquiry: the applicant answered a request",
                () -> jdbc.sql("SELECT partnership.answer_request(:t, :a)").param("t", token).param("a", body.answer()).query(String.class).single());
        return Map.of("answered", true, "status", to);
    }

    @PostMapping("/status/{token}/attachments")
    Map<String, Object> addDocument(@PathVariable String token, @Valid @RequestBody FileIn body, HttpServletRequest request) {
        throttle.take(Throttle.Door.PARTNERSHIP_FORM, ClientAddress.of(request));
        UUID id = draft(token);
        Map<String, Object> p = jdbc.sql("""
                SELECT p.status, (SELECT r.id FROM partnership.info_request r WHERE r.proposal_id = p.id AND r.answered_at IS NULL AND r.withdrawn_at IS NULL) AS open_request
                  FROM partnership.proposal p WHERE p.id = :id
                """).param("id", id).query().singleRow();
        String status = String.valueOf(p.get("status"));
        if ("DRAFT".equals(status) || List.of("DECLINED", "CLOSED", "CANCELLED").contains(status)) {
            throw new DomainRuleViolation("PTN_STATUS", "Documents are added to an enquiry that is open.",
                    new DomainRuleViolation.Remedy("Contact the Directorate of Linkages & Partnerships.", "Directorate of Linkages & Partnerships"));
        }
        PartnershipFiles.Decoded f = files.decode(body.filename(), body.dataUrl());
        asPublic("collaboration enquiry: the applicant added a document", () -> {
            UUID att = files.keep(id, "REQUESTED_DOCUMENT", f, true, null, (UUID) p.get("open_request"));
            jdbc.sql("SELECT partnership.log(:p, 'DOCUMENT_ADDED', NULL, NULL, :d, true)").param("p", id).param("d", "The applicant added " + f.filename())
                    .query().listOfRows();
            return att;
        });
        return Map.of("attachments", files.list(id, true));
    }

    public record LinkIn(@NotBlank @Size(max = 40) String reference, @NotBlank @Size(max = 200) String email, @Size(max = 200) String website2) {
    }

    /** a new private link to the address the enquiry was sent from; the answer is the same whether or not they match */
    @PostMapping("/link")
    Map<String, Object> link(@Valid @RequestBody LinkIn body, HttpServletRequest request) {
        throttle.take(Throttle.Door.PARTNERSHIP_LINK, ClientAddress.of(request));
        honeypot(body.website2());
        String token = newToken();
        asPublic("collaboration enquiry: the private link sent again", () -> jdbc.sql("SELECT partnership.new_link(:r, :e, :t, CAST(:l AS jsonb))")
                .param("r", body.reference()).param("e", body.email()).param("t", token).param("l", json(links(token))).query(Boolean.class).single());
        return Map.of("sent", true);
    }
}
