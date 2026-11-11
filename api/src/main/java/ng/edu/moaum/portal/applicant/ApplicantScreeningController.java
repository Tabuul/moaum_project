package ng.edu.moaum.portal.applicant;

import java.math.BigDecimal;
import java.sql.Types;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import jakarta.servlet.http.HttpServletRequest;

import ng.edu.moaum.portal.shared.FileObjects;
import ng.edu.moaum.portal.shared.DomainRuleViolation;
import ng.edu.moaum.portal.shared.NotFound;

import org.springframework.http.HttpStatus;
import org.springframework.http.ProblemDetail;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.Authentication;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.ErrorResponseException;

/**
 * The applicant's admission lifecycle (V269): the status and the tracker after the offer, and the online screening form —
 * the Registry's screening of fresh students done on the portal: personal data on the biodata catalogue, the institutions
 * attended, the O'Level results as declared beside JAMB's, the documents, the declaration; saved as a draft, submitted once
 * complete, read-only until an officer returns it. Everything under {@code /me} is the signed-in applicant's own.
 */
@RestController
class ApplicantScreeningController {

    private static final String APPLICANT = "hasAuthority('OFFICE_applicant')";
    private final FileObjects files;
    private final JdbcClient jdbc;
    private final AdmissionDocuments documents;

    ApplicantScreeningController(FileObjects files, JdbcClient jdbc, AdmissionDocuments documents) {
        this.jdbc = jdbc;
        this.files = files;
        this.documents = documents;
    }

    private UUID myApplication(Authentication a) {
        UUID account;
        try {
            account = UUID.fromString(a.getName());
        } catch (IllegalArgumentException e) {
            throw new NotFound("application", a.getName());
        }
        return jdbc.sql("SELECT id FROM admissions.application WHERE account_id = :acc").param("acc", account).query(UUID.class).optional()
                .orElseThrow(() -> new NotFound("application for account", account));
    }

    /* ── the lifecycle: where the applicant stands and what comes next ── */

    @GetMapping("/api/v1/applicant/me/admission")
    @PreAuthorize(APPLICANT)
    @Transactional(readOnly = true)
    Map<String, Object> admission(Authentication a) {
        UUID app = myApplication(a);
        Map<String, Object> out = new LinkedHashMap<>(jdbc.sql("SELECT * FROM admissions.admission_status(:a)").param("a", app).query().singleRow());
        out.put("tracker", jdbc.sql("SELECT admissions.admission_tracker(:a)::text").param("a", app).query(String.class).single());
        // V724: the entitlement carries fee_due, paid_total, balance, settled, payments, balance_due and the open reference beside what it said
        out.put("entitlement", jdbc.sql("SELECT * FROM admissions.acceptance_entitlement(:a)").param("a", app).query().singleRow());
        out.put("screeningRequired", jdbc.sql("SELECT admissions.screening_required(:a)").param("a", app).query(Boolean.class).single());
        boolean checkingDue = jdbc.sql("SELECT admissions.checking_due(:a)").param("a", app).query(Boolean.class).single();
        out.put("checkingDue", checkingDue);
        /* V295: Admission Status Checking — who may pay and check is the application, the window and the fee, never the decision */
        Map<String, Object> checking = jdbc.sql(ApplicantRepository.STATUS_CHECKING).param("a", app).query().listOfRows().stream().findFirst().orElse(Map.of());
        boolean visible = Boolean.TRUE.equals(checking.get("decisionVisible"));
        out.put("checking", checking);
        out.put("checks", jdbc.sql("SELECT checked_at, result, label FROM admissions.status_check WHERE application_id = :a ORDER BY checked_at DESC LIMIT 50").param("a", app).query().listOfRows());
        // V404: the fee status checking charges this application (the CCE route's for a CCE applicant)
        out.put("checkingFee", jdbc.sql("SELECT coalesce((SELECT k.fee FROM admissions.status_checking(:a) k), 0)").param("a", app).query(java.math.BigDecimal.class).single());
        out.put("checkingReference", jdbc.sql("SELECT reference FROM admissions.fee_reference WHERE application_id = :a AND kind = 'CHECKING' AND confirmed_at IS NULL AND expires_at > now() ORDER BY generated_at DESC LIMIT 1").param("a", app).query(String.class).optional().orElse(null));
        Map<String, Object> offer = jdbc.sql("""
                SELECT a.application_no, a.session, a.decision, a.decision_released_at, a.decision_basis, a.accepted_at, a.undertaking_at, a.acceptance_confirmed_at, a.cleared_at,
                       c.surname, c.other_names, c.jamb_reg_no, c.programme, c.entry_mode, c.entry_level,
                       p.code AS programme_code, p.category AS degree_type, f.name AS faculty, d.name AS department,
                       s.id AS student_id, s.admission_no, s.matric_no, s.matriculated_at, s.status AS student_status, s.current_level,
                       (SELECT q.to_programme FROM admissions.programme_change_request q WHERE q.application_id = a.id AND q.state = 'APPROVED' ORDER BY q.decided_at DESC LIMIT 1) AS changed_to,
                       (SELECT q.from_programme FROM admissions.programme_change_request q WHERE q.application_id = a.id AND q.state = 'APPROVED' ORDER BY q.decided_at DESC LIMIT 1) AS changed_from
                  FROM admissions.application a JOIN admissions.candidate c ON c.id = a.candidate_id
                  LEFT JOIN admissions.programme_by_name p_n ON p_n.name = c.programme LEFT JOIN ref.programme p ON p.code = p_n.code LEFT JOIN ref.faculty f ON f.code = p.faculty_code LEFT JOIN ref.department d ON d.code = p.dept_code
                  LEFT JOIN people.student s ON s.candidate_id = c.id
                 WHERE a.id = :a
                """).param("a", app).query().singleRow();
        if (!visible) {
            // the decision and what it names stay closed until the applicant may check it (V271, V295)
            for (String k : List.of("decision", "decision_basis", "decision_released_at", "programme", "programme_code", "degree_type", "faculty", "department", "changed_to", "changed_from")) offer.put(k, null);
        }
        out.put("offer", offer);
        return out;
    }

