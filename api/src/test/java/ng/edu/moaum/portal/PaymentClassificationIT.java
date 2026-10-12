package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.math.BigDecimal;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import org.junit.jupiter.api.AfterEach;
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
 * Every payment on the one ledger, classified by programme type, purpose, source module and responsible office as separate
 * dimensions (V409): an undergraduate's school fees are the Bursary's, a Sandwich student's are Sandwich school fees, a CCE
 * student's GST fee is the GST office's whatever the programme, a JUPEB application is the JUPEB Office's and now on the same
 * ledger. The Bursary reads "Sandwich school fees" and "JUPEB applications" as figures; an office that owns a purpose reads
 * only its own, whatever it asks for; the catalogue is the Bursary's to state, and a rule stated reclassifies at once; the
 * student's receipt says what was paid for; the general ledger posts JUPEB's payment too. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class PaymentClassificationIT {

    static final String S = "2135/2136";
    static final String SUMMARY = "/api/v1/analytics/finance/summary?compare=false&session=" + S;
    static final String TRANSACTIONS = "/api/v1/analytics/finance/transactions?size=200&session=" + S;

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    ItSupport it;
    String bursar;
    UUID ug;
    UUID sandwich;
    UUID cce;
    UUID jupebApp;
    String tag;
    String sandwichRef;
    String jupebRef;

    static List<Map<String, Object>> l(Object o) { return (List<Map<String, Object>>) o; }

    private String pay(UUID student, String purpose, int amount) {
        String ref = "ZZPC-" + tag + "-" + amount;
        it.db(() -> jdbc.sql("""
                INSERT INTO finance.payment_reference (id, student_id, session, reference, purpose, amount, expires_at, confirmed_at, confirmed_by, channel, receipt_no)
                VALUES (gen_random_uuid(), :s, :ses, :r, :p, :a, now() + interval '30 days', now(), :s, 'WEBPAY', :rc)
                """).param("s", student).param("ses", S).param("r", ref).param("p", purpose).param("a", amount).param("rc", "RCT/PC/" + tag + "/" + amount).update());
        return ref;
    }

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
        it.session(S, 2135);
        tag = UUID.randomUUID().toString().substring(0, 6).toUpperCase();
        bursar = TestTokens.token(it.person("ZZ-PC-BURSAR", "ZZPCBURSAR"), List.of("bursar"));
        ug = it.student("ZZPCUG", "C00023", null, "MOAUM/MTC/95/7701", 300);
        sandwich = it.student("ZZPCSANDWICH", "C00023", null, "MOAUM/MTC/95/7702", 300);
        cce = it.student("ZZPCCCE", "C00023", null, "MOAUM/MTC/95/7703", 200);
        it.db(() -> {
            // the route is the Registry's to set (STUDENT_ROUTE_LOCKED): the fixture acts as the Registry
            jdbc.sql("SELECT set_config('moaum.actor_office', 'registrar', true)").query().listOfRows();
            jdbc.sql("UPDATE people.student SET entry_mode = 'UTME', study_mode = 'FULL_TIME' WHERE id = :s").param("s", ug).update();
            jdbc.sql("UPDATE people.student SET entry_mode = 'SANDWICH', study_mode = 'FULL_TIME' WHERE id = :s").param("s", sandwich).update();
            jdbc.sql("UPDATE people.student SET study_mode = 'PART_TIME', entry_mode = 'CCE' WHERE id = :s").param("s", cce).update();
            // an earlier run's payments of this session: each run counts its own
            jdbc.sql("DELETE FROM finance.payment_reference WHERE session = :ses AND student_id IN (:a, :b, :c)").param("ses", S).param("a", ug).param("b", sandwich).param("c", cce).update();
            jdbc.sql("DELETE FROM jupeb.fee_reference WHERE session = :ses AND reference LIKE 'JUPEB-ZZPC%'").param("ses", S).update();
            return null;
        });
        // a JUPEB student, uploaded from the old portal as the JUPEB Office does
        String office = ItSupport.token("jupeb");
        Map<String, Object> row = new HashMap<>(Map.of("row", 2, "appNo", "ZZPCJ01", "firstName", "Doose", "surname", "ZZPCJUPEB", "email", "zzpcjupeb@example.com"));
        Map<String, Object> in = new HashMap<>(Map.of("rows", List.of(row), "session", S, "dayFirst", true, "commit", true, "fileName", "pc.xlsx", "emailLinks", false));
        it.call(office, HttpMethod.POST, "/api/v1/jupeb/office/old-portal-students/import", in);
        jupebApp = jdbc.sql("SELECT id FROM jupeb.application WHERE application_no = 'ZZPCJ01'").query(UUID.class).single();

        pay(ug, "School fees (full session)", 180000);
        pay(ug, "Hostel accommodation " + S, 30000);
        sandwichRef = pay(sandwich, "School fees (full session)", 200000);
        pay(cce, "GST fee " + S, 20000);
        jupebRef = "JUPEB-ZZPC" + tag;
        it.db(() -> jdbc.sql("""
                INSERT INTO jupeb.fee_reference (application_id, kind, reference, amount, session, expires_at, confirmed_at, channel)
                VALUES (:a, 'APPLICATION', :r, 15000, :s, now() + interval '30 days', now(), 'WEBPAY')
                """).param("a", jupebApp).param("r", jupebRef).param("s", S).update());
    }

    @AfterEach
    void tearDown() {
        it.db(() -> {
            jdbc.sql("DELETE FROM finance.payment_classification WHERE purpose = 'SCHOOL_FEES' AND programme_type = 'SANDWICH'").update();
            jdbc.sql("UPDATE finance.programme_type SET programme_categories = '{}' WHERE code = 'PRELIMINARY'").update();
            return null;
        });
    }

    private static Map<String, Object> pick(List<Map<String, Object>> rows, String type, String purpose) {
        return rows.stream().filter(r -> type.equals(r.get("programme_type")) && purpose.equals(r.get("purpose_code"))).findFirst().orElse(null);
    }

    private static int amount(Map<String, Object> m) {
        return m == null ? 0 : new BigDecimal(String.valueOf(m.get("amount"))).intValue();
    }

    @Test
    void everyPaymentIsClassifiedOnTheOneLedgerAndTheBursaryReadsItByTypeAndPurpose() {
        Map<String, Object> sum = it.get(bursar, SUMMARY).getBody();
        List<Map<String, Object>> byTypePurpose = l(sum.get("byTypeAndPurpose"));
        assertThat(amount(pick(byTypePurpose, "UNDERGRADUATE", "SCHOOL_FEES"))).isEqualTo(180000);
        assertThat(amount(pick(byTypePurpose, "SANDWICH", "SCHOOL_FEES"))).isEqualTo(200000);
        assertThat(amount(pick(byTypePurpose, "CCE", "GST_FEE"))).isEqualTo(20000);
        assertThat(amount(pick(byTypePurpose, "JUPEB", "APPLICATION"))).isEqualTo(15000);
        assertThat(amount(pick(byTypePurpose, "UNDERGRADUATE", "HOSTEL_FEE"))).isEqualTo(30000);
        assertThat(pick(byTypePurpose, "SANDWICH", "SCHOOL_FEES").get("programme_type_label")).isEqualTo("Sandwich");
        // a filter is a figure: Sandwich school fees alone
        Map<String, Object> sandwichFees = (Map<String, Object>) it.get(bursar, SUMMARY + "&ptype=SANDWICH&purpose=SCHOOL_FEES").getBody().get("totals");
        assertThat(new BigDecimal(String.valueOf(sandwichFees.get("amount"))).intValue()).isEqualTo(200000);
        // the source module and the responsible office are kept apart
        assertThat(l(sum.get("bySourceModule"))).extracting(r -> r.get("source_module")).contains("STUDENT_FINANCE", "SANDWICH", "GST", "JUPEB", "HOSTEL");
        assertThat(l(sum.get("byResponsibleOffice"))).extracting(r -> r.get("responsible_office")).contains("bursar", "gst", "jupeb", "housing");

        // the transactions carry every dimension
        List<Map<String, Object>> rows = l(it.get(bursar, TRANSACTIONS).getBody().get("rows"));
        Map<String, Object> sw = rows.stream().filter(r -> sandwichRef.equals(r.get("reference"))).findFirst().orElseThrow();
        assertThat(sw).containsEntry("programme_type", "SANDWICH").containsEntry("purpose_code", "SCHOOL_FEES").containsEntry("source_module", "SANDWICH")
                .containsEntry("responsible_office", "bursar").containsEntry("admission_route", "SANDWICH").containsEntry("ledger_status", "PAID");
        Map<String, Object> jp = rows.stream().filter(r -> jupebRef.equals(r.get("reference"))).findFirst().orElseThrow();
        assertThat(jp).containsEntry("source", "JUPEB").containsEntry("programme_type", "JUPEB").containsEntry("purpose_code", "APPLICATION")
                .containsEntry("source_module", "JUPEB").containsEntry("responsible_office", "jupeb").containsEntry("application_no", "ZZPCJ01");

        // the student's receipt says what was paid for, on which programme
        Map<String, Object> receipt = it.get(TestTokens.token(sandwich, List.of("student")), "/api/v1/me/fees/receipts/" + sandwichRef).getBody();
        assertThat(receipt).containsEntry("programme_type_label", "Sandwich").containsEntry("purpose_label", "School fees").containsEntry("responsible_office", "bursar");

        // the general ledger posts JUPEB's payment, to the income account of its purpose
        assertThat(it.call(bursar, HttpMethod.POST, "/api/v1/finance/accounting/sync", Map.of()).getStatusCode().value()).isEqualTo(200);
        assertThat(jdbc.sql("""
                SELECT p.account FROM finance.gl_journal j JOIN finance.gl_posting p ON p.journal_id = j.id
                 WHERE j.source_type = 'PAYMENT' AND j.source_ref = :r AND p.credit > 0
                """).param("r", jupebRef).query(String.class).list()).containsExactly("4030");
    }

    @Test
    void anOfficeThatOwnsAPurposeReadsOnlyItsOwnAndTheCatalogueIsTheBursarys() {
        // the JUPEB Office: JUPEB's payments only, whatever it asks for
        String jupeb = ItSupport.token("jupeb");
        Map<String, Object> mine = it.get(jupeb, SUMMARY).getBody();
        assertThat(l(mine.get("byProgrammeType"))).extracting(r -> r.get("programme_type")).containsOnly("JUPEB");
        assertThat(((Map<String, Object>) mine.get("scope")).get("owner")).isEqualTo("jupeb");
        Map<String, Object> asked = (Map<String, Object>) it.get(jupeb, SUMMARY + "&ptype=UNDERGRADUATE").getBody().get("totals");
        assertThat(new BigDecimal(String.valueOf(asked.get("amount"))).intValue()).isZero();
        assertThat(l(it.get(jupeb, TRANSACTIONS).getBody().get("rows"))).extracting(r -> r.get("responsible_office")).containsOnly("jupeb");
        // the GST office: the CCE student's GST fee is theirs, the school fees are not
        Map<String, Object> gst = it.get(ItSupport.token("gst"), SUMMARY).getBody();
        assertThat(l(gst.get("byTypeAndPurpose"))).extracting(r -> r.get("programme_type") + "/" + r.get("purpose_code")).containsOnly("CCE/GST_FEE");

        // the catalogue: read by the finance readers, stated by the Bursary only
        Map<String, Object> cat = it.get(bursar, "/api/v1/analytics/finance/classification").getBody();
        assertThat(l(cat.get("programmeTypes"))).extracting(r -> r.get("code")).contains("UNDERGRADUATE", "POSTGRADUATE", "CCE", "JUPEB", "SANDWICH", "PRELIMINARY", "REMEDIAL", "FOUNDATION");
        Map<String, Object> rule = Map.of("purpose", "SCHOOL_FEES", "programmeType", "SANDWICH", "sourceModule", "SANDWICH", "responsibleOffice", "registrar");
        assertThat(it.call(jupeb, HttpMethod.PUT, "/api/v1/analytics/finance/classification", rule).getStatusCode().value()).isEqualTo(403);
        assertThat(it.call(bursar, HttpMethod.PUT, "/api/v1/analytics/finance/classification", rule).getStatusCode().value()).isEqualTo(200);
        Map<String, Object> sw = l(it.get(bursar, TRANSACTIONS + "&ptype=SANDWICH").getBody().get("rows")).stream()
                .filter(r -> sandwichRef.equals(r.get("reference"))).findFirst().orElseThrow();
        assertThat(sw).containsEntry("responsible_office", "registrar");
        // a programme type is mapped by the Bursary; an income account outside the ledger's is refused
        assertThat(it.call(bursar, HttpMethod.PUT, "/api/v1/analytics/finance/programme-types/PRELIMINARY",
                Map.of("label", "Preliminary", "entryModes", List.of(), "programmeCategories", List.of("ZZ PRELIMINARY"))).getStatusCode().value()).isEqualTo(200);
        assertThat(jdbc.sql("SELECT finance.programme_type_for('UTME', 'ZZ PRELIMINARY') || '/' || finance.programme_type_for(NULL, 'ZZ PRELIMINARY')").query(String.class).single())
                .isEqualTo("UNDERGRADUATE/PRELIMINARY");
        ResponseEntity<Map> badAccount = it.call(bursar, HttpMethod.PUT, "/api/v1/analytics/finance/purposes/CONVOCATION_FEE", Map.of("label", "Convocation fee", "glAccount", "1010"));
        assertThat(String.valueOf(badAccount.getBody().get("code"))).isEqualTo("PAY_PURPOSE_ACCOUNT");
    }
}
