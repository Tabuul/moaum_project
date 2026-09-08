package ng.edu.moaum.portal.admissions;

import java.util.List;

/** The admission cycle of a session, counted from the register and not from a report. */
public record AdmissionCycle(String session, long applications, long screened, long offers, long accepted, long onTheRegister,
                             long notYetOnRegister, Integer capacity, boolean settingsInForce,
                             List<ProgrammeLine> programmes, List<Finding> reconciliation) {

    public record ProgrammeLine(String code, String name, String facultyCode, String facultyName, long applied, Integer quota,
                                long offered, long accepted, Integer cutoff, String stage) {
    }

    record Counts(long applications, long screened, long offers, long accepted, long onTheRegister, long notYetOnRegister) {
    }

    record ProgrammeRow(String code, String name, String facultyCode, String facultyName, long applied, Integer quota,
                        long offered, long accepted, Integer cutoff) {
    }
}
