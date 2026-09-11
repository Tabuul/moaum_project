package ng.edu.moaum.portal.admissions;

import java.math.BigDecimal;
import java.sql.Types;
import java.time.LocalDate;
import java.time.LocalTime;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import jakarta.validation.Valid;
import jakarta.validation.constraints.DecimalMax;
import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

import ng.edu.moaum.portal.applicant.ApplicantService;
import ng.edu.moaum.portal.shared.AuditContextHolder;
import ng.edu.moaum.portal.shared.DomainRuleViolation;
import ng.edu.moaum.portal.shared.NotFound;

import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * The Academic Office's desk for the applicants (V021): the fees stated,
 * payments confirmed against the bank's record, documents reviewed,
 * screening batches made and seated, scores entered and released, the
 * Board's decisions entered and released, and the Registry's clearance.
 * Every act is the office's, and released things are released together.
 */
@RestController
@RequestMapping("/api/v1/admissions/sessions/{session}/{year}")
class ApplicantsController {

    private static final String READERS =
            "hasAnyAuthority('OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar','OFFICE_records','OFFICE_bursar','OFFICE_ict','OFFICE_admin','OFFICE_super')";
    private static final String OFFICE = "hasAnyAuthority('OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar')";
    private static final String CONFIRMERS = "hasAnyAuthority('OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar','OFFICE_bursar')";
    private static final String REGISTRY = "hasAnyAuthority('OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar','OFFICE_records')";

    public record Fees(@NotNull @DecimalMin("0") BigDecimal applicationFee, @NotNull @DecimalMin("0") BigDecimal portalCharge,
                       @NotNull @DecimalMin("0") BigDecimal acceptanceFee) {
    }

    public record Confirmation(@NotBlank @Size(max = 60) String channel, @Size(max = 400) String note) {
    }

    public record Review(@NotBlank String status, @Size(max = 400) String note) {
    }

    public record NewBatch(@NotBlank @Size(max = 20) String label, @NotNull LocalDate heldOn, @NotNull LocalTime startsAt,
                           @NotNull LocalTime endsAt, @NotBlank @Size(max = 200) String venue, @Min(1) @Max(5000) int capacity) {
    }

    public record Score(@NotNull @DecimalMin("0") @DecimalMax("100") BigDecimal score) {
    }

    /** {@code basis}: NM, SM, ELG, LOCALITY, PLWD or OTHER — what goes back to JAMB as the general remark (V025); required for an offer */
    public record Decision(@NotBlank String decision, @Size(max = 400) String note, @Size(max = 20) String basis) {
    }

    private static final List<String> BASES = List.of("NM", "SM", "ELG", "LOCALITY", "PLWD", "OTHER");

    public record Clearance(@NotBlank String state, @Size(max = 400) String note) {
    }

    private final JdbcClient jdbc;
    private final ApplicantService applicants;

    ApplicantsController(JdbcClient jdbc, ApplicantService applicants) {
        this.jdbc = jdbc;
        this.applicants = applicants;
    }

    /* ── the list ── */

