package ng.edu.moaum.portal.gst;

import java.sql.Types;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;
import ng.edu.moaum.portal.shared.AuditContext;
import ng.edu.moaum.portal.shared.AuditContextHolder;
import ng.edu.moaum.portal.shared.NotFound;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.AccessDeniedException;
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
 * V492: the GST & EPS examination permits on the GST and EPS offices' desks. An office sees the students an approved
 * registration of its own courses concerns, for a session and semester, with each one's permit (generated, downloaded,
 * printed, withdrawn), the examination schedule of its courses, a student's permit as the student sees it, and a permit found
 * by its reference. It withdraws or restores a permit that carries one of its courses, with a reason. It never changes a
 * registration: the registration stays the Registry's and the student's, the fee the Bursary's.
 */
@RestController
@RequestMapping("/api/v1/gst")
class GstPermitController {

    private static final String READERS =
            "hasAnyAuthority('OFFICE_gst','OFFICE_eps','OFFICE_bursar','OFFICE_financecontroller','OFFICE_registrar','OFFICE_dregistrar',"
            + "'OFFICE_dvc','OFFICE_vc','OFFICE_academic','OFFICE_records','OFFICE_ict','OFFICE_admin','OFFICE_super')";
    private static final String MANAGERS = "hasAnyAuthority('OFFICE_gst','OFFICE_eps','OFFICE_super')";
    private static final Set<String> OFFICES = Set.of("GST", "EPS");
    private static final Set<String> STATUSES = Set.of("NOT_GENERATED", "GENERATED", "DOWNLOADED", "PRINTED", "REVOKED");

    public record ReasonIn(@NotBlank @Size(min = 10, max = 500) String reason) {
    }

    private final JdbcClient jdbc;

