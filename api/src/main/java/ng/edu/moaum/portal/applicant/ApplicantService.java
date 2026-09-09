package ng.edu.moaum.portal.applicant;

import java.security.SecureRandom;
import java.time.Duration;
import java.time.Instant;
import java.time.OffsetDateTime;
import java.util.ArrayList;
import java.util.Base64;
import java.util.HexFormat;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;
import java.util.function.Supplier;
import java.util.regex.Pattern;

import ng.edu.moaum.portal.auth.TokenIssuer;
import ng.edu.moaum.portal.shared.AuditContext;
import ng.edu.moaum.portal.shared.AuditContextHolder;
import ng.edu.moaum.portal.shared.DomainRuleViolation;
import ng.edu.moaum.portal.shared.NotFound;

import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionTemplate;

/**
 * Post-UTME registration and the applicant's own account: the JAMB number
 * first and, until it is found on the list the Academic Office loaded, the
 * only field. Then sign-in with the same lockout the staff door has, and the
 * application as one view — every fact the Office holds about it, and no
 * score the applicant is not meant to see.
 */
@Service
public class ApplicantService {

    static final Duration SESSION_LENGTH = Duration.ofHours(12);
    static final int LOCK_AFTER = 5;
    static final Duration LOCK_FOR = Duration.ofMinutes(15);
    static final int MIN_PASSWORD = 8;
    static final UUID NOBODY = new UUID(0, 0);
    static final Pattern REG_SHAPE = Pattern.compile("^\\d{12}[A-Z]{2,3}$");
    static final Pattern EMAIL_SHAPE = Pattern.compile("^[^\\s@]+@[^\\s@]+\\.[A-Za-z]{2,}$");
    static final List<String> DOCUMENT_KINDS = List.of("OLEVEL_STATEMENT", "BIRTH_CERT", "LGA_ID", "JAMB_SLIP", "PASSPORT");
    static final int MAX_DOCUMENT = 2 * 1024 * 1024;

    public record SignedIn(String token, Instant expiresAt, UUID accountId, String applicationNo, String surname, String otherNames) {
    }

    private final ApplicantRepository repo;
    private final TokenIssuer issuer;
    private final TransactionTemplate tx;
    private final BCryptPasswordEncoder encoder = new BCryptPasswordEncoder(12);
    private final SecureRandom random = new SecureRandom();

    private final String portalUrl;

    ApplicantService(ApplicantRepository repo, TokenIssuer issuer, PlatformTransactionManager transactions,
                     @org.springframework.beans.factory.annotation.Value("${moaum.portal-url:https://moaum-portal-production.up.railway.app}") String portalUrl) {
        this.repo = repo;
        this.issuer = issuer;
        this.tx = new TransactionTemplate(transactions);
        this.portalUrl = portalUrl == null ? "" : portalUrl.replaceAll("/+$", "");
    }

    /* ── forgotten password (V025): a one-hour token, sent as a notice, kept as a hash, used once ── */

    static String sha256(String s) {
        try {
            byte[] d = java.security.MessageDigest.getInstance("SHA-256").digest(s.getBytes(java.nio.charset.StandardCharsets.UTF_8));
            return HexFormat.of().formatHex(d);
        } catch (java.security.NoSuchAlgorithmException e) {
            throw new IllegalStateException(e);
        }
    }

    /** always accepted, whether or not the identifier names an account — the page cannot be used to list accounts */
    public void forgot(String identifier, String ip) {
        ApplicantRepository.Account a = repo.byIdentifier(identifier).orElse(null);
        atTheDoor(a == null ? null : a.id(), "applicant password reset requested", () -> {
            if (a == null) {
                repo.event(identifier, null, "RESET_UNKNOWN", ip);
                return null;
            }
            byte[] raw = new byte[24];
            random.nextBytes(raw);
            String token = HexFormat.of().formatHex(raw);
            repo.newReset(a.id(), sha256(token), Instant.now().plus(Duration.ofHours(1)));
            String link = portalUrl + "/login/reset?token=" + token;
            repo.queueNotice("EMAIL", a.email(), "Reset your MOAUM application password",
                    "Somebody — we hope you — asked to reset the password of application " + a.applicationNo() + ". Open this link within the hour to choose a new one: "
                            + link + " If you did not ask, ignore this; nothing changes until the link is used.", a.applicationId());
            repo.queueNotice("SMS", a.phone(), "Reset your MOAUM application password",
                    "MOAUM: reset your application password within the hour at " + link, a.applicationId());
            repo.event(identifier, a.id(), "RESET_REQUESTED", ip);
            return null;
        });
    }

