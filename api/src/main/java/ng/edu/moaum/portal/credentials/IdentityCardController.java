package ng.edu.moaum.portal.credentials;

import java.sql.Types;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import jakarta.validation.Valid;
import jakarta.validation.constraints.Size;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * The Library's card desk (V027): the students on the matriculation
 * register who hold no live card, the cards issued, and the act of issuing
 * one — on the matriculation number, when the scheme releases ID_CARD, one
 * live card at a time; a lost card is ended on the record and replaced.
 */
@RestController
@RequestMapping("/api/v1/credentials/identity-cards")
class IdentityCardController {

    private static final String READERS = "hasAnyAuthority('OFFICE_library','OFFICE_security','OFFICE_registrar','OFFICE_dregistrar','OFFICE_academic','OFFICE_records','OFFICE_ict','OFFICE_super')";
    /** GAP-005 (the University's decision, 16 Oct 2026): the Security Unit alone prints, issues and reports a card lost — as the
     *  brief has it; the Library and the other offices read a card's status (super stays the system's break-glass) */
    private static final String ISSUERS = "hasAnyAuthority('OFFICE_security','OFFICE_super')";
    /** V439: the staff cards are read by the card desk and by HR, whose staff record prints the card */
    private static final String STAFF_READERS = "hasAnyAuthority('OFFICE_library','OFFICE_security','OFFICE_registrar','OFFICE_dregistrar','OFFICE_academic','OFFICE_records','OFFICE_ict','OFFICE_hrm','OFFICE_super')";

    public record Issue(@Size(max = 200) String reason) {
    }

    private final JdbcClient jdbc;
    private final ng.edu.moaum.portal.shared.CheckCodes codes;
    private final ng.edu.moaum.portal.shared.FileObjects files;
    private final ng.edu.moaum.portal.studentportal.StudentPortalService portal;

    IdentityCardController(JdbcClient jdbc, ng.edu.moaum.portal.shared.CheckCodes codes, ng.edu.moaum.portal.shared.FileObjects files,
                           ng.edu.moaum.portal.studentportal.StudentPortalService portal) {
        this.jdbc = jdbc;
        this.codes = codes;
        this.files = files;
        this.portal = portal;
    }

    @GetMapping
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> desk(@RequestParam(required = false) String q) {
        List<Map<String, Object>> cards = jdbc.sql("""
                SELECT c.id, c.card_no, c.issued_at, c.valid_to, c.state, c.ended_at, c.ended_reason,
                       s.id AS student_id, s.matric_no, s.surname, s.other_names, p.name AS programme, s.current_level
                  FROM credentials.identity_card c JOIN people.student s ON s.id = c.student_id JOIN ref.programme p ON p.code = s.programme_code
                 ORDER BY c.issued_at DESC LIMIT 300
                """).query().listOfRows();
        // the address the card's QR carries: the public page answers only with the code signed over the card number
        cards = cards.stream().map(r -> {
            Map<String, Object> m = new java.util.LinkedHashMap<>(r);
            String no = String.valueOf(r.get("card_no"));
            m.put("verify_path", "/verify/idcard?no=" + java.net.URLEncoder.encode(no, java.nio.charset.StandardCharsets.UTF_8)
                    + "&c=" + codes.sign(ng.edu.moaum.portal.shared.CheckCodes.Kind.ID_CARD, no));
            return m;
        }).toList();
        List<Map<String, Object>> waiting = jdbc.sql("""
                SELECT s.id AS student_id, s.matric_no, s.surname, s.other_names, p.name AS programme, s.current_level, s.status,
                       EXISTS (SELECT 1 FROM credentials.identity_card c WHERE c.student_id = s.id) AS had_one
                  FROM people.student s JOIN ref.programme p ON p.code = s.programme_code
                 -- a card is keyed on the matriculation number: every matriculated student still on the books
                 -- (admitted, active, on probation, or dormant between sessions) may be issued one; the
                 -- withdrawn, expelled, transferred-out, graduated and deceased may not
                 WHERE s.matric_no IS NOT NULL AND s.status IN ('ADMITTED','ACTIVE','PROBATION','DORMANT')
                   AND NOT EXISTS (SELECT 1 FROM credentials.identity_card c WHERE c.student_id = s.id AND c.state = 'ISSUED')
                   AND (:q::text IS NULL OR s.matric_no ILIKE '%' || :q || '%' OR s.surname ILIKE '%' || :q || '%')
                 ORDER BY s.surname LIMIT 200
                """).param("q", q, Types.VARCHAR).query().listOfRows();
        return Map.of("cards", cards, "waiting", waiting);
    }

