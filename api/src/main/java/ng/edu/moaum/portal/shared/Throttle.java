package ng.edu.moaum.portal.shared;

import java.time.Duration;
import java.util.ArrayDeque;
import java.util.EnumMap;
import java.util.Locale;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

import org.springframework.core.env.Environment;
import org.springframework.stereotype.Component;

/**
 * V359: how many times one connection may knock on a public door in fifteen minutes. Each account already locks after
 * five wrong passwords; this is the other half — one connection trying many accounts, asking for reset links, looking up
 * JAMB numbers or checking verification codes one after another.
 *
 * <p>A sign-in door counts a wrong password (or a locked account) on an account that exists — not an unknown name, which
 * the portal's own sign-in page produces whenever it tries the next door for a person (an applicant's email is tried at
 * the staff door first). A reset link is counted every time it is asked for, a reset by a link that fails, a JAMB
 * look-up and an applicant registration every time, a verification that does not match. Past the door's number the
 * connection is refused with 429 until its oldest knock is fifteen minutes old. A request from the machine itself
 * (development, the test suite) is not counted.
 *
 * <p>Each API instance counts on its own, in memory: a restart forgets, and two instances allow twice. The numbers are
 * the defaults below, and each may be set in the environment ({@code moaum.throttle.staff-sign-in=50}, or
 * {@code MOAUM_THROTTLE_STAFF_SIGN_IN=50}).
 */
@Component
public class Throttle {

    public static final Duration WINDOW = Duration.ofMinutes(15);

    public enum Door {
        STAFF_SIGN_IN(30, "AUTH_THROTTLED", "Too many failed sign-ins from this connection", "Wait, or reset your password from the sign-in page."),
        STUDENT_SIGN_IN(60, "AUTH_THROTTLED", "Too many failed sign-ins from this connection", "Wait, or reset your password from the sign-in page."),
        APPLICANT_SIGN_IN(30, "AUTH_THROTTLED", "Too many failed sign-ins from this connection", "Wait, or reset your password from the sign-in page."),
        PG_SIGN_IN(20, "AUTH_THROTTLED", "Too many failed sign-ins from this connection", "Wait, or reset your password with the email you applied with."),
        JUPEB_SIGN_IN(20, "AUTH_THROTTLED", "Too many failed sign-ins from this connection", "Wait, or reset your password with the email you applied with."),
        RESET_LINK(20, "AUTH_THROTTLED", "Too many password-reset requests from this connection", "Wait; a link already sent is good for an hour."),
        RESET(20, "AUTH_THROTTLED", "Too many reset links that did not work from this connection", "Wait, then ask for a new link and use it within the hour."),
        APPLICANT_LOOKUP(60, "APP_THROTTLED", "Too many JAMB look-ups from this connection", "Each applicant looks up their own JAMB number; a list is not looked up here."),
        APPLICANT_REGISTER(30, "APP_THROTTLED", "Too many registrations from this connection", "Wait; each applicant registers once, with their own JAMB number."),
        VERIFY(40, "VERIFY_THROTTLED", "Too many checks that did not match from this connection", "The verification page checks documents one at a time, by the QR on each.");

        final int limit;
        final String code;
        final String said;
        final String remedy;

        Door(int limit, String code, String said, String remedy) {
            this.limit = limit;
            this.code = code;
            this.said = said;
            this.remedy = remedy;
        }

        /** moaum.throttle.staff-sign-in, and so on */
        public String key() {
            return "moaum.throttle." + name().toLowerCase(Locale.ROOT).replace('_', '-');
        }
    }

    /** refused at a door: answered 429, with the seconds until the connection may knock again */
    public static final class Throttled extends DomainRuleViolation {
        private final long retryAfterSeconds;

        Throttled(Door door, long retryAfterSeconds) {
            super(door.code, door.said + "; try again in " + Math.max(1, (retryAfterSeconds + 59) / 60) + " minute"
                    + ((retryAfterSeconds + 59) / 60 == 1 ? "" : "s") + ".", new Remedy(door.remedy, "You"));
            this.retryAfterSeconds = retryAfterSeconds;
        }

        public long retryAfterSeconds() {
            return retryAfterSeconds;
        }
    }

    private static final int MAX_KEYS = 50_000;

    private final Map<Door, Integer> limits = new EnumMap<>(Door.class);
    private final ConcurrentHashMap<String, ArrayDeque<Long>> knocks = new ConcurrentHashMap<>();

    Throttle(Environment env) {
        for (Door d : Door.values()) {
            Integer n = env.getProperty(d.key(), Integer.class, d.limit);
            limits.put(d, n == null || n < 1 ? d.limit : n);
        }
    }

    public int limit(Door door) {
        return limits.get(door);
    }

    /** refused when the connection has used the door's number in the window */
    public void refuse(Door door, String source) {
        if (ClientAddress.local(source)) return;
        ArrayDeque<Long> q = knocks.get(door.name() + "|" + source);
        if (q == null) return;
        long now = System.currentTimeMillis();
        synchronized (q) {
            prune(q, now);
            if (q.size() >= limits.get(door)) {
                long oldest = q.peekFirst() == null ? now : q.peekFirst();
                throw new Throttled(door, Math.max(1, (oldest + WINDOW.toMillis() - now) / 1000));
            }
        }
    }

    /** one knock counted against the connection */
    public void count(Door door, String source) {
        if (ClientAddress.local(source)) return;
        if (knocks.size() > MAX_KEYS) sweep();
        ArrayDeque<Long> q = knocks.computeIfAbsent(door.name() + "|" + source, k -> new ArrayDeque<>());
        long now = System.currentTimeMillis();
        synchronized (q) {
            prune(q, now);
            q.addLast(now);
        }
    }

    /** refused when spent, otherwise counted: for a door counted every time */
    public void take(Door door, String source) {
        refuse(door, source);
        count(door, source);
    }

    private static void prune(ArrayDeque<Long> q, long now) {
        long floor = now - WINDOW.toMillis();
        while (!q.isEmpty() && q.peekFirst() < floor) q.pollFirst();
    }

    /** the connections whose knocks are all older than the window are forgotten; the rest are kept */
    private void sweep() {
        long now = System.currentTimeMillis();
        knocks.entrySet().removeIf(e -> {
            synchronized (e.getValue()) {
                prune(e.getValue(), now);
                return e.getValue().isEmpty();
            }
        });
    }
}
