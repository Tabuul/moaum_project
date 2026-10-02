package ng.edu.moaum.portal.shared;

import org.springframework.boot.autoconfigure.condition.ConditionalOnMissingBean;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

/** No object store: files stay in the database. The default, and what Railway runs. */
@Configuration
class NoFileStore {

    @Bean
    @ConditionalOnMissingBean(FileStore.class)
    FileStore databaseOnly() {
        return new FileStore() {
            @Override
            public boolean enabled() {
                return false;
            }

            @Override
            public void put(String key, byte[] bytes, String contentType) {
                throw new IllegalStateException("no object store is configured");
            }

            @Override
            public byte[] get(String key) {
                throw new IllegalStateException("no object store is configured");
            }

            @Override
            public void delete(String key) {
                throw new IllegalStateException("no object store is configured");
            }
        };
    }
}