    @PostMapping("/students/{studentId}/issue")
    @PreAuthorize(ISSUERS)
    @Transactional
    Map<String, Object> issue(@PathVariable UUID studentId, @RequestBody(required = false) @Valid Issue body) {
        String no = jdbc.sql("SELECT credentials.issue_identity_card(:s, :r)").param("s", studentId).param("r", body == null ? null : body.reason(), Types.VARCHAR)
                .query(String.class).single();
        return Map.of("studentId", studentId, "cardNo", no);
    }

    @PostMapping("/students/{studentId}/lost")
    @PreAuthorize(ISSUERS)
    @Transactional
    Map<String, Object> lost(@PathVariable UUID studentId, @RequestBody(required = false) @Valid Issue body) {
        int n = jdbc.sql("SELECT credentials.report_card_lost(:s, :r)").param("s", studentId).param("r", body == null ? null : body.reason(), Types.VARCHAR)
                .query(Integer.class).single();
        return Map.of("studentId", studentId, "ended", n);
    }

    /* ── the student card printed at the desk: the card in the register, its QR the signed check address ── */

    /** the live card of one student, with what the card shows, for the desk's print — none until the desk issues one */
    @GetMapping("/students/{studentId}/card")
    @PreAuthorize(ISSUERS)   // the printable card: the Security Unit's (GAP-005)
    @Transactional(readOnly = true)
    Map<String, Object> studentCard(@PathVariable UUID studentId) {
        Map<String, Object> row = jdbc.sql("""
                SELECT c.card_no, c.issued_at, c.valid_to, s.surname || ', ' || s.other_names AS name, s.matric_no, p.name AS programme,
                       f.name AS faculty, s.current_level AS level, s.entry_session, policy.university_current_session() AS session,
                       (SELECT r.phone FROM people.student_reach(s.id) r) AS reach_phone
                  FROM credentials.identity_card c JOIN people.student s ON s.id = c.student_id
                  LEFT JOIN ref.programme p ON p.code = s.programme_code LEFT JOIN ref.faculty f ON f.code = p.faculty_code
                 WHERE c.student_id = :s AND c.state = 'ISSUED'
                """).param("s", studentId).query().listOfRows().stream().findFirst()
                .orElseThrow(() -> new ng.edu.moaum.portal.shared.DomainRuleViolation("ID_CARD_NONE", "No identity card is in force for this student.",
                        new ng.edu.moaum.portal.shared.DomainRuleViolation.Remedy("Issue the card first; the print carries its number.", "Security Unit")));
        Map<String, Object> m = new java.util.LinkedHashMap<>(row);
        String no = String.valueOf(row.get("card_no"));
        m.put("verify_path", "/verify/idcard?no=" + java.net.URLEncoder.encode(no, java.nio.charset.StandardCharsets.UTF_8)
                + "&c=" + codes.sign(ng.edu.moaum.portal.shared.CheckCodes.Kind.ID_CARD, no));
        m.put("has_photo", portal.passportImage(studentId).isPresent());
        return m;
    }

