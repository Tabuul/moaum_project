package ng.edu.moaum.portal.stats;

import java.sql.Types;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;

import ng.edu.moaum.portal.shared.AuditContextHolder;
import ng.edu.moaum.portal.stats.AnalyticsScope.Bound;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.stereotype.Service;

/**
 * The student query engine (V469): every learner the University has — the register, the JUPEB learners and the
 * Preliminary learners — read from one view, people.learner, classified by people.student_classification. The list,
 * the figures by programme type and the filter options are three readings of one WHERE clause, so a card, a list and
 * an export can never count differently.
 *
 * <p>The acting office's scope is added here and nowhere else, from the server's own record of the office: a Dean is held
 * to their faculty, a Head to their department, the College's offices to the College, and an office whose students are
 * one programme type (the School of Postgraduate Studies, the CCE, JUPEB, Preliminary and Sandwich offices —
 * finance.programme_type.offices) to that type. A filter outside the scope returns nothing; it never widens it. The SQL
 * is fixed text: every value the officer chose is a bound parameter.
 */
@Service
public class StudentQueryService {

    /** the statuses a learner has left with: "current students" leaves them out */
    static final String[] ENDED = {"GRADUATED", "COMPLETED", "WITHDRAWN", "VOLUNTARY_WITHDRAWAL", "EXPELLED", "TRANSFERRED_OUT", "DECEASED", "PROGRESSED"};
    /** the offices that read a student's school-fee standing — the same offices as the student record's (StudentController.FEE_READERS, V360) */
    static final Set<String> FEE_READERS = Set.of("bursar", "studentaccounts", "financecontroller", "registrar", "dregistrar", "academic",
            "records", "vc", "dvc", "dean", "hod", "facultyofficer", "provost", "audit", "ict", "admin", "super");
    /** the offices that decide a student's classification (people.require_classifier) */
    static final Set<String> CLASSIFIERS = Set.of("academic", "registrar", "dregistrar", "super");

    /** the scope the acting office is held to: the analytics bound and, for an office of one programme type, that type */
    public record Scope(String kind, String label, String faculty, String dept, boolean college, String programmeType) {
    }

