package ng.edu.moaum.portal.platform;

import java.util.UUID;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;

import ng.edu.moaum.portal.shared.AuditContextHolder;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.context.annotation.Configuration;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.TransactionDefinition;
import org.springframework.transaction.support.TransactionTemplate;
import org.springframework.web.servlet.HandlerInterceptor;
import org.springframework.web.servlet.config.annotation.InterceptorRegistry;
import org.springframework.web.servlet.config.annotation.WebMvcConfigurer;

/**
 * V530: an office opening a student's record is recorded — the student record (Student 360) and ICT Support's record of the
 * student, once the record has been answered. The database records it for the person and office of the request
 * (people.log_record_view: once for each person, office and record within ten minutes; never the student's own reading, never ICT
 * Support's read-only view of the student's portal, which helpdesk.portal_view records). The read is recorded in a transaction of
 * its own, after the record's own read-only one, and a failure to record it never fails the record.
 */
@Configuration(proxyBeanMethods = false)
class RecordViewLog implements HandlerInterceptor, WebMvcConfigurer {

    private static final Logger LOG = LoggerFactory.getLogger(RecordViewLog.class);
    private static final Pattern STUDENT_RECORD = Pattern.compile("^/api/v1/student/students/([0-9a-fA-F-]{36})$");
    private static final Pattern SUPPORT_RECORD = Pattern.compile("^/api/v1/helpdesk/support/students/([0-9a-fA-F-]{36})$");

    private final JdbcClient jdbc;
    private final TransactionTemplate tx;

    RecordViewLog(JdbcClient jdbc, PlatformTransactionManager transactions) {
        this.jdbc = jdbc;
        this.tx = new TransactionTemplate(transactions);
        this.tx.setPropagationBehavior(TransactionDefinition.PROPAGATION_REQUIRES_NEW);
    }

    @Override
    public void addInterceptors(InterceptorRegistry registry) {
        registry.addInterceptor(this).addPathPatterns("/api/v1/student/students/*", "/api/v1/helpdesk/support/students/*");
    }

    @Override
    public void afterCompletion(HttpServletRequest request, HttpServletResponse response, Object handler, Exception ex) {
        if (!"GET".equals(request.getMethod()) || response.getStatus() != 200 || ex != null
                || request.getAttribute(SupportView.ATTRIBUTE) != null || AuditContextHolder.current().isEmpty()) {
            return;
        }
        String path = request.getRequestURI();
        String record = null;
        Matcher m = STUDENT_RECORD.matcher(path);
        if (m.matches()) {
            record = "STUDENT_RECORD";
        } else {
            m = SUPPORT_RECORD.matcher(path);
            if (m.matches()) {
                record = "SUPPORT_RECORD";
            }
        }
        if (record == null) {
            return;
        }
        try {
            UUID student = UUID.fromString(m.group(1));
            String r = record;
            tx.execute(st -> jdbc.sql("SELECT people.log_record_view(:s, :r)").param("s", student).param("r", r).query(Boolean.class).single());
        } catch (RuntimeException e) {
            LOG.warn("record view not recorded for {}: {}", path, e.getMessage());
        }
    }
}
