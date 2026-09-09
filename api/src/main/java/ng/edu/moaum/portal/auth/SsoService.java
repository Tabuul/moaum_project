package ng.edu.moaum.portal.auth;

import java.net.URI;
import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import java.security.SecureRandom;
import java.time.Instant;
import java.util.Arrays;
import java.util.Base64;
import java.util.HexFormat;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;

import ng.edu.moaum.portal.shared.AuditContext;
import ng.edu.moaum.portal.shared.AuditContextHolder;
import ng.edu.moaum.portal.shared.DomainRuleViolation;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Service;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;
import org.springframework.util.LinkedMultiValueMap;
import org.springframework.util.MultiValueMap;
import org.springframework.web.client.RestClient;

import tools.jackson.databind.JsonNode;
import tools.jackson.databind.json.JsonMapper;

/**
 * Single sign-on for staff through the University's OpenID Connect provider
 * (Keycloak): the authorization-code flow, the ID token verified with the
 * provider's published keys, a second factor required of staff when the
 * portal says so, and the person matched to the register — by staff number,
 * else by the username or email already on their credential. The portal's
 * own session and token follow, exactly as after a password sign-in.
 *
 * <p>Switched on by MOAUM_SSO_ISSUER, MOAUM_SSO_CLIENT_ID and
 * MOAUM_SSO_CLIENT_SECRET; until they are set, the sign-in page does not
 * offer it and this service says so.
 */
@Service
public class SsoService {

    private static final long STATE_WINDOW_SECONDS = 600;

    private final AuthRepository repo;
    private final TokenIssuer issuer;
    private final TransactionTemplate tx;
    private final RestClient http = RestClient.create();
    private final JsonMapper json = JsonMapper.builder().build();
    private final SecureRandom random = new SecureRandom();
    private final String issuerUri;
    private final String clientId;
    private final String clientSecret;
    private final boolean requireMfa;
    private final List<String> mfaAcr;
    private final String label;
    private final String staffClaim;
    private final String stateSecret;
    private volatile JsonNode discovery;
    private volatile OidcVerifier verifier;
    private volatile Instant verifierFetchedAt = Instant.EPOCH;

    SsoService(AuthRepository repo, TokenIssuer issuer, PlatformTransactionManager transactions,
               @Value("${moaum.sso.issuer:}") String issuerUri,
               @Value("${moaum.sso.client-id:}") String clientId,
               @Value("${moaum.sso.client-secret:}") String clientSecret,
               @Value("${moaum.sso.require-mfa:true}") boolean requireMfa,
               @Value("${moaum.sso.mfa-acr:mfa,otp,2fa,gold,silver}") String mfaAcr,
               @Value("${moaum.sso.label:Sign in with the University's single sign-on}") String label,
               @Value("${moaum.sso.staff-claim:staff_number}") String staffClaim,
               @Value("${moaum.auth.hmac-secret:}") String stateSecret) {
        this.repo = repo;
        this.issuer = issuer;
        this.tx = new TransactionTemplate(transactions);
        this.issuerUri = issuerUri == null ? "" : issuerUri.trim().replaceAll("/+$", "");
        this.clientId = clientId == null ? "" : clientId.trim();
        this.clientSecret = clientSecret == null ? "" : clientSecret;
        this.requireMfa = requireMfa;
        this.mfaAcr = Arrays.stream(mfaAcr.split(",")).map(String::trim).filter(s -> !s.isEmpty()).toList();
        this.label = label;
        this.staffClaim = staffClaim;
        this.stateSecret = stateSecret == null ? "" : stateSecret;
    }

    public boolean enabled() {
        return !issuerUri.isEmpty() && !clientId.isEmpty() && !clientSecret.isEmpty();
    }

    public Map<String, Object> describe() {
        return Map.of("enabled", enabled(), "label", label, "requireMfa", requireMfa, "issuer", enabled() ? issuerUri : "");
    }