    private static final String WHERE = """
             WHERE (CAST(:btype AS text) IS NULL OR l.programme_type = CAST(:btype AS text))
               AND (CAST(:bfac AS text) IS NULL OR l.faculty_code = CAST(:bfac AS text))
               AND (CAST(:bdept AS text) IS NULL OR l.dept_code = CAST(:bdept AS text))
               AND (CAST(:bchs AS boolean) IS NULL OR l.college_code = 'CHS')
               AND (CAST(:type AS text) IS NULL OR l.programme_type = CAST(:type AS text))
               AND (CAST(:route AS text) IS NULL OR l.admission_route = CAST(:route AS text))
               AND (CAST(:centre AS text) IS NULL OR l.centre_code = CAST(:centre AS text))
               AND (CAST(:mode AS text) IS NULL OR l.study_mode = CAST(:mode AS text))
               AND (CAST(:fac AS text) IS NULL OR l.faculty_code = CAST(:fac AS text))
               AND (CAST(:dept AS text) IS NULL OR l.dept_code = CAST(:dept AS text))
               AND (CAST(:prog AS text) IS NULL OR l.programme_code = CAST(:prog AS text))
               AND (CAST(:award AS text) IS NULL OR coalesce(l.pg_award, '-') = CAST(:award AS text))
               AND (CAST(:session AS text) IS NULL OR l.source = 'REGISTER' OR l.current_session = CAST(:session AS text))
               AND (CAST(:asession AS text) IS NULL OR l.admission_session = CAST(:asession AS text))
               AND (CAST(:level AS int) IS NULL OR l.level = CAST(:level AS int))
               AND (CAST(:status AS text) IS NULL OR l.status = CAST(:status AS text)
                    OR (CAST(:status AS text) = 'CURRENT' AND l.status <> ALL (CAST(:ended AS text[]))))
               AND (CAST(:sex AS text) IS NULL OR l.sex = CAST(:sex AS text))
               AND (CAST(:matric AS boolean) IS NULL OR (l.matriculated_at IS NOT NULL) = CAST(:matric AS boolean))
               AND (CAST(:final AS boolean) IS NULL OR l.final_year = CAST(:final AS boolean))
               AND (CAST(:spill AS text) IS NULL
                    OR (CAST(:spill AS text) = 'ANY' AND coalesce(l.spillover_state, '') LIKE 'SPILLOVER%')
                    OR (CAST(:spill AS text) = 'NONE' AND coalesce(l.spillover_state, '') NOT LIKE 'SPILLOVER%')
                    OR l.spillover_state = CAST(:spill AS text))
               AND (CAST(:grad AS boolean) IS NULL OR (l.status IN ('GRADUATED', 'COMPLETED')) = CAST(:grad AS boolean))
               AND (CAST(:cls AS text) IS NULL OR l.classification_status = CAST(:cls AS text))
               AND (CAST(:comb AS uuid) IS NULL OR l.jupeb_combination_id = CAST(:comb AS uuid))
               AND (CAST(:subj AS uuid) IS NULL OR CAST(:subj AS uuid) = ANY (l.jupeb_subjects))
               AND (CAST(:proute AS text) IS NULL OR l.prelim_route = CAST(:proute AS text))
               AND (CAST(:ey AS int) IS NULL OR l.entry_year = CAST(:ey AS int))
               AND (CAST(:my AS int) IS NULL OR l.matric_year = CAST(:my AS int))
               AND (CAST(:jy AS int) IS NULL OR l.jamb_year = CAST(:jy AS int))
               AND (CAST(:q AS text) IS NULL
                    OR lower(concat_ws(' ', l.surname, l.other_names, l.surname, l.matric_no, l.jamb_no, l.application_no, l.admission_no)) LIKE CAST(:q AS text)
                    OR l.learner_id = CAST(:qid AS uuid))
               AND (CAST(:reg AS boolean) IS NULL OR CAST(:reg AS boolean) = CASE l.source
                        WHEN 'REGISTER' THEN EXISTS (
                            SELECT 1 FROM registration.course_registration x
                             WHERE x.student_id = l.student_id AND x.session = coalesce(CAST(:session AS text), l.current_session)
                               AND (CAST(:semester AS int) IS NULL OR x.semester = CAST(:semester AS int))
                               AND x.status IN ('SUBMITTED', 'APPROVED', 'LOCKED'))
                        WHEN 'JUPEB' THEN coalesce(l.jupeb_registered, false)
                        ELSE false END)
            """;

    /** the school-fee standing of the session, read only when an office that may see it asks for it */
    private static final String FEES_JOIN = """
             JOIN finance.session_positions(CAST(:fsession AS text), CAST(:semester AS int)) fp ON fp.student_id = l.student_id
            """;
    private static final String FEES_PREDICATE = """
               AND ((CAST(:fees AS text) = 'OUTSTANDING' AND fp.status IN ('PART_PAYMENT', 'NOT_PAID'))
                    OR (CAST(:fees AS text) = 'COMPLETED' AND fp.status = 'FULLY_PAID'))
            """;

    private final JdbcClient jdbc;
    private final AnalyticsScope analytics;

    StudentQueryService(JdbcClient jdbc, AnalyticsScope analytics) {
        this.jdbc = jdbc;
        this.analytics = analytics;
    }

    private static String office() {
        return AuditContextHolder.current().map(c -> c.actorOffice()).orElse("");
    }

    /** whether the acting office reads school-fee standing (the fee filter is offered only to these) */
    public boolean readsFees() {
        return FEE_READERS.contains(office());
    }

    /** whether the acting office decides classifications */
    public boolean classifies() {
        return CLASSIFIERS.contains(office());
    }

    /** the acting office's scope, from the server's record of the office and its assignment */
    public Scope scope() {
        Bound b = analytics.bound();
        String type = analytics.programmeType();
        if (b.pg() && type == null) type = "POSTGRADUATE";
        String label = b.label();
        if (type != null && !b.pg()) {
            label = jdbc.sql("SELECT label FROM finance.programme_type WHERE code = :c").param("c", type).query(String.class).optional().orElse(type);
        }
        return new Scope(type != null ? "PROGRAMME_TYPE" : b.kind(), label, b.faculty(), b.dept(), b.chs(), type);
    }

    /** the University's current session, as the portal reads it everywhere (policy.university_current_session) */
    private String currentSession() {
        return jdbc.sql("SELECT policy.university_current_session()").query(String.class).optional().orElse(null);
    }

