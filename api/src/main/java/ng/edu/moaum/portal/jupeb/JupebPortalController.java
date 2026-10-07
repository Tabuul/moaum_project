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

    private static final tools.jackson.databind.ObjectMapper JSON = new tools.jackson.databind.ObjectMapper();

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
        UUID app = me(auth);
        Map<String, Object> out = new java.util.LinkedHashMap<>(view.of(app, false));
        out.put("combinations", view.combinationsFor(app));
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

    public record Choice(@NotBlank @Pattern(regexp = "(?i)SCIENCE|NON[-_ ]?SCIENCE|ARTS", message = "Science or Non-Science") String stream,
                         @Size(max = 60) String combination) {
    }

    /** Science or Non-Science (V341, V342; an older page's ARTS is Non-Science) */
    static String stream(String raw) {
        String s = raw.trim().toUpperCase().replaceAll("[- ]", "_");
        return "SCIENCE".equals(s) ? "SCIENCE" : "NON_SCIENCE";
    }

    /** the programme, Science or Non-Science, and one offered combination of it, while the application is a draft or returned (V342) */
    @PutMapping("/choice")
    @Transactional
    Map<String, Object> choice(Authentication auth, @Valid @RequestBody Choice c) {
        UUID app = me(auth);
        requireEditable(app);
        jdbc.sql("SELECT jupeb.choose(:id, :s, :c)").param("id", app).param("s", stream(c.stream())).param("c", c.combination(), Types.VARCHAR).query().listOfRows();
        return mine(auth);
    }

    /* ── the O'Level: at most two sittings ── */

    public record Grade(@Min(1) @Max(2) int sitting, @NotBlank @Pattern(regexp = "WAEC|NECO|NABTEB|GCE|OTHER") String examType,
                        @Size(max = 30) String examNumber, Integer examYear, @NotBlank @Size(max = 60) String subject,
                        @NotBlank @Pattern(regexp = "A1|B2|B3|C4|C5|C6|D7|E8|F9|AR") String grade) {
    }

    /** V342: the sittings declared (one or two) and every subject of each */
    public record Olevel(@Min(1) @Max(2) Integer sittings, @NotNull @Size(max = 24) List<@Valid Grade> grades) {
    }

    @PutMapping("/olevel")
    @Transactional
    Map<String, Object> olevel(Authentication auth, @Valid @RequestBody Olevel body) {
        UUID app = me(auth);
        requireEditable(app);
        Set<String> seen = new java.util.HashSet<>();
        int declared = body.sittings() == null ? (int) body.grades().stream().mapToInt(Grade::sitting).distinct().count() : body.sittings();
        for (Grade g : body.grades()) {
            if (g.sitting() > Math.max(declared, 1)) {
                throw new DomainRuleViolation("JUPEB_OLEVEL_SITTINGS", "A result of sitting " + g.sitting() + " is entered, but you declared " + (declared == 1 ? "one sitting" : declared + " sittings") + ".",
                        new DomainRuleViolation.Remedy("Declare two sittings, or remove the second sitting's results.", "You"));
            }
            if (!seen.add(g.sitting() + "|" + g.subject().trim().toUpperCase())) {
                throw new DomainRuleViolation("JUPEB_OLEVEL_TWICE", g.subject().trim() + " appears twice in sitting " + g.sitting() + ".",
                        new DomainRuleViolation.Remedy("Enter each subject once per sitting.", "You"));
            }
            if (g.examYear() != null && (g.examYear() < 1970 || g.examYear() > java.time.Year.now().getValue())) {
                throw new DomainRuleViolation("JUPEB_OLEVEL_YEAR", "The examination year " + g.examYear() + " is not possible.",
                        new DomainRuleViolation.Remedy("Enter the year you sat the examination.", "You"));
            }
        }
        jdbc.sql("UPDATE jupeb.application SET olevel_sittings = :n WHERE id = :id").param("n", declared == 0 ? null : declared, Types.INTEGER).param("id", app).update();
        jdbc.sql("DELETE FROM jupeb.olevel WHERE application_id = :id").param("id", app).update();
        for (Grade g : body.grades()) {
            jdbc.sql("INSERT INTO jupeb.olevel (application_id, sitting, exam_type, exam_number, exam_year, subject, grade) VALUES (:a, :s, :t, :n, :y, :sub, :g)")
                    .param("a", app).param("s", g.sitting()).param("t", g.examType()).param("n", blank(g.examNumber()), Types.VARCHAR)
                    .param("y", g.examYear(), Types.INTEGER).param("sub", g.subject().trim()).param("g", g.grade()).update();
        }
        // a sitting no longer declared takes its O'Level document with it
        jdbc.sql("DELETE FROM jupeb.document WHERE application_id = :id AND kind = 'OLEVEL_RESULT' AND sitting > :n").param("id", app).param("n", Math.max(declared, 1)).update();
        return mine(auth);
    }

    /* ── the documents: private, read back only by their owner and the JUPEB Office ── */

    public record DocumentIn(@NotBlank @Size(max = 200) String filename, @NotBlank @Size(max = 100) String contentType, @NotBlank String base64) {
    }

    /** the sitting an O'Level result is uploaded for (one of those declared); any other document has none */
    private Integer sittingOf(UUID app, String kind, Integer sitting) {
        if (!"OLEVEL_RESULT".equals(kind)) return null;
        int declared = jdbc.sql("SELECT coalesce(olevel_sittings, 1) FROM jupeb.application WHERE id = :id").param("id", app).query(Integer.class).single();
        int s = sitting == null ? 1 : sitting;
        if (s < 1 || s > declared) {
            throw new DomainRuleViolation("JUPEB_DOC_SITTING", "Each O'Level result is uploaded for one of the sittings you declared (" + declared + ").",
                    new DomainRuleViolation.Remedy("Upload the first sitting's result, and the second's if you declared two.", "You"));
        }
        return s;
    }

    @PostMapping("/documents/{kind}")
    @Transactional
    Map<String, Object> upload(Authentication auth, @PathVariable String kind, @RequestParam(required = false) Integer sitting, @Valid @RequestBody DocumentIn body) {
        UUID app = me(auth);
        String k = kind.trim().toUpperCase();
        Map<String, Object> dk = jdbc.sql("SELECT code, image FROM jupeb.document_kind WHERE code = :k AND active").param("k", k).query().listOfRows().stream().findFirst()
                .orElseThrow(() -> new NotFound("document kind", k));
        Integer sit = sittingOf(app, k, sitting);
        String current = jdbc.sql("SELECT status FROM jupeb.document WHERE application_id = :a AND kind = :k AND coalesce(sitting, 0) = coalesce(:s, 0)")
                .param("a", app).param("k", k).param("s", sit, Types.INTEGER).query(String.class).optional().orElse(null);
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
        List<UUID> old = jdbc.sql("SELECT object_id FROM jupeb.document WHERE application_id = :a AND kind = :k AND coalesce(sitting, 0) = coalesce(:s, 0) AND object_id IS NOT NULL")
                .param("a", app).param("k", k).param("s", sit, Types.INTEGER).query(UUID.class).list();
        UUID oid = files.store("jupeb.document", app, body.filename().trim(), ct, content);
        // an O'Level result carries its sitting's examination body and year, from the results entered for that sitting
        UUID doc = jdbc.sql("""
                INSERT INTO jupeb.document (application_id, kind, sitting, exam_body, exam_year, filename, content_type, size_bytes, object_id)
                VALUES (:a, :k, :s,
                        (SELECT o.exam_type FROM jupeb.olevel o WHERE o.application_id = :a AND o.sitting = :s LIMIT 1),
                        (SELECT o.exam_year FROM jupeb.olevel o WHERE o.application_id = :a AND o.sitting = :s LIMIT 1),
                        :fn, :ct, :sz, :o)
                ON CONFLICT (application_id, kind, (coalesce(sitting, 0))) DO UPDATE SET filename = EXCLUDED.filename, content_type = EXCLUDED.content_type,
                       size_bytes = EXCLUDED.size_bytes, object_id = EXCLUDED.object_id, exam_body = EXCLUDED.exam_body, exam_year = EXCLUDED.exam_year,
                       status = 'UPLOADED', review_note = NULL, reviewed_by = NULL, reviewed_at = NULL, uploaded_at = now()
                RETURNING id
                """).param("a", app).param("k", k).param("s", sit, Types.INTEGER).param("fn", body.filename().trim()).param("ct", ct).param("sz", content.length)
                .param("o", oid, Types.OTHER).query(UUID.class).single();
        jdbc.sql("DELETE FROM jupeb.document_blob WHERE document_id = :d").param("d", doc).update();
        if (oid == null) {
            jdbc.sql("INSERT INTO jupeb.document_blob (document_id, bytes) VALUES (:d, :b)").param("d", doc).param("b", content, Types.BINARY).update();
        }
        old.stream().filter(o -> !o.equals(oid)).forEach(files::forget);
        if (replacing) {
            jdbc.sql("SELECT jupeb.app_event(:a, 'DOCUMENT_REPLACED', :n)").param("a", app).param("n", k + (sit == null ? "" : " (sitting " + sit + ")") + " replaced as the JUPEB Office asked").query().listOfRows();
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
    Map<String, Object> remove(Authentication auth, @PathVariable String kind, @RequestParam(required = false) Integer sitting) {
        UUID app = me(auth);
        requireEditable(app);
        List<UUID> old = jdbc.sql("DELETE FROM jupeb.document WHERE application_id = :a AND kind = :k AND coalesce(sitting, 0) = coalesce(:s, 0) RETURNING object_id")
                .param("a", app).param("k", kind.trim().toUpperCase()).param("s", "OLEVEL_RESULT".equalsIgnoreCase(kind.trim()) ? (sitting == null ? 1 : sitting) : null, Types.INTEGER)
                .query(UUID.class).list();
        if (old.isEmpty()) throw new NotFound("document", kind);
        old.stream().filter(java.util.Objects::nonNull).forEach(files::forget);
        return mine(auth);
    }

    @GetMapping("/documents/{kind}/content")
    @Transactional(readOnly = true)
    ResponseEntity<byte[]> content(Authentication auth, @PathVariable String kind, @RequestParam(required = false) Integer sitting,
                                   @RequestParam(required = false) String format) {
        String k = kind.trim().toUpperCase();
        return JupebDocuments.stream(jdbc, files, me(auth), k, "OLEVEL_RESULT".equals(k) ? (sitting == null ? 1 : sitting) : null, "jpeg".equalsIgnoreCase(format));
    }

    /* ── paying: the amount is the server's, never the page's ── */

    @PostMapping("/fee-reference")
    @Transactional
    Map<String, Object> feeReference(Authentication auth, @RequestParam String kind) {
        UUID app = me(auth);
        String k = kind.trim().toUpperCase();
        if (!Set.of("APPLICATION", "STATUS_CHECKING", "ACCEPTANCE", "SCHOOL_FIRST", "SCHOOL_SECOND", "SCHOOL_FULL").contains(k)) throw new NotFound("fee", k);
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

    public record Registration(UUID combination) {
    }

    /** the active student chooses a combination of their stream and registers its three subjects — no other (V341) */
    @PostMapping("/register-subjects")
    @Transactional
    Map<String, Object> register(Authentication auth, @RequestBody(required = false) Registration body) {
        UUID app = me(auth);
        jdbc.sql("SELECT jupeb.register_subjects(:a, :a, :c)").param("a", app).param("c", body == null ? null : body.combination(), Types.OTHER)
                .query(Integer.class).single();
        return mine(auth);
    }

    /* ── the candidate's own password (V345): a temporary one from the JUPEB Office is changed at first sign-in ── */

    public record PasswordIn(@NotBlank @Size(max = 100) String currentPassword, @NotBlank @Size(min = 8, max = 100) String newPassword) {
    }

    private final org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder encoder = new org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder(12);

    @PostMapping("/password")
    @Transactional
    Map<String, Object> password(Authentication auth, @Valid @RequestBody PasswordIn body) {
        UUID app = me(auth);
        Map<String, Object> acc = jdbc.sql("SELECT acc.id, acc.password_hash FROM jupeb.account acc JOIN jupeb.application a ON a.account_id = acc.id WHERE a.id = :a")
                .param("a", app).query().singleRow();
        if (!encoder.matches(body.currentPassword(), String.valueOf(acc.get("password_hash")))) {
            throw new DomainRuleViolation("JUPEB_PASSWORD_CURRENT", "The current password is not right.",
                    new DomainRuleViolation.Remedy("Type the password you signed in with (the temporary one, if the JUPEB Office gave you one).", "You"));
        }
        if (body.newPassword().equals(body.currentPassword())) {
            throw new DomainRuleViolation("JUPEB_PASSWORD_SAME", "Choose a password different from the one you signed in with.",
                    new DomainRuleViolation.Remedy("At least eight characters, different from the temporary one.", "You"));
        }
        jdbc.sql("UPDATE jupeb.account SET password_hash = :h, must_change_password = false, failed_attempts = 0, locked_until = NULL, temp_expires_at = NULL, temp_issued_by = NULL, temp_used_at = NULL WHERE id = :id")
                .param("h", encoder.encode(body.newPassword())).param("id", acc.get("id")).update();
        return mine(auth);
    }

    /* ── verifiable papers (V343): the code a paper's QR carries, issued by the server for the record as it stands ── */

    public record PaperIn(@NotBlank @Pattern(regexp = "RESULT|ADMISSION_LETTER|ACCEPTANCE_LETTER|STATUS_SLIP|REGISTRATION_SLIP|ACKNOWLEDGEMENT|RECEIPT") String kind,
                          @Size(max = 60) String reference) {
    }

    @PostMapping("/papers")
    @Transactional
    Map<String, Object> paper(Authentication auth, @Valid @RequestBody PaperIn body) {
        UUID app = me(auth);
        String code = jdbc.sql("SELECT jupeb.issue_paper(:a, :k, :r, false, :a, 'applicant')").param("a", app).param("k", body.kind())
                .param("r", body.reference(), Types.VARCHAR).query(String.class).single();
        return Map.of("code", code, "kind", body.kind());
    }

    /* ── change requests after submission (V343): withdraw, defer, change the combination or the programme — the JUPEB Office decides ── */

    public record ChangeIn(@NotBlank @Pattern(regexp = "WITHDRAW|DEFER|CHANGE_COMBINATION|CHANGE_PROGRAMME") String kind, @Size(max = 20) String stream,
                           @Size(max = 60) String combination, @Size(max = 9) String toSession, @NotBlank @Size(max = 1000) String reason) {
    }

    @PostMapping("/requests")
    @Transactional
    Map<String, Object> request(Authentication auth, @Valid @RequestBody ChangeIn body) {
        UUID app = me(auth);
        jdbc.sql("SELECT jupeb.request_change(:a, :k, :s, :c, :t, :r, :a, 'applicant')").param("a", app).param("k", body.kind())
                .param("s", body.stream(), Types.VARCHAR).param("c", body.combination(), Types.VARCHAR).param("t", body.toSession(), Types.VARCHAR)
                .param("r", body.reason()).query(UUID.class).single();
        return mine(auth);
    }

    @PostMapping("/requests/{id}/cancel")
    @Transactional
    Map<String, Object> cancelRequest(Authentication auth, @PathVariable UUID id) {
        UUID app = me(auth);
        jdbc.sql("SELECT jupeb.cancel_change(:r, :a, :a)").param("r", id).param("a", app).query().listOfRows();
        return mine(auth);
    }

    /* ── the student's own attendance (V342): subject by subject, from the University's attendance engine ── */

    @GetMapping("/attendance")
    @Transactional(readOnly = true)
    Map<String, Object> attendance(Authentication auth, @RequestParam(required = false) String session) {
        UUID app = me(auth);
        Map<String, Object> out = new java.util.LinkedHashMap<>();
        out.put("subjects", jdbc.sql("""
                SELECT m.session, m.semester, s.code, s.title, m.total, m.present, m.absent, m.late, m.excused, m.rate, m.min_percent, m.verdict,
                       m.counted, m.at_risk, m.warnable
                  FROM attendance.member_summary('JUPEB', :a, :s) m JOIN jupeb.subject s ON s.id = m.subject_ref
                 ORDER BY m.session DESC, m.semester, s.title
                """).param("a", app).param("s", blank(session), Types.VARCHAR).query().listOfRows());
        out.put("recent", jdbc.sql("""
                SELECT r.held_on, r.session, r.semester, s.code, s.title, k.status, k.marked_time::text AS marked_time, k.remarks
                  FROM attendance.mark k JOIN attendance.register r ON r.id = k.register_id JOIN jupeb.subject s ON s.id = r.subject_ref
                 WHERE r.context = 'JUPEB' AND k.member_ref = :a ORDER BY r.held_on DESC, s.title LIMIT 200
                """).param("a", app).query().listOfRows());
        return out;
    }

    /* ── V347: the student keeps their own contact details; a change of identity is a request the JUPEB Office decides ── */

    public record ContactIn(@Pattern(regexp = "^(0[0-9]{10})?$", message = "an eleven-digit Nigerian number") String phone,
                            @Size(max = 300) String contactAddress, @Size(max = 300) String permanentAddress,
                            @Size(max = 120) String guardianName, @Pattern(regexp = "^(0[0-9]{10})?$", message = "an eleven-digit Nigerian number") String guardianPhone,
                            @Size(max = 300) String guardianAddress, @Size(max = 120) String nextOfKinName,
                            @Pattern(regexp = "^(0[0-9]{10})?$", message = "an eleven-digit Nigerian number") String nextOfKinPhone,
                            @Size(max = 60) String nextOfKinRelationship) {
    }

    private static final String[][] CONTACT = {
            {"phone", "phone"}, {"contact_address", "contact address"}, {"permanent_address", "permanent address"}, {"guardian_name", "guardian"},
            {"guardian_phone", "guardian's phone"}, {"guardian_address", "guardian's address"}, {"next_of_kin_name", "next of kin"},
            {"next_of_kin_phone", "next of kin's phone"}, {"next_of_kin_relationship", "next of kin's relationship"}};

    /** the contact details, at any time: what changed is on the record's trail; the phone is never blanked */
    @PutMapping("/contact")
    @Transactional
    Map<String, Object> contact(Authentication auth, @Valid @RequestBody ContactIn b) {
        UUID app = me(auth);
        if ("WITHDRAWN".equals(state(app))) {
            throw new DomainRuleViolation("JUPEB_WITHDRAWN", "A withdrawn application is not changed.", new DomainRuleViolation.Remedy("Ask the JUPEB Office.", "JUPEB Office"));
        }
        Map<String, Object> before = jdbc.sql("SELECT phone, contact_address, permanent_address, guardian_name, guardian_phone, guardian_address, next_of_kin_name, next_of_kin_phone, next_of_kin_relationship FROM jupeb.application WHERE id = :id")
                .param("id", app).query().singleRow();
        Map<String, String> next = new java.util.LinkedHashMap<>();
        next.put("phone", blank(b.phone()));
        next.put("contact_address", blank(b.contactAddress()));
        next.put("permanent_address", blank(b.permanentAddress()));
        next.put("guardian_name", blank(b.guardianName()));
        next.put("guardian_phone", blank(b.guardianPhone()));
        next.put("guardian_address", blank(b.guardianAddress()));
        next.put("next_of_kin_name", blank(b.nextOfKinName()));
        next.put("next_of_kin_phone", blank(b.nextOfKinPhone()));
        next.put("next_of_kin_relationship", blank(b.nextOfKinRelationship()));
        if (next.get("phone") == null) {
            throw new DomainRuleViolation("JUPEB_PHONE_REQUIRED", "Keep a phone number on your record.", new DomainRuleViolation.Remedy("Enter it as 08012345678.", "You"));
        }
        List<String> changed = new java.util.ArrayList<>();
        for (String[] f : CONTACT) {
            if (!java.util.Objects.equals(before.get(f[0]) == null ? null : String.valueOf(before.get(f[0])), next.get(f[0]))) changed.add(f[1]);
        }
        if (changed.isEmpty()) return mine(auth);
        jdbc.sql("""
                UPDATE jupeb.application SET phone = :phone, contact_address = :ca, permanent_address = :pa, guardian_name = :gn, guardian_phone = :gp,
                       guardian_address = :ga, next_of_kin_name = :kn, next_of_kin_phone = :kp, next_of_kin_relationship = :kr WHERE id = :id
                """).param("phone", next.get("phone")).param("ca", next.get("contact_address"), Types.VARCHAR).param("pa", next.get("permanent_address"), Types.VARCHAR)
                .param("gn", next.get("guardian_name"), Types.VARCHAR).param("gp", next.get("guardian_phone"), Types.VARCHAR).param("ga", next.get("guardian_address"), Types.VARCHAR)
                .param("kn", next.get("next_of_kin_name"), Types.VARCHAR).param("kp", next.get("next_of_kin_phone"), Types.VARCHAR).param("kr", next.get("next_of_kin_relationship"), Types.VARCHAR)
                .param("id", app).update();
        jdbc.sql("SELECT jupeb.app_event(:a, 'CONTACT_UPDATED', :n)").param("a", app).param("n", "Updated by the student: " + String.join(", ", changed)).query().listOfRows();
        return mine(auth);
    }

    public record CorrectionIn(@jakarta.validation.constraints.NotNull Map<String, String> changes, @NotBlank @Size(max = 1000) String reason) {
    }

    /** name, sex, date of birth, NIN, nationality, state or LGA: asked of the JUPEB Office, applied only when it approves */
    @PostMapping("/corrections")
    @Transactional
    Map<String, Object> correction(Authentication auth, @Valid @RequestBody CorrectionIn body) {
        UUID app = me(auth);
        jdbc.sql("SELECT jupeb.request_correction(:a, :c::jsonb, :r, :a, 'applicant')").param("a", app)
                .param("c", JSON.writeValueAsString(body.changes())).param("r", body.reason()).query(UUID.class).single();
        return mine(auth);
    }

    /* ── V347: the timetable and the practice tests ── */

    /** the week's lectures of the student's subjects, for their class (and the slots for every class) */
    @GetMapping("/timetable")
    @Transactional(readOnly = true)
    Map<String, Object> timetable(Authentication auth, @RequestParam(required = false) Integer semester) {
        UUID app = me(auth);
        Map<String, Object> a = jdbc.sql("SELECT session, class_id FROM jupeb.application WHERE id = :id").param("id", app).query().singleRow();
        Map<String, Object> out = new java.util.LinkedHashMap<>();
        out.put("session", a.get("session"));
        out.put("semester", jdbc.sql("SELECT jupeb.current_semester(:s, NULL)").param("s", a.get("session")).query(Integer.class).single());
        out.put("slots", jdbc.sql("""
                SELECT t.id, t.semester, t.weekday, to_char(t.starts_at, 'HH24:MI') AS starts_at, to_char(t.ends_at, 'HH24:MI') AS ends_at, t.venue, t.note,
                       s.code, s.title, k.name AS class_name, t.course_code, t.practical,
                       (SELECT string_agg(p.surname || ', ' || p.given_names, '; ' ORDER BY p.surname) FROM attendance.instructor i JOIN iam.person p ON p.id = i.person_id
                         WHERE i.context = 'JUPEB' AND i.session = t.session AND i.subject_ref = t.subject_id AND i.ended_at IS NULL
                           AND (i.class_ref IS NULL OR i.class_ref = :class)) AS instructors
                  FROM jupeb.timetable_slot t JOIN jupeb.subject s ON s.id = t.subject_id LEFT JOIN jupeb.class k ON k.id = t.class_id
                 WHERE t.active AND t.session = :ses AND (:sem::int IS NULL OR t.semester = :sem)
                   AND (t.class_id IS NULL OR t.class_id = :class)
                   AND t.subject_id IN (SELECT subject_id FROM jupeb.practice_subjects(:app))
                 ORDER BY t.semester, t.weekday, t.starts_at
                """).param("ses", a.get("session")).param("sem", semester, Types.INTEGER).param("class", a.get("class_id"), Types.OTHER).param("app", app)
                .query().listOfRows());
        /* V351: the programme's day — its first and last hour and the hours no lecture uses (BREAK) — from the whole timetable, not only this student's
           subjects, so an hour free for them alone is not called a break */
        out.put("frames", jdbc.sql("""
                SELECT t.semester, t.lo AS "from", t.hi AS "to",
                       (SELECT string_agg(h::text, ',' ORDER BY h) FROM generate_series(t.lo, t.hi - 1) h
                         WHERE NOT EXISTS (SELECT 1 FROM jupeb.timetable_slot x WHERE x.session = :ses AND x.active AND x.semester = t.semester
                                             AND x.starts_at < make_time(h + 1, 0, 0) AND make_time(h, 0, 0) < x.ends_at)) AS breaks
                  FROM (SELECT semester, min(extract(hour FROM starts_at))::int AS lo, max(ceil(extract(epoch FROM ends_at) / 3600))::int AS hi
                          FROM jupeb.timetable_slot WHERE session = :ses AND active GROUP BY semester) t
                 ORDER BY t.semester
                """).param("ses", a.get("session")).query().listOfRows().stream().map(r -> {
                    Map<String, Object> f = new java.util.LinkedHashMap<>(r);
                    Object b = r.get("breaks");
                    f.put("breaks", b == null ? List.of() : java.util.Arrays.stream(b.toString().split(",")).map(Integer::valueOf).toList());
                    return f;
                }).toList());
        return out;
    }

    /* ── V354: the session calendar's dates for students, and the student's own clearance for the examination ── */

    @GetMapping("/calendar")
    @Transactional(readOnly = true)
    Map<String, Object> calendar(Authentication auth) {
        UUID app = me(auth);
        String s = jdbc.sql("SELECT session FROM jupeb.application WHERE id = :a").param("a", app).query(String.class).single();
        Map<String, Object> out = new java.util.LinkedHashMap<>();
        out.put("session", s);
        out.put("today", jdbc.sql("SELECT (now() AT TIME ZONE 'Africa/Lagos')::date::text").query(String.class).single());
        out.put("events", jdbc.sql("""
                SELECT starts_on::text AS starts_on, ends_on::text AS ends_on, title, deadline_on::text AS deadline_on, deadline_note, marker, planned
                  FROM jupeb.calendar_event WHERE session = :s AND for_students AND removed_at IS NULL ORDER BY starts_on, ord
                """).param("s", s).query().listOfRows());
        return out;
    }

    /** the student's own standing against what sitting the examination needs — only an active student has one */
    @GetMapping("/clearance")
    @Transactional(readOnly = true)
    Map<String, Object> clearance(Authentication auth) {
        UUID app = me(auth);
        return jdbc.sql("""
                SELECT c.cleared, c.checks::text AS checks, c.exam_no FROM jupeb.application a CROSS JOIN LATERAL jupeb.exam_clearance(a.session) c
                 WHERE a.id = :a AND c.application_id = :a
                """).param("a", app).query().listOfRows().stream().findFirst().map(r -> {
                    Map<String, Object> m = new java.util.LinkedHashMap<>(r);
                    m.put("checks", JupebView.readJson(String.valueOf(r.get("checks"))));
                    return m;
                }).orElseThrow(() -> new NotFound("examination clearance", app));
    }

    /* ── V353: the student's courses, as the Board's syllabus has them ── */

    /** the courses of the student's subjects (or of the combination chosen, before registration), semester by semester */
    @GetMapping("/units")
    @Transactional(readOnly = true)
    Map<String, Object> units(Authentication auth) {
        UUID app = me(auth);
        Map<String, Object> out = new java.util.LinkedHashMap<>();
        out.put("units", jdbc.sql("SELECT * FROM jupeb.units_for((SELECT combination_id FROM jupeb.application WHERE id = :a), :a)").param("a", app).query().listOfRows());
        out.put("syllabus", jdbc.sql("""
                SELECT y.title FROM jupeb.syllabus y JOIN jupeb.application a ON a.id = :a AND a.session BETWEEN y.first_session AND y.last_session
                 ORDER BY y.first_session DESC LIMIT 1
                """).param("a", app).query(String.class).optional().orElse(null));
        return out;
    }

    /** a course unit's syllabus — only of the student's own courses; another's is not found */
    @GetMapping("/units/{id}/syllabus")
    @Transactional(readOnly = true)
    Map<String, Object> unitSyllabus(Authentication auth, @PathVariable UUID id) {
        UUID app = me(auth);
        boolean mine = jdbc.sql("SELECT EXISTS (SELECT 1 FROM jupeb.units_for((SELECT combination_id FROM jupeb.application WHERE id = :a), :a) u WHERE u.unit_id = :u)")
                .param("a", app).param("u", id).query(Boolean.class).single();
        if (!mine) throw new NotFound("course unit", id);
        return JupebView.unitSyllabus(jdbc, id);
    }

    public record OptionIn(@jakarta.validation.constraints.NotNull UUID subjectId, @jakarta.validation.constraints.NotNull UUID boardSubjectId) {
    }

    /** of an either/or subject, the one the student sits — theirs to choose until their examination number is assigned */
    @PutMapping("/subject-option")
    @Transactional
    Map<String, Object> subjectOption(Authentication auth, @Valid @RequestBody OptionIn b) {
        UUID app = me(auth);
        jdbc.sql("SELECT jupeb.choose_option(:a, :s, :b, false, NULL)").param("a", app).param("s", b.subjectId()).param("b", b.boardSubjectId()).query().listOfRows();
        return mine(auth);
    }

    /** the practice tests of the student's subjects, with the attempts left and the best score */
    @GetMapping("/practice")
    @Transactional(readOnly = true)
    Map<String, Object> practice(Authentication auth) {
        UUID app = me(auth);
        return Map.of("tests", jdbc.sql("""
                SELECT t.id, t.title, t.instructions, t.duration_minutes, t.questions_per_attempt, t.attempts_allowed, t.show_answers, s.code, s.title AS subject,
                       (SELECT count(*) FROM jupeb.practice_question q WHERE q.test_id = t.id AND q.active) AS questions,
                       (SELECT count(*) FROM jupeb.practice_attempt p WHERE p.test_id = t.id AND p.application_id = :app) AS used,
                       (SELECT max(p.percentage) FROM jupeb.practice_attempt p WHERE p.test_id = t.id AND p.application_id = :app AND p.submitted_at IS NOT NULL) AS best,
                       (SELECT p.id FROM jupeb.practice_attempt p WHERE p.test_id = t.id AND p.application_id = :app AND p.submitted_at IS NULL) AS open_attempt,
                       (SELECT coalesce(jsonb_agg(jsonb_build_object('id', p.id, 'number', p.number, 'submittedAt', p.submitted_at, 'score', p.score, 'total', p.total,
                                                                     'percentage', p.percentage) ORDER BY p.number), '[]'::jsonb)::text
                          FROM jupeb.practice_attempt p WHERE p.test_id = t.id AND p.application_id = :app AND p.submitted_at IS NOT NULL) AS attempts
                  FROM jupeb.practice_test t JOIN jupeb.subject s ON s.id = t.subject_id
                 WHERE t.open AND t.subject_id IN (SELECT subject_id FROM jupeb.practice_subjects(:app))
                 ORDER BY s.code, t.title
                """).param("app", app).query().listOfRows());
    }

    private Map<String, Object> paper(UUID app, UUID attempt) {
        return JSON.readValue(jdbc.sql("SELECT jupeb.practice_paper(:a, :t)::text").param("a", app).param("t", attempt).query(String.class).single(),
                new tools.jackson.core.type.TypeReference<Map<String, Object>>() { });
    }

    @PostMapping("/practice/{test}/start")
    @Transactional
    Map<String, Object> startPractice(Authentication auth, @PathVariable UUID test) {
        UUID app = me(auth);
        UUID attempt = jdbc.sql("SELECT jupeb.practice_start(:a, :t)").param("a", app).param("t", test).query(UUID.class).single();
        return paper(app, attempt);
    }

    @GetMapping("/practice/attempts/{attempt}")
    @Transactional
    Map<String, Object> practiceAttempt(Authentication auth, @PathVariable UUID attempt) {
        return paper(me(auth), attempt);
    }

    public record ChoiceIn(@Size(max = 1) String choice) {
    }

    @PutMapping("/practice/attempts/{attempt}/answers/{question}")
    @Transactional
    Map<String, Object> answerPractice(Authentication auth, @PathVariable UUID attempt, @PathVariable UUID question, @Valid @RequestBody ChoiceIn body) {
        UUID app = me(auth);
        jdbc.sql("SELECT jupeb.practice_answer_set(:a, :t, :q, :c)").param("a", app).param("t", attempt).param("q", question).param("c", body.choice(), Types.VARCHAR).query().listOfRows();
        return Map.of("saved", true);
    }

    @PostMapping("/practice/attempts/{attempt}/submit")
    @Transactional
    Map<String, Object> submitPractice(Authentication auth, @PathVariable UUID attempt) {
        UUID app = me(auth);
        jdbc.sql("SELECT jupeb.practice_submit(:a, :t)").param("a", app).param("t", attempt).query().listOfRows();
        return paper(app, attempt);
    }

    /* ── V349: the JUPEB Office's announcements, a question's image inside an attempt, the identity card ── */

    /** the notices that reach the candidate now: pinned first, newest next, each marked read or not */
    @GetMapping("/announcements")
    @Transactional(readOnly = true)
    Map<String, Object> announcements(Authentication auth) {
        UUID app = me(auth);
        return Map.of("announcements", jdbc.sql("""
                SELECT n.id, n.title, n.body, n.pinned, n.published_at, n.expires_on, r.read_at IS NOT NULL AS read
                  FROM jupeb.announcement n JOIN jupeb.application a ON a.id = :a
                  LEFT JOIN jupeb.announcement_read r ON r.announcement_id = n.id AND r.application_id = a.id
                 WHERE n.withdrawn_at IS NULL AND (n.expires_on IS NULL OR n.expires_on >= (now() AT TIME ZONE 'Africa/Lagos')::date)
                   AND jupeb.audience_reaches(n.session, n.audience, n.audience_ref, a)
                 ORDER BY n.pinned DESC, n.published_at DESC LIMIT 200
                """).param("a", app).query().listOfRows());
    }

    @PostMapping("/announcements/{id}/read")
    @Transactional
    Map<String, Object> readAnnouncement(Authentication auth, @PathVariable UUID id) {
        UUID app = me(auth);
        int n = jdbc.sql("""
                INSERT INTO jupeb.announcement_read (announcement_id, application_id)
                SELECT x.id, a.id FROM jupeb.announcement x JOIN jupeb.application a ON a.id = :a
                 WHERE x.id = :n AND x.withdrawn_at IS NULL AND jupeb.audience_reaches(x.session, x.audience, x.audience_ref, a)
                ON CONFLICT DO NOTHING
                """).param("a", app).param("n", id).update();
        if (n == 0 && !Boolean.TRUE.equals(jdbc.sql("SELECT EXISTS (SELECT 1 FROM jupeb.announcement_read WHERE announcement_id = :n AND application_id = :a)")
                .param("n", id).param("a", app).query(Boolean.class).single())) {
            throw new NotFound("announcement", id);
        }
        return Map.of("read", true);
    }

    /* ── V350: the account a refund of a withdrawn candidate's fees is paid into ── */

    public record RefundDetailsIn(@NotBlank @Size(min = 2, max = 120) String bankName, @NotBlank @Size(min = 2, max = 200) String accountName,
                                  @NotBlank @Pattern(regexp = "^[0-9]{10}$", message = "the ten-digit account number (NUBAN)") String accountNumber) {
    }

    /** given once the claim is open, and changed until the Bursary raises a refund to it (after a rejected one, again) */
    @PutMapping("/refund-details")
    @Transactional
    Map<String, Object> refundDetails(Authentication auth, @Valid @RequestBody RefundDetailsIn b) {
        UUID app = me(auth);
        Map<String, Object> c = jdbc.sql("""
                SELECT c.id, c.declined_at, EXISTS (SELECT 1 FROM jupeb.refund_claim_refund x JOIN finance.refund f ON f.id = x.refund_id
                                                     WHERE x.claim_id = c.id AND f.state <> 'REJECTED') AS raised
                  FROM jupeb.refund_claim c WHERE c.application_id = :a
                """).param("a", app).query().listOfRows().stream().findFirst()
                .orElseThrow(() -> new DomainRuleViolation("JUPEB_REFUND_CLAIM", "There is no refund claim on your record.",
                        new DomainRuleViolation.Remedy("A claim opens when a withdrawal takes effect after fees were paid on the portal.", "JUPEB Office")));
        if (c.get("declined_at") != null) {
            throw new DomainRuleViolation("JUPEB_REFUND_DECLINED", "The Bursary declined this refund claim.", new DomainRuleViolation.Remedy("Ask the Bursary if you disagree.", "Bursary"));
        }
        if (Boolean.TRUE.equals(c.get("raised"))) {
            throw new DomainRuleViolation("JUPEB_REFUND_LOCKED", "The Bursary has already raised a refund to the account you gave.",
                    new DomainRuleViolation.Remedy("Ask the Bursary to change it.", "Bursary"));
        }
        jdbc.sql("UPDATE jupeb.refund_claim SET bank_name = :b, account_name = :n, account_number = :x, details_at = now() WHERE id = :id")
                .param("b", b.bankName().trim()).param("n", b.accountName().trim()).param("x", b.accountNumber()).param("id", c.get("id")).update();
        jdbc.sql("SELECT jupeb.app_event(:a, 'REFUND_DETAILS_GIVEN', 'Account for a refund given by the candidate')").param("a", app).query().listOfRows();
        return mine(auth);
    }

    /** a question's image, only inside an attempt of the student's that drew the question */
    @GetMapping("/practice/attempts/{attempt}/questions/{question}/image")
    @Transactional(readOnly = true)
    ResponseEntity<byte[]> practiceImage(Authentication auth, @PathVariable UUID attempt, @PathVariable UUID question) {
        UUID app = me(auth);
        if (!Boolean.TRUE.equals(jdbc.sql("SELECT jupeb.practice_image_visible(:a, :t, :q)").param("a", app).param("t", attempt).param("q", question).query(Boolean.class).single())) {
            throw new NotFound("question image", question);
        }
        return JupebPracticeImages.stream(jdbc, files, question);
    }

    /** the identity card's code, issued like the other JUPEB papers; an active student with a passport photograph on file has one */
    @PostMapping("/id-card")
    @Transactional
    Map<String, Object> idCard(Authentication auth) {
        UUID app = me(auth);
        Map<String, Object> a = jdbc.sql("""
                SELECT a.state, EXISTS (SELECT 1 FROM jupeb.document d WHERE d.application_id = a.id AND d.kind = 'PASSPORT') AS photo
                  FROM jupeb.application a WHERE a.id = :a
                """).param("a", app).query().singleRow();
        if (!List.of("STUDENT", "COMPLETED").contains(String.valueOf(a.get("state")))) {
            throw new DomainRuleViolation("JUPEB_ID_CARD_NOT_YET", "The identity card is for an active JUPEB student.",
                    new DomainRuleViolation.Remedy("It opens once your school fee activates your studentship.", "You"));
        }
        if (!Boolean.TRUE.equals(a.get("photo"))) {
            throw new DomainRuleViolation("JUPEB_ID_CARD_PHOTO", "The card carries your passport photograph, and none is on file.",
                    new DomainRuleViolation.Remedy("Ask the JUPEB Office to put your passport photograph on your record.", "JUPEB Office"));
        }
        String code = jdbc.sql("SELECT jupeb.issue_paper(:a, 'ID_CARD', NULL, false, :a, 'applicant')").param("a", app).query(String.class).single();
        return jdbc.sql("SELECT code, issued_at, issued_office FROM jupeb.paper WHERE code = :c").param("c", code).query().singleRow();
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
