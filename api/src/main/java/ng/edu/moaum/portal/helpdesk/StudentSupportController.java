package ng.edu.moaum.portal.helpdesk;

import java.sql.Types;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

import jakarta.validation.Valid;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

import org.springframework.http.CacheControl;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.GrantedAuthority;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import ng.edu.moaum.portal.platform.NoticeRepository;
import ng.edu.moaum.portal.shared.DomainRuleViolation;
import ng.edu.moaum.portal.shared.FileObjects;
import ng.edu.moaum.portal.shared.NotFound;
import ng.edu.moaum.portal.student.StudentService;
import ng.edu.moaum.portal.studentportal.StudentPortalService;

/**
 * Student record support from the ICT Support Desk (V334). A support agent reaches the students their postings' scopes
 * cover and does what the Head granted the posting: reads the record the Registry's screens read, edits the open contact,
 * personal and family fields, replaces the photograph, raises a Registry change for a sensitive field, and manages a
 * registration through the student portal's own service — the registration engine's rules unchanged. Every act is
 * written to the support ledger with its reason and, when a ticket is named, on that ticket's timeline; the student is
 * told. Status, programme, matriculation, results and money are not reachable from here at all.
 */
@RestController
@RequestMapping("/api/v1/helpdesk/support")
class StudentSupportController {

    private static final String AGENTS = "hasAnyAuthority('OFFICE_ictagent','OFFICE_helpdeskhead','OFFICE_ict','OFFICE_admin','OFFICE_super')";
    private static final Set<String> HEADS = Set.of("OFFICE_helpdeskhead", "OFFICE_ict", "OFFICE_admin", "OFFICE_super");
    private static final List<String> ALL = List.of("VIEW_STUDENT", "EDIT_CONTACT", "EDIT_PERSONAL", "EDIT_FAMILY", "EDIT_PHOTO", "REQUEST_CHANGE",
            "VIEW_PAYMENTS", "VIEW_DOCUMENTS", "MANAGE_REGISTRATION", "EXPORT_STUDENTS");
    private static final Map<String, String> WORDS = Map.of("VIEW_STUDENT", "viewing student records", "EDIT_CONTACT", "editing contact details",
            "EDIT_PERSONAL", "editing personal details", "EDIT_FAMILY", "editing family and sponsor details", "EDIT_PHOTO", "replacing the photograph",
            "REQUEST_CHANGE", "requesting a Registry change", "VIEW_PAYMENTS", "viewing payments", "VIEW_DOCUMENTS", "viewing documents",
            "MANAGE_REGISTRATION", "managing course registration", "EXPORT_STUDENTS", "exporting lists");
    private static final Set<String> CONTACT_MIRROR = Set.of("mobile", "personal_email", "term_address");
    /** fields that bear on identity and fee status: from the desk they go to the Registry as a request, whatever tier the student's own form gives them */
    private static final Set<String> SENSITIVE = Set.of("nationality", "country_of_origin", "state_of_origin", "lga");
    private static final long MAX_PHOTO = 2L * 1024 * 1024;

    private final JdbcClient jdbc;
    private final StudentService students;
    private final StudentPortalService portal;
    private final NoticeRepository notices;
    private final FileObjects files;

    StudentSupportController(JdbcClient jdbc, StudentService students, StudentPortalService portal, NoticeRepository notices, FileObjects files) {
        this.jdbc = jdbc;
        this.students = students;
        this.portal = portal;
        this.notices = notices;
        this.files = files;
    }

    /* ── who is asking, what they may do, whom they reach ── */

    record Access(UUID agent, boolean head, Set<String> caps, String scope) {
        boolean has(String cap) {
            return caps.contains(cap);
        }
    }

    private static boolean has(Authentication auth, String authority) {
        for (GrantedAuthority a : auth.getAuthorities()) if (authority.equals(a.getAuthority())) return true;
        return false;
    }

    private static String blank(String s) {
        return s == null || s.isBlank() ? null : s.trim();
    }

    @SuppressWarnings("unchecked")
    private static List<String> texts(Object v) {
        try {
            if (v instanceof java.sql.Array a) return List.of((String[]) a.getArray());
            if (v instanceof List<?> l) return (List<String>) l;
            if (v instanceof String[] s) return List.of(s);
        } catch (java.sql.SQLException e) {
            throw new IllegalStateException(e);
        }
        return List.of();
    }

