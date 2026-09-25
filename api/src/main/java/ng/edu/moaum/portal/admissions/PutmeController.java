package ng.edu.moaum.portal.admissions;

import java.sql.Types;
import java.time.LocalDate;
import java.time.LocalTime;
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

import ng.edu.moaum.portal.shared.AuditContextHolder;
import ng.edu.moaum.portal.shared.DomainRuleViolation;
import ng.edu.moaum.portal.shared.NotFound;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * The Post-UTME CBT examination of a session (V260): the event, its centres, rooms, workstations, slots and days; the
 * candidates and where each stands; the batches generated, validated, published; a candidate moved, a batch postponed;
 * the door and the hall. The rules are in the database; this is the desk's door to them. The Academic Office and the
 * Registry manage; the offices that read admissions read.
 */
@RestController
@RequestMapping("/api/v1/admissions/sessions/{session}/{year}/putme")
class PutmeController {

    private static final String READERS = "hasAnyAuthority('OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar','OFFICE_records','OFFICE_bursar','OFFICE_ict','OFFICE_admin','OFFICE_super')";
    private static final String OFFICE = "hasAnyAuthority('OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar','OFFICE_super')";
    private static final String DOOR = "hasAnyAuthority('OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar','OFFICE_records','OFFICE_ict','OFFICE_super')";
    private static final Set<String> STATES = Set.of("DRAFT", "CONFIGURING", "OPEN_FOR_SCHEDULING", "SCHEDULING_IN_PROGRESS", "SCHEDULED", "ONGOING", "COMPLETED", "CANCELLED");
    private static final Set<String> STRATEGIES = Set.of("PROGRAMME", "DEPARTMENT", "FACULTY", "ALPHABETICAL", "APPLICATION_NO", "BALANCED");

    private final JdbcClient jdbc;

