package ng.edu.moaum.portal.studentportal;

import java.io.IOException;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;

import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;

import ng.edu.moaum.portal.shared.AuditContext;
import ng.edu.moaum.portal.shared.AuditContextHolder;

import org.springframework.context.annotation.Configuration;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.web.servlet.HandlerInterceptor;
import org.springframework.web.servlet.config.annotation.InterceptorRegistry;
import org.springframework.web.servlet.config.annotation.WebMvcConfigurer;

import tools.jackson.databind.ObjectMapper;

/**
 * V485 — the forced password change, enforced on the server. A student whose account must change its password (a reset to the
 * default credential at the ICT Support Desk, a temporary password, the Registry's first password, the first sign-in on the
 * number) reaches only what changing it needs — the change itself and the account's state (/student-auth), signing out, the
 * session check and the signed-in person — and every other request, whatever the screen, the address typed, another tab, a
 * refresh or a direct call, is refused with 403 PASSWORD_CHANGE_REQUIRED, which the portal answers by opening the change page.
 * It runs before the biodata gate (V423): the password comes first.
 *
 * <p>Every other office is never read here. Each student response carries {@code X-Password-Change} (REQUIRED or NONE), so the
 * portal's own navigation check (/iam/session) sends the student to the change page without asking twice.
 */
@Configuration(proxyBeanMethods = false)
class PasswordChangeGate implements HandlerInterceptor, WebMvcConfigurer {

    static final String HEADER = "X-Password-Change";
    static final String CODE = "PASSWORD_CHANGE_REQUIRED";

    /** open while the change is required: exactly these paths … */
    private static final List<String> OPEN_EXACT = List.of("/api/v1/iam/me", "/api/v1/iam/session");
    /** … and everything under these (the change, the account's state, signing out) */
    private static final List<String> OPEN_UNDER = List.of("/api/v1/student-auth");

    private final JdbcClient jdbc;
    private final ObjectMapper json;

    PasswordChangeGate(JdbcClient jdbc, ObjectMapper json) {
        this.jdbc = jdbc;
        this.json = json;
    }

    @Override
    public void addInterceptors(InterceptorRegistry registry) {
        registry.addInterceptor(this).addPathPatterns("/api/**").order(-10);
    }

    static boolean open(String path) {
        if (OPEN_EXACT.contains(path)) {
            return true;
        }
        for (String p : OPEN_UNDER) {
            if (path.equals(p) || path.startsWith(p + "/")) {
                return true;
            }
        }
        return false;
    }

    @Override
    public boolean preHandle(HttpServletRequest request, HttpServletResponse response, Object handler) throws IOException {
        Optional<AuditContext> ctx = AuditContextHolder.current();
        if (ctx.isEmpty() || !"student".equals(ctx.get().actorOffice())) {
            return true;   // the student's alone
        }
        if (ng.edu.moaum.portal.platform.SupportView.agent(request) != null) {
            return true;   // V521: ICT Support viewing the portal read-only changes no password
        }
        boolean required = jdbc.sql("SELECT must_change FROM iam.student_account WHERE student_id = :s")
                .param("s", ctx.get().actorId()).query(Boolean.class).optional().orElse(false);
        response.setHeader(HEADER, required ? "REQUIRED" : "NONE");
        if (!required) {
            return true;
        }
        String path = request.getRequestURI().substring(request.getContextPath().length());
        if (open(path)) {
            return true;
        }
        response.setStatus(HttpStatus.FORBIDDEN.value());
        response.setContentType(MediaType.APPLICATION_PROBLEM_JSON_VALUE);
        Map<String, Object> problem = new LinkedHashMap<>();
        problem.put("type", "https://api.moaum.edu.ng/problems/password-change-required");
        problem.put("title", "Password change required");
        problem.put("status", HttpStatus.FORBIDDEN.value());
        problem.put("detail", "You must change your password before continuing.");
        problem.put("code", CODE);
        problem.put("instance", path);
        problem.put("remedy", Map.of("message", "Open Change password and choose your own password.", "office", "You"));
        response.getWriter().write(json.writeValueAsString(problem));
        return false;
    }
}
