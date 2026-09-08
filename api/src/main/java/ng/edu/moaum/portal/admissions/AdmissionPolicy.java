package ng.edu.moaum.portal.admissions;

import java.util.List;

/**
 * A session's admission settings as the Central Admissions Committee issued
 * them (V008): the weights, the quota, and the cut-offs — a faculty's, and a
 * programme's own where one is set. In force, or a draft with the findings
 * that keep it one.
 */
public record AdmissionPolicy(String session, String state, boolean inForce, String instrument, int nucQuota,
                              int weightUtme, int weightPutme, int ratioUtme, int ratioDe,
                              List<FacultyCutoff> facultyCutoffs, List<ProgrammeCutoff> programmeCutoffs,
                              List<PolicyFinding> findings) {

    public record FacultyCutoff(String facultyCode, String facultyName, Integer quota, Integer cutoff) {
    }

    public record ProgrammeCutoff(String code, String name, int cutoff) {
    }

    /** The row of {@code admissions.session_policy}, before the cut-offs and findings are attached. */
    record Row(String session, String state, String instrument, int nucQuota, int weightUtme, int weightPutme,
               int ratioUtme, int ratioDe) {
    }
}
