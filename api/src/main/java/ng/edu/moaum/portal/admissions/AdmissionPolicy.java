package ng.edu.moaum.portal.admissions;

import java.time.OffsetDateTime;
import java.util.List;

/**
 * A session's admission settings as the Central Admissions Committee issued
 * them (V008): the quota, the weighting, the ratios and caps, the four
 * criteria, every faculty's quota and cut-off, every programme's rule and
 * its own cut-off where set. In force under a minute, or a draft with the
 * findings that keep it one.
 */
public record AdmissionPolicy(String session, String state, boolean inForce, String instrument, OffsetDateTime inForceSince,
                              int nucQuota, int weightUtme, int weightPutme, int ratioUtme, int ratioDe,
                              int ratioScience, int ratioArts, int elgCapPct, int deptSharePct,
                              int indexPrelimPlaces, int indexPerZone, boolean mpfOnly, boolean screeningRequired,
                              List<Criterion> criteria, List<FacultyCutoff> facultyCutoffs,
                              List<ProgrammeCutoff> programmeCutoffs, List<ProgrammeRule> programmes,
                              List<PolicyFinding> findings) {

    public record Criterion(String criterion, int percent) {
    }

    public record FacultyCutoff(String facultyCode, String facultyName, Integer quota, Integer cutoff) {
    }

    public record ProgrammeCutoff(String code, String name, int cutoff) {
    }

    /** A programme the University runs and what this session's settings say about it — nothing, until stated. */
    public record ProgrammeRule(String code, String name, String facultyCode, String facultyName, Integer cutoff,
                                String olevelText, String utmeText, String deText, Integer olevelCredits,
                                Integer olevelSittings, boolean stated, List<String> olevelSubjects) {
    }

    /** One line of the register of sessions that have settings at all. */
    public record Summary(String session, String state) {
    }

    /** The row of {@code admissions.session_policy}, before the rest is attached. */
    record Row(String session, String state, String instrument, OffsetDateTime inForceSince, int nucQuota,
               int weightUtme, int weightPutme, int ratioUtme, int ratioDe, int ratioScience, int ratioArts,
               int elgCapPct, int deptSharePct, int indexPrelimPlaces, int indexPerZone, boolean mpfOnly,
               boolean screeningRequired) {
    }
}
