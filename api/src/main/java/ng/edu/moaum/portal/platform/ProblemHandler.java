package ng.edu.moaum.portal.platform;

import java.net.URI;
import java.sql.SQLException;
import java.util.List;
import java.util.Map;

import jakarta.servlet.http.HttpServletRequest;

import ng.edu.moaum.portal.shared.DomainRuleViolation;
import ng.edu.moaum.portal.shared.NotFound;

import org.postgresql.util.PSQLException;
import org.postgresql.util.ServerErrorMessage;
import org.springframework.dao.DataAccessException;
import org.springframework.http.HttpStatus;
import org.springframework.http.ProblemDetail;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

/**
 * Every refusal is an RFC 9457 problem (DSN §8): a stable {@code code}, the
 * correlation id, and where a person can do something about it, a
 * {@code remedy} naming the responsible office.
 *
 * <p>The database's own refusals — the audit spine, the list-kind trigger, a
 * policy not in force — arrive as SQLSTATE 23514 with a message and a HINT
 * written for a person. They are passed through as 422 with the hint as the
 * remedy, because the database is where those rules live and its wording is
 * the wording that was reviewed. An exclusion constraint (23P01) is the same
 * kind of refusal wearing a different SQLSTATE — two academic sessions
 * overlapping, two policy versions in force at once — and is answered the
 * same way: it is a rule a person can do something about, not a fault.
 */
@RestControllerAdvice
class ProblemHandler {

    private static final String PROBLEM_BASE = "https://api.moaum.edu.ng/problems/";

    @ExceptionHandler(DomainRuleViolation.class)
    ProblemDetail domainRule(DomainRuleViolation e, HttpServletRequest request) {
        ProblemDetail problem = problem(HttpStatus.UNPROCESSABLE_CONTENT, e.getMessage(), request);
        problem.setType(URI.create(PROBLEM_BASE + e.code().toLowerCase().replace('_', '-')));
        problem.setTitle(titleOf(e.code()));
        problem.setProperty("code", e.code());
        if (e.remedy() != null) {
            // a remedy may name no office (an action the person takes themselves); Map.of rejects a
            // null value, so build a map that tolerates one rather than 500 on the way to a 422.
            Map<String, Object> remedy = new java.util.LinkedHashMap<>();
            remedy.put("message", e.remedy().message());
            remedy.put("office", e.remedy().office());
            problem.setProperty("remedy", remedy);
        }
        return problem;
    }

    @ExceptionHandler(NotFound.class)
    ProblemDetail notFound(NotFound e, HttpServletRequest request) {
        ProblemDetail problem = problem(HttpStatus.NOT_FOUND, e.getMessage(), request);
        problem.setProperty("code", "NOT_FOUND");
        return problem;
    }

    @ExceptionHandler(MethodArgumentNotValidException.class)
    ProblemDetail invalid(MethodArgumentNotValidException e, HttpServletRequest request) {
        List<Map<String, Object>> violations = e.getBindingResult().getFieldErrors().stream()
                .map(f -> Map.<String, Object>of("field", f.getField(), "code", "INVALID",
                        "message", f.getDefaultMessage() == null ? "invalid" : f.getDefaultMessage()))
                .toList();
        ProblemDetail problem = problem(HttpStatus.BAD_REQUEST, "The request did not validate.", request);
        problem.setProperty("code", "VALIDATION_FAILED");
        problem.setProperty("violations", violations);
        return problem;
    }

    @ExceptionHandler(DataAccessException.class)
    ProblemDetail database(DataAccessException e, HttpServletRequest request) {
        PSQLException pg = postgres(e);
        if (pg == null) {
            throw e;
        }
        ServerErrorMessage server = pg.getServerErrorMessage();
        String state = pg.getSQLState();
        String message = server == null ? pg.getMessage() : server.getMessage();
        String hint = server == null ? null : server.getHint();

        if ("23514".equals(state) && message != null && message.startsWith("unattributed change")) {
            ProblemDetail problem = problem(HttpStatus.FORBIDDEN,
                    "This request names no acting office, so it may read but not change anything.", request);
            problem.setProperty("code", "NO_ACTING_OFFICE");
            problem.setProperty("remedy", Map.of("message",
                    "Send X-Active-Office with one of the offices your token carries.", "office", "Directorate of ICT"));
            return problem;
        }
        if ("23514".equals(state) || "23502".equals(state) || "22P02".equals(state) || "P0002".equals(state)
                || "23P01".equals(state)) {
            ProblemDetail problem = problem(HttpStatus.UNPROCESSABLE_CONTENT, message, request);
            problem.setProperty("code", "DATABASE_RULE_REFUSED");
            if (hint != null) {
                problem.setProperty("remedy", Map.of("message", hint, "office", "the office named in the rule"));
            }
            return problem;
        }
        if ("23505".equals(state) || "23503".equals(state)) {
            ProblemDetail problem = problem(HttpStatus.CONFLICT, message, request);
            problem.setProperty("code", "23505".equals(state) ? "ALREADY_EXISTS" : "REFERENCE_MISSING");
            return problem;
        }
        if ("42501".equals(state)) {
            ProblemDetail problem = problem(HttpStatus.FORBIDDEN, message, request);
            problem.setProperty("code", "DATABASE_PERMISSION");
            return problem;
        }
        /* any other database error: surface its message rather than a blank 500, so a refusal is legible */
        ProblemDetail problem = problem(HttpStatus.UNPROCESSABLE_CONTENT,
                message == null || message.isBlank() ? "The database refused this request." : message, request);
        problem.setProperty("code", "DATABASE_REFUSED");
        if (state != null) {
            problem.setProperty("sqlstate", state);
        }
        return problem;
    }

