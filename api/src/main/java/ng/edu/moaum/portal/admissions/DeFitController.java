package ng.edu.moaum.portal.admissions;

import java.sql.Types;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

import ng.edu.moaum.portal.shared.AuditContext;
import ng.edu.moaum.portal.shared.AuditContextHolder;
import ng.edu.moaum.portal.shared.DomainRuleViolation;
import ng.edu.moaum.portal.shared.NotFound;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * V773: the Direct Entry Preliminary Fit rules of a session's admission settings (admissions.de_fit_rule) — how a candidate's
 * qualification is read against a programme on the Direct Entry candidates workbook: Relevant, Partly relevant, Not relevant or
 * Check manually. One rule is six rows, one for each kind of qualification (DEGREE, UNIVERSITY_DIPLOMA, HND, ND, NCE, A_LEVEL): the
 * University's default applies to every programme, a programme's own rule replaces it whole, and where a session states none the
 * built-in default is read (admissions.de_fit_rules). A guide for the Admissions Committee only — it never changes the rank, the
 * qualified test or the decision — so, like the subject sets, it is corrected whether the settings are a draft or in force. Read
 * by every admissions office; written by the Committee's secretariat.
 */
@RestController
@RequestMapping("/api/v1/admissions/sessions/{session}/{year}/policy")
class DeFitController {

    private static final String READERS =
            "hasAnyAuthority('OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar','OFFICE_dvc','OFFICE_vc','OFFICE_records','OFFICE_dean','OFFICE_hod','OFFICE_ict','OFFICE_admin','OFFICE_super')";
    private static final String SECRETARIAT = "hasAnyAuthority('OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar')";

    /** the six kinds, in the order every rule is read and written */
    static final List<String> KINDS = List.of("DEGREE", "UNIVERSITY_DIPLOMA", "HND", "ND", "NCE", "A_LEVEL");
    /** each kind in words, as admissions.de_fit_criteria names it */
    private static final Map<String, String> LABEL = Map.of(
            "DEGREE", "1st Degree (Nigerian or foreign)", "UNIVERSITY_DIPLOMA", "University Diploma", "HND", "Higher National Diploma (HND)",
            "ND", "National Diploma (ND)", "NCE", "Nigeria Certificate in Education (NCE)", "A_LEVEL", "A'Level (GCE, IJMB, JUPEB)");
    /** the most points each kind's scale reaches (admissions.de_points_max; an A'Level threshold is a letter, A 5 … E 1) */
    private static final Map<String, Integer> MAX = Map.of("DEGREE", 5, "UNIVERSITY_DIPLOMA", 4, "HND", 5, "ND", 4, "NCE", 15, "A_LEVEL", 5);
    private static final Set<String> OTHER_FITS = Set.of("RELEVANT", "PARTLY_RELEVANT", "NOT_RELEVANT", "CHECK_MANUALLY");
    private static final String KIND_ORDER =
            "CASE f.kind WHEN 'DEGREE' THEN 1 WHEN 'UNIVERSITY_DIPLOMA' THEN 2 WHEN 'HND' THEN 3 WHEN 'ND' THEN 4 WHEN 'NCE' THEN 5 ELSE 6 END";

    private final JdbcClient jdbc;
    private final tools.jackson.databind.ObjectMapper json;

    DeFitController(JdbcClient jdbc, tools.jackson.databind.ObjectMapper json) {
        this.jdbc = jdbc;
        this.json = json;
    }

    /** one kind's rule: an absent coreDisciplines is "any discipline", an empty one "none" */
    public record RuleIn(String kind, List<String> coreDisciplines, Integer relevantMin, Integer partlyMin, List<String> relatedDisciplines,
                         Integer relatedRelevantMin, Integer relatedPartlyMin, String otherFit, Integer relevantPasses, Integer partlyPasses) {
    }

    public record RulesIn(List<RuleIn> rows) {
    }

    /** the rules of the session: the University's default (or the built-in one), each programme's own, and both in words */
    @GetMapping("/de-fit")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> fit(@PathVariable String session, @PathVariable String year) {
        return read(session + "/" + year);
    }

    /** the University's default for every programme, replaced whole */
    @PutMapping("/de-fit")
    @PreAuthorize(SECRETARIAT)
    @Transactional
    Map<String, Object> saveDefault(@PathVariable String session, @PathVariable String year, @RequestBody RulesIn body) {
        String s = session + "/" + year;
        UUID policy = policy(s);
        replace(policy, null, checked(body == null ? null : body.rows(), false));
        return read(s);
    }

