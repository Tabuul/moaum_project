package ng.edu.moaum.portal.jupeb;

import java.sql.Types;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

import jakarta.validation.Valid;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

import ng.edu.moaum.portal.helpdesk.RequesterTickets;
import ng.edu.moaum.portal.shared.DomainRuleViolation;
import ng.edu.moaum.portal.shared.FileObjects;
import ng.edu.moaum.portal.shared.NotFound;

import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.Authentication;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * The JUPEB candidate's own dashboard (V339), from applicant to student to result. The token's subject is the candidate's
 * JUPEB application and every read and write here is scoped to it, so nothing reaches another candidate. The candidate
 * continues the biodata the short application form did not ask, enters the O'Level, uploads the documents, pays — the amount
 * always the server's, from the Bursary's rule — submits, corrects a returned application, registers the combination's three
 * subjects, and raises support tickets on the University's desk.
 */
@RestController
@RequestMapping("/api/v1/jupeb/me")
@PreAuthorize("hasAuthority('OFFICE_applicant')")
class JupebPortalController {

    static final int MAX_DOC = 5 * 1024 * 1024;
    private static final Set<String> TYPES = Set.of("application/pdf", "image/jpeg", "image/png");
    private static final Set<String> SUPPORT = Set.of("JUPEB");

    private final JdbcClient jdbc;
    private final JupebView view;
    private final FileObjects files;
    private final RequesterTickets tickets;

    JupebPortalController(JdbcClient jdbc, JupebView view, FileObjects files, RequesterTickets tickets) {
        this.jdbc = jdbc;
        this.view = view;
        this.files = files;
        this.tickets = tickets;
    }

    /** the signed-in candidate's application; a token whose subject is not a JUPEB application is answered as not found */
    private UUID me(Authentication auth) {
        UUID id = UUID.fromString(auth.getName());
        boolean ok = jdbc.sql("SELECT true FROM jupeb.application WHERE id = :id").param("id", id).query(Boolean.class).optional().orElse(false);
        if (!ok) throw new NotFound("JUPEB application", id);
        return id;
    }

    private String state(UUID app) {
        return jdbc.sql("SELECT state FROM jupeb.application WHERE id = :id").param("id", app).query(String.class).single();
    }

    /** the record under review does not change beneath the JUPEB Office: it is edited while a draft, or once returned for correction */
    private void requireEditable(UUID app) {
        String s = state(app);
        if (!"DRAFT".equals(s) && !"RETURNED".equals(s)) {
            throw new DomainRuleViolation("JUPEB_NOT_EDITABLE", "Your application is with the JUPEB Office, so it cannot be changed now.",
                    new DomainRuleViolation.Remedy("If something must be corrected, the JUPEB Office returns the application to you and says what. Otherwise raise a support ticket.", "JUPEB Office"));
        }
    }

    @GetMapping
    @Transactional(readOnly = true)
    Map<String, Object> mine(Authentication auth) {
        Map<String, Object> out = new java.util.LinkedHashMap<>(view.of(me(auth), false));
        out.put("combinations", view.combinations(true));
        return out;
    }

    /* ── the biodata the application form did not ask, continued on the dashboard ── */

    public record Biodata(@Size(max = 80) String middleName,
                          @Pattern(regexp = "^(F|M)?$", message = "F or M") String sex,
                          @Pattern(regexp = "^(\\d{4}-\\d{2}-\\d{2})?$", message = "a date, YYYY-MM-DD") String dob,
                          @Pattern(regexp = "^([0-9]{11})?$", message = "eleven digits") String nin,
                          @Pattern(regexp = "^(0[0-9]{10})?$", message = "an eleven-digit Nigerian number") String phone,
                          @Size(max = 80) String nationality, @Size(max = 80) String stateOfOrigin, @Size(max = 80) String lga,
                          @Size(max = 300) String contactAddress, @Size(max = 300) String permanentAddress, @Size(max = 80) String homeTown,
                          @Size(max = 120) String guardianName, @Pattern(regexp = "^(0[0-9]{10})?$", message = "an eleven-digit Nigerian number") String guardianPhone,
                          @Size(max = 300) String guardianAddress,
                          @Size(max = 120) String nextOfKinName, @Pattern(regexp = "^(0[0-9]{10})?$", message = "an eleven-digit Nigerian number") String nextOfKinPhone,
                          @Size(max = 60) String nextOfKinRelationship) {
    }

