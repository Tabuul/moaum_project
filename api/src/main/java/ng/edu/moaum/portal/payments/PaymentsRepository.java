package ng.edu.moaum.portal.payments;

import java.math.BigDecimal;
import java.sql.Types;
import java.time.OffsetDateTime;
import java.util.Optional;
import java.util.UUID;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;

/** The fee references (V021) as a gateway sees them, and the one act a gateway performs: confirming one. */
@Repository
class PaymentsRepository {

    private final JdbcClient jdbc;

    PaymentsRepository(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    record Reference(UUID id, UUID applicationId, UUID accountId, String kind, String reference, BigDecimal amount,
                     OffsetDateTime expiresAt, OffsetDateTime confirmedAt, String email, String applicationNo) {
    }

    Optional<Reference> byReference(String reference) {
        return jdbc.sql("""
                SELECT f.id, f.application_id, a.account_id, f.kind, f.reference, f.amount, f.expires_at, f.confirmed_at, acc.email, a.application_no
                  FROM admissions.fee_reference f
                  JOIN admissions.application a ON a.id = f.application_id
                  JOIN admissions.applicant_account acc ON acc.id = a.account_id
                 WHERE f.reference = upper(btrim(:r))
                """).param("r", reference).query(Reference.class).optional();
    }

    String confirm(String reference, String channel, String note) {
        return jdbc.sql("SELECT admissions.confirm_fee(:r, :c, :n)")
                .param("r", reference).param("c", channel).param("n", note, Types.VARCHAR).query(String.class).single();
    }
}