    public SignedIn reset(String token, String password, String ip) {
        if (token == null || token.isBlank()) {
            throw new DomainRuleViolation("AUTH_RESET_TOKEN", "The reset link is incomplete.",
                    new DomainRuleViolation.Remedy("Open the link exactly as it was sent, or ask for a new one.", "You"));
        }
        if (password == null || password.length() < MIN_PASSWORD) {
            throw new DomainRuleViolation("APP_PASSWORD_SHORT", "Eight characters at the very least.",
                    new DomainRuleViolation.Remedy("This one account carries you to graduation.", "You"));
        }
        ApplicantRepository.Reset r = repo.resetByHash(sha256(token.trim())).orElse(null);
        if (r == null || r.usedAt() != null || r.expiresAt().isBefore(OffsetDateTime.now())) {
            throw new DomainRuleViolation("AUTH_RESET_TOKEN", "This reset link has expired or was already used.",
                    new DomainRuleViolation.Remedy("Ask for a new one from the sign-in page; it is good for an hour and used once.", "You"));
        }
        String hash = encoder.encode(password);
        ApplicantRepository.Account a = atTheDoor(r.accountId(), "applicant password reset", () -> {
            repo.useReset(r.id());
            repo.setPassword(r.accountId(), hash);
            repo.event("", r.accountId(), "RESET_DONE", ip);
            return repo.byId(r.accountId()).orElseThrow();
        });
        return signIn(a.email(), password, ip);
    }

    /** a transaction attributed to the applicant at the door, opened after the context is placed */
    private <T> T atTheDoor(UUID actor, String reason, Supplier<T> work) {
        return AuditContextHolder.with(new AuditContext(actor == null ? NOBODY : actor, "applicant", reason, null, null),
                () -> tx.execute(status -> work.get()));
    }

    /* ── the number against the list ── */

    @Transactional(readOnly = true)
    public Map<String, Object> lookup(String session, String jambKey) {
        String key = jambKey == null ? "" : jambKey.trim().toUpperCase();
        if (!REG_SHAPE.matcher(key).matches()) {
            return Map.of("state", "idle");
        }
        Map<String, Object> row = repo.lookup(session, key);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("state", row.get("state"));
        if ("found".equals(row.get("state")) || "registered".equals(row.get("state")) || "closed".equals(row.get("state"))) {
            out.put("name", row.get("surname") + ", " + row.get("other_names"));
            out.put("programme", row.get("programme") == null ? row.get("programme_code") : row.get("programme"));
            out.put("list", "DIRECT_ENTRY".equals(row.get("list_kind")) ? "de" : "utme");
        }
        return out;
    }

    /* ── registering ── */

    /** A Nigerian mobile number read any of the three usual ways: 0803…, +234 803…, 803…. */
    static String phone(String v) {
        String d = v == null ? "" : v.replaceAll("[^0-9]", "");
        if (d.length() == 13 && d.startsWith("234")) {
            d = "0" + d.substring(3);
        } else if (d.length() == 10 && !d.startsWith("0")) {
            d = "0" + d;
        }
        return d;
    }

