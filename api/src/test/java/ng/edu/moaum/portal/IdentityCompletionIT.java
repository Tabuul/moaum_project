package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.awt.image.BufferedImage;
import java.io.ByteArrayOutputStream;
import java.util.Base64;
import java.util.List;
import java.util.Map;
import java.util.Random;
import java.util.UUID;

import javax.imageio.ImageIO;

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
 * V749: the identity-completion report over the API, on a small made-up population. Students in study: the counts move as the
 * students are added and as a blood group is confirmed at the desk or typed unconfirmed on the biodata; the list behind them is
 * filtered by what is missing and searched. Staff in service (a unit of the test's own): the photograph enhanced and accepted, the
 * e-mail verified or not or none, the blood group confirmed, unconfirmed or none, who cannot sign in, by category; the list filtered
 * the same. Each side read by its own offices and refused to the others. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class IdentityCompletionIT {

    private static final String BASE = "/api/v1/identity/completion";

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    ItSupport it;
    final String registrar = ItSupport.token("registrar");
    final String hrm = ItSupport.token("hrm");
    final String security = ItSupport.token("security");

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
    }

    /** the counts at BASE + path (/students or /staff) for the query given */
    private Map<String, Long> counts(String token, String path, String query) {
        ResponseEntity<Map> r = it.get(token, u -> u.path(BASE + path).query(query).build());
        assertThat(r.getStatusCode().value()).as(String.valueOf(r.getBody())).isEqualTo(200);
        Map<String, Long> out = new java.util.HashMap<>();
        ((Map<String, Object>) r.getBody().get("counts")).forEach((k, v) -> out.put(k, ((Number) v).longValue()));
        return out;
    }

    /** a page of the list at BASE + path; when it is the whole of it, the total says as much */
    private List<Map<String, Object>> list(String token, String path, String query) {
        ResponseEntity<Map> r = it.get(token, u -> u.path(BASE + path).query(query).build());
        assertThat(r.getStatusCode().value()).as(String.valueOf(r.getBody())).isEqualTo(200);
        List<Map<String, Object>> rows = (List<Map<String, Object>>) r.getBody().get("rows");
        if (!query.contains("page=")) assertThat(((Number) r.getBody().get("total")).intValue()).isEqualTo(rows.size());
        return rows;
    }

    private static List<Object> names(List<Map<String, Object>> rows) {
        return rows.stream().map(r -> r.get("name")).toList();
    }

    private static void moved(Map<String, Long> before, Map<String, Long> after, Map<String, Integer> by) {
        for (String k : before.keySet()) {
            assertThat(after.get(k) - before.get(k)).as(k).isEqualTo((long) by.getOrDefault(k, 0));
        }
    }

    @Test
    void theStudentsInStudyCountedAndListedByWhatIsMissing() {
        String tag = it.freeSurname("ZZIDCMP");
        String q = "programme=C00023&level=300";
        Map<String, Long> c0 = counts(registrar, "/students", q);

        UUID a = it.student(tag + "A", "C00023", it.freeNumber("MOAUM/ADM/26/", 6), it.freeNumber("MOAUM/IDM/26/", 5), 300);
        UUID b = it.student(tag + "B", "C00023", it.freeNumber("MOAUM/ADM/26/", 6), it.freeNumber("MOAUM/IDM/26/", 5), 300);
        it.student(tag + "C", "C00023", it.freeNumber("MOAUM/ADM/26/", 6), null, 300);
        it.db(() -> jdbc.sql("INSERT INTO people.student_photo (student_id, content, content_type, bytes, replaced_at, reason) VALUES (:s, :c, 'image/jpeg', 4, now(), 'integration test') ON CONFLICT (student_id) DO NOTHING")
                .param("s", a).param("c", new byte[] {(byte) 0xFF, (byte) 0xD8, (byte) 0xFF, (byte) 0xD9}).update());
        Map<String, Long> c1 = counts(registrar, "/students", q);
        moved(c0, c1, Map.of("total", 3, "blood_missing", 3, "with_photo", 1, "without_photo", 2, "without_matric", 1, "needs_update", 3));

        // the desk records A's blood group (confirmed); B types one on the biodata (not confirmed)
        assertThat(it.call(security, HttpMethod.PUT, "/api/v1/credentials/identity-cards/students/" + a + "/blood-group", Map.of("bloodGroup", "O-"))
                .getStatusCode().value()).isEqualTo(200);
        assertThat(it.call(TestTokens.token(b, List.of("student")), HttpMethod.PUT, "/api/v1/me/biodata/blood_group", Map.of("value", "A+"))
                .getStatusCode().value()).isEqualTo(200);
        Map<String, Long> c2 = counts(registrar, "/students", q);
        moved(c1, c2, Map.of("blood_confirmed", 1, "blood_missing", -2, "blood_unconfirmed", 1, "complete", 1, "needs_update", -1));

        // the students behind the counts, by what is missing
        String mine = q + "&q=" + tag;
        List<Map<String, Object>> all = list(registrar, "/students/list", mine);
        assertThat(names(all)).containsExactly(tag + "A Invented", tag + "B Invented", tag + "C Invented");
        assertThat(all.get(0)).containsEntry("complete", true).containsEntry("blood_group", "O-").containsEntry("blood_confirmed", true).containsEntry("has_photo", true)
                .containsKey("blood_confirmed_at");
        assertThat(all.get(1)).containsEntry("complete", false).containsEntry("blood_group", "A+").containsEntry("blood_confirmed", false).containsEntry("has_photo", false);
        assertThat(names(list(registrar, "/students/list", mine + "&missing=BLOOD"))).containsExactly(tag + "B Invented", tag + "C Invented");
        assertThat(names(list(registrar, "/students/list", mine + "&missing=photo"))).containsExactly(tag + "B Invented", tag + "C Invented");
        assertThat(names(list(registrar, "/students/list", mine + "&missing=MATRIC"))).containsExactly(tag + "C Invented");
        assertThat(names(list(registrar, "/students/list", mine + "&missing=ANY"))).containsExactly(tag + "B Invented", tag + "C Invented");
        assertThat(names(list(registrar, "/students/list", mine + "&size=1&page=1"))).containsExactly(tag + "B Invented");
        assertThat(it.get(registrar, u -> u.path(BASE + "/students/list").query(mine + "&missing=EMAIL").build()).getBody()).containsEntry("code", "IDENTITY_FILTER");

        // the readers: the Registry, Student Affairs, the card desk, ICT; not HR, not a lecturer
        for (String office : List.of("records", "dsa", "ict", "dregistrar")) {
            assertThat(it.get(ItSupport.token(office), BASE + "/students?programme=C00023").getStatusCode().value()).as(office).isEqualTo(200);
        }
        assertThat(it.get(security, BASE + "/students/list?" + mine).getStatusCode().value()).isEqualTo(200);
        assertThat(it.get(hrm, BASE + "/students?programme=C00023").getStatusCode().value()).isEqualTo(403);
        assertThat(it.get(ItSupport.token("lecturer"), BASE + "/students/list?" + mine).getStatusCode().value()).isEqualTo(403);
        Map<String, Object> filters = it.get(registrar, BASE + "/students?programme=C00023").getBody();
        assertThat((List<Map<String, Object>>) filters.get("programmes")).anySatisfy(p -> assertThat(p).containsEntry("code", "C00023"));
        assertThat((List<?>) filters.get("faculties")).isNotEmpty();
        assertThat((List<?>) filters.get("departments")).isNotEmpty();
    }

    /** a member of staff on the HR register in the test's own unit, with an office today when asked */
    private UUID staff(String number, String surname, String unit, String category, boolean office) {
        UUID p = it.person(number, surname);
        it.db(() -> {
            jdbc.sql("INSERT INTO hrm.staff_record (person_id, home_department, category, unit_as_given) VALUES (:p, :u, :c, :n) ON CONFLICT (person_id) DO NOTHING")
                    .param("p", p).param("u", unit).param("c", category).param("n", "ZZ Unit " + unit).update();
            if (office) {
                jdbc.sql("""
                        INSERT INTO iam.office_assignment (id, person_id, office_code, scope_kind, scope_id, instrument, granted_by, valid_from)
                        VALUES (gen_random_uuid(), :p, 'lecturer', 'department', 'MTC', 'identity completion test', :p, current_date)
                        """).param("p", p).update();
            }
            return 0;
        });
        return p;
    }

    private static String photo() throws Exception {
        Random random = new Random(11);
        BufferedImage img = new BufferedImage(720, 900, BufferedImage.TYPE_INT_RGB);
        for (int y = 0; y < 900; y++) {
            for (int x = 0; x < 720; x++) {
                int v = 100 + ((x / 7 + y / 11) % 2 == 0 ? 40 : 0) + random.nextInt(20);
                img.setRGB(x, y, (v << 16) | (v << 8) | v);
            }
        }
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        ImageIO.write(img, "jpg", out);
        return Base64.getEncoder().encodeToString(out.toByteArray());
    }

    @Test
    void theStaffInServiceCountedAndListedByWhatIsMissing() throws Exception {
        int n = it.freeDraw(100000, 999999, k -> List.of("ZZIDS1-" + k, "ZZIDS2-" + k, "ZZIDS3-" + k, "ZZIDSA" + k, "ZZIDSB" + k, "ZZIDSC" + k));
        String unit = "ZZU" + n;
        UUID s1 = staff("ZZIDS1-" + n, "ZZIDSA" + n, unit, "ACADEMIC", true);       // all three done, and a sign-in
        UUID s2 = staff("ZZIDS2-" + n, "ZZIDSB" + n, unit, "NON_ACADEMIC", false);  // on the register only: an e-mail not verified
        UUID s3 = staff("ZZIDS3-" + n, "ZZIDSC" + n, unit, "ACADEMIC", true);       // a blood group not confirmed, no e-mail
        it.db(() -> {
            jdbc.sql("UPDATE iam.person SET email = :e WHERE id = :p").param("e", "zzids1." + n + "@example.com").param("p", s1).update();
            jdbc.sql("UPDATE iam.person SET email = :e WHERE id = :p").param("e", "zzids2." + n + "@example.com").param("p", s2).update();
            jdbc.sql("INSERT INTO iam.person_email_verified (person_id, email, verified_at) VALUES (:p, :e, now())")
                    .param("p", s1).param("e", "zzids1." + n + "@example.com").update();
            jdbc.sql("""
                    INSERT INTO iam.credential (person_id, username, password_hash, must_change, set_by)
                    VALUES (:p, :u, '$2a$12$abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0', false, :p)
                    """).param("p", s1).param("u", "zzids1-" + n).update();
            // a blood group written to the card detail without the desk's or the holder's confirmation
            jdbc.sql("INSERT INTO credentials.staff_card_detail (person_id, blood_group, set_at, set_by, set_office) VALUES (:p, 'A-', now(), :p, 'ict')")
                    .param("p", s3).update();
            return 0;
        });
        assertThat(it.call(security, HttpMethod.PUT, "/api/v1/credentials/identity-cards/staff/" + s1 + "/blood-group", Map.of("bloodGroup", "AB+"))
                .getStatusCode().value()).isEqualTo(200);
        String s1Token = TestTokens.token(s1, List.of("lecturer"));
        ResponseEntity<Map> up = it.call(s1Token, HttpMethod.POST, "/api/v1/staff/identity/photo", Map.of("contentType", "image/jpeg", "dataBase64", photo()));
        assertThat(up.getStatusCode().value()).as(String.valueOf(up.getBody())).isEqualTo(200);
        ResponseEntity<Map> accepted = it.call(s1Token, HttpMethod.POST, "/api/v1/staff/identity/photo/" + up.getBody().get("id") + "/accept", null);
        assertThat(accepted.getStatusCode().value()).as(String.valueOf(accepted.getBody())).isEqualTo(200);

        Map<String, Long> c = counts(hrm, "/staff", "unit=" + unit);
        assertThat(c).containsEntry("total", 3L).containsEntry("with_photo", 1L).containsEntry("without_photo", 2L).containsEntry("photo_enhanced", 1L)
                .containsEntry("email_verified", 1L).containsEntry("email_unverified", 1L).containsEntry("email_missing", 1L)
                .containsEntry("blood_confirmed", 1L).containsEntry("blood_missing", 1L).containsEntry("blood_unconfirmed", 1L)
                .containsEntry("complete", 1L).containsEntry("no_sign_in", 2L);
        assertThat(counts(hrm, "/staff", "unit=" + unit + "&category=non_academic")).containsEntry("total", 1L).containsEntry("email_unverified", 1L);
        assertThat(counts(hrm, "/staff", "unit=" + unit + "&category=ACADEMIC")).containsEntry("total", 2L).containsEntry("complete", 1L);
        assertThat(it.get(hrm, BASE + "/staff?unit=" + unit + "&category=CASUAL").getBody()).containsEntry("code", "IDENTITY_FILTER");

        String q = "unit=" + unit;
        List<Map<String, Object>> all = list(hrm, "/staff/list", q);
        assertThat(all).extracting(r -> r.get("person_id")).containsExactly(s1.toString(), s2.toString(), s3.toString());
        assertThat(all.get(0)).containsEntry("complete", true).containsEntry("photo_enhanced", true).containsEntry("email_verified", true)
                .containsEntry("blood_confirmed", true).containsEntry("can_sign_in", true).containsEntry("in_office", true).containsEntry("category", "ACADEMIC")
                .containsEntry("unit", "ZZ Unit " + unit);
        assertThat(all.get(1)).containsEntry("complete", false).containsEntry("in_office", false).containsEntry("can_sign_in", false)
                .containsEntry("email", "zzids2." + n + "@example.com").containsEntry("email_verified", false);
        assertThat(all.get(2)).containsEntry("blood_group", "A-").containsEntry("blood_confirmed", false).doesNotContainKey("email");
        for (String missing : List.of("PHOTO", "EMAIL", "BLOOD", "any")) {
            assertThat(list(hrm, "/staff/list", q + "&missing=" + missing)).as(missing).extracting(r -> r.get("person_id")).containsExactly(s2.toString(), s3.toString());
        }
        assertThat(list(hrm, "/staff/list", q + "&q=ZZIDS2-" + n)).extracting(r -> r.get("person_id")).containsExactly(s2.toString());
        assertThat(it.get(hrm, BASE + "/staff/list?" + q + "&missing=MATRIC").getBody()).containsEntry("code", "IDENTITY_FILTER");
        Map<String, Object> filters = it.get(hrm, BASE + "/staff?" + q).getBody();
        assertThat((List<Map<String, Object>>) filters.get("units")).anySatisfy(u -> assertThat(u).containsEntry("code", unit));
        assertThat((List<String>) filters.get("categories")).containsExactly("ACADEMIC", "NON_ACADEMIC");

        // the readers: HR, the Registry's two, the card desk, ICT and the administrators; not Records or Student Affairs, not a lecturer
        for (String office : List.of("registrar", "dregistrar", "security", "ict", "admin", "super")) {
            assertThat(it.get(ItSupport.token(office), BASE + "/staff?" + q).getStatusCode().value()).as(office).isEqualTo(200);
        }
        for (String office : List.of("records", "dsa", "lecturer")) {
            assertThat(it.get(ItSupport.token(office), BASE + "/staff/list?" + q).getStatusCode().value()).as(office).isEqualTo(403);
        }
    }
}
