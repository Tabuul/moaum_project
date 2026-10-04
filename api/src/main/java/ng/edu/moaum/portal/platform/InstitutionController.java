package ng.edu.moaum.portal.platform;

import java.awt.Color;
import java.awt.Graphics2D;
import java.awt.RenderingHints;
import java.awt.image.BufferedImage;
import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.util.Base64;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.TimeUnit;

import javax.imageio.ImageIO;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

import ng.edu.moaum.portal.shared.AuditContextHolder;
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
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * The institution profile (V320): the official identity every document reads. Anyone may read it and
 * the logo — a receipt, a form or a letter is branded before anyone signs in — while only the
 * administrators the Registry and the Directorate of ICT name may change it. The logo is kept in the
 * file store as uploaded, with a JPEG derivative the PDF engine embeds; the record is audited.
 */
@RestController
class InstitutionController {

    private static final String KEEPERS = "hasAnyAuthority('OFFICE_ict','OFFICE_super','OFFICE_admin','OFFICE_registrar','OFFICE_dregistrar')";
    private static final int MAX_LOGO_BYTES = 2_000_000;
    private static final int JPEG_MAX_SIDE = 600;

    private final JdbcClient jdbc;
    private final FileObjects files;
    private final Branding branding;
    private final tools.jackson.databind.ObjectMapper json;

    InstitutionController(JdbcClient jdbc, FileObjects files, Branding branding, tools.jackson.databind.ObjectMapper json) {
        this.jdbc = jdbc;
        this.files = files;
        this.branding = branding;
        this.json = json;
    }

    public record ProfileIn(@NotBlank @Size(max = 200) String name, @NotBlank @Size(max = 40) String shortName,
                            @Size(max = 200) String motto, @Size(max = 400) String address, @Size(max = 100) String city,
                            @Size(max = 100) String state, @Size(max = 100) String country, @Size(max = 100) String phone,
                            @Size(max = 200) String email, @Size(max = 200) String website, @Size(max = 400) String footerNote,
                            Boolean showGeneratedBy, Boolean showPageNumbers, String dateFormat) {
    }

    public record LogoIn(@NotBlank @Size(max = 200) String filename, String contentType, @NotBlank String contentBase64) {
    }

    public record IssueIn(@NotBlank @Size(max = 60) String kind, @Size(max = 120) String reference, @Size(max = 60) String subjectKind,
                          @Size(max = 120) String subjectId, Map<String, Object> detail) {
    }

    @SuppressWarnings("unchecked")
    private Map<String, Object> profile() {
        String text = jdbc.sql("SELECT platform.institution()::text").query(String.class).single();
        Map<String, Object> raw;
        try {
            raw = json.readValue(text, Map.class);
        } catch (RuntimeException unreadable) {
            raw = Map.of("name", Branding.DEFAULT_NAME, "shortName", Branding.DEFAULT_SHORT_NAME);
        }
        Map<String, Object> out = new LinkedHashMap<>(raw);
        boolean hasLogo = Boolean.TRUE.equals(raw.get("hasLogo"));
        boolean hasJpeg = Boolean.TRUE.equals(raw.get("hasLogoJpeg"));
        Object version = raw.getOrDefault("logoVersion", 0);
        out.put("logoUrl", hasLogo ? "/api/v1/public/institution/logo?v=" + version : null);
        out.put("logoJpegUrl", hasJpeg ? "/api/v1/public/institution/logo?format=jpeg&v=" + version : null);
        return out;
    }

    /** the identity every document carries: public, cached for a minute */
    @GetMapping("/api/v1/public/institution")
    @Transactional(readOnly = true)
    ResponseEntity<Map<String, Object>> read() {
        return ResponseEntity.ok().cacheControl(CacheControl.maxAge(60, TimeUnit.SECONDS).cachePublic()).body(profile());
    }

    /** the logo as uploaded (for screens and browser printing), or its JPEG derivative (for the PDF engine); 404 when none is set,
     *  which the portal answers with its built-in crest */
    @GetMapping("/api/v1/public/institution/logo")
    @Transactional(readOnly = true)
    ResponseEntity<byte[]> logo(@RequestParam(required = false) String format) {
        boolean jpeg = "jpeg".equalsIgnoreCase(format) || "jpg".equalsIgnoreCase(format);
        UUID id = jdbc.sql("SELECT " + (jpeg ? "logo_jpeg_object_id" : "logo_object_id") + " FROM platform.institution_profile WHERE id")
                .query(UUID.class).optional().orElse(null);
        if (id == null) {
            return ResponseEntity.notFound().build();
        }
        FileObjects.Typed t = files.typed(id);
        if (t == null || t.bytes() == null) {
            return ResponseEntity.notFound().build();
        }
        return ResponseEntity.ok().cacheControl(CacheControl.maxAge(1, TimeUnit.HOURS).cachePublic())
                .contentType(MediaType.parseMediaType(t.contentType() == null ? "application/octet-stream" : t.contentType())).body(t.bytes());
    }

