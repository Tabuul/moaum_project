/**
 * The member of staff as an employee of the University, and the College tier
 * they may belong to.
 *
 * <p>Two small reads and nothing else. {@code GET /me} answers "who am I on
 * this portal, and under what instrument" from {@code iam.person} and
 * {@code iam.office_assignment} — everything else the Leave and payslip
 * screen shows belongs to a Staff module that is not on the portal yet, and
 * the screen says so rather than inventing it. {@code GET /college/{code}}
 * answers what the College of Health Sciences holds on this portal: the
 * faculties under it and the students on its register.
 *
 * <p>The module reads {@code iam}'s and {@code ref}'s tables through its own
 * SQL rather than importing their types, so that a screen about employment
 * does not make the identity module depend on it.
 */
@org.springframework.modulith.ApplicationModule(displayName = "Staff")
package ng.edu.moaum.portal.staff;
