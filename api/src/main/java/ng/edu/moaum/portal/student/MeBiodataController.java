package ng.edu.moaum.portal.student;

import java.util.UUID;

import jakarta.validation.Valid;

import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;

/**
 * A student's own biodata, under /api/v1/me/biodata. It is the same record and
 * the same tier rules the Registry works (StudentService), but keyed on the
 * signed-in student rather than a path id: a student reads and edits their own,
 * and no other. An open field is written straight away; a field that changes
 * only on evidence raises a request the Registry decides; a JAMB field refuses.
 */
@RestController
class MeBiodataController {

    private final StudentService students;

    MeBiodataController(StudentService students) {
        this.students = students;
    }

    private static UUID me(Authentication auth) {
        return UUID.fromString(auth.getName());
    }

    @GetMapping("/api/v1/me/biodata")
    @PreAuthorize("hasAuthority('OFFICE_student')")
    StudentRecord mine(Authentication auth) {
        return students.record(me(auth), null);
    }

    @PutMapping("/api/v1/me/biodata/{field}")
    @PreAuthorize("hasAuthority('OFFICE_student')")
    StudentService.BiodataWritten write(Authentication auth, @PathVariable String field, @Valid @RequestBody StudentService.BiodataIn body) {
        return students.writeBiodata(me(auth), field, body);
    }
}
