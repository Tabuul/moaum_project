package ng.edu.moaum.portal.shared;

import java.util.Arrays;
import java.util.Base64;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;

/**
 * Moves the files already in the database to the object store, a few hundred rows every half minute,
 * table by table, while the portal runs. Each row: the bytes go to the store, are read back and
 * their SHA-256 compared, the object is recorded, and only then are the database bytes cleared —
 * one row, one transaction, so a failure leaves nothing half done and the next pass resumes. Runs
 * only with MOAUM_FILES_PROVIDER=S3 and MOAUM_FILES_MIGRATE=true, on one instance at a time; switch
 * MIGRATE off when every table reports nothing left.
 */
@Component
@ConditionalOnProperty(name = "moaum.files.migrate", havingValue = "true")
public class FileMigrationJob {

    private static final Logger LOG = LoggerFactory.getLogger(FileMigrationJob.class);
    private static final UUID NOBODY = UUID.fromString("00000000-0000-0000-0000-000000000000");

    /** blob table, its key column, its bytes column, and where its type and name are kept */
    record Spec(String table, String key, String bytes, String parent, String parentKey, String type, String name) {
    }

    static final List<Spec> SPECS = List.of(
            new Spec("admissions.application_document_blob", "document_id", "content", "admissions.application_document", "id", "content_type", "filename"),
            new Spec("admissions.pg_document", "id", "bytes", null, null, "content_type", "filename"),
            new Spec("admissions.pg_research_document_blob", "document_id", "bytes", "admissions.pg_research_document", "id", "content_type", "filename"),
            new Spec("lms.material_blob", "material_id", "content", "lms.material", "id", "content_type", "filename"),
            new Spec("lms.submission_blob", "submission_id", "content", "lms.submission", "id", "content_type", "filename"),
            new Spec("platform.request_document_blob", "document_id", "content", "platform.request_document", "id", "content_type", "filename"),
            new Spec("helpdesk.ticket_attachment_blob", "attachment_id", "content", "helpdesk.ticket_attachment", "id", "content_type", "filename"),
            new Spec("people.deferment_document_blob", "document_id", "bytes", "people.deferment_document", "id", "content_type", "filename"),
            new Spec("hrm.staff_photo", "person_id", "content", null, null, "content_type", null),
            new Spec("extexam.examiner_file_blob", "file_id", "content", "extexam.examiner_file", "id", "content_type", "filename"),
            new Spec("extexam.project_document_blob", "document_id", "content", "extexam.project_document", "id", "content_type", "filename"));

    private final JdbcClient jdbc;
    private final FileStore store;
    private final FileObjects files;
    private final JobLock lock;
    private final TransactionTemplate tx;
    private final int batch;

    FileMigrationJob(JdbcClient jdbc, FileStore store, FileObjects files, JobLock lock, PlatformTransactionManager transactions,
                     @Value("${moaum.files.migrate-batch:200}") int batch) {
        this.jdbc = jdbc;
        this.store = store;
        this.files = files;
        this.lock = lock;
        this.tx = new TransactionTemplate(transactions);
        this.batch = batch;
    }

    @Scheduled(fixedDelayString = "${moaum.files.migrate-every-ms:30000}", initialDelay = 60000)
    public void sweep() {
        if (!store.enabled()) {
            return;
        }
        lock.runExclusively("file-migration", this::sweepNow);
    }

    void sweepNow() {
        int left = batch;
        for (Spec s : SPECS) {
            if (left <= 0) break;
            left -= migrate(s, left);
        }
        if (left > 0) {
            left -= migratePassports(left);
        }
        if (left == batch) {
            LOG.info("files: nothing left to move to the object store");
        }
        forgetOrphans();
    }

    /**
     * an object no row points at any more (a photograph replaced by another, a document deleted) is removed;
     * an hour's grace keeps an upload in progress out of reach. Whether a row points at it is asked of every table that keeps
     * an object id (each uuid column named object_id, as the database lists them now), never of a list kept by hand: V348
     * found that the JUPEB documents, added after the list was written, had every object swept away an hour after upload.
     */
    void forgetOrphans() {
        List<Map<String, Object>> holders = jdbc.sql("""
                SELECT c.table_schema, c.table_name FROM information_schema.columns c JOIN information_schema.tables t
                    ON t.table_schema = c.table_schema AND t.table_name = c.table_name AND t.table_type = 'BASE TABLE'
                 WHERE c.column_name = 'object_id' AND c.data_type = 'uuid' AND c.table_schema NOT IN ('pg_catalog', 'information_schema')
                   AND NOT (c.table_schema = 'platform' AND c.table_name = 'file_object')
                 ORDER BY 1, 2
                """).query().listOfRows();
        if (holders.isEmpty()) {
            LOG.warn("files: no table holding object ids was found; nothing is removed");
            return;
        }
        StringBuilder none = new StringBuilder();
        for (Map<String, Object> h : holders) {
            none.append(" AND NOT EXISTS (SELECT 1 FROM ").append(quoted(h.get("table_schema"))).append('.').append(quoted(h.get("table_name")))
                    .append(" t WHERE t.object_id = f.id)");
        }
        List<UUID> orphans = jdbc.sql("SELECT f.id FROM platform.file_object f WHERE f.created_at < now() - interval '1 hour'" + none + " LIMIT 100")
                .query(UUID.class).list();
        int n = 0;
        for (UUID id : orphans) {
            try {
                Boolean gone = AuditContextHolder.with(new AuditContext(NOBODY, "ict", "orphaned file object removed", null, null), () -> tx.execute(st -> {
                    files.forget(id);
                    return true;
                }));
                if (Boolean.TRUE.equals(gone)) n++;
            } catch (RuntimeException e) {
                LOG.warn("files: orphan {} not removed: {}", id, e.getMessage());
            }
        }
        if (n > 0) LOG.info("files: {} orphaned objects removed from the object store", n);
    }