    /** the applicant checks their admission status (V271, V295): refused unless Admission Status Checking allows it — a valid
     *  application, checking open, the checking fee confirmed (422 ADMISSION_CHECKING_NOT_ELIGIBLE, _CLOSED, _FEE_UNPAID) — and
     *  kept, each time, with the status it returned; the first reading of an offer is stamped before the acceptance */
    @PostMapping("/api/v1/applicant/me/admission/checked")
    @PreAuthorize(APPLICANT)
    @Transactional
    Map<String, Object> checked(Authentication a) {
        UUID app = myApplication(a);
        jdbc.sql("SELECT admissions.admission_status_checked(:a)").param("a", app).query().listOfRows();
        return admission(a);
    }

    /* ── V724: the entry session's school fees, read and paid from the applicant dashboard before the student portal opens ── */

    /** the register row behind the applicant's account, once the Registry has brought them onto it: the student the session's fees are
     *  charged to (people.student through the candidate, never a duplicate) and the student's entry session — V724: the school fees are
     *  read and drawn for the session the student entered in (people.student.entry_session), as finance.portal_access_state and
     *  admissions.admission_status read them, never the application's session (an applicant of one session admitted into the next) */
    private Map<String, Object> myRegisterRow(Authentication a) {
        UUID account;
        try {
            account = UUID.fromString(a.getName());
        } catch (IllegalArgumentException e) {
            throw new NotFound("application", a.getName());
        }
        return jdbc.sql("""
                SELECT ap.id AS application_id, ap.session, s.id AS student_id, s.admission_no, s.entry_session
                  FROM admissions.application ap
                  LEFT JOIN people.student s ON s.candidate_id = ap.candidate_id AND s.duplicate_of IS NULL
                 WHERE ap.account_id = :acc
                 ORDER BY s.matriculated_at NULLS LAST, s.id
                 LIMIT 1
                """).param("acc", account).query().listOfRows().stream().findFirst()
                .orElseThrow(() -> new NotFound("application for account", account));
    }

