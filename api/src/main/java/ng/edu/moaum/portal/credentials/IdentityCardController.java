package ng.edu.moaum.portal.credentials;

import java.sql.Types;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * The Library's card desk (V027): the students on the matriculation
 * register who hold no live card, the cards issued, and the act of issuing
 * one — on the matriculation number, when the scheme releases ID_CARD, one
 * live card at a time; a lost card is ended on the record and replaced.
 */
@RestController
@RequestMapping("/api/v1/credentials/identity-cards")
class IdentityCardController {

    private static final String READERS = "hasAnyAuthority('OFFICE_library','OFFICE_security','OFFICE_registrar','OFFICE_dregistrar','OFFICE_academic','OFFICE_records','OFFICE_ict','OFFICE_super')";
    /** GAP-005 (the University's decision, 16 Oct 2026): the Security Unit alone prints, issues and reports a card lost — as the
     *  brief has it; the Library and the other offices read a card's status (super stays the system's break-glass) */
    private static final String ISSUERS = "hasAnyAuthority('OFFICE_security','OFFICE_super')";
    /** V439: the staff cards are read by the card desk and by HR, whose staff record prints the card */
    private static final String STAFF_READERS = "hasAnyAuthority('OFFICE_library','OFFICE_security','OFFICE_registrar','OFFICE_dregistrar','OFFICE_academic','OFFICE_records','OFFICE_ict','OFFICE_hrm','OFFICE_super')";

    public record Issue(@Size(max = 200) String reason) {
    }

    /** V622: the blood group the card prints — one of A+, A-, B+, B-, AB+, AB-, O+, O- (the database reads the common spellings) */
    public record BloodGroup(@NotBlank @Size(max = 20) String bloodGroup) {
    }

    /** V622: a student's blood group added or corrected at the card desk — the record's own (the biodata), printed on the card */
    @org.springframework.web.bind.annotation.PutMapping("/students/{studentId}/blood-group")
    @PreAuthorize(ISSUERS)
    @Transactional
    Map<String, Object> studentBloodGroup(@PathVariable UUID studentId, @Valid @RequestBody BloodGroup body) {
        String g = jdbc.sql("SELECT credentials.set_blood_group('STUDENT', :s, :g)").param("s", studentId).param("g", body.bloodGroup().trim())
                .query(String.class).single();
        return Map.of("bloodGroup", g);
    }

    /** V622: a member of staff's blood group added or corrected at the card desk, printed on the staff card */
    @org.springframework.web.bind.annotation.PutMapping("/staff/{personId}/blood-group")
    @PreAuthorize(ISSUERS)
    @Transactional
    Map<String, Object> staffBloodGroup(@PathVariable UUID personId, @Valid @RequestBody BloodGroup body) {
        String g = jdbc.sql("SELECT credentials.set_blood_group('STAFF', :p, :g)").param("p", personId).param("g", body.bloodGroup().trim())
                .query(String.class).single();
        return Map.of("bloodGroup", g);
    }

    private final JdbcClient jdbc;
    private final ng.edu.moaum.portal.shared.CheckCodes codes;
    private final ng.edu.moaum.portal.shared.FileObjects files;
    private final ng.edu.moaum.portal.studentportal.StudentPortalService portal;

    IdentityCardController(JdbcClient jdbc, ng.edu.moaum.portal.shared.CheckCodes codes, ng.edu.moaum.portal.shared.FileObjects files,
                           ng.edu.moaum.portal.studentportal.StudentPortalService portal) {
        this.jdbc = jdbc;
        this.codes = codes;
        this.files = files;
        this.portal = portal;
    }

