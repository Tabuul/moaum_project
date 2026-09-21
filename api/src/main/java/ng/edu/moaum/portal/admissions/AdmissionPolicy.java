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
                              List<PolicyFinding> findings,
                              /** the local governments in the University's catchment, for the Locality basis (V054) */
                              List<String> catchmentLgas) {

    public record Criterion(String criterion, int percent) {
    }

    public record FacultyCutoff(String facultyCode, String facultyName, Integer quota, Integer cutoff,
                                /** the faculty's own UTME:DE split (V053); null on both means the session default */
                                Integer ratioUtme, Integer ratioDe) {
    }

    public record ProgrammeCutoff(String code, String name, int cutoff) {
    }

    /** A programme the University runs and what this session's settings say about it — nothing, until stated. */
    public record ProgrammeRule(String code, String name, String facultyCode, String facultyName, Integer cutoff,
                                /** the programme's own carrying capacity (V054); null means none is set */
                                Integer quota,
                                String olevelText, String utmeText, String deText, Integer olevelCredits,
                                Integer olevelSittings, boolean stated, List<String> olevelSubjects,
                                /** compulsory O'Level subjects this programme accepts a pass in / waives (V053) */
                                List<String> olevelAllowances,
                                /** the required UTME subjects the merit list checks (V189); empty = not gated */
                                List<String> utmeSubjects,
                                /** the required Direct Entry subjects the DE gate checks (V200); empty = not gated */
                                List<String> deSubjects,
                                /** how many of the DE subject set a candidate must offer (V200); null = not gated */
                                Integer deChoose,
                                /** closed for the session (V023): not admitted into, needs no rule */
                                boolean closed, String closedReason) {
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
