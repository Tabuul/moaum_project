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
 * V574 — duplicate programmes merged into one over the API: the School of Postgraduate Studies sees the merges proposed (two older
 * codes of one name, one of them into its catalogue programme), a reader previews them and nothing changes, the School merges them
 * (the students on the kept programme, the history read back, only the latest merge open to undoing), a later record written with
 * an old code lands on the kept programme, the School is refused an undergraduate merge and the Bursary and the Academic Office any
 * merge, and the merges are undone in order to the record as it was. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = {"moaum.auth.hmac-secret=" + TestTokens.SECRET})
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"unchecked", "rawtypes"})
class ProgrammeMergeIT {

    static final String BASE = "/api/v1/records/programme-merge";

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

    /** free programme codes of the test's own, drawn where no programme sits */
    private List<String> freeCodes(int n) {
        return jdbc.sql("""
                SELECT 'C9' || lpad(g::text, 4, '0') FROM generate_series(8000, 9999) g
                 WHERE NOT EXISTS (SELECT 1 FROM ref.programme p WHERE p.code = 'C9' || lpad(g::text, 4, '0'))
                 ORDER BY random() LIMIT :n
                """).param("n", n).query(String.class).list();
    }

    private void programme(String code, String name, String dept, String category, String award) {
        it.db(() -> jdbc.sql("""
                INSERT INTO ref.programme (code, name, dept_code, faculty_code, min_score, archived, category, pg_award)
                SELECT :c, :n, d.code, d.faculty_code, 0, false, :k, :a FROM ref.department d WHERE d.code = :d
                """).param("c", code).param("n", name).param("d", dept).param("k", category).param("a", award).update());
    }

    private UUID pgStudent(String programme, String surname) {
        UUID id = UUID.randomUUID();
        it.db(() -> jdbc.sql("""
                INSERT INTO people.student (id, admission_no, matric_no, surname, other_names, programme_code, entry_mode, entry_session, entry_level, current_level, status, matriculated_at)
                VALUES (:id, :adm, :mat, :s, 'Invented', :p, 'POSTGRADUATE', '2020/2021', 800, 800, 'ACTIVE', now())
                """).param("id", id).param("adm", it.freeNumber("MOAUM/ADM/86/", 6)).param("mat", it.freeNumber("MOAUM/PGM/86/", 6))
                .param("s", surname).param("p", programme).update());
        return id;
    }

    private String on(UUID student) {
        return jdbc.sql("SELECT programme_code FROM people.student WHERE id = :id").param("id", student).query(String.class).single();
    }

    private static Map<String, Object> pair(String from, String to) {
        return Map.of("from", from, "to", to);
    }