    @GetMapping
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> desk(@RequestParam(required = false) String q) {
        List<Map<String, Object>> cards = jdbc.sql("""
                SELECT c.id, c.card_no, c.issued_at, c.valid_to, c.state, c.ended_at, c.ended_reason,
                       s.id AS student_id, s.matric_no, s.surname, s.other_names, p.name AS programme, s.current_level
                  FROM credentials.identity_card c JOIN people.student s ON s.id = c.student_id JOIN ref.programme p ON p.code = s.programme_code
                 ORDER BY c.issued_at DESC LIMIT 300
                """).query().listOfRows();
        // the address the card's QR carries: the public page answers only with the code signed over the card number
        cards = cards.stream().map(r -> {
            Map<String, Object> m = new java.util.LinkedHashMap<>(r);
            String no = String.valueOf(r.get("card_no"));
            m.put("verify_path", "/verify/idcard?no=" + java.net.URLEncoder.encode(no, java.nio.charset.StandardCharsets.UTF_8)
                    + "&c=" + codes.sign(ng.edu.moaum.portal.shared.CheckCodes.Kind.ID_CARD, no));
            return m;
        }).toList();
        List<Map<String, Object>> waiting = jdbc.sql("""
                SELECT s.id AS student_id, s.matric_no, s.surname, s.other_names, p.name AS programme, s.current_level, s.status,
                       EXISTS (SELECT 1 FROM credentials.identity_card c WHERE c.student_id = s.id) AS had_one
                  FROM people.student s JOIN ref.programme p ON p.code = s.programme_code
                 -- a card is keyed on the matriculation number: every matriculated student still on the books
                 -- (admitted, active, on probation, or dormant between sessions) may be issued one; the
                 -- withdrawn, expelled, transferred-out, graduated and deceased may not
                 WHERE s.matric_no IS NOT NULL AND s.status IN ('ADMITTED','ACTIVE','PROBATION','DORMANT')
                   AND NOT EXISTS (SELECT 1 FROM credentials.identity_card c WHERE c.student_id = s.id AND c.state = 'ISSUED')
                   AND (:q::text IS NULL OR s.matric_no ILIKE '%' || :q || '%' OR s.surname ILIKE '%' || :q || '%')
                 ORDER BY s.surname LIMIT 200
                """).param("q", q, Types.VARCHAR).query().listOfRows();
        return Map.of("cards", cards, "waiting", waiting);
    }

    @PostMapping("/students/{studentId}/issue")
    @PreAuthorize(ISSUERS)
    @Transactional
    Map<String, Object> issue(@PathVariable UUID studentId, @RequestBody(required = false) @Valid Issue body) {
        String no = jdbc.sql("SELECT credentials.issue_identity_card(:s, :r)").param("s", studentId).param("r", body == null ? null : body.reason(), Types.VARCHAR)
                .query(String.class).single();
        return Map.of("studentId", studentId, "cardNo", no);
    }

    @PostMapping("/students/{studentId}/lost")
    @PreAuthorize(ISSUERS)
    @Transactional
    Map<String, Object> lost(@PathVariable UUID studentId, @RequestBody(required = false) @Valid Issue body) {
        int n = jdbc.sql("SELECT credentials.report_card_lost(:s, :r)").param("s", studentId).param("r", body == null ? null : body.reason(), Types.VARCHAR)
                .query(Integer.class).single();
        return Map.of("studentId", studentId, "ended", n);
    }

    /* ── V605 · the Security Unit's desk: search, the student, eligibility, print, hand over, end, history, report ── */

    private static final tools.jackson.databind.ObjectMapper JSON = new tools.jackson.databind.ObjectMapper();
    private static final java.util.regex.Pattern CODED = java.util.regex.Pattern.compile("([A-Z][A-Z0-9]*_[A-Z0-9_]{2,60}): ([^\\n]+)");
    static final java.util.Set<String> REPLACE_REASONS = java.util.Set.of("LOST", "DAMAGED", "NAME_CORRECTION", "PROGRAMME_CHANGE", "MATRIC_CORRECTION",
            "PHOTOGRAPH_UPDATE", "SECURITY_REPLACEMENT", "EXPIRED", "OTHER");
    static final java.util.Set<String> END_STATES = java.util.Set.of("LOST", "DAMAGED", "RETURNED", "REVOKED", "CANCELLED");

    public record Print(@Size(max = 40) String replaceReason, @Size(max = 300) String note) {
    }

    public record Collect(@Size(max = 300) String note) {
    }

    public record End(@NotBlank @Size(max = 20) String state, @NotBlank @Size(max = 300) String reason) {
    }

