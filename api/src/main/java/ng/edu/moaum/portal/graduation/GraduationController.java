package ng.edu.moaum.portal.graduation;

import java.util.List;
import java.util.Map;
import java.util.UUID;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;

import ng.edu.moaum.portal.shared.AuditContextHolder;

import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/v1/graduation")
class GraduationController {

    private static final String READERS =
            "hasAnyAuthority('OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar','OFFICE_dvc','OFFICE_vc','OFFICE_records',"
            + "'OFFICE_dean','OFFICE_hod','OFFICE_ict','OFFICE_admin','OFFICE_super',"
            // V640: the Database Operations office reads; the batches and corrections stay with the Academic Office and the Registry
            + "'OFFICE_dbops')";
    private static final String OFFICE = "hasAnyAuthority('OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar','OFFICE_records')";

    /** V602: who confirms awards in batches — the Academic Office and the Registry; and who corrects a graduation — the Registrar only */
    private static final String BATCHERS = "hasAnyAuthority('OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar')";
    private static final String CORRECTORS = "hasAnyAuthority('OFFICE_registrar','OFFICE_dregistrar')";

    private final GraduationService service;
    private final GraduationBatchService batches;

    private final ng.edu.moaum.portal.shared.OfficeScope scope;

    GraduationController(GraduationService service, GraduationBatchService batches, ng.edu.moaum.portal.shared.OfficeScope scope) {
        this.service = service;
        this.batches = batches;
        this.scope = scope;
    }

    /* ── V602: graduation management — batches on the Senate's minute, the lock, the correction, the reports ── */

    public record BatchFilter(String entry, String level, String status, String q, String fac, String dept, String prog, List<UUID> students) {
    }

    public record BatchPreview(@NotBlank String session, BatchFilter filter) {
    }

    public record BatchOpen(@NotBlank String session, @NotBlank String senateMinute, @NotBlank String reason, BatchFilter filter) {
    }

    public record Correction(@NotBlank String reason, @NotBlank String evidence) {
    }

    @GetMapping("/management")
    @PreAuthorize(READERS)
    Map<String, Object> management(@RequestParam String session, @RequestParam(required = false) String fac,
                                   @RequestParam(required = false) String dept, @RequestParam(required = false) String prog) {
        return batches.management(session, scope.bound(fac, dept, prog));
    }

    /** nothing written: who the filter names, and each one's verdict */
    @PostMapping("/batches/preview")
    @PreAuthorize(BATCHERS)
    Map<String, Object> preview(@Valid @RequestBody BatchPreview body) {
        List<UUID> chosen = batches.select(filterOf(body.filter()), boundOf(body.filter()));
        List<GraduationBatchService.Verdict> rows = batches.preview(body.session(), chosen);
        return Map.of("session", body.session(), "selected", chosen.size(), "rows", rows, "tally", tally(rows));
    }

    @PostMapping("/batches")
    @PreAuthorize(BATCHERS)
    Map<String, Object> open(@Valid @RequestBody BatchOpen body) {
        List<UUID> chosen = batches.select(filterOf(body.filter()), boundOf(body.filter()));
        Map<String, Object> scopeWords = new java.util.LinkedHashMap<>();
        if (body.filter() != null) {
            if (blank(body.filter().fac()) != null) scopeWords.put("fac", body.filter().fac());
            if (blank(body.filter().dept()) != null) scopeWords.put("dept", body.filter().dept());
            if (blank(body.filter().prog()) != null) scopeWords.put("prog", body.filter().prog());
            if (blank(body.filter().entry()) != null) scopeWords.put("entry", body.filter().entry());
            if (blank(body.filter().level()) != null) scopeWords.put("level", body.filter().level());
            if (blank(body.filter().status()) != null) scopeWords.put("status", body.filter().status());
            if (blank(body.filter().q()) != null) scopeWords.put("q", body.filter().q());
            if (body.filter().students() != null && !body.filter().students().isEmpty()) scopeWords.put("chosen", body.filter().students().size());
        }
        return batches.open(body.session(), body.senateMinute(), body.reason(), chosen, scopeWords, AuditContextHolder.required());
    }

