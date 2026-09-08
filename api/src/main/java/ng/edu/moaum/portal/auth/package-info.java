/**
 * Signing in (iam.credential, platform.session, V017): a username and a
 * password become a server-side session and a token that carries the
 * person and the offices they hold today. The token is what every other
 * module already verifies; Keycloak will issue the same claims later.
 */
@org.springframework.modulith.ApplicationModule(displayName = "Authentication")
package ng.edu.moaum.portal.auth;
