package ng.edu.moaum.portal.privacy;

import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.UUID;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

import jakarta.servlet.http.HttpServletRequest;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

import ng.edu.moaum.portal.shared.AuditContext;
import ng.edu.moaum.portal.shared.AuditContextHolder;
import ng.edu.moaum.portal.shared.ClientAddress;
import ng.edu.moaum.portal.shared.DomainRuleViolation;
import ng.edu.moaum.portal.shared.NotFound;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.Authentication;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import tools.jackson.databind.ObjectMapper;

/**
 * V441 — the Privacy Policy read by anyone, accepted by each signed-in person once per version, drafted and published by
 * the Directorate of ICT or an administrator, with the privacy contact and the person's own privacy requests. The text is
 * read with the University's name, address and contacts, the privacy contact, the providers in use, the version and its
 * dates filled into its {{tokens}}, so none of those is written into the policy itself.
 */
@RestController
class PrivacyController {

    private static final String SETTERS = "hasAnyAuthority('OFFICE_ict','OFFICE_admin','OFFICE_super')";
    private static final String CONTACT_SETTERS = "hasAnyAuthority('OFFICE_ict','OFFICE_admin','OFFICE_super','OFFICE_registrar')";
    private static final String READERS = "hasAnyAuthority('OFFICE_ict','OFFICE_admin','OFFICE_super','OFFICE_registrar','OFFICE_dregistrar','OFFICE_audit','OFFICE_deputyaudit','OFFICE_vc','OFFICE_dvc')";
    private static final Map<String, String> KINDS = Map.of("privacy-policy", "PRIVACY_POLICY", "terms-of-use", "TERMS_OF_USE", "cookie-notice", "COOKIE_NOTICE");
    private static final Pattern TOKEN = Pattern.compile("\\{\\{\\s*([a-z_]+)\\s*}}");
    private static final DateTimeFormatter DAY = DateTimeFormatter.ofPattern("d MMMM uuuu", Locale.UK);

    private final PrivacyRepository repo;
    private final ObjectMapper json;
    private final boolean paystack;
    private final boolean flutterwave;
    private final boolean quickteller;
    private final String filesProvider;
    private final String filesRegion;

    PrivacyController(PrivacyRepository repo, ObjectMapper json,
                      @Value("${moaum.payments.paystack-secret:}") String paystackSecret,
                      @Value("${moaum.payments.flutterwave-secret:}") String flutterwaveSecret,
                      @Value("${moaum.payments.quickteller-config:}") String quicktellerConfig,
                      @Value("${moaum.files.provider:DB}") String filesProvider,
                      @Value("${moaum.files.region:}") String filesRegion) {
        this.repo = repo;
        this.json = json;
        this.paystack = paystackSecret != null && !paystackSecret.isBlank();
        this.flutterwave = flutterwaveSecret != null && !flutterwaveSecret.isBlank();
        this.quickteller = quicktellerConfig != null && !quicktellerConfig.isBlank();
        this.filesProvider = filesProvider == null ? "DB" : filesProvider.trim().toUpperCase(Locale.ROOT);
        this.filesRegion = filesRegion == null ? "" : filesRegion.trim();
    }

    public record Draft(@NotBlank @Size(max = 20) String kind) { }
    public record Update(@NotBlank @Size(max = 200) String title, @Size(max = 2000) String summary, @NotNull List<Map<String, Object>> sections,
                         LocalDate effectiveOn, Boolean requiresAcceptance) { }
    public record Review(@NotBlank @Size(max = 60) String key, @NotNull Boolean confirmed) { }
    public record Publish(LocalDate effectiveOn) { }
    public record Contact(@Size(max = 200) String name, @Size(max = 200) String title, @Size(max = 200) String office, @Size(max = 200) String email,
                          @Size(max = 60) String phone, @Size(max = 400) String address, Integer requestDays, @Size(max = 1000) String note) { }
    public record Accept(@NotNull UUID documentId, @Size(max = 20) String channel) { }
    public record Request(@NotBlank @Size(max = 20) String kind, @Size(max = 200) String contact, @NotBlank @Size(max = 4000) String detail) { }

    /* ── public ── */

