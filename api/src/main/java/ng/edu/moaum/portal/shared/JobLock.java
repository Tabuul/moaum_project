package ng.edu.moaum.portal.shared;

import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;

import javax.sql.DataSource;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;

/**
 * One instance runs a scheduled job at a time, however many API tasks are up. The lock is a
 * PostgreSQL session-level advisory lock held on a connection of its own for the job's whole run,
 * so the job's own transactions commit and roll back as they always did; a second instance that
 * finds the lock taken skips its turn and tries again at its next tick. Nothing is stored and
 * nothing can be left behind: a lock dies with its connection.
 */
@Component
public class JobLock {

    private static final Logger LOG = LoggerFactory.getLogger(JobLock.class);
    private final DataSource dataSource;

    JobLock(DataSource dataSource) {
        this.dataSource = dataSource;
    }

    /** Runs {@code body} if this instance wins the lock named {@code job}; returns whether it ran. */
    public boolean runExclusively(String job, Runnable body) {
        try (Connection c = dataSource.getConnection()) {
            if (!tryLock(c, job)) {
                LOG.debug("job {}: another instance holds it; skipped", job);
                return false;
            }
            try {
                body.run();
            } finally {
                try (PreparedStatement ps = c.prepareStatement("SELECT pg_advisory_unlock(hashtext(?))")) {
                    ps.setString(1, "job:" + job);
                    ps.execute();
                }
            }
            return true;
        } catch (SQLException e) {
            LOG.warn("job {}: could not take the lock ({}); skipped this tick", job, e.getMessage());
            return false;
        }
    }

    private static boolean tryLock(Connection c, String job) throws SQLException {
        try (PreparedStatement ps = c.prepareStatement("SELECT pg_try_advisory_lock(hashtext(?))")) {
            ps.setString(1, "job:" + job);
            try (ResultSet rs = ps.executeQuery()) {
                return rs.next() && rs.getBoolean(1);
            }
        }
    }
}
