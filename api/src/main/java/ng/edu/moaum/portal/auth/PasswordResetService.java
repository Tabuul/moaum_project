package ng.edu.moaum.portal.auth;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.SecureRandom;
import java.time.OffsetDateTime;
import java.util.HexFormat;
import java.util.Map;
import java.util.UUID;
import java.util.regex.Pattern;

import ng.edu.moaum.portal.shared.AuditContext;
import ng.edu.moaum.portal.shared.AuditContextHolder;
import ng.edu.moaum.portal.shared.DomainRuleViolation;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;

/**
 * Self-service password reset for the main sign-in (V058): a staff member
 * (iam.credential) or a student (iam.student_account) — and an applicant
 * (admissions.applicant_account) — asks for a reset, a one-hour token is
 * emailed to the address on file and kept only as a hash, and used once to set
 * a new password. The answer to a request is always the same, so nothing is
 * revealed about whether an account exists.
 */
@Service
public class PasswordResetService {

    private static final UUID NOBODY = new UUID(0, 0);
    private static final Pattern EMAIL = Pattern.compile("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$");
    private static final SecureRandom RANDOM = new SecureRandom();

    private final JdbcClient jdbc;
    private final TransactionTemplate tx;
    private final BCryptPasswordEncoder encoder = new BCryptPasswordEncoder(12);
    private final String portalUrl;

    PasswordResetService(JdbcClient jdbc, PlatformTransactionManager transactions,
                         @Value("${moaum.portal-url:https://moaum-portal-production.up.railway.app}") String portalUrl) {
        this.jdbc = jdbc;
        this.tx = new TransactionTemplate(transactions);
        this.portalUrl = portalUrl == null ? "" : portalUrl.replaceAll("/+$", "");
    }

    private record Subject(String kind, UUID id, String email, String phone, String label) {
    }

    /** resolve an identifier to a staff, student or applicant account — the first that matches */
    private Subject resolve(String identifier) {
        String id = identifier.trim();
        String lower = id.toLowerCase();
        String upper = id.toUpperCase();

        // staff: the username is the staff number or an email; a staff email exists only when the username is one
        var staff = jdbc.sql("SELECT person_id FROM iam.credential WHERE username = :u").param("u", lower).query().listOfRows();
        if (!staff.isEmpty()) {
            UUID person = (UUID) staff.get(0).get("person_id");
            return new Subject("STAFF", person, EMAIL.matcher(lower).matches() ? lower : null, null, "staff account");
        }
        // student: by matriculation or admission number, or by the email on file
        var student = jdbc.sql("""
                SELECT s.id, r.email, r.phone FROM people.student s
                  LEFT JOIN LATERAL people.student_reach(s.id) r ON true
                 WHERE upper(s.matric_no) = :k OR upper(s.admission_no) = :k OR lower(r.email) = :e
                 LIMIT 1
                """).param("k", upper).param("e", lower).query().listOfRows();
        if (!student.isEmpty()) {
            Map<String, Object> s = student.get(0);
            return new Subject("STUDENT", (UUID) s.get("id"), (String) s.get("email"), (String) s.get("phone"), "student account");
        }
        // applicant: by JAMB number, email or application number
        var applicant = jdbc.sql("""
                SELECT a.id, a.email, a.phone FROM admissions.applicant_account a
                  JOIN admissions.application ap ON ap.account_id = a.id
                 WHERE upper(a.jamb_key) = :k OR lower(a.email) = :e OR upper(ap.application_no) = :k
                 LIMIT 1
                """).param("k", upper).param("e", lower).query().listOfRows();
        if (!applicant.isEmpty()) {
            Map<String, Object> a = applicant.get(0);
            return new Subject("APPLICANT", (UUID) a.get("id"), (String) a.get("email"), (String) a.get("phone"), "portal account");
        }
        return null;
    }

