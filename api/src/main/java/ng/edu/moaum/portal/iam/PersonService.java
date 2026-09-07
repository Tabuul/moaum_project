package ng.edu.moaum.portal.iam;

import java.time.LocalDate;
import java.util.List;
import java.util.UUID;

import ng.edu.moaum.portal.shared.AuditContextHolder;
import ng.edu.moaum.portal.shared.DomainRuleViolation;
import ng.edu.moaum.portal.shared.NotFound;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * The application service owns the transaction (ARC §7): one command, one
 * transaction, one aggregate. The audit context rides on the transaction and
 * the database records every row written here against it.
 */
@Service
public class PersonService {

    private final PersonRepository persons;

    PersonService(PersonRepository persons) {
        this.persons = persons;
    }

    @Transactional(readOnly = true)
    public Person get(UUID id) {
        return persons.find(id).orElseThrow(() -> new NotFound("person", id));
    }

    @Transactional(readOnly = true)
    public List<OfficeAssignment> assignments(UUID personId) {
        get(personId);
        return persons.assignments(personId);
    }

    @Transactional
    public Person create(String staffNumber, String surname, String givenNames) {
        Person person = new Person(UUID.randomUUID(), blankToNull(staffNumber), surname.trim(), givenNames.trim(), null, null);
        persons.insert(person);
        return person;
    }

    /**
     * Grants an office. The instrument is required by the schema
     * ({@code ck_grant_instrument}); the grantor is whoever is acting, taken
     * from the audit context rather than from the request body, so a grant
     * can never claim to have been made by somebody else.
     */
    @Transactional
    public OfficeAssignment grant(UUID personId, String officeCode, String scopeKind, String scopeId,
                                  String instrument, LocalDate validFrom, LocalDate validTo) {
        get(personId);
        if (!persons.officeExists(officeCode)) {
            throw new DomainRuleViolation("IAM_NO_SUCH_OFFICE",
                    "'" + officeCode + "' is not one of the offices in ref.office.",
                    new DomainRuleViolation.Remedy("Choose one of the University's offices.", "Directorate of ICT"));
        }
        if (instrument == null || instrument.isBlank()) {
            throw new DomainRuleViolation("IAM_GRANT_NEEDS_INSTRUMENT",
                    "An office is held under a letter or minute; none was given.",
                    new DomainRuleViolation.Remedy("Quote the appointment letter or the minute that made the appointment.", "Registrar"));
        }
        OfficeAssignment grant = new OfficeAssignment(UUID.randomUUID(), personId, officeCode, scopeKind,
                blankToNull(scopeId), instrument.trim(), AuditContextHolder.required().actorId(),
                validFrom == null ? LocalDate.now() : validFrom, validTo);
        persons.insert(grant);
        return grant;
    }

    private static String blankToNull(String s) {
        return s == null || s.isBlank() ? null : s.trim();
    }
}
