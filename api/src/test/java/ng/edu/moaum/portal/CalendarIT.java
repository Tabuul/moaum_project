package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.List;
import java.util.Map;
import java.util.UUID;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpMethod;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.client.RestClient;

/**
 * The calendar, through the API: a session is recorded, a second one that
 * overlaps it is refused by the database's exclusion constraint, a session
 * does not become current without the Senate minute that opened it, and when
 * one does, whatever was current before is closed in the same transaction.
 * Then a semester and a unit limit, read back where the screen reads them.
 *
 * <p>The sessions are the test's own — 2096/2097, 2097/2098 and 2098/2099 —
 * so nothing here touches the calendar the University actually runs to. The
 * whole class tolerates a re-run on the same database.
 *
 * <p>Needs a database the migrations have been applied to: set DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT,
        properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
class CalendarIT {

    static final String FIRST = "2096/2097";
    static final String SECOND = "2097/2098";
    static final String OVERLAPS = "2098/2099";

    @Value("${local.server.port}")
    int port;

    RestClient client;
    final String academic = TestTokens.token(UUID.randomUUID(), List.of("academic"));

    @BeforeEach
    void client() {
        client = RestClient.builder()
                .baseUrl("http://localhost:" + port)
                .defaultStatusHandler(status -> true, (request, response) -> { })
                .build();
    }

    ResponseEntity<Map> call(HttpMethod method, String path, Object body) {
        RestClient.RequestBodySpec spec = client.method(method).uri(path)
                .header(HttpHeaders.AUTHORIZATION, "Bearer " + academic)
                .contentType(MediaType.APPLICATION_JSON);
        return (body == null ? spec : spec.body(body)).retrieve().toEntity(Map.class);
    }

    ResponseEntity<Map> get(String path) {
        return client.get().uri(path).header(HttpHeaders.AUTHORIZATION, "Bearer " + academic).retrieve().toEntity(Map.class);
    }

    static Map<String, Object> session(String starts, String ends) {
        return Map.of("startsOn", starts, "endsOn", ends, "semesters", 2);
    }

    @SuppressWarnings("unchecked")
    static Map<String, Object> row(ResponseEntity<Map> response, String name) {
        List<Map<String, Object>> sessions = (List<Map<String, Object>>) response.getBody().get("sessions");
        return sessions.stream().filter(s -> name.equals(s.get("name"))).findFirst().orElse(null);
    }

    @Test
    @SuppressWarnings("unchecked")
    void aSessionIsRecordedOpenedAndClosed() {
        // 1 · two sessions of the test's own, one after the other
        ResponseEntity<Map> first = call(HttpMethod.PUT, "/api/v1/calendar/sessions/" + FIRST,
                session("2096-10-01", "2097-08-31"));
        assertThat(first.getStatusCode().value()).as(String.valueOf(first.getBody())).isEqualTo(200);

        ResponseEntity<Map> second = call(HttpMethod.PUT, "/api/v1/calendar/sessions/" + SECOND,
                session("2097-10-01", "2098-08-31"));
        assertThat(second.getStatusCode().value()).as(String.valueOf(second.getBody())).isEqualTo(200);
        assertThat(row(second, SECOND).get("state")).isEqualTo("PLANNED");
        assertThat(row(second, SECOND).get("students")).isEqualTo(0);

        // 2 · a third that runs into the second is refused — by the exclusion
        //     constraint in the database, not by a check on the form
        ResponseEntity<Map> overlapping = call(HttpMethod.PUT, "/api/v1/calendar/sessions/" + OVERLAPS,
                session("2098-06-01", "2099-05-31"));
        assertThat(overlapping.getStatusCode().value()).as(String.valueOf(overlapping.getBody())).isEqualTo(422);
        List<Map<String, Object>> after = (List<Map<String, Object>>) get("/api/v1/calendar").getBody().get("sessions");
        assertThat(after).noneSatisfy(s -> assertThat(s.get("name")).isEqualTo(OVERLAPS));

        // 3 · a session does not open without the minute that opened it
        ResponseEntity<Map> noMinute = call(HttpMethod.POST, "/api/v1/calendar/sessions/" + FIRST + "/make-current",
                Map.of("senateMinute", " "));
        assertThat(noMinute.getStatusCode().value()).isEqualTo(422);
        assertThat(noMinute.getBody().get("code")).isEqualTo("CAL_MINUTE_REQUIRED");

        // 4 · with it, it is current
        ResponseEntity<Map> opened = call(HttpMethod.POST, "/api/v1/calendar/sessions/" + FIRST + "/make-current",
                Map.of("senateMinute", "SEN/TEST/2096/001"));
        assertThat(opened.getStatusCode().value()).as(String.valueOf(opened.getBody())).isEqualTo(200);
        assertThat(opened.getBody().get("current")).isEqualTo(FIRST);

        // 5 · opening the next one closes it, in one transaction
        ResponseEntity<Map> moved = call(HttpMethod.POST, "/api/v1/calendar/sessions/" + SECOND + "/make-current",
                Map.of("senateMinute", "SEN/TEST/2097/001"));
        assertThat(moved.getStatusCode().value()).as(String.valueOf(moved.getBody())).isEqualTo(200);
        assertThat(moved.getBody().get("current")).isEqualTo(SECOND);
        assertThat(row(moved, SECOND).get("state")).isEqualTo("CURRENT");
        assertThat(row(moved, SECOND).get("senateMinute")).isEqualTo("SEN/TEST/2097/001");
        assertThat(row(moved, FIRST).get("state")).isEqualTo("CLOSED");

        // 6 · and closing this one leaves nothing current
        ResponseEntity<Map> closed = call(HttpMethod.POST, "/api/v1/calendar/sessions/" + SECOND + "/close", null);
        assertThat(closed.getStatusCode().value()).as(String.valueOf(closed.getBody())).isEqualTo(200);
        assertThat(row(closed, SECOND).get("state")).isEqualTo("CLOSED");
        assertThat(closed.getBody().get("current")).isNotEqualTo(SECOND);
    }

    @Test
    @SuppressWarnings("unchecked")
    void semestersAndUnitLimitsAreReadBackWhereTheScreenReadsThem() {
        assertThat(call(HttpMethod.PUT, "/api/v1/calendar/sessions/" + SECOND, session("2097-10-01", "2098-08-31"))
                .getStatusCode().value()).isEqualTo(200);

        ResponseEntity<Map> semester = call(HttpMethod.PUT, "/api/v1/calendar/sessions/" + SECOND + "/semesters/1",
                Map.ofEntries(Map.entry("lecturesFrom", "2097-10-14"), Map.entry("lecturesTo", "2098-01-31"),
                        Map.entry("registrationOpens", "2097-10-01"), Map.entry("registrationCloses", "2097-10-28"),
                        Map.entry("lateRegistrationCloses", "2097-11-11"), Map.entry("examsFrom", "2098-02-10"),
                        Map.entry("examsTo", "2098-02-21"), Map.entry("resultsDue", "2098-03-14"),
                        Map.entry("queryWindow", "5 working days from release"), Map.entry("state", "NOT_YET_OPEN")));
        assertThat(semester.getStatusCode().value()).as(String.valueOf(semester.getBody())).isEqualTo(200);

        // level 600 keeps the figures Senate set; what this records is the instrument
        ResponseEntity<Map> level = call(HttpMethod.PUT, "/api/v1/calendar/levels/600",
                Map.of("appliesTo", "MBBS", "minUnits", 15, "maxUnits", 24, "carryoverCounts", true,
                        "instrument", "SEN/TEST/2097/002"));
        assertThat(level.getStatusCode().value()).as(String.valueOf(level.getBody())).isEqualTo(200);

        ResponseEntity<Map> read = get("/api/v1/calendar?session=" + SECOND);
        assertThat(read.getStatusCode().value()).isEqualTo(200);
        List<Map<String, Object>> semesters = (List<Map<String, Object>>) read.getBody().get("semesters");
        assertThat(semesters).anySatisfy(s -> {
            assertThat(s.get("number")).isEqualTo(1);
            assertThat(s.get("registrationCloses")).isEqualTo("2097-10-28");
            assertThat(s.get("resultsDue")).isEqualTo("2098-03-14");
            assertThat(s.get("queryWindow")).isEqualTo("5 working days from release");
        });
        List<Map<String, Object>> limits = (List<Map<String, Object>>) read.getBody().get("levelLimits");
        assertThat(limits).anySatisfy(l -> {
            assertThat(l.get("level")).isEqualTo(600);
            assertThat(l.get("maxUnits")).isEqualTo(24);
            assertThat(l.get("instrument")).isEqualTo("SEN/TEST/2097/002");
        });
    }

    @Test
    @SuppressWarnings("unchecked")
    void aSignedInActorWithNoPersonRowStillGetsAnAnswer() {
        ResponseEntity<Map> me = get("/api/v1/staff/me");
        assertThat(me.getStatusCode().value()).as(String.valueOf(me.getBody())).isEqualTo(200);
        assertThat(me.getBody().get("person")).isNull();
        assertThat((List<Object>) me.getBody().get("offices")).isEmpty();
    }

    @Test
    @SuppressWarnings("unchecked")
    void theCollegeOfHealthSciencesNamesItsFaculties() {
        ResponseEntity<Map> college = get("/api/v1/staff/college/CHS");
        assertThat(college.getStatusCode().value()).as(String.valueOf(college.getBody())).isEqualTo(200);
        assertThat(((Map<String, Object>) college.getBody().get("college")).get("system")).isEqualTo("CHS-AMS");
        assertThat((List<Map<String, Object>>) college.getBody().get("faculties"))
                .anySatisfy(f -> assertThat(f.get("code")).isEqualTo("BAMS"));
        assertThat(college.getBody().get("students")).isNotNull();
    }
}
