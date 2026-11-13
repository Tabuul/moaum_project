package ng.edu.moaum.portal.student;

import java.sql.Types;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.UUID;

import jakarta.validation.Valid;
import jakarta.validation.constraints.Size;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.Authentication;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import tools.jackson.databind.ObjectMapper;

/**
 * V749: the student's own blood group, confirmed — the University's brief of 12 November 2026, "UPDATE YOUR BLOOD GROUP INFORMATION":
 * one of A+, A-, B+, B-, AB+, AB-, O+, O-, and "I confirm that the blood group information supplied is accurate." ticked, saved to
 * the record (the biodata) with the time and the confirmation (credentials.confirm_my_blood_group). The identity card reads it from
 * there and waits on it (credentials.id_card_eligibility). Always the signed-in student's own: the student is the token's subject.
 */
@RestController
@RequestMapping("/api/v1/me/blood-group")
@PreAuthorize("hasAuthority('OFFICE_student')")
class MeBloodGroupController {

    public record BloodGroupIn(@Size(max = 20) String bloodGroup, Boolean confirmed) {
    }

    private final JdbcClient jdbc;
    private final ObjectMapper json;

    MeBloodGroupController(JdbcClient jdbc, ObjectMapper json) {
        this.jdbc = jdbc;
        this.json = json;
    }

    private static UUID me(Authentication auth) {
        return UUID.fromString(auth.getName());
    }

    /** the blood group on the record, and whether it is confirmed (by the student, or recorded at the card desk) */
    @GetMapping
    @Transactional(readOnly = true)
    Map<String, Object> mine(Authentication auth) {
        return stateOf(me(auth));
    }

    Map<String, Object> stateOf(UUID student) {
        Map<String, Object> r = jdbc.sql("""
                SELECT credentials.student_blood_group(:s) AS blood_group, credentials.blood_group_confirmed('STUDENT', :s) AS confirmed_group,
                       c.confirmed_at, c.source
                  FROM (SELECT 1) one
                  LEFT JOIN credentials.blood_group_confirmation c ON c.kind = 'STUDENT' AND c.holder_id = :s
                """).param("s", student).query().singleRow();
        boolean confirmed = r.get("confirmed_group") != null;
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("bloodGroup", r.get("blood_group"));
        out.put("confirmed", confirmed);
        out.put("confirmedAt", confirmed ? r.get("confirmed_at") : null);
        out.put("source", confirmed ? r.get("source") : null);
        return out;
    }

    /** the student's blood group saved and confirmed; refused (and nothing saved) for a value that is not one of the eight, or without
     *  the confirmation ticked */
    @PutMapping
    @Transactional
    Map<String, Object> confirm(Authentication auth, @Valid @RequestBody BloodGroupIn in) {
        String j = jdbc.sql("SELECT credentials.confirm_my_blood_group(:g, :c)::text")
                .param("g", in.bloodGroup(), Types.VARCHAR).param("c", in.confirmed(), Types.BOOLEAN).query(String.class).single();
        Map<String, Object> out = new LinkedHashMap<>(json.readValue(j, new tools.jackson.core.type.TypeReference<Map<String, Object>>() { }));
        out.put("confirmed", true);
        return out;
    }
}
