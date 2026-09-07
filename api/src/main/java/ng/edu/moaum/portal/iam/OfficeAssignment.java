package ng.edu.moaum.portal.iam;

import java.time.LocalDate;
import java.util.UUID;

/** A row of {@code iam.office_assignment}: an office held, under an instrument, for a period. */
public record OfficeAssignment(UUID id, UUID personId, String officeCode, String scopeKind, String scopeId,
                               String instrument, UUID grantedBy, LocalDate validFrom, LocalDate validTo) {
}
