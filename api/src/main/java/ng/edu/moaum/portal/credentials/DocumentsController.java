package ng.edu.moaum.portal.credentials;

import java.math.BigDecimal;
import java.sql.Types;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;

import jakarta.servlet.http.HttpServletRequest;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

import ng.edu.moaum.portal.shared.DomainRuleViolation;
import ng.edu.moaum.portal.shared.NotFound;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.Authentication;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * Digital academic documents (V262): the student's library and requests; the documents office — the queue, the
 * validation, the generation, the quality check, the release, the deliveries, the register of issued documents
 * with revocation and reissue, the policies and templates, the reports; and the public verification door,
 * rate-limited by source. The rules are the database's; this is the door.
 */
@RestController
class DocumentsController {

    private static final String STUDENT = "hasAuthority('OFFICE_student')";
    private static final String READERS = "hasAnyAuthority('OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar','OFFICE_records','OFFICE_dvc','OFFICE_vc','OFFICE_bursar','OFFICE_ict','OFFICE_admin','OFFICE_super','OFFICE_audit')";
    private static final String OFFICE = "hasAnyAuthority('OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar','OFFICE_records')";
    private static final String SIGNERS = "hasAnyAuthority('OFFICE_registrar','OFFICE_dregistrar','OFFICE_academic')";
    private static final String REVOKERS = "hasAnyAuthority('OFFICE_registrar','OFFICE_vc')";
    private static final String CONFIG = "hasAnyAuthority('OFFICE_registrar','OFFICE_dregistrar','OFFICE_academic','OFFICE_super')";
    private static final Set<String> KINDS = Set.of("DEGREE_CERTIFICATE", "TRANSCRIPT", "SESSIONAL_TRANSCRIPT", "MINI_TRANSCRIPT", "ACADEMIC_STATEMENT");
    private static final int VERIFY_LIMIT = 40;
    private static final long VERIFY_WINDOW_MS = 15 * 60_000L;

    private final JdbcClient jdbc;
    private final ConcurrentHashMap<String, long[]> hits = new ConcurrentHashMap<>();