    @GetMapping("/applicants")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> applicants(@PathVariable String session, @PathVariable String year) {
        String s = session + "/" + year;
        List<Map<String, Object>> rows = jdbc.sql("""
                SELECT a.id, a.application_no, c.surname, c.other_names, c.jamb_reg_no AS jamb_key, c.programme, c.entry_mode,
                       admissions.application_stage(a.id) AS stage,
                       a.fee_confirmed_at, a.submitted_at, sb.label AS batch, a.seat, a.screening_score, a.score_released_at,
                       a.decision, a.decision_basis, a.decision_released_at, a.accepted_at, a.declined_at, a.cleared_at, acc.email, acc.phone,
                       (SELECT count(*) FROM admissions.fee_reference f WHERE f.application_id = a.id AND f.confirmed_at IS NULL AND f.expires_at > now()) AS references_open,
                       (SELECT count(*) FROM admissions.application_document d WHERE d.application_id = a.id AND d.superseded_at IS NULL AND d.status = 'PENDING') AS documents_pending,
                       st.admission_no, st.matric_no
                  FROM admissions.application a
                  JOIN admissions.applicant_account acc ON acc.id = a.account_id
                  JOIN admissions.candidate c ON c.id = a.candidate_id
                  LEFT JOIN admissions.screening_batch sb ON sb.id = a.screening_batch_id
                  LEFT JOIN people.student st ON st.candidate_id = c.id
                 WHERE a.session = :s
                 ORDER BY a.application_no
                """).param("s", s).query().listOfRows();
        List<Map<String, Object>> batches = batches(s);
        List<Map<String, Object>> references = jdbc.sql("""
                SELECT f.id, f.reference, f.kind, f.amount, f.generated_at, f.expires_at, a.application_no, c.surname, c.other_names
                  FROM admissions.fee_reference f
                  JOIN admissions.application a ON a.id = f.application_id
                  JOIN admissions.candidate c ON c.id = a.candidate_id
                 WHERE a.session = :s AND f.confirmed_at IS NULL
                 ORDER BY f.generated_at DESC
                """).param("s", s).query().listOfRows();
        Map<String, Object> fees = jdbc.sql("SELECT * FROM admissions.applicant_fee_rule(:s)").param("s", s).query().singleRow();
        return Map.of("session", s, "applications", rows, "batches", batches, "openReferences", references,
                "fees", Map.of("stated", fees.get("stated"), "applicationFee", fees.get("application_fee"),
                        "portalCharge", fees.get("portal_charge"), "acceptanceFee", fees.get("acceptance_fee")));
    }

    private List<Map<String, Object>> batches(String session) {
        return jdbc.sql("""
                SELECT b.id, b.label, b.held_on, b.starts_at, b.ends_at, b.venue, b.capacity,
                       (SELECT count(*) FROM admissions.application a WHERE a.screening_batch_id = b.id) AS seated
                  FROM admissions.screening_batch b WHERE b.session = :s ORDER BY b.held_on, b.starts_at, b.label
                """).param("s", session).query().listOfRows();
    }

    @GetMapping("/applications/{id}")
    @PreAuthorize(READERS)
    Map<String, Object> application(@PathVariable String session, @PathVariable String year, @PathVariable UUID id) {
        Map<String, Object> v = applicants.view(id, true);
        if (!(session + "/" + year).equals(v.get("session"))) {
            throw new NotFound("application in " + session + "/" + year, id);
        }
        return v;
    }

    /* ── the fees ── */

    // the applicant fees are set on the Academic Office desk and, since they are a
    // charge like any other, on the Bursary's fee-setup screen too
    private static final String FEESETTERS =
            "hasAnyAuthority('OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar','OFFICE_bursar','OFFICE_ict','OFFICE_admin','OFFICE_super')";

    /** the applicant fees for a session — the Post-UTME screening fee, the portal charge and the acceptance fee */
    @GetMapping("/applicant-fees")
    @PreAuthorize(FEESETTERS)
    Map<String, Object> applicantFees(@PathVariable String session, @PathVariable String year) {
        Map<String, Object> f = jdbc.sql("SELECT * FROM admissions.applicant_fee_rule(:s)").param("s", session + "/" + year).query().singleRow();
        return Map.of("session", session + "/" + year, "stated", f.get("stated"),
                "applicationFee", f.get("application_fee"), "portalCharge", f.get("portal_charge"), "acceptanceFee", f.get("acceptance_fee"));
    }

    @PutMapping("/applicant-fees")
    @PreAuthorize(FEESETTERS)
    @Transactional
    Map<String, Object> fees(@PathVariable String session, @PathVariable String year, @Valid @RequestBody Fees body) {
        String s = session + "/" + year;
        jdbc.sql("""
                INSERT INTO admissions.applicant_fee (session, application_fee, portal_charge, acceptance_fee, stated_at)
                VALUES (:s, :a, :p, :c, now())
                ON CONFLICT (session) DO UPDATE SET application_fee = EXCLUDED.application_fee, portal_charge = EXCLUDED.portal_charge,
                    acceptance_fee = EXCLUDED.acceptance_fee, stated_at = now()
                """).param("s", s).param("a", body.applicationFee()).param("p", body.portalCharge()).param("c", body.acceptanceFee()).update();
        return applicants(session, year);
    }

