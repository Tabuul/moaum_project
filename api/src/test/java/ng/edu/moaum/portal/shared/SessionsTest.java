package ng.edu.moaum.portal.shared;

import static org.assertj.core.api.Assertions.assertThat;

import java.time.LocalDate;

import org.junit.jupiter.api.Test;

/** the session by the date, for a calendar with no session on it: September begins the next one */
class SessionsTest {

    @Test
    void aSessionRunsFromSeptemberToAugust() {
        assertThat(Sessions.byDate(LocalDate.of(2026, 10, 11))).isEqualTo("2026/2027");
        assertThat(Sessions.byDate(LocalDate.of(2026, 9, 1))).isEqualTo("2026/2027");
        assertThat(Sessions.byDate(LocalDate.of(2026, 8, 31))).isEqualTo("2025/2026");
        assertThat(Sessions.byDate(LocalDate.of(2027, 1, 15))).isEqualTo("2026/2027");
        assertThat(Sessions.byDate()).matches("\\d{4}/\\d{4}");
    }
}