    private void requireEnabled() {
        if (!enabled()) {
            throw new DomainRuleViolation("AUTH_SSO_OFF", "Single sign-on is not connected to this portal.",
                    new DomainRuleViolation.Remedy("Set MOAUM_SSO_ISSUER, MOAUM_SSO_CLIENT_ID and MOAUM_SSO_CLIENT_SECRET on the API service.", "Directorate of ICT"));
        }
        if (stateSecret.isBlank()) {
            throw new DomainRuleViolation("AUTH_SSO_SECRET", "The portal has no secret to sign the sign-in state with.",
                    new DomainRuleViolation.Remedy("MOAUM_AUTH_HMAC_SECRET is set on the API service.", "Directorate of ICT"));
        }
    }

    private JsonNode discovery() {
        if (discovery == null) {
            try {
                discovery = json.readTree(http.get().uri(issuerUri + "/.well-known/openid-configuration").retrieve().body(String.class));
            } catch (Exception unreachable) {
                throw new DomainRuleViolation("AUTH_SSO_PROVIDER", "The identity provider at " + issuerUri + " did not answer.",
                        new DomainRuleViolation.Remedy("Check MOAUM_SSO_ISSUER — the realm's address, for example https://sso.example.edu/realms/moaum.", "Directorate of ICT"));
            }
        }
        return discovery;
    }

    private OidcVerifier verifier(boolean refresh) {
        if (verifier == null || refresh || verifierFetchedAt.isBefore(Instant.now().minusSeconds(3600))) {
            String jwks = http.get().uri(discovery().path("jwks_uri").asString()).retrieve().body(String.class);
            verifier = new OidcVerifier(jwks);
            verifierFetchedAt = Instant.now();
        }
        return verifier;
    }

    /* ── the state: a nonce and a time, signed, so the callback answers a sign-in this portal started ── */

    private String hmac(String data) {
        try {
            Mac mac = Mac.getInstance("HmacSHA256");
            mac.init(new SecretKeySpec(stateSecret.getBytes(StandardCharsets.UTF_8), "HmacSHA256"));
            return Base64.getUrlEncoder().withoutPadding().encodeToString(mac.doFinal(data.getBytes(StandardCharsets.UTF_8)));
        } catch (Exception e) {
            throw new IllegalStateException(e);
        }
    }

    String newState(String nonce) {
        String body = Instant.now().getEpochSecond() + "." + nonce;
        return body + "." + hmac(body);
    }

    String nonceOf(String state) {
        String[] p = state == null ? new String[0] : state.split("\\.");
        if (p.length != 3 || !hmac(p[0] + "." + p[1]).equals(p[2])) {
            throw new DomainRuleViolation("AUTH_SSO_STATE", "The sign-in did not start from this portal.",
                    new DomainRuleViolation.Remedy("Start again from the portal's sign-in page.", "You"));
        }
        long at = Long.parseLong(p[0]);
        if (Instant.now().getEpochSecond() - at > STATE_WINDOW_SECONDS) {
            throw new DomainRuleViolation("AUTH_SSO_STATE_OLD", "The sign-in took longer than ten minutes.",
                    new DomainRuleViolation.Remedy("Start again from the portal's sign-in page.", "You"));
        }
        return p[1];
    }

    /** where the browser goes: the provider's authorization endpoint, with a signed state and a nonce */
    public Map<String, Object> start(String redirectUri) {
        requireEnabled();
        byte[] n = new byte[16];
        random.nextBytes(n);
        String nonce = HexFormat.of().formatHex(n);
        String state = newState(nonce);
        String url = discovery().path("authorization_endpoint").asString()
                + "?response_type=code&scope=" + enc("openid profile email")
                + "&client_id=" + enc(clientId) + "&redirect_uri=" + enc(redirectUri)
                + "&state=" + enc(state) + "&nonce=" + enc(nonce)
                + (requireMfa ? "&acr_values=" + enc(String.join(" ", mfaAcr)) : "");
        return Map.of("url", url, "state", state);
    }

