package ng.edu.moaum.portal.admissions;

import java.sql.Types;
import java.time.LocalDate;
import java.util.HexFormat;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

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

    Optional<String> regNoIn(String text) {
        return jdbc.sql("SELECT admissions.reg_no_in(:text)").param("text", text).query(String.class).optional();
    }
}