    @PostMapping("/fee-references/{reference}/confirm")
    @PreAuthorize(CONFIRMERS)
    @Transactional
    Map<String, Object> confirm(@PathVariable String session, @PathVariable String year, @PathVariable String reference,
                                @Valid @RequestBody Confirmation body) {
        String outcome = jdbc.sql("SELECT admissions.confirm_fee(:r, :c, :n)")
                .param("r", reference).param("c", body.channel()).param("n", body.note(), Types.VARCHAR).query(String.class).single();
        return Map.of("reference", reference, "outcome", outcome);
    }

    /* ── the documents ── */

    @PostMapping("/applications/{id}/documents/{documentId}/review")
    @PreAuthorize(OFFICE)
    @Transactional
    Map<String, Object> review(@PathVariable String session, @PathVariable String year, @PathVariable UUID id,
                               @PathVariable UUID documentId, @Valid @RequestBody Review body) {
        String status = body.status().trim().toUpperCase();
        if (!List.of("ACCEPTED", "REJECTED").contains(status)) {
            throw new DomainRuleViolation("APP_REVIEW", "'" + body.status() + "' is not a review outcome.",
                    new DomainRuleViolation.Remedy("ACCEPTED or REJECTED, with the reason for a rejection.", "Academic Office"));
        }
        if (status.equals("REJECTED") && (body.note() == null || body.note().isBlank())) {
            throw new DomainRuleViolation("APP_REVIEW_NOTE", "A rejection says what was wrong.",
                    new DomainRuleViolation.Remedy("The applicant must know what to replace it with.", "Academic Office"));
        }
        UUID actor = AuditContextHolder.current().map(c -> c.actorId()).orElse(null);
        int n = jdbc.sql("""
                UPDATE admissions.application_document SET status = :st, review_note = :n, reviewed_at = now(), reviewed_by = :by
                 WHERE id = :d AND application_id = :a AND superseded_at IS NULL
                """).param("st", status).param("n", body.note(), Types.VARCHAR).param("by", actor).param("d", documentId).param("a", id).update();
        if (n == 0) {
            throw new NotFound("current document", documentId);
        }
        return applicants.view(id, true);
    }

    @GetMapping("/applications/{id}/documents/{documentId}/content")
    @PreAuthorize(READERS)
    ResponseEntity<byte[]> content(@PathVariable String session, @PathVariable String year, @PathVariable UUID id, @PathVariable UUID documentId) {
        var c = applicants.anyDocumentContent(documentId);
        return ResponseEntity.ok().contentType(MediaType.parseMediaType(c.contentType()))
                .header(HttpHeaders.CONTENT_DISPOSITION, "inline; filename=\"" + c.filename().replace("\"", "") + "\"")
                .body(c.content());
    }

    /* ── screening ── */

    @GetMapping("/screening-batches")
    @PreAuthorize(READERS)
    List<Map<String, Object>> screeningBatches(@PathVariable String session, @PathVariable String year) {
        return batches(session + "/" + year);
    }

    @PostMapping("/screening-batches")
    @PreAuthorize(OFFICE)
    @Transactional
    List<Map<String, Object>> newBatch(@PathVariable String session, @PathVariable String year, @Valid @RequestBody NewBatch body) {
        String s = session + "/" + year;
        jdbc.sql("""
                INSERT INTO admissions.screening_batch (id, session, label, held_on, starts_at, ends_at, venue, capacity)
                VALUES (gen_random_uuid(), :s, :l, :d, :a, :b, :v, :c)
                """).param("s", s).param("l", body.label().trim().toUpperCase()).param("d", body.heldOn()).param("a", body.startsAt())
                .param("b", body.endsAt()).param("v", body.venue().trim()).param("c", body.capacity()).update();
        return batches(s);
    }

    @PostMapping("/screening-batches/{id}/assign")
    @PreAuthorize(OFFICE)
    @Transactional
    Map<String, Object> assign(@PathVariable String session, @PathVariable String year, @PathVariable UUID id) {
        int seated = jdbc.sql("SELECT admissions.assign_screening(:id)").param("id", id).query(Integer.class).single();
        return Map.of("batchId", id, "seated", seated);
    }

