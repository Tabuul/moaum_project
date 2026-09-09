# Single sign-on for staff (Keycloak) and MFA

Staff sign in through the University's OpenID Connect provider; the portal never sees
their password. The provider asks for the second factor; the portal refuses any sign-on
the provider does not say completed one. Students and applicants keep the portal's own
sign-in (matriculation, JAMB or application number).

## How it works

1. The sign-in page shows the button when the API has the three settings below.
2. The browser goes to `/api/auth/sso/start`; the API builds the provider's authorize
   address with a signed, dated state and a nonce, and the browser is sent there.
3. The provider signs the person in (password, then the authenticator), and sends the
   browser back to `/api/auth/sso/callback` with a code.
4. The API exchanges the code, verifies the ID token with the provider's published keys
   (RS256), checks the issuer, the audience, the expiry and the nonce, and requires the
   `amr` or `acr` claim to say a second factor was completed.
5. The person is matched to the register: by staff number (the `staff_number` claim),
   else by the username or email already on their portal credential. Somebody the
   register does not hold is refused, by name, with the Registry named as the remedy.
6. The portal's own session and token follow, exactly as after a password sign-in;
   the sign-in event says it came through single sign-on.

## Keycloak setup

Realm `moaum` (any name; the issuer is the realm's address).

**Client** `moaum-portal`

- Client authentication: on (confidential). Standard flow: on. Direct access grants: off.
- Valid redirect URIs: `https://moaum-portal-production.up.railway.app/api/auth/sso/callback`
  (and the same path on any other portal address you run).
- Web origins: the portal's origin.

**Mappers on the client** (Client scopes → `moaum-portal-dedicated` → Add mapper):

- `staff_number`: *User attribute* mapper, user attribute `staff_number`, token claim
  name `staff_number`, add to ID token. Set the attribute on each staff user to the staff
  number as the portal's register holds it (for example `MOAUM/STF/1142`).
- `amr`: Keycloak 22+ puts `amr` on the token when the *Authentication Method Reference*
  mapper is added (Add mapper → By configuration → "Authentication Method Reference");
  add it to the ID token. The portal reads `otp`, `mfa`, `webauthn` and the like.
  If your version lacks it, use `acr` instead (below).

**MFA** (Authentication → Required actions): make *Configure OTP* a default action, or
in the browser flow set *OTP Form* to *Required*. Every staff user is then asked to enrol
an authenticator at first sign-in and to enter its code at every sign-in. For
WebAuthn/passkeys, add the WebAuthn authenticator step instead; the `amr` claim carries it.

If the realm uses ACR levels instead of `amr` (Authentication → Policies → ACR to LoA
mapping), set `MOAUM_SSO_MFA_ACR` to the level names that mean a second factor
(default `mfa,otp,2fa,gold,silver`); the portal also asks for those levels with
`acr_values` when it starts the sign-in.

## Settings on the moaum-api service (Railway)

| Variable | Value |
|----------|-------|
| `MOAUM_SSO_ISSUER` | the realm's address, e.g. `https://sso.moaum.edu.ng/realms/moaum` |
| `MOAUM_SSO_CLIENT_ID` | `moaum-portal` |
| `MOAUM_SSO_CLIENT_SECRET` | the client's secret from Keycloak (never in the repository) |
| `MOAUM_SSO_REQUIRE_MFA` | `true` (default); `false` only for a test realm |
| `MOAUM_SSO_MFA_ACR` | ACR level names meaning a second factor, comma-separated (optional) |
| `MOAUM_SSO_STAFF_CLAIM` | the claim carrying the staff number (default `staff_number`) |
| `MOAUM_SSO_LABEL` | the button's wording (optional) |

`MOAUM_AUTH_HMAC_SECRET` must also be set; it signs the state that proves the callback
answers a sign-in this portal started.

## What still signs in with a password

The portal's own staff sign-in stays available beside the button, for the bootstrap
account and for offices not yet on the provider. To make SSO the only door for staff,
end their portal credentials from Users & roles once they are on the provider; the
Registry can restore one at any time.

## Verified without a provider

`OidcVerifierTest` signs a token with a generated key and checks the verifier refuses
a wrong key, a wrong audience, an old expiry, a wrong nonce and a wrong issuer, and that
a password alone is not read as a second factor. The exchange itself needs a live
provider and is exercised on the portal, not in CI.