    private Access access(Authentication auth) {
        UUID me = UUID.fromString(auth.getName());
        boolean head = HEADS.stream().anyMatch(h -> has(auth, h));
        if (head) return new Access(me, true, Set.copyOf(ALL), "The University");
        Map<String, Object> row = jdbc.sql("SELECT helpdesk.agent_capabilities(:p) AS caps, (SELECT words FROM helpdesk.agent_student_scope(:p)) AS words")
                .param("p", me).query().singleRow();
        return new Access(me, false, Set.copyOf(texts(row.get("caps"))), row.get("words") == null ? "" : String.valueOf(row.get("words")));
    }

    /** a student outside the agent's reach is not found — the desk never says whether such a student exists */
    private void reach(Access a, UUID student) {
        if (a.head()) {
            jdbc.sql("SELECT 1 FROM people.student WHERE id = :s").param("s", student).query(Integer.class).optional().orElseThrow(() -> new NotFound("student", student));
            return;
        }
        if (!Boolean.TRUE.equals(jdbc.sql("SELECT helpdesk.agent_may_see_student(:p, :s)").param("p", a.agent()).param("s", student).query(Boolean.class).optional().orElse(false))) {
            throw new NotFound("student", student);
        }
    }

    private static void can(Access a, String cap) {
        if (!a.has(cap)) {
            throw new DomainRuleViolation("SUPPORT_CAPABILITY", "Your posting does not carry " + WORDS.getOrDefault(cap, cap.toLowerCase()) + ".",
                    new DomainRuleViolation.Remedy("Ask the Head of the ICT Support Desk to grant it on your posting; until then, document the issue on the ticket and escalate it.", "Head of ICT Support Desk"));
        }
    }

    /** the ticket a support act is done for: it must be the student's own, else it is not the ticket */
    private Map<String, Object> ticketOf(UUID ticket, UUID student) {
        if (ticket == null) return null;
        return jdbc.sql("""
                SELECT t.id, t.number, t.subject, t.status, c.name AS category
                  FROM helpdesk.ticket t JOIN helpdesk.category c ON c.id = t.category_id
                 WHERE t.id = :t AND t.requester_kind = 'STUDENT' AND t.requester_id = :s
                """).param("t", ticket).param("s", student).query().listOfRows().stream().findFirst().orElse(null);
    }

    private UUID act(UUID student, UUID ticket, String action, String field, String old, String now, String reason, String session, Integer semester) {
        return jdbc.sql("SELECT helpdesk.record_support_action(:s, :t, :a, :f, :o, :n, :r, :ses, :sem)")
                .param("s", student).param("t", ticket, Types.OTHER).param("a", action).param("f", field, Types.VARCHAR).param("o", old, Types.VARCHAR)
                .param("n", now, Types.VARCHAR).param("r", reason).param("ses", session, Types.VARCHAR).param("sem", semester, Types.INTEGER).query(UUID.class).single();
    }

    /** the student is told what ICT Support did, on the address the University reaches them at */
    private void tell(UUID student, String subject, String body) {
        String email = jdbc.sql("SELECT email FROM people.student_reach(:s)").param("s", student).query(String.class).optional().orElse(null);
        if (email != null && !email.isBlank()) notices.queueEmail(email, subject, body, "student", student, List.of());
    }

    private Map<String, Object> student(UUID id) {
        return jdbc.sql("""
                SELECT s.id, s.surname, s.other_names, s.matric_no, s.programme_code, p.name AS programme, p.dept_code, p.faculty_code
                  FROM people.student s JOIN ref.programme p ON p.code = s.programme_code WHERE s.id = :s
                """).param("s", id).query().listOfRows().stream().findFirst().orElseThrow(() -> new NotFound("student", id));
    }

    /* ── the search: within the agent's reach, by the server, a page at a time ── */

