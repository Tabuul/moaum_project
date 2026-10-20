package ng.edu.moaum.portal.student;

import java.util.Map;
import java.util.Set;
import java.util.UUID;

import ng.edu.moaum.portal.shared.AuditContextHolder;
import ng.edu.moaum.portal.shared.DomainRuleViolation;
import ng.edu.moaum.portal.shared.NotFound;
import ng.edu.moaum.portal.studentportal.StudentPortalService;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * The full record (Student 360°, Oct 2026): one student's record as the institution holds it, read a section at a time from the
 * modules that own each part — nothing here is stored, computed afresh or written. Each section is its own call, so the page loads
 * the overview and reads a tab only when it is opened:
 *
 *   overview      identity, contact, numbers, the cohort engine's lifecycle position and recommendation, graduation, the session
 *   admission     the JAMB candidate, the applications, their fees, programme changes and transfers, admission documents
 *   progression   the level held session by session (enrolments, registrations) and every change of level, programme or status on
 *                 the audit chain and the cohort decisions — recorded, never filled in
 *   registrations every course registration with its courses, and every reset (V491) with what it held
 *   results       every result as published (a missing result is never a zero), the GPA of each semester, the courses owed
 *   finance       every payment reference (school fees and every other purpose), the school fees position of each session, refunds,
 *                 overpayment decisions, payments withdrawn, NELFUND — for the offices that read fees (StudentController.FEE_READERS)
 *   receipts/{r}  one confirmed payment's official receipt facts (StudentPortalService.receipt: the student's own receipt, with the
 *                 signed check code its QR carries) — only a reference of this student's, for the offices that read fees
 *   hostel, clearance, documents, support (ICT support tickets and actions), audit (the activity on the record)
 *
 * Every section is held to the office's bound on the student (StudentReach, the record's own rule).
 */
@RestController
@RequestMapping("/api/v1/student/students/{id}/full")
class StudentFullRecordController {

    private static final String READERS = "hasAnyAuthority('OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar',"
            + "'OFFICE_dvc','OFFICE_vc','OFFICE_records','OFFICE_dean','OFFICE_hod','OFFICE_exams',"
            + "'OFFICE_facultyexams','OFFICE_facultyofficer','OFFICE_ict','OFFICE_admin','OFFICE_super',"
            + "'OFFICE_bursar','OFFICE_studentaccounts','OFFICE_library','OFFICE_security','OFFICE_housing','OFFICE_hrm',"
            + "'OFFICE_audit','OFFICE_deputyaudit','OFFICE_lecturer',"
            + "'OFFICE_provost','OFFICE_collegesecretary','OFFICE_financecontroller','OFFICE_mbbscoordinator')";
    /** the offices that read the activity on a record: the Registry, the platform and audit */
    private static final Set<String> AUDIT_READERS = Set.of("registrar", "dregistrar", "records", "ict", "admin", "super", "audit", "deputyaudit");
    /** the offices that read a student's support tickets: the Registry, the academic offices and heads, the platform */
    private static final Set<String> SUPPORT_READERS = Set.of("registrar", "dregistrar", "records", "academic", "ict", "admin", "super", "dean", "hod",
            "facultyofficer", "vc", "dvc", "audit", "deputyaudit");
    /** the record's readers whose work touches one part of it read that part alone (besides the overview): a lecturer the
     *  registrations and results, the library and security the clearance (security the identity cards too), housing the hostel */
    private static final Map<String, Set<String>> LIMITED = Map.of(
            "lecturer", Set.of("overview", "registrations", "results"),
            "library", Set.of("overview", "clearance"),
            "security", Set.of("overview", "clearance", "documents"),
            "housing", Set.of("overview", "hostel", "clearance"),
            "hrm", Set.of("overview"));
    static final java.util.List<String> SECTIONS = java.util.List.of("overview", "admission", "progression", "registrations", "results", "finance",
            "hostel", "clearance", "documents", "support", "audit");

    private final JdbcClient jdbc;
    private final StudentReach reach;
    private final StudentPortalService portal;
    private final tools.jackson.databind.ObjectMapper json;

