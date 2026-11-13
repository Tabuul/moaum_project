package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.awt.image.BufferedImage;
import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.util.Base64;
import java.util.List;
import java.util.Map;
import java.util.Random;
import java.util.UUID;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

import javax.imageio.ImageIO;

import ng.edu.moaum.portal.shared.PhotoEnhancer;

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
 * V749, the University's brief of 12 November 2026 ("UPDATE STAFF IDENTITY INFORMATION"), end to end for a member of staff in service:
 * asked on the first screen (iam/me) until done; the blood group confirmed (refused unticked, or not one of the eight; refused for a
 * person not in the University's service); the e-mail verified by a code sent to the new address — a malformed address refused,
 * another person's verified address refused with the try kept (one of the hour's three, and past them the limit answers first), an
 * address only typed on someone else's record no bar and left as it stands, a wrong code counted, the old address kept until the
 * right one; the contact banner refuses a new address with nothing saved and keeps the address when it is blank, the profile takes
 * none (the one sent is not read, the record's written into it), and the office's correction never places an address another
 * person holds verified; the photograph uploaded (a damaged file and a non-image refused, nothing kept), assessed and enhanced (a
 * dark photograph comes back a little brighter and flagged, the original kept beside it, both served to the holder alone,
 * no-store), retried, set aside, one too small refused at acceptance, another person's never reached; the old raw upload retired; accepted, it is the card photograph — the PNG it replaced kept on the upload — and the
 * card's photograph is served as a JPEG (as an old PNG photograph now is too). All three done, the person is no longer asked; the HR
 * record and the employment are as they were before each of the three. Twenty uploads and retries an hour, refused before any work.
 * Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class StaffIdentityIT {

    private static final Pattern CODE = Pattern.compile("\\b(\\d{6})\\b");
    private static final String BASE = "/api/v1/staff/identity";

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

    /** a member of staff in service: a staff number and an office today */
    private UUID staff(String number, String surname) {
        UUID p = it.person(number, surname);
        it.db(() -> jdbc.sql("""
                INSERT INTO iam.office_assignment (id, person_id, office_code, scope_kind, scope_id, instrument, granted_by, valid_from)
                SELECT gen_random_uuid(), :p, 'lecturer', 'department', 'MTC', 'staff identity test', :p, current_date
                 WHERE NOT EXISTS (SELECT 1 FROM iam.office_assignment a WHERE a.person_id = :p AND a.office_code = 'lecturer')
                """).param("p", p).update());
        return p;
    }

    /** a made-up photograph, textured so it has detail to read */
    private static BufferedImage picture(int w, int h, int base, long seed) {
        Random random = new Random(seed);
        BufferedImage img = new BufferedImage(w, h, BufferedImage.TYPE_INT_RGB);
        for (int y = 0; y < h; y++) {
            for (int x = 0; x < w; x++) {
                int v = Math.min(255, base + ((x / 7 + y / 11) % 2 == 0 ? 22 : 0) + random.nextInt(14));
                img.setRGB(x, y, (Math.min(255, v + 6) << 16) | (v << 8) | Math.max(0, v - 4));
            }
        }
        return img;
    }

    private static byte[] write(BufferedImage img, String format) throws Exception {
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        ImageIO.write(img, format, out);
        return out.toByteArray();
    }

    private static double meanLuma(byte[] bytes) throws Exception {
        BufferedImage img = ImageIO.read(new ByteArrayInputStream(bytes));
        double s = 0;
        for (int y = 0; y < img.getHeight(); y++) {
            for (int x = 0; x < img.getWidth(); x++) {
                int p = img.getRGB(x, y);
                s += 0.299 * ((p >> 16) & 0xFF) + 0.587 * ((p >> 8) & 0xFF) + 0.114 * (p & 0xFF);
            }
        }
        return s / ((double) img.getWidth() * img.getHeight());
    }

    private ResponseEntity<Map> upload(String token, byte[] bytes, String type) {
        return it.call(token, HttpMethod.POST, BASE + "/photo", Map.of("contentType", type, "dataBase64", Base64.getEncoder().encodeToString(bytes)));
    }

    private long submissions(UUID person) {
        return jdbc.sql("SELECT count(*) FROM hrm.staff_photo_submission WHERE person_id = :p").param("p", person).query(Long.class).single();
    }

    /** the person's staff record as HR keeps it — the number, the HR register row, the employment, the offices — to show that the
     *  identity information touches none of it (the briefs: "existing staff records and employment information remain intact") */
    private String hrRecord(UUID person) {
        return jdbc.sql("""
                SELECT jsonb_build_object(
                    'person', (SELECT jsonb_build_object('staff_number', pe.staff_number, 'surname', pe.surname, 'given_names', pe.given_names,
                                                         'ended_on', pe.ended_on) FROM iam.person pe WHERE pe.id = :p),
                    'record', (SELECT to_jsonb(r) FROM hrm.staff_record r WHERE r.person_id = :p),
                    'employment', (SELECT jsonb_agg(to_jsonb(e) ORDER BY e.id) FROM hrm.employment e WHERE e.person_id = :p),
                    'offices', (SELECT jsonb_agg(to_jsonb(a) ORDER BY a.id) FROM iam.office_assignment a WHERE a.person_id = :p))::text
                """).param("p", person).query(String.class).single();
    }

    private String email(UUID person) {
        return jdbc.sql("SELECT email FROM iam.person WHERE id = :p").param("p", person).query(String.class).single();
    }

    private String phone(UUID person) {
        return jdbc.sql("SELECT coalesce(phone, '') FROM iam.person WHERE id = :p").param("p", person).query(String.class).single();
    }

    @Test
    void aMemberOfStaffBringsThePhotographTheEmailAndTheBloodGroupUpToDate() throws Exception {
        int n = it.freeDraw(100000, 999999, k -> List.of("ZZSID-" + k, "ZZSIDQ-" + k, "ZZSIDR-" + k, "ZZSID" + k, "ZZSIDQ" + k, "ZZSIDR" + k));
        UUID p = staff("ZZSID-" + n, "ZZSID" + n);
        UUID q = staff("ZZSIDQ-" + n, "ZZSIDQ" + n);
        UUID r = it.person("ZZSIDR-" + n, "ZZSIDR" + n);   // a staff number, but no office today and not on the HR register
        String oldEmail = "zzsid" + n + ".old@example.com", taken = "zzsid" + n + ".taken@example.com", fresh = "zzsid" + n + ".new@example.com";
        // q holds `taken`, verified; r has `fresh` typed on its record (another case), never verified
        it.db(() -> jdbc.sql("UPDATE iam.person SET email = CASE id WHEN :p THEN :o WHEN :q THEN :t WHEN :r THEN :f END WHERE id IN (:p, :q, :r)")
                .param("p", p).param("q", q).param("r", r).param("o", oldEmail).param("t", taken).param("f", fresh.toUpperCase()).update());
        it.db(() -> jdbc.sql("INSERT INTO iam.person_email_verified (person_id, email, verified_at) VALUES (:q, :t, now())").param("q", q).param("t", taken).update());
        // p's HR record and employment, as HR keeps them: none of the three flows below may touch them
        it.db(() -> jdbc.sql("""
                INSERT INTO hrm.staff_record (person_id, pno, present_rank, category, date_first_appointment) VALUES (:p, :no, 'LECTURER I', 'ACADEMIC', DATE '2010-01-04')
                """).param("p", p).param("no", "ZZSID-" + n).update());
        it.db(() -> jdbc.sql("""
                INSERT INTO hrm.employment (person_id, staff_no, grade, step, category, appointment_date)
                SELECT :p, :no, g.grade, g.step, 'ACADEMIC', DATE '2010-01-04' FROM hrm.grade g ORDER BY g.grade, g.step LIMIT 1
                """).param("p", p).param("no", "ZZSID-" + n).update());
        String hr = hrRecord(p);
        String mine = TestTokens.token(p, List.of("lecturer"));
        String other = TestTokens.token(q, List.of("lecturer"));
        String notInService = TestTokens.token(r, List.of("lecturer"));
        String security = TestTokens.token(it.person("ZZSID-CSO", "ZZSIDCSO"), List.of("security"));
        String office = TestTokens.token(it.person("ZZSID-HRM", "ZZSIDHRM"), List.of("hrm"));

        // where the person stands, and asked on the first screen until it is done; a student and an applicant are not asked here
        Map<String, Object> start = it.get(mine, BASE).getBody();
        assertThat(start).containsEntry("staff", true).containsEntry("complete", false);
        assertThat((Map<String, Object>) start.get("email")).containsEntry("value", oldEmail).containsEntry("verified", false);
        assertThat((Map<String, Object>) start.get("photo")).containsEntry("present", false).containsEntry("enhanced", false);
        Map<String, Object> prompt = (Map<String, Object>) it.get(mine, "/api/v1/iam/me").getBody().get("identityPrompt");
        assertThat(prompt).containsEntry("complete", false).containsKeys("photo", "email", "bloodGroup");
        assertThat(it.get(TestTokens.token(UUID.randomUUID(), List.of("applicant")), BASE).getStatusCode().value()).isEqualTo(403);   // a student: StudentBloodGroupIT
        assertThat(it.get(notInService, "/api/v1/iam/me").getBody()).doesNotContainKey("identityPrompt");

        // ── the blood group: ticked, one of the eight; a member of staff in service only
        assertThat(it.call(mine, HttpMethod.PUT, BASE + "/blood-group", Map.of("bloodGroup", "B+", "confirmed", false)).getBody())
                .containsEntry("code", "IDENTITY_BLOOD_UNCONFIRMED");
        assertThat(it.call(mine, HttpMethod.PUT, BASE + "/blood-group", Map.of("bloodGroup", "B positive", "confirmed", true)).getBody())
                .containsEntry("code", "IDENTITY_BLOOD_GROUP");
        ResponseEntity<Map> refusedR = it.call(notInService, HttpMethod.PUT, BASE + "/blood-group", Map.of("bloodGroup", "B+", "confirmed", true));
        assertThat(refusedR.getStatusCode().value()).isEqualTo(403);
        assertThat(refusedR.getBody()).containsEntry("code", "IDENTITY_NOT_STAFF");
        ResponseEntity<Map> blood = it.call(mine, HttpMethod.PUT, BASE + "/blood-group", Map.of("bloodGroup", " b+ ", "confirmed", true));
        assertThat(blood.getStatusCode().value()).as(String.valueOf(blood.getBody())).isEqualTo(200);
        assertThat(blood.getBody()).containsEntry("bloodGroup", "B+").containsEntry("kind", "STAFF");
        assertThat((Map<String, Object>) ((Map<String, Object>) blood.getBody().get("identity")).get("bloodGroup"))
                .containsEntry("value", "B+").containsEntry("confirmed", true).containsEntry("source", "SELF");
        assertThat(jdbc.sql("SELECT credentials.staff_blood_group(:p)").param("p", p).query(String.class).single()).isEqualTo("B+");
        assertThat(jdbc.sql("SELECT holder_number || ':' || new_value || ':' || source || ':' || office FROM credentials.blood_group_event WHERE kind = 'STAFF' AND holder_id = :p")
                .param("p", p).query(String.class).single()).isEqualTo("ZZSID-" + n + ":B+:SELF:lecturer");
        assertThat(hrRecord(p)).as("the HR record after the blood group").isEqualTo(hr);

        // ── the e-mail: a malformed address refused; another person's, verified, refused once the try is kept (one of the hour's
        //    three); one only typed on someone else's record is no bar; a code to the new one; the old one kept until it is right
        assertThat(it.call(mine, HttpMethod.POST, BASE + "/email/code", Map.of("email", "not an address")).getBody()).containsEntry("code", "IDENTITY_EMAIL_FORMAT");
        ResponseEntity<Map> takenRefused = it.call(mine, HttpMethod.POST, BASE + "/email/code", Map.of("email", "  " + taken.toUpperCase() + " "));
        assertThat(takenRefused.getStatusCode().value()).isEqualTo(422);
        assertThat(takenRefused.getBody()).containsEntry("code", "IDENTITY_EMAIL_TAKEN");
        assertThat(jdbc.sql("SELECT count(*) FROM iam.email_verification WHERE person_id = :p AND outcome = 'TAKEN' AND email = :t").param("p", p).param("t", taken)
                .query(Long.class).single()).as("the refused try is kept, and counts").isEqualTo(1L);
        ResponseEntity<Map> sent = it.call(mine, HttpMethod.POST, BASE + "/email/code", Map.of("email", fresh.toUpperCase()));
        assertThat(sent.getStatusCode().value()).as(String.valueOf(sent.getBody())).isEqualTo(200);
        assertThat(sent.getBody()).containsEntry("sentTo", fresh).containsEntry("minutes", 15);
        assertThat((Map<String, Object>) ((Map<String, Object>) sent.getBody().get("identity")).get("email"))
                .containsEntry("value", oldEmail).containsEntry("pending", fresh).containsEntry("verified", false);
        // the code's e-mail is filed against the code (never the person who asked), so the portal never lists it back
        Map<String, Object> notice = jdbc.sql("""
                SELECT body, template_key, priority, about_kind, about_id, channel FROM platform.notice WHERE lower(recipient) = :r ORDER BY created_at DESC LIMIT 1
                """).param("r", fresh).query().singleRow();
        UUID openCode = jdbc.sql("SELECT id FROM iam.email_verification WHERE person_id = :p AND outcome IS NULL").param("p", p).query(UUID.class).single();
        assertThat(notice).containsEntry("template_key", "STAFF_EMAIL_CODE").containsEntry("priority", "HIGH").containsEntry("about_kind", "email_verification")
                .containsEntry("about_id", openCode).containsEntry("channel", "EMAIL");
        Matcher m = CODE.matcher(String.valueOf(notice.get("body")));
        assertThat(m.find()).as(String.valueOf(notice.get("body"))).isTrue();
        String code = m.group(1);
        assertThat(it.call(mine, HttpMethod.POST, BASE + "/email/verify", Map.of("code", "000000".equals(code) ? "111111" : "000000")).getBody())
                .containsEntry("outcome", "WRONG");
        assertThat(jdbc.sql("SELECT email FROM iam.person WHERE id = :p").param("p", p).query(String.class).single()).isEqualTo(oldEmail);
        // another person's code is not this person's: nothing open for them
        assertThat(it.call(other, HttpMethod.POST, BASE + "/email/verify", Map.of("code", code)).getBody()).containsEntry("outcome", "EXPIRED");
        ResponseEntity<Map> verified = it.call(mine, HttpMethod.POST, BASE + "/email/verify", Map.of("code", code));
        assertThat(verified.getBody()).as(String.valueOf(verified.getBody())).containsEntry("outcome", "VERIFIED");
        assertThat((Map<String, Object>) ((Map<String, Object>) verified.getBody().get("identity")).get("email"))
                .containsEntry("value", fresh).containsEntry("verified", true);
        assertThat(jdbc.sql("SELECT email FROM iam.person WHERE id = :p").param("p", p).query(String.class).single()).isEqualTo(fresh);
        assertThat(jdbc.sql("SELECT previous_email FROM iam.email_verification WHERE person_id = :p AND outcome = 'VERIFIED'").param("p", p)
                .query(String.class).single()).isEqualTo(oldEmail);
        // the copy only typed on r's record is left as it stands
        assertThat(email(r)).isEqualTo(fresh.toUpperCase());
        assertThat(hrRecord(p)).as("the HR record after the e-mail verified").isEqualTo(hr);
        // and now no one else may take it — and past the hour's three tries the limit answers first, never whose the address is
        assertThat(it.call(other, HttpMethod.POST, BASE + "/email/code", Map.of("email", fresh)).getBody()).containsEntry("code", "IDENTITY_EMAIL_TAKEN");
        assertThat(it.call(other, HttpMethod.POST, BASE + "/email/code", Map.of("email", "zzsidq" + n + ".a@example.com")).getStatusCode().value()).isEqualTo(200);
        assertThat(it.call(other, HttpMethod.POST, BASE + "/email/code", Map.of("email", "zzsidq" + n + ".b@example.com")).getStatusCode().value()).isEqualTo(200);
        assertThat(it.call(other, HttpMethod.POST, BASE + "/email/code", Map.of("email", fresh)).getBody()).containsEntry("code", "IDENTITY_EMAIL_CODE_LIMIT");

        // ── the person's own doors: a new address refused at the banner with nothing saved, the one on record or blank keeping it; the
        //    profile takes no address at all — the one sent is not read, and the record's is written into it
        String elsewhere = "zzsid" + n + ".elsewhere@example.com";
        ResponseEntity<Map> bannerNew = it.call(mine, HttpMethod.PUT, "/api/v1/staff/contact", Map.of("email", elsewhere, "phone", "0803 111 2222"));
        assertThat(bannerNew.getStatusCode().value()).isEqualTo(422);
        assertThat(bannerNew.getBody()).containsEntry("code", "STAFF_EMAIL_VERIFY");
        assertThat(email(p)).isEqualTo(fresh);
        assertThat(phone(p)).isEmpty();
        assertThat(it.call(mine, HttpMethod.PUT, "/api/v1/staff/contact", Map.of("email", " " + fresh.toUpperCase(), "phone", "0803 111 2222")).getBody())
                .containsEntry("email", fresh).containsEntry("phone", "0803 111 2222");
        Map<String, Object> blankEmail = new java.util.HashMap<>();
        blankEmail.put("email", null);
        blankEmail.put("phone", "0803 333 4444");
        assertThat(it.call(mine, HttpMethod.PUT, "/api/v1/staff/contact", blankEmail).getBody()).containsEntry("email", fresh).containsEntry("phone", "0803 333 4444");
        assertThat(it.get(mine, "/api/v1/staff/profile").getBody()).containsEntry("email", fresh);
        ResponseEntity<Map> profileNew = it.call(mine, HttpMethod.PUT, "/api/v1/staff/profile", Map.of("email", elsewhere, "department", "Mathematics"));
        assertThat(profileNew.getStatusCode().value()).as(String.valueOf(profileNew.getBody())).isEqualTo(200);
        assertThat(profileNew.getBody()).containsEntry("email", fresh).containsEntry("department", "Mathematics");
        assertThat(email(p)).isEqualTo(fresh);
        assertThat(jdbc.sql("SELECT email FROM hrm.staff_profile WHERE person_id = :p").param("p", p).query(String.class).single()).isEqualTo(fresh);
        ResponseEntity<Map> profileSame = it.call(mine, HttpMethod.PUT, "/api/v1/staff/profile", Map.of("email", fresh, "department", "Mathematics"));
        assertThat(profileSame.getStatusCode().value()).as(String.valueOf(profileSame.getBody())).isEqualTo(200);
        assertThat(profileSame.getBody()).containsEntry("email", fresh).containsEntry("department", "Mathematics");
        assertThat((Map<String, Object>) it.get(mine, BASE).getBody().get("email")).containsEntry("value", fresh).containsEntry("verified", true);
        // the office's correction: never to an address another person holds verified; any other is set
        ResponseEntity<Map> officeTaken = it.call(office, HttpMethod.PUT, "/api/v1/iam/persons/" + r + "/contact", Map.of("email", " " + taken.toUpperCase()));
        assertThat(officeTaken.getStatusCode().value()).isEqualTo(422);
        assertThat(officeTaken.getBody()).containsEntry("code", "IDENTITY_EMAIL_TAKEN");
        assertThat(email(r)).isEqualTo(fresh.toUpperCase());
        ResponseEntity<Map> officeSet = it.call(office, HttpMethod.PUT, "/api/v1/iam/persons/" + r + "/contact", Map.of("email", "zzsidr" + n + "@example.com", "phone", "0803 555 6666"));
        assertThat(officeSet.getStatusCode().value()).as(String.valueOf(officeSet.getBody())).isEqualTo(200);
        assertThat(email(r)).isEqualTo("zzsidr" + n + "@example.com");

        // ── the photograph: a damaged file and a non-image refused, and nothing kept of either
        long before = submissions(p);
        byte[] damaged = new byte[600];
        new Random(n).nextBytes(damaged);
        damaged[0] = (byte) 0xFF;
        damaged[1] = (byte) 0xD8;
        damaged[2] = (byte) 0xFF;
        damaged[3] = (byte) 0xDB;
        ResponseEntity<Map> corrupt = upload(mine, damaged, "image/jpeg");
        assertThat(corrupt.getStatusCode().value()).isEqualTo(422);
        assertThat(corrupt.getBody()).containsEntry("code", "PHOTO_CORRUPT");
        assertThat(upload(mine, "%PDF-1.4 not a photograph".getBytes(), "image/jpeg").getBody()).containsEntry("code", "PHOTO_FORMAT");
        assertThat(submissions(p)).isEqualTo(before);

        // one too small for the card: enhanced, but to be replaced — never accepted
        ResponseEntity<Map> tiny = upload(mine, write(picture(100, 125, 90, 1), "jpg"), "image/jpeg");
        assertThat(tiny.getStatusCode().value()).as(String.valueOf(tiny.getBody())).isEqualTo(200);
        assertThat(tiny.getBody()).containsEntry("state", "PROCESSED").containsEntry("quality", "REPLACE");
        String tinyId = String.valueOf(tiny.getBody().get("id"));
        assertThat(it.call(mine, HttpMethod.POST, BASE + "/photo/" + tinyId + "/accept", null).getBody()).containsEntry("code", "PHOTO_NEEDS_REPLACING");

        // a dark photograph: assessed (the face never claimed), enhanced a little brighter (flagged TOO_DARK), the original kept beside it
        byte[] dark = write(picture(720, 900, 22, 2), "jpg");
        ResponseEntity<Map> up = upload(mine, dark, "image/jpeg");
        assertThat(up.getStatusCode().value()).as(String.valueOf(up.getBody())).isEqualTo(200);
        assertThat(up.getBody()).containsEntry("state", "PROCESSED").containsEntry("width", 600).containsEntry("height", 750).containsEntry("originalType", "image/jpeg");
        assertThat(up.getBody().get("quality")).isIn("GOOD", "FAIR");
        Map<String, Object> assessment = (Map<String, Object>) up.getBody().get("assessment");
        assertThat(assessment).containsEntry("face", PhotoEnhancer.FACE).containsEntry("width", 720).containsEntry("height", 900);
        assertThat((List<String>) assessment.get("flags")).contains("TOO_DARK");
        assertThat(String.valueOf(up.getBody().get("enhancement"))).contains("Global corrections only");
        String id = String.valueOf(up.getBody().get("id"));
        ResponseEntity<byte[]> enhanced = it.getBytes(mine, BASE + "/photo/" + id + "/enhanced");
        assertThat(enhanced.getStatusCode().value()).isEqualTo(200);
        assertThat(enhanced.getHeaders().getContentType().toString()).isEqualTo("image/jpeg");
        assertThat(enhanced.getHeaders().getCacheControl()).contains("no-store").contains("private");
        assertThat(enhanced.getHeaders().getFirst("X-Content-Type-Options")).isEqualTo("nosniff");
        // lifted a little and no more (PhotoEnhancer.UNDER_GAIN_MAX, 1.1 times: a dark face on a dark wall can read as under-exposed),
        // TOO_DARK asking for a retake in better light
        assertThat(meanLuma(enhanced.getBody())).isGreaterThan(meanLuma(dark) + 1).isLessThan(meanLuma(dark) * 1.2);
        ResponseEntity<byte[]> original = it.getBytes(mine, BASE + "/photo/" + id + "/original");
        assertThat(original.getStatusCode().value()).isEqualTo(200);
        assertThat(original.getBody()).isEqualTo(dark);
        assertThat(it.get(mine, BASE + "/photo/" + id).getBody()).containsEntry("state", "PROCESSED").containsEntry("hasEnhanced", true);

        // another person's upload is never reached: not seen, not accepted, not set aside
        assertThat(it.getBytes(other, BASE + "/photo/" + id + "/enhanced").getStatusCode().value()).isEqualTo(404);
        assertThat(it.getBytes(other, BASE + "/photo/" + id + "/original").getStatusCode().value()).isEqualTo(404);
        assertThat(it.get(other, BASE + "/photo/" + id).getStatusCode().value()).isEqualTo(404);
        ResponseEntity<Map> stolen = it.call(other, HttpMethod.POST, BASE + "/photo/" + id + "/accept", null);
        assertThat(stolen.getStatusCode().value()).isEqualTo(403);
        assertThat(stolen.getBody()).containsEntry("code", "PHOTO_NOT_YOURS");
        assertThat(it.call(other, HttpMethod.POST, BASE + "/photo/" + id + "/discard", null).getBody()).containsEntry("code", "PHOTO_NOT_YOURS");
        assertThat(it.call(other, HttpMethod.POST, BASE + "/photo/" + id + "/retry", null).getBody()).containsEntry("code", "PHOTO_NOT_YOURS");
        assertThat(it.call(mine, HttpMethod.POST, BASE + "/photo/" + UUID.randomUUID() + "/accept", null).getBody()).containsEntry("code", "PHOTO_NOT_YOURS");

        // another upload: the enhancement done again, then set aside — and a photograph set aside is not accepted
        ResponseEntity<Map> third = upload(mine, write(picture(720, 900, 40, 3), "jpg"), "image/jpeg");
        String thirdId = String.valueOf(third.getBody().get("id"));
        ResponseEntity<Map> retried = it.call(mine, HttpMethod.POST, BASE + "/photo/" + thirdId + "/retry", null);
        assertThat(retried.getStatusCode().value()).as(String.valueOf(retried.getBody())).isEqualTo(200);
        assertThat(retried.getBody()).containsEntry("state", "PROCESSED");
        assertThat(it.call(mine, HttpMethod.POST, BASE + "/photo/" + thirdId + "/discard", null).getBody()).containsEntry("state", "DISCARDED");
        assertThat(it.call(mine, HttpMethod.POST, BASE + "/photo/" + thirdId + "/accept", null).getBody()).containsEntry("code", "PHOTO_STATE");
        assertThat(jdbc.sql("SELECT string_agg(action, ',' ORDER BY at) FROM hrm.staff_photo_event WHERE submission_id = :s").param("s", UUID.fromString(thirdId))
                .query(String.class).single()).isEqualTo("UPLOADED,ENHANCED,RETRIED,DISCARDED");

        // the old raw upload is retired: it says where to go and changes nothing
        byte[] png = write(picture(200, 250, 120, 4), "png");
        ResponseEntity<Map> raw = it.call(mine, HttpMethod.PUT, "/api/v1/staff/profile/photo", Map.of("contentType", "image/png", "dataBase64", Base64.getEncoder().encodeToString(png)));
        assertThat(raw.getStatusCode().value()).isEqualTo(422);
        assertThat(raw.getBody()).containsEntry("code", "STAFF_PHOTO_USE_IDENTITY");
        assertThat(jdbc.sql("SELECT count(*) FROM hrm.staff_photo WHERE person_id = :p").param("p", p).query(Long.class).single()).isZero();
        // a photograph set before V749 (a PNG, as the old upload kept it), and a card in force: the card's photograph is served as a JPEG
        it.db(() -> jdbc.sql("INSERT INTO hrm.staff_photo (person_id, content_type, bytes, content, updated_at) VALUES (:p, 'image/png', :n, :c, now())")
                .param("p", p).param("n", (long) png.length).param("c", png).update());
        assertThat(it.get(mine, "/api/v1/staff/profile/photo").getBody()).containsEntry("contentType", "image/png").containsKey("dataBase64");
        ResponseEntity<Map> card = it.call(security, HttpMethod.POST, "/api/v1/credentials/identity-cards/staff/issue", Map.of("staffNumber", "ZZSID-" + n, "reason", "staff identity test"));
        assertThat(card.getStatusCode().value()).as(String.valueOf(card.getBody())).isEqualTo(200);
        ResponseEntity<byte[]> pngOnCard = it.getBytes(security, "/api/v1/credentials/identity-cards/staff/" + p + "/photo");
        assertThat(pngOnCard.getStatusCode().value()).isEqualTo(200);
        assertThat(pngOnCard.getHeaders().getContentType().toString()).isEqualTo("image/jpeg");
        assertThat(PhotoEnhancer.sniff(pngOnCard.getBody())).isEqualTo("image/jpeg");

        // accepted: the card photograph from now, the PNG it replaced kept on the upload, the undecided one set aside
        ResponseEntity<Map> accepted = it.call(mine, HttpMethod.POST, BASE + "/photo/" + id + "/accept", null);
        assertThat(accepted.getStatusCode().value()).as(String.valueOf(accepted.getBody())).isEqualTo(200);
        assertThat(accepted.getBody()).containsEntry("state", "ACCEPTED").containsEntry("contentType", "image/jpeg").containsEntry("previousKept", true)
                .containsEntry("superseded", 1);
        assertThat(jdbc.sql("SELECT state FROM hrm.staff_photo_submission WHERE id = :s").param("s", UUID.fromString(tinyId)).query(String.class).single())
                .isEqualTo("SUPERSEDED");
        assertThat(jdbc.sql("SELECT content_type || ':' || (submission_id = :s) FROM hrm.staff_photo WHERE person_id = :p").param("s", UUID.fromString(id)).param("p", p)
                .query(String.class).single()).isEqualTo("image/jpeg:true");
        assertThat(jdbc.sql("SELECT previous_photo_type FROM hrm.staff_photo_submission WHERE id = :s").param("s", UUID.fromString(id)).query(String.class).single())
                .isEqualTo("image/png");
        assertThat(jdbc.sql("SELECT string_agg(action, ',' ORDER BY at) FROM hrm.staff_photo_event WHERE submission_id = :s").param("s", UUID.fromString(id))
                .query(String.class).single()).isEqualTo("UPLOADED,ENHANCED,ACCEPTED");
        ResponseEntity<byte[]> current = it.getBytes(mine, BASE + "/photo/current");
        assertThat(current.getStatusCode().value()).isEqualTo(200);
        assertThat(current.getBody()).isEqualTo(enhanced.getBody());
        ResponseEntity<byte[]> onCard = it.getBytes(security, "/api/v1/credentials/identity-cards/staff/" + p + "/photo");
        assertThat(onCard.getHeaders().getContentType().toString()).isEqualTo("image/jpeg");
        assertThat(onCard.getBody()).isEqualTo(enhanced.getBody());
        assertThat(it.call(mine, HttpMethod.POST, BASE + "/photo/" + id + "/accept", null).getBody()).containsEntry("code", "PHOTO_STATE");
        assertThat(hrRecord(p)).as("the HR record after the photograph accepted").isEqualTo(hr);

        // all three done: complete, and no longer asked
        Map<String, Object> done = it.get(mine, BASE).getBody();
        assertThat(done).containsEntry("complete", true);
        assertThat((Map<String, Object>) done.get("photo")).containsEntry("present", true).containsEntry("enhanced", true);
        assertThat(it.get(mine, "/api/v1/iam/me").getBody()).doesNotContainKey("identityPrompt");

        // ── the hour's twenty, uploads, retries and refused files together: made up to twenty, an upload and a retry are refused before
        //    any work — a damaged file is answered by the limit, not read — and nothing is kept
        ResponseEntity<Map> waiting = upload(mine, write(picture(720, 900, 60, 5), "jpg"), "image/jpeg");
        assertThat(waiting.getBody()).containsEntry("state", "PROCESSED");
        assertThat(jdbc.sql("SELECT string_agg(detail->>'code', ',' ORDER BY at) FROM hrm.staff_photo_event WHERE person_id = :p AND action = 'REFUSED' AND submission_id IS NULL")
                .param("p", p).query(String.class).single()).as("the damaged file and the non-image, counted").isEqualTo("PHOTO_CORRUPT,PHOTO_FORMAT");
        long counted = jdbc.sql("SELECT count(*) FROM hrm.staff_photo_event WHERE person_id = :p AND action IN ('UPLOADED', 'RETRIED', 'REFUSED') AND at > now() - interval '1 hour'")
                .param("p", p).query(Long.class).single();
        assertThat(counted).as("four uploads, a retry and two refused files").isEqualTo(7L);
        it.db(() -> jdbc.sql("INSERT INTO hrm.staff_photo_event (person_id, action, by, office) SELECT :p, 'UPLOADED', :p, 'lecturer' FROM generate_series(1, :k)")
                .param("p", p).param("k", (int) (20 - counted)).update());
        long kept = submissions(p);
        ResponseEntity<Map> overLimit = upload(mine, damaged, "image/jpeg");
        assertThat(overLimit.getStatusCode().value()).isEqualTo(422);
        assertThat(overLimit.getBody()).containsEntry("code", "PHOTO_UPLOAD_LIMIT");
        assertThat(it.call(mine, HttpMethod.POST, BASE + "/photo/" + waiting.getBody().get("id") + "/retry", null).getBody()).containsEntry("code", "PHOTO_UPLOAD_LIMIT");
        assertThat(submissions(p)).isEqualTo(kept);
        assertThat(jdbc.sql("SELECT count(*) FROM hrm.staff_photo_event WHERE submission_id = :s").param("s", UUID.fromString(String.valueOf(waiting.getBody().get("id"))))
                .query(Long.class).single()).as("the refused retry left no event").isEqualTo(2L);
    }

    /** a file the portal reads in full and then refuses is work all the same: twenty damaged files in the hour, each refused and counted
     *  (REFUSED, no upload kept, nothing in the file store), and the twenty-first is answered by the limit before it is even decoded */
    @Test
    void refusedFilesCountAmongTheHoursTwenty() {
        int n = it.freeDraw(100000, 999999, k -> List.of("ZZSIDF-" + k, "ZZSIDF" + k));
        UUID p = staff("ZZSIDF-" + n, "ZZSIDF" + n);
        String mine = TestTokens.token(p, List.of("lecturer"));
        byte[] damaged = new byte[600];
        new Random(n).nextBytes(damaged);
        damaged[0] = (byte) 0xFF;
        damaged[1] = (byte) 0xD8;
        damaged[2] = (byte) 0xFF;
        damaged[3] = (byte) 0xDB;
        long objects = jdbc.sql("SELECT count(*) FROM platform.file_object WHERE owner_table = 'hrm.staff_photo_submission' AND owner_id = :p")
                .param("p", p.toString()).query(Long.class).single();
        for (int i = 1; i <= 20; i++) {
            ResponseEntity<Map> refused = upload(mine, damaged, "image/jpeg");
            assertThat(refused.getStatusCode().value()).as("upload " + i).isEqualTo(422);
            assertThat(refused.getBody()).as("upload " + i).containsEntry("code", "PHOTO_CORRUPT");
        }
        assertThat(jdbc.sql("SELECT count(*) FROM hrm.staff_photo_event WHERE person_id = :p AND action = 'REFUSED' AND submission_id IS NULL AND detail->>'code' = 'PHOTO_CORRUPT'")
                .param("p", p).query(Long.class).single()).isEqualTo(20L);
        // the twenty-first: not base64 at all — read, it would be refused PHOTO_DATA; the limit answers first
        ResponseEntity<Map> limited = it.call(mine, HttpMethod.POST, BASE + "/photo", Map.of("contentType", "image/jpeg", "dataBase64", "%%% not base64 %%%"));
        assertThat(limited.getStatusCode().value()).isEqualTo(422);
        assertThat(limited.getBody()).containsEntry("code", "PHOTO_UPLOAD_LIMIT");
        // and a good photograph too, before any work: no event, no upload, nothing stored
        assertThat(upload(mine, damaged, "image/jpeg").getBody()).containsEntry("code", "PHOTO_UPLOAD_LIMIT");
        assertThat(jdbc.sql("SELECT count(*) FROM hrm.staff_photo_event WHERE person_id = :p").param("p", p).query(Long.class).single()).isEqualTo(20L);
        assertThat(submissions(p)).isZero();
        assertThat(jdbc.sql("SELECT count(*) FROM platform.file_object WHERE owner_table = 'hrm.staff_photo_submission' AND owner_id = :p")
                .param("p", p.toString()).query(Long.class).single()).isEqualTo(objects);
    }

    /** the latest code's e-mail for the person, read from the outbox as its mailbox would read it */
    private String codeFor(UUID person) {
        String body = jdbc.sql("""
                SELECT n.body FROM platform.notice n JOIN iam.email_verification x ON x.id = n.about_id
                 WHERE n.about_kind = 'email_verification' AND x.person_id = :p AND x.outcome IS NULL ORDER BY n.created_at DESC LIMIT 1
                """).param("p", person).query(String.class).single();
        Matcher m = CODE.matcher(body);
        assertThat(m.find()).as(body).isTrue();
        return m.group(1);
    }

    /** the words of a member of staff's notices as GET /api/v1/me/notices lists them — subject, body and template of each (not the ids
     *  or times, whose digits could pass for a code) */
    private String listed(String token) {
        return words(it.getList(token, "/api/v1/me/notices?limit=500").getBody());
    }

    private static String words(List<Map<String, Object>> notices) {
        StringBuilder out = new StringBuilder();
        for (Map<String, Object> x : notices) {
            out.append(x.get("subject")).append(" | ").append(x.get("body")).append(" | ").append(x.get("template_key")).append(" | ")
               .append(x.get("about_kind")).append(" ## ");
        }
        return out.toString();
    }

    /** V749: the code proves the mailbox, and nothing read on the portal stands in for it. GET /api/v1/me/notices never lists a code —
     *  to the member of staff who asked for it (for their own address, or for an address on someone else's record), nor to anyone
     *  else — nor a password-reset link, the person's own or another's; an address an office typed on a second record shows that record
     *  none of the holder's mail, while what is the person's own (filed against them, the notices of their work) is still listed. A code
     *  replaced before its message went is cancelled, and once a code's message has gone its words leave the outbox */
    @Test
    void theCodeAndAResetLinkNeverComeBackOnThePortal() {
        int n = it.freeDraw(100000, 999999, k -> List.of("ZZSIDA-" + k, "ZZSIDB-" + k, "ZZSIDA" + k, "ZZSIDB" + k));
        UUID a = staff("ZZSIDA-" + n, "ZZSIDA" + n);
        UUID b = staff("ZZSIDB-" + n, "ZZSIDB" + n);
        String aMail = "zzsida" + n + "@example.com", aNew = "zzsida" + n + ".new@example.com", bMail = "zzsidb" + n + "@example.com";
        // B's address on B's record, not verified (as nearly every member of staff's is at launch); B signs in by the staff number
        it.db(() -> jdbc.sql("UPDATE iam.person SET email = CASE id WHEN :a THEN :am WHEN :b THEN :bm END WHERE id IN (:a, :b)")
                .param("a", a).param("b", b).param("am", aMail).param("bm", bMail).update());
        it.db(() -> jdbc.sql("""
                INSERT INTO iam.credential (person_id, username, password_hash, must_change, set_by) VALUES (:b, lower(:u), crypt(gen_random_uuid()::text, gen_salt('bf', 12)), true, :b)
                """).param("b", b).param("u", "ZZSIDB-" + n).update());
        String tokenA = TestTokens.token(a, List.of("lecturer"));
        String tokenB = TestTokens.token(b, List.of("lecturer"));

        // the plain case: A asks for a code for A's own new address — it goes to that mailbox, and A's list never shows it
        assertThat(it.call(tokenA, HttpMethod.POST, BASE + "/email/code", Map.of("email", aNew)).getStatusCode().value()).isEqualTo(200);
        String first = codeFor(a);
        UUID firstNotice = jdbc.sql("SELECT n.id FROM platform.notice n JOIN iam.email_verification x ON x.id = n.about_id WHERE n.about_kind = 'email_verification' AND x.person_id = :a")
                .param("a", a).query(UUID.class).single();
        String listA = listed(tokenA);
        assertThat(listA).doesNotContain(first).doesNotContain("STAFF_EMAIL_CODE").doesNotContain("email_verification").doesNotContain(aNew);

        // the case of an address on another's record: A asks for a code for B's address (B has not verified it, so it is not refused) —
        // neither A nor B is shown it; the first code, replaced while its message waited, is cancelled and its words gone
        assertThat(it.call(tokenA, HttpMethod.POST, BASE + "/email/code", Map.of("email", bMail)).getStatusCode().value()).isEqualTo(200);
        String second = codeFor(a);
        assertThat(jdbc.sql("SELECT state || ':' || (position(:c IN body) > 0) FROM platform.notice WHERE id = :n").param("n", firstNotice).param("c", first)
                .query(String.class).single()).isEqualTo("CANCELLED:false");
        assertThat(listed(tokenA)).doesNotContain(second).doesNotContain("STAFF_EMAIL_CODE");
        assertThat(listed(tokenB)).doesNotContain(second).doesNotContain("STAFF_EMAIL_CODE").doesNotContain("email_verification");

        // B asks for a password reset: the link goes to B's address, filed against B as a member of staff
        assertThat(it.anon(HttpMethod.POST, "/api/v1/auth/forgot", Map.of("identifier", "ZZSIDB-" + n)).getStatusCode().value()).isEqualTo(202);
        String reset = jdbc.sql("SELECT body FROM platform.notice WHERE about_kind = 'staff' AND about_id = :b AND channel = 'EMAIL' ORDER BY created_at DESC LIMIT 1")
                .param("b", b).query(String.class).single();
        Matcher link = Pattern.compile("token=([0-9a-f]+)").matcher(reset);
        assertThat(link.find()).as(reset).isTrue();
        String resetToken = link.group(1);
        // an office types B's address on A's record as well (unverified, so nothing refuses it): A is shown none of B's mail, and B is
        // never shown the link either — it proves the mailbox, and the portal never stands in for the mailbox
        it.db(() -> jdbc.sql("UPDATE iam.person SET email = :bm WHERE id = :a").param("a", a).param("bm", bMail.toUpperCase()).update());
        listA = listed(tokenA);
        assertThat(listA).doesNotContain(resetToken).doesNotContain(second).doesNotContain("Reset your MOAUM password");
        assertThat(listed(tokenB)).doesNotContain(resetToken).doesNotContain("Reset your MOAUM password");

        // B verifies B's own address from B's mailbox: still neither code nor link comes back to B, and A (whose copy stands, unverified)
        // is shown nothing sent to it; a work notice to B's verified address is B's
        assertThat(it.call(tokenB, HttpMethod.POST, BASE + "/email/code", Map.of("email", bMail)).getStatusCode().value()).isEqualTo(200);
        String bCode = codeFor(b);
        assertThat(it.call(tokenB, HttpMethod.POST, BASE + "/email/verify", Map.of("code", bCode)).getBody()).containsEntry("outcome", "VERIFIED");
        UUID offering = UUID.randomUUID();
        it.db(() -> jdbc.sql("SELECT platform.queue_notice('EMAIL', :to, 'ZZSID course allocated', 'A course is allocated to you.', 'offering', :o)")
                .param("to", bMail).param("o", offering).query().singleRow());
        List<Map<String, Object>> mineB = it.getList(tokenB, "/api/v1/me/notices?limit=500").getBody();
        assertThat(words(mineB)).doesNotContain(bCode).doesNotContain(second).doesNotContain(resetToken).doesNotContain("STAFF_EMAIL_CODE");
        assertThat(mineB).anySatisfy(x -> assertThat(x).containsEntry("subject", "ZZSID course allocated"));
        listA = listed(tokenA);
        assertThat(listA).doesNotContain("ZZSID course allocated").doesNotContain(resetToken).doesNotContain(bCode);
        // and no door now places B's verified address on another record — a person added by an office is refused it (the rule is on
        // iam.person itself) — while A's copy, typed before, stands as it is when A's record is written again
        ResponseEntity<Map> added = it.call(TestTokens.token(it.person("ZZSID-HRM", "ZZSIDHRM"), List.of("hrm")), HttpMethod.POST, "/api/v1/iam/persons",
                Map.of("staffNumber", "ZZSIDC-" + n, "surname", "ZZSIDC" + n, "givenNames", "Invented", "email", " " + bMail.toUpperCase()));
        assertThat(added.getStatusCode().value()).as(String.valueOf(added.getBody())).isEqualTo(422);
        assertThat(added.getBody()).containsEntry("code", "IDENTITY_EMAIL_TAKEN");
        assertThat(jdbc.sql("SELECT count(*) FROM iam.person WHERE staff_number = :s").param("s", "ZZSIDC-" + n).query(Long.class).single()).isZero();
        it.db(() -> jdbc.sql("UPDATE iam.person SET email = :bm, phone = '08030000000' WHERE id = :a").param("a", a).param("bm", "  " + bMail + " ").update());
        assertThat(email(a)).isEqualTo("  " + bMail + " ");

        // what is A's own is still listed: a notice filed against A, and the notices of A's work to an address A's record alone holds
        // (not yet verified) — a score sheet, a deferment at A's desk, a report sent from the portal (its public check code is no
        // secret), an office's notice. Not, with the address unverified, another's mail sent to it: an applicant's own message (filed
        // 'application' as an office's notice is, but unmarked — sent while an applicant account held the address, since corrected
        // away from it), nor a reply to a sign-in ticket raised with it from the sign-in page (the request names no one)
        it.db(() -> jdbc.sql("UPDATE iam.person SET email = :am WHERE id = :a").param("a", a).param("am", aMail).update());
        it.db(() -> jdbc.sql("SELECT platform.queue_notice('EMAIL', :to, 'ZZSID about A', 'A notice filed against A.', 'person', :a)")
                .param("to", aMail).param("a", a).query().singleRow());
        it.db(() -> jdbc.sql("SELECT platform.queue_notice('EMAIL', :to, 'ZZSID sheet of A', 'A score sheet waits for A.', 'score_sheet', :o)")
                .param("to", aMail).param("o", UUID.randomUUID()).query().singleRow());
        it.db(() -> jdbc.sql("SELECT platform.queue_notice('EMAIL', :to, 'ZZSID deferment at A''s desk', 'A deferment request awaits you.\n\nDeferment reference: DEF/ZZSID', 'deferment', :o)")
                .param("to", aMail).param("o", UUID.randomUUID()).query().singleRow());
        it.db(() -> jdbc.sql("SELECT platform.queue_notice('EMAIL', :to, 'ZZSID report sent to A', 'Please find attached the return.\n\nVerification code: ZZSIDCHECK\nThe figures can be checked at https://portal.example/verify/report/ZZSIDCHECK', 'report_snapshot', :o)")
                .param("to", aMail).param("o", UUID.randomUUID()).query().singleRow());
        // as admissions.tell_office files an office's notice to each holder (the calendar, the audit chain, the staff reach digest …):
        // 'application', marked OFFICE_TELL
        it.db(() -> jdbc.sql("SELECT platform.queue_notice('EMAIL', :to, 'ZZSID the office is told', 'A notice to every holder of the office.', 'application', NULL::uuid, NULL, 'OFFICE_TELL', NULL)")
                .param("to", aMail).query().singleRow());
        it.db(() -> jdbc.sql("SELECT platform.queue_notice('EMAIL', :to, 'ZZSID applicant''s own to A''s address', 'Your MOAUM applicant account: application APP/ZZSID, JAMB 20990000000ZZ.', 'application', :o)")
                .param("to", aMail).param("o", UUID.randomUUID()).query().singleRow());
        it.db(() -> jdbc.sql("SELECT platform.queue_notice('EMAIL', :to, 'ZZSID ticket to A''s address', 'Your ticket TCK-ZZSID needs something from you. Track the ticket at /track with the number and this email address.', 'ticket', :o)")
                .param("to", aMail).param("o", UUID.randomUUID()).query().singleRow());
        List<Map<String, Object>> mineA = it.getList(tokenA, "/api/v1/me/notices?limit=500").getBody();
        assertThat(mineA).anySatisfy(x -> assertThat(x).containsEntry("subject", "ZZSID about A"));
        assertThat(mineA).anySatisfy(x -> assertThat(x).containsEntry("subject", "ZZSID sheet of A"));
        assertThat(mineA).anySatisfy(x -> assertThat(x).containsEntry("subject", "ZZSID deferment at A's desk").containsEntry("about_kind", "deferment"));
        assertThat(mineA).anySatisfy(x -> assertThat(x).containsEntry("subject", "ZZSID report sent to A").containsEntry("about_kind", "report_snapshot"));
        assertThat(mineA).anySatisfy(x -> assertThat(x).containsEntry("subject", "ZZSID the office is told").containsEntry("about_kind", "application")
                .containsEntry("template_key", "OFFICE_TELL"));
        assertThat(words(mineA)).doesNotContain("ZZSID applicant's own to A's address").doesNotContain("APP/ZZSID")
                .doesNotContain("ZZSID ticket to A's address").doesNotContain("TCK-ZZSID");
        // the newest first, stopping at the limit: the newest two are the first two of the whole list
        List<Map<String, Object>> twoA = it.getList(tokenA, "/api/v1/me/notices?limit=2").getBody();
        assertThat(twoA.stream().map(x -> x.get("id")).toList()).isEqualTo(mineA.stream().limit(2).map(x -> x.get("id")).toList());
        // and none of A's work to B, whose address is B's (verified); a sign-in ticket's reply sent to B's verified address is B's
        it.db(() -> jdbc.sql("SELECT platform.queue_notice('EMAIL', :to, 'ZZSID ticket to B''s address', 'Your ticket TCK-ZZSIB needs something from you.', 'ticket', :o)")
                .param("to", bMail).param("o", UUID.randomUUID()).query().singleRow());
        List<Map<String, Object>> mineB2 = it.getList(tokenB, "/api/v1/me/notices?limit=500").getBody();
        assertThat(words(mineB2)).doesNotContain("ZZSID deferment at A's desk").doesNotContain("ZZSID the office is told").doesNotContain("ZZSID ticket to A's address");
        assertThat(mineB2).anySatisfy(x -> assertThat(x).containsEntry("subject", "ZZSID ticket to B's address").containsEntry("about_kind", "ticket"));

        // once the code's message has gone, its words leave the outbox
        UUID bNotice = jdbc.sql("SELECT n.id FROM platform.notice n JOIN iam.email_verification x ON x.id = n.about_id WHERE n.about_kind = 'email_verification' AND x.person_id = :b")
                .param("b", b).query(UUID.class).single();
        it.db(() -> jdbc.sql("UPDATE platform.notice SET state = 'SENT', sent_at = now() WHERE id = :n").param("n", bNotice).update());
        assertThat(jdbc.sql("SELECT body FROM platform.notice WHERE id = :n").param("n", bNotice).query(String.class).single()).doesNotContain(bCode);
    }
}
