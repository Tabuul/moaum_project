package ng.edu.moaum.portal.hostel;

import java.math.BigDecimal;
import java.sql.Types;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.OffsetDateTime;
import java.time.ZoneId;
import java.time.format.DateTimeParseException;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
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
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * Hostel discipline (FR-HST-008) and the room swap (FR-HST-006), V291. An incident is reported against a student by the
 * housing desk, Student Services or the Dean of Student Affairs; the student answers it; the Dean dismisses it or decides a
 * sanction — a warning, a fine paid through the Bursary, loss of accommodation with a bar until a date, or another measure;
 * the student appeals once and the Dean upholds, varies or quashes. Two occupants swap beds: one proposes, the other agrees,
 * the Dean approves and both beds move at once. Every rule is the database's (hostel.impose_sanction, hostel.swap_check and
 * the rest); this controller finds the student, reads the session and passes the words through.
 */
@RestController
@PreAuthorize("isAuthenticated()")
class HostelDisciplineController {

    /** who may report an incident and decide a swap: the hostel's offices */
    static final String DESK = "hasAnyAuthority('OFFICE_dsa','OFFICE_services','OFFICE_housing','OFFICE_registrar','OFFICE_admin','OFFICE_super')";
    /** who decides a sanction, an appeal or a waiver: the Dean of Student Affairs and those above; not the housing desk */
    static final String DISCIPLINE = "hasAnyAuthority('OFFICE_dsa','OFFICE_services','OFFICE_registrar','OFFICE_admin','OFFICE_super')";
    static final String READERS = "hasAnyAuthority('OFFICE_dsa','OFFICE_services','OFFICE_housing','OFFICE_bursar','OFFICE_registrar','OFFICE_dregistrar','OFFICE_admin','OFFICE_super','OFFICE_audit','OFFICE_deputyaudit','OFFICE_vc','OFFICE_dvc')";
    static final String STUDENT = "hasAuthority('OFFICE_student')";
    private static final ZoneId LAGOS = ZoneId.of("Africa/Lagos");

    private final JdbcClient jdbc;

