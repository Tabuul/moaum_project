package ng.edu.moaum.portal.admissions;

/**
 * A programme the University runs ({@code ref.programme}) with the name
 * JAMB uses for it ({@code ref.jamb_alias}), which is how a CAPS download —
 * which names the course and gives no code — is resolved to a code.
 */
public record Programme(String code, String name, String deptCode, String facultyCode, String facultyName,
                        String jambName, String category, boolean archived) {
}
