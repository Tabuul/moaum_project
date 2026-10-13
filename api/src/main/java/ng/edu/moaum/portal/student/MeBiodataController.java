package ng.edu.moaum.portal.student;

import java.util.LinkedHashMap;
import java.util.Map;
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
    private final BiodataCompliance compliance;

    MeBiodataController(StudentService students, BiodataCompliance compliance) {
        this.students = students;
        this.compliance = compliance;
    }

    private static UUID me(Authentication auth) {
        return UUID.fromString(auth.getName());
    }

    @GetMapping("/api/v1/me/biodata")
    @PreAuthorize("hasAuthority('OFFICE_student')")
    StudentRecord mine(Authentication auth) {
        return students.record(me(auth), null);
    }

    /**
     * V423: where the student stands with the biodata gate — OFF, EXCEPTION (until when), COMPLETE or REQUIRED — and their
     * completion: the required items, how many are given, the percentage, the missing ones by name, when it last changed.
     */
    @GetMapping("/api/v1/me/biodata/completion")
    @PreAuthorize("hasAuthority('OFFICE_student')")
    Map<String, Object> completion(Authentication auth) {
        UUID id = me(auth);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("gate", compliance.gateState(id));
        out.put("enabled", Boolean.TRUE.equals(compliance.gate().get("enabled")));
        out.put("completion", compliance.completion(id));
        out.put("requiredItems", compliance.requiredItems());
        out.put("exception", compliance.liveException(id));
        return out;
    }

    @PutMapping("/api/v1/me/biodata/{field}")
    @PreAuthorize("hasAuthority('OFFICE_student')")
    StudentService.BiodataWritten write(Authentication auth, @PathVariable String field, @Valid @RequestBody StudentService.BiodataIn body) {
        return students.writeBiodata(me(auth), field, body);
    }
}
