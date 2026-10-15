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
}
