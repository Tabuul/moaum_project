package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.math.BigDecimal;
import java.util.ArrayList;
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
 * V651: postgraduate stages, cycles, extension, restart and stage-based fees, through the API. Made-up Masters students in far-future
 * sessions: a stage's fee structure stated in one step (Tuition and Bench fee for 800 B) reaches the 800 B student alone, a line for
 * 800 A the fresh student alone; the same structure again, a component twice, an undergraduate programme and a PhD stage on a Masters
 * programme are refused; a reading office states nothing; the school-fees reference names the stage it was raised under. A student
 * of M.Sc. Computer Science reconciled into cycle 1 by the PG Secretary, progressed to 800 B, the extension 800 C left to the Dean of
 * the PG School, a stage out of order refused, the cycle closed as exhausted; a restart requested and recommended by the Head of the
 * Department (another department's Head refused), refused to the Secretary and approved by the Dean: cycle 2 at 800 A, fresh, cycle 1
 * kept with its three stages. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class PgAcademicIT {

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    ItSupport it;
    final List<String> sessions = new ArrayList<>();

    /** the lines the test states are taken away (FeeLineLeakGuard): a planned session with fees is a later test's default */
    @AfterEach
    void takeAwayFeeLines() {
        if (it != null && !sessions.isEmpty()) {
            it.db(() -> jdbc.sql("DELETE FROM finance.fee_schedule WHERE session = ANY (string_to_array(:s, ','))").param("s", String.join(",", sessions)).update());
        }
    }

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
    }

    /** far-future sessions y/y+1 … for the test's own use */
    private List<String> sessions(int count) {
        int y = it.freeYear(7600, 7990, 0, count - 1);
        List<String> out = new ArrayList<>();
        for (int i = 0; i < count; i++) {
            String s = (y + i) + "/" + (y + i + 1);
            it.session(s, y + i);
            out.add(s);
        }
        sessions.addAll(out);
        return out;
    }

    /** an invented postgraduate student, ACTIVE at 800 Level from the session given */
    private UUID pgStudent(String surname, String programme, String entrySession) {
        UUID id = UUID.randomUUID();
        String adm = it.freeNumber("MOAUM/ADM/76/", 6), mat = it.freeNumber("MOAUM/PGC/76/", 6);
        it.db(() -> jdbc.sql("""
                INSERT INTO people.student (id, admission_no, matric_no, surname, other_names, programme_code, entry_mode, entry_session, entry_level,
                                            current_level, status, matriculated_at)
                VALUES (:id, :adm, :mat, :s, 'Invented', :p, 'POSTGRADUATE', :e, 800, 800, 'ACTIVE', now())
                """).param("id", id).param("adm", adm).param("mat", mat).param("s", surname).param("p", programme).param("e", entrySession).update());
        return id;
    }

    private static String path(String session) {
        return "/api/v1/finance/sessions/" + session;
    }

    /** an undergraduate programme no postgraduate student is on (another class may put one on C00023): a stage line there is refused */
    private String ugProgramme() {
        return jdbc.sql("""
                SELECT p.code FROM ref.programme p
                 WHERE p.category = 'UNDER GRADUATE' AND NOT coalesce(p.archived, false)
                   AND NOT EXISTS (SELECT 1 FROM people.student s WHERE s.programme_code = p.code AND s.entry_mode = 'POSTGRADUATE')
                 ORDER BY p.code LIMIT 1
                """).query(String.class).single();
    }

    private BigDecimal charged(UUID student, String session) {
        return jdbc.sql("SELECT coalesce(sum(c.amount), 0) FROM finance.charges(:st, :s) c").param("st", student).param("s", session).query(BigDecimal.class).single();
    }

    @Test
    void aStagesFeeStructureChargesOnlyItsStudentsAndTheReferenceNamesTheStage() {
        List<String> s = sessions(2);
        String bursar = ItSupport.token("bursar");
        String pgschool = ItSupport.token("pgschool");

        List<Map<String, Object>> stages = (List<Map<String, Object>>) (List) it.getList(bursar, "/api/v1/finance/pg-stages").getBody();
        assertThat(stages).anySatisfy(x -> {
            assertThat(x).containsEntry("code", "800B").containsEntry("label", "800 B — Year 2").containsEntry("category", "RETURNING").containsEntry("qualification", "MASTERS");
            assertThat(((Number) x.get("level")).intValue()).isEqualTo(800);
        });
        assertThat(stages).anySatisfy(x -> assertThat(x).containsEntry("code", "900E").containsEntry("is_extension", true));

        String surname = it.freeSurname("ZZPGSTAGE");
        UUID returning = pgStudent(surname + "R", "C90090", s.get(0));   // 800 B in the second session
        UUID fresh = pgStudent(surname + "F", "C90090", s.get(1));       // 800 A in it

        Map<String, Object> structure = Map.of("pgStage", "800B", "programmeCode", "C90090", "semester", 1, "reason", "Approved by the PG School Board",
                "components", List.of(Map.of("item", "Tuition", "amount", 50000), Map.of("item", "Bench fee", "amount", 12000)));
        assertThat(it.call(ItSupport.token("registrar"), HttpMethod.POST, path(s.get(1)) + "/pg-fee-structure", structure).getStatusCode().value()).isEqualTo(403);
        ResponseEntity<Map> saved = it.call(bursar, HttpMethod.POST, path(s.get(1)) + "/pg-fee-structure", structure);
        assertThat(saved.getStatusCode().value()).as(String.valueOf(saved.getBody())).isEqualTo(200);
        assertThat(saved.getBody()).containsEntry("stated", 2);
        assertThat(new BigDecimal(String.valueOf(saved.getBody().get("total")))).isEqualByComparingTo("62000");

        // refused: the same again, a component twice, an undergraduate programme, a PhD stage on a Masters programme
        ResponseEntity<Map> again = it.call(bursar, HttpMethod.POST, path(s.get(1)) + "/pg-fee-structure", structure);
        assertThat(again.getStatusCode().value()).isEqualTo(422);
        assertThat(again.getBody()).containsEntry("code", "FEE_LINE_DUPLICATE");
        ResponseEntity<Map> twice = it.call(bursar, HttpMethod.POST, path(s.get(1)) + "/pg-fee-structure", Map.of("pgStage", "800C",
                "components", List.of(Map.of("item", "Tuition", "amount", 1), Map.of("item", "tuition", "amount", 2))));
        assertThat(twice.getStatusCode().value()).isEqualTo(422);
        assertThat(twice.getBody()).containsEntry("code", "FEE_COMPONENT_TWICE");
        ResponseEntity<Map> ug = it.call(bursar, HttpMethod.POST, path(s.get(1)) + "/pg-fee-structure", Map.of("pgStage", "800C", "programmeCode", ugProgramme(),
                "components", List.of(Map.of("item", "Tuition", "amount", 1))));
        assertThat(ug.getStatusCode().value()).as(String.valueOf(ug.getBody())).isEqualTo(422);
        assertThat(ug.getBody()).containsEntry("code", "FEE_PG_STAGE_PROGRAMME");
        ResponseEntity<Map> phd = it.call(bursar, HttpMethod.POST, path(s.get(1)) + "/pg-fee-structure", Map.of("pgStage", "900A", "programmeCode", "C90090",
                "components", List.of(Map.of("item", "Tuition", "amount", 1))));
        assertThat(phd.getStatusCode().value()).isEqualTo(422);
        assertThat(phd.getBody()).containsEntry("code", "FEE_PG_STAGE_PROGRAMME");

        // a line by hand for 800 A: the stage sets its level and its students are fresh
        Map<String, Object> line = new HashMap<>(Map.of("item", "Tuition", "amount", 70000, "programmeCode", "C90090", "semester", 1, "pgStage", "800A"));
        ResponseEntity<Map> added = it.call(bursar, HttpMethod.POST, path(s.get(1)) + "/schedule", line);
        assertThat(added.getStatusCode().value()).as(String.valueOf(added.getBody())).isEqualTo(200);
        List<Map<String, Object>> items = (List<Map<String, Object>>) it.get(bursar, path(s.get(1)) + "/schedule").getBody().get("items");
        assertThat(items).anySatisfy(i -> {
            assertThat(i).containsEntry("pg_stage", "800A").containsEntry("fee_category", "FRESH").containsEntry("pg_stage_label", "800 A — Year 1");
            assertThat(((Number) i.get("level")).intValue()).isEqualTo(800);
        });
        assertThat(items.stream().filter(i -> "800B".equals(i.get("pg_stage"))).count()).isEqualTo(2L);

        // each student is charged their own stage's lines
        assertThat(charged(returning, s.get(1))).isEqualByComparingTo("62000");
        assertThat(charged(fresh, s.get(1))).isEqualByComparingTo("70000");

        // the school-fees reference names the stage it was raised under; the history reads it
        String ref = "MOAUM-FEE-V651IT" + UUID.randomUUID().toString().substring(0, 8).toUpperCase();
        it.db(() -> jdbc.sql("""
                INSERT INTO finance.payment_reference (student_id, session, reference, purpose, amount, expires_at)
                VALUES (:st, :s, :r, 'School fees ' || :s, 62000, now() + interval '3 days')
                """).param("st", returning).param("s", s.get(1)).param("r", ref).update());
        Map<String, Object> history = it.get(pgschool, "/api/v1/pg/academic/students/" + returning + "/history?session=" + s.get(1)).getBody();
        assertThat(history).containsEntry("pg", true);
        assertThat((Map<String, Object>) history.get("current")).containsEntry("stage_code", "800B").containsEntry("category", "RETURNING").containsEntry("official", false);
        assertThat((List<Map<String, Object>>) history.get("payments")).singleElement().satisfies(p ->
                assertThat(p).containsEntry("reference", ref).containsEntry("stage_code", "800B").containsEntry("category", "RETURNING").containsEntry("cycle_no", 1));
    }

    /** V653: the fee spreadsheet upload with PG stages — previewed, loaded, refused when a stage is unknown or not the programme's;
     *  an undergraduate row leaves the stage lines; each student charged their stage's line; the unstated list by stage */
    @Test
    void theStructureUploadReadsPgStagesAndTheUnstatedListNamesTheStage() {
        List<String> s = sessions(3);
        String bursar = ItSupport.token("bursar");
        String surname = it.freeSurname("ZZPGUPLOAD");
        UUID ext = pgStudent(surname + "E", "C90090", s.get(0));   // 800 C in the third session
        UUID ret = pgStudent(surname + "R", "C90090", s.get(1));   // 800 B
        String path = path(s.get(2));

        // before any line: the students with no fee stated, by stage
        List<Map<String, Object>> unstated = (List<Map<String, Object>>) (List) it.getList(bursar, path + "/postgraduate/unstated").getBody();
        assertThat(unstated).anySatisfy(u -> assertThat(u).containsEntry("programme_code", "C90090").containsEntry("stage_code", "800C")
                .containsEntry("stage_label", "800 C — Extension").containsEntry("category", "RETURNING"));

        // previewed, then loaded: an 800 B line for every Masters programme, the programme's own 800 C line
        List<Map<String, Object>> rows = List.of(Map.of("pgStage", "800 B — Year 2", "item", "Tuition", "amount", "55000", "semester", "1"),
                Map.of("programmeCode", "C90090", "pgStage", "800C", "item", "Tuition", "amount", "40000", "semester", "1"));
        ResponseEntity<Map> preview = it.call(bursar, HttpMethod.POST, path + "/fee-structure/preview", Map.of("rows", rows, "scope", "LISTED"));
        assertThat(preview.getStatusCode().value()).as(String.valueOf(preview.getBody())).isEqualTo(200);
        assertThat((Map<String, Object>) preview.getBody().get("totals")).containsEntry("new", 2).containsEntry("ended", 0);
        ResponseEntity<Map> loaded = it.call(bursar, HttpMethod.POST, path + "/fee-structure", Map.of("rows", rows, "scope", "LISTED"));
        assertThat(loaded.getStatusCode().value()).as(String.valueOf(loaded.getBody())).isEqualTo(200);
        assertThat(loaded.getBody()).containsEntry("lines", 2);
        assertThat(charged(ret, s.get(2))).isEqualByComparingTo("55000");
        assertThat(charged(ext, s.get(2))).isEqualByComparingTo("40000");

        // an undergraduate row for what it names leaves the stage lines
        ResponseEntity<Map> ug = it.call(bursar, HttpMethod.POST, path + "/fee-structure",
                Map.of("rows", List.of(Map.of("level", "100", "item", "V653 IT undergraduate", "amount", "100")), "scope", "LISTED"));
        assertThat(ug.getStatusCode().value()).as(String.valueOf(ug.getBody())).isEqualTo(200);
        List<Map<String, Object>> items = (List<Map<String, Object>>) it.get(bursar, path + "/schedule").getBody().get("items");
        assertThat(items.stream().filter(i -> i.get("pg_stage") != null).map(i -> i.get("pg_stage") + "=" + new BigDecimal(String.valueOf(i.get("amount"))).stripTrailingZeros().toPlainString()))
                .containsExactlyInAnyOrder("800B=55000", "800C=40000");

        // refused before anything changes: an unknown stage, a stage on an undergraduate programme
        ResponseEntity<Map> unknown = it.call(bursar, HttpMethod.POST, path + "/fee-structure", Map.of("rows", List.of(Map.of("pgStage", "800 Z", "amount", "1")), "scope", "LISTED"));
        assertThat(unknown.getStatusCode().value()).isEqualTo(422);
        assertThat(unknown.getBody()).containsEntry("code", "FEE_STRUCTURE_UNKNOWN");
        ResponseEntity<Map> ugStage = it.call(bursar, HttpMethod.POST, path + "/fee-structure",
                Map.of("rows", List.of(Map.of("programmeCode", ugProgramme(), "pgStage", "800B", "amount", "1")), "scope", "LISTED"));
        assertThat(ugStage.getStatusCode().value()).isEqualTo(422);
        assertThat(ugStage.getBody()).containsEntry("code", "FEE_STRUCTURE_PG");
        assertThat(String.valueOf(ugStage.getBody().get("detail"))).contains("row 1").contains("not a postgraduate programme");

        // the preview of a new 800 B amount pairs it with the line it replaces, by stage
        ResponseEntity<Map> change = it.call(bursar, HttpMethod.POST, path + "/fee-structure/preview",
                Map.of("rows", List.of(Map.of("pgStage", "800B", "item", "Tuition", "amount", "60000", "semester", "1")), "scope", "LISTED"));
        assertThat(change.getStatusCode().value()).as(String.valueOf(change.getBody())).isEqualTo(200);
        assertThat((Map<String, Object>) change.getBody().get("totals")).containsEntry("changed", 1).containsEntry("new", 0).containsEntry("ended", 0);
        assertThat((List<Map<String, Object>>) change.getBody().get("changes")).singleElement().satisfies(c ->
                assertThat(c).containsEntry("pgStage", "800B").containsEntry("pgStageLabel", "800 B — Year 2"));
    }

    @Test
    void aCycleIsReconciledProgressedExtendedClosedAndRestartedIntoCycleTwo() {
        List<String> s = sessions(4);
        String pgschool = ItSupport.token("pgschool");
        String secretary = ItSupport.token("pgsecretary");
        String hod = it.officer("hod", "department", "MTC");
        String otherHod = it.officer("hod", "department", "GEO");
        String surname = it.freeSurname("ZZPGCYCLE");
        UUID st = pgStudent(surname, "C90002", s.get(0));   // M.Sc. Computer Science
        String pg = "/api/v1/pg/academic";

        // the structure and who may
        Map<String, Object> cfg = it.get(pgschool, pg + "/config").getBody();
        assertThat((List<String>) cfg.get("permissions")).contains("APPROVE_PG_EXTENSION", "APPROVE_PG_RESTART", "MANAGE_PG_LEVEL_STRUCTURE");
        assertThat((List<Map<String, Object>>) cfg.get("stages")).filteredOn(x -> "MASTERS".equals(x.get("qualification")) && Boolean.TRUE.equals(x.get("active")))
                .extracting(x -> x.get("label")).containsExactly("800 A — Year 1", "800 B — Year 2", "800 C — Extension");
        assertThat((List<String>) it.get(secretary, pg + "/config").getBody().get("permissions"))
                .contains("MANAGE_PG_PROGRESSION", "MANAGE_PG_ACADEMIC_CYCLE").doesNotContain("APPROVE_PG_EXTENSION", "APPROVE_PG_RESTART", "MANAGE_PG_LEVEL_STRUCTURE");
        assertThat(it.get(ItSupport.token("lecturer"), pg + "/config").getStatusCode().value()).isEqualTo(403);
        assertThat(it.call(secretary, HttpMethod.PUT, pg + "/config/MASTERS", Map.of("normalYears", 2, "extensionYears", 2, "restartAllowed", true))
                .getStatusCode().value()).isEqualTo(403);

        // reconciled: previewed, then committed by the PG Secretary (not by a department)
        Map<String, Object> scan = it.get(pgschool, pg + "/reconciliation?session=" + s.get(0) + "&q=" + surname).getBody();
        assertThat((List<Map<String, Object>>) scan.get("rows")).singleElement().satisfies(r ->
                assertThat(r).containsEntry("confidence", "HIGH").containsEntry("stage_code", "800A"));
        Map<String, Object> commit = Map.of("studentIds", List.of(st), "session", s.get(0), "reason", "Cycles recorded for the PG register");
        assertThat(it.call(hod, HttpMethod.POST, pg + "/reconciliation/commit", commit).getStatusCode().value()).isEqualTo(403);
        ResponseEntity<Map> committed = it.call(secretary, HttpMethod.POST, pg + "/reconciliation/commit", commit);
        assertThat(committed.getStatusCode().value()).as(String.valueOf(committed.getBody())).isEqualTo(200);
        assertThat((Map<String, Object>) committed.getBody().get("outcomes")).containsEntry("RECORDED", 1);

        // progressed; the extension is the Dean's; a stage below the one reached is refused
        Map<String, Object> outcomes = (Map<String, Object>) it.call(secretary, HttpMethod.POST, pg + "/progress", Map.of("studentIds", List.of(st), "session", s.get(1)))
                .getBody().get("outcomes");
        assertThat(outcomes).containsEntry("PROGRESSED", 1);
        assertThat((Map<String, Object>) it.call(secretary, HttpMethod.POST, pg + "/progress", Map.of("studentIds", List.of(st), "session", s.get(2))).getBody().get("outcomes"))
                .containsEntry("NEEDS_APPROVAL", 1);
        assertThat((Map<String, Object>) it.call(pgschool, HttpMethod.POST, pg + "/progress", Map.of("studentIds", List.of(st), "session", s.get(2),
                "reason", "Thesis outstanding: one year's extension")).getBody().get("outcomes")).containsEntry("EXTENDED", 1);
        Map<String, Object> history = it.get(pgschool, pg + "/students/" + st + "/history").getBody();
        String cycle = String.valueOf(((List<Map<String, Object>>) history.get("cycles")).get(0).get("id"));
        ResponseEntity<Map> order = it.call(pgschool, HttpMethod.POST, pg + "/stage", Map.of("cycleId", cycle, "session", s.get(3), "stage", "800A",
                "reason", "Recorded below the stage already reached"));
        assertThat(order.getStatusCode().value()).isEqualTo(422);
        assertThat(order.getBody()).containsEntry("code", "PG_STAGE_ORDER");

        // another department's Head reads nothing of the student; the cycle closed as exhausted at its last stage
        assertThat(it.get(otherHod, pg + "/students/" + st + "/history").getStatusCode().value()).isEqualTo(403);
        ResponseEntity<Map> closed = it.call(secretary, HttpMethod.POST, pg + "/cycles/" + cycle + "/close",
                Map.of("status", "MAXIMUM_PERIOD_EXHAUSTED", "reason", "The extension year ended with the thesis outstanding"));
        assertThat(closed.getStatusCode().value()).as(String.valueOf(closed.getBody())).isEqualTo(200);

        // the restart: requested and recommended by the department, refused to the Secretary, approved by the Dean
        Map<String, Object> restart = Map.of("studentId", st, "startSession", s.get(3), "reason", "The student asks to begin the Masters again");
        assertThat(it.call(otherHod, HttpMethod.POST, pg + "/restarts", restart).getStatusCode().value()).isEqualTo(403);
        ResponseEntity<Map> requested = it.call(hod, HttpMethod.POST, pg + "/restarts", restart);
        assertThat(requested.getStatusCode().value()).as(String.valueOf(requested.getBody())).isEqualTo(200);
        String reference = String.valueOf(requested.getBody().get("reference"));
        assertThat(reference).matches("^PG-RST/[0-9]{4}/[0-9]{6}$");
        String rpath = pg + "/restarts/" + reference.substring("PG-RST/".length());
        assertThat(it.call(hod, HttpMethod.POST, rpath + "/recommend", Map.of("recommend", true, "note", "The department supports a fresh start")).getBody())
                .containsEntry("state", "UNDER_REVIEW");
        assertThat((List<Map<String, Object>>) (List) it.getList(hod, pg + "/restarts?state=OPEN").getBody())
                .anySatisfy(r -> assertThat(r).containsEntry("reference", reference).containsEntry("mine", true));
        assertThat(it.call(secretary, HttpMethod.POST, rpath + "/decide", Map.of("approve", true)).getStatusCode().value()).isEqualTo(403);
        ResponseEntity<Map> decided = it.call(pgschool, HttpMethod.POST, rpath + "/decide", Map.of("approve", true, "note", "Approved by the Board of the School"));
        assertThat(decided.getStatusCode().value()).as(String.valueOf(decided.getBody())).isEqualTo(200);
        assertThat(decided.getBody()).containsEntry("state", "APPROVED").containsEntry("cycle_no", 2).containsEntry("stage_code", "800A");

        // cycle 2 at 800 A, fresh; cycle 1 kept with its stages
        Map<String, Object> page = it.get(pgschool, pg + "/students?session=" + s.get(3) + "&q=" + surname).getBody();
        assertThat((List<Map<String, Object>>) page.get("rows")).singleElement().satisfies(r ->
                assertThat(r).containsEntry("cycle_no", 2).containsEntry("stage_code", "800A").containsEntry("category", "FRESH").containsEntry("official", true));
        Map<String, Object> after = it.get(hod, pg + "/students/" + st + "/history?session=" + s.get(1)).getBody();
        // read in an earlier session, cycle 1 is closed: the restart approved, it needs nothing more
        assertThat((Map<String, Object>) after.get("current")).containsEntry("cycle_no", 1).containsEntry("stage_code", "800B").containsEntry("recommendation", "CLOSED");
        List<Map<String, Object>> cycles = (List<Map<String, Object>>) after.get("cycles");
        assertThat(cycles).hasSize(2);
        assertThat(cycles.get(0)).containsEntry("status", "MAXIMUM_PERIOD_EXHAUSTED");
        assertThat((List<Map<String, Object>>) cycles.get(0).get("stages")).extracting(x -> x.get("stage_code") + "/" + x.get("source"))
                .containsExactly("800A/RECONCILIATION", "800B/PROGRESSION", "800C/EXTENSION");
        assertThat(cycles.get(1)).containsEntry("status", "ACTIVE").containsEntry("source", "RESTART").containsEntry("start_session", s.get(3));
        assertThat((List<Map<String, Object>>) after.get("restarts")).singleElement().satisfies(r -> assertThat(r).containsEntry("state", "APPROVED").containsEntry("new_cycle_no", 2));

        // the counts and the data quality read for the department's Head and the School
        assertThat((List<Map<String, Object>>) it.get(hod, pg + "/counts?session=" + s.get(3)).getBody().get("rows"))
                .anySatisfy(r -> { assertThat(r).containsEntry("stage_code", "800A"); assertThat(((Number) r.get("fresh")).intValue()).isGreaterThanOrEqualTo(1); });
        assertThat(it.get(pgschool, pg + "/quality?session=" + s.get(3)).getStatusCode().value()).isEqualTo(200);
    }
}
