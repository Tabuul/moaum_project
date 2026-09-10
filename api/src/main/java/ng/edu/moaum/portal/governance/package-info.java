/**
 * Data governance (V075): the register of processing activities, the log of
 * data-subject rights requests, the disaster-recovery drill log, and the
 * security posture read from the audit spine and the sign-in record. Only what
 * the system can truthfully report is shown; infrastructure metrics it cannot
 * see are named as such rather than invented.
 */
@org.springframework.modulith.ApplicationModule(displayName = "Governance")
package ng.edu.moaum.portal.governance;
