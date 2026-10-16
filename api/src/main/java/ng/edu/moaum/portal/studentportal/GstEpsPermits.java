package ng.edu.moaum.portal.studentportal;

import java.util.LinkedHashMap;
import java.util.Map;
import java.util.UUID;

import ng.edu.moaum.portal.shared.CheckCodes;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * V492: a student's GST & EPS examination permit — whether it may be issued and why not, the GST and EPS courses on the
 * student's approved registration (read by the database, never filtered in the browser), and its issue with the signed
 * check code its QR carries. The rules are the database's (registration.gst_eps_permit_state); this reads them.
 */
@Service
public class GstEpsPermits {

    private static final tools.jackson.databind.ObjectMapper JSON = new tools.jackson.databind.ObjectMapper();

    private final JdbcClient jdbc;
    private final CheckCodes codes;

    GstEpsPermits(JdbcClient jdbc, CheckCodes codes) {
        this.jdbc = jdbc;
        this.codes = codes;
    }

    /** the permit's state for the student's session and semester; nothing is made or counted */
    @Transactional(readOnly = true)
    public Map<String, Object> state(UUID student, String session, int semester) {
        return read(jdbc.sql("SELECT registration.gst_eps_permit_state(:s, :ses, :sem)::text")
                .param("s", student).param("ses", session).param("sem", semester).query(String.class).single());
    }

    /** the permit issued (VIEW, DOWNLOAD or PRINT): made at the first issue, counted each time, with the check code its QR carries;
     *  refused with the reason (GST_EPS_PERMIT_…) when a rule fails */
    @Transactional
    public Map<String, Object> issue(UUID student, String session, int semester, String act) {
        Map<String, Object> out = read(jdbc.sql("SELECT registration.issue_gst_eps_permit(:s, :ses, :sem, :act)::text")
                .param("s", student).param("ses", session).param("sem", semester).param("act", act).query(String.class).single());
        @SuppressWarnings("unchecked")
        Map<String, Object> permit = (Map<String, Object>) out.get("permit");
        out.put("checkCode", codes.sign(CheckCodes.Kind.GST_EPS_PERMIT, String.valueOf(permit.get("reference"))));
        return out;
    }

    /** whether a check code is the one signed for this reference */
    public boolean signed(String code, String reference) {
        return codes.signed(code, CheckCodes.Kind.GST_EPS_PERMIT, reference);
    }

    @SuppressWarnings("unchecked")
    static Map<String, Object> read(String json) {
        return new LinkedHashMap<>(JSON.readValue(json, Map.class));
    }
}