    /** the published document of a kind, read with the University's own names in it; 404 while none is published */
    @GetMapping("/api/v1/public/legal/{kind}")
    @Transactional(readOnly = true)
    Map<String, Object> published(@PathVariable String kind) {
        String k = KINDS.get(kind.toLowerCase(Locale.ROOT));
        if (k == null) {
            throw new NotFound("legal document", kind);
        }
        Map<String, Object> doc = repo.published(k).orElseThrow(() -> new NotFound("published " + kind.replace('-', ' '), k));
        return render(doc);
    }

    /** which legal documents are published — for the links a page shows */
    @GetMapping("/api/v1/public/legal")
    @Transactional(readOnly = true)
    Map<String, Object> publishedKinds() {
        List<Map<String, Object>> rows = new ArrayList<>();
        for (Map.Entry<String, String> e : KINDS.entrySet()) {
            repo.published(e.getValue()).ifPresent(d -> rows.add(Map.of("kind", e.getKey(), "title", String.valueOf(d.get("title")),
                    "version", d.get("version"), "effectiveOn", String.valueOf(d.get("effective_on")))));
        }
        return Map.of("documents", rows);
    }

    /* ── the person's own acceptance and requests ── */

    @GetMapping("/api/v1/privacy/acceptance")
    @Transactional(readOnly = true)
    Map<String, Object> acceptance(Authentication auth) {
        String kind = subjectKind(auth);
        UUID subject = UUID.fromString(auth.getName());
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("subjectKind", kind);
        out.put("needed", kind == null ? List.of() : repo.needed(kind, subject));
        out.put("accepted", kind == null ? List.of() : repo.accepted(kind, subject));
        return out;
    }

    /** the person's own act: recorded once per version, with where it came from; a second call answers false */
    @PostMapping("/api/v1/privacy/acceptance")
    @Transactional
    Map<String, Object> accept(Authentication auth, @Valid @RequestBody Accept body, HttpServletRequest request,
                               @RequestHeader(value = "User-Agent", required = false) String userAgent) {
        String kind = subjectKind(auth);
        if (kind == null) {
            throw new DomainRuleViolation("ACCEPTANCE_SUBJECT", "This session is not a person's own account.",
                    new DomainRuleViolation.Remedy("Sign in to your own portal account to accept the policy.", "You"));
        }
        String channel = "REGISTRATION".equalsIgnoreCase(body.channel()) ? "REGISTRATION" : "PORTAL";
        boolean recorded = repo.accept(kind, UUID.fromString(auth.getName()), body.documentId(), ClientAddress.of(request), userAgent, channel);
        return Map.of("accepted", true, "recorded", recorded);
    }

    @GetMapping("/api/v1/privacy/requests")
    @Transactional(readOnly = true)
    Map<String, Object> requests(Authentication auth) {
        String kind = subjectKind(auth);
        return Map.of("rows", kind == null ? List.of() : repo.myRequests(kind, UUID.fromString(auth.getName())));
    }

    /** a privacy request by the person, onto the governance request log under its own reference */
    @PostMapping("/api/v1/privacy/requests")
    @Transactional
    Map<String, Object> file(Authentication auth, @Valid @RequestBody Request body) {
        String kind = subjectKind(auth);
        if (kind == null) {
            throw new DomainRuleViolation("DSR_SUBJECT", "This session is not a person's own account.",
                    new DomainRuleViolation.Remedy("Sign in to your own portal account, or write to the privacy contact.", "You"));
        }
        String reference = repo.fileRequest(body.kind().trim().toUpperCase(Locale.ROOT), kind, UUID.fromString(auth.getName()),
                body.contact() == null || body.contact().isBlank() ? null : body.contact().trim(), body.detail().trim());
        return Map.of("reference", reference);
    }

    /* ── the administrator's screen ── */

    @GetMapping("/api/v1/privacy/admin/documents")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> documents() {
        List<Map<String, Object>> rows = new ArrayList<>();
        for (Map<String, Object> d : repo.documents()) {
            Map<String, Object> r = new LinkedHashMap<>(d);
            r.remove("sections");
            r.remove("review_points");
            if ("PUBLISHED".equals(d.get("status"))) {
                r.put("acceptance", repo.acceptanceSummary((UUID) d.get("id")));
            }
            rows.add(r);
        }
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("rows", rows);
        out.put("contact", repo.contact());
        out.put("providers", providers());
        out.put("tokens", tokenLegend());
        return out;
    }

