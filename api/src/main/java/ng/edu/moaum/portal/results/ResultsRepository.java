package ng.edu.moaum.portal.results;

import java.sql.Types;
import java.time.LocalDate;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;

@Repository
class ResultsRepository {

    private static final String SHEET_SELECT = """
            SELECT s.id, o.course_code, c.title AS course_title, c.units, c.dept_code, d.name AS dept_name,
                   d.faculty_code, f.name AS faculty_name, o.session, o.semester, s.stage, s.due_on, s.submitted_at,
                   s.returned_times, o.lecturer_id, coalesce(es.kind, 'MAIN') AS sitting,
                   CASE WHEN p.id IS NULL THEN NULL ELSE p.surname || ', ' || p.given_names END AS lecturer,
                   (SELECT count(*) FROM assessment.sheet_candidates(s.id)) AS candidates,
                   (SELECT count(*) FROM assessment.latest_scores(s.id) WHERE outcome = 'GRADED') AS graded,
                   (SELECT count(*) FROM assessment.latest_scores(s.id) WHERE outcome = 'GRADED' AND points = 0) AS failed,
                   (SELECT dd.actor_id FROM assessment.decision dd WHERE dd.sheet_id = s.id AND dd.kind IN ('SUBMIT','ADVANCE')
                     ORDER BY dd.decided_at DESC LIMIT 1) AS last_actor
              FROM assessment.score_sheet s
              JOIN catalogue.offering o ON o.id = s.offering_id
              JOIN catalogue.course c ON c.code = o.course_code
              JOIN ref.department d ON d.code = c.dept_code
              JOIN ref.faculty f ON f.code = d.faculty_code
              LEFT JOIN assessment.exam_session es ON es.id = s.exam_session_id
              LEFT JOIN iam.person p ON p.id = o.lecturer_id
            """;

    private final JdbcClient jdbc;