    /** the code exchanged, the token verified, the person matched, the session opened */
    public AuthService.SignedIn callback(String code, String state, String redirectUri, String ip) {
        requireEnabled();
        String nonce = nonceOf(state);
        MultiValueMap<String, String> form = new LinkedMultiValueMap<>();
        form.add("grant_type", "authorization_code");
        form.add("code", code);
        form.add("redirect_uri", redirectUri);
        form.add("client_id", clientId);
        form.add("client_secret", clientSecret);
        JsonNode tokens;
        try {
            tokens = json.readTree(http.post().uri(URI.create(discovery().path("token_endpoint").asString()))
                    .contentType(MediaType.APPLICATION_FORM_URLENCODED).body(form).retrieve().body(String.class));
        } catch (Exception refusedByProvider) {
            throw new DomainRuleViolation("AUTH_SSO_EXCHANGE", "The identity provider did not accept the sign-in.",
                    new DomainRuleViolation.Remedy("Try again; if it persists, the client secret on the API service does not match the provider's.", "Directorate of ICT"));
        }
        String idToken = tokens.path("id_token").asString();
        Map<String, Object> claims;
        try {
            claims = verifier(false).verify(idToken, issuerUri, clientId, nonce, Instant.now());
        } catch (DomainRuleViolation first) {
            claims = verifier(true).verify(idToken, issuerUri, clientId, nonce, Instant.now());
        }
        if (requireMfa && !OidcVerifier.secondFactorCompleted(claims, mfaAcr)) {
            throw new DomainRuleViolation("AUTH_SSO_MFA", "Staff complete a second step to sign in, and the provider did not say one was completed.",
                    new DomainRuleViolation.Remedy("Enrol an authenticator on the University's sign-on and try again; the provider must put the amr or acr claim on the ID token.", "Directorate of ICT"));
        }
        String staffNumber = str(claims.get(staffClaim));
        String username = str(claims.get("preferred_username"));
        String email = str(claims.get("email"));
        AuthRepository.Person person = null;
        if (staffNumber != null && !staffNumber.isBlank()) {
            person = repo.personByStaffNumber(staffNumber.trim()).orElse(null);
        }
        if (person == null) {
            for (String candidate : List.of(username == null ? "" : username, email == null ? "" : email)) {
                if (!candidate.isBlank()) {
                    AuthRepository.Credential c = repo.byUsername(candidate.trim().toLowerCase()).orElse(null);
                    if (c != null) {
                        person = new AuthRepository.Person(c.personId(), c.surname(), c.givenNames(), c.staffNumber(), c.endedOn());
                        break;
                    }
                }
            }
        }
        if (person == null || person.endedOn() != null) {
            throw new DomainRuleViolation("AUTH_SSO_UNKNOWN", "The University's sign-on knows this person, but the portal's register does not.",
                    new DomainRuleViolation.Remedy("The Registry records the person and their office on the Users & roles screen, with the staff number the sign-on carries.", "Registrar"));
        }
        AuthRepository.Person who = person;
        String label = who.surname() + ", " + who.givenNames();
        return AuditContextHolder.with(new AuditContext(who.id(), "ict", "sign-in through single sign-on", null, null), () -> tx.execute(status -> {
            List<AuthRepository.Office> offices = repo.liveOffices(who.id());
            List<String> codes = offices.stream().map(AuthRepository.Office::officeCode).distinct().toList();
            String active = codes.isEmpty() ? "ict" : codes.getFirst();
            byte[] sid = new byte[32];
            random.nextBytes(sid);
            Instant end = Instant.now().plus(AuthService.SESSION_LENGTH);
            repo.openSession(sid, who.id(), active, end);
            repo.event(username == null ? (email == null ? "sso" : email) : username, who.id(), "SIGNED_IN", ip, sid);
            return new AuthService.SignedIn(issuer.issue(who.id(), label, codes, sid, end), end, who.id(), who.surname(), who.givenNames(), who.staffNumber(),
                    offices.stream().map(o -> Map.<String, Object>of("code", o.officeCode(), "label", o.label(), "scopeKind", o.scopeKind(),
                            "scopeId", o.scopeId() == null ? "" : o.scopeId(), "validTo", o.validTo() == null ? "" : o.validTo().toString())).toList(), false);
        }));
    }

    private static String str(Object o) {
        return o == null ? null : String.valueOf(o);
    }

    private static String enc(String s) {
        return URLEncoder.encode(s, StandardCharsets.UTF_8);
    }
}
