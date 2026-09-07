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

    public static final String ACTIVE_OFFICE_HEADER = "X-Active-Office";
    public static final String REASON_HEADER = "X-Reason";
    public static final String OFFICES_CLAIM = "offices";

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain chain)
            throws ServletException, IOException {
        Authentication authentication = SecurityContextHolder.getContext().getAuthentication();
        if (authentication instanceof JwtAuthenticationToken token) {
            Jwt jwt = token.getToken();
            UUID actor;
            try {
                actor = UUID.fromString(jwt.getSubject());
            } catch (IllegalArgumentException | NullPointerException notAUuid) {
                refuse(response, HttpStatus.UNAUTHORIZED, "The token's subject is not a person id.");
                return;
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
        }
    }

    static List<String> offices(Jwt jwt) {
        List<String> offices = jwt.getClaimAsStringList(OFFICES_CLAIM);
        return offices == null ? List.of() : offices;
    }

    private static void refuse(HttpServletResponse response, HttpStatus status, String detail) throws IOException {
        response.setStatus(status.value());
        response.setContentType(MediaType.APPLICATION_PROBLEM_JSON_VALUE);
        response.getWriter().write("{\"type\":\"about:blank\",\"title\":\"" + status.getReasonPhrase()
                + "\",\"status\":" + status.value() + ",\"detail\":\"" + detail.replace("\"", "'") + "\"}");
    }
}
