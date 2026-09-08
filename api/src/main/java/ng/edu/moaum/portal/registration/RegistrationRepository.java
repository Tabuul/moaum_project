package ng.edu.moaum.portal.registration;

import java.sql.Types;
import java.time.LocalDate;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;

@Repository
class RegistrationRepository {

    private final JdbcClient jdbc;

    RegistrationRepository(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    record RegistrationRow(UUID id, UUID studentId, String session, int semester, int level, String status, String studentStatus) {
    }

    record OfferingRow(UUID id, String courseCode, String courseTitle, int units, String session, int semester,
                       String deptCode, String deptName, UUID lecturerId, String lecturer) {
    }

    void upsertCourse(String code, RegistrationService.CourseIn c, String state) {
        jdbc.sql("""
                INSERT INTO catalogue.course (code, title, units, semester, level, dept_code, kind, state)
                VALUES (:code, :title, :units, :sem, :level, :dept, :kind, :state)
                ON CONFLICT (code) DO UPDATE SET title = EXCLUDED.title, units = EXCLUDED.units, semester = EXCLUDED.semester,
                        level = EXCLUDED.level, dept_code = EXCLUDED.dept_code, kind = EXCLUDED.kind, state = EXCLUDED.state
                """)
                .param("code", code).param("title", c.title().trim()).param("units", c.units()).param("sem", c.semester())
                .param("level", c.level()).param("dept", c.deptCode().trim().toUpperCase()).param("kind", c.kind())
                .param("state", state)
                .update();
    }

    void endCourse(String code, LocalDate endedOn) {
        jdbc.sql("UPDATE catalogue.course SET state = 'ENDED', ended_on = :on WHERE code = :code")
                .param("on", endedOn).param("code", code).update();
    }

    boolean courseExists(String code) {
        return jdbc.sql("SELECT count(*) FROM catalogue.course WHERE code = :c").param("c", code).query(Long.class).single() > 0;
    }

    void upsertOffer(String course, String programme, int level, String basis) {
        jdbc.sql("""
                INSERT INTO catalogue.course_offer (course_code, programme_code, level, basis) VALUES (:c, :p, :l, :b)
                ON CONFLICT (course_code, programme_code, level) DO UPDATE SET basis = EXCLUDED.basis
                """).param("c", course).param("p", programme).param("l", level).param("b", basis).update();
    }

    UUID upsertOffering(RegistrationService.OfferingIn o) {
        return jdbc.sql("""
                INSERT INTO catalogue.offering (id, course_code, session, semester, lecturer_id, second_examiner_id, allocated_on)
                VALUES (gen_random_uuid(), :c, :s, :sem, :l, :e, CASE WHEN :l::uuid IS NULL THEN NULL ELSE current_date END)
                ON CONFLICT (course_code, session, semester) DO UPDATE SET
                        lecturer_id = EXCLUDED.lecturer_id, second_examiner_id = EXCLUDED.second_examiner_id,
                        allocated_on = CASE WHEN EXCLUDED.lecturer_id IS NULL THEN catalogue.offering.allocated_on
                                            ELSE coalesce(catalogue.offering.allocated_on, current_date) END
                RETURNING id
                """)
                .param("c", o.courseCode().trim().toUpperCase()).param("s", o.session()).param("sem", o.semester())
                .param("l", o.lecturerId(), Types.OTHER).param("e", o.secondExaminerId(), Types.OTHER)
                .query(UUID.class).single();
    }

    Optional<OfferingRow> offering(String course, String session, int semester) {
        return jdbc.sql("""
                SELECT o.id, o.course_code, c.title AS course_title, c.units, o.session, o.semester, c.dept_code, d.name AS dept_name,
                       o.lecturer_id, CASE WHEN p.id IS NULL THEN NULL ELSE p.surname || ', ' || p.given_names END AS lecturer
                  FROM catalogue.offering o
                  JOIN catalogue.course c ON c.code = o.course_code
                  JOIN ref.department d ON d.code = c.dept_code
                  LEFT JOIN iam.person p ON p.id = o.lecturer_id
                 WHERE o.course_code = :c AND o.session = :s AND o.semester = :sem
                """).param("c", course).param("s", session).param("sem", semester)
                .query(OfferingRow.class).optional();
    }

    UUID createRegistration(RegistrationService.RegistrationIn r) {
        UUID id = UUID.randomUUID();
        jdbc.sql("""
                INSERT INTO registration.course_registration (id, student_id, session, semester, level, status)
                VALUES (:id, :st, :s, :sem, :l, 'DRAFT')
                """).param("id", id).param("st", r.studentId()).param("s", r.session()).param("sem", r.semester())
                .param("l", r.level()).update();
        for (RegistrationService.EntryIn e : r.entries()) {
            jdbc.sql("""
                    INSERT INTO registration.entry (registration_id, offering_id, units, entry_type)
                    VALUES (:r, :o, :u, :t)
                    """).param("r", id).param("o", e.offeringId()).param("u", e.units())
                    .param("t", e.entryType() == null ? "CURRENT" : e.entryType()).update();
        }
        return id;
    }

    Optional<RegistrationRow> registration(UUID id) {
        return jdbc.sql("""
                SELECT r.id, r.student_id, r.session, r.semester, r.level, r.status, s.status AS student_status
                  FROM registration.course_registration r JOIN people.student s ON s.id = r.student_id
                 WHERE r.id = :id
                """).param("id", id).query(RegistrationRow.class).optional();
    }

    int units(UUID registration) {
        return jdbc.sql("SELECT registration.units_of(:id)").param("id", registration).query(Integer.class).single();
    }

    record Limit(int minUnits, int maxUnits) {
    }

    Optional<Limit> limit(int level) {
        return jdbc.sql("SELECT min_units, max_units FROM policy.level_limit WHERE level = :l").param("l", level)
                .query(Limit.class).optional();
    }

    void setStatus(UUID id, String status, UUID approvedBy) {
        jdbc.sql("""
                UPDATE registration.course_registration
                   SET status = :st,
                       submitted_at = CASE WHEN :st = 'SUBMITTED' THEN now() ELSE submitted_at END,
                       approved_at  = CASE WHEN :st = 'APPROVED' THEN now() ELSE approved_at END,
                       approved_by  = CASE WHEN :st = 'APPROVED' THEN :by ELSE approved_by END
                 WHERE id = :id
                """).param("st", status).param("by", approvedBy, Types.OTHER).param("id", id).update();
        if ("APPROVED".equals(status)) {
            jdbc.sql("UPDATE registration.entry SET status = 'APPROVED' WHERE registration_id = :id AND status = 'REGISTERED'")
                    .param("id", id).update();
        }
    }

    List<ClassList.Row> roll(UUID offeringId) {
        return jdbc.sql("""
                SELECT s.id AS student_id, coalesce(s.matric_no, s.admission_no) AS number, s.surname, s.other_names,
                       s.programme_code, p.name AS programme_name, p.dept_code, r.level,
                       coalesce(cof.basis, 'Borrowed') AS basis,
                       clearance.is_clear(s.id, 'EXAMINATION') AS cleared
                  FROM registration.entry e
                  JOIN registration.course_registration r ON r.id = e.registration_id
                  JOIN people.student s ON s.id = r.student_id
                  JOIN ref.programme p ON p.code = s.programme_code
                  JOIN catalogue.offering o ON o.id = e.offering_id
                  LEFT JOIN catalogue.course_offer cof ON cof.course_code = o.course_code
                                                       AND cof.programme_code = s.programme_code AND cof.level = r.level
                 WHERE e.offering_id = :o AND e.status = 'APPROVED' AND r.status IN ('APPROVED','LOCKED')
                 ORDER BY s.surname, s.other_names
                """).param("o", offeringId).query(ClassList.Row.class).list();
    }
}
