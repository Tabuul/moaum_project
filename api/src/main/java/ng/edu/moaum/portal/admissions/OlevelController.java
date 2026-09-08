package ng.edu.moaum.portal.admissions;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import jakarta.validation.Valid;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotNull;

import ng.edu.moaum.portal.shared.AuditContextHolder;
import ng.edu.moaum.portal.shared.DomainRuleViolation;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * The O'Level results JAMB sends and the screening score they carry (V020).
 * The grading is the Academic Office's to state, per session. A candidate's
 * sittings are shown as JAMB sent them; the score is computed under the
 * session's grading and the programme's relevant subjects, and it is the
 * Academic Office's — no other office, and never the applicant, is given it.
 */
@RestController
@RequestMapping("/api/v1/admissions/sessions/{session}/{year}")
class OlevelController {

    private static final String READERS =
            "hasAnyAuthority('OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar','OFFICE_records','OFFICE_ict','OFFICE_admin','OFFICE_super')";
    private static final String SECRETARIAT = "hasAnyAuthority('OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar')";
    static final List<String> GRADES = List.of("A1", "B2", "B3", "C4", "C5", "C6", "D7", "E8", "F9");
    /** the office the score belongs to */
    static final String SCORE_OFFICE = "academic";

    public record Grading(String session, boolean stated, int subjectsCounted, int bonusOneSitting, int bonusTwoSittings,
                          Map<String, Integer> points) {
    }

    public record GradingIn(@Min(1) @Max(9) int subjectsCounted, @Min(0) @Max(100) int bonusOneSitting,
                            @Min(0) @Max(100) int bonusTwoSittings, @NotNull Map<String, Integer> points) {
    }

    public record Grade(String subject, String grade, int points) {
    }

    public record Sitting(String body, String type, String year, String examNumber, List<Grade> subjects) {
    }

    public record Screening(int sittings, boolean relevantKnown, List<Grade> counted, int points, int bonus, int total) {
    }

    /** {@code screening} is null for every office but the Academic Office; {@code screeningIs} says whose it is. */
    public record Olevel(String session, String jambKey, String programme, String programmeCode, List<Sitting> sittings,
                         Screening screening, String screeningIs) {
    }

    private final JdbcClient jdbc;