    public SignedIn register(String session, String jambKey, String email, String phoneIn, String password, String ip) {
        String key = jambKey == null ? "" : jambKey.trim().toUpperCase();
        String mail = email == null ? "" : email.trim();
        String phone = phone(phoneIn);
        if (!REG_SHAPE.matcher(key).matches()) {
            throw new DomainRuleViolation("APP_NUMBER_SHAPE", "A JAMB registration number is twelve digits and then two or three letters.",
                    new DomainRuleViolation.Remedy("Copy it from your JAMB slip.", "You"));
        }
        if (!EMAIL_SHAPE.matcher(mail).matches()) {
            throw new DomainRuleViolation("APP_EMAIL", "That is not a complete email address.",
                    new DomainRuleViolation.Remedy("It needs a name, an @, and a domain with a dot in it — you@example.com.", "You"));
        }
        if (!phone.matches("^0\\d{10}$")) {
            throw new DomainRuleViolation("APP_PHONE", "A Nigerian mobile number is eleven digits beginning with a zero.",
                    new DomainRuleViolation.Remedy("Written as +234 or without the zero is fine; " + phone.length() + " digits were read.", "You"));
        }
        if (password == null || password.length() < MIN_PASSWORD) {
            throw new DomainRuleViolation("APP_PASSWORD_SHORT", "Eight characters at the very least.",
                    new DomainRuleViolation.Remedy("This one account carries you to graduation.", "You"));
        }
        String hash = encoder.encode(password);
        UUID account = atTheDoor(null, "Post-UTME registration", () -> repo.register(session, key, mail, phone, hash));
        // the account details go to the email (and phone) the applicant registered with;
        // queued inside an attributed transaction, or the write to platform.notice is refused
        repo.byId(account).ifPresent(a -> atTheDoor(a.id(), "applicant account created", () -> {
            String link = portalUrl + "/login";
            repo.queueNotice("EMAIL", a.email(), "Your MOAUM applicant account",
                    "Welcome to the Rev. Fr. Moses Orshio Adasu University applicant portal.\n\n"
                            + "Your application account has been created:\n"
                            + "  Application number: " + a.applicationNo() + "\n"
                            + "  Sign-in email: " + a.email() + "\n"
                            + "  JAMB registration number: " + a.jambKey() + "\n\n"
                            + "Sign in at " + link + " to pay the Post-UTME screening fee and complete your application. "
                            + "Keep these details safe, and do not create a second account — it invalidates both.", a.applicationId());
            repo.queueNotice("SMS", a.phone(), "MOAUM applicant account",
                    "MOAUM: your applicant account is created. Application no " + a.applicationNo() + ". Sign in at " + link, a.applicationId());
            return null;
        }));
        return signIn(key, password, ip);
    }

    /* ── signing in ── */

    private static DomainRuleViolation badCredentials() {
        return new DomainRuleViolation("AUTH_BAD_CREDENTIALS", "That number and password do not match an application account.",
                new DomainRuleViolation.Remedy("Use your application number, your email or your JAMB number, and the password you chose; five failures lock the account for fifteen minutes.", "Registry"));
    }

    public SignedIn signIn(String identifier, String password, String ip) {
        ApplicantRepository.Account a = repo.byIdentifier(identifier).orElse(null);
        Object outcome = atTheDoor(a == null ? null : a.id(), "applicant sign-in", () -> {
            if (a == null) {
                repo.event(identifier, null, "UNKNOWN", ip);
                return badCredentials();
            }
            if (a.lockedUntil() != null && a.lockedUntil().isAfter(OffsetDateTime.now())) {
                repo.event(identifier, a.id(), "LOCKED", ip);
                return new DomainRuleViolation("AUTH_LOCKED", "This account is locked after repeated failures; try again after "
                        + a.lockedUntil().toLocalTime().withNano(0) + ".",
                        new DomainRuleViolation.Remedy("Wait fifteen minutes.", "You"));
            }
            if (!encoder.matches(password == null ? "" : password, a.passwordHash())) {
                int attempts = a.failedAttempts() + 1;
                repo.failed(a.id(), attempts, attempts >= LOCK_AFTER ? OffsetDateTime.now().plus(LOCK_FOR) : null);
                repo.event(identifier, a.id(), "BAD_PASSWORD", ip);
                return badCredentials();
            }
            byte[] sid = new byte[32];
            random.nextBytes(sid);
            Instant end = Instant.now().plus(SESSION_LENGTH);
            repo.openSession(sid, a.id(), end);
            repo.signedIn(a.id());
            repo.event(identifier, a.id(), "SIGNED_IN", ip);
            String name = a.surname() + ", " + a.otherNames();
            return new SignedIn(issuer.issue(a.id(), name, List.of("applicant"), sid, end), end, a.id(), a.applicationNo(), a.surname(), a.otherNames());
        });
        if (outcome instanceof DomainRuleViolation refused) {
            throw refused;
        }
        return (SignedIn) outcome;
    }

