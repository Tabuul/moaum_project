package ng.edu.moaum.portal.applicant;

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
 * V687 — the applicant's forced password change, on the server, as the student's (V485). An applicant signed in on a temporary
 * password from the University (the Director of ICT, the Academic Office or ICT Support reset it) reaches only what changing it needs —
 * the change and its state (/applicant/me/password), signing out, the session check and the signed-in person — and every other request
 * is refused with 403 PASSWORD_CHANGE_REQUIRED, which the portal answers by opening the change page. A JUPEB or postgraduate candidate
 * signs in as an applicant too; their accounts are not here, and they are never held.
 */
@Configuration(proxyBeanMethods = false)
class ApplicantPasswordGate implements HandlerInterceptor, WebMvcConfigurer {

    static final String CODE = "PASSWORD_CHANGE_REQUIRED";

    private static final List<String> OPEN_EXACT = List.of("/api/v1/iam/me", "/api/v1/iam/session", "/api/v1/applicant/me/password", "/api/v1/applicant/sign-out");

    private final JdbcClient jdbc;
    private final ObjectMapper json;

    ApplicantPasswordGate(JdbcClient jdbc, ObjectMapper json) {
        this.jdbc = jdbc;
        this.json = json;
    }

    @Override
    public void addInterceptors(InterceptorRegistry registry) {
        registry.addInterceptor(this).addPathPatterns("/api/**").order(-10);
    }

    @Override
    public boolean preHandle(HttpServletRequest request, HttpServletResponse response, Object handler) throws IOException {
        Optional<AuditContext> ctx = AuditContextHolder.current();
        if (ctx.isEmpty() || !"applicant".equals(ctx.get().actorOffice()) || ctx.get().actorId() == null) {
            return true;   // the applicant's alone
        }
        String path = request.getRequestURI().substring(request.getContextPath().length());
        if (OPEN_EXACT.contains(path)) {
            return true;
        }
        boolean required = jdbc.sql("SELECT must_change_password FROM admissions.applicant_account WHERE id = :a")
                .param("a", ctx.get().actorId()).query(Boolean.class).optional().orElse(false);
        if (!required) {
            return true;
        }
        response.setStatus(HttpStatus.FORBIDDEN.value());
        response.setContentType(MediaType.APPLICATION_PROBLEM_JSON_VALUE);
        Map<String, Object> problem = new LinkedHashMap<>();
        problem.put("type", "https://api.moaum.edu.ng/problems/password-change-required");
        problem.put("title", "Password change required");
        problem.put("status", HttpStatus.FORBIDDEN.value());
        problem.put("detail", "Choose your own password before you continue: you signed in with a temporary password.");
        problem.put("code", CODE);
        problem.put("instance", path);
        problem.put("remedy", Map.of("message", "Open Change password and choose your own password.", "office", "You"));
        response.getWriter().write(json.writeValueAsString(problem));
        return false;
    }
}
