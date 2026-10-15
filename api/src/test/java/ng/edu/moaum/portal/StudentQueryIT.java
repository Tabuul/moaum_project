package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.List;
import java.util.Map;
import java.util.Random;
import java.util.Set;
import java.util.UUID;
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
 * The Student Query (V469): an undergraduate and a postgraduate of the same department (B.Sc. and M.Sc. Computer
 * Science), a CCE student, a student whose postgraduate entry mode sits on an undergraduate programme, an Accounting
 * undergraduate and a JUPEB learner. Each is its own programme type, from structured fields; the conflicting record is
 * no type until the Academic Office decides; the figures by type agree with the list; the Dean, the Head, the School of
 * Postgraduate Studies and the CCE and JUPEB offices see only their own, whatever the request asks; the fee filter is
 * for the offices that read fees; offices outside the readers are refused. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class StudentQueryIT {

    static final String SESSION = "2093/2094";

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    ItSupport it;
    String registrar = ItSupport.token("registrar");
    String academic = ItSupport.token("academic");

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
        it.session(SESSION, 2093);
    }

    private UUID student(String surname, String programme, String entryMode, String studyMode, int level, String admissionNo, String matricNo) {
        return it.db(() -> {
            UUID id = UUID.randomUUID();
            jdbc.sql("""
                    INSERT INTO people.student (id, admission_no, matric_no, surname, other_names, programme_code, entry_mode, study_mode,
                                                entry_session, entry_level, current_level, status, matriculated_at)
                    VALUES (:id, :adm, :mat, :s, 'Invented', :p, :e, :m, '2090/2091', :l, :l,
                            CASE WHEN :mat::text IS NULL THEN 'ADMITTED' ELSE 'ACTIVE' END, CASE WHEN :mat::text IS NULL THEN NULL ELSE now() END)
                    """).param("id", id).param("adm", admissionNo).param("mat", matricNo).param("s", surname).param("p", programme)
                    .param("e", entryMode).param("m", studyMode).param("l", level).update();
            return id;
        });
    }

    private List<Map<String, Object>> rows(String token, String query) {
        ResponseEntity<Map> r = it.get(token, "/api/v1/stats/students/query?size=500&" + query);
        assertThat(r.getStatusCode().value()).as(query + " → " + r.getBody()).isEqualTo(200);
        return (List<Map<String, Object>>) r.getBody().get("rows");
    }

    private Set<String> learners(String token, String query) {
        return rows(token, query).stream().map(r -> String.valueOf(r.get("learner_id"))).collect(Collectors.toSet());
    }

    @Test
    void everyLearnerIsTheirOwnTypeAndEveryScopeHolds() {
        int n = new Random().nextInt(8000) + 1000;
        String tag = "ZZSQ" + n;
        UUID ug = student(tag + "A", "C00023", "UTME", "FULL_TIME", 400, "MOAUM/ADM/93/" + (200000 + n * 6), "MOAUM/MTC/93/" + (20000 + n));
        UUID pg = student(tag + "B", "C90002", "POSTGRADUATE", "FULL_TIME", 800, "MOAUM/ADM/93/" + (200000 + n * 6 + 1), null);
        UUID cce = student(tag + "C", "C00023", "CCE", "PART_TIME", 300, "MOAUM/ADM/93/" + (200000 + n * 6 + 2), null);
        UUID odd = student(tag + "D", "C00023", "POSTGRADUATE", "FULL_TIME", 400, "MOAUM/ADM/93/" + (200000 + n * 6 + 3), null);
        UUID acc = student(tag + "E", "C00019", "UTME", "FULL_TIME", 200, "MOAUM/ADM/93/" + (200000 + n * 6 + 4), null);
        UUID jupeb = it.db(() -> {
            UUID account = jdbc.sql("INSERT INTO jupeb.account (email, password_hash) VALUES (:e, '$2a$12$abcdefghijklmnopqrstuuabcdefghijklmnopqrstuvwxyz12345') RETURNING id")
                    .param("e", "zz.sq" + n + "@example.com").query(UUID.class).single();
            return jdbc.sql("""
                    INSERT INTO jupeb.application (account_id, session, application_no, surname, first_name, email, state)
                    VALUES (:a, :s, :no, :sn, 'Invented', :e, 'STUDENT') RETURNING id
                    """).param("a", account).param("s", SESSION).param("no", "JUPEB/APP/2093/" + (300000 + n)).param("sn", tag + "J")
                    .param("e", "zz.sq" + n + "@example.com").query(UUID.class).single();
        });

        // all types: every learner, each with its programme type; the conflicting record is no type and says why
        List<Map<String, Object>> all = rows(registrar, "q=" + tag);
        assertThat(all).hasSize(6);
        Map<String, Map<String, Object>> byId = all.stream().collect(Collectors.toMap(r -> String.valueOf(r.get("learner_id")), r -> r));
        assertThat(byId.get(ug.toString()).get("programme_type")).isEqualTo("UNDERGRADUATE");
        assertThat(byId.get(ug.toString()).get("admission_route")).isEqualTo("UTME");
        assertThat(byId.get(ug.toString()).get("centre_code")).isEqualTo("MAIN_CAMPUS");
        assertThat(byId.get(pg.toString()).get("programme_type")).isEqualTo("POSTGRADUATE");
        assertThat(byId.get(pg.toString()).get("department")).isEqualTo(byId.get(ug.toString()).get("department"));
        assertThat(byId.get(cce.toString()).get("programme_type")).isEqualTo("CCE");
        assertThat(byId.get(cce.toString()).get("study_mode")).isEqualTo("PART_TIME");
        assertThat(byId.get(cce.toString()).get("centre_code")).isEqualTo("CCE");
        assertThat(byId.get(odd.toString()).get("programme_type")).isNull();
        assertThat(byId.get(odd.toString()).get("classification_status")).isEqualTo("REQUIRES_CLASSIFICATION");
        assertThat(byId.get(odd.toString()).get("proposed_type")).isEqualTo("POSTGRADUATE");
        assertThat(byId.get(jupeb.toString()).get("programme_type")).isEqualTo("JUPEB");
        assertThat(byId.get(jupeb.toString()).get("faculty")).isNull();
        assertThat(byId.get(jupeb.toString()).get("status")).isEqualTo("ACTIVE");
        // names A–Z
        assertThat(all.stream().map(r -> String.valueOf(r.get("surname"))).toList())
                .containsExactly(tag + "A", tag + "B", tag + "C", tag + "D", tag + "E", tag + "J");

        // one type at a time: the undergraduate and the postgraduate of the same department are never confused
        assertThat(learners(registrar, "type=UNDERGRADUATE&q=" + tag)).containsExactlyInAnyOrder(ug.toString(), acc.toString());
        assertThat(learners(registrar, "type=POSTGRADUATE&q=" + tag)).containsExactly(pg.toString());
        assertThat(learners(registrar, "type=CCE&q=" + tag)).containsExactly(cce.toString());
        assertThat(learners(registrar, "type=JUPEB&q=" + tag)).containsExactly(jupeb.toString());
        assertThat(learners(registrar, "classification=REQUIRES_CLASSIFICATION&q=" + tag)).containsExactly(odd.toString());
        // "all active 400-level undergraduates in Science"
        assertThat(learners(registrar, "type=UNDERGRADUATE&fac=SC&level=400&status=ACTIVE&q=" + tag)).containsExactly(ug.toString());
        assertThat(learners(registrar, "matriculated=NO&q=" + tag)).doesNotContain(ug.toString()).contains(pg.toString());
        // the search finds a learner by matriculation number and by application number
        assertThat(learners(registrar, "q=MOAUM/MTC/93/" + (20000 + n))).containsExactly(ug.toString());
        assertThat(learners(registrar, "q=JUPEB/APP/2093/" + (300000 + n))).containsExactly(jupeb.toString());

        // the cards: the same filters counted by type, the conflicting record apart
        Map<String, Object> summary = it.get(registrar, "/api/v1/stats/students/query/summary?q=" + tag).getBody();
        Map<String, Number> counts = ((List<Map<String, Object>>) summary.get("types")).stream()
                .collect(Collectors.toMap(t -> String.valueOf(t.get("code")), t -> (Number) t.get("count")));
        assertThat(counts.get("UNDERGRADUATE").intValue()).isEqualTo(2);
        assertThat(counts.get("POSTGRADUATE").intValue()).isEqualTo(1);
        assertThat(counts.get("CCE").intValue()).isEqualTo(1);
        assertThat(counts.get("JUPEB").intValue()).isEqualTo(1);
        assertThat(((Number) summary.get("requiresClassification")).intValue()).isEqualTo(1);
        assertThat(((Number) summary.get("total")).intValue()).isEqualTo(6);

        // the Dean: their faculty, whatever the request asks
        String deanSc = it.officer("dean", "faculty", "SC");
        assertThat(learners(deanSc, "q=" + tag)).containsExactlyInAnyOrder(ug.toString(), pg.toString(), cce.toString(), odd.toString());
        assertThat(learners(deanSc, "fac=MS&q=" + tag)).isEmpty();
        String deanMs = it.officer("dean", "faculty", "MS");
        assertThat(learners(deanMs, "q=" + tag)).containsExactly(acc.toString());
        // the Head: their department
        assertThat(learners(it.officer("hod", "department", "MTC"), "q=" + tag)).containsExactlyInAnyOrder(ug.toString(), pg.toString(), cce.toString(), odd.toString());
        assertThat(learners(it.officer("hod", "department", "ACC"), "type=UNDERGRADUATE&q=" + tag)).containsExactly(acc.toString());
        // the offices of one type: their type only, a request for another returns nothing
        String pgschool = ItSupport.token("pgschool");
        assertThat(learners(pgschool, "q=" + tag)).containsExactly(pg.toString());
        assertThat(learners(pgschool, "type=UNDERGRADUATE&q=" + tag)).isEmpty();
        assertThat(((Map<String, Object>) it.get(pgschool, "/api/v1/stats/students/query/summary?q=" + tag).getBody().get("scope")).get("programmeType")).isEqualTo("POSTGRADUATE");
        assertThat(learners(ItSupport.token("cce"), "q=" + tag)).containsExactly(cce.toString());
        assertThat(learners(ItSupport.token("jupeb"), "q=" + tag)).containsExactly(jupeb.toString());
        assertThat(learners(ItSupport.token("sandwich"), "q=" + tag)).isEmpty();
        assertThat(learners(ItSupport.token("prelim"), "q=" + tag)).isEmpty();
        // the options follow the type and the scope: the Dean of Management Sciences is offered Accounting, not Computer Science
        List<Map<String, Object>> progs = (List<Map<String, Object>>) it.get(deanMs, "/api/v1/stats/students/query/options?type=UNDERGRADUATE").getBody().get("programmes");
        assertThat(progs).extracting(p -> p.get("faculty_code")).containsOnly("MS");

        // the fee filter is for the offices that read fees; offices outside the readers are refused
        assertThat(it.get(ItSupport.token("cce"), "/api/v1/stats/students/query?fees=OUTSTANDING&q=" + tag).getStatusCode().value()).isEqualTo(403);
        assertThat(it.get(registrar, "/api/v1/stats/students/query?fees=OUTSTANDING&session=" + SESSION + "&q=" + tag).getStatusCode().value()).isEqualTo(200);
        assertThat(it.get(ItSupport.token("housing"), "/api/v1/stats/students/query?q=" + tag).getStatusCode().value()).isEqualTo(403);
        assertThat(it.get(ItSupport.token("ictagent"), "/api/v1/stats/students/query/summary").getStatusCode().value()).isEqualTo(403);

        // the conflicting record: in the review list, decided by the Academic Office with a reason, never by a Head
        List<Map<String, Object>> review = (List<Map<String, Object>>) it.get(academic, "/api/v1/student/classification/review?q=" + tag).getBody().get("rows");
        assertThat(review).extracting(r -> String.valueOf(r.get("learner_id"))).containsExactly(odd.toString());
        Map<String, Object> decision = Map.of("programmeType", "UNDERGRADUATE", "admissionRoute", "UTME", "reason", "The admission letter names UTME");
        assertThat(it.call(it.officer("hod", "department", "MTC"), HttpMethod.POST, "/api/v1/student/classification/" + odd, decision).getStatusCode().value()).isEqualTo(403);
        assertThat(it.call(academic, HttpMethod.POST, "/api/v1/student/classification/" + odd, Map.of("programmeType", "UNDERGRADUATE")).getStatusCode().value()).isEqualTo(400);
        ResponseEntity<Map> decided = it.call(academic, HttpMethod.POST, "/api/v1/student/classification/" + odd, decision);
        assertThat(decided.getStatusCode().value()).as(String.valueOf(decided.getBody())).isEqualTo(200);
        assertThat(decided.getBody().get("programme_type")).isEqualTo("UNDERGRADUATE");
        assertThat(decided.getBody().get("type_source")).isEqualTo("DECISION");
        assertThat((List<Map<String, Object>>) decided.getBody().get("history")).extracting(h -> h.get("kind")).containsExactly("CORRECTION");
        assertThat(learners(registrar, "type=UNDERGRADUATE&q=" + tag)).containsExactlyInAnyOrder(ug.toString(), acc.toString(), odd.toString());

        // the record shows its classification, in the record's own scope
        Map<String, Object> mine = it.get(registrar, "/api/v1/student/students/" + pg + "/classification").getBody();
        assertThat(mine.get("programme_type")).isEqualTo("POSTGRADUATE");
        assertThat(mine.get("admission_route")).isEqualTo("PG_APPLICATION");
        assertThat(it.get(it.officer("hod", "department", "ACC"), "/api/v1/student/students/" + pg + "/classification").getStatusCode().value()).isEqualTo(403);

        // the student statistics read the same classification
        Map<String, Object> stats = it.get(registrar, "/api/v1/stats/students/summary?session=" + SESSION + "&type=CCE&q=" + tag).getBody();
        assertThat(((Map<String, Object>) stats.get("totals")).get("total")).isEqualTo(1);
        List<Map<String, Object>> byType = (List<Map<String, Object>>) it.get(registrar, "/api/v1/stats/students/summary?session=" + SESSION + "&q=" + tag).getBody().get("byProgrammeType");
        assertThat(byType).extracting(t -> t.get("programme_type")).contains("UNDERGRADUATE", "POSTGRADUATE", "CCE");
    }
}