    @GetMapping("/api/v1/privacy/admin/documents/{id}")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> document(@PathVariable UUID id) {
        Map<String, Object> d = repo.document(id).orElseThrow(() -> new NotFound("legal document", id));
        Map<String, Object> out = new LinkedHashMap<>(d);
        out.put("sections", parse(d.get("sections")));
        out.put("review_points", parse(d.get("review_points")));
        return out;
    }

    /** the draft as the public will read it, tokens filled, for the administrator's preview */
    @GetMapping("/api/v1/privacy/admin/documents/{id}/preview")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> preview(@PathVariable UUID id) {
        return render(repo.document(id).orElseThrow(() -> new NotFound("legal document", id)));
    }

    @PostMapping("/api/v1/privacy/admin/documents/draft")
    @PreAuthorize(SETTERS)
    @Transactional
    Map<String, Object> draft(@Valid @RequestBody Draft body) {
        AuditContext ctx = AuditContextHolder.required();
        return repo.draft(body.kind().trim().toUpperCase(Locale.ROOT), ctx.actorId(), ctx.actorOffice());
    }

    @PutMapping("/api/v1/privacy/admin/documents/{id}")
    @PreAuthorize(SETTERS)
    @Transactional
    Map<String, Object> update(@PathVariable UUID id, @Valid @RequestBody Update body) {
        AuditContext ctx = AuditContextHolder.required();
        repo.update(id, body.title().trim(), body.summary(), json.writeValueAsString(body.sections()), body.effectiveOn(), body.requiresAcceptance(),
                ctx.actorId(), ctx.actorOffice());
        return document(id);
    }

    @PostMapping("/api/v1/privacy/admin/documents/{id}/review")
    @PreAuthorize(SETTERS)
    @Transactional
    Map<String, Object> review(@PathVariable UUID id, @Valid @RequestBody Review body) {
        AuditContext ctx = AuditContextHolder.required();
        repo.review(id, body.key().trim(), body.confirmed(), ctx.actorId(), ctx.actorOffice());
        return document(id);
    }

    @PostMapping("/api/v1/privacy/admin/documents/{id}/publish")
    @PreAuthorize(SETTERS)
    @Transactional
    Map<String, Object> publish(@PathVariable UUID id, @RequestBody(required = false) Publish body) {
        AuditContext ctx = AuditContextHolder.required();
        repo.publish(id, body == null ? null : body.effectiveOn(), ctx.actorId(), ctx.actorOffice());
        return document(id);
    }

    @PostMapping("/api/v1/privacy/admin/documents/{id}/withdraw")
    @PreAuthorize(SETTERS)
    @Transactional
    Map<String, Object> withdraw(@PathVariable UUID id) {
        AuditContext ctx = AuditContextHolder.required();
        repo.withdraw(id, ctx.actorId(), ctx.actorOffice());
        return document(id);
    }

    @GetMapping("/api/v1/privacy/admin/contact")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> contact() {
        return repo.contact();
    }

    @PutMapping("/api/v1/privacy/admin/contact")
    @PreAuthorize(CONTACT_SETTERS)
    @Transactional
    Map<String, Object> setContact(@Valid @RequestBody Contact body) {
        AuditContext ctx = AuditContextHolder.required();
        repo.setContact(body.name(), body.title(), body.office(), body.email(), body.phone(), body.address(),
                body.requestDays() == null ? 30 : body.requestDays(), body.note(), ctx.actorId(), ctx.actorOffice());
        return repo.contact();
    }

    @GetMapping("/api/v1/privacy/admin/history")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> history(@RequestParam(defaultValue = "100") int limit) {
        return Map.of("rows", repo.history(limit));
    }

    /* ── rendering ── */