    @PutMapping("/applications/{id}/screening-score")
    @PreAuthorize(OFFICE)
    @Transactional
    Map<String, Object> score(@PathVariable String session, @PathVariable String year, @PathVariable UUID id, @Valid @RequestBody Score body) {
        int n = jdbc.sql("""
                UPDATE admissions.application SET screening_score = :v, score_entered_at = now()
                 WHERE id = :id AND screening_batch_id IS NOT NULL AND score_released_at IS NULL
                """).param("v", body.score()).param("id", id).update();
        if (n == 0) {
            throw new DomainRuleViolation("APP_SCORE_LOCKED", "The score is entered for a seated candidate, and not after it is released.",
                    new DomainRuleViolation.Remedy("Seat the candidate first; a released score is corrected by the Board, on the record.", "Academic Office"));
        }
        return applicants.view(id, true);
    }

    // Post-UTME scores are uploaded in bulk and reconciled against the applicant records;
    // the Directorate of ICT and the Super Administrator do it, as well as the Academic Office
    private static final String SCORE_UPLOADERS =
            "hasAnyAuthority('OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar','OFFICE_ict','OFFICE_admin','OFFICE_super')";

    public record ScoreRow(String key, java.math.BigDecimal score) {
    }

    public record ScoreUpload(@jakarta.validation.constraints.NotNull List<ScoreRow> rows) {
    }

    /**
     * A batch of Post-UTME scores, each keyed by JAMB registration number or
     * application number, reconciled against the session's applicants: a matched
     * candidate whose score is not yet released has it entered; the rest are
     * reported (not found, already released, out of range) and nothing is invented.
     */
    @PostMapping("/screening-scores/upload")
    @PreAuthorize(SCORE_UPLOADERS)
    @Transactional
    Map<String, Object> uploadScores(@PathVariable String session, @PathVariable String year, @Valid @RequestBody ScoreUpload body) {
        String s = session + "/" + year;
        int applied = 0;
        List<String> notFound = new java.util.ArrayList<>();
        List<String> alreadyReleased = new java.util.ArrayList<>();
        List<String> outOfRange = new java.util.ArrayList<>();
        for (ScoreRow row : body.rows()) {
            String key = row.key() == null ? "" : row.key().trim().toUpperCase();
            if (key.isEmpty()) {
                continue;
            }
            if (row.score() == null || row.score().signum() < 0 || row.score().compareTo(new java.math.BigDecimal("100")) > 0) {
                outOfRange.add(key);
                continue;
            }
            Map<String, Object> app = jdbc.sql("""
                    SELECT a.id, a.score_released_at FROM admissions.application a
                      JOIN admissions.candidate c ON c.id = a.candidate_id
                     WHERE a.session = :s AND (upper(c.jamb_reg_no) = :k OR upper(c.jamb_key) = :k OR upper(a.application_no) = :k)
                     LIMIT 1
                    """).param("s", s).param("k", key).query().listOfRows().stream().findFirst().orElse(null);
            if (app == null) {
                notFound.add(key);
                continue;
            }
            if (app.get("score_released_at") != null) {
                alreadyReleased.add(key);
                continue;
            }
            jdbc.sql("UPDATE admissions.application SET screening_score = :v, score_entered_at = now() WHERE id = :id AND score_released_at IS NULL")
                    .param("v", row.score()).param("id", app.get("id")).update();
            applied++;
        }
        Map<String, Object> out = new java.util.LinkedHashMap<>();
        out.put("received", body.rows().size());
        out.put("applied", applied);
        out.put("notFound", notFound);
        out.put("alreadyReleased", alreadyReleased);
        out.put("outOfRange", outOfRange);
        return out;
    }

    @PostMapping("/screening-scores/release")
    @PreAuthorize(OFFICE)
    @Transactional
    Map<String, Object> releaseScores(@PathVariable String session, @PathVariable String year) {
        int n = jdbc.sql("SELECT admissions.release_scores(:s)").param("s", session + "/" + year).query(Integer.class).single();
        return Map.of("released", n);
    }

    /* ── the Board ── */

