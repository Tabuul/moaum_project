package ng.edu.moaum.portal.studentportal;

import java.math.BigDecimal;
import java.sql.Types;
import java.time.Instant;
import java.time.OffsetDateTime;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;

/** The student's rows (V026), read and written through the database's own functions. */
@Repository
class StudentPortalRepository {

    private final JdbcClient jdbc;

    StudentPortalRepository(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    /* ── the account ── */

    record Student(UUID id, String matricNo, String admissionNo, String surname, String otherNames, String programmeCode,
                   String programme, String facultyCode, String facultyName, String collegeCode, String deptCode, String deptName, String entryMode,
                   String entrySession, int entryLevel, int currentLevel, String status, UUID candidateId, String curriculumVersion) {
    }

    private static final String STUDENT = """
            SELECT s.id, s.matric_no, s.admission_no, s.surname, s.other_names, s.programme_code, p.name AS programme,
                   p.faculty_code, f.name AS faculty_name, f.college_code, p.dept_code, d.name AS dept_name, s.entry_mode, s.entry_session,
                   s.entry_level, s.current_level, s.status, s.candidate_id, s.curriculum_version
              FROM people.student s
              JOIN ref.programme p ON p.code = s.programme_code
              JOIN ref.faculty f ON f.code = p.faculty_code
              JOIN ref.department d ON d.code = p.dept_code
            """;

    /* the student is found by the matriculation number, or before it is issued by the admission
       number, or by the JAMB registration number the candidate has used since application — so the
       same JAMB number that opened the applicant portal opens the student dashboard once they are
       on the register. */
    Optional<Student> byMatric(String matricNo) {
        return jdbc.sql(STUDENT + " WHERE upper(s.matric_no) = upper(:m) OR upper(s.admission_no) = upper(:m) OR upper(s.jamb_reg_no) = upper(:m)")
                .param("m", matricNo == null ? "" : matricNo.trim()).query(Student.class).optional();
    }

    Optional<Student> byId(UUID id) {
        return jdbc.sql(STUDENT + " WHERE s.id = :id").param("id", id).query(Student.class).optional();
    }

    record Account(UUID id, UUID studentId, String passwordHash, boolean mustChange, int failedAttempts, OffsetDateTime lockedUntil) {
    }

    Optional<Account> account(UUID student) {
        return jdbc.sql("SELECT id, student_id, password_hash, must_change, failed_attempts, locked_until FROM iam.student_account WHERE student_id = :s")
                .param("s", student).query(Account.class).optional();
    }

    /** the applicant's hash, when the student came in through the portal: the one account, carried over */
    Optional<String> applicantHash(UUID candidateId) {
        if (candidateId == null) {
            return Optional.empty();
        }
        return jdbc.sql("SELECT password_hash FROM admissions.applicant_account WHERE candidate_id = :c").param("c", candidateId)
                .query(String.class).optional();
    }

    UUID openAccount(UUID student, String hash, boolean mustChange) {
        UUID id = UUID.randomUUID();
        jdbc.sql("INSERT INTO iam.student_account (id, student_id, password_hash, must_change) VALUES (:id, :s, :h, :m) ON CONFLICT (student_id) DO UPDATE SET password_hash = EXCLUDED.password_hash, must_change = EXCLUDED.must_change, failed_attempts = 0, locked_until = NULL")
                .param("id", id).param("s", student).param("h", hash).param("m", mustChange).update();
        return id;
    }

    void failed(UUID student, int attempts, OffsetDateTime lockedUntil) {
        jdbc.sql("UPDATE iam.student_account SET failed_attempts = :n, locked_until = :until WHERE student_id = :s")
                .param("n", attempts).param("until", lockedUntil, Types.TIMESTAMP_WITH_TIMEZONE).param("s", student).update();
    }

    void signedIn(UUID student) {
        jdbc.sql("UPDATE iam.student_account SET failed_attempts = 0, locked_until = NULL, last_signed_in_at = now() WHERE student_id = :s")
                .param("s", student).update();
    }

    void changePassword(UUID student, String hash) {
        jdbc.sql("UPDATE iam.student_account SET password_hash = :h, must_change = false, failed_attempts = 0, locked_until = NULL WHERE student_id = :s")
                .param("h", hash).param("s", student).update();
    }

    void event(String identifier, UUID student, String outcome, String ip) {
        jdbc.sql("INSERT INTO iam.student_event (student_id, identifier, outcome, ip) VALUES (:s, :i, :o, :ip)")
                .param("s", student, Types.OTHER).param("i", identifier == null ? "" : identifier).param("o", outcome).param("ip", ip, Types.VARCHAR).update();
    }

    void openSession(byte[] id, UUID student, Instant absoluteEnd) {
        jdbc.sql("INSERT INTO platform.session (id, person_id, active_office, absolute_end) VALUES (:id, :p, 'student', :end)")
                .param("id", id).param("p", student).param("end", absoluteEnd.atOffset(java.time.ZoneOffset.UTC)).update();
    }

    void endSession(byte[] id, UUID student) {
        jdbc.sql("UPDATE platform.session SET ended_at = now(), ended_reason = 'signed out' WHERE id = :id AND person_id = :p AND ended_at IS NULL")
                .param("id", id).param("p", student).update();
    }

    /* ── the profile ── */

    Map<String, Object> contact(UUID student) {
        return jdbc.sql("SELECT c.phone, c.email, c.address, r.email AS reach_email, r.phone AS reach_phone FROM people.student_reach(:s) r LEFT JOIN people.student_contact c ON c.student_id = :s")
                .param("s", student).query().singleRow();
    }

    void saveContact(UUID student, String phone, String email, String address) {
        jdbc.sql("""
                INSERT INTO people.student_contact (student_id, phone, email, address, updated_at) VALUES (:s, :p, :e, :a, now())
                ON CONFLICT (student_id) DO UPDATE SET phone = EXCLUDED.phone, email = EXCLUDED.email, address = EXCLUDED.address, updated_at = now()
                """).param("s", student).param("p", phone, Types.VARCHAR).param("e", email, Types.VARCHAR).param("a", address, Types.VARCHAR).update();
    }

    Optional<UUID> passportDocument(UUID candidateId) {
        if (candidateId == null) {
            return Optional.empty();
        }
        return jdbc.sql("""
                SELECT d.id FROM admissions.application_document d JOIN admissions.application a ON a.id = d.application_id
                 WHERE a.candidate_id = :c AND d.kind = 'PASSPORT' AND d.superseded_at IS NULL
                 ORDER BY d.id LIMIT 1
                """).param("c", candidateId).query(UUID.class).optional();
    }

    /** the student's passport image bytes: the document store (via their candidate), else the attachment store —
     *  matched by their candidate OR by their own JAMB number (a legacy student loaded by matric → JAMB, whose
     *  photo was uploaded named by JAMB number, carries no candidate). Keyed on the student, not the candidate. */
    Optional<byte[]> passportImage(UUID studentId) {
        if (studentId == null) {
            return Optional.empty();
        }
        Optional<byte[]> doc = jdbc.sql("""
                SELECT b.content FROM people.student s
                  JOIN admissions.application a ON a.candidate_id = s.candidate_id
                  JOIN admissions.application_document d ON d.application_id = a.id AND d.kind = 'PASSPORT' AND d.superseded_at IS NULL
                  JOIN admissions.application_document_blob b ON b.document_id = d.id
                 WHERE s.id = :s ORDER BY d.id LIMIT 1
                """).param("s", studentId).query(byte[].class).optional();
        if (doc.isPresent()) {
            return doc;
        }
        return jdbc.sql("""
                SELECT at.payload->>'dataUrl' FROM people.student s
                  JOIN admissions.attachment at ON at.kind = 'PASSPORT' AND jsonb_exists(at.payload, 'dataUrl')
                     AND (at.candidate_id = s.candidate_id
                          OR (s.jamb_reg_no IS NOT NULL AND at.jamb_key = upper(btrim(s.jamb_reg_no))))
                 WHERE s.id = :s LIMIT 1
                """).param("s", studentId).query(String.class).optional()
                .map(u -> { int i = u.indexOf(','); return java.util.Base64.getDecoder().decode(i >= 0 ? u.substring(i + 1) : u); });
    }

    /** whether a passport photo exists for the student, in either store — so the UI shows the photo without a broken image */
    boolean hasPassport(UUID studentId) {
        if (studentId == null) {
            return false;
        }
        return Boolean.TRUE.equals(jdbc.sql("""
                SELECT EXISTS (SELECT 1 FROM people.student s
                          JOIN admissions.application a ON a.candidate_id = s.candidate_id
                          JOIN admissions.application_document d ON d.application_id = a.id AND d.kind = 'PASSPORT' AND d.superseded_at IS NULL
                         WHERE s.id = :s)
                    OR EXISTS (SELECT 1 FROM people.student s
                          JOIN admissions.attachment at ON at.kind = 'PASSPORT' AND jsonb_exists(at.payload, 'dataUrl')
                             AND (at.candidate_id = s.candidate_id
                                  OR (s.jamb_reg_no IS NOT NULL AND at.jamb_key = upper(btrim(s.jamb_reg_no))))
                         WHERE s.id = :s)
                """).param("s", studentId).query(Boolean.class).single());
    }

    /* ── the fees ── */

    List<Map<String, Object>> charges(UUID student, String session) {
        return jdbc.sql("SELECT id, item, amount, ord FROM finance.charges(:s, :ses)").param("s", student).param("ses", session).query().listOfRows();
    }

    Map<String, Object> position(UUID student, String session) {
        return jdbc.sql("SELECT * FROM finance.position(:s, :ses)").param("s", student).param("ses", session).query().singleRow();
    }

    /** the cumulative charge up to and including a semester (whole-session items always count) */
    java.math.BigDecimal dueForSemester(UUID student, String session, int semester) {
        return jdbc.sql("SELECT finance.due_for_semester(:s, :ses, :sem)")
                .param("s", student).param("ses", session).param("sem", semester)
                .query(java.math.BigDecimal.class).single();
    }

    /** whether a clearance scheme is in force today: asked first, because clears() refuses — and aborts the transaction — when none is */
    boolean schemeInForce() {
        return Boolean.TRUE.equals(jdbc.sql("SELECT policy.in_force('clearance', 'UNIVERSITY', current_date) IS NOT NULL").query(Boolean.class).single());
    }

    boolean clears(UUID student, String session, String purpose) {
        return Boolean.TRUE.equals(jdbc.sql("SELECT finance.clears(:s, :ses, :p)").param("s", student).param("ses", session).param("p", purpose)
                .query(Boolean.class).single());
    }

    /** the highest open semester for a session (registration is gated on that semester's fees), else 1 */
    int openSemester(String session) {
        return jdbc.sql("SELECT coalesce(max(number), 1) FROM policy.semester WHERE session = :ses AND state = 'OPEN'")
                .param("ses", session).query(Integer.class).single();
    }

    /** the SIWES / industrial-training units for the student's programme at a level and semester, else null */
    Integer siwesUnits(UUID student, int level, int semester) {
        return jdbc.sql("""
                SELECT registration.siwes_units(s.programme_code, :lvl, :sem)
                  FROM people.student s WHERE s.id = :id
                """).param("id", student).param("lvl", level).param("sem", semester)
                .query(Integer.class).optional().orElse(null);
    }

    /** the semesters of the session the student has actually registered (submitted or beyond) */
    java.util.List<Integer> registeredSemesters(UUID student, String session) {
        return jdbc.sql("""
                SELECT DISTINCT semester FROM registration.course_registration
                 WHERE student_id = :s AND session = :ses AND status IN ('SUBMITTED', 'APPROVED', 'LOCKED')
                 ORDER BY semester
                """).param("s", student).param("ses", session).query(Integer.class).list();
    }

    /** whether the student's confirmed school-fee payments cover the charge up to and including a semester */
    boolean semesterCleared(UUID student, String session, int semester) {
        return Boolean.TRUE.equals(jdbc.sql("SELECT finance.semester_cleared(:s, :ses, :sem)")
                .param("s", student).param("ses", session).param("sem", semester).query(Boolean.class).single());
    }

    List<Map<String, Object>> references(UUID student) {
        return jdbc.sql("""
                SELECT id, session, reference, purpose, amount, generated_at, expires_at, confirmed_at, channel, note, receipt_no,
                       CASE WHEN confirmed_at IS NOT NULL THEN finance.payment_term(id) END AS term
                  FROM finance.payment_reference WHERE student_id = :s ORDER BY generated_at DESC
                """).param("s", student).query().listOfRows();
    }

    Optional<Map<String, Object>> reference(UUID student, String reference) {
        return jdbc.sql("""
                SELECT id, session, reference, purpose, amount, generated_at, expires_at, confirmed_at, channel, note, receipt_no,
                       CASE WHEN confirmed_at IS NOT NULL THEN finance.payment_term(id) END AS term
                  FROM finance.payment_reference WHERE student_id = :s AND reference = upper(btrim(:r))
                """).param("s", student).param("r", reference).query().listOfRows().stream().findFirst();
    }

    /** the level the student was at during a session — for a receipt, the level when they paid, not
     *  today's. The enrolment for that session if there is one; otherwise derived from the entry level
     *  and how many sessions have passed (a non-dated 'LEGACY' session falls back to the current level). */
    int levelForSession(UUID student, String session) {
        return jdbc.sql("""
                SELECT coalesce(
                    (SELECT e.level FROM people.enrolment e WHERE e.student_id = :s AND e.session = :ses LIMIT 1),
                    (SELECT CASE WHEN :ses ~ '^[0-9]{4}/[0-9]{4}$'
                                 THEN least(600, greatest(100, st.entry_level + (left(:ses, 4)::int - left(st.entry_session, 4)::int) * 100))
                                 ELSE st.current_level END
                       FROM people.student st WHERE st.id = :s))
                """).param("s", student).param("ses", session).query(Integer.class).single();
    }

    String newReference(UUID student, String session, BigDecimal amount, String purpose) {
        return jdbc.sql("SELECT finance.new_reference(:s, :ses, :a, :p)").param("s", student).param("ses", session).param("a", amount)
                .param("p", purpose, Types.VARCHAR).query(String.class).single();
    }

    List<String> sessionsWithCharges() {
        return jdbc.sql("SELECT DISTINCT session FROM finance.fee_schedule WHERE ended_at IS NULL ORDER BY session DESC").query(String.class).list();
    }

    /* ── registration ── */

    List<Map<String, Object>> menu(UUID student, String session, int semester) {
        return jdbc.sql("SELECT * FROM registration.student_menu(:s, :ses, :sem)").param("s", student).param("ses", session).param("sem", semester).query().listOfRows();
    }

    Optional<Map<String, Object>> registration(UUID student, String session, int semester) {
        return jdbc.sql("""
                SELECT r.id, r.status, r.level, r.submitted_at, r.approved_at, r.returned_comment, registration.units_of(r.id) AS units,
                       (SELECT json_agg(json_build_object('offeringId', e.offering_id, 'courseCode', c.code, 'title', c.title, 'units', e.units,
                               'kind', c.kind, 'basis', CASE WHEN e.entry_type = 'CARRYOVER' THEN 'Carryover' ELSE co.basis END, 'courseSemester', c.semester,
                               'lecturer', CASE WHEN lp.id IS NULL THEN NULL ELSE lp.surname || ', ' || lp.given_names END,
                               'entryType', e.entry_type, 'status', e.status) ORDER BY e.entry_type = 'CARRYOVER' DESC, c.code)::text
                          FROM registration.entry e JOIN catalogue.offering o ON o.id = e.offering_id JOIN catalogue.course c ON c.code = o.course_code
                          LEFT JOIN iam.person lp ON lp.id = o.lecturer_id
                          LEFT JOIN catalogue.course_offer co ON co.course_code = c.code AND co.programme_code = st.programme_code AND co.level = r.level
                         WHERE e.registration_id = r.id) AS entries
                  FROM registration.course_registration r JOIN people.student st ON st.id = r.student_id
                 WHERE r.student_id = :s AND r.session = :ses AND r.semester = :sem
                """).param("s", student).param("ses", session).param("sem", semester).query().listOfRows().stream().findFirst();
    }

    /* every registration the student has made, newest session first — the registration history */
    List<Map<String, Object>> registrationHistory(UUID student) {
        return jdbc.sql("""
                SELECT r.id, r.session, r.semester, r.status, r.level, r.submitted_at, r.approved_at, registration.units_of(r.id) AS units,
                       (SELECT json_agg(json_build_object('courseCode', c.code, 'title', c.title, 'units', e.units,
                               'kind', c.kind, 'basis', CASE WHEN e.entry_type = 'CARRYOVER' THEN 'Carryover' ELSE co.basis END, 'courseSemester', c.semester,
                               'lecturer', CASE WHEN lp.id IS NULL THEN NULL ELSE lp.surname || ', ' || lp.given_names END,
                               'entryType', e.entry_type, 'status', e.status) ORDER BY e.entry_type = 'CARRYOVER' DESC, c.code)::text
                          FROM registration.entry e JOIN catalogue.offering o ON o.id = e.offering_id JOIN catalogue.course c ON c.code = o.course_code
                          LEFT JOIN iam.person lp ON lp.id = o.lecturer_id
                          LEFT JOIN catalogue.course_offer co ON co.course_code = c.code AND co.programme_code = st.programme_code AND co.level = r.level
                         WHERE e.registration_id = r.id) AS entries
                  FROM registration.course_registration r JOIN people.student st ON st.id = r.student_id
                 WHERE r.student_id = :s
                 ORDER BY r.session DESC, r.semester
                """).param("s", student).query().listOfRows();
    }

    UUID draft(UUID student, String session, int semester) {
        return jdbc.sql("SELECT registration.student_draft(:s, :ses, :sem)").param("s", student).param("ses", session).param("sem", semester).query(UUID.class).single();
    }

    int choose(UUID registration, List<UUID> offerings) {
        return jdbc.sql("SELECT registration.student_choose(:r, :o)").param("r", registration).param("o", offerings.toArray(UUID[]::new)).query(Integer.class).single();
    }

    String submit(UUID registration) {
        return jdbc.sql("SELECT registration.student_submit(:r)").param("r", registration).query(String.class).single();
    }

    boolean addDropOpen(String session, int semester) {
        return Boolean.TRUE.equals(jdbc.sql("SELECT registration.add_drop_open(:ses, :sem)")
                .param("ses", session).param("sem", semester).query(Boolean.class).single());
    }

    int addCourse(UUID student, String session, int semester, UUID offering) {
        return jdbc.sql("SELECT registration.student_add(:s, :ses, :sem, :o)")
                .param("s", student).param("ses", session).param("sem", semester).param("o", offering).query(Integer.class).single();
    }

    int dropCourse(UUID student, String session, int semester, UUID offering) {
        return jdbc.sql("SELECT registration.student_drop(:s, :ses, :sem, :o)")
                .param("s", student).param("ses", session).param("sem", semester).param("o", offering).query(Integer.class).single();
    }

    Map<String, Object> limit(int level) {
        return jdbc.sql("SELECT min_units, max_units FROM policy.level_limit WHERE level = :l").param("l", level).query().listOfRows().stream().findFirst()
                .orElse(Map.of("min_units", 0, "max_units", 99));
    }

    /* ── results ── */

    List<Map<String, Object>> results(UUID student) {
        return jdbc.sql("SELECT * FROM assessment.student_results(:s)").param("s", student).query().listOfRows();
    }

    List<Map<String, Object>> gpa(UUID student) {
        return jdbc.sql("SELECT * FROM assessment.student_gpa(:s)").param("s", student).query().listOfRows();
    }

    List<Map<String, Object>> carryovers(UUID student) {
        return jdbc.sql("SELECT * FROM registration.carryovers(:s)").param("s", student).query().listOfRows();
    }

    String classOf(BigDecimal cgpa) {
        if (cgpa == null) {
            return null;
        }
        return jdbc.sql("SELECT policy.class_of(:c)").param("c", cgpa).query(String.class).optional().orElse(null);
    }

    /* ── the calendar ── */

    Optional<String> currentSession() {
        return jdbc.sql("SELECT name FROM policy.academic_session WHERE state = 'CURRENT'").query(String.class).optional();
    }

    /* ── the services (V027) ── */

    List<Map<String, Object>> queries(UUID student) {
        return jdbc.sql("""
                SELECT q.id, q.ref, q.part, q.said, q.routed_dept, d.name AS dept_name, q.raised_at, q.state, q.answer, q.answered_at,
                       c.code AS course_code, c.title
                  FROM assessment.result_query q
                  JOIN assessment.score_sheet sh ON sh.id = q.sheet_id JOIN catalogue.offering o ON o.id = sh.offering_id
                  JOIN catalogue.course c ON c.code = o.course_code JOIN ref.department d ON d.code = q.routed_dept
                 WHERE q.student_id = :s ORDER BY q.raised_at DESC
                """).param("s", student).query().listOfRows();
    }

    /** the published sheets whose query window is open, with the student's mark on them */
    List<Map<String, Object>> queryable(UUID student) {
        return jdbc.sql("""
                SELECT sh.id AS sheet_id, c.code AS course_code, c.title, o.session, o.semester, sh.published_at,
                       (sh.published_at + interval '7 days')::date AS window_until, ls.ca, ls.exam, ls.total, ls.grade, ls.outcome
                  FROM assessment.score s JOIN assessment.score_sheet sh ON sh.id = s.sheet_id
                  JOIN catalogue.offering o ON o.id = sh.offering_id JOIN catalogue.course c ON c.code = o.course_code
                  LEFT JOIN LATERAL (SELECT * FROM assessment.latest_scores(sh.id) x WHERE x.student_id = :s) ls ON true
                 WHERE s.student_id = :s AND assessment.query_window_open(sh.id)
                 GROUP BY sh.id, c.code, c.title, o.session, o.semester, sh.published_at, ls.ca, ls.exam, ls.total, ls.grade, ls.outcome
                 ORDER BY c.code
                """).param("s", student).query().listOfRows();
    }

    String raiseQuery(UUID student, UUID sheet, String part, String said) {
        return jdbc.sql("SELECT assessment.raise_query(:s, :sh, :p, :t)").param("s", student).param("sh", sheet).param("p", part).param("t", said).query(String.class).single();
    }

    List<Map<String, Object>> examSessions(String session) {
        return jdbc.sql("SELECT id, session, semester, kind, exams_from, exams_to, state FROM assessment.exam_session WHERE session = :s AND state <> 'DRAFT' ORDER BY semester, kind")
                .param("s", session).query().listOfRows();
    }

    List<Map<String, Object>> docket(UUID student, UUID examSession) {
        return jdbc.sql("SELECT * FROM assessment.student_docket(:s, :x)").param("s", student).param("x", examSession).query().listOfRows();
    }

    List<Map<String, Object>> timetable(UUID student, String session, int semester) {
        return jdbc.sql("SELECT * FROM registration.student_timetable(:s, :ses, :sem)").param("s", student).param("ses", session).param("sem", semester).query().listOfRows();
    }

    List<Map<String, Object>> attendance(UUID student, String session, int semester) {
        return jdbc.sql("SELECT * FROM registration.attendance_rate(:s, :ses, :sem)").param("s", student).param("ses", session).param("sem", semester).query().listOfRows();
    }

    List<Map<String, Object>> cards(UUID student) {
        return jdbc.sql("SELECT id, card_no, issued_at, valid_to, state, ended_at, ended_reason FROM credentials.identity_card WHERE student_id = :s ORDER BY issued_at DESC")
                .param("s", student).query().listOfRows();
    }

    int reportLost(UUID student, String reason) {
        return jdbc.sql("SELECT credentials.report_card_lost(:s, :r)").param("s", student).param("r", reason, Types.VARCHAR).query(Integer.class).single();
    }

    List<Map<String, Object>> transcripts(UUID student) {
        return jdbc.sql("""
                SELECT t.id, t.ref, t.destination, t.destination_name, t.mode, t.copies, t.requested_at, t.paid_at, t.stage, t.produced_at, t.released_at,
                       (SELECT r.reference FROM finance.payment_reference r WHERE r.student_id = :s AND r.purpose = 'Transcript ' || t.ref AND r.confirmed_at IS NULL AND r.expires_at > now() ORDER BY r.generated_at DESC LIMIT 1) AS open_reference
                  FROM credentials.transcript_request t WHERE t.student_id = :s ORDER BY t.requested_at DESC
                """).param("s", student).query().listOfRows();
    }

    String requestTranscript(UUID student, String destination, String destinationName, String mode, int copies) {
        return jdbc.sql("SELECT credentials.student_transcript_request(:s, :d, :dn, :m, :c)").param("s", student).param("d", destination)
                .param("dn", destinationName, Types.VARCHAR).param("m", mode).param("c", copies).query(String.class).single();
    }

    BigDecimal transcriptFee(String session) {
        return jdbc.sql("SELECT finance.transcript_fee(:s)").param("s", session).query(BigDecimal.class).single();
    }

    String purposeReference(UUID student, String session, BigDecimal amount, String purpose) {
        return jdbc.sql("SELECT finance.new_purpose_reference(:s, :ses, :a, :p)").param("s", student).param("ses", session).param("a", amount).param("p", purpose).query(String.class).single();
    }

    List<Map<String, Object>> notices(UUID student) {
        return jdbc.sql("""
                SELECT id, channel, recipient, subject, body, created_at, state, sent_at
                  FROM platform.notice WHERE about_kind = 'student' AND about_id = :s ORDER BY created_at DESC LIMIT 30
                """).param("s", student).query().listOfRows();
    }

    /** the student's own graduation, computed by the record (V029) */
    Map<String, Object> graduation(UUID student) {
        return jdbc.sql("SELECT * FROM records.student_graduation(:s)").param("s", student).query().singleRow();
    }

    /** the convocation clearance, unit by unit, as clearance.position states it */
    List<Map<String, Object>> clearancePosition(UUID student) {
        return jdbc.sql("""
                SELECT p.unit, p.label, p.state, p.item, p.decided_at, u.clears_against, u.holds_for, u.office_code
                  FROM clearance.position(:s, 'CONVOCATION') p JOIN clearance.unit u ON u.code = p.unit ORDER BY p.ord
                """).param("s", student).query().listOfRows();
    }
}