    private int migrate(Spec s, int limit) {
        String typeExpr = s.parent == null ? "b." + s.type : "p." + s.type;
        String nameExpr = s.name == null ? "NULL" : (s.parent == null ? "b." + s.name : "p." + s.name);
        String join = s.parent == null ? "" : " JOIN " + s.parent + " p ON p." + s.parentKey + " = b." + s.key;
        List<Map<String, Object>> rows = jdbc.sql("SELECT b." + s.key + " AS k, " + typeExpr + " AS t, " + nameExpr + " AS n FROM " + s.table + " b" + join
                        + " WHERE b.object_id IS NULL AND b." + s.bytes + " IS NOT NULL LIMIT :n")
                .param("n", limit).query().listOfRows();
        int done = 0;
        for (Map<String, Object> r : rows) {
            Object k = r.get("k");
            String type = r.get("t") == null ? "application/octet-stream" : String.valueOf(r.get("t"));
            String name = r.get("n") == null ? null : String.valueOf(r.get("n"));
            try {
                Boolean moved = AuditContextHolder.with(new AuditContext(NOBODY, "ict", "files moved to the object store", null, null), () -> tx.execute(st -> {
                    Map<String, Object> row = jdbc.sql("SELECT " + s.bytes + " AS c FROM " + s.table + " WHERE " + s.key + " = :k AND object_id IS NULL FOR UPDATE SKIP LOCKED")
                            .param("k", k).query().listOfRows().stream().findFirst().orElse(null);
                    if (row == null || row.get("c") == null) return false;
                    byte[] bytes = (byte[]) row.get("c");
                    UUID oid = files.store(s.table, k, name, type, bytes);
                    verify(oid, bytes);
                    jdbc.sql("UPDATE " + s.table + " SET object_id = :o, " + s.bytes + " = NULL WHERE " + s.key + " = :k").param("o", oid).param("k", k).update();
                    return true;
                }));
                if (Boolean.TRUE.equals(moved)) done++;
            } catch (RuntimeException e) {
                LOG.warn("files: {} {} not moved: {}", s.table, k, e.getMessage());
            }
        }
        if (done > 0) LOG.info("files: {} rows of {} moved to the object store", done, s.table);
        return done;
    }

    /** JAMB passports: a base64 data URL inside admissions.attachment.payload becomes an object; the payload keeps the rest */
    private int migratePassports(int limit) {
        List<Map<String, Object>> rows = jdbc.sql("""
                SELECT id FROM admissions.attachment WHERE kind = 'PASSPORT' AND object_id IS NULL AND jsonb_exists(payload, 'dataUrl') LIMIT :n
                """).param("n", limit).query().listOfRows();
        int done = 0;
        for (Map<String, Object> r : rows) {
            UUID id = (UUID) r.get("id");
            try {
                Boolean moved = AuditContextHolder.with(new AuditContext(NOBODY, "ict", "files moved to the object store", null, null), () -> tx.execute(st -> {
                    Map<String, Object> row = jdbc.sql("SELECT payload ->> 'dataUrl' AS u, source_name FROM admissions.attachment WHERE id = :id AND object_id IS NULL FOR UPDATE SKIP LOCKED")
                            .param("id", id).query().listOfRows().stream().findFirst().orElse(null);
                    if (row == null || row.get("u") == null) return false;
                    String u = String.valueOf(row.get("u"));
                    int comma = u.indexOf(',');
                    String meta = comma > 0 ? u.substring(u.startsWith("data:") ? 5 : 0, comma) : "image/jpeg;base64";
                    String type = meta.contains(";") ? meta.substring(0, meta.indexOf(';')) : meta;
                    if (type.isBlank()) type = "image/jpeg";
                    byte[] bytes = Base64.getDecoder().decode((comma > 0 ? u.substring(comma + 1) : u).replaceAll("\\s", ""));
                    UUID oid = files.store("admissions.attachment", id, String.valueOf(row.get("source_name")), type, bytes);
                    verify(oid, bytes);
                    jdbc.sql("UPDATE admissions.attachment SET object_id = :o, object_key = (SELECT object_key FROM platform.file_object WHERE id = :o), payload = payload - 'dataUrl' WHERE id = :id")
                            .param("o", oid).param("id", id).update();
                    return true;
                }));
                if (Boolean.TRUE.equals(moved)) done++;
            } catch (RuntimeException e) {
                LOG.warn("files: passport attachment {} not moved: {}", id, e.getMessage());
            }
        }
        if (done > 0) LOG.info("files: {} passport photographs moved to the object store", done);
        return done;
    }

    /** a schema or table name from the catalogue, quoted as an identifier */
    private static String quoted(Object name) {
        return "\"" + String.valueOf(name).replace("\"", "\"\"") + "\"";
    }

    /** read it back: what the store holds is what the database held, byte for byte */
    private void verify(UUID objectId, byte[] original) {
        byte[] back = files.load(objectId);
        if (!Arrays.equals(FileObjects.sha256(back), FileObjects.sha256(original))) {
            throw new IllegalStateException("object " + objectId + " read back with a different SHA-256");
        }
    }
}
