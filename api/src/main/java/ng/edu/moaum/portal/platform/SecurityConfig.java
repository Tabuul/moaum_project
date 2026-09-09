package ng.edu.moaum.portal.platform;

import java.nio.charset.StandardCharsets;
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
import org.springframework.security.oauth2.server.resource.web.authentication.BearerTokenAuthenticationFilter;
import org.springframework.security.web.SecurityFilterChain;

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

    @Bean
    SecurityFilterChain api(HttpSecurity http, SessionGuard sessions) throws Exception {
        http.csrf(csrf -> csrf.disable())
                .sessionManagement(session -> session.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
                .authorizeHttpRequests(requests -> requests
                        .requestMatchers("/actuator/health", "/actuator/health/**", "/api/v1/platform/status",
                                "/api/v1/auth/sign-in", "/api/v1/auth/bootstrap", "/api/v1/auth/offices",
                                "/api/v1/auth/forgot", "/api/v1/auth/reset",
                                "/api/v1/auth/sso", "/api/v1/auth/sso/start", "/api/v1/auth/sso/callback",
                                "/api/v1/applicant/lookup", "/api/v1/applicant/register", "/api/v1/applicant/sign-in",
                                "/api/v1/applicant/forgot", "/api/v1/applicant/reset",
                                "/api/v1/payments/webhook/paystack", "/api/v1/payments/webhook/flutterwave",
                                "/api/v1/payments/webhook/quickteller", "/api/v1/payments/quickteller/start",
                                "/api/v1/student-auth/sign-in").permitAll()
                        .anyRequest().authenticated())
                .oauth2ResourceServer(oauth2 -> oauth2.jwt(jwt -> jwt.jwtAuthenticationConverter(authenticationConverter())))
                .addFilterAfter(new AuditContextFilter(sessions), BearerTokenAuthenticationFilter.class);
        return http.build();
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