    private static String blank(String s) {
        return s == null || s.isBlank() ? null : s.trim();
    }

    @PutMapping("/biodata")
    @Transactional
    Map<String, Object> biodata(Authentication auth, @Valid @RequestBody Biodata b) {
        UUID app = me(auth);
        requireEditable(app);
        jdbc.sql("""
                UPDATE jupeb.application SET middle_name = :mid, sex = coalesce(:sex, sex), date_of_birth = coalesce(:dob::date, date_of_birth),
                       nin = coalesce(:nin, nin), phone = coalesce(:phone, phone), nationality = :nat, state_of_origin = :st, lga = :lga,
                       contact_address = :ca, permanent_address = :pa, home_town = :ht, guardian_name = :gn, guardian_phone = :gp, guardian_address = :ga,
                       next_of_kin_name = :kn, next_of_kin_phone = :kp, next_of_kin_relationship = :kr
                 WHERE id = :id
                """).param("mid", blank(b.middleName()), Types.VARCHAR).param("sex", blank(b.sex()), Types.VARCHAR).param("dob", blank(b.dob()), Types.VARCHAR)
                .param("nin", blank(b.nin()), Types.VARCHAR).param("phone", blank(b.phone()), Types.VARCHAR).param("nat", blank(b.nationality()), Types.VARCHAR)
                .param("st", blank(b.stateOfOrigin()), Types.VARCHAR).param("lga", blank(b.lga()), Types.VARCHAR).param("ca", blank(b.contactAddress()), Types.VARCHAR)
                .param("pa", blank(b.permanentAddress()), Types.VARCHAR).param("ht", blank(b.homeTown()), Types.VARCHAR).param("gn", blank(b.guardianName()), Types.VARCHAR)
                .param("gp", blank(b.guardianPhone()), Types.VARCHAR).param("ga", blank(b.guardianAddress()), Types.VARCHAR).param("kn", blank(b.nextOfKinName()), Types.VARCHAR)
                .param("kp", blank(b.nextOfKinPhone()), Types.VARCHAR).param("kr", blank(b.nextOfKinRelationship()), Types.VARCHAR).param("id", app).update();
        return mine(auth);
    }

    public record Choice(@NotBlank @Size(max = 10) String programme, @NotBlank @Size(max = 40) String combination) {
    }

    /** the programme of interest and the combination, while the application is a draft or returned */
    @PutMapping("/choice")
    @Transactional
    Map<String, Object> choice(Authentication auth, @Valid @RequestBody Choice c) {
        UUID app = me(auth);
        requireEditable(app);
        String prog = jdbc.sql("SELECT code FROM ref.programme WHERE code = upper(btrim(:p)) AND category = 'UNDER GRADUATE' AND NOT archived")
                .param("p", c.programme()).query(String.class).optional()
                .orElseThrow(() -> new DomainRuleViolation("JUPEB_PROGRAMME", "Choose the undergraduate programme you intend to study.",
                        new DomainRuleViolation.Remedy("Pick one from the list.", "You")));
        UUID comb = jdbc.sql("SELECT id FROM jupeb.combination WHERE (id::text = :c OR code = upper(btrim(:c))) AND active").param("c", c.combination())
                .query(UUID.class).optional()
                .orElseThrow(() -> new DomainRuleViolation("JUPEB_COMBINATION", "Choose one of the approved subject combinations.",
                        new DomainRuleViolation.Remedy("Pick one from the list.", "You")));
        jdbc.sql("UPDATE jupeb.application SET programme_code = :p, combination_id = :c WHERE id = :id").param("p", prog).param("c", comb).param("id", app).update();
        return mine(auth);
    }