    StudentFullRecordController(JdbcClient jdbc, StudentReach reach, StudentPortalService portal, tools.jackson.databind.ObjectMapper json) {
        this.jdbc = jdbc;
        this.reach = reach;
        this.portal = portal;
        this.json = json;
    }

    private static String office() {
        return AuditContextHolder.current().map(c -> c.actorOffice()).orElse("");
    }

    /** the sections of the record this office reads */
    static java.util.List<String> sections(String office) {
        Set<String> limited = LIMITED.get(office);
        return SECTIONS.stream().filter(k -> limited == null || limited.contains(k))
                .filter(k -> !"finance".equals(k) || StudentController.FEE_READERS.contains(office))
                .filter(k -> !"support".equals(k) || SUPPORT_READERS.contains(office))
                .filter(k -> !"audit".equals(k) || AUDIT_READERS.contains(office))
                .toList();
    }

    private void need(String section) {
        if (!sections(office()).contains(section)) {
            throw new AccessDeniedException("This part of a student's record (" + section + ") is not read by this office.");
        }
    }

    /** who made an audit entry: the student themselves, the system, or the officer by name ({actor} in a section's SQL) */
    private static final String ACTOR = "CASE WHEN e.actor_office = 'student' THEN 'The student' WHEN e.actor_id IS NULL THEN 'The system' "
            + "ELSE helpdesk.person_name(e.actor_id) END";

    /** the student is within the office's bound (the record's own rule, which answers an unknown id as not found), and known */
    private void reach(UUID id) {
        reach.check(id);
        boolean known = jdbc.sql("SELECT EXISTS (SELECT 1 FROM people.student WHERE id = :s)").param("s", id).query(Boolean.class).single();
        if (!known) throw new NotFound("student", id);
    }

    private Map<String, Object> read(String sql, UUID id) {
        String text = jdbc.sql(sql.replace("{actor}", ACTOR)).param("s", id).query(String.class).single();
        return json.readValue(text, new tools.jackson.core.type.TypeReference<Map<String, Object>>() { });
    }

    /* ── the overview: who the student is, and where they stand ── */

