package ng.edu.moaum.portal.credentials;

import java.awt.image.BufferedImage;
import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import java.sql.Types;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.UUID;

import jakarta.validation.Valid;
import jakarta.validation.constraints.Size;

import ng.edu.moaum.portal.shared.DomainRuleViolation;
import ng.edu.moaum.portal.shared.FileObjects;

import org.springframework.http.CacheControl;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * V759: the signature printed above a signatory's name — on the admission letter first — is a setting, not a file in the code. A
 * signature belongs to the signatory a document template names (credentials.signatory_key matches the name, case and spacing
 * aside). An admission letter is drawn with the template in force whenever it is opened, so every letter, the letters issued
 * earlier included, prints the signature of the signatory that template names, and none prints a signature kept for a signatory no
 * template in force names. The offices that change the templates upload it (a PNG or JPEG of at most a megabyte, kept as given and
 * as a JPEG on white for the PDF engine, in the file store when one is configured and in the row otherwise, as the identity cards'
 * signature is: SignatureImages), replace it (a new version) and remove it (the row and the audit trail kept); the offices that read
 * the templates see it. Never public: an applicant or a student receives it only inside their own letter (AdmissionDocuments). The
 * database holds the rule on who sets it (credentials.set_signatory_signature).
 */
@RestController
@RequestMapping("/api/v1/documents/signatures")
class SignatorySignatureController {

    private static final String OWNER = "credentials.signatory_signature";
    private static final String OFFICE = "The Registry";

    private final JdbcClient jdbc;
    private final FileObjects files;

    SignatorySignatureController(JdbcClient jdbc, FileObjects files) {
        this.jdbc = jdbc;
        this.files = files;
    }

    public record SignatureIn(@Size(max = 120) String name, @Size(max = 200) String filename, String contentBase64) {
    }

    /** a row of credentials.signatory_signatures() as the screen reads it: camelCase, and no key the row holds no value for */
    private static Map<String, Object> entry(Map<String, Object> r) {
        boolean has = Boolean.TRUE.equals(r.get("has_signature"));
        Map<String, Object> e = new LinkedHashMap<>();
        e.put("name", r.get("name"));
        e.put("hasSignature", has);
        put(e, "version", r.get("version"));
        put(e, "setAt", r.get("set_at"));
        put(e, "setByName", r.get("set_by_name"));
        put(e, "setOffice", r.get("set_office"));
        if (has) {
            // the version in the address: a replaced signature is never the old one from a browser's cache
            e.put("signatureUrl", "/api/v1/documents/signatures/image?name=" + URLEncoder.encode(String.valueOf(r.get("name")), StandardCharsets.UTF_8)
                    + "&v=" + r.get("version"));
        }
        e.put("kinds", kinds(r.get("kinds")));
        e.put("inUse", Boolean.TRUE.equals(r.get("in_use")));
        return e;
    }

    private static void put(Map<String, Object> e, String key, Object value) {
        if (value != null) e.put(key, value);
    }

    private static List<String> kinds(Object v) {
        try {
            if (v instanceof java.sql.Array a) return List.of((String[]) a.getArray());
        } catch (java.sql.SQLException unreadable) {
            throw new IllegalStateException("the kinds of a signatory could not be read", unreadable);
        }
        return List.of();
    }

    /** one signatory by the key: as the list has it, or — removed, and named by no current template — as the row stands */
    private Map<String, Object> entryOf(String key) {
        return jdbc.sql("SELECT * FROM credentials.signatory_signatures() WHERE name_key = :k").param("k", key).query().listOfRows().stream().findFirst()
                .or(() -> jdbc.sql("""
                        SELECT s.name, s.name_key, '{}'::text[] AS kinds, false AS in_use,
                               (s.signature_type IS NOT NULL AND (s.signature_jpeg IS NOT NULL OR s.signature_jpeg_object_id IS NOT NULL)) AS has_signature,
                               s.version, s.set_at, s.set_office,
                               nullif(btrim(coalesce(p.surname, '') || ', ' || coalesce(p.given_names, ''), ', '), '') AS set_by_name
                          FROM credentials.signatory_signature s LEFT JOIN iam.person p ON p.id = s.set_by
                         WHERE s.name_key = :k
                        """).param("k", key).query().listOfRows().stream().findFirst())
                .map(SignatorySignatureController::entry).orElseThrow(() -> new IllegalStateException("no signatory " + key));
    }

