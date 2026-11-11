package ng.edu.moaum.portal.platform;

import java.net.URI;
import java.sql.SQLException;
import java.util.List;
import java.util.Map;

import jakarta.servlet.http.HttpServletRequest;

import ng.edu.moaum.portal.shared.DomainRuleViolation;
import ng.edu.moaum.portal.shared.NotFound;
import ng.edu.moaum.portal.shared.Throttle;

import org.postgresql.util.PSQLException;
import org.postgresql.util.ServerErrorMessage;
import org.springframework.core.Ordered;
import org.springframework.core.annotation.Order;
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
 *
 * <p>Ordered first (27 October 2026): Spring Boot's own problem handler
 * (spring.mvc.problemdetails.enabled) is ordered 0 and also answers a body
 * that fails its checks, with a bare "Bad Request — Invalid request content."
 * that names no field; this answer, which names them, is the one sent. Only
 * the exceptions handled here are affected; every other one still reaches
 * Spring Boot's handler.
 */
@RestControllerAdvice
@Order(Ordered.HIGHEST_PRECEDENCE)
class ProblemHandler {

    private static final String PROBLEM_BASE = "https://api.moaum.edu.ng/problems/";
    private static final org.slf4j.Logger log = org.slf4j.LoggerFactory.getLogger(ProblemHandler.class);

    /** 11 Nov 2026: each statement the database stops, kept for ICT's Slow statements page */
    private final QueryCancellations cancellations;

    ProblemHandler(QueryCancellations cancellations) {
        this.cancellations = cancellations;
    }

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