    /** the document with its tokens resolved: the University, the privacy contact, the providers, the version and its dates */
    private Map<String, Object> render(Map<String, Object> doc) {
        Map<String, String> tokens = tokens(doc);
        List<Map<String, Object>> sections = new ArrayList<>();
        int no = 0;
        for (Map<String, Object> s : parse(doc.get("sections"))) {
            no++;
            Map<String, Object> r = new LinkedHashMap<>();
            r.put("no", no);
            r.put("key", s.get("key") == null ? "s" + no : s.get("key"));
            r.put("heading", String.valueOf(s.get("heading")));
            r.put("body", fill(String.valueOf(s.get("body")), tokens));
            sections.add(r);
        }
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("id", doc.get("id"));
        out.put("kind", doc.get("kind"));
        out.put("version", doc.get("version"));
        out.put("status", doc.get("status"));
        out.put("title", doc.get("title"));
        out.put("summary", doc.get("summary") == null ? null : fill(String.valueOf(doc.get("summary")), tokens));
        out.put("effectiveOn", doc.get("effective_on"));
        out.put("publishedAt", doc.get("published_at"));
        out.put("updatedAt", doc.get("updated_at"));
        out.put("requiresAcceptance", doc.get("requires_acceptance"));
        out.put("sections", sections);
        Map<String, Object> inst = repo.institution();
        Map<String, Object> contact = repo.contact();
        out.put("institution", Map.of("name", str(inst.get("name")), "shortName", str(inst.get("short_name")), "address", tokens.get("address"),
                "phone", str(inst.get("phone")), "email", str(inst.get("email")), "website", str(inst.get("website"))));
        out.put("contact", Map.of("name", str(contact.get("dpo_name")), "title", str(contact.get("dpo_title")), "office", str(contact.get("dpo_office")),
                "email", str(contact.get("dpo_email")), "phone", str(contact.get("dpo_phone")), "address", str(contact.get("dpo_address")),
                "requestDays", contact.get("request_days") == null ? 30 : contact.get("request_days")));
        return out;
    }

    private Map<String, String> tokens(Map<String, Object> doc) {
        Map<String, Object> inst = repo.institution();
        Map<String, Object> c = repo.contact();
        Map<String, String> t = new LinkedHashMap<>();
        String address = String.join(", ", nonBlank(inst.get("address"), inst.get("city"), inst.get("state"), inst.get("country")));
        t.put("university", or(inst.get("name"), "the University"));
        t.put("short_name", or(inst.get("short_name"), or(inst.get("name"), "the University")));
        t.put("address", address.isBlank() ? "address as published by the University" : address);
        t.put("phone", or(inst.get("phone"), "not stated"));
        t.put("email", or(inst.get("email"), "not stated"));
        t.put("website", or(inst.get("website"), "not stated"));
        t.put("dpo_name", or(c.get("dpo_name"), "the Data Protection Officer (name to be stated)"));
        t.put("dpo_title", or(c.get("dpo_title"), "Data Protection Officer"));
        t.put("dpo_office", or(c.get("dpo_office"), "the University's privacy office"));
        t.put("dpo_email", or(c.get("dpo_email"), or(inst.get("email"), "the University's e-mail address")));
        t.put("dpo_phone", or(c.get("dpo_phone"), or(inst.get("phone"), "the University's telephone number")));
        t.put("dpo_address", or(c.get("dpo_address"), address.isBlank() ? "the University's address" : address));
        t.put("request_days", String.valueOf(c.get("request_days") == null ? 30 : c.get("request_days")));
        t.put("providers", providers());
        t.put("version", String.valueOf(doc.get("version")));
        t.put("effective_on", day(doc.get("effective_on"), "the date of publication"));
        t.put("published_on", day(doc.get("published_at"), "publication"));
        return t;
    }