    PutmeController(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    private static String ses(String session, String year) {
        return session + "/" + year;
    }

    private Map<String, Object> exam(String s) {
        return jdbc.sql("SELECT * FROM admissions.putme_exam WHERE session = :s ORDER BY created_at DESC LIMIT 1").param("s", s).query().listOfRows().stream().findFirst().orElse(null);
    }

    private UUID examId(String s) {
        Map<String, Object> x = exam(s);
        if (x == null) throw new DomainRuleViolation("PUTME_NO_EXAM", "No Post-UTME examination is set up for " + s + ".", new DomainRuleViolation.Remedy("Create the examination on the setup screen first.", "Academic Office"));
        return (UUID) x.get("id");
    }

    /* ── the overview: everything the desk opens on ─────────────────────── */

    @GetMapping
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> overview(@PathVariable String session, @PathVariable String year) {
        String s = ses(session, year);
        Map<String, Object> x = exam(s);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("session", s);
        out.put("exam", x);
        out.put("statuses", jdbc.sql("SELECT status, count(*) AS n FROM admissions.putme_candidates(:s) GROUP BY status ORDER BY status").param("s", s).query().listOfRows());
        out.put("examProgrammes", jdbc.sql("""
                SELECT e.programme_code, p.name FROM admissions.screening_exam_programme e JOIN ref.programme p ON p.code = e.programme_code WHERE e.session = :s ORDER BY p.name
                """).param("s", s).query().listOfRows());
        out.put("centres", centres());
        if (x != null) {
            UUID id = (UUID) x.get("id");
            out.put("preview", jdbc.sql("SELECT * FROM admissions.putme_preview(:e)").param("e", id).query().singleRow());
            out.put("findings", jdbc.sql("SELECT * FROM admissions.putme_validate(:e)").param("e", id).query().listOfRows());
            out.put("slots", jdbc.sql("SELECT id, code, starts_at, ends_at, ord, active FROM admissions.putme_slot WHERE exam_id = :e ORDER BY ord, starts_at").param("e", id).query().listOfRows());
            out.put("days", jdbc.sql("SELECT held_on, active FROM admissions.putme_day WHERE exam_id = :e ORDER BY held_on").param("e", id).query().listOfRows());
            out.put("examCentres", jdbc.sql("SELECT centre_id FROM admissions.putme_exam_centre WHERE exam_id = :e AND active").param("e", id).query(UUID.class).list());
            out.put("capacity", jdbc.sql("SELECT * FROM admissions.putme_capacity(:e)").param("e", id).query().listOfRows());
            out.put("batches", batches(s));
            out.put("byDate", jdbc.sql("""
                    SELECT b.held_on, count(a.id) AS candidates, coalesce(sum(b.capacity), 0) AS capacity FROM admissions.screening_batch b LEFT JOIN admissions.application a ON a.screening_batch_id = b.id
                     WHERE b.exam_id = :e AND b.state IN ('DRAFT','PUBLISHED') GROUP BY b.held_on ORDER BY b.held_on
                    """).param("e", id).query().listOfRows());
            out.put("byCentre", jdbc.sql("""
                    SELECT c.id AS centre_id, c.name AS centre, count(DISTINCT r.id) AS rooms, count(DISTINCT b.id) AS batches,
                           coalesce(sum(b.capacity), 0) AS capacity, count(a.id) AS assigned
                      FROM admissions.putme_exam_centre ec JOIN admissions.cbt_centre c ON c.id = ec.centre_id
                      LEFT JOIN admissions.cbt_room r ON r.centre_id = c.id AND r.state = 'ACTIVE'
                      LEFT JOIN admissions.screening_batch b ON b.exam_id = ec.exam_id AND b.centre_id = c.id AND b.state IN ('DRAFT','PUBLISHED')
                      LEFT JOIN admissions.application a ON a.screening_batch_id = b.id
                     WHERE ec.exam_id = :e AND ec.active GROUP BY c.id, c.name ORDER BY c.name
                    """).param("e", id).query().listOfRows());
            out.put("byFaculty", jdbc.sql("""
                    SELECT faculty, count(*) AS candidates, count(*) FILTER (WHERE batch_id IS NOT NULL) AS scheduled FROM admissions.putme_candidates(:s)
                     WHERE status NOT IN ('NOT_ELIGIBLE') GROUP BY faculty ORDER BY faculty
                    """).param("s", s).query().listOfRows());
            out.put("byProgramme", jdbc.sql("""
                    SELECT programme_code, programme, faculty, count(*) AS candidates, count(*) FILTER (WHERE batch_id IS NOT NULL) AS scheduled FROM admissions.putme_candidates(:s)
                     WHERE status NOT IN ('NOT_ELIGIBLE') GROUP BY programme_code, programme, faculty ORDER BY programme
                    """).param("s", s).query().listOfRows());
        }
        return out;
    }

    private List<Map<String, Object>> centres() {
        List<Map<String, Object>> cs = jdbc.sql("SELECT * FROM admissions.cbt_centre ORDER BY name").query().listOfRows();
        List<Map<String, Object>> out = new ArrayList<>();
        for (Map<String, Object> c : cs) {
            Map<String, Object> m = new LinkedHashMap<>(c);
            m.put("rooms", jdbc.sql("""
                    SELECT r.*, (SELECT count(*) FROM admissions.cbt_workstation w WHERE w.room_id = r.id AND w.operational) AS operational_workstations
                      FROM admissions.cbt_room r WHERE r.centre_id = :c ORDER BY r.code
                    """).param("c", c.get("id")).query().listOfRows());
            out.add(m);
        }
        return out;
    }

    private List<Map<String, Object>> batches(String s) {
        return jdbc.sql("""
                SELECT b.id, b.label, b.ordinal, b.held_on, b.starts_at, b.ends_at, b.venue, b.capacity, b.state, b.note, b.exam_id,
                       c.name AS centre, r.name AS room, sl.code AS slot,
                       (SELECT count(*) FROM admissions.application a WHERE a.screening_batch_id = b.id) AS assigned,
                       (SELECT count(*) FROM admissions.screening_assignment sa WHERE sa.batch_id = b.id AND sa.state = 'ACTIVE' AND sa.attendance IN ('CHECKED_IN','PRESENT')) AS checked_in,
                       (SELECT count(*) FROM admissions.screening_assignment sa WHERE sa.batch_id = b.id AND sa.state = 'ACTIVE' AND sa.attendance = 'ABSENT') AS absent
                  FROM admissions.screening_batch b LEFT JOIN admissions.cbt_centre c ON c.id = b.centre_id LEFT JOIN admissions.cbt_room r ON r.id = b.room_id LEFT JOIN admissions.putme_slot sl ON sl.id = b.slot_id
                 WHERE b.session = :s ORDER BY b.held_on, b.starts_at, b.ordinal NULLS LAST, b.label
                """).param("s", s).query().listOfRows();
    }

    /* ── the examination ────────────────────────────────────────────────── */

    public record ExamIn(@NotBlank @Size(max = 160) String name, LocalDate startsOn, LocalDate endsOn, Integer checkinMinutes, Integer durationMinutes, Integer bufferMinutes,
                         LocalDate registrationDeadline, String strategy, Boolean keepProgramme, @Size(max = 4000) String instructions, @Size(max = 2000) String venueInstructions, @Size(max = 400) String contact) {
    }

    @PutMapping("/exam")
    @PreAuthorize(OFFICE)
    @Transactional
    Map<String, Object> saveExam(@PathVariable String session, @PathVariable String year, @Valid @RequestBody ExamIn body) {
        String s = ses(session, year);
        String strategy = body.strategy() == null || body.strategy().isBlank() ? "PROGRAMME" : body.strategy().trim().toUpperCase();
        if (!STRATEGIES.contains(strategy)) throw new DomainRuleViolation("PUTME_STRATEGY", "'" + strategy + "' is not a batching strategy.", new DomainRuleViolation.Remedy("Programme, department, faculty, alphabetical, application number or balanced.", "Academic Office"));
        Map<String, Object> x = exam(s);
        if (x == null) {
            jdbc.sql("""
                    INSERT INTO admissions.putme_exam (session, name, starts_on, ends_on, checkin_minutes, duration_minutes, buffer_minutes, registration_deadline, strategy, keep_programme, instructions, venue_instructions, contact, state)
                    VALUES (:s, :n, :a, :b, :ci, :du, :bu, :rd, :st, :kp, :i, :vi, :c, 'CONFIGURING')
                    """).param("s", s).param("n", body.name().trim()).param("a", body.startsOn(), Types.DATE).param("b", body.endsOn(), Types.DATE)
                    .param("ci", body.checkinMinutes() == null ? 30 : body.checkinMinutes()).param("du", body.durationMinutes() == null ? 120 : body.durationMinutes()).param("bu", body.bufferMinutes() == null ? 30 : body.bufferMinutes())
                    .param("rd", body.registrationDeadline(), Types.DATE).param("st", strategy).param("kp", body.keepProgramme() == null || body.keepProgramme())
                    .param("i", body.instructions(), Types.VARCHAR).param("vi", body.venueInstructions(), Types.VARCHAR).param("c", body.contact(), Types.VARCHAR).update();
            log(s, null, null, "EXAM_CREATED", null, body.name().trim(), null);
        } else {
            jdbc.sql("""
                    UPDATE admissions.putme_exam SET name = :n, starts_on = :a, ends_on = :b, checkin_minutes = :ci, duration_minutes = :du, buffer_minutes = :bu, registration_deadline = :rd,
                           strategy = :st, keep_programme = :kp, instructions = :i, venue_instructions = :vi, contact = :c, updated_at = now() WHERE id = :id
                    """).param("id", x.get("id")).param("n", body.name().trim()).param("a", body.startsOn(), Types.DATE).param("b", body.endsOn(), Types.DATE)
                    .param("ci", body.checkinMinutes() == null ? 30 : body.checkinMinutes()).param("du", body.durationMinutes() == null ? 120 : body.durationMinutes()).param("bu", body.bufferMinutes() == null ? 30 : body.bufferMinutes())
                    .param("rd", body.registrationDeadline(), Types.DATE).param("st", strategy).param("kp", body.keepProgramme() == null || body.keepProgramme())
                    .param("i", body.instructions(), Types.VARCHAR).param("vi", body.venueInstructions(), Types.VARCHAR).param("c", body.contact(), Types.VARCHAR).update();
            log(s, null, null, "EXAM_CHANGED", null, body.name().trim(), null);
        }
        return overview(session, year);
    }

    public record StateIn(@NotBlank String state, @Size(max = 600) String note) {
    }

    @PostMapping("/exam/state")
    @PreAuthorize(OFFICE)
    @Transactional
    Map<String, Object> examState(@PathVariable String session, @PathVariable String year, @Valid @RequestBody StateIn body) {
        String s = ses(session, year);
        UUID id = examId(s);
        String st = body.state().trim().toUpperCase();
        if (!STATES.contains(st)) throw new DomainRuleViolation("PUTME_STATE", "'" + st + "' is not an examination state.", new DomainRuleViolation.Remedy("Use one of the desk's states.", "Academic Office"));
        if ("SCHEDULED".equals(st)) throw new DomainRuleViolation("PUTME_PUBLISH", "A schedule is published, not declared.", new DomainRuleViolation.Remedy("Press Publish Schedule once the validation stands.", "Academic Office"));
        String from = String.valueOf(exam(s).get("state"));
        jdbc.sql("UPDATE admissions.putme_exam SET state = :st, updated_at = now() WHERE id = :id").param("st", st).param("id", id).update();
        log(s, null, null, "EXAM_STATE", from, st, body.note());
        return overview(session, year);
    }

    /* ── centres, rooms, workstations ───────────────────────────────────── */

    public record CentreIn(@NotBlank @Size(max = 12) String code, @NotBlank @Size(max = 160) String name, @Size(max = 200) String location, @Size(max = 400) String address,
                           @Size(max = 160) String contactPerson, @Size(max = 200) String contactInfo, String state) {
    }

    @PostMapping("/centres")
    @PreAuthorize(OFFICE)
    @Transactional
    List<Map<String, Object>> saveCentre(@PathVariable String session, @PathVariable String year, @Valid @RequestBody CentreIn body) {
        jdbc.sql("""
                INSERT INTO admissions.cbt_centre (code, name, location, address, contact_person, contact_info, state)
                VALUES (:c, :n, :l, :a, :cp, :ci, :st)
                ON CONFLICT (code) DO UPDATE SET name = EXCLUDED.name, location = EXCLUDED.location, address = EXCLUDED.address, contact_person = EXCLUDED.contact_person, contact_info = EXCLUDED.contact_info, state = EXCLUDED.state
                """).param("c", body.code().trim().toUpperCase()).param("n", body.name().trim()).param("l", body.location(), Types.VARCHAR).param("a", body.address(), Types.VARCHAR)
                .param("cp", body.contactPerson(), Types.VARCHAR).param("ci", body.contactInfo(), Types.VARCHAR).param("st", "INACTIVE".equalsIgnoreCase(body.state()) ? "INACTIVE" : "ACTIVE").update();
        log(ses(session, year), null, null, "CENTRE_SAVED", null, body.code().trim().toUpperCase(), body.name().trim());
        return centres();
    }

    public record RoomIn(@NotBlank @Size(max = 12) String code, @NotBlank @Size(max = 160) String name, @Min(1) @Max(2000) int capacity, Integer workstations, String state) {
    }

    @PostMapping("/centres/{centreId}/rooms")
    @PreAuthorize(OFFICE)
    @Transactional
    List<Map<String, Object>> saveRoom(@PathVariable String session, @PathVariable String year, @PathVariable UUID centreId, @Valid @RequestBody RoomIn body) {
        int ws = body.workstations() == null ? body.capacity() : Math.max(0, Math.min(body.workstations(), body.capacity()));
        UUID id = jdbc.sql("""
                INSERT INTO admissions.cbt_room (centre_id, code, name, capacity, workstations, state)
                VALUES (:c, :code, :n, :cap, :ws, :st)
                ON CONFLICT (centre_id, code) DO UPDATE SET name = EXCLUDED.name, capacity = EXCLUDED.capacity, workstations = EXCLUDED.workstations, state = EXCLUDED.state
                RETURNING id
                """).param("c", centreId).param("code", body.code().trim().toUpperCase()).param("n", body.name().trim()).param("cap", body.capacity()).param("ws", ws)
                .param("st", "INACTIVE".equalsIgnoreCase(body.state()) ? "INACTIVE" : "ACTIVE").query(UUID.class).single();
        jdbc.sql("SELECT admissions.cbt_room_workstations(:r)").param("r", id).query(Integer.class).single();
        log(ses(session, year), null, null, "ROOM_SAVED", null, body.code().trim().toUpperCase(), body.name().trim() + " · " + body.capacity() + " seats, " + ws + " workstations");
        return centres();
    }

    @GetMapping("/rooms/{roomId}/workstations")
    @PreAuthorize(READERS)
    List<Map<String, Object>> workstations(@PathVariable String session, @PathVariable String year, @PathVariable UUID roomId) {
        return jdbc.sql("SELECT id, number, label, operational FROM admissions.cbt_workstation WHERE room_id = :r ORDER BY number").param("r", roomId).query().listOfRows();
    }

    public record WorkstationIn(@NotNull Boolean operational) {
    }

    @PutMapping("/workstations/{id}")
    @PreAuthorize(OFFICE)
    @Transactional
    Map<String, Object> workstation(@PathVariable String session, @PathVariable String year, @PathVariable UUID id, @Valid @RequestBody WorkstationIn body) {
        jdbc.sql("UPDATE admissions.cbt_workstation SET operational = :o WHERE id = :id").param("o", body.operational()).param("id", id).update();
        return jdbc.sql("SELECT id, number, label, operational FROM admissions.cbt_workstation WHERE id = :id").param("id", id).query().singleRow();
    }

    /* ── the examination's centres, days and slots ──────────────────────── */

    public record IdsIn(@NotNull List<UUID> ids) {
    }

    @PutMapping("/exam/centres")
    @PreAuthorize(OFFICE)
    @Transactional
    Map<String, Object> examCentres(@PathVariable String session, @PathVariable String year, @Valid @RequestBody IdsIn body) {
        String s = ses(session, year);
        UUID e = examId(s);
        jdbc.sql("UPDATE admissions.putme_exam_centre SET active = false WHERE exam_id = :e").param("e", e).update();
        for (UUID c : body.ids()) {
            jdbc.sql("INSERT INTO admissions.putme_exam_centre (exam_id, centre_id, active) VALUES (:e, :c, true) ON CONFLICT (exam_id, centre_id) DO UPDATE SET active = true").param("e", e).param("c", c).update();
        }
        log(s, null, null, "EXAM_CENTRES", null, body.ids().size() + " centre(s)", null);
        return overview(session, year);
    }

    public record DaysIn(@NotNull List<LocalDate> dates) {
    }

    @PutMapping("/exam/days")
    @PreAuthorize(OFFICE)
    @Transactional
    Map<String, Object> examDays(@PathVariable String session, @PathVariable String year, @Valid @RequestBody DaysIn body) {
        String s = ses(session, year);
        UUID e = examId(s);
        jdbc.sql("UPDATE admissions.putme_day SET active = false WHERE exam_id = :e").param("e", e).update();
        for (LocalDate d : body.dates()) {
            jdbc.sql("INSERT INTO admissions.putme_day (exam_id, held_on, active) VALUES (:e, :d, true) ON CONFLICT (exam_id, held_on) DO UPDATE SET active = true").param("e", e).param("d", d).update();
        }
        log(s, null, null, "EXAM_DAYS", null, body.dates().size() + " day(s)", String.valueOf(body.dates()));
        return overview(session, year);
    }

    public record SlotIn(@NotBlank @Size(max = 20) String code, @NotNull LocalTime startsAt, @NotNull LocalTime endsAt) {
    }

    public record SlotsIn(@NotNull List<@Valid SlotIn> slots) {
    }

    @PutMapping("/exam/slots")
    @PreAuthorize(OFFICE)
    @Transactional
    Map<String, Object> examSlots(@PathVariable String session, @PathVariable String year, @Valid @RequestBody SlotsIn body) {
        String s = ses(session, year);
        UUID e = examId(s);
        jdbc.sql("UPDATE admissions.putme_slot SET active = false WHERE exam_id = :e").param("e", e).update();
        int ord = 0;
        for (SlotIn sl : body.slots()) {
            if (!sl.endsAt().isAfter(sl.startsAt())) throw new DomainRuleViolation("PUTME_SLOT", "Slot " + sl.code() + " ends before it starts.", new DomainRuleViolation.Remedy("Give it an end after its start.", "Academic Office"));
            ord++;
            jdbc.sql("""
                    INSERT INTO admissions.putme_slot (exam_id, code, starts_at, ends_at, ord, active) VALUES (:e, :c, :a, :b, :o, true)
                    ON CONFLICT (exam_id, code) DO UPDATE SET starts_at = EXCLUDED.starts_at, ends_at = EXCLUDED.ends_at, ord = EXCLUDED.ord, active = true
                    """).param("e", e).param("c", sl.code().trim().toUpperCase()).param("a", sl.startsAt()).param("b", sl.endsAt()).param("o", ord).update();
        }
        log(s, null, null, "EXAM_SLOTS", null, body.slots().size() + " slot(s)", null);
        return overview(session, year);
    }

    /* ── the candidates ─────────────────────────────────────────────────── */

    @GetMapping("/candidates")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> candidates(@PathVariable String session, @PathVariable String year, @RequestParam(required = false) String status,
                                   @RequestParam(required = false) String fac, @RequestParam(required = false) String dept, @RequestParam(required = false) String prog,
                                   @RequestParam(required = false) UUID batch, @RequestParam(required = false) String centre, @RequestParam(required = false) String q,
                                   @RequestParam(defaultValue = "0") int page, @RequestParam(defaultValue = "200") int size) {
        String s = ses(session, year);
        String st = status == null || status.isBlank() ? null : status.trim().toUpperCase();
        String stPred = st == null ? "" : "SCHEDULED".equals(st) ? " AND c.status IN ('SCHEDULED','RESCHEDULED')" : "UNSCHEDULED".equals(st) ? " AND c.status IN ('READY_FOR_SCHEDULING','RESCHEDULE_REQUIRED')" : "ELIGIBLE".equals(st) ? " AND c.status <> 'NOT_ELIGIBLE'" : " AND c.status = :st";
        String needle = q == null || q.isBlank() ? null : "%" + q.trim().toLowerCase() + "%";
        int sz = Math.max(1, Math.min(size, 2000)), pg = Math.max(0, page);
        JdbcClient.StatementSpec spec = jdbc.sql("""
                SELECT count(*) OVER () AS total_rows, c.* FROM admissions.putme_candidates(:s) c
                 WHERE (:fac::text IS NULL OR c.faculty_code = :fac) AND (:dept::text IS NULL OR c.dept_code = :dept) AND (:prog::text IS NULL OR c.programme_code = :prog)
                   AND (:batch::uuid IS NULL OR c.batch_id = :batch) AND (:centre::text IS NULL OR c.centre = :centre)
                   AND (:q::text IS NULL OR lower(c.surname || ' ' || c.other_names) LIKE :q OR lower(c.application_no) LIKE :q OR lower(c.jamb_reg_no) LIKE :q OR lower(c.programme) LIKE :q)
                """ + stPred + " ORDER BY c.surname, c.other_names, c.application_no LIMIT :n OFFSET :o")
                .param("s", s).param("fac", blank(fac), Types.VARCHAR).param("dept", blank(dept), Types.VARCHAR).param("prog", blank(prog), Types.VARCHAR)
                .param("batch", batch, Types.OTHER).param("centre", blank(centre), Types.VARCHAR).param("q", needle, Types.VARCHAR).param("n", sz).param("o", pg * sz);
        if (stPred.contains(":st")) spec = spec.param("st", st);
        List<Map<String, Object>> rows = spec.query().listOfRows();
        long total = rows.isEmpty() ? 0 : ((Number) rows.get(0).get("total_rows")).longValue();
        rows.forEach(r -> r.remove("total_rows"));
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("session", s); out.put("total", total); out.put("page", pg); out.put("size", sz); out.put("rows", rows);
        out.put("options", jdbc.sql("""
                SELECT DISTINCT faculty_code, faculty, dept_code, department, programme_code, programme FROM admissions.putme_candidates(:s) WHERE programme_code IS NOT NULL ORDER BY faculty, department, programme
                """).param("s", s).query().listOfRows());
        return out;
    }

    @GetMapping("/candidates/{id}/events")
    @PreAuthorize(READERS)
    List<Map<String, Object>> candidateEvents(@PathVariable String session, @PathVariable String year, @PathVariable UUID id) {
        return jdbc.sql("""
                SELECT e.action, e.from_value, e.to_value, e.note, e.actor_office, e.at, b.label AS batch,
                       CASE WHEN x.id IS NULL THEN NULL ELSE x.surname || ', ' || x.given_names END AS actor
                  FROM admissions.putme_event e LEFT JOIN admissions.screening_batch b ON b.id = e.batch_id LEFT JOIN iam.person x ON x.id = e.actor_id
                 WHERE e.application_id = :id ORDER BY e.at
                """).param("id", id).query().listOfRows();
    }

    @GetMapping("/candidates/{id}/seatings")
    @PreAuthorize(READERS)
    List<Map<String, Object>> seatings(@PathVariable String session, @PathVariable String year, @PathVariable UUID id) {
        return jdbc.sql("""
                SELECT sa.state, sa.seat, sa.reason, sa.assigned_at, sa.ended_at, sa.attendance, sa.exam_status, sa.checked_in_at, b.label, b.held_on, b.starts_at, b.ends_at, b.venue
                  FROM admissions.screening_assignment sa JOIN admissions.screening_batch b ON b.id = sa.batch_id WHERE sa.application_id = :id ORDER BY sa.assigned_at
                """).param("id", id).query().listOfRows();
    }

    /* ── generate, validate, publish ────────────────────────────────────── */

    @PostMapping("/generate")
    @PreAuthorize(OFFICE)
    @Transactional
    Map<String, Object> generate(@PathVariable String session, @PathVariable String year) {
        String s = ses(session, year);
        Map<String, Object> r = jdbc.sql("SELECT * FROM admissions.putme_generate(:e)").param("e", examId(s)).query().singleRow();
        Map<String, Object> out = new LinkedHashMap<>(r);
        out.put("overview", overview(session, year));
        return out;
    }

    @GetMapping("/validate")
    @PreAuthorize(READERS)
    List<Map<String, Object>> validate(@PathVariable String session, @PathVariable String year) {
        return jdbc.sql("SELECT * FROM admissions.putme_validate(:e)").param("e", examId(ses(session, year))).query().listOfRows();
    }

    @PostMapping("/publish")
    @PreAuthorize(OFFICE)
    @Transactional
    Map<String, Object> publish(@PathVariable String session, @PathVariable String year) {
        String s = ses(session, year);
        int told = jdbc.sql("SELECT admissions.putme_publish(:e)").param("e", examId(s)).query(Integer.class).single();
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("told", told);
        out.put("overview", overview(session, year));
        return out;
    }

    /* ── batches ────────────────────────────────────────────────────────── */

    @GetMapping("/batches")
    @PreAuthorize(READERS)
    List<Map<String, Object>> listBatches(@PathVariable String session, @PathVariable String year) {
        return batches(ses(session, year));
    }

    @GetMapping("/batches/{id}")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> batch(@PathVariable String session, @PathVariable String year, @PathVariable UUID id) {
        String s = ses(session, year);
        Map<String, Object> b = batches(s).stream().filter(x -> id.equals(x.get("id"))).findFirst().orElseThrow(() -> new NotFound("batch", id));
        Map<String, Object> out = new LinkedHashMap<>(b);
        out.put("candidates", jdbc.sql("SELECT * FROM admissions.putme_candidates(:s) WHERE batch_id = :b ORDER BY surname, other_names").param("s", s).param("b", id).query().listOfRows());
        out.put("byProgramme", jdbc.sql("SELECT programme, faculty, count(*) AS n FROM admissions.putme_candidates(:s) WHERE batch_id = :b GROUP BY programme, faculty ORDER BY programme").param("s", s).param("b", id).query().listOfRows());
        out.put("byFaculty", jdbc.sql("SELECT faculty, count(*) AS n FROM admissions.putme_candidates(:s) WHERE batch_id = :b GROUP BY faculty ORDER BY faculty").param("s", s).param("b", id).query().listOfRows());
        out.put("exam", exam(s));
        return out;
    }

    public record BatchStateIn(@NotBlank String state, @NotBlank @Size(max = 600) String reason) {
    }

    @PostMapping("/batches/{id}/state")
    @PreAuthorize(OFFICE)
    @Transactional
    Map<String, Object> batchState(@PathVariable String session, @PathVariable String year, @PathVariable UUID id, @Valid @RequestBody BatchStateIn body) {
        int n = jdbc.sql("SELECT admissions.putme_batch_state(:b, :st, :r)").param("b", id).param("st", body.state().trim().toUpperCase()).param("r", body.reason().trim()).query(Integer.class).single();
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("unseated", n);
        out.put("batches", batches(ses(session, year)));
        return out;
    }

    public record MoveIn(@NotNull List<UUID> applicationIds, @NotNull UUID batchId, @NotBlank @Size(max = 600) String reason) {
    }

    /** one candidate or many moved (or seated for the first time) into a batch: the same rule for each, the seat given in turn */
    @PostMapping("/move")
    @PreAuthorize(OFFICE)
    @Transactional
    Map<String, Object> move(@PathVariable String session, @PathVariable String year, @Valid @RequestBody MoveIn body) {
        List<Map<String, Object>> results = new ArrayList<>();
        for (UUID app : body.applicationIds()) {
            String r = jdbc.sql("SELECT admissions.putme_move(:a, :b, :r)").param("a", app).param("b", body.batchId()).param("r", body.reason().trim()).query(String.class).single();
            results.add(Map.of("applicationId", app, "result", r));
        }
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("moved", results);
        out.put("batches", batches(ses(session, year)));
        return out;
    }

    public record UnscheduleIn(@NotNull List<UUID> applicationIds, @NotBlank @Size(max = 600) String reason) {
    }

    @PostMapping("/unschedule")
    @PreAuthorize(OFFICE)
    @Transactional
    Map<String, Object> unschedule(@PathVariable String session, @PathVariable String year, @Valid @RequestBody UnscheduleIn body) {
        for (UUID app : body.applicationIds()) jdbc.sql("SELECT admissions.putme_unschedule(:a, :r)").param("a", app).param("r", body.reason().trim()).query().listOfRows();
        return Map.of("unscheduled", body.applicationIds().size(), "batches", batches(ses(session, year)));
    }

    /** the desk confirms a seating flagged after a programme change */
    @PostMapping("/candidates/{id}/confirm-schedule")
    @PreAuthorize(OFFICE)
    @Transactional
    Map<String, Object> confirmSchedule(@PathVariable String session, @PathVariable String year, @PathVariable UUID id) {
        jdbc.sql("UPDATE admissions.application SET schedule_review = false WHERE id = :id").param("id", id).update();
        log(ses(session, year), null, id, "SCHEDULE_CONFIRMED", null, null, "Seating confirmed after the programme change");
        return Map.of("ok", true);
    }

    /* ── the door and the hall ──────────────────────────────────────────── */

    public record CheckinIn(@NotBlank @Size(max = 80) String key) {
    }

    /** the candidate found by the slip's QR token, the application number or the JAMB number */
    @GetMapping("/lookup")
    @PreAuthorize(DOOR)
    @Transactional(readOnly = true)
    Map<String, Object> lookup(@PathVariable String session, @PathVariable String year, @RequestParam String key) {
        return find(ses(session, year), key);
    }

    private Map<String, Object> find(String s, String key) {
        String k = key.trim();
        String token = k.contains("/verify/putme/") ? k.substring(k.lastIndexOf('/') + 1) : k;
        Map<String, Object> c = jdbc.sql("""
                SELECT * FROM admissions.putme_candidates(:s) c WHERE c.putme_token = :t OR upper(c.application_no) = upper(:k) OR upper(c.jamb_reg_no) = upper(:k)
                """).param("s", s).param("t", token).param("k", k).query().listOfRows().stream().findFirst().orElseThrow(() -> new NotFound("candidate", k));
        Map<String, Object> out = new LinkedHashMap<>(c);
        out.put("passport_id", jdbc.sql("SELECT d.id FROM admissions.application_document d WHERE d.application_id = :a AND d.kind = 'PASSPORT' AND d.superseded_at IS NULL LIMIT 1")
                .param("a", c.get("application_id")).query(UUID.class).optional().orElse(null));
        return out;
    }

    @PostMapping("/checkin")
    @PreAuthorize(DOOR)
    @Transactional
    Map<String, Object> checkin(@PathVariable String session, @PathVariable String year, @Valid @RequestBody CheckinIn body) {
        String s = ses(session, year);
        Map<String, Object> c = find(s, body.key());
        String r = jdbc.sql("SELECT admissions.putme_checkin(:a, :by)").param("a", c.get("application_id")).param("by", AuditContextHolder.required().actorId()).query(String.class).single();
        Map<String, Object> out = new LinkedHashMap<>(find(s, body.key()));
        out.put("result", r);
        return out;
    }

    public record MarkIn(@NotNull UUID applicationId, String attendance, String examStatus, @Size(max = 400) String remarks) {
    }

    @PostMapping("/attendance")
    @PreAuthorize(DOOR)
    @Transactional
    Map<String, Object> mark(@PathVariable String session, @PathVariable String year, @Valid @RequestBody MarkIn body) {
        String att = body.attendance() == null || body.attendance().isBlank() ? null : body.attendance().trim().toUpperCase();
        String ex = body.examStatus() == null || body.examStatus().isBlank() ? null : body.examStatus().trim().toUpperCase();
        if (att != null && !Set.of("NOT_CHECKED_IN", "CHECKED_IN", "PRESENT", "ABSENT", "DISQUALIFIED").contains(att)) throw new DomainRuleViolation("PUTME_ATTENDANCE", "'" + att + "' is not an attendance status.", new DomainRuleViolation.Remedy("Not checked in, checked in, present, absent or disqualified.", "Academic Office"));
        if (ex != null && !Set.of("NOT_STARTED", "IN_PROGRESS", "COMPLETED", "ABSENT", "DISQUALIFIED").contains(ex)) throw new DomainRuleViolation("PUTME_EXAM_STATUS", "'" + ex + "' is not an examination status.", new DomainRuleViolation.Remedy("Not started, in progress, completed, absent or disqualified.", "Academic Office"));
        jdbc.sql("SELECT admissions.putme_mark(:a, :att, :ex, :r)").param("a", body.applicationId()).param("att", att, Types.VARCHAR).param("ex", ex, Types.VARCHAR).param("r", body.remarks(), Types.VARCHAR).query().listOfRows();
        return jdbc.sql("SELECT * FROM admissions.putme_candidates(:s) WHERE application_id = :a").param("s", ses(session, year)).param("a", body.applicationId()).query().singleRow();
    }

    /* ── helpers ────────────────────────────────────────────────────────── */

    private static String blank(String v) {
        return v == null || v.isBlank() ? null : v.trim();
    }

    private void log(String s, UUID batch, UUID app, String action, String from, String to, String note) {
        Map<String, Object> x = exam(s);
        jdbc.sql("SELECT admissions.putme_log(:e, :b, :a, :act, :f, :t, :n)").param("e", x == null ? null : x.get("id"), Types.OTHER).param("b", batch, Types.OTHER).param("a", app, Types.OTHER)
                .param("act", action).param("f", from, Types.VARCHAR).param("t", to, Types.VARCHAR).param("n", note, Types.VARCHAR).query().listOfRows();
    }
}
