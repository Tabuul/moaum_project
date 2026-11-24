package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.math.BigDecimal;
import java.nio.charset.StandardCharsets;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.stream.Collectors;
import java.util.stream.IntStream;

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
 * V779 — the Summer Semester open to every final-year and spillover student, whose courses the Academic Office verifies, through the
 * API. A final-year student with no result on the portal at all reads the programme's courses of both semesters, selects a
 * first-semester and a second-semester course no result confirms, pays the fees (₦50,000 and ₦5,000 a course) and is registered,
 * each course Pending verification and typed as a student's own, never a carry-over; a spillover student recorded at 100 Level
 * selects a 300 Level course; the Academic Office confirms one of the first student's and rejects the other with a reason — the
 * paid entry is withdrawn, its fee becomes a Summer credit on the Bursar's page that the Bursar settles, the student reads the
 * reason; a student, a Head of Department and a Dean see and do only what their office allows, a selection of another department is
 * a 404; the CSVs are text/csv with the byte order mark, a name that looks like a formula is made plain, and each leaves a row on
 * the export log; the printable confirmation never calls a chosen course a carry-over; the server, not the form, refuses a course
 * outside the pool, more than 30 at once and more than the ceiling. Results published after a selection are reconciled — an unpaid
 * course taken back, a paid one flagged, nothing again on a second run; the examinations do not open over paid courses nobody has
 * verified until the Office records why, and again when more arrive; the notices walk their audience by a cursor; ICT Support's
 * read-only view reads the page and the card and changes nothing; a paid course the Director of ICT removes is flagged for the
 * Office and, once the Office decides it, its removal cannot be undone. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class SummerVerificationIT {

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

    String student(UUID id) {
        return TestTokens.token(id, List.of("student"));
    }

    /** one invented Summer: two sessions (the later one made CURRENT, the calendar put back by {@link #close}), a programme of the
     *  run's own with four core courses and an elective in its structure, the Bursary's fee published, and the Summer open */
    final class Scene {
        final String before, session, path, prog, dept, faculty, otherDept, otherFaculty, px, yy;
        final String c1, c2, c3, c4, elective;
        final int n;
        private final String beforeState, sessionState, previousCurrent;

        Scene(int minYear, int bound) {
            int y = it.freeYear(minYear, bound, 1, 1);
            before = (y - 1) + "/" + y;
            session = y + "/" + (y + 1);
            path = "/api/v1/summer/" + session;
            it.session(before, y - 1);
            it.session(session, y);
            beforeState = jdbc.sql("SELECT state FROM policy.academic_session WHERE name = :n").param("n", before).query(String.class).single();
            sessionState = jdbc.sql("SELECT state FROM policy.academic_session WHERE name = :n").param("n", session).query(String.class).single();
            previousCurrent = jdbc.sql("SELECT name FROM policy.academic_session WHERE state = 'CURRENT' ORDER BY starts_on DESC LIMIT 1").query(String.class).optional().orElse(null);
            px = it.freeCoursePrefix("Z");
            yy = String.format("%02d", y % 100);
            n = it.freeDraw(1000, 9000, k -> {
                List<String> ids = new ArrayList<>();
                for (String l : List.of("A", "B", "E", "F", "G", "H")) ids.add("ZZSUMV" + l + k);
                for (int i = 0; i < 6; i++) ids.add("MOAU/" + px + "/" + yy + "/" + (k + i));
                return ids;
            });
            String[] place = it.db(() -> jdbc.sql("""
                    SELECT p.dept_code || ',' || p.faculty_code FROM ref.programme p JOIN ref.faculty f ON f.code = p.faculty_code
                     WHERE p.category = 'UNDER GRADUATE' AND NOT p.archived AND p.dept_code IS NOT NULL AND coalesce(f.college_code, '') <> 'CHS'
                     ORDER BY p.code LIMIT 1
                    """).query(String.class).single().split(","));
            dept = place[0];
            faculty = place[1];
            String[] other = jdbc.sql("SELECT d.code || ',' || d.faculty_code FROM ref.department d WHERE d.ended_on IS NULL AND d.faculty_code <> :f ORDER BY d.code LIMIT 1")
                    .param("f", faculty).query(String.class).single().split(",");
            otherDept = other[0];
            otherFaculty = other[1];
            prog = jdbc.sql("""
                    SELECT 'C' || lpad(k::text, 5, '0') FROM generate_series(95000, 95999) k
                     WHERE NOT EXISTS (SELECT 1 FROM ref.programme p WHERE p.code = 'C' || lpad(k::text, 5, '0'))
                     ORDER BY random() LIMIT 1
                    """).query(String.class).single();
            c1 = px + " 401";
            c2 = px + " 402";
            c3 = px + " 301";
            c4 = px + " 302";
            elective = px + " 405";
            it.db(() -> {
                jdbc.sql("UPDATE policy.academic_session SET state = 'CLOSED' WHERE state = 'CURRENT'").update();
                jdbc.sql("UPDATE policy.academic_session SET state = 'CLOSED' WHERE name = :n").param("n", before).update();
                jdbc.sql("UPDATE policy.academic_session SET state = 'CURRENT', senate_minute = coalesce(senate_minute, 'SEN/IT/779') WHERE name = :n").param("n", session).update();
                jdbc.sql("""
                        INSERT INTO ref.programme (code, name, dept_code, faculty_code, category, min_score, final_level, duration_years, matric_code)
                        SELECT :p, 'B.Sc. Summer Verification IT ' || :p, d.code, d.faculty_code, 'UNDER GRADUATE', 0, 400, 4, :x FROM ref.department d WHERE d.code = :d
                        ON CONFLICT (code) DO NOTHING
                        """).param("p", prog).param("d", dept).param("x", px).update();
                for (Object[] c : new Object[][] {{c1, 3, 1, 400, "Core"}, {c2, 2, 2, 400, "Core"}, {c3, 3, 1, 300, "Core"}, {c4, 2, 2, 300, "Core"}, {elective, 2, 1, 400, "Elective"}}) {
                    jdbc.sql("INSERT INTO catalogue.course (code, title, units, semester, level, dept_code, kind, state) VALUES (:c, 'Summer Verification ' || :c, :u, :s, :l, :d, :k, 'LIVE') ON CONFLICT (code) DO NOTHING")
                            .param("c", c[0]).param("u", c[1]).param("s", c[2]).param("l", c[3]).param("d", dept).param("k", c[4]).update();
                    jdbc.sql("INSERT INTO catalogue.course_offer (course_code, programme_code, level, basis) VALUES (:c, :p, :l, :k) ON CONFLICT DO NOTHING")
                            .param("c", c[0]).param("p", prog).param("l", c[3]).param("k", c[4]).update();
                }
                return null;
            });
            // the Bursary's fee, the Academic Office's period: the Summer is open
            ResponseEntity<Map> stated = it.call(ItSupport.token("studentaccounts"), HttpMethod.POST, "/api/v1/finance/summer-fees",
                    Map.of("session", session, "programme", prog, "programmeFee", 50000, "courseFee", 5000, "reason", "The Summer fees approved by management"));
            assertThat(stated.getStatusCode().value()).as(String.valueOf(stated.getBody())).isEqualTo(200);
            assertThat(it.call(ItSupport.token("bursar"), HttpMethod.POST, "/api/v1/finance/summer-fees/" + stated.getBody().get("id") + "/publish", Map.of()).getStatusCode().value()).isEqualTo(200);
            ResponseEntity<Map> set = it.call(ItSupport.token("academic"), HttpMethod.PUT, path, period("OPEN"));
            assertThat(set.getStatusCode().value()).as(String.valueOf(set.getBody())).isEqualTo(200);
            assertThat(set.getBody()).containsEntry("open_now", true);
        }

        Map<String, Object> period(String state) {
            Map<String, Object> m = new HashMap<>();
            m.put("state", state);
            m.put("registrationOpens", LocalDate.now().minusDays(1).toString());
            m.put("registrationCloses", LocalDate.now().plusDays(10).toString());
            m.put("examsFrom", LocalDate.now().plusDays(20).toString());
            m.put("examsTo", LocalDate.now().plusDays(25).toString());
            m.put("resultsDue", LocalDate.now().plusDays(30).toString());
            m.put("categories", List.of("FINAL_YEAR", "SPILLOVER", "BEYOND_DURATION", "AUTHORISED"));
            m.put("reason", "The Summer of the session, Senate approved");
            return m;
        }

        String matric(int k) {
            return "MOAU/" + px + "/" + yy + "/" + (n + k);
        }

        /** an invented student of the programme: letter and k as the draw named them */
        UUID student(String letter, int k, int level) {
            return named("ZZSUMV" + letter + n, k, level);
        }

        /** the same, with the surname given; the student entered in the session before this Summer's (the engine reads a first-year student, not
         *  one who has been here for thousands of years of the calendar) */
        UUID named(String surname, int k, int level) {
            UUID id = it.student(surname, prog, null, matric(k), level);
            it.db(() -> jdbc.sql("UPDATE people.student SET entry_session = :e WHERE id = :id").param("e", before).param("id", id).update());
            return id;
        }

        /** the calendar put back */
        void close() {
            it.db(() -> {
                jdbc.sql("UPDATE policy.academic_session SET state = :st WHERE name = :n").param("st", sessionState).param("n", session).update();
                jdbc.sql("UPDATE policy.academic_session SET state = :st WHERE name = :n").param("st", beforeState).param("n", before).update();
                if (previousCurrent != null && !previousCurrent.equals(session)) jdbc.sql("UPDATE policy.academic_session SET state = 'CURRENT' WHERE name = :n").param("n", previousCurrent).update();
                return null;
            });
        }
    }

    /* ── helpers ── */

    Map<String, Object> mine(String token, Scene s) {
        ResponseEntity<Map> r = it.get(token, "/api/v1/me/summer?session=" + s.session);
        assertThat(r.getStatusCode().value()).as(String.valueOf(r.getBody())).isEqualTo(200);
        return r.getBody();
    }

    List<Map<String, Object>> coursesOf(Map<String, Object> page) {
        return (List<Map<String, Object>>) page.get("courses");
    }

    Map<String, Object> row(Map<String, Object> page, String code) {
        return coursesOf(page).stream().filter(c -> code.equals(c.get("course_code"))).findFirst().orElseThrow(() -> new AssertionError("no course " + code + " on the page"));
    }

    UUID selection(Map<String, Object> page, String code) {
        return UUID.fromString(String.valueOf(row(page, code).get("selection_id")));
    }

    ResponseEntity<Map> select(String token, Scene s, String... codes) {
        return it.call(token, HttpMethod.POST, "/api/v1/me/summer/select", Map.of("session", s.session, "courses", List.of(codes)));
    }

    /** the reference for what is owed, paid by the bank's confirmation as the Bursary's lane records it */
    String pay(String token, Scene s) {
        ResponseEntity<Map> ref = it.call(token, HttpMethod.POST, "/api/v1/me/summer/reference", Map.of("session", s.session));
        assertThat(ref.getStatusCode().value()).as(String.valueOf(ref.getBody())).isEqualTo(200);
        String reference = String.valueOf(ref.getBody().get("reference"));
        confirm(reference);
        return reference;
    }

    void confirm(String reference) {
        it.db(() -> {
            jdbc.sql("SELECT set_config('moaum.actor_office', 'bursar', true)").query().listOfRows();
            return jdbc.sql("SELECT finance.confirm_payment(:r, 'Bank transfer', 'SummerVerificationIT')").param("r", reference).query(String.class).single();
        });
    }

    String entry(UUID student, Scene s, String course, String column) {
        return jdbc.sql("SELECT e." + column + " FROM registration.entry e JOIN registration.course_registration r ON r.id = e.registration_id "
                + "JOIN catalogue.offering o ON o.id = e.offering_id WHERE r.student_id = :st AND r.session = :s AND r.semester = 3 AND o.course_code = :c ORDER BY e.status LIMIT 1")
                .param("st", student).param("s", s.session).param("c", course).query(String.class).optional().orElse(null);
    }

    static BigDecimal money(Object o) {
        return new BigDecimal(String.valueOf(o));
    }

    /** the queue page's row of a selection */
    static Map<String, Object> queueRow(Map<String, Object> queue, UUID selection) {
        return ((List<Map<String, Object>>) queue.get("rows")).stream().filter(r -> selection.toString().equals(String.valueOf(r.get("selection_id"))))
                .findFirst().orElseThrow(() -> new AssertionError("no queue row for " + selection + " in " + queue.get("rows")));
    }

    /** the three money keys of a queue row (and of the selection read in full): the course's live charge, the programme fee paid
     *  (absent or null when none is paid) and the student's courses with a live charge */
    static void assertMoneyKeys(Map<String, Object> row, String charge, String programmeFeePaid, int standing) {
        assertThat(money(row.get("charge_amount"))).as("charge_amount of " + row).isEqualByComparingTo(charge);
        if (programmeFeePaid == null) {
            assertThat(row.get("programme_fee_paid")).as("programme_fee_paid of " + row).isNull();
        } else {
            assertThat(money(row.get("programme_fee_paid"))).as("programme_fee_paid of " + row).isEqualByComparingTo(programmeFeePaid);
        }
        assertThat(((Number) row.get("courses_standing")).intValue()).as("courses_standing of " + row).isEqualTo(standing);
    }

    ResponseEntity<Map> decide(Scene s, String token, List<UUID> ids, String decision, String reason) {
        Map<String, Object> body = new HashMap<>();
        body.put("ids", ids.stream().map(UUID::toString).toList());
        body.put("decision", decision);
        body.put("reason", reason);
        return it.call(token, HttpMethod.POST, s.path + "/selections/decide", body);
    }

    /** the students' positions: an engine that counts the student in spillover (the position is derived; the test says what it derives) */
    void spillover(UUID student) {
        it.db(() -> {
            jdbc.sql("SELECT people.refresh_academic_position(:s)").param("s", student).query().listOfRows();
            return jdbc.sql("UPDATE people.academic_position SET spillover_state = 'SPILLOVER_YEAR_1', spillover_years = 1 WHERE student_id = :s").param("s", student).update();
        });
    }

    ResponseEntity<Map> tell(String token, Scene s, int limit, String after) {
        Map<String, Object> body = new HashMap<>();
        body.put("kind", "OPEN");
        body.put("limit", limit);
        if (after != null) body.put("after", after);
        ResponseEntity<Map> r = it.call(token, HttpMethod.POST, s.path + "/tell", body);
        assertThat(r.getStatusCode().value()).as(String.valueOf(r.getBody())).isEqualTo(200);
        return r;
    }

    /** the whole audience told in large tranches from a cursor to its end (null: the start); how many were told */
    long walk(String token, Scene s, String cursor) {
        long told = 0;
        for (int i = 0; i < 400; i++) {
            ResponseEntity<Map> r = tell(token, s, 2000, cursor);
            told += ((Number) r.getBody().get("told")).longValue();
            if (r.getBody().get("next") == null) {
                assertThat(((Number) r.getBody().get("remaining")).longValue()).isZero();
                return told;
            }
            cursor = String.valueOf(r.getBody().get("next"));
        }
        throw new AssertionError("the audience was not walked to its end");
    }

    long exportRows(String report) {
        return jdbc.sql("SELECT count(*) FROM platform.export_log WHERE report = :r AND format = 'CSV'").param("r", report).query(Long.class).single();
    }

    /* ── the journey ── */

    @Test
    void aStudentSelectsWithNoResultOnThePortalAndTheAcademicOfficeVerifiesWhatWasPaid() {
        Scene s = new Scene(4000, 4700);
        try {
            UUID a = s.student("A", 0, 400);
            UUID b = s.student("B", 1, 100);
            // a student whose name begins like a spreadsheet formula, in the same programme
            UUID f = s.named("=ZZSUMVF" + s.n, 3, 400);
            spillover(b);
            String ta = student(a), tb = student(b), tf = student(f);

            // ── 1: a final-year student with no result at all reads the programme's courses of both semesters ──
            Map<String, Object> page = mine(ta, s);
            assertThat((Map<String, Object>) page.get("eligibility")).containsEntry("eligible", true).containsEntry("category", "FINAL_YEAR");
            assertThat(coursesOf(page)).extracting(c -> c.get("course_code")).contains(s.c1, s.c2, s.c3, s.c4).doesNotContain(s.elective);
            assertThat(row(page, s.c1)).containsEntry("selectable", true).containsEntry("evidence", "NO_RESULT").containsEntry("source", "STRUCTURE").containsEntry("course_semester", 1);
            assertThat(row(page, s.c2)).containsEntry("course_semester", 2).containsEntry("level", 400);
            assertThat(page.get("registered")).isEqualTo(List.of());

            // the server, not the form, refuses a course outside the pool, too many at once, and more than the ceiling
            ResponseEntity<Map> outside = select(ta, s, s.elective);
            assertThat(outside.getStatusCode().value()).isEqualTo(422);
            assertThat(outside.getBody()).containsEntry("code", "SUMMER_COURSE_NOT_AVAILABLE");
            ResponseEntity<Map> nothing = select(ta, s, s.px + " 999");
            assertThat(nothing.getBody()).containsEntry("code", "SUMMER_COURSE_NOT_AVAILABLE");
            // a code as long as the catalogue allows (20 characters, V776) reaches the database's own answer on every door; 21 is no course code
            String twenty = (s.px + " 40123456789ABCDEFGHIJ").substring(0, 20);
            ResponseEntity<Map> longCode = select(ta, s, twenty);
            assertThat(longCode.getStatusCode().value()).as(String.valueOf(longCode.getBody())).isEqualTo(422);
            assertThat(longCode.getBody()).containsEntry("code", "SUMMER_COURSE_NOT_AVAILABLE");
            assertThat(select(ta, s, twenty + "K").getStatusCode().value()).isEqualTo(400);
            assertThat(it.call(ta, HttpMethod.POST, "/api/v1/me/summer/unselect", Map.of("session", s.session, "course", twenty)).getBody()).containsEntry("code", "SUMMER_NOT_SELECTED");
            assertThat(it.call(ta, HttpMethod.POST, "/api/v1/me/summer/note", Map.of("session", s.session, "course", twenty, "note", "I owe it")).getBody()).containsEntry("code", "SUMMER_NOT_YOURS");
            List<String> thirtyOne = IntStream.range(0, 31).mapToObj(i -> s.px + " " + (600 + i)).toList();
            ResponseEntity<Map> many = it.call(ta, HttpMethod.POST, "/api/v1/me/summer/select", Map.of("session", s.session, "courses", thirtyOne));
            assertThat(many.getStatusCode().value()).isEqualTo(422);
            assertThat(many.getBody()).containsEntry("code", "SUMMER_TOO_MANY");
            List<String> twoHundredAndOne = IntStream.range(0, 201).mapToObj(i -> "Z" + i).toList();
            assertThat(it.call(ta, HttpMethod.POST, "/api/v1/me/summer/select", Map.of("session", s.session, "courses", twoHundredAndOne)).getStatusCode().value()).isEqualTo(400);

            // a first- and a second-semester course no result confirms: both Pending verification, never a carry-over, ₦60,000 and the server says so
            ResponseEntity<Map> chosen = select(ta, s, s.c1, s.c2);
            assertThat(chosen.getStatusCode().value()).as(String.valueOf(chosen.getBody())).isEqualTo(200);
            Map<String, Object> afterSelect = chosen.getBody();
            assertThat(row(afterSelect, s.c1)).containsEntry("verification", "PENDING_VERIFICATION").containsEntry("basis", "STUDENT_SELECTED").containsEntry("status", "SELECTED");
            assertThat(row(afterSelect, s.c2)).containsEntry("verification", "PENDING_VERIFICATION").containsEntry("basis", "STUDENT_SELECTED");
            assertThat(money(((Map<String, Object>) afterSelect.get("account")).get("due"))).isEqualByComparingTo("60000");
            Map<String, Object> summary = (Map<String, Object>) afterSelect.get("summary");
            assertThat(summary).containsEntry("selected", 2).containsEntry("pending", 2);
            assertThat(money(((Map<String, Object>) summary.get("formula")).get("total"))).isEqualByComparingTo("60000");
            // the same course again is refused, and costs nothing
            assertThat(select(ta, s, s.c1).getBody()).containsEntry("code", "SUMMER_COURSE_REFUSED");

            // the ceiling: a course more than it allows is refused (the Academic Office may set it, a reader may not)
            assertThat(it.call(ItSupport.token("bursar"), HttpMethod.PUT, s.path + "/ceiling", Map.of("maxCourses", 2, "reason", "Two courses a student this Summer")).getStatusCode().value()).isEqualTo(403);
            ResponseEntity<Map> ceiling = it.call(ItSupport.token("academic"), HttpMethod.PUT, s.path + "/ceiling", Map.of("maxCourses", 2, "reason", "Two courses a student this Summer"));
            assertThat(ceiling.getStatusCode().value()).as(String.valueOf(ceiling.getBody())).isEqualTo(200);
            assertThat(ceiling.getBody()).containsEntry("max_courses", 2);
            assertThat(it.call(ItSupport.token("academic"), HttpMethod.PUT, s.path + "/ceiling", Map.of("maxCourses", 0, "reason", "No courses at all, said the Board")).getBody()).containsEntry("code", "SUMMER_CEILING_RANGE");
            assertThat(it.call(ItSupport.token("academic"), HttpMethod.PUT, s.path + "/ceiling", Map.of("maxCourses", 61, "reason", "Too many courses, said the Board")).getBody()).containsEntry("code", "SUMMER_CEILING_RANGE");
            ResponseEntity<Map> over = select(ta, s, s.c3);
            assertThat(over.getStatusCode().value()).isEqualTo(422);
            assertThat(over.getBody()).containsEntry("code", "SUMMER_CEILING");
            assertThat(it.call(ItSupport.token("academic"), HttpMethod.PUT, s.path + "/ceiling", java.util.Collections.singletonMap("reason", "No ceiling after all, said")).getStatusCode().value()).isEqualTo(200);

            // paid: both registered as the student's own courses, typed CURRENT (a carry-over is a confirmed one)
            String reference = pay(ta, s);
            Map<String, Object> paid = mine(ta, s);
            assertThat((List<Map<String, Object>>) paid.get("registered")).extracting(x -> x.get("course_code"), x -> x.get("verification"), x -> x.get("basis"), x -> x.get("category_label"))
                    .containsExactlyInAnyOrder(org.assertj.core.groups.Tuple.tuple(s.c1, "PENDING_VERIFICATION", "STUDENT_SELECTED", "Student-selected course"),
                            org.assertj.core.groups.Tuple.tuple(s.c2, "PENDING_VERIFICATION", "STUDENT_SELECTED", "Student-selected course"));
            assertThat(entry(a, s, s.c1, "entry_type")).isEqualTo("CURRENT");
            assertThat(entry(a, s, s.c2, "entry_type")).isEqualTo("CURRENT");
            assertThat(row(paid, s.c1)).containsEntry("status", "REGISTERED");

            // the public check of the registration (the QR on the printed confirmation) says each course is pending verification, never a carry-over
            Map<String, Object> code = it.get(ta, "/api/v1/me/check-code?kind=REG&session=" + s.session + "&semester=3").getBody();
            Map<String, Object> checked = it.anon(HttpMethod.GET, "/api/v1/verify/registration?matric=" + s.matric(0) + "&session=" + s.session + "&semester=3&c=" + code.get("code"), null).getBody();
            assertThat(checked).containsEntry("genuine", true).containsEntry("summer", true);
            assertThat((List<Map<String, Object>>) checked.get("courses")).extracting(c -> c.get("course_code"), c -> c.get("verification"), c -> c.get("entry_type"))
                    .containsExactlyInAnyOrder(org.assertj.core.groups.Tuple.tuple(s.c1, "PENDING_VERIFICATION", "CURRENT"), org.assertj.core.groups.Tuple.tuple(s.c2, "PENDING_VERIFICATION", "CURRENT"));

            // ── 8: the printable confirmation: no carry-over label for a course the student chose; a student with nothing has none ──
            ResponseEntity<Map> confirmation = it.get(ta, "/api/v1/me/summer/confirmation?session=" + s.session);
            assertThat(confirmation.getStatusCode().value()).as(String.valueOf(confirmation.getBody())).isEqualTo(200);
            assertThat(confirmation.getBody()).containsEntry("status", "REGISTERED");
            List<Map<String, Object>> confirmationRows = (List<Map<String, Object>>) confirmation.getBody().get("rows");
            assertThat(confirmationRows).extracting(r -> r.get("course_code")).containsExactlyInAnyOrder(s.c1, s.c2);
            assertThat(confirmationRows).allSatisfy(r -> assertThat(r).containsEntry("category_label", "Student-selected course").containsEntry("verification", "PENDING_VERIFICATION"));
            assertThat(confirmationRows).noneMatch(r -> String.valueOf(r.get("category_label")).contains("Carry-over"));
            assertThat(it.get(tf, "/api/v1/me/summer/confirmation?session=" + s.session).getStatusCode().value()).isEqualTo(404);

            // ── 2: a spillover student recorded at 100 selects a 300 Level course of the programme ──
            spillover(b);
            Map<String, Object> pageB = mine(tb, s);
            assertThat((Map<String, Object>) pageB.get("eligibility")).containsEntry("eligible", true).containsEntry("category", "SPILLOVER");
            assertThat(row(pageB, s.c3)).containsEntry("selectable", true).containsEntry("level", 300);
            // where the student says they owe it: a Summer is no semester to have failed in, so the database refuses it, and takes the true word
            ResponseEntity<Map> badOrigin = it.call(tb, HttpMethod.POST, "/api/v1/me/summer/select",
                    Map.of("session", s.session, "courses", List.of(s.c3), "origins", List.of(Map.of("course", s.c3, "session", s.before, "semester", 3))));
            assertThat(badOrigin.getStatusCode().value()).isEqualTo(422);
            assertThat(badOrigin.getBody()).containsEntry("code", "SUMMER_ORIGIN_INVALID");
            ResponseEntity<Map> chosenB = it.call(tb, HttpMethod.POST, "/api/v1/me/summer/select",
                    Map.of("session", s.session, "courses", List.of(s.c3), "origins", List.of(Map.of("course", s.c3, "session", s.before, "semester", 1))));
            assertThat(chosenB.getStatusCode().value()).as(String.valueOf(chosenB.getBody())).isEqualTo(200);
            assertThat(row(chosenB.getBody(), s.c3)).containsEntry("verification", "PENDING_VERIFICATION").containsEntry("original_session", s.before)
                    .containsEntry("original_semester", 1).containsEntry("original_source", "STUDENT");
            // the Academic Office asks the student about it, the student answers on the page; neither moves the state
            UUID selC3 = selection(chosenB.getBody(), s.c3);
            String officeToken = ItSupport.token("academic");
            assertThat(it.call(officeToken, HttpMethod.POST, s.path + "/selections/" + selC3 + "/clarify", Map.of("note", "short")).getBody()).containsEntry("code", "SUMMER_NOTE");
            assertThat(it.call(ItSupport.token("bursar"), HttpMethod.POST, s.path + "/selections/" + selC3 + "/clarify", Map.of("note", "Which session did you fail it in?")).getStatusCode().value()).isEqualTo(403);
            assertThat(it.call(officeToken, HttpMethod.POST, s.path + "/selections/" + selC3 + "/clarify", Map.of("note", "Which session did you fail it in?")).getStatusCode().value()).isEqualTo(200);
            Map<String, Object> asked = mine(tb, s);
            assertThat(row(asked, s.c3)).containsEntry("clarification_open", true).containsEntry("clarification_note", "Which session did you fail it in?").containsEntry("verification", "PENDING_VERIFICATION");
            assertThat((Map<String, Object>) asked.get("summary")).containsEntry("clarifications", 1);
            assertThat(it.call(tb, HttpMethod.POST, "/api/v1/me/summer/note", Map.of("session", s.session, "course", s.c3, "note", "x".repeat(501))).getBody()).containsEntry("code", "SUMMER_NOTE_LONG");
            assertThat(it.call(ta, HttpMethod.POST, "/api/v1/me/summer/note", Map.of("session", s.session, "course", s.c3, "note", "That is not my selection")).getBody()).containsEntry("code", "SUMMER_NOT_YOURS");
            assertThat(it.call(tb, HttpMethod.POST, "/api/v1/me/summer/note", Map.of("session", s.session, "course", s.c3, "note", "I failed it in my second year")).getBody()).containsEntry("ok", true);
            assertThat(row(mine(tb, s), s.c3)).containsEntry("student_note", "I failed it in my second year").containsEntry("clarification_open", true);
            // a student who is neither (a 200 Level student with no spillover) is not eligible
            UUID e = s.student("E", 2, 200);
            assertThat((Map<String, Object>) mine(student(e), s).get("eligibility")).containsEntry("eligible", false).containsEntry("reason", "NOT_FINAL_OR_SPILLOVER");

            // ── 4: who may decide and who sees what ──
            UUID selC1 = selection(paid, s.c1), selC2 = selection(paid, s.c2);
            String hod = it.officer("hod", "department", s.dept), otherHod = it.officer("hod", "department", s.otherDept);
            String dean = it.officer("dean", "faculty", s.faculty), otherDean = it.officer("dean", "faculty", s.otherFaculty);
            assertThat(decide(s, ta, List.of(selC1), "CONFIRM", null).getStatusCode().value()).isEqualTo(403);
            assertThat(decide(s, hod, List.of(selC1), "CONFIRM", null).getStatusCode().value()).isEqualTo(403);
            assertThat(decide(s, ItSupport.token("bursar"), List.of(selC1), "CONFIRM", null).getStatusCode().value()).isEqualTo(403);
            assertThat(it.get(ta, s.path + "/selections").getStatusCode().value()).isEqualTo(403);
            Map<String, Object> hodQueue = it.get(hod, s.path + "/selections?state=ANY").getBody();
            assertThat(((Number) hodQueue.get("total")).longValue()).isGreaterThanOrEqualTo(3);
            assertThat(((List<Map<String, Object>>) hodQueue.get("rows")).stream().map(r -> String.valueOf(r.get("course_code"))).collect(Collectors.toSet())).contains(s.c1, s.c2, s.c3);
            assertThat(((Number) it.get(otherHod, s.path + "/selections?state=ANY").getBody().get("total")).longValue()).isZero();
            assertThat(((Number) it.get(dean, s.path + "/selections?state=ANY").getBody().get("total")).longValue()).isGreaterThanOrEqualTo(3);
            assertThat(((Number) it.get(otherDean, s.path + "/selections?state=ANY").getBody().get("total")).longValue()).isZero();
            assertThat(it.get(hod, s.path + "/selections/" + selC1).getStatusCode().value()).isEqualTo(200);
            assertThat(it.get(otherHod, s.path + "/selections/" + selC1).getStatusCode().value()).isEqualTo(404);
            // a reader asking for another department by name is refused by the scope, not shown it
            assertThat(it.get(hod, s.path + "/selections?dept=" + s.otherDept).getStatusCode().value()).isEqualTo(422);
            // the academic office reads one selection in full
            Map<String, Object> detail = it.get(ItSupport.token("academic"), s.path + "/selections/" + selC1).getBody();
            assertThat((Map<String, Object>) detail.get("selection")).containsEntry("state", "PENDING_VERIFICATION").containsEntry("course_code", s.c1);
            // what a decision would hold as Summer credit, read the same way from the drawer and from the queue: the course's own fee, the
            // programme fee paid, and how many courses of the student still stand (the programme fee follows the last one: summer_verify)
            assertMoneyKeys((Map<String, Object>) detail.get("selection"), "5000", "50000", 2);
            assertMoneyKeys(queueRow(hodQueue, selC1), "5000", "50000", 2);
            Map<String, Object> unpaidRow = ((List<Map<String, Object>>) hodQueue.get("rows")).stream().filter(r -> s.c3.equals(r.get("course_code"))).findFirst().orElseThrow();
            assertThat(unpaidRow).containsEntry("charge_state", "DUE");
            assertMoneyKeys(unpaidRow, "5000", null, 1);
            assertThat((Map<String, Object>) detail.get("student")).containsEntry("level", 400);
            assertThat((Map<String, Object>) detail.get("charge")).containsEntry("state", "PAID");
            assertThat((List<?>) detail.get("others")).hasSize(1);
            Map<String, Object> facets = (Map<String, Object>) it.get(ItSupport.token("academic"), s.path + "/selections?state=ANY").getBody().get("facets");
            assertThat((List<Map<String, Object>>) facets.get("programmes")).extracting(x -> x.get("code")).contains(s.prog);
            assertThat((List<Integer>) facets.get("levels")).contains(400);

            // ── 3: the Academic Office confirms one and rejects the other, with a reason ──
            String academic = ItSupport.token("academic");
            assertThat(decide(s, academic, List.of(selC2), "REJECT", "short").getBody()).containsEntry("code", "SUMMER_REASON");
            assertThat(decide(s, academic, List.of(selC1), "BANISH", "A reason of some length").getBody()).containsEntry("code", "SUMMER_DECISION");
            assertThat(decide(s, academic, IntStream.range(0, 201).mapToObj(i -> UUID.randomUUID()).toList(), "CONFIRM", null).getBody()).containsEntry("code", "SUMMER_BATCH_TOO_BIG");
            ResponseEntity<Map> confirmed = decide(s, academic, List.of(selC1), "CONFIRM", null);
            assertThat(confirmed.getStatusCode().value()).as(String.valueOf(confirmed.getBody())).isEqualTo(200);
            assertThat(confirmed.getBody()).containsEntry("decided", 1);
            assertThat(entry(a, s, s.c1, "entry_type")).isEqualTo("CARRYOVER");
            // the same decision again changes nothing
            assertThat(decide(s, academic, List.of(selC1), "CONFIRM", null).getBody()).containsEntry("decided", 0).containsEntry("unchanged", 1);
            String why = "The course is not in the student's record as owed";
            // the queue says a decision on the other course holds its own fee alone: the confirmed course still stands
            assertMoneyKeys(queueRow(it.get(academic, s.path + "/selections?state=ANY&size=200").getBody(), selC2), "5000", "50000", 2);
            ResponseEntity<Map> rejected = decide(s, academic, List.of(selC2), "REJECT", why);
            assertThat(rejected.getStatusCode().value()).as(String.valueOf(rejected.getBody())).isEqualTo(200);
            assertThat(rejected.getBody()).containsEntry("decided", 1).containsEntry("withdrawn", 1);
            assertThat(money(rejected.getBody().get("credited"))).isEqualByComparingTo("5000");
            assertThat((List<?>) rejected.getBody().get("refused")).isEmpty();
            assertThat(entry(a, s, s.c2, "status")).isEqualTo("WITHDRAWN");
            assertThat(jdbc.sql("SELECT count(*) FROM registration.entry_removal WHERE student_id = :st AND course_code = :c AND state = 'APPLIED' AND ref LIKE 'RCR-%'")
                    .param("st", a).param("c", s.c2).query(Long.class).single()).isEqualTo(1);
            // the student reads the reason, the course is taken off, the other stands
            Map<String, Object> afterDecision = mine(ta, s);
            assertThat(row(afterDecision, s.c2)).containsEntry("verification", "REJECTED").containsEntry("decision_reason", why).containsEntry("status", "TAKEN_OFF").containsEntry("selectable", false);
            assertThat(row(afterDecision, s.c1)).containsEntry("verification", "CONFIRMED_OUTSTANDING").containsEntry("status", "REGISTERED");
            assertThat((Map<String, Object>) afterDecision.get("summary")).containsEntry("rejected", 1).containsEntry("confirmed", 1);
            assertThat((List<Map<String, Object>>) afterDecision.get("registered")).extracting(x -> x.get("course_code")).containsExactly(s.c1);
            // a rejected course that was paid cannot be selected again or reopened
            assertThat(select(ta, s, s.c2).getBody()).containsEntry("code", "SUMMER_COURSE_REFUSED");
            List<Map<String, Object>> noReopen = (List<Map<String, Object>>) decide(s, academic, List.of(selC2), "REOPEN", null).getBody().get("refused");
            assertThat(noReopen).extracting(r -> r.get("code")).containsExactly("SUMMER_DECIDED_PAID");

            // the fee of the course is a credit on the Bursar's page, from the decision, not an automatic refund; the Bursar settles it
            Map<String, Object> bursarPage = it.get(ItSupport.token("bursar"), "/api/v1/finance/summer-fees?session=" + s.session).getBody();
            List<Map<String, Object>> credits = (List<Map<String, Object>>) bursarPage.get("credits");
            Map<String, Object> credit = credits.stream().filter(c -> s.c2.equals(c.get("course_code"))).findFirst().orElseThrow(() -> new AssertionError("no credit on " + credits));
            assertThat(credit).containsEntry("source", "DECISION").containsEntry("state", "OPEN").containsEntry("selection_state", "REJECTED");
            assertThat(money(credit.get("amount"))).isEqualByComparingTo("5000");
            assertThat(String.valueOf(credit.get("note"))).isNotBlank();
            assertThat(it.call(academic, HttpMethod.POST, "/api/v1/finance/summer-credits/" + credit.get("id") + "/settle", Map.of("state", "REFUNDED", "note", "Refunded to the student")).getStatusCode().value()).isEqualTo(403);
            ResponseEntity<Map> settled = it.call(ItSupport.token("bursar"), HttpMethod.POST, "/api/v1/finance/summer-credits/" + credit.get("id") + "/settle", Map.of("state", "REFUNDED", "note", "Refunded to the student"));
            assertThat(settled.getStatusCode().value()).as(String.valueOf(settled.getBody())).isEqualTo(200);
            assertThat(settled.getBody()).containsEntry("state", "REFUNDED");

            // ── 7 and 13: each CSV is text/csv with the byte order mark, a formula-looking name is made plain, and each leaves a row on the export log ──
            long exportsBefore = exportRows("Summer selections"), studentsBefore = exportRows("Summer students"), reportBefore = exportRows("Summer report");
            selectFor(tf, s);
            ResponseEntity<byte[]> csv = it.getBytes(academic, s.path + "/selections/export?state=ANY");
            assertThat(csv.getStatusCode().value()).isEqualTo(200);
            assertThat(String.valueOf(csv.getHeaders().getContentType())).startsWith("text/csv");
            assertThat(String.valueOf(csv.getHeaders().getFirst("Content-Disposition"))).contains("summer-" + s.session.replace('/', '-') + "-selections.csv");
            String text = new String(csv.getBody(), StandardCharsets.UTF_8);
            assertThat(text).startsWith("﻿").contains("Matriculation number").contains(s.c1).contains("Academically confirmed outstanding").contains("Rejected");
            assertThat(text).contains("'=ZZSUMVF" + s.n).doesNotContain(",=ZZSUMVF").doesNotContain("\"=ZZSUMVF");
            assertThat(it.getBytes(otherHod, s.path + "/selections/export?state=ANY").getBody()).satisfies(bytes -> assertThat(new String(bytes, StandardCharsets.UTF_8)).doesNotContain(s.c1));
            ResponseEntity<byte[]> studentsCsv = it.getBytes(academic, s.path + "/students/export");
            assertThat(studentsCsv.getStatusCode().value()).isEqualTo(200);
            assertThat(new String(studentsCsv.getBody(), StandardCharsets.UTF_8)).startsWith("﻿").contains(s.matric(0));
            ResponseEntity<byte[]> reportCsv = it.getBytes(academic, s.path + "/report/export?group=FACULTY");
            assertThat(reportCsv.getStatusCode().value()).isEqualTo(200);
            assertThat(new String(reportCsv.getBody(), StandardCharsets.UTF_8)).startsWith("﻿");
            assertThat(exportRows("Summer selections")).isGreaterThanOrEqualTo(exportsBefore + 2);
            assertThat(exportRows("Summer students")).isEqualTo(studentsBefore + 1);
            assertThat(exportRows("Summer report")).isEqualTo(reportBefore + 1);

            // the roster and the report read the same students, and a reader outside the programme's department sees none of them
            Map<String, Object> roster = it.get(academic, s.path + "/students?scope=SELECTED&programme=" + s.prog).getBody();
            assertThat(((List<Map<String, Object>>) roster.get("rows")).stream().map(r -> String.valueOf(r.get("matric_no"))).toList()).contains(s.matric(0), s.matric(1));
            assertThat(roster.get("summary")).isNotNull();
            assertThat((Map<String, Object>) roster.get("summary")).containsKeys("eligible", "commenced", "completed", "owing", "paid", "registeredCourses", "feesOutstanding");
            assertThat(((List<Map<String, Object>>) it.get(otherHod, s.path + "/students?scope=SELECTED").getBody().get("rows")).stream().map(r -> String.valueOf(r.get("matric_no"))).toList())
                    .doesNotContain(s.matric(0), s.matric(1));
            Map<String, Object> report = it.get(academic, s.path + "/report?group=PROGRAMME&programme=" + s.prog).getBody();
            List<Map<String, Object>> reportRows = (List<Map<String, Object>>) report.get("rows");
            assertThat(reportRows).hasSize(1);
            assertThat(reportRows.get(0)).containsEntry("groupCode", s.prog);
            assertThat(((Number) reportRows.get(0).get("studentsSelected")).longValue()).isGreaterThanOrEqualTo(2);
            assertThat(((Number) reportRows.get(0).get("rejected")).longValue()).isEqualTo(1);
            assertThat(it.get(academic, s.path + "/report?group=NONSENSE").getStatusCode().value()).isEqualTo(422);
            assertThat(reference).isNotBlank();
        } finally {
            s.close();
        }
    }

    /** a student selects one course, so the queue and the CSV carry the name that looks like a formula */
    private void selectFor(String token, Scene s) {
        assertThat(select(token, s, s.c4).getStatusCode().value()).isEqualTo(200);
    }

    /* ── 5: the results published after a selection ── */

    @Test
    void resultsPublishedAfterASelectionAreReconciledAnUnpaidCourseTakenBackAndAPaidOneFlagged() {
        Scene s = new Scene(4700, 5400);
        try {
            UUID g = s.student("G", 4, 400);
            String tg = student(g);
            String academic = ItSupport.token("academic");
            // one course paid and one chosen after, unpaid
            assertThat(select(tg, s, s.c3).getStatusCode().value()).isEqualTo(200);
            pay(tg, s);
            assertThat(select(tg, s, s.c4).getStatusCode().value()).isEqualTo(200);
            Map<String, Object> page = mine(tg, s);
            UUID paidSel = selection(page, s.c3), unpaidSel = selection(page, s.c4);
            assertThat((Map<String, Object>) page.get("summary")).containsEntry("reconcilable", true);

            // the results of the course both passed in the session before are published after the selections were made
            String matric = s.matric(4);
            it.db(() -> {
                jdbc.sql("SELECT set_config('moaum.actor_office', 'ict', true)").query().listOfRows();
                jdbc.sql("SELECT assessment.import_legacy_semester(:s, 1, CAST(:rows AS jsonb), true)").param("s", s.before)
                        .param("rows", "[{\"matric\":\"" + matric + "\",\"course\":\"" + s.c3 + "\",\"total\":\"61\",\"level\":\"300\"}]").query().listOfRows();
                jdbc.sql("SELECT assessment.import_legacy_semester(:s, 2, CAST(:rows AS jsonb), true)").param("s", s.before)
                        .param("rows", "[{\"matric\":\"" + matric + "\",\"course\":\"" + s.c4 + "\",\"total\":\"62\",\"level\":\"300\"}]").query().listOfRows();
                return null;
            });
            // the page reads the evidence live, without writing it
            Map<String, Object> read = mine(tg, s);
            assertThat(row(read, s.c3)).containsEntry("evidence", "RESULT_PASSED");
            assertThat(row(read, s.c4)).containsEntry("evidence", "RESULT_PASSED");
            assertThat(row(read, s.c3)).containsEntry("verification", "PENDING_VERIFICATION");

            // the page's own reconcile: the unpaid course is taken back (nothing owed on it), the paid one flagged, never withdrawn
            ResponseEntity<Map> first = it.call(tg, HttpMethod.POST, "/api/v1/me/summer/reconcile", Map.of("session", s.session));
            assertThat(first.getStatusCode().value()).as(String.valueOf(first.getBody())).isEqualTo(200);
            assertThat(((Number) first.getBody().get("changed")).intValue()).isGreaterThanOrEqualTo(2);
            Map<String, Object> after = mine(tg, s);
            assertThat(row(after, s.c4)).containsEntry("verification", "NOT_OUTSTANDING");
            assertThat(jdbc.sql("SELECT state FROM registration.summer_charge WHERE student_id = :st AND session = :s AND course_code = :c AND kind = 'COURSE'")
                    .param("st", g).param("s", s.session).param("c", s.c4).query(String.class).single()).isEqualTo("CANCELLED");
            assertThat(row(after, s.c3)).containsEntry("verification", "PENDING_VERIFICATION");
            assertThat(entry(g, s, s.c3, "status")).isNotEqualTo("WITHDRAWN").isNotNull();
            Map<String, Object> flagged = it.get(academic, s.path + "/selections?flag=REVIEW&state=ANY").getBody();
            assertThat(((List<Map<String, Object>>) flagged.get("rows")).stream().filter(r -> s.c3.equals(r.get("course_code")) && s.matric(4).equals(r.get("matric_no"))).toList())
                    .singleElement().satisfies(r -> assertThat(r).containsEntry("review_flag", "PASSED_ON_RECORD").containsEntry("needs_review", true));
            assertThat(((Map<String, Object>) flagged.get("counts")).get("review")).isNotNull();

            // a second run changes nothing; the desk's tranche reads and leaves nothing
            ResponseEntity<Map> second = it.call(tg, HttpMethod.POST, "/api/v1/me/summer/reconcile", Map.of("session", s.session));
            assertThat(((Number) second.getBody().get("changed")).intValue()).isZero();
            String since = null;
            for (int i = 0; i < 50; i++) {
                Map<String, Object> body = new HashMap<>();
                body.put("limit", 2000);
                if (since != null) body.put("since", since);
                ResponseEntity<Map> tranche = it.call(academic, HttpMethod.POST, s.path + "/reconcile", body);
                assertThat(tranche.getStatusCode().value()).as(String.valueOf(tranche.getBody())).isEqualTo(200);
                since = String.valueOf(tranche.getBody().get("since"));
                if (((Number) tranche.getBody().get("left")).longValue() == 0) break;
            }
            assertThat(it.call(ItSupport.token("bursar"), HttpMethod.POST, s.path + "/reconcile", Map.of("limit", 10)).getStatusCode().value()).isEqualTo(403);

            // a confirmation can never contradict a pass: the Office decides it Not outstanding, and the fee becomes a credit
            ResponseEntity<Map> confirm = decide(s, academic, List.of(paidSel), "CONFIRM", null);
            assertThat(((List<Map<String, Object>>) confirm.getBody().get("refused")).stream().map(r -> r.get("code")).toList()).containsExactly("SUMMER_PASSED_CONFIRM");
            ResponseEntity<Map> notOutstanding = decide(s, academic, List.of(paidSel), "NOT_OUTSTANDING", "A pass is on record for the course");
            assertThat(notOutstanding.getBody()).containsEntry("decided", 1);
            assertThat(money(notOutstanding.getBody().get("credited"))).isGreaterThanOrEqualTo(new BigDecimal("5000"));
            assertThat(unpaidSel).isNotNull();
        } finally {
            s.close();
        }
    }

    /* ── 6: the examinations ── */

    @Test
    void theExaminationsDoNotOpenOverPaidCoursesNobodyHasVerifiedUntilTheOfficeSaysWhyAndAgainWhenMoreArrive() {
        Scene s = new Scene(5400, 6100);
        try {
            UUID a = s.student("A", 0, 400);
            UUID b = s.student("B", 1, 400);
            UUID e = s.student("E", 2, 400);
            String ta = student(a), tb = student(b), te = student(e);
            String academic = ItSupport.token("academic");
            assertThat(select(ta, s, s.c1).getStatusCode().value()).isEqualTo(200);
            pay(ta, s);
            // another student's reference is drawn while the window is open and paid after it closes: a late payment, honoured
            assertThat(select(tb, s, s.c3).getStatusCode().value()).isEqualTo(200);
            String late = String.valueOf(it.call(tb, HttpMethod.POST, "/api/v1/me/summer/reference", Map.of("session", s.session)).getBody().get("reference"));
            assertThat(select(te, s, s.c4).getStatusCode().value()).isEqualTo(200);   // chosen, never paid

            Map<String, Object> period = (Map<String, Object>) it.get(academic, s.path + "/period").getBody();
            assertThat(period).containsEntry("unverified", 1);
            assertThat(period.get("exam_session_id")).isNotNull();

            // while the registration window is open the examinations do not open
            ResponseEntity<Map> windowOpen = it.call(academic, HttpMethod.POST, s.path + "/exams/open", Map.of());
            assertThat(windowOpen.getStatusCode().value()).isEqualTo(422);
            assertThat(windowOpen.getBody()).containsEntry("code", "SUMMER_REGISTRATION_OPEN");
            // the window ends (its dates pass; the Summer stays open as a state): the paid course nobody has verified holds the act
            it.db(() -> jdbc.sql("UPDATE registration.summer_period SET registration_opens = current_date - 20, registration_closes = current_date - 1 WHERE session = :s").param("s", s.session).update());
            ResponseEntity<Map> held = it.call(academic, HttpMethod.POST, s.path + "/exams/open", Map.of());
            assertThat(held.getStatusCode().value()).as(String.valueOf(held.getBody())).isEqualTo(422);
            assertThat(held.getBody()).containsEntry("code", "SUMMER_VERIFICATION_PENDING");
            assertThat(String.valueOf(held.getBody().get("detail"))).contains("1");

            // an override needs the Office and a reason; with it the act goes through
            assertThat(it.call(ItSupport.token("bursar"), HttpMethod.POST, s.path + "/exams/open/override", Map.of("reason", "The Academic Board has ruled")).getStatusCode().value()).isEqualTo(403);
            assertThat(it.call(academic, HttpMethod.POST, s.path + "/exams/open/override", Map.of("reason", "short")).getBody()).containsEntry("code", "SUMMER_REASON");
            ResponseEntity<Map> override = it.call(academic, HttpMethod.POST, s.path + "/exams/open/override", Map.of("reason", "The Academic Board has ruled that the examinations go ahead"));
            assertThat(override.getStatusCode().value()).as(String.valueOf(override.getBody())).isEqualTo(200);
            assertThat(override.getBody()).containsEntry("unverified", 1);
            Map<String, Object> withOverride = (Map<String, Object>) it.get(academic, s.path + "/period").getBody();
            assertThat((List<Map<String, Object>>) withOverride.get("overrides")).extracting(o -> o.get("act")).containsExactly("OPEN");

            // another paid course arrives late: the count has grown, so the override no longer holds
            confirm(late);
            assertThat(entry(b, s, s.c3, "status")).isNotNull();
            assertThat(((Map<String, Object>) it.get(academic, s.path + "/period").getBody())).containsEntry("unverified", 2);
            ResponseEntity<Map> again = it.call(academic, HttpMethod.POST, s.path + "/exams/open", Map.of());
            assertThat(again.getStatusCode().value()).isEqualTo(422);
            assertThat(again.getBody()).containsEntry("code", "SUMMER_VERIFICATION_PENDING");
            // verifying one and overriding the rest lets the act through, once
            Map<String, Object> pageA = mine(ta, s);
            assertThat(decide(s, academic, List.of(selection(pageA, s.c1)), "CONFIRM", null).getBody()).containsEntry("decided", 1);
            assertThat(((Map<String, Object>) it.get(academic, s.path + "/period").getBody())).containsEntry("unverified", 1);
            assertThat(it.call(academic, HttpMethod.POST, s.path + "/exams/open/override", Map.of("reason", "The remaining course is verified next week")).getStatusCode().value()).isEqualTo(200);
            ResponseEntity<Map> opened = it.call(academic, HttpMethod.POST, s.path + "/exams/open", Map.of());
            assertThat(opened.getStatusCode().value()).as(String.valueOf(opened.getBody())).isEqualTo(200);
            assertThat(opened.getBody()).containsEntry("exam_state", "OPEN");
            // the unpaid course and the withdrawn entry never counted
            assertThat(jdbc.sql("SELECT registration.summer_unverified(:s)").param("s", s.session).query(Integer.class).single()).isEqualTo(1);
            // the score sheets are released from the same desk under the same gate: an override of the act's own is needed
            ResponseEntity<Map> sheets = it.call(academic, HttpMethod.POST, s.path + "/exams/release-sheets", Map.of());
            assertThat(sheets.getStatusCode().value()).as(String.valueOf(sheets.getBody())).isEqualTo(422);
            assertThat(sheets.getBody()).containsEntry("code", "SUMMER_VERIFICATION_PENDING");
            assertThat(it.call(academic, HttpMethod.POST, s.path + "/exams/release-sheets/override", Map.of("reason", "The sheets go to the lecturers while the course is verified")).getStatusCode().value()).isEqualTo(200);
            ResponseEntity<Map> released = it.call(academic, HttpMethod.POST, s.path + "/exams/release-sheets", Map.of());
            assertThat(released.getStatusCode().value()).as(String.valueOf(released.getBody())).isEqualTo(200);
        } finally {
            s.close();
        }
    }

    /* ── 10: the notices ── */

    @Test
    void theStudentsAreToldInTranchesWalkedByACursorAndNeverTwice() {
        Scene s = new Scene(6100, 6800);
        try {
            s.student("A", 0, 400);
            s.student("B", 1, 400);
            s.student("E", 2, 400);
            String academic = ItSupport.token("academic");
            // the eligible are identified first (a tranche at a time), then told
            String since = null;
            for (int i = 0; i < 200; i++) {
                Map<String, Object> body = new HashMap<>();
                body.put("limit", 2000);
                if (since != null) body.put("since", since);
                ResponseEntity<Map> r = it.call(academic, HttpMethod.POST, s.path + "/identify", body);
                assertThat(r.getStatusCode().value()).as(String.valueOf(r.getBody())).isEqualTo(200);
                assertThat(r.getBody()).containsKeys("read", "left", "eligible", "since", "results");
                since = String.valueOf(r.getBody().get("since"));
                if (((Number) r.getBody().get("left")).longValue() == 0) break;
            }
            // the portal's delivery is switched off, and these students have no address anywhere: they cannot be told, no notice row is made
            // for them, and still the cursor — not the absence of a notice — walks the audience: three tranches of one each take one student and
            // say where they stopped, the rest go in large tranches, the cursor ends null and nothing remains
            boolean portalWas = jdbc.sql("SELECT portal_delivery FROM platform.notice_setting WHERE id").query(Boolean.class).single();
            try {
                it.db(() -> jdbc.sql("UPDATE platform.notice_setting SET portal_delivery = false WHERE id").update());
                String after = null;
                long remaining = -1;
                for (int i = 0; i < 3; i++) {
                    ResponseEntity<Map> r = tell(academic, s, 1, after);
                    assertThat(((Number) r.getBody().get("visited")).intValue()).isEqualTo(1);
                    assertThat(r.getBody().get("next")).isNotNull();
                    long left = ((Number) r.getBody().get("remaining")).longValue();
                    if (remaining >= 0) assertThat(left).isEqualTo(remaining - 1);
                    remaining = left;
                    after = String.valueOf(r.getBody().get("next"));
                }
                walk(academic, s, after);   // (a student left by another test with an e-mail address is told even now: the cursor does not depend on it)
                // delivery on again: the students who could not be told before are told now, once, and a second walk tells nobody
                it.db(() -> jdbc.sql("UPDATE platform.notice_setting SET portal_delivery = true WHERE id").update());
                assertThat(walk(academic, s, null)).isGreaterThanOrEqualTo(3);
                assertThat(walk(academic, s, null)).isZero();
            } finally {
                it.db(() -> jdbc.sql("UPDATE platform.notice_setting SET portal_delivery = :v WHERE id").param("v", portalWas).update());
            }
            // the window checks stand
            assertThat(it.call(academic, HttpMethod.POST, s.path + "/tell", Map.of("kind", "NONSENSE")).getStatusCode().value()).isEqualTo(400);
            assertThat(it.call(ItSupport.token("bursar"), HttpMethod.POST, s.path + "/tell", Map.of("kind", "OPEN")).getStatusCode().value()).isEqualTo(403);
        } finally {
            s.close();
        }
    }

    /* ── 11: ICT Support's read-only view ── */

    private UUID agent(String tag) {
        UUID p = it.person("ZZ-VIEW-" + tag, "ZZVIEW" + tag);
        it.db(() -> jdbc.sql("""
                INSERT INTO iam.office_assignment (id, person_id, office_code, scope_kind, scope_id, instrument, granted_by, valid_from)
                SELECT gen_random_uuid(), :p, 'ictagent', 'platform', NULL, 'integration test', :p, current_date
                 WHERE NOT EXISTS (SELECT 1 FROM iam.office_assignment a WHERE a.person_id = :p AND a.office_code = 'ictagent' AND (a.valid_to IS NULL OR a.valid_to >= current_date))
                """).param("p", p).update());
        return p;
    }

    @Test
    void ictSupportReadsTheSummerPageAndTheCardInItsReadOnlyViewAndChangesNothing() {
        Scene s = new Scene(6800, 7500);
        try {
            UUID a = s.student("A", 0, 400);
            String ta = student(a);
            assertThat(select(ta, s, s.c1).getStatusCode().value()).isEqualTo(200);
            // the student's own card answers the same, without the pool (before the account's first password gate stands)
            ResponseEntity<Map> own = it.get(ta, "/api/v1/me/summer/card?session=" + s.session);
            assertThat(own.getStatusCode().value()).isEqualTo(200);
            assertThat(own.getBody()).containsKeys("session", "period", "eligibility", "summary").doesNotContainKeys("courses", "registered", "payments");
            String tag = UUID.randomUUID().toString().substring(0, 4).toUpperCase().replaceAll("[^A-Z0-9]", "Q");
            assertThat(it.call(ItSupport.token("registrar"), HttpMethod.PUT, "/api/v1/student-auth/accounts/" + a, Map.of("password", "first password 7790")).getStatusCode().value()).isEqualTo(200);
            String agent = TestTokens.token(agent("S" + tag), List.of("ictagent"));
            ResponseEntity<Map> opened = it.call(agent, HttpMethod.POST, "/api/v1/helpdesk/support/students/" + a + "/portal-view", Map.of("reason", "The student says the Summer page shows no courses"));
            assertThat(opened.getStatusCode().value()).as(String.valueOf(opened.getBody())).isEqualTo(200);
            String view = String.valueOf(opened.getBody().get("token"));
            long auditBefore = jdbc.sql("SELECT count(*) FROM audit.entries WHERE subject_type LIKE 'registration.summer%'").query(Long.class).single();
            long evidenceBefore = jdbc.sql("SELECT count(*) FROM registration.summer_selection_evidence").query(Long.class).single();

            ResponseEntity<Map> page = it.get(view, "/api/v1/me/summer?session=" + s.session);
            assertThat(page.getStatusCode().value()).as(String.valueOf(page.getBody())).isEqualTo(200);
            assertThat(row(page.getBody(), s.c1)).containsEntry("verification", "PENDING_VERIFICATION");
            ResponseEntity<Map> card = it.get(view, "/api/v1/me/summer/card?session=" + s.session);
            assertThat(card.getStatusCode().value()).as(String.valueOf(card.getBody())).isEqualTo(200);
            assertThat(card.getBody()).containsKeys("session", "period", "eligibility", "fee", "summary").doesNotContainKeys("courses", "registered", "payments");
            assertThat((Map<String, Object>) card.getBody().get("summary")).containsEntry("selected", 1);
            // the read wrote nothing: not an audit row, not a cached piece of evidence
            assertThat(jdbc.sql("SELECT count(*) FROM registration.summer_selection_evidence").query(Long.class).single()).isEqualTo(evidenceBefore);
            assertThat(jdbc.sql("SELECT count(*) FROM audit.entries WHERE subject_type LIKE 'registration.summer%'").query(Long.class).single()).isEqualTo(auditBefore);
            // and the reconcile, a write, is refused in the view
            ResponseEntity<Map> reconcile = it.call(view, HttpMethod.POST, "/api/v1/me/summer/reconcile", Map.of("session", s.session));
            assertThat(reconcile.getStatusCode().value()).isEqualTo(403);
            assertThat(reconcile.getBody()).containsEntry("code", "SUPPORT_VIEW_READ_ONLY");
        } finally {
            s.close();
        }
    }

    /* ── 12: the Director of ICT removes a paid course ── */

    @Test
    void aPaidCourseTheDirectorOfIctRemovedIsFlaggedForTheOfficeAndOnceDecidedItsRemovalCannotBeUndone() {
        Scene s = new Scene(7500, 8200);
        try {
            UUID a = s.student("A", 0, 400);
            String ta = student(a);
            String academic = ItSupport.token("academic");
            assertThat(select(ta, s, s.c1, s.c2).getStatusCode().value()).isEqualTo(200);
            pay(ta, s);
            Map<String, Object> page = mine(ta, s);
            UUID selC1 = selection(page, s.c1), selC2 = selection(page, s.c2);
            UUID registration = jdbc.sql("SELECT id FROM registration.course_registration WHERE student_id = :st AND session = :s AND semester = 3").param("st", a).param("s", s.session).query(UUID.class).single();
            UUID offering = jdbc.sql("SELECT id FROM catalogue.offering WHERE session = :s AND semester = 3 AND course_code = :c").param("s", s.session).param("c", s.c1).query(UUID.class).single();
            ResponseEntity<Map> removal = it.call(ItSupport.token("ict"), HttpMethod.POST, "/api/v1/registration/corrections",
                    Map.of("studentId", a.toString(), "entries", List.of(Map.of("registrationId", registration.toString(), "offeringId", offering.toString())),
                            "reason", "The course was counted by mistake on this registration"));
            assertThat(removal.getStatusCode().value()).as(String.valueOf(removal.getBody())).isEqualTo(200);
            assertThat(entry(a, s, s.c1, "status")).isEqualTo("WITHDRAWN");
            // the paid course is not silently dropped: it is flagged for the Office, which may only decide it Not outstanding or Rejected
            Map<String, Object> flagged = it.get(academic, s.path + "/selections?flag=REVIEW&state=ANY").getBody();
            assertThat(((List<Map<String, Object>>) flagged.get("rows")).stream().filter(r -> s.c1.equals(r.get("course_code"))).toList())
                    .singleElement().satisfies(r -> assertThat(r).containsEntry("review_flag", "ENTRY_REMOVED"));
            ResponseEntity<Map> confirm = decide(s, academic, List.of(selC1), "CONFIRM", null);
            assertThat(((List<Map<String, Object>>) confirm.getBody().get("refused")).stream().map(r -> r.get("code")).toList()).containsExactly("SUMMER_ENTRY_REMOVED");
            ResponseEntity<Map> rejected = decide(s, academic, List.of(selC1), "NOT_OUTSTANDING", "The course is not owed, the Director removed it");
            assertThat(rejected.getStatusCode().value()).as(String.valueOf(rejected.getBody())).isEqualTo(200);
            assertThat(rejected.getBody()).containsEntry("decided", 1);
            assertThat(money(rejected.getBody().get("credited"))).isEqualByComparingTo("5000");
            assertThat(jdbc.sql("SELECT count(*) FROM registration.summer_credit WHERE student_id = :st AND session = :s AND source = 'DECISION'").param("st", a).param("s", s.session).query(Long.class).single()).isEqualTo(1);
            // the Director's own undo of that removal is refused: the entry, the charge and the credit stand as the decision left them
            UUID removalId = jdbc.sql("SELECT id FROM registration.entry_removal WHERE student_id = :st AND course_code = :c AND state = 'APPLIED'").param("st", a).param("c", s.c1).query(UUID.class).single();
            ResponseEntity<Map> undo = it.call(ItSupport.token("ict"), HttpMethod.POST, "/api/v1/registration/corrections/" + removalId + "/undo", Map.of("reason", "Putting the course back, said the Director"));
            assertThat(undo.getStatusCode().value()).isEqualTo(422);
            assertThat(undo.getBody()).containsEntry("code", "SUMMER_REMOVAL_HELD");
            assertThat(selC2).isNotNull();
        } finally {
            s.close();
        }
    }
}
