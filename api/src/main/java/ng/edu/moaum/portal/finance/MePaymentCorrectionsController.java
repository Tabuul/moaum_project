package ng.edu.moaum.portal.finance;

import java.util.List;
import java.util.Map;
import java.util.UUID;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.Authentication;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * V527: the school-fees payments the Bursary reallocated on the signed-in student's account — one credited to them in error and
 * moved to the student it belongs to (AWAY), or theirs moved onto their account (TO) — for the fees page. The other student is
 * never named.
 */
@RestController
@RequestMapping("/api/v1/me")
@PreAuthorize("hasAuthority('OFFICE_student')")
class MePaymentCorrectionsController {

    private final JdbcClient jdbc;

    MePaymentCorrectionsController(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    @GetMapping("/payment-corrections")
    @Transactional(readOnly = true)
    List<Map<String, Object>> corrections(Authentication auth) {
        return jdbc.sql("""
                SELECT swap_ref, kind, reference, amount, session, direction, executed_at, status
                  FROM finance.payment_swaps_of(:me) ORDER BY executed_at DESC
                """).param("me", UUID.fromString(auth.getName())).query().listOfRows();
    }
}
