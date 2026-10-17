package ng.edu.moaum.portal.platform;

import java.util.UUID;

import jakarta.servlet.http.HttpServletRequest;

import org.springframework.web.context.request.RequestAttributes;
import org.springframework.web.context.request.RequestContextHolder;

/**
 * V521: ICT Support viewing a student's portal as the student. The token of such a session (helpdesk.open_portal_view) names
 * the agent in its {@code support_view} claim; the request it carries is marked here, by {@link AuditContextFilter}, so that the
 * request is refused any change, its transactions run read-only ({@link AttributedTransactionManager}), and the student's own
 * gates — the forced password change, the biodata gate — stand aside for the agent who only looks.
 */
public final class SupportView {

    /** the token's claim naming the agent who views */
    public static final String CLAIM = "support_view";
    /** the request attribute holding the agent's id while a support view's request runs */
    public static final String ATTRIBUTE = "moaum.supportView";

    private SupportView() {
    }

    /** the agent viewing this request, or null when it is the student's own (or no request) */
    public static UUID agent(HttpServletRequest request) {
        Object a = request == null ? null : request.getAttribute(ATTRIBUTE);
        return a instanceof UUID u ? u : null;
    }

    /** whether the request now running is a support view's */
    public static boolean active() {
        RequestAttributes attributes = RequestContextHolder.getRequestAttributes();
        return attributes != null && attributes.getAttribute(ATTRIBUTE, RequestAttributes.SCOPE_REQUEST) != null;
    }
}