    @Transactional
    public void signOut(UUID account, String sidHex) {
        if (sidHex != null) {
            repo.endSession(HexFormat.of().parseHex(sidHex), account);
        }
    }

    /* ── the application, as one view ── */

    UUID applicationOf(UUID account) {
        return repo.byId(account).orElseThrow(() -> new NotFound("application account", account)).applicationId();
    }

    /**
     * Everything the application is, for the applicant ({@code forOffice} false: no O'Level score, no
     * unreleased score or decision) or for the Academic Office (everything, including what is not yet released).
     */
    @Transactional(readOnly = true)
    public Map<String, Object> view(UUID applicationId, boolean forOffice) {
        Map<String, Object> a = repo.application(applicationId).orElseThrow(() -> new NotFound("application", applicationId));
        String session = String.valueOf(a.get("session"));
        String key = String.valueOf(a.get("jamb_reg_no")).trim().toUpperCase();
        int stage = ((Number) a.get("stage")).intValue();
        Map<String, Object> v = new LinkedHashMap<>();
        v.put("id", a.get("id"));
        v.put("session", session);
        v.put("applicationNo", a.get("application_no"));
        v.put("stage", stage);
        v.put("name", a.get("surname") + ", " + a.get("other_names"));
        v.put("surname", a.get("surname"));
        v.put("otherNames", a.get("other_names"));
        v.put("jambKey", key);
        v.put("programme", a.get("programme"));
        v.put("programmeCode", a.get("programme_code"));
        v.put("faculty", a.get("faculty_name"));
        v.put("entryMode", a.get("entry_mode"));
        v.put("entryLevel", a.get("entry_level"));
        v.put("listKind", a.get("list_kind"));
        v.put("offerState", a.get("offer_state"));
        v.put("email", a.get("email"));
        v.put("phone", a.get("phone"));
        Map<String, Object> bio = new LinkedHashMap<>();
        bio.put("sex", a.get("sex"));
        bio.put("stateOfOrigin", a.get("state_of_origin"));
        bio.put("lga", a.get("lga"));
        bio.put("dateOfBirth", a.get("dob"));
        bio.put("utme", a.get("utme"));
        bio.put("nextOfKin", a.get("next_of_kin"));
        v.put("biodata", bio);

        List<Map<String, Object>> sittings = new ArrayList<>();
        for (Map<String, Object> s : repo.sittings(session, key)) {
            Map<String, Object> st = new LinkedHashMap<>();
            st.put("body", s.get("exam_body"));
            st.put("type", s.get("exam_type_raw"));
            st.put("year", s.get("exam_year"));
            st.put("examNumber", s.get("exam_number"));
            st.put("subjects", Json.list(String.valueOf(s.get("subjects"))));
            sittings.add(st);
        }
        v.put("olevel", sittings);

        Map<String, Object> fees = repo.fees(session);
        v.put("fees", Map.of("applicationFee", fees.get("application_fee"), "portalCharge", fees.get("portal_charge"),
                "acceptanceFee", fees.get("acceptance_fee"), "stated", fees.get("stated")));
        v.put("feeReferences", repo.feeReferences(applicationId));
        v.put("feeConfirmedAt", a.get("fee_confirmed_at"));
        v.put("documents", repo.documents(applicationId));
        v.put("submittedAt", a.get("submitted_at"));

        if (a.get("screening_batch_id") != null) {
            Map<String, Object> slip = new LinkedHashMap<>();
            slip.put("batch", a.get("batch_label"));
            slip.put("heldOn", a.get("held_on"));
            slip.put("startsAt", a.get("starts_at"));
            slip.put("endsAt", a.get("ends_at"));
            slip.put("venue", a.get("venue"));
            slip.put("seat", a.get("seat"));
            v.put("screeningSlip", slip);
        } else {
            v.put("screeningSlip", null);
        }

        boolean scoreVisible = a.get("score_released_at") != null || forOffice;
        v.put("scoreReleasedAt", a.get("score_released_at"));
        if (scoreVisible && (a.get("score_released_at") != null || a.get("screening_batch_id") != null)) {
            Optional<Map<String, Object>> r = repo.screeningResult(applicationId);
            v.put("result", r.map(x -> {
                Map<String, Object> m = new LinkedHashMap<>();
                m.put("utme", x.get("utme"));
                m.put("utmeScaled", x.get("utme_scaled"));
                m.put("screening", x.get("screening"));
                m.put("screeningSource", x.get("screening_source"));
                m.put("weightUtme", x.get("weight_utme"));
                m.put("weightPutme", x.get("weight_putme"));
                m.put("aggregate", x.get("aggregate"));
                m.put("cutoff", x.get("cutoff"));
                m.put("meritPosition", x.get("merit_position"));
                m.put("applied", x.get("applied"));
                m.put("places", x.get("places"));
                return m;
            }).orElse(null));
        } else {
            v.put("result", null);
        }
        if (forOffice) {
            v.put("screeningScore", a.get("screening_score"));
        }

        boolean decisionVisible = a.get("decision_released_at") != null || forOffice;
        v.put("decisionReleasedAt", a.get("decision_released_at"));
        v.put("decision", decisionVisible ? a.get("decision") : null);
        v.put("decisionNote", decisionVisible ? a.get("decision_note") : null);
        v.put("decisionBasis", decisionVisible ? a.get("decision_basis") : null);
        /* the notices sent about this application (V025): what was said, and whether it went */
        v.put("notices", repo.notices(applicationId));
        v.put("undertakingAt", a.get("undertaking_at"));
        v.put("acceptanceConfirmedAt", a.get("acceptance_confirmed_at"));
        v.put("acceptedAt", a.get("accepted_at"));
        v.put("declinedAt", a.get("declined_at"));
        v.put("clearance", repo.clearance(applicationId));
        v.put("clearedAt", a.get("cleared_at"));
        v.put("admissionNo", a.get("admission_no"));
        v.put("matricNo", a.get("matric_no"));
        v.put("studentProgramme", a.get("student_programme"));
        return v;
    }

