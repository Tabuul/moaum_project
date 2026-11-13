package ng.edu.moaum.portal.iam;

import java.sql.Types;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;

@Repository
class PersonRepository {

    private final JdbcClient jdbc;

    PersonRepository(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    Optional<Person> find(UUID id) {
        return jdbc.sql("SELECT id, staff_number, surname, given_names, email, phone, ended_on, ended_reason FROM iam.person WHERE id = :id")
                .param("id", id)
                .query(Person.class)
                .optional();
    }

    void insert(Person person) {
        jdbc.sql("INSERT INTO iam.person (id, staff_number, surname, given_names, email, phone) VALUES (:id, :staff, :surname, :given, :email, :phone)")
                .param("id", person.id())
                .param("staff", person.staffNumber(), Types.VARCHAR)
                .param("surname", person.surname())
                .param("given", person.givenNames())
                .param("email", person.email(), Types.VARCHAR)
                .param("phone", person.phone(), Types.VARCHAR)
                .update();
    }

    /** an office corrects a person's e-mail and phone (blank clears); V749: never to an address another person holds verified
     *  (IDENTITY_EMAIL_TAKEN, iam.set_person_contact), and the staff profile's copy follows, so the profile never brings back what
     *  the office corrected or cleared */
    void setContact(UUID id, String email, String phone) {
        jdbc.sql("SELECT iam.set_person_contact(:id, :email, :phone)")
                .param("id", id).param("email", email, Types.VARCHAR).param("phone", phone, Types.VARCHAR).query().singleRow();
    }

    /** V749: the signed-in person's own phone; the e-mail only as it stands on record or blank — a new address is refused
     *  (STAFF_EMAIL_VERIFY, iam.set_my_contact) and is verified by a code at My identity */
    void setMyContact(String email, String phone) {
        jdbc.sql("SELECT iam.set_my_contact(:email, :phone)")
                .param("email", email, Types.VARCHAR).param("phone", phone, Types.VARCHAR).query().singleRow();
    }

    /** one grant as the record holds it — the scope as the register's code once the trigger has resolved it (V316/V325) */
    java.util.Optional<OfficeAssignment> assignment(UUID id) {
        return jdbc.sql("""
                SELECT id, person_id, office_code, scope_kind, scope_id, instrument, granted_by, valid_from, valid_to
                  FROM iam.office_assignment WHERE id = :id
                """)
                .param("id", id)
                .query(OfficeAssignment.class)
                .optional();
    }

    List<OfficeAssignment> assignments(UUID personId) {
        return jdbc.sql("""
                SELECT id, person_id, office_code, scope_kind, scope_id, instrument, granted_by, valid_from, valid_to
                  FROM iam.office_assignment WHERE person_id = :person ORDER BY valid_from, office_code
                """)
                .param("person", personId)
                .query(OfficeAssignment.class)
                .list();
    }

    void insert(OfficeAssignment grant) {
        jdbc.sql("""
                INSERT INTO iam.office_assignment
                       (id, person_id, office_code, scope_kind, scope_id, instrument, granted_by, valid_from, valid_to)
                VALUES (:id, :person, :office, :scopeKind, :scopeId, :instrument, :grantedBy, :from, :to)
                """)
                .param("id", grant.id())
                .param("person", grant.personId())
                .param("office", grant.officeCode())
                .param("scopeKind", grant.scopeKind())
                .param("scopeId", grant.scopeId(), Types.VARCHAR)
                .param("instrument", grant.instrument())
                .param("grantedBy", grant.grantedBy())
                .param("from", grant.validFrom())
                .param("to", grant.validTo(), Types.DATE)
                .update();
    }

    boolean officeExists(String code) {
        return jdbc.sql("SELECT count(*) FROM ref.office WHERE code = :code")
                .param("code", code)
                .query(Long.class)
                .single() > 0;
    }
}
