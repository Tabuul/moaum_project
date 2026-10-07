package ng.edu.moaum.portal.helpdesk;

import java.sql.Types;
import java.util.ArrayList;
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
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import ng.edu.moaum.portal.auth.PasswordResetService;
import ng.edu.moaum.portal.shared.DomainRuleViolation;
import ng.edu.moaum.portal.shared.FileObjects;
import ng.edu.moaum.portal.shared.NotFound;
import ng.edu.moaum.portal.student.StudentService;
import ng.edu.moaum.portal.studentportal.StudentAuthService;
import ng.edu.moaum.portal.studentportal.StudentPortalService;

import static ng.edu.moaum.portal.helpdesk.SupportAccess.AGENTS;
import static ng.edu.moaum.portal.helpdesk.SupportAccess.blank;
import static ng.edu.moaum.portal.helpdesk.SupportAccess.can;
import static ng.edu.moaum.portal.helpdesk.SupportAccess.texts;

/**
 * Student record support from the ICT Support Desk (V334, V346). A support agent reaches the students their postings' scopes
 * cover and does what the Head granted the postings that cover each student: reads the record the Registry's screens read,
 * edits the open contact, personal and family fields, replaces the photograph, raises a Registry change for a sensitive
 * field; manages a registration through the registration engine's own functions — every rule checked and named, the window
 * and the menu set aside only by a recorded support override on the student's ticket, never the fees, the units, the GST
 * gate, a lock, a mark or a closed semester; resets the password through the portal's own reset; raises and escalates the
 * student's tickets. Every act is written to the support ledger with its reason and, when a ticket is named, on that
 * ticket's timeline; the student is told. Status, programme, matriculation, results and money are not reachable from here.
 */
@RestController
@RequestMapping("/api/v1/helpdesk/support")
class StudentSupportController {

    private static final Set<String> CONTACT_MIRROR = Set.of("mobile", "personal_email", "term_address");
    /** fields that bear on identity and fee status: from the desk they go to the Registry as a request, whatever tier the student's own form gives them */
    private static final Set<String> SENSITIVE = Set.of("nationality", "country_of_origin", "state_of_origin", "lga");
    private static final long MAX_PHOTO = 2L * 1024 * 1024;
    /** the offices a ticket is escalated to from the student's record: the Bursary, the Director of ICT, the Examinations and Records, the Academic Office, the Registry */
    private static final Set<String> ESCALATE_TO = Set.of("bursar", "ict", "records", "academic", "registrar");

    private final JdbcClient jdbc;
    private final StudentService students;
    private final StudentPortalService portal;
    private final StudentAuthService studentAuth;
    private final PasswordResetService resets;
    private final FileObjects files;
    private final SupportAccess support;
    private final TicketNotifier notifier;

    StudentSupportController(JdbcClient jdbc, StudentService students, StudentPortalService portal, StudentAuthService studentAuth, PasswordResetService resets,
                             FileObjects files, SupportAccess support, TicketNotifier notifier) {
        this.jdbc = jdbc;
        this.students = students;
        this.portal = portal;
        this.studentAuth = studentAuth;
        this.resets = resets;
        this.files = files;
        this.support = support;
        this.notifier = notifier;
    }

    private static String ordinal(int semester) {
        return semester == 1 ? "first" : semester == 2 ? "second" : "third";
    }

    /* ── the search: within the agent's reach, by the server, a page at a time ── */

