package ng.edu.moaum.portal;

import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.function.Supplier;

import ng.edu.moaum.portal.shared.AuditContext;
import ng.edu.moaum.portal.shared.AuditContextHolder;

import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpMethod;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;
import org.springframework.web.client.RestClient;

/** What every journey test does: talk to the API as an office, and write the rows the API has no door for yet. */
final class ItSupport {

    private final RestClient client;
    private final JdbcClient jdbc;
    private final PlatformTransactionManager transactions;

    ItSupport(int port, JdbcClient jdbc, PlatformTransactionManager transactions) {
        this.client = RestClient.builder()
                .baseUrl("http://localhost:" + port)
                .defaultStatusHandler(status -> true, (request, response) -> { })
                .build();
        this.jdbc = jdbc;
        this.transactions = transactions;
    }

    static String token(String office) {
        return TestTokens.token(UUID.randomUUID(), List.of(office));
    }

    /** a call with no token at all: the public doors (apply, sign-in, status) */
    @SuppressWarnings("rawtypes")
    ResponseEntity<Map> anon(HttpMethod method, String path, Object body) {
        RestClient.RequestBodySpec spec = client.method(method).uri(path).contentType(MediaType.APPLICATION_JSON);
        return (body == null ? spec : spec.body(body)).retrieve().toEntity(Map.class);
    }

    @SuppressWarnings("rawtypes")
    ResponseEntity<Map> call(String token, HttpMethod method, String path, Object body) {
        RestClient.RequestBodySpec spec = client.method(method).uri(path)
                .header(HttpHeaders.AUTHORIZATION, "Bearer " + token)
                .header("X-Reason", "integration test")
                .contentType(MediaType.APPLICATION_JSON);
        return (body == null ? spec : spec.body(body)).retrieve().toEntity(Map.class);
    }

    @SuppressWarnings("rawtypes")
    ResponseEntity<Map> get(String token, String path) {
        return client.get().uri(path).header(HttpHeaders.AUTHORIZATION, "Bearer " + token).retrieve().toEntity(Map.class);
    }

    /** a read of bytes (a PDF, an image): the status and the body as they came */
    ResponseEntity<byte[]> getBytes(String token, String path) {
        return client.get().uri(path).header(HttpHeaders.AUTHORIZATION, "Bearer " + token).retrieve().toEntity(byte[].class);
    }

    @SuppressWarnings("rawtypes")
    ResponseEntity<List> callList(String token, HttpMethod method, String path, Object body) {
        RestClient.RequestBodySpec spec = client.method(method).uri(path)
                .header(HttpHeaders.AUTHORIZATION, "Bearer " + token)
                .header("X-Reason", "integration test")
                .contentType(MediaType.APPLICATION_JSON);
        return (body == null ? spec : spec.body(body)).retrieve().toEntity(List.class);
    }

    @SuppressWarnings("rawtypes")
    ResponseEntity<List> getList(String token, String path) {
        return client.get().uri(path).header(HttpHeaders.AUTHORIZATION, "Bearer " + token).retrieve().toEntity(List.class);
    }

    /** an attributed write straight into the database, as the ICT office */
    <T> T db(Supplier<T> work) {
        TransactionTemplate tx = new TransactionTemplate(transactions);
        AuditContext context = new AuditContext(UUID.randomUUID(), "ict", "integration test set-up", null, null);
        return AuditContextHolder.with(context, () -> tx.execute(status -> work.get()));
    }

    JdbcClient jdbc() {
        return jdbc;
    }

    /** a far-future session for the test's own use, non-overlapping with every other test's */
    void session(String name, int startYear) {
        db(() -> jdbc.sql("""
                INSERT INTO policy.academic_session (id, name, starts_on, ends_on)
                VALUES (gen_random_uuid(), :n, make_date(:y, 10, 1), make_date(:y + 1, 8, 31))
                ON CONFLICT (name) DO NOTHING
                """).param("n", name).param("y", startYear).update());
    }

    /** an invented student, ACTIVE with a matriculation number when one is given, ADMITTED otherwise */
    UUID student(String surname, String programme, String admissionNo, String matricNo, int level) {
        return db(() -> {
            UUID existing = jdbc.sql("SELECT id FROM people.student WHERE surname = :s AND other_names = 'Invented'")
                    .param("s", surname).query(UUID.class).optional().orElse(null);
            if (existing != null) {
                return existing;
            }
            UUID id = UUID.randomUUID();
            jdbc.sql("""
                    INSERT INTO people.student (id, admission_no, matric_no, surname, other_names, programme_code, entry_mode,
                                                entry_session, entry_level, current_level, status, matriculated_at)
                    VALUES (:id, :adm, :mat, :s, 'Invented', :p, 'UTME', '2020/2021', 100, :l,
                            CASE WHEN :mat::text IS NULL THEN 'ADMITTED' ELSE 'ACTIVE' END,
                            CASE WHEN :mat::text IS NULL THEN NULL ELSE now() END)
                    """).param("id", id).param("adm", admissionNo).param("mat", matricNo).param("s", surname)
                    .param("p", programme).param("l", level).update();
            return id;
        });
    }

    UUID person(String staffNumber, String surname) {
        return db(() -> {
            UUID existing = jdbc.sql("SELECT id FROM iam.person WHERE staff_number = :n").param("n", staffNumber)
                    .query(UUID.class).optional().orElse(null);
            if (existing != null) {
                return existing;
            }
            UUID id = UUID.randomUUID();
            jdbc.sql("INSERT INTO iam.person (id, staff_number, surname, given_names) VALUES (:id, :n, :s, 'Invented')")
                    .param("id", id).param("n", staffNumber).param("s", surname).update();
            return id;
        });
    }
}
