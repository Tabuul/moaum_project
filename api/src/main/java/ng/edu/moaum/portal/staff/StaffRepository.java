package ng.edu.moaum.portal.staff;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;

/** {@code iam.person} and {@code iam.office_assignment} for one actor; {@code ref.college} and what hangs under it. */
@Repository
class StaffRepository {

    private final JdbcClient jdbc;

    StaffRepository(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    Optional<StaffMe.Person> person(UUID actor) {
        return jdbc.sql("SELECT staff_number, surname, given_names FROM iam.person WHERE id = :id")
                .param("id", actor)
                .query(StaffMe.Person.class)
                .optional();
    }

    List<StaffMe.OfficeHeld> offices(UUID actor) {
        return jdbc.sql("""
                SELECT a.office_code, o.label AS office, a.scope_kind, a.scope_id,
                       a.instrument, a.valid_from, a.valid_to
                  FROM iam.office_assignment a
                  JOIN ref.office o ON o.code = a.office_code
                 WHERE a.person_id = :id
                 ORDER BY a.valid_from DESC, a.office_code
                """)
                .param("id", actor)
                .query(StaffMe.OfficeHeld.class)
                .list();
    }

    /** The acting person's own profile as one JSON object, camel-cased for the portal, or empty when they have none yet. */
    Optional<String> profileJson(UUID actor) {
        return jdbc.sql("""
                SELECT jsonb_build_object(
                    'email', sp.email, 'phone', sp.phone, 'department', sp.department,
                    'faculty', sp.faculty, 'responsibility', sp.responsibility,
                    'scholarUrl', sp.scholar_url, 'orcid', sp.orcid,
                    'researchInterests', sp.research_interests,
                    'mastersGraduated', sp.masters_graduated, 'phdGraduated', sp.phd_graduated,
                    'publications', sp.publications, 'grants', sp.grants,
                    'collaborations', sp.collaborations, 'conferences', sp.conferences,
                    'assignments', sp.assignments, 'innovations', sp.innovations,
                    'patents', sp.patents, 'achievements', sp.achievements,
                    'contributions', sp.contributions,
                    'updatedAt', sp.updated_at,
                    'photo', EXISTS(SELECT 1 FROM hrm.staff_photo ph WHERE ph.person_id = sp.person_id)
                )::text
                  FROM hrm.staff_profile sp
                 WHERE sp.person_id = :id
                """)
                .param("id", actor)
                .query(String.class)
                .optional();
    }

    /** Upsert the acting person's profile from one JSON object; the function takes the person from the audit context. */
    void saveProfile(String profileJson) {
        jdbc.sql("SELECT hrm.save_my_staff_profile(:j::jsonb)").param("j", profileJson).query().singleRow();
    }

    Optional<StaffMe.Photo> photo(UUID actor) {
        return jdbc.sql("SELECT content_type, encode(content, 'base64') AS data_base64 FROM hrm.staff_photo WHERE person_id = :id")
                .param("id", actor)
                .query(StaffMe.Photo.class)
                .optional();
    }

    void savePhoto(String contentType, long bytes, byte[] content) {
        jdbc.sql("SELECT hrm.set_my_staff_photo(:ct, :b, :c)")
                .param("ct", contentType).param("b", bytes).param("c", content)
                .query().singleRow();
    }

    Optional<College.Row> college(String code) {
        return jdbc.sql("SELECT code, name, system, url FROM ref.college WHERE code = :code")
                .param("code", code)
                .query(College.Row.class)
                .optional();
    }

    List<College.Faculty> faculties(String college) {
        return jdbc.sql("""
                SELECT f.code, f.name,
                       (SELECT count(*) FROM people.student s
                          JOIN ref.programme p ON p.code = s.programme_code
                         WHERE p.faculty_code = f.code) AS students
                  FROM ref.faculty f
                 WHERE f.college_code = :college
                 ORDER BY f.name
                """)
                .param("college", college)
                .query(College.Faculty.class)
                .list();
    }

    long students(String college) {
        return jdbc.sql("""
                SELECT count(*) FROM people.student s
                  JOIN ref.programme p ON p.code = s.programme_code
                  JOIN ref.faculty f ON f.code = p.faculty_code
                 WHERE f.college_code = :college
                """)
                .param("college", college)
                .query(Long.class)
                .single();
    }

    List<College.LevelCount> byLevel(String college) {
        return jdbc.sql("""
                SELECT s.current_level AS level, count(*) AS students
                  FROM people.student s
                  JOIN ref.programme p ON p.code = s.programme_code
                  JOIN ref.faculty f ON f.code = p.faculty_code
                 WHERE f.college_code = :college
                 GROUP BY s.current_level
                 ORDER BY s.current_level
                """)
                .param("college", college)
                .query(College.LevelCount.class)
                .list();
    }
}
