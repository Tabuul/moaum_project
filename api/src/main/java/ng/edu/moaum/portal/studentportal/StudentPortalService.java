package ng.edu.moaum.portal.studentportal;

import java.math.BigDecimal;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import ng.edu.moaum.portal.shared.DomainRuleViolation;
import ng.edu.moaum.portal.shared.CheckCodes;
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

    private final CheckCodes codes;

    StudentPortalService(StudentPortalRepository repo, CheckCodes codes) {
        this.repo = repo;
        this.codes = codes;
    }

    /** V360: the signed check code the student's own examination card, course form or results statement carries in its QR —
     *  over the number the document prints (the matriculation number, or the admission number before it is issued) */
    @Transactional(readOnly = true)
    public Map<String, Object> checkCode(UUID id, String kind, String session, int semester) {
        CheckCodes.Kind k = switch (kind == null ? "" : kind.trim().toUpperCase()) {
            case "EXAM" -> CheckCodes.Kind.EXAM;
            case "REG" -> CheckCodes.Kind.REG;
            case "RESULT" -> CheckCodes.Kind.RESULT;
            default -> throw new DomainRuleViolation("CHECK_CODE_KIND", "A check code is made for an examination card (EXAM), a course form (REG) or a results statement (RESULT).");
        };
        if (session == null || !session.matches("^[0-9]{4}/[0-9]{4}$") || semester < 1 || semester > 3) {
            throw new DomainRuleViolation("CHECK_CODE_SESSION", "A check code is made for one session (such as 2026/2027) and one semester.");
        }
        StudentPortalRepository.Student s = student(id);
        String number = s.matricNo() != null ? s.matricNo() : s.admissionNo();
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("kind", k.name());
        out.put("number", number);
        out.put("session", session);
        out.put("semester", semester);
        out.put("code", codes.sign(k, number, session, String.valueOf(semester)));
        return out;
    }

    private StudentPortalRepository.Student student(UUID id) {
        return repo.byId(id).orElseThrow(() -> new NotFound("student", id));
    }

    /** the student's passport image bytes, from the document store or the JAMB/attachment store */
    @Transactional(readOnly = true)
    public java.util.Optional<byte[]> passportImage(UUID id) {
        return repo.passportImage(id).map(StudentPortalService::toJpeg);
    }

    /** Serve the passport as JPEG whatever it was stored as. The exam card, course form and receipt PDFs embed
     *  only JPEG (DCTDecode), so a PNG — which the bulk passport upload accepts — would otherwise print a blank
     *  photo box, defeating the invigilator's face check. Already-JPEG bytes pass straight through. */
    private static byte[] toJpeg(byte[] img) {
        if (img == null || img.length < 2) {
            return img;
        }
        if ((img[0] & 0xFF) == 0xFF && (img[1] & 0xFF) == 0xD8) {
            return img;   // JPEG SOI marker — already JPEG
        }
        try {
            java.awt.image.BufferedImage src = javax.imageio.ImageIO.read(new java.io.ByteArrayInputStream(img));
            if (src == null) {
                return img;   // not a decodable raster (e.g. already-unknown bytes) — serve as-is
            }
            // JPEG has no alpha, so flatten any transparency onto white
            java.awt.image.BufferedImage rgb = new java.awt.image.BufferedImage(
                    src.getWidth(), src.getHeight(), java.awt.image.BufferedImage.TYPE_INT_RGB);
            java.awt.Graphics2D g = rgb.createGraphics();
            g.drawImage(src, 0, 0, java.awt.Color.WHITE, null);
            g.dispose();
            java.io.ByteArrayOutputStream out = new java.io.ByteArrayOutputStream();
            if (!javax.imageio.ImageIO.write(rgb, "jpg", out)) {
                return img;
            }
            return out.toByteArray();
        } catch (java.io.IOException e) {
            return img;   // decode/encode failed — serve the original bytes rather than nothing
        }
    }

    /** the current session, or the latest one the Bursar has charged for */
    public String session() {
        return repo.currentSession().orElseGet(() -> repo.sessionsWithCharges().stream().findFirst().orElse("2026/2027"));
    }

    /**
     * The session a student stands in: the University's current session — or, for
     * an entrant admitted for a session that is still planned (the register is
     * built before the session opens), that entry session. Fees, registration and
     * the dashboard open on it; otherwise a fresh student landed on the closing
     * session, saw no charge there, and could not pay.
     * <p>
     * Between sessions — none CURRENT, the last one CLOSED and the next still
     * PLANNED — a returning student stands in the session the University last
     * ran (2025/2026), not in the planned one the Bursar has already stated a
     * charge for (2026/2027): their charge, payments and registration are there,
     * and the planned session is a click away on the fees page. An entrant of the
     * planned session still stands in it.
     */
    private String sessionOf(StudentPortalRepository.Student s) {
        String current = repo.currentSession().or(repo::latestRunSession).orElseGet(this::session);
        return s.entrySession() != null && s.entrySession().compareTo(current) > 0 ? s.entrySession() : current;
    }

    public String sessionFor(UUID id) {
        return sessionOf(student(id));
    }

    /* ── me ── */

    @Transactional(readOnly = true)
    public Map<String, Object> me(UUID id) {
        StudentPortalRepository.Student s = student(id);
        // a record closed by voluntary withdrawal (V247) is refused at the portal, with the reason
        if ("VOLUNTARY_WITHDRAWAL".equals(s.status())) {
            throw new DomainRuleViolation("STUDENT_RECORD_CLOSED",
                    "Your record was closed as a voluntary withdrawal: four consecutive semesters passed without a course registration, and the University's regulation removes the record.",
                    new DomainRuleViolation.Remedy("Write to the Registrar if you believe the record should be reopened.", "Registry"));
        }
        String session = sessionOf(s);
        Map<String, Object> v = new LinkedHashMap<>();
        v.put("id", s.id());
        v.put("name", s.surname() + ", " + s.otherNames());
        v.put("surname", s.surname());
        v.put("otherNames", s.otherNames());
        v.put("matricNo", s.matricNo());
        v.put("admissionNo", s.admissionNo());
        // the sign-in they use: the matriculation number once issued, until then the JAMB number they have used since application (V282)
        v.put("jambRegNo", s.jambRegNo());
        v.put("loginId", s.matricNo() != null ? s.matricNo() : s.jambRegNo() != null ? s.jambRegNo() : s.admissionNo());
        v.put("lifecycle", repo.lifecycle(id));
        v.put("programmeCode", s.programmeCode());
        v.put("programme", s.programme());
        v.put("faculty", s.facultyName());
        v.put("collegeCode", s.collegeCode());
        v.put("department", s.deptName());
        v.put("entryMode", s.entryMode());
        v.put("entrySession", s.entrySession());
        v.put("entryLevel", s.entryLevel());
        v.put("level", s.currentLevel());
        v.put("status", s.status());
        v.put("curriculumVersion", s.curriculumVersion());
        v.put("session", session);
        // V331: where the student stands — the cohort that carries them (the entry session, or the session it was merged into), the
        // expected completion, and the spillover; the entry session and the matriculation number above stay what history made them
        repo.academicPosition(id).ifPresent(pos -> {
            v.put("jambYear", pos.get("jamb_year"));
            v.put("effectiveCohort", pos.get("effective_cohort"));
            v.put("cohortSource", pos.get("cohort_source"));
            v.put("durationYears", pos.get("duration_years"));
            v.put("expectedCompletion", pos.get("expected_completion"));
            v.put("spilloverState", pos.get("spillover_state"));
            v.put("spilloverYears", pos.get("spillover_years"));
            v.put("classification", pos.get("classification"));
        });
        v.put("contact", repo.contact(id));
        v.put("passportDocumentId", repo.passportDocument(s.candidateId()).orElse(null));
        v.put("hasPhoto", repo.hasPassport(id));
        v.put("fees", fees(id, session));
        // V288: the portal's windows as the dashboard shows them: school fees payment for the session, course registration for the open semester
        Map<String, Object> windows = new LinkedHashMap<>();
        windows.put("schoolFees", repo.windowState("SCHOOL_FEES_PAYMENT", session, null));
        windows.put("courseRegistration", repo.windowState("COURSE_REGISTRATION", session, repo.openSemester(session)));
        v.put("windows", windows);
        List<Map<String, Object>> gpa = repo.gpa(id);
        v.put("gpa", gpa);
        BigDecimal cgpa = gpa.isEmpty() ? null : (BigDecimal) gpa.get(gpa.size() - 1).get("cgpa");
        v.put("cgpa", cgpa);
        v.put("standing", repo.classOf(cgpa));
        v.put("probation", repo.standing(id, s.currentLevel()));
        v.put("carryovers", repo.carryovers(id));
        v.put("registration", repo.registration(id, session, 1).map(StudentPortalService::withEntries).orElse(null));
        v.put("notices", repo.notices(id));
        v.put("graduation", repo.graduation(id));
        v.put("academic", academic(id, s, String.valueOf(v.get("lifecycle")), (Map<String, Object>) v.get("fees")));
        return v;
    }

    /**
     * V289: the academic context the dashboard names — the session the student
     * stands in, whether they are a returning student of the current session or
     * an entrant preparing for a session still planned — and, for the entrant,
     * where they stand on the University's own pre-resumption requirements:
     * admission, acceptance, screening, school fees, the account, course
     * registration and the matriculation number. Nothing is invented: each step
     * is read from the record that already holds it.
     */
    private Map<String, Object> academic(UUID id, StudentPortalRepository.Student s, String lifecycle, Map<String, Object> fees) {
        Map<String, Object> ctx = new LinkedHashMap<>(repo.academicContext(id));
        boolean preparing = "PREPARING".equals(ctx.get("context"));
        int rank = switch (lifecycle == null ? "" : lifecycle) {
            case "ACCEPTANCE_PENDING", "OFFERED", "APPROVED", "CHECKING_FEE_PENDING" -> 1;
            case "SCREENING_PENDING", "SCREENING_IN_REVIEW", "SCREENING_CORRECTION", "CHANGE_OF_PROGRAMME_PENDING", "CHANGE_OF_PROGRAMME_REQUIRED" -> 2;
            case "SCHOOL_FEES_PENDING" -> 3;
            case "REGISTER_PENDING" -> 4;
            case "COURSE_REGISTRATION_PENDING" -> 5;
            case "MATRICULATION_PENDING" -> 6;
            case "MATRICULATED" -> 7;
            default -> s.matricNo() != null ? 7 : 4;   // on the register without an admission trail: the fees decide the rest
        };
        String session = String.valueOf(ctx.get("session"));
        boolean feesPaid = Boolean.TRUE.equals(fees.get("paidInFull")) || Boolean.TRUE.equals(fees.get("clearsRegistration")) || rank >= 4;
        boolean registered = repo.registrationIn(id, session) || rank >= 6;
        Map<String, Object> steps = new LinkedHashMap<>();
        steps.put("admission", true);
        steps.put("acceptance", rank >= 2);
        steps.put("screening", rank >= 3);
        steps.put("schoolFees", feesPaid);
        steps.put("account", true);
        steps.put("courseRegistration", registered);
        steps.put("matriculation", s.matricNo() != null);
        boolean ready = steps.values().stream().allMatch(Boolean.TRUE::equals);
        ctx.put("steps", steps);
        ctx.put("ready", ready);
        ctx.put("status", preparing ? (ready ? "READY_FOR_RESUMPTION" : "FRESH_STUDENT_PREPARING") : "CURRENT_SESSION");
        return ctx;
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
        // V361: whether the Bursary has stated a school fee that applies to the student — until it has, nothing is cleared
        out.put("stated", repo.feeStated(id, session));
        out.put("due", pos.get("due"));
        out.put("paid", pos.get("paid"));
        out.put("balance", pos.get("balance"));
        out.put("instalmentsPaid", pos.get("instalments_paid"));
        out.put("paidInFull", pos.get("paid_in_full"));
        out.put("hasArrears", pos.get("has_arrears"));
        /* per-semester amounts, so the student pays a fixed first / second / full-session figure
         * rather than typing one. Payments are cumulative (V149): the first semester must clear
         * before the second, so each figure below is what is still owed toward that milestone. */
        BigDecimal paid = (BigDecimal) pos.get("paid");
        BigDecimal balance = (BigDecimal) pos.get("balance");
        BigDecimal firstDue = repo.dueForSemester(id, session, 1);
        BigDecimal firstOutstanding = firstDue.subtract(paid).max(BigDecimal.ZERO);
        BigDecimal secondOutstanding = balance.subtract(firstOutstanding).max(BigDecimal.ZERO);
        out.put("firstSemesterOutstanding", firstOutstanding);
        out.put("secondSemesterOutstanding", secondOutstanding);
        /* registration is now gated per semester on that semester's school fees, paid in full (V149) */
        boolean inForce = repo.schemeInForce();
        out.put("clearsRegistration", repo.semesterCleared(id, session, repo.openSemester(session)));
        String schemeProblem = inForce ? null : "No clearance scheme is in force, so the examination, results and transcript are not yet released against a payment; the Bursar states the scheme. Course registration opens on this semester's school fees, paid in full.";
        out.put("schemeProblem", schemeProblem);
        out.put("references", repo.references(id));
        out.put("sessions", repo.sessionsWithCharges());
        out.put("window", repo.windowState("SCHOOL_FEES_PAYMENT", session, null));   // V288: open, scheduled, closed, or in the late period
        return out;
    }

    /** the portal's school-fees window (V288): a new reference is generated only while it is open; one already generated is paid as before */
    private void assertFeesWindowOpen(String session) {
        Map<String, Object> w = repo.windowState("SCHOOL_FEES_PAYMENT", session, null);
        String state = String.valueOf(w.get("state"));
        if (!"OPEN".equals(state)) {
            throw new DomainRuleViolation("SCHOOL_FEES_PAYMENT_CLOSED", "School fees payment is currently " + ("SCHEDULED".equals(state) ? "not yet open" : "closed") + " for " + session + "."
                    + (w.get("reason") == null ? "" : " " + w.get("reason")),
                    new DomainRuleViolation.Remedy("SCHEDULED".equals(state) ? "It opens on the date the Directorate of ICT set; check again then." : "The Directorate of ICT reopens the payment window; a reference already generated may still be paid.", "Directorate of ICT"));
        }
    }

    @Transactional
    public Map<String, Object> newReference(UUID id, String session, BigDecimal amount) {
        String ses = session == null || session.isBlank() ? sessionFor(id) : session.trim();
        assertFeesWindowOpen(ses);
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
        out.put("name", s.surname().toUpperCase() + ", " + s.otherNames());
        out.put("matricNo", s.matricNo());
        out.put("programme", s.programme());
        // the level the student was at when they paid this session's fee, not today's level
        out.put("level", repo.levelForSession(id, String.valueOf(r.get("session"))));
        // V360: the signed check code the receipt's QR carries, over the reference and the receipt number
        if (r.get("receipt_no") != null) {
            out.put("checkCode", codes.sign(CheckCodes.Kind.RECEIPT, String.valueOf(r.get("reference")), String.valueOf(r.get("receipt_no"))));
        }
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
        // the SIWES / industrial-training semester carries exactly the SIWES units, not the 18-24 range
        Integer siwes = repo.siwesUnits(id, s.currentLevel(), semester);
        // on probation, the form's ceiling is the level's probation ceiling where the Registry has set one
        Map<String, Object> standing = repo.standing(s.id(), s.currentLevel());
        Map<String, Object> limit = siwes != null ? Map.of("min_units", siwes, "max_units", siwes) : new java.util.LinkedHashMap<>(repo.limit(s.currentLevel()));
        if (siwes == null && "PROBATION".equals(standing.get("standing")) && standing.get("probation_max_units") != null) {
            int cap = ((Number) standing.get("probation_max_units")).intValue();
            int max = ((Number) limit.get("max_units")).intValue();
            if (cap < max) { limit.put("max_units", cap); limit.put("min_units", Math.min(((Number) limit.get("min_units")).intValue(), cap)); }
        }
        out.put("limit", limit);
        out.put("probation", standing);
        out.put("siwes", siwes != null);
        // V314: a GST/EPS course on the menu says whether the GST fee locks it, and why
        List<Map<String, Object>> menu = repo.menu(id, session, semester);
        for (Map<String, Object> m : menu) {
            if ("GST".equals(m.get("kind")) || "GST".equals(m.get("basis"))) {
                String gate = repo.gstGate(id, session, String.valueOf(m.get("course_code")));
                m.put("gstLocked", gate != null);
                m.put("gstGate", gate);
            }
        }
        out.put("menu", menu);
        out.put("gst", repo.gstEntitlement(id, session));
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
        // V287 · the semester's door: open, closed, not yet open, or open early to the session's fresh students
        Map<String, Object> window = new LinkedHashMap<>();
        Map<String, Object> sm = repo.semesterWindow(session, semester);
        if (sm != null) window.putAll(sm);
        String gate = repo.registrationGate(id, session, semester);
        window.put("gate", gate);
        window.put("open", gate == null);
        window.put("fresh", session.equals(s.entrySession()));
        window.put("portal", repo.windowState("COURSE_REGISTRATION", session, semester));   // V288
        out.put("window", window);
        return out;
    }

    /** GST & EPS (V314): the fee stated for the student, the entitlement a confirmed payment grants, the references, the courses */
    @Transactional(readOnly = true)
    public Map<String, Object> gst(UUID id, String session) {
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("session", session);
        out.put("entitlement", repo.gstEntitlement(id, session));
        out.put("setting", repo.gstSetting());
        out.put("references", repo.gstReferences(id));
        out.put("courses", repo.gstCourses(id, session));
        return out;
    }

    /** the reference to pay the GST fee against: the stated fee, once; an open one is returned again rather than doubled */
    @Transactional
    public Map<String, Object> newGstReference(UUID id, String session) {
        String ses = session == null || session.isBlank() ? sessionFor(id) : session;
        String reference = repo.newGstReference(id, ses);
        Map<String, Object> out = new LinkedHashMap<>(gst(id, ses));
        out.put("reference", reference);
        return out;
    }

    /** the calendar's word on the semester (V287): a registration is drafted, changed or submitted only while the door is open */
    private void assertWindowOpen(UUID id, String session, int semester) {
        String gate = repo.registrationGate(id, session, semester);
        if (gate != null) {
            throw new DomainRuleViolation("COURSE_REGISTRATION_CLOSED", gate,
                    new DomainRuleViolation.Remedy("The Directorate of ICT opens the registration window; the Academic Office opens the semester on the calendar or dates the early window for the session's fresh students.", "Directorate of ICT"));
        }
    }

    @Transactional
    public Map<String, Object> addCourse(UUID id, String session, int semester, UUID offering) {
        assertWindowOpen(id, session, semester);
        repo.addCourse(id, session, semester, offering);
        return registrationView(id, session, semester);
    }

    @Transactional
    public Map<String, Object> dropCourse(UUID id, String session, int semester, UUID offering) {
        assertWindowOpen(id, session, semester);
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
        out.put("name", s.surname().toUpperCase() + ", " + s.otherNames());
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
        assertWindowOpen(id, session, semester);
        UUID reg = repo.draft(id, session, semester);
        repo.choose(reg, offerings == null ? List.of() : offerings);
        return registrationView(id, session, semester);
    }

    @Transactional
    public Map<String, Object> submit(UUID id, String session, int semester) {
        assertWindowOpen(id, session, semester);
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
        // the level the student held in each semester (V330), so a past statement reads at its own level, not today's
        Map<String, Integer> levels = new java.util.HashMap<>();
        java.util.function.BiFunction<String, Object, Integer> levelOf = (ses, sem) -> {
            int m = sem == null ? 1 : ((Number) sem).intValue();
            return levels.computeIfAbsent(ses + "|" + m, k -> { Integer l = repo.levelIn(id, ses, m); return l == null ? s.currentLevel() : l; });
        };
        for (Map<String, Object> row : rows) row.put("level", levelOf.apply(String.valueOf(row.get("session")), row.get("semester")));
        for (Map<String, Object> g : gpa) g.put("level", levelOf.apply(String.valueOf(g.get("session")), g.get("semester")));

        Map<String, Object> out = new LinkedHashMap<>();
        out.put("name", s.surname().toUpperCase() + ", " + s.otherNames());
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
        out.put("name", s.surname().toUpperCase() + ", " + s.otherNames());
        out.put("matricNo", s.matricNo());
        out.put("programme", s.programme());
        out.put("level", s.currentLevel());
        out.put("clearance", repo.clearancePosition(id));
        return out;
    }
}
