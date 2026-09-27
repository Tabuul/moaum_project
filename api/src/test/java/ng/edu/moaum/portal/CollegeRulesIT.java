package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.time.LocalDate;
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
 * Every College policy acts (V285): the calendar must be dated before a year takes results; the strictest attendance rule that
 * reaches a subject bars the sitting — the phase's 75% for the 1st Professional, the Surgery block's 80% for the Final; a resit
 * is recorded only within the resit window; a decision names carry-overs of GST and EPS only, which the Board's confirmation
 * writes to the register and tells the student, and which the desk clears on a minute; the rules desk reads and sets the
 * thresholds and refuses weights that do not total 100; the Board's 100 Level act runs; the College's offices may search.
 * Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class CollegeRulesIT {

    static final String SESSION = "2096/2097";
    static final String BASE = "/api/v1/college";

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    ItSupport it;
    String secretary = ItSupport.token("collegesecretary");
    String finance = ItSupport.token("financecontroller");

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
        it.session(SESSION, 2096);
    }

    static Map<String, Object> m(Object o) { return (Map<String, Object>) o; }
    static List<Map<String, Object>> l(Object o) { return (List<Map<String, Object>>) o; }

    UUID subject(String exam, String name) {
        return jdbc.sql("SELECT s.id FROM college.exam_subject s JOIN college.professional_exam e ON e.id = s.exam_id WHERE e.code = :e AND s.name = :n")
                .param("e", exam).param("n", name).query(UUID.class).single();
    }

    /** a College student at a level with the year open in the session, and the level's calendar dated so the year has reached its end */
    UUID candidate(String tag, int level) {
        int n = new Random().nextInt(9000) + 1000;
        UUID s = it.student(tag + n, "C00061", "MOAUM/ADM/96/" + String.format("%06d", (level / 100) * 10000 + n), "MOAUM/MED/96/" + (level / 100) + n, level);
        it.db(() -> jdbc.sql("UPDATE people.student SET entry_session = :s, entry_mode = 'UTME' WHERE id = :id").param("s", (2096 - (level / 100) + 1) + "/" + (2096 - (level / 100) + 2)).param("id", s).update());
        it.db(() -> jdbc.sql("INSERT INTO people.student_contact (student_id, phone, email, updated_at) VALUES (:s, '08033335555', :e, now()) ON CONFLICT (student_id) DO UPDATE SET email = EXCLUDED.email, phone = EXCLUDED.phone").param("s", s).param("e", tag.toLowerCase() + n + "@example.edu").update());   // the notices reach somebody
        it.db(() -> jdbc.sql("SELECT college.open_enrolment(:s, :l, :ses, NULL)").param("s", s).param("l", level).param("ses", SESSION).query(UUID.class).single());
        return s;
    }

    void dateYear(int level) {
        int semesters = jdbc.sql("SELECT count(*) FROM college.semester_template WHERE level = :l").param("l", level).query(Integer.class).single();
        for (int o = 1; o <= Math.max(1, semesters); o++) {
            ResponseEntity<Map> r = it.call(secretary, HttpMethod.PUT, BASE + "/calendar", Map.of("session", SESSION, "level", level, "ordinal", o,
                    "startsOn", LocalDate.now().minusDays(400 - o * 100L).toString(), "endsOn", LocalDate.now().minusDays(380 - o * 100L).toString()));
            assertThat(r.getStatusCode().value()).as(String.valueOf(r.getBody())).isEqualTo(200);
        }
    }

    ResponseEntity<Map> result(String code, UUID student, UUID subject, String attempt, Integer ca, Integer exam, Integer clinical, Integer attendance) {
        java.util.Map<String, Object> body = new java.util.LinkedHashMap<>();
        body.put("session", SESSION); body.put("studentId", student); body.put("subjectId", subject); body.put("attempt", attempt);
        if (ca != null) body.put("caScore", ca); if (exam != null) body.put("examScore", exam); if (clinical != null) body.put("clinicalScore", clinical); if (attendance != null) body.put("attendancePct", attendance);
        return it.call(secretary, HttpMethod.POST, BASE + "/exams/" + code + "/results", body);
    }

    @Test
    void theCalendarTheAttendanceTheResitWindowTheCarryOversAndTheBoardActAsTheRulesSay() {
        UUID anatomy = subject("PE1", "Anatomy"), biochem = subject("PE1", "Medical Biochemistry"), physio = subject("PE1", "Physiology");
        UUID s = candidate("ZZRULE", 300);
        it.db(() -> jdbc.sql("DELETE FROM college.semester WHERE session = :s").param("s", SESSION).update());   // an undated year, whatever an earlier run dated

        // 1 · the rules desk reads the regulations; the College's offices read it, the Finance Controller may search
        Map<String, Object> rules = m(it.get(secretary, BASE + "/rules").getBody());
        assertThat(l(rules.get("exams")).stream().map(x -> x.get("code"))).contains("CPE", "PE1", "PE4");
        Map<String, Object> pe1Anatomy = l(rules.get("subjects")).stream().filter(x -> anatomy.toString().equals(String.valueOf(x.get("id")))).findFirst().orElseThrow();
        assertThat(((Number) pe1Anatomy.get("min_attendance")).intValue()).isEqualTo(75);   // the examination's 75, and the preclinical phase's 75
        Map<String, Object> surgeryRow = l(rules.get("subjects")).stream().filter(x -> "PE4".equals(x.get("exam")) && "Surgery".equals(x.get("name"))).findFirst().orElseThrow();
        assertThat(((Number) surgeryRow.get("min_attendance")).intValue()).isEqualTo(80);   // the Surgery block's 80 reaches the subject; the Final states none of its own
        assertThat(it.get(finance, "/api/v1/student/students?q=ZZRULE").getStatusCode().value()).isEqualTo(200);
        // weights that do not total 100 are refused; the distinction mark is the programme's to set
        assertThat(it.call(secretary, HttpMethod.PUT, BASE + "/rules/subjects/" + anatomy, Map.of("caWeight", 40, "examWeight", 50)).getStatusCode().value()).isEqualTo(422);
        ResponseEntity<Map> pr = it.call(secretary, HttpMethod.PUT, BASE + "/rules/programme/C00061", Map.of("distinctionMark", 70, "resitWindowMonths", 3));
        assertThat(pr.getStatusCode().value()).as(String.valueOf(pr.getBody())).isEqualTo(200);

        // 2 · an undated year takes no results; dated, it does — and the phase rule bars a candidate under 75%
        ResponseEntity<Map> early = result("PE1", s, anatomy, "FIRST", 20, 45, null, 90);
        assertThat(early.getStatusCode().value()).isEqualTo(422);
        assertThat(early.getBody().get("code")).isEqualTo("COLLEGE_YEAR_NOT_ENDED");
        dateYear(300);
        ResponseEntity<Map> barred = result("PE1", s, anatomy, "FIRST", 20, 45, null, 70);
        assertThat(barred.getStatusCode().value()).as(String.valueOf(barred.getBody())).isEqualTo(200);
        assertThat(barred.getBody().get("barred")).isEqualTo(true);
        assertThat(barred.getBody().get("passed")).isEqualTo(false);
        assertThat(((Number) barred.getBody().get("minAttendance")).intValue()).isEqualTo(75);

        // 3 · the resit window: a first attempt failed four months ago takes no resit; decided today, it does
        ResponseEntity<Map> failed = result("PE1", s, anatomy, "FIRST", 10, 20, null, 90);
        assertThat(failed.getBody().get("passed")).isEqualTo(false);
        it.db(() -> jdbc.sql("UPDATE college.exam_result SET decided_on = current_date - interval '4 months' WHERE student_id = :s AND subject_id = :sub AND attempt = 'FIRST'").param("s", s).param("sub", anatomy).update());
        ResponseEntity<Map> late = result("PE1", s, anatomy, "RESIT", 20, 45, null, 90);
        assertThat(late.getStatusCode().value()).isEqualTo(422);
        assertThat(late.getBody().get("code")).isEqualTo("COLLEGE_RESIT_WINDOW");
        it.db(() -> jdbc.sql("UPDATE college.exam_result SET decided_on = current_date WHERE student_id = :s AND subject_id = :sub AND attempt = 'FIRST'").param("s", s).param("sub", anatomy).update());
        assertThat(result("PE1", s, anatomy, "RESIT", 20, 45, null, 90).getStatusCode().value()).isEqualTo(200);

        // 4 · every subject passed → PROMOTE provisionally; a decision may carry GST and EPS only; the Board's confirmation writes the carry-over, promotes, tells the student
        assertThat(result("PE1", s, biochem, "FIRST", 25, 50, null, 90).getBody().get("passed")).isEqualTo(true);
        Map<String, Object> last = result("PE1", s, physio, "FIRST", 25, 50, null, 90).getBody();
        assertThat(last.get("outcome")).isEqualTo("PROMOTE");
        ResponseEntity<Map> badCarry = it.call(secretary, HttpMethod.POST, BASE + "/exams/PE1/decisions", Map.of("session", SESSION, "studentId", s, "outcome", "PROMOTE", "carryOvers", List.of("PHY101")));
        assertThat(badCarry.getStatusCode().value()).isEqualTo(422);
        assertThat(badCarry.getBody().get("code")).isEqualTo("COLLEGE_CARRY_OVER");
        assertThat(it.call(secretary, HttpMethod.POST, BASE + "/exams/PE1/decisions", Map.of("session", SESSION, "studentId", s, "outcome", "PROMOTE", "carryOvers", List.of("GST101"))).getStatusCode().value()).isEqualTo(200);
        ResponseEntity<Map> confirmed = it.call(secretary, HttpMethod.POST, BASE + "/exams/PE1/confirm", Map.of("session", SESSION, "minute", "CAB/96/01"));
        assertThat(confirmed.getStatusCode().value()).as(String.valueOf(confirmed.getBody())).isEqualTo(200);
        assertThat(jdbc.sql("SELECT current_level FROM people.student WHERE id = :s").param("s", s).query(Integer.class).single()).isEqualTo(400);
        assertThat(jdbc.sql("SELECT count(*) FROM college.carry_over WHERE student_id = :s AND code = 'GST101' AND cleared_on IS NULL").param("s", s).query(Long.class).single()).isEqualTo(1);
        assertThat(jdbc.sql("SELECT count(*) FROM platform.notice WHERE about_kind = 'student' AND about_id = :s AND subject LIKE 'College Academic Board%'").param("s", s).query(Long.class).single()).isGreaterThanOrEqualTo(1);
        // the desk lists it and clears it on a minute
        assertThat(l(m(it.get(secretary, BASE + "/carry-overs?q=ZZRULE").getBody()).get("rows")).stream().map(x -> x.get("code"))).contains("GST101");
        assertThat(it.call(secretary, HttpMethod.POST, BASE + "/carry-overs/clear", Map.of("studentId", s, "code", "GST101", "minute", "")).getStatusCode().value()).isIn(400, 422);
        ResponseEntity<Map> cleared = it.call(secretary, HttpMethod.POST, BASE + "/carry-overs/clear", Map.of("studentId", s, "code", "GST101", "minute", "CAB/96/02"));
        assertThat(cleared.getStatusCode().value()).as(String.valueOf(cleared.getBody())).isEqualTo(200);
        assertThat(jdbc.sql("SELECT cleared_on IS NOT NULL FROM college.carry_over WHERE student_id = :s AND code = 'GST101'").param("s", s).query(Boolean.class).single()).isTrue();

        // 5 · the Surgery block's 80% bars a Final candidate at 79% though the Final states no minimum of its own
        UUID f = candidate("ZZRULF", 600);
        dateYear(600);
        UUID surgery = subject("PE4", "Surgery");
        ResponseEntity<Map> surg = result("PE4", f, surgery, "FIRST", 25, 50, 60, 79);
        assertThat(surg.getStatusCode().value()).as(String.valueOf(surg.getBody())).isEqualTo(200);
        assertThat(surg.getBody().get("barred")).isEqualTo(true);
        assertThat(((Number) surg.getBody().get("minAttendance")).intValue()).isEqualTo(80);
        assertThat(result("PE4", f, surgery, "FIRST", 25, 50, 60, 85).getBody().get("barred")).isEqualTo(false);

        // 6 · the Board's act on the 100 Level rule runs on a minute (no entrant of this session stands at 100 Level, so nothing moves)
        assertThat(it.call(secretary, HttpMethod.POST, BASE + "/level100/confirm", Map.of("session", SESSION, "minute", "")).getStatusCode().value()).isIn(400, 422);
        ResponseEntity<Map> act = it.call(secretary, HttpMethod.POST, BASE + "/level100/confirm", Map.of("session", SESSION, "minute", "CAB/96/03"));
        assertThat(act.getStatusCode().value()).as(String.valueOf(act.getBody())).isEqualTo(200);
        assertThat(((Number) act.getBody().get("promoted")).intValue()).isGreaterThanOrEqualTo(0);
    }
}
