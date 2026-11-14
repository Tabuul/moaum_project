package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.math.BigDecimal;
import java.time.LocalDate;
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
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.web.client.RestClient;

/**
 * V752 — SIWES registration at 300 Level, Second Semester (the University's master prompt of 12 November 2026), end to end through the
 * API, the brief's fourteen acceptance scenarios in turn: (1) an eligible student sees SIWES; (2) the semester offers the SIWES course
 * alone; (3) the ₦4,000 is paid through the existing gateways (the checkout, the WebPAY start page, PayDirect validation, the return
 * page), confirmed as the Summer's tests confirm it (the Bursary's lane); (4) the course is registered after the payment is verified,
 * approved at once, once; (5) no ordinary course is registered on the student's door, (6) nor through an office's API; (7) the fee is
 * never paid twice — the reference is drawn once, a paid session draws none, a late second payment is a credit for the Bursar; (8) a
 * programme not configured is not restricted (V503 stands); (9) a postgraduate is not subject; (10) the first semester is unchanged;
 * (11) history is intact — the old portal's registration of a past semester SIWES binds loads, the current one is refused; (12) the
 * statistics, the lists and the Bursary's reconciliation read the records; (13) the six-month training dates are shown; (14) another
 * level is unchanged. Then access: a department reader held to its department (the desk and the supervision of an offering), a
 * non-reader refused, the setters and the Bursary checked by the API and again by the database. The reviews of the build answered:
 * the student's own drop door sheds an ordinary course placed before SIWES bound them (never the SIWES course, and nothing is added);
 * an office adding to an approved SIWES registration is refused; the published fee stays in force while Student Accounts' restatement
 * waits for the Bursar; a credit is reopened by the Bursar alone and never settled while it settles the fee or once its payment is
 * archived; a payment refunded on the refund desk no longer settles, and none is refunded under a standing registration; the old fees
 * reset keeps the old-portal payment a SIWES registration stands on. The second round's: one payment never given back twice, the credit
 * recorded refunded first (the refund desk refuses, REFUND_SIWES_CREDIT_SETTLED) or the refund desk first (the credit waits,
 * SIWES_CREDIT_REFUND_DESK, and the approval settles it); the settling payment refunded on the desk and the open credit settling the
 * fee in its place (listed settles, nothing to refund); a partial refund ending the settlement; an old-portal payment's credit refunded
 * by the Bursar; the period not opened while no SIWES course reaches the programme (SIWES_COURSE_MISSING), and a mapping students paid
 * on replaced, never taken away (SIWES_COURSE_IN_USE); after a remap, a registered student's own course (registration.courseCode, never
 * among otherCourses); a carry-over and a deferred course placed while the period was a draft dropped on the student's door, then SIWES
 * registered (K9); the Head of Department's return refused (REG_RETURN_SIWES); the credits and payments in the screens' shapes (K4',
 * K6'). The third round's: the Second Semester school fees on the SIWES page (K10: semesterFees, canRegister waiting on them); the
 * reset offered and made in a SIWES-bound Second Semester while add/drop is closed (K11, K9); ICT Support dropping a course in the
 * SIWES course's way with no override (K12); an office submit of a SIWES registration refused (REG_STATUS_SIWES) and a part of a SIWES
 * payment refused on the refund desk, raised or approved (REFUND_SIWES_PART, K13); a programme added to the open period only once its
 * students have a course, and a paid student whose course ended told SIWES_COURSE_MISSING on registering; a registered student whose
 * level is corrected (no longer bound) having the SIWES course dropped by the Student edit with no override, then the fee refunded whole
 * (K12). The fourth round's: an office's undoing leaving an ordinary registration (the desk's and the history's siwes flag false) and the
 * student's SIWES of every session on their page (history); an old-portal SIWES credit that may be a bank double charge (V561) refused by
 * the Bursar's hand (SIWES_CREDIT_CHECK_BANK) and on the refund desk, either payment (REFUND_SIWES_CHECK_BANK), until the bank check finds
 * it received (K15); a SIWES course entered on a registration a Head approved stamped AUTO, now, by nobody (K17). The fifth round's: the
 * payment correction desk moving neither payment of a possible bank double charge before that check (REALLOC_SIWES_CHECK_BANK, K18); how
 * each credit was settled (settledKind: HAND_REFUND, DESK_REFUND, SETTLES — K19); a check that found one record never received holding
 * the whole day — the withdrawal waiting, then rejected — until the record is withdrawn, the record received settling the fee meanwhile
 * and after (K20); the withdrawal as never received of the only SIWES payment a standing registration rests on refused
 * (PAY_NOT_RECEIVED_SIWES_REGISTERED, K21), and allowed beside another; the desk's course with its catalogue state, at the Board and
 * ended (K25). The sixth round's: the withdrawal as never received of a SIWES payment whose credit the Bursar refunded refused, raised on
 * its own or named by a second bank check, which is refused whole (PAY_NOT_RECEIVED_SIWES_REFUNDED, K26); the record the bank received
 * settling the fee (its credit APPLIED, SETTLES) the moment the other is found never received (K27); the bank check's wait as the
 * database's code beside its words, on the credits list and the payments report alike — UNCHECKED, PROPOSED, NOT_RECEIVED on the record
 * the bank never received and NOT_RECEIVED_WAITING on the one it did (bankCheckState, K31); the SIWES menu item kept while a payment of
 * a session SIWES bound the student in stands, and gone once that SIWES is wholly undone (siwesArea, K30). The seventh round's: a
 * record the bank check found never received stays so when the old portal's export, loaded again on Old Fees History without payment
 * numbers, puts its day right — held, refused on the refund desk, the other record's credit settling the fee as before (K32); a credit
 * the Bursar reopens while nothing else settles the fee settles it, the answer saying so (APPLIED, SETTLES — K33); and a payment given
 * back, its credit refunded or itself refunded on the refund desk, shows no bank-check hold on the payments report (K35). The test
 * makes its session CURRENT (an IT database has none of its own) and puts the calendar, the fee lines, the approval rule and the gateway
 * key back, and the course it ended live again.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class SiwesRegistrationIT {

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    ItSupport it;
    RestClient open;
    final String instrument = "BUR/IT/SIWES752";

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
        open = RestClient.builder().baseUrl("http://localhost:" + port).defaultStatusHandler(s -> true, (q, r) -> { }).build();
    }

    static String student(UUID id) {
        return TestTokens.token(id, List.of("student"));
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

    String postXml(String path, String xml) {
        return open.post().uri(path).contentType(MediaType.TEXT_XML).body(xml).retrieve().body(String.class);
    }

    /** a bank's confirmation, as the Bursary's lane records it (as SummerSemesterIT confirms) */
    private String confirm(String reference) {
        return it.db(() -> {
            jdbc.sql("SELECT set_config('moaum.actor_office', 'bursar', true)").query().listOfRows();
            return jdbc.sql("SELECT finance.confirm_payment(:r, 'Bank transfer', 'SiwesRegistrationIT')").param("r", reference).query(String.class).single();
        });
    }

    /** the old portal's SIWES payment of the session, as its import records it ("SIWES (legacy)") */
    private void oldPortalSiwes(UUID student, String session, String tag) {
        it.db(() -> jdbc.sql("""
                INSERT INTO finance.payment_reference (student_id, session, reference, purpose, amount, generated_at, expires_at, confirmed_at, confirmed_by,
                                                       channel, note, receipt_no)
                VALUES (:s, :ses, 'MOAUM-LEG-IT752-' || :t, 'SIWES (legacy) · semester 1', 4000, now() - interval '30 days', now() - interval '30 days',
                        now() - interval '30 days', gen_random_uuid(), 'Legacy', 'Imported from the old portal', 'RCT-LEG-IT752-' || :t)
                """).param("s", student).param("ses", session).param("t", tag).update());
    }

    /** a row of the old portal's fees export as the Bursary's Old Fees History upload sends it: a Second Semester SIWES payment of ₦4,000
     *  paid on the day given (day first, as the export writes it), under the old portal's payment number when one is given */
    private static Map<String, Object> oldFeesRow(String matricNo, String session, LocalDate day, String payref) {
        Map<String, Object> row = new java.util.LinkedHashMap<>();
        row.put("matric", matricNo);
        row.put("session", session);
        row.put("semester", "2");
        row.put("purpose", "SIWES");
        row.put("amount", "4000");
        row.put("paidOn", String.format("%02d/%02d/%04d", day.getDayOfMonth(), day.getMonthValue(), day.getYear()));
        if (payref != null) row.put("receiptNo", payref);
        return row;
    }

    private UUID offering(String course, String session, int semester) {
        return jdbc.sql("SELECT id FROM catalogue.offering WHERE course_code = :c AND session = :s AND semester = :m ORDER BY stream = 'REGULAR' DESC LIMIT 1")
                .param("c", course).param("s", session).param("m", semester).query(UUID.class).single();
    }

    private List<String> codes(List<Map<String, Object>> rows, String key) {
        return rows.stream().map(r -> String.valueOf(r.get(key))).toList();
    }

    /** the Bursar's SIWES credit on a payment, as GET /credits lists it (null: not listed) */
    private Map<String, Object> creditOf(String token, String session, String reference) {
        return ((List<Map<String, Object>>) (List<?>) it.getList(token, "/api/v1/finance/siwes/credits?session=" + session).getBody()).stream()
                .filter(c -> reference.equals(c.get("reference"))).findFirst().orElse(null);
    }

    /** the Bursary's payments report rows of the payments named (GET /payments of the session and programme), by reference: each one
     *  listed once */
    private Map<String, Map<String, Object>> paymentsOf(String token, String session, String programme, String... references) {
        List<Map<String, Object>> rows = (List<Map<String, Object>>) it.get(token, "/api/v1/finance/siwes/payments?session=" + session + "&programme=" + programme
                + "&size=500").getBody().get("rows");
        Map<String, Map<String, Object>> out = new HashMap<>();
        for (String reference : references) {
            List<Map<String, Object>> found = rows.stream().filter(r -> reference.equals(r.get("reference"))).toList();
            assertThat(found).as(reference + " on the payments report").hasSize(1);
            out.put(reference, found.get(0));
        }
        return out;
    }

    /** a refund raised on the refund desk by one Bursary officer and, when approve, approved by another; returns the refund's reference */
    private String refund(String maker, String checker, UUID student, String payer, String source, int amount, boolean approve) {
        ResponseEntity<Map> raised = it.call(maker, HttpMethod.POST, "/api/v1/finance/refunds", Map.of("student", student, "payer", payer,
                "reason", "SiwesRegistrationIT: the SIWES payment given back", "amount", amount, "source", source));
        assertThat(status(raised)).as(String.valueOf(raised.getBody())).isEqualTo(200);
        String reference = String.valueOf(raised.getBody().get("reference"));
        if (approve) approveRefund(checker, reference);
        return reference;
    }

    private void approveRefund(String checker, String reference) {
        UUID id = jdbc.sql("SELECT id FROM finance.refund WHERE reference = :r").param("r", reference).query(UUID.class).single();
        ResponseEntity<Map> approved = it.call(checker, HttpMethod.POST, "/api/v1/finance/refunds/" + id + "/approve", Map.of());
        assertThat(status(approved)).as(String.valueOf(approved.getBody())).isEqualTo(200);
    }

    /** a payment archived for review on the Archived payments desk; returns the archive's id */
    private UUID archive(String accounts, String reference) {
        UUID payment = jdbc.sql("SELECT id FROM finance.payment_reference WHERE reference = :r").param("r", reference).query(UUID.class).single();
        ResponseEntity<Map> archived = it.call(accounts, HttpMethod.POST, "/api/v1/finance/payment-archive", Map.of("payment", payment, "reason", "UNVERIFIED_PAYMENT",
                "note", "The bank has not confirmed this SIWES payment", "confirmed", true));
        assertThat(status(archived)).as(String.valueOf(archived.getBody())).isEqualTo(200);
        return UUID.fromString(String.valueOf(((Map<String, Object>) archived.getBody().get("archive")).get("id")));
    }

    /** an archived payment restored as the desk restores it: proposed with its evidence by one officer, approved by a Bursar officer */
    private void restore(String accounts, String bursar, UUID archive) {
        ResponseEntity<Map> proposed = it.call(accounts, HttpMethod.POST, "/api/v1/finance/payment-archive/" + archive + "/proposal", Map.of("outcome", "RESTORE",
                "note", "The bank confirmed the payment and the student it stands on", "items", List.of(Map.of("kind", "GATEWAY_PAYER", "value", "The bank's payer record")),
                "confirmed", true));
        assertThat(status(proposed)).as(String.valueOf(proposed.getBody())).isEqualTo(200);
        ResponseEntity<Map> decided = it.call(bursar, HttpMethod.POST, "/api/v1/finance/payment-archive/" + archive + "/decision",
                Map.of("decision", "APPROVE", "note", "The bank's record seen", "confirmed", true));
        assertThat(status(decided)).as(String.valueOf(decided.getBody())).isEqualTo(200);
        assertThat((Map<String, Object>) decided.getBody().get("result")).containsEntry("state", "RECONCILED");
    }

    @Test
    void anEligibleStudentPaysOnceRegistersTheSiwesCourseAloneAndTheDesksReadIt() {
        int y = it.freeYear(3100, 3900, 1, 1);
        String before = (y - 1) + "/" + y, session = y + "/" + (y + 1);
        it.session(before, y - 1);
        it.session(session, y);
        String beforeState = jdbc.sql("SELECT state FROM policy.academic_session WHERE name = :n").param("n", before).query(String.class).single();
        String sessionState = jdbc.sql("SELECT state FROM policy.academic_session WHERE name = :n").param("n", session).query(String.class).single();
        String previousCurrent = jdbc.sql("SELECT name FROM policy.academic_session WHERE state = 'CURRENT' ORDER BY starts_on DESC LIMIT 1").query(String.class).optional().orElse(null);
        String px = it.freeCoursePrefix("Z");
        String siwesCode = px + " 302", elective = px + " 304", first = px + " 301", v503 = px + " 399", pgCourse = px + " 702";
        // a 200 Level course failed (a carry-over), one deferred, and the SIWES course the Academic Office later maps in its place
        String carry = px + " 204", deferred = px + " 206", remap = px + " 306";
        // the SIWES course of a programme added at the end (M), ended after its student E paid (SIWES_COURSE_MISSING), then restored
        String missing = px + " 308";
        String yy = String.format("%02d", y % 100);
        // J and L are made at the end, for the fourth round's cases alone (K15, K17), N for the fifth round's (K20), and O and W for the
        // seventh round's (K32; K33, K35): reserved here, out of every count before
        String[] who = {"A", "B", "G", "K", "F", "C", "D", "H", "E", "J", "L", "N", "O", "W"};
        int n = it.freeDraw(1000, 8000, k -> {
            List<String> ids = new java.util.ArrayList<>();
            for (int i = 0; i < who.length; i++) {
                ids.add("ZZSIWES" + who[i] + k);
                ids.add("MOAU/" + px + "/" + yy + "/" + (k + i));
            }
            return ids;
        });
        Map<String, String> matric = new HashMap<>();
        for (int i = 0; i < who.length; i++) matric.put(who[i], "MOAU/" + px + "/" + yy + "/" + (n + i));
        // four programme codes no run has used (the register's shape: C and five digits): P configured, Q not (its 300/2 is a V503
        // attachment semester), R postgraduate, M added to the open period at the end
        List<String> progs = jdbc.sql("""
                SELECT 'C' || lpad(k::text, 5, '0') FROM generate_series(97000, 99999) k
                 WHERE NOT EXISTS (SELECT 1 FROM ref.programme p WHERE p.code = 'C' || lpad(k::text, 5, '0'))
                 ORDER BY random() LIMIT 4
                """).query(String.class).list();
        String P = progs.get(0), Q = progs.get(1), R = progs.get(2), M = progs.get(3);
        String dept = jdbc.sql("SELECT dept_code FROM ref.programme WHERE category = 'UNDER GRADUATE' AND dept_code IS NOT NULL AND NOT archived ORDER BY code LIMIT 1")
                .query(String.class).single();
        String otherDept = jdbc.sql("SELECT code FROM ref.department WHERE ended_on IS NULL AND code <> :d ORDER BY code LIMIT 1").param("d", dept).query(String.class).single();
        LocalDate today = LocalDate.now(java.time.ZoneId.of("Africa/Lagos"));
        LocalDate trainingStarts = today.plusDays(30), trainingEnds = trainingStarts.plusMonths(6);
        String ict = ItSupport.token("ict");
        boolean keySet = false;
        try {
            it.db(() -> {
                jdbc.sql("UPDATE policy.academic_session SET state = 'CLOSED' WHERE state = 'CURRENT'").update();
                jdbc.sql("UPDATE policy.academic_session SET state = 'CLOSED' WHERE name = :n").param("n", before).update();
                jdbc.sql("UPDATE policy.academic_session SET state = 'CURRENT', senate_minute = coalesce(senate_minute, 'SEN/IT/752') WHERE name = :n").param("n", session).update();
                jdbc.sql("""
                        INSERT INTO ref.programme (code, name, dept_code, faculty_code, category, min_score, final_level, duration_years)
                        SELECT x.code, x.name, d.code, d.faculty_code, x.category, 0, x.final_level, x.years
                          FROM ref.department d,
                               (VALUES (:p, 'B.Sc. SIWES IT ' || :p, 'UNDER GRADUATE', 400, 4), (:q, 'B.Sc. SIWES IT ' || :q, 'UNDER GRADUATE', 400, 4),
                                       (:r, 'M.Sc. SIWES IT ' || :r, 'POST GRADUATE', 900, 2), (:m, 'B.Sc. SIWES IT ' || :m, 'UNDER GRADUATE', 400, 4))
                                       x(code, name, category, final_level, years)
                         WHERE d.code = :d
                        ON CONFLICT (code) DO NOTHING
                        """).param("p", P).param("q", Q).param("r", R).param("m", M).param("d", dept).update();
                for (Object[] c : new Object[][] {{siwesCode, 6, 2, 300, "Core", true}, {elective, 3, 2, 300, "Elective", false}, {first, 3, 1, 300, "Core", false},
                        {v503, 6, 2, 300, "Core", true}, {pgCourse, 3, 2, 700, "Core", false}, {carry, 3, 2, 200, "Core", false},
                        {deferred, 3, 2, 200, "Core", false}, {remap, 6, 2, 300, "Core", true}, {missing, 6, 2, 300, "Core", true}}) {
                    jdbc.sql("""
                            INSERT INTO catalogue.course (code, title, units, semester, level, dept_code, kind, state, industrial_training)
                            VALUES (:c, 'SIWES IT ' || :c, :u, :s, :l, :d, :k, 'LIVE', :it) ON CONFLICT (code) DO NOTHING
                            """).param("c", c[0]).param("u", c[1]).param("s", c[2]).param("l", c[3]).param("d", dept).param("k", c[4]).param("it", c[5]).update();
                }
                for (Object[] o : new Object[][] {{siwesCode, P, 300, "Core"}, {first, P, 300, "Core"}, {elective, P, 300, "Elective"},
                        {v503, Q, 300, "Core"}, {elective, Q, 300, "Elective"}, {pgCourse, R, 700, "Core"}}) {
                    jdbc.sql("INSERT INTO catalogue.course_offer (course_code, programme_code, level, basis) VALUES (:c, :p, :l, :b) ON CONFLICT DO NOTHING")
                            .param("c", o[0]).param("p", o[1]).param("l", o[2]).param("b", o[3]).update();
                }
                for (Object[] o : new Object[][] {{siwesCode, 2, "REGULAR"}, {elective, 2, "REGULAR"}, {first, 1, "REGULAR"}, {v503, 2, "REGULAR"}, {pgCourse, 2, "PG"},
                        {carry, 2, "REGULAR"}, {deferred, 2, "REGULAR"}}) {
                    jdbc.sql("INSERT INTO catalogue.offering (id, course_code, session, semester, stream) VALUES (gen_random_uuid(), :c, :s, :m, :st) ON CONFLICT DO NOTHING")
                            .param("c", o[0]).param("s", session).param("m", o[1]).param("st", o[2]).update();
                }
                return null;
            });
            Map<String, UUID> id = new HashMap<>();
            for (String w : List.of("A", "B", "G", "K", "H")) id.put(w, it.student("ZZSIWES" + w + n, P, null, matric.get(w), 300));
            id.put("F", it.student("ZZSIWESF" + n, P, null, matric.get("F"), 200));
            id.put("C", it.student("ZZSIWESC" + n, Q, null, matric.get("C"), 300));
            id.put("E", it.student("ZZSIWESE" + n, M, null, matric.get("E"), 300));
            UUID pgId = UUID.randomUUID();
            id.put("D", pgId);
            it.db(() -> {
                jdbc.sql("""
                        INSERT INTO people.student (id, matric_no, surname, other_names, programme_code, entry_mode, entry_session, entry_level, current_level,
                                                    status, matriculated_at)
                        VALUES (:id, :m, :s, 'Invented', :p, 'POSTGRADUATE', :e, 700, 700, 'ACTIVE', now())
                        """).param("id", pgId).param("m", matric.get("D")).param("s", "ZZSIWESD" + n).param("p", R).param("e", before).update();
                jdbc.sql("UPDATE people.student SET entry_session = :e WHERE id = ANY (CAST(:ids AS uuid[])) AND entry_mode <> 'POSTGRADUATE'")
                        .param("e", before).param("ids", id.values().toArray(new UUID[0])).update();
                // the session's school fees, stated for both undergraduate programmes and paid by A, C and H; a clearance scheme in force where none is
                jdbc.sql("INSERT INTO finance.fee_schedule (session, item, amount, level, programme_code) VALUES (:s, 'School fees', 100000, 300, :p), (:s, 'School fees', 100000, 300, :q)")
                        .param("s", session).param("p", P).param("q", Q).update();
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
                for (String w : List.of("A", "C", "H")) {
                    String ref = jdbc.sql("SELECT finance.new_purpose_reference(:s, :ses, 100000, 'School fees ' || :ses)").param("s", id.get(w)).param("ses", session)
                            .query(String.class).single();
                    jdbc.sql("SELECT finance.confirm_payment(:r, 'BANK_BRANCH', 'teller for the SIWES test')").param("r", ref).query(String.class).single();
                }
                return null;
            });
            UUID A = id.get("A"), B = id.get("B"), G = id.get("G"), K = id.get("K"), F = id.get("F"), C = id.get("C"), D = id.get("D"), H = id.get("H"),
                    E = id.get("E");
            String academic = ItSupport.token("academic"), bursar = ItSupport.token("bursar"), accounts = ItSupport.token("studentaccounts");
            // the refund desk's two Bursary officers: one raises a refund, another approves it
            String maker = TestTokens.token(UUID.randomUUID(), List.of("bursar")), checker = TestTokens.token(UUID.randomUUID(), List.of("bursar"));
            String admin = "/api/v1/siwes/admin";
            UUID electiveOff = offering(elective, session, 2), siwesOff = offering(siwesCode, session, 2), firstOff = offering(first, session, 1);

            // ── the Academic Office configures the session: a postgraduate programme refused, P taken, its SIWES course an existing
            //    Second Semester course of the catalogue (a first-semester one and one not in the catalogue refused) ──
            Map<String, Object> cfg0 = it.get(academic, admin + "/config?session=" + session).getBody();
            assertThat(cfg0).containsEntry("session", session);
            assertThat(cfg0.get("period")).isNull();
            assertThat((List<Map<String, Object>>) cfg0.get("candidates")).anySatisfy(c -> assertThat(c).containsEntry("code", P).containsEntry("attachment", true));
            assertThat((Map<String, Object>) cfg0.get("access")).containsEntry("set", true);
            ResponseEntity<Map> pg = it.call(academic, HttpMethod.POST, admin + "/programmes", Map.of("session", session, "programmeCode", R));
            assertThat(status(pg)).isEqualTo(422);
            assertThat(code(pg)).isEqualTo("SIWES_NOT_UNDERGRADUATE");
            assertThat(status(it.call(bursar, HttpMethod.POST, admin + "/programmes", Map.of("session", session, "programmeCode", P)))).isEqualTo(403);
            ResponseEntity<Map> added = it.call(academic, HttpMethod.POST, admin + "/programmes", Map.of("session", session, "programmeCode", P));
            assertThat(status(added)).as(String.valueOf(added.getBody())).isEqualTo(200);
            assertThat(codes((List<Map<String, Object>>) added.getBody().get("programmes"), "code")).containsExactly(P);
            // the period does not open while no SIWES course reaches P's 300 Level students (nothing is written)
            Map<String, Object> tooSoon = new HashMap<>();
            tooSoon.put("session", session);
            tooSoon.put("state", "OPEN");
            tooSoon.put("registrationOpens", today.minusDays(1).toString());
            tooSoon.put("registrationCloses", today.plusDays(10).toString());
            tooSoon.put("trainingStarts", trainingStarts.toString());
            tooSoon.put("trainingEnds", trainingEnds.toString());
            tooSoon.put("durationMonths", 6);
            ResponseEntity<Map> unmapped = it.call(academic, HttpMethod.PUT, admin + "/period", tooSoon);
            assertThat(status(unmapped)).as(String.valueOf(unmapped.getBody())).isEqualTo(422);
            assertThat(code(unmapped)).isEqualTo("SIWES_COURSE_MISSING");
            assertThat(String.valueOf(unmapped.getBody().get("detail"))).contains(P);
            Map<String, Object> mapping = new HashMap<>();
            mapping.put("programmeCode", P);
            mapping.put("curriculum", null);
            mapping.put("courseCode", first);
            assertThat(code(it.call(academic, HttpMethod.PUT, admin + "/courses", mapping))).isEqualTo("SIWES_COURSE_SEMESTER");
            mapping.put("courseCode", px + " 999");
            assertThat(code(it.call(academic, HttpMethod.PUT, admin + "/courses", mapping))).isEqualTo("SIWES_COURSE_UNKNOWN");
            mapping.put("courseCode", siwesCode);
            ResponseEntity<Map> mapped = it.call(academic, HttpMethod.PUT, admin + "/courses", mapping);
            assertThat(status(mapped)).as(String.valueOf(mapped.getBody())).isEqualTo(200);
            assertThat((Map<String, Object>) mapped.getBody().get("course")).containsEntry("code", siwesCode).containsEntry("units", 6).containsEntry("state", "LIVE");
            // K25: the desk reads each mapped course with its catalogue state (it warns of one not LIVE)
            assertThat((List<Map<String, Object>>) it.get(academic, admin + "/config?session=" + session).getBody().get("programmes")).singleElement().satisfies(p -> {
                assertThat(p).containsEntry("code", P);
                assertThat((Map<String, Object>) p.get("course")).containsEntry("code", siwesCode).containsEntry("state", "LIVE");
            });

            // a draft binds nobody: A is not yet in SIWES (K1: applies says so)
            Map<String, Object> draft = it.get(student(A), "/api/v1/me/siwes").getBody();
            assertThat((List<String>) draft.get("reasons")).contains("NO_PERIOD");
            assertThat(draft).containsEntry("applies", false);
            assertThat(it.get(student(A), "/api/v1/me").getBody()).containsEntry("siwesArea", false);
            // so H registers an ordinary Second Semester course on the ordinary page, before SIWES binds P
            ResponseEntity<Map> beforeSiwes = it.call(student(H), HttpMethod.PUT, "/api/v1/me/registration", Map.of("session", session, "semester", 2, "offerings", List.of(electiveOff)));
            assertThat(status(beforeSiwes)).as(String.valueOf(beforeSiwes.getBody())).isEqualTo(200);
            // and H's draft holds a carry-over and a deferred course, as the student's draft places those the results and a deferment
            // state (K9: they wait for a later semester once SIWES binds H)
            UUID carryOff = offering(carry, session, 2), deferredOff = offering(deferred, session, 2);
            it.db(() -> jdbc.sql("""
                    INSERT INTO registration.entry (registration_id, offering_id, units, entry_type, status)
                    SELECT r.id, x.o, 3, x.t, 'REGISTERED' FROM registration.course_registration r,
                           (VALUES (CAST(:c AS uuid), 'CARRYOVER'), (CAST(:d AS uuid), 'DEFERRED')) x(o, t)
                     WHERE r.student_id = :s AND r.session = :ss AND r.semester = 2
                    """).param("c", carryOff).param("d", deferredOff).param("s", H).param("ss", session).update());

            // the period: opening needs both windows dated; the bursar may not set it; the database checks the office again
            Map<String, Object> period = new HashMap<>();
            period.put("session", session);
            period.put("state", "OPEN");
            period.put("registrationOpens", today.minusDays(1).toString());
            period.put("registrationCloses", today.plusDays(10).toString());
            period.put("durationMonths", 6);
            period.put("note", "SIWES of the session, Senate approved");
            assertThat(code(it.call(academic, HttpMethod.PUT, admin + "/period", period))).isEqualTo("SIWES_PERIOD_DATES");
            period.put("trainingStarts", trainingStarts.toString());
            period.put("trainingEnds", trainingEnds.toString());
            assertThat(status(it.call(bursar, HttpMethod.PUT, admin + "/period", period))).isEqualTo(403);
            String academicLecturer = TestTokens.token(UUID.randomUUID(), List.of("academic", "lecturer"));
            ResponseEntity<Map> asLecturer = it.callWith(academicLecturer, HttpMethod.PUT, admin + "/period", period, Map.of("X-Active-Office", "lecturer"));
            assertThat(status(asLecturer)).isEqualTo(422);
            assertThat(code(asLecturer)).isEqualTo("SIWES_OFFICE");
            ResponseEntity<Map> opened = it.call(academic, HttpMethod.PUT, admin + "/period", period);
            assertThat(status(opened)).as(String.valueOf(opened.getBody())).isEqualTo(200);
            assertThat(opened.getBody()).containsEntry("state", "OPEN").containsEntry("durationMonths", 6);

            // ── the Bursary: no fee yet, so no reference; stated by Student Accounts (a draft), published by the Bursar alone ──
            ResponseEntity<Map> noFee = it.call(student(A), HttpMethod.POST, "/api/v1/me/siwes/reference", Map.of());
            assertThat(status(noFee)).isEqualTo(422);
            assertThat(code(noFee)).isEqualTo("SIWES_FEE_NOT_SET");
            assertThat(status(it.call(academic, HttpMethod.PUT, "/api/v1/finance/siwes/fee", Map.of("session", session, "amount", 4000)))).isEqualTo(403);
            ResponseEntity<Map> stated = it.call(accounts, HttpMethod.PUT, "/api/v1/finance/siwes/fee", Map.of("session", session, "amount", 4000, "note", "The SIWES registration fee"));
            assertThat(status(stated)).as(String.valueOf(stated.getBody())).isEqualTo(200);
            assertThat(stated.getBody()).containsEntry("state", "DRAFT");
            assertThat(status(it.call(accounts, HttpMethod.POST, "/api/v1/finance/siwes/fee/publish", Map.of("session", session)))).isEqualTo(403);
            ResponseEntity<Map> published = it.call(bursar, HttpMethod.POST, "/api/v1/finance/siwes/fee/publish", Map.of("session", session));
            assertThat(status(published)).as(String.valueOf(published.getBody())).isEqualTo(200);
            assertThat(published.getBody()).containsEntry("state", "PUBLISHED");
            assertThat(money(published.getBody().get("amount"))).isEqualByComparingTo("4000");
            assertThat((List<?>) it.get(bursar, "/api/v1/finance/siwes/fee?session=" + session).getBody().get("history")).hasSizeGreaterThanOrEqualTo(2);
            // K2: Student Accounts restates it — a draft beside the published fee, which stays in force (never withdrawn) until the Bursar
            // publishes the draft (at the end, below)
            ResponseEntity<Map> restated = it.call(accounts, HttpMethod.PUT, "/api/v1/finance/siwes/fee", Map.of("session", session, "amount", 5000, "note", "The fee restated for the Bursar"));
            assertThat(status(restated)).as(String.valueOf(restated.getBody())).isEqualTo(200);
            assertThat(restated.getBody()).containsEntry("state", "PUBLISHED");
            assertThat(money(restated.getBody().get("amount"))).isEqualByComparingTo("4000");
            assertThat(money(((Map<String, Object>) restated.getBody().get("draft")).get("amount"))).isEqualByComparingTo("5000");
            Map<String, Object> feeNow = it.get(ItSupport.token("audit"), "/api/v1/finance/siwes/fee?session=" + session).getBody();
            assertThat(feeNow).containsEntry("state", "PUBLISHED");
            assertThat(money(feeNow.get("amount"))).isEqualByComparingTo("4000");
            assertThat((List<Map<String, Object>>) feeNow.get("history")).filteredOn(h -> "STATED".equals(h.get("action")) && h.get("wasAmount") != null)
                    .extracting(h -> money(h.get("amount")).intValue() + "/" + money(h.get("wasAmount")).intValue()).contains("5000/4000");

            // ── (1) an eligible student sees SIWES; (13) the training period and its six months are shown ──
            assertThat(it.get(student(A), "/api/v1/me").getBody()).containsEntry("siwesArea", true);
            Map<String, Object> mine = it.get(student(A), "/api/v1/me/siwes").getBody();
            assertThat(mine).containsEntry("eligible", true).containsEntry("applies", true).containsEntry("session", session).containsEntry("level", 300).containsEntry("semester", 2)
                    .containsEntry("registrationOpen", true).containsEntry("canPay", true).containsEntry("canRegister", false);
            assertThat((List<?>) mine.get("reasons")).isEmpty();
            assertThat(mine.get("paid")).isNull();
            assertThat((Map<String, Object>) mine.get("course")).containsEntry("code", siwesCode).containsEntry("units", 6);
            assertThat((Map<String, Object>) mine.get("fee")).containsEntry("state", "PUBLISHED");
            assertThat(money(((Map<String, Object>) mine.get("fee")).get("amount"))).as("the fee in force, not the draft").isEqualByComparingTo("4000");
            assertThat((Map<String, Object>) mine.get("period")).containsEntry("state", "OPEN").containsEntry("durationMonths", 6)
                    .containsEntry("trainingStarts", trainingStarts.toString()).containsEntry("trainingEnds", trainingEnds.toString())
                    .containsEntry("registrationCloses", today.plusDays(10).toString());

            // ── (2) the Second Semester offers the SIWES course alone, at its units; the ordinary page sends the student to the SIWES page ──
            Map<String, Object> view = it.get(student(A), "/api/v1/me/registration?session=" + session + "&semester=2").getBody();
            assertThat(codes((List<Map<String, Object>>) view.get("menu"), "course_code")).containsExactly(siwesCode);
            assertThat((Map<String, Object>) view.get("limit")).containsEntry("min_units", 6).containsEntry("max_units", 6).containsEntry("basis", "SIWES");
            assertThat((Map<String, Object>) view.get("window")).containsEntry("siwes", true).containsEntry("open", false);

            // ── (5) no ordinary course on the student's own door ──
            ResponseEntity<Map> ordinary = it.call(student(A), HttpMethod.PUT, "/api/v1/me/registration", Map.of("session", session, "semester", 2, "offerings", List.of(electiveOff)));
            assertThat(status(ordinary)).isEqualTo(422);
            assertThat(String.valueOf(ordinary.getBody().get("detail"))).contains("SIWES page");
            // ── (6) nor through an office's API: the ordinary course refused, the SIWES course refused until paid; nothing written ──
            ResponseEntity<Map> office = it.call(academic, HttpMethod.POST, "/api/v1/registration/course-registrations", Map.of("studentId", A, "session", session,
                    "semester", 2, "level", 300, "entries", List.of(Map.of("offeringId", electiveOff, "units", 3))));
            assertThat(status(office)).as(String.valueOf(office.getBody())).isEqualTo(422);
            assertThat(code(office)).isEqualTo("SIWES_COURSE_ONLY");
            ResponseEntity<Map> unpaidByOffice = it.call(academic, HttpMethod.POST, "/api/v1/registration/course-registrations", Map.of("studentId", A, "session", session,
                    "semester", 2, "level", 300, "entries", List.of(Map.of("offeringId", siwesOff, "units", 6))));
            assertThat(code(unpaidByOffice)).isEqualTo("SIWES_UNPAID");
            assertThat(jdbc.sql("SELECT count(*) FROM registration.course_registration WHERE student_id = :s AND session = :ss AND semester = 2")
                    .param("s", A).param("ss", session).query(Integer.class).single()).isZero();

            // ── (10) the first semester is the student's own as ever ──
            ResponseEntity<Map> firstSaved = it.call(student(A), HttpMethod.PUT, "/api/v1/me/registration", Map.of("session", session, "semester", 1, "offerings", List.of(firstOff)));
            assertThat(status(firstSaved)).as(String.valueOf(firstSaved.getBody())).isEqualTo(200);
            String firstBefore = jdbc.sql("""
                    SELECT string_agg(o.course_code || ':' || e.status || ':' || e.units, ',' ORDER BY o.course_code) FROM registration.entry e
                      JOIN registration.course_registration r ON r.id = e.registration_id JOIN catalogue.offering o ON o.id = e.offering_id
                     WHERE r.student_id = :s AND r.session = :ss AND r.semester = 1
                    """).param("s", A).param("ss", session).query(String.class).single();
            assertThat(firstBefore).isEqualTo(first + ":REGISTERED:3");

            // ── (3) the ₦4,000: registering first is refused (not paid); the reference drawn once, at the server's amount, never a school fee ──
            ResponseEntity<Map> early = it.call(student(A), HttpMethod.POST, "/api/v1/me/siwes/register", Map.of());
            assertThat(status(early)).isEqualTo(422);
            assertThat(code(early)).isEqualTo("SIWES_UNPAID");
            ResponseEntity<Map> drawn = it.call(student(A), HttpMethod.POST, "/api/v1/me/siwes/reference", Map.of());
            assertThat(status(drawn)).as(String.valueOf(drawn.getBody())).isEqualTo(200);
            String ref1 = String.valueOf(drawn.getBody().get("reference"));
            assertThat(money(drawn.getBody().get("amount"))).isEqualByComparingTo("4000");
            assertThat(drawn.getBody()).containsEntry("purpose", "SIWES registration fee " + session);
            assertThat(it.call(student(A), HttpMethod.POST, "/api/v1/me/siwes/reference", Map.of()).getBody()).containsEntry("reference", ref1);
            assertThat(jdbc.sql("SELECT count(*) FROM finance.payment_reference WHERE student_id = :s AND purpose LIKE 'SIWES registration fee%'").param("s", A)
                    .query(Integer.class).single()).isEqualTo(1);
            assertThat(jdbc.sql("SELECT finance.categorise(NULL, :p)").param("p", "SIWES registration fee " + session).query(String.class).single()).isEqualTo("SIWES");
            assertThat(String.valueOf(((Map<String, Object>) it.get(student(A), "/api/v1/me/siwes").getBody().get("openReference")).get("reference"))).isEqualTo(ref1);

            // the gateways: the checkout hands it to WebPAY's start page, which names the SIWES registration fee at the server's amount;
            // PayDirect's validation answers it with its amount
            ResponseEntity<Map> key = it.call(ict, HttpMethod.PUT, "/api/v1/payments/gateways/quickteller/key", Map.of("secret",
                    "{\"productId\":\"6498\",\"payItemId\":\"101\",\"macKey\":\"0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF\",\"sandbox\":true}"));
            assertThat(status(key)).as(String.valueOf(key.getBody())).isEqualTo(200);
            keySet = true;
            ResponseEntity<Map> checkout = it.call(student(A), HttpMethod.POST, "/api/v1/payments/checkout", Map.of("reference", ref1, "gateway", "quickteller"));
            assertThat(status(checkout)).as(String.valueOf(checkout.getBody())).isEqualTo(200);
            assertThat(String.valueOf(checkout.getBody().get("url"))).contains("/api/v1/payments/quickteller/start?reference=" + ref1);
            String startPage = open.get().uri("/api/v1/payments/quickteller/start?reference=" + ref1).retrieve().body(String.class);
            assertThat(startPage).contains("SIWES registration fee").contains("name=\"amount\" value=\"400000\"");
            assertThat(postXml("/api/v1/payments/paydirect/validate", "<CustomerInformationRequest><CustReference>" + ref1 + "</CustReference></CustomerInformationRequest>"))
                    .contains("<Status>0</Status>").contains("<Amount>4000.00</Amount>");

            // a reference left to expire (taken to a bank, say) and a new one drawn: the student pays the new one by card
            it.db(() -> jdbc.sql("UPDATE finance.payment_reference SET expires_at = now() - interval '1 minute' WHERE reference = :r").param("r", ref1).update());
            String ref2 = String.valueOf(it.call(student(A), HttpMethod.POST, "/api/v1/me/siwes/reference", Map.of()).getBody().get("reference"));
            assertThat(ref2).isNotEqualTo(ref1);
            assertThat(confirm(ref2)).isNotEqualTo("already confirmed");
            Map<String, Object> paid = it.get(student(A), "/api/v1/me/siwes").getBody();
            assertThat((Map<String, Object>) paid.get("paid")).containsEntry("reference", ref2).containsEntry("source", "PORTAL");
            assertThat(((Map<String, Object>) paid.get("paid")).get("receiptNo")).isNotNull();
            assertThat(paid).containsEntry("canPay", false).containsEntry("canRegister", true);
            // K10: A's Second Semester school fees are paid, by the test registering applies
            assertThat((Map<String, Object>) paid.get("semesterFees")).containsEntry("cleared", true).containsEntry("stated", true);
            assertThat(((Map<String, Object>) paid.get("semesterFees")).get("outstanding")).isNull();
            // paying registers nothing: the student registers
            assertThat(jdbc.sql("SELECT count(*) FROM registration.course_registration WHERE student_id = :s AND session = :ss AND semester = 2")
                    .param("s", A).param("ss", session).query(Integer.class).single()).isZero();
            // WebPAY's return comes back to the SIWES page
            String returned = open.post().uri("/api/v1/payments/quickteller/return?reference=" + ref2).contentType(MediaType.APPLICATION_FORM_URLENCODED)
                    .body("txnref=" + ref2 + "&resp=00&desc=Approved").retrieve().body(String.class);
            assertThat(returned).contains("/student/siwes?paid=" + ref2).contains("SIWES registration fee");

            // ── (7) never paid twice: no new reference, the paid one not taken to a gateway, a late bank payment of the first held as a credit ──
            ResponseEntity<Map> twice = it.call(student(A), HttpMethod.POST, "/api/v1/me/siwes/reference", Map.of());
            assertThat(status(twice)).isEqualTo(422);
            assertThat(code(twice)).isEqualTo("SIWES_PAID");
            assertThat(code(it.call(student(A), HttpMethod.POST, "/api/v1/payments/checkout", Map.of("reference", ref2, "gateway", "quickteller")))).isEqualTo("PAY_ALREADY_CONFIRMED");
            assertThat(confirm(ref2)).isEqualTo("already confirmed");
            confirm(ref1);
            // K6': the credit as the screens read it — who, why it arose, and what the Bursar may do (the database's own tests)
            Map<String, Object> credit = creditOf(bursar, session, ref1);
            assertThat(credit).as(String.valueOf(credit)).containsEntry("state", "OPEN").containsEntry("studentId", A.toString()).containsEntry("matric", matric.get("A"))
                    .containsEntry("session", session).containsEntry("automatic", false).containsEntry("settles", false)
                    .containsEntry("canRefund", true).containsEntry("canReopen", false).doesNotContainKeys("student_id", "settled_note", "can_refund");
            assertThat(String.valueOf(credit.get("student"))).startsWith("ZZSIWESA" + n);
            assertThat(String.valueOf(credit.get("reason"))).as("why the credit arose: the payment that settled the fee").contains(ref2);
            assertThat(credit.get("note")).as("no settlement yet").isNull();
            // K19: open, settled by nothing yet; no bank check waits on a portal payment
            assertThat(List.of("settledKind", "bankCheck", "bankCheckState")).allSatisfy(k -> assertThat(credit.get(k)).as(k).isNull());
            assertThat(money(credit.get("amount"))).isEqualByComparingTo("4000");
            assertThat(credit.get("paidAt")).as("when the credit's payment was confirmed").isNotNull();
            String creditPath = "/api/v1/finance/siwes/credits/" + credit.get("id");
            assertThat(status(it.call(accounts, HttpMethod.POST, creditPath + "/settle",
                    Map.of("state", "REFUNDED", "note", "Refunded to the student's account")))).isEqualTo(403);
            // K3: a SIWES credit is the whole of its payment, so it is applied by moving the payment, never by hand
            ResponseEntity<Map> appliedByHand = it.call(bursar, HttpMethod.POST, creditPath + "/settle", Map.of("state", "APPLIED", "note", "Applied to the student's school fees"));
            assertThat(status(appliedByHand)).isEqualTo(422);
            assertThat(code(appliedByHand)).isEqualTo("SIWES_CREDIT_MOVE_IT");
            ResponseEntity<Map> settled = it.call(bursar, HttpMethod.POST, creditPath + "/settle",
                    Map.of("state", "REFUNDED", "note", "Refunded to the student's account"));
            assertThat(status(settled)).as(String.valueOf(settled.getBody())).isEqualTo(200);
            assertThat(settled.getBody()).containsEntry("state", "REFUNDED");
            assertThat(String.valueOf(((Map<String, Object>) it.get(student(A), "/api/v1/me/siwes").getBody().get("paid")).get("reference"))).isEqualTo(ref2);
            // K3: settled by hand in error, it is reopened by the Bursar alone, with a reason of ten characters or more; then refunded again
            assertThat(status(it.call(accounts, HttpMethod.POST, creditPath + "/reopen", Map.of("reason", "Recorded as refunded in error")))).isEqualTo(403);
            assertThat(status(it.call(bursar, HttpMethod.POST, creditPath + "/reopen", Map.of("reason", "in error")))).isEqualTo(400);
            ResponseEntity<Map> reopened = it.call(bursar, HttpMethod.POST, creditPath + "/reopen", Map.of("reason", "Recorded as refunded in error"));
            assertThat(status(reopened)).as(String.valueOf(reopened.getBody())).isEqualTo(200);
            assertThat(reopened.getBody()).containsEntry("state", "OPEN");
            ResponseEntity<Map> reopenedTwice = it.call(bursar, HttpMethod.POST, creditPath + "/reopen", Map.of("reason", "Recorded as refunded in error"));
            assertThat(status(reopenedTwice)).isEqualTo(422);
            assertThat(code(reopenedTwice)).isEqualTo("SIWES_CREDIT_NOT_REOPENED");
            assertThat(status(it.call(bursar, HttpMethod.POST, creditPath + "/settle", Map.of("state", "REFUNDED", "note", "Refunded to the student's account")))).isEqualTo(200);
            Map<String, Object> creditRefunded = creditOf(bursar, session, ref1);
            assertThat(creditRefunded).as(String.valueOf(creditRefunded)).containsEntry("state", "REFUNDED").containsEntry("note", "Refunded to the student's account")
                    .containsEntry("automatic", false).containsEntry("canRefund", false).containsEntry("canReopen", true).containsEntry("settledKind", "HAND_REFUND");
            assertThat(creditRefunded.get("settledAt")).isNotNull();
            // [0.0] one payment never given back twice — the credit recorded refunded first: the refund desk raises nothing on that payment
            ResponseEntity<Map> deskAfterCredit = it.call(maker, HttpMethod.POST, "/api/v1/finance/refunds", Map.of("student", A, "payer", "ZZSIWESA" + n + ", Invented",
                    "reason", "SiwesRegistrationIT: the late bank payment given back", "amount", 4000, "source", ref1));
            assertThat(status(deskAfterCredit)).as(String.valueOf(deskAfterCredit.getBody())).isEqualTo(422);
            assertThat(code(deskAfterCredit)).isEqualTo("REFUND_SIWES_CREDIT_SETTLED");
            // a programme with a student paid stays in the session
            assertThat(code(it.call(academic, HttpMethod.DELETE, admin + "/programmes?session=" + session + "&programmeCode=" + P, null))).isEqualTo("SIWES_PROGRAMME_IN_USE");

            // ── (4) registered after the payment is verified: approved as it is made, once; the history carries it ──
            ResponseEntity<Map> reg = it.call(student(A), HttpMethod.POST, "/api/v1/me/siwes/register", Map.of());
            assertThat(status(reg)).as(String.valueOf(reg.getBody())).isEqualTo(200);
            assertThat(reg.getBody()).containsEntry("status", "APPROVED").containsEntry("courseCode", siwesCode).containsEntry("semester", 2).containsEntry("level", 300);
            ResponseEntity<Map> again = it.call(student(A), HttpMethod.POST, "/api/v1/me/siwes/register", Map.of());
            assertThat(status(again)).isEqualTo(200);
            assertThat(again.getBody().get("registrationId")).isEqualTo(reg.getBody().get("registrationId"));
            assertThat(again.getBody().get("siwesRegistrationId")).isEqualTo(reg.getBody().get("siwesRegistrationId"));
            Map<String, Object> made = jdbc.sql("""
                    SELECT r.status, r.approval_mode, r.level, count(e.*) AS entries, string_agg(o.course_code || ':' || e.status || ':' || e.units, ',') AS courses
                      FROM registration.course_registration r JOIN registration.entry e ON e.registration_id = r.id JOIN catalogue.offering o ON o.id = e.offering_id
                     WHERE r.student_id = :s AND r.session = :ss AND r.semester = 2 GROUP BY r.id
                    """).param("s", A).param("ss", session).query().singleRow();
            assertThat(made).containsEntry("status", "APPROVED").containsEntry("approval_mode", "AUTO").containsEntry("level", 300).containsEntry("entries", 1L)
                    .containsEntry("courses", siwesCode + ":APPROVED:6");
            assertThat((Map<String, Object>) it.get(student(A), "/api/v1/me/siwes").getBody().get("registration")).containsEntry("status", "APPROVED");
            Map<String, Object> siwesRow = ((List<Map<String, Object>>) it.get(student(A), "/api/v1/me/registration-history").getBody().get("history")).stream()
                    .filter(h -> session.equals(h.get("session")) && Integer.valueOf(2).equals(h.get("semester"))).findFirst().orElseThrow();
            assertThat(siwesRow).containsEntry("siwes", true).containsEntry("status", "APPROVED");
            assertThat(codes((List<Map<String, Object>>) siwesRow.get("entries"), "courseCode")).containsExactly(siwesCode);
            // (10) the first semester untouched by all of it, and still the student's to change
            assertThat(jdbc.sql("""
                    SELECT string_agg(o.course_code || ':' || e.status || ':' || e.units, ',' ORDER BY o.course_code) FROM registration.entry e
                      JOIN registration.course_registration r ON r.id = e.registration_id JOIN catalogue.offering o ON o.id = e.offering_id
                     WHERE r.student_id = :s AND r.session = :ss AND r.semester = 1
                    """).param("s", A).param("ss", session).query(String.class).single()).isEqualTo(firstBefore);
            assertThat(status(it.call(student(A), HttpMethod.PUT, "/api/v1/me/registration", Map.of("session", session, "semester", 1, "offerings", List.of(firstOff))))).isEqualTo(200);
            // (5) the approved SIWES registration takes nothing else on the student's own door (the gate sends the semester to the SIWES page)
            ResponseEntity<Map> afterwards = it.call(student(A), HttpMethod.PUT, "/api/v1/me/registration", Map.of("session", session, "semester", 2, "offerings", List.of(siwesOff, electiveOff)));
            assertThat(status(afterwards)).isEqualTo(422);
            assertThat(code(afterwards)).isEqualTo("COURSE_REGISTRATION_CLOSED");
            // (6) nor by an office adding to it: the Academic Office's Student edit (ICT Support's engine) refuses the SIWES rule, which no
            // override sets aside (REG_RULE, the engine's refusal, in the SIWES rule's words) ...
            String editPath = "/api/v1/student/students/" + A + "/edit/registration/add";
            ResponseEntity<Map> edited = it.call(academic, HttpMethod.POST, editPath, Map.of("session", session, "semester", 2, "offering", electiveOff,
                    "reason", "The department asked for the elective on the student's registration"));
            assertThat(status(edited)).as(String.valueOf(edited.getBody())).isEqualTo(422);
            assertThat(code(edited)).isEqualTo("REG_RULE");
            assertThat(String.valueOf(edited.getBody().get("detail"))).contains("SIWES (industrial training) semester");
            ResponseEntity<Map> overridden = it.call(academic, HttpMethod.POST, editPath, Map.of("session", session, "semester", 2, "offering", electiveOff,
                    "reason", "The department asked for the elective on the student's registration", "override", true,
                    "description", "The portal holds the semester to the SIWES course and the department disagrees"));
            assertThat(status(overridden)).as(String.valueOf(overridden.getBody())).isEqualTo(422);
            assertThat(code(overridden)).isEqualTo("REG_RULE");
            // (the old portal's registration upload into it, at (11) below, is refused by the database's own word)

            // ── school fees are still owed: B's SIWES fee paid on the old portal counts, but the Second Semester's school fees are not paid ──
            oldPortalSiwes(B, session, String.valueOf(n) + "B");
            Map<String, Object> mineB = it.get(student(B), "/api/v1/me/siwes").getBody();
            assertThat((Map<String, Object>) mineB.get("paid")).containsEntry("source", "OLD_PORTAL");
            // K10: the page says so before B tries — the Second Semester school fees not cleared (what is left owed), so no registering yet
            Map<String, Object> feesB = (Map<String, Object>) mineB.get("semesterFees");
            assertThat(feesB).as(String.valueOf(mineB)).containsEntry("cleared", false).containsEntry("stated", true);
            assertThat(money(feesB.get("outstanding"))).isPositive();
            assertThat(mineB).containsEntry("eligible", true).containsEntry("canRegister", false);
            ResponseEntity<Map> regB = it.call(student(B), HttpMethod.POST, "/api/v1/me/siwes/register", Map.of());
            assertThat(status(regB)).as(String.valueOf(regB.getBody())).isEqualTo(422);
            assertThat(code(regB)).isEqualTo("REG_SEMESTER_FEES_DUE");
            assertThat(jdbc.sql("SELECT count(*) FROM registration.siwes_registration WHERE student_id = :s").param("s", B).query(Integer.class).single()).isZero();

            // ── a stale reference is never paid: K draws one, then the old portal's payment of the session is found ──
            String refK = String.valueOf(it.call(student(K), HttpMethod.POST, "/api/v1/me/siwes/reference", Map.of()).getBody().get("reference"));
            oldPortalSiwes(K, session, String.valueOf(n) + "K");
            ResponseEntity<Map> staleCheckout = it.call(student(K), HttpMethod.POST, "/api/v1/payments/checkout", Map.of("reference", refK, "gateway", "quickteller"));
            assertThat(status(staleCheckout)).isEqualTo(422);
            assertThat(code(staleCheckout)).isEqualTo("SIWES_REFERENCE_STALE");
            assertThat(open.get().uri("/api/v1/payments/quickteller/start?reference=" + refK).retrieve().body(String.class)).contains("can no longer be paid");
            assertThat(postXml("/api/v1/payments/paydirect/validate", "<CustomerInformationRequest><CustReference>" + refK + "</CustReference></CustomerInformationRequest>"))
                    .contains("<Status>1</Status>");
            // G draws and has not paid: payable at the bank
            String refG = String.valueOf(it.call(student(G), HttpMethod.POST, "/api/v1/me/siwes/reference", Map.of()).getBody().get("reference"));
            assertThat(postXml("/api/v1/payments/paydirect/validate", "<CustomerInformationRequest><CustReference>" + refG + "</CustReference></CustomerInformationRequest>"))
                    .contains("<Status>0</Status>");

            // ── (8) a programme not configured is not restricted: C keeps V503's attachment semester and registers as before ──
            Map<String, Object> mineC = it.get(student(C), "/api/v1/me/siwes").getBody();
            assertThat((List<String>) mineC.get("reasons")).contains("NOT_CONFIGURED");
            assertThat(mineC).containsEntry("applies", false);
            assertThat(it.get(student(C), "/api/v1/me").getBody()).containsEntry("siwesArea", false);
            Map<String, Object> viewC = it.get(student(C), "/api/v1/me/registration?session=" + session + "&semester=2").getBody();
            assertThat(viewC).containsEntry("siwes", true);
            assertThat((Map<String, Object>) viewC.get("limit")).containsEntry("min_units", 6).containsEntry("max_units", 6);
            assertThat((Map<String, Object>) viewC.get("window")).containsEntry("siwes", false).containsEntry("open", true);
            assertThat(codes((List<Map<String, Object>>) viewC.get("menu"), "course_code")).contains(v503, elective);
            ResponseEntity<Map> savedC = it.call(student(C), HttpMethod.PUT, "/api/v1/me/registration", Map.of("session", session, "semester", 2, "offerings", List.of(electiveOff)));
            assertThat(status(savedC)).as(String.valueOf(savedC.getBody())).isEqualTo(200);

            // ── (9) a postgraduate is not subject; (14) another level of the configured programme is unchanged ──
            Map<String, Object> mineD = it.get(student(D), "/api/v1/me/siwes?session=" + session).getBody();
            assertThat((List<String>) mineD.get("reasons")).contains("NOT_UNDERGRADUATE");
            assertThat(mineD).containsEntry("applies", false);
            ResponseEntity<Map> pgReg = it.call(academic, HttpMethod.POST, "/api/v1/registration/course-registrations", Map.of("studentId", D, "session", session,
                    "semester", 2, "level", 700, "entries", List.of(Map.of("offeringId", offering(pgCourse, session, 2), "units", 3))));
            assertThat(status(pgReg)).as(String.valueOf(pgReg.getBody())).isEqualTo(200);
            Map<String, Object> mineF = it.get(student(F), "/api/v1/me/siwes").getBody();
            assertThat((List<String>) mineF.get("reasons")).contains("NOT_300_LEVEL");
            assertThat(mineF).containsEntry("applies", false);
            assertThat(it.get(student(F), "/api/v1/me").getBody()).containsEntry("siwesArea", false);
            ResponseEntity<Map> otherLevel = it.call(academic, HttpMethod.POST, "/api/v1/registration/course-registrations", Map.of("studentId", F, "session", session,
                    "semester", 2, "level", 200, "entries", List.of(Map.of("offeringId", electiveOff, "units", 3))));
            assertThat(status(otherLevel)).as(String.valueOf(otherLevel.getBody())).isEqualTo(200);

            // ── (11) history intact: the old portal's registration of a past semester SIWES binds is loaded; in the current session it is refused ──
            Map<String, Object> pastPeriod = new HashMap<>();
            pastPeriod.put("session", before);
            pastPeriod.put("state", "CLOSED");
            pastPeriod.put("durationMonths", 6);
            // set by a person of the Academic Office: the desk names who last set the period (s4-7), never their id
            String academicPerson = TestTokens.token(it.person("ZZ-SIWES-ACA-752", "ZZSIWESACA"), List.of("academic"));
            assertThat(status(it.call(academicPerson, HttpMethod.PUT, admin + "/period", pastPeriod))).isEqualTo(200);
            Map<String, Object> pastConfig = (Map<String, Object>) it.get(academic, admin + "/config?session=" + before).getBody().get("period");
            assertThat(pastConfig).as(String.valueOf(pastConfig)).containsEntry("setOffice", "academic").doesNotContainKey("setBy");
            assertThat(String.valueOf(pastConfig.get("setByName"))).startsWith("ZZSIWESACA");
            assertThat(status(it.call(academic, HttpMethod.POST, admin + "/programmes", Map.of("session", before, "programmeCode", P)))).isEqualTo(200);
            ResponseEntity<Map> history = it.call(ict, HttpMethod.POST, "/api/v1/results/legacy/registration", Map.of("session", before, "semester", 2,
                    "rows", List.of(Map.of("line", "2", "matric", matric.get("B"), "course", elective, "level", "300"))));
            assertThat(status(history)).as(String.valueOf(history.getBody())).isEqualTo(200);
            assertThat(((Number) history.getBody().get("entries")).intValue()).isEqualTo(1);
            assertThat(jdbc.sql("SELECT registration.siwes_applies(:s, :ses)").param("s", B).param("ses", before).query(Boolean.class).single())
                    .as("SIWES binds that past semester, and its history loaded all the same").isTrue();
            // (6) the upload is an office's path into a registration that stands, too: A's approved SIWES registration takes nothing else
            ResponseEntity<Map> current = it.call(ict, HttpMethod.POST, "/api/v1/results/legacy/registration", Map.of("session", session, "semester", 2,
                    "rows", List.of(Map.of("line", "2", "matric", matric.get("G"), "course", elective, "level", "300"),
                                    Map.of("line", "3", "matric", matric.get("A"), "course", elective, "level", "300"))));
            assertThat(status(current)).as(String.valueOf(current.getBody())).isEqualTo(200);
            assertThat(((Number) current.getBody().get("entries")).intValue()).isZero();
            for (String line : List.of("2", "3")) {
                assertThat((List<Map<String, Object>>) current.getBody().get("lines")).anySatisfy(l -> {
                    assertThat(String.valueOf(l.get("line"))).isEqualTo(line);
                    assertThat(l).containsEntry("status", "REFUSED");
                    assertThat(String.valueOf(l.get("detail"))).contains("SIWES_COURSE_ONLY");
                });
            }
            assertThat(jdbc.sql("""
                    SELECT string_agg(o.course_code || ':' || e.status, ',' ORDER BY o.course_code) FROM registration.entry e
                      JOIN registration.course_registration r ON r.id = e.registration_id JOIN catalogue.offering o ON o.id = e.offering_id
                     WHERE r.student_id = :s AND r.session = :ss AND r.semester = 2
                    """).param("s", A).param("ss", session).query(String.class).single()).as("A's registration holds the SIWES course alone").isEqualTo(siwesCode + ":APPROVED");

            // ── K5, K9, K11, K12: what H's draft held before SIWES bound P — an ordinary course, a carry-over and a deferred course — waits
            //    for a later semester: ICT Support drops the ordinary course with no override, H drops the carry-over on the student's own
            //    door and a reset clears the deferred course; then H registers the SIWES course ──
            oldPortalSiwes(H, session, String.valueOf(n) + "H");
            Map<String, Object> mineH = it.get(student(H), "/api/v1/me/siwes").getBody();
            assertThat(mineH).containsEntry("applies", true);
            assertThat((List<String>) mineH.get("otherCourses")).containsExactlyInAnyOrder(elective, carry, deferred);
            ResponseEntity<Map> heldH = it.call(student(H), HttpMethod.POST, "/api/v1/me/siwes/register", Map.of());
            assertThat(status(heldH)).isEqualTo(422);
            assertThat(code(heldH)).isEqualTo("SIWES_OTHER_COURSES");
            // the Second Semester open on the calendar with its add/drop period over (it closed yesterday; the SIWES window, the Academic
            // Office's own dates, runs on), and students reset their own registration this semester
            it.db(() -> {
                jdbc.sql("""
                        INSERT INTO policy.semester (id, session, number, state, registration_closes) VALUES (gen_random_uuid(), :s, 2, 'OPEN', current_date - 1)
                        ON CONFLICT (session, number) DO UPDATE SET state = 'OPEN', registration_closes = current_date - 1, late_registration_closes = NULL
                        """).param("s", session).update();
                jdbc.sql("""
                        INSERT INTO registration.approval_policy (session, semester, mode, allow_student_reset, card_on_approval, reason)
                        SELECT :s, 2, p.mode, true, p.card_on_approval, 'SiwesRegistrationIT: students reset their own registration'
                          FROM registration.approval_policy p WHERE p.session IS NULL
                        """).param("s", session).update();
                return null;
            });
            // K11: the page offers the reset as the reset door judges it (reset_refusal alone, past the gate's SIWES words), while the
            // student's Remove waits for add/drop
            Map<String, Object> viewH = it.get(student(H), "/api/v1/me/registration?session=" + session + "&semester=2").getBody();
            assertThat((Map<String, Object>) viewH.get("window")).containsEntry("siwes", true).containsEntry("open", false);
            assertThat((Map<String, Object>) viewH.get("reset")).as(String.valueOf(viewH.get("reset"))).containsEntry("allowed", true);
            assertThat(((Map<String, Object>) viewH.get("reset")).get("why")).isNull();
            assertThat(viewH).containsEntry("addDropOpen", false);
            // s4-5: the SIWES page reads the same of the courses in the way (clearing): no Remove while add and drop is closed, the reset
            Map<String, Object> clearingH = (Map<String, Object>) it.get(student(H), "/api/v1/me/siwes").getBody().get("clearing");
            assertThat(clearingH).as(String.valueOf(clearingH)).containsEntry("addDropOpen", false).containsEntry("resetAllowed", true);
            ResponseEntity<Map> dropClosedH = it.call(student(H), HttpMethod.POST, "/api/v1/me/registration/drop", Map.of("session", session, "semester", 2, "offering", electiveOff));
            assertThat(status(dropClosedH)).isEqualTo(422);
            assertThat(String.valueOf(dropClosedH.getBody().get("detail"))).contains("add and drop is not open");
            // the add/drop period open again (the database's own word on a drop)
            it.db(() -> jdbc.sql("UPDATE policy.semester SET registration_closes = NULL WHERE session = :s AND number = 2").param("s", session).update());
            assertThat(it.get(student(H), "/api/v1/me/registration?session=" + session + "&semester=2").getBody()).containsEntry("addDropOpen", true);
            assertThat((Map<String, Object>) it.get(student(H), "/api/v1/me/siwes").getBody().get("clearing")).containsEntry("addDropOpen", true);
            // adding stays refused: the semester is registered on the SIWES page
            ResponseEntity<Map> addedH = it.call(student(H), HttpMethod.POST, "/api/v1/me/registration/add", Map.of("session", session, "semester", 2, "offering", electiveOff));
            assertThat(status(addedH)).isEqualTo(422);
            assertThat(code(addedH)).isEqualTo("COURSE_REGISTRATION_CLOSED");
            // K12: ICT Support drops the ordinary course in the SIWES course's way with no override — the registration window passes, in
            // the words the checks dialog shows, as the support override is kept for the SIWES course itself
            String supportPath = "/api/v1/helpdesk/support/students/" + H + "/registration";
            // the Director of ICT at the desk, a person on the register (the desk's act is recorded against them)
            String ictDesk = TestTokens.token(it.person("ZZ-SIWES-ICT-752", "ZZSIWESICT"), List.of("ict"));
            Map<String, Object> checksH = it.get(ictDesk, supportPath + "/checks?session=" + session + "&semester=2&offering=" + electiveOff + "&verb=drop").getBody();
            assertThat(checksH).as(String.valueOf(checksH)).containsEntry("allowed", true).containsEntry("overridable", false);
            assertThat((List<Map<String, Object>>) checksH.get("rules")).anySatisfy(r -> assertThat(r).containsEntry("rule", "REGISTRATION_WINDOW").containsEntry("passed", true)
                    .containsEntry("message", elective + " waits for a later semester: the SIWES semester holds the SIWES course alone."));
            ResponseEntity<Map> supportDropH = it.call(ictDesk, HttpMethod.POST, supportPath + "/drop", Map.of("session", session, "semester", 2, "offering", electiveOff,
                    "reason", "The elective stands in the way of the student's SIWES course"));
            assertThat(status(supportDropH)).as(String.valueOf(supportDropH.getBody())).isEqualTo(200);
            assertThat(supportDropH.getBody().get("overridden")).isNotEqualTo(true);
            assertThat(jdbc.sql("""
                    SELECT e.status FROM registration.entry e JOIN registration.course_registration r ON r.id = e.registration_id
                     WHERE r.student_id = :s AND r.session = :ss AND r.semester = 2 AND e.offering_id = :o
                    """).param("s", H).param("ss", session).param("o", electiveOff).query(String.class).single()).isEqualTo("DROPPED");
            // K9: the carry-over goes on H's own drop door (a carry-over is otherwise never dropped; it must be repeated) ...
            ResponseEntity<Map> droppedCarry = it.call(student(H), HttpMethod.POST, "/api/v1/me/registration/drop", Map.of("session", session, "semester", 2, "offering", carryOff));
            assertThat(status(droppedCarry)).as(String.valueOf(droppedCarry.getBody())).isEqualTo(200);
            // ... the deferred course still holds the semester ...
            ResponseEntity<Map> stillHeldH = it.call(student(H), HttpMethod.POST, "/api/v1/me/siwes/register", Map.of());
            assertThat(status(stillHeldH)).isEqualTo(422);
            assertThat(code(stillHeldH)).isEqualTo("SIWES_OTHER_COURSES");
            assertThat(String.valueOf(stillHeldH.getBody().get("detail"))).contains(deferred).doesNotContain(carry).doesNotContain(elective);
            // ... until H resets the registration (K9: the reset clears carry-overs and deferred courses too, for that semester), the
            // page having offered it (K11)
            assertThat((Map<String, Object>) it.get(student(H), "/api/v1/me/registration?session=" + session + "&semester=2").getBody().get("reset"))
                    .containsEntry("allowed", true);
            ResponseEntity<Map> resetShedH = it.call(student(H), HttpMethod.POST, "/api/v1/me/registration/reset", Map.of("session", session, "semester", 2,
                    "reason", "To register the SIWES course alone"));
            assertThat(status(resetShedH)).as(String.valueOf(resetShedH.getBody())).isEqualTo(200);
            assertThat((Map<String, Object>) resetShedH.getBody().get("result")).containsEntry("reset", true);
            assertThat((List<String>) it.get(student(H), "/api/v1/me/siwes").getBody().get("otherCourses")).isEmpty();
            ResponseEntity<Map> regH = it.call(student(H), HttpMethod.POST, "/api/v1/me/siwes/register", Map.of());
            assertThat(status(regH)).as(String.valueOf(regH.getBody())).isEqualTo(200);
            assertThat(regH.getBody()).containsEntry("status", "APPROVED").containsEntry("courseCode", siwesCode);
            assertThat(jdbc.sql("""
                    SELECT string_agg(o.course_code || ':' || e.status, ',' ORDER BY o.course_code) FROM registration.entry e
                      JOIN registration.course_registration r ON r.id = e.registration_id JOIN catalogue.offering o ON o.id = e.offering_id
                     WHERE r.student_id = :s AND r.session = :ss AND r.semester = 2 AND e.status NOT IN ('DROPPED', 'WITHDRAWN')
                    """).param("s", H).param("ss", session).query(String.class).single()).isEqualTo(siwesCode + ":APPROVED");
            assertThat(it.get(student(H), "/api/v1/me/siwes").getBody()).as("nothing in the way once registered").doesNotContainKey("clearing");
            assertThat(jdbc.sql("SELECT legacy_payment_id IS NOT NULL FROM registration.siwes_registration WHERE student_id = :s AND session = :ss")
                    .param("s", H).param("ss", session).query(Boolean.class).single()).as("registered on the old portal's payment").isTrue();
            // the SIWES course itself is never dropped on the student's door, nor reset away (student resets open for the semester): the
            // page says the reset is refused, in the reset door's own words (K11)
            ResponseEntity<Map> keptH = it.call(student(H), HttpMethod.POST, "/api/v1/me/registration/drop", Map.of("session", session, "semester", 2, "offering", siwesOff));
            assertThat(status(keptH)).isEqualTo(422);
            assertThat(code(keptH)).isEqualTo("SIWES_COURSE_KEPT");
            Map<String, Object> resetRefusedH = (Map<String, Object>) it.get(student(H), "/api/v1/me/registration?session=" + session + "&semester=2").getBody().get("reset");
            assertThat(resetRefusedH).containsEntry("allowed", false);
            assertThat(String.valueOf(resetRefusedH.get("why"))).startsWith("REG_RESET_SIWES");
            ResponseEntity<Map> resetH = it.call(student(H), HttpMethod.POST, "/api/v1/me/registration/reset", Map.of("session", session, "semester", 2, "reason", "To register again"));
            assertThat(status(resetH)).isEqualTo(422);
            assertThat(code(resetH)).isEqualTo("REG_RESET_SIWES");
            it.db(() -> {
                jdbc.sql("DELETE FROM registration.approval_policy WHERE session = :s").param("s", session).update();
                jdbc.sql("DELETE FROM policy.semester WHERE session = :s").param("s", session).update();
                return null;
            });

            // ── [0.1] the mapping paid and registered students need is replaced, never taken away; K7: a registered student keeps the
            //    course the registration was made on, whatever the mapping says since ──
            Map<String, Object> remapping = new HashMap<>();
            remapping.put("programmeCode", P);
            remapping.put("curriculum", null);
            remapping.put("courseCode", null);
            ResponseEntity<Map> cleared = it.call(academic, HttpMethod.PUT, admin + "/courses", remapping);
            assertThat(status(cleared)).as(String.valueOf(cleared.getBody())).isEqualTo(422);
            assertThat(code(cleared)).isEqualTo("SIWES_COURSE_IN_USE");
            remapping.put("courseCode", remap);
            ResponseEntity<Map> replaced = it.call(academic, HttpMethod.PUT, admin + "/courses", remapping);
            assertThat(status(replaced)).as(String.valueOf(replaced.getBody())).isEqualTo(200);
            assertThat((Map<String, Object>) replaced.getBody().get("course")).containsEntry("code", remap);
            Map<String, Object> remappedA = it.get(student(A), "/api/v1/me/siwes").getBody();
            assertThat((Map<String, Object>) remappedA.get("course")).as("today's mapping").containsEntry("code", remap);
            assertThat((Map<String, Object>) remappedA.get("registration")).as("the course registered").containsEntry("courseCode", siwesCode).containsEntry("status", "APPROVED");
            assertThat((List<String>) remappedA.get("otherCourses")).as("the course registered is never in the way").isEmpty();
            assertThat((List<String>) it.get(academic, admin + "/students/" + A + "?session=" + session).getBody().get("otherCourses")).isEmpty();
            // the course registered is still the SIWES course on the student's drop door
            ResponseEntity<Map> keptA = it.call(student(A), HttpMethod.POST, "/api/v1/me/registration/drop", Map.of("session", session, "semester", 2, "offering", siwesOff));
            assertThat(status(keptA)).isEqualTo(422);
            assertThat(code(keptA)).isEqualTo("SIWES_COURSE_KEPT");
            // the replacement is not taken away either; the course put back
            remapping.put("courseCode", null);
            assertThat(code(it.call(academic, HttpMethod.PUT, admin + "/courses", remapping))).isEqualTo("SIWES_COURSE_IN_USE");
            remapping.put("courseCode", siwesCode);
            assertThat(status(it.call(academic, HttpMethod.PUT, admin + "/courses", remapping))).isEqualTo(200);
            assertThat((Map<String, Object>) it.get(student(G), "/api/v1/me/siwes").getBody().get("course")).containsEntry("code", siwesCode);

            // ── (12) the statistics, the lists and the Bursary's reconciliation read the records: A registered (paid on the portal), H
            //    registered (paid on the old portal), B and K paid on the old portal, G yet to pay ──
            Map<String, Object> stats = it.get(academic, admin + "/stats?session=" + session + "&programme=" + P).getBody();
            assertThat(stats).containsEntry("eligible", 5).containsEntry("paid", 4).containsEntry("registered", 2).containsEntry("unpaid", 1).containsEntry("notRegistered", 3);
            assertThat(money(stats.get("amountPaid"))).isEqualByComparingTo("16000");
            assertThat(money(stats.get("amountOutstanding"))).isEqualByComparingTo("4000");
            assertThat((List<Map<String, Object>>) stats.get("byProgramme")).singleElement().satisfies(g -> assertThat(g).containsEntry("code", P).containsEntry("registered", 2));
            Map<String, Object> list = it.get(academic, admin + "/students?session=" + session + "&programme=" + P).getBody();
            assertThat(((Number) list.get("total")).intValue()).isEqualTo(5);
            List<Map<String, Object>> registered = (List<Map<String, Object>>) it.get(academic, admin + "/students?session=" + session + "&programme=" + P + "&status=REGISTERED").getBody().get("rows");
            assertThat(registered).hasSize(2).anySatisfy(r -> assertThat(r).containsEntry("studentId", A.toString()).containsEntry("matricNo", matric.get("A"))
                    .containsEntry("courseCode", siwesCode).containsEntry("paymentReference", ref2).containsEntry("paymentSource", "PORTAL").containsEntry("registered", true));
            assertThat(registered).anySatisfy(r -> assertThat(r).containsEntry("studentId", H.toString()).containsEntry("paymentSource", "OLD_PORTAL"));
            assertThat(codes((List<Map<String, Object>>) it.get(academic, admin + "/students?session=" + session + "&programme=" + P + "&status=UNPAID").getBody().get("rows"), "studentId"))
                    .containsExactly(G.toString());
            assertThat((List<Map<String, Object>>) it.get(academic, admin + "/students?session=" + session + "&programme=" + P + "&status=PAID").getBody().get("rows"))
                    .hasSize(4).anySatisfy(r -> assertThat(r).containsEntry("studentId", B.toString()).containsEntry("paymentSource", "OLD_PORTAL"));
            assertThat(((Number) it.get(academic, admin + "/students?session=" + session + "&q=" + matric.get("A")).getBody().get("total")).intValue()).isEqualTo(1);
            Map<String, Object> detail = it.get(academic, admin + "/students/" + A + "?session=" + session).getBody();
            assertThat(detail).containsEntry("matricNo", matric.get("A"));
            assertThat((List<Map<String, Object>>) detail.get("history")).anySatisfy(h -> {
                assertThat(h).containsEntry("session", session);
                assertThat((Map<String, Object>) h.get("registration")).containsEntry("courseCode", siwesCode);
                assertThat((Map<String, Object>) h.get("paid")).containsEntry("reference", ref2);
            });
            Map<String, Object> payments = it.get(bursar, "/api/v1/finance/siwes/payments?session=" + session + "&programme=" + P).getBody();
            assertThat(((Number) payments.get("total")).intValue()).isEqualTo(5);
            assertThat(money(payments.get("amount"))).isEqualByComparingTo("20000");
            // K4': what settles students' fees (A's ref2, B's, K's and H's), what was given back (A's ref1, its credit refunded by the
            // Bursar) and the money held that settles nothing (none): the three add up to the amount, each payment counted once
            assertThat(money(payments.get("amountSettling"))).isEqualByComparingTo("16000");
            assertThat(money(payments.get("amountRefunded"))).isEqualByComparingTo("4000");
            assertThat(money(payments.get("amountCredits"))).isEqualByComparingTo("0");
            List<Map<String, Object>> payRows = (List<Map<String, Object>>) payments.get("rows");
            assertThat(payRows).anySatisfy(r -> {
                assertThat(r).containsEntry("reference", ref2).containsEntry("settles", true).containsEntry("source", "PORTAL");
                assertThat(money(r.get("refunded"))).isEqualByComparingTo("0");
            });
            assertThat(payRows).anySatisfy(r -> {
                assertThat(r).containsEntry("reference", ref1).containsEntry("settles", false).containsEntry("creditState", "REFUNDED");
                assertThat(money(r.get("refunded"))).isEqualByComparingTo("4000");
            });
            assertThat(payRows.stream().map(r -> String.valueOf(r.get("reference")))).doesNotContainAnyElementsOf(jdbc.sql(
                    "SELECT reference FROM finance.payment_reference WHERE student_id = :s AND purpose LIKE 'School fees%'").param("s", A).query(String.class).list());
            assertThat(((Number) it.get(bursar, "/api/v1/finance/siwes/payments?session=" + session + "&programme=" + P + "&source=OLD_PORTAL").getBody().get("total")).intValue()).isEqualTo(3);
            // the course registration report labels the SIWES registration SIWES, never an ordinary Second Semester course
            List<Map<String, Object>> siwesReport = (List<Map<String, Object>>) it.get(academic, "/api/v1/reports/course-registrations?session=" + session
                    + "&semester=2&prog=" + P + "&category=SIWES").getBody().get("rows");
            assertThat(siwesReport).anySatisfy(r -> assertThat(r).containsEntry("course_code", siwesCode).containsEntry("category", "SIWES").containsEntry("student_id", A.toString()));
            List<Map<String, Object>> ordinaryReport = (List<Map<String, Object>>) it.get(academic, "/api/v1/reports/course-registrations?session=" + session
                    + "&semester=2&prog=" + P + "&category=OTHER_COURSES").getBody().get("rows");
            assertThat(ordinaryReport).noneMatch(r -> A.toString().equals(String.valueOf(r.get("student_id"))));

            // ── access: a department reader is held to its department; a non-reader is refused ──
            String hodOther = it.officer("hod", "department", otherDept);
            assertThat(codes((List<Map<String, Object>>) it.get(hodOther, admin + "/students?session=" + session).getBody().get("rows"), "studentId")).doesNotContain(A.toString());
            assertThat(code(it.get(hodOther, admin + "/students?session=" + session + "&department=" + dept))).isEqualTo("SCOPE_DEPARTMENT");
            assertThat(code(it.get(hodOther, admin + "/students/" + A + "?session=" + session))).isEqualTo("SCOPE_DEPARTMENT");
            assertThat(code(it.get(hodOther, admin + "/stats?session=" + session + "&programme=" + P))).isEqualTo("SCOPE_DEPARTMENT");
            assertThat(codes((List<Map<String, Object>>) it.get(hodOther, admin + "/config?session=" + session).getBody().get("programmes"), "code")).doesNotContain(P);
            String hodOwn = it.officer("hod", "department", dept);
            assertThat(((Number) it.get(hodOwn, admin + "/students?session=" + session + "&programme=" + P).getBody().get("total")).intValue()).isEqualTo(5);
            Map<String, Object> ownConfig = it.get(hodOwn, admin + "/config?session=" + session).getBody();
            assertThat(codes((List<Map<String, Object>>) ownConfig.get("programmes"), "code")).contains(P);
            assertThat((Map<String, Object>) ownConfig.get("access")).containsEntry("set", false);
            // the department's registrations desk labels the SIWES registration, at its units
            List<Map<String, Object>> desk = (List<Map<String, Object>>) (List<?>) it.getList(hodOwn, "/api/v1/registration/course-registrations?session=" + session
                    + "&semester=2&status=ALL").getBody();
            assertThat(desk).anySatisfy(r -> assertThat(r).containsEntry("matric_no", matric.get("A")).containsEntry("siwes", true).containsEntry("range", "6"));
            assertThat(desk).anySatisfy(r -> assertThat(r).containsEntry("matric_no", matric.get("F")).containsEntry("siwes", false));
            // K8: the department's Head never returns it — approved on the SIWES fee, the student could not submit it again
            Object regA = reg.getBody().get("registrationId");
            ResponseEntity<Map> returnedByHead = it.call(hodOwn, HttpMethod.POST, "/api/v1/registration/course-registrations/" + regA + "/return",
                    Map.of("comment", "Add the elective of the semester and submit again"));
            assertThat(status(returnedByHead)).as(String.valueOf(returnedByHead.getBody())).isEqualTo(422);
            assertThat(code(returnedByHead)).isEqualTo("REG_RETURN_SIWES");
            assertThat(jdbc.sql("SELECT status FROM registration.course_registration WHERE id = CAST(:id AS uuid)").param("id", String.valueOf(regA)).query(String.class).single())
                    .isEqualTo("APPROVED");
            // K13: nor does an office submit it again — a standing SIWES registration stays approved, whichever door tries
            ResponseEntity<Map> submittedByOffice = it.call(hodOwn, HttpMethod.POST, "/api/v1/registration/course-registrations/" + regA + "/submit", Map.of());
            assertThat(status(submittedByOffice)).as(String.valueOf(submittedByOffice.getBody())).isEqualTo(422);
            assertThat(code(submittedByOffice)).isEqualTo("REG_STATUS_SIWES");
            assertThat(jdbc.sql("SELECT status || '/' || approval_mode FROM registration.course_registration WHERE id = CAST(:id AS uuid)").param("id", String.valueOf(regA))
                    .query(String.class).single()).isEqualTo("APPROVED/AUTO");
            String coordinator = it.officer("siwes", "department", dept);
            assertThat(codes((List<Map<String, Object>>) it.get(coordinator, admin + "/students?session=" + session).getBody().get("rows"), "studentId")).contains(A.toString());
            // the supervision of the SIWES class: the department's own HOD reads it, another department's may not, by id or otherwise
            UUID siwesClass = UUID.fromString(String.valueOf(jdbc.sql("SELECT offering_id FROM registration.siwes_registration WHERE student_id = :s AND session = :ss")
                    .param("s", A).param("ss", session).query(UUID.class).single()));
            List<Map<String, Object>> supervised = (List<Map<String, Object>>) (List<?>) it.getList(hodOwn, "/api/v1/siwes/offerings/" + siwesClass + "/students").getBody();
            assertThat(codes(supervised, "student_id")).contains(A.toString());
            assertThat(code(it.get(hodOther, "/api/v1/siwes/offerings/" + siwesClass + "/students"))).isEqualTo("SCOPE_DEPARTMENT");
            assertThat(code(it.get(hodOther, "/api/v1/siwes/offerings/" + siwesClass + "/supervisors"))).isEqualTo("SCOPE_DEPARTMENT");
            assertThat(code(it.call(hodOther, HttpMethod.PUT, "/api/v1/siwes/offerings/" + siwesClass + "/students/" + A + "/practical", Map.of("mark", 50)))).isEqualTo("SCOPE_DEPARTMENT");
            // a person holding a reading office acts in it: acting as a lecturer, the desk and the supervision are refused
            String hodLecturer = TestTokens.token(UUID.randomUUID(), List.of("hod", "lecturer"));
            assertThat(status(it.callWith(hodLecturer, HttpMethod.GET, admin + "/students?session=" + session, null, Map.of("X-Active-Office", "lecturer")))).isEqualTo(403);
            assertThat(status(it.callWith(hodLecturer, HttpMethod.GET, "/api/v1/siwes/offerings/" + siwesClass + "/students", null, Map.of("X-Active-Office", "lecturer")))).isEqualTo(403);
            // not readers at all
            assertThat(status(it.get(ItSupport.token("lecturer"), admin + "/students?session=" + session))).isEqualTo(403);
            assertThat(status(it.get(student(A), admin + "/config?session=" + session))).isEqualTo(403);
            assertThat(status(it.get(student(A), "/api/v1/finance/siwes/payments?session=" + session))).isEqualTo(403);
            assertThat(status(it.get(hodOwn, "/api/v1/finance/siwes/payments?session=" + session))).isEqualTo(403);
            assertThat(status(it.get(ItSupport.token("audit"), "/api/v1/finance/siwes/payments?session=" + session))).isEqualTo(200);
            assertThat(status(it.get(bursar, admin + "/students?session=" + session))).isEqualTo(200);
            assertThat(status(it.get(ItSupport.token("academic"), "/api/v1/me/siwes"))).isEqualTo(403);

            // ── afterwards, the money ([0.0], [0.2]): none is refunded under a standing SIWES registration; one payment is never given back
            //    twice, whichever desk comes first; a payment anything was given back on settles nothing; a credit is never refunded while
            //    it settles the fee, nor while its payment is archived for review ──
            ResponseEntity<Map> underRegistration = it.call(maker, HttpMethod.POST, "/api/v1/finance/refunds", Map.of("student", A, "payer", "ZZSIWESA" + n + ", Invented",
                    "reason", "SiwesRegistrationIT: the SIWES fee refunded", "amount", 4000, "source", ref2));
            assertThat(status(underRegistration)).as(String.valueOf(underRegistration.getBody())).isEqualTo(422);
            assertThat(code(underRegistration)).isEqualTo("REFUND_SIWES_REGISTERED");
            // G pays twice: the reference drawn earlier left to expire and paid at the bank after a new one was paid
            it.db(() -> jdbc.sql("UPDATE finance.payment_reference SET expires_at = now() - interval '1 minute' WHERE reference = :r").param("r", refG).update());
            String refG2 = String.valueOf(it.call(student(G), HttpMethod.POST, "/api/v1/me/siwes/reference", Map.of()).getBody().get("reference"));
            assertThat(refG2).isNotEqualTo(refG);
            confirm(refG2);
            confirm(refG);
            Map<String, Object> creditG = creditOf(bursar, session, refG);
            assertThat(creditG).as(String.valueOf(creditG)).containsEntry("state", "OPEN").containsEntry("settles", false).containsEntry("canRefund", true);
            String creditGPath = "/api/v1/finance/siwes/credits/" + creditG.get("id");
            // archived for review, the credit's payment is held: the credit is not listed, nor settled, until the payment is restored
            UUID archiveG = archive(accounts, refG);
            assertThat(creditOf(bursar, session, refG)).isNull();
            ResponseEntity<Map> heldG = it.call(bursar, HttpMethod.POST, creditGPath + "/settle", Map.of("state", "REFUNDED", "note", "Refunded to the student's account"));
            assertThat(status(heldG)).isEqualTo(422);
            assertThat(code(heldG)).isEqualTo("SIWES_CREDIT_HELD");
            restore(accounts, checker, archiveG);
            assertThat(creditOf(bursar, session, refG)).containsEntry("state", "OPEN").containsEntry("canRefund", true);
            // refG2, which settles G's fee, refunded on the refund desk (raised by one officer, approved by another): the open credit
            // settles the fee now, recorded so — listed as settling, never offered to refund or to reopen
            String refundG2 = refund(maker, checker, G, "ZZSIWESG" + n + ", Invented", refG2, 4000, true);
            assertThat(String.valueOf(((Map<String, Object>) it.get(student(G), "/api/v1/me/siwes").getBody().get("paid")).get("reference"))).isEqualTo(refG);
            Map<String, Object> settlingG = creditOf(bursar, session, refG);
            assertThat(settlingG).as(String.valueOf(settlingG)).containsEntry("state", "APPLIED").containsEntry("settles", true).containsEntry("automatic", true)
                    .containsEntry("canRefund", false).containsEntry("canReopen", false).containsEntry("settledKind", "SETTLES");
            assertThat(String.valueOf(settlingG.get("note"))).startsWith("Settles the SIWES fee: " + refG2).contains(refundG2);
            List<Map<String, Object>> rowsG = (List<Map<String, Object>>) it.get(bursar, "/api/v1/finance/siwes/payments?session=" + session + "&programme=" + P + "&size=500")
                    .getBody().get("rows");
            assertThat(rowsG).anySatisfy(r -> {
                assertThat(r).containsEntry("reference", refG2).containsEntry("settles", false);
                assertThat(money(r.get("refunded"))).isEqualByComparingTo("4000");
            });
            assertThat(rowsG).anySatisfy(r -> assertThat(r).containsEntry("reference", refG).containsEntry("settles", true).containsEntry("creditState", "APPLIED"));
            ResponseEntity<Map> settlesG = it.call(bursar, HttpMethod.POST, creditGPath + "/settle", Map.of("state", "REFUNDED", "note", "Refunded to the student's account"));
            assertThat(status(settlesG)).isEqualTo(422);
            assertThat(code(settlesG)).isEqualTo("SIWES_CREDIT_UNKNOWN");
            // K13: the fee is all or nothing, so the refund desk gives a SIWES payment back whole or not at all — ₦1,000 of refG refused,
            // raised now (REFUND_SIWES_PART) or raised before V752 and approved now
            ResponseEntity<Map> partG = it.call(maker, HttpMethod.POST, "/api/v1/finance/refunds", Map.of("student", G, "payer", "ZZSIWESG" + n + ", Invented",
                    "reason", "SiwesRegistrationIT: part of the SIWES payment given back", "amount", 1000, "source", refG));
            assertThat(status(partG)).as(String.valueOf(partG.getBody())).isEqualTo(422);
            assertThat(code(partG)).isEqualTo("REFUND_SIWES_PART");
            UUID partBefore = UUID.randomUUID();
            it.db(() -> jdbc.sql("""
                    INSERT INTO finance.refund (id, reference, student_id, payer, reason, amount, proposed_by, source_reference)
                    VALUES (:id, 'RF-IT752-' || :t, :s, :p, 'SiwesRegistrationIT: a part raised before V752', 1000, gen_random_uuid(), :r)
                    """).param("id", partBefore).param("t", String.valueOf(n) + "G").param("s", G).param("p", "ZZSIWESG" + n + ", Invented").param("r", refG).update());
            ResponseEntity<Map> partApproved = it.call(checker, HttpMethod.POST, "/api/v1/finance/refunds/" + partBefore + "/approve", Map.of());
            assertThat(status(partApproved)).as(String.valueOf(partApproved.getBody())).isEqualTo(422);
            assertThat(code(partApproved)).isEqualTo("REFUND_SIWES_PART");
            assertThat(status(it.call(checker, HttpMethod.POST, "/api/v1/finance/refunds/" + partBefore + "/reject",
                    Map.of("why", "A SIWES payment is refunded whole")))).isEqualTo(200);
            // [0.2] refG given back whole on the refund desk: it settles nothing — G is unpaid, may pay again, and registers nothing on it;
            // its credit is the refund desk's
            refund(maker, checker, G, "ZZSIWESG" + n + ", Invented", refG, 4000, true);
            Map<String, Object> partlyG = it.get(student(G), "/api/v1/me/siwes").getBody();
            assertThat(partlyG.get("paid")).as("nothing of G's stands now").isNull();
            assertThat(partlyG).containsEntry("canPay", true);
            ResponseEntity<Map> regG = it.call(student(G), HttpMethod.POST, "/api/v1/me/siwes/register", Map.of());
            assertThat(status(regG)).isEqualTo(422);
            assertThat(code(regG)).isEqualTo("SIWES_UNPAID");
            assertThat(creditOf(bursar, session, refG)).containsEntry("state", "REFUNDED").containsEntry("automatic", true).containsEntry("canReopen", false);
            // [0.0] the refund desk first: K's stale reference, paid at the bank after the old portal's payment settled K's fee, is a
            // credit; while a refund raised on it waits the Bursar records nothing (the desk gives it back), and its approval settles the
            // credit — never refunded or reopened again by hand
            confirm(refK);
            Map<String, Object> creditK = creditOf(bursar, session, refK);
            assertThat(creditK).as(String.valueOf(creditK)).containsEntry("state", "OPEN").containsEntry("settles", false).containsEntry("canRefund", true);
            String creditKPath = "/api/v1/finance/siwes/credits/" + creditK.get("id");
            String refundK = refund(maker, checker, K, "ZZSIWESK" + n + ", Invented", refK, 4000, false);
            assertThat(creditOf(bursar, session, refK)).containsEntry("state", "OPEN").containsEntry("canRefund", false);
            ResponseEntity<Map> deskFirst = it.call(bursar, HttpMethod.POST, creditKPath + "/settle", Map.of("state", "REFUNDED", "note", "Refunded to the student's account"));
            assertThat(status(deskFirst)).isEqualTo(422);
            assertThat(code(deskFirst)).isEqualTo("SIWES_CREDIT_REFUND_DESK");
            approveRefund(checker, refundK);
            Map<String, Object> creditKDesk = creditOf(bursar, session, refK);
            assertThat(creditKDesk).as(String.valueOf(creditKDesk)).containsEntry("state", "REFUNDED").containsEntry("automatic", true)
                    .containsEntry("canRefund", false).containsEntry("canReopen", false).containsEntry("note", "Refunded on the refund desk: " + refundK)
                    .containsEntry("settledKind", "DESK_REFUND");
            ResponseEntity<Map> refundedTwice = it.call(bursar, HttpMethod.POST, creditKPath + "/settle", Map.of("state", "REFUNDED", "note", "Refunded to the student's account"));
            assertThat(status(refundedTwice)).isEqualTo(422);
            assertThat(code(refundedTwice)).isEqualTo("SIWES_CREDIT_UNKNOWN");
            ResponseEntity<Map> reopenedDesk = it.call(bursar, HttpMethod.POST, creditKPath + "/reopen", Map.of("reason", "Recorded as refunded in error"));
            assertThat(status(reopenedDesk)).isEqualTo(422);
            assertThat(code(reopenedDesk)).isEqualTo("SIWES_CREDIT_NOT_REOPENED");
            // K4': every payment counted once — settling (A's ref2; B's, K's and H's old-portal payments) and given back (A's ref1 by the
            // Bursar; refG2, refG and refK on the refund desk, each whole); none held settling nothing
            Map<String, Object> totals = it.get(bursar, "/api/v1/finance/siwes/payments?session=" + session + "&programme=" + P).getBody();
            assertThat(((Number) totals.get("total")).intValue()).isEqualTo(8);
            assertThat(money(totals.get("amount"))).isEqualByComparingTo("32000");
            assertThat(money(totals.get("amountSettling"))).isEqualByComparingTo("16000");
            assertThat(money(totals.get("amountRefunded"))).isEqualByComparingTo("16000");
            assertThat(money(totals.get("amountCredits"))).isEqualByComparingTo("0");
            assertThat((List<Map<String, Object>>) totals.get("rows")).anySatisfy(r -> {
                assertThat(r).containsEntry("reference", refG).containsEntry("settles", false).containsEntry("creditState", "REFUNDED");
                assertThat(money(r.get("refunded"))).isEqualByComparingTo("4000");
            });
            // ── the old fees history started over: the old-portal payment H's SIWES registration stands on is kept; B's and K's go ──
            ResponseEntity<Map> reset = it.call(bursar, HttpMethod.POST, "/api/v1/finance/legacy-fees/reset", Map.of("session", session, "confirm", "RESET"));
            assertThat(status(reset)).as(String.valueOf(reset.getBody())).isEqualTo(200);
            assertThat(((Number) reset.getBody().get("deleted")).intValue()).isEqualTo(2);
            assertThat(((Number) reset.getBody().get("kept_in_use")).intValue()).isEqualTo(1);
            Map<String, Object> mineHAfter = it.get(student(H), "/api/v1/me/siwes").getBody();
            assertThat((Map<String, Object>) mineHAfter.get("paid")).containsEntry("source", "OLD_PORTAL");
            assertThat((Map<String, Object>) mineHAfter.get("registration")).containsEntry("status", "APPROVED");
            assertThat(it.get(student(B), "/api/v1/me/siwes").getBody().get("paid")).isNull();

            // ── [0.3] a credit on an old-portal payment is the Bursar's to refund as any other: B's old-portal payment, imported again, is
            //    archived for review while B pays on the portal, then restored — a credit, refunded by the Bursar; the refund desk and the
            //    archive then hold off it (that money is spent) ──
            oldPortalSiwes(B, session, String.valueOf(n) + "B2");
            String legacyB = "MOAUM-LEG-IT752-" + n + "B2";
            assertThat((Map<String, Object>) it.get(student(B), "/api/v1/me/siwes").getBody().get("paid")).containsEntry("reference", legacyB);
            UUID archiveB = archive(accounts, legacyB);
            assertThat(it.get(student(B), "/api/v1/me/siwes").getBody().get("paid")).isNull();
            String refB = String.valueOf(it.call(student(B), HttpMethod.POST, "/api/v1/me/siwes/reference", Map.of()).getBody().get("reference"));
            confirm(refB);
            restore(accounts, checker, archiveB);
            assertThat(String.valueOf(((Map<String, Object>) it.get(student(B), "/api/v1/me/siwes").getBody().get("paid")).get("reference"))).isEqualTo(refB);
            Map<String, Object> creditB = creditOf(bursar, session, legacyB);
            assertThat(creditB).as(String.valueOf(creditB)).containsEntry("state", "OPEN").containsEntry("settles", false).containsEntry("canRefund", true);
            assertThat(String.valueOf(creditB.get("reason"))).contains(refB);
            ResponseEntity<Map> refundedB = it.call(bursar, HttpMethod.POST, "/api/v1/finance/siwes/credits/" + creditB.get("id") + "/settle",
                    Map.of("state", "REFUNDED", "note", "Refunded to the student's account"));
            assertThat(status(refundedB)).as(String.valueOf(refundedB.getBody())).isEqualTo(200);
            assertThat(creditOf(bursar, session, legacyB)).containsEntry("state", "REFUNDED").containsEntry("automatic", false).containsEntry("canReopen", true);
            ResponseEntity<Map> deskB = it.call(maker, HttpMethod.POST, "/api/v1/finance/refunds", Map.of("student", B, "payer", "ZZSIWESB" + n + ", Invented",
                    "reason", "SiwesRegistrationIT: the old portal's payment given back", "amount", 4000, "source", legacyB));
            assertThat(status(deskB)).as(String.valueOf(deskB.getBody())).isEqualTo(422);
            assertThat(code(deskB)).isEqualTo("REFUND_SIWES_CREDIT_SETTLED");
            UUID legacyBId = jdbc.sql("SELECT id FROM finance.payment_reference WHERE reference = :r").param("r", legacyB).query(UUID.class).single();
            ResponseEntity<Map> archivedAgain = it.call(accounts, HttpMethod.POST, "/api/v1/finance/payment-archive", Map.of("payment", legacyBId, "reason", "UNVERIFIED_PAYMENT",
                    "note", "The bank has not confirmed this SIWES payment", "confirmed", true));
            assertThat(status(archivedAgain)).as(String.valueOf(archivedAgain.getBody())).isEqualTo(422);
            assertThat(code(archivedAgain)).isEqualTo("PAR_LINKED");
            // ── K2: the Bursar publishes Student Accounts' draft: the fee in force now, the figure it replaced kept in the history ──
            ResponseEntity<Map> republished = it.call(bursar, HttpMethod.POST, "/api/v1/finance/siwes/fee/publish", Map.of("session", session));
            assertThat(status(republished)).as(String.valueOf(republished.getBody())).isEqualTo(200);
            assertThat(republished.getBody()).containsEntry("state", "PUBLISHED");
            assertThat(money(republished.getBody().get("amount"))).isEqualByComparingTo("5000");
            assertThat(republished.getBody().get("draft")).isNull();
            assertThat((List<Map<String, Object>>) republished.getBody().get("history")).filteredOn(h -> "PUBLISHED".equals(h.get("action")) && h.get("wasAmount") != null)
                    .extracting(h -> money(h.get("amount")).intValue() + "/" + money(h.get("wasAmount")).intValue()).contains("5000/4000");
            assertThat(money(((Map<String, Object>) it.get(student(G), "/api/v1/me/siwes").getBody().get("fee")).get("amount"))).isEqualByComparingTo("5000");
            // ── a programme is added to the open period only once its 300 Level students have a SIWES course; a student who paid on the
            //    portal, whose course has since ended, is told so plainly (SIWES_COURSE_MISSING) and is still bound; the course restored,
            //    the student's SIWES is as before. M, E and its course are this case's alone ──
            ResponseEntity<Map> tooSoonM = it.call(academic, HttpMethod.POST, admin + "/programmes", Map.of("session", session, "programmeCode", M));
            assertThat(status(tooSoonM)).as(String.valueOf(tooSoonM.getBody())).isEqualTo(422);
            assertThat(code(tooSoonM)).isEqualTo("SIWES_COURSE_MISSING");
            assertThat(String.valueOf(tooSoonM.getBody().get("detail"))).contains(M);
            assertThat(codes((List<Map<String, Object>>) it.get(academic, admin + "/config?session=" + session).getBody().get("programmes"), "code")).doesNotContain(M);
            Map<String, Object> mappingM = new HashMap<>();
            mappingM.put("programmeCode", M);
            mappingM.put("curriculum", null);
            mappingM.put("courseCode", missing);
            assertThat(status(it.call(academic, HttpMethod.PUT, admin + "/courses", mappingM))).isEqualTo(200);
            ResponseEntity<Map> addedM = it.call(academic, HttpMethod.POST, admin + "/programmes", Map.of("session", session, "programmeCode", M));
            assertThat(status(addedM)).as(String.valueOf(addedM.getBody())).isEqualTo(200);
            assertThat(codes((List<Map<String, Object>>) addedM.getBody().get("programmes"), "code")).contains(P, M);
            assertThat(it.get(student(E), "/api/v1/me/siwes").getBody()).containsEntry("eligible", true).containsEntry("applies", true).containsEntry("canPay", true);
            String refE = String.valueOf(it.call(student(E), HttpMethod.POST, "/api/v1/me/siwes/reference", Map.of()).getBody().get("reference"));
            confirm(refE);
            assertThat((Map<String, Object>) it.get(student(E), "/api/v1/me/siwes").getBody().get("paid")).containsEntry("reference", refE).containsEntry("source", "PORTAL");
            // K25: the desk reads the catalogue state of each programme's SIWES course — a course still at the Board shows so (the desk
            // warns of it), as does one ended below
            it.db(() -> jdbc.sql("UPDATE catalogue.course SET state = 'BOARD' WHERE code = :c").param("c", missing).update());
            assertThat(((List<Map<String, Object>>) it.get(academic, admin + "/config?session=" + session).getBody().get("programmes")).stream()
                    .filter(p -> M.equals(p.get("code"))).findFirst().orElseThrow().get("course")).as("at the Board")
                    .satisfies(c -> assertThat((Map<String, Object>) c).containsEntry("code", missing).containsEntry("state", "BOARD"));
            it.db(() -> jdbc.sql("UPDATE catalogue.course SET state = 'LIVE' WHERE code = :c").param("c", missing).update());
            // the department ends the course on the catalogue
            ResponseEntity<Map> ended = it.call(academic, HttpMethod.POST, "/api/v1/registration/courses/" + missing + "/end", Map.of());
            assertThat(status(ended)).as(String.valueOf(ended.getBody())).isEqualTo(200);
            assertThat(((List<Map<String, Object>>) it.get(academic, admin + "/config?session=" + session).getBody().get("programmes")).stream()
                    .filter(p -> M.equals(p.get("code"))).findFirst().orElseThrow().get("course")).as("ended")
                    .satisfies(c -> assertThat((Map<String, Object>) c).containsEntry("state", "ENDED"));
            ResponseEntity<Map> regE = it.call(student(E), HttpMethod.POST, "/api/v1/me/siwes/register", Map.of());
            assertThat(status(regE)).as(String.valueOf(regE.getBody())).isEqualTo(422);
            assertThat(code(regE)).isEqualTo("SIWES_COURSE_MISSING");
            assertThat(String.valueOf(regE.getBody().get("detail"))).contains(missing + " has ended");
            Map<String, Object> endedE = it.get(student(E), "/api/v1/me/siwes").getBody();
            assertThat(endedE).as("the payment keeps E bound").containsEntry("applies", true).containsEntry("canRegister", false);
            assertThat((List<String>) endedE.get("reasons")).contains("NO_COURSE");
            it.db(() -> jdbc.sql("UPDATE catalogue.course SET state = 'LIVE', ended_on = NULL WHERE code = :c").param("c", missing).update());
            Map<String, Object> restoredE = it.get(student(E), "/api/v1/me/siwes").getBody();
            assertThat((List<String>) restoredE.get("reasons")).isEmpty();
            assertThat((Map<String, Object>) restoredE.get("course")).containsEntry("code", missing);

            // ── K12: a SIWES registration made in error is undone by an office. A's level is corrected to 200, so SIWES no longer binds A;
            //    the student still never drops the SIWES course, the Academic Office's Student edit drops it with no override (add/drop
            //    open), and the fee is then refunded — whole ──
            it.db(() -> {
                jdbc.sql("""
                        INSERT INTO policy.semester (id, session, number, state) VALUES (gen_random_uuid(), :s, 2, 'OPEN')
                        ON CONFLICT (session, number) DO UPDATE SET state = 'OPEN', registration_closes = NULL, late_registration_closes = NULL
                        """).param("s", session).update();
                jdbc.sql("UPDATE people.student SET current_level = 200 WHERE id = :s").param("s", A).update();
                return null;
            });
            assertThat(it.get(student(A), "/api/v1/me/siwes").getBody()).containsEntry("applies", false);
            ResponseEntity<Map> keptUnbound = it.call(student(A), HttpMethod.POST, "/api/v1/me/registration/drop", Map.of("session", session, "semester", 2, "offering", siwesOff));
            assertThat(status(keptUnbound)).isEqualTo(422);
            assertThat(code(keptUnbound)).isEqualTo("SIWES_COURSE_KEPT");
            ResponseEntity<Map> officeDrop = it.call(academic, HttpMethod.POST, "/api/v1/student/students/" + A + "/edit/registration/drop", Map.of("session", session,
                    "semester", 2, "offering", siwesOff, "reason", "The SIWES registration was made in error: the Registry corrected the student's level to 200"));
            assertThat(status(officeDrop)).as(String.valueOf(officeDrop.getBody())).isEqualTo(200);
            assertThat(officeDrop.getBody().get("overridden")).isNotEqualTo(true);
            assertThat(it.get(student(A), "/api/v1/me/siwes").getBody().get("registration")).as("the SIWES registration no longer stands").isNull();
            // undone, it is an ordinary registration again: the Head's desk and the student's history no longer call it SIWES (s4-2)
            assertThat((List<Map<String, Object>>) (List<?>) it.getList(hodOwn, "/api/v1/registration/course-registrations?session=" + session + "&semester=2&status=ALL").getBody())
                    .anySatisfy(r -> assertThat(r).containsEntry("matric_no", matric.get("A")).containsEntry("siwes", false));
            assertThat(((List<Map<String, Object>>) it.get(student(A), "/api/v1/me/registration-history").getBody().get("history")).stream()
                    .filter(h -> session.equals(h.get("session")) && Integer.valueOf(2).equals(h.get("semester"))).findFirst().orElseThrow()).containsEntry("siwes", false);
            // the student's own SIWES page lists the session, its payment and the registration undone (s4-1: history)
            assertThat((List<Map<String, Object>>) it.get(student(A), "/api/v1/me/siwes").getBody().get("history")).anySatisfy(h -> {
                assertThat(h).containsEntry("session", session);
                assertThat((Map<String, Object>) h.get("registration")).containsEntry("status", "DROPPED").containsEntry("courseCode", siwesCode);
            });
            // K30: the SIWES page stays in A's menu while the payment of the session SIWES bound A in stands (A paid it on the portal) ...
            assertThat(it.get(student(A), "/api/v1/me").getBody()).as("the payment stands").containsEntry("siwesArea", true);
            ResponseEntity<Map> partA = it.call(maker, HttpMethod.POST, "/api/v1/finance/refunds", Map.of("student", A, "payer", "ZZSIWESA" + n + ", Invented",
                    "reason", "SiwesRegistrationIT: part of the SIWES fee refunded", "amount", 3000, "source", ref2));
            assertThat(status(partA)).isEqualTo(422);
            assertThat(code(partA)).isEqualTo("REFUND_SIWES_PART");
            refund(maker, checker, A, "ZZSIWESA" + n + ", Invented", ref2, 4000, true);
            Map<String, Object> undoneA = it.get(student(A), "/api/v1/me/siwes").getBody();
            assertThat(undoneA.get("paid")).as("the fee given back").isNull();
            // ... and goes once A's SIWES is wholly undone: the course dropped, ref2 given back, ref1's credit refunded by the Bursar. The
            // page, reached from a payment's link, finds the session's registration undone and nothing paid (the screen's UNDONE step)
            assertThat(it.get(student(A), "/api/v1/me").getBody()).as("wholly undone").containsEntry("siwesArea", false);
            assertThat(undoneA).containsEntry("applies", false);
            assertThat(undoneA.get("registration")).isNull();
            assertThat((List<Map<String, Object>>) undoneA.get("history")).anySatisfy(h -> {
                assertThat(h).containsEntry("session", session);
                assertThat(h.get("paid")).isNull();
                assertThat((Map<String, Object>) h.get("registration")).containsEntry("status", "DROPPED");
            });

            // ── K15: J's two old-portal SIWES payments of one Lagos day and amount under two payment numbers — V561's possible bank double
            //    charge. The second is J's credit; neither is refunded, by the Bursar's hand or on the refund desk, until the Bursary's bank
            //    check finds them received (the credits list says why, bankCheck); found received, the credit is the Bursar's to refund ──
            UUID J = it.student("ZZSIWESJ" + n, P, null, matric.get("J"), 300);
            String legJ1 = "MOAUM-LEG-IT752-" + n + "J1", legJ2 = "MOAUM-LEG-IT752-" + n + "J2";
            LocalDate paidOnJ = today.minusDays(20);
            it.db(() -> {
                jdbc.sql("UPDATE people.student SET entry_session = :e WHERE id = :s").param("e", before).param("s", J).update();
                for (String[] row : new String[][] {{legJ1, "10:00", "J1"}, {legJ2, "10:05", "J2"}}) {
                    jdbc.sql("""
                            INSERT INTO finance.payment_reference (student_id, session, reference, purpose, amount, generated_at, expires_at, confirmed_at, confirmed_by,
                                                                   channel, note, receipt_no)
                            VALUES (:s, :ses, :r, 'SIWES (legacy) · semester 2', 4000, now() - interval '30 days', now() - interval '30 days',
                                    (CAST(:d AS date) + CAST(:t AS time)) AT TIME ZONE 'Africa/Lagos', gen_random_uuid(), 'Legacy', 'Imported from the old portal',
                                    'RCT-' || :r)
                            """).param("s", J).param("ses", session).param("r", row[0]).param("d", paidOnJ.toString()).param("t", row[1]).update();
                    // the old portal's own payment number of each: two numbers, one day and amount (V561's list)
                    jdbc.sql("INSERT INTO finance.legacy_payref (payref, reference, amount) VALUES (:p, :r, 4000)")
                            .param("p", "IT752PAY" + n + row[2]).param("r", row[0]).update();
                }
                return null;
            });
            Map<String, Object> creditJ = creditOf(bursar, session, legJ2);
            assertThat(creditJ).as(String.valueOf(creditJ)).containsEntry("state", "OPEN").containsEntry("settles", false).containsEntry("canRefund", false);
            assertThat(String.valueOf(creditJ.get("reason"))).as("the payment that settles J's fee").contains(legJ1);
            assertThat(String.valueOf(creditJ.get("bankCheck"))).contains(legJ2).contains(legJ1)
                    .contains("check them with the bank first (Old Fees History, possible double charges)");
            // K31: the wait as the database's code, for the screen's pill: not yet checked with the bank
            assertThat(creditJ).containsEntry("bankCheckState", "UNCHECKED");
            assertThat(creditJ.get("settledKind")).as("open: settled by nothing").isNull();
            // K31: the payments report says so of both payments, the code beside the words
            assertThat(paymentsOf(bursar, session, P, legJ1, legJ2).values()).allSatisfy(r -> {
                assertThat(r).as(String.valueOf(r)).containsEntry("bankCheckState", "UNCHECKED");
                assertThat(String.valueOf(r.get("bankCheck"))).contains("may be a bank double charge").contains("check them with the bank first");
            });
            String creditJPath = "/api/v1/finance/siwes/credits/" + creditJ.get("id");
            ResponseEntity<Map> byHandJ = it.call(bursar, HttpMethod.POST, creditJPath + "/settle", Map.of("state", "REFUNDED", "note", "Refunded to the student's account"));
            assertThat(status(byHandJ)).as(String.valueOf(byHandJ.getBody())).isEqualTo(422);
            assertThat(code(byHandJ)).isEqualTo("SIWES_CREDIT_CHECK_BANK");
            // the refund desk refunds neither, the credit's payment nor the one settling the fee
            for (String source : List.of(legJ2, legJ1)) {
                ResponseEntity<Map> deskJ = it.call(maker, HttpMethod.POST, "/api/v1/finance/refunds", Map.of("student", J, "payer", "ZZSIWESJ" + n + ", Invented",
                        "reason", "SiwesRegistrationIT: a possible bank double charge given back", "amount", 4000, "source", source));
                assertThat(status(deskJ)).as(source + " " + deskJ.getBody()).isEqualTo(422);
                assertThat(code(deskJ)).isEqualTo("REFUND_SIWES_CHECK_BANK");
            }
            assertThat(jdbc.sql("SELECT count(*) FROM finance.refund WHERE student_id = :s").param("s", J).query(Integer.class).single()).isZero();
            // K18: nor moved on the payment correction desk, either payment: the check names the bank check in its words, and an
            // initiation is refused with its code — nothing is opened
            for (String source : List.of(legJ2, legJ1)) {
                UUID payJ = jdbc.sql("SELECT id FROM finance.payment_reference WHERE reference = :r").param("r", source).query(UUID.class).single();
                Map<String, Object> moveJ = it.get(accounts, "/api/v1/finance/payment-reallocations/check?payment=" + payJ + "&purpose=SCHOOL_FEES&session=" + session
                        + "&semester=2").getBody();
                assertThat(moveJ).as(source + " " + moveJ).containsEntry("ok", false);
                assertThat((List<String>) moveJ.get("refusals")).as(source).anySatisfy(r -> assertThat(r).startsWith("REALLOC_SIWES_CHECK_BANK: ")
                        .contains("check them with the bank first (Old Fees History, possible double charges)"));
                ResponseEntity<Map> movedJ = it.call(accounts, HttpMethod.POST, "/api/v1/finance/payment-reallocations", Map.of("payment", payJ, "purpose", "SCHOOL_FEES",
                        "session", session, "semester", 2, "reasonCode", "WRONG_PURPOSE", "reason", "SiwesRegistrationIT: the SIWES payment applied to the school fees",
                        "confirmed", true));
                assertThat(status(movedJ)).as(source + " " + movedJ.getBody()).isEqualTo(422);
                assertThat(code(movedJ)).isEqualTo("REALLOC_SIWES_CHECK_BANK");
                assertThat(String.valueOf(movedJ.getBody().get("detail"))).contains("may be a bank double charge");
            }
            assertThat(jdbc.sql("SELECT count(*) FROM finance.payment_reallocation WHERE student_id = :s").param("s", J).query(Integer.class).single()).isZero();
            // the Bursary checks them with the bank on Old Fees History (possible double charges): both arrived
            ResponseEntity<Map> checkedJ = it.call(bursar, HttpMethod.POST, "/api/v1/finance/legacy-fees/double-charges/check", Map.of("studentId", J, "session", session,
                    "purpose", "SIWES (legacy) · semester 2", "paidOn", paidOnJ.toString(), "amount", 4000, "verdict", "RECEIVED",
                    "evidence", "Bank statement of the day: both payments arrived"));
            assertThat(status(checkedJ)).as(String.valueOf(checkedJ.getBody())).isEqualTo(200);
            Map<String, Object> releasedJ = creditOf(bursar, session, legJ2);
            assertThat(releasedJ).as(String.valueOf(releasedJ)).containsEntry("state", "OPEN").containsEntry("canRefund", true);
            assertThat(releasedJ.get("bankCheck")).isNull();
            assertThat(releasedJ.get("bankCheckState")).isNull();
            // K18: found received, the correction desk no longer holds them for the bank
            UUID payJ2 = jdbc.sql("SELECT id FROM finance.payment_reference WHERE reference = :r").param("r", legJ2).query(UUID.class).single();
            assertThat((List<String>) it.get(accounts, "/api/v1/finance/payment-reallocations/check?payment=" + payJ2 + "&purpose=SCHOOL_FEES&session=" + session
                    + "&semester=2").getBody().get("refusals")).noneMatch(r -> r.startsWith("REALLOC_SIWES_CHECK_BANK"));
            ResponseEntity<Map> refundedJ = it.call(bursar, HttpMethod.POST, creditJPath + "/settle", Map.of("state", "REFUNDED", "note", "Refunded to the student's account"));
            assertThat(status(refundedJ)).as(String.valueOf(refundedJ.getBody())).isEqualTo(200);
            assertThat(refundedJ.getBody()).containsEntry("state", "REFUNDED");
            // K19: the Bursar's refund by hand, recorded so by the settling itself
            assertThat(creditOf(bursar, session, legJ2)).containsEntry("settledKind", "HAND_REFUND").containsEntry("automatic", false);
            // ── K26: the money given back on legJ2 stays on the books with it: legJ2 is not withdrawn as never received — raised on its own
            //    on Payments not received, or named by a second bank check of the day, which is then refused whole (the first stands) ──
            ResponseEntity<Map> withdrawnJ = it.call(maker, HttpMethod.POST, "/api/v1/finance/payments-not-received", Map.of("reference", legJ2,
                    "evidence", "Bank statement of the day", "reason", "SiwesRegistrationIT: the bank never received it"));
            assertThat(status(withdrawnJ)).as(String.valueOf(withdrawnJ.getBody())).isEqualTo(422);
            assertThat(code(withdrawnJ)).isEqualTo("PAY_NOT_RECEIVED_SIWES_REFUNDED");
            assertThat(String.valueOf(withdrawnJ.getBody().get("detail"))).startsWith("the SIWES credit of this payment is recorded refunded");
            assertThat(String.valueOf(((Map<String, Object>) withdrawnJ.getBody().get("remedy")).get("message"))).startsWith("The Bursar reopens the credit first");
            ResponseEntity<Map> recheckedJ = it.call(maker, HttpMethod.POST, "/api/v1/finance/legacy-fees/double-charges/check", Map.of("studentId", J,
                    "session", session, "purpose", "SIWES (legacy) · semester 2", "paidOn", paidOnJ.toString(), "amount", 4000, "verdict", "NOT_RECEIVED",
                    "evidence", "Bank statement of the day, read again", "notReceived", List.of(legJ2)));
            assertThat(status(recheckedJ)).as(String.valueOf(recheckedJ.getBody())).isEqualTo(422);
            assertThat(code(recheckedJ)).isEqualTo("PAY_NOT_RECEIVED_SIWES_REFUNDED");
            assertThat(jdbc.sql("SELECT count(*) FROM finance.payment_not_received WHERE reference = :r").param("r", legJ2).query(Integer.class).single()).isZero();
            assertThat(jdbc.sql("SELECT verdict FROM finance.double_charge_check WHERE student_id = :s AND session = :ses").param("s", J).param("ses", session)
                    .query(String.class).single()).as("the first check stands").isEqualTo("RECEIVED");
            Map<String, Object> refundedRowJ = paymentsOf(bursar, session, P, legJ2).get(legJ2);
            assertThat(refundedRowJ).as(String.valueOf(refundedRowJ)).containsEntry("creditState", "REFUNDED");
            assertThat(money(refundedRowJ.get("refunded"))).isEqualByComparingTo("4000");
            assertThat(List.of("bankCheck", "bankCheckState")).as("found received: no wait").allSatisfy(k -> assertThat(refundedRowJ.get(k)).as(k).isNull());
            // ── K35 (s6-1): the day checked again and legJ1 — the payment that settles J's fee, its money never given back — named never
            //    received. legJ2, whose credit the Bursar refunded, waits on nothing on the payments report, as the credits list shows its
            //    refunded credit: the hold's "not refunded or moved" never stands beside "refunded" — while legJ1's withdrawal waits, and
            //    once it is rejected ──
            ResponseEntity<Map> namedJ1 = it.call(maker, HttpMethod.POST, "/api/v1/finance/legacy-fees/double-charges/check", Map.of("studentId", J,
                    "session", session, "purpose", "SIWES (legacy) · semester 2", "paidOn", paidOnJ.toString(), "amount", 4000, "verdict", "NOT_RECEIVED",
                    "evidence", "Bank statement of the day, read a third time", "notReceived", List.of(legJ1)));
            assertThat(status(namedJ1)).as(String.valueOf(namedJ1.getBody())).isEqualTo(200);
            List<String> raisedJ = (List<String>) namedJ1.getBody().get("raised");
            assertThat(raisedJ).hasSize(1);
            Map<String, Map<String, Object>> waitingJ = paymentsOf(bursar, session, P, legJ1, legJ2);
            assertThat(waitingJ.get(legJ1)).as(String.valueOf(waitingJ)).containsEntry("bankCheckState", "PROPOSED").containsEntry("settles", false);
            assertThat(waitingJ.get(legJ2)).as(String.valueOf(waitingJ)).containsEntry("creditState", "REFUNDED");
            assertThat(money(waitingJ.get(legJ2).get("refunded"))).isEqualByComparingTo("4000");
            assertThat(List.of("bankCheck", "bankCheckState")).as("given back: no hold, the withdrawal waiting").allSatisfy(k -> assertThat(waitingJ.get(legJ2).get(k)).as(k).isNull());
            Map<String, Object> refundedCreditJ = creditOf(bursar, session, legJ2);
            assertThat(refundedCreditJ).as(String.valueOf(refundedCreditJ)).containsEntry("state", "REFUNDED").containsEntry("settledKind", "HAND_REFUND");
            assertThat(List.of("bankCheck", "bankCheckState")).as("the credits list: no hold on a refunded credit").allSatisfy(k -> assertThat(refundedCreditJ.get(k)).as(k).isNull());
            ResponseEntity<Map> rejectedJ = it.call(checker, HttpMethod.POST, "/api/v1/finance/payments-not-received/" + raisedJ.get(0).substring("PNR/".length()) + "/decide",
                    Map.of("approve", false, "note", "The statement line was read against the wrong day"));
            assertThat(status(rejectedJ)).as(String.valueOf(rejectedJ.getBody())).isEqualTo(200);
            assertThat(rejectedJ.getBody()).containsEntry("state", "REJECTED");
            Map<String, Map<String, Object>> heldJ = paymentsOf(bursar, session, P, legJ1, legJ2);
            assertThat(heldJ.get(legJ1)).as(String.valueOf(heldJ)).containsEntry("bankCheckState", "NOT_RECEIVED");
            assertThat(List.of("bankCheck", "bankCheckState")).as("given back: no hold, the withdrawal rejected").allSatisfy(k -> assertThat(heldJ.get(legJ2).get(k)).as(k).isNull());

            // ── K20: N's two old-portal SIWES payments of one Lagos day and amount under two payment numbers; the Bursary's bank check
            //    finds the first (the one settling N's fee) never received. While that record stands — its withdrawal waiting for a second
            //    officer, then rejected — the whole day waits: no refund by hand or on the desk, no move; the record never received settles
            //    nothing, and the one received settles N's fee from the check on, its credit APPLIED (SETTLES) at once (K27), held all the
            //    same, under the code of its wait (K31) — never the code of the record never received (s5-1). Withdrawn at last, the record
            //    received settles the fee, held no more ──
            UUID N = it.student("ZZSIWESN" + n, P, null, matric.get("N"), 300);
            String legN1 = "MOAUM-LEG-IT752-" + n + "N1", legN2 = "MOAUM-LEG-IT752-" + n + "N2";
            LocalDate paidOnN = today.minusDays(21);
            it.db(() -> {
                jdbc.sql("UPDATE people.student SET entry_session = :e WHERE id = :s").param("e", before).param("s", N).update();
                for (String[] row : new String[][] {{legN1, "09:00", "N1"}, {legN2, "09:05", "N2"}}) {
                    jdbc.sql("""
                            INSERT INTO finance.payment_reference (student_id, session, reference, purpose, amount, generated_at, expires_at, confirmed_at, confirmed_by,
                                                                   channel, note, receipt_no)
                            VALUES (:s, :ses, :r, 'SIWES (legacy) · semester 2', 4000, now() - interval '30 days', now() - interval '30 days',
                                    (CAST(:d AS date) + CAST(:t AS time)) AT TIME ZONE 'Africa/Lagos', gen_random_uuid(), 'Legacy', 'Imported from the old portal',
                                    'RCT-' || :r)
                            """).param("s", N).param("ses", session).param("r", row[0]).param("d", paidOnN.toString()).param("t", row[1]).update();
                    jdbc.sql("INSERT INTO finance.legacy_payref (payref, reference, amount) VALUES (:p, :r, 4000)")
                            .param("p", "IT752PAY" + n + row[2]).param("r", row[0]).update();
                }
                return null;
            });
            assertThat(String.valueOf(((Map<String, Object>) it.get(student(N), "/api/v1/me/siwes").getBody().get("paid")).get("reference"))).isEqualTo(legN1);
            assertThat(creditOf(bursar, session, legN2)).containsEntry("state", "OPEN").containsEntry("bankCheckState", "UNCHECKED");
            ResponseEntity<Map> checkedN = it.call(maker, HttpMethod.POST, "/api/v1/finance/legacy-fees/double-charges/check", Map.of("studentId", N, "session", session,
                    "purpose", "SIWES (legacy) · semester 2", "paidOn", paidOnN.toString(), "amount", 4000, "verdict", "NOT_RECEIVED",
                    "evidence", "Bank statement of the day: one payment arrived", "notReceived", List.of(legN1)));
            assertThat(status(checkedN)).as(String.valueOf(checkedN.getBody())).isEqualTo(200);
            List<String> raisedN = (List<String>) checkedN.getBody().get("raised");
            assertThat(raisedN).hasSize(1);
            // the withdrawal waits for a second officer: the day waits with it, in words that say so; the record received settles N's fee
            // now, its credit settled so by the check itself (K27: one payment settles, and it is no open credit)
            Map<String, Object> waitingN = creditOf(bursar, session, legN2);
            assertThat(waitingN).as(String.valueOf(waitingN)).containsEntry("state", "APPLIED").containsEntry("settledKind", "SETTLES").containsEntry("settles", true)
                    .containsEntry("canRefund", false).containsEntry("bankCheckState", "PROPOSED");
            assertThat(String.valueOf(waitingN.get("bankCheck"))).contains(legN1).contains("waits for a second Bursary officer (Payments not received)");
            assertThat(creditOf(bursar, session, legN1)).as("no credit on the record found never received").isNull();
            assertThat(String.valueOf(((Map<String, Object>) it.get(student(N), "/api/v1/me/siwes").getBody().get("paid")).get("reference")))
                    .as("the record never received settles nothing").isEqualTo(legN2);
            // K31: the payments report gives both records of the day the same wait while the withdrawal waits
            Map<String, Map<String, Object>> payN = paymentsOf(bursar, session, P, legN1, legN2);
            assertThat(payN.get(legN1)).as(String.valueOf(payN)).containsEntry("bankCheckState", "PROPOSED").containsEntry("settles", false);
            assertThat(payN.get(legN2)).as(String.valueOf(payN)).containsEntry("bankCheckState", "PROPOSED").containsEntry("settles", true)
                    .containsEntry("creditState", "APPLIED");
            // the second officer rejects the withdrawal: the record never received still stands, so the day still waits
            String pnrN = raisedN.get(0);
            ResponseEntity<Map> rejectedN = it.call(checker, HttpMethod.POST, "/api/v1/finance/payments-not-received/" + pnrN.substring("PNR/".length()) + "/decide",
                    Map.of("approve", false, "note", "The statement line was read against the wrong day"));
            assertThat(status(rejectedN)).as(String.valueOf(rejectedN.getBody())).isEqualTo(200);
            assertThat(rejectedN.getBody()).containsEntry("state", "REJECTED");
            // s5-1, K31: the record received waits on the other's withdrawal (NOT_RECEIVED_WAITING), never marked as the one never received
            Map<String, Object> heldN = creditOf(bursar, session, legN2);
            assertThat(heldN).as(String.valueOf(heldN)).containsEntry("state", "APPLIED").containsEntry("canRefund", false).containsEntry("bankCheckState", "NOT_RECEIVED_WAITING")
                    .as("the record received settles the fee meanwhile, and still says what it waits on").containsEntry("settles", true);
            assertThat(String.valueOf(heldN.get("bankCheck"))).contains("found payment " + legN1 + " never received; until it is withdrawn (Payments not received)");
            Map<String, Map<String, Object>> heldPayN = paymentsOf(bursar, session, P, legN1, legN2);
            assertThat(heldPayN.get(legN1)).as(String.valueOf(heldPayN)).containsEntry("bankCheckState", "NOT_RECEIVED");
            assertThat(heldPayN.get(legN2)).as(String.valueOf(heldPayN)).containsEntry("bankCheckState", "NOT_RECEIVED_WAITING");
            assertThat(String.valueOf(heldPayN.get(legN1).get("bankCheck"))).contains("found payment " + legN1 + " never received");
            assertThat(creditOf(bursar, session, legN1)).isNull();
            String creditNPath = "/api/v1/finance/siwes/credits/" + heldN.get("id");
            // settling the fee, the credit is no open credit: nothing to refund by hand
            ResponseEntity<Map> byHandN = it.call(bursar, HttpMethod.POST, creditNPath + "/settle", Map.of("state", "REFUNDED", "note", "Refunded to the student's account"));
            assertThat(status(byHandN)).as(String.valueOf(byHandN.getBody())).isEqualTo(422);
            assertThat(code(byHandN)).isEqualTo("SIWES_CREDIT_UNKNOWN");
            ResponseEntity<Map> deskN = it.call(maker, HttpMethod.POST, "/api/v1/finance/refunds", Map.of("student", N, "payer", "ZZSIWESN" + n + ", Invented",
                    "reason", "SiwesRegistrationIT: the payment the bank received given back", "amount", 4000, "source", legN2));
            assertThat(status(deskN)).as(String.valueOf(deskN.getBody())).isEqualTo(422);
            assertThat(code(deskN)).isEqualTo("REFUND_SIWES_CHECK_BANK");
            UUID payN2 = jdbc.sql("SELECT id FROM finance.payment_reference WHERE reference = :r").param("r", legN2).query(UUID.class).single();
            ResponseEntity<Map> movedN = it.call(accounts, HttpMethod.POST, "/api/v1/finance/payment-reallocations", Map.of("payment", payN2, "purpose", "SCHOOL_FEES",
                    "session", session, "semester", 2, "reasonCode", "WRONG_PURPOSE", "reason", "SiwesRegistrationIT: the SIWES payment applied to the school fees",
                    "confirmed", true));
            assertThat(status(movedN)).as(String.valueOf(movedN.getBody())).isEqualTo(422);
            assertThat(code(movedN)).isEqualTo("REALLOC_SIWES_CHECK_BANK");
            assertThat(String.valueOf(movedN.getBody().get("detail"))).contains("never received");
            assertThat(String.valueOf(((Map<String, Object>) it.get(student(N), "/api/v1/me/siwes").getBody().get("paid")).get("reference"))).isEqualTo(legN2);
            // raised again and approved by another officer: the record never received is withdrawn (archived), and the record received
            // settles N's fee, recorded so (SETTLES), held no more
            ResponseEntity<Map> raisedAgainN = it.call(maker, HttpMethod.POST, "/api/v1/finance/payments-not-received", Map.of("reference", legN1,
                    "evidence", "Bank statement of the day, read again", "reason", "SiwesRegistrationIT: the bank never received it"));
            assertThat(status(raisedAgainN)).as(String.valueOf(raisedAgainN.getBody())).isEqualTo(200);
            ResponseEntity<Map> approvedN = it.call(checker, HttpMethod.POST, "/api/v1/finance/payments-not-received/"
                    + String.valueOf(raisedAgainN.getBody().get("requestRef")).substring("PNR/".length()) + "/decide", Map.of("approve", true));
            assertThat(status(approvedN)).as(String.valueOf(approvedN.getBody())).isEqualTo(200);
            assertThat(approvedN.getBody()).containsEntry("state", "APPROVED");
            assertThat(jdbc.sql("SELECT archived_at IS NOT NULL FROM finance.payment_reference WHERE reference = :r").param("r", legN1).query(Boolean.class).single()).isTrue();
            Map<String, Object> settlesN = creditOf(bursar, session, legN2);
            assertThat(settlesN).as(String.valueOf(settlesN)).containsEntry("state", "APPLIED").containsEntry("settledKind", "SETTLES").containsEntry("settles", true)
                    .containsEntry("automatic", true);
            assertThat(List.of("bankCheck", "bankCheckState")).allSatisfy(k -> assertThat(settlesN.get(k)).as(k).isNull());
            Map<String, Object> settlesPayN = paymentsOf(bursar, session, P, legN2).get(legN2);
            assertThat(settlesPayN).as(String.valueOf(settlesPayN)).containsEntry("settles", true);
            assertThat(List.of("bankCheck", "bankCheckState")).allSatisfy(k -> assertThat(settlesPayN.get(k)).as(k).isNull());
            assertThat(String.valueOf(((Map<String, Object>) it.get(student(N), "/api/v1/me/siwes").getBody().get("paid")).get("reference"))).isEqualTo(legN2);

            // ── K32 (d6-1): O's two old-portal SIWES payments of one day and amount, loaded by the Bursary's Old Fees History upload under
            //    two payment numbers (V561's possible bank double charge). The bank check finds the first — the one settling O's fee —
            //    never received, and its withdrawal is rejected. The old portal's export loaded again without payment numbers puts that
            //    record's day right (a day later): the finding follows the record, not its day — still never received and held, refused on
            //    the refund desk, the other's credit settling the fee as before, nothing for the Bursar to refund by hand ──
            UUID O = it.student("ZZSIWESO" + n, P, null, matric.get("O"), 300);
            it.db(() -> jdbc.sql("UPDATE people.student SET entry_session = :e WHERE id = :s").param("e", before).param("s", O).update());
            LocalDate paidOnO = today.minusDays(25);
            ResponseEntity<Map> loadedO = it.call(bursar, HttpMethod.POST, "/api/v1/finance/legacy-fees", Map.of("rows", List.of(
                    oldFeesRow(matric.get("O"), session, paidOnO, "IT752PAY" + n + "O1"), oldFeesRow(matric.get("O"), session, paidOnO, "IT752PAY" + n + "O2"))));
            assertThat(status(loadedO)).as(String.valueOf(loadedO.getBody())).isEqualTo(200);
            List<String> legO = jdbc.sql("SELECT reference FROM finance.payment_reference WHERE student_id = :s AND channel = 'Legacy' ORDER BY length(reference), reference")
                    .param("s", O).query(String.class).list();
            assertThat(legO).as("one record a payment number").hasSize(2);
            String legO1 = legO.get(0), legO2 = legO.get(1);
            assertThat(legO2).startsWith(legO1 + "-");
            assertThat(String.valueOf(((Map<String, Object>) it.get(student(O), "/api/v1/me/siwes").getBody().get("paid")).get("reference"))).isEqualTo(legO1);
            assertThat(creditOf(bursar, session, legO2)).containsEntry("state", "OPEN").containsEntry("bankCheckState", "UNCHECKED");
            ResponseEntity<Map> checkedO = it.call(maker, HttpMethod.POST, "/api/v1/finance/legacy-fees/double-charges/check", Map.of("studentId", O, "session", session,
                    "purpose", "SIWES (legacy) · semester 2", "paidOn", paidOnO.toString(), "amount", 4000, "verdict", "NOT_RECEIVED",
                    "evidence", "Bank statement of the day: one payment arrived", "notReceived", List.of(legO1)));
            assertThat(status(checkedO)).as(String.valueOf(checkedO.getBody())).isEqualTo(200);
            List<String> raisedO = (List<String>) checkedO.getBody().get("raised");
            assertThat(raisedO).hasSize(1);
            ResponseEntity<Map> rejectedO = it.call(checker, HttpMethod.POST, "/api/v1/finance/payments-not-received/" + raisedO.get(0).substring("PNR/".length()) + "/decide",
                    Map.of("approve", false, "note", "The statement line was read against the wrong day"));
            assertThat(status(rejectedO)).as(String.valueOf(rejectedO.getBody())).isEqualTo(200);
            // the picture before the day is put right, and the same after it: what the record found never received shows, by the API
            java.util.function.Supplier<String> pictureO = () -> {
                Map<String, Map<String, Object>> pay = paymentsOf(bursar, session, P, legO1, legO2);
                Map<String, Object> c1 = creditOf(bursar, session, legO1), c2 = creditOf(bursar, session, legO2);
                return pay.get(legO1).get("bankCheckState") + "/" + pay.get(legO1).get("settles") + " | " + pay.get(legO2).get("bankCheckState") + "/" + pay.get(legO2).get("settles")
                        + "/" + pay.get(legO2).get("creditState") + " | " + (c1 == null ? "not listed" : c1.get("state")) + " | "
                        + (c2 == null ? "not listed" : c2.get("state") + ":" + c2.get("settledKind") + "/" + c2.get("settles") + "/" + c2.get("canRefund") + "/" + c2.get("bankCheckState"))
                        + " | paid by " + ((Map<String, Object>) it.get(student(O), "/api/v1/me/siwes").getBody().get("paid")).get("reference");
            };
            String expectedO = "NOT_RECEIVED/false | NOT_RECEIVED_WAITING/true/APPLIED | not listed | APPLIED:SETTLES/true/false/NOT_RECEIVED_WAITING | paid by " + legO2;
            assertThat(pictureO.get()).as("found never received, the withdrawal rejected").isEqualTo(expectedO);
            // the export loaded again, without payment numbers: the record's day put right, a day later
            ResponseEntity<Map> reloadedO = it.call(bursar, HttpMethod.POST, "/api/v1/finance/legacy-fees", Map.of("rows", List.of(
                    oldFeesRow(matric.get("O"), session, paidOnO.plusDays(1), null))));
            assertThat(status(reloadedO)).as(String.valueOf(reloadedO.getBody())).isEqualTo(200);
            assertThat(jdbc.sql("SELECT (confirmed_at AT TIME ZONE 'Africa/Lagos')::date FROM finance.payment_reference WHERE reference = :r").param("r", legO1)
                    .query(LocalDate.class).single()).as("the upload put the day right").isEqualTo(paidOnO.plusDays(1));
            assertThat(pictureO.get()).as("the finding follows the record, whatever its day").isEqualTo(expectedO);
            // never refunded though the bank never received it, nor the one received while the other stands (V561); nothing open to refund
            for (String source : List.of(legO1, legO2)) {
                ResponseEntity<Map> deskO = it.call(maker, HttpMethod.POST, "/api/v1/finance/refunds", Map.of("student", O, "payer", "ZZSIWESO" + n + ", Invented",
                        "reason", "SiwesRegistrationIT: a SIWES payment given back", "amount", 4000, "source", source));
                assertThat(status(deskO)).as(source + " " + deskO.getBody()).isEqualTo(422);
                assertThat(code(deskO)).as(source).isEqualTo("REFUND_SIWES_CHECK_BANK");
            }
            ResponseEntity<Map> byHandO = it.call(bursar, HttpMethod.POST, "/api/v1/finance/siwes/credits/" + creditOf(bursar, session, legO2).get("id") + "/settle",
                    Map.of("state", "REFUNDED", "note", "Refunded to the student's account"));
            assertThat(status(byHandO)).as(String.valueOf(byHandO.getBody())).isEqualTo(422);
            assertThat(code(byHandO)).isEqualTo("SIWES_CREDIT_UNKNOWN");
            assertThat(jdbc.sql("SELECT count(*) FROM finance.refund WHERE student_id = :s").param("s", O).query(Integer.class).single()).isZero();

            // ── K33 (d6-2): W's two old-portal SIWES payments of one day under two payment numbers, found received by the bank check. The
            //    Bursar refunds W's credit (legW2) by hand; then legW1, the payment that settled W's fee, is refunded whole on the refund
            //    desk: nothing settles the fee. The credit reopened (recorded refunded in error) is put under the one rule again and settles
            //    the fee (APPLIED, SETTLES) — never a fee paid by an open credit offered for refund. K35 (s6-1): the day checked again and
            //    legW2 named never received, legW1 — given back on the desk, with no credit — shows no hold on the payments report ──
            UUID W = it.student("ZZSIWESW" + n, P, null, matric.get("W"), 300);
            String legW1 = "MOAUM-LEG-IT752-" + n + "W1", legW2 = "MOAUM-LEG-IT752-" + n + "W2";
            LocalDate paidOnW = today.minusDays(22);
            it.db(() -> {
                jdbc.sql("UPDATE people.student SET entry_session = :e WHERE id = :s").param("e", before).param("s", W).update();
                for (String[] row : new String[][] {{legW1, "11:00", "W1"}, {legW2, "11:05", "W2"}}) {
                    jdbc.sql("""
                            INSERT INTO finance.payment_reference (student_id, session, reference, purpose, amount, generated_at, expires_at, confirmed_at, confirmed_by,
                                                                   channel, note, receipt_no)
                            VALUES (:s, :ses, :r, 'SIWES (legacy) · semester 2', 4000, now() - interval '30 days', now() - interval '30 days',
                                    (CAST(:d AS date) + CAST(:t AS time)) AT TIME ZONE 'Africa/Lagos', gen_random_uuid(), 'Legacy', 'Imported from the old portal',
                                    'RCT-' || :r)
                            """).param("s", W).param("ses", session).param("r", row[0]).param("d", paidOnW.toString()).param("t", row[1]).update();
                    jdbc.sql("INSERT INTO finance.legacy_payref (payref, reference, amount) VALUES (:p, :r, 4000)")
                            .param("p", "IT752PAY" + n + row[2]).param("r", row[0]).update();
                }
                return null;
            });
            assertThat(String.valueOf(((Map<String, Object>) it.get(student(W), "/api/v1/me/siwes").getBody().get("paid")).get("reference"))).isEqualTo(legW1);
            ResponseEntity<Map> checkedW = it.call(bursar, HttpMethod.POST, "/api/v1/finance/legacy-fees/double-charges/check", Map.of("studentId", W, "session", session,
                    "purpose", "SIWES (legacy) · semester 2", "paidOn", paidOnW.toString(), "amount", 4000, "verdict", "RECEIVED",
                    "evidence", "Bank statement of the day: both payments arrived"));
            assertThat(status(checkedW)).as(String.valueOf(checkedW.getBody())).isEqualTo(200);
            String creditWPath = "/api/v1/finance/siwes/credits/" + creditOf(bursar, session, legW2).get("id");
            ResponseEntity<Map> byHandW = it.call(bursar, HttpMethod.POST, creditWPath + "/settle", Map.of("state", "REFUNDED", "note", "Refunded to the student's account"));
            assertThat(status(byHandW)).as(String.valueOf(byHandW.getBody())).isEqualTo(200);
            refund(maker, checker, W, "ZZSIWESW" + n + ", Invented", legW1, 4000, true);
            assertThat(it.get(student(W), "/api/v1/me/siwes").getBody().get("paid")).as("both given back: nothing settles W's fee").isNull();
            ResponseEntity<Map> reopenedW = it.call(bursar, HttpMethod.POST, creditWPath + "/reopen", Map.of("reason", "Recorded as refunded in error: the transfer came back"));
            assertThat(status(reopenedW)).as(String.valueOf(reopenedW.getBody())).isEqualTo(200);
            // the answer is the credit as it then stands (the database's names, as the screen reads them)
            assertThat(reopenedW.getBody()).as(String.valueOf(reopenedW.getBody())).containsEntry("state", "APPLIED").containsEntry("settled_kind", "SETTLES");
            Map<String, Object> settlesW = creditOf(bursar, session, legW2);
            assertThat(settlesW).as(String.valueOf(settlesW)).containsEntry("state", "APPLIED").containsEntry("settledKind", "SETTLES").containsEntry("settles", true)
                    .containsEntry("canRefund", false).containsEntry("automatic", true);
            assertThat(String.valueOf(((Map<String, Object>) it.get(student(W), "/api/v1/me/siwes").getBody().get("paid")).get("reference"))).isEqualTo(legW2);
            Map<String, Map<String, Object>> payW = paymentsOf(bursar, session, P, legW1, legW2);
            assertThat(payW.get(legW2)).as(String.valueOf(payW)).containsEntry("settles", true).containsEntry("creditState", "APPLIED");
            assertThat(payW.get(legW1)).as(String.valueOf(payW)).containsEntry("settles", false);
            assertThat(payW.get(legW1).get("creditState")).isNull();
            assertThat(money(payW.get(legW1).get("refunded"))).isEqualByComparingTo("4000");
            ResponseEntity<Map> namedW2 = it.call(maker, HttpMethod.POST, "/api/v1/finance/legacy-fees/double-charges/check", Map.of("studentId", W, "session", session,
                    "purpose", "SIWES (legacy) · semester 2", "paidOn", paidOnW.toString(), "amount", 4000, "verdict", "NOT_RECEIVED",
                    "evidence", "Bank statement of the day, read again", "notReceived", List.of(legW2)));
            assertThat(status(namedW2)).as(String.valueOf(namedW2.getBody())).isEqualTo(200);
            assertThat((List<String>) namedW2.getBody().get("raised")).hasSize(1);
            Map<String, Map<String, Object>> heldW = paymentsOf(bursar, session, P, legW1, legW2);
            assertThat(heldW.get(legW2)).as(String.valueOf(heldW)).containsEntry("bankCheckState", "PROPOSED");
            assertThat(List.of("bankCheck", "bankCheckState")).as("given back on the desk: no hold").allSatisfy(k -> assertThat(heldW.get(legW1).get(k)).as(k).isNull());

            // ── K17: a SIWES course entered on a Second Semester registration an office had approved is stamped approved on the fee (AUTO,
            //    now, by nobody), the status unchanged: L's ordinary course was approved by a Head while L read 200 Level, before SIWES bound
            //    L; ICT Support drops it with no override (K12), L pays and registers the SIWES course on it ──
            UUID L = it.student("ZZSIWESL" + n, P, null, matric.get("L"), 300);
            UUID regL = UUID.randomUUID();
            it.db(() -> {
                jdbc.sql("UPDATE people.student SET entry_session = :e WHERE id = :s").param("e", before).param("s", L).update();
                String feesL = jdbc.sql("SELECT finance.new_purpose_reference(:s, :ses, 100000, 'School fees ' || :ses)").param("s", L).param("ses", session)
                        .query(String.class).single();
                jdbc.sql("SELECT finance.confirm_payment(:r, 'BANK_BRANCH', 'teller for the SIWES test')").param("r", feesL).query(String.class).single();
                jdbc.sql("UPDATE people.student SET current_level = 200 WHERE id = :s").param("s", L).update();
                jdbc.sql("""
                        INSERT INTO registration.course_registration (id, student_id, session, semester, level, status, submitted_at, approved_at, approved_by, approval_mode)
                        VALUES (:id, :s, :ses, 2, 300, 'APPROVED', now() - interval '3 days', now() - interval '2 days', gen_random_uuid(), 'HOD')
                        """).param("id", regL).param("s", L).param("ses", session).update();
                jdbc.sql("INSERT INTO registration.entry (registration_id, offering_id, units, status) VALUES (:r, :o, 3, 'APPROVED')")
                        .param("r", regL).param("o", electiveOff).update();
                jdbc.sql("UPDATE people.student SET current_level = 300 WHERE id = :s").param("s", L).update();
                return null;
            });
            ResponseEntity<Map> supportDropL = it.call(ictDesk, HttpMethod.POST, "/api/v1/helpdesk/support/students/" + L + "/registration/drop", Map.of("session", session,
                    "semester", 2, "offering", electiveOff, "reason", "The elective stands in the way of the student's SIWES course"));
            assertThat(status(supportDropL)).as(String.valueOf(supportDropL.getBody())).isEqualTo(200);
            String refL = String.valueOf(it.call(student(L), HttpMethod.POST, "/api/v1/me/siwes/reference", Map.of()).getBody().get("reference"));
            confirm(refL);
            ResponseEntity<Map> regL2 = it.call(student(L), HttpMethod.POST, "/api/v1/me/siwes/register", Map.of());
            assertThat(status(regL2)).as(String.valueOf(regL2.getBody())).isEqualTo(200);
            assertThat(regL2.getBody()).containsEntry("status", "APPROVED").containsEntry("registrationId", regL.toString());
            assertThat(jdbc.sql("""
                    SELECT r.status || '/' || r.approval_mode || '/' || (r.approved_by IS NULL) || '/' || (r.approved_at > now() - interval '10 minutes') || '/'
                           || (SELECT string_agg(o.course_code || ':' || e.status, ',' ORDER BY o.course_code) FROM registration.entry e
                                 JOIN catalogue.offering o ON o.id = e.offering_id WHERE e.registration_id = r.id)
                      FROM registration.course_registration r WHERE r.id = :id
                    """).param("id", regL).query(String.class).single())
                    .as("stamped on the fee: AUTO, now, by nobody; the Head's approval of the course the Head never saw is gone")
                    .isEqualTo("APPROVED/AUTO/true/true/" + siwesCode + ":APPROVED," + elective + ":DROPPED");

            // ── K21: H's SIWES registration stands on H's old-portal payment, the only SIWES payment H holds for the session: it is not
            //    withdrawn as never received (the registration would stand on money the bank never received) — the Academic Office or ICT
            //    Support undoes the registration first; with another SIWES payment of H's standing, the withdrawal is raised ──
            String legH = "MOAUM-LEG-IT752-" + n + "H";
            Map<String, Object> raiseH = Map.of("reference", legH, "evidence", "Bank statement of the day", "reason", "SiwesRegistrationIT: the bank never received it");
            ResponseEntity<Map> withdrawnH = it.call(maker, HttpMethod.POST, "/api/v1/finance/payments-not-received", raiseH);
            assertThat(status(withdrawnH)).as(String.valueOf(withdrawnH.getBody())).isEqualTo(422);
            assertThat(code(withdrawnH)).isEqualTo("PAY_NOT_RECEIVED_SIWES_REGISTERED");
            assertThat(String.valueOf(withdrawnH.getBody().get("detail"))).contains("a SIWES course stands registered on this payment");
            assertThat((Map<String, Object>) withdrawnH.getBody().get("remedy")).containsEntry("message", "The Academic Office or ICT Support undoes the SIWES registration first.");
            assertThat(jdbc.sql("SELECT count(*) FROM finance.payment_not_received WHERE reference = :r").param("r", legH).query(Integer.class).single()).isZero();
            assertThat((Map<String, Object>) it.get(student(H), "/api/v1/me/siwes").getBody().get("registration")).containsEntry("status", "APPROVED");
            // another payment of H's standing (a second old-portal payment, H's credit): the withdrawal is raised, then cancelled here
            oldPortalSiwes(H, session, String.valueOf(n) + "H2");
            ResponseEntity<Map> raisedH = it.call(maker, HttpMethod.POST, "/api/v1/finance/payments-not-received", raiseH);
            assertThat(status(raisedH)).as(String.valueOf(raisedH.getBody())).isEqualTo(200);
            assertThat(raisedH.getBody()).containsEntry("state", "PROPOSED");
            ResponseEntity<Map> cancelledH = it.call(maker, HttpMethod.POST, "/api/v1/finance/payments-not-received/"
                    + String.valueOf(raisedH.getBody().get("requestRef")).substring("PNR/".length()) + "/cancel", Map.of());
            assertThat(status(cancelledH)).as(String.valueOf(cancelledH.getBody())).isEqualTo(200);
        } finally {
            if (keySet) {
                it.call(ict, HttpMethod.POST, "/api/v1/payments/gateways/quickteller/clear-key", Map.of());
            }
            it.db(() -> {
                jdbc.sql("DELETE FROM finance.fee_schedule WHERE session = :s").param("s", session).update();
                // the add/drop calendar and the student-reset rule opened for H's doors (the session is the test's own)
                jdbc.sql("DELETE FROM registration.approval_policy WHERE session = :s").param("s", session).update();
                jdbc.sql("DELETE FROM policy.semester WHERE session = :s").param("s", session).update();
                // the course put at the Board and ended for E's case, live again whatever happened
                jdbc.sql("UPDATE catalogue.course SET state = 'LIVE', ended_on = NULL WHERE code = :c AND state <> 'LIVE'").param("c", missing).update();
                jdbc.sql("DELETE FROM policy.clearance_rule WHERE version_id IN (SELECT id FROM policy.version WHERE instrument = :i)").param("i", instrument).update();
                jdbc.sql("DELETE FROM policy.clearance_scheme WHERE version_id IN (SELECT id FROM policy.version WHERE instrument = :i)").param("i", instrument).update();
                jdbc.sql("DELETE FROM policy.version WHERE instrument = :i").param("i", instrument).update();
                jdbc.sql("UPDATE policy.academic_session SET state = :st WHERE name = :n").param("st", sessionState).param("n", session).update();
                jdbc.sql("UPDATE policy.academic_session SET state = :st WHERE name = :n").param("st", beforeState).param("n", before).update();
                if (previousCurrent != null && !previousCurrent.equals(session)) jdbc.sql("UPDATE policy.academic_session SET state = 'CURRENT' WHERE name = :n").param("n", previousCurrent).update();
                return null;
            });
        }
    }
}
