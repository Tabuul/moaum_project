package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.ThreadLocalRandom;

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
 * V715 through the API: postgraduate record management. Made-up postgraduate programmes of a made-up session, an applicant made
 * through the apply door's own function, a postgraduate student and an undergraduate. The School finds the applicant in the one
 * search (a Head of Department is refused the pages), opens the record, corrects the surname and the programme in one save — an
 * unconfirmed critical change refused, the old reading refused afterwards — replaces the previous degrees, and reads the history.
 * The Director of ICT opens the postgraduate student on the student edit page with the ordinary permissions and corrects a name;
 * the School is refused the undergraduate there; the latest corrections list both. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class PgRecordEditIT {

    private static final String R = "/api/v1/pg/records";

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

    private Map<String, Object> ok(ResponseEntity<Map> r) {
        assertThat(r.getStatusCode().value()).as(String.valueOf(r.getBody())).isEqualTo(200);
        return r.getBody();
    }

    private String freeCode() {
        return jdbc.sql("""
                SELECT 'C9' || lpad(g::text, 4, '0') FROM generate_series(8000, 9999) g
                 WHERE NOT EXISTS (SELECT 1 FROM ref.programme p WHERE p.code = 'C9' || lpad(g::text, 4, '0')) ORDER BY random() LIMIT 1
                """).query(String.class).single();
    }

    @Test
    void theSchoolAndTheDirectorOfIctCorrectPostgraduateRecordsFromOnePlace() {
        int y = it.freeYear(7600, 7790, 0, 0);
        String session = y + "/" + (y + 1);
        it.session(session, y);
        String msc = freeCode();
        it.db(() -> jdbc.sql("""
                INSERT INTO ref.programme (code, name, dept_code, faculty_code, min_score, archived, category, pg_award)
                SELECT :c, :n, d.code, d.faculty_code, 0, false, 'POST GRADUATE', 'MSC' FROM ref.department d ORDER BY d.code LIMIT 1
                """).param("c", msc).param("n", "M.Sc. Record Edit Check " + y).update());
        String phd = freeCode();
        it.db(() -> jdbc.sql("""
                INSERT INTO ref.programme (code, name, dept_code, faculty_code, min_score, archived, category, pg_award, pg_research)
                SELECT :c, :n, d.code, d.faculty_code, 0, false, 'POST GRADUATE', 'PHD', true FROM ref.department d ORDER BY d.code LIMIT 1
                """).param("c", phd).param("n", "Ph.D. Record Edit Check " + y).update());
        String dept = jdbc.sql("SELECT dept_code FROM ref.programme WHERE code = :c").param("c", msc).query(String.class).single();
        String school = it.officer("pgschool", "institution", "University");
        String ict = it.officer("ict", "institution", "University");
        String hod = it.officer("hod", "department", dept);

        // an applicant through the apply door's own function, as the public form makes one
        ItSupport.PgPerson p = ItSupport.pgPerson("ZZRECEDIT");
        String email = "zzrecedit" + y + ThreadLocalRandom.current().nextInt(1000, 9999) + "@example.test";
        UUID app = it.db(() -> UUID.fromString(jdbc.sql("""
                SELECT (admissions.pg_apply(jsonb_build_object('session', :s, 'programme', :p, 'surname', :sn, 'otherNames', :on, 'dob', :dob, 'phone', :ph, 'email', :em,
                                                                'passwordHash', crypt('x', gen_salt('bf', 12))))).application_id::text
                """).param("s", session).param("p", msc).param("sn", p.surname()).param("on", p.otherNames()).param("dob", p.dob()).param("ph", p.phone()).param("em", email)
                .query(String.class).single()));
        String appNo = jdbc.sql("SELECT application_no FROM admissions.pg_application WHERE id = :a").param("a", app).query(String.class).single();

        // the one search: the School finds the applicant by number and by e-mail; a Head of Department is refused the pages
        Map<String, Object> found = ok(it.get(school, u -> u.path(R + "/search").queryParam("q", appNo).build()));
        assertThat((List<Map<String, Object>>) found.get("rows")).extracting(r -> r.get("kind")).containsExactly("APPLICANT");
        assertThat((List<Map<String, Object>>) ok(it.get(school, u -> u.path(R + "/search").queryParam("q", email).build())).get("rows")).hasSize(1);
        assertThat(it.get(hod, u -> u.path(R + "/search").queryParam("q", appNo).build()).getStatusCode().value()).isEqualTo(403);

        // the record opened: the version read, the permissions; the surname and the programme corrected in one save
        Map<String, Object> page = ok(it.get(school, R + "/applications/" + app + "/edit"));
        String version = String.valueOf(page.get("version"));
        assertThat((List<String>) page.get("permissions")).contains("EDIT_PG_APPLICANT", "EDIT_PG_PROGRAMME", "VIEW_PG_CHANGE_HISTORY").doesNotContain("EDIT_PG_FINANCIAL_RECORD");
        String reason = "The degree certificate presented at screening names the applicant so; the PhD was applied for";
        Map<String, Object> changes = Map.of("surname", "Zzrecedited", "programme_code", phd);
        ResponseEntity<Map> unconfirmed = it.call(school, HttpMethod.PUT, R + "/applications/" + app + "/edit", Map.of("changes", changes, "reason", reason, "version", version));
        assertThat(unconfirmed.getStatusCode().value()).isEqualTo(422);
        assertThat(unconfirmed.getBody().get("code")).isEqualTo("PG_EDIT_CONFIRM");
        ResponseEntity<Map> thin = it.call(school, HttpMethod.PUT, R + "/applications/" + app + "/edit", Map.of("changes", changes, "reason", "fix", "version", version, "confirmCritical", true));
        assertThat(thin.getStatusCode().value()).isEqualTo(422);
        assertThat(thin.getBody().get("code")).isEqualTo("PG_EDIT_REASON");
        Map<String, Object> saved = ok(it.call(school, HttpMethod.PUT, R + "/applications/" + app + "/edit", Map.of("changes", changes, "reason", reason, "version", version, "confirmCritical", true)));
        assertThat(((Number) saved.get("changed")).intValue()).isEqualTo(2);
        Map<String, Object> row = jdbc.sql("SELECT p.surname, a.programme_code, a.entry_level FROM admissions.pg_application a JOIN admissions.pg_applicant p ON p.id = a.applicant_id WHERE a.id = :a")
                .param("a", app).query().singleRow();
        assertThat(row).containsEntry("surname", "ZZRECEDITED").containsEntry("programme_code", phd).containsEntry("entry_level", 900);
        // the old reading is refused; the Head of Department may not save at all
        ResponseEntity<Map> stale = it.call(school, HttpMethod.PUT, R + "/applications/" + app + "/edit", Map.of("changes", Map.of("lga", "Makurdi"), "reason", reason, "version", version));
        assertThat(stale.getStatusCode().value()).isEqualTo(422);
        assertThat(stale.getBody().get("code")).isEqualTo("PG_EDIT_STALE");
        assertThat(it.call(hod, HttpMethod.PUT, R + "/applications/" + app + "/edit", Map.of("changes", Map.of("lga", "Makurdi"), "reason", reason, "version", saved.get("version"))).getStatusCode().value()).isEqualTo(403);
        // the previous degrees as one change; the history lists the corrections
        Map<String, Object> degrees = ok(it.call(school, HttpMethod.PUT, R + "/applications/" + app + "/edit/prior-degrees", Map.of(
                "rows", List.of(Map.of("kind", "FIRST", "institution", "A Check University", "award", "B.Sc. Computer Science", "class_of_degree", "Second Class Upper", "cgpa", "4.10", "year", "2015")),
                "reason", "The transcript presented at screening lists the first degree; the form carried none", "version", saved.get("version"))));
        assertThat(((Number) degrees.get("degrees")).intValue()).isEqualTo(1);
        List<Map<String, Object>> history = (List<Map<String, Object>>) it.getList(school, R + "/applications/" + app + "/edit/history").getBody();
        assertThat(history.stream().filter(h -> "EDIT".equals(h.get("change_type"))).map(h -> h.get("field"))).contains("surname", "programme_code", "prior_degrees");

        // a postgraduate student on the register: the Director of ICT holds the student edit page's ordinary permissions and corrects a name
        int n = ThreadLocalRandom.current().nextInt(100_000, 999_999);
        UUID pg = it.student("ZZRECEDITPG", msc, String.format("MOAUM/ADM/15/%06d", n), "MOAUM/ZZR/15/" + n, 800);
        it.db(() -> jdbc.sql("UPDATE people.student SET entry_mode = 'POSTGRADUATE' WHERE id = :s").param("s", pg).update());
        UUID ug = it.student("ZZRECEDITUG", "C00023", String.format("MOAUM/ADM/15/%06d", n + 1), "MOAUM/ZZU/15/" + n, 200);
        Map<String, Object> edit = ok(it.get(ict, "/api/v1/student/students/" + pg + "/edit"));
        assertThat((List<String>) edit.get("permissions")).contains("EDIT_STUDENT_BIODATA", "EDIT_STUDENT_STATUS").doesNotContain("EDIT_STUDENT_MATRICULATION", "EDIT_STUDENT_LEVEL");
        assertThat(edit.get("postgraduate")).isNotNull();
        Map<String, Object> named = ok(it.call(ict, HttpMethod.PUT, "/api/v1/student/students/" + pg + "/edit", Map.of("changes", Map.of("other_names", "Record Corrected"),
                "reason", "The other names on the register are the register upload's; the certificate names the student so", "version", edit.get("version"))));
        assertThat(((Number) named.get("changed")).intValue()).isEqualTo(1);
        // the School searches the postgraduate alone, and is refused the undergraduate's page
        List<Map<String, Object>> hits = (List<Map<String, Object>>) it.getList(school, "/api/v1/student/edit/search?q=ZZRECEDIT").getBody();
        assertThat(hits).extracting(h -> h.get("id")).contains(pg.toString()).doesNotContain(ug.toString());
        assertThat(it.get(school, "/api/v1/student/students/" + ug + "/edit").getStatusCode().value()).isEqualTo(403);
        // the latest corrections list the applicant's and the student's
        Map<String, Object> recent = ok(it.get(ict, R + "/history?limit=50"));
        assertThat((List<Map<String, Object>>) recent.get("rows")).extracting(r -> r.get("record_id")).contains(app.toString(), pg.toString());
    }
}
