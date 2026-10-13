package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

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
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.transaction.PlatformTransactionManager;

/**
 * Portal gap audit (V429 and the fixes beside it), through the API: a Head of Department reads the HR record of their own department's
 * staff and of anyone teaching their courses, never another department's; the Registry reads the possible duplicate students and a
 * lecturer does not; a student who was on the register under the JAMB number before admission is linked, not made twice. Runs again
 * on the same database. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class PortalAuditIT {

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

    @Test
    void staffRecordsKeepToTheDepartmentAndDuplicatesAreTheRegistrys() {
        int n = new Random().nextInt(8000) + 1000;
        String dept = "MTC";
        String other = jdbc.sql("SELECT code FROM ref.department WHERE code <> 'MTC' AND faculty_code IS NOT NULL AND faculty_code <> (SELECT faculty_code FROM ref.department WHERE code = 'MTC') ORDER BY code LIMIT 1")
                .query(String.class).single();
        // two members of staff: one at home in MTC, one at home elsewhere
        UUID ours = it.person("ZZAUDIT-OURS-" + n, "ZZAUDITOURS" + n);
        UUID theirs = it.person("ZZAUDIT-THEIRS-" + n, "ZZAUDITTHEIRS" + n);
        it.db(() -> {
            for (Object[] r : new Object[][] {{ours, dept}, {theirs, other}}) {
                jdbc.sql("""
                        INSERT INTO hrm.staff_record (person_id, home_department) VALUES (:p, :d)
                        ON CONFLICT (person_id) DO UPDATE SET home_department = EXCLUDED.home_department
                        """).param("p", r[0]).param("d", r[1]).update();
            }
            return null;
        });
        String hod = it.officer("hod", "department", dept);
        assertThat(it.get(hod, "/api/v1/hr/staff/" + ours).getStatusCode().value()).isEqualTo(200);
        assertThat(it.get(hod, "/api/v1/hr/staff/" + theirs).getStatusCode().value()).isEqualTo(403);
        assertThat(it.get(hod, "/api/v1/hr/staff/" + theirs + "/photo").getStatusCode().value()).isEqualTo(403);
        // the Registry reads every record, as before
        assertThat(it.get(ItSupport.token("registrar"), "/api/v1/hr/staff/" + theirs).getStatusCode().value()).isEqualTo(200);

        // the possible duplicates: two records under one JAMB number, read by the Registry, never by a lecturer
        String jamb = "8429" + String.format("%08d", n) + "DU";
        it.student("ZZDUPAUDITA" + n, "C00061", "MOAUM/ADM/29/8" + n + "0", null, 100);
        it.student("ZZDUPAUDITB" + n, "C00061", "MOAUM/ADM/29/9" + n + "0", null, 100);
        it.db(() -> jdbc.sql("UPDATE people.student SET jamb_reg_no = :j WHERE surname IN (:a, :b)")
                .param("j", jamb).param("a", "ZZDUPAUDITA" + n).param("b", "ZZDUPAUDITB" + n).update());
        List<Map<String, Object>> dups = (List<Map<String, Object>>) (List<?>) it.getList(ItSupport.token("registrar"), "/api/v1/student/duplicates").getBody();
        assertThat(dups).filteredOn(d -> jamb.equals(d.get("match_key"))).hasSize(2);
        assertThat(it.get(ItSupport.token("lecturer"), "/api/v1/student/duplicates").getStatusCode().value()).isEqualTo(403);
    }
}
