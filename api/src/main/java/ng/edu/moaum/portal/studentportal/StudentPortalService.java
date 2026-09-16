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
        v.put("graduation", repo.graduation(id));
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
        /* registration is now gated per semester on that semester's school fees, paid in full (V149) */
        boolean inForce = repo.schemeInForce();
        out.put("clearsRegistration", repo.semesterCleared(id, session, repo.openSemester(session)));
        String schemeProblem = inForce ? null : "No clearance scheme is in force, so the examination, results and transcript are not yet released against a payment; the Bursar states the scheme. Course registration opens on this semester's school fees, paid in full.";
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
        // the level the student was at when they paid this session's fee, not today's level
        out.put("level", repo.levelForSession(id, String.valueOf(r.get("session"))));
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
        out.put("addDropOpen", repo.addDropOpen(session, semester));
        /* registration is gated per semester on that semester's fees (V149). A student who has paid
         * the whole session may register an earlier semester they never registered — the fee gate
         * clears it — so the screen offers each semester up to the open one and gates on the one in
         * view, not only the open one. */
        out.put("clears", repo.semesterCleared(id, session, semester));
        out.put("openSemester", repo.openSemester(session));
        out.put("registeredSemesters", repo.registeredSemesters(id, session));
        return out;
    }

    @Transactional
    public Map<String, Object> addCourse(UUID id, String session, int semester, UUID offering) {
        repo.addCourse(id, session, semester, offering);
        return registrationView(id, session, semester);
    }

    @Transactional
    public Map<String, Object> dropCourse(UUID id, String session, int semester, UUID offering) {
        repo.dropCourse(id, session, semester, offering);
        return registrationView(id, session, semester);
    }

    @Transactional(readOnly = true)
    public Map<String, Object> registrationHistory(UUID id) {
        StudentPortalRepository.Student s = student(id);
        List<Map<String, Object>> history = repo.registrationHistory(id).stream().map(StudentPortalService::withEntries).toList();
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("matricNo", s.matricNo());
        out.put("admissionNo", s.admissionNo());
        out.put("name", s.surname() + ", " + s.otherNames());
        out.put("programme", s.programme());
        out.put("history", history);
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

        // the fee gate: a semester's marks are withheld until that session's fees clear (RESULTS).
        // Redacted here on the server, not just hidden on the screen, so an unpaid student cannot read
        // the marks through the raw endpoint. No scheme in force means no gate.
        boolean scheme = repo.schemeInForce();
        Map<String, Boolean> clearedBySession = new java.util.HashMap<>();
        java.util.function.Function<String, Boolean> cleared = ses ->
                !scheme || clearedBySession.computeIfAbsent(ses, x -> repo.clears(id, x, "RESULTS"));
        List<String> withheld = new java.util.ArrayList<>();
        for (Map<String, Object> row : rows) {
            String ses = String.valueOf(row.get("session"));
            if (!Boolean.TRUE.equals(cleared.apply(ses))) {
                row.put("ca", null); row.put("exam", null); row.put("total", null);
                row.put("grade", null); row.put("points", null);
                row.put("withheld", true);
                if (!withheld.contains(ses)) {
                    withheld.add(ses);
                }
            } else {
                row.put("withheld", false);
            }
        }
        for (Map<String, Object> g : gpa) {
            if (!Boolean.TRUE.equals(cleared.apply(String.valueOf(g.get("session"))))) {
                g.put("gpa", null); g.put("cgpa", null);
            }
        }
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
        Boolean resultsCleared = scheme ? repo.clears(id, session(), "RESULTS") : null;
        out.put("clearsResults", resultsCleared);
        out.put("withheldSessions", withheld);
        return out;
    }

    /* ── the services (V027) ── */

    @Transactional(readOnly = true)
    public Map<String, Object> queries(UUID id) {
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("queryable", repo.queryable(id));
        out.put("queries", repo.queries(id));
        return out;
    }

    @Transactional
    public Map<String, Object> raiseQuery(UUID id, UUID sheet, String part, String said) {
        String p = part == null ? "" : part.trim().toUpperCase();
        if (!List.of("EXAM", "CA", "ABSENT").contains(p)) {
            throw new DomainRuleViolation("RES_QUERY_PART", "A query names the mark it is about.",
                    new DomainRuleViolation.Remedy("The examination mark, the continuous assessment mark, or an absence recorded for a paper you sat.", "You"));
        }
        if (said == null || said.isBlank()) {
            throw new DomainRuleViolation("RES_QUERY_SAID", "Say what you say is wrong.",
                    new DomainRuleViolation.Remedy("What you expected and why. 'I expected a better grade' is not a query.", "You"));
        }
        Map<String, Object> out = new LinkedHashMap<>(Map.of("ref", repo.raiseQuery(id, sheet, p, said)));
        out.putAll(queries(id));
        return out;
    }

    @Transactional(readOnly = true)
    public Map<String, Object> docket(UUID id) {
        String session = session();
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("session", session);
        boolean inForce = repo.schemeInForce();
        Boolean cleared = inForce ? repo.clears(id, session, "EXAMINATION") : null;
        String schemeProblem = inForce ? null : "No clearance scheme is in force, so nothing is released against a payment yet; the Bursar states the scheme.";
        out.put("clearsExamination", cleared);
        out.put("schemeProblem", schemeProblem);
        List<Map<String, Object>> sessions = new ArrayList<>();
        for (Map<String, Object> x : repo.examSessions(session)) {
            Map<String, Object> e = new LinkedHashMap<>(x);
            e.put("papers", repo.docket(id, (UUID) x.get("id")));
            sessions.add(e);
        }
        out.put("examSessions", sessions);
        return out;
    }

    @Transactional(readOnly = true)
    public Map<String, Object> timetable(UUID id, int semester) {
        String session = session();
        return Map.of("session", session, "semester", semester, "slots", repo.timetable(id, session, semester), "attendance", repo.attendance(id, session, semester));
    }

    @Transactional(readOnly = true)
    public Map<String, Object> card(UUID id) {
        StudentPortalRepository.Student s = student(id);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("matricNo", s.matricNo());
        out.put("cards", repo.cards(id));
        Boolean cleared = repo.schemeInForce() ? repo.clears(id, session(), "ID_CARD") : null;
        out.put("clearsIdCard", cleared);
        return out;
    }

    @Transactional
    public Map<String, Object> reportLost(UUID id, String reason) {
        repo.reportLost(id, reason);
        return card(id);
    }

    @Transactional(readOnly = true)
    public Map<String, Object> transcripts(UUID id) {
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("fee", repo.transcriptFee(session()));
        out.put("requests", repo.transcripts(id));
        return out;
    }

    @Transactional
    public Map<String, Object> requestTranscript(UUID id, String destination, String destinationName, String mode, Integer copies) {
        String d = destination == null ? "" : destination.trim().toUpperCase();
        if (!List.of("SELF", "INSTITUTION", "EMPLOYER", "EMBASSY").contains(d)) {
            throw new DomainRuleViolation("CTP_DESTINATION", "A transcript goes to you, an institution, an employer or an embassy.",
                    new DomainRuleViolation.Remedy("Choose one.", "You"));
        }
        String m = mode == null || mode.isBlank() ? "DIGITAL" : mode.trim().toUpperCase();
        int c = copies == null ? 1 : Math.max(1, Math.min(10, copies));
        String ref = repo.requestTranscript(id, d, destinationName, m, c);
        String session = session();
        BigDecimal fee = repo.transcriptFee(session).multiply(BigDecimal.valueOf(c));
        String reference = repo.purposeReference(id, session, fee, "Transcript " + ref);
        Map<String, Object> out = new LinkedHashMap<>(transcripts(id));
        out.put("ref", ref);
        out.put("reference", reference);
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

    /* ── graduation, the student's end (V029) ── */

    @Transactional(readOnly = true)
    public Map<String, Object> graduation(UUID id) {
        StudentPortalRepository.Student s = student(id);
        Map<String, Object> out = new LinkedHashMap<>(repo.graduation(id));
        out.put("name", s.surname() + ", " + s.otherNames());
        out.put("matricNo", s.matricNo());
        out.put("programme", s.programme());
        out.put("level", s.currentLevel());
        out.put("clearance", repo.clearancePosition(id));
        return out;
    }
}
