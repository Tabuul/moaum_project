package ng.edu.moaum.portal.credentials;

import java.security.SecureRandom;
import java.sql.Types;
import java.time.LocalDate;
import java.time.format.DateTimeParseException;
import java.util.Base64;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.UUID;

import jakarta.servlet.http.HttpServletRequest;
import jakarta.validation.Valid;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpHeaders;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import ng.edu.moaum.portal.shared.AuditContext;
import ng.edu.moaum.portal.shared.AuditContextHolder;
import ng.edu.moaum.portal.shared.ClientAddress;
import ng.edu.moaum.portal.shared.DomainRuleViolation;
import ng.edu.moaum.portal.shared.FileObjects;
import ng.edu.moaum.portal.shared.Throttle;

/**
 * A transcript asked for without a portal account (V668), under /api/v1/public (a public door: no session, no token read). A graduate
 * is proved by the matriculation number, the date of birth and a code sent to the contact on record — the code gives a pass good for an
 * hour, a long random secret the database keeps only as a hash — or, without that contact, by an identity document the Transcript Desk
 * checks. An institution names the graduate by number and surname, and the graduate consents at a private link. Every request is
 * followed by its own private link; nothing internal is shown there. The rules (the fee, the payment reference, the duplicate request,
 * what may be produced and when) are the database's, the same as a signed-in student's request.
 */
@RestController
@RequestMapping("/api/v1/public/transcripts")
class TranscriptPublicController {

    private static final UUID NOBODY = new UUID(0, 0);
    private static final SecureRandom RANDOM = new SecureRandom();
    private static final int MAX_ID_MB = 5;
    private static final Map<String, String> ID_TYPES = Map.of("pdf", "application/pdf", "jpg", "image/jpeg", "jpeg", "image/jpeg", "png", "image/png");

    private final JdbcClient jdbc;
    private final TransactionTemplate tx;
    private final Throttle throttle;
    private final FileObjects files;
    private final String portalUrl;

