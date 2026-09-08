package ng.edu.moaum.portal.admissions;

import java.util.List;

/**
 * What loading a list did: the batch, how many rows went on the register,
 * and every row held back — by number, with the cut-off that applied — so
 * that nothing left out is left unexplained.
 */
public record CapsLoadResult(CapsBatch batch, int rowsLoaded, List<ExcludedRow> excluded) {

    public record ExcludedRow(String jambRegNo, String surname, String otherNames, String jambCode, String programme,
                              Integer aggregate, int cutoff, String reason) {
    }
}
