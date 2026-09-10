package ng.edu.moaum.portal.admissions;

import java.sql.Types;
import java.time.LocalDate;
import java.util.Collection;
import java.util.HexFormat;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;
import java.util.stream.Collectors;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;

@Repository
class CapsRepository {

    private static final String BATCH_COLUMNS = """
            id, session, source, filename, encode(file_sha256, 'hex') AS file_sha256, rows_read, list_kind,
            downloaded_on, uploaded_at, uploaded_by, uploaded_office, committed_at, withdrawn_at, withdrawn_reason
            """;

    private final JdbcClient jdbc;

    CapsRepository(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    Optional<CapsBatch> find(UUID id) {
        return jdbc.sql("SELECT " + BATCH_COLUMNS + " FROM admissions.caps_batch WHERE id = :id")
                .param("id", id)
                .query(CapsBatch.class)
                .optional();
    }

    List<CapsBatch> bySession(String session) {
        return jdbc.sql("SELECT " + BATCH_COLUMNS + " FROM admissions.caps_batch WHERE session = :session ORDER BY uploaded_at DESC")
                .param("session", session)
                .query(CapsBatch.class)
                .list();
    }

    void insertBatch(UUID id, String session, String source, String filename, String fileSha256, int rowsRead,
                     String listKind, LocalDate downloadedOn, UUID uploadedBy, String uploadedOffice) {
        jdbc.sql("""
                INSERT INTO admissions.caps_batch
                       (id, session, source, filename, file_sha256, rows_read, list_kind, downloaded_on, uploaded_by, uploaded_office)
                VALUES (:id, :session, :source, :filename, :sha, :rows, :kind, :downloaded, :by, :office)
                """)
                .param("id", id)
                .param("session", session)
                .param("source", source)
                .param("filename", filename, Types.VARCHAR)
                .param("sha", HexFormat.of().parseHex(fileSha256.toLowerCase()))
                .param("rows", rowsRead)
                .param("kind", listKind)
                .param("downloaded", downloadedOn)
                .param("by", uploadedBy)
                .param("office", uploadedOffice)
                .update();
    }

    void insertRow(UUID batchId, String session, CapsRowIn row, String rawJson) {
        jdbc.sql("""
                INSERT INTO admissions.caps_row
                       (id, batch_id, session, jamb_reg_no, raw, surname, other_names, jamb_code, aggregate,
                        sex, state_of_origin, lga, entry_mode)
                VALUES (:id, :batch, :session, :reg, CAST(:raw AS jsonb), :surname, :others, :code, :aggregate,
                        :sex, :state, :lga, :mode)
                """)
                .param("id", UUID.randomUUID())
                .param("batch", batchId)
                .param("session", session)
                .param("reg", row.jambRegNo().trim().toUpperCase())
                .param("raw", rawJson)
                .param("surname", row.surname().trim())
                .param("others", row.otherNames() == null ? "" : row.otherNames().trim())
                .param("code", row.jambCode().trim().toUpperCase())
                .param("aggregate", row.aggregate(), Types.INTEGER)
                .param("sex", row.sex(), Types.VARCHAR)
                .param("state", row.stateOfOrigin(), Types.VARCHAR)
                .param("lga", row.lga(), Types.VARCHAR)
                .param("mode", row.entryMode())
                .update();
    }

    void insertExcluded(UUID batchId, String session, CapsRowIn row, int cutoff, String reason, String rawJson) {
        jdbc.sql("""
                INSERT INTO admissions.caps_row_excluded
                       (id, batch_id, session, jamb_reg_no, jamb_code, surname, other_names, aggregate, cutoff, reason, raw)
                VALUES (:id, :batch, :session, :reg, :code, :surname, :others, :aggregate, :cutoff, :reason, CAST(:raw AS jsonb))
                """)
                .param("id", UUID.randomUUID())
                .param("batch", batchId)
                .param("session", session)
                .param("reg", row.jambRegNo().trim().toUpperCase())
                .param("code", row.jambCode().trim().toUpperCase())
                .param("surname", row.surname().trim())
                .param("others", row.otherNames() == null ? "" : row.otherNames().trim())
                .param("aggregate", row.aggregate(), Types.INTEGER)
                .param("cutoff", cutoff)
                .param("reason", reason)
                .param("raw", rawJson)
                .update();
    }

    /* ── the session's admission settings ───────────────────────────── */

    /** the one UTME cut-off the session loads its lists under (V024), or none while it is not stated */
    Optional<Integer> loadCutoff(String session) {
        return jdbc.sql("SELECT admissions.load_cutoff_for(:s)").param("s", session).query(Integer.class).optional();
    }

    boolean policyInForce(String session) {
        return jdbc.sql("SELECT count(*) FROM admissions.session_policy WHERE session = :session AND state = 'IN_FORCE'")
                .param("session", session)
                .query(Long.class)
                .single() > 0;
    }

    List<AdmissionPolicy.FacultyCutoff> facultyCutoffs(String session) {
        return jdbc.sql("""
                SELECT f.faculty_code, fa.name AS faculty_name, f.quota, f.cutoff, f.ratio_utme, f.ratio_de
                  FROM admissions.faculty_quota f
                  JOIN admissions.session_policy p ON p.id = f.policy_id
                  JOIN ref.faculty fa ON fa.code = f.faculty_code
                 WHERE p.session = :session
                 ORDER BY f.faculty_code
                """)
                .param("session", session)
                .query(AdmissionPolicy.FacultyCutoff.class)
                .list();
    }

    List<AdmissionPolicy.ProgrammeCutoff> programmeCutoffs(String session) {
        return jdbc.sql("""
                SELECT r.programme_code AS code, g.name, r.cutoff
                  FROM admissions.programme_rule r
                  JOIN admissions.session_policy p ON p.id = r.policy_id
                  JOIN ref.programme g ON g.code = r.programme_code
                 WHERE p.session = :session AND r.cutoff IS NOT NULL
                 ORDER BY r.programme_code
                """)
                .param("session", session)
                .query(AdmissionPolicy.ProgrammeCutoff.class)
                .list();
    }

    /**
     * The cut-off that applies to each programme — the database's own answer
     * ({@code admissions.cutoff_for}): the programme's, else its faculty's,
     * and an error if neither is set or no settings are in force.
     */
    Map<String, Integer> cutoffsFor(String session, Collection<String> codes) {
        if (codes.isEmpty()) {
            return Map.of();
        }
        return jdbc.sql("SELECT code, admissions.cutoff_for(:session, code) AS cutoff FROM ref.programme WHERE code IN (:codes)")
                .param("session", session)
                .param("codes", List.copyOf(codes))
                .query((rs, i) -> Map.entry(rs.getString("code"), rs.getInt("cutoff")))
                .list()
                .stream()
                .collect(Collectors.toMap(Map.Entry::getKey, Map.Entry::getValue));
    }

    /** {@code admissions.withdraw_batch}: kept and marked, out of every count, or refused with the database's reason. */
    String withdraw(UUID batchId, String reason) {
        return jdbc.sql("SELECT admissions.withdraw_batch(:id, :reason)").param("id", batchId).param("reason", reason)
                .query(String.class).single();
    }

    String commit(UUID batchId) {
        return jdbc.sql("SELECT admissions.commit_batch(:id)").param("id", batchId).query(String.class).single();
    }

    /** the applicants on committed admission lists for a session, filtered by faculty, programme
     *  and entry mode, and whether each has registered */
    java.util.List<java.util.Map<String, Object>> applicants(String session, String q, String faculty, String programme, String entryMode, int limit) {
        return jdbc.sql("""
                SELECT r.jamb_reg_no, r.surname, r.other_names, r.jamb_code, r.entry_mode, r.aggregate,
                       p.name AS programme, p.faculty_code, fa.name AS faculty, (a.id IS NOT NULL) AS registered, c.offer_state
                  FROM admissions.caps_row_live r
                  JOIN admissions.caps_batch b ON b.id = r.batch_id AND b.committed_at IS NOT NULL
                  LEFT JOIN ref.programme p ON p.code = r.jamb_code
                  LEFT JOIN ref.faculty fa ON fa.code = p.faculty_code
                  LEFT JOIN admissions.candidate c ON c.session = r.session AND c.jamb_reg_no = r.jamb_reg_no
                  LEFT JOIN admissions.applicant_account a ON a.candidate_id = c.id
                 WHERE r.session = :s
                   AND (:q::text IS NULL OR r.surname ILIKE '%' || :q || '%' OR r.other_names ILIKE '%' || :q || '%'
                        OR r.jamb_reg_no ILIKE '%' || :q || '%')
                   AND (:fac::text IS NULL OR p.faculty_code = :fac)
                   AND (:prog::text IS NULL OR r.jamb_code = :prog)
                   AND (:em::text IS NULL OR r.entry_mode = :em)
                 ORDER BY fa.name, p.name, r.surname, r.other_names
                 LIMIT :lim
                """).param("s", session).param("q", q, java.sql.Types.VARCHAR)
                .param("fac", faculty, java.sql.Types.VARCHAR).param("prog", programme, java.sql.Types.VARCHAR)
                .param("em", entryMode, java.sql.Types.VARCHAR).param("lim", limit).query().listOfRows();
    }

    /** the committed admission list broken down by programme, for the current filter — the clear
     *  admitted view: how many are admitted into each programme and how many have registered */
    java.util.List<java.util.Map<String, Object>> applicantBreakdown(String session, String faculty, String programme, String entryMode) {
        return jdbc.sql("""
                SELECT p.faculty_code, fa.name AS faculty, r.jamb_code AS programme_code, p.name AS programme,
                       count(*) AS admitted, count(*) FILTER (WHERE a.id IS NOT NULL) AS registered
                  FROM admissions.caps_row_live r
                  JOIN admissions.caps_batch b ON b.id = r.batch_id AND b.committed_at IS NOT NULL
                  LEFT JOIN ref.programme p ON p.code = r.jamb_code
                  LEFT JOIN ref.faculty fa ON fa.code = p.faculty_code
                  LEFT JOIN admissions.candidate c ON c.session = r.session AND c.jamb_reg_no = r.jamb_reg_no
                  LEFT JOIN admissions.applicant_account a ON a.candidate_id = c.id
                 WHERE r.session = :s
                   AND (:fac::text IS NULL OR p.faculty_code = :fac)
                   AND (:prog::text IS NULL OR r.jamb_code = :prog)
                   AND (:em::text IS NULL OR r.entry_mode = :em)
                 GROUP BY p.faculty_code, fa.name, r.jamb_code, p.name
                 ORDER BY fa.name NULLS LAST, p.name NULLS LAST
                """).param("s", session).param("fac", faculty, java.sql.Types.VARCHAR)
                .param("prog", programme, java.sql.Types.VARCHAR).param("em", entryMode, java.sql.Types.VARCHAR)
                .query().listOfRows();
    }

    /** the programmes whose applicants have registered for post-UTME, with how many are scored,
     *  released and still awaiting a score — the programmes whose scores must be uploaded before
     *  the admission process proceeds */
    java.util.List<java.util.Map<String, Object>> postUtmeProgrammes(String session) {
        return jdbc.sql("""
                WITH app AS (
                    SELECT a.screening_score, a.score_released_at,
                           (SELECT p.code FROM ref.programme p WHERE p.name = c.programme ORDER BY p.archived, p.code LIMIT 1) AS code
                      FROM admissions.application a
                      JOIN admissions.candidate c ON c.id = a.candidate_id
                     WHERE a.session = :s AND a.submitted_at IS NOT NULL
                )
                SELECT pr.code AS programme_code, pr.name AS programme, fa.name AS faculty,
                       count(*) AS registered,
                       count(*) FILTER (WHERE app.screening_score IS NOT NULL) AS scored,
                       count(*) FILTER (WHERE app.score_released_at IS NOT NULL) AS released,
                       count(*) FILTER (WHERE app.screening_score IS NULL) AS awaiting
                  FROM app
                  JOIN ref.programme pr ON pr.code = app.code
                  LEFT JOIN ref.faculty fa ON fa.code = pr.faculty_code
                 GROUP BY pr.code, pr.name, fa.name
                 ORDER BY count(*) FILTER (WHERE app.screening_score IS NULL) DESC, fa.name, pr.name
                """).param("s", session).query().listOfRows();
    }

    /** the merit list for a programme: admissions.merit_list ranks the eligible pool and proposes the offers */
    java.util.List<java.util.Map<String, Object>> meritList(String session, String programme) {
        return jdbc.sql("SELECT * FROM admissions.merit_list(:s, :p)")
                .param("s", session).param("p", programme).query().listOfRows();
    }

    /** whether an application's decision is already released and stands (not to be overwritten) */
    boolean decisionReleased(java.util.UUID app) {
        return Boolean.TRUE.equals(jdbc.sql("SELECT decision_released_at IS NOT NULL FROM admissions.application WHERE id = :id")
                .param("id", app).query(Boolean.class).optional().orElse(false));
    }

    /** record the Board's decision on one application (admissions.decide_application) */
    void decide(java.util.UUID app, String decision, String note, String basis) {
        jdbc.sql("SELECT admissions.decide_application(:a, :d, :n, :b)")
                .param("a", app).param("d", decision).param("n", note, java.sql.Types.VARCHAR).param("b", basis, java.sql.Types.VARCHAR)
                .query().listOfRows();
    }

    java.util.Map<String, Object> applicantCounts(String session, String faculty, String programme, String entryMode) {
        return jdbc.sql("""
                SELECT count(*) AS total,
                       count(*) FILTER (WHERE a.id IS NOT NULL) AS registered
                  FROM admissions.caps_row_live r
                  JOIN admissions.caps_batch b ON b.id = r.batch_id AND b.committed_at IS NOT NULL
                  LEFT JOIN ref.programme p ON p.code = r.jamb_code
                  LEFT JOIN admissions.candidate c ON c.session = r.session AND c.jamb_reg_no = r.jamb_reg_no
                  LEFT JOIN admissions.applicant_account a ON a.candidate_id = c.id
                 WHERE r.session = :s
                   AND (:fac::text IS NULL OR p.faculty_code = :fac)
                   AND (:prog::text IS NULL OR r.jamb_code = :prog)
                   AND (:em::text IS NULL OR r.entry_mode = :em)
                """).param("s", session).param("fac", faculty, java.sql.Types.VARCHAR)
                .param("prog", programme, java.sql.Types.VARCHAR).param("em", entryMode, java.sql.Types.VARCHAR).query().singleRow();
    }

    List<Finding> reconcile(String session) {
        return jdbc.sql("SELECT finding, n, owner, what_it_means FROM admissions.reconcile(:session)")
                .param("session", session)
                .query(Finding.class)
                .list();
    }

    List<Finding> attachmentState(String session) {
        return jdbc.sql("SELECT finding, n, owner, what_it_means FROM admissions.attachment_state(:session)")
                .param("session", session)
                .query(Finding.class)
                .list();
    }

    List<PolicyFinding> policyFindings(String session) {
        return jdbc.sql("SELECT finding, detail, owner FROM admissions.policy_findings(:session)")
                .param("session", session)
                .query(PolicyFinding.class)
                .list();
    }

    List<Programme> programmes() {
        return jdbc.sql("""
                SELECT p.code, p.name, p.dept_code, p.faculty_code, f.name AS faculty_name,
                       a.jamb_name, p.category, p.archived,
                       coalesce((SELECT string_agg(n.jamb_name, E'\n' ORDER BY n.added_at) FROM ref.jamb_alias_name n WHERE n.code = p.code), '') AS more
                  FROM ref.programme p
                  JOIN ref.faculty f ON f.code = p.faculty_code
                  LEFT JOIN ref.jamb_alias a ON a.code = p.code
                 ORDER BY p.code
                """)
                .query((rs, i) -> new Programme(rs.getString("code"), rs.getString("name"), rs.getString("dept_code"),
                        rs.getString("faculty_code"), rs.getString("faculty_name"), rs.getString("jamb_name"),
                        rs.getString("more").isEmpty() ? List.of() : List.of(rs.getString("more").split("\n")),
                        rs.getString("category"), rs.getBoolean("archived")))
                .list();
    }

    /** The code, if any, whose JAMB alias normalises to the same letters and digits. */
    /** the programme a JAMB name means, whether it is the primary alias or a further name */
    Optional<String> codeWithAlias(String normalisedName) {
        return jdbc.sql("""
                SELECT code FROM ref.jamb_alias
                 WHERE lower(regexp_replace(jamb_name, '[^A-Za-z0-9]', '', 'g')) = :name
                UNION
                SELECT code FROM ref.jamb_alias_name WHERE jamb_key = :name
                LIMIT 1
                """)
                .param("name", normalisedName)
                .query(String.class)
                .optional();
    }

    /** whether the primary alias is still the University's own name — the seed's fallback, not a name JAMB gave */
    boolean aliasIsOwnName(String code) {
        return jdbc.sql("""
                SELECT count(*) FROM ref.programme p LEFT JOIN ref.jamb_alias a ON a.code = p.code
                 WHERE p.code = :code AND (a.jamb_name IS NULL
                    OR lower(regexp_replace(a.jamb_name, '[^A-Za-z0-9]', '', 'g')) = lower(regexp_replace(p.name, '[^A-Za-z0-9]', '', 'g')))
                """).param("code", code).query(Long.class).single() > 0;
    }

    /** a further name JAMB uses for the programme, kept beside the primary */
    void addAliasName(String code, String jambName, String normalisedName) {
        jdbc.sql("""
                INSERT INTO ref.jamb_alias_name (jamb_key, jamb_name, code) VALUES (:key, :name, :code)
                ON CONFLICT (jamb_key) DO UPDATE SET jamb_name = EXCLUDED.jamb_name, code = EXCLUDED.code
                """).param("key", normalisedName).param("name", jambName).param("code", code).update();
    }

    void upsertAlias(String code, String jambName) {
        jdbc.sql("""
                INSERT INTO ref.jamb_alias (code, jamb_name) VALUES (:code, :name)
                ON CONFLICT (code) DO UPDATE SET jamb_name = EXCLUDED.jamb_name
                """)
                .param("code", code)
                .param("name", jambName)
                .update();
    }

    Optional<Programme> programme(String code) {
        return programmes().stream().filter(p -> p.code().equals(code)).findFirst();
    }

    /** The faculty a live department belongs to, or none when the code is unknown or the department has ended. */
    Optional<String> facultyOfDepartment(String deptCode) {
        return jdbc.sql("SELECT faculty_code FROM ref.department WHERE code = :d AND ended_on IS NULL")
                .param("d", deptCode).query(String.class).optional();
    }

    /** The University's own words for a programme: the name, its department (and so its faculty), its category, and whether it still admits. */
    void updateProgramme(String code, String name, String deptCode, String facultyCode, String category, boolean archived) {
        jdbc.sql("""
                UPDATE ref.programme
                   SET name = :name, dept_code = :dept, faculty_code = :fac, category = :cat, archived = :archived
                 WHERE code = :code
                """)
                .param("code", code).param("name", name).param("dept", deptCode).param("fac", facultyCode)
                .param("cat", category).param("archived", archived)
                .update();
    }

    Optional<String> regNoIn(String text) {
        return jdbc.sql("SELECT admissions.reg_no_in(:text)").param("text", text).query(String.class).optional();
    }
}
