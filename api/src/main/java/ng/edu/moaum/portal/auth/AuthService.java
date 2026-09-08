package ng.edu.moaum.portal.auth;

import java.security.SecureRandom;
import java.time.Duration;
import java.time.Instant;
import java.time.OffsetDateTime;
import java.util.HexFormat;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.function.Supplier;

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
 * FR-IAM-010/011/015/019: username and password, bcrypt at cost 12,
 * progressive lockout after five failures, sessions the person can see and
 * end. The same wrong answer for an unknown username and a wrong password,
 * so the sign-in page cannot be used to list accounts.
 *
 * <p>Sign-in and bootstrap arrive with no token, so no audit context is on
 * the thread. They place one — the person signing in, at the door the
 * Directorate of ICT operates — BEFORE the transaction opens, because the
 * transaction manager copies the context onto the connection at that moment.
 */
@Service
public class AuthService {

    static final Duration SESSION_LENGTH = Duration.ofHours(12);
    static final int LOCK_AFTER = 5;
    static final Duration LOCK_FOR = Duration.ofMinutes(15);
    static final int MIN_PASSWORD = 10;
    static final UUID NOBODY = new UUID(0, 0);

    public record SignedIn(String token, Instant expiresAt, UUID personId, String surname, String givenNames, String staffNumber,
                           List<Map<String, Object>> offices, boolean mustChange) {
    }

    private final AuthRepository repo;
    private final TokenIssuer issuer;
    private final TransactionTemplate tx;
    private final BCryptPasswordEncoder encoder = new BCryptPasswordEncoder(12);
    private final SecureRandom random = new SecureRandom();

    AuthService(AuthRepository repo, TokenIssuer issuer, PlatformTransactionManager transactions) {
        this.repo = repo;
        this.issuer = issuer;
        this.tx = new TransactionTemplate(transactions);
    }

    /** a transaction attributed to the person at the door, opened after the context is placed */
    private <T> T atTheDoor(UUID person, String reason, Supplier<T> work) {
        return AuditContextHolder.with(new AuditContext(person == null ? NOBODY : person, "ict", reason, null, null),
                () -> tx.execute(status -> work.get()));
    }

    public SignedIn signIn(String usernameIn, String password, String ip, String preferredOffice) {
        String username = usernameIn == null ? "" : usernameIn.trim().toLowerCase();
        AuthRepository.Credential c = repo.byUsername(username).orElse(null);
        return atTheDoor(c == null ? null : c.personId(), "sign-in", () -> {
            if (c == null || c.endedOn() != null) {
                repo.event(username, c == null ? null : c.personId(), "UNKNOWN", ip, null);
                throw badCredentials();
            }
            if (c.lockedUntil() != null && c.lockedUntil().isAfter(OffsetDateTime.now())) {
                repo.event(username, c.personId(), "LOCKED", ip, null);
                throw new DomainRuleViolation("AUTH_LOCKED", "This account is locked after repeated failures; try again after "
                        + c.lockedUntil().toLocalTime().withNano(0) + ".",
                        new DomainRuleViolation.Remedy("Wait fifteen minutes, or ask the Registry to reset the password.", "Registrar"));
            }
            if (!encoder.matches(password == null ? "" : password, c.passwordHash())) {
                int attempts = c.failedAttempts() + 1;
                repo.failed(c.personId(), attempts, attempts >= LOCK_AFTER ? OffsetDateTime.now().plus(LOCK_FOR) : null);
                repo.event(username, c.personId(), "BAD_PASSWORD", ip, null);
                throw badCredentials();
            }
            List<AuthRepository.Office> offices = repo.liveOffices(c.personId());
            List<String> codes = offices.stream().map(AuthRepository.Office::officeCode).distinct().toList();
            String active = preferredOffice != null && codes.contains(preferredOffice) ? preferredOffice : codes.isEmpty() ? "ict" : codes.getFirst();
            byte[] sid = new byte[32];
            random.nextBytes(sid);
            Instant end = Instant.now().plus(SESSION_LENGTH);
            repo.openSession(sid, c.personId(), active, end);
            repo.signedIn(c.personId());
            repo.event(username, c.personId(), "SIGNED_IN", ip, sid);
            String name = c.surname() + ", " + c.givenNames();
            return new SignedIn(issuer.issue(c.personId(), name, codes, sid, end), end, c.personId(), c.surname(), c.givenNames(),
                    c.staffNumber(), offices.stream().map(o -> Map.<String, Object>of("code", o.officeCode(), "label", o.label(),
                            "scopeKind", o.scopeKind(), "scopeId", o.scopeId() == null ? "" : o.scopeId(),
                            "validTo", o.validTo() == null ? "" : o.validTo().toString())).toList(), c.mustChange());
        });
    }

    private static DomainRuleViolation badCredentials() {
        return new DomainRuleViolation("AUTH_BAD_CREDENTIALS", "That username and password do not match an account.",
                new DomainRuleViolation.Remedy("Check the number the University issued you and try again; five failures lock the account for fifteen minutes.", "Registry"));
    }

