package ng.edu.moaum.portal.studentportal;

import java.security.SecureRandom;
import java.time.Duration;
import java.time.Instant;
import java.time.OffsetDateTime;
import java.util.HexFormat;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.function.Supplier;

import ng.edu.moaum.portal.auth.TokenIssuer;
import ng.edu.moaum.portal.shared.AuditContext;
import ng.edu.moaum.portal.shared.AuditContextHolder;
import ng.edu.moaum.portal.shared.DomainRuleViolation;
import ng.edu.moaum.portal.shared.NotFound;

import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionTemplate;

/**
 * The student's sign-in on the matriculation number. The applicant account
 * becomes the student account the first time: the password the applicant
 * chose is verified against the application account, and the student
 * account is opened on the same hash. A student with no application behind
 * them is given a password by the Registry, and changes it at first sign-in.
 * The same lockout as every other door.
 */
@Service
public class StudentAuthService {

    static final Duration SESSION_LENGTH = Duration.ofHours(12);
    static final int LOCK_AFTER = 5;
    static final Duration LOCK_FOR = Duration.ofMinutes(15);
    static final int MIN_PASSWORD = 8;
    static final UUID NOBODY = new UUID(0, 0);

    public record SignedIn(String token, Instant expiresAt, UUID studentId, String matricNo, String surname, String otherNames, boolean mustChange) {
    }

    private final StudentPortalRepository repo;
    private final TokenIssuer issuer;
    private final TransactionTemplate tx;
    private final BCryptPasswordEncoder encoder = new BCryptPasswordEncoder(12);
    private final SecureRandom random = new SecureRandom();

    StudentAuthService(StudentPortalRepository repo, TokenIssuer issuer, PlatformTransactionManager transactions) {
        this.repo = repo;
        this.issuer = issuer;
        this.tx = new TransactionTemplate(transactions);
    }

    private <T> T atTheDoor(UUID actor, String reason, Supplier<T> work) {
        return AuditContextHolder.with(new AuditContext(actor == null ? NOBODY : actor, "student", reason, null, null),
                () -> tx.execute(status -> work.get()));
    }

    private static DomainRuleViolation badCredentials() {
        return new DomainRuleViolation("AUTH_BAD_CREDENTIALS", "That number and password do not match a student account.",
                new DomainRuleViolation.Remedy("Use your matriculation number, or your admission number before it is issued, with the password you chose at application or the one the Registry gave you; five failures lock the account for fifteen minutes.", "Registry"));
    }

    public SignedIn signIn(String matricNo, String password, String ip) {
        StudentPortalRepository.Student s = repo.byMatric(matricNo).orElse(null);
        Object outcome = atTheDoor(s == null ? null : s.id(), "student sign-in", () -> {
            /* the student door opens on the matriculation number and, before it is issued, on the
               admission number — so an admitted candidate signs in to pay school fees and register
               courses under it; matriculation issues the matric number afterwards */
            if (s == null || (s.matricNo() == null && s.admissionNo() == null)) {
                repo.event(matricNo, s == null ? null : s.id(), "UNKNOWN", ip);
                return badCredentials();
            }
            StudentPortalRepository.Account a = repo.account(s.id()).orElse(null);
            if (a == null) {
                /* the applicant account, carried over on first sign-in */
                String applicantHash = repo.applicantHash(s.candidateId()).orElse(null);
                if (applicantHash == null) {
                    repo.event(matricNo, s.id(), "NO_ACCOUNT", ip);
                    return new DomainRuleViolation("AUTH_NO_STUDENT_ACCOUNT", "No portal account has been opened for this number yet.",
                            new DomainRuleViolation.Remedy("The Registry opens it and gives you a first password; you change it when you sign in.", "Registry"));
                }
                if (!encoder.matches(password == null ? "" : password, applicantHash)) {
                    repo.event(matricNo, s.id(), "BAD_PASSWORD", ip);
                    return badCredentials();
                }
                repo.openAccount(s.id(), applicantHash, false);
                repo.event(matricNo, s.id(), "CARRIED_OVER", ip);
                a = repo.account(s.id()).orElseThrow();
            }
            if (a.lockedUntil() != null && a.lockedUntil().isAfter(OffsetDateTime.now())) {
                repo.event(matricNo, s.id(), "LOCKED", ip);
                return new DomainRuleViolation("AUTH_LOCKED", "This account is locked after repeated failures; try again after "
                        + a.lockedUntil().toLocalTime().withNano(0) + ".", new DomainRuleViolation.Remedy("Wait fifteen minutes.", "You"));
            }
            if (!encoder.matches(password == null ? "" : password, a.passwordHash())) {
                int attempts = a.failedAttempts() + 1;
                repo.failed(s.id(), attempts, attempts >= LOCK_AFTER ? OffsetDateTime.now().plus(LOCK_FOR) : null);
                repo.event(matricNo, s.id(), "BAD_PASSWORD", ip);
                return badCredentials();
            }
            byte[] sid = new byte[32];
            random.nextBytes(sid);
            Instant end = Instant.now().plus(SESSION_LENGTH);
            repo.openSession(sid, s.id(), end);
            repo.signedIn(s.id());
            repo.event(matricNo, s.id(), "SIGNED_IN", ip);
            String name = s.surname() + ", " + s.otherNames();
            return new SignedIn(issuer.issue(s.id(), name, List.of("student"), sid, end), end, s.id(), s.matricNo(), s.surname(), s.otherNames(), a.mustChange());
        });
        if (outcome instanceof DomainRuleViolation refused) {
            throw refused;
        }
        return (SignedIn) outcome;
    }

    @Transactional
    public void signOut(UUID student, String sidHex) {
        if (sidHex != null) {
            repo.endSession(HexFormat.of().parseHex(sidHex), student);
        }
    }

    @Transactional
    public Map<String, Object> changePassword(UUID student, String current, String next) {
        StudentPortalRepository.Account a = repo.account(student).orElseThrow(() -> new NotFound("student account", student));
        if (!encoder.matches(current == null ? "" : current, a.passwordHash())) {
            throw badCredentials();
        }
        if (next == null || next.length() < MIN_PASSWORD) {
            throw new DomainRuleViolation("APP_PASSWORD_SHORT", "Eight characters at the very least.",
                    new DomainRuleViolation.Remedy("This one account carries you to graduation.", "You"));
        }
        repo.changePassword(student, encoder.encode(next));
        repo.event("", student, "PASSWORD_CHANGED", null);
        return Map.of("changed", true);
    }

    /** the Registry opens or resets a student's account: a first password, changed at sign-in */
    @Transactional
    public Map<String, Object> open(UUID student, String firstPassword) {
        repo.byId(student).orElseThrow(() -> new NotFound("student", student));
        if (firstPassword == null || firstPassword.length() < MIN_PASSWORD) {
            throw new DomainRuleViolation("APP_PASSWORD_SHORT", "Eight characters at the very least.",
                    new DomainRuleViolation.Remedy("Give the student a first password of eight characters or more; they change it at sign-in.", "Registry"));
        }
        repo.openAccount(student, encoder.encode(firstPassword), true);
        repo.event("", student, "OPENED_BY_REGISTRY", null);
        return Map.of("studentId", student, "opened", true, "mustChange", true);
    }
}
