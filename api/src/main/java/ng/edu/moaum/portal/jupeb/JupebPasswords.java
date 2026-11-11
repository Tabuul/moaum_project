package ng.edu.moaum.portal.jupeb;

import java.util.UUID;

import org.springframework.jdbc.core.simple.JdbcClient;

import ng.edu.moaum.portal.shared.DomainRuleViolation;

/**
 * The one place for the JUPEB portal's rule on a candidate's own number as a password (V718, after V428's rule for everyone
 * else). The application number — this portal's, or the old portal's App No kept as legacy_ref — is the first password of a
 * student uploaded from the old portal (jupeb.first_password_opens: compared at the door, never hashed into the account) and
 * is never the chosen one: the change of password and the reset link both refuse it. The JUPEB door's and the CBT door's
 * gates share the words that send a candidate still on a first password to choose their own.
 */
public final class JupebPasswords {

    private JupebPasswords() {
    }

    /** whether the text, however its letters and spaces are typed, is one of the account's numbers */
    static boolean isOwnNumber(JdbcClient jdbc, UUID account, String text) {
        return Boolean.TRUE.equals(jdbc.sql("""
                SELECT EXISTS (SELECT 1 FROM jupeb.application x WHERE x.account_id = :a
                                  AND upper(regexp_replace(:p, '\\s+', '', 'g')) IN (upper(x.application_no), upper(nullif(x.legacy_ref, ''))))
                """).param("a", account).param("p", text).query(Boolean.class).single());
    }

    static DomainRuleViolation numberIsNoPassword() {
        return new DomainRuleViolation("JUPEB_PASSWORD_IS_NUMBER", "Your application number cannot be your password.",
                new DomainRuleViolation.Remedy("Choose a password that is not your application number.", "You"));
    }

    /** V356: a first password opens the portal to read and to choose a password, nothing else — on the server, not only on the page */
    public static DomainRuleViolation changeFirst() {
        return new DomainRuleViolation("JUPEB_PASSWORD_CHANGE_FIRST", "Choose your own password first: your application number or a temporary password only opens the portal to change it.",
                new DomainRuleViolation.Remedy("Change your password, then carry on.", "You"));
    }
}
