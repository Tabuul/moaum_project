package ng.edu.moaum.portal.shared;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.SecureRandom;
import java.util.HexFormat;
import java.util.Locale;

import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

/**
 * V360: the check code a printed document's QR carries — a receipt, an examination card, a course registration form, a
 * results statement, a postgraduate offer letter. The public verification page shows the University's record only when
 * the code matches.
 *
 * <p>Until V360 the code was a plain SHA-256 of what the document already shows (the matric number, the session, the
 * semester; the application number), so anyone who read the formula could make a valid code for any student and read
 * their name, photograph, courses or grades. The code is now an HMAC under a key only the API holds: twelve hex digits,
 * as before, so the documents look the same. The key is derived from {@code moaum.qr.secret} when it is set, else from
 * the API's signing secret ({@code moaum.auth.hmac-secret}) — a key of its own may be set later without a code change,
 * and a change of either makes the codes already printed stop verifying (the student prints the document again).
 *
 * <p>The old codes are recognised by {@link #legacy}, so the verifier can keep honouring a document printed before the
 * change on its own terms (see VerifyController).
 */
@Component
public class CheckCodes {

    private static final Logger LOG = LoggerFactory.getLogger(CheckCodes.class);

    public enum Kind { RECEIPT, EXAM, REG, RESULT, PG_OFFER }

    private final byte[] key;

    CheckCodes(@Value("${moaum.qr.secret:}") String qrSecret, @Value("${moaum.auth.hmac-secret:}") String authSecret) {
        String secret = qrSecret != null && !qrSecret.isBlank() ? qrSecret : authSecret;
        if (secret == null || secret.isBlank()) {
            byte[] r = new byte[32];
            new SecureRandom().nextBytes(r);
            this.key = r;
            LOG.warn("no moaum.qr.secret or moaum.auth.hmac-secret: check codes are signed with a key that lasts until this instance restarts");
        } else {
            this.key = hmac(secret.getBytes(StandardCharsets.UTF_8), "MOAUM-QR-CHECK-v1");
        }
    }

    /** the signed code for a document: twelve upper-case hex digits */
    public String sign(Kind kind, String... parts) {
        return HexFormat.of().formatHex(hmac(key, payload(kind, parts))).substring(0, 12).toUpperCase(Locale.ROOT);
    }

    /** whether a code is the signed one, compared in constant time */
    public boolean signed(String code, Kind kind, String... parts) {
        return same(code, sign(kind, parts));
    }

    /** whether a code is the one the document carried before V360 (the plain digest of its printed facts) */
    public static boolean legacy(String code, Kind kind, String... parts) {
        String payload = switch (kind) {
            case RECEIPT -> part(parts, 0) + "|" + part(parts, 1);
            case EXAM -> "EXAM|" + part(parts, 0) + "|" + part(parts, 1) + "|" + part(parts, 2);
            case REG -> "REG|" + part(parts, 0) + "|" + part(parts, 1) + "|" + part(parts, 2);
            case RESULT -> "RESULT|" + part(parts, 0) + "|" + part(parts, 1) + "|" + part(parts, 2);
            case PG_OFFER -> part(parts, 0) + "|MOAUM-PG-OFFER";
        };
        try {
            byte[] d = MessageDigest.getInstance("SHA-256").digest(payload.getBytes(StandardCharsets.UTF_8));
            return same(code, HexFormat.of().formatHex(d).substring(0, 12).toUpperCase(Locale.ROOT));
        } catch (java.security.NoSuchAlgorithmException e) {
            throw new IllegalStateException(e);
        }
    }

    private static String payload(Kind kind, String... parts) {
        StringBuilder sb = new StringBuilder(kind.name());
        for (int i = 0; i < parts.length; i++) sb.append('|').append(part(parts, i));
        return sb.toString();
    }

    private static String part(String[] parts, int i) {
        return i < parts.length && parts[i] != null ? parts[i] : "";
    }

    private static boolean same(String code, String expected) {
        if (code == null) return false;
        String c = code.trim().toUpperCase(Locale.ROOT);
        return MessageDigest.isEqual(c.getBytes(StandardCharsets.UTF_8), expected.getBytes(StandardCharsets.UTF_8));
    }

    private static byte[] hmac(byte[] k, String message) {
        try {
            Mac mac = Mac.getInstance("HmacSHA256");
            mac.init(new SecretKeySpec(k, "HmacSHA256"));
            return mac.doFinal(message.getBytes(StandardCharsets.UTF_8));
        } catch (java.security.GeneralSecurityException e) {
            throw new IllegalStateException(e);
        }
    }
}
