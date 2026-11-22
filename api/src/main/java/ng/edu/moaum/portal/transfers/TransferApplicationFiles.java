package ng.edu.moaum.portal.transfers;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.util.Base64;
import java.util.HexFormat;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

import ng.edu.moaum.portal.shared.DomainRuleViolation;
import ng.edu.moaum.portal.shared.FileObjects;
import ng.edu.moaum.portal.shared.NotFound;

import org.apache.pdfbox.Loader;
import org.apache.pdfbox.multipdf.PDFMergerUtility;
import org.apache.pdfbox.pdmodel.PDDocument;
import org.apache.pdfbox.pdmodel.PDPage;
import org.apache.pdfbox.pdmodel.PDPageContentStream;
import org.apache.pdfbox.pdmodel.common.PDRectangle;
import org.apache.pdfbox.pdmodel.graphics.image.PDImageXObject;
import org.springframework.http.CacheControl;
import org.springframework.http.ContentDisposition;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Component;

/**
 * V766: the files of an online inter-university transfer application — the University's decision that a transfer applicant uploads
 * the transcript, the letter of release or of good standing, the JAMB admission letter and the like (an exception to the rule that
 * applicants never upload). A file arrives as a data URL in JSON, as every upload in the portal does: its type named in the URL must be
 * a PDF, JPEG or PNG, it is at most 5 MB, and its first bytes must be the type it claims (a renamed file is not taken for what it says it
 * is, JUPEB's rule). The database decides the rest (the fee settled, the state, the kind and whether images are allowed for it). A file
 * is streamed back sandboxed and never cached; the department reads all of an application's current documents as one PDF.
 */
@Component
public class TransferApplicationFiles {

    /** the most a document may be: the database's own limit (admissions.iut_document.bytes) */
    static final int MAX_BYTES = 5 * 1024 * 1024;
    static final Set<String> TYPES = Set.of("application/pdf", "image/jpeg", "image/png");

    private final JdbcClient jdbc;
    private final FileObjects files;

    TransferApplicationFiles(JdbcClient jdbc, FileObjects files) {
        this.jdbc = jdbc;
        this.files = files;
    }

    /** a file as it arrived: its type, its bytes and their SHA-256 in lower-case hex */
    record Read(String contentType, byte[] bytes, String sha256) {
    }

    private static DomainRuleViolation type(String said) {
        return new DomainRuleViolation("IUT_DOCUMENT_TYPE", said,
                new DomainRuleViolation.Remedy("Upload the original PDF, or a JPEG or PNG scan where the document allows one.", "You"));
    }

    /** the data URL read: the type it names (PDF, JPEG or PNG), at most 5 MB, and its first bytes that type's */
    static Read read(String dataUrl) {
        String d = dataUrl == null ? "" : dataUrl.trim();
        int comma = d.indexOf(',');
        if (!d.regionMatches(true, 0, "data:", 0, 5) || comma < 0) {
            throw type("The file did not arrive as a file: choose it again and upload it.");
        }
        String head = d.substring(5, comma).toLowerCase(Locale.ROOT);
        if (!head.endsWith(";base64")) {
            throw type("The file did not arrive intact: choose it again and upload it.");
        }
        String ct = head.substring(0, head.length() - ";base64".length()).trim();
        int param = ct.indexOf(';');
        if (param >= 0) ct = ct.substring(0, param).trim();
        if ("image/jpg".equals(ct)) ct = "image/jpeg";
        if (!TYPES.contains(ct)) {
            throw type("A document is a PDF, JPEG or PNG file; this one is " + (ct.isEmpty() ? "of no type" : ct) + ".");
        }
        // the size is judged before the bytes are decoded: base64 is four characters for every three bytes
        String body = d.substring(comma + 1).replaceAll("\\s", "");
        long approx = (long) body.length() * 3 / 4;
        if (approx > MAX_BYTES + 3L) {
            throw size(approx);
        }
        byte[] bytes;
        try {
            bytes = Base64.getDecoder().decode(body);
        } catch (IllegalArgumentException notBase64) {
            throw type("The file did not arrive intact: choose it again and upload it.");
        }
        if (bytes.length == 0 || bytes.length > MAX_BYTES) {
            throw size(bytes.length);
        }
        if (!signatureMatches(ct, bytes)) {
            throw type("The file's contents are not the " + words(ct) + " its name claims.");
        }
        return new Read(ct, bytes, HexFormat.of().formatHex(FileObjects.sha256(bytes)));
    }

    private static DomainRuleViolation size(long bytes) {
        return new DomainRuleViolation("IUT_DOCUMENT_SIZE", bytes == 0 ? "The file is empty." : "A document is at most 5 MB; this one is " + (bytes / 1024) + " KB.",
                new DomainRuleViolation.Remedy("Scan it at a lower resolution, or save it as a smaller PDF, and upload it again.", "You"));
    }

    private static String words(String ct) {
        return switch (ct) {
            case "application/pdf" -> "PDF";
            case "image/jpeg" -> "JPEG";
            default -> "PNG";
        };
    }

