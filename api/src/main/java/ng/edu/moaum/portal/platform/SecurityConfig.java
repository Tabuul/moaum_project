package ng.edu.moaum.portal.platform;

import java.nio.charset.StandardCharsets;
import java.util.Arrays;
import java.util.Collection;
import java.util.List;

import javax.crypto.spec.SecretKeySpec;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.security.config.Customizer;
import org.springframework.security.config.annotation.method.configuration.EnableMethodSecurity;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.core.GrantedAuthority;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.jwt.JwtDecoder;
import org.springframework.security.oauth2.jwt.JwtDecoders;
import org.springframework.security.oauth2.jwt.NimbusJwtDecoder;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationConverter;
import org.springframework.security.oauth2.server.resource.web.BearerTokenResolver;
import org.springframework.security.oauth2.server.resource.web.DefaultBearerTokenResolver;
import org.springframework.security.oauth2.server.resource.web.authentication.BearerTokenAuthenticationFilter;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.security.web.servlet.util.matcher.PathPatternRequestMatcher;
import org.springframework.security.web.util.matcher.RequestMatcher;
import org.springframework.web.cors.CorsConfiguration;
import org.springframework.web.cors.CorsConfigurationSource;
import org.springframework.web.cors.UrlBasedCorsConfigurationSource;

/**
 * Authentication is Keycloak's; authorisation is ours (ADR-004).
 *
 * <p>The token's {@code offices} claim becomes one {@code OFFICE_<code>}
 * authority per office, which is what controllers check. Scope (a HOD of
 * Mathematics, not of Physics) is the next layer and lives in
 * {@code iam.office_assignment}; it is not modelled in the token.
 */
@Configuration
@EnableMethodSecurity
class SecurityConfig {

    static final String OFFICE_AUTHORITY_PREFIX = "OFFICE_";

    /**
     * The public doors: reached by people who are not signed in (the application forms, the sign-ins, the forgotten-password
     * pages, the verification pages, the public figures) and by the gateways and providers with credentials of their own.
     * None of them reads the token a request may carry, and none is answered from it (see {@link #publicDoorsReadNoToken()}).
     */
    static final String[] PUBLIC_DOORS = {"/actuator/health", "/actuator/health/**", "/api/v1/platform/status",
            "/api/v1/auth/sign-in", "/api/v1/auth/bootstrap", "/api/v1/auth/offices",
            "/api/v1/auth/forgot", "/api/v1/auth/reset",
            "/api/v1/auth/sso", "/api/v1/auth/sso/start", "/api/v1/auth/sso/callback",
            "/api/v1/applicant/lookup", "/api/v1/applicant/register", "/api/v1/applicant/sign-in",
            "/api/v1/applicant/cce/lookup", "/api/v1/applicant/cce/register",
            // V446: the Preliminary Science application is started online, with no list to look up
            "/api/v1/applicant/preliminary/register",
            "/api/v1/applicant/forgot", "/api/v1/applicant/reset",
            "/api/v1/payments/webhook/paystack", "/api/v1/payments/webhook/flutterwave",
            "/api/v1/payments/webhook/quickteller", "/api/v1/payments/quickteller/start", "/api/v1/payments/quickteller/return",
            "/api/v1/payments/paydirect/validate", "/api/v1/payments/paydirect/notify", "/api/v1/payments/paydirect/interswitch",
            // Oct 2026: the same doors with a key in the address (the key is the credential; see PaymentsController)
            "/api/v1/payments/paydirect/validate/*", "/api/v1/payments/paydirect/notify/*", "/api/v1/payments/paydirect/interswitch/*",
            "/api/v1/student-auth/sign-in",
            "/api/v1/pg/apply", "/api/v1/pg/programmes", "/api/v1/pg/status",
            "/api/v1/pg/sign-in", "/api/v1/pg/referee/**",
            "/api/v1/jupeb/options", "/api/v1/jupeb/apply", "/api/v1/jupeb/sign-in", "/api/v1/jupeb/forgot", "/api/v1/jupeb/reset",
            "/api/v1/verify/**", "/api/v1/helpdesk/track", "/api/v1/helpdesk/sign-in-help", "/api/v1/helpdesk/sign-in-help/check", "/api/v1/public/**",
            "/api/v1/examiners/invitation/*", "/api/v1/examiners/activate",
            // V385: the Post-UTME CBT door and result checking — public, verified by JAMB number and a second factor, throttled
            "/api/v1/putme/cbt/public", "/api/v1/putme/cbt/verify", "/api/v1/putme/results/check",
            // V438: the providers' delivery reports, behind the token the Directorate of ICT generated
            "/api/v1/notices/receipts/*",
            // V511: the integration door; the API key is the credential, checked by the database on every call
            "/api/integration/v1/**"};

