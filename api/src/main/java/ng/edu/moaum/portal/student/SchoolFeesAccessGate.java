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
import ng.edu.moaum.portal.shared.DomainRuleViolation;
import ng.edu.moaum.portal.studentportal.StudentAuthService;

import org.springframework.context.annotation.Configuration;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.web.servlet.HandlerInterceptor;
import org.springframework.web.servlet.config.annotation.InterceptorRegistry;
import org.springframework.web.servlet.config.annotation.WebMvcConfigurer;

import tools.jackson.databind.ObjectMapper;

/**
 * V724 — the student portal's fee gate, enforced on the server for every request a student makes, whatever the screen, the
 * address typed, a token kept from before the gate or a modified page. A fresh UTME or Direct Entry admit of a gated entry
 * session (ADMITTED, no matriculation number) is held out of the portal while an acceptance fee balance is owed (the fee
 * revised after part of it was paid), and until the session's school fees are stated by the Bursary and paid as the gate
 * requires — the first semester's, or the session's in full — unless the Bursary let them through by an exception. The state is finance.portal_access_state's, read on every request and never cached: a payment verified a
 * moment ago opens the portal on the next request, and a matriculated student, an earlier cohort, a postgraduate or a CCE
 * student read OPEN from it and are never held. The door itself (StudentAuthService) refuses a held student a token in the
 * same words; this gate stands behind it for a session opened before the gate, or a token carried from the applicant portal.
 *
 * <p>While held, only what the applicant dashboard's hand-off and the payment need is open — the student's own record, the
 * notices, the admission documents, the fee and payment paths the biodata gate already lets through (the balance is paid from
 * the applicant dashboard, through the same gateway), the account and signing out, the session check and the manual — and
 * anything else is refused with 403 STUDENT_PORTAL_HELD_FEES — whatever holds the student, so the portal answers every hold
 * alike; {@code state} and the detail say which — and the portal answers it by sending the student back to the applicant
 * dashboard. Every student response carries {@code X-Portal-Access} (the state), so the portal's own navigation
 * check (/iam/session) can send a held student on without asking twice.
 *
 * <p>Every other office is never read here: the gate is the student's alone. It runs after the forced password change (V485)
 * and before the biodata gate (V423): a student the fees hold is not asked for biodata first.
 */
@Configuration(proxyBeanMethods = false)
class SchoolFeesAccessGate implements HandlerInterceptor, WebMvcConfigurer {

    static final String HEADER = "X-Portal-Access";
    static final String CODE = "STUDENT_PORTAL_HELD_FEES";
    static final String HELD_UNPAID = "HELD_FEES_UNPAID";
    static final String HELD_NOT_AVAILABLE = "HELD_FEES_NOT_AVAILABLE";
    /** V724: the acceptance fee, revised after part of it was paid, still owed — held before the school fees are read */
    static final String HELD_ACCEPTANCE_BALANCE = "HELD_ACCEPTANCE_BALANCE";

    /** open while the gate holds the student, beside everything the biodata gate lets through ({@link BiodataGateInterceptor#open}:
     *  the student's own record — GET /api/v1/me — the contact and passport, the notices, the fee and payment paths, signing out):
     *  exactly these … */
    private static final List<String> OPEN_EXACT = List.of("/api/v1/me");
    /** … and everything under these — the admission documents and the account's password, the student door, the session and the
     *  signed-in person, the manual */
    private static final List<String> OPEN_UNDER = List.of(
            "/api/v1/me/notices", "/api/v1/me/notifications", "/api/v1/me/admission-documents", "/api/v1/me/password",
            "/api/v1/student-auth", "/api/v1/iam", "/api/v1/manual",
            // V733: an MBBS student states the session they stand in — the fees the gate reads are that session's
            "/api/v1/me/study-session");

    private final JdbcClient jdbc;
    private final ObjectMapper json;

    SchoolFeesAccessGate(JdbcClient jdbc, ObjectMapper json) {
        this.jdbc = jdbc;
        this.json = json;
    }

    @Override
    public void addInterceptors(InterceptorRegistry registry) {
        // after the forced password change (PasswordChangeGate, -10) and before the biodata gate (BiodataGateInterceptor, the default 0)
        registry.addInterceptor(this).addPathPatterns("/api/**").order(-5);
    }

    static boolean open(String path) {
        if (BiodataGateInterceptor.open(path) || OPEN_EXACT.contains(path)) {
            return true;
        }
        for (String p : OPEN_UNDER) {
            if (path.equals(p) || path.startsWith(p + "/")) {
                return true;
            }
        }
        return false;
    }

    /** every held state of finance.portal_access_state: the acceptance balance (V724's brief: "acceptance fee partially paid — no
     *  access"), the school fees not yet stated, the school fees not paid as the gate asks */
    static boolean held(String state) {
        return HELD_ACCEPTANCE_BALANCE.equals(state) || HELD_UNPAID.equals(state) || HELD_NOT_AVAILABLE.equals(state);
    }

    @Override
    public boolean preHandle(HttpServletRequest request, HttpServletResponse response, Object handler) throws IOException {
        Optional<AuditContext> ctx = AuditContextHolder.current();
        if (ctx.isEmpty() || !"student".equals(ctx.get().actorOffice())) {
            return true;   // the gate is the student's alone
        }
        if (ng.edu.moaum.portal.platform.SupportView.agent(request) != null) {
            return true;   // V521: ICT Support viewing the portal read-only pays no fees
        }
        UUID student = ctx.get().actorId();
        // one read, now — the state and the entry session the refusal names; a record not on the register is nobody's to hold
        Map<String, Object> row = jdbc.sql("SELECT finance.portal_access_state(s.id) AS state, s.entry_session FROM people.student s WHERE s.id = :s")
                .param("s", student).query().listOfRows().stream().findFirst().orElse(null);
        String state = row == null || row.get("state") == null ? "OPEN" : String.valueOf(row.get("state"));
        response.setHeader(HEADER, state);
        if (!held(state)) {
            return true;
        }
        String path = request.getRequestURI().substring(request.getContextPath().length());
        if (open(path)) {
            return true;
        }
        DomainRuleViolation refusal = StudentAuthService.heldAtTheGate(state, row.get("entry_session") == null ? null : String.valueOf(row.get("entry_session")));
        response.setStatus(HttpStatus.FORBIDDEN.value());
        response.setContentType(MediaType.APPLICATION_PROBLEM_JSON_VALUE);
        Map<String, Object> problem = new LinkedHashMap<>();
        problem.put("type", "https://api.moaum.edu.ng/problems/student-portal-held-fees");
        problem.put("title", "Student portal not yet open");
        problem.put("status", HttpStatus.FORBIDDEN.value());
        problem.put("detail", refusal.getMessage());
        problem.put("code", CODE);
        problem.put("state", state);
        problem.put("instance", path);
        problem.put("remedy", Map.of("message", refusal.remedy().message(), "office", refusal.remedy().office()));
        response.getWriter().write(json.writeValueAsString(problem));
        return false;
    }
}