    private static final String SCOPE = "WITH sc AS MATERIALIZED (SELECT * FROM helpdesk.agent_scope_for(:me, 'VIEW_STUDENT')) ";
    private static final String FROM = """
              FROM people.student s
              JOIN ref.programme p ON p.code = s.programme_code
              LEFT JOIN ref.department d ON d.code = p.dept_code
              LEFT JOIN ref.faculty f ON f.code = p.faculty_code
              LEFT JOIN people.academic_position ap ON ap.student_id = s.id
              LEFT JOIN admissions.application app ON app.candidate_id = s.candidate_id
             WHERE (:head OR EXISTS (SELECT 1 FROM sc WHERE sc.global OR p.faculty_code = ANY(sc.faculties) OR p.dept_code = ANY(sc.departments)))
               AND (:fac::text IS NULL OR p.faculty_code = :fac)
               AND (:dept::text IS NULL OR p.dept_code = :dept)
               AND (:prog::text IS NULL OR p.code = :prog)
               AND (:level::int IS NULL OR s.current_level = :level)
               AND (:status::text IS NULL OR s.status = :status)
               AND (:session::text IS NULL OR s.entry_session = :session)
               AND (:q::text IS NULL
                    OR upper(s.surname) LIKE :qp OR upper(s.other_names) LIKE :qp OR upper(s.matric_no) LIKE :qp OR upper(s.admission_no) LIKE :qp
                    OR upper(s.jamb_reg_no) = :qu OR s.id = :uid
                    OR s.candidate_id = (SELECT x.candidate_id FROM admissions.application x WHERE x.application_no = :qu)
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
        SupportAccess.Access a = support.access(auth);
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
        params.put("uid", SupportAccess.uuidOrNull(term));
        var count = jdbc.sql(SCOPE + "SELECT count(*) " + FROM);
        var rows = jdbc.sql(SCOPE + """
                SELECT s.id, s.surname, s.other_names, s.matric_no, s.jamb_reg_no, s.admission_no, app.application_no, s.sex, s.entry_session, s.current_level, s.status,
                       p.code AS programme_code, p.name AS programme, d.code AS dept_code, d.name AS department, f.code AS faculty_code, f.name AS faculty,
                       ap.current_session, ap.classification,
                       CASE WHEN ap.registered_current THEN 'REGISTERED' WHEN ap.enrolled_current THEN 'ENROLLED' ELSE 'NOT_REGISTERED' END AS registration
                """ + FROM + " ORDER BY s.surname, s.other_names, s.matric_no LIMIT :lim OFFSET :off");
        for (var e : params.entrySet()) {
            int type = switch (e.getKey()) { case "head" -> Types.BOOLEAN; case "me", "uid" -> Types.OTHER; case "level" -> Types.INTEGER; default -> Types.VARCHAR; };
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
        SupportAccess.Access a = support.on(auth, id);
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
        String ses = portal.sessionFor(id);
        out.put("academic", jdbc.sql("""
                SELECT (SELECT ap.application_no FROM admissions.application ap WHERE ap.candidate_id = s.candidate_id) AS application_no,
                       :ses AS session, (SELECT coalesce(max(sm.number), 1) FROM policy.semester sm WHERE sm.session = :ses AND sm.state = 'OPEN') AS semester
                  FROM people.student s WHERE s.id = :s
                """).param("s", id).param("ses", ses, Types.VARCHAR).query().singleRow());
        out.put("capabilities", List.copyOf(a.caps()));
        out.put("center", center(a));
        out.put("scope", a.scope());
        out.put("agent", support.agentName(a.agent()));
        out.put("openedAt", java.time.OffsetDateTime.now().toString());
        out.put("ticket", support.ticketOf(ticket, id));
        out.put("actions", actions(id));
        out.put("tickets", tickets(id));
        out.put("history", jdbc.sql("""
                SELECT e.occurred_at, e.actor_office, e.action, e.subject_type, e.reason,
                       CASE WHEN p.id IS NULL THEN NULL ELSE p.surname || ', ' || p.given_names END AS actor_name
                  FROM audit.entries e LEFT JOIN iam.person p ON p.id = e.actor_id
                 WHERE e.subject_id = :s ORDER BY e.occurred_at DESC LIMIT 100
                """).param("s", id).query().listOfRows());
        out.put("hasPassport", portal.passportImage(id).isPresent());
        out.put("escalateTo", ESCALATE_TO.stream().sorted().toList());
        out.put("categories", jdbc.sql("SELECT code, name, fields::text AS fields FROM helpdesk.category WHERE active ORDER BY ordinal").query().listOfRows());
        return out;
    }

    /** the Support Action Center: only the acts the agent's postings allow on this student — the server refuses the rest anyway */
    private static List<Map<String, Object>> center(SupportAccess.Access a) {
        List<Map<String, Object>> out = new ArrayList<>();
        java.util.function.BiConsumer<String, String> add = (code, label) -> out.add(Map.of("code", code, "label", label));
        if (a.has("EDIT_CONTACT") || a.has("EDIT_PERSONAL") || a.has("EDIT_FAMILY") || a.has("EDIT_PHOTO") || a.has("REQUEST_CHANGE")) add.accept("EDIT_RECORD", "Edit student record");
        add.accept("VIEW_REGISTRATION", a.has("MANAGE_REGISTRATION") ? "Manage course registration" : "View course registration");
        if (a.has("MANAGE_REGISTRATION")) { add.accept("ADD_COURSE", "Add course"); add.accept("DROP_COURSE", "Drop course"); }
        if (a.has("OVERRIDE_REGISTRATION")) add.accept("OVERRIDE_REGISTRATION", "Support override");
        if (a.has("RESET_PASSWORD")) add.accept("RESET_PASSWORD", "Reset password");
        if (a.has("INVESTIGATE_PAYMENT") || a.has("VIEW_PAYMENTS")) add.accept("INVESTIGATE_PAYMENT", a.has("INVESTIGATE_PAYMENT") ? "Investigate payment" : "View payments");
        if (a.has("VERIFY_PAYMENT")) add.accept("VERIFY_PAYMENT", "Verify payment");
        if (a.has("SYNC_ENTITLEMENT")) add.accept("REFRESH_ENTITLEMENT", "Refresh payment entitlement");
        if (a.has("REGENERATE_RECEIPT")) add.accept("REGENERATE_RECEIPT", "Regenerate receipt");
        if (a.has("VIEW_DOCUMENTS")) add.accept("VIEW_DOCUMENTS", "View documents");
        add.accept("VIEW_TICKETS", "View support tickets");
        if (a.has("CREATE_TICKET")) add.accept("CREATE_TICKET", "Create support ticket");
        add.accept("ESCALATE", "Escalate");
        return out;
    }

    /** the Support Action History: date, agent, module, act, ticket, reason, and the result — the ticket's own state once it is resolved */
    private List<Map<String, Object>> actions(UUID id) {
        return jdbc.sql("""
                SELECT a.id, a.action, helpdesk.support_module(a.action) AS module, a.field, a.old_value, a.new_value, a.reason, a.session, a.semester, a.at, a.agent_office,
                       helpdesk.person_name(a.agent_id) AS agent, a.ticket_id, t.number AS ticket_number, t.status AS ticket_status,
                       a.summary, a.outcome, a.override, a.normal_rule, a.description, a.method, a.payment_reference,
                       CASE WHEN t.status IN ('RESOLVED', 'CLOSED') THEN 'RESOLVED' ELSE a.outcome END AS result
                  FROM helpdesk.support_action a LEFT JOIN helpdesk.ticket t ON t.id = a.ticket_id
                 WHERE a.student_id = :s ORDER BY a.at DESC LIMIT 200
                """).param("s", id).query().listOfRows();
    }

    private List<Map<String, Object>> tickets(UUID id) {
        return jdbc.sql("""
                SELECT t.id, t.number, t.subject, t.status, t.priority, c.name AS category, t.created_at, t.updated_at, helpdesk.person_name(t.assigned_to) AS agent,
                       t.escalated_office
                  FROM helpdesk.ticket t JOIN helpdesk.category c ON c.id = t.category_id
                 WHERE t.requester_kind = 'STUDENT' AND t.requester_id = :s ORDER BY (t.status = 'CLOSED'), t.updated_at DESC LIMIT 100
                """).param("s", id).query().listOfRows();
    }

    @GetMapping("/students/{id}/tickets")
    @PreAuthorize(AGENTS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> studentTickets(Authentication auth, @PathVariable UUID id) {
        can(support.on(auth, id), "VIEW_STUDENT");
        return tickets(id);
    }

    @GetMapping("/students/{id}/passport")
    @PreAuthorize(AGENTS)
    @Transactional(readOnly = true)
    ResponseEntity<byte[]> passport(Authentication auth, @PathVariable UUID id) {
        can(support.on(auth, id), "VIEW_STUDENT");
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
        SupportAccess.Access a = support.on(auth, id);
        String f = field.trim().toLowerCase();
        Map<String, Object> def = jdbc.sql("SELECT field, section, label, tier FROM ref.biodata_field WHERE field = :f").param("f", f)
                .query().listOfRows().stream().findFirst().orElseThrow(() -> new NotFound("biodata field", field));
        String tier = String.valueOf(def.get("tier"));
        String section = String.valueOf(def.get("section"));
        String label = String.valueOf(def.get("label"));
        String value = body.value().trim();
        String reason = body.reason().trim();
        UUID ticket = support.ticketFor(a, body.ticket(), id, false);
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
            support.act(id, ticket, "CHANGE_REQUESTED", f, old, value, reason, null, null,
                    Map.of("summary", "A change of " + label.toLowerCase() + " was requested of the Registry"));
            support.tell(id, "A change of your " + label.toLowerCase() + " was requested", "ICT Support raised a request for the Registry to change your " + label.toLowerCase() + " to \"" + value + "\". The Registry decides it; you will be told when it is.");
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
        support.act(id, ticket, "EDIT_CONTACT".equals(cap) ? "CONTACT_EDITED" : "EDIT_FAMILY".equals(cap) ? "FAMILY_EDITED" : "PERSONAL_EDITED", f, old, value, reason, null, null,
                Map.of("summary", label + " updated"));
        support.tell(id, "Your " + label.toLowerCase() + " was updated by ICT Support", "Your " + label.toLowerCase() + " on the portal now reads \"" + value + "\" (it read \"" + (old == null ? "nothing" : old) + "\"). Reason: " + reason + ". If this is not what you asked for, reply to your support ticket.");
        return Map.of("field", f, "value", value, "old", old == null ? "" : old, "pending", false, "tier", tier);
    }

    /* ── the photograph ── */

    public record PhotoIn(@NotBlank String dataUrl, @NotBlank @Size(max = 2000) String reason, UUID ticket) {
    }

    @PutMapping("/students/{id}/passport")
    @PreAuthorize(AGENTS)
    @Transactional
    Map<String, Object> replacePassport(Authentication auth, @PathVariable UUID id, @Valid @RequestBody PhotoIn body) {
        SupportAccess.Access a = support.on(auth, id);
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
        UUID ticket = support.ticketFor(a, body.ticket(), id, false);
        UUID object = files.enabled() ? files.store("student_photo", id, "passport." + (type.endsWith("png") ? "png" : "jpg"), type, bytes) : null;
        boolean had = portal.passportImage(id).isPresent();
        jdbc.sql("""
                INSERT INTO people.student_photo (student_id, content, object_id, content_type, bytes, replaced_by, replaced_at, reason)
                VALUES (:s, :c, :o, :t, :n, :by, now(), :r)
                ON CONFLICT (student_id) DO UPDATE SET content = EXCLUDED.content, object_id = EXCLUDED.object_id, content_type = EXCLUDED.content_type,
                    bytes = EXCLUDED.bytes, replaced_by = EXCLUDED.replaced_by, replaced_at = now(), reason = EXCLUDED.reason
                """).param("s", id).param("c", object == null ? bytes : null, Types.BINARY).param("o", object, Types.OTHER).param("t", type).param("n", bytes.length)
                .param("by", a.agent()).param("r", body.reason().trim()).update();
        support.act(id, ticket, "PHOTO_REPLACED", "passport", had ? "a photograph" : "no photograph", bytes.length + " bytes " + type, body.reason().trim(), null, null,
                Map.of("summary", "Passport photograph replaced"));
        support.tell(id, "Your passport photograph was replaced by ICT Support", "ICT Support replaced the passport photograph on your portal. Reason: " + body.reason().trim() + ". If this is not what you asked for, reply to your support ticket.");
        return Map.of("replaced", true, "bytes", bytes.length, "store", object == null ? "database" : "object");
    }

    /* ── course registration, through the registration engine: every rule named, the override recorded ── */

    /** the current registration as a support screen reads it: every course with its type, kind, level, semester and state, and the issues outstanding */
    private Map<String, Object> current(UUID id, String session, int semester) {
        Map<String, Object> out = new LinkedHashMap<>();
        Map<String, Object> reg = jdbc.sql("""
                SELECT r.id, r.status, r.level, r.submitted_at, r.approved_at, r.returned_comment, registration.units_of(r.id) AS units
                  FROM registration.course_registration r WHERE r.student_id = :s AND r.session = :ses AND r.semester = :sem
                """).param("s", id).param("ses", session).param("sem", semester).query().listOfRows().stream().findFirst().orElse(null);
        out.put("registration", reg);
        out.put("courses", reg == null ? List.of() : jdbc.sql("""
                SELECT e.offering_id, o.course_code, c.title, e.units, e.entry_type, c.kind, coalesce(co.basis, c.kind) AS basis, c.level, o.semester, o.session,
                       e.status, coalesce(r.approved_at, r.submitted_at) AS registered_at, e.support_override_at, e.support_override_reason,
                       EXISTS (SELECT 1 FROM assessment.score sc JOIN assessment.score_sheet sh ON sh.id = sc.sheet_id WHERE sc.student_id = r.student_id AND sh.offering_id = e.offering_id) AS marked
                  FROM registration.entry e
                  JOIN registration.course_registration r ON r.id = e.registration_id
                  JOIN catalogue.offering o ON o.id = e.offering_id
                  JOIN catalogue.course c ON c.code = o.course_code
                  LEFT JOIN people.student s ON s.id = r.student_id
                  LEFT JOIN catalogue.course_offer co ON co.course_code = c.code AND co.programme_code = s.programme_code AND co.level = r.level
                 WHERE e.registration_id = :r
                 ORDER BY (e.status = 'DROPPED'), o.course_code
                """).param("r", reg.get("id")).query().listOfRows());
        return out;
    }

    /** the student's registration in words: what stands in the way, from the engine's own answers */
    private static List<String> issues(Map<String, Object> view, Map<String, Object> current) {
        List<String> out = new ArrayList<>();
        if (view.get("window") instanceof Map<?, ?> w && w.get("gate") != null) out.add(String.valueOf(w.get("gate")));
        if (Boolean.FALSE.equals(view.get("clears"))) out.add("The semester's school fees are not cleared; the registration cannot be submitted until they are.");
        if (current.get("registration") instanceof Map<?, ?> r) {
            if ("RETURNED".equals(r.get("status"))) out.add("Returned by the level adviser" + (r.get("returned_comment") == null ? "." : ": " + r.get("returned_comment")));
            if (view.get("limit") instanceof Map<?, ?> lim && r.get("units") instanceof Number u && lim.get("min_units") instanceof Number min && u.intValue() < min.intValue()
                    && List.of("DRAFT", "RETURNED").contains(String.valueOf(r.get("status")))) {
                out.add("The draft carries " + u + " units; at least " + min + " are needed to submit.");
            }
        } else {
            out.add("No registration has been started for this semester.");
        }
        if (view.get("gst") instanceof Map<?, ?> g && Boolean.TRUE.equals(g.get("required")) && !Boolean.TRUE.equals(g.get("entitled"))) {
            out.add("The GST fee for the session is not paid; GST/EPS courses stay locked until it is.");
        }
        return out;
    }

    @GetMapping("/students/{id}/registration")
    @PreAuthorize(AGENTS)
    @Transactional(readOnly = true)
    Map<String, Object> registration(Authentication auth, @PathVariable UUID id, @RequestParam(required = false) String session, @RequestParam(defaultValue = "1") int semester) {
        SupportAccess.Access a = support.on(auth, id);
        can(a, "VIEW_STUDENT");
        String ses = blank(session) == null ? portal.sessionFor(id) : session.trim();
        Map<String, Object> out = new LinkedHashMap<>();
        Map<String, Object> view = portal.registrationView(id, ses, semester);
        Map<String, Object> current = current(id, ses, semester);
        out.put("view", view);
        out.put("current", current);
        out.put("issues", issues(view, current));
        out.put("history", portal.registrationHistory(id));
        out.put("manage", a.has("MANAGE_REGISTRATION"));
        out.put("override", a.has("OVERRIDE_REGISTRATION"));
        return out;
    }

    /** every rule the engine applies to adding or dropping this course for this student, judged now — what the confirmation dialog shows */
    @GetMapping("/students/{id}/registration/checks")
    @PreAuthorize(AGENTS)
    @Transactional(readOnly = true)
    Map<String, Object> checks(Authentication auth, @PathVariable UUID id, @RequestParam String session, @RequestParam @Min(1) @Max(3) int semester,
                               @RequestParam UUID offering, @RequestParam(defaultValue = "add") String verb) {
        SupportAccess.Access a = support.on(auth, id);
        can(a, "VIEW_STUDENT");
        String fn = "drop".equalsIgnoreCase(verb) ? "registration.support_drop_checks" : "registration.support_add_checks";
        List<Map<String, Object>> rules = jdbc.sql("SELECT * FROM " + fn + "(:s, :ses, :sem, :o) ORDER BY ord")
                .param("s", id).param("ses", session.trim()).param("sem", semester).param("o", offering).query().listOfRows();
        boolean hard = rules.stream().anyMatch(r -> !Boolean.TRUE.equals(r.get("passed")) && !Boolean.TRUE.equals(r.get("overridable")));
        boolean soft = rules.stream().anyMatch(r -> !Boolean.TRUE.equals(r.get("passed")) && Boolean.TRUE.equals(r.get("overridable")));
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("rules", rules);
        out.put("course", jdbc.sql("SELECT o.course_code, c.title, coalesce(o.units, c.units) AS units, o.session, o.semester FROM catalogue.offering o JOIN catalogue.course c ON c.code = o.course_code WHERE o.id = :o")
                .param("o", offering).query().listOfRows().stream().findFirst().orElse(null));
        out.put("allowed", !hard && !soft);
        out.put("overridable", !hard && soft);
        out.put("mayOverride", a.has("OVERRIDE_REGISTRATION"));
        return out;
    }

    /** the courses offered this session and semester beyond the student's menu, by code or title — what an override may add when the mapping is wrong */
    @GetMapping("/students/{id}/registration/offerings")
    @PreAuthorize(AGENTS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> offerings(Authentication auth, @PathVariable UUID id, @RequestParam String session, @RequestParam @Min(1) @Max(3) int semester,
                                        @RequestParam String q) {
        SupportAccess.Access a = support.on(auth, id);
        can(a, "MANAGE_REGISTRATION");
        String term = blank(q);
        if (term == null || term.length() < 2) return List.of();
        return jdbc.sql("""
                SELECT o.id AS offering_id, o.course_code, c.title, coalesce(o.units, c.units) AS units, c.level, c.kind, c.dept_code, d.name AS department
                  FROM catalogue.offering o JOIN catalogue.course c ON c.code = o.course_code LEFT JOIN ref.department d ON d.code = c.dept_code
                 WHERE o.session = :ses AND o.semester = :sem AND c.state <> 'ENDED'
                   AND (upper(o.course_code) LIKE :p OR upper(replace(o.course_code, ' ', '')) LIKE :p2 OR upper(c.title) LIKE :t)
                 ORDER BY o.course_code LIMIT 25
                """).param("ses", session.trim()).param("sem", semester).param("p", term.toUpperCase() + "%")
                .param("p2", term.toUpperCase().replace(" ", "") + "%").param("t", "%" + term.toUpperCase() + "%").query().listOfRows();
    }

    public record RegIn(@NotBlank String session, @Min(1) @Max(3) int semester, UUID offering, List<UUID> offerings,
                        @NotBlank @Size(max = 2000) String reason, UUID ticket, Boolean override, @Size(max = 4000) String description) {
    }

    private String courseOf(UUID offering) {
        return offering == null ? null : jdbc.sql("SELECT o.course_code || ' — ' || c.title FROM catalogue.offering o JOIN catalogue.course c ON c.code = o.course_code WHERE o.id = :o")
                .param("o", offering).query(String.class).optional().orElse(String.valueOf(offering));
    }

    private String codeOf(UUID offering) {
        return offering == null ? null : jdbc.sql("SELECT course_code FROM catalogue.offering WHERE id = :o").param("o", offering).query(String.class).optional().orElse(String.valueOf(offering));
    }

    /** the registration before and after an act: its state, its units and every course on it */
    private Map<String, Object> snapshot(UUID id, String session, int semester) {
        Map<String, Object> c = current(id, session, semester);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("status", c.get("registration") instanceof Map<?, ?> r ? r.get("status") : "NONE");
        out.put("units", c.get("registration") instanceof Map<?, ?> r ? r.get("units") : 0);
        List<String> courses = new ArrayList<>();
        for (Object o : (List<?>) c.get("courses")) if (o instanceof Map<?, ?> e) courses.add(e.get("course_code") + " " + String.valueOf(e.get("status")).toLowerCase());
        out.put("courses", courses);
        return out;
    }

    @SuppressWarnings("unchecked")
    private Map<String, Object> engine(String sql, Map<String, Object> params) {
        var spec = jdbc.sql(sql);
        for (var e : params.entrySet()) spec = spec.param(e.getKey(), e.getValue());
        return support.json().readValue(spec.query(String.class).single(), Map.class);
    }

    @PostMapping("/students/{id}/registration/{verb}")
    @PreAuthorize(AGENTS)
    @Transactional
    Map<String, Object> registrationAct(Authentication auth, @PathVariable UUID id, @PathVariable String verb, @Valid @RequestBody RegIn body) {
        SupportAccess.Access a = support.on(auth, id);
        can(a, "MANAGE_REGISTRATION");
        String v = verb.toLowerCase();
        String reason = body.reason().trim();
        String session = body.session().trim();
        int sem = body.semester();
        boolean override = Boolean.TRUE.equals(body.override());
        if (override) {
            can(a, "OVERRIDE_REGISTRATION");
            if (blank(body.description()) == null) {
                throw new DomainRuleViolation("SUPPORT_OVERRIDE_DESCRIPTION", "A support override describes the problem found.",
                        new DomainRuleViolation.Remedy("Say what the portal did wrong — the error, the missing course, the interrupted registration.", "You"));
            }
        }
        UUID ticket = support.ticketFor(a, body.ticket(), id, override);
        Map<String, Object> before = snapshot(id, session, sem);
        Map<String, Object> result;
        switch (v) {
            case "choose" -> {
                if (override) throw new DomainRuleViolation("SUPPORT_OVERRIDE_VERB", "The override applies to adding, dropping, restoring or submitting, one course at a time.", new DomainRuleViolation.Remedy("Add the course on its own.", "You"));
                if (body.offerings() == null) throw new DomainRuleViolation("REG_OFFERINGS", "Name the courses chosen.", new DomainRuleViolation.Remedy("Tick the courses on the form.", "You"));
                result = portal.choose(id, session, sem, body.offerings());
                support.act(id, ticket, "REGISTRATION_CHOSEN", null, null, body.offerings().size() + " courses", reason, session, sem,
                        Map.of("summary", body.offerings().size() + " courses chosen on the " + session + " " + ordinal(sem) + " semester registration", "before", before, "after", snapshot(id, session, sem)));
                support.tell(id, "Your course registration was updated by ICT Support", "ICT Support set the courses on your " + session + " " + ordinal(sem) + " semester registration (" + body.offerings().size() + " courses). Reason: " + reason + ". Open Course Registration on your portal to see them.");
            }
            case "add", "restore" -> {
                if (body.offering() == null) throw new DomainRuleViolation("REG_OFFERING", "Name the course to add.", new DomainRuleViolation.Remedy("Choose it from the eligible courses.", "You"));
                String code = codeOf(body.offering());
                result = engine("SELECT registration.support_add(:s, :ses, :sem, :o, :ov, :by, :r)::text",
                        Map.of("s", id, "ses", session, "sem", sem, "o", body.offering(), "ov", override, "by", a.agent(), "r", reason));
                boolean restored = Boolean.TRUE.equals(result.get("restored"));
                boolean overridden = Boolean.TRUE.equals(result.get("overridden"));
                String summary = code + (restored ? " restored to the " : " added to the ") + session + " " + ordinal(sem) + " semester registration" + (overridden ? " by support override" : "");
                Map<String, Object> d = new LinkedHashMap<>();
                d.put("summary", summary);
                d.put("before", before);
                d.put("after", snapshot(id, session, sem));
                if (overridden) { d.put("override", true); d.put("normalRule", result.get("normalRule")); d.put("description", body.description().trim()); }
                support.act(id, ticket, restored ? "COURSE_RESTORED" : "COURSE_ADDED", courseOf(body.offering()), restored ? "Dropped" : "Not registered", "Registered", reason, session, sem, d);
                support.tell(id, "Your course " + code + " was " + (restored ? "restored" : "added"),
                        "Your course " + code + " has been " + (restored ? "restored to" : "added to") + " your current course registration by ICT Support (" + session + ", " + ordinal(sem) + " semester). Open Course Registration on your portal to see it.");
            }
            case "drop" -> {
                if (body.offering() == null) throw new DomainRuleViolation("REG_OFFERING", "Name the course to drop.", new DomainRuleViolation.Remedy("Choose it from the registration.", "You"));
                String code = codeOf(body.offering());
                result = engine("SELECT registration.support_drop(:s, :ses, :sem, :o, :ov, :by, :r)::text",
                        Map.of("s", id, "ses", session, "sem", sem, "o", body.offering(), "ov", override, "by", a.agent(), "r", reason));
                boolean overridden = Boolean.TRUE.equals(result.get("overridden"));
                Map<String, Object> d = new LinkedHashMap<>();
                d.put("summary", code + " dropped from the " + session + " " + ordinal(sem) + " semester registration" + (overridden ? " by support override" : "") + "; the entry is kept as dropped");
                d.put("before", before);
                d.put("after", snapshot(id, session, sem));
                if (overridden) { d.put("override", true); d.put("normalRule", result.get("normalRule")); d.put("description", body.description().trim()); }
                support.act(id, ticket, "COURSE_DROPPED", courseOf(body.offering()), "Registered", "Dropped", reason, session, sem, d);
                support.tell(id, "Your course " + code + " was removed",
                        "Your course " + code + " has been removed from your current course registration by ICT Support (" + session + ", " + ordinal(sem) + " semester). Your earlier registrations and results are unchanged.");
            }
            case "submit" -> {
                result = engine("SELECT registration.support_submit(:s, :ses, :sem, :ov, :by, :r)::text",
                        Map.of("s", id, "ses", session, "sem", sem, "ov", override, "by", a.agent(), "r", reason));
                boolean overridden = Boolean.TRUE.equals(result.get("overridden"));
                Map<String, Object> d = new LinkedHashMap<>();
                d.put("summary", "The " + session + " " + ordinal(sem) + " semester registration submitted for the department's approval" + (overridden ? " by support override" : ""));
                d.put("before", before);
                d.put("after", snapshot(id, session, sem));
                d.put("outcome", String.valueOf(result.get("result")).startsWith("already") ? "NO_CHANGE" : "COMPLETED");
                if (overridden) { d.put("override", true); d.put("normalRule", result.get("normalRule")); d.put("description", body.description().trim()); }
                support.act(id, ticket, "REGISTRATION_SUBMITTED", null, String.valueOf(before.get("status")), "Submitted", reason, session, sem, d);
                support.tell(id, "Your course registration was submitted by ICT Support", "ICT Support submitted your " + session + " " + ordinal(sem) + " semester registration for your department's approval.");
            }
            default -> throw new NotFound("registration act", verb);
        }
        Map<String, Object> out = new LinkedHashMap<>(result == null ? Map.of() : result);
        out.put("view", portal.registrationView(id, session, sem));
        out.put("current", current(id, session, sem));
        return out;
    }

    /* ── the password: the portal's own reset; a temporary one only at the desk, on a ticket ── */

    public record PasswordIn(@NotBlank String method, @NotBlank @Size(max = 2000) String reason, UUID ticket) {
    }

    @PostMapping("/students/{id}/password")
    @PreAuthorize(AGENTS)
    @Transactional
    Map<String, Object> resetPassword(Authentication auth, @PathVariable UUID id, @Valid @RequestBody PasswordIn body) {
        SupportAccess.Access a = support.on(auth, id);
        can(a, "RESET_PASSWORD");
        String method = body.method().trim().toUpperCase();
        String reason = body.reason().trim();
        Map<String, Object> out = new LinkedHashMap<>();
        switch (method) {
            case "LINK", "RESET_LINK" -> {
                UUID ticket = support.ticketFor(a, body.ticket(), id, false);
                PasswordResetService.StudentReset sent = resets.forStudent(id);
                String to = String.join(" and ", java.util.stream.Stream.of(sent.email(), sent.phone()).filter(java.util.Objects::nonNull).toList());
                support.act(id, ticket, "PASSWORD_RESET", null, null, null, reason, null, null,
                        Map.of("method", "RESET_LINK", "authEventId", sent.resetId().toString(), "summary", "Password reset initiated: a one-hour link sent to " + to));
                out.put("method", "RESET_LINK");
                out.put("sentTo", to);
                out.put("expiresIn", "1 hour");
            }
            case "TEMPORARY", "TEMPORARY_PASSWORD" -> {
                UUID ticket = support.ticketFor(a, body.ticket(), id, true);
                StudentAuthService.Temporary t = studentAuth.issueTemporary(id, a.agent());
                support.act(id, ticket, "PASSWORD_RESET", null, null, null, reason, null, null,
                        Map.of("method", "TEMPORARY_PASSWORD", "authEventId", t.eventId().toString(),
                               "summary", "Temporary password issued at the desk: one sign-in, changed at it, until "
                                + t.expiresAt().atZoneSameInstant(java.time.ZoneId.of("Africa/Lagos")).format(java.time.format.DateTimeFormatter.ofPattern("d MMM yyyy, HH:mm"))));
                support.tell(id, "Your portal password was reset by ICT Support",
                        "Your portal password reset has been initiated by ICT Support at the desk. Sign in with the temporary password you were given; it works once, "
                        + "within 24 hours, and you will be asked to choose your own at once. If you did not ask for this, contact ICT Support.");
                out.put("method", "TEMPORARY_PASSWORD");
                out.put("temporaryPassword", t.password());
                out.put("expiresAt", t.expiresAt().toString());
                out.put("note", "Give it to the student now; it is not shown again and is kept only as a hash. It opens one sign-in, and the student must change it there.");
            }
            default -> throw new DomainRuleViolation("SUPPORT_RESET_METHOD", "A reset is a link to the student's address, or a temporary password at the desk.",
                    new DomainRuleViolation.Remedy("Choose LINK or TEMPORARY.", "You"));
        }
        return out;
    }

    /* ── tickets: raised for the student at the desk, escalated to the office that decides ── */

    public record TicketIn(@NotBlank @Size(max = 40) String category, @NotBlank @Size(max = 200) String subject, @NotBlank @Size(max = 8000) String description,
                           Map<String, String> details) {
    }

    @PostMapping("/students/{id}/tickets")
    @PreAuthorize(AGENTS)
    @Transactional
    Map<String, Object> raiseTicket(Authentication auth, @PathVariable UUID id, @Valid @RequestBody TicketIn body) {
        SupportAccess.Access a = support.on(auth, id);
        can(a, "CREATE_TICKET");
        Map<String, Object> s = jdbc.sql("""
                SELECT s.surname || ', ' || s.other_names AS name, coalesce(s.matric_no, s.admission_no) AS number, r.email, r.phone, p.dept_code, p.faculty_code
                  FROM people.student s JOIN ref.programme p ON p.code = s.programme_code LEFT JOIN LATERAL people.student_reach(s.id) r ON true WHERE s.id = :s
                """).param("s", id).query().singleRow();
        if (s.get("email") == null || String.valueOf(s.get("email")).isBlank()) {
            throw new DomainRuleViolation("SUPPORT_TICKET_EMAIL", "The record holds no email address for the ticket's updates.",
                    new DomainRuleViolation.Remedy("Correct the student's contact email first.", "You"));
        }
        String fields = jdbc.sql("SELECT fields::text FROM helpdesk.category WHERE code = upper(btrim(:c))").param("c", body.category()).query(String.class).optional().orElse("[]");
        Set<String> declared = new java.util.HashSet<>();
        for (var node : support.json().readTree(fields)) if (node.get("key") != null) declared.add(node.get("key").asText());
        Map<String, String> details = new LinkedHashMap<>();
        if (body.details() != null) body.details().forEach((k, v) -> {
            if (k != null && declared.contains(k) && v != null && !v.isBlank() && details.size() < 30) details.put(k, v.trim().substring(0, Math.min(v.trim().length(), 500)));
        });
        UUID t = jdbc.sql("SELECT helpdesk.submit('STUDENT', :id, :n, :num, :e, :ph, :d, :f, :c, :s, :desc, :j::jsonb)")
                .param("id", id).param("n", s.get("name")).param("num", s.get("number"), Types.VARCHAR).param("e", s.get("email"), Types.VARCHAR).param("ph", s.get("phone"), Types.VARCHAR)
                .param("d", s.get("dept_code"), Types.VARCHAR).param("f", s.get("faculty_code"), Types.VARCHAR).param("c", body.category()).param("s", body.subject().trim())
                .param("desc", body.description().trim()).param("j", support.json().writeValueAsString(details)).query(UUID.class).single();
        jdbc.sql("SELECT helpdesk.route(:t)").param("t", t).query(String.class).single();
        String agent = support.agentName(a.agent());
        jdbc.sql("SELECT helpdesk.comment(:t, 'AGENT', :a, :n, true, :b)").param("t", t).param("a", a.agent()).param("n", agent)
                .param("b", "Raised at the support desk on the student's behalf by " + agent + ".").query(UUID.class).single();
        notifier.submitted(t);
        String number = jdbc.sql("SELECT number FROM helpdesk.ticket WHERE id = :id").param("id", t).query(String.class).single();
        support.act(id, t, "TICKET_CREATED", null, null, number, "Raised at the desk: " + body.subject().trim(), null, null,
                Map.of("summary", "Ticket " + number + " raised for the student: " + body.subject().trim()));
        return Map.of("id", t, "number", number);
    }

    public record EscalateIn(@NotNull UUID ticket, @NotBlank @Size(max = 40) String office, @NotBlank @Size(max = 2000) String reason, @Size(max = 60) String paymentReference) {
    }

    /** a decision support cannot take goes to the office that owns it: money to the Bursary, a result to Examinations and Records, a system fault to the Director of ICT */
    @PostMapping("/students/{id}/escalate")
    @PreAuthorize(AGENTS)
    @Transactional
    Map<String, Object> escalate(Authentication auth, @PathVariable UUID id, @Valid @RequestBody EscalateIn body) {
        SupportAccess.Access a = support.on(auth, id);
        can(a, "VIEW_STUDENT");
        UUID ticket = support.ticketFor(a, body.ticket(), id, true);
        String office = body.office().trim().toLowerCase();
        if (!ESCALATE_TO.contains(office)) {
            throw new DomainRuleViolation("SUPPORT_ESCALATE_OFFICE", "A ticket is escalated from here to the Bursary, the Director of ICT, Examinations and Records, the Academic Office or the Registry.",
                    new DomainRuleViolation.Remedy("Choose one of those.", "You"));
        }
        String reason = body.reason().trim();
        jdbc.sql("SELECT helpdesk.escalate_to_office(:t, :o, :by, :r)").param("t", ticket).param("o", office).param("by", a.agent()).param("r", reason).query().singleRow();
        notifier.escalatedToOffice(ticket, office, reason);
        String words = jdbc.sql("SELECT label FROM ref.office WHERE code = :o").param("o", office).query(String.class).optional().orElse(office);
        Map<String, Object> d = new LinkedHashMap<>();
        d.put("summary", "Escalated to " + words);
        d.put("outcome", "ESCALATED");
        if (blank(body.paymentReference()) != null) d.put("paymentReference", body.paymentReference().trim().toUpperCase());
        support.act(id, ticket, "ESCALATED", null, null, words, reason, null, null, d);
        return Map.of("ticket", ticket, "office", office, "status", "WAITING_FOR_OFFICE");
    }

    /* ── the desk's own audit: every support act across the students the reader may audit ── */

    @GetMapping("/actions")
    @PreAuthorize(AGENTS)
    @Transactional(readOnly = true)
    Map<String, Object> audit(Authentication auth, @RequestParam(required = false) String module, @RequestParam(required = false) String action,
                              @RequestParam(required = false) UUID agent, @RequestParam(required = false) java.time.LocalDate from,
                              @RequestParam(required = false) java.time.LocalDate to, @RequestParam(defaultValue = "false") boolean overrides,
                              @RequestParam(defaultValue = "1") int page, @RequestParam(defaultValue = "50") int size, @RequestParam(defaultValue = "false") boolean export) {
        SupportAccess.Access a = support.access(auth);
        can(a, "VIEW_SUPPORT_AUDIT");
        if (export) can(a, "EXPORT_STUDENTS");
        int sz = Math.max(1, Math.min(size, export ? 5000 : 200));
        int pg = Math.max(1, page);
        String where = """
                  FROM helpdesk.support_action a
                  LEFT JOIN people.student s ON s.id = a.student_id
                  LEFT JOIN ref.programme p ON p.code = s.programme_code
                  LEFT JOIN jupeb.application ja ON ja.id = a.jupeb_application_id
                  LEFT JOIN helpdesk.ticket t ON t.id = a.ticket_id
                 WHERE (:head
                        OR (a.student_id IS NOT NULL AND EXISTS (SELECT 1 FROM sc WHERE sc.global OR p.faculty_code = ANY(sc.faculties) OR p.dept_code = ANY(sc.departments)))
                        OR (a.jupeb_application_id IS NOT NULL AND 'VIEW_SUPPORT_AUDIT' = ANY (helpdesk.agent_jupeb_capabilities(:me))))
                   AND (:module::text IS NULL OR helpdesk.support_module(a.action) = :module)
                   AND (:action::text IS NULL OR a.action = :action)
                   AND (:agent::uuid IS NULL OR a.agent_id = :agent)
                   AND (:from::date IS NULL OR a.at >= :from)
                   AND (:to::date IS NULL OR a.at < :to + 1)
                   AND (NOT :overrides OR a.override)
                """;
        String cte = "WITH sc AS MATERIALIZED (SELECT * FROM helpdesk.agent_scope_for(:me, 'VIEW_SUPPORT_AUDIT')) ";
        java.util.function.Function<String, JdbcClient.StatementSpec> with = sql -> jdbc.sql(sql)
                .param("head", a.head()).param("me", a.agent())
                .param("module", blank(module) == null ? null : module.trim().toUpperCase(), Types.VARCHAR)
                .param("action", blank(action) == null ? null : action.trim().toUpperCase(), Types.VARCHAR)
                .param("agent", agent, Types.OTHER).param("from", from, Types.DATE).param("to", to, Types.DATE).param("overrides", overrides);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("total", with.apply(cte + "SELECT count(*) " + where).query(Long.class).single());
        out.put("rows", with.apply(cte + """
                SELECT a.id, a.at, a.action, helpdesk.support_module(a.action) AS module, a.summary, a.reason, a.outcome, a.override, a.normal_rule, a.method,
                       a.payment_reference, a.session, a.semester, helpdesk.person_name(a.agent_id) AS agent, a.agent_office,
                       s.id AS student_id, a.jupeb_application_id, coalesce(s.surname || ', ' || s.other_names, ja.surname || ', ' || ja.first_name) AS student,
                       coalesce(s.matric_no, s.admission_no, ja.application_no) AS number,
                       t.id AS ticket_id, t.number AS ticket_number, CASE WHEN t.status IN ('RESOLVED', 'CLOSED') THEN 'RESOLVED' ELSE a.outcome END AS result
                """ + where + " ORDER BY a.at DESC LIMIT :n OFFSET :o").param("n", sz).param("o", (long) (pg - 1) * sz).query().listOfRows());
        out.put("page", pg);
        out.put("size", sz);
        if (pg == 1 && !export) {
            out.put("summary", with.apply(cte + """
                    SELECT helpdesk.support_module(a.action) AS module, count(*) AS acts, count(*) FILTER (WHERE a.override) AS overrides,
                           count(*) FILTER (WHERE a.at >= now() - interval '7 days') AS week
                    """ + where + " GROUP BY 1 ORDER BY 1").query().listOfRows());
        }
        return out;
    }

    /* ── payments and documents: read ── */

    @GetMapping("/students/{id}/payments")
    @PreAuthorize(AGENTS)
    @Transactional(readOnly = true)
    Map<String, Object> payments(Authentication auth, @PathVariable UUID id) {
        SupportAccess.Access a = support.on(auth, id);
        can(a, "VIEW_PAYMENTS");
        Map<String, Object> me = portal.me(id);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("fees", me.get("fees"));
        out.put("session", me.get("session"));
        out.put("references", jdbc.sql("""
                SELECT r.id, r.session, r.reference, r.purpose, r.amount, r.generated_at, r.expires_at, r.confirmed_at, r.channel, r.receipt_no,
                       CASE WHEN r.confirmed_at IS NOT NULL THEN finance.payment_term(r.id) END AS term,
                       CASE WHEN r.confirmed_at IS NOT NULL THEN 'CONFIRMED' WHEN r.expires_at < now() THEN 'EXPIRED' ELSE 'PENDING' END AS status,
                       ge.gateway, ge.gateway_ref, ge.outcome AS gateway_outcome, ge.received_at AS gateway_at
                  FROM finance.payment_reference r
                  LEFT JOIN LATERAL (SELECT e.gateway, e.gateway_ref, e.outcome, e.received_at FROM finance.gateway_event e
                                      WHERE e.reference = r.reference ORDER BY e.received_at DESC LIMIT 1) ge ON true
                 WHERE r.student_id = :s ORDER BY r.generated_at DESC LIMIT 200
                """).param("s", id).query().listOfRows());
        out.put("capabilities", List.copyOf(a.caps()));
        return out;
    }

    @GetMapping("/students/{id}/documents")
    @PreAuthorize(AGENTS)
    @Transactional(readOnly = true)
    Map<String, Object> documents(Authentication auth, @PathVariable UUID id) {
        SupportAccess.Access a = support.on(auth, id);
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