    @Test
    void theSchoolMergesItsDuplicatesWithTheirStudentsAndUndoesThemInOrder() {
        String dept = jdbc.sql("SELECT code FROM ref.department WHERE faculty_code IS NOT NULL ORDER BY code LIMIT 1").query(String.class).single();
        List<String> codes = freeCodes(5);
        String x1 = codes.get(0), x2 = codes.get(1), c = codes.get(2), ug1 = codes.get(3), ug2 = codes.get(4);
        // a made-up subject of six letters, drawn afresh each run (a UUID's hex letters may be fewer than six)
        StringBuilder letters = new StringBuilder("Zzpm");
        java.util.Random random = new java.util.Random();
        for (int i = 0; i < 6; i++) letters.append((char) ('a' + random.nextInt(26)));
        String word = letters.toString();
        programme(x1, "MSC " + word.toUpperCase() + " STUDIES", dept, "POST GRADUATE", null);
        programme(x2, "MSC " + word.toUpperCase() + " STUDIES", dept, "POST GRADUATE", null);
        programme(c, "M.Sc. " + word + " Studies", dept, "POST GRADUATE", "MSC");
        programme(ug1, "B.Sc. " + word + " One", dept, "UNDER GRADUATE", null);
        programme(ug2, "B.Sc. " + word + " Two", dept, "UNDER GRADUATE", null);
        String surname = it.freeSurname("ZZPGM");
        UUID s1 = pgStudent(x1, surname), s2 = pgStudent(x1, surname), s3 = pgStudent(x2, surname);
        String school = ItSupport.token("pgschool");

        // the merges proposed: the two codes of one name into the one more students sit on, that one into the School's programme
        ResponseEntity<Map> sg = it.get(school, BASE + "/suggestions");
        assertThat(sg.getStatusCode().value()).as(String.valueOf(sg.getBody())).isEqualTo(200);
        List<Map<String, Object>> mine = ((List<Map<String, Object>>) sg.getBody().get("suggestions")).stream()
                .filter(s -> List.of(x1, x2, c).contains(s.get("from_code"))).toList();
        assertThat(mine).extracting(s -> s.get("kind") + ":" + s.get("from_code") + ">" + s.get("to_code"))
                .containsExactly("SAME_NAME:" + x2 + ">" + x1, "EXACT:" + x1 + ">" + c);
        assertThat((List<Map<String, Object>>) sg.getBody().get("programmes")).extracting(p -> p.get("code")).contains(x1, x2, c);

        // a reader sees what the merges would do, and nothing changes
        List<Map<String, Object>> pairs = List.of(pair(x2, x1), pair(x1, c));
        ResponseEntity<List> pv = it.callList(ItSupport.token("academic"), HttpMethod.POST, BASE + "/preview", Map.of("pairs", pairs));
        assertThat(pv.getStatusCode().value()).as(String.valueOf(pv.getBody())).isEqualTo(200);
        assertThat((List<Map<String, Object>>) pv.getBody()).extracting(e -> e.get("from") + ">" + e.get("to") + ":" + e.get("students"))
                .containsExactly(x2 + ">" + x1 + ":1", x1 + ">" + c + ":3");
        assertThat(List.of(on(s1), on(s2), on(s3))).containsExactly(x1, x1, x2);

        // the Academic Office and the Bursary do not merge; the School does not merge undergraduate programmes
        String reason = "The School of Postgraduate Studies list: one programme per name";
        assertThat(it.call(ItSupport.token("academic"), HttpMethod.POST, BASE, Map.of("pairs", pairs, "reason", reason)).getStatusCode().value()).isEqualTo(403);
        assertThat(it.call(ItSupport.token("bursar"), HttpMethod.POST, BASE, Map.of("pairs", pairs, "reason", reason)).getStatusCode().value()).isEqualTo(403);
        assertThat(it.get(ItSupport.token("bursar"), BASE + "/suggestions").getStatusCode().value()).isEqualTo(403);
        ResponseEntity<Map> ug = it.call(school, HttpMethod.POST, BASE, Map.of("pairs", List.of(pair(ug2, ug1)), "reason", reason));
        assertThat(ug.getStatusCode().value()).as(String.valueOf(ug.getBody())).isEqualTo(403);
        assertThat(ug.getBody()).containsEntry("code", "PROGRAMME_MERGE_OFFICE");
        assertThat(it.call(school, HttpMethod.POST, BASE, Map.of("pairs", pairs, "reason", "short")).getStatusCode().value()).isEqualTo(400);

        // the School merges them: every student on the kept programme, the old codes archived
        ResponseEntity<List> mg = it.callList(school, HttpMethod.POST, BASE, Map.of("pairs", pairs, "reason", reason));
        assertThat(mg.getStatusCode().value()).as(String.valueOf(mg.getBody())).isEqualTo(200);
        assertThat((List<Map<String, Object>>) mg.getBody()).extracting(e -> e.get("students")).containsExactly(1, 3);
        assertThat(List.of(on(s1), on(s2), on(s3))).containsExactly(c, c, c);
        assertThat(jdbc.sql("SELECT count(*) FROM ref.programme WHERE code IN (:a, :b) AND archived").param("a", x1).param("b", x2).query(Integer.class).single()).isEqualTo(2);
        // a student written later with an old code lands on the kept programme
        assertThat(on(pgStudent(x2, surname))).isEqualTo(c);
        // a code already merged is refused
        ResponseEntity<Map> again = it.call(school, HttpMethod.POST, BASE, Map.of("pairs", List.of(pair(x1, c)), "reason", reason));
        assertThat(again.getStatusCode().value()).isEqualTo(422);
        assertThat(again.getBody()).containsEntry("code", "PROGRAMME_MERGE_DONE");

        // the history: the latest first; only the later merge may be undone while the earlier one's kept code is merged away
        ResponseEntity<List> hs = it.getList(school, BASE + "/history");
        assertThat(hs.getStatusCode().value()).isEqualTo(200);
        List<Map<String, Object>> made = ((List<Map<String, Object>>) hs.getBody()).stream()
                .filter(m -> List.of(x1, x2).contains(m.get("from_code"))).toList();
        assertThat(made).extracting(m -> m.get("from_code") + ">" + m.get("to_code") + ":" + m.get("may_undo"))
                .containsExactly(x1 + ">" + c + ":true", x2 + ">" + x1 + ":false");
        String later = String.valueOf(made.get(0).get("id")), earlier = String.valueOf(made.get(1).get("id"));
        ResponseEntity<Map> early = it.call(school, HttpMethod.POST, BASE + "/" + earlier + "/undo", Map.of("reason", "the School asked for the merge to wait"));
        assertThat(early.getStatusCode().value()).isEqualTo(422);
        assertThat(early.getBody()).containsEntry("code", "PROGRAMME_MERGE_LATER");
        assertThat(it.call(ItSupport.token("bursar"), HttpMethod.POST, BASE + "/" + later + "/undo", Map.of("reason", "the School asked for the merge to wait")).getStatusCode().value()).isEqualTo(403);

        // undone in order: each student back on the code they were on, the codes in use again
        ResponseEntity<Map> u1 = it.call(school, HttpMethod.POST, BASE + "/" + later + "/undo", Map.of("reason", "the School asked for the merge to wait"));
        assertThat(u1.getStatusCode().value()).as(String.valueOf(u1.getBody())).isEqualTo(200);
        assertThat(u1.getBody()).containsEntry("students", 3);
        ResponseEntity<Map> u2 = it.call(school, HttpMethod.POST, BASE + "/" + earlier + "/undo", Map.of("reason", "the School asked for the merge to wait"));
        assertThat(u2.getStatusCode().value()).as(String.valueOf(u2.getBody())).isEqualTo(200);
        assertThat(List.of(on(s1), on(s2), on(s3))).containsExactly(x1, x1, x2);
        assertThat(jdbc.sql("SELECT count(*) FROM ref.programme WHERE code IN (:a, :b) AND archived").param("a", x1).param("b", x2).query(Integer.class).single()).isZero();
        ResponseEntity<Map> twice = it.call(school, HttpMethod.POST, BASE + "/" + later + "/undo", Map.of("reason", "the School asked for the merge to wait"));
        assertThat(twice.getStatusCode().value()).isEqualTo(422);
        assertThat(twice.getBody()).containsEntry("code", "PROGRAMME_MERGE_UNDONE");

        // the test's programmes put away, so they are proposed to no later run
        it.db(() -> jdbc.sql("UPDATE ref.programme SET archived = true WHERE code IN (:codes)").param("codes", codes).update());
    }
}
