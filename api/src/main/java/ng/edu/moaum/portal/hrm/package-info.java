/**
 * The payroll (V069): the salary structure, the establishment, and the monthly
 * pay run. A run is built over the active establishment, each staff's payslip a
 * snapshot of the components and the statutory deductions (pension and PAYE); it
 * is built by one officer and approved by another before it is marked paid, the
 * same maker–checker every money act on this portal keeps. The audit directorate
 * reads the runs and the variance of one month against the last. A member of
 * staff sees their own payslips and nobody else's.
 *
 * <p>The module reads {@code iam}'s tables through its own SQL rather than
 * importing their types, so employment does not make the identity module depend
 * on it.
 */
@org.springframework.modulith.ApplicationModule(displayName = "Payroll")
package ng.edu.moaum.portal.hrm;
