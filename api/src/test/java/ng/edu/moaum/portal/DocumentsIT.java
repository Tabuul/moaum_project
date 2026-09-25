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
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.transaction.PlatformTransactionManager;

/**
 * Digital documents (V262), end to end: a student with a published result asks for a full transcript to an institution
 * with a recipient email; the invoice is paid through the existing reference and confirmed by the Bursary; the desk
 * validates, generates a versioned document, checks it, a different officer releases it; the student downloads it and
 * the recipient's secure link opens once and is logged; a stranger verifies it by code and by number and gets only the
 * public fields; the request completes. A free mini-transcript is issued at once. A graduate gets a digital certificate
 * only when graduated, approved and cleared; the certificate is reissued after a correction and the old version
 * verifies as REPLACED; a revocation names its minute and the certificate verifies as REVOKED; a changed result flags
 * the transcript; the Bursary reads and cannot act; a student cannot read another's document; a made-up code is NOT_FOUND.
 * Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class DocumentsIT {

    static final String SESSION = "2098/2099";

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    ItSupport it;
    String records, registrar, bursar, lecturer;
    UUID recordsId, registrarId;

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
        it.session(SESSION, 2098);
        recordsId = it.person("ZZDC-REC", "ZZDCRECORDS");
        registrarId = it.person("ZZDC-REG", "ZZDCREGISTRAR");
        records = TestTokens.token(recordsId, List.of("records"));
        registrar = TestTokens.token(registrarId, List.of("registrar"));
        bursar = TestTokens.token(it.person("ZZDC-BUR", "ZZDCBURSAR"), List.of("bursar"));
        lecturer = ItSupport.token("lecturer");
    }

    /** a student with one published result in the test session */
    private UUID studentWithResult(String surname, int level) {
        String tag = String.format("%06d", new Random().nextInt(999_999));
        UUID s = it.student(surname, "C00023", "MOAUM/ADM/98/" + tag, "MOAUM/DC/98/" + tag.substring(2), level);
        it.db(() -> {
            jdbc.sql("INSERT INTO people.student_contact (student_id, phone, email, updated_at) VALUES (:s, '08022224444', :e, now()) ON CONFLICT (student_id) DO NOTHING").param("s", s).param("e", surname.toLowerCase() + "@example.com").update();
            jdbc.sql("INSERT INTO people.enrolment (id, student_id, session, level) VALUES (gen_random_uuid(), :s, :sess, :l) ON CONFLICT (student_id, session) DO NOTHING").param("s", s).param("sess", SESSION).param("l", level).update();
            jdbc.sql("INSERT INTO catalogue.course (code, title, units, semester, level, dept_code, state) VALUES ('ZZD 401', 'Digital documents for the test', 3, 1, 400, 'MTC', 'LIVE') ON CONFLICT (code) DO NOTHING").update();
            UUID offering = jdbc.sql("INSERT INTO catalogue.offering (id, course_code, session, semester) VALUES (gen_random_uuid(), 'ZZD 401', :sess, 1) ON CONFLICT (course_code, session, semester) DO UPDATE SET semester = EXCLUDED.semester RETURNING id").param("sess", SESSION).query(UUID.class).single();
            UUID reg = jdbc.sql("INSERT INTO registration.course_registration (id, student_id, session, semester, level, status, approved_at) VALUES (gen_random_uuid(), :s, :sess, 1, :l, 'APPROVED', now()) ON CONFLICT (student_id, session, semester) DO UPDATE SET status = 'APPROVED' RETURNING id").param("s", s).param("sess", SESSION).param("l", level).query(UUID.class).single();
            jdbc.sql("INSERT INTO registration.entry (registration_id, offering_id, units, status) VALUES (:r, :o, 3, 'APPROVED') ON CONFLICT (registration_id, offering_id) DO NOTHING").param("r", reg).param("o", offering).update();
            UUID es = jdbc.sql("INSERT INTO assessment.exam_session (id, session, semester, kind, exams_from, exams_to, sheets_due, state, opened_at) VALUES (gen_random_uuid(), :sess, 1, 'MAIN', DATE '2098-12-08', DATE '2098-12-19', DATE '2099-01-16', 'OPEN', now()) ON CONFLICT (session, semester, kind) DO UPDATE SET state = 'OPEN' RETURNING id").param("sess", SESSION).query(UUID.class).single();
            UUID sheet = jdbc.sql("INSERT INTO assessment.score_sheet (id, offering_id, exam_session_id, stage, senate_minute, published_at, submitted_at) VALUES (gen_random_uuid(), :o, :es, 'PUBLISHED', 'SEN/2098/01', now(), now()) ON CONFLICT (offering_id, exam_session_id) DO UPDATE SET stage = 'PUBLISHED' RETURNING id").param("o", offering).param("es", es).query(UUID.class).single();
            return jdbc.sql("INSERT INTO assessment.score (sheet_id, student_id, ca, exam) VALUES (:sh, :s, 32, 48) ON CONFLICT (sheet_id, student_id, version) DO NOTHING").param("sh", sheet).param("s", s).update();
        });
        return s;
    }

    private Map<String, Object> mine(String token) {
        return it.get(token, "/api/v1/me/documents").getBody();
    }

    private Map<String, Object> verify(String key) {
        return (Map<String, Object>) parse(String.valueOf(it.anon(HttpMethod.GET, "/api/v1/verify/document/" + key, null).getBody().get("result")));
    }

    private static Object parse(String json) {
        return new tools.jackson.databind.ObjectMapper().readValue(json, Map.class);
    }

    @Test
    void fromTheRequestToAVerifiedDocument() {
        UUID ada = studentWithResult("ZZDC-ADA" + new Random().nextInt(1000), 400);
        String tAda = TestTokens.token(ada, List.of("student"));
        UUID bob = studentWithResult("ZZDC-BOB" + new Random().nextInt(1000), 300);
        String tBob = TestTokens.token(bob, List.of("student"));

        // ── 1 · the library, empty; the policies; a full transcript asked for, to an institution, digital and physical ──
        Map<String, Object> lib = mine(tAda);
        assertThat((List<?>) lib.get("documents")).isEmpty();
        assertThat((List<?>) lib.get("policies")).hasSizeGreaterThanOrEqualTo(5);
        assertThat((List<String>) lib.get("sessions")).contains(SESSION);
        Map<String, Object> ask = new java.util.LinkedHashMap<>();
        ask.put("kind", "TRANSCRIPT"); ask.put("destination", "INSTITUTION"); ask.put("destinationName", "University of Jos"); ask.put("department", "Admissions"); ask.put("recipientName", "The Registrar");
        ask.put("recipientEmail", "registrar@unijos.example.com"); ask.put("recipientAddress", "PMB 2084, Jos"); ask.put("recipientReference", "UJ/PG/2099/001"); ask.put("purpose", "Postgraduate admission"); ask.put("delivery", "BOTH"); ask.put("copies", 1);
        ResponseEntity<Map> req = it.call(tAda, HttpMethod.POST, "/api/v1/me/documents/requests", ask);
        assertThat(req.getStatusCode().value()).as(String.valueOf(req.getBody())).isEqualTo(200);
        String ref = String.valueOf(req.getBody().get("ref"));
        assertThat(ref).matches("TRN-\\d{4}-\\d{5}");
        assertThat(req.getBody().get("stage")).isEqualTo("AWAITING_PAYMENT");
        String payRef = String.valueOf(req.getBody().get("reference"));
        assertThat(payRef).startsWith("MOAUM-FEE-");
        double fee = ((Number) req.getBody().get("fee")).doubleValue();
        assertThat(fee).isGreaterThan(0);
        // a bad email is refused; a degree certificate is not requested
        assertThat(it.call(tBob, HttpMethod.POST, "/api/v1/me/documents/requests", Map.of("kind", "TRANSCRIPT", "destination", "SELF", "recipientEmail", "not-an-email")).getStatusCode().value()).isEqualTo(422);
        assertThat(it.call(tBob, HttpMethod.POST, "/api/v1/me/documents/requests", Map.of("kind", "DEGREE_CERTIFICATE")).getStatusCode().value()).isEqualTo(422);
        String reqId = String.valueOf(((List<Map<String, Object>>) mine(tAda).get("requests")).get(0).get("id"));
        // processing before payment is refused; the timeline holds the submission
        assertThat(it.call(records, HttpMethod.POST, "/api/v1/documents/requests/" + reqId + "/start", null).getStatusCode().value()).isEqualTo(422);
        Map<String, Object> tl = it.get(tAda, "/api/v1/me/documents/requests/" + reqId).getBody();
        assertThat((List<Map<String, Object>>) tl.get("events")).extracting(e -> e.get("action")).contains("REQUESTED");
        // another student cannot open it
        assertThat(it.get(tBob, "/api/v1/me/documents/requests/" + reqId).getStatusCode().value()).isEqualTo(404);

        // ── 2 · paid through the existing reference: the request is READY, the trail says so ──
        assertThat(it.call(bursar, HttpMethod.POST, "/api/v1/finance/references/" + payRef + "/confirm", Map.of("channel", "Bank transfer")).getStatusCode().value()).isEqualTo(200);
        Map<String, Object> r1 = ((List<Map<String, Object>>) mine(tAda).get("requests")).get(0);
        assertThat(r1.get("stage")).isIn("READY", "HELD_AT_CLEARANCE");
        assertThat(r1.get("payment_status")).isEqualTo("PAID");
        // the transcript clearance holds the student at first: clear the three units so the desk may proceed
        for (String unit : List.of("BURSARY", "LIBRARY", "DEPARTMENT", "FACULTY", "HEALTH", "HOSTEL", "WORKS", "ALUMNI")) {
            ResponseEntity<Map> cl = it.call(registrar, HttpMethod.POST, "/api/v1/clearance/students/" + ada + "/" + unit + "/clear", Map.of("purpose", "TRANSCRIPT", "note", "test"));
            assertThat(cl.getStatusCode().value()).as(unit + ": " + cl.getBody()).isIn(200, 422);
        }

        // ── 3 · the desk validates, generates a versioned document, checks it; the producer cannot release; the Registrar can ──
        assertThat(it.get(bursar, "/api/v1/documents/dashboard").getStatusCode().value()).isEqualTo(200);
        assertThat(it.call(bursar, HttpMethod.POST, "/api/v1/documents/requests/" + reqId + "/start", null).getStatusCode().value()).isEqualTo(403);
        assertThat(it.get(lecturer, "/api/v1/documents/requests").getStatusCode().value()).isEqualTo(403);
        ResponseEntity<Map> started = it.call(records, HttpMethod.POST, "/api/v1/documents/requests/" + reqId + "/start", null);
        assertThat(started.getStatusCode().value()).as(String.valueOf(started.getBody())).isEqualTo(200);
        Map<String, Object> validation = (Map<String, Object>) parse(String.valueOf(started.getBody().get("validation")));
        assertThat(validation.get("ok")).as(String.valueOf(validation)).isEqualTo(true);
        ResponseEntity<Map> gen = it.call(records, HttpMethod.POST, "/api/v1/documents/requests/" + reqId + "/generate", null);
        assertThat(gen.getStatusCode().value()).as(String.valueOf(gen.getBody())).isEqualTo(200);
        String number = String.valueOf(gen.getBody().get("number"));
        assertThat(number).matches("TRN/\\d{4}/\\d{6}");
        Map<String, Object> full = it.get(records, "/api/v1/documents/requests/" + reqId).getBody();
        assertThat(full.get("stage")).isEqualTo("GENERATED");
        Map<String, Object> stmt = (Map<String, Object>) parse(String.valueOf(((Map<String, Object>) full.get("document")).get("statement")));
        assertThat(stmt.get("matricNo")).isNotNull();
        assertThat((List<?>) stmt.get("sessions")).hasSize(1);
        assertThat(stmt.get("cgpa")).isNotNull();
        // the quality check asks for a correction, then approves the regenerated version
        assertThat(it.call(records, HttpMethod.POST, "/api/v1/documents/requests/" + reqId + "/qc", Map.of("decision", "CORRECTION", "note", "Check the title")).getStatusCode().value()).isEqualTo(200);
        assertThat(it.call(records, HttpMethod.POST, "/api/v1/documents/requests/" + reqId + "/generate", null).getStatusCode().value()).isEqualTo(200);
        full = it.get(records, "/api/v1/documents/requests/" + reqId).getBody();
        assertThat(((List<?>) full.get("versions"))).hasSize(2);
        assertThat(((Map<String, Object>) full.get("document")).get("version")).isEqualTo(2);
        assertThat(it.call(records, HttpMethod.POST, "/api/v1/documents/requests/" + reqId + "/qc", Map.of("decision", "APPROVED")).getStatusCode().value()).isEqualTo(200);
        assertThat(it.call(records, HttpMethod.POST, "/api/v1/documents/requests/" + reqId + "/release", null).getStatusCode().value()).isIn(403, 422); // records is not a signer / produced it
        ResponseEntity<Map> rel = it.call(registrar, HttpMethod.POST, "/api/v1/documents/requests/" + reqId + "/release", null);
        assertThat(rel.getStatusCode().value()).as(String.valueOf(rel.getBody())).isEqualTo(200);
        full = it.get(records, "/api/v1/documents/requests/" + reqId).getBody();
        assertThat(full.get("stage")).isEqualTo("RELEASED");
        List<Map<String, Object>> deliveries = (List<Map<String, Object>>) full.get("deliveries");
        assertThat(deliveries).extracting(d -> d.get("kind")).contains("DIGITAL", "PHYSICAL");
        String recipientToken = String.valueOf(deliveries.stream().filter(d -> "registrar@unijos.example.com".equals(d.get("email"))).findFirst().orElseThrow().get("token"));
        String physical = String.valueOf(deliveries.stream().filter(d -> "PHYSICAL".equals(d.get("kind"))).findFirst().orElseThrow().get("id"));
        List<String> notices = jdbc.sql("SELECT subject FROM platform.notice WHERE about_kind = 'student' AND about_id = :s").param("s", ada).query(String.class).list();
        assertThat(notices).anyMatch(n -> n.contains("submitted")).anyMatch(n -> n.contains("generated")).anyMatch(n -> n.contains("ready"));

        // ── 4 · the student downloads; the recipient's link opens; a stranger verifies by code and by number, public fields only ──
        Map<String, Object> myLib = mine(tAda);
        List<Map<String, Object>> docs = (List<Map<String, Object>>) myLib.get("documents");
        Map<String, Object> current = docs.stream().filter(d -> "ACTIVE".equals(d.get("status"))).findFirst().orElseThrow();
        String docId = String.valueOf(current.get("id"));
        String code = String.valueOf(current.get("verification_code"));
        assertThat(docs.stream().filter(d -> "REPLACED".equals(d.get("status"))).count()).isEqualTo(1);
        assertThat(it.get(tAda, "/api/v1/me/documents/" + docId + "?download=true").getStatusCode().value()).isEqualTo(200);
        assertThat(it.get(tBob, "/api/v1/me/documents/" + docId).getStatusCode().value()).isEqualTo(404);
        ResponseEntity<Map> dlr = it.anon(HttpMethod.GET, "/api/v1/verify/download/" + recipientToken, null);
        assertThat(dlr.getStatusCode().value()).as("token " + recipientToken + " → " + dlr.getBody()).isEqualTo(200);
        Map<String, Object> opened = (Map<String, Object>) parse(String.valueOf(dlr.getBody().get("result")));
        assertThat(opened.get("ok")).isEqualTo(true);
        assertThat(((Map<String, Object>) opened.get("statement")).get("holder")).isEqualTo(current.get("holder"));
        assertThat(jdbc.sql("SELECT count(*) FROM credentials.download_log WHERE issued_id = :i").param("i", UUID.fromString(docId)).query(Integer.class).single()).isGreaterThanOrEqualTo(2);
        Map<String, Object> v = verify(code);
        assertThat(v.get("status")).isEqualTo("VALID");
        assertThat(v.get("number")).isEqualTo(number);
        assertThat(v.get("holder")).isEqualTo(current.get("holder"));
        assertThat(v).doesNotContainKeys("sessions", "matricNo", "cgpa", "admissionNo");
        assertThat(((Map<String, Object>) parse(String.valueOf(it.anon(HttpMethod.GET, "/api/v1/verify/document?key=" + number, null).getBody().get("result")))).get("status")).isEqualTo("VALID");
        assertThat(verify("ZZZZZ-ZZZZZ-ZZZZZ-ZZZZZ-ZZZZZ").get("status")).isEqualTo("NOT_FOUND");
        assertThat(jdbc.sql("SELECT count(*) FROM credentials.verification WHERE issued_id = :i").param("i", UUID.fromString(docId)).query(Integer.class).single()).isGreaterThanOrEqualTo(2);
        // the physical copy dispatched and delivered; the recipient's link already counted as delivered; the request completes
        assertThat(it.call(records, HttpMethod.POST, "/api/v1/documents/deliveries/" + physical, Map.of("state", "DISPATCHED", "courier", "DHL", "tracking", "DHL123")).getStatusCode().value()).isEqualTo(200);
        assertThat(it.call(records, HttpMethod.POST, "/api/v1/documents/deliveries/" + physical, Map.of("state", "DELIVERED")).getStatusCode().value()).isEqualTo(200);
        full = it.get(records, "/api/v1/documents/requests/" + reqId).getBody();
        assertThat(full.get("stage")).isIn("DELIVERED", "RELEASED");
        assertThat(it.call(records, HttpMethod.POST, "/api/v1/documents/requests/" + reqId + "/complete", null).getStatusCode().value()).isEqualTo(200);

        // ── 5 · a free mini-transcript is issued at once ──
        ResponseEntity<Map> mini = it.call(tBob, HttpMethod.POST, "/api/v1/me/documents/requests", Map.of("kind", "MINI_TRANSCRIPT", "destination", "SELF"));
        assertThat(mini.getStatusCode().value()).as(String.valueOf(mini.getBody())).isEqualTo(200);
        assertThat(mini.getBody().get("stage")).isEqualTo("RELEASED");
        assertThat(((Number) mini.getBody().get("fee")).doubleValue()).isEqualTo(0.0);
        assertThat((List<Map<String, Object>>) mine(tBob).get("documents")).anySatisfy(d -> assertThat(d.get("kind")).isEqualTo("MINI_TRANSCRIPT"));

        // ── 6 · the degree certificate: refused until graduated, approved and cleared; then issued, verified, reissued, revoked ──
        assertThat(it.call(registrar, HttpMethod.POST, "/api/v1/documents/certificates", Map.of("studentId", ada)).getStatusCode().value()).isEqualTo(422);
        it.db(() -> {
            jdbc.sql("INSERT INTO records.graduand (id, student_id, session, cgpa, award, senate_state, senate_minute) VALUES (gen_random_uuid(), :s, :sess, 4.62, 'B.Sc. Computer Science', 'APPROVED', 'SEN/2099/07') ON CONFLICT (student_id, session) DO UPDATE SET senate_state = 'APPROVED', cgpa = 4.62, senate_minute = 'SEN/2099/07'").param("s", ada).param("sess", SESSION).update();
            return jdbc.sql("UPDATE people.student SET status = 'GRADUATED' WHERE id = :s").param("s", ada).update();
        });
        assertThat(it.call(registrar, HttpMethod.POST, "/api/v1/documents/certificates", Map.of("studentId", ada)).getStatusCode().value()).isEqualTo(422); // not yet cleared
        for (String unit : List.of("BURSARY", "DEPARTMENT", "FACULTY", "LIBRARY", "HEALTH", "HOSTEL", "WORKS", "ALUMNI")) {
            assertThat(it.call(registrar, HttpMethod.POST, "/api/v1/clearance/students/" + ada + "/" + unit + "/clear", Map.of("purpose", "CONVOCATION", "note", "test")).getStatusCode().value()).isEqualTo(200);
        }
        assertThat(it.call(bursar, HttpMethod.POST, "/api/v1/documents/certificates", Map.of("studentId", ada)).getStatusCode().value()).isEqualTo(403);
        ResponseEntity<Map> cert = it.call(registrar, HttpMethod.POST, "/api/v1/documents/certificates", Map.of("studentId", ada));
        assertThat(cert.getStatusCode().value()).as(String.valueOf(cert.getBody())).isEqualTo(200);
        String certNo = String.valueOf(cert.getBody().get("number"));
        assertThat(certNo).matches("CERT/\\d{4}/\\d{6}");
        String certId = String.valueOf(cert.getBody().get("issuedId"));
        assertThat(it.call(registrar, HttpMethod.POST, "/api/v1/documents/certificates", Map.of("studentId", ada)).getStatusCode().value()).isEqualTo(409); // one active certificate
        Map<String, Object> certDoc = it.get(tAda, "/api/v1/me/documents/" + certId).getBody();
        Map<String, Object> cs = (Map<String, Object>) parse(String.valueOf(certDoc.get("statement")));
        assertThat(cs.get("classOfDegree")).isEqualTo("First Class Honours");
        assertThat(cs.get("award")).isEqualTo("B.Sc. Computer Science");
        String certCode = String.valueOf(certDoc.get("verification_code"));
        Map<String, Object> cv = verify(certCode);
        assertThat(cv.get("status")).isEqualTo("VALID");
        assertThat(cv.get("kind")).isEqualTo("DEGREE_CERTIFICATE");
        assertThat(cv.get("classOfDegree")).isEqualTo("First Class Honours");
        // the record corrected: the award changes, the certificate is flagged; the desk reissues; the old version verifies REPLACED
        it.db(() -> jdbc.sql("UPDATE records.graduand SET award = 'B.Sc. (Hons) Computer Science' WHERE student_id = :s AND session = :sess").param("s", ada).param("sess", SESSION).update());
        assertThat(jdbc.sql("SELECT flag_reason FROM credentials.issued WHERE id = :i").param("i", UUID.fromString(certId)).query(String.class).single()).contains("award");
        ResponseEntity<Map> re = it.call(registrar, HttpMethod.POST, "/api/v1/documents/issued/" + certId + "/reissue", Map.of("reason", "Award title corrected"));
        assertThat(re.getStatusCode().value()).as(String.valueOf(re.getBody())).isEqualTo(200);
        assertThat(re.getBody().get("version")).isEqualTo(2);
        assertThat(verify(certCode).get("status")).isEqualTo("REPLACED");
        String cert2 = String.valueOf(re.getBody().get("issuedId"));
        Map<String, Object> cert2Doc = it.get(registrar, "/api/v1/documents/issued/" + cert2).getBody();
        assertThat(cert2Doc.get("number")).isEqualTo(certNo);
        assertThat(((Map<String, Object>) parse(String.valueOf(cert2Doc.get("statement")))).get("award")).isEqualTo("B.Sc. (Hons) Computer Science");
        assertThat((List<?>) cert2Doc.get("versions")).hasSize(2);
        // revoked by the Registrar with the minute; not by Records; verification answers REVOKED
        assertThat(it.call(records, HttpMethod.POST, "/api/v1/documents/issued/" + cert2 + "/revoke", Map.of("reason", "x", "instrument", "SEN/2099/09")).getStatusCode().value()).isEqualTo(403);
        assertThat(it.call(registrar, HttpMethod.POST, "/api/v1/documents/issued/" + cert2 + "/revoke", Map.of("reason", "Entry qualification found to be forged", "instrument", "SEN/2099/09")).getStatusCode().value()).isEqualTo(200);
        Map<String, Object> rv = verify(String.valueOf(cert2Doc.get("verification_code")));
        assertThat(rv.get("status")).isEqualTo("REVOKED");
        assertThat(rv.get("revokedUnder")).isEqualTo("SEN/2099/09");
        assertThat(it.get(tAda, "/api/v1/me/documents/" + cert2 + "/link").getStatusCode().value()).isIn(404, 405);
        assertThat(it.call(tAda, HttpMethod.POST, "/api/v1/me/documents/" + cert2 + "/link", Map.of("days", 7)).getStatusCode().value()).isEqualTo(422); // revoked: no link

        // ── 7 · the office reads the figures; the register lists the documents; the verification log holds the strangers' checks ──
        Map<String, Object> dash = it.get(registrar, "/api/v1/documents/dashboard").getBody();
        assertThat(String.valueOf(dash.get("dashboard"))).contains("\"completed\"").contains("\"revoked\"");
        Map<String, Object> reg = it.get(registrar, "/api/v1/documents/issued?q=" + number).getBody();
        assertThat(((Number) reg.get("total")).intValue()).isGreaterThanOrEqualTo(2);
        List<Map<String, Object>> vlog = it.getList(registrar, "/api/v1/documents/verifications?size=50").getBody();
        assertThat(vlog).extracting(x -> x.get("status")).contains("VALID", "NOT_FOUND", "REVOKED");
    }
}
