package ng.edu.moaum.portal.platform;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.LinkedHashMap;
import java.util.Map;
import java.util.TimeZone;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import tools.jackson.databind.json.JsonMapper;

/** Oct 2026: a database date goes out as its calendar day, whatever the server's clock zone (V480's day paid came back a day early) */
class SqlDateJsonTest {

    private TimeZone was;

    @BeforeEach
    void lagos() {
        was = TimeZone.getDefault();
        TimeZone.setDefault(TimeZone.getTimeZone("Africa/Lagos"));
    }

    @AfterEach
    void back() {
        TimeZone.setDefault(was);
    }

    @Test
    void aDateIsWrittenAsItsCalendarDayOnAServerAheadOfUtc() {
        Map<String, Object> row = new LinkedHashMap<>();
        row.put("paid_on", java.sql.Date.valueOf("2026-10-15"));
        row.put("new_year", java.sql.Date.valueOf("2027-01-01"));
        String plain = JsonMapper.builder().build().writeValueAsString(row);
        assertThat(plain).as("without it: midnight in Lagos written as the instant, the day before in UTC").contains("2026-10-14T23:00");
        String held = JsonMapper.builder().addModule(SqlDateJson.module()).build().writeValueAsString(row);
        assertThat(held).isEqualTo("{\"paid_on\":\"2026-10-15\",\"new_year\":\"2027-01-01\"}");
    }

    @Test
    void aTimestampIsLeftAsTheInstantItIs() {
        String held = JsonMapper.builder().addModule(SqlDateJson.module()).build()
                .writeValueAsString(Map.of("at", java.sql.Timestamp.valueOf("2026-10-15 10:30:00")));
        assertThat(held).as("an instant keeps its time").contains("2026-10-15T09:30");
    }
}
