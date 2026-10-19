package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.List;
import java.util.Map;
import java.util.UUID;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.HttpMethod;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.transaction.PlatformTransactionManager;

/**
 * Student 360° — the full record over the API: the sections read what the modules hold (a payment of the student's own, a level
 * corrected through the record's own endpoint read back from the audit chain), a receipt is the student's own receipt and only for
 * a confirmed reference of that student (another student's reference through this student's record is not found — no IDOR), the
 * offices that do not read fees are refused the finance and the receipts, a Head of Department reads only their department's
 * students, a lecturer or the library only their part, and a student none of it. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = {"moaum.auth.hmac-secret=" + TestTokens.SECRET})
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"unchecked", "rawtypes"})
class StudentFullRecordIT {

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    ItSupport it;

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
    }

    private String pay(UUID student, long amount, boolean confirmed) {
        String ref = "MOAUM-ITSR-" + UUID.randomUUID().toString().substring(0, 12).toUpperCase();
        it.db(() -> jdbc.sql("""
                INSERT INTO finance.payment_reference (student_id, session, reference, purpose, amount, expires_at, confirmed_at, confirmed_by, channel, receipt_no, note)
                VALUES (:st, '2020/2021', :r, 'School fees 2020/2021', :a, now() + interval '7 days',
                        CASE WHEN :c THEN now() END, CASE WHEN :c THEN gen_random_uuid() END, CASE WHEN :c THEN 'INTERSWITCH' END,
                        CASE WHEN :c THEN 'RCT-' || :r END, 'full record test')
                """).param("st", student).param("r", ref).param("a", amount).param("c", confirmed).update());
        return ref;
    }

    private static String path(UUID id, String section) {
        return "/api/v1/student/students/" + id + "/full/" + section;
    }

    @Test
    void theSectionsReadTheRecordAndTheReceiptIsOnlyTheStudentsOwn() {
        UUID mine = it.student(it.freeSurname("ZZSRA"), "C00023", null, it.freeNumber("MOAUM/SRA/86/", 6), 200);
        UUID other = it.student(it.freeSurname("ZZSRB"), "C00023", null, it.freeNumber("MOAUM/SRB/86/", 6), 200);
        String paid = pay(mine, 75000, true);
        String pending = pay(mine, 5000, false);
        String theirs = pay(other, 75000, true);
        String bursar = ItSupport.token("bursar");

        ResponseEntity<Map> o = it.get(bursar, path(mine, "overview"));
        assertThat(o.getStatusCode().value()).as(String.valueOf(o.getBody())).isEqualTo(200);
        assertThat((Map<String, Object>) o.getBody().get("identity")).containsEntry("current_level", 200).containsEntry("programme_code", "C00023");
        assertThat((List<String>) o.getBody().get("sections")).contains("overview", "finance", "results", "registrations");
        // the Bursary reads the record's money, not its activity log
        assertThat((List<String>) o.getBody().get("sections")).doesNotContain("audit");

        ResponseEntity<Map> f = it.get(bursar, path(mine, "finance"));
        assertThat(f.getStatusCode().value()).as(String.valueOf(f.getBody())).isEqualTo(200);
        List<Map<String, Object>> payments = (List<Map<String, Object>>) f.getBody().get("payments");
        assertThat(payments).extracting(p -> p.get("reference")).containsExactlyInAnyOrder(paid, pending);
        assertThat(payments).filteredOn(p -> paid.equals(p.get("reference"))).first().satisfies(p -> {
            assertThat(p.get("status")).isEqualTo("PAID");
            assertThat(p.get("school_fees")).isEqualTo(true);
        });
        assertThat(payments).filteredOn(p -> pending.equals(p.get("reference"))).first().extracting(p -> p.get("status")).isEqualTo("PENDING");

        // the receipt: the student's own, with the signed check code its QR carries
        ResponseEntity<Map> r = it.get(bursar, path(mine, "receipts/" + paid));
        assertThat(r.getStatusCode().value()).as(String.valueOf(r.getBody())).isEqualTo(200);
        // the level the student was at in the session paid for (entry 2020/2021 at 100), as on the student's own receipt — not today's 200
        assertThat(r.getBody()).containsEntry("reference", paid).containsEntry("receipt_no", "RCT-" + paid).containsEntry("level", 100);
        assertThat(String.valueOf(r.getBody().get("checkCode"))).isNotBlank();
        // the QR's code is the one the public verification checks: the same receipt as the student's, genuine
        ResponseEntity<Map> v = it.get(bursar, "/api/v1/verify/receipt/" + paid + "?c=" + r.getBody().get("checkCode"));
        assertThat(v.getStatusCode().value()).as(String.valueOf(v.getBody())).isEqualTo(200);
        assertThat(v.getBody()).containsEntry("genuine", true);
        assertThat(it.get(bursar, "/api/v1/verify/receipt/" + paid + "?c=0000" + r.getBody().get("checkCode")).getBody()).containsEntry("genuine", false);
        // another student's reference through this student's record is not found; an unconfirmed one has no receipt
        assertThat(it.get(bursar, path(mine, "receipts/" + theirs)).getStatusCode().value()).isEqualTo(404);
        assertThat(it.get(bursar, path(mine, "receipts/" + pending)).getStatusCode().value()).isEqualTo(422);
        assertThat(it.get(bursar, path(UUID.randomUUID(), "overview")).getStatusCode().value()).isEqualTo(404);

        // the offices that do not read fees are refused the money and its receipts, whatever they ask for
        String library = ItSupport.token("library");
        ResponseEntity<Map> lo = it.get(library, path(mine, "overview"));
        assertThat(lo.getStatusCode().value()).isEqualTo(200);
        assertThat(lo.getBody()).doesNotContainKey("contact").doesNotContainKey("fees");
        assertThat((List<String>) lo.getBody().get("sections")).containsExactly("overview", "clearance");
        assertThat(it.get(library, path(mine, "finance")).getStatusCode().value()).isEqualTo(403);
        assertThat(it.get(library, path(mine, "receipts/" + paid)).getStatusCode().value()).isEqualTo(403);
        assertThat(it.get(library, path(mine, "admission")).getStatusCode().value()).isEqualTo(403);
        assertThat(it.get(library, path(mine, "clearance")).getStatusCode().value()).isEqualTo(200);

        // a student reads none of it, their own record included
        String student = TestTokens.token(mine, List.of("student"));
        assertThat(it.get(student, path(mine, "overview")).getStatusCode().value()).isEqualTo(403);
        assertThat(it.get(student, path(mine, "receipts/" + paid)).getStatusCode().value()).isEqualTo(403);
    }

    @Test
    void aHeadOfDepartmentReadsTheirOwnStudentsAndALecturerOnlyTheirs() {
        UUID mine = it.student(it.freeSurname("ZZSRH"), "C00023", null, it.freeNumber("MOAUM/SRH/86/", 6), 100);
        String dept = jdbc.sql("SELECT dept_code FROM ref.programme WHERE code = 'C00023'").query(String.class).single();
        String other = jdbc.sql("SELECT code FROM ref.department WHERE code <> :d ORDER BY code LIMIT 1").param("d", dept).query(String.class).single();
        String paid = pay(mine, 1000, true);

        String hod = it.officer("hod", "department", dept);
        assertThat(it.get(hod, path(mine, "overview")).getStatusCode().value()).isEqualTo(200);
        assertThat(it.get(hod, path(mine, "receipts/" + paid)).getStatusCode().value()).isEqualTo(200);
        String elsewhere = it.officer("hod", "department", other);
        for (String section : List.of("overview", "finance", "results", "registrations", "receipts/" + paid)) {
            assertThat(it.get(elsewhere, path(mine, section)).getStatusCode().value()).as(section).isEqualTo(403);
        }
        // a lecturer who teaches the student nothing reads nothing of theirs
        String lecturer = TestTokens.token(it.person("ZZ-LECT-SR", "ZZLECTSR"), List.of("lecturer"));
        assertThat(it.get(lecturer, path(mine, "overview")).getStatusCode().value()).isEqualTo(403);
    }

    @Test
    void aLevelCorrectedIsReadBackFromTheAuditChainAndNothingIsFilledIn() {
        UUID mine = it.student(it.freeSurname("ZZSRL"), "C00023", null, it.freeNumber("MOAUM/SRL/86/", 6), 200);
        String registrar = ItSupport.token("registrar");
        ResponseEntity<Map> before = it.get(registrar, path(mine, "progression"));
        assertThat(before.getStatusCode().value()).as(String.valueOf(before.getBody())).isEqualTo(200);
        assertThat((List<?>) before.getBody().get("changes")).isEmpty();
        // no enrolment and no registration: no level is shown for any session
        assertThat((List<?>) before.getBody().get("held")).isEmpty();

        ResponseEntity<Map> put = it.call(registrar, HttpMethod.PUT, "/api/v1/student/students/" + mine + "/level", Map.of("level", 300, "reason", "Passed 200 Level"));
        assertThat(put.getStatusCode().value()).as(String.valueOf(put.getBody())).isEqualTo(200);

        ResponseEntity<Map> after = it.get(registrar, path(mine, "progression"));
        List<Map<String, Object>> changes = (List<Map<String, Object>>) after.getBody().get("changes");
        assertThat(changes).hasSize(1);
        assertThat(changes.get(0)).containsEntry("previous_level", 200).containsEntry("new_level", 300).containsEntry("actor_office", "registrar");
        assertThat((List<?>) after.getBody().get("held")).isEmpty();

        // the activity on the record says so too, for the Registry; a Bursar does not read it
        ResponseEntity<Map> audit = it.get(registrar, path(mine, "audit"));
        assertThat(audit.getStatusCode().value()).isEqualTo(200);
        assertThat((List<Map<String, Object>>) audit.getBody().get("activity")).anySatisfy(a -> {
            assertThat(a.get("kind")).isEqualTo("RECORD_UPDATE");
            assertThat(String.valueOf(a.get("changed"))).contains("current_level");
        });
        assertThat(it.get(ItSupport.token("bursar"), path(mine, "audit")).getStatusCode().value()).isEqualTo(403);

        // the results of a student with no approved registration: none, and no standing made up
        ResponseEntity<Map> results = it.get(registrar, path(mine, "results"));
        assertThat(results.getStatusCode().value()).isEqualTo(200);
        assertThat((List<?>) results.getBody().get("results")).isEmpty();
        assertThat((List<?>) results.getBody().get("owed")).isEmpty();
    }
}
