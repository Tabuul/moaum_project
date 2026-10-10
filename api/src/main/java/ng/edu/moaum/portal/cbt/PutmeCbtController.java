package ng.edu.moaum.portal.cbt;

import java.security.SecureRandom;
import java.sql.Types;
import java.time.Duration;
import java.time.Instant;
import java.time.OffsetDateTime;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import jakarta.servlet.http.HttpServletRequest;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

import ng.edu.moaum.portal.auth.TokenIssuer;
import ng.edu.moaum.portal.cbt.CbtCandidateDoor.AnswersIn;
import ng.edu.moaum.portal.cbt.CbtCandidateDoor.CameraIn;
import ng.edu.moaum.portal.cbt.CbtCandidateDoor.EventsIn;
import ng.edu.moaum.portal.cbt.CbtCandidateDoor.Kind;
import ng.edu.moaum.portal.shared.ClientAddress;
import ng.edu.moaum.portal.shared.DomainRuleViolation;
import ng.edu.moaum.portal.shared.NotFound;
import ng.edu.moaum.portal.shared.Throttle;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.Authentication;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * V385: the Post-UTME candidate's door to the one CBT engine — not the applicant dashboard. The candidate gives their JAMB
 * registration number and the second factor the examination names (the application number, the screening slip's token, the phone
 * they registered with, or the date of birth on record); the database says yes or no and never which part was wrong; a wrong
 * answer counts against the connection (V359). A yes opens a short session of its own office ({@code putmecbt}): the token it
 * carries opens this door and nothing else — not the applicant's dashboard, not the student's. Behind the door the candidate's
 * examinations, the start, the paper, the answers, the browser's reports and the submission go through the one implementation
 * every candidate shares ({@link CbtCandidateDoor}); a result is never given here. The result-checking door is separate and reads
 * only what the Academic Office released, only while the Director of ICT's window is open.
 */
@RestController
@RequestMapping("/api/v1/putme")
class PutmeCbtController {

    private static final String CANDIDATE = "hasAuthority('OFFICE_putmecbt')";
    /** the examination session lasts this long from the door; the attempt's own clock is the server's regardless */
    private static final Duration SESSION_LENGTH = Duration.ofHours(6);
    private static final Map<String, String> FACTOR_WORD = Map.of(
            "APPLICATION_NO", "Application number", "SLIP_TOKEN", "Screening slip code", "PHONE", "Phone number you registered with", "DATE_OF_BIRTH", "Date of birth (yyyy-mm-dd)");

    public record VerifyIn(@Size(max = 9) String session, @NotBlank @Size(max = 40) String jambRegNo, @NotBlank @Size(max = 80) String proof) {
    }

    private final CbtCandidateDoor door;
    private final JdbcClient jdbc;
    private final TokenIssuer issuer;
    private final Throttle throttle;
    private final SecureRandom random = new SecureRandom();

    PutmeCbtController(CbtCandidateDoor door, JdbcClient jdbc, TokenIssuer issuer, Throttle throttle) {
        this.door = door;
        this.jdbc = jdbc;
        this.issuer = issuer;
        this.throttle = throttle;
    }

    /** the admission session the door serves when none is named: the one new Post-UTME applications are filed under today */
    private String sessionOf(String asked) {
        if (asked != null && asked.trim().matches("^\\d{4}/\\d{4}$")) return asked.trim();
        return jdbc.sql("SELECT policy.application_session('POST_UTME_REGISTRATION')").query(String.class).single();
    }

    private Map<String, Object> window(String type, String session) {
        Map<String, Object> w = jdbc.sql("""
                SELECT w.state, w.opens_at, w.closes_at, (SELECT m.message FROM policy.portal_window_message m WHERE m.window_type = :t) AS message
                  FROM policy.window_state(:t, :s, NULL) w
                """).param("t", type).param("s", session).query().singleRow();
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("type", type);
        out.put("state", w.get("state"));
        out.put("open", "OPEN".equals(w.get("state")));
        out.put("opensAt", w.get("opens_at"));
        out.put("closesAt", w.get("closes_at"));
        out.put("message", "OPEN".equals(w.get("state")) ? null : w.get("message"));
        return out;
    }