    /** a programme's own rule, replaced whole; no rows: removed, and the programme follows the default again */
    @PutMapping("/programmes/{code}/de-fit")
    @PreAuthorize(SECRETARIAT)
    @Transactional
    Map<String, Object> saveProgramme(@PathVariable String session, @PathVariable String year, @PathVariable String code, @RequestBody RulesIn body) {
        String s = session + "/" + year;
        UUID policy = policy(s);
        String programme = code.trim().toUpperCase();
        if (jdbc.sql("SELECT count(*) FROM ref.programme WHERE code = :c").param("c", programme).query(Long.class).single() == 0) {
            throw new NotFound("programme", programme);
        }
        replace(policy, programme, checked(body == null ? null : body.rows(), true));
        return read(s);
    }

    private UUID policy(String session) {
        return jdbc.sql("SELECT id FROM admissions.session_policy WHERE session = :s").param("s", session).query(UUID.class).optional()
                .orElseThrow(() -> new NotFound("admission settings for", session));
    }

    private Map<String, Object> read(String session) {
        UUID policy = policy(session);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("session", session);
        out.put("policyState", jdbc.sql("SELECT state FROM admissions.session_policy WHERE id = :p").param("p", policy).query(String.class).single());

        // each kind's classes from the highest, for the editor's choices (an NCE is a number of points, 0 to 15)
        Map<String, List<Map<String, Object>>> classes = new LinkedHashMap<>();
        for (Map<String, Object> r : jdbc.sql("""
                SELECT k.kind, gs.pts AS points, admissions.de_class_name(k.kind, gs.pts) AS name
                  FROM (VALUES (1, 'DEGREE'), (2, 'UNIVERSITY_DIPLOMA'), (3, 'HND'), (4, 'ND'), (5, 'A_LEVEL')) k(o, kind)
                 CROSS JOIN LATERAL generate_series(admissions.de_points_max(k.kind), 1, -1) gs(pts)
                 WHERE admissions.de_class_name(k.kind, gs.pts) IS NOT NULL
                 ORDER BY k.o, gs.pts DESC
                """).query().listOfRows()) {
            Map<String, Object> c = new LinkedHashMap<>();
            c.put("points", r.get("points"));
            c.put("name", r.get("name"));
            classes.computeIfAbsent((String) r.get("kind"), k -> new ArrayList<>()).add(c);
        }
        out.put("classes", classes);

        // the default: the session's own where it states one, else the built-in (a programme of NULL has no rule of its own).
        // rule is jsonb: read as text and parsed
        List<Map<String, Object>> rows = new ArrayList<>();
        String source = null;
        for (Map<String, Object> r : jdbc.sql("SELECT f.source, f.rule::text AS rule_text FROM admissions.de_fit_rules(:p, CAST(NULL AS text)) f ORDER BY " + KIND_ORDER)
                .param("p", policy).query().listOfRows()) {
            source = (String) r.get("source");
            rows.add(rule((String) r.get("rule_text")));
        }
        Map<String, Object> dflt = new LinkedHashMap<>();
        dflt.put("source", source);
        dflt.put("rows", rows);
        dflt.put("criteria", criteria(jdbc.sql("SELECT f.qualification, f.rule_applied FROM admissions.de_fit_criteria(:s, CAST(NULL AS text)) f ORDER BY f.ord")
                .param("s", session).query().listOfRows()));
        out.put("default", dflt);

        // the programmes with a rule of their own, by name
        Map<String, Map<String, Object>> own = new LinkedHashMap<>();
        for (Map<String, Object> r : jdbc.sql("""
                SELECT c.code, pg.name, f.rule::text AS rule_text
                  FROM (SELECT DISTINCT r.programme_code AS code FROM admissions.de_fit_rule r
                         WHERE r.policy_id = :p AND r.programme_code IS NOT NULL) c
                  JOIN ref.programme pg ON pg.code = c.code
                 CROSS JOIN LATERAL admissions.de_fit_rules(:p, c.code) f
                 ORDER BY pg.name, c.code,
                """ + KIND_ORDER).param("p", policy).query().listOfRows()) {
            Map<String, Object> programme = own.computeIfAbsent((String) r.get("code"), k -> {
                Map<String, Object> m = new LinkedHashMap<>();
                m.put("code", k);
                m.put("name", r.get("name"));
                m.put("rows", new ArrayList<Map<String, Object>>());
                m.put("criteria", new ArrayList<Map<String, Object>>());
                return m;
            });
            rowsOf(programme, "rows").add(rule((String) r.get("rule_text")));
        }
        for (Map<String, Object> r : jdbc.sql("""
                SELECT c.code, f.qualification, f.rule_applied
                  FROM (SELECT DISTINCT r.programme_code AS code FROM admissions.de_fit_rule r
                         WHERE r.policy_id = :p AND r.programme_code IS NOT NULL) c
                 CROSS JOIN LATERAL admissions.de_fit_criteria(:s, c.code) f
                 ORDER BY c.code, f.ord
                """).param("p", policy).param("s", session).query().listOfRows()) {
            Map<String, Object> programme = own.get((String) r.get("code"));
            if (programme != null) {
                rowsOf(programme, "criteria").addAll(criteria(List.of(r)));
            }
        }
        out.put("programmes", new ArrayList<>(own.values()));
        return out;
    }