    @GetMapping("/overview")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> overview(@PathVariable UUID id) {
        reach(id);
        Map<String, Object> out = read("""
                SELECT json_build_object(
                    'identity', (SELECT row_to_json(x) FROM (
                        SELECT s.id, s.surname, s.other_names, s.sex, s.date_of_birth, s.matric_no, s.admission_no, s.jamb_reg_no, s.status,
                               s.entry_mode, s.entry_session, s.entry_level, s.current_level, s.study_mode, s.centre_code, s.matriculated_at,
                               s.state_of_origin, s.programme_code, p.name AS programme, p.category, p.pg_award, d.code AS dept_code, d.name AS department,
                               f.code AS faculty_code, f.name AS faculty,
                               (SELECT a.application_no FROM admissions.application a WHERE a.candidate_id = s.candidate_id ORDER BY a.created_at DESC LIMIT 1) AS application_no,
                               (SELECT c.session FROM admissions.candidate c WHERE c.id = s.candidate_id) AS jamb_session,
                               -- V578: the programme the student was admitted to, where the record has moved since
                               (SELECT ap.name FROM admissions.candidate c JOIN ref.programme ap ON ap.code = c.programme
                                 WHERE c.id = s.candidate_id AND c.programme <> s.programme_code) AS admitted_programme
                          FROM people.student s
                          JOIN ref.programme p ON p.code = s.programme_code
                          LEFT JOIN ref.department d ON d.code = p.dept_code
                          LEFT JOIN ref.faculty f ON f.code = p.faculty_code
                         WHERE s.id = :s) x),
                    'contact', (SELECT row_to_json(x) FROM (SELECT c.email, c.phone, c.address, c.updated_at FROM people.student_contact c WHERE c.student_id = :s) x),
                    'session', policy.university_current_session(),
                    'semester', (SELECT m.number FROM policy.semester m WHERE m.session = policy.university_current_session() AND m.state = 'OPEN' ORDER BY m.number LIMIT 1),
                    'position', (SELECT row_to_json(x) FROM (
                        SELECT ap.jamb_year, ap.matric_year, ap.effective_cohort, ap.cohort_source, ap.duration_years, ap.final_level, ap.expected_completion,
                               ap.current_session, ap.spillover_years, ap.spillover_state, ap.classification, ap.registered_current, ap.last_session,
                               ap.graduation_state, ap.graduation_session, ap.computed_at
                          FROM people.academic_position ap WHERE ap.student_id = :s) x),
                    'lifecycle', (SELECT row_to_json(x) FROM (
                        SELECT lr.recommendation, lr.candidate_basis, lr.confidence, lr.confidence_reasons, lr.explanation, lr.completion, lr.review_state, lr.batch_ref
                          FROM people.lifecycle_recommendation lr WHERE lr.student_id = :s) x),
                    'graduand', (SELECT row_to_json(x) FROM (
                        SELECT g.session, g.cgpa, g.award, g.unmet, g.senate_state, g.senate_minute FROM records.graduand g WHERE g.student_id = :s
                         ORDER BY (g.senate_state = 'APPROVED') DESC, g.session DESC LIMIT 1) x),
                    'registrations', (SELECT count(*) FROM registration.course_registration r WHERE r.student_id = :s),
                    'clearances', (SELECT coalesce(json_agg(x ORDER BY x.started_at DESC), '[]'::json) FROM (
                        SELECT q.workflow, q.reference, q.started_at, q.completed_at, q.cancelled_at FROM clearance.process q WHERE q.student_id = :s) x),
                    'hostel', (SELECT row_to_json(x) FROM (
                        SELECT a.session, a.state, a.reference_no FROM hostel.allocation a WHERE a.student_id = :s ORDER BY a.session DESC LIMIT 1) x)
                )::text
                """, id);
        // the summary cards: the standing the results engine pronounces, and — for the offices that read fees — this session's
        // school fees position alone (one call, never the student's payment history)
        out.put("standing", jdbc.sql("SELECT row_to_json(x)::text FROM assessment.student_standing(:s) x LIMIT 1").param("s", id).query(String.class)
                .optional().map(t -> json.readValue(t, Map.class)).orElse(null));
        if (StudentController.FEE_READERS.contains(office()) && out.get("session") != null) {
            out.put("fees", jdbc.sql("SELECT row_to_json(x)::text FROM finance.payment_position(:s, :ses, NULL) x").param("s", id).param("ses", out.get("session"))
                    .query(String.class).optional().map(t -> json.readValue(t, Map.class)).orElse(null));
        }
        // a lecturer, the library, security, housing and HR read who the student is, not how to reach them
        if (LIMITED.containsKey(office())) out.remove("contact");
        out.put("sections", sections(office()));
        return out;
    }

    /* ── admission: the candidate, the applications and their fees, programme changes and transfers ── */

