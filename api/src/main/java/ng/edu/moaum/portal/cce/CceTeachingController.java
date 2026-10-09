package ng.edu.moaum.portal.cce;

import java.time.LocalDate;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

import ng.edu.moaum.portal.shared.AuditContextHolder;
import ng.edu.moaum.portal.shared.DomainRuleViolation;
import ng.edu.moaum.portal.shared.NotFound;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * A lecturer's evening classes of the Centre for Continuing Education (V380): their CCE classes in the CCE session, the
 * slots, the class list, and the attendance register of each lecture — present, absent, late or excused; a saved mark
 * corrected with its reason; locked when done (the Centre or the Academic Office reopens a locked register, with a reason).
 * A lecturer reaches only the classes they teach; the Centre and the Academic Office reach every CCE class.
 */
@RestController
@RequestMapping("/api/v1/cce/teaching")
class CceTeachingController {

    static final String TEACH = "hasAnyAuthority('OFFICE_lecturer','OFFICE_hod','OFFICE_dean','OFFICE_cce','OFFICE_academic','OFFICE_super')";

    private final JdbcClient jdbc;
    private final tools.jackson.databind.ObjectMapper json;

    CceTeachingController(JdbcClient jdbc, tools.jackson.databind.ObjectMapper json) {
        this.jdbc = jdbc;
        this.json = json;
    }

    private static UUID me() {
        return AuditContextHolder.required().actorId();
    }

    private static boolean centre() {
        String office = AuditContextHolder.current().map(c -> c.actorOffice()).orElse(null);
        return "cce".equals(office) || "academic".equals(office) || "super".equals(office);
    }

    /** the class, if it is a CCE class the person teaches (or the Centre or the Academic Office asks) — else refused */
    private Map<String, Object> reach(UUID offering) {
        Map<String, Object> o = jdbc.sql("""
                SELECT o.id, o.course_code, coalesce(o.title, c.title) AS title, coalesce(o.units, c.units) AS units, c.level, o.session, o.semester, o.stream,
                       nullif(btrim(coalesce(lp.surname, '') || ', ' || coalesce(lp.given_names, '')), ',') AS lecturer,
                       attendance.course_teaches(:me, o.id) AS teaches
                  FROM catalogue.offering o JOIN catalogue.course c ON c.code = o.course_code LEFT JOIN iam.person lp ON lp.id = o.lecturer_id
                 WHERE o.id = :o
                """).param("o", offering).param("me", me()).query().listOfRows().stream().findFirst().orElseThrow(() -> new NotFound("class", offering));
        if (!"CCE".equals(o.get("stream"))) {
            throw new NotFound("CCE class", offering);
        }
        if (!Boolean.TRUE.equals(o.get("teaches")) && !centre()) {
            throw new AccessDeniedException(o.get("course_code") + " is not a class you teach; a lecturer keeps the register of their own classes.");
        }
        return o;
    }

    private Map<String, Object> register(UUID id) {
        Map<String, Object> r = jdbc.sql("""
                SELECT r.id, r.subject_ref AS class_id, r.session, r.semester, r.held_on, r.topic, r.slot_ref, r.saved_at, r.locked_at,
                       nullif(btrim(coalesce(lb.surname, '') || ', ' || coalesce(lb.given_names, '')), ',') AS locked_by,
                       nullif(btrim(coalesce(ob.surname, '') || ', ' || coalesce(ob.given_names, '')), ',') AS opened_by,
                       to_char(s.starts_at, 'HH24:MI') AS starts_at, to_char(s.ends_at, 'HH24:MI') AS ends_at, s.venue
                  FROM attendance.register r
                  LEFT JOIN catalogue.class_slot s ON s.id = r.slot_ref
                  LEFT JOIN iam.person lb ON lb.id = r.locked_by
                  LEFT JOIN iam.person ob ON ob.id = r.opened_by
                 WHERE r.id = :id AND r.context = 'COURSE'
                """).param("id", id).query().listOfRows().stream().findFirst().orElseThrow(() -> new NotFound("register", id));
        reach((UUID) r.get("class_id"));
        return r;
    }

