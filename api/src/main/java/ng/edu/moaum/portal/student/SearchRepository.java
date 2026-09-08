package ng.edu.moaum.portal.student;

import java.util.List;
import java.util.UUID;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;

/**
 * Search finds one record. Four corpora are searched — the register, the
 * staff of {@code iam.person} who hold a staff number, the catalogue, and
 * the credentials that have been issued — and every search for a person is
 * written to {@code people.search_log}, because looking somebody up is
 * processing their personal data whether or not anything changes.
 */
@Repository
class SearchRepository {

    private final JdbcClient jdbc;

    SearchRepository(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    List<SearchHit> students(String like) {
        return jdbc.sql("""
                SELECT 'students' AS kind,
                       coalesce(s.matric_no, s.admission_no, '—') AS identifier,
                       s.surname || ', ' || s.other_names AS name,
                       p.name || ' · ' || s.current_level || ' Level' AS detail,
                       s.status, s.id::text AS id
                  FROM people.student s
                  JOIN ref.programme p ON p.code = s.programme_code
                 WHERE s.matric_no ILIKE :like OR s.admission_no ILIKE :like
                    OR s.surname ILIKE :like OR s.other_names ILIKE :like
                    OR (s.surname || ' ' || s.other_names) ILIKE :like
                    OR s.jamb_reg_no ILIKE :like
                 ORDER BY s.surname, s.other_names
                 LIMIT 200
                """).param("like", like).query(SearchHit.class).list();
    }

    List<SearchHit> staff(String like) {
        return jdbc.sql("""
                SELECT 'staff' AS kind, r.staff_number AS identifier,
                       r.surname || ', ' || r.given_names AS name,
                       coalesce((SELECT string_agg(DISTINCT o.label, ' · ')
                                   FROM iam.office_assignment a
                                   JOIN ref.office o ON o.code = a.office_code
                                  WHERE a.person_id = r.id
                                    AND (a.valid_to IS NULL OR a.valid_to >= current_date)), 'Staff') AS detail,
                       CASE WHEN r.ended_on IS NULL THEN 'Staff' ELSE 'Ended' END AS status,
                       r.id::text AS id
                  FROM iam.person r
                 WHERE r.staff_number IS NOT NULL
                   AND (r.staff_number ILIKE :like OR r.surname ILIKE :like OR r.given_names ILIKE :like
                        OR (r.surname || ' ' || r.given_names) ILIKE :like)
                 ORDER BY r.surname, r.given_names
                 LIMIT 200
                """).param("like", like).query(SearchHit.class).list();
    }

    List<SearchHit> courses(String like) {
        return jdbc.sql("""
                SELECT 'courses' AS kind, c.code AS identifier, c.title AS name,
                       c.units || ' units · ' || d.name AS detail,
                       initcap(lower(c.state)) AS status, c.code AS id
                  FROM catalogue.course c
                  JOIN ref.department d ON d.code = c.dept_code
                 WHERE c.code ILIKE :like OR c.title ILIKE :like
                 ORDER BY c.code
                 LIMIT 200
                """).param("like", like).query(SearchHit.class).list();
    }

    List<SearchHit> credentials(String like) {
        return jdbc.sql("""
                SELECT 'credentials' AS kind, i.verification_code AS identifier,
                       coalesce(s.surname || ', ' || s.other_names, 'Holder not on the register') AS name,
                       initcap(lower(replace(i.kind, '_', ' '))) || ' · issued ' || to_char(i.issued_on, 'DD Mon YYYY') AS detail,
                       'Valid' AS status, i.verification_code AS id
                  FROM credentials.issued i
                  LEFT JOIN people.student s ON s.id = i.student_id
                 WHERE i.verification_code ILIKE :like
                    OR s.surname ILIKE :like OR s.other_names ILIKE :like
                 ORDER BY i.issued_on DESC
                 LIMIT 200
                """).param("like", like).query(SearchHit.class).list();
    }

    /** Every search, with what was asked, what kind and how many it found. */
    void log(String term, String kind, int hits) {
        jdbc.sql("""
                INSERT INTO people.search_log (id, term, kind, hits) VALUES (:id, :term, :kind, :hits)
                """).param("id", UUID.randomUUID()).param("term", term).param("kind", kind).param("hits", hits)
                .update();
    }
}
