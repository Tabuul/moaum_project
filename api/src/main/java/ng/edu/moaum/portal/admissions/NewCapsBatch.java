package ng.edu.moaum.portal.admissions;

import java.time.LocalDate;
import java.util.List;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotEmpty;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;

/**
 * A CAPS list to load. The list kind is declared here, BEFORE the rows are
 * read, and the database refuses whole any file whose rows contradict it
 * ({@code admissions.assert_row_matches_batch}).
 */
public record NewCapsBatch(@NotBlank @Pattern(regexp = "\\d{4}/\\d{4}") String session,
                           @NotBlank @Pattern(regexp = "CAPS_DOWNLOAD|CAPS_API") String source,
                           String filename,
                           @NotBlank @Pattern(regexp = "[0-9a-fA-F]{64}") String fileSha256,
                           @NotBlank @Pattern(regexp = "UTME|DIRECT_ENTRY") String listKind,
                           @NotNull LocalDate downloadedOn,
                           @NotEmpty List<@Valid CapsRowIn> rows,
                           Integer rowsExpected) {
}
