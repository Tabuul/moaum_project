package ng.edu.moaum.portal.admissions;

import java.util.List;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotEmpty;

/** A further chunk of a list already opened: a large download arrives in several requests, and the batch is one. */
public record CapsRowsIn(@NotEmpty List<@Valid CapsRowIn> rows) {
}