    /** a reset is asked for; if it names an account with an email, a one-hour link is sent. Always silent about which. */
    public void forgot(String identifier, String ip) {
        if (identifier == null || identifier.isBlank()) {
            return;
        }
        Subject s = resolve(identifier);
        if (s == null) {
            return;   // the same neutral answer whether or not it names an account
        }
        String token = HexFormat.of().formatHex(randomBytes());
        String hash = sha256(token);
        String link = portalUrl + "/login/reset?token=" + token;
        AuditContextHolder.with(new AuditContext(s.id(), "registrar", "password reset requested", null, null), () -> tx.execute(st -> {
            jdbc.sql("INSERT INTO iam.password_reset (subject_kind, subject_id, token_hash, expires_at) VALUES (:k, :s, :h, now() + interval '1 hour')")
                    .param("k", s.kind()).param("s", s.id()).param("h", hash).update();
            if (s.email() != null && !s.email().isBlank()) {
                jdbc.sql("SELECT platform.queue_notice('EMAIL', :r, :sub, :b, :ak, :ai)")
                        .param("r", s.email()).param("sub", "Reset your MOAUM password")
                        .param("b", "Somebody — we hope you — asked to reset the password of your MOAUM " + s.label() + ". "
                                + "Open this link within the hour to choose a new one:\n\n" + link
                                + "\n\nIf it was not you, ignore this message; your password is unchanged.")
                        .param("ak", s.kind().toLowerCase()).param("ai", s.id()).query().listOfRows();
            }
            if (s.phone() != null && !s.phone().isBlank()) {
                jdbc.sql("SELECT platform.queue_notice('SMS', :r, :sub, :b, :ak, :ai)")
                        .param("r", s.phone()).param("sub", "Reset your MOAUM password")
                        .param("b", "MOAUM: reset your password within the hour at " + link)
                        .param("ak", s.kind().toLowerCase()).param("ai", s.id()).query().listOfRows();
            }
            return null;
        }));
    }

    /** the token names the account and the store; a new password is set once, and the token is spent. */
    public void reset(String token, String password, String ip) {
        if (token == null || token.isBlank()) {
            throw badToken();
        }
        if (password == null || password.length() < 8) {
            throw new DomainRuleViolation("AUTH_PASSWORD_SHORT", "A password is at least eight characters.",
                    new DomainRuleViolation.Remedy("Choose one of eight characters or more.", "You"));
        }
        String hash = sha256(token.trim());
        var found = jdbc.sql("SELECT id, subject_kind, subject_id, expires_at, used_at FROM iam.password_reset WHERE token_hash = :h ORDER BY created_at DESC LIMIT 1")
                .param("h", hash).query().listOfRows();
        if (found.isEmpty()) {
            throw badToken();
        }
        Map<String, Object> r = found.get(0);
        if (r.get("used_at") != null || ((OffsetDateTime) r.get("expires_at")).isBefore(OffsetDateTime.now())) {
            throw badToken();
        }
        UUID resetId = (UUID) r.get("id");
        UUID subject = (UUID) r.get("subject_id");
        String kind = (String) r.get("subject_kind");
        String pwHash = encoder.encode(password);
        AuditContextHolder.with(new AuditContext(subject, "registrar", "password reset", null, null), () -> tx.execute(st -> {
            switch (kind) {
                case "STAFF" -> jdbc.sql("UPDATE iam.credential SET password_hash = :h, must_change = false, failed_attempts = 0, locked_until = NULL WHERE person_id = :s")
                        .param("h", pwHash).param("s", subject).update();
                case "STUDENT" -> jdbc.sql("UPDATE iam.student_account SET password_hash = :h, must_change = false, failed_attempts = 0, locked_until = NULL WHERE student_id = :s")
                        .param("h", pwHash).param("s", subject).update();
                default -> jdbc.sql("UPDATE admissions.applicant_account SET password_hash = :h WHERE id = :s")
                        .param("h", pwHash).param("s", subject).update();
            }
            jdbc.sql("UPDATE iam.password_reset SET used_at = now() WHERE id = :id").param("id", resetId).update();
            return null;
        }));
    }

    private static DomainRuleViolation badToken() {
        return new DomainRuleViolation("AUTH_RESET_TOKEN", "This reset link has expired or was already used.",
                new DomainRuleViolation.Remedy("Ask for a new reset link; each one is good for an hour and works once.", "You"));
    }

    private static byte[] randomBytes() {
        byte[] b = new byte[32];
        RANDOM.nextBytes(b);
        return b;
    }

    private static String sha256(String s) {
        try {
            return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(s.getBytes(StandardCharsets.UTF_8)));
        } catch (Exception e) {
            throw new IllegalStateException(e);
        }
    }
}
