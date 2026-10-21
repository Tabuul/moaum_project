package ng.edu.moaum.portal.stats;

import java.util.UUID;
import java.util.regex.Pattern;

/**
 * One student query (V469): the filters an officer picks, as the address carries them. Nothing here is trusted — every
 * value is trimmed, shape-checked and dropped when malformed, and the repository binds what is left as parameters; the
 * office's own scope is added on the server (StudentQueryService.bound), never read from here.
 *
 * <p>{@code type} is the programme type ("ALL" or blank for every type); {@code session} is the academic session whose
 * registrations and fees are read (and the session of a JUPEB or Preliminary learner); {@code admissionSession} the
 * session a learner came in. {@code status} takes a student status or CURRENT, every learner who has not left.
 *
 * <p>V593: {@code expectedLevel} is the level the cohort engine computes (people.academic_position), {@code levelBehind} whether
 * the record stands below it, {@code programmeLength} the programme's own length in years, {@code recommendation} the lifecycle
 * reconciliation's recommendation and {@code completion} its completion check (people.lifecycle_completion, as last analysed).
 */
public record StudentQueryRequest(String type, String route, String centre, String studyMode,
                                  String fac, String dept, String prog, String pgAward,
                                  String session, Integer semester, String admissionSession, Integer level,
                                  String status, String sex, String matriculated, String finalYear, String spillover,
                                  String graduation, String registration, String fees, String classification,
                                  String jupebCombination, String jupebSubject, String prelimRoute,
                                  Integer entryYear, Integer matricYear, Integer jambYear,
                                  Integer expectedLevel, String levelBehind, Integer programmeLength, String recommendation, String completion,
                                  String graduationSession, String graduationBatch,
                                  String q) {

    /** V593: the lifecycle reconciliation's recommendations and completion states (V558) */
    static final String[] RECOMMENDATIONS = {"WITHIN_NORMAL_DURATION", "GRADUATION_CANDIDATE", "SPILLOVER_YEAR_1", "SPILLOVER_YEAR_2",
            "MAXIMUM_SPILLOVER_REACHED", "REQUIRES_REVIEW", "DATA_INCOMPLETE", "ON_GRADUATION_LIST"};
    static final String[] COMPLETIONS = {"COMPLETED", "OUTSTANDING_COURSES", "AWAITING_RESULT", "FINAL_LEVEL_NOT_REACHED", "NO_PUBLISHED_RESULT"};

    private static final Pattern CODE = Pattern.compile("^[A-Z][A-Z0-9_]{0,40}$");
    private static final Pattern UNIT = Pattern.compile("^[A-Za-z0-9][A-Za-z0-9_./ -]{0,29}$");
    private static final Pattern SESSION = Pattern.compile("^\\d{4}/\\d{4}$");
    private static final Pattern UUID_SHAPE = Pattern.compile("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$");

    /** the request with every value checked: what does not have its shape is as if it had not been sent */
    public StudentQueryRequest normalized() {
        String t = code(type);
        return new StudentQueryRequest("ALL".equals(t) ? null : t, code(route), code(centre), code(studyMode),
                unit(fac), unit(dept), unit(prog), award(pgAward),
                session(session), semester != null && semester >= 1 && semester <= 3 ? semester : null, session(admissionSession),
                level != null && level >= 0 && level <= 900 ? level : null,
                code(status), "M".equalsIgnoreCase(trim(sex)) ? "M" : "F".equalsIgnoreCase(trim(sex)) ? "F" : null,
                yesNo(matriculated), yesNo(finalYear), code(spillover), oneOf(graduation, "GRADUATED", "NOT_GRADUATED"),
                oneOf(registration, "REGISTERED", "NOT_REGISTERED"), oneOf(fees, "OUTSTANDING", "COMPLETED"),
                oneOf(classification, "CLASSIFIED", "REQUIRES_CLASSIFICATION"),
                uuid(jupebCombination), uuid(jupebSubject), code(prelimRoute),
                year(entryYear), year(matricYear), year(jambYear),
                expectedLevel != null && expectedLevel >= 100 && expectedLevel <= 900 && expectedLevel % 100 == 0 ? expectedLevel : null,
                yesNo(levelBehind), programmeLength != null && programmeLength >= 1 && programmeLength <= 10 ? programmeLength : null,
                oneOf(recommendation, RECOMMENDATIONS), oneOf(completion, COMPLETIONS),
                session(graduationSession), batch(graduationBatch),
                q == null || q.isBlank() ? null : q.trim().length() > 80 ? q.trim().substring(0, 80) : q.trim());
    }

    /** the search as a LIKE pattern on the lower-cased name and numbers, its wildcards taken literally */
    String like() {
        if (q == null) return null;
        String s = q.toLowerCase().replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_");
        return "%" + s.replaceAll("\\s+", " ") + "%";
    }

    /** the search as a learner's own identifier, when it is one (the student ID, where the office may use it) */
    UUID searchId() {
        return q != null && UUID_SHAPE.matcher(q).matches() ? UUID.fromString(q) : null;
    }

    Boolean matriculatedFlag() {
        return "YES".equals(matriculated) ? Boolean.TRUE : "NO".equals(matriculated) ? Boolean.FALSE : null;
    }

    Boolean finalYearFlag() {
        return "YES".equals(finalYear) ? Boolean.TRUE : "NO".equals(finalYear) ? Boolean.FALSE : null;
    }

    Boolean graduatedFlag() {
        return "GRADUATED".equals(graduation) ? Boolean.TRUE : "NOT_GRADUATED".equals(graduation) ? Boolean.FALSE : null;
    }

    Boolean registeredFlag() {
        return "REGISTERED".equals(registration) ? Boolean.TRUE : "NOT_REGISTERED".equals(registration) ? Boolean.FALSE : null;
    }

    UUID combinationId() {
        return jupebCombination == null ? null : UUID.fromString(jupebCombination);
    }

    UUID subjectId() {
        return jupebSubject == null ? null : UUID.fromString(jupebSubject);
    }

    private static String trim(String v) {
        return v == null ? null : v.trim();
    }

    private static String code(String v) {
        String t = trim(v);
        if (t == null || t.isEmpty()) return null;
        t = t.toUpperCase();
        return CODE.matcher(t).matches() ? t : null;
    }

    /** a postgraduate award as the programme table holds it (PHD, MSC, PGD…), or "-" for a programme that states none */
    private static String award(String v) {
        String t = trim(v);
        if (t == null || t.isEmpty()) return null;
        return "-".equals(t) ? "-" : code(t);
    }

    private static String unit(String v) {
        String t = trim(v);
        return t == null || t.isEmpty() || !UNIT.matcher(t).matches() ? null : t;
    }

    /** V602: a graduation batch reference, GRAD/YYYY/NNNNNN */
    private static String batch(String v) {
        String t = trim(v);
        return t != null && t.matches("GRAD/\\d{4}/\\d{6}") ? t : null;
    }

    private static String session(String v) {
        String t = trim(v);
        return t != null && SESSION.matcher(t).matches() ? t : null;
    }

    private static String yesNo(String v) {
        return oneOf(v, "YES", "NO");
    }

    private static String oneOf(String v, String... allowed) {
        String t = trim(v);
        if (t == null) return null;
        for (String a : allowed) if (a.equalsIgnoreCase(t)) return a;
        return null;
    }

    private static String uuid(String v) {
        String t = trim(v);
        return t != null && UUID_SHAPE.matcher(t).matches() ? t.toLowerCase() : null;
    }

    private static Integer year(Integer y) {
        return y != null && y >= 1950 && y <= 2100 ? y : null;
    }
}
