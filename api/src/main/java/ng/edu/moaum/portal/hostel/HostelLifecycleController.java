package ng.edu.moaum.portal.hostel;

import java.math.BigDecimal;
import java.sql.Types;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

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
 * The accommodation lifecycle (V261) on the hostel module (V030): the inventory of halls, blocks, rooms, beds, facilities and
 * assets; the session's window and its rules; the applications reviewed, seated by hand or by the draw; the allocation
 * accepted, declined, checked in, transferred, inspected, charged and cleared; the student's own screen. The rules are the
 * database's; this is the door. The housing desk and Student Services act; the offices that read accommodation read.
 */
@RestController
class HostelLifecycleController {

    private static final String OFFICE = "hasAnyAuthority('OFFICE_services','OFFICE_housing','OFFICE_registrar','OFFICE_admin','OFFICE_super')";
    private static final String READERS = "hasAnyAuthority('OFFICE_services','OFFICE_housing','OFFICE_bursar','OFFICE_registrar','OFFICE_dregistrar','OFFICE_academic','OFFICE_admin','OFFICE_super','OFFICE_ict','OFFICE_audit','OFFICE_vc','OFFICE_dvc')";
    private static final String STUDENT = "hasAuthority('OFFICE_student')";
    private static final Set<String> METHODS = Set.of("BALLOT", "FIRST_COME", "LEVEL", "FACULTY", "PROGRAMME", "SPECIAL_NEEDS", "MANUAL");

    private final JdbcClient jdbc;

