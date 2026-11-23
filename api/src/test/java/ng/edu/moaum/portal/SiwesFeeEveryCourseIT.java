package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.math.BigDecimal;
import java.util.ArrayList;
import java.util.HashMap;
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
 * V777 (the University's word of 22 November 2026, "yes charge every siwes course"): every SIWES course — a catalogue course the
 * Academic Office marks, whatever its code and title — carries the one SIWES registration fee, paid once a session before the student
 * registers it, whatever the programme, level or semester, through the API. Each test makes its own session (the student's current
 * one), programmes, courses and students, and puts the session, the calendar, the fee lines and the rules back.
 * <ul>
 *   <li>a Communication-like student, SIWES the one course of the First Semester at 300 Level (V503's attachment semester) of a
 *       programme the Academic Office never configured: refused while the Bursary has published no fee (SIWES_FEE_NOT_SET) — with a
 *       fee stated and not yet published too, a draft being no fee in force — then until the fee is paid (SIWES_UNPAID), the form
 *       locking the row with the database's words; paid on the SIWES page, the course is registered on Course Registration at
 *       exactly its units and the registration approved; a plain course is never charged;</li>
 *   <li>a Nursing-like student, the SIWES course beside required courses in the Second Semester: the other courses register freely,
 *       the SIWES course waits for the fee, on the form, in the Add Other Course search and on save; the SIWES page reads COURSE;</li>
 *   <li>a spillover student's carry-over picker marking the SIWES carry-over held, adding it refused until the fee is paid and the
 *       registration left as it was (a spillover registration places no carry-over of its own, V682, so the form's save is no proof
 *       of anything here); a student with a failed SIWES course of an earlier level whose save places it only once the fee is paid —
 *       the form's save never placing an unpaid carry-over is that student's, a student who is not in spillover;</li>
 *   <li>SIWES in both semesters of a level under one payment, the fee never paid twice;</li>
 *   <li>a student the programme carries no SIWES course for, who holds none and owes none: not asked, cannot draw a reference, a SIWES
 *       course an office places on them refused SIWES_NOT_IN_REACH;</li>
 *   <li>the refund desk refusing the payment a course registration stands on, releasing it once the student drops the course on the
 *       ordinary form, the refunded fee asked again;</li>
 *   <li>a SIWES course entered at the instant its payment's refund is approved: one of the two happens, never both;</li>
 *   <li>the old portal's payers of either semester registering freely;</li>
 *   <li>a student holding a SIWES course from before the rule, unpaid, asked and able to pay, never refused at approval, and listed on
 *       the Bursary's list of the SIWES courses held with no SIWES payment (the desk's readers allowed, the auditors, a lecturer and a
 *       student refused);</li>
 *   <li>that list read by a Head of Department, the SIWES Coordinator, a Dean and a Faculty Officer: each held to its own unit
 *       whatever is asked (another unit's department or programme refused, its own students none), then filtered by faculty,
 *       department, programme and a name or matric number, paged, and counted by rows and by students (a student holding two unpaid
 *       courses is two rows and one student), the fee null while none is published;</li>
 *   <li>a student of a programme the Academic Office configured whose period is still a draft (the shape of the programmes seeded
 *       before V777): the SIWES course is charged as any is, refused until the fee is paid and registered, linked to the payment, once
 *       it is;</li>
 *   <li>a SIWES course the old portal's registration loader places on a student of the current session: it stands unpaid and
 *       unlinked, on the Bursary's list, while the student's own door still refuses it.</li>
 * </ul>
 * Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class SiwesFeeEveryCourseIT {

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

    static int status(ResponseEntity<?> r) {
        return r.getStatusCode().value();
    }

    static String code(ResponseEntity<Map> r) {
        return r.getBody() == null ? null : String.valueOf(r.getBody().get("code"));
    }

    static BigDecimal money(Object o) {
        return new BigDecimal(String.valueOf(o));
    }

    private static Map<String, Object> menuRow(Map<String, Object> view, String course) {
        return ((List<Map<String, Object>>) view.get("menu")).stream().filter(m -> course.equals(m.get("course_code"))).findFirst()
                .orElseThrow(() -> new AssertionError("no menu row " + course + " in " + view.get("menu")));
    }

    /** a bank's confirmation, as the Bursary's lane records it */
    private String confirm(String reference) {
        return it.db(() -> {
            jdbc.sql("SELECT set_config('moaum.actor_office', 'bursar', true)").query().listOfRows();
            return jdbc.sql("SELECT finance.confirm_payment(:r, 'Bank transfer', 'SiwesFeeEveryCourseIT')").param("r", reference).query(String.class).single();
        });
    }

    /** the old portal's SIWES payment of the session, as its import records it ("SIWES (legacy)"), for a semester of its purpose */
    private void oldPortalSiwes(UUID student, String session, int semester, String tag) {
        it.db(() -> jdbc.sql("""
                INSERT INTO finance.payment_reference (student_id, session, reference, purpose, amount, generated_at, expires_at, confirmed_at, confirmed_by,
                                                       channel, note, receipt_no)
                VALUES (:s, :ses, 'MOAUM-LEG-IT777-' || :t, 'SIWES (legacy) · semester ' || :m, 4000, now() - interval '30 days', now() - interval '30 days',
                        now() - interval '30 days', gen_random_uuid(), 'Legacy', 'Imported from the old portal', 'RCT-LEG-IT777-' || :t)
                """).param("s", student).param("ses", session).param("t", tag).param("m", semester).update());
    }

    /** the SIWES course entries of the student in the session, each with the payment it stands on (the reference) */
    private List<String> linked(UUID student, String session) {
        return jdbc.sql("""
                SELECT x.course_code || '<' || r.reference FROM registration.siwes_course_entry x
                  JOIN finance.payment_reference r ON r.id IN (x.payment_reference_id, x.legacy_payment_id)
                 WHERE x.student_id = :s AND x.session = :ses ORDER BY x.course_code
                """).param("s", student).param("ses", session).query(String.class).list();
    }

    /** the courses standing on the student's registrations of the session (not dropped), with their status */
    private List<String> standing(UUID student, String session) {
        return jdbc.sql("""
                SELECT o.course_code || ':' || e.status FROM registration.entry e JOIN registration.course_registration r ON r.id = e.registration_id
                  JOIN catalogue.offering o ON o.id = e.offering_id
                 WHERE r.student_id = :s AND r.session = :ses AND e.status NOT IN ('DROPPED', 'WITHDRAWN') ORDER BY o.course_code
                """).param("s", student).param("ses", session).query(String.class).list();
    }

    /**
     * What every test needs, made from nothing and put back: the test's own session, made the University's current one (the session a
     * SIWES fee is judged in), the one before it, a department and programmes of its own, courses of its own prefix, students, the
     * Bursary's fee and the school fees of the students who submit.
     */
    private final class World implements AutoCloseable {
        final int y;
        final String before, session, px, yy, instrument, dept;
        final String beforeState, sessionState, previousCurrent;
        final int n;
        int next = 0;
        String basisBefore;
        final Map<UUID, String> surnames = new HashMap<>();

        World(String tag) {
            int year = it.freeYear(5100, 5800, 1, 1);
            y = year;
            before = (year - 1) + "/" + year;
            session = year + "/" + (year + 1);
            yy = String.format("%02d", year % 100);
            instrument = "BUR/IT/SIWES777/" + tag;
            it.session(before, year - 1);
            it.session(session, year);
            String prefix = it.freeCoursePrefix("Z");
            px = prefix;
            String twoDigits = yy;
            n = it.freeDraw(1000, 8000, k -> {
                List<String> ids = new ArrayList<>();
                for (int i = 0; i < 30; i++) {
                    ids.add("ZZFEE" + k + "S" + i);
                    ids.add("MOAU/" + prefix + "/" + twoDigits + "/" + (k * 30 + i));
                }
                return ids;
            });
            String base = jdbc.sql("SELECT dept_code FROM ref.programme WHERE category = 'UNDER GRADUATE' AND dept_code IS NOT NULL AND NOT archived ORDER BY code LIMIT 1")
                    .query(String.class).single();
            // the department of the run's own: the SIWES courses the run makes are the only ones it holds
            dept = jdbc.sql("""
                    SELECT 'ZV' || lpad(k::text, 4, '0') FROM generate_series(1000, 9999) k
                     WHERE NOT EXISTS (SELECT 1 FROM ref.department d WHERE d.code = 'ZV' || lpad(k::text, 4, '0')) ORDER BY random() LIMIT 1
                    """).query(String.class).single();
            beforeState = jdbc.sql("SELECT state FROM policy.academic_session WHERE name = :n").param("n", before).query(String.class).single();
            sessionState = jdbc.sql("SELECT state FROM policy.academic_session WHERE name = :n").param("n", session).query(String.class).single();
            previousCurrent = jdbc.sql("SELECT name FROM policy.academic_session WHERE state = 'CURRENT' ORDER BY starts_on DESC LIMIT 1").query(String.class).optional().orElse(null);
            it.db(() -> jdbc.sql("INSERT INTO ref.department (code, name, faculty_code) SELECT :m, 'SIWES FEE IT ' || :m, d.faculty_code FROM ref.department d WHERE d.code = :d")
                    .param("m", dept).param("d", base).update());
            // last: the session the student's SIWES fee is judged in is this one, until close()
            it.db(() -> {
                jdbc.sql("UPDATE policy.academic_session SET state = 'CLOSED' WHERE state = 'CURRENT'").update();
                jdbc.sql("UPDATE policy.academic_session SET state = 'CLOSED' WHERE name = :n").param("n", before).update();
                jdbc.sql("UPDATE policy.academic_session SET state = 'CURRENT', senate_minute = coalesce(senate_minute, 'SEN/IT/777') WHERE name = :n").param("n", session).update();
                return null;
            });
        }

        String programme(int finalLevel) {
            return it.db(() -> {
                String c = jdbc.sql("""
                        SELECT 'C' || lpad(k::text, 5, '0') FROM generate_series(97000, 99999) k
                         WHERE NOT EXISTS (SELECT 1 FROM ref.programme p WHERE p.code = 'C' || lpad(k::text, 5, '0')) ORDER BY random() LIMIT 1
                        """).query(String.class).single();
                jdbc.sql("""
                        INSERT INTO ref.programme (code, name, dept_code, faculty_code, category, min_score, final_level, duration_years)
                        SELECT :c, 'B.Sc. SIWES FEE IT ' || :c, d.code, d.faculty_code, 'UNDER GRADUATE', 0, :fl, :yrs FROM ref.department d WHERE d.code = :d
                        """).param("c", c).param("fl", finalLevel).param("yrs", finalLevel / 100).param("d", dept).update();
                return c;
            });
        }

        /** a LIVE Core course of the run's department; a SIWES one is marked, under a title of its own that reads so */
        void course(String code, int units, int semester, int level, boolean siwes) {
            it.db(() -> jdbc.sql("""
                    INSERT INTO catalogue.course (code, title, units, semester, level, dept_code, kind, state, industrial_training)
                    VALUES (:c, :t, :u, :s, :l, :d, 'Core', 'LIVE', :it) ON CONFLICT (code) DO NOTHING
                    """).param("c", code).param("t", (siwes ? "SIWES FEE IT " : "Invented course ") + code).param("u", units).param("s", semester).param("l", level)
                    .param("d", dept).param("it", siwes).update());
        }

        void offer(String course, String programme, int level, String basis) {
            it.db(() -> jdbc.sql("INSERT INTO catalogue.course_offer (course_code, programme_code, level, basis) VALUES (:c, :p, :l, :b) ON CONFLICT DO NOTHING")
                    .param("c", course).param("p", programme).param("l", level).param("b", basis).update());
        }

        UUID offeringIn(String in, String course, int semester) {
            return it.db(() -> {
                jdbc.sql("INSERT INTO catalogue.offering (id, course_code, session, semester, stream) VALUES (gen_random_uuid(), :c, :s, :m, 'REGULAR') ON CONFLICT DO NOTHING")
                        .param("c", course).param("s", in).param("m", semester).update();
                return jdbc.sql("SELECT id FROM catalogue.offering WHERE course_code = :c AND session = :s AND semester = :m AND stream = 'REGULAR'")
                        .param("c", course).param("s", in).param("m", semester).query(UUID.class).single();
            });
        }

        UUID offering(String course, int semester) {
            return offeringIn(session, course, semester);
        }

        UUID student(String programme, int level) {
            int i = next++;
            String surname = "ZZFEE" + n + "S" + i;
            UUID id = it.student(surname, programme, null, "MOAU/" + px + "/" + yy + "/" + (n * 30 + i), level);
            it.db(() -> jdbc.sql("UPDATE people.student SET entry_session = :e WHERE id = :s").param("e", before).param("s", id).update());
            surnames.put(id, surname);
            return id;
        }

        String matric(UUID student) {
            return jdbc.sql("SELECT matric_no FROM people.student WHERE id = :s").param("s", student).query(String.class).single();
        }

        String token(UUID student) {
            return TestTokens.token(student, List.of("student"));
        }

        /** the Bursary's fee stated by Student Accounts: a draft until the Bursar publishes it, and a draft is no fee in force; the answer */
        Map<String, Object> stateFee() {
            ResponseEntity<Map> stated = it.call(ItSupport.token("studentaccounts"), HttpMethod.PUT, "/api/v1/finance/siwes/fee",
                    Map.of("session", session, "amount", 4000, "note", "The SIWES registration fee"));
            assertThat(status(stated)).as(String.valueOf(stated.getBody())).isEqualTo(200);
            return stated.getBody();
        }

        /** the Bursary's fee: stated by Student Accounts (a draft stated before is stated again, as it was), published by the Bursar */
        void publishFee() {
            stateFee();
            ResponseEntity<Map> published = it.call(ItSupport.token("bursar"), HttpMethod.POST, "/api/v1/finance/siwes/fee/publish", Map.of("session", session));
            assertThat(status(published)).as(String.valueOf(published.getBody())).isEqualTo(200);
            assertThat(published.getBody()).containsEntry("state", "PUBLISHED");
        }

        /** the student's SIWES fee drawn on the SIWES page and confirmed by the Bursary; the reference */
        String pay(UUID student) {
            ResponseEntity<Map> drawn = it.call(token(student), HttpMethod.POST, "/api/v1/me/siwes/reference", Map.of());
            assertThat(status(drawn)).as(String.valueOf(drawn.getBody())).isEqualTo(200);
            String reference = String.valueOf(drawn.getBody().get("reference"));
            assertThat(money(drawn.getBody().get("amount"))).isEqualByComparingTo("4000");
            assertThat(confirm(reference)).isNotEqualTo("already confirmed");
            return reference;
        }

        ResponseEntity<Map> put(UUID student, int semester, UUID... offerings) {
            return it.call(token(student), HttpMethod.PUT, "/api/v1/me/registration", Map.of("session", session, "semester", semester, "offerings", List.of(offerings)));
        }

        Map<String, Object> view(UUID student, int semester) {
            ResponseEntity<Map> r = it.get(token(student), "/api/v1/me/registration?session=" + session + "&semester=" + semester);
            assertThat(status(r)).as(String.valueOf(r.getBody())).isEqualTo(200);
            return r.getBody();
        }

        Map<String, Object> page(UUID student) {
            ResponseEntity<Map> r = it.get(token(student), "/api/v1/me/siwes");
            assertThat(status(r)).as(String.valueOf(r.getBody())).isEqualTo(200);
            return r.getBody();
        }

        /** the school fees of the session stated for the programme and level and paid by the student, and a clearance scheme in force
         *  where none is: the registration the student submits is cleared */
        void cleared(UUID student, String programme, int level) {
            it.db(() -> {
                jdbc.sql("""
                        INSERT INTO finance.fee_schedule (session, item, amount, level, programme_code)
                        SELECT :s, 'School fees', 100000, :l, :p
                         WHERE NOT EXISTS (SELECT 1 FROM finance.fee_schedule f WHERE f.session = :s AND f.item = 'School fees' AND f.level = :l AND f.programme_code = :p)
                        """).param("s", session).param("l", level).param("p", programme).update();
                jdbc.sql("""
                        INSERT INTO policy.version (id, kind, scope, validity, instrument, decided_by)
                        SELECT gen_random_uuid(), 'clearance', 'UNIVERSITY',
                               daterange(current_date, (SELECT min(lower(validity)) FROM policy.version WHERE kind = 'clearance' AND scope = 'UNIVERSITY' AND lower(validity) > current_date)),
                               :i, 'bursar'
                         WHERE policy.in_force('clearance', 'UNIVERSITY', current_date) IS NULL
                        """).param("i", instrument).update();
                jdbc.sql("INSERT INTO policy.clearance_scheme SELECT id, true FROM policy.version WHERE instrument = :i ON CONFLICT DO NOTHING").param("i", instrument).update();
                jdbc.sql("""
                        INSERT INTO policy.clearance_rule SELECT v.id, p.code, CASE p.code WHEN 'HOSTEL' THEN 'NEVER_GATED' ELSE 'INSTALMENT_1' END
                          FROM policy.version v, ref.clearance_purpose p WHERE v.instrument = :i ON CONFLICT DO NOTHING
                        """).param("i", instrument).update();
                String ref = jdbc.sql("SELECT finance.new_purpose_reference(:s, :ses, 100000, 'School fees ' || :ses)").param("s", student).param("ses", session).query(String.class).single();
                return jdbc.sql("SELECT finance.confirm_payment(:r, 'BANK_BRANCH', 'teller for the SIWES fee test')").param("r", ref).query(String.class).single();
            });
        }

        void autoApproval() {
            ResponseEntity<Map> r = it.call(ItSupport.token("academic"), HttpMethod.PUT, "/api/v1/registration/approval/rules", Map.of("session", session, "mode", "AUTO_APPROVAL",
                    "allowStudentReset", true, "cardOnApproval", true, "reason", "Integration test: automatic approval"));
            assertThat(status(r)).as(String.valueOf(r.getBody())).isEqualTo(200);
        }

        /** both semesters of the session open on the calendar, add and drop with them: a course is dropped on the ordinary form */
        void openSemesters() {
            it.db(() -> jdbc.sql("""
                    INSERT INTO policy.semester (id, session, number, state) VALUES (gen_random_uuid(), :s, 1, 'OPEN'), (gen_random_uuid(), :s, 2, 'OPEN')
                    ON CONFLICT (session, number) DO UPDATE SET state = 'OPEN', registration_closes = NULL, late_registration_closes = NULL
                    """).param("s", session).update());
        }

        /** spillover read by the level (above the programme's final level), as the Bursary's setting reads it, put back at the end */
        void spilloverByLevel() {
            basisBefore = jdbc.sql("SELECT spillover_basis FROM finance.fee_setting WHERE id = 1").query(String.class).optional().orElse("LEVEL");
            it.db(() -> jdbc.sql("UPDATE finance.fee_setting SET spillover_basis = 'LEVEL' WHERE id = 1").update());
        }

        /** a course the student registered in the session before and failed, on a published sheet (an F): a carry-over */
        void failed(UUID student, String course, int semester, int level) {
            UUID earlier = offeringIn(before, course, semester);
            it.db(() -> {
                UUID reg = UUID.randomUUID();
                jdbc.sql("INSERT INTO registration.course_registration (id, student_id, session, semester, level, status, submitted_at, approved_at) VALUES (:r, :s, :e, :m, :l, 'APPROVED', now(), now())")
                        .param("r", reg).param("s", student).param("e", before).param("m", semester).param("l", level).update();
                jdbc.sql("INSERT INTO registration.entry (registration_id, offering_id, units, entry_type, status) VALUES (:r, :o, 3, 'CURRENT', 'APPROVED')")
                        .param("r", reg).param("o", earlier).update();
                jdbc.sql("INSERT INTO assessment.score_sheet (id, offering_id) VALUES (gen_random_uuid(), :o)").param("o", earlier).update();
                jdbc.sql("INSERT INTO assessment.score (sheet_id, student_id, ca, exam) SELECT id, :s, 10, 15 FROM assessment.score_sheet WHERE offering_id = :o")
                        .param("s", student).param("o", earlier).update();
                jdbc.sql("SELECT set_config('moaum.maintenance', 'on', true)").query().singleRow();
                return jdbc.sql("UPDATE assessment.score_sheet SET stage = 'PUBLISHED', published_at = now(), senate_minute = 'IT V777' WHERE offering_id = :o")
                        .param("o", earlier).update();
            });
        }

        /** a SIWES course the student held before the rule, as the old portal's loaders place one (the override): a registration of
         *  the semester submitted with the course on it, nothing paid */
        UUID held(UUID student, UUID offering, int semester, int level, int units, boolean override) {
            UUID reg = UUID.randomUUID();
            it.db(() -> {
                if (override) jdbc.sql("SELECT set_config('moaum.siwes_override', 'on', true)").query().listOfRows();
                jdbc.sql("INSERT INTO registration.course_registration (id, student_id, session, semester, level, status) VALUES (:r, :s, :ses, :m, :l, 'DRAFT')")
                        .param("r", reg).param("s", student).param("ses", session).param("m", semester).param("l", level).update();
                jdbc.sql("INSERT INTO registration.entry (registration_id, offering_id, units, status) VALUES (:r, :o, :u, 'REGISTERED')")
                        .param("r", reg).param("o", offering).param("u", units).update();
                return jdbc.sql("UPDATE registration.course_registration SET status = 'SUBMITTED', submitted_at = now() WHERE id = :r").param("r", reg).update();
            });
            return reg;
        }

        @Override
        public void close() {
            it.db(() -> {
                jdbc.sql("DELETE FROM finance.fee_schedule WHERE session = :s").param("s", session).update();
                jdbc.sql("DELETE FROM registration.approval_policy WHERE session = :s").param("s", session).update();
                jdbc.sql("DELETE FROM policy.semester WHERE session = :s").param("s", session).update();
                jdbc.sql("DELETE FROM policy.clearance_rule WHERE version_id IN (SELECT id FROM policy.version WHERE instrument = :i)").param("i", instrument).update();
                jdbc.sql("DELETE FROM policy.clearance_scheme WHERE version_id IN (SELECT id FROM policy.version WHERE instrument = :i)").param("i", instrument).update();
                jdbc.sql("DELETE FROM policy.version WHERE instrument = :i").param("i", instrument).update();
                if (basisBefore != null) jdbc.sql("UPDATE finance.fee_setting SET spillover_basis = :b WHERE id = 1").param("b", basisBefore).update();
                jdbc.sql("UPDATE policy.academic_session SET state = :st WHERE name = :n").param("st", sessionState).param("n", session).update();
                jdbc.sql("UPDATE policy.academic_session SET state = :st WHERE name = :n").param("st", beforeState).param("n", before).update();
                if (previousCurrent != null && !previousCurrent.equals(session)) jdbc.sql("UPDATE policy.academic_session SET state = 'CURRENT' WHERE name = :n").param("n", previousCurrent).update();
                return null;
            });
        }
    }

    // ── I-1: a Communication-like student, SIWES alone in the First Semester of 300 Level, the programme never configured ──

    @Test
    void aStudentOfAnUnconfiguredProgrammeWithSiwesAloneInTheFirstSemesterPaysThenRegistersItAtItsUnits() {
        try (World w = new World("attachment")) {
            String P = w.programme(400);
            String siwes = w.px + " 301", plain = w.px + " 302";
            w.course(siwes, 6, 1, 300, true);
            w.course(plain, 3, 2, 300, false);
            w.offer(siwes, P, 300, "Core");
            w.offer(plain, P, 300, "Core");
            UUID siwesOff = w.offering(siwes, 1), plainOff = w.offering(plain, 2);
            UUID A = w.student(P, 300);
            w.cleared(A, P, 300);
            w.autoApproval();
            String a = w.token(A);

            // no fee published, no registration: the form locks the row in the database's words, the save and the reference refuse
            Map<String, Object> view0 = w.view(A, 1);
            assertThat(view0).containsEntry("siwes", true);
            assertThat((Map<String, Object>) view0.get("limit")).containsEntry("min_units", 6).containsEntry("max_units", 6).containsEntry("basis", "SIWES");
            Map<String, Object> row0 = menuRow(view0, siwes);
            assertThat(row0).containsEntry("siwesLocked", true);
            assertThat(String.valueOf(row0.get("siwesGate"))).startsWith("SIWES_FEE_NOT_SET");
            ResponseEntity<Map> noFee = w.put(A, 1, siwesOff);
            assertThat(status(noFee)).as(String.valueOf(noFee.getBody())).isEqualTo(422);
            assertThat(code(noFee)).isEqualTo("SIWES_FEE_NOT_SET");
            ResponseEntity<Map> noReference = it.call(a, HttpMethod.POST, "/api/v1/me/siwes/reference", Map.of());
            assertThat(status(noReference)).isEqualTo(422);
            assertThat(code(noReference)).isEqualTo("SIWES_FEE_NOT_SET");
            Map<String, Object> page0 = w.page(A);
            assertThat(page0).containsEntry("mode", "COURSE").containsEntry("canPay", false).containsEntry("registrationOpen", false);

            // the fee stated and not published: a draft is no fee in force (as V777 itself states one for each session still to come), so
            // every refusal reads as with no fee at all, and the page shows the draft but does not ask for it
            assertThat(w.stateFee()).containsEntry("state", "DRAFT");
            Map<String, Object> rowDraft = menuRow(w.view(A, 1), siwes);
            assertThat(rowDraft).containsEntry("siwesLocked", true);
            assertThat(String.valueOf(rowDraft.get("siwesGate"))).startsWith("SIWES_FEE_NOT_SET");
            ResponseEntity<Map> draftSave = w.put(A, 1, siwesOff);
            assertThat(status(draftSave)).as(String.valueOf(draftSave.getBody())).isEqualTo(422);
            assertThat(code(draftSave)).isEqualTo("SIWES_FEE_NOT_SET");
            ResponseEntity<Map> draftReference = it.call(a, HttpMethod.POST, "/api/v1/me/siwes/reference", Map.of());
            assertThat(status(draftReference)).as(String.valueOf(draftReference.getBody())).isEqualTo(422);
            assertThat(code(draftReference)).isEqualTo("SIWES_FEE_NOT_SET");
            Map<String, Object> pageDraft = w.page(A);
            assertThat(pageDraft).containsEntry("mode", "COURSE").containsEntry("canPay", false).containsEntry("registrationOpen", false);
            assertThat((Map<String, Object>) pageDraft.get("fee")).containsEntry("state", "DRAFT");

            // a plain course is never charged, whatever the fee
            assertThat(status(w.put(A, 2, plainOff))).isEqualTo(200);
            assertThat(menuRow(w.view(A, 2), plain)).doesNotContainKeys("siwesLocked", "siwesGate");

            // the fee published, the course waits for it, the page asks for it
            w.publishFee();
            Map<String, Object> row1 = menuRow(w.view(A, 1), siwes);
            assertThat(row1).containsEntry("siwesLocked", true);
            assertThat(String.valueOf(row1.get("siwesGate"))).startsWith("SIWES_UNPAID").contains(w.session).contains(siwes);
            ResponseEntity<Map> unpaid = w.put(A, 1, siwesOff);
            assertThat(status(unpaid)).as(String.valueOf(unpaid.getBody())).isEqualTo(422);
            assertThat(code(unpaid)).isEqualTo("SIWES_UNPAID");
            assertThat(standing(A, w.session)).as("nothing stays of the refused save").containsExactly(plain + ":REGISTERED");
            Map<String, Object> page1 = w.page(A);
            assertThat(page1).containsEntry("mode", "COURSE").containsEntry("canPay", true).containsEntry("registrationOpen", true).containsEntry("canRegister", false);
            assertThat((Map<String, Object>) page1.get("fee")).containsEntry("state", "PUBLISHED");

            // paid on the SIWES page; paying registers nothing
            String reference = w.pay(A);
            assertThat(standing(A, w.session)).containsExactly(plain + ":REGISTERED");
            Map<String, Object> row2 = menuRow(w.view(A, 1), siwes);
            assertThat(row2).containsEntry("siwesLocked", false);
            assertThat(row2.get("siwesGate")).isNull();
            Map<String, Object> page2 = w.page(A);
            assertThat(page2).containsEntry("canPay", false);
            assertThat((Map<String, Object>) page2.get("paid")).containsEntry("reference", reference).containsEntry("source", "PORTAL");

            // registered on Course Registration at exactly its units, and approved on submission: the unit rule of V503 holds under the fee
            ResponseEntity<Map> saved = w.put(A, 1, siwesOff);
            assertThat(status(saved)).as(String.valueOf(saved.getBody())).isEqualTo(200);
            assertThat(linked(A, w.session)).containsExactly(siwes + "<" + reference);
            assertThat(jdbc.sql("""
                    SELECT e.units || ':' || e.status FROM registration.entry e JOIN registration.course_registration r ON r.id = e.registration_id
                      JOIN catalogue.offering o ON o.id = e.offering_id WHERE r.student_id = :s AND r.semester = 1 AND o.course_code = :c
                    """).param("s", A).param("c", siwes).query(String.class).single()).isEqualTo("6:REGISTERED");
            ResponseEntity<Map> submitted = it.call(a, HttpMethod.POST, "/api/v1/me/registration/submit", Map.of("session", w.session, "semester", 1));
            assertThat(status(submitted)).as(String.valueOf(submitted.getBody())).isEqualTo(200);
            assertThat(submitted.getBody().get("result")).isEqualTo("approved");
            assertThat(standing(A, w.session)).contains(siwes + ":APPROVED");
            // the fee is never paid twice, the page now reads what is held
            ResponseEntity<Map> twice = it.call(a, HttpMethod.POST, "/api/v1/me/siwes/reference", Map.of());
            assertThat(status(twice)).isEqualTo(422);
            assertThat(code(twice)).isEqualTo("SIWES_PAID");
            Map<String, Object> page3 = w.page(A);
            assertThat(((List<Map<String, Object>>) page3.get("courses"))).singleElement().satisfies(c -> assertThat(c).containsEntry("code", siwes).containsEntry("held", true)
                    .containsEntry("why", "HELD"));
        }
    }

    // ── I-2 and I-5: a Nursing-like student, the SIWES course beside required courses in the Second Semester ──

    @Test
    void aStudentWhoseSiwesCourseStandsBesideRequiredCoursesRegistersThemFreelyAndTheSiwesCourseWaitsForTheFee() {
        try (World w = new World("beside")) {
            w.publishFee();
            String P = w.programme(400);
            String siwes = w.px + " 311", r1 = w.px + " 312", r2 = w.px + " 313", r3 = w.px + " 314";
            w.course(siwes, 3, 2, 300, true);
            for (String c : List.of(r1, r2, r3)) w.course(c, 3, 2, 300, false);
            for (String c : List.of(siwes, r1, r2, r3)) w.offer(c, P, 300, "Core");
            UUID siwesOff = w.offering(siwes, 2), o1 = w.offering(r1, 2), o2 = w.offering(r2, 2), o3 = w.offering(r3, 2);
            UUID B = w.student(P, 300);

            // the page reads COURSE: the programme was never added to the SIWES period, the student pays here and registers elsewhere
            Map<String, Object> page = w.page(B);
            assertThat(page).containsEntry("mode", "COURSE").containsEntry("bound", false).containsEntry("applies", false).containsEntry("eligible", true)
                    .containsEntry("canPay", true).containsEntry("canRegister", false).containsEntry("registerOn", "COURSE_REGISTRATION")
                    .containsEntry("registrationOpen", true).containsEntry("session", w.session);
            assertThat(List.of("level", "semester", "course", "semesterFees", "paid")).allSatisfy(k -> assertThat(page.get(k)).as(k).isNull());
            assertThat((List<?>) page.get("reasons")).isEmpty();
            assertThat((List<?>) page.get("otherCourses")).isEmpty();
            assertThat(((List<Map<String, Object>>) page.get("courses"))).singleElement().satisfies(c -> assertThat(c).containsEntry("code", siwes).containsEntry("title", "SIWES FEE IT " + siwes)
                    .containsEntry("units", 3).containsEntry("level", 300).containsEntry("semester", 2).containsEntry("why", "STRUCTURE").containsEntry("held", false)
                    .containsEntry("passed", false));
            assertThat(it.get(w.token(B), "/api/v1/me").getBody()).containsEntry("siwesArea", true);

            // the other courses register freely; the SIWES course alone is locked on the form
            Map<String, Object> view = w.view(B, 2);
            assertThat(menuRow(view, siwes)).containsEntry("siwesLocked", true);
            assertThat(String.valueOf(menuRow(view, siwes).get("siwesGate"))).startsWith("SIWES_UNPAID");
            for (String c : List.of(r1, r2, r3)) assertThat(menuRow(view, c)).doesNotContainKeys("siwesLocked", "siwesGate");
            assertThat(status(w.put(B, 2, o1, o2, o3))).isEqualTo(200);
            ResponseEntity<Map> refused = w.put(B, 2, o1, o2, o3, siwesOff);
            assertThat(status(refused)).as(String.valueOf(refused.getBody())).isEqualTo(422);
            assertThat(code(refused)).isEqualTo("SIWES_UNPAID");
            assertThat(standing(B, w.session)).as("the saved courses stand, the SIWES course is not placed")
                    .containsExactlyInAnyOrder(r1 + ":REGISTERED", r2 + ":REGISTERED", r3 + ":REGISTERED");

            // the Add Other Course search marks it held as it marks a GST course
            ResponseEntity<Map> found = it.get(w.token(B), u -> u.path("/api/v1/me/registration/courses").queryParam("session", w.session).queryParam("semester", 2)
                    .queryParam("q", siwes).build());
            assertThat(status(found)).as(String.valueOf(found.getBody())).isEqualTo(200);
            Map<String, Object> foundRow = ((List<Map<String, Object>>) found.getBody().get("results")).stream().filter(r -> siwes.equals(r.get("course_code"))).findFirst()
                    .orElseThrow(() -> new AssertionError("the search found no " + siwes + ": " + found.getBody()));
            assertThat(String.valueOf(foundRow.get("siwesHeld"))).as(String.valueOf(foundRow)).startsWith("SIWES_UNPAID");
            assertThat(foundRow.get("refusal")).isNull();
            // another door the form never offers: an office placing the course on a student's registration is held to the fee as the
            // student is (B2 has nothing paid, nothing registered)
            UUID B2 = w.student(P, 300);
            ResponseEntity<Map> byOffice = it.call(ItSupport.token("academic"), HttpMethod.POST, "/api/v1/registration/course-registrations", Map.of("studentId", B2, "session", w.session,
                    "semester", 2, "level", 300, "entries", List.of(Map.of("offeringId", siwesOff, "units", 3))));
            assertThat(status(byOffice)).as(String.valueOf(byOffice.getBody())).isEqualTo(422);
            assertThat(code(byOffice)).isEqualTo("SIWES_UNPAID");
            assertThat(standing(B2, w.session)).isEmpty();

            // paid, it goes on the same registration beside the others, and the fee says what it stands on
            String reference = w.pay(B);
            assertThat(status(w.put(B, 2, o1, o2, o3, siwesOff))).isEqualTo(200);
            assertThat(standing(B, w.session)).containsExactlyInAnyOrder(r1 + ":REGISTERED", r2 + ":REGISTERED", r3 + ":REGISTERED", siwes + ":REGISTERED");
            assertThat(linked(B, w.session)).as("only the SIWES course stands on the payment").containsExactly(siwes + "<" + reference);
            Map<String, Object> after = w.page(B);
            assertThat(after).containsEntry("mode", "COURSE").containsEntry("canPay", false).containsEntry("canRegister", false);
            assertThat((Map<String, Object>) after.get("paid")).containsEntry("reference", reference).containsEntry("source", "PORTAL");
            assertThat(((List<Map<String, Object>>) after.get("courses"))).singleElement().satisfies(c -> assertThat(c).containsEntry("held", true).containsEntry("why", "HELD"));
        }
    }

    // ── I-3: a spillover student's picker marks the unpaid SIWES carry-over held, and adding it is refused ──
    // (a spillover registration places no carry-over of its own — V682's student_draft and student_choose — so what the form's save
    // does with an unpaid carry-over is not shown here: it is the next test's, a student who is not in spillover)

    @Test
    void aSpilloverStudentsPickerMarksTheSiwesCarryOverHeldAndARefusedAddLeavesTheRegistrationUntouched() {
        try (World w = new World("carry")) {
            w.publishFee();
            w.spilloverByLevel();
            // a programme whose SIWES course is at its final level (400); a student past it (500, spillover by level) who failed it
            String P = w.programme(400);
            String siwes = w.px + " 451";
            w.course(siwes, 3, 1, 400, true);
            w.offer(siwes, P, 400, "Core");
            w.offering(siwes, 1);
            UUID C = w.student(P, 500);
            w.failed(C, siwes, 1, 400);
            String c = w.token(C);

            ResponseEntity<Map> listed = it.get(c, u -> u.path("/api/v1/me/registration/carry-overs").queryParam("session", w.session).queryParam("semester", 1).build());
            assertThat(status(listed)).as(String.valueOf(listed.getBody())).isEqualTo(200);
            Map<String, Object> row = ((List<Map<String, Object>>) listed.getBody().get("rows")).stream().filter(r -> siwes.equals(r.get("course_code"))).findFirst()
                    .orElseThrow(() -> new AssertionError("no carry-over row " + siwes + " in " + listed.getBody().get("rows")));
            assertThat(row).containsEntry("status", "OUTSTANDING").containsEntry("selectable", true).containsEntry("siwes_held", true);
            assertThat(String.valueOf(row.get("siwes_gate"))).startsWith("SIWES_UNPAID");

            // ticked all the same, it is refused with the database's words and the registration is left as it was
            Object courseId = row.get("course_id");
            ResponseEntity<Map> added = it.call(c, HttpMethod.POST, "/api/v1/me/registration/carry-overs", Map.of("session", w.session, "semester", 1, "courses", List.of(String.valueOf(courseId))));
            assertThat(status(added)).as(String.valueOf(added.getBody())).isEqualTo(200);
            assertThat(added.getBody()).containsEntry("addedCount", 0).containsEntry("refusedCount", 1);
            assertThat(((List<Map<String, Object>>) added.getBody().get("results"))).singleElement().satisfies(r -> {
                assertThat(r).containsEntry("added", false).containsEntry("code", "SIWES_UNPAID");
                assertThat(String.valueOf(r.get("message"))).contains("SIWES registration fee");
            });
            assertThat(status(w.put(C, 1))).as("a save with nothing chosen (a spillover save places no carry-over by itself, V682)").isEqualTo(200);
            assertThat(standing(C, w.session)).isEmpty();
            Map<String, Object> page = w.page(C);
            assertThat(page).containsEntry("mode", "COURSE").containsEntry("canPay", true);
            assertThat(((List<Map<String, Object>>) page.get("courses"))).singleElement().satisfies(k -> assertThat(k).containsEntry("code", siwes).containsEntry("why", "CARRYOVER")
                    .containsEntry("level", 400).containsEntry("held", false));

            // paid, the picker no longer holds it and adding it works
            String reference = w.pay(C);
            Map<String, Object> rowPaid = ((List<Map<String, Object>>) it.get(c, u -> u.path("/api/v1/me/registration/carry-overs").queryParam("session", w.session)
                    .queryParam("semester", 1).build()).getBody().get("rows")).stream().filter(r -> siwes.equals(r.get("course_code"))).findFirst().orElseThrow();
            assertThat(rowPaid).containsEntry("siwes_held", false);
            assertThat(rowPaid.get("siwes_gate")).isNull();
            ResponseEntity<Map> addedPaid = it.call(c, HttpMethod.POST, "/api/v1/me/registration/carry-overs", Map.of("session", w.session, "semester", 1, "courses", List.of(String.valueOf(courseId))));
            assertThat(status(addedPaid)).as(String.valueOf(addedPaid.getBody())).isEqualTo(200);
            assertThat(addedPaid.getBody()).containsEntry("addedCount", 1);
            assertThat(standing(C, w.session)).containsExactly(siwes + ":REGISTERED");
            assertThat(linked(C, w.session)).containsExactly(siwes + "<" + reference);
        }
    }

    @Test
    void aSaveOfTheFormNeverPlacesAnUnpaidSiwesCarryOverAndPlacesItOnceTheFeeIsPaid() {
        try (World w = new World("draft")) {
            w.publishFee();
            // a student of 300 Level who failed a SIWES course of 200 Level (the programme carries none at 300): it is owed, and so is the fee
            String P = w.programme(400);
            String siwes = w.px + " 251", plain = w.px + " 351";
            w.course(siwes, 3, 1, 200, true);
            w.course(plain, 3, 1, 300, false);
            w.offer(siwes, P, 200, "Core");
            w.offer(plain, P, 300, "Core");
            UUID siwesOff = w.offering(siwes, 1), plainOff = w.offering(plain, 1);
            UUID D = w.student(P, 300);
            w.failed(D, siwes, 1, 200);

            Map<String, Object> view = w.view(D, 1);
            Map<String, Object> carried = menuRow(view, siwes);
            assertThat(carried).containsEntry("carryover", true).containsEntry("siwesLocked", true);
            assertThat(String.valueOf(carried.get("siwesGate"))).startsWith("SIWES_UNPAID");
            Map<String, Object> page = w.page(D);
            assertThat(page).containsEntry("mode", "COURSE").containsEntry("canPay", true);
            assertThat(((List<Map<String, Object>>) page.get("courses"))).singleElement().satisfies(k -> assertThat(k).containsEntry("code", siwes).containsEntry("why", "CARRYOVER"));
            // the save is made, the carry-over due is not placed on it
            assertThat(status(w.put(D, 1, plainOff))).isEqualTo(200);
            assertThat(standing(D, w.session)).containsExactly(plain + ":REGISTERED");
            assertThat(status(w.put(D, 1, plainOff))).as("saved again").isEqualTo(200);
            assertThat(standing(D, w.session)).containsExactly(plain + ":REGISTERED");
            // the fee paid, the next save places it as a carry-over
            String reference = w.pay(D);
            assertThat(status(w.put(D, 1, plainOff))).isEqualTo(200);
            assertThat(standing(D, w.session)).containsExactlyInAnyOrder(plain + ":REGISTERED", siwes + ":REGISTERED");
            assertThat(linked(D, w.session)).containsExactly(siwes + "<" + reference);
            assertThat(jdbc.sql("""
                    SELECT e.entry_type FROM registration.entry e JOIN registration.course_registration r ON r.id = e.registration_id WHERE r.student_id = :s AND e.offering_id = :o
                    """).param("s", D).param("o", siwesOff).query(String.class).single()).isEqualTo("CARRYOVER");
        }
    }

    // ── I-4: SIWES in both semesters of a level, one payment ──

    @Test
    void siwesInBothSemestersOfALevelIsPaidOnce() {
        try (World w = new World("both")) {
            w.publishFee();
            String P = w.programme(400);
            String s1 = w.px + " 321", s2 = w.px + " 322", p1 = w.px + " 323", p2 = w.px + " 324";
            w.course(s1, 3, 1, 300, true);
            w.course(s2, 3, 2, 300, true);
            w.course(p1, 3, 1, 300, false);
            w.course(p2, 3, 2, 300, false);
            for (String c : List.of(s1, s2, p1, p2)) w.offer(c, P, 300, "Core");
            UUID o1 = w.offering(s1, 1), o2 = w.offering(s2, 2);
            w.offering(p1, 1);
            w.offering(p2, 2);
            UUID E = w.student(P, 300);

            assertThat(code(w.put(E, 1, o1))).isEqualTo("SIWES_UNPAID");
            assertThat(code(w.put(E, 2, o2))).isEqualTo("SIWES_UNPAID");
            Map<String, Object> page = w.page(E);
            assertThat(((List<Map<String, Object>>) page.get("courses"))).extracting(k -> String.valueOf(k.get("code"))).containsExactly(s1, s2);
            String reference = w.pay(E);
            assertThat(status(w.put(E, 1, o1))).isEqualTo(200);
            assertThat(status(w.put(E, 2, o2))).isEqualTo(200);
            assertThat(linked(E, w.session)).as("both courses stand on the one payment").containsExactly(s1 + "<" + reference, s2 + "<" + reference);
            ResponseEntity<Map> again = it.call(w.token(E), HttpMethod.POST, "/api/v1/me/siwes/reference", Map.of());
            assertThat(status(again)).isEqualTo(422);
            assertThat(code(again)).isEqualTo("SIWES_PAID");
            assertThat(jdbc.sql("SELECT count(*) FROM finance.payment_reference WHERE student_id = :s AND purpose LIKE 'SIWES registration fee%'").param("s", E).query(Integer.class).single()).isEqualTo(1);
            assertThat(((List<Map<String, Object>>) w.page(E).get("courses"))).allSatisfy(k -> assertThat(k).containsEntry("held", true));
        }
    }

    // ── I-6: a student the programme carries no SIWES course for is not asked and cannot pay ──

    @Test
    void aStudentWhoseProgrammeCarriesNoSiwesCourseAtTheirLevelIsNotAskedAndCannotPay() {
        try (World w = new World("noreach")) {
            w.publishFee();
            String P = w.programme(400);
            String siwes = w.px + " 301", plain = w.px + " 201";
            w.course(siwes, 6, 1, 300, true);
            w.course(plain, 3, 1, 200, false);
            w.offer(siwes, P, 300, "Core");
            w.offer(plain, P, 200, "Core");
            UUID siwesOff = w.offering(siwes, 1);
            w.offering(plain, 1);
            UUID F = w.student(P, 200);
            String f = w.token(F);

            Map<String, Object> page = w.page(F);
            assertThat(page).containsEntry("eligible", false).containsEntry("canPay", false).containsEntry("canRegister", false);
            assertThat(page.get("mode")).isNull();
            assertThat((List<String>) page.get("reasons")).contains("NO_SIWES_COURSE");
            assertThat((List<?>) page.get("courses")).isEmpty();
            assertThat(it.get(f, "/api/v1/me").getBody()).containsEntry("siwesArea", false);
            ResponseEntity<Map> reference = it.call(f, HttpMethod.POST, "/api/v1/me/siwes/reference", Map.of());
            assertThat(status(reference)).as(String.valueOf(reference.getBody())).isEqualTo(422);
            assertThat(code(reference)).isEqualTo("SIWES_NOT_ELIGIBLE");
            assertThat(String.valueOf(reference.getBody().get("detail"))).contains("the programme carries no SIWES course at the student's level");
            assertThat(jdbc.sql("SELECT count(*) FROM finance.payment_reference WHERE student_id = :s AND purpose LIKE 'SIWES%'").param("s", F).query(Integer.class).single()).isZero();
            // a SIWES course an office places on them is refused in words that say it is not part of the programme: never "pay" with nowhere to pay
            ResponseEntity<Map> placed = it.call(ItSupport.token("academic"), HttpMethod.POST, "/api/v1/registration/course-registrations", Map.of("studentId", F, "session", w.session,
                    "semester", 1, "level", 200, "entries", List.of(Map.of("offeringId", siwesOff, "units", 6))));
            assertThat(status(placed)).as(String.valueOf(placed.getBody())).isEqualTo(422);
            assertThat(code(placed)).isEqualTo("SIWES_NOT_IN_REACH");
            assertThat(standing(F, w.session)).isEmpty();
        }
    }

    // ── I-7: the refund desk and the payment a course registration stands on ──

    @Test
    void theRefundDeskHoldsThePaymentACourseStandsOnAndReleasesItOnceTheStudentDropsTheCourse() {
        try (World w = new World("refund")) {
            w.publishFee();
            w.openSemesters();
            String P = w.programme(400);
            String siwes = w.px + " 311", r1 = w.px + " 312";
            w.course(siwes, 3, 2, 300, true);
            w.course(r1, 3, 2, 300, false);
            w.offer(siwes, P, 300, "Core");
            w.offer(r1, P, 300, "Core");
            UUID siwesOff = w.offering(siwes, 2), o1 = w.offering(r1, 2);
            UUID B = w.student(P, 300);
            String maker = TestTokens.token(UUID.randomUUID(), List.of("bursar")), checker = TestTokens.token(UUID.randomUUID(), List.of("bursar"));
            String payer = w.surnames.get(B) + ", Invented";

            String reference = w.pay(B);
            assertThat(status(w.put(B, 2, o1, siwesOff))).isEqualTo(200);
            assertThat(linked(B, w.session)).containsExactly(siwes + "<" + reference);
            // the course stands on the payment: the fee is not given back under it
            Map<String, Object> raise = Map.of("student", B, "payer", payer, "reason", "SiwesFeeEveryCourseIT: the SIWES fee given back", "amount", 4000, "source", reference);
            ResponseEntity<Map> held = it.call(maker, HttpMethod.POST, "/api/v1/finance/refunds", raise);
            assertThat(status(held)).as(String.valueOf(held.getBody())).isEqualTo(422);
            assertThat(code(held)).isEqualTo("REFUND_SIWES_REGISTERED");
            // the student drops the course on the ordinary form (it is no SIWES registration the form keeps), and the payment is free
            ResponseEntity<Map> dropped = it.call(w.token(B), HttpMethod.POST, "/api/v1/me/registration/drop", Map.of("session", w.session, "semester", 2, "offering", siwesOff));
            assertThat(status(dropped)).as(String.valueOf(dropped.getBody())).isEqualTo(200);
            assertThat(standing(B, w.session)).containsExactly(r1 + ":REGISTERED");
            ResponseEntity<Map> raised = it.call(maker, HttpMethod.POST, "/api/v1/finance/refunds", raise);
            assertThat(status(raised)).as(String.valueOf(raised.getBody())).isEqualTo(200);
            UUID refund = jdbc.sql("SELECT id FROM finance.refund WHERE reference = :r").param("r", String.valueOf(raised.getBody().get("reference"))).query(UUID.class).single();
            ResponseEntity<Map> approved = it.call(checker, HttpMethod.POST, "/api/v1/finance/refunds/" + refund + "/approve", Map.of());
            assertThat(status(approved)).as(String.valueOf(approved.getBody())).isEqualTo(200);
            // given back, the fee is owed again: the course is refused as before
            assertThat(w.page(B)).containsEntry("canPay", true);
            ResponseEntity<Map> again = w.put(B, 2, o1, siwesOff);
            assertThat(status(again)).as(String.valueOf(again.getBody())).isEqualTo(422);
            assertThat(code(again)).isEqualTo("SIWES_UNPAID");
        }
    }

    /** two calls sent at one moment (the student's save and an officer's approval): each on its own thread, released together; the answers in order */
    private static List<ResponseEntity<Map>> atOnce(java.util.function.Supplier<ResponseEntity<Map>> first, java.util.function.Supplier<ResponseEntity<Map>> second) {
        java.util.concurrent.CyclicBarrier together = new java.util.concurrent.CyclicBarrier(2);
        java.util.concurrent.ExecutorService pool = java.util.concurrent.Executors.newFixedThreadPool(2);
        try {
            java.util.concurrent.Future<ResponseEntity<Map>> a = pool.submit(() -> {
                together.await(30, java.util.concurrent.TimeUnit.SECONDS);
                return first.get();
            });
            java.util.concurrent.Future<ResponseEntity<Map>> b = pool.submit(() -> {
                together.await(30, java.util.concurrent.TimeUnit.SECONDS);
                return second.get();
            });
            return List.of(a.get(120, java.util.concurrent.TimeUnit.SECONDS), b.get(120, java.util.concurrent.TimeUnit.SECONDS));
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            throw new IllegalStateException(e);
        } catch (java.util.concurrent.ExecutionException | java.util.concurrent.TimeoutException e) {
            throw new IllegalStateException("two calls at one moment did not both answer", e);
        } finally {
            pool.shutdownNow();
        }
    }

    // ── the instant a course is entered and its payment's refund is approved: one wins, never both ──

    @Test
    void aSiwesCourseEnteredAtTheInstantItsPaymentsRefundIsApprovedIsNeverBothRegisteredAndGivenBack() {
        try (World w = new World("race")) {
            w.publishFee();
            String P = w.programme(400);
            String siwes = w.px + " 311", r1 = w.px + " 312";
            w.course(siwes, 3, 2, 300, true);
            w.course(r1, 3, 2, 300, false);
            w.offer(siwes, P, 300, "Core");
            w.offer(r1, P, 300, "Core");
            UUID siwesOff = w.offering(siwes, 2), o1 = w.offering(r1, 2);
            UUID B = w.student(P, 300);
            String maker = TestTokens.token(UUID.randomUUID(), List.of("bursar")), checker = TestTokens.token(UUID.randomUUID(), List.of("bursar"));
            String reference = w.pay(B);
            assertThat(status(w.put(B, 2, o1))).isEqualTo(200);
            // the refund is raised while nothing stands on the payment: the one student's save and the other officer's approval then meet
            ResponseEntity<Map> raised = it.call(maker, HttpMethod.POST, "/api/v1/finance/refunds", Map.of("student", B, "payer", w.surnames.get(B) + ", Invented",
                    "reason", "SiwesFeeEveryCourseIT: the SIWES fee given back", "amount", 4000, "source", reference));
            assertThat(status(raised)).as(String.valueOf(raised.getBody())).isEqualTo(200);
            UUID refund = jdbc.sql("SELECT id FROM finance.refund WHERE reference = :r").param("r", String.valueOf(raised.getBody().get("reference"))).query(UUID.class).single();

            List<ResponseEntity<Map>> answers = atOnce(() -> w.put(B, 2, o1, siwesOff),
                    () -> it.call(checker, HttpMethod.POST, "/api/v1/finance/refunds/" + refund + "/approve", Map.of()));
            ResponseEntity<Map> saved = answers.get(0), decided = answers.get(1);
            boolean stands = standing(B, w.session).contains(siwes + ":REGISTERED");
            boolean givenBack = status(decided) == 200;
            assertThat(stands && givenBack).as("registered and given back: " + saved.getBody() + " / " + decided.getBody()).isFalse();
            if (stands) {
                assertThat(status(saved)).as(String.valueOf(saved.getBody())).isEqualTo(200);
                assertThat(status(decided)).as(String.valueOf(decided.getBody())).isEqualTo(422);
                assertThat(code(decided)).isEqualTo("REFUND_SIWES_REGISTERED");
                assertThat(linked(B, w.session)).containsExactly(siwes + "<" + reference);
            } else {
                assertThat(givenBack).as("neither registered nor given back: " + saved.getBody() + " / " + decided.getBody()).isTrue();
                assertThat(status(saved)).as(String.valueOf(saved.getBody())).isEqualTo(422);
                assertThat(code(saved)).isEqualTo("SIWES_UNPAID");
                assertThat(linked(B, w.session)).isEmpty();
            }
        }
    }

    // ── I-8: the old portal's payers register freely ──

    @Test
    void aStudentWhoPaidTheOldPortalForEitherSemesterRegistersTheSiwesCourseFreely() {
        try (World w = new World("legacy")) {
            w.publishFee();
            String P = w.programme(400);
            String siwes = w.px + " 311", r1 = w.px + " 312";
            w.course(siwes, 3, 2, 300, true);
            w.course(r1, 3, 2, 300, false);
            w.offer(siwes, P, 300, "Core");
            w.offer(r1, P, 300, "Core");
            UUID siwesOff = w.offering(siwes, 2), o1 = w.offering(r1, 2);
            UUID semester1 = w.student(P, 300), semester2 = w.student(P, 300), nobody = w.student(P, 300);
            oldPortalSiwes(semester1, w.session, 1, w.n + "A");
            oldPortalSiwes(semester2, w.session, 2, w.n + "B");

            for (UUID s : List.of(semester1, semester2)) {
                Map<String, Object> page = w.page(s);
                assertThat(page).containsEntry("canPay", false);
                assertThat((Map<String, Object>) page.get("paid")).containsEntry("source", "OLD_PORTAL");
                assertThat(menuRow(w.view(s, 2), siwes)).containsEntry("siwesLocked", false);
                assertThat(status(w.put(s, 2, o1, siwesOff))).as("registered on the old portal's payment").isEqualTo(200);
                assertThat(standing(s, w.session)).containsExactlyInAnyOrder(r1 + ":REGISTERED", siwes + ":REGISTERED");
                assertThat(jdbc.sql("SELECT (x.legacy_payment_id IS NOT NULL AND x.payment_reference_id IS NULL) FROM registration.siwes_course_entry x WHERE x.student_id = :s")
                        .param("s", s).query(Boolean.class).single()).isTrue();
                ResponseEntity<Map> again = it.call(w.token(s), HttpMethod.POST, "/api/v1/me/siwes/reference", Map.of());
                assertThat(code(again)).isEqualTo("SIWES_PAID");
            }
            // and the one who paid nothing is still asked
            assertThat(code(w.put(nobody, 2, o1, siwesOff))).isEqualTo("SIWES_UNPAID");
        }
    }

    // ── D2 and the Bursary's list: a SIWES course held from before the rule, unpaid ──

    @Test
    void aStudentHoldingAnUnpaidSiwesCourseIsAskedAbleToPayNeverRefusedAtApprovalAndListedForTheBursary() {
        try (World w = new World("held")) {
            w.publishFee();
            String P = w.programme(400);
            String siwes = w.px + " 301";
            w.course(siwes, 6, 1, 300, true);
            w.offer(siwes, P, 300, "Core");
            UUID off = w.offering(siwes, 1);
            UUID J = w.student(P, 300), K = w.student(P, 300);
            // K paid the old portal, so the course is accepted as any is (and stands on that payment); J holds it from before the rule, as
            // the old portal's loaders placed it (the override), nothing paid
            oldPortalSiwes(K, w.session, 1, w.n + "K");
            UUID regK = w.held(K, off, 1, 300, 6, false);
            UUID regJ = w.held(J, off, 1, 300, 6, true);
            assertThat(standing(J, w.session)).containsExactly(siwes + ":REGISTERED");
            assertThat(linked(K, w.session)).hasSize(1);
            assertThat(linked(J, w.session)).as("a course held from before stands on no payment").isEmpty();

            // asked, and able to pay: the page reads the course as held
            Map<String, Object> page = w.page(J);
            assertThat(page).containsEntry("mode", "COURSE").containsEntry("canPay", true).containsEntry("canRegister", false);
            assertThat(((List<Map<String, Object>>) page.get("courses"))).singleElement().satisfies(c -> assertThat(c).containsEntry("code", siwes).containsEntry("why", "HELD")
                    .containsEntry("held", true));
            assertThat(w.page(K)).containsEntry("canPay", false);

            // the Head approves the registration: the entry stands, it is not a registration of the course again
            String hod = it.officer("hod", "department", w.dept);
            ResponseEntity<Map> approved = it.call(hod, HttpMethod.POST, "/api/v1/registration/course-registrations/" + regJ + "/approve", Map.of());
            assertThat(status(approved)).as(String.valueOf(approved.getBody())).isEqualTo(200);
            assertThat(standing(J, w.session)).containsExactly(siwes + ":APPROVED");
            assertThat(status(it.call(hod, HttpMethod.POST, "/api/v1/registration/course-registrations/" + regK + "/approve", Map.of()))).isEqualTo(200);

            // the Bursary's list: the students who hold a SIWES course with no SIWES payment, J and not K
            String path = "/api/v1/siwes/admin/unpaid-entries?session=" + w.session + "&programme=" + P + "&size=500";
            for (String office : List.of("bursar", "studentaccounts", "registrar", "academic")) {
                ResponseEntity<Map> listed = it.get(ItSupport.token(office), path);
                assertThat(status(listed)).as(office + ": " + listed.getBody()).isEqualTo(200);
                List<Map<String, Object>> rows = (List<Map<String, Object>>) listed.getBody().get("rows");
                assertThat(rows).as(office).singleElement().satisfies(r -> assertThat(r).containsEntry("matricNo", w.matric(J)).containsEntry("courseCode", siwes)
                        .containsEntry("programmeCode", P).containsEntry("payable", true).containsEntry("registrationStatus", "APPROVED").containsEntry("level", 300)
                        .containsEntry("semester", 1));
                assertThat(listed.getBody()).containsEntry("session", w.session).containsEntry("total", 1).containsEntry("students", 1);
                assertThat(money(listed.getBody().get("fee"))).isEqualByComparingTo("4000");
            }
            // the list is a tab of the SIWES desk, read by the desk's readers: the auditors, who have no way into the desk, do not read it
            for (String office : List.of("audit", "deputyaudit", "lecturer")) {
                assertThat(status(it.get(ItSupport.token(office), path))).as(office).isEqualTo(403);
            }
            assertThat(status(it.get(w.token(J), path))).isEqualTo(403);

            // J pays: the list no longer holds J
            String reference = w.pay(J);
            ResponseEntity<Map> after = it.get(ItSupport.token("bursar"), path);
            assertThat(status(after)).isEqualTo(200);
            assertThat(after.getBody()).containsEntry("total", 0);
            assertThat((Map<String, Object>) w.page(J).get("paid")).containsEntry("reference", reference);
            // the course J held stands on the payment J has just paid: the payment trigger linked it (registration.siwes_link_held), so the refund desk
            // does not give the fee back under a course that stands (K's was linked as the course was accepted)
            assertThat(linked(J, w.session)).containsExactly(siwes + "<" + reference);
            String maker = TestTokens.token(UUID.randomUUID(), List.of("bursar"));
            ResponseEntity<Map> given = it.call(maker, HttpMethod.POST, "/api/v1/finance/refunds",
                    Map.of("student", J, "payer", w.surnames.get(J) + ", Invented", "reason", "SiwesFeeEveryCourseIT: the SIWES fee given back", "amount", 4000, "source", reference));
            assertThat(status(given)).as(String.valueOf(given.getBody())).isEqualTo(422);
            assertThat(code(given)).isEqualTo("REFUND_SIWES_REGISTERED");
        }
    }

    // ── the Bursary's list read by the unit offices: held to the unit, filtered, paged, counted by student ──

    /** the list of the SIWES courses held with no SIWES payment as an office reads it, the query values encoded; the filters are name and value pairs */
    private ResponseEntity<Map> unpaidList(String token, String session, String... filters) {
        return it.get(token, u -> {
            u.path("/api/v1/siwes/admin/unpaid-entries").queryParam("session", session);
            for (int i = 0; i + 1 < filters.length; i += 2) u.queryParam(filters[i], filters[i + 1]);
            return u.build();
        });
    }

    private static List<Map<String, Object>> rowsOf(ResponseEntity<Map> list) {
        assertThat(status(list)).as(String.valueOf(list.getBody())).isEqualTo(200);
        return (List<Map<String, Object>>) list.getBody().get("rows");
    }

    /** the list answered, with this many rows over its whole selection (not the page) and this many students among them */
    private static void counts(String what, ResponseEntity<Map> list, int rows, int students) {
        assertThat(status(list)).as(what + ": " + list.getBody()).isEqualTo(200);
        assertThat(list.getBody()).as(what).containsEntry("total", rows).containsEntry("students", students);
    }

    @Test
    void theBursarysListOfUnpaidSiwesCoursesIsHeldToAUnitOfficesOwnUnitFilteredPagedAndCountedByStudent() {
        try (World w = new World("unpaidlist")) {
            String P = w.programme(400), P2 = w.programme(400);
            String s1 = w.px + " 301", s2 = w.px + " 322";
            w.course(s1, 6, 1, 300, true);
            w.course(s2, 3, 2, 300, true);
            w.offer(s1, P, 300, "Core");
            w.offer(s2, P, 300, "Core");
            w.offer(s1, P2, 300, "Core");
            UUID off1 = w.offering(s1, 1), off2 = w.offering(s2, 2);
            // X holds both SIWES courses (one in each semester), Y and Z one each (Z in the run's other programme); nobody has paid
            UUID X = w.student(P, 300), Y = w.student(P, 300), Z = w.student(P2, 300);
            w.held(X, off1, 1, 300, 6, true);
            w.held(X, off2, 2, 300, 3, true);
            w.held(Y, off1, 1, 300, 6, true);
            w.held(Z, off1, 1, 300, 6, true);
            // the run's department and faculty, and a department (and so a faculty) that is not the run's
            String facOwn = jdbc.sql("SELECT faculty_code FROM ref.department WHERE code = :d").param("d", w.dept).query(String.class).single();
            String facName = jdbc.sql("SELECT name FROM ref.faculty WHERE code = :f").param("f", facOwn).query(String.class).single();
            String otherDept = jdbc.sql("SELECT code FROM ref.department WHERE ended_on IS NULL AND faculty_code <> :f ORDER BY code LIMIT 1")
                    .param("f", facOwn).query(String.class).single();
            String otherFaculty = jdbc.sql("SELECT faculty_code FROM ref.department WHERE code = :d").param("d", otherDept).query(String.class).single();
            String bursar = ItSupport.token("bursar");

            // no fee published: the list is read all the same, and the fee in force is null
            ResponseEntity<Map> noFee = unpaidList(bursar, w.session);
            counts("no fee published", noFee, 4, 3);
            assertThat(noFee.getBody().get("fee")).isNull();
            w.publishFee();

            // rows and students: X's two courses are two rows and one student; each row says who, where and what
            ResponseEntity<Map> all = unpaidList(bursar, w.session, "size", "500");
            counts("the session", all, 4, 3);
            assertThat(all.getBody()).containsEntry("session", w.session).containsEntry("page", 0).containsEntry("size", 500);
            assertThat(money(all.getBody().get("fee"))).isEqualByComparingTo("4000");
            assertThat(rowsOf(all)).extracting(r -> r.get("matricNo") + "/" + r.get("courseCode"))
                    .containsExactlyInAnyOrder(w.matric(X) + "/" + s1, w.matric(X) + "/" + s2, w.matric(Y) + "/" + s1, w.matric(Z) + "/" + s1);
            assertThat(rowsOf(all)).filteredOn(r -> w.matric(Z).equals(r.get("matricNo"))).singleElement().satisfies(r -> {
                assertThat(r).containsEntry("studentId", Z.toString()).containsEntry("programmeCode", P2).containsEntry("programme", "B.Sc. SIWES FEE IT " + P2)
                        .containsEntry("departmentCode", w.dept).containsEntry("department", "SIWES FEE IT " + w.dept).containsEntry("facultyCode", facOwn)
                        .containsEntry("faculty", facName).containsEntry("currentLevel", 300).containsEntry("courseCode", s1).containsEntry("courseTitle", "SIWES FEE IT " + s1)
                        .containsEntry("level", 300).containsEntry("semester", 1).containsEntry("payable", true);
                assertThat(String.valueOf(r.get("name"))).startsWith(w.surnames.get(Z).toUpperCase());
            });
            assertThat(rowsOf(all)).filteredOn(r -> w.matric(X).equals(r.get("matricNo"))).extracting(r -> r.get("courseCode") + "@" + r.get("semester"))
                    .containsExactlyInAnyOrder(s1 + "@1", s2 + "@2");

            // a page at a time, the totals those of the whole selection: P's three rows in the list's order (faculty, department, programme,
            // name, then semester), one to a page; a page past the end is empty
            List<String> order = new ArrayList<>();
            for (int pg = 0; pg < 3; pg++) {
                ResponseEntity<Map> one = unpaidList(bursar, w.session, "programme", P, "size", "1", "page", String.valueOf(pg));
                counts("page " + pg, one, 3, 2);
                assertThat(one.getBody()).containsEntry("page", pg).containsEntry("size", 1);
                assertThat(rowsOf(one)).hasSize(1);
                order.add(rowsOf(one).get(0).get("matricNo") + "/" + rowsOf(one).get(0).get("courseCode"));
            }
            assertThat(order).containsExactly(w.matric(X) + "/" + s1, w.matric(X) + "/" + s2, w.matric(Y) + "/" + s1);
            assertThat(rowsOf(unpaidList(bursar, w.session, "programme", P, "size", "1", "page", "3"))).isEmpty();
            // a page is at least one row and at most the ceiling; a page before the first is the first
            ResponseEntity<Map> least = unpaidList(bursar, w.session, "size", "0", "page", "-3");
            assertThat(least.getBody()).containsEntry("size", 1).containsEntry("page", 0);
            assertThat(rowsOf(least)).hasSize(1);
            assertThat(unpaidList(bursar, w.session, "size", "100000").getBody()).containsEntry("size", 500);

            // the filters: faculty, department, programme, and a name or a matric number in any case
            counts("faculty", unpaidList(bursar, w.session, "faculty", facOwn), 4, 3);
            counts("another faculty", unpaidList(bursar, w.session, "faculty", otherFaculty), 0, 0);
            counts("department", unpaidList(bursar, w.session, "department", w.dept), 4, 3);
            counts("another department", unpaidList(bursar, w.session, "department", otherDept), 0, 0);
            counts("programme", unpaidList(bursar, w.session, "programme", P), 3, 2);
            counts("the other programme", unpaidList(bursar, w.session, "programme", P2), 1, 1);
            counts("programme and department", unpaidList(bursar, w.session, "programme", P2, "department", w.dept), 1, 1);
            counts("a name, in lower case", unpaidList(bursar, w.session, "q", w.surnames.get(X).toLowerCase()), 2, 1);
            counts("a matric number", unpaidList(bursar, w.session, "q", w.matric(Y)), 1, 1);
            counts("nobody of that name", unpaidList(bursar, w.session, "q", "ZZ-nobody-of-this-name"), 0, 0);

            // a unit office reads its own unit alone, whatever it asks (OfficeScope.bound): the Head of Department and the SIWES Coordinator
            // their department, the Dean and the Faculty Officer their faculty — the run's students are in the run's department
            String hodOwn = it.officer("hod", "department", w.dept), hodOther = it.officer("hod", "department", otherDept);
            String coordinatorOwn = it.officer("siwes", "department", w.dept), coordinatorOther = it.officer("siwes", "department", otherDept);
            String deanOwn = it.officer("dean", "faculty", facOwn), deanOther = it.officer("dean", "faculty", otherFaculty);
            String officerOwn = it.officer("facultyofficer", "faculty", facOwn), officerOther = it.officer("facultyofficer", "faculty", otherFaculty);
            for (String own : List.of(hodOwn, coordinatorOwn, deanOwn, officerOwn)) {
                counts("its own unit", unpaidList(own, w.session), 4, 3);
                counts("its own programme", unpaidList(own, w.session, "programme", P2), 1, 1);
                counts("its own department asked for", unpaidList(own, w.session, "department", w.dept), 4, 3);
                counts("its own faculty asked for", unpaidList(own, w.session, "faculty", facOwn), 4, 3);
            }
            // another unit's office is shown none of them (whatever is not asked for is filled in), and is refused the run's own unit
            for (String other : List.of(hodOther, coordinatorOther, deanOther, officerOther)) {
                counts("another unit", unpaidList(other, w.session), 0, 0);
            }
            for (String other : List.of(hodOther, coordinatorOther)) {
                assertThat(code(unpaidList(other, w.session, "department", w.dept))).isEqualTo("SCOPE_DEPARTMENT");
                assertThat(code(unpaidList(other, w.session, "programme", P))).isEqualTo("SCOPE_DEPARTMENT");
            }
            assertThat(code(unpaidList(hodOwn, w.session, "department", otherDept))).isEqualTo("SCOPE_DEPARTMENT");
            assertThat(code(unpaidList(hodOwn, w.session, "faculty", otherFaculty))).isEqualTo("SCOPE_DEPARTMENT");
            for (String other : List.of(deanOther, officerOther)) {
                assertThat(code(unpaidList(other, w.session, "faculty", facOwn))).isEqualTo("SCOPE_FACULTY");
                assertThat(code(unpaidList(other, w.session, "department", w.dept))).isEqualTo("SCOPE_FACULTY");
                assertThat(code(unpaidList(other, w.session, "programme", P))).isEqualTo("SCOPE_FACULTY");
            }
            for (String own : List.of(deanOwn, officerOwn)) {
                assertThat(code(unpaidList(own, w.session, "faculty", otherFaculty))).isEqualTo("SCOPE_FACULTY");
                assertThat(code(unpaidList(own, w.session, "department", otherDept))).isEqualTo("SCOPE_FACULTY");
            }
        }
    }

    // ── V777: a programme the Academic Office configured whose period is still a draft (the seven programmes seeded before V777) ──

    @Test
    void aStudentOfAConfiguredProgrammeWhosePeriodIsStillADraftIsChargedLikeAnyOtherAndRegistersItsSiwesCourseOnceItIsPaid() {
        try (World w = new World("seeded")) {
            w.publishFee();
            String P = w.programme(400);
            String siwes = w.px + " 311";
            w.course(siwes, 6, 2, 300, true);
            w.offer(siwes, P, 300, "Core");
            UUID off = w.offering(siwes, 2);
            UUID S = w.student(P, 300);
            // the programme takes part in the session (its period is made a draft where there is none) and the period stays a draft:
            // nobody is bound, as before the Academic Office opens the period — and before V777 the programme's SIWES course registered free
            ResponseEntity<Map> added = it.call(ItSupport.token("academic"), HttpMethod.POST, "/api/v1/siwes/admin/programmes", Map.of("session", w.session, "programmeCode", P));
            assertThat(status(added)).as(String.valueOf(added.getBody())).isEqualTo(200);
            assertThat(jdbc.sql("SELECT state FROM registration.siwes_period WHERE session = :s").param("s", w.session).query(String.class).single()).isEqualTo("DRAFT");
            assertThat(jdbc.sql("SELECT count(*) FROM registration.siwes_programme WHERE session = :s AND programme_code = :p").param("s", w.session).param("p", P)
                    .query(Integer.class).single()).isEqualTo(1);
            Map<String, Object> page = w.page(S);
            assertThat(page).containsEntry("applies", false).containsEntry("bound", false).containsEntry("mode", "COURSE").containsEntry("eligible", true)
                    .containsEntry("canPay", true);
            assertThat(((List<Map<String, Object>>) page.get("courses"))).singleElement().satisfies(c -> assertThat(c).containsEntry("code", siwes).containsEntry("held", false));

            // the course is refused until the fee is paid, and nothing of the refused save stays
            ResponseEntity<Map> unpaid = w.put(S, 2, off);
            assertThat(status(unpaid)).as(String.valueOf(unpaid.getBody())).isEqualTo(422);
            assertThat(code(unpaid)).isEqualTo("SIWES_UNPAID");
            assertThat(standing(S, w.session)).isEmpty();

            // paid, it is registered on Course Registration, standing on the payment
            String reference = w.pay(S);
            ResponseEntity<Map> saved = w.put(S, 2, off);
            assertThat(status(saved)).as(String.valueOf(saved.getBody())).isEqualTo(200);
            assertThat(standing(S, w.session)).containsExactly(siwes + ":REGISTERED");
            assertThat(linked(S, w.session)).containsExactly(siwes + "<" + reference);
        }
    }

    // ── the old portal's registration loader keeps its override: a SIWES course of the current session stands, unpaid ──

    @Test
    void theOldPortalsRegistrationLoaderPlacesASiwesCourseOfTheCurrentSessionUnpaidWhereTheStudentsOwnDoorRefusesIt() {
        try (World w = new World("loader")) {
            w.publishFee();
            w.openSemesters();   // the student's own door below is a save of the form: its semester is open, so the refusal it meets is the fee's
            String P = w.programme(400);
            String siwes = w.px + " 301";
            w.course(siwes, 6, 1, 300, true);
            w.offer(siwes, P, 300, "Core");
            UUID off = w.offering(siwes, 1);
            UUID J = w.student(P, 300), K = w.student(P, 300);
            String ict = ItSupport.token("ict");

            // the old portal's registration, loaded as the Directorate of ICT loads it, under a confirmed upload
            ResponseEntity<Map> confirmed = it.call(ict, HttpMethod.POST, "/api/v1/results/legacy/uploads", Map.of("kind", "REGISTRATION", "fileName", "siwes-held.xlsx",
                    "rows", 1, "reason", "SiwesFeeEveryCourseIT: the old portal's registration of a SIWES course"));
            assertThat(status(confirmed)).as(String.valueOf(confirmed.getBody())).isEqualTo(200);
            String uploadId = String.valueOf(confirmed.getBody().get("id"));
            ResponseEntity<Map> loaded = it.call(ict, HttpMethod.POST, "/api/v1/results/legacy/registration", Map.of("session", w.session, "semester", 1,
                    "rows", List.of(Map.of("line", "2", "matric", w.matric(J), "course", siwes, "title", "SIWES FEE IT " + siwes, "creditUnits", "6",
                                           "category", "Core", "level", "300")), "uploadId", uploadId));
            assertThat(status(loaded)).as(String.valueOf(loaded.getBody())).isEqualTo(200);
            assertThat(((Number) loaded.getBody().get("entries")).intValue()).as(String.valueOf(loaded.getBody())).isEqualTo(1);
            assertThat(status(it.call(ict, HttpMethod.POST, "/api/v1/results/legacy/uploads/" + uploadId + "/finish", Map.of("complete", true)))).isEqualTo(200);

            // it stands on J's registration with nothing paid, linked to no payment, and the Bursary's list asks J for the fee
            assertThat(standing(J, w.session)).extracting(c -> c.split(":")[0]).containsExactly(siwes);
            assertThat(linked(J, w.session)).as("placed under the override it stands on no payment").isEmpty();
            ResponseEntity<Map> listed = it.get(ItSupport.token("bursar"), "/api/v1/siwes/admin/unpaid-entries?session=" + w.session + "&programme=" + P + "&size=500");
            assertThat(rowsOf(listed)).singleElement().satisfies(r -> assertThat(r).containsEntry("matricNo", w.matric(J)).containsEntry("courseCode", siwes)
                    .containsEntry("payable", true));
            // the override is the loaders': the student's own door refuses the same course
            ResponseEntity<Map> own = w.put(K, 1, off);
            assertThat(status(own)).as(String.valueOf(own.getBody())).isEqualTo(422);
            assertThat(code(own)).isEqualTo("SIWES_UNPAID");
            assertThat(standing(K, w.session)).isEmpty();
        }
    }
}
