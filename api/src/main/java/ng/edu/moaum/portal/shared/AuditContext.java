package ng.edu.moaum.portal.shared;

import java.util.Objects;
import java.util.UUID;

/**
 * Who is acting, in which office, why, and under which correlation id.
 *
 * <p>This is the half of the audit mechanism the application owns (V002): it
 * is placed on every transaction as {@code SET LOCAL moaum.*}, and the audit
 * trigger reads it back and REFUSES any write to an attached table when it is
 * absent. A service that forgets the context cannot write at all.
 *
 * @param actorId       the acting person (Keycloak {@code sub}, a UUID)
 * @param actorOffice   one of the office codes in {@code ref.office}
 * @param reason        free text, optional — the "why" a later reader wants
 * @param correlationId the request's correlation id, generated when absent
 * @param sourceIp      the client address, optional
 */
public record AuditContext(UUID actorId, String actorOffice, String reason, UUID correlationId, String sourceIp) {

    public AuditContext {
        Objects.requireNonNull(actorId, "actorId");
        if (actorOffice == null || actorOffice.isBlank()) {
            throw new IllegalArgumentException("actorOffice is required: the acting office is part of every attributed write");
        }
        if (correlationId == null) {
            correlationId = UUID.randomUUID();
        }
    }

    public AuditContext withReason(String newReason) {
        return new AuditContext(actorId, actorOffice, newReason, correlationId, sourceIp);
    }
}
