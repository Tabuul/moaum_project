package ng.edu.moaum.portal.auth;

import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.util.Date;
import java.util.HexFormat;
import java.util.List;
import java.util.UUID;

import com.nimbusds.jose.JOSEException;
import com.nimbusds.jose.JWSAlgorithm;
import com.nimbusds.jose.JWSHeader;
import com.nimbusds.jose.crypto.MACSigner;
import com.nimbusds.jwt.JWTClaimsSet;
import com.nimbusds.jwt.SignedJWT;

import ng.edu.moaum.portal.shared.DomainRuleViolation;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

/**
 * Mints the token a sign-in issues, signed with the same secret the API
 * verifies with. When the API verifies against Keycloak instead, sign-in
 * happens there and this issuer refuses by name.
 */
@Component
public class TokenIssuer {

    private final byte[] key;

    TokenIssuer(@Value("${moaum.auth.hmac-secret:}") String hmacSecret) {
        this.key = hmacSecret == null || hmacSecret.isBlank() ? null : hmacSecret.getBytes(StandardCharsets.UTF_8);
    }

    public boolean available() {
        return key != null;
    }

    public String issue(UUID person, String name, List<String> offices, byte[] sessionId, Instant expires) {
        return issue(person, name, offices, sessionId, expires, null);
    }

    /** V521: a student's portal opened by ICT Support — the student's token, naming the agent who views (read-only on the API) */
    public String issueSupportView(UUID student, String name, byte[] sessionId, Instant expires, UUID agent) {
        return issue(student, name, List.of("student"), sessionId, expires, agent);
    }

    private String issue(UUID person, String name, List<String> offices, byte[] sessionId, Instant expires, UUID viewer) {
        if (key == null) {
            throw new DomainRuleViolation("AUTH_SIGN_IN_ELSEWHERE", "This portal verifies tokens issued by the University's identity provider; sign in there.",
                    new DomainRuleViolation.Remedy("Use the single sign-on page.", "Directorate of ICT"));
        }
        try {
            JWTClaimsSet.Builder builder = new JWTClaimsSet.Builder()
                    .subject(person.toString())
                    .issueTime(new Date())
                    .expirationTime(Date.from(expires))
                    .claim("offices", offices)
                    .claim("sid", HexFormat.of().formatHex(sessionId))
                    .claim("name", name);
            if (viewer != null) builder.claim("support_view", viewer.toString());
            JWTClaimsSet claims = builder.build();
            SignedJWT jwt = new SignedJWT(new JWSHeader(JWSAlgorithm.HS256), claims);
            jwt.sign(new MACSigner(key));
            return jwt.serialize();
        } catch (JOSEException e) {
            throw new IllegalStateException("could not sign the token", e);
        }
    }
}