    /** each signatory the current template versions name, the admission letter's first, and any signature still held for a name
     *  none of them names (so it can be removed) */
    @GetMapping
    @PreAuthorize(DocumentsController.READERS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> list() {
        return jdbc.sql("SELECT * FROM credentials.signatory_signatures()").query().listOfRows().stream().map(SignatorySignatureController::entry).toList();
    }

    /** the signature as uploaded, or (format=jpeg) the JPEG the letter's PDF draws; 404 when none is held for the name */
    @GetMapping("/image")
    @PreAuthorize(DocumentsController.READERS)
    @Transactional(readOnly = true)
    ResponseEntity<byte[]> image(@RequestParam String name, @RequestParam(required = false) String format) {
        boolean jpeg = "jpeg".equalsIgnoreCase(format) || "jpg".equalsIgnoreCase(format);
        Map<String, Object> r = jdbc.sql("""
                SELECT signature, signature_object_id, signature_type, signature_jpeg, signature_jpeg_object_id
                  FROM credentials.signatory_signature_of(:n)
                """).param("n", name).query().listOfRows().stream().findFirst().orElse(null);
        byte[] bytes = r == null ? null : jpeg ? files.resolve((byte[]) r.get("signature_jpeg"), (UUID) r.get("signature_jpeg_object_id"))
                : files.resolve((byte[]) r.get("signature"), (UUID) r.get("signature_object_id"));
        if (bytes == null) {
            return ResponseEntity.notFound().build();
        }
        String type = jpeg ? "image/jpeg" : String.valueOf(r.get("signature_type"));
        return ResponseEntity.ok().cacheControl(CacheControl.noStore()).contentType(MediaType.parseMediaType(type)).body(bytes);
    }

    /** upload, or replace as a new version, the signature of the signatory a template names: a PNG or JPEG of at most a megabyte */
    @PutMapping
    @PreAuthorize(DocumentsController.CONFIG)
    @Transactional
    Map<String, Object> set(@Valid @RequestBody SignatureIn in) {
        String name = in.name() == null ? "" : in.name().trim();
        String key = jdbc.sql("SELECT coalesce(credentials.signatory_key(:n), '')").param("n", name).query(String.class).single();
        if (key.isEmpty()) {
            throw refusal("SIGNATORY_SIGNATURE_NAME", "Say whose signature this is, by the name the document template states.",
                    "Upload it from the template's Signature section, which names the signatory.");
        }
        // asked before anything is stored: the database refuses the name too (the same words), but by then a configured file store
        // already holds both images, where nothing reaches them
        boolean named = jdbc.sql("SELECT EXISTS (SELECT 1 FROM credentials.document_template t WHERE credentials.signatory_key(t.signatory_name) = :k)")
                .param("k", key).query(Boolean.class).single();
        if (!named) {
            throw refusal("SIGNATORY_SIGNATURE_UNKNOWN", "No document template names \"" + name + "\" as its signatory.",
                    "Upload the signature for the name the template states, from the template's Signature section.");
        }
        if (in.contentBase64() == null || in.contentBase64().isBlank()) {
            throw refusal("SIGNATORY_SIGNATURE_IMAGE", "No file came with the upload.", "Choose the scan of the signature, a PNG or a JPEG.");
        }
        byte[] bytes = SignatureImages.bytesOf(in.contentBase64());
        if (bytes == null || bytes.length == 0) {
            throw refusal("SIGNATORY_SIGNATURE_UNREADABLE", "The upload is not a file the portal can read.", "Upload the signature as a PNG or JPEG image.");
        }
        if (bytes.length > SignatureImages.MAX_BYTES) {
            throw refusal("SIGNATORY_SIGNATURE_TOO_LARGE", "The signature is " + size(bytes.length) + "; the limit is 1 MB (1,000,000 bytes).",
                    "Save the signature smaller: 800 pixels wide prints sharply on the letter.");
        }
        String type = SignatureImages.typeOf(bytes);
        if (type == null) {
            throw refusal("SIGNATORY_SIGNATURE_FORMAT", "The signature must be a PNG or a JPEG; this file is neither.",
                    "Save the scan as a PNG (a transparent background prints best) or a JPEG.");
        }
        SignatureImages.Decoded decoded = SignatureImages.decode(bytes);
        if (decoded.image() == null && decoded.tooManyPixels()) {
            throw refusal("SIGNATORY_SIGNATURE_UNREADABLE", "The picture is " + decoded.width() + " × " + decoded.height() + " pixels, too large to read.",
                    "Crop the scan close to the ink and save it at about 800 pixels wide.");
        }
        BufferedImage img = decoded.image();
        if (img == null || img.getWidth() < 60 || img.getHeight() < 20) {
            throw refusal("SIGNATORY_SIGNATURE_UNREADABLE", "The image could not be decoded, or is too small to print (at least 60 × 20 pixels).",
                    "Upload a clear scan of the signature, cropped close to the ink.");
        }
        SignatureImages.Jpeg jpeg = SignatureImages.jpegOf(img);
        UUID original = files.store(OWNER, key, in.filename() == null || in.filename().isBlank() ? "signature" : in.filename().trim(), type, bytes);
        UUID derived = files.store(OWNER, key, "signature.jpg", "image/jpeg", jpeg.bytes());
        String stored = jdbc.sql("SELECT name_key FROM credentials.set_signatory_signature(:n, :b, :bo, :t, :j, :jo, :w, :h)")
                .param("n", name)
                .param("b", original == null ? bytes : null, Types.BINARY).param("bo", original, Types.OTHER).param("t", type)
                .param("j", derived == null ? jpeg.bytes() : null, Types.BINARY).param("jo", derived, Types.OTHER)
                .param("w", jpeg.width()).param("h", jpeg.height())
                .query(String.class).single();
        return entryOf(stored);
    }

    /** the signature removed: the letters naming the signatory leave the space for a hand signature; the row and its trail stay */
    @DeleteMapping
    @PreAuthorize(DocumentsController.CONFIG)
    @Transactional
    Map<String, Object> remove(@RequestParam String name) {
        String stored = jdbc.sql("SELECT name_key FROM credentials.remove_signatory_signature(:n)").param("n", name).query(String.class).single();
        return entryOf(stored);
    }

    /** a file's size in the limit's own unit, rounded up, with its bytes: a file just over the limit never reads as under it (1,000,001
     *  bytes is "1.01 MB (1,000,001 bytes)", where a division by 1024 said "976 KB" of a file refused as over 1 MB) */
    static String size(long bytes) {
        return String.format(Locale.ROOT, "%.2f MB (%,d bytes)", Math.ceil(bytes / 10_000.0) / 100, bytes);
    }

    private static DomainRuleViolation refusal(String code, String words, String remedy) {
        return new DomainRuleViolation(code, words, new DomainRuleViolation.Remedy(remedy, OFFICE));
    }
}
