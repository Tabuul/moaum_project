package ng.edu.moaum.portal.studentportal;

import ng.edu.moaum.portal.shared.DomainRuleViolation;
import ng.edu.moaum.portal.shared.FileObjects;
import java.math.BigDecimal;
import java.sql.Types;
import java.time.Instant;
import java.time.OffsetDateTime;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;

/** The student's rows (V026), read and written through the database's own functions. */
@Repository
class StudentPortalRepository {

    private final FileObjects files;
    private final JdbcClient jdbc;
    private final long feeCacheMillis;

    StudentPortalRepository(FileObjects files, JdbcClient jdbc, @Value("${moaum.student-fee-cache-seconds:120}") long feeCacheSeconds) {
        this.jdbc = jdbc;
        this.files = files;
        this.feeCacheMillis = Math.max(0, feeCacheSeconds) * 1000L;
    }

    /* The two dearest reads of a student's dashboard — finance.due_for_semester and finance.spillover_panel — kept per student for a
     * short while (moaum.student-fee-cache-seconds, two minutes by default; 0 turns it off), so the dashboard, its outstanding-fees card
     * and a reload do not each work them out again: on 27 November 2026 they were the database's load and timed the portal out. What a
     * semester charges changes only with the fee setup or the student's registration, and the panel is a picture of the page; no payment
     * is drawn or worded from a kept value (the *Live readers below). */
    private record Kept(Object value, long at) {
    }

    private static final Object NOTHING = new Object();
    private final java.util.concurrent.ConcurrentHashMap<String, Kept> feeKept = new java.util.concurrent.ConcurrentHashMap<>();

    private Object kept(String key, java.util.function.Supplier<Object> read) {
        if (feeCacheMillis <= 0) {
            return read.get();
        }
        long now = System.currentTimeMillis();
        Kept k = feeKept.get(key);
        if (k != null && now - k.at() < feeCacheMillis) {
            return k.value() == NOTHING ? null : k.value();
        }
        Object v = read.get();
        if (feeKept.size() > 100_000) {
            feeKept.entrySet().removeIf(e -> now - e.getValue().at() >= feeCacheMillis);
        }
        feeKept.put(key, new Kept(v == null ? NOTHING : v, now));
        return v;
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
           number is issued — from that moment the number IS the sign-in (V267), and the old one is history. A record the Registry
           ended as a duplicate (V431) opens nothing; two live records under one JAMB number are refused by name, never guessed. */
        java.util.List<Student> found = jdbc.sql(STUDENT + " WHERE s.duplicate_of IS NULL AND (upper(s.matric_no) = upper(:m) OR (s.matric_no IS NULL AND (upper(s.admission_no) = upper(:m) OR upper(s.jamb_reg_no) = upper(:m))))")
                .param("m", matricNo == null ? "" : matricNo.trim()).query(Student.class).list();
        if (found.size() > 1) {
            throw new ng.edu.moaum.portal.shared.DomainRuleViolation("STUDENT_NUMBER_SHARED", "Two records on the register carry this number.",
                    new ng.edu.moaum.portal.shared.DomainRuleViolation.Remedy("Sign in with your admission number. The Registry is settling the two records.", "Registry"));
        }
        return found.stream().findFirst();
    }

    /** V579: a former matriculation number, kept when the Registry corrected it: it opens nothing, and the door says so */
    boolean correctedNumber(String number) {
        return Boolean.TRUE.equals(jdbc.sql("SELECT EXISTS (SELECT 1 FROM people.matric_alias WHERE upper(old_no) = upper(btrim(:n)) AND ended_at IS NULL)")
                .param("n", number == null ? "" : number).query(Boolean.class).single());
    }

    Optional<Student> byId(UUID id) {
        return jdbc.sql(STUDENT + " WHERE s.id = :id").param("id", id).query(Student.class).optional();
    }

    /** V346: tempExpiresAt/tempUsedAt are set while the hash is a temporary password ICT Support issued — good once, until the time;
     *  V485: supportResetAt is when ICT Support last reset the account, until the student chooses a password */
    record Account(UUID id, UUID studentId, String passwordHash, boolean mustChange, int failedAttempts, OffsetDateTime lockedUntil,
                   OffsetDateTime tempExpiresAt, OffsetDateTime tempUsedAt, OffsetDateTime supportResetAt) {
        boolean temporary() {
            return tempExpiresAt != null;
        }

        boolean temporarySpent() {
            return tempExpiresAt != null && (tempUsedAt != null || !tempExpiresAt.isAfter(OffsetDateTime.now()));
        }
    }