    /** the students a search names — matriculation, JAMB or admission number, name, phone or e-mail — a page at a time, each with
     *  the live card and the eligibility reading; nothing of finance beyond the reading */
    @GetMapping("/students/search")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> search(@RequestParam String q, @RequestParam(defaultValue = "0") int page, @RequestParam(defaultValue = "25") int size) {
        String term = q == null ? "" : q.trim().replaceAll("\\s+", " ");
        int sz = Math.max(1, Math.min(size, 50));
        int pg = Math.max(0, page);
        if (term.length() < 2) {
            return Map.of("rows", List.of(), "total", 0, "page", pg, "size", sz);
        }
        List<Map<String, Object>> rows = jdbc.sql("""
                SELECT x.*, (e.j->>'eligible')::boolean AS eligible, (e.j->'checks'->>'fees')::boolean AS fees_ok, (e.j->'checks'->>'photo')::boolean AS photo,
                       e.j->'reasons' AS reasons_json
                  FROM (SELECT s.id AS student_id, s.surname || ', ' || s.other_names AS name, s.matric_no, s.jamb_reg_no, s.admission_no,
                               f.name AS faculty, d.name AS department, p.name AS programme, s.current_level AS level, s.entry_session, s.status,
                               c.card_no, c.state AS card_state, c.version AS card_version, count(*) OVER () AS total
                          FROM people.student s
                          LEFT JOIN ref.programme p ON p.code = s.programme_code
                          LEFT JOIN ref.department d ON d.code = p.dept_code
                          LEFT JOIN ref.faculty f ON f.code = p.faculty_code
                          LEFT JOIN people.student_contact sc ON sc.student_id = s.id
                          LEFT JOIN LATERAL (SELECT c.card_no, c.state, c.version FROM credentials.identity_card c
                                              WHERE c.student_id = s.id AND c.state IN ('PRINTED', 'ISSUED') LIMIT 1) c ON true
                         WHERE s.duplicate_of IS NULL
                           AND (s.matric_no ILIKE :q || '%' OR s.matric_no ILIKE '%/' || :q OR s.jamb_reg_no ILIKE :q || '%' OR s.admission_no ILIKE :q || '%'
                                OR (s.surname || ' ' || s.other_names) ILIKE '%' || :q || '%' OR (s.other_names || ' ' || s.surname) ILIKE '%' || :q || '%'
                                OR sc.phone ILIKE '%' || :q || '%' OR sc.email ILIKE :q || '%')
                         ORDER BY s.surname, s.other_names
                         LIMIT :size OFFSET :off) x
                  CROSS JOIN LATERAL (SELECT credentials.id_card_eligibility(x.student_id) AS j) e
                """).param("q", term).param("size", sz).param("off", pg * sz).query().listOfRows();
        long total = rows.isEmpty() ? 0 : ((Number) rows.get(0).get("total")).longValue();
        List<Map<String, Object>> out = rows.stream().map(r -> {
            Map<String, Object> m = new java.util.LinkedHashMap<>(r);
            m.remove("total");
            m.put("reasons", reasons(m.remove("reasons_json")));
            return m;
        }).toList();
        return Map.of("rows", out, "total", total, "page", pg, "size", sz);
    }

    /** one student for the desk: the particulars, whether a photograph is held, the eligibility reading with its reasons, the live card
     *  with its signed check address, and the history — every card and every act */
    @GetMapping("/students/{studentId}")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> student(@PathVariable UUID studentId) {
        Map<String, Object> s = jdbc.sql("""
                SELECT s.id AS student_id, s.surname || ', ' || s.other_names AS name, s.surname, s.other_names, s.matric_no, s.jamb_reg_no, s.admission_no, s.sex,
                       f.name AS faculty, d.name AS department, p.name AS programme, s.programme_code, s.current_level AS level, s.entry_session, s.entry_mode,
                       s.status, s.matriculated_at, policy.university_current_session() AS current_session,
                       (SELECT r.phone FROM people.student_reach(s.id) r) AS reach_phone,
                       credentials.student_blood_group(s.id) AS blood_group   -- V622
                  FROM people.student s
                  LEFT JOIN ref.programme p ON p.code = s.programme_code
                  LEFT JOIN ref.department d ON d.code = p.dept_code
                  LEFT JOIN ref.faculty f ON f.code = p.faculty_code
                 WHERE s.id = :s
                """).param("s", studentId).query().listOfRows().stream().findFirst()
                .orElseThrow(() -> new ng.edu.moaum.portal.shared.DomainRuleViolation("ID_CARD_NO_STUDENT", "No such student.",
                        new ng.edu.moaum.portal.shared.DomainRuleViolation.Remedy("Search again.", "Security Unit")));
        Map<String, Object> out = new java.util.LinkedHashMap<>();
        out.put("student", s);
        out.put("photo", portal.passportImage(studentId).isPresent());
        out.put("eligibility", eligibility(studentId));
        out.putAll(history(studentId));
        return out;
    }

    @GetMapping("/students/{studentId}/eligibility")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> eligibilityOf(@PathVariable UUID studentId) {
        return eligibility(studentId);
    }

