/**
 * CCE — the Centre for Continuing Education (V379): a regular, part-time, six-year undergraduate route inside the portal. The
 * desk of the Academic Office (the CCE list, the CCE session, the programmes the Centre admits into, publication) and of the
 * Centre (the review of each application). Every rule is a database function; this module reads and calls them. A CCE student
 * is an ordinary student and a CCE applicant an ordinary applicant: nothing here duplicates the admission, student, finance or
 * session systems (docs/cce.md).
 */
@org.springframework.modulith.ApplicationModule(displayName = "CCE")
package ng.edu.moaum.portal.cce;
