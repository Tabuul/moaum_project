package ng.edu.moaum.portal.staff;

import java.util.List;

/**
 * A College and what this portal holds for it: the faculties under it, the
 * students on its register, and how they sit across the levels.
 *
 * <p>{@code url} is {@code ref.college.url} and is null until the College's
 * own system has an address recorded. The screen shows the link disabled
 * rather than pointing at nothing.
 */
public record College(Row college, List<Faculty> faculties, long students, List<LevelCount> byLevel) {

    /** One row of {@code ref.college}. */
    public record Row(String code, String name, String system, String url) {
    }

    /** A faculty under the College, with the students on its programmes. */
    public record Faculty(String code, String name, long students) {
    }

    /** How many students of the College are at each level. */
    public record LevelCount(int level, long students) {
    }
}