    /** the card printed: made on the first print (PRINTED, a number drawn), printed again and counted after, or — on a reason from the
     *  list — the live card ended and replaced by a new number; eligibility is read again in the database under the student's lock */
    @PostMapping("/students/{studentId}/print")
    @PreAuthorize(ISSUERS)
    @Transactional
    Map<String, Object> print(@PathVariable UUID studentId, @RequestBody(required = false) @Valid Print body) {
        String reason = body == null ? null : blank(body.replaceReason());
        if (reason != null && !REPLACE_REASONS.contains(reason)) {
            throw new ng.edu.moaum.portal.shared.DomainRuleViolation("ID_CARD_REASON", "A replacement is made on a reason from the list.",
                    new ng.edu.moaum.portal.shared.DomainRuleViolation.Remedy("Choose the reason: lost, damaged, name correction, programme change, matriculation correction, photograph update, security replacement, expired, other.", "Security Unit"));
        }
        try {
            String j = jdbc.sql("SELECT credentials.print_identity_card(:s, :r, :n)::text").param("s", studentId).param("r", reason, Types.VARCHAR)
                    .param("n", body == null ? null : blank(body.note()), Types.VARCHAR).query(String.class).single();
            return parse(j);
        } catch (org.springframework.dao.DataAccessException e) {
            throw coded(e);
        }
    }

    /** the printed card handed to the student */
    @PostMapping("/students/{studentId}/collect")
    @PreAuthorize(ISSUERS)
    @Transactional
    Map<String, Object> collect(@PathVariable UUID studentId, @RequestBody(required = false) @Valid Collect body) {
        try {
            String j = jdbc.sql("SELECT credentials.collect_identity_card(:s, :n)::text").param("s", studentId)
                    .param("n", body == null ? null : blank(body.note()), Types.VARCHAR).query(String.class).single();
            return parse(j);
        } catch (org.springframework.dao.DataAccessException e) {
            throw coded(e);
        }
    }

    /** a live card ended — lost, damaged, returned, revoked or cancelled — on a reason; the record stays */
    @PostMapping("/cards/{cardId}/end")
    @PreAuthorize(ISSUERS)
    @Transactional
    Map<String, Object> end(@PathVariable UUID cardId, @RequestBody @Valid End body) {
        String state = body.state().trim().toUpperCase();
        if (!END_STATES.contains(state)) {
            throw new ng.edu.moaum.portal.shared.DomainRuleViolation("ID_CARD_STATE", "A card is ended as lost, damaged, returned, revoked or cancelled.",
                    new ng.edu.moaum.portal.shared.DomainRuleViolation.Remedy("Choose one of them.", "Security Unit"));
        }
        try {
            String j = jdbc.sql("SELECT credentials.end_identity_card(:c, :st, :r)::text").param("c", cardId).param("st", state).param("r", body.reason().trim())
                    .query(String.class).single();
            return parse(j);
        } catch (org.springframework.dao.DataAccessException e) {
            throw coded(e);
        }
    }

    @GetMapping("/students/{studentId}/history")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> historyOf(@PathVariable UUID studentId) {
        return history(studentId);
    }