    @Bean
    SecurityFilterChain api(HttpSecurity http, SessionGuard sessions) throws Exception {
        http.csrf(csrf -> csrf.disable())
                .cors(cors -> cors.configurationSource(publicCors()))
                .sessionManagement(session -> session.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
                .authorizeHttpRequests(requests -> requests
                        .requestMatchers(PUBLIC_DOORS).permitAll()
                        .anyRequest().authenticated())
                .oauth2ResourceServer(oauth2 -> oauth2.bearerTokenResolver(publicDoorsReadNoToken())
                        .jwt(jwt -> jwt.jwtAuthenticationConverter(authenticationConverter())))
                .addFilterAfter(new AuditContextFilter(sessions), BearerTokenAuthenticationFilter.class);
        return http.build();
    }

    /**
     * A public door reads no token (Oct 2026). The portal's browser side forwards whatever session cookie the browser
     * holds to every call it makes for a page, the public doors included, and a token that no longer opens anything — its
     * session ended by the server for idleness or signed out elsewhere, or past its time — was refused here before the
     * door was reached: the bearer filter answered 401 for a token it could not accept, and {@link AuditContextFilter}
     * for a session that had ended. So a JUPEB candidate whose earlier session had lapsed, or anyone on a computer another
     * person had signed in on, found the application form refused on submission with "The request failed". A door that
     * {@link #PUBLIC_DOORS permits anyone} is answered as it answers anyone: the token is not read there, and the door's
     * own rules (its validation, the window, the credentials it asks for) decide. Every other path reads the token as
     * before, and an ended session is still refused there.
     */
    static BearerTokenResolver publicDoorsReadNoToken() {
        DefaultBearerTokenResolver bearer = new DefaultBearerTokenResolver();
        List<RequestMatcher> doors = Arrays.stream(PUBLIC_DOORS).map(PathPatternRequestMatcher::pathPattern).map(RequestMatcher.class::cast).toList();
        return request -> doors.stream().anyMatch(door -> door.matches(request)) ? null : bearer.resolve(request);
    }

    /**
     * The University's website, on its own domain, reads the public figures
     * ({@code /api/v1/public/**}) straight from the browser: those paths answer any
     * origin, GET only, without credentials. Every other path stays same-origin —
     * the portal's own frontend calls the API server-side — so no CORS headers are
     * issued for them and a cross-origin preflight to them is refused.
     */
    private static CorsConfigurationSource publicCors() {
        CorsConfiguration open = new CorsConfiguration();
        open.setAllowedOrigins(List.of("*"));
        open.setAllowedMethods(List.of("GET", "HEAD", "OPTIONS"));
        open.setAllowedHeaders(List.of("Accept", "Content-Type"));
        open.setAllowCredentials(false);
        open.setMaxAge(3600L);
        UrlBasedCorsConfigurationSource source = new UrlBasedCorsConfigurationSource();
        source.registerCorsConfiguration("/api/v1/public/**", open);
        return source;
    }

    /**
     * The decoder. A shared secret ({@code MOAUM_AUTH_HMAC_SECRET}) is for
     * development and tests, where there is no Keycloak; an issuer URI is for
     * everything else. Neither set is a configuration error, reported at boot.
     */
    @Bean
    JwtDecoder jwtDecoder(@Value("${moaum.auth.hmac-secret:}") String hmacSecret,
                          @Value("${moaum.auth.issuer-uri:}") String issuerUri) {
        if (hmacSecret != null && !hmacSecret.isBlank()) {
            byte[] key = hmacSecret.getBytes(StandardCharsets.UTF_8);
            if (key.length < 32) {
                throw new IllegalStateException("moaum.auth.hmac-secret must be at least 32 bytes");
            }
            return NimbusJwtDecoder.withSecretKey(new SecretKeySpec(key, "HmacSHA256")).build();
        }
        if (issuerUri != null && !issuerUri.isBlank()) {
            return JwtDecoders.fromIssuerLocation(issuerUri);
        }
        throw new IllegalStateException(
                "no way to verify tokens: set MOAUM_AUTH_ISSUER_URI (Keycloak) or, for development only, MOAUM_AUTH_HMAC_SECRET");
    }

    static JwtAuthenticationConverter authenticationConverter() {
        JwtAuthenticationConverter converter = new JwtAuthenticationConverter();
        converter.setJwtGrantedAuthoritiesConverter(SecurityConfig::authorities);
        return converter;
    }

    static Collection<GrantedAuthority> authorities(Jwt jwt) {
        List<String> offices = AuditContextFilter.offices(jwt);
        return offices.stream()
                .map(office -> (GrantedAuthority) new SimpleGrantedAuthority(OFFICE_AUTHORITY_PREFIX + office))
                .toList();
    }
}
