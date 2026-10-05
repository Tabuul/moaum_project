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
import org.springframework.http.HttpMethod;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.transaction.PlatformTransactionManager;

/**
 * V325 — a bounded office is granted with its bound, and a desk explains the scope it reads: a Head of Department
 * over the University or over no department is refused with the remedy; one over a department by its name is stored
 * as the code and read through the grant; one whose department has since ended is read through the lecturer grant,
 * the state says why the grant itself did not answer, and Users &amp; Roles marks the grant. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT,
        properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
class ScopeStateIT {

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;
    ItSupport it;
    String registrar = ItSupport.token("registrar");

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
    }

    @SuppressWarnings("rawtypes")
    private ResponseEntity<Map> asOffice(String token, String office, String path) {
        return it.callWith(token, HttpMethod.GET, path, null, Map.of("X-Active-Office", office));
    }

    @Test
    @SuppressWarnings({"rawtypes", "unchecked"})
    void aDepartmentOfficeIsGrantedOverItsDepartmentAndTheDeskExplainsWhatItReads() {
        String tag = UUID.randomUUID().toString().substring(0, 8);
        UUID p = it.person("ZZ-V325-" + tag, "ZZSCOPE" + tag.toUpperCase());
        String hod = TestTokens.token(p, List.of("hod"));
        String grants = "/api/v1/iam/persons/" + p + "/office-assignments";

        // before any grant: the desk says no live grant stands
        ResponseEntity<Map> s = asOffice(hod, "hod", "/api/v1/iam/me/scope");
        assertThat(s.getStatusCode().value()).as(String.valueOf(s.getBody())).isEqualTo(200);
        assertThat(s.getBody().get("bounded")).isEqualTo(true);
        assertThat(s.getBody().get("kind")).isEqualTo("department");
        assertThat(s.getBody().get("resolved")).isEqualTo(false);
        assertThat(s.getBody().get("reason")).isEqualTo("NO_LIVE_GRANT");

        // over the University: refused with the remedy; over a department with none chosen: refused
        ResponseEntity<Map> r = it.call(registrar, HttpMethod.POST, grants,
                Map.of("officeCode", "hod", "scopeKind", "institution", "instrument", "ScopeStateIT"));
        assertThat(r.getStatusCode().value()).as(String.valueOf(r.getBody())).isEqualTo(422);
        assertThat(r.getBody().get("code")).isEqualTo("OFFICE_SCOPE_REQUIRED");
        assertThat(String.valueOf(r.getBody().get("remedy"))).contains("Users & Roles");
        r = it.call(registrar, HttpMethod.POST, grants,
                Map.of("officeCode", "hod", "scopeKind", "department", "scopeId", " ", "instrument", "ScopeStateIT"));
        assertThat(r.getStatusCode().value()).as(String.valueOf(r.getBody())).isEqualTo(422);
        assertThat(r.getBody().get("code")).isEqualTo("OFFICE_SCOPE_REQUIRED");

        // over the department by its name: granted, the code stored, the desk reads it through the grant
        r = it.call(registrar, HttpMethod.POST, grants,
                Map.of("officeCode", "hod", "scopeKind", "department", "scopeId", "Mathematics and Computer Science", "instrument", "ScopeStateIT"));
        assertThat(r.getStatusCode().value()).as(String.valueOf(r.getBody())).isEqualTo(201);
        assertThat(r.getBody().get("scopeId")).isEqualTo("MTC");
        s = asOffice(hod, "hod", "/api/v1/iam/me/scope");
        assertThat(s.getBody().get("resolved")).as(String.valueOf(s.getBody())).isEqualTo(true);
        assertThat(s.getBody().get("code")).isEqualTo("MTC");
        assertThat(s.getBody().get("source")).isEqualTo("OFFICE_GRANT");
        assertThat(s.getBody().get("reason")).isNull();
        assertThat(((Map<String, Object>) s.getBody().get("grant")).get("scopeId")).isEqualTo("MTC");
        // the desk itself (the staff list: it needs no clearance scheme, which a fresh database has not yet)
        ResponseEntity<Map> d = asOffice(hod, "hod", "/api/v1/hod/staff");
        assertThat(d.getStatusCode().value()).as(String.valueOf(d.getBody())).isEqualTo(200);
        assertThat(d.getBody().get("resolved")).isEqualTo(true);
        assertThat(d.getBody().get("dept")).isEqualTo("MTC");
    }

    @Test
    @SuppressWarnings({"rawtypes", "unchecked"})
    void aGrantWhoseDepartmentHasEndedIsReadThroughTheLecturerGrantAndTheConsoleMarksIt() {
        String tag = UUID.randomUUID().toString().substring(0, 8);
        UUID p = it.person("ZZ-V325-" + tag, "ZZENDED" + tag.toUpperCase());
        String code = "Z" + tag.substring(0, 5).toUpperCase();
        it.db(() -> {
            jdbc.sql("INSERT INTO ref.department (code, name, faculty_code) VALUES (:c, 'SCOPE STATE IT ' || :c, 'SC')")
                    .param("c", code).update();
            jdbc.sql("""
                    INSERT INTO iam.office_assignment (id, person_id, office_code, scope_kind, scope_id, instrument, granted_by, valid_from)
                    VALUES (gen_random_uuid(), :p, 'hod', 'department', :c, 'ScopeStateIT', :p, current_date),
                           (gen_random_uuid(), :p, 'lecturer', 'department', 'MTC', 'ScopeStateIT', :p, current_date)
                    """).param("p", p).param("c", code).update();
            jdbc.sql("UPDATE ref.department SET ended_on = current_date - 1 WHERE code = :c").param("c", code).update();
            return null;
        });
        String hod = TestTokens.token(p, List.of("hod"));

        // the desk reads MTC through the lecturer grant, and says why the office's own grant did not answer
        ResponseEntity<Map> s = asOffice(hod, "hod", "/api/v1/iam/me/scope");
        assertThat(s.getStatusCode().value()).as(String.valueOf(s.getBody())).isEqualTo(200);
        assertThat(s.getBody().get("resolved")).isEqualTo(true);
        assertThat(s.getBody().get("code")).isEqualTo("MTC");
        assertThat(s.getBody().get("source")).isEqualTo("LECTURER_GRANT");
        assertThat(s.getBody().get("reason")).isEqualTo("SCOPE_ENDED");
        assertThat(((Map<String, Object>) s.getBody().get("grant")).get("scopeId")).isEqualTo(code);
        ResponseEntity<Map> d = asOffice(hod, "hod", "/api/v1/hod/staff");
        assertThat(d.getStatusCode().value()).as(String.valueOf(d.getBody())).isEqualTo(200);
        assertThat(d.getBody().get("dept")).isEqualTo("MTC");

        // Users & Roles marks the grant: its scope resolves to nothing live
        ResponseEntity<List> all = it.callList(registrar, HttpMethod.GET, "/api/v1/iam/office-assignments", null);
        assertThat(all.getStatusCode().value()).isEqualTo(200);
        Map<String, Object> mine = ((List<Map<String, Object>>) all.getBody()).stream()
                .filter(g -> p.toString().equals(String.valueOf(g.get("personId"))) && "hod".equals(g.get("officeCode")))
                .findFirst().orElseThrow();
        assertThat(mine.get("scopeId")).isEqualTo(code);
        assertThat(mine.get("scopeLive")).isNull();
        Map<String, Object> teaching = ((List<Map<String, Object>>) all.getBody()).stream()
                .filter(g -> p.toString().equals(String.valueOf(g.get("personId"))) && "lecturer".equals(g.get("officeCode")))
                .findFirst().orElseThrow();
        assertThat(teaching.get("scopeLive")).isEqualTo("MTC");
    }
}
