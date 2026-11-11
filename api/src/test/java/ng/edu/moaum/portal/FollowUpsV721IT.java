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
 * V721, the follow-ups of 11 November 2026: (1) the preliminary desk's default route is the office's preliminary programme whatever
 * the fee types' order (the nightly suite-twice failure); (3) the desk uploads or replaces a postgraduate applicant's document, kept on
 * the application's history, refused to the Bursary; (4) old-portal students' dates of birth re-read from the file — the preview writes
 * nothing, Records writes the filled and the corrected, the Bursary is refused; (6) the School reads the swaps of postgraduate
 * students alone. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class FollowUpsV721IT {

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
    void thePreliminaryDesksDefaultRouteDoesNotFollowTheFeeTypesOrder() {
        ItSupport it = new ItSupport(port, jdbc, transactions);
        Integer was = jdbc.sql("SELECT ord FROM finance.programme_type WHERE code = 'PRELIMINARY'").query(Integer.class).single();
        try {
            it.db(() -> jdbc.sql("UPDATE finance.programme_type SET ord = 100 WHERE code = 'PRELIMINARY'").update());   // behind the proficiency courses, as the Bursary's desk may put it
            ResponseEntity<Map> summary = it.get(ItSupport.token("prelimtech"), "/api/v1/admissions/preliminary/summary");
            assertThat(summary.getStatusCode().value()).as(String.valueOf(summary.getBody())).isEqualTo(200);
            assertThat(summary.getBody()).containsEntry("route", "PRELIMINARY_TECHNOLOGY");
            List<Map> routes = it.getList(ItSupport.token("prelimtech"), "/api/v1/admissions/preliminary/routes").getBody();
            assertThat(routes.get(0).get("route")).isEqualTo("PRELIMINARY_TECHNOLOGY");
        } finally {
            it.db(() -> jdbc.sql("UPDATE finance.programme_type SET ord = :o WHERE code = 'PRELIMINARY'").param("o", was).update());
        }
    }

    @Test
    void theDeskUploadsADocumentAndTheSchoolReadsPostgraduateSwapsAlone() {
        ItSupport it = new ItSupport(port, jdbc, transactions);
        int y = it.freeYear(3100, 3800);
        String session = y + "/" + (y + 1);
        it.session(session, y);
        String prog1 = freeCode();
        String prog2 = freeCode();
        Map<String, Object> dept = jdbc.sql("SELECT d.code, d.faculty_code FROM ref.department d WHERE d.faculty_code IS NOT NULL ORDER BY d.code LIMIT 1").query().singleRow();
        UUID pg = UUID.randomUUID();
        UUID app = it.db(() -> {
            jdbc.sql("INSERT INTO ref.programme (code, name, dept_code, faculty_code, category, min_score, pg_award, pg_research) VALUES "
                    + "(:a, 'M.Sc. Follow Up Studies', :d, :f, 'POST GRADUATE', 0, 'MSC', false), (:b, 'Ph.D. Follow Up Studies', :d, :f, 'POST GRADUATE', 0, 'PHD', true)")
                    .param("a", prog1).param("b", prog2).param("d", dept.get("code")).param("f", dept.get("faculty_code")).update();
            jdbc.sql("INSERT INTO people.student (id, admission_no, matric_no, surname, other_names, programme_code, entry_mode, entry_session, entry_level, current_level, status, matriculated_at) "
                    + "VALUES (:id, :adm, :mat, 'ZZFOLLOWUP', 'Invented', :p, 'POSTGRADUATE', :s, 800, 800, 'ACTIVE', now())")
                    .param("id", pg).param("adm", it.freeNumber("MOAUM/ADM/20/", 6)).param("mat", it.freeNumber("MOAUM/ZZF/20/", 4)).param("p", prog1).param("s", session).update();
            UUID made = jdbc.sql("SELECT x.application_id FROM admissions.pg_apply(jsonb_build_object('session', :s, 'programme', :p, 'surname', 'ZZFOLLOWUP', 'otherNames', 'Invented', "
                    + "'dob', '1990-01-01', 'phone', '08030007201', 'email', :e, 'passwordHash', crypt('x', gen_salt('bf', 12)))) x")
                    .param("s", session).param("p", prog1).param("e", "zz.followup." + y + "@example.test").query(UUID.class).single();
            jdbc.sql("UPDATE admissions.pg_application SET state = 'ADMITTED', student_id = :st, admitted_at = now() WHERE id = :id").param("st", pg).param("id", made).update();
            return made;
        });
        UUID undergraduate = it.student(it.freeSurname("ZZFOLLOWUG"), "C00023", it.freeNumber("MOAUM/ADM/20/", 6), it.freeNumber("MOAUM/ZZG/20/", 4), 200);
        String school = ItSupport.token("pgschool");
        String bursar = ItSupport.token("bursar");
        String registrar = ItSupport.token("registrar");

        // (3) the desk uploads a transcript, then replaces it; the Bursary may not
        String base64 = java.util.Base64.getEncoder().encodeToString("%PDF-1.4 follow-up transcript".getBytes());
        Map<String, Object> doc = Map.of("kind", "transcript", "filename", "transcript.pdf", "contentType", "application/pdf", "base64", base64, "reason", "Brought to the School in person");
        ResponseEntity<Map> up = it.call(school, HttpMethod.POST, "/api/v1/pg/records/applications/" + app + "/documents", doc);
        assertThat(up.getStatusCode().value()).as(String.valueOf(up.getBody())).isEqualTo(200);
        assertThat(up.getBody()).containsEntry("kind", "TRANSCRIPT").containsEntry("filename", "transcript.pdf");
        assertThat(up.getBody().get("replaced")).isNull();
        ResponseEntity<Map> again = it.call(school, HttpMethod.POST, "/api/v1/pg/records/applications/" + app + "/documents",
                Map.of("kind", "TRANSCRIPT", "filename", "transcript-2.pdf", "contentType", "application/pdf", "base64", base64));
        assertThat(again.getBody()).containsEntry("replaced", "transcript.pdf");
        assertThat(jdbc.sql("SELECT count(*) FROM admissions.pg_document WHERE application_id = :a AND kind = 'TRANSCRIPT'").param("a", app).query(Long.class).single()).isEqualTo(1L);
        assertThat(jdbc.sql("SELECT count(*) FROM admissions.pg_application_event WHERE application_id = :a AND kind = 'DOCUMENT_UPLOADED_BY_DESK'").param("a", app).query(Long.class).single()).isEqualTo(2L);
        assertThat(it.call(bursar, HttpMethod.POST, "/api/v1/pg/records/applications/" + app + "/documents", doc).getStatusCode().value()).isEqualTo(403);
        assertThat(it.call(school, HttpMethod.POST, "/api/v1/pg/records/applications/" + app + "/documents",
                Map.of("kind", "PASSPORT", "filename", "p.jpg", "contentType", "image/jpeg", "base64", base64)).getBody().get("code")).isEqualTo("PG_DOC_KIND");

        // (2) on the register, the applicant editor refuses a programme change and points to the student edit page
        String version = String.valueOf(it.get(school, "/api/v1/pg/records/applications/" + app + "/edit").getBody().get("version"));
        ResponseEntity<Map> onRegister = it.call(school, HttpMethod.PUT, "/api/v1/pg/records/applications/" + app + "/edit",
                Map.of("changes", Map.of("programme_code", prog2), "reason", "Follow-up: the programme corrected on the applicant page", "version", version, "confirmCritical", true));
        assertThat(onRegister.getBody().get("code")).isEqualTo("PG_EDIT_ON_REGISTER");
        assertThat(String.valueOf(onRegister.getBody().get("detail"))).contains("student edit page");

        // (6) a postgraduate's swap by the Registry and an undergraduate's: the School lists the postgraduate's alone
        ResponseEntity<Map> pgSwap = it.call(registrar, HttpMethod.POST, "/api/v1/programme-swaps", Map.of("studentId", pg.toString(), "toProgramme", prog2, "toLevel", 900,
                "kind", "PROGRAMME_CORRECTION", "reason", "Follow-up: the postgraduate moved by the Registry"));
        assertThat(pgSwap.getStatusCode().value()).as(String.valueOf(pgSwap.getBody())).isEqualTo(200);
        String ug = jdbc.sql("SELECT code FROM ref.programme WHERE category <> 'POST GRADUATE' AND NOT archived AND code <> 'C00023' AND dept_code IS NOT NULL AND faculty_code IS NOT NULL ORDER BY code LIMIT 1").query(String.class).single();
        ResponseEntity<Map> ugSwap = it.call(registrar, HttpMethod.POST, "/api/v1/programme-swaps", Map.of("studentId", undergraduate.toString(), "toProgramme", ug, "toLevel", 200,
                "kind", "PROGRAMME_CORRECTION", "reason", "Follow-up: the undergraduate moved by the Registry"));
        assertThat(ugSwap.getStatusCode().value()).as(String.valueOf(ugSwap.getBody())).isEqualTo(200);
        List<Map> schoolSees = it.getList(school, "/api/v1/programme-swaps?limit=5000").getBody();
        assertThat(schoolSees).extracting(r -> r.get("swap_ref")).contains(pgSwap.getBody().get("swap_ref")).doesNotContain(ugSwap.getBody().get("swap_ref"));
        List<Map> registrarSees = it.getList(registrar, "/api/v1/programme-swaps?limit=5000").getBody();
        assertThat(registrarSees).extracting(r -> r.get("swap_ref")).contains(pgSwap.getBody().get("swap_ref"), ugSwap.getBody().get("swap_ref"));
        assertThat(it.get(bursar, "/api/v1/programme-swaps").getStatusCode().value()).isEqualTo(403);
    }

    @Test
    void oldPortalDatesOfBirthAreReReadFromTheFile() {
        ItSupport it = new ItSupport(port, jdbc, transactions);
        String stem = "MOAUM/ZZD/20/";
        String[] names = {"Misread", "Empty", "Agrees", "Differs"};
        String[] held = {"2003-12-09", null, "2003-09-12", "2001-01-01"};
        String[] matric = new String[4];
        UUID[] st = new UUID[4];
        for (int i = 0; i < 4; i++) {
            matric[i] = it.freeNumber(stem, 4);
            st[i] = it.student(it.freeSurname("ZZDOBF"), "C00023", it.freeNumber("MOAUM/ADM/20/", 6), matric[i], 200);
            final int k = i;
            it.db(() -> jdbc.sql("UPDATE people.student SET date_of_birth = :d::date WHERE id = :s").param("d", held[k], java.sql.Types.VARCHAR).param("s", st[k]).update());
        }
        List<Map<String, Object>> rows = List.of(
                Map.of("matric", matric[0].toLowerCase(), "dob", "12-09-2003"), Map.of("matric", matric[1], "dob", "12/09/2003"),
                Map.of("matric", matric[2], "dob", "2003-09-12"), Map.of("matric", matric[3], "dob", "12-09-2003"),
                Map.of("matric", "MOAUM/ZZD/20/0000", "dob", "12-09-2003"), Map.of("matric", matric[0], "dob", "unknown"));
        String records = ItSupport.token("records");
        ResponseEntity<Map> preview = it.call(records, HttpMethod.POST, "/api/v1/results/legacy/dates-of-birth", Map.of("rows", rows, "commit", false));
        assertThat(preview.getStatusCode().value()).as(String.valueOf(preview.getBody())).isEqualTo(200);
        Map counts = (Map) preview.getBody().get("counts");
        assertThat(counts).containsEntry("CORRECTED", 1).containsEntry("FILLED", 1).containsEntry("AGREES", 1).containsEntry("DIFFERS", 1).containsEntry("NO_STUDENT", 1).containsEntry("UNREADABLE", 1);
        assertThat(jdbc.sql("SELECT date_of_birth FROM people.student WHERE id = :s").param("s", st[0]).query(java.time.LocalDate.class).single()).isEqualTo(java.time.LocalDate.of(2003, 12, 9));
        assertThat(it.call(ItSupport.token("bursar"), HttpMethod.POST, "/api/v1/results/legacy/dates-of-birth", Map.of("rows", rows, "commit", true, "reason", "not mine")).getStatusCode().value()).isEqualTo(403);
        ResponseEntity<Map> done = it.call(records, HttpMethod.POST, "/api/v1/results/legacy/dates-of-birth", Map.of("rows", rows, "commit", true, "reason", "The old portal's file, read day, month, year"));
        assertThat(done.getStatusCode().value()).as(String.valueOf(done.getBody())).isEqualTo(200);
        assertThat(done.getBody()).containsEntry("applied", true);
        assertThat(jdbc.sql("SELECT date_of_birth FROM people.student WHERE id = :s").param("s", st[0]).query(java.time.LocalDate.class).single()).as("corrected").isEqualTo(java.time.LocalDate.of(2003, 9, 12));
        assertThat(jdbc.sql("SELECT date_of_birth FROM people.student WHERE id = :s").param("s", st[1]).query(java.time.LocalDate.class).single()).as("filled").isEqualTo(java.time.LocalDate.of(2003, 9, 12));
        assertThat(jdbc.sql("SELECT date_of_birth FROM people.student WHERE id = :s").param("s", st[3]).query(java.time.LocalDate.class).single()).as("left").isEqualTo(java.time.LocalDate.of(2001, 1, 1));
        assertThat(jdbc.sql("SELECT value FROM people.biodata WHERE student_id = :s AND field = 'date_of_birth'").param("s", st[0]).query(String.class).single()).isEqualTo("2003-09-12");
        assertThat(jdbc.sql("SELECT count(*) FROM audit.entries WHERE subject_id = :s AND reason = 'The old portal''s file, read day, month, year'").param("s", st[0]).query(Long.class).single()).isGreaterThanOrEqualTo(1L);
        Map after = (Map) it.call(records, HttpMethod.POST, "/api/v1/results/legacy/dates-of-birth", Map.of("rows", rows, "commit", false)).getBody().get("counts");
        assertThat(after).containsEntry("AGREES", 3).containsEntry("DIFFERS", 1);
    }
}
