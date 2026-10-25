package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.io.ByteArrayInputStream;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Random;
import java.util.UUID;
import java.util.zip.ZipEntry;
import java.util.zip.ZipInputStream;

import org.junit.jupiter.api.AfterEach;
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
 * V650: the Master University Report over the API. A four-year programme of the test's own, in a session of the test's own, with
 * its school fees stated for 200 Level and the session's GST fee stated, and two students: Ada (female) paid the school fees and
 * the GST fee, registered a core course and a GST course, drew her examination card and printed her GST & EPS permit; Bayo (male)
 * owes everything and holds a payment reference he never paid. A Database Operator held over the University reads the report:
 * every dimension from one dataset, the figures reconciled with each other, the students behind a figure, the transactions with
 * their status; issues it under an RPT reference, reads the PDF's package (the lists inside it), streams the Excel workbook (a
 * real workbook, a sheet for each section and list) and completes it in the history. An Examinations Officer reads it without
 * any amount and is refused the transactions; the GST office reads its own fee's payments and no school-fee amount; a Head of
 * another department is refused the programme; a lecturer reads none of it; another officer cannot complete someone else's
 * report. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class MasterReportIT {

    private static final String M = "/api/v1/reports/master";

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    ItSupport it;
    String session;
    String PROGRAMME;

    @AfterEach
    void clean() {
        if (it != null && session != null) {
            it.db(() -> jdbc.sql("DELETE FROM finance.fee_schedule WHERE session = :s AND programme_code = :p").param("s", session).param("p", PROGRAMME).update());
        }
    }

    @Test
    void oneDatasetEveryDimensionTheMoneyByOfficeAndTheReportItsOwnRecord() throws IOException {
        it = new ItSupport(port, jdbc, transactions);
        int y = it.freeYear(4400, 4490, 0, 1);
        session = y + "/" + (y + 1);
        it.session(session, y);
        PROGRAMME = jdbc.sql("SELECT 'C' || x FROM generate_series(96500, 96999) x WHERE NOT EXISTS (SELECT 1 FROM ref.programme p WHERE p.code = 'C' || x) ORDER BY random() LIMIT 1")
                .query(String.class).single();
        String yy = String.format("%02d", y % 100);
        int n = 1000 + new Random().nextInt(8999);
        String[] df = it.db(() -> {
            String[] d = jdbc.sql("""
                    SELECT p.dept_code || ',' || p.faculty_code FROM ref.programme p JOIN ref.faculty f ON f.code = p.faculty_code
                     WHERE p.category = 'UNDER GRADUATE' AND NOT p.archived AND coalesce(f.college_code, '') <> 'CHS' ORDER BY p.code LIMIT 1
                    """).query(String.class).single().split(",");
            jdbc.sql("""
                    INSERT INTO ref.programme (code, name, dept_code, faculty_code, category, min_score, final_level, duration_years)
                    VALUES (:c, 'B.Sc. Master Report Test', :d, :f, 'UNDER GRADUATE', 0, 400, 4)
                    ON CONFLICT (code) DO UPDATE SET archived = false
                    """).param("c", PROGRAMME).param("d", d[0]).param("f", d[1]).update();
            return d;
        });
        String dept = df[0];
        UUID ada = it.student("ZZMRPAID" + n, PROGRAMME, "MOAUM/ADM/" + yy + "/81" + n, "MOAUM/MRT/" + yy + "/1" + n, 200);
        UUID bayo = it.student("ZZMROWING" + n, PROGRAMME, "MOAUM/ADM/" + yy + "/82" + n, "MOAUM/MRT/" + yy + "/2" + n, 200);
        String core = "ZMR " + (100 + n % 800);
        String gst = "GST " + (900 + n % 99);    // above every real GST course code
        String[] refs = it.db(() -> {
            jdbc.sql("UPDATE people.student SET entry_session = :e, sex = CASE WHEN id = :a THEN 'F' ELSE 'M' END WHERE id IN (:a, :b)")
                    .param("e", (y - 1) + "/" + y).param("a", ada).param("b", bayo).update();
            jdbc.sql("INSERT INTO catalogue.course (code, title, units, semester, level, dept_code, kind, state) VALUES (:c, 'Master Report Core', 3, 1, 200, :d, 'Core', 'LIVE'), (:g, 'Master Report GST', 2, 1, 200, :d, 'GST', 'LIVE') ON CONFLICT DO NOTHING")
                    .param("c", core).param("g", gst).param("d", dept).update();
            jdbc.sql("INSERT INTO catalogue.course_offer (course_code, programme_code, level, basis) VALUES (:c, :p, 200, 'Core'), (:g, :p, 200, 'GST') ON CONFLICT DO NOTHING")
                    .param("c", core).param("g", gst).param("p", PROGRAMME).update();
            UUID oc = UUID.randomUUID(), og = UUID.randomUUID(), reg = UUID.randomUUID();
            jdbc.sql("INSERT INTO catalogue.offering (id, course_code, session, semester) VALUES (:oc, :c, :s, 1), (:og, :g, :s, 1)")
                    .param("oc", oc).param("og", og).param("c", core).param("g", gst).param("s", session).update();
            jdbc.sql("INSERT INTO finance.fee_schedule (session, item, amount, level, programme_code) VALUES (:s, 'School fees', 100000, 200, :p)")
                    .param("s", session).param("p", PROGRAMME).update();
            jdbc.sql("SELECT finance.state_gst_fee(:s, 4000, NULL, NULL, NULL, NULL, NULL, 'master report test', gen_random_uuid(), 'bursar')")
                    .param("s", session).query().listOfRows();
            jdbc.sql("INSERT INTO registration.course_registration (id, student_id, session, semester, level, status, submitted_at) VALUES (:r, :st, :s, 1, 200, 'SUBMITTED', now())")
                    .param("r", reg).param("st", ada).param("s", session).update();
            jdbc.sql("INSERT INTO registration.entry (registration_id, offering_id, units, entry_type, status) VALUES (:r, :oc, 3, 'CURRENT', 'REGISTERED'), (:r, :og, 2, 'CURRENT', 'REGISTERED')")
                    .param("r", reg).param("oc", oc).param("og", og).update();
            String fees = jdbc.sql("SELECT finance.new_reference(:s, :ses, 100000, NULL)").param("s", ada).param("ses", session).query(String.class).single();
            jdbc.sql("SELECT finance.confirm_payment(:r, 'BANK_BRANCH', 'teller for the master report test')").param("r", fees).query(String.class).single();
            String gstRef = jdbc.sql("SELECT finance.new_gst_reference(:s, :ses)").param("s", ada).param("ses", session).query(String.class).single();
            jdbc.sql("SELECT finance.confirm_payment(:r, 'BANK_BRANCH', 'teller for the master report test')").param("r", gstRef).query(String.class).single();
            String pending = jdbc.sql("SELECT finance.new_reference(:s, :ses, 50000, NULL)").param("s", bayo).param("ses", session).query(String.class).single();
            jdbc.sql("INSERT INTO registration.exam_card_issue (student_id, session, semester, times) VALUES (:st, :s, 1, 1)").param("st", ada).param("s", session).update();
            jdbc.sql("INSERT INTO registration.gst_eps_permit (reference, student_id, session, semester, printed) VALUES (:r, :st, :s, 1, 1)")
                    .param("r", "GST-EPS/" + y + "/99" + n).param("st", ada).param("s", session).update();
            return new String[] {fees, gstRef, pending};
        });

        String operator = it.officer("dbops", "institution", "University");
        String q = "?session=" + session + "&semester=1&prog=" + PROGRAMME;

        // what there is to choose from, and the money the office reads
        ResponseEntity<Map> options = it.get(operator, M + "/options");
        assertThat(options.getStatusCode().value()).as(String.valueOf(options.getBody())).isEqualTo(200);
        assertThat(options.getBody()).containsEntry("money", "ALL").containsKeys("period", "sessions", "types", "purposes", "scope");

        // one dataset, every dimension: the whole, the gender, the fees, registration, GST, the card and the permit
        ResponseEntity<Map> summary = it.get(operator, M + "/summary" + q);
        assertThat(summary.getStatusCode().value()).as(String.valueOf(summary.getBody())).isEqualTo(200);
        Map<String, Object> all = row(summary, "ALL");
        assertThat(all).containsEntry("total", 2).containsEntry("female", 1).containsEntry("male", 1).containsEntry("fees_paid", 1).containsEntry("fees_not_paid", 1)
                .containsEntry("registered", 1).containsEntry("paid_not_registered", 0).containsEntry("gst_registered", 1).containsEntry("gst_paid", 1)
                .containsEntry("card_issued", 1).containsEntry("permit_printed", 1);
        assertThat(((Number) all.get("payable")).intValue()).isEqualTo(200000);
        assertThat(((Number) all.get("outstanding")).intValue()).isEqualTo(100000);
        List<String> keys = ((List<Map<String, Object>>) summary.getBody().get("sections")).stream().map(s -> String.valueOf(s.get("key"))).toList();
        assertThat(keys).contains("executive", "faculty", "department", "programme", "level", "gender", "fees", "tx_purpose", "gst", "registration", "cards", "permits",
                "reconciliation", "definitions");
        // the figures agree with each other, and the period's revenue is the successful payments only
        assertThat((List<Map<String, Object>>) summary.getBody().get("reconciliation")).isNotEmpty().allSatisfy(c -> assertThat(c).containsEntry("holds", true));
        Map<String, Object> txTotal = (Map<String, Object>) ((Map<String, Object>) summary.getBody().get("transactions")).get("total");
        assertThat(txTotal).containsEntry("transactions", 3);
        assertThat(((Number) txTotal.get("revenue")).intValue()).isEqualTo(104000);

        // the students behind a figure; the transactions with their status
        ResponseEntity<Map> owing = it.get(operator, M + "/students" + q + "&fee=NOT_PAID");
        assertThat(owing.getBody()).containsEntry("total", 1);
        Map<String, Object> bayoRow = ((List<Map<String, Object>>) owing.getBody().get("rows")).get(0);
        assertThat(bayoRow).containsEntry("student_id", bayo.toString()).containsEntry("card_eligible", false);
        assertThat(((Number) bayoRow.get("outstanding")).intValue()).isEqualTo(100000);
        assertThat(it.get(operator, M + "/students" + q + "&card=ISSUED").getBody()).containsEntry("total", 1);
        ResponseEntity<Map> pendingTx = it.get(operator, M + "/transactions" + q + "&pstatus=PENDING");
        assertThat(pendingTx.getStatusCode().value()).as(String.valueOf(pendingTx.getBody())).isEqualTo(200);
        assertThat(((List<Map<String, Object>>) pendingTx.getBody().get("rows"))).extracting(r -> r.get("reference")).containsExactly(refs[2]);

        // the report's own record: an RPT reference, the PDF's package with its lists, the workbook, completed in the history
        Map<String, Object> filters = new LinkedHashMap<>();
        filters.put("session", session);
        filters.put("prog", PROGRAMME);
        filters.put("scope", "The University");
        ResponseEntity<Map> issued = it.call(operator, HttpMethod.POST, M + "/issue",
                Map.of("title", "Master Academic, Finance & Student Report", "filters", filters, "rows", 2, "sections", List.of("executive", "fees")));
        assertThat(issued.getStatusCode().value()).as(String.valueOf(issued.getBody())).isEqualTo(200);
        String reference = String.valueOf(issued.getBody().get("reference"));
        assertThat(reference).matches("RPT/[0-9]{4}/[0-9]{6}");
        assertThat(issued.getBody()).containsEntry("status", "GENERATING");

        ResponseEntity<Map> pack = it.get(operator, M + "/package" + q + "&reference=" + reference);
        assertThat(pack.getStatusCode().value()).as(String.valueOf(pack.getBody())).isEqualTo(200);
        Map<String, Map<String, Object>> byKey = new LinkedHashMap<>();
        for (Map<String, Object> s : (List<Map<String, Object>>) pack.getBody().get("sections")) byKey.put(String.valueOf(s.get("key")), s);
        assertThat(byKey).containsKeys("fee_details", "card_details", "permit_details", "quality");
        assertThat((List<List<Object>>) byKey.get("fee_details").get("rows")).hasSize(2);
        assertThat((List<String>) byKey.get("fee_details").get("headers")).doesNotContain("S/N");   // S/N is drawn, never data

        ResponseEntity<byte[]> book = it.getBytes(operator, M + "/workbook" + q + "&reference=" + reference);
        assertThat(book.getStatusCode().value()).isEqualTo(200);
        assertThat(book.getHeaders().getContentType().toString()).contains("spreadsheetml");
        assertThat(book.getHeaders().getFirst("Content-Disposition")).contains("master-report-RPT-");
        Map<String, String> entries = unzip(book.getBody());
        assertThat(entries).containsKeys("[Content_Types].xml", "xl/workbook.xml", "xl/styles.xml", "xl/worksheets/sheet1.xml");
        assertThat(entries.keySet().stream().filter(e -> e.startsWith("xl/worksheets/sheet")).count()).isGreaterThan(10);
        String workbook = entries.get("xl/workbook.xml");
        assertThat(workbook).contains("Cover &amp; Summary").contains("School fees");
        assertThat(String.join("", entries.values())).contains("MOAUM/MRT/" + yy + "/2" + n).contains("<pane").contains("autoFilter");

        ResponseEntity<Map> finished = it.call(operator, HttpMethod.POST, M + "/finish", Map.of("reference", reference, "status", "COMPLETED", "formats", List.of("PDF", "XLSX"), "rows", 2));
        assertThat(finished.getStatusCode().value()).as(String.valueOf(finished.getBody())).isEqualTo(200);
        assertThat((List<Map<String, Object>>) it.getList(operator, M + "/history").getBody()).anySatisfy(h -> assertThat(h)
                .containsEntry("reference", reference).containsEntry("status", "COMPLETED").containsEntry("formats", "{PDF,XLSX}"));
        // the issue and both exports kept on the query log under the reference
        assertThat(jdbc.sql("SELECT string_agg(action || ':' || coalesce(format, ''), ',' ORDER BY action, format) FROM reporting.query_log WHERE reference = :r")
                .param("r", reference).query(String.class).single()).isEqualTo("EXPORT:PDF,EXPORT:XLSX,ISSUE:");
        // completed once; never by another officer
        String exams = it.officer("exams", "department", dept);
        ResponseEntity<Map> notMine = it.call(exams, HttpMethod.POST, M + "/finish", Map.of("reference", reference, "status", "FAILED"));
        assertThat(notMine.getStatusCode().value()).isIn(403, 422);
        assertThat((List<Map<String, Object>>) it.getList(exams, M + "/history").getBody()).noneSatisfy(h -> assertThat(h).containsEntry("reference", reference));

        // the Examinations Officer: the same figures, no amount, no transactions
        ResponseEntity<Map> noMoney = it.get(exams, M + "/summary" + q);
        assertThat(noMoney.getStatusCode().value()).as(String.valueOf(noMoney.getBody())).isEqualTo(200);
        assertThat(noMoney.getBody()).containsEntry("money", "NONE");
        Map<String, Object> examsAll = row(noMoney, "ALL");
        assertThat(examsAll).containsEntry("total", 2).containsEntry("fees_paid", 1);
        assertThat(examsAll.get("payable")).isNull();
        assertThat(examsAll.get("gst_paid_amount")).isNull();
        assertThat(noMoney.getBody().get("transactions")).isNull();
        assertThat(it.get(exams, M + "/transactions" + q).getBody()).containsEntry("code", "MASTER_MONEY");
        assertThat(((List<Map<String, Object>>) it.get(exams, M + "/students" + q).getBody().get("rows"))).isNotEmpty().allSatisfy(r -> assertThat(r.get("paid_amount")).isNull());

        // the GST office: its own fee's payments, no school-fee amount
        String gstOffice = ItSupport.token("gst");
        ResponseEntity<Map> gstView = it.get(gstOffice, M + "/summary" + q);
        assertThat(gstView.getBody()).containsEntry("money", "GST");
        assertThat(row(gstView, "ALL").get("payable")).isNull();
        assertThat(((Number) row(gstView, "ALL").get("gst_paid_amount")).intValue()).isEqualTo(4000);
        List<Map<String, Object>> gstTx = (List<Map<String, Object>>) it.get(gstOffice, M + "/transactions" + q).getBody().get("rows");
        assertThat(gstTx).extracting(r -> r.get("reference")).containsExactly(refs[1]);

        // a Head of another department is refused the programme; a lecturer reads none of it; the filters never widen the scope
        String otherDept = jdbc.sql("SELECT code FROM ref.department WHERE code <> :d AND ended_on IS NULL ORDER BY code LIMIT 1").param("d", dept).query(String.class).single();
        String hod = it.officer("hod", "department", otherDept);
        assertThat(it.get(hod, M + "/summary" + q).getStatusCode().value()).isEqualTo(422);
        assertThat(it.get(hod, M + "/students" + q).getStatusCode().value()).isEqualTo(422);
        ResponseEntity<Map> hodOwn = it.get(hod, M + "/students?session=" + session + "&semester=1");
        assertThat(((List<Map<String, Object>>) hodOwn.getBody().get("rows"))).noneSatisfy(r -> assertThat(r.get("programme_code")).isEqualTo(PROGRAMME));
        assertThat(it.get(ItSupport.token("lecturer"), M + "/summary" + q).getStatusCode().value()).isEqualTo(403);
        assertThat(it.getBytes(ItSupport.token("lecturer"), M + "/workbook" + q).getStatusCode().value()).isEqualTo(403);
    }

    private static Map<String, Object> row(ResponseEntity<Map> summary, String dim) {
        return ((List<Map<String, Object>>) summary.getBody().get("summary")).stream().filter(r -> dim.equals(r.get("dim"))).findFirst().orElseThrow();
    }

    private static Map<String, String> unzip(byte[] bytes) throws IOException {
        Map<String, String> out = new LinkedHashMap<>();
        try (ZipInputStream z = new ZipInputStream(new ByteArrayInputStream(bytes))) {
            for (ZipEntry e = z.getNextEntry(); e != null; e = z.getNextEntry()) {
                out.put(e.getName(), e.getName().endsWith(".png") ? "" : new String(z.readAllBytes(), StandardCharsets.UTF_8));
            }
        }
        return out;
    }
}
