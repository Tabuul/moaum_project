package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.math.BigDecimal;
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
 * Old-portal GST payments reconciled into the GST/EPS entitlement (V323), end to end: the brief's cases — the paid legacy student, the
 * unpaid one, the wrong session, the failed and the refunded payment, the duplicate, the ambiguous student, the unmatched student, the
 * current-plus-legacy duplicate, the partial payment, the historical fee — the dry run that writes nothing, the apply that writes the one
 * ledger, the queue worked by an officer with the identifier guard, the relabel, the student's screen, the registration gate and the CBT
 * eligibility reading the same answer, the GST dashboard's split, and the offices that are refused.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class LegacyGstIT {

    static final String SESSION = "2119/2120";
    static final String PREVIOUS = "2118/2119";
    static final String PROGRAMME = "C00023";

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    ItSupport it;
    String bursar = ItSupport.token("bursar");
    String gst = ItSupport.token("gst");
    String registrar = ItSupport.token("registrar");
    String lecturer = ItSupport.token("lecturer");
    int n;
    UUID a, b, c, d, e;
    String tokenA, tokenD;
    String matricA, matricB, matricC, matricD, matricE, jambA;
    String code;
    UUID offering;

    static Map<String, Object> m(Object o) { return (Map<String, Object>) o; }
    static List<Map<String, Object>> l(Object o) { return (List<Map<String, Object>>) o; }

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
        it.session(SESSION, 2119);
        it.session(PREVIOUS, 2118);
        n = new Random().nextInt(9000) + 1000;
        matricA = "MOAUM/LGA/19/" + n; matricB = "MOAUM/LGB/19/" + n; matricC = "MOAUM/LGC/19/" + n; matricD = "MOAUM/LGD/19/" + n; matricE = "MOAUM/LGE/19/" + n;
        jambA = "19" + String.format("%06d", n) + "LA";
        a = it.student("ZZLGA" + n, PROGRAMME, "MOAUM/ADM/19/" + String.format("%06d", n), matricA, 100);
        b = it.student("ZZLGB" + n, PROGRAMME, "MOAUM/ADM/19/" + String.format("%06d", n + 1), matricB, 100);
        c = it.student("ZZLGC" + n, PROGRAMME, "MOAUM/ADM/19/" + String.format("%06d", n + 2), matricC, 100);
        d = it.student("ZZLGD" + n, PROGRAMME, "MOAUM/ADM/19/" + String.format("%06d", n + 3), matricD, 100);
        e = it.student("ZZLGD" + n, PROGRAMME, "MOAUM/ADM/19/" + String.format("%06d", n + 4), matricE, 100);   // same surname as D: a suggestion, never a match
        tokenA = TestTokens.token(a, List.of("student"));
        tokenD = TestTokens.token(d, List.of("student"));
        code = "GST " + (300 + n % 199);
        it.db(() -> {
            // E shares D's surname and other names but has its own number: ItSupport reuses a student by surname, so E is made by hand when it collapsed onto D
            if (e.equals(d)) {
                e = UUID.randomUUID();
                jdbc.sql("INSERT INTO people.student (id, admission_no, matric_no, surname, other_names, programme_code, entry_mode, entry_session, entry_level, current_level, status, matriculated_at) VALUES (:id, :adm, :mat, :s, 'Invented', :p, 'UTME', '2020/2021', 100, 100, 'ACTIVE', now())")
                        .param("id", e).param("adm", "MOAUM/ADM/19/" + String.format("%06d", n + 4)).param("mat", matricE).param("s", "ZZLGD" + n).param("p", PROGRAMME).update();
            }
            jdbc.sql("UPDATE people.student SET jamb_reg_no = :j, entry_session = :ses WHERE id = :id").param("j", jambA).param("ses", SESSION).param("id", a).update();
            for (UUID id : List.of(b, c, d, e)) jdbc.sql("UPDATE people.student SET entry_session = :ses WHERE id = :id").param("ses", SESSION).param("id", id).update();
            jdbc.sql("UPDATE finance.gst_fee SET superseded_at = now() WHERE session IN (:s, :p) AND superseded_at IS NULL").param("s", SESSION).param("p", PREVIOUS).update();
            jdbc.sql("UPDATE finance.gst_setting SET required_for_gst_eps = true, required_for_all = false, covers_eps = true WHERE id = 1").update();
            String dept = jdbc.sql("SELECT dept_code FROM ref.programme WHERE code = :p").param("p", PROGRAMME).query(String.class).single();
            jdbc.sql("INSERT INTO catalogue.course (code, title, units, semester, level, dept_code, kind, state) VALUES (:c, :t, 2, 1, 100, :d, 'GST', 'LIVE') ON CONFLICT (code) DO NOTHING")
                    .param("c", code).param("t", "Legacy General Studies " + n).param("d", dept).update();
            jdbc.sql("INSERT INTO catalogue.course_offer (course_code, programme_code, level, basis) VALUES (:c, :p, 100, 'GST') ON CONFLICT DO NOTHING").param("c", code).param("p", PROGRAMME).update();
            jdbc.sql("INSERT INTO catalogue.offering (id, course_code, session, semester) VALUES (gen_random_uuid(), :c, :s, 1) ON CONFLICT (course_code, session, semester, stream) DO NOTHING").param("c", code).param("s", SESSION).update();
            return null;
        });
        offering = jdbc.sql("SELECT id FROM catalogue.offering WHERE course_code = :c AND session = :s AND semester = 1").param("c", code).param("s", SESSION).query(UUID.class).single();
        // the fee of each session, as the Bursar states it: 15,000 last session, 20,000 this one
        assertThat(it.call(bursar, HttpMethod.PUT, "/api/v1/gst/fee", Map.of("session", PREVIOUS, "amount", 15000)).getStatusCode().value()).isEqualTo(200);
        assertThat(it.call(bursar, HttpMethod.PUT, "/api/v1/gst/fee", Map.of("session", SESSION, "amount", 20000)).getStatusCode().value()).isEqualTo(200);
    }

    private Map<String, Object> row(String tx, String ref, String matric, String jamb, String name, String type, String amount, String paidAt, String session, String status) {
        Map<String, Object> r = new java.util.LinkedHashMap<>();
        r.put("transactionId", tx); r.put("reference", ref); r.put("matric", matric); r.put("jamb", jamb); r.put("name", name); r.put("paymentType", type);
        r.put("amount", amount); r.put("paidAt", paidAt); r.put("session", session); r.put("status", status);
        return r;
    }

    private String tag(String s) { return s + "-" + n; }

    private List<Map<String, Object>> file() {
        return List.of(
                row(tag("TX1"), tag("OLD-GST-000123"), matricA, jambA, "ZZLGA Invented", "GST PAYMENT", "20,000.00", "15/09/2119", SESSION, "SUCCESS"),   // the paid legacy student
                row(tag("TX2"), tag("OLD-GST-000124"), matricB, null, null, "GST", "20000", "2119-09-16", SESSION, "FAILED"),                           // failed: establishes nothing
                row(tag("TX3"), tag("OLD-GST-000125"), matricB, null, null, "GST", "20000", "2119-09-17", SESSION, "REFUNDED"),                         // refunded: establishes nothing
                row(tag("TX4"), tag("OLD-GST-000126"), matricC, null, null, "GST", "20000", "2119-09-16", SESSION, "successful"),                       // C paid on this portal too: duplicate
                row(tag("TX5"), tag("OLD-GST-000127"), matricA, null, null, "GST", "15000", "2118-10-02", PREVIOUS, "PAID"),                            // the historical fee of last session: valid for THAT session
                row(tag("TX6"), tag("OLD-GST-000128"), matricD, null, null, "GST", "2000", "2119-09-16", SESSION, "SUCCESS"),                            // partial: review
                row(tag("TX7"), tag("OLD-GST-000129"), "MOAUM/NOPE/19/" + n, null, "ZZLGD" + n + " Invented", "GST", "20000", "2119-09-16", SESSION, "SUCCESS"),   // nobody by number; two by name: unmatched with suggestions
                row(tag("TX8"), tag("OLD-GST-000130"), matricA, null, null, "HOSTEL", "20000", "2119-09-16", SESSION, "SUCCESS"),                        // not a GST type
                row(tag("TX9"), tag("OLD-GST-000131"), matricD, null, null, "GST", "20000", "2119-09-16", "2001/2002", "SUCCESS"),                     // a session not on the calendar
                row(tag("TX1"), tag("OLD-GST-000123"), matricA, null, null, "GST", "20000", null, SESSION, "SUCCESS"));                                 // the same old payment twice in the file
    }

    @Test
    void theBriefsCasesFromDryRunToTheStudentsScreen() {
        // C paid on this portal already
        ResponseEntity<Map> refC = it.call(TestTokens.token(c, List.of("student")), HttpMethod.POST, "/api/v1/me/gst/reference", Map.of("session", SESSION));
        assertThat(refC.getStatusCode().value()).as(String.valueOf(refC.getBody())).isEqualTo(200);
        it.db(() -> jdbc.sql("SELECT finance.confirm_payment(:r, 'CARD', 'gateway for the test')").param("r", String.valueOf(refC.getBody().get("reference"))).query(String.class).single());
        // before anything: A reads NOT PAID and is held at the gate
        assertThat(m(it.get(tokenA, "/api/v1/me/gst?session=" + SESSION).getBody().get("entitlement")).get("state")).isEqualTo("NOT_PAID");
        ResponseEntity<Map> held = it.call(tokenA, HttpMethod.PUT, "/api/v1/me/registration", Map.of("session", SESSION, "semester", 1, "offerings", List.of(offering)));
        assertThat(held.getBody().get("code")).isEqualTo("GST_PAYMENT_REQUIRED");

        // the other offices are refused the desk
        assertThat(it.call(gst, HttpMethod.POST, "/api/v1/finance/legacy-gst/imports", Map.of("rows", file(), "dryRun", true)).getStatusCode().value()).isEqualTo(403);
        assertThat(it.call(lecturer, HttpMethod.POST, "/api/v1/finance/legacy-gst/imports", Map.of("rows", file(), "dryRun", true)).getStatusCode().value()).isEqualTo(403);
        assertThat(it.get(gst, "/api/v1/finance/legacy-gst/summary").getStatusCode().value()).isEqualTo(403);
        assertThat(it.get(registrar, "/api/v1/finance/legacy-gst/summary").getStatusCode().value()).isEqualTo(200);

        // the dry run: judged, counted, nothing kept
        long before = jdbc.sql("SELECT count(*) FROM finance.legacy_gst_payment").query(Long.class).single();
        ResponseEntity<Map> dry = it.call(bursar, HttpMethod.POST, "/api/v1/finance/legacy-gst/imports", Map.of("rows", file(), "fileName", "old-gst.xlsx", "session", SESSION, "dryRun", true));
        assertThat(dry.getStatusCode().value()).as(String.valueOf(dry.getBody())).isEqualTo(200);
        assertThat(dry.getBody().get("dryRun")).isEqualTo(true);
        Map<String, Object> ds = m(dry.getBody().get("summary"));
        assertThat(((Number) ds.get("matched")).intValue()).isEqualTo(2);          // TX1 and TX5 would reconcile
        assertThat(((Number) ds.get("requires_review")).intValue()).isEqualTo(1);  // TX6 partial
        assertThat(((Number) ds.get("unmatched")).intValue()).isEqualTo(1);        // TX7
        assertThat(((Number) ds.get("duplicates")).intValue()).isEqualTo(1);       // TX4
        assertThat(((Number) ds.get("rejected")).intValue()).isEqualTo(4);         // TX2, TX3, TX8, TX9
        assertThat(((Number) m(dry.getBody().get("staging")).get("already_staged")).intValue()).isEqualTo(1);   // TX1 twice in the file
        assertThat(jdbc.sql("SELECT count(*) FROM finance.legacy_gst_payment").query(Long.class).single()).isEqualTo(before);
        assertThat(m(it.get(tokenA, "/api/v1/me/gst?session=" + SESSION).getBody().get("entitlement")).get("state")).isEqualTo("NOT_PAID");

        // staged: on the record, still nothing on the ledger
        ResponseEntity<Map> staged = it.call(bursar, HttpMethod.POST, "/api/v1/finance/legacy-gst/imports", Map.of("rows", file(), "fileName", "old-gst.xlsx", "session", SESSION));
        assertThat(staged.getStatusCode().value()).as(String.valueOf(staged.getBody())).isEqualTo(200);
        Map<String, Object> imp = m(staged.getBody().get("import"));
        String importId = String.valueOf(imp.get("id"));
        assertThat(String.valueOf(imp.get("reference"))).startsWith("GST-MIGRATION-2119-2120-");
        assertThat(imp.get("status")).isEqualTo("STAGED");
        assertThat(m(it.get(tokenA, "/api/v1/me/gst?session=" + SESSION).getBody().get("entitlement")).get("state")).isEqualTo("NOT_PAID");
        List<Map<String, Object>> rows = l(staged.getBody().get("rows"));
        Map<String, Object> tx1 = rows.stream().filter(r -> tag("TX1").equals(r.get("source_transaction_id"))).findFirst().orElseThrow();
        assertThat(tx1.get("status")).isEqualTo("MATCHED");
        assertThat(tx1.get("match_method")).isEqualTo("MATRIC_NO");
        assertThat(tx1.get("match_confidence")).isEqualTo("HIGH");
        assertThat(new BigDecimal(String.valueOf(tx1.get("fee_amount")))).isEqualByComparingTo("20000");
        Map<String, Object> tx5 = rows.stream().filter(r -> tag("TX5").equals(r.get("source_transaction_id"))).findFirst().orElseThrow();
        assertThat(tx5.get("status")).isEqualTo("MATCHED");
        assertThat(new BigDecimal(String.valueOf(tx5.get("fee_amount")))).as("the historical fee of that session, not today's").isEqualByComparingTo("15000");
        assertThat(rows.stream().filter(r -> tag("TX2").equals(r.get("source_transaction_id"))).findFirst().orElseThrow().get("reason_code")).isEqualTo("PAYMENT_FAILED");
        assertThat(rows.stream().filter(r -> tag("TX3").equals(r.get("source_transaction_id"))).findFirst().orElseThrow().get("reason_code")).isEqualTo("PAYMENT_REFUNDED");
        assertThat(rows.stream().filter(r -> tag("TX4").equals(r.get("source_transaction_id"))).findFirst().orElseThrow().get("reason_code")).isEqualTo("EXISTING_ENTITLEMENT");
        assertThat(rows.stream().filter(r -> tag("TX6").equals(r.get("source_transaction_id"))).findFirst().orElseThrow().get("reason_code")).isEqualTo("PARTIAL_PAYMENT");
        Map<String, Object> tx7 = rows.stream().filter(r -> tag("TX7").equals(r.get("source_transaction_id"))).findFirst().orElseThrow();
        assertThat(tx7.get("status")).isEqualTo("UNMATCHED");
        assertThat(l(tx7.get("candidates"))).as("two students share the name: suggestions, never a match").hasSize(2);
        assertThat(rows.stream().filter(r -> tag("TX8").equals(r.get("source_transaction_id"))).findFirst().orElseThrow().get("reason_code")).isEqualTo("UNKNOWN_PAYMENT_TYPE");
        assertThat(rows.stream().filter(r -> tag("TX9").equals(r.get("source_transaction_id"))).findFirst().orElseThrow().get("reason_code")).isEqualTo("INVALID_SESSION");
        // the raw row is written once
        String rawGuard = it.db(() -> { try { jdbc.sql("UPDATE finance.legacy_gst_payment SET amount = 1 WHERE id = :id").param("id", UUID.fromString(String.valueOf(tx1.get("id")))).update(); return "allowed"; } catch (RuntimeException ex) { return ex.getMessage(); } });
        assertThat(rawGuard).contains("LEGACY_PAYMENT_WRITTEN_ONCE");

        // applied: the ledger carries the old reference and the old date; the student reads PAID from the old portal; the gate opens; EPS is covered
        ResponseEntity<Map> applied = it.call(bursar, HttpMethod.POST, "/api/v1/finance/legacy-gst/imports/" + importId + "/apply", Map.of());
        assertThat(applied.getStatusCode().value()).as(String.valueOf(applied.getBody())).isEqualTo(200);
        assertThat(((Number) m(applied.getBody().get("applied")).get("reconciled")).intValue()).isEqualTo(2);
        assertThat(new BigDecimal(String.valueOf(m(applied.getBody().get("applied")).get("amount")))).isEqualByComparingTo("35000");
        Map<String, Object> ent = m(it.get(tokenA, "/api/v1/me/gst?session=" + SESSION).getBody().get("entitlement"));
        assertThat(ent.get("state")).isEqualTo("PAID");
        assertThat(ent.get("entitled")).isEqualTo(true);
        assertThat(ent.get("covers_eps")).isEqualTo(true);
        assertThat(ent.get("source")).isEqualTo("LEGACY_PORTAL");
        assertThat(ent.get("legacy_reference")).isEqualTo(tag("OLD-GST-000123"));
        assertThat(String.valueOf(ent.get("reference"))).startsWith("MOAUM-LEG-GST-");
        assertThat(String.valueOf(ent.get("paid_at"))).startsWith("2119-09-15");
        assertThat(it.call(tokenA, HttpMethod.POST, "/api/v1/me/gst/reference", Map.of("session", SESSION)).getBody().get("code")).as("not asked to pay again").isEqualTo("GST_ALREADY_PAID");
        assertThat(m(it.get(tokenA, "/api/v1/me/gst?session=" + PREVIOUS).getBody().get("entitlement")).get("state")).as("last session's payment stands for last session").isEqualTo("PAID");
        ResponseEntity<Map> reg = it.call(tokenA, HttpMethod.PUT, "/api/v1/me/registration", Map.of("session", SESSION, "semester", 1, "offerings", List.of(offering)));
        assertThat(reg.getStatusCode().value()).as(String.valueOf(reg.getBody())).isEqualTo(200);
        // applied again: nothing more
        assertThat(((Number) m(it.call(bursar, HttpMethod.POST, "/api/v1/finance/legacy-gst/imports/" + importId + "/apply", Map.of()).getBody().get("applied")).get("reconciled")).intValue()).isEqualTo(0);
        long ledgerRows = jdbc.sql("SELECT count(*) FROM finance.payment_reference WHERE student_id = :s AND purpose LIKE 'GST fee %'").param("s", a).query(Long.class).single();
        assertThat(ledgerRows).isEqualTo(2);
        // the same file staged again: every old payment already staged, nothing new
        Map<String, Object> again = it.call(bursar, HttpMethod.POST, "/api/v1/finance/legacy-gst/imports", Map.of("rows", file(), "fileName", "old-gst.xlsx")).getBody();
        assertThat(((Number) m(again.get("staging")).get("staged")).intValue()).isEqualTo(0);
        assertThat(((Number) m(again.get("staging")).get("already_staged")).intValue()).isEqualTo(10);

        // the CBT eligibility reads the same answer: A, registered and reconciled, may sit; D, unpaid, may not
        it.db(() -> jdbc.sql("UPDATE registration.course_registration SET status = 'SUBMITTED', submitted_at = now() WHERE student_id = :s AND session = :ses").param("s", a).param("ses", SESSION).update());
        UUID exam = it.db(() -> jdbc.sql("""
                SELECT (assessment.cbt_new_exam('GST', :o, 'Legacy check', NULL, 30, 0, 'FIXED', false, false, 50, 1, 'STANDARD', 'REMOTE', 2, 'WARN', 'CONTINUE', now() - interval '1 minute', now() + interval '1 hour')).id
                """).param("o", offering).query(UUID.class).single());
        it.db(() -> {
            UUID q = jdbc.sql("INSERT INTO assessment.question (course_code, stem, options, answer, kind, marks) VALUES (:c, 'legacy q', '[\"a\",\"b\"]', 0, 'MCQ', 1) RETURNING id").param("c", code).query(UUID.class).single();
            // V374: approved by a moderator (someone other than its setter) before it goes on a paper
            jdbc.sql("UPDATE assessment.question SET moderation = 'APPROVED', moderated_version = version, moderated_by = gen_random_uuid(), moderated_at = now() WHERE id = :q").param("q", q).update();
            jdbc.sql("INSERT INTO assessment.cbt_exam_question (exam_id, question_id, ordinal) VALUES (:e, :q, 1)").param("e", exam).param("q", q).update();
            jdbc.sql("UPDATE assessment.cbt_exam SET state = 'PUBLISHED', published_at = now() WHERE id = :e").param("e", exam).update();
            return null;
        });
        assertThat(jdbc.sql("SELECT assessment.cbt_eligibility(:e, :s)").param("e", exam).param("s", a).query(String.class).optional().orElse(null)).isNull();
        assertThat(jdbc.sql("SELECT assessment.cbt_eligibility(:e, :s)").param("e", exam).param("s", d).query(String.class).single()).startsWith("CBT_COURSE_NOT_REGISTERED");

        // the queue: the partial payment reconciled with an override; the unmatched row cannot be moved onto A (A's number is on other rows? no — the guard is on the row's own identifiers)
        String tx6 = String.valueOf(rows.stream().filter(r -> tag("TX6").equals(r.get("source_transaction_id"))).findFirst().orElseThrow().get("id"));
        String tx7id = String.valueOf(tx7.get("id"));
        assertThat(it.call(bursar, HttpMethod.POST, "/api/v1/finance/legacy-gst/rows/" + tx6 + "/reconcile", Map.of("reason", "")).getBody().get("code")).isEqualTo("LEGACY_REASON_REQUIRED");
        ResponseEntity<Map> partial = it.call(bursar, HttpMethod.POST, "/api/v1/finance/legacy-gst/rows/" + tx6 + "/reconcile", Map.of("reason", "Bursar approved the concession, memo BUR/2119/77"));
        assertThat(partial.getStatusCode().value()).as(String.valueOf(partial.getBody())).isEqualTo(200);
        assertThat(m(partial.getBody().get("row")).get("status")).isEqualTo("RECONCILED");
        assertThat(m(it.get(tokenD, "/api/v1/me/gst?session=" + SESSION).getBody().get("entitlement")).get("state")).isEqualTo("PAID");
        // a row whose matriculation number names B cannot be matched by hand to E: ownership is never moved by guesswork
        String tx4 = String.valueOf(rows.stream().filter(r -> tag("TX4").equals(r.get("source_transaction_id"))).findFirst().orElseThrow().get("id"));
        ResponseEntity<Map> steal = it.call(bursar, HttpMethod.POST, "/api/v1/finance/legacy-gst/rows/" + tx4 + "/match", Map.of("studentId", e, "reason", "guessing"));
        assertThat(steal.getBody().get("code")).isEqualTo("LEGACY_IDENTIFIER_CONFLICT");
        // the unmatched row matched by hand to E after verification, then reconciled; its old id would go on the crosswalk had it carried one
        ResponseEntity<Map> matched = it.call(bursar, HttpMethod.POST, "/api/v1/finance/legacy-gst/rows/" + tx7id + "/match", Map.of("studentId", e, "reason", "verified against the bank statement of 16 Sep"));
        assertThat(matched.getStatusCode().value()).as(String.valueOf(matched.getBody())).isEqualTo(200);
        assertThat(m(matched.getBody().get("row")).get("match_method")).isEqualTo("MANUAL");
        assertThat(m(matched.getBody().get("row")).get("status")).isEqualTo("MATCHED");
        assertThat(m(it.call(bursar, HttpMethod.POST, "/api/v1/finance/legacy-gst/rows/" + tx7id + "/reconcile", Map.of("reason", "as verified")).getBody().get("row")).get("status")).isEqualTo("RECONCILED");
        assertThat(it.call(gst, HttpMethod.POST, "/api/v1/finance/legacy-gst/rows/" + tx7id + "/reject", Map.of("reason", "no")).getStatusCode().value()).isEqualTo(403);

        // the summary: counts and amounts that must agree, the variance explained by the duplicate and the rejections
        Map<String, Object> summary = m(it.get(bursar, "/api/v1/finance/legacy-gst/summary?session=" + SESSION).getBody().get("summary"));
        assertThat(((Number) summary.get("reconciled")).intValue()).isGreaterThanOrEqualTo(3);
        assertThat(l(it.get(bursar, "/api/v1/finance/legacy-gst/rows?status=OPEN&session=" + SESSION + "&q=-" + n).getBody().get("rows"))).isEmpty();
        assertThat(((Number) it.get(bursar, "/api/v1/finance/legacy-gst/rows?status=REJECTED&q=-" + n).getBody().get("total")).intValue()).isEqualTo(4);
        // the GST dashboard splits the paid by source
        Map<String, Object> dash = it.get(gst, "/api/v1/gst/GST/dashboard?session=" + SESSION + "&prog=" + PROGRAMME).getBody();
        assertThat(((Number) m(dash.get("totals")).get("paid_legacy")).intValue()).isGreaterThanOrEqualTo(3);
        assertThat(((Number) m(dash.get("totals")).get("paid_current")).intValue()).isGreaterThanOrEqualTo(1);
        assertThat(((Number) m(dash.get("legacy")).get("reconciled")).intValue()).isGreaterThanOrEqualTo(3);
        Map<String, Object> list = it.get(gst, "/api/v1/gst/GST/students?session=" + SESSION + "&q=ZZLGA" + n).getBody();
        assertThat(l(list.get("rows"))).anySatisfy(r -> { assertThat(r.get("pay_state")).isEqualTo("PAID"); assertThat(r.get("pay_source")).isEqualTo("LEGACY_PORTAL"); });
    }

    @Test
    void theSameMoneyAlreadyOnTheLedgerAsSchoolFeesIsRelabelledNotDoubled() {
        // the Old Fees History import put B's 20,000 of 16 Sep on the ledger as school fees
        it.db(() -> jdbc.sql("""
                INSERT INTO finance.payment_reference (student_id, session, reference, purpose, amount, expires_at, confirmed_at, confirmed_by, channel, receipt_no, note)
                VALUES (:s, :ses, :r, 'School fees (legacy)', 20000, '2119-09-16', '2119-09-16', gen_random_uuid(), 'Legacy', :rc, 'Imported from the old portal')
                """).param("s", b).param("ses", SESSION).param("r", "MOAUM-LEG-" + matricB.replaceAll("[^0-9A-Z]", "") + "-2119-2120").param("rc", "LEG-MOAUM-LEG-" + matricB.replaceAll("[^0-9A-Z]", "") + "-2119-2120").update());
        Map<String, Object> staged = it.call(bursar, HttpMethod.POST, "/api/v1/finance/legacy-gst/imports", Map.of("rows", List.of(
                row(tag("TXR"), tag("OLD-GST-000200"), matricB, null, null, "GST", "20000", "2119-09-16", SESSION, "SUCCESS")), "fileName", "relabel.csv")).getBody();
        Map<String, Object> r = l(staged.get("rows")).get(0);
        assertThat(r.get("status")).isEqualTo("REQUIRES_REVIEW");
        assertThat(r.get("reason_code")).isEqualTo("POSSIBLE_RELABEL");
        // applying writes nothing for a row under review
        assertThat(((Number) m(it.call(bursar, HttpMethod.POST, "/api/v1/finance/legacy-gst/imports/" + m(staged.get("import")).get("id") + "/apply", Map.of()).getBody().get("applied")).get("reconciled")).intValue()).isEqualTo(0);
        // relabelled: the school-fees row becomes the GST fee; one ledger row, not two; B reads PAID from the old portal
        ResponseEntity<Map> relabel = it.call(bursar, HttpMethod.POST, "/api/v1/finance/legacy-gst/rows/" + r.get("id") + "/relabel", Map.of("reason", "the 16 Sep 20,000 was the GST fee, bank narration says GST"));
        assertThat(relabel.getStatusCode().value()).as(String.valueOf(relabel.getBody())).isEqualTo(200);
        assertThat(m(relabel.getBody().get("row")).get("status")).isEqualTo("RECONCILED");
        assertThat(m(relabel.getBody().get("row")).get("reason_code")).isEqualTo("RELABELLED");
        assertThat(jdbc.sql("SELECT count(*) FROM finance.payment_reference WHERE student_id = :s AND session = :ses AND confirmed_at IS NOT NULL").param("s", b).param("ses", SESSION).query(Long.class).single()).isEqualTo(1);
        assertThat(jdbc.sql("SELECT purpose FROM finance.payment_reference WHERE student_id = :s AND session = :ses").param("s", b).param("ses", SESSION).query(String.class).single()).isEqualTo("GST fee " + SESSION);
        Map<String, Object> ent = m(it.get(TestTokens.token(b, List.of("student")), "/api/v1/me/gst?session=" + SESSION).getBody().get("entitlement"));
        assertThat(ent.get("state")).isEqualTo("PAID");
        assertThat(ent.get("source")).isEqualTo("LEGACY_PORTAL");
    }
}
