package ng.edu.moaum.portal.student;

import java.util.Map;
import java.util.UUID;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * Student classification (V469): the audit of how every learner is classified, the learners that require
 * classification, and the Academic Office's or the Registry's decision for one of them — or the progression of an
 * earlier JUPEB or Preliminary record onto the register. University-wide offices read the audit; only the Academic
 * Office, the Deputy Registrar, the Registrar and the platform decide, and the database holds the same line.
 */
@RestController
@RequestMapping("/api/v1/student/classification")
class StudentClassificationController {

    static final String READERS = "hasAnyAuthority('OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar','OFFICE_super',"
            + "'OFFICE_ict','OFFICE_vc','OFFICE_dvc','OFFICE_records','OFFICE_admin',"
            // V640: the Database Operations office reads the classification; deciding one stays with the Academic Office and the Registry
            + "'OFFICE_dbops')";
    static final String DECIDERS = "hasAnyAuthority('OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar','OFFICE_super')";

    private final ClassificationService classification;

    StudentClassificationController(ClassificationService classification) {
        this.classification = classification;
    }

    record Decision(@NotBlank @Pattern(regexp = "[A-Za-z_]{2,31}") String programmeType,
                    @Pattern(regexp = "[A-Za-z0-9_]{2,41}") String admissionRoute,
                    @Pattern(regexp = "[A-Za-z0-9_]{2,31}") String centre,
                    @NotBlank @Size(max = 1000) String reason) {
    }

    record Progression(@NotBlank @Pattern(regexp = "(?i)JUPEB|PRELIMINARY") String source,
                       @NotBlank @Size(max = 40) String applicationNo,
                       @NotBlank @Size(max = 1000) String reason) {
    }

    /** the classification audit of every learner: classified, requiring classification, and what is missing */
    @GetMapping("/audit")
    @PreAuthorize(READERS)
    Map<String, Object> audit() {
        return classification.audit();
    }

    /** the learners that require classification, with what their fields propose and why */
    @GetMapping("/review")
    @PreAuthorize(READERS)
    Map<String, Object> review(@RequestParam(required = false) String q, @RequestParam(defaultValue = "0") int page,
                               @RequestParam(defaultValue = "50") int size) {
        return classification.review(q, page, size);
    }

    /** decide one student's programme type (and admission route and centre where known), with the reason */
    @PostMapping("/{studentId}")
    @PreAuthorize(DECIDERS)
    Map<String, Object> decide(@PathVariable UUID studentId, @Valid @RequestBody Decision body) {
        return classification.decide(studentId, body.programmeType().trim().toUpperCase(),
                body.admissionRoute() == null || body.admissionRoute().isBlank() ? null : body.admissionRoute().trim().toUpperCase(),
                body.centre() == null || body.centre().isBlank() ? null : body.centre().trim().toUpperCase(), body.reason().trim());
    }

    /** record that this student came from an earlier JUPEB or Preliminary record, which stays as it was */
    @PostMapping("/{studentId}/progression")
    @PreAuthorize(DECIDERS)
    Map<String, Object> progression(@PathVariable UUID studentId, @Valid @RequestBody Progression body) {
        return classification.progression(studentId, body.source().trim().toUpperCase(), body.applicationNo().trim(), body.reason().trim());
    }
}
