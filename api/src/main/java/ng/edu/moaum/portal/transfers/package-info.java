/**
 * Inter-departmental transfer (V070): a matriculated student's application to
 * move to another department, the Special Admissions and Admission Irregularities
 * Committee's recommendation, Senate's approval, the non-refundable processing
 * fee, and the change effected on the register. The two memos the office issues —
 * the recommended list and a withdrawal — are read from the same applications.
 *
 * <p>The module reads {@code people}, {@code ref} and {@code finance} through its
 * own SQL rather than importing their types.
 */
@org.springframework.modulith.ApplicationModule(displayName = "Transfers")
package ng.edu.moaum.portal.transfers;
