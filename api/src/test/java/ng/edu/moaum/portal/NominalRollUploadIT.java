package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.ThreadLocalRandom;

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
 * V750: the November 2026 nominal roll through both staff uploads. The teaching staff's roll (FIRST NAME, MIDDLE NAME,
 * LAST-SURNAME, PNO, … DEPARTMENT, FAC-COLL-DIR): a dry run says row by row what the upload would do and writes nothing — not the
 * new lecturers, not a change to one on record; uploaded, each new lecturer is a person, a sign-in and the lecturer office, the
 * dates read day first and a note kept where a date is expected ('NA' is no value); the same file again is all UNCHANGED; a roll
 * that differs updates the names and the record and lists each change, while an e-mail that differs from the one on record is kept
 * and reported, never written, and one missing is filled; a department not on the portal leaves the one on record and is reported,
 * and a new lecturer in such a department is not loaded (SKIPPED, the message saying to add the department or correct the cell).
 * The non-teaching rolls: a senior P number and a junior JP number of the same digits are two people, the junior never merged into
 * the P record; the old sheet still loads. The roll's "on the portal but not on this roll" by kind and series. Who may: Human
 * Resources not the teaching staff's upload nor its absent list, a lecturer neither upload. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class NominalRollUploadIT {

    private static final String I = "/api/v1/iam";

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    @Test
    void theRollCreatesUpdatesAndLeavesAloneWhatItShouldAndADryRunWritesNothing() {
        ItSupport it = new ItSupport(port, jdbc, transactions);
        String ict = it.officer("ict", "institution", "University");
        String hrm = ItSupport.token("hrm");
        String lecturer = ItSupport.token("lecturer");
        // a department whose name no other live department shares (case, spacing and & aside), so the row naming it finds it alone
        String[] dept = jdbc.sql("""
                SELECT d.code || '|' || d.name || '|' || f.code FROM ref.programme p JOIN ref.department d ON d.code = p.dept_code JOIN ref.faculty f ON f.code = p.faculty_code
                 WHERE p.category = 'UNDER GRADUATE' AND NOT p.archived AND coalesce(f.college_code, '') <> 'CHS' AND d.ended_on IS NULL
                   AND NOT EXISTS (SELECT 1 FROM ref.department o WHERE o.code <> d.code AND o.ended_on IS NULL
                                    AND regexp_replace(replace(upper(o.name), '&', 'AND'), '[^A-Z0-9]', '', 'g')
                                      = regexp_replace(replace(upper(d.name), '&', 'AND'), '[^A-Z0-9]', '', 'g'))
                 ORDER BY p.code LIMIT 1
                """).query(String.class).single().split("\\|");
        // a second live department, named by its code on the roll, for a lecturer the roll moves
        String[] dept2 = jdbc.sql("""
                SELECT d.code || '|' || d.name FROM ref.department d
                 WHERE d.ended_on IS NULL AND d.code <> :c
                   AND NOT EXISTS (SELECT 1 FROM ref.department o WHERE o.code <> d.code AND o.ended_on IS NULL
                                    AND regexp_replace(replace(upper(o.name), '&', 'AND'), '[^A-Z0-9]', '', 'g') = upper(d.code))
                 ORDER BY d.code LIMIT 1
                """).param("c", dept[0]).query(String.class).single().split("\\|");
        String[] unit = jdbc.sql("""
                SELECT u.code || '|' || u.name FROM ref.unit u, LATERAL (SELECT * FROM ref.resolve_unit(u.name) LIMIT 1) r
                 WHERE u.ended_on IS NULL AND r.unit_code = u.code ORDER BY u.code LIMIT 1
                """).query(String.class).single().split("\\|");
        // six numbers free in both series (P and JP), so the junior's JP number shares its digits with no one but this test's senior
        String[] n = new String[6];
        for (int i = 0; i < n.length; i++) {
            String d;
            do {
                d = String.valueOf(ThreadLocalRandom.current().nextInt(9_100_000, 9_999_999));
            } while (jdbc.sql("SELECT count(*) FROM iam.person WHERE upper(staff_number) IN ('P' || :d, 'JP' || :d)").param("d", d).query(Integer.class).single() > 0
                    || java.util.Arrays.asList(n).contains(d));
            n[i] = d;
        }
        String a = "P" + n[0], b = "P" + n[1], old = "P" + n[2], senior = "P" + n[3], junior = "JP" + n[3], other = "P" + n[4], nowhere = "P" + n[5];
        List<String> made = List.of(a, b, old, senior, junior, other, nowhere);
        try {
            // ── the teaching staff's roll ──
            Map<String, Object> rowA = row("sheet_row", 5, "sno", "", "first_name", "Adaeze", "middle_name", "Roll", "last_name", "Zzroll" + n[0],
                    "pno", n[0], "sex", "F", "date_of_birth", "03/04/1980", "email", "zzroll" + n[0] + "a@example.com", "phone", "0803 123 " + n[0].substring(3),
                    "lga", "Makurdi", "state", "Benue", "date_first_appointment", "01/10/2015", "date_of_confirmation", "NA",
                    "date_of_last_promotion", "(Transfer of Service) Another University", "present_rank", "LECTURER II",
                    "department", dept[0], "faculty", dept[2]);
            Map<String, Object> rowB = row("sheet_row", 6, "first_name", "Bem", "middle_name", "", "last_name", "Zzroll" + n[1], "pno", n[1], "sex", "M",
                    "date_of_birth", "12/09/1975", "email", "", "phone", "NA", "lga", "Gboko", "state", "Benue", "date_first_appointment", "02/01/2010",
                    "date_of_confirmation", "02/01/2013", "date_of_last_promotion", "01/10/2020", "present_rank", "SENIOR LECTURER",
                    "department", dept[1], "faculty", dept[2]);
            long[] before = counts();

            // a dry run: every row's outcome, nothing written
            ResponseEntity<Map> dry = it.call(ict, HttpMethod.POST, I + "/lecturers/import", Map.of("dryRun", true, "rows", List.of(rowA, rowB)));
            assertThat(dry.getStatusCode().value()).as(String.valueOf(dry.getBody())).isEqualTo(200);
            assertThat(dry.getBody()).containsEntry("created", 2).containsEntry("updated", 0).containsEntry("errors", 0).containsEntry("skipped", 0);
            assertThat(result(dry, a)).containsEntry("row", 5).containsEntry("action", "CREATED");
            assertThat(result(dry, b)).containsEntry("row", 6).containsEntry("action", "CREATED");
            assertThat(counts()).as("a dry run writes nothing").containsExactly(before);
            assertThat(person(a)).isNull();

            // uploaded: the person, the sign-in, the lecturer office; dates day first, a note where a date is expected, 'NA' no value
            ResponseEntity<Map> up = it.call(ict, HttpMethod.POST, I + "/lecturers/import", Map.of("rows", List.of(rowA, rowB)));
            assertThat(up.getStatusCode().value()).as(String.valueOf(up.getBody())).isEqualTo(200);
            assertThat(up.getBody()).containsEntry("created", 2).containsEntry("credentialed", 2).containsEntry("granted", 2).containsEntry("errors", 0);
            UUID pa = person(a), pb = person(b);
            assertThat(pa).isNotNull();
            assertThat(result(up, a)).containsEntry("personId", pa.toString());
            Map<String, Object> recA = jdbc.sql("""
                    SELECT p.surname, p.given_names, p.email, p.phone, sr.date_of_birth::text AS dob, sr.date_first_appointment::text AS appointed,
                           sr.date_of_confirmation, sr.confirmation_note, sr.date_of_last_promotion, sr.promotion_note, sr.lga, sr.state_of_origin,
                           sr.home_department, sr.home_faculty, sr.category, sr.cadre, sr.roll_updated_at IS NOT NULL AS stamped,
                           (SELECT count(*) FROM iam.credential c WHERE c.person_id = p.id) AS signins,
                           (SELECT count(*) FROM iam.office_assignment o WHERE o.person_id = p.id AND o.office_code = 'lecturer' AND o.scope_id = sr.home_department) AS offices
                      FROM iam.person p JOIN hrm.staff_record sr ON sr.person_id = p.id WHERE p.id = :p
                    """).param("p", pa).query().singleRow();
            assertThat(recA).containsEntry("surname", "Zzroll" + n[0]).containsEntry("given_names", "Adaeze Roll")
                    .containsEntry("dob", "1980-04-03").containsEntry("appointed", "2015-10-01")
                    .containsEntry("promotion_note", "(Transfer of Service) Another University")
                    .containsEntry("lga", "Makurdi").containsEntry("state_of_origin", "Benue").containsEntry("home_department", dept[0])
                    .containsEntry("home_faculty", dept[2]).containsEntry("category", "ACADEMIC").containsEntry("stamped", true)
                    .containsEntry("signins", 1L).containsEntry("offices", 1L);
            assertThat(recA.get("date_of_confirmation")).isNull();
            assertThat(recA.get("confirmation_note")).isNull();
            assertThat(recA.get("date_of_last_promotion")).isNull();
            assertThat(recA.get("cadre")).isNull();
            assertThat(recA.get("email")).isEqualTo("zzroll" + n[0] + "a@example.com");
            assertThat(jdbc.sql("SELECT home_department FROM hrm.staff_record WHERE person_id = :p").param("p", pb).query(String.class).single())
                    .as("a department named as the portal names it").isEqualTo(dept[0]);

            // the same file again: nothing differs, nothing written
            ResponseEntity<Map> again = it.call(ict, HttpMethod.POST, I + "/lecturers/import", Map.of("rows", List.of(rowA, rowB)));
            assertThat(again.getStatusCode().value()).as(String.valueOf(again.getBody())).isEqualTo(200);
            assertThat(again.getBody()).containsEntry("created", 0).containsEntry("updated", 0).containsEntry("unchanged", 2);
            assertThat(result(again, a)).containsEntry("action", "UNCHANGED");
            assertThat((List) result(again, a).get("changes")).isEmpty();

            // a roll that differs: names and record follow it; an e-mail that differs is kept, one missing filled; 'NA' erases nothing;
            // a department not on the portal leaves the one on record, and is reported
            Map<String, Object> rowA2 = new LinkedHashMap<>(rowA);
            rowA2.putAll(row("last_name", "Zzrollnew" + n[0], "email", "zzroll" + n[0] + "other@example.com", "lga", "NA", "present_rank", "LECTURER I",
                    "date_of_last_promotion", "01/10/2024"));
            Map<String, Object> rowB2 = new LinkedHashMap<>(rowB);
            rowB2.putAll(row("email", "zzroll" + n[1] + "b@example.com", "phone", "+234 806 " + n[1].substring(0, 3) + " " + n[1].substring(3),
                    "department", "Zzroll Nowhere " + n[1]));
            Map<String, Object> fingerprint = fingerprint(pa, pb);
            ResponseEntity<Map> check = it.call(ict, HttpMethod.POST, I + "/lecturers/import", Map.of("dryRun", true, "rows", List.of(rowA2, rowB2)));
            assertThat(check.getStatusCode().value()).as(String.valueOf(check.getBody())).isEqualTo(200);
            assertThat(check.getBody()).containsEntry("updated", 2);
            assertThat(fingerprint(pa, pb)).as("a dry run changes no one on record").isEqualTo(fingerprint);

            ResponseEntity<Map> upd = it.call(ict, HttpMethod.POST, I + "/lecturers/import", Map.of("rows", List.of(rowA2, rowB2)));
            assertThat(upd.getStatusCode().value()).as(String.valueOf(upd.getBody())).isEqualTo(200);
            assertThat(upd.getBody()).containsEntry("created", 0).containsEntry("updated", 2).containsEntry("credentialed", 0).containsEntry("granted", 0);
            Map<String, Object> ra = result(upd, a);
            assertThat(ra).containsEntry("action", "UPDATED");
            assertThat(changes(ra)).containsEntry("surname", List.of("Zzroll" + n[0], "Zzrollnew" + n[0]))
                    .containsEntry("present_rank", List.of("LECTURER II", "LECTURER I"))
                    .containsKeys("date_of_last_promotion", "promotion_note")
                    .doesNotContainKeys("email", "lga");
            assertThat((List<Map<String, Object>>) ra.get("kept")).anySatisfy(k -> assertThat(k).containsEntry("field", "email")
                    .containsEntry("onRecord", "zzroll" + n[0] + "a@example.com").containsEntry("reason", "DIFFERS"));
            Map<String, Object> rb = result(upd, b);
            assertThat(rb).containsEntry("action", "UPDATED");
            assertThat(changes(rb)).containsKeys("email", "phone").doesNotContainKey("home_department");
            assertThat((List<Map<String, Object>>) rb.get("unresolved")).anySatisfy(u -> assertThat(u).containsEntry("field", "department")
                    .containsEntry("onRoll", "Zzroll Nowhere " + n[1]));
            assertThat(upd.getBody()).containsEntry("no_department", 1);
            assertThat(jdbc.sql("SELECT home_department FROM hrm.staff_record WHERE person_id = :p").param("p", pb).query(String.class).single())
                    .as("a department not on the portal leaves the one on record").isEqualTo(dept[0]);
            Map<String, Object> nowA = jdbc.sql("""
                    SELECT p.surname, p.email, sr.lga, sr.present_rank, sr.date_of_last_promotion::text AS promoted, sr.promotion_note
                      FROM iam.person p JOIN hrm.staff_record sr ON sr.person_id = p.id WHERE p.id = :p
                    """).param("p", pa).query().singleRow();
            assertThat(nowA).containsEntry("surname", "Zzrollnew" + n[0]).containsEntry("email", "zzroll" + n[0] + "a@example.com")
                    .containsEntry("lga", "Makurdi").containsEntry("present_rank", "LECTURER I").containsEntry("promoted", "2024-10-01");
            assertThat(nowA.get("promotion_note")).isNull();
            assertThat(jdbc.sql("SELECT email || '|' || phone FROM iam.person WHERE id = :p").param("p", pb).query(String.class).single())
                    .isEqualTo("zzroll" + n[1] + "b@example.com|0806" + n[1]);
            assertThat(jdbc.sql("SELECT count(*) FROM iam.credential WHERE person_id IN (:a, :b)").param("a", pa).param("b", pb).query(Integer.class).single())
                    .as("an update never touches a sign-in").isEqualTo(2);

            // a blank MIDDLE NAME keeps the given names on record (they begin with the roll's first name); the result names the record
            Map<String, Object> rowA3 = new LinkedHashMap<>(rowA2);
            rowA3.put("middle_name", "");
            ResponseEntity<Map> blankMiddle = it.call(ict, HttpMethod.POST, I + "/lecturers/import", Map.of("rows", List.of(rowA3)));
            assertThat(blankMiddle.getStatusCode().value()).as(String.valueOf(blankMiddle.getBody())).isEqualTo(200);
            assertThat(result(blankMiddle, a)).containsEntry("action", "UNCHANGED").containsEntry("name", "Zzrollnew" + n[0] + ", Adaeze Roll");
            assertThat((List) result(blankMiddle, a).get("changes")).isEmpty();
            // a blank (NA) FIRST NAME keeps them too, and is reported
            Map<String, Object> rowA3f = new LinkedHashMap<>(rowA2);
            rowA3f.put("first_name", "NA");
            ResponseEntity<Map> blankFirst = it.call(ict, HttpMethod.POST, I + "/lecturers/import", Map.of("rows", List.of(rowA3f)));
            assertThat(blankFirst.getStatusCode().value()).as(String.valueOf(blankFirst.getBody())).isEqualTo(200);
            assertThat(result(blankFirst, a)).containsEntry("action", "UNCHANGED");
            assertThat((List<Map<String, Object>>) result(blankFirst, a).get("unresolved")).anySatisfy(u -> assertThat(u)
                    .containsEntry("field", "first_name").containsEntry("onRoll", "NA").containsEntry("reason", "BLANK"));
            assertThat(jdbc.sql("SELECT given_names FROM iam.person WHERE id = :p").param("p", pa).query(String.class).single())
                    .as("a blank name cell never erases a name").isEqualTo("Adaeze Roll");
            // a different first name beside a blank MIDDLE NAME replaces only the first of the given names: the rest stand
            Map<String, Object> rowA3d = new LinkedHashMap<>(rowA2);
            rowA3d.put("first_name", "Adanna");
            rowA3d.put("middle_name", "NA");
            ResponseEntity<Map> otherFirst = it.call(ict, HttpMethod.POST, I + "/lecturers/import", Map.of("dryRun", true, "rows", List.of(rowA3d)));
            assertThat(otherFirst.getStatusCode().value()).as(String.valueOf(otherFirst.getBody())).isEqualTo(200);
            assertThat(result(otherFirst, a)).containsEntry("action", "UPDATED");
            assertThat(changes(result(otherFirst, a))).containsEntry("given_names", List.of("Adaeze Roll", "Adanna Roll"));
            assertThat(jdbc.sql("SELECT given_names FROM iam.person WHERE id = :p").param("p", pa).query(String.class).single())
                    .as("a dry run writes nothing").isEqualTo("Adaeze Roll");

            // a department the roll changes takes the lecturer office with it, as the Edit form moves it: said by the dry run (nothing
            // written), then the old office ended today and one open in the new department; the same file again moves nothing
            Map<String, Object> rowA4 = new LinkedHashMap<>(rowA2);
            rowA4.put("department", dept2[0]);
            long[] beforeMove = counts();
            List<String> officesBefore = lecturerOffices(pa);
            assertThat(officesBefore).containsExactly(dept[0] + ":open");
            ResponseEntity<Map> moveDry = it.call(ict, HttpMethod.POST, I + "/lecturers/import", Map.of("dryRun", true, "rows", List.of(rowA4)));
            assertThat(moveDry.getStatusCode().value()).as(String.valueOf(moveDry.getBody())).isEqualTo(200);
            assertThat(changes(result(moveDry, a))).containsEntry("home_department", List.of(dept[1], dept2[1]))
                    .containsEntry("lecturer_office", List.of(dept[1], dept2[1]));
            assertThat(counts()).as("a dry run moves no office").containsExactly(beforeMove);
            assertThat(lecturerOffices(pa)).isEqualTo(officesBefore);
            ResponseEntity<Map> move = it.call(ict, HttpMethod.POST, I + "/lecturers/import", Map.of("rows", List.of(rowA4)));
            assertThat(move.getStatusCode().value()).as(String.valueOf(move.getBody())).isEqualTo(200);
            assertThat(result(move, a)).containsEntry("action", "UPDATED");
            assertThat(changes(result(move, a))).containsEntry("lecturer_office", List.of(dept[1], dept2[1]));
            assertThat(lecturerOffices(pa)).containsExactlyInAnyOrder(dept[0] + ":ended today", dept2[0] + ":open");
            assertThat(jdbc.sql("SELECT home_department FROM hrm.staff_record WHERE person_id = :p").param("p", pa).query(String.class).single())
                    .isEqualTo(dept2[0]);
            ResponseEntity<Map> moveAgain = it.call(ict, HttpMethod.POST, I + "/lecturers/import", Map.of("rows", List.of(rowA4)));
            assertThat(result(moveAgain, a)).containsEntry("action", "UNCHANGED");
            assertThat(lecturerOffices(pa)).hasSize(2);

            // the teaching staff's upload refuses a junior's number; a new lecturer in a department not on the portal is not loaded;
            // the old sheet still loads
            ResponseEntity<Map> mixed = it.call(ict, HttpMethod.POST, I + "/lecturers/import", Map.of("rows", List.of(
                    row("first_name", "Junior", "last_name", "Wrongupload", "jp_no", n[4], "department", dept[0]),
                    row("first_name", "Nowhere", "last_name", "Zzroll" + n[5], "pno", n[5], "sex", "F", "department", "Zzroll Nowhere " + n[5], "faculty", dept[2]),
                    row("pno", n[2], "full_names", "Dr Old Sheet Zzroll" + n[2], "sex", "M", "department", dept[0], "present_rank", "ASSISTANT LECTURER"))));
            assertThat(mixed.getStatusCode().value()).as(String.valueOf(mixed.getBody())).isEqualTo(200);
            assertThat(mixed.getBody()).containsEntry("created", 1).containsEntry("errors", 1).containsEntry("skipped", 1).containsEntry("no_department", 1);
            assertThat(String.valueOf(result(mixed, "JP" + n[4]).get("error"))).contains("non-academic staff desk");
            assertThat(result(mixed, nowhere)).containsEntry("action", "SKIPPED");
            assertThat(String.valueOf(result(mixed, nowhere).get("error"))).contains("Zzroll Nowhere " + n[5]).contains("add the department");
            assertThat(result(mixed, old)).containsEntry("action", "CREATED");
            assertThat(person("JP" + n[4])).isNull();
            assertThat(person(nowhere)).isNull();

            // ── the non-teaching rolls: a senior and a junior of the same digits are two people ──
            Map<String, Object> sen = row("sheet_row", 3, "first_name", "Senior", "middle_name", "Roll", "last_name", "Zzroll" + n[3], "pno", n[3], "sex", "M",
                    "date_of_birth", "31/12/1970", "present_rank", "CHIEF CLERICAL OFFICER", "posting", unit[1]);
            Map<String, Object> oth = row("sheet_row", 4, "first_name", "Other", "last_name", "Zzroll" + n[4], "pno", n[4], "sex", "F", "posting", unit[1]);
            ResponseEntity<Map> seniors = it.call(hrm, HttpMethod.POST, I + "/staff/import", Map.of("rows", List.of(sen, oth)));
            assertThat(seniors.getStatusCode().value()).as(String.valueOf(seniors.getBody())).isEqualTo(200);
            assertThat(seniors.getBody()).containsEntry("created", 2).containsEntry("errors", 0);
            assertThat(result(seniors, senior)).containsEntry("cadre", "SENIOR").containsEntry("row", 3);

            Map<String, Object> jun = row("sheet_row", 9, "first_name", "Junior", "last_name", "Zzrolljun" + n[3], "jp_no", n[3], "sex", "F",
                    "date_of_birth", "01/02/1990", "present_rank", "MESSENGER", "posting", unit[1]);
            long[] beforeJunior = counts();
            ResponseEntity<Map> jdry = it.call(hrm, HttpMethod.POST, I + "/staff/import", Map.of("dryRun", true, "rows", List.of(jun)));
            assertThat(jdry.getStatusCode().value()).as(String.valueOf(jdry.getBody())).isEqualTo(200);
            assertThat(result(jdry, junior)).containsEntry("action", "CREATED").containsEntry("cadre", "JUNIOR");
            assertThat(counts()).containsExactly(beforeJunior);
            ResponseEntity<Map> juniors = it.call(hrm, HttpMethod.POST, I + "/staff/import", Map.of("rows", List.of(jun)));
            assertThat(juniors.getStatusCode().value()).as(String.valueOf(juniors.getBody())).isEqualTo(200);
            assertThat(juniors.getBody()).containsEntry("created", 1).containsEntry("updated", 0);
            UUID ps = person(senior), pj = person(junior);
            assertThat(pj).isNotNull().isNotEqualTo(ps);
            assertThat(jdbc.sql("SELECT p.surname || '|' || sr.cadre || '|' || sr.home_unit FROM iam.person p JOIN hrm.staff_record sr ON sr.person_id = p.id WHERE p.id = :p")
                    .param("p", pj).query(String.class).single()).isEqualTo("Zzrolljun" + n[3] + "|JUNIOR|" + unit[0]);
            assertThat(jdbc.sql("SELECT p.surname || '|' || sr.cadre FROM iam.person p JOIN hrm.staff_record sr ON sr.person_id = p.id WHERE p.id = :p")
                    .param("p", ps).query(String.class).single()).as("the senior of the same digits is untouched").isEqualTo("Zzroll" + n[3] + "|SENIOR");
            assertThat(jdbc.sql("SELECT count(*) FROM iam.credential WHERE person_id IN (:s, :j)").param("s", ps).param("j", pj).query(Integer.class).single())
                    .as("the non-teaching upload makes no sign-in").isZero();
            ResponseEntity<Map> jagain = it.call(hrm, HttpMethod.POST, I + "/staff/import", Map.of("rows", List.of(jun)));
            assertThat(jagain.getBody()).containsEntry("unchanged", 1).containsEntry("created", 0).containsEntry("updated", 0);
            ResponseEntity<Map> oldSheet = it.call(hrm, HttpMethod.POST, I + "/staff/import", Map.of("rows", List.of(
                    row("pno", n[4], "full_names", "Mrs Renamed By Guess", "department", unit[1], "present_rank", "SENIOR CLERK", "contiss", "6"))));
            assertThat(oldSheet.getBody()).containsEntry("updated", 1);
            assertThat(changes(result(oldSheet, other))).containsKey("present_rank").doesNotContainKeys("surname", "given_names");
            assertThat(result(oldSheet, other)).as("the old sheet's row is named as the record names them, not by the guess")
                    .containsEntry("name", "Zzroll" + n[4] + ", Other");

            // each roll keeps to its own staff: a lecturer's number on the non-teaching upload, a senior's on the teaching-staff upload,
            // is an ERROR that writes nothing
            UUID po = person(other);
            Map<String, Object> kinds = fingerprint(pa, po);
            ResponseEntity<Map> wrongStaff = it.call(hrm, HttpMethod.POST, I + "/staff/import", Map.of("rows", List.of(
                    row("first_name", "Adaeze", "last_name", "Moved", "pno", n[0], "sex", "F", "present_rank", "CLERICAL OFFICER", "posting", unit[1]))));
            assertThat(wrongStaff.getStatusCode().value()).as(String.valueOf(wrongStaff.getBody())).isEqualTo(200);
            assertThat(wrongStaff.getBody()).containsEntry("errors", 1).containsEntry("updated", 0);
            assertThat(result(wrongStaff, a)).containsEntry("action", "ERROR")
                    .containsEntry("error", a + " is on record as teaching staff: they are loaded on the teaching staff desk");
            ResponseEntity<Map> wrongLect = it.call(ict, HttpMethod.POST, I + "/lecturers/import", Map.of("rows", List.of(
                    row("first_name", "Other", "last_name", "Zzroll" + n[4], "pno", n[4], "present_rank", "LECTURER II", "department", dept[0]))));
            assertThat(wrongLect.getStatusCode().value()).as(String.valueOf(wrongLect.getBody())).isEqualTo(200);
            assertThat(wrongLect.getBody()).containsEntry("errors", 1).containsEntry("updated", 0).containsEntry("granted", 0);
            assertThat(result(wrongLect, other)).containsEntry("action", "ERROR")
                    .containsEntry("error", other + " is on record as non-teaching staff: they are loaded on the non-academic staff desk");
            assertThat(fingerprint(pa, po)).as("the wrong roll writes nothing").isEqualTo(kinds);
            assertThat(lecturerOffices(po)).isEmpty();

            // ── on the portal but not on this roll: by kind, within the series the roll holds ──
            ResponseEntity<List> absentSenior = it.callList(hrm, HttpMethod.POST, I + "/staff/roll-absent", Map.of("kind", "NON_ACADEMIC", "numbers", List.of(senior)));
            assertThat(absentSenior.getStatusCode().value()).as(String.valueOf(absentSenior.getBody())).isEqualTo(200);
            List<String> sAbsent = numbers(absentSenior);
            assertThat(sAbsent).contains(other).doesNotContain(senior, junior, a, b);
            ResponseEntity<List> absentJunior = it.callList(hrm, HttpMethod.POST, I + "/staff/roll-absent", Map.of("kind", "non_academic", "numbers", List.of(junior)));
            assertThat(numbers(absentJunior)).doesNotContain(junior, senior, other);
            ResponseEntity<List> absentAcademic = it.callList(ict, HttpMethod.POST, I + "/staff/roll-absent", Map.of("kind", "ACADEMIC", "numbers", List.of(n[0])));
            assertThat(absentAcademic.getStatusCode().value()).as(String.valueOf(absentAcademic.getBody())).isEqualTo(200);
            assertThat(numbers(absentAcademic)).contains(b, old).doesNotContain(a, senior, other, junior);
            assertThat(((List<Map<String, Object>>) absentAcademic.getBody()).stream().filter(x -> b.equals(x.get("staff_number"))).findFirst().orElseThrow())
                    .containsEntry("rank", "SENIOR LECTURER").containsEntry("posting", dept[1]);
            assertThat(it.call(ict, HttpMethod.POST, I + "/staff/roll-absent", Map.of("kind", "EVERYONE", "numbers", List.of())).getStatusCode().value()).isEqualTo(400);

            // ── who may ──
            assertThat(it.call(hrm, HttpMethod.POST, I + "/lecturers/import", Map.of("dryRun", true, "rows", List.of(rowA))).getStatusCode().value()).isEqualTo(403);
            assertThat(it.callList(hrm, HttpMethod.POST, I + "/staff/roll-absent", Map.of("kind", "ACADEMIC", "numbers", List.of(a))).getStatusCode().value()).isEqualTo(403);
            assertThat(it.call(lecturer, HttpMethod.POST, I + "/staff/import", Map.of("dryRun", true, "rows", List.of(jun))).getStatusCode().value()).isEqualTo(403);
            assertThat(it.call(lecturer, HttpMethod.POST, I + "/lecturers/import", Map.of("dryRun", true, "rows", List.of(rowA))).getStatusCode().value()).isEqualTo(403);
            assertThat(it.callList(lecturer, HttpMethod.POST, I + "/staff/roll-absent", Map.of("kind", "NON_ACADEMIC", "numbers", List.of(senior))).getStatusCode().value()).isEqualTo(403);
        } finally {
            // tidy: the people this run made are deleted (tied to nothing), so a later run's absent lists hold nothing of this one
            List<String> ids = new ArrayList<>();
            for (String s : made) {
                UUID p = person(s);
                if (p != null) ids.add(p.toString());
            }
            if (!ids.isEmpty()) {
                it.call(ict, HttpMethod.POST, I + "/staff/remove", Map.of("ids", ids, "mode", "AUTO", "reasonCode", "OTHER", "reason", "Integration test tidy"));
            }
        }
    }

    /** a roll's row: its cells, in order */
    private static Map<String, Object> row(Object... kv) {
        Map<String, Object> out = new LinkedHashMap<>();
        for (int i = 0; i < kv.length; i += 2) out.put((String) kv[i], kv[i + 1]);
        return out;
    }

    /** the people, sign-ins, offices and staff records on the portal: what an upload writes */
    private long[] counts() {
        return new long[] {
            jdbc.sql("SELECT count(*) FROM iam.person").query(Long.class).single(),
            jdbc.sql("SELECT count(*) FROM iam.credential").query(Long.class).single(),
            jdbc.sql("SELECT count(*) FROM iam.office_assignment").query(Long.class).single(),
            jdbc.sql("SELECT count(*) FROM hrm.staff_record").query(Long.class).single(),
        };
    }

    /** two people and their staff records as they stand, to the column */
    private Map<String, Object> fingerprint(UUID x, UUID y) {
        return jdbc.sql("""
                SELECT string_agg(to_jsonb(p)::text || to_jsonb(sr)::text, '|' ORDER BY p.id) AS rows
                  FROM iam.person p JOIN hrm.staff_record sr ON sr.person_id = p.id WHERE p.id IN (:x, :y)
                """).param("x", x).param("y", y).query().singleRow();
    }

    /** a person's lecturer offices as "department:open", "department:ended today" (or the date it ended) */
    private List<String> lecturerOffices(UUID p) {
        return jdbc.sql("""
                SELECT a.scope_id || ':' || CASE WHEN a.valid_to IS NULL THEN 'open' WHEN a.valid_to = current_date THEN 'ended today' ELSE a.valid_to::text END
                  FROM iam.office_assignment a WHERE a.person_id = :p AND a.office_code = 'lecturer' ORDER BY a.valid_from, a.scope_id
                """).param("p", p).query(String.class).list();
    }

    private UUID person(String staffNumber) {
        return jdbc.sql("SELECT id FROM iam.person WHERE upper(staff_number) = upper(:s)").param("s", staffNumber).query(UUID.class).optional().orElse(null);
    }

    /** the upload's result for the staff number named */
    private static Map<String, Object> result(ResponseEntity<Map> upload, String staffNumber) {
        return ((List<Map<String, Object>>) upload.getBody().get("results")).stream()
                .filter(r -> staffNumber.equals(r.get("staffNumber"))).findFirst()
                .orElseThrow(() -> new AssertionError("no result for " + staffNumber + " in " + upload.getBody()));
    }

    /** a result's changes as field → [from, to] */
    private static Map<String, List<Object>> changes(Map<String, Object> result) {
        Map<String, List<Object>> out = new LinkedHashMap<>();
        for (Map<String, Object> c : (List<Map<String, Object>>) result.get("changes")) {
            List<Object> pair = new ArrayList<>();
            pair.add(c.get("from"));
            pair.add(c.get("to"));
            out.put(String.valueOf(c.get("field")), pair);
        }
        return out;
    }

    private static List<String> numbers(ResponseEntity<List> absent) {
        return ((List<Map<String, Object>>) absent.getBody()).stream().map(x -> String.valueOf(x.get("staff_number"))).toList();
    }
}
