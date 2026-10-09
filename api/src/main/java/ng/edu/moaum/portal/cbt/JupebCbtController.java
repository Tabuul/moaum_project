package ng.edu.moaum.portal.cbt;

import java.util.Map;
import java.util.UUID;

import jakarta.servlet.http.HttpServletRequest;
import jakarta.validation.Valid;

import ng.edu.moaum.portal.cbt.CbtCandidateDoor.AnswersIn;
import ng.edu.moaum.portal.cbt.CbtCandidateDoor.CameraIn;
import ng.edu.moaum.portal.cbt.CbtCandidateDoor.EventsIn;
import ng.edu.moaum.portal.cbt.CbtCandidateDoor.Kind;
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
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * V365: the JUPEB student's door to the same CBT engine — the examinations of the subjects they are registered for, the start, the paper,
 * the answers, the reports, the submission and the released result, through the one implementation every candidate shares. The JUPEB
 * portal's token carries the application as its subject; a token whose subject is not a JUPEB application is answered as not found, and a
 * temporary password opens the portal only to change it (V356), so nothing here is written until it is changed.
 */
@RestController
@RequestMapping("/api/v1/jupeb/me/cbt")
@PreAuthorize("hasAuthority('OFFICE_applicant')")
class JupebCbtController {

    private final CbtCandidateDoor door;
    private final JdbcClient jdbc;

    JupebCbtController(CbtCandidateDoor door, JdbcClient jdbc) {
        this.door = door;
        this.jdbc = jdbc;
    }

    /** the signed-in JUPEB candidate, held to the portal's own rule on a temporary password */
    private UUID me(Authentication auth, HttpServletRequest request) {
        UUID id = UUID.fromString(auth.getName());
        Boolean mustChange = jdbc.sql("SELECT coalesce(acc.must_change_password, false) FROM jupeb.application a LEFT JOIN jupeb.account acc ON acc.id = a.account_id WHERE a.id = :id")
                .param("id", id).query(Boolean.class).optional().orElse(null);
        if (mustChange == null) throw new NotFound("JUPEB application", id);
        if (mustChange && !"GET".equalsIgnoreCase(request.getMethod())) {
            throw new DomainRuleViolation("JUPEB_PASSWORD_CHANGE_FIRST", "Choose your own password first: a temporary password only opens the portal to change it.",
                    new DomainRuleViolation.Remedy("Change your password, then carry on.", "You"));
        }
        return id;
    }

    @GetMapping
    @Transactional(readOnly = true)
    Map<String, Object> list(Authentication auth, HttpServletRequest request, @RequestParam(required = false) String session) {
        return door.list(Kind.JUPEB, me(auth, request), session);
    }

    @GetMapping("/exams/{id}")
    @Transactional(readOnly = true)
    Map<String, Object> one(Authentication auth, HttpServletRequest request, @PathVariable UUID id) {
        return door.one(Kind.JUPEB, me(auth, request), id);
    }

    /** V375: the CBT slip — the sitting, the seat and the signed code the invigilator scans at the door */
    @GetMapping("/exams/{id}/slip")
    @Transactional(readOnly = true)
    Map<String, Object> slip(Authentication auth, HttpServletRequest request, @PathVariable UUID id) {
        return door.slip(Kind.JUPEB, me(auth, request), id);
    }

    @PostMapping("/exams/{id}/start")
    @Transactional
    Map<String, Object> start(Authentication auth, HttpServletRequest request, @PathVariable UUID id, @RequestHeader(value = "User-Agent", required = false) String agent) {
        return door.start(Kind.JUPEB, me(auth, request), id, agent);
    }

    @GetMapping("/attempts/{id}")
    @Transactional
    Map<String, Object> attempt(Authentication auth, HttpServletRequest request, @PathVariable UUID id, @RequestHeader(value = "X-Attempt-Token", required = false) String token) {
        return door.attempt(Kind.JUPEB, me(auth, request), id, token);
    }

    @PutMapping("/attempts/{id}/answers")
    @Transactional
    Map<String, Object> answers(Authentication auth, HttpServletRequest request, @PathVariable UUID id, @RequestHeader(value = "X-Attempt-Token", required = false) String token,
                                @Valid @RequestBody AnswersIn in) {
        return door.answers(Kind.JUPEB, me(auth, request), id, token, in);
    }

    @PostMapping("/attempts/{id}/ping")
    @Transactional
    Map<String, Object> ping(Authentication auth, HttpServletRequest request, @PathVariable UUID id, @RequestHeader(value = "X-Attempt-Token", required = false) String token) {
        return door.ping(Kind.JUPEB, me(auth, request), id, token);
    }

    @PostMapping("/attempts/{id}/events")
    @Transactional
    Map<String, Object> events(Authentication auth, HttpServletRequest request, @PathVariable UUID id, @RequestHeader(value = "X-Attempt-Token", required = false) String token,
                               @Valid @RequestBody EventsIn in) {
        return door.events(Kind.JUPEB, me(auth, request), id, token, in);
    }

    @PostMapping("/attempts/{id}/camera")
    @Transactional
    Map<String, Object> camera(Authentication auth, HttpServletRequest request, @PathVariable UUID id, @RequestHeader(value = "X-Attempt-Token", required = false) String token,
                               @Valid @RequestBody CameraIn in) {
        return door.camera(Kind.JUPEB, me(auth, request), id, token, in);
    }

    @PostMapping("/attempts/{id}/submit")
    @Transactional
    Map<String, Object> submit(Authentication auth, HttpServletRequest request, @PathVariable UUID id, @RequestHeader(value = "X-Attempt-Token", required = false) String token) {
        return door.submit(Kind.JUPEB, me(auth, request), id, token);
    }

    @GetMapping("/attempts/{id}/result")
    @Transactional(readOnly = true)
    Map<String, Object> result(Authentication auth, HttpServletRequest request, @PathVariable UUID id) {
        return door.result(Kind.JUPEB, me(auth, request), id);
    }
}
