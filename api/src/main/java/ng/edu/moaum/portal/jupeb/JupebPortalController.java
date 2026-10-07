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
        jdbc.sql("UPDATE jupeb.account SET password_hash = :h, must_change_password = false, failed_attempts = 0, locked_until = NULL WHERE id = :id")
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