    @GetMapping("/admission")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> admission(@PathVariable UUID id) {
        need("admission");
        reach(id);
        return read("""
                WITH s AS (SELECT * FROM people.student WHERE id = :s)
                SELECT json_build_object(
                    'student', (SELECT row_to_json(x) FROM (SELECT s.entry_mode, s.entry_session, s.entry_level, s.admission_no, s.jamb_reg_no, s.programme_code,
                                                                   s.matriculated_at FROM s) x),
                    'candidate', (SELECT row_to_json(x) FROM (
                        SELECT c.session, c.jamb_reg_no, c.admission_no, c.programme, c.entry_mode, c.entry_level, c.offer_state, c.utme_aggregate,
                               cr.aggregate AS caps_aggregate, cr.jamb_code AS caps_programme_code, cr.state_of_origin AS caps_state, cr.lga AS caps_lga
                          FROM admissions.candidate c LEFT JOIN admissions.caps_row cr ON cr.id = c.admitted_from
                         WHERE c.id = (SELECT candidate_id FROM s)) x),
                    'applications', (SELECT coalesce(json_agg(x ORDER BY x.created_at), '[]'::json) FROM (
                        SELECT a.application_no, a.session, a.created_at, a.submitted_at, a.fee_confirmed_at, a.screening_score, a.score_released_at,
                               a.decision, a.decided_at, a.decision_released_at, a.checking_confirmed_at, a.acceptance_confirmed_at, a.accepted_at,
                               a.declined_at, a.cleared_at, a.lapsed_at
                          FROM admissions.application a WHERE a.candidate_id = (SELECT candidate_id FROM s)) x),
                    'fees', (SELECT coalesce(json_agg(x ORDER BY x.generated_at), '[]'::json) FROM (
                        SELECT f.kind, f.reference, f.amount, f.generated_at, f.confirmed_at, f.channel, f.receipt_no
                          FROM admissions.fee_reference f JOIN admissions.application a ON a.id = f.application_id
                         WHERE a.candidate_id = (SELECT candidate_id FROM s)) x),
                    'programmeChanges', (SELECT coalesce(json_agg(x ORDER BY x.requested_at), '[]'::json) FROM (
                        SELECT r.session, r.kind, r.from_programme_code, r.from_programme, r.to_programme_code, r.to_programme, r.state, r.requested_at,
                               r.decided_at, r.decided_office, r.decision_note, r.reason_code, r.admission_stage
                          FROM admissions.programme_change_request r WHERE r.candidate_id = (SELECT candidate_id FROM s)) x),
                    'transfers', (SELECT coalesce(json_agg(x ORDER BY x.applied_at), '[]'::json) FROM (
                        SELECT t.session, t.from_programme_code, fp.name AS from_programme, t.from_level, t.to_programme_code, tp.name AS to_programme,
                               t.recommended_level, t.state, t.reason, t.applied_at, t.senate_at, t.senate_note, t.effected_at
                          FROM people.transfer_application t
                          LEFT JOIN ref.programme fp ON fp.code = t.from_programme_code LEFT JOIN ref.programme tp ON tp.code = t.to_programme_code
                         WHERE t.student_id = :s) x),
                    'documents', (SELECT coalesce(json_agg(x ORDER BY x.kind), '[]'::json) FROM (
                        SELECT d.kind, d.detail, d.source, d.received_on, d.status FROM people.document d WHERE d.student_id = :s) x),
                    -- V578: every placement the record has had — the admission, transfers, record moves, swaps, other changes on the chain
                    'programmeHistory', (SELECT coalesce(json_agg(h ORDER BY h.at NULLS FIRST), '[]'::json) FROM people.programme_history(:s) h)
                )::text
                """, id);
    }

    /* ── progression: the level held session by session, and every change of level, programme or status as recorded ── */

    @GetMapping("/progression")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> progression(@PathVariable UUID id) {
        need("progression");
        reach(id);
        return read("""
                SELECT json_build_object(
                    'held', (SELECT coalesce(json_agg(x ORDER BY x.session, x.semester NULLS FIRST), '[]'::json) FROM (
                        SELECT e.session, NULL::int AS semester, e.level, 'ENROLMENT' AS source, e.mode AS detail, e.enrolled_at AS at
                          FROM people.enrolment e WHERE e.student_id = :s
                        UNION ALL
                        SELECT r.session, r.semester, r.level, 'REGISTRATION', r.status, coalesce(r.submitted_at, r.approved_at)
                          FROM registration.course_registration r WHERE r.student_id = :s) x),
                    -- every change of the record's level, programme or status the audit chain holds (the whole row before and after)
                    'changes', (SELECT coalesce(json_agg(x ORDER BY x.at), '[]'::json) FROM (
                        SELECT e.occurred_at AS at, e.actor_office, {actor} AS actor, e.reason,
                               nullif(e.before_state->>'current_level', '')::int AS previous_level, nullif(e.after_state->>'current_level', '')::int AS new_level,
                               e.before_state->>'programme_code' AS previous_programme, e.after_state->>'programme_code' AS new_programme,
                               e.before_state->>'status' AS previous_status, e.after_state->>'status' AS new_status
                          FROM audit.entries e
                         WHERE e.subject_type = 'people.student' AND e.subject_id = :s AND e.action = 'UPDATE'
                           AND (e.before_state->>'current_level' IS DISTINCT FROM e.after_state->>'current_level'
                                OR e.before_state->>'programme_code' IS DISTINCT FROM e.after_state->>'programme_code'
                                OR e.before_state->>'status' IS DISTINCT FROM e.after_state->>'status')) x),
                    'decisions', (SELECT coalesce(json_agg(x ORDER BY x.decided_at), '[]'::json) FROM (
                        SELECT d.decided_at, d.rule, d.previous_status, d.final_status, d.previous_level, d.new_level, d.previous_cohort, d.effective_cohort,
                               d.reason, d.batch_ref, d.actor_office, helpdesk.person_name(d.officer) AS officer
                          FROM people.cohort_decision d WHERE d.student_id = :s) x),
                    'statuses', (SELECT coalesce(json_agg(x ORDER BY x.effective_on, x.id), '[]'::json) FROM (
                        SELECT c.id, c.from_status, c.to_status, c.instrument, c.effective_on, c.expires_on, c.reason FROM people.status_change c WHERE c.student_id = :s) x),
                    'deferments', (SELECT coalesce(json_agg(x ORDER BY x.created_at), '[]'::json) FROM (
                        SELECT d.reference, d.kind, d.session, d.semester, d.state, d.return_session, d.return_semester, d.created_at
                          FROM people.deferment d WHERE d.student_id = :s) x),
                    'position', (SELECT row_to_json(x) FROM (
                        SELECT ap.entry_session, ap.effective_cohort, ap.cohort_source, ap.entry_level, ap.final_level, ap.duration_years, ap.expected_completion,
                               ap.current_session, ap.current_level, ap.computed_level, ap.spillover_years, ap.spillover_state, ap.deferred_sessions
                          FROM people.academic_position ap WHERE ap.student_id = :s) x)
                )::text
                """, id);
    }

