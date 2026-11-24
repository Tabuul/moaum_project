package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.math.BigDecimal;
import java.time.LocalDate;
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
 * V735 — the Summer Semester for final-year and spillover students (the University's master prompt of 12 November 2026), through the
 * API: the Academic Office sets the period; a final-year student with outstanding courses of both semesters reads them, each with the
 * session and semester it was failed in, and cannot select before the Bursary's fees are published; the Bursary states the fees as a
 * draft and the Bursar (not the Student Accounts officer) publishes them; the student selects a first- and a second-semester course
 * (₦50,000 once and ₦5,000 a course), draws one reference, and the payment's confirmation registers both in the Summer (semester 3),
 * approved; a course added later costs its course fee alone; a reference drawn for another figure is refused at the checkout; the
 * desk reads the student with the programme and course fees apart — a Head of another department sees none of it; the Academic Office
 * authorises a 200 Level student for a named course, a reader may not; the Summer's classes are on the allocation desk under semester 3.
 * The test makes its session CURRENT (an IT database has none of its own) and puts the calendar back.
 *
 * V779: the same journey under the new rules — what the page reads carries the evidence on record, the level and, once selected, the
 * verification (a failure the results confirm is confirmed by them, no officer needed); the summary's formula is the server's own
 * total; what is registered carries how it came in; a student's pool where the programme has no structure holds the carry-overs and
 * the authorised courses alone; the identification counts the results it read.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class SummerSemesterIT {

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

    @Test
    void aFinalYearStudentSelectsPaysAndIsRegisteredInTheSummerAndTheDesksReadIt() {
        int y = it.freeYear(3100, 3900, 1, 1);
        String before = (y - 1) + "/" + y, session = y + "/" + (y + 1);
        it.session(before, y - 1);
        it.session(session, y);
        String beforeState = jdbc.sql("SELECT state FROM policy.academic_session WHERE name = :n").param("n", before).query(String.class).single();
        String sessionState = jdbc.sql("SELECT state FROM policy.academic_session WHERE name = :n").param("n", session).query(String.class).single();
        String previousCurrent = jdbc.sql("SELECT name FROM policy.academic_session WHERE state = 'CURRENT' ORDER BY starts_on DESC LIMIT 1").query(String.class).optional().orElse(null);
        String px = it.freeCoursePrefix("Z");
        String c1 = px + " 401", c2 = px + " 402", c3 = px + " 403", c4 = px + " 404";
        String yy = String.format("%02d", y % 100);   // the matriculation number's year: two digits
        int n = it.freeDraw(1000, 9000, k -> List.of("ZZSUMMERA" + k, "ZZSUMMERD" + k, "MOAU/" + px + "/" + yy + "/" + k, "MOAU/" + px + "/" + yy + "/" + (k + 1)));
        // a programme code no run has used (the register's shape: C and five digits)
        String prog = jdbc.sql("""
                SELECT 'C' || lpad(k::text, 5, '0') FROM generate_series(97000, 99999) k
                 WHERE NOT EXISTS (SELECT 1 FROM ref.programme p WHERE p.code = 'C' || lpad(k::text, 5, '0'))
                 ORDER BY random() LIMIT 1
                """).query(String.class).single();
        String matricA = "MOAU/" + px + "/" + yy + "/" + n, matricD = "MOAU/" + px + "/" + yy + "/" + (n + 1);
        String dept = jdbc.sql("SELECT dept_code FROM ref.programme WHERE category = 'UNDER GRADUATE' AND dept_code IS NOT NULL AND NOT archived ORDER BY code LIMIT 1")
                .query(String.class).single();
        String otherDept = jdbc.sql("SELECT code FROM ref.department WHERE ended_on IS NULL AND code <> :d ORDER BY code LIMIT 1").param("d", dept).query(String.class).single();
        try {
            it.db(() -> {
                jdbc.sql("UPDATE policy.academic_session SET state = 'CLOSED' WHERE state = 'CURRENT'").update();
                jdbc.sql("UPDATE policy.academic_session SET state = 'CLOSED' WHERE name = :n").param("n", before).update();
                jdbc.sql("UPDATE policy.academic_session SET state = 'CURRENT', senate_minute = coalesce(senate_minute, 'SEN/IT/735') WHERE name = :n").param("n", session).update();
                jdbc.sql("""
                        INSERT INTO ref.programme (code, name, dept_code, faculty_code, category, min_score, final_level, duration_years, matric_code)
                        SELECT :p, 'B.Sc. Summer IT ' || :p, d.code, d.faculty_code, 'UNDER GRADUATE', 0, 400, 4, :x FROM ref.department d WHERE d.code = :d
                        ON CONFLICT (code) DO NOTHING
                        """).param("p", prog).param("d", dept).param("x", px).update();
                for (Object[] c : new Object[][] {{c1, 3, 1}, {c2, 2, 2}, {c3, 3, 1}, {c4, 2, 2}}) {
                    jdbc.sql("INSERT INTO catalogue.course (code, title, units, semester, level, dept_code, kind, state) VALUES (:c, 'Summer IT ' || :c, :u, :s, 400, :d, 'Core', 'LIVE') ON CONFLICT (code) DO NOTHING")
                            .param("c", c[0]).param("u", c[1]).param("s", c[2]).param("d", dept).update();
                }
                return null;
            });
            UUID a = it.student("ZZSUMMERA" + n, prog, null, matricA, 400);
            UUID d = it.student("ZZSUMMERD" + n, prog, null, matricD, 200);
            // the results of the session before, published as the old portal's past results are loaded: A failed all four
            it.db(() -> {
                jdbc.sql("UPDATE people.student SET entry_session = :e WHERE id IN (:a, :d)").param("e", before).param("a", a).param("d", d).update();
                jdbc.sql("SELECT set_config('moaum.actor_office', 'ict', true)").query().listOfRows();
                jdbc.sql("SELECT assessment.import_legacy_semester(:s, 1, CAST(:rows AS jsonb), true)").param("s", before)
                        .param("rows", "[{\"matric\":\"" + matricA + "\",\"course\":\"" + c1 + "\",\"total\":\"30\",\"level\":\"400\"},"
                                + "{\"matric\":\"" + matricA + "\",\"course\":\"" + c3 + "\",\"total\":\"25\",\"level\":\"400\"}]").query().listOfRows();
                jdbc.sql("SELECT assessment.import_legacy_semester(:s, 2, CAST(:rows AS jsonb), true)").param("s", before)
                        .param("rows", "[{\"matric\":\"" + matricA + "\",\"course\":\"" + c2 + "\",\"total\":\"35\",\"level\":\"400\"},"
                                + "{\"matric\":\"" + matricA + "\",\"course\":\"" + c4 + "\",\"total\":\"20\",\"level\":\"400\"}]").query().listOfRows();
                return null;
            });
            String path = "/api/v1/summer/" + session;

            // ── the Academic Office sets the period; a reader may not ──
            Map<String, Object> period = Map.of("state", "OPEN", "registrationOpens", LocalDate.now().minusDays(1).toString(), "registrationCloses", LocalDate.now().plusDays(10).toString(),
                    "examsFrom", LocalDate.now().plusDays(20).toString(), "examsTo", LocalDate.now().plusDays(25).toString(), "resultsDue", LocalDate.now().plusDays(30).toString(),
                    "categories", List.of("FINAL_YEAR", "SPILLOVER", "BEYOND_DURATION", "AUTHORISED"), "reason", "The Summer of the session, Senate approved");
            assertThat(it.call(ItSupport.token("bursar"), HttpMethod.PUT, path, period).getStatusCode().value()).isEqualTo(403);
            ResponseEntity<Map> set = it.call(ItSupport.token("academic"), HttpMethod.PUT, path, period);
            assertThat(set.getStatusCode().value()).as(String.valueOf(set.getBody())).isEqualTo(200);
            assertThat(set.getBody()).containsEntry("state", "OPEN").containsEntry("open_now", true);

            // ── the student: eligible, four outstanding courses of both semesters, each where it was failed; no fee yet ──
            Map<String, Object> mine = it.get(student(a), "/api/v1/me/summer?session=" + session).getBody();
            assertThat((Map<String, Object>) mine.get("eligibility")).containsEntry("eligible", true).containsEntry("category", "FINAL_YEAR").containsEntry("outstanding", 4);
            List<Map<String, Object>> courses = (List<Map<String, Object>>) mine.get("courses");
            assertThat(courses).extracting(x -> x.get("course_code"), x -> x.get("original_session"), x -> x.get("original_semester"), x -> x.get("selectable"))
                    .containsExactlyInAnyOrder(org.assertj.core.groups.Tuple.tuple(c1, before, 1, true), org.assertj.core.groups.Tuple.tuple(c2, before, 2, true),
                            org.assertj.core.groups.Tuple.tuple(c3, before, 1, true), org.assertj.core.groups.Tuple.tuple(c4, before, 2, true));
            // V779: each course carries the evidence on record (here the failure) and how it came in; it has no verification before it is selected
            // (the API leaves a null out, so the key is absent)
            assertThat(courses).allSatisfy(x -> assertThat(x).containsKeys("evidence", "basis", "source", "selectable").containsEntry("evidence", "RESULT_FAILED").doesNotContainKey("verification"));
            assertThat(mine.get("fee")).isNull();
            ResponseEntity<Map> early = it.call(student(a), HttpMethod.POST, "/api/v1/me/summer/select", Map.of("session", session, "courses", List.of(c1)));
            assertThat(early.getStatusCode().value()).isEqualTo(422);
            assertThat(String.valueOf(early.getBody())).contains("SUMMER_FEE_NOT_PUBLISHED");

            // ── the Bursary states the fees, a draft; the Student Accounts officer may not publish, the Bursar does ──
            String accounts = ItSupport.token("studentaccounts");
            String bursar = ItSupport.token("bursar");
            ResponseEntity<Map> stated = it.call(accounts, HttpMethod.POST, "/api/v1/finance/summer-fees",
                    Map.of("session", session, "programme", prog, "programmeFee", 50000, "courseFee", 5000, "reason", "The Summer fees approved by management"));
            assertThat(stated.getStatusCode().value()).as(String.valueOf(stated.getBody())).isEqualTo(200);
            String fee = String.valueOf(stated.getBody().get("id"));
            assertThat(it.call(accounts, HttpMethod.POST, "/api/v1/finance/summer-fees/" + fee + "/publish", Map.of()).getStatusCode().value()).isEqualTo(403);
            assertThat(it.call(bursar, HttpMethod.POST, "/api/v1/finance/summer-fees/" + fee + "/publish", Map.of()).getStatusCode().value()).isEqualTo(200);
            assertThat(it.call(bursar, HttpMethod.DELETE, "/api/v1/finance/summer-fees/" + fee, null).getStatusCode().value()).isEqualTo(422);

            // ── a first- and a second-semester course selected: ₦60,000 owed, one reference, nothing registered until it is paid ──
            ResponseEntity<Map> chosen = it.call(student(a), HttpMethod.POST, "/api/v1/me/summer/select", Map.of("session", session, "courses", List.of(c1, c2)));
            assertThat(chosen.getStatusCode().value()).as(String.valueOf(chosen.getBody())).isEqualTo(200);
            Map<String, Object> account = (Map<String, Object>) chosen.getBody().get("account");
            assertThat(new BigDecimal(String.valueOf(account.get("due")))).isEqualByComparingTo("60000");
            assertThat((List<?>) chosen.getBody().get("registered")).isEmpty();
            // V779: a failure on record confirms itself by the results, no officer; the summary's formula is the server's own total
            List<Map<String, Object>> selectedRows = ((List<Map<String, Object>>) chosen.getBody().get("courses")).stream().filter(x -> List.of(c1, c2).contains(x.get("course_code"))).toList();
            assertThat(selectedRows).hasSize(2).allSatisfy(x -> assertThat(x).containsEntry("verification", "CONFIRMED_OUTSTANDING").containsEntry("verified_via", "RESULTS").containsEntry("status", "SELECTED"));
            Map<String, Object> summary = (Map<String, Object>) chosen.getBody().get("summary");
            assertThat(summary).containsEntry("selected", 2).containsEntry("confirmed", 2).containsEntry("pending", 0);
            assertThat(new BigDecimal(String.valueOf(((Map<String, Object>) summary.get("formula")).get("total")))).isEqualByComparingTo("60000");
            ResponseEntity<Map> ref = it.call(student(a), HttpMethod.POST, "/api/v1/me/summer/reference", Map.of("session", session));
            assertThat(ref.getStatusCode().value()).as(String.valueOf(ref.getBody())).isEqualTo(200);
            String reference = String.valueOf(ref.getBody().get("reference"));
            assertThat(new BigDecimal(String.valueOf(ref.getBody().get("amount")))).isEqualByComparingTo("60000");
            assertThat(it.call(student(a), HttpMethod.POST, "/api/v1/me/summer/reference", Map.of("session", session)).getBody()).containsEntry("reference", reference);

            // ── paid (the bank's confirmation): both registered in the Summer, approved, each with its own semester and the session it was failed in ──
            confirm(reference);
            Map<String, Object> paid = it.get(student(a), "/api/v1/me/summer?session=" + session).getBody();
            List<Map<String, Object>> registered = (List<Map<String, Object>>) paid.get("registered");
            assertThat(registered).extracting(x -> x.get("course_code"), x -> x.get("course_semester"), x -> x.get("original_session"), x -> x.get("registration_status"))
                    .containsExactlyInAnyOrder(org.assertj.core.groups.Tuple.tuple(c1, 1, before, "APPROVED"), org.assertj.core.groups.Tuple.tuple(c2, 2, before, "APPROVED"));
            // V779: and how each came in and what the Academic Office has found of it
            assertThat(registered).allSatisfy(x -> assertThat(x).containsEntry("basis", "CARRY_OVER").containsEntry("verification", "CONFIRMED_OUTSTANDING")
                    .containsEntry("verified_via", "RESULTS").containsEntry("category_label", "Carry-over"));
            assertThat(jdbc.sql("SELECT count(*) FROM registration.course_registration WHERE student_id = :s AND session = :ss AND semester = 3")
                    .param("s", a).param("ss", session).query(Integer.class).single()).isEqualTo(1);

            // ── a third course later: its course fee alone; a reference drawn, then the selection changed: that reference is not taken ──
            Map<String, Object> third = it.call(student(a), HttpMethod.POST, "/api/v1/me/summer/select", Map.of("session", session, "courses", List.of(c3))).getBody();
            assertThat(new BigDecimal(String.valueOf(((Map<String, Object>) third.get("account")).get("due")))).isEqualByComparingTo("5000");
            String staleRef = String.valueOf(it.call(student(a), HttpMethod.POST, "/api/v1/me/summer/reference", Map.of("session", session)).getBody().get("reference"));
            it.call(student(a), HttpMethod.POST, "/api/v1/me/summer/select", Map.of("session", session, "courses", List.of(c4)));
            ResponseEntity<Map> stale = it.call(student(a), HttpMethod.POST, "/api/v1/payments/checkout", Map.of("reference", staleRef));
            assertThat(stale.getStatusCode().value()).isEqualTo(422);
            assertThat(jdbc.sql("SELECT registration.summer_reference_payable(:r)").param("r", staleRef).query(Boolean.class).single()).isFalse();
            String fresh = String.valueOf(it.call(student(a), HttpMethod.POST, "/api/v1/me/summer/reference", Map.of("session", session)).getBody().get("reference"));
            assertThat(fresh).isNotEqualTo(staleRef);
            assertThat(jdbc.sql("SELECT amount FROM finance.payment_reference WHERE reference = :r").param("r", fresh).query(BigDecimal.class).single()).isEqualByComparingTo("10000");
            assertThat(jdbc.sql("SELECT registration.summer_reference_payable(:r)").param("r", fresh).query(Boolean.class).single()).isTrue();

            // ── the desk: the student with the programme and course fees apart; a Head of another department sees none of it ──
            ResponseEntity<Map> identified = it.call(ItSupport.token("academic"), HttpMethod.POST, path + "/identify", Map.of("limit", 2000));
            assertThat(identified.getStatusCode().value()).as(String.valueOf(identified.getBody())).isEqualTo(200);
            assertThat(identified.getBody()).containsKeys("read", "left", "eligible", "since", "results");
            Map<String, Object> desk = it.get(ItSupport.token("academic"), path + "/students").getBody();
            Map<String, Object> rowA = ((List<Map<String, Object>>) desk.get("rows")).stream().filter(r -> String.valueOf(a).equals(String.valueOf(r.get("student_id")))).findFirst().orElseThrow();
            assertThat(new BigDecimal(String.valueOf(rowA.get("programme_fee_paid")))).isEqualByComparingTo("50000");
            assertThat(new BigDecimal(String.valueOf(rowA.get("course_fees_paid")))).isEqualByComparingTo("10000");
            assertThat(rowA).containsEntry("payment_state", "PART_PAID").containsEntry("courses_registered", 2).containsEntry("eligible", true);
            String otherHod = it.officer("hod", "department", otherDept);
            List<Map<String, Object>> theirs = (List<Map<String, Object>>) it.get(otherHod, path + "/students").getBody().get("rows");
            assertThat(theirs).noneMatch(r -> String.valueOf(a).equals(String.valueOf(r.get("student_id"))));
            assertThat(it.get(student(a), path + "/students").getStatusCode().value()).isEqualTo(403);

            // ── the Academic Office authorises a 200 Level student for a named course; a reader may not ──
            assertThat(String.valueOf(((Map<String, Object>) it.get(student(d), "/api/v1/me/summer?session=" + session).getBody().get("eligibility")).get("reason")))
                    .isEqualTo("NOT_FINAL_OR_SPILLOVER");
            Map<String, Object> grant = Map.of("number", matricD, "courses", List.of(c1), "reason", "Senate approval: a deficiency course before graduation", "revoke", false);
            assertThat(it.call(ItSupport.token("bursar"), HttpMethod.POST, path + "/authorise", grant).getStatusCode().value()).isEqualTo(403);
            ResponseEntity<Map> granted = it.call(ItSupport.token("academic"), HttpMethod.POST, path + "/authorise", grant);
            assertThat(granted.getStatusCode().value()).as(String.valueOf(granted.getBody())).isEqualTo(200);
            assertThat((Map<String, Object>) granted.getBody().get("eligibility")).containsEntry("eligible", true).containsEntry("category", "AUTHORISED");
            // V779: the programme has no structure here, so the pool holds that one course alone
            assertThat((List<Map<String, Object>>) it.get(student(d), "/api/v1/me/summer?session=" + session).getBody().get("courses"))
                    .extracting(x -> x.get("course_code"), x -> x.get("basis")).containsExactly(org.assertj.core.groups.Tuple.tuple(c1, "AUTHORISED"));

            // ── the Summer's classes on the allocation desk, semester 3, and the Bursary's collections apart ──
            List<Map<String, Object>> classes = (List<Map<String, Object>>) (List<?>) it.getList(ItSupport.token("academic"),
                    "/api/v1/allocation?dept=" + dept + "&session=" + session + "&semester=3").getBody();
            assertThat(classes).extracting(x -> x.get("course_code")).contains(c1, c2).doesNotContain(c3, c4);
            Map<String, Object> fees = it.get(bursar, "/api/v1/finance/summer-fees?session=" + session).getBody();
            Map<String, Object> collected = ((List<Map<String, Object>>) fees.get("collections")).get(0);
            assertThat(new BigDecimal(String.valueOf(collected.get("programme_fees_paid")))).isGreaterThanOrEqualTo(new BigDecimal("50000"));
            assertThat(new BigDecimal(String.valueOf(collected.get("course_fees_paid")))).isGreaterThanOrEqualTo(new BigDecimal("10000"));

            // ── V739: the desk is read in an office that reads it, whatever other offices the token carries ──
            String hodLecturer = TestTokens.token(UUID.randomUUID(), List.of("hod", "lecturer"));
            assertThat(it.callWith(hodLecturer, HttpMethod.GET, path + "/students", null, Map.of("X-Active-Office", "lecturer")).getStatusCode().value()).isEqualTo(403);
            assertThat(it.callWith(hodLecturer, HttpMethod.GET, path + "/courses", null, Map.of("X-Active-Office", "lecturer")).getStatusCode().value()).isEqualTo(403);

            // ── V741: both unpaid courses passed since they were chosen — drawing takes them back, nothing is owed, and the take-back stands ──
            it.db(() -> {
                jdbc.sql("SELECT set_config('moaum.actor_office', 'ict', true)").query().listOfRows();
                jdbc.sql("SELECT assessment.import_legacy_semester(:s, 1, CAST(:rows AS jsonb), true)").param("s", session)
                        .param("rows", "[{\"matric\":\"" + matricA + "\",\"course\":\"" + c3 + "\",\"total\":\"61\",\"level\":\"400\"}]").query().listOfRows();
                jdbc.sql("SELECT assessment.import_legacy_semester(:s, 2, CAST(:rows AS jsonb), true)").param("s", session)
                        .param("rows", "[{\"matric\":\"" + matricA + "\",\"course\":\"" + c4 + "\",\"total\":\"62\",\"level\":\"400\"}]").query().listOfRows();
                return null;
            });
            // V742: the reference drawn for them is no longer payable, so the student's Pay draws again
            assertThat(jdbc.sql("SELECT registration.summer_reference_payable(:r)").param("r", fresh).query(Boolean.class).single()).isFalse();
            ResponseEntity<Map> nothing = it.call(student(a), HttpMethod.POST, "/api/v1/me/summer/reference", Map.of("session", session));
            assertThat(nothing.getStatusCode().value()).as(String.valueOf(nothing.getBody())).isEqualTo(200);
            assertThat(nothing.getBody().get("reference")).isNull();   // the API leaves a null out
            assertThat(nothing.getBody()).containsEntry("takenBack", true);
            assertThat(jdbc.sql("SELECT string_agg(state, ',' ORDER BY course_code) FROM registration.summer_charge WHERE student_id = :s AND session = :ss AND course_code IN (:c3, :c4)")
                    .param("s", a).param("ss", session).param("c3", c3).param("c4", c4).query(String.class).single()).isEqualTo("CANCELLED,CANCELLED");

            // ── V739: the Summer closed — what is selected and unpaid is taken back, and the students are no longer told it is open ──
            Map<String, Object> closedPeriod = new java.util.HashMap<>(period);
            closedPeriod.put("state", "CLOSED");
            assertThat(it.call(ItSupport.token("academic"), HttpMethod.PUT, path, closedPeriod).getStatusCode().value()).isEqualTo(200);
            assertThat(jdbc.sql("SELECT count(*) FROM registration.summer_charge WHERE student_id = :s AND session = :ss AND state = 'DUE'")
                    .param("s", a).param("ss", session).query(Integer.class).single()).isZero();
            ResponseEntity<Map> told = it.call(ItSupport.token("academic"), HttpMethod.POST, path + "/tell", Map.of("kind", "OPEN"));
            assertThat(told.getStatusCode().value()).isEqualTo(422);
            assertThat(String.valueOf(told.getBody())).contains("SUMMER_NOT_TO_TELL");
        } finally {
            it.db(() -> {
                jdbc.sql("UPDATE policy.academic_session SET state = :st WHERE name = :n").param("st", sessionState).param("n", session).update();
                jdbc.sql("UPDATE policy.academic_session SET state = :st WHERE name = :n").param("st", beforeState).param("n", before).update();
                if (previousCurrent != null && !previousCurrent.equals(session)) jdbc.sql("UPDATE policy.academic_session SET state = 'CURRENT' WHERE name = :n").param("n", previousCurrent).update();
                return null;
            });
        }
    }

    /** a bank's confirmation, as the Bursary's lane records it */
    private void confirm(String reference) {
        it.db(() -> {
            jdbc.sql("SELECT set_config('moaum.actor_office', 'bursar', true)").query().listOfRows();
            return jdbc.sql("SELECT finance.confirm_payment(:r, 'Bank transfer', 'SummerSemesterIT')").param("r", reference).query(String.class).single();
        });
    }
}
