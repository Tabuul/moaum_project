package ng.edu.moaum.portal.support;

import java.sql.Types;
import java.util.Base64;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

import ng.edu.moaum.portal.shared.AuditContextHolder;
import ng.edu.moaum.portal.shared.DomainRuleViolation;
import ng.edu.moaum.portal.shared.NotFound;

import org.springframework.http.ContentDisposition;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.Authentication;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/** The student's requests under /api/v1/me/requests; the office's desk under /api/v1/support/requests. */
@RestController
class SupportController {

    private static final String OFFICES = "hasAnyAuthority('OFFICE_registrar','OFFICE_dregistrar','OFFICE_bursar','OFFICE_ict','OFFICE_library','OFFICE_services','OFFICE_academic','OFFICE_hod','OFFICE_housing','OFFICE_admin','OFFICE_super')";
    /** each request carries a count of the documents attached to it, so a desk can see there is evidence to read */
    private static final String REQUEST = """
            SELECT r.id, r.ref, r.office_code, o.label AS office, r.subject, r.detail, r.raised_at, r.state, r.answer, r.answered_at,
                   st.surname || ', ' || st.other_names AS student, coalesce(st.matric_no, st.admission_no) AS number,
                   CASE WHEN p.id IS NULL THEN NULL ELSE p.surname || ', ' || p.given_names END AS answered_by_name,
                   (SELECT count(*) FROM platform.request_document d WHERE d.request_id = r.id) AS documents
              FROM platform.service_request r
              JOIN ref.office o ON o.code = r.office_code
              JOIN people.student st ON st.id = r.student_id
              LEFT JOIN iam.person p ON p.id = r.answered_by
            """;
    private static final String DOC_LIST =
            "SELECT id, filename, content_type, bytes, uploaded_at FROM platform.request_document WHERE request_id = :r ORDER BY uploaded_at";
    /** a file at most 2 MB, of a kind an office can open */
    private static final long MAX_BYTES = 2_097_152L;
    private static final List<String> TYPES = List.of("application/pdf", "image/jpeg", "image/png");

    public record Raise(@NotBlank @Size(max = 20) String office, @NotBlank @Size(max = 200) String subject, @Size(max = 4000) String detail) {
    }

    public record Answer(@NotBlank @Size(max = 4000) String answer, Boolean resolved) {
    }

    public record Upload(@NotBlank @Size(max = 200) String filename, @NotBlank String contentType, @NotBlank String contentBase64) {
    }

    private final JdbcClient jdbc;

