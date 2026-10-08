package ng.edu.moaum.portal.shared;

import java.util.Map;
import java.util.UUID;

import org.springframework.jdbc.core.simple.JdbcClient;

/**
 * V366: "why is this student paying GST/EPS?" — the whole answer for one student in a session, as the database gives it
 * (finance.gst_eps_explain): who they are (programme, department, faculty, level), their GST and EPS requirement with its
 * reason code, the entitlement, and every GST/EPS course that concerns them with its source (the programme's offering at
 * their level, a carryover, a registration) and status. Read by the student for themselves, by the GST and EPS offices,
 * the Bursary, the Academic Office and the ICT Support desk; it changes nothing. Each caller checks who may read first.
 */
public final class GstEpsExplain {

    private static final tools.jackson.databind.ObjectMapper MAPPER = new tools.jackson.databind.ObjectMapper();

    private GstEpsExplain() {
    }

    public static Map<String, Object> read(JdbcClient jdbc, UUID student, String session) {
        String text = jdbc.sql("SELECT finance.gst_eps_explain(:s, :ses)::text").param("s", student).param("ses", session).query(String.class).single();
        return MAPPER.readValue(text, new tools.jackson.core.type.TypeReference<Map<String, Object>>() { });
    }
}
