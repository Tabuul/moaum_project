package ng.edu.moaum.portal.helpdesk;

import java.sql.Types;
import java.time.LocalDate;
import java.time.ZoneId;
import java.time.format.DateTimeParseException;
import java.util.LinkedHashMap;
import java.util.Map;

import ng.edu.moaum.portal.shared.DomainRuleViolation;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.Authentication;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * V599: Sign-In Help Contacts. The e-mails and phones the sign-in help saved to student records that held none (V596) reach no
 * notice until they are confirmed; here they are listed within the agent's contact-editing scope, each with the request that saved
 * it and who asked, to be confirmed with the student or refused on the student's support profile (StudentSupportController,
 * /contact/confirm and /contact/refuse). For the Head of the ICT Support Desk and the Director of ICT, the day's student-number
 * checks on the sign-in page by connection, and the two figures that cap and watch them.
 */
@RestController
@RequestMapping("/api/v1/helpdesk/support/sign-in-contacts")
class SignInContactsController {

    private static final String HEADS = "hasAnyAuthority('OFFICE_helpdeskhead','OFFICE_ict','OFFICE_admin','OFFICE_super')";
    private static final ZoneId LAGOS = ZoneId.of("Africa/Lagos");

    private final JdbcClient jdbc;
    private final SupportAccess support;

    SignInContactsController(JdbcClient jdbc, SupportAccess support) {
        this.jdbc = jdbc;
        this.support = support;
    }

    /** the unconfirmed contacts the sign-in help saved, within the reader's contact-editing scope, newest request first */
    @GetMapping
    @PreAuthorize(SupportAccess.AGENTS)
    @Transactional(readOnly = true)
    Map<String, Object> list(Authentication auth) {
        SupportAccess.Access a = support.access(auth);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("rows", a.has("EDIT_CONTACT")
                ? jdbc.sql("SELECT * FROM helpdesk.sign_in_contacts(:me, :head)").param("me", a.agent()).param("head", a.head()).query().listOfRows()
                : java.util.List.of());
        out.put("mayDecide", a.has("EDIT_CONTACT"));
        out.put("scope", a.head() ? "The University"
                : jdbc.sql("SELECT words FROM helpdesk.agent_scope_for(:me, 'EDIT_CONTACT')").param("me", a.agent()).query(String.class).optional().orElse(null));
        out.put("head", a.head());
        return out;
    }

    /** a Lagos day's student-number checks on the sign-in page by connection (today by default), with the day's figures */
    @GetMapping("/lookups")
    @PreAuthorize(HEADS)
    @Transactional(readOnly = true)
    Map<String, Object> lookups(@RequestParam(required = false) String day) {
        LocalDate d;
        try {
            d = day == null || day.isBlank() ? LocalDate.now(LAGOS) : LocalDate.parse(day.trim());
        } catch (DateTimeParseException e) {
            throw new DomainRuleViolation("SIGN_IN_LOOKUP_DAY", "The day is written as 2026-10-21.", new DomainRuleViolation.Remedy("Choose a day from the calendar.", "You"));
        }
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("day", d.toString());
        out.put("rows", jdbc.sql("SELECT * FROM helpdesk.sign_in_lookups_by_source(:d)").param("d", d).query().listOfRows());
        out.putAll(figures());
        return out;
    }

    private Map<String, Object> figures() {
        Map<String, Object> f = jdbc.sql("SELECT sign_in_lookups_daily AS daily, sign_in_lookups_alert AS alert FROM helpdesk.setting WHERE row_no").query().singleRow();
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("daily", f.get("daily"));
        out.put("alert", f.get("alert"));
        return out;
    }

    /** the day's figure past which a connection's checks are refused, and the different numbers at which the Head is told; a figure
     *  named empty (null) is none; a figure not named is kept */
    @PutMapping("/lookups/figures")
    @PreAuthorize(HEADS)
    @Transactional
    Map<String, Object> saveFigures(@RequestBody tools.jackson.databind.JsonNode body) {
        Map<String, Object> now = figures();
        Integer daily = body.has("daily") ? bounded(body.get("daily"), "SIGN_IN_LOOKUP_DAILY", "The day's number of checks from one connection") : (Integer) now.get("daily");
        Integer alert = body.has("alert") ? bounded(body.get("alert"), "SIGN_IN_LOOKUP_ALERT", "The different numbers at which the Head is told") : (Integer) now.get("alert");
        jdbc.sql("UPDATE helpdesk.setting SET sign_in_lookups_daily = :d, sign_in_lookups_alert = :a WHERE row_no")
                .param("d", daily, Types.INTEGER).param("a", alert, Types.INTEGER).update();
        return figures();
    }

    private static Integer bounded(tools.jackson.databind.JsonNode v, String code, String what) {
        if (v == null || v.isNull() || (v.isString() && v.asString().isBlank())) return null;
        int n;
        try {
            n = v.isNumber() ? v.asInt() : Integer.parseInt(v.asString().trim());
        } catch (NumberFormatException e) {
            n = -1;
        }
        if (n < 1 || n > 10000) {
            throw new DomainRuleViolation(code, what + " is a whole number from 1 to 10,000, or empty for none.",
                    new DomainRuleViolation.Remedy("Type a figure, or clear it.", "Directorate of ICT"));
        }
        return n;
    }
}