    /* ── course registration: every registration with its courses, and every reset ── */

    @GetMapping("/registrations")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> registrations(@PathVariable UUID id) {
        need("registrations");
        reach(id);
        return read("""
                SELECT json_build_object(
                    'registrations', (SELECT coalesce(json_agg(x ORDER BY x.session DESC, x.semester DESC), '[]'::json) FROM (
                        SELECT r.id, r.session, r.semester, r.level, r.status, r.submitted_at, r.approved_at, r.approval_mode, r.returned_comment,
                               helpdesk.person_name(r.approved_by) AS approved_by,
                               (SELECT coalesce(sum(e.units), 0) FROM registration.entry e WHERE e.registration_id = r.id AND e.status IN ('REGISTERED','APPROVED')) AS units,
                               (SELECT coalesce(json_agg(c ORDER BY c.course_code), '[]'::json) FROM (
                                   SELECT o.course_code, coalesce(o.title, cc.title) AS title, e.units, e.entry_type, e.status, e.added_as
                                     FROM registration.entry e JOIN catalogue.offering o ON o.id = e.offering_id
                                     LEFT JOIN catalogue.course cc ON cc.code = o.course_code
                                    WHERE e.registration_id = r.id) c) AS courses
                          FROM registration.course_registration r WHERE r.student_id = :s) x),
                    'resets', (SELECT coalesce(json_agg(x ORDER BY x.reset_at DESC), '[]'::json) FROM (
                        SELECT z.session, z.semester, z.level, z.previous_status, z.previous_approval_mode, z.courses, z.course_count, z.units, z.kept,
                               z.reason, z.source, z.reset_office, helpdesk.person_name(z.reset_by) AS reset_by, z.reset_at
                          FROM registration.registration_reset z WHERE z.student_id = :s) x)
                )::text
                """, id);
    }

    /* ── results: as published; a missing result is never a zero ── */

    @GetMapping("/results")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> results(@PathVariable UUID id) {
        need("results");
        reach(id);
        return read("""
                SELECT json_build_object(
                    'results', (SELECT coalesce(json_agg(x), '[]'::json) FROM assessment.student_results(:s) x),
                    'semesters', (SELECT coalesce(json_agg(x ORDER BY x.session, x.semester), '[]'::json) FROM assessment.student_gpa(:s) x),
                    'owed', (SELECT coalesce(json_agg(x ORDER BY x.course_code), '[]'::json) FROM registration.carryovers(:s) x),
                    'standing', (SELECT row_to_json(x) FROM assessment.student_standing(:s) x LIMIT 1)
                )::text
                """, id);
    }

    /* ── finance: every payment reference, each session's school fees, refunds, overpayments, withdrawals, NELFUND ── */

