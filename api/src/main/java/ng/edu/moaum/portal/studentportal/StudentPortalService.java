package ng.edu.moaum.portal.studentportal;

import java.math.BigDecimal;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import ng.edu.moaum.portal.shared.DomainRuleViolation;
import ng.edu.moaum.portal.shared.NotFound;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * What the student sees and does: the record as the register holds it, the
 * fees as the schedule computes them, the registration against the eligible
 * set, the results the published sheets say. Nothing here is typed by the
 * student except the contact details and the choice of courses.
 */
@Service
public class StudentPortalService {

    private final StudentPortalRepository repo;

    StudentPortalService(StudentPortalRepository repo) {
        this.repo = repo;
    }

    private StudentPortalRepository.Student student(UUID id) {
        return repo.byId(id).orElseThrow(() -> new NotFound("student", id));
    }

    /** the current session, or the latest one the Bursar has charged for */
    public String session() {
        return repo.currentSession().orElseGet(() -> repo.sessionsWithCharges().stream().findFirst().orElse("2026/2027"));
    }

    /* ── me ── */

    @Transactional(readOnly = true)
    public Map<String, Object> me(UUID id) {
        StudentPortalRepository.Student s = student(id);
        String session = session();
        Map<String, Object> v = new LinkedHashMap<>();
        v.put("id", s.id());
        v.put("name", s.surname() + ", " + s.otherNames());
        v.put("surname", s.surname());
        v.put("otherNames", s.otherNames());
        v.put("matricNo", s.matricNo());
        v.put("admissionNo", s.admissionNo());
        v.put("programmeCode", s.programmeCode());
        v.put("programme", s.programme());
        v.put("faculty", s.facultyName());
        v.put("department", s.deptName());
        v.put("entryMode", s.entryMode());
        v.put("entrySession", s.entrySession());
        v.put("entryLevel", s.entryLevel());
        v.put("level", s.currentLevel());
        v.put("status", s.status());
        v.put("curriculumVersion", s.curriculumVersion());
        v.put("session", session);
        v.put("contact", repo.contact(id));
        v.put("passportDocumentId", repo.passportDocument(s.candidateId()).orElse(null));
        v.put("fees", fees(id, session));
        List<Map<String, Object>> gpa = repo.gpa(id);
        v.put("gpa", gpa);
        BigDecimal cgpa = gpa.isEmpty() ? null : (BigDecimal) gpa.get(gpa.size() - 1).get("cgpa");
        v.put("cgpa", cgpa);
        v.put("standing", repo.classOf(cgpa));
        v.put("carryovers", repo.carryovers(id));
        v.put("registration", repo.registration(id, session, 1).map(StudentPortalService::withEntries).orElse(null));
        v.put("notices", repo.notices(id));
        return v;
    }

    @Transactional
    public Map<String, Object> saveContact(UUID id, String phone, String email, String address) {
        String p = phone == null ? null : phone.replaceAll("[^0-9]", "");
        if (p != null && p.length() == 13 && p.startsWith("234")) {
            p = "0" + p.substring(3);
        } else if (p != null && p.length() == 10 && !p.startsWith("0")) {
            p = "0" + p;
        }
        if (p != null && !p.isEmpty() && !p.matches("^0\\d{10}$")) {
            throw new DomainRuleViolation("STU_PHONE", "A Nigerian mobile number is eleven digits beginning with a zero.",
                    new DomainRuleViolation.Remedy("Written as +234 or without the zero is fine.", "You"));
        }
        String e = email == null || email.isBlank() ? null : email.trim();
        if (e != null && !e.matches("^[^\\s@]+@[^\\s@]+\\.[A-Za-z]{2,}$")) {
            throw new DomainRuleViolation("STU_EMAIL", "That is not a complete email address.",
                    new DomainRuleViolation.Remedy("It needs a name, an @, and a domain with a dot in it.", "You"));
        }
        repo.saveContact(id, p == null || p.isEmpty() ? null : p, e, address == null || address.isBlank() ? null : address.trim());
        return repo.contact(id);
    }

    /* ── fees ── */

    @Transactional(readOnly = true)
    public Map<String, Object> fees(UUID id, String session) {
        Map<String, Object> pos = repo.position(id, session);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("session", session);
        out.put("charges", repo.charges(id, session));
        out.put("due", pos.get("due"));
        out.put("paid", pos.get("paid"));
        out.put("balance", pos.get("balance"));
        out.put("instalmentsPaid", pos.get("instalments_paid"));
        out.put("paidInFull", pos.get("paid_in_full"));
        out.put("hasArrears", pos.get("has_arrears"));
        Boolean registration = null;
        String schemeProblem = null;
        try {
            registration = repo.clears(id, session, "REGISTRATION");
        } catch (RuntimeException noScheme) {
            schemeProblem = "No clearance scheme is in force, so nothing is released against a payment yet; the Bursar states the scheme.";
        }
        out.put("clearsRegistration", registration);
        out.put("schemeProblem", schemeProblem);
        out.put("references", repo.references(id));
        out.put("sessions", repo.sessionsWithCharges());
        return out;
    }

