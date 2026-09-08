package ng.edu.moaum.portal.registration;

import java.util.List;
import java.util.UUID;

/** One register, six screens: the approved registrations of an offering, all of them. */
public record ClassList(UUID offeringId, String courseCode, String courseTitle, int units, String session, int semester,
                        String deptCode, String deptName, String lecturer, int all, int own, int borrowed,
                        List<String> fromProgrammes, List<Row> rows) {

    public record Row(UUID studentId, String number, String surname, String otherNames, String programmeCode,
                      String programmeName, String deptCode, int level, String basis, boolean cleared) {
    }
}
