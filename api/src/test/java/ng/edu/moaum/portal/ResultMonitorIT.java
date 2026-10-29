package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.List;
import java.util.Map;
import java.util.Random;
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
 * V700: the Director of ICT's result monitoring. An invented programme in a session of the run's own: A registered for two courses
 * (one published with a mark, one at entry with none), B for the second (a mark at entry), and C with a mark on the first and no
 * registration of it. The overview counts the programme by level; the records read as the broadsheet reads them, filtered by state
 * and found by name; one record opens with its result and history; the exceptions name C's mark; the Registry reads and a lecturer
 * and the Bursary do not; only the Director of ICT asks for a correction, once at a time; the programme's Examinations Officer sees
 * it on the sheet and declines it, the Director of ICT not; a second is withdrawn; the corrections list holds both; the upload of a
 * sheet is in the history. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class ResultMonitorIT {

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    ItSupport it;
    final String ict = ItSupport.token("ict");
    String session;
    String prog;
    String dept;
    String fac;
    String p;
    UUID a;
    UUID b;
    UUID c;
    UUID sheet1;
    UUID offering1;
    String surname;

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
        int year = it.freeYear(2300, 2900, 0, 0);
        session = year + "/" + (year + 1);
        it.session(session, year);
        p = it.freeCoursePrefix("Z");
        int n = 1000 + new Random().nextInt(8999);
        String yy = String.format("%02d", year % 100);
        surname = "ZZRMON" + n;
        String[] place = it.db(() -> {
            String[] one = jdbc.sql("""
                    SELECT p.dept_code || ',' || p.faculty_code FROM ref.programme p JOIN ref.faculty f ON f.code = p.faculty_code
                     WHERE p.category = 'UNDER GRADUATE' AND NOT p.archived AND coalesce(f.college_code, '') <> 'CHS' ORDER BY p.code LIMIT 1
                    """).query(String.class).single().split(",");
            String code = jdbc.sql("SELECT 'C' || x FROM generate_series(97100, 97999) x WHERE NOT EXISTS (SELECT 1 FROM ref.programme p WHERE p.code = 'C' || x) ORDER BY random() LIMIT 1")
                    .query(String.class).single();
            jdbc.sql("""
                    INSERT INTO ref.programme (code, name, dept_code, faculty_code, category, min_score, final_level, duration_years)
                    VALUES (:c, 'B.Sc. Result Monitoring Test ' || :c, :d, :f, 'UNDER GRADUATE', 0, 400, 4)
                    """).param("c", code).param("d", one[0]).param("f", one[1]).update();
            return new String[] {one[0], one[1], code};
        });
        dept = place[0];
        fac = place[1];
        prog = place[2];
        a = it.student(surname + "A", prog, "MOAUM/ADM/" + yy + "/71" + n, "MOAUM/RMN/" + yy + "/1" + n, 100);
        b = it.student(surname + "B", prog, "MOAUM/ADM/" + yy + "/72" + n, "MOAUM/RMN/" + yy + "/2" + n, 100);
        c = it.student(surname + "C", prog, "MOAUM/ADM/" + yy + "/73" + n, "MOAUM/RMN/" + yy + "/3" + n, 100);
        it.db(() -> {
            jdbc.sql("""
                    INSERT INTO catalogue.course (code, title, units, semester, level, dept_code, kind, state, ca_max) VALUES
                        (:p || ' 101', 'Monitor Course One', 3, 1, 100, :d, 'Core', 'LIVE', 40), (:p || ' 102', 'Monitor Course Two', 2, 1, 100, :d, 'Core', 'LIVE', 40)
                    """).param("p", p).param("d", dept).update();
            jdbc.sql("INSERT INTO catalogue.course_offer (course_code, programme_code, level, basis) SELECT :p || ' ' || x, :prog, 100, 'Core' FROM unnest(ARRAY['101', '102']) x")
                    .param("p", p).param("prog", prog).update();
            jdbc.sql("INSERT INTO catalogue.offering (id, course_code, session, semester) SELECT gen_random_uuid(), :p || ' ' || x, :s, 1 FROM unnest(ARRAY['101', '102']) x")
                    .param("p", p).param("s", session).update();
            jdbc.sql("INSERT INTO assessment.score_sheet (id, offering_id) SELECT gen_random_uuid(), o.id FROM catalogue.offering o WHERE o.session = :s AND o.course_code LIKE :p || ' %'")
                    .param("s", session).param("p", p).update();
            for (UUID st : List.of(a, b)) {
                UUID reg = UUID.randomUUID();
                jdbc.sql("INSERT INTO registration.course_registration (id, student_id, session, semester, level, status, submitted_at, approved_at) VALUES (:r, :st, :s, 1, 100, 'APPROVED', now(), now())")
                        .param("r", reg).param("st", st).param("s", session).update();
                jdbc.sql("""
                        INSERT INTO registration.entry (registration_id, offering_id, units, entry_type, status, basis)
                        SELECT :r, o.id, 2, 'CURRENT', 'APPROVED', 'Core' FROM catalogue.offering o
                         WHERE o.session = :s AND (o.course_code = :p || ' 102' OR (:st = :a AND o.course_code = :p || ' 101'))
                        """).param("r", reg).param("s", session).param("p", p).param("st", st).param("a", a).update();
            }
            jdbc.sql("""
                    INSERT INTO assessment.score (sheet_id, student_id, ca, exam, outcome)
                    SELECT sh.id, x.st, x.ca, x.ex, 'GRADED' FROM (VALUES (:a, '101', 30, 40), (:b, '102', 20, 30), (:c, '101', 25, 35)) x(st, n, ca, ex)
                      JOIN catalogue.offering o ON o.course_code = :p || ' ' || x.n AND o.session = :s JOIN assessment.score_sheet sh ON sh.offering_id = o.id
                    """).param("a", a).param("b", b).param("c", c).param("p", p).param("s", session).update();
            jdbc.sql("SELECT set_config('moaum.maintenance', 'on', true)").query().singleRow();
            jdbc.sql("""
                    UPDATE assessment.score_sheet sh SET stage = 'PUBLISHED', published_at = now(), senate_minute = 'IT V700'
                      FROM catalogue.offering o WHERE o.id = sh.offering_id AND o.session = :s AND o.course_code = :p || ' 101'
                    """).param("s", session).param("p", p).update();
            return jdbc.sql("""
                    INSERT INTO assessment.sheet_upload (id, sheet_id, uploaded_by, uploader_office, reason, rows_written, uploaded_at)
                    SELECT gen_random_uuid(), sh.id, gen_random_uuid(), 'lecturer', 'IT V700: the class uploaded', 2, now()
                      FROM assessment.score_sheet sh JOIN catalogue.offering o ON o.id = sh.offering_id WHERE o.session = :s AND o.course_code = :p || ' 101'
                    """).param("s", session).param("p", p).update();
        });
        offering1 = jdbc.sql("SELECT id FROM catalogue.offering WHERE session = :s AND course_code = :p || ' 101'").param("s", session).param("p", p).query(UUID.class).single();
        sheet1 = jdbc.sql("SELECT id FROM assessment.score_sheet WHERE offering_id = :o").param("o", offering1).query(UUID.class).single();
    }

    private String q(String path) {
        return path + (path.contains("?") ? "&" : "?") + "session=" + session + "&sem=1";
    }

    @Test
    void theDirectorOfIctSeesTheResultsAndAsksTheDeskOfEntryForACorrection() {
        // ── the overview: the programme by level, in its department ──
        ResponseEntity<Map> ov = it.get(ict, q("/api/v1/results/monitor/overview?fac=" + fac + "&dept=" + dept));
        assertThat(ov.getStatusCode().value()).as(String.valueOf(ov.getBody())).isEqualTo(200);
        assertThat(ov.getBody()).containsEntry("by", "PROGRAMME");
        Map<String, Object> row = ((List<Map<String, Object>>) ov.getBody().get("rows")).stream().filter(r -> prog.equals(r.get("programmeCode"))).findFirst().orElseThrow();
        assertThat(row).containsEntry("level", 100).containsEntry("students", 2).containsEntry("results", 3).containsEntry("withResult", 2)
                .containsEntry("awaiting", 1).containsEntry("atEntry", 1).containsEntry("published", 1).containsEntry("exceptions", 1);

        // ── the records, as the broadsheet reads them ──
        ResponseEntity<Map> rec = it.get(ict, q("/api/v1/results/monitor/records?prog=" + prog + "&level=100"));
        assertThat(rec.getStatusCode().value()).as(String.valueOf(rec.getBody())).isEqualTo(200);
        assertThat(rec.getBody()).containsEntry("total", 3);
        assertThat((Map<String, Object>) rec.getBody().get("summary")).containsEntry("students", 2).containsEntry("withResult", 2).containsEntry("exceptions", 1);
        List<Map<String, Object>> rows = (List<Map<String, Object>>) rec.getBody().get("rows");
        assertThat(rows).extracting(r -> r.get("surname") + " " + r.get("courseCode") + " " + r.get("state"))
                .containsExactly(surname + "A " + p + " 101 PUBLISHED", surname + "A " + p + " 102 AWAITING", surname + "B " + p + " 102 ENTRY");
        assertThat(rows.get(0)).containsEntry("total", 70).containsEntry("ca", 30).containsEntry("exam", 40).containsEntry("versions", 1);
        assertThat((List) it.get(ict, q("/api/v1/results/monitor/records?prog=" + prog + "&state=AWAITING")).getBody().get("rows")).hasSize(1);
        assertThat(it.get(ict, q("/api/v1/results/monitor/records?prog=" + prog + "&q=" + surname + "B")).getBody()).containsEntry("total", 1);

        // ── one record: the result, the sittings and the history ──
        ResponseEntity<Map> one = it.get(ict, "/api/v1/results/monitor/records/" + offering1 + "/" + a);
        assertThat(one.getStatusCode().value()).as(String.valueOf(one.getBody())).isEqualTo(200);
        assertThat((Map<String, Object>) one.getBody().get("result")).containsEntry("total", 70).containsEntry("stage", "PUBLISHED");
        assertThat((List) one.getBody().get("versions")).hasSize(1);
        assertThat(one.getBody()).containsEntry("mayRequest", true);

        // ── the exceptions: C's mark with no registration ──
        ResponseEntity<Map> ex = it.get(ict, q("/api/v1/results/monitor/exceptions?prog=" + prog));
        assertThat(ex.getStatusCode().value()).as(String.valueOf(ex.getBody())).isEqualTo(200);
        assertThat((Map<String, Object>) ex.getBody().get("counts")).containsEntry("RESULT_WITHOUT_REGISTRATION", 1);
        assertThat((List<Map<String, Object>>) ex.getBody().get("rows")).extracting(r -> r.get("surname")).containsExactly(surname + "C");

        // ── who reads: the Registry does; a lecturer and the Bursary do not ──
        assertThat(it.get(ItSupport.token("registrar"), q("/api/v1/results/monitor/records?prog=" + prog)).getStatusCode().value()).isEqualTo(200);
        assertThat(it.get(ItSupport.token("lecturer"), q("/api/v1/results/monitor/records?prog=" + prog)).getStatusCode().value()).isEqualTo(403);
        assertThat(it.get(ItSupport.token("bursar"), q("/api/v1/results/monitor/overview")).getStatusCode().value()).isEqualTo(403);

        // ── a correction asked for: the Director of ICT alone, once at a time ──
        Map<String, Object> ask = Map.of("sheetId", sheet1.toString(), "studentId", a.toString(), "reasonKind", "INCORRECT_SCORE",
                "note", "IT V700: the examination was 50 on the script", "ca", 30, "exam", 50);
        assertThat(it.call(ItSupport.token("registrar"), HttpMethod.POST, "/api/v1/results/monitor/corrections", ask).getStatusCode().value()).isEqualTo(403);
        ResponseEntity<Map> made = it.call(ict, HttpMethod.POST, "/api/v1/results/monitor/corrections", ask);
        assertThat(made.getStatusCode().value()).as(String.valueOf(made.getBody())).isEqualTo(200);
        assertThat(made.getBody()).containsEntry("state", "OPEN").containsEntry("wasCa", 30).containsEntry("wasExam", 40).containsEntry("ca", 30).containsEntry("exam", 50);
        assertThat(String.valueOf(made.getBody().get("ref"))).matches("CRQ-[0-9]{4}-[0-9]{5}");
        String id = String.valueOf(made.getBody().get("id"));
        ResponseEntity<Map> again = it.call(ict, HttpMethod.POST, "/api/v1/results/monitor/corrections", ask);
        assertThat(again.getStatusCode().value()).isEqualTo(422);
        assertThat(again.getBody()).containsEntry("code", "CRQ_OPEN");

        // ── the programme's Examinations Officer sees it on the sheet and declines it; the Director of ICT may not decline ──
        String exams = it.officer("exams", "programme", prog);
        ResponseEntity<List> onSheet = it.callList(exams, HttpMethod.GET, "/api/v1/results/sheets/" + sheet1 + "/correction-requests", null);
        assertThat(onSheet.getStatusCode().value()).isEqualTo(200);
        assertThat((List<Map<String, Object>>) onSheet.getBody()).extracting(r -> r.get("id")).containsExactly(id);
        Map<String, Object> no = Map.of("note", "IT V700: the board approved the mark as it stands");
        assertThat(it.call(ict, HttpMethod.POST, "/api/v1/results/correction-requests/" + id + "/decline", no).getStatusCode().value()).isEqualTo(403);
        ResponseEntity<Map> declined = it.call(exams, HttpMethod.POST, "/api/v1/results/correction-requests/" + id + "/decline", no);
        assertThat(declined.getStatusCode().value()).as(String.valueOf(declined.getBody())).isEqualTo(200);
        assertThat(declined.getBody()).containsEntry("state", "DECLINED").containsEntry("closedOffice", "exams");

        // ── a second, withdrawn by the Director of ICT ──
        ResponseEntity<Map> second = it.call(ict, HttpMethod.POST, "/api/v1/results/monitor/corrections", Map.of("sheetId", sheet1.toString(), "studentId", c.toString(),
                "reasonKind", "WRONG_STUDENT", "note", "IT V700: C did not take this course"));
        assertThat(second.getStatusCode().value()).as(String.valueOf(second.getBody())).isEqualTo(200);
        ResponseEntity<Map> withdrawn = it.call(ict, HttpMethod.POST, "/api/v1/results/monitor/corrections/" + second.getBody().get("id") + "/withdraw",
                Map.of("note", "IT V700: raised in error by the test"));
        assertThat(withdrawn.getStatusCode().value()).as(String.valueOf(withdrawn.getBody())).isEqualTo(200);
        assertThat(withdrawn.getBody()).containsEntry("state", "WITHDRAWN");

        // ── the corrections list holds both; the upload is in the history ──
        ResponseEntity<Map> list = it.get(ict, q("/api/v1/results/monitor/corrections?state=ALL"));
        assertThat(list.getStatusCode().value()).isEqualTo(200);
        assertThat((List<Map<String, Object>>) list.getBody().get("requests")).extracting(r -> r.get("courseCode") + " " + r.get("state"))
                .contains(p + " 101 DECLINED", p + " 101 WITHDRAWN");
        ResponseEntity<Map> up = it.get(ict, q("/api/v1/results/monitor/uploads?kind=SCORE_SHEET"));
        assertThat(up.getStatusCode().value()).isEqualTo(200);
        assertThat((List<Map<String, Object>>) up.getBody().get("rows")).extracting(r -> r.get("courseCode") + " " + r.get("records")).contains(p + " 101 2");
    }
}