    DocumentsController(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    private static UUID student(Authentication auth) {
        return UUID.fromString(auth.getName());
    }

    private static String blank(String v) {
        return v == null || v.isBlank() ? null : v.trim();
    }

    private static String ip(HttpServletRequest req) {
        String f = req.getHeader("X-Forwarded-For");
        String ip = f == null || f.isBlank() ? req.getRemoteAddr() : f.split(",")[0].trim();
        return ip == null ? null : ip.substring(0, Math.min(ip.length(), 60));
    }

    private static String agent(HttpServletRequest req) {
        String a = req.getHeader("User-Agent");
        return a == null ? null : a.substring(0, Math.min(a.length(), 200));
    }

    /** a stranger's verifications are counted by source: past the limit in the window, the door answers slowly-please */
    private void throttle(String source) {
        long now = System.currentTimeMillis();
        long[] w = hits.compute(source == null ? "?" : source, (k, v) -> {
            if (v == null || now - v[0] > VERIFY_WINDOW_MS) return new long[] {now, 1};
            v[1]++;
            return v;
        });
        if (w[1] > VERIFY_LIMIT) {
            throw new DomainRuleViolation("VERIFY_THROTTLED", "Too many verifications from this source; try again in a few minutes.",
                    new DomainRuleViolation.Remedy("The verification page answers a handful of documents at a time, not a list.", "The Registry"));
        }
        if (hits.size() > 20_000) hits.clear();
    }

    /* ── the student ─────────────────────────────────────────────────────── */

    @GetMapping("/api/v1/me/documents")
    @PreAuthorize(STUDENT)
    @Transactional(readOnly = true)
    Map<String, Object> mine(Authentication auth) {
        UUID me = student(auth);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("documents", jdbc.sql("SELECT * FROM credentials.document_rows() WHERE student_id = :s ORDER BY issued_at DESC").param("s", me).query().listOfRows());
        out.put("requests", jdbc.sql("SELECT * FROM credentials.request_rows(NULL) WHERE student_id = :s ORDER BY requested_at DESC").param("s", me).query().listOfRows());
        out.put("policies", jdbc.sql("""
                SELECT p.*, credentials.fee_for(p.kind, (SELECT name FROM policy.academic_session WHERE state = 'CURRENT'), 'DIGITAL', false, false, 1) AS fee_now,
                       credentials.fee_for(p.kind, (SELECT name FROM policy.academic_session WHERE state = 'CURRENT'), 'PHYSICAL', false, false, 1) - credentials.fee_for(p.kind, (SELECT name FROM policy.academic_session WHERE state = 'CURRENT'), 'DIGITAL', false, false, 1) AS physical_extra
                  FROM credentials.document_policy p WHERE p.active ORDER BY p.kind
                """).query().listOfRows());
        out.put("sessions", jdbc.sql("""
                SELECT DISTINCT r.session FROM assessment.student_results(:s) r WHERE r.published
                UNION SELECT DISTINCT r.session FROM admissions.pg_registration r JOIN admissions.pg_registration_entry e ON e.registration_id = r.id JOIN admissions.pg_score sc ON sc.entry_id = e.id WHERE r.student_id = :s
                ORDER BY 1 DESC
                """).param("s", me).query(String.class).list());
        out.put("student", jdbc.sql("""
                SELECT st.surname || ', ' || st.other_names AS name, coalesce(st.matric_no, st.admission_no) AS number, st.status, st.current_level AS level, st.entry_mode, p.name AS programme, d.name AS department, f.name AS faculty,
                       (SELECT g.senate_state FROM records.graduand g WHERE g.student_id = st.id ORDER BY g.session DESC LIMIT 1) AS senate_state
                  FROM people.student st LEFT JOIN ref.programme p ON p.code = st.programme_code LEFT JOIN ref.department d ON d.code = p.dept_code LEFT JOIN ref.faculty f ON f.code = p.faculty_code WHERE st.id = :s
                """).param("s", me).query().singleRow());
        out.put("counts", jdbc.sql("""
                SELECT count(*) FILTER (WHERE i.kind = 'DEGREE_CERTIFICATE' AND credentials.document_status(i.id) = 'ACTIVE') AS certificates,
                       count(*) FILTER (WHERE i.kind <> 'DEGREE_CERTIFICATE' AND credentials.document_status(i.id) = 'ACTIVE') AS transcripts,
                       (SELECT count(*) FROM credentials.transcript_request t WHERE t.student_id = :s AND t.stage NOT IN ('COMPLETED','REJECTED','CANCELLED','DELIVERED')) AS pending,
                       count(*) FILTER (WHERE credentials.document_status(i.id) = 'ACTIVE') AS downloads
                  FROM credentials.issued i WHERE i.student_id = :s
                """).param("s", me).query().singleRow());
        return out;
    }

    public record RequestIn(@NotBlank String kind, String session, Integer semester, String destination, @Size(max = 200) String destinationName, @Size(max = 200) String department,
                            @Size(max = 160) String recipientName, @Size(max = 200) String recipientEmail, @Size(max = 600) String recipientAddress, @Size(max = 120) String recipientReference,
                            @Size(max = 400) String purpose, String delivery, Boolean express, Boolean international, Integer copies) {
    }

    @PostMapping("/api/v1/me/documents/requests")
    @PreAuthorize(STUDENT)
    @Transactional
    Map<String, Object> request(Authentication auth, @Valid @RequestBody RequestIn body) {
        String kind = body.kind().trim().toUpperCase();
        if (!KINDS.contains(kind)) throw new DomainRuleViolation("DOC_KIND", "'" + kind + "' is not a document kind.", new DomainRuleViolation.Remedy("Full, sessional or mini transcript, or a statement of record.", "You"));
        if (kind.equals("DEGREE_CERTIFICATE")) throw new DomainRuleViolation("DOC_KIND", "A degree certificate is issued by the Registry, not requested.", new DomainRuleViolation.Remedy("It appears under My Documents once issued.", "The Registry"));
        return jdbc.sql("SELECT * FROM credentials.request_document(:s, :k, :ses, :sem, :d, :dn, :dep, :rn, :re, :ra, :rr, :p, :dl, :ex, :intl, :c)")
                .param("s", student(auth)).param("k", kind).param("ses", blank(body.session()), Types.VARCHAR).param("sem", body.semester(), Types.INTEGER)
                .param("d", blank(body.destination()) == null ? "SELF" : body.destination().trim().toUpperCase()).param("dn", blank(body.destinationName()), Types.VARCHAR).param("dep", blank(body.department()), Types.VARCHAR)
                .param("rn", blank(body.recipientName()), Types.VARCHAR).param("re", blank(body.recipientEmail()), Types.VARCHAR).param("ra", blank(body.recipientAddress()), Types.VARCHAR).param("rr", blank(body.recipientReference()), Types.VARCHAR)
                .param("p", blank(body.purpose()), Types.VARCHAR).param("dl", blank(body.delivery()) == null ? "DIGITAL" : body.delivery().trim().toUpperCase())
                .param("ex", body.express() != null && body.express()).param("intl", body.international() != null && body.international()).param("c", body.copies() == null ? 1 : body.copies())
                .query().singleRow();
    }

    @GetMapping("/api/v1/me/documents/requests/{id}")
    @PreAuthorize(STUDENT)
    @Transactional(readOnly = true)
    Map<String, Object> myRequest(Authentication auth, @PathVariable UUID id) {
        Map<String, Object> r = jdbc.sql("SELECT * FROM credentials.request_rows(NULL) WHERE id = :id AND student_id = :s").param("id", id).param("s", student(auth)).query().listOfRows().stream().findFirst()
                .orElseThrow(() -> new NotFound("request", id));
        Map<String, Object> out = new LinkedHashMap<>(r);
        out.put("events", jdbc.sql("SELECT action, from_state, to_state, note, at FROM credentials.event WHERE request_id = :id ORDER BY at").param("id", id).query().listOfRows());
        out.put("deliveries", jdbc.sql("SELECT id, kind, state, recipient, email, courier, tracking_no, dispatched_on, delivered_on, note, updated_at FROM credentials.delivery WHERE request_id = :id ORDER BY created_at").param("id", id).query().listOfRows());
        return out;
    }

    public record ReasonIn(@Size(max = 600) String reason) {
    }

    @PostMapping("/api/v1/me/documents/requests/{id}/cancel")
    @PreAuthorize(STUDENT)
    @Transactional
    Map<String, Object> cancelMine(Authentication auth, @PathVariable UUID id, @RequestBody(required = false) ReasonIn body) {
        jdbc.sql("SELECT credentials.cancel_request(:id, :s, :r)").param("id", id).param("s", student(auth)).param("r", body == null ? null : blank(body.reason()), Types.VARCHAR).query().listOfRows();
        return Map.of("ok", true);
    }

    /** the student's own document, statement and all, for the portal's PDF; the download is logged */
    @GetMapping("/api/v1/me/documents/{id}")
    @PreAuthorize(STUDENT)
    @Transactional
    Map<String, Object> myDocument(Authentication auth, @PathVariable UUID id, HttpServletRequest req, @RequestParam(defaultValue = "false") boolean download) {
        UUID me = student(auth);
        Map<String, Object> d = document(id);
        if (!me.equals(d.get("student_id"))) throw new NotFound("document", id);
        if (download) jdbc.sql("SELECT credentials.record_download(:i, :a, 'STUDENT', :ip, :ua)").param("i", id).param("a", me).param("ip", ip(req), Types.VARCHAR).param("ua", agent(req), Types.VARCHAR).query().listOfRows();
        return d;
    }

    private Map<String, Object> document(UUID id) {
        Map<String, Object> d = jdbc.sql("SELECT * FROM credentials.document_rows() WHERE id = :id").param("id", id).query().listOfRows().stream().findFirst().orElseThrow(() -> new NotFound("document", id));
        Map<String, Object> out = new LinkedHashMap<>(d);
        out.put("statement", jdbc.sql("SELECT statement::text FROM credentials.issued WHERE id = :id").param("id", id).query(String.class).single());
        out.put("template", jdbc.sql("SELECT * FROM credentials.document_template WHERE kind = :k AND version = coalesce(:v, (SELECT max(version) FROM credentials.document_template WHERE kind = :k))")
                .param("k", d.get("kind")).param("v", d.get("template_version"), Types.INTEGER).query().listOfRows().stream().findFirst().orElse(null));
        return out;
    }

    public record LinkIn(Integer days) {
    }

    @PostMapping("/api/v1/me/documents/{id}/link")
    @PreAuthorize(STUDENT)
    @Transactional
    Map<String, Object> myLink(Authentication auth, @PathVariable UUID id, @RequestBody(required = false) LinkIn body) {
        String t = jdbc.sql("SELECT credentials.new_download_token(:i, :s, :d)").param("i", id).param("s", student(auth)).param("d", body == null ? 7 : body.days(), Types.INTEGER).query(String.class).single();
        return Map.of("token", t, "path", "/documents/d/" + t);
    }

    /* ── the public doors: verification and a recipient's secure link ────── */

    /** a document number carries slashes, which a path will not take; the typed form comes as a query, the QR's code as a path */
    @GetMapping("/api/v1/verify/document")
    @Transactional
    Map<String, Object> verifyByQuery(@RequestParam String key, HttpServletRequest req) {
        return verify(key, req);
    }

    @GetMapping("/api/v1/verify/document/{key}")
    @Transactional
    Map<String, Object> verify(@PathVariable String key, HttpServletRequest req) {
        throttle(ip(req));
        String json = jdbc.sql("SELECT credentials.verify_document(:k, :ip, :ua)::text").param("k", key).param("ip", ip(req), Types.VARCHAR).param("ua", agent(req), Types.VARCHAR).query(String.class).single();
        return Map.of("result", json);
    }

    @GetMapping("/api/v1/verify/download/{token}")
    @Transactional
    Map<String, Object> download(@PathVariable String token, HttpServletRequest req) {
        throttle(ip(req));
        String t = token == null ? "" : token.trim().toLowerCase().replaceAll("[^a-f0-9]", "");
        String json = jdbc.sql("SELECT credentials.consume_token(:t, :ip, :ua)::text").param("t", t).param("ip", ip(req), Types.VARCHAR).param("ua", agent(req), Types.VARCHAR).query(String.class).single();
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("result", json);
        out.put("template", jdbc.sql("""
                SELECT row_to_json(x)::text FROM (SELECT tp.* FROM credentials.document_template tp JOIN credentials.download_token dt ON dt.token = :t JOIN credentials.issued i ON i.id = dt.issued_id
                  WHERE tp.kind = i.kind AND tp.version = coalesce(i.template_version, (SELECT max(version) FROM credentials.document_template WHERE kind = i.kind))) x
                """).param("t", t).query(String.class).optional().orElse(null));
        return out;
    }

    /* ── the documents office ────────────────────────────────────────────── */

    @GetMapping("/api/v1/documents/dashboard")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> dashboard() {
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("dashboard", jdbc.sql("SELECT credentials.office_dashboard()::text").query(String.class).single());
        out.put("policies", jdbc.sql("SELECT * FROM credentials.document_policy ORDER BY kind").query().listOfRows());
        out.put("flagged", jdbc.sql("SELECT * FROM credentials.document_rows() WHERE flagged_at IS NOT NULL AND status = 'ACTIVE' ORDER BY flagged_at DESC LIMIT 100").query().listOfRows());
        out.put("suspected", jdbc.sql("SELECT * FROM credentials.suspected_forgeries()").query().listOfRows());
        out.put("awaitingCertificate", jdbc.sql("""
                SELECT s.id AS student_id, s.surname || ', ' || s.other_names AS student_name, coalesce(s.matric_no, s.admission_no) AS student_number, g.session, g.award, g.cgpa, coalesce(policy.class_of(g.cgpa), 'Pass') AS class_of_degree,
                       clearance.is_clear(s.id, 'CONVOCATION') AS cleared, p.name AS programme
                  FROM records.graduand g JOIN people.student s ON s.id = g.student_id LEFT JOIN ref.programme p ON p.code = s.programme_code
                 WHERE g.senate_state = 'APPROVED' AND s.status = 'GRADUATED'
                   AND NOT EXISTS (SELECT 1 FROM credentials.issued x WHERE x.student_id = g.student_id AND x.kind = 'DEGREE_CERTIFICATE' AND credentials.document_status(x.id) = 'ACTIVE')
                 ORDER BY s.surname, s.other_names LIMIT 500
                """).query().listOfRows());
        return out;
    }

    @GetMapping("/api/v1/documents/requests")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> requests(@RequestParam(required = false) String stage, @RequestParam(required = false) String kind, @RequestParam(required = false) String payment, @RequestParam(required = false) String delivery,
                                 @RequestParam(required = false) String fac, @RequestParam(required = false) String dept, @RequestParam(required = false) String prog, @RequestParam(required = false) String session,
                                 @RequestParam(required = false) String q, @RequestParam(defaultValue = "0") int page, @RequestParam(defaultValue = "200") int size) {
        String st = blank(stage) == null ? null : stage.trim().toUpperCase();
        String pred = st == null ? "" : switch (st) {
            case "NEW" -> " AND r.stage IN ('READY','HELD_AT_CLEARANCE') AND r.started_at IS NULL";
            case "OPEN" -> " AND r.stage NOT IN ('COMPLETED','REJECTED','CANCELLED')";
            case "PROCESSING" -> " AND r.stage IN ('PROCESSING','CORRECTION')";
            case "QUALITY_CHECK" -> " AND r.stage = 'GENERATED'";
            case "BREACHING" -> " AND r.breaching";
            default -> " AND r.stage = :st";
        };
        String needle = blank(q) == null ? null : "%" + q.trim().toLowerCase() + "%";
        int sz = Math.max(1, Math.min(size, 2000)), pg = Math.max(0, page);
        JdbcClient.StatementSpec spec = jdbc.sql("""
                SELECT count(*) OVER () AS total_rows, r.* FROM credentials.request_rows(NULL) r
                 WHERE (:k::text IS NULL OR r.kind = :k) AND (:pay::text IS NULL OR r.payment_status = :pay) AND (:dl::text IS NULL OR r.delivery = :dl)
                   AND (:fac::text IS NULL OR r.faculty_code = :fac) AND (:dept::text IS NULL OR r.dept_code = :dept) AND (:prog::text IS NULL OR r.programme_code = :prog) AND (:ses::text IS NULL OR r.session = :ses)
                   AND (:q::text IS NULL OR lower(r.student_name) LIKE :q OR lower(r.student_number) LIKE :q OR lower(r.ref) LIKE :q OR lower(coalesce(r.document_number, '')) LIKE :q OR lower(coalesce(r.verification_code, '')) LIKE :q)
                """ + pred + " ORDER BY r.student_name, r.requested_at DESC LIMIT :n OFFSET :o")
                .param("k", blank(kind) == null ? null : kind.trim().toUpperCase(), Types.VARCHAR).param("pay", blank(payment) == null ? null : payment.trim().toUpperCase(), Types.VARCHAR).param("dl", blank(delivery) == null ? null : delivery.trim().toUpperCase(), Types.VARCHAR)
                .param("fac", blank(fac), Types.VARCHAR).param("dept", blank(dept), Types.VARCHAR).param("prog", blank(prog), Types.VARCHAR).param("ses", blank(session), Types.VARCHAR).param("q", needle, Types.VARCHAR).param("n", sz).param("o", pg * sz);
        if (pred.contains(":st")) spec = spec.param("st", st);
        List<Map<String, Object>> rows = spec.query().listOfRows();
        long total = rows.isEmpty() ? 0 : ((Number) rows.get(0).get("total_rows")).longValue();
        rows.forEach(r -> r.remove("total_rows"));
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("total", total); out.put("page", pg); out.put("size", sz); out.put("rows", rows);
        out.put("options", jdbc.sql("SELECT DISTINCT faculty_code, faculty, dept_code, department, programme_code, programme FROM credentials.request_rows(NULL) WHERE programme_code IS NOT NULL ORDER BY faculty, department, programme").query().listOfRows());
        return out;
    }

    @GetMapping("/api/v1/documents/requests/{id}")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> request(@PathVariable UUID id) {
        Map<String, Object> r = jdbc.sql("SELECT * FROM credentials.request_rows(NULL) WHERE id = :id").param("id", id).query().listOfRows().stream().findFirst().orElseThrow(() -> new NotFound("request", id));
        Map<String, Object> out = new LinkedHashMap<>(r);
        Map<String, Object> full = jdbc.sql("SELECT recipient_department, recipient_name, recipient_address, recipient_reference, purpose, international, validation::text AS validation, qc_note, produced_by, released_by, qc_by FROM credentials.transcript_request WHERE id = :id").param("id", id).query().singleRow();
        out.putAll(full);
        out.put("events", jdbc.sql("SELECT e.action, e.from_state, e.to_state, e.note, e.actor_office, e.at, pe.surname || ', ' || pe.given_names AS actor FROM credentials.event e LEFT JOIN iam.person pe ON pe.id = e.actor_id WHERE e.request_id = :id ORDER BY e.at").param("id", id).query().listOfRows());
        out.put("deliveries", jdbc.sql("SELECT d.*, dt.token, dt.expires_at, dt.uses, dt.max_uses FROM credentials.delivery d LEFT JOIN credentials.download_token dt ON dt.id = d.token_id WHERE d.request_id = :id ORDER BY d.created_at").param("id", id).query().listOfRows());
        out.put("preview", jdbc.sql("SELECT credentials.build_statement(:s, :k, :ses, :sem)::text").param("s", r.get("student_id")).param("k", r.get("kind")).param("ses", r.get("session"), Types.VARCHAR).param("sem", r.get("semester"), Types.INTEGER).query(String.class).single());
        if (r.get("issued_id") != null) out.put("document", document((UUID) r.get("issued_id")));
        out.put("versions", jdbc.sql("SELECT id, number, version, verification_code, issued_on, credentials.document_status(id) AS status FROM credentials.issued WHERE request_id = :id ORDER BY version").param("id", id).query().listOfRows());
        return out;
    }

    @PostMapping("/api/v1/documents/requests/{id}/start")
    @PreAuthorize(OFFICE)
    @Transactional
    Map<String, Object> start(@PathVariable UUID id) {
        return Map.of("validation", jdbc.sql("SELECT credentials.start_processing(:id)::text").param("id", id).query(String.class).single());
    }

    @PostMapping("/api/v1/documents/requests/{id}/generate")
    @PreAuthorize(OFFICE)
    @Transactional
    Map<String, Object> generate(@PathVariable UUID id) {
        UUID i = jdbc.sql("SELECT credentials.produce_transcript(:id)").param("id", id).query(UUID.class).single();
        return Map.of("issuedId", i, "number", jdbc.sql("SELECT number FROM credentials.issued WHERE id = :i").param("i", i).query(String.class).single());
    }

    public record QcIn(@NotBlank String decision, @Size(max = 800) String note) {
    }

    @PostMapping("/api/v1/documents/requests/{id}/qc")
    @PreAuthorize(OFFICE)
    @Transactional
    Map<String, Object> qc(@PathVariable UUID id, @Valid @RequestBody QcIn body) {
        jdbc.sql("SELECT credentials.qc_transcript(:id, :d, :n)").param("id", id).param("d", body.decision().trim().toUpperCase()).param("n", blank(body.note()), Types.VARCHAR).query().listOfRows();
        return Map.of("ok", true);
    }

    @PostMapping("/api/v1/documents/requests/{id}/release")
    @PreAuthorize(SIGNERS)
    @Transactional
    Map<String, Object> release(@PathVariable UUID id) {
        jdbc.sql("SELECT credentials.release_transcript(:id)").param("id", id).query().listOfRows();
        return Map.of("ok", true);
    }

    @PostMapping("/api/v1/documents/requests/{id}/cancel")
    @PreAuthorize(OFFICE)
    @Transactional
    Map<String, Object> cancel(@PathVariable UUID id, @RequestBody(required = false) ReasonIn body) {
        jdbc.sql("SELECT credentials.cancel_request(:id, NULL, :r)").param("id", id).param("r", body == null ? "Cancelled by the desk" : blank(body.reason()), Types.VARCHAR).query().listOfRows();
        return Map.of("ok", true);
    }

    @PostMapping("/api/v1/documents/requests/{id}/complete")
    @PreAuthorize(OFFICE)
    @Transactional
    Map<String, Object> complete(@PathVariable UUID id, @RequestBody(required = false) ReasonIn body) {
        jdbc.sql("SELECT credentials.complete_request(:id, :n)").param("id", id).param("n", body == null ? null : blank(body.reason()), Types.VARCHAR).query().listOfRows();
        return Map.of("ok", true);
    }

    public record DeliveryIn(@NotBlank String state, @Size(max = 120) String courier, @Size(max = 120) String tracking, @Size(max = 400) String note) {
    }

    @PostMapping("/api/v1/documents/deliveries/{id}")
    @PreAuthorize(OFFICE)
    @Transactional
    Map<String, Object> delivery(@PathVariable UUID id, @Valid @RequestBody DeliveryIn body) {
        jdbc.sql("SELECT credentials.mark_delivery(:id, :s, :c, :t, :n)").param("id", id).param("s", body.state().trim().toUpperCase()).param("c", blank(body.courier()), Types.VARCHAR).param("t", blank(body.tracking()), Types.VARCHAR).param("n", blank(body.note()), Types.VARCHAR).query().listOfRows();
        return Map.of("ok", true);
    }

    @PostMapping("/api/v1/documents/deliveries/{id}/resend")
    @PreAuthorize(OFFICE)
    @Transactional
    Map<String, Object> resend(@PathVariable UUID id) {
        Map<String, Object> d = jdbc.sql("SELECT d.*, t.recipient_email FROM credentials.delivery d JOIN credentials.transcript_request t ON t.id = d.request_id WHERE d.id = :id").param("id", id).query().listOfRows().stream().findFirst().orElseThrow(() -> new NotFound("delivery", id));
        if (!"DIGITAL".equals(d.get("kind")) || d.get("email") == null) throw new DomainRuleViolation("DOC_RESEND", "Only a digital delivery to an email address is resent.", new DomainRuleViolation.Remedy("Record a physical delivery's dispatch instead.", "Exams and Records"));
        String token = jdbc.sql("INSERT INTO credentials.download_token (issued_id, for_kind, email, expires_at, max_uses) VALUES (:i, 'RECIPIENT', :e, now() + interval '30 days', 10) RETURNING token").param("i", d.get("issued_id")).param("e", d.get("email")).query(String.class).single();
        jdbc.sql("UPDATE credentials.delivery SET token_id = (SELECT id FROM credentials.download_token WHERE token = :t), state = 'RESENT', updated_at = now() WHERE id = :id").param("t", token).param("id", id).update();
        jdbc.sql("SELECT platform.queue_notice('EMAIL', :e, 'An official document from Rev. Fr. Moses Orshio Adasu University (resent)', :b, 'document', :i)")
                .param("e", d.get("email")).param("b", "A fresh secure link to the official document: open the portal under /documents/d/" + token + " — it expires in 30 days.").param("i", d.get("issued_id")).query().listOfRows();
        jdbc.sql("SELECT credentials.mark_delivery(:id, 'RESENT', NULL, NULL, 'Link resent')").param("id", id).query().listOfRows();
        return Map.of("ok", true);
    }

    /* ── the register of issued documents ────────────────────────────────── */

    @GetMapping("/api/v1/documents/issued")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> issued(@RequestParam(required = false) String kind, @RequestParam(required = false) String status, @RequestParam(required = false) String q, @RequestParam(defaultValue = "false") boolean flagged,
                               @RequestParam(defaultValue = "0") int page, @RequestParam(defaultValue = "200") int size) {
        String needle = blank(q) == null ? null : "%" + q.trim().toLowerCase() + "%";
        int sz = Math.max(1, Math.min(size, 2000)), pg = Math.max(0, page);
        List<Map<String, Object>> rows = jdbc.sql("""
                SELECT count(*) OVER () AS total_rows, d.* FROM credentials.document_rows() d
                 WHERE (:k::text IS NULL OR d.kind = :k) AND (:st::text IS NULL OR d.status = :st) AND (NOT :fl OR d.flagged_at IS NOT NULL)
                   AND (:q::text IS NULL OR lower(coalesce(d.student_name, d.holder, '')) LIKE :q OR lower(coalesce(d.student_number, '')) LIKE :q OR lower(coalesce(d.number, '')) LIKE :q OR lower(d.verification_code) LIKE :q OR lower(coalesce(d.request_ref, '')) LIKE :q)
                 ORDER BY coalesce(d.student_name, d.holder), d.issued_at DESC LIMIT :n OFFSET :o
                """).param("k", blank(kind) == null ? null : kind.trim().toUpperCase(), Types.VARCHAR).param("st", blank(status) == null ? null : status.trim().toUpperCase(), Types.VARCHAR).param("fl", flagged)
                .param("q", needle, Types.VARCHAR).param("n", sz).param("o", pg * sz).query().listOfRows();
        long total = rows.isEmpty() ? 0 : ((Number) rows.get(0).get("total_rows")).longValue();
        rows.forEach(r -> r.remove("total_rows"));
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("total", total); out.put("page", pg); out.put("size", sz); out.put("rows", rows);
        return out;
    }

    @GetMapping("/api/v1/documents/issued/{id}")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> issuedOne(@PathVariable UUID id) {
        Map<String, Object> out = document(id);
        out.put("events", jdbc.sql("SELECT e.action, e.from_state, e.to_state, e.note, e.actor_office, e.at, pe.surname || ', ' || pe.given_names AS actor FROM credentials.event e LEFT JOIN iam.person pe ON pe.id = e.actor_id WHERE e.issued_id = :id ORDER BY e.at").param("id", id).query().listOfRows());
        out.put("downloadsLog", jdbc.sql("SELECT kind, at, ip FROM credentials.download_log WHERE issued_id = :id ORDER BY at DESC LIMIT 50").param("id", id).query().listOfRows());
        out.put("verificationsLog", jdbc.sql("SELECT status, at, ip FROM credentials.verification WHERE issued_id = :id ORDER BY at DESC LIMIT 50").param("id", id).query().listOfRows());
        out.put("tokens", jdbc.sql("SELECT id, for_kind, email, expires_at, uses, max_uses, revoked_at, created_at FROM credentials.download_token WHERE issued_id = :id ORDER BY created_at DESC").param("id", id).query().listOfRows());
        out.put("versions", jdbc.sql("""
                WITH RECURSIVE chain AS (SELECT i.* FROM credentials.issued i WHERE i.id = :id UNION ALL SELECT p.* FROM credentials.issued p JOIN chain c ON c.supersedes = p.id),
                fwd AS (SELECT i.* FROM credentials.issued i WHERE i.id = :id UNION ALL SELECT n.* FROM credentials.issued n JOIN fwd f ON n.supersedes = f.id)
                SELECT DISTINCT x.id, x.number, x.version, x.verification_code, x.issued_on, credentials.document_status(x.id) AS status, x.note FROM (SELECT * FROM chain UNION SELECT * FROM fwd) x ORDER BY x.version
                """).param("id", id).query().listOfRows());
        return out;
    }

    /** the office reads a document for its PDF; logged as an office download */
    @GetMapping("/api/v1/documents/issued/{id}/download")
    @PreAuthorize(READERS)
    @Transactional
    Map<String, Object> officeDownload(@PathVariable UUID id, Authentication auth, HttpServletRequest req) {
        Map<String, Object> d = document(id);
        jdbc.sql("SELECT credentials.record_download(:i, :a, 'OFFICE', :ip, :ua)").param("i", id).param("a", UUID.fromString(auth.getName())).param("ip", ip(req), Types.VARCHAR).param("ua", agent(req), Types.VARCHAR).query().listOfRows();
        return d;
    }

    public record RevokeIn(@NotBlank @Size(max = 600) String reason, @NotBlank @Size(max = 120) String instrument) {
    }

    @PostMapping("/api/v1/documents/issued/{id}/revoke")
    @PreAuthorize(REVOKERS)
    @Transactional
    Map<String, Object> revoke(@PathVariable UUID id, @Valid @RequestBody RevokeIn body) {
        jdbc.sql("SELECT credentials.revoke_document(:id, :r, :i)").param("id", id).param("r", body.reason().trim()).param("i", body.instrument().trim()).query().listOfRows();
        return Map.of("ok", true, "status", "REVOKED");
    }

    @PostMapping("/api/v1/documents/issued/{id}/reissue")
    @PreAuthorize(SIGNERS)
    @Transactional
    Map<String, Object> reissue(@PathVariable UUID id, @Valid @RequestBody ReasonIn body) {
        if (blank(body.reason()) == null) throw new DomainRuleViolation("DOC_REASON", "A reissue carries its reason.", new DomainRuleViolation.Remedy("Say what was corrected.", "The Registry"));
        UUID n = jdbc.sql("SELECT credentials.reissue_document(:id, :r)").param("id", id).param("r", body.reason().trim()).query(UUID.class).single();
        return Map.of("issuedId", n, "version", jdbc.sql("SELECT version FROM credentials.issued WHERE id = :i").param("i", n).query(Integer.class).single());
    }

    @PostMapping("/api/v1/documents/issued/{id}/clear-flag")
    @PreAuthorize(OFFICE)
    @Transactional
    Map<String, Object> clearFlag(@PathVariable UUID id, @RequestBody(required = false) ReasonIn body) {
        jdbc.sql("SELECT credentials.clear_flag(:id, :n)").param("id", id).param("n", body == null ? "Reviewed; the document stands" : blank(body.reason()), Types.VARCHAR).query().listOfRows();
        return Map.of("ok", true);
    }

    public record CertificateIn(@NotNull UUID studentId, @Size(max = 400) String note) {
    }

    @PostMapping("/api/v1/documents/certificates")
    @PreAuthorize(SIGNERS)
    @Transactional
    Map<String, Object> issueCertificate(@Valid @RequestBody CertificateIn body) {
        UUID i = jdbc.sql("SELECT credentials.issue_certificate(:s, :n)").param("s", body.studentId()).param("n", blank(body.note()), Types.VARCHAR).query(UUID.class).single();
        return Map.of("issuedId", i, "number", jdbc.sql("SELECT number FROM credentials.issued WHERE id = :i").param("i", i).query(String.class).single());
    }

    public record BulkCertificateIn(@NotNull List<UUID> studentIds, @Size(max = 400) String note) {
    }

    @PostMapping("/api/v1/documents/certificates/bulk")
    @PreAuthorize(SIGNERS)
    @Transactional
    Map<String, Object> issueCertificates(@Valid @RequestBody BulkCertificateIn body) {
        List<Map<String, Object>> results = new ArrayList<>();
        for (UUID s : body.studentIds()) {
            try {
                UUID i = jdbc.sql("SELECT credentials.issue_certificate(:s, :n)").param("s", s).param("n", blank(body.note()), Types.VARCHAR).query(UUID.class).single();
                results.add(Map.of("studentId", s, "issuedId", i, "ok", true));
            } catch (RuntimeException e) {
                throw e; // one refusal rolls the run back: the desk fixes the record and runs again
            }
        }
        return Map.of("issued", results.size(), "results", results);
    }

    @GetMapping("/api/v1/documents/verifications")
    @PreAuthorize(READERS)
    List<Map<String, Object>> verifications(@RequestParam(defaultValue = "200") int size) {
        return jdbc.sql("SELECT v.key, v.status, v.kind, v.at, v.ip, d.number, d.student_name FROM credentials.verification v LEFT JOIN credentials.document_rows() d ON d.id = v.issued_id ORDER BY v.at DESC LIMIT :n").param("n", Math.max(1, Math.min(size, 2000))).query().listOfRows();
    }

    /* ── policies and templates ──────────────────────────────────────────── */

    public record PolicyIn(Boolean billable, BigDecimal fee, BigDecimal urgentFee, BigDecimal physicalFee, BigDecimal internationalFee, Boolean selfService, Integer slaDays, Integer urgentSlaDays,
                           String includes, List<String> publicFields, Boolean graduatesOnly, Boolean active, @Size(max = 120) String label) {
    }

    @PutMapping("/api/v1/documents/policies/{kind}")
    @PreAuthorize(CONFIG)
    @Transactional
    Map<String, Object> policy(@PathVariable String kind, @RequestBody PolicyIn body) {
        String k = kind.trim().toUpperCase();
        if (!KINDS.contains(k)) throw new NotFound("document kind", k);
        jdbc.sql("""
                UPDATE credentials.document_policy SET billable = coalesce(:b, billable), fee = CASE WHEN :feeSet THEN :fee ELSE fee END, urgent_fee = coalesce(:uf, urgent_fee), physical_fee = coalesce(:pf, physical_fee),
                       international_fee = coalesce(:if, international_fee), self_service = coalesce(:ss, self_service), sla_days = coalesce(:sla, sla_days), urgent_sla_days = coalesce(:usla, urgent_sla_days),
                       includes = coalesce(:inc, includes), public_fields = coalesce(:pfld, public_fields), graduates_only = coalesce(:go, graduates_only), active = coalesce(:act, active), label = coalesce(:lbl, label), updated_at = now()
                 WHERE kind = :k
                """).param("k", k).param("b", body.billable(), Types.BOOLEAN).param("feeSet", body.fee() != null || (body.billable() != null && !body.billable())).param("fee", body.fee(), Types.NUMERIC)
                .param("uf", body.urgentFee(), Types.NUMERIC).param("pf", body.physicalFee(), Types.NUMERIC).param("if", body.internationalFee(), Types.NUMERIC).param("ss", body.selfService(), Types.BOOLEAN)
                .param("sla", body.slaDays(), Types.INTEGER).param("usla", body.urgentSlaDays(), Types.INTEGER).param("inc", blank(body.includes()) == null ? null : body.includes().trim().toUpperCase(), Types.VARCHAR)
                .param("pfld", body.publicFields() == null || body.publicFields().isEmpty() ? null : body.publicFields().toArray(String[]::new), Types.ARRAY).param("go", body.graduatesOnly(), Types.BOOLEAN).param("act", body.active(), Types.BOOLEAN).param("lbl", blank(body.label()), Types.VARCHAR).update();
        jdbc.sql("SELECT credentials.log(NULL, NULL, NULL, 'POLICY_CHANGED', NULL, :k, NULL)").param("k", k).query().listOfRows();
        return jdbc.sql("SELECT * FROM credentials.document_policy WHERE kind = :k").param("k", k).query().singleRow();
    }

    @GetMapping("/api/v1/documents/templates")
    @PreAuthorize(READERS)
    List<Map<String, Object>> templates() {
        return jdbc.sql("SELECT * FROM credentials.document_template ORDER BY kind, version DESC").query().listOfRows();
    }

    public record TemplateIn(@NotBlank String kind, @NotBlank @Size(max = 120) String title, @Size(max = 200) String subtitle, @NotBlank @Size(max = 120) String signatoryName, @NotBlank @Size(max = 120) String signatoryTitle,
                             @Size(max = 120) String secondName, @Size(max = 120) String secondTitle, @Size(max = 600) String footer, @Size(max = 1000) String remarks) {
    }

    /** a new template version: documents already issued stay under the version they were issued with */
    @PostMapping("/api/v1/documents/templates")
    @PreAuthorize(CONFIG)
    @Transactional
    Map<String, Object> template(@Valid @RequestBody TemplateIn body) {
        String k = body.kind().trim().toUpperCase();
        if (!KINDS.contains(k)) throw new NotFound("document kind", k);
        int v = jdbc.sql("SELECT coalesce(max(version), 0) + 1 FROM credentials.document_template WHERE kind = :k").param("k", k).query(Integer.class).single();
        jdbc.sql("UPDATE credentials.document_template SET active = false WHERE kind = :k").param("k", k).update();
        UUID id = jdbc.sql("INSERT INTO credentials.document_template (kind, version, title, subtitle, signatory_name, signatory_title, second_name, second_title, footer, remarks) VALUES (:k, :v, :t, :s, :sn, :st, :n2, :t2, :f, :r) RETURNING id")
                .param("k", k).param("v", v).param("t", body.title().trim()).param("s", blank(body.subtitle()), Types.VARCHAR).param("sn", body.signatoryName().trim()).param("st", body.signatoryTitle().trim())
                .param("n2", blank(body.secondName()), Types.VARCHAR).param("t2", blank(body.secondTitle()), Types.VARCHAR).param("f", blank(body.footer()), Types.VARCHAR).param("r", blank(body.remarks()), Types.VARCHAR).query(UUID.class).single();
        jdbc.sql("SELECT credentials.log(NULL, NULL, NULL, 'TEMPLATE_VERSION', NULL, :k || ' v' || :v, NULL)").param("k", k).param("v", v).query().listOfRows();
        return Map.of("id", id, "version", v);
    }
}
