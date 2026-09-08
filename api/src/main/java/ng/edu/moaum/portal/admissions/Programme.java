package ng.edu.moaum.portal.admissions;

import java.util.List;

/**
 * A programme with what JAMB calls it: the primary alias, and every further
 * name JAMB has used for it (V018). A CAPS download is matched on all of them.
 */
public record Programme(String code, String name, String deptCode, String facultyCode, String facultyName,
                        String jambName, List<String> jambNames, String category, boolean archived) {
}
