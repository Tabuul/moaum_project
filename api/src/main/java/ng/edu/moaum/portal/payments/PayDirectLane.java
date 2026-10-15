package ng.edu.moaum.portal.payments;

import java.sql.SQLException;
import java.util.Properties;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;

import javax.sql.DataSource;

import com.zaxxer.hikari.HikariConfig;
import com.zaxxer.hikari.HikariDataSource;

import ng.edu.moaum.portal.platform.AttributedTransactionManager;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.DisposableBean;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Component;
import org.springframework.transaction.support.TransactionTemplate;

/**
 * V474: the PAYDirect door's own way to the database. Interswitch waits a fixed time for its answer (about fifty seconds on
 * 15 Oct 2026) and the portal's ten connections may all be busy with other work; a step of a notification waiting for one
 * waits up to thirty seconds, and the steps add up past Interswitch's patience. The door (its call counter, the credentials,
 * Quickteller's question about a reference, the record of each notified payment) uses this small pool of its own, whose
 * statements are cut short rather than left waiting; the settling of a payment runs on the settlers here, on the portal's
 * own pool, and the answer waits for it only up to a budget.
 *
 * <p>Not a {@code DataSource} bean — Spring Boot's own pool stays the portal's one {@code DataSource}; this one is made from
 * its settings and closed with the context. Where the portal's pool is not Hikari (it always is outside a unit test), the
 * door shares it.
 */
@Component
class PayDirectLane implements DisposableBean {

    private static final Logger LOG = LoggerFactory.getLogger(PayDirectLane.class);

    private final HikariDataSource own;
    private final JdbcClient jdbc;
    private final TransactionTemplate tx;
    private final ExecutorService settlers;
    private final long budgetMs;

    PayDirectLane(DataSource portal,
                  @Value("${moaum.paydirect.pool-size:3}") int poolSize,
                  @Value("${moaum.paydirect.pool-min-idle:1}") int minIdle,
                  @Value("${moaum.paydirect.connection-timeout-ms:5000}") long connectionTimeoutMs,
                  @Value("${moaum.paydirect.statement-timeout-ms:8000}") long statementTimeoutMs,
                  @Value("${moaum.paydirect.settlers:4}") int settlers,
                  @Value("${moaum.paydirect.settle-budget-ms:10000}") long budgetMs) {
        HikariDataSource pool = null;
        HikariDataSource hikari = hikari(portal);
        if (hikari != null) {
            HikariConfig c = new HikariConfig();
            c.setPoolName("paydirect");
            c.setJdbcUrl(hikari.getJdbcUrl());
            c.setUsername(hikari.getUsername());
            c.setPassword(hikari.getPassword());
            if (hikari.getDriverClassName() != null) {
                c.setDriverClassName(hikari.getDriverClassName());
            }
            Properties props = new Properties();
            props.putAll(hikari.getDataSourceProperties());
            // a statement of the door's never waits long, for a lock or for itself: it fails, and the door answers
            props.setProperty("options", "-c statement_timeout=" + Math.max(1000, statementTimeoutMs) + " -c lock_timeout=" + Math.max(500, statementTimeoutMs / 2));
            c.setDataSourceProperties(props);
            c.setMaximumPoolSize(Math.max(1, poolSize));
            c.setMinimumIdle(Math.max(0, Math.min(minIdle, poolSize)));
            c.setConnectionTimeout(Math.max(250, connectionTimeoutMs));
            c.setInitializationFailTimeout(-1);   // the API starts whatever the database says at that moment, as the portal's pool does
            pool = new HikariDataSource(c);
        }
        this.own = pool;
        DataSource ds = pool != null ? pool : portal;
        this.jdbc = JdbcClient.create(ds);
        this.tx = new TransactionTemplate(new AttributedTransactionManager(ds));
        AtomicInteger n = new AtomicInteger();
        this.settlers = Executors.newFixedThreadPool(Math.max(1, settlers), r -> {
            Thread t = new Thread(r, "paydirect-settle-" + n.incrementAndGet());
            t.setDaemon(true);
            return t;
        });
        this.budgetMs = Math.max(0, budgetMs);
    }

    private static HikariDataSource hikari(DataSource ds) {
        if (ds instanceof HikariDataSource h) {
            return h;
        }
        try {
            return ds.isWrapperFor(HikariDataSource.class) ? ds.unwrap(HikariDataSource.class) : null;
        } catch (SQLException notWrapped) {
            return null;
        }
    }

    JdbcClient jdbc() {
        return jdbc;
    }

    TransactionTemplate tx() {
        return tx;
    }

    ExecutorService settlers() {
        return settlers;
    }

    /** how long Interswitch's answer waits for a payment to settle before it is answered as received */
    long budgetMs() {
        return budgetMs;
    }

    @Override
    public void destroy() {
        settlers.shutdown();
        try {
            if (!settlers.awaitTermination(10, TimeUnit.SECONDS)) {
                LOG.warn("payments: PAYDirect settlers still running at shutdown; the sweeper settles what they leave");
                settlers.shutdownNow();
            }
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        }
        if (own != null) {
            own.close();
        }
    }
}