    @PutMapping("/applications/{id}/decision")
    @PreAuthorize(OFFICE)
    @Transactional
    Map<String, Object> decide(@PathVariable String session, @PathVariable String year, @PathVariable UUID id, @Valid @RequestBody Decision body) {
        String d = body.decision().trim().toUpperCase();
        if (!List.of("OFFERED", "WAITING", "NOT_OFFERED").contains(d)) {
            throw new DomainRuleViolation("APP_DECISION", "'" + body.decision() + "' is not one of the Board's three outcomes.",
                    new DomainRuleViolation.Remedy("OFFERED, WAITING or NOT_OFFERED.", "Admissions Board"));
        }
        String basis = body.basis() == null || body.basis().isBlank() ? null : body.basis().trim().toUpperCase();
        if (basis != null && !BASES.contains(basis)) {
            throw new DomainRuleViolation("APP_DECISION_BASIS", "'" + body.basis() + "' is not a basis the Board admits on.",
                    new DomainRuleViolation.Remedy("NM, SM, ELG, LOCALITY, PLWD or OTHER — it is what goes back to JAMB.", "Admissions Board"));
        }
        jdbc.sql("SELECT admissions.decide_application(:id, :d, :n, :b)").param("id", id).param("d", d)
                .param("n", body.note(), Types.VARCHAR).param("b", basis, Types.VARCHAR).query(String.class).single();
        return applicants.view(id, true);
    }

    @PostMapping("/decisions/release")
    @PreAuthorize(OFFICE)
    @Transactional
    Map<String, Object> releaseDecisions(@PathVariable String session, @PathVariable String year) {
        int n = jdbc.sql("SELECT admissions.release_decisions(:s)").param("s", session + "/" + year).query(Integer.class).single();
        return Map.of("released", n);
    }

    /* ── the list that goes back to JAMB ── */