    @Transactional
    public Map<String, Object> newReference(UUID id, String session, BigDecimal amount) {
        String ses = session == null || session.isBlank() ? session() : session.trim();
        Map<String, Object> pos = repo.position(id, ses);
        BigDecimal balance = (BigDecimal) pos.get("balance");
        BigDecimal amt = amount == null ? balance : amount;
        String reference = repo.newReference(id, ses, amt, "School fees " + ses);
        Map<String, Object> out = new LinkedHashMap<>(fees(id, ses));
        out.put("reference", reference);
        return out;
    }

    @Transactional(readOnly = true)
    public Map<String, Object> receipt(UUID id, String reference) {
        Map<String, Object> r = repo.reference(id, reference).orElseThrow(() -> new NotFound("payment reference", reference));
        StudentPortalRepository.Student s = student(id);
        Map<String, Object> out = new LinkedHashMap<>(r);
        out.put("name", s.surname() + ", " + s.otherNames());
        out.put("matricNo", s.matricNo());
        out.put("programme", s.programme());
        out.put("level", s.currentLevel());
        return out;
    }

    /* ── registration ── */

    @Transactional(readOnly = true)
    public Map<String, Object> registrationView(UUID id, String session, int semester) {
        StudentPortalRepository.Student s = student(id);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("session", session);
        out.put("semester", semester);
        out.put("level", s.currentLevel());
        out.put("limit", repo.limit(s.currentLevel()));
        out.put("menu", repo.menu(id, session, semester));
        out.put("registration", repo.registration(id, session, semester).map(StudentPortalService::withEntries).orElse(null));
        out.put("fees", fees(id, session));
        out.put("status", s.status());
        return out;
    }

    @Transactional
    public Map<String, Object> choose(UUID id, String session, int semester, List<UUID> offerings) {
        StudentPortalRepository.Student s = student(id);
        if (!List.of("ADMITTED", "ACTIVE", "PROBATION").contains(s.status())) {
            throw new DomainRuleViolation("REG_STUDENT_NOT_ELIGIBLE", "A student who is " + s.status().toLowerCase() + " does not register.",
                    new DomainRuleViolation.Remedy("Only an admitted, active or probation student may register.", "Academic Office"));
        }
        UUID reg = repo.draft(id, session, semester);
        repo.choose(reg, offerings == null ? List.of() : offerings);
        return registrationView(id, session, semester);
    }

    @Transactional
    public Map<String, Object> submit(UUID id, String session, int semester) {
        UUID reg = repo.draft(id, session, semester);
        repo.submit(reg);
        return registrationView(id, session, semester);
    }

    /* ── results ── */

    @Transactional(readOnly = true)
    public Map<String, Object> results(UUID id) {
        StudentPortalRepository.Student s = student(id);
        List<Map<String, Object>> rows = repo.results(id);
        List<Map<String, Object>> gpa = repo.gpa(id);
        BigDecimal cgpa = gpa.isEmpty() ? null : (BigDecimal) gpa.get(gpa.size() - 1).get("cgpa");
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("name", s.surname() + ", " + s.otherNames());
        out.put("matricNo", s.matricNo());
        out.put("programme", s.programme());
        out.put("level", s.currentLevel());
        out.put("rows", rows);
        out.put("semesters", gpa);
        out.put("cgpa", cgpa);
        out.put("standing", repo.classOf(cgpa));
        out.put("carryovers", repo.carryovers(id));
        Boolean resultsCleared = null;
        try {
            resultsCleared = repo.clears(id, session(), "RESULTS");
        } catch (RuntimeException noScheme) {
            resultsCleared = null;
        }
        out.put("clearsResults", resultsCleared);
        return out;
    }

    /* ── helpers ── */

    static Map<String, Object> withEntries(Map<String, Object> r) {
        Map<String, Object> out = new LinkedHashMap<>(r);
        Object entries = r.get("entries");
        out.put("entries", entries == null ? List.of() : Json.list(String.valueOf(entries)));
        return out;
    }

    static final class Json {
        private static final tools.jackson.databind.ObjectMapper MAPPER = new tools.jackson.databind.ObjectMapper();

        static List<Map<String, Object>> list(String text) {
            if (text == null || text.isBlank() || "null".equals(text)) {
                return new ArrayList<>();
            }
            return MAPPER.readValue(text, new tools.jackson.core.type.TypeReference<List<Map<String, Object>>>() { });
        }
    }
}
