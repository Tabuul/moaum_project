package ng.edu.moaum.portal.shared;

import java.util.Optional;

/**
 * The audit context of the current thread of work.
 *
 * <p>Set by the platform once the request's principal is known, read by the
 * transaction manager when a transaction begins, and cleared when the request
 * ends. Batch jobs set it explicitly with a system actor.
 */
public final class AuditContextHolder {

    private static final ThreadLocal<AuditContext> CURRENT = new ThreadLocal<>();

    private AuditContextHolder() {
    }

    public static Optional<AuditContext> current() {
        return Optional.ofNullable(CURRENT.get());
    }

    public static AuditContext required() {
        return current().orElseThrow(() -> new IllegalStateException(
                "no audit context on this thread — every state change is attributable (P5, D6)"));
    }

    public static void set(AuditContext context) {
        CURRENT.set(context);
    }

    public static void clear() {
        CURRENT.remove();
    }

    /** Run {@code work} with {@code context} in place, restoring whatever was there before. */
    public static <T> T with(AuditContext context, java.util.function.Supplier<T> work) {
        AuditContext previous = CURRENT.get();
        CURRENT.set(context);
        try {
            return work.get();
        } finally {
            if (previous == null) {
                CURRENT.remove();
            } else {
                CURRENT.set(previous);
            }
        }
    }
}
