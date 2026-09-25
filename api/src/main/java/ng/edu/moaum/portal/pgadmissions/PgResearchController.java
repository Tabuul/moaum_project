package ng.edu.moaum.portal.pgadmissions;

import java.math.BigDecimal;
import java.nio.charset.StandardCharsets;
import java.util.Base64;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

import ng.edu.moaum.portal.shared.DomainRuleViolation;
import ng.edu.moaum.portal.shared.AuditContextHolder;
import ng.edu.moaum.portal.shared.NotFound;

import org.springframework.http.CacheControl;
import org.springframework.http.ContentDisposition;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.Authentication;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * The postgraduate research / thesis lifecycle (V209), following the University's Postgraduate Policy:
 * supervision → proposal → research seminar → registration of title → panel of examiners → oral defence
 * (viva) → corrections → final submission → the Secretary's clearance → the School Board's recommendation
 * to Senate → award. The candidate sees and drives the early student-side steps on their own record; the
 * School (Dean and Secretary) runs the desk that advances every stage and keeps the milestone log.
 */
@RestController
@RequestMapping("/api/v1/pg/research")
class PgResearchController {

    private static final String STUDENT = "hasAuthority('OFFICE_student')";
    private static final String SCHOOL = "hasAnyAuthority('OFFICE_pgschool','OFFICE_pgsecretary','OFFICE_super')";

    private final JdbcClient jdbc;