    /** the CCE classes the person teaches: the CCE session's (and the one after it), else every CCE class for the Centre */
    @GetMapping
    @PreAuthorize(TEACH)
    @Transactional(readOnly = true)
    Map<String, Object> mine() {
        UUID me = me();
        boolean all = centre();
        Map<String, Object> out = new LinkedHashMap<>();
        String s = jdbc.sql("SELECT policy.route_session('CCE')").query(String.class).single();
        out.put("session", s);
        out.put("all", all);
        List<Map<String, Object>> rows = jdbc.sql("""
                SELECT o.id, o.course_code, coalesce(o.title, c.title) AS title, coalesce(o.units, c.units) AS units, c.level, o.session, o.semester,
                       d.name AS department,
                       CASE WHEN o.lecturer_id = :me THEN 'Lecturer' WHEN o.second_examiner_id = :me THEN 'Second examiner'
                            WHEN EXISTS (SELECT 1 FROM catalogue.offering_teacher t WHERE t.offering_id = o.id AND t.lecturer_id = :me) THEN 'Co-lecturer' END AS role,
                       nullif(btrim(coalesce(lp.surname, '') || ', ' || coalesce(lp.given_names, '')), ',') AS lecturer,
                       (SELECT count(*) FROM registration.entry e JOIN registration.course_registration r ON r.id = e.registration_id
                         WHERE e.offering_id = o.id AND e.status IN ('REGISTERED', 'APPROVED') AND r.status IN ('SUBMITTED', 'APPROVED', 'LOCKED')) AS students,
                       (SELECT count(*) FROM attendance.register ar WHERE ar.context = 'COURSE' AND ar.subject_ref = o.id) AS registers,
                       (SELECT max(ar.held_on) FROM attendance.register ar WHERE ar.context = 'COURSE' AND ar.subject_ref = o.id) AS last_held,
                       coalesce((SELECT jsonb_agg(jsonb_build_object('id', sl.id, 'weekday', sl.weekday, 'starts_at', to_char(sl.starts_at, 'HH24:MI'),
                                                                     'ends_at', to_char(sl.ends_at, 'HH24:MI'), 'venue', sl.venue, 'kind', sl.kind) ORDER BY sl.weekday, sl.starts_at)
                                   FROM catalogue.class_slot sl WHERE sl.offering_id = o.id AND sl.ended_at IS NULL), '[]'::jsonb)::text AS slots
                  FROM catalogue.offering o
                  JOIN catalogue.course c ON c.code = o.course_code
                  LEFT JOIN ref.department d ON d.code = c.dept_code
                  LEFT JOIN iam.person lp ON lp.id = o.lecturer_id
                 WHERE o.stream = 'CCE' AND o.session IN (:s, policy.session_after(:s, 1))
                   AND (:all OR attendance.course_teaches(:me, o.id))
                 ORDER BY o.session, o.semester, c.level, o.course_code
                """).param("me", me).param("s", s).param("all", all).query().listOfRows();
        out.put("classes", rows.stream().map(r -> {
            Map<String, Object> m = new LinkedHashMap<>(r);
            m.put("slots", json.readValue(String.valueOf(r.get("slots")), List.class));
            return m;
        }).toList());
        return out;
    }

    /** one class: its slots, its class list and its registers */
    @GetMapping("/classes/{id}")
    @PreAuthorize(TEACH)
    @Transactional(readOnly = true)
    Map<String, Object> one(@PathVariable UUID id) {
        Map<String, Object> out = new LinkedHashMap<>(reach(id));
        out.put("slots", jdbc.sql("""
                SELECT id, weekday, to_char(starts_at, 'HH24:MI') AS starts_at, to_char(ends_at, 'HH24:MI') AS ends_at, venue, kind
                  FROM catalogue.class_slot WHERE offering_id = :o AND ended_at IS NULL ORDER BY weekday, starts_at
                """).param("o", id).query().listOfRows());
        out.put("students", jdbc.sql("""
                SELECT st.id, coalesce(st.matric_no, st.admission_no) AS number, st.surname || ', ' || st.other_names AS name, st.programme_code,
                       p.name AS programme, r.level, r.status AS registration, e.entry_type,
                       count(k.id) FILTER (WHERE k.status <> 'EXCUSED') AS counted, count(k.id) FILTER (WHERE k.status IN ('PRESENT', 'LATE')) AS attended,
                       count(k.id) FILTER (WHERE k.status = 'LATE') AS late, count(k.id) FILTER (WHERE k.status = 'EXCUSED') AS excused
                  FROM registration.entry e
                  JOIN registration.course_registration r ON r.id = e.registration_id AND r.status IN ('SUBMITTED', 'APPROVED', 'LOCKED')
                  JOIN people.student st ON st.id = r.student_id
                  JOIN ref.programme p ON p.code = st.programme_code
                  LEFT JOIN attendance.register ar ON ar.context = 'COURSE' AND ar.subject_ref = e.offering_id
                  LEFT JOIN attendance.mark k ON k.register_id = ar.id AND k.member_ref = st.id
                 WHERE e.offering_id = :o AND e.status IN ('REGISTERED', 'APPROVED')
                 GROUP BY st.id, st.matric_no, st.admission_no, st.surname, st.other_names, st.programme_code, p.name, r.level, r.status, e.entry_type
                 ORDER BY st.surname, st.other_names
                """).param("o", id).query().listOfRows());
        out.put("registers", jdbc.sql("""
                SELECT r.id, r.held_on, r.topic, r.saved_at, r.locked_at, to_char(s.starts_at, 'HH24:MI') AS starts_at, s.venue,
                       count(k.id) AS marked, count(k.id) FILTER (WHERE k.status = 'PRESENT') AS present, count(k.id) FILTER (WHERE k.status = 'LATE') AS late,
                       count(k.id) FILTER (WHERE k.status = 'ABSENT') AS absent, count(k.id) FILTER (WHERE k.status = 'EXCUSED') AS excused
                  FROM attendance.register r
                  LEFT JOIN catalogue.class_slot s ON s.id = r.slot_ref
                  LEFT JOIN attendance.mark k ON k.register_id = r.id
                 WHERE r.context = 'COURSE' AND r.subject_ref = :o
                 GROUP BY r.id, r.held_on, r.topic, r.saved_at, r.locked_at, s.starts_at, s.venue
                 ORDER BY r.held_on DESC, s.starts_at
                """).param("o", id).query().listOfRows());
        out.put("policy", jdbc.sql("SELECT * FROM attendance.course_policy(:o)").param("o", id).query().listOfRows().stream().findFirst().orElse(null));
        return out;
    }

