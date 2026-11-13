package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.awt.image.BufferedImage;
import java.io.ByteArrayOutputStream;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.util.Base64;
import java.util.List;
import java.util.Map;
import java.util.Random;
import java.util.UUID;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.TimeUnit;

import javax.imageio.ImageIO;
import javax.sql.DataSource;

import ng.edu.moaum.portal.shared.FileStore;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Primary;
import org.springframework.http.HttpMethod;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.transaction.PlatformTransactionManager;

/**
 * V749, the staff photograph with an object store (an in-memory one here; S3 in production): the original and the enhanced copy are
 * kept in the store, the upload naming them, and served back from it. When the database refuses the upload after its files were put
 * in the store — here the hour's twenty reached while the upload was being worked, so the final guard in
 * hrm.add_my_staff_photo_submission refuses it — the files are taken back out: no record and no bytes are left where nothing reaches
 * them. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class StaffPhotoStoreIT {

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

    @TestConfiguration
    static class Store {
        @Bean
        @Primary
        MemoryStore memoryStore() {
            return new MemoryStore();
        }
    }

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;
    @Autowired
    DataSource dataSource;
    @Autowired
    MemoryStore store;

    ItSupport it;

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
    }

    private static byte[] jpeg(long seed) throws Exception {
        Random random = new Random(seed);
        BufferedImage img = new BufferedImage(720, 900, BufferedImage.TYPE_INT_RGB);
        for (int y = 0; y < 900; y++) {
            for (int x = 0; x < 720; x++) {
                int v = Math.min(255, 70 + ((x / 7 + y / 11) % 2 == 0 ? 22 : 0) + random.nextInt(14));
                img.setRGB(x, y, (v << 16) | (v << 8) | v);
            }
        }
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        ImageIO.write(img, "jpg", out);
        return out.toByteArray();
    }

    private long keys(UUID person) {
        return store.objects.keySet().stream().filter(k -> k.startsWith("hrm/staff_photo_submission/" + person + "/")).count();
    }

    private long records(UUID person) {
        return jdbc.sql("SELECT count(*) FROM platform.file_object WHERE owner_table = 'hrm.staff_photo_submission' AND owner_id = :p")
                .param("p", person.toString()).query(Long.class).single();
    }

    @Test
    void anUploadIsKeptInTheStoreAndOneTheDatabaseRefusesIsTakenBackOutOfIt() throws Exception {
        int n = it.freeDraw(100000, 999999, k -> List.of("ZZSPS-" + k, "ZZSPS" + k));
        UUID p = it.person("ZZSPS-" + n, "ZZSPS" + n);
        it.db(() -> jdbc.sql("""
                INSERT INTO iam.office_assignment (id, person_id, office_code, scope_kind, scope_id, instrument, granted_by, valid_from)
                VALUES (gen_random_uuid(), :p, 'lecturer', 'department', 'MTC', 'staff photograph store test', :p, current_date)
                """).param("p", p).update());
        String mine = TestTokens.token(p, List.of("lecturer"));

        // kept in the store: the upload names both objects, and the original comes back from the store byte for byte
        byte[] first = jpeg(n);
        ResponseEntity<Map> up = it.call(mine, HttpMethod.POST, "/api/v1/staff/identity/photo", Map.of("contentType", "image/jpeg", "dataBase64", Base64.getEncoder().encodeToString(first)));
        assertThat(up.getStatusCode().value()).as(String.valueOf(up.getBody())).isEqualTo(200);
        UUID id = UUID.fromString(String.valueOf(up.getBody().get("id")));
        assertThat(jdbc.sql("""
                SELECT (original_content IS NULL AND original_object IS NOT NULL AND enhanced_content IS NULL AND enhanced_object IS NOT NULL)
                  FROM hrm.staff_photo_submission WHERE id = :s
                """).param("s", id).query(Boolean.class).single()).isTrue();
        assertThat(keys(p)).isEqualTo(2L);
        assertThat(records(p)).isEqualTo(2L);
        assertThat(it.getBytes(mine, "/api/v1/staff/identity/photo/" + id + "/original").getBody()).isEqualTo(first);

        // nineteen in the hour: the upload is let through to be worked, and its files are put in the store; the holder's lock is held
        // here until the twentieth is recorded, so the upload's own record meets the final guard and is refused
        long counted = jdbc.sql("SELECT count(*) FROM hrm.staff_photo_event WHERE person_id = :p AND action IN ('UPLOADED', 'RETRIED', 'REFUSED') AND at > now() - interval '1 hour'")
                .param("p", p).query(Long.class).single();
        it.db(() -> jdbc.sql("INSERT INTO hrm.staff_photo_event (person_id, action, by, office) SELECT :p, 'UPLOADED', :p, 'lecturer' FROM generate_series(1, :k)")
                .param("p", p).param("k", (int) (19 - counted)).update());
        long submissions = jdbc.sql("SELECT count(*) FROM hrm.staff_photo_submission WHERE person_id = :p").param("p", p).query(Long.class).single();
        byte[] second = jpeg(n + 1L);
        try (Connection held = dataSource.getConnection()) {
            held.setAutoCommit(false);
            try (PreparedStatement s = held.prepareStatement("""
                    SELECT set_config('moaum.actor_id', ?, true), set_config('moaum.actor_office', 'lecturer', true),
                           set_config('moaum.reason', 'staff photograph store test', true), pg_advisory_xact_lock(hashtext('staff_photo:' || ?))
                    """)) {
                s.setString(1, p.toString());
                s.setString(2, p.toString());
                s.execute();
            }
            CompletableFuture<ResponseEntity<Map>> refused = CompletableFuture.supplyAsync(() -> it.call(mine, HttpMethod.POST, "/api/v1/staff/identity/photo",
                    Map.of("contentType", "image/jpeg", "dataBase64", Base64.getEncoder().encodeToString(second))));
            boolean waiting = false;
            for (int i = 0; i < 600 && !waiting; i++) {
                waiting = jdbc.sql("""
                        SELECT EXISTS (SELECT 1 FROM pg_stat_activity WHERE wait_event_type = 'Lock' AND wait_event = 'advisory'
                                                                     AND query ILIKE '%add_my_staff_photo_submission%')
                        """).query(Boolean.class).single();
                if (!waiting) {
                    Thread.sleep(100);
                }
            }
            assertThat(waiting).as("the upload reached its record, its files stored, and waits for the holder's lock").isTrue();
            assertThat(keys(p)).as("the second upload's files are in the store while it waits").isEqualTo(4L);
            try (PreparedStatement s = held.prepareStatement("INSERT INTO hrm.staff_photo_event (person_id, action, by, office) VALUES (?::uuid, 'UPLOADED', ?::uuid, 'lecturer')")) {
                s.setString(1, p.toString());
                s.setString(2, p.toString());
                s.executeUpdate();
            }
            held.commit();
            ResponseEntity<Map> answer = refused.get(60, TimeUnit.SECONDS);
            assertThat(answer.getStatusCode().value()).isEqualTo(422);
            assertThat(answer.getBody()).containsEntry("code", "PHOTO_UPLOAD_LIMIT");
        }
        // nothing of the refused upload is left: no submission, no file record, no bytes in the store
        assertThat(jdbc.sql("SELECT count(*) FROM hrm.staff_photo_submission WHERE person_id = :p").param("p", p).query(Long.class).single()).isEqualTo(submissions);
        assertThat(records(p)).isEqualTo(2L);
        assertThat(keys(p)).isEqualTo(2L);
    }
}
