package ng.edu.moaum.portal.hostel;

import java.math.BigDecimal;
import java.sql.Types;
import java.time.LocalDate;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

import ng.edu.moaum.portal.shared.AuditContextHolder;
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
 * The hostel upgrade (V290) on the accommodation module: the Dean of Student
 * Affairs' room categories, the workbook import, the special, Student Union
 * and Security allocations and the accountability report; the Bursar's fee
 * rules and hostel figures; and the student's eligibility checklist, the rooms
 * they may choose and their own reservation, held 48 hours. Every rule is the
 * database's: the category, the window, the prerequisites and the lock on the
 * bed are enforced in hostel.reserve_room and hostel.hold, not here.
 */
@RestController
@PreAuthorize("isAuthenticated()")
class HostelUpgradeController {

    /** the Dean of Student Affairs runs the hostels; the housing desk and Student Services keep their hands; the Registrar and the platform's administrators may act */
    static final String DEAN = "hasAnyAuthority('OFFICE_dsa','OFFICE_services','OFFICE_housing','OFFICE_registrar','OFFICE_admin','OFFICE_super')";
    /** the Bursar states the hostel fees and reads the money; the College's Finance Controller reads too */
    static final String FINANCE = "hasAnyAuthority('OFFICE_bursar','OFFICE_financecontroller','OFFICE_super')";
    static final String READERS = "hasAnyAuthority('OFFICE_dsa','OFFICE_services','OFFICE_housing','OFFICE_bursar','OFFICE_financecontroller','OFFICE_registrar','OFFICE_dregistrar','OFFICE_academic','OFFICE_admin','OFFICE_super','OFFICE_ict','OFFICE_audit','OFFICE_deputyaudit','OFFICE_vc','OFFICE_dvc')";
    static final String STUDENT = "hasAuthority('OFFICE_student')";

    private final JdbcClient jdbc;

