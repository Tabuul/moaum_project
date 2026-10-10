package ng.edu.moaum.portal.shared;

import java.time.OffsetDateTime;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Component;

/**
 * The application windows of the admission exercise (V312; JUPEB from V339): whether Post-UTME registration, the
 * postgraduate application and the JUPEB application are open — the Director of ICT's rule in {@code policy.portal_window}, read from the
 * server's clock — and the message the public reads while one is closed. The door every new application comes
 * through: {@link #requireOpen} refuses with the Director's own message, and the database refuses once more
 * behind it, so no path round the API can start an application while the window is closed.
 */
@Component
public class ApplicationWindows {

    public static final String POST_UTME = "POST_UTME_REGISTRATION";
    public static final String POSTGRADUATE = "POSTGRADUATE_APPLICATION";
    /** V339: the JUPEB programme's application; closed until the Director of ICT first opens it */
    public static final String JUPEB = "JUPEB_APPLICATION";
    /** V379: the Centre for Continuing Education's application (only those on JAMB's CCE list); closed until first opened */
    public static final String CCE = "CCE_APPLICATION";
    public static final List<String> TYPES = List.of(POST_UTME, POSTGRADUATE, JUPEB, CCE);
    /** V385: the Post-UTME CBT examination's door (may candidates sit) and the result-checking page (may candidates read a released score);
     *  the Director's windows over the admission exercise, closed until first opened, independent of Post-UTME registration */
    public static final String POST_UTME_CBT = "POST_UTME_CBT";
    public static final String POST_UTME_RESULTS = "POST_UTME_RESULT_CHECKING";
    public static final List<String> POST_UTME_CBT_TYPES = List.of(POST_UTME_CBT, POST_UTME_RESULTS);

    /** one window as the public reads it: the session it is for, its state, its dates, and the closure message */
    public record Window(String type, String session, String state, OffsetDateTime opensAt, OffsetDateTime closesAt, String message) {
        public boolean open() {
            return "OPEN".equals(state);
        }
    }

    private final JdbcClient jdbc;

    public ApplicationWindows(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    public static String word(String type) {
        return POST_UTME.equals(type) ? "Post-UTME registration" : JUPEB.equals(type) ? "JUPEB application" : CCE.equals(type) ? "The CCE application"
                : POST_UTME_CBT.equals(type) ? "The Post-UTME CBT examination" : POST_UTME_RESULTS.equals(type) ? "Post-UTME result checking" : "Postgraduate application";
    }

    /** the session a new application of this kind is filed under today */
    public String sessionOf(String type) {
        return jdbc.sql("SELECT policy.application_session(:t)").param("t", type).query(String.class).single();
    }

    /** the window for a session, or for the session an application would be filed under today when none is named */
    public Window read(String type, String session) {
        String s = session == null || session.isBlank() ? sessionOf(type) : session.trim();
        Map<String, Object> w = jdbc.sql("""
                SELECT w.state, w.opens_at, w.closes_at, (SELECT m.message FROM policy.portal_window_message m WHERE m.window_type = :t) AS message
                  FROM policy.window_state(:t, :s, NULL) w
                """).param("t", type).param("s", s).query().singleRow();
        return new Window(type, s, String.valueOf(w.get("state")), at(w.get("opens_at")), at(w.get("closes_at")), (String) w.get("message"));
    }

    /** every application window, for the login page, the apply pages and the University's website */
    public Map<String, Window> readAll(String postUtmeSession) {
        Map<String, Window> out = new LinkedHashMap<>();
        out.put(POST_UTME, read(POST_UTME, postUtmeSession));
        out.put(POSTGRADUATE, read(POSTGRADUATE, null));
        out.put(JUPEB, read(JUPEB, null));
        out.put(CCE, read(CCE, null));
        return out;
    }

    /** the door: a new application of this kind for this session goes through only while its window is open */
    public Window requireOpen(String type, String session) {
        Window w = read(type, session);
        if (!w.open()) {
            String detail = w.message() == null || w.message().isBlank()
                    ? word(type) + " for " + w.session() + " is " + w.state().toLowerCase() + "."
                    : w.message();
            String remedy = switch (w.state()) {
                case "SCHEDULED" -> w.opensAt() == null ? "It opens on the date the University announces." : "It opens on " + day(w.opensAt()) + ".";
                case "EXPIRED" -> w.closesAt() == null ? "The application period has ended." : "The application period ended on " + day(w.closesAt()) + ".";
                default -> "Watch the University's website and this portal for the next application period.";
            };
            throw new DomainRuleViolation("APPLICATION_CLOSED", detail, new DomainRuleViolation.Remedy(remedy, "Directorate of ICT"));
        }
        return w;
    }

    private static OffsetDateTime at(Object v) {
        if (v == null) return null;
        if (v instanceof OffsetDateTime o) return o;
        if (v instanceof java.sql.Timestamp ts) return ts.toInstant().atOffset(java.time.ZoneOffset.UTC);
        if (v instanceof java.time.Instant i) return i.atOffset(java.time.ZoneOffset.UTC);
        try {
            return OffsetDateTime.parse(String.valueOf(v));
        } catch (RuntimeException e) {
            return null;
        }
    }

    private static String day(OffsetDateTime t) {
        return t.atZoneSameInstant(java.time.ZoneId.of("Africa/Lagos")).format(java.time.format.DateTimeFormatter.ofPattern("d MMMM yyyy 'at' HH:mm"));
    }
}
