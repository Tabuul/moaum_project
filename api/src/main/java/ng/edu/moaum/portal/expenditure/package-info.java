/**
 * Payment vouchers and the pre-payment gate (EXA, V044): every University
 * payment passes Internal Audit before money moves. The Bursary raises a
 * voucher, it advances one desk at a time through the Director, the Deputy and
 * an auditor, and returns to the Bursary to pay. A query blocks it until it is
 * answered, and BR-006 forbids any person acting twice in its chain.
 */
@org.springframework.modulith.ApplicationModule(displayName = "Payment vouchers")
package ng.edu.moaum.portal.expenditure;
