package ng.edu.moaum.portal.admissions;

import java.sql.Types;
import java.time.LocalDate;
import java.util.Collection;
import java.util.HexFormat;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;
import java.util.stream.Collectors;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;

@Repository
class CapsRepository {

    private static final String BATCH_COLUMNS = """
            id, session, source, filename, encode(file_sha256, 'hex') AS file_sha256, rows_read, list_kind,
            downloaded_on, uploaded_at, uploaded_by, uploaded_office, committed_at
            """;

    private final JdbcClient jdbc;

    CapsRepository(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    Optional<CapsBatch> find(UUID id) {
        return jdbc.sql("SELECT " + BATCH_COLUMNS + " FROM admissions.caps_batch WHERE id = :id")
                .param("id", id)
                .query(CapsBatch.class)
                .optional();
    }

    List<CapsBatch> bySession(String session) {
        return jdbc.sql("SELECT " + BATCH_COLUMNS + " FROM admissions.caps_batch WHERE session = :session ORDER BY uploaded_at DESC")
                .param("session", session)
                .query(CapsBatch.class)
                .list();
    }

    void insertBatch(UUID id, String session, String source, String filename, String fileSha256, int rowsRead,
                     String listKind, LocalDate downloadedOn, UUID uploadedBy, String uploadedOffice) {
        jdbc.sql("""
                INSERT INTO admissions.caps_batch
                       (id, session, source, filename, file_sha256, rows_read, list_kind, downloaded_on, uploaded_by, uploaded_office)
                VALUES (:id, :session, :source, :filename, :sha, :rows, :kind, :downloaded, :by, :office)
                """)
                .param("id", id)
                .param("session", session)
                .param("source", source)
                .param("filename", filename, Types.VARCHAR)
                .param("sha", HexFormat.of().parseHex(fileSha256.toLowerCase()))
                .param("rows", rowsRead)
                .param("kind", listKind)
                .param("downloaded", downloadedOn)
                .param("by", uploadedBy)
                .param("office", uploadedOffice)
                .update();
    }

    void insertRow(UUID batchId, String session, CapsRowIn row, String rawJson) {
        jdbc.sql("""
                INSERT INTO admissions.caps_row
                       (id, batch_id, session, jamb_reg_no, raw, surname, other_names, jamb_code, aggregate,
                        sex, state_of_origin, lga, entry_mode)
                VALUES (:id, :batch, :session, :reg, CAST(:raw AS jsonb), :surname, :others, :code, :aggregate,
                        :sex, :state, :lga, :mode)
                """)
                .param("id", UUID.randomUUID())
                .param("batch", batchId)
                .param("session", session)
                .param("reg", row.jambRegNo().trim().toUpperCase())
                .param("raw", rawJson)
                .param("surname", row.surname().trim())
                .param("others", row.otherNames() == null ? "" : row.otherNames().trim())
                .param("code", row.jambCode().trim().toUpperCase())
                .param("aggregate", row.aggregate(), Types.INTEGER)
                .param("sex", row.sex(), Types.VARCHAR)
                .param("state", row.stateOfOrigin(), Types.VARCHAR)
                .param("lga", row.lga(), Types.VARCHAR)
                .param("mode", row.entryMode())
                .update();
    }

    void insertExcluded(UUID batchId, String session, CapsRowIn row, int cutoff, String reason, String rawJson) {
        jdbc.sql("""
                INSERT INTO admissions.caps_row_excluded
                       (id, batch_id, session, jamb_reg_no, jamb_code, surname, other_names, aggregate, cutoff, reason, raw)
                VALUES (:id, :batch, :session, :reg, :code, :surname, :others, :aggregate, :cutoff, :reason, CAST(:raw AS jsonb))
                """)
                .param("id", UUID.randomUUID())
                .param("batch", batchId)
                .param("session", session)
                .param("reg", row.jambRegNo().trim().toUpperCase())
                .param("code", row.jambCode().trim().toUpperCase())
                .param("surname", row.surname().trim())
                .param("others", row.otherNames() == null ? "" : row.otherNames().trim())
                .param("aggregate", row.aggregate(), Types.INTEGER)
                .param("cutoff", cutoff)
                .param("reason", reason)
                .param("raw", rawJson)
                .update();
    }

    /* ── the session's admission settings ───────────────────────────── */

    Optional<AdmissionPolicy.Row> policy(String session) {
        return jdbc.sql("""
                SELECT session, state, instrument, nuc_quota, weight_utme, weight_putme, ratio_utme, ratio_de
                  FROM admissions.session_policy WHERE session = :session
                """)
                .param("session", session)
                .query(AdmissionPolicy.Row.class)
                .optional();
    }

    boolean policyInForce(String session) {
        return jdbc.sql("SELECT count(*) FROM admissions.session_policy WHERE session = :session AND state = 'IN_FORCE'")
                .param("session", session)
                .query(Long.class)
                .single() > 0;
    }

    List<AdmissionPolicy.FacultyCutoff> facultyCutoffs(String session) {
        return jdbc.sql("""
                SELECT f.faculty_code, fa.name AS faculty_name, f.quota, f.cutoff
                  FROM admissions.faculty_quota f
                  JOIN admissions.session_policy p ON p.id = f.policy_id
                  JOIN ref.faculty fa ON fa.code = f.faculty_code
                 WHERE p.session = :session
                 ORDER BY f.faculty_code
                """)
                .param("session", session)
                .query(AdmissionPolicy.FacultyCutoff.class)
                .list();
    }

    List<AdmissionPolicy.ProgrammeCutoff> programmeCutoffs(String session) {
        return jdbc.sql("""
                SELECT r.programme_code AS code, g.name, r.cutoff
                  FROM admissions.programme_rule r
                  JOIN admissions.session_policy p ON p.id = r.policy_id
                  JOIN ref.programme g ON g.code = r.programme_code
                 WHERE p.session = :session AND r.cutoff IS NOT NULL
                 ORDER BY r.programme_code
                """)
                .param("session", session)
                .query(AdmissionPolicy.ProgrammeCutoff.class)
                .list();
    }

    /**
     * The cut-off that applies to each programme — the database's own answer
     * ({@code admissions.cutoff_for}): the programme's, else its faculty's,
     * and an error if neither is set or no settings are in force.
     */
    Map<String, Integer> cutoffsFor(String session, Collection<String> codes) {
        if (codes.isEmpty()) {
            return Map.of();
        }
        return jdbc.sql("SELECT code, admissions.cutoff_for(:session, code) AS cutoff FROM ref.programme WHERE code IN (:codes)")
                .param("session", session)
                .param("codes", List.copyOf(codes))
                .query((rs, i) -> Map.entry(rs.getString("code"), rs.getInt("cutoff")))
                .list()
                .stream()
                .collect(Collectors.toMap(Map.Entry::getKey, Map.Entry::getValue));
    }

    String commit(UUID batchId) {
        return jdbc.sql("SELECT admissions.commit_batch(:id)").param("id", batchId).query(String.class).single();
    }

    List<Finding> reconcile(String session) {
        return jdbc.sql("SELECT finding, n, owner, what_it_means FROM admissions.reconcile(:session)")
                .param("session", session)
                .query(Finding.class)
                .list();
    }

    List<Finding> attachmentState(String session) {
        return jdbc.sql("SELECT finding, n, owner, what_it_means FROM admissions.attachment_state(:session)")
                .param("session", session)
                .query(Finding.class)
                .list();
    }

    List<PolicyFinding> policyFindings(String session) {
        return jdbc.sql("SELECT finding, detail, owner FROM admissions.policy_findings(:session)")
                .param("session", session)
                .query(PolicyFinding.class)
                .list();
    }

    List<Programme> programmes() {
        return jdbc.sql("""
                SELECT p.code, p.name, p.dept_code, p.faculty_code, f.name AS faculty_name,
                       a.jamb_name, p.category, p.archived
                  FROM ref.programme p
                  JOIN ref.faculty f ON f.code = p.faculty_code
                  LEFT JOIN ref.jamb_alias a ON a.code = p.code
                 ORDER BY p.code
                """)
                .query(Programme.class)
                .list();
    }

    /** The code, if any, whose JAMB alias normalises to the same letters and digits. */
    Optional<String> codeWithAlias(String normalisedName) {
        return jdbc.sql("""
                SELECT code FROM ref.jamb_alias
                 WHERE lower(regexp_replace(jamb_name, '[^A-Za-z0-9]', '', 'g')) = :name
                """)
                .param("name", normalisedName)
                .query(String.class)
                .optional();
    }

    void upsertAlias(String code, String jambName) {
        jdbc.sql("""
                INSERT INTO ref.jamb_alias (code, jamb_name) VALUES (:code, :name)
                ON CONFLICT (code) DO UPDATE SET jamb_name = EXCLUDED.jamb_name
                """)
                .param("code", code)
                .param("name", jambName)
                .update();
    }

    Optional<Programme> programme(String code) {
        return programmes().stream().filter(p -> p.code().equals(code)).findFirst();
    }

    Optional<String> regNoIn(String text) {
        return jdbc.sql("SELECT admissions.reg_no_in(:text)").param("text", text).query(String.class).optional();
    }
}