    /** the cards printed and issued, filtered as the report asks, a page at a time (export=true: up to 20,000 rows) */
    @GetMapping("/report")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> report(@RequestParam(required = false) String session, @RequestParam(required = false) String fac,
                               @RequestParam(required = false) String dept, @RequestParam(required = false) String prog,
                               @RequestParam(required = false) Integer level, @RequestParam(required = false) String status,
                               @RequestParam(required = false) String cardState, @RequestParam(required = false) String printedFrom,
                               @RequestParam(required = false) String printedTo, @RequestParam(required = false) String issuedFrom,
                               @RequestParam(required = false) String issuedTo, @RequestParam(required = false) String printedBy,
                               @RequestParam(defaultValue = "0") int page, @RequestParam(defaultValue = "50") int size,
                               @RequestParam(defaultValue = "false") boolean export) {
        int sz = export ? 20000 : Math.max(1, Math.min(size, 200));
        List<Map<String, Object>> rows = jdbc.sql("""
                SELECT c.id AS card_id, c.card_no, c.state, c.version, c.print_count, c.printed_at, c.collected_at AS issued_at, c.valid_to, c.ended_at, c.ended_reason,
                       c.replacement_reason, s.id AS student_id, s.surname || ', ' || s.other_names AS name, s.matric_no, s.current_level AS level, s.status,
                       s.entry_session, f.name AS faculty, d.name AS department, p.name AS programme,
                       coalesce(pb.surname || ', ' || pb.given_names, c.printed_by::text) AS printed_by,
                       coalesce(cb.surname || ', ' || cb.given_names, c.collected_by::text) AS issued_by,
                       count(*) OVER () AS total
                  FROM credentials.identity_card c
                  JOIN people.student s ON s.id = c.student_id
                  LEFT JOIN ref.programme p ON p.code = s.programme_code
                  LEFT JOIN ref.department d ON d.code = p.dept_code
                  LEFT JOIN ref.faculty f ON f.code = p.faculty_code
                  LEFT JOIN iam.person pb ON pb.id = c.printed_by
                  LEFT JOIN iam.person cb ON cb.id = c.collected_by
                 WHERE (CAST(:session AS text) IS NULL OR s.entry_session = :session)
                   AND (CAST(:fac AS text) IS NULL OR p.faculty_code = :fac) AND (CAST(:dept AS text) IS NULL OR p.dept_code = :dept)
                   AND (CAST(:prog AS text) IS NULL OR p.code = :prog) AND (CAST(:level AS int) IS NULL OR s.current_level = :level)
                   AND (CAST(:status AS text) IS NULL OR s.status = :status) AND (CAST(:cstate AS text) IS NULL OR c.state = :cstate)
                   AND (CAST(:pfrom AS date) IS NULL OR c.printed_at >= CAST(:pfrom AS date)) AND (CAST(:pto AS date) IS NULL OR c.printed_at < CAST(:pto AS date) + 1)
                   AND (CAST(:ifrom AS date) IS NULL OR c.collected_at >= CAST(:ifrom AS date)) AND (CAST(:ito AS date) IS NULL OR c.collected_at < CAST(:ito AS date) + 1)
                   AND (CAST(:pby AS text) IS NULL OR (pb.surname || ' ' || pb.given_names) ILIKE '%' || :pby || '%' OR c.printed_by::text = :pby)
                 ORDER BY s.surname, s.other_names, c.version
                 LIMIT :size OFFSET :off
                """).param("session", blank(session), Types.VARCHAR).param("fac", blank(fac), Types.VARCHAR).param("dept", blank(dept), Types.VARCHAR)
                .param("prog", blank(prog), Types.VARCHAR).param("level", level, Types.INTEGER).param("status", blank(status), Types.VARCHAR)
                .param("cstate", blank(cardState), Types.VARCHAR).param("pfrom", date(printedFrom), Types.DATE).param("pto", date(printedTo), Types.DATE)
                .param("ifrom", date(issuedFrom), Types.DATE).param("ito", date(issuedTo), Types.DATE).param("pby", blank(printedBy), Types.VARCHAR)
                .param("size", sz).param("off", export ? 0 : Math.max(0, page) * sz).query().listOfRows();
        long total = rows.isEmpty() ? 0 : ((Number) rows.get(0).get("total")).longValue();
        List<Map<String, Object>> out = rows.stream().map(r -> { Map<String, Object> m = new java.util.LinkedHashMap<>(r); m.remove("total"); return m; }).toList();
        return Map.of("rows", out, "total", total, "page", export ? 0 : Math.max(0, page), "size", sz);
    }

    private Map<String, Object> eligibility(UUID studentId) {
        String j = jdbc.sql("SELECT credentials.id_card_eligibility(:s)::text").param("s", studentId).query(String.class).single();
        return parse(j);
    }

