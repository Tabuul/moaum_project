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

    void setContact(UUID id, String email, String phone) {
        jdbc.sql("UPDATE iam.person SET email = :email, phone = :phone WHERE id = :id")
                .param("id", id).param("email", email, Types.VARCHAR).param("phone", phone, Types.VARCHAR).update();
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