    /* ── the O'Level: at most two sittings ── */

    public record Grade(@Min(1) @Max(2) int sitting, @NotBlank @Pattern(regexp = "WAEC|NECO|NABTEB|GCE|OTHER") String examType,
                        @Size(max = 30) String examNumber, Integer examYear, @NotBlank @Size(max = 60) String subject,
                        @NotBlank @Pattern(regexp = "A1|B2|B3|C4|C5|C6|D7|E8|F9|AR") String grade) {
    }

    public record Olevel(@NotNull @Size(max = 24) List<@Valid Grade> grades) {
    }

    @PutMapping("/olevel")
    @Transactional
    Map<String, Object> olevel(Authentication auth, @Valid @RequestBody Olevel body) {
        UUID app = me(auth);
        requireEditable(app);
        Set<String> seen = new java.util.HashSet<>();
        for (Grade g : body.grades()) {
            if (!seen.add(g.sitting() + "|" + g.subject().trim().toUpperCase())) {
                throw new DomainRuleViolation("JUPEB_OLEVEL_TWICE", g.subject().trim() + " appears twice in sitting " + g.sitting() + ".",
                        new DomainRuleViolation.Remedy("Enter each subject once per sitting.", "You"));
            }
            if (g.examYear() != null && (g.examYear() < 1970 || g.examYear() > java.time.Year.now().getValue())) {
                throw new DomainRuleViolation("JUPEB_OLEVEL_YEAR", "The examination year " + g.examYear() + " is not possible.",
                        new DomainRuleViolation.Remedy("Enter the year you sat the examination.", "You"));
            }
        }
        jdbc.sql("DELETE FROM jupeb.olevel WHERE application_id = :id").param("id", app).update();
        for (Grade g : body.grades()) {
            jdbc.sql("INSERT INTO jupeb.olevel (application_id, sitting, exam_type, exam_number, exam_year, subject, grade) VALUES (:a, :s, :t, :n, :y, :sub, :g)")
                    .param("a", app).param("s", g.sitting()).param("t", g.examType()).param("n", blank(g.examNumber()), Types.VARCHAR)
                    .param("y", g.examYear(), Types.INTEGER).param("sub", g.subject().trim()).param("g", g.grade()).update();
        }
        return mine(auth);
    }

    /* ── the documents: private, read back only by their owner and the JUPEB Office ── */

    public record DocumentIn(@NotBlank @Size(max = 200) String filename, @NotBlank @Size(max = 100) String contentType, @NotBlank String base64) {
    }

