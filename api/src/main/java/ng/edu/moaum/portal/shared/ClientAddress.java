package ng.edu.moaum.portal.shared;

import java.util.regex.Pattern;

import jakarta.servlet.http.HttpServletRequest;

/**
 * V359: the address of the person at the other end of a request — what a limit on a public door counts, and what a
 * sign-in records. The API never sees the person directly: on Railway the portal calls it over the private network and
 * the connection's own address is the portal's; on AWS it sits behind the load balancer.
 *
 * <p>So the address is read from {@code X-Forwarded-For}, which the portal passes on as it received it. Which entry is
 * the person's depends on the edge in front of the portal: Railway's edge drops whatever the client sent and writes the
 * address it saw, so the first entry is the person's; a load balancer that appends (AWS's) writes the address it saw at
 * the end, and anything to its left the client could have written itself. The API runs on Railway when Railway says so
 * ({@code RAILWAY_ENVIRONMENT_ID}); {@code MOAUM_CLIENT_ADDRESS=first|last} overrides the choice for another edge. With no
 * header, the connection's own address. An entry that is not an address is not trusted.
 */
public final class ClientAddress {

    private static final Pattern ADDRESS = Pattern.compile("^[0-9A-Fa-f:.]{2,45}$");
    private static final Pattern IPV4_WITH_PORT = Pattern.compile("^([0-9]{1,3}(\\.[0-9]{1,3}){3}):[0-9]{1,5}$");
    private static final boolean FIRST = first(System.getenv("MOAUM_CLIENT_ADDRESS"), System.getenv("RAILWAY_ENVIRONMENT_ID"));

    private ClientAddress() {
    }

    static boolean first(String setting, String railway) {
        if ("first".equalsIgnoreCase(setting == null ? "" : setting.trim())) return true;
        if ("last".equalsIgnoreCase(setting == null ? "" : setting.trim())) return false;
        return railway != null && !railway.isBlank();
    }

    /** the person's address, or null when the request carries none that can be trusted */
    public static String of(HttpServletRequest request) {
        return pick(request.getHeader("X-Forwarded-For"), request.getRemoteAddr(), FIRST);
    }

    static String pick(String forwarded, String remote, boolean first) {
        if (forwarded != null && !forwarded.isBlank()) {
            String[] parts = forwarded.split(",");
            String p = clean(first ? parts[0] : parts[parts.length - 1]);
            if (p != null) return p;
        }
        return clean(remote);
    }

    private static String clean(String a) {
        if (a == null) return null;
        String t = a.trim();
        var withPort = IPV4_WITH_PORT.matcher(t);
        if (withPort.matches()) t = withPort.group(1);
        if (t.startsWith("[") && t.contains("]")) t = t.substring(1, t.indexOf(']'));
        return ADDRESS.matcher(t).matches() ? t : null;
    }

    /** the machine itself — development and the test suite; never a person on a network */
    public static boolean local(String address) {
        return address == null || address.equals("127.0.0.1") || address.equals("::1") || address.equals("0:0:0:0:0:0:0:1");
    }
}
