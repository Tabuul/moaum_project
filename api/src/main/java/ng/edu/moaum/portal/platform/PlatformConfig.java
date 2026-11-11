package ng.edu.moaum.portal.platform;

import javax.sql.DataSource;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.annotation.EnableTransactionManagement;

@Configuration
@EnableTransactionManagement
class PlatformConfig {

    /** Replaces Boot's default so that every transaction carries the audit context. */
    @Bean
    PlatformTransactionManager transactionManager(DataSource dataSource,
                                                  @org.springframework.beans.factory.annotation.Value("${moaum.db.request-read-timeout-ms:90000}") long readTimeoutMs) {
        return new AttributedTransactionManager(dataSource, readTimeoutMs);
    }

    /**
     * 11 Nov 2026: the portal's JdbcTemplate (behind the JdbcClient every module injects) turns a statement the database stops
     * (SQLSTATE 57014) into a StoppedStatement noted on the failing statement's own thread and transaction, so ProblemHandler names
     * the portal's read limit only where it was on that statement.
     */
    @Bean
    static org.springframework.beans.factory.config.BeanPostProcessor stoppedStatementTranslator(
            @org.springframework.beans.factory.annotation.Value("${moaum.db.request-read-timeout-ms:90000}") long readTimeoutMs) {
        return new org.springframework.beans.factory.config.BeanPostProcessor() {
            @Override
            public Object postProcessAfterInitialization(Object bean, String name) {
                if (bean instanceof org.springframework.jdbc.core.JdbcTemplate template
                        && !(template.getExceptionTranslator() instanceof StoppedStatement.Translator)) {
                    template.setExceptionTranslator(new StoppedStatement.Translator(template.getExceptionTranslator(), Math.max(0, readTimeoutMs), null));
                }
                return bean;
            }
        };
    }
}