    @Transactional
    public void signOut(UUID person, String sidHex) {
        if (sidHex == null) {
            return;
        }
        byte[] sid = HexFormat.of().parseHex(sidHex);
        repo.endSession(sid, person, "signed out");
        repo.event("", person, "SIGNED_OUT", null, sid);
    }

    @Transactional(readOnly = true)
    public List<AuthRepository.Session> sessions(UUID person) {
        return repo.sessions(person);
    }

    @Transactional
    public void endSession(UUID person, String sidHex) {
        int n = repo.endSession(HexFormat.of().parseHex(sidHex), person, "ended by the person");
        if (n == 0) {
            throw new NotFound("session", sidHex);
        }
    }

    static void checkPolicy(String username, String password) {
        if (password == null || password.length() < MIN_PASSWORD) {
            throw new DomainRuleViolation("AUTH_PASSWORD_SHORT", "A password is at least " + MIN_PASSWORD + " characters.",
                    new DomainRuleViolation.Remedy("Choose a longer one; a sentence you will remember is better than a word you will not.", "You"));
        }
        if (username != null && !username.isBlank() && password.toLowerCase().contains(username.toLowerCase())) {
            throw new DomainRuleViolation("AUTH_PASSWORD_IS_USERNAME", "The password contains the username.",
                    new DomainRuleViolation.Remedy("Choose one that does not.", "You"));
        }
    }

    @Transactional
    public void changePassword(UUID person, String current, String next) {
        AuthRepository.Credential c = repo.byPerson(person).orElseThrow(() -> new NotFound("credential for", person));
        if (!encoder.matches(current == null ? "" : current, c.passwordHash())) {
            throw new DomainRuleViolation("AUTH_BAD_CREDENTIALS", "The current password is not right.",
                    new DomainRuleViolation.Remedy("Type the password you signed in with.", "You"));
        }
        checkPolicy(c.username(), next);
        repo.setCredential(person, c.username(), encoder.encode(next), false, person, "CHANGED");
    }

    /** the Registry sets or resets a person's password; the person changes it at first sign-in */
    @Transactional
    public Map<String, Object> setCredential(UUID person, String usernameIn, String password) {
        String username = usernameIn == null ? "" : usernameIn.trim().toLowerCase();
        if (username.length() < 3) {
            throw new DomainRuleViolation("AUTH_USERNAME", "A username is the staff number or an email address.",
                    new DomainRuleViolation.Remedy("Give the number the University issued.", "Registry"));
        }
        if (repo.usernameTaken(username, person)) {
            throw new DomainRuleViolation("AUTH_USERNAME_TAKEN", "'" + username + "' already signs somebody else in.",
                    new DomainRuleViolation.Remedy("Two people do not share a username.", "Registry"));
        }
        checkPolicy(username, password);
        boolean existed = repo.byPerson(person).isPresent();
        repo.setCredential(person, username, encoder.encode(password), true, AuditContextHolder.required().actorId(), existed ? "RESET" : "SET");
        return Map.of("personId", person, "username", username, "mustChange", true);
    }

    /**
     * The first account, made once, with the secret the API already trusts:
     * a person, the offices that run the platform and the Registry, a password.
     */
    public SignedIn bootstrap(String secret, String expectedSecret, String staffNumber, String surname, String givenNames,
                              String username, String password, String ip) {
        if (expectedSecret == null || expectedSecret.isBlank() || !expectedSecret.equals(secret)) {
            throw new DomainRuleViolation("AUTH_BOOTSTRAP_SECRET", "The bootstrap secret is not right.",
                    new DomainRuleViolation.Remedy("It is the value of MOAUM_AUTH_HMAC_SECRET on the API service.", "Directorate of ICT"));
        }
        if (repo.credentials() > 0) {
            throw new DomainRuleViolation("AUTH_BOOTSTRAPPED", "The portal already has accounts; the first one is made once.",
                    new DomainRuleViolation.Remedy("Sign in, and grant offices from the Users & roles screen.", "Registrar"));
        }
        String user = username == null ? "" : username.trim().toLowerCase();
        checkPolicy(user, password);
        atTheDoor(NOBODY, "bootstrap: the first account", () -> {
            UUID person = repo.createPerson(staffNumber == null || staffNumber.isBlank() ? null : staffNumber.trim(), surname.trim(), givenNames.trim());
            repo.grant(person, "registrar", "institution", "Bootstrap of the portal, Directorate of ICT", NOBODY);
            repo.grant(person, "academic", "institution", "Bootstrap of the portal, Directorate of ICT", NOBODY);
            repo.grant(person, "ict", "platform", "Bootstrap of the portal, Directorate of ICT", NOBODY);
            repo.grant(person, "super", "platform", "Bootstrap of the portal, Directorate of ICT", NOBODY);
            repo.setCredential(person, user, encoder.encode(password), false, NOBODY, "SET");
            return person;
        });
        return signIn(user, password, ip, "registrar");
    }

    @Transactional(readOnly = true)
    public List<AuthRepository.OfficeRow> offices() {
        return repo.offices();
    }
}
