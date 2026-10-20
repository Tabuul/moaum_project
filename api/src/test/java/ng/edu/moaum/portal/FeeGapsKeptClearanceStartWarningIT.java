package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.List;
import java.util.Map;
import java.util.Random;
import java.util.UUID;

import ng.edu.moaum.portal.calendar.SessionTransitionClock;

import org.junit.jupiter.api.AfterEach;
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
 * V584 and V585, end to end: a fee-effect run's students charged nothing after are offered the lines they could be stated from, and
 * the Bursary states them once (the Registrar may read, not state); an upload's students are listed with what became of each
 * contact; the migrated students' figures follow a decision at once (the kept counts); the Registrar's office is told once that a
 * session starts automatically in three days; the Bursar alone sets the hold on the automatic start. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class FeeGapsKeptClearanceStartWarningIT {

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;
    @Autowired
    SessionTransitionClock clock;

    /** the invented session whose fee lines the test states, the one it sets to start automatically, and its fee-effect run (dated
     *  ahead, so the latest a reader sees): taken off again */
    String ses, auto;
    UUID run;

    @AfterEach
    void clean() {
        ItSupport it = new ItSupport(port, jdbc, transactions);
        if (ses != null) it.db(() -> jdbc.sql("DELETE FROM finance.fee_schedule WHERE session = :s").param("s", ses).update());
        if (run != null) it.db(() -> jdbc.sql("DELETE FROM people.level_fee_effect_run WHERE id = :r").param("r", run).update());
        if (auto != null) it.db(() -> jdbc.sql("UPDATE policy.academic_session SET transition_mode = 'MANUAL', transitions_on = NULL WHERE name = :s").param("s", auto).update());
        it.db(() -> jdbc.sql("UPDATE finance.fee_setting SET spill_lines_hold_start = false WHERE id = 1").update());
    }

    private long migratedCleared(ItSupport it, String token, String key) {
        Map<String, Object> m = it.get(token, "/api/v1/student/students/migrated?from=200&to=200&refresh=true").getBody();
        return ((Number) m.get(key)).longValue();
    }

    @Test
    void feeGapsUploadsKeptClearanceAndTheStartWarning() {
        ItSupport it = new ItSupport(port, jdbc, transactions);
        int n = it.freeDraw(10000, 99999, k -> List.of("ZZFGKA" + k, "ZZFGKB" + k, "ZZFGKC" + k, "ZZFGKM" + k, "ZZ-FGK-BU-" + k, "ZZ-FGK-RG-" + k,
                "MOAU/SC/FGK/26/" + k, "MOAU/SC/FGL/26/" + k, "MOAU/SC/FGM/26/" + k, "MOAU/SC/FGN/26/" + k));
        String bursar = TestTokens.token(it.person("ZZ-FGK-BU-" + n, "ZZFGKBU" + n), List.of("bursar"));
        UUID registrarId = it.person("ZZ-FGK-RG-" + n, "ZZFGKRG" + n);
        String registrarMail = "zzfgkrg" + n + "@example.com";
        it.db(() -> jdbc.sql("UPDATE iam.person SET email = :e WHERE id = :p").param("e", registrarMail).param("p", registrarId).update());
        it.db(() -> jdbc.sql("""
                INSERT INTO iam.office_assignment (id, person_id, office_code, scope_kind, instrument, granted_by, valid_from)
                VALUES (gen_random_uuid(), :p, 'registrar', 'institution', 'FeeGapsKeptClearanceStartWarningIT', :p, current_date - 1)
                """).param("p", registrarId).update());
        String registrar = TestTokens.token(registrarId, List.of("registrar"));

        // ── V584: a run's gap, offered from the nearest lines, stated once by the Bursary ──
        Random random = new Random();
        int year = 3190 + random.nextInt(5);
        for (int i = 0; i < 20 && jdbc.sql("SELECT EXISTS (SELECT 1 FROM finance.fee_schedule WHERE session = :s)").param("s", year + "/" + (year + 1))
                .query(Boolean.class).single(); i++) {
            year = 3190 + random.nextInt(5);
        }
        ses = year + "/" + (year + 1);
        it.session(ses, year);
        it.db(() -> jdbc.sql("""
                INSERT INTO finance.fee_schedule (session, item, amount, level, programme_code) VALUES
                    (:s, 'School fees', 300000, 100, 'C00023'), (:s, 'School fees', 250000, 400, 'C00028')
                """).param("s", ses).update());
        UUID a = it.student("ZZFGKA" + n, "C00023", "MOAUM/ADM/88/" + (100000 + n), "MOAU/SC/FGK/26/" + n, 100);
        run = UUID.randomUUID();
        UUID runId = run;
        it.db(() -> {
            jdbc.sql("INSERT INTO people.level_fee_effect_run (id, session, basis, bases, state, students, done, started_at) VALUES (:r, :s, 'LEVEL', ARRAY['SPILLOVER'], 'DONE', 1, 1, now() + interval '1 hour')")
                    .param("r", runId).param("s", ses).update();
            return jdbc.sql("INSERT INTO people.level_fee_effect_row (run_id, student_id, basis, current_level, new_level, charged_now, charged_after) VALUES (:r, :a, 'SPILLOVER', 100, 400, 300000, 0)")
                    .param("r", runId).param("a", a).update();
        });
        Map<String, Object> latest = it.get(registrar, "/api/v1/finance/level-fee-effect").getBody();
        assertThat(((Map<String, Object>) latest.get("run")).get("id")).isEqualTo(runId.toString());
        List<Map<String, Object>> gaps = (List<Map<String, Object>>) latest.get("gaps");
        assertThat(gaps).singleElement().satisfies(g -> {
            assertThat(g).containsEntry("programme_code", "C00023").containsEntry("level", 400).containsEntry("students", 1).containsEntry("programme_states", true);
            assertThat((List<Map<String, Object>>) g.get("sources")).first().satisfies(src -> assertThat(src).containsEntry("kind", "SAME_PROGRAMME").containsEntry("level", 100));
            assertThat((List<Map<String, Object>>) g.get("sources")).anySatisfy(src -> assertThat(src).containsEntry("kind", "SAME_DEPARTMENT").containsEntry("programme_code", "C00028"));
        });
        String session = ses;
        ResponseEntity<Map> preview = it.get(registrar, u -> u.path("/api/v1/finance/level-fee-effect/gap-lines").queryParam("fromSession", session)
                .queryParam("fromProgramme", "C00028").queryParam("fromLevel", 400).queryParam("session", session).queryParam("programme", "C00023")
                .queryParam("level", 400).build());
        assertThat(preview.getStatusCode().value()).as(String.valueOf(preview.getBody())).isEqualTo(200);
        assertThat(preview.getBody()).containsEntry("copy", 1).containsEntry("kept", 0).containsEntry("applied", false);
        Map<String, Object> body = Map.of("fromSession", ses, "fromProgramme", "C00028", "fromLevel", 400, "session", ses, "programme", "C00023", "level", 400);
        assertThat(it.call(registrar, HttpMethod.POST, "/api/v1/finance/level-fee-effect/gap-lines", body).getStatusCode().value()).isEqualTo(403);
        ResponseEntity<Map> stated = it.call(bursar, HttpMethod.POST, "/api/v1/finance/level-fee-effect/gap-lines", body);
        assertThat(stated.getStatusCode().value()).as(String.valueOf(stated.getBody())).isEqualTo(200);
        assertThat(stated.getBody()).containsEntry("copy", 1).containsEntry("applied", true);
        assertThat(it.call(bursar, HttpMethod.POST, "/api/v1/finance/level-fee-effect/gap-lines", body).getBody()).as("stated once").containsEntry("copy", 0).containsEntry("kept", 1);
        it.db(() -> jdbc.sql("UPDATE people.student SET current_level = 400 WHERE id = :a").param("a", a).update());
        List<Map<String, Object>> report = (List<Map<String, Object>>) it.get(registrar, "/api/v1/finance/level-fee-effect").getBody().get("report");
        assertThat(report).filteredOn(r -> "PROGRAMME".equals(r.get("scope"))).singleElement().satisfies(r -> assertThat(r).containsEntry("corrected", 1));

        // ── V584: an upload's students, each contact with what became of it ──
        it.student("ZZFGKB" + n, "C00023", "MOAUM/ADM/88/" + (200000 + n), "MOAU/SC/FGL/26/" + n, 200);
        UUID c = it.student("ZZFGKC" + n, "C00023", "MOAUM/ADM/88/" + (300000 + n), "MOAU/SC/FGM/26/" + n, 200);
        ResponseEntity<Map> up = it.call(registrar, HttpMethod.POST, "/api/v1/student-contacts/upload", Map.of("fileName", "fgk-" + n + ".csv", "rows", List.of(
                Map.of("number", "MOAU/SC/FGL/26/" + n, "phone", String.format("0807%07d", n)), Map.of("number", "MOAU/SC/FGM/26/" + n, "phone", String.format("0808%07d", n)))));
        assertThat(up.getStatusCode().value()).as(String.valueOf(up.getBody())).isEqualTo(200);
        assertThat(it.call(TestTokens.token(c, List.of("student")), HttpMethod.POST, "/api/v1/me/contact/not-mine", Map.of("field", "PHONE")).getBody()).containsEntry("outcome", "REFUSED");
        ResponseEntity<Map> listed = it.get(registrar, "/api/v1/student-contacts/uploads/" + up.getBody().get("uploadId") + "/students");
        assertThat(listed.getStatusCode().value()).as(String.valueOf(listed.getBody())).isEqualTo(200);
        assertThat((List<Map<String, Object>>) listed.getBody().get("rows")).extracting(r -> r.get("outcome") + ":" + r.get("value"))
                .containsExactly("WAITING:" + String.format("0807%07d", n), "REFUSED:" + String.format("0808%07d", n));

        // ── V585: the migrated students' figures follow a decision at once ──
        UUID m = it.student("ZZFGKM" + n, "C00023", "MOAUM/ADM/88/" + (400000 + n), "MOAU/SC/FGN/26/" + n, 200);
        long clearedBefore = migratedCleared(it, registrar, "cleared");
        it.db(() -> jdbc.sql("""
                INSERT INTO clearance.item (id, student_id, purpose, unit, state, decided_at)
                SELECT gen_random_uuid(), :m, pu.code, u.code, 'CLEARED', now() - interval '1 hour' FROM ref.clearance_purpose pu CROSS JOIN clearance.unit u WHERE pu.gate
                """).param("m", m).update());
        assertThat(migratedCleared(it, registrar, "cleared")).isEqualTo(clearedBefore + 1);
        long unclearedBefore = migratedCleared(it, registrar, "uncleared");
        it.db(() -> jdbc.sql("""
                INSERT INTO clearance.item (id, student_id, purpose, unit, state, item, decided_at)
                SELECT gen_random_uuid(), :m, (SELECT code FROM ref.clearance_purpose WHERE gate ORDER BY code LIMIT 1), (SELECT code FROM clearance.unit ORDER BY code LIMIT 1),
                       'HELD', 'FeeGapsKeptClearanceStartWarningIT hold', now()
                """).param("m", m).update());
        assertThat(migratedCleared(it, registrar, "uncleared")).isEqualTo(unclearedBefore + 1);

        // ── V585: the start warned of once; the Bursar's hold ──
        int autoYear = 3196 + random.nextInt(3);
        auto = autoYear + "/" + (autoYear + 1);
        it.session(auto, autoYear);
        String autoSession = auto;
        it.db(() -> jdbc.sql("UPDATE policy.academic_session SET transition_mode = 'AUTOMATIC', transitions_on = (now() AT TIME ZONE 'Africa/Lagos')::date + 3 WHERE name = :s")
                .param("s", autoSession).update());
        String noticeSql = "SELECT count(*) FROM platform.notice WHERE lower(recipient) = lower(:r) AND template_key = 'SESSION_START_READINESS' AND subject LIKE :s";
        clock.remindStart();
        clock.remindStart();
        assertThat(jdbc.sql(noticeSql).param("r", registrarMail).param("s", auto + "%").query(Long.class).single()).as("told once").isEqualTo(1);
        assertThat(it.call(registrar, HttpMethod.PUT, "/api/v1/finance/spillover-basis/hold-start", Map.of("hold", true)).getStatusCode().value()).isEqualTo(403);
        ResponseEntity<Map> held = it.call(bursar, HttpMethod.PUT, "/api/v1/finance/spillover-basis/hold-start", Map.of("hold", true));
        assertThat(held.getStatusCode().value()).as(String.valueOf(held.getBody())).isEqualTo(200);
        assertThat(held.getBody()).containsEntry("hold_start", true);
        assertThat(it.call(bursar, HttpMethod.PUT, "/api/v1/finance/spillover-basis/hold-start", Map.of("hold", false)).getBody()).containsEntry("hold_start", false);
    }
}
