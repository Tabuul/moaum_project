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
 * A JUPEB document streamed to someone already authorised for it — its candidate, the JUPEB Office, or (the passport only)
 * an instructor taking the candidate's attendance. Sensitive personal papers (NIN, birth certificate, results) are never
 * public: no URL is stored, the bytes come from the private object store or the database through this one door, inline,
 * uncached and sandboxed. An O'Level result is one document a sitting. The passport can be had as a JPEG, which the
 * document writer embeds (V342).
 */
public final class JupebDocuments {

    private JupebDocuments() {
    }

    static ResponseEntity<byte[]> stream(JdbcClient jdbc, FileObjects files, UUID app, String kind, Integer sitting) {
        return stream(jdbc, files, app, kind, sitting, false);
    }

    public static ResponseEntity<byte[]> stream(JdbcClient jdbc, FileObjects files, UUID app, String kind, Integer sitting, boolean jpeg) {
        Map<String, Object> d = jdbc.sql("""
                SELECT d.filename, d.content_type, d.object_id, b.bytes
                  FROM jupeb.document d LEFT JOIN jupeb.document_blob b ON b.document_id = d.id
                 WHERE d.application_id = :a AND d.kind = upper(btrim(:k)) AND coalesce(d.sitting, 0) = coalesce(:s, 0)
                """).param("a", app).param("k", kind).param("s", sitting, java.sql.Types.INTEGER).query().listOfRows().stream().findFirst()
                .orElseThrow(() -> new NotFound("document", kind));
        byte[] bytes = files.resolve((byte[]) d.get("bytes"), (UUID) d.get("object_id"));
        if (bytes == null) throw new NotFound("document", kind);
        String ct = String.valueOf(d.get("content_type"));
        String name = String.valueOf(d.get("filename"));
        if (jpeg && !ct.contains("jpeg")) {
            byte[] converted = toJpeg(bytes);
            if (converted == null) throw new NotFound("document", kind);
            bytes = converted;
            ct = "image/jpeg";
            name = name.replaceAll("\\.[A-Za-z0-9]+$", "") + ".jpg";
        }
        return ResponseEntity.ok()
                .contentType(MediaType.parseMediaType(ct))
                .cacheControl(CacheControl.noStore())
                .header("Content-Disposition", ContentDisposition.inline().filename(name, StandardCharsets.UTF_8).build().toString())
                .header("X-Content-Type-Options", "nosniff").header("Content-Security-Policy", "sandbox")
                .body(bytes);
    }

    /** an image as a JPEG on a white ground (a PNG's transparency would print black) */
    static byte[] toJpeg(byte[] bytes) {
        try {
            java.awt.image.BufferedImage src = javax.imageio.ImageIO.read(new java.io.ByteArrayInputStream(bytes));
            if (src == null) return null;
            java.awt.image.BufferedImage rgb = new java.awt.image.BufferedImage(src.getWidth(), src.getHeight(), java.awt.image.BufferedImage.TYPE_INT_RGB);
            java.awt.Graphics2D g = rgb.createGraphics();
            g.setColor(java.awt.Color.WHITE);
            g.fillRect(0, 0, src.getWidth(), src.getHeight());
            g.drawImage(src, 0, 0, null);
            g.dispose();
            java.io.ByteArrayOutputStream out = new java.io.ByteArrayOutputStream();
            return javax.imageio.ImageIO.write(rgb, "jpg", out) ? out.toByteArray() : null;
        } catch (java.io.IOException unreadable) {
            return null;
        }
    }
}
