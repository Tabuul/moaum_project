package ng.edu.moaum.portal.shared;

import static org.assertj.core.api.Assertions.assertThat;

import java.nio.charset.StandardCharsets;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;

/**
 * V348: the object store's orphan sweep removes an object no row points at, and never one a row still shows — here a JUPEB
 * document, the table the hand-kept list of V310 missed (every JUPEB document and passport was swept away an hour after it
 * was uploaded). The store is an in-memory one; the rows are the database's. Needs DATABASE_URL.
 */
@SpringBootTest(properties = "moaum.auth.hmac-secret=test-only-secret-of-at-least-thirty-two-bytes")
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
class FileSweepIT {

    private static final UUID NOBODY = UUID.fromString("00000000-0000-0000-0000-000000000000");

    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;
    @Autowired
    JobLock lock;

    /** an object store in memory: what is put is kept, what is deleted is gone */
    static final class MemoryStore implements FileStore {
        final Map<String, byte[]> objects = new ConcurrentHashMap<>();

        @Override
        public boolean enabled() {
            return true;
        }

        @Override
        public void put(String key, byte[] bytes, String contentType) {
            objects.put(key, bytes);
        }

        @Override
        public byte[] get(String key) {
            return objects.get(key);
        }

        @Override
        public void delete(String key) {
            objects.remove(key);
        }
    }

    @Test
    void theSweepKeepsAnObjectAJupebDocumentStillShowsAndRemovesOneNobodyHolds() {
        MemoryStore store = new MemoryStore();
        FileObjects files = new FileObjects(store, jdbc);
        FileMigrationJob job = new FileMigrationJob(jdbc, store, files, lock, transactions, 10);
        TransactionTemplate tx = new TransactionTemplate(transactions);
        String tag = UUID.randomUUID().toString().substring(0, 8).toUpperCase();

        UUID[] ids = AuditContextHolder.with(new AuditContext(NOBODY, "jupeb", "the orphan sweep test", null, null), () -> tx.execute(st -> {
            jdbc.sql("SELECT set_config('moaum.jupeb_quiet', 'on', true)").query().listOfRows();
            jdbc.sql("""
                    SELECT jupeb.import_old_portal_students(jsonb_build_array(jsonb_build_object('row', 2, 'appNo', :n, 'firstName', 'Sweep', 'surname', 'Check',
                           'sex', 'Female', 'phone', '08011112222', 'dob', '1/2/2005', 'email', lower(:n) || '@example.com',
                           'passwordHash', '$2a$12$abcdefghijklmnopqrstuuabcdefghijklmnopqrstuvwxyz12345')),
                           jupeb.current_session(), true, true, 'sweep.xlsx', :by)::text
                    """).param("n", "ZZSWEEP" + tag).param("by", NOBODY).query(String.class).single();
            UUID app = jdbc.sql("SELECT id FROM jupeb.application WHERE application_no = :n").param("n", "ZZSWEEP" + tag).query(UUID.class).single();
            UUID held = files.store("jupeb.document", app, "nin.pdf", "application/pdf", ("%PDF held " + tag).getBytes(StandardCharsets.UTF_8));
            jdbc.sql("INSERT INTO jupeb.document (application_id, kind, filename, content_type, size_bytes, object_id) VALUES (:a, 'NIN', 'nin.pdf', 'application/pdf', 20, :o)")
                    .param("a", app).param("o", held).update();
            UUID orphan = files.store("test.orphan", UUID.randomUUID(), "x.pdf", "application/pdf", ("%PDF orphan " + tag).getBytes(StandardCharsets.UTF_8));
            // older than the hour's grace the sweep gives an upload in progress
            jdbc.sql("UPDATE platform.file_object SET created_at = now() - interval '2 hours' WHERE id IN (:h, :o)").param("h", held).param("o", orphan).update();
            return new UUID[] {held, orphan};
        }));
        UUID held = ids[0];
        UUID orphan = ids[1];
        String heldKey = jdbc.sql("SELECT object_key FROM platform.file_object WHERE id = :h").param("h", held).query(String.class).single();

        // other tests may leave older orphans; the sweep takes a hundred at a time
        for (int i = 0; i < 50 && Boolean.TRUE.equals(jdbc.sql("SELECT EXISTS (SELECT 1 FROM platform.file_object WHERE id = :o)").param("o", orphan).query(Boolean.class).single()); i++) {
            job.forgetOrphans();
        }

        assertThat(jdbc.sql("SELECT count(*) FROM platform.file_object WHERE id = :o").param("o", orphan).query(Integer.class).single()).isZero();
        assertThat(jdbc.sql("SELECT count(*) FROM platform.file_object WHERE id = :h").param("h", held).query(Integer.class).single()).isEqualTo(1);
        assertThat(store.objects).containsKey(heldKey);
        assertThat(files.load(held)).isEqualTo(("%PDF held " + tag).getBytes(StandardCharsets.UTF_8));
    }
}