    /** the providers in use, read from what is configured — never a list of possible ones */
    private String providers() {
        List<String> gateways = new ArrayList<>();
        if (paystack) gateways.add("Paystack");
        if (flutterwave) gateways.add("Flutterwave");
        if (quickteller) gateways.add("Interswitch Quickteller/WebPAY");
        StringBuilder b = new StringBuilder();
        b.append("- Payments: ");
        if (!gateways.isEmpty()) {
            b.append(String.join(", ", gateways)).append(" (card and bank payments on the provider's own page) and ");
        }
        b.append("Interswitch PAYDirect (payment at the bank against your fee reference). Each receives your name, the fee reference, the amount and its purpose, and returns its own transaction reference to the portal.\n");
        b.append("- SMS: ").append(repo.smsOn() ? "eBulkSMS, which receives the phone number and the text of each message the University sends."
                : "no SMS service is switched on at present; SMS notices are not sent.").append("\n");
        b.append("- E-mail: ").append(repo.mailOn() ? "the University's own mail service (SMTP), which receives the address and the message."
                : "no mail service is switched on at present; e-mail notices are not sent.").append("\n");
        b.append("- File storage: ").append("S3".equals(filesProvider)
                ? "S3-compatible object storage" + (filesRegion.isBlank() ? "" : " in the " + filesRegion + " region") + ", which holds uploaded documents and photographs under keys the portal issues."
                : "uploaded documents and photographs are held in the University's own database.");
        return b.toString();
    }

    private Map<String, String> tokenLegend() {
        Map<String, String> m = new LinkedHashMap<>();
        m.put("university", "the University's name (institution profile)");
        m.put("short_name", "the short name");
        m.put("address", "the address, city, state and country");
        m.put("phone", "the University's telephone");
        m.put("email", "the University's e-mail");
        m.put("website", "the website");
        m.put("dpo_name", "the privacy contact's name");
        m.put("dpo_title", "the privacy contact's title");
        m.put("dpo_office", "the privacy contact's office");
        m.put("dpo_email", "the privacy contact's e-mail");
        m.put("dpo_phone", "the privacy contact's telephone");
        m.put("dpo_address", "the privacy contact's address");
        m.put("request_days", "the period for answering requests");
        m.put("providers", "the providers in use, read from the configuration");
        m.put("version", "this version's number");
        m.put("effective_on", "the effective date");
        m.put("published_on", "the publication date");
        return m;
    }

    private static String fill(String text, Map<String, String> tokens) {
        Matcher m = TOKEN.matcher(text);
        StringBuilder b = new StringBuilder();
        while (m.find()) {
            String v = tokens.get(m.group(1));
            m.appendReplacement(b, Matcher.quoteReplacement(v == null ? m.group(0) : v));
        }
        m.appendTail(b);
        return b.toString();
    }

    @SuppressWarnings("unchecked")
    private List<Map<String, Object>> parse(Object jsonText) {
        if (jsonText == null) {
            return List.of();
        }
        return json.readValue(String.valueOf(jsonText), List.class);
    }

    private static String day(Object v, String otherwise) {
        if (v instanceof LocalDate d) return DAY.format(d);
        if (v instanceof OffsetDateTime t) return DAY.format(t.toLocalDate());
        if (v instanceof java.sql.Date d) return DAY.format(d.toLocalDate());
        if (v instanceof java.sql.Timestamp t) return DAY.format(t.toLocalDateTime().toLocalDate());
        return otherwise;
    }

    private static List<String> nonBlank(Object... parts) {
        List<String> out = new ArrayList<>();
        for (Object p : parts) {
            if (p != null && !String.valueOf(p).isBlank()) out.add(String.valueOf(p).trim());
        }
        return out;
    }

    private static String or(Object v, String otherwise) {
        return v == null || String.valueOf(v).isBlank() ? otherwise : String.valueOf(v).trim();
    }

    private static String str(Object v) {
        return v == null ? "" : String.valueOf(v);
    }

    /** whose acceptance: a student's, an applicant's (Post-UTME, CCE, JUPEB, PG — one door each), else a staff member's; a CBT-only token is nobody's */
    static String subjectKind(Authentication auth) {
        boolean student = false, applicant = false, other = false;
        for (var a : auth.getAuthorities()) {
            String s = a.getAuthority();
            if ("OFFICE_student".equals(s)) student = true;
            else if ("OFFICE_applicant".equals(s)) applicant = true;
            else if (s.startsWith("OFFICE_") && !"OFFICE_putmecbt".equals(s)) other = true;
        }
        if (student) return "STUDENT";
        if (applicant) return "APPLICANT";
        return other ? "STAFF" : null;
    }
}
