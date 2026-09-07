/**
 * Identity and access: persons and the offices they hold, each grant backed
 * by an instrument (the letter or minute — V003). Authentication itself is
 * Keycloak's; this module owns who may act as what, and on what.
 */
@org.springframework.modulith.ApplicationModule(displayName = "IAM")
package ng.edu.moaum.portal.iam;
