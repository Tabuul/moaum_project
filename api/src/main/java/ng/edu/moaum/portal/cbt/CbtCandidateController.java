package ng.edu.moaum.portal.cbt;

import java.util.Map;
import java.util.UUID;

import jakarta.validation.Valid;

import ng.edu.moaum.portal.cbt.CbtCandidateDoor.AnswersIn;
import ng.edu.moaum.portal.cbt.CbtCandidateDoor.CameraIn;
import ng.edu.moaum.portal.cbt.CbtCandidateDoor.EventsIn;
import ng.edu.moaum.portal.cbt.CbtCandidateDoor.Kind;

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
 * The University student's door to the CBT engine (V322): the examinations on the signed-in student's registered courses, the instructions,
 * the start, the paper without its keys, the answers saved as they go, the browser's reports, the submission, and the result once it is
 * released. The candidate is the signed-in student; everything else is the one implementation every candidate shares (CbtCandidateDoor).
 */
@RestController
@RequestMapping("/api/v1/me/cbt")
@PreAuthorize("hasAuthority('OFFICE_student')")
class CbtCandidateController {

    private final CbtCandidateDoor door;

    CbtCandidateController(CbtCandidateDoor door) {
        this.door = door;
    }

    private static UUID me(Authentication auth) {
        return UUID.fromString(auth.getName());
    }

    @GetMapping
    @Transactional(readOnly = true)
    Map<String, Object> list(Authentication auth, @RequestParam(required = false) String session) {
        return door.list(Kind.STUDENT, me(auth), session);
    }

    @GetMapping("/exams/{id}")
    @Transactional(readOnly = true)
    Map<String, Object> one(Authentication auth, @PathVariable UUID id) {
        return door.one(Kind.STUDENT, me(auth), id);
    }

    @PostMapping("/exams/{id}/start")
    @Transactional
    Map<String, Object> start(Authentication auth, @PathVariable UUID id, @RequestHeader(value = "User-Agent", required = false) String agent) {
        return door.start(Kind.STUDENT, me(auth), id, agent);
    }

    @GetMapping("/attempts/{id}")
    @Transactional
    Map<String, Object> attempt(Authentication auth, @PathVariable UUID id, @RequestHeader(value = "X-Attempt-Token", required = false) String token) {
        return door.attempt(Kind.STUDENT, me(auth), id, token);
    }

    @PutMapping("/attempts/{id}/answers")
    @Transactional
    Map<String, Object> answers(Authentication auth, @PathVariable UUID id, @RequestHeader(value = "X-Attempt-Token", required = false) String token, @Valid @RequestBody AnswersIn in) {
        return door.answers(Kind.STUDENT, me(auth), id, token, in);
    }

    @PostMapping("/attempts/{id}/ping")
    @Transactional
    Map<String, Object> ping(Authentication auth, @PathVariable UUID id, @RequestHeader(value = "X-Attempt-Token", required = false) String token) {
        return door.ping(Kind.STUDENT, me(auth), id, token);
    }

    @PostMapping("/attempts/{id}/events")
    @Transactional
    Map<String, Object> events(Authentication auth, @PathVariable UUID id, @RequestHeader(value = "X-Attempt-Token", required = false) String token, @Valid @RequestBody EventsIn in) {
        return door.events(Kind.STUDENT, me(auth), id, token, in);
    }

    @PostMapping("/attempts/{id}/camera")
    @Transactional
    Map<String, Object> camera(Authentication auth, @PathVariable UUID id, @RequestHeader(value = "X-Attempt-Token", required = false) String token, @Valid @RequestBody CameraIn in) {
        return door.camera(Kind.STUDENT, me(auth), id, token, in);
    }

    @PostMapping("/attempts/{id}/submit")
    @Transactional
    Map<String, Object> submit(Authentication auth, @PathVariable UUID id, @RequestHeader(value = "X-Attempt-Token", required = false) String token) {
        return door.submit(Kind.STUDENT, me(auth), id, token);
    }

    @GetMapping("/attempts/{id}/result")
    @Transactional(readOnly = true)
    Map<String, Object> result(Authentication auth, @PathVariable UUID id) {
        return door.result(Kind.STUDENT, me(auth), id);
    }
}