    /* ── the public face: what the door and the result-checking page say before anyone is verified ── */

    @GetMapping("/cbt/public")
    @Transactional(readOnly = true)
    Map<String, Object> publicState(@RequestParam(required = false) String session) {
        String s = sessionOf(session);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("session", s);
        out.put("cbt", window("POST_UTME_CBT", s));
        out.put("results", window("POST_UTME_RESULT_CHECKING", s));
        String factor = jdbc.sql("SELECT admissions.putme_cbt_factor(:s)").param("s", s).query(String.class).single();
        out.put("factor", factor);
        out.put("factorLabel", FACTOR_WORD.getOrDefault(factor, "Verification"));
        // the examinations of the session as the public may know them: title, when, how long, how many questions — no candidate, no paper
        out.put("exams", jdbc.sql("""
                SELECT e.id, e.title, e.starts_at, e.ends_at, e.duration_minutes, assessment.cbt_live_state(e) AS live_state,
                       CASE WHEN e.selection = 'RANDOM' THEN e.total_questions ELSE (SELECT count(*)::int FROM assessment.cbt_pool(e.id)) END AS questions
                  FROM assessment.cbt_exam e WHERE e.office = 'POST_UTME' AND e.putme_session = :s AND e.state IN ('PUBLISHED', 'CLOSED')
                 ORDER BY e.starts_at
                """).param("s", s).query().listOfRows());
        out.put("now", OffsetDateTime.now());
        return out;
    }

    /** the door: JAMB registration number plus the examination's second factor; one answer for every failure, counted against the connection */
    @PostMapping("/cbt/verify")
    @Transactional
    Map<String, Object> verify(@Valid @RequestBody VerifyIn in, HttpServletRequest request, @RequestHeader(value = "User-Agent", required = false) String agent) {
        String source = ClientAddress.of(request);
        throttle.take(Throttle.Door.APPLICANT_LOOKUP, source);
        String s = sessionOf(in.session());
        Map<String, Object> cbt = window("POST_UTME_CBT", s);
        if (!Boolean.TRUE.equals(cbt.get("open"))) {
            String msg = cbt.get("message") == null ? "The Post-UTME CBT for " + s + " is " + String.valueOf(cbt.get("state")).toLowerCase() + "." : String.valueOf(cbt.get("message"));
            throw new DomainRuleViolation("CBT_PUTME_WINDOW", msg, new DomainRuleViolation.Remedy("The examination opens at the time the University announces.", "Directorate of ICT"));
        }
        UUID app = jdbc.sql("SELECT admissions.putme_cbt_verify(:s, :j, :p)").param("s", s).param("j", in.jambRegNo().trim()).param("p", in.proof().trim())
                .query(UUID.class).optional().orElse(null);
        if (app == null) {
            throttle.count(Throttle.Door.APPLICANT_LOOKUP, source);
            jdbc.sql("INSERT INTO admissions.applicant_event (account_id, identifier, outcome, ip) VALUES (NULL, :i, 'PUTME_CBT_VERIFY_FAILED', :ip)")
                    .param("i", in.jambRegNo().trim().toUpperCase()).param("ip", source, Types.VARCHAR).update();
            throw new DomainRuleViolation("CBT_PUTME_VERIFY", "Candidate verification failed.",
                    new DomainRuleViolation.Remedy("Check the JAMB registration number and the verification detail on your screening slip, then try again.", "You"));
        }
        Map<String, Object> who = jdbc.sql("""
                SELECT a.account_id, a.application_no, upper(c.surname) AS surname, c.other_names, c.jamb_reg_no, c.programme
                  FROM admissions.application a JOIN admissions.candidate c ON c.id = a.candidate_id WHERE a.id = :a
                """).param("a", app).query().singleRow();
        // a session of the candidate's own office, with the application as its person: the token opens this door and no dashboard
        byte[] sid = new byte[32];
        random.nextBytes(sid);
        Instant end = Instant.now().plus(SESSION_LENGTH);
        jdbc.sql("INSERT INTO platform.session (id, person_id, active_office, absolute_end) VALUES (:id, :p, 'putmecbt', :end)")
                .param("id", sid).param("p", app).param("end", end.atOffset(java.time.ZoneOffset.UTC)).update();
        jdbc.sql("INSERT INTO admissions.applicant_event (account_id, identifier, outcome, ip) VALUES (:a, :i, 'PUTME_CBT_VERIFIED', :ip)")
                .param("a", who.get("account_id"), Types.OTHER).param("i", in.jambRegNo().trim().toUpperCase()).param("ip", source, Types.VARCHAR).update();
        String name = who.get("surname") + ", " + who.get("other_names");
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("token", issuer.issue(app, name, List.of("putmecbt"), sid, end));
        out.put("expiresAt", end.atOffset(java.time.ZoneOffset.UTC));
        Map<String, Object> candidate = new LinkedHashMap<>();
        candidate.put("name", name);
        candidate.put("jambRegNo", who.get("jamb_reg_no"));
        candidate.put("applicationNo", who.get("application_no"));
        candidate.put("programme", who.get("programme"));
        out.put("candidate", candidate);
        out.put("session", s);
        out.put("exams", door.list(Kind.PUTME, app, s).get("rows"));
        return out;
    }

