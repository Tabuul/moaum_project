package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.List;
import java.util.Map;
import java.util.Random;
import java.util.UUID;

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
 * V640: the Database Operations office and examination readiness over the API. A four-year programme of the test's own with its
 * school fees stated for 200 Level, in a session of the test's own, and four students: paid and registered (one course), paid and
 * not registered, registered and not paid, neither. A Database Operator held over the University reads the readiness by programme,
 * opens each figure's students, the course's students and the department's courses, issues the six-report package under one
 * DBO/EXAM reference, queries the register and the payments through the query engine (a field it does not offer, an operator it
 * does not know and an unbound value refused or bound, never run), saves a query and shares it with ICT, who reads it and cannot
 * change it; ICT reads the readiness but not individual payments; an Examinations Officer reads the readiness without amounts; a
 * lecturer reads none of it; an operator held to another department is refused this programme and reads nothing of it; the
 * operator writes no payment and no graduation; data quality finds the shared JAMB number; the query log holds every act.
 * Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class DatabaseOperationsIT {

    private static final String R = "/api/v1/reports/exam-readiness";
    private static final String D = "/api/v1/dbops";

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    ItSupport it;
    String session;
    /** a programme of the run's own, so no earlier run's students are counted with this one's */
    String PROGRAMME;

    /** the fee line the test states is ended with it, so no later test's student reads it */
    @AfterEach
    void clean() {
        if (it != null && session != null) {
            it.db(() -> jdbc.sql("DELETE FROM finance.fee_schedule WHERE session = :s AND programme_code = :p").param("s", session).param("p", PROGRAMME).update());
        }
    }

    @Test
    void readinessQueriesAndReportsAreTheOperatorsAndNeverWriteAnything() {
        it = new ItSupport(port, jdbc, transactions);
        int y = it.freeYear(4300, 4390, 0, 1);
        session = y + "/" + (y + 1);
        it.session(session, y);
        PROGRAMME = jdbc.sql("SELECT 'C' || x FROM generate_series(96400, 96999) x WHERE NOT EXISTS (SELECT 1 FROM ref.programme p WHERE p.code = 'C' || x) ORDER BY random() LIMIT 1")
                .query(String.class).single();
        String yy = String.format("%02d", y % 100);
        int n = 1000 + new Random().nextInt(8999);
        String dept = it.db(() -> {
            String[] df = jdbc.sql("""
                    SELECT p.dept_code || ',' || p.faculty_code FROM ref.programme p JOIN ref.faculty f ON f.code = p.faculty_code
                     WHERE p.category = 'UNDER GRADUATE' AND NOT p.archived AND coalesce(f.college_code, '') <> 'CHS' ORDER BY p.code LIMIT 1
                    """).query(String.class).single().split(",");
            jdbc.sql("""
                    INSERT INTO ref.programme (code, name, dept_code, faculty_code, category, min_score, final_level, duration_years)
                    VALUES (:c, 'B.Sc. Database Operations Test', :d, :f, 'UNDER GRADUATE', 0, 400, 4)
                    ON CONFLICT (code) DO UPDATE SET archived = false
                    """).param("c", PROGRAMME).param("d", df[0]).param("f", df[1]).update();
            return df[0];
        });
        UUID both = it.student("ZZDBOBOTH" + n, PROGRAMME, "MOAUM/ADM/" + yy + "/91" + n, "MOAUM/DBO/" + yy + "/1" + n, 200);
        UUID paidOnly = it.student("ZZDBOPAID" + n, PROGRAMME, "MOAUM/ADM/" + yy + "/92" + n, "MOAUM/DBO/" + yy + "/2" + n, 200);
        UUID regOnly = it.student("ZZDBOREG" + n, PROGRAMME, "MOAUM/ADM/" + yy + "/93" + n, "MOAUM/DBO/" + yy + "/3" + n, 200);
        UUID neither = it.student("ZZDBONONE" + n, PROGRAMME, "MOAUM/ADM/" + yy + "/94" + n, "MOAUM/DBO/" + yy + "/4" + n, 200);
        String course = "ZDB " + (100 + n % 800);
        it.db(() -> {
            jdbc.sql("UPDATE people.student SET entry_session = :e, jamb_reg_no = CASE WHEN id IN (:a, :b) THEN :j END WHERE id IN (:a, :b, :c, :d)")
                    .param("e", (y - 1) + "/" + y).param("j", y + "DBO" + n + "AB").param("a", both).param("b", paidOnly).param("c", regOnly).param("d", neither).update();
            jdbc.sql("INSERT INTO catalogue.course (code, title, units, semester, level, dept_code, kind, state) VALUES (:c, 'Readiness Test Course', 3, 1, 200, :d, 'Core', 'LIVE') ON CONFLICT (code) DO NOTHING")
                    .param("c", course).param("d", dept).update();
            jdbc.sql("INSERT INTO catalogue.course_offer (course_code, programme_code, level, basis) VALUES (:c, :p, 200, 'Core') ON CONFLICT DO NOTHING")
                    .param("c", course).param("p", PROGRAMME).update();
            UUID offering = UUID.randomUUID();
            jdbc.sql("INSERT INTO catalogue.offering (id, course_code, session, semester) VALUES (:o, :c, :s, 1)").param("o", offering).param("c", course).param("s", session).update();
            jdbc.sql("INSERT INTO finance.fee_schedule (session, item, amount, level, programme_code) VALUES (:s, 'School fees', 100000, 200, :p)")
                    .param("s", session).param("p", PROGRAMME).update();
            for (UUID st : List.of(both, regOnly)) {
                UUID reg = UUID.randomUUID();
                jdbc.sql("INSERT INTO registration.course_registration (id, student_id, session, semester, level, status, submitted_at) VALUES (:r, :st, :s, 1, 200, 'SUBMITTED', now())")
                        .param("r", reg).param("st", st).param("s", session).update();
                jdbc.sql("INSERT INTO registration.entry (registration_id, offering_id, units, entry_type, status) VALUES (:r, :o, 3, 'CURRENT', 'REGISTERED')")
                        .param("r", reg).param("o", offering).update();
            }
            for (UUID st : List.of(both, paidOnly)) {
                String ref = jdbc.sql("SELECT finance.new_reference(:s, :ses, 100000, NULL)").param("s", st).param("ses", session).query(String.class).single();
                jdbc.sql("SELECT finance.confirm_payment(:r, 'BANK_BRANCH', 'teller for the database operations test')").param("r", ref).query(String.class).single();
            }
            return 0;
        });

        String operator = it.officer("dbops", "institution", "University");
        String ict = ItSupport.token("ict");
        String q = "?session=" + session + "&semester=1&prog=" + PROGRAMME;

        // the readiness by programme: four students, one paid and registered, one paid not registered, two not paid (one registered)
        ResponseEntity<Map> summary = it.get(operator, R + "/summary" + q + "&by=programme");
        assertThat(summary.getStatusCode().value()).as(String.valueOf(summary.getBody())).isEqualTo(200);
        Map<String, Object> total = (Map<String, Object>) summary.getBody().get("total");
        assertThat(total).containsEntry("total", 4).containsEntry("paid_registered", 1).containsEntry("paid_not_registered", 1)
                .containsEntry("not_paid", 2).containsEntry("not_paid_registered", 1).containsEntry("exam_cards", 1);
        // each figure opens its students
        assertThat(ids(it.get(operator, R + "/students" + q + "&category=PAID_NOT_REGISTERED"))).containsExactly(paidOnly.toString());
        assertThat(ids(it.get(operator, R + "/students" + q + "&category=NOT_PAID_REGISTERED"))).containsExactly(regOnly.toString());
        assertThat(ids(it.get(operator, R + "/students" + q + "&category=PAID_REGISTERED"))).containsExactly(both.toString());
        Map<String, Object> row = ((List<Map<String, Object>>) it.get(operator, R + "/students" + q + "&category=PAID_REGISTERED").getBody().get("rows")).get(0);
        assertThat(row).containsEntry("exam_card", true).containsEntry("courses", 1).containsEntry("units", 3).containsEntry("registration_status", "SUBMITTED");
        assertThat(((Number) row.get("paid_amount")).intValue()).isEqualTo(100000);
        // the course: registered, expected by the structure; the department's courses
        ResponseEntity<Map> byCourse = it.get(operator, R + "/summary" + q + "&course=" + course + "&by=all");
        assertThat(((Map<String, Object>) byCourse.getBody().get("total"))).containsEntry("paid_registered", 1).containsEntry("paid_not_registered", 1).containsEntry("not_paid", 2);
        ResponseEntity<Map> courses = it.get(operator, R + "/courses?session=" + session + "&semester=1&prog=" + PROGRAMME + "&cdept=" + dept);
        assertThat(courses.getStatusCode().value()).as(String.valueOf(courses.getBody())).isEqualTo(200);
        assertThat((List<Map<String, Object>>) courses.getBody().get("rows")).anySatisfy(c -> assertThat(c)
                .containsEntry("course_code", course).containsEntry("registered", 2).containsEntry("registered_paid", 1).containsEntry("expected_not_registered_paid", 1));

        // the package: six reports under one reference
        ResponseEntity<Map> pack = it.call(ict, HttpMethod.POST, R + "/package", Map.of("session", session, "semester", 1, "prog", PROGRAMME));
        assertThat(pack.getStatusCode().value()).as(String.valueOf(pack.getBody())).isEqualTo(200);
        String ref = String.valueOf(pack.getBody().get("reference"));
        assertThat(ref).matches("DBO/EXAM/[0-9]{4}/[0-9]{6}");
        assertThat((List<String>) pack.getBody().get("parts")).hasSize(6);
        assertThat(jdbc.sql("SELECT row_count FROM reporting.official_report WHERE reference = :r").param("r", ref).query(Integer.class).single()).isEqualTo(4);

        // ICT reads the readiness, not individual payments; an Examinations Officer reads it without amounts; a lecturer reads none
        assertThat(it.get(ict, R + "/summary" + q).getStatusCode().value()).isEqualTo(200);
        String examsOfficer = it.officer("exams", "department", dept);
        Map<String, Object> noAmount = ((List<Map<String, Object>>) it.get(examsOfficer, R + "/students" + q + "&category=PAID_REGISTERED").getBody().get("rows")).get(0);
        assertThat(noAmount.get("paid_amount")).isNull();
        assertThat(noAmount).containsEntry("readiness", "PAID_REGISTERED");
        assertThat(it.get(ItSupport.token("lecturer"), R + "/summary" + q).getStatusCode().value()).isEqualTo(403);

        // the query engine: the register, a grouping, the payments; what it does not offer is refused, a value is always bound
        Map<String, Object> studentsDef = Map.of("source", "STUDENTS", "filters", List.of(Map.of("field", "programme", "op", "eq", "value", PROGRAMME)));
        ResponseEntity<Map> run = it.call(operator, HttpMethod.POST, D + "/query/run", Map.of("definition", studentsDef));
        assertThat(run.getStatusCode().value()).as(String.valueOf(run.getBody())).isEqualTo(200);
        assertThat(run.getBody()).containsEntry("total", 4);
        ResponseEntity<Map> grouped = it.call(operator, HttpMethod.POST, D + "/query/run",
                Map.of("definition", Map.of("source", "STUDENTS", "filters", studentsDef.get("filters"), "group", Map.of("field", "status"))));
        assertThat((List<Map<String, Object>>) grouped.getBody().get("rows")).anySatisfy(g -> assertThat(g).containsEntry("key", "ACTIVE").containsEntry("count", 4));
        Map<String, Object> payDef = Map.of("source", "PAYMENTS", "filters", List.of(Map.of("field", "programme", "op", "eq", "value", PROGRAMME),
                Map.of("field", "payment_status", "op", "eq", "value", "PAID")));
        ResponseEntity<Map> pays = it.call(operator, HttpMethod.POST, D + "/query/run", Map.of("definition", payDef));
        assertThat(pays.getBody()).containsEntry("total", 2);
        assertThat(it.call(ict, HttpMethod.POST, D + "/query/run", Map.of("definition", payDef)).getBody()).containsEntry("code", "QUERY_SOURCE_OFFICE");
        assertThat(it.call(operator, HttpMethod.POST, D + "/query/run", Map.of("definition",
                Map.of("source", "STUDENTS", "filters", List.of(Map.of("field", "surname; DROP TABLE people.student", "op", "eq", "value", "x"))))).getBody())
                .containsEntry("code", "QUERY_FIELD");
        assertThat(it.call(operator, HttpMethod.POST, D + "/query/run", Map.of("definition",
                Map.of("source", "STUDENTS", "filters", List.of(Map.of("field", "name", "op", "regex", "value", "x"))))).getBody())
                .containsEntry("code", "QUERY_OPERATOR");
        ResponseEntity<Map> quoted = it.call(operator, HttpMethod.POST, D + "/query/run", Map.of("definition",
                Map.of("source", "STUDENTS", "filters", List.of(Map.of("field", "name", "op", "contains", "value", "x' OR '1'='1")))));
        assertThat(quoted.getStatusCode().value()).isEqualTo(200);
        assertThat(quoted.getBody()).containsEntry("total", 0);

        // saved, shared with ICT, read by ICT, changed by its owner alone
        ResponseEntity<Map> saved = it.call(operator, HttpMethod.POST, D + "/saved",
                Map.of("name", "Database operations test " + n, "kind", "QUERY", "definition", studentsDef, "sharedOffices", List.of("ict")));
        assertThat(saved.getStatusCode().value()).as(String.valueOf(saved.getBody())).isEqualTo(200);
        String savedId = String.valueOf(saved.getBody().get("id"));
        assertThat((List<Map<String, Object>>) it.getList(ict, D + "/saved").getBody()).anySatisfy(s -> assertThat(s).containsEntry("id", savedId).containsEntry("mine", false));
        assertThat(it.call(ict, HttpMethod.PUT, D + "/saved/" + savedId, Map.of("name", "Taken over", "definition", studentsDef)).getBody())
                .containsEntry("code", "SAVED_QUERY_OWNER");

        // an operator held to another department is refused this programme and reads nothing of it
        String otherDept = jdbc.sql("SELECT code FROM ref.department WHERE code <> :d AND ended_on IS NULL ORDER BY code LIMIT 1").param("d", dept).query(String.class).single();
        String scoped = it.officer("dbops", "department", otherDept);
        assertThat(it.get(scoped, R + "/summary" + q).getStatusCode().value()).isEqualTo(422);
        ResponseEntity<Map> scopedRun = it.call(scoped, HttpMethod.POST, D + "/query/run", Map.of("definition", studentsDef));
        assertThat(scopedRun.getBody()).containsEntry("total", 0);

        // the operator writes nothing: no graduation batch, no payment confirmation
        assertThat(it.call(operator, HttpMethod.POST, "/api/v1/graduation/reconciliation/batches", Map.of("description", "Operator tries", "studentIds", List.of(both.toString())))
                .getStatusCode().value()).isEqualTo(403);
        assertThat(it.call(operator, HttpMethod.POST, "/api/v1/payments/confirm", Map.of("reference", "X")).getStatusCode().value()).isIn(403, 404, 405);

        // data quality: the shared JAMB number; the home; Student Query
        ResponseEntity<Map> dq = it.get(operator, D + "/data-quality/DUPLICATE_JAMB?prog=" + PROGRAMME + "&session=" + session + "&semester=1");
        assertThat(dq.getStatusCode().value()).as(String.valueOf(dq.getBody())).isEqualTo(200);
        assertThat(dq.getBody()).containsEntry("total", 2);
        assertThat(it.get(operator, D + "/home").getStatusCode().value()).isEqualTo(200);
        assertThat(it.get(operator, "/api/v1/stats/students/query?prog=" + PROGRAMME).getStatusCode().value()).isEqualTo(200);

        // the query log: the runs, the save and share, the package issued
        UUID operatorId = jdbc.sql("SELECT person_id FROM iam.office_assignment WHERE office_code = 'dbops' AND scope_kind = 'institution' ORDER BY valid_from DESC LIMIT 1")
                .query(UUID.class).single();
        List<String> actions = jdbc.sql("SELECT DISTINCT action FROM reporting.query_log WHERE actor_id = :a").param("a", operatorId).query(String.class).list();
        assertThat(actions).contains("RUN", "SAVE");
        assertThat(jdbc.sql("SELECT count(*) FROM reporting.query_log WHERE action = 'ISSUE' AND reference = :r").param("r", ref).query(Long.class).single()).isEqualTo(1L);
    }

    private static List<String> ids(ResponseEntity<Map> r) {
        assertThat(r.getStatusCode().value()).as(String.valueOf(r.getBody())).isEqualTo(200);
        return ((List<Map<String, Object>>) r.getBody().get("rows")).stream().map(x -> String.valueOf(x.get("student_id"))).toList();
    }
}