    private JdbcClient.StatementSpec bind(JdbcClient.StatementSpec s, Scope sc, StudentQueryRequest r, boolean withType) {
        return s.param("btype", sc.programmeType(), Types.VARCHAR)
                .param("bfac", sc.faculty(), Types.VARCHAR)
                .param("bdept", sc.dept(), Types.VARCHAR)
                .param("bchs", sc.college() ? Boolean.TRUE : null, Types.BOOLEAN)
                .param("type", withType ? r.type() : null, Types.VARCHAR)
                .param("route", r.route(), Types.VARCHAR)
                .param("centre", r.centre(), Types.VARCHAR)
                .param("mode", r.studyMode(), Types.VARCHAR)
                .param("fac", r.fac(), Types.VARCHAR)
                .param("dept", r.dept(), Types.VARCHAR)
                .param("prog", r.prog(), Types.VARCHAR)
                .param("award", r.pgAward(), Types.VARCHAR)
                .param("session", r.session(), Types.VARCHAR)
                .param("semester", r.semester(), Types.INTEGER)
                .param("asession", r.admissionSession(), Types.VARCHAR)
                .param("level", r.level(), Types.INTEGER)
                .param("status", r.status(), Types.VARCHAR)
                .param("ended", ENDED, Types.ARRAY)
                .param("sex", r.sex(), Types.VARCHAR)
                .param("matric", r.matriculatedFlag(), Types.BOOLEAN)
                .param("final", r.finalYearFlag(), Types.BOOLEAN)
                .param("spill", r.spillover(), Types.VARCHAR)
                .param("grad", r.graduatedFlag(), Types.BOOLEAN)
                .param("cls", r.classification(), Types.VARCHAR)
                .param("comb", r.combinationId(), Types.OTHER)
                .param("subj", r.subjectId(), Types.OTHER)
                .param("proute", r.prelimRoute(), Types.VARCHAR)
                .param("ey", r.entryYear(), Types.INTEGER)
                .param("my", r.matricYear(), Types.INTEGER)
                .param("jy", r.jambYear(), Types.INTEGER)
                .param("q", r.like(), Types.VARCHAR)
                .param("qid", r.searchId(), Types.OTHER)
                .param("reg", r.registeredFlag(), Types.BOOLEAN)
                .param("xlevel", r.expectedLevel(), Types.INTEGER)
                .param("plen", r.programmeLength(), Types.INTEGER)
                .param("rec", r.recommendation(), Types.VARCHAR)
                .param("compl", r.completion(), Types.VARCHAR)
                .param("gsession", r.graduationSession(), Types.VARCHAR)
                .param("gbatch", r.graduationBatch(), Types.VARCHAR);
    }

    private JdbcClient.StatementSpec withFees(JdbcClient.StatementSpec s, StudentQueryRequest r) {
        if (r.fees() == null) return s;
        return s.param("fees", r.fees()).param("fsession", r.session() != null ? r.session() : currentSession(), Types.VARCHAR);
    }

    private void checkFees(StudentQueryRequest r) {
        if (r.fees() != null && !readsFees()) {
            throw new AccessDeniedException("This office does not read students' school-fee standing; the fee filter is for the offices that do.");
        }
    }

    private static String from(StudentQueryRequest r) {
        return " FROM people.learner l " + (r.fees() != null ? FEES_JOIN : "") + WHERE + (r.fees() != null ? FEES_PREDICATE : "") + position(r);
    }

    /** V593: the cohort engine's position and the lifecycle reconciliation's reading, joined only when one of their filters is asked
     *  for — the expected level and whether the record stands below it (people.academic_position), the programme's own length,
     *  the recommendation (people.lifecycle_recommendation) and the completion check (people.lifecycle_completion) */
    private static String position(StudentQueryRequest r) {
        StringBuilder sb = new StringBuilder();
        if (r.expectedLevel() != null || r.levelBehind() != null) {
            sb.append(" AND l.student_id IN (SELECT ap.student_id FROM people.academic_position ap JOIN people.student st ON st.id = ap.student_id WHERE ap.computed_level IS NOT NULL");
            if (r.expectedLevel() != null) sb.append(" AND ap.computed_level = CAST(:xlevel AS int)");
            if ("YES".equals(r.levelBehind())) sb.append(" AND st.current_level < ap.computed_level");
            if ("NO".equals(r.levelBehind())) sb.append(" AND st.current_level >= ap.computed_level");
            sb.append(")\n");
        }
        if (r.programmeLength() != null) {
            sb.append(" AND l.programme_code IN (SELECT pr.code FROM ref.programme pr WHERE coalesce(pr.duration_years, pr.final_level / 100) = CAST(:plen AS int))\n");
        }
        if (r.recommendation() != null) {
            sb.append(" AND l.student_id IN (SELECT lr.student_id FROM people.lifecycle_recommendation lr WHERE lr.recommendation = CAST(:rec AS text))\n");
        }
        if (r.completion() != null) {
            sb.append(" AND l.student_id IN (SELECT lc.student_id FROM people.lifecycle_completion lc WHERE lc.completion = CAST(:compl AS text))\n");
        }
        return sb.toString();
    }

