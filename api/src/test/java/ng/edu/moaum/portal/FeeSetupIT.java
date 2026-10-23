package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.HashMap;
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
 * V648: the school fees setup, edit and remove, through the API. A made-up session with lines for Computer Science (100 to 400 Level):
 * a 600 Level line is refused as outside the programme structure, and one put there by mistake is flagged; the database decides use —
 * the 600 Level line never used is removed permanently, the 300 Level line a student generated an invoice under and the 100 Level
 * line a student paid under are archived, never deleted; the reason is required; the Students Account Officer deactivates but does
 * not remove, the Registrar reads, a lecturer reads nothing; a line's history and the removed lines are read back; editing a line no
 * invoice was made under corrects it in place, editing one with an invoice versions it, and a duplicate or an invalid level is
 * refused; the invoice and the payment keep their amounts; an archived line charges nobody, the corrected line charges. Needs
 * DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class FeeSetupIT {

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    ItSupport it;
    String session;

    /** the lines the test states are taken away (FeeLineLeakGuard): a planned session with fees is a later test's default */
    @AfterEach
    void takeAwayFeeLines() {
        if (it != null && session != null) it.db(() -> jdbc.sql("DELETE FROM finance.fee_schedule WHERE session = :s").param("s", session).update());
    }

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
    }

    private UUID line(String session, String item, int amount, int level) {
        return it.db(() -> jdbc.sql("INSERT INTO finance.fee_schedule (session, item, amount, level, programme_code, semester) VALUES (:s, :i, :a, :l, 'C00023', 1) RETURNING id")
                .param("s", session).param("i", item).param("a", amount).param("l", level).query(UUID.class).single());
    }

    private static Map<String, Object> body(String item, int amount, Integer level, int semester) {
        Map<String, Object> m = new HashMap<>(Map.of("item", item, "amount", amount, "programmeCode", "C00023", "semester", semester));
        m.put("level", level);
        return m;
    }

    @Test
    void aLineNeverUsedIsRemovedOneUsedIsArchivedAndAnEditOfAnInvoicedLineIsVersioned() {
        int y = it.freeYear(7200, 7500);
        session = y + "/" + (y + 1);
        it.session(session, y);
        String path = "/api/v1/finance/sessions/" + y + "/" + (y + 1);
        String bursar = ItSupport.token("bursar");
        String sao = ItSupport.token("studentaccounts");

        // a level outside the programme structure is refused; one already there is flagged
        ResponseEntity<Map> outside = it.call(bursar, HttpMethod.POST, path + "/schedule", body("School fees", 99000, 600, 1));
        assertThat(outside.getStatusCode().value()).as(String.valueOf(outside.getBody())).isEqualTo(422);
        assertThat(outside.getBody()).containsEntry("code", "FEE_LEVEL_NOT_IN_STRUCTURE");
        UUID l600 = line(session, "School fees", 99000, 600);
        UUID l300 = line(session, "School fees", 93000, 300);
        UUID l100 = line(session, "School fees", 91000, 100);
        UUID l200 = line(session, "School fees", 92000, 200);
        List<Map<String, Object>> items = (List<Map<String, Object>>) it.get(bursar, path + "/schedule").getBody().get("items");
        assertThat(items).anySatisfy(i -> {
            assertThat(i.get("id")).isEqualTo(l600.toString());
            assertThat(String.valueOf(i.get("level_problem"))).contains("not 600 Level");
            assertThat(i).containsEntry("status", "ACTIVE");
        });
        assertThat(items).anySatisfy(i -> { assertThat(i.get("id")).isEqualTo(l300.toString()); assertThat(i.get("level_problem")).isNull(); });

        // an invoice under the 300 Level line; a payment under the 100 Level line
        String surname = it.freeSurname("ZZFEESETUP");
        UUID b = it.student(surname + "B", "C00023", it.freeNumber("MOAUM/ADM/72/", 6), it.freeNumber("MOAUM/FSU/72/", 6), 300);
        UUID c = it.student(surname + "C", "C00023", it.freeNumber("MOAUM/ADM/72/", 6), it.freeNumber("MOAUM/FSU/72/", 6), 100);
        String refB = "MOAUM-FEE-V648" + y + "B", refC = "MOAUM-FEE-V648" + y + "C";
        it.db(() -> jdbc.sql("""
                INSERT INTO finance.payment_reference (student_id, session, reference, purpose, amount, generated_at, expires_at, confirmed_at, confirmed_by, channel, receipt_no)
                VALUES (:b, :s, :rb, 'School fees ' || :s, 93000, clock_timestamp(), now() + interval '3 days', NULL, NULL, NULL, NULL),
                       (:c, :s, :rc, 'School fees ' || :s, 91000, clock_timestamp(), now() + interval '3 days', clock_timestamp(), gen_random_uuid(), 'Bank branch', :rc)
                """).param("b", b).param("c", c).param("s", session).param("rb", refB).param("rc", refC).update());

        // the database decides use
        List<Map<String, Object>> usage = (List<Map<String, Object>>) (List) it.getList(bursar, path + "/schedule/usage").getBody();
        Map<String, String> used = new HashMap<>();
        usage.forEach(u -> used.put(String.valueOf(u.get("line_id")), String.valueOf(u.get("used_by"))));
        assertThat(used).containsEntry(l600.toString(), "NONE").containsEntry(l300.toString(), "INVOICE").containsEntry(l100.toString(), "PAYMENT");

        // who may: the officer and the Registrar may not remove, a lecturer reads nothing
        Map<String, Object> perms = it.get(sao, "/api/v1/finance/fee-setup/permissions").getBody();
        assertThat((List<String>) perms.get("permissions")).contains("EDIT_FEE_STRUCTURE", "DEACTIVATE_FEE_STRUCTURE").doesNotContain("REMOVE_FEE_STRUCTURE");
        assertThat((List<String>) it.get(bursar, "/api/v1/finance/fee-setup/permissions").getBody().get("permissions")).contains("REMOVE_FEE_STRUCTURE");
        Map<String, Object> removal = new HashMap<>(Map.of("ids", List.of(l600, l300, l100), "mode", "AUTO", "reasonCode", "WRONG_LEVEL", "reason", "600 Level was added in error"));
        assertThat(it.call(sao, HttpMethod.POST, path + "/schedule/remove", removal).getStatusCode().value()).isEqualTo(403);
        assertThat(it.call(ItSupport.token("registrar"), HttpMethod.POST, path + "/schedule/remove", removal).getStatusCode().value()).isEqualTo(403);
        assertThat(it.get(ItSupport.token("lecturer"), path + "/schedule/usage").getStatusCode().value()).isEqualTo(403);

        // the preview, then: a reason is required; one used line cannot be removed and is unchanged
        Map<String, Object> preview = it.call(bursar, HttpMethod.POST, path + "/schedule/remove/preview", Map.of("ids", List.of(l600, l300, l100), "mode", "AUTO")).getBody();
        assertThat(preview).containsEntry("selected", 3).containsEntry("REMOVED", 1).containsEntry("ARCHIVED", 2);
        ResponseEntity<Map> noReason = it.call(bursar, HttpMethod.POST, path + "/schedule/remove", Map.of("ids", List.of(l600), "mode", "AUTO"));
        assertThat(noReason.getStatusCode().value()).isEqualTo(422);
        assertThat(noReason.getBody()).containsEntry("code", "FEE_REMOVE_REASON");
        Map<String, Object> cannot = it.call(bursar, HttpMethod.POST, path + "/schedule/remove", Map.of("ids", List.of(l300), "mode", "REMOVE", "reasonCode", "WRONG_LEVEL")).getBody();
        assertThat(cannot).containsEntry("CANNOT_REMOVE", 1);
        assertThat(String.valueOf(((List<Map<String, Object>>) cannot.get("rows")).get(0).get("message"))).contains("1 school-fees invoice generated").contains("deactivate");

        // removed or archived as its use decides
        ResponseEntity<Map> done = it.call(bursar, HttpMethod.POST, path + "/schedule/remove", removal);
        assertThat(done.getStatusCode().value()).as(String.valueOf(done.getBody())).isEqualTo(200);
        assertThat(done.getBody()).containsEntry("REMOVED", 1).containsEntry("ARCHIVED", 2);
        assertThat(jdbc.sql("SELECT count(*) FROM finance.fee_schedule WHERE id = :id").param("id", l600).query(Long.class).single()).isZero();
        assertThat(jdbc.sql("SELECT count(*) FROM finance.fee_schedule WHERE id IN (:a, :b) AND ended_at IS NOT NULL").param("a", l300).param("b", l100).query(Long.class).single()).isEqualTo(2L);
        // the invoice and the payment as they were; the archived line charges nobody
        assertThat(jdbc.sql("SELECT string_agg(reference || '=' || amount || '/' || (confirmed_at IS NOT NULL), ',' ORDER BY reference) FROM finance.payment_reference WHERE reference IN (:a, :b)")
                .param("a", refB).param("b", refC).query(String.class).single()).isEqualTo(refB + "=93000.00/false," + refC + "=91000.00/true");
        assertThat(jdbc.sql("SELECT count(*) FROM finance.charges(:c, :s) WHERE id = :l").param("c", c).param("s", session).param("l", l100).query(Long.class).single()).isZero();
        assertThat(jdbc.sql("SELECT reason FROM audit.entries WHERE subject_type = 'finance.fee_schedule' AND subject_id = :id AND action = 'DELETE'")
                .param("id", l600).query(String.class).single()).isEqualTo("Wrong level: 600 Level was added in error");

        // the history and the removed lines, read back
        List<Map<String, Object>> history = (List<Map<String, Object>>) (List) it.getList(bursar, path + "/schedule/" + l300 + "/history").getBody();
        assertThat(history).extracting(h -> h.get("action")).containsExactly("CREATED", "DEACTIVATED");
        assertThat(history.get(1).get("reason")).isEqualTo("Wrong level: 600 Level was added in error");
        List<Map<String, Object>> removed = (List<Map<String, Object>>) (List) it.getList(sao, path + "/schedule/removed").getBody();
        assertThat(removed).anySatisfy(r -> { assertThat(r.get("id")).isEqualTo(l600.toString()); assertThat(r).containsEntry("reason_words", "Wrong level").containsEntry("level", 600); });
        List<Map<String, Object>> archived = (List<Map<String, Object>>) it.get(bursar, path + "/schedule?status=ARCHIVED").getBody().get("items");
        assertThat(archived).extracting(i -> i.get("id")).contains(l300.toString(), l100.toString());

        // edit: a line no invoice was made under is corrected in place, by the officer
        ResponseEntity<Map> inPlace = it.call(sao, HttpMethod.PUT, path + "/schedule/" + l200, body("School fees", 95000, 200, 1));
        assertThat(inPlace.getStatusCode().value()).as(String.valueOf(inPlace.getBody())).isEqualTo(200);
        assertThat((Map<String, Object>) inPlace.getBody().get("edit")).containsEntry("outcome", "EDITED").containsEntry("line_id", l200.toString());
        // a level outside the structure, or a scope another line states, refused; the Registrar may not edit
        ResponseEntity<Map> badLevel = it.call(bursar, HttpMethod.PUT, path + "/schedule/" + l200, body("School fees", 95000, 500, 1));
        assertThat(badLevel.getBody()).containsEntry("code", "FEE_LEVEL_NOT_IN_STRUCTURE");
        UUID l400 = line(session, "School fees", 94000, 400);
        ResponseEntity<Map> twice = it.call(bursar, HttpMethod.PUT, path + "/schedule/" + l200, body("School fees", 95000, 400, 1));
        assertThat(twice.getBody()).containsEntry("code", "FEE_LINE_DUPLICATE");
        assertThat(it.call(ItSupport.token("registrar"), HttpMethod.PUT, path + "/schedule/" + l400, body("School fees", 1000, 400, 1)).getStatusCode().value()).isEqualTo(403);

        // a line with an invoice: ₦200,000 to ₦220,000 versioned — the invoice keeps ₦200,000, the corrected line charges
        UUID lUsed = line(session, "Development levy", 200000, 300);
        String refE = "MOAUM-FEE-V648" + y + "E";
        it.db(() -> jdbc.sql("INSERT INTO finance.payment_reference (student_id, session, reference, purpose, amount, generated_at, expires_at) VALUES (:b, :s, :r, 'School fees ' || :s, 200000, clock_timestamp(), now() + interval '3 days')")
                .param("b", b).param("s", session).param("r", refE).update());
        Map<String, Object> versioned = new HashMap<>(body("Development levy", 220000, 300, 1));
        versioned.put("reason", "Council approved the new amount");
        ResponseEntity<Map> ve = it.call(bursar, HttpMethod.PUT, path + "/schedule/" + lUsed, versioned);
        assertThat(ve.getStatusCode().value()).as(String.valueOf(ve.getBody())).isEqualTo(200);
        Map<String, Object> edit = (Map<String, Object>) ve.getBody().get("edit");
        assertThat(edit).containsEntry("outcome", "VERSIONED").containsEntry("previous_id", lUsed.toString());
        UUID corrected = UUID.fromString(String.valueOf(edit.get("line_id")));
        assertThat(jdbc.sql("SELECT amount FROM finance.payment_reference WHERE reference = :r").param("r", refE).query(java.math.BigDecimal.class).single()).isEqualByComparingTo("200000");
        assertThat(jdbc.sql("SELECT count(*) FROM finance.charges(:b, :s) WHERE id = :l AND amount = 220000").param("b", b).param("s", session).param("l", corrected).query(Long.class).single()).isEqualTo(1L);
        assertThat(jdbc.sql("SELECT count(*) FROM finance.charges(:b, :s) WHERE id = :l").param("b", b).param("s", session).param("l", lUsed).query(Long.class).single()).isZero();
        List<Map<String, Object>> versions = (List<Map<String, Object>>) (List) it.getList(bursar, path + "/schedule/" + corrected + "/history").getBody();
        assertThat(versions).extracting(h -> h.get("action")).containsExactly("CREATED", "REPLACED", "VERSIONED");
        assertThat(versions.get(2).get("reason")).isEqualTo("Council approved the new amount");
    }
}
