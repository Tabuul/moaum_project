package ng.edu.moaum.portal.staff;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.security.SecureRandom;
import java.sql.Types;
import java.util.Base64;
import java.util.HexFormat;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.UUID;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

import ng.edu.moaum.portal.shared.AuditContextHolder;
import ng.edu.moaum.portal.shared.DomainRuleViolation;
import ng.edu.moaum.portal.shared.FileObjects;
import ng.edu.moaum.portal.shared.NotFound;
import ng.edu.moaum.portal.shared.PhotoEnhancer;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.CacheControl;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionTemplate;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import tools.jackson.databind.ObjectMapper;

/**
 * V749: a member of staff's own identity information — the University's brief of 12 November 2026, "UPDATE STAFF IDENTITY
 * INFORMATION": the blood group confirmed; the e-mail address verified by a six-digit code sent to it (iam.email_code_issue /
 * email_code_check: three codes an hour, fifteen minutes each, five tries, the old address kept until the code is right, never an
 * address another person holds), as V575's ContactConfirmController does for a student; the photograph uploaded, assessed and
 * enhanced on the server ({@link PhotoEnhancer}), the original kept beside the enhanced copy, and made the card photograph only when
 * the holder accepts it. Done is all three (iam.staff_identity_state).
 *
 * <p>Always the signed-in person's own: the person is the token's subject, never a path id; a photograph's id is the only id taken,
 * and the database answers PHOTO_NOT_YOURS for one that is not theirs. Files go where every other file goes (FileObjects, owner
 * hrm.staff_photo_submission and the person's id) and are served back only here, no-store.
 */
@RestController
@RequestMapping("/api/v1/staff/identity")
@PreAuthorize("isAuthenticated() and !hasAuthority('OFFICE_student') and !hasAuthority('OFFICE_applicant')")
class StaffIdentityController {

    private static final Logger LOG = LoggerFactory.getLogger(StaffIdentityController.class);
    private static final SecureRandom RANDOM = new SecureRandom();
    /** the owner the uploads are kept under in the file store */
    private static final String OWNER = "hrm.staff_photo_submission";

    public record BloodGroupIn(@Size(max = 20) String bloodGroup, Boolean confirmed) {
    }

    public record EmailIn(@NotBlank @Size(max = 320) String email) {
    }

    public record CodeIn(@NotBlank @Size(max = 12) String code) {
    }

    /** a photograph as every upload arrives: base64 in JSON (a data URL's header is read past); the type is what the bytes say */
    public record PhotoIn(@Size(max = 40) String contentType, @NotBlank String dataBase64) {
    }

    private final JdbcClient jdbc;
    private final FileObjects files;
    private final PhotoEnhancer enhancer;
    private final ObjectMapper json;
    /** the photograph's two short transactions (upload and retry): the image is worked between them */
    private final TransactionTemplate tx;

    StaffIdentityController(JdbcClient jdbc, FileObjects files, PhotoEnhancer enhancer, ObjectMapper json, PlatformTransactionManager transactions) {
        this.jdbc = jdbc;
        this.files = files;
        this.enhancer = enhancer;
        this.json = json;
        this.tx = new TransactionTemplate(transactions);
    }

    private static UUID me() {
        return AuditContextHolder.required().actorId();
    }

    /** where the person stands: in service, the photograph, the e-mail, the blood group, and whether all three are done */
    @GetMapping
    @Transactional(readOnly = true)
    Map<String, Object> state() {
        return state(me());
    }

    private Map<String, Object> state(UUID person) {
        return parse(jdbc.sql("SELECT iam.staff_identity_state(:p)::text").param("p", person).query(String.class).single());
    }

    /* ── the blood group ───────────────────────────────────────────────────────────────────────────────────────────────────── */

    /** the person's own blood group, saved and confirmed — one of the eight exactly, "I confirm …" ticked; a member of staff in the
     *  University's service only (V698's reading) */
    @PutMapping("/blood-group")
    @Transactional
    Map<String, Object> bloodGroup(@Valid @RequestBody BloodGroupIn in) {
        Map<String, Object> out = parse(jdbc.sql("SELECT credentials.confirm_my_blood_group(:g, :c)::text")
                .param("g", in.bloodGroup(), Types.VARCHAR).param("c", in.confirmed(), Types.BOOLEAN).query(String.class).single());
        out.put("identity", state(me()));
        return out;
    }

