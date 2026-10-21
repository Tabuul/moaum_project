package ng.edu.moaum.portal.credentials;

import java.awt.Color;
import java.awt.Graphics2D;
import java.awt.RenderingHints;
import java.awt.image.BufferedImage;
import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.sql.Types;
import java.util.Base64;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.UUID;

import javax.imageio.ImageIO;

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
 * V622: who signs the identity cards for the University — the Chief Security Officer. The Directorate of ICT sets the name and
 * uploads the signature (a PNG or JPEG, kept as given and as a JPEG on white for the PDF engine; in the file store when one is
 * configured, in the row otherwise), replaces or removes it; the card desk's prints read it. Unlike the logo the signature is never
 * public: only the offices that print or set it read the image. The database holds the rule on who sets it.
 */
@RestController
@RequestMapping("/api/v1/credentials/identity-cards/signatory")
class CardSignatoryController {

    private static final String READERS = "hasAnyAuthority('OFFICE_ict','OFFICE_security','OFFICE_super')";
    private static final String SETTERS = "hasAnyAuthority('OFFICE_ict','OFFICE_super')";
    private static final int MAX_BYTES = 1_000_000;
    private static final int JPEG_MAX_SIDE = 800;

    private final JdbcClient jdbc;
    private final FileObjects files;

    CardSignatoryController(JdbcClient jdbc, FileObjects files) {
        this.jdbc = jdbc;
        this.files = files;
    }

    public record SignatoryIn(@Size(max = 120) String name, @Size(max = 200) String filename, String contentBase64) {
    }

    private Map<String, Object> info() {
        Map<String, Object> r = jdbc.sql("""
                SELECT c.title, c.name, c.version, c.set_at, c.set_office,
                       (c.signature IS NOT NULL OR c.signature_object_id IS NOT NULL) AS has_signature,
                       nullif(btrim(coalesce(p.surname, '') || ', ' || coalesce(p.given_names, ''), ', '), '') AS set_by_name
                  FROM credentials.card_signatory c LEFT JOIN iam.person p ON p.id = c.set_by
                 WHERE c.role = 'CHIEF_SECURITY_OFFICER'
                """).query().singleRow();
        Map<String, Object> out = new LinkedHashMap<>(r);
        out.put("signatureUrl", Boolean.TRUE.equals(r.get("has_signature")) ? "/api/v1/credentials/identity-cards/signatory/signature?v=" + r.get("version") : null);
        return out;
    }

    /** the Chief Security Officer as the cards name them, and whether a signature is held */
    @GetMapping
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> read() {
        return info();
    }

    /** the signature as uploaded, or (format=jpeg) the JPEG the card's PDF embeds; 404 when none is set */
    @GetMapping("/signature")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    ResponseEntity<byte[]> signature(@RequestParam(required = false) String format) {
        boolean jpeg = "jpeg".equalsIgnoreCase(format) || "jpg".equalsIgnoreCase(format);
        Map<String, Object> r = jdbc.sql("""
                SELECT signature, signature_object_id, signature_type, signature_jpeg, signature_jpeg_object_id
                  FROM credentials.card_signatory WHERE role = 'CHIEF_SECURITY_OFFICER'
                """).query().singleRow();
        byte[] bytes = jpeg ? files.resolve((byte[]) r.get("signature_jpeg"), (UUID) r.get("signature_jpeg_object_id"))
                : files.resolve((byte[]) r.get("signature"), (UUID) r.get("signature_object_id"));
        if (bytes == null) {
            return ResponseEntity.notFound().build();
        }
        String type = jpeg ? "image/jpeg" : String.valueOf(r.get("signature_type"));
        return ResponseEntity.ok().cacheControl(CacheControl.noStore()).contentType(MediaType.parseMediaType(type)).body(bytes);
    }