    @GetMapping("/finance")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> finance(@PathVariable UUID id) {
        need("finance");
        reach(id);
        return read("""
                WITH refs AS MATERIALIZED (
                    SELECT r.id, r.session, r.reference, r.purpose, r.amount, r.generated_at, r.expires_at, r.confirmed_at, r.channel, r.receipt_no, r.note,
                           CASE WHEN r.confirmed_at IS NOT NULL THEN finance.payment_term(r.id) END AS term,
                           CASE WHEN r.confirmed_at IS NOT NULL THEN 'PAID' WHEN r.expires_at < now() THEN 'EXPIRED' ELSE 'PENDING' END AS status,
                           r.purpose LIKE 'School fees%' AS school_fees,
                           ge.gateway, ge.gateway_ref, ge.outcome AS gateway_outcome
                      FROM finance.payment_reference r
                      LEFT JOIN LATERAL (SELECT e.gateway, e.gateway_ref, e.outcome FROM finance.gateway_event e
                                          WHERE e.reference = r.reference ORDER BY e.received_at DESC LIMIT 1) ge ON true
                     WHERE r.student_id = :s),
                sessions AS (SELECT DISTINCT r.session FROM refs r WHERE r.school_fees AND r.session ~ '^[0-9]{4}/[0-9]{4}$'
                             UNION SELECT e.session FROM people.enrolment e WHERE e.student_id = :s)
                SELECT json_build_object(
                    'payments', (SELECT coalesce(json_agg(x ORDER BY coalesce(x.confirmed_at, x.generated_at) DESC), '[]'::json) FROM refs x),
                    'summary', (SELECT json_build_object(
                                    'count', count(*), 'paid', count(*) FILTER (WHERE status = 'PAID'), 'pending', count(*) FILTER (WHERE status = 'PENDING'),
                                    'expired', count(*) FILTER (WHERE status = 'EXPIRED'),
                                    'amountPaid', coalesce(sum(amount) FILTER (WHERE status = 'PAID'), 0),
                                    'schoolFeesPaid', coalesce(sum(amount) FILTER (WHERE status = 'PAID' AND school_fees), 0)) FROM refs),
                    'schoolFees', (SELECT coalesce(json_agg(x ORDER BY x.session DESC), '[]'::json) FROM (
                        SELECT ss.session, pp.payable, pp.paid, pp.outstanding, pp.status, pp.payments, pp.last_paid_at, pp.last_reference
                          FROM sessions ss CROSS JOIN LATERAL finance.payment_position(:s, ss.session, NULL) pp) x),
                    'refunds', (SELECT coalesce(json_agg(x ORDER BY x.created_at DESC), '[]'::json) FROM (
                        SELECT f.reference, f.amount, f.state, f.reason, f.source_reference, f.bank_name, f.account_last4, f.proposed_at AS created_at,
                               f.approved_at, f.paid_at, f.rejected_why FROM finance.refund f WHERE f.student_id = :s) x),
                    'overpayments', (SELECT coalesce(json_agg(x ORDER BY x.decided_at DESC), '[]'::json) FROM (
                        SELECT o.session, o.due, o.paid, o.amount, o.decision, o.to_session, o.reference, o.decided_at, o.superseded_at
                          FROM finance.overpayment_decision o WHERE o.student_id = :s) x),
                    'withdrawn', (SELECT coalesce(json_agg(x ORDER BY x.withdrawn_at DESC), '[]'::json) FROM (
                        SELECT w.reference, w.double_kind, w.kept_reference, w.session, w.purpose, w.amount, w.confirmed_at, w.withdrawn_at, w.reason
                          FROM finance.old_payment_withdrawn w WHERE w.student_id = :s) x),
                    'wallet', (SELECT coalesce(json_agg(x ORDER BY x.at DESC), '[]'::json) FROM (
                        SELECT we.kind, we.amount, we.session, we.reference, we.source_code, we.note, we.at FROM finance.wallet_entry we WHERE we.student_id = :s) x),
                    -- V583: the old portal's e-wallet — what it held, what is posted to the wallet, applied and left
                    'legacyWallet', finance.legacy_wallet_of(:s)
                )::text
                """, id);
    }