    @SuppressWarnings("unchecked")
    private static List<Map<String, Object>> rowsOf(Map<String, Object> programme, String key) {
        return (List<Map<String, Object>>) programme.get(key);
    }

    private static List<Map<String, Object>> criteria(List<Map<String, Object>> lines) {
        List<Map<String, Object>> out = new ArrayList<>();
        for (Map<String, Object> r : lines) {
            Map<String, Object> line = new LinkedHashMap<>();
            line.put("qualification", r.get("qualification"));
            line.put("rule", r.get("rule_applied"));
            out.add(line);
        }
        return out;
    }

    /** a rule as admissions.de_fit_rules gives it (its column names) in the API's words; a null is left out */
    private Map<String, Object> rule(String text) {
        Map<String, Object> r = json.readValue(text, new tools.jackson.core.type.TypeReference<Map<String, Object>>() { });
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("kind", r.get("kind"));
        put(out, "coreDisciplines", r.get("core_disciplines"));
        put(out, "relevantMin", r.get("relevant_min"));
        put(out, "partlyMin", r.get("partly_min"));
        out.put("relatedDisciplines", r.get("related_disciplines") == null ? List.of() : r.get("related_disciplines"));
        put(out, "relatedRelevantMin", r.get("related_relevant_min"));
        put(out, "relatedPartlyMin", r.get("related_partly_min"));
        out.put("otherFit", r.get("other_fit"));
        put(out, "relevantPasses", r.get("relevant_passes"));
        put(out, "partlyPasses", r.get("partly_passes"));
        return out;
    }

    private static void put(Map<String, Object> map, String key, Object value) {
        if (value != null) {
            map.put(key, value);
        }
    }

    /** a list as it is kept: trimmed, without blanks, a discipline named twice (whatever its case) once; null stays null */
    private static List<String> clean(List<String> items) {
        if (items == null) {
            return null;
        }
        Set<String> seen = new LinkedHashSet<>();
        List<String> out = new ArrayList<>();
        for (String item : items) {
            String t = item == null ? "" : item.trim();
            if (!t.isEmpty() && seen.add(t.toLowerCase())) {
                out.add(t);
            }
        }
        return out;
    }

    /** the six rows in their order, their lists cleaned — or the refusal, before anything is written; the table's own checks stand behind these */
    private static List<RuleIn> checked(List<RuleIn> sent, boolean mayBeNone) {
        List<RuleIn> rows = sent == null ? List.of() : sent;
        if (rows.isEmpty() && mayBeNone) {
            return List.of();
        }
        Map<String, RuleIn> byKind = new LinkedHashMap<>();
        boolean sixOnce = rows.size() == KINDS.size();
        for (RuleIn r : rows) {
            if (r == null || r.kind() == null || !KINDS.contains(r.kind()) || byKind.put(r.kind(), r) != null) {
                sixOnce = false;
            }
        }
        if (!sixOnce) {
            throw refused("ADM_DE_FIT_KINDS", "A rule states each of the six qualifications once: DEGREE, UNIVERSITY_DIPLOMA, HND, ND, NCE, A_LEVEL.",
                    "Send all six rows, one per qualification.");
        }
        List<RuleIn> out = new ArrayList<>();
        for (String kind : KINDS) {
            RuleIn r = byKind.get(kind);
            List<String> related = clean(r.relatedDisciplines());
            out.add(new RuleIn(kind, clean(r.coreDisciplines()), r.relevantMin(), r.partlyMin(), related == null ? List.of() : related,
                    r.relatedRelevantMin(), r.relatedPartlyMin(), r.otherFit(), r.relevantPasses(), r.partlyPasses()));
        }
        for (RuleIn r : out) {
            if (r.otherFit() == null || !OTHER_FITS.contains(r.otherFit())) {
                throw refused("ADM_DE_FIT_OTHER",
                        LABEL.get(r.kind()) + ": “any other discipline” must be Relevant, Partly relevant, Not relevant or Check manually.",
                        "Choose one of the four.");
            }
        }
        for (RuleIn r : out) {
            int min = "A_LEVEL".equals(r.kind()) ? 1 : 0;
            int max = MAX.get(r.kind());
            for (Integer threshold : new Integer[] {r.relevantMin(), r.partlyMin(), r.relatedRelevantMin(), r.relatedPartlyMin()}) {
                if (threshold != null && (threshold < min || threshold > max)) {
                    throw refused("ADM_DE_FIT_RANGE", LABEL.get(r.kind()) + ": a threshold must be between " + min + " and " + max + ".",
                            "Choose a class (or a number of points) the qualification can reach.");
                }
            }
        }
        for (RuleIn r : out) {
            if ((r.relevantMin() != null && r.partlyMin() != null && r.relevantMin() < r.partlyMin())
                    || (r.relatedRelevantMin() != null && r.relatedPartlyMin() != null && r.relatedRelevantMin() < r.relatedPartlyMin())) {
                throw refused("ADM_DE_FIT_ORDER", LABEL.get(r.kind()) + ": Relevant cannot start below Partly relevant.",
                        "Set Relevant at the same class as Partly relevant or above it.");
            }
        }
        for (RuleIn r : out) {
            boolean wrong = "A_LEVEL".equals(r.kind())
                    ? r.relevantMin() == null || r.partlyMin() == null || r.relevantPasses() == null || r.partlyPasses() == null
                            || r.relevantPasses() < 1 || r.relevantPasses() > 9 || r.partlyPasses() < 1 || r.partlyPasses() > 9
                            || !r.relatedDisciplines().isEmpty() || r.relatedRelevantMin() != null || r.relatedPartlyMin() != null
                    : r.relevantPasses() != null || r.partlyPasses() != null;
            if (wrong) {
                throw refused("ADM_DE_FIT_PASSES",
                        "A'Level: state the passes and the grade for Relevant and for Partly relevant (1–9 passes, A–E); other qualifications take no passes.",
                        "Fill both lines of the A'Level card.");
            }
        }
        for (RuleIn r : out) {
            List<String> core = r.coreDisciplines();
            boolean wrong = r.relatedDisciplines().size() > 60 || r.relatedDisciplines().stream().anyMatch(x -> x.length() > 120)
                    || (core != null && (core.size() > 60 || core.stream().anyMatch(x -> x.length() > 120)))
                    || ("A_LEVEL".equals(r.kind()) && core != null && core.isEmpty());
            if (wrong) {
                throw refused("ADM_DE_FIT_LIST", LABEL.get(r.kind()) + ": a list holds 1 to 60 disciplines (or subjects) of at most 120 characters each.",
                        "Shorten the list, or choose “Any discipline” (for A'Level, “the programme's Direct Entry subjects”).");
            }
        }
        return out;
    }

