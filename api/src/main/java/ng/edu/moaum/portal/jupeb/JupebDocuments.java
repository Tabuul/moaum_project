package ng.edu.moaum.portal.jupeb;

import java.nio.charset.StandardCharsets;
import java.util.Map;
import java.util.UUID;

import ng.edu.moaum.portal.shared.FileObjects;
import ng.edu.moaum.portal.shared.NotFound;

import org.springframework.http.CacheControl;
import org.springframework.http.ContentDisposition;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.simple.JdbcClient;

/**
 * A JUPEB document streamed to someone already authorised for it — its candidate, or the JUPEB Office. Sensitive personal
 * papers (NIN, birth certificate, results) are never public: no URL is stored, the bytes come from the private object store
 * or the database through this one door, inline, uncached and sandboxed.
 */
final class JupebDocuments {

    private JupebDocuments() {
    }

    static ResponseEntity<byte[]> stream(JdbcClient jdbc, FileObjects files, UUID app, String kind) {
        Map<String, Object> d = jdbc.sql("""
                SELECT d.filename, d.content_type, d.object_id, b.bytes
                  FROM jupeb.document d LEFT JOIN jupeb.document_blob b ON b.document_id = d.id
                 WHERE d.application_id = :a AND d.kind = upper(btrim(:k))
                """).param("a", app).param("k", kind).query().listOfRows().stream().findFirst().orElseThrow(() -> new NotFound("document", kind));
        byte[] bytes = files.resolve((byte[]) d.get("bytes"), (UUID) d.get("object_id"));
        if (bytes == null) throw new NotFound("document", kind);
        return ResponseEntity.ok()
                .contentType(MediaType.parseMediaType(String.valueOf(d.get("content_type"))))
                .cacheControl(CacheControl.noStore())
                .header("Content-Disposition", ContentDisposition.inline().filename(String.valueOf(d.get("filename")), StandardCharsets.UTF_8).build().toString())
                .header("X-Content-Type-Options", "nosniff").header("Content-Security-Policy", "sandbox")
                .body(bytes);
    }
}
