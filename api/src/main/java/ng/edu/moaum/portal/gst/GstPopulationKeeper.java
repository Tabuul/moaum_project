package ng.edu.moaum.portal.gst;

import java.time.Duration;
import java.time.Instant;
import java.time.OffsetDateTime;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Component;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.TransactionDefinition;
import org.springframework.transaction.support.TransactionTemplate;

/**
 * V577: the GST/EPS population a screen reads is the kept one (finance.gst_population_kept): worked out now when none is kept, a
 * change to the GST fee, its setting or a payment review has put it out of date, or the reader asks (Refresh); worked out behind
 * the screens, while the kept one is served, once it is older than five minutes. Each working-out is its own transaction, so a
 * screen's read-only transaction never writes.
 */
@Component
public class GstPopulationKeeper {

    private static final Logger LOG = LoggerFactory.getLogger(GstPopulationKeeper.class);

    private final JdbcClient jdbc;
    private final TransactionTemplate tx;
    private final Duration fresh;
    private final Set<String> behind = ConcurrentHashMap.newKeySet();
    private final ExecutorService pool = Executors.newSingleThreadExecutor(r -> {
        Thread t = new Thread(r, "gst-population-keeper");
        t.setDaemon(true);
        return t;
    });

    GstPopulationKeeper(JdbcClient jdbc, PlatformTransactionManager transactions, @Value("${moaum.gst.population-fresh-seconds:300}") long freshSeconds) {
        this.jdbc = jdbc;
        this.tx = new TransactionTemplate(transactions);
        this.tx.setPropagationBehavior(TransactionDefinition.PROPAGATION_REQUIRES_NEW);
        this.fresh = Duration.ofSeconds(Math.max(0, freshSeconds));
    }

    /** the kept population of the session (and semester) ready to read; the time it was worked out */
    public Instant ensure(String session, Integer semester, boolean refresh) {
        Map<String, Object> st = state(session, semester);
        if (refresh || st == null || Boolean.TRUE.equals(st.get("invalid"))) {
            keepNow(session, semester);
            st = state(session, semester);
            return st == null ? Instant.now() : at(st);
        }
        if (Duration.between(at(st), Instant.now()).compareTo(fresh) > 0) {
            keepBehind(session, semester);
        }
        return at(st);
    }

    private Map<String, Object> state(String session, Integer semester) {
        return jdbc.sql("SELECT kept_at, invalid FROM finance.gst_population_state WHERE session = :s AND semester = :m")
                .param("s", session).param("m", semester == null ? 0 : semester).query().listOfRows().stream().findFirst().orElse(null);
    }

    private static Instant at(Map<String, Object> st) {
        Object v = st.get("kept_at");
        if (v instanceof java.sql.Timestamp t) return t.toInstant();
        if (v instanceof OffsetDateTime o) return o.toInstant();
        return Instant.now();
    }

    private void keepNow(String session, Integer semester) {
        tx.execute(s -> jdbc.sql("SELECT finance.keep_gst_population(:s, :m, true)").param("s", session).param("m", semester, java.sql.Types.INTEGER)
                .query(Integer.class).single());
    }

    private void keepBehind(String session, Integer semester) {
        String key = session + ":" + (semester == null ? 0 : semester);
        if (!behind.add(key)) return;
        try {
            pool.execute(() -> {
                try {
                    tx.execute(s -> jdbc.sql("SELECT finance.keep_gst_population(:s, :m, false)").param("s", session).param("m", semester, java.sql.Types.INTEGER)
                            .query(Integer.class).single());
                } catch (RuntimeException e) {
                    LOG.warn("the GST/EPS population of {} was not worked out again: {}", key, e.getMessage());
                } finally {
                    behind.remove(key);
                }
            });
        } catch (RuntimeException e) {
            behind.remove(key);
        }
    }
}