    ResultsRepository(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    List<Sheets.Row> sheets(String fac, String dept, String prog, String course, String session, Integer sem, String stage, UUID mine) {
        return jdbc.sql(SHEET_SELECT + """
                 WHERE (:fac::text IS NULL OR d.faculty_code = :fac)
                   AND (:dept::text IS NULL OR c.dept_code = :dept)
                   AND (:prog::text IS NULL OR EXISTS (SELECT 1 FROM catalogue.course_offer cf
                                                        WHERE cf.course_code = c.code AND cf.programme_code = :prog))
                   AND (:course::text IS NULL OR o.course_code = :course)
                   AND (:session::text IS NULL OR o.session = :session)
                   AND (:sem::int IS NULL OR o.semester = :sem)
                   AND (:stage::text IS NULL OR s.stage = :stage)
                   AND (:mine::uuid IS NULL OR o.lecturer_id = :mine OR o.second_examiner_id = :mine
                        OR EXISTS (SELECT 1 FROM catalogue.offering_teacher t WHERE t.offering_id = o.id AND t.lecturer_id = :mine))
                 ORDER BY f.name, d.name, o.course_code
                """)
                .param("fac", fac).param("dept", dept).param("prog", prog).param("course", course)
                .param("session", session).param("sem", sem).param("stage", stage).param("mine", mine)
                .query(Sheets.Row.class).list();
    }

    Optional<Sheets.Row> sheet(UUID id) {
        return jdbc.sql(SHEET_SELECT + " WHERE s.id = :id").param("id", id).query(Sheets.Row.class).optional();
    }

    /**
     * The department a person holds an office over (e.g. 'hod'), or null — used to scope a HOD to
     * their own. Resolved, in order of authority, from the office's own department scope, then the
     * person's home department as a lecturer, then their staff record — so a HOD whose 'hod' grant
     * carries no department still scopes to their own department (V135/V137 put the home department
     * on the lecturer grant and the staff record).
     */
    String officeDepartment(UUID person, String office) {
        return jdbc.sql("""
                WITH raw AS (
                  SELECT COALESCE(
                    (SELECT scope_id FROM iam.office_assignment
                      WHERE person_id = :p AND office_code = :o AND scope_kind = 'department'
                        AND nullif(btrim(scope_id), '') IS NOT NULL
                        AND valid_from <= current_date AND (valid_to IS NULL OR valid_to >= current_date)
                      ORDER BY valid_from DESC LIMIT 1),
                    (SELECT scope_id FROM iam.office_assignment
                      WHERE person_id = :p AND office_code = 'lecturer' AND scope_kind = 'department'
                        AND nullif(btrim(scope_id), '') IS NOT NULL
                        AND valid_from <= current_date AND (valid_to IS NULL OR valid_to >= current_date)
                      ORDER BY valid_from DESC LIMIT 1),
                    (SELECT home_department FROM hrm.staff_record
                      WHERE person_id = :p AND nullif(btrim(home_department), '') IS NOT NULL LIMIT 1)
                  ) AS v)
                SELECT d.code FROM ref.department d, raw
                 WHERE raw.v IS NOT NULL AND d.ended_on IS NULL
                   AND (upper(btrim(d.code)) = upper(btrim(raw.v)) OR lower(btrim(d.name)) = lower(btrim(raw.v)))
                 LIMIT 1
                """).param("p", person).param("o", office).query(String.class).optional().orElse(null);
    }

    long offeringsWithLecturer(String fac, String dept, String session, Integer sem, UUID mine) {
        return jdbc.sql("""
                SELECT count(*) FROM catalogue.offering o JOIN catalogue.course c ON c.code = o.course_code
                  JOIN ref.department d ON d.code = c.dept_code
                 WHERE o.lecturer_id IS NOT NULL
                   AND (:fac::text IS NULL OR d.faculty_code = :fac) AND (:dept::text IS NULL OR c.dept_code = :dept)
                   AND (:session::text IS NULL OR o.session = :session) AND (:sem::int IS NULL OR o.semester = :sem)
                   AND (:mine::uuid IS NULL OR o.lecturer_id = :mine OR o.second_examiner_id = :mine
                        OR EXISTS (SELECT 1 FROM catalogue.offering_teacher t WHERE t.offering_id = o.id AND t.lecturer_id = :mine))
                """).param("fac", fac).param("dept", dept).param("session", session).param("sem", sem).param("mine", mine)
                .query(Long.class).single();
    }

    record Examiner(String secondExaminer, String senateMinute, java.time.OffsetDateTime publishedAt, String engineVersion) {
    }

    Examiner examiner(UUID sheetId) {
        return jdbc.sql("""
                SELECT CASE WHEN p.id IS NULL THEN NULL ELSE p.surname || ', ' || p.given_names END AS second_examiner,
                       s.senate_minute, s.published_at, s.engine_version
                  FROM assessment.score_sheet s JOIN catalogue.offering o ON o.id = s.offering_id
                  LEFT JOIN iam.person p ON p.id = o.second_examiner_id
                 WHERE s.id = :id
                """).param("id", sheetId).query(Examiner.class).single();
    }

    List<Sheets.Decision> chain(UUID sheetId) {
        return jdbc.sql("""
                SELECT d.id, d.from_stage, d.to_stage, d.kind, d.actor_id,
                       CASE WHEN p.id IS NULL THEN NULL ELSE p.surname || ', ' || p.given_names END AS actor,
                       d.actor_office, d.comment, d.decided_at
                  FROM assessment.decision d LEFT JOIN iam.person p ON p.id = d.actor_id
                 WHERE d.sheet_id = :id ORDER BY d.decided_at
                """).param("id", sheetId).query(Sheets.Decision.class).list();
    }

    List<Sheets.Mark> marks(UUID sheetId) {
        return jdbc.sql("""
                SELECT l.student_id, coalesce(st.matric_no, st.admission_no) AS number, st.surname, st.other_names,
                       l.ca, l.exam, l.total, l.grade, l.points, l.outcome, l.version, l.amended
                  FROM assessment.latest_scores(:id) l JOIN people.student st ON st.id = l.student_id
                 ORDER BY st.surname, st.other_names
                """).param("id", sheetId).query(Sheets.Mark.class).list();
    }

    record Latest(Integer ca, Integer exam, String outcome, int version) {
    }

    Optional<Latest> latest(UUID sheetId, UUID studentId) {
        return jdbc.sql("SELECT ca, exam, outcome, version FROM assessment.latest_scores(:s) WHERE student_id = :st")
                .param("s", sheetId).param("st", studentId).query(Latest.class).optional();
    }

    void score(UUID sheetId, UUID studentId, int version, Integer ca, Integer exam, String outcome, String reason) {
        jdbc.sql("""
                INSERT INTO assessment.score (sheet_id, student_id, version, ca, exam, outcome, reason)
                VALUES (:s, :st, :v, :ca, :exam, :o, :r)
                """).param("s", sheetId).param("st", studentId).param("v", version)
                .param("ca", ca, Types.INTEGER).param("exam", exam, Types.INTEGER).param("o", outcome)
                .param("r", reason, Types.VARCHAR).update();
    }

    String advance(UUID sheetId, String comment, String minute) {
        return jdbc.sql("SELECT assessment.advance(:s, :c, :m)").param("s", sheetId)
                .param("c", comment, Types.VARCHAR).param("m", minute, Types.VARCHAR).query(String.class).single();
    }

    void giveBack(UUID sheetId, String comment) {
        jdbc.sql("SELECT assessment.return_sheet(:s, :c)").param("s", sheetId).param("c", comment).query().singleRow();
    }

    List<Sheets.ExamSession> examSessions(String session) {
        return jdbc.sql("""
                SELECT e.id, e.session, e.semester, e.kind, e.exams_from, e.exams_to, e.sheets_due, e.state, e.opened_at,
                       (SELECT count(*) FROM assessment.score_sheet s WHERE s.exam_session_id = e.id) AS sheets,
                       (SELECT count(DISTINCT r.student_id) FROM assessment.score_sheet s
                          JOIN registration.entry en ON en.offering_id = s.offering_id AND en.status = 'APPROVED'
                          JOIN registration.course_registration r ON r.id = en.registration_id
                         WHERE s.exam_session_id = e.id) AS candidates,
                       (SELECT count(*) FROM assessment.score_sheet s WHERE s.exam_session_id = e.id AND s.stage = 'ENTRY') AS outstanding
                  FROM assessment.exam_session e
                 WHERE (:session::text IS NULL OR e.session = :session)
                 ORDER BY e.session DESC, e.semester DESC, e.kind
                """).param("session", session).query(Sheets.ExamSession.class).list();
    }

    Optional<Sheets.ExamSession> examSession(UUID id) {
        return examSessions(null).stream().filter(e -> e.id().equals(id)).findFirst();
    }

    UUID createExamSession(ResultsService.ExamSessionIn in) {
        UUID id = UUID.randomUUID();
        jdbc.sql("""
                INSERT INTO assessment.exam_session (id, session, semester, kind, exams_from, exams_to, sheets_due)
                VALUES (:id, :s, :sem, :k, :f, :t, :d)
                """).param("id", id).param("s", in.session()).param("sem", in.semester())
                .param("k", in.kind() == null ? "MAIN" : in.kind()).param("f", in.examsFrom()).param("t", in.examsTo())
                .param("d", in.sheetsDue()).update();
        return id;
    }

    /** update an examination session (identity + dates) that is not closed; returns rows changed */
    int updateExamSession(UUID id, String session, int semester, String kind,
                          java.time.LocalDate from, java.time.LocalDate to, java.time.LocalDate due) {
        return jdbc.sql("""
                UPDATE assessment.exam_session
                   SET session = :s, semester = :sem, kind = :k, exams_from = :f, exams_to = :t, sheets_due = :d
                 WHERE id = :id AND state <> 'CLOSED'
                """).param("id", id).param("s", session).param("sem", semester).param("k", kind)
                .param("f", from).param("t", to).param("d", due).update();
    }

    /** is there another examination session for this academic session, semester and type? */
    boolean examSessionExists(String session, int semester, String kind, UUID excludeId) {
        return Boolean.TRUE.equals(jdbc.sql("""
                SELECT EXISTS (SELECT 1 FROM assessment.exam_session
                                WHERE session = :s AND semester = :sem AND kind = :k AND id <> :id)
                """).param("s", session).param("sem", semester).param("k", kind).param("id", excludeId).query(Boolean.class).single());
    }

    record Opened(int sheetsMade, int offeringsWithoutLecturer) {
    }

    Opened open(UUID id) {
        return jdbc.sql("SELECT sheets_made, offerings_without_lecturer FROM assessment.open_exam_session(:id)")
                .param("id", id).query(Opened.class).single();
    }

    List<Sheets.FacultyProgress> progress(UUID examSessionId) {
        return jdbc.sql("""
                SELECT f.code AS faculty_code, f.name AS faculty_name,
                       count(s.id) AS expected,
                       count(s.id) FILTER (WHERE s.stage <> 'ENTRY') AS submitted,
                       count(s.id) FILTER (WHERE s.stage NOT IN ('ENTRY','VERIFICATION')) AS verified,
                       count(s.id) FILTER (WHERE s.stage IN ('RECORDS','SENATE','PUBLISHED')) AS past_the_board,
                       count(s.id) FILTER (WHERE s.stage = 'ENTRY') AS outstanding,
                       CASE WHEN count(s.id) = 0 THEN 0
                            ELSE (100 * count(s.id) FILTER (WHERE s.stage IN ('RECORDS','SENATE','PUBLISHED')) / count(s.id))::int END AS progress
                  FROM ref.faculty f
                  LEFT JOIN (assessment.score_sheet s JOIN catalogue.offering o ON o.id = s.offering_id
                             JOIN catalogue.course c ON c.code = o.course_code
                             JOIN ref.department d ON d.code = c.dept_code) ON d.faculty_code = f.code AND s.exam_session_id = :id
                 GROUP BY f.code, f.name
                HAVING count(s.id) > 0
                 ORDER BY f.name
                """).param("id", examSessionId).query(Sheets.FacultyProgress.class).list();
    }

    /* ── the lecturer's own sheets (proto/part5 staffScores) ── */

    record MineRow(UUID id, String courseCode, String courseTitle, int units, String session, int semester, String stage,
                   LocalDate dueOn, int returnedTimes, long candidates, long entered, long graded, String secondExaminer, UUID lecturerId) {
    }

    List<MineRow> mine(UUID person, String session, Integer sem, boolean all) {
        return jdbc.sql("""
                SELECT s.id, o.course_code, c.title AS course_title, c.units, o.session, o.semester, s.stage, s.due_on, s.returned_times,
                       (SELECT count(*) FROM registration.entry e JOIN registration.course_registration r ON r.id = e.registration_id
                         WHERE e.offering_id = o.id AND e.status = 'APPROVED' AND r.status IN ('APPROVED','LOCKED')) AS candidates,
                       (SELECT count(*) FROM assessment.latest_scores(s.id)) AS entered,
                       (SELECT count(*) FROM assessment.latest_scores(s.id) WHERE outcome = 'GRADED') AS graded,
                       CASE WHEN x.id IS NULL THEN NULL ELSE x.surname || ', ' || x.given_names END AS second_examiner,
                       o.lecturer_id
                  FROM assessment.score_sheet s
                  JOIN catalogue.offering o ON o.id = s.offering_id
                  JOIN catalogue.course c ON c.code = o.course_code
                  LEFT JOIN iam.person x ON x.id = o.second_examiner_id
                 WHERE (:all OR o.lecturer_id = :me OR o.second_examiner_id = :me
                        OR EXISTS (SELECT 1 FROM catalogue.offering_teacher t WHERE t.offering_id = o.id AND t.lecturer_id = :me))
                   AND (:session::text IS NULL OR o.session = :session)
                   AND (:sem::int IS NULL OR o.semester = :sem)
                 ORDER BY o.session DESC, o.semester DESC, o.course_code
                """).param("me", person).param("session", session).param("sem", sem).param("all", all)
                .query(MineRow.class).list();
    }

    /** the roll the sheet is entered on: every approved registration, marked or not */
    List<Sheets.RollRow> roll(UUID sheetId) {
        return jdbc.sql("""
                SELECT st.id AS student_id, coalesce(st.matric_no, st.admission_no) AS number, st.surname, st.other_names,
                       st.programme_code, p.name AS programme_name, r.level,
                       l.ca, l.exam, l.total, l.grade, l.points, l.outcome, l.version
                  FROM assessment.score_sheet s
                  JOIN catalogue.offering o ON o.id = s.offering_id
                  JOIN registration.entry e ON e.offering_id = o.id AND e.status = 'APPROVED'
                  JOIN registration.course_registration r ON r.id = e.registration_id AND r.status IN ('APPROVED','LOCKED')
                  JOIN people.student st ON st.id = r.student_id
                  JOIN ref.programme p ON p.code = st.programme_code
                  LEFT JOIN LATERAL (SELECT * FROM assessment.latest_scores(s.id) x WHERE x.student_id = st.id) l ON true
                 WHERE s.id = :id
                 ORDER BY st.surname, st.other_names
                """).param("id", sheetId).query(Sheets.RollRow.class).list();
    }

    /* ── the broadsheet: computed from the sheets, by programme and level (proto/part26 tBroadsheet) ── */

    List<Sheets.BroadsheetCell> broadsheet(String prog, int level, String session, int sem) {
        return jdbc.sql("""
                SELECT st.id AS student_id, coalesce(st.matric_no, st.admission_no) AS number, st.surname, st.other_names,
                       o.course_code, c.title, e.units, coalesce(c.kind, 'Compulsory') AS kind, coalesce(cf.stage, 'NO_SHEET') AS stage, cf.total, cf.grade, cf.points, cf.outcome
                  FROM registration.course_registration r
                  JOIN people.student st ON st.id = r.student_id
                  JOIN registration.entry e ON e.registration_id = r.id AND e.status = 'APPROVED'
                  JOIN catalogue.offering o ON o.id = e.offering_id
                  JOIN catalogue.course c ON c.code = o.course_code
                  LEFT JOIN LATERAL assessment.course_final(st.id, o.id) cf ON true
                 WHERE st.programme_code = :prog AND r.level = :level AND r.session = :session AND r.semester = :sem
                   AND r.status IN ('APPROVED','LOCKED')
                 ORDER BY st.surname, st.other_names, o.course_code
                """).param("prog", prog).param("level", level).param("session", session).param("sem", sem)
                .query(Sheets.BroadsheetCell.class).list();
    }

    /** the candidate's cumulative figures to a point (TCR, TCE, TWGP, CGPA, previous CGPA) */
    Sheets.Cumulative cumulative(UUID student, String session, int sem) {
        return jdbc.sql("SELECT tcr, tce, twgp, cgpa, prev_cgpa AS prevCgpa FROM assessment.student_cumulative(:s, :ss, :sem)")
                .param("s", student).param("ss", session).param("sem", sem)
                .query(Sheets.Cumulative.class).optional().orElse(new Sheets.Cumulative(0, 0, java.math.BigDecimal.ZERO, null, null));
    }

    /** the candidate's outstanding carryover course codes (their standing right now, all levels) */
    List<String> carryovers(UUID student) {
        return jdbc.sql("SELECT course_code FROM registration.carryovers(:s) ORDER BY course_code")
                .param("s", student).query(String.class).list();
    }

    /** carryovers the candidate held as of a period — inclusive=false: carried INTO the semester (the
     *  column); inclusive=true: owed leaving it (the remark). Never pulls from a later period. */
    List<String> carryoversAt(UUID student, String session, int semester, boolean inclusive) {
        return jdbc.sql("SELECT course_code FROM registration.carryovers_at(:s, :se, :sem, :inc) ORDER BY course_code")
                .param("s", student).param("se", session).param("sem", semester).param("inc", inclusive)
                .query(String.class).list();
    }

    List<Sheets.GradeBand> gradeBands() {
        return jdbc.sql("""
                SELECT b.grade, b.low, b.high, b.points FROM policy.grade_band b
                 WHERE b.version_id = policy.in_force('grading', 'UNIVERSITY', current_date) ORDER BY b.low DESC
                """).query(Sheets.GradeBand.class).list();
    }

    List<Sheets.ClassBand> classBands() {
        return jdbc.sql("""
                SELECT b.class AS clazz, b.low, b.high, b.ord FROM policy.classification_band b
                 WHERE b.version_id = policy.in_force('classification', 'UNIVERSITY', current_date) ORDER BY b.ord
                """).query(Sheets.ClassBand.class).list();
    }

    String gradingInstrument() {
        return jdbc.sql("SELECT v.instrument FROM policy.version v WHERE v.id = policy.in_force('grading', 'UNIVERSITY', current_date)")
                .query(String.class).optional().orElse(null);
    }

    /* ── Senate: the schedule by faculty, and the minutes recorded (proto/part26 tSenate, tPublish) ── */

    List<Sheets.SenateFaculty> senateFaculties(String session, int sem) {
        return jdbc.sql("""
                SELECT f.code AS faculty_code, f.name AS faculty_name, count(*) AS sets,
                       count(*) FILTER (WHERE s.stage = 'SENATE') AS at_senate,
                       count(*) FILTER (WHERE s.stage = 'PUBLISHED') AS published,
                       count(*) FILTER (WHERE s.stage NOT IN ('SENATE','PUBLISHED')) AS outstanding,
                       coalesce(sum((SELECT count(*) FROM registration.entry e JOIN registration.course_registration r ON r.id = e.registration_id
                                      WHERE e.offering_id = o.id AND e.status = 'APPROVED' AND r.status IN ('APPROVED','LOCKED'))), 0) AS candidates
                  FROM assessment.score_sheet s
                  JOIN catalogue.offering o ON o.id = s.offering_id
                  JOIN catalogue.course c ON c.code = o.course_code
                  JOIN ref.department d ON d.code = c.dept_code
                  JOIN ref.faculty f ON f.code = d.faculty_code
                 WHERE o.session = :session AND o.semester = :sem
                 GROUP BY f.code, f.name ORDER BY f.name
                """).param("session", session).param("sem", sem).query(Sheets.SenateFaculty.class).list();
    }

    List<Sheets.SenateMinute> senateMinutes(String session, int sem) {
        return jdbc.sql("""
                SELECT s.senate_minute AS minute, min(s.published_at) AS first_published_at, max(s.published_at) AS last_published_at,
                       count(*) AS sets,
                       coalesce(sum((SELECT count(*) FROM registration.entry e JOIN registration.course_registration r ON r.id = e.registration_id
                                      WHERE e.offering_id = o.id AND e.status = 'APPROVED' AND r.status IN ('APPROVED','LOCKED'))), 0) AS candidates
                  FROM assessment.score_sheet s JOIN catalogue.offering o ON o.id = s.offering_id
                 WHERE o.session = :session AND o.semester = :sem AND s.stage = 'PUBLISHED'
                 GROUP BY s.senate_minute ORDER BY min(s.published_at) DESC
                """).param("session", session).param("sem", sem).query(Sheets.SenateMinute.class).list();
    }

    List<UUID> sheetsAtSenate(String session, int sem, String fac) {
        return jdbc.sql("""
                SELECT s.id FROM assessment.score_sheet s
                  JOIN catalogue.offering o ON o.id = s.offering_id
                  JOIN catalogue.course c ON c.code = o.course_code
                  JOIN ref.department d ON d.code = c.dept_code
                 WHERE o.session = :session AND o.semester = :sem AND s.stage = 'SENATE'
                   AND (:fac::text IS NULL OR d.faculty_code = :fac)
                 ORDER BY o.course_code
                """).param("session", session).param("sem", sem).param("fac", fac).query(UUID.class).list();
    }

    /* ── migration from the old portal (V082) ── */

    java.util.Map<String, Object> importStudents(String rowsJson) {
        return jdbc.sql("SELECT * FROM people.import_students(:j::jsonb)").param("j", rowsJson).query().singleRow();
    }

    java.util.Map<String, Object> setDefaultPasswords() {
        return jdbc.sql("SELECT iam.set_migrated_default_passwords() AS updated").query().singleRow();
    }

    java.util.Map<String, Object> setJambNumbers(String rowsJson) {
        return jdbc.sql("SELECT * FROM people.set_jamb_numbers(:j::jsonb)").param("j", rowsJson).query().singleRow();
    }

    java.util.Map<String, Object> importBiography(String rowsJson) {
        return jdbc.sql("SELECT * FROM people.import_biography(:j::jsonb)").param("j", rowsJson).query().singleRow();
    }

    java.util.Map<String, Object> importLegacy(String session, int semester, String rowsJson, boolean withResults) {
        return jdbc.sql("SELECT * FROM assessment.import_legacy_semester(:s, :sem, :j::jsonb, :wr)")
                .param("s", session).param("sem", semester).param("j", rowsJson).param("wr", withResults).query().singleRow();
    }

    /**
     * Store one migrated passport photo, matched to a candidate by JAMB reg no (the picture's file name).
     * When the candidate has an application and the image is an acceptable type/size, it goes into the
     * document store (visible everywhere, incl. the exam card and the dashboard's passportDocumentId);
     * otherwise it goes into the candidate's attachment store (visible on the dashboard, printouts and
     * the receipt). Returns "STORED", "ATTACHED", or "NOT_FOUND" when no candidate matches (the caller skips it).
     */
    String storePassport(String key, String tok, String filename, String contentType, byte[] content, String base64, boolean docOk) {
        if (docOk) {
            List<java.util.Map<String, Object>> app = jdbc.sql("""
                    SELECT a.id AS app_id
                      FROM admissions.application a JOIN admissions.candidate c ON c.id = a.candidate_id
                     WHERE c.jamb_key = :key OR (:tok::text IS NOT NULL AND c.jamb_key = :tok)
                     ORDER BY a.session DESC LIMIT 1
                    """).param("key", key).param("tok", tok, Types.VARCHAR).query().listOfRows();
            if (!app.isEmpty()) {
                UUID appId = (UUID) app.get(0).get("app_id");
                UUID docId = UUID.randomUUID();
                jdbc.sql("UPDATE admissions.application_document SET superseded_at = now() WHERE application_id = :a AND kind = 'PASSPORT' AND superseded_at IS NULL")
                        .param("a", appId).update();
                jdbc.sql("""
                        INSERT INTO admissions.application_document (id, application_id, kind, filename, content_type, bytes, status)
                        VALUES (:id, :a, 'PASSPORT', :f, :t, :b, 'ACCEPTED')
                        """).param("id", docId).param("a", appId).param("f", filename).param("t", contentType).param("b", content.length).update();
                jdbc.sql("INSERT INTO admissions.application_document_blob (document_id, content) VALUES (:id, :c)")
                        .param("id", docId).param("c", content).update();
                return "STORED";
            }
        }
        // a candidate matched by JAMB number (CAPS/applicant-migrated) → candidate-keyed attachment
        List<java.util.Map<String, Object>> cand = jdbc.sql("""
                SELECT id, session, jamb_key FROM admissions.candidate
                 WHERE jamb_key = :key OR (:tok::text IS NOT NULL AND jamb_key = :tok) LIMIT 1
                """).param("key", key).param("tok", tok, Types.VARCHAR).query().listOfRows();
        if (!cand.isEmpty()) {
            UUID cid = (UUID) cand.get(0).get("id");
            String ses = String.valueOf(cand.get(0).get("session"));
            String candKey = String.valueOf(cand.get(0).get("jamb_key"));
            attach(ses, filename, candKey, cid, contentType, base64, content.length, true);
            return "ATTACHED";
        }
        // a student matched by their own JAMB number (a legacy student with no candidate) → jamb-keyed attachment,
        // read back by the student's jamb_reg_no; no candidate is required
        List<java.util.Map<String, Object>> stu = jdbc.sql("""
                SELECT s.candidate_id, s.entry_session, upper(btrim(s.jamb_reg_no)) AS jkey
                  FROM people.student s
                 WHERE s.jamb_reg_no IS NOT NULL
                   AND (upper(btrim(s.jamb_reg_no)) = :key OR (:tok::text IS NOT NULL AND upper(btrim(s.jamb_reg_no)) = :tok))
                 LIMIT 1
                """).param("key", key).param("tok", tok, Types.VARCHAR).query().listOfRows();
        if (stu.isEmpty()) {
            return "NOT_FOUND";
        }
        UUID cid = (UUID) stu.get(0).get("candidate_id");
        String ses = String.valueOf(stu.get(0).get("entry_session"));
        String jkey = String.valueOf(stu.get(0).get("jkey"));
        attach(ses, filename, jkey, cid, contentType, base64, content.length, cid != null);
        return "ATTACHED";
    }

    /** upsert one PASSPORT attachment (a base64 data URL), keyed by (session, source_name); the jamb_key lets a
     *  student without a candidate still read it by their own JAMB number. matched_at is set only with a candidate. */
    private void attach(String session, String filename, String jambKey, UUID candidateId, String contentType, String base64, int bytes, boolean matched) {
        String dataUrl = "data:" + contentType + ";base64," + base64;
        jdbc.sql("""
                INSERT INTO admissions.attachment (id, session, kind, source_name, jamb_key, read_as, candidate_id, matched_at, payload, bytes)
                VALUES (gen_random_uuid(), :ses, 'PASSPORT', :src, :key, 'EXACT', :cid, CASE WHEN :m THEN now() ELSE NULL END,
                        jsonb_build_object('dataUrl', :url::text), :b)
                ON CONFLICT (session, kind, source_name) DO UPDATE
                   SET payload = EXCLUDED.payload, candidate_id = EXCLUDED.candidate_id,
                       matched_at = CASE WHEN :m THEN now() ELSE admissions.attachment.matched_at END,
                       bytes = EXCLUDED.bytes, jamb_key = EXCLUDED.jamb_key, read_as = 'EXACT'
                """).param("ses", session).param("src", filename).param("key", jambKey).param("cid", candidateId, Types.OTHER)
                .param("m", matched).param("url", dataUrl).param("b", bytes).update();
    }
}