    /** V724: what the school fees of the student's entry session say for the applicant now on the register — stated or not (nothing is
     *  charged at a guess), the payment window, due, paid, the balance, the first semester's due, a reference awaiting the bank — with
     *  the acceptance fee balance still owed (it comes first: the school fees are not drawn while it stands), the student portal's fee
     *  gate as it stands and where the record stands at it (finance.school_fee_state, admissions.acceptance_balance_of_student,
     *  finance.portal_access_state, read on every request, never cached); before the register: REGISTER_PENDING under the application's
     *  session and nothing else */
    @GetMapping("/api/v1/applicant/me/school-fees")
    @PreAuthorize(APPLICANT)
    @Transactional(readOnly = true)
    Map<String, Object> schoolFees(Authentication a) {
        Map<String, Object> me = myRegisterRow(a);
        Map<String, Object> out = new LinkedHashMap<>();
        if (me.get("student_id") == null) {
            out.put("onRegister", false);
            out.put("session", me.get("session"));
            out.put("state", "REGISTER_PENDING");
            return out;
        }
        UUID student = (UUID) me.get("student_id");
        String session = String.valueOf(me.get("entry_session"));
        Map<String, Object> sf = jdbc.sql("""
                SELECT f.state, f.due, f.paid, f.balance, f.paid_in_full, f.first_semester_cleared, f.instalments_paid, f.window_state, f.opens_at,
                       f.open_reference, f.open_amount, f.open_expires_at, array_to_string(f.unstated_semesters, ',') AS unstated_semesters,
                       coalesce(finance.due_for_semester(:s, :ses, 1), 0) AS due_first_semester
                  FROM finance.school_fee_state(:s, :ses) f
                """).param("s", student).param("ses", session).query().singleRow();
        out.put("onRegister", true);
        out.put("admissionNo", me.get("admission_no"));
        out.put("session", session);
        out.put("state", sf.get("state"));
        out.put("due", sf.get("due"));
        out.put("dueFirstSemester", sf.get("due_first_semester"));
        out.put("paid", sf.get("paid"));
        out.put("balance", sf.get("balance"));
        out.put("paidInFull", sf.get("paid_in_full"));
        out.put("firstSemesterCleared", sf.get("first_semester_cleared"));
        out.put("instalmentsPaid", sf.get("instalments_paid"));
        out.put("windowState", sf.get("window_state"));
        out.put("opensAt", sf.get("opens_at"));
        out.put("openReference", sf.get("open_reference"));
        out.put("openAmount", sf.get("open_amount"));
        out.put("openExpiresAt", sf.get("open_expires_at"));
        out.put("unstatedSemesters", semesters(sf.get("unstated_semesters")));
        // V724: the acceptance fee balance (a fee revised after part of it was paid) holds the school fees and the portal until it is paid
        BigDecimal acceptanceBalance = acceptanceBalance(student);
        out.put("acceptanceBalance", acceptanceBalance);
        out.put("acceptanceBalanceDue", acceptanceBalance.signum() > 0);
        Map<String, Object> g = jdbc.sql("SELECT enabled, clears_on, from_session FROM finance.portal_fee_gate WHERE id = 1").query().singleRow();
        Map<String, Object> gate = new LinkedHashMap<>();
        gate.put("enabled", g.get("enabled"));
        gate.put("clearsOn", g.get("clears_on"));
        gate.put("fromSession", g.get("from_session"));
        out.put("gate", gate);
        out.put("portalState", jdbc.sql("SELECT finance.portal_access_state(:s)").param("s", student).query(String.class).single());
        return out;
    }

    /** V724: the acceptance fee balance the student still owes over the candidate's offers (0 when none) */
    private BigDecimal acceptanceBalance(UUID student) {
        BigDecimal b = jdbc.sql("SELECT admissions.acceptance_balance_of_student(:s)").param("s", student).query(BigDecimal.class).single();
        return b == null ? BigDecimal.ZERO : b;
    }

    /** a naira figure as the notes read it: thousands separated, kobo only when there are any (₦10,000; ₦10,000.50) */
    private static String naira(BigDecimal amount) {
        return new java.text.DecimalFormat("#,##0.##").format(amount);
    }