    private Map<String, Object> history(UUID studentId) {
        List<Map<String, Object>> cards = jdbc.sql("""
                SELECT c.id, c.card_no, c.state, c.version, c.print_count, c.issued_at AS made_at, c.printed_at, c.collected_at, c.valid_to, c.ended_at, c.ended_reason,
                       c.replacement_reason, c.previous_card_id, prev.card_no AS previous_card_no,
                       coalesce(pb.surname || ', ' || pb.given_names, c.printed_by::text) AS printed_by,
                       coalesce(cb.surname || ', ' || cb.given_names, c.collected_by::text) AS issued_by
                  FROM credentials.identity_card c
                  LEFT JOIN credentials.identity_card prev ON prev.id = c.previous_card_id
                  LEFT JOIN iam.person pb ON pb.id = c.printed_by
                  LEFT JOIN iam.person cb ON cb.id = c.collected_by
                 WHERE c.student_id = :s
                 ORDER BY c.issued_at DESC
                """).param("s", studentId).query().listOfRows();
        List<Map<String, Object>> events = jdbc.sql("""
                SELECT e.action, e.from_state, e.to_state, e.note, e.at, e.actor_office, coalesce(p.surname || ', ' || p.given_names, e.actor_id::text) AS actor
                  FROM credentials.event e LEFT JOIN iam.person p ON p.id = e.actor_id
                 WHERE e.student_id = :s AND e.action LIKE 'ID_CARD_%'
                 ORDER BY e.at DESC LIMIT 200
                """).param("s", studentId).query().listOfRows();
        Map<String, Object> live = cards.stream().filter(c -> "PRINTED".equals(c.get("state")) || "ISSUED".equals(c.get("state"))).findFirst().orElse(null);
        Map<String, Object> out = new java.util.LinkedHashMap<>();
        if (live != null) {
            Map<String, Object> l = new java.util.LinkedHashMap<>(live);
            String no = String.valueOf(live.get("card_no"));
            l.put("verify_path", "/verify/idcard?no=" + java.net.URLEncoder.encode(no, java.nio.charset.StandardCharsets.UTF_8)
                    + "&c=" + codes.sign(ng.edu.moaum.portal.shared.CheckCodes.Kind.ID_CARD, no));
            out.put("card", l);
        } else {
            out.put("card", null);
        }
        out.put("cards", cards);
        out.put("events", events);
        return out;
    }

    @SuppressWarnings("unchecked")
    private static Map<String, Object> parse(String json) {
        return JSON.readValue(json, Map.class);
    }

    @SuppressWarnings("unchecked")
    private static List<String> reasons(Object json) {
        if (json == null) return List.of();
        try {
            return JSON.readValue(String.valueOf(json), List.class);
        } catch (RuntimeException e) {
            return List.of();
        }
    }

    private static ng.edu.moaum.portal.shared.DomainRuleViolation coded(org.springframework.dao.DataAccessException e) {
        String m = String.valueOf(e.getMostSpecificCause() == null ? e.getMessage() : e.getMostSpecificCause().getMessage());
        java.util.regex.Matcher c = CODED.matcher(m);
        boolean coded = c.find();
        return new ng.edu.moaum.portal.shared.DomainRuleViolation(coded ? c.group(1) : "ID_CARD_REFUSED", coded ? c.group(2).trim() : m,
                new ng.edu.moaum.portal.shared.DomainRuleViolation.Remedy("Read the reason; the record says what is missing.", "Security Unit"));
    }

    private static String blank(String v) {
        return v == null || v.isBlank() ? null : v.trim();
    }

    private static java.time.LocalDate date(String v) {
        try {
            return v == null || v.isBlank() ? null : java.time.LocalDate.parse(v.trim());
        } catch (java.time.format.DateTimeParseException e) {
            return null;
        }
    }

    /* ── the student card printed at the desk: the card in the register, its QR the signed check address ── */

    /** the live card of one student, with what the card shows, for the desk's print — none until the desk issues one */
    @GetMapping("/students/{studentId}/card")
    @PreAuthorize(ISSUERS)   // the printable card: the Security Unit's (GAP-005)
    @Transactional(readOnly = true)
    Map<String, Object> studentCard(@PathVariable UUID studentId) {
        Map<String, Object> row = jdbc.sql("""
                SELECT c.card_no, c.issued_at, c.valid_to, c.state, c.version, c.print_count, s.surname || ', ' || s.other_names AS name, s.matric_no, p.name AS programme,
                       f.name AS faculty, s.current_level AS level, s.entry_session, policy.university_current_session() AS session,
                       (SELECT r.phone FROM people.student_reach(s.id) r) AS reach_phone, credentials.student_blood_group(s.id) AS blood_group
                  FROM credentials.identity_card c JOIN people.student s ON s.id = c.student_id
                  LEFT JOIN ref.programme p ON p.code = s.programme_code LEFT JOIN ref.faculty f ON f.code = p.faculty_code
                 WHERE c.student_id = :s AND c.state IN ('PRINTED', 'ISSUED')   -- V605: printed and awaiting collection, or in force
                """).param("s", studentId).query().listOfRows().stream().findFirst()
                .orElseThrow(() -> new ng.edu.moaum.portal.shared.DomainRuleViolation("ID_CARD_NONE", "No identity card is in force for this student.",
                        new ng.edu.moaum.portal.shared.DomainRuleViolation.Remedy("Issue the card first; the print carries its number.", "Security Unit")));
        Map<String, Object> m = new java.util.LinkedHashMap<>(row);
        String no = String.valueOf(row.get("card_no"));
        m.put("verify_path", "/verify/idcard?no=" + java.net.URLEncoder.encode(no, java.nio.charset.StandardCharsets.UTF_8)
                + "&c=" + codes.sign(ng.edu.moaum.portal.shared.CheckCodes.Kind.ID_CARD, no));
        m.put("has_photo", portal.passportImage(studentId).isPresent());
        return m;
    }

