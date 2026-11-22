package ng.edu.moaum.portal.admissions;

import java.sql.Types;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.TreeMap;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * V764: the Direct Entry admission template — the list that goes back to JAMB for Direct Entry, mirroring the UTME one
 * ({@code ApplicantsController.jambTemplate}). Every registered Direct Entry applicant of the programme is a row
 * (admissions.de_template), ranked (V773) by the score of the qualification that counts — its points as a percentage of its own
 * maximum (an A-Level, IJMB or JUPEB of 16, an NCE of 15, a degree or an HND of 5, an ND or a University Diploma of 4), every
 * qualification together, highest first, ties by name, the unscored and then the uncaptured last — and qualified or not, with the
 * reasons; the Board's recorded decision places a row (OFFERED on the merit list, WAITING among the other qualified, NOT_OFFERED
 * among the non-qualified), and without one a qualified applicant is among the other qualified. Beside the rows: the summary (on
 * JAMB's Direct Entry list, registered, qualified and not, the programme's quota and its Direct Entry share by the faculty's or
 * the session's UTME:DE ratio, the number on the merit list), the quota distribution over the Direct Entry share and the LGA
 * analysis of those offered — the University's decisions of 14 November 2026, the ranking by its word of 15 November 2026 (the
 * workbook rule everywhere: the Direct Entry candidates workbook, {@code DeCandidatesController}, ranks the same way).
 */
@RestController
@RequestMapping("/api/v1/admissions/sessions/{session}/{year}")
class DeTemplateController {

    private static final String READERS =
            "hasAnyAuthority('OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar','OFFICE_records','OFFICE_bursar','OFFICE_ict','OFFICE_admin','OFFICE_super')";

    private final JdbcClient jdbc;
    private final tools.jackson.databind.ObjectMapper json;

    DeTemplateController(JdbcClient jdbc, tools.jackson.databind.ObjectMapper json) {
        this.jdbc = jdbc;
        this.json = json;
    }

