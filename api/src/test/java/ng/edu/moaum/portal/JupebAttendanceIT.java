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

    /** V354: a lecture's register opened from its timetable slot, on its weekday, by its instructor only — two lectures of a subject a day,
     *  a register each; a lecture not held is not opened until the office withdraws that; the lectures due say which is which. The
     *  lecturer's workspace: their subjects and students only, and notices to the students of a subject (and class) they teach. */
    @Test
    void lecturesFromTheTimetableAndTheLecturersWorkspace() {
        String far = "2091/2092";
        UUID room = UUID.randomUUID();
        UUID person = jdbc.sql("SELECT id FROM iam.person WHERE staff_number = :s").param("s", staffNumber).query(UUID.class).single();
        List<String> slots = new java.util.ArrayList<>();
        try {
            it.db(() -> jdbc.sql("INSERT INTO jupeb.room (id, code) VALUES (:id, :c)").param("id", room).param("c", "ZZATT" + tag).update());
            int wd = LocalDate.now(java.time.ZoneId.of("Africa/Lagos")).getDayOfWeek().getValue();
            for (Object[] t : new Object[][] {{"10:00", "11:00", s1}, {"14:00", "15:00", s1}, {"16:00", "17:00", s2}}) {
                Map<String, Object> slot = Map.of("session", far, "semester", 1, "subjectId", t[2].toString(), "weekday", wd, "startsAt", t[0], "endsAt", t[1], "roomId", room.toString());
                slots.add(ok(it.call(office, HttpMethod.POST, "/api/v1/jupeb/office/timetable", slot)).get("id").toString());
            }
            assertThat(status(it.callList(office, HttpMethod.POST, "/api/v1/attendance/jupeb/instructors", Map.of("session", far, "subjectId", s1, "staff", staffNumber)))).isEqualTo(200);

            // the lecturer's lectures today: their subject's two, not the other subject's
            Map<String, Object> due = ok(it.get(lecturer, ub -> ub.path("/api/v1/attendance/jupeb/lectures").queryParam("session", far).build()));
            List<Map<String, Object>> rows = (List<Map<String, Object>>) due.get("rows");
            assertThat(rows).extracting(r -> r.get("slot_id").toString()).containsExactlyInAnyOrder(slots.get(0), slots.get(1));
            assertThat(rows).extracting(r -> r.get("state")).containsOnly("DUE");
            String today = due.get("today").toString();
            String reg = ok(it.call(lecturer, HttpMethod.POST, "/api/v1/attendance/jupeb/slots/" + slots.get(0) + "/register", Map.of("day", today))).get("id").toString();
            assertThat(ok(it.call(lecturer, HttpMethod.POST, "/api/v1/attendance/jupeb/slots/" + slots.get(0) + "/register", Map.of("day", today))).get("id").toString()).isEqualTo(reg);
            assertThat(code(it.call(lecturer, HttpMethod.POST, "/api/v1/attendance/jupeb/slots/" + slots.get(0) + "/register",
                    Map.of("day", LocalDate.parse(today).minusDays(1).toString())))).isEqualTo("ATT_SLOT_DAY");
            assertThat(status(it.call(lecturer, HttpMethod.POST, "/api/v1/attendance/jupeb/slots/" + slots.get(2) + "/register", Map.of("day", today)))).isEqualTo(403);

            // the other lecture not held: not opened; the lectures due say so; the office withdraws it and it is opened, a register of its own
            ok(it.call(lecturer, HttpMethod.POST, "/api/v1/attendance/jupeb/slots/" + slots.get(1) + "/not-held", Map.of("day", today, "reason", "The lecturer was at a workshop")));
            assertThat(code(it.call(lecturer, HttpMethod.POST, "/api/v1/attendance/jupeb/slots/" + slots.get(1) + "/register", Map.of("day", today)))).isEqualTo("JUPEB_LECTURE_NOT_HELD");
            rows = (List<Map<String, Object>>) ok(it.get(office, ub -> ub.path("/api/v1/attendance/jupeb/lectures").queryParam("session", far).build())).get("rows");
            assertThat(rows).anySatisfy(r -> { assertThat(r.get("slot_id").toString()).isEqualTo(slots.get(0)); assertThat(r.get("state")).isEqualTo("OPEN"); });
            assertThat(rows).anySatisfy(r -> { assertThat(r.get("slot_id").toString()).isEqualTo(slots.get(1)); assertThat(r.get("state")).isEqualTo("NOT_HELD"); });
            assertThat(status(it.call(lecturer, HttpMethod.POST, "/api/v1/attendance/jupeb/slots/" + slots.get(1) + "/not-held/withdraw", Map.of("day", today)))).isEqualTo(403);
            ok(it.call(office, HttpMethod.POST, "/api/v1/attendance/jupeb/slots/" + slots.get(1) + "/not-held/withdraw", Map.of("day", today)));
            String other = ok(it.call(lecturer, HttpMethod.POST, "/api/v1/attendance/jupeb/slots/" + slots.get(1) + "/register", Map.of("day", today))).get("id").toString();
            assertThat(other).isNotEqualTo(reg);

            // the workspace of the current session: assigned to s1, class A
            assertThat(status(it.callList(office, HttpMethod.POST, "/api/v1/attendance/jupeb/instructors",
                    Map.of("session", session, "subjectId", s1, "classId", classA, "staff", staffNumber)))).isEqualTo(200);
            Map<String, Object> ws = ok(it.get(lecturer, "/api/v1/jupeb/teaching"));
            assertThat((List<Map<String, Object>>) ws.get("assignments")).extracting(a -> a.get("subject_id").toString()).containsExactly(s1.toString());
            List<Map<String, Object>> students = (List<Map<String, Object>>) (List<?>) it.callList(lecturer, HttpMethod.GET, "/api/v1/jupeb/teaching/subjects/" + s1 + "/students", null).getBody();
            assertThat(students).extracting(x -> x.get("id").toString()).containsExactly(studentA.toString());
            assertThat(status(it.get(lecturer, "/api/v1/jupeb/teaching/subjects/" + s2 + "/students"))).isEqualTo(404);
            Map<String, Object> notice = ok(it.call(lecturer, HttpMethod.POST, "/api/v1/jupeb/teaching/notices",
                    Map.of("subjectId", s1, "classId", classA, "title", "Test on cells", "body", "The class test on cells is on Friday.")));
            assertThat(notice.get("reach")).isEqualTo(1);
            assertThat(status(it.call(lecturer, HttpMethod.POST, "/api/v1/jupeb/teaching/notices", Map.of("subjectId", s1, "title", "Everyone", "body", "To every class.")))).isEqualTo(403);
            assertThat(status(it.call(lecturer, HttpMethod.POST, "/api/v1/jupeb/teaching/notices", Map.of("subjectId", s2, "classId", classA, "title", "Not mine", "body", "Another subject.")))).isEqualTo(403);
            assertThat(status(it.get(office, "/api/v1/jupeb/teaching"))).isEqualTo(403);
            String a = TestTokens.token(studentA, List.of("applicant"));
            String b = TestTokens.token(studentB, List.of("applicant"));
            assertThat((List<Map<String, Object>>) ok(it.get(a, "/api/v1/jupeb/me/announcements")).get("announcements")).extracting(n -> n.get("title")).contains("Test on cells");
            assertThat((List<Map<String, Object>>) ok(it.get(b, "/api/v1/jupeb/me/announcements")).get("announcements")).extracting(n -> n.get("title")).doesNotContain("Test on cells");
        } finally {
            it.db(() -> {
                for (String id : slots) {
                    jdbc.sql("DELETE FROM jupeb.lecture_not_held WHERE slot_id = :s::uuid").param("s", id).update();
                    jdbc.sql("DELETE FROM attendance.mark WHERE register_id IN (SELECT id FROM attendance.register WHERE slot_ref = :s::uuid)").param("s", id).update();
                    jdbc.sql("DELETE FROM attendance.register WHERE slot_ref = :s::uuid").param("s", id).update();
                    jdbc.sql("DELETE FROM jupeb.timetable_slot WHERE id = :s::uuid").param("s", id).update();
                }
                jdbc.sql("DELETE FROM attendance.instructor WHERE session = '2091/2092' AND person_id = :p").param("p", person).update();
                jdbc.sql("DELETE FROM jupeb.room WHERE id = :r").param("r", room).update();
                return null;
            });
        }
    }

    /** V355: the topics a lecture covered, ticked by its instructor with the register and counted to the course's coverage (a lecturer
     *  sees their own subjects'); the continuous assessment a lecturer enters — their classes' students only, within each part's
     *  maximum, not once the office has locked the subject */
    @Test
    void topicsCoveredAndTheLecturersAssessment() {
        UUID unit = UUID.randomUUID();
        UUID part = UUID.randomUUID();
        StringBuilder letters = new StringBuilder();
        for (char c : tag.toCharArray()) letters.append(Character.isDigit(c) ? (char) ('G' + (c - '0')) : c);
        String course = "ZQ" + letters.substring(0, 3) + " 001";
        List<UUID> topics = List.of(UUID.randomUUID(), UUID.randomUUID(), UUID.randomUUID());
        try {
            it.db(() -> {
                jdbc.sql("INSERT INTO jupeb.subject_unit (id, subject_id, code, title, ord, semester) VALUES (:id, :s, :c, 'Cells and tissues', 1, 1)")
                        .param("id", unit).param("s", s1).param("c", course).update();
                for (int i = 0; i < topics.size(); i++) {
                    jdbc.sql("INSERT INTO jupeb.unit_topic (id, unit_id, ord, sn, topic) VALUES (:id, :u, :o, :sn, :t)").param("id", topics.get(i)).param("u", unit)
                            .param("o", i + 1).param("sn", String.valueOf(i + 1)).param("t", "Topic " + (i + 1)).update();
                }
                return jdbc.sql("INSERT INTO jupeb.ca_component (id, session, code, title, max_score) VALUES (:id, :s, :c, 'Class test', 20)").param("id", part).param("s", session)
                        .param("c", "ZZ" + tag).update();
            });
            assertThat(status(it.callList(office, HttpMethod.POST, "/api/v1/attendance/jupeb/instructors",
                    Map.of("session", session, "subjectId", s1, "classId", classA, "staff", staffNumber)))).isEqualTo(200);

            // the register's topics: its course's; two ticked; a topic of no course of the lecture refused; another lecturer not let in
            String reg = String.valueOf(open(lecturer, s1, classA).get("id"));
            String path = "/api/v1/attendance/jupeb/registers/" + reg + "/topics";
            List<Map<String, Object>> list = it.callList(lecturer, HttpMethod.GET, path, null).getBody();
            assertThat(list).extracting(x -> x.get("topic_id").toString()).containsExactly(topics.get(0).toString(), topics.get(1).toString(), topics.get(2).toString());
            list = it.callList(lecturer, HttpMethod.PUT, path, Map.of("topicIds", List.of(topics.get(0), topics.get(1)))).getBody();
            assertThat(list).filteredOn(x -> Boolean.TRUE.equals(x.get("here"))).hasSize(2);
            assertThat(list).filteredOn(x -> Boolean.TRUE.equals(x.get("here"))).extracting(x -> x.get("first_on")).containsOnly(LocalDate.now(java.time.ZoneId.of("Africa/Lagos")).toString());
            assertThat(code(it.call(lecturer, HttpMethod.PUT, path, Map.of("topicIds", List.of(UUID.randomUUID()))))).isEqualTo("JUPEB_COVERAGE_TOPIC");
            String stranger = TestTokens.token(it.person("ZZATT-LEC2-" + tag, "ZZATTSTRANGER"), List.of("lecturer"));
            assertThat(status(it.call(stranger, HttpMethod.PUT, path, Map.of("topicIds", List.of(topics.get(2)))))).isEqualTo(404);
            Map<String, Object> cov = ok(it.get(lecturer, ub -> ub.path("/api/v1/attendance/jupeb/coverage").queryParam("session", session).queryParam("semester", 1).build()));
            List<Map<String, Object>> rows = (List<Map<String, Object>>) cov.get("rows");
            assertThat(rows).extracting(r -> r.get("subject_id").toString()).containsOnly(s1.toString());
            assertThat(rows).filteredOn(r -> course.equals(r.get("code"))).extracting(r -> r.get("covered") + "/" + r.get("topics")).containsExactly("2/3");
            assertThat((List<Map<String, Object>>) ok(it.get(stranger, ub -> ub.path("/api/v1/attendance/jupeb/coverage").queryParam("session", session).queryParam("semester", 1).build()))
                    .get("rows")).isEmpty();

            // the lecturer's assessment: class A's student only; within the maximum; not another class's; not once locked
            Map<String, Object> sheet = ok(it.get(lecturer, "/api/v1/jupeb/teaching/ca?subject=" + s1));
            assertThat((List<Map<String, Object>>) sheet.get("rows")).extracting(r -> r.get("application_id").toString()).containsExactly(studentA.toString());
            assertThat(status(it.get(lecturer, "/api/v1/jupeb/teaching/ca?subject=" + s2))).isEqualTo(404);
            assertThat(code(it.call(lecturer, HttpMethod.PUT, "/api/v1/jupeb/teaching/ca",
                    Map.of("subjectId", s1, "scores", List.of(Map.of("applicationId", studentA, "componentId", part, "score", 21)))))).isEqualTo("JUPEB_CA_RANGE");
            assertThat(status(it.call(lecturer, HttpMethod.PUT, "/api/v1/jupeb/teaching/ca",
                    Map.of("subjectId", s1, "scores", List.of(Map.of("applicationId", studentB, "componentId", part, "score", 12)))))).isEqualTo(403);
            sheet = ok(it.call(lecturer, HttpMethod.PUT, "/api/v1/jupeb/teaching/ca",
                    Map.of("subjectId", s1, "scores", List.of(Map.of("applicationId", studentA, "componentId", part, "score", 17.5)))));
            Map<String, Object> scores = (Map<String, Object>) ((List<Map<String, Object>>) sheet.get("rows")).get(0).get("scores");
            assertThat(new java.math.BigDecimal(String.valueOf(scores.get(part.toString())))).isEqualByComparingTo("17.5");
            assertThat(jdbc.sql("SELECT entered_office FROM jupeb.ca_score WHERE application_id = :a AND component_id = :c").param("a", studentA).param("c", part)
                    .query(String.class).single()).isEqualTo("lecturer");
            ok(it.call(office, HttpMethod.POST, "/api/v1/jupeb/office/ca/lock", Map.of("session", session, "subjectId", s1)));
            assertThat(code(it.call(lecturer, HttpMethod.PUT, "/api/v1/jupeb/teaching/ca",
                    Map.of("subjectId", s1, "scores", List.of(Map.of("applicationId", studentA, "componentId", part, "score", 18)))))).isEqualTo("JUPEB_CA_LOCKED");
            assertThat(status(it.callList(lecturer, HttpMethod.GET, "/api/v1/jupeb/teaching/topics?subject=" + s1, null))).isEqualTo(200);
        } finally {
            it.db(() -> {
                jdbc.sql("DELETE FROM jupeb.lecture_topic WHERE topic_id IN (SELECT id FROM jupeb.unit_topic WHERE unit_id = :u)").param("u", unit).update();
                jdbc.sql("DELETE FROM jupeb.unit_topic WHERE unit_id = :u").param("u", unit).update();
                jdbc.sql("DELETE FROM jupeb.subject_unit WHERE id = :u").param("u", unit).update();
                jdbc.sql("DELETE FROM jupeb.ca_score WHERE component_id = :c").param("c", part).update();
                jdbc.sql("DELETE FROM jupeb.ca_lock WHERE session = :s AND subject_id = :x").param("s", session).param("x", s1).update();
                return jdbc.sql("DELETE FROM jupeb.ca_component WHERE id = :c").param("c", part).update();
            });
        }
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
