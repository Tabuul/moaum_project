package ng.edu.moaum.portal.partnership;

import java.io.ByteArrayInputStream;
import java.io.IOException;
import java.util.Base64;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.zip.ZipEntry;
import java.util.zip.ZipInputStream;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Component;

import ng.edu.moaum.portal.shared.DomainRuleViolation;
import ng.edu.moaum.portal.shared.FileObjects;
import ng.edu.moaum.portal.shared.NotFound;

/**
 * A partnership file (V658): a PDF, DOCX, XLSX or PPTX, told apart by what the bytes are — a PDF's header, or an Office Open XML
 * package (a ZIP holding [Content_Types].xml and the word/, xl/ or ppt/ part), a macro-enabled package refused — never by the name
 * or the type the browser claims; within the configured size and count; kept in the file store where there is one, else in the row.
 * The portal has no malware scanner to call; the content check and the type list are what stands in its place.
 */
@Component
class PartnershipFiles {

    static final Set<String> KINDS = Set.of("CONCEPT_NOTE", "PROPOSAL", "ORGANISATION_PROFILE", "DRAFT_MOU", "DRAFT_AGREEMENT", "CV", "FUNDING_CALL",
            "BUDGET", "SUPPORT_LETTER", "REGISTRATION_EVIDENCE", "REQUESTED_DOCUMENT", "AGREEMENT", "INTERNAL", "OTHER");
    static final Map<String, String> TYPES = Map.of(
            "pdf", "application/pdf",
            "docx", "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
            "xlsx", "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
            "pptx", "application/vnd.openxmlformats-officedocument.presentationml.presentation");

    private final JdbcClient jdbc;
    private final FileObjects files;

    PartnershipFiles(JdbcClient jdbc, FileObjects files) {
        this.jdbc = jdbc;
        this.files = files;
    }

    record Decoded(String filename, String contentType, byte[] bytes) {
    }

    private static DomainRuleViolation bad(String code, String what) {
        return new DomainRuleViolation(code, what, new DomainRuleViolation.Remedy("Save the document as PDF, DOCX, XLSX or PPTX and choose it again.", "You"));
    }

    /** the file from a data URL: its extension one of the four, its bytes what the extension says, within the size allowed */
    Decoded decode(String filename, String dataUrl) {
        String name = filename == null ? "" : filename.replaceAll("[\\\\/:*?\"<>|\\p{Cntrl}]", "_").trim();
        if (name.isEmpty() || name.length() > 200) throw bad("PTN_FILE_NAME", "Attachment: give the file a name of up to 200 characters.");
        int dot = name.lastIndexOf('.');
        String ext = dot < 0 ? "" : name.substring(dot + 1).toLowerCase();
        String type = TYPES.get(ext);
        if (type == null) throw bad("PTN_FILE_TYPE", "Attachment: upload a PDF, DOCX, XLSX or PPTX file within the permitted size.");
        String u = dataUrl == null ? "" : dataUrl;
        int comma = u.indexOf(',');
        if (!u.startsWith("data:") || comma < 0 || !u.substring(0, comma).contains(";base64")) throw bad("PTN_FILE_READ", "Attachment: the file could not be read; choose it again.");
        byte[] bytes;
        try {
            bytes = Base64.getDecoder().decode(u.substring(comma + 1).replaceAll("\\s", ""));
        } catch (IllegalArgumentException e) {
            throw bad("PTN_FILE_READ", "Attachment: the file could not be read; choose it again.");
        }
        int maxMb = jdbc.sql("SELECT max_file_mb FROM partnership.setting WHERE id = 1").query(Integer.class).single();
        if (bytes.length == 0) throw bad("PTN_FILE_EMPTY", "Attachment: the file is empty.");
        if (bytes.length > maxMb * 1024L * 1024L) throw bad("PTN_FILE_SIZE", "Attachment: upload a file of at most " + maxMb + " MB.");
        if (!matches(ext, bytes)) throw bad("PTN_FILE_TYPE", "Attachment: the file is not a real " + ext.toUpperCase() + " document; upload a PDF, DOCX, XLSX or PPTX file.");
        return new Decoded(name, type, bytes);
    }