    private static final String FROM = """
              FROM people.student s
              JOIN ref.programme p ON p.code = s.programme_code
              LEFT JOIN ref.department d ON d.code = p.dept_code
              LEFT JOIN ref.faculty f ON f.code = p.faculty_code
              LEFT JOIN people.academic_position ap ON ap.student_id = s.id
             WHERE (:head OR EXISTS (SELECT 1 FROM helpdesk.agent_student_scope(:me) sc WHERE sc.global OR p.faculty_code = ANY(sc.faculties) OR p.dept_code = ANY(sc.departments)))
               AND (:fac::text IS NULL OR p.faculty_code = :fac)
               AND (:dept::text IS NULL OR p.dept_code = :dept)
               AND (:prog::text IS NULL OR p.code = :prog)
               AND (:level::int IS NULL OR s.current_level = :level)
               AND (:status::text IS NULL OR s.status = :status)
               AND (:session::text IS NULL OR s.entry_session = :session)
               AND (:q::text IS NULL
                    OR upper(s.surname) LIKE :qp OR upper(s.other_names) LIKE :qp OR upper(s.matric_no) LIKE :qp OR upper(s.admission_no) LIKE :qp
                    OR upper(s.jamb_reg_no) = :qu OR s.id::text = lower(:q)
                    OR EXISTS (SELECT 1 FROM people.student_contact c WHERE c.student_id = s.id AND (c.phone = :q OR lower(c.email) = lower(:q)))
                    OR EXISTS (SELECT 1 FROM people.biodata b WHERE b.student_id = s.id AND b.field IN ('mobile', 'alt_mobile', 'personal_email') AND lower(b.value) = lower(:q)))
            """;

    @GetMapping("/students")
    @PreAuthorize(AGENTS)
    @Transactional(readOnly = true)
    Map<String, Object> search(Authentication auth, @RequestParam(required = false) String q, @RequestParam(required = false) String fac,
                               @RequestParam(required = false) String dept, @RequestParam(required = false) String prog,
                               @RequestParam(required = false) Integer level, @RequestParam(required = false) String status,
                               @RequestParam(required = false) String session, @RequestParam(defaultValue = "1") int page,
                               @RequestParam(defaultValue = "50") int size, @RequestParam(defaultValue = "false") boolean export) {
        Access a = access(auth);
        can(a, "VIEW_STUDENT");
        if (export) can(a, "EXPORT_STUDENTS");
        int sz = Math.max(1, Math.min(size, export ? 2000 : 500));
        int pg = Math.max(1, page);
        String term = blank(q);
        var params = new LinkedHashMap<String, Object>();
        params.put("head", a.head());
        params.put("me", a.agent());
        params.put("fac", blank(fac) == null ? null : fac.trim().toUpperCase());
        params.put("dept", blank(dept) == null ? null : dept.trim().toUpperCase());
        params.put("prog", blank(prog) == null ? null : prog.trim().toUpperCase());
        params.put("level", level);
        params.put("status", blank(status) == null ? null : status.trim().toUpperCase());
        params.put("session", blank(session));
        params.put("q", term);
        params.put("qp", term == null ? null : term.toUpperCase() + "%");
        params.put("qu", term == null ? null : term.toUpperCase());
        var count = jdbc.sql("SELECT count(*) " + FROM);
        var rows = jdbc.sql("""
                SELECT s.id, s.surname, s.other_names, s.matric_no, s.jamb_reg_no, s.admission_no, s.sex, s.entry_session, s.current_level, s.status,
                       p.code AS programme_code, p.name AS programme, d.code AS dept_code, d.name AS department, f.code AS faculty_code, f.name AS faculty,
                       ap.current_session, ap.classification,
                       CASE WHEN ap.registered_current THEN 'REGISTERED' WHEN ap.enrolled_current THEN 'ENROLLED' ELSE 'NOT_REGISTERED' END AS registration
                """ + FROM + " ORDER BY s.surname, s.other_names, s.matric_no LIMIT :lim OFFSET :off");
        for (var e : params.entrySet()) {
            int type = switch (e.getKey()) { case "head" -> Types.BOOLEAN; case "me" -> Types.OTHER; case "level" -> Types.INTEGER; default -> Types.VARCHAR; };
            count = count.param(e.getKey(), e.getValue(), type);
            rows = rows.param(e.getKey(), e.getValue(), type);
        }
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("total", count.query(Long.class).single());
        out.put("page", pg);
        out.put("size", sz);
        out.put("rows", rows.param("lim", sz).param("off", (long) (pg - 1) * sz).query().listOfRows());
        out.put("scope", a.scope());
        out.put("capabilities", List.copyOf(a.caps()));
        if (pg == 1 && !export) {
            Map<String, Object> options = new LinkedHashMap<>();
            options.put("faculties", jdbc.sql("SELECT code, name FROM ref.faculty ORDER BY name").query().listOfRows());
            options.put("departments", jdbc.sql("SELECT code, name, faculty_code FROM ref.department WHERE ended_on IS NULL ORDER BY name").query().listOfRows());
            options.put("programmes", jdbc.sql("SELECT code, name, dept_code FROM ref.programme WHERE NOT coalesce(archived, false) ORDER BY name").query().listOfRows());
            options.put("sessions", jdbc.sql("SELECT DISTINCT entry_session FROM people.student WHERE entry_session IS NOT NULL ORDER BY entry_session DESC").query(String.class).list());
            out.put("options", options);
        }
        return out;
    }

