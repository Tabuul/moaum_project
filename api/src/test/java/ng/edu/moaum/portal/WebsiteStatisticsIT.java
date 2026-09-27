package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.Map;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.ResponseEntity;
import org.springframework.web.client.RestClient;

/**
 * The public statistics the University's website shows: readable without a token, from another origin, with the
 * counts the reference lists and the register hold, and a cache header; a preflight to a protected path is refused.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class WebsiteStatisticsIT {
    @Value("${local.server.port}")
    int port;

    private RestClient anonymous() {
        return RestClient.builder().baseUrl("http://localhost:" + port).defaultStatusHandler(status -> true, (request, response) -> { }).build();
    }

    @Test
    void theWebsiteReadsTheFiguresWithoutSigningIn() {
        ResponseEntity<Map> r = anonymous().get().uri("/api/v1/public/statistics").header("Origin", "https://www.moaum.edu.ng").retrieve().toEntity(Map.class);
        assertThat(r.getStatusCode().value()).as(String.valueOf(r.getBody())).isEqualTo(200);
        assertThat(r.getHeaders().getAccessControlAllowOrigin()).isEqualTo("*");
        assertThat(r.getHeaders().getCacheControl()).contains("max-age=300");
        Map figures = (Map) r.getBody().get("figures");
        Map display = (Map) r.getBody().get("display");
        assertThat(((Number) figures.get("faculties")).longValue()).isGreaterThan(0);
        assertThat(((Number) figures.get("facultiesAndColleges")).longValue())
                .isEqualTo(((Number) figures.get("faculties")).longValue() + ((Number) figures.get("colleges")).longValue());
        assertThat(((Number) figures.get("academicDepartments")).longValue()).isGreaterThan(0);
        assertThat(((Number) figures.get("coursesOfStudy")).longValue())
                .isEqualTo(((Number) figures.get("undergraduateProgrammes")).longValue() + ((Number) figures.get("postgraduateProgrammes")).longValue());
        assertThat(((Number) figures.get("degreeProgrammeTypes")).longValue()).isGreaterThan(1);
        assertThat(((Number) figures.get("enrolledStudents")).longValue())
                .isEqualTo(((Number) figures.get("undergraduates")).longValue() + ((Number) figures.get("postgraduates")).longValue());
        assertThat(((Number) figures.get("academicAndSupportStaff")).longValue()).isGreaterThanOrEqualTo(((Number) figures.get("academicStaff")).longValue());
        assertThat(display.get("coursesOfStudy")).isEqualTo(java.text.NumberFormat.getIntegerInstance(java.util.Locale.UK).format(((Number) figures.get("coursesOfStudy")).longValue()));
        assertThat(r.getBody().get("awards")).isInstanceOf(java.util.List.class);
        assertThat(((Map) r.getBody().get("definitions")).get("enrolledStudents")).isNotNull();
    }

    @Test
    void theOpenDoorIsOnlyForThePublicFigures() {
        // a protected path is never opened to another origin: no allow-origin header on its preflight or on a read, and the read is refused
        ResponseEntity<String> preflight = anonymous().options().uri("/api/v1/me").header("Origin", "https://www.moaum.edu.ng")
                .header("Access-Control-Request-Method", "GET").retrieve().toEntity(String.class);
        assertThat(preflight.getHeaders().getAccessControlAllowOrigin()).isNull();
        ResponseEntity<String> read = anonymous().get().uri("/api/v1/me").header("Origin", "https://www.moaum.edu.ng").retrieve().toEntity(String.class);
        assertThat(read.getStatusCode().value()).isEqualTo(401);
        assertThat(read.getHeaders().getAccessControlAllowOrigin()).isNull();
        ResponseEntity<String> ok = anonymous().options().uri("/api/v1/public/statistics").header("Origin", "https://www.moaum.edu.ng")
                .header("Access-Control-Request-Method", "GET").retrieve().toEntity(String.class);
        assertThat(ok.getStatusCode().value()).isEqualTo(200);
        assertThat(ok.getHeaders().getAccessControlAllowOrigin()).isEqualTo("*");
    }
}