    /** the photograph the student card carries, for the desk's print — only of a student with a card in force */
    @GetMapping("/students/{studentId}/photo")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    org.springframework.http.ResponseEntity<byte[]> studentPhoto(@PathVariable UUID studentId) {
        boolean carded = jdbc.sql("SELECT EXISTS (SELECT 1 FROM credentials.identity_card WHERE student_id = :s AND state = 'ISSUED')")
                .param("s", studentId).query(Boolean.class).single();
        if (!carded) return org.springframework.http.ResponseEntity.notFound().build();
        return portal.passportImage(studentId)
                .map(img -> org.springframework.http.ResponseEntity.ok().contentType(org.springframework.http.MediaType.IMAGE_JPEG)
                        .cacheControl(org.springframework.http.CacheControl.noStore()).body(img))
                .orElseGet(() -> org.springframework.http.ResponseEntity.notFound().build());
    }

    /* ── V439 · staff identity cards: the register, issued on the staff number by the same desk ── */

    /** the address a staff card's QR carries; the public page answers only with the code signed over the card number */
    private String staffVerifyPath(String cardNo) {
        return "/verify/staffcard?no=" + java.net.URLEncoder.encode(cardNo, java.nio.charset.StandardCharsets.UTF_8)
                + "&c=" + codes.sign(ng.edu.moaum.portal.shared.CheckCodes.Kind.STAFF_CARD, cardNo);
    }

    private static final String STAFF_CARD_ROWS = """
            SELECT c.id, c.card_no, c.issued_at, c.valid_to, c.state, c.ended_at, c.ended_reason, c.issued_office,
                   p.id AS person_id, p.staff_number, p.surname, p.given_names, d.name AS department
              FROM credentials.staff_identity_card c JOIN iam.person p ON p.id = c.person_id
              LEFT JOIN hrm.staff_record r ON r.person_id = p.id LEFT JOIN ref.department d ON d.code = r.home_department
            """;

    @GetMapping("/staff")
    @PreAuthorize(STAFF_READERS)
    @Transactional(readOnly = true)
    Map<String, Object> staffDesk(@RequestParam(required = false) String q) {
        List<Map<String, Object>> cards = jdbc.sql(STAFF_CARD_ROWS + """
                 WHERE (:q::text IS NULL OR p.staff_number ILIKE '%' || :q || '%' OR p.surname ILIKE '%' || :q || '%' OR c.card_no ILIKE '%' || :q || '%')
                 ORDER BY c.issued_at DESC LIMIT 300
                """).param("q", q == null || q.isBlank() ? null : q.trim(), Types.VARCHAR).query().listOfRows().stream().map(r -> {
            Map<String, Object> m = new java.util.LinkedHashMap<>(r);
            m.put("verify_path", staffVerifyPath(String.valueOf(r.get("card_no"))));
            return m;
        }).toList();
        return Map.of("cards", cards);
    }

    /** the live card of one member of staff, for the print — none until the desk issues one */
    @GetMapping("/staff/{personId}/card")
    @PreAuthorize(ISSUERS)   // the printable card: the Security Unit's (GAP-005)
    @Transactional(readOnly = true)
    Map<String, Object> staffCard(@PathVariable UUID personId) {
        Map<String, Object> row = jdbc.sql(STAFF_CARD_ROWS + " WHERE c.person_id = :p AND c.state = 'ISSUED'").param("p", personId)
                .query().listOfRows().stream().findFirst()
                .orElseThrow(() -> new ng.edu.moaum.portal.shared.DomainRuleViolation("STAFF_CARD_NONE", "No staff identity card is in force for this person.",
                        new ng.edu.moaum.portal.shared.DomainRuleViolation.Remedy("Issue the card on the card desk first; the print carries its number.", "Security Unit")));
        Map<String, Object> m = new java.util.LinkedHashMap<>(row);
        m.put("verify_path", staffVerifyPath(String.valueOf(row.get("card_no"))));
        // what the card shows, and nothing more of the HR record: the desk prints from the register
        m.put("face", jdbc.sql("""
                SELECT pe.staff_number, pe.surname, pe.given_names, sr.present_rank AS rank, dp.name AS department, f.name AS faculty, e.category,
                       sr.date_first_appointment, e.appointment_date, EXISTS (SELECT 1 FROM hrm.staff_photo ph WHERE ph.person_id = pe.id) AS has_photo
                  FROM iam.person pe LEFT JOIN hrm.staff_record sr ON sr.person_id = pe.id
                  LEFT JOIN hrm.employment e ON e.person_id = pe.id AND e.status <> 'ENDED'
                  LEFT JOIN ref.department dp ON dp.code = sr.home_department LEFT JOIN ref.faculty f ON f.code = dp.faculty_code
                 WHERE pe.id = :p
                """).param("p", personId).query().listOfRows().stream().findFirst().orElse(Map.of()));
        m.put("offices", jdbc.sql("""
                SELECT a.office_code, o.label AS office FROM iam.office_assignment a JOIN ref.office o ON o.code = a.office_code
                 WHERE a.person_id = :p AND a.valid_from <= current_date AND (a.valid_to IS NULL OR a.valid_to >= current_date)
                 ORDER BY a.valid_from DESC
                """).param("p", personId).query().listOfRows());
        return m;
    }

