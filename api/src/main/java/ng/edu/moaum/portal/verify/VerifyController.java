package ng.edu.moaum.portal.verify;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * Public receipt verification. A receipt's QR opens the verification page, which
 * asks this endpoint for the authoritative Bursary record. The record is the
 * truth; the printed receipt is only a view of it, so an altered or cloned
 * receipt is exposed when the payer, amount or date shown here does not match
 * the paper. Unauthenticated (see SecurityConfig): it returns only a confirmed
 * receipt, and only when the stateless check token on the QR matches — so the
 * references cannot simply be enumerated to harvest names and amounts.
 */
@RestController
@RequestMapping("/api/v1/verify")
class VerifyController {

    private final JdbcClient jdbc;

    VerifyController(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    /** the same digest the receipt carries: sha256(reference|receiptNo), hex, upper-cased, first 12 */
    private static String token(String reference, String receiptNo) {
        try {
            byte[] d = MessageDigest.getInstance("SHA-256")
                    .digest((reference + "|" + (receiptNo == null ? "" : receiptNo)).getBytes(StandardCharsets.UTF_8));
            StringBuilder sb = new StringBuilder(d.length * 2);
            for (byte b : d) sb.append(Character.forDigit((b >> 4) & 0xF, 16)).append(Character.forDigit(b & 0xF, 16));
            return sb.substring(0, 12).toUpperCase();
        } catch (Exception e) {
            return "";
        }
    }

    @GetMapping("/receipt/{reference}")
    @Transactional(readOnly = true)
    Map<String, Object> receipt(@PathVariable String reference, @RequestParam(required = false) String c) {
        List<Map<String, Object>> rows = jdbc.sql("""
                SELECT pr.reference, pr.receipt_no, pr.amount, pr.purpose, pr.session, pr.channel, pr.confirmed_at,
                       finance.payment_term(pr.id) AS term,
                       trim(upper(s.surname) || ', ' || s.other_names) AS name, s.matric_no, pg.name AS programme,
                       coalesce(
                         (SELECT e.level FROM people.enrolment e WHERE e.student_id = pr.student_id AND e.session = pr.session LIMIT 1),
                         CASE WHEN pr.session ~ '^[0-9]{4}/[0-9]{4}$'
                              THEN least(600, greatest(100, s.entry_level + (left(pr.session, 4)::int - left(s.entry_session, 4)::int) * 100))
                              ELSE s.current_level END) AS level,
                       coalesce(
                         (SELECT 'data:' || d.content_type || ';base64,' || encode(b.content, 'base64')
                            FROM admissions.application_document d
                            JOIN admissions.application ap ON ap.id = d.application_id
                            JOIN admissions.application_document_blob b ON b.document_id = d.id
                           WHERE ap.candidate_id = s.candidate_id AND d.kind = 'PASSPORT' AND d.superseded_at IS NULL
                           ORDER BY d.id LIMIT 1),
                         (SELECT at.payload->>'dataUrl' FROM admissions.attachment at
                           WHERE at.candidate_id = s.candidate_id AND at.kind = 'PASSPORT'
                             AND jsonb_exists(at.payload, 'dataUrl') LIMIT 1)) AS passport
                  FROM finance.payment_reference pr
                  JOIN people.student s ON s.id = pr.student_id
                  LEFT JOIN ref.programme pg ON pg.code = s.programme_code
                 WHERE (upper(pr.reference) = upper(:ref) OR upper(coalesce(pr.receipt_no, '')) = upper(:ref))
                   AND pr.confirmed_at IS NOT NULL
                 LIMIT 1
                """).param("ref", reference).query().listOfRows();

        Map<String, Object> out = new LinkedHashMap<>();
        if (rows.isEmpty()) { out.put("genuine", false); return out; }
        Map<String, Object> row = rows.get(0);
        String expected = token(String.valueOf(row.get("reference")), row.get("receipt_no") == null ? null : String.valueOf(row.get("receipt_no")));
        if (c == null || !expected.equalsIgnoreCase(c.trim())) { out.put("genuine", false); return out; }

        out.put("genuine", true);
        out.put("name", row.get("name"));
        out.put("matricNo", row.get("matric_no"));
        out.put("programme", row.get("programme"));
        out.put("level", row.get("level"));
        out.put("amount", row.get("amount"));
        out.put("purpose", row.get("purpose"));
        out.put("session", row.get("session"));
        out.put("term", row.get("term"));
        out.put("channel", row.get("channel"));
        out.put("confirmedOn", row.get("confirmed_at"));
        out.put("receiptNo", row.get("receipt_no"));
        out.put("passport", row.get("passport"));
        return out;
    }

    private static String examToken(String matric, String session, int semester) {
        try {
            byte[] d = MessageDigest.getInstance("SHA-256")
                    .digest(("EXAM|" + matric + "|" + session + "|" + semester).getBytes(StandardCharsets.UTF_8));
            StringBuilder sb = new StringBuilder(d.length * 2);
            for (byte b : d) sb.append(Character.forDigit((b >> 4) & 0xF, 16)).append(Character.forDigit(b & 0xF, 16));
            return sb.substring(0, 12).toUpperCase();
        } catch (Exception e) {
            return "";
        }
    }

    /**
     * Verify a student's examination card. The card's QR opens the public page, which asks this for
     * the authoritative permit: the student's name and PHOTO (so the invigilator confirms the face —
     * anti-impersonation), whether they are cleared for the examination, and the courses on the
     * approved registration for the session and semester (anti-clone: an edited card is exposed).
     */
    @GetMapping("/exam")
    @Transactional(readOnly = true)
    Map<String, Object> exam(@RequestParam String matric, @RequestParam String session,
                             @RequestParam(defaultValue = "1") int semester, @RequestParam(required = false) String c) {
        Map<String, Object> out = new LinkedHashMap<>();
        List<Map<String, Object>> rows = jdbc.sql("""
                SELECT s.id, trim(s.other_names || ' ' || s.surname) AS name, s.matric_no, s.current_level, pg.name AS programme,
                       finance.clears(s.id, :session, 'EXAMINATION') AS cleared,
                       (SELECT d.id FROM admissions.application_document d JOIN admissions.application a ON a.id = d.application_id
                         WHERE a.candidate_id = s.candidate_id AND d.kind = 'PASSPORT' AND d.superseded_at IS NULL) AS passport_id
                  FROM people.student s LEFT JOIN ref.programme pg ON pg.code = s.programme_code
                 WHERE upper(s.matric_no) = upper(:m) LIMIT 1
                """).param("m", matric).param("session", session).query().listOfRows();
        if (rows.isEmpty()) { out.put("genuine", false); return out; }
        Map<String, Object> row = rows.get(0);
        if (c == null || !examToken(String.valueOf(row.get("matric_no")), session, semester).equalsIgnoreCase(c.trim())) {
            out.put("genuine", false); return out;
        }
        java.util.UUID sid = (java.util.UUID) row.get("id");
        List<Map<String, Object>> courses = jdbc.sql("""
                SELECT c.code AS course_code, c.title, e.units, e.entry_type
                  FROM registration.course_registration r
                  JOIN registration.entry e ON e.registration_id = r.id AND e.status IN ('REGISTERED','APPROVED')
                  JOIN catalogue.offering o ON o.id = e.offering_id JOIN catalogue.course c ON c.code = o.course_code
                 WHERE r.student_id = :s AND r.session = :session AND r.semester = :sem AND r.status IN ('APPROVED','LOCKED')
                 ORDER BY c.code
                """).param("s", sid).param("session", session).param("sem", semester).query().listOfRows();

        String photo = null;
        Object pid = row.get("passport_id");
        if (pid != null) {
            List<Map<String, Object>> b = jdbc.sql("SELECT encode(content, 'base64') AS b64 FROM admissions.application_document_blob WHERE document_id = :d")
                    .param("d", pid).query().listOfRows();
            if (!b.isEmpty() && b.get(0).get("b64") != null) photo = "data:image/jpeg;base64," + b.get(0).get("b64");
        }

        out.put("genuine", true);
        out.put("name", row.get("name"));
        out.put("matricNo", row.get("matric_no"));
        out.put("programme", row.get("programme"));
        out.put("level", row.get("current_level"));
        out.put("session", session);
        out.put("semester", semester);
        out.put("cleared", row.get("cleared"));
        out.put("photo", photo);
        out.put("courses", courses);
        return out;
    }
}