    /** the result-checking door: a released score, only while the Director's window is open, only to the verified candidate */
    @PostMapping("/results/check")
    @Transactional(readOnly = true)
    Map<String, Object> checkResult(@Valid @RequestBody VerifyIn in, HttpServletRequest request) {
        String source = ClientAddress.of(request);
        throttle.take(Throttle.Door.VERIFY, source);
        String s = sessionOf(in.session());
        Map<String, Object> r = jdbc.sql("SELECT * FROM admissions.putme_result_check(:s, :j, :p)").param("s", s).param("j", in.jambRegNo().trim()).param("p", in.proof().trim())
                .query().singleRow();
        if ("NOT_VERIFIED".equals(r.get("outcome"))) {
            throttle.count(Throttle.Door.VERIFY, source);
            throw new DomainRuleViolation("CBT_PUTME_VERIFY", "Candidate verification failed.",
                    new DomainRuleViolation.Remedy("Check the JAMB registration number and the verification detail on your screening slip, then try again.", "You"));
        }
        Map<String, Object> out = new LinkedHashMap<>(r);
        out.put("session", s);
        out.put("window", window("POST_UTME_RESULT_CHECKING", s));
        out.put("now", OffsetDateTime.now());
        return out;
    }

    /* ── behind the door: the verified candidate's own examination ── */

    private UUID me(Authentication auth) {
        UUID id = UUID.fromString(auth.getName());
        if (!jdbc.sql("SELECT EXISTS (SELECT 1 FROM admissions.application WHERE id = :id)").param("id", id).query(Boolean.class).single()) {
            throw new NotFound("Post-UTME application", id);
        }
        return id;
    }

    @GetMapping("/cbt")
    @PreAuthorize(CANDIDATE)
    @Transactional(readOnly = true)
    Map<String, Object> list(Authentication auth, @RequestParam(required = false) String session) {
        UUID app = me(auth);
        Map<String, Object> out = new LinkedHashMap<>(door.list(Kind.PUTME, app, session));
        out.put("candidate", jdbc.sql("""
                SELECT upper(c.surname) || ', ' || c.other_names AS name, c.jamb_reg_no AS "jambRegNo", a.application_no AS "applicationNo", c.programme
                  FROM admissions.application a JOIN admissions.candidate c ON c.id = a.candidate_id WHERE a.id = :a
                """).param("a", app).query().singleRow());
        return out;
    }