    /** the name and, when a file is given, the signature: a PNG or JPEG of at most one megabyte */
    @PutMapping
    @PreAuthorize(SETTERS)
    @Transactional
    Map<String, Object> set(@Valid @RequestBody SignatoryIn in) {
        String b64 = in.contentBase64() == null ? "" : in.contentBase64().trim();
        if (b64.isEmpty()) {
            jdbc.sql("SELECT credentials.set_card_signatory(:n, NULL, NULL, NULL, NULL, NULL, false)").param("n", in.name(), Types.VARCHAR)
                    .query().listOfRows();
            return info();
        }
        int comma = b64.indexOf(',');
        if (b64.startsWith("data:") && comma > 0) b64 = b64.substring(comma + 1);
        byte[] bytes;
        try {
            bytes = Base64.getDecoder().decode(b64);
        } catch (IllegalArgumentException bad) {
            throw refusal("CARD_SIGNATURE_UNREADABLE", "The upload is not a file the portal can read.", "Upload the signature as a PNG or JPEG image.");
        }
        if (bytes.length > MAX_BYTES) {
            throw refusal("CARD_SIGNATURE_TOO_LARGE", "The signature is " + (bytes.length / 1024) + " KB; the limit is " + (MAX_BYTES / 1000) + " KB.",
                    "Scan or export the signature smaller — 600 pixels wide prints sharply on the card.");
        }
        String type = bytes.length > 3 && (bytes[0] & 0xFF) == 0x89 && bytes[1] == 'P' && bytes[2] == 'N' && bytes[3] == 'G' ? "image/png"
                : bytes.length > 2 && (bytes[0] & 0xFF) == 0xFF && (bytes[1] & 0xFF) == 0xD8 ? "image/jpeg" : null;
        if (type == null) {
            throw refusal("CARD_SIGNATURE_FORMAT", "The signature must be a PNG or a JPEG; this file is neither.", "Scan the signature on white paper and save it as PNG or JPEG.");
        }
        BufferedImage img;
        try {
            img = ImageIO.read(new ByteArrayInputStream(bytes));
        } catch (java.io.IOException unreadable) {
            img = null;
        }
        if (img == null || img.getWidth() < 60 || img.getHeight() < 20) {
            throw refusal("CARD_SIGNATURE_UNREADABLE", "The image could not be decoded, or is too small to print (at least 60 × 20 pixels).",
                    "Upload a clear scan of the signature, cropped close to the ink.");
        }
        byte[] jpeg = jpegOnWhite(img);
        UUID original = files.store("credentials.card_signatory", "CHIEF_SECURITY_OFFICER", in.filename() == null ? "signature" : in.filename(), type, bytes);
        UUID derived = files.store("credentials.card_signatory", "CHIEF_SECURITY_OFFICER", "signature.jpg", "image/jpeg", jpeg);
        jdbc.sql("SELECT credentials.set_card_signatory(:n, :b, :bo, :t, :j, :jo, false)")
                .param("n", in.name(), Types.VARCHAR)
                .param("b", original == null ? bytes : null, Types.BINARY).param("bo", original, Types.OTHER).param("t", type)
                .param("j", derived == null ? jpeg : null, Types.BINARY).param("jo", derived, Types.OTHER)
                .query().listOfRows();
        return info();
    }

    /** the signature removed: the cards print the line alone until another is uploaded */
    @DeleteMapping("/signature")
    @PreAuthorize(SETTERS)
    @Transactional
    Map<String, Object> clear() {
        jdbc.sql("SELECT credentials.set_card_signatory(NULL, NULL, NULL, NULL, NULL, NULL, true)").query().listOfRows();
        return info();
    }

    private static DomainRuleViolation refusal(String code, String words, String remedy) {
        return new DomainRuleViolation(code, words, new DomainRuleViolation.Remedy(remedy, "Directorate of ICT"));
    }

    /** the signature drawn on white, no larger than 800 pixels on its longest side, as a JPEG the PDF engine embeds */
    static byte[] jpegOnWhite(BufferedImage img) {
        int w = img.getWidth(), h = img.getHeight();
        double k = Math.min(1.0, (double) JPEG_MAX_SIDE / Math.max(w, h));
        int tw = Math.max(1, (int) Math.round(w * k)), th = Math.max(1, (int) Math.round(h * k));
        BufferedImage rgb = new BufferedImage(tw, th, BufferedImage.TYPE_INT_RGB);
        Graphics2D g = rgb.createGraphics();
        try {
            g.setColor(Color.WHITE);
            g.fillRect(0, 0, tw, th);
            g.setRenderingHint(RenderingHints.KEY_INTERPOLATION, RenderingHints.VALUE_INTERPOLATION_BILINEAR);
            g.setRenderingHint(RenderingHints.KEY_RENDERING, RenderingHints.VALUE_RENDER_QUALITY);
            g.drawImage(img, 0, 0, tw, th, null);
        } finally {
            g.dispose();
        }
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        try {
            ImageIO.write(rgb, "jpeg", out);
        } catch (java.io.IOException impossible) {
            throw new IllegalStateException("the JPEG writer is part of the JDK", impossible);
        }
        return out.toByteArray();
    }
}