    /** the leading bytes say what a file is (JupebPortalController.signatureMatches): %PDF-, FF D8 FF, 89 50 4E 47 */
    static boolean signatureMatches(String contentType, byte[] b) {
        return switch (contentType) {
            case "application/pdf" -> b.length > 5 && b[0] == '%' && b[1] == 'P' && b[2] == 'D' && b[3] == 'F' && b[4] == '-';
            case "image/jpeg" -> b.length > 3 && (b[0] & 0xFF) == 0xFF && (b[1] & 0xFF) == 0xD8 && (b[2] & 0xFF) == 0xFF;
            case "image/png" -> b.length > 8 && (b[0] & 0xFF) == 0x89 && b[1] == 'P' && b[2] == 'N' && b[3] == 'G';
            default -> false;
        };
    }

    /** a document of the application, current or superseded, as the database keeps it; the bytes from the row or the file store */
    ResponseEntity<byte[]> stream(UUID application, UUID document) {
        Map<String, Object> d = jdbc.sql("""
                SELECT d.filename, d.content_type, d.object_id, b.content
                  FROM admissions.iut_document d LEFT JOIN admissions.iut_document_blob b ON b.document_id = d.id
                 WHERE d.id = :d AND d.application_id = :a
                """).param("d", document).param("a", application).query().listOfRows().stream().findFirst()
                .orElseThrow(() -> new NotFound("document", document));
        byte[] bytes = files.resolve((byte[]) d.get("content"), (UUID) d.get("object_id"));
        if (bytes == null) {
            throw new NotFound("document", document);
        }
        // sandboxed and never cached: a document is the applicant's, read by the offices that decide
        return ResponseEntity.ok()
                .contentType(MediaType.parseMediaType(String.valueOf(d.get("content_type"))))
                .cacheControl(CacheControl.noStore())
                .header(HttpHeaders.CONTENT_DISPOSITION, ContentDisposition.inline().filename(String.valueOf(d.get("filename")), StandardCharsets.UTF_8).build().toString())
                .header("X-Content-Type-Options", "nosniff").header("Content-Security-Policy", "sandbox")
                .body(bytes);
    }

    /** the application's current documents as one PDF, in the order the kinds are asked for — images on pages of their own
     *  (PgAdmissionsController.mergedDocuments) */
    ResponseEntity<byte[]> merged(UUID application, String applicationNo) {
        List<Map<String, Object>> docs = jdbc.sql("""
                SELECT d.kind, d.content_type, d.object_id, b.content
                  FROM admissions.iut_document d
                  JOIN admissions.iut_document_kind k ON k.code = d.kind
                  LEFT JOIN admissions.iut_document_blob b ON b.document_id = d.id
                 WHERE d.application_id = :a AND d.superseded_at IS NULL
                 ORDER BY k.ord, d.kind
                """).param("a", application).query().listOfRows();
        if (docs.isEmpty()) {
            throw new NotFound("documents of the transfer application", applicationNo);
        }
        try (PDDocument out = new PDDocument(); ByteArrayOutputStream baos = new ByteArrayOutputStream()) {
            PDFMergerUtility merger = new PDFMergerUtility();
            for (Map<String, Object> d : docs) {
                byte[] b = files.resolve((byte[]) d.get("content"), (UUID) d.get("object_id"));
                if (b == null) {
                    continue;
                }
                String ct = String.valueOf(d.get("content_type"));
                if ("application/pdf".equals(ct)) {
                    try (PDDocument src = Loader.loadPDF(b)) {
                        merger.appendDocument(out, src);
                    } catch (RuntimeException | IOException badPdf) { /* an unreadable PDF is left out; it opens on its own from the list */ }
                } else {
                    try {
                        PDImageXObject img = PDImageXObject.createFromByteArray(out, b, String.valueOf(d.get("kind")));
                        PDPage page = new PDPage(PDRectangle.A4);
                        out.addPage(page);
                        float maxW = PDRectangle.A4.getWidth() - 72, maxH = PDRectangle.A4.getHeight() - 72;
                        float scale = Math.min(1f, Math.min(maxW / img.getWidth(), maxH / img.getHeight()));
                        float w = img.getWidth() * scale, h = img.getHeight() * scale;
                        float x = (PDRectangle.A4.getWidth() - w) / 2, y = (PDRectangle.A4.getHeight() - h) / 2;
                        try (PDPageContentStream cs = new PDPageContentStream(out, page)) {
                            cs.drawImage(img, x, y, w, h);
                        }
                    } catch (RuntimeException | IOException badImage) { /* an unreadable image is left out likewise */ }
                }
            }
            if (out.getNumberOfPages() == 0) {
                throw new DomainRuleViolation("IUT_DOCUMENTS_MERGE", "None of the documents could be put into one PDF.",
                        new DomainRuleViolation.Remedy("Open each document on its own from the list.", "Registry"));
            }
            out.save(baos);
            String name = "transfer-documents-" + applicationNo.replaceAll("[^A-Za-z0-9]+", "-") + ".pdf";
            return ResponseEntity.ok().contentType(MediaType.APPLICATION_PDF).cacheControl(CacheControl.noStore())
                    .header(HttpHeaders.CONTENT_DISPOSITION, ContentDisposition.inline().filename(name).build().toString())
                    .header("X-Content-Type-Options", "nosniff")
                    .body(baos.toByteArray());
        } catch (IOException e) {
            throw new DomainRuleViolation("IUT_DOCUMENTS_MERGE", "The documents could not be combined into one PDF.",
                    new DomainRuleViolation.Remedy("Open each document on its own from the list.", "Registry"));
        }
    }
}
