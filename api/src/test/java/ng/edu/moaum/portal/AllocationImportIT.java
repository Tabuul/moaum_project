package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.ArrayList;
import java.util.HashMap;
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
 * Bulk course allocation (V321): the file is judged against the register row by row — an unknown staff number, a
 * lecturer put in the wrong department, an unknown course, a course of another department without the cross-department
 * mark, an unknown session, a course not offered in the semester, a duplicate in the file, an allocation already on
 * record, a load over twelve units — and only the valid rows are written, through the same allocation every desk uses;
 * a Head of Department is refused another department's courses; the same key never allocates twice; the lecturer sees
 * the course on their teaching page and the result desks read the same allocation. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class AllocationImportIT {

    static final String SESSION = "2114/2115";

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    ItSupport it;
    String academic = ItSupport.token("academic");
    String hod;
    UUID lecturerA;
    UUID lecturerB;
    String otherDept;

    static Map<String, Object> m(Object o) { return (Map<String, Object>) o; }
    static List<Map<String, Object>> l(Object o) { return (List<Map<String, Object>>) o; }

    private Map<String, Object> row(int n, String staff, String course, String... kv) {
        Map<String, Object> r = new HashMap<>();
        r.put("row", n); r.put("staffId", staff); r.put("courseCode", course); r.put("session", SESSION); r.put("semester", "1");
        for (int i = 0; i + 1 < kv.length; i += 2) r.put(kv[i], kv[i + 1]);
        return r;
    }

    private UUID lecturer(String staff, String surname, String dept) {
        UUID id = it.person(staff, surname);
        it.db(() -> jdbc.sql("""
                INSERT INTO iam.office_assignment (id, person_id, office_code, scope_kind, scope_id, instrument, granted_by, valid_from)
                SELECT gen_random_uuid(), :p, 'lecturer', 'department', :d, 'integration test', :p, current_date
                 WHERE NOT EXISTS (SELECT 1 FROM iam.office_assignment a WHERE a.person_id = :p AND a.office_code = 'lecturer' AND a.scope_id = :d AND (a.valid_to IS NULL OR a.valid_to >= current_date))
                """).param("p", id).param("d", dept).update());
        return id;
    }

    private void course(String code, String title, int units, String dept) {
        ResponseEntity<Map> r = it.call(academic, HttpMethod.PUT, "/api/v1/registration/courses/" + code,
                Map.of("title", title, "units", units, "semester", 1, "level", 200, "deptCode", dept, "kind", "Core", "state", "LIVE"));
        assertThat(r.getStatusCode().value()).as(String.valueOf(r.getBody())).isEqualTo(200);
    }

    private UUID offering(String code, int semester) {
        ResponseEntity<Map> r = it.call(academic, HttpMethod.PUT, "/api/v1/registration/offerings", Map.of("courseCode", code, "session", SESSION, "semester", semester));
        assertThat(r.getStatusCode().value()).as(String.valueOf(r.getBody())).isEqualTo(200);
        return UUID.fromString(String.valueOf(r.getBody().get("id")));
    }

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
        it.session(SESSION, 2114);
        hod = it.officer("hod", "department", "MTC");
        lecturerA = lecturer("ZZ-ALC-A", "ZZALCA", "MTC");
        lecturerB = lecturer("ZZ-ALC-B", "ZZALCB", "MTC");
        otherDept = jdbc.sql("SELECT code FROM ref.department WHERE code <> 'MTC' AND ended_on IS NULL ORDER BY code LIMIT 1").query(String.class).single();
        course("ZZA 201", "Allocation import one", 3, "MTC");
        course("ZZA 202", "Allocation import two", 4, "MTC");
        course("ZZA 203", "Allocation import three", 3, "MTC");
        course("ZZA 204", "Allocation import four", 3, "MTC");
        course("ZZA 205", "Allocation import five", 2, "MTC");
        course("ZZA 299", "Not offered this semester", 3, "MTC");
        course("ZZB 201", "Another department's course", 3, otherDept);
        for (String c : List.of("ZZA 201", "ZZA 202", "ZZA 203", "ZZA 204", "ZZA 205", "ZZB 201")) offering(c, 1);
        offering("ZZA 299", 2);
        // a clean slate for the test's own offerings on a database that ran it before
        it.db(() -> {
            jdbc.sql("DELETE FROM catalogue.offering_teacher WHERE offering_id IN (SELECT id FROM catalogue.offering WHERE session = :s)").param("s", SESSION).update();
            return jdbc.sql("UPDATE catalogue.offering SET lecturer_id = NULL, second_examiner_id = NULL, allocated_on = NULL WHERE session = :s AND NOT EXISTS (SELECT 1 FROM assessment.score_sheet sh WHERE sh.offering_id = catalogue.offering.id)").param("s", SESSION).update();
        });
    }

    @Test
    void everyRowIsJudgedAgainstTheRegisterAndOnlyTheValidOnesAreWritten() {
        List<Map<String, Object>> rows = new ArrayList<>();
        rows.add(row(2, "ZZ-ALC-A", "ZZA 201", "lecturerName", "ZZALCA, Invented", "lecturerDept", "MTC", "courseTitle", "Allocation import one"));
        rows.add(row(3, "ZZ-NOBODY", "ZZA 202"));
        rows.add(row(4, "ZZ-ALC-A", "ZZA 202", "lecturerDept", otherDept));
        rows.add(row(5, "ZZ-ALC-A", "ZZX 999"));
        rows.add(row(6, "ZZ-ALC-A", "ZZB 201"));
        rows.add(row(7, "ZZ-ALC-A", "ZZB 201", "crossDepartment", "YES"));
        rows.add(row(8, "ZZ-ALC-A", "ZZA 203", "session", "2999/3000"));
        rows.add(row(9, "ZZ-ALC-A", "ZZA 299"));
        rows.add(row(10, "ZZ-ALC-B", "ZZA 203", "courseTitle", "A different title"));
        rows.add(row(11, "ZZ-ALC-B", "ZZA 203"));
        rows.add(row(12, "ZZ-ALC-B", "ZZA 204", "role", "Second examiner"));
        rows.add(row(13, "ZZ-ALC-A", "ZZA 204"));
        rows.add(row(14, "ZZ-ALC-B", "ZZA 204", "role", "Co-lecturer"));
        rows.add(row(15, "ZZ-ALC-A", "ZZA 205", "semester", "First", "level", "200"));
        rows.add(row(16, "ZZ-ALC-A", "ZZA 205", "programme", "C00023"));

        ResponseEntity<Map> v = it.call(hod, HttpMethod.POST, "/api/v1/allocation/import/validate", Map.of("rows", rows, "options", Map.of()));
        assertThat(v.getStatusCode().value()).as(String.valueOf(v.getBody())).isEqualTo(200);
        Map<Integer, Map<String, Object>> by = new HashMap<>();
        for (Map<String, Object> f : l(v.getBody().get("rows"))) by.put(((Number) f.get("row")).intValue(), f);
        assertThat(by.get(2).get("status")).isEqualTo("VALID");
        assertThat(by.get(3).get("status")).isEqualTo("ERROR");
        assertThat((List<String>) by.get(3).get("codes")).contains("STAFF_ID_NOT_FOUND");
        assertThat((List<String>) by.get(4).get("codes")).contains("LECTURER_DEPARTMENT_MISMATCH");
        assertThat((List<String>) by.get(5).get("codes")).contains("COURSE_NOT_FOUND");
        assertThat((List<String>) by.get(6).get("codes")).contains("CROSS_DEPARTMENT_NOT_ALLOWED");
        // a Head of Department allocates only the department's own courses, cross-department mark or not
        assertThat((List<String>) by.get(7).get("codes")).contains("OUT_OF_SCOPE");
        assertThat((List<String>) by.get(8).get("codes")).contains("SESSION_NOT_FOUND");
        assertThat((List<String>) by.get(9).get("codes")).contains("COURSE_NOT_OFFERED");
        assertThat(by.get(10).get("status")).isEqualTo("WARNING");
        assertThat((List<String>) by.get(10).get("codes")).contains("COURSE_TITLE_MISMATCH");
        assertThat(by.get(11).get("status")).isEqualTo("DUPLICATE");
        assertThat((List<String>) by.get(11).get("codes")).contains("DUPLICATE_IN_FILE");
        assertThat(by.get(12).get("status")).isEqualTo("VALID");
        assertThat(by.get(13).get("status")).isEqualTo("VALID");
        assertThat(by.get(14).get("status")).isEqualTo("VALID");
        assertThat(by.get(15).get("status")).isEqualTo("VALID");
        assertThat((List<String>) by.get(16).get("codes")).contains("COURSE_NOT_OFFERED_TO_PROGRAMME");
        Map<String, Object> summary = m(v.getBody().get("summary"));
        assertThat(summary.get("total")).isEqualTo(15);
        assertThat(summary.get("willImport")).isEqualTo(6);
        // nothing was written by the validation
        assertThat(jdbc.sql("SELECT count(*) FROM catalogue.offering WHERE session = :s AND lecturer_id IS NOT NULL").param("s", SESSION).query(Long.class).single()).isZero();

        // an unauthorised office is refused, and a lecturer's token cannot import
        assertThat(it.call(ItSupport.token("lecturer"), HttpMethod.POST, "/api/v1/allocation/import", Map.of("rows", rows, "importKey", UUID.randomUUID().toString())).getStatusCode().value()).isEqualTo(403);
        // an import without its key is refused
        assertThat(it.call(hod, HttpMethod.POST, "/api/v1/allocation/import", Map.of("rows", rows)).getStatusCode().value()).isEqualTo(422);

        UUID key = UUID.randomUUID();
        ResponseEntity<Map> imp = it.call(hod, HttpMethod.POST, "/api/v1/allocation/import", Map.of("rows", rows, "options", Map.of(), "fileName", "allocations.xlsx", "importKey", key.toString()));
        assertThat(imp.getStatusCode().value()).as(String.valueOf(imp.getBody())).isEqualTo(200);
        assertThat(imp.getBody().get("imported")).isEqualTo(6);
        assertThat(imp.getBody().get("status")).isEqualTo("COMPLETED_WITH_ERRORS");
        assertThat(String.valueOf(imp.getBody().get("reference"))).startsWith("ALLOC/2114-2115/");
        assertThat(imp.getBody().get("repeated")).isEqualTo(false);

        // the allocations are on the offerings themselves, as every allocation is
        assertThat(jdbc.sql("SELECT lecturer_id FROM catalogue.offering WHERE session = :s AND course_code = 'ZZA 201'").param("s", SESSION).query(UUID.class).single()).isEqualTo(lecturerA);
        assertThat(jdbc.sql("SELECT lecturer_id FROM catalogue.offering WHERE session = :s AND course_code = 'ZZA 203'").param("s", SESSION).query(UUID.class).single()).isEqualTo(lecturerB);
        Map<String, Object> four = jdbc.sql("SELECT lecturer_id::text AS lead, second_examiner_id::text AS second FROM catalogue.offering WHERE session = :s AND course_code = 'ZZA 204'").param("s", SESSION).query().singleRow();
        assertThat(four.get("lead")).isEqualTo(lecturerA.toString());
        assertThat(four.get("second")).isEqualTo(lecturerB.toString());
        assertThat(jdbc.sql("SELECT count(*) FROM catalogue.offering_teacher t JOIN catalogue.offering o ON o.id = t.offering_id WHERE o.session = :s AND o.course_code = 'ZZA 204' AND t.lecturer_id = :l")
                .param("s", SESSION).param("l", lecturerB).query(Long.class).single()).isEqualTo(1L);
        assertThat(jdbc.sql("SELECT lecturer_id FROM catalogue.offering WHERE session = :s AND course_code = 'ZZB 201'").param("s", SESSION).query(UUID.class).optional()).isEmpty();

        // the same key again: the record already made, nothing allocated twice
        ResponseEntity<Map> again = it.call(hod, HttpMethod.POST, "/api/v1/allocation/import", Map.of("rows", rows, "options", Map.of(), "fileName", "allocations.xlsx", "importKey", key.toString()));
        assertThat(again.getStatusCode().value()).isEqualTo(200);
        assertThat(again.getBody().get("repeated")).isEqualTo(true);
        assertThat(again.getBody().get("reference")).isEqualTo(imp.getBody().get("reference"));

        // a second file: what is on record is reported as existing, and a new lead needs the replace option
        List<Map<String, Object>> second = List.of(row(2, "ZZ-ALC-A", "ZZA 201"), row(3, "ZZ-ALC-B", "ZZA 201"));
        ResponseEntity<Map> v2 = it.call(hod, HttpMethod.POST, "/api/v1/allocation/import/validate", Map.of("rows", second, "options", Map.of()));
        List<Map<String, Object>> f2 = l(v2.getBody().get("rows"));
        assertThat(f2.get(0).get("status")).isEqualTo("EXISTING");
        assertThat((List<String>) f2.get(1).get("codes")).contains("ALLOCATION_EXISTS_OTHER");
        ResponseEntity<Map> v3 = it.call(hod, HttpMethod.POST, "/api/v1/allocation/import/validate", Map.of("rows", second, "options", Map.of("replaceExisting", true)));
        assertThat(l(v3.getBody().get("rows")).get(1).get("status")).isEqualTo("WARNING");

        // the load: lecturer A leads 3 + 3 + 2 = 8 units; a fourth course of 5 makes 13, over twelve, unless the overload is allowed
        course("ZZA 206", "Allocation import six", 5, "MTC");
        offering("ZZA 206", 1);
        List<Map<String, Object>> heavy = List.of(row(2, "ZZ-ALC-A", "ZZA 206"));
        ResponseEntity<Map> v4 = it.call(hod, HttpMethod.POST, "/api/v1/allocation/import/validate", Map.of("rows", heavy, "options", Map.of()));
        assertThat((List<String>) l(v4.getBody().get("rows")).get(0).get("codes")).contains("LECTURER_WORKLOAD_EXCEEDED");
        assertThat(l(v4.getBody().get("rows")).get(0).get("status")).isEqualTo("ERROR");
        ResponseEntity<Map> v5 = it.call(hod, HttpMethod.POST, "/api/v1/allocation/import/validate", Map.of("rows", heavy, "options", Map.of("allowOverload", true)));
        assertThat(l(v5.getBody().get("rows")).get(0).get("status")).isEqualTo("WARNING");

        // the history, in the department's scope, with the error report's findings
        ResponseEntity<List> history = it.getList(hod, "/api/v1/allocation/imports");
        assertThat(history.getStatusCode().value()).isEqualTo(200);
        assertThat((List<Map<String, Object>>) history.getBody()).anySatisfy(h -> assertThat(h.get("reference")).isEqualTo(imp.getBody().get("reference")));
        ResponseEntity<Map> one = it.get(hod, "/api/v1/allocation/imports/" + imp.getBody().get("id"));
        assertThat(one.getStatusCode().value()).isEqualTo(200);
        assertThat(l(one.getBody().get("findings"))).hasSize(15);
        // another department's Head of Department does not see it
        assertThat((List<Map<String, Object>>) it.getList(it.officer("hod", "department", otherDept), "/api/v1/allocation/imports").getBody())
                .noneMatch(h -> imp.getBody().get("reference").equals(h.get("reference")));

        // the lecturer sees the course on their teaching page; the allocation desk and the result desks read the same offering
        String lect = TestTokens.token(lecturerA, List.of("lecturer"));
        ResponseEntity<Map> teaching = it.get(lect, "/api/v1/me/teaching?session=" + SESSION);
        assertThat(teaching.getStatusCode().value()).isEqualTo(200);
        assertThat(String.valueOf(teaching.getBody())).contains("ZZA 201");
        ResponseEntity<List> desk = it.getList(hod, "/api/v1/allocation?dept=MTC&session=" + SESSION + "&semester=1");
        assertThat((List<Map<String, Object>>) desk.getBody()).anySatisfy(o -> {
            assertThat(o.get("course_code")).isEqualTo("ZZA 204");
            assertThat(o.get("lecturer_id")).isEqualTo(lecturerA.toString());
        });
    }
}