    @PostMapping("/documents/{kind}")
    @Transactional
    Map<String, Object> upload(Authentication auth, @PathVariable String kind, @Valid @RequestBody DocumentIn body) {
        UUID app = me(auth);
        String k = kind.trim().toUpperCase();
        Map<String, Object> dk = jdbc.sql("SELECT code, image FROM jupeb.document_kind WHERE code = :k AND active").param("k", k).query().listOfRows().stream().findFirst()
                .orElseThrow(() -> new NotFound("document kind", k));
        String current = jdbc.sql("SELECT status FROM jupeb.document WHERE application_id = :a AND kind = :k").param("a", app).param("k", k).query(String.class).optional().orElse(null);
        // a draft or returned application takes any document; afterwards only one the office asked to be replaced
        boolean replacing = "REJECTED".equals(current) || "REPLACEMENT_REQUIRED".equals(current);
        if (!replacing) requireEditable(app);
        boolean image = Boolean.TRUE.equals(dk.get("image"));
        String ct = body.contentType().trim().toLowerCase();
        if (!TYPES.contains(ct) || (image && "application/pdf".equals(ct))) {
            throw new DomainRuleViolation("JUPEB_DOC_TYPE", image ? "The passport photograph is a JPEG or PNG image." : "A document is a PDF, JPEG or PNG file.",
                    new DomainRuleViolation.Remedy("Scan or save it in one of those formats and upload it again.", "You"));
        }
        byte[] content;
        try {
            content = java.util.Base64.getDecoder().decode(body.base64());
        } catch (IllegalArgumentException notBase64) {
            throw new DomainRuleViolation("JUPEB_DOC_ENCODING", "The file did not arrive intact.", new DomainRuleViolation.Remedy("Try the upload again.", "You"));
        }
        if (content.length == 0 || content.length > MAX_DOC) {
            throw new DomainRuleViolation("JUPEB_DOC_SIZE", "A document is at most 5 MB; this one is " + (content.length / 1024) + " KB.",
                    new DomainRuleViolation.Remedy("Reduce the scan's resolution and upload it again.", "You"));
        }
        if (!signatureMatches(ct, content)) {
            throw new DomainRuleViolation("JUPEB_DOC_TYPE", "The file's contents are not the " + ct + " its name claims.",
                    new DomainRuleViolation.Remedy("Upload the original PDF, JPEG or PNG.", "You"));
        }
        List<UUID> old = jdbc.sql("SELECT object_id FROM jupeb.document WHERE application_id = :a AND kind = :k AND object_id IS NOT NULL").param("a", app).param("k", k).query(UUID.class).list();
        UUID oid = files.store("jupeb.document", app, body.filename().trim(), ct, content);
        UUID doc = jdbc.sql("""
                INSERT INTO jupeb.document (application_id, kind, filename, content_type, size_bytes, object_id)
                VALUES (:a, :k, :fn, :ct, :sz, :o)
                ON CONFLICT (application_id, kind) DO UPDATE SET filename = EXCLUDED.filename, content_type = EXCLUDED.content_type, size_bytes = EXCLUDED.size_bytes,
                       object_id = EXCLUDED.object_id, status = 'UPLOADED', review_note = NULL, reviewed_by = NULL, reviewed_at = NULL, uploaded_at = now()
                RETURNING id
                """).param("a", app).param("k", k).param("fn", body.filename().trim()).param("ct", ct).param("sz", content.length).param("o", oid, Types.OTHER)
                .query(UUID.class).single();
        jdbc.sql("DELETE FROM jupeb.document_blob WHERE document_id = :d").param("d", doc).update();
        if (oid == null) {
            jdbc.sql("INSERT INTO jupeb.document_blob (document_id, bytes) VALUES (:d, :b)").param("d", doc).param("b", content, Types.BINARY).update();
        }
        old.stream().filter(o -> !o.equals(oid)).forEach(files::forget);
        if (replacing) {
            jdbc.sql("SELECT jupeb.app_event(:a, 'DOCUMENT_REPLACED', :n)").param("a", app).param("n", k + " replaced as the JUPEB Office asked").query().listOfRows();
        }
        return mine(auth);
    }

    /** the leading bytes say what a file is; a renamed file is not taken for what it claims */
    static boolean signatureMatches(String contentType, byte[] b) {
        return switch (contentType) {
            case "application/pdf" -> b.length > 4 && b[0] == '%' && b[1] == 'P' && b[2] == 'D' && b[3] == 'F';
            case "image/jpeg" -> b.length > 3 && (b[0] & 0xFF) == 0xFF && (b[1] & 0xFF) == 0xD8;
            case "image/png" -> b.length > 8 && (b[0] & 0xFF) == 0x89 && b[1] == 'P' && b[2] == 'N' && b[3] == 'G';
            default -> false;
        };
    }

    @DeleteMapping("/documents/{kind}")
    @Transactional
    Map<String, Object> remove(Authentication auth, @PathVariable String kind) {
        UUID app = me(auth);
        requireEditable(app);
        List<UUID> old = jdbc.sql("DELETE FROM jupeb.document WHERE application_id = :a AND kind = :k RETURNING object_id").param("a", app).param("k", kind.trim().toUpperCase())
                .query(UUID.class).list();
        if (old.isEmpty()) throw new NotFound("document", kind);
        old.stream().filter(java.util.Objects::nonNull).forEach(files::forget);
        return mine(auth);
    }