    @PutMapping("/api/v1/platform/institution")
    @PreAuthorize(KEEPERS)
    @Transactional
    Map<String, Object> update(@Valid @RequestBody ProfileIn in) {
        jdbc.sql("SELECT platform.set_institution_profile(:n, :s, :m, :a, :c, :st, :co, :p, :e, :w, :f, :g, :pn, :d)")
                .param("n", in.name()).param("s", in.shortName()).param("m", in.motto(), java.sql.Types.VARCHAR)
                .param("a", in.address(), java.sql.Types.VARCHAR).param("c", in.city(), java.sql.Types.VARCHAR)
                .param("st", in.state(), java.sql.Types.VARCHAR).param("co", in.country(), java.sql.Types.VARCHAR)
                .param("p", in.phone(), java.sql.Types.VARCHAR).param("e", in.email(), java.sql.Types.VARCHAR)
                .param("w", in.website(), java.sql.Types.VARCHAR).param("f", in.footerNote(), java.sql.Types.VARCHAR)
                .param("g", in.showGeneratedBy() == null || in.showGeneratedBy()).param("pn", in.showPageNumbers() == null || in.showPageNumbers())
                .param("d", in.dateFormat() == null || in.dateFormat().isBlank() ? "LONG" : in.dateFormat().trim().toUpperCase())
                .query().listOfRows();
        branding.invalidate();
        return profile();
    }

    /** the logo: a PNG or JPEG of at most two megabytes, kept as given and as a JPEG on white for the PDF engine */
    @PutMapping("/api/v1/platform/institution/logo")
    @PreAuthorize(KEEPERS)
    @Transactional
    Map<String, Object> setLogo(@Valid @RequestBody LogoIn in) {
        if (!files.enabled()) {
            throw new DomainRuleViolation("FILES_NOT_CONFIGURED", "The portal has no file store configured, so a logo cannot be kept; the documents carry the built-in crest.",
                    new DomainRuleViolation.Remedy("Configure the file store (MOAUM_FILES_PROVIDER) on the service, then upload the logo again.", "Directorate of ICT"));
        }
        String b64 = in.contentBase64().trim();
        int comma = b64.indexOf(',');
        if (b64.startsWith("data:") && comma > 0) b64 = b64.substring(comma + 1);
        byte[] bytes;
        try {
            bytes = Base64.getDecoder().decode(b64);
        } catch (IllegalArgumentException bad) {
            throw new DomainRuleViolation("LOGO_UNREADABLE", "The upload is not a file the portal can read.", new DomainRuleViolation.Remedy("Upload the logo as a PNG or JPEG image.", "Directorate of ICT"));
        }
        if (bytes.length > MAX_LOGO_BYTES) {
            throw new DomainRuleViolation("LOGO_TOO_LARGE", "The logo is " + (bytes.length / 1024) + " KB; the limit is " + (MAX_LOGO_BYTES / 1000) + " KB.",
                    new DomainRuleViolation.Remedy("Export the logo at a smaller size — 600 pixels on its longest side prints sharply on every document.", "Directorate of ICT"));
        }
        String type = bytes.length > 3 && (bytes[0] & 0xFF) == 0x89 && bytes[1] == 'P' && bytes[2] == 'N' && bytes[3] == 'G' ? "image/png"
                : bytes.length > 2 && (bytes[0] & 0xFF) == 0xFF && (bytes[1] & 0xFF) == 0xD8 ? "image/jpeg" : null;
        if (type == null) {
            throw new DomainRuleViolation("LOGO_FORMAT", "The logo must be a PNG or a JPEG; this file is neither.", new DomainRuleViolation.Remedy("Export the logo as PNG (with transparency) or JPEG and upload it again.", "Directorate of ICT"));
        }
        BufferedImage img;
        try {
            img = ImageIO.read(new ByteArrayInputStream(bytes));
        } catch (java.io.IOException unreadable) {
            img = null;
        }
        if (img == null || img.getWidth() < 32 || img.getHeight() < 32) {
            throw new DomainRuleViolation("LOGO_UNREADABLE", "The image could not be decoded, or is smaller than 32 pixels.", new DomainRuleViolation.Remedy("Upload a clear logo of at least 200 pixels on its shortest side.", "Directorate of ICT"));
        }
        byte[] jpeg = jpegOnWhite(img);
        UUID original = files.store("platform.institution_profile", "logo", in.filename(), type, bytes);
        UUID derived = files.store("platform.institution_profile", "logo-jpeg", "logo.jpg", "image/jpeg", jpeg);
        jdbc.sql("SELECT platform.set_institution_logo(:a, :b)").param("a", original).param("b", derived).query().listOfRows();
        branding.invalidate();
        return profile();
    }

    /** back to the built-in crest */
    @DeleteMapping("/api/v1/platform/institution/logo")
    @PreAuthorize(KEEPERS)
    @Transactional
    Map<String, Object> clearLogo() {
        jdbc.sql("SELECT platform.set_institution_logo(NULL, NULL)").query().listOfRows();
        branding.invalidate();
        return profile();
    }

    /** a document the portal issued, on the record in the actor's name (V320) */
    @PostMapping("/api/v1/documents/issued")
    @PreAuthorize("isAuthenticated()")
    @Transactional
    Map<String, Object> issued(@Valid @RequestBody IssueIn in) {
        AuditContextHolder.required();
        String detail;
        try {
            detail = in.detail() == null ? null : json.writeValueAsString(in.detail());
        } catch (RuntimeException bad) {
            detail = null;
        }
        UUID id = jdbc.sql("SELECT platform.record_document_issue(:k, :r, :sk, :si, :d::jsonb)")
                .param("k", in.kind().trim().toUpperCase().replaceAll("[^A-Z0-9_]", "_")).param("r", in.reference(), java.sql.Types.VARCHAR)
                .param("sk", in.subjectKind(), java.sql.Types.VARCHAR).param("si", in.subjectId(), java.sql.Types.VARCHAR)
                .param("d", detail, java.sql.Types.VARCHAR).query(UUID.class).single();
        return Map.of("id", id);
    }

    /** the logo drawn on white, no larger than 600 pixels on its longest side, as a JPEG the PDF engine embeds */
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
