package ng.edu.moaum.portal.shared;

import static org.assertj.core.api.Assertions.assertThat;

import java.nio.charset.StandardCharsets;
import java.util.List;
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

    /** an object store in memory: what is put is kept, what is deleted is gone — except a key it is told it cannot delete */
    static final class MemoryStore implements FileStore {
        final Map<String, byte[]> objects = new ConcurrentHashMap<>();
        java.util.function.Predicate<String> undeletable = key -> false;

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
            if (undeletable.test(key)) {
                throw new IllegalStateException("the store refused to delete " + key);
            }
            objects.remove(key);
        }
    }

    /**
     * V749: the columns that hold an object are read from the foreign keys to platform.file_object, not only from the columns named
     * object_id — the staff photograph's uploads (original_object, enhanced_object, previous_photo_object), the logo and the card
     * signatory's signature (whose foreign keys SET NULL: swept, the signature would have gone). An object held only through such a
     * column is never taken. And an object that cannot be removed (here the store refuses) is passed over: a hundred of them, the
     * oldest of all, never keep the sweep from an orphan after them.
     */
    @Test
    void theSweepReadsEveryColumnThatHoldsAnObjectAndAnObjectItCannotRemoveNeverStarvesIt() {
        MemoryStore store = new MemoryStore();
        store.undeletable = key -> key.startsWith("stuck/");
        FileObjects files = new FileObjects(store, jdbc);
        FileMigrationJob job = new FileMigrationJob(jdbc, store, files, lock, transactions, 10);
        TransactionTemplate tx = new TransactionTemplate(transactions);
        String tag = UUID.randomUUID().toString().substring(0, 8).toUpperCase();

        List<String> holders = job.holders().stream()
                .map(h -> h.get("table_schema") + "." + h.get("table_name") + "." + h.get("column_name")).toList();
        assertThat(holders).contains("hrm.staff_photo_submission.original_object", "hrm.staff_photo_submission.enhanced_object",
                "hrm.staff_photo_submission.previous_photo_object", "hrm.staff_photo.object_id", "jupeb.document.object_id",
                "platform.institution_profile.logo_object_id", "credentials.card_signatory.signature_object_id");

        UUID[] ids = AuditContextHolder.with(new AuditContext(NOBODY, "ict", "the orphan sweep test", null, null), () -> tx.execute(st -> {
            UUID person = UUID.randomUUID();
            jdbc.sql("INSERT INTO iam.person (id, staff_number, surname, given_names) VALUES (:p, :n, 'ZZSWEEP', 'Photograph')")
                    .param("p", person).param("n", "ZZSWEEP-" + tag).update();
            UUID held = files.store("hrm.staff_photo_submission", person, "original.jpg", "image/jpeg", ("photograph held " + tag).getBytes(StandardCharsets.UTF_8));
            jdbc.sql("""
                    INSERT INTO hrm.staff_photo_submission (person_id, state, original_type, original_bytes, original_object, error)
                    VALUES (:p, 'FAILED', 'image/jpeg', 20, :o, 'the orphan sweep test')
                    """).param("p", person).param("o", held).update();
            // a hundred the store will not let go, older than anything else
            jdbc.sql("""
                    INSERT INTO platform.file_object (id, object_key, content_type, size_bytes, sha256, owner_table, owner_id, created_at)
                    SELECT gen_random_uuid(), 'stuck/' || :t || '/' || i, 'application/pdf', 1, sha256(convert_to(:t || i, 'UTF8')), 'test.stuck', :t,
                           timestamptz '2000-01-01 00:00:00+00' + i * interval '1 second'
                      FROM generate_series(1, 100) i
                    """).param("t", tag).update();
            UUID orphan = files.store("test.orphan", UUID.randomUUID(), "x.pdf", "application/pdf", ("%PDF orphan " + tag).getBytes(StandardCharsets.UTF_8));
            jdbc.sql("UPDATE platform.file_object SET created_at = now() - interval '2 hours' WHERE id IN (:h, :o)").param("h", held).param("o", orphan).update();
            return new UUID[] {held, orphan};
        }));
        UUID held = ids[0];
        UUID orphan = ids[1];
        String heldKey = jdbc.sql("SELECT object_key FROM platform.file_object WHERE id = :h").param("h", held).query(String.class).single();
        try {
            for (int i = 0; i < 50 && Boolean.TRUE.equals(jdbc.sql("SELECT EXISTS (SELECT 1 FROM platform.file_object WHERE id = :o)").param("o", orphan).query(Boolean.class).single()); i++) {
                job.forgetOrphans();
            }
            assertThat(jdbc.sql("SELECT count(*) FROM platform.file_object WHERE id = :o").param("o", orphan).query(Integer.class).single())
                    .as("the orphan after a hundred the sweep cannot remove").isZero();
            assertThat(jdbc.sql("SELECT count(*) FROM platform.file_object WHERE owner_table = 'test.stuck' AND owner_id = :t").param("t", tag).query(Integer.class).single())
                    .as("the hundred the store refused stay recorded").isEqualTo(100);
            assertThat(jdbc.sql("SELECT count(*) FROM platform.file_object WHERE id = :h").param("h", held).query(Integer.class).single()).isEqualTo(1);
            assertThat(store.objects).containsKey(heldKey);
        } finally {
            AuditContextHolder.with(new AuditContext(NOBODY, "ict", "the orphan sweep test cleared", null, null), () -> tx.execute(st ->
                    jdbc.sql("DELETE FROM platform.file_object WHERE owner_table = 'test.stuck' AND owner_id = :t").param("t", tag).update()));
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
