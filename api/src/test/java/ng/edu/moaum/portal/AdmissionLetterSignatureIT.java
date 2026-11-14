package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.awt.BasicStroke;
import java.awt.Color;
import java.awt.Graphics2D;
import java.awt.RenderingHints;
import java.awt.image.BufferedImage;
import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.net.URI;
import java.time.OffsetDateTime;
import java.util.Arrays;
import java.util.Base64;
import java.util.List;
import java.util.Map;
import java.util.Random;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;

import javax.imageio.ImageIO;

import ng.edu.moaum.portal.shared.FileStore;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Primary;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpMethod;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.web.client.RestClient;

/**
 * V759 — the admission letter's signature uploaded as a setting, through the API. A made-up applicant is offered a place, accepts
 * and pays, and opens the letter: no signature yet. The offices that change the document templates upload the signature of the
 * signatory the letter's template names (the name typed loosely: case and spacing aside it is the same signatory); an office that
 * only reads the templates, ICT, may not, nor may the database be written to as another office; a file that is not a PNG or JPEG,
 * one over a megabyte, one that does not decode, and a name no template states are refused with their codes. The letter's JSON —
 * at the applicant's door and the student's — then carries the signature as the JPEG on white the letter draws (a transparent
 * 1057 × 350 PNG as 800 × 265); the offices that read the templates list it and read the image, an applicant, a student and the
 * public do not. A template version naming someone else carries no signature (that person's is not held), and the earlier
 * signatory's stays listed so it can be removed. The Academic Office replaces it with a JPEG (a new version, the letter's JPEG with
 * it); the Registrar removes it (the row and the trail kept, the version rising): the letter carries none, the image is gone, and a
 * second removal is refused. Needs DATABASE_URL. The University's real signature is never used here: the images are drawn.
 * <p>
 * The fixes of the review: the file store (in memory here, switched on for the replacement as S3 is on AWS) holds both images of a
 * replacement and gives them back to the letter and the screen; an upload for a name no template states puts nothing in it; a store
 * that cannot give the signature back leaves the letter printing without it rather than failing; a phone's JPEG stored on its side
 * (EXIF orientation 6) prints upright; the refusal of a file just over 1 MB says its size in the limit's unit; and the new template
 * version naming someone else is put in force through Document settings' own door, the admission letter being a template kind.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class AdmissionLetterSignatureIT {

    static final String CS = "C00023";
    static final String BASE = "/api/v1/documents/signatures";

    /** an object store in memory, off until the test turns it on (the files then stay in the rows, as on Railway), and able to fail
     *  every read as a store out of reach does */
    static final class MemoryStore implements FileStore {
        final Map<String, byte[]> objects = new ConcurrentHashMap<>();
        volatile boolean on;
        volatile boolean broken;

        @Override
        public boolean enabled() {
            return on;
        }

        @Override
        public void put(String key, byte[] bytes, String contentType) {
            if (!on) throw new IllegalStateException("no object store is configured");
            objects.put(key, bytes);
        }

        @Override
        public byte[] get(String key) {
            if (broken) throw new IllegalStateException("the object store is out of reach");
            byte[] b = objects.get(key);
            if (b == null) throw new IllegalStateException("no such key " + key);
            return b;
        }

        @Override
        public void delete(String key) {
            objects.remove(key);
        }
    }

    @TestConfiguration
    static class Store {
        @Bean
        @Primary
        MemoryStore memoryStore() {
            return new MemoryStore();
        }
    }

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;
    @Autowired
    MemoryStore store;

    ItSupport it;
    String session;
    String path;
    final String bursar = ItSupport.token("bursar");

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
        int year = it.freeYear(9960, 9990);
        session = year + "/" + (year + 1);
        path = "/api/v1/admissions/sessions/" + year + "/" + (year + 1);
        it.session(session, year);
        it.db(() -> jdbc.sql("INSERT INTO admissions.applicant_fee (session, application_fee, portal_charge, acceptance_fee, checking_fee) VALUES (:s, 2000, 0, 25000, 3000) ON CONFLICT (session) DO UPDATE SET acceptance_fee = 25000")
                .param("s", session).update());
    }

    record Applicant(UUID app, String token) { }

    /** an applicant offered a place who has accepted it and paid the acceptance fee: the letter is theirs to open */
    Applicant admitted() {
        int n = new Random().nextInt(90_000_000) + 10_000_000;
        String jamb = session.substring(0, 4) + n + "SG";
        String no = "APP/" + session.substring(2, 4) + "/" + String.format("%06d", n % 1_000_000);
        Applicant a = it.db(() -> {
            UUID cand = UUID.randomUUID(), acct = UUID.randomUUID(), app = UUID.randomUUID(), batch = UUID.randomUUID();
            jdbc.sql("INSERT INTO admissions.caps_batch (id, session, source, filename, file_sha256, rows_read, list_kind, downloaded_on, uploaded_by, uploaded_office, committed_at) VALUES (:id, :s, 'CAPS_DOWNLOAD', 'signature.xlsx', decode(md5(random()::text) || md5(random()::text), 'hex'), 1, 'UTME', current_date, gen_random_uuid(), 'academic', now())")
                    .param("id", batch).param("s", session).update();
            jdbc.sql("INSERT INTO admissions.caps_row (id, batch_id, session, jamb_reg_no, raw, surname, other_names, jamb_code, aggregate, entry_mode, sex) VALUES (gen_random_uuid(), :b, :s, :j, '{}'::jsonb, :sn, 'Signature Person', :p, 250, 'UTME', 'F')")
                    .param("b", batch).param("s", session).param("j", jamb).param("sn", "ZZSIG-" + n).param("p", CS).update();
            jdbc.sql("INSERT INTO admissions.candidate (id, session, jamb_reg_no, surname, other_names, programme, entry_mode, entry_level, offer_state, admitted_from) VALUES (:id, :s, :j, :sn, 'Signature Person', (SELECT name FROM ref.programme WHERE code = :p), 'UTME', 100, 'ADMITTED', (SELECT id FROM admissions.caps_row WHERE session = :s AND jamb_reg_no = :j))")
                    .param("id", cand).param("s", session).param("j", jamb).param("sn", "ZZSIG-" + n).param("p", CS).update();
            jdbc.sql("INSERT INTO admissions.applicant_account (id, session, candidate_id, jamb_key, email, phone, password_hash) VALUES (:id, :s, :c, :k, :e, '08030000000', crypt('x', gen_salt('bf', 12)))")
                    .param("id", acct).param("s", session).param("c", cand).param("k", jamb).param("e", jamb.toLowerCase() + "@example.com").update();
            jdbc.sql("INSERT INTO admissions.application (id, account_id, candidate_id, session, application_no, fee_confirmed_at, submitted_at, decision, decided_at, decision_released_at, checking_confirmed_at, status_checked_at) VALUES (:id, :a, :c, :s, :no, now(), now(), 'OFFERED', now(), now(), now(), now())")
                    .param("id", app).param("a", acct).param("c", cand).param("s", session).param("no", no).update();
            return new Applicant(app, TestTokens.token(acct, List.of("applicant")));
        });
        assertThat(it.call(a.token(), HttpMethod.POST, "/api/v1/applicant/me/accept", Map.of("undertaking", true)).getStatusCode().value()).isEqualTo(200);
        ResponseEntity<Map> ref = it.call(a.token(), HttpMethod.POST, "/api/v1/applicant/me/fee-references", Map.of("kind", "ACCEPTANCE"));
        assertThat(ref.getStatusCode().value()).as(String.valueOf(ref.getBody())).isEqualTo(200);
        ResponseEntity<Map> paid = it.call(bursar, HttpMethod.POST, path + "/fee-references/" + ref.getBody().get("reference") + "/confirm", Map.of("channel", "Card"));
        assertThat(paid.getStatusCode().value()).as(String.valueOf(paid.getBody())).isEqualTo(200);
        return a;
    }

    /** a signature in blue ink on a transparent background, as the University scans its own */
    static byte[] png(int w, int h) throws Exception {
        BufferedImage img = new BufferedImage(w, h, BufferedImage.TYPE_INT_ARGB);
        Graphics2D g = img.createGraphics();
        g.setRenderingHint(RenderingHints.KEY_ANTIALIASING, RenderingHints.VALUE_ANTIALIAS_ON);
        g.setColor(new Color(20, 40, 160));
        g.setStroke(new BasicStroke(Math.max(3, w / 120f)));
        int[] xs = new int[9], ys = new int[9];
        for (int i = 0; i < 9; i++) {
            xs[i] = w / 12 + i * w / 10;
            ys[i] = i % 2 == 0 ? h * 3 / 4 : h / 4;
        }
        g.drawPolyline(xs, ys, 9);
        g.dispose();
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        ImageIO.write(img, "png", out);
        return out.toByteArray();
    }

    /** a signature photographed on a phone: its pixels stored on their side (h wide, w high) and the EXIF orientation 6 telling a
     *  viewer to turn them a quarter clockwise — upright it is w × h, with a dark mark in its top-left corner. A dot placed at random
     *  in the middle makes each run's file its own: the file store reuses an object already recorded with the same bytes, which an
     *  earlier run's in-memory store no longer holds */
    static byte[] phoneJpeg(int w, int h) throws Exception {
        BufferedImage stored = new BufferedImage(h, w, BufferedImage.TYPE_INT_RGB);
        Graphics2D g = stored.createGraphics();
        g.setColor(Color.WHITE);
        g.fillRect(0, 0, h, w);
        g.setColor(new Color(10, 20, 90));
        // upright (x, y) is stored at (y, w - 1 - x): the upright top-left corner is the stored bottom-left
        g.fillRect(0, w - w / 8, h / 4, w / 8);
        g.setStroke(new BasicStroke(4));
        g.drawLine(h / 2, w / 10, h / 2, w * 9 / 10);
        Random dot = new Random();
        g.fillRect(h / 2 - 20 + dot.nextInt(40), w / 3 + dot.nextInt(w / 3), 4, 4);
        g.dispose();
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        ImageIO.write(stored, "jpeg", out);
        byte[] plain = out.toByteArray();
        assertThat(plain[2] & 0xFF).as("the JDK's writer begins with a JFIF APP0").isEqualTo(0xFF);
        assertThat(plain[3] & 0xFF).isEqualTo(0xE0);
        // after the SOI and the APP0, an APP1 "Exif" whose IFD0 holds the one tag Orientation (0x0112), a SHORT, 6
        int at = 4 + (((plain[4] & 0xFF) << 8) | (plain[5] & 0xFF));
        byte[] exif = {(byte) 0xFF, (byte) 0xE1, 0x00, 0x22, 'E', 'x', 'i', 'f', 0, 0, 'M', 'M', 0, 0x2A, 0, 0, 0, 8,
            0, 1, 0x01, 0x12, 0, 3, 0, 0, 0, 1, 0, 6, 0, 0, 0, 0, 0, 0};
        ByteArrayOutputStream withExif = new ByteArrayOutputStream();
        withExif.write(plain, 0, at);
        withExif.write(exif);
        withExif.write(plain, at, plain.length - at);
        return withExif.toByteArray();
    }

    /** a PNG of a few dozen bytes whose header claims a picture of w × h pixels: refused on the header, never decoded */
    static byte[] pngClaiming(int w, int h) {
        java.nio.ByteBuffer ihdr = java.nio.ByteBuffer.allocate(17);
        ihdr.put("IHDR".getBytes()).putInt(w).putInt(h).put((byte) 8).put((byte) 6).put((byte) 0).put((byte) 0).put((byte) 0);
        java.util.zip.CRC32 crc = new java.util.zip.CRC32();
        crc.update(ihdr.array());
        java.nio.ByteBuffer png = java.nio.ByteBuffer.allocate(8 + 4 + 17 + 4 + 12);
        png.put(new byte[] {(byte) 0x89, 'P', 'N', 'G', 0x0D, 0x0A, 0x1A, 0x0A}).putInt(13).put(ihdr.array()).putInt((int) crc.getValue());
        png.putInt(0).put("IEND".getBytes()).putInt(0xAE426082);
        return png.array();
    }

    static String b64(byte[] bytes) {
        return Base64.getEncoder().encodeToString(bytes);
    }

    /** a GET of bytes at an address the API gave (its query already encoded), with a token or none */
    ResponseEntity<byte[]> bytes(String token, String address) {
        RestClient.RequestHeadersSpec<?> spec = RestClient.builder().defaultStatusHandler(status -> true, (request, response) -> { }).build()
                .get().uri(URI.create("http://localhost:" + port + address));
        if (token != null) spec = spec.header(HttpHeaders.AUTHORIZATION, "Bearer " + token);
        return spec.retrieve().toEntity(byte[].class);
    }

    ResponseEntity<Map> put(String token, Map<String, Object> body) {
        return it.call(token, HttpMethod.PUT, BASE, body);
    }

    ResponseEntity<Map> delete(String token, String name) {
        return it.call(token, HttpMethod.DELETE, b -> b.path(BASE).queryParam("name", name).build(), null);
    }

    /** the signatories as the offices that read the templates list them */
    List<Map<String, Object>> listed(String token) {
        ResponseEntity<List> r = it.getList(token, BASE);
        assertThat(r.getStatusCode().value()).as(String.valueOf(r.getBody())).isEqualTo(200);
        return (List<Map<String, Object>>) r.getBody();
    }

    String key(Object name) {
        return jdbc.sql("SELECT credentials.signatory_key(:n)").param("n", String.valueOf(name)).query(String.class).single();
    }

    /** the signatory's entry, found as the database matches names: a signature kept for a name no current template states is listed
     *  under the name as it was typed for the upload */
    Map<String, Object> entry(List<Map<String, Object>> list, String name) {
        String k = key(name);
        return list.stream().filter(e -> k.equals(key(e.get("name")))).findFirst().orElseThrow(() -> new AssertionError(name + " is not listed: " + list));
    }

    static int version(Map<String, Object> e) {
        return e.get("version") == null ? 0 : ((Number) e.get("version")).intValue();
    }

    static Map<String, Object> m(Object o) {
        return (Map<String, Object>) o;
    }

    @Test
    void theTemplateOfficesUploadTheSignatureEveryLetterNamingItsSignatoryPrints() throws Exception {
        String tag = UUID.randomUUID().toString().substring(0, 6).toUpperCase();
        UUID deputy = it.person("ZZ-SIG-D" + tag, "ZZSIGDEPUTY");
        String dregistrar = TestTokens.token(deputy, List.of("dregistrar"));
        String academic = ItSupport.token("academic");
        String registrar = ItSupport.token("registrar");
        String records = ItSupport.token("records");
        String ict = ItSupport.token("ict");

        // the signatory the admission letter's template names now (the live template: the Deputy Registrar's name)
        String signatory = jdbc.sql("SELECT signatory_name FROM credentials.document_template WHERE kind = 'ADMISSION_LETTER' AND active ORDER BY version DESC LIMIT 1")
                .query(String.class).single();
        String key = jdbc.sql("SELECT credentials.signatory_key(:n)").param("n", signatory).query(String.class).single();
        // a run stopped part-way may have left one held: the Registrar removes it, so the letter starts without
        if (Boolean.TRUE.equals(entry(listed(records), signatory).get("hasSignature"))) {
            assertThat(delete(registrar, signatory).getStatusCode().value()).isEqualTo(200);
        }
        int v0 = version(entry(listed(records), signatory));
        OffsetDateTime from = jdbc.sql("SELECT clock_timestamp()").query(OffsetDateTime.class).single();

        Applicant a = admitted();
        UUID student = jdbc.sql("SELECT s.id FROM people.student s JOIN admissions.application ap ON ap.candidate_id = s.candidate_id WHERE ap.id = :a")
                .param("a", a.app()).query(UUID.class).single();
        String studentToken = TestTokens.token(student, List.of("student"));
        ResponseEntity<Map> plain = it.get(a.token(), "/api/v1/applicant/me/letter");
        assertThat(plain.getStatusCode().value()).as(String.valueOf(plain.getBody())).isEqualTo(200);
        assertThat(m(plain.getBody().get("template"))).containsEntry("signatory_name", signatory);
        assertThat(plain.getBody()).doesNotContainKey("signature");

        // who may set it: the offices that change the templates; ICT and the Records office read the templates and may not; nor may
        // the database be written to as one of them
        String png = b64(png(1057, 350));
        assertThat(put(ict, Map.of("name", signatory, "filename", "signature.png", "contentBase64", png)).getStatusCode().value()).isEqualTo(403);
        assertThat(put(records, Map.of("name", signatory, "filename", "signature.png", "contentBase64", png)).getStatusCode().value()).isEqualTo(403);
        assertThatThrownBy(() -> it.db(() -> jdbc.sql("SELECT credentials.set_signatory_signature(:n, '\\x89504e47'::bytea, NULL, 'image/png', '\\xffd8'::bytea, NULL, 10, 10)")
                .param("n", signatory).query().listOfRows())).rootCause().hasMessageContaining("SIGNATORY_SIGNATURE_OFFICE");

        // what is refused, with its code: not an image, over a megabyte, an image that does not decode or is too small to print, no
        // name, no file, a name no template states
        assertThat(put(registrar, Map.of("name", signatory, "filename", "x.txt", "contentBase64", b64("not an image".getBytes()))).getBody())
                .containsEntry("code", "SIGNATORY_SIGNATURE_FORMAT").containsEntry("status", 422);
        byte[] big = new byte[1_000_001];
        System.arraycopy(new byte[] {(byte) 0x89, 'P', 'N', 'G', 0x0D, 0x0A, 0x1A, 0x0A}, 0, big, 0, 8);
        Map<String, Object> tooLarge = put(registrar, Map.of("name", signatory, "filename", "big.png", "contentBase64", b64(big))).getBody();
        assertThat(tooLarge).containsEntry("code", "SIGNATORY_SIGNATURE_TOO_LARGE").containsEntry("status", 422);
        // its size in the limit's own unit, rounded up — never "976 KB" of a file refused as over 1 MB
        assertThat(tooLarge.get("detail")).isEqualTo("The signature is 1.01 MB (1,000,001 bytes); the limit is 1 MB (1,000,000 bytes).");
        byte[] broken = Arrays.copyOf(png(400, 120), 60);
        assertThat(put(registrar, Map.of("name", signatory, "filename", "broken.png", "contentBase64", b64(broken))).getBody())
                .containsEntry("code", "SIGNATORY_SIGNATURE_UNREADABLE");
        assertThat(put(registrar, Map.of("name", signatory, "filename", "tiny.png", "contentBase64", b64(png(30, 10)))).getBody())
                .containsEntry("code", "SIGNATORY_SIGNATURE_UNREADABLE");
        Map<String, Object> vast = put(registrar, Map.of("name", signatory, "filename", "vast.png", "contentBase64", b64(pngClaiming(40_000, 30_000)))).getBody();
        assertThat(vast).containsEntry("code", "SIGNATORY_SIGNATURE_UNREADABLE");
        assertThat(String.valueOf(vast.get("detail"))).contains("40000 × 30000 pixels");
        assertThat(put(registrar, Map.of("name", signatory, "filename", "x.png", "contentBase64", "@@ not base64 @@")).getBody())
                .containsEntry("code", "SIGNATORY_SIGNATURE_UNREADABLE");
        assertThat(put(registrar, Map.of("name", "  ", "filename", "signature.png", "contentBase64", png)).getBody())
                .containsEntry("code", "SIGNATORY_SIGNATURE_NAME");
        assertThat(put(registrar, Map.of("name", signatory)).getBody()).containsEntry("code", "SIGNATORY_SIGNATURE_IMAGE");
        // a name no template states, with a file store configured: refused before anything is put in the store, where nothing would
        // reach it
        String nobody = "ZZ Nobody Named " + tag;
        store.on = true;
        try {
            assertThat(put(registrar, Map.of("name", nobody, "filename", "signature.png", "contentBase64", png)).getBody())
                    .containsEntry("code", "SIGNATORY_SIGNATURE_UNKNOWN").containsEntry("status", 422);
        } finally {
            store.on = false;
        }
        assertThat(store.objects.keySet()).noneMatch(k -> k.startsWith("credentials/signatory_signature/" + key(nobody) + "/"));
        assertThat(entry(listed(records), signatory)).containsEntry("hasSignature", false);

        // the Deputy Registrar uploads it, the name typed loosely: the same signatory, case and spacing aside
        String loose = "  " + signatory.toLowerCase().replace(" ", "  ").replace(", ", " ,") + " ";
        ResponseEntity<Map> up = put(dregistrar, Map.of("name", loose, "filename", "signature.png", "contentBase64", png));
        assertThat(up.getStatusCode().value()).as(String.valueOf(up.getBody())).isEqualTo(200);
        assertThat(up.getBody()).containsEntry("name", signatory).containsEntry("hasSignature", true).containsEntry("version", v0 + 1)
                .containsEntry("inUse", true).containsEntry("setOffice", "dregistrar").containsEntry("setByName", "ZZSIGDEPUTY, Invented");
        assertThat((List<String>) up.getBody().get("kinds")).contains("ADMISSION_LETTER");
        // no store configured: both images in the row
        assertThat(jdbc.sql("""
                SELECT signature IS NOT NULL AND signature_object_id IS NULL AND signature_jpeg IS NOT NULL AND signature_jpeg_object_id IS NULL
                  FROM credentials.signatory_signature WHERE name_key = :k
                """).param("k", key).query(Boolean.class).single()).isTrue();

        // the offices that read the templates list it, the admission letter's signatory first, and read the image as uploaded and as
        // the JPEG the letter draws
        List<Map<String, Object>> list = listed(records);
        assertThat(list.get(0)).containsEntry("name", signatory).containsEntry("hasSignature", true);
        String url = String.valueOf(list.get(0).get("signatureUrl"));
        assertThat(url).startsWith(BASE + "/image?name=").endsWith("&v=" + (v0 + 1));
        ResponseEntity<byte[]> original = bytes(records, url);
        assertThat(original.getStatusCode().value()).isEqualTo(200);
        assertThat(original.getHeaders().getContentType().toString()).isEqualTo("image/png");
        assertThat(original.getBody()).isEqualTo(Base64.getDecoder().decode(png));
        ResponseEntity<byte[]> printed = bytes(registrar, url + "&format=jpeg");
        assertThat(printed.getStatusCode().value()).isEqualTo(200);
        assertThat(printed.getHeaders().getContentType().toString()).isEqualTo("image/jpeg");

        // never an applicant's, a student's or the public's: the list and the image are the offices'
        assertThat(bytes(a.token(), url).getStatusCode().value()).isEqualTo(403);
        assertThat(bytes(studentToken, url).getStatusCode().value()).isEqualTo(403);
        assertThat(bytes(null, url).getStatusCode().value()).isIn(401, 403);
        assertThat(it.get(a.token(), BASE).getStatusCode().value()).isEqualTo(403);
        assertThat(it.get(studentToken, BASE).getStatusCode().value()).isEqualTo(403);

        // the letter carries it, to its owner, at both doors: the transparent 1057 × 350 PNG as the 800 × 265 JPEG on white
        Map<String, Object> letter = it.get(a.token(), "/api/v1/applicant/me/letter").getBody();
        Map<String, Object> sig = m(letter.get("signature"));
        assertThat(sig).containsEntry("width", 800).containsEntry("height", 265);
        byte[] drawn = Base64.getDecoder().decode(String.valueOf(sig.get("jpegBase64")));
        assertThat(drawn).isEqualTo(printed.getBody());
        BufferedImage seen = ImageIO.read(new ByteArrayInputStream(drawn));
        assertThat(seen.getWidth()).isEqualTo(800);
        assertThat(seen.getHeight()).isEqualTo(265);
        assertThat(new Color(seen.getRGB(2, 2)).getRed()).isGreaterThan(240);     // the transparent background is the paper's white
        ResponseEntity<Map> fromLibrary = it.get(studentToken, "/api/v1/me/admission-documents/letter");
        assertThat(fromLibrary.getStatusCode().value()).as(String.valueOf(fromLibrary.getBody())).isEqualTo(200);
        assertThat(m(fromLibrary.getBody().get("signature"))).containsEntry("jpegBase64", sig.get("jpegBase64"));

        // a template version that names someone else, put in force on Document settings (the admission letter is a template kind):
        // every letter is drawn with it, the earlier ones included, and carries no signature (that person's is not held); the earlier
        // signatory's stays listed, no longer in use, so it can be removed
        String activeBefore = jdbc.sql("SELECT string_agg(version::text, ',') FROM credentials.document_template WHERE kind = 'ADMISSION_LETTER' AND active")
                .query(String.class).single();
        int next = jdbc.sql("SELECT max(version) + 1 FROM credentials.document_template WHERE kind = 'ADMISSION_LETTER'").query(Integer.class).single();
        String other = "ZZ Other Signatory " + tag;
        Map<String, Object> current = jdbc.sql("""
                SELECT title, subtitle, signatory_title, second_name, second_title, footer, remarks
                  FROM credentials.document_template WHERE kind = 'ADMISSION_LETTER' AND active ORDER BY version DESC LIMIT 1
                """).query().singleRow();
        Map<String, Object> version = new java.util.HashMap<>();
        version.put("kind", "ADMISSION_LETTER");
        version.put("title", current.get("title"));
        version.put("subtitle", current.get("subtitle"));
        version.put("signatoryName", other);
        version.put("signatoryTitle", current.get("signatory_title"));
        version.put("secondName", current.get("second_name"));
        version.put("secondTitle", current.get("second_title"));
        version.put("footer", current.get("footer"));
        version.put("remarks", current.get("remarks"));
        try {
            ResponseEntity<Map> inForce = it.call(registrar, HttpMethod.POST, "/api/v1/documents/templates", version);
            assertThat(inForce.getStatusCode().value()).as(String.valueOf(inForce.getBody())).isEqualTo(200);
            assertThat(inForce.getBody()).containsEntry("version", next);
            Map<String, Object> named = it.get(a.token(), "/api/v1/applicant/me/letter").getBody();
            assertThat(m(named.get("template"))).containsEntry("signatory_name", other);
            assertThat(named).doesNotContainKey("signature");
            List<Map<String, Object>> now = listed(records);
            assertThat(now.get(0)).containsEntry("name", other).containsEntry("hasSignature", false).containsEntry("inUse", true);
            assertThat(entry(now, signatory)).containsEntry("hasSignature", true).containsEntry("inUse", false).containsEntry("name", loose.trim())
                    .containsEntry("kinds", List.of());
            assertThat(bytes(records, String.valueOf(entry(now, signatory).get("signatureUrl"))).getStatusCode().value()).isEqualTo(200);
        } finally {
            it.db(() -> {
                jdbc.sql("DELETE FROM credentials.document_template WHERE kind = 'ADMISSION_LETTER' AND version = :v").param("v", next).update();
                return jdbc.sql("UPDATE credentials.document_template SET active = (version::text = ANY (string_to_array(:a, ','))) WHERE kind = 'ADMISSION_LETTER'")
                        .param("a", activeBefore).update();
            });
        }
        assertThat(it.get(a.token(), "/api/v1/applicant/me/letter").getBody().get("signature")).isNotNull();

        // the Academic Office replaces it with a JPEG photographed on a phone — stored on its side, EXIF orientation 6 — now with a file
        // store configured: a new version, both images in the store, and the letter's JPEG upright, 600 × 200, its mark top-left
        store.on = true;
        byte[] scan = phoneJpeg(600, 200);
        ResponseEntity<Map> replaced = put(academic, Map.of("name", signatory, "filename", "signature.jpg", "contentBase64", b64(scan)));
        assertThat(replaced.getStatusCode().value()).as(String.valueOf(replaced.getBody())).isEqualTo(200);
        assertThat(replaced.getBody()).containsEntry("hasSignature", true).containsEntry("version", v0 + 2).containsEntry("setOffice", "academic");
        assertThat(jdbc.sql("""
                SELECT signature IS NULL AND signature_object_id IS NOT NULL AND signature_jpeg IS NULL AND signature_jpeg_object_id IS NOT NULL
                  FROM credentials.signatory_signature WHERE name_key = :k
                """).param("k", key).query(Boolean.class).single()).as("both images in the store, none in the row").isTrue();
        assertThat(store.objects.keySet().stream().filter(k -> k.startsWith("credentials/signatory_signature/" + key + "/")).count()).isEqualTo(2);
        Map<String, Object> again = m(it.get(a.token(), "/api/v1/applicant/me/letter").getBody().get("signature"));
        assertThat(again).containsEntry("width", 600).containsEntry("height", 200);
        assertThat(again.get("jpegBase64")).isNotEqualTo(sig.get("jpegBase64"));
        BufferedImage upright = ImageIO.read(new ByteArrayInputStream(Base64.getDecoder().decode(String.valueOf(again.get("jpegBase64")))));
        assertThat(upright.getWidth()).isEqualTo(600);
        assertThat(upright.getHeight()).isEqualTo(200);
        assertThat(new Color(upright.getRGB(10, 10)).getRed()).as("the mark stands top-left, as the phone showed it").isLessThan(100);
        assertThat(new Color(upright.getRGB(590, 10)).getRed()).isGreaterThan(240);
        assertThat(new Color(upright.getRGB(10, 190)).getRed()).isGreaterThan(240);
        ResponseEntity<byte[]> asUploaded = bytes(records, String.valueOf(entry(listed(records), signatory).get("signatureUrl")));
        assertThat(asUploaded.getHeaders().getContentType().toString()).isEqualTo("image/jpeg");
        assertThat(asUploaded.getBody()).isEqualTo(scan);

        // a store that cannot give the signature back never stops the letter: it prints with the space for a hand signature, at both
        // doors, and with the signature again once the store answers
        store.broken = true;
        try {
            ResponseEntity<Map> unreadable = it.get(a.token(), "/api/v1/applicant/me/letter");
            assertThat(unreadable.getStatusCode().value()).as(String.valueOf(unreadable.getBody())).isEqualTo(200);
            assertThat(unreadable.getBody()).doesNotContainKey("signature").containsKey("template");
            ResponseEntity<Map> unreadableStudent = it.get(studentToken, "/api/v1/me/admission-documents/letter");
            assertThat(unreadableStudent.getStatusCode().value()).as(String.valueOf(unreadableStudent.getBody())).isEqualTo(200);
            assertThat(unreadableStudent.getBody()).doesNotContainKey("signature");
        } finally {
            store.broken = false;
        }
        assertThat(m(it.get(a.token(), "/api/v1/applicant/me/letter").getBody().get("signature"))).containsEntry("jpegBase64", again.get("jpegBase64"));

        // the Registrar removes it (ICT may not): the row and its trail stay, the version rises; the letter leaves the space for a
        // hand signature, the image is gone, and there is nothing left to remove
        assertThat(delete(ict, signatory).getStatusCode().value()).isEqualTo(403);
        ResponseEntity<Map> removed = delete(registrar, signatory);
        assertThat(removed.getStatusCode().value()).as(String.valueOf(removed.getBody())).isEqualTo(200);
        assertThat(removed.getBody()).containsEntry("hasSignature", false).containsEntry("version", v0 + 3).containsEntry("setOffice", "registrar")
                .doesNotContainKey("signatureUrl");
        assertThat(it.get(a.token(), "/api/v1/applicant/me/letter").getBody()).doesNotContainKey("signature");
        assertThat(it.get(studentToken, "/api/v1/me/admission-documents/letter").getBody()).doesNotContainKey("signature");
        assertThat(bytes(records, url).getStatusCode().value()).isEqualTo(404);
        assertThat(delete(registrar, signatory).getBody()).containsEntry("code", "SIGNATORY_SIGNATURE_NONE");
        assertThat(jdbc.sql("SELECT version FROM credentials.signatory_signature WHERE name_key = :k").param("k", key).query(Integer.class).single()).isEqualTo(v0 + 3);

        // the audit trail: the upload, the replacement and the removal, each under its office
        List<String> trail = jdbc.sql("""
                SELECT e.actor_office FROM audit.entries e
                 WHERE e.subject_type = 'credentials.signatory_signature' AND coalesce(e.after_state, e.before_state) ->> 'name_key' = :k AND e.occurred_at >= :f
                 ORDER BY e.occurred_at, e.seq
                """).param("k", key).param("f", from).query(String.class).list();
        assertThat(trail).containsExactly("dregistrar", "academic", "registrar");
    }
}