    Optional<Account> account(UUID student) {
        return jdbc.sql("SELECT id, student_id, password_hash, must_change, failed_attempts, locked_until, temp_expires_at, temp_used_at, support_reset_at FROM iam.student_account WHERE student_id = :s")
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

    /** V766: the password of the online inter-university transfer application that admitted the student, carried over at the first
     *  sign-in as an applicant account's is — only for a record that transfer made: an applicant's password never opens the record of a
     *  student who was on the register before them */
    Optional<String> transferApplicantHash(UUID student) {
        return jdbc.sql("""
                SELECT acc.password_hash FROM admissions.iut_application ap JOIN admissions.iut_account acc ON acc.id = ap.account_id
                  JOIN people.university_transfer t ON t.id = ap.transfer_id AND t.created_student AND t.student_id = ap.student_id
                 WHERE ap.student_id = :s AND ap.state = 'ADMITTED'
                 ORDER BY ap.updated_at DESC LIMIT 1
                """).param("s", student).query(String.class).optional();
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
                    temp_expires_at = EXCLUDED.temp_expires_at, temp_issued_by = EXCLUDED.temp_issued_by, temp_used_at = NULL, support_reset_at = now()
                """).param("s", student).param("h", hash).param("until", until).param("by", by).update();
    }

    /** V485: the student's one account put back on its first password by ICT Support — a hash of a secret nobody holds, must-change
     *  on, any temporary password withdrawn — so the sign-in door accepts the matriculation number once, for the forced change; the
     *  lockout cleared only when asked. The account is opened in that state if it never was. True when the account was opened here. */
    boolean resetToFirstPassword(UUID student, String hash, boolean unlock) {
        return Boolean.TRUE.equals(jdbc.sql("""
                INSERT INTO iam.student_account (id, student_id, password_hash, must_change, support_reset_at)
                VALUES (gen_random_uuid(), :s, :h, true, now())
                ON CONFLICT (student_id) DO UPDATE SET password_hash = EXCLUDED.password_hash, must_change = true,
                    failed_attempts = CASE WHEN :unlock THEN 0 ELSE iam.student_account.failed_attempts END,
                    locked_until = CASE WHEN :unlock THEN NULL ELSE iam.student_account.locked_until END,
                    temp_expires_at = NULL, temp_issued_by = NULL, temp_used_at = NULL, support_reset_at = now()
                RETURNING (xmax = 0)
                """).param("s", student).param("h", hash).param("unlock", unlock).query(Boolean.class).single());
    }

    /** V485: every session the student holds is ended — a session opened on the old password does not outlive its reset */
    int endSessions(UUID student, String reason) {
        return jdbc.sql("UPDATE platform.session SET ended_at = now(), ended_reason = :r WHERE person_id = :p AND ended_at IS NULL")
                .param("r", reason).param("p", student).update();
    }

    /** V485: the record, the account's state and whether the desk may reset it to the default credential (iam.student_reset_check) */
    Optional<Map<String, Object>> resetCheck(UUID student) {
        return jdbc.sql("SELECT * FROM iam.student_reset_check(:s)").param("s", student).query().listOfRows().stream().findFirst();
    }

    /** V485: the student held while a reset is made, so two clicks are one reset */
    void holdStudent(UUID student) {
        jdbc.sql("SELECT id FROM people.student WHERE id = :s FOR UPDATE").param("s", student).query(UUID.class).optional();
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
        jdbc.sql("UPDATE iam.student_account SET password_hash = :h, must_change = false, failed_attempts = 0, locked_until = NULL, temp_expires_at = NULL, temp_issued_by = NULL, temp_used_at = NULL, support_reset_at = NULL WHERE student_id = :s")
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

    /** V423: the student's own first photograph, in the object store where one is on, else in the row; the student is the one who gave it */
    String savePassport(UUID studentId, byte[] bytes, String type) {
        UUID object = files.enabled() ? files.store("student_photo", studentId, "passport." + (type.endsWith("png") ? "png" : "jpg"), type, bytes) : null;
        int n = jdbc.sql("""
                INSERT INTO people.student_photo (student_id, content, object_id, content_type, bytes, replaced_by, replaced_at, reason)
                VALUES (:s, :c, :o, :t, :n, :s, now(), 'Given by the student on the portal')
                ON CONFLICT (student_id) DO NOTHING
                """).param("s", studentId).param("c", object == null ? bytes : null, java.sql.Types.BINARY).param("o", object, java.sql.Types.OTHER)
                .param("t", type).param("n", bytes.length).update();
        if (n == 0) {
            throw new DomainRuleViolation("PHOTO_ON_RECORD", "Your passport photograph is already on record.",
                    new DomainRuleViolation.Remedy("To change it, ask ICT Support through Help & Requests.", "ICT Support"));
        }
        return object == null ? "database" : "object";
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

    /** the cumulative charge up to and including a semester (whole-session items always count); kept a short while (see kept) */
    java.math.BigDecimal dueForSemester(UUID student, String session, int semester) {
        return (java.math.BigDecimal) kept("due|" + student + "|" + session + "|" + semester, () -> dueForSemesterLive(student, session, semester));
    }

    /** the same, read now: for what a payment is drawn and worded from */
    java.math.BigDecimal dueForSemesterLive(UUID student, String session, int semester) {
        return jdbc.sql("SELECT finance.due_for_semester(:s, :ses, :sem)")
                .param("s", student).param("ses", session).param("sem", semester)
                .query(java.math.BigDecimal.class).single();
    }

    /** whether a clearance scheme is in force today: asked first, because clears() refuses — and aborts the transaction — when none is */
    boolean schemeInForce() {
        return Boolean.TRUE.equals(jdbc.sql("SELECT policy.in_force('clearance', 'UNIVERSITY', current_date) IS NOT NULL").query(Boolean.class).single());
    }

    /** V503: finance.clears_or_null — the clearance's answer, or null where it cannot say (no scheme in force) */
    Boolean clearsOrNull(UUID student, String session, String purpose) {
        return jdbc.sql("SELECT finance.clears_or_null(:s, :ses, :p)").param("s", student).param("ses", session).param("p", purpose)
                .query(Boolean.class).optional().orElse(null);
    }

    boolean clears(UUID student, String session, String purpose) {
        return Boolean.TRUE.equals(jdbc.sql("SELECT finance.clears(:s, :ses, :p)").param("s", student).param("ses", session).param("p", purpose)
                .query(Boolean.class).single());
    }

    /** V667: whether a semester's results are released — the session's rule, or else the fees up to that semester paid */
    boolean resultsCleared(UUID student, String session, int semester) {
        return Boolean.TRUE.equals(jdbc.sql("SELECT finance.results_cleared(:s, :ses, :sem)").param("s", student).param("ses", session).param("sem", semester)
                .query(Boolean.class).single());
    }

    /** V667, V685: what is still to pay for a semester's results to be released — the figure a withheld semester is named with (a past
     *  session from the historical account, at the level of that session: finance.results_outstanding) */
    BigDecimal semesterOutstanding(UUID student, String session, int semester) {
        return jdbc.sql("SELECT finance.results_outstanding(:s, :ses, :sem)").param("s", student).param("ses", session).param("sem", semester)
                .query(BigDecimal.class).optional().orElse(BigDecimal.ZERO);
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
        // V466: the closure message the Director wrote for the window asked for (a CCE student reads the same words)
        return jdbc.sql("""
                SELECT w.configured, w.state, w.phase, w.opens_at, w.closes_at, w.late_until, w.late_fee_enabled, w.reason,
                       (SELECT m.message FROM policy.portal_window_message m WHERE m.window_type = :t) AS message
                  FROM policy.window_state(policy.window_type_for(:st, :t), :s, :sem) w
                """)
                .param("st", student).param("t", type).param("s", session).param("sem", semester, Types.INTEGER).query().singleRow();
    }

    /** V752: whether SIWES binds the student's Second Semester of the session (registration.siwes_applies): it is registered on the
     *  SIWES page, the SIWES course alone */
    boolean siwesApplies(UUID student, String session) {
        return jdbc.sql("SELECT registration.siwes_applies(:s, :ses)").param("s", student).param("ses", session).query(Boolean.class).optional().orElse(false);
    }

    /** V752: whether a class is the SIWES course a SIWES registration holds alone: in the Second Semester SIWES binds
     *  (registration.siwes_applies), the programme's (registration.siwes_course_for); in any semester, the one a SIWES registration of
     *  the student was made on (a row of registration.siwes_registration).
     *  V777: nothing else. Every SIWES course carries the fee now, but where SIWES does not bind the semester a SIWES course is placed
     *  on the ordinary registration beside the others, standing on the paid fee through registration.siwes_course_entry, and the
     *  student drops it on the ordinary form like any course — which frees the payment. The programme's mapped course is therefore
     *  kept here only in the bound semester, never because the programme maps it. */
    boolean siwesCourse(UUID student, String session, int semester, UUID offering) {
        return jdbc.sql("""
                SELECT (:sem = 2 AND registration.siwes_applies(:s, :ses)
                        AND EXISTS (SELECT 1 FROM catalogue.offering o WHERE o.id = :o AND o.course_code = registration.siwes_course_for(:s)))
                    OR EXISTS (SELECT 1 FROM registration.siwes_registration x WHERE x.student_id = :s AND x.offering_id = :o)
                """).param("s", student).param("ses", session).param("sem", semester).param("o", offering).query(Boolean.class).single();
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

    /** V519: the student's overpaid school fees and what the Bursary decided — carried into the next session, or a refund raised
     *  and how far it has gone (V528: with the account given for it, and whether one may be given now; V534: when and how it was paid) */
    List<Map<String, Object>> overpayments(UUID student) {
        return jdbc.sql("""
                SELECT session, amount, decision, to_session, reference, refund_state, decided_at::text AS decided_at,
                       bank_name, account_name, account_last4, account_given_at::text AS account_given_at, account_open,
                       paid_on::text AS paid_on, paid_reference
                  FROM finance.student_overpayments(:s)
                """).param("s", student).query().listOfRows();
    }

    /** V533: the banks a refund is paid into, the commercial and non-interest banks first */
    List<Map<String, Object>> banks() {
        return jdbc.sql("SELECT code, name, nuban_check FROM finance.bank WHERE active ORDER BY (kind IN ('COMMERCIAL', 'NON_INTEREST')) DESC, name")
                .query().listOfRows();
    }

    /** V528: the student gives the bank account a refund raised to them is paid into (finance.give_refund_account refuses
     *  another student's refund, a number that is not ten digits, and an account fixed by approval or payment) */
    void giveRefundAccount(UUID student, String reference, String bank, String accountName, String accountNumber) {
        jdbc.sql("SELECT finance.give_refund_account(:s, :r, :b, :n, :a)")
                .param("s", student).param("r", reference).param("b", bank).param("n", accountName).param("a", accountNumber)
                .query().singleRow();
    }

    /** V451: the open semesters of the session whose school fees are not yet stated for the student, while another's are */
    List<Integer> unstatedSemesters(UUID student, String session) {
        return jdbc.sql("SELECT unnest(finance.fee_unstated_semesters(:s, :ses))").param("s", student).param("ses", session).query(Integer.class).list();
    }

    /** V616: whether the student is in spillover on the Bursary's basis — charged a semester's fees only when they register a course in it */
    private static final tools.jackson.databind.ObjectMapper PANEL_JSON = new tools.jackson.databind.ObjectMapper();

    /** V637: a spillover student's position for a session as the Fees page and dashboard show it (finance.spillover_panel); null when not in spillover */
    Map<String, Object> spilloverPanel(UUID student, String session) {
        String text = (String) kept("spill|" + student + "|" + session, () -> spilloverPanelText(student, session));
        return text == null ? null : PANEL_JSON.readValue(text, new tools.jackson.core.type.TypeReference<Map<String, Object>>() { });
    }

    /** the same, read now: for what a payment is worded from */
    Map<String, Object> spilloverPanelLive(UUID student, String session) {
        String text = spilloverPanelText(student, session);
        return text == null ? null : PANEL_JSON.readValue(text, new tools.jackson.core.type.TypeReference<Map<String, Object>>() { });
    }

    private String spilloverPanelText(UUID student, String session) {
        return jdbc.sql("SELECT finance.spillover_panel(:s, :ses)::text").param("s", student).param("ses", session).query(String.class).optional().orElse(null);
    }

    /** V651: a postgraduate student's stage in the session — the qualification, the stage (800 B — Year 2), fresh or returning, the
     *  cycle, whether the stage is recorded or calculated; null for any other student */
    /** V654: a graduate's historical school fees as the student may see them — the periods with an official amount (the fee structure or
     *  an approved assessment), a period being assessed or reviewed shown as such and never as a debt, the totals of what is official,
     *  whether it is paid online, and the historical references still open; V665: the approved waivers of each period, and whether the
     *  award is approved with the final clearance still to complete */
    Map<String, Object> historicalFees(UUID student) {
        Map<String, Object> out = new java.util.LinkedHashMap<>();
        // V683: each period with what is under review for it — the student's own evidence, a school-fee payment of the session archived for
        // review, a payment of the session under another purpose — so a period is never read as plainly unpaid while a payment is checked
        List<Map<String, Object>> periods = jdbc.sql("""
                SELECT x.session, x.semester, x.level,
                       CASE WHEN x.status IN ('REQUIRES_REVIEW', 'PENDING_APPROVAL') THEN NULL ELSE x.assessed END AS assessed,
                       x.paid, x.outstanding, x.credit,
                       CASE WHEN x.status IN ('REQUIRES_REVIEW', 'PENDING_APPROVAL') THEN 'BEING_ASSESSED' ELSE x.status END AS status,
                       x.waived, rv.review, rv.evidence_ref, rv.evidence_state, rv.archived_amount, rv.other_amount
                  FROM finance.historical_account(:s) x
                  LEFT JOIN finance.historical_review(ARRAY[CAST(:s AS uuid)]) rv ON rv.session = x.session AND rv.semester = x.semester
                """).param("s", student).query().listOfRows();
        out.put("periods", periods);
        out.put("evidence", historicalEvidence(student));
        out.put("graduated", jdbc.sql("""
                SELECT s.status = 'GRADUATED' OR EXISTS (SELECT 1 FROM records.graduand g WHERE g.student_id = s.id AND g.senate_state = 'APPROVED')
                  FROM people.student s WHERE s.id = :s
                """).param("s", student).query(Boolean.class).optional().orElse(false));
        out.put("graduationSession", jdbc.sql("SELECT records.graduation_session(:s)").param("s", student).query(String.class).optional().orElse(null));
        // V665: the award approved and the final clearance under way — the record reads GRADUATED once the Bursar confirms it
        out.put("awaitingFinalClearance", jdbc.sql("SELECT records.awaiting_final_clearance(:s)").param("s", student).query(Boolean.class).optional().orElse(false));
        out.put("onlinePayment", jdbc.sql("SELECT online_payment FROM finance.historical_setting WHERE id = 1").query(Boolean.class).optional().orElse(false));
        out.put("open", jdbc.sql("""
                SELECT r.reference, r.session, r.amount, r.expires_at FROM finance.payment_reference r
                 WHERE r.student_id = :s AND r.confirmed_at IS NULL AND r.expires_at > now() AND r.purpose LIKE 'School fees % (historical)'
                 ORDER BY r.generated_at DESC
                """).param("s", student).query().listOfRows());
        return out;
    }

    /** V720: the student's open, unexpired school-fee references — of any session, the historical door's included — newest first */
    List<Map<String, Object>> openSchoolFeeReferences(UUID student) {
        return jdbc.sql("""
                SELECT r.reference, r.session, r.amount, r.expires_at, r.purpose FROM finance.payment_reference r
                 WHERE r.student_id = :s AND r.confirmed_at IS NULL AND r.archived_at IS NULL AND r.expires_at > now() AND r.purpose LIKE 'School fees%'
                 ORDER BY r.generated_at DESC
                """).param("s", student).query().listOfRows();
    }

    /** V720: the session the historical assessment starts from (finance.historical_start) */
    String historicalStart() {
        return jdbc.sql("SELECT finance.historical_start()").query(String.class).optional().orElse(null);
    }

    String entrySession(UUID student) {
        return jdbc.sql("SELECT entry_session FROM people.student WHERE id = :s").param("s", student).query(String.class).optional().orElse(null);
    }

    /** V740: the session the student's first year of study is in (people.first_session: the session after admission for the admissions
     *  the University's rule names, else the admission session) */
    String firstSession(UUID student) {
        return jdbc.sql("SELECT people.first_session(entry_session, entry_mode) FROM people.student WHERE id = :s").param("s", student)
                .query(String.class).optional().orElse(null);
    }

    Integer levelOf(UUID student) {
        return jdbc.sql("SELECT current_level FROM people.student WHERE id = :s").param("s", student).query(Integer.class).optional().orElse(null);
    }

    /** V665: whether the student's award is approved, the record not yet GRADUATED, and the session after the graduation session */
    boolean awaitingFinalClearanceAfter(UUID student, String session) {
        if (session == null) return false;
        return jdbc.sql("SELECT records.awaiting_final_clearance(:s) AND :ses > coalesce(records.graduation_session(:s), :ses)")
                .param("s", student).param("ses", session).query(Boolean.class).optional().orElse(false);
    }

    /** V683: the student's payment evidence for past semesters, newest first, each with its files and where it stands */
    List<Map<String, Object>> historicalEvidence(UUID student) {
        List<Map<String, Object>> rows = jdbc.sql("""
                SELECT e.id, e.reference, e.session, e.semester, e.amount, e.paid_on::text AS paid_on, e.channel, e.payment_reference, e.note, e.state,
                       e.submitted_at, e.updated_at, e.decided_at, e.decision_note,
                       (SELECT coalesce(jsonb_agg(jsonb_build_object('id', f.id, 'filename', f.filename) ORDER BY f.added_at), '[]'::jsonb)
                          FROM finance.historical_payment_evidence_file f WHERE f.evidence_id = e.id)::text AS files
                  FROM finance.historical_payment_evidence e WHERE e.student_id = :s ORDER BY e.submitted_at DESC
                """).param("s", student).query().listOfRows();
        List<Map<String, Object>> out = new java.util.ArrayList<>();
        for (Map<String, Object> r : rows) {
            Map<String, Object> m = new java.util.LinkedHashMap<>(r);
            m.put("files", PANEL_JSON.readValue(String.valueOf(r.get("files")), new tools.jackson.core.type.TypeReference<List<Map<String, Object>>>() { }));
            out.add(m);
        }
        return out;
    }

    /** V683: payment evidence the student submits for a past semester (the database checks the period, the one open, the fields) */
    Map<String, Object> submitEvidence(UUID student, String session, int semester, BigDecimal amount, java.time.LocalDate paidOn, String channel, String reference,
                                       String note) {
        return jdbc.sql("SELECT x.id, x.reference, x.state FROM finance.historical_evidence_submit(:s, :ses, :sem, :a, :d, :c, :r, :n) x")
                .param("s", student).param("ses", session).param("sem", semester).param("a", amount).param("d", paidOn, Types.DATE)
                .param("c", channel).param("r", reference).param("n", note, Types.VARCHAR).query().singleRow();
    }

    String resubmitEvidence(UUID id, UUID student, BigDecimal amount, java.time.LocalDate paidOn, String channel, String reference, String note) {
        return jdbc.sql("SELECT finance.historical_evidence_resubmit(:id, :s, :a, :d, :c, :r, :n)").param("id", id).param("s", student).param("a", amount)
                .param("d", paidOn, Types.DATE).param("c", channel).param("r", reference).param("n", note, Types.VARCHAR).query(String.class).single();
    }

    String withdrawEvidence(UUID id, UUID student, String reason) {
        return jdbc.sql("SELECT finance.historical_evidence_withdraw(:id, :s, :r)").param("id", id).param("s", student).param("r", reason, Types.VARCHAR)
                .query(String.class).single();
    }

    static final java.util.Set<String> EVIDENCE_TYPES = java.util.Set.of("application/pdf", "image/jpeg", "image/png");

    /** V683: a file of the student's own open payment evidence — a PDF, JPEG or PNG up to 5 MB, ten at most */
    void addEvidenceFile(UUID id, UUID student, String filename, String dataUrl) {
        Map<String, Object> e = jdbc.sql("""
                SELECT x.state, (SELECT count(*) FROM finance.historical_payment_evidence_file f WHERE f.evidence_id = x.id) AS n
                  FROM finance.historical_payment_evidence x WHERE x.id = :id AND x.student_id = :s FOR UPDATE
                """).param("id", id).param("s", student).query().listOfRows().stream().findFirst()
                .orElseThrow(() -> new ng.edu.moaum.portal.shared.NotFound("payment evidence", id));
        if (!java.util.Set.of("SUBMITTED", "MORE_INFORMATION_REQUIRED").contains(String.valueOf(e.get("state")))) {
            throw new DomainRuleViolation("HPE_DECIDED", "This evidence is decided; files are added while it is with the Bursary.",
                    new DomainRuleViolation.Remedy("Submit new evidence if the semester still shows a balance.", "You"));
        }
        if (((Number) e.get("n")).intValue() >= 10) {
            throw new DomainRuleViolation("HPE_FILES", "An evidence carries ten files at most.", new DomainRuleViolation.Remedy("Put the pages in one PDF.", "You"));
        }
        String u = dataUrl == null ? "" : dataUrl;
        int comma = u.indexOf(',');
        String meta = comma > 0 && u.startsWith("data:") ? u.substring(5, comma) : "";
        String type = meta.contains(";") ? meta.substring(0, meta.indexOf(';')) : meta;
        if (!EVIDENCE_TYPES.contains(type)) {
            throw new DomainRuleViolation("HPE_FILE_TYPE", "Evidence is a PDF, JPEG or PNG file.", new DomainRuleViolation.Remedy("Scan or photograph it as one of those.", "You"));
        }
        byte[] bytes;
        try {
            bytes = java.util.Base64.getDecoder().decode(u.substring(comma + 1).replaceAll("\\s", ""));
        } catch (IllegalArgumentException bad) {
            throw new DomainRuleViolation("HPE_FILE", "The file could not be read.", new DomainRuleViolation.Remedy("Choose the file again.", "You"));
        }
        if (bytes.length == 0 || bytes.length > 5 * 1024 * 1024) {
            throw new DomainRuleViolation("HPE_FILE_SIZE", "Evidence is up to 5 MB a file.", new DomainRuleViolation.Remedy("Scan it at a lower resolution.", "You"));
        }
        String name = filename == null || filename.isBlank() ? "evidence" : filename.trim();
        UUID object = files.store("finance.historical_payment_evidence_file", id, name, type, bytes);
        jdbc.sql("""
                INSERT INTO finance.historical_payment_evidence_file (evidence_id, filename, content_type, size_bytes, content, object_id, added_by, added_office)
                VALUES (:x, :f, :t, :n, :c, :o, nullif(current_setting('moaum.actor_id', true), '')::uuid, nullif(current_setting('moaum.actor_office', true), ''))
                """).param("x", id).param("f", name).param("t", type).param("n", (long) bytes.length)
                .param("c", object == null ? bytes : null, Types.BINARY).param("o", object, Types.OTHER).update();
        jdbc.sql("SELECT finance.historical_evidence_event(:x, 'FILE_ADDED', :n)").param("x", id).param("n", name).query().listOfRows();
    }

    /** V683: a file of the student's own evidence — never another student's */
    Optional<FileObjects.Typed> evidenceFile(UUID id, UUID student, UUID file) {
        return jdbc.sql("""
                SELECT f.content_type, f.content, f.object_id FROM finance.historical_payment_evidence_file f
                  JOIN finance.historical_payment_evidence e ON e.id = f.evidence_id
                 WHERE f.id = :f AND e.id = :id AND e.student_id = :s
                """).param("f", file).param("id", id).param("s", student).query().listOfRows().stream().findFirst()
                .map(r -> new FileObjects.Typed(r.get("content") instanceof byte[] b ? b : files.load(UUID.fromString(String.valueOf(r.get("object_id")))),
                        String.valueOf(r.get("content_type"))));
    }

    /** V654: a reference for a graduate's approved historical balance of a session (the database checks the balance and the student) */
    String historicalReference(UUID student, String session, java.math.BigDecimal amount) {
        return jdbc.sql("SELECT finance.historical_reference(:s, :ses, :a)").param("s", student).param("ses", session).param("a", amount).query(String.class).single();
    }

    /** V723: whether the session is on the student's historical account — the door a reference for it goes through */
    boolean onHistoricalAccount(UUID student, String session) {
        return Boolean.TRUE.equals(jdbc.sql("SELECT EXISTS (SELECT 1 FROM finance.historical_account(:s) x WHERE x.session = :ses)")
                .param("s", student).param("ses", session).query(Boolean.class).single());
    }

    Map<String, Object> pgStage(UUID student, String session) {
        return jdbc.sql("""
                SELECT x.cycle_no, x.qualification, q.label AS qualification_label, x.stage_code, x.stage_label, x.category, x.official, x.beyond,
                       x.recommendation, x.cycle_status, x.start_session
                  FROM admissions.pg_stages_of(:ses, ARRAY[CAST(:s AS uuid)]) x LEFT JOIN admissions.pg_qualification q ON q.code = x.qualification
                """).param("s", student).param("ses", session).query().listOfRows().stream().findFirst().orElse(null);
    }

    boolean isSpillover(UUID student) {
        return Boolean.TRUE.equals(jdbc.sql("SELECT finance.is_spillover(:s)").param("s", student).query(Boolean.class).single());
    }

    /** V674: a spillover student's registration of their current session (or a later one) — every course on it is a carry-over */
    boolean carryOnly(UUID student, String session) {
        return Boolean.TRUE.equals(jdbc.sql("SELECT registration.spillover_registration(:s, :ses)").param("s", student).param("ses", session)
                .query(Boolean.class).single());
    }

    boolean semesterCleared(UUID student, String session, int semester) {
        return Boolean.TRUE.equals(jdbc.sql("SELECT finance.semester_cleared(:s, :ses, :sem)")
                .param("s", student).param("ses", session).param("sem", semester).query(Boolean.class).single());
    }

    List<Map<String, Object>> references(UUID student) {
        return jdbc.sql("""
                SELECT pr.id, pr.session, pr.reference, pr.purpose, pr.amount, pr.generated_at, pr.expires_at, pr.confirmed_at, pr.channel, pr.note, pr.receipt_no,
                       pr.archived_at IS NOT NULL AS archived,   -- V670: under review by the Bursary, or excluded for good: never paid
                       CASE WHEN pr.confirmed_at IS NOT NULL THEN finance.payment_term(pr.id) END AS term,
                       """ + CLASSIFIED + """
                  FROM finance.payment_reference pr""" + LEDGER + """
                 WHERE pr.student_id = :s ORDER BY pr.generated_at DESC
                """).param("s", student).query().listOfRows();
    }

    Optional<Map<String, Object>> reference(UUID student, String reference) {
        return jdbc.sql("""
                SELECT pr.id, pr.session, pr.reference, pr.purpose, pr.amount, pr.generated_at, pr.expires_at, pr.confirmed_at, pr.channel, pr.note, pr.receipt_no,
                       pr.archived_at IS NOT NULL AS archived,
                       (SELECT a.archive_ref FROM finance.payment_archive a WHERE a.payment_id = pr.id AND a.state <> 'RECONCILED' ORDER BY a.archived_at DESC LIMIT 1) AS archive_ref,
                       CASE WHEN pr.confirmed_at IS NOT NULL THEN finance.payment_term(pr.id) END AS term,
                       """ + CLASSIFIED + """
                       , (SELECT e.gateway_ref FROM finance.gateway_event e WHERE e.reference = pr.reference AND e.outcome IN ('SETTLED', 'ALREADY_SETTLED')
                           AND e.gateway_ref IS NOT NULL ORDER BY e.received_at DESC LIMIT 1) AS gateway_reference,
                       x.realloc_ref AS correction_ref, x.from_purpose AS correction_from, x.from_session AS correction_from_session,
                       x.executed_at AS correction_at
                  FROM finance.payment_reference pr""" + LEDGER + """
                  -- V649: the Bursary's correction of the payment to another purpose or period, standing
                  LEFT JOIN LATERAL (SELECT y.realloc_ref, y.from_purpose, y.from_session, y.executed_at FROM finance.payment_reallocation y
                                      WHERE y.payment_id = pr.id AND y.status = 'COMPLETED' AND y.kind = 'REALLOCATION'
                                      ORDER BY y.executed_at DESC LIMIT 1) x ON true
                 WHERE pr.student_id = :s AND pr.reference = upper(btrim(:r))
                """).param("s", student).param("r", reference).query().listOfRows().stream().findFirst();
    }

    /* V409: a payment's classification, read from the one ledger (reporting.payments) — programme type, purpose, source module, responsible office */
    private static final String CLASSIFIED = """
            v.programme_type, coalesce(pt.label, v.programme_type) AS programme_type_label, v.purpose_code, coalesce(pu.label, v.purpose_code) AS purpose_label,
                       v.source_module, v.responsible_office, coalesce(ro.label, v.responsible_office) AS responsible_office_label, v.semester AS ledger_semester
            """;
    /* The ledger is a union of four sources that classifies every payment of the University row by row; a join condition on it
     * cannot be pushed into those branches, so joining it on pr.id classified all 314k payments on every dashboard load (70 s on
     * live-shaped data: the student profile's statement timeout). A constant restriction on the student IS pushed into every
     * branch, so the ledger is read for this student only, then joined by payment. */
    private static final String LEDGER = """

              LEFT JOIN (SELECT x.* FROM reporting.payments x WHERE x.source = 'STUDENT' AND x.student_id = :s) v ON v.payment_id = pr.id
              LEFT JOIN finance.programme_type pt ON pt.code = v.programme_type
              LEFT JOIN finance.payment_purpose pu ON pu.code = v.purpose_code
              LEFT JOIN ref.office ro ON ro.code = v.responsible_office
            """;

    /** the level a receipt of the session prints (V672, people.receipt_level): the level the student was at in the session —
     *  the session's course registration (V641), the enrolment, the sessions studied since entry as the cohort engine counts
     *  them (V725: a merged session such as 2019/2020 once — a /19/ student is 300 Level in 2022/2023, not 400; a postgraduate's
     *  level their own, V455) — never below the level the record holds in the session the student is in now (a 300 Level
     *  student's 2025/2026 receipt read 200 from a registration the old-portal upload made at a carry-over's level) */
    Integer levelForSession(UUID student, String session) {
        return jdbc.sql("SELECT people.receipt_level(:s, :ses)").param("s", student).param("ses", session).query(Integer.class).single();
    }

    /** V635: finance.renew_reference — the reference payable again (REOPENED), a new one for what is owed now (NEW), or the one still open (OPEN) */
    Map<String, Object> renewReference(UUID student, String reference) {
        return jdbc.sql("""
                SELECT reference_out AS reference, amount_out AS amount, until_out AS "expiresAt", purpose_out AS purpose, outcome
                  FROM finance.renew_reference(:s, :r)
                """).param("s", student).param("r", reference).query().singleRow();
    }

    /** V781: what the student's own fees page says of school fees paid above the session's charge (finance.student_excess: no row unless a
     *  charge is stated and ₦1 or more is paid above it) — the whole excess, what is decided of it, what is left, what a wallet credit
     *  request waits for, and the cause and holds of the Overpaid school fees list's row when it reads the same excess (else null:
     *  a new overpayment not yet listed). Asked only when the position already read shows ₦1 or more paid above the charge. */
    Optional<Map<String, Object>> studentExcess(UUID student, String session) {
        return jdbc.sql("""
                SELECT excess, decided, remaining, requested, cause, holds IS NOT NULL AS listed, array_to_string(holds, ',') AS holds
                  FROM finance.student_excess(:s, :ses)
                """).param("s", student).param("ses", session).query().listOfRows().stream().findFirst();
    }

    /** V781: the wallet's own money from an overpayment (finance.overpaid_wallet_money) — asked only when the student has a WALLET decision */
    BigDecimal walletOverpaid(UUID student) {
        return jdbc.sql("SELECT finance.overpaid_wallet_money(:s)").param("s", student).query(BigDecimal.class).single();
    }

    String newReference(UUID student, String session, BigDecimal amount, String purpose) {
        return jdbc.sql("SELECT finance.new_reference(:s, :ses, :a, :p)").param("s", student).param("ses", session).param("a", amount)
                .param("p", purpose, Types.VARCHAR).query(String.class).single();
    }

    List<String> sessionsWithCharges() {
        return jdbc.sql("SELECT DISTINCT session FROM finance.fee_schedule WHERE ended_at IS NULL ORDER BY session DESC").query(String.class).list();
    }

    /** V379: the sessions with a fee line that applies to this student (finance.fee_stated). The sessions are listed first and each is
     *  asked once: left in a subquery, the test was pushed below the DISTINCT and asked once for every fee line (851 times for two
     *  sessions, about 4 s on live data, every page of a postgraduate, CCE or MBBS student) */
    List<String> sessionsWithChargesFor(UUID student) {
        return jdbc.sql("""
                WITH x AS MATERIALIZED (SELECT DISTINCT session FROM finance.fee_schedule WHERE ended_at IS NULL)
                SELECT x.session FROM x WHERE finance.fee_stated(:s, x.session) ORDER BY x.session DESC
                """).param("s", student).query(String.class).list();
    }

    /* ── registration ── */

    List<Map<String, Object>> menu(UUID student, String session, int semester) {
        return jdbc.sql("SELECT * FROM registration.student_menu(:s, :ses, :sem)").param("s", student).param("ses", session).param("sem", semester).query().listOfRows();
    }

    /** V504: the student's carry-overs as the published results state them, each with its class this semester (or the semester
     *  of the session it runs in) and whether it is on the semester's registration */
    List<Map<String, Object>> outstanding(UUID student, String session, int semester) {
        return jdbc.sql("SELECT * FROM registration.outstanding_courses(:s, :ses, :sem)").param("s", student).param("ses", session).param("sem", semester)
                .query().listOfRows();
    }

    /** V504: whether students add courses beside their recommended list, how wide, and whether a higher level's course */
    Map<String, Object> flexRule() {
        return jdbc.sql("SELECT allow_other_courses, other_scope, allow_higher_levels FROM registration.flex_rule()").query().singleRow();
    }

    /** V504: the Add Other Course search — every course found judged by the engine (registration.course_check), never by the
     *  browser; the term and filters are bound, never spliced */
    List<Map<String, Object>> searchCourses(UUID student, String session, int semester, String q, Integer level, String dept, String faculty,
                                            String category, int limit, int offset) {
        return jdbc.sql("SELECT * FROM registration.course_search(:s, :ses, :sem, :q, :l, :d, :f, :c, :lim, :off)")
                .param("s", student).param("ses", session).param("sem", semester).param("q", q, Types.VARCHAR).param("l", level, Types.INTEGER)
                .param("d", dept, Types.VARCHAR).param("f", faculty, Types.VARCHAR).param("c", category, Types.VARCHAR)
                .param("lim", limit).param("off", offset).query().listOfRows();
    }

    /** V504: the departments and faculties the search narrows to */
    List<Map<String, Object>> searchDepartments() {
        return jdbc.sql("""
                SELECT d.code, d.name, d.faculty_code, f.name AS faculty FROM ref.department d LEFT JOIN ref.faculty f ON f.code = d.faculty_code
                 WHERE d.ended_on IS NULL ORDER BY f.name NULLS LAST, d.name
                """).query().listOfRows();
    }

    /** V655: the classes of the student's level's courses and carry-overs taught in the semester, opened where the session has none */
    int openStudentClasses(UUID student, String session, int semester) {
        return jdbc.sql("SELECT registration.open_student_classes(:s, :ses, :sem)")
                .param("s", student).param("ses", session).param("sem", semester).query(Integer.class).single();
    }

    /** V655: the class a student adds a course by — the course judged by the engine (refused with its reason), the session's class of
     *  it, opened now when there is none */
    UUID classToAdd(UUID student, String session, int semester, String course) {
        return jdbc.sql("SELECT registration.class_to_add(:s, :ses, :sem, :c)")
                .param("s", student).param("ses", session).param("sem", semester).param("c", course).query(UUID.class).single();
    }

    /** V682: for a spillover registration, what registering a course in the semester costs (finance.spillover_semester_quote): the
     *  semester's own spillover fee, the whole-session item owed with the first semester, what its registration then needs paid; null
     *  for any other student */
    Map<String, Object> spilloverSemesterQuote(UUID student, String session, int semester) {
        String text = jdbc.sql("SELECT finance.spillover_semester_quote(:s, :ses, :sem)::text").param("s", student).param("ses", session).param("sem", semester)
                .query(String.class).optional().orElse(null);
        return text == null ? null : PANEL_JSON.readValue(text, new tools.jackson.core.type.TypeReference<Map<String, Object>>() { });
    }

    /** V663: every earlier course of the student for the carry-over picker, with what it is now and whether it may be added */
    List<Map<String, Object>> carryOverCandidates(UUID student, String session, int semester) {
        return jdbc.sql("SELECT * FROM registration.carry_over_candidates(:s, :ses, :sem)")
                .param("s", student).param("ses", session).param("sem", semester).query().listOfRows();
    }

    /** V663: in this transaction the engine owes, beside the published fail and the declared, a course of the programme below the
     *  student's level with no record on the portal — the carry-over picker's add only (registration.course_context reads it) */
    void declareCarryOvers() {
        jdbc.sql("SELECT set_config('moaum.carry_declare', 'on', true)").query().singleRow();
    }

    /** V663: the reason the audit trail records for what this transaction writes next */
    void reason(String why) {
        jdbc.sql("SELECT set_config('moaum.reason', :r, true)").param("r", why.length() > 500 ? why.substring(0, 500) : why).query().singleRow();
    }

    /** V504: the student adds one course to the semester's draft (made if there is none); the engine refuses what it does not allow */
    String addOther(UUID student, String session, int semester, UUID offering) {
        return jdbc.sql("SELECT registration.student_add_other(:s, :ses, :sem, :o)::text")
                .param("s", student).param("ses", session).param("sem", semester).param("o", offering).query(String.class).single();
    }

    /** V483: the specialisation the student reads within their programme ("MON — Monetary Economics"), or null */
    String specialisation(UUID student) {
        return jdbc.sql("""
                SELECT ps.code || ' — ' || ps.name FROM people.student_specialisation ss
                  JOIN people.student st ON st.id = ss.student_id
                  JOIN catalogue.programme_specialisation ps ON ps.id = ss.specialisation_id AND ps.programme_code = st.programme_code
                 WHERE ss.student_id = :s
                """).param("s", student).query(String.class).optional().orElse(null);
    }

    /** V482: the prerequisite rule in force — ADVISORY (shown) or ENFORCED (the engine refuses) */
    String prerequisiteMode() {
        return jdbc.sql("SELECT registration.prerequisite_mode()").query(String.class).single();
    }

    /** V482: per course, the prerequisites the student has not passed — only the courses that have one unmet */
    Map<String, String> prerequisitesUnmet(UUID student, List<String> codes) {
        Map<String, String> out = new java.util.HashMap<>();
        if (codes.isEmpty()) return out;
        jdbc.sql("""
                SELECT c.code, array_to_string(registration.prerequisites_unmet(:s, c.code), ', ') AS unmet
                  FROM unnest(CAST(:codes AS text[])) AS c(code)
                 WHERE EXISTS (SELECT 1 FROM catalogue.course_prerequisite p WHERE p.course_code = c.code)
                """).param("s", student).param("codes", codes.toArray(String[]::new)).query().listOfRows()
                .forEach(r -> { if (r.get("unmet") != null && !String.valueOf(r.get("unmet")).isEmpty()) out.put(String.valueOf(r.get("code")), String.valueOf(r.get("unmet"))); });
        return out;
    }

    /** V402/V413: the code family the student's cohort registers — BSU or MOAU — or null while the rule is unstated */
    String codeFamily(UUID student) {
        return jdbc.sql("SELECT catalogue.student_code_family(:s)").param("s", student).query(String.class).optional().orElse(null);
    }

    /** V491: how the semester's registration is approved, whether a student may reset it, whether the card follows approval */
    Map<String, Object> approvalRule(String session, int semester) {
        return jdbc.sql("""
                SELECT coalesce(r.mode, 'HOD_APPROVAL_REQUIRED') AS mode, coalesce(r.allow_student_reset, false) AS allow_student_reset,
                       coalesce(r.card_on_approval, true) AS card_on_approval
                  FROM (SELECT 1) one LEFT JOIN LATERAL (SELECT * FROM registration.approval_rule(:s, :m) x WHERE x.id IS NOT NULL) r ON true
                """).param("s", session).param("m", semester).query().singleRow();
    }

    /** V491: why the student's registration for the semester may not be reset by the student, or null */
    String resetRefusal(UUID student, String session, int semester) {
        return jdbc.sql("SELECT registration.reset_refusal(:st, :s, :m, 'STUDENT_PORTAL')").param("st", student).param("s", session).param("m", semester)
                .query(String.class).optional().orElse(null);
    }

    /** V491: the student's own reset — the registration as it stood kept, the chosen courses cleared, back to DRAFT */
    String reset(UUID student, String session, int semester, String reason) {
        return jdbc.sql("SELECT registration.student_reset(:st, :s, :m, :r, 'STUDENT_PORTAL')::text").param("st", student).param("s", session).param("m", semester)
                .param("r", reason, Types.VARCHAR).query(String.class).single();
    }

    /** V491: the resets of the student's registration for the semester, newest first */
    List<Map<String, Object>> resets(UUID student, String session, int semester) {
        return jdbc.sql("""
                SELECT reset_at, previous_status, course_count, units, source FROM registration.registration_reset
                 WHERE student_id = :st AND session = :s AND semester = :m ORDER BY reset_at DESC LIMIT 10
                """).param("st", student).param("s", session).param("m", semester).query().listOfRows();
    }

    /** V491: what holds the registration for review under automatic approval, or null */
    String reviewReason(UUID student, String session, int semester) {
        return jdbc.sql("""
                SELECT ar.reason FROM registration.approval_review ar JOIN registration.course_registration r ON r.id = ar.registration_id
                 WHERE r.student_id = :st AND r.session = :s AND r.semester = :m AND ar.cleared_at IS NULL
                """).param("st", student).param("s", session).param("m", semester).query(String.class).optional().orElse(null);
    }

    /** V491: the student's examination card issued once more */
    /** V501: the examination card's rule, as JSON */
    String examCardState(UUID student, String session, int semester) {
        return jdbc.sql("SELECT registration.exam_card_state(:st, :s, :m)::text").param("st", student).param("s", session).param("m", semester)
                .query(String.class).single();
    }

    void recordExamCard(UUID student, String session, int semester) {
        jdbc.sql("SELECT registration.record_exam_card(:st, :s, :m)").param("st", student).param("s", session).param("m", semester).query().listOfRows();
    }

    Optional<Map<String, Object>> registration(UUID student, String session, int semester) {
        return jdbc.sql("""
                SELECT r.id, r.status, r.level, r.submitted_at, r.approved_at, r.returned_comment, r.approval_mode, registration.units_of(r.id) AS units,
                       -- V756: the student's Summer semester (a CCE or postgraduate semester 3 is their own third semester)
                       (r.semester = 3 AND registration.is_summer_for(r.student_id, r.session, r.semester)) AS summer,
                       -- a past course as the student took it: the title and the code an old-portal file stated (codeAsTaken null where none did)
                       (SELECT json_agg(json_build_object('offeringId', e.offering_id, 'courseCode', c.code, 'codeAsTaken', at.code_as_taken,
                               'title', coalesce(at.title, o.title, c.title), 'units', e.units,
                               'kind', c.kind, 'basis', CASE WHEN e.entry_type = 'CARRYOVER' THEN 'Carryover' WHEN e.entry_type = 'DEFERRED' THEN 'Deferred' ELSE e.basis END, 'courseSemester', c.semester,
                               'lecturer', CASE WHEN lp.id IS NULL THEN NULL ELSE lp.surname || ', ' || lp.given_names END,
                               'entryType', e.entry_type, 'status', e.status,
                               -- V504: the category the University orders by (carry-over, GST, core, elective), and a course the student added
                               -- V620: the basis as the student registered it (registration.entry.basis), never the binding as it is today
                               'category', registration.entry_category(e.entry_type, c.kind, e.basis), 'addedAs', e.added_as,
                               'studentAdded', e.student_added_at IS NOT NULL)
                               ORDER BY registration.entry_rank(e.entry_type, c.kind, e.basis), e.entry_type = 'DEFERRED', c.code)::text
                          FROM registration.entry e JOIN catalogue.offering o ON o.id = e.offering_id JOIN catalogue.course c ON c.code = o.course_code
                          LEFT JOIN catalogue.course_as_taken at ON at.id = e.as_taken_id
                          LEFT JOIN iam.person lp ON lp.id = o.lecturer_id
                         WHERE e.registration_id = r.id) AS entries
                  FROM registration.course_registration r JOIN people.student st ON st.id = r.student_id
                 WHERE r.student_id = :s AND r.session = :ses AND r.semester = :sem
                """).param("s", student).param("ses", session).param("sem", semester).query().listOfRows().stream().findFirst();
    }

    /* every registration the student has made, newest session first — the registration history */
    List<Map<String, Object>> registrationHistory(UUID student) {
        return jdbc.sql("""
                SELECT r.id, r.session, r.semester, r.status, r.level, r.submitted_at, r.approved_at, registration.units_of(r.id) AS units,
                       -- V756: the student's Summer semester (a CCE or postgraduate semester 3 is their own third semester)
                       (r.semester = 3 AND registration.is_summer_for(r.student_id, r.session, r.semester)) AS summer,
                       -- V752: a SIWES registration (the SIWES course registered on the SIWES page) says so in the history — while its
                       -- SIWES course stands (registration.siwes_registered's test): undone by an office, it is an ordinary registration
                       EXISTS (SELECT 1 FROM registration.siwes_registration sr
                                 JOIN registration.entry se ON se.registration_id = sr.course_registration_id AND se.offering_id = sr.offering_id
                                                           AND se.status NOT IN ('DROPPED', 'WITHDRAWN')
                                WHERE sr.course_registration_id = r.id) AS siwes,
                       -- a past course as the student took it: the title and the code an old-portal file stated (codeAsTaken null where none did)
                       (SELECT json_agg(json_build_object('courseCode', c.code, 'codeAsTaken', at.code_as_taken, 'title', coalesce(at.title, o.title, c.title), 'units', e.units,
                               'kind', c.kind, 'basis', CASE WHEN e.entry_type = 'CARRYOVER' THEN 'Carryover' WHEN e.entry_type = 'DEFERRED' THEN 'Deferred' ELSE e.basis END, 'courseSemester', c.semester,
                               'lecturer', CASE WHEN lp.id IS NULL THEN NULL ELSE lp.surname || ', ' || lp.given_names END,
                               'entryType', e.entry_type, 'status', e.status,
                               -- V504: the category the University orders by (carry-over, GST, core, elective), and a course the student added
                               -- V620: the basis as the student registered it (registration.entry.basis), never the binding as it is today
                               'category', registration.entry_category(e.entry_type, c.kind, e.basis), 'addedAs', e.added_as,
                               'studentAdded', e.student_added_at IS NOT NULL)
                               ORDER BY registration.entry_rank(e.entry_type, c.kind, e.basis), e.entry_type = 'DEFERRED', c.code)::text
                          FROM registration.entry e JOIN catalogue.offering o ON o.id = e.offering_id JOIN catalogue.course c ON c.code = o.course_code
                          LEFT JOIN catalogue.course_as_taken at ON at.id = e.as_taken_id
                          LEFT JOIN iam.person lp ON lp.id = o.lecturer_id
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

    /** the unit range at the level for the session and semester — V380: the CCE course load for a CCE student where the Academic
     *  Office stated one; V495: else the minimum of the student's curriculum (CCMAS, BMAS) the Directorate of ICT set, with the
     *  curriculum and what the minimum comes from (CCE, CURRICULUM or LEVEL) */
    Map<String, Object> limit(UUID student, int level, String session, int semester) {
        return jdbc.sql("SELECT min_units, max_units, curriculum, basis FROM registration.unit_rule(:s, :l, :ses, :sem)")
                .param("s", student).param("l", level).param("ses", session).param("sem", semester).query().listOfRows().stream().findFirst()
                .orElse(Map.of("min_units", 0, "max_units", 99));
    }

    /** the student's standing (V244): PROBATION or GOOD, with the semester that pronounced it and the level's probation ceiling */
    Map<String, Object> standing(UUID student, int level) {
        Map<String, Object> st = jdbc.sql("SELECT standing, cgpa, pronounced_session, pronounced_semester, pronounced_level FROM assessment.student_standing(:s)")
                .param("s", student).query().listOfRows().stream().findFirst().orElse(null);
        Integer cap = jdbc.sql("SELECT probation_max_units FROM registration.unit_limit(:s, :l)").param("s", student).param("l", level)
                .query(Integer.class).optional().orElse(null);
        Map<String, Object> out = new java.util.LinkedHashMap<>();
        // V421: NOT_AVAILABLE before any complete published semester — a missing result is never good or bad standing
        out.put("standing", st == null ? "NOT_AVAILABLE" : st.get("standing"));
        out.put("cgpa", st == null ? null : st.get("cgpa"));
        out.put("pronounced_session", st == null ? null : st.get("pronounced_session"));
        out.put("pronounced_semester", st == null ? null : st.get("pronounced_semester"));
        out.put("pronounced_level", st == null ? null : st.get("pronounced_level"));
        out.put("probation_max_units", cap);
        // V421: the University's threshold, and the latest ended semester's result status with the message the student reads
        out.put("threshold", jdbc.sql("SELECT policy.probation_below_cgpa()").query(java.math.BigDecimal.class).single());
        Map<String, Object> rs = jdbc.sql("SELECT session, semester, level, status, registered, published, message FROM assessment.student_result_status(:s)")
                .param("s", student).query().listOfRows().stream().findFirst().orElse(null);
        out.put("result_status", rs == null ? null : rs.get("status"));
        out.put("result_session", rs == null ? null : rs.get("session"));
        out.put("result_semester", rs == null ? null : rs.get("semester"));
        out.put("result_message", rs == null ? null : rs.get("message"));
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

    /** V666: every attempt of each course the student has failed on a published result, and whether it is owed now */
    List<Map<String, Object>> carryoverHistory(UUID student) {
        return jdbc.sql("SELECT * FROM registration.carryover_history(:s)").param("s", student).query().listOfRows();
    }

    /** V597: the kind of load the semester's registration carries — NORMAL (a current course of the programme, which the minimum binds),
     *  CARRY_OVER (carry-overs and deferred courses alone) or GST_EPS (GST/EPS courses alone); null without a registration */
    String loadKind(UUID student, String session, int semester) {
        return jdbc.sql("SELECT registration.load_kind(r.id) FROM registration.course_registration r WHERE r.student_id = :s AND r.session = :n AND r.semester = :m")
                .param("s", student).param("n", session).param("m", semester).query(String.class).optional().orElse(null);
    }

    /** V603: the dashboard the student lands on — COLLEGE for a programme the College runs (MBBS) from 200 Level, else UNIVERSITY */
    String dashboard(UUID student) {
        return jdbc.sql("SELECT people.student_dashboard(:s)").param("s", student).query(String.class).optional().orElse("UNIVERSITY");
    }

    /** V606: whether the student's programme is one the College runs on its own machinery (MBBS) — the College's student area is theirs */
    boolean collegeArea(UUID student) {
        return jdbc.sql("SELECT college.runs_programme(st.programme_code) FROM people.student st WHERE st.id = :s").param("s", student)
                .query(Boolean.class).optional().orElse(false);
    }

    /** V735: whether the Summer Semester page is in the student's menu (registration.summer_area) */
    boolean summerArea(UUID student) {
        return jdbc.sql("SELECT registration.summer_area(:s)").param("s", student).query(Boolean.class).optional().orElse(false);
    }

    /** V752: whether the SIWES page is in the student's menu (registration.siwes_area): SIWES binds the student's current session, or a
     *  SIWES of theirs still stands — a SIWES registration not undone, or a SIWES payment standing for a session SIWES bound them in (K30:
     *  a SIWES wholly undone leaves no menu item) */
    boolean siwesArea(UUID student) {
        return jdbc.sql("SELECT registration.siwes_area(:s)").param("s", student).query(Boolean.class).optional().orElse(false);
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

    /** V389: the School of Postgraduate Studies' session in progress */
    String pgSession() {
        return jdbc.sql("SELECT admissions.pg_current_session()").query(String.class).single();
    }

    /** V733: the session an MBBS student stands in as their own (people.study_session), or null — the University's */
    String ownSession(UUID student) {
        return jdbc.sql("SELECT people.own_session(:s)").param("s", student).query(String.class).optional().orElse(null);
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

    /** the examination sessions whose cards are released — V381: of the student's own stream (a CCE student's are the CCE ones) */
    List<Map<String, Object>> examSessions(UUID student, String session) {
        return jdbc.sql("SELECT id, session, semester, kind, exams_from, exams_to, state, stream FROM assessment.exam_session WHERE session = :s AND state <> 'DRAFT' AND cards_released_at IS NOT NULL AND stream = people.student_stream(:st) ORDER BY semester, kind")
                .param("s", session).param("st", student).query().listOfRows();
    }

    /** V381: why attendance bars the student from the paper, or null (the Centre's policy, where it says so) */
    String examBar(UUID student, UUID offering) {
        return jdbc.sql("SELECT attendance.exam_bar(:s, :o)").param("s", student).param("o", offering).query(String.class).optional().orElse(null);
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
                       -- V635: the unpaid reference, expired or not — the pay block regenerates an expired one
                       (SELECT r.reference FROM finance.payment_reference r WHERE r.student_id = :s AND r.purpose = 'Transcript ' || t.ref AND r.confirmed_at IS NULL ORDER BY (r.expires_at > now()) DESC, r.generated_at DESC LIMIT 1) AS open_reference
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

    /** V699: whether a new identity card would be a replacement, its fee, whether it is paid, and the open reference to pay it */
    Map<String, Object> cardReplacement(UUID student) {
        String text = jdbc.sql("SELECT credentials.id_card_replacement_state(:s)::text").param("s", student).query(String.class).optional().orElse(null);
        return text == null ? null : PANEL_JSON.readValue(text, new tools.jackson.core.type.TypeReference<Map<String, Object>>() { });
    }

    String cardReplacementReference(UUID student) {
        return jdbc.sql("SELECT credentials.id_card_replacement_reference(:s)").param("s", student).query(String.class).single();
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

    /** V512: a course the student asks to add — its code, whether it is a GST/EPS course, and whether it is one of their carry-overs */
    Map<String, Object> gstCourseOf(UUID student, UUID offering) {
        return jdbc.sql("""
                SELECT c.code, c.kind = 'GST' AS gst,
                       CASE WHEN c.kind = 'GST' THEN EXISTS (SELECT 1 FROM registration.carryovers(:s) cv WHERE cv.course_code = c.code) ELSE false END AS carry
                  FROM catalogue.offering o JOIN catalogue.course c ON c.code = o.course_code WHERE o.id = :o
                """).param("s", student).param("o", offering).query().listOfRows().stream().findFirst().orElse(null);
    }

    /** V512: one entry of the GST/EPS registration log (registration.gst_course_event) */
    void gstCourseEvent(UUID student, String session, int semester, String course, boolean carry, String what) {
        jdbc.sql("SELECT registration.gst_course_event(:s, :ses, :sem, :c, :carry, :w)").param("s", student).param("ses", session).param("sem", semester)
                .param("c", course).param("carry", carry).param("w", what).query().listOfRows();
    }

    String gstGate(UUID student, String session, String course) {
        return jdbc.sql("SELECT registration.gst_gate(:s, :ses, :c)").param("s", student).param("ses", session).param("c", course).query(String.class).optional().orElse(null);
    }

    /** V767: the GST gate of several courses in one call (registration.gst_gate_many: each course's answer is registration.gst_gate's
     *  for it, the student's entitlement and payable courses worked out once, not once a course); a course with no hold maps to null */
    Map<String, String> gstGates(UUID student, String session, java.util.Collection<String> courses) {
        Map<String, String> out = new java.util.HashMap<>();
        if (courses.isEmpty()) return out;
        jdbc.sql("SELECT g.course_code, g.message FROM registration.gst_gate_many(:s, :ses, CAST(:codes AS text[])) g")
                .param("codes", courses.toArray(String[]::new), java.sql.Types.ARRAY).param("s", student).param("ses", session)
                .query().listOfRows().forEach(r -> out.put(String.valueOf(r.get("course_code")), (String) r.get("message")));
        return out;
    }

    /** V777: the SIWES registration fee's gate of several courses in one call (registration.siwes_fee_gate_many: each course's answer
     *  is registration.siwes_fee_gate's, the words the entry trigger refuses with — SIWES_UNPAID, SIWES_FEE_NOT_SET or SIWES_NOT_IN_REACH —
     *  the student's standing worked out once, not once a course). The map holds the SIWES courses among those asked (catalogue.course
     *  industrial_training, not ended: the predicate of ix_course_siwes_marked) and no other, each with its refusal, or null where the
     *  fee does not hold it (paid, or the student is not asked: CCE, postgraduate, not in study, not the current session) */
    Map<String, String> siwesFeeGates(UUID student, String session, java.util.Collection<String> courses) {
        Map<String, String> out = new java.util.HashMap<>();
        if (courses.isEmpty()) return out;
        jdbc.sql("""
                SELECT g.course_code, g.message
                  FROM registration.siwes_fee_gate_many(:s, :ses, CAST(:codes AS text[])) g
                 WHERE EXISTS (SELECT 1 FROM catalogue.course c WHERE c.code = g.course_code AND c.industrial_training AND c.state <> 'ENDED')
                """)
                .param("codes", courses.toArray(String[]::new), java.sql.Types.ARRAY).param("s", student).param("ses", session)
                .query().listOfRows().forEach(r -> out.put(String.valueOf(r.get("course_code")), (String) r.get("message")));
        return out;
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

    /** V767: the requirement part of the student's GST/EPS answer alone — finance.gst_eps_explain's 'eligibility', the same to_jsonb of
     *  finance.gst_eps_eligibility. The dashboard reads no more of the answer (it reads the entitlement and the courses on their own),
     *  and the rest, worked out only to be dropped, was most of the dashboard's GST read */
    Map<String, Object> gstEligibility(UUID student, String session) {
        String text = jdbc.sql("SELECT (SELECT to_jsonb(e) FROM finance.gst_eps_eligibility(:s, :ses) e)::text")
                .param("s", student).param("ses", session).query(String.class).optional().orElse(null);
        return text == null ? null : PANEL_JSON.readValue(text, new tools.jackson.core.type.TypeReference<Map<String, Object>>() { });
    }

    /** V643: the GST/EPS courses the registration page shows the student this session (finance.gst_payable_courses) — a student
     *  shown one pays the GST fee for it, whether or not it is owed yet */
    List<Map<String, Object>> gstPayable(UUID student, String session) {
        return jdbc.sql("SELECT course_code, office FROM finance.gst_payable_courses(:s, :ses) ORDER BY course_code")
                .param("s", student).param("ses", session).query().listOfRows();
    }

    /** V690: the GST/EPS courses the student may add as a carry-over (finance.gst_carry_payable) */
    List<Map<String, Object>> gstCarryPayable(UUID student, String session) {
        return jdbc.sql("SELECT course_code, office FROM finance.gst_carry_payable(:s, :ses) ORDER BY course_code")
                .param("s", student).param("ses", session).query().listOfRows();
    }

    /** V691: the GST/EPS courses of the carry-over list the GST fee holds (registration.gst_gate_many: the gate an add meets, over every
     *  course at once), and what the fee comes to — the gate asked only while the fee is stated, above nothing and not paid */
    Map<String, Object> gstCarryHolds(UUID student, String session, List<String> codes) {
        if (codes.isEmpty()) return Map.of("held", List.of());
        Map<String, Object> e = jdbc.sql("SELECT stated, fee, paid, entitled FROM finance.gst_entitlement(:s, :ses)")
                .param("s", student).param("ses", session).query().listOfRows().stream().findFirst().orElse(null);
        if (e == null || !Boolean.TRUE.equals(e.get("stated")) || Boolean.TRUE.equals(e.get("entitled"))) return Map.of("held", List.of());
        java.math.BigDecimal fee = (java.math.BigDecimal) e.get("fee");
        java.math.BigDecimal paid = e.get("paid") == null ? java.math.BigDecimal.ZERO : (java.math.BigDecimal) e.get("paid");
        if (fee == null || fee.signum() <= 0) return Map.of("held", List.of());
        List<String> held = jdbc.sql("SELECT g.course_code FROM registration.gst_gate_many(:s, :ses, CAST(:codes AS text[])) g WHERE g.message IS NOT NULL ORDER BY g.course_code")
                .param("codes", codes.toArray(String[]::new), java.sql.Types.ARRAY).param("s", student).param("ses", session)
                .query(String.class).list();
        return Map.of("held", held, "fee", fee, "toPay", fee.subtract(paid).max(java.math.BigDecimal.ZERO));
    }

    String newGstReference(UUID student, String session) {
        return jdbc.sql("SELECT finance.new_gst_reference(:s, :ses)").param("s", student).param("ses", session).query(String.class).single();
    }

    /** the notices sent to the student, newest first. V749: never a message that carries a secret for its mailbox alone
     *  (platform.notice_carries_secret) — the code that confirms an e-mail or phone (V575), a password-reset link — so a contact is
     *  confirmed only from the mailbox or phone that holds it, never from the dashboard. Read off the student's own messages
     *  (ix_notice_about), the words tested only on them */
    List<Map<String, Object>> notices(UUID student) {
        return jdbc.sql("""
                SELECT x.id, x.channel, x.recipient, x.subject, x.body, x.created_at, x.state, x.sent_at
                  FROM (SELECT n.id, n.channel, n.recipient, n.subject, n.body, n.created_at, n.state, n.sent_at, n.template_key
                          FROM platform.notice n WHERE n.about_kind = 'student' AND n.about_id = :s OFFSET 0) x
                 WHERE NOT platform.notice_carries_secret(x.template_key, x.body)
                 ORDER BY x.created_at DESC LIMIT 30
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
