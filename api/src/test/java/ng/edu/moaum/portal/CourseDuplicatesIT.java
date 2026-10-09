package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.List;
import java.util.Map;
import java.util.Random;
import java.util.stream.Collectors;

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
 * The duplicate courses of a department, on a department of the test's own: the same course under two codes is a duplicate and the
 * cleanest code is kept — but a BSU- code and its MOAU- twin are never duplicates. The University keeps both: students in 300 level
 * and above carry the BSU- code, those in 100 and 200 level the MOAU- code, the same course taught by the same lecturer. A third
 * code of the same course beside the pair, or a second code of one family, is still a duplicate. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class CourseDuplicatesIT {

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    ItSupport it;
    String academic;
    String dept;
    String l;

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
        academic = TestTokens.token(it.person("ZZDUP-ACAD", "ZZDUPACAD"), List.of("academic"));
        String tag = Long.toString(Math.abs(new Random().nextLong()), 36).toUpperCase().replaceAll("[^A-Z]", "") + "QWERTY";
        dept = "Z" + tag.substring(0, 4);
        l = "Z" + tag.substring(0, 3);
        it.db(() -> jdbc.sql("INSERT INTO ref.department (code, name, faculty_code) VALUES (:c, 'DUPLICATES IT ' || :c, 'SC')").param("c", dept).update());
    }

    private void course(String code, String title, int level) {
        it.db(() -> jdbc.sql("""
                INSERT INTO catalogue.course (code, title, units, semester, level, dept_code, state)
                VALUES (:c, :t, 3, 1, :l, :d, 'LIVE')
                """).param("c", code).param("t", title).param("l", level).param("d", dept).update());
    }

    private List<Map<String, Object>> duplicates() {
        ResponseEntity<List> r = it.getList(academic, "/api/v1/catalogue/duplicates?dept=" + dept);
        assertThat(r.getStatusCode().value()).isEqualTo(200);
        return r.getBody();
    }

    private static Map<String, Boolean> keepers(List<Map<String, Object>> rows) {
        return rows.stream().collect(Collectors.toMap(m -> (String) m.get("code"), m -> (Boolean) m.get("keeper")));
    }

    @Test
    void aBsuCodeAndItsMoauTwinAreBothKeptAndOnlyTheRestAreDuplicates() {
        // the pair alone: both kept, nothing to show
        course("BSU-" + l + " 113", "Duplicates Pair Only", 100);
        course("MOAU-" + l + " 113", "duplicates  pair only", 100);
        assertThat(duplicates()).isEmpty();

        // a third, unprefixed code of the same course beside the pair: it alone is the duplicate, the pair both kept
        course("BSU-" + l + " 211", "Duplicates Triple", 200);
        course("MOAU-" + l + " 211", "Duplicates Triple", 200);
        course(l + " 211", "Duplicates Triple", 200);
        // a second code of one family: the cleaner of the two is kept
        course("BSU-" + l + " 311", "Duplicates Same Family", 300);
        course("BSU-" + l + " 311/312", "Duplicates Same Family", 300);
        // no family at all: the rule as before, the cleanest code kept
        course(l + " 105", "Duplicates Plain", 100);
        course(l + " 105/" + l + " 106", "Duplicates Plain", 100);

        Map<String, Boolean> k = keepers(duplicates());
        assertThat(k).containsOnlyKeys(
                "BSU-" + l + " 211", "MOAU-" + l + " 211", l + " 211",
                "BSU-" + l + " 311", "BSU-" + l + " 311/312",
                l + " 105", l + " 105/" + l + " 106");
        assertThat(k.get("BSU-" + l + " 211")).isTrue();
        assertThat(k.get("MOAU-" + l + " 211")).isTrue();
        assertThat(k.get(l + " 211")).isFalse();
        assertThat(k.get("BSU-" + l + " 311")).isTrue();
        assertThat(k.get("BSU-" + l + " 311/312")).isFalse();
        assertThat(k.get(l + " 105")).isTrue();
        assertThat(k.get(l + " 105/" + l + " 106")).isFalse();

        // removing the duplicates leaves every BSU- and MOAU- keeper as it was
        ResponseEntity<Map> removed = it.call(academic, HttpMethod.POST, "/api/v1/catalogue/duplicates/remove?dept=" + dept, null);
        assertThat(removed.getStatusCode().value()).as(String.valueOf(removed.getBody())).isEqualTo(200);
        assertThat(((Number) removed.getBody().get("removed")).intValue() + ((Number) removed.getBody().get("ended")).intValue()).isEqualTo(3);
        List<String> live = jdbc.sql("SELECT code FROM catalogue.course WHERE dept_code = :d AND state <> 'ENDED' ORDER BY code")
                .param("d", dept).query(String.class).list();
        assertThat(live).containsExactlyInAnyOrder(
                "BSU-" + l + " 113", "MOAU-" + l + " 113", "BSU-" + l + " 211", "MOAU-" + l + " 211", "BSU-" + l + " 311", l + " 105");
        assertThat(duplicates()).isEmpty();
    }
}
