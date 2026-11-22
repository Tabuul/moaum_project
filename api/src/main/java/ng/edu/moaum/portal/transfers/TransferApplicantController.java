package ng.edu.moaum.portal.transfers;

import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import java.sql.Types;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.UUID;

import jakarta.servlet.http.HttpServletRequest;
import jakarta.validation.Valid;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

import ng.edu.moaum.portal.shared.CheckCodes;
import ng.edu.moaum.portal.shared.ClientAddress;
import ng.edu.moaum.portal.shared.DomainRuleViolation;
import ng.edu.moaum.portal.shared.FileObjects;
import ng.edu.moaum.portal.shared.NotFound;

import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.Authentication;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.TransactionDefinition;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionTemplate;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * V766: the inter-university transfer applicant's own portal. Every token of an applicant carries the same office ("applicant"), so the
 * office says nothing of which applicant it is: each endpoint finds the account in admissions.iut_account from the token's subject and
 * answers 404 when there is none — a Post-UTME, postgraduate or JUPEB applicant's token reaches nothing here. The application is the
 * account's latest. Every act is the database's (admissions.iut_update, iut_fee_reference_draw, iut_add_document, iut_remove_document,
 * iut_submit, iut_withdraw, iut_apply for applying again), each checking again that the application is the token's own (IUT_NOT_YOURS)
 * under the request's own audit context: the account, office applicant. The fee is paid through the gateways every applicant fee uses
 * (POST /api/v1/payments/checkout on the reference drawn here).
 */
@RestController
@RequestMapping("/api/v1/transfer-applications/me")
@PreAuthorize("hasAuthority('OFFICE_applicant')")
class TransferApplicantController {

    static final String PURPOSE = "Inter-university transfer application fee";

    private final JdbcClient jdbc;
    private final FileObjects files;
    private final TransferApplicationFiles documents;
    private final CheckCodes codes;
    private final TransactionTemplate tx;
    private final TransactionTemplate nested;
    private final tools.jackson.databind.ObjectMapper json;
    private final BCryptPasswordEncoder encoder = new BCryptPasswordEncoder(12);

    TransferApplicantController(JdbcClient jdbc, FileObjects files, TransferApplicationFiles documents, CheckCodes codes,
                                PlatformTransactionManager transactions, tools.jackson.databind.ObjectMapper json) {
        this.jdbc = jdbc;
        this.files = files;
        this.documents = documents;
        this.codes = codes;
        this.tx = new TransactionTemplate(transactions);
        this.nested = new TransactionTemplate(transactions);
        this.nested.setPropagationBehavior(TransactionDefinition.PROPAGATION_NESTED);
        this.json = json;
    }

    @SuppressWarnings("unchecked")
    private Map<String, Object> parse(String text) {
        return text == null ? new LinkedHashMap<>() : new LinkedHashMap<>(json.readValue(text, Map.class));
    }

    /** the account of the token: a transfer applicant's own, else nothing here is theirs (404) */
    private UUID account(Authentication auth) {
        UUID subject = UUID.fromString(auth.getName());
        return jdbc.sql("SELECT id FROM admissions.iut_account WHERE id = :s").param("s", subject).query(UUID.class).optional()
                .orElseThrow(() -> new NotFound("transfer application account", subject));
    }

    /** the account's latest application */
    private UUID application(UUID account) {
        return jdbc.sql("SELECT id FROM admissions.iut_application WHERE account_id = :a ORDER BY created_at DESC LIMIT 1").param("a", account)
                .query(UUID.class).optional().orElseThrow(() -> new NotFound("transfer application of the account", account));
    }

    private Map<String, Object> view(UUID app) {
        return parse(jdbc.sql("SELECT admissions.iut_view(:a, 'APPLICANT')::text").param("a", app).query(String.class).single());
    }

