package ng.edu.moaum.portal.admissions;

import java.sql.Types;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import jakarta.validation.Valid;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

import ng.edu.moaum.portal.shared.AuditContext;
import ng.edu.moaum.portal.shared.AuditContextHolder;
import ng.edu.moaum.portal.shared.DomainRuleViolation;
import ng.edu.moaum.portal.shared.NotFound;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * V773: the Direct Entry candidates with their qualifications — the Admissions Committee's screening sheet, in the layout of the
 * two workbooks the University gave on 15 November 2026, for every Direct Entry programme. The download: everyone on JAMB's live
 * Direct Entry list for a programme (by the code the list carries, read through the programme aliases in force), registered on the
 * portal or not, with the qualification that counts, its score (the points as a percentage of the qualification's own maximum), a
 * Preliminary Fit (a guide for the Committee, never a decision) and the O'Level the portal holds, ranked by score, ties by name
 * (admissions.de_candidates); the programmes on the list; and one candidate found by REG NO. The upload: a workbook in the same
 * layout, read by the screen, each row's qualification recorded at once (admissions.de_upload_record) — first decided without
 * writing (the preview), then committed; a row an earlier upload recorded unchanged is left as it is, so the same file twice changes
 * nothing. A key whose value is null is left out of every answer.
 */
@RestController
@RequestMapping("/api/v1/admissions/sessions/{session}/{year}")
class DeCandidatesController {

    private static final String READERS =
            "hasAnyAuthority('OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar','OFFICE_records','OFFICE_bursar','OFFICE_ict','OFFICE_admin','OFFICE_super')";
    private static final String LOADERS = "hasAnyAuthority('OFFICE_academic','OFFICE_registrar')";

    private final JdbcClient jdbc;
    private final tools.jackson.databind.ObjectMapper json;

    DeCandidatesController(JdbcClient jdbc, tools.jackson.databind.ObjectMapper json) {
        this.jdbc = jdbc;
        this.json = json;
    }

    // ── the upload ──

    public record UploadSubjectIn(@Size(max = 120) String subject, @Size(max = 60) String grade) {
    }

    /** one row of the workbook as the screen read it (lib/de-candidates.ts parseDeCandidatesWorkbook) */
    public record UploadRowIn(@NotNull @Min(1) Integer line,
                              @NotBlank @Size(max = 40) String regNo,
                              @Size(max = 120) String capsQualification,
                              @Min(0) @Max(99) Integer capsGrade,
                              Boolean hasFiveCredits,
                              Boolean isCleared,
                              @Size(max = 60) String status,
                              @Min(0) @Max(120) Integer age,
                              Boolean ageQualified,
                              @Size(max = 80) String admissionCategory,
                              @Size(max = 120) String typeText,
                              @Size(max = 40) String basis,
                              @Size(max = 200) String discipline,
                              @Size(max = 60) String awardClass,
                              @Size(max = 12) List<@Valid UploadSubjectIn> subjects,
                              @Size(max = 200) String institution,
                              @Min(1960) @Max(2100) Integer year,
                              @Size(max = 60) String examNo,
                              @Size(max = 10) List<@Size(max = 200) String> notes) {
    }

    public record UploadIn(@Size(max = 255) String filename,
                           @Pattern(regexp = "[0-9a-fA-F]{64}", message = "sha256 must be 64 hexadecimal characters") String sha256,
                           @Pattern(regexp = "C[0-9]{5}", message = "programme must be a programme code") String programme,
                           @NotNull @Size(min = 1, max = 2000) List<@Valid @NotNull UploadRowIn> rows) {
    }

    /** what an upload would record: every row's outcome and problems decided, nothing written (so no audit lock, no trigger) */
    @PostMapping("/de-candidates/upload/preview")
    @PreAuthorize(LOADERS)
    @Transactional(readOnly = true)
    Map<String, Object> preview(@PathVariable String session, @PathVariable String year, @Valid @RequestBody UploadIn body) {
        return decide(session + "/" + year, body, false);
    }

    /** the upload recorded: only the rows that change something are written, under one admissions.de_upload row; none when nothing changes */
    @PostMapping("/de-candidates/upload")
    @PreAuthorize(LOADERS)
    @Transactional
    Map<String, Object> upload(@PathVariable String session, @PathVariable String year, @Valid @RequestBody UploadIn body) {
        return decide(session + "/" + year, body, true);
    }

    private Map<String, Object> decide(String s, UploadIn body, boolean commit) {
        AuditContext actor = AuditContextHolder.required();
        if (commit && !CapsIntakeService.UPLOADING_OFFICES.contains(actor.actorOffice())) {
            // ck on admissions.de_upload: the token may carry the office and the request still act as another
            throw new DomainRuleViolation("ADM_DE_UPLOAD_OFFICE",
                    "Direct Entry qualifications are uploaded by the Academic Office or the Registrar, not by '" + actor.actorOffice() + "'.",
                    new DomainRuleViolation.Remedy("Ask the Academic Office to upload the file, or act as that office if you hold it.", "Academic Office"));
        }
        List<Map<String, Object>> sent = new ArrayList<>();
        for (UploadRowIn r : body.rows()) {
            Map<String, Object> row = new LinkedHashMap<>();
            put(row, "line", r.line());
            put(row, "regNo", r.regNo());
            put(row, "capsQualification", r.capsQualification());
            put(row, "capsGrade", r.capsGrade());
            put(row, "hasFiveCredits", r.hasFiveCredits());
            put(row, "isCleared", r.isCleared());
            put(row, "status", r.status());
            put(row, "age", r.age());
            put(row, "ageQualified", r.ageQualified());
            put(row, "admissionCategory", r.admissionCategory());
            put(row, "typeText", r.typeText());
            put(row, "basis", r.basis());
            put(row, "discipline", r.discipline());
            put(row, "awardClass", r.awardClass());
            List<Map<String, Object>> subjects = new ArrayList<>();
            for (UploadSubjectIn x : r.subjects() == null ? List.<UploadSubjectIn>of() : r.subjects()) {
                if (x == null) {
                    continue;
                }
                Map<String, Object> subject = new LinkedHashMap<>();
                put(subject, "subject", x.subject());
                put(subject, "grade", x.grade());
                subjects.add(subject);
            }
            row.put("subjects", subjects);
            put(row, "institution", r.institution());
            put(row, "year", r.year());
            put(row, "examNo", r.examNo());
            row.put("notes", r.notes() == null ? List.of() : r.notes().stream().filter(n -> n != null).toList());
            sent.add(row);
        }
        String programme = body.programme() == null || body.programme().isBlank() ? null : body.programme();
        // problems is jsonb: read as text and parsed (a PGobject would reach the JSON as {"type":"jsonb","value":…})
        List<Map<String, Object>> decided = jdbc.sql("""
                SELECT r.line, r.reg_no, r.jamb_key, r.name, r.programme_code, r.programme, r.outcome, r.problems::text AS problems_text, r.upload_id
                  FROM admissions.de_upload_record(:s, :p, CAST(:rows AS jsonb), :f, decode(:sha, 'hex'), :actor, :office, :commit) r
                """).param("s", s).param("p", programme, Types.VARCHAR).param("rows", json.writeValueAsString(sent))
                .param("f", body.filename() == null || body.filename().isBlank() ? null : body.filename().trim(), Types.VARCHAR)
                .param("sha", body.sha256(), Types.VARCHAR).param("actor", actor.actorId()).param("office", actor.actorOffice())
                .param("commit", commit).query().listOfRows();

        List<Map<String, Object>> rows = new ArrayList<>();
        int recorded = 0, unchanged = 0, skipped = 0, repeated = 0, warnings = 0;
        Object uploadId = null;
        for (Map<String, Object> r : decided) {
            List<Map<String, Object>> problems = list((String) r.get("problems_text"));
            Map<String, Object> row = new LinkedHashMap<>();
            put(row, "line", r.get("line"));
            put(row, "regNo", r.get("reg_no"));
            put(row, "name", r.get("name"));
            put(row, "programmeCode", r.get("programme_code"));
            put(row, "programme", r.get("programme"));
            put(row, "outcome", r.get("outcome"));
            row.put("problems", problems);
            rows.add(row);
            switch (String.valueOf(r.get("outcome"))) {
                case "RECORDED" -> recorded++;
                case "UNCHANGED" -> unchanged++;
                case "SKIPPED" -> skipped++;
                default -> repeated++;
            }
            if (problems.stream().anyMatch(p -> "WARNING".equals(p.get("level")))) {
                warnings++;
            }
            if (uploadId == null) {
                uploadId = r.get("upload_id");
            }
        }
        Map<String, Object> counts = new LinkedHashMap<>();
        counts.put("read", rows.size());
        counts.put("recorded", recorded);
        counts.put("unchanged", unchanged);
        counts.put("skipped", skipped);
        counts.put("repeated", repeated);
        counts.put("warnings", warnings);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("session", s);
        put(out, "programme", programme);
        out.put("preview", !commit);
        out.put("counts", counts);
        out.put("rows", rows);
        // only a commit that recorded something names its upload
        put(out, "uploadId", uploadId);
        return out;
    }

    // ── the download ──

    /** every programme with a candidate on JAMB's live Direct Entry list, by name: on the list, registered, with a qualification captured */
    @GetMapping("/de-candidates/programmes")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> programmes(@PathVariable String session, @PathVariable String year) {
        String s = session + "/" + year;
        List<Map<String, Object>> programmes = new ArrayList<>();
        for (Map<String, Object> r : jdbc.sql("""
                WITH rws AS (
                    SELECT admissions.de_programme_of(x.jamb_code) AS code, x.jamb_key
                      FROM admissions.caps_row_live x WHERE x.session = :s AND x.entry_mode = 'DIRECT_ENTRY'),
                reg AS (
                    SELECT DISTINCT c.jamb_key FROM admissions.candidate c JOIN admissions.application a ON a.candidate_id = c.id
                     WHERE c.session = :s AND c.jamb_key IS NOT NULL),
                rec AS (
                    SELECT DISTINCT d.jamb_key FROM admissions.de_award_scores(:s, ARRAY(SELECT r.jamb_key FROM rws r)) d WHERE d.captured)
                SELECT r.code, pg.name, count(*) AS on_list, count(reg.jamb_key) AS registered, count(rec.jamb_key) AS recorded
                  FROM rws r
                  JOIN ref.programme pg ON pg.code = r.code
                  LEFT JOIN reg ON reg.jamb_key = r.jamb_key
                  LEFT JOIN rec ON rec.jamb_key = r.jamb_key
                 GROUP BY r.code, pg.name
                 ORDER BY pg.name, r.code
                """).param("s", s).query().listOfRows()) {
            Map<String, Object> row = new LinkedHashMap<>();
            row.put("code", r.get("code"));
            row.put("name", r.get("name"));
            row.put("onList", r.get("on_list"));
            row.put("registered", r.get("registered"));
            row.put("recorded", r.get("recorded"));
            programmes.add(row);
        }
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("session", s);
        out.put("programmes", programmes);
        return out;
    }

    /** one programme's workbook: its candidates in rank order, its O'Level subjects, the fit rules in force in words */
    @GetMapping("/de-candidates")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> candidates(@PathVariable String session, @PathVariable String year, @RequestParam String programme) {
        String s = session + "/" + year;
        String code = programme.trim();
        String name = !code.matches("C[0-9]{5}") ? null
                : jdbc.sql("SELECT name FROM ref.programme WHERE code = :c").param("c", code).query(String.class).optional().orElse(null);
        if (name == null) {
            throw new NotFound("programme", code);
        }
        // the day the sheet is made, in Lagos: the ages are counted to it
        LocalDate today = jdbc.sql("SELECT (now() AT TIME ZONE 'Africa/Lagos')::date").query(LocalDate.class).single();

        // the session's settings as the functions read them (in force, else as they stand) and the programme's O'Level numbers
        Map<String, Object> settings = jdbc.sql("""
                WITH pol AS (
                    SELECT p.id, p.state, p.instrument FROM admissions.session_policy p
                     WHERE p.session = :s ORDER BY (p.state = 'IN_FORCE') DESC LIMIT 1)
                SELECT (SELECT pol.state FROM pol) AS state, (SELECT pol.instrument FROM pol) AS instrument,
                       coalesce(pr.olevel_credits, 5) AS credits, greatest(1, coalesce(pr.olevel_sittings, 2)) AS sittings
                  FROM (VALUES (1)) one(x)
                  LEFT JOIN admissions.programme_rule pr ON pr.policy_id = (SELECT pol.id FROM pol) AND pr.programme_code = :c
                """).param("s", s).param("c", code).query().singleRow();
        Map<String, Object> olevel = new LinkedHashMap<>();
        olevel.put("subjects", jdbc.sql("SELECT o.item FROM admissions.de_olevel_set(:s, :c) o ORDER BY o.ord")
                .param("s", s).param("c", code).query(String.class).list());
        olevel.put("credits", settings.get("credits"));
        olevel.put("sittings", settings.get("sittings"));
        olevel.put("required", jdbc.sql("SELECT o.item FROM admissions.de_olevel_required(:s, :c) o ORDER BY o.ord")
                .param("s", s).param("c", code).query(String.class).list());

        List<Map<String, Object>> criteria = new ArrayList<>();
        Object source = null;
        for (Map<String, Object> r : jdbc.sql("SELECT f.qualification, f.rule_applied, f.source FROM admissions.de_fit_criteria(:s, :c) f ORDER BY f.ord")
                .param("s", s).param("c", code).query().listOfRows()) {
            Map<String, Object> line = new LinkedHashMap<>();
            line.put("qualification", r.get("qualification"));
            line.put("rule", r.get("rule_applied"));
            criteria.add(line);
            if (source == null) {
                source = r.get("source");
            }
        }
        Map<String, Object> fit = new LinkedHashMap<>();
        put(fit, "source", source);
        fit.put("criteria", criteria);

        List<Map<String, Object>> rows = new ArrayList<>();
        for (Map<String, Object> r : jdbc.sql("""
                SELECT t.rank, t.list_no, t.jamb_reg_no, t.name, t.state_of_origin, t.lga, t.sex,
                       t.caps_qualification, t.caps_grade, t.has_five_credits, t.is_cleared, t.status, t.age, t.age_qualified,
                       t.admission_category, t.registered, t.qualification_type, t.basis, t.discipline, t.grades, t.points, t.max_points,
                       t.score, t.class_points, t.institution, t.awarded_year, t.exam_no, t.fit, t.reason, t.other_notes,
                       t.olevel_results, t.olevel_sittings, t.sittings, t.olevel_grades::text AS olevel_grades_text,
                       t.key_credits, t.key_of, t.total_credits, t.olevel_check, t.olevel_check_kind
                  FROM admissions.de_candidates(:s, :c, :on) t
                 ORDER BY t.rank
                """).param("s", s).param("c", code).param("on", today).query().listOfRows()) {
            Map<String, Object> row = new LinkedHashMap<>();
            put(row, "rank", r.get("rank"));
            put(row, "listNo", r.get("list_no"));
            put(row, "regNo", r.get("jamb_reg_no"));
            put(row, "name", r.get("name"));
            put(row, "state", r.get("state_of_origin"));
            put(row, "lga", r.get("lga"));
            put(row, "sex", r.get("sex"));
            // CAPS's "Qualification" as the upload read it — not "qualification", which in the JAMB return's rows is the basis
            put(row, "capsQualification", r.get("caps_qualification"));
            put(row, "capsGrade", r.get("caps_grade"));
            put(row, "hasFiveCredits", r.get("has_five_credits"));
            put(row, "isCleared", r.get("is_cleared"));
            put(row, "status", r.get("status"));
            put(row, "age", r.get("age"));
            put(row, "ageQualified", r.get("age_qualified"));
            put(row, "admissionCategory", r.get("admission_category"));
            put(row, "registered", r.get("registered"));
            put(row, "qualificationType", r.get("qualification_type"));
            put(row, "basis", r.get("basis"));
            put(row, "discipline", r.get("discipline"));
            put(row, "grades", r.get("grades"));
            put(row, "points", r.get("points"));
            put(row, "maxPoints", r.get("max_points"));
            put(row, "score", r.get("score"));
            put(row, "classPoints", r.get("class_points"));
            put(row, "institution", r.get("institution"));
            put(row, "year", r.get("awarded_year"));
            put(row, "examNo", r.get("exam_no"));
            put(row, "fit", r.get("fit"));
            put(row, "reason", r.get("reason"));
            put(row, "otherNotes", r.get("other_notes"));
            put(row, "olevelResults", r.get("olevel_results"));
            put(row, "olevelSittings", r.get("olevel_sittings"));
            put(row, "sittings", r.get("sittings"));
            row.put("olevelGrades", list((String) r.get("olevel_grades_text")));
            put(row, "keyCredits", r.get("key_credits"));
            put(row, "keyOf", r.get("key_of"));
            put(row, "totalCredits", r.get("total_credits"));
            put(row, "olevelCheck", r.get("olevel_check"));
            put(row, "olevelCheckKind", r.get("olevel_check_kind"));
            rows.add(row);
        }

        Map<String, Object> out = new LinkedHashMap<>();
        out.put("session", s);
        Map<String, Object> prog = new LinkedHashMap<>();
        prog.put("code", code);
        prog.put("name", name);
        out.put("programme", prog);
        out.put("asAt", today.toString());
        if (settings.get("state") != null) {
            Map<String, Object> policy = new LinkedHashMap<>();
            policy.put("state", settings.get("state"));
            put(policy, "instrument", settings.get("instrument"));
            out.put("policy", policy);
        }
        out.put("olevel", olevel);
        out.put("fit", fit);
        out.put("rows", rows);
        return out;
    }

    /** a candidate on the session's live Direct Entry list by REG NO., registered or not — for the capture form on Direct Entry
     *  Screening, whose own list holds the submitted applications only */
    @GetMapping("/de-candidates/lookup")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> lookup(@PathVariable String session, @PathVariable String year, @RequestParam String regNo) {
        String s = session + "/" + year;
        Map<String, Object> r = jdbc.sql("""
                SELECT x.jamb_key, x.jamb_reg_no, concat_ws(' ', x.surname, x.other_names) AS name, p.code, pg.name AS programme,
                       EXISTS (SELECT 1 FROM admissions.candidate c JOIN admissions.application a ON a.candidate_id = c.id
                                WHERE c.session = x.session AND c.jamb_key = x.jamb_key) AS registered
                  FROM admissions.caps_row_live x
                 CROSS JOIN LATERAL (SELECT admissions.de_programme_of(x.jamb_code) AS code) p
                  LEFT JOIN ref.programme pg ON pg.code = p.code
                 WHERE x.session = :s AND x.entry_mode = 'DIRECT_ENTRY' AND x.jamb_key = upper(btrim(:r))
                """).param("s", s).param("r", regNo).query().listOfRows().stream().findFirst()
                .orElseThrow(() -> new NotFound("a Direct Entry candidate on JAMB's list with REG NO.", regNo.trim()));
        Map<String, Object> out = new LinkedHashMap<>();
        put(out, "jambKey", r.get("jamb_key"));
        put(out, "regNo", r.get("jamb_reg_no"));
        put(out, "name", r.get("name"));
        put(out, "programmeCode", r.get("code"));
        put(out, "programme", r.get("programme"));
        put(out, "registered", r.get("registered"));
        return out;
    }

    /** a key whose value is null is left out, whatever the JSON writer would do with it */
    private static void put(Map<String, Object> map, String key, Object value) {
        if (value != null) {
            map.put(key, value);
        }
    }

    /** a jsonb array of objects read as text, each object without its null values */
    private List<Map<String, Object>> list(String text) {
        if (text == null || text.isBlank()) {
            return List.of();
        }
        List<Map<String, Object>> parsed = json.readValue(text, new tools.jackson.core.type.TypeReference<List<Map<String, Object>>>() { });
        for (Map<String, Object> m : parsed) {
            m.values().removeIf(v -> v == null);
        }
        return parsed;
    }
}