    /** V359: a public door's limit spent — 429, and when to knock again */
    @ExceptionHandler(Throttle.Throttled.class)
    org.springframework.http.ResponseEntity<ProblemDetail> throttled(Throttle.Throttled e, HttpServletRequest request) {
        ProblemDetail problem = domainRule(e, request);
        problem.setStatus(HttpStatus.TOO_MANY_REQUESTS.value());
        return org.springframework.http.ResponseEntity.status(HttpStatus.TOO_MANY_REQUESTS)
                .header("Retry-After", String.valueOf(e.retryAfterSeconds())).body(problem);
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
        // the fields named in words ("programmeCode" → "programme code"), so the toast says what to correct
        String fields = e.getBindingResult().getFieldErrors().stream().map(f -> fieldWords(f.getField())).distinct()
                .collect(java.util.stream.Collectors.joining(", "));
        ProblemDetail problem = problem(HttpStatus.BAD_REQUEST,
                fields.isEmpty() ? "The request did not validate." : "Not accepted as entered: " + fields + ".", request);
        problem.setTitle("Please check the form");
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
            // a rule that names its own business code ("SCHOOL_FEES_PAYMENT_CLOSED: ...") carries it (V288); the rest are the database's refusals
            java.util.regex.Matcher coded = message == null ? null : java.util.regex.Pattern.compile("^([A-Z][A-Z0-9_]{3,60}): (.+)$", java.util.regex.Pattern.DOTALL).matcher(message);
            boolean named = coded != null && coded.matches();
            ProblemDetail problem = problem(HttpStatus.UNPROCESSABLE_CONTENT, named ? coded.group(2) : message, request);
            problem.setProperty("code", named ? coded.group(1) : "DATABASE_RULE_REFUSED");
            if (hint != null) {
                problem.setProperty("remedy", Map.of("message", hint, "office", "the office named in the rule"));
            }
            return problem;
        }
        if ("25006".equals(state)) {
            // V521: a read-only transaction asked to write — ICT Support viewing a student's portal
            ProblemDetail problem = problem(HttpStatus.FORBIDDEN, "ICT Support is viewing this student's portal read-only: this screen would record something for the student, so it is not opened from the student view.", request);
            problem.setProperty("code", "SUPPORT_VIEW_READ_ONLY");
            return problem;
        }
        if ("57014".equals(state)) {
            return stopped(message, request, e);
        }
        if ("23505".equals(state) || "23503".equals(state)) {
            ProblemDetail problem = problem(HttpStatus.CONFLICT, message, request);
            problem.setProperty("code", "23505".equals(state) ? "ALREADY_EXISTS" : "REFERENCE_MISSING");
            return problem;
        }
        if ("42501".equals(state)) {
            // V527: a refusal that names its own code ("SWAP_SAME_OFFICER: ...") carries it, as a rule's does above
            java.util.regex.Matcher coded = message == null ? null : java.util.regex.Pattern.compile("^([A-Z][A-Z0-9_]{3,60}): (.+)$", java.util.regex.Pattern.DOTALL).matcher(message);
            boolean named = coded != null && coded.matches();
            ProblemDetail problem = problem(HttpStatus.FORBIDDEN, named ? coded.group(2) : message, request);
            problem.setProperty("code", named ? coded.group(1) : "DATABASE_PERMISSION");
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

    /**
     * SQLSTATE 57014: the database stopped a statement before it finished. Oct 2026 answered every one as the portal's read limit;
     * since 11 November 2026 the answer names what stopped it — the portal's limit on a screen's read, the PAYDirect door's own
     * limit, a statement timeout set outside the portal (the server, the database, the role or the connection), or a cancel request
     * — from the database's own words and the portal's limit noted on the failing statement where it failed (StoppedStatement; the
     * request's note of its latest transaction only where the statement did not pass the portal's JdbcTemplate), logs it once at
     * WARN with how long the request had run, and keeps it for ICT (QueryCancellations). The code stays QUERY_TOO_LONG for a time
     * limit; a cancel is QUERY_CANCELLED.
     */
    ProblemDetail stopped(String databaseSaid, HttpServletRequest request, Throwable failure) {
        StoppedStatement noted = StoppedStatement.in(failure);
        String transaction;
        Long limit;
        StoppedStatement.Limit limitKind;
        if (noted != null) {
            transaction = noted.transaction();
            limit = noted.portalLimitMs();
            limitKind = noted.portalLimit();
        } else {
            transaction = request.getAttribute(AttributedTransactionManager.TRANSACTION_ATTRIBUTE) instanceof String t ? t : null;
            limit = "READ".equals(transaction) && request.getAttribute(AttributedTransactionManager.READ_LIMIT_ATTRIBUTE) instanceof Long l ? l : null;
            limitKind = limit == null ? null : StoppedStatement.Limit.SCREEN_READ;
        }
        QueryCancellations.Cause cause = QueryCancellations.cause(databaseSaid, limitKind);
        if (cause != QueryCancellations.Cause.PORTAL_READ_LIMIT && cause != QueryCancellations.Cause.PAYDIRECT_DOOR_LIMIT) {
            limit = null;   // a limit the portal placed but which did not stop this statement is not shown as its cause
        }
        Long ranFor = CorrelationIdFilter.ranForMs(request);
        String route = request.getAttribute(org.springframework.web.servlet.HandlerMapping.BEST_MATCHING_PATTERN_ATTRIBUTE) instanceof String p
                ? p : "(no route)";
        // the office the request acted as (AuditContextFilter's: the header checked against the token, else the token's first office)
        String office = ng.edu.moaum.portal.shared.AuditContextHolder.current().map(ng.edu.moaum.portal.shared.AuditContext::actorOffice).orElse(null);
        String reference = CorrelationIdFilter.of(request).toString();
        String ran = ranFor == null ? "" : " after " + seconds(ranFor);
        String detail;
        String title;
        String remedy;
        switch (cause) {
            case PORTAL_READ_LIMIT -> {
                title = "This screen took too long to read";
                detail = "This took longer than the portal allows a screen to read (" + seconds(limit) + "), and was stopped" + ran
                        + " so other work is not kept waiting.";
                remedy = "Narrow the list (a session, a faculty, a department) and try again; if it recurs, tell the Directorate of ICT which screen.";
            }
            case PAYDIRECT_DOOR_LIMIT -> {
                title = "The payment door stopped this: it ran too long";
                detail = "This took longer than the portal allows the PAYDirect door one statement (" + seconds(limit) + "), and was stopped" + ran
                        + ". The work it was doing when it was stopped was not saved.";
                remedy = "The bank's system asks again; if it recurs, tell the Directorate of ICT — its Slow statements page lists what was stopped.";
            }
            case DATABASE_STATEMENT_TIMEOUT -> {
                title = "The database stopped this: it ran too long";
                detail = "The database stopped this" + ran + ": it ran longer than the database allows one statement to run. "
                        + "The work it was doing when it was stopped was not saved.";
                remedy = "Try again; if it recurs, tell the Directorate of ICT which screen and when — its Slow statements page shows the database's time limit and what it stopped.";
            }
            case CANCEL_REQUEST -> {
                title = "This was stopped before it finished";
                detail = "A cancel request stopped this" + (ranFor == null ? "" : " " + seconds(ranFor) + " in") + ", before it finished. "
                        + "The work it was doing when it was stopped was not saved.";
                remedy = "Try again; if it recurs, tell the Directorate of ICT which screen and when — its Slow statements page lists what was stopped.";
            }
            default -> {
                title = "The database stopped this before it finished";
                detail = "The database stopped this" + ran + " before it finished. The work it was doing when it was stopped was not saved.";
                remedy = "Try again; if it recurs, tell the Directorate of ICT which screen and when.";
            }
        }
        ProblemDetail problem = problem(HttpStatus.SERVICE_UNAVAILABLE, detail, request);
        problem.setTitle(title);
        problem.setProperty("code", cause == QueryCancellations.Cause.CANCEL_REQUEST || cause == QueryCancellations.Cause.OTHER
                ? "QUERY_CANCELLED" : "QUERY_TOO_LONG");
        problem.setProperty("cause", cause.name());
        problem.setProperty("remedy", Map.of("message", remedy, "office", "Directorate of ICT"));
        log.warn("statement stopped: {} — the database said \"{}\"; {} transaction{}, {} ms into {} {}, office {}, reference {}",
                cause, databaseSaid, transaction == null ? "no" : transaction, limit == null ? "" : " under the portal's " + limit + " ms limit",
                ranFor == null ? "?" : ranFor, request.getMethod(), route, office == null ? "-" : office, reference);
        cancellations.record(new QueryCancellations.Cancellation(java.time.Instant.now(), cause, transaction, limit, ranFor,
                request.getMethod(), route, office, reference, databaseSaid));
        return problem;
    }

    /** milliseconds as a person reads them: 90 s, 1.5 s, 4 min 12 s — seconds below two minutes, as the portal words its 90 s */
    static String seconds(Long ms) {
        if (ms == null) {
            return "";
        }
        if (ms >= 120_000) {
            long s = Math.round(ms / 1000.0);
            return (s / 60) + " min" + (s % 60 == 0 ? "" : " " + (s % 60) + " s");
        }
        if (ms >= 10_000 || ms % 1000 == 0) {
            return Math.round(ms / 1000.0) + " s";
        }
        return String.format(java.util.Locale.ENGLISH, "%.1f s", ms / 1000.0);
    }

    private static ProblemDetail problem(HttpStatus status, String detail, HttpServletRequest request) {
        ProblemDetail problem = ProblemDetail.forStatusAndDetail(status, detail);
        problem.setInstance(URI.create(request.getRequestURI()));
        problem.setProperty("correlationId", CorrelationIdFilter.of(request).toString());
        return problem;
    }

    /* ── the title a person reads: the code's own words in plain English, never the code ── */
    private static final Map<String, String> TITLES = Map.ofEntries(
            // V408: the course allocation desk
            Map.entry("ALLOC_CAPABILITY", "Not in your support posting"), Map.entry("ALLOC_SCOPE", "Outside your allocation scope"),
            Map.entry("ALLOC_REASON", "A reason is needed"), Map.entry("ALLOC_DUPLICATE", "Already allocated"),
            Map.entry("ALLOC_TICKET", "No such ticket"), Map.entry("ALLOC_TICKET_SCOPE", "Ticket outside your scope"),
            Map.entry("ALLOC_ACTIVE", "Not an active member of staff"), Map.entry("ALLOC_TEACHING", "Not a lecturer"),
            Map.entry("ALLOC_OVERLOAD", "Over the approved load"), Map.entry("ALLOC_COURSE", "Course not available for allocation"),
            Map.entry("ALLOC_OFFERED", "Course not offered here"), Map.entry("ALLOC_SESSION", "Session not on the calendar"),
            Map.entry("ALLOC_LECTURER", "Staff member not found"), Map.entry("ALLOC_NO_LEAD", "No lead lecturer yet"),
            Map.entry("ALLOC_SECOND_IS_LEAD", "The lecturer cannot verify their own marks"), Map.entry("ALLOC_SECOND_NOT_TEACHING", "Not an active lecturer"),
            Map.entry("ALLOC_NOT_CO_LECTURER", "Not a co-lecturer of this class"),
            Map.entry("AUTH_BAD_CREDENTIALS", "Wrong username or password"),
            Map.entry("AUTH_LOCKED", "Account locked for now"),
            Map.entry("AUTH_THROTTLED", "Too many attempts"),
            Map.entry("APP_THROTTLED", "Too many attempts"),
            Map.entry("VERIFY_THROTTLED", "Too many checks"),
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
            Map.entry("REG_UNITS_BELOW_MINIMUM", "Below the minimum credit load"),
            Map.entry("REG_MIN_UNITS_POSITIVE", "Minimum credit units must be greater than zero"),
            Map.entry("REG_MIN_UNITS_OVER_MAXIMUM", "Minimum above the maximum"),
            Map.entry("REG_STUDENT_NOT_ELIGIBLE", "Not eligible to register"),
            Map.entry("COLLEGE_NOT_MEMBER", "Not a College student"),
            Map.entry("COLLEGE_YEAR_NOT_ENDED", "The year has not ended"),
            Map.entry("COLLEGE_NOT_YOUR_LEVEL", "Not your level"),
            Map.entry("COLLEGE_CA_RANGE", "CA out of range"),
            Map.entry("COLLEGE_EXAM_RANGE", "Examination mark out of range"),
            Map.entry("STUDENT_RECORD_CLOSED", "This record is closed"),
            Map.entry("IAM_NO_SUCH_OFFICE", "No such office"),
            Map.entry("IAM_GRANT_NEEDS_INSTRUMENT", "An instrument is needed"),
            // V527: the school fees payment swap
            Map.entry("SWAP_OFFICE", "Not for your office"), Map.entry("SWAP_SAME_OFFICER", "Another officer decides this swap"),
            Map.entry("SWAP_REASON", "A reason is needed"), Map.entry("SWAP_CONFIRM", "Your confirmation is needed"),
            Map.entry("SWAP_OPEN", "A swap of this payment is waiting"), Map.entry("SWAP_ALREADY_SWAPPED", "Already reallocated"),
            Map.entry("SWAP_SAME_STUDENT", "The same student"), Map.entry("SWAP_NOT_SCHOOL_FEES", "Not a school fees payment"),
            Map.entry("SWAP_NOT_VERIFIED", "Payment not verified"), Map.entry("SWAP_DECIDED", "Already decided"),
            Map.entry("SWAP_RECONCILIATION", "The accounts did not reconcile"), Map.entry("SWAP_SEARCH", "Type a little more"),
            // Oct 2026: the sign-in help form checks a student's number
            Map.entry("HELPDESK_HELP_NUMBER_UNKNOWN", "Number not on the register"), Map.entry("HELPDESK_CHECK_SLOW_DOWN", "Too many checks"),
            // V564: the postgraduate application door
            Map.entry("PG_APP_EXISTS", "Already applied with this email"), Map.entry("PG_APPLY_RETRY", "Not saved: please try again"),
            // V694: one application per person a session; the desk's documents filter
            Map.entry("PG_APPLY_DOB", "Date of birth needed"), Map.entry("PG_DOCUMENTS_FILTER", "Not a documents filter"),
            // V578: the programme swap
            Map.entry("PSW_SAME_OFFICER", "Another officer decides"), Map.entry("PSW_OFFICE", "Not for this office"), Map.entry("PSW_PENDING", "A swap is already pending"),
            Map.entry("PSW_TRANSFER_OPEN", "A transfer is under way"), Map.entry("PSW_LEVEL", "Not a level of that programme"), Map.entry("PSW_CATEGORY", "Not a programme swap"),
            Map.entry("PSW_SAME", "Nothing would change"), Map.entry("PSW_REASON", "Say why"), Map.entry("PSW_DECIDED", "Already decided"),
            Map.entry("PSW_STUDENT_STATE", "The record is not live"), Map.entry("PSW_PROGRAMME", "Choose a programme"), Map.entry("PSW_PROGRAMME_ARCHIVED", "Programme archived"),
            Map.entry("PSW_SESSION", "Not a session"), Map.entry("PSW_KIND", "Say what the swap is"), Map.entry("PSW_CHANGE_REQUESTED", "A change is requested at admissions"),
            Map.entry("PSW_EVIDENCE_TYPE", "PDF, JPEG or PNG only"), Map.entry("PSW_EVIDENCE_SIZE", "File too large"), Map.entry("PSW_NOT_FOUND", "No such swap"),
            Map.entry("PSW_REVIEW_STATUS", "Not a review status"), Map.entry("PSW_CHANGED", "The record changed; prepare again"));

    /** a request field as a person reads it: "programmeCode" → "programme code", "rows[2].amount" → "amount" */
    static String fieldWords(String field) {
        if (field == null || field.isBlank()) return "a field";
        String last = field.substring(field.lastIndexOf('.') + 1).replaceAll("\\[.*?]", "");
        return last.replaceAll("([a-z0-9])([A-Z])", "$1 $2").replace('_', ' ').toLowerCase(java.util.Locale.ROOT).trim();
    }

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