    HostelUpgradeController(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    private static UUID student(Authentication auth) {
        return UUID.fromString(auth.getName());
    }

    private static String ses(String s, String y) {
        return s + "/" + y;
    }

    private static String blank(String v) {
        return v == null || v.isBlank() ? null : v.trim();
    }

    /** the session a student stands in (V289): their entry session while it is planned, else the current one */
    private String studentSession(UUID me, String asked) {
        if (blank(asked) != null) return asked.trim();
        return jdbc.sql("SELECT session FROM people.academic_context(:s)").param("s", me).query(String.class).optional()
                .orElseGet(() -> jdbc.sql("SELECT name FROM policy.academic_session WHERE state = 'CURRENT'").query(String.class).optional().orElse("2026/2027"));
    }

    /* ── the student: the checklist, the rooms, the reservation ─────────── */

    /** the checklist the dashboard shows: school fees, course registration, status, the window; and the rooms open to this student */
    @GetMapping("/api/v1/me/hostel/rooms")
    @PreAuthorize(STUDENT)
    @Transactional(readOnly = true)
    Map<String, Object> rooms(Authentication auth, @RequestParam(required = false) String session, @RequestParam(required = false) String hall,
                              @RequestParam(required = false) String type, @RequestParam(required = false) Integer minFree, @RequestParam(required = false) BigDecimal maxFee) {
        UUID me = student(auth);
        String s = studentSession(me, session);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("session", s);
        out.put("checklist", jdbc.sql("SELECT * FROM hostel.eligibility_checklist(:m, :s)").param("m", me).param("s", s).query().singleRow());
        out.put("setting", jdbc.sql("SELECT session, semester, state, allocation_method, requires_review, applications_open, applications_close, hold_hours, fee, drawn_at, require_school_fees, require_registration FROM hostel.session_setting WHERE session = :s")
                .param("s", s).query().listOfRows().stream().findFirst().orElse(null));
        out.put("rooms", jdbc.sql("""
                SELECT * FROM hostel.room_choices(:m, :s) rc
                 WHERE (:h::text IS NULL OR rc.hall_code = :h) AND (:t::text IS NULL OR rc.room_type = :t) AND (:f::int IS NULL OR rc.available >= :f) AND (:x::numeric IS NULL OR coalesce(rc.fee, 0) <= :x)
                """).param("m", me).param("s", s).param("h", blank(hall) == null ? null : hall.trim().toUpperCase(), Types.VARCHAR).param("t", blank(type) == null ? null : type.trim().toUpperCase(), Types.VARCHAR)
                .param("f", minFree, Types.INTEGER).param("x", maxFee, Types.NUMERIC).query().listOfRows());
        out.put("totalOpenRooms", jdbc.sql("SELECT count(*) FROM hostel.room_choices(:m, :s)").param("m", me).param("s", s).query(Long.class).single());
        out.put("halls", jdbc.sql("SELECT code, name, sex, kind, campus, location FROM hostel.hall WHERE ended_on IS NULL AND state = 'ACTIVE' ORDER BY name").query().listOfRows());
        out.put("roomTypes", jdbc.sql("SELECT code, label, beds FROM hostel.room_type WHERE active ORDER BY beds").query().listOfRows());
        return out;
    }

    public record ReserveIn(String session, @NotNull UUID roomId) {
    }

    /** the student's own reservation: a bed of the room, locked and held for the session's hold hours (48 by the University's rule) */
    @PostMapping("/api/v1/me/hostel/reserve")
    @PreAuthorize(STUDENT)
    @Transactional
    Map<String, Object> reserve(Authentication auth, @Valid @RequestBody ReserveIn body) {
        UUID me = student(auth);
        String s = studentSession(me, body.session());
        UUID id = jdbc.sql("SELECT hostel.reserve_room(:m, :s, :r)").param("m", me).param("s", s).param("r", body.roomId()).query(UUID.class).single();
        Map<String, Object> al = jdbc.sql("""
                SELECT al.id, al.reference_no, al.state, al.held_until, al.fee_amount, al.fee_status, h.name AS hall_name, r.block, r.room_no, b.label AS bed_label, r.beds AS capacity
                  FROM hostel.allocation al JOIN hostel.room r ON r.id = al.room_id JOIN hostel.hall h ON h.code = r.hall_code LEFT JOIN hostel.bed b ON b.id = al.bed_id WHERE al.id = :i
                """).param("i", id).query().singleRow();
        Map<String, Object> out = new LinkedHashMap<>(al);
        out.put("session", s);
        return out;
    }

    /* ── the Dean: categories, the room's category and state, the import ── */

    @GetMapping("/api/v1/hostel/room-categories")
    @PreAuthorize(READERS)
    List<Map<String, Object>> categories() {
        return jdbc.sql("SELECT code, label, general_selection, chargeable, active, note FROM hostel.room_category ORDER BY (code = 'GENERAL') DESC, label").query().listOfRows();
    }

    public record CategoryIn(@NotBlank @Size(max = 30) String code, @NotBlank @Size(max = 80) String label, Boolean generalSelection, Boolean chargeable, Boolean active, @Size(max = 300) String note) {
    }

    /** a category added or amended: the architecture takes any number without a change to the design */
    @PutMapping("/api/v1/hostel/room-categories")
    @PreAuthorize(DEAN)
    @Transactional
    Map<String, Object> saveCategory(@Valid @RequestBody CategoryIn body) {
        String code = body.code().trim().toUpperCase().replaceAll("[^A-Z0-9_]", "_");
        jdbc.sql("""
                INSERT INTO hostel.room_category (code, label, general_selection, chargeable, active, note) VALUES (:c, :l, :g, :ch, :a, :n)
                ON CONFLICT (code) DO UPDATE SET label = EXCLUDED.label, general_selection = EXCLUDED.general_selection, chargeable = EXCLUDED.chargeable, active = EXCLUDED.active, note = EXCLUDED.note
                """).param("c", code).param("l", body.label().trim()).param("g", Boolean.TRUE.equals(body.generalSelection())).param("ch", body.chargeable() == null || body.chargeable())
                .param("a", body.active() == null || body.active()).param("n", blank(body.note()), Types.VARCHAR).update();
        jdbc.sql("SELECT hostel.log(NULL, NULL, NULL, NULL, NULL, NULL, 'ROOM_CATEGORY_SAVED', NULL, :c, :n)").param("c", code + " · " + body.label().trim()).param("n", blank(body.note()), Types.VARCHAR).query().listOfRows();
        return Map.of("code", code);
    }

    public record RoomCategoryIn(@NotBlank @Size(max = 30) String category, @Size(max = 400) String reason) {
    }

    /** what a room is for: general, special, Student Union, Security or any category the Dean has added; the change is on the record */
    @PutMapping("/api/v1/hostel/rooms/{id}/category")
    @PreAuthorize(DEAN)
    @Transactional
    Map<String, Object> roomCategory(@PathVariable UUID id, @Valid @RequestBody RoomCategoryIn body) {
        jdbc.sql("SELECT hostel.set_room_category(:r, :c, :why)").param("r", id).param("c", body.category().trim().toUpperCase()).param("why", blank(body.reason()), Types.VARCHAR).query().listOfRows();
        return jdbc.sql("SELECT id, hall_code, block, room_no, beds, category, state FROM hostel.room WHERE id = :r").param("r", id).query().singleRow();
    }

    public record ImportIn(@NotNull List<Map<String, Object>> rows) {
    }

    /** the workbook's rows, previewed: NEW, EXISTING, UPDATED, DUPLICATE or ERROR, nothing written */
    @PostMapping("/api/v1/hostel/import/preview")
    @PreAuthorize(DEAN)
    @Transactional(readOnly = true)
    Map<String, Object> importPreview(@Valid @RequestBody ImportIn body) {
        return importRows(body.rows(), false);
    }

    /** the same rows committed: halls, blocks and rooms created or updated, never duplicated */
    @PostMapping("/api/v1/hostel/import")
    @PreAuthorize(DEAN)
    @Transactional
    Map<String, Object> importCommit(@Valid @RequestBody ImportIn body) {
        return importRows(body.rows(), true);
    }

    private Map<String, Object> importRows(List<Map<String, Object>> rows, boolean commit) {
        if (rows.size() > 5000) {
            throw new DomainRuleViolation("HOSTEL_IMPORT_TOO_LARGE", "The import takes up to 5,000 rows at a time; this file has " + rows.size() + ".",
                    new DomainRuleViolation.Remedy("Split the workbook and import it in parts.", "Dean of Student Affairs"));
        }
        String json;
        try {
            json = new tools.jackson.databind.ObjectMapper().writeValueAsString(rows);
        } catch (RuntimeException e) {
            throw new DomainRuleViolation("HOSTEL_IMPORT_UNREADABLE", "The rows could not be read.", new DomainRuleViolation.Remedy("Re-upload the workbook.", "Dean of Student Affairs"));
        }
        List<Map<String, Object>> result = jdbc.sql("SELECT * FROM hostel.import_rows(cast(:j AS jsonb), :c)").param("j", json).param("c", commit).query().listOfRows();
        Map<String, Long> counts = new LinkedHashMap<>();
        for (String k : List.of("NEW", "EXISTING", "UPDATED", "DUPLICATE", "ERROR")) counts.put(k, result.stream().filter(r -> k.equals(r.get("outcome"))).count());
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("committed", commit);
        out.put("received", rows.size());
        out.put("counts", counts);
        out.put("rows", result);
        return out;
    }

    /* ── the Dean: special, Student Union and Security allocations ───────── */

    /** every free bed the Dean may allocate, whatever the room's category, with the fee it carries */
    @GetMapping("/api/v1/hostel/sessions/{s}/{y}/allocatable-beds")
    @PreAuthorize(READERS)
    Map<String, Object> allocatable(@PathVariable String s, @PathVariable String y, @RequestParam(required = false) String category) {
        String session = ses(s, y);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("session", session);
        out.put("beds", jdbc.sql("SELECT * FROM hostel.allocatable_beds(:s) ab WHERE (:c::text IS NULL OR ab.category = :c)").param("s", session).param("c", blank(category) == null ? null : category.trim().toUpperCase(), Types.VARCHAR).query().listOfRows());
        out.put("categories", categories());
        return out;
    }

    public record SpecialIn(@NotNull UUID bedId, @Size(max = 30) String category, @Size(max = 40) String studentNumber, UUID personId, @Size(max = 120) String occupantName,
                            @NotBlank @Size(max = 600) String reason, LocalDate startOn, LocalDate endOn) {
    }

    /** a bed of a special, Student Union or Security room allocated to a student, a member of staff or a named person: payable or no charge by the category, recorded either way */
    @PostMapping("/api/v1/hostel/sessions/{s}/{y}/allocate-special")
    @PreAuthorize(DEAN)
    @Transactional
    Map<String, Object> allocateSpecial(@PathVariable String s, @PathVariable String y, @Valid @RequestBody SpecialIn body) {
        String session = ses(s, y);
        UUID studentId = null;
        if (blank(body.studentNumber()) != null) {
            studentId = jdbc.sql("SELECT id FROM people.student WHERE upper(matric_no) = upper(:n) OR upper(admission_no) = upper(:n) LIMIT 1").param("n", body.studentNumber().trim()).query(UUID.class).optional()
                    .orElseThrow(() -> new NotFound("student", body.studentNumber().trim()));
        }
        UUID id = jdbc.sql("SELECT hostel.allocate_special(:b, :s, :c, :st, :p, :n, :why, :from, :to)")
                .param("b", body.bedId()).param("s", session).param("c", blank(body.category()) == null ? null : body.category().trim().toUpperCase(), Types.VARCHAR)
                .param("st", studentId, Types.OTHER).param("p", body.personId(), Types.OTHER).param("n", blank(body.occupantName()), Types.VARCHAR)
                .param("why", body.reason().trim()).param("from", body.startOn(), Types.DATE).param("to", body.endOn(), Types.DATE).query(UUID.class).single();
        return jdbc.sql("SELECT * FROM hostel.accountability(:s) a WHERE a.allocation_id = :i").param("s", session).param("i", id).query().singleRow();
    }

    /** the special, Student Union and Security allocations of the session: occupant, room, category, fee, status, who allocated and why */
    @GetMapping("/api/v1/hostel/sessions/{s}/{y}/special")
    @PreAuthorize(READERS)
    Map<String, Object> special(@PathVariable String s, @PathVariable String y, @RequestParam(required = false) String category) {
        String session = ses(s, y);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("session", session);
        out.put("rows", jdbc.sql("SELECT * FROM hostel.accountability(:s) a WHERE a.category <> 'GENERAL' AND (:c::text IS NULL OR a.category = :c)").param("s", session)
                .param("c", blank(category) == null ? null : category.trim().toUpperCase(), Types.VARCHAR).query().listOfRows());
        out.put("rooms", jdbc.sql("SELECT * FROM hostel.room_board(:s) rb WHERE NOT rb.general_selection").param("s", session).query().listOfRows());
        out.put("categories", categories());
        return out;
    }

    /** who occupies or holds every bed of the session, paying, paid or not required: the report no occupied room is invisible to */
    @GetMapping("/api/v1/hostel/sessions/{s}/{y}/accountability")
    @PreAuthorize(READERS)
    Map<String, Object> accountability(@PathVariable String s, @PathVariable String y, @RequestParam(required = false) String hall, @RequestParam(required = false) String category, @RequestParam(required = false) String feeStatus) {
        String session = ses(s, y);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("session", session);
        out.put("rows", jdbc.sql("SELECT * FROM hostel.accountability(:s) a WHERE (:h::text IS NULL OR a.hall_code = :h) AND (:c::text IS NULL OR a.category = :c) AND (:f::text IS NULL OR a.fee_status = :f)")
                .param("s", session).param("h", blank(hall) == null ? null : hall.trim().toUpperCase(), Types.VARCHAR).param("c", blank(category) == null ? null : category.trim().toUpperCase(), Types.VARCHAR)
                .param("f", blank(feeStatus) == null ? null : feeStatus.trim().toUpperCase(), Types.VARCHAR).query().listOfRows());
        out.put("board", jdbc.sql("SELECT * FROM hostel.room_board(:s)").param("s", session).query().listOfRows());
        out.put("halls", jdbc.sql("SELECT code, name FROM hostel.hall WHERE ended_on IS NULL ORDER BY name").query().listOfRows());
        out.put("categories", categories());
        return out;
    }

    /* ── the Bursar: the fee rules and the money ─────────────────────────── */

    @GetMapping("/api/v1/hostel/sessions/{s}/{y}/fees")
    @PreAuthorize(READERS)
    Map<String, Object> fees(@PathVariable String s, @PathVariable String y) {
        String session = ses(s, y);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("session", session);
        out.put("baseFee", jdbc.sql("SELECT fee FROM hostel.session_setting WHERE session = :s").param("s", session).query(BigDecimal.class).optional().orElse(null));
        out.put("rules", jdbc.sql("""
                SELECT fr.id, fr.hall_code, h.name AS hall_name, fr.room_type, rt.label AS room_type_label, fr.category, rc.label AS category_label, fr.level, fr.amount, fr.note, fr.created_at, fr.ended_at,
                       coalesce(p.surname || ', ' || p.given_names, '') AS created_by_name
                  FROM hostel.fee_rule fr LEFT JOIN hostel.hall h ON h.code = fr.hall_code LEFT JOIN hostel.room_type rt ON rt.code = fr.room_type LEFT JOIN hostel.room_category rc ON rc.code = fr.category
                  LEFT JOIN iam.person p ON p.id = fr.created_by
                 WHERE fr.session = :s ORDER BY fr.ended_at IS NOT NULL, fr.created_at DESC
                """).param("s", session).query().listOfRows());
        out.put("categories", categories());
        out.put("halls", jdbc.sql("SELECT code, name FROM hostel.hall WHERE ended_on IS NULL ORDER BY name").query().listOfRows());
        out.put("roomTypes", jdbc.sql("SELECT code, label, beds FROM hostel.room_type WHERE active ORDER BY beds").query().listOfRows());
        return out;
    }

    public record FeeRuleIn(@Size(max = 8) String hall, @Size(max = 30) String roomType, @Size(max = 30) String category, Integer level, @NotNull BigDecimal amount, @Size(max = 300) String note) {
    }

    /** a fee rule stated by the Bursar: by hostel, room type, category and level, any of them; a live rule on the same dimensions is ended and replaced */
    @PutMapping("/api/v1/hostel/sessions/{s}/{y}/fees")
    @PreAuthorize(FINANCE)
    @Transactional
    Map<String, Object> saveFee(@PathVariable String s, @PathVariable String y, @Valid @RequestBody FeeRuleIn body) {
        String session = ses(s, y);
        if (body.amount().signum() < 0) throw new DomainRuleViolation("HOSTEL_FEE", "A hostel fee is zero or more.", new DomainRuleViolation.Remedy("State the amount in naira.", "Bursary"));
        UUID who = AuditContextHolder.required().actorId();
        String hall = blank(body.hall()) == null ? null : body.hall().trim().toUpperCase(), type = blank(body.roomType()) == null ? null : body.roomType().trim().toUpperCase(), cat = blank(body.category()) == null ? null : body.category().trim().toUpperCase();
        jdbc.sql("""
                UPDATE hostel.fee_rule SET ended_at = now(), ended_by = :who
                 WHERE session = :s AND ended_at IS NULL AND coalesce(hall_code, '') = coalesce(:h, '') AND coalesce(room_type, '') = coalesce(:t, '') AND coalesce(category, '') = coalesce(:c, '') AND coalesce(level, 0) = coalesce(:l, 0)
                """).param("who", who).param("s", session).param("h", hall, Types.VARCHAR).param("t", type, Types.VARCHAR).param("c", cat, Types.VARCHAR).param("l", body.level(), Types.INTEGER).update();
        UUID id = jdbc.sql("INSERT INTO hostel.fee_rule (session, hall_code, room_type, category, level, amount, note, created_by) VALUES (:s, :h, :t, :c, :l, :a, :n, :who) RETURNING id")
                .param("s", session).param("h", hall, Types.VARCHAR).param("t", type, Types.VARCHAR).param("c", cat, Types.VARCHAR).param("l", body.level(), Types.INTEGER).param("a", body.amount()).param("n", blank(body.note()), Types.VARCHAR).param("who", who)
                .query(UUID.class).single();
        jdbc.sql("SELECT hostel.log(NULL, NULL, NULL, :h, NULL, NULL, 'FEE_RULE_SAVED', NULL, :t, :n)").param("h", hall, Types.VARCHAR)
                .param("t", session + " · " + (hall == null ? "every hostel" : hall) + " · " + (type == null ? "every type" : type) + " · " + (cat == null ? "every category" : cat) + " · " + (body.level() == null ? "every level" : body.level() + " Level") + " · " + body.amount())
                .param("n", blank(body.note()), Types.VARCHAR).query().listOfRows();
        return Map.of("id", id);
    }

    @PostMapping("/api/v1/hostel/fees/{id}/end")
    @PreAuthorize(FINANCE)
    @Transactional
    Map<String, Object> endFee(@PathVariable UUID id) {
        int n = jdbc.sql("UPDATE hostel.fee_rule SET ended_at = now(), ended_by = :who WHERE id = :i AND ended_at IS NULL").param("who", AuditContextHolder.required().actorId()).param("i", id).update();
        if (n == 0) throw new NotFound("live hostel fee rule", id.toString());
        jdbc.sql("SELECT hostel.log(NULL, NULL, NULL, NULL, NULL, NULL, 'FEE_RULE_ENDED', NULL, :i, NULL)").param("i", id.toString()).query().listOfRows();
        return Map.of("ended", true);
    }

    /** the Bursar's hostel figures: charges, paid, outstanding, exempt (no charge, never revenue), by hostel, category and status, and every occupant's fee line */
    @GetMapping("/api/v1/hostel/sessions/{s}/{y}/finance")
    @PreAuthorize(READERS)
    Map<String, Object> finance(@PathVariable String s, @PathVariable String y) {
        String session = ses(s, y);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("session", session);
        out.put("summary", jdbc.sql("SELECT hostel.finance_summary(:s)::text").param("s", session).query(String.class).single());
        out.put("rows", jdbc.sql("SELECT * FROM hostel.accountability(:s)").param("s", session).query().listOfRows());
        return out;
    }

    /** the fee a bed carries for a student, as the desk quotes it before allocating */
    @GetMapping("/api/v1/hostel/sessions/{s}/{y}/fee-for")
    @PreAuthorize(READERS)
    Map<String, Object> feeFor(@PathVariable String s, @PathVariable String y, @RequestParam UUID roomId, @RequestParam(required = false) Integer level) {
        Map<String, Object> r = jdbc.sql("SELECT hall_code, room_type, category FROM hostel.room WHERE id = :r").param("r", roomId).query().singleRow();
        return jdbc.sql("SELECT amount, status, rule_id FROM hostel.fee_for(:s, :h, :t, :c, :l)").param("s", ses(s, y)).param("h", String.valueOf(r.get("hall_code")))
                .param("t", r.get("room_type") == null ? null : String.valueOf(r.get("room_type")), Types.VARCHAR).param("c", String.valueOf(r.get("category"))).param("l", level, Types.INTEGER).query().singleRow();
    }
}
