package ng.edu.moaum.portal.allocation;

import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

import ng.edu.moaum.portal.shared.DomainRuleViolation;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Component;

/**
 * What every allocation desk reads before and after an act (V408): the checks of catalogue.allocation_checks — whether a
 * person may take a class, each said — and the class's history on catalogue.allocation_event. The department's desk and the
 * ICT desk read the same, so a Head of Department and the Director of ICT are told the same thing in the same words.
 */
@Component
class AllocationRecord {

    /** the checks no desk may override: the course and class as they stand, the session, the person active and teaching */
    private static final Set<String> FIRM = Set.of("COURSE", "OFFERED", "SESSION", "LECTURER", "ACTIVE", "TEACHING");

    private final JdbcClient jdbc;

    AllocationRecord(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    /** each check with OK, WARNING or ERROR and its words; ok when none is an ERROR; overload when the lead's load passes 12 */
    Map<String, Object> checks(UUID offering, UUID person, String role) {
        String rl = "CO_LECTURER".equalsIgnoreCase(role) ? "CO_LECTURER" : "LECTURER";
        List<Map<String, Object>> list = jdbc.sql("SELECT code, level, words FROM catalogue.allocation_checks(:o, :p, :r)")
                .param("o", offering).param("p", person).param("r", rl).query().listOfRows();
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("checks", list);
        out.put("ok", list.stream().noneMatch(c -> "ERROR".equals(c.get("level"))));
        out.put("overload", list.stream().anyMatch(c -> "LOAD".equals(c.get("code")) && "WARNING".equals(c.get("level"))));
        return out;
    }

    /** refused, in the check's own words, when the person cannot take the class at all (left the University, holds no lecturer
     *  office, the course ended or not offered) — the same allocation twice and the load are each desk's own to judge */
    void refuseIneligible(UUID offering, UUID person, String role) {
        @SuppressWarnings("unchecked")
        List<Map<String, Object>> list = (List<Map<String, Object>>) checks(offering, person, role).get("checks");
        for (Map<String, Object> c : list) {
            if ("ERROR".equals(c.get("level")) && FIRM.contains(String.valueOf(c.get("code")))) {
                throw new DomainRuleViolation("ALLOC_" + c.get("code"), String.valueOf(c.get("words")),
                        new DomainRuleViolation.Remedy("Choose an active lecturer; nothing was changed.", "You"));
            }
        }
    }

    /** the history, newest first, within a where clause on ev (the event), c (its course) and d (the course's department) */
    List<Map<String, Object>> events(String where, Map<String, Object> params, int limit) {
        var q = jdbc.sql("""
                SELECT ev.id, ev.offering_id, ev.course_code, ev.session, ev.semester, ev.action, ev.role, ev.reason, ev.source, ev.actor_office, ev.at,
                       concat_ws(', ', nullif(btrim(lp.surname), ''), nullif(btrim(lp.given_names), '')) AS lecturer, lp.staff_number AS lecturer_staff_number,
                       concat_ws(', ', nullif(btrim(pp.surname), ''), nullif(btrim(pp.given_names), '')) AS previous_lecturer,
                       concat_ws(', ', nullif(btrim(ap.surname), ''), nullif(btrim(ap.given_names), '')) AS performed_by,
                       tk.number AS ticket, c.dept_code, d.name AS department
                  FROM catalogue.allocation_event ev
                  JOIN catalogue.course c ON c.code = ev.course_code
                  LEFT JOIN ref.department d ON d.code = c.dept_code
                  LEFT JOIN iam.person lp ON lp.id = ev.lecturer_id
                  LEFT JOIN iam.person pp ON pp.id = ev.previous_lecturer_id
                  LEFT JOIN iam.person ap ON ap.id = ev.actor_id
                  LEFT JOIN helpdesk.ticket tk ON tk.id = ev.ticket_id
                """ + where + " ORDER BY ev.at DESC, ev.id LIMIT :lim").param("lim", Math.max(1, Math.min(limit, 5000)));
        for (var e : params.entrySet()) q = q.param(e.getKey(), e.getValue());
        return q.query().listOfRows();
    }

    /** a reason the history and the notices carry, said in a few words */
    static String need(String reason, String what) {
        String r = reason == null ? "" : reason.trim();
        if (r.length() < 5) {
            throw new DomainRuleViolation("ALLOC_REASON", "Give the reason for " + what + ".",
                    new DomainRuleViolation.Remedy("Say why, in a few words: the allocation history carries it.", "You"));
        }
        return r;
    }

    /** the reason the history records for the acts that follow in this transaction */
    void reason(String reason) {
        if (reason != null && !reason.isBlank()) {
            jdbc.sql("SELECT set_config('moaum.reason', :r, true)").param("r", reason.trim()).query().listOfRows();
        }
    }
}
