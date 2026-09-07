package ng.edu.moaum.portal.admissions;

/**
 * One line of what the database reports about a session's list: a named
 * finding, how many rows it covers, whose desk it is, and what it means.
 * The shape of {@code admissions.reconcile} and {@code admissions.attachment_state}.
 */
public record Finding(String finding, long n, String owner, String whatItMeans) {
}