    PgResearchController(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    /* ── the candidate's own record ───────────────────────────────────────── */

    /** the signed-in postgraduate student's research record (created on first read) */
    @GetMapping("/me")
    @PreAuthorize(STUDENT)
    @Transactional
    Map<String, Object> mine(Authentication authentication) {
        UUID student = UUID.fromString(authentication.getName());
        UUID id = jdbc.sql("SELECT admissions.pg_research_ensure(:s)").param("s", student).query(UUID.class).single();
        return detail(id);
    }

    public record TopicIn(@NotBlank @Size(max = 400) String topic) {
    }

    /** the candidate states or revises the working topic (before the proposal is approved) */
    @PostMapping("/me/topic")
    @PreAuthorize(STUDENT)
    @Transactional
    Map<String, Object> setTopic(Authentication authentication, @Valid @RequestBody TopicIn body) {
        UUID student = UUID.fromString(authentication.getName());
        UUID id = jdbc.sql("SELECT admissions.pg_research_ensure(:s)").param("s", student).query(UUID.class).single();
        String stage = jdbc.sql("SELECT stage FROM admissions.pg_research WHERE id = :id").param("id", id).query(String.class).single();
        if (List.of("PROPOSAL_APPROVED", "SEMINAR_HELD", "TITLE_REGISTERED", "PANEL_CONSTITUTED", "DRAFT_SUBMITTED",
                "VIVA_HELD", "CORRECTIONS", "FINAL_SUBMITTED", "CLEARED", "AWARD_RECOMMENDED", "AWARDED").contains(stage)) {
            throw new DomainRuleViolation("PG_TOPIC_LOCKED", "The topic can no longer be changed here once the proposal is approved.",
                    new DomainRuleViolation.Remedy("A change of an approved topic needs the Board's approval (Policy 21.6).", "School of Postgraduate Studies"));
        }
        jdbc.sql("UPDATE admissions.pg_research SET topic = :t, updated_at = now() WHERE id = :id")
                .param("t", body.topic().trim()).param("id", id).update();
        return detail(id);
    }

    /** the candidate submits the research proposal (topic required); moves to PROPOSAL_SUBMITTED */
    @PostMapping("/me/proposal")
    @PreAuthorize(STUDENT)
    @Transactional
    Map<String, Object> submitProposal(Authentication authentication) {
        UUID student = UUID.fromString(authentication.getName());
        UUID id = jdbc.sql("SELECT admissions.pg_research_ensure(:s)").param("s", student).query(UUID.class).single();
        Map<String, Object> r = jdbc.sql("SELECT stage, topic FROM admissions.pg_research WHERE id = :id").param("id", id).query().singleRow();
        if (r.get("topic") == null || String.valueOf(r.get("topic")).isBlank()) {
            throw new DomainRuleViolation("PG_TOPIC_REQUIRED", "State your research topic before submitting the proposal.",
                    new DomainRuleViolation.Remedy("Enter the topic, then submit.", "You"));
        }
        jdbc.sql("UPDATE admissions.pg_research SET stage = 'PROPOSAL_SUBMITTED', proposal_submitted_at = now(), updated_at = now() WHERE id = :id")
                .param("id", id).update();
        event(id, "PROPOSAL_SUBMITTED", "Proposal submitted by the candidate", null);
        return detail(id);
    }

    /* ── the School's desk ─────────────────────────────────────────────────── */

    /** the research pipeline, optionally filtered by stage, with per-stage counts (School desk) */
    @GetMapping
    @PreAuthorize(SCHOOL)
    @Transactional(readOnly = true)
    Map<String, Object> list(@RequestParam(required = false) String stage) {
        List<Map<String, Object>> rows = jdbc.sql("""
                SELECT r.id, r.stage, r.degree_kind, r.topic, r.updated_at, r.viva_grade, r.viva_outcome,
                       s.matric_no, s.admission_no, s.surname, s.other_names,
                       g.name AS programme_name, g.pg_award, f.name AS faculty_name, d.name AS department_name,
                       (SELECT string_agg(sup.name, ', ' ORDER BY sup.role) FROM admissions.pg_research_supervisor sup
                         WHERE sup.research_id = r.id AND sup.ended_at IS NULL) AS supervisors
                  FROM admissions.pg_research r
                  JOIN people.student s ON s.id = r.student_id
                  JOIN ref.programme g ON g.code = s.programme_code
                  JOIN ref.faculty f ON f.code = g.faculty_code
                  JOIN ref.department d ON d.code = g.dept_code
                 WHERE (:stage::text IS NULL OR r.stage = :stage)
                 ORDER BY r.updated_at DESC
                """).param("stage", stage == null || stage.isBlank() ? null : stage.trim().toUpperCase()).query().listOfRows();
        Map<String, Object> counts = jdbc.sql("""
                SELECT count(*) AS total,
                       count(*) FILTER (WHERE stage IN ('REGISTERED','SUPERVISED')) AS supervision,
                       count(*) FILTER (WHERE stage IN ('PROPOSAL_SUBMITTED','PROPOSAL_APPROVED')) AS proposal,
                       count(*) FILTER (WHERE stage IN ('SEMINAR_HELD','TITLE_REGISTERED')) AS seminar,
                       count(*) FILTER (WHERE stage IN ('PANEL_CONSTITUTED','DRAFT_SUBMITTED','VIVA_HELD','CORRECTIONS')) AS examination,
                       count(*) FILTER (WHERE stage IN ('FINAL_SUBMITTED','CLEARED','AWARD_RECOMMENDED')) AS finishing,
                       count(*) FILTER (WHERE stage = 'AWARDED') AS awarded
                  FROM admissions.pg_research
                """).query().singleRow();
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("counts", counts);
        out.put("rows", rows);
        return out;
    }

    /** one candidate's research record in full (School desk) */
    @GetMapping("/{id}")
    @PreAuthorize(SCHOOL)
    @Transactional(readOnly = true)
    Map<String, Object> one(@PathVariable UUID id) {
        return detail(id);
    }

    public record SupervisorIn(@NotBlank @Size(max = 200) String name, UUID personId,
                               @Size(max = 10) String role, Boolean external) {
    }

    /** assign a supervisor to a candidate; the first assignment moves REGISTERED → SUPERVISED (Policy 14) */
    @PostMapping("/{id}/supervisor")
    @PreAuthorize(SCHOOL)
    @Transactional
    Map<String, Object> addSupervisor(@PathVariable UUID id, @Valid @RequestBody SupervisorIn body) {
        stageOrThrow(id);
        String role = body.role() == null || body.role().isBlank() ? "FIRST" : body.role().trim().toUpperCase();
        if (!List.of("FIRST", "SECOND", "CO").contains(role)) {
            throw new DomainRuleViolation("PG_SUP_ROLE", "A supervisor is the First, the Second, or a Co-supervisor.",
                    new DomainRuleViolation.Remedy("Choose FIRST, SECOND or CO.", "School of Postgraduate Studies"));
        }
        jdbc.sql("""
                INSERT INTO admissions.pg_research_supervisor (research_id, person_id, name, role, is_external)
                VALUES (:r, :p, :n, :role, :ext)
                """)
                .param("r", id).param("p", body.personId()).param("n", body.name().trim())
                .param("role", role).param("ext", Boolean.TRUE.equals(body.external()))
                .update();
        jdbc.sql("UPDATE admissions.pg_research SET stage = 'SUPERVISED', updated_at = now() WHERE id = :id AND stage = 'REGISTERED'")
                .param("id", id).update();
        event(id, "SUPERVISED", body.name().trim() + " assigned as " + role.toLowerCase() + " supervisor", null);
        return detail(id);
    }

    public record PanelIn(@NotBlank @Size(max = 200) String name, @NotBlank String role, Boolean external) {
    }

    /** add a member to the panel of examiners (Policy 24.3): chair, external, supervisor(s), internal, PGSR, coordinator */
    @PostMapping("/{id}/panel-member")
    @PreAuthorize(SCHOOL)
    @Transactional
    Map<String, Object> addPanelMember(@PathVariable UUID id, @Valid @RequestBody PanelIn body) {
        stageOrThrow(id);
        String role = body.role().trim().toUpperCase();
        if (!List.of("CHAIR", "EXTERNAL", "SUPERVISOR", "CO_SUPERVISOR", "INTERNAL", "PGSR", "COORDINATOR").contains(role)) {
            throw new DomainRuleViolation("PG_PANEL_ROLE", "'" + role + "' is not a panel role.",
                    new DomainRuleViolation.Remedy("Chair, external, supervisor, co-supervisor, internal, PGSR or coordinator.", "School of Postgraduate Studies"));
        }
        jdbc.sql("INSERT INTO admissions.pg_research_panel (research_id, name, role, is_external) VALUES (:r, :n, :role, :ext)")
                .param("r", id).param("n", body.name().trim()).param("role", role).param("ext", Boolean.TRUE.equals(body.external()))
                .update();
        event(id, "PANEL_CONSTITUTED", body.name().trim() + " added to the panel (" + role.toLowerCase().replace('_', ' ') + ")", null);
        return detail(id);
    }

    public record ActionIn(@NotBlank String action, @Size(max = 1000) String note, @Size(max = 200) String pgsr,
                           BigDecimal plagiarismPct, BigDecimal vivaScore, @Size(max = 20) String vivaOutcome,
                           String correctionsDue, @Size(max = 120) String senateMinute, @Size(max = 9) String session) {
    }

    /** the stage each desk action follows from — the policy's order, held on the record rather than on the menu */
    private static final Map<String, Set<String>> FROM = Map.ofEntries(
            Map.entry("SUBMIT_PROPOSAL", Set.of("REGISTERED", "SUPERVISED")),
            Map.entry("APPROVE_PROPOSAL", Set.of("PROPOSAL_SUBMITTED")),
            Map.entry("SEMINAR", Set.of("PROPOSAL_APPROVED")),
            Map.entry("REGISTER_TITLE", Set.of("SEMINAR_HELD")),
            Map.entry("PANEL", Set.of("TITLE_REGISTERED")),
            Map.entry("DRAFT", Set.of("TITLE_REGISTERED", "PANEL_CONSTITUTED")),
            Map.entry("VIVA", Set.of("DRAFT_SUBMITTED", "CORRECTIONS")),
            Map.entry("CORRECTIONS", Set.of("VIVA_HELD")),
            Map.entry("FINAL", Set.of("VIVA_HELD", "CORRECTIONS")),
            Map.entry("CLEAR", Set.of("FINAL_SUBMITTED")),
            Map.entry("RECOMMEND", Set.of("CLEARED")),
            Map.entry("AWARD", Set.of("AWARD_RECOMMENDED")));
    private static final Map<String, String> STAGE_WORDS = Map.ofEntries(
            Map.entry("REGISTERED", "registered"), Map.entry("SUPERVISED", "supervised"), Map.entry("PROPOSAL_SUBMITTED", "proposal submitted"),
            Map.entry("PROPOSAL_APPROVED", "proposal approved"), Map.entry("SEMINAR_HELD", "seminar held"), Map.entry("TITLE_REGISTERED", "title registered"),
            Map.entry("PANEL_CONSTITUTED", "panel constituted"), Map.entry("DRAFT_SUBMITTED", "draft submitted"), Map.entry("VIVA_HELD", "viva held"),
            Map.entry("CORRECTIONS", "corrections"), Map.entry("FINAL_SUBMITTED", "final submitted"), Map.entry("CLEARED", "cleared"),
            Map.entry("AWARD_RECOMMENDED", "recommended to Senate"), Map.entry("AWARDED", "awarded"), Map.entry("WITHDRAWN", "withdrawn"));

    /**
     * Advance a candidate through the pipeline. One endpoint, one action at a time, each setting its stage
     * and milestone and writing the log. The actions follow the policy's stages; the School desk drives them.
     */
    @PostMapping("/{id}/action")
    @PreAuthorize(SCHOOL)
    @Transactional
    Map<String, Object> action(@PathVariable UUID id, @Valid @RequestBody ActionIn body) {
        String current = stageOrThrow(id);
        String a = body.action().trim().toUpperCase();
        String note = body.note() == null || body.note().isBlank() ? null : body.note().trim();
        Set<String> from = FROM.get(a);
        if (from != null && !from.contains(current)) {
            String need = String.join(" or ", from.stream().map(x -> STAGE_WORDS.getOrDefault(x, x)).toList());
            throw new DomainRuleViolation("PG_STAGE_ORDER", "This record is at '" + STAGE_WORDS.getOrDefault(current, current) + "'; "
                    + a.toLowerCase().replace('_', ' ') + " follows '" + need + "'.",
                    new DomainRuleViolation.Remedy("Record the earlier step first; the stages run in the policy's order.", "School of Postgraduate Studies"));
        }
        if ("AWARDED".equals(current) && !"AWARD".equals(a)) {
            throw new DomainRuleViolation("PG_AWARDED", "The award is recorded; nothing further is done on this record.",
                    new DomainRuleViolation.Remedy("A change after the award is a matter for Senate.", "School of Postgraduate Studies"));
        }
        switch (a) {
            case "SUBMIT_PROPOSAL" -> set(id, "PROPOSAL_SUBMITTED", "proposal_submitted_at", "Proposal submitted", note);
            case "APPROVE_PROPOSAL" -> set(id, "PROPOSAL_APPROVED", "proposal_approved_at", "Proposal approved by the Board", note);
            case "SEMINAR" -> {
                jdbc.sql("UPDATE admissions.pg_research SET stage='SEMINAR_HELD', seminar_held_at=now(), pgsr=:pgsr, updated_at=now() WHERE id=:id")
                        .param("pgsr", body.pgsr() == null || body.pgsr().isBlank() ? null : body.pgsr().trim(), java.sql.Types.VARCHAR)
                        .param("id", id).update();
                event(id, "SEMINAR_HELD", "Research seminar held" + (body.pgsr() != null && !body.pgsr().isBlank() ? " · PGSR " + body.pgsr().trim() : ""), note);
            }
            case "REGISTER_TITLE" -> {
                if (body.plagiarismPct() == null) {
                    throw new DomainRuleViolation("PG_PLAGIARISM", "Record the plagiarism-check originality before registering the title.",
                            new DomainRuleViolation.Remedy("Enter the originality percentage (Policy 23.4 requires 75–85%).", "School of Postgraduate Studies"));
                }
                jdbc.sql("UPDATE admissions.pg_research SET stage='TITLE_REGISTERED', title_registered_at=now(), plagiarism_pct=:p, updated_at=now() WHERE id=:id")
                        .param("p", body.plagiarismPct()).param("id", id).update();
                event(id, "TITLE_REGISTERED", "Title registered · originality " + body.plagiarismPct().toPlainString() + "%", note);
            }
            case "PANEL" -> set(id, "PANEL_CONSTITUTED", "panel_constituted_at", "Panel of examiners constituted", note);
            case "DRAFT" -> set(id, "DRAFT_SUBMITTED", "draft_submitted_at", "Draft submitted for examination", note);
            case "VIVA" -> {
                if (body.vivaScore() == null || body.vivaOutcome() == null || body.vivaOutcome().isBlank()) {
                    throw new DomainRuleViolation("PG_VIVA", "Record the viva score and outcome.",
                            new DomainRuleViolation.Remedy("Enter the panel's score and the outcome.", "School of Postgraduate Studies"));
                }
                String outcome = body.vivaOutcome().trim().toUpperCase();
                if (!List.of("PASS_CLEAN", "PASS_MINOR", "PASS_MAJOR", "SECOND_ORAL", "FAIL").contains(outcome)) {
                    throw new DomainRuleViolation("PG_VIVA_OUTCOME", "'" + outcome + "' is not a viva outcome.",
                            new DomainRuleViolation.Remedy("PASS_CLEAN, PASS_MINOR, PASS_MAJOR, SECOND_ORAL or FAIL.", "School of Postgraduate Studies"));
                }
                String grade = vivaGrade(body.vivaScore());
                jdbc.sql("UPDATE admissions.pg_research SET stage='VIVA_HELD', viva_held_at=now(), viva_score=:s, viva_grade=:g, viva_outcome=:o, updated_at=now() WHERE id=:id")
                        .param("s", body.vivaScore()).param("g", grade).param("o", outcome).param("id", id).update();
                event(id, "VIVA_HELD", "Viva held · " + body.vivaScore().toPlainString() + "% (" + grade + ") · " + outcome, note);
            }
            case "CORRECTIONS" -> {
                jdbc.sql("UPDATE admissions.pg_research SET stage='CORRECTIONS', corrections_due=:d::date, updated_at=now() WHERE id=:id")
                        .param("d", body.correctionsDue() == null || body.correctionsDue().isBlank() ? null : body.correctionsDue().trim(), java.sql.Types.VARCHAR)
                        .param("id", id).update();
                event(id, "CORRECTIONS", "Corrections required" + (body.correctionsDue() != null && !body.correctionsDue().isBlank() ? " · due " + body.correctionsDue().trim() : ""), note);
            }
            case "FINAL" -> set(id, "FINAL_SUBMITTED", "final_submitted_at", "Final bound copies submitted", note);
            case "CLEAR" -> set(id, "CLEARED", "cleared_at", "Cleared by the Secretary before binding", note);
            case "RECOMMEND" -> set(id, "AWARD_RECOMMENDED", "award_recommended_at", "Recommended by the School Board to Senate", note);
            case "AWARD" -> {
                if (body.senateMinute() == null || body.senateMinute().isBlank()) {
                    throw new DomainRuleViolation("PG_AWARD_MINUTE", "An award is recorded on a Senate minute.",
                            new DomainRuleViolation.Remedy("Cite the minute of the Senate that approved the award.", "School of Postgraduate Studies"));
                }
                // the award ends on the register: the graduand written, the student GRADUATED, the candidate told (V255)
                jdbc.sql("SELECT admissions.pg_award(:id, :m, :s)").param("id", id).param("m", body.senateMinute().trim())
                        .param("s", body.session() == null || body.session().isBlank() ? null : body.session().trim(), java.sql.Types.VARCHAR).query(UUID.class).single();
                if (note != null) event(id, "AWARDED", "Note", note);
            }
            case "WITHDRAW" -> {
                jdbc.sql("UPDATE admissions.pg_research SET stage='WITHDRAWN', updated_at=now() WHERE id=:id").param("id", id).update();
                event(id, "WITHDRAWN", "Withdrawn from the programme", note);
            }
            default -> throw new DomainRuleViolation("PG_ACTION", "'" + a + "' is not a research action.",
                    new DomainRuleViolation.Remedy("Use one of the desk's actions.", "Directorate of ICT"));
        }
        return detail(id);
    }

    /* ── helpers ──────────────────────────────────────────────────────────── */

    private static String vivaGrade(BigDecimal score) {
        double v = score.doubleValue();
        return v >= 70 ? "A" : v >= 60 ? "B" : v >= 50 ? "C" : "F";
    }

    private void set(UUID id, String stage, String tsColumn, String eventText, String note) {
        jdbc.sql("UPDATE admissions.pg_research SET stage = :st, " + tsColumn + " = coalesce(" + tsColumn + ", now()), updated_at = now() WHERE id = :id")
                .param("st", stage).param("id", id).update();
        event(id, stage, eventText, note);
    }

    private void event(UUID id, String stage, String text, String note) {
        String full = note == null ? text : text + " — " + note;
        jdbc.sql("INSERT INTO admissions.pg_research_event (research_id, stage, note) VALUES (:r, :s, :n)")
                .param("r", id).param("s", stage).param("n", full).update();
    }

    private String stageOrThrow(UUID id) {
        return jdbc.sql("SELECT stage FROM admissions.pg_research WHERE id = :id").param("id", id).query(String.class).optional()
                .orElseThrow(() -> new NotFound("research record", id));
    }

    /* ── the candidate's documents: proposal, seminar paper, plagiarism report, draft, corrected draft, final copy —
          each kept by version, never replaced (V255). The candidate submits their own; the desk reads, accepts or
          returns each; a draft or final copy submitted moves the stage as the policy has it. ── */

    static final Set<String> DOC_KINDS = Set.of("PROPOSAL", "SEMINAR_PAPER", "PLAGIARISM_REPORT", "DRAFT", "CORRECTED", "FINAL", "OTHER");
    static final Set<String> DOC_TYPES = Set.of("application/pdf", "application/vnd.openxmlformats-officedocument.wordprocessingml.document");
    static final long DOC_MAX = 25L * 1024 * 1024;

    public record DocumentIn(@NotBlank @Size(max = 30) String kind, @NotBlank @Size(max = 200) String filename, @NotBlank String contentType,
                             @NotBlank @Size(max = 36_000_000) String contentBase64, @Size(max = 600) String note) {
    }

    /** the candidate submits a document on their own research */
    @PostMapping("/me/documents")
    @PreAuthorize(STUDENT)
    @Transactional
    Map<String, Object> submitDocument(Authentication authentication, @Valid @RequestBody DocumentIn body) {
        UUID student = UUID.fromString(authentication.getName());
        UUID id = jdbc.sql("SELECT admissions.pg_research_ensure(:s)").param("s", student).query(UUID.class).single();
        String stage = stageOrThrow(id);
        String kind = body.kind().trim().toUpperCase();
        if (!DOC_KINDS.contains(kind)) {
            throw new DomainRuleViolation("PG_DOC_KIND", "'" + kind + "' is not a kind of research document.",
                    new DomainRuleViolation.Remedy("Proposal, seminar paper, plagiarism report, draft, corrected draft, final copy or other.", "You"));
        }
        if ("AWARDED".equals(stage) || "WITHDRAWN".equals(stage)) {
            throw new DomainRuleViolation("PG_DOC_CLOSED", "The record is closed; no further document is taken on it.",
                    new DomainRuleViolation.Remedy("Write to the School of Postgraduate Studies.", "School of Postgraduate Studies"));
        }
        if ("DRAFT".equals(kind) && !Set.of("TITLE_REGISTERED", "PANEL_CONSTITUTED").contains(stage)) {
            throw new DomainRuleViolation("PG_DRAFT_EARLY", "The draft is submitted for examination once your title is registered.",
                    new DomainRuleViolation.Remedy("Your research desk shows the step you are at.", "You"));
        }
        if ("FINAL".equals(kind) && !Set.of("VIVA_HELD", "CORRECTIONS").contains(stage)) {
            throw new DomainRuleViolation("PG_FINAL_EARLY", "The final copy is submitted after the oral examination.",
                    new DomainRuleViolation.Remedy("Your research desk shows the step you are at.", "You"));
        }
        if ("CORRECTED".equals(kind) && !"CORRECTIONS".equals(stage)) {
            throw new DomainRuleViolation("PG_CORRECTED_EARLY", "A corrected copy is submitted when the panel has asked for corrections.",
                    new DomainRuleViolation.Remedy("Your research desk shows the step you are at.", "You"));
        }
        UUID docId = storeDocument(id, kind, body, true, student);
        switch (kind) {
            case "DRAFT" -> set(id, "DRAFT_SUBMITTED", "draft_submitted_at", "Draft submitted for examination by the candidate", null);
            case "FINAL" -> set(id, "FINAL_SUBMITTED", "final_submitted_at", "Final copy submitted by the candidate", null);
            case "CORRECTED" -> event(id, "CORRECTIONS", "Corrected copy submitted by the candidate", null);
            case "PROPOSAL" -> event(id, stage, "Proposal document submitted (version " + versionOf(docId) + ")", null);
            default -> event(id, stage, kind.toLowerCase().replace('_', ' ') + " submitted (version " + versionOf(docId) + ")", null);
        }
        return detail(id);
    }

    /** the candidate reads one of their own documents back */
    @GetMapping("/me/documents/{docId}/content")
    @PreAuthorize(STUDENT)
    @Transactional(readOnly = true)
    ResponseEntity<byte[]> myDocument(Authentication authentication, @PathVariable UUID docId) {
        UUID student = UUID.fromString(authentication.getName());
        Map<String, Object> d = jdbc.sql("""
                SELECT d.filename, d.content_type, b.bytes AS content FROM admissions.pg_research_document d
                  JOIN admissions.pg_research_document_blob b ON b.document_id = d.id
                  JOIN admissions.pg_research r ON r.id = d.research_id
                 WHERE d.id = :d AND r.student_id = :s
                """).param("d", docId).param("s", student).query().listOfRows().stream().findFirst().orElseThrow(() -> new NotFound("document", docId));
        return serve(d);
    }

    /** the desk reads a candidate's document */
    @GetMapping("/{id}/documents/{docId}/content")
    @PreAuthorize(SCHOOL)
    @Transactional(readOnly = true)
    ResponseEntity<byte[]> deskDocument(@PathVariable UUID id, @PathVariable UUID docId) {
        Map<String, Object> d = jdbc.sql("""
                SELECT d.filename, d.content_type, b.bytes AS content FROM admissions.pg_research_document d
                  JOIN admissions.pg_research_document_blob b ON b.document_id = d.id
                 WHERE d.id = :d AND d.research_id = :r
                """).param("d", docId).param("r", id).query().listOfRows().stream().findFirst().orElseThrow(() -> new NotFound("document", docId));
        return serve(d);
    }

    public record ReviewIn(@NotBlank @Size(max = 12) String status, @Size(max = 1000) String note) {
    }

    /** the desk accepts or returns a document the candidate submitted; the version stays on the record either way */
    @PostMapping("/{id}/documents/{docId}/review")
    @PreAuthorize(SCHOOL)
    @Transactional
    Map<String, Object> review(@PathVariable UUID id, @PathVariable UUID docId, @Valid @RequestBody ReviewIn body) {
        stageOrThrow(id);
        String status = body.status().trim().toUpperCase();
        if (!Set.of("ACCEPTED", "RETURNED").contains(status)) {
            throw new DomainRuleViolation("PG_DOC_REVIEW", "A document is accepted or returned.", new DomainRuleViolation.Remedy("Choose one.", "School of Postgraduate Studies"));
        }
        int n = jdbc.sql("""
                UPDATE admissions.pg_research_document SET status = :st, reviewer_note = :n, reviewed_by = :by, reviewed_at = now()
                 WHERE id = :d AND research_id = :r
                """).param("st", status).param("n", body.note() == null || body.note().isBlank() ? null : body.note().trim(), java.sql.Types.VARCHAR)
                .param("by", AuditContextHolder.required().actorId()).param("d", docId).param("r", id).update();
        if (n == 0) throw new NotFound("document", docId);
        Map<String, Object> d = jdbc.sql("SELECT kind, version FROM admissions.pg_research_document WHERE id = :d").param("d", docId).query().singleRow();
        event(id, stageOrThrow(id), String.valueOf(d.get("kind")).toLowerCase().replace('_', ' ') + " version " + d.get("version") + " " + status.toLowerCase(),
                body.note() == null || body.note().isBlank() ? null : body.note().trim());
        return detail(id);
    }

    private UUID storeDocument(UUID research, String kind, DocumentIn body, boolean byCandidate, UUID who) {
        byte[] bytes;
        try {
            bytes = Base64.getDecoder().decode(body.contentBase64());
        } catch (IllegalArgumentException notBase64) {
            throw new DomainRuleViolation("PG_DOC_BAD", "The file could not be read.", new DomainRuleViolation.Remedy("Attach it again.", "You"));
        }
        if (bytes.length == 0 || bytes.length > DOC_MAX) {
            throw new DomainRuleViolation("PG_DOC_SIZE", "A research document is between 1 byte and 25 MB.", new DomainRuleViolation.Remedy("Attach a smaller file.", "You"));
        }
        String type = body.contentType().trim().toLowerCase();
        boolean pdf = bytes.length >= 5 && bytes[0] == '%' && bytes[1] == 'P' && bytes[2] == 'D' && bytes[3] == 'F' && bytes[4] == '-';
        boolean zip = bytes.length >= 4 && bytes[0] == 'P' && bytes[1] == 'K' && (bytes[2] == 3 || bytes[2] == 5 || bytes[2] == 7);
        if (!DOC_TYPES.contains(type) || ("application/pdf".equals(type) ? !pdf : !zip)) {
            throw new DomainRuleViolation("PG_DOC_TYPE", "A research document is a PDF or a Word (.docx) file, and its contents must be what its name says.",
                    new DomainRuleViolation.Remedy("Attach the PDF or Word file.", "You"));
        }
        UUID id = UUID.randomUUID();
        jdbc.sql("""
                INSERT INTO admissions.pg_research_document (id, research_id, kind, version, filename, content_type, size_bytes, note, by_candidate, uploaded_by)
                VALUES (:id, :r, :k, admissions.pg_research_next_version(:r, :k), :f, :t, :n, :note, :bc, :who)
                """).param("id", id).param("r", research).param("k", kind).param("f", body.filename().trim().replaceAll("[\\\\/\\r\\n\\t]", "_"))
                .param("t", type).param("n", bytes.length).param("note", body.note() == null || body.note().isBlank() ? null : body.note().trim(), java.sql.Types.VARCHAR)
                .param("bc", byCandidate).param("who", who, java.sql.Types.OTHER).update();
        jdbc.sql("INSERT INTO admissions.pg_research_document_blob (document_id, bytes) VALUES (:id, :b)").param("id", id).param("b", bytes).update();
        return id;
    }

    private int versionOf(UUID docId) {
        return jdbc.sql("SELECT version FROM admissions.pg_research_document WHERE id = :d").param("d", docId).query(Integer.class).single();
    }

    private static ResponseEntity<byte[]> serve(Map<String, Object> r) {
        String type = String.valueOf(r.get("content_type"));
        ContentDisposition cd = ("application/pdf".equals(type) ? ContentDisposition.inline() : ContentDisposition.attachment())
                .filename(String.valueOf(r.get("filename")), StandardCharsets.UTF_8).build();
        return ResponseEntity.ok().contentType(MediaType.parseMediaType(type)).cacheControl(CacheControl.noStore())
                .header("Content-Disposition", cd.toString()).header("X-Content-Type-Options", "nosniff").header("Content-Security-Policy", "sandbox")
                .body((byte[]) r.get("content"));
    }

    private Map<String, Object> detail(UUID id) {
        List<Map<String, Object>> found = jdbc.sql("""
                SELECT r.*, s.matric_no, s.admission_no, s.surname, s.other_names, s.entry_session, s.entry_level,
                       g.name AS programme_name, g.pg_award, f.name AS faculty_name, d.name AS department_name
                  FROM admissions.pg_research r
                  JOIN people.student s ON s.id = r.student_id
                  JOIN ref.programme g ON g.code = s.programme_code
                  JOIN ref.faculty f ON f.code = g.faculty_code
                  JOIN ref.department d ON d.code = g.dept_code
                 WHERE r.id = :id
                """).param("id", id).query().listOfRows();
        if (found.isEmpty()) {
            throw new NotFound("research record", id);
        }
        Map<String, Object> r = found.get(0);
        List<Map<String, Object>> supervisors = jdbc.sql("""
                SELECT name, role, is_external, assigned_at FROM admissions.pg_research_supervisor
                 WHERE research_id = :id AND ended_at IS NULL ORDER BY role
                """).param("id", id).query().listOfRows();
        List<Map<String, Object>> events = jdbc.sql("""
                SELECT stage, note, at FROM admissions.pg_research_event
                 WHERE research_id = :id ORDER BY at DESC LIMIT 50
                """).param("id", id).query().listOfRows();
        List<Map<String, Object>> panel = jdbc.sql("""
                SELECT name, role, is_external FROM admissions.pg_research_panel
                 WHERE research_id = :id ORDER BY CASE role WHEN 'CHAIR' THEN 0 WHEN 'EXTERNAL' THEN 1
                        WHEN 'SUPERVISOR' THEN 2 WHEN 'CO_SUPERVISOR' THEN 3 WHEN 'INTERNAL' THEN 4
                        WHEN 'PGSR' THEN 5 ELSE 6 END, name
                """).param("id", id).query().listOfRows();
        List<Map<String, Object>> documents = jdbc.sql("""
                SELECT d.id, d.kind, d.version, d.filename, d.content_type, d.size_bytes, d.note, d.status, d.reviewer_note, d.reviewed_at,
                       d.by_candidate, d.uploaded_at
                  FROM admissions.pg_research_document d WHERE d.research_id = :id ORDER BY d.uploaded_at DESC
                """).param("id", id).query().listOfRows();
        Map<String, Object> out = new LinkedHashMap<>(r);
        out.put("name", r.get("surname") + ", " + r.get("other_names"));
        out.put("supervisors", supervisors);
        out.put("panel", panel);
        out.put("events", events);
        out.put("documents", documents);
        return out;
    }
}
