/**
 * The audit trail viewer (DGV/ADR-018): a read over audit.entries, the
 * hash-chained store every state change is written to. The application holds
 * insert and select on that store and nothing else, so the trail cannot be
 * edited through the portal; this module only reads it, for the offices that
 * oversee the platform and Internal Audit.
 */
@org.springframework.modulith.ApplicationModule(displayName = "Audit trail")
package ng.edu.moaum.portal.auditlog;
