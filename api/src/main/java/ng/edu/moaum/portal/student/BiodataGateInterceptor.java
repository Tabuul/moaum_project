package ng.edu.moaum.portal.student;

import java.io.IOException;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;

import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;

import ng.edu.moaum.portal.shared.AuditContext;
import ng.edu.moaum.portal.shared.AuditContextHolder;

import org.springframework.context.annotation.Configuration;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.web.servlet.HandlerInterceptor;
import org.springframework.web.servlet.config.annotation.InterceptorRegistry;
import org.springframework.web.servlet.config.annotation.WebMvcConfigurer;

import tools.jackson.databind.ObjectMapper;

/**
 * V423 — the biodata gate, enforced on the server for every request a student makes, whatever the screen, the
 * address typed, an old endpoint or a modified page. A request made in the student office is let through when the gate
 * is OFF, when a live exception covers the student, or when the required biodata is complete. Otherwise only what
 * completing the biodata needs is open — the student's own record and biodata, the passport photograph, the contact,
 * the notices, a request for help, the lists the form chooses from, signing out — and anything else is refused with
 * 403 BIODATA_COMPLETION_REQUIRED, which the portal answers by opening the biodata page.
 *
 * <p>Every other office — the ICT Director, the Registry, the Bursary, a lecturer, a CPO, an administrator — is never
 * read here: the gate is the student's alone. Each student response carries {@code X-Biodata-Gate} (the state), so the
 * portal's own navigation check (/iam/session) can send a gated student to the biodata page without asking twice.
 */
@Configuration(proxyBeanMethods = false)
class BiodataGateInterceptor implements HandlerInterceptor, WebMvcConfigurer {

    static final String HEADER = "X-Biodata-Gate";
    static final String CODE = "BIODATA_COMPLETION_REQUIRED";

    /** open while the gate holds the student: exactly these paths … */
    private static final List<String> OPEN_EXACT = List.of(
            "/api/v1/me", "/api/v1/me/passport", "/api/v1/me/contact", "/api/v1/me/biodata-status",
            "/api/v1/iam/me", "/api/v1/iam/session", "/api/v1/iam/me/scope",
            "/api/v1/ref/states", "/api/v1/ref/countries");
    /** … and everything under these */
    private static final List<String> OPEN_UNDER = List.of(
            "/api/v1/me/biodata", "/api/v1/me/notices", "/api/v1/me/notifications", "/api/v1/me/requests", "/api/v1/student-auth", "/api/v1/manual");

    private final BiodataCompliance compliance;
    private final ObjectMapper json;

    BiodataGateInterceptor(BiodataCompliance compliance, ObjectMapper json) {
        this.compliance = compliance;
        this.json = json;
    }

    @Override
    public void addInterceptors(InterceptorRegistry registry) {
        registry.addInterceptor(this).addPathPatterns("/api/**");
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
            return true;   // the gate is the student's alone
        }
        UUID student = ctx.get().actorId();
        String state = compliance.gateState(student);
        response.setHeader(HEADER, state);
        if (!BiodataCompliance.REQUIRED.equals(state)) {
            return true;
        }
        String path = request.getRequestURI().substring(request.getContextPath().length());
        if (open(path)) {
            return true;
        }
        response.setStatus(HttpStatus.FORBIDDEN.value());
        response.setContentType(MediaType.APPLICATION_PROBLEM_JSON_VALUE);
        Map<String, Object> problem = new LinkedHashMap<>();
        problem.put("type", "https://api.moaum.edu.ng/problems/biodata-completion-required");
        problem.put("title", "Biodata completion required");
        problem.put("status", HttpStatus.FORBIDDEN.value());
        problem.put("detail", "Please complete your required biodata before continuing to the Student Portal.");
        problem.put("code", CODE);
        problem.put("instance", path);
        problem.put("remedy", Map.of("message", "Open Biodata and complete the items marked required.", "office", "You"));
        response.getWriter().write(json.writeValueAsString(problem));
        return false;
    }
}
