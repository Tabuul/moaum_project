package ng.edu.moaum.portal;

import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.SpringBootTest;

/**
 * The context starts without a database in reach: the pool connects lazily,
 * and a service that cannot boot without its database cannot report that the
 * database is down.
 */
@SpringBootTest(properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
class PortalApiApplicationTests {

    @Test
    void contextLoads() {
    }
}