    /** the semesters a fee line is not stated for, as the database lists them ("1,2" → [1, 2]; nothing → []) */
    private static List<Integer> semesters(Object joined) {
        List<Integer> out = new ArrayList<>();
        if (joined == null || String.valueOf(joined).isBlank()) {
            return out;
        }
        for (String part : String.valueOf(joined).split(",")) {
            if (!part.isBlank()) {
                out.add(Integer.parseInt(part.trim()));
            }
        }
        return out;
    }

    public record SchoolFeesReferenceIn(BigDecimal amount) {
    }

    /** V724: a payment reference for the school fees of the student's entry session, drawn for the student the applicant has become —
     *  the student's own reference (finance.new_reference: the window, the position and the amount are its to refuse, as
     *  SCHOOL_FEES_PAYMENT_CLOSED and the rest) and paid through the gateway from the applicant dashboard; the balance when no amount is
     *  given; 409 APPLICANT_NOT_ON_REGISTER before the Registry brings the applicant onto the register; 422 ACCEPTANCE_BALANCE_DUE while
     *  a balance of the acceptance fee stands (the brief: the acceptance fee first, then the school fees) */
    @PostMapping("/api/v1/applicant/me/school-fees/references")
    @PreAuthorize(APPLICANT)
    @Transactional
    Map<String, Object> schoolFeesReference(Authentication a, @RequestBody(required = false) SchoolFeesReferenceIn body) {
        Map<String, Object> me = myRegisterRow(a);
        if (me.get("student_id") == null) {
            String session = String.valueOf(me.get("session"));
            ProblemDetail problem = ProblemDetail.forStatusAndDetail(HttpStatus.CONFLICT,
                    "You are not yet on the register under an admission number; the " + session + " school fees are paid once the Registry brings you onto it.");
            problem.setTitle("Not yet on the register");
            problem.setProperty("code", "APPLICANT_NOT_ON_REGISTER");
            problem.setProperty("remedy", Map.of("message", "Wait for the Registry; your applicant dashboard says when the school fees open.", "office", "Registry"));
            throw new ErrorResponseException(HttpStatus.CONFLICT, problem, null);
        }
        UUID student = (UUID) me.get("student_id");
        String session = String.valueOf(me.get("entry_session"));
        BigDecimal acceptanceBalance = acceptanceBalance(student);
        if (acceptanceBalance.signum() > 0) {
            throw new DomainRuleViolation("ACCEPTANCE_BALANCE_DUE",
                    "Pay the acceptance fee balance of ₦" + naira(acceptanceBalance) + " first; the school fees follow it.",
                    new DomainRuleViolation.Remedy("Pay the balance on the Accept page of your applicant dashboard; you are never charged the full fee again.", "Bursary"));
        }
        BigDecimal amount = body == null ? null : body.amount();
        if (amount == null) {
            amount = jdbc.sql("SELECT f.balance FROM finance.school_fee_state(:s, :ses) f").param("s", student).param("ses", session).query(BigDecimal.class).single();
        }
        String reference = jdbc.sql("SELECT finance.new_reference(:s, :ses, :a, NULL)").param("s", student).param("ses", session).param("a", amount).query(String.class).single();
        Map<String, Object> r = jdbc.sql("SELECT reference, amount, expires_at FROM finance.payment_reference WHERE reference = :r").param("r", reference).query().singleRow();
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("reference", r.get("reference"));
        out.put("amount", r.get("amount"));
        out.put("expiresAt", r.get("expires_at"));
        return out;
    }

    /** the letter of provisional admission as a digital document (V275): issued on first request once the offer is accepted, a new
     *  version when the programme changed; the number, the verification code and the statement the PDF is drawn from — V724: refused
     *  with ACCEPTANCE_BALANCE_DUE while a balance of the acceptance fee stands */
    @GetMapping("/api/v1/applicant/me/letter")
    @PreAuthorize(APPLICANT)
    @Transactional
    Map<String, Object> letter(Authentication a, @RequestParam(required = false) String event) {
        return documents.letter(myApplication(a), event);
    }

