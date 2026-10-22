package ng.edu.moaum.portal.admissions;

import java.util.List;
import java.util.Map;

/**
 * What loading a list did: the batch, how many rows went on the register,
 * and every row held back — by number, with the cut-off that applied — so
 * that nothing left out is left unexplained. V629: the candidates already on
 * the live list — updated where JAMB changed them, else skipped; the updated
 * ones named (at most {@link #UPDATED_LISTED} a request) with what changed;
 * a candidate on the other list (UTME or Direct Entry) named and left as it is.
 */
public record CapsLoadResult(CapsBatch batch, int rowsLoaded, List<ExcludedRow> excluded,
                             int rowsUpdated, int rowsUnchanged, List<UpdatedRow> updated, List<String> otherList,
                             /* V636: after a course changed, the candidates on the portal who followed JAMB's course and those
                                left as admitted (an offer stands; corrected on Programme Changes) */
                             int programmesFollowed, int programmesAdmittedLeft) {

    public record ExcludedRow(String jambRegNo, String surname, String otherNames, String jambCode, String programme,
                              Integer aggregate, int cutoff, String reason) {
    }

    /** V629: a candidate JAMB changed — each field as it was and as it became */
    public record UpdatedRow(String jambRegNo, String surname, String otherNames, Map<String, Map<String, Object>> changes) {
    }

    /** V629: how many updated candidates one request names; the count is always whole */
    public static final int UPDATED_LISTED = 300;
}
