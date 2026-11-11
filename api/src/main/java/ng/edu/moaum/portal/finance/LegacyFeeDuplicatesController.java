package ng.edu.moaum.portal.finance;

import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * V726: the legacy school-fee duplicate cleanup run on deployment — each run's actual counts (finance.legacy_fee_duplicate_run) and
 * what the plan reads now (finance.legacy_fee_duplicate_plan): the groups left whole for the Bursary, with the reason, and whether any
 * group could still be deleted. Read-only: the cleanup itself runs only as a migration, never from a screen.
 */
@RestController
@RequestMapping("/api/v1/finance/legacy-fees/duplicate-cleanup")
class LegacyFeeDuplicatesController {

    private static final String READERS = "hasAnyAuthority('OFFICE_bursar','OFFICE_studentaccounts','OFFICE_registrar','OFFICE_dregistrar','OFFICE_academic','OFFICE_audit','OFFICE_deputyaudit','OFFICE_ict','OFFICE_admin','OFFICE_super','OFFICE_vc','OFFICE_dvc')";

    private final JdbcClient jdbc;

    LegacyFeeDuplicatesController(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    @GetMapping
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> cleanup(@RequestParam(defaultValue = "500") int limit) {
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("runs", jdbc.sql("""
                SELECT run_ref, run_by, database_name, started_at, finished_at, status, inspected, groups_found, groups_cleaned, retained, deleted,
                       groups_skipped, records_skipped, skipped_by_reason::text AS skipped_by_reason, amount_deleted, students, numbers_sealed,
                       ledger_moved, ledger_released, identities_moved, receipts_voided, reconciliation, integrity, checks::text AS checks, error
                  FROM finance.legacy_fee_duplicate_run ORDER BY finished_at DESC LIMIT 20
                """).query().listOfRows());
        // what the plan reads now: after a successful run, only the groups left whole
        List<Map<String, Object>> plan = jdbc.sql("""
                SELECT group_key, reference, matric_no, session, level, semester, paid_on, payref, amount, role, reason, kept_reference
                  FROM finance.legacy_fee_duplicate_plan()
                """).query().listOfRows();
        Map<String, Object> now = new LinkedHashMap<>();
        now.put("groups", plan.stream().map(r -> r.get("group_key")).distinct().count());
        now.put("deletable", plan.stream().filter(r -> "DELETE".equals(r.get("role"))).count());
        now.put("groupsLeftWhole", plan.stream().filter(r -> "SKIP".equals(r.get("role"))).map(r -> r.get("group_key")).distinct().count());
        now.put("recordsLeftWhole", plan.stream().filter(r -> "SKIP".equals(r.get("role"))).count());
        out.put("now", now);
        out.put("leftWhole", plan.stream().filter(r -> "SKIP".equals(r.get("role"))).limit(Math.max(1, Math.min(limit, 5000))).toList());
        return out;
    }
}
