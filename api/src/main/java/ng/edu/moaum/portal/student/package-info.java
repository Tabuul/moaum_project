/**
 * The student register (V013): who is on it, the whole of one person's
 * record, the biodata changes the Registry decides, the search that finds one
 * record, and the queries every list in the estate is a list within.
 *
 * <p>Three rules shape this module. A field is <em>open</em>, <em>locked</em>
 * or <em>on approval</em>, and the difference is enforced here rather than in
 * a form. Looking a person up is processing their personal data whether or
 * not anything changes, so every search is written to {@code
 * people.search_log}. And a register with nothing on it reports nothing: no
 * figure in this module is computed from anything but the rows themselves.
 */
@org.springframework.modulith.ApplicationModule(displayName = "Student")
package ng.edu.moaum.portal.student;
