package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.ThreadLocalRandom;

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
 * V719: a postgraduate student's programme changed by the School of Postgraduate Studies through the programme swap the student edit
 * page uses. Two made-up postgraduate programmes in one department (a specialisation on the first), a postgraduate student admitted
 * on the first with their application, and an undergraduate. The School reads the structure (the degree type on each postgraduate
 * programme), checks the change, makes it: the student on the new programme at the new level, the admission record following with
 * the specialisation of the old programme let go and a PROGRAMME_CHANGED event, the application number and state untouched, the
 * swap kept with the reason, the School's office and the time. The School is refused for the undergraduate (PSW_OFFICE) and for the
 * postgraduate onto an undergraduate programme (PSW_CATEGORY); the Bursary is refused the desk. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class PgProgrammeChangeIT {

    static final String BASE = "/api/v1/programme-swaps";

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    private String freeCode() {
        for (int i = 0; i < 50; i++) {
            String c = "C9" + String.format("%04d", ThreadLocalRandom.current().nextInt(1000, 9999));
            if (jdbc.sql("SELECT count(*) FROM ref.programme WHERE code = :c").param("c", c).query(Long.class).single() == 0L) return c;
        }
        throw new IllegalStateException("no free programme code");
    }

    @Test
    void theSchoolMovesAPostgraduateStudentAndTheAdmissionRecordFollows() {
        ItSupport it = new ItSupport(port, jdbc, transactions);
        int y = it.freeYear(3100, 3800);
        String session = y + "/" + (y + 1);
        it.session(session, y);
        String prog1 = freeCode();
        String prog2 = freeCode();
        Map<String, Object> dept = jdbc.sql("SELECT d.code, d.faculty_code FROM ref.department d WHERE d.faculty_code IS NOT NULL ORDER BY d.code LIMIT 1").query().singleRow();
        String ug = jdbc.sql("SELECT code FROM ref.programme WHERE category <> 'POST GRADUATE' AND NOT archived AND code <> 'C00023' ORDER BY code LIMIT 1").query(String.class).single();
        UUID spec = UUID.randomUUID();
        UUID pg = UUID.randomUUID();
        it.db(() -> {
            jdbc.sql("INSERT INTO ref.programme (code, name, dept_code, faculty_code, category, min_score, pg_award, pg_research) VALUES "
                    + "(:a, 'M.Sc. Programme Change Studies', :d, :f, 'POST GRADUATE', 0, 'MSC', false), (:b, 'Ph.D. Programme Change Studies', :d, :f, 'POST GRADUATE', 0, 'PHD', true)")
                    .param("a", prog1).param("b", prog2).param("d", dept.get("code")).param("f", dept.get("faculty_code")).update();
            jdbc.sql("INSERT INTO catalogue.programme_specialisation (id, programme_code, code, name, active) VALUES (:id, :p, 'PCS', 'Programme Change Specialisation', true)")
                    .param("id", spec).param("p", prog1).update();
            jdbc.sql("INSERT INTO people.student (id, admission_no, matric_no, surname, other_names, programme_code, entry_mode, entry_session, entry_level, current_level, status, matriculated_at) "
                    + "VALUES (:id, :adm, :mat, 'ZZPGCHANGE', 'Invented', :p, 'POSTGRADUATE', :s, 800, 800, 'ACTIVE', now())")
                    .param("id", pg).param("adm", it.freeNumber("MOAUM/ADM/19/", 6)).param("mat", it.freeNumber("MOAUM/ZZS/19/", 4)).param("p", prog1).param("s", session).update();
            // the application as the applicant's door makes one (admissions.pg_apply), then admitted onto the register
            UUID made = jdbc.sql("SELECT x.application_id FROM admissions.pg_apply(jsonb_build_object('session', :s, 'programme', :p, 'surname', 'ZZPGCHANGE', 'otherNames', 'Invented', "
                    + "'dob', '1990-01-01', 'phone', '08030007191', 'email', :e, 'passwordHash', crypt('x', gen_salt('bf', 12)))) x")
                    .param("s", session).param("p", prog1).param("e", "zz.pgchange." + y + "@example.test").query(UUID.class).single();
            jdbc.sql("UPDATE admissions.pg_application SET specialisation_id = :spec, state = 'ADMITTED', student_id = :st, admitted_at = now() WHERE id = :id")
                    .param("spec", spec).param("st", pg).param("id", made).update();
            return made;
        });
        UUID app = jdbc.sql("SELECT id FROM admissions.pg_application WHERE student_id = :s").param("s", pg).query(UUID.class).single();
        String appNo = jdbc.sql("SELECT application_no FROM admissions.pg_application WHERE id = :a").param("a", app).query(String.class).single();
        UUID undergraduate = it.student(it.freeSurname("ZZPGCHU"), "C00023", it.freeNumber("MOAUM/ADM/19/", 6), it.freeNumber("MOAUM/ZZU/19/", 4), 200);
        String school = ItSupport.token("pgschool");
        String bursar = ItSupport.token("bursar");

        // the structure the picker is filled from: the School reads it, each postgraduate programme with its degree type
        ResponseEntity<Map> structure = it.get(school, BASE + "/structure");
        assertThat(structure.getStatusCode().value()).as(String.valueOf(structure.getBody())).isEqualTo(200);
        Map programme = ((List<Map>) structure.getBody().get("faculties")).stream()
                .flatMap(f -> ((List<Map>) f.get("departments")).stream()).flatMap(d -> ((List<Map>) d.get("programmes")).stream())
                .filter(p -> prog2.equals(p.get("code"))).findFirst().orElseThrow();
        assertThat(String.valueOf(programme.get("award"))).as("the degree type").isNotBlank().isNotEqualTo("null");
        assertThat(programme.get("category")).isEqualTo("POST GRADUATE");
        assertThat(it.get(bursar, BASE + "/structure").getStatusCode().value()).isEqualTo(403);

        // the change checked, then made, by the School
        Map<String, Object> body = Map.of("studentId", pg.toString(), "toProgramme", prog2, "toLevel", 900, "kind", "PROGRAMME_CORRECTION",
                "reason", "Admitted on the wrong programme: the School's memo of 11 November");
        ResponseEntity<Map> check = it.call(school, HttpMethod.POST, BASE + "/check", Map.of("studentId", pg.toString(), "toProgramme", prog2, "toLevel", 900));
        assertThat(check.getStatusCode().value()).as(String.valueOf(check.getBody())).isEqualTo(200);
        assertThat(check.getBody()).containsEntry("ok", true);
        ResponseEntity<Map> done = it.call(school, HttpMethod.POST, BASE, body);
        assertThat(done.getStatusCode().value()).as(String.valueOf(done.getBody())).isEqualTo(200);
        assertThat(done.getBody()).containsEntry("status", "COMPLETED").containsEntry("prepared_office", "pgschool").containsEntry("to_programme", prog2);
        assertThat(String.valueOf(done.getBody().get("swap_ref"))).startsWith("PSW/");
        Map<String, Object> student = jdbc.sql("SELECT programme_code, current_level FROM people.student WHERE id = :s").param("s", pg).query().singleRow();
        assertThat(student).containsEntry("programme_code", prog2).containsEntry("current_level", 900);
        Map<String, Object> application = jdbc.sql("SELECT programme_code, specialisation_id, application_no, state, student_id FROM admissions.pg_application WHERE id = :a").param("a", app).query().singleRow();
        assertThat(application).as("the admission record follows").containsEntry("programme_code", prog2).containsEntry("application_no", appNo).containsEntry("state", "ADMITTED");
        assertThat(application.get("specialisation_id")).as("the old programme's specialisation let go").isNull();
        assertThat(application.get("student_id")).isEqualTo(pg);
        String event = jdbc.sql("SELECT note FROM admissions.pg_application_event WHERE application_id = :a AND kind = 'PROGRAMME_CHANGED'").param("a", app).query(String.class).single();
        assertThat(event).contains(prog1 + " → " + prog2).contains("specialisation of the old programme let go").contains("the School's memo");
        assertThat(jdbc.sql("SELECT count(*) FROM admissions.pg_application WHERE student_id = :s").param("s", pg).query(Long.class).single()).as("no duplicate").isEqualTo(1L);
        assertThat(jdbc.sql("SELECT count(*) FROM people.student WHERE surname = 'ZZPGCHANGE'").query(Long.class).single()).isEqualTo(1L);

        // refused: the School for an undergraduate, the School for a postgraduate onto an undergraduate programme, the Bursary at all
        ResponseEntity<Map> ugRefused = it.call(school, HttpMethod.POST, BASE, Map.of("studentId", undergraduate.toString(), "toProgramme", ug, "toLevel", 100,
                "kind", "PROGRAMME_CORRECTION", "reason", "The School may not move an undergraduate student"));
        assertThat(ugRefused.getStatusCode().value()).isEqualTo(403);
        assertThat(ugRefused.getBody().get("code")).isEqualTo("PSW_OFFICE");
        assertThat(it.call(school, HttpMethod.POST, BASE, Map.of("studentId", pg.toString(), "toProgramme", "C00023", "toLevel", 100,
                "kind", "PROGRAMME_CORRECTION", "reason", "A postgraduate onto an undergraduate programme")).getBody().get("code")).isEqualTo("PSW_CATEGORY");
        assertThat(it.call(bursar, HttpMethod.POST, BASE + "/check", Map.of("studentId", pg.toString(), "toProgramme", prog1, "toLevel", 800)).getStatusCode().value()).isEqualTo(403);
        assertThat(jdbc.sql("SELECT programme_code FROM people.student WHERE id = :s").param("s", undergraduate).query(String.class).single()).isEqualTo("C00023");
    }
}