    /** the photograph the student card carries — for the desk's print and, V605, for the desk's view of a matriculated student before the
     *  card is printed; never of a record with no matriculation number */
    @GetMapping("/students/{studentId}/photo")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    org.springframework.http.ResponseEntity<byte[]> studentPhoto(@PathVariable UUID studentId) {
        boolean matriculated = jdbc.sql("SELECT EXISTS (SELECT 1 FROM people.student WHERE id = :s AND matric_no IS NOT NULL)")
                .param("s", studentId).query(Boolean.class).single();
        if (!matriculated) return org.springframework.http.ResponseEntity.notFound().build();
        return portal.passportImage(studentId)
                .map(img -> org.springframework.http.ResponseEntity.ok().contentType(org.springframework.http.MediaType.IMAGE_JPEG)
                        .cacheControl(org.springframework.http.CacheControl.noStore()).body(img))
                .orElseGet(() -> org.springframework.http.ResponseEntity.notFound().build());
    }

    /* ── V439 · staff identity cards: the register, issued on the staff number by the same desk ── */

    /** the address a staff card's QR carries; the public page answers only with the code signed over the card number */
    private String staffVerifyPath(String cardNo) {
        return "/verify/staffcard?no=" + java.net.URLEncoder.encode(cardNo, java.nio.charset.StandardCharsets.UTF_8)
                + "&c=" + codes.sign(ng.edu.moaum.portal.shared.CheckCodes.Kind.STAFF_CARD, cardNo);
    }

    private static final String STAFF_CARD_ROWS = """
            SELECT c.id, c.card_no, c.issued_at, c.valid_to, c.state, c.ended_at, c.ended_reason, c.issued_office,
                   p.id AS person_id, p.staff_number, p.surname, p.given_names, d.name AS department, credentials.staff_blood_group(p.id) AS blood_group
              FROM credentials.staff_identity_card c JOIN iam.person p ON p.id = c.person_id
              LEFT JOIN hrm.staff_record r ON r.person_id = p.id LEFT JOIN ref.department d ON d.code = r.home_department
            """;

    @GetMapping("/staff")
    @PreAuthorize(STAFF_READERS)
    @Transactional(readOnly = true)
    Map<String, Object> staffDesk(@RequestParam(required = false) String q) {
        List<Map<String, Object>> cards = jdbc.sql(STAFF_CARD_ROWS + """
                 WHERE (:q::text IS NULL OR p.staff_number ILIKE '%' || :q || '%' OR p.surname ILIKE '%' || :q || '%' OR c.card_no ILIKE '%' || :q || '%')
                 ORDER BY c.issued_at DESC LIMIT 300
                """).param("q", q == null || q.isBlank() ? null : q.trim(), Types.VARCHAR).query().listOfRows().stream().map(r -> {
            Map<String, Object> m = new java.util.LinkedHashMap<>(r);
            m.put("verify_path", staffVerifyPath(String.valueOf(r.get("card_no"))));
            return m;
        }).toList();
        return Map.of("cards", cards);
    }

