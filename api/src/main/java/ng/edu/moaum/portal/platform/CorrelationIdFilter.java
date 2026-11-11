package ng.edu.moaum.portal.platform;

import java.io.IOException;
import java.util.UUID;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;

import org.slf4j.MDC;
import org.springframework.core.Ordered;
import org.springframework.core.annotation.Order;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

/**
 * {@code X-Correlation-Id} is accepted and echoed, and generated when absent
 * (DSN §8). It is the id that ties a log line, an audit row and a problem
 * response to one request, so it is the first thing set and the last thing
 * cleared.
 */
@Component
@Order(Ordered.HIGHEST_PRECEDENCE)
public class CorrelationIdFilter extends OncePerRequestFilter {

    public static final String HEADER = "X-Correlation-Id";
    public static final String ATTRIBUTE = CorrelationIdFilter.class.getName() + ".id";
    static final String MDC_KEY = "correlationId";
    /** 11 Nov 2026: when the request arrived (System.nanoTime), so a statement the database stops is told with how long it had run */
    public static final String STARTED_ATTRIBUTE = CorrelationIdFilter.class.getName() + ".startedNanos";

    /** how long the request has run, in milliseconds; null where its arrival was not noted */
    public static Long ranForMs(HttpServletRequest request) {
        Object started = request.getAttribute(STARTED_ATTRIBUTE);
        return started instanceof Long nanos ? (System.nanoTime() - nanos) / 1_000_000 : null;
    }

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain chain)
            throws ServletException, IOException {
        UUID id = parse(request.getHeader(HEADER));
        request.setAttribute(ATTRIBUTE, id);
        request.setAttribute(STARTED_ATTRIBUTE, System.nanoTime());
        response.setHeader(HEADER, id.toString());
        MDC.put(MDC_KEY, id.toString());
        try {
            chain.doFilter(request, response);
        } finally {
            MDC.remove(MDC_KEY);
        }
    }

    static UUID parse(String header) {
        if (header == null || header.isBlank()) {
            return UUID.randomUUID();
        }
        try {
            return UUID.fromString(header.trim());
        } catch (IllegalArgumentException notAUuid) {
            // a caller-supplied id that is not a UUID is not trusted as one; a fresh id is issued instead
            return UUID.randomUUID();
        }
    }

    public static UUID of(HttpServletRequest request) {
        Object id = request.getAttribute(ATTRIBUTE);
        return id instanceof UUID uuid ? uuid : UUID.randomUUID();
    }
}