    /* ── the document centre (V282): every document of the admission, with its state, in one place ── */

    @GetMapping("/api/v1/applicant/me/documents-centre")
    @PreAuthorize(APPLICANT)
    @Transactional(readOnly = true)
    Map<String, Object> documentsCentre(Authentication a) {
        return Map.of("rows", documents.centre(myApplication(a)));
    }

    @GetMapping("/api/v1/applicant/me/receipts/{reference}")
    @PreAuthorize(APPLICANT)
    @Transactional(readOnly = true)
    Map<String, Object> receipt(Authentication a, @PathVariable String reference) {
        return documents.receipt(myApplication(a), reference);
    }

    /* the same documents from the student side of the same account: the register knows the applicant they were */

    private static final String STUDENT = "hasAuthority('OFFICE_student')";

    private UUID studentApplication(Authentication a) {
        return documents.applicationOfStudent(UUID.fromString(a.getName()));
    }

    @GetMapping("/api/v1/me/admission-documents")
    @PreAuthorize(STUDENT)
    @Transactional(readOnly = true)
    Map<String, Object> studentDocuments(Authentication a) {
        return Map.of("rows", documents.centre(studentApplication(a)));
    }

    @GetMapping("/api/v1/me/admission-documents/letter")
    @PreAuthorize(STUDENT)
    @Transactional
    Map<String, Object> studentLetter(Authentication a, @RequestParam(required = false) String event) {
        return documents.letter(studentApplication(a), event);
    }

    @GetMapping("/api/v1/me/admission-documents/forms")
    @PreAuthorize(STUDENT)
    @Transactional
    Map<String, Object> studentForms(Authentication a, @RequestParam(required = false) String event) {
        return documents.forms(studentApplication(a), event);
    }

    @GetMapping("/api/v1/me/admission-documents/screening")
    @PreAuthorize(STUDENT)
    @Transactional(readOnly = true)
    Map<String, Object> studentScreening(Authentication a) {
        return form(studentApplication(a));
    }

    @GetMapping("/api/v1/me/admission-documents/receipts/{reference}")
    @PreAuthorize(STUDENT)
    @Transactional(readOnly = true)
    Map<String, Object> studentReceipt(Authentication a, @PathVariable String reference) {
        return documents.receipt(studentApplication(a), reference);
    }

    /* ── the screening form ── */

