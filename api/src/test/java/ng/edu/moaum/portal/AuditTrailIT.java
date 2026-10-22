package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.time.Instant;
import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.time.ZoneId;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;

/**
 * V623: the audit trail screen reads the end of the trail and counts it from the chain. A made-up member of staff written now by the
 * Directorate of ICT and a made-up student sign-in refused now are among the latest entries; the total equals the entries, staff
 * sign-ins and student sign-ins counted one by one; a filter by office or by domain returns only what it names, from the latest
 * entries (the window is stated), and the filters' counts name the domains and offices present; the Bursary may not read the trail.
 * "Today" on the tiles starts at midnight in Lagos, not at the database's UTC midnight: a made-up student sign-in a minute after
 * Lagos midnight is counted. The security posture's count of entries is the chain's, equal to the entries counted one by one.
 * V627: "who" reads one person's own entries — a made-up member of staff's writes by staff number, a made-up student's sign-in
 * by matriculation number, nobody for a name that matches no one — and a date range reads only those days (in Lagos).
 * The tiles are worked out on every call here (moaum.audit.tiles-seconds=0), so the counts are exact.
 * Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT,
        properties = {"moaum.auth.hmac-secret=" + TestTokens.SECRET, "moaum.audit.tiles-seconds=0"})
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class AuditTrailIT {

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

    private long counted() {
        return jdbc.sql("SELECT (SELECT count(*) FROM audit.entries) + (SELECT count(*) FROM iam.sign_in_event) + (SELECT count(*) FROM iam.student_event)")
                .query(Long.class).single();
    }

    private static List<Map<String, Object>> entries(ResponseEntity<Map> r) {
        return (List<Map<String, Object>>) r.getBody().get("entries");
    }

    @Test
    void theTrailIsReadFromItsEndAndCountedFromTheChain() {
        String registrar = ItSupport.token("registrar");
        String base = "/api/v1/audit";

        // a made-up member of staff written now (an attributed write by the Directorate of ICT) and a made-up student sign-in refused now
        String tag = it.freeSurname("ZZAUDTRL");
        UUID person = it.person("ZZ-ATL-" + tag.substring(8), tag);
        String identifier = "ZZ/ATL/" + tag.substring(8);
        jdbc.sql("INSERT INTO iam.student_event (student_id, identifier, outcome, ip) VALUES (NULL, :i, 'NO_ACCOUNT', '10.9.9.9')")
                .param("i", identifier).update();

        // the latest entries carry both; the total is every entry and sign-in, counted from the chain
        long before = counted();
        ResponseEntity<Map> latest = it.get(registrar, base + "/entries?limit=100");
        long after = counted();
        assertThat(latest.getStatusCode().value()).as(String.valueOf(latest.getBody())).isEqualTo(200);
        assertThat(entries(latest)).anySatisfy(e -> {
            assertThat(e).containsEntry("subject_id", person.toString()).containsEntry("actor_office", "ict").containsEntry("action", "INSERT");
        });
        assertThat(entries(latest)).anySatisfy(e -> {
            assertThat(e).containsEntry("subject_type", "student_sign_in").containsEntry("action", "auth:NO_ACCOUNT");
            assertThat(String.valueOf(e.get("reason"))).startsWith(identifier);
        });
        long total = ((Number) ((Map<String, Object>) latest.getBody().get("tiles")).get("total")).longValue();
        assertThat(total).isBetween(before, after);
        assertThat(latest.getBody().get("filterWindow")).isEqualTo(50_000);

        // a filter by office returns that office's entries alone; by domain, that domain's
        ResponseEntity<Map> byOffice = it.get(registrar, base + "/entries?office=ict&limit=500");
        assertThat(entries(byOffice)).isNotEmpty().allSatisfy(e -> assertThat(e).containsEntry("actor_office", "ict"))
                .anySatisfy(e -> assertThat(e).containsEntry("subject_id", person.toString()));
        ResponseEntity<Map> byDomain = it.get(registrar, base + "/entries?action=auth&limit=500");
        assertThat(entries(byDomain)).isNotEmpty().allSatisfy(e -> assertThat(String.valueOf(e.get("action"))).startsWith("auth:"))
                .anySatisfy(e -> assertThat(String.valueOf(e.get("reason"))).startsWith(identifier));

        // the filters' counts, over the same latest entries
        Map<String, Object> facets = it.get(registrar, base + "/facets").getBody();
        assertThat(facets).containsEntry("window", 50_000);
        assertThat((List<Map<String, Object>>) facets.get("actions")).extracting(a -> a.get("domain")).contains("INSERT", "auth");
        assertThat((List<Map<String, Object>>) facets.get("offices")).extracting(o -> o.get("actor_office")).contains("ict");

        // the Bursary does not read the trail
        assertThat(it.get(ItSupport.token("bursary"), base + "/entries").getStatusCode().value()).isEqualTo(403);
    }

    private static final String LAGOS_MIDNIGHT = "((now() AT TIME ZONE 'Africa/Lagos')::date::timestamp AT TIME ZONE 'Africa/Lagos')";

    private long countedToday() {
        return jdbc.sql("""
                SELECT (SELECT count(*) FROM audit.entries WHERE occurred_at >= %1$s)
                     + (SELECT count(*) FROM iam.sign_in_event WHERE at >= %1$s)
                     + (SELECT count(*) FROM iam.student_event WHERE at >= %1$s)
                """.formatted(LAGOS_MIDNIGHT)).query(Long.class).single();
    }

    @Test
    void todayStartsAtMidnightInLagosAndTheSecurityPostureCountsFromTheChain() {
        String auditor = ItSupport.token("audit");
        // a made-up student sign-in a minute after midnight in Lagos (23:01 UTC the day before): today in Lagos
        String identifier = "ZZ/ATL/LAGOS/" + it.freeSurname("ZZ").substring(2);
        jdbc.sql("INSERT INTO iam.student_event (student_id, identifier, outcome, ip, at) VALUES (NULL, :i, 'NO_ACCOUNT', '10.9.9.8', "
                + "least(now(), " + LAGOS_MIDNIGHT + " + interval '1 minute'))").param("i", identifier).update();
        long before = countedToday();
        ResponseEntity<Map> latest = it.get(auditor, "/api/v1/audit/entries?limit=1");
        long after = countedToday();
        assertThat(latest.getStatusCode().value()).as(String.valueOf(latest.getBody())).isEqualTo(200);
        long today = ((Number) ((Map<String, Object>) latest.getBody().get("tiles")).get("today")).longValue();
        assertThat(today).isBetween(before, after);

        // the security posture: the entries counted from the chain
        long rowsBefore = jdbc.sql("SELECT count(*) FROM audit.entries").query(Long.class).single();
        ResponseEntity<Map> posture = it.get(auditor, "/api/v1/governance/security");
        long rowsAfter = jdbc.sql("SELECT count(*) FROM audit.entries").query(Long.class).single();
        assertThat(posture.getStatusCode().value()).as(String.valueOf(posture.getBody())).isEqualTo(200);
        long entries = ((Number) ((Map<String, Object>) posture.getBody().get("audit")).get("entries")).longValue();
        assertThat(entries).isBetween(rowsBefore, rowsAfter);
    }

    private static Instant at(Map<String, Object> entry) {
        return OffsetDateTime.parse(String.valueOf(entry.get("occurred_at"))).toInstant();
    }

    @Test
    void whoReadsOnePersonsOwnEntriesAndADateRangeOnlyThoseDays() {
        String auditor = ItSupport.token("audit");
        String base = "/api/v1/audit";
        // a made-up member of staff who writes something now (an attributed write of their own) and a made-up student who signs in
        String tag = it.freeSurname("ZZAUDWHO");
        String staffNo = "ZZ-AWH-" + tag.substring(8);
        UUID person = it.person(staffNo, tag);
        UUID other = UUID.randomUUID();
        new TransactionTemplate(transactions).executeWithoutResult(tx -> {
            jdbc.sql("SELECT set_config('moaum.actor_id', :a, true), set_config('moaum.actor_office', 'ict', true), "
                    + "set_config('moaum.reason', 'audit trail who check', true)").param("a", person.toString()).query().listOfRows();
            jdbc.sql("INSERT INTO iam.person (id, staff_number, surname, given_names) VALUES (:id, :n, :s, 'Invented')")
                    .param("id", other).param("n", staffNo + "B").param("s", tag + "B").update();
        });
        String matric = it.freeNumber("MOAUM/AWH/26/", 5);
        UUID student = it.student(it.freeSurname("ZZAUDSTU"), "C00023", it.freeNumber("MOAUM/ADM/26/", 6), matric, 100);
        jdbc.sql("INSERT INTO iam.student_event (student_id, identifier, outcome, ip) VALUES (:s, :i, 'SIGNED_IN', '10.9.9.7')")
                .param("s", student).param("i", matric).update();

        // who = the staff number: their entries alone, the write among them, the person named back
        ResponseEntity<Map> byStaff = it.get(auditor, base + "/entries?who=" + staffNo);
        assertThat(byStaff.getStatusCode().value()).as(String.valueOf(byStaff.getBody())).isEqualTo(200);
        assertThat((List<Map<String, Object>>) byStaff.getBody().get("who")).extracting(w -> w.get("id")).containsExactly(person.toString());
        assertThat(entries(byStaff)).isNotEmpty().allSatisfy(e -> assertThat(e).containsEntry("actor_id", person.toString()))
                .anySatisfy(e -> assertThat(e).containsEntry("subject_id", other.toString()));
        // who = the matriculation number: the student's sign-in
        ResponseEntity<Map> byStudent = it.get(auditor, base + "/entries?who=" + matric);
        assertThat(entries(byStudent)).isNotEmpty().allSatisfy(e -> assertThat(e).containsEntry("actor_id", student.toString()))
                .anySatisfy(e -> assertThat(e).containsEntry("action", "auth:SIGNED_IN"));
        // who = nobody: nothing, and nobody named
        ResponseEntity<Map> nobody = it.get(auditor, base + "/entries?who=ZZNOBODY" + tag.substring(8));
        assertThat(entries(nobody)).isEmpty();
        assertThat((List<?>) nobody.getBody().get("who")).isEmpty();
        // the person's filters' counts
        Map<String, Object> facets = it.get(auditor, base + "/facets?who=" + staffNo).getBody();
        assertThat((List<Map<String, Object>>) facets.get("actions")).extracting(a -> a.get("domain")).contains("INSERT");

        // a date range: today in Lagos holds the write; up to yesterday holds nothing from today
        LocalDate today = LocalDate.now(ZoneId.of("Africa/Lagos"));
        Instant midnight = today.atStartOfDay(ZoneId.of("Africa/Lagos")).toInstant();
        ResponseEntity<Map> todays = it.get(auditor, base + "/entries?who=" + staffNo + "&from=" + today + "&to=" + today);
        assertThat(entries(todays)).anySatisfy(e -> assertThat(e).containsEntry("subject_id", other.toString()))
                .allSatisfy(e -> assertThat(at(e)).isAfterOrEqualTo(midnight));
        ResponseEntity<Map> before = it.get(auditor, base + "/entries?to=" + today.minusDays(1));
        assertThat(before.getStatusCode().value()).isEqualTo(200);
        assertThat(entries(before)).allSatisfy(e -> assertThat(at(e)).isBefore(midnight));
        ResponseEntity<Map> filtered = it.get(auditor, base + "/entries?office=ict&from=" + today + "&to=" + today);
        assertThat(entries(filtered)).isNotEmpty().allSatisfy(e -> {
            assertThat(e).containsEntry("actor_office", "ict");
            assertThat(at(e)).isAfterOrEqualTo(midnight);
        });
    }
}
