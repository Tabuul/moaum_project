package ng.edu.moaum.portal.lms;

import java.math.BigDecimal;
import java.time.OffsetDateTime;
import java.util.Base64;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import ng.edu.moaum.portal.shared.AuditContextHolder;
import ng.edu.moaum.portal.shared.DomainRuleViolation;
import ng.edu.moaum.portal.shared.NotFound;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class LmsService {

    static final int MAX_FILE = 5 * 1024 * 1024;
    private static final List<String> KINDS = List.of("NOTES", "SLIDES", "READING", "VIDEO", "AUDIO", "OTHER");
    private static final List<String> TYPES = List.of("application/pdf", "image/jpeg", "image/png", "text/plain", "text/csv",
            "application/vnd.openxmlformats-officedocument.wordprocessingml.document", "application/vnd.openxmlformats-officedocument.presentationml.presentation",
            "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", "application/zip", "audio/mpeg", "video/mp4");

    private final LmsRepository repo;

    LmsService(LmsRepository repo) {
        this.repo = repo;
    }

    private static UUID me() {
        return AuditContextHolder.required().actorId();
    }

    private String session(String asked) {
        return asked == null || asked.isBlank() ? repo.currentSession() : asked;
    }

    private static byte[] decode(String base64, String contentType) {
        if (base64 == null || base64.isBlank()) {
            return null;
        }
        if (contentType == null || !TYPES.contains(contentType)) {
            throw new DomainRuleViolation("LMS_FILE_TYPE", "A file is a PDF, an image, a document, a spreadsheet, a slide deck, a zip, an MP3 or an MP4.",
                    new DomainRuleViolation.Remedy("Save it as one of those; anything larger than 5 MB is linked by address instead.", "You"));
        }
        byte[] content;
        try {
            content = Base64.getDecoder().decode(base64);
        } catch (IllegalArgumentException notBase64) {
            throw new DomainRuleViolation("LMS_FILE_ENCODING", "The file did not arrive intact.", new DomainRuleViolation.Remedy("Try the upload again.", "You"));
        }
        if (content.length == 0 || content.length > MAX_FILE) {
            throw new DomainRuleViolation("LMS_FILE_SIZE", "A file is between 1 byte and 5 MB; this one is " + content.length + " bytes.",
                    new DomainRuleViolation.Remedy("Compress it, or publish it by address and link it here.", "You"));
        }
        return content;
    }

    /* ── the student ── */

    @Transactional(readOnly = true)
    public Map<String, Object> mine(UUID student, String sessionAsked) {
        String session = session(sessionAsked);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("session", session);
        out.put("spaces", repo.studentSpaces(student, session));
        return out;
    }

    @Transactional(readOnly = true)
    public Map<String, Object> space(UUID student, UUID offering) {
        if (!repo.onRoll(offering, student)) {
            throw new NotFound("course space", offering);
        }
        Map<String, Object> out = new LinkedHashMap<>(repo.offering(offering));
        out.put("materials", repo.materials(offering, true, student));
        out.put("assignments", repo.assignments(offering, student));
        return out;
    }

    @Transactional
    public LmsRepository.FileContent read(UUID student, UUID material) {
        UUID offering = repo.offeringOfMaterial(material).orElseThrow(() -> new NotFound("material", material));
        if (!repo.onRoll(offering, student)) {
            throw new NotFound("material", material);
        }
        repo.countRead(material, student);
        return repo.materialContent(material).orElseThrow(() -> new NotFound("file for material", material));
    }

    @Transactional
    public Map<String, Object> noteRead(UUID student, UUID material) {
        UUID offering = repo.offeringOfMaterial(material).orElseThrow(() -> new NotFound("material", material));
        if (!repo.onRoll(offering, student)) {
            throw new NotFound("material", material);
        }
        repo.countRead(material, student);
        return Map.of("materialId", material, "read", true);
    }

    @Transactional
    public Map<String, Object> submit(UUID student, UUID assignment, String text, String filename, String contentType, String base64) {
        byte[] content = decode(base64, contentType);
        if ((text == null || text.isBlank()) && content == null) {
            throw new DomainRuleViolation("LMS_SUBMISSION_EMPTY", "A submission is text, a file, or both.", new DomainRuleViolation.Remedy("Write it or attach it.", "You"));
        }
        UUID id = repo.submit(assignment, student, text, content == null ? null : (filename == null || filename.isBlank() ? "submission" : filename.trim()), content == null ? null : contentType, content);
        return Map.of("submissionId", id);
    }

    /* ── the lecturer ── */

    @Transactional(readOnly = true)
    public Map<String, Object> teaching(String sessionAsked) {
        String session = session(sessionAsked);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("session", session);
        out.put("spaces", repo.lecturerSpaces(me(), session));
        return out;
    }

    private void requireTeaches(UUID offering) {
        String office = AuditContextHolder.required().actorOffice();
        if (!repo.teaches(offering, me()) && !List.of("hod", "dean", "academic", "super").contains(office)) {
            throw new DomainRuleViolation("LMS_NOT_YOURS", "This course space belongs to the lecturer the department allocated.",
                    new DomainRuleViolation.Remedy("The Head of Department allocates the course; the space follows the allocation.", "Head of Department"));
        }
    }

    @Transactional(readOnly = true)
    public Map<String, Object> desk(UUID offering) {
        requireTeaches(offering);
        Map<String, Object> out = new LinkedHashMap<>(repo.offering(offering));
        out.put("materials", repo.materials(offering, false, null));
        out.put("assignments", repo.assignments(offering, null));
        out.put("gradebook", repo.gradebook(offering));
        out.put("engagement", repo.engagement(offering));
        return out;
    }

    @Transactional
    public Map<String, Object> addMaterial(UUID offering, Integer week, String title, String kind, String description, String filename, String contentType,
                                           String base64, String link, boolean publish) {
        requireTeaches(offering);
        if (title == null || title.isBlank()) {
            throw new DomainRuleViolation("LMS_TITLE", "Material has a title.", new DomainRuleViolation.Remedy("What the students will see.", "You"));
        }
        String k = kind == null || kind.isBlank() ? "NOTES" : kind.trim().toUpperCase();
        if (!KINDS.contains(k)) {
            throw new DomainRuleViolation("LMS_KIND", "The kind is one the space knows.", new DomainRuleViolation.Remedy(String.join(", ", KINDS), "You"));
        }
        byte[] content = decode(base64, contentType);
        if (content == null && (link == null || link.isBlank())) {
            throw new DomainRuleViolation("LMS_MATERIAL_EMPTY", "Material is a file up to 5 MB, or an address.", new DomainRuleViolation.Remedy("Attach it or link it.", "You"));
        }
        UUID id = repo.addMaterial(offering, week, title.trim(), k, description, content == null ? null : filename, content == null ? null : contentType, content,
                link == null || link.isBlank() ? null : link.trim(), publish, me());
        return Map.of("materialId", id, "published", publish, "bytes", content == null ? 0 : content.length);
    }

    @Transactional
    public Map<String, Object> publish(UUID offering, UUID material) {
        requireTeaches(offering);
        if (repo.publish(material, offering, me()) == 0) {
            throw new NotFound("unpublished material", material);
        }
        return Map.of("materialId", material, "published", true);
    }

    @Transactional
    public Map<String, Object> end(UUID offering, UUID material) {
        requireTeaches(offering);
        if (repo.endMaterial(material, offering) == 0) {
            throw new NotFound("material", material);
        }
        return Map.of("materialId", material, "ended", true);
    }

    @Transactional(readOnly = true)
    public LmsRepository.FileContent materialForLecturer(UUID offering, UUID material) {
        requireTeaches(offering);
        return repo.materialContent(material).orElseThrow(() -> new NotFound("file for material", material));
    }

    @Transactional
    public Map<String, Object> addAssignment(UUID offering, String title, String brief, String kind, OffsetDateTime opens, OffsetDateTime closes, Integer lateHours,
                                             Integer latePenalty, Integer weight, Integer outOf) {
        requireTeaches(offering);
        if (title == null || title.isBlank() || closes == null || weight == null) {
            throw new DomainRuleViolation("LMS_ASSIGNMENT", "An assignment has a title, a closing time and a weight.",
                    new DomainRuleViolation.Remedy("The weight is its share of the 40 marks of continuous assessment.", "You"));
        }
        String k = kind == null || kind.isBlank() ? "INDIVIDUAL" : kind.trim().toUpperCase();
        return Map.of("assignmentId", repo.addAssignment(offering, title.trim(), brief, k, opens, closes, lateHours, latePenalty, weight, outOf, me()));
    }

    @Transactional(readOnly = true)
    public List<Map<String, Object>> submissions(UUID offering, UUID assignment) {
        requireTeaches(offering);
        UUID of = repo.offeringOfAssignment(assignment).orElseThrow(() -> new NotFound("assignment", assignment));
        if (!of.equals(offering)) {
            throw new NotFound("assignment", assignment);
        }
        return repo.submissions(assignment);
    }

    @Transactional
    public Map<String, Object> mark(UUID offering, UUID assignment, UUID submission, BigDecimal mark, String feedback) {
        requireTeaches(offering);
        if (mark == null || mark.signum() < 0) {
            throw new DomainRuleViolation("LMS_MARK", "A mark is a number from zero.", new DomainRuleViolation.Remedy("Out of what the assignment states.", "You"));
        }
        if (repo.mark(submission, assignment, mark, feedback, me()) == 0) {
            throw new NotFound("submission", submission);
        }
        return Map.of("submissionId", submission, "mark", mark);
    }

    @Transactional(readOnly = true)
    public LmsRepository.FileContent submissionFile(UUID offering, UUID submission) {
        requireTeaches(offering);
        Map<String, Object> o = repo.submissionOwner(submission).orElseThrow(() -> new NotFound("submission", submission));
        if (!offering.equals(o.get("offering_id"))) {
            throw new NotFound("submission", submission);
        }
        return repo.submissionContent(submission).orElseThrow(() -> new NotFound("file for submission", submission));
    }

    @Transactional
    public Map<String, Object> promote(UUID offering) {
        requireTeaches(offering);
        return Map.of("offeringId", offering, "written", repo.promote(offering));
    }
}