    /** a page of the learners the query selects, names A–Z, with the total and the scope it was read in */
    public Map<String, Object> page(StudentQueryRequest raw, int page, int size) {
        StudentQueryRequest r = raw.normalized();
        checkFees(r);
        Scope sc = scope();
        int sz = Math.max(1, Math.min(size, 500));
        int pg = Math.max(0, page);
        String sql = """
                SELECT p.total_rows, p.source, p.learner_id, p.student_id, p.surname, p.other_names, p.sex,
                       p.matric_no, p.jamb_no, p.application_no, p.admission_no,
                       p.programme_type, pt.label AS programme_type_name, p.proposed_type, p.classification_status, p.classification_note,
                       p.admission_route, ar.name AS admission_route_name, p.study_mode, p.centre_code, ce.name AS centre_name,
                       p.faculty_code, p.faculty, p.dept_code, p.department, p.programme_code, p.programme, p.programme_is_target, p.pg_award,
                       p.level, p.admission_session, p.current_session, p.status, (p.matriculated_at IS NOT NULL) AS matriculated,
                       p.final_year, p.spillover_state, p.application_status, p.jupeb_combination, p.prelim_name, p.fee_status,
                       CASE p.source
                           WHEN 'REGISTER' THEN (SELECT x.status FROM registration.course_registration x
                                                  WHERE x.student_id = p.student_id AND x.session = coalesce(CAST(:session AS text), p.current_session)
                                                    AND (CAST(:semester AS int) IS NULL OR x.semester = CAST(:semester AS int))
                                                  ORDER BY (x.status IN ('SUBMITTED', 'APPROVED', 'LOCKED')) DESC, x.semester DESC LIMIT 1)
                           WHEN 'JUPEB' THEN CASE WHEN p.jupeb_registered THEN 'REGISTERED' END
                       END AS registration_status
                  FROM (SELECT count(*) OVER () AS total_rows, l.*, """ + (r.fees() != null ? "fp.status" : "NULL::text") + " AS fee_status" + from(r) + """
                         ORDER BY lower(l.surname), lower(l.other_names), l.learner_id
                         LIMIT :n OFFSET :o) p
                  LEFT JOIN finance.programme_type pt ON pt.code = p.programme_type
                  LEFT JOIN ref.admission_route ar ON ar.code = p.admission_route
                  LEFT JOIN ref.centre ce ON ce.code = p.centre_code
                 ORDER BY lower(p.surname), lower(p.other_names), p.learner_id
                """;
        List<Map<String, Object>> rows = withFees(bind(jdbc.sql(sql), sc, r, true), r).param("n", sz).param("o", pg * sz).query().listOfRows();
        long total = rows.isEmpty() ? (pg == 0 ? 0 : count(sc, r)) : ((Number) rows.get(0).get("total_rows")).longValue();
        List<Map<String, Object>> out = new ArrayList<>(rows.size());
        for (Map<String, Object> row : rows) {
            Map<String, Object> x = new LinkedHashMap<>(row);
            x.remove("total_rows");
            if (r.fees() == null) x.remove("fee_status");
            out.add(x);
        }
        Map<String, Object> res = new LinkedHashMap<>();
        res.put("scope", scopeMap(sc));
        res.put("session", r.session() != null ? r.session() : currentSession());
        res.put("total", total);
        res.put("page", pg);
        res.put("size", sz);
        res.put("rows", out);
        return res;
    }