    /** the live card of one member of staff, for the print — none until the desk issues one */
    @GetMapping("/staff/{personId}/card")
    @PreAuthorize(ISSUERS)   // the printable card: the Security Unit's (GAP-005)
    @Transactional(readOnly = true)
    Map<String, Object> staffCard(@PathVariable UUID personId) {
        Map<String, Object> row = jdbc.sql(STAFF_CARD_ROWS + " WHERE c.person_id = :p AND c.state = 'ISSUED'").param("p", personId)
                .query().listOfRows().stream().findFirst()
                .orElseThrow(() -> new ng.edu.moaum.portal.shared.DomainRuleViolation("STAFF_CARD_NONE", "No staff identity card is in force for this person.",
                        new ng.edu.moaum.portal.shared.DomainRuleViolation.Remedy("Issue the card on the card desk first; the print carries its number.", "Security Unit")));
        Map<String, Object> m = new java.util.LinkedHashMap<>(row);
        m.put("verify_path", staffVerifyPath(String.valueOf(row.get("card_no"))));
        // what the card shows, and nothing more of the HR record: the desk prints from the register
        m.put("face", jdbc.sql("""
                SELECT pe.staff_number, pe.surname, pe.given_names, sr.present_rank AS rank, dp.name AS department, f.name AS faculty, e.category,
                       sr.date_first_appointment, e.appointment_date, EXISTS (SELECT 1 FROM hrm.staff_photo ph WHERE ph.person_id = pe.id) AS has_photo,
                       credentials.staff_blood_group(pe.id) AS blood_group
                  FROM iam.person pe LEFT JOIN hrm.staff_record sr ON sr.person_id = pe.id
                  LEFT JOIN hrm.employment e ON e.person_id = pe.id AND e.status <> 'ENDED'
                  LEFT JOIN ref.department dp ON dp.code = sr.home_department LEFT JOIN ref.faculty f ON f.code = dp.faculty_code
                 WHERE pe.id = :p
                """).param("p", personId).query().listOfRows().stream().findFirst().orElse(Map.of()));
        m.put("offices", jdbc.sql("""
                SELECT a.office_code, o.label AS office FROM iam.office_assignment a JOIN ref.office o ON o.code = a.office_code
                 WHERE a.person_id = :p AND a.valid_from <= current_date AND (a.valid_to IS NULL OR a.valid_to >= current_date)
                 ORDER BY a.valid_from DESC
                """).param("p", personId).query().listOfRows());
        return m;
    }

    /** the photograph the card carries, for the desk's print — only of a member of staff with a card in force */
    @GetMapping("/staff/{personId}/photo")
    @PreAuthorize(STAFF_READERS)
    @Transactional(readOnly = true)
    org.springframework.http.ResponseEntity<byte[]> staffPhoto(@PathVariable UUID personId) {
        boolean carded = jdbc.sql("SELECT EXISTS (SELECT 1 FROM credentials.staff_identity_card WHERE person_id = :p AND state = 'ISSUED')")
                .param("p", personId).query(Boolean.class).single();
        if (!carded) return org.springframework.http.ResponseEntity.notFound().build();
        return jdbc.sql("SELECT content_type, content, object_id FROM hrm.staff_photo WHERE person_id = :p").param("p", personId)
                .query().listOfRows().stream().findFirst()
                .map(r -> org.springframework.http.ResponseEntity.ok()
                        .contentType(org.springframework.http.MediaType.parseMediaType(String.valueOf(r.get("content_type"))))
                        .body(files.resolve((byte[]) r.get("content"), (UUID) r.get("object_id"))))
                .orElseGet(() -> org.springframework.http.ResponseEntity.notFound().build());
    }

    public record StaffIssue(@jakarta.validation.constraints.NotBlank @Size(max = 40) String staffNumber, @Size(max = 200) String reason) {
    }

    @PostMapping("/staff/issue")
    @PreAuthorize(ISSUERS)
    @Transactional
    Map<String, Object> issueStaff(@Valid @RequestBody StaffIssue body) {
        UUID person = jdbc.sql("SELECT id FROM iam.person WHERE upper(staff_number) = upper(:n)").param("n", body.staffNumber().trim())
                .query(UUID.class).optional()
                .orElseThrow(() -> new ng.edu.moaum.portal.shared.DomainRuleViolation("STAFF_CARD_NO_PERSON", "No member of staff carries that staff number.",
                        new ng.edu.moaum.portal.shared.DomainRuleViolation.Remedy("Check the number on the staff record.", "Registry")));
        String no = jdbc.sql("SELECT credentials.issue_staff_card(:p, :r)").param("p", person).param("r", body.reason(), Types.VARCHAR)
                .query(String.class).single();
        return Map.of("personId", person, "cardNo", no);
    }

    @PostMapping("/staff/{personId}/lost")
    @PreAuthorize(ISSUERS)
    @Transactional
    Map<String, Object> staffLost(@PathVariable UUID personId, @RequestBody(required = false) @Valid Issue body) {
        int n = jdbc.sql("SELECT credentials.report_staff_card_lost(:p, :r)").param("p", personId).param("r", body == null ? null : body.reason(), Types.VARCHAR)
                .query(Integer.class).single();
        return Map.of("personId", personId, "ended", n);
    }
}