    /** one confirmed payment's official receipt — only a reference of this student's (an id or reference the reader supplies for
     *  another student is not found), only for the offices that read fees */
    @GetMapping("/receipts/{reference}")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> receipt(@PathVariable UUID id, @PathVariable String reference) {
        need("finance");
        reach(id);
        Map<String, Object> r = portal.receipt(id, reference);
        if (r.get("confirmed_at") == null) {
            throw new DomainRuleViolation("RECEIPT_NOT_CONFIRMED", "A receipt follows a confirmed payment; this one is not confirmed.",
                    new DomainRuleViolation.Remedy("Verify it with the gateway first.", "Bursary"));
        }
        Map<String, Object> out = new java.util.LinkedHashMap<>(r);
        out.put("studentId", id);
        return out;
    }

    /* ── hostel, clearance, documents ── */

    @GetMapping("/hostel")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> hostel(@PathVariable UUID id) {
        need("hostel");
        reach(id);
        return read("""
                SELECT json_build_object(
                    'history', (SELECT coalesce(json_agg(x), '[]'::json) FROM hostel.history(:s) x),
                    'events', (SELECT coalesce(json_agg(x ORDER BY x.at DESC), '[]'::json) FROM (
                        SELECT e.action, e.from_value, e.to_value, e.note, e.actor_office, e.at FROM hostel.event e WHERE e.student_id = :s ORDER BY e.at DESC LIMIT 200) x)
                )::text
                """, id);
    }

    @GetMapping("/clearance")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> clearance(@PathVariable UUID id) {
        need("clearance");
        reach(id);
        return read("""
                SELECT json_build_object(
                    'processes', (SELECT coalesce(json_agg(x ORDER BY x.started_at DESC), '[]'::json) FROM (
                        SELECT p.id, p.workflow, w.label AS workflow_label, p.reference, p.session, p.started_at, p.started_office, p.completed_at,
                               p.cancelled_at, p.cancel_reason, p.certificate_at,
                               (SELECT coalesce(json_agg(i ORDER BY i.unit), '[]'::json) FROM (
                                   SELECT ci.unit, ci.state, ci.item, ci.office, ci.decided_at, ci.note, ci.override
                                     FROM clearance.item ci WHERE ci.process_id = p.id AND ci.superseded_by IS NULL) i) AS items
                          FROM clearance.process p LEFT JOIN clearance.workflow w ON w.code = p.workflow WHERE p.student_id = :s) x),
                    -- the clearance items kept outside a process (the older per-purpose clearance)
                    'items', (SELECT coalesce(json_agg(x ORDER BY x.decided_at DESC NULLS FIRST), '[]'::json) FROM (
                        SELECT ci.purpose, ci.unit, ci.state, ci.item, ci.office, ci.decided_at, ci.note
                          FROM clearance.item ci WHERE ci.student_id = :s AND ci.process_id IS NULL AND ci.superseded_by IS NULL LIMIT 200) x)
                )::text
                """, id);
    }

    @GetMapping("/documents")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> documents(@PathVariable UUID id) {
        need("documents");
        reach(id);
        return read("""
                SELECT json_build_object(
                    'admission', (SELECT coalesce(json_agg(x ORDER BY x.kind), '[]'::json) FROM (
                        SELECT d.kind, d.detail, d.source, d.received_on, d.status FROM people.document d WHERE d.student_id = :s) x),
                    'issued', (SELECT coalesce(json_agg(x ORDER BY x.issued_on DESC), '[]'::json) FROM (
                        SELECT i.kind, i.verification_code, i.issuing_name, i.issued_on, i.issued_office, (i.supersedes IS NOT NULL) AS reissue,
                               EXISTS (SELECT 1 FROM credentials.revocation r WHERE r.credential_id = i.id) AS revoked
                          FROM credentials.issued i WHERE i.student_id = :s) x),
                    'transcripts', (SELECT coalesce(json_agg(x ORDER BY x.requested_at DESC), '[]'::json) FROM (
                        SELECT t.ref, t.kind, t.destination_name, t.mode, t.copies, t.requested_at, t.paid_at, t.stage, t.released_at, t.delivered_at,
                               t.completed_at, t.closed_at FROM credentials.transcript_request t WHERE t.student_id = :s) x),
                    'cards', (SELECT coalesce(json_agg(x ORDER BY x.issued_at DESC), '[]'::json) FROM (
                        SELECT c.card_no, c.issued_at, c.valid_to, c.state, c.ended_at, c.ended_reason FROM credentials.identity_card c WHERE c.student_id = :s) x)
                )::text
                """, id);
    }

