package ng.edu.moaum.portal.jupeb;

import java.nio.charset.StandardCharsets;
import java.sql.Types;
import java.util.Base64;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import org.springframework.http.CacheControl;
import org.springframework.http.ContentDisposition;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.simple.JdbcClient;

import ng.edu.moaum.portal.shared.DomainRuleViolation;
import ng.edu.moaum.portal.shared.FileObjects;
import ng.edu.moaum.portal.shared.NotFound;

/**
 * The image of a practice question (V349): one PNG or JPEG of at most 1 MB, kept like the JUPEB documents — in the object store
 * when one is configured, else in the database — and served privately, uncached and sandboxed. Who may see it is decided by the
 * caller (the office; a student only inside an attempt that drew the question).
 */
final class JupebPracticeImages {

    static final int MAX = 1024 * 1024;

    private JupebPracticeImages() {
    }

    /** the image put on (or replacing the image of) a question; the bytes are checked to be what their type claims */
    static void store(JdbcClient jdbc, FileObjects files, UUID question, String filename, String contentType, String base64, UUID actor) {
        String ct = contentType == null ? "" : contentType.trim().toLowerCase();
        if (!ct.equals("image/png") && !ct.equals("image/jpeg")) {
            throw new DomainRuleViolation("JUPEB_PRACTICE_IMAGE_TYPE", "A question's image is a PNG or a JPEG.", new DomainRuleViolation.Remedy("Save the diagram as PNG or JPEG.", "JUPEB Office"));
        }
        byte[] bytes;
        try {
            bytes = Base64.getDecoder().decode(base64 == null ? "" : base64);
        } catch (IllegalArgumentException notBase64) {
            throw new DomainRuleViolation("JUPEB_DOC_ENCODING", "The file did not arrive intact.", new DomainRuleViolation.Remedy("Try the upload again.", "JUPEB Office"));
        }
        if (bytes.length == 0 || bytes.length > MAX) {
            throw new DomainRuleViolation("JUPEB_PRACTICE_IMAGE_SIZE", "A question's image is at most 1 MB; this one is " + (bytes.length / 1024) + " KB.",
                    new DomainRuleViolation.Remedy("Crop it or save it at a lower resolution.", "JUPEB Office"));
        }
        if (!JupebPortalController.signatureMatches(ct, bytes)) {
            throw new DomainRuleViolation("JUPEB_DOC_TYPE", "The file's contents are not the " + ct + " its name claims.", new DomainRuleViolation.Remedy("Upload the original image.", "JUPEB Office"));
        }
        String name = filename == null || filename.isBlank() ? "question" + (ct.equals("image/png") ? ".png" : ".jpg") : filename.trim();
        if (name.length() > 200) name = name.substring(0, 200);
        List<UUID> old = jdbc.sql("SELECT object_id FROM jupeb.practice_image WHERE question_id = :q AND object_id IS NOT NULL").param("q", question).query(UUID.class).list();
        UUID oid = files.store("jupeb.practice_image", question, name, ct, bytes);
        jdbc.sql("""
                INSERT INTO jupeb.practice_image (question_id, filename, content_type, size_bytes, object_id, uploaded_by)
                VALUES (:q, :fn, :ct, :sz, :o, :by)
                ON CONFLICT (question_id) DO UPDATE SET filename = EXCLUDED.filename, content_type = EXCLUDED.content_type, size_bytes = EXCLUDED.size_bytes,
                       object_id = EXCLUDED.object_id, uploaded_by = EXCLUDED.uploaded_by, uploaded_at = now()
                """).param("q", question).param("fn", name).param("ct", ct).param("sz", bytes.length).param("o", oid, Types.OTHER).param("by", actor, Types.OTHER).update();
        jdbc.sql("DELETE FROM jupeb.practice_image_blob WHERE question_id = :q").param("q", question).update();
        if (oid == null) {
            jdbc.sql("INSERT INTO jupeb.practice_image_blob (question_id, bytes) VALUES (:q, :b)").param("q", question).param("b", bytes, Types.BINARY).update();
        }
        old.stream().filter(o -> !o.equals(oid)).forEach(files::forget);
    }

    /** the image taken off a question (the object goes only when no other version of the question still shows it) */
    static void remove(JdbcClient jdbc, FileObjects files, UUID question) {
        List<UUID> old = jdbc.sql("DELETE FROM jupeb.practice_image WHERE question_id = :q RETURNING object_id").param("q", question).query(UUID.class).list();
        if (old.isEmpty()) throw new NotFound("question image", question);
        old.stream().filter(java.util.Objects::nonNull).forEach(files::forget);
    }

    /** the image's bytes, private and uncached */
    static ResponseEntity<byte[]> stream(JdbcClient jdbc, FileObjects files, UUID question) {
        Map<String, Object> row = jdbc.sql("""
                SELECT i.filename, i.content_type, i.object_id, b.bytes FROM jupeb.practice_image i LEFT JOIN jupeb.practice_image_blob b ON b.question_id = i.question_id
                 WHERE i.question_id = :q
                """).param("q", question).query().listOfRows().stream().findFirst().orElseThrow(() -> new NotFound("question image", question));
        byte[] bytes = files.resolve((byte[]) row.get("bytes"), (UUID) row.get("object_id"));
        if (bytes == null) throw new NotFound("question image", question);
        return ResponseEntity.ok().contentType(MediaType.parseMediaType(String.valueOf(row.get("content_type"))))
                .cacheControl(CacheControl.noStore())
                .header("Content-Disposition", ContentDisposition.inline().filename(String.valueOf(row.get("filename")), StandardCharsets.UTF_8).build().toString())
                .header("X-Content-Type-Options", "nosniff").header("Content-Security-Policy", "sandbox")
                .body(bytes);
    }
}
