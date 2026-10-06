package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.time.LocalDate;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import org.junit.jupiter.api.AfterEach;
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
 * JUPEB attendance on the University's attendance engine (V342): the class list is the subject's registered students of the
 * class; an instructor takes only the registers they are assigned to, marks everyone at once, corrects a saved mark only with
 * a reason (kept on the history), locks the register, after which only the JUPEB Office corrects it; a student's photograph
 * is shown to the instructor of a subject they take and to no one else's; a student reads their own attendance and no one
 * else's; the reports count the rate over the classes not excused and compare it with a minimum only once one is set.
 * Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class JupebAttendanceIT {

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    ItSupport it;
    String office;
    String lecturer;
    String staffNumber;
    String session;
    String tag;
    UUID s1;
    UUID s2;
    UUID classA;
    UUID classB;
    UUID studentA;
    UUID studentB;

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
        office = TestTokens.token(it.person("ZZATT-OFFICE", "ZZATTOFFICE"), List.of("jupeb"));
        tag = UUID.randomUUID().toString().replace("-", "").substring(0, 6).toUpperCase();
        staffNumber = "ZZATT-LEC-" + tag;
        lecturer = TestTokens.token(it.person(staffNumber, "ZZATTLECTURER"), List.of("lecturer"));
        session = jdbc.sql("SELECT jupeb.current_session()").query(String.class).single();
        s1 = UUID.randomUUID();
        s2 = UUID.randomUUID();
        UUID s3 = UUID.randomUUID();
        UUID comb = UUID.randomUUID();
        classA = UUID.randomUUID();
        classB = UUID.randomUUID();
        studentA = UUID.randomUUID();
        studentB = UUID.randomUUID();
        it.db(() -> {
            for (Object[] s : new Object[][] {{s1, "ZA" + tag, "Att Biology " + tag}, {s2, "ZB" + tag, "Att Chemistry " + tag}, {s3, "ZC" + tag, "Att Physics " + tag}}) {
                jdbc.sql("INSERT INTO jupeb.subject (id, code, title) VALUES (:id, :c, :t)").param("id", s[0]).param("c", s[1]).param("t", s[2]).update();
            }
            jdbc.sql("INSERT INTO jupeb.combination (id, code, name, subject1, subject2, subject3, area) VALUES (:id, :c, 'Att combination', :a, :b, :d, 'Science')")
                    .param("id", comb).param("c", "ZT" + tag).param("a", s1).param("b", s2).param("d", s3).update();
            jdbc.sql("INSERT INTO jupeb.class (id, session, name) VALUES (:a, :s, :na), (:b, :s, :nb)").param("a", classA).param("b", classB).param("s", session)
                    .param("na", "Att A " + tag).param("nb", "Att B " + tag).update();
            for (Object[] st : new Object[][] {{studentA, classA, "A"}, {studentB, classB, "B"}}) {
                UUID acc = UUID.randomUUID();
                String email = "zz.att." + tag.toLowerCase() + "." + st[2] + "@example.com";
                jdbc.sql("INSERT INTO jupeb.account (id, email, password_hash) VALUES (:id, :e, '$2a$12$abcdefghijklmnopqrstuuabcdefghijklmnopqrstuvwxyz12345')")
                        .param("id", acc).param("e", email).update();
                jdbc.sql("""
                        INSERT INTO jupeb.application (id, account_id, session, application_no, surname, first_name, email, stream, combination_id, class_id, state, subjects_registered_at)
                        VALUES (:id, :acc, :s, :no, :sn, 'Student', :e, 'SCIENCE', :comb, :cls, 'STUDENT', now())
                        """).param("id", st[0]).param("acc", acc).param("s", session).param("no", "JUPEB/APP/ATT/" + tag + st[2]).param("sn", "ZZATT" + st[2])
                        .param("e", email).param("comb", comb).param("cls", st[1]).update();
                for (UUID sub : List.of(s1, s2, s3)) {
                    jdbc.sql("INSERT INTO jupeb.subject_registration (application_id, subject_id, session) VALUES (:a, :s, :sess)").param("a", st[0]).param("s", sub).param("sess", session).update();
                }
            }
            return null;
        });
    }

    @AfterEach
    void tearDown() {
        it.db(() -> jdbc.sql("DELETE FROM attendance.policy WHERE context = 'JUPEB' AND session = :s").param("s", session).update());
    }

    private static int status(ResponseEntity<?> r) {
        return r.getStatusCode().value();
    }

    private static Map<String, Object> ok(ResponseEntity<Map> r) {
        assertThat(r.getStatusCode().value()).as(String.valueOf(r.getBody())).isEqualTo(200);
        return r.getBody();
    }

    private static String code(ResponseEntity<Map> r) {
        assertThat(r.getStatusCode().value()).as(String.valueOf(r.getBody())).isEqualTo(422);
        return String.valueOf(r.getBody().get("code"));
    }

    private Map<String, Object> open(String token, UUID subject, UUID klass) {
        java.util.Map<String, Object> body = new java.util.HashMap<>();
        body.put("session", session);
        body.put("semester", 1);
        body.put("subjectId", subject);
        body.put("classId", klass);
        body.put("heldOn", LocalDate.now().toString());
        body.put("topic", "Cells");
        return it.call(token, HttpMethod.POST, "/api/v1/attendance/jupeb/registers", body).getBody();
    }

    @Test
    void anInstructorTakesTheirOwnRegisterAndTheOfficeCorrectsALockedOne() {
        // not yet assigned: nothing to take
        assertThat(status(it.call(lecturer, HttpMethod.POST, "/api/v1/attendance/jupeb/registers",
                Map.of("session", session, "semester", 1, "subjectId", s1, "classId", classA, "heldOn", LocalDate.now().toString())))).isEqualTo(403);
        // the JUPEB Office assigns the lecturer to the subject, class A
        assertThat(status(it.call(lecturer, HttpMethod.POST, "/api/v1/attendance/jupeb/instructors",
                Map.of("session", session, "subjectId", s1, "classId", classA, "staff", staffNumber)))).isEqualTo(403);
        assertThat(status(it.callList(office, HttpMethod.POST, "/api/v1/attendance/jupeb/instructors",
                Map.of("session", session, "subjectId", s1, "classId", classA, "staff", staffNumber)))).isEqualTo(200);
        Map<String, Object> options = ok(it.get(lecturer, ub -> ub.path("/api/v1/attendance/jupeb/options").queryParam("session", session).build()));
        assertThat((List<Map<String, Object>>) options.get("subjects")).extracting(s -> s.get("id")).containsExactly(s1.toString());

        // the register of class A: student A only, drawn from the registrations
        Map<String, Object> reg = open(lecturer, s1, classA);
        String id = String.valueOf(reg.get("id"));
        List<Map<String, Object>> rows = (List<Map<String, Object>>) reg.get("rows");
        assertThat(rows).extracting(r -> r.get("member_ref")).containsExactly(studentA.toString());
        // another subject, or the other class: not this lecturer's
        assertThat(status(it.call(lecturer, HttpMethod.POST, "/api/v1/attendance/jupeb/registers",
                Map.of("session", session, "semester", 1, "subjectId", s2, "classId", classA, "heldOn", LocalDate.now().toString())))).isEqualTo(403);
        String other = String.valueOf(open(office, s1, classB).get("id"));
        assertThat(status(it.get(lecturer, "/api/v1/attendance/jupeb/registers/" + other))).isEqualTo(404);
        // a student not on the class list is not marked here
        assertThat(code(it.call(lecturer, HttpMethod.POST, "/api/v1/attendance/jupeb/registers/" + id + "/marks",
                Map.of("marks", List.of(Map.of("member", studentB, "status", "PRESENT")))))).isEqualTo("ATT_NOT_ON_LIST");

        // mark all present, then the correction: with a reason, kept on the history
        Map<String, Object> saved = ok(it.call(lecturer, HttpMethod.POST, "/api/v1/attendance/jupeb/registers/" + id + "/marks",
                Map.of("marks", List.of(Map.of("member", studentA, "status", "PRESENT")))));
        assertThat(((Map<String, Object>) saved.get("counts")).get("present")).isEqualTo(1);
        assertThat(code(it.call(lecturer, HttpMethod.POST, "/api/v1/attendance/jupeb/registers/" + id + "/marks",
                Map.of("marks", List.of(Map.of("member", studentA, "status", "LATE")))))).isEqualTo("ATT_REASON");
        ok(it.call(lecturer, HttpMethod.POST, "/api/v1/attendance/jupeb/registers/" + id + "/marks",
                Map.of("marks", List.of(Map.of("member", studentA, "status", "LATE", "remarks", "came in at 9:20")), "reason", "Recorded present by mistake")));
        List<Map<String, Object>> changes = it.callList(lecturer, HttpMethod.GET, "/api/v1/attendance/jupeb/registers/" + id + "/changes", null).getBody();
        assertThat(changes).hasSize(1);
        assertThat(changes.get(0).get("old_status")).isEqualTo("PRESENT");
        assertThat(changes.get(0).get("new_status")).isEqualTo("LATE");

        // locked: the lecturer no longer changes it; the JUPEB Office corrects it with a reason
        ok(it.call(lecturer, HttpMethod.POST, "/api/v1/attendance/jupeb/registers/" + id + "/lock", null));
        assertThat(code(it.call(lecturer, HttpMethod.POST, "/api/v1/attendance/jupeb/registers/" + id + "/marks",
                Map.of("marks", List.of(Map.of("member", studentA, "status", "ABSENT")), "reason", "x y z")))).isEqualTo("ATT_LOCKED");
        assertThat(status(it.call(lecturer, HttpMethod.POST, "/api/v1/attendance/jupeb/registers/" + id + "/unlock", Map.of("reason", "please")))).isEqualTo(403);
        ok(it.call(office, HttpMethod.POST, "/api/v1/attendance/jupeb/registers/" + id + "/marks",
                Map.of("marks", List.of(Map.of("member", studentA, "status", "EXCUSED", "remarks", "medical")), "reason", "Medical note presented")));
        assertThat(it.callList(office, HttpMethod.GET, "/api/v1/attendance/jupeb/registers/" + id + "/changes", null).getBody()).hasSize(2);

        // the photograph: to the instructor of a subject the student takes, not of a student they do not teach
        it.db(() -> {
            UUID doc = UUID.randomUUID();
            jdbc.sql("INSERT INTO jupeb.document (id, application_id, kind, filename, content_type, size_bytes) VALUES (:d, :a, 'PASSPORT', 'p.png', 'image/png', :n)")
                    .param("d", doc).param("a", studentA).param("n", JupebIT.PNG.length).update();
            jdbc.sql("INSERT INTO jupeb.document_blob (document_id, bytes) VALUES (:d, :b)").param("d", doc).param("b", JupebIT.PNG).update();
            return null;
        });
        ResponseEntity<byte[]> photo = it.getBytes(lecturer, "/api/v1/attendance/jupeb/photo/" + studentA);
        assertThat(photo.getStatusCode().value()).isEqualTo(200);
        assertThat(photo.getBody()[0] & 0xFF).isEqualTo(0xFF);
        assertThat(it.getBytes(lecturer, "/api/v1/attendance/jupeb/photo/" + studentB).getStatusCode().value()).isEqualTo(404);

        // the student reads their own attendance; the engine's registers are not theirs to open
        String student = TestTokens.token(studentA, List.of("applicant"));
        Map<String, Object> mine = ok(it.get(student, "/api/v1/jupeb/me/attendance"));
        List<Map<String, Object>> subjects = (List<Map<String, Object>>) mine.get("subjects");
        assertThat(subjects).hasSize(1);
        assertThat(((Number) subjects.get(0).get("excused")).intValue()).isEqualTo(1);
        assertThat(subjects.get(0).get("verdict")).isNull();
        assertThat(status(it.get(student, "/api/v1/attendance/jupeb/registers/" + id))).isEqualTo(403);
        String studentBToken = TestTokens.token(studentB, List.of("applicant"));
        assertThat((List<?>) ok(it.get(studentBToken, "/api/v1/jupeb/me/attendance")).get("subjects")).isEmpty();

        // the reports: the rate over the classes not excused; the minimum only once it is set
        ok(it.call(office, HttpMethod.POST, "/api/v1/attendance/jupeb/registers/" + other + "/marks",
                Map.of("marks", List.of(Map.of("member", studentB, "status", "ABSENT")))));
        Map<String, Object> report = ok(it.get(office, ub -> ub.path("/api/v1/attendance/jupeb/reports").queryParam("session", session).queryParam("subject", s1).build()));
        assertThat(report.get("minPercent")).isNull();
        assertThat((List<Map<String, Object>>) report.get("rows")).extracting(r -> r.get("member_ref")).contains(studentA.toString(), studentB.toString());
        ok(it.call(office, HttpMethod.PUT, "/api/v1/attendance/jupeb/policy", Map.of("session", session, "minPercent", 75)));
        Map<String, Object> below = ok(it.get(office, ub -> ub.path("/api/v1/attendance/jupeb/reports").queryParam("session", session).queryParam("subject", s1)
                .queryParam("below", true).build()));
        assertThat((List<Map<String, Object>>) below.get("rows")).extracting(r -> r.get("member_ref")).containsExactly(studentB.toString());

        // V344: the standing against the minimum — below it, close to it — and the warning, the office's to send; nobody else's
        ok(it.call(office, HttpMethod.PUT, "/api/v1/attendance/jupeb/policy", Map.of("session", session, "minPercent", 75, "warnBand", 10, "minClasses", 1)));
        Map<String, Object> opts = ok(it.get(office, ub -> ub.path("/api/v1/attendance/jupeb/options").queryParam("session", session).build()));
        assertThat(new java.math.BigDecimal(String.valueOf(opts.get("warnBand")))).isEqualByComparingTo("10");
        assertThat(((Number) opts.get("minClasses")).intValue()).isEqualTo(1);
        Map<String, Object> standing = ok(it.get(office, ub -> ub.path("/api/v1/attendance/jupeb/standing").queryParam("session", session).queryParam("only", "below").build()));
        assertThat((List<Map<String, Object>>) standing.get("rows")).extracting(r -> r.get("member_ref")).containsOnly(studentB.toString());
        assertThat((List<Map<String, Object>>) standing.get("rows")).allMatch(r -> Boolean.TRUE.equals(r.get("warnable")));
        assertThat(status(it.get(lecturer, ub -> ub.path("/api/v1/attendance/jupeb/standing").queryParam("session", session).build()))).isEqualTo(403);
        assertThat(status(it.call(lecturer, HttpMethod.POST, "/api/v1/attendance/jupeb/warn", null))).isEqualTo(403);
        Map<String, Object> warned = ok(it.call(office, HttpMethod.POST, "/api/v1/attendance/jupeb/warn", null));
        assertThat(((Number) ((Map<String, Object>) warned.get("result")).get("sent")).intValue()).isGreaterThanOrEqualTo(1);
        assertThat(jdbc.sql("SELECT count(*) FROM jupeb.reminder_log WHERE application_id = :a AND kind = 'ATTENDANCE_LOW'").param("a", studentB).query(Integer.class).single()).isEqualTo(1);
        assertThat(jdbc.sql("SELECT count(*) FROM jupeb.reminder_log WHERE application_id = :a AND kind = 'ATTENDANCE_LOW'").param("a", studentA).query(Integer.class).single()).isZero();
        // once a day at most: warning again at once sends nothing more to the same student
        ok(it.call(office, HttpMethod.POST, "/api/v1/attendance/jupeb/warn", null));
        assertThat(jdbc.sql("SELECT count(*) FROM jupeb.reminder_log WHERE application_id = :a AND kind = 'ATTENDANCE_LOW'").param("a", studentB).query(Integer.class).single()).isEqualTo(1);
        // the student sees it on their own record
        List<Map<String, Object>> mineStanding = (List<Map<String, Object>>) ok(it.get(studentBToken, "/api/v1/jupeb/me")).get("attendanceStanding");
        assertThat(mineStanding).anySatisfy(r -> assertThat(r.get("verdict")).isEqualTo("NOT_ELIGIBLE"));
        // the lecturer's report reaches their own class only
        Map<String, Object> lec = ok(it.get(lecturer, ub -> ub.path("/api/v1/attendance/jupeb/reports").queryParam("session", session).build()));
        assertThat((List<Map<String, Object>>) lec.get("rows")).extracting(r -> r.get("member_ref")).containsExactly(studentA.toString());
    }
}
