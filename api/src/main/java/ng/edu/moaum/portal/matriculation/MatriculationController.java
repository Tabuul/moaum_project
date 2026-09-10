package ng.edu.moaum.portal.matriculation;

import java.util.List;
import java.util.Map;
import java.util.UUID;

import ng.edu.moaum.portal.shared.AuditContextHolder;
import ng.edu.moaum.portal.shared.DomainRuleViolation;
import ng.edu.moaum.portal.shared.NotFound;

import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/v1/matriculation/sessions/{s}/{y}")
class MatriculationController {

    private static final String READERS =
            "hasAnyAuthority('OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar','OFFICE_dvc','OFFICE_vc','OFFICE_records',"
            + "'OFFICE_dean','OFFICE_hod','OFFICE_facultyofficer','OFFICE_ict','OFFICE_admin','OFFICE_super')";
    private static final String OFFICERS = "hasAnyAuthority('OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar','OFFICE_facultyofficer')";
    private static final String RUNNERS = "hasAnyAuthority('OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar')";

    private final MatriculationRepository repo;

    MatriculationController(MatriculationRepository repo) {
        this.repo = repo;
    }

    @GetMapping
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Matriculation.Overview overview(@PathVariable String s, @PathVariable String y) {
        String session = s + "/" + y;
        List<Matriculation.FacultyLine> faculties = repo.faculties(session);
        long registered = 0;
        long confirmed = 0;
        long queried = 0;
        long pending = 0;
        for (Matriculation.FacultyLine f : faculties) {
            registered += f.registered();
            confirmed += f.confirmed();
            queried += f.queried();
            if (f.registered() > 0 && !"CONFIRMED".equals(f.state())) {
                pending++;
            }
        }
        List<Matriculation.Run> runs = repo.runs(session);
        List<Matriculation.Allocation> sample = runs.isEmpty() ? List.of() : repo.sample(runs.get(0).id());
        return new Matriculation.Overview(session, new Matriculation.Totals(registered, confirmed, pending, queried), faculties,
                repo.heldBack(session), runs, sample, repo.minUnits(100));
    }

    @GetMapping("/faculties/{code}")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Matriculation.FacultyList faculty(@PathVariable String s, @PathVariable String y, @PathVariable String code) {
        String session = s + "/" + y;
        String name = repo.facultyName(code.toUpperCase()).orElseThrow(() -> new NotFound("faculty", code));
        MatriculationRepository.ListRow l = repo.list(session, code.toUpperCase()).orElse(null);
        return new Matriculation.FacultyList(session, code.toUpperCase(), name, l == null ? "NOT_RETURNED" : l.state(),
                l == null ? null : l.confirmedAt(), repo.minUnits(100), repo.rows(session, code.toUpperCase()));
    }

    @PutMapping("/faculties/{code}/queries/{studentId}")
    @PreAuthorize(OFFICERS)
    @Transactional
    Map<String, Object> query(@PathVariable String s, @PathVariable String y, @PathVariable String code, @PathVariable UUID studentId,
                              @RequestBody Map<String, String> body) {
        String session = s + "/" + y;
        String reason = body.get("reason");
        if (reason == null || reason.isBlank()) {
            throw new DomainRuleViolation("MAT_QUERY_SAYS_WHY", "A name is put under query with the reason.",
                    new DomainRuleViolation.Remedy("Say what stands in the way, and which office clears it.", "Faculty Officer"));
        }
        if (!repo.onList(session, code.toUpperCase(), studentId)) {
            throw new NotFound("student on the " + code.toUpperCase() + " list", studentId);
        }
        UUID list = repo.ensureList(session, code.toUpperCase());
        repo.query(list, studentId, reason.trim(), body.getOrDefault("office", "Faculty Officer"));
        return Map.of("student", studentId, "state", "QUERIED");
    }

    @PostMapping("/faculties/{code}/queries/{studentId}/withdraw")
    @PreAuthorize(OFFICERS)
    @Transactional
    Map<String, Object> withdraw(@PathVariable String s, @PathVariable String y, @PathVariable String code, @PathVariable UUID studentId) {
        MatriculationRepository.ListRow l = repo.list(s + "/" + y, code.toUpperCase()).orElseThrow(() -> new NotFound("faculty list", code));
        int n = repo.withdraw(l.id(), studentId);
        if (n == 0) {
            throw new NotFound("query on the list for", studentId);
        }
        return Map.of("student", studentId, "state", "QUERY_WITHDRAWN");
    }

    @PostMapping("/faculties/{code}/confirm")
    @PreAuthorize(OFFICERS)
    @Transactional
    Map<String, Object> confirm(@PathVariable String s, @PathVariable String y, @PathVariable String code) {
        String session = s + "/" + y;
        repo.facultyName(code.toUpperCase()).orElseThrow(() -> new NotFound("faculty", code));
        MatriculationRepository.ListRow existing = repo.list(session, code.toUpperCase()).orElse(null);
        if (existing != null && "CONFIRMED".equals(existing.state())) {
            throw new DomainRuleViolation("MAT_ALREADY_CONFIRMED", "The " + code.toUpperCase() + " list for " + session + " is already confirmed.",
                    new DomainRuleViolation.Remedy("A confirmed list is not confirmed twice; the run reads it as it stands.", "Academic Office"));
        }
        UUID list = repo.ensureList(session, code.toUpperCase());
        repo.confirm(list, AuditContextHolder.required().actorId());
        return Map.of("faculty", code.toUpperCase(), "state", "CONFIRMED", "confirmed", repo.rows(session, code.toUpperCase()).stream()
                .filter(r -> r.queryReason() == null).count());
    }

    /** One transaction, one sequence: every number, or none. */
    @PostMapping("/run")
    @PreAuthorize(RUNNERS)
    @Transactional
    Map<String, Object> run(@PathVariable String s, @PathVariable String y) {
        MatriculationRepository.RunResult r = repo.run(s + "/" + y);
        return Map.of("run", r.runRef(), "issued", r.issued());
    }

    /**
     * Matriculate one student who has since paid the fees and registered — a straggler the batch
     * run missed. The database refuses, with the reason, anyone not admitted, not registered, or
     * still owing; nothing is typed, the number follows the record.
     */
    @PostMapping("/students/{studentId}/matriculate")
    @PreAuthorize(RUNNERS)
    @Transactional
    Map<String, Object> matriculateStudent(@PathVariable String s, @PathVariable String y, @PathVariable UUID studentId) {
        String matric = repo.matriculateStudent(studentId);
        return Map.of("student", studentId, "matricNo", matric);
    }
}
