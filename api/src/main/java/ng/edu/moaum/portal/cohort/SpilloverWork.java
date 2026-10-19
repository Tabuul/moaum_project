package ng.edu.moaum.portal.cohort;

import java.util.LinkedHashMap;
import java.util.Map;
import java.util.UUID;

import ng.edu.moaum.portal.shared.AuditContext;
import ng.edu.moaum.portal.shared.AuditContextHolder;
import ng.edu.moaum.portal.shared.FigureCache;
import ng.edu.moaum.portal.shared.JobLock;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * V572: the spillover work waiting on Student Cohorts — level corrections by basis, the recommendations not yet reconciled, and when
 * Reconciliation last ran (people.spillover_work) — read on the Academic Office's and the Registrar's homes (kept five minutes:
 * under a second on a register of 48,000, the views it reads are not cheap), and told to the holders of both offices each Monday
 * morning while any of it waits (people.tell_spillover_work, once a week each).
 */
@RestController
@RequestMapping("/api/v1/cohorts")
class SpilloverWork {

    private static final Logger LOG = LoggerFactory.getLogger(SpilloverWork.class);
    private static final UUID NOBODY = new UUID(0, 0);
    private static final String READERS = "hasAnyAuthority('OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar','OFFICE_records','OFFICE_dvc','OFFICE_vc',"
            + "'OFFICE_ict','OFFICE_admin','OFFICE_super')";

    private final JdbcClient jdbc;
    private final FigureCache figures;
    private final JobLock lock;
    private final TransactionTemplate tx;

    SpilloverWork(JdbcClient jdbc, FigureCache figures, JobLock lock, PlatformTransactionManager transactions) {
        this.jdbc = jdbc;
        this.figures = figures;
        this.lock = lock;
        this.tx = new TransactionTemplate(transactions);
    }

    @GetMapping("/spillover-work")
    @PreAuthorize(READERS)
    Map<String, Object> work(@RequestParam(defaultValue = "false") boolean refresh) {
        FigureCache.Answer<String> a = figures.get("spillover-work", refresh, () -> jdbc.sql("SELECT people.spillover_work()::text").query(String.class).single());
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("work", new tools.jackson.databind.ObjectMapper().readValue(a.value(), Map.class));
        out.put("at", a.at());
        return out;
    }

    @Scheduled(cron = "${moaum.cohorts.spillover-work-cron:0 30 8 * * MON}", zone = "Africa/Lagos")
    public void tell() {
        lock.runExclusively("spillover-work", this::tellNow);
    }

    void tellNow() {
        try {
            Integer n = AuditContextHolder.with(new AuditContext(NOBODY, "registrar", "the spillover work waiting, told weekly", null, null), () -> tx.execute(status ->
                    jdbc.sql("SELECT people.tell_spillover_work()").query(Integer.class).single()));
            LOG.info("spillover work: {} notice(s) queued", n);
            figures.forget("spillover-work");
        } catch (RuntimeException e) {
            LOG.warn("spillover work notice did not run: {}", e.getMessage());
        }
    }
}