    TranscriptPublicController(JdbcClient jdbc, PlatformTransactionManager transactions, Throttle throttle, FileObjects files,
                               @Value("${moaum.portal-url:https://moaum-portal-production.up.railway.app}") String portalUrl) {
        this.jdbc = jdbc;
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
            throw new DomainRuleViolation("TRN_REFUSED", "The request could not be accepted.",
                    new DomainRuleViolation.Remedy("Reload the page and fill in the form again.", "You"));
        }
    }

    private static LocalDate date(String s) {
        try {
            return LocalDate.parse(s == null ? "" : s.trim());
        } catch (DateTimeParseException e) {
            throw new DomainRuleViolation("TRN_DATE", "Give the date of birth as day, month and year.",
                    new DomainRuleViolation.Remedy("Pick it from the date field.", "You"));
        }
    }

    private <T> T asPublic(String why, java.util.function.Supplier<T> work) {
        return AuditContextHolder.with(new AuditContext(NOBODY, "applicant", why, null, null), () -> tx.execute(st -> work.get()));
    }

    private String statusUrl(String token) {
        return portalUrl + "/transcripts/status/" + token;
    }

    /** what the request answers: its reference, the fee, the payment reference, and the private link to follow it */
    private Map<String, Object> made(Map<String, Object> r, String token) {
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("ref", r.get("ref"));
        out.put("fee", r.get("fee"));
        out.put("reference", r.get("reference"));
        out.put("stage", r.get("stage"));
        out.put("statusPath", "/transcripts/status/" + token);
        return out;
    }

    /* ── what the form offers ── */

    @GetMapping("/options")
    Map<String, Object> options() {
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("policies", jdbc.sql("""
                SELECT p.kind, p.label, p.currency, p.physical_fee, p.international_fee, p.urgent_fee, p.sla_days, p.urgent_sla_days,
                       credentials.fee_for(p.kind, (SELECT name FROM policy.academic_session WHERE state = 'CURRENT'), 'DIGITAL', false, false, 1) AS fee_now
                  FROM credentials.document_policy p WHERE p.kind IN ('TRANSCRIPT', 'SESSIONAL_TRANSCRIPT') AND p.active ORDER BY p.kind DESC
                """).query().listOfRows());
        out.put("maxIdMb", MAX_ID_MB);
        return out;
    }

    /* ── a graduate: the code to the contact on record ── */

    public record CodeIn(@NotBlank @Size(max = 40) String matricNo, @NotBlank @Size(max = 10) String dateOfBirth, @Size(max = 200) String website2) {
    }

    @PostMapping("/code")
    Map<String, Object> code(@Valid @RequestBody CodeIn body, HttpServletRequest request) {
        throttle.take(Throttle.Door.TRANSCRIPT_CODE, ClientAddress.of(request));
        honeypot(body.website2());
        LocalDate dob = date(body.dateOfBirth());
        return asPublic("transcript request: a code sent to the contact on record", () -> jdbc.sql("SELECT * FROM credentials.public_code_send(:m, :d, :s)")
                .param("m", body.matricNo()).param("d", dob).param("s", ClientAddress.of(request), Types.VARCHAR).query().singleRow());
    }

    public record CheckIn(@NotNull UUID challenge, @NotBlank @Size(max = 12) String code) {
    }

    /** the code typed: a pass for the hour, or a refusal that says nothing more */
    @PostMapping("/code/check")
    Map<String, Object> check(@Valid @RequestBody CheckIn body, HttpServletRequest request) {
        throttle.take(Throttle.Door.TRANSCRIPT_FORM, ClientAddress.of(request));
        String pass = newToken();
        Boolean ok = asPublic("transcript request: a code checked", () -> jdbc.sql("SELECT credentials.public_code_check(:c, :k, :p)")
                .param("c", body.challenge()).param("k", body.code()).param("p", pass).query(Boolean.class).single());
        if (!Boolean.TRUE.equals(ok)) {
            throw new DomainRuleViolation("TRN_CODE_WRONG", "That code is not the one sent.",
                    new DomainRuleViolation.Remedy("Type the six digits of the latest code; after five tries, ask for a new one.", "You"));
        }
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("pass", pass);
        out.put("graduate", jdbc.sql("""
                SELECT s.other_names || ' ' || s.surname AS name, s.matric_no, p.name AS programme, r.email, r.phone
                  FROM people.student s JOIN ref.programme p ON p.code = s.programme_code CROSS JOIN LATERAL people.student_reach(s.id) r
                 WHERE s.id = credentials.public_pass_student(:p)
                """).param("p", pass).query().singleRow());
        return out;
    }

    /** where the copy goes and how: the same answers on every kind of public request */
    public record Order(@Size(max = 30) String kind, @Size(max = 30) String destination, @Size(max = 200) String destinationName, @Size(max = 200) String department,
                        @Size(max = 200) String recipient, @Size(max = 200) String recipientEmail, @Size(max = 1000) String address,
                        @Size(max = 100) String recipientReference, @Size(max = 200) String purpose, @Size(max = 10) String delivery, Boolean express,
                        Boolean international, @Min(1) @Max(10) Integer copies) {
    }

    public record GraduateIn(@NotBlank String pass, @Size(max = 200) String name, @Size(max = 200) String email, @Size(max = 40) String phone,
                             @NotNull @Valid Order order, @Size(max = 200) String website2) {
    }

    @PostMapping("/requests/graduate")
    Map<String, Object> graduate(@Valid @RequestBody GraduateIn body, HttpServletRequest request) {
        throttle.take(Throttle.Door.TRANSCRIPT_FORM, ClientAddress.of(request));
        honeypot(body.website2());
        String token = newToken();
        Order o = body.order();
        Map<String, Object> r = asPublic("transcript request by a graduate without a portal account", () -> jdbc.sql("""
                SELECT * FROM credentials.public_request_graduate(:pass, :tok, :name, :email, :phone, :kind, :dest, :dname, :dept, :rec, :remail, :addr, :rref, :purpose,
                                                                  :delivery, :express, :intl, :copies, :src, :url)
                """).param("pass", body.pass()).param("tok", token).param("name", body.name(), Types.VARCHAR).param("email", body.email(), Types.VARCHAR)
                .param("phone", body.phone(), Types.VARCHAR).param("kind", o.kind(), Types.VARCHAR).param("dest", o.destination(), Types.VARCHAR)
                .param("dname", o.destinationName(), Types.VARCHAR).param("dept", o.department(), Types.VARCHAR).param("rec", o.recipient(), Types.VARCHAR)
                .param("remail", o.recipientEmail(), Types.VARCHAR).param("addr", o.address(), Types.VARCHAR).param("rref", o.recipientReference(), Types.VARCHAR)
                .param("purpose", o.purpose(), Types.VARCHAR).param("delivery", o.delivery(), Types.VARCHAR).param("express", o.express(), Types.BOOLEAN)
                .param("intl", o.international(), Types.BOOLEAN).param("copies", o.copies(), Types.INTEGER).param("src", ClientAddress.of(request), Types.VARCHAR)
                .param("url", statusUrl(token)).query().singleRow());
        return made(r, token);
    }

    /* ── a graduate without the contact on record: a new one and an identity document ── */

    public record DocumentIn(@NotBlank @Size(max = 40) String matricNo, @NotBlank @Size(max = 10) String dateOfBirth, @NotBlank @Size(max = 200) String name,
                             @NotBlank @Size(max = 200) String email, @Size(max = 40) String phone, @NotBlank @Size(max = 200) String idFilename,
                             @NotBlank String idDataUrl, @NotNull @Valid Order order, @Size(max = 200) String website2) {
    }

    private record IdFile(String filename, String contentType, byte[] bytes) {
    }

    /** the identity document from a data URL: a PDF, JPEG or PNG that is what it says, within the size allowed */
    private static IdFile idFile(String filename, String dataUrl) {
        DomainRuleViolation.Remedy fix = new DomainRuleViolation.Remedy("Photograph or scan the identity document as a JPEG, PNG or PDF of at most " + MAX_ID_MB + " MB.", "You");
        String name = filename.replaceAll("[\\\\/:*?\"<>|\\p{Cntrl}]", "_").trim();
        int dot = name.lastIndexOf('.');
        String type = ID_TYPES.get(dot < 0 ? "" : name.substring(dot + 1).toLowerCase());
        int comma = dataUrl.indexOf(',');
        if (type == null || !dataUrl.startsWith("data:") || comma < 0 || !dataUrl.substring(0, comma).contains(";base64")) {
            throw new DomainRuleViolation("TRN_ID_FILE", "The identity document could not be read.", fix);
        }
        byte[] b;
        try {
            b = Base64.getDecoder().decode(dataUrl.substring(comma + 1).replaceAll("\\s", ""));
        } catch (IllegalArgumentException e) {
            throw new DomainRuleViolation("TRN_ID_FILE", "The identity document could not be read.", fix);
        }
        boolean real = switch (type) {
            case "application/pdf" -> b.length > 5 && b[0] == '%' && b[1] == 'P' && b[2] == 'D' && b[3] == 'F';
            case "image/png" -> b.length > 8 && (b[0] & 0xff) == 0x89 && b[1] == 'P' && b[2] == 'N' && b[3] == 'G';
            default -> b.length > 3 && (b[0] & 0xff) == 0xFF && (b[1] & 0xff) == 0xD8 && (b[2] & 0xff) == 0xFF;
        };
        if (b.length == 0 || b.length > MAX_ID_MB * 1024L * 1024L || !real) {
            throw new DomainRuleViolation("TRN_ID_FILE", "The identity document is empty, too large, or not the kind of file its name says.", fix);
        }
        return new IdFile(name, type, b);
    }

    @PostMapping("/requests/with-document")
    Map<String, Object> withDocument(@Valid @RequestBody DocumentIn body, HttpServletRequest request) {
        throttle.take(Throttle.Door.TRANSCRIPT_FORM, ClientAddress.of(request));
        honeypot(body.website2());
        LocalDate dob = date(body.dateOfBirth());
        IdFile f = idFile(body.idFilename(), body.idDataUrl());
        String token = newToken();
        Order o = body.order();
        Map<String, Object> r = asPublic("transcript request by a graduate with an identity document", () -> {
            UUID object = files.store("credentials.public_request", token.substring(0, 12), f.filename(), f.contentType(), f.bytes());
            return jdbc.sql("""
                    SELECT * FROM credentials.public_request_with_document(:m, :dob, :tok, :name, :email, :phone, :fname, :ftype, :fbytes, :fobj, :fsha,
                                                                           :kind, :dest, :dname, :dept, :rec, :remail, :addr, :rref, :purpose,
                                                                           :delivery, :express, :intl, :copies, :src, :url)
                    """).param("m", body.matricNo()).param("dob", dob).param("tok", token).param("name", body.name()).param("email", body.email())
                    .param("phone", body.phone(), Types.VARCHAR).param("fname", f.filename()).param("ftype", f.contentType())
                    .param("fbytes", object == null ? f.bytes() : null, Types.BINARY).param("fobj", object, Types.OTHER).param("fsha", FileObjects.sha256(f.bytes()))
                    .param("kind", o.kind(), Types.VARCHAR).param("dest", o.destination(), Types.VARCHAR).param("dname", o.destinationName(), Types.VARCHAR)
                    .param("dept", o.department(), Types.VARCHAR).param("rec", o.recipient(), Types.VARCHAR).param("remail", o.recipientEmail(), Types.VARCHAR)
                    .param("addr", o.address(), Types.VARCHAR).param("rref", o.recipientReference(), Types.VARCHAR).param("purpose", o.purpose(), Types.VARCHAR)
                    .param("delivery", o.delivery(), Types.VARCHAR).param("express", o.express(), Types.BOOLEAN).param("intl", o.international(), Types.BOOLEAN)
                    .param("copies", o.copies(), Types.INTEGER).param("src", ClientAddress.of(request), Types.VARCHAR).param("url", statusUrl(token))
                    .query().singleRow();
        });
        return made(r, token);
    }

    /* ── an institution, with the graduate's consent ── */

    public record InstitutionIn(@NotBlank @Size(max = 40) String matricNo, @NotBlank @Size(max = 100) String surname, @NotBlank @Size(max = 200) String organisation,
                                @NotBlank @Size(max = 200) String name, @NotBlank @Size(max = 200) String email, @Size(max = 40) String phone,
                                @NotNull @Valid Order order, @Size(max = 200) String website2) {
    }

    @PostMapping("/requests/institution")
    Map<String, Object> institution(@Valid @RequestBody InstitutionIn body, HttpServletRequest request) {
        throttle.take(Throttle.Door.TRANSCRIPT_FORM, ClientAddress.of(request));
        honeypot(body.website2());
        String token = newToken(), consent = newToken();
        Order o = body.order();
        Map<String, Object> r = asPublic("transcript request by an institution", () -> jdbc.sql("""
                SELECT * FROM credentials.public_request_institution(:m, :sn, :tok, :con, :org, :name, :email, :phone, :dest, :dept, :rec, :remail, :addr, :rref,
                                                                     :purpose, :delivery, :express, :intl, :copies, :src, :url, :curl)
                """).param("m", body.matricNo()).param("sn", body.surname()).param("tok", token).param("con", consent).param("org", body.organisation())
                .param("name", body.name()).param("email", body.email()).param("phone", body.phone(), Types.VARCHAR).param("dest", o.destination(), Types.VARCHAR)
                .param("dept", o.department(), Types.VARCHAR).param("rec", o.recipient(), Types.VARCHAR).param("remail", o.recipientEmail(), Types.VARCHAR)
                .param("addr", o.address(), Types.VARCHAR).param("rref", o.recipientReference(), Types.VARCHAR).param("purpose", o.purpose(), Types.VARCHAR)
                .param("delivery", o.delivery(), Types.VARCHAR).param("express", o.express(), Types.BOOLEAN).param("intl", o.international(), Types.BOOLEAN)
                .param("copies", o.copies(), Types.INTEGER).param("src", ClientAddress.of(request), Types.VARCHAR).param("url", statusUrl(token))
                .param("curl", portalUrl + "/transcripts/consent/" + consent).query().singleRow());
        return made(r, token);
    }

    /* ── a request followed by its private link ── */

    @GetMapping("/status/{token}")
    ResponseEntity<Map<String, Object>> status(@PathVariable String token, HttpServletRequest request) {
        throttle.take(Throttle.Door.TRANSCRIPT_STATUS, ClientAddress.of(request));
        String json = jdbc.sql("SELECT credentials.public_status(:t)::text").param("t", token).query(String.class).single();
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("request", json);
        out.put("pay", jdbc.sql("""
                SELECT q.url, q.biller_name FROM credentials.public_request pr JOIN credentials.transcript_request t ON t.id = pr.request_id
                 CROSS JOIN LATERAL finance.quickteller_link(t.reference) q
                 WHERE pr.status_hash = credentials.secret_hash(:t) AND t.paid_at IS NULL AND t.closed_at IS NULL AND t.reference IS NOT NULL
                """).param("t", token).query().listOfRows().stream().findFirst().orElse(null));
        return ResponseEntity.ok().header(HttpHeaders.CACHE_CONTROL, "no-store").body(out);
    }

    /** the payment reference made payable again once it has expired */
    @PostMapping("/status/{token}/renew")
    Map<String, Object> renew(@PathVariable String token, HttpServletRequest request) {
        throttle.take(Throttle.Door.TRANSCRIPT_FORM, ClientAddress.of(request));
        String ref = asPublic("transcript request: the payment reference renewed from its private link",
                () -> jdbc.sql("SELECT credentials.public_renew_reference(:t)").param("t", token).query(String.class).single());
        return Map.of("reference", ref);
    }

    @GetMapping("/consent/{token}")
    ResponseEntity<Map<String, Object>> consentView(@PathVariable String token, HttpServletRequest request) {
        throttle.take(Throttle.Door.TRANSCRIPT_STATUS, ClientAddress.of(request));
        String json = jdbc.sql("SELECT credentials.public_consent_view(:t)::text").param("t", token).query(String.class).single();
        return ResponseEntity.ok().header(HttpHeaders.CACHE_CONTROL, "no-store").body(Map.of("consent", json));
    }

    public record ConsentIn(@NotNull Boolean give, @Size(max = 1000) String note) {
    }

    @PostMapping("/consent/{token}")
    Map<String, Object> consent(@PathVariable String token, @Valid @RequestBody ConsentIn body, HttpServletRequest request) {
        throttle.take(Throttle.Door.TRANSCRIPT_FORM, ClientAddress.of(request));
        String to = asPublic("transcript request: the graduate " + (body.give() ? "consented" : "refused consent"),
                () -> jdbc.sql("SELECT credentials.public_consent(:t, :g, :n)").param("t", token).param("g", body.give()).param("n", body.note(), Types.VARCHAR)
                        .query(String.class).single());
        return Map.of("consent", to);
    }
}
