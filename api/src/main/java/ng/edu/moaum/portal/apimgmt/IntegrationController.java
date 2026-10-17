package ng.edu.moaum.portal.apimgmt;

import java.net.URI;
import java.util.LinkedHashMap;
import java.util.Map;

import jakarta.servlet.http.HttpServletRequest;

import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * V511: the integration door — read-only calls from outside the University with an API key the Directorate of ICT issued (V047),
 * sent as {@code X-API-Key}. The key is the credential (the path is open to the security chain, as the PAYDirect doors are): the
 * database checks it by its hash (live, of an ACTIVE consumer), the scope and the consumer's daily quota, answers, and logs every
 * call (apimgmt.request_log). The first read is the student status lookup (scope students:status).
 */
@RestController
@RequestMapping("/api/integration/v1")
class IntegrationController {

    private static final Map<String, HttpStatus> STATUS = Map.of(
            "BAD_KEY", HttpStatus.UNAUTHORIZED, "NO_SCOPE", HttpStatus.FORBIDDEN, "OVER_QUOTA", HttpStatus.TOO_MANY_REQUESTS,
            "NOT_FOUND", HttpStatus.NOT_FOUND, "BAD_REQUEST", HttpStatus.BAD_REQUEST);
    private static final Map<String, String> SAID = Map.of(
            "BAD_KEY", "The API key is missing, unknown, revoked or expired.",
            "NO_SCOPE", "The key's consumer does not hold the students:status scope.",
            "OVER_QUOTA", "The consumer's calls for today are used up; the count starts again at midnight, Lagos time.",
            "NOT_FOUND", "No student has that matriculation number.",
            "BAD_REQUEST", "A matriculation number is 4 to 40 letters, digits, / . _ or -.");
    private static final tools.jackson.databind.ObjectMapper JSON = new tools.jackson.databind.ObjectMapper();

    private final JdbcClient jdbc;

    IntegrationController(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    private static String caller(HttpServletRequest request) {
        String fwd = request.getHeader("X-Forwarded-For");
        return fwd != null && !fwd.isBlank() ? fwd.split(",")[0].trim() : request.getRemoteAddr();
    }

    /** whether a matriculation number is a student of the University, and minimally how (scope students:status) */
    @GetMapping("/students/status")
    @Transactional
    @SuppressWarnings("unchecked")
    ResponseEntity<Map<String, Object>> studentStatus(@RequestHeader(name = "X-API-Key", required = false) String key,
                                                      @RequestParam(required = false) String matric, HttpServletRequest request) {
        Map<String, Object> out = JSON.readValue(jdbc.sql("SELECT apimgmt.student_status(:k, :m, :ip)::text")
                .param("k", key == null ? "" : key.trim()).param("m", matric == null ? "" : matric).param("ip", caller(request))
                .query(String.class).single(), Map.class);
        String outcome = String.valueOf(out.get("outcome"));
        if ("OK".equals(outcome)) {
            return ResponseEntity.ok().contentType(MediaType.APPLICATION_JSON).header("Cache-Control", "no-store").body((Map<String, Object>) out.get("student"));
        }
        HttpStatus status = STATUS.getOrDefault(outcome, HttpStatus.BAD_REQUEST);
        Map<String, Object> problem = new LinkedHashMap<>();
        problem.put("type", URI.create("https://moaum.edu.ng/problems/integration/" + outcome.toLowerCase().replace('_', '-')).toString());
        problem.put("title", SAID.getOrDefault(outcome, "The call was refused."));
        problem.put("status", status.value());
        problem.put("code", "API_" + outcome);
        return ResponseEntity.status(status).contentType(MediaType.APPLICATION_PROBLEM_JSON).header("Cache-Control", "no-store").body(problem);
    }
}
