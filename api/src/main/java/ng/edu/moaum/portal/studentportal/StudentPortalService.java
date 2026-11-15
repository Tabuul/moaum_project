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
import ng.edu.moaum.portal.platform.SupportView;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Service;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.TransactionDefinition;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionTemplate;
import ng.edu.moaum.portal.shared.Sessions;

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

    /** V512: the GST/EPS registration log's own transaction — a refused add rolls back, its attempt and its hold stay recorded */
    private final TransactionTemplate ownTransaction;

    /** V724: the student portal's fee gate, read for GET /me (finance.portal_access_state) */
    private final JdbcClient jdbc;

    StudentPortalService(StudentPortalRepository repo, CheckCodes codes, PlatformTransactionManager transactions, JdbcClient jdbc) {
        this.repo = repo;
        this.codes = codes;
        this.jdbc = jdbc;
        this.ownTransaction = new TransactionTemplate(transactions);
        this.ownTransaction.setPropagationBehavior(TransactionDefinition.PROPAGATION_REQUIRES_NEW);
    }

    /** V360: the signed check code the student's own examination card, course form or results statement carries in its QR —
     *  over the number the document prints (the matriculation number, or the admission number before it is issued) */
    @Transactional
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
        // V495/V501/V567: an examination card's code is signed only when the card's own rule says it may be issued (a registration
        // submitted carrying a course, the school fees paid) — the card issued is counted only then
        if (k == CheckCodes.Kind.EXAM) {
            Map<String, Object> card = examCard(id, session, semester);
            if (!Boolean.TRUE.equals(card.get("available"))) {
                throw new DomainRuleViolation(String.valueOf(card.get("code")), String.valueOf(card.get("reason")),
                        new DomainRuleViolation.Remedy("Register and submit your courses and pay your school fees; the card follows.", "Academic Office"));
            }
        }
        String number = s.matricNo() != null ? s.matricNo() : s.admissionNo();
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("kind", k.name());
        out.put("number", number);
        out.put("session", session);
        out.put("semester", semester);
        out.put("code", codes.sign(k, number, session, String.valueOf(semester)));
        // V491: the examination card is issued with its code; counted once a student and semester, with how many times — V589: not
        // when ICT Support looks at the card as the student (V521): the view reads, counts nothing, and is no longer refused the card
        if (k == CheckCodes.Kind.EXAM && !SupportView.active()) repo.recordExamCard(id, session, semester);
        return out;
    }

    /** V501: the examination card's state for the session and semester (registration.exam_card_state) — available or the first
     *  rule that fails, with every course on the approved registration; nothing is counted */
    @Transactional(readOnly = true)
    public Map<String, Object> examCard(UUID id, String session, int semester) {
        return GstEpsPermits.read(repo.examCardState(id, session, semester));
    }

    private StudentPortalRepository.Student student(UUID id) {
        return repo.byId(id).orElseThrow(() -> new NotFound("student", id));
    }

    /** the student's passport image bytes, from the document store or the JAMB/attachment store */
    @Transactional(readOnly = true)
    public java.util.Optional<byte[]> passportImage(UUID id) {
        return repo.passportImage(id).map(StudentPortalService::toJpeg);
    }

    private static final int MAX_PHOTO = 2 * 1024 * 1024;

    /**
     * V423: the student gives their own passport photograph — but only a first one: when the portal finds a photograph
     * anywhere (replaced on the portal, the admission's document, the attachment store), changing it stays with ICT
     * Support, who sees the student and records why. A JPEG or a PNG up to 2 MB, kept where every other photograph is.
     */
    @Transactional
    public Map<String, Object> uploadPassport(UUID id, String dataUrl) {
        student(id);
        if (repo.hasPassport(id)) {
            throw new DomainRuleViolation("PHOTO_ON_RECORD", "Your passport photograph is already on record.",
                    new DomainRuleViolation.Remedy("To change it, ask ICT Support through Help & Requests.", "ICT Support"));
        }
        String u = dataUrl.trim();
        int comma = u.indexOf(',');
        String head = comma > 0 ? u.substring(0, comma).toLowerCase() : "";
        String type = head.contains("image/png") ? "image/png" : head.contains("image/jpeg") || head.contains("image/jpg") ? "image/jpeg" : null;
        if (type == null) {
            throw new DomainRuleViolation("PHOTO_TYPE", "A passport photograph is a JPEG or a PNG.", new DomainRuleViolation.Remedy("Choose a .jpg or .png file.", "You"));
        }
        byte[] bytes;
        try {
            bytes = java.util.Base64.getDecoder().decode(u.substring(comma + 1));
        } catch (IllegalArgumentException e) {
            throw new DomainRuleViolation("PHOTO_BYTES", "The photograph could not be read.", new DomainRuleViolation.Remedy("Choose the file again.", "You"));
        }
        if (bytes.length == 0 || bytes.length > MAX_PHOTO) {
            throw new DomainRuleViolation("PHOTO_SIZE", "A passport photograph is up to 2 MB.", new DomainRuleViolation.Remedy("Choose a smaller file.", "You"));
        }
        if (!isImage(bytes, type)) {
            throw new DomainRuleViolation("PHOTO_BYTES", "The file is not a photograph the portal can read.", new DomainRuleViolation.Remedy("Choose a .jpg or .png photograph.", "You"));
        }
        String store = repo.savePassport(id, bytes, type);
        return Map.of("saved", true, "bytes", bytes.length, "store", store);
    }

    /** the bytes are the image they say they are: a JPEG starts FF D8, a PNG with its eight-byte signature */
    private static boolean isImage(byte[] b, String type) {
        if ("image/jpeg".equals(type)) {
            return b.length > 3 && (b[0] & 0xFF) == 0xFF && (b[1] & 0xFF) == 0xD8;
        }
        return b.length > 8 && (b[0] & 0xFF) == 0x89 && b[1] == 'P' && b[2] == 'N' && b[3] == 'G';
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

    /** V492: the session a student's examinations stand in — the examination card's (a CCE or PG student's own calendar) — and
     *  the semester open in it */
    public String examSession(UUID id) {
        return ownCalendar(id) ? sessionFor(id) : session();
    }

    public int openSemester(UUID id, String session) {
        return repo.openSemester(id, session);
    }

    /** the current session, or the latest one the Bursar has charged for */
    public String session() {
        return repo.currentSession().orElseGet(() -> repo.sessionsWithCharges().stream().findFirst().orElseGet(Sessions::byDate));
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
        // V379: a CCE student stands in the CCE session — the route's, one behind undergraduate by default — never the undergraduate one
        if ("CCE".equals(s.entryMode())) {
            String cce = repo.routeSession("CCE");
            return s.entrySession() != null && (cce == null || s.entrySession().compareTo(cce) > 0) ? s.entrySession() : cce;
        }
        // V389: a postgraduate student stands in the School of Postgraduate Studies' session
        if ("POSTGRADUATE".equals(s.entryMode())) {
            String pg = repo.pgSession();
            return s.entrySession() != null && (pg == null || s.entrySession().compareTo(pg) > 0) ? s.entrySession() : pg;
        }
        // V733: an MBBS student who stands in a session of their own (people.study_session), one behind the University's
        String own = repo.ownSession(s.id());
        if (own != null) {
            return own;
        }
        String current = repo.currentSession().or(repo::latestRunSession).orElseGet(this::session);
        return s.entrySession() != null && s.entrySession().compareTo(current) > 0 ? s.entrySession() : current;
    }

    /** V389: a student on a calendar of their own — the Centre's (CCE) or the School of Postgraduate Studies' — V733: or an MBBS student
     *  standing in a session of their own: their examinations, permits and charges are that session's */
    private boolean ownCalendar(UUID id) {
        String mode = student(id).entryMode();
        return "CCE".equals(mode) || "POSTGRADUATE".equals(mode) || repo.ownSession(id) != null;
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
        // V724: where the record stands at the student portal's fee gate (OPEN, EXCEPTION, CLEARED, HELD_ACCEPTANCE_BALANCE,
        // HELD_FEES_NOT_AVAILABLE, HELD_FEES_UNPAID), read now in one query — GET /me is open to a held student, so the portal sends
        // them to the applicant dashboard even on a client-side navigation the X-Portal-Access header never reached
        v.put("portalAccess", jdbc.sql("SELECT finance.portal_access_state(:s)").param("s", id).query(String.class).single());
        v.put("programmeCode", s.programmeCode());
        v.put("programme", s.programme());
        v.put("faculty", s.facultyName());
        v.put("collegeCode", s.collegeCode());
        // V603: the dashboard the student lands on, from the programme and level on the record — the College's own student area
        // for a programme the College runs (MBBS), the University's for every other student, College of Health Sciences or not
        v.put("dashboard", repo.dashboard(id));
        // V606: whether the College's own student area is the student's at all (an MBBS student at 100 Level too) — its menu link
        v.put("collegeArea", repo.collegeArea(id));
        // V735: the Summer Semester page in the menu — a Summer set and not closed that the student may be eligible for, or one they took
        v.put("summerArea", repo.summerArea(id));
        // V752: the SIWES page in the menu — SIWES binds the student's current session (300 Level, a programme the Academic Office
        // configured, its period no longer a draft), or the student has registered SIWES before
        v.put("siwesArea", repo.siwesArea(id));
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
        // V380: a CCE student's windows are the CCE ones, on the CCE calendar's open semester
        windows.put("schoolFees", repo.windowFor(id, "SCHOOL_FEES_PAYMENT", session, null));
        windows.put("courseRegistration", repo.windowFor(id, "COURSE_REGISTRATION", session, repo.openSemester(id, session)));
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
            // V724: the fees not yet stated, not yet open to pay, or paid in part — and an acceptance fee balance owed (the fee revised
            // after part of it was paid: the acceptance is made, the screening done, the balance paid before the school fees) — stand
            // where SCHOOL_FEES_PENDING stands
            case "SCHOOL_FEES_PENDING", "SCHOOL_FEES_NOT_AVAILABLE", "SCHOOL_FEES_NOT_OPEN", "SCHOOL_FEES_PART_PAID", "ACCEPTANCE_BALANCE_PENDING" -> 3;
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
        // V379: the route, the study mode and, for CCE, the Centre, the CCE session beside undergraduate's and the expected completion
        ctx.putAll(repo.routeFacts(id));
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
        // V451: an open semester with no line stated for the student, while another semester's is — not "settled"
        out.put("unstatedSemesters", repo.unstatedSemesters(id, session));
        // V616: a spillover student is charged a semester's school fees only when they register a course in it — the page says so
        boolean spill = repo.isSpillover(id);
        out.put("spilloverBySemester", spill);
        // V637: the SP year, each semester's spillover fee and whether a course is registered in it, the carry-overs by semester
        out.put("spillover", spill ? repo.spilloverPanel(id, session) : null);
        // V651: a postgraduate student's stage and fresh/returning in the session, the fee lines read by them
        out.put("pg", repo.pgStage(id, session));
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
        // V454: short by under one naira counts as paid (finance.fee_short), so no semester is offered for kobo
        if (firstOutstanding.compareTo(BigDecimal.ONE) < 0) {
            firstOutstanding = BigDecimal.ZERO;
        }
        BigDecimal secondOutstanding = balance.subtract(firstOutstanding).max(BigDecimal.ZERO);
        out.put("firstSemesterOutstanding", firstOutstanding);
        out.put("secondSemesterOutstanding", secondOutstanding);
        /* registration is now gated per semester on that semester's school fees, paid in full (V149) */
        boolean inForce = repo.schemeInForce();
        out.put("clearsRegistration", repo.semesterCleared(id, session, repo.openSemester(id, session)));
        String schemeProblem = inForce ? null : "No clearance scheme is in force, so the examination card, results and transcript are not yet released. Course registration opens on this semester's school fees, paid in full.";
        out.put("schemeProblem", schemeProblem);
        out.put("references", repo.references(id));
        // V519: what the Bursary decided for school fees the student paid beyond a session's charge
        out.put("overpayments", repo.overpayments(id));
        // V379: a CCE student is pointed only to the sessions whose fee lines are theirs (never the full-time students' lines)
        out.put("sessions", ownCalendar(id) ? repo.sessionsWithChargesFor(id) : repo.sessionsWithCharges());   // V389: and a PG student
        out.put("window", repo.windowFor(id, "SCHOOL_FEES_PAYMENT", session, null));   // V288: open, scheduled, closed, or in the late period (V380: the CCE window for a CCE student)
        return out;
    }

    /** V528: the bank account a refund raised to the student is paid into — the database refuses another student's refund, a
     *  number that is not ten digits and an account already fixed by approval or payment */
    @Transactional
    public Map<String, Object> giveRefundAccount(UUID id, String reference, String bank, String accountName, String accountNumber) {
        repo.giveRefundAccount(id, reference, bank, accountName, accountNumber);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("reference", reference == null ? null : reference.trim().toUpperCase());
        out.put("overpayments", repo.overpayments(id));
        return out;
    }

    /** V533: the banks a refund is paid into */
    @Transactional(readOnly = true)
    public List<Map<String, Object>> banks() {
        return repo.banks();
    }

    /** the portal's school-fees window (V288): a new reference is generated only while it is open; one already generated is paid as before */
    private void assertFeesWindowOpen(UUID id, String session) {
        Map<String, Object> w = repo.windowFor(id, "SCHOOL_FEES_PAYMENT", session, null);
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
        assertFeesWindowOpen(id, ses);
        Map<String, Object> pos = repo.position(id, ses);
        BigDecimal balance = (BigDecimal) pos.get("balance");
        BigDecimal amt = amount == null ? balance : amount;
        String reference = repo.newReference(id, ses, amt, schoolFeesPurpose(id, ses, amt, pos));
        Map<String, Object> out = new LinkedHashMap<>(fees(id, ses));
        out.put("reference", reference);
        return out;
    }

    /** V654: a graduate's historical school fees, official amounts only */
    @Transactional(readOnly = true)
    public Map<String, Object> historicalFees(UUID id) {
        return repo.historicalFees(id);
    }

    /* ── V720: every outstanding school fee of the record, in one read ── */

    private static BigDecimal money(Object o) {
        return o == null ? BigDecimal.ZERO : o instanceof BigDecimal b ? b : new BigDecimal(String.valueOf(o));
    }

    private static String periodWords(Integer semester) {
        return semester == null ? "Entire session" : semester == 1 ? "First semester" : semester == 2 ? "Second semester" : "Third semester";
    }

    /** the status words the brief asks for: UNPAID, PARTIALLY_PAID, PAYMENT_PENDING, PAID — and the engine's own for a period being
     *  assessed, under review, or in credit */
    private static String statusOf(String engine, BigDecimal due, BigDecimal paid, BigDecimal balance, boolean pending) {
        if ("BEING_ASSESSED".equals(engine) || "REQUIRES_REVIEW".equals(engine) || "PENDING_APPROVAL".equals(engine)) return "BEING_ASSESSED";
        if ("CREDIT".equals(engine)) return "CREDIT";
        if (balance == null || balance.signum() <= 0) return "PAID";
        if (pending) return "PAYMENT_PENDING";
        return paid != null && paid.signum() > 0 ? "PARTIALLY_PAID" : "UNPAID";
    }

    /**
     * Every outstanding school fee of the student's record: each past session and semester as the historical engine assesses it
     * (finance.historical_account — the level of the session, a postgraduate stage's lines, approved assessments and waivers), and
     * the current session as the fees position reads it (finance.position, by semester) — never one engine standing in for the
     * other, and never the same session twice (V723). Each open, unexpired reference of a session is attached to one owed row
     * of it (PAYMENT_PENDING) and offered to pay; a past session takes one Pay now, on its first owed period (V723).
     * The summary counts what is owed across sessions. Nothing here is a new detection: the two engines are the authorities.
     */
    @Transactional(readOnly = true)
    public Map<String, Object> outstandingFees(UUID id) {
        String session = sessionFor(id);
        Map<String, Object> hist = repo.historicalFees(id);
        Map<String, Object> cur = fees(id, session);
        List<Map<String, Object>> open = repo.openSchoolFeeReferences(id);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("session", session);
        out.put("graduated", hist.get("graduated"));
        out.put("graduationSession", hist.get("graduationSession"));
        out.put("awaitingFinalClearance", hist.get("awaitingFinalClearance"));
        boolean onlinePayment = Boolean.TRUE.equals(hist.get("onlinePayment"));
        out.put("onlinePayment", onlinePayment);
        Map<String, Object> window = cur.get("window") instanceof Map<?, ?> w ? (Map<String, Object>) w : null;
        boolean windowOpen = window == null || window.get("state") == null || "OPEN".equals(String.valueOf(window.get("state")));
        out.put("windowOpen", windowOpen);
        String assessedFrom = repo.historicalStart();
        String entrySession = repo.entrySession(id);
        out.put("assessedFrom", assessedFrom);
        out.put("entrySession", entrySession);
        // V740: sessions are owed from the first year of study, not the admission session (the University's rule for admissions of
        // 2019/2020 to 2021/2022): nothing before the first year is "not yet assessed"
        String firstSession = repo.firstSession(id);
        out.put("firstSession", firstSession);
        out.put("unassessedBefore", assessedFrom != null && firstSession != null && firstSession.compareTo(assessedFrom) < 0);

        List<Map<String, Object>> rows = new ArrayList<>();
        // the past: the historical account, each period in the session's order. A session whose structure is one whole-session line is
        // assessed on its first semester with nothing on the others: shown as one row, "Entire session", the empty semesters left out
        // (the engine's amounts, the brief's words)
        List<Map<String, Object>> periods = (List<Map<String, Object>>) hist.get("periods");
        java.util.Set<String> wholeSessions = new java.util.HashSet<>();
        java.util.Set<String> pastSessions = new java.util.HashSet<>();
        for (Map<String, Object> p : periods) {
            String ses = String.valueOf(p.get("session"));
            pastSessions.add(ses);
            boolean others = periods.stream().filter(q -> ses.equals(String.valueOf(q.get("session"))) && !Integer.valueOf(1).equals(q.get("semester")))
                    .allMatch(q -> q.get("assessed") != null && money(q.get("assessed")).signum() == 0 && money(q.get("paid")).signum() == 0
                            && !"BEING_ASSESSED".equals(String.valueOf(q.get("status"))));
            boolean first = Integer.valueOf(1).equals(p.get("semester")) && p.get("assessed") != null && money(p.get("assessed")).signum() > 0;
            if (first && others) wholeSessions.add(ses);
        }
        for (Map<String, Object> p : periods) {
            String ses = String.valueOf(p.get("session"));
            Integer sem = p.get("semester") == null ? null : ((Number) p.get("semester")).intValue();
            if (wholeSessions.contains(ses) && !Integer.valueOf(1).equals(sem)) continue;
            Map<String, Object> row = new LinkedHashMap<>();
            row.put("kind", "PAST");
            row.put("session", ses);
            row.put("semester", wholeSessions.contains(ses) ? null : sem);
            row.put("period", wholeSessions.contains(ses) ? "Entire session" : periodWords(sem));
            row.put("level", p.get("level"));
            row.put("description", "School fees");
            row.put("due", p.get("assessed") == null ? null : money(p.get("assessed")));
            row.put("paid", money(p.get("paid")));
            row.put("balance", p.get("outstanding") == null ? null : money(p.get("outstanding")));
            row.put("credit", p.get("credit"));
            row.put("waived", p.get("waived"));
            row.put("engine", String.valueOf(p.get("status")));
            row.put("review", p.get("review"));
            row.put("door", "HISTORICAL");
            rows.add(row);
        }
        // the current session: what the position says is due, by semester — unless the session is already on the historical account
        // (V723: a graduate, or an approved graduand, whose award is of the session the University stands in reads it once, as the past)
        BigDecimal due = money(cur.get("due"));
        if (!pastSessions.contains(session) && Boolean.TRUE.equals(cur.get("stated")) && due.signum() > 0) {
            BigDecimal paid = money(cur.get("paid"));
            BigDecimal balance = money(cur.get("balance"));
            BigDecimal firstDue = repo.dueForSemester(id, session, 1);
            BigDecimal firstOut = money(cur.get("firstSemesterOutstanding"));
            BigDecimal secondOut = money(cur.get("secondSemesterOutstanding"));
            // V723: one row for the whole session only when the structure is one whole-session charge — a first semester charged alone
            // (a spillover student's semester, a second semester not yet stated) is said as the first semester
            boolean unstated = cur.get("unstatedSemesters") instanceof List<?> u && !u.isEmpty();
            boolean whole = firstDue.compareTo(due) >= 0 && !unstated && !Boolean.TRUE.equals(cur.get("spilloverBySemester"));
            List<Object[]> parts = new ArrayList<>();
            if (whole) {
                parts.add(new Object[] {null, due, paid.min(due), balance});
            } else if (firstDue.compareTo(due) >= 0) {
                parts.add(new Object[] {1, due, paid.min(due), balance});
            } else {
                parts.add(new Object[] {1, firstDue, paid.min(firstDue), firstOut});
                parts.add(new Object[] {2, due.subtract(firstDue), paid.subtract(firstDue).max(BigDecimal.ZERO).min(due.subtract(firstDue)), secondOut});
            }
            for (Object[] part : parts) {
                Integer sem = (Integer) part[0];
                Map<String, Object> row = new LinkedHashMap<>();
                row.put("kind", "CURRENT");
                row.put("session", session);
                row.put("semester", sem);
                row.put("period", periodWords(sem));
                row.put("level", repo.levelOf(id));
                row.put("description", "School fees");
                row.put("due", part[1]);
                row.put("paid", part[2]);
                row.put("balance", part[3]);
                row.put("engine", null);
                row.put("door", "CURRENT");
                rows.add(row);
            }
        }
        // V723: every open, unexpired reference of a session attached to one owed row of it — the row whose balance it matches first,
        // else the next owed row without one, oldest reference first — so two references on one session are both shown and counted
        Map<String, List<Map<String, Object>>> opens = new LinkedHashMap<>();
        for (int i = open.size() - 1; i >= 0; i--) {
            Map<String, Object> r = open.get(i);
            opens.computeIfAbsent(String.valueOf(r.get("session")), k -> new ArrayList<>()).add(r);
        }
        for (Map.Entry<String, List<Map<String, Object>>> e : opens.entrySet()) {
            List<Map<String, Object>> owed = rows.stream().filter(r -> e.getKey().equals(r.get("session")) && r.get("balance") != null && money(r.get("balance")).signum() > 0).toList();
            for (Map<String, Object> ref : e.getValue()) {
                BigDecimal amount = money(ref.get("amount"));
                Map<String, Object> target = owed.stream().filter(r -> r.get("reference") == null && money(r.get("balance")).compareTo(amount) == 0).findFirst()
                        .orElseGet(() -> owed.stream().filter(r -> r.get("reference") == null).findFirst().orElse(null));
                if (target != null) target.put("reference", ref);
            }
        }
        // the status in the brief's words, and the door: a past session takes one Pay now, on its first owed period, because the
        // historical door's payments settle the first semester first (the row may also pay the session's whole balance); the current
        // session's rows each pay their own figure through the fees page's door
        java.util.Set<String> firstOwedGiven = new java.util.HashSet<>();
        for (Map<String, Object> row : rows) {
            BigDecimal rowDue = row.get("due") == null ? null : money(row.get("due"));
            BigDecimal rowPaid = money(row.get("paid"));
            BigDecimal rowBal = row.get("balance") == null ? null : money(row.get("balance"));
            Map<String, Object> ref = (Map<String, Object>) row.get("reference");
            String status = statusOf((String) row.remove("engine"), rowDue, rowPaid, rowBal, ref != null);
            row.put("status", status);
            if (!row.containsKey("reference")) row.put("reference", null);
            boolean owes = rowBal != null && rowBal.signum() > 0 && !"BEING_ASSESSED".equals(status);
            String ses = String.valueOf(row.get("session"));
            boolean payable, first = false;
            if ("HISTORICAL".equals(row.get("door"))) {
                first = owes && firstOwedGiven.add(ses);
                payable = first && onlinePayment;
            } else {
                payable = owes && windowOpen;
            }
            row.put("payable", payable);
            row.put("payAmount", payable ? rowBal : null);
            if (payable && first) {
                BigDecimal sessionBalance = rows.stream().filter(r -> ses.equals(r.get("session")) && r.get("balance") != null).map(r -> money(r.get("balance")))
                        .filter(b -> b.signum() > 0).reduce(BigDecimal.ZERO, BigDecimal::add);
                row.put("sessionBalance", sessionBalance.compareTo(rowBal) > 0 ? sessionBalance : null);
            } else {
                row.put("sessionBalance", null);
            }
            row.put("payNote", owes && !payable && "HISTORICAL".equals(row.get("door")) && onlinePayment && !first
                    ? "Paid from the first semester's row: a session's payments settle its first semester first" : null);
        }
        out.put("rows", rows);
        // the summary: sessions and periods with a balance, the total, what the references shown on the rows would settle (each
        // attached to one owed row — a leftover reference of a settled session, or one past the rows owed, is not counted), what has
        // been paid
        BigDecimal outstanding = BigDecimal.ZERO, paidTotal = BigDecimal.ZERO, pending = BigDecimal.ZERO;
        java.util.Set<String> owingSessions = new java.util.TreeSet<>();
        int periodsOwed = 0;
        for (Map<String, Object> r : rows) {
            BigDecimal b = r.get("balance") == null ? BigDecimal.ZERO : money(r.get("balance"));
            paidTotal = paidTotal.add(money(r.get("paid")));
            if (b.signum() > 0) { outstanding = outstanding.add(b); owingSessions.add(String.valueOf(r.get("session"))); periodsOwed++; }
            if (r.get("reference") instanceof Map<?, ?> rf) pending = pending.add(money(((Map<String, Object>) rf).get("amount")));
        }
        Map<String, Object> summary = new LinkedHashMap<>();
        summary.put("sessions", owingSessions.size());
        summary.put("periods", periodsOwed);
        summary.put("items", periodsOwed);
        summary.put("outstanding", outstanding);
        summary.put("pending", pending);
        summary.put("paid", paidTotal);
        summary.put("beingAssessed", rows.stream().filter(r -> "BEING_ASSESSED".equals(r.get("status"))).count());
        out.put("summary", summary);
        return out;
    }

    /** V720: a reference for one outstanding fee — a past session through the historical door (any student; the database caps it at
     *  the balance), the current session through the fees page's own (its window, its position); the outstanding fees read again */
    @Transactional
    public Map<String, Object> outstandingReference(UUID id, String session, BigDecimal amount) {
        if (session == null || !session.matches("^[0-9]{4}/[0-9]{4}$")) {
            throw new DomainRuleViolation("HFA_PERIOD", "Choose the session to pay for.", new DomainRuleViolation.Remedy("Pick a row that shows a balance.", "You"));
        }
        // V723: routed by the row's door — a session on the historical account (every past session, and the current one for a
        // graduate whose award is of it) through the historical door; the current session otherwise through the fees page's own
        String reference;
        if (!repo.onHistoricalAccount(id, session) && session.equals(sessionFor(id))) {
            reference = String.valueOf(newReference(id, session, amount).get("reference"));
        } else {
            reference = repo.historicalReference(id, session, amount);
        }
        Map<String, Object> out = new LinkedHashMap<>(outstandingFees(id));
        out.put("reference", reference);
        return out;
    }

    /** V683: payment evidence a graduate submits for a past semester — the database checks the period (on their history, not settled),
     *  that one is open at a time, and the fields; it counts for nothing until the Bursary verifies the payment it shows */
    @Transactional
    public Map<String, Object> submitEvidence(UUID id, String session, int semester, BigDecimal amount, String paidOn, String channel, String reference, String note) {
        if (session == null || !session.matches("^[0-9]{4}/[0-9]{4}$")) {
            throw new DomainRuleViolation("HPE_PERIOD", "Choose the session and semester the payment was for.",
                    new DomainRuleViolation.Remedy("Pick a semester your school fees history lists.", "You"));
        }
        return repo.submitEvidence(id, session, semester, amount, evidenceDay(paidOn), channel, reference, note);
    }

    /** V683: a file added to the student's own evidence while it is with the Bursary */
    @Transactional
    public Map<String, Object> addEvidenceFile(UUID id, UUID evidence, String filename, String dataUrl) {
        repo.addEvidenceFile(evidence, id, filename, dataUrl);
        return Map.of("added", true);
    }

    /** V683: the evidence sent again with what the Bursary asked for */
    @Transactional
    public Map<String, Object> resubmitEvidence(UUID id, UUID evidence, BigDecimal amount, String paidOn, String channel, String reference, String note) {
        return Map.of("state", repo.resubmitEvidence(evidence, id, amount, evidenceDay(paidOn), channel, reference, note));
    }

    /** V683: the student withdraws their evidence while it is with the Bursary */
    @Transactional
    public Map<String, Object> withdrawEvidence(UUID id, UUID evidence, String reason) {
        return Map.of("state", repo.withdrawEvidence(evidence, id, reason));
    }

    /** V683: a file of the student's own evidence */
    @Transactional(readOnly = true)
    public java.util.Optional<ng.edu.moaum.portal.shared.FileObjects.Typed> evidenceFile(UUID id, UUID evidence, UUID file) {
        return repo.evidenceFile(evidence, id, file);
    }

    private static java.time.LocalDate evidenceDay(String day) {
        if (day == null || day.isBlank()) return null;
        try {
            return java.time.LocalDate.parse(day.trim());
        } catch (java.time.format.DateTimeParseException bad) {
            throw new DomainRuleViolation("HPE_DATE", "The day you paid is a date (YYYY-MM-DD).", new DomainRuleViolation.Remedy("Pick the day from the calendar.", "You"));
        }
    }

    /** V654: a reference for an approved historical balance — the database refuses anything but a graduate's balance owed */
    @Transactional
    public Map<String, Object> historicalReference(UUID id, String session, BigDecimal amount) {
        if (session == null || !session.matches("^[0-9]{4}/[0-9]{4}$")) {
            throw new DomainRuleViolation("HFA_PERIOD", "Choose the session to pay for.", new DomainRuleViolation.Remedy("Pick a session that shows a balance.", "You"));
        }
        String reference = repo.historicalReference(id, session, amount);
        Map<String, Object> out = new LinkedHashMap<>(repo.historicalFees(id));
        out.put("reference", reference);
        return out;
    }

    /** V635: an expired, unpaid reference of the student's made payable again — the same reference reopened for 24 hours while what
     *  it pays for is still owed, or (school fees, the GST fee owed now at less) a new one for what is owed; the database decides */
    @Transactional
    public Map<String, Object> renewReference(UUID id, String reference) {
        return repo.renewReference(id, reference);
    }

    /** V637: what a school-fees reference pays for, in words — for a spillover student "School fees 2025/2026 · spillover (SP1) · first
     *  semester" (or second, or both semesters, by the amount against what each semester still owes), so the reference, the receipt and
     *  the ledger's semester say so; every reader still reads it as school fees (LIKE 'School fees%') */
    private String schoolFeesPurpose(UUID id, String session, BigDecimal amount, Map<String, Object> pos) {
        String purpose = "School fees " + session;
        if (!repo.isSpillover(id)) return purpose;
        Map<String, Object> panel = repo.spilloverPanel(id, session);
        Object year = panel == null ? null : panel.get("year");
        BigDecimal paid = pos.get("paid") == null ? BigDecimal.ZERO : (BigDecimal) pos.get("paid");
        BigDecimal balance = pos.get("balance") == null ? BigDecimal.ZERO : (BigDecimal) pos.get("balance");
        BigDecimal first = repo.dueForSemester(id, session, 1).subtract(paid).max(BigDecimal.ZERO);
        if (first.compareTo(BigDecimal.ONE) < 0) first = BigDecimal.ZERO;
        BigDecimal second = balance.subtract(first).max(BigDecimal.ZERO);
        String which = first.signum() > 0
                ? (amount != null && amount.compareTo(first) > 0 && second.signum() > 0 ? "both semesters" : "first semester")
                : "second semester";
        return purpose + " · spillover" + (year == null ? "" : " (SP" + year + ")") + " · " + which;
    }

    @Transactional(readOnly = true)
    public Map<String, Object> receipt(UUID id, String reference) {
        Map<String, Object> r = repo.reference(id, reference).orElseThrow(() -> new NotFound("payment reference", reference));
        // V670: a payment archived for review has no receipt to print until the Bursary verifies it
        if (Boolean.TRUE.equals(r.get("archived"))) {
            throw new DomainRuleViolation("PAYMENT_UNDER_REVIEW", "Payment " + r.get("reference") + " is under review by the Bursary"
                    + (r.get("archive_ref") == null ? "" : " (" + r.get("archive_ref") + ")") + " and is not counted in your verified payments; its receipt is available again once it is verified.",
                    new DomainRuleViolation.Remedy("If you made this payment, keep your bank or gateway receipt; the Bursary may ask for it.", "Bursary"));
        }
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

    /** V655: the student's registration page — a course is never tied to a session: the classes of the student's level's courses and
     *  carry-overs that the session has none of yet are opened first, so the recommended list holds every course of the level whenever
     *  it was uploaded or bound (never in ICT Support's read-only view of the portal, which writes nothing) */
    @Transactional
    public Map<String, Object> registrationPage(UUID id, String session, int semester) {
        // only the session the student registers in now: the page names a session, and an older or later one opens nothing
        if (!ng.edu.moaum.portal.platform.SupportView.active() && semester >= 1 && semester <= 3 && session != null && session.equals(sessionFor(id))) {
            repo.openStudentClasses(id, session, semester);
        }
        return registrationView(id, session, semester);
    }

    /** V665: a record whose award is approved registers nothing for a session after its graduation session: the final clearance is under way */
    private void refuseAfterApprovedAward(UUID id, String session) {
        if (repo.awaitingFinalClearanceAfter(id, session)) {
            throw new DomainRuleViolation("REG_STUDENT_NOT_ELIGIBLE", "Course registration is unavailable: your award is approved and your final clearance is under way.",
                    new DomainRuleViolation.Remedy("Follow your final clearance on My Clearance; your record reads GRADUATED once the Bursar confirms it.", "Academic Office"));
        }
    }

    @Transactional(readOnly = true)
    public Map<String, Object> registrationView(UUID id, String session, int semester) {
        StudentPortalRepository.Student s = student(id);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("session", session);
        out.put("semester", semester);
        // V756: the semester in view is the student's Summer (the registration object, once made, says the same); a CCE or postgraduate
        // student's semester 3 is their own third semester
        out.put("summer", semester == 3 && Boolean.TRUE.equals(jdbc.sql("SELECT registration.is_summer_for(:s, :ses, :sem)")
                .param("s", id).param("ses", session).param("sem", semester).query(Boolean.class).single()));
        out.put("level", s.currentLevel());
        // V602: a graduated record registers nothing — no menu, no carry-over to add, the registration of the semester (if any) read as history;
        // V665: nor, for a session after the graduation session, does one whose award is approved and whose final clearance is under way
        boolean graduated = "GRADUATED".equals(s.status());
        if (graduated || repo.awaitingFinalClearanceAfter(id, session)) {
            out.put("closed", graduated
                    ? Map.of("code", "REG_STUDENT_GRADUATED",
                            "words", "Course registration is unavailable because this academic record has been graduated.",
                            "remedy", "Your registrations, results and payments stay on your record; transcripts, the certificate and clearance are on Documents and Graduation.")
                    : Map.of("code", "REG_STUDENT_AWARD_APPROVED",
                            "words", "Course registration is unavailable: your award is approved and your final clearance is under way.",
                            "remedy", "Follow your final clearance on My Clearance; your record reads GRADUATED once the Bursar confirms it."));
            out.put("limit", Map.of("min_units", 0, "max_units", 0, "basis", "CLOSED"));
            out.put("probation", Map.of());
            out.put("siwes", false);
            out.put("menu", List.of());
            out.put("outstanding", List.of());
            out.put("registration", repo.registration(id, session, semester).map(StudentPortalService::withEntries).orElse(null));
            out.put("loadKind", repo.loadKind(id, session, semester));
            out.put("fees", fees(id, session));
            out.put("status", s.status());
            out.put("addDropOpen", false);
            out.put("clears", false);
            out.put("openSemester", semester);
            return out;
        }
        // the SIWES / industrial-training semester carries exactly the SIWES units, not the 18-24 range — V752: as the unit rule reads it,
        // a SIWES student's Second Semester (registration.siwes_applies) first, V503's attachment semester for every programme not configured
        Map<String, Object> unitRule = new java.util.LinkedHashMap<>(repo.limit(id, s.currentLevel(), session, semester));
        Integer siwes = "SIWES".equals(unitRule.get("basis")) && unitRule.get("min_units") instanceof Number n ? n.intValue() : null;
        // on probation, the form's ceiling is the level's probation ceiling where the Registry has set one
        Map<String, Object> standing = repo.standing(s.id(), s.currentLevel());
        Map<String, Object> limit = siwes != null ? Map.of("min_units", siwes, "max_units", siwes, "basis", "SIWES") : unitRule;
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
        // V767: the gate of every GST/EPS course on the menu asked in one call, not once a course
        Map<String, String> gates = repo.gstGates(id, session, menu.stream()
                .filter(m -> "GST".equals(m.get("kind")) || "GST".equals(m.get("basis")))
                .map(m -> String.valueOf(m.get("course_code"))).collect(java.util.stream.Collectors.toCollection(java.util.LinkedHashSet::new)));
        for (Map<String, Object> m : menu) {
            if ("GST".equals(m.get("kind")) || "GST".equals(m.get("basis"))) {
                String gate = gates.get(String.valueOf(m.get("course_code")));
                m.put("gstLocked", gate != null);
                m.put("gstGate", gate);
            }
        }
        // V482: a course whose prerequisite the student has not passed says which; where the Academic Office enforces
        // prerequisites the engine refuses it, so the form locks it (a carry-over is never held to them)
        String prerequisiteMode = repo.prerequisiteMode();
        Map<String, String> unmet = repo.prerequisitesUnmet(id, menu.stream().filter(m -> !Boolean.TRUE.equals(m.get("carryover")))
                .map(m -> String.valueOf(m.get("course_code"))).distinct().toList());
        for (Map<String, Object> m : menu) {
            String u = Boolean.TRUE.equals(m.get("carryover")) ? null : unmet.get(String.valueOf(m.get("course_code")));
            if (u != null) {
                m.put("prerequisitesUnmet", u);
                m.put("prerequisiteLocked", "ENFORCED".equals(prerequisiteMode));
            }
        }
        out.put("prerequisiteMode", prerequisiteMode);
        out.put("menu", menu);
        // V504: the carry-overs as the published results state them (one not offered this semester says when it runs), and the
        // rule on adding courses beside the recommended list
        out.put("outstanding", repo.outstanding(id, session, semester));
        out.put("flex", repo.flexRule());
        out.put("codeFamily", repo.codeFamily(id));   // V402/V413: the cohort's code family, named on the screen
        out.put("specialisation", repo.specialisation(id));   // V483: a postgraduate student's specialisation, which decides some courses
        out.put("gst", repo.gstEntitlement(id, session));
        out.put("registration", repo.registration(id, session, semester).map(StudentPortalService::withEntries).orElse(null));
        // V597: what the minimum binds — a registration of carry-overs or of GST/EPS courses alone is submitted at whatever it carries;
        // V615: so is a spillover student's, whatever it holds (the cohort engine's spillover state, for the screen's meter)
        out.put("loadKind", repo.loadKind(id, session, semester));
        out.put("spilloverState", repo.academicPosition(id).map(p -> p.get("spillover_state")).orElse(null));
        // V674: a spillover student registers carry-overs only — the server enters every course of theirs as one; the page offers no fresh course
        out.put("carryOnly", repo.carryOnly(id, session));
        out.put("fees", fees(id, session));
        out.put("status", s.status());
        out.put("addDropOpen", repo.addDropOpen(id, session, semester));
        /* registration is gated per semester on that semester's fees (V149). A student who has paid
         * the whole session may register an earlier semester they never registered — the fee gate
         * clears it — so the screen offers each semester up to the open one and gates on the one in
         * view, not only the open one. */
        out.put("clears", repo.semesterCleared(id, session, semester));
        out.put("openSemester", repo.openSemester(id, session));
        out.put("registeredSemesters", repo.registeredSemesters(id, session));
        // V287 · the semester's door: open, closed, not yet open, or open early to the session's fresh students
        Map<String, Object> window = new LinkedHashMap<>();
        Map<String, Object> sm = repo.semesterWindow(id, session, semester);
        if (sm != null) window.putAll(sm);
        String gate = repo.registrationGate(id, session, semester);
        window.put("gate", gate);
        window.put("open", gate == null);
        // V752: the Second Semester is the student's SIWES semester, registered on the SIWES page
        boolean siwesSemester = semester == 2 && repo.siwesApplies(id, session);
        window.put("siwes", siwesSemester);
        window.put("fresh", session.equals(s.entrySession()));
        window.put("portal", repo.windowFor(id, "COURSE_REGISTRATION", session, semester));   // V288 (V380: the CCE window for a CCE student)
        window.put("cce", "CCE".equals(s.entryMode()));
        window.put("pg", "POSTGRADUATE".equals(s.entryMode()));   // V389
        out.put("window", window);
        // V491: how the registration is approved this semester, whether the student may reset it (and why not), its resets,
        // and what holds it for review under automatic approval
        Map<String, Object> rule = repo.approvalRule(session, semester);
        out.put("approval", rule);
        Map<String, Object> reset = new LinkedHashMap<>();
        // V752: the reset door's own word (reset()): a SIWES student's Second Semester passes the gate there — a reset clears what stands
        // in the SIWES course's way, carry-overs and deferred courses too — so whether it is allowed is reset_refusal's alone
        // (REG_RESET_SIWES once the SIWES course stands registered); every other semester keeps the gate's refusal first
        String why = gate != null && !siwesSemester ? gate : repo.resetRefusal(id, session, semester);
        reset.put("allowed", why == null);
        reset.put("why", why);
        reset.put("history", repo.resets(id, session, semester));
        out.put("reset", reset);
        out.put("reviewReason", repo.reviewReason(id, session, semester));
        return out;
    }

    /**
     * GST & EPS (V314): the fee stated for the student, the entitlement a confirmed payment grants, the references, the courses.
     * V366: whether a GST or EPS course requires the fee of them at all this session, and why — the courses are the ones that
     * concern them (the programme's offering at their level, a carryover, a registration), not every course of their level.
     */
    @Transactional(readOnly = true)
    public Map<String, Object> gst(UUID id, String session) {
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("session", session);
        out.put("eligibility", repo.gstEligibility(id, session));   // V767: the answer's requirement alone, not the whole answer
        out.put("entitlement", repo.gstEntitlement(id, session));
        // V643: the GST/EPS courses the registration page shows — the fee is paid for them though not yet owed
        out.put("payable", repo.gstPayable(id, session));
        // V690: the GST/EPS courses the student may add as a carry-over — the fee is paid before one is added
        out.put("carryPayable", repo.gstCarryPayable(id, session));
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
        assertWindowOpen(id, session, semester, false);
    }

    /** the door's word, and whether it stands open only because a SIWES student's Second Semester is shedding (V752): the gate sends
     *  that semester to the SIWES page, yet registration.siwes_register refuses while a course placed before SIWES bound the student is
     *  still on it (SIWES_OTHER_COURSES), so the drop and reset doors pass. What they may shed is the database's word, never judged here:
     *  ordinary courses, and carry-overs and deferred courses too, which wait for a later semester while no SIWES registration stands
     *  (registration.siwes_sheds, read by student_drop and student_reset); the add/drop calendar (student_drop) and the reset rule
     *  (reset_refusal: REG_RESET_SIWES once the SIWES course stands registered). Every other door keeps the gate's refusal. */
    private boolean assertWindowOpen(UUID id, String session, int semester, boolean shedding) {
        String gate = repo.registrationGate(id, session, semester);
        if (gate != null) {
            String mode = student(id).entryMode();
            // V752: a SIWES student's Second Semester is registered on the SIWES page (the gate reads registration.siwes_applies first)
            if (semester == 2 && repo.siwesApplies(id, session)) {
                if (shedding) {
                    return true;
                }
                throw new DomainRuleViolation("COURSE_REGISTRATION_CLOSED", gate,
                        new DomainRuleViolation.Remedy("Register your SIWES course on the SIWES page once its fee is paid; it is the only course of the semester.", "You"));
            }
            throw new DomainRuleViolation("COURSE_REGISTRATION_CLOSED", gate, "CCE".equals(mode)
                    // V380: a CCE student's door is the Centre's calendar and classes
                    ? new DomainRuleViolation.Remedy("The Centre opens the semester on the CCE calendar; the Directorate of ICT may also hold the CCE registration window.", "Centre for Continuing Education")
                    // V389: a PG student's door is the School's calendar and classes
                    : "POSTGRADUATE".equals(mode)
                    ? new DomainRuleViolation.Remedy("The School opens the semester on its calendar; the Directorate of ICT may also hold the postgraduate registration window.", "School of Postgraduate Studies")
                    : new DomainRuleViolation.Remedy("The Directorate of ICT opens the registration window; the Academic Office opens the semester on the calendar.", "Directorate of ICT"));
        }
        return false;
    }

    @Transactional
    public Map<String, Object> addCourse(UUID id, String session, int semester, UUID offering) {
        assertWindowOpen(id, session, semester);
        repo.addCourse(id, session, semester, offering);
        return registrationView(id, session, semester);
    }

    static final java.util.Set<String> COURSE_CATEGORIES = java.util.Set.of("CARRY_OVER", "GST", "CORE", "ELECTIVE");
    static final int COURSE_PAGE = 20;

    /** V504: the Add Other Course search — the courses a code or title, a department or a faculty finds, or (V507) without them the
     *  courses that concern the student, narrowed by the level and category; each judged by the engine for this student and semester:
     *  the category it is registered in and why, or why it is not available */
    @Transactional(readOnly = true)
    public Map<String, Object> searchCourses(UUID id, String session, int semester, String q, Integer level, String dept, String faculty,
                                             String category, int page) {
        StudentPortalRepository.Student s = student(id);
        // V602: a graduated record adds no course and no carry-over: the search is closed with the registration
        if ("GRADUATED".equals(s.status())) {
            throw new DomainRuleViolation("REG_STUDENT_NOT_ELIGIBLE", "Course registration is unavailable because this academic record has been graduated.",
                    new DomainRuleViolation.Remedy("Your registrations and results stay on your record; transcripts and the certificate are on Documents.", "Academic Office"));
        }
        refuseAfterApprovedAward(id, session);
        String term = q == null ? null : q.trim().replaceAll("\\s+", " ");
        if (term != null && term.isEmpty()) term = null;
        if (term != null && term.length() > 60) term = term.substring(0, 60);
        String cat = category == null || category.isBlank() ? null : category.trim().toUpperCase();
        if (cat != null && !COURSE_CATEGORIES.contains(cat)) {
            throw new DomainRuleViolation("REG_SEARCH_CATEGORY", "A course is CARRY_OVER, GST, CORE or ELECTIVE.",
                    new DomainRuleViolation.Remedy("Choose one of the categories, or none.", "Directorate of ICT"));
        }
        if (level != null && (level < 100 || level > 900 || level % 100 != 0)) {
            throw new DomainRuleViolation("REG_SEARCH_LEVEL", "A level is 100 to 900.", new DomainRuleViolation.Remedy("Choose a level, or none.", "Directorate of ICT"));
        }
        String d = dept == null || dept.isBlank() ? null : dept.trim().toUpperCase();
        String f = faculty == null || faculty.isBlank() ? null : faculty.trim().toUpperCase();
        int p = Math.max(0, Math.min(page, 50));
        List<Map<String, Object>> rows = repo.searchCourses(id, session, semester, term, level, d, f, cat, COURSE_PAGE, p * COURSE_PAGE);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("session", session);
        out.put("semester", semester);
        out.put("page", p);
        out.put("size", COURSE_PAGE);
        out.put("total", rows.isEmpty() ? 0 : ((Number) rows.get(0).get("total")).longValue());
        // V767: the gate of every GST/EPS course of the page that the student could add, asked in one call
        java.util.function.Predicate<Map<String, Object>> addableGst = r -> "GST".equals(r.get("kind")) && r.get("refusal") == null
                && !Boolean.TRUE.equals(r.get("on_registration"));
        Map<String, String> gates = repo.gstGates(id, session, rows.stream().filter(addableGst)
                .map(r -> String.valueOf(r.get("course_code"))).collect(java.util.stream.Collectors.toCollection(java.util.LinkedHashSet::new)));
        out.put("results", rows.stream().map(r -> {
            Map<String, Object> m = new LinkedHashMap<>(r);
            m.remove("total");
            // V512: a GST/EPS course the student could add is held while the GST fee they owe is not paid — said before they click
            if (addableGst.test(m)) {
                String gate = gates.get(String.valueOf(m.get("course_code")));
                if (gate != null) m.put("gstHeld", gate);
            }
            return m;
        }).toList());
        // V507: YOUR_COURSES — the programme's at every level, the University GST/EPS courses, the carry-overs; SEARCH — every course
        out.put("listed", term == null && d == null && f == null ? "YOUR_COURSES" : "SEARCH");
        out.put("flex", repo.flexRule());
        return out;
    }

    /** V504: the departments and faculties the search narrows to */
    @Transactional(readOnly = true)
    public Map<String, Object> searchFilters() {
        return Map.of("departments", repo.searchDepartments(), "categories", List.of("CARRY_OVER", "GST", "CORE", "ELECTIVE"));
    }

    /** V504: the student adds a course found by the search — to the draft while the registration is being made, or by add and drop
     *  once it is submitted or approved; the engine judges it (programme, level, semester, passed, awaited, prerequisites, GST fee)
     *  and refuses with its reason; the window and the student's standing are the API's to check first.
     *  V655: a course with no class in the session yet comes by its code; the engine judges it and opens its class, in this transaction,
     *  so an add refused afterwards (the GST fee, the unit ceiling) leaves no class behind */
    @Transactional
    public Map<String, Object> addOtherCourse(UUID id, String session, int semester, UUID offering, String courseCode) {
        Map<String, Object> one = addOne(id, session, semester, offering, courseCode);
        Map<String, Object> out = new LinkedHashMap<>(registrationView(id, session, semester));
        out.put("added", one.get("added"));
        out.put("offering", one.get("offering"));   // V655: the class the course was added by, opened now or not
        return out;
    }

    /** the add itself, in the caller's transaction (V663: shared by Add Other Course and the carry-over picker) */
    private Map<String, Object> addOne(UUID id, String session, int semester, UUID offering, String courseCode) {
        StudentPortalRepository.Student s = student(id);
        if (!List.of("ADMITTED", "ACTIVE", "PROBATION").contains(s.status())) {
            throw new DomainRuleViolation("REG_STUDENT_NOT_ELIGIBLE", "A student who is " + s.status().toLowerCase() + " does not register.",
                    new DomainRuleViolation.Remedy("Only an admitted, active or probation student may register.", "Academic Office"));
        }
        refuseAfterApprovedAward(id, session);
        assertWindowOpen(id, session, semester);
        if (offering == null) {
            if (courseCode == null || courseCode.isBlank()) {
                throw new DomainRuleViolation("REG_COURSE_UNKNOWN", "Choose the course to add.",
                        new DomainRuleViolation.Remedy("Pick a course from the search.", "Student"));
            }
            offering = repo.classToAdd(id, session, semester, courseCode.trim());
        }
        String status = repo.registration(id, session, semester).map(r -> String.valueOf(r.get("status"))).orElse("DRAFT");
        // V512: a GST/EPS carry-over the student asks to register is logged as attempted, and as held where the GST fee stops it
        Map<String, Object> g = repo.gstCourseOf(id, offering);
        boolean gst = g != null && Boolean.TRUE.equals(g.get("gst"));
        boolean carry = gst && Boolean.TRUE.equals(g.get("carry"));
        String code = g == null ? null : String.valueOf(g.get("code"));
        if (carry) logGstCourse(id, session, semester, code, true, "CARRY_OVER_REGISTRATION_ATTEMPTED");
        Object added;
        try {
            if (List.of("SUBMITTED", "APPROVED", "LOCKED").contains(status)) {
                repo.addCourse(id, session, semester, offering);   // add and drop: its own window, clearance and unit ceiling
                added = Map.of("added", true, "addDrop", true);
            } else {
                added = RESET_JSON.readValue(repo.addOther(id, session, semester, offering), Map.class);
            }
        } catch (RuntimeException e) {
            if (gst && heldOnTheGstFee(e)) {
                logGstCourse(id, session, semester, code, carry, "PAYMENT_REQUIRED_FOR_REGISTRATION");
                if (carry) logGstCourse(id, session, semester, code, true, "CARRY_OVER_REGISTRATION_BLOCKED");
            }
            throw e;
        }
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("added", added);
        out.put("offering", offering);
        return out;
    }

    /** V666: the carry-overs owed now, once each (registration.carryovers), and every attempt behind them and behind the courses
     *  cleared since (registration.carryover_history) */
    @Transactional(readOnly = true)
    public Map<String, Object> carryoverHistory(UUID id) {
        student(id);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("owed", repo.carryovers(id));
        out.put("history", repo.carryoverHistory(id));
        return out;
    }

    /** V663: the carry-over picker — every earlier course of the student, with what it is now (registration.carry_over_candidates):
     *  outstanding, no result, no record, awaited, cleared, already registered; selectable only as a carry-over the engine allows */
    @Transactional(readOnly = true)
    public Map<String, Object> carryOverCandidates(UUID id, String session, int semester) {
        StudentPortalRepository.Student s = student(id);
        Map<String, Object> who = new LinkedHashMap<>();
        who.put("name", (s.surname() == null ? "" : s.surname().toUpperCase()) + (s.otherNames() == null || s.otherNames().isBlank() ? "" : ", " + s.otherNames()));
        who.put("matricNo", s.matricNo() != null ? s.matricNo() : s.admissionNo());
        who.put("programme", s.programme());
        who.put("level", s.currentLevel());
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("student", who);
        out.put("session", session);
        out.put("semester", semester);
        List<Map<String, Object>> rows = repo.carryOverCandidates(id, session, semester);
        // V691: a GST/EPS course the GST fee holds is marked before it is ticked, with what the fee comes to — added, it would be refused
        // until the fee is paid (V690)
        List<String> gst = rows.stream().filter(r -> Boolean.TRUE.equals(r.get("selectable")) && List.of("GST", "EPS").contains(String.valueOf(r.get("course_group"))))
                .map(r -> String.valueOf(r.get("course_code"))).distinct().toList();
        Map<String, Object> hold = repo.gstCarryHolds(id, session, gst);
        @SuppressWarnings("unchecked")
        List<String> held = (List<String>) hold.get("held");
        for (Map<String, Object> r : rows) {
            boolean h = Boolean.TRUE.equals(r.get("selectable")) && held.contains(String.valueOf(r.get("course_code")));
            r.put("gst_held", h);
            r.put("gst_to_pay", h ? hold.get("toPay") : null);
        }
        out.put("rows", rows);
        // V682: a spillover student sees what the semester costs as soon as a course is ticked — every course they add is a carry-over,
        // and the semester's spillover fee is owed once one is on the registration (V616)
        out.put("fee", repo.spilloverSemesterQuote(id, session, semester));
        return out;
    }

    /** V663: the carry-overs the student ticked, added one by one by course id — each judged again by the engine and added in its own
     *  transaction, so one refused (the GST fee, the unit ceiling, the window) leaves the others added and is answered with its reason.
     *  A course the student does not owe, one cleared or already registered, is refused here before the engine is asked: the course
     *  is the server's to judge, never the screen's. Nothing earlier on the record is touched. */
    public Map<String, Object> addCarryOvers(UUID id, String session, int semester, List<UUID> courses) {
        TransactionTemplate read = new TransactionTemplate(ownTransaction.getTransactionManager());
        read.setReadOnly(true);
        List<Map<String, Object>> first = read.execute(t -> repo.carryOverCandidates(id, session, semester));
        // the semester's draft first, made as the page makes it: a carry-over a published result shows, taught this semester, is placed on
        // it by the draft itself — answered as added, never refused as "already added"
        boolean drafting = read.execute(t -> repo.registration(id, session, semester))
                .map(r -> !List.of("SUBMITTED", "APPROVED", "LOCKED").contains(String.valueOf(r.get("status")))).orElse(true);
        if (drafting) {
            try {
                ownTransaction.executeWithoutResult(t -> {
                    assertWindowOpen(id, session, semester);
                    repo.draft(id, session, semester);
                });
            } catch (RuntimeException e) {
                // the window or the student's standing: each course is refused below with the reason
            }
        }
        List<Map<String, Object>> rows = read.execute(t -> repo.carryOverCandidates(id, session, semester));
        Map<String, Map<String, Object>> before = new java.util.HashMap<>();
        for (Map<String, Object> r : first) before.put(String.valueOf(r.get("course_id")), r);
        Map<String, Map<String, Object>> byId = new java.util.HashMap<>();
        for (Map<String, Object> r : rows) byId.put(String.valueOf(r.get("course_id")), r);
        List<Map<String, Object>> results = new java.util.ArrayList<>();
        int added = 0;
        for (UUID c : new java.util.LinkedHashSet<>(courses)) {
            Map<String, Object> row = byId.get(c.toString());
            Map<String, Object> r = new LinkedHashMap<>();
            r.put("courseId", c);
            if (row == null) {
                r.put("added", false);
                r.put("code", "CARRY_NOT_YOURS");
                r.put("message", "This course is not among your earlier courses.");
                results.add(r);
                continue;
            }
            r.put("courseCode", row.get("shown_code"));
            r.put("title", row.get("title"));
            r.put("units", row.get("units"));
            r.put("level", row.get("level"));
            Map<String, Object> was = before.get(c.toString());
            if (was != null && Boolean.TRUE.equals(was.get("selectable")) && "ALREADY_REGISTERED".equals(row.get("status"))) {
                r.put("added", true);   // placed on the registration as its draft was made
                r.put("offering", row.get("offering_id"));
                added++;
                results.add(r);
                continue;
            }
            if (!Boolean.TRUE.equals(row.get("selectable"))) {
                r.put("added", false);
                r.put("code", "CARRY_" + row.get("status"));
                r.put("message", row.get("reason"));
                results.add(r);
                continue;
            }
            String code = String.valueOf(row.get("course_code"));
            String why = "Carry-over " + code + " added by the student" + (row.get("origin_session") == null ? "" : " (last registered " + row.get("origin_session") + ")")
                    + " — " + row.get("status");
            try {
                Map<String, Object> one = ownTransaction.execute(t -> {
                    repo.reason(why);
                    repo.declareCarryOvers();   // a no-record course of the programme comes as a declared carry-over here, nowhere else
                    return addOne(id, session, semester, null, code);
                });
                r.put("added", true);
                r.put("offering", one == null ? null : one.get("offering"));   // the class it was added by: the draft's selection keeps it
                added++;
            } catch (RuntimeException e) {
                String[] refusal = refusalOf(e);
                r.put("added", false);
                r.put("code", refusal[0]);
                r.put("message", refusal[1]);
            }
            results.add(r);
        }
        Map<String, Object> out = new LinkedHashMap<>(read.execute(t -> registrationView(id, session, semester)));
        out.put("results", results);
        out.put("addedCount", added);
        out.put("refusedCount", results.size() - added);
        return out;
    }

    /** a refusal in words: a rule's own code and message (DomainRuleViolation), or the database's "CODE: message", whatever wraps it */
    static String[] refusalOf(Throwable e) {
        for (Throwable t = e; t != null; t = t.getCause()) {
            if (t instanceof DomainRuleViolation d) return new String[] {d.code(), d.getMessage()};
        }
        for (Throwable t = e; t != null; t = t.getCause()) {
            if (t instanceof java.sql.SQLException q && q.getMessage() != null) {
                String m = q.getMessage().replaceFirst("^ERROR:\\s*", "").split("\\R", 2)[0].trim();
                java.util.regex.Matcher k = java.util.regex.Pattern.compile("^([A-Z][A-Z0-9_]{3,60}): (.+)$").matcher(m);
                return k.matches() ? new String[] {k.group(1), k.group(2)} : new String[] {"REFUSED", m};
            }
        }
        return new String[] {"REFUSED", e.getMessage() == null ? "The course could not be added." : e.getMessage()};
    }

    private void logGstCourse(UUID id, String session, int semester, String code, boolean carry, String what) {
        ownTransaction.executeWithoutResult(t -> repo.gstCourseEvent(id, session, semester, code, carry, what));
    }

    /** the database's GST fee refusal (GST_PAYMENT_REQUIRED, registration.gst_gate), anywhere in the cause chain */
    private static boolean heldOnTheGstFee(Throwable e) {
        for (Throwable t = e; t != null; t = t.getCause()) {
            if (t.getMessage() != null && t.getMessage().contains("GST_PAYMENT_REQUIRED")) return true;
        }
        return false;
    }

    @Transactional
    public Map<String, Object> dropCourse(UUID id, String session, int semester, UUID offering) {
        // V752: a SIWES student's Second Semester sheds here what was placed before SIWES bound the student — an ordinary course, or a
        // carry-over or deferred course, which waits for a later semester (the database's word) — never the SIWES course itself: the
        // programme's course or, after a remap, the one a SIWES registration was made on, whether or not one stands yet (the database
        // refuses the standing one too, SIWES_COURSE_KEPT)
        if (assertWindowOpen(id, session, semester, true) && repo.siwesCourse(id, offering)) {
            throw new DomainRuleViolation("SIWES_COURSE_KEPT", "This is your SIWES course; it is registered on the SIWES page and is not dropped here.",
                    new DomainRuleViolation.Remedy("The Academic Office or ICT Support undoes a SIWES registration.", "Academic Office"));
        }
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
        refuseAfterApprovedAward(id, session);
        assertWindowOpen(id, session, semester);
        UUID reg = repo.draft(id, session, semester);
        repo.choose(reg, offerings == null ? List.of() : offerings);
        return registrationView(id, session, semester);
    }

    @Transactional
    public Map<String, Object> submit(UUID id, String session, int semester) {
        assertWindowOpen(id, session, semester);
        UUID reg = repo.draft(id, session, semester);
        String result = repo.submit(reg);
        Map<String, Object> out = new LinkedHashMap<>(registrationView(id, session, semester));
        out.put("result", result);   // V491: 'approved' where the registration was approved on submission
        return out;
    }

    private static final tools.jackson.databind.ObjectMapper RESET_JSON = new tools.jackson.databind.ObjectMapper();

    /** V491: the student resets the semester's registration while the window is open and the rule allows it — the registration
     *  as it stood is kept on its reset record, the chosen courses are cleared (carryovers stay, but for a SIWES student's Second
     *  Semester before the SIWES course is registered: V752, they wait for a later semester), and it is a draft again */
    @Transactional
    public Map<String, Object> reset(UUID id, String session, int semester, String reason) {
        assertWindowOpen(id, session, semester, true);   // V752: a SIWES student's Second Semester resets what stands in the SIWES course's way
        String done = repo.reset(id, session, semester, reason == null || reason.isBlank() ? "Reset by the student to register again" : reason.trim());
        Map<String, Object> out = new LinkedHashMap<>(registrationView(id, session, semester));
        out.put("result", RESET_JSON.readValue(done, Map.class));
        return out;
    }

    /* ── results ── */

    @Transactional(readOnly = true)
    public Map<String, Object> results(UUID id) {
        StudentPortalRepository.Student s = student(id);
        List<Map<String, Object>> rows = repo.results(id);
        List<Map<String, Object>> gpa = repo.gpa(id);

        // the fee gate: a semester's marks are withheld until its fees clear — V667: semester by semester (finance.results_cleared:
        // the session's RESULTS rule, or else the fees up to that semester paid), so a balance on one semester never hides the results
        // of the semesters paid for. Redacted here on the server, not just hidden on the screen, so an unpaid student cannot read the
        // marks through the raw endpoint. No scheme in force means no gate.
        boolean scheme = repo.schemeInForce();
        Map<String, Boolean> clearedBySemester = new java.util.HashMap<>();
        java.util.function.BiFunction<String, Object, Boolean> cleared = (ses, sem) -> {
            int m = sem == null ? 1 : ((Number) sem).intValue();
            return !scheme || clearedBySemester.computeIfAbsent(ses + "|" + m, k -> repo.resultsCleared(id, ses, m));
        };
        // V754, V756: the sessions whose semester 3 was this student's Summer Semester, named the Summer semester on the statements
        // (a CCE or postgraduate student's semester 3 is their own third semester)
        List<String> summerSessions = jdbc.sql("SELECT sp.session FROM registration.summer_period sp WHERE registration.is_summer_for(:s, sp.session, 3) ORDER BY sp.session")
                .param("s", id).query(String.class).list();
        List<String> withheld = new java.util.ArrayList<>();
        List<Map<String, Object>> withheldSemesters = new java.util.ArrayList<>();
        for (Map<String, Object> row : rows) {
            String ses = String.valueOf(row.get("session"));
            if (!Boolean.TRUE.equals(cleared.apply(ses, row.get("semester")))) {
                row.put("ca", null); row.put("exam", null); row.put("total", null);
                row.put("grade", null); row.put("points", null);
                row.put("withheld", true);
                if (!withheld.contains(ses)) {
                    withheld.add(ses);
                }
                int m = row.get("semester") == null ? 1 : ((Number) row.get("semester")).intValue();
                // named only where something is published — a semester still in the approval chain holds nothing back
                if (Boolean.TRUE.equals(row.get("published"))
                        && withheldSemesters.stream().noneMatch(w -> ses.equals(w.get("session")) && Integer.valueOf(m).equals(w.get("semester")))) {
                    Map<String, Object> w = new LinkedHashMap<>();
                    w.put("session", ses);
                    w.put("semester", m);
                    w.put("summer", m == 3 && summerSessions.contains(ses));   // V756: the student's Summer, named so
                    w.put("outstanding", repo.semesterOutstanding(id, ses, m));
                    withheldSemesters.add(w);
                }
            } else {
                row.put("withheld", false);
            }
        }
        BigDecimal cgpa = null;
        for (Map<String, Object> g : gpa) {
            if (!Boolean.TRUE.equals(cleared.apply(String.valueOf(g.get("session")), g.get("semester")))) {
                g.put("gpa", null); g.put("cgpa", null);
                g.put("withheld", true);
            } else {
                g.put("withheld", false);
                // the cumulative as of the last semester released
                if (g.get("cgpa") != null) cgpa = (BigDecimal) g.get("cgpa");
            }
        }
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
        // V667: true when no published result is withheld; the semesters withheld are named with what is outstanding on each
        out.put("clearsResults", scheme ? withheldSemesters.isEmpty() : null);
        out.put("withheldSessions", withheld);
        out.put("withheldSemesters", withheldSemesters);
        out.put("summerSessions", summerSessions);   // V754, V756
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
        // V381: a CCE student's examination card is the CCE session's
        String session = ownCalendar(id) ? sessionFor(id) : session();   // V389: and a PG student's card is the School's session
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("session", session);
        boolean inForce = repo.schemeInForce();
        // V503: the Bursary's answer as the examination card and the GST & EPS permit read it (finance.clears_or_null): refused
        // (false) whenever the clearance refuses — also with no scheme in force when no fee is stated — and unknown (null) only
        // where no scheme says what a payment releases
        Boolean cleared = repo.clearsOrNull(id, session, "EXAMINATION");
        String schemeProblem = inForce ? null : "No clearance scheme is in force yet; the Bursar states it.";
        out.put("clearsExamination", cleared);
        out.put("schemeProblem", schemeProblem);
        List<Map<String, Object>> sessions = new ArrayList<>();
        for (Map<String, Object> x : repo.examSessions(id, session)) {
            Map<String, Object> e = new LinkedHashMap<>(x);
            List<Map<String, Object>> papers = new ArrayList<>();
            for (Map<String, Object> p : repo.docket(id, (UUID) x.get("id"))) {
                Map<String, Object> paper = new LinkedHashMap<>(p);
                paper.put("bar", repo.examBar(id, (UUID) p.get("offering_id")));   // V381: attendance below the Centre's minimum, where it bars
                papers.add(paper);
            }
            e.put("papers", papers);
            sessions.add(e);
        }
        out.put("examSessions", sessions);
        return out;
    }

    @Transactional(readOnly = true)
    public Map<String, Object> timetable(UUID id, int semester) {
        // V380: a CCE student's timetable and attendance are the CCE session's, and their attendance is the register's
        boolean cce = "CCE".equals(student(id).entryMode());
        String session = ownCalendar(id) ? sessionFor(id) : session();   // V389: a PG student's timetable is the School's session
        if (!cce) {
            return Map.of("session", session, "semester", semester, "slots", repo.timetable(id, session, semester), "attendance", repo.attendance(id, session, semester));
        }
        List<Map<String, Object>> att = repo.registerAttendance(id, session, semester);
        boolean shown = att.stream().allMatch(a -> !Boolean.FALSE.equals(a.get("show_students")));
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("session", session);
        out.put("semester", semester);
        out.put("slots", repo.timetable(id, session, semester));
        out.put("attendance", shown ? att : List.of());
        out.put("attendanceShown", shown);
        out.put("register", true);
        return out;
    }

    @Transactional(readOnly = true)
    public Map<String, Object> card(UUID id) {
        StudentPortalRepository.Student s = student(id);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("matricNo", s.matricNo());
        out.put("cards", repo.cards(id));
        Boolean cleared = repo.schemeInForce() ? repo.clears(id, session(), "ID_CARD") : null;
        out.put("clearsIdCard", cleared);
        // V699: the first card is issued on the matriculation number; a card after it waits on the replacement fee — whether a new card
        // would be one, the fee, whether it is paid, and the open reference to pay it
        out.put("replacement", repo.cardReplacement(id));
        return out;
    }

    @Transactional
    public Map<String, Object> cardReplacementFee(UUID id) {
        String reference = repo.cardReplacementReference(id);
        Map<String, Object> out = new LinkedHashMap<>(card(id));
        out.put("reference", reference);
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
