package ng.edu.moaum.portal.student;

import java.util.List;

/**
 * One thing found. The scope bar narrows a list; search finds one record,
 * so a hit carries the identifier a person quoted, the name it belongs to,
 * a line of detail and where the record is opened.
 *
 * @param kind       students, staff, courses or credentials
 * @param identifier the matriculation, admission, staff, course or verification number
 * @param name       the name the identifier belongs to
 * @param detail     the line under the name, as the prototype prints it
 * @param status     the pill: a student's status, a course's state, "Staff", "Valid"
 * @param id         what the link needs: a student's id, a course code, a verification code
 */
record SearchHit(String kind, String identifier, String name, String detail, String status, String id) {

    /**
     * The result of one search. {@code exact} is set when the term is an
     * identifier typed in full, which goes straight to the record.
     */
    record Result(String q, String kind, List<SearchHit> hits, SearchHit exact, int total) {
    }
}
