package ng.edu.moaum.portal.auditlog;

import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

/**
 * The audit chain recomputed every night (V286): {@code audit.verify_chain()} walks every shard's
 * hash chain; the result of each period and shard is written to {@code platform.chain_verification},
 * so "verified nightly" is a fact the Security page reads rather than a sentence. A break reaches
 * the Registrar and the Directorate of ICT as a notice the same night, not ICT alone. The desk may
 * run the same verification on demand.
 */
@Component
public class AuditChainVerifier {

    private static final Logger log = LoggerFactory.getLogger(AuditChainVerifier.class);
    private final JdbcClient jdbc;

    AuditChainVerifier(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    @Scheduled(cron = "${moaum.audit.verify-cron:0 20 2 * * *}", zone = "Africa/Lagos")
    public void nightly() {
        try {
            Map<String, Object> r = run("NIGHTLY");
            log.info("audit chain verified: {} shard-periods, ok={}", r.get("checked"), r.get("ok"));
        } catch (RuntimeException e) {
            log.error("audit chain verification failed to run", e);
        }
    }

    @Transactional
    public Map<String, Object> run(String trigger) {
        UUID ref = UUID.randomUUID();
        List<Map<String, Object>> rows = jdbc.sql("SELECT period, shard, entries, ok, first_break, broke_at FROM audit.verify_chain()").query().listOfRows();
        long broken = 0;
        for (Map<String, Object> r : rows) {
            boolean ok = Boolean.TRUE.equals(r.get("ok"));
            if (!ok) broken++;
            jdbc.sql("INSERT INTO platform.chain_verification (trigger, period, shard, entries, ok, first_break, broke_at, run_ref) VALUES (:t, :p, :s, :e, :ok, :fb, :ba, :ref)")
                    .param("t", trigger).param("p", r.get("period"), java.sql.Types.DATE).param("s", r.get("shard"), java.sql.Types.SMALLINT)
                    .param("e", r.get("entries") == null ? 0L : ((Number) r.get("entries")).longValue()).param("ok", ok)
                    .param("fb", r.get("first_break"), java.sql.Types.OTHER).param("ba", r.get("broke_at"), java.sql.Types.TIMESTAMP_WITH_TIMEZONE).param("ref", ref).update();
        }
        if (rows.isEmpty()) {
            jdbc.sql("INSERT INTO platform.chain_verification (trigger, entries, ok, run_ref) VALUES (:t, 0, true, :ref)").param("t", trigger).param("ref", ref).update();
        }
        if (broken > 0) {
            String subject = "AUDIT CHAIN BREAK: " + broken + " shard-period(s) failed verification";
            String body = "The " + (trigger.equals("NIGHTLY") ? "nightly" : "on-demand") + " recomputation of the audit chain found " + broken + " shard-period(s) whose hash chain does not hold. "
                    + "Open Security → the audit spine for the first broken entry of each. No application role can amend an audit row; a break is investigated as an incident.";
            for (String office : List.of("ict", "registrar", "audit")) {
                jdbc.sql("SELECT admissions.tell_office(:o, :s, :b, NULL)").param("o", office).param("s", subject).param("b", body).query().listOfRows();
            }
        }
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("runRef", ref);
        out.put("checked", rows.size());
        out.put("broken", broken);
        out.put("ok", broken == 0);
        out.putAll(status());
        return out;
    }

    @Transactional(readOnly = true)
    public Map<String, Object> status() {
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("last", jdbc.sql("""
                SELECT run_ref, min(run_at) AS run_at, max(trigger) AS trigger, count(*) AS checked, count(*) FILTER (WHERE NOT ok) AS broken, sum(entries) AS entries
                  FROM platform.chain_verification GROUP BY run_ref ORDER BY min(run_at) DESC LIMIT 1
                """).query().listOfRows().stream().findFirst().orElse(null));
        out.put("runs", jdbc.sql("""
                SELECT run_ref, min(run_at) AS run_at, max(trigger) AS trigger, count(*) AS checked, count(*) FILTER (WHERE NOT ok) AS broken, sum(entries) AS entries
                  FROM platform.chain_verification GROUP BY run_ref ORDER BY min(run_at) DESC LIMIT 30
                """).query().listOfRows());
        out.put("breaks", jdbc.sql("SELECT run_at, trigger, period, shard, entries, first_break, broke_at FROM platform.chain_verification WHERE NOT ok ORDER BY run_at DESC LIMIT 50").query().listOfRows());
        return out;
    }
}
