/**
 * Examination attendance (V652): the attendance sheet of a course's class, issued within a scope (the class, a faculty,
 * a department or a programme) with every registered student listed and their eligibility marked — the examination card,
 * or the GST &amp; EPS permit for a general course — and blank rows for handwritten late entries; a later sheet is a new
 * version, never the old one rewritten. After the paper the list is marked, each handwritten row is matched to its student
 * by the number written or held pending verification, and the course is reconciled: registered and not listed, listed and
 * not registered, present without the card or permit, a handwritten student not registered. Attendance is never a
 * registration or a result; nothing here creates a student or changes a registration.
 */
@org.springframework.modulith.ApplicationModule(displayName = "Examination attendance")
package ng.edu.moaum.portal.examattendance;
