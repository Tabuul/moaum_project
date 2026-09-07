package ng.edu.moaum.portal.admissions;

/** The shape of {@code admissions.policy_findings}: what stands between a draft policy and one in force. */
public record PolicyFinding(String finding, String detail, String owner) {
}