    /**
     * The rows of JAMB's admission template for one programme (or all): the
     * UTME subjects and score as CAPS sent them, the O'Level grades and points
     * under the session's grading — English, Mathematics, then the three best
     * relevant subjects — the sittings and their bonus, the two ratios under
     * the session's weighting, the total, and the Board's decision as the
     * remark. Every figure is the same one the applicant's result shows.
     */
    @GetMapping("/jamb-template")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> jambTemplate(@PathVariable String session, @PathVariable String year,
                                     @org.springframework.web.bind.annotation.RequestParam(required = false) String programme) {
        String s = session + "/" + year;
        List<Map<String, Object>> rows = jdbc.sql("""
                SELECT a.id, a.application_no, c.jamb_reg_no, c.jamb_key, c.surname, c.other_names, c.programme, c.entry_mode,
                       r.sex, r.state_of_origin, r.lga, r.aggregate AS utme, r.raw::text AS raw_text,
                       a.decision, a.decision_note, a.decision_basis, a.decision_released_at, a.screening_score, a.submitted_at,
                       sr.utme_scaled, sr.screening, sr.screening_source, sr.weight_utme, sr.weight_putme, sr.aggregate AS total, sr.cutoff,
                       sc.olevel_total, sc.olevel_ceiling,
                       (SELECT count(DISTINCT st.id) FROM admissions.olevel_sitting st WHERE st.session = a.session AND st.jamb_key = c.jamb_key) AS sittings,
                       rule.bonus_one_sitting, rule.bonus_two_sittings, rule.subjects_counted
                  FROM admissions.application a
                  JOIN admissions.candidate c ON c.id = a.candidate_id
                  LEFT JOIN admissions.caps_row r ON r.id = c.admitted_from
                  CROSS JOIN LATERAL admissions.screening_result(a.id) sr
                  CROSS JOIN LATERAL admissions.screening_component(a.id) sc
                  CROSS JOIN LATERAL admissions.olevel_rule(a.session) rule
                 WHERE a.session = :s AND a.submitted_at IS NOT NULL AND (:p::text IS NULL OR c.programme = :p)
                 ORDER BY c.programme, sr.aggregate DESC NULLS LAST, c.surname, c.other_names
                """).param("s", s).param("p", programme, Types.VARCHAR).query().listOfRows();
        List<Map<String, Object>> out = new java.util.ArrayList<>();
        for (Map<String, Object> r : rows) {
            Map<String, Object> raw = CandidateDataController.Json.map((String) r.get("raw_text"));
            List<Map<String, Object>> grades = jdbc.sql("""
                    SELECT g.subject, (array_agg(g.grade ORDER BY admissions.olevel_points(:s, g.grade) DESC, g.grade))[1] AS grade,
                           max(admissions.olevel_points(:s, g.grade)) AS points
                      FROM admissions.olevel_sitting st JOIN admissions.olevel_grade g ON g.sitting_id = st.id
                     WHERE st.session = :s AND st.jamb_key = :k
                     GROUP BY g.subject ORDER BY points DESC, g.subject
                    """).param("s", s).param("k", r.get("jamb_key")).query().listOfRows();
            Map<String, Object> eng = grades.stream().filter(g -> "English Language".equals(g.get("subject"))).findFirst().orElse(null);
            Map<String, Object> maths = grades.stream().filter(g -> "Mathematics".equals(g.get("subject"))).findFirst().orElse(null);
            List<Map<String, Object>> others = grades.stream().filter(g -> g != eng && g != maths).limit(3).toList();
            long sittings = ((Number) r.get("sittings")).longValue();
            int bonus = sittings == 0 ? 0 : sittings == 1 ? ((Number) r.get("bonus_one_sitting")).intValue() : ((Number) r.get("bonus_two_sittings")).intValue();
            Map<String, Object> row = new LinkedHashMap<>();
            row.put("applicationNo", r.get("application_no"));
            row.put("regNo", r.get("jamb_reg_no"));
            row.put("name", r.get("surname") + " " + r.get("other_names"));
            row.put("gender", "F".equals(r.get("sex")) ? "Female" : "M".equals(r.get("sex")) ? "Male" : r.get("sex"));
            row.put("state", r.get("state_of_origin"));
            row.put("lga", r.get("lga"));
            row.put("programme", r.get("programme"));
            row.put("entryMode", r.get("entry_mode"));
            row.put("utmeSubjects", utmeSubjects(raw));
            row.put("utmeScore", r.get("utme"));
            row.put("engGrade", eng == null ? null : eng.get("grade"));
            row.put("engPoint", eng == null ? null : eng.get("points"));
            row.put("mathsGrade", maths == null ? null : maths.get("grade"));
            row.put("mathsPoint", maths == null ? null : maths.get("points"));
            row.put("others", others);
            row.put("sittings", sittings);
            row.put("cbtScore", r.get("screening_score"));
            row.put("sittingPoints", bonus);
            row.put("olevelTotal", r.get("olevel_total"));
            row.put("olevelCeiling", r.get("olevel_ceiling"));
            row.put("screening", r.get("screening"));
            row.put("screeningSource", r.get("screening_source"));
            row.put("weightUtme", r.get("weight_utme"));
            row.put("weightPutme", r.get("weight_putme"));
            row.put("olevelRatio", r.get("screening") == null ? null : scale(r.get("screening"), r.get("weight_putme")));
            row.put("utmeRatio", r.get("utme_scaled") == null ? null : scale(r.get("utme_scaled"), r.get("weight_utme")));
            row.put("total", r.get("total"));
            row.put("cutoff", r.get("cutoff"));
            row.put("decision", r.get("decision"));
            row.put("decisionNote", r.get("decision_note"));
            row.put("decisionBasis", r.get("decision_basis"));
            row.put("released", r.get("decision_released_at") != null);
            out.add(row);
        }
        Map<String, Object> fees = jdbc.sql("SELECT count(*) AS n FROM admissions.application WHERE session = :s AND (:p::text IS NULL OR candidate_id IN (SELECT id FROM admissions.candidate WHERE programme = :p))")
                .param("s", s).param("p", programme, Types.VARCHAR).query().singleRow();
        long onCaps = jdbc.sql("SELECT count(*) FROM admissions.caps_row_live r JOIN ref.programme p ON p.code = r.jamb_code WHERE r.session = :s AND (:p::text IS NULL OR p.name = :p)")
                .param("s", s).param("p", programme, Types.VARCHAR).query(Long.class).single();
        Integer quota = programme == null ? null : jdbc.sql("""
                SELECT f.quota FROM admissions.faculty_quota f JOIN admissions.session_policy p ON p.id = f.policy_id
                  JOIN ref.programme pr ON pr.faculty_code = f.faculty_code WHERE p.session = :s AND pr.name = :p LIMIT 1
                """).param("s", s).param("p", programme).query(Integer.class).optional().orElse(null);
        // the UTME share of the quota: the faculty's UTME:DE ratio where set, else the session's (V054)
        Integer ratioUtme = programme == null ? null : jdbc.sql("""
                SELECT coalesce(f.ratio_utme, p.ratio_utme) FROM admissions.session_policy p
                  LEFT JOIN admissions.faculty_quota f ON f.policy_id = p.id
                    AND f.faculty_code = (SELECT faculty_code FROM ref.programme WHERE name = :p LIMIT 1)
                 WHERE p.session = :s LIMIT 1
                """).param("s", s).param("p", programme).query(Integer.class).optional().orElse(null);
        Integer utmeQuota = (quota == null || ratioUtme == null) ? null : (int) Math.round(quota * ratioUtme / 100.0);
        long onMerit = out.stream().filter(x -> "OFFERED".equals(x.get("decision"))).count();
        Map<String, Object> summary = new LinkedHashMap<>();
        summary.put("totalApplicants", onCaps);
        summary.put("registeredApplicants", ((Number) fees.get("n")).longValue());
        summary.put("qualifiedCases", out.stream().filter(x -> "OFFERED".equals(x.get("decision")) || "WAITING".equals(x.get("decision"))).count());
        summary.put("nonQualifiedCases", out.stream().filter(x -> "NOT_OFFERED".equals(x.get("decision"))).count());
        summary.put("totalQuota", quota);
        summary.put("utmeQuota", utmeQuota);
        summary.put("numberOnMeritList", onMerit);

        // the quota distribution: each selection criterion's share of the UTME quota, and how many it admitted
        List<Map<String, Object>> quotaDistribution = new java.util.ArrayList<>();
        if (programme != null && utmeQuota != null) {
            Map<String, String> critName = Map.of("NM", "National Merit", "SM", "State Merit", "ELG", "Equality of LG", "LOCALITY", "Locality");
            for (String code : List.of("NM", "SM", "ELG", "LOCALITY")) {
                Integer pct = jdbc.sql("SELECT sc.percent FROM admissions.selection_criterion sc JOIN admissions.session_policy p ON p.id = sc.policy_id WHERE p.session = :s AND sc.criterion = :c")
                        .param("s", s).param("c", code).query(Integer.class).optional().orElse(null);
                if (pct == null) {
                    continue;
                }
                long admitted = out.stream().filter(x -> "OFFERED".equals(x.get("decision")) && code.equals(x.get("decisionBasis"))).count();
                int cQuota = (int) Math.round(utmeQuota * pct / 100.0);
                Map<String, Object> row = new LinkedHashMap<>();
                row.put("criterion", critName.get(code));
                row.put("percent", pct);
                row.put("quota", cQuota);
                row.put("admitted", admitted);
                row.put("shortfall", Math.max(cQuota - admitted, 0));
                quotaDistribution.add(row);
            }
        }

        // the LGA analysis: the offered candidates by local government and the basis they came in on
        List<Map<String, Object>> lgaAnalysis = new java.util.ArrayList<>();
        Map<String, long[]> byLga = new java.util.TreeMap<>();
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
        long tElg = 0;
        long tSm = 0;
        long tNm = 0;
        for (Map.Entry<String, long[]> e : byLga.entrySet()) {
            long[] c = e.getValue();
            tElg += c[0];
            tSm += c[1];
            tNm += c[2];
            Map<String, Object> row = new LinkedHashMap<>();
            row.put("lga", e.getKey());
            row.put("elg", c[0]);
            row.put("sm", c[1]);
            row.put("nm", c[2]);
            row.put("total", c[0] + c[1] + c[2]);
            lgaAnalysis.add(row);
        }
        Map<String, Object> lgaTotal = new LinkedHashMap<>();
        lgaTotal.put("lga", "TOTAL");
        lgaTotal.put("elg", tElg);
        lgaTotal.put("sm", tSm);
        lgaTotal.put("nm", tNm);
        lgaTotal.put("total", tElg + tSm + tNm);

        Map<String, Object> result = new LinkedHashMap<>();
        result.put("session", s);
        result.put("programme", programme == null ? "" : programme);
        result.put("asAt", LocalDate.now().toString());
        result.put("summary", summary);
        result.put("quotaDistribution", quotaDistribution);
        result.put("lgaAnalysis", lgaAnalysis);
        result.put("lgaTotal", lgaTotal);
        result.put("rows", out);
        return result;
    }

