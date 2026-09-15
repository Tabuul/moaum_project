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
                       trim(s.other_names || ' ' || s.surname) AS name, s.matric_no, pg.name AS programme
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
        out.put("amount", row.get("amount"));
        out.put("purpose", row.get("purpose"));
        out.put("session", row.get("session"));
        out.put("channel", row.get("channel"));
        out.put("confirmedOn", row.get("confirmed_at"));
        out.put("receiptNo", row.get("receipt_no"));
        return out;
    }
}
