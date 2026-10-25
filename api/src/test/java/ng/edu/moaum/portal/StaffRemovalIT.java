package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.List;
import java.util.Map;
import java.util.Random;
import java.util.UUID;

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
 * V656: staff deleted or deactivated over the API. Two lecturers loaded through the teaching-staff upload (one then given a class)
 * and two members of non-academic staff through the nominal roll (one then signed in). The Directorate of ICT previews deleting all
 * four (nothing written), Human Resources may not touch a lecturer, a lecturer may not reach the desk, a reason is required; applied,
 * the two never used are deleted and the two tied to records deactivated — gone from both lists, their class still theirs; the
 * removed staff are listed with what tied them; a deactivated lecturer is restored once, back on the list, by an office that may,
 * not by Human Resources. The old outright delete is gone. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class StaffRemovalIT {

    private static final String I = "/api/v1/iam";

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    @Test
    void staffTiedToNothingAreDeletedTheRestDeactivatedAndRestorable() {
        ItSupport it = new ItSupport(port, jdbc, transactions);
        String ict = it.officer("ict", "institution", "University");
        String hrm = ItSupport.token("hrm");
        String[] dept = jdbc.sql("""
                SELECT d.code || '|' || d.name FROM ref.programme p JOIN ref.department d ON d.code = p.dept_code JOIN ref.faculty f ON f.code = p.faculty_code
                 WHERE p.category = 'UNDER GRADUATE' AND NOT p.archived AND coalesce(f.college_code, '') <> 'CHS' AND d.ended_on IS NULL ORDER BY p.code LIMIT 1
                """).query(String.class).single().split("\\|");
        Random rnd = new Random();
        String[] pno = new String[4];
        for (int i = 0; i < 4; i++) {
            String n;
            do {
                n = String.valueOf(9_000_000 + rnd.nextInt(999_999));
            } while (it.taken("P" + n) || jdbc.sql("SELECT count(*) FROM iam.person WHERE staff_number = :s").param("s", "P" + n).query(Integer.class).single() > 0);
            pno[i] = n;
        }

        // two lecturers through the teaching-staff upload, two non-academic staff through the roll
        ResponseEntity<Map> lect = it.call(ict, HttpMethod.POST, I + "/lecturers/import", Map.of("rows", List.of(
                Map.of("pno", pno[0], "full_names", "Unused Remove Lecturer", "sex", "F", "department", dept[0], "present_rank", "LECTURER II"),
                Map.of("pno", pno[1], "full_names", "Teaching Remove Lecturer", "sex", "M", "department", dept[0], "present_rank", "LECTURER I"))));
        assertThat(lect.getStatusCode().value()).as(String.valueOf(lect.getBody())).isEqualTo(200);
        assertThat(lect.getBody()).containsEntry("created", 2);
        ResponseEntity<Map> roll = it.call(hrm, HttpMethod.POST, I + "/staff/import", Map.of("dryRun", false, "rows", List.of(
                Map.of("pno", pno[2], "full_names", "Unused Remove Clerk", "department", dept[1], "present_rank", "CLERICAL OFFICER"),
                Map.of("pno", pno[3], "full_names", "SignedIn Remove Clerk", "department", dept[1], "present_rank", "SENIOR CLERK"))));
        assertThat(roll.getStatusCode().value()).as(String.valueOf(roll.getBody())).isEqualTo(200);
        assertThat(roll.getBody()).containsEntry("created", 2);
        UUID a = person("P" + pno[0]), b = person("P" + pno[1]), c = person("P" + pno[2]), d = person("P" + pno[3]);
        String course = jdbc.sql("SELECT 'ZSR ' || x FROM generate_series(100, 999) x WHERE NOT EXISTS (SELECT 1 FROM catalogue.course c WHERE c.code = 'ZSR ' || x) ORDER BY random() LIMIT 1")
                .query(String.class).single();
        it.db(() -> {
            jdbc.sql("INSERT INTO catalogue.course (code, title, units, semester, level, dept_code, kind, state) VALUES (:c, 'Staff Removal Test', 2, 2, 100, :d, 'Core', 'LIVE')")
                    .param("c", course).param("d", dept[0]).update();
            String session = jdbc.sql("SELECT m.session FROM policy.semester m WHERE m.number = 2 ORDER BY m.session DESC LIMIT 1").query(String.class).single();
            jdbc.sql("INSERT INTO catalogue.offering (id, course_code, session, semester, lecturer_id) VALUES (gen_random_uuid(), :c, :s, 2, :b)")
                    .param("c", course).param("s", session).param("b", b).update();
            jdbc.sql("INSERT INTO iam.credential (person_id, username, password_hash, must_change, set_by, last_sign_in_at) VALUES (:d, :u, :h, false, :d, now())")
                    .param("d", d).param("u", "zzsr" + pno[3]).param("h", "$2a$12$staffremovalitnotarealhash" + "x".repeat(29)).update();
            return 0;
        });
        assertThat(ids(it.getList(ict, I + "/lecturers"))).contains(a.toString(), b.toString());
        assertThat(ids(it.getList(ict, I + "/staff"))).contains(c.toString(), d.toString());
        List<String> four = List.of(a.toString(), b.toString(), c.toString(), d.toString());

        // the preview: deleted where tied to nothing, deactivated where tied; nothing written
        ResponseEntity<List> preview = it.callList(ict, HttpMethod.POST, I + "/staff/remove/preview", Map.of("ids", four, "mode", "AUTO"));
        assertThat(preview.getStatusCode().value()).as(String.valueOf(preview.getBody())).isEqualTo(200);
        Map<String, Map<String, Object>> by = byPerson((List<Map<String, Object>>) preview.getBody());
        assertThat(by.get(a.toString())).containsEntry("outcome", "REMOVE").containsEntry("applied", false);
        assertThat(by.get(b.toString())).containsEntry("outcome", "DEACTIVATE");
        assertThat((List<Map<String, Object>>) by.get(b.toString()).get("ties")).anySatisfy(t -> assertThat(t).containsEntry("label", "Lecturer of a course class"));
        assertThat(by.get(c.toString())).containsEntry("outcome", "REMOVE");
        assertThat(by.get(d.toString())).containsEntry("outcome", "DEACTIVATE");
        assertThat((List<Map<String, Object>>) by.get(d.toString()).get("ties")).anySatisfy(t -> assertThat(t).containsEntry("label", "Has signed in to the portal"));
        assertThat(jdbc.sql("SELECT count(*) FROM iam.staff_change WHERE person_id IN (:a, :b, :c, :d)").param("a", a).param("b", b).param("c", c).param("d", d)
                .query(Integer.class).single()).isZero();

        // who may: Human Resources not a lecturer; a lecturer not the desk at all; a reason is required
        ResponseEntity<Map> byHr = it.call(hrm, HttpMethod.POST, I + "/staff/remove", Map.of("ids", List.of(a.toString()), "reasonCode", "ADDED_IN_ERROR"));
        assertThat(byHr.getStatusCode().value()).isEqualTo(200);
        assertThat(byHr.getBody()).containsEntry("removed", 0).containsEntry("refused", 1);
        assertThat(((List<Map<String, Object>>) byHr.getBody().get("rows")).get(0)).containsEntry("outcome", "NOT_PERMITTED");
        assertThat(it.callList(ItSupport.token("lecturer"), HttpMethod.POST, I + "/staff/remove/preview", Map.of("ids", four)).getStatusCode().value()).isEqualTo(403);
        ResponseEntity<Map> noReason = it.call(ict, HttpMethod.POST, I + "/staff/remove", Map.of("ids", four));
        assertThat(noReason.getStatusCode().value()).isEqualTo(422);
        assertThat(noReason.getBody()).containsEntry("code", "STAFF_REASON");

        // applied
        ResponseEntity<Map> done = it.call(ict, HttpMethod.POST, I + "/staff/remove", Map.of("ids", four, "mode", "AUTO", "reasonCode", "LEFT_SERVICE", "reason", "Integration test"));
        assertThat(done.getStatusCode().value()).as(String.valueOf(done.getBody())).isEqualTo(200);
        assertThat(done.getBody()).containsEntry("removed", 2).containsEntry("deactivated", 2).containsEntry("refused", 0);
        assertThat(jdbc.sql("SELECT count(*) FROM iam.person WHERE id IN (:a, :c)").param("a", a).param("c", c).query(Integer.class).single()).isZero();
        assertThat(ids(it.getList(ict, I + "/lecturers"))).doesNotContain(a.toString(), b.toString());
        assertThat(ids(it.getList(ict, I + "/staff"))).doesNotContain(c.toString(), d.toString());
        assertThat(jdbc.sql("SELECT count(*) FROM catalogue.offering WHERE course_code = :c AND lecturer_id = :b").param("c", course).param("b", b).query(Integer.class).single())
                .isEqualTo(1);

        // the removed staff, with what tied them; Human Resources may not restore a lecturer; an office that may restores once
        List<Map<String, Object>> removed = (List<Map<String, Object>>) it.getList(ict, I + "/staff/removed?category=ACADEMIC").getBody();
        assertThat(removed).anySatisfy(x -> assertThat(x).containsEntry("person_id", a.toString()).containsEntry("action", "STAFF_REMOVED").containsEntry("restorable", false));
        Map<String, Object> bChange = removed.stream().filter(x -> b.toString().equals(x.get("person_id")) && "STAFF_DEACTIVATED".equals(x.get("action"))).findFirst().orElseThrow();
        assertThat(bChange).containsEntry("restorable", true).containsEntry("reason_code", "LEFT_SERVICE");
        assertThat((List<Map<String, Object>>) bChange.get("ties")).isNotEmpty();
        assertThat((List<Map<String, Object>>) it.getList(ict, I + "/staff/removed?category=NON_ACADEMIC").getBody())
                .anySatisfy(x -> assertThat(x).containsEntry("person_id", d.toString()).containsEntry("action", "STAFF_DEACTIVATED"));
        String restore = I + "/staff/removed/" + bChange.get("id") + "/restore";
        assertThat(it.call(hrm, HttpMethod.POST, restore, Map.of("reasonCode", "RETURNED_TO_SERVICE")).getStatusCode().value()).isEqualTo(403);
        ResponseEntity<Map> back = it.call(ict, HttpMethod.POST, restore, Map.of("reasonCode", "RETURNED_TO_SERVICE"));
        assertThat(back.getStatusCode().value()).as(String.valueOf(back.getBody())).isEqualTo(200);
        assertThat(((Number) back.getBody().get("grants_reopened")).intValue()).isEqualTo(1);
        assertThat(ids(it.getList(ict, I + "/lecturers"))).contains(b.toString());
        ResponseEntity<Map> twice = it.call(ict, HttpMethod.POST, restore, Map.of("reasonCode", "RETURNED_TO_SERVICE"));
        assertThat(twice.getStatusCode().value()).isEqualTo(422);
        assertThat(twice.getBody()).containsEntry("code", "STAFF_RESTORED");

        // the old outright delete is gone
        assertThat(it.call(ict, HttpMethod.POST, I + "/lecturers/delete", Map.of("ids", List.of(b.toString()))).getStatusCode().value()).isIn(404, 405);

        // tidy: the restored lecturer and the deactivated clerk taken off the lists again, so later runs see nothing of this one
        it.call(ict, HttpMethod.POST, I + "/staff/remove", Map.of("ids", List.of(b.toString()), "mode", "DEACTIVATE", "reasonCode", "OTHER", "reason", "Integration test tidy"));
    }

    private UUID person(String staffNumber) {
        return jdbc.sql("SELECT id FROM iam.person WHERE staff_number = :s").param("s", staffNumber).query(UUID.class).single();
    }

    private static List<String> ids(ResponseEntity<List> list) {
        return ((List<Map<String, Object>>) list.getBody()).stream().map(x -> String.valueOf(x.get("id"))).toList();
    }

    private static Map<String, Map<String, Object>> byPerson(List<Map<String, Object>> rows) {
        Map<String, Map<String, Object>> out = new java.util.HashMap<>();
        for (Map<String, Object> r : rows) out.put(String.valueOf(r.get("person_id")), r);
        return out;
    }
}
