package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.List;
import java.util.Map;
import java.util.UUID;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.transaction.PlatformTransactionManager;

/**
 * V606: the College's Student Payment Report comes a page at a time from the server, with how many the filters find and every
 * student on export, current, graduated or both; the College's MBBS machinery counts MBBS students (the College's own programmes)
 * beside the whole College — the overview's levels, the dashboard's totals — and the posting allocation list is MBBS alone.
 * Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class CollegeMbbsCountsIT {

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    private static long n(Object v) {
        return ((Number) v).longValue();
    }

    private Map<String, Object> level(List<Map<String, Object>> levels, int l) {
        return levels.stream().filter(x -> n(x.get("level")) == l).findFirst().orElseThrow();
    }

    @Test
    void theReportComesAPageAtATimeAndTheCollegesYearsCountMbbs() {
        ItSupport it = new ItSupport(port, jdbc, transactions);
        String bursar = ItSupport.token("bursar");
        String provost = ItSupport.token("provost");
        String tag = it.freeSurname("ZZCMC");

        // the overview before, then three College students of 300 Level — one MBBS, two Nursing — and a graduated MBBS student
        Map<String, Object> before = it.get(provost, "/api/v1/college/overview").getBody();
        Map<String, Object> l300 = level((List<Map<String, Object>>) before.get("levels"), 300);
        UUID mbbs = it.student(tag + "A", "C00061", null, it.freeNumber("MOAUM/CMC/26/1", 5), 300);
        UUID nurse1 = it.student(tag + "B", "C35147", null, it.freeNumber("MOAUM/CMC/26/2", 5), 300);
        UUID nurse2 = it.student(tag + "C", "C35147", null, it.freeNumber("MOAUM/CMC/26/3", 5), 300);
        UUID graduate = it.student(tag + "D", "C00061", null, it.freeNumber("MOAUM/CMC/26/4", 5), 600);
        it.db(() -> jdbc.sql("UPDATE people.student SET status = 'GRADUATED' WHERE id = :s").param("s", graduate).update());

        // the College's years count MBBS; the whole College beside it
        Map<String, Object> after = it.get(provost, "/api/v1/college/overview").getBody();
        Map<String, Object> a300 = level((List<Map<String, Object>>) after.get("levels"), 300);
        assertThat(n(a300.get("students")) - n(l300.get("students"))).isEqualTo(1);
        assertThat(n(a300.get("college_students")) - n(l300.get("college_students"))).isEqualTo(3);
        Map<String, Object> totals = (Map<String, Object>) after.get("totals");
        assertThat(n(totals.get("college_students"))).isGreaterThanOrEqualTo(n(totals.get("students")));
        ResponseEntity<Map> dashboard = it.get(provost, "/api/v1/college/dashboard");
        assertThat(dashboard.getStatusCode().value()).as(String.valueOf(dashboard.getBody())).isEqualTo(200);
        assertThat((Map<String, Object>) dashboard.getBody().get("totals")).containsKeys("students", "college_students");

        // the posting allocation list of a level is the College's own programmes' students
        ResponseEntity<List> postingList = it.getList(provost, "/api/v1/college/students?session=2025/2026&level=300");
        assertThat(postingList.getStatusCode().value()).isEqualTo(200);
        assertThat((List<Map<String, Object>>) postingList.getBody()).extracting(r -> String.valueOf(r.get("id")))
                .contains(mbbs.toString()).doesNotContain(nurse1.toString(), nurse2.toString());

        // the report a page at a time: two of three on the first page, the third on the second, all three for a download
        String q = "/api/v1/college/payments?q=" + tag;
        Map<String, Object> page1 = it.get(bursar, q + "&size=2").getBody();
        assertThat(n(page1.get("total"))).isEqualTo(3);
        assertThat((List<?>) page1.get("rows")).hasSize(2);
        assertThat(n(((Map<String, Object>) page1.get("summary")).get("students"))).isEqualTo(3);
        Map<String, Object> page2 = it.get(bursar, q + "&size=2&page=2").getBody();
        assertThat((List<?>) page2.get("rows")).hasSize(1);
        assertThat((List<?>) it.get(bursar, q + "&size=2&export=true").getBody().get("rows")).hasSize(3);
        // the graduated student is on the report when asked for, and with everyone under ALL
        Map<String, Object> grads = it.get(bursar, q + "&students=GRADUATED").getBody();
        assertThat(grads).containsEntry("students", "GRADUATED");
        assertThat((List<Map<String, Object>>) grads.get("rows")).extracting(r -> String.valueOf(r.get("id"))).containsExactly(graduate.toString());
        assertThat(n(it.get(bursar, q + "&students=ALL").getBody().get("total"))).isEqualTo(4);
    }
}