    @GetMapping("/de-template")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> deTemplate(@PathVariable String session, @PathVariable String year,
                                   @RequestParam(required = false) String programme) {
        String s = session + "/" + year;
        String p = programme == null || programme.isBlank() ? null : programme;
        List<Map<String, Object>> out = new ArrayList<>();
        for (Map<String, Object> r : jdbc.sql("SELECT t.*, t.subjects::text AS subjects_text FROM admissions.de_template(:s, :p) t")
                .param("s", s).param("p", p, Types.VARCHAR).query().listOfRows()) {
            Map<String, Object> row = new LinkedHashMap<>();
            row.put("rank", r.get("rank"));
            row.put("applicationNo", r.get("application_no"));
            row.put("regNo", r.get("jamb_reg_no"));
            row.put("name", r.get("surname") + " " + r.get("other_names"));
            row.put("gender", "F".equals(r.get("sex")) ? "Female" : "M".equals(r.get("sex")) ? "Male" : r.get("sex"));
            row.put("state", r.get("state_of_origin"));
            row.put("lga", r.get("lga"));
            row.put("programme", r.get("programme"));
            // V773: the programme the rank is counted within — its code, whatever text the candidate's record carries for it
            row.put("programmeCode", r.get("programme_code"));
            row.put("entryMode", "DIRECT_ENTRY");
            row.put("entryLevel", r.get("entry_level"));
            row.put("qualification", r.get("qualification"));
            row.put("institution", r.get("institution"));
            row.put("awardedYear", r.get("awarded_year"));
            row.put("subjects", subjects((String) r.get("subjects_text")));
            row.put("otherQualifications", r.get("other_qualifications"));
            row.put("points", r.get("points"));
            // V773: the scale the points are on and the score the rows are ranked by (the points as a percentage of that maximum)
            row.put("maxPoints", r.get("max_points"));
            row.put("score", r.get("score"));
            row.put("unreadGrades", r.get("unread_grades"));
            row.put("deStatus", r.get("de_status"));
            row.put("olevelUploaded", r.get("olevel_uploaded"));
            row.put("olevelMissing", r.get("olevel_missing"));
            row.put("engGrade", r.get("english"));
            row.put("mathsGrade", r.get("mathematics"));
            row.put("sittings", r.get("sittings"));
            row.put("recordedDecision", r.get("recorded_decision"));
            row.put("decision", r.get("decision"));
            row.put("decisionBasis", r.get("decision_basis"));
            row.put("decisionNote", r.get("decision_note"));
            row.put("released", r.get("released"));
            row.put("qualified", r.get("qualified"));
            row.put("reason", r.get("reason"));
            out.add(row);
        }

        // on JAMB's Direct Entry list for the programme (or every programme), registered or not
        long onCaps = jdbc.sql("""
                SELECT count(*) FROM admissions.caps_row_live r JOIN ref.programme pr ON pr.code = r.jamb_code
                 WHERE r.session = :s AND r.entry_mode = 'DIRECT_ENTRY' AND (:p::text IS NULL OR pr.name = :p)
                """).param("s", s).param("p", p, Types.VARCHAR).query(Long.class).single();
        // the programme's quota, and its Direct Entry share: what the UTME share (the faculty's UTME:DE ratio where set, else the
        // session's) leaves — the split the merit engine makes (admissions.merit_list)
        Integer quota = p == null ? null : jdbc.sql("""
                SELECT r.quota FROM admissions.programme_rule r JOIN admissions.session_policy sp ON sp.id = r.policy_id
                  JOIN ref.programme pr ON pr.code = r.programme_code WHERE sp.session = :s AND sp.state = 'IN_FORCE' AND pr.name = :p
                 ORDER BY pr.archived, pr.code LIMIT 1
                """).param("s", s).param("p", p).query(Integer.class).optional().orElse(null);
        Integer ratioUtme = p == null ? null : jdbc.sql("""
                SELECT coalesce(f.ratio_utme, sp.ratio_utme) FROM admissions.session_policy sp
                  LEFT JOIN admissions.faculty_quota f ON f.policy_id = sp.id
                    AND f.faculty_code = (SELECT faculty_code FROM ref.programme WHERE name = :p ORDER BY archived, code LIMIT 1)
                 WHERE sp.session = :s AND sp.state = 'IN_FORCE' LIMIT 1
                """).param("s", s).param("p", p).query(Integer.class).optional().orElse(null);
        Integer deQuota = (quota == null || ratioUtme == null) ? null : quota - (int) Math.round(quota * ratioUtme / 100.0);
        long onMerit = out.stream().filter(x -> "OFFERED".equals(x.get("decision"))).count();
        long qualified = out.stream().filter(x -> "OFFERED".equals(x.get("decision")) || "WAITING".equals(x.get("decision"))).count();
        Map<String, Object> summary = new LinkedHashMap<>();
        summary.put("totalApplicants", onCaps);
        summary.put("registeredApplicants", (long) out.size());
        summary.put("qualifiedCases", qualified);
        summary.put("nonQualifiedCases", out.size() - qualified);
        summary.put("totalQuota", quota);
        summary.put("deQuota", deQuota);
        summary.put("deRatio", ratioUtme == null ? null : 100 - ratioUtme);
        summary.put("numberOnMeritList", onMerit);

        // the quota distribution: each selection criterion's share of the Direct Entry quota, and how many it admitted
        List<Map<String, Object>> quotaDistribution = new ArrayList<>();
        if (p != null && deQuota != null) {
            Map<String, String> critName = Map.of("NM", "National Merit", "SM", "State Merit", "ELG", "Equality of LG", "LOCALITY", "Locality");
            Map<String, String> critCode = Map.of("NM", "NATIONAL_MERIT", "SM", "STATE_MERIT", "ELG", "ELG", "LOCALITY", "LOCALITY");
            for (String code : List.of("NM", "SM", "ELG", "LOCALITY")) {
                Integer pct = jdbc.sql("""
                        SELECT sc.percent FROM admissions.selection_criterion sc JOIN admissions.session_policy sp ON sp.id = sc.policy_id
                         WHERE sp.session = :s AND sp.state = 'IN_FORCE' AND sc.criterion = :c
                        """).param("s", s).param("c", critCode.get(code)).query(Integer.class).optional().orElse(null);
                if (pct == null) {
                    continue;
                }
                long admitted = out.stream().filter(x -> "OFFERED".equals(x.get("decision")) && code.equals(x.get("decisionBasis"))).count();
                int cQuota = (int) Math.round(deQuota * pct / 100.0);
                Map<String, Object> row = new LinkedHashMap<>();
                row.put("criterion", critName.get(code));
                row.put("percent", pct);
                row.put("quota", cQuota);
                row.put("admitted", admitted);
                row.put("shortfall", Math.max(cQuota - admitted, 0));
                quotaDistribution.add(row);
            }
        }

        // the LGA analysis: the offered applicants by local government and the basis they came in on
        Map<String, long[]> byLga = new TreeMap<>();
        for (Map<String, Object> x : out) {
            if (!"OFFERED".equals(x.get("decision"))) {
                continue;
            }
            String lga = x.get("lga") == null || String.valueOf(x.get("lga")).isBlank() ? "Others" : String.valueOf(x.get("lga"));
            String basis = String.valueOf(x.get("decisionBasis"));
            long[] c = byLga.computeIfAbsent(lga, k -> new long[3]);
            if ("ELG".equals(basis)) {
                c[0]++;
            } else if ("SM".equals(basis)) {
                c[1]++;
            } else if ("NM".equals(basis)) {
                c[2]++;
            }
        }
        List<Map<String, Object>> lgaAnalysis = new ArrayList<>();
        long[] t = new long[3];
        for (Map.Entry<String, long[]> e : byLga.entrySet()) {
            long[] c = e.getValue();
            t[0] += c[0];
            t[1] += c[1];
            t[2] += c[2];
            lgaAnalysis.add(lgaRow(e.getKey(), c));
        }

        Map<String, Object> result = new LinkedHashMap<>();
        result.put("kind", "DE");
        result.put("session", s);
        result.put("programme", p == null ? "" : p);
        result.put("asAt", LocalDate.now().toString());
        result.put("summary", summary);
        result.put("quotaDistribution", quotaDistribution);
        result.put("lgaAnalysis", lgaAnalysis);
        result.put("lgaTotal", lgaRow("TOTAL", t));
        result.put("rows", out);
        return result;
    }

    private static Map<String, Object> lgaRow(String lga, long[] c) {
        Map<String, Object> row = new LinkedHashMap<>();
        row.put("lga", lga);
        row.put("elg", c[0]);
        row.put("sm", c[1]);
        row.put("nm", c[2]);
        row.put("total", c[0] + c[1] + c[2]);
        return row;
    }

    /** the qualification's subjects as the function gives them, best first: {subject, grade, points} */
    private List<Map<String, Object>> subjects(String text) {
        if (text == null || text.isBlank()) {
            return List.of();
        }
        return json.readValue(text, new tools.jackson.core.type.TypeReference<List<Map<String, Object>>>() { });
    }
}
