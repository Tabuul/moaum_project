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
 * The Post-UTME paid applicants report (V479), end to end: a session's paid applicants listed one row an application — a
 * pending payment only under its own status — filtered by gender, programme, JAMB number, a search and payment dates; the
 * figures counted from the same rows; a Head of Department held to the department whatever the request names, for the list
 * and the download alike; each download recorded with its filters and rows; an office outside the report refused. Each run
 * files its applicants under its own far-future session. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class PaidApplicantsIT {

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    ItSupport it;
    final String academic = ItSupport.token("academic");
    final Random random = new Random();

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
    }

    /** an applicant of the session: JAMB's record (aggregate and gender), the candidate, the account, the application and the
     *  application-fee references — confirmed or not */
    UUID applicant(String session, String surname, String programmeCode, String mode, String sex, Integer aggregate, String email, String phone, boolean confirmed) {
        int n = random.nextInt(90_000_000) + 10_000_000;
        String jamb = session.substring(0, 4) + n + "PA";
        return it.db(() -> {
            UUID batch = UUID.randomUUID(), row = UUID.randomUUID(), cand = UUID.randomUUID(), acct = UUID.randomUUID(), app = UUID.randomUUID();
            jdbc.sql("INSERT INTO admissions.caps_batch (id, session, source, filename, file_sha256, rows_read, list_kind, downloaded_on, uploaded_by, uploaded_office, committed_at) VALUES (:id, :s, 'CAPS_DOWNLOAD', 'paid.xlsx', decode(md5(:id::text), 'hex'), 1, :k, current_date, gen_random_uuid(), 'academic', now())")
                    .param("id", batch).param("s", session).param("k", "UTME".equals(mode) ? "UTME" : "DIRECT_ENTRY").update();
            jdbc.sql("INSERT INTO admissions.caps_row (id, batch_id, session, jamb_reg_no, raw, surname, other_names, jamb_code, aggregate, entry_mode, sex) VALUES (:id, :b, :s, :j, '{}'::jsonb, :sn, 'Paid Person', :p, :agg, :m, :sex)")
                    .param("id", row).param("b", batch).param("s", session).param("j", jamb).param("sn", surname).param("p", programmeCode)
                    .param("agg", aggregate, java.sql.Types.INTEGER).param("m", mode).param("sex", sex).update();
            jdbc.sql("INSERT INTO admissions.candidate (id, session, jamb_reg_no, surname, other_names, programme, entry_mode, entry_level, offer_state, admitted_from) VALUES (:id, :s, :j, :sn, 'Paid Person', (SELECT name FROM ref.programme WHERE code = :p), :m, :l, 'PROPOSED', :r)")
                    .param("id", cand).param("s", session).param("j", jamb).param("sn", surname).param("p", programmeCode).param("m", mode)
                    .param("l", "UTME".equals(mode) ? 100 : 200).param("r", row).update();
            jdbc.sql("INSERT INTO admissions.applicant_account (id, session, candidate_id, jamb_key, email, phone, password_hash) VALUES (:id, :s, :c, :k, :e, :ph, 'SET_ON_FIRST_LOGIN')")
                    .param("id", acct).param("s", session).param("c", cand).param("k", jamb).param("e", email == null ? jamb.toLowerCase() + "@migrate.moau.local" : email)
                    .param("ph", phone).update();
            jdbc.sql("INSERT INTO admissions.application (id, account_id, candidate_id, session, application_no) VALUES (:id, :a, :c, :s, :no)")
                    .param("id", app).param("a", acct).param("c", cand).param("s", session).param("no", "APP/" + session.substring(2, 4) + "/" + String.format("%06d", n % 1_000_000)).update();
            jdbc.sql("""
                    INSERT INTO admissions.fee_reference (id, application_id, kind, reference, amount, expires_at, confirmed_at, confirmed_by, channel, receipt_no)
                    VALUES (gen_random_uuid(), :a, 'APPLICATION', :ref, 2000, now() + interval '1 day',
                            CASE WHEN :ok THEN now() END, CASE WHEN :ok THEN gen_random_uuid() END, CASE WHEN :ok THEN 'CARD' END, CASE WHEN :ok THEN :rc END)
                    """).param("a", app).param("ref", "PAIDIT-" + n).param("ok", confirmed).param("rc", "RCPAIDIT-" + n).update();
            return app;
        });
    }

    String other() {
        return jdbc.sql("SELECT code FROM ref.programme WHERE dept_code <> 'MTC' AND category = 'UNDER GRADUATE' AND NOT archived ORDER BY code LIMIT 1").query(String.class).single();
    }

    @Test
    void theSessionsPaidApplicantsAreListedFilteredScopedAndDownloadedOnTheRecord() {
        int y = 2300 + random.nextInt(600);
        String session = y + "/" + (y + 1);
        it.session(session, y);
        String tag = "ZZPAID" + (100000 + random.nextInt(900000));
        String base = "/api/v1/admissions/sessions/" + session + "/paid-applicants";
        String otherProg = other();
        UUID ada = applicant(session, tag + "ADA", "C00023", "UTME", "F", 231, tag.toLowerCase() + ".ada@example.com", "08031110001", true);
        UUID ben = applicant(session, tag + "BEN", otherProg, "UTME", "M", 205, tag.toLowerCase() + ".ben@example.com", "08031110002", true);
        UUID cal = applicant(session, tag + "CAL", "C00023", "UTME", "M", 199, tag.toLowerCase() + ".cal@example.com", "08031110003", false);
        UUID dan = applicant(session, tag + "DAN", "C00023", "DIRECT_ENTRY", "M", null, null, "00000000000", true);

        // the paid applicants, names A-Z: the pending payment is not paid; a Direct Entry candidate has no aggregate, and the
        // old portal's placeholder contacts are missing, never shown
        ResponseEntity<Map> list = it.get(academic, base);
        assertThat(list.getStatusCode().value()).as(String.valueOf(list.getBody())).isEqualTo(200);
        assertThat(((Number) list.getBody().get("total")).intValue()).isEqualTo(3);
        List<Map<String, Object>> rows = (List<Map<String, Object>>) list.getBody().get("rows");
        assertThat(rows).extracting(r -> r.get("application_id").toString()).containsExactly(ada.toString(), ben.toString(), dan.toString());
        Map<String, Object> first = rows.get(0);
        assertThat(first.get("full_name")).isEqualTo(tag + "ADA, Paid Person");
        assertThat(first.get("sex")).isEqualTo("F");
        assertThat(first.get("utme_aggregate")).isEqualTo(231);
        assertThat(first.get("phone")).isEqualTo("08031110001");
        assertThat(first.get("payment_status")).isEqualTo("VERIFIED");
        Map<String, Object> de = rows.get(2);
        assertThat(de.get("utme_aggregate")).isNull();
        assertThat(de.get("phone")).isNull();
        assertThat(de.get("email")).isNull();
        assertThat((List<String>) de.get("missing")).containsExactly("PHONE", "EMAIL");
        assertThat((List<Map<String, Object>>) list.getBody().get("missing")).extracting(m -> m.get("field")).containsExactlyInAnyOrder("PHONE", "EMAIL");

        // payment status, gender, programme, JAMB number, search and payment dates are the server's filters
        assertThat(total(base + "?status=PENDING")).isEqualTo(1);
        assertThat(total(base + "?status=ALL")).isEqualTo(4);
        assertThat(total(base + "?sex=F")).isEqualTo(1);
        assertThat(total(base + "?prog=C00023")).isEqualTo(2);
        assertThat(total(base + "?entry=DIRECT_ENTRY")).isEqualTo(1);
        String adaJamb = (String) first.get("jamb_reg_no");
        assertThat(total(base + "?jamb=" + adaJamb.toLowerCase())).isEqualTo(1);
        assertThat(total(base + "?q=" + tag.toLowerCase() + "ben")).isEqualTo(1);
        assertThat(total(base + "?from=" + LocalDate.now().plusDays(2))).isZero();
        assertThat(total(base + "?from=" + LocalDate.now().minusDays(2) + "&to=" + LocalDate.now().plusDays(1))).isEqualTo(3);
        assertThat(it.get(academic, base + "?status=PAID").getStatusCode().is4xxClientError()).isTrue();
        assertThat(it.get(academic, base + "?from=2030-01-02&to=2030-01-01").getStatusCode().is4xxClientError()).isTrue();

        // the figures, from the same rows
        Map<String, Object> summary = it.get(academic, base + "/summary").getBody();
        assertThat(((Number) summary.get("total")).intValue()).isEqualTo(3);
        assertThat((List<Map<String, Object>>) summary.get("bySex")).extracting(m -> m.get("sex") + "=" + m.get("n")).containsExactlyInAnyOrder("M=2", "F=1");
        assertThat((List<Map<String, Object>>) summary.get("byStatus")).extracting(m -> m.get("status") + "=" + m.get("n")).containsExactlyInAnyOrder("VERIFIED=3", "PENDING=1");
        assertThat((List<Map<String, Object>>) summary.get("byProgramme")).extracting(m -> m.get("programme_code") + "=" + m.get("n"))
                .containsExactlyInAnyOrder("C00023=2", otherProg + "=1");
        // a gender chosen narrows the total; the gender figures stay, so the other is a click away
        Map<String, Object> women = it.get(academic, base + "/summary?sex=F").getBody();
        assertThat(((Number) women.get("total")).intValue()).isEqualTo(1);
        assertThat((List<Map<String, Object>>) women.get("bySex")).extracting(m -> m.get("sex") + "=" + m.get("n")).containsExactlyInAnyOrder("M=2", "F=1");
        assertThat((List<Map<String, Object>>) women.get("byEntryMode")).extracting(m -> m.get("entry_mode") + "=" + m.get("n")).containsExactly("UTME=1");
        assertThat((List<Map<String, Object>>) it.get(academic, base + "/options").getBody().get("programmes"))
                .extracting(m -> m.get("programme_code")).contains("C00023", otherProg);

        // a Head of Department reads the department alone, whatever the request names — the list, the figures, the download
        String hod = it.officer("hod", "department", "MTC");
        assertThat(totalFor(hod, base)).isEqualTo(2);
        assertThat(it.get(hod, base + "?dept=" + deptOf(otherProg)).getStatusCode().is4xxClientError()).isTrue();
        assertThat(it.get(hod, base + "?prog=" + otherProg).getStatusCode().is4xxClientError()).isTrue();
        assertThat(it.call(hod, HttpMethod.POST, base + "/export", Map.of("format", "PDF", "prog", otherProg)).getStatusCode().is4xxClientError()).isTrue();
        ResponseEntity<Map> hodExport = it.call(hod, HttpMethod.POST, base + "/export", Map.of("format", "PDF"));
        assertThat(hodExport.getStatusCode().value()).as(String.valueOf(hodExport.getBody())).isEqualTo(200);
        assertThat(((Number) hodExport.getBody().get("total")).intValue()).isEqualTo(2);

        // the whole selection for the export engine, and the download recorded: who, the format, the filters, the rows
        ResponseEntity<Map> export = it.call(academic, HttpMethod.POST, base + "/export", Map.of("format", "XLSX", "sex", "M"));
        assertThat(export.getStatusCode().value()).as(String.valueOf(export.getBody())).isEqualTo(200);
        assertThat(((Number) export.getBody().get("total")).intValue()).isEqualTo(2);
        assertThat((List<Map<String, Object>>) export.getBody().get("rows")).extracting(r -> r.get("full_name")).containsExactly(tag + "BEN, Paid Person", tag + "DAN, Paid Person");
        List<Map<String, Object>> recorded = jdbc.sql("""
                SELECT format, row_count, office, filters->>'gender' AS gender, filters->>'status' AS status, filters->>'department' AS dept, exported_by IS NOT NULL AS attributed
                  FROM admissions.report_export WHERE report = 'POST_UTME_PAID_APPLICANTS' AND session = :s ORDER BY exported_at
                """).param("s", session).query().listOfRows();
        assertThat(recorded).hasSize(2);
        assertThat(recorded.get(0)).containsEntry("format", "PDF").containsEntry("row_count", 2).containsEntry("office", "hod").containsEntry("dept", "MTC").containsEntry("attributed", true);
        assertThat(recorded.get(1)).containsEntry("format", "XLSX").containsEntry("row_count", 2).containsEntry("gender", "M").containsEntry("status", "VERIFIED");
        assertThat(it.call(academic, HttpMethod.POST, base + "/export", Map.of("format", "CSV")).getStatusCode().is4xxClientError()).isTrue();

        // an office outside the report is refused, the list and the download alike
        String bursar = ItSupport.token("bursar");
        assertThat(it.get(bursar, base).getStatusCode().value()).isEqualTo(403);
        assertThat(it.call(bursar, HttpMethod.POST, base + "/export", Map.of("format", "XLSX")).getStatusCode().value()).isEqualTo(403);
        assertThat(cal).isNotNull();
    }

    int total(String path) {
        return totalFor(academic, path);
    }

    int totalFor(String token, String path) {
        ResponseEntity<Map> r = it.get(token, path);
        assertThat(r.getStatusCode().value()).as(path + " " + r.getBody()).isEqualTo(200);
        return ((Number) r.getBody().get("total")).intValue();
    }

    String deptOf(String programme) {
        return jdbc.sql("SELECT dept_code FROM ref.programme WHERE code = :p").param("p", programme).query(String.class).single();
    }
}
