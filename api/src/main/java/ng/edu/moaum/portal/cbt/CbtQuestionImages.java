package ng.edu.moaum.portal.cbt;

import java.nio.charset.StandardCharsets;
import java.sql.Types;
import java.util.Base64;
import java.util.Map;
import java.util.UUID;

import ng.edu.moaum.portal.shared.DomainRuleViolation;
import ng.edu.moaum.portal.shared.FileObjects;
import ng.edu.moaum.portal.shared.NotFound;

import org.springframework.http.CacheControl;
import org.springframework.http.ContentDisposition;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.simple.JdbcClient;

/**
 * V376: the images of CBT questions — a question's diagram, or an option's — each a PNG or JPEG of at most 1 MB, kept like the
 * University's other private files (in the object store when one is configured, else in the database) and never changed: a new
 * image is added and the question versioned. Served uncached and sandboxed; who may see one is decided by the caller (the office
 * through the question's bank; a candidate only inside their own running attempt that drew it).
 */
final class CbtQuestionImages {

    static final int MAX = 1024 * 1024;

    private CbtQuestionImages() {
    }

    /** whether the bytes are what the type claims: PNG's signature, or JPEG's */
    static boolean signatureMatches(String ct, byte[] b) {
        if ("image/png".equals(ct)) return b.length > 8 && (b[0] & 0xFF) == 0x89 && b[1] == 'P' && b[2] == 'N' && b[3] == 'G';
        if ("image/jpeg".equals(ct)) return b.length > 3 && (b[0] & 0xFF) == 0xFF && (b[1] & 0xFF) == 0xD8 && (b[2] & 0xFF) == 0xFF;
        return false;
    }

    /** an image added: checked, stored, its id back */
    static UUID add(JdbcClient jdbc, FileObjects files, String filename, String contentType, String base64, UUID actor) {
        String ct = contentType == null ? "" : contentType.trim().toLowerCase();
        if (!ct.equals("image/png") && !ct.equals("image/jpeg")) {
            throw new DomainRuleViolation("CBT_IMAGE_TYPE", "A question's image is a PNG or a JPEG.", new DomainRuleViolation.Remedy("Save the diagram as PNG or JPEG.", "You"));
        }
        byte[] bytes;
        try {
            bytes = Base64.getDecoder().decode(base64 == null ? "" : base64);
        } catch (IllegalArgumentException notBase64) {
            throw new DomainRuleViolation("CBT_IMAGE_ENCODING", "The image did not arrive intact.", new DomainRuleViolation.Remedy("Try the upload again.", "You"));
        }
        if (bytes.length == 0 || bytes.length > MAX) {
            throw new DomainRuleViolation("CBT_IMAGE_SIZE", "A question's image is at most 1 MB; this one is " + (bytes.length / 1024) + " KB.",
                    new DomainRuleViolation.Remedy("Crop it or save it at a lower resolution.", "You"));
        }
        if (!signatureMatches(ct, bytes)) {
            throw new DomainRuleViolation("CBT_IMAGE_CONTENT", "The file's contents are not the " + ct + " its name claims.", new DomainRuleViolation.Remedy("Upload the original image.", "You"));
        }
        String name = filename == null || filename.isBlank() ? "diagram" + (ct.equals("image/png") ? ".png" : ".jpg") : filename.trim();
        if (name.length() > 200) name = name.substring(0, 200);
        UUID id = UUID.randomUUID();
        UUID oid = files.store("assessment.question_image", id, name, ct, bytes);
        jdbc.sql("INSERT INTO assessment.question_image (id, filename, content_type, size_bytes, object_id, uploaded_by) VALUES (:id, :fn, :ct, :sz, :o, :by)")
                .param("id", id).param("fn", name).param("ct", ct).param("sz", bytes.length).param("o", oid, Types.OTHER).param("by", actor, Types.OTHER).update();
        if (oid == null) {
            jdbc.sql("INSERT INTO assessment.question_image_blob (image_id, bytes) VALUES (:i, :b)").param("i", id).param("b", bytes, Types.BINARY).update();
        }
        return id;
    }

    /** the image's bytes, private and uncached */
    static ResponseEntity<byte[]> stream(JdbcClient jdbc, FileObjects files, UUID image) {
        Map<String, Object> row = jdbc.sql("""
                SELECT i.filename, i.content_type, i.object_id, b.bytes FROM assessment.question_image i LEFT JOIN assessment.question_image_blob b ON b.image_id = i.id
                 WHERE i.id = :i
                """).param("i", image).query().listOfRows().stream().findFirst().orElseThrow(() -> new NotFound("question image", image.toString()));
        byte[] bytes = files.resolve((byte[]) row.get("bytes"), (UUID) row.get("object_id"));
        if (bytes == null) throw new NotFound("question image", image.toString());
        return ResponseEntity.ok().contentType(MediaType.parseMediaType(String.valueOf(row.get("content_type"))))
                .cacheControl(CacheControl.noStore())
                .header("Content-Disposition", ContentDisposition.inline().filename(String.valueOf(row.get("filename")), StandardCharsets.UTF_8).build().toString())
                .header("X-Content-Type-Options", "nosniff").header("Content-Security-Policy", "sandbox")
                .body(bytes);
    }
}