    /* ── one student, as the support desk sees them ── */

    @GetMapping("/students/{id}")
    @PreAuthorize(AGENTS)
    @Transactional(readOnly = true)
    Map<String, Object> profile(Authentication auth, @PathVariable UUID id, @RequestParam(required = false) UUID ticket, @RequestParam(required = false) String session) {
        Access a = access(auth);
        reach(a, id);
        can(a, "VIEW_STUDENT");
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("record", students.record(id, blank(session)));
        Map<String, Object> me = new LinkedHashMap<>(portal.me(id));
        if (!a.has("VIEW_PAYMENTS")) { me.remove("fees"); me.remove("wallet"); me.remove("receipts"); }
        out.put("portal", me);
        out.put("contact", jdbc.sql("""
                SELECT c.phone, c.email, c.address, r.email AS reach_email, r.phone AS reach_phone
                  FROM people.student_reach(:s) r LEFT JOIN people.student_contact c ON c.student_id = :s
                """).param("s", id).query().listOfRows().stream().findFirst().orElse(Map.of()));
        Map<String, Object> position = jdbc.sql("SELECT * FROM people.academic_position WHERE student_id = :s").param("s", id).query().listOfRows().stream().findFirst().orElse(null);
        if (position != null) position = new LinkedHashMap<>(position) {{ put("issues", texts(get("issues"))); }};
        out.put("position", position);
        out.put("capabilities", List.copyOf(a.caps()));
        out.put("scope", a.scope());
        out.put("agent", jdbc.sql("SELECT helpdesk.person_name(:p)").param("p", a.agent()).query(String.class).optional().orElse(""));
        out.put("openedAt", java.time.OffsetDateTime.now().toString());
        out.put("ticket", ticketOf(ticket, id));
        out.put("actions", actions(id));
        out.put("tickets", tickets(id));
        out.put("history", jdbc.sql("""
                SELECT e.occurred_at, e.actor_office, e.action, e.subject_type, e.reason,
                       CASE WHEN p.id IS NULL THEN NULL ELSE p.surname || ', ' || p.given_names END AS actor_name
                  FROM audit.entries e LEFT JOIN iam.person p ON p.id = e.actor_id
                 WHERE e.subject_id = :s ORDER BY e.occurred_at DESC LIMIT 100
                """).param("s", id).query().listOfRows());
        out.put("hasPassport", portal.passportImage(id).isPresent());
        return out;
    }

    private List<Map<String, Object>> actions(UUID id) {
        return jdbc.sql("""
                SELECT a.id, a.action, a.field, a.old_value, a.new_value, a.reason, a.session, a.semester, a.at, a.agent_office,
                       helpdesk.person_name(a.agent_id) AS agent, a.ticket_id, t.number AS ticket_number
                  FROM helpdesk.support_action a LEFT JOIN helpdesk.ticket t ON t.id = a.ticket_id
                 WHERE a.student_id = :s ORDER BY a.at DESC LIMIT 200
                """).param("s", id).query().listOfRows();
    }

    private List<Map<String, Object>> tickets(UUID id) {
        return jdbc.sql("""
                SELECT t.id, t.number, t.subject, t.status, t.priority, c.name AS category, t.created_at, t.updated_at, helpdesk.person_name(t.assigned_to) AS agent
                  FROM helpdesk.ticket t JOIN helpdesk.category c ON c.id = t.category_id
                 WHERE t.requester_kind = 'STUDENT' AND t.requester_id = :s ORDER BY (t.status = 'CLOSED'), t.updated_at DESC LIMIT 100
                """).param("s", id).query().listOfRows();
    }

