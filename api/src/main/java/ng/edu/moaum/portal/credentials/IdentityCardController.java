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
    private static final String ISSUERS = "hasAnyAuthority('OFFICE_library','OFFICE_security','OFFICE_super')";

    public record Issue(@Size(max = 200) String reason) {
    }

    private final JdbcClient jdbc;

    IdentityCardController(JdbcClient jdbc) {
        this.jdbc = jdbc;
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
}
