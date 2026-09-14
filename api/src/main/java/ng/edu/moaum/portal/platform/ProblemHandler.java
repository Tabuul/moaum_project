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
        problem.setTitle(e.code().replace('_', ' '));
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
}
