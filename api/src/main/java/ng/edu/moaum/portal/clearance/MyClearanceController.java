package ng.edu.moaum.portal.clearance;

import java.sql.Types;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

import ng.edu.moaum.portal.shared.DomainRuleViolation;
import ng.edu.moaum.portal.shared.FileObjects;
import ng.edu.moaum.portal.shared.NotFound;

import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.Authentication;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * My Clearance (V415): the student's own clearances — every office's word with its official remark (never an office's
 * internal note), what to do, the documents asked for and uploaded, the alumni details for final clearance, and the
 * certificate once complete. A student reaches only their own: another student's process answers as not found.
 */
@RestController
@RequestMapping("/api/v1/me/clearance")
@PreAuthorize("hasAuthority('OFFICE_student')")
class MyClearanceController {

    private static final Set<String> EMPLOYMENT = Set.of("EMPLOYED", "SELF_EMPLOYED", "SEEKING", "FURTHER_STUDY", "NATIONAL_SERVICE", "OTHER");

    private final ClearanceDesk desk;
    private final JdbcClient jdbc;
    private final FileObjects files;

    MyClearanceController(ClearanceDesk desk, JdbcClient jdbc, FileObjects files) {
        this.desk = desk;
        this.jdbc = jdbc;
        this.files = files;
    }

    private static UUID me(Authentication auth) {
        return UUID.fromString(auth.getName());
    }

    /** the student's own process, or not found */
    private Map<String, Object> mine(UUID id, UUID student) {
        Map<String, Object> p = desk.process(id).orElseThrow(() -> new NotFound("clearance", id));
        if (!student.equals(p.get("student_id"))) throw new NotFound("clearance", id);
        return p;
    }

    @GetMapping
    @Transactional(readOnly = true)
    Map<String, Object> clearances(Authentication auth) {
        UUID student = me(auth);
        List<Map<String, Object>> out = new ArrayList<>();
        boolean alumni = false;
        for (UUID id : jdbc.sql("SELECT id FROM clearance.process WHERE student_id = :s ORDER BY cancelled_at IS NOT NULL, started_at DESC")
                .param("s", student).query(UUID.class).list()) {
            Map<String, Object> p = desk.process(id).orElseThrow();
            Map<String, Object> one = new LinkedHashMap<>();
            for (String k : List.of("id", "reference", "workflow", "workflow_label", "session", "started_at", "completed_at", "cancelled_at",
                    "cancel_reason", "overall", "complete_word", "certificate")) one.put(k, p.get(k));
            boolean complete = p.get("completed_at") != null && p.get("cancelled_at") == null;
            // the check code the certificate's QR carries, only once there is a certificate to carry it
            one.put("verify_code", complete && Boolean.TRUE.equals(p.get("certificate")) ? p.get("verify_code") : null);
            List<Map<String, Object>> stages = new ArrayList<>();
            for (Map<String, Object> s : desk.stages(p)) {
                Map<String, Object> st = new LinkedHashMap<>(s);
                st.remove("office_code");
                stages.add(st);
                if ("ALUMNI".equals(s.get("unit")) && Boolean.TRUE.equals(s.get("applies")) && p.get("cancelled_at") == null) alumni = true;
            }
            one.put("stages", stages);
            one.put("history", desk.history(p, false));
            one.put("documents", desk.documents(id));
            out.add(one);
        }
        Map<String, Object> r = new LinkedHashMap<>();
        r.put("processes", out);
        r.put("alumni", alumni ? alumni(student) : null);
        return r;
    }

    private Map<String, Object> alumni(UUID student) {
        return jdbc.sql("""
                SELECT c.email, c.phone, c.address, ap.state_of_residence, ap.country, ap.employment_status, ap.employer, ap.occupation, ap.linkedin,
                       coalesce(ap.association_member, false) AS association_member, ap.membership_no, ap.confirmed_at, ap.verified_at
                  FROM people.student s
                  LEFT JOIN people.student_contact c ON c.student_id = s.id
                  LEFT JOIN clearance.alumni_profile ap ON ap.student_id = s.id
                 WHERE s.id = :s
                """).param("s", student).query().singleRow();
    }

    public record Upload(@NotBlank String unit, @NotBlank @Size(max = 120) String label, @NotBlank @Size(max = 200) String fileName,
                         @NotBlank String contentBase64) {
    }

    /** a document a stage asked for, uploaded by the student to a stage that applies to them and is not yet cleared */
    @PostMapping("/{id}/documents")
    @Transactional
    Map<String, Object> upload(Authentication auth, @PathVariable UUID id, @Valid @RequestBody Upload body) {
        UUID student = me(auth);
        Map<String, Object> p = mine(id, student);
        String unit = body.unit().trim().toUpperCase();
        Map<String, Object> stage = desk.stages(p).stream().filter(s -> unit.equals(s.get("unit"))).findFirst()
                .orElseThrow(() -> new NotFound("clearance stage", unit));
        if (!Boolean.TRUE.equals(stage.get("applies")) || "CLEARED".equals(stage.get("state"))) {
            throw new DomainRuleViolation("CLR_STAGE_CLOSED", "That stage takes no upload now.",
                    new DomainRuleViolation.Remedy("Upload to a stage that applies to you and is not yet cleared.", "You"));
        }
        UUID doc = ClearanceDeskController.store(jdbc, files, id, unit, body.label().trim(), body.fileName().trim(),
                ClearanceDeskController.decode(body.contentBase64()), student, "student");
        return Map.of("document", doc);
    }

