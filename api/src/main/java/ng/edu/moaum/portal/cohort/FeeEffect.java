package ng.edu.moaum.portal.cohort;

import java.math.BigDecimal;
import java.sql.Types;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import org.springframework.jdbc.core.simple.JdbcClient;

/**
 * V576: what a level change does to the students' fees for the current session, before it is made — the levels raised in a
 * sub-transaction that is always undone (finance.level_fee_effect), the session's charges read before and after: the totals, how
 * many owe more, less or the same, and how many would have no fee line at all. Read by Level corrections and Reconciliation.
 */
final class FeeEffect {

    private FeeEffect() {
    }

    static Map<String, Object> of(JdbcClient jdbc, List<UUID> students, List<Integer> levels) {
        String session = jdbc.sql("SELECT policy.university_current_session()").query(String.class).optional()
                .orElseGet(ng.edu.moaum.portal.shared.Sessions::byDate);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("session", session);
        out.put("basis", jdbc.sql("SELECT finance.spill_basis()").query(String.class).single());
        BigDecimal now = BigDecimal.ZERO, after = BigDecimal.ZERO;
        int more = 0, less = 0, same = 0, noneAfter = 0;
        List<Map<String, Object>> changed = new ArrayList<>();
        if (!students.isEmpty()) {
            List<Map<String, Object>> rows = jdbc.sql("""
                    SELECT e.student_id, e.current_level, e.new_level, e.charged_now, e.charged_after,
                           upper(btrim(s.surname)) || coalesce(', ' || nullif(btrim(s.other_names), ''), '') AS name, coalesce(s.matric_no, s.admission_no) AS number
                      FROM finance.level_fee_effect(:s, CAST(:ids AS uuid[]), CAST(:lv AS integer[])) e
                      JOIN people.student s ON s.id = e.student_id
                     ORDER BY abs(e.charged_after - e.charged_now) DESC, name
                    """).param("s", session)
                    .param("ids", students.stream().map(UUID::toString).toArray(String[]::new), Types.ARRAY)
                    .param("lv", levels.toArray(Integer[]::new), Types.ARRAY)
                    .query().listOfRows();
            for (Map<String, Object> r : rows) {
                BigDecimal a = (BigDecimal) r.get("charged_now"), b = (BigDecimal) r.get("charged_after");
                now = now.add(a);
                after = after.add(b);
                int c = b.compareTo(a);
                if (c > 0) more++;
                else if (c < 0) less++;
                else same++;
                if (b.signum() == 0) noneAfter++;
                if (c != 0 && changed.size() < 50) changed.add(r);
            }
        }
        out.put("students", students.size());
        out.put("chargedNow", now);
        out.put("chargedAfter", after);
        out.put("more", more);
        out.put("less", less);
        out.put("same", same);
        out.put("noneAfter", noneAfter);
        out.put("largest", changed);
        return out;
    }
}