    /** the latest application as the applicant reads it (admissions.iut_view APPLICANT), with the account's e-mail and phone, every
     *  application of the account, and whether the account may apply again now: its latest application refused or withdrawn, a window
     *  open, and no application of the account in that window's session (admissions.iut_apply's own rule) */
    @GetMapping
    @Transactional(readOnly = true)
    Map<String, Object> me(Authentication auth) {
        UUID account = account(auth);
        UUID app = application(account);
        Map<String, Object> out = view(app);
        out.put("account", jdbc.sql("SELECT email, phone FROM admissions.iut_account WHERE id = :a").param("a", account).query().singleRow());
        // D11: each application's state as the applicant reads it (a recommendation, a decline and an approval: WITH_REGISTRY), as the view
        out.put("applications", jdbc.sql("""
                SELECT id, application_no AS "applicationNo", session, admissions.iut_state_shown(state) AS state
                  FROM admissions.iut_application WHERE account_id = :a ORDER BY created_at DESC
                """).param("a", account).query().listOfRows());
        Map<String, Object> again = jdbc.sql("""
                SELECT o.s AS open_session,
                       coalesce(l.state IN ('REJECTED', 'WITHDRAWN') AND o.s IS NOT NULL
                                AND NOT EXISTS (SELECT 1 FROM admissions.iut_application x WHERE x.account_id = :a AND x.session = o.s), false) AS may
                  FROM (SELECT admissions.iut_open_session() AS s) o
                  LEFT JOIN LATERAL (SELECT x.state FROM admissions.iut_application x WHERE x.account_id = :a ORDER BY x.created_at DESC LIMIT 1) l ON true
                """).param("a", account).query().singleRow();
        out.put("canApplyAgain", again.get("may"));
        out.put("openSession", again.get("open_session"));
        return out;
    }

    /** a change to the application: every field optional; a field not sent is not changed (admissions.iut_update, which says what the
     *  state lets change: everything in a draft but the window's own refusal, the particulars when returned for a correction, the e-mail
     *  and phone until it is decided) */
    public record Update(@Size(max = 60) String surname, @Size(max = 120) String otherNames, @Pattern(regexp = "M|F") String sex,
                         @Size(max = 10) String dateOfBirth, @Size(max = 200) String email, @Size(max = 20) String phone, @Size(max = 20) String jambRegNo,
                         @Size(max = 16) String universityCode, @Size(max = 200) String universityNamed, @Size(max = 40) String otherMatricNo,
                         @Size(max = 200) String otherProgramme, @Min(100) @Max(900) Integer otherLevel, @Size(max = 9) String otherEntrySession,
                         @Size(max = 4) String otherCgpa, @Min(4) @Max(5) Integer otherCgpaScale, @Size(max = 20) String programme,
                         @Min(100) @Max(900) Integer level, @Size(max = 2000) String reason) {

        Map<String, Object> given() {
            Map<String, Object> p = new LinkedHashMap<>();
            p.put("surname", surname); p.put("otherNames", otherNames); p.put("sex", sex); p.put("dateOfBirth", dateOfBirth);
            p.put("email", email); p.put("phone", phone); p.put("jambRegNo", jambRegNo);
            p.put("universityCode", universityCode); p.put("universityNamed", universityNamed);
            p.put("otherMatricNo", otherMatricNo); p.put("otherProgramme", otherProgramme); p.put("otherLevel", otherLevel);
            p.put("otherEntrySession", otherEntrySession); p.put("otherCgpa", otherCgpa); p.put("otherCgpaScale", otherCgpaScale);
            p.put("programme", programme); p.put("level", level); p.put("reason", reason);
            p.values().removeIf(Objects::isNull);
            return p;
        }
    }

    @PutMapping
    @Transactional
    Map<String, Object> update(Authentication auth, @Valid @RequestBody Update body) {
        UUID app = application(account(auth));
        return parse(jdbc.sql("SELECT admissions.iut_update(:a, CAST(:p AS jsonb))::text").param("a", app).param("p", json.writeValueAsString(body.given()))
                .query(String.class).single());
    }

