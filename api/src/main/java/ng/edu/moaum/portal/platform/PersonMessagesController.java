package ng.edu.moaum.portal.platform;

import java.util.List;
import java.util.Map;
import java.util.UUID;

import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RestController;

import ng.edu.moaum.portal.shared.AuditContext;
import ng.edu.moaum.portal.shared.AuditContextHolder;

/**
 * V440: what the portal sent a student or a member of staff — e-mail, SMS, portal notice — with the provider's word where there
 * is one, read on Student 360 and the HR record by the offices that read the whole University's records; a message that
 * failed, was cancelled, bounced or went undelivered sent again to the address the record holds now.
 */
@RestController
public class PersonMessagesController {

    private static final String STUDENT_READERS = "hasAnyAuthority('OFFICE_ict','OFFICE_admin','OFFICE_super','OFFICE_registrar','OFFICE_dregistrar','OFFICE_records','OFFICE_academic','OFFICE_dsa')";
    private static final String STAFF_READERS = "hasAnyAuthority('OFFICE_ict','OFFICE_admin','OFFICE_super','OFFICE_registrar','OFFICE_dregistrar','OFFICE_hrm','OFFICE_records')";

    private final NoticeRepository notices;

    PersonMessagesController(NoticeRepository notices) {
        this.notices = notices;
    }

    @GetMapping("/api/v1/students/{id}/messages")
    @PreAuthorize(STUDENT_READERS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> studentMessages(@PathVariable UUID id) {
        return notices.messagesFor("student", id);
    }

    @PostMapping("/api/v1/students/{id}/messages/{notice}/resend")
    @PreAuthorize(STUDENT_READERS)
    @Transactional
    Map<String, Object> resendToStudent(@PathVariable UUID id, @PathVariable UUID notice) {
        return resend("student", id, notice);
    }

    @GetMapping("/api/v1/hr/staff/{id}/messages")
    @PreAuthorize(STAFF_READERS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> staffMessages(@PathVariable UUID id) {
        return notices.messagesFor("person", id);
    }

    @PostMapping("/api/v1/hr/staff/{id}/messages/{notice}/resend")
    @PreAuthorize(STAFF_READERS)
    @Transactional
    Map<String, Object> resendToStaff(@PathVariable UUID id, @PathVariable UUID notice) {
        return resend("person", id, notice);
    }

    /** the message must be the person's own: a message of another record is answered as not found */
    private Map<String, Object> resend(String kind, UUID id, UUID notice) {
        if (!notices.isAbout(notice, kind, id)) {
            throw new ng.edu.moaum.portal.shared.NotFound("message", notice);
        }
        AuditContext ctx = AuditContextHolder.required();
        UUID again = notices.resend(notice, ctx.actorId(), ctx.actorOffice());
        return Map.of("resent", again, "messages", notices.messagesFor(kind, id));
    }
}
