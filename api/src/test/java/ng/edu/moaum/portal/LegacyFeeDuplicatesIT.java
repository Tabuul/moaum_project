package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.List;
import java.util.Map;
import java.util.UUID;

import ng.edu.moaum.portal.shared.AuditContext;
import ng.edu.moaum.portal.shared.AuditContextHolder;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.HttpHeaders;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;
import org.springframework.web.client.RestClient;

/**
 * V726: legacy school-fee records that repeat another on all six fields are deleted for good, one kept per group, and the run is read
 * on Old Fees History.
 *
 * <p>Three invented students in a session of the test's own: one payment recorded three times (one kept, two deleted), one recorded
 * twice with different amounts (left whole, AMOUNTS_DIFFER), and one recorded twice where the second carries a refund (left whole,
 * LINKED_RECORD). The cleanup runs as a deployment would run it; the Bursary then reads the run's counts and the two groups left
 * whole; a second run deletes nothing; a lecturer may not read it.
 *
 * <p>Needs a database the migrations have been applied to: set DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT,
        properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
class LegacyFeeDuplicatesIT {

    static final String SESSION = "2149/2150";
    static final String KEY = "MOAUM-LEG-ITDUP";
    static final List<UUID> STUDENTS = List.of(UUID.fromString("d0000000-0000-4000-8000-000000072601"),
            UUID.fromString("d0000000-0000-4000-8000-000000072602"), UUID.fromString("d0000000-0000-4000-8000-000000072603"));

    @Value("${local.server.port}")
    int port;

    @Autowired
    JdbcClient jdbc;

    @Autowired
    PlatformTransactionManager transactions;

    RestClient client;
    UUID officer = UUID.randomUUID();
    String bursar = TestTokens.token(officer, List.of("bursar"));
    String studentAccounts = TestTokens.token(UUID.randomUUID(), List.of("studentaccounts"));
    String lecturer = TestTokens.token(UUID.randomUUID(), List.of("lecturer"));

    @BeforeEach
    void setUp() {
        client = RestClient.builder().baseUrl("http://localhost:" + port).defaultStatusHandler(status -> true, (request, response) -> { }).build();
        asOfficer(() -> {
            // a previous run's records and runs taken away, so the test can run again on the same database
            jdbc.sql("DELETE FROM finance.refund WHERE reference = 'IT-V726-RF'").update();
            jdbc.sql("DELETE FROM finance.payment_reference WHERE reference LIKE :k").param("k", KEY + "%").update();
            jdbc.sql("DELETE FROM finance.legacy_fee_duplicate_run WHERE run_by LIKE 'LegacyFeeDuplicatesIT%'").update();
            jdbc.sql("INSERT INTO policy.academic_session (id, name, starts_on, ends_on) VALUES (gen_random_uuid(), :s, date '2149-10-01', date '2150-08-31') ON CONFLICT (name) DO NOTHING")
                    .param("s", SESSION).update();
            for (int i = 0; i < STUDENTS.size(); i++) {
                jdbc.sql("""
                        INSERT INTO people.student (id, admission_no, matric_no, surname, other_names, sex, programme_code, entry_mode, entry_session,
                                                    entry_level, current_level, status, matriculated_at)
                        VALUES (:id, :adm, :matric, 'ITV726', 'Invented', 'M', 'C00023', 'UTME', :s, 100, 100, 'ACTIVE', now())
                        ON CONFLICT (id) DO NOTHING
                        """).param("id", STUDENTS.get(i)).param("adm", "MOAUM/ADM/49/72600" + (i + 1)).param("matric", "MOAUM/ZZI/49/726" + (i + 1))
                        .param("s", SESSION).update();
            }
            // the records as older uploads left them: inserted, then the old portal's number written into the notes
            record(0, "-S1", 85000, "PRIT726A", 2);
            record(0, "-S1-PRIT726A", 85000, "PRIT726A", 1);
            record(0, "-S1-X", 85000, "PRIT726A", 3);
            record(1, "-S1", 85000, "PRIT726B", 1);
            record(1, "-S1-B", 84000, "PRIT726B", 2);
            record(2, "-S1", 85000, "PRIT726C", 1);
            record(2, "-S1-C", 85000, "PRIT726C", 2);
            jdbc.sql("INSERT INTO finance.legacy_payref (payref, reference, amount) VALUES ('PRIT726A', :r, 85000) ON CONFLICT (payref) DO UPDATE SET reference = EXCLUDED.reference")
                    .param("r", ref(0, "-S1")).update();
            jdbc.sql("""
                    INSERT INTO finance.refund (reference, student_id, payer, reason, amount, proposed_by, source_reference)
                    VALUES ('IT-V726-RF', :s, 'ITV726 Invented', 'LegacyFeeDuplicatesIT', 100, :who, :src)
                    """).param("s", STUDENTS.get(2)).param("who", officer).param("src", ref(2, "-S1-C")).update();
            return null;
        });
    }

    static String ref(int student, String suffix) {
        return KEY + (student + 1) + "-2149-2150" + suffix;
    }

    void record(int student, String suffix, int amount, String payref, int hour) {
        String reference = ref(student, suffix);
        jdbc.sql("""
                INSERT INTO finance.payment_reference (student_id, session, reference, purpose, amount, generated_at, expires_at, confirmed_at,
                                                       confirmed_by, channel, receipt_no, note)
                VALUES (:s, :ses, :ref, 'School fees (legacy) · semester 1', :amount, timestamptz '2149-11-01 00:00:00+00' + make_interval(hours => :h),
                        timestamptz '2149-11-01 00:00:00+00', timestamptz '2149-11-01 00:00:00+00', :who, 'Legacy', :rcpt, 'LegacyFeeDuplicatesIT')
                """).param("s", STUDENTS.get(student)).param("ses", SESSION).param("ref", reference).param("amount", amount).param("h", hour)
                .param("who", officer).param("rcpt", "LEG-" + reference).update();
        jdbc.sql("UPDATE finance.payment_reference SET note = :note WHERE reference = :ref")
                .param("note", "Imported from the old portal · old ref " + payref).param("ref", reference).update();
    }

    <T> T asOfficer(java.util.function.Supplier<T> work) {
        TransactionTemplate tx = new TransactionTemplate(transactions);
        return AuditContextHolder.with(new AuditContext(officer, "bursar", "LegacyFeeDuplicatesIT: invented records", null, null),
                () -> tx.execute(status -> work.get()));
    }

    Map<String, Object> run(String by) {
        return asOfficer(() -> jdbc.sql("SELECT status, deleted, retained, groups_found, groups_skipped FROM finance.legacy_fee_duplicates_remove(:by)")
                .param("by", by).query().singleRow());
    }

    @Test
    @SuppressWarnings({"rawtypes", "unchecked"})
    void theDuplicatesAreDeletedForGoodAndTheRunIsRead() {
        Map<String, Object> first = run("LegacyFeeDuplicatesIT");
        assertThat(first.get("status")).isEqualTo("DELETED");
        // the whole database is in scope: at least this test's three groups, of which one is cleaned and two left whole
        assertThat(((Number) first.get("deleted")).intValue()).isGreaterThanOrEqualTo(2);
        assertThat(((Number) first.get("groups_skipped")).intValue()).isGreaterThanOrEqualTo(2);

        List<String> left = jdbc.sql("SELECT reference FROM finance.payment_reference WHERE reference LIKE :k ORDER BY reference")
                .param("k", KEY + "%").query(String.class).list();
        assertThat(left).containsExactly(ref(0, "-S1"), ref(1, "-S1"), ref(1, "-S1-B"), ref(2, "-S1"), ref(2, "-S1-C"));
        assertThat(jdbc.sql("SELECT reference FROM finance.legacy_payref WHERE payref = 'PRIT726A'").query(String.class).single()).isEqualTo(ref(0, "-S1"));

        // the Bursary reads the run and the groups left whole
        ResponseEntity<Map> read = get(bursar, "bursar");
        assertThat(read.getStatusCode().value()).as(String.valueOf(read.getBody())).isEqualTo(200);
        Map<String, Object> run = ((List<Map<String, Object>>) read.getBody().get("runs")).get(0);
        assertThat(run).containsEntry("run_by", "LegacyFeeDuplicatesIT").containsEntry("status", "DELETED")
                .containsEntry("reconciliation", "PASSED").containsEntry("integrity", "PASSED");
        assertThat((String) run.get("skipped_by_reason")).contains("AMOUNTS_DIFFER").contains("LINKED_RECORD");
        Map<String, Object> now = (Map<String, Object>) read.getBody().get("now");
        assertThat(((Number) now.get("deletable")).intValue()).isZero();
        List<Map<String, Object>> leftWhole = (List<Map<String, Object>>) read.getBody().get("leftWhole");
        assertThat(leftWhole).filteredOn(r -> String.valueOf(r.get("reference")).startsWith(KEY))
                .extracting(r -> r.get("reference") + ":" + r.get("reason"))
                .containsExactlyInAnyOrder(ref(1, "-S1") + ":AMOUNTS_DIFFER", ref(1, "-S1-B") + ":AMOUNTS_DIFFER",
                        ref(2, "-S1") + ":LINKED_RECORD", ref(2, "-S1-C") + ":LINKED_RECORD");
        assertThat(leftWhole).filteredOn(r -> String.valueOf(r.get("reference")).startsWith(KEY)).allSatisfy(r -> {
            assertThat(r.get("matric_no")).asString().startsWith("MOAUM/ZZI/49/726");
            assertThat(r.get("level")).isEqualTo(100);
        });

        // a second run deletes nothing
        Map<String, Object> again = run("LegacyFeeDuplicatesIT again");
        assertThat(again.get("status")).isEqualTo("NOTHING_TO_DELETE");
        assertThat(((Number) again.get("deleted")).intValue()).isZero();

        // the Students Account Officer reads it too; a lecturer does not
        assertThat(get(studentAccounts, "studentaccounts").getStatusCode().value()).isEqualTo(200);
        assertThat(get(lecturer, "lecturer").getStatusCode().value()).isEqualTo(403);
    }

    @SuppressWarnings("rawtypes")
    ResponseEntity<Map> get(String token, String office) {
        return client.get().uri("/api/v1/finance/legacy-fees/duplicate-cleanup").header(HttpHeaders.AUTHORIZATION, "Bearer " + token)
                .header("X-Active-Office", office).retrieve().toEntity(Map.class);
    }
}
