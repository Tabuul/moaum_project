package ng.edu.moaum.portal.admissions;

import java.sql.Types;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;

import ng.edu.moaum.portal.shared.DomainRuleViolation;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * The three other JAMB downloads (V007): passports named by the number,
 * dates of birth and O'Level results as spreadsheets. Each is recorded as it
 * arrived and matched on the registration number, in both directions.
 */
@RestController
@RequestMapping("/api/v1/admissions/sessions/{session}/{year}/candidate-data")
class CandidateDataController {

    private static final String READERS =
            "hasAnyAuthority('OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar','OFFICE_records','OFFICE_ict','OFFICE_admin','OFFICE_super')";
    private static final String WRITERS = "hasAnyAuthority('OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar')";

    public record Item(@NotBlank String sourceName, String jambKey, @NotBlank String readAs, Map<String, Object> payload,
                       Long bytes, Integer widthPx, Integer heightPx) {
    }

    public record Batch(@NotBlank String kind, @NotNull List<Item> items) {
    }

    public record Attachment(UUID id, String kind, String sourceName, String jambKey, String readAs, boolean matched,
                             Map<String, Object> payload, Long bytes, Integer widthPx, Integer heightPx, java.time.OffsetDateTime arrivedAt) {
    }

    public record Candidate(UUID id, String jambKey, String surname, String otherNames, String programme, String entryMode,
                            boolean hasPassport, boolean hasDob, boolean hasOlevel) {
    }

    public record State(String session, List<Finding> findings, List<Attachment> attachments, List<Candidate> candidates) {
    }

    private final JdbcClient jdbc;
    private final CapsIntakeService intake;

    CandidateDataController(JdbcClient jdbc, CapsIntakeService intake) {
        this.jdbc = jdbc;
        this.intake = intake;
    }

    @GetMapping
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    State state(@PathVariable String session, @PathVariable String year) {
        String s = session + "/" + year;
        List<Attachment> attachments = jdbc.sql("""
                SELECT id, kind, source_name, jamb_key, read_as, candidate_id IS NOT NULL AS matched,
                       payload::text AS payload_text, bytes, width_px, height_px, arrived_at
                  FROM admissions.attachment WHERE session = :s ORDER BY kind, source_name
                """).param("s", s).query((rs, i) -> new Attachment(UUID.fromString(rs.getString("id")), rs.getString("kind"),
                        rs.getString("source_name"), rs.getString("jamb_key"), rs.getString("read_as"), rs.getBoolean("matched"),
                        Json.map(rs.getString("payload_text")), (Long) rs.getObject("bytes"), (Integer) rs.getObject("width_px"),
                        (Integer) rs.getObject("height_px"), rs.getObject("arrived_at", java.time.OffsetDateTime.class))).list();
        List<Candidate> candidates = jdbc.sql("""
                SELECT c.id, c.jamb_key, c.surname, c.other_names, c.programme, c.entry_mode,
                       EXISTS (SELECT 1 FROM admissions.attachment a WHERE a.candidate_id = c.id AND a.kind = 'PASSPORT') AS has_passport,
                       EXISTS (SELECT 1 FROM admissions.attachment a WHERE a.candidate_id = c.id AND a.kind = 'DATE_OF_BIRTH') AS has_dob,
                       EXISTS (SELECT 1 FROM admissions.attachment a WHERE a.candidate_id = c.id AND a.kind = 'OLEVEL') AS has_olevel
                  FROM admissions.candidate c WHERE c.session = :s ORDER BY c.surname, c.other_names
                """).param("s", s).query(Candidate.class).list();
        return new State(s, intake.attachmentState(s), attachments, candidates);
    }

    /** Records what was read, as it was read, then re-matches everything held. */
    @PostMapping
    @PreAuthorize(WRITERS)
    @Transactional
    Map<String, Object> record(@PathVariable String session, @PathVariable String year, @Valid @RequestBody Batch batch) {
        String s = session + "/" + year;
        if (!List.of("PASSPORT", "DATE_OF_BIRTH", "OLEVEL").contains(batch.kind())) {
            throw new DomainRuleViolation("ATT_KIND", "'" + batch.kind() + "' is not one of the three downloads.",
                    new DomainRuleViolation.Remedy("PASSPORT, DATE_OF_BIRTH or OLEVEL.", "Directorate of ICT"));
        }
        int recorded = 0;
        for (Item it : batch.items()) {
            String key = it.jambKey() == null || it.jambKey().isBlank() ? null : it.jambKey().trim().toUpperCase();
            String readAs = key == null ? "UNREADABLE" : it.readAs();
            long already = jdbc.sql("SELECT count(*) FROM admissions.attachment WHERE session = :s AND kind = :k AND source_name = :n")
                    .param("s", s).param("k", batch.kind()).param("n", it.sourceName()).query(Long.class).single();
            if (already > 0) {
                continue;
            }
            UUID id = UUID.randomUUID();
            jdbc.sql("""
                    INSERT INTO admissions.attachment (id, session, kind, source_name, jamb_key, read_as, payload, bytes, width_px, height_px)
                    VALUES (:id, :s, :k, :n, :key, :r, CAST(:p AS jsonb), :b, :w, :h)
                    """).param("id", id).param("s", s).param("k", batch.kind()).param("n", it.sourceName()).param("key", key, Types.VARCHAR)
                    .param("r", readAs).param("p", Json.text(it.payload())).param("b", it.bytes(), Types.BIGINT)
                    .param("w", it.widthPx(), Types.INTEGER).param("h", it.heightPx(), Types.INTEGER).update();
            if ("OLEVEL".equals(batch.kind())) {
                /* the sittings, read out of what arrived (V020) */
                jdbc.sql("SELECT admissions.olevel_from_attachment(:id)").param("id", id).query(Integer.class).single();
            }
            recorded++;
        }
        List<Map<String, Object>> attached = new ArrayList<>(jdbc.sql("SELECT kind, newly_attached FROM admissions.attach_pending(:s)")
                .param("s", s).query().listOfRows());
        return Map.of("recorded", recorded, "attached", attached, "findings", intake.attachmentState(s));
    }

    /** the little JSON the payload needs, without another dependency on the mapper's configuration */
    static final class Json {
        private static final tools.jackson.databind.ObjectMapper MAPPER = new tools.jackson.databind.ObjectMapper();

        static Map<String, Object> map(String text) {
            if (text == null || text.isBlank()) {
                return Map.of();
            }
            return MAPPER.readValue(text, new tools.jackson.core.type.TypeReference<Map<String, Object>>() { });
        }

        static List<Map<String, Object>> list(String text) {
            if (text == null || text.isBlank()) {
                return List.of();
            }
            return MAPPER.readValue(text, new tools.jackson.core.type.TypeReference<List<Map<String, Object>>>() { });
        }

        static String text(Map<String, Object> m) {
            return MAPPER.writeValueAsString(m == null ? Map.of() : m);
        }
    }
}
