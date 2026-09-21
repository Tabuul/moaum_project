package ng.edu.moaum.portal.pgadmissions;

import java.math.BigDecimal;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

import ng.edu.moaum.portal.shared.DomainRuleViolation;
import ng.edu.moaum.portal.shared.NotFound;

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
                           String correctionsDue) {
    }

    /**
     * Advance a candidate through the pipeline. One endpoint, one action at a time, each setting its stage
     * and milestone and writing the log. The actions follow the policy's stages; the School desk drives them.
     */
    @PostMapping("/{id}/action")
    @PreAuthorize(SCHOOL)
    @Transactional
    Map<String, Object> action(@PathVariable UUID id, @Valid @RequestBody ActionIn body) {
        stageOrThrow(id);
        String a = body.action().trim().toUpperCase();
        String note = body.note() == null || body.note().isBlank() ? null : body.note().trim();
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
            case "AWARD" -> set(id, "AWARDED", "awarded_at", "Award approved by Senate", note);
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

    private void stageOrThrow(UUID id) {
        Long n = jdbc.sql("SELECT count(*) FROM admissions.pg_research WHERE id = :id").param("id", id).query(Long.class).single();
        if (n == 0) {
            throw new NotFound("research record", id);
        }
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
        Map<String, Object> out = new LinkedHashMap<>(r);
        out.put("name", r.get("surname") + ", " + r.get("other_names"));
        out.put("supervisors", supervisors);
        out.put("panel", panel);
        out.put("events", events);
        return out;
    }
}