    @GetMapping("/documents/{kind}/content")
    @Transactional(readOnly = true)
    ResponseEntity<byte[]> content(Authentication auth, @PathVariable String kind) {
        return JupebDocuments.stream(jdbc, files, me(auth), kind);
    }

    /* ── paying: the amount is the server's, never the page's ── */

    @PostMapping("/fee-reference")
    @Transactional
    Map<String, Object> feeReference(Authentication auth, @RequestParam String kind) {
        UUID app = me(auth);
        String k = kind.trim().toUpperCase();
        if (!Set.of("APPLICATION", "SCHOOL_FIRST", "SCHOOL_SECOND", "SCHOOL_FULL").contains(k)) throw new NotFound("fee", k);
        String ref = jdbc.sql("SELECT jupeb.new_fee_reference(:a, :k)").param("a", app).param("k", k).query(String.class).single();
        return jdbc.sql("SELECT reference, kind, amount, expires_at, confirmed_at FROM jupeb.fee_reference WHERE reference = :r").param("r", ref).query().singleRow();
    }

    /* ── submitting ── */

    @PostMapping("/submit")
    @Transactional
    Map<String, Object> submit(Authentication auth) {
        UUID app = me(auth);
        jdbc.sql("SELECT jupeb.submit(:a)").param("a", app).query().listOfRows();
        return mine(auth);
    }

    /** the active student registers the three subjects of the approved combination — no other */
    @PostMapping("/register-subjects")
    @Transactional
    Map<String, Object> register(Authentication auth) {
        UUID app = me(auth);
        jdbc.sql("SELECT jupeb.register_subjects(:a, :a)").param("a", app).query(Integer.class).single();
        return mine(auth);
    }

    /* ── support: the University's desk, the JUPEB queue ── */

    private RequesterTickets.Requester requester(UUID app) {
        Map<String, Object> a = jdbc.sql("SELECT surname || ', ' || first_name || coalesce(' ' || middle_name, '') AS name, application_no, email, phone FROM jupeb.application WHERE id = :id")
                .param("id", app).query().singleRow();
        return new RequesterTickets.Requester("JUPEB", app, (String) a.get("name"), (String) a.get("application_no"), (String) a.get("email"), (String) a.get("phone"));
    }

    @GetMapping("/support")
    @Transactional(readOnly = true)
    Map<String, Object> support(Authentication auth) {
        UUID app = me(auth);
        return Map.of("categories", tickets.categories(SUPPORT), "tickets", tickets.mine(requester(app)));
    }

    public record TicketIn(@NotBlank @Size(max = 40) String category, @NotBlank @Size(max = 200) String subject, @NotBlank @Size(max = 8000) String description,
                           Map<String, String> details) {
    }

    @PostMapping("/support")
    @Transactional
    Map<String, Object> raise(Authentication auth, @Valid @RequestBody TicketIn body) {
        UUID app = me(auth);
        return tickets.submit(requester(app), SUPPORT, body.category(), body.subject(), body.description(), body.details());
    }

    @GetMapping("/support/{ticket}")
    @Transactional(readOnly = true)
    Map<String, Object> ticket(Authentication auth, @PathVariable UUID ticket) {
        return tickets.detail(requester(me(auth)), ticket);
    }

    public record Say(@NotBlank @Size(max = 8000) String body) {
    }

    @PostMapping("/support/{ticket}/comments")
    @Transactional
    Map<String, Object> say(Authentication auth, @PathVariable UUID ticket, @Valid @RequestBody Say body) {
        UUID app = me(auth);
        tickets.comment(requester(app), ticket, body.body());
        return tickets.detail(requester(app), ticket);
    }
}