    @Transactional(readOnly = true)
    public Map<String, Object> me(UUID account) {
        return view(applicationOf(account), false);
    }

    @Transactional
    public Map<String, Object> nextOfKin(UUID account, String text) {
        UUID app = applicationOf(account);
        if (text == null || text.isBlank()) {
            throw new DomainRuleViolation("APP_NEXT_OF_KIN", "The next of kin was not given.",
                    new DomainRuleViolation.Remedy("Name and phone number of the person the University may call.", "You"));
        }
        repo.nextOfKin(app, text.trim());
        return view(app, false);
    }

    @Transactional
    public Map<String, Object> feeReference(UUID account, String kind) {
        UUID app = applicationOf(account);
        String k = kind == null ? "" : kind.trim().toUpperCase();
        if (!k.equals("APPLICATION") && !k.equals("ACCEPTANCE")) {
            throw new DomainRuleViolation("APP_FEE_KIND", "'" + kind + "' is not a fee this portal takes.",
                    new DomainRuleViolation.Remedy("APPLICATION or ACCEPTANCE.", "Directorate of ICT"));
        }
        String reference = repo.newFeeReference(app, k);
        Map<String, Object> out = new LinkedHashMap<>(view(app, false));
        out.put("reference", reference);
        return out;
    }

    @Transactional
    public Map<String, Object> document(UUID account, String kind, String filename, String contentType, String base64) {
        UUID app = applicationOf(account);
        Map<String, Object> a = repo.application(app).orElseThrow();
        /* the passport photograph comes whenever the applicant has one (V022); everything else is part of the declaration */
        if (a.get("submitted_at") != null && !"PASSPORT".equals(kind)) {
            throw new DomainRuleViolation("APP_SUBMITTED", "The application was submitted and can no longer be edited.",
                    new DomainRuleViolation.Remedy("Write to the Registry quoting your application number. The passport photograph can still be replaced.", "Registry"));
        }
        if (kind == null || !DOCUMENT_KINDS.contains(kind)) {
            throw new DomainRuleViolation("APP_DOCUMENT_KIND", "'" + kind + "' is not one of the five documents.",
                    new DomainRuleViolation.Remedy(String.join(", ", DOCUMENT_KINDS) + ".", "Directorate of ICT"));
        }
        if (contentType == null || !List.of("application/pdf", "image/jpeg", "image/png").contains(contentType)) {
            throw new DomainRuleViolation("APP_DOCUMENT_TYPE", "A document is a PDF or a JPEG or PNG image.",
                    new DomainRuleViolation.Remedy("Scan or photograph it as one of those.", "You"));
        }
        byte[] content;
        try {
            content = Base64.getDecoder().decode(base64 == null ? "" : base64);
        } catch (IllegalArgumentException notBase64) {
            throw new DomainRuleViolation("APP_DOCUMENT_ENCODING", "The file did not arrive intact.",
                    new DomainRuleViolation.Remedy("Try the upload again.", "You"));
        }
        if (content.length == 0 || content.length > MAX_DOCUMENT) {
            throw new DomainRuleViolation("APP_DOCUMENT_SIZE", "A document is between 1 byte and 2 MB; this one is " + content.length + " bytes.",
                    new DomainRuleViolation.Remedy("Reduce the scan's resolution and upload it again.", "You"));
        }
        repo.storeDocument(app, kind, filename == null || filename.isBlank() ? kind.toLowerCase() : filename.trim(), contentType, content);
        return view(app, false);
    }