    private Map<String, Object> form(UUID app) {
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("required", jdbc.sql("SELECT admissions.screening_required(:a)").param("a", app).query(Boolean.class).single());
        out.put("form", jdbc.sql("SELECT * FROM admissions.screening_form WHERE application_id = :a").param("a", app).query().listOfRows().stream().findFirst().orElse(null));
        out.put("policy", jdbc.sql("SELECT sp.* FROM admissions.screening_policy sp JOIN admissions.application a ON a.session = sp.session WHERE a.id = :a").param("a", app).query().listOfRows().stream().findFirst().orElse(null));
        out.put("fields", jdbc.sql("SELECT field, section, label, tier, hint, wide, ord FROM ref.biodata_field ORDER BY CASE section WHEN 'personal' THEN 1 WHEN 'origin' THEN 2 WHEN 'contact' THEN 3 WHEN 'family' THEN 4 WHEN 'kin' THEN 5 WHEN 'education' THEN 6 WHEN 'health' THEN 7 ELSE 8 END, ord, label").query().listOfRows());
        out.put("answers", jdbc.sql("SELECT field, value FROM admissions.screening_answer WHERE application_id = :a").param("a", app).query().listOfRows());
        out.put("institutions", jdbc.sql("SELECT ord, name, from_year, to_year, certificate, award_year FROM admissions.screening_institution WHERE application_id = :a AND active ORDER BY ord").param("a", app).query().listOfRows());
        out.put("olevel", jdbc.sql("SELECT ord, exam_body, exam_number, exam_year, subject, grade FROM admissions.screening_olevel WHERE application_id = :a AND active ORDER BY ord").param("a", app).query().listOfRows());
        out.put("jambOlevel", jdbc.sql("""
                SELECT st.exam_body, st.exam_year, st.exam_number, g.subject, g.grade FROM admissions.application a JOIN admissions.candidate c ON c.id = a.candidate_id
                  JOIN admissions.olevel_sitting st ON st.session = c.session AND st.jamb_key = c.jamb_key JOIN admissions.olevel_grade g ON g.sitting_id = st.id WHERE a.id = :a ORDER BY st.ord, g.subject
                """).param("a", app).query().listOfRows());
        out.put("documents", jdbc.sql("SELECT id, kind, filename, content_type, bytes, uploaded_at, status, review_note, reviewed_at FROM admissions.application_document WHERE application_id = :a ORDER BY uploaded_at DESC").param("a", app).query().listOfRows());
        out.put("missing", jdbc.sql("SELECT * FROM admissions.screening_missing(:a)").param("a", app).query().listOfRows());
        Map<String, Object> prefill = jdbc.sql("""
                SELECT c.surname, c.other_names, c.jamb_reg_no, c.programme, c.entry_mode, a.session, a.application_no, r.sex, r.state_of_origin, r.lga, f.name AS faculty, d.name AS department,
                       (SELECT x.payload ->> 'dob' FROM admissions.attachment x WHERE x.candidate_id = c.id AND x.kind = 'DATE_OF_BIRTH' ORDER BY x.arrived_at DESC LIMIT 1) AS date_of_birth,
                       (SELECT platform.read_date(x.payload ->> 'dob')::text FROM admissions.attachment x WHERE x.candidate_id = c.id AND x.kind = 'DATE_OF_BIRTH' ORDER BY x.arrived_at DESC LIMIT 1) AS date_of_birth_iso,
                       acc.email, acc.phone, a.next_of_kin,
                       (SELECT x.payload ->> 'dataUrl' FROM admissions.attachment x WHERE x.session = c.session AND x.jamb_key = c.jamb_key AND x.kind = 'PASSPORT' AND jsonb_exists(x.payload, 'dataUrl') ORDER BY x.arrived_at DESC LIMIT 1) AS jamb_passport,
                       (SELECT x.object_id FROM admissions.attachment x WHERE x.session = c.session AND x.jamb_key = c.jamb_key AND x.kind = 'PASSPORT' AND x.object_id IS NOT NULL ORDER BY x.arrived_at DESC LIMIT 1) AS jamb_passport_object
                  FROM admissions.application a JOIN admissions.candidate c ON c.id = a.candidate_id JOIN admissions.applicant_account acc ON acc.id = a.account_id
                  LEFT JOIN admissions.caps_row r ON r.id = c.admitted_from
                  LEFT JOIN admissions.programme_by_name p_n ON p_n.name = c.programme LEFT JOIN ref.programme p ON p.code = p_n.code LEFT JOIN ref.faculty f ON f.code = p.faculty_code LEFT JOIN ref.department d ON d.code = p.dept_code
                 WHERE a.id = :a
                """).param("a", app).query().singleRow();
        prefill.put("jamb_passport", files.dataUrl((String) prefill.get("jamb_passport"), (UUID) prefill.remove("jamb_passport_object")));
        out.put("prefill", prefill);
        out.put("events", jdbc.sql("SELECT action, detail, actor_office, at FROM admissions.screening_event WHERE application_id = :a ORDER BY at DESC").param("a", app).query().listOfRows());
        out.put("changes", jdbc.sql("SELECT id, from_programme, to_programme, state, requested_at, decided_at, decision_note FROM admissions.programme_change_request WHERE application_id = :a ORDER BY requested_at DESC").param("a", app).query().listOfRows());
        out.put("status", jdbc.sql("SELECT * FROM admissions.admission_status(:a)").param("a", app).query().singleRow());
        // V280: the record the University screens, assembled from what it already holds, and the state of the generated forms
        out.put("facts", jdbc.sql("SELECT admissions.screening_facts(:a)::text").param("a", app).query(String.class).single());
        out.put("forms", jdbc.sql("SELECT * FROM admissions.screening_forms_state(:a)").param("a", app).query().singleRow());
        return out;
    }