    @GetMapping("/documents/{doc}/file")
    @Transactional(readOnly = true)
    ResponseEntity<byte[]> file(Authentication auth, @PathVariable UUID doc) {
        UUID process = jdbc.sql("SELECT d.process_id FROM clearance.document d JOIN clearance.process p ON p.id = d.process_id WHERE d.id = :d AND p.student_id = :s")
                .param("d", doc).param("s", me(auth)).query(UUID.class).optional().orElseThrow(() -> new NotFound("document", doc));
        return ClearanceDeskController.file(jdbc, files, doc, process);
    }

    public record Alumni(@Size(max = 80) String stateOfResidence, @Size(max = 80) String country, String employmentStatus,
                         @Size(max = 160) String employer, @Size(max = 120) String occupation, @Size(max = 200) String linkedin,
                         Boolean associationMember, @Size(max = 40) String membershipNo, Boolean confirm) {

        boolean confirming() {
            return Boolean.TRUE.equals(confirm);
        }
    }

    /** the alumni details, kept beside the contact details the student keeps under Biodata; confirm says they are current */
    @PutMapping("/alumni")
    @Transactional
    Map<String, Object> alumni(Authentication auth, @Valid @RequestBody Alumni body) {
        UUID student = me(auth);
        String emp = body.employmentStatus() == null || body.employmentStatus().isBlank() ? null : body.employmentStatus().trim().toUpperCase();
        if (emp != null && !EMPLOYMENT.contains(emp)) {
            throw new DomainRuleViolation("CLR_EMPLOYMENT", "Choose an employment status from the list.", new DomainRuleViolation.Remedy("Pick one, or leave it blank.", "You"));
        }
        if (body.confirming()) {
            Map<String, Object> c = alumni(student);
            if (blank(c.get("email")) || blank(c.get("phone"))) {
                throw new DomainRuleViolation("CLR_CONTACT", "An e-mail and a phone number are needed before you confirm.",
                        new DomainRuleViolation.Remedy("Add them under Contact details, then confirm.", "You"));
            }
        }
        jdbc.sql("""
                INSERT INTO clearance.alumni_profile AS ap (student_id, state_of_residence, country, employment_status, employer, occupation, linkedin,
                                                            association_member, membership_no, confirmed_at, updated_at)
                VALUES (:s, :st, :co, :emp, :er, :oc, :li, :am, :mn, CASE WHEN :confirm THEN now() END, now())
                ON CONFLICT (student_id) DO UPDATE
                   SET state_of_residence = EXCLUDED.state_of_residence, country = EXCLUDED.country, employment_status = EXCLUDED.employment_status,
                       employer = EXCLUDED.employer, occupation = EXCLUDED.occupation, linkedin = EXCLUDED.linkedin,
                       association_member = EXCLUDED.association_member, membership_no = EXCLUDED.membership_no,
                       confirmed_at = CASE WHEN :confirm THEN now() ELSE ap.confirmed_at END, updated_at = now()
                """).param("s", student).param("st", trim(body.stateOfResidence()), Types.VARCHAR).param("co", trim(body.country()), Types.VARCHAR)
                .param("emp", emp, Types.VARCHAR).param("er", trim(body.employer()), Types.VARCHAR).param("oc", trim(body.occupation()), Types.VARCHAR)
                .param("li", trim(body.linkedin()), Types.VARCHAR).param("am", Boolean.TRUE.equals(body.associationMember())).param("mn", trim(body.membershipNo()), Types.VARCHAR)
                .param("confirm", body.confirming()).update();
        return alumni(student);
    }

    /**
     * The certificate's facts, once the clearance is complete and the workflow issues one: the student, the clearance, the
     * offices and the check code its QR carries. The first issue is recorded and the student told.
     */
    @PostMapping("/{id}/certificate")
    @Transactional
    Map<String, Object> certificate(Authentication auth, @PathVariable UUID id) {
        UUID student = me(auth);
        Map<String, Object> p = mine(id, student);
        if (p.get("completed_at") == null || p.get("cancelled_at") != null || !Boolean.TRUE.equals(p.get("certificate"))) {
            throw new DomainRuleViolation("CLR_NO_CERTIFICATE", "The certificate is issued once every office has cleared you.",
                    new DomainRuleViolation.Remedy("Follow the offices still open under My Clearance.", "You"));
        }
        if (p.get("certificate_at") == null) {
            jdbc.sql("UPDATE clearance.process SET certificate_at = now() WHERE id = :id").param("id", id).update();
            jdbc.sql("SELECT clearance.tell(:s, :subj, :body, :sms)").param("s", student)
                    .param("subj", p.get("workflow_label") + " certificate issued (" + p.get("reference") + ")")
                    .param("body", "Your " + String.valueOf(p.get("workflow_label")).toLowerCase() + " certificate (" + p.get("reference")
                            + ") was issued from the portal. Anyone may check it by scanning its QR code.\n\nOffice of the Registrar")
                    .param("sms", "MOAUM: your clearance certificate " + p.get("reference") + " was issued from the portal.").query().singleRow();
        }
        Map<String, Object> out = new LinkedHashMap<>();
        for (String k : List.of("reference", "workflow_label", "session", "completed_at", "surname", "other_names", "matric_no", "admission_no",
                "programme", "department", "faculty", "verify_code")) out.put(k, p.get(k));
        List<Map<String, Object>> stages = new ArrayList<>();
        for (Map<String, Object> s : desk.stages(p)) {
            stages.add(Map.of("label", s.get("label"), "state", s.get("state"), "decided_at", s.get("decided_at") == null ? "" : s.get("decided_at"),
                    "officer", s.get("officer") == null ? "" : s.get("officer")));
        }
        out.put("stages", stages);
        out.put("issued_at", java.time.LocalDate.now().toString());
        return out;
    }

    private static boolean blank(Object o) {
        return o == null || String.valueOf(o).isBlank();
    }

    private static String trim(String s) {
        return s == null || s.isBlank() ? null : s.trim();
    }
}
