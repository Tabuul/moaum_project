package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.time.LocalDate;
import java.util.List;
import java.util.Map;
import java.util.UUID;

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
 * V717: dates are read day first — JAMB's "12-09-2003" is 12 September 2003 through the API's own connection — and the register is put
 * right from JAMB's date-of-birth file: a made-up committed list with five candidates whose file says 12-09-2003 (one says "n/a"),
 * five students on the register — one holding the old misreading (9 December), one holding nothing, one agreeing, one holding another
 * date, one under the unreadable text. The Registry reads the register against the file (nothing written); the Bursary may not write
 * it; the Academic Office writes it — the misread corrected, the empty filled, the agreeing kept, the other date left and listed,
 * the Biodata form following, every write on the audit spine with the reason. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class DateOfBirthReadingIT {

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    @Test
    void theApisConnectionReadsDayFirst() {
        assertThat(jdbc.sql("SHOW datestyle").query(String.class).single()).isEqualTo("ISO, DMY");
        assertThat(jdbc.sql("SELECT '12-09-2003'::date").query(LocalDate.class).single()).isEqualTo(LocalDate.of(2003, 9, 12));
        assertThat(jdbc.sql("SELECT platform.read_date('September 12, 2003')").query(LocalDate.class).single()).isEqualTo(LocalDate.of(2003, 9, 12));
        assertThat(jdbc.sql("SELECT platform.date_misread('12-09-2003')").query(LocalDate.class).single()).isEqualTo(LocalDate.of(2003, 12, 9));
    }

    @Test
    void theRegisterIsPutRightFromJambsFile() {
        ItSupport it = new ItSupport(port, jdbc, transactions);
        int y = it.freeYear(3100, 3800);
        String session = y + "/" + (y + 1);
        it.session(session, y);
        String base = "/api/v1/admissions/sessions/" + session + "/candidate-data/dates-of-birth";
        String stem = "9717" + it.freeNumber("", 7);
        String[] names = {"Misread", "Empty", "Agrees", "Differs", "Unreadable"};
        String[] held = {"2003-12-09", null, "2003-09-12", "2001-01-01", null};
        UUID[] students = new UUID[5];
        UUID batch = UUID.randomUUID();
        it.db(() -> {
            jdbc.sql("INSERT INTO admissions.caps_batch (id, session, source, filename, file_sha256, rows_read, list_kind, downloaded_on, uploaded_by, uploaded_office, committed_at) "
                    + "VALUES (:id, :s, 'CAPS_DOWNLOAD', 'dob.xlsx', decode(md5(:id::text), 'hex'), 5, 'UTME', current_date, gen_random_uuid(), 'academic', now())")
                    .param("id", batch).param("s", session).update();
            for (int i = 0; i < 5; i++) {
                String jamb = stem + i + "DB";
                UUID cand = UUID.randomUUID();
                jdbc.sql("INSERT INTO admissions.caps_row (id, batch_id, session, jamb_reg_no, raw, surname, other_names, jamb_code, aggregate, entry_mode) "
                        + "VALUES (gen_random_uuid(), :b, :s, :j, '{}'::jsonb, 'ZZDOBIT', :n, 'C00023', 210, 'UTME')").param("b", batch).param("s", session).param("j", jamb).param("n", names[i]).update();
                jdbc.sql("INSERT INTO admissions.candidate (id, session, jamb_reg_no, surname, other_names, programme, entry_mode, entry_level, offer_state) "
                        + "VALUES (:id, :s, :j, 'ZZDOBIT', :n, (SELECT name FROM ref.programme WHERE code = 'C00023'), 'UTME', 100, 'PROPOSED')")
                        .param("id", cand).param("s", session).param("j", jamb).param("n", names[i]).update();
                jdbc.sql("INSERT INTO admissions.attachment (id, session, kind, source_name, jamb_key, read_as, candidate_id, matched_at, payload) "
                        + "VALUES (gen_random_uuid(), :s, 'DATE_OF_BIRTH', :j, :j, 'COLUMN', :c, now(), jsonb_build_object('dob', :d::text, 'ambiguous', true))")
                        .param("s", session).param("j", jamb).param("c", cand).param("d", i == 4 ? "n/a" : "12-09-2003").update();
                UUID st = UUID.randomUUID();
                students[i] = st;
                jdbc.sql("INSERT INTO people.student (id, candidate_id, admission_no, jamb_reg_no, surname, other_names, date_of_birth, programme_code, entry_mode, entry_session, entry_level, current_level, status) "
                        + "VALUES (:id, :c, :adm, :j, 'ZZDOBIT', :n, :dob::date, 'C00023', 'UTME', :s, 100, 100, 'ADMITTED')")
                        .param("id", st).param("c", cand).param("adm", it.freeNumber("MOAUM/ADM/17/", 6)).param("j", jamb).param("n", names[i]).param("dob", held[i], java.sql.Types.VARCHAR).param("s", session).update();
            }
            jdbc.sql("INSERT INTO people.biodata (student_id, field, value) VALUES (:a, 'date_of_birth', '2003-12-09'), (:d, 'date_of_birth', '2001-01-01')").param("a", students[0]).param("d", students[3]).update();
            return null;
        });
        String registrar = ItSupport.token("registrar");
        String bursar = ItSupport.token("bursar");
        String academic = ItSupport.token("academic");

        // the Registry reads the register against the file: nothing is written
        ResponseEntity<Map> read = it.get(registrar, base);
        assertThat(read.getStatusCode().value()).as(String.valueOf(read.getBody())).isEqualTo(200);
        Map counts = (Map) read.getBody().get("counts");
        assertThat(counts).containsEntry("total", 5).containsEntry("agrees", 1).containsEntry("filled", 1).containsEntry("corrected", 1).containsEntry("differs", 1).containsEntry("unreadable", 1);
        assertThat(read.getBody()).containsEntry("applied", false);
        List<Map> rows = (List<Map>) read.getBody().get("rows");
        assertThat(rows).hasSize(4);
        assertThat(rows.stream().filter(r -> "Misread".equals(r.get("other_names"))).findFirst().orElseThrow()).containsEntry("action", "CORRECTED").containsEntry("held", "2003-12-09").containsEntry("jamb_date", "2003-09-12");
        assertThat(dob(students[0])).isEqualTo(LocalDate.of(2003, 12, 9));
        assertThat(dob(students[1])).isNull();

        // the Bursary may not write it; the Academic Office does
        assertThat(it.call(bursar, HttpMethod.POST, base + "/reconcile", Map.of("reason", "not mine")).getStatusCode().value()).isEqualTo(403);
        assertThat(dob(students[0])).isEqualTo(LocalDate.of(2003, 12, 9));
        ResponseEntity<Map> done = it.call(academic, HttpMethod.POST, base + "/reconcile", Map.of("reason", "JAMB's date of birth, read day, month, year"));
        assertThat(done.getStatusCode().value()).as(String.valueOf(done.getBody())).isEqualTo(200);
        assertThat(done.getBody()).containsEntry("applied", true);
        assertThat((Map) done.getBody().get("counts")).containsEntry("corrected", 1).containsEntry("filled", 1).containsEntry("differs", 1);
        assertThat(dob(students[0])).as("the misread corrected").isEqualTo(LocalDate.of(2003, 9, 12));
        assertThat(dob(students[1])).as("the empty record filled").isEqualTo(LocalDate.of(2003, 9, 12));
        assertThat(dob(students[2])).isEqualTo(LocalDate.of(2003, 9, 12));
        assertThat(dob(students[3])).as("another date is left for the Registry").isEqualTo(LocalDate.of(2001, 1, 1));
        assertThat(dob(students[4])).isNull();
        assertThat(form(students[0])).as("the Biodata form follows the record").isEqualTo("2003-09-12");
        assertThat(form(students[1])).isEqualTo("2003-09-12");
        assertThat(form(students[3])).isEqualTo("2001-01-01");
        assertThat(jdbc.sql("SELECT count(*) FROM audit.entries WHERE subject_id = :s AND reason = 'JAMB''s date of birth, read day, month, year'").param("s", students[0]).query(Long.class).single())
                .as("the correction is on the audit spine with the reason").isGreaterThanOrEqualTo(1L);

        // read again: everything written now agrees
        Map again = (Map) it.get(registrar, base).getBody().get("counts");
        assertThat(again).containsEntry("agrees", 3).containsEntry("corrected", 0).containsEntry("filled", 0).containsEntry("differs", 1).containsEntry("unreadable", 1);
    }

    private LocalDate dob(UUID student) {
        return jdbc.sql("SELECT date_of_birth FROM people.student WHERE id = :s").param("s", student).query(LocalDate.class).optional().orElse(null);
    }

    private String form(UUID student) {
        return jdbc.sql("SELECT value FROM people.biodata WHERE student_id = :s AND field = 'date_of_birth'").param("s", student).query(String.class).optional().orElse(null);
    }
}