    @GetMapping("/batches")
    @PreAuthorize(READERS)
    List<Map<String, Object>> batches(@RequestParam(required = false) String session, @RequestParam(required = false) String fac,
                                      @RequestParam(required = false) String dept, @RequestParam(required = false) String prog) {
        return batches.batches(session, scope.bound(fac, dept, prog));
    }

    @GetMapping("/batches/{year}/{seq}")
    @PreAuthorize(READERS)
    Map<String, Object> batch(@PathVariable String year, @PathVariable String seq) {
        return batches.batch("GRAD/" + year + "/" + seq);
    }

    /** one step: up to 200 eligible students graduated, each all or nothing; called again until done */
    @PostMapping("/batches/{year}/{seq}/execute")
    @PreAuthorize(BATCHERS)
    Map<String, Object> execute(@PathVariable String year, @PathVariable String seq) {
        return batches.execute("GRAD/" + year + "/" + seq, AuditContextHolder.required());
    }

    @PostMapping("/batches/{year}/{seq}/close")
    @PreAuthorize(BATCHERS)
    Map<String, Object> close(@PathVariable String year, @PathVariable String seq) {
        return batches.close("GRAD/" + year + "/" + seq, AuditContextHolder.required());
    }

    @GetMapping("/students/{id}/verdict")
    @PreAuthorize(READERS)
    Map<String, Object> verdict(@PathVariable UUID id, @RequestParam String session) {
        return batches.verdict(id, session);
    }

    @PostMapping("/students/{id}/correct")
    @PreAuthorize(CORRECTORS)
    Map<String, Object> correct(@PathVariable UUID id, @Valid @RequestBody Correction body) {
        return batches.correct(id, body.reason(), body.evidence(), AuditContextHolder.required());
    }

    @GetMapping("/report")
    @PreAuthorize(READERS)
    Map<String, Object> report(@RequestParam(required = false) String session, @RequestParam(defaultValue = "faculty") String by,
                               @RequestParam(required = false) String fac, @RequestParam(required = false) String dept,
                               @RequestParam(required = false) String prog) {
        return Map.of("session", session == null ? "" : session, "by", by, "rows", batches.report(session, by, scope.bound(fac, dept, prog)));
    }

    private GraduationBatchService.Filter filterOf(BatchFilter f) {
        return f == null ? new GraduationBatchService.Filter(null, null, null, null, null)
                : new GraduationBatchService.Filter(f.entry(), f.level(), f.status(), f.q(), f.students());
    }

    private ng.edu.moaum.portal.shared.OfficeScope.Bound boundOf(BatchFilter f) {
        return f == null ? scope.bound(null, null, null) : scope.bound(blank(f.fac()), blank(f.dept()), blank(f.prog()));
    }

    private static Map<String, Long> tally(List<GraduationBatchService.Verdict> rows) {
        Map<String, Long> t = new java.util.TreeMap<>();
        for (GraduationBatchService.Verdict v : rows) {
            t.merge(v.verdict(), 1L, Long::sum);
        }
        return t;
    }

    @GetMapping("/sessions/{s}/{y}")
    @PreAuthorize(READERS)
    GraduationService.View view(@PathVariable String s, @PathVariable String y, @RequestParam(required = false) String fac,
                                @RequestParam(required = false) String dept, @RequestParam(required = false) String prog) {
        ng.edu.moaum.portal.shared.OfficeScope.Bound b = scope.bound(fac, dept, prog);   // the office's bound, whatever the parameters say
        return service.view(s + "/" + y, b.fac(), b.dept(), b.prog());
    }

    @PostMapping("/sessions/{s}/{y}/audit")
    @PreAuthorize(OFFICE)
    Map<String, Object> audit(@PathVariable String s, @PathVariable String y) {
        return service.audit(s + "/" + y);
    }

    @PostMapping("/sessions/{s}/{y}/approve")
    @PreAuthorize("hasAnyAuthority('OFFICE_registrar','OFFICE_dregistrar','OFFICE_academic')")
    Map<String, Object> approve(@PathVariable String s, @PathVariable String y, @RequestBody(required = false) Map<String, String> body) {
        return service.approve(s + "/" + y, body == null ? null : body.get("senateMinute"));
    }

    private static String blank(String v) {
        return v == null || v.isBlank() ? null : v;
    }
}
