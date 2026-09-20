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
                         (SELECT 'data:' || coalesce(nullif(btrim(d.content_type), ''), 'image/jpeg') || ';base64,' || encode(b.content, 'base64')
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

    /** sha256(payload), hex, upper-cased, first 12 — the stateless check token every QR carries */
    private static String digest12(String payload) {
        try {
            byte[] d = MessageDigest.getInstance("SHA-256").digest(payload.getBytes(StandardCharsets.UTF_8));
            StringBuilder sb = new StringBuilder(d.length * 2);
            for (byte b : d) sb.append(Character.forDigit((b >> 4) & 0xF, 16)).append(Character.forDigit(b & 0xF, 16));
            return sb.substring(0, 12).toUpperCase();
        } catch (Exception e) {
            return "";
        }
    }

    private static String examToken(String matric, String session, int semester) {
        return digest12("EXAM|" + matric + "|" + session + "|" + semester);
    }

    private static String regToken(String matric, String session, int semester) {
        return digest12("REG|" + matric + "|" + session + "|" + semester);
    }

    private static String resultToken(String matric, String session, int semester) {
        return digest12("RESULT|" + matric + "|" + session + "|" + semester);
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
                         WHERE a.candidate_id = s.candidate_id AND d.kind = 'PASSPORT' AND d.superseded_at IS NULL
                         ORDER BY d.id LIMIT 1) AS passport_id
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
        if (photo == null) {
            // fall back to the JAMB/attachment store — a migrated or JAMB-loaded photo (no candidate document),
            // matched by the student's candidate or their own JAMB number, so it also shows at the exam hall
            List<Map<String, Object>> at = jdbc.sql("""
                    SELECT at.payload->>'dataUrl' AS url FROM people.student s
                      JOIN admissions.attachment at ON at.kind = 'PASSPORT' AND jsonb_exists(at.payload, 'dataUrl')
                         AND (at.candidate_id = s.candidate_id
                              OR (s.jamb_reg_no IS NOT NULL AND at.jamb_key = upper(btrim(s.jamb_reg_no))))
                     WHERE s.id = :s LIMIT 1
                    """).param("s", sid).query().listOfRows();
            if (!at.isEmpty() && at.get(0).get("url") != null) photo = String.valueOf(at.get(0).get("url"));
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

    /**
     * Verify a course registration form. The form's QR opens the public page, which asks this for the
     * University's own record: the student, the approved courses, the units and the approval date. The
     * record is the truth; the printed form is a view of it, so a form whose courses, units or approval
     * date do not match here is exposed. The stateless check token (sha256 of matric|session|semester)
     * gates enumeration, and only an approved registration is returned.
     */
    @GetMapping("/registration")
    @Transactional(readOnly = true)
    Map<String, Object> registration(@RequestParam String matric, @RequestParam String session,
                                     @RequestParam(defaultValue = "1") int semester, @RequestParam(required = false) String c) {
        Map<String, Object> out = new LinkedHashMap<>();
        List<Map<String, Object>> rows = jdbc.sql("""
                SELECT r.id, trim(upper(s.surname) || ', ' || s.other_names) AS name, s.matric_no, pg.name AS programme,
                       r.level, r.status, r.approved_at, r.submitted_at, registration.units_of(r.id) AS units
                  FROM registration.course_registration r
                  JOIN people.student s ON s.id = r.student_id
                  LEFT JOIN ref.programme pg ON pg.code = s.programme_code
                 WHERE upper(s.matric_no) = upper(:m) AND r.session = :session AND r.semester = :sem
                   AND r.status IN ('APPROVED','LOCKED')
                 ORDER BY r.approved_at DESC NULLS LAST LIMIT 1
                """).param("m", matric).param("session", session).param("sem", semester).query().listOfRows();
        if (rows.isEmpty()) { out.put("genuine", false); return out; }
        Map<String, Object> row = rows.get(0);
        if (c == null || !regToken(String.valueOf(row.get("matric_no")), session, semester).equalsIgnoreCase(c.trim())) {
            out.put("genuine", false); return out;
        }
        java.util.UUID rid = (java.util.UUID) row.get("id");
        List<Map<String, Object>> courses = jdbc.sql("""
                SELECT c.code AS course_code, c.title, e.units, e.entry_type, c.kind
                  FROM registration.entry e
                  JOIN catalogue.offering o ON o.id = e.offering_id JOIN catalogue.course c ON c.code = o.course_code
                 WHERE e.registration_id = :r AND e.status IN ('REGISTERED','APPROVED')
                 ORDER BY (e.entry_type = 'CARRYOVER') DESC, c.code
                """).param("r", rid).query().listOfRows();
        out.put("genuine", true);
        out.put("name", row.get("name"));
        out.put("matricNo", row.get("matric_no"));
        out.put("programme", row.get("programme"));
        out.put("level", row.get("level"));
        out.put("session", session);
        out.put("semester", semester);
        out.put("status", row.get("status"));
        out.put("approvedOn", row.get("approved_at"));
        out.put("units", row.get("units"));
        out.put("courses", courses);
        return out;
    }

    /**
     * Verify a semester results statement. The statement's QR opens the public page, which asks this for
     * the University's own record: the published grades, the semester and cumulative GPA, the class of
     * standing and the Senate approval date. Only published results are returned, and only when the
     * stateless check token (sha256 of matric|session|semester) matches — so a statement whose grades or
     * GPA do not match here is exposed, and the records cannot be enumerated.
     */
    @GetMapping("/results")
    @Transactional(readOnly = true)
    Map<String, Object> results(@RequestParam String matric, @RequestParam String session,
                                @RequestParam(defaultValue = "1") int semester, @RequestParam(required = false) String c) {
        Map<String, Object> out = new LinkedHashMap<>();
        List<Map<String, Object>> stu = jdbc.sql("""
                SELECT s.id, trim(upper(s.surname) || ', ' || s.other_names) AS name, s.matric_no, pg.name AS programme,
                       coalesce((SELECT e.level FROM people.enrolment e WHERE e.student_id = s.id AND e.session = :session LIMIT 1),
                                s.current_level) AS level
                  FROM people.student s LEFT JOIN ref.programme pg ON pg.code = s.programme_code
                 WHERE upper(s.matric_no) = upper(:m) LIMIT 1
                """).param("m", matric).param("session", session).query().listOfRows();
        if (stu.isEmpty()) { out.put("genuine", false); return out; }
        Map<String, Object> s = stu.get(0);
        if (c == null || !resultToken(String.valueOf(s.get("matric_no")), session, semester).equalsIgnoreCase(c.trim())) {
            out.put("genuine", false); return out;
        }
        java.util.UUID sid = (java.util.UUID) s.get("id");
        List<Map<String, Object>> rows = jdbc.sql("""
                SELECT course_code, title, units, total, grade, points, outcome, published_at, senate_minute
                  FROM assessment.student_results(:s)
                 WHERE session = :session AND semester = :sem AND published
                 ORDER BY course_code
                """).param("s", sid).param("session", session).param("sem", semester).query().listOfRows();
        if (rows.isEmpty()) { out.put("genuine", false); return out; }
        List<Map<String, Object>> g = jdbc.sql("""
                SELECT gpa, cgpa FROM assessment.student_gpa(:s) WHERE session = :session AND semester = :sem LIMIT 1
                """).param("s", sid).param("session", session).param("sem", semester).query().listOfRows();
        Object gpa = g.isEmpty() ? null : g.get(0).get("gpa");
        Object cgpa = g.isEmpty() ? null : g.get(0).get("cgpa");
        String standing = null;
        if (cgpa != null) {
            standing = jdbc.sql("SELECT policy.class_of(:c)").param("c", cgpa).query(String.class).optional().orElse(null);
        }
        out.put("genuine", true);
        out.put("name", s.get("name"));
        out.put("matricNo", s.get("matric_no"));
        out.put("programme", s.get("programme"));
        out.put("level", s.get("level"));
        out.put("session", session);
        out.put("semester", semester);
        out.put("gpa", gpa);
        out.put("cgpa", cgpa);
        out.put("standing", standing);
        out.put("approvedOn", rows.get(0).get("published_at"));
        out.put("senateMinute", rows.get(0).get("senate_minute"));
        out.put("rows", rows);
        return out;
    }
}
