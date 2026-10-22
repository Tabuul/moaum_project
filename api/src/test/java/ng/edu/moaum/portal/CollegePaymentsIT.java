package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.List;
import java.util.Map;
import java.util.Random;
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
 * The College's Student Payment Report (V256): a College student with a session charge split over two semesters
 * and one confirmed part payment shows the right payable, paid, outstanding and status for the whole session and
 * for each semester; the totals and the by-programme figures agree with the rows; the search finds the payment
 * reference; an office outside the readers is refused. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class CollegePaymentsIT {

    static final String SESSION = "2092/2093";

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    ItSupport it;
    String finance = ItSupport.token("financecontroller");
    String bursar = ItSupport.token("bursar");

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
        it.session(SESSION, 2092);
    }

    /** the charge never outlives the test: another test's student must not find this session as "the latest with charges" (StudentPortalService.session()) */
    @AfterEach
    void dropTheCharge() {
        it.db(() -> jdbc.sql("DELETE FROM finance.fee_schedule WHERE session = :s").param("s", SESSION).update());
    }

    @Test
    void theReportReadsThePositionBySessionAndBySemester() {
        int n = it.freeDraw(1000, 10000, k -> List.of("MOAUM/ADM/92/00" + k, "MOAUM/MED/92/" + k, "ZZCHSPAY" + k));
        // a College student (MBBS, C00061, faculty of the College) at 300 Level with an account on the register
        UUID student = it.student("ZZCHSPAY" + n, "C00061", "MOAUM/ADM/92/00" + n, "MOAUM/MED/92/" + n, 300);
        it.db(() -> jdbc.sql("UPDATE people.student SET current_level = 300 WHERE id = :s").param("s", student).update());
        // the session's charge for 300 Level: 120,000 in the first semester and 80,000 in the second
        it.db(() -> {
            jdbc.sql("DELETE FROM finance.fee_schedule WHERE session = :s").param("s", SESSION).update();
            jdbc.sql("INSERT INTO finance.fee_schedule (session, item, amount, level, semester, programme_code) VALUES (:s, 'School fees (semester 1)', 120000, 300, 1, 'C00061')").param("s", SESSION).update();
            jdbc.sql("INSERT INTO finance.fee_schedule (session, item, amount, level, semester, programme_code) VALUES (:s, 'School fees (semester 2)', 80000, 300, 2, 'C00061')").param("s", SESSION).update();
            return null;
        });
        // one payment of 150,000, confirmed by the Bursary
        String ref = it.db(() -> jdbc.sql("SELECT finance.new_reference(:s, :ses, 150000, 'School fees')").param("s", student).param("ses", SESSION).query(String.class).single());
        ResponseEntity<Map> confirmed = it.call(bursar, HttpMethod.POST, "/api/v1/finance/references/" + ref + "/confirm", Map.of("channel", "bank", "note", "test"));
        assertThat(confirmed.getStatusCode().value()).as(String.valueOf(confirmed.getBody())).isEqualTo(200);

        // the whole session: 200,000 payable, 150,000 paid, 50,000 outstanding, part payment
        Map<String, Object> row = rowFor(finance, "session=" + SESSION + "&q=ZZCHSPAY" + n, student);
        assertThat(((Number) row.get("payable")).doubleValue()).isEqualTo(200000.0);
        assertThat(((Number) row.get("paid")).doubleValue()).isEqualTo(150000.0);
        assertThat(((Number) row.get("outstanding")).doubleValue()).isEqualTo(50000.0);
        assertThat(row.get("status")).isEqualTo("PART_PAYMENT");
        assertThat(row.get("last_reference")).isEqualTo(ref);
        assertThat(row.get("programme")).isEqualTo("MBBS");

        // the first semester is covered in full; the second has 30,000 of its 80,000
        row = rowFor(finance, "session=" + SESSION + "&semester=1&q=ZZCHSPAY" + n, student);
        assertThat(((Number) row.get("payable")).doubleValue()).isEqualTo(120000.0);
        assertThat(((Number) row.get("paid")).doubleValue()).isEqualTo(120000.0);
        assertThat(row.get("status")).isEqualTo("FULLY_PAID");
        row = rowFor(finance, "session=" + SESSION + "&semester=2&q=ZZCHSPAY" + n, student);
        assertThat(((Number) row.get("payable")).doubleValue()).isEqualTo(80000.0);
        assertThat(((Number) row.get("paid")).doubleValue()).isEqualTo(30000.0);
        assertThat(((Number) row.get("outstanding")).doubleValue()).isEqualTo(50000.0);
        assertThat(row.get("status")).isEqualTo("PART_PAYMENT");

        // the search finds the payment reference; the totals and the programme line agree with the row
        ResponseEntity<Map> byRef = it.get(finance, "/api/v1/college/payments?session=" + SESSION + "&q=" + ref);
        assertThat(byRef.getStatusCode().value()).isEqualTo(200);
        Map<String, Object> summary = (Map<String, Object>) byRef.getBody().get("summary");
        assertThat(summary.get("students")).isEqualTo(1);
        assertThat(((Number) summary.get("outstanding")).doubleValue()).isEqualTo(50000.0);
        assertThat(summary.get("partPayment")).isEqualTo(1);
        List<Map<String, Object>> byProgramme = (List<Map<String, Object>>) byRef.getBody().get("byProgramme");
        assertThat(byProgramme).hasSize(1);
        assertThat(byProgramme.get(0).get("programme")).isEqualTo("MBBS");
        assertThat(byProgramme.get(0).get("students")).isEqualTo(1);

        // a status filter that excludes the student leaves the set empty; an office outside the readers is refused
        ResponseEntity<Map> none = it.get(finance, "/api/v1/college/payments?session=" + SESSION + "&status=FULLY_PAID&q=ZZCHSPAY" + n);
        assertThat(((List<?>) none.getBody().get("rows"))).isEmpty();
        assertThat(it.get(ItSupport.token("lecturer"), "/api/v1/college/payments?session=" + SESSION).getStatusCode().value()).isEqualTo(403);
    }

    /** 22 Oct 2026: the College Finance Controller reads every College payment as the Bursary reads the University's — the Payments
     *  Query (by date range, department, programme …) and the School Fees Report, held to the College on the server */
    @Test
    void theFinanceControllerQueriesTheCollegesPaymentsAloneAsTheBursaryQueriesTheUniversitys() {
        int n = it.freeDraw(1000, 10000, k -> List.of("MOAUM/ADM/92/10" + k, "MOAUM/MED/92/1" + k, "ZZCHSQ" + k, "MOAUM/ADM/92/20" + k, "MOAUM/MTC/92/2" + k, "ZZUNIQ" + k));
        UUID college = it.student("ZZCHSQ" + n, "C00061", "MOAUM/ADM/92/10" + n, "MOAUM/MED/92/1" + n, 300);
        UUID other = it.student("ZZUNIQ" + n, "C00023", "MOAUM/ADM/92/20" + n, "MOAUM/MTC/92/2" + n, 300);
        String collegeFaculty = jdbc.sql("SELECT faculty_code FROM ref.programme WHERE code = 'C00061'").query(String.class).single();
        String otherFaculty = jdbc.sql("SELECT faculty_code FROM ref.programme WHERE code = 'C00023'").query(String.class).single();
        // the session's school fees for both programmes (taken away after the test)
        it.db(() -> {
            jdbc.sql("DELETE FROM finance.fee_schedule WHERE session = :s").param("s", SESSION).update();
            for (String prog : List.of("C00061", "C00023")) {
                jdbc.sql("INSERT INTO finance.fee_schedule (session, item, amount, level, programme_code) VALUES (:s, 'School fees', 100000, 300, :p)")
                        .param("s", SESSION).param("p", prog).update();
            }
            return null;
        });
        String collegeRef = it.db(() -> jdbc.sql("SELECT finance.new_reference(:s, :ses, 70000, 'School fees')").param("s", college).param("ses", SESSION).query(String.class).single());
        String otherRef = it.db(() -> jdbc.sql("SELECT finance.new_reference(:s, :ses, 60000, 'School fees')").param("s", other).param("ses", SESSION).query(String.class).single());
        for (String ref : List.of(collegeRef, otherRef)) {
            ResponseEntity<Map> c = it.call(bursar, HttpMethod.POST, "/api/v1/finance/references/" + ref + "/confirm", Map.of("channel", "bank", "note", "test"));
            assertThat(c.getStatusCode().value()).as(String.valueOf(c.getBody())).isEqualTo(200);
        }
        String today = java.time.LocalDate.now(java.time.ZoneId.of("Africa/Lagos")).toString();
        String q = "/api/v1/finance/payments?session=" + SESSION + "&from=" + java.time.LocalDate.parse(today).minusDays(1) + "&to=" + java.time.LocalDate.parse(today).plusDays(1);

        // the Controller: the College's payment, never the University's other faculties'; the choices are the College's
        ResponseEntity<Map> mine = it.get(finance, q);
        assertThat(mine.getStatusCode().value()).as(String.valueOf(mine.getBody())).isEqualTo(200);
        List<Map<String, Object>> rows = (List<Map<String, Object>>) mine.getBody().get("rows");
        assertThat(rows).extracting(r -> r.get("reference")).contains(collegeRef).doesNotContain(otherRef);
        assertThat(rows).allSatisfy(r -> assertThat(r.get("faculty_code")).isEqualTo(collegeFaculty));
        Map<String, Object> options = (Map<String, Object>) mine.getBody().get("options");
        assertThat((List<Map<String, Object>>) options.get("faculties")).extracting(f -> f.get("code")).containsExactly(collegeFaculty);
        assertThat((List<Map<String, Object>>) options.get("programmes")).extracting(x -> x.get("code")).contains("C00061").doesNotContain("C00023");
        // by programme and by date: the College's programme finds it; a range that ends before today does not
        assertThat((List<Map<String, Object>>) it.get(finance, q + "&programme=C00061").getBody().get("rows")).extracting(r -> r.get("reference")).contains(collegeRef);
        assertThat((List<Map<String, Object>>) it.get(finance, "/api/v1/finance/payments?session=" + SESSION + "&to=" + java.time.LocalDate.parse(today).minusDays(2)).getBody().get("rows"))
                .extracting(r -> r.get("reference")).doesNotContain(collegeRef);
        // another faculty or programme asked for is refused
        ResponseEntity<Map> outside = it.get(finance, q + "&faculty=" + otherFaculty);
        assertThat(outside.getStatusCode().value()).isEqualTo(422);
        assertThat(String.valueOf(outside.getBody())).contains("SCOPE_COLLEGE");
        assertThat(it.get(finance, q + "&programme=C00023").getStatusCode().value()).isEqualTo(422);
        // the Bursary reads both, as before
        assertThat((List<Map<String, Object>>) it.get(bursar, q).getBody().get("rows")).extracting(r -> r.get("reference")).contains(collegeRef, otherRef);

        // the School Fees Report opens for the Controller, held to the College
        ResponseEntity<Map> report = it.get(finance, "/api/v1/finance/fee-report?session=" + SESSION);
        assertThat(report.getStatusCode().value()).as(String.valueOf(report.getBody())).isEqualTo(200);
        assertThat(report.getBody().get("faculty")).isEqualTo(collegeFaculty);
        assertThat(it.get(finance, "/api/v1/finance/fee-report?session=" + SESSION + "&fac=" + otherFaculty).getStatusCode().value()).isEqualTo(422);
    }

    private Map<String, Object> rowFor(String token, String query, UUID student) {
        ResponseEntity<Map> r = it.get(token, "/api/v1/college/payments?" + query);
        assertThat(r.getStatusCode().value()).as(String.valueOf(r.getBody())).isEqualTo(200);
        List<Map<String, Object>> rows = (List<Map<String, Object>>) r.getBody().get("rows");
        return rows.stream().filter(x -> student.toString().equals(String.valueOf(x.get("id")))).findFirst()
                .orElseThrow(() -> new AssertionError("the student is not on the report: " + rows));
    }
}
