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

    /** V374: a question approved by a moderator who did not set it — the Super Administrator under a fresh token, so another person */
    @SuppressWarnings("rawtypes")
    void approve(UUID question) {
        ResponseEntity<Map> r = call(token("super"), HttpMethod.POST, "/api/v1/cbt/questions/" + question + "/moderation", Map.of("decision", "APPROVE"));
        if (r.getStatusCode().value() != 200) throw new IllegalStateException("approving " + question + ": " + r.getBody());
    }

    /** V376: a GET whose answer is bytes (an image), with the headers given */
    ResponseEntity<byte[]> getBytesWith(String token, String path, Map<String, String> headers) {
        RestClient.RequestHeadersSpec<?> spec = client.get().uri(path).header(HttpHeaders.AUTHORIZATION, "Bearer " + token);
        for (Map.Entry<String, String> h : headers.entrySet()) spec = spec.header(h.getKey(), h.getValue());
        return spec.retrieve().toEntity(byte[].class);
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

    /** a GET whose path variables and query values the builder encodes (V332: course codes and titles carry spaces) */
    @SuppressWarnings("rawtypes")
    ResponseEntity<Map> get(String token, java.util.function.Function<org.springframework.web.util.UriBuilder, java.net.URI> uri) {
        return client.get().uri(uri).header(HttpHeaders.AUTHORIZATION, "Bearer " + token).retrieve().toEntity(Map.class);
    }

    /** a call whose path variables and query values the builder encodes */
    @SuppressWarnings("rawtypes")
    ResponseEntity<Map> call(String token, HttpMethod method, java.util.function.Function<org.springframework.web.util.UriBuilder, java.net.URI> uri, Object body) {
        RestClient.RequestBodySpec spec = client.method(method).uri(uri)
                .header(HttpHeaders.AUTHORIZATION, "Bearer " + token)
                .header("X-Reason", "integration test")
                .contentType(MediaType.APPLICATION_JSON);
        return (body == null ? spec : spec.body(body)).retrieve().toEntity(Map.class);
    }

    /** a call with extra headers (V322: the examination screen's attempt token) */
    @SuppressWarnings("rawtypes")
    ResponseEntity<Map> callWith(String token, HttpMethod method, String path, Object body, Map<String, String> headers) {
        RestClient.RequestBodySpec spec = client.method(method).uri(path)
                .header(HttpHeaders.AUTHORIZATION, "Bearer " + token)
                .header("X-Reason", "integration test")
                .contentType(MediaType.APPLICATION_JSON);
        for (Map.Entry<String, String> h : headers.entrySet()) {
            spec = spec.header(h.getKey(), h.getValue());
        }
        return (body == null ? spec : spec.body(body)).retrieve().toEntity(Map.class);
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

    /**
     * Oct 2026: a year from min (inclusive) to bound (exclusive) whose session no test has opened — and, for a test that opens more
     * than one, the sessions `before` years before it and `after` years after it too. Tests drew their sessions at random from
     * shared ranges (eight of them from 2300–2899), and a session another test opened first carries that test's fees, rules and
     * windows: two CI runs went red on it in two days (AllocationImportIT, FlexibleRegistrationIT). Drawn at random, then stepped
     * on; a range used up on a database that has run the suite many times gives the random draw, as before.
     */
    int freeYear(int min, int bound) {
        return freeYear(min, bound, 0, 0);
    }

    int freeYear(int min, int bound, int before, int after) {
        int size = bound - min;
        int start = min + java.util.concurrent.ThreadLocalRandom.current().nextInt(size);
        for (int i = 0; i < size; i++) {
            int y = min + (start - min + i) % size;
            StringBuilder names = new StringBuilder();
            for (int x = y - before; x <= y + after; x++) names.append(names.length() == 0 ? "" : ",").append(x).append('/').append(x + 1);
            boolean opened = jdbc.sql("SELECT EXISTS (SELECT 1 FROM policy.academic_session WHERE name = ANY (string_to_array(:n, ',')))")
                    .param("n", names.toString()).query(Boolean.class).single();
            if (!opened) {
                return y;
            }
        }
        return start;
    }

    /** a far-future session for the test's own use, non-overlapping with every other test's */
    void session(String name, int startYear) {
        db(() -> jdbc.sql("""
                INSERT INTO policy.academic_session (id, name, starts_on, ends_on)
                VALUES (gen_random_uuid(), :n, make_date(:y, 10, 1), make_date(:y + 1, 8, 31))
                ON CONFLICT (name) DO NOTHING
                """).param("n", name).param("y", startYear).update());
    }

    /** Admission Status Checking open for a session's applicants (V295): the Director of ICT's window, closed until first opened,
     *  opened here as the Director's act would open it, unless it is open already */
    void openChecking(String session) {
        db(() -> jdbc.sql("""
                SELECT CASE WHEN (SELECT w.state FROM policy.window_state('ADMISSION_STATUS_CHECKING', :s, NULL) w) = 'OPEN' THEN NULL
                            ELSE policy.window_act('ADMISSION_STATUS_CHECKING', :s, NULL, 'OPEN', NULL, NULL, NULL, false,
                                                   'integration test: admission status checking open', gen_random_uuid(), 'ict') END
                """).param("s", session).query().listOfRows());
    }

    /** whether a student holds the number, as admission or matriculation number */
    boolean taken(String number) {
        return jdbc.sql("SELECT EXISTS (SELECT 1 FROM people.student WHERE matric_no = :n OR admission_no = :n)")
                .param("n", number).query(Boolean.class).single();
    }

    /** the prefix and a number of the width given that no student holds, as admission or matriculation number: a test's invented
     *  student never draws the number of one an earlier run, or another class, left on the database (four random digits did) */
    String freeNumber(String prefix, int digits) {
        int bound = (int) Math.pow(10, digits);
        for (int i = 0; i < 500; i++) {
            String number = prefix + String.format("%0" + digits + "d", java.util.concurrent.ThreadLocalRandom.current().nextInt(bound / 10, bound));
            if (!taken(number)) {
                return number;
            }
        }
        throw new IllegalStateException("no free number after " + prefix + " in " + digits + " digits");
    }

    /** a number in [min, bound) none of whose identifiers — as {@code identifiers} builds them from it: matriculation, admission and
     *  staff numbers, the surnames of invented students and people — any student or person holds, so the people a test invents from
     *  one random number are new on any database, however often the suite has run on it */
    int freeDraw(int min, int bound, java.util.function.IntFunction<List<String>> identifiers) {
        for (int i = 0; i < 500; i++) {
            int n = java.util.concurrent.ThreadLocalRandom.current().nextInt(min, bound);
            String ids = String.join("|", identifiers.apply(n));
            boolean taken = jdbc.sql("""
                    SELECT EXISTS (SELECT 1 FROM people.student s, string_to_array(:ids, '|') a
                                    WHERE s.matric_no = ANY (a) OR s.admission_no = ANY (a) OR s.surname = ANY (a))
                        OR EXISTS (SELECT 1 FROM iam.person p, string_to_array(:ids, '|') a WHERE p.staff_number = ANY (a) OR p.surname = ANY (a))
                    """).param("ids", ids).query(Boolean.class).single();
            if (!taken) {
                return n;
            }
        }
        throw new IllegalStateException("no free draw in [" + min + ", " + bound + ")");
    }

    /** a surname no student holds: {@link #student} hands back the student of a surname already invented, so a surname drawn again
     *  would give the test an earlier run's student and its state */
    String freeSurname(String prefix) {
        for (int i = 0; i < 500; i++) {
            String surname = prefix + java.util.concurrent.ThreadLocalRandom.current().nextInt(100_000, 1_000_000);
            if (!jdbc.sql("SELECT EXISTS (SELECT 1 FROM people.student WHERE surname = :s)").param("s", surname).query(Boolean.class).single()) {
                return surname;
            }
        }
        throw new IllegalStateException("no free surname after " + prefix);
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

    /**
     * A token for an office held over a scope (V316/V318): an invented person with a standing grant of the
     * office over the department, programme or faculty named — the Head of Department over 'MTC', the
     * Programme Examinations Officer over 'C00023', the Dean over 'SC'. The same office over the same scope
     * is the same person on every run, so the chain's rule that no two consecutive stages are one person's
     * holds between offices and not within one.
     */
    String officer(String office, String scopeKind, String scopeId) {
        String tag = scopeId.replaceAll("[^A-Za-z0-9]", "");
        UUID id = person("ZZ-" + office.toUpperCase() + "-" + tag, "ZZ" + office.toUpperCase() + tag);
        db(() -> jdbc.sql("""
                INSERT INTO iam.office_assignment (id, person_id, office_code, scope_kind, scope_id, instrument, granted_by, valid_from)
                SELECT gen_random_uuid(), :p, :o, :k, :s, 'integration test', :p, current_date
                 WHERE NOT EXISTS (SELECT 1 FROM iam.office_assignment a
                                    WHERE a.person_id = :p AND a.office_code = :o AND a.scope_kind = :k AND upper(a.scope_id) = upper(:s)
                                      AND (a.valid_to IS NULL OR a.valid_to >= current_date))
                """).param("p", id).param("o", office).param("k", scopeKind).param("s", scopeId).update());
        return TestTokens.token(id, List.of(office));
    }
}