    /** applying again in a later window, once the last application is refused or withdrawn: the public form's fields but the e-mail, the
     *  phone and the password, which the account keeps */
    public record Again(@NotBlank @Size(max = 60) String surname, @NotBlank @Size(max = 120) String otherNames, @Pattern(regexp = "M|F") String sex,
                        @NotBlank @Size(max = 10) String dateOfBirth, @NotBlank @Size(max = 20) String jambRegNo,
                        @Size(max = 16) String universityCode, @Size(max = 200) String universityNamed, @NotBlank @Size(max = 40) String otherMatricNo,
                        @NotBlank @Size(max = 200) String otherProgramme, @NotNull @Min(100) @Max(900) Integer otherLevel,
                        @NotBlank @Size(max = 9) String otherEntrySession, @NotBlank @Size(max = 4) String otherCgpa,
                        @NotNull @Min(4) @Max(5) Integer otherCgpaScale, @NotBlank @Size(max = 20) String programme,
                        @NotNull @Min(100) @Max(900) Integer level, @NotBlank @Size(max = 2000) String reason) {

        Map<String, Object> particulars() {
            return new Update(surname, otherNames, sex, dateOfBirth, null, null, jambRegNo, universityCode, universityNamed, otherMatricNo, otherProgramme,
                    otherLevel, otherEntrySession, otherCgpa, otherCgpaScale, programme, level, reason).given();
        }
    }

    /** a new application of the account in the window open now (admissions.iut_apply with the account): {accountId, applicationId,
     *  applicationNo, session, feeDue} */
    @PostMapping("/applications")
    @Transactional
    Map<String, Object> applyAgain(Authentication auth, @Valid @RequestBody Again body) {
        UUID account = account(auth);
        return parse(jdbc.sql("SELECT admissions.iut_apply(CAST(:p AS jsonb), NULL, :acc)::text").param("p", json.writeValueAsString(body.particulars()))
                .param("acc", account).query(String.class).single());
    }

    /** the application fee's reference to pay: the open one for the fee in force, else a new one for 24 hours; {settled:true, due:0}
     *  when no fee is charged */
    @PostMapping("/fee-reference")
    @Transactional
    Map<String, Object> feeReference(Authentication auth) {
        UUID app = application(account(auth));
        return parse(jdbc.sql("SELECT admissions.iut_fee_reference_draw(:a)::text").param("a", app).query(String.class).single());
    }

    /** a confirmed payment of the account's own, as its receipt prints it, with the code signed over the reference for the receipt's
     *  QR (the public verification page answers it, as every applicant's receipt) */
    @GetMapping("/receipts/{reference}")
    @Transactional(readOnly = true)
    Map<String, Object> receipt(Authentication auth, @PathVariable String reference) {
        UUID account = account(auth);
        Map<String, Object> r = jdbc.sql("""
                SELECT f.receipt_no AS "receiptNo", f.reference, f.amount, f.confirmed_at AS "paidAt", f.channel,
                       a.application_no AS "applicationNo", a.surname || ', ' || a.other_names AS name, a.session, f.settles
                  FROM admissions.iut_fee_reference f JOIN admissions.iut_application a ON a.id = f.application_id
                 WHERE a.account_id = :acc AND f.reference = upper(btrim(:r)) AND f.confirmed_at IS NOT NULL
                """).param("acc", account).param("r", reference).query().listOfRows().stream().findFirst()
                .orElseThrow(() -> new NotFound("receipt", reference));
        Map<String, Object> out = new LinkedHashMap<>(r);
        out.put("purpose", PURPOSE);
        out.put("checkCode", codes.sign(CheckCodes.Kind.APPLICANT_RECEIPT, String.valueOf(r.get("reference"))));
        return out;
    }

    /** a document uploaded: {kind, filename, dataUrl}; up to 5 MB of PDF, JPEG or PNG, its first bytes the type it claims */
    public record DocumentIn(@NotBlank @Size(max = 40) String kind, @NotBlank @Size(max = 200) String filename, @NotBlank @Size(max = 7_100_000) String dataUrl) {
    }

