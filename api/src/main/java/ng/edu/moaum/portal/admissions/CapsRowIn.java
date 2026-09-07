package ng.edu.moaum.portal.admissions;

import java.util.Map;

import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;

/**
 * One row of a CAPS list as the office read it. {@code raw} is the row
 * exactly as it came out of the spreadsheet — every column, untouched — so
 * that what JAMB sent can always be shown beside what was made of it.
 */
public record CapsRowIn(@NotBlank @Pattern(regexp = "\\d{12}[A-Za-z]{2,3}") String jambRegNo,
                        @NotBlank String surname,
                        String otherNames,
                        @NotBlank @Pattern(regexp = "C\\d{5}") String jambCode,
                        @Min(1) @Max(400) Integer aggregate,
                        String sex,
                        String stateOfOrigin,
                        String lga,
                        @NotBlank @Pattern(regexp = "UTME|DIRECT_ENTRY|TRANSFER") String entryMode,
                        Map<String, Object> raw) {
}
