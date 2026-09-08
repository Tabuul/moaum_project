package ng.edu.moaum.portal.student;

/**
 * The scope every list in the estate is a list within (proto/part21): a
 * faculty, a department, a programme, a level, a course, a session and a
 * semester. Absent members mean "all", and the repository writes them into
 * its SQL as {@code (:x IS NULL OR …)} rather than building a query string.
 */
record Scope(String fac, String dept, String prog, Integer level, String course, String session, Integer sem) {

    static Scope of(String fac, String dept, String prog, Integer level, String course, String session, Integer sem) {
        return new Scope(blankToNull(fac), blankToNull(dept), blankToNull(prog), level,
                blankToNull(course), blankToNull(session), sem);
    }

    private static String blankToNull(String s) {
        return s == null || s.isBlank() ? null : s.trim();
    }
}
