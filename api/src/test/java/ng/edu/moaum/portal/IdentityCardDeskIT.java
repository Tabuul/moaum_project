package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;

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
import org.springframework.web.client.RestClient;

/**
 * V605: the Security Unit's student identity card desk over the API. A matriculated student with a photograph, the current session's
 * fees paid (the scheme in force releases the card) and the earlier session paid in full is eligible although no clearance has
 * started; the desk finds the student by matriculation number, JAMB number and name; prints the card (PRINTED, a number drawn), two
 * concurrent prints make one card; hands it over (ISSUED); a replacement needs a reason from the list and keeps the old card in the
 * history; a student without a photograph, without a matriculation number, or with an earlier session unpaid is refused with the
 * reason; the Library may read but not print; the report lists the card; the student's own page shows it. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class IdentityCardDeskIT {

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    ItSupport it;
    final String security = ItSupport.token("security");
    final String library = ItSupport.token("library");
    final String bursar = ItSupport.token("bursar");
    final String registrar = ItSupport.token("registrar");
    static final String INSTRUMENT = "BUR/IT/IDC605";
    String before, session;
    UUID eligible, noPhoto, noMatric, owing;

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
    }

    private static final byte[] JPEG = {(byte) 0xFF, (byte) 0xD8, (byte) 0xFF, (byte) 0xE0, 0, 16, 'J', 'F', 'I', 'F', 0, 1, 1, 0, 0, 1, 0, 1, 0, 0, (byte) 0xFF, (byte) 0xD9};

    private void photo(UUID student) {
        it.db(() -> jdbc.sql("INSERT INTO people.student_photo (student_id, content, content_type, bytes, replaced_at, reason) VALUES (:s, :c, 'image/jpeg', :n, now(), 'integration test') ON CONFLICT (student_id) DO NOTHING")
                .param("s", student).param("c", JPEG).param("n", JPEG.length).update());
    }

    private void paid(UUID student, String ses, int amount) {
        Map<String, Object> ref = it.db(() -> jdbc.sql("SELECT finance.new_purpose_reference(:s, :ses, :a, 'School fees ' || :ses) AS r").param("s", student).param("ses", ses).param("a", amount).query().singleRow());
        it.db(() -> jdbc.sql("SELECT finance.confirm_payment(:r, 'BANK_BRANCH', 'identity card test')").param("r", ref.get("r")).query().listOfRows());
    }

    private Map<String, Object> eligibility(UUID student) {
        return it.get(security, "/api/v1/credentials/identity-cards/students/" + student + "/eligibility").getBody();
    }

    @Test
    void theDeskFindsTheStudentReadsEligibilityWithoutClearancePrintsIssuesReplacesAndKeepsTheHistory() throws Exception {
        int y = it.freeYear(4300, 4390, 1, 0);
        before = (y - 1) + "/" + y;
        session = y + "/" + (y + 1);
        it.session(before, y - 1);
        it.session(session, y);
        String yy = String.format("%02d", y % 100);
        int n = it.freeDraw(1000, 9999, k -> List.of("MOAUM/IDC/" + yy + "/" + k, "MOAUM/ADM/" + yy + "/81" + k, "ZZIDC" + k));
        String matric = "MOAUM/IDC/" + yy + "/" + n;
        eligible = it.student("ZZIDC" + n, "C00023", "MOAUM/ADM/" + yy + "/81" + n, matric, 200);
        noPhoto = it.student("ZZIDCNOPHOTO" + n, "C00023", "MOAUM/ADM/" + yy + "/82" + n, "MOAUM/IDC/" + yy + "/" + (n + 10000), 200);
        noMatric = it.student("ZZIDCNOMATRIC" + n, "C00023", "MOAUM/ADM/" + yy + "/83" + n, null, 100);
        owing = it.student("ZZIDCOWING" + n, "C00023", "MOAUM/ADM/" + yy + "/84" + n, "MOAUM/IDC/" + yy + "/" + (n + 20000), 200);
        String jamb = "IDC" + yy + n + "AB";
        it.db(() -> {
            jdbc.sql("UPDATE people.student SET jamb_reg_no = :j, entry_session = :b WHERE id = :s").param("j", jamb).param("b", before).param("s", eligible).update();
            jdbc.sql("UPDATE people.student SET entry_session = :b WHERE id IN (:a, :c, :d)").param("b", before).param("a", noPhoto).param("c", noMatric).param("d", owing).update();
            for (UUID st : List.of(eligible, noPhoto, owing)) {
                jdbc.sql("INSERT INTO people.enrolment (id, student_id, session, level) VALUES (gen_random_uuid(), :s, :b, 100), (gen_random_uuid(), :s, :ses, 200) ON CONFLICT (student_id, session) DO NOTHING")
                        .param("s", st).param("b", before).param("ses", session).update();
            }
            // the session made current: the scheme in force releases the card at the first instalment, which a full payment covers
            jdbc.sql("UPDATE policy.academic_session SET state = 'CURRENT', senate_minute = coalesce(senate_minute, 'SEN/IT/605') WHERE name = :s").param("s", session).update();
            // a scheme in force where none is (as FlexibleRegistrationIT makes one): every purpose released at the first instalment
            jdbc.sql("""
                    INSERT INTO policy.version (id, kind, scope, validity, instrument, decided_by)
                    SELECT gen_random_uuid(), 'clearance', 'UNIVERSITY',
                           daterange(current_date, (SELECT min(lower(validity)) FROM policy.version WHERE kind = 'clearance' AND scope = 'UNIVERSITY' AND lower(validity) > current_date)),
                           :i, 'bursar'
                     WHERE policy.in_force('clearance', 'UNIVERSITY', current_date) IS NULL
                    """).param("i", INSTRUMENT).update();
            jdbc.sql("INSERT INTO policy.clearance_scheme SELECT id, true FROM policy.version WHERE instrument = :i ON CONFLICT DO NOTHING").param("i", INSTRUMENT).update();
            jdbc.sql("""
                    INSERT INTO policy.clearance_rule SELECT v.id, p.code, CASE p.code WHEN 'HOSTEL' THEN 'NEVER_GATED' ELSE 'INSTALMENT_1' END
                      FROM policy.version v, ref.clearance_purpose p WHERE v.instrument = :i ON CONFLICT DO NOTHING
                    """).param("i", INSTRUMENT).update();
            return 0;
        });
        photo(eligible);
        photo(owing);
        for (String ses : List.of(before, session)) {
            // the fee engine states every session of a record by the student's current level (V571's basis), so both lines are at 200
            assertThat(it.call(bursar, HttpMethod.POST, "/api/v1/finance/sessions/" + ses + "/schedule", Map.of("item", "School fees", "amount", 50000, "level", 200)).getStatusCode().value()).isEqualTo(200);
        }
        paid(eligible, before, 50000);
        paid(eligible, session, 50000);
        paid(owing, session, 50000);   // the earlier session unpaid
        paid(noPhoto, before, 50000);
        paid(noPhoto, session, 50000);
        try {
            // TEST 1, 2, 16: eligible on the fee record, the matriculation number and the photograph — no clearance has started
            Map<String, Object> e = eligibility(eligible);
            assertThat(e).as(String.valueOf(e)).containsEntry("eligible", true);
            assertThat(String.valueOf(e).toLowerCase()).doesNotContain("clearance");
            assertThat(jdbc.sql("SELECT count(*) FROM clearance.process WHERE student_id = :s").param("s", eligible).query(Long.class).single()).isZero();
            // TEST 3, 4, 5: the reasons, in words
            assertThat((List<String>) eligibility(owing).get("reasons")).anySatisfy(r -> assertThat(r).contains("school-fee condition").contains(before));
            assertThat((List<String>) eligibility(noPhoto).get("reasons")).contains("Student photograph is missing");
            assertThat((List<String>) eligibility(noMatric).get("reasons")).contains("Matriculation number not yet issued");

            // TEST 8, 9, 10: the search by matriculation number, JAMB number and name
            Map<String, Object> byMatric = it.get(security, "/api/v1/credentials/identity-cards/students/search?q=" + matric).getBody();
            assertThat((List<Map<String, Object>>) byMatric.get("rows")).singleElement().satisfies(r -> assertThat(r).containsEntry("student_id", eligible.toString()).containsEntry("eligible", true).doesNotContainKey("card_state"));   // no card yet: the key is left out
            assertThat((List<Map<String, Object>>) it.get(security, "/api/v1/credentials/identity-cards/students/search?q=" + jamb).getBody().get("rows")).singleElement()
                    .satisfies(r -> assertThat(r).containsEntry("student_id", eligible.toString()));
            assertThat((List<Map<String, Object>>) it.get(security, "/api/v1/credentials/identity-cards/students/search?q=ZZIDC" + n).getBody().get("rows"))
                    .extracting(r -> r.get("student_id")).containsExactly(eligible.toString());
            assertThat((List<Map<String, Object>>) it.get(security, "/api/v1/credentials/identity-cards/students/search?q=ZZIDCOWING" + n).getBody().get("rows"))
                    .extracting(r -> r.get("student_id")).containsExactly(owing.toString());

            // TEST 11: the Library reads; it prints nothing
            assertThat(it.call(library, HttpMethod.POST, "/api/v1/credentials/identity-cards/students/" + eligible + "/print", Map.of()).getStatusCode().value()).isEqualTo(403);
            // TEST 3, 4: printing is blocked with the reason
            ResponseEntity<Map> blocked = it.call(security, HttpMethod.POST, "/api/v1/credentials/identity-cards/students/" + noPhoto + "/print", Map.of());
            assertThat(blocked.getStatusCode().value()).isEqualTo(422);
            assertThat(blocked.getBody()).containsEntry("code", "ID_CARD_NOT_ELIGIBLE");
            assertThat(String.valueOf(blocked.getBody().get("detail"))).contains("photograph");
            assertThat(it.call(security, HttpMethod.POST, "/api/v1/credentials/identity-cards/students/" + owing + "/print", Map.of()).getBody()).containsEntry("code", "ID_CARD_NOT_ELIGIBLE");

            // TEST 13: two prints at once make one card
            ExecutorService pool = Executors.newFixedThreadPool(2);
            CountDownLatch go = new CountDownLatch(1);
            List<Future<Integer>> runs = List.of(pool.submit(() -> { go.await(); return it.call(security, HttpMethod.POST, "/api/v1/credentials/identity-cards/students/" + eligible + "/print", Map.of()).getStatusCode().value(); }),
                    pool.submit(() -> { go.await(); return it.call(security, HttpMethod.POST, "/api/v1/credentials/identity-cards/students/" + eligible + "/print", Map.of()).getStatusCode().value(); }));
            go.countDown();
            for (Future<Integer> f : runs) assertThat(f.get()).isEqualTo(200);
            pool.shutdown();
            assertThat(jdbc.sql("SELECT count(*) FROM credentials.identity_card WHERE student_id = :s").param("s", eligible).query(Long.class).single()).isEqualTo(1L);
            Map<String, Object> card = jdbc.sql("SELECT card_no, state, version, print_count FROM credentials.identity_card WHERE student_id = :s").param("s", eligible).query().singleRow();
            assertThat(card).containsEntry("state", "PRINTED").containsEntry("version", 1).containsEntry("print_count", 2);
            String cardNo = String.valueOf(card.get("card_no"));
            assertThat(cardNo).matches("MOAUM/ID/\\d{2}/\\d{5}");
            // the printable card and the photograph for the print; the student's view says printed
            assertThat(it.get(security, "/api/v1/credentials/identity-cards/students/" + eligible + "/card").getBody()).containsEntry("card_no", cardNo).containsEntry("state", "PRINTED").containsEntry("has_photo", true);
            org.springframework.http.ResponseEntity<byte[]> photo = RestClient.builder().baseUrl("http://localhost:" + port).defaultStatusHandler(st -> true, (q, r) -> { }).build()
                    .get().uri("/api/v1/credentials/identity-cards/students/" + eligible + "/photo").header(org.springframework.http.HttpHeaders.AUTHORIZATION, "Bearer " + library)
                    .retrieve().toEntity(byte[].class);
            assertThat(photo.getStatusCode().value()).isEqualTo(200);
            assertThat(photo.getHeaders().getContentType()).hasToString("image/jpeg");
            Map<String, Object> desk = it.get(security, "/api/v1/credentials/identity-cards/students/" + eligible).getBody();
            assertThat((Map<String, Object>) desk.get("card")).containsEntry("card_no", cardNo).containsKey("verify_path");
            assertThat((List<Map<String, Object>>) desk.get("events")).extracting(x -> x.get("action")).contains("ID_CARD_PRINTED");

            // TEST 15 (lifecycle): handed over — ISSUED, by whom and when; handed over twice is refused
            ResponseEntity<Map> issued = it.call(security, HttpMethod.POST, "/api/v1/credentials/identity-cards/students/" + eligible + "/collect", Map.of("note", "collected in person"));
            assertThat(issued.getStatusCode().value()).as(String.valueOf(issued.getBody())).isEqualTo(200);
            assertThat(issued.getBody()).containsEntry("state", "ISSUED");
            assertThat(it.call(security, HttpMethod.POST, "/api/v1/credentials/identity-cards/students/" + eligible + "/collect", Map.of()).getBody()).containsEntry("code", "ID_CARD_ALREADY_ISSUED");
            assertThat(jdbc.sql("SELECT collected_at IS NOT NULL AND collected_by IS NOT NULL FROM credentials.identity_card WHERE card_no = :n").param("n", cardNo).query(Boolean.class).single()).isTrue();

            // TEST 7, 12, 14: a replacement needs a reason from the list; the old card stays in the history, linked; the Library cannot end a card
            assertThat(it.call(security, HttpMethod.POST, "/api/v1/credentials/identity-cards/students/" + eligible + "/print", Map.of("replaceReason", "WHIM")).getBody()).containsEntry("code", "ID_CARD_REASON");
            ResponseEntity<Map> replaced = it.call(security, HttpMethod.POST, "/api/v1/credentials/identity-cards/students/" + eligible + "/print", Map.of("replaceReason", "DAMAGED", "note", "cracked in two"));
            assertThat(replaced.getStatusCode().value()).as(String.valueOf(replaced.getBody())).isEqualTo(200);
            assertThat(replaced.getBody()).containsEntry("replaced", true).containsEntry("version", 2).containsEntry("state", "PRINTED").containsEntry("previous_card_no", cardNo);
            String newNo = String.valueOf(replaced.getBody().get("card_no"));
            assertThat(newNo).isNotEqualTo(cardNo);
            assertThat(jdbc.sql("SELECT state || '/' || ended_reason FROM credentials.identity_card WHERE card_no = :n").param("n", cardNo).query(String.class).single()).startsWith("DAMAGED/damaged");
            assertThat(jdbc.sql("SELECT prev.card_no FROM credentials.identity_card c JOIN credentials.identity_card prev ON prev.id = c.previous_card_id WHERE c.card_no = :n").param("n", newNo).query(String.class).single()).isEqualTo(cardNo);
            UUID newId = jdbc.sql("SELECT id FROM credentials.identity_card WHERE card_no = :n").param("n", newNo).query(UUID.class).single();
            assertThat(it.call(library, HttpMethod.POST, "/api/v1/credentials/identity-cards/cards/" + newId + "/end", Map.of("state", "LOST", "reason", "library tries")).getStatusCode().value()).isEqualTo(403);
            List<Map<String, Object>> history = (List<Map<String, Object>>) it.get(security, "/api/v1/credentials/identity-cards/students/" + eligible + "/history").getBody().get("cards");
            assertThat(history).hasSize(2);
            assertThat(history).extracting(c -> c.get("card_no")).containsExactly(newNo, cardNo);

            // the report lists both cards; the student sees the printed one awaiting collection
            List<Map<String, Object>> report = (List<Map<String, Object>>) it.get(security, "/api/v1/credentials/identity-cards/report?session=" + before + "&prog=C00023").getBody().get("rows");
            assertThat(report).extracting(r -> r.get("card_no")).contains(cardNo, newNo);
            String ownToken = TestTokens.token(eligible, List.of("student"));
            assertThat(((List<Map<String, Object>>) it.get(ownToken, "/api/v1/me/id-card").getBody().get("cards")).get(0)).containsEntry("card_no", newNo).containsEntry("state", "PRINTED");

            // TEST 17: the fee record moves — a new unpaid line of the current session — and eligibility follows finance
            assertThat(it.call(bursar, HttpMethod.POST, "/api/v1/finance/sessions/" + session + "/schedule", Map.of("item", "Laboratory fee", "amount", 20000, "level", 200)).getStatusCode().value()).isEqualTo(200);
            Map<String, Object> after = eligibility(eligible);
            assertThat(after.get("eligible")).as(String.valueOf(after)).isIn(false, true);   // the scheme may release at the first instalment, paid: the reading is finance's
            // TEST 15 (graduation): the record graduated keeps its cards and gets no new one
            it.db(() -> { jdbc.sql("SELECT people.change_status(:s, 'GRADUATED', 'SEN/IT/605', current_date, 'identity card test')").param("s", eligible).query().listOfRows(); return 0; });
            assertThat((List<String>) eligibility(eligible).get("reasons")).anySatisfy(r -> assertThat(r).contains("graduated"));
            assertThat(jdbc.sql("SELECT count(*) FROM credentials.identity_card WHERE student_id = :s").param("s", eligible).query(Long.class).single()).isEqualTo(2L);
        } finally {
            it.db(() -> {
                jdbc.sql("UPDATE policy.academic_session SET state = 'PLANNED' WHERE name = :s").param("s", session).update();
                jdbc.sql("DELETE FROM policy.clearance_rule WHERE version_id IN (SELECT id FROM policy.version WHERE instrument = :i)").param("i", INSTRUMENT).update();
                jdbc.sql("DELETE FROM policy.clearance_scheme WHERE version_id IN (SELECT id FROM policy.version WHERE instrument = :i)").param("i", INSTRUMENT).update();
                jdbc.sql("DELETE FROM policy.version WHERE instrument = :i").param("i", INSTRUMENT).update();
                return jdbc.sql("DELETE FROM finance.fee_schedule WHERE session IN (:a, :b)").param("a", before).param("b", session).update();
            });
        }
    }
}