    GstPermitController(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    /** the office's students for the session and semester, with their permits, the figures and the schedule of its courses */
    @GetMapping("/{office}/permits")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> permits(@PathVariable String office, @RequestParam(required = false) String session, @RequestParam(required = false) Integer semester,
                                @RequestParam(required = false) String status, @RequestParam(required = false) String course, @RequestParam(required = false) String q,
                                @RequestParam(defaultValue = "0") int page, @RequestParam(defaultValue = "50") int size) {
        String o = office(office);
        String s = session(session);
        int sem = semester == null ? semesterOf(s) : Math.max(1, Math.min(3, semester));
        String st = status == null || status.isBlank() || "ALL".equalsIgnoreCase(status) ? null : status.trim().toUpperCase();
        if (st != null && !STATUSES.contains(st)) throw new ng.edu.moaum.portal.shared.DomainRuleViolation("GST_EPS_PERMIT_STATUS", "A permit is NOT_GENERATED, GENERATED, DOWNLOADED, PRINTED or REVOKED.");
        String code = course == null || course.isBlank() ? null : course.trim().toUpperCase();
        String like = q == null || q.isBlank() ? null : "%" + q.trim().toUpperCase().replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_") + "%";
        int sz = Math.max(1, Math.min(size, 500)), pg = Math.max(0, page);

        Map<String, Object> figures = jdbc.sql("""
                SELECT count(*) AS students, count(permit_id) AS generated, count(*) - count(permit_id) AS not_generated,
                       count(*) FILTER (WHERE downloaded > 0) AS downloaded, count(*) FILTER (WHERE printed > 0) AS printed,
                       count(*) FILTER (WHERE revoked_at IS NOT NULL) AS revoked
                  FROM registration.gst_eps_permit_roster(:s, :sem, :o)
                """).param("s", s).param("sem", sem).param("o", o).query().singleRow();
        List<Map<String, Object>> rows = jdbc.sql("""
                SELECT r.*, count(*) OVER () AS total_rows
                  FROM registration.gst_eps_permit_roster(:s, :sem, :o) r
                 WHERE (:st::text IS NULL OR coalesce(r.permit_status, 'NOT_GENERATED') = :st)
                   AND (:code::text IS NULL OR (', ' || r.courses || ', ') LIKE '%, ' || :code || ', %')
                   AND (:like::text IS NULL OR upper(r.number) LIKE :like ESCAPE '\\' OR upper(r.name) LIKE :like ESCAPE '\\')
                 ORDER BY r.name, r.number
                 LIMIT :n OFFSET :off
                """).param("s", s).param("sem", sem).param("o", o).param("st", st, Types.VARCHAR).param("code", code, Types.VARCHAR)
                .param("like", like, Types.VARCHAR).param("n", sz).param("off", pg * sz).query().listOfRows();
        long total = rows.isEmpty() ? 0 : ((Number) rows.get(0).get("total_rows")).longValue();
        rows.forEach(r -> r.remove("total_rows"));

        Map<String, Object> out = new LinkedHashMap<>();
        out.put("office", o);
        out.put("session", s);
        out.put("semester", sem);
        out.put("figures", figures);
        out.put("courses", schedule(o, s, sem));
        out.put("total", total);
        out.put("page", pg);
        out.put("size", sz);
        out.put("rows", rows);
        return out;
    }

    /** one student's permit for the session and semester, as the student sees it, with what was done with it */
    @GetMapping("/{office}/permits/students/{id}")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> student(@PathVariable String office, @PathVariable UUID id, @RequestParam(required = false) String session,
                                @RequestParam(required = false) Integer semester) {
        String o = office(office);
        String s = session(session);
        int sem = semester == null ? semesterOf(s) : Math.max(1, Math.min(3, semester));
        reach(o, id, s, sem);
        Map<String, Object> out = read(
                jdbc.sql("SELECT registration.gst_eps_permit_state(:id, :s, :sem)::text").param("id", id).param("s", s).param("sem", sem).query(String.class).single());
        out.put("studentId", id);
        out.put("permitId", jdbc.sql("SELECT id FROM registration.gst_eps_permit WHERE student_id = :id AND session = :s AND semester = :sem")
                .param("id", id).param("s", s).param("sem", sem).query(UUID.class).optional().orElse(null));
        out.put("events", jdbc.sql("""
                SELECT ev.action, ev.courses::text AS courses, ev.reason, ev.actor_office, ev.at,
                       coalesce(nullif(btrim(coalesce(p.given_names, '') || ' ' || coalesce(p.surname, '')), ''), CASE WHEN ev.actor_id = pm.student_id THEN 'the student' END) AS actor
                  FROM registration.gst_eps_permit_event ev JOIN registration.gst_eps_permit pm ON pm.id = ev.permit_id
                  LEFT JOIN iam.person p ON p.id = ev.actor_id
                 WHERE pm.student_id = :id AND pm.session = :s AND pm.semester = :sem
                 ORDER BY ev.at DESC LIMIT 200
                """).param("id", id).param("s", s).param("sem", sem).query().listOfRows());
        return out;
    }

    /** a permit found by its reference (GST-EPS/2026/000001): whose it is, for the drill-down */
    @GetMapping("/{office}/permits/lookup")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> lookup(@PathVariable String office, @RequestParam String reference) {
        String o = office(office);
        Map<String, Object> row = jdbc.sql("SELECT student_id, session, semester FROM registration.gst_eps_permit WHERE reference = :r")
                .param("r", reference == null ? "" : reference.trim().toUpperCase()).query().listOfRows().stream().findFirst()
                .orElseThrow(() -> new NotFound("permit", reference));
        reach(o, (UUID) row.get("student_id"), (String) row.get("session"), ((Number) row.get("semester")).intValue());
        return row;
    }

    /** withdraw a permit carrying one of the office's courses, with the reason; the student is told, without the reason */
    @PostMapping("/{office}/permits/{id}/revoke")
    @PreAuthorize(MANAGERS)
    @Transactional
    Map<String, Object> revoke(@PathVariable String office, @PathVariable UUID id, @Valid @RequestBody ReasonIn body) {
        return decide(office, id, body.reason(), false);
    }

    /** restore a withdrawn permit, with the reason */
    @PostMapping("/{office}/permits/{id}/restore")
    @PreAuthorize(MANAGERS)
    @Transactional
    Map<String, Object> restore(@PathVariable String office, @PathVariable UUID id, @Valid @RequestBody ReasonIn body) {
        return decide(office, id, body.reason(), true);
    }

    /* ── the parts ── */

    private Map<String, Object> decide(String office, UUID id, String reason, boolean restore) {
        String o = manage(office);
        if (jdbc.sql("SELECT count(*) FROM registration.gst_eps_permit WHERE id = :id").param("id", id).query(Long.class).single() == 0) {
            throw new NotFound("permit", id);
        }
        String acting = AuditContextHolder.current().map(AuditContext::actorOffice).orElse("");
        return read(jdbc.sql("SELECT registration.revoke_gst_eps_permit(:id, :o, :r, :restore)::text")
                .param("id", id).param("o", "super".equals(acting) ? "SUPER" : o).param("r", reason.trim()).param("restore", restore).query(String.class).single());
    }

    /** the examination schedule of the office's courses that run in the semester: the timetable's slot or the CBT examination */
    private List<Map<String, Object>> schedule(String office, String session, int semester) {
        return jdbc.sql("""
                SELECT c.code AS course_code, coalesce(o.title, c.title) AS title, c.units, c.general_office AS course_type, o.stream,
                       (SELECT count(DISTINCT r.student_id) FROM registration.entry e
                          JOIN registration.course_registration r ON r.id = e.registration_id AND r.session = :s AND r.semester = :sem AND r.status IN ('APPROVED', 'LOCKED')
                         WHERE e.offering_id = o.id AND e.status IN ('REGISTERED', 'APPROVED')) AS registered,
                       t.held_on, t.starts_at, t.ends_at, t.venue,
                       x.reference AS cbt_reference, x.state AS cbt_state, x.starts_at AS cbt_starts_at, x.ends_at AS cbt_ends_at, x.venue AS cbt_venue,
                       (SELECT count(*) FROM assessment.cbt_sitting si WHERE si.exam_id = x.id) AS cbt_sittings
                  FROM catalogue.course c
                  JOIN catalogue.offering o ON o.course_code = c.code AND o.session = :s AND o.semester = :sem
                  LEFT JOIN assessment.exam_timetable t ON t.offering_id = o.id
                  LEFT JOIN LATERAL (SELECT * FROM assessment.cbt_exam x WHERE x.offering_id = o.id AND x.state <> 'CANCELLED' ORDER BY x.created_at DESC LIMIT 1) x ON true
                 WHERE c.kind = 'GST' AND c.general_office = :o AND c.code NOT LIKE 'DMO %'
                 ORDER BY c.code, o.stream
                """).param("s", session).param("sem", semester).param("o", office).query().listOfRows();
    }

    /** the GST and EPS offices read a student only when an approved registration of the semester carries one of their courses */
    private void reach(String office, UUID student, String session, int semester) {
        String acting = AuditContextHolder.current().map(AuditContext::actorOffice).orElse("");
        if (!("gst".equals(acting) || "eps".equals(acting))) return;
        boolean concerned = jdbc.sql("""
                SELECT EXISTS (SELECT 1 FROM registration.course_registration r
                                 JOIN registration.entry e ON e.registration_id = r.id AND e.status IN ('REGISTERED', 'APPROVED')
                                 JOIN catalogue.offering o ON o.id = e.offering_id
                                 JOIN catalogue.course c ON c.code = o.course_code AND c.kind = 'GST' AND c.general_office = :o
                                WHERE r.student_id = :id AND r.session = :s AND r.semester = :sem AND r.status IN ('APPROVED', 'LOCKED'))
                    OR EXISTS (SELECT 1 FROM registration.gst_eps_permit pm, jsonb_array_elements(pm.courses) x
                                WHERE pm.student_id = :id AND pm.session = :s AND pm.semester = :sem AND x->>'type' = :o)
                """).param("o", office).param("id", student).param("s", session).param("sem", semester).query(Boolean.class).single();
        if (!concerned) throw new NotFound("permit", student);
    }

    /** the office named on the path, and whether the acting office may read it: GST sees GST, EPS sees EPS, the rest see both */
    private static String office(String path) {
        String o = path == null ? "" : path.trim().toUpperCase();
        if (!OFFICES.contains(o)) throw new NotFound("office", path);
        String acting = AuditContextHolder.current().map(AuditContext::actorOffice).orElse("");
        if (("gst".equals(acting) && !"GST".equals(o)) || ("eps".equals(acting) && !"EPS".equals(o))) {
            throw new AccessDeniedException("The " + acting.toUpperCase() + " office reads its own desk; the " + o + " desk is the other office's.");
        }
        return o;
    }

    /** the office whose permits are withdrawn: its own, never the other's */
    private static String manage(String path) {
        String o = office(path);
        String acting = AuditContextHolder.current().map(AuditContext::actorOffice).orElse("");
        if (!("super".equals(acting) || acting.equalsIgnoreCase(o))) {
            throw new AccessDeniedException("Only the " + o + " office withdraws or restores a permit for its courses.");
        }
        return o;
    }

    private String session(String asked) {
        if (asked != null && asked.matches("\\d{4}/\\d{4}")) return asked;
        return jdbc.sql("SELECT coalesce((SELECT name FROM policy.academic_session WHERE state = 'CURRENT'), (SELECT max(name) FROM policy.academic_session WHERE state <> 'PLANNED'), (SELECT max(name) FROM policy.academic_session))")
                .query(String.class).single();
    }

    /** the semester the University's calendar has open in the session, or the first */
    private int semesterOf(String session) {
        return jdbc.sql("SELECT coalesce(max(number), 1) FROM policy.semester WHERE session = :s AND state = 'OPEN'").param("s", session).query(Integer.class).single();
    }

    private static final tools.jackson.databind.ObjectMapper JSON = new tools.jackson.databind.ObjectMapper();

    @SuppressWarnings("unchecked")
    private static Map<String, Object> read(String json) {
        return new LinkedHashMap<>(JSON.readValue(json, Map.class));
    }
}