    private static Object scale(Object value, Object weight) {
        return new BigDecimal(String.valueOf(value)).multiply(new BigDecimal(String.valueOf(weight))).divide(BigDecimal.valueOf(100), 2, java.math.RoundingMode.HALF_UP);
    }

    /** the UTME subjects and scores as CAPS sent them, whichever of the two layouts the row came in */
    private static List<Map<String, Object>> utmeSubjects(Map<String, Object> raw) {
        List<Map<String, Object>> out = new java.util.ArrayList<>();
        for (int i = 1; i <= 4; i++) {
            Object subject = first(raw, "Subject" + i, "SUBJECT" + i, "subject" + i, "Subj" + i);
            Object score = first(raw, "RG_Sub" + i + "Score", "Subject" + i + "Score", "SUBJECT" + i + "SCORE", "Score" + i, "Subj" + i + "Score");
            if (subject != null || score != null) {
                out.add(Map.of("subject", subject == null ? "" : String.valueOf(subject), "score", score == null ? "" : String.valueOf(score)));
            }
        }
        Object eng = first(raw, "EngScore", "ENGSCORE", "English", "ENG");
        if (eng != null && out.stream().noneMatch(x -> String.valueOf(x.get("subject")).toLowerCase().startsWith("eng"))) {
            out.add(0, Map.of("subject", "English Language", "score", String.valueOf(eng)));
        }
        return out;
    }