    /* ── the e-mail address ────────────────────────────────────────────────────────────────────────────────────────────────── */

    /** a six-digit code sent to the new address; the address is the person's only once the code comes back (the old one stands until
     *  then). The code is made here and kept only as its hash. An address another person holds verified is refused — after the
     *  transaction commits, so the refused try is kept and counts among the hour's three (whose an address is never comes free).
     *  The code's e-mail is filed against the code (about_kind 'email_verification', the iam.email_verification row), never against the
     *  person who asked: the portal never lists it back to anyone (platform.person_notices), so the code proves the mailbox and nothing
     *  else; its words leave the outbox once it has gone (V749's trg_notice_code_scrubbed) */
    @PostMapping("/email/code")
    Map<String, Object> emailCode(@Valid @RequestBody EmailIn in) {
        UUID person = me();
        String code = String.format("%06d", RANDOM.nextInt(1_000_000));
        Map<String, Object> out = tx.execute(status -> {
            Map<String, Object> issued = parse(jdbc.sql("SELECT iam.email_code_issue(:e, :h)::text").param("e", in.email().trim()).param("h", sha256(code))
                    .query(String.class).single());
            if (!"ISSUED".equals(issued.get("outcome"))) {
                return issued;
            }
            String to = String.valueOf(issued.get("email"));
            jdbc.sql("SELECT platform.queue_notice('EMAIL', :to, :sub, :b, 'email_verification', :v, NULL, 'STAFF_EMAIL_CODE', 'HIGH')")
                    .param("to", to).param("sub", "Your MOAUM verification code")
                    .param("b", "Your code to verify this e-mail address on your MOAUM portal staff record is " + code + ". It works for fifteen minutes.\n\n"
                            + "Enter it on the portal where you asked for it. If you did not ask for it, ignore this message: the address is not added "
                            + "to your record, and nothing changes.")
                    .param("v", UUID.fromString(String.valueOf(issued.get("id")))).query().listOfRows();
            Map<String, Object> sent = new LinkedHashMap<>();
            sent.put("sentTo", to);
            sent.put("minutes", 15);
            sent.put("identity", state(person));
            return sent;
        });
        if ("TAKEN".equals(out.get("outcome"))) {
            throw new DomainRuleViolation("IDENTITY_EMAIL_TAKEN", "This e-mail address is another person's, verified on their record; give an address that is yours alone.",
                    new DomainRuleViolation.Remedy("Give an address that is yours alone. If this one is yours, ask the Directorate of ICT to look at the record that holds it.",
                            "Directorate of ICT"));
        }
        return out;
    }

    /** the code entered: VERIFIED (the address is the person's from now), WRONG (a try used, five at most), EXPIRED, or TAKEN (another
     *  person holds the address now) — answered, never refused, so the try is counted */
    @PostMapping("/email/verify")
    @Transactional
    Map<String, Object> emailVerify(@Valid @RequestBody CodeIn in) {
        UUID person = me();
        String outcome = jdbc.sql("SELECT iam.email_code_check(:h)").param("h", sha256(in.code().trim())).query(String.class).single();
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("outcome", outcome);
        out.put("identity", state(person));
        return out;
    }

    /* ── the photograph ────────────────────────────────────────────────────────────────────────────────────────────────────── */

