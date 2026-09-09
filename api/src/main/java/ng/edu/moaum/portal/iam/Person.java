package ng.edu.moaum.portal.iam;

import java.time.LocalDate;
import java.util.UUID;

/** A row of {@code iam.person}. Ended, never deleted (D11). */
public record Person(UUID id, String staffNumber, String surname, String givenNames, String email, String phone, LocalDate endedOn, String endedReason) {
}
