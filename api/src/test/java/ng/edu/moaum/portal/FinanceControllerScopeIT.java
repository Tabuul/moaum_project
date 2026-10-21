package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.List;
import java.util.Map;
import java.util.UUID;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.transaction.PlatformTransactionManager;

/**
 * V603: the College of Health Sciences' Finance Controller is held to the College on the server. Its dashboard reads the College's
 * fees position without the students (summary=true); the student register, a student's record and the search answer the
 * College's students alone — another faculty named is refused, another faculty's student is refused, a graduated College student
 * still opens; the University-wide finance desks with no College scope (the old GST payments, the registrations without fees)
 * refuse the office. The Bursar's University-wide reach is unchanged. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class FinanceControllerScopeIT {

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    /** the Finance Controller as the office is held: a person with a live grant over the College of Health Sciences */
    private String financeController(ItSupport it) {
        UUID p = it.person("MOAUM/FC/IT01", "ZZFCSCOPE");
        it.db(() -> jdbc.sql("""
                INSERT INTO iam.office_assignment (id, person_id, office_code, scope_kind, scope_id, instrument, granted_by, valid_from)
                SELECT gen_random_uuid(), :p, 'financecontroller', 'college', 'CHS', 'integration test', :p, current_date
                 WHERE NOT EXISTS (SELECT 1 FROM iam.office_assignment a WHERE a.person_id = :p AND a.office_code = 'financecontroller'
                                     AND (a.valid_to IS NULL OR a.valid_to >= current_date))
                """).param("p", p).update());
        return TestTokens.token(p, List.of("financecontroller"));
    }

    @Test
    void theFinanceControllerReadsTheCollegeAloneAndTheBursarTheUniversity() {
        ItSupport it = new ItSupport(port, jdbc, transactions);
        String fc = financeController(it);
        String bursar = ItSupport.token("bursar");
        String tag = it.freeSurname("ZZFCS");
        UUID nurse = it.student(tag + "NURSE", "C35147", null, it.freeNumber("MOAUM/FCS/26/1", 5), 300);
        UUID graduate = it.student(tag + "GRAD", "C00061", null, it.freeNumber("MOAUM/FCS/26/2", 5), 600);
        UUID computing = it.student(tag + "COMP", "C00023", null, it.freeNumber("MOAUM/FCS/26/3", 5), 300);
        it.db(() -> jdbc.sql("UPDATE people.student SET status = 'GRADUATED' WHERE id = :s").param("s", graduate).update());

        // the dashboard's summary: the College's totals and its programmes, without the students
        ResponseEntity<Map> summary = it.get(fc, "/api/v1/college/payments?summary=true");
        assertThat(summary.getStatusCode().value()).as(String.valueOf(summary.getBody())).isEqualTo(200);
        assertThat(summary.getBody()).containsKeys("session", "summary", "byProgramme").doesNotContainKeys("rows", "options");

        // the register: the College's faculty alone; another faculty named is refused
        ResponseEntity<Map> other = it.get(fc, "/api/v1/student/students?fac=SC");
        assertThat(other.getStatusCode().value()).as(String.valueOf(other.getBody())).isEqualTo(422);
        assertThat(other.getBody()).containsEntry("code", "SCOPE_COLLEGE");
        ResponseEntity<Map> list = it.get(fc, "/api/v1/student/students?q=" + tag);
        assertThat(list.getStatusCode().value()).as(String.valueOf(list.getBody())).isEqualTo(200);
        assertThat((List<Map<String, Object>>) list.getBody().get("rows")).extracting(r -> String.valueOf(r.get("id")))
                .contains(nurse.toString()).doesNotContain(computing.toString());

        // a student's record: a College student opens, graduated or not; another faculty's is refused
        assertThat(it.get(fc, "/api/v1/student/students/" + nurse).getStatusCode().value()).isEqualTo(200);
        assertThat(it.get(fc, "/api/v1/student/students/" + graduate).getStatusCode().value()).isEqualTo(200);
        assertThat(it.get(fc, "/api/v1/student/students/" + computing).getStatusCode().value()).isEqualTo(403);

        // the search finds the College's students alone
        Map<String, Object> found = it.get(fc, "/api/v1/student/search?kind=students&q=" + tag).getBody();
        assertThat((List<Map<String, Object>>) found.get("hits")).extracting(h -> String.valueOf(h.get("id")))
                .contains(nurse.toString(), graduate.toString()).doesNotContain(computing.toString());

        // the University-wide finance desks with no College scope refuse the office
        assertThat(it.get(fc, "/api/v1/finance/legacy-gst/summary").getStatusCode().value()).isEqualTo(403);
        assertThat(it.get(fc, "/api/v1/finance/registrations-without-fees").getStatusCode().value()).isEqualTo(403);

        // the Bursar reads the University as before
        assertThat(it.get(bursar, "/api/v1/student/students/" + computing).getStatusCode().value()).isEqualTo(200);
        assertThat(it.get(bursar, "/api/v1/finance/legacy-gst/summary").getStatusCode().value()).isEqualTo(200);
        Map<String, Object> all = it.get(bursar, "/api/v1/student/search?kind=students&q=" + tag).getBody();
        assertThat((List<Map<String, Object>>) all.get("hits")).extracting(h -> String.valueOf(h.get("id"))).contains(computing.toString(), nurse.toString());
    }
}