    private long count(Scope sc, StudentQueryRequest r) {
        return withFees(bind(jdbc.sql("SELECT count(*)" + from(r)), sc, r, true), r).query(Long.class).single();
    }

    /**
     * The figures by programme type for the same filters (the type itself aside, so every card is shown): each type the
     * scope may see, in the registry's order, with its learners; those that require classification counted apart and in
     * no type; and the total. With them, the same selection — the type included — by faculty, department and programme.
     */
    public Map<String, Object> summary(StudentQueryRequest raw) {
        StudentQueryRequest r = raw.normalized();
        checkFees(r);
        Scope sc = scope();
        List<Map<String, Object>> groups = withFees(bind(jdbc.sql("""
                SELECT grouping(l.programme_type, l.classification_status) AS g_type, grouping(l.dept_code) AS g_dept, grouping(l.programme_code) AS g_prog,
                       l.programme_type, l.classification_status, l.faculty_code, l.faculty, l.dept_code, l.department, l.programme_code, l.programme,
                       count(*) AS n""" + from(r) + """
                 GROUP BY GROUPING SETS ((l.programme_type, l.classification_status), (l.programme_type, l.faculty_code, l.faculty),
                                         (l.programme_type, l.faculty_code, l.faculty, l.dept_code, l.department),
                                         (l.programme_type, l.faculty_code, l.faculty, l.dept_code, l.department, l.programme_code, l.programme))
                """), sc, r, false), r).query().listOfRows();
        Map<String, Long> byType = new LinkedHashMap<>();
        // the breakdowns are of the type chosen (every type when none is): counted by type in the one pass, merged here
        Map<String, Map<String, Object>> byFac = new LinkedHashMap<>(), byDept = new LinkedHashMap<>(), byProg = new LinkedHashMap<>();
        long requires = 0, total = 0;
        for (Map<String, Object> g : groups) {
            long n = ((Number) g.get("n")).longValue();
            if (zero(g, "g_type")) {
                total += n;
                if (!"CLASSIFIED".equals(g.get("classification_status")) || g.get("programme_type") == null) requires += n;
                else byType.merge((String) g.get("programme_type"), n, Long::sum);
                continue;
            }
            if (r.type() != null && !r.type().equals(g.get("programme_type"))) continue;
            boolean prog = zero(g, "g_prog"), dept = prog || zero(g, "g_dept");
            String key = g.get("faculty_code") + "|" + (dept ? g.get("dept_code") : "") + "|" + (prog ? g.get("programme_code") : "");
            Map<String, Map<String, Object>> into = prog ? byProg : dept ? byDept : byFac;
            Map<String, Object> row = into.computeIfAbsent(key, k -> {
                Map<String, Object> m = new LinkedHashMap<>();
                m.put("faculty_code", g.get("faculty_code"));
                m.put("faculty", g.get("faculty"));
                if (dept) { m.put("dept_code", g.get("dept_code")); m.put("department", g.get("department")); }
                if (prog) { m.put("programme_code", g.get("programme_code")); m.put("programme", g.get("programme")); }
                m.put("count", 0L);
                return m;
            });
            row.put("count", (Long) row.get("count") + n);
        }
        List<Map<String, Object>> byFaculty = new ArrayList<>(byFac.values()), byDepartment = new ArrayList<>(byDept.values()),
                byProgramme = new ArrayList<>(byProg.values());
        java.util.Comparator<Map<String, Object>> byName = java.util.Comparator.comparing(
                (Map<String, Object> m) -> String.valueOf(m.get("faculty")) + "|" + String.valueOf(m.getOrDefault("department", "")) + "|" + String.valueOf(m.getOrDefault("programme", "")));
        byFaculty.sort(byName);
        byDepartment.sort(byName);
        byProgramme.sort(byName);
        List<Map<String, Object>> types = new ArrayList<>();
        for (Map<String, Object> t : jdbc.sql("""
                SELECT t.id, t.code, t.label AS name, t.description, t.ord AS display_order, t.active,
                       (cardinality(t.entry_modes) > 0 OR cardinality(t.programme_categories) > 0) AS mapped
                  FROM finance.programme_type t
                 WHERE CAST(:btype AS text) IS NULL OR t.code = CAST(:btype AS text)
                 ORDER BY t.ord, t.code
                """).param("btype", sc.programmeType(), Types.VARCHAR).query().listOfRows()) {
            long n = byType.getOrDefault((String) t.get("code"), 0L);
            boolean shown = n > 0 || (Boolean.TRUE.equals(t.get("active")) && Boolean.TRUE.equals(t.get("mapped"))) || sc.programmeType() != null;
            if (!shown) continue;
            Map<String, Object> x = new LinkedHashMap<>(t);
            x.put("count", n);
            types.add(x);
        }
        Map<String, Object> res = new LinkedHashMap<>();
        res.put("scope", scopeMap(sc));
        res.put("session", r.session() != null ? r.session() : currentSession());
        res.put("types", types);
        res.put("requiresClassification", sc.programmeType() == null ? requires : 0L);
        res.put("total", sc.programmeType() == null ? total : total - requires);
        res.put("byFaculty", byFaculty);
        res.put("byDepartment", byDepartment);
        res.put("byProgramme", byProgramme);
        return res;
    }

