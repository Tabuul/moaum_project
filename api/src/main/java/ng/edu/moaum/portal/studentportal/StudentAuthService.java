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
                new DomainRuleViolation.Remedy("Use your matriculation number (or admission number before it is issued) and your password; five failures lock the account for fifteen minutes.", "Registry"));
    }

    /** V428: a person's own number is never their password — not the matriculation, admission or JAMB number, whether it is
     *  offered at the door or was stored as a hash (the migration desk's old "default passwords") — once a password has been chosen.
     *  Before one is, the number is the first password (see {@link #firstPassword}); otherwise it is the reset link to the contact on
     *  record, ICT Support's temporary password, or one the Registry gives. */
    static boolean ownNumber(String password, StudentPortalRepository.Student s) {
        String p = password == null ? "" : password.trim();
        return !p.isEmpty() && s != null
               && ((s.matricNo() != null && p.equalsIgnoreCase(s.matricNo().trim())) || (s.admissionNo() != null && p.equalsIgnoreCase(s.admissionNo().trim()))
                   || (s.jambRegNo() != null && p.equalsIgnoreCase(s.jambRegNo().trim())));
    }

    /** the first password (V178, V122), granted at the door rather than hashed into 47,000 accounts: the number the student signs in
     *  with — the matriculation number, or before one is issued the JAMB or admission number the door accepts (V267). It holds while
     *  the account is still on its first password: must-change on, no temporary password, none chosen; the change is forced before
     *  anything else, and from then on the number opens nothing. Most migrated students have no email or phone on record for the reset
     *  link to reach. */
    static boolean firstPassword(String password, String signedInAs) {
        String p = password == null ? "" : password.trim();
        String u = signedInAs == null ? "" : signedInAs.trim();
        return !p.isEmpty() && p.equalsIgnoreCase(u);
    }

    static boolean onFirstPassword(StudentPortalRepository.Account a) {
        return a.mustChange() && !a.temporary();
    }

    /** V485: said on the public sign-in page, so it never says what the default credential is */
    static DomainRuleViolation ownNumberRefused() {
        return new DomainRuleViolation("AUTH_FIRST_PASSWORD_RETIRED", "Your own number is not your password.",
                new DomainRuleViolation.Remedy("Use the password you chose. Forgotten it? Choose \"Forgot password?\": a link goes to the email or phone the University has for you; with none on record, ICT Support resets it at the desk.", "ICT Support"));
    }

    /** V485: a password that carries the student's own matriculation, admission or JAMB number — the staff rule (no password that
     *  holds the username) applied to the numbers a student signs in with */
    static boolean holdsOwnNumber(String password, StudentPortalRepository.Student s) {
        String p = password == null ? "" : password.toUpperCase();
        if (p.isBlank() || s == null) return false;
        for (String n : new String[] {s.matricNo(), s.admissionNo(), s.jambRegNo()}) {
            if (n != null && n.trim().length() >= 6 && p.contains(n.trim().toUpperCase())) return true;
        }
        return false;
    }

    /** what the student account opens with when it is carried over from the applicant's: the applicant's own bcrypt hash — or, for an
     *  account still on its first-login sentinel (V178), a fresh hash nobody knows with must-change on (V428: the JAMB number no longer
     *  opens anything; the student chooses a password in the session they continued, or through the reset link).
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
                // V579: a number the Registry corrected is answered as such, without saying the new one
                if (s == null && repo.correctedNumber(matricNo)) {
                    return new DomainRuleViolation("STUDENT_NUMBER_CORRECTED", "This matriculation number was corrected.",
                            new DomainRuleViolation.Remedy("Sign in with your new matriculation number. The University sent it to the e-mail and phone it holds for you; not received it? Ask the Registry or ICT Support.", "Registry"));
                }
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
            // the first sign-in: while the account is still on its first password, the number is that password and the change is
            // forced before anything else (V178, V122); once one is chosen, the student's own number opens nothing (V428)
            boolean firstSignIn = onFirstPassword(a) && firstPassword(password, matricNo);
            if (ownNumber(password, s) && !firstSignIn) {
                repo.event(matricNo, s.id(), "OWN_NUMBER_REFUSED", ip);
                throttle.count(Throttle.Door.STUDENT_SIGN_IN, ip);
                return ownNumberRefused();
            }
            boolean ok = firstSignIn || encoder.matches(password == null ? "" : password, a.passwordHash());
            if (ok && a.temporarySpent()) {
                /* V346: a temporary password from ICT Support opens one session, until its time; spent or lapsed, it opens nothing */
                repo.event(matricNo, s.id(), "TEMP_PASSWORD_SPENT", ip);
                return new DomainRuleViolation("AUTH_TEMP_PASSWORD_SPENT", "This temporary password has expired or was already used.",
                        new DomainRuleViolation.Remedy("Ask ICT Support for a reset link, or a new temporary password at the desk; it is good for one sign-in.", "ICT Support"));
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
            repo.event(matricNo, s.id(), firstSignIn ? "FIRST_SIGN_IN" : "SIGNED_IN", ip);
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
                        new DomainRuleViolation.Remedy("Your student account opens when your screening is successful, or on acceptance where no screening is needed. Until then, use the applicant portal.", "Registry"));
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
        StudentPortalRepository.Student s = repo.byId(student).orElse(null);
        boolean ok = encoder.matches(current == null ? "" : current, a.passwordHash());
        // an account still on its first password was opened by a door that already proved the student — the number at the first
        // sign-in, the applicant's own session continued, or the reset link — on a hash nobody knows: the number it opened with is
        // accepted as the current password, or none at all (V428)
        if (!ok && onFirstPassword(a) && (current == null || current.isBlank() || ownNumber(current, s))) {
            ok = true;
        }
        if (!ok) {
            throw badCredentials();
        }
        if (next == null || next.length() < MIN_PASSWORD) {
            throw new DomainRuleViolation("APP_PASSWORD_SHORT", "Eight characters at the very least.",
                    new DomainRuleViolation.Remedy("Choose a longer password.", "You"));
        }
        if (ownNumber(next, s) || holdsOwnNumber(next, s)) {
            throw new DomainRuleViolation("AUTH_PASSWORD_IS_NUMBER", "Your own number cannot be your password, or part of it.",
                    new DomainRuleViolation.Remedy("Choose a password that does not contain your matriculation, admission or JAMB number.", "You"));
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
        // V485: a session opened on the old password does not outlive its reset
        repo.endSessions(student, "password reset by ICT Support");
        UUID event = repo.event("", student, "TEMP_PASSWORD_ISSUED");
        return new Temporary(pw, until, event);
    }

    /* ── V485: the reset to the default credential at the ICT Support Desk ── */

    /** a second reset of the same student within this time is the same reset (a second click, a retried request) */
    static final Duration SAME_RESET = Duration.ofSeconds(60);

    /** what the desk is told: nothing about the password — whether this repeated a reset just made, whether the account was opened
     *  by it, whether it was locked and was unlocked, how many sessions were ended, and the sign-in log's event */
    public record DefaultReset(boolean alreadyDone, boolean opened, boolean wasLocked, boolean unlocked, int sessionsEnded, UUID eventId) {
    }

    /** the desk's words for why the reset to the default credential may not be made (iam.student_reset_check) */
    public static DomainRuleViolation resetRefusal(String code, String status) {
        return switch (code == null ? "" : code) {
            case "RESET_NO_MATRIC" -> new DomainRuleViolation(code,
                    "THIS STUDENT DOES NOT HAVE A VALID MATRICULATION NUMBER. PASSWORD RESET USING THE DEFAULT STUDENT CREDENTIAL POLICY IS NOT AVAILABLE.",
                    new DomainRuleViolation.Remedy("Send the reset link to the student's email or phone, or issue a temporary password on the student's ticket. The Registry issues matriculation numbers.", "ICT Support"));
            case "RESET_STATUS" -> new DomainRuleViolation(code, "THIS STUDENT ACCOUNT IS NOT ACTIVE" + (status == null ? "" : " (" + status + ")") + ".",
                    new DomainRuleViolation.Remedy("The Registry decides a student's status; the desk resets only the statuses its policy allows.", "Registry"));
            case "RESET_MERGED_RECORD" -> new DomainRuleViolation(code, "THIS RECORD WAS MERGED INTO ANOTHER STUDENT RECORD.",
                    new DomainRuleViolation.Remedy("Find the student's live record and reset that one.", "ICT Support"));
            case "RESET_DISABLED" -> new DomainRuleViolation(code, "PASSWORD RESET TO THE DEFAULT CREDENTIAL IS SWITCHED OFF.",
                    new DomainRuleViolation.Remedy("The Head of the ICT Support Desk or the Director of ICT switches it on in ICT Support Settings.", "Head of ICT Support Desk"));
            default -> new DomainRuleViolation("RESET_REFUSED", "PASSWORD RESET COULD NOT BE COMPLETED. PLEASE TRY AGAIN OR CONTACT THE ICT DIRECTOR.",
                    new DomainRuleViolation.Remedy("Try again; if it fails again, tell the Director of ICT.", "Directorate of ICT"));
        };
    }

    /**
     * V485: ICT Support resets the student's one account to the default credential — the matriculation number, as username and,
     * until the student chooses their own, as password. Nothing about the number is written: the account is put on its first
     * password (a hash of a secret nobody holds, must-change on, any temporary password withdrawn), the state in which the sign-in
     * door accepts the number the student signs in with and forces the change before anything else. The student is held while
     * it is made, so a second click within a minute is the same reset; every session the student holds is ended; the lockout is
     * cleared only when {@code unlock}. Refused, in the desk's words, when iam.student_reset_check says it may not be made.
     */
    @Transactional
    public DefaultReset resetToDefault(UUID student, boolean unlock) {
        return resetToDefault(student, unlock, null);
    }

    /**
     * V559: the hash of a secret nobody holds, made once for a bulk reset and given to each of its students' accounts — the costly
     * part of a reset is this hash, and one unknown secret seals any number of accounts as well as one (V294 seals an upload so)
     */
    public String sealedHash() {
        byte[] secret = new byte[32];
        random.nextBytes(secret);
        return encoder.encode(HexFormat.of().formatHex(secret));
    }

    /** V559: the one reset to the default credential, with the sealed hash of a bulk reset given (null: one made for this reset) */
    @Transactional
    public DefaultReset resetToDefault(UUID student, boolean unlock, String sealed) {
        repo.holdStudent(student);
        Map<String, Object> check = repo.resetCheck(student).orElseThrow(() -> new NotFound("student", student));
        if (!Boolean.TRUE.equals(check.get("eligible"))) {
            throw resetRefusal((String) check.get("refusal"), (String) check.get("status"));
        }
        StudentPortalRepository.Account a = repo.account(student).orElse(null);
        OffsetDateTime now = OffsetDateTime.now();
        boolean locked = a != null && a.lockedUntil() != null && a.lockedUntil().isAfter(now);
        if (a != null && onFirstPassword(a) && a.supportResetAt() != null && a.supportResetAt().isAfter(now.minus(SAME_RESET))) {
            return new DefaultReset(true, false, locked, false, 0, null);
        }
        boolean opened = repo.resetToFirstPassword(student, sealed != null ? sealed : sealedHash(), unlock);
        int ended = repo.endSessions(student, "password reset by ICT Support");
        UUID event = repo.event("", student, "PASSWORD_RESET_BY_SUPPORT");
        if (locked && unlock) {
            repo.event("", student, "UNLOCKED_BY_SUPPORT");
        }
        return new DefaultReset(false, opened, locked, locked && unlock, ended, event);
    }

    /** V485: the student's own account, for the forced change: whether a change is required and whether ICT Support asked for it */
    public Map<String, Object> passwordStatus(UUID student) {
        StudentPortalRepository.Account a = repo.account(student).orElse(null);
        Map<String, Object> out = new java.util.LinkedHashMap<>();
        out.put("mustChange", a != null && a.mustChange());
        out.put("resetBySupport", a != null && a.mustChange() && a.supportResetAt() != null);
        out.put("temporary", a != null && a.temporary());
        out.put("firstPassword", a != null && onFirstPassword(a));
        return out;
    }

    /** the Registry opens or resets a student's account: a first password, changed at sign-in */
    @Transactional
    public Map<String, Object> open(UUID student, String firstPassword) {
        StudentPortalRepository.Student s = repo.byId(student).orElseThrow(() -> new NotFound("student", student));
        if (firstPassword == null || firstPassword.length() < MIN_PASSWORD) {
            throw new DomainRuleViolation("APP_PASSWORD_SHORT", "Eight characters at the very least.",
                    new DomainRuleViolation.Remedy("Give the student a first password of eight characters or more; they change it at sign-in.", "Registry"));
        }
        if (ownNumber(firstPassword, s)) {   // V428
            throw new DomainRuleViolation("AUTH_PASSWORD_IS_NUMBER", "A student's own number is never their password.",
                    new DomainRuleViolation.Remedy("Give a first password that is not the matriculation or admission number, or send the student the reset link.", "Registry"));
        }
        repo.openAccount(student, encoder.encode(firstPassword), true);
        repo.event("", student, "OPENED_BY_REGISTRY", null);
        return Map.of("studentId", student, "opened", true, "mustChange", true);
    }
}