    private static Object first(Map<String, Object> raw, String... keys) {
        for (String k : keys) {
            for (Map.Entry<String, Object> e : raw.entrySet()) {
                if (e.getKey().equalsIgnoreCase(k) && e.getValue() != null && !String.valueOf(e.getValue()).isBlank()) {
                    return e.getValue();
                }
            }
        }
        return null;
    }

    /** the hall list of one batch: every seat in order, with the photograph on file, for the invigilator at the door */
    @GetMapping("/screening-batches/{id}/hall-list")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> hallList(@PathVariable String session, @PathVariable String year, @PathVariable UUID id) {
        String s = session + "/" + year;
        Map<String, Object> batch = jdbc.sql("SELECT id, label, held_on, starts_at, ends_at, venue, capacity FROM admissions.screening_batch WHERE id = :id AND session = :s")
                .param("id", id).param("s", s).query().listOfRows().stream().findFirst().orElseThrow(() -> new NotFound("screening batch", id));
        List<Map<String, Object>> seats = jdbc.sql("""
                SELECT a.id, a.seat, a.application_no, c.surname, c.other_names, c.jamb_reg_no AS jamb_key, c.programme, c.entry_mode,
                       (SELECT d.id FROM admissions.application_document d WHERE d.application_id = a.id AND d.kind = 'PASSPORT' AND d.superseded_at IS NULL) AS passport_id
                  FROM admissions.application a JOIN admissions.candidate c ON c.id = a.candidate_id
                 WHERE a.screening_batch_id = :id ORDER BY a.seat
                """).param("id", id).query().listOfRows();
        return Map.of("session", s, "batch", batch, "seats", seats);
    }

    /* ── clearance ── */

    @PutMapping("/applications/{id}/clearance/{item}")
    @PreAuthorize(REGISTRY)
    @Transactional
    Map<String, Object> clearance(@PathVariable String session, @PathVariable String year, @PathVariable UUID id,
                                  @PathVariable String item, @Valid @RequestBody Clearance body) {
        String st = body.state().trim().toUpperCase();
        if (!List.of("NOT_PRESENTED", "VERIFIED", "QUERY").contains(st)) {
            throw new DomainRuleViolation("APP_CLEARANCE_STATE", "'" + body.state() + "' is not a clearance state.",
                    new DomainRuleViolation.Remedy("NOT_PRESENTED, VERIFIED or QUERY, with the query stated.", "Registry"));
        }
        jdbc.sql("SELECT admissions.clear_document(:id, :i, :s, :n)").param("id", id).param("i", item.trim().toUpperCase())
                .param("s", st).param("n", body.note(), Types.VARCHAR).query(Integer.class).single();
        return applicants.view(id, true);
    }
}
