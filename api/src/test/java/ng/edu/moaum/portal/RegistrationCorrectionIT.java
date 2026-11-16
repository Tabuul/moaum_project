package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.util.List;
import java.util.Map;
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
 * V772: Course Registration Correction. A made-up student registered in a session of the run's own for an elective with no result
 * and a core course with a mark. The Director of ICT finds the student by the matriculation number in any case and reads the
 * registration's courses — how each came on, its result; the Registry reads them too, a lecturer and Records do not. The elective is
 * taken off at once (APPLIED: withdrawn, every other course untouched); the core course, carrying a result, is held for the Registry
 * (PENDING) and asked for once only. The officer who asked cannot decide it, under any office; the Director of ICT is not a decider;
 * a decline needs its note; the Registrar confirms it — withdrawn, the mark kept on its sheet — and nothing but the Director's undo
 * puts it back. The list reads the Registry's queue and the student's history, newest first; the Director's undo puts the elective
 * back as it stood. A student not yet given a matriculation number is found by the admission number, as the verification pages find
 * one, and goes by it. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class RegistrationCorrectionIT {

    static final String PATH = "/api/v1/registration/corrections";

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    ItSupport it;
    /** the Director of ICT — one person, who also holds the Registrar's office under another token (the same person, never the decider) */
    final UUID director = UUID.randomUUID();
    final String ict = TestTokens.token(director, List.of("ict"));
    final String directorAsRegistrar = TestTokens.token(director, List.of("registrar"));
    String session;
    String matric;
    UUID student;
    /** a student admitted and not yet matriculated: an admission number and no matriculation number */
    String admissionOnly;
    UUID unmatriculated;
    UUID registration;
    UUID elective;
    UUID core;
    String electiveCode;
    String coreCode;

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
        int year = it.freeYear(2300, 2900);
        session = year + "/" + (year + 1);
        it.session(session, year);
        String yy = String.format("%02d", year % 100);
        int n = it.freeDraw(1000, 9000, k -> List.of("ZZRCR" + k, "MOAUM/RCR/" + yy + "/1" + k, "MOAUM/ADM/" + yy + "/91" + k,
                "ZZRCRN" + k, "MOAUM/ADM/" + yy + "/92" + k));
        matric = "MOAUM/RCR/" + yy + "/1" + n;
        student = it.student("ZZRCR" + n, "C00023", "MOAUM/ADM/" + yy + "/91" + n, matric, 100);
        admissionOnly = "MOAUM/ADM/" + yy + "/92" + n;
        unmatriculated = it.student("ZZRCRN" + n, "C00023", admissionOnly, null, 100);
        String px = it.freeCoursePrefix("Z");
        electiveCode = px + " 201";
        coreCode = px + " 202";
        registration = UUID.randomUUID();
        elective = UUID.randomUUID();
        core = UUID.randomUUID();
        it.db(() -> {
            jdbc.sql("""
                    INSERT INTO catalogue.course (code, title, units, semester, level, dept_code, kind, state, ca_max)
                    SELECT x.code, x.title, x.units, 1, 100, p.dept_code, x.kind, 'LIVE', 40
                      FROM ref.programme p, (VALUES (:e, 'Correction Elective', 2, 'Elective'), (:c, 'Correction Core', 3, 'Core')) x(code, title, units, kind)
                     WHERE p.code = 'C00023'
                    """).param("e", electiveCode).param("c", coreCode).update();
            jdbc.sql("INSERT INTO catalogue.offering (id, course_code, session, semester) VALUES (:e, :ec, :s, 1), (:c, :cc, :s, 1)")
                    .param("e", elective).param("ec", electiveCode).param("c", core).param("cc", coreCode).param("s", session).update();
            jdbc.sql("""
                    INSERT INTO registration.course_registration (id, student_id, session, semester, level, status, submitted_at, approved_at)
                    VALUES (:r, :st, :s, 1, 100, 'APPROVED', now(), now())
                    """).param("r", registration).param("st", student).param("s", session).update();
            jdbc.sql("""
                    INSERT INTO registration.entry (registration_id, offering_id, units, entry_type, status, basis)
                    VALUES (:r, :e, 2, 'CURRENT', 'APPROVED', 'Elective'), (:r, :c, 3, 'CURRENT', 'APPROVED', 'Core')
                    """).param("r", registration).param("e", elective).param("c", core).update();
            // the core course carries a mark (any mark is a result: the removal waits for the Registry)
            jdbc.sql("INSERT INTO assessment.score_sheet (id, offering_id) VALUES (gen_random_uuid(), :c)").param("c", core).update();
            return jdbc.sql("""
                    INSERT INTO assessment.score (sheet_id, student_id, ca, exam, outcome)
                    SELECT sh.id, :st, 20, 30, 'GRADED' FROM assessment.score_sheet sh WHERE sh.offering_id = :c
                    """).param("st", student).param("c", core).update();
        });
    }

    private static Map<String, Object> ok(ResponseEntity<Map> r) {
        assertThat(r.getStatusCode().value()).as(String.valueOf(r.getBody())).isEqualTo(200);
        return r.getBody();
    }

    private static void refused(ResponseEntity<Map> r, int status, String code) {
        assertThat(r.getStatusCode().value()).as(String.valueOf(r.getBody())).isEqualTo(status);
        if (code != null) assertThat(r.getBody()).as(String.valueOf(r.getBody())).containsEntry("code", code);
    }

    private String status(UUID offering) {
        return jdbc.sql("SELECT status FROM registration.entry WHERE registration_id = :r AND offering_id = :o")
                .param("r", registration).param("o", offering).query(String.class).single();
    }

    private Map<String, Object> removal(UUID offering, String reason) {
        return Map.of("studentId", student.toString(), "entries", List.of(Map.of("registrationId", registration.toString(), "offeringId", offering.toString())),
                "reason", reason);
    }

    private List<Map<String, Object>> list(String token, String query) {
        ResponseEntity<List> r = it.getList(token, PATH + query);
        assertThat(r.getStatusCode().value()).isEqualTo(200);
        return (List<Map<String, Object>>) r.getBody();
    }

    @Test
    void theDirectorOfIctTakesAWronglyCountedCourseOffAndTheRegistryDecidesOneWithAResult() {
        String registrar = ItSupport.token("registrar");

        // ── the student, by the matriculation number in any case; the Registry reads, a lecturer and Records do not ──
        Map<String, Object> found = ok(it.get(ict, PATH + "/student?matric=" + matric.toLowerCase()));
        assertThat(found).containsEntry("id", student.toString()).containsEntry("matric", matric).containsEntry("programmeCode", "C00023")
                .containsEntry("level", 100).containsEntry("graduate", false);
        assertThat((List<Map<String, Object>>) found.get("registrations")).singleElement()
                .satisfies(r -> assertThat(r).containsEntry("registrationId", registration.toString()).containsEntry("session", session)
                        .containsEntry("semester", 1).containsEntry("courses", 2));
        ok(it.get(registrar, PATH + "/student?matric=" + matric));
        ok(it.get(ItSupport.token("dregistrar"), PATH + "/student?matric=" + matric));
        refused(it.get(ItSupport.token("lecturer"), PATH + "/student?matric=" + matric), 403, null);
        refused(it.get(ItSupport.token("records"), PATH + "/student?matric=" + matric), 403, null);
        refused(it.get(ict, PATH + "/student?matric=MOAUM/NOPE/" + matric.substring(matric.lastIndexOf('/') + 1)), 404, "RCR_NOT_FOUND");

        // ── the registration's courses: how each came on, its result ──
        ResponseEntity<List> read = it.getList(ict, PATH + "/entries?student=" + student + "&session=" + session + "&semester=1");
        assertThat(read.getStatusCode().value()).isEqualTo(200);
        List<Map<String, Object>> entries = (List<Map<String, Object>>) read.getBody();
        assertThat(entries).extracting(e -> e.get("courseCode") + " " + e.get("hasResult") + " " + e.get("status"))
                .containsExactly(electiveCode + " false APPROVED", coreCode + " true APPROVED");
        assertThat(entries).allSatisfy(e -> assertThat(String.valueOf(e.get("came"))).isIn("STUDENT", "OFFICE", "REGISTRY_LATE", "OLD_PORTAL", "CARRY_OVER", "DEFERRED", "UNKNOWN"));
        assertThat(entries.get(1)).containsEntry("resultWords", "CA 20 + exam 30 = 50").containsEntry("registrationStatus", "APPROVED");
        assertThat(entries.get(0)).containsEntry("isElective", true).containsEntry("elsewhere", List.of());
        assertThat(it.getList(registrar, PATH + "/entries?student=" + student + "&session=" + session + "&semester=1").getStatusCode().value()).isEqualTo(200);

        // ── a removal asked for: the Director of ICT alone, with a reason ──
        refused(it.call(ItSupport.token("lecturer"), HttpMethod.POST, PATH, removal(elective, "The student never chose this elective")), 403, null);
        refused(it.call(registrar, HttpMethod.POST, PATH, removal(elective, "The student never chose this elective")), 403, null);
        refused(it.call(ict, HttpMethod.POST, PATH, removal(elective, "wrong")), 422, "RCR_REASON");
        assertThat(status(elective)).isEqualTo("APPROVED");

        // without a result: withdrawn at once, the other course untouched
        Map<String, Object> applied = ok(it.call(ict, HttpMethod.POST, PATH, removal(elective, "The student never chose this elective")));
        assertThat(applied).containsEntry("graduate", false);
        Map<String, Object> one = ((List<Map<String, Object>>) applied.get("removals")).get(0);
        assertThat(one).containsEntry("state", "APPLIED").containsEntry("courseCode", electiveCode);
        assertThat(String.valueOf(one.get("ref"))).matches("RCR-[0-9]{4}-[0-9]{5,}");
        assertThat(status(elective)).isEqualTo("WITHDRAWN");
        assertThat(status(core)).isEqualTo("APPROVED");

        // with a result: held for the Registry, the course still counted; asked for once only
        Map<String, Object> held = ok(it.call(ict, HttpMethod.POST, PATH, removal(core, "Registered in error by the old portal's upload")));
        Map<String, Object> pending = ((List<Map<String, Object>>) held.get("removals")).get(0);
        assertThat(pending).containsEntry("state", "PENDING");
        String pendingId = String.valueOf(pending.get("id"));
        assertThat(status(core)).isEqualTo("APPROVED");
        refused(it.call(ict, HttpMethod.POST, PATH, removal(core, "Registered in error by the old portal's upload")), 422, "RCR_OPEN");
        assertThat(list(registrar, "?state=PENDING")).extracting(r -> r.get("id")).contains(pendingId);

        // ── the decision: never the Director of ICT, never the officer who asked; a decline says why; the Registrar confirms ──
        refused(it.call(ict, HttpMethod.POST, PATH + "/" + pendingId + "/decide", Map.of("confirm", true)), 403, null);
        refused(it.call(directorAsRegistrar, HttpMethod.POST, PATH + "/" + pendingId + "/decide", Map.of("confirm", true)), 422, "RCR_SAME_PERSON");
        refused(it.call(registrar, HttpMethod.POST, PATH + "/" + pendingId + "/decide", Map.of("confirm", false)), 422, "RCR_NOTE");
        assertThat(ok(it.call(registrar, HttpMethod.POST, PATH + "/" + pendingId + "/decide", Map.of("confirm", true, "note", "Confirmed from the course form on file"))))
                .containsEntry("state", "APPLIED");
        assertThat(status(core)).isEqualTo("WITHDRAWN");
        assertThat(jdbc.sql("""
                SELECT count(*) FROM assessment.score s JOIN assessment.score_sheet sh ON sh.id = s.sheet_id WHERE sh.offering_id = :c AND s.student_id = :st
                """).param("c", core).param("st", student).query(Integer.class).single()).as("the mark stays on its sheet as history").isEqualTo(1);
        refused(it.call(registrar, HttpMethod.POST, PATH + "/" + pendingId + "/decide", Map.of("confirm", true)), 422, "RCR_STATE");
        // nothing but the Director's undo puts it back
        assertThatThrownBy(() -> it.db(() -> jdbc.sql("UPDATE registration.entry SET status = 'APPROVED' WHERE registration_id = :r AND offering_id = :c")
                .param("r", registration).param("c", core).update())).hasMessageContaining("RCR_REMOVED");

        // ── the list: the Registry's queue empty of it, the student's history newest first; a lecturer reads none ──
        assertThat(list(registrar, "?state=PENDING")).extracting(r -> r.get("id")).doesNotContain(pendingId);
        List<Map<String, Object>> history = list(ict, "?student=" + student);
        assertThat(history).extracting(r -> r.get("courseCode") + " " + r.get("state")).containsExactly(coreCode + " APPLIED", electiveCode + " APPLIED");
        assertThat(history.get(0)).containsEntry("hadResult", true).containsEntry("wasStatus", "APPROVED").containsEntry("wasUnits", 3)
                .containsEntry("requestedOffice", "ict").containsEntry("decidedOffice", "registrar").containsEntry("matric", matric);
        refused(it.get(ItSupport.token("lecturer"), PATH + "?student=" + student), 403, null);
        refused(it.get(ict, PATH + "?state=NOPE"), 422, "RCR_LIST_STATE");

        // ── the undo: the Director of ICT's alone, once; the elective back as it stood ──
        String appliedId = String.valueOf(one.get("id"));
        refused(it.call(registrar, HttpMethod.POST, PATH + "/" + appliedId + "/undo", Map.of("reason", "The student did choose the elective after all")), 403, null);
        assertThat(ok(it.call(ict, HttpMethod.POST, PATH + "/" + appliedId + "/undo", Map.of("reason", "The student did choose the elective after all"))))
                .containsEntry("state", "UNDONE");
        assertThat(status(elective)).isEqualTo("APPROVED");
        refused(it.call(ict, HttpMethod.POST, PATH + "/" + appliedId + "/undo", Map.of("reason", "The student did choose the elective after all")), 422, "RCR_STATE");
        assertThat(list(ict, "?student=" + student)).extracting(r -> r.get("courseCode") + " " + r.get("state"))
                .containsExactly(coreCode + " APPLIED", electiveCode + " UNDONE");
    }

    @Test
    void aStudentWithoutAMatriculationNumberIsFoundByTheAdmissionNumber() {
        // found by the admission number in any case, and goes by it; the matriculation number reported apart (none yet)
        Map<String, Object> found = ok(it.get(ict, PATH + "/student?matric=" + admissionOnly.toLowerCase()));
        assertThat(found).containsEntry("id", unmatriculated.toString()).containsEntry("matric", admissionOnly)
                .containsEntry("admissionNo", admissionOnly).containsEntry("programmeCode", "C00023");
        assertThat(found.get("matricNo")).as("no matriculation number yet").isNull();
        assertThat((List<Map<String, Object>>) found.get("registrations")).isEmpty();
        ok(it.get(ItSupport.token("registrar"), PATH + "/student?matric=" + admissionOnly));

        // a matriculated student goes by the matriculation number, and is not found by the admission number they were given before it
        Map<String, Object> matriculated = ok(it.get(ict, PATH + "/student?matric=" + matric));
        assertThat(matriculated).containsEntry("id", student.toString()).containsEntry("matric", matric).containsEntry("matricNo", matric);
        String admitted = String.valueOf(matriculated.get("admissionNo"));
        assertThat(admitted).startsWith("MOAUM/ADM/");
        ResponseEntity<Map> none = it.get(ict, PATH + "/student?matric=" + admitted);
        refused(none, 404, "RCR_NOT_FOUND");
        assertThat(String.valueOf(none.getBody().get("detail"))).contains("matriculation or admission number");
    }
}