    /** the photograph the card carries, for the desk's print — only of a member of staff with a card in force */
    @GetMapping("/staff/{personId}/photo")
    @PreAuthorize(STAFF_READERS)
    @Transactional(readOnly = true)
    org.springframework.http.ResponseEntity<byte[]> staffPhoto(@PathVariable UUID personId) {
        boolean carded = jdbc.sql("SELECT EXISTS (SELECT 1 FROM credentials.staff_identity_card WHERE person_id = :p AND state = 'ISSUED')")
                .param("p", personId).query(Boolean.class).single();
        if (!carded) return org.springframework.http.ResponseEntity.notFound().build();
        return jdbc.sql("SELECT content_type, content, object_id FROM hrm.staff_photo WHERE person_id = :p").param("p", personId)
                .query().listOfRows().stream().findFirst()
                .map(r -> org.springframework.http.ResponseEntity.ok()
                        .contentType(org.springframework.http.MediaType.parseMediaType(String.valueOf(r.get("content_type"))))
                        .body(files.resolve((byte[]) r.get("content"), (UUID) r.get("object_id"))))
                .orElseGet(() -> org.springframework.http.ResponseEntity.notFound().build());
    }

    public record StaffIssue(@jakarta.validation.constraints.NotBlank @Size(max = 40) String staffNumber, @Size(max = 200) String reason) {
    }

    @PostMapping("/staff/issue")
    @PreAuthorize(ISSUERS)
    @Transactional
    Map<String, Object> issueStaff(@Valid @RequestBody StaffIssue body) {
        UUID person = jdbc.sql("SELECT id FROM iam.person WHERE upper(staff_number) = upper(:n)").param("n", body.staffNumber().trim())
                .query(UUID.class).optional()
                .orElseThrow(() -> new ng.edu.moaum.portal.shared.DomainRuleViolation("STAFF_CARD_NO_PERSON", "No member of staff carries that staff number.",
                        new ng.edu.moaum.portal.shared.DomainRuleViolation.Remedy("Check the number on the staff record.", "Registry")));
        String no = jdbc.sql("SELECT credentials.issue_staff_card(:p, :r)").param("p", person).param("r", body.reason(), Types.VARCHAR)
                .query(String.class).single();
        return Map.of("personId", person, "cardNo", no);
    }

    @PostMapping("/staff/{personId}/lost")
    @PreAuthorize(ISSUERS)
    @Transactional
    Map<String, Object> staffLost(@PathVariable UUID personId, @RequestBody(required = false) @Valid Issue body) {
        int n = jdbc.sql("SELECT credentials.report_staff_card_lost(:p, :r)").param("p", personId).param("r", body == null ? null : body.reason(), Types.VARCHAR)
                .query(Integer.class).single();
        return Map.of("personId", personId, "ended", n);
    }
}