    @GetMapping("/students/{id}/tickets")
    @PreAuthorize(AGENTS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> studentTickets(Authentication auth, @PathVariable UUID id) {
        Access a = access(auth);
        reach(a, id);
        can(a, "VIEW_STUDENT");
        return tickets(id);
    }

    @GetMapping("/students/{id}/passport")
    @PreAuthorize(AGENTS)
    @Transactional(readOnly = true)
    ResponseEntity<byte[]> passport(Authentication auth, @PathVariable UUID id) {
        Access a = access(auth);
        reach(a, id);
        can(a, "VIEW_STUDENT");
        return portal.passportImage(id)
                .map(img -> ResponseEntity.ok().contentType(MediaType.IMAGE_JPEG).cacheControl(CacheControl.noStore()).body(img))
                .orElseGet(() -> ResponseEntity.notFound().build());
    }

    /* ── biodata: the open fields written, the sensitive ones requested of the Registry, the JAMB-read ones refused ── */

    public record FieldIn(@NotNull @Size(max = 4000) String value, @NotBlank @Size(max = 2000) String reason, UUID ticket) {
    }

    @PutMapping("/students/{id}/biodata/{field}")
    @PreAuthorize(AGENTS)
    @Transactional
    Map<String, Object> writeField(Authentication auth, @PathVariable UUID id, @PathVariable String field, @Valid @RequestBody FieldIn body) {
        Access a = access(auth);
        reach(a, id);
        String f = field.trim().toLowerCase();
        Map<String, Object> def = jdbc.sql("SELECT field, section, label, tier FROM ref.biodata_field WHERE field = :f").param("f", f)
                .query().listOfRows().stream().findFirst().orElseThrow(() -> new NotFound("biodata field", field));
        String tier = String.valueOf(def.get("tier"));
        String section = String.valueOf(def.get("section"));
        String label = String.valueOf(def.get("label"));
        String value = body.value().trim();
        String reason = body.reason().trim();
        UUID ticket = ticketOf(body.ticket(), id) == null ? null : body.ticket();
        if (body.ticket() != null && ticket == null) {
            throw new DomainRuleViolation("SUPPORT_TICKET", "That ticket is not this student's.", new DomainRuleViolation.Remedy("Open the student from their own ticket, or leave the ticket blank.", "You"));
        }
        String old = jdbc.sql("SELECT value FROM people.biodata WHERE student_id = :s AND field = :f").param("s", id).param("f", f).query(String.class).optional().orElse(null);
        if ("locked".equals(tier)) {
            throw new DomainRuleViolation("STU_FIELD_LOCKED", label + " is read from the JAMB record or derived; it is not changed on the portal.",
                    new DomainRuleViolation.Remedy("Corrected with JAMB or by the Registry, not here; escalate the ticket to the Academic Office.", "Academic Office"));
        }
        if ("approval".equals(tier) || SENSITIVE.contains(f)) {
            can(a, "REQUEST_CHANGE");
            if (value.isEmpty()) throw new DomainRuleViolation("STU_VALUE", "Say what " + label.toLowerCase() + " should read.", new DomainRuleViolation.Remedy("Enter the value the evidence shows.", "You"));
            UUID change = UUID.randomUUID();
            jdbc.sql("""
                    INSERT INTO people.biodata_change (id, student_id, field, from_value, to_value, evidence, state)
                    VALUES (:id, :s, :f, :from, :to, :ev, 'PENDING')
                    """).param("id", change).param("s", id).param("f", f).param("from", old, Types.VARCHAR).param("to", value)
                    .param("ev", "Raised by ICT Support: " + reason, Types.VARCHAR).update();
            act(id, ticket, "CHANGE_REQUESTED", f, old, value, reason, null, null);
            tell(id, "A change of your " + label.toLowerCase() + " was requested", "ICT Support raised a request for the Registry to change your " + label.toLowerCase() + " to \"" + value + "\". The Registry decides it; you will be told when it is.");
            return Map.of("field", f, "pending", true, "changeId", change, "tier", tier);
        }
        String cap = "contact".equals(section) ? "EDIT_CONTACT" : ("family".equals(section) || "origin".equals(section)) ? "EDIT_FAMILY" : "EDIT_PERSONAL";
        can(a, cap);
        if (f.endsWith("mobile") || "whatsapp".equals(f)) {
            if (!value.isEmpty() && !value.matches("^0[0-9]{10}$")) throw new DomainRuleViolation("STU_PHONE", "A Nigerian number is eleven digits beginning with 0.", new DomainRuleViolation.Remedy("Enter it as 08012345678.", "You"));
        }
        if (f.endsWith("email")) {
            if (!value.isEmpty() && !value.matches("^[^\\s@]+@[^\\s@]+\\.[A-Za-z]{2,}$")) throw new DomainRuleViolation("STU_EMAIL", "That is not an email address.", new DomainRuleViolation.Remedy("Enter it as name@example.com.", "You"));
        }
        if (value.isEmpty()) throw new DomainRuleViolation("STU_VALUE", "A support edit sets a value; it does not blank a field.", new DomainRuleViolation.Remedy("Enter the corrected value.", "You"));
        students.writeBiodata(id, f, new StudentService.BiodataIn(value, reason));
        if (CONTACT_MIRROR.contains(f)) {
            // where the University reaches the student is kept in step with what they are told it is
            Map<String, Object> c = jdbc.sql("SELECT phone, email, address FROM people.student_contact WHERE student_id = :s").param("s", id).query().listOfRows().stream().findFirst().orElse(Map.of());
            String phone = "mobile".equals(f) ? value : (String) c.get("phone");
            String email = "personal_email".equals(f) ? value : (String) c.get("email");
            String address = "term_address".equals(f) ? value : (String) c.get("address");
            portal.saveContact(id, phone, email, address);
        }
        act(id, ticket, "EDIT_CONTACT".equals(cap) ? "CONTACT_EDITED" : "EDIT_FAMILY".equals(cap) ? "FAMILY_EDITED" : "PERSONAL_EDITED", f, old, value, reason, null, null);
        tell(id, "Your " + label.toLowerCase() + " was updated by ICT Support", "Your " + label.toLowerCase() + " on the portal now reads \"" + value + "\" (it read \"" + (old == null ? "nothing" : old) + "\"). Reason: " + reason + ". If this is not what you asked for, reply to your support ticket.");
        return Map.of("field", f, "value", value, "old", old == null ? "" : old, "pending", false, "tier", tier);
    }

    /* ── the photograph ── */

    public record PhotoIn(@NotBlank String dataUrl, @NotBlank @Size(max = 2000) String reason, UUID ticket) {
    }

    @PutMapping("/students/{id}/passport")
    @PreAuthorize(AGENTS)
    @Transactional
    Map<String, Object> replacePassport(Authentication auth, @PathVariable UUID id, @Valid @RequestBody PhotoIn body) {
        Access a = access(auth);
        reach(a, id);
        can(a, "EDIT_PHOTO");
        String u = body.dataUrl().trim();
        int comma = u.indexOf(',');
        String head = comma > 0 ? u.substring(0, comma).toLowerCase() : "";
        String type = head.contains("image/png") ? "image/png" : head.contains("image/jpeg") || head.contains("image/jpg") ? "image/jpeg" : null;
        if (type == null) throw new DomainRuleViolation("PHOTO_TYPE", "A passport photograph is a JPEG or a PNG.", new DomainRuleViolation.Remedy("Choose a .jpg or .png file.", "You"));
        byte[] bytes;
        try {
            bytes = java.util.Base64.getDecoder().decode(u.substring(comma + 1));
        } catch (IllegalArgumentException e) {
            throw new DomainRuleViolation("PHOTO_BYTES", "The photograph could not be read.", new DomainRuleViolation.Remedy("Choose the file again.", "You"));
        }
        if (bytes.length == 0 || bytes.length > MAX_PHOTO) throw new DomainRuleViolation("PHOTO_SIZE", "A passport photograph is up to 2 MB.", new DomainRuleViolation.Remedy("Choose a smaller file.", "You"));
        UUID ticket = ticketOf(body.ticket(), id) == null ? null : body.ticket();
        UUID object = files.enabled() ? files.store("student_photo", id, "passport." + (type.endsWith("png") ? "png" : "jpg"), type, bytes) : null;
        boolean had = portal.passportImage(id).isPresent();
        jdbc.sql("""
                INSERT INTO people.student_photo (student_id, content, object_id, content_type, bytes, replaced_by, replaced_at, reason)
                VALUES (:s, :c, :o, :t, :n, :by, now(), :r)
                ON CONFLICT (student_id) DO UPDATE SET content = EXCLUDED.content, object_id = EXCLUDED.object_id, content_type = EXCLUDED.content_type,
                    bytes = EXCLUDED.bytes, replaced_by = EXCLUDED.replaced_by, replaced_at = now(), reason = EXCLUDED.reason
                """).param("s", id).param("c", object == null ? bytes : null, Types.BINARY).param("o", object, Types.OTHER).param("t", type).param("n", bytes.length)
                .param("by", a.agent()).param("r", body.reason().trim()).update();
        act(id, ticket, "PHOTO_REPLACED", "passport", had ? "a photograph" : "no photograph", bytes.length + " bytes " + type, body.reason().trim(), null, null);
        tell(id, "Your passport photograph was replaced by ICT Support", "ICT Support replaced the passport photograph on your portal. Reason: " + body.reason().trim() + ". If this is not what you asked for, reply to your support ticket.");
        return Map.of("replaced", true, "bytes", bytes.length, "store", object == null ? "database" : "object");
    }

    /* ── course registration, through the student portal's own service: the engine's rules unchanged ── */

    @GetMapping("/students/{id}/registration")
    @PreAuthorize(AGENTS)
    @Transactional(readOnly = true)
    Map<String, Object> registration(Authentication auth, @PathVariable UUID id, @RequestParam(required = false) String session, @RequestParam(defaultValue = "1") int semester) {
        Access a = access(auth);
        reach(a, id);
        can(a, "VIEW_STUDENT");
        String ses = blank(session) == null ? portal.sessionFor(id) : session.trim();
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("view", portal.registrationView(id, ses, semester));
        out.put("history", portal.registrationHistory(id));
        out.put("manage", a.has("MANAGE_REGISTRATION"));
        return out;
    }

    public record RegIn(@NotBlank String session, @Min(1) @Max(3) int semester, UUID offering, List<UUID> offerings,
                        @NotBlank @Size(max = 2000) String reason, UUID ticket) {
    }

    private String courseOf(UUID offering) {
        return offering == null ? null : jdbc.sql("SELECT o.course_code || ' — ' || c.title FROM catalogue.offering o JOIN catalogue.course c ON c.code = o.course_code WHERE o.id = :o")
                .param("o", offering).query(String.class).optional().orElse(String.valueOf(offering));
    }

    private UUID ticketFor(RegIn body, UUID id) {
        if (body.ticket() != null && ticketOf(body.ticket(), id) == null) {
            throw new DomainRuleViolation("SUPPORT_TICKET", "That ticket is not this student's.", new DomainRuleViolation.Remedy("Open the student from their own ticket, or leave the ticket blank.", "You"));
        }
        return body.ticket();
    }

    @PostMapping("/students/{id}/registration/{verb}")
    @PreAuthorize(AGENTS)
    @Transactional
    Map<String, Object> registrationAct(Authentication auth, @PathVariable UUID id, @PathVariable String verb, @Valid @RequestBody RegIn body) {
        Access a = access(auth);
        reach(a, id);
        can(a, "MANAGE_REGISTRATION");
        UUID ticket = ticketFor(body, id);
        String reason = body.reason().trim();
        Map<String, Object> result;
        switch (verb.toLowerCase()) {
            case "choose" -> {
                if (body.offerings() == null) throw new DomainRuleViolation("REG_OFFERINGS", "Name the courses chosen.", new DomainRuleViolation.Remedy("Tick the courses on the form.", "You"));
                result = portal.choose(id, body.session(), body.semester(), body.offerings());
                act(id, ticket, "REGISTRATION_CHOSEN", null, null, body.offerings().size() + " courses", reason, body.session(), body.semester());
                tell(id, "Your course registration was updated by ICT Support", "ICT Support set the courses on your " + body.session() + " semester " + body.semester() + " registration (" + body.offerings().size() + " courses). Reason: " + reason + ". Open Course Registration on your portal to see them.");
            }
            case "add" -> {
                if (body.offering() == null) throw new DomainRuleViolation("REG_OFFERING", "Name the course to add.", new DomainRuleViolation.Remedy("Choose it from the eligible courses.", "You"));
                String course = courseOf(body.offering());
                result = portal.addCourse(id, body.session(), body.semester(), body.offering());
                act(id, ticket, "COURSE_ADDED", course, "Not registered", "Registered", reason, body.session(), body.semester());
                tell(id, course + " was added to your course registration", "ICT Support added " + course + " to your " + body.session() + " semester " + body.semester() + " registration. Reason: " + reason + ".");
            }
            case "drop" -> {
                if (body.offering() == null) throw new DomainRuleViolation("REG_OFFERING", "Name the course to drop.", new DomainRuleViolation.Remedy("Choose it from the registration.", "You"));
                String course = courseOf(body.offering());
                result = portal.dropCourse(id, body.session(), body.semester(), body.offering());
                act(id, ticket, "COURSE_DROPPED", course, "Registered", "Not registered", reason, body.session(), body.semester());
                tell(id, course + " was removed from your course registration", "ICT Support removed " + course + " from your " + body.session() + " semester " + body.semester() + " registration. Reason: " + reason + ".");
            }
            case "submit" -> {
                result = portal.submit(id, body.session(), body.semester());
                act(id, ticket, "REGISTRATION_SUBMITTED", null, "Draft", "Submitted", reason, body.session(), body.semester());
                tell(id, "Your course registration was submitted by ICT Support", "ICT Support submitted your " + body.session() + " semester " + body.semester() + " registration for approval. Reason: " + reason + ".");
            }
            default -> throw new NotFound("registration act", verb);
        }
        Map<String, Object> out = new LinkedHashMap<>(result == null ? Map.of() : result);
        out.put("view", portal.registrationView(id, body.session(), body.semester()));
        return out;
    }

    /* ── payments and documents: read only ── */

    @GetMapping("/students/{id}/payments")
    @PreAuthorize(AGENTS)
    @Transactional(readOnly = true)
    Map<String, Object> payments(Authentication auth, @PathVariable UUID id) {
        Access a = access(auth);
        reach(a, id);
        can(a, "VIEW_PAYMENTS");
        Map<String, Object> me = portal.me(id);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("fees", me.get("fees"));
        out.put("session", me.get("session"));
        out.put("references", jdbc.sql("""
                SELECT id, session, reference, purpose, amount, generated_at, expires_at, confirmed_at, channel, note, receipt_no,
                       CASE WHEN confirmed_at IS NOT NULL THEN finance.payment_term(id) END AS term
                  FROM finance.payment_reference WHERE student_id = :s ORDER BY generated_at DESC LIMIT 200
                """).param("s", id).query().listOfRows());
        return out;
    }

    @GetMapping("/students/{id}/documents")
    @PreAuthorize(AGENTS)
    @Transactional(readOnly = true)
    Map<String, Object> documents(Authentication auth, @PathVariable UUID id) {
        Access a = access(auth);
        reach(a, id);
        can(a, "VIEW_DOCUMENTS");
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("admission", jdbc.sql("SELECT id, kind, detail, source, received_on, status FROM people.document WHERE student_id = :s ORDER BY kind").param("s", id).query().listOfRows());
        out.put("issued", jdbc.sql("""
                SELECT i.id, i.kind, i.verification_code, i.issuing_name, i.issued_on, i.issued_office, (i.supersedes IS NOT NULL) AS reissue,
                       EXISTS (SELECT 1 FROM credentials.revocation r WHERE r.credential_id = i.id) AS revoked
                  FROM credentials.issued i WHERE i.student_id = :s ORDER BY i.issued_on DESC
                """).param("s", id).query().listOfRows());
        out.put("receipts", jdbc.sql("""
                SELECT id, session, reference, purpose, amount, confirmed_at, channel, receipt_no
                  FROM finance.payment_reference WHERE student_id = :s AND receipt_no IS NOT NULL ORDER BY confirmed_at DESC LIMIT 100
                """).param("s", id).query().listOfRows());
        return out;
    }
}
