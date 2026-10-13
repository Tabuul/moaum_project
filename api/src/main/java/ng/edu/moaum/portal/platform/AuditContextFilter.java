package ng.edu.moaum.portal.platform;

import java.io.IOException;
import java.util.List;
import java.util.UUID;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;

import ng.edu.moaum.portal.shared.AuditContext;
import ng.edu.moaum.portal.shared.AuditContextHolder;

import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;
import org.springframework.web.filter.OncePerRequestFilter;

/**
 * Turns the authenticated principal into the request's {@link AuditContext}.
 *
 * <p>The actor is the token's subject (Keycloak issues a UUID). The acting
 * office is {@code X-Active-Office} when the request names one — a Dean who is
 * also a lecturer acts as one or the other, never both — and otherwise the
 * first office the token carries. An office the token does not carry is
 * refused here, before any service runs.
 *
 * <p>A request with no office at all still proceeds: reads need no
 * attribution, and any write it attempts is refused by the database.
 */
public class AuditContextFilter extends OncePerRequestFilter {

    public static final String SESSION_CLAIM = "sid";

    private final SessionGuard sessions;

    public AuditContextFilter(SessionGuard sessions) {
        this.sessions = sessions;
    }

    public static final String ACTIVE_OFFICE_HEADER = "X-Active-Office";
    public static final String REASON_HEADER = "X-Reason";
    public static final String OFFICES_CLAIM = "offices";
    /** V437: a request the browser sends on its own — a poll, a board refreshing — never counts as the person's activity */
    public static final String BACKGROUND_HEADER = "X-Background";
    /** a request this long (an upload) is activity to its end as well, not only at its start */
    private static final long LONG_REQUEST_MS = 10_000;

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain chain)
            throws ServletException, IOException {
        Authentication authentication = SecurityContextHolder.getContext().getAuthentication();
        String longRequest = null;
        long startedAt = System.currentTimeMillis();
        if (authentication instanceof JwtAuthenticationToken token) {
            Jwt jwt = token.getToken();
            UUID actor;
            try {
                actor = UUID.fromString(jwt.getSubject());
            } catch (IllegalArgumentException | NullPointerException notAUuid) {
                refuse(response, HttpStatus.UNAUTHORIZED, "The token's subject is not a person id.");
                return;
            }
            String sid = jwt.getClaimAsString(SESSION_CLAIM);
            boolean quiet = "1".equals(request.getHeader(BACKGROUND_HEADER));
            if (sid != null && sessions != null) {
                java.util.Optional<SessionGuard.Refusal> refused = sessions.refuse(sid, quiet);
                if (refused.isPresent()) {
                    refuse(response, HttpStatus.UNAUTHORIZED, refused.get().code(), refused.get().detail());
                    return;
                }
                if (!quiet) {
                    longRequest = sid;
                }
            }
            List<String> offices = offices(jwt);
            String active = request.getHeader(ACTIVE_OFFICE_HEADER);
            if (active != null && !active.isBlank()) {
                active = active.trim();
                if (!offices.contains(active)) {
                    refuse(response, HttpStatus.FORBIDDEN,
                            "The office '" + active + "' is not one this token carries: " + offices + ".");
                    return;
                }
            } else {
                active = offices.isEmpty() ? null : offices.getFirst();
            }
            if (active != null) {
                AuditContextHolder.set(new AuditContext(actor, active, request.getHeader(REASON_HEADER),
                        CorrelationIdFilter.of(request), request.getRemoteAddr()));
            }
        }
        try {
            chain.doFilter(request, response);
        } finally {
            AuditContextHolder.clear();
            // an upload that took a while is activity until it finished, so the session is not judged idle from its start
            if (longRequest != null && sessions != null && System.currentTimeMillis() - startedAt > LONG_REQUEST_MS) {
                sessions.touch(longRequest);
            }
        }
    }

    static List<String> offices(Jwt jwt) {
        List<String> offices = jwt.getClaimAsStringList(OFFICES_CLAIM);
        return offices == null ? List.of() : offices;
    }

    private static void refuse(HttpServletResponse response, HttpStatus status, String detail) throws IOException {
        refuse(response, status, null, detail);
    }

    /** a refusal as a problem, with a stable code when there is one (the portal reads SESSION_EXPIRED_IDLE to say "Session expired") */
    private static void refuse(HttpServletResponse response, HttpStatus status, String code, String detail) throws IOException {
        response.setStatus(status.value());
        response.setContentType(MediaType.APPLICATION_PROBLEM_JSON_VALUE);
        response.getWriter().write("{\"type\":\"about:blank\",\"title\":\"" + status.getReasonPhrase()
                + "\",\"status\":" + status.value() + (code == null ? "" : ",\"code\":\"" + code + "\"")
                + ",\"detail\":\"" + detail.replace("\"", "'") + "\"}");
    }
}
