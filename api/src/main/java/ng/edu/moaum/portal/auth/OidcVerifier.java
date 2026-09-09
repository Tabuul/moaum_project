package ng.edu.moaum.portal.auth;

import java.math.BigInteger;
import java.nio.charset.StandardCharsets;
import java.security.KeyFactory;
import java.security.PublicKey;
import java.security.Signature;
import java.security.spec.RSAPublicKeySpec;
import java.time.Instant;
import java.util.Base64;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import ng.edu.moaum.portal.shared.DomainRuleViolation;

import tools.jackson.databind.JsonNode;
import tools.jackson.databind.json.JsonMapper;

/**
 * Verifies an OpenID Connect ID token the way the identity provider's own
 * library would, with nothing but the JDK: the signature under the RSA key
 * the provider publishes (RS256), the issuer, the audience, the expiry, and
 * — for staff — that a second factor was actually completed, read from the
 * {@code amr} or {@code acr} claim the provider puts on the token.
 */
public final class OidcVerifier {

    private static final Base64.Decoder URL = Base64.getUrlDecoder();
    private final JsonMapper json = JsonMapper.builder().build();
    private final Map<String, PublicKey> keys = new HashMap<>();

    /** the provider's keys, from its JWKS document */
    public OidcVerifier(String jwksJson) {
        try {
            JsonNode set = json.readTree(jwksJson);
            for (JsonNode k : set.path("keys")) {
                if (!"RSA".equals(k.path("kty").asString()) || k.path("n").isMissingNode()) {
                    continue;
                }
                BigInteger n = new BigInteger(1, URL.decode(k.path("n").asString()));
                BigInteger e = new BigInteger(1, URL.decode(k.path("e").asString()));
                keys.put(k.path("kid").asString(), KeyFactory.getInstance("RSA").generatePublic(new RSAPublicKeySpec(n, e)));
            }
        } catch (Exception unreadable) {
            throw refused("The identity provider's keys could not be read.", "Check MOAUM_SSO_ISSUER and that the provider publishes a JWKS document.");
        }
    }

    public int keyCount() {
        return keys.size();
    }

    /** the token's claims, once every check has passed */
    public Map<String, Object> verify(String idToken, String issuer, String clientId, String expectedNonce, Instant now) {
        String[] parts = idToken == null ? new String[0] : idToken.split("\\.");
        if (parts.length != 3) {
            throw refused("The identity provider did not return a token.", "Try the single sign-on again.");
        }
        JsonNode header;
        JsonNode claims;
        try {
            header = json.readTree(URL.decode(parts[0]));
            claims = json.readTree(URL.decode(parts[1]));
        } catch (Exception unreadable) {
            throw refused("The token from the identity provider could not be read.", "Try the single sign-on again.");
        }
        if (!"RS256".equals(header.path("alg").asString())) {
            throw refused("The token is not signed with RS256.", "The provider's client is configured for RS256 ID tokens.");
        }
        PublicKey key = keys.get(header.path("kid").asString());
        if (key == null && keys.size() == 1) {
            key = keys.values().iterator().next();
        }
        if (key == null) {
            throw refused("The token is signed with a key the provider does not publish.", "The provider's keys were fetched afresh; try again.");
        }
        try {
            Signature sig = Signature.getInstance("SHA256withRSA");
            sig.initVerify(key);
            sig.update((parts[0] + "." + parts[1]).getBytes(StandardCharsets.US_ASCII));
            if (!sig.verify(URL.decode(parts[2]))) {
                throw refused("The token's signature does not verify.", "Try the single sign-on again; if it persists, the provider's keys have rotated.");
            }
        } catch (DomainRuleViolation r) {
            throw r;
        } catch (Exception broken) {
            throw refused("The token's signature could not be checked.", "Try the single sign-on again.");
        }
        if (!issuer.equals(claims.path("iss").asString())) {
            throw refused("The token was issued by " + claims.path("iss").asString() + ", not by the University's provider.", "MOAUM_SSO_ISSUER names the realm the portal trusts.");
        }
        JsonNode aud = claims.path("aud");
        boolean audienceOk = aud.isArray() ? stream(aud).contains(clientId) : clientId.equals(aud.asString());
        if (!audienceOk) {
            throw refused("The token was not issued for this portal.", "MOAUM_SSO_CLIENT_ID is the client the provider issued the token to.");
        }
        if (claims.path("exp").isMissingNode() || Instant.ofEpochSecond(claims.path("exp").asLong()).isBefore(now)) {
            throw refused("The token has expired.", "Try the single sign-on again.");
        }
        if (expectedNonce != null && !expectedNonce.equals(claims.path("nonce").asString())) {
            throw refused("The token does not answer this sign-in.", "Try the single sign-on again from the portal's own page.");
        }
        Map<String, Object> out = new HashMap<>();
        claims.properties().forEach(e -> out.put(e.getKey(), e.getValue().isArray() ? stream(e.getValue()) : e.getValue().asString()));
        return out;
    }

    /** whether the claims say a second factor was completed: {@code amr} carries one of the factors, or {@code acr} is one of the levels named */
    public static boolean secondFactorCompleted(Map<String, Object> claims, List<String> acrLevels) {
        Object amr = claims.get("amr");
        if (amr instanceof List<?> factors) {
            for (Object f : factors) {
                String s = String.valueOf(f).toLowerCase();
                if (List.of("mfa", "otp", "hwk", "swk", "sms", "webauthn", "fido", "totp").contains(s)) {
                    return true;
                }
            }
        }
        Object acr = claims.get("acr");
        return acr != null && acrLevels.contains(String.valueOf(acr));
    }

    private static List<String> stream(JsonNode array) {
        List<String> out = new java.util.ArrayList<>();
        array.forEach(n -> out.add(n.asString()));
        return out;
    }

    private static DomainRuleViolation refused(String what, String remedy) {
        return new DomainRuleViolation("AUTH_SSO_TOKEN", what, new DomainRuleViolation.Remedy(remedy, "Directorate of ICT"));
    }
}