    @Transactional(readOnly = true)
    public DocumentContent documentContent(UUID account, UUID documentId) {
        return repo.documentContent(documentId, applicationOf(account)).orElseThrow(() -> new NotFound("document", documentId));
    }

    /** for the offices: any application's document */
    @Transactional(readOnly = true)
    public DocumentContent anyDocumentContent(UUID documentId) {
        return repo.documentContent(documentId, null).orElseThrow(() -> new NotFound("document", documentId));
    }

    @Transactional
    public Map<String, Object> submit(UUID account, boolean declaration, String ip) {
        UUID app = applicationOf(account);
        if (!declaration) {
            throw new DomainRuleViolation("APP_DECLARATION", "The declaration was not accepted.",
                    new DomainRuleViolation.Remedy("Tick the declaration that the particulars given are true.", "You"));
        }
        repo.submit(app, ip);
        return view(app, false);
    }

    @Transactional
    public Map<String, Object> accept(UUID account, boolean undertaking) {
        UUID app = applicationOf(account);
        if (!undertaking) {
            throw new DomainRuleViolation("APP_UNDERTAKING", "The undertaking was not accepted.",
                    new DomainRuleViolation.Remedy("Read the undertaking and tick that you accept it.", "You"));
        }
        repo.undertaking(app);
        return view(app, false);
    }

    @Transactional
    public Map<String, Object> decline(UUID account) {
        UUID app = applicationOf(account);
        repo.decline(app);
        return view(app, false);
    }

    /** the little JSON the sittings need */
    static final class Json {
        private static final tools.jackson.databind.ObjectMapper MAPPER = new tools.jackson.databind.ObjectMapper();

        static List<Map<String, Object>> list(String text) {
            if (text == null || text.isBlank() || "null".equals(text)) {
                return List.of();
            }
            return MAPPER.readValue(text, new tools.jackson.core.type.TypeReference<List<Map<String, Object>>>() { });
        }
    }
}
