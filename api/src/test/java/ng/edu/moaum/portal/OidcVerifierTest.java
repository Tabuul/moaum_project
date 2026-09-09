package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.math.BigInteger;
import java.nio.charset.StandardCharsets;
import java.security.KeyPair;
import java.security.KeyPairGenerator;
import java.security.Signature;
import java.security.interfaces.RSAPublicKey;
import java.time.Instant;
import java.util.Base64;
import java.util.List;
import java.util.Map;

import ng.edu.moaum.portal.auth.OidcVerifier;
import ng.edu.moaum.portal.shared.DomainRuleViolation;

import org.junit.jupiter.api.Test;

/** The ID token is verified with the JDK alone: the signature, the issuer, the audience, the expiry, the nonce, and the second factor. */
class OidcVerifierTest {

    static final String ISSUER = "https://sso.example.edu/realms/moaum";
    static final String CLIENT = "moaum-portal";
    static final Base64.Encoder B64 = Base64.getUrlEncoder().withoutPadding();

    static KeyPair keys() throws Exception {
        KeyPairGenerator g = KeyPairGenerator.getInstance("RSA");
        g.initialize(2048);
        return g.generateKeyPair();
    }

    static String jwks(KeyPair kp, String kid) {
        RSAPublicKey pub = (RSAPublicKey) kp.getPublic();
        return "{\"keys\":[{\"kty\":\"RSA\",\"kid\":\"" + kid + "\",\"alg\":\"RS256\",\"n\":\"" + B64.encodeToString(unsigned(pub.getModulus()))
                + "\",\"e\":\"" + B64.encodeToString(unsigned(pub.getPublicExponent())) + "\"}]}";
    }

    static byte[] unsigned(BigInteger i) {
        byte[] b = i.toByteArray();
        return b[0] == 0 ? java.util.Arrays.copyOfRange(b, 1, b.length) : b;
    }

    static String token(KeyPair kp, String kid, String payload) throws Exception {
        String head = B64.encodeToString(("{\"alg\":\"RS256\",\"kid\":\"" + kid + "\"}").getBytes(StandardCharsets.UTF_8));
        String body = B64.encodeToString(payload.getBytes(StandardCharsets.UTF_8));
        Signature s = Signature.getInstance("SHA256withRSA");
        s.initSign(kp.getPrivate());
        s.update((head + "." + body).getBytes(StandardCharsets.US_ASCII));
        return head + "." + body + "." + B64.encodeToString(s.sign());
    }

    static String payload(String extra) {
        long exp = Instant.now().plusSeconds(300).getEpochSecond();
        return "{\"iss\":\"" + ISSUER + "\",\"aud\":\"" + CLIENT + "\",\"exp\":" + exp + ",\"nonce\":\"n1\",\"preferred_username\":\"demo.registrar\",\"staff_number\":\"MOAUM/DEMO/010\"" + extra + "}";
    }

    @Test
    void aTokenSignedByThePublishedKeyVerifiesAndItsClaimsAreRead() throws Exception {
        KeyPair kp = keys();
        OidcVerifier v = new OidcVerifier(jwks(kp, "k1"));
        Map<String, Object> claims = v.verify(token(kp, "k1", payload(",\"amr\":[\"pwd\",\"otp\"]")), ISSUER, CLIENT, "n1", Instant.now());
        assertThat(claims.get("staff_number")).isEqualTo("MOAUM/DEMO/010");
        assertThat(OidcVerifier.secondFactorCompleted(claims, List.of("mfa"))).isTrue();
    }

    @Test
    void aTokenSignedByAnotherKeyTheWrongAudienceOrAnOldExpiryIsRefused() throws Exception {
        KeyPair kp = keys();
        KeyPair other = keys();
        OidcVerifier v = new OidcVerifier(jwks(kp, "k1"));
        assertThatThrownBy(() -> v.verify(token(other, "k1", payload("")), ISSUER, CLIENT, "n1", Instant.now())).isInstanceOf(DomainRuleViolation.class);
        assertThatThrownBy(() -> v.verify(token(kp, "k1", payload("")), ISSUER, "somebody-else", "n1", Instant.now())).isInstanceOf(DomainRuleViolation.class);
        assertThatThrownBy(() -> v.verify(token(kp, "k1", payload("")), ISSUER, CLIENT, "n1", Instant.now().plusSeconds(3600))).isInstanceOf(DomainRuleViolation.class);
        assertThatThrownBy(() -> v.verify(token(kp, "k1", payload("")), ISSUER, CLIENT, "another-nonce", Instant.now())).isInstanceOf(DomainRuleViolation.class);
        assertThatThrownBy(() -> v.verify(token(kp, "k1", payload("")), "https://elsewhere", CLIENT, "n1", Instant.now())).isInstanceOf(DomainRuleViolation.class);
    }

    @Test
    void theSecondFactorIsReadFromAmrOrAcrAndAPasswordAloneIsNotOne() throws Exception {
        KeyPair kp = keys();
        OidcVerifier v = new OidcVerifier(jwks(kp, "k1"));
        Map<String, Object> pwdOnly = v.verify(token(kp, "k1", payload(",\"amr\":[\"pwd\"],\"acr\":\"1\"")), ISSUER, CLIENT, "n1", Instant.now());
        assertThat(OidcVerifier.secondFactorCompleted(pwdOnly, List.of("mfa", "otp", "gold"))).isFalse();
        Map<String, Object> byAcr = v.verify(token(kp, "k1", payload(",\"acr\":\"gold\"")), ISSUER, CLIENT, "n1", Instant.now());
        assertThat(OidcVerifier.secondFactorCompleted(byAcr, List.of("mfa", "otp", "gold"))).isTrue();
        assertThat(OidcVerifier.secondFactorCompleted(v.verify(token(kp, "k1", payload("")), ISSUER, CLIENT, "n1", Instant.now()), List.of("mfa"))).isFalse();
    }
}
