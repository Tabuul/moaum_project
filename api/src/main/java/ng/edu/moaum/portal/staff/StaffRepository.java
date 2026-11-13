package ng.edu.moaum.portal.staff;

import ng.edu.moaum.portal.shared.FileObjects;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;

/** {@code iam.person} and {@code iam.office_assignment} for one actor; {@code ref.college} and what hangs under it. */
@Repository
class StaffRepository {

    private final FileObjects files;
    private final JdbcClient jdbc;

    StaffRepository(FileObjects files, JdbcClient jdbc) {
        this.jdbc = jdbc;
        this.files = files;
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

    /** The acting person's own profile as one JSON object, camel-cased for the portal, or empty when they have none yet. V749: the
     *  e-mail is the one on record (iam.person), the address the University writes to and the one a save writes into the profile —
     *  the profile's own copy can lag behind an office's correction */
    Optional<String> profileJson(UUID actor) {
        return jdbc.sql("""
                SELECT jsonb_build_object(
                    'email', (SELECT pe.email FROM iam.person pe WHERE pe.id = sp.person_id), 'phone', sp.phone, 'department', sp.department,
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

    /** Upsert the acting person's profile from one JSON object; the function takes the person from the audit context. V749: the
     *  e-mail is never the caller's. The address on record (iam.person, of the person in the audit context) is written in its place,
     *  trimmed, or none where it is not one the profile can hold (ck_sp_email) — so a page opened before the address changed (verified
     *  at My identity, or corrected by an office) saves the rest. Where the record has no address at all, the profile keeps its own —
     *  one it can hold that no other record holds — rather than losing it (Human Resources' reach falls back on it), and V425's copy
     *  puts it on the record, as V749 put such an address there once; an office that clears the record clears the profile too
     *  (iam.set_person_contact), so this never brings back what an office took off. The record is locked as it is read: the
     *  profile's contact is copied back to it (hrm.staff_profile_contact, V425), and a code verified or an office's correction in the
     *  same instant waits for this save rather than being overwritten by the address read before it (only the record is locked here,
     *  never an address, so the address-then-record order of those doors stands) */
    void saveProfile(String profileJson) {
        jdbc.sql("""
                WITH me AS (SELECT pe.id, pe.email FROM iam.person pe WHERE pe.id = nullif(current_setting('moaum.actor_id', true), '')::uuid FOR UPDATE)
                SELECT hrm.save_my_staff_profile(CAST(:j AS jsonb) || jsonb_build_object('email',
                           (SELECT CASE WHEN btrim(m.email) ~ '^[^@[:space:]]+@[^@[:space:]]+\\.[^@[:space:]]+$' THEN btrim(m.email)
                                        WHEN nullif(btrim(coalesce(m.email, '')), '') IS NULL THEN
                                            (SELECT btrim(sp.email) FROM hrm.staff_profile sp
                                              WHERE sp.person_id = m.id AND btrim(sp.email) ~ '^[^@[:space:]]+@[^@[:space:]]+\\.[^@[:space:]]+$'
                                                AND NOT EXISTS (SELECT 1 FROM iam.person o WHERE o.id <> m.id AND lower(btrim(o.email)) = lower(btrim(sp.email))))
                                   END FROM me m)))
                """).param("j", profileJson).query().singleRow();
    }

    /** V749: the acting person's e-mail on record, or none */
    Optional<String> recordEmail(UUID actor) {
        return jdbc.sql("SELECT email FROM iam.person WHERE id = :id AND email IS NOT NULL").param("id", actor).query(String.class).optional();
    }

    /** V749: the bytes from the row or, where the photograph is in the file store (object_id), from the store — the row's own bytes
     *  alone answered nothing for a photograph kept there */
    Optional<StaffMe.Photo> photo(UUID actor) {
        return jdbc.sql("SELECT content_type, content, object_id FROM hrm.staff_photo WHERE person_id = :id")
                .param("id", actor)
                .query().listOfRows().stream().findFirst()
                .map(r -> {
                    byte[] b = files.resolve((byte[]) r.get("content"), (UUID) r.get("object_id"));
                    return new StaffMe.Photo(String.valueOf(r.get("content_type")), b == null ? null : java.util.Base64.getEncoder().encodeToString(b));
                });
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