    SupportController(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    private static UUID student(Authentication auth) {
        return UUID.fromString(auth.getName());
    }

    @GetMapping("/api/v1/me/requests")
    @PreAuthorize("hasAuthority('OFFICE_student')")
    @Transactional(readOnly = true)
    List<Map<String, Object>> mine(Authentication auth) {
        return jdbc.sql(REQUEST + " WHERE r.student_id = :s ORDER BY r.raised_at DESC LIMIT 50").param("s", student(auth)).query().listOfRows();
    }

    @PostMapping("/api/v1/me/requests")
    @PreAuthorize("hasAuthority('OFFICE_student')")
    @Transactional
    Map<String, Object> raise(Authentication auth, @Valid @RequestBody Raise body) {
        String ref = jdbc.sql("SELECT platform.raise_request(:s, :o, :j, :d)").param("s", student(auth)).param("o", body.office().trim().toLowerCase())
                .param("j", body.subject()).param("d", body.detail(), Types.VARCHAR).query(String.class).single();
        UUID id = jdbc.sql("SELECT id FROM platform.service_request WHERE ref = :ref").param("ref", ref).query(UUID.class).single();
        return Map.of("id", id, "ref", ref, "state", "OPEN");
    }

    /* ── supporting documents (V040) ── */

    /** the student lists the documents on their own request */
    @GetMapping("/api/v1/me/requests/{id}/documents")
    @PreAuthorize("hasAuthority('OFFICE_student')")
    @Transactional(readOnly = true)
    List<Map<String, Object>> myDocuments(Authentication auth, @PathVariable UUID id) {
        requireOwnRequest(id, student(auth));
        return jdbc.sql(DOC_LIST).param("r", id).query().listOfRows();
    }

    /** the student attaches a supporting document to their own request */
    @PostMapping("/api/v1/me/requests/{id}/documents")
    @PreAuthorize("hasAuthority('OFFICE_student')")
    @Transactional
    Map<String, Object> attach(Authentication auth, @PathVariable UUID id, @Valid @RequestBody Upload body) {
        requireOwnRequest(id, student(auth));
        return store(id, body);
    }

    @GetMapping("/api/v1/me/requests/{id}/documents/{doc}/content")
    @PreAuthorize("hasAuthority('OFFICE_student')")
    @Transactional(readOnly = true)
    ResponseEntity<byte[]> myDocumentContent(Authentication auth, @PathVariable UUID id, @PathVariable UUID doc) {
        requireOwnRequest(id, student(auth));
        return content(id, doc);
    }

    /** the office lists the documents on a request it handles */
    @GetMapping("/api/v1/support/requests/{id}/documents")
    @PreAuthorize(OFFICES)
    @Transactional(readOnly = true)
    List<Map<String, Object>> deskDocuments(@PathVariable UUID id) {
        requireOfficeRequest(id);
        return jdbc.sql(DOC_LIST).param("r", id).query().listOfRows();
    }

    @GetMapping("/api/v1/support/requests/{id}/documents/{doc}/content")
    @PreAuthorize(OFFICES)
    @Transactional(readOnly = true)
    ResponseEntity<byte[]> deskDocumentContent(@PathVariable UUID id, @PathVariable UUID doc) {
        requireOfficeRequest(id);
        return content(id, doc);
    }

    /** the office's queue: its own requests, the oldest open first — or every office's for the platform */
    @GetMapping("/api/v1/support/requests")
    @PreAuthorize(OFFICES)
    @Transactional(readOnly = true)
    List<Map<String, Object>> desk(@RequestParam(required = false) String state) {
        String office = AuditContextHolder.required().actorOffice();
        boolean all = List.of("admin", "super", "ict").contains(office);
        return jdbc.sql(REQUEST + """
                 WHERE (:all OR r.office_code = :o)
                   AND (:state::text IS NULL OR r.state = :state)
                 ORDER BY (r.state IN ('OPEN','WITH_OFFICE')) DESC, r.raised_at LIMIT 300
                """).param("all", all).param("o", office).param("state", state == null || state.isBlank() ? null : state.toUpperCase(), Types.VARCHAR)
                .query().listOfRows();
    }

    @PostMapping("/api/v1/support/requests/{id}/answer")
    @PreAuthorize(OFFICES)
    @Transactional
    Map<String, Object> answer(@PathVariable UUID id, @Valid @RequestBody Answer body) {
        jdbc.sql("SELECT platform.answer_request(:id, :a, :r)").param("id", id).param("a", body.answer()).param("r", body.resolved() == null || body.resolved()).query().singleRow();
        return Map.of("id", id, "state", body.resolved() == null || body.resolved() ? "RESOLVED" : "WITH_OFFICE");
    }

    /* ── helpers ── */

    private void requireOwnRequest(UUID request, UUID student) {
        Boolean ok = jdbc.sql("SELECT true FROM platform.service_request WHERE id = :id AND student_id = :s")
                .param("id", request).param("s", student).query(Boolean.class).optional().orElse(false);
        if (!ok) throw new NotFound("request", request.toString());
    }

    /** the request must belong to the acting office, unless the office sees every desk (admin/super/ict) */
    private void requireOfficeRequest(UUID request) {
        String office = AuditContextHolder.required().actorOffice();
        boolean all = List.of("admin", "super", "ict").contains(office);
        Boolean ok = jdbc.sql("SELECT true FROM platform.service_request WHERE id = :id AND (:all OR office_code = :o)")
                .param("id", request).param("all", all).param("o", office).query(Boolean.class).optional().orElse(false);
        if (!ok) throw new NotFound("request", request.toString());
    }

    private Map<String, Object> store(UUID request, Upload body) {
        byte[] bytes;
        try {
            bytes = Base64.getDecoder().decode(body.contentBase64());
        } catch (IllegalArgumentException notBase64) {
            throw new DomainRuleViolation("SUPPORT_DOC_BAD", "The document could not be read.",
                    new DomainRuleViolation.Remedy("Attach the file again.", "Directorate of ICT"));
        }
        if (bytes.length == 0 || bytes.length > MAX_BYTES) {
            throw new DomainRuleViolation("SUPPORT_DOC_SIZE", "A supporting document is between 1 byte and 2 MB.",
                    new DomainRuleViolation.Remedy("Attach a smaller file.", "Student Services"));
        }
        if (!TYPES.contains(body.contentType())) {
            throw new DomainRuleViolation("SUPPORT_DOC_TYPE", "A supporting document is a PDF, a JPEG or a PNG.",
                    new DomainRuleViolation.Remedy("Save it as one of those and attach it again.", "Student Services"));
        }
        UUID docId = jdbc.sql("SELECT platform.attach_request_document(:r, :f, :t, :b, :c)")
                .param("r", request).param("f", body.filename()).param("t", body.contentType()).param("b", (long) bytes.length).param("c", bytes)
                .query(UUID.class).single();
        return Map.of("id", docId, "filename", body.filename(), "bytes", bytes.length);
    }

    private ResponseEntity<byte[]> content(UUID request, UUID doc) {
        List<Map<String, Object>> rows = jdbc.sql("""
                SELECT d.filename, d.content_type, b.content
                  FROM platform.request_document d JOIN platform.request_document_blob b ON b.document_id = d.id
                 WHERE d.id = :doc AND d.request_id = :r
                """).param("doc", doc).param("r", request).query().listOfRows();
        if (rows.isEmpty()) throw new NotFound("document", doc.toString());
        Map<String, Object> r = rows.get(0);
        byte[] content = (byte[]) r.get("content");
        return ResponseEntity.ok()
                .contentType(MediaType.parseMediaType((String) r.get("content_type")))
                .header("Content-Disposition", ContentDisposition.inline().filename(String.valueOf(r.get("filename"))).build().toString())
                .body(content);
    }
}