    /** a photograph uploaded: read safely (a file that is not a JPEG or a PNG, too large, damaged or a print file is refused and nothing
     *  is kept), assessed and enhanced; the original kept always, the enhanced copy beside it — PROCESSED, waiting for the holder to
     *  accept it — or FAILED with the reason, to be retried. The image is worked between short transactions, never inside one: a
     *  connection is not held while a photograph is decoded (or waits its turn to be). Who may upload and the hour's twenty are asked
     *  first, before the upload is even read; the files are kept in the store in a transaction of their own, so that when the database
     *  then refuses the upload they are taken back out rather than left where nothing reaches them. A file refused as it is read is
     *  counted among the twenty all the same (REFUSED): reading it was work, and a damaged file free to send again would keep both
     *  of the enhancer's places busy */
    @PostMapping("/photo")
    Map<String, Object> upload(@Valid @RequestBody PhotoIn in) {
        UUID person = me();
        // a member of staff on the register, under the hour's twenty, before any work (PHOTO_NOT_STAFF, PHOTO_UPLOAD_LIMIT otherwise)
        tx.execute(status -> jdbc.sql("SELECT hrm.staff_photo_upload_allowed()").query(UUID.class).single());
        byte[] bytes = base64(in.dataBase64());
        PhotoEnhancer.Enhanced e = enhance(bytes, null);
        String type = PhotoEnhancer.sniff(bytes);
        UUID[] stored = tx.execute(status -> new UUID[] {
                files.store(OWNER, person, "image/jpeg".equals(type) ? "original.jpg" : "original.png", type, bytes),
                e.jpeg() == null ? null : files.store(OWNER, person, "enhanced.jpg", "image/jpeg", e.jpeg())});
        UUID original = stored[0];
        UUID enhanced = stored[1];
        try {
            return tx.execute(status -> {
                UUID id = jdbc.sql("""
                        SELECT hrm.add_my_staff_photo_submission(:ot, :ob, :oc, :oo, :ec, :eo, :ew, :eh, CAST(:a AS jsonb), CAST(:x AS jsonb), :q, :err)
                        """).param("ot", type).param("ob", bytes.length)
                        .param("oc", original == null ? bytes : null, Types.BINARY).param("oo", original, Types.OTHER)
                        .param("ec", enhanced == null ? e.jpeg() : null, Types.BINARY).param("eo", enhanced, Types.OTHER)
                        .param("ew", e.jpeg() == null ? null : e.width(), Types.INTEGER).param("eh", e.jpeg() == null ? null : e.height(), Types.INTEGER)
                        .param("a", json.writeValueAsString(e.assessment().toMap())).param("x", json.writeValueAsString(e.enhancement()))
                        .param("q", e.assessment().quality()).param("err", e.error(), Types.VARCHAR)
                        .query(UUID.class).single();
                return submission(id, person);
            });
        } catch (RuntimeException refused) {
            forget(original, enhanced);
            throw refused;
        }
    }

    /** one of the person's own uploads: its state, verdict, readings, what was done and why it failed (not the images) */
    @GetMapping("/photo/{id}")
    @Transactional(readOnly = true)
    Map<String, Object> photo(@PathVariable UUID id) {
        return submission(id, me());
    }

    /** the original as uploaded — the holder's own only */
    @GetMapping("/photo/{id}/original")
    @Transactional(readOnly = true)
    ResponseEntity<byte[]> original(@PathVariable UUID id) {
        return jdbc.sql("SELECT original_type, original_content, original_object FROM hrm.staff_photo_submission WHERE id = :id AND person_id = :p")
                .param("id", id).param("p", me()).query().listOfRows().stream().findFirst()
                .map(r -> image(files.resolve((byte[]) r.get("original_content"), (UUID) r.get("original_object")), String.valueOf(r.get("original_type"))))
                .orElseGet(() -> ResponseEntity.notFound().build());
    }

    /** the enhanced copy (a JPEG) — the holder's own only; none for an upload whose enhancement failed */
    @GetMapping("/photo/{id}/enhanced")
    @Transactional(readOnly = true)
    ResponseEntity<byte[]> enhanced(@PathVariable UUID id) {
        return jdbc.sql("SELECT enhanced_content, enhanced_object FROM hrm.staff_photo_submission WHERE id = :id AND person_id = :p")
                .param("id", id).param("p", me()).query().listOfRows().stream().findFirst()
                .filter(r -> r.get("enhanced_content") != null || r.get("enhanced_object") != null)
                .map(r -> image(files.resolve((byte[]) r.get("enhanced_content"), (UUID) r.get("enhanced_object")), "image/jpeg"))
                .orElseGet(() -> ResponseEntity.notFound().build());
    }

