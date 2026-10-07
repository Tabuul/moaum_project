package ng.edu.moaum.portal.admissions;

import java.sql.Types;
import java.time.LocalDate;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import jakarta.validation.Valid;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

import ng.edu.moaum.portal.shared.AuditContextHolder;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * Offers that lapse and a waiting list that moves (V358), decided by the Admissions Office (the Academic Office and the
 * Registrar): the session's acceptance deadline — a date, days after an offer's own release, or the later of the two; none
 * set, no offer lapses; the offers past it, neither accepted nor paid for, lapsed when the office says so; each place freed
 * by a lapse or a decline filled from the programme's waiting list in merit order by the office's choice, the place's quota
 * basis shown beside the candidates' state and LGA. Reads for the admissions readers.
 */
@RestController
@RequestMapping("/api/v1/admissions/offers")
class OffersController {

    private static final String READERS =
            "hasAnyAuthority('OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar','OFFICE_dvc','OFFICE_vc','OFFICE_records','OFFICE_ict','OFFICE_admin','OFFICE_super')";
    private static final String DECIDERS = "hasAnyAuthority('OFFICE_academic','OFFICE_registrar')";

    private final JdbcClient jdbc;

    OffersController(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    @GetMapping
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> read(@RequestParam String session) {
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("session", session);
        out.put("deadline", jdbc.sql("""
                SELECT d.accept_by::text AS accept_by, d.days_after_release, d.note, d.set_at, p.surname || ', ' || p.given_names AS set_by
                  FROM admissions.offer_deadline d LEFT JOIN iam.person p ON p.id = d.set_by WHERE d.session = :s
                """).param("s", session).query().listOfRows().stream().findFirst().orElse(null));
        out.put("pastDeadline", jdbc.sql("SELECT *, released_on::text AS released, deadline::text AS deadline_on FROM admissions.offers_past_deadline(:s)")
                .param("s", session).query().listOfRows());
        out.put("vacancies", jdbc.sql("SELECT * FROM admissions.vacancies(:s)").param("s", session).query().listOfRows());
        out.put("counts", jdbc.sql("""
                SELECT count(*) FILTER (WHERE decision = 'OFFERED' AND decision_released_at IS NOT NULL) AS offered,
                       count(*) FILTER (WHERE accepted_at IS NOT NULL) AS accepted,
                       count(*) FILTER (WHERE declined_at IS NOT NULL) AS declined,
                       count(*) FILTER (WHERE lapsed_at IS NOT NULL) AS lapsed,
                       count(*) FILTER (WHERE promoted_for IS NOT NULL) AS promoted,
                       count(*) FILTER (WHERE decision = 'WAITING' AND lapsed_at IS NULL) AS waiting
                  FROM admissions.application WHERE session = :s
                """).param("s", session).query().singleRow());
        return out;
    }

    public record DeadlineIn(@NotBlank @Pattern(regexp = "^\\d{4}/\\d{4}$") String session, LocalDate acceptBy,
                             @Min(1) @Max(120) Integer daysAfterRelease, @Size(max = 500) String note) {
    }

    /** the session's acceptance deadline set (a date, days after release, or both) — or, neither given, cleared: then nothing lapses */
    @PutMapping("/deadline")
    @PreAuthorize(DECIDERS)
    @Transactional
    Map<String, Object> deadline(@Valid @RequestBody DeadlineIn b) {
        if (b.acceptBy() == null && b.daysAfterRelease() == null) {
            jdbc.sql("DELETE FROM admissions.offer_deadline WHERE session = :s").param("s", b.session()).update();
        } else {
            jdbc.sql("""
                    INSERT INTO admissions.offer_deadline (session, accept_by, days_after_release, note, set_by) VALUES (:s, :d, :n, :note, :by)
                    ON CONFLICT (session) DO UPDATE SET accept_by = EXCLUDED.accept_by, days_after_release = EXCLUDED.days_after_release, note = EXCLUDED.note,
                           set_by = EXCLUDED.set_by, set_at = now()
                    """).param("s", b.session()).param("d", b.acceptBy(), Types.DATE).param("n", b.daysAfterRelease(), Types.INTEGER)
                    .param("note", b.note() == null || b.note().isBlank() ? null : b.note().trim(), Types.VARCHAR)
                    .param("by", AuditContextHolder.required().actorId()).update();
        }
        return read(b.session());
    }

    public record LapseIn(@NotBlank @Pattern(regexp = "^\\d{4}/\\d{4}$") String session, @Size(max = 5000) List<UUID> applicationIds) {
    }

    /** the offers past their deadline lapsed — those named, or every one — each applicant told */
    @PostMapping("/lapse")
    @PreAuthorize(DECIDERS)
    @Transactional
    Map<String, Object> lapse(@Valid @RequestBody LapseIn b) {
        int n = jdbc.sql("SELECT admissions.lapse_offers(:s, :a)").param("s", b.session())
                .param("a", (b.applicationIds() == null ? List.<UUID>of() : b.applicationIds()).toArray(new UUID[0]))
                .query(Integer.class).single();
        Map<String, Object> out = new LinkedHashMap<>(read(b.session()));
        out.put("lapsed", n);
        return out;
    }

    /** a programme's waiting list in merit order, and the places it has freed */
    @GetMapping("/waiting")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> waiting(@RequestParam String session, @RequestParam String programme) {
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("session", session);
        out.put("programme", programme);
        out.put("waiting", jdbc.sql("SELECT * FROM admissions.waiting_list(:s, :p)").param("s", session).param("p", programme).query().listOfRows());
        out.put("vacancies", jdbc.sql("SELECT * FROM admissions.vacancies(:s) WHERE programme = :p").param("s", session).param("p", programme).query().listOfRows());
        return out;
    }

    public record PromoteIn(@NotBlank @Pattern(regexp = "^\\d{4}/\\d{4}$") String session, @NotBlank String programme,
                            @NotNull @Size(min = 1, max = 500) List<UUID> applicationIds) {
    }

    /** the waiting candidates chosen promoted to the programme's freed places, in the order they were freed */
    @PostMapping("/promote")
    @PreAuthorize(DECIDERS)
    @Transactional
    Map<String, Object> promote(@Valid @RequestBody PromoteIn b) {
        int n = jdbc.sql("SELECT admissions.promote_waiting(:s, :p, :a, :by)").param("s", b.session()).param("p", b.programme().trim())
                .param("a", b.applicationIds().toArray(new UUID[0])).param("by", AuditContextHolder.required().actorId()).query(Integer.class).single();
        Map<String, Object> out = new LinkedHashMap<>(waiting(b.session(), b.programme().trim()));
        out.put("promoted", n);
        return out;
    }
}