    /** the policy's default (programme null) or a programme's own rule replaced whole: its rows removed, the six written (none: back to the default) */
    private void replace(UUID policy, String programme, List<RuleIn> rows) {
        AuditContext actor = AuditContextHolder.required();
        jdbc.sql("DELETE FROM admissions.de_fit_rule WHERE policy_id = :p AND coalesce(programme_code, '') = coalesce(:c, '')")
                .param("p", policy).param("c", programme, Types.VARCHAR).update();
        for (RuleIn r : rows) {
            // the lists travel as JSON and are made text[] in their order; a null core list stays NULL (every discipline is core)
            jdbc.sql("""
                    INSERT INTO admissions.de_fit_rule (policy_id, programme_code, kind, core_disciplines, relevant_min, partly_min, related_disciplines,
                                                        related_relevant_min, related_partly_min, other_fit, relevant_passes, partly_passes, set_by, set_office)
                    VALUES (:p, :c, :kind,
                            CASE WHEN CAST(:core AS text) IS NULL THEN NULL
                                 ELSE ARRAY(SELECT e.x FROM jsonb_array_elements_text(CAST(:core AS jsonb)) WITH ORDINALITY e(x, o) ORDER BY e.o) END,
                            :rmin, :pmin,
                            ARRAY(SELECT e.x FROM jsonb_array_elements_text(CAST(:related AS jsonb)) WITH ORDINALITY e(x, o) ORDER BY e.o),
                            :rrmin, :rpmin, :other, :rpass, :ppass, :by, :office)
                    """).param("p", policy).param("c", programme, Types.VARCHAR).param("kind", r.kind())
                    .param("core", r.coreDisciplines() == null ? null : json.writeValueAsString(r.coreDisciplines()), Types.VARCHAR)
                    .param("rmin", r.relevantMin(), Types.INTEGER).param("pmin", r.partlyMin(), Types.INTEGER)
                    .param("related", json.writeValueAsString(r.relatedDisciplines()))
                    .param("rrmin", r.relatedRelevantMin(), Types.INTEGER).param("rpmin", r.relatedPartlyMin(), Types.INTEGER)
                    .param("other", r.otherFit())
                    .param("rpass", r.relevantPasses(), Types.INTEGER).param("ppass", r.partlyPasses(), Types.INTEGER)
                    .param("by", actor.actorId()).param("office", actor.actorOffice()).update();
        }
    }

    private static DomainRuleViolation refused(String code, String detail, String remedy) {
        return new DomainRuleViolation(code, detail, new DomainRuleViolation.Remedy(remedy, "Central Admissions Committee"));
    }
}