    /** the enhancement done again on the original kept — an upload not yet decided (PROCESSED or FAILED); the image worked between
     *  transactions as an upload is, the last asking again that it is still undecided. A retry counts with the uploads, twenty an hour */
    @PostMapping("/photo/{id}/retry")
    Map<String, Object> retry(@PathVariable UUID id) {
        UUID person = me();
        // the holder's own, not yet decided, under the hour's twenty — or the refusal that says why not (PHOTO_NOT_YOURS, PHOTO_STATE,
        // PHOTO_UPLOAD_LIMIT) — before the original is read or worked
        byte[] bytes = tx.execute(status -> {
            Map<String, Object> row = jdbc.sql("""
                    SELECT s.original_content, s.original_object FROM hrm.my_staff_photo_submission(:id, ARRAY['PROCESSED', 'FAILED']) s
                    """).param("id", id).query().singleRow();
            jdbc.sql("SELECT hrm.staff_photo_upload_allowed()").query(UUID.class).single();
            return files.resolve((byte[]) row.get("original_content"), (UUID) row.get("original_object"));
        });
        PhotoEnhancer.Enhanced e = enhance(bytes, id);
        UUID enhanced = e.jpeg() == null ? null : tx.execute(status -> files.store(OWNER, person, "enhanced.jpg", "image/jpeg", e.jpeg()));
        try {
            return tx.execute(status -> {
                jdbc.sql("SELECT hrm.update_my_staff_photo_submission(:id, :ec, :eo, :ew, :eh, CAST(:a AS jsonb), CAST(:x AS jsonb), :q, :err)")
                        .param("id", id)
                        .param("ec", enhanced == null ? e.jpeg() : null, Types.BINARY).param("eo", enhanced, Types.OTHER)
                        .param("ew", e.jpeg() == null ? null : e.width(), Types.INTEGER).param("eh", e.jpeg() == null ? null : e.height(), Types.INTEGER)
                        .param("a", json.writeValueAsString(e.assessment().toMap())).param("x", json.writeValueAsString(e.enhancement()))
                        .param("q", e.assessment().quality()).param("err", e.error(), Types.VARCHAR)
                        .query(String.class).single();
                return submission(id, person);
            });
        } catch (RuntimeException refused) {
            forget(enhanced);
            throw refused;
        }
    }

    /** the enhanced copy accepted: the card photograph from now (the one it replaces kept on the upload); never one judged REPLACE */
    @PostMapping("/photo/{id}/accept")
    @Transactional
    Map<String, Object> accept(@PathVariable UUID id) {
        Map<String, Object> out = parse(jdbc.sql("SELECT hrm.accept_my_staff_photo(:id)::text").param("id", id).query(String.class).single());
        out.put("identity", state(me()));
        return out;
    }

    /** an upload set aside (the original stays kept) */
    @PostMapping("/photo/{id}/discard")
    @Transactional
    Map<String, Object> discard(@PathVariable UUID id) {
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("id", id);
        out.put("state", jdbc.sql("SELECT hrm.discard_my_staff_photo(:id)").param("id", id).query(String.class).single());
        out.put("identity", state(me()));
        return out;
    }

    /** the card photograph on record, as a JPEG (a PNG set the old way is turned into one) */
    @GetMapping("/photo/current")
    @Transactional(readOnly = true)
    ResponseEntity<byte[]> current() {
        return jdbc.sql("SELECT content, object_id FROM hrm.staff_photo WHERE person_id = :p").param("p", me()).query().listOfRows().stream().findFirst()
                .map(r -> files.resolve((byte[]) r.get("content"), (UUID) r.get("object_id")))
                .filter(b -> b != null && b.length > 0)
                .map(b -> {
                    byte[] jpeg = PhotoEnhancer.toJpeg(b, enhancer.settings().quality());
                    return image(jpeg, "image/jpeg".equals(PhotoEnhancer.sniff(jpeg)) ? "image/jpeg" : "image/png");
                })
                .orElseGet(() -> ResponseEntity.notFound().build());
    }

    /* ── helpers ───────────────────────────────────────────────────────────────────────────────────────────────────────────── */

    /** the photograph read, assessed and enhanced; a file refused as it is read is recorded (REFUSED, counted among the hour's twenty,
     *  in a transaction of its own since the refusal undoes the request's) and the refusal answered as it came. PHOTO_BUSY alone is not
     *  counted: the file was not read, only kept waiting for a place */
    private PhotoEnhancer.Enhanced enhance(byte[] bytes, UUID retryOf) {
        try {
            return enhancer.enhance(bytes);
        } catch (PhotoEnhancer.Refused refused) {
            if (!"PHOTO_BUSY".equals(refused.code())) {
                try {
                    tx.executeWithoutResult(status -> jdbc.sql("SELECT hrm.record_my_staff_photo_refusal(:c, :b, :s)")
                            .param("c", refused.code()).param("b", bytes == null ? 0 : bytes.length).param("s", retryOf, Types.OTHER).query().singleRow());
                } catch (RuntimeException notRecorded) {
                    LOG.warn("staff photograph: a refused file ({}) was not counted: {}", refused.code(), notRecorded.getMessage());
                }
            }
            throw refused;
        }
    }

