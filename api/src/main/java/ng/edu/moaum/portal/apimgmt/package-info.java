/**
 * API management (API, V047): the external consumers of University data, each
 * named, scoped and rate-limited, and their keys. A key is shown once at issue
 * and only its hash is kept; no key lives longer than a year, and a credential
 * with an end date stops working by itself.
 */
@org.springframework.modulith.ApplicationModule(displayName = "API management")
package ng.edu.moaum.portal.apimgmt;