    HostelDisciplineController(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    private static UUID student(Authentication auth) {
        return UUID.fromString(auth.getName());
    }

    private static String ses(String s, String y) {
        return s + "/" + y;
    }

    private static String blank(String v) {
        return v == null || v.isBlank() ? null : v.trim();
    }

    private static String upper(String v) {
        return blank(v) == null ? null : v.trim().toUpperCase();
    }

    /** the session a student stands in (V289): their entry session while it is planned, else the current one */
    private String studentSession(UUID me, String asked) {
        if (blank(asked) != null) return asked.trim();
        return jdbc.sql("SELECT session FROM people.academic_context(:s)").param("s", me).query(String.class).optional()
                .orElseGet(() -> jdbc.sql("SELECT name FROM policy.academic_session WHERE state = 'CURRENT'").query(String.class).optional().orElse("2026/2027"));
    }

    private UUID studentByNumber(String number) {
        return jdbc.sql("SELECT id FROM people.student WHERE upper(matric_no) = upper(:n) OR upper(admission_no) = upper(:n) LIMIT 1").param("n", number.trim())
                .query(UUID.class).optional().orElseThrow(() -> new NotFound("student", number.trim()));
    }

    /** the register's sanctions arrive as jsonb; they leave as a list the browser reads without parsing a string */
    @SuppressWarnings("unchecked")
    private static List<Map<String, Object>> withSanctions(List<Map<String, Object>> rows) {
        tools.jackson.databind.ObjectMapper json = new tools.jackson.databind.ObjectMapper();
        List<Map<String, Object>> out = new ArrayList<>(rows.size());
        for (Map<String, Object> r : rows) {
            Map<String, Object> m = new LinkedHashMap<>(r);
            Object raw = m.remove("sanctions_json");
            m.put("sanctions", raw == null ? List.of() : json.readValue(String.valueOf(raw), List.class));
            out.add(m);
        }
        return out;
    }

    /* ── the desk: the register, the report, the decision ────────────────── */

    @GetMapping("/api/v1/hostel/incident-kinds")
    @PreAuthorize(READERS)
    List<Map<String, Object>> kinds() {
        return jdbc.sql("SELECT code, label, active FROM hostel.incident_kind ORDER BY ord, label").query().listOfRows();
    }

    public record KindIn(@NotBlank @Size(max = 30) String code, @NotBlank @Size(max = 120) String label, Boolean active) {
    }

    /** a kind of incident added or retired by the Dean; none is removed */
    @PutMapping("/api/v1/hostel/incident-kinds")
    @PreAuthorize(DISCIPLINE)
    @Transactional
    Map<String, Object> saveKind(@Valid @RequestBody KindIn body) {
        String code = body.code().trim().toUpperCase().replaceAll("[^A-Z0-9_]", "_");
        jdbc.sql("""
                INSERT INTO hostel.incident_kind (code, label, active) VALUES (:c, :l, :a)
                ON CONFLICT (code) DO UPDATE SET label = EXCLUDED.label, active = EXCLUDED.active
                """).param("c", code).param("l", body.label().trim()).param("a", body.active() == null || body.active()).update();
        return Map.of("code", code);
    }

    /** every incident of the session, with the student's account, each sanction and its appeal, and the figures the desk works from */
    @GetMapping("/api/v1/hostel/sessions/{s}/{y}/discipline")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> register(@PathVariable String s, @PathVariable String y, @RequestParam(required = false) String state) {
        String session = ses(s, y);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("session", session);
        out.put("incidents", withSanctions(jdbc.sql("""
                SELECT d.incident_id, d.reference, d.session, d.student_id, d.student_name, d.student_number, d.sex, d.programme, d.hall_name, d.block, d.room_no,
                       d.kind, d.kind_label, d.occurred_at, d.place, d.description, d.witnesses, d.reported_by, d.reported_office, d.reported_at,
                       d.statement, d.statement_at, d.state, d.decided_at, d.decision_note, d.prior_incidents, d.sanctions::text AS sanctions_json
                  FROM hostel.discipline_register(:s) d WHERE (:st::text IS NULL OR d.state = :st)
                """).param("s", session).param("st", upper(state), Types.VARCHAR).query().listOfRows()));
        out.put("counts", jdbc.sql("""
                SELECT count(*) FILTER (WHERE i.state = 'REPORTED') AS reported,
                       count(*) FILTER (WHERE i.state = 'SANCTIONED') AS sanctioned,
                       count(*) FILTER (WHERE i.state = 'DISMISSED') AS dismissed,
                       (SELECT count(*) FROM hostel.sanction x WHERE x.session = :s AND x.appeal_state = 'LODGED') AS appeals_waiting,
                       (SELECT coalesce(sum(x.amount), 0) FROM hostel.sanction x WHERE x.session = :s AND x.kind = 'FINE' AND x.state = 'IN_FORCE' AND x.settled_at IS NULL AND x.waived_at IS NULL) AS fines_outstanding,
                       (SELECT count(DISTINCT x.student_id) FROM hostel.sanction x WHERE x.kind = 'EVICTION' AND x.state = 'IN_FORCE' AND x.barred_until >= current_date) AS barred
                  FROM hostel.incident i WHERE i.session = :s
                """).param("s", session).query().singleRow());
        out.put("kinds", kinds());
        return out;
    }

    public record IncidentIn(@NotBlank @Size(max = 40) String studentNumber, @NotBlank @Size(max = 30) String kind, @Size(max = 25) String occurredAt,
                             @Size(max = 200) String place, @NotBlank @Size(max = 4000) String description, @Size(max = 1000) String witnesses) {
    }

    /** an incident reported against a student: the stay it happened in attached, the student told and invited to answer */
    @PostMapping("/api/v1/hostel/sessions/{s}/{y}/incidents")
    @PreAuthorize(DESK)
    @Transactional
    Map<String, Object> report(@PathVariable String s, @PathVariable String y, @Valid @RequestBody IncidentIn body) {
        String session = ses(s, y);
        UUID st = studentByNumber(body.studentNumber());
        OffsetDateTime when = null;
        if (blank(body.occurredAt()) != null) {
            try {
                String v = body.occurredAt().trim();
                when = v.length() > 16 && (v.endsWith("Z") || v.matches(".*[+-]\\d\\d:\\d\\d$")) ? OffsetDateTime.parse(v) : LocalDateTime.parse(v).atZone(LAGOS).toOffsetDateTime();
            } catch (DateTimeParseException e) {
                throw new DomainRuleViolation("HOSTEL_INCIDENT", "The time of the incident could not be read.", new DomainRuleViolation.Remedy("Give the date and time it happened.", "Dean of Student Affairs"));
            }
        }
        UUID id = jdbc.sql("SELECT hostel.report_incident(:st, :s, :k, :w, :p, :d, :x)").param("st", st).param("s", session).param("k", body.kind().trim().toUpperCase())
                .param("w", when, Types.TIMESTAMP_WITH_TIMEZONE).param("p", blank(body.place()), Types.VARCHAR).param("d", body.description().trim())
                .param("x", blank(body.witnesses()), Types.VARCHAR).query(UUID.class).single();
        return jdbc.sql("SELECT id, reference, state FROM hostel.incident WHERE id = :i").param("i", id).query().singleRow();
    }

    public record NoteIn(@NotBlank @Size(max = 2000) String note) {
    }

    @PostMapping("/api/v1/hostel/incidents/{id}/dismiss")
    @PreAuthorize(DISCIPLINE)
    @Transactional
    Map<String, Object> dismiss(@PathVariable UUID id, @Valid @RequestBody NoteIn body) {
        jdbc.sql("SELECT hostel.dismiss_incident(:i, :n)").param("i", id).param("n", body.note().trim()).query().listOfRows();
        return Map.of("ok", true, "state", "DISMISSED");
    }

    public record SanctionIn(@NotBlank @Size(max = 20) String kind, BigDecimal amount, LocalDate barredUntil, LocalDate vacateBy, @NotBlank @Size(max = 2000) String reason) {
    }

    /** the Dean's sanction: its effect on the stay, the bar and the fine's payment reference are the database's */
    @PostMapping("/api/v1/hostel/incidents/{id}/sanction")
    @PreAuthorize(DISCIPLINE)
    @Transactional
    Map<String, Object> sanction(@PathVariable UUID id, @Valid @RequestBody SanctionIn body) {
        UUID sid = jdbc.sql("SELECT hostel.impose_sanction(:i, :k, :a, :b, :v, :r)").param("i", id).param("k", body.kind().trim().toUpperCase())
                .param("a", body.amount(), Types.NUMERIC).param("b", body.barredUntil(), Types.DATE).param("v", body.vacateBy(), Types.DATE).param("r", body.reason().trim())
                .query(UUID.class).single();
        return jdbc.sql("SELECT id, reference, kind, amount, payment_ref, barred_until, vacate_by, effect, appeal_by FROM hostel.sanction WHERE id = :i").param("i", sid).query().singleRow();
    }

    public record AppealDecisionIn(@NotBlank @Size(max = 20) String decision, BigDecimal amount, LocalDate barredUntil, @NotBlank @Size(max = 2000) String note) {
    }

    @PostMapping("/api/v1/hostel/sanctions/{id}/appeal-decision")
    @PreAuthorize(DISCIPLINE)
    @Transactional
    Map<String, Object> decideAppeal(@PathVariable UUID id, @Valid @RequestBody AppealDecisionIn body) {
        jdbc.sql("SELECT hostel.decide_appeal(:i, :d, :a, :b, :n)").param("i", id).param("d", body.decision().trim().toUpperCase())
                .param("a", body.amount(), Types.NUMERIC).param("b", body.barredUntil(), Types.DATE).param("n", body.note().trim()).query().listOfRows();
        return jdbc.sql("SELECT id, reference, kind, state, amount, barred_until, appeal_state, appeal_note FROM hostel.sanction WHERE id = :i").param("i", id).query().singleRow();
    }

    public record ReasonIn(@NotBlank @Size(max = 1000) String reason) {
    }

    @PostMapping("/api/v1/hostel/sanctions/{id}/waive")
    @PreAuthorize(DISCIPLINE)
    @Transactional
    Map<String, Object> waive(@PathVariable UUID id, @Valid @RequestBody ReasonIn body) {
        jdbc.sql("SELECT hostel.waive_fine(:i, :r)").param("i", id).param("r", body.reason().trim()).query().listOfRows();
        return Map.of("ok", true);
    }

    /* ── the desk: swaps ─────────────────────────────────────────────────── */

    @GetMapping("/api/v1/hostel/sessions/{s}/{y}/swaps")
    @PreAuthorize(READERS)
    List<Map<String, Object>> swaps(@PathVariable String s, @PathVariable String y, @RequestParam(required = false) String state) {
        return jdbc.sql("SELECT * FROM hostel.swaps(:s) w WHERE (:st::text IS NULL OR w.state = :st)").param("s", ses(s, y)).param("st", upper(state), Types.VARCHAR).query().listOfRows();
    }

    public record DecideIn(@NotBlank @Size(max = 20) String decision, @Size(max = 1000) String note) {
    }

    /** approved, both beds move in one transaction after every rule is checked again; rejected, with the reason */
    @PostMapping("/api/v1/hostel/swaps/{id}/decide")
    @PreAuthorize(DESK)
    @Transactional
    Map<String, Object> decideSwap(@PathVariable UUID id, @Valid @RequestBody DecideIn body) {
        jdbc.sql("SELECT hostel.decide_swap(:i, :d, :n)").param("i", id).param("d", body.decision().trim().toUpperCase()).param("n", blank(body.note()), Types.VARCHAR).query().listOfRows();
        return jdbc.sql("SELECT id, reference, state, new_allocation, new_partner_allocation FROM hostel.swap_request WHERE id = :i").param("i", id).query().singleRow();
    }

    /* ── the student: conduct, answer, appeal, pay; swaps ───────────────── */

    /** the student's incidents and sanctions of every session, the swaps they propose or are asked to agree, and any bar in force */
    @GetMapping("/api/v1/me/hostel/conduct")
    @PreAuthorize(STUDENT)
    @Transactional(readOnly = true)
    Map<String, Object> conduct(Authentication auth, @RequestParam(required = false) String session) {
        UUID me = student(auth);
        String s = studentSession(me, session);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("session", s);
        out.put("incidents", jdbc.sql("""
                SELECT i.id, i.reference, i.session, i.kind, k.label AS kind_label, i.occurred_at, i.place, i.description, i.reported_at, i.statement, i.statement_at,
                       i.state, i.decided_at, i.decision_note, h.name AS hall_name, r.block, r.room_no
                  FROM hostel.incident i JOIN hostel.incident_kind k ON k.code = i.kind LEFT JOIN hostel.hall h ON h.code = i.hall_code LEFT JOIN hostel.room r ON r.id = i.room_id
                 WHERE i.student_id = :m ORDER BY i.reported_at DESC
                """).param("m", me).query().listOfRows());
        out.put("sanctions", jdbc.sql("""
                SELECT s.id, s.reference, s.incident_id, i.reference AS incident_ref, s.session, s.kind, s.amount, s.payment_ref, s.settled_at, s.waived_at, s.waived_reason,
                       s.barred_until, s.vacate_by, s.effect, s.reason, s.state, s.decided_at, s.appeal_by, s.appeal_state, s.appeal_ground, s.appealed_at, s.appeal_note, s.appeal_decided_at,
                       (s.state = 'IN_FORCE' AND s.appeal_state IS NULL AND current_date <= s.appeal_by) AS may_appeal,
                       (s.kind = 'FINE' AND s.state = 'IN_FORCE' AND s.settled_at IS NULL AND s.waived_at IS NULL AND coalesce(s.amount, 0) > 0) AS payable
                  FROM hostel.sanction s JOIN hostel.incident i ON i.id = s.incident_id
                 WHERE s.student_id = :m ORDER BY s.decided_at DESC
                """).param("m", me).query().listOfRows());
        out.put("swaps", jdbc.sql("""
                SELECT w.*, CASE WHEN w.student_id = :m THEN 'PROPOSER' ELSE 'PARTNER' END AS role
                  FROM hostel.swaps(:s) w WHERE w.student_id = :m OR w.partner_id = :m
                """).param("m", me).param("s", s).query().listOfRows());
        out.put("bar", jdbc.sql("SELECT coalesce(hostel.discipline_bar(:m, true), '')").param("m", me).query(String.class).optional().map(HostelDisciplineController::blank).orElse(null));
        return out;
    }

    public record StatementIn(@NotBlank @Size(max = 4000) String statement) {
    }

    @PostMapping("/api/v1/me/hostel/incidents/{id}/answer")
    @PreAuthorize(STUDENT)
    @Transactional
    Map<String, Object> answer(Authentication auth, @PathVariable UUID id, @Valid @RequestBody StatementIn body) {
        jdbc.sql("SELECT hostel.answer_incident(:i, :m, :t)").param("i", id).param("m", student(auth)).param("t", body.statement().trim()).query().listOfRows();
        return Map.of("ok", true);
    }

    public record GroundIn(@NotBlank @Size(max = 4000) String ground) {
    }

    @PostMapping("/api/v1/me/hostel/sanctions/{id}/appeal")
    @PreAuthorize(STUDENT)
    @Transactional
    Map<String, Object> appeal(Authentication auth, @PathVariable UUID id, @Valid @RequestBody GroundIn body) {
        jdbc.sql("SELECT hostel.appeal_sanction(:i, :m, :g)").param("i", id).param("m", student(auth)).param("g", body.ground().trim()).query().listOfRows();
        return Map.of("ok", true, "appealState", "LODGED");
    }

    /** the fine's payment reference, the live one or a new one; paid on the Fees page like any other */
    @PostMapping("/api/v1/me/hostel/sanctions/{id}/pay")
    @PreAuthorize(STUDENT)
    @Transactional
    Map<String, Object> pay(Authentication auth, @PathVariable UUID id) {
        UUID me = student(auth);
        BigDecimal amount = jdbc.sql("SELECT amount FROM hostel.sanction WHERE id = :i AND student_id = :m").param("i", id).param("m", me).query(BigDecimal.class).optional()
                .orElseThrow(() -> new NotFound("sanction", id));
        String ref = jdbc.sql("SELECT hostel.fine_reference(:i)").param("i", id).query(String.class).single();
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("reference", ref);
        out.put("amount", amount);
        return out;
    }

    public record SwapIn(String session, @NotBlank @Size(max = 40) String partnerNumber, @NotBlank @Size(max = 1000) String reason) {
    }

    /** a swap proposed to another occupant of the session, named by their number; nothing moves until they agree and the Dean approves */
    @PostMapping("/api/v1/me/hostel/swaps")
    @PreAuthorize(STUDENT)
    @Transactional
    Map<String, Object> propose(Authentication auth, @Valid @RequestBody SwapIn body) {
        UUID me = student(auth);
        String s = studentSession(me, body.session());
        UUID id = jdbc.sql("SELECT hostel.propose_swap(:m, :s, :n, :r)").param("m", me).param("s", s).param("n", body.partnerNumber().trim()).param("r", body.reason().trim())
                .query(UUID.class).single();
        return jdbc.sql("SELECT id, reference, state FROM hostel.swap_request WHERE id = :i").param("i", id).query().singleRow();
    }

    public record SwapAnswerIn(@NotNull Boolean agree, @Size(max = 1000) String note) {
    }

    @PostMapping("/api/v1/me/hostel/swaps/{id}/answer")
    @PreAuthorize(STUDENT)
    @Transactional
    Map<String, Object> answerSwap(Authentication auth, @PathVariable UUID id, @Valid @RequestBody SwapAnswerIn body) {
        jdbc.sql("SELECT hostel.answer_swap(:i, :m, :a, :n)").param("i", id).param("m", student(auth)).param("a", body.agree()).param("n", blank(body.note()), Types.VARCHAR).query().listOfRows();
        return jdbc.sql("SELECT id, reference, state FROM hostel.swap_request WHERE id = :i").param("i", id).query().singleRow();
    }

    @PostMapping("/api/v1/me/hostel/swaps/{id}/cancel")
    @PreAuthorize(STUDENT)
    @Transactional
    Map<String, Object> cancelSwap(Authentication auth, @PathVariable UUID id) {
        jdbc.sql("SELECT hostel.cancel_swap(:i, :m)").param("i", id).param("m", student(auth)).query().listOfRows();
        return Map.of("ok", true, "state", "CANCELLED");
    }
}