    private Map<String, Object> submission(UUID id, UUID person) {
        Map<String, Object> r = jdbc.sql("""
                SELECT id, state, quality, error, original_type, original_bytes, enhanced_width, enhanced_height,
                       assessment::text AS assessment, enhancement::text AS enhancement, created_at, decided_at,
                       (enhanced_content IS NOT NULL OR enhanced_object IS NOT NULL) AS has_enhanced
                  FROM hrm.staff_photo_submission WHERE id = :id AND person_id = :p
                """).param("id", id).param("p", person).query().listOfRows().stream().findFirst()
                // another person's upload is answered as one that does not exist, as its images are
                .orElseThrow(() -> new NotFound("staff photograph", id));
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("id", r.get("id"));
        out.put("state", r.get("state"));
        out.put("quality", r.get("quality"));
        out.put("error", r.get("error"));
        out.put("originalType", r.get("original_type"));
        out.put("originalBytes", r.get("original_bytes"));
        out.put("width", r.get("enhanced_width"));
        out.put("height", r.get("enhanced_height"));
        out.put("hasEnhanced", r.get("has_enhanced"));
        out.put("assessment", r.get("assessment") == null ? null : parse(String.valueOf(r.get("assessment"))));
        out.put("enhancement", r.get("enhancement") == null ? null : parse(String.valueOf(r.get("enhancement"))));
        out.put("createdAt", r.get("created_at"));
        out.put("decidedAt", r.get("decided_at"));
        out.put("identity", state(person));
        return out;
    }

    /** the files of an upload the database then refused, taken back out of the store — each in a transaction of its own; one another
     *  row still holds (the same bytes uploaded before) stays, as FileObjects.forget always leaves it */
    private void forget(UUID... objects) {
        for (UUID object : objects) {
            if (object == null) {
                continue;
            }
            try {
                tx.executeWithoutResult(status -> files.forget(object));
            } catch (RuntimeException kept) {
                LOG.warn("staff photograph: file object {} of a refused upload not removed (the orphan sweep takes it after the hour): {}", object, kept.getMessage());
            }
        }
    }

    /** the base64 of the upload (a data URL's header read past), refused before decoding when it is plainly too large */
    private byte[] base64(String data) {
        String s = data.trim();
        if (s.startsWith("data:")) {
            int comma = s.indexOf(',');
            s = comma < 0 ? "" : s.substring(comma + 1);
        }
        long max = enhancer.settings().maxBytes();
        if (s.length() > max / 3 * 4 + 64) {
            throw new DomainRuleViolation("PHOTO_SIZE", "The photograph is larger than the " + (max / (1024 * 1024)) + " MB the portal takes.",
                    new DomainRuleViolation.Remedy("Upload a smaller copy of the photograph (a phone's 'medium' size is enough).", "You"));
        }
        try {
            return Base64.getDecoder().decode(s.replaceAll("\\s", ""));
        } catch (IllegalArgumentException notBase64) {
            throw new DomainRuleViolation("PHOTO_DATA", "The photograph could not be read.",
                    new DomainRuleViolation.Remedy("Choose the photograph again and upload it.", "You"));
        }
    }

    private static ResponseEntity<byte[]> image(byte[] bytes, String type) {
        return ResponseEntity.ok().contentType(MediaType.parseMediaType(type)).cacheControl(CacheControl.noStore().cachePrivate())
                .header("X-Content-Type-Options", "nosniff").body(bytes);
    }

    private Map<String, Object> parse(String j) {
        return json.readValue(j, new tools.jackson.core.type.TypeReference<Map<String, Object>>() { });
    }

    private static String sha256(String s) {
        try {
            return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(s.getBytes(StandardCharsets.UTF_8)));
        } catch (NoSuchAlgorithmException e) {
            throw new IllegalStateException(e);
        }
    }
}
