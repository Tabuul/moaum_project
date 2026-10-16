package ng.edu.moaum.portal.registration;

import java.sql.Types;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;

import jakarta.validation.Valid;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

import ng.edu.moaum.portal.shared.DomainRuleViolation;
import ng.edu.moaum.portal.shared.FigureCache;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * V505: who cannot have the examination card, and why — every approved registration of a session (and semester) whose card the
 * card's own rule refuses (registration.exam_cards_withheld: not in study, no course, the Bursary's clearance refused, not
 * released), by faculty and department, for Exams & Records, the Bursary and the Registry, with a reminder to those students.
 * The list asks the Bursary's clearance of each student (some 12 s for a session on the live-shaped copy), so it is kept a few
 * minutes (shared.FigureCache) with the time it was worked out, and worked out again on Refresh.
 */
@RestController
@RequestMapping("/api/v1/registration/exam-cards/withheld")
class ExamCardsWithheldController {

    static final String READERS = "hasAnyAuthority('OFFICE_records','OFFICE_bursar','OFFICE_registrar','OFFICE_dregistrar','OFFICE_academic','OFFICE_ict','OFFICE_admin','OFFICE_super')";
    static final String REMINDERS = "hasAnyAuthority('OFFICE_records','OFFICE_bursar','OFFICE_registrar','OFFICE_dregistrar','OFFICE_academic','OFFICE_super')";
    static final Set<String> CODES = Set.of("EXAM_CARD_NOT_CLEARED", "EXAM_CARD_NOT_RELEASED", "EXAM_CARD_NO_COURSES", "EXAM_CARD_NOT_IN_STUDY");

    private final JdbcClient jdbc;
    private final FigureCache figures;

    ExamCardsWithheldController(JdbcClient jdbc, FigureCache figures) {
        this.jdbc = jdbc;
        this.figures = figures;
    }

    private static String session(String s) {
        if (s == null || !s.trim().matches("\\d{4}/\\d{4}")) {
            throw new DomainRuleViolation("EXAM_CARDS_SESSION", "A session is named YYYY/YYYY.", new DomainRuleViolation.Remedy("Choose the session.", "Exams & Records"));
        }
        return s.trim();
    }

    private static Integer semester(Integer m) {
        if (m != null && (m < 1 || m > 3)) {
            throw new DomainRuleViolation("EXAM_CARDS_SEMESTER", "A semester is 1, 2 or 3.", new DomainRuleViolation.Remedy("Choose the semester, or every semester.", "Exams & Records"));
        }
        return m;
    }

    private List<Map<String, Object>> compute(String session, Integer semester) {
        return jdbc.sql("SELECT * FROM registration.exam_cards_withheld(:s, :m) ORDER BY faculty_code, dept_code, programme, level, full_name")
                .param("s", session).param("m", semester, Types.INTEGER).query().listOfRows();
    }

    /** the withheld cards of a session (and semester), filtered and a page at a time, with the counts by reason and the time the
     *  list was worked out */
    @GetMapping
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> list(@RequestParam(required = false) String session, @RequestParam(required = false) Integer semester, @RequestParam(required = false) String code,
                             @RequestParam(required = false) String faculty, @RequestParam(required = false) String dept, @RequestParam(required = false) String q,
                             @RequestParam(defaultValue = "0") int page, @RequestParam(defaultValue = "50") int size, @RequestParam(defaultValue = "false") boolean refresh) {
        String current = jdbc.sql("SELECT policy.university_current_session()").query(String.class).optional().orElse(null);
        String s = session == null || session.isBlank() ? current : session(session);
        if (s == null) throw new DomainRuleViolation("EXAM_CARDS_SESSION", "No session is current; choose one.");
        Integer m = semester(semester);
        FigureCache.Answer<List<Map<String, Object>>> a = figures.get(List.of("exam-cards-withheld", s, m == null ? 0 : m), refresh, () -> compute(s, m));
        String c = code == null || code.isBlank() ? null : code.trim().toUpperCase(Locale.ROOT);
        String f = faculty == null || faculty.isBlank() ? null : faculty.trim().toUpperCase(Locale.ROOT);
        String d = dept == null || dept.isBlank() ? null : dept.trim().toUpperCase(Locale.ROOT);
        String t = q == null || q.isBlank() ? null : q.trim().toUpperCase(Locale.ROOT);
        Map<String, Long> counts = new LinkedHashMap<>();
        for (String k : List.of("EXAM_CARD_NOT_CLEARED", "EXAM_CARD_NOT_RELEASED", "EXAM_CARD_NO_COURSES", "EXAM_CARD_NOT_IN_STUDY")) counts.put(k, 0L);
        List<Map<String, Object>> rows = new ArrayList<>();
        for (Map<String, Object> r : a.value()) {
            if (f != null && !f.equals(String.valueOf(r.get("faculty_code")).toUpperCase(Locale.ROOT))) continue;
            if (d != null && !d.equals(String.valueOf(r.get("dept_code")).toUpperCase(Locale.ROOT))) continue;
            if (t != null && !String.valueOf(r.get("full_name")).toUpperCase(Locale.ROOT).contains(t)
                    && !String.valueOf(r.get("matric_no")).toUpperCase(Locale.ROOT).contains(t)) continue;
            counts.merge(String.valueOf(r.get("code")), 1L, Long::sum);
            if (c == null || c.equals(r.get("code"))) rows.add(r);
        }
        int sz = Math.max(1, Math.min(size, 5000)), pg = Math.max(0, page);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("session", s);
        out.put("semester", m);
        out.put("current", current);
        out.put("sessions", jdbc.sql("SELECT name FROM policy.academic_session ORDER BY name DESC LIMIT 12").query(String.class).list());
        out.put("counts", counts);
        out.put("total", rows.size());
        out.put("page", pg);
        out.put("size", sz);
        out.put("rows", rows.subList(Math.min(rows.size(), pg * sz), Math.min(rows.size(), (pg + 1) * sz)));
        out.put("computedAt", a.at());
        out.put("refreshing", a.refreshing());
        return out;
    }

    public record RemindIn(@NotBlank @Size(max = 9) String session, @Min(1) @Max(3) Integer semester, @Size(max = 40) String code) {
    }

    /** the students whose cards are withheld (of one reason, or all), told why on the notification engine, once a day at most */
    @PostMapping("/remind")
    @PreAuthorize(REMINDERS)
    @Transactional
    Map<String, Object> remind(@Valid @RequestBody RemindIn body) {
        String c = body.code() == null || body.code().isBlank() ? null : body.code().trim().toUpperCase(Locale.ROOT);
        if (c != null && !CODES.contains(c)) {
            throw new DomainRuleViolation("EXAM_CARDS_CODE", "That is not a reason a card is withheld.", new DomainRuleViolation.Remedy("Choose a reason from the list, or all.", "Exams & Records"));
        }
        int told = jdbc.sql("SELECT registration.remind_exam_cards_withheld(:s, :m, :c)").param("s", session(body.session())).param("m", semester(body.semester()), Types.INTEGER)
                .param("c", c, Types.VARCHAR).query(Integer.class).single();
        return Map.of("told", told);
    }
}
