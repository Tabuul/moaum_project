package ng.edu.moaum.portal;

import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.util.Date;
import java.util.List;
import java.util.UUID;

import com.nimbusds.jose.JOSEException;
import com.nimbusds.jose.JWSAlgorithm;
import com.nimbusds.jose.JWSHeader;
import com.nimbusds.jose.crypto.MACSigner;
import com.nimbusds.jwt.JWTClaimsSet;
import com.nimbusds.jwt.SignedJWT;

/** Mints the tokens Keycloak would, signed with the development secret. */
public final class TestTokens {

    public static final String SECRET = "test-only-secret-of-at-least-thirty-two-bytes";

    private TestTokens() {
    }

    public static String token(UUID subject, List<String> offices) {
        return token(subject, offices, null);
    }

    /** V437: a token that names a server-side session (its id in hex), so the session's own rules apply to it */
    public static String token(UUID subject, List<String> offices, String sessionHex) {
        try {
            JWTClaimsSet.Builder b = new JWTClaimsSet.Builder()
                    .subject(subject.toString())
                    .issueTime(new Date())
                    .expirationTime(Date.from(Instant.now().plusSeconds(600)))
                    .claim("offices", offices);
            if (sessionHex != null) b.claim("sid", sessionHex);
            JWTClaimsSet claims = b.build();
            SignedJWT jwt = new SignedJWT(new JWSHeader(JWSAlgorithm.HS256), claims);
            jwt.sign(new MACSigner(SECRET.getBytes(StandardCharsets.UTF_8)));
            return jwt.serialize();
        } catch (JOSEException e) {
            throw new IllegalStateException(e);
        }
    }
}