    /** the file read and checked (TransferApplicationFiles.read), kept in the file store when one is configured (else in the database),
     *  and recorded by admissions.iut_add_document, which replaces the kind's current document (kept, superseded) — after the fee, in a
     *  draft or an application returned for a correction. Refused by the database, the object stored for it is forgotten. */
    @PostMapping("/documents")
    @Transactional
    Map<String, Object> upload(Authentication auth, @Valid @RequestBody DocumentIn body) {
        UUID app = application(account(auth));
        TransferApplicationFiles.Read f = TransferApplicationFiles.read(body.dataUrl());
        String filename = body.filename().trim();
        UUID oid = files.store("admissions.iut_document", app, filename, f.contentType(), f.bytes());
        try {
            // a savepoint: the database's refusal leaves the transaction able to forget the object just stored
            nested.execute(st -> jdbc.sql("SELECT admissions.iut_add_document(:a, :k, :fn, :ct, :n, :h, :o, :c)")
                    .param("a", app).param("k", body.kind().trim()).param("fn", filename).param("ct", f.contentType()).param("n", f.bytes().length)
                    .param("h", f.sha256()).param("o", oid, Types.OTHER).param("c", oid == null ? f.bytes() : null, Types.BINARY)
                    .query(UUID.class).single());
        } catch (RuntimeException refused) {
            files.forget(oid);
            throw refused;
        }
        return view(app);
    }

    /** a document of the account's application — current or superseded — streamed back to the applicant */
    @GetMapping("/documents/{id}")
    @Transactional(readOnly = true)
    ResponseEntity<byte[]> document(Authentication auth, @PathVariable UUID id) {
        UUID account = account(auth);
        UUID app = jdbc.sql("""
                SELECT d.application_id FROM admissions.iut_document d JOIN admissions.iut_application a ON a.id = d.application_id
                 WHERE d.id = :d AND a.account_id = :acc
                """).param("d", id).param("acc", account).query(UUID.class).optional().orElseThrow(() -> new NotFound("document", id));
        return documents.stream(app, id);
    }

    /** a current document taken off (kept, superseded) while the application is a draft or returned for a correction */
    @DeleteMapping("/documents/{id}")
    @Transactional
    Map<String, Object> remove(Authentication auth, @PathVariable UUID id) {
        UUID app = application(account(auth));
        jdbc.sql("SELECT admissions.iut_remove_document(:a, :d)").param("a", app).param("d", id).query().listOfRows();
        return view(app);
    }

    public record Submit(Boolean declaration) {
    }

    /** submitted under the declaration: the fee settled, every required document there and none rejected (admissions.iut_submit) */
    @PostMapping("/submit")
    @Transactional
    Map<String, Object> submit(Authentication auth, @RequestBody Submit body, HttpServletRequest request) {
        UUID app = application(account(auth));
        if (body == null || !Boolean.TRUE.equals(body.declaration())) {
            throw new DomainRuleViolation("IUT_DECLARATION", "The application is submitted with the declaration ticked.",
                    new DomainRuleViolation.Remedy("Tick the declaration that the particulars and documents you have given are true, then submit.", "You"));
        }
        return parse(jdbc.sql("SELECT admissions.iut_submit(:a, :ip)::text").param("a", app).param("ip", ClientAddress.of(request), Types.VARCHAR)
                .query(String.class).single());
    }

    public record Withdraw(@Size(max = 500) String reason) {
    }

    /** withdrawn at the applicant's request until the department has assessed it (a draft, submitted, returned for correction or with the
     *  department); with the Registry for a decision (recommended, declined or approved alike, D11) it is asked of the Registry, which
     *  ends it by its rejection (admissions.iut_withdraw) */
    @PostMapping("/withdraw")
    @Transactional
    Map<String, Object> withdraw(Authentication auth, @Valid @RequestBody(required = false) Withdraw body) {
        UUID app = application(account(auth));
        String reason = body == null || body.reason() == null || body.reason().isBlank() ? null : body.reason().trim();
        return parse(jdbc.sql("SELECT admissions.iut_withdraw(:a, :r)::text").param("a", app).param("r", reason, Types.VARCHAR).query(String.class).single());
    }