    OlevelController(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    @GetMapping("/olevel-grading")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Grading grading(@PathVariable String session, @PathVariable String year) {
        return read(session + "/" + year);
    }

    /** The Academic Office states the rule; every number is recorded against it. */
    @PutMapping("/olevel-grading")
    @PreAuthorize(SECRETARIAT)
    @Transactional
    Grading state(@PathVariable String session, @PathVariable String year, @Valid @RequestBody GradingIn in) {
        String s = session + "/" + year;
        for (Map.Entry<String, Integer> e : in.points().entrySet()) {
            if (!GRADES.contains(e.getKey())) {
                throw new DomainRuleViolation("OLEVEL_GRADE_UNKNOWN", "\"" + e.getKey() + "\" is not an O'Level grade.",
                        new DomainRuleViolation.Remedy("The grades are A1, B2, B3, C4, C5, C6, D7, E8 and F9.", "Academic Office"));
            }
            if (e.getValue() == null || e.getValue() < 0 || e.getValue() > 20) {
                throw new DomainRuleViolation("OLEVEL_POINTS_RANGE", "Points for " + e.getKey() + " must be between 0 and 20.",
                        new DomainRuleViolation.Remedy("State the points a grade is worth, 0 to 20.", "Academic Office"));
            }
        }
        jdbc.sql("""
                INSERT INTO admissions.olevel_grading (session, subjects_counted, bonus_one_sitting, bonus_two_sittings, stated_at)
                VALUES (:s, :n, :one, :two, now())
                ON CONFLICT (session) DO UPDATE SET subjects_counted = EXCLUDED.subjects_counted,
                    bonus_one_sitting = EXCLUDED.bonus_one_sitting, bonus_two_sittings = EXCLUDED.bonus_two_sittings, stated_at = now()
                """).param("s", s).param("n", in.subjectsCounted()).param("one", in.bonusOneSitting()).param("two", in.bonusTwoSittings()).update();
        for (String grade : GRADES) {
            int points = in.points().getOrDefault(grade, 0);
            jdbc.sql("""
                    INSERT INTO admissions.olevel_grade_point (session, grade, points) VALUES (:s, :g, :p)
                    ON CONFLICT (session, grade) DO UPDATE SET points = EXCLUDED.points
                    """).param("s", s).param("g", grade).param("p", points).update();
        }
        return read(s);
    }

    /** A candidate's results as JAMB sent them, sitting by sitting, and — for the Academic Office — the score. */
    @GetMapping("/candidate-data/{jambKey}/olevel")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Olevel olevel(@PathVariable String session, @PathVariable String year, @PathVariable String jambKey) {
        String s = session + "/" + year;
        String key = jambKey.trim().toUpperCase();
        List<Sitting> sittings = new ArrayList<>();
        for (Map<String, Object> row : jdbc.sql("""
                SELECT st.id, st.exam_body, st.exam_type_raw, st.exam_year, st.exam_number
                  FROM admissions.olevel_sitting st WHERE st.session = :s AND st.jamb_key = :k
                 ORDER BY st.exam_year NULLS LAST, st.ord
                """).param("s", s).param("k", key).query().listOfRows()) {
            List<Grade> subjects = jdbc.sql("""
                    SELECT g.subject, g.grade, admissions.olevel_points(:s, g.grade) AS points
                      FROM admissions.olevel_grade g WHERE g.sitting_id = :id ORDER BY g.subject
                    """).param("s", s).param("id", row.get("id")).query(Grade.class).list();
            sittings.add(new Sitting(String.valueOf(row.get("exam_body")), (String) row.get("exam_type_raw"),
                    (String) row.get("exam_year"), (String) row.get("exam_number"), subjects));
        }
        Map<String, Object> prog = jdbc.sql("""
                SELECT c.programme AS name, (SELECT p.code FROM ref.programme p WHERE p.name = c.programme ORDER BY p.archived, p.code LIMIT 1) AS code
                  FROM admissions.candidate c WHERE c.session = :s AND c.jamb_key = :k
                """).param("s", s).param("k", key).query().listOfRows().stream().findFirst().orElse(Map.of());
        String programmeName = (String) prog.get("name");
        String programmeCode = (String) prog.get("code");

        String office = AuditContextHolder.current().map(c -> c.actorOffice()).orElse(null);
        Screening screening = null;
        if (SCORE_OFFICE.equals(office)) {
            Map<String, Object> r = jdbc.sql("SELECT * FROM admissions.olevel_score(:s, :k, :p)")
                    .param("s", s).param("k", key).param("p", programmeCode, java.sql.Types.VARCHAR).query().singleRow();
            List<Grade> counted = new ArrayList<>();
            for (Map<String, Object> c : CandidateDataController.Json.list(String.valueOf(r.get("counted")))) {
                counted.add(new Grade(String.valueOf(c.get("subject")), String.valueOf(c.get("grade")), ((Number) c.get("points")).intValue()));
            }
            screening = new Screening(((Number) r.get("sittings")).intValue(), Boolean.TRUE.equals(r.get("relevant_known")), counted,
                    ((Number) r.get("points")).intValue(), ((Number) r.get("bonus")).intValue(), ((Number) r.get("total")).intValue());
        }
        return new Olevel(s, key, programmeName, programmeCode, sittings, screening, "Academic Office");
    }

    private Grading read(String session) {
        Map<String, Object> rule = jdbc.sql("SELECT * FROM admissions.olevel_rule(:s)").param("s", session).query().singleRow();
        Map<String, Integer> points = new LinkedHashMap<>();
        for (String grade : GRADES) {
            points.put(grade, jdbc.sql("SELECT admissions.olevel_points(:s, :g)").param("s", session).param("g", grade).query(Integer.class).single());
        }
        return new Grading(session, Boolean.TRUE.equals(rule.get("stated")), ((Number) rule.get("subjects_counted")).intValue(),
                ((Number) rule.get("bonus_one_sitting")).intValue(), ((Number) rule.get("bonus_two_sittings")).intValue(), points);
    }
}