    /**
     * What the filter bar may offer for the type chosen, within the scope: only the routes, centres, study modes,
     * programmes (faculty → department → programme), levels, statuses and sessions its learners have, and the
     * type's own filters — the postgraduate awards, the JUPEB combinations and subjects, the Preliminary programmes.
     */
    public Map<String, Object> options(StudentQueryRequest raw) {
        StudentQueryRequest r = raw.normalized();
        Scope sc = scope();
        StudentQueryRequest only = new StudentQueryRequest(r.type(), null, null, null, null, null, null, null, null, null, null, null,
                null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null);
        List<Map<String, Object>> sets = bind(jdbc.sql("""
                SELECT grouping(l.admission_route) AS g_route, grouping(l.centre_code) AS g_centre, grouping(l.study_mode) AS g_mode,
                       grouping(l.status) AS g_status, grouping(l.level) AS g_level, grouping(l.admission_session) AS g_asession,
                       grouping(l.pg_award) AS g_award, grouping(l.programme_code) AS g_prog, grouping(l.prelim_route) AS g_prelim,
                       grouping(l.jupeb_combination_id) AS g_comb, grouping(l.current_session) AS g_session,
                       l.admission_route, l.centre_code, l.study_mode, l.status, l.level, l.admission_session, l.pg_award,
                       l.faculty_code, l.faculty, l.dept_code, l.department, l.programme_code, l.programme,
                       l.prelim_route, l.prelim_name, l.jupeb_combination_id, l.jupeb_combination, l.current_session, count(*) AS n
                  FROM people.learner l""" + WHERE + """
                 GROUP BY GROUPING SETS ((l.admission_route), (l.centre_code), (l.study_mode), (l.status), (l.level), (l.admission_session),
                                         (l.pg_award), (l.faculty_code, l.faculty, l.dept_code, l.department, l.programme_code, l.programme),
                                         (l.prelim_route, l.prelim_name), (l.jupeb_combination_id, l.jupeb_combination), (l.current_session))
                """), sc, only, true).query().listOfRows();
        List<String> routes = new ArrayList<>(), centres = new ArrayList<>(), modes = new ArrayList<>(), statuses = new ArrayList<>(),
                admissionSessions = new ArrayList<>(), awards = new ArrayList<>(), learnerSessions = new ArrayList<>();
        List<Integer> levels = new ArrayList<>();
        List<Map<String, Object>> programmes = new ArrayList<>(), prelim = new ArrayList<>(), combinations = new ArrayList<>();
        for (Map<String, Object> g : sets) {
            if (zero(g, "g_route")) { if (g.get("admission_route") != null) routes.add((String) g.get("admission_route")); }
            else if (zero(g, "g_centre")) { if (g.get("centre_code") != null) centres.add((String) g.get("centre_code")); }
            else if (zero(g, "g_mode")) { if (g.get("study_mode") != null) modes.add((String) g.get("study_mode")); }
            else if (zero(g, "g_status")) { if (g.get("status") != null) statuses.add((String) g.get("status")); }
            else if (zero(g, "g_level")) { if (g.get("level") != null) levels.add(((Number) g.get("level")).intValue()); }
            else if (zero(g, "g_asession")) { if (g.get("admission_session") != null) admissionSessions.add((String) g.get("admission_session")); }
            else if (zero(g, "g_award")) { awards.add(g.get("pg_award") == null ? "-" : (String) g.get("pg_award")); }
            else if (zero(g, "g_prog")) {
                if (g.get("programme_code") != null) {
                    Map<String, Object> p = new LinkedHashMap<>();
                    for (String k : List.of("faculty_code", "faculty", "dept_code", "department", "programme_code", "programme")) p.put(k, g.get(k));
                    programmes.add(p);
                }
            }
            else if (zero(g, "g_prelim")) { if (g.get("prelim_route") != null) prelim.add(Map.of("code", g.get("prelim_route"), "name", String.valueOf(g.get("prelim_name")))); }
            else if (zero(g, "g_comb")) {
                if (g.get("jupeb_combination_id") != null) combinations.add(Map.of("id", g.get("jupeb_combination_id"), "name", String.valueOf(g.get("jupeb_combination"))));
            }
            else if (zero(g, "g_session")) { if (g.get("current_session") != null) learnerSessions.add((String) g.get("current_session")); }
        }
        programmes.sort((a, b) -> (a.get("faculty") + "|" + a.get("department") + "|" + a.get("programme")).compareTo(b.get("faculty") + "|" + b.get("department") + "|" + b.get("programme")));
        levels.sort(Integer::compare);
        admissionSessions.sort(java.util.Comparator.reverseOrder());
        awards.sort(String::compareTo);
        combinations.sort((a, b) -> String.valueOf(a.get("name")).compareTo(String.valueOf(b.get("name"))));

        Map<String, Object> o = new LinkedHashMap<>();
        o.put("scope", scopeMap(sc));
        o.put("currentSession", currentSession());
        o.put("type", r.type());
        o.put("types", jdbc.sql("""
                SELECT t.id, t.code, t.label AS name, t.description, t.ord AS display_order, t.active
                  FROM finance.programme_type t
                 WHERE (CAST(:btype AS text) IS NULL OR t.code = CAST(:btype AS text)) AND t.active
                 ORDER BY t.ord, t.code
                """).param("btype", sc.programmeType(), Types.VARCHAR).query().listOfRows());
        o.put("routes", named("SELECT code, name FROM ref.admission_route WHERE code = ANY (CAST(:c AS text[])) ORDER BY ord, code", routes));
        o.put("centres", named("SELECT code, name FROM ref.centre WHERE code = ANY (CAST(:c AS text[])) ORDER BY ord, code", centres));
        o.put("studyModes", modes.stream().sorted().toList());
        o.put("statuses", statuses.stream().sorted().toList());
        o.put("levels", levels);
        o.put("admissionSessions", admissionSessions);
        o.put("programmes", programmes);
        o.put("pgAwards", awards);
        o.put("prelimRoutes", prelim);
        o.put("jupebCombinations", combinations);
        o.put("jupebSubjects", combinations.isEmpty() ? List.of() : jdbc.sql("""
                SELECT DISTINCT s.id, s.code, s.title FROM jupeb.subject s
                  JOIN jupeb.combination c ON s.id IN (c.subject1, c.subject2, c.subject3)
                 WHERE c.id = ANY (CAST(:ids AS uuid[]))
                 ORDER BY s.code
                """).param("ids", combinations.stream().map(c -> String.valueOf(c.get("id"))).toArray(String[]::new), Types.ARRAY).query().listOfRows());
        o.put("sessions", jdbc.sql("SELECT name FROM policy.academic_session ORDER BY name DESC").query(String.class).list());
        o.put("learnerSessions", learnerSessions.stream().sorted(java.util.Comparator.reverseOrder()).toList());
        o.put("semesters", jdbc.sql("SELECT DISTINCT number FROM policy.semester ORDER BY number").query(Integer.class).list());
        o.put("fees", readsFees());
        o.put("classifies", classifies());
        return o;
    }

    private static boolean zero(Map<String, Object> g, String k) {
        return ((Number) g.get(k)).intValue() == 0;
    }

    private List<Map<String, Object>> named(String sql, List<String> codes) {
        if (codes.isEmpty()) return List.of();
        return jdbc.sql(sql).param("c", codes.toArray(new String[0]), Types.ARRAY).query().listOfRows();
    }

    private static Map<String, Object> scopeMap(Scope sc) {
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("kind", sc.kind());
        m.put("label", sc.label());
        m.put("faculty", sc.faculty());
        m.put("department", sc.dept());
        m.put("programmeType", sc.programmeType());
        return m;
    }
}
