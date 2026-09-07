package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.util.Map;
import java.util.UUID;

import ng.edu.moaum.portal.shared.AuditContext;
import ng.edu.moaum.portal.shared.AuditContextHolder;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.dao.DataAccessException;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;

/**
 * The property the whole design rests on, checked from the application side:
 * a transaction without an audit context cannot write to an attached table,
 * and one with a context leaves an audit row naming the actor.
 *
 * <p>Needs a database the migrations have been applied to: set DATABASE_URL.
 */
@SpringBootTest(properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
class AuditSpineIT {

    @Autowired
    JdbcClient jdbc;

    @Autowired
    PlatformTransactionManager transactions;

    @Test
    void anUnattributedWriteIsRefusedByTheDatabase() {
        TransactionTemplate tx = new TransactionTemplate(transactions);
        AuditContextHolder.clear();
        assertThatThrownBy(() -> tx.executeWithoutResult(status -> insertPerson(UUID.randomUUID())))
                .isInstanceOf(DataAccessException.class)
                .hasMessageContaining("unattributed change to iam.person");
    }

    @Test
    void anAttributedWriteIsRecordedAgainstTheActor() {
        TransactionTemplate tx = new TransactionTemplate(transactions);
        UUID actor = UUID.randomUUID();
        UUID person = UUID.randomUUID();
        AuditContext context = new AuditContext(actor, "registrar", "AuditSpineIT", null, null);

        AuditContextHolder.with(context, () -> tx.execute(status -> {
            insertPerson(person);
            return null;
        }));

        Map<String, Object> entry = jdbc.sql("""
                SELECT actor_id, actor_office, action, subject_type, reason
                  FROM audit.entries WHERE subject_id = :id ORDER BY occurred_at DESC LIMIT 1
                """).param("id", person).query().singleRow();
        assertThat(entry.get("actor_id")).isEqualTo(actor);
        assertThat(entry.get("actor_office")).isEqualTo("registrar");
        assertThat(entry.get("reason")).isEqualTo("AuditSpineIT");
        assertThat(String.valueOf(entry.get("subject_type"))).contains("person");
    }

    @Test
    void theContextIsLocalToTheTransaction() {
        // after an attributed transaction, the pooled connection must carry nothing over
        TransactionTemplate tx = new TransactionTemplate(transactions);
        AuditContextHolder.with(new AuditContext(UUID.randomUUID(), "registrar", null, null, null),
                () -> tx.execute(status -> insertPerson(UUID.randomUUID())));
        AuditContextHolder.clear();
        String leaked = tx.execute(status ->
                jdbc.sql("SELECT coalesce(current_setting('moaum.actor_id', true), '')").query(String.class).single());
        assertThat(leaked).isEmpty();
    }

    private int insertPerson(UUID id) {
        return jdbc.sql("INSERT INTO iam.person (id, surname, given_names) VALUES (:id, 'Test', 'Person')")
                .param("id", id).update();
    }
}
