package ng.edu.moaum.portal.results;

import ng.edu.moaum.portal.shared.FileObjects;
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
            SELECT s.id, o.course_code, coalesce(o.title, c.title) AS course_title, coalesce(o.units, c.units) AS units, c.ca_max, c.dept_code, d.name AS dept_name,
                   d.faculty_code, f.name AS faculty_name, o.session, o.semester, s.stage, s.due_on, s.submitted_at,
                   s.returned_times, o.lecturer_id, coalesce(es.kind, 'MAIN') AS sitting,
                   CASE WHEN p.id IS NULL THEN NULL ELSE p.surname || ', ' || p.given_names END AS lecturer,
                   (SELECT count(*) FROM assessment.sheet_candidates(s.id)) AS candidates,
                   (SELECT count(*) FROM assessment.sheet_candidates(s.id) c
                     WHERE EXISTS (SELECT 1 FROM assessment.score sc WHERE sc.sheet_id = s.id AND sc.student_id = c.student_id)) AS received,
                   (SELECT count(*) FROM assessment.held_script h WHERE h.sheet_id = s.id AND h.state = 'HELD') AS held_scripts,
                   (SELECT count(*) FROM assessment.latest_scores(s.id) WHERE outcome = 'GRADED') AS graded,
                   (SELECT count(*) FROM assessment.latest_scores(s.id) WHERE outcome = 'GRADED' AND points = 0) AS failed,
                   (SELECT dd.actor_id FROM assessment.decision dd WHERE dd.sheet_id = s.id AND dd.kind IN ('SUBMIT','ADVANCE')
                     ORDER BY dd.decided_at DESC LIMIT 1) AS last_actor,
                   c.general_office
              FROM assessment.score_sheet s
              JOIN catalogue.offering o ON o.id = s.offering_id
              JOIN catalogue.course c ON c.code = o.course_code
              JOIN ref.department d ON d.code = c.dept_code
              JOIN ref.faculty f ON f.code = d.faculty_code
              LEFT JOIN assessment.exam_session es ON es.id = s.exam_session_id
              LEFT JOIN iam.person p ON p.id = o.lecturer_id
            """;

    private final FileObjects files;
    private final JdbcClient jdbc;

    ResultsRepository(FileObjects files, JdbcClient jdbc) {
        this.jdbc = jdbc;
        this.files = files;
    }

    List<Sheets.Row> sheets(String fac, String dept, String prog, String course, String session, Integer sem, String stage, UUID mine) {
        return jdbc.sql(SHEET_SELECT + """
                 WHERE (:fac::text IS NULL OR d.faculty_code = :fac)
                   AND (:dept::text IS NULL OR c.dept_code = :dept)
                   AND (:prog::text IS NULL OR catalogue.offering_serves(o.id, :prog))
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

    long offeringsWithLecturer(String fac, String dept, String prog, String session, Integer sem, UUID mine) {
        return jdbc.sql("""
                SELECT count(*) FROM catalogue.offering o JOIN catalogue.course c ON c.code = o.course_code
                  JOIN ref.department d ON d.code = c.dept_code
                 WHERE o.lecturer_id IS NOT NULL
                   AND (:fac::text IS NULL OR d.faculty_code = :fac) AND (:dept::text IS NULL OR c.dept_code = :dept)
                   AND (:prog::text IS NULL OR catalogue.offering_serves(o.id, :prog))
                   AND (:session::text IS NULL OR o.session = :session) AND (:sem::int IS NULL OR o.semester = :sem)
                   AND (:mine::uuid IS NULL OR o.lecturer_id = :mine OR o.second_examiner_id = :mine
                        OR EXISTS (SELECT 1 FROM catalogue.offering_teacher t WHERE t.offering_id = o.id AND t.lecturer_id = :mine))
                """).param("fac", fac).param("dept", dept).param("prog", prog).param("session", session).param("sem", sem).param("mine", mine)
                .query(Long.class).single();
    }

    /* ── V318: the pipeline monitor ── */

    /** the session in progress, or the latest one on the calendar */
    String currentSession() {
        return jdbc.sql("""
                SELECT name FROM policy.academic_session
                 ORDER BY (state = 'CURRENT') DESC, (current_date BETWEEN starts_on AND ends_on) DESC, starts_on DESC LIMIT 1
                """).query(String.class).optional().orElse("2026/2027");
    }

    /** the offerings in scope for the period: all of them, and those with a lecturer (a sheet opens only over those) */
    record OfferingsCount(long offerings, long withLecturer) {
    }

    OfferingsCount offeringsInScope(String fac, String dept, String prog, String session, Integer sem, UUID mine) {
        return jdbc.sql("""
                SELECT count(*) AS offerings, count(*) FILTER (WHERE o.lecturer_id IS NOT NULL) AS with_lecturer
                  FROM catalogue.offering o JOIN catalogue.course c ON c.code = o.course_code
                  JOIN ref.department d ON d.code = c.dept_code
                 WHERE (:fac::text IS NULL OR d.faculty_code = :fac) AND (:dept::text IS NULL OR c.dept_code = :dept)
                   AND (:prog::text IS NULL OR catalogue.offering_serves(o.id, :prog))
                   AND o.session = :session AND (:sem::int IS NULL OR o.semester = :sem)
                   AND (:mine::uuid IS NULL OR o.lecturer_id = :mine OR o.second_examiner_id = :mine
                        OR EXISTS (SELECT 1 FROM catalogue.offering_teacher t WHERE t.offering_id = o.id AND t.lecturer_id = :mine))
                """).param("fac", fac).param("dept", dept).param("prog", prog).param("session", session).param("sem", sem).param("mine", mine)
                .query(OfferingsCount.class).single();
    }

    /** one sheet as the monitor reads it: the listing's row with its coverage, when it reached its stage, and the uploads on behalf */
    record ProgressRow(UUID id, String courseCode, String courseTitle, int units, String deptCode, String deptName, String facultyCode,
                       String facultyName, String session, int semester, String sitting, String stage, LocalDate dueOn, int returnedTimes,
                       UUID lecturerId, String lecturer, long candidates, long received, long missing, long graded, long failed,
                       long heldScripts, long uploadsOnBehalf, java.time.OffsetDateTime stageSince, UUID lastActor, String generalOffice) {
    }

    List<ProgressRow> progress(String fac, String dept, String prog, String session, Integer sem, UUID mine) {
        return jdbc.sql("""
                SELECT s.id, o.course_code, coalesce(o.title, c.title) AS course_title, coalesce(o.units, c.units) AS units, c.dept_code, d.name AS dept_name, d.faculty_code, f.name AS faculty_name,
                       o.session, o.semester, coalesce(es.kind, 'MAIN') AS sitting, s.stage, s.due_on, s.returned_times, o.lecturer_id,
                       CASE WHEN p.id IS NULL THEN NULL ELSE p.surname || ', ' || p.given_names END AS lecturer,
                       cv.expected AS candidates, cv.received, cv.missing, cv.graded,
                       (SELECT count(*) FROM assessment.latest_scores(s.id) WHERE outcome = 'GRADED' AND points = 0) AS failed,
                       (SELECT count(*) FROM assessment.held_script h WHERE h.sheet_id = s.id AND h.state = 'HELD') AS held_scripts,
                       (SELECT count(*) FROM assessment.sheet_upload u WHERE u.sheet_id = s.id) AS uploads_on_behalf,
                       assessment.sheet_stage_since(s.id) AS stage_since,
                       (SELECT dd.actor_id FROM assessment.decision dd WHERE dd.sheet_id = s.id AND dd.kind IN ('SUBMIT','ADVANCE')
                         ORDER BY dd.decided_at DESC LIMIT 1) AS last_actor,
                       c.general_office
                  FROM assessment.score_sheet s
                  JOIN catalogue.offering o ON o.id = s.offering_id
                  JOIN catalogue.course c ON c.code = o.course_code
                  JOIN ref.department d ON d.code = c.dept_code
                  JOIN ref.faculty f ON f.code = d.faculty_code
                  LEFT JOIN assessment.exam_session es ON es.id = s.exam_session_id
                  LEFT JOIN iam.person p ON p.id = o.lecturer_id
                  CROSS JOIN LATERAL assessment.sheet_coverage(s.id) cv
                 WHERE (:fac::text IS NULL OR d.faculty_code = :fac)
                   AND (:dept::text IS NULL OR c.dept_code = :dept)
                   AND (:prog::text IS NULL OR catalogue.offering_serves(o.id, :prog))
                   AND o.session = :session AND (:sem::int IS NULL OR o.semester = :sem)
                   AND (:mine::uuid IS NULL OR o.lecturer_id = :mine OR o.second_examiner_id = :mine
                        OR EXISTS (SELECT 1 FROM catalogue.offering_teacher t WHERE t.offering_id = o.id AND t.lecturer_id = :mine))
                 ORDER BY f.name, d.name, o.course_code
                """).param("fac", fac).param("dept", dept).param("prog", prog).param("session", session).param("sem", sem).param("mine", mine)
                .query(ProgressRow.class).list();
    }

    /** an offering in scope with registered candidates and no sheet: no lecturer allocated, or the session not opened over it */
    record NoSheetRow(UUID offeringId, String courseCode, String courseTitle, String deptName, String lecturer, long candidates, boolean noLecturer) {
    }

    List<NoSheetRow> offeringsWithoutSheet(String fac, String dept, String prog, String session, Integer sem, UUID mine) {
        return jdbc.sql("""
                SELECT o.id AS offering_id, o.course_code, coalesce(o.title, c.title) AS course_title, d.name AS dept_name,
                       CASE WHEN p.id IS NULL THEN NULL ELSE p.surname || ', ' || p.given_names END AS lecturer,
                       cand.n AS candidates, o.lecturer_id IS NULL AS no_lecturer
                  FROM catalogue.offering o
                  JOIN catalogue.course c ON c.code = o.course_code
                  JOIN ref.department d ON d.code = c.dept_code
                  LEFT JOIN iam.person p ON p.id = o.lecturer_id
                  CROSS JOIN LATERAL (SELECT count(*) AS n FROM registration.entry e JOIN registration.course_registration r ON r.id = e.registration_id
                                       WHERE e.offering_id = o.id AND e.status = 'APPROVED' AND r.status IN ('APPROVED','LOCKED')) cand
                 WHERE NOT EXISTS (SELECT 1 FROM assessment.score_sheet s WHERE s.offering_id = o.id)
                   AND cand.n > 0
                   AND (:fac::text IS NULL OR d.faculty_code = :fac)
                   AND (:dept::text IS NULL OR c.dept_code = :dept)
                   AND (:prog::text IS NULL OR catalogue.offering_serves(o.id, :prog))
                   AND o.session = :session AND (:sem::int IS NULL OR o.semester = :sem)
                   AND (:mine::uuid IS NULL OR o.lecturer_id = :mine OR o.second_examiner_id = :mine
                        OR EXISTS (SELECT 1 FROM catalogue.offering_teacher t WHERE t.offering_id = o.id AND t.lecturer_id = :mine))
                 ORDER BY d.name, o.course_code
                """).param("fac", fac).param("dept", dept).param("prog", prog).param("session", session).param("sem", sem).param("mine", mine)
                .query(NoSheetRow.class).list();
    }

    /** the last events on the record in scope: the chain's decisions and the uploads on behalf, newest first */
    List<Sheets.TimelineEvent> timeline(String fac, String dept, String prog, String session, Integer sem, UUID mine, int limit) {
        return jdbc.sql("""
                WITH scoped AS (
                    SELECT s.id, o.course_code
                      FROM assessment.score_sheet s
                      JOIN catalogue.offering o ON o.id = s.offering_id
                      JOIN catalogue.course c ON c.code = o.course_code
                      JOIN ref.department d ON d.code = c.dept_code
                     WHERE (:fac::text IS NULL OR d.faculty_code = :fac)
                       AND (:dept::text IS NULL OR c.dept_code = :dept)
                       AND (:prog::text IS NULL OR catalogue.offering_serves(o.id, :prog))
                       AND o.session = :session AND (:sem::int IS NULL OR o.semester = :sem)
                       AND (:mine::uuid IS NULL OR o.lecturer_id = :mine OR o.second_examiner_id = :mine
                            OR EXISTS (SELECT 1 FROM catalogue.offering_teacher t WHERE t.offering_id = o.id AND t.lecturer_id = :mine)))
                SELECT x.sheet_id, x.course_code, x.from_stage, x.to_stage, x.kind, x.actor_office,
                       CASE WHEN p.id IS NULL THEN NULL ELSE p.surname || ', ' || p.given_names END AS actor, x.comment, x.decided_at
                  FROM (
                    SELECT d.sheet_id, sc.course_code, d.from_stage, d.to_stage, d.kind, d.actor_office, d.actor_id, d.comment, d.decided_at
                      FROM assessment.decision d JOIN scoped sc ON sc.id = d.sheet_id
                    UNION ALL
                    SELECT u.sheet_id, sc.course_code, 'ENTRY', 'ENTRY', 'UPLOAD_ON_BEHALF', u.uploader_office, u.uploaded_by,
                           u.reason || ' (' || u.rows_written || ' mark' || CASE WHEN u.rows_written = 1 THEN '' ELSE 's' END || ')', u.uploaded_at
                      FROM assessment.sheet_upload u JOIN scoped sc ON sc.id = u.sheet_id
                  ) x
                  LEFT JOIN iam.person p ON p.id = x.actor_id
                 ORDER BY x.decided_at DESC
                 LIMIT :limit
                """).param("fac", fac).param("dept", dept).param("prog", prog).param("session", session).param("sem", sem).param("mine", mine)
                .param("limit", limit).query(Sheets.TimelineEvent.class).list();
    }

    /** every programme and level in scope with an approved registration this period: the cells its broadsheet expects, the marks in, the sets published */
    List<Sheets.ProgrammeLevel> programmeCoverage(String fac, String dept, String prog, String session, Integer sem, UUID mine) {
        return jdbc.sql("""
                WITH sh AS (
                    SELECT s.id, s.offering_id, s.stage
                      FROM assessment.score_sheet s JOIN catalogue.offering o ON o.id = s.offering_id
                     WHERE o.session = :session AND (:sem::int IS NULL OR o.semester = :sem)
                ), sc AS (
                    SELECT sh.offering_id, ls.student_id FROM sh CROSS JOIN LATERAL assessment.latest_scores(sh.id) ls
                )
                SELECT st.programme_code, pr.name AS programme_name, pr.dept_code, d.name AS dept_name, r.level,
                       count(DISTINCT r.student_id) AS students, count(*) AS cells,
                       count(sc.student_id) AS received, count(*) - count(sc.student_id) AS missing,
                       count(*) FILTER (WHERE sh.stage = 'PUBLISHED') AS published,
                       CASE WHEN count(*) = 0 THEN 0 ELSE (100 * count(sc.student_id) / count(*))::int END AS percent
                  FROM registration.course_registration r
                  JOIN registration.entry e ON e.registration_id = r.id AND e.status = 'APPROVED'
                  JOIN people.student st ON st.id = r.student_id
                  JOIN ref.programme pr ON pr.code = st.programme_code
                  JOIN ref.department d ON d.code = pr.dept_code
                  JOIN catalogue.offering o ON o.id = e.offering_id
                  LEFT JOIN sh ON sh.offering_id = o.id
                  LEFT JOIN sc ON sc.offering_id = o.id AND sc.student_id = r.student_id
                 WHERE r.session = :session AND (:sem::int IS NULL OR r.semester = :sem) AND r.status IN ('APPROVED','LOCKED')
                   AND (:fac::text IS NULL OR d.faculty_code = :fac)
                   AND (:dept::text IS NULL OR pr.dept_code = :dept)
                   AND (:prog::text IS NULL OR st.programme_code = :prog)
                   AND (:mine::uuid IS NULL OR o.lecturer_id = :mine OR o.second_examiner_id = :mine
                        OR EXISTS (SELECT 1 FROM catalogue.offering_teacher t WHERE t.offering_id = o.id AND t.lecturer_id = :mine))
                 GROUP BY st.programme_code, pr.name, pr.dept_code, d.name, r.level
                 ORDER BY d.name, pr.name, r.level
                """).param("fac", fac).param("dept", dept).param("prog", prog).param("session", session).param("sem", sem).param("mine", mine)
                .query(Sheets.ProgrammeLevel.class).list();
    }

    /** true when the sheet serves the programme: its course is offered to the programme, or a student of the programme is on its roll */
    boolean sheetServesProgramme(UUID sheetId, String prog) {
        return jdbc.sql("""
                SELECT EXISTS (
                  SELECT 1 FROM assessment.score_sheet s JOIN catalogue.offering o ON o.id = s.offering_id
                   WHERE s.id = :id
                     AND catalogue.offering_serves(o.id, :p))
                """).param("id", sheetId).param("p", prog).query(Boolean.class).single();
    }

    /** the uploads made on the lecturer's behalf on a sheet (V318), newest first */
    List<Sheets.Upload> uploads(UUID sheetId) {
        return jdbc.sql("""
                SELECT u.id, u.uploaded_by AS uploaded_by_id,
                       CASE WHEN p.id IS NULL THEN NULL ELSE p.surname || ', ' || p.given_names END AS uploaded_by,
                       u.uploader_office,
                       CASE WHEN w.id IS NULL THEN NULL ELSE w.surname || ', ' || w.given_names END AS owner,
                       u.reason, u.rows_written, u.uploaded_at
                  FROM assessment.sheet_upload u
                  LEFT JOIN iam.person p ON p.id = u.uploaded_by
                  LEFT JOIN iam.person w ON w.id = u.owner_id
                 WHERE u.sheet_id = :id ORDER BY u.uploaded_at DESC
                """).param("id", sheetId).query(Sheets.Upload.class).list();
    }

    /** the record of an upload on behalf: refused by the database without a reason, or when the actor teaches the course */
    UUID recordUploadOnBehalf(UUID sheetId, String reason, int rows) {
        return jdbc.sql("SELECT assessment.record_upload_on_behalf(:s, :r, :n)").param("s", sheetId)
                .param("r", reason, Types.VARCHAR).param("n", rows).query(UUID.class).single();
    }

    /** the lecturer of record is told of an upload made on their behalf (V318): an e-mail notice through the platform's
     *  queue, when the lecturer has an address; nothing otherwise, and never a failure of the upload */
    void tellLecturerOfUpload(UUID sheetId, UUID uploadId, String uploader, String office, String reason, int rows) {
        jdbc.sql("""
                SELECT platform.queue_notice('EMAIL', p.email,
                           o.course_code || ': marks entered on your behalf',
                           format('%s marks were entered on the score sheet of %s (%s, %s semester %s) on your behalf by %s (%s). Reason given: %s. '
                                  || 'You remain the academic owner of the sheet; it passes verification, the Departmental Board, the Faculty and Senate as any other.',
                                  :rows, o.course_code, o.session, o.semester, p.surname, :by, :office, :reason),
                           'score_sheet', :sheet)
                  FROM assessment.score_sheet s JOIN catalogue.offering o ON o.id = s.offering_id JOIN iam.person p ON p.id = o.lecturer_id
                 WHERE s.id = :sheet AND nullif(btrim(coalesce(p.email, '')), '') IS NOT NULL
                """).param("rows", rows).param("by", uploader == null ? "the office" : uploader).param("office", office)
                .param("reason", reason).param("sheet", sheetId).query().listOfRows();
    }

    /** the acting person's name, for a notice */
    String personName(UUID id) {
        return jdbc.sql("SELECT surname || ', ' || given_names FROM iam.person WHERE id = :id").param("id", id).query(String.class).optional().orElse(null);
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
                       l.ca, l.exam, l.total, l.grade, l.points, l.outcome, l.version, l.amended,
                       CASE WHEN w.id IS NULL THEN NULL ELSE w.surname || ', ' || w.given_names END AS entered_by,
                       sc.entered_office, sc.on_behalf
                  FROM assessment.latest_scores(:id) l JOIN people.student st ON st.id = l.student_id
                  JOIN assessment.score sc ON sc.sheet_id = :id AND sc.student_id = l.student_id AND sc.version = l.version
                  LEFT JOIN iam.person w ON w.id = sc.entered_by
                 ORDER BY st.surname, st.other_names
                """).param("id", sheetId).query(Sheets.Mark.class).list();
    }

    record Latest(Integer ca, Integer exam, String outcome, int version) {
    }

    Optional<Latest> latest(UUID sheetId, UUID studentId) {
        return jdbc.sql("SELECT ca, exam, outcome, version FROM assessment.latest_scores(:s) WHERE student_id = :st")
                .param("s", sheetId).param("st", studentId).query(Latest.class).optional();
    }

    /** true when the sheet's latest decision is a return: it is at entry again because a desk sent it back */
    boolean returnedToEntry(UUID sheetId) {
        return jdbc.sql("""
                SELECT coalesce((SELECT d.kind = 'RETURN' FROM assessment.decision d
                                  WHERE d.sheet_id = :id ORDER BY d.decided_at DESC LIMIT 1), false)
                """).param("id", sheetId).query(Boolean.class).single();
    }

    void score(UUID sheetId, UUID studentId, int version, Integer ca, Integer exam, String outcome, String reason) {
        score(sheetId, studentId, version, ca, exam, outcome, reason, null);
    }

    /** a version of a mark; with an on-behalf reason it is written as an entry on the lecturer's behalf (V318) — the
     *  writer and their office are filled in by the record from the attributed transaction */
    void score(UUID sheetId, UUID studentId, int version, Integer ca, Integer exam, String outcome, String reason, String onBehalfReason) {
        jdbc.sql("""
                INSERT INTO assessment.score (sheet_id, student_id, version, ca, exam, outcome, reason, on_behalf, on_behalf_reason)
                VALUES (:s, :st, :v, :ca, :exam, :o, :r, :b::text IS NOT NULL, :b)
                """).param("s", sheetId).param("st", studentId).param("v", version)
                .param("ca", ca, Types.INTEGER).param("exam", exam, Types.INTEGER).param("o", outcome)
                .param("r", reason, Types.VARCHAR).param("b", onBehalfReason, Types.VARCHAR).update();
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
                       (SELECT count(*) FROM assessment.score_sheet s WHERE s.exam_session_id = e.id AND s.stage = 'ENTRY') AS outstanding,
                       e.cards_released_at, e.sheets_released_at
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

    /** V335: the score sheets released to the lecturers — made now, over the offerings with a lecturer */
    Opened releaseSheets(UUID id) {
        return jdbc.sql("SELECT sheets_made, offerings_without_lecturer FROM assessment.release_exam_sheets(:id)")
                .param("id", id).query(Opened.class).single();
    }

    /** V335: the examination cards released to the students, or withdrawn */
    java.time.OffsetDateTime releaseCards(UUID id, boolean release) {
        return jdbc.sql("SELECT assessment.release_exam_cards(:id, :r)").param("id", id).param("r", release)
                .query(java.time.OffsetDateTime.class).optional().orElse(null);
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
                   LocalDate dueOn, int returnedTimes, long candidates, long entered, long graded, String secondExaminer, UUID lecturerId,
                   long openQueries, long bankQuestions, long caEntered, long heldScripts) {
    }

    List<MineRow> mine(UUID person, String session, Integer sem, boolean all) {
        return jdbc.sql("""
                SELECT s.id, o.course_code, coalesce(o.title, c.title) AS course_title, coalesce(o.units, c.units) AS units, o.session, o.semester, s.stage, s.due_on, s.returned_times,
                       (SELECT count(*) FROM registration.entry e JOIN registration.course_registration r ON r.id = e.registration_id
                         WHERE e.offering_id = o.id AND e.status = 'APPROVED' AND r.status IN ('APPROVED','LOCKED')) AS candidates,
                       (SELECT count(*) FROM assessment.latest_scores(s.id)) AS entered,
                       (SELECT count(*) FROM assessment.latest_scores(s.id) WHERE outcome = 'GRADED') AS graded,
                       CASE WHEN x.id IS NULL THEN NULL ELSE x.surname || ', ' || x.given_names END AS second_examiner,
                       o.lecturer_id,
                       (SELECT count(*) FROM assessment.result_query rq WHERE rq.sheet_id = s.id AND rq.state = 'RAISED') AS open_queries,
                       (SELECT count(*) FROM assessment.question q WHERE q.course_code = c.code AND q.active) AS bank_questions,
                       (SELECT count(*) FROM assessment.latest_scores(s.id) WHERE ca IS NOT NULL) AS ca_entered,
                       (SELECT count(*) FROM assessment.held_script h WHERE h.sheet_id = s.id AND h.state = 'HELD') AS held_scripts
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

    /** true when the person carries the sheet's offering — as its lecturer, its second examiner or a co-lecturer */
    boolean teaches(UUID sheetId, UUID person) {
        return jdbc.sql("""
                SELECT EXISTS (
                  SELECT 1 FROM assessment.score_sheet s JOIN catalogue.offering o ON o.id = s.offering_id
                   WHERE s.id = :id AND (o.lecturer_id = :me OR o.second_examiner_id = :me
                      OR EXISTS (SELECT 1 FROM catalogue.offering_teacher t WHERE t.offering_id = o.id AND t.lecturer_id = :me)))
                """).param("id", sheetId).param("me", person).query(Boolean.class).single();
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
                 ORDER BY coalesce(st.matric_no, st.admission_no), st.surname, st.other_names
                """).param("id", sheetId).query(Sheets.RollRow.class).list();
    }

    /* ── the broadsheet: computed from the sheets, by programme and level (proto/part26 tBroadsheet) ── */

    List<Sheets.BroadsheetCell> broadsheet(String prog, int level, String session, int sem) {
        return jdbc.sql("""
                SELECT st.id AS student_id, coalesce(st.matric_no, st.admission_no) AS number, st.surname, st.other_names, st.entry_mode,
                       o.course_code, coalesce(o.title, c.title) AS title, e.units, coalesce(c.kind, 'Core') AS kind, c.level AS course_level, coalesce(cf.stage, 'NO_SHEET') AS stage, cf.total, cf.grade, cf.points, cf.outcome,
                       cf.sheet_id
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

    /** a student in the class — registered at this level this session in another semester, or at this level now in the
     *  session in progress — with no approved registration for the semester: on the sheet as DID NOT REGISTER */
    record ClassMember(UUID studentId, String number, String surname, String otherNames, String entryMode) {
    }

    List<ClassMember> unregistered(String prog, int level, String session, int sem) {
        return jdbc.sql("""
                SELECT st.id AS student_id, coalesce(st.matric_no, st.admission_no) AS number, st.surname, st.other_names, st.entry_mode
                  FROM people.student st
                 WHERE st.programme_code = :prog
                   AND (EXISTS (SELECT 1 FROM registration.course_registration r
                                 WHERE r.student_id = st.id AND r.session = :session AND r.level = :level AND r.status IN ('APPROVED','LOCKED'))
                        OR (st.current_level = :level AND st.status IN ('ACTIVE','PROBATION')
                            AND EXISTS (SELECT 1 FROM policy.academic_session s WHERE s.name = :session AND current_date BETWEEN s.starts_on AND s.ends_on)))
                   AND NOT EXISTS (SELECT 1 FROM registration.course_registration r
                                    WHERE r.student_id = st.id AND r.session = :session AND r.semester = :sem AND r.status IN ('APPROVED','LOCKED'))
                 ORDER BY st.surname, st.other_names
                """).param("prog", prog).param("level", level).param("session", session).param("sem", sem)
                .query(ClassMember.class).list();
    }

    /** Senate's rule on a semester's cumulative standing (V246, assessment.standing_of): PROBATION, ADVISED_TO_WITHDRAW, or null */
    String standingOf(int level, int sem, java.math.BigDecimal cgpa, java.math.BigDecimal prevCgpa, boolean deAt200) {
        return jdbc.sql("SELECT assessment.standing_of(:l, :s, :c::numeric, :p::numeric, :de)")
                .param("l", level).param("s", sem).param("c", cgpa).param("p", prevCgpa).param("de", deAt200)
                .query(String.class).optional().orElse(null);
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

    java.util.Map<String, Object> importPostgraduate(String rowsJson) {
        return jdbc.sql("SELECT * FROM people.import_postgraduate(:j::jsonb)").param("j", rowsJson).query().singleRow();
    }

    java.util.Map<String, Object> reconcileHolding() {
        return jdbc.sql("SELECT * FROM assessment.reconcile_legacy_holding()").query().singleRow();
    }

    java.util.Map<String, Object> importBiography(String rowsJson) {
        return jdbc.sql("SELECT * FROM people.import_biography(:j::jsonb)").param("j", rowsJson).query().singleRow();
    }

    java.util.Map<String, Object> importLegacy(String session, int semester, String rowsJson, boolean withResults) {
        return jdbc.sql("SELECT * FROM assessment.import_legacy_semester(:s, :sem, :j::jsonb, :wr)")
                .param("s", session).param("sem", semester).param("j", rowsJson).param("wr", withResults).query().singleRow();
    }

    java.util.Map<String, Object> importLegacyPg(String session, int semester, String rowsJson, boolean withResults) {
        return jdbc.sql("SELECT * FROM admissions.import_legacy_pg_semester(:s, :sem, :j::jsonb, :wr)")
                .param("s", session).param("sem", semester).param("j", rowsJson).param("wr", withResults).query().singleRow();
    }

    java.util.Map<String, Object> reconcilePgHolding() {
        return jdbc.sql("SELECT * FROM admissions.pg_reconcile_legacy_holding()").query().singleRow();
    }

    java.util.Map<String, Object> importPgResearch(String rowsJson) {
        return jdbc.sql("SELECT * FROM admissions.import_legacy_pg_research(:j::jsonb)").param("j", rowsJson).query().singleRow();
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
                // the same photograph already current for this application: nothing to write, nothing to upload
                boolean same = jdbc.sql("""
                        SELECT (b.content IS NOT NULL AND sha256(b.content) = :h) OR (f.sha256 = :h)
                          FROM admissions.application_document d
                          JOIN admissions.application_document_blob b ON b.document_id = d.id
                          LEFT JOIN platform.file_object f ON f.id = b.object_id
                         WHERE d.application_id = :a AND d.kind = 'PASSPORT' AND d.superseded_at IS NULL
                         ORDER BY d.id LIMIT 1
                        """).param("a", appId).param("h", ng.edu.moaum.portal.shared.FileObjects.sha256(content)).query(Boolean.class).optional().orElse(false);
                if (same) {
                    return "STORED";
                }
                UUID docId = UUID.randomUUID();
                jdbc.sql("UPDATE admissions.application_document SET superseded_at = now() WHERE application_id = :a AND kind = 'PASSPORT' AND superseded_at IS NULL")
                        .param("a", appId).update();
                jdbc.sql("""
                        INSERT INTO admissions.application_document (id, application_id, kind, filename, content_type, bytes, status)
                        VALUES (:id, :a, 'PASSPORT', :f, :t, :b, 'ACCEPTED')
                        """).param("id", docId).param("a", appId).param("f", filename).param("t", contentType).param("b", content.length).update();
                UUID oid = files.store("admissions.application_document", docId, filename, contentType, content);
                jdbc.sql("INSERT INTO admissions.application_document_blob (document_id, content, object_id) VALUES (:id, :c, :o)")
                        .param("id", docId).param("c", oid == null ? content : null, Types.BINARY).param("o", oid, Types.OTHER).update();
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
        UUID previous = jdbc.sql("SELECT object_id FROM admissions.attachment WHERE session = :ses AND kind = 'PASSPORT' AND source_name = :src")
                .param("ses", session).param("src", filename).query(UUID.class).optional().orElse(null);
        UUID oid = files.enabled() ? files.store("admissions.attachment", jambKey, filename, contentType, java.util.Base64.getDecoder().decode(base64)) : null;
        jdbc.sql("""
                INSERT INTO admissions.attachment (id, session, kind, source_name, jamb_key, read_as, candidate_id, matched_at, payload, bytes, object_id)
                VALUES (gen_random_uuid(), :ses, 'PASSPORT', :src, :key, 'EXACT', :cid, CASE WHEN :m THEN now() ELSE NULL END,
                        CASE WHEN :o::uuid IS NULL THEN jsonb_build_object('dataUrl', :url::text) ELSE '{}'::jsonb END, :b, :o)
                ON CONFLICT (session, kind, source_name) DO UPDATE
                   SET payload = EXCLUDED.payload, candidate_id = EXCLUDED.candidate_id, object_id = EXCLUDED.object_id,
                       matched_at = CASE WHEN :m THEN now() ELSE admissions.attachment.matched_at END,
                       bytes = EXCLUDED.bytes, jamb_key = EXCLUDED.jamb_key, read_as = 'EXACT'
                """).param("ses", session).param("src", filename).param("key", jambKey).param("cid", candidateId, Types.OTHER)
                .param("m", matched).param("url", dataUrl).param("b", bytes).param("o", oid, Types.OTHER).update();
        if (previous != null && !previous.equals(oid)) {
            files.forget(previous);   // a different photograph replaced it; the old object is no longer held by any row
        }
    }
}
