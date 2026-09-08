package ng.edu.moaum.portal.graduation;

import java.math.BigDecimal;
import java.sql.Types;
import java.util.List;
import java.util.UUID;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;

@Repository
class GraduationRepository {

    private final JdbcClient jdbc;

    GraduationRepository(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    record Finalist(UUID studentId, String programmeCode, String programmeName, int level) {
    }

    /** every student enrolled in the session at the final level of their programme */
    List<Finalist> finalists(String session) {
        return jdbc.sql("""
                SELECT s.id AS student_id, s.programme_code, p.name AS programme_name, e.level
                  FROM people.enrolment e
                  JOIN people.student s ON s.id = e.student_id
                  JOIN ref.programme p ON p.code = s.programme_code
                 WHERE e.session = :s
                   AND e.level = CASE WHEN p.code = 'C00061' THEN 600
                                      WHEN upper(p.name) LIKE 'LL.B%' OR upper(p.name) LIKE '%PHARMACY%' THEN 500
                                      ELSE 400 END
                 ORDER BY s.surname, s.other_names
                """).param("s", session).query(Finalist.class).list();
    }

    record Standing(BigDecimal cgpa, String ungraded) {
    }

    /** cgpa over every published sheet the student sat, and the first registered course not yet published */
    Standing standing(UUID student) {
        return jdbc.sql("""
                WITH regs AS (
                    SELECT e.offering_id, e.units, o.course_code
                      FROM registration.entry e
                      JOIN registration.course_registration r ON r.id = e.registration_id
                      JOIN catalogue.offering o ON o.id = e.offering_id
                     WHERE r.student_id = :s AND e.status = 'APPROVED' AND r.status IN ('APPROVED','LOCKED')),
                graded AS (
                    SELECT rg.units, l.points
                      FROM regs rg
                      JOIN assessment.score_sheet sh ON sh.offering_id = rg.offering_id AND sh.stage = 'PUBLISHED'
                      JOIN LATERAL assessment.latest_scores(sh.id) l ON l.student_id = :s)
                SELECT CASE WHEN coalesce(sum(units), 0) = 0 THEN NULL
                            ELSE round(sum(coalesce(points, 0) * units) / sum(units), 2) END AS cgpa,
                       (SELECT rg.course_code FROM regs rg
                         WHERE NOT EXISTS (SELECT 1 FROM assessment.score_sheet sh
                                            WHERE sh.offering_id = rg.offering_id AND sh.stage = 'PUBLISHED')
                         ORDER BY rg.course_code LIMIT 1) AS ungraded
                  FROM graded
                """).param("s", student).query(Standing.class).single();
    }

    void upsert(UUID student, String session, BigDecimal cgpa, String award, String unmet) {
        jdbc.sql("""
                INSERT INTO records.graduand (id, student_id, session, cgpa, award, unmet)
                VALUES (gen_random_uuid(), :s, :sess, :cgpa, :award, :unmet)
                ON CONFLICT (student_id, session) DO UPDATE SET
                        cgpa = EXCLUDED.cgpa, award = EXCLUDED.award,
                        unmet = CASE WHEN records.graduand.senate_state = 'APPROVED' THEN records.graduand.unmet ELSE EXCLUDED.unmet END
                """).param("s", student).param("sess", session).param("cgpa", cgpa, Types.NUMERIC).param("award", award)
                .param("unmet", unmet, Types.VARCHAR).update();
    }

    record Graduand(UUID studentId, String number, String surname, String otherNames, String programmeName, BigDecimal cgpa,
                    String unmet, String senateState, String classOfDegree, boolean cleared) {
    }

    List<Graduand> graduands(String session, String fac, String dept, String prog) {
        return jdbc.sql("""
                SELECT g.student_id, coalesce(s.matric_no, s.admission_no) AS number, s.surname, s.other_names,
                       p.name AS programme_name, g.cgpa, g.unmet, g.senate_state,
                       CASE WHEN g.cgpa IS NULL THEN NULL ELSE policy.class_of(g.cgpa) END AS class_of_degree,
                       clearance.is_clear(g.student_id, 'CONVOCATION') AS cleared
                  FROM records.graduand g
                  JOIN people.student s ON s.id = g.student_id
                  JOIN ref.programme p ON p.code = s.programme_code
                 WHERE g.session = :s
                   AND (:fac::text IS NULL OR p.faculty_code = :fac)
                   AND (:dept::text IS NULL OR p.dept_code = :dept)
                   AND (:prog::text IS NULL OR p.code = :prog)
                 ORDER BY s.surname, s.other_names
                """).param("s", session).param("fac", fac).param("dept", dept).param("prog", prog)
                .query(Graduand.class).list();
    }

    record Band(String clazz, BigDecimal low, BigDecimal high, int ord) {
    }

    List<Band> bands() {
        return jdbc.sql("""
                SELECT b.class AS clazz, b.low, b.high, b.ord FROM policy.classification_band b
                 WHERE b.version_id = policy.in_force('classification', 'UNIVERSITY', current_date)
                 ORDER BY b.ord
                """).query(Band.class).list();
    }

    int approve(String session, String minute) {
        int n = jdbc.sql("""
                UPDATE records.graduand SET senate_state = 'APPROVED', senate_minute = :m
                 WHERE session = :s AND senate_state = 'AWAITING' AND unmet IS NULL AND cgpa IS NOT NULL
                """).param("m", minute).param("s", session).update();
        jdbc.sql("""
                SELECT people.change_status(g.student_id, 'GRADUATED', :m, current_date, 'Award approved by Senate')
                  FROM records.graduand g JOIN people.student s ON s.id = g.student_id
                 WHERE g.session = :s AND g.senate_state = 'APPROVED' AND g.senate_minute = :m AND s.status <> 'GRADUATED'
                """).param("m", minute).param("s", session).query().listOfRows();
        return n;
    }
}
