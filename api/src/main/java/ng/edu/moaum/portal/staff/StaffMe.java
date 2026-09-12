package ng.edu.moaum.portal.staff;

import java.time.LocalDate;
import java.util.List;

/**
 * The acting person as the portal knows them: the row of {@code iam.person}
 * their token points at, and every office they hold with the instrument it is
 * held under.
 *
 * <p>{@code person} is null when the token carries an actor with no person row
 * — a development token, or an account created in Keycloak before the Registry
 * recorded the appointment. That is a 200 with an honest empty answer, not a
 * 404: the person is signed in, and the screen says what is missing.
 */
public record StaffMe(Person person, List<OfficeHeld> offices) {

    /** {@code iam.person}, less the columns a person does not need to see about themselves. */
    public record Person(String staffNumber, String surname, String givenNames) {
    }

    /** One row of {@code iam.office_assignment}, with the office's label from {@code ref.office}. */
    public record OfficeHeld(String officeCode, String office, String scopeKind, String scopeId,
                             String instrument, LocalDate validFrom, LocalDate validTo) {
    }

    /** The staff photograph, its bytes base64-encoded so it crosses the JSON API without a binary stream. */
    public record Photo(String contentType, String dataBase64) {
    }
}
