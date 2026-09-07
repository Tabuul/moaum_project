package ng.edu.moaum.portal.admissions;

import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.util.UUID;

/** One upload of a CAPS list ({@code admissions.caps_batch}), declared before it was read. */
public record CapsBatch(UUID id, String session, String source, String filename, String fileSha256, int rowsRead,
                        String listKind, LocalDate downloadedOn, OffsetDateTime uploadedAt, UUID uploadedBy,
                        String uploadedOffice, OffsetDateTime committedAt) {
}
