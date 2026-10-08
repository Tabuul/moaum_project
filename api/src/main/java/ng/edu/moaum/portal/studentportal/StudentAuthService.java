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
import ng.edu.moaum.portal.shared.Throttle;

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
    private final Throttle throttle;
    private final BCryptPasswordEncoder encoder = new BCryptPasswordEncoder(12);
    private final SecureRandom random = new SecureRandom();

    StudentAuthService(StudentPortalRepository repo, TokenIssuer issuer, PlatformTransactionManager transactions, Throttle throttle) {
        this.repo = repo;
        this.throttle = throttle;
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

    /** what the student account opens with when it is carried over from the applicant's: the applicant's own bcrypt hash — or, for an
     *  account still on its first-login sentinel (V178: the JAMB number is the password until one is chosen), a fresh hash nobody knows
     *  with must-change on, so the door opens the same way it did for the applicant: the number is the first password, changed at once.
     *  The sentinel itself is not a hash and the account table refuses it (ck_student_hash). */
    private record Carried(String hash, boolean mustChange) { }

    private Carried carried(String applicantHash) {
        if (applicantHash != null && applicantHash.startsWith("$2")) {
            return new Carried(applicantHash, false);
        }
        return new Carried(encoder.encode(UUID.randomUUID().toString()), true);
    }

    public SignedIn signIn(String matricNo, String password, String ip) {
        // V359: one connection trying many student accounts is refused before any is tried
        throttle.refuse(Throttle.Door.STUDENT_SIGN_IN, ip);
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
                    throttle.count(Throttle.Door.STUDENT_SIGN_IN, ip);
                    return badCredentials();
                }
                Carried c = carried(applicantHash);
                repo.openAccount(s.id(), c.hash(), c.mustChange());
                repo.event(matricNo, s.id(), "CARRIED_OVER", ip);
                a = repo.account(s.id()).orElseThrow();
            }
            if (a.lockedUntil() != null && a.lockedUntil().isAfter(OffsetDateTime.now())) {
                repo.event(matricNo, s.id(), "LOCKED", ip);
                throttle.count(Throttle.Door.STUDENT_SIGN_IN, ip);
                return new DomainRuleViolation("AUTH_LOCKED", "This account is locked after repeated failures; try again after "
                        + a.lockedUntil().toLocalTime().withNano(0) + ".", new DomainRuleViolation.Remedy("Wait fifteen minutes.", "You"));
            }
            boolean ok = encoder.matches(password == null ? "" : password, a.passwordHash());
            if (ok && a.temporarySpent()) {
                /* V346: a temporary password from ICT Support opens one session, until its time; spent or lapsed, it opens nothing */
                repo.event(matricNo, s.id(), "TEMP_PASSWORD_SPENT", ip);
                return new DomainRuleViolation("AUTH_TEMP_PASSWORD_SPENT", "This temporary password has expired or was already used.",
                        new DomainRuleViolation.Remedy("Ask ICT Support for a reset link, or a new temporary password at the desk; it is good for one sign-in.", "ICT Support"));
            }
            if (!ok && a.mustChange() && !a.temporary()) {
                /* a migrated student whose password was never set signs in with their own number as the
                   password (username == password) and is then forced to choose a real one. This is the
                   default first password, granted at sign-in — so no 40,000 accounts are pre-hashed. */
                String u = matricNo == null ? "" : matricNo.trim();
                String p = password == null ? "" : password.trim();
                ok = !p.isEmpty() && p.equalsIgnoreCase(u);
            }
            if (!ok) {
                int attempts = a.failedAttempts() + 1;
                repo.failed(s.id(), attempts, attempts >= LOCK_AFTER ? OffsetDateTime.now().plus(LOCK_FOR) : null);
                repo.event(matricNo, s.id(), "BAD_PASSWORD", ip);
                throttle.count(Throttle.Door.STUDENT_SIGN_IN, ip);
                return badCredentials();
            }
            byte[] sid = new byte[32];
            random.nextBytes(sid);
            Instant end = Instant.now().plus(SESSION_LENGTH);
            repo.openSession(sid, s.id(), end);
            repo.signedIn(s.id());
            if (a.temporary()) {
                repo.temporaryUsed(s.id());
            }
            repo.event(matricNo, s.id(), "SIGNED_IN", ip);
            String name = s.surname() + ", " + s.otherNames();
            return new SignedIn(issuer.issue(s.id(), name, List.of("student"), sid, end), end, s.id(), s.matricNo(), s.surname(), s.otherNames(), a.mustChange());
        });
        if (outcome instanceof DomainRuleViolation refused) {
            throw refused;
        }
        return (SignedIn) outcome;
    }

    /**
     * The applicant, already signed in, continues into the student portal as the
     * student they have become: the same person, so no second password is asked.
     * The account is carried over from the applicant's on first use, exactly as
     * the sign-in door does it. Refused while they are not yet on the register.
     */
    public SignedIn continueFromApplicant(UUID applicantAccountId, String ip) {
        StudentPortalRepository.Student s = repo.byApplicantAccount(applicantAccountId).orElse(null);
        Object outcome = atTheDoor(s == null ? null : s.id(), "student portal continued from the applicant portal", () -> {
            if (s == null) {
                return new DomainRuleViolation("AUTH_NOT_ON_REGISTER", "You are not yet on the student register.",
                        new DomainRuleViolation.Remedy("The register follows your admission: it opens when your screening is successful, or on acceptance where the session needs no screening. Until then, everything is on the applicant portal.", "Registry"));
            }
            String number = s.matricNo() != null ? s.matricNo() : s.admissionNo();
            StudentPortalRepository.Account a = repo.account(s.id()).orElse(null);
            if (a == null) {
                String applicantHash = repo.applicantHash(s.candidateId()).orElse(null);
                if (applicantHash == null) {
                    repo.event(number, s.id(), "NO_ACCOUNT", ip);
                    return new DomainRuleViolation("AUTH_NO_STUDENT_ACCOUNT", "No portal account has been opened for this number yet.",
                            new DomainRuleViolation.Remedy("The Registry opens it and gives you a first password; you change it when you sign in.", "Registry"));
                }
                Carried c = carried(applicantHash);
                repo.openAccount(s.id(), c.hash(), c.mustChange());
                repo.event(number, s.id(), "CARRIED_OVER", ip);
                a = repo.account(s.id()).orElseThrow();
            }
            if (a.lockedUntil() != null && a.lockedUntil().isAfter(OffsetDateTime.now())) {
                repo.event(number, s.id(), "LOCKED", ip);
                return new DomainRuleViolation("AUTH_LOCKED", "This account is locked after repeated failures; try again after "
                        + a.lockedUntil().toLocalTime().withNano(0) + ".", new DomainRuleViolation.Remedy("Wait fifteen minutes.", "You"));
            }
            byte[] sid = new byte[32];
            random.nextBytes(sid);
            Instant end = Instant.now().plus(SESSION_LENGTH);
            repo.openSession(sid, s.id(), end);
            repo.signedIn(s.id());
            repo.event(number, s.id(), "SIGNED_IN", ip);
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
        boolean ok = encoder.matches(current == null ? "" : current, a.passwordHash());
        if (!ok && a.mustChange() && !a.temporary()) {
            // the default first password is the student's own number (matric, or admission before it is
            // issued) — the same default sign-in grants, so changing from it here must accept it too
            StudentPortalRepository.Student s = repo.byId(student).orElse(null);
            String c = current == null ? "" : current.trim();
            ok = !c.isEmpty() && s != null
                 && ((s.matricNo() != null && c.equalsIgnoreCase(s.matricNo().trim()))
                     || (s.admissionNo() != null && c.equalsIgnoreCase(s.admissionNo().trim())));
        }
        if (!ok) {
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

    /** V346: what ICT Support hands the student at the desk — once; the account keeps only its hash */
    public record Temporary(String password, OffsetDateTime expiresAt, UUID eventId) {
    }

    static final Duration TEMPORARY_FOR = Duration.ofHours(24);
    private static final String TEMP_LETTERS = "ABCDEFGHJKMNPQRSTUVWXYZabcdefghjkmnpqrstuvwxyz23456789";

    /**
     * V346: a temporary password issued by ICT Support at the desk — random (twelve characters from SecureRandom, never a
     * number the student is known by), kept only as a bcrypt hash, good for one sign-in within 24 hours, and changed at it;
     * while it stands the matriculation-number first password opens nothing. The password is returned here once.
     */
    @Transactional
    public Temporary issueTemporary(UUID student, UUID by) {
        StudentPortalRepository.Student s = repo.byId(student).orElseThrow(() -> new NotFound("student", student));
        String pw;
        do {
            StringBuilder b = new StringBuilder(12);
            for (int i = 0; i < 12; i++) b.append(TEMP_LETTERS.charAt(random.nextInt(TEMP_LETTERS.length())));
            pw = b.toString();
        } while (pw.equalsIgnoreCase(s.matricNo() == null ? "" : s.matricNo()) || pw.equalsIgnoreCase(s.admissionNo() == null ? "" : s.admissionNo()));
        OffsetDateTime until = OffsetDateTime.now().plus(TEMPORARY_FOR);
        repo.issueTemporary(student, encoder.encode(pw), by, until);
        UUID event = repo.event("", student, "TEMP_PASSWORD_ISSUED");
        return new Temporary(pw, until, event);
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
