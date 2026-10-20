package ng.edu.moaum.portal.finance;

import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

import ng.edu.moaum.portal.shared.AuditContext;
import ng.edu.moaum.portal.shared.AuditContextHolder;
import ng.edu.moaum.portal.shared.JobLock;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.TransactionDefinition;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionTemplate;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * V580: what correcting every waiting level would do to the current session's charges, for the Bursary before the Academic Office or
 * the Registry corrects them. A run takes the corrections waiting on the bases chosen as they stand, then reads them 1,000 at a
 * time behind the screens (people.level_fee_effect_step: the levels raised and undone, the basis of its start held), each step its
 * own transaction in the starter's name; the screen polls how far it got and reads the sums by faculty and programme, and every
 * student's row for the Excel. Nothing on a record changes. One run at a time; a run an API restart left open is taken up again.
 */
@RestController
@RequestMapping("/api/v1/finance/level-fee-effect")
class LevelFeeEffectController {

    private static final Logger LOG = LoggerFactory.getLogger(LevelFeeEffectController.class);
    private static final String READERS = "hasAnyAuthority('OFFICE_bursar','OFFICE_studentaccounts','OFFICE_registrar','OFFICE_dregistrar','OFFICE_academic',"
            + "'OFFICE_records','OFFICE_audit','OFFICE_deputyaudit','OFFICE_ict','OFFICE_admin','OFFICE_super','OFFICE_vc','OFFICE_dvc')";
    private static final String STARTERS = "hasAnyAuthority('OFFICE_bursar','OFFICE_studentaccounts','OFFICE_registrar','OFFICE_dregistrar','OFFICE_academic','OFFICE_super')";
    private static final List<String> BASES = List.of("SPILLOVER", "REGISTRATION", "ARITHMETIC");
    private static final int STEP = 1000;

    private final JdbcClient jdbc;
    private final JobLock lock;
    private final TransactionTemplate tx;
    private final ExecutorService now = Executors.newSingleThreadExecutor(r -> {
        Thread t = new Thread(r, "level-fee-effect");
        t.setDaemon(true);
        return t;
    });

    LevelFeeEffectController(JdbcClient jdbc, JobLock lock, PlatformTransactionManager transactions) {
        this.jdbc = jdbc;
        this.lock = lock;
        this.tx = new TransactionTemplate(transactions);
        this.tx.setPropagationBehavior(TransactionDefinition.PROPAGATION_REQUIRES_NEW);
    }

    /** the latest run: how far it got and, once done, the sums for the University, each faculty and each programme */
    @GetMapping
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> latest() {
        Map<String, Object> out = new LinkedHashMap<>();
        Map<String, Object> run = jdbc.sql("""
                SELECT r.id, r.session, r.basis, r.bases, r.state, r.students, r.done, r.error, r.started_at, r.finished_at, r.started_office,
                       helpdesk.person_name(r.started_by) AS started_by
                  FROM people.level_fee_effect_run r ORDER BY r.started_at DESC LIMIT 1
                """).query().listOfRows().stream().findFirst().orElse(null);
        if (run != null && run.get("bases") instanceof java.sql.Array a) {
            try {
                run.put("bases", List.of((Object[]) a.getArray()));
            } catch (java.sql.SQLException e) {
                run.put("bases", List.of());
            }
        }
        out.put("run", run);
        out.put("waiting", jdbc.sql("SELECT basis, count(*) AS students FROM people.level_correction GROUP BY basis ORDER BY basis").query().listOfRows());
        if (run != null && "DONE".equals(run.get("state"))) {
            out.put("report", jdbc.sql("SELECT * FROM people.level_fee_effect_report(:r)").param("r", run.get("id")).query().listOfRows());
        }
        return out;
    }

    public record Start(List<String> bases) {
    }

    /** a run begun on the bases chosen (spillover and own registration when none is named) and read behind the screens */
    @PostMapping
    @PreAuthorize(STARTERS)
    Map<String, Object> start(@RequestBody(required = false) Start body) {
        List<String> bases = body == null || body.bases() == null || body.bases().isEmpty() ? List.of("SPILLOVER", "REGISTRATION")
                : body.bases().stream().map(b -> b == null ? "" : b.trim().toUpperCase()).distinct().toList();
        if (!BASES.containsAll(bases)) {
            throw new ng.edu.moaum.portal.shared.DomainRuleViolation("LEVEL_CORRECTION_BASIS", "A basis is SPILLOVER, REGISTRATION or ARITHMETIC.");
        }
        UUID id = tx.execute(st -> jdbc.sql("SELECT people.start_level_fee_effect(CAST(:b AS text[]))").param("b", bases.toArray(String[]::new), java.sql.Types.ARRAY)
                .query(UUID.class).single());
        now.submit(() -> lock.runExclusively("level-fee-effect", this::runNow));
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("id", id);
        out.put("state", "RUNNING");
        return out;
    }

    /** every student of a run, for the Excel */
    @GetMapping("/{id}/rows")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> rows(@PathVariable UUID id) {
        return jdbc.sql("""
                SELECT x.student_id, upper(btrim(s.surname)) || coalesce(', ' || nullif(btrim(s.other_names), ''), '') AS name,
                       coalesce(s.matric_no, s.admission_no) AS number, f.name AS faculty, p.name AS programme, x.basis,
                       x.current_level, x.new_level, x.charged_now, x.charged_after
                  FROM people.level_fee_effect_row x
                  JOIN people.student s ON s.id = x.student_id
                  LEFT JOIN ref.programme p ON p.code = s.programme_code
                  LEFT JOIN ref.faculty f ON f.code = p.faculty_code
                 WHERE x.run_id = :r AND x.charged_now IS NOT NULL
                 ORDER BY f.name, p.name, name
                """).param("r", id).query().listOfRows();
    }

    /** a run an API restart left open is taken up again */
    @Scheduled(fixedDelayString = "${moaum.level-fee-effect.every-ms:60000}", initialDelayString = "${moaum.level-fee-effect.initial-ms:45000}")
    void tick() {
        lock.runExclusively("level-fee-effect", this::runNow);
    }

    void runNow() {
        Map<String, Object> run = jdbc.sql("SELECT id, started_by, started_office FROM people.level_fee_effect_run WHERE state = 'RUNNING' ORDER BY started_at LIMIT 1")
                .query().listOfRows().stream().findFirst().orElse(null);
        if (run == null) {
            return;
        }
        UUID id = (UUID) run.get("id");
        UUID by = run.get("started_by") instanceof UUID u ? u : new UUID(0, 0);
        String office = run.get("started_office") instanceof String o && !o.isBlank() ? o : "bursar";
        AuditContext ctx = new AuditContext(by, office, "the fee effect of the waiting level corrections worked out", id, null);
        try {
            while (true) {
                Integer n = AuditContextHolder.with(ctx, () -> tx.execute(st ->
                        jdbc.sql("SELECT people.level_fee_effect_step(:r, :n)").param("r", id).param("n", STEP).query(Integer.class).single()));
                if (n == null || n == 0) {
                    return;
                }
            }
        } catch (RuntimeException e) {
            LOG.warn("level fee effect {} stopped: {}", id, e.getMessage());
            String why = e.getMessage() == null ? e.getClass().getSimpleName() : e.getMessage();
            AuditContextHolder.with(ctx, () -> tx.execute(st -> jdbc.sql("""
                    UPDATE people.level_fee_effect_run SET state = 'FAILED', error = left(:e, 500), finished_at = now() WHERE id = :r AND state = 'RUNNING'
                    """).param("e", why).param("r", id).update()));
        }
    }
}