    /** the bytes are what the extension says: a PDF header, or an Office Open XML package of that kind with no macros */
    static boolean matches(String ext, byte[] b) {
        if ("pdf".equals(ext)) return b.length > 5 && b[0] == '%' && b[1] == 'P' && b[2] == 'D' && b[3] == 'F' && b[4] == '-';
        if (b.length < 4 || b[0] != 'P' || b[1] != 'K' || b[2] != 3 || b[3] != 4) return false;
        String part = switch (ext) { case "docx" -> "word/"; case "xlsx" -> "xl/"; case "pptx" -> "ppt/"; default -> "?"; };
        boolean types = false, kind = false;
        try (ZipInputStream z = new ZipInputStream(new ByteArrayInputStream(b))) {
            ZipEntry e;
            int n = 0;
            while ((e = z.getNextEntry()) != null && n++ < 5000) {
                String name = e.getName();
                if (name.equals("[Content_Types].xml")) types = true;
                if (name.startsWith(part)) kind = true;
                String lower = name.toLowerCase();
                if (lower.endsWith("vbaproject.bin") || lower.endsWith(".exe") || lower.endsWith(".dll") || lower.endsWith(".bat") || lower.endsWith(".cmd")
                        || lower.endsWith(".js") || lower.endsWith(".vbs") || lower.endsWith(".ps1")) return false;
            }
        } catch (IOException | IllegalArgumentException e) {
            return false;
        }
        return types && kind;
    }

    /** the file kept for the proposal (count checked for the applicant's own), its row id */
    UUID keep(UUID proposal, String kind, Decoded f, boolean fromApplicant, UUID agreement, UUID infoRequest) {
        String k = kind == null ? "OTHER" : kind.trim().toUpperCase();
        if (!KINDS.contains(k)) throw bad("PTN_FILE_KIND", "Attachment: choose what the document is (concept note, proposal, profile …).");
        if (fromApplicant) {
            Map<String, Object> c = jdbc.sql("""
                    SELECT (SELECT count(*) FROM partnership.attachment a WHERE a.proposal_id = :p AND a.from_applicant) AS n, s.max_files
                      FROM partnership.setting s WHERE s.id = 1
                    """).param("p", proposal).query().singleRow();
            int max = ((Number) c.get("max_files")).intValue();
            // the documents asked for later are counted apart from the enquiry's own
            if (!"REQUESTED_DOCUMENT".equals(k) && ((Number) c.get("n")).intValue() >= max) {
                throw new DomainRuleViolation("PTN_FILE_COUNT", "Attachments: attach at most " + max + " files.",
                        new DomainRuleViolation.Remedy("Remove one before adding another, or combine documents into one PDF.", "You"));
            }
        }
        UUID object = files.store("partnership.attachment", proposal, f.filename(), f.contentType(), f.bytes());
        return jdbc.sql("""
                INSERT INTO partnership.attachment (proposal_id, agreement_id, info_request_id, kind, filename, content_type, size_bytes, sha256, content, object_id,
                                                    from_applicant, added_by, added_office)
                VALUES (:p, :ag, :ir, :k, :f, :t, :n, :h, :c, :o, :fa, nullif(current_setting('moaum.actor_id', true), '')::uuid,
                        nullif(current_setting('moaum.actor_office', true), ''))
                RETURNING id
                """).param("p", proposal).param("ag", agreement).param("ir", infoRequest).param("k", k).param("f", f.filename()).param("t", f.contentType())
                .param("n", (long) f.bytes().length).param("h", FileObjects.sha256(f.bytes())).param("c", object == null ? f.bytes() : null)
                .param("o", object).param("fa", fromApplicant).query(UUID.class).single();
    }

    record Loaded(String filename, String contentType, byte[] bytes) {
    }

    Loaded load(UUID proposal, UUID attachment) {
        Map<String, Object> r = jdbc.sql("SELECT filename, content_type, content, object_id FROM partnership.attachment WHERE id = :a AND proposal_id = :p")
                .param("a", attachment).param("p", proposal).query().listOfRows().stream().findFirst().orElseThrow(() -> new NotFound("attachment", attachment));
        byte[] bytes = files.resolve((byte[]) r.get("content"), (UUID) r.get("object_id"));
        return new Loaded(String.valueOf(r.get("filename")), String.valueOf(r.get("content_type")), bytes);
    }

    List<Map<String, Object>> list(UUID proposal, boolean applicantOnly) {
        return jdbc.sql("""
                SELECT a.id, a.kind, a.filename, a.content_type, a.size_bytes, a.from_applicant, a.added_at, a.agreement_id, a.info_request_id,
                       CASE WHEN a.added_by IS NULL OR a.from_applicant THEN NULL ELSE helpdesk.person_name(a.added_by) END AS added_by_name
                  FROM partnership.attachment a WHERE a.proposal_id = :p AND (NOT :ao OR a.from_applicant) ORDER BY a.added_at
                """).param("p", proposal).param("ao", applicantOnly).query().listOfRows();
    }
}