    /* ── ICT support: the tickets the student raised and what the desk did on the record ── */

    @GetMapping("/support")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> support(@PathVariable UUID id) {
        need("support");
        reach(id);
        return read("""
                SELECT json_build_object(
                    'tickets', (SELECT coalesce(json_agg(x ORDER BY x.created_at DESC), '[]'::json) FROM (
                        SELECT t.id, t.number, cat.name AS category, t.subject, t.priority, t.queue_code, t.status, t.created_at, t.updated_at, t.resolved_at,
                               helpdesk.person_name(t.assigned_to) AS assigned_to
                          FROM helpdesk.ticket t LEFT JOIN helpdesk.category cat ON cat.id = t.category_id
                         WHERE t.requester_kind = 'STUDENT' AND t.requester_id = :s) x),
                    'actions', (SELECT coalesce(json_agg(x ORDER BY x.at DESC), '[]'::json) FROM (
                        SELECT a.action, a.summary, a.reason, a.session, a.semester, a.outcome, a.override, a.agent_office, helpdesk.person_name(a.agent_id) AS agent, a.at
                          FROM helpdesk.support_action a WHERE a.student_id = :s ORDER BY a.at DESC LIMIT 300) x)
                )::text
                """, id);
    }

    /* ── the activity on the record, for the Registry, the platform and audit ── */

    @GetMapping("/audit")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> audit(@PathVariable UUID id) {
        need("audit");
        reach(id);
        return read("""
                SELECT json_build_object('activity', (SELECT coalesce(json_agg(x ORDER BY x.at DESC), '[]'::json) FROM (
                    SELECT e.occurred_at AS at, 'RECORD_' || e.action AS kind, e.subject_type AS subject, e.actor_office, {actor} AS actor,
                           e.reason, (SELECT string_agg(k, ', ' ORDER BY k) FROM jsonb_object_keys(coalesce(e.after_state, '{}'::jsonb)) k
                                       WHERE e.action = 'UPDATE' AND e.before_state->k IS DISTINCT FROM e.after_state->k) AS changed, NULL::text AS reference
                      FROM audit.entries e
                     -- the record, its contact row (keyed on the student: the chain's subject is md5 of the table and the key, as audit.record
                     -- makes it) and its course registrations
                     WHERE (e.subject_type = 'people.student' AND e.subject_id = :s)
                        OR (e.subject_type = 'people.student_contact' AND e.subject_id = md5(('people.student_contact'::regclass)::oid::text || '|' || :s::text)::uuid)
                        OR (e.subject_type = 'registration.course_registration'
                            AND e.subject_id IN (SELECT r.id FROM registration.course_registration r WHERE r.student_id = :s))
                    UNION ALL
                    SELECT a.at, 'SUPPORT_' || a.action, 'helpdesk.support_action', a.agent_office, helpdesk.person_name(a.agent_id), a.reason, a.field, a.payment_reference
                      FROM helpdesk.support_action a WHERE a.student_id = :s
                    UNION ALL
                    SELECT m.issued_at, 'MATRICULATION_ISSUED', 'people.matric_history', m.actor_office, helpdesk.person_name(m.issued_by), m.reason, NULL, m.matric_no
                      FROM people.matric_history m WHERE m.student_id = :s
                    UNION ALL
                    SELECT ev.at, 'PAYMENT_SWAP_' || ev.action, 'finance.payment_swap_event', ev.actor_office, helpdesk.person_name(ev.actor_id), ev.note, NULL, sw.swap_ref
                      FROM finance.payment_swap_event ev JOIN finance.payment_swap sw ON sw.id = ev.swap_id WHERE ev.student_id = :s
                    UNION ALL
                    SELECT i.issued_on::timestamptz, 'DOCUMENT_ISSUED_' || i.kind, 'credentials.issued', i.issued_office, NULL, NULL, NULL, i.verification_code
                      FROM credentials.issued i WHERE i.student_id = :s
                    ORDER BY 1 DESC LIMIT 500) x))::text
                """, id);
    }
}