    /** the acknowledgement of a submitted application: who applied, from where, for what, the documents sent and the fee, with the code
     *  signed over the application number for its QR — it attests the submission only, never a state or a decision */
    @GetMapping("/acknowledgement")
    @Transactional(readOnly = true)
    Map<String, Object> acknowledgement(Authentication auth) {
        UUID app = application(account(auth));
        Map<String, Object> v = view(app);
        if (v.get("submittedAt") == null) {
            throw new DomainRuleViolation("IUT_STATE", "The acknowledgement is printed once the application is submitted.",
                    new DomainRuleViolation.Remedy("Submit the application first; the acknowledgement follows.", "You"));
        }
        String no = String.valueOf(v.get("applicationNo"));
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("applicationNo", no);
        out.put("session", v.get("session"));
        out.put("submittedAt", v.get("submittedAt"));
        out.put("lastSubmittedAt", v.get("lastSubmittedAt"));
        out.put("applicant", v.get("applicant"));
        out.put("previous", v.get("previous"));
        out.put("applied", v.get("applied"));
        List<Map<String, Object>> docs = new ArrayList<>();
        if (v.get("documents") instanceof List<?> l) {
            for (Object o : l) {
                if (o instanceof Map<?, ?> d) {
                    Map<String, Object> x = new LinkedHashMap<>();
                    x.put("label", d.get("label"));
                    x.put("filename", d.get("filename"));
                    docs.add(x);
                }
            }
        }
        out.put("documents", docs);
        out.put("fee", jdbc.sql("""
                SELECT a.fee_basis AS basis, f.receipt_no AS "receiptNo", f.amount
                  FROM admissions.iut_application a LEFT JOIN admissions.iut_fee_reference f ON f.application_id = a.id AND f.settles
                 WHERE a.id = :a
                """).param("a", app).query().singleRow());
        String code = codes.sign(CheckCodes.Kind.IUT_ACKNOWLEDGEMENT, no);
        out.put("checkCode", code);
        // the number in the query, never the path: its slashes encoded (%2F) are refused by the request firewall, on the page's call too
        out.put("verifyPath", "/verify/transfer-application?no=" + URLEncoder.encode(no, StandardCharsets.UTF_8) + "&t=" + code);
        return out;
    }

    public record PasswordIn(@NotBlank @Size(max = 200) String current, @NotBlank @Size(max = 200) String next) {
    }

    /** the password changed: the current one first, then a new one of eight characters or more that is not the account's JAMB or
     *  application number; every other open session of the account ends with the old password (V687's rule for applicants), the one
     *  making the change kept */
    @PostMapping("/password")
    Map<String, Object> password(Authentication auth, @Valid @RequestBody PasswordIn body) {
        UUID account = account(auth);
        String hash = jdbc.sql("SELECT password_hash FROM admissions.iut_account WHERE id = :a").param("a", account).query(String.class).single();
        if (!encoder.matches(body.current(), hash)) {
            throw new DomainRuleViolation("AUTH_BAD_CREDENTIALS", "The password you have now is not the one entered.",
                    new DomainRuleViolation.Remedy("Enter the password you signed in with.", "You"));
        }
        List<String> numbers = jdbc.sql("""
                SELECT unnest(ARRAY[a.jamb_reg_no, a.application_no]) FROM admissions.iut_application a WHERE a.account_id = :acc
                """).param("acc", account).query(String.class).list();
        TransferApplicationPublicController.checkPassword(body.next(), numbers);
        String chosen = encoder.encode(body.next());
        byte[] keep = sessionOf(auth);
        tx.execute(st -> {
            jdbc.sql("UPDATE admissions.iut_account SET password_hash = :h, password_changed_at = now(), failed_attempts = 0, locked_until = NULL WHERE id = :a")
                    .param("h", chosen).param("a", account).update();
            return jdbc.sql("""
                    UPDATE platform.session SET ended_at = now(), ended_reason = 'password changed'
                     WHERE person_id = :a AND ended_at IS NULL AND (CAST(:keep AS bytea) IS NULL OR id <> CAST(:keep AS bytea))
                    """).param("a", account).param("keep", keep, Types.BINARY).update();
        });
        return Map.of("changed", true);
    }

    /** the session the token was issued for (its "sid" claim, hex), or null */
    private static byte[] sessionOf(Authentication auth) {
        String sid = auth instanceof org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken t ? t.getToken().getClaimAsString("sid") : null;
        if (sid == null || sid.isBlank()) return null;
        try {
            return java.util.HexFormat.of().parseHex(sid);
        } catch (IllegalArgumentException notHex) {
            return null;
        }
    }
}
