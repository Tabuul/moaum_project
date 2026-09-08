package ng.edu.moaum.portal.student;

import java.util.List;
import java.util.Map;

/**
 * One view of the query workbench (proto/part21): the rows the scope
 * selects, the population it selects them from, and — where the office that
 * owns the figures is not on the portal yet — the sentence that says so
 * instead of a figure nobody can stand behind.
 *
 * <p>Rows are maps because each view has its own columns; the SQL names them
 * in the shape the screen reads them.
 *
 * @param view      students, registration, fees, results, exams, allocation, clearance, attendance
 * @param rows      the view's rows, keyed by column name
 * @param total     the students the scope selects
 * @param notServed why a view is empty, when the reason is that nothing serves it yet
 */
record RecordsResult(String view, List<Map<String, Object>> rows, int total, String notServed) {
}
