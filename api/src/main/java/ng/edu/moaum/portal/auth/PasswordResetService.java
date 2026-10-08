package ng.edu.moaum.portal.auth;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.SecureRandom;
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

        // staff: matched on the username (staff number or email); the reset goes to the person's
        // email on record (V060), or the username when it is itself an email
        var staff = jdbc.sql("""
                SELECT c.person_id, p.email, p.phone FROM iam.credential c JOIN iam.person p ON p.id = c.person_id
                 WHERE c.username = :u
                """).param("u", lower).query().listOfRows();
        if (!staff.isEmpty()) {
            Map<String, Object> c = staff.get(0);
            String email = (String) c.get("email");
            if (email == null || email.isBlank()) {
                email = EMAIL.matcher(lower).matches() ? lower : null;
            }
            return new Subject("STAFF", (UUID) c.get("person_id"), email, (String) c.get("phone"), "staff account");
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
        // postgraduate applicant: by email or application number
        var pg = jdbc.sql("""
                SELECT p.id, p.email, p.phone FROM admissions.pg_applicant p
                  JOIN admissions.pg_application ap ON ap.applicant_id = p.id
                 WHERE lower(p.email) = :e OR upper(ap.application_no) = :k
                 LIMIT 1
                """).param("k", upper).param("e", lower).query().listOfRows();
        if (!pg.isEmpty()) {
            Map<String, Object> a = pg.get(0);
            return new Subject("PGAPPLICANT", (UUID) a.get("id"), (String) a.get("email"), (String) a.get("phone"), "postgraduate application account");
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
        // V359: at most three links an hour to one account, however often they are asked for — the same neutral answer
        long recent = jdbc.sql("SELECT count(*) FROM iam.password_reset WHERE subject_kind = :k AND subject_id = :s AND created_at > now() - interval '1 hour'")
                .param("k", s.kind()).param("s", s.id()).query(Long.class).single();
        if (recent >= 3) {
            return;
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

    /** V346: what ICT Support is told of a reset it started: which reset, and where the link went — the addresses masked, never the token */
    public record StudentReset(UUID resetId, String email, String phone) {
    }

    private static String mask(String v, boolean email) {
        if (v == null || v.isBlank()) return null;
        String t = v.trim();
        if (email) {
            int at = t.indexOf('@');
            return at <= 1 ? "***" + (at >= 0 ? t.substring(at) : "") : t.charAt(0) + "***" + t.substring(at - 1);
        }
        return t.length() <= 4 ? "****" : "*".repeat(t.length() - 4) + t.substring(t.length() - 4);
    }

    /**
     * V346: ICT Support starts a reset for one student, named by the record (never by an identifier that might name another
     * account): the same one-hour, single-use link the student would ask for, to the email and phone the University reaches
     * them at, saying the reset was started by ICT Support. Refused when the record holds no address to send it to.
     */
    public StudentReset forStudent(UUID student) {
        return forStudent(student, null);
    }

    /**
     * The same, with a fallback address: the email on the student's own support ticket, which the student gave while signed
     * in — used only when the record holds no email, so a student whose record lacks an address can still be reached.
     */
    public StudentReset forStudent(UUID student, String ticketEmail) {
        var row = jdbc.sql("SELECT r.email, r.phone FROM people.student s LEFT JOIN LATERAL people.student_reach(s.id) r ON true WHERE s.id = :s")
                .param("s", student).query().listOfRows();
        if (row.isEmpty()) {
            throw new DomainRuleViolation("AUTH_NO_STUDENT", "No such student.", new DomainRuleViolation.Remedy("Open the student from the search.", "ICT Support"));
        }
        String email = (String) row.get(0).get("email");
        String phone = (String) row.get(0).get("phone");
        if ((email == null || email.isBlank()) && ticketEmail != null && EMAIL.matcher(ticketEmail.trim()).matches()) {
            email = ticketEmail.trim().toLowerCase();
        }
        if ((email == null || email.isBlank()) && (phone == null || phone.isBlank())) {
            throw new DomainRuleViolation("AUTH_NO_ADDRESS", "The record holds no email or phone to send a reset link to.",
                    new DomainRuleViolation.Remedy("Correct the student's contact first, or issue a temporary password at the desk on the student's ticket.", "ICT Support"));
        }
        String token = HexFormat.of().formatHex(randomBytes());
        String link = portalUrl + "/login/reset?token=" + token;
        UUID id = jdbc.sql("INSERT INTO iam.password_reset (subject_kind, subject_id, token_hash, expires_at) VALUES ('STUDENT', :s, :h, now() + interval '1 hour') RETURNING id")
                .param("s", student).param("h", sha256(token)).query(UUID.class).single();
        if (email != null && !email.isBlank()) {
            jdbc.sql("SELECT platform.queue_notice('EMAIL', :r, :sub, :b, 'student', :ai)")
                    .param("r", email).param("sub", "Your portal password reset")
                    .param("b", "Your portal password reset has been initiated by ICT Support. Follow the secure instructions to create a new password: open this link "
                            + "within the hour and choose a new one.\n\n" + link + "\n\nThe link works once. ICT Support never sees or sets your password. "
                            + "If you did not ask for this, ignore this message and tell ICT Support; your password is unchanged.")
                    .param("ai", student).query().listOfRows();
        }
        if (phone != null && !phone.isBlank()) {
            jdbc.sql("SELECT platform.queue_notice('SMS', :r, :sub, :b, 'student', :ai)")
                    .param("r", phone).param("sub", "Your portal password reset")
                    .param("b", "MOAUM: ICT Support started your password reset. Choose a new password within the hour at " + link)
                    .param("ai", student).query().listOfRows();
        }
        return new StudentReset(id, mask(email, true), mask(phone, false));
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
        // the expiry and single-use are checked in SQL, so no timestamp type has to cross into Java
        var found = jdbc.sql("SELECT id, subject_kind, subject_id FROM iam.password_reset WHERE token_hash = :h AND used_at IS NULL AND expires_at > now() ORDER BY created_at DESC LIMIT 1")
                .param("h", hash).query().listOfRows();
        if (found.isEmpty()) {
            throw badToken();
        }
        Map<String, Object> r = found.get(0);
        UUID resetId = (UUID) r.get("id");
        UUID subject = (UUID) r.get("subject_id");
        String kind = (String) r.get("subject_kind");
        String pwHash = encoder.encode(password);
        AuditContextHolder.with(new AuditContext(subject, "registrar", "password reset", null, null), () -> tx.execute(st -> {
            switch (kind) {
                case "STAFF" -> jdbc.sql("UPDATE iam.credential SET password_hash = :h, must_change = false, failed_attempts = 0, locked_until = NULL WHERE person_id = :s")
                        .param("h", pwHash).param("s", subject).update();
                // V346: the account is opened if it never was (the link proves the address on the record), and a temporary password ends
                case "STUDENT" -> jdbc.sql("""
                        INSERT INTO iam.student_account (id, student_id, password_hash, must_change) VALUES (gen_random_uuid(), :s, :h, false)
                        ON CONFLICT (student_id) DO UPDATE SET password_hash = EXCLUDED.password_hash, must_change = false, failed_attempts = 0, locked_until = NULL,
                            temp_expires_at = NULL, temp_issued_by = NULL, temp_used_at = NULL
                        """).param("h", pwHash).param("s", subject).update();
                case "PGAPPLICANT" -> jdbc.sql("UPDATE admissions.pg_applicant SET password_hash = :h WHERE id = :s")
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