    @GetMapping("/cbt/exams/{id}")
    @PreAuthorize(CANDIDATE)
    @Transactional(readOnly = true)
    Map<String, Object> one(Authentication auth, @PathVariable UUID id) {
        return door.one(Kind.PUTME, me(auth), id);
    }

    @PostMapping("/cbt/exams/{id}/start")
    @PreAuthorize(CANDIDATE)
    @Transactional
    Map<String, Object> start(Authentication auth, @PathVariable UUID id, @RequestHeader(value = "User-Agent", required = false) String agent) {
        return door.start(Kind.PUTME, me(auth), id, agent);
    }

    @GetMapping("/cbt/attempts/{id}")
    @PreAuthorize(CANDIDATE)
    @Transactional
    Map<String, Object> attempt(Authentication auth, @PathVariable UUID id, @RequestHeader(value = "X-Attempt-Token", required = false) String token) {
        return door.attempt(Kind.PUTME, me(auth), id, token);
    }

    @GetMapping("/cbt/attempts/{id}/images/{image}")
    @PreAuthorize(CANDIDATE)
    @Transactional(readOnly = true)
    org.springframework.http.ResponseEntity<byte[]> image(Authentication auth, @PathVariable UUID id, @PathVariable UUID image,
                                                          @RequestHeader(value = "X-Attempt-Token", required = false) String token) {
        return door.image(Kind.PUTME, me(auth), id, token, image);
    }

    @PutMapping("/cbt/attempts/{id}/answers")
    @PreAuthorize(CANDIDATE)
    @Transactional
    Map<String, Object> answers(Authentication auth, @PathVariable UUID id, @RequestHeader(value = "X-Attempt-Token", required = false) String token, @Valid @RequestBody AnswersIn in) {
        return door.answers(Kind.PUTME, me(auth), id, token, in);
    }

    @PostMapping("/cbt/attempts/{id}/ping")
    @PreAuthorize(CANDIDATE)
    @Transactional
    Map<String, Object> ping(Authentication auth, @PathVariable UUID id, @RequestHeader(value = "X-Attempt-Token", required = false) String token) {
        return door.ping(Kind.PUTME, me(auth), id, token);
    }

    @PostMapping("/cbt/attempts/{id}/events")
    @PreAuthorize(CANDIDATE)
    @Transactional
    Map<String, Object> events(Authentication auth, @PathVariable UUID id, @RequestHeader(value = "X-Attempt-Token", required = false) String token, @Valid @RequestBody EventsIn in) {
        return door.events(Kind.PUTME, me(auth), id, token, in);
    }

    @PostMapping("/cbt/attempts/{id}/camera")
    @PreAuthorize(CANDIDATE)
    @Transactional
    Map<String, Object> camera(Authentication auth, @PathVariable UUID id, @RequestHeader(value = "X-Attempt-Token", required = false) String token, @Valid @RequestBody CameraIn in) {
        return door.camera(Kind.PUTME, me(auth), id, token, in);
    }

    /** the submission: the attempt is scored and stored in the engine; the candidate is told it is submitted, and nothing of the score */
    @PostMapping("/cbt/attempts/{id}/submit")
    @PreAuthorize(CANDIDATE)
    @Transactional
    Map<String, Object> submit(Authentication auth, @PathVariable UUID id, @RequestHeader(value = "X-Attempt-Token", required = false) String token) {
        Map<String, Object> t = door.submit(Kind.PUTME, me(auth), id, token);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("status", t.get("status"));
        out.put("submittedAt", t.get("submittedAt"));
        out.put("now", t.get("now"));
        out.put("message", "EXAM SUBMITTED SUCCESSFULLY. Your result will be processed and released by the University.");
        return out;
    }

    /** V385: the examination door gives no result; the door says so rather than answering nothing */
    @GetMapping("/cbt/attempts/{id}/result")
    @PreAuthorize(CANDIDATE)
    @Transactional(readOnly = true)
    Map<String, Object> result(Authentication auth, @PathVariable UUID id) {
        return door.result(Kind.PUTME, me(auth), id);
    }
}