    HostelLifecycleController(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    private static UUID student(Authentication auth) {
        return UUID.fromString(auth.getName());
    }

    private static String ses(String s, String y) {
        return s + "/" + y;
    }

    private String session(String asked) {
        if (asked != null && !asked.isBlank()) return asked;
        return jdbc.sql("SELECT name FROM policy.academic_session WHERE state = 'CURRENT'").query(String.class).optional().orElse("2026/2027");
    }

    private static String blank(String v) {
        return v == null || v.isBlank() ? null : v.trim();
    }

    /* ── the student ─────────────────────────────────────────────────────── */

    @GetMapping("/api/v1/me/hostel/full")
    @PreAuthorize(STUDENT)
    @Transactional(readOnly = true)
    Map<String, Object> mine(Authentication auth, @RequestParam(required = false) String session) {
        UUID me = student(auth);
        String s = session(session);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("session", s);
        Map<String, Object> view = jdbc.sql("SELECT * FROM hostel.student_view(:s, :n)").param("s", me).param("n", s).query().listOfRows().stream().findFirst().orElse(Map.of());
        out.put("view", view);
        out.put("sessions", jdbc.sql("SELECT session FROM hostel.session_setting ORDER BY session DESC").query(String.class).list());
        out.put("halls", jdbc.sql("""
                SELECT h.code, h.name, h.sex, h.kind, h.campus, h.location, h.description,
                       (SELECT count(*) FROM hostel.bed_board(:n) bb WHERE bb.hall_code = h.code AND bb.occupancy = 'AVAILABLE') AS free,
                       (SELECT count(*) FROM hostel.bed_board(:n) bb WHERE bb.hall_code = h.code AND bb.occupancy <> 'OUT_OF_SERVICE') AS beds
                  FROM hostel.hall h WHERE h.ended_on IS NULL AND h.state = 'ACTIVE' ORDER BY h.name
                """).param("n", s).query().listOfRows());
        out.put("roomTypes", jdbc.sql("SELECT code, label, beds FROM hostel.room_type WHERE active ORDER BY beds").query().listOfRows());
        out.put("history", jdbc.sql("SELECT * FROM hostel.history(:s)").param("s", me).query().listOfRows());
        Object alloc = view.get("allocation_id");
        if (alloc != null) {
            UUID a = (UUID) alloc;
            out.put("roommates", jdbc.sql("SELECT * FROM hostel.roommates(:a)").param("a", a).query().listOfRows());
            out.put("transfers", jdbc.sql("SELECT id, requested_hall, requested_type, reason, state, submitted_at, decided_at, decision_note FROM hostel.transfer_request WHERE allocation_id = :a ORDER BY submitted_at DESC").param("a", a).query().listOfRows());
            out.put("charges", jdbc.sql("SELECT id, description, charge, reference, raised_at, settled_at, waived_at, waived_reason FROM hostel.damage_charge WHERE allocation_id = :a ORDER BY raised_at").param("a", a).query().listOfRows());
            out.put("clearanceItems", jdbc.sql("""
                    SELECT i.id, i.requirement, r.label, i.state, i.decided_at, i.remarks FROM hostel.clearance_item i JOIN hostel.clearance_requirement r ON r.code = i.requirement
                     JOIN hostel.clearance c ON c.id = i.clearance_id WHERE c.allocation_id = :a ORDER BY r.ord
                    """).param("a", a).query().listOfRows());
            out.put("inspections", jdbc.sql("SELECT kind, inspected_at, condition, cleanliness, damages, keys_returned, card_returned, remarks FROM hostel.inspection WHERE allocation_id = :a ORDER BY inspected_at").param("a", a).query().listOfRows());
            out.put("maintenance", jdbc.sql("""
                    SELECT m.id, m.issue, m.category, m.priority, m.raised_at, m.state, m.note, m.decided_at, st.surname || ', ' || st.other_names AS raised_by_name
                      FROM hostel.maintenance_request m JOIN people.student st ON st.id = m.raised_by JOIN hostel.allocation al ON al.id = :a AND al.room_id = m.room_id
                     ORDER BY m.raised_at DESC
                    """).param("a", a).query().listOfRows());
        } else {
            out.put("roommates", List.of()); out.put("transfers", List.of()); out.put("charges", List.of()); out.put("clearanceItems", List.of()); out.put("inspections", List.of()); out.put("maintenance", List.of());
        }
        out.put("events", jdbc.sql("SELECT action, from_value, to_value, note, at FROM hostel.event WHERE student_id = :s ORDER BY at DESC LIMIT 60").param("s", me).query().listOfRows());
        return out;
    }

    public record ApplyIn(String session, @Size(max = 8) String hall, @Size(max = 20) String category, @Size(max = 400) String note, @Size(max = 30) String roomType,
                          @Size(max = 12) String block, @Size(max = 600) String specialNeed, @Size(max = 40) String roommateNumber, @Size(max = 300) String roommateNote) {
    }

    @PostMapping("/api/v1/me/hostel/apply-full")
    @PreAuthorize(STUDENT)
    @Transactional
    Map<String, Object> apply(Authentication auth, @Valid @RequestBody ApplyIn body) {
        UUID me = student(auth);
        String s = session(body.session());
        UUID roommate = null;
        if (blank(body.roommateNumber()) != null) {
            roommate = jdbc.sql("SELECT id FROM people.student WHERE upper(matric_no) = upper(:n) OR upper(admission_no) = upper(:n) LIMIT 1").param("n", body.roommateNumber().trim()).query(UUID.class).optional()
                    .orElseThrow(() -> new DomainRuleViolation("HOSTEL_ROOMMATE", "No student carries the number " + body.roommateNumber().trim() + ".", new DomainRuleViolation.Remedy("Give the roommate's matriculation or admission number as it is on their record.", "You")));
        }
        UUID id = jdbc.sql("SELECT hostel.apply(:s, :n, :h, :c, :t, :rt, :b, :sp, :rm, :rn)").param("s", me).param("n", s)
                .param("h", blank(body.hall()) == null ? null : body.hall().trim().toUpperCase(), Types.VARCHAR).param("c", blank(body.category()), Types.VARCHAR).param("t", blank(body.note()), Types.VARCHAR)
                .param("rt", blank(body.roomType()), Types.VARCHAR).param("b", blank(body.block()), Types.VARCHAR).param("sp", blank(body.specialNeed()), Types.VARCHAR)
                .param("rm", roommate, Types.OTHER).param("rn", blank(body.roommateNote()), Types.VARCHAR).query(UUID.class).single();
        return Map.of("applicationId", id, "session", s, "reference", jdbc.sql("SELECT reference FROM hostel.application WHERE id = :i").param("i", id).query(String.class).single());
    }

    public record ReasonIn(String session, @NotBlank @Size(max = 600) String reason) {
    }

    private UUID myApplication(UUID me, String s) {
        return jdbc.sql("SELECT id FROM hostel.application WHERE student_id = :s AND session = :n AND state <> 'WITHDRAWN'").param("s", me).param("n", s).query(UUID.class).optional()
                .orElseThrow(() -> new NotFound("hostel application for", s));
    }

    private UUID myAllocation(UUID me, String s) {
        return jdbc.sql("SELECT id FROM hostel.allocation WHERE student_id = :s AND session = :n AND lapsed_at IS NULL AND ended_at IS NULL").param("s", me).param("n", s).query(UUID.class).optional()
                .orElseThrow(() -> new NotFound("hostel allocation for", s));
    }

    @PostMapping("/api/v1/me/hostel/withdraw")
    @PreAuthorize(STUDENT)
    @Transactional
    Map<String, Object> withdraw(Authentication auth, @Valid @RequestBody ReasonIn body) {
        String s = session(body.session());
        jdbc.sql("SELECT hostel.withdraw(:a, :r)").param("a", myApplication(student(auth), s)).param("r", body.reason().trim()).query().listOfRows();
        return Map.of("ok", true);
    }

    public record AcceptIn(String session, Integer rulesVersion) {
    }

    @PostMapping("/api/v1/me/hostel/accept")
    @PreAuthorize(STUDENT)
    @Transactional
    Map<String, Object> accept(Authentication auth, @RequestBody AcceptIn body) {
        String s = session(body.session());
        UUID me = student(auth);
        jdbc.sql("SELECT hostel.accept(:a, :s, :v)").param("a", myAllocation(me, s)).param("s", me).param("v", body.rulesVersion(), Types.INTEGER).query().listOfRows();
        return Map.of("ok", true);
    }

    @PostMapping("/api/v1/me/hostel/decline")
    @PreAuthorize(STUDENT)
    @Transactional
    Map<String, Object> decline(Authentication auth, @Valid @RequestBody ReasonIn body) {
        String s = session(body.session());
        UUID me = student(auth);
        jdbc.sql("SELECT hostel.decline(:a, :s, :r)").param("a", myAllocation(me, s)).param("s", me).param("r", body.reason().trim()).query().listOfRows();
        return Map.of("ok", true);
    }

    public record TransferIn(String session, @Size(max = 8) String hall, @Size(max = 30) String roomType, @NotBlank @Size(max = 600) String reason) {
    }

    @PostMapping("/api/v1/me/hostel/transfer")
    @PreAuthorize(STUDENT)
    @Transactional
    Map<String, Object> requestTransfer(Authentication auth, @Valid @RequestBody TransferIn body) {
        String s = session(body.session());
        UUID id = jdbc.sql("SELECT hostel.request_transfer(:s, :n, :h, :t, :r)").param("s", student(auth)).param("n", s)
                .param("h", blank(body.hall()) == null ? null : body.hall().trim().toUpperCase(), Types.VARCHAR).param("t", blank(body.roomType()), Types.VARCHAR).param("r", body.reason().trim()).query(UUID.class).single();
        return Map.of("id", id, "state", "SUBMITTED");
    }

    public record CheckoutIn(String session, LocalDate on, @Size(max = 600) String reason) {
    }

    @PostMapping("/api/v1/me/hostel/checkout")
    @PreAuthorize(STUDENT)
    @Transactional
    Map<String, Object> requestCheckout(Authentication auth, @RequestBody CheckoutIn body) {
        String s = session(body.session());
        jdbc.sql("SELECT hostel.request_checkout(:s, :n, :d, :r)").param("s", student(auth)).param("n", s).param("d", body.on(), Types.DATE).param("r", blank(body.reason()), Types.VARCHAR).query().listOfRows();
        return Map.of("ok", true);
    }

    public record IssueIn(String session, @NotBlank @Size(max = 600) String issue, String category, String priority) {
    }

    @PostMapping("/api/v1/me/hostel/maintenance-full")
    @PreAuthorize(STUDENT)
    @Transactional
    Map<String, Object> raise(Authentication auth, @Valid @RequestBody IssueIn body) {
        String s = session(body.session());
        UUID me = student(auth);
        Map<String, Object> al = jdbc.sql("SELECT id, room_id, bed_id, state FROM hostel.allocation WHERE student_id = :s AND session = :n AND lapsed_at IS NULL AND ended_at IS NULL").param("s", me).param("n", s).query().listOfRows().stream().findFirst()
                .orElseThrow(() -> new DomainRuleViolation("HOSTEL_NO_ROOM", "No room stands against you this session.", new DomainRuleViolation.Remedy("A maintenance request is raised from a room you occupy.", "You")));
        if (!Set.of("CONFIRMED", "ACCEPTED", "CHECKED_IN").contains(String.valueOf(al.get("state")))) {
            throw new DomainRuleViolation("HOSTEL_NO_ROOM", "The bed is held, not yet yours; pay the fee first.", new DomainRuleViolation.Remedy("A maintenance request is raised from a confirmed room.", "You"));
        }
        String cat = blank(body.category()) == null ? "OTHER" : body.category().trim().toUpperCase();
        String pri = blank(body.priority()) == null ? "NORMAL" : body.priority().trim().toUpperCase();
        UUID id = jdbc.sql("INSERT INTO hostel.maintenance_request (room_id, raised_by, issue, category, priority, bed_id) VALUES (:r, :s, :i, :c, :p, :b) RETURNING id")
                .param("r", al.get("room_id")).param("s", me).param("i", body.issue().trim()).param("c", cat).param("p", pri).param("b", al.get("bed_id"), Types.OTHER).query(UUID.class).single();
        jdbc.sql("SELECT hostel.log(NULL, :a, :s, NULL, :r, :b, 'MAINTENANCE_RAISED', NULL, :c, :i)").param("a", al.get("id")).param("s", me).param("r", al.get("room_id")).param("b", al.get("bed_id"), Types.OTHER).param("c", cat).param("i", body.issue().trim()).query().listOfRows();
        jdbc.sql("SELECT hostel.tell_desk('A hostel maintenance request', :b)").param("b", "A " + pri.toLowerCase() + " " + cat.toLowerCase() + " request has been raised from a room: " + body.issue().trim()).query().listOfRows();
        return Map.of("id", id, "state", "RAISED");
    }

    /* ── the inventory ───────────────────────────────────────────────────── */

    @GetMapping("/api/v1/hostel/inventory")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> inventory(@RequestParam(required = false) String session) {
        String s = session(session);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("session", s);
        out.put("kinds", jdbc.sql("SELECT code, label, active FROM hostel.hall_kind ORDER BY label").query().listOfRows());
        out.put("roomTypes", jdbc.sql("SELECT code, label, beds, active FROM hostel.room_type ORDER BY beds").query().listOfRows());
        out.put("facilities", jdbc.sql("SELECT code, label, active FROM hostel.facility ORDER BY label").query().listOfRows());
        out.put("halls", jdbc.sql("SELECT * FROM hostel.hall WHERE ended_on IS NULL ORDER BY name").query().listOfRows());
        out.put("blocks", jdbc.sql("SELECT * FROM hostel.block ORDER BY hall_code, code").query().listOfRows());
        out.put("rooms", jdbc.sql("""
                SELECT r.id, r.hall_code, h.name AS hall_name, r.block, r.block_id, r.floor, r.room_no, r.room_type, rt.label AS room_type_label, r.beds, r.sex, r.state, r.state_reason, r.note,
                       count(*) FILTER (WHERE bb.occupancy = 'OCCUPIED') AS occupied, count(*) FILTER (WHERE bb.occupancy = 'RESERVED') AS reserved,
                       count(*) FILTER (WHERE bb.occupancy = 'AVAILABLE') AS available, count(*) FILTER (WHERE bb.occupancy = 'MAINTENANCE') AS maintenance,
                       count(*) FILTER (WHERE bb.occupancy = 'OUT_OF_SERVICE') AS out_of_service,
                       (SELECT string_agg(f.label || CASE WHEN rf.quantity > 1 THEN ' ×' || rf.quantity ELSE '' END, ', ' ORDER BY f.label) FROM hostel.room_facility rf JOIN hostel.facility f ON f.code = rf.facility_code WHERE rf.room_id = r.id) AS facilities
                  FROM hostel.room r JOIN hostel.hall h ON h.code = r.hall_code LEFT JOIN hostel.room_type rt ON rt.code = r.room_type
                  LEFT JOIN hostel.bed_board(:s) bb ON bb.room_id = r.id
                 WHERE h.ended_on IS NULL
                 GROUP BY r.id, h.name, rt.label ORDER BY h.name, r.block, r.floor, r.room_no
                """).param("s", s).query().listOfRows());
        out.put("assets", jdbc.sql("SELECT a.*, h.name AS hall_name, r.room_no, r.block FROM hostel.asset a JOIN hostel.hall h ON h.code = a.hall_code LEFT JOIN hostel.room r ON r.id = a.room_id ORDER BY h.name, a.tag").query().listOfRows());
        return out;
    }

    @GetMapping("/api/v1/hostel/rooms/{id}")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> room(@PathVariable UUID id, @RequestParam(required = false) String session) {
        String s = session(session);
        Map<String, Object> r = jdbc.sql("SELECT r.*, h.name AS hall_name, h.sex AS hall_sex, rt.label AS room_type_label FROM hostel.room r JOIN hostel.hall h ON h.code = r.hall_code LEFT JOIN hostel.room_type rt ON rt.code = r.room_type WHERE r.id = :id")
                .param("id", id).query().listOfRows().stream().findFirst().orElseThrow(() -> new NotFound("room", id));
        Map<String, Object> out = new LinkedHashMap<>(r);
        out.put("session", s);
        out.put("beds", jdbc.sql("SELECT * FROM hostel.bed_board(:s) WHERE room_id = :r ORDER BY bed_no").param("s", s).param("r", id).query().listOfRows());
        out.put("facilities", jdbc.sql("SELECT rf.facility_code, f.label, rf.quantity FROM hostel.room_facility rf JOIN hostel.facility f ON f.code = rf.facility_code WHERE rf.room_id = :r ORDER BY f.label").param("r", id).query().listOfRows());
        out.put("assets", jdbc.sql("SELECT * FROM hostel.asset WHERE room_id = :r ORDER BY tag").param("r", id).query().listOfRows());
        out.put("maintenance", jdbc.sql("SELECT m.*, st.surname || ', ' || st.other_names AS raised_by_name FROM hostel.maintenance_request m JOIN people.student st ON st.id = m.raised_by WHERE m.room_id = :r ORDER BY m.raised_at DESC").param("r", id).query().listOfRows());
        out.put("history", jdbc.sql("""
                SELECT al.reference_no, al.session, al.state, al.bed, al.allocated_at, al.checked_in_at, al.checked_out_at, al.ended_at, al.ended_reason, st.surname || ', ' || st.other_names AS student_name, coalesce(st.matric_no, st.admission_no) AS student_number
                  FROM hostel.allocation al JOIN people.student st ON st.id = al.student_id WHERE al.room_id = :r ORDER BY al.allocated_at DESC LIMIT 200
                """).param("r", id).query().listOfRows());
        out.put("events", jdbc.sql("SELECT action, from_value, to_value, note, actor_office, at FROM hostel.event WHERE room_id = :r ORDER BY at DESC LIMIT 100").param("r", id).query().listOfRows());
        return out;
    }

    public record HallIn(@NotBlank @Size(max = 8) String code, @NotBlank @Size(max = 120) String name, String sex, String kind, @Size(max = 120) String campus, @Size(max = 200) String location, @Size(max = 1000) String description) {
    }

    @PutMapping("/api/v1/hostel/halls-full")
    @PreAuthorize(OFFICE)
    @Transactional
    Map<String, Object> hall(@Valid @RequestBody HallIn body) {
        String code = body.code().trim().toUpperCase();
        if (!code.matches("[A-Z0-9]{2,8}")) throw new DomainRuleViolation("HOSTEL_HALL", "A hall has a short code of two to eight letters or digits.", new DomainRuleViolation.Remedy("Give the code.", "Housing"));
        String sex = blank(body.sex()) == null ? null : body.sex().trim().toUpperCase();
        String kind = blank(body.kind()) == null ? "UNDERGRADUATE" : body.kind().trim().toUpperCase();
        jdbc.sql("""
                INSERT INTO hostel.hall (code, name, sex, kind, campus, location, description) VALUES (:c, :n, :x, :k, :ca, :l, :d)
                ON CONFLICT (code) DO UPDATE SET name = EXCLUDED.name, sex = EXCLUDED.sex, kind = EXCLUDED.kind, campus = EXCLUDED.campus, location = EXCLUDED.location, description = EXCLUDED.description
                """).param("c", code).param("n", body.name().trim()).param("x", sex, Types.VARCHAR).param("k", kind).param("ca", blank(body.campus()), Types.VARCHAR).param("l", blank(body.location()), Types.VARCHAR).param("d", blank(body.description()), Types.VARCHAR).update();
        jdbc.sql("SELECT hostel.log(NULL, NULL, NULL, :c, NULL, NULL, 'HALL_SAVED', NULL, :n, NULL)").param("c", code).param("n", body.name().trim()).query().listOfRows();
        return Map.of("code", code);
    }

    public record BlockIn(@NotBlank String hall, @NotBlank @Size(max = 12) String code, @Size(max = 120) String name, Integer floors, @Size(max = 400) String note) {
    }

    @PutMapping("/api/v1/hostel/blocks")
    @PreAuthorize(OFFICE)
    @Transactional
    Map<String, Object> block(@Valid @RequestBody BlockIn body) {
        String hall = body.hall().trim().toUpperCase(), code = body.code().trim().toUpperCase();
        UUID id = jdbc.sql("""
                INSERT INTO hostel.block (hall_code, code, name, floors, note) VALUES (:h, :c, :n, :f, :t)
                ON CONFLICT (hall_code, code) DO UPDATE SET name = EXCLUDED.name, floors = EXCLUDED.floors, note = EXCLUDED.note RETURNING id
                """).param("h", hall).param("c", code).param("n", blank(body.name()) == null ? "Block " + code : body.name().trim()).param("f", body.floors() == null ? 1 : body.floors()).param("t", blank(body.note()), Types.VARCHAR).query(UUID.class).single();
        jdbc.sql("SELECT hostel.log(NULL, NULL, NULL, :h, NULL, NULL, 'BLOCK_SAVED', NULL, :c, NULL)").param("h", hall).param("c", code).query().listOfRows();
        return Map.of("id", id, "hall", hall, "code", code);
    }

    public record RoomIn(@NotBlank String hall, @NotBlank String block, @NotBlank String roomNo, @NotNull Integer beds, Integer floor, String roomType, String sex, String state, @Size(max = 400) String note) {
    }

    @PutMapping("/api/v1/hostel/rooms-full")
    @PreAuthorize(OFFICE)
    @Transactional
    Map<String, Object> room(@Valid @RequestBody RoomIn body) {
        UUID id = saveRoom(body.hall(), body.block(), body.roomNo(), body.beds(), body.floor(), body.roomType(), body.sex(), body.state(), body.note());
        return Map.of("id", id);
    }

    private UUID saveRoom(String hall, String block, String roomNo, int beds, Integer floor, String roomType, String sex, String state, String note) {
        String st = blank(state) == null ? "AVAILABLE" : state.trim().toUpperCase();
        UUID id = jdbc.sql("""
                INSERT INTO hostel.room (hall_code, block, room_no, beds, floor, room_type, sex, state, note) VALUES (:h, :b, :r, :n, :f, :t, :x, :st, :note)
                ON CONFLICT (hall_code, block, room_no) DO UPDATE SET beds = EXCLUDED.beds, floor = EXCLUDED.floor, room_type = coalesce(EXCLUDED.room_type, hostel.room.room_type), sex = EXCLUDED.sex, state = EXCLUDED.state, note = EXCLUDED.note
                RETURNING id
                """).param("h", hall.trim().toUpperCase()).param("b", block.trim().toUpperCase()).param("r", roomNo.trim()).param("n", beds).param("f", floor == null ? 0 : floor)
                .param("t", blank(roomType) == null ? null : roomType.trim().toUpperCase(), Types.VARCHAR).param("x", blank(sex) == null ? null : sex.trim().toUpperCase(), Types.VARCHAR).param("st", st).param("note", blank(note), Types.VARCHAR).query(UUID.class).single();
        jdbc.sql("SELECT hostel.log(NULL, NULL, NULL, :h, :r, NULL, 'ROOM_SAVED', NULL, :n, :b)").param("h", hall.trim().toUpperCase()).param("r", id).param("n", block.trim().toUpperCase() + "-" + roomNo.trim() + " · " + beds + " beds").param("b", blank(note), Types.VARCHAR).query().listOfRows();
        return id;
    }

    public record GenerateRoomsIn(@NotBlank String hall, @NotBlank String block, Integer floor, @NotNull Integer from, @NotNull Integer to, @NotNull Integer beds, String roomType, String prefix) {
    }

    /** rooms generated in a run: A-101 … A-120, each with its beds */
    @PostMapping("/api/v1/hostel/rooms/generate")
    @PreAuthorize(OFFICE)
    @Transactional
    Map<String, Object> generateRooms(@Valid @RequestBody GenerateRoomsIn body) {
        if (body.to() < body.from() || body.to() - body.from() > 500) throw new DomainRuleViolation("HOSTEL_ROOMS", "Generate at most five hundred rooms in a run, from a lower number to a higher one.", new DomainRuleViolation.Remedy("Split the run.", "Housing"));
        int n = 0;
        for (int i = body.from(); i <= body.to(); i++) {
            saveRoom(body.hall(), body.block(), (blank(body.prefix()) == null ? "" : body.prefix().trim()) + i, body.beds(), body.floor(), body.roomType(), null, null, null);
            n++;
        }
        return Map.of("generated", n);
    }

    public record FacilitiesIn(@NotNull List<Map<String, Object>> items) {
    }

    @PutMapping("/api/v1/hostel/rooms/{id}/facilities")
    @PreAuthorize(OFFICE)
    @Transactional
    Map<String, Object> facilities(@PathVariable UUID id, @Valid @RequestBody FacilitiesIn body) {
        jdbc.sql("UPDATE hostel.room_facility SET quantity = 0 WHERE room_id = :r").param("r", id).update();
        for (Map<String, Object> it : body.items()) {
            String code = String.valueOf(it.get("code")).trim().toUpperCase();
            int q = it.get("quantity") == null ? 1 : ((Number) it.get("quantity")).intValue();
            jdbc.sql("INSERT INTO hostel.room_facility (room_id, facility_code, quantity) VALUES (:r, :c, :q) ON CONFLICT (room_id, facility_code) DO UPDATE SET quantity = EXCLUDED.quantity").param("r", id).param("c", code).param("q", q).update();
        }
        return Map.of("ok", true);
    }

    public record AssetIn(@NotBlank @Size(max = 40) String tag, @NotBlank @Size(max = 80) String kind, @NotBlank String hall, UUID blockId, UUID roomId, Integer quantity, String condition, LocalDate acquiredOn, BigDecimal value, String state, @Size(max = 400) String note) {
    }

    @PutMapping("/api/v1/hostel/assets")
    @PreAuthorize(OFFICE)
    @Transactional
    Map<String, Object> asset(@Valid @RequestBody AssetIn body) {
        UUID id = jdbc.sql("""
                INSERT INTO hostel.asset (tag, kind, hall_code, block_id, room_id, quantity, condition, acquired_on, value, state, note) VALUES (:t, :k, :h, :b, :r, :q, :c, :a, :v, :s, :n)
                ON CONFLICT (tag) DO UPDATE SET kind = EXCLUDED.kind, hall_code = EXCLUDED.hall_code, block_id = EXCLUDED.block_id, room_id = EXCLUDED.room_id, quantity = EXCLUDED.quantity, condition = EXCLUDED.condition,
                    acquired_on = EXCLUDED.acquired_on, value = EXCLUDED.value, state = EXCLUDED.state, note = EXCLUDED.note RETURNING id
                """).param("t", body.tag().trim().toUpperCase()).param("k", body.kind().trim()).param("h", body.hall().trim().toUpperCase()).param("b", body.blockId(), Types.OTHER).param("r", body.roomId(), Types.OTHER)
                .param("q", body.quantity() == null ? 1 : body.quantity()).param("c", blank(body.condition()) == null ? "GOOD" : body.condition().trim().toUpperCase()).param("a", body.acquiredOn(), Types.DATE).param("v", body.value(), Types.NUMERIC)
                .param("s", blank(body.state()) == null ? "ACTIVE" : body.state().trim().toUpperCase()).param("n", blank(body.note()), Types.VARCHAR).query(UUID.class).single();
        jdbc.sql("SELECT hostel.log(NULL, NULL, NULL, :h, :r, NULL, 'ASSET_SAVED', NULL, :t, :k)").param("h", body.hall().trim().toUpperCase()).param("r", body.roomId(), Types.OTHER).param("t", body.tag().trim().toUpperCase()).param("k", body.kind().trim() + " · " + (blank(body.condition()) == null ? "GOOD" : body.condition().trim().toUpperCase())).query().listOfRows();
        return Map.of("id", id);
    }

    public record CloseIn(@NotBlank String kind, @NotBlank String id, @NotBlank String state, @Size(max = 600) String reason) {
    }

    /** a hall, block, room or bed closed or reopened; the occupants it affects are named */
    @PostMapping("/api/v1/hostel/close")
    @PreAuthorize(OFFICE)
    @Transactional
    Map<String, Object> close(@Valid @RequestBody CloseIn body, @RequestParam(required = false) String session) {
        String kind = body.kind().trim().toUpperCase(), st = body.state().trim().toUpperCase();
        int n = jdbc.sql("SELECT hostel.close(:k, :i, :s, :r)").param("k", kind).param("i", body.id().trim()).param("s", st).param("r", blank(body.reason()), Types.VARCHAR).query(Integer.class).single();
        String where = switch (kind) { case "HALL" -> "r.hall_code = :i"; case "BLOCK" -> "r.block_id = :i::uuid"; case "ROOM" -> "r.id = :i::uuid"; default -> "al.bed_id = :i::uuid"; };
        List<Map<String, Object>> affected = jdbc.sql("""
                SELECT al.id AS allocation_id, al.reference_no, al.state, st.surname || ', ' || st.other_names AS student_name, coalesce(st.matric_no, st.admission_no) AS student_number, h.name AS hall_name, r.block, r.room_no, b.label AS bed_label
                  FROM hostel.allocation al JOIN hostel.room r ON r.id = al.room_id JOIN hostel.hall h ON h.code = r.hall_code JOIN people.student st ON st.id = al.student_id LEFT JOIN hostel.bed b ON b.id = al.bed_id
                 WHERE al.lapsed_at IS NULL AND al.ended_at IS NULL AND al.session = :s
                """ + " AND " + where + " ORDER BY st.surname, st.other_names")
                .param("i", body.id().trim()).param("s", session(session)).query().listOfRows();
        return Map.of("affected", n, "occupants", affected);
    }

    /* ── the window and its rules ────────────────────────────────────────── */

    public record WindowIn(BigDecimal fee, Integer holdHours, LocalDate applicationsOpen, LocalDate applicationsClose, String allocationMethod, Boolean requiresReview, Boolean waitlist, Integer maxApplications,
                           List<String> eligibleStatuses, List<Integer> eligibleLevels, List<String> eligibleFaculties, List<String> eligibleKinds, Boolean requireRegistration, Boolean refuseHostelDebt,
                           @Size(max = 20000) String rules, LocalDate stayFrom, LocalDate stayTo, String state) {
    }

    @PutMapping("/api/v1/hostel/sessions/{s}/{y}/window")
    @PreAuthorize(OFFICE)
    @Transactional
    Map<String, Object> window(@PathVariable String s, @PathVariable String y, @RequestBody WindowIn body) {
        String session = ses(s, y);
        if (body.fee() == null || body.fee().signum() < 0) throw new DomainRuleViolation("HOSTEL_FEE", "State the accommodation fee for the session.", new DomainRuleViolation.Remedy("Zero is a fee; blank is not.", "Housing"));
        String method = blank(body.allocationMethod()) == null ? "BALLOT" : body.allocationMethod().trim().toUpperCase();
        if (!METHODS.contains(method)) throw new DomainRuleViolation("HOSTEL_METHOD", "'" + method + "' is not an allocation method.", new DomainRuleViolation.Remedy("Ballot, first come, level, faculty, programme, special needs or manual.", "Housing"));
        String state = blank(body.state()) == null ? null : body.state().trim().toUpperCase();
        Map<String, Object> cur = jdbc.sql("SELECT rules, rules_version, state FROM hostel.session_setting WHERE session = :s").param("s", session).query().listOfRows().stream().findFirst().orElse(null);
        boolean rulesChanged = cur != null && !String.valueOf(cur.get("rules")).equals(String.valueOf(blank(body.rules())));
        String[] statuses = body.eligibleStatuses() == null || body.eligibleStatuses().isEmpty() ? new String[] {"ACTIVE", "ADMITTED", "PROBATION"} : body.eligibleStatuses().stream().map(String::toUpperCase).toArray(String[]::new);
        Integer[] levels = body.eligibleLevels() == null || body.eligibleLevels().isEmpty() ? null : body.eligibleLevels().toArray(Integer[]::new);
        String[] faculties = body.eligibleFaculties() == null || body.eligibleFaculties().isEmpty() ? null : body.eligibleFaculties().toArray(String[]::new);
        String[] kinds = body.eligibleKinds() == null || body.eligibleKinds().isEmpty() ? null : body.eligibleKinds().stream().map(String::toUpperCase).toArray(String[]::new);
        jdbc.sql("""
                INSERT INTO hostel.session_setting (session, fee, hold_hours, applications_open, applications_close, allocation_method, requires_review, waitlist, max_applications,
                                                    eligible_statuses, eligible_levels, eligible_faculties, eligible_kinds, require_registration, refuse_hostel_debt, rules, rules_version, stay_from, stay_to, state)
                VALUES (:s, :f, :h, :ao, :ac, :m, :rv, :w, :mx, :es, :el, :ef, :ek, :rr, :rd, :rules, 1, :sf, :st, coalesce(:state, 'OPEN'))
                ON CONFLICT (session) DO UPDATE SET fee = EXCLUDED.fee, hold_hours = EXCLUDED.hold_hours, applications_open = EXCLUDED.applications_open, applications_close = EXCLUDED.applications_close,
                    allocation_method = EXCLUDED.allocation_method, requires_review = EXCLUDED.requires_review, waitlist = EXCLUDED.waitlist, max_applications = EXCLUDED.max_applications,
                    eligible_statuses = EXCLUDED.eligible_statuses, eligible_levels = EXCLUDED.eligible_levels, eligible_faculties = EXCLUDED.eligible_faculties, eligible_kinds = EXCLUDED.eligible_kinds,
                    require_registration = EXCLUDED.require_registration, refuse_hostel_debt = EXCLUDED.refuse_hostel_debt, rules = EXCLUDED.rules,
                    rules_version = CASE WHEN :changed THEN hostel.session_setting.rules_version + 1 ELSE hostel.session_setting.rules_version END,
                    stay_from = EXCLUDED.stay_from, stay_to = EXCLUDED.stay_to, state = coalesce(:state, hostel.session_setting.state), updated_at = now()
                """).param("s", session).param("f", body.fee()).param("h", body.holdHours() == null ? 72 : body.holdHours()).param("ao", body.applicationsOpen(), Types.DATE).param("ac", body.applicationsClose(), Types.DATE)
                .param("m", method).param("rv", body.requiresReview() != null && body.requiresReview()).param("w", body.waitlist() == null || body.waitlist()).param("mx", body.maxApplications(), Types.INTEGER)
                .param("es", statuses).param("el", levels, Types.ARRAY).param("ef", faculties, Types.ARRAY).param("ek", kinds, Types.ARRAY)
                .param("rr", body.requireRegistration() != null && body.requireRegistration()).param("rd", body.refuseHostelDebt() == null || body.refuseHostelDebt())
                .param("rules", blank(body.rules()), Types.VARCHAR).param("sf", body.stayFrom(), Types.DATE).param("st", body.stayTo(), Types.DATE).param("state", state, Types.VARCHAR).param("changed", rulesChanged).update();
        jdbc.sql("SELECT hostel.log(NULL, NULL, NULL, NULL, NULL, NULL, 'WINDOW_SAVED', :f, :t, :n)").param("f", cur == null ? null : String.valueOf(cur.get("state")), Types.VARCHAR).param("t", session + " · " + method + (state == null ? "" : " · " + state)).param("n", rulesChanged ? "Rules changed (new version)" : null, Types.VARCHAR).query().listOfRows();
        if (cur == null || ("OPEN".equals(state) && !"OPEN".equals(String.valueOf(cur.get("state"))))) {
            jdbc.sql("""
                    SELECT hostel.tell_student(st.id, 'Hostel applications are open', 'Applications for accommodation in ' || :s || ' are open on the portal' || coalesce(' until ' || :c::text, '') || '. Apply under Hostel on your dashboard.', 'MOAUM: hostel applications for ' || :s || ' are open. See the portal.')
                      FROM people.student st WHERE st.status = ANY (:es) AND (SELECT count(*) FROM people.student WHERE status = ANY (:es)) <= 5000
                    """).param("s", session).param("c", body.applicationsClose(), Types.DATE).param("es", statuses).query().listOfRows();
        }
        return jdbc.sql("SELECT * FROM hostel.session_setting WHERE session = :s").param("s", session).query().singleRow();
    }

    /* ── the desk: the figures, the applications, the seats ──────────────── */

    @GetMapping("/api/v1/hostel/sessions/{s}/{y}/dashboard")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> dashboard(@PathVariable String s, @PathVariable String y) {
        String session = ses(s, y);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("dashboard", jdbc.sql("SELECT hostel.dashboard(:s)::text").param("s", session).query(String.class).single());
        out.put("preview", jdbc.sql("SELECT * FROM hostel.preview(:s)").param("s", session).query().singleRow());
        out.put("sessions", jdbc.sql("SELECT name FROM policy.academic_session ORDER BY name DESC").query(String.class).list());
        out.put("halls", jdbc.sql("SELECT code, name, sex, kind, state FROM hostel.hall WHERE ended_on IS NULL ORDER BY name").query().listOfRows());
        out.put("kinds", jdbc.sql("SELECT code, label FROM hostel.hall_kind WHERE active ORDER BY label").query().listOfRows());
        out.put("faculties", jdbc.sql("SELECT code, name FROM ref.faculty ORDER BY name").query().listOfRows());
        out.put("waiting", jdbc.sql("""
                SELECT (SELECT count(*) FROM hostel.applications(:s) WHERE state = 'APPLIED' AND review IS NULL) AS reviews,
                       (SELECT count(*) FROM hostel.transfer_request t JOIN hostel.allocation a ON a.id = t.allocation_id WHERE a.session = :s AND t.state IN ('SUBMITTED','UNDER_REVIEW')) AS transfers,
                       (SELECT count(*) FROM hostel.allocation WHERE session = :s AND state = 'CHECKED_IN' AND checkout_requested_at IS NOT NULL) AS checkouts,
                       (SELECT count(*) FROM hostel.allocation WHERE session = :s AND state IN ('CONFIRMED','ACCEPTED')) AS checkins,
                       (SELECT count(*) FROM hostel.clearance c JOIN hostel.allocation a ON a.id = c.allocation_id WHERE a.session = :s AND c.state = 'PENDING') AS clearances,
                       (SELECT count(*) FROM hostel.maintenance_request WHERE state IN ('RAISED','ASSIGNED')) AS maintenance
                """).param("s", session).query().singleRow());
        return out;
    }

    @GetMapping("/api/v1/hostel/sessions/{s}/{y}/applications")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> applications(@PathVariable String s, @PathVariable String y, @RequestParam(required = false) String state, @RequestParam(required = false) String review,
                                     @RequestParam(required = false) String fac, @RequestParam(required = false) String dept, @RequestParam(required = false) String prog, @RequestParam(required = false) Integer level,
                                     @RequestParam(required = false) String hall, @RequestParam(required = false) String q, @RequestParam(defaultValue = "0") int page, @RequestParam(defaultValue = "200") int size) {
        String session = ses(s, y);
        String st = blank(state) == null ? null : state.trim().toUpperCase();
        String stPred = st == null ? "" : switch (st) {
            case "PENDING_REVIEW" -> " AND a.state = 'APPLIED' AND a.review IS NULL";
            case "APPROVED" -> " AND a.state = 'APPLIED' AND a.review = 'APPROVED'";
            case "WAITLISTED" -> " AND a.state = 'UNSUCCESSFUL'";
            case "ALLOCATED" -> " AND a.allocation_state IN ('HELD','CONFIRMED','ACCEPTED','CHECKED_IN')";
            case "PAYMENT_PENDING" -> " AND a.allocation_state = 'HELD'";
            case "UNALLOCATED" -> " AND a.state IN ('APPLIED','UNSUCCESSFUL','LAPSED')";
            default -> " AND a.state = :st";
        };
        String needle = blank(q) == null ? null : "%" + q.trim().toLowerCase() + "%";
        int sz = Math.max(1, Math.min(size, 2000)), pg = Math.max(0, page);
        JdbcClient.StatementSpec spec = jdbc.sql("""
                SELECT count(*) OVER () AS total_rows, a.* FROM hostel.applications(:s) a
                 WHERE (:rv::text IS NULL OR a.review = :rv) AND (:fac::text IS NULL OR a.faculty_code = :fac) AND (:dept::text IS NULL OR a.dept_code = :dept) AND (:prog::text IS NULL OR a.programme_code = :prog)
                   AND (:lv::int IS NULL OR a.level = :lv) AND (:hall::text IS NULL OR a.hall_pref = :hall)
                   AND (:q::text IS NULL OR lower(a.student_name) LIKE :q OR lower(a.student_number) LIKE :q OR lower(a.reference) LIKE :q OR lower(coalesce(a.programme, '')) LIKE :q)
                """ + stPred + " ORDER BY a.student_name LIMIT :n OFFSET :o")
                .param("s", session).param("rv", blank(review) == null ? null : review.trim().toUpperCase(), Types.VARCHAR).param("fac", blank(fac), Types.VARCHAR).param("dept", blank(dept), Types.VARCHAR).param("prog", blank(prog), Types.VARCHAR)
                .param("lv", level, Types.INTEGER).param("hall", blank(hall) == null ? null : hall.trim().toUpperCase(), Types.VARCHAR).param("q", needle, Types.VARCHAR).param("n", sz).param("o", pg * sz);
        if (stPred.contains(":st")) spec = spec.param("st", st);
        List<Map<String, Object>> rows = spec.query().listOfRows();
        long total = rows.isEmpty() ? 0 : ((Number) rows.get(0).get("total_rows")).longValue();
        rows.forEach(r -> r.remove("total_rows"));
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("session", session); out.put("total", total); out.put("page", pg); out.put("size", sz); out.put("rows", rows);
        out.put("options", jdbc.sql("SELECT DISTINCT faculty_code, faculty, dept_code, department, programme_code, programme FROM hostel.applications(:s) WHERE programme_code IS NOT NULL ORDER BY faculty, department, programme").param("s", session).query().listOfRows());
        out.put("setting", jdbc.sql("SELECT * FROM hostel.session_setting WHERE session = :s").param("s", session).query().listOfRows().stream().findFirst().orElse(null));
        return out;
    }

    public record ReviewIn(@NotBlank String decision, @Size(max = 600) String note) {
    }

    @PostMapping("/api/v1/hostel/sessions/{s}/{y}/applications/{id}/review")
    @PreAuthorize(OFFICE)
    @Transactional
    Map<String, Object> review(@PathVariable String s, @PathVariable String y, @PathVariable UUID id, @Valid @RequestBody ReviewIn body) {
        jdbc.sql("SELECT hostel.review(:a, :d, :n)").param("a", id).param("d", body.decision().trim().toUpperCase()).param("n", blank(body.note()), Types.VARCHAR).query().listOfRows();
        return Map.of("ok", true);
    }

    public record BulkReviewIn(@NotNull List<UUID> ids, @NotBlank String decision, @Size(max = 600) String note) {
    }

    @PostMapping("/api/v1/hostel/sessions/{s}/{y}/applications/review-bulk")
    @PreAuthorize(OFFICE)
    @Transactional
    Map<String, Object> reviewBulk(@PathVariable String s, @PathVariable String y, @Valid @RequestBody BulkReviewIn body) {
        int n = 0;
        for (UUID id : body.ids()) {
            jdbc.sql("SELECT hostel.review(:a, :d, :n)").param("a", id).param("d", body.decision().trim().toUpperCase()).param("n", blank(body.note()), Types.VARCHAR).query().listOfRows();
            n++;
        }
        return Map.of("reviewed", n);
    }

    public record AllocateIn(@NotNull UUID bedId, @NotBlank @Size(max = 600) String reason) {
    }

    @PostMapping("/api/v1/hostel/sessions/{s}/{y}/applications/{id}/allocate")
    @PreAuthorize(OFFICE)
    @Transactional
    Map<String, Object> allocate(@PathVariable String s, @PathVariable String y, @PathVariable UUID id, @Valid @RequestBody AllocateIn body) {
        UUID a = jdbc.sql("SELECT hostel.allocate(:a, :b, :r)").param("a", id).param("b", body.bedId()).param("r", body.reason().trim()).query(UUID.class).single();
        return Map.of("allocationId", a, "reference", jdbc.sql("SELECT reference_no FROM hostel.allocation WHERE id = :i").param("i", a).query(String.class).single());
    }

    @PostMapping("/api/v1/hostel/sessions/{s}/{y}/applications/{id}/withdraw")
    @PreAuthorize(OFFICE)
    @Transactional
    Map<String, Object> withdrawByDesk(@PathVariable String s, @PathVariable String y, @PathVariable UUID id, @Valid @RequestBody ReviewIn body) {
        jdbc.sql("SELECT hostel.withdraw(:a, :r)").param("a", id).param("r", blank(body.note()) == null ? "Withdrawn by the housing desk" : body.note().trim()).query().listOfRows();
        return Map.of("ok", true);
    }

    @GetMapping("/api/v1/hostel/sessions/{s}/{y}/free-beds")
    @PreAuthorize(READERS)
    List<Map<String, Object>> freeBeds(@PathVariable String s, @PathVariable String y, @RequestParam(required = false) String hall, @RequestParam(required = false) String sex) {
        return jdbc.sql("""
                SELECT fb.*, h.name AS hall_name, rt.label AS room_type_label FROM hostel.free_beds(:s) fb JOIN hostel.hall h ON h.code = fb.hall_code LEFT JOIN hostel.room_type rt ON rt.code = fb.room_type
                 WHERE (:h::text IS NULL OR fb.hall_code = :h) AND (:x::text IS NULL OR fb.hall_sex IS NULL OR fb.hall_sex = :x) ORDER BY h.name, fb.block, fb.room_no, fb.bed LIMIT 2000
                """).param("s", ses(s, y)).param("h", blank(hall) == null ? null : hall.trim().toUpperCase(), Types.VARCHAR).param("x", blank(sex) == null ? null : sex.trim().toUpperCase(), Types.VARCHAR).query().listOfRows();
    }

    @GetMapping("/api/v1/hostel/sessions/{s}/{y}/preview")
    @PreAuthorize(READERS)
    Map<String, Object> preview(@PathVariable String s, @PathVariable String y) {
        return jdbc.sql("SELECT * FROM hostel.preview(:s)").param("s", ses(s, y)).query().singleRow();
    }

    @GetMapping("/api/v1/hostel/sessions/{s}/{y}/occupancy")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> occupancy(@PathVariable String s, @PathVariable String y, @RequestParam(required = false) String hall, @RequestParam(required = false) String block, @RequestParam(required = false) String status,
                                  @RequestParam(required = false) String fac, @RequestParam(required = false) String dept, @RequestParam(required = false) String prog, @RequestParam(required = false) Integer level,
                                  @RequestParam(required = false) String sex, @RequestParam(required = false) String q, @RequestParam(required = false) String view,
                                  @RequestParam(defaultValue = "0") int page, @RequestParam(defaultValue = "500") int size) {
        String session = ses(s, y);
        String st = blank(status) == null ? null : status.trim().toUpperCase();
        String pred = "";
        if ("students".equalsIgnoreCase(view)) pred += " AND bb.allocation_id IS NOT NULL";
        if ("checkouts".equalsIgnoreCase(view)) pred += " AND bb.allocation_state = 'CHECKED_IN' AND EXISTS (SELECT 1 FROM hostel.allocation z WHERE z.id = bb.allocation_id AND z.checkout_requested_at IS NOT NULL)";
        if ("checkins".equalsIgnoreCase(view)) pred += " AND bb.allocation_state IN ('CONFIRMED','ACCEPTED')";
        if (st != null) pred += Set.of("HELD", "CONFIRMED", "ACCEPTED", "CHECKED_IN").contains(st) ? " AND bb.allocation_state = :st" : " AND bb.occupancy = :st";
        String needle = blank(q) == null ? null : "%" + q.trim().toLowerCase() + "%";
        int sz = Math.max(1, Math.min(size, 5000)), pg = Math.max(0, page);
        JdbcClient.StatementSpec spec = jdbc.sql("""
                SELECT count(*) OVER () AS total_rows, bb.* FROM hostel.bed_board(:s) bb
                 WHERE (:h::text IS NULL OR bb.hall_code = :h) AND (:b::text IS NULL OR bb.block = :b) AND (:fac::text IS NULL OR bb.faculty_code = :fac) AND (:dept::text IS NULL OR bb.dept_code = :dept)
                   AND (:prog::text IS NULL OR bb.programme_code = :prog) AND (:lv::int IS NULL OR bb.level = :lv) AND (:x::text IS NULL OR bb.sex = :x)
                   AND (:q::text IS NULL OR lower(coalesce(bb.student_name, '')) LIKE :q OR lower(coalesce(bb.student_number, '')) LIKE :q OR lower(bb.room_no) LIKE :q)
                """ + pred + " ORDER BY bb.student_name NULLS LAST, bb.hall_name, bb.block, bb.room_no, bb.bed_no LIMIT :n OFFSET :o")
                .param("s", session).param("h", blank(hall) == null ? null : hall.trim().toUpperCase(), Types.VARCHAR).param("b", blank(block) == null ? null : block.trim().toUpperCase(), Types.VARCHAR)
                .param("fac", blank(fac), Types.VARCHAR).param("dept", blank(dept), Types.VARCHAR).param("prog", blank(prog), Types.VARCHAR).param("lv", level, Types.INTEGER)
                .param("x", blank(sex) == null ? null : sex.trim().toUpperCase(), Types.VARCHAR).param("q", needle, Types.VARCHAR).param("n", sz).param("o", pg * sz);
        if (pred.contains(":st")) spec = spec.param("st", st);
        List<Map<String, Object>> rows = spec.query().listOfRows();
        long total = rows.isEmpty() ? 0 : ((Number) rows.get(0).get("total_rows")).longValue();
        rows.forEach(r -> r.remove("total_rows"));
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("session", session); out.put("total", total); out.put("page", pg); out.put("size", sz); out.put("rows", rows);
        out.put("halls", jdbc.sql("SELECT code, name FROM hostel.hall WHERE ended_on IS NULL ORDER BY name").query().listOfRows());
        out.put("blocks", jdbc.sql("SELECT hall_code, code FROM hostel.block ORDER BY hall_code, code").query().listOfRows());
        out.put("options", jdbc.sql("SELECT DISTINCT faculty_code, faculty, dept_code, department, programme_code, programme FROM hostel.bed_board(:s) WHERE programme_code IS NOT NULL ORDER BY faculty, department, programme").param("s", session).query().listOfRows());
        return out;
    }

    /* ── one allocation, and everything done on it ───────────────────────── */

    @GetMapping("/api/v1/hostel/allocations/{id}")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> allocation(@PathVariable UUID id) {
        Map<String, Object> al = jdbc.sql("""
                SELECT al.*, ap.reference AS application_ref, ap.category, ap.category_note, ap.special_need, ap.roommate_note, h.code AS hall_code, h.name AS hall_name, h.sex AS hall_sex, r.block, r.floor, r.room_no, r.room_type, b.label AS bed_label,
                       st.surname || ', ' || st.other_names AS student_name, coalesce(st.matric_no, st.admission_no) AS student_number, st.sex, st.current_level AS level, st.status AS student_status, p.name AS programme, d.name AS department, f.name AS faculty,
                       s.fee, s.rules, s.rules_version AS current_rules_version, cl.id AS clearance_id, cl.reference AS clearance_ref, cl.state AS clearance_state, cl.completed_at AS clearance_completed_at,
                       (SELECT reference_no FROM hostel.allocation m WHERE m.id = al.moved_from) AS moved_from_ref
                  FROM hostel.allocation al JOIN hostel.application ap ON ap.id = al.application_id JOIN hostel.room r ON r.id = al.room_id JOIN hostel.hall h ON h.code = r.hall_code LEFT JOIN hostel.bed b ON b.id = al.bed_id
                  JOIN people.student st ON st.id = al.student_id LEFT JOIN ref.programme p ON p.code = st.programme_code LEFT JOIN ref.department d ON d.code = p.dept_code LEFT JOIN ref.faculty f ON f.code = p.faculty_code
                  LEFT JOIN hostel.session_setting s ON s.session = al.session LEFT JOIN hostel.clearance cl ON cl.allocation_id = al.id
                 WHERE al.id = :id
                """).param("id", id).query().listOfRows().stream().findFirst().orElseThrow(() -> new NotFound("allocation", id));
        Map<String, Object> out = new LinkedHashMap<>(al);
        out.put("roommates", jdbc.sql("SELECT * FROM hostel.roommates(:a)").param("a", id).query().listOfRows());
        out.put("inspections", jdbc.sql("SELECT i.*, pe.surname || ', ' || pe.given_names AS officer FROM hostel.inspection i LEFT JOIN iam.person pe ON pe.id = i.inspected_by WHERE i.allocation_id = :a ORDER BY i.inspected_at").param("a", id).query().listOfRows());
        out.put("charges", jdbc.sql("SELECT c.*, a.tag AS asset_tag FROM hostel.damage_charge c LEFT JOIN hostel.asset a ON a.id = c.asset_id WHERE c.allocation_id = :a ORDER BY c.raised_at").param("a", id).query().listOfRows());
        out.put("clearanceItems", jdbc.sql("""
                SELECT i.id, i.requirement, r.label, i.state, i.decided_at, i.remarks, pe.surname || ', ' || pe.given_names AS officer FROM hostel.clearance_item i JOIN hostel.clearance_requirement r ON r.code = i.requirement
                  JOIN hostel.clearance c ON c.id = i.clearance_id LEFT JOIN iam.person pe ON pe.id = i.officer_id WHERE c.allocation_id = :a ORDER BY r.ord
                """).param("a", id).query().listOfRows());
        out.put("transfers", jdbc.sql("SELECT t.*, h.name AS requested_hall_name FROM hostel.transfer_request t LEFT JOIN hostel.hall h ON h.code = t.requested_hall WHERE t.allocation_id = :a ORDER BY t.submitted_at DESC").param("a", id).query().listOfRows());
        out.put("events", jdbc.sql("SELECT e.action, e.from_value, e.to_value, e.note, e.actor_office, e.at, pe.surname || ', ' || pe.given_names AS actor FROM hostel.event e LEFT JOIN iam.person pe ON pe.id = e.actor_id WHERE e.allocation_id = :a OR e.application_id = (SELECT application_id FROM hostel.allocation WHERE id = :a) ORDER BY e.at").param("a", id).query().listOfRows());
        out.put("assets", jdbc.sql("SELECT * FROM hostel.asset WHERE room_id = (SELECT room_id FROM hostel.allocation WHERE id = :a) ORDER BY tag").param("a", id).query().listOfRows());
        out.put("passport_id", jdbc.sql("""
                SELECT d.id FROM admissions.application_document d JOIN admissions.application a ON a.id = d.application_id JOIN people.student st ON st.candidate_id = a.candidate_id
                 WHERE st.id = (SELECT student_id FROM hostel.allocation WHERE id = :a) AND d.kind = 'PASSPORT' AND d.superseded_at IS NULL ORDER BY d.id LIMIT 1
                """).param("a", id).query(UUID.class).optional().orElse(null));
        return out;
    }

    public record CheckinIn(@Size(max = 600) String note, String condition) {
    }

    @PostMapping("/api/v1/hostel/allocations/{id}/checkin")
    @PreAuthorize(OFFICE)
    @Transactional
    Map<String, Object> checkin(@PathVariable UUID id, @RequestBody(required = false) CheckinIn body) {
        String cond = body == null || blank(body.condition()) == null ? "GOOD" : body.condition().trim().toUpperCase();
        jdbc.sql("SELECT hostel.checkin(:a, :n, :c)").param("a", id).param("n", body == null ? null : blank(body.note()), Types.VARCHAR).param("c", cond).query().listOfRows();
        return Map.of("ok", true, "state", "CHECKED_IN");
    }

    public record MoveIn(@NotNull UUID bedId, @NotBlank @Size(max = 600) String reason) {
    }

    @PostMapping("/api/v1/hostel/allocations/{id}/transfer")
    @PreAuthorize(OFFICE)
    @Transactional
    Map<String, Object> transfer(@PathVariable UUID id, @Valid @RequestBody MoveIn body) {
        UUID n = jdbc.sql("SELECT hostel.transfer(:a, :b, :r)").param("a", id).param("b", body.bedId()).param("r", body.reason().trim()).query(UUID.class).single();
        return Map.of("allocationId", n, "reference", jdbc.sql("SELECT reference_no FROM hostel.allocation WHERE id = :i").param("i", n).query(String.class).single());
    }

    @PostMapping("/api/v1/hostel/allocations/{id}/cancel")
    @PreAuthorize(OFFICE)
    @Transactional
    Map<String, Object> cancel(@PathVariable UUID id, @Valid @RequestBody ReasonIn body) {
        jdbc.sql("SELECT hostel.cancel(:a, :r)").param("a", id).param("r", body.reason().trim()).query().listOfRows();
        return Map.of("ok", true);
    }

    public record InspectIn(@NotBlank String condition, String cleanliness, @Size(max = 2000) String damages, Boolean keysReturned, Boolean cardReturned, @Size(max = 1000) String remarks) {
    }

    @PostMapping("/api/v1/hostel/allocations/{id}/inspect")
    @PreAuthorize(OFFICE)
    @Transactional
    Map<String, Object> inspect(@PathVariable UUID id, @Valid @RequestBody InspectIn body) {
        UUID i = jdbc.sql("SELECT hostel.inspect(:a, :c, :cl, :d, :k, :cd, :r)").param("a", id).param("c", body.condition().trim().toUpperCase()).param("cl", blank(body.cleanliness()) == null ? null : body.cleanliness().trim().toUpperCase(), Types.VARCHAR)
                .param("d", blank(body.damages()), Types.VARCHAR).param("k", body.keysReturned(), Types.BOOLEAN).param("cd", body.cardReturned(), Types.BOOLEAN).param("r", blank(body.remarks()), Types.VARCHAR).query(UUID.class).single();
        return Map.of("inspectionId", i);
    }

    public record ChargeIn(UUID assetId, @NotBlank @Size(max = 600) String description, BigDecimal repairCost, BigDecimal replacementCost, @NotNull BigDecimal charge) {
    }

    @PostMapping("/api/v1/hostel/allocations/{id}/charge")
    @PreAuthorize(OFFICE)
    @Transactional
    Map<String, Object> charge(@PathVariable UUID id, @Valid @RequestBody ChargeIn body) {
        UUID c = jdbc.sql("SELECT hostel.charge(:a, :as, :d, :rp, :rc, :c)").param("a", id).param("as", body.assetId(), Types.OTHER).param("d", body.description().trim()).param("rp", body.repairCost(), Types.NUMERIC).param("rc", body.replacementCost(), Types.NUMERIC).param("c", body.charge()).query(UUID.class).single();
        return jdbc.sql("SELECT * FROM hostel.damage_charge WHERE id = :c").param("c", c).query().singleRow();
    }

    @PostMapping("/api/v1/hostel/charges/{id}/waive")
    @PreAuthorize(OFFICE)
    @Transactional
    Map<String, Object> waive(@PathVariable UUID id, @Valid @RequestBody ReasonIn body) {
        jdbc.sql("SELECT hostel.waive_charge(:c, :r)").param("c", id).param("r", body.reason().trim()).query().listOfRows();
        return Map.of("ok", true);
    }

    @PostMapping("/api/v1/hostel/allocations/{id}/clearance")
    @PreAuthorize(OFFICE)
    @Transactional
    Map<String, Object> startClearance(@PathVariable UUID id) {
        UUID c = jdbc.sql("SELECT hostel.start_clearance(:a)").param("a", id).query(UUID.class).single();
        return Map.of("clearanceId", c, "reference", jdbc.sql("SELECT reference FROM hostel.clearance WHERE id = :c").param("c", c).query(String.class).single());
    }

    public record ItemIn(@NotBlank String state, @Size(max = 600) String remarks) {
    }

    @PostMapping("/api/v1/hostel/clearance-items/{id}")
    @PreAuthorize(OFFICE)
    @Transactional
    Map<String, Object> item(@PathVariable UUID id, @Valid @RequestBody ItemIn body) {
        jdbc.sql("SELECT hostel.decide_item(:i, :s, :r)").param("i", id).param("s", body.state().trim().toUpperCase()).param("r", blank(body.remarks()), Types.VARCHAR).query().listOfRows();
        return Map.of("ok", true);
    }

    public record NoteIn(@Size(max = 600) String note) {
    }

    @PostMapping("/api/v1/hostel/clearances/{id}/complete")
    @PreAuthorize(OFFICE)
    @Transactional
    Map<String, Object> complete(@PathVariable UUID id, @RequestBody(required = false) NoteIn body) {
        String st = jdbc.sql("SELECT hostel.complete_clearance(:c, :n)").param("c", id).param("n", body == null ? null : blank(body.note()), Types.VARCHAR).query(String.class).single();
        return Map.of("state", st);
    }

    @PostMapping("/api/v1/hostel/clearances/{id}/reopen")
    @PreAuthorize(OFFICE)
    @Transactional
    Map<String, Object> reopen(@PathVariable UUID id, @RequestBody(required = false) NoteIn body) {
        jdbc.sql("SELECT hostel.reopen_clearance(:c, :n)").param("c", id).param("n", body == null ? null : blank(body.note()), Types.VARCHAR).query().listOfRows();
        return Map.of("state", "PENDING");
    }

    @GetMapping("/api/v1/hostel/sessions/{s}/{y}/clearances")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> clearances(@PathVariable String s, @PathVariable String y, @RequestParam(required = false) String state, @RequestParam(required = false) String q) {
        String session = ses(s, y);
        String needle = blank(q) == null ? null : "%" + q.trim().toLowerCase() + "%";
        List<Map<String, Object>> rows = jdbc.sql("""
                SELECT c.id, c.reference, c.state, c.started_at, c.completed_at, al.id AS allocation_id, al.reference_no, al.state AS allocation_state, al.checkout_requested_at, al.checkout_on, al.checked_out_at,
                       st.surname || ', ' || st.other_names AS student_name, coalesce(st.matric_no, st.admission_no) AS student_number, h.name AS hall_name, r.block, r.room_no, b.label AS bed_label,
                       (SELECT count(*) FROM hostel.clearance_item i WHERE i.clearance_id = c.id AND i.state IN ('PENDING','NOT_CLEARED')) AS outstanding,
                       (SELECT string_agg(rq.label, '; ' ORDER BY rq.ord) FROM hostel.clearance_item i JOIN hostel.clearance_requirement rq ON rq.code = i.requirement WHERE i.clearance_id = c.id AND i.state IN ('PENDING','NOT_CLEARED')) AS outstanding_items,
                       (SELECT coalesce(sum(charge), 0) FROM hostel.damage_charge d WHERE d.allocation_id = al.id AND d.settled_at IS NULL AND d.waived_at IS NULL) AS charges_due
                  FROM hostel.clearance c JOIN hostel.allocation al ON al.id = c.allocation_id JOIN people.student st ON st.id = al.student_id JOIN hostel.room r ON r.id = al.room_id JOIN hostel.hall h ON h.code = r.hall_code LEFT JOIN hostel.bed b ON b.id = al.bed_id
                 WHERE al.session = :s AND (:st::text IS NULL OR c.state = :st) AND (:q::text IS NULL OR lower(st.surname || ', ' || st.other_names) LIKE :q OR lower(coalesce(st.matric_no, st.admission_no)) LIKE :q OR lower(c.reference) LIKE :q)
                 ORDER BY st.surname, st.other_names
                """).param("s", session).param("st", blank(state) == null ? null : state.trim().toUpperCase(), Types.VARCHAR).param("q", needle, Types.VARCHAR).query().listOfRows();
        return Map.of("session", session, "rows", rows);
    }

    @GetMapping("/api/v1/hostel/sessions/{s}/{y}/transfers")
    @PreAuthorize(READERS)
    List<Map<String, Object>> transfers(@PathVariable String s, @PathVariable String y, @RequestParam(required = false) String state) {
        return jdbc.sql("""
                SELECT t.*, al.reference_no, al.state AS allocation_state, st.surname || ', ' || st.other_names AS student_name, coalesce(st.matric_no, st.admission_no) AS student_number, st.sex,
                       h.name AS hall_name, r.block, r.room_no, b.label AS bed_label, rh.name AS requested_hall_name, rt.label AS requested_type_label
                  FROM hostel.transfer_request t JOIN hostel.allocation al ON al.id = t.allocation_id JOIN people.student st ON st.id = t.student_id JOIN hostel.room r ON r.id = al.room_id JOIN hostel.hall h ON h.code = r.hall_code
                  LEFT JOIN hostel.bed b ON b.id = al.bed_id LEFT JOIN hostel.hall rh ON rh.code = t.requested_hall LEFT JOIN hostel.room_type rt ON rt.code = t.requested_type
                 WHERE al.session = :s AND (:st::text IS NULL OR t.state = :st) ORDER BY t.submitted_at DESC
                """).param("s", ses(s, y)).param("st", blank(state) == null ? null : state.trim().toUpperCase(), Types.VARCHAR).query().listOfRows();
    }

    public record DecideTransferIn(@NotBlank String decision, UUID bedId, @Size(max = 600) String note) {
    }

    @PostMapping("/api/v1/hostel/transfers/{id}")
    @PreAuthorize(OFFICE)
    @Transactional
    Map<String, Object> decideTransfer(@PathVariable UUID id, @Valid @RequestBody DecideTransferIn body) {
        UUID n = jdbc.sql("SELECT hostel.decide_transfer(:t, :d, :b, :n)").param("t", id).param("d", body.decision().trim().toUpperCase()).param("b", body.bedId(), Types.OTHER).param("n", blank(body.note()), Types.VARCHAR).query(UUID.class).optional().orElse(null);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("newAllocationId", n);
        return out;
    }

    public record MaintenanceIn(String state, @Size(max = 600) String note, @Size(max = 120) String assignedTo, String priority) {
    }

    @PostMapping("/api/v1/hostel/maintenance/{id}/update")
    @PreAuthorize(OFFICE)
    @Transactional
    Map<String, Object> maintenance(@PathVariable UUID id, @Valid @RequestBody MaintenanceIn body) {
        String st = blank(body.state()) == null ? null : body.state().trim().toUpperCase();
        if (st != null && !Set.of("RAISED", "ASSIGNED", "FIXED", "CLOSED").contains(st)) throw new DomainRuleViolation("HOSTEL_MAINT_STATE", "A request is raised, assigned, fixed or closed.", new DomainRuleViolation.Remedy("One of those.", "Housing"));
        String pri = blank(body.priority()) == null ? null : body.priority().trim().toUpperCase();
        int n = jdbc.sql("""
                UPDATE hostel.maintenance_request SET state = coalesce(:st, state), note = coalesce(:n, note), assigned_to = coalesce(:a, assigned_to), priority = coalesce(:p, priority),
                       decided_at = CASE WHEN :st IN ('FIXED','CLOSED') THEN now() ELSE decided_at END WHERE id = :id
                """).param("st", st, Types.VARCHAR).param("n", blank(body.note()), Types.VARCHAR).param("a", blank(body.assignedTo()), Types.VARCHAR).param("p", pri, Types.VARCHAR).param("id", id).update();
        if (n == 0) throw new NotFound("maintenance request", id);
        Map<String, Object> m = jdbc.sql("SELECT * FROM hostel.maintenance_request WHERE id = :id").param("id", id).query().singleRow();
        jdbc.sql("SELECT hostel.log(NULL, NULL, :s, NULL, :r, :b, 'MAINTENANCE_UPDATED', NULL, :st, :n)").param("s", m.get("raised_by")).param("r", m.get("room_id")).param("b", m.get("bed_id"), Types.OTHER).param("st", String.valueOf(m.get("state"))).param("n", blank(body.note()), Types.VARCHAR).query().listOfRows();
        if (st != null && Set.of("FIXED", "CLOSED").contains(st)) {
            jdbc.sql("SELECT hostel.tell_student(:s, 'Your maintenance request is ' || :w, 'Your request (' || :i || ') is ' || :w || coalesce(': ' || :n, '') || '.', 'MOAUM: hostel maintenance request ' || :w || '.')")
                    .param("s", m.get("raised_by")).param("w", st.toLowerCase()).param("i", String.valueOf(m.get("issue"))).param("n", blank(body.note()), Types.VARCHAR).query().listOfRows();
        }
        return m;
    }

    @GetMapping("/api/v1/hostel/maintenance")
    @PreAuthorize(READERS)
    List<Map<String, Object>> maintenanceList(@RequestParam(required = false) String state) {
        return jdbc.sql("""
                SELECT m.*, h.name AS hall_name, r.block, r.room_no, st.surname || ', ' || st.other_names AS raised_by_name, coalesce(st.matric_no, st.admission_no) AS number
                  FROM hostel.maintenance_request m JOIN hostel.room r ON r.id = m.room_id JOIN hostel.hall h ON h.code = r.hall_code JOIN people.student st ON st.id = m.raised_by
                 WHERE (:st::text IS NULL OR m.state = :st) ORDER BY CASE m.priority WHEN 'URGENT' THEN 0 WHEN 'HIGH' THEN 1 WHEN 'NORMAL' THEN 2 ELSE 3 END, m.raised_at DESC LIMIT 1000
                """).param("st", blank(state) == null ? null : state.trim().toUpperCase(), Types.VARCHAR).query().listOfRows();
    }

    /* ── a student's whole accommodation history, for the record ─────────── */

    @GetMapping("/api/v1/hostel/students/{id}/history")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> studentHistory(@PathVariable UUID id) {
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("student", jdbc.sql("SELECT st.id, st.surname || ', ' || st.other_names AS name, coalesce(st.matric_no, st.admission_no) AS number, st.sex, st.current_level, st.status, p.name AS programme FROM people.student st LEFT JOIN ref.programme p ON p.code = st.programme_code WHERE st.id = :id")
                .param("id", id).query().listOfRows().stream().findFirst().orElseThrow(() -> new NotFound("student", id)));
        out.put("history", jdbc.sql("SELECT * FROM hostel.history(:s)").param("s", id).query().listOfRows());
        out.put("events", jdbc.sql("SELECT action, from_value, to_value, note, actor_office, at FROM hostel.event WHERE student_id = :s ORDER BY at DESC LIMIT 200").param("s", id).query().listOfRows());
        out.put("charges", jdbc.sql("SELECT c.*, al.reference_no, al.session FROM hostel.damage_charge c JOIN hostel.allocation al ON al.id = c.allocation_id WHERE al.student_id = :s ORDER BY c.raised_at DESC").param("s", id).query().listOfRows());
        return out;
    }

    /* ── the holds lapse on the clock, session by session ────────────────── */

    @PostMapping("/api/v1/hostel/lapse-all")
    @PreAuthorize(OFFICE)
    @Transactional
    Map<String, Object> lapseAll() {
        List<String> sessions = jdbc.sql("SELECT session FROM hostel.session_setting WHERE drawn_at IS NOT NULL OR EXISTS (SELECT 1 FROM hostel.allocation a WHERE a.session = hostel.session_setting.session AND a.state = 'HELD')").query(String.class).list();
        List<Map<String, Object>> out = new ArrayList<>();
        for (String s : sessions) out.add(Map.of("session", s, "lapsed", jdbc.sql("SELECT hostel.lapse_holds(:s)").param("s", s).query(Integer.class).single()));
        return Map.of("sessions", out);
    }
}
