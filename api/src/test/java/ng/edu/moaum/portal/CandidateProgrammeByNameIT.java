package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.List;
import java.util.Map;
import java.util.UUID;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.transaction.PlatformTransactionManager;

/**
 * V769 through the API: a candidate's programme is the NAME JAMB's list gives (B.Sc. ACCOUNTING), never the code. The Academic
 * Office's report of 15 November 2026: the cycle's cards counted the session's offers and acceptances while every row of the
 * "Programmes — merit lists" table read OFFERED 0 and ACCEPTED 0, the table having grouped the candidates by the name and joined it to
 * the code. Here made-up candidates of a session no test has opened — on Accounting by its name and one by its code, on Computer
 * Science by its name, one on a name no programme carries — are counted on the row of the programme each names, the unknown name on
 * none; and a student admitted to Computer Science and now on Accounting is shown, on the full record and on the programme swap page,
 * as admitted to Computer Science, while one admitted to Accounting by its name is not shown as admitted elsewhere. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class CandidateProgrammeByNameIT {

    static final String ACC = "C00019", CS = "C00023";

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    ItSupport it;
    final String academic = ItSupport.token("academic");
    final String registrar = ItSupport.token("registrar");
    int year;
    String session;
    UUID batch;

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
        year = it.freeYear(6700, 7000);
        session = year + "/" + (year + 1);
        it.session(session, year);
        // the session is the test's own: nothing on JAMB's list or among the candidates yet
        assertThat(jdbc.sql("SELECT count(*) FROM admissions.candidate WHERE session = :s").param("s", session).query(Long.class).single()).isZero();
        batch = UUID.randomUUID();
        it.db(() -> jdbc.sql("""
                INSERT INTO admissions.caps_batch (id, session, source, filename, file_sha256, rows_read, list_kind, downloaded_on, uploaded_by, uploaded_office, committed_at)
                VALUES (:id, :s, 'CAPS_DOWNLOAD', 'by-name.xlsx', decode(md5(:id::text), 'hex'), 8, 'UTME', current_date, gen_random_uuid(), 'academic', now())
                """).param("id", batch).param("s", session).update());
    }

    String name(String code) {
        return jdbc.sql("SELECT name FROM ref.programme WHERE code = :c").param("c", code).query(String.class).single();
    }

    /** a candidate on JAMB's list for the code given, their programme written as the text given (a name, as JAMB's list gives it) */
    UUID candidate(String tag, String jambCode, String programme, String state) {
        String jamb = year + String.format("%06d", java.util.concurrent.ThreadLocalRandom.current().nextInt(1_000_000)) + "BN";
        return it.db(() -> {
            UUID row = UUID.randomUUID(), cand = UUID.randomUUID();
            jdbc.sql("""
                    INSERT INTO admissions.caps_row (id, batch_id, session, jamb_reg_no, raw, surname, other_names, jamb_code, aggregate, entry_mode, sex, state_of_origin, lga)
                    VALUES (:id, :b, :s, :j, '{}'::jsonb, 'ZZBYNAME', :t, :p, 250, 'UTME', 'F', 'Benue', 'Makurdi')
                    """).param("id", row).param("b", batch).param("s", session).param("j", jamb).param("t", tag).param("p", jambCode).update();
            jdbc.sql("""
                    INSERT INTO admissions.candidate (id, session, jamb_reg_no, surname, other_names, programme, entry_mode, entry_level, offer_state, admitted_from)
                    VALUES (:id, :s, :j, 'ZZBYNAME', :t, :p, 'UTME', 100, :st, :r)
                    """).param("id", cand).param("s", session).param("j", jamb).param("t", tag).param("p", programme).param("st", state).param("r", row).update();
            return cand;
        });
    }

    Map<String, Object> row(List<Map<String, Object>> rows, String code) {
        return rows.stream().filter(r -> code.equals(r.get("code"))).findFirst().orElseThrow(() -> new AssertionError("no row for " + code));
    }

    long n(Object o) {
        return ((Number) o).longValue();
    }

    @Test
    void eachProgrammeRowCountsTheOffersAndAcceptancesOfTheCandidatesItsNameNames() {
        candidate("A1", ACC, name(ACC), "ADMITTED");
        candidate("A2", ACC, name(ACC), "ACCEPTED");
        candidate("A3", ACC, name(ACC), "PROPOSED");
        candidate("A4", ACC, ACC, "ACCEPTED");                        // written as the code, as before the name was the rule
        candidate("C1", CS, name(CS), "ADMITTED");
        candidate("C2", CS, name(CS), "ACCEPTED");
        candidate("X1", ACC, "ZZ NOT A PROGRAMME OF V769", "ADMITTED"); // a name no programme carries: counted on no row

        ResponseEntity<Map> got = it.get(academic, "/api/v1/admissions/sessions/" + session + "/cycle");
        assertThat(got.getStatusCode().value()).as(String.valueOf(got.getBody())).isEqualTo(200);
        Map<String, Object> cycle = got.getBody();
        assertThat(n(cycle.get("offers"))).isEqualTo(6);
        assertThat(n(cycle.get("accepted"))).isEqualTo(3);
        List<Map<String, Object>> rows = (List<Map<String, Object>>) cycle.get("programmes");
        assertThat(n(row(rows, ACC).get("offered"))).as("Accounting offered").isEqualTo(3);
        assertThat(n(row(rows, ACC).get("accepted"))).as("Accounting accepted").isEqualTo(2);
        assertThat(n(row(rows, CS).get("offered"))).as("Computer Science offered").isEqualTo(2);
        assertThat(n(row(rows, CS).get("accepted"))).as("Computer Science accepted").isEqualTo(1);
        // the rows add up to the cards, less the offer on a name no programme carries
        assertThat(rows.stream().mapToLong(r -> n(r.get("offered"))).sum()).isEqualTo(5);
        assertThat(rows.stream().mapToLong(r -> n(r.get("accepted"))).sum()).isEqualTo(3);
    }

    @Test
    void theFullRecordAndTheSwapPageNameTheProgrammeAStudentWasAdmittedTo() {
        UUID here = candidate("S1", ACC, name(ACC), "ACCEPTED");
        UUID elsewhere = candidate("S2", CS, name(CS), "ACCEPTED");
        UUID onHere = UUID.randomUUID(), onElsewhere = UUID.randomUUID();
        it.db(() -> jdbc.sql("""
                INSERT INTO people.student (id, candidate_id, surname, other_names, programme_code, entry_mode, entry_session, entry_level, current_level, status)
                VALUES (:a, :ca, 'ZZBYNAME', 'Admitted Here', :p, 'UTME', :s, 100, 100, 'ADMITTED'),
                       (:b, :cb, 'ZZBYNAME', 'Admitted Elsewhere', :p, 'UTME', :s, 100, 100, 'ADMITTED')
                """).param("a", onHere).param("ca", here).param("b", onElsewhere).param("cb", elsewhere).param("p", ACC).param("s", session).update());

        // the full record: "Original admission programme" where the record is on another programme than the one admitted to
        Map<String, Object> idHere = (Map<String, Object>) ok(it.get(registrar, "/api/v1/student/students/" + onHere + "/full/overview")).get("identity");
        Map<String, Object> idElsewhere = (Map<String, Object>) ok(it.get(registrar, "/api/v1/student/students/" + onElsewhere + "/full/overview")).get("identity");
        assertThat(idHere.get("admitted_programme")).isNull();
        assertThat(idElsewhere.get("admitted_programme")).isEqualTo(name(CS));

        // the programme swap page: the programme admitted to, by code, which the page compares with the code held
        Map<String, Object> sigHere = (Map<String, Object>) ok(it.get(academic, "/api/v1/programme-swaps/students/" + onHere)).get("signals");
        Map<String, Object> sigElsewhere = (Map<String, Object>) ok(it.get(academic, "/api/v1/programme-swaps/students/" + onElsewhere)).get("signals");
        assertThat((Map<String, Object>) sigHere.get("admitted")).containsEntry("code", ACC).containsEntry("name", name(ACC));
        assertThat((Map<String, Object>) sigElsewhere.get("admitted")).containsEntry("code", CS).containsEntry("name", name(CS));
    }

    Map<String, Object> ok(ResponseEntity<Map> r) {
        assertThat(r.getStatusCode().value()).as(String.valueOf(r.getBody())).isEqualTo(200);
        return r.getBody();
    }
}
