package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.HashMap;
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
 * A course's code and title corrected by the Director of ICT and the ICT Support Desk (V713, the University's brief of 30 October
 * 2026): the same course (its id) before and after, for a reason, against the version read, with what hangs on it shown first and
 * every registration, carry-over, result, allocation, binding, question and GST classification still on it; the same code under
 * another title kept as a separate course, the same code and title refused; an agent by the capability its posting carries and
 * within its scope, on a ticket; the trail kept and searchable; the old code finds the course. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class CourseCorrectionIT {

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    ItSupport it;
    String tag;
    String deptA;
    String faculty;
    String deptB;

    private static int status(ResponseEntity<Map> r) {
        return r.getStatusCode().value();
    }

    private static String code(ResponseEntity<Map> r) {
        return r.getBody() == null ? null : String.valueOf(r.getBody().get("code"));
    }

    private Map<String, Object> ok(ResponseEntity<Map> r) {
        assertThat(status(r)).as(String.valueOf(r.getBody())).isEqualTo(200);
        return r.getBody();
    }

    private UUID person(String office) {
        UUID p = it.person("ZZ-CCR-" + office + tag, "ZZCCR" + office.toUpperCase() + tag);
        it.db(() -> jdbc.sql("""
                INSERT INTO iam.office_assignment (id, person_id, office_code, scope_kind, scope_id, instrument, granted_by, valid_from)
                SELECT gen_random_uuid(), :p, :o, 'platform', NULL, 'integration test', :p, current_date
                 WHERE NOT EXISTS (SELECT 1 FROM iam.office_assignment a WHERE a.person_id = :p AND a.office_code = :o AND (a.valid_to IS NULL OR a.valid_to >= current_date))
                """).param("p", p).param("o", office).update());
        return p;
    }

    private Map<String, Object> detail(String token, String course) {
        return ok(it.get(token, "/api/v1/catalogue/courses/" + course + "/detail"));
    }

    private String version(String course) {
        return jdbc.sql("SELECT catalogue.course_version(c) FROM catalogue.course c WHERE code = :c").param("c", course).query(String.class).single();
    }

    private ResponseEntity<Map> correct(String token, String course, String newCode, String newTitle, String reason, String remarks, String version, Boolean past, String ticket) {
        Map<String, Object> body = new HashMap<>();
        body.put("code", newCode);
        body.put("title", newTitle);
        body.put("reasonKind", reason);
        body.put("remarks", remarks);
        body.put("version", version);
        body.put("pastClasses", past);
        return it.call(token, HttpMethod.POST, "/api/v1/catalogue/courses/" + course + "/correction" + (ticket == null ? "" : "?ticket=" + ticket), body);
    }

    private Map<String, Object> course(UUID id) {
        return jdbc.sql("SELECT code, title, units, general_office FROM catalogue.course WHERE id = :i").param("i", id).query().singleRow();
    }

    private long count(String sql, UUID id) {
        return jdbc.sql(sql).param("i", id).query(Long.class).single();
    }

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
        tag = Integer.toString(ThreadLocalRandom.current().nextInt(100000, 999999));
        Map<String, Object> one = jdbc.sql("""
                SELECT d.code AS a, d.faculty_code AS f FROM ref.department d
                 WHERE d.ended_on IS NULL AND d.faculty_code IS NOT NULL ORDER BY d.code LIMIT 1
                """).query().singleRow();
        deptA = String.valueOf(one.get("a"));
        faculty = String.valueOf(one.get("f"));
        deptB = jdbc.sql("SELECT code FROM ref.department WHERE ended_on IS NULL AND faculty_code IS DISTINCT FROM :f ORDER BY code LIMIT 1")
                .param("f", faculty).query(String.class).single();
    }

    @Test
    void aCourseCodeAndTitleAreCorrectedOnTheSameCourseWithEverythingOnIt() {
        String p = it.freeCoursePrefix("Z");
        String x = p + " 401", y = p + " 405", g = p + " 301", far = p + " 302";
        int yr = it.freeYear(5600, 5990, 0, 0);
        String session = yr + "/" + (yr + 1);
        it.session(session, yr);
        UUID lecturer = person("lecturer");
        String[] made = it.db(() -> {
            String prog = jdbc.sql("SELECT 'C' || n FROM generate_series(97000, 97499) n WHERE NOT EXISTS (SELECT 1 FROM ref.programme p WHERE p.code = 'C' || n) ORDER BY random() LIMIT 1")
                    .query(String.class).single();
            jdbc.sql("""
                    INSERT INTO ref.programme (code, name, dept_code, faculty_code, category, min_score, final_level, duration_years)
                    VALUES (:c, 'B.Sc. Course Correction Test ' || :c, :d, :f, 'UNDER GRADUATE', 0, 400, 4)
                    """).param("c", prog).param("d", deptA).param("f", faculty).update();
            jdbc.sql("""
                    INSERT INTO catalogue.course (code, title, units, semester, level, dept_code, kind, state) VALUES
                        (:x, 'Operating System', 3, 1, 400, :d, 'Core', 'LIVE'), (:y, 'Advanced Biology', 3, 1, 400, :d, 'Core', 'LIVE'),
                        (:far, 'Correction Out Of Reach', 2, 1, 300, :b, 'Core', 'LIVE')
                    """).param("x", x).param("y", y).param("far", far).param("d", deptA).param("b", deptB).update();
            jdbc.sql("INSERT INTO catalogue.course (code, title, units, semester, level, dept_code, kind, state, general_office) VALUES (:g, 'Use of Englsh', 2, 1, 300, :d, 'GST', 'LIVE', 'GST')")
                    .param("g", g).param("d", deptA).update();
            jdbc.sql("INSERT INTO catalogue.course_offer (course_code, programme_code, level, basis) VALUES (:x, :p, 400, 'Core')").param("x", x).param("p", prog).update();
            UUID cls = jdbc.sql("INSERT INTO catalogue.offering (id, course_code, session, semester, lecturer_id) VALUES (gen_random_uuid(), :x, :s, 1, :l) RETURNING id")
                    .param("x", x).param("s", session).param("l", lecturer).query(UUID.class).single();
            String yy = String.format("%02d", yr % 100);
            String matric = "MOAUM/ITO/" + yy + "/" + tag;
            UUID student = it.student("ZZCCR" + tag, prog, "MOAUM/ADM/" + yy + "/" + tag, matric, 400);
            UUID reg = UUID.randomUUID();
            jdbc.sql("INSERT INTO registration.course_registration (id, student_id, session, semester, level, status, submitted_at, approved_at) VALUES (:r, :st, :s, 1, 400, 'APPROVED', now(), now())")
                    .param("r", reg).param("st", student).param("s", session).update();
            jdbc.sql("INSERT INTO registration.entry (registration_id, offering_id, units, entry_type, status) VALUES (:r, :o, 3, 'CARRYOVER', 'APPROVED')")
                    .param("r", reg).param("o", cls).update();
            UUID sheet = jdbc.sql("INSERT INTO assessment.score_sheet (id, offering_id) VALUES (gen_random_uuid(), :o) RETURNING id").param("o", cls).query(UUID.class).single();
            jdbc.sql("INSERT INTO assessment.score (sheet_id, student_id, ca, exam, outcome) VALUES (:sh, :st, 20, 40, 'GRADED')").param("sh", sheet).param("st", student).update();
            jdbc.sql("SELECT set_config('moaum.maintenance', 'on', true)").query().singleRow();
            jdbc.sql("UPDATE assessment.score_sheet SET stage = 'PUBLISHED', published_at = now(), senate_minute = 'IT V713' WHERE id = :sh").param("sh", sheet).update();
            jdbc.sql("SELECT set_config('moaum.maintenance', '', true)").query().singleRow();
            jdbc.sql("INSERT INTO assessment.question (course_code, stem, options, answer, kind, marks) VALUES (:x, 'V713 question', '[\"a\",\"b\"]', 0, 'MCQ', 1)").param("x", x).update();
            return new String[] {prog, matric};
        });
        UUID id = jdbc.sql("SELECT id FROM catalogue.course WHERE code = :c").param("c", x).query(UUID.class).single();
        UUID gid = jdbc.sql("SELECT id FROM catalogue.course WHERE code = :c").param("c", g).query(UUID.class).single();
        String ict = TestTokens.token(person("ict"), List.of("ict"));

        // ── the Director of ICT: the course page offers the correction (not the full edit), with the version to correct against ──
        Map<String, Object> d = detail(ict, x);
        assertThat((Map<String, Object>) d.get("may")).containsEntry("correctCode", true).containsEntry("correctTitle", true).containsEntry("edit", false).containsEntry("changes", true);
        String v1 = String.valueOf(((Map<String, Object>) d.get("course")).get("version"));
        assertThat(v1).isEqualTo(version(x));

        // the check: what hangs on the course, and nothing refused; it changes nothing
        Map<String, Object> chk = ok(it.call(ict, HttpMethod.POST, "/api/v1/catalogue/courses/" + x + "/correction/check", Map.of("code", x, "title", "Operating Systems")));
        assertThat(chk.get("refusal")).isNull();
        assertThat(chk).containsEntry("titleChanged", true).containsEntry("codeChanged", false);
        Map<String, Object> impact = (Map<String, Object>) chk.get("impact");
        assertThat(impact).containsEntry("registrations", 1).containsEntry("carryOvers", 1).containsEntry("results", 1).containsEntry("publishedResults", 1)
                .containsEntry("lecturerAllocations", 1).containsEntry("programmeBindings", 1).containsEntry("questions", 1).containsEntry("pastClasses", 1);
        assertThat(course(id)).containsEntry("title", "Operating System");

        // a reason is required; Other is explained
        assertThat(code(correct(ict, x, x, "Operating Systems", null, null, v1, true, null))).isEqualTo("COURSE_CHANGE_REASON");
        assertThat(code(correct(ict, x, x, "Operating Systems", "OTHER", null, v1, true, null))).isEqualTo("COURSE_CHANGE_REASON");
        // a version not read: refused, nothing changes
        assertThat(code(correct(ict, x, x, "Operating Systems", "TYPOGRAPHICAL_ERROR", null, "not-the-version", true, null))).isEqualTo("COURSE_CHANGED_SINCE");
        assertThat(course(id)).containsEntry("title", "Operating System");

        // ── the title corrected: the same course, every class retitled (results, broadsheets), the units unchanged ──
        Map<String, Object> done = ok(correct(ict, x, x, "Operating  Systems ", "TYPOGRAPHICAL_ERROR", "Title misspelt on the old portal", v1, true, null));
        assertThat(done).containsEntry("id", id.toString()).containsEntry("title", "Operating Systems").containsEntry("wasTitle", "Operating System").containsEntry("classesRetitled", 1);
        assertThat(course(id)).containsEntry("code", x).containsEntry("title", "Operating Systems").containsEntry("units", 3);
        assertThat(count("SELECT count(*) FROM catalogue.offering o JOIN catalogue.course c ON c.code = o.course_code WHERE c.id = :i AND o.title = 'Operating Systems' AND o.units = 3", id)).isEqualTo(1L);
        assertThat(count("SELECT count(*) FROM catalogue.course_change WHERE course_id = :i AND field = 'TITLE' AND source = 'CORRECTION' AND reason_kind = 'TYPOGRAPHICAL_ERROR' AND old_value = 'Operating System' AND past_classes", id)).isEqualTo(1L);
        // the second person, who read the course before the first correction: refused, never written over
        assertThat(code(correct(ict, x, x, "Operating Systems Design", "OFFICIAL_CORRECTION", null, v1, true, null))).isEqualTo("COURSE_CHANGED_SINCE");
        assertThat(course(id)).containsEntry("title", "Operating Systems");

        // the plain edit no longer changes a title in passing
        String hodA = it.officer("hod", "department", deptA);
        assertThat(code(it.call(hodA, HttpMethod.PUT, "/api/v1/catalogue/courses/" + x, Map.of("title", "Operating Systems II", "units", 3, "semester", 1, "level", 400))))
                .isEqualTo("COURSE_TITLE_BY_CORRECTION");

        // ── the code corrected onto one another course holds under another title: kept a separate course, everything on it follows ──
        Map<String, Object> chk2 = ok(it.call(ict, HttpMethod.POST, "/api/v1/catalogue/courses/" + x + "/correction/check", Map.of("code", y.toLowerCase().replace(" ", ""), "title", "Operating Systems")));
        assertThat(chk2).containsEntry("separate", true).containsEntry("newCode", y).containsEntry("key", y + " V2");
        assertThat((List<Map<String, Object>>) chk2.get("sameCode")).extracting(r -> r.get("title")).containsExactly("Advanced Biology");
        Map<String, Object> moved = ok(correct(ict, x, y, "Operating Systems", "CURRICULUM_CORRECTION", null, version(x), true, null));
        String key = y + " V2";
        assertThat(moved).containsEntry("id", id.toString()).containsEntry("code", key).containsEntry("shown", y).containsEntry("was", x);
        assertThat(course(id)).containsEntry("code", key);
        assertThat(count("SELECT count(*) FROM catalogue.course WHERE id = :i", id)).isEqualTo(1L);
        // the registration, the carry-over (one), the result, the lecturer, the binding, the question: all on the same course
        assertThat(count("SELECT count(*) FROM registration.entry e JOIN catalogue.offering o ON o.id = e.offering_id JOIN catalogue.course c ON c.code = o.course_code WHERE c.id = :i", id)).isEqualTo(1L);
        assertThat(count("SELECT count(*) FROM registration.entry e JOIN catalogue.offering o ON o.id = e.offering_id JOIN catalogue.course c ON c.code = o.course_code WHERE c.id = :i AND e.entry_type = 'CARRYOVER'", id)).isEqualTo(1L);
        assertThat(count("SELECT count(*) FROM assessment.score s JOIN assessment.score_sheet sh ON sh.id = s.sheet_id JOIN catalogue.offering o ON o.id = sh.offering_id JOIN catalogue.course c ON c.code = o.course_code WHERE c.id = :i", id)).isEqualTo(1L);
        assertThat(count("SELECT count(*) FROM catalogue.offering o JOIN catalogue.course c ON c.code = o.course_code WHERE c.id = :i AND o.lecturer_id IS NOT NULL", id)).isEqualTo(1L);
        assertThat(count("SELECT count(*) FROM catalogue.course_offer co JOIN catalogue.course c ON c.code = co.course_code WHERE c.id = :i", id)).isEqualTo(1L);
        assertThat(count("SELECT count(*) FROM assessment.question q JOIN catalogue.course c ON c.code = q.course_code WHERE c.id = :i", id)).isEqualTo(1L);
        assertThat(jdbc.sql("SELECT count(*) FROM catalogue.offering WHERE course_code = :c").param("c", x).query(Long.class).single()).isZero();
        // the history keeps what the course was under its old code; the old code and the Course ID find it
        List<Map<String, Object>> history = jdbc.sql("SELECT action, field, old_value, new_value, reason FROM catalogue.course_history(:c)").param("c", key).query().listOfRows();
        assertThat(history).anyMatch(h -> "CREATED".equals(h.get("action")) && x.equals(h.get("new_value")));
        assertThat(history).anyMatch(h -> "code".equals(h.get("field")) && x.equals(h.get("old_value")) && key.equals(h.get("new_value")));
        assertThat(history).anyMatch(h -> "title".equals(h.get("field")) && String.valueOf(h.get("reason")).startsWith("Typographical error — Title misspelt"));
        Map<String, Object> byOld = ok(it.get(ict, "/api/v1/catalogue/courses/list?q=" + x + "&size=20"));
        assertThat((List<Map<String, Object>>) byOld.get("rows")).extracting(r -> r.get("code")).contains(key);
        Map<String, Object> opened = detail(ict, x);   // the old code opens the course it was renamed to
        assertThat(((Map<String, Object>) opened.get("course")).get("code")).isEqualTo(key);
        assertThat(opened.get("requested")).isEqualTo(x);
        Map<String, Object> byId = ok(it.get(ict, "/api/v1/catalogue/courses/list?q=" + id + "&size=20"));
        assertThat((List<Map<String, Object>>) byId.get("rows")).extracting(r -> r.get("code")).containsExactly(key);

        // ── the same code and the same title is the same course: refused, and nothing is written ──
        long trail = count("SELECT count(*) FROM catalogue.course_change", id);
        UUID yid = jdbc.sql("SELECT id FROM catalogue.course WHERE code = :c").param("c", y).query(UUID.class).single();
        assertThat(code(correct(ict, y, y, "Operating Systems", "DUPLICATE_DATA_CORRECTION", null, version(y), true, null))).isEqualTo("COURSE_SAME_CODE_AND_TITLE");
        assertThat(course(yid)).containsEntry("title", "Advanced Biology");
        assertThat(count("SELECT count(*) FROM catalogue.course_change", id)).isEqualTo(trail);

        // ── a GST course keeps its classification ──
        ok(correct(ict, g, g, "Use of English", "TYPOGRAPHICAL_ERROR", null, version(g), true, null));
        assertThat(course(gid)).containsEntry("title", "Use of English").containsEntry("general_office", "GST");

        // ── ICT Support: by the capability its posting carries, within its scope, on a ticket ──
        UUID agent = person("ictagent");
        String tok = TestTokens.token(agent, List.of("ictagent"));
        assertThat(code(correct(tok, key, key, "Operating Systems Concepts", "ICT_SUPPORT_CORRECTION", null, version(key), true, null))).isEqualTo("STRUCTURE_CAPABILITY");
        it.db(() -> jdbc.sql("""
                INSERT INTO helpdesk.agent_assignment (person_id, queue_code, scope_kind, scope_ref, capabilities)
                VALUES (:p, 'STUDENT_BIODATA_SUPPORT', 'FACULTY', :f, ARRAY['EDIT_COURSE_TITLE'])
                """).param("p", agent).param("f", faculty).update());
        assertThat((Map<String, Object>) detail(tok, key).get("may")).containsEntry("correctTitle", true).containsEntry("correctCode", false);
        // the title only: a code change is refused
        assertThat(code(correct(tok, key, p + " 409", "Operating Systems", "ICT_SUPPORT_CORRECTION", null, version(key), true, null))).isEqualTo("STRUCTURE_CAPABILITY");
        String number = "TICK-7120-" + ThreadLocalRandom.current().nextInt(10000, 99999);
        UUID t = it.db(() -> jdbc.sql("""
                INSERT INTO helpdesk.ticket (number, category_id, subject, description, requester_kind, requester_id, requester_name, queue_code, faculty_code, department_code, assigned_to)
                SELECT :n, c.id, 'Course title incorrectly displayed', 'The title should read Operating Systems Concepts', 'STAFF', :a, 'ZZCCR', 'COURSE_REGISTRATION_SUPPORT', NULL, NULL, :a
                  FROM helpdesk.category c WHERE c.code = 'REGISTRATION'
                RETURNING id
                """).param("n", number).param("a", agent).query(UUID.class).single());
        // the classes already examined keep their title when the person correcting says so
        Map<String, Object> byAgent = ok(correct(tok, key, key, "Operating Systems Concepts", "ICT_SUPPORT_CORRECTION", "On the ticket", version(key), false, number));
        assertThat(byAgent).containsEntry("classesRetitled", 0);
        assertThat(course(id)).containsEntry("title", "Operating Systems Concepts");
        assertThat(count("SELECT count(*) FROM catalogue.offering o JOIN catalogue.course c ON c.code = o.course_code WHERE c.id = :i AND o.title = 'Operating Systems'", id)).isEqualTo(1L);
        assertThat(count("SELECT count(*) FROM catalogue.course_change WHERE course_id = :i AND ticket_id IS NOT NULL AND NOT past_classes AND changed_office = 'ictagent'", id)).isEqualTo(1L);
        assertThat(jdbc.sql("SELECT count(*) FROM helpdesk.ticket_event WHERE ticket_id = :t AND to_value LIKE 'Corrected " + y + "%'").param("t", t).query(Integer.class).single()).isEqualTo(1);
        // out of the posting's scope: refused
        assertThat(code(correct(tok, far, far, "Correction Out Of Reach Again", "ICT_SUPPORT_CORRECTION", null, version(far), true, null))).isEqualTo("STRUCTURE_SCOPE");
        // a Head of Department corrects the department's own course as it edits it, and not another department's
        assertThat(status(correct(it.officer("hod", "department", deptB), key, key, "Operating Systems Concepts I", "OFFICIAL_CORRECTION", null, version(key), true, null))).isEqualTo(422);

        // ── the trail, searchable: by the Course ID; refused to an office that does not read it ──
        Map<String, Object> changes = ok(it.get(ict, "/api/v1/catalogue/course-changes?q=" + id));
        assertThat((List<Map<String, Object>>) changes.get("rows")).extracting(r -> r.get("field") + ":" + r.get("old_value") + ">" + r.get("new_value"))
                .contains("TITLE:Operating System>Operating Systems", "CODE:" + x + ">" + key, "TITLE:Operating Systems>Operating Systems Concepts");
        assertThat((List<Map<String, Object>>) changes.get("rows")).anyMatch(r -> number.equals(r.get("ticket")) && "ICT Support correction".equals(r.get("reason_words")));
        assertThat(ok(it.get(ict, "/api/v1/catalogue/course-changes?q=" + x + "&field=CODE")).get("total")).isEqualTo(1);
        assertThat(status(it.get(hodA, "/api/v1/catalogue/course-changes"))).isEqualTo(403);
        // the trail is never altered
        String kept;
        try {
            jdbc.sql("DELETE FROM catalogue.course_change WHERE course_id = :i").param("i", id).update();
            kept = "deleted";
        } catch (RuntimeException e) {
            kept = String.valueOf(e.getMessage());
        }
        assertThat(kept).contains("COURSE_CHANGE_KEPT");
    }
}
