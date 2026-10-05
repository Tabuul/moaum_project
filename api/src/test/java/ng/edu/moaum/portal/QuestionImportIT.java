package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Random;

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

/** The question bank from a spreadsheet: every row judged, the key read as letters, numbers or text, the kind worked out, duplicates found
 *  in the file and against the bank, a check writing nothing, the import writing the valid rows once, and the other office refused. */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class QuestionImportIT {

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    ItSupport it;
    String gst = ItSupport.token("gst");
    String eps = ItSupport.token("eps");
    String code;

    static Map<String, Object> m(Object o) { return (Map<String, Object>) o; }
    static List<Map<String, Object>> l(Object o) { return (List<Map<String, Object>>) o; }
    static List<String> codes(Map<String, Object> r) { return (List<String>) r.get("codes"); }

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
        int n = new Random().nextInt(9000) + 1000;
        code = "GST " + (100 + n % 199) + "Q";
        it.db(() -> {
            String dept = jdbc.sql("SELECT dept_code FROM ref.programme WHERE code = 'C00023'").query(String.class).single();
            jdbc.sql("INSERT INTO catalogue.course (code, title, units, semester, level, dept_code, kind, state) VALUES (:c, :t, 2, 1, 100, :d, 'GST', 'LIVE') ON CONFLICT (code) DO NOTHING")
                    .param("c", code).param("t", "Import General Studies " + n).param("d", dept).update();
            return null;
        });
    }

    private Map<String, Object> row(int no, String stem, List<String> options, String answer, String kind, String difficulty, String marks) {
        Map<String, Object> r = new LinkedHashMap<>();
        r.put("row", no); r.put("topic", "T1"); r.put("stem", stem); r.put("options", options); r.put("answer", answer); r.put("kind", kind); r.put("difficulty", difficulty); r.put("marks", marks); r.put("explanation", null);
        return r;
    }

    private List<Map<String, Object>> file() {
        return List.of(
                row(2, "Which arm makes laws?", List.of("Executive", "Legislature", "Judiciary", "Press"), "B", null, "EASY", "1"),
                row(3, "The judiciary interprets the law.", List.of("True", "False"), "true", null, null, null),
                row(4, "Which are even?", List.of("3", "4", "7", "10"), "B, D", null, "medium", "2"),
                row(5, "Pick by number", List.of("x", "y", "z"), "3", "MCQ", null, null),
                row(6, "", List.of("a", "b"), "A", null, null, null),
                row(7, "One option only", List.of("a"), "A", null, null, null),
                row(8, "Key names nothing", List.of("a", "b"), "Z", null, null, null),
                row(9, "Three for true/false", List.of("True", "False", "Maybe"), "A", "TRUE_FALSE", null, null),
                row(10, "Two keys for one choice", List.of("a", "b", "c"), "A, B", "MCQ", null, null),
                row(11, "Bad marks", List.of("a", "b"), "A", null, null, "0"),
                row(12, "Which arm makes laws?", List.of("Executive", "Legislature"), "B", null, null, null));
    }

    @Test
    void everyRowIsJudgedAndOnlyTheValidOnesAreWrittenOnce() {
        assertThat(it.call(eps, HttpMethod.POST, "/api/v1/cbt/questions/import", Map.of("course", code, "dryRun", true, "rows", file())).getStatusCode().value()).isEqualTo(403);
        ResponseEntity<Map> check = it.call(gst, HttpMethod.POST, "/api/v1/cbt/questions/import", Map.of("course", code, "dryRun", true, "fileName", "q.xlsx", "rows", file()));
        assertThat(check.getStatusCode().value()).as(String.valueOf(check.getBody())).isEqualTo(200);
        Map<String, Object> s = m(check.getBody().get("summary"));
        assertThat(((Number) s.get("valid")).intValue()).isEqualTo(4);
        assertThat(((Number) s.get("errors")).intValue()).isEqualTo(6);
        assertThat(((Number) s.get("duplicatesInFile")).intValue()).isEqualTo(1);
        assertThat(((Number) s.get("imported")).intValue()).isEqualTo(0);
        List<Map<String, Object>> rows = l(check.getBody().get("rows"));
        assertThat(rows.get(0).get("kind")).isEqualTo("MCQ");
        assertThat(rows.get(0).get("answers")).isEqualTo(List.of(1));
        assertThat(rows.get(1).get("kind")).as("True/False alone is a true/false question, the key read from the option's text").isEqualTo("TRUE_FALSE");
        assertThat(rows.get(1).get("answers")).isEqualTo(List.of(0));
        assertThat(rows.get(2).get("kind")).as("several keys is multiple select").isEqualTo("MULTI");
        assertThat(rows.get(2).get("answers")).isEqualTo(List.of(1, 3));
        assertThat(rows.get(3).get("answers")).as("a number is 1-based").isEqualTo(List.of(2));
        assertThat(codes(rows.get(4))).contains("STEM_REQUIRED");
        assertThat(codes(rows.get(5))).contains("OPTIONS_TOO_FEW");
        assertThat(codes(rows.get(6))).contains("ANSWER_INVALID");
        assertThat(codes(rows.get(7))).contains("TRUE_FALSE_OPTIONS");
        assertThat(codes(rows.get(8))).contains("ANSWER_INVALID");
        assertThat(codes(rows.get(9))).contains("MARKS_INVALID");
        assertThat(rows.get(10).get("status")).isEqualTo("DUPLICATE_IN_FILE");
        assertThat(jdbc.sql("SELECT count(*) FROM assessment.question WHERE course_code = :c").param("c", code).query(Long.class).single()).as("a check writes nothing").isEqualTo(0L);

        ResponseEntity<Map> imported = it.call(gst, HttpMethod.POST, "/api/v1/cbt/questions/import", Map.of("course", code, "dryRun", false, "fileName", "q.xlsx", "rows", file()));
        assertThat(imported.getStatusCode().value()).as(String.valueOf(imported.getBody())).isEqualTo(200);
        assertThat(((Number) m(imported.getBody().get("summary")).get("imported")).intValue()).isEqualTo(4);
        assertThat(jdbc.sql("SELECT count(*) FROM assessment.question WHERE course_code = :c").param("c", code).query(Long.class).single()).isEqualTo(4L);
        assertThat(jdbc.sql("SELECT answers::text FROM assessment.question WHERE course_code = :c AND kind = 'MULTI'").param("c", code).query(String.class).single()).isEqualTo("{1,3}");
        assertThat(jdbc.sql("SELECT marks FROM assessment.question WHERE course_code = :c AND kind = 'MULTI'").param("c", code).query(Integer.class).single()).isEqualTo(2);
        // the same file again: every valid row is already in the bank, nothing added twice
        Map<String, Object> again = m(it.call(gst, HttpMethod.POST, "/api/v1/cbt/questions/import", Map.of("course", code, "dryRun", false, "rows", file())).getBody().get("summary"));
        assertThat(((Number) again.get("alreadyInBank")).intValue()).isEqualTo(4);
        assertThat(((Number) again.get("imported")).intValue()).isEqualTo(0);
        assertThat(jdbc.sql("SELECT count(*) FROM assessment.question WHERE course_code = :c").param("c", code).query(Long.class).single()).isEqualTo(4L);
        // the bank reads them back with their kinds and keys
        List<Map<String, Object>> bank = l(it.get(gst, "/api/v1/cbt/questions?course=" + code).getBody().get("rows"));
        assertThat(bank).hasSize(4);
        assertThat(bank).anySatisfy(q -> { assertThat(q.get("kind")).isEqualTo("TRUE_FALSE"); assertThat(q.get("answers")).isEqualTo(List.of(0)); });
    }
}
