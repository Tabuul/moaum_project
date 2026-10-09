package ng.edu.moaum.portal.studentportal;

import ng.edu.moaum.portal.shared.FileObjects;
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

    private final FileObjects files;
    private final JdbcClient jdbc;

    StudentPortalRepository(FileObjects files, JdbcClient jdbc) {
        this.jdbc = jdbc;
        this.files = files;
    }

    /* ── the account ── */

    record Student(UUID id, String matricNo, String admissionNo, String surname, String otherNames, String programmeCode,
                   String programme, String facultyCode, String facultyName, String collegeCode, String deptCode, String deptName, String entryMode,
                   String entrySession, int entryLevel, int currentLevel, String status, UUID candidateId, String curriculumVersion, String jambRegNo) {
    }

    private static final String STUDENT = """
            SELECT s.id, s.matric_no, s.admission_no, s.surname, s.other_names, s.programme_code, p.name AS programme,
                   p.faculty_code, f.name AS faculty_name, f.college_code, p.dept_code, d.name AS dept_name, s.entry_mode, s.entry_session,
                   s.entry_level, s.current_level, s.status, s.candidate_id, s.curriculum_version, s.jamb_reg_no
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
        /* the door opens on the matriculation number; on the admission (or JAMB) number only until the matriculation
           number is issued — from that moment the number IS the sign-in (V267), and the old one is history */
        return jdbc.sql(STUDENT + " WHERE upper(s.matric_no) = upper(:m) OR (s.matric_no IS NULL AND (upper(s.admission_no) = upper(:m) OR upper(s.jamb_reg_no) = upper(:m)))")
                .param("m", matricNo == null ? "" : matricNo.trim()).query(Student.class).optional();
    }

    Optional<Student> byId(UUID id) {
        return jdbc.sql(STUDENT + " WHERE s.id = :id").param("id", id).query(Student.class).optional();
    }

    /** V346: tempExpiresAt/tempUsedAt are set while the hash is a temporary password ICT Support issued — good once, until the time */
    record Account(UUID id, UUID studentId, String passwordHash, boolean mustChange, int failedAttempts, OffsetDateTime lockedUntil,
                   OffsetDateTime tempExpiresAt, OffsetDateTime tempUsedAt) {
        boolean temporary() {
            return tempExpiresAt != null;
        }

        boolean temporarySpent() {
            return tempExpiresAt != null && (tempUsedAt != null || !tempExpiresAt.isAfter(OffsetDateTime.now()));
        }
    }

    Optional<Account> account(UUID student) {
        return jdbc.sql("SELECT id, student_id, password_hash, must_change, failed_attempts, locked_until, temp_expires_at, temp_used_at FROM iam.student_account WHERE student_id = :s")
                .param("s", student).query(Account.class).optional();
    }

    /** the student behind an applicant account: the same person, once the Registry has them on the register */
    Optional<Student> byApplicantAccount(UUID applicantAccountId) {
        return jdbc.sql(STUDENT + " JOIN admissions.application ap ON ap.candidate_id = s.candidate_id WHERE ap.account_id = :acc ORDER BY s.matriculated_at NULLS LAST LIMIT 1")
                .param("acc", applicantAccountId).query(Student.class).optional();
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
        jdbc.sql("INSERT INTO iam.student_account (id, student_id, password_hash, must_change) VALUES (:id, :s, :h, :m) ON CONFLICT (student_id) DO UPDATE SET password_hash = EXCLUDED.password_hash, must_change = EXCLUDED.must_change, failed_attempts = 0, locked_until = NULL, temp_expires_at = NULL, temp_issued_by = NULL, temp_used_at = NULL")
                .param("id", id).param("s", student).param("h", hash).param("m", mustChange).update();
        return id;
    }

    /** V346: a temporary password ICT Support issued — the hash only, a forced change, good once until the time; the account opened if there was none */
    void issueTemporary(UUID student, String hash, UUID by, OffsetDateTime until) {
        jdbc.sql("""
                INSERT INTO iam.student_account (id, student_id, password_hash, must_change, temp_expires_at, temp_issued_by)
                VALUES (gen_random_uuid(), :s, :h, true, :until, :by)
                ON CONFLICT (student_id) DO UPDATE SET password_hash = EXCLUDED.password_hash, must_change = true, failed_attempts = 0, locked_until = NULL,
                    temp_expires_at = EXCLUDED.temp_expires_at, temp_issued_by = EXCLUDED.temp_issued_by, temp_used_at = NULL
                """).param("s", student).param("h", hash).param("until", until).param("by", by).update();
    }

    /** V346: the temporary password has opened its one session */
    void temporaryUsed(UUID student) {
        jdbc.sql("UPDATE iam.student_account SET temp_used_at = now() WHERE student_id = :s AND temp_expires_at IS NOT NULL AND temp_used_at IS NULL")
                .param("s", student).update();
    }

    UUID event(String identifier, UUID student, String outcome) {
        return jdbc.sql("INSERT INTO iam.student_event (student_id, identifier, outcome) VALUES (:s, :i, :o) RETURNING id")
                .param("s", student, Types.OTHER).param("i", identifier == null ? "" : identifier).param("o", outcome).query(UUID.class).single();
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
        jdbc.sql("UPDATE iam.student_account SET password_hash = :h, must_change = false, failed_attempts = 0, locked_until = NULL, temp_expires_at = NULL, temp_issued_by = NULL, temp_used_at = NULL WHERE student_id = :s")
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
        // V334: a photograph replaced on the portal (by the support desk) stands before the admission's
        Optional<byte[]> replaced = jdbc.sql("SELECT content, object_id FROM people.student_photo WHERE student_id = :s").param("s", studentId)
                .query().listOfRows().stream().findFirst().map(r -> files.resolve((byte[]) r.get("content"), (UUID) r.get("object_id")));
        if (replaced.isPresent()) {
            return replaced;
        }
        Optional<byte[]> doc = jdbc.sql("""
                SELECT b.content, b.object_id FROM people.student s
                  JOIN admissions.application a ON a.candidate_id = s.candidate_id
                  JOIN admissions.application_document d ON d.application_id = a.id AND d.kind = 'PASSPORT' AND d.superseded_at IS NULL
                  JOIN admissions.application_document_blob b ON b.document_id = d.id
                 WHERE s.id = :s ORDER BY d.id LIMIT 1
                """).param("s", studentId).query().listOfRows().stream().findFirst()
                .map(r -> files.resolve((byte[]) r.get("content"), (UUID) r.get("object_id")));
        if (doc.isPresent()) {
            return doc;
        }
        return jdbc.sql("""
                SELECT at.payload->>'dataUrl' AS u, at.object_id FROM people.student s
                  JOIN admissions.attachment at ON at.kind = 'PASSPORT' AND (jsonb_exists(at.payload, 'dataUrl') OR at.object_id IS NOT NULL)
                     AND (at.candidate_id = s.candidate_id
                          OR (s.jamb_reg_no IS NOT NULL AND at.jamb_key = upper(btrim(s.jamb_reg_no))))
                 WHERE s.id = :s LIMIT 1
                """).param("s", studentId).query().listOfRows().stream().findFirst()
                .map(r -> {
                    if (r.get("object_id") != null) return files.load((UUID) r.get("object_id"));
                    String u = String.valueOf(r.get("u")); int i = u.indexOf(',');
                    return java.util.Base64.getDecoder().decode(i >= 0 ? u.substring(i + 1) : u);
                });
    }

    /** whether a passport photo exists for the student, in either store — so the UI shows the photo without a broken image */
    boolean hasPassport(UUID studentId) {
        if (studentId == null) {
            return false;
        }
        return Boolean.TRUE.equals(jdbc.sql("""
                SELECT EXISTS (SELECT 1 FROM people.student_photo ph WHERE ph.student_id = :s)
                    OR EXISTS (SELECT 1 FROM people.student s
                          JOIN admissions.application a ON a.candidate_id = s.candidate_id
                          JOIN admissions.application_document d ON d.application_id = a.id AND d.kind = 'PASSPORT' AND d.superseded_at IS NULL
                         WHERE s.id = :s)
                    OR EXISTS (SELECT 1 FROM people.student s
                          JOIN admissions.attachment at ON at.kind = 'PASSPORT' AND (jsonb_exists(at.payload, 'dataUrl') OR at.object_id IS NOT NULL)
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

    /** the portal window's state now (V288): school fees payment for the session, or course registration for a semester */
    Map<String, Object> windowState(String type, String session, Integer semester) {
        return jdbc.sql("SELECT configured, state, phase, opens_at, closes_at, late_until, late_fee_enabled, reason FROM policy.window_state(:t, :s, :sem)")
                .param("t", type).param("s", session).param("sem", semester, Types.INTEGER).query().singleRow();
    }

    /** why the student may not register the semester now, or null when the door is open (V287): closed, not yet open, or open early to the session's fresh students from a date */
    String registrationGate(UUID student, String session, int semester) {
        return jdbc.sql("SELECT registration.registration_gate(:s, :ses, :sem)").param("s", student).param("ses", session).param("sem", semester).query(String.class).optional().orElse(null);
    }

    /** the semester's window as the calendar states it */
    Map<String, Object> semesterWindow(String session, int semester) {
        return jdbc.sql("SELECT state, registration_opens, registration_closes, late_registration_closes, fresh_registration_from FROM policy.semester WHERE session = :ses AND number = :sem")
                .param("ses", session).param("sem", semester).query().listOfRows().stream().findFirst().orElse(null);
    }

    /** the highest open semester for a session (registration is gated on that semester's fees), else 1 */
    int openSemester(String session) {
        return jdbc.sql("SELECT coalesce(max(number), 1) FROM policy.semester WHERE session = :ses AND state = 'OPEN'")
                .param("ses", session).query(Integer.class).single();
    }

    /** V380: the open semester of the student's own calendar — the CCE calendar for a CCE student, the full-time one for every other */
    int openSemester(UUID student, String session) {
        return jdbc.sql("SELECT registration.open_semester(:s, :ses)").param("s", student).param("ses", session).query(Integer.class).single();
    }

    /** V380: the semester as the student's own calendar states it */
    Map<String, Object> semesterWindow(UUID student, String session, int semester) {
        return jdbc.sql("SELECT state, registration_opens, registration_closes, late_registration_closes, fresh_registration_from, calendar FROM registration.calendar_semester(:s, :ses, :sem)")
                .param("s", student).param("ses", session).param("sem", semester).query().listOfRows().stream().findFirst().orElse(null);
    }

    /** V380: the portal window that governs the student — a CCE student's school fees and course registration are the CCE windows */
    Map<String, Object> windowFor(UUID student, String type, String session, Integer semester) {
        return jdbc.sql("SELECT configured, state, phase, opens_at, closes_at, late_until, late_fee_enabled, reason FROM policy.window_state(policy.window_type_for(:st, :t), :s, :sem)")
                .param("st", student).param("t", type).param("s", session).param("sem", semester, Types.INTEGER).query().singleRow();
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
    /** V361: whether a school fee of the session applies to the student (a ₦0 line stated on purpose counts) */
    boolean feeStated(UUID student, String session) {
        return Boolean.TRUE.equals(jdbc.sql("SELECT finance.fee_stated(:s, :ses)").param("s", student).param("ses", session).query(Boolean.class).single());
    }

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

    /** V379: the sessions with a fee line that applies to this student (finance.fee_stated) */
    List<String> sessionsWithChargesFor(UUID student) {
        return jdbc.sql("""
                SELECT x.session FROM (SELECT DISTINCT session FROM finance.fee_schedule WHERE ended_at IS NULL) x
                 WHERE finance.fee_stated(:s, x.session) ORDER BY x.session DESC
                """).param("s", student).query(String.class).list();
    }

    /* ── registration ── */

    List<Map<String, Object>> menu(UUID student, String session, int semester) {
        return jdbc.sql("SELECT * FROM registration.student_menu(:s, :ses, :sem)").param("s", student).param("ses", session).param("sem", semester).query().listOfRows();
    }

    Optional<Map<String, Object>> registration(UUID student, String session, int semester) {
        return jdbc.sql("""
                SELECT r.id, r.status, r.level, r.submitted_at, r.approved_at, r.returned_comment, registration.units_of(r.id) AS units,
                       (SELECT json_agg(json_build_object('offeringId', e.offering_id, 'courseCode', c.code, 'title', coalesce(o.title, c.title), 'units', e.units,
                               'kind', c.kind, 'basis', CASE WHEN e.entry_type = 'CARRYOVER' THEN 'Carryover' WHEN e.entry_type = 'DEFERRED' THEN 'Deferred' ELSE co.basis END, 'courseSemester', c.semester,
                               'lecturer', CASE WHEN lp.id IS NULL THEN NULL ELSE lp.surname || ', ' || lp.given_names END,
                               'entryType', e.entry_type, 'status', e.status) ORDER BY e.entry_type IN ('CARRYOVER','DEFERRED') DESC, c.code)::text
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
                       (SELECT json_agg(json_build_object('courseCode', c.code, 'title', coalesce(o.title, c.title), 'units', e.units,
                               'kind', c.kind, 'basis', CASE WHEN e.entry_type = 'CARRYOVER' THEN 'Carryover' WHEN e.entry_type = 'DEFERRED' THEN 'Deferred' ELSE co.basis END, 'courseSemester', c.semester,
                               'lecturer', CASE WHEN lp.id IS NULL THEN NULL ELSE lp.surname || ', ' || lp.given_names END,
                               'entryType', e.entry_type, 'status', e.status) ORDER BY e.entry_type IN ('CARRYOVER','DEFERRED') DESC, c.code)::text
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

    /** V380: add and drop by the student's own calendar */
    boolean addDropOpen(UUID student, String session, int semester) {
        return Boolean.TRUE.equals(jdbc.sql("SELECT registration.add_drop_open(:st, :ses, :sem)")
                .param("st", student).param("ses", session).param("sem", semester).query(Boolean.class).single());
    }

    int addCourse(UUID student, String session, int semester, UUID offering) {
        return jdbc.sql("SELECT registration.student_add(:s, :ses, :sem, :o)")
                .param("s", student).param("ses", session).param("sem", semester).param("o", offering).query(Integer.class).single();
    }

    int dropCourse(UUID student, String session, int semester, UUID offering) {
        return jdbc.sql("SELECT registration.student_drop(:s, :ses, :sem, :o)")
                .param("s", student).param("ses", session).param("sem", semester).param("o", offering).query(Integer.class).single();
    }

    /** the unit range at the level — V380: the CCE course load for a CCE student where the Academic Office stated one */
    Map<String, Object> limit(UUID student, int level) {
        return jdbc.sql("SELECT min_units, max_units FROM registration.unit_limit(:s, :l)").param("s", student).param("l", level).query().listOfRows().stream().findFirst()
                .orElse(Map.of("min_units", 0, "max_units", 99));
    }

    /** the student's standing (V244): PROBATION or GOOD, with the semester that pronounced it and the level's probation ceiling */
    Map<String, Object> standing(UUID student, int level) {
        Map<String, Object> st = jdbc.sql("SELECT standing, cgpa, pronounced_session, pronounced_semester, pronounced_level FROM assessment.student_standing(:s)")
                .param("s", student).query().listOfRows().stream().findFirst().orElse(null);
        Integer cap = jdbc.sql("SELECT probation_max_units FROM registration.unit_limit(:s, :l)").param("s", student).param("l", level)
                .query(Integer.class).optional().orElse(null);
        Map<String, Object> out = new java.util.LinkedHashMap<>();
        out.put("standing", st == null ? "GOOD" : st.get("standing"));
        out.put("cgpa", st == null ? null : st.get("cgpa"));
        out.put("pronounced_session", st == null ? null : st.get("pronounced_session"));
        out.put("pronounced_semester", st == null ? null : st.get("pronounced_semester"));
        out.put("pronounced_level", st == null ? null : st.get("pronounced_level"));
        out.put("probation_max_units", cap);
        return out;
    }

    /* ── results ── */

    List<Map<String, Object>> results(UUID student) {
        return jdbc.sql("SELECT * FROM assessment.student_results(:s)").param("s", student).query().listOfRows();
    }

    List<Map<String, Object>> gpa(UUID student) {
        return jdbc.sql("SELECT * FROM assessment.student_gpa(:s)").param("s", student).query().listOfRows();
    }

    /** where the student stands (V331): the cohort, the expected completion, the spillover, as computed on the register */
    java.util.Optional<Map<String, Object>> academicPosition(UUID student) {
        return jdbc.sql("SELECT jamb_year, effective_cohort, cohort_source, duration_years, expected_completion, spillover_state, spillover_years, classification FROM people.academic_position WHERE student_id = :s")
                .param("s", student).query().listOfRows().stream().findFirst();
    }

    /** the level the student was at in a session and semester (V330): the registration's, else the enrolment's, else carried from entry */
    Integer levelIn(UUID student, String session, int semester) {
        return jdbc.sql("SELECT people.level_in(:s, :n, :m)").param("s", student).param("n", session).param("m", semester).query(Integer.class).optional().orElse(null);
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

    /** where the student stands on the admission lifecycle (V282): MATRICULATED, else the admission status of the application they came through, else the register's status */
    String lifecycle(UUID student) {
        return jdbc.sql("""
                SELECT CASE WHEN s.matric_no IS NOT NULL THEN 'MATRICULATED'
                            ELSE coalesce((SELECT x.status FROM admissions.application ap CROSS JOIN LATERAL admissions.admission_status(ap.id) x
                                            WHERE ap.candidate_id = s.candidate_id ORDER BY ap.submitted_at DESC NULLS LAST LIMIT 1), s.status) END
                  FROM people.student s WHERE s.id = :s
                """).param("s", student).query(String.class).optional().orElse("ADMITTED");
    }

    Optional<String> currentSession() {
        return jdbc.sql("SELECT name FROM policy.academic_session WHERE state = 'CURRENT'").query(String.class).optional();
    }

    /** the latest session the University has run (CURRENT, CLOSED or ARCHIVED; never a draft or planned one) — the one a returning student stands in between sessions */
    Optional<String> latestRunSession() {
        return jdbc.sql("SELECT name FROM policy.academic_session WHERE state IN ('CURRENT', 'CLOSED', 'ARCHIVED') ORDER BY name DESC LIMIT 1").query(String.class).optional();
    }

    /** V379: the current session of a route with a calendar of its own (CCE) */
    String routeSession(String route) {
        return jdbc.sql("SELECT policy.route_session(:r)").param("r", route).query(String.class).optional().orElse(null);
    }

    /** V379: the student's route and study mode; for CCE the Centre, the CCE session beside the undergraduate one, the programme's
     *  duration on the route and the expected completion (the CCE entry session and the duration — never the undergraduate session) */
    Map<String, Object> routeFacts(UUID student) {
        return jdbc.sql("""
                SELECT s.entry_mode AS route, s.study_mode AS "studyMode",
                       CASE WHEN s.entry_mode = 'CCE' THEN (SELECT u.name FROM ref.unit u WHERE u.code = t.centre_unit) END AS centre,
                       CASE WHEN s.entry_mode = 'CCE' THEN policy.route_session('CCE') END AS "cceSession",
                       CASE WHEN s.entry_mode = 'CCE' THEN policy.university_current_session() END AS "undergraduateSession",
                       CASE WHEN s.entry_mode = 'CCE' THEN t.duration_years END AS "durationYears",
                       CASE WHEN s.entry_mode = 'CCE' THEN policy.session_after(s.entry_session, t.duration_years - 1) END AS "expectedCompletion"
                  FROM people.student s LEFT JOIN LATERAL ref.programme_route_terms(s.programme_code, 'CCE') t ON true
                 WHERE s.id = :s
                """).param("s", student).query().singleRow();
    }

    /** the session the student stands in and why (V289): CURRENT, or PREPARING for an entrant of a session still planned */
    Map<String, Object> academicContext(UUID student) {
        return jdbc.sql("SELECT session, context, session_state, current_session, transitions_on::text AS transitions_on FROM people.academic_context(:s)")
                .param("s", student).query().singleRow();
    }

    /** whether the student's course registration for a session is in (submitted, approved or locked) — the resumption step (V289) */
    boolean registrationIn(UUID student, String session) {
        return jdbc.sql("SELECT EXISTS (SELECT 1 FROM registration.course_registration r WHERE r.student_id = :s AND r.session = :ses AND r.status IN ('SUBMITTED', 'APPROVED', 'LOCKED'))")
                .param("s", student).param("ses", session).query(Boolean.class).single();
    }

    /* ── the services (V027) ── */

    List<Map<String, Object>> queries(UUID student) {
        return jdbc.sql("""
                SELECT q.id, q.ref, q.part, q.said, q.routed_dept, d.name AS dept_name, q.raised_at, q.state, q.answer, q.answered_at,
                       c.code AS course_code, coalesce(o.title, c.title) AS title
                  FROM assessment.result_query q
                  JOIN assessment.score_sheet sh ON sh.id = q.sheet_id JOIN catalogue.offering o ON o.id = sh.offering_id
                  JOIN catalogue.course c ON c.code = o.course_code JOIN ref.department d ON d.code = q.routed_dept
                 WHERE q.student_id = :s ORDER BY q.raised_at DESC
                """).param("s", student).query().listOfRows();
    }

    /** the published sheets whose query window is open, with the student's mark on them */
    List<Map<String, Object>> queryable(UUID student) {
        return jdbc.sql("""
                SELECT sh.id AS sheet_id, c.code AS course_code, coalesce(o.title, c.title) AS title, o.session, o.semester, sh.published_at,
                       (sh.published_at + interval '7 days')::date AS window_until, ls.ca, ls.exam, ls.total, ls.grade, ls.outcome
                  FROM assessment.score s JOIN assessment.score_sheet sh ON sh.id = s.sheet_id
                  JOIN catalogue.offering o ON o.id = sh.offering_id JOIN catalogue.course c ON c.code = o.course_code
                  LEFT JOIN LATERAL (SELECT * FROM assessment.latest_scores(sh.id) x WHERE x.student_id = :s) ls ON true
                 WHERE s.student_id = :s AND assessment.query_window_open(sh.id)
                 GROUP BY sh.id, c.code, coalesce(o.title, c.title), o.session, o.semester, sh.published_at, ls.ca, ls.exam, ls.total, ls.grade, ls.outcome
                 ORDER BY c.code
                """).param("s", student).query().listOfRows();
    }

    String raiseQuery(UUID student, UUID sheet, String part, String said) {
        return jdbc.sql("SELECT assessment.raise_query(:s, :sh, :p, :t)").param("s", student).param("sh", sheet).param("p", part).param("t", said).query(String.class).single();
    }

    List<Map<String, Object>> examSessions(String session) {
        return jdbc.sql("SELECT id, session, semester, kind, exams_from, exams_to, state FROM assessment.exam_session WHERE session = :s AND state <> 'DRAFT' AND cards_released_at IS NOT NULL ORDER BY semester, kind")
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

    /** V380: a CCE student's attendance by the register (present, absent, late, excused), and whether the Centre's policy lets students read it */
    List<Map<String, Object>> registerAttendance(UUID student, String session, int semester) {
        return jdbc.sql("""
                SELECT course_code, title, present + late AS attended, total - excused AS held, round(rate)::int AS rate, total, present, absent, late, excused,
                       min_percent, verdict, show_students
                  FROM attendance.course_summary(:s, :ses) WHERE semester = :sem
                """).param("s", student).param("ses", session).param("sem", semester).query().listOfRows();
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

    /* ── GST & EPS (V314) ── */

    Map<String, Object> gstEntitlement(UUID student, String session) {
        return jdbc.sql("SELECT * FROM finance.gst_entitlement(:s, :ses)").param("s", student).param("ses", session).query().singleRow();
    }

    Map<String, Object> gstSetting() {
        return jdbc.sql("SELECT required_for_gst_eps, required_for_all, covers_eps FROM finance.gst_setting WHERE id = 1").query().singleRow();
    }

    String gstGate(UUID student, String session, String course) {
        return jdbc.sql("SELECT registration.gst_gate(:s, :ses, :c)").param("s", student).param("ses", session).param("c", course).query(String.class).optional().orElse(null);
    }

    List<Map<String, Object>> gstReferences(UUID student) {
        return jdbc.sql("""
                SELECT r.reference, r.receipt_no, r.amount, r.session, r.purpose, r.generated_at, r.expires_at, r.confirmed_at, r.channel
                  FROM finance.payment_reference r WHERE r.student_id = :s AND r.purpose LIKE 'GST fee %' ORDER BY r.generated_at DESC
                """).param("s", student).query().listOfRows();
    }

    /**
     * the GST/EPS courses that concern the student this session (V366: finance.gst_eps_rows — the programme's offering at their level,
     * a carryover, a registration), each with why, whether it is owed, offered, registered and marked; a course already passed is shown
     * as such and owes nothing
     */
    List<Map<String, Object>> gstCourses(UUID student, String session) {
        return jdbc.sql("""
                SELECT r.course_code AS code, r.title, r.units, r.level, coalesce(r.semesters[1], c.semester) AS semester, array_to_string(r.semesters, ',') AS semesters,
                       r.office AS general_office, r.offering_id,
                       r.registered, r.source, r.counts, r.status, r.failed_in, r.last_grade, r.passed_in,
                       (SELECT cr.status FROM registration.course_registration cr
                         WHERE cr.student_id = :s AND cr.session = :ses AND cr.semester = coalesce(r.semesters[1], c.semester)) AS registration_status,
                       (SELECT sh.stage FROM assessment.score_sheet sh WHERE sh.offering_id = r.offering_id ORDER BY sh.published_at DESC NULLS LAST LIMIT 1) AS result_stage
                  FROM finance.gst_eps_rows(:ses, :s) r
                  JOIN catalogue.course c ON c.code = r.course_code
                 ORDER BY r.counts DESC, coalesce(r.semesters[1], c.semester), r.course_code
                """).param("s", student).param("ses", session).query().listOfRows();
    }

    /** V366: the student's whole GST/EPS answer for the session (finance.gst_eps_explain) — their requirement, its reasons, the courses */
    Map<String, Object> gstExplain(UUID student, String session) {
        return ng.edu.moaum.portal.shared.GstEpsExplain.read(jdbc, student, session);
    }

    String newGstReference(UUID student, String session) {
        return jdbc.sql("SELECT finance.new_gst_reference(:s, :ses)").param("s", student).param("ses", session).query(String.class).single();
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
