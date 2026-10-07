package ng.edu.moaum.portal.jupeb;

import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;

import ng.edu.moaum.portal.shared.AuditContextHolder;
import ng.edu.moaum.portal.shared.NotFound;

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
 * The next JUPEB session planned from the one before (V356): for each item — the settings, classes, calendar, timetable, the
 * parts of the continuous assessment, the minimum attendance and the lecturers' assignments — what the session it comes from
 * holds and what the next already holds, and the item carried only when the JUPEB Office says so, never over what is there.
 * The fees are shown but carried only by the Bursary (on its own JUPEB fees page); the application windows are the Director of
 * ICT's and are only shown. Reads for jupeb, super and admin; carrying for jupeb and super.
 */
@RestController
@RequestMapping("/api/v1/jupeb/office/rollover")
class JupebRolloverController {

    private final JdbcClient jdbc;

    JupebRolloverController(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    private static String next(String session) {
        int y = Integer.parseInt(session.substring(0, 4)) + 1;
        return y + "/" + (y + 1);
    }

    @GetMapping
    @PreAuthorize(JupebOfficeController.READ)
    @Transactional(readOnly = true)
    Map<String, Object> plan(@RequestParam(required = false) String from, @RequestParam(required = false) String to) {
        String f = from == null || from.isBlank() ? jdbc.sql("SELECT jupeb.current_session()").query(String.class).single() : from.trim();
        if (!f.matches("^\\d{4}/\\d{4}$")) throw new NotFound("session", f);
        String t = to == null || to.isBlank() ? next(f) : to.trim();
        if (!t.matches("^\\d{4}/\\d{4}$")) throw new NotFound("session", t);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("from", f);
        out.put("to", t);
        out.put("items", jdbc.sql("SELECT * FROM jupeb.rollover_plan(:f, :t)").param("f", f).param("t", t).query().listOfRows());
        out.put("windows", jdbc.sql("""
                SELECT w.t AS window_type, w.label, ws.state, ws.opens_at, ws.closes_at
                  FROM (VALUES ('JUPEB_APPLICATION', 'Applications'), ('JUPEB_ADMISSION_STATUS_CHECKING', 'Admission status checking')) w(t, label)
                  CROSS JOIN LATERAL policy.window_state(w.t, :t, NULL) ws
                """).param("t", t).query().listOfRows());
        out.put("onCalendar", jdbc.sql("SELECT EXISTS (SELECT 1 FROM policy.academic_session WHERE name = :t)").param("t", t).query(Boolean.class).single());
        out.put("history", jdbc.sql("""
                SELECT r.from_session, r.to_session, r.item, r.carried, r.skipped, r.note, r.at, r.office, p.surname || ', ' || p.given_names AS actor_name
                  FROM jupeb.session_rollover r LEFT JOIN iam.person p ON p.id = r.actor
                 WHERE r.to_session = :t ORDER BY r.at DESC
                """).param("t", t).query().listOfRows());
        return out;
    }

    public record CarryIn(@NotBlank @Pattern(regexp = "^\\d{4}/\\d{4}$") String from, @NotBlank @Pattern(regexp = "^\\d{4}/\\d{4}$") String to) {
    }

    /** one item carried into the next session — the fees refused here: they are the Bursary's */
    @PostMapping("/{item}")
    @PreAuthorize(JupebOfficeController.WRITE)
    @Transactional
    Map<String, Object> carry(@PathVariable String item, @Valid @RequestBody CarryIn b) {
        String it = item.trim().toUpperCase().replace('-', '_');
        if (!List.of("SETTINGS", "CLASSES", "CALENDAR", "TIMETABLE", "CA_PARTS", "ATTENDANCE_POLICY", "LECTURERS", "FEES").contains(it)) throw new NotFound("rollover item", item);
        var ctx = AuditContextHolder.required();
        String result = jdbc.sql("SELECT jupeb.rollover_carry(:f, :t, :i, :by, :o)::text").param("f", b.from()).param("t", b.to()).param("i", it)
                .param("by", ctx.actorId()).param("o", ctx.actorOffice(), java.sql.Types.VARCHAR).query(String.class).single();
        Map<String, Object> out = new LinkedHashMap<>(plan(b.from(), b.to()));
        out.put("result", JupebView.readJson(result));
        return out;
    }
}