    public record Open(@NotNull LocalDate heldOn, UUID slotId, @Size(max = 300) String topic) {
    }

    /** the register of one lecture: opened (or found) for the day, on one of the class's slots when named */
    @PostMapping("/classes/{id}/registers")
    @PreAuthorize(TEACH)
    @Transactional
    Map<String, Object> open(@PathVariable UUID id, @Valid @RequestBody Open body) {
        Map<String, Object> o = reach(id);
        UUID rid = jdbc.sql("SELECT attendance.open_register('COURSE', :s, :sem, :o, NULL, :d, :t, :me)")
                .param("s", o.get("session")).param("sem", o.get("semester")).param("o", id).param("d", body.heldOn())
                .param("t", body.topic() == null || body.topic().isBlank() ? null : body.topic().trim()).param("me", me()).query(UUID.class).single();
        if (body.slotId() != null) {
            jdbc.sql("UPDATE attendance.register SET slot_ref = :sl WHERE id = :r AND slot_ref IS NULL AND locked_at IS NULL").param("sl", body.slotId()).param("r", rid).update();
        }
        return sheet(rid);
    }

    /** a register with its class list and each student's mark */
    @GetMapping("/registers/{id}")
    @PreAuthorize(TEACH)
    @Transactional(readOnly = true)
    Map<String, Object> sheet(@PathVariable UUID id) {
        Map<String, Object> out = new LinkedHashMap<>(register(id));
        out.put("marks", jdbc.sql("""
                SELECT x.member_ref AS student_id, x.name, x.application_no AS number, x.combination_code AS programme_code, x.class_name AS level,
                       k.status, to_char(k.marked_time, 'HH24:MI') AS marked_time, k.remarks, k.marked_at
                  FROM attendance.roster(:r) x LEFT JOIN attendance.mark k ON k.register_id = :r AND k.member_ref = x.member_ref
                """).param("r", id).query().listOfRows());
        out.put("changes", jdbc.sql("""
                SELECT c.member_ref AS student_id, c.old_status, c.new_status, c.reason, c.changed_at,
                       nullif(btrim(coalesce(p.surname, '') || ', ' || coalesce(p.given_names, '')), ',') AS changed_by
                  FROM attendance.mark_change c LEFT JOIN iam.person p ON p.id = c.changed_by
                 WHERE c.register_id = :r ORDER BY c.changed_at DESC
                """).param("r", id).query().listOfRows());
        return out;
    }

    public record Mark(@NotNull UUID student, @NotNull @Pattern(regexp = "PRESENT|ABSENT|LATE|EXCUSED") String status, @Pattern(regexp = "\\d{2}:\\d{2}") String time,
                       @Size(max = 300) String remarks) {
    }

    public record Marks(@NotNull @Size(max = 2000) List<@Valid Mark> marks, @Size(max = 600) String reason) {
    }

    /** the marks saved; a saved mark changed says why; a locked register is not changed here */
    @PutMapping("/registers/{id}/marks")
    @PreAuthorize(TEACH)
    @Transactional
    Map<String, Object> save(@PathVariable UUID id, @Valid @RequestBody Marks body) {
        register(id);
        List<Map<String, Object>> marks = body.marks().stream().map(m -> {
            Map<String, Object> x = new LinkedHashMap<>();
            x.put("member", m.student().toString());
            x.put("status", m.status());
            if (m.time() != null) x.put("time", m.time());
            if (m.remarks() != null) x.put("remarks", m.remarks());
            return x;
        }).toList();
        String result = jdbc.sql("SELECT attendance.save_marks(:r, :m::jsonb, :why, :me, false)::text").param("r", id).param("m", json.writeValueAsString(marks))
                .param("why", body.reason() == null || body.reason().isBlank() ? null : body.reason().trim(), java.sql.Types.VARCHAR).param("me", me()).query(String.class).single();
        Map<String, Object> out = new LinkedHashMap<>(sheet(id));
        out.put("result", json.readValue(result, Map.class));
        return out;
    }

    @PostMapping("/registers/{id}/lock")
    @PreAuthorize(TEACH)
    @Transactional
    Map<String, Object> lock(@PathVariable UUID id) {
        Map<String, Object> r = register(id);
        if (r.get("locked_at") != null) {
            throw new DomainRuleViolation("ATT_LOCKED", "This register is already locked.", new DomainRuleViolation.Remedy("The Centre reopens a locked register for correction.", "Centre for Continuing Education"));
        }
        jdbc.sql("SELECT attendance.lock_register(:r, :me, true, NULL)").param("r", id).param("me", me()).query().listOfRows();
        return sheet(id);
    }
}