    private static PSQLException postgres(Throwable t) {
        for (Throwable c = t; c != null; c = c.getCause()) {
            if (c instanceof PSQLException pg) {
                return pg;
            }
            if (c instanceof SQLException && c.getCause() == null) {
                return null;
            }
            if (c.getCause() == c) {
                break;
            }
        }
        return null;
    }

    private static ProblemDetail problem(HttpStatus status, String detail, HttpServletRequest request) {
        ProblemDetail problem = ProblemDetail.forStatusAndDetail(status, detail);
        problem.setInstance(URI.create(request.getRequestURI()));
        problem.setProperty("correlationId", CorrelationIdFilter.of(request).toString());
        return problem;
    }

    /* ── the title a person reads: the code's own words in plain English, never the code ── */
    private static final Map<String, String> TITLES = Map.ofEntries(
            Map.entry("AUTH_BAD_CREDENTIALS", "Wrong username or password"),
            Map.entry("AUTH_LOCKED", "Account locked for now"),
            Map.entry("AUTH_THROTTLED", "Too many attempts"),
            Map.entry("AUTH_RESET_TOKEN", "That reset link is not valid"),
            Map.entry("AUTH_PASSWORD_SHORT", "Password too short"),
            Map.entry("APP_PASSWORD_SHORT", "Password too short"),
            Map.entry("AUTH_PASSWORD_IS_USERNAME", "The password cannot be the username"),
            Map.entry("AUTH_USERNAME_TAKEN", "That username is taken"),
            Map.entry("AUTH_NO_STUDENT_ACCOUNT", "No student account yet"),
            Map.entry("AUTH_SIGN_IN_ELSEWHERE", "Sign in through the other door"),
            Map.entry("PAY_GATEWAY_UNREACHABLE", "The payment gateway is not reachable"),
            Map.entry("PAY_GATEWAY_REFUSED", "The payment was refused"),
            Map.entry("PAY_ALREADY_CONFIRMED", "That payment is already confirmed"),
            Map.entry("PAY_REFERENCE_EXPIRED", "That payment reference has expired"),
            Map.entry("REG_UNITS_OUT_OF_RANGE", "Units out of range"),
            Map.entry("REG_STUDENT_NOT_ELIGIBLE", "Not eligible to register"),
            Map.entry("COLLEGE_NOT_MEMBER", "Not a College student"),
            Map.entry("COLLEGE_YEAR_NOT_ENDED", "The year has not ended"),
            Map.entry("COLLEGE_NOT_YOUR_LEVEL", "Not your level"),
            Map.entry("COLLEGE_CA_RANGE", "CA out of range"),
            Map.entry("COLLEGE_EXAM_RANGE", "Examination mark out of range"),
            Map.entry("STUDENT_RECORD_CLOSED", "This record is closed"),
            Map.entry("IAM_NO_SUCH_OFFICE", "No such office"),
            Map.entry("IAM_GRANT_NEEDS_INSTRUMENT", "An instrument is needed"));

    static String titleOf(String code) {
        if (code == null || code.isBlank()) return "The request was refused";
        String known = TITLES.get(code);
        if (known != null) return known;
        String[] words = code.split("_");
        String[] rest = words.length > 2 ? java.util.Arrays.copyOfRange(words, 1, words.length) : words;   // the module prefix goes when there is more to say
        String tail = String.join(" ", rest);
        if (code.endsWith("_SAYS_WHY")) return "A reason is needed";
        if (code.endsWith("_MINUTE_REQUIRED")) return "A minute is needed";
        if (code.endsWith("_ROWS")) return "The file's rows could not be read";
        if (code.endsWith("_RANGE")) return sentence(String.join(" ", java.util.Arrays.copyOfRange(rest, 0, Math.max(rest.length - 1, 0))).isBlank() ? "Value" : String.join(" ", java.util.Arrays.copyOfRange(rest, 0, rest.length - 1))) + " out of range";
        if (code.endsWith("_SIZE")) return "The file is too large";
        if (code.endsWith("_TYPE")) return "That file type is not accepted";
        if (code.endsWith("_ENCODING")) return "The file could not be read";
        return sentence(tail);
    }

    private static String sentence(String s) {
        String w = s.toLowerCase().trim();
        return w.isEmpty() ? s : Character.toUpperCase(w.charAt(0)) + w.substring(1);
    }
}