    /** the official screening forms of a successful screening (V280): generated from the record, numbered under the screening number,
     *  a new version when the record changed; each opening is on the document's trail */
    @GetMapping("/api/v1/applicant/me/screening/forms")
    @PreAuthorize(APPLICANT)
    @Transactional
    Map<String, Object> forms(Authentication a, @RequestParam(required = false) String event) {
        return documents.forms(myApplication(a), event);
    }

    @GetMapping("/api/v1/applicant/me/screening")
    @PreAuthorize(APPLICANT)
    @Transactional
    Map<String, Object> screening(Authentication a) {
        UUID app = myApplication(a);
        // the record opens by itself when the acceptance settles (V280); a record accepted before that is opened on first sight
        boolean accepted = jdbc.sql("SELECT accepted_at IS NOT NULL FROM admissions.application WHERE id = :a").param("a", app).query(Boolean.class).single();
        if (accepted) {
            jdbc.sql("SELECT admissions.screening_open(:a)").param("a", app).query().singleRow();
        }
        return form(app);
    }

    public record SaveIn(Map<String, String> answers, List<Map<String, Object>> institutions, List<Map<String, Object>> olevel, String membership) {
    }

    @PutMapping("/api/v1/applicant/me/screening")
    @PreAuthorize(APPLICANT)
    @Transactional
    Map<String, Object> save(Authentication a, @RequestBody SaveIn body) {
        UUID app = myApplication(a);
        String answers = body.answers() == null ? null : Json.write(body.answers());
        String institutions = body.institutions() == null ? null : Json.write(body.institutions());
        String olevel = body.olevel() == null ? null : Json.write(body.olevel());
        jdbc.sql("SELECT admissions.screening_save(:a, :ans::jsonb, :inst::jsonb, :ol::jsonb, :m)").param("a", app)
                .param("ans", answers, Types.VARCHAR).param("inst", institutions, Types.VARCHAR).param("ol", olevel, Types.VARCHAR).param("m", body.membership(), Types.VARCHAR).query().singleRow();
        return form(app);
    }

    public record SubmitIn(boolean declaration) {
    }

    @PostMapping("/api/v1/applicant/me/screening/submit")
    @PreAuthorize(APPLICANT)
    @Transactional
    Map<String, Object> submit(Authentication a, @RequestBody SubmitIn body, HttpServletRequest request) {
        UUID app = myApplication(a);
        if (!body.declaration()) {
            throw new DomainRuleViolation("SCR_DECLARATION", "The declaration was not accepted.", new DomainRuleViolation.Remedy("Read the declaration and tick that you accept it.", "You"));
        }
        jdbc.sql("SELECT admissions.screening_submit(:a, true, :ip)").param("a", app).param("ip", request.getRemoteAddr(), Types.VARCHAR).query().singleRow();
        return form(app);
    }

    /** a tiny JSON writer for the save body: strings, numbers, booleans, nulls, maps and lists — nothing else arrives */
    static final class Json {
        static String write(Object o) {
            StringBuilder b = new StringBuilder();
            write(o, b);
            return b.toString();
        }

        @SuppressWarnings("unchecked")
        private static void write(Object o, StringBuilder b) {
            if (o == null) b.append("null");
            else if (o instanceof String s) b.append('"').append(s.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n").replace("\r", "\\r").replace("\t", "\\t")).append('"');
            else if (o instanceof Number || o instanceof Boolean) b.append(o);
            else if (o instanceof Map<?, ?> m) {
                b.append('{');
                boolean first = true;
                for (Map.Entry<Object, Object> e : ((Map<Object, Object>) m).entrySet()) {
                    if (!first) b.append(',');
                    first = false;
                    write(String.valueOf(e.getKey()), b);
                    b.append(':');
                    write(e.getValue(), b);
                }
                b.append('}');
            } else if (o instanceof List<?> l) {
                b.append('[');
                boolean first = true;
                for (Object x : l) {
                    if (!first) b.append(',');
                    first = false;
                    write(x, b);
                }
                b.append(']');
            } else write(String.valueOf(o), b);
        }
    }
}
