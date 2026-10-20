package ng.edu.moaum.portal.studentportal;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.security.SecureRandom;
import java.util.HexFormat;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.UUID;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.Authentication;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * V575: a contact a department uploaded, confirmed by the student. While unconfirmed no password reset link goes to it; the
 * student, signed in, has a six-digit code sent to it and enters it here (people.contact_code_issue / contact_code_check: three
 * codes an hour, fifteen minutes each, five tries), or says it is not theirs (people.contact_refuse: the field is emptied). The
 * code is made here and kept only as a hash.
 */
@RestController
@RequestMapping("/api/v1/me/contact")
@PreAuthorize("hasAuthority('OFFICE_student')")
class ContactConfirmController {

    private static final SecureRandom RANDOM = new SecureRandom();

    public record Field(@NotBlank @Pattern(regexp = "EMAIL|PHONE") String field) {
    }

    public record Code(@NotBlank @Pattern(regexp = "EMAIL|PHONE") String field, @NotBlank @Size(max = 12) String code) {
    }

    private final JdbcClient jdbc;

    ContactConfirmController(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    private static UUID id(Authentication auth) {
        return UUID.fromString(auth.getName());
    }

    /** the contacts on the record not yet confirmed (none when the student holds none) */
    @GetMapping("/pending")
    @Transactional(readOnly = true)
    Map<String, Object> pending(Authentication auth) {
        return pendingOf(id(auth));
    }

    Map<String, Object> pendingOf(UUID student) {
        Map<String, Object> out = new LinkedHashMap<>();
        jdbc.sql("SELECT unconfirmed_email, unconfirmed_phone FROM people.student_reset_reach(:s)").param("s", student).query().listOfRows().stream().findFirst()
                .ifPresent(r -> {
                    out.put("email", r.get("unconfirmed_email"));
                    out.put("phone", r.get("unconfirmed_phone"));
                });
        return out;
    }

    /** a code sent to the unconfirmed e-mail or phone */
    @PostMapping("/confirm/code")
    @Transactional
    Map<String, Object> sendCode(Authentication auth, @Valid @RequestBody Field body) {
        UUID student = id(auth);
        String code = String.format("%06d", RANDOM.nextInt(1_000_000));
        String to = jdbc.sql("SELECT people.contact_code_issue(:s, :f, :h)").param("s", student).param("f", body.field()).param("h", sha256(code))
                .query(String.class).single();
        if ("EMAIL".equals(body.field())) {
            jdbc.sql("SELECT platform.queue_notice('EMAIL', :to, :sub, :b, 'student', :s)")
                    .param("to", to).param("sub", "Your MOAUM confirmation code")
                    .param("b", "Your code to confirm this e-mail address on your MOAUM portal record is " + code + ". It works for fifteen minutes.\n\n"
                            + "Enter it on the portal where you asked for it. If you did not ask for it, ignore this message: the address is not confirmed, "
                            + "and nothing changes.")
                    .param("s", student).query().listOfRows();
        } else {
            jdbc.sql("SELECT platform.queue_notice('SMS', :to, :sub, :b, 'student', :s)")
                    .param("to", to).param("sub", "Your MOAUM confirmation code")
                    .param("b", "MOAUM: your code to confirm this phone on your portal record is " + code + " (15 minutes). Not you? Ignore this message.")
                    .param("s", student).query().listOfRows();
        }
        return Map.of("field", body.field(), "sentTo", mask(to, "EMAIL".equals(body.field())), "minutes", 15);
    }

    /** the code entered: confirmed, or the try counted (five at most) */
    @PostMapping("/confirm")
    @Transactional
    Map<String, Object> confirm(Authentication auth, @Valid @RequestBody Code body) {
        UUID student = id(auth);
        String outcome = jdbc.sql("SELECT people.contact_code_check(:s, :f, :h)").param("s", student).param("f", body.field())
                .param("h", sha256(body.code().trim())).query(String.class).single();
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("field", body.field());
        out.put("outcome", outcome);
        out.put("pending", pendingOf(student));
        return out;
    }

    /** not theirs: the field is emptied, and the department's upload is told by its counts */
    @PostMapping("/not-mine")
    @Transactional
    Map<String, Object> notMine(Authentication auth, @Valid @RequestBody Field body) {
        UUID student = id(auth);
        jdbc.sql("SELECT people.contact_refuse(:s, :f)").param("s", student).param("f", body.field()).query(String.class).single();
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("field", body.field());
        out.put("outcome", "REFUSED");
        out.put("pending", pendingOf(student));
        return out;
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

    private static String sha256(String s) {
        try {
            return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(s.getBytes(StandardCharsets.UTF_8)));
        } catch (NoSuchAlgorithmException e) {
            throw new IllegalStateException(e);
        }
    }
}
