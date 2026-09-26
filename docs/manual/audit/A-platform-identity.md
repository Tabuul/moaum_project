# Dossier A — Platform, Identity, Access, Administration, Governance and Cross-cutting Reporting

Read-only audit of the MOAUM Unified University Portal, group A. Evidence is cited as `path:line` relative to `C:\Users\ajene\Documents\moaumpp`. Where the local read-only database (port 5433) was queried, the section says so. Nothing in the repository or database was modified.

Conventions used below: **office codes** are those of `ref.office` (34 rows in the local database; `verify.sql` asserts 33 — see §K); guards are the `@PreAuthorize` constants quoted from the controllers; "BFF" is the Next.js route `frontend/src/app/api/bff/[...path]/route.ts` through which every client screen calls `/api/bff/api/v1/...`.

---

# A1. Identity and sign-in  (API modules: auth, studentportal (StudentAuth*), platform (SecurityConfig, SessionGuard, AuditContextFilter); schemas: iam, platform.session; pages: /login, /login/first, /login/forgot, /login/reset, /login/activate, /account/password, frontend/src/app/api/auth/**, frontend/src/proxy.ts)

## 1 Purpose
One sign-in door (`/login`) serves staff, students, applicants and postgraduate applicants: the frontend reads the shape of the identifier typed and forwards to the right API door. The API issues an HS256 JWT bound to a server-side session row (`platform.session`); the frontend keeps the token in an httpOnly cookie (`moaum_session`) and the chosen acting office in a readable cookie (`moaum_office`). Every later request carries the offices as `OFFICE_<code>` authorities and the acting office as `X-Active-Office`, which becomes the audit context placed on every database transaction. Password self-service (forgot/reset), forced change of a first password, Keycloak single sign-on with MFA, and the one-time bootstrap of the first account are all here.

## 2 Users and roles
- Public (no token): `/api/v1/auth/sign-in`, `/bootstrap`, `/offices`, `/forgot`, `/reset`, `/sso`, `/sso/start`, `/sso/callback`, `/api/v1/student-auth/sign-in`, `/api/v1/applicant/sign-in`, `/api/v1/pg/sign-in` — the permit-all list in `api/.../platform/SecurityConfig.java:44-58`.
- Any signed-in principal: `/auth/sign-out`, `/auth/sessions`, `/auth/sessions/{id}/end`, `/auth/change-password` (authenticated, no office needed) — `AuthController.java:95-116`.
- Student only: `/student-auth/sign-out`, `/student-auth/change-password` (`hasAuthority('OFFICE_student')`, `StudentAuthController.java:46-58`).
- Registry opens/resets a student account: `PUT /student-auth/accounts/{studentId}` — `registrar, dregistrar, academic, records, ict, super` (`StudentAuthController.java:62`).
- Scope is not in the token: "Scope (a HOD of Mathematics, not of Physics) … lives in iam.office_assignment; it is not modelled in the token" (`SecurityConfig.java:30-32`); it is applied per request by `shared/OfficeScope.java` (see A2 §6).

## 3 Navigation
No menu item: `/login`, `/login/first`, `/login/forgot`, `/login/reset`, `/login/activate` are reached from the sign-in card links ("Forgot your password?", "First account", `Login.tsx:110-111`) or from emailed links. `/account/password` (route id `a/password`, title "Your password") is where a staff member with `mustChange` is sent after sign-in (`api/auth/sign-in/route.ts:125`, `Login.tsx:50`); the Shell's sign-out button is in the nav foot (`Shell.tsx:500`).

## 4 Screens
**Sign in — `/login`** (`frontend/src/app/login/Login.tsx`). Two-column page: brand panel (crest, "Rev. Fr. Moses Orshio Adasu University, Makurdi", stats "12 faculties · 1 college · 1992 established" — static text, `Login.tsx:74-76`) and the card. Fields: "Your number or email address" (`id=uid`, placeholder `MOAUM/CSC/23/1487 · MOAUM/STF/1142 · 202699168863AH`), a live hint that names who the number looks like (`whoIs`, lines 21-29), and "Password" with a show/hide eye button. Button "Sign in" (disabled until both fields are filled). If the API says SSO is enabled a ghost link "Sign in with the University's single sign-on" (label configurable) points at `/api/auth/sso/start`. Links: "Forgot your password?", "First account", "Post UTME Registration" (→ `/apply`), "Postgraduate application" (→ `/pg/apply`), "Verify a payment or receipt" (→ `/verify`). Footer notice: "Five failed attempts lock an account for fifteen minutes…". Errors render as `ProblemNotice` plus a toast; an SSO failure arrives as `?sso=<why>` and renders "Single sign-on did not complete". Note: the hint regex for a matric number (`^MOAUM\/[A-Z]{2,4}\/[0-9]{2}\/[0-9]{4}$`, line 16) is narrower than the routing regex in the handler (V263 form `MOAU/FAC[/PROG]/YY/SEQ`, `api/auth/sign-in/route.ts:15`), so a new-format number is labelled "A member of staff, on the staff number" in the hint while still being routed to the student door.

**The sign-in handler — `frontend/src/app/api/auth/sign-in/route.ts`.** Decides the door from the identifier: MATRIC or ADMISSION (`MOAUM/ADM/YY/NNNNNN`) → `POST /api/v1/student-auth/sign-in`; `PG/YY/NNNNNN` → `/api/v1/pg/sign-in`; JAMB (12 digits + 2–3 letters) or `APP/YY/NNNNNN` → tries the student door first, then `/api/v1/applicant/sign-in`; a legacy matric shape (`BSU/…`, `MOAU/…`) → student door, falling back to staff; anything else → `/api/v1/auth/sign-in`, and if that answers 422 and the identifier contains `@`, the applicant door then the PG applicant door are tried (lines 49-96). On success it sets `moaum_session` (httpOnly, sameSite lax, secure in production, max-age to the token's `expiresAt`, `lib/session.ts:19-27`) and `moaum_office` (not httpOnly) to `student`/`applicant`/the preferred or first staff office, and answers `{kind, home, mustChange, name, office, offices}`; a staff `mustChange` home is `/account/password`, a student's `/student/profile?change=1` (lines 107-129).

**Create the first account — `/login/first`** (`login/first/page.tsx`). Fields: "Bootstrap secret" (password field; hint "The value of MOAUM_AUTH_HMAC_SECRET on the API service. It is checked, never stored here."), "Surname", "Given names", "Staff number" (Optional), "Username" (hint "The staff number or an email address…"), "Password" (hint "At least ten characters"). Button "Create and sign in" → `POST /api/auth/bootstrap` (secret travels as `X-Bootstrap-Secret`, `api/auth/bootstrap/route.ts:12`) → on success cookies are set with office `registrar` and the browser goes to `/people`.

**Forgot password — `/login/forgot`** (`Forgot.tsx`). One field "Staff number, matriculation number, application number, email or JAMB number"; button "Send the reset link" → `POST /api/auth/forgot`. Always answers with the green note "If that names an account, a reset link is on its way" (line 51) — the API returns 202 `{sent:true}` whether or not an account matched (`AuthController.java:62-65`).

**Choose a new password — `/login/reset?token=…`** (`Reset.tsx`). Fields "New password" (show/hide), "Type it again" (inline error "The two do not match."); button "Save the new password" enabled at 8+ characters → `POST /api/auth/reset`; success note "Your password has been changed". Missing token → "This link is incomplete".

**Activate an examiner account — `/login/activate?token=…`** (`Activate.tsx`) belongs to the external-examiner module (V254) but sits under `/login`: reads `GET /api/v1/examiners/invitation/{token}`, asks for a password (10+ chars, not containing the email) twice, `POST /api/v1/examiners/activate`; success: "Your examiner account is active".

**Your password — `/account/password`** (`ChangePassword.tsx`). Inside the Shell. Note "Choose a password of your own — The Registry set the one you signed in with, so it changes now. At least ten characters, and not your username…". Fields "Current password", "New password", "New password, again"; button "Change the password" (enabled when current is filled, new ≥ 10 chars and both match) → `POST /api/auth/change-password` (forwarded with `X-Reason: password changed by the person`, `api/auth/change-password/route.ts:12`) → then `router.push(next)`.

**Sign-out** — nav foot button (`Shell.tsx:398-402`) → `POST /api/auth/sign-out`, which calls `/api/v1/auth/sign-out` with the bearer token and clears both cookies (`api/auth/sign-out/route.ts`).

**Route protection — `frontend/src/proxy.ts`.** Everything except the OPEN list (`/login`, `/apply`, `/pg/apply`, `/api/auth/`, `/verify`, `/healthz`, `/crest.png`, examiner invitation/activate, `/pg/referee/`, `/documents/d/`, and four exact public PG endpoints) requires the `moaum_session` cookie; a page navigation (not BFF calls, not prefetches) is validated against `GET /api/v1/iam/me` and a 401 clears both cookies and redirects to `/login?next=…` (lines 56-71). If the API is unreachable the request is allowed through. In non-production, `PORTAL_API_TOKEN` bypasses the gate (line 72).

## 5 Workflow and statuses
**Staff password sign-in** (`AuthService.signIn`, `AuthService.java:71-110`): username lower-cased and trimmed → `iam.credential` looked up → refused as `AUTH_BAD_CREDENTIALS` if unknown or the person is ended (`iam.person.ended_on`), as `AUTH_LOCKED` if `locked_until` is in the future, or on a bcrypt mismatch (failed attempts +1; the 5th failure sets `locked_until = now()+15 min`) → on success `iam.live_offices(person)` is read, a 32-byte session id is generated, `platform.session` row inserted with `absolute_end = now()+12h` (`SESSION_LENGTH`), failed attempts reset and `last_sign_in_at` stamped, an `iam.sign_in_event` written, and a JWT issued with claims `sub` (person id), `offices` (codes), `sid` (hex session id), `name`, `exp` (`TokenIssuer.java:40-56`). The failure event is written **before** the refusal is thrown, in its own transaction attributed to the person "at the door" with office `ict` and reason `sign-in` (`atTheDoor`, lines 61-64) so the lockout counter survives the rollback.
- `iam.sign_in_event.outcome` CHECK: `SIGNED_IN, BAD_PASSWORD, UNKNOWN, LOCKED, MUST_CHANGE, SIGNED_OUT, ENDED` (constraints.psv). The code writes `UNKNOWN`, `LOCKED`, `BAD_PASSWORD`, `SIGNED_IN`, `SIGNED_OUT`; `MUST_CHANGE`/`ENDED` are never written.
- Active office at issue: the `office` the body asked for if the person holds it, else the first live office, else `ict` (line 93). The `platform.session.active_office` column is set once at sign-in and is **not** updated when the user switches office later (the switch is a cookie change only, `Shell.tsx:393-396`).

**Every authenticated request** (`AuditContextFilter.java:49-92`): subject must be a UUID (else 401 "The token's subject is not a person id."); if the token carries `sid`, `SessionGuard.refuse` (`SessionGuard.java:36-60`) answers 401 with one of: "The token names a session that cannot exist.", "The token names a session this portal does not hold. Sign in again.", "This session was ended. Sign in again.", "This session reached its end. Sign in again.", "The portal was updated. Sign in again." (a session issued before this API instance started — the deploy floor). `last_seen_at` is touched at most once a minute. `X-Active-Office` must be one of the token's offices or the request is refused 403 "The office 'x' is not one this token carries: […]". With no office header the first office is the acting one; with no office at all the request proceeds and may only read.

**Student sign-in** (`StudentAuthService.signIn`, `StudentAuthService.java:67-127`): finds the student by matric or admission number; if no `iam.student_account` exists, the applicant account's bcrypt hash is verified and carried over (event `CARRIED_OVER`), otherwise `AUTH_NO_STUDENT_ACCOUNT` ("No portal account has been opened for this number yet."); lockout identical (5 / 15 min); a migrated account with `must_change` and no matching hash accepts the student's **own number as the password** (line 100-107; see also `iam.set_migrated_default_passwords`); token offices = `["student"]`. Outcomes written to `iam.student_event`: `UNKNOWN, NO_ACCOUNT, BAD_PASSWORD, CARRIED_OVER, LOCKED, SIGNED_IN, PASSWORD_CHANGED, OPENED_BY_REGISTRY` (no CHECK constraint on this column).

**Registry opens a student account**: `PUT /student-auth/accounts/{id}` with a first password (≥ 8 chars, `APP_PASSWORD_SHORT`) sets `must_change = true` (`StudentAuthService.open`).

**Forgot / reset** (`PasswordResetService.java`): identifier resolved in order STAFF (by username) → STUDENT (matric, admission no or email) → APPLICANT (JAMB key, email, application no) → PGAPPLICANT (email, application no); a 32-byte token is generated, only its SHA-256 kept in `iam.password_reset` (`subject_kind` CHECK `STAFF|STUDENT|APPLICANT|PGAPPLICANT`, `expires_at = now()+1 hour`), and `platform.queue_notice` is called for EMAIL (subject "Reset your MOAUM password", link `<portal-url>/login/reset?token=…`) and SMS when the account has an email/phone. A staff account with no `iam.person.email` is emailed only when its username is itself an email (lines 66-70). Reset requires ≥ 8 characters (note: shorter than the 10 the sign-in policy demands for a Registry-set password), consumes the token once (`used_at`), clears the lockout and `must_change`.

**Change password (staff)**: current must match; `checkPolicy` requires ≥ 10 chars (`AUTH_PASSWORD_SHORT`) and that the password does not contain the username (`AUTH_PASSWORD_IS_USERNAME`); the credential is rewritten with `must_change=false` and an `iam.credential_event` of kind `CHANGED` (kinds CHECK: `SET, RESET, CHANGED, LOCKED, UNLOCKED`; only SET/RESET/CHANGED are written).

**Bootstrap** (`AuthService.bootstrap`, lines 184-206): refused unless `X-Bootstrap-Secret` equals `MOAUM_AUTH_HMAC_SECRET` (`AUTH_BOOTSTRAP_SECRET`) and `iam.credential` is empty (`AUTH_BOOTSTRAPPED` — "The portal already has accounts; the first one is made once."); creates the person, grants `registrar` (institution), `academic` (institution), `ict` (platform), `super` (platform) with instrument "Bootstrap of the portal, Directorate of ICT", sets the credential and signs in as `registrar`.

**SSO (Keycloak)** (`SsoService.java`): enabled only when `MOAUM_SSO_ISSUER`, `MOAUM_SSO_CLIENT_ID`, `MOAUM_SSO_CLIENT_SECRET` are all set; `/sso/start` builds the authorize URL with `scope=openid profile email`, a signed state `epoch.nonce.hmac` (HMAC-SHA256 with the HMAC secret; 10-minute window) and, when MFA is required (default true), `acr_values`; `/sso/callback` exchanges the code, verifies the ID token with the realm's JWKS (RS256, issuer, audience, expiry, nonce — `OidcVerifier.java`), requires an `amr` factor among `mfa, otp, hwk, swk, sms, webauthn, fido, totp` or an `acr` level in `MOAUM_SSO_MFA_ACR` (default `mfa,otp,2fa,gold,silver`), matches the person by the `staff_number` claim, else by username/email on an existing credential, refuses an unknown or ended person (`AUTH_SSO_UNKNOWN`: "The University's sign-on knows this person, but the portal's register does not."), then opens the same session and token as a password sign-in with `mustChange=false`. The frontend callback route sets the cookies and redirects to `/`.

**Sessions list / end**: `GET /api/v1/auth/sessions` (live sessions of the caller) and `POST /api/v1/auth/sessions/{hexId}/end` exist (`AuthController.java:101-110`) but **no screen calls them** (no match in routes.md).

## 6 Business rules and validations
- Username: `iam.credential.ck_credential_username` — lower-case, trimmed, 3–200 chars; unique. Set by the Registry through `AuthService.setCredential`: `AUTH_USERNAME` ("A username is the staff number or an email address.") under 3 chars; `AUTH_USERNAME_TAKEN` ("'x' already signs somebody else in."); password policy as above; `must_change=true`; kind `SET` or `RESET`.
- Hash format enforced by CHECK `password_hash LIKE '$2%$12$%'` on both `iam.credential` and `iam.student_account` (bcrypt cost 12).
- Session id length: `platform.session.ck_session_id_len` (32 bytes).
- `iam.person.ck_person_ended`: an ended person carries `ended_reason`.
- JWT decoder: `MOAUM_AUTH_HMAC_SECRET` (≥ 32 bytes, else the API refuses to start: "moaum.auth.hmac-secret must be at least 32 bytes") or `MOAUM_AUTH_ISSUER_URI`; neither → "no way to verify tokens…" at boot (`SecurityConfig.java:69-84`). Note: when the issuer-URI mode is used the HS256 `TokenIssuer` has no key and password sign-in is refused with `AUTH_SIGN_IN_ELSEWHERE` ("This portal verifies tokens issued by the University's identity provider; sign in there.", `TokenIssuer.java:41-44`) — yet the SSO callback also mints its token through `TokenIssuer`, so in that mode SSO sign-in would fail too. In practice the deployed configuration keeps the HMAC secret (README, `docs/keycloak.md:67`).

## 7 Notifications
| event | trigger | recipient | channel | subject |
|---|---|---|---|---|
| Password reset requested | `PasswordResetService.forgot` → `platform.queue_notice` | email on the account (staff: `iam.person.email` or username-if-email; student: `people.student_reach`; applicant/PG applicant: account email) | EMAIL | "Reset your MOAUM password" |
| same | same | phone on the account | SMS | "Reset your MOAUM password" (body "MOAUM: reset your password within the hour at <link>") |

Sign-in, lockout, password change and bootstrap send nothing.

## 8 Reports, exports and documents
None.

## 9 Configuration
Environment variables (names only): `MOAUM_AUTH_HMAC_SECRET`, `MOAUM_AUTH_ISSUER_URI`, `MOAUM_SSO_ISSUER`, `MOAUM_SSO_CLIENT_ID`, `MOAUM_SSO_CLIENT_SECRET`, `MOAUM_SSO_REQUIRE_MFA`, `MOAUM_SSO_MFA_ACR`, `MOAUM_SSO_STAFF_CLAIM`, `MOAUM_SSO_LABEL`, `MOAUM_PORTAL_URL` (reset links); frontend `PORTAL_API_URL`, `PORTAL_API_TOKEN`, `PORTAL_ACTIVE_OFFICE` (development only). Constants in code: session 12 h, lock after 5 for 15 min, staff minimum password 10, student/reset minimum 8, reset token 1 h, SSO state window 600 s, JWKS refresh hourly.

## 10 Data
`iam.credential` (PK person_id; username, password_hash, must_change, failed_attempts, locked_until, set_at, set_by, last_sign_in_at) — audit-exempt ("Carries a password hash…"); `iam.credential_event` (attached); `iam.sign_in_event` (exempt; the log itself); `iam.student_account` (exempt), `iam.student_event` (exempt); `iam.password_reset` (exempt; token hash, used once); `platform.session` (exempt: "Session rows are written and touched on every request…"; id bytea, person_id, active_office → ref.office, issued_at, last_seen_at, absolute_end, ended_at, ended_reason). Exemption reasons were read from `audit.exemption` on the local database.

## 11 Scheduled jobs and integrations
None in this module beyond Keycloak (OIDC discovery `/.well-known/openid-configuration`, token endpoint, JWKS).

## 12 Security notes
- Tokens are HS256 with a shared secret; a session-less token (development token from `api/scripts/dev-token.mjs`) is accepted without a session check (`AuditContextFilter.java:63`).
- The office cookie is client-writable by design; the API still refuses an office the token does not carry.
- `/api/v1/auth/forgot` and `/reset` are public and unauthenticated; there is **no rate limit** in code (the `AUTH_THROTTLED` title exists in `ProblemHandler.java:151` but nothing raises it).
- `/api/v1/auth/sessions` lets a person list and end their own sessions, but the Registrar has no endpoint or screen to end another person's session (the ADR text in `SessionGuard.java:12` says "by the Registrar" — not implemented).
- CSRF is disabled and the API is stateless (`SecurityConfig.java:42-43`); the browser never holds the token.
- The `AUTH_LOCKED` message includes a time-of-day computed on the server (`toLocalTime()`), i.e. in the server's time zone.

## 13 Implementation status
| Feature | Status | Evidence | Notes |
|---|---|---|---|
| Staff password sign-in with lockout, session, JWT | IMPLEMENTED | `AuthService.java:71-110`, `SessionGuard.java` | |
| One-door routing (staff/student/applicant/PG/legacy matric) | IMPLEMENTED | `api/auth/sign-in/route.ts:49-96` | hint regex on the card is stale for V263 numbers |
| Student sign-in, applicant hash carry-over, default first password | IMPLEMENTED | `StudentAuthService.java:67-127` | |
| Forgot / reset for four account kinds | IMPLEMENTED | `PasswordResetService.java` | needs an outbox provider to actually deliver (see A3) |
| Forced change of first password | IMPLEMENTED | `ChangePassword.tsx`, `AuthService.changePassword` | |
| Bootstrap first account | IMPLEMENTED | `AuthService.bootstrap`, `login/first/page.tsx` | |
| Keycloak SSO with MFA | IMPLEMENTED (code), NOT DEPLOYED | `SsoService.java`, `docs/keycloak.md:111` "nothing is deployed" | button hidden until env set |
| Sessions list / end own session | PARTIALLY IMPLEMENTED | `AuthController.java:101-110`; no page | backend without UI |
| Registrar ends another's session | NOT IMPLEMENTED | `SessionGuard.java:12` (intent only) | |
| Rate limiting of sign-in / forgot | NOT IMPLEMENTED | `ProblemHandler.java:151` title only | |
| Deploy floor (sessions before restart refused) | IMPLEMENTED | `SessionGuard.java:26,54-56`, `proxy.ts:64-65` | |

## 14 Common problems and troubleshooting
- "That username and password do not match an account." — unknown username, ended person, or wrong password; after five the account locks 15 minutes ("This account is locked after repeated failures; try again after HH:MM."). Registry: Users & roles → "Reset password" (sets a new first password and clears the lock).
- "No portal account has been opened for this number yet." — student with no applicant account behind them; Registry opens it (`PUT /student-auth/accounts/{id}` — used from the student record screens, not in this group).
- "The portal was updated. Sign in again." — the API restarted; every earlier session is refused by design.
- "The office 'x' is not one this token carries" — stale `moaum_office` cookie after a grant ended; sign out and in.
- "This reset link has expired or was already used." — one hour, single use; ask again.
- Reset email never arrives — the staff person has no email on record (set it via Users & roles → Contact) or no mail/SMS provider is configured (A3).
- "The bootstrap secret is not right." / "The portal already has accounts" — bootstrap is once; afterwards grant offices from `/people`.

## 15 Glossary
**Door** — an API sign-in endpoint for one kind of person. **Acting office** — the office a request is made in (`X-Active-Office`), one of the offices the token carries. **Session floor** — the API instance's start time; older sessions are refused. **Must change** — flag on a credential set by the Registry; the holder is sent to `/account/password` before anything else. **Instrument** — the letter or minute under which an office is held (see A2).

---

# A2. Users, roles and people  (API module: iam; schemas: iam, ref.office/unit; pages: /people, /people/lecturers, /people/staff, /me, /me/profile, /me/notices, /me/courses, /me/teaching, /me/siwes)

## 1 Purpose
A person (`iam.person`) is created once; a credential signs them in; each office they hold is a dated grant under an instrument (`iam.office_assignment`), optionally bounded to a scope (faculty, department, programme, course, unit, level…). The Users & roles console does this one person at a time; two bulk loaders onboard teaching staff (person + sign-in + lecturer office + establishment record) and non-academic staff (person + establishment record only). `GET /api/v1/iam/me` tells the frontend who is signed in, which office is acting and what waits in each queue (the menu badges). The "Me" pages are the staff member's own record.

## 2 Users and roles
Guards in `AccountsController.java:30-32,80`: `READERS` = registrar, dregistrar, hrm, ict, admin, super, audit; `CREDENTIALS` = registrar, dregistrar, ict, admin, super; `GRANTORS` = registrar, dregistrar, vc, super, ict, admin; `STAFF_LOADERS` = registrar, dregistrar, hrm, ict, admin, super. `IamController`: create person / read person / set contact = registrar, dregistrar, hrm, ict, admin, super; grant = registrar, dregistrar, vc, super, ict, admin (`IamController.java:70,87,98,112`). `/iam/offices` and `/iam/me` need only a token. The UI mirrors these lists (`People.tsx:62-63`, `Lecturers.tsx:37` MAY = ict, super, admin, registrar, dregistrar; `NonAcademic.tsx:26` MAY = registrar, dregistrar, hrm, ict, admin, super) and greys out buttons; the `RoleLine` on the two upload screens names the offices.

Scope is applied by `shared/OfficeScope.java`: department offices (`hod, exams, siwes, lecturer`) are held to their department — the scope of their grant, else their `lecturer` grant's department, else `hrm.staff_record.home_department` (lines 76-100); faculty offices (`dean, facultyofficer`) to their faculty (lines 200-219); `bound()` refuses a parameter outside the bound with `SCOPE_DEPARTMENT`/`SCOPE_FACULTY` ("That department is not in your faculty." etc., line 134-136); `reportScope()` returns the faculty/department a return is cut to. An office that resolves to nothing is bound to the sentinel `__none__` and sees nothing.

## 3 Navigation
- Users & Roles `t/users` → `/people`: super (Administration), ict (Administration, badge = persons without a credential), admin (Administration).
- Upload Lecturers `t/lecturers` → `/people/lecturers`: super, ict, admin (Staff group).
- Upload Non-Academic Staff `t/staffupload` → `/people/staff`: super, ict, admin, registrar, dregistrar, hrm (Staff group).
- Leave & Payslip `r/self` → `/me`: every staff office menu (Me group); My Profile `t/myprofile` → `/me/profile`, Course History `t/coursehistory` → `/me/courses`, My Courses & Timetable `t/teaching` → `/me/teaching`, Notifications `r/notices` → `/me/notices`, My SIWES Students `r/mysiwes` → `/me/siwes`: lecturer menu (and hod for teaching; siwes for mysiwes) — menus.md lines 9-33, 57.
- Dashboard shortcuts: `/people?new=person` and `/people?new=grant` open the console straight into a modal (`People.tsx:64-72`, `Platform.tsx:107-108`).

## 4 Screens
**Users & roles — `/people`** (`People.tsx`). Red note "A role is granted by the Registrar, recorded here, and reviewed". Tiles: "Accounts" (persons with a username), "Staff accounts" (with ≥1 live office), "Holding two offices", "Grants expiring in 30 days". Panel "People on the register": search field "Find a person" (placeholder "Name, staff number or username"; submits `?q=` → `GET /iam/persons?q=`), table columns Name, Staff number, Username ("no account" when none), Offices (live count), Last sign-in ("never"), State pill (Ended / Locked / "Password to change" / Active / "No account"), Action buttons "Reset password" or "Create account", "Contact", "Grant an office". Footer button "+ New person". Panel "Staff accounts and the offices they hold" (`GET /iam/office-assignments`, live grants newest first): Name, Staff number, Office label, "Bounded to" (scope kind label + id: The University / The College / Faculty / Department / Programme / Own courses / Unit / The platform / "Level (MBBS Coordinator: 200 to 600)"), Granted by (name, else the instrument), From, To (red when set), Action "End"; footer "+ Grant an office".
Modals: **New person** (Surname, Given names required; Staff number "Optional; the number the University issued" placeholder `MOAUM/STF/`; Email "Where a password reset and notices are sent"; Phone "Optional; for SMS notices") → `POST /iam/persons`, toast "Person created". **Contact** (Email, Phone) → `PUT /iam/persons/{id}/contact`. **Grant an office** (Office select from `GET /iam/offices`, choosing one presets "Bounded to" from `ref.office.scope_kind`; "Which one" — "The faculty, department, programme or course code; blank for the University or the platform"; From; To "An acting grant must carry one."; "Authority for the grant" required, placeholder "Registrar, memo REG/2026/318") → `POST /iam/persons/{id}/office-assignments`, toast "<office> granted under <instrument>". **Create/Reset credential** (Username — "The staff number or an email address", prefilled with the staff number lower-cased; "First password" ≥ 10) → `PUT /iam/persons/{id}/credential`, toast "Account created by the Registry" / "Password reset by the Registry". **End** (date "Ended with effect from" — today when blank; "Reason, as it will read in the log" required) → `POST /iam/persons/{id}/office-assignments/{grant}/end`. Every write carries `X-Reason`. Errors: `ProblemNotice` + toast.

**Upload Lecturers — `/people/lecturers`** (`Lecturers.tsx`). RoleLine "Onboarding teaching staff"; info note explaining that each row becomes person + sign-in (username and first password = `P<PNO>`) + lecturer office at the home department + establishment record; "Download template" (xlsx with columns PNO, Full Names, Sex, Date of 1st Appt, Department, Present Rank, Phone No, CONUASS); "Upload teaching staff (.xlsx)" — the file is parsed in the browser (`xlsxRows`), needs PNO, Full Names and Department columns ("That file needs PNO, Full Names and Department columns."), rows are sent in chunks of 25 to `POST /iam/lecturers/import` (bcrypt cost makes large requests time out; the import is idempotent so re-uploading fills gaps), progress "Onboarding n of m…", result tiles "New staff / Sign-ins issued / Department grants / Records kept" and a summary note listing `no_department`, `skipped`, failed chunks and "Create these departments first, then re-upload: …". Panel "Teaching staff on record" (`GET /iam/lecturers`): search, checkboxes, "Add staff" (single-row import through the same endpoint), "Delete selected (n)" → confirm → `POST /iam/lecturers/delete` (a lecturer who already teaches an offering is kept), "Edit" modal (PNO locked on edit; Department "Code or name"; Surname; Given names; Sex; Present rank; Phone; CONUASS; Email) → `PUT /iam/lecturers/{id}`. Table shows first 500. Pills: Active / "First password set" / Issued / "No sign-in".

**Upload Non-Academic Staff — `/people/staff`** (`NonAcademic.tsx`, title "Non-Academic Staff"). Two-step: "Check a File (.xlsx)" runs a **dry run** (`POST /iam/staff/import` with `dryRun:true`, chunks of 100) and reports rows read / would be added / already on record / "Not placed" with the spellings that matched no unit ("Not placed, as spelt in the sheet: …"); then "Load All n Rows" or "Load the n Placed Rows". No sign-in and no office are issued. Tabs "Non-Academic Staff" (Staff id, Name, Placed in — with a CHS / Academic department / Faculty office pill —, "As the roll spelt it", Rank, Scale, First appointed) and "The Unit Register" (`GET /iam/units`: Unit, Kind, Under, Campus, Staff, "Spellings known").

**Leave & Payslip — `/me`** (`Self.tsx` + `LeaveSelf.tsx`). Reads `/staff/me`, `/me/payslips`, `/me/leave` (HR/payroll modules). Tiles Leave taken / Leave remaining / Last payslip / Appraisal ("—", "Staff module, not yet on the portal"). Panel "My record" (Staff number, Office, Unit, Appointment "—", Grade, Next increment "—"; buttons "My ID card (PDF)" → `/staff/idcard/pdf`, "Edit my profile"); "Payslips" table; "Offices held" (Office, Scope, Instrument, From, Until) from `staff/me`; "Leave" panel with a request form (Type, From, To, Cover, Note → `POST /me/leave`) and history with Cancel. Empty states are explicit ("No office assignment is recorded against you", "You are signed in, but the Registry has no record of you yet").

**My Profile — `/me/profile`**, **Course History — `/me/courses`**, **My Courses & Timetable — `/me/teaching`**, **My SIWES Students — `/me/siwes`** read the staff, allocation, `me/teaching` and SIWES modules respectively (`PUT /staff/profile`, `PUT /staff/profile/photo` JPEG/PNG ≤ 2 MB; `GET /allocation/history?scope=me`; `GET /me/teaching?session=`; `PUT /siwes/mine/students/{id}/score`). They are listed here because they sit under `/me`; their rules belong to those modules.

**My notifications — `/me/notices`** (`me/notices/Notices.tsx`, title "Notifications"): `GET /api/v1/me/notices?limit=200`; tiles All / This week / By email / Not delivered; filters Search and Channel (Email and SMS / Email / SMS); each notice expands to its body; pills Delivered / "Waiting to send" / "Not delivered". Read-only.

## 5 Workflow and statuses
- Person: created → (optionally) ended (`ended_on` + `ended_reason`; no endpoint in this group ends a person — `iam.delete_lecturers` removes a lecturer outright when they have no teaching history).
- Grant: live while `valid_from <= today <= coalesce(valid_to, ∞)` (`iam.live_offices`); ended by `iam.end_grant(grant, on, reason)` which sets `valid_to`; refuses without a reason ("an office is ended with the reason on the record, and none was given") and when no live grant matches ("no live grant <id>"). A grant is never deleted. Grants take effect at the next sign-in (the token carries the office codes as of sign-in).
- Credential: none → SET (must_change) → CHANGED by the holder; RESET by the Registry sets must_change again.
- Waiting badges (`WaitingRepository.java:27-63`): `t/users` = persons with no credential; `t/biochange`, `t/admissions`, `t/clearance`, `t/transcripts`, `t/certificates`, `t/approvals` counts; `t/admissionsetup` "!" when the next PLANNED session has no in-force admission policy; `t/matriculation` "!" when current-session ADMITTED students lack a matric number.

## 6 Business rules and validations
- `IAM_NO_SUCH_OFFICE` ("'x' is not one of the offices in ref.office."), `IAM_GRANT_NEEDS_INSTRUMENT` ("An office is held under a letter or minute; none was given.") — `PersonService.java:65-74`; `NewGrant.scopeKind` must match `institution|college|faculty|department|programme|course|unit|platform|level` (`IamController.java:104`) and the DB CHECK `ck_grant_scope` says the same; `ck_grant_dates` (valid_to ≥ valid_from); `ck_grant_instrument` (non-blank).
- Grantor is the acting person from the audit context, never the body (`PersonService.java:76`).
- `iam.guard_coordinator_grant` trigger: an `mbbscoordinator` grant must be `scope_kind='level'` with scope 200–600 ("the MBBS Coordinator is held by level: 200, 300, 400, 500 or 600") and the person must already hold a lecturer office in a College department ("…Grant the lecturer's office in a College department first…").
- `iam.person.staff_number` is UNIQUE; the frontend hides but the DB raises 409 `ALREADY_EXISTS` on a duplicate.
- `iam.import_lecturers` (V135): idempotent; username/first password = `P<PNO>`; reports `missing_departments`; a password already set is never reset. `iam.import_staff` (V253): dry run writes nothing; unplaced spellings reported; no sign-in, no office. `iam.update_lecturer` moves the lecturer office when the department changes; staff number and sign-in unchanged (function comments, local DB).
- `/iam/persons/{id}/contact` is where the email a reset goes to is set (`IamController.java:96`).

## 7 Notifications
None sent by this module (the People console tells the person their first password out of band — "told to the person, never written down here").

## 8 Reports, exports and documents
Template workbooks "Teaching staff template.xlsx" and "Non-academic staff template.xlsx" (client-built `buildXlsx`). The staff register proper is under Reports (A6).

## 9 Configuration
`ref.office` (code, label, scope_kind — CHECK on the nine scope kinds); `ref.unit` and `ref.unit_alias` (the unit register the non-academic loader resolves spellings against; a unit is "ended, never deleted"). No screen edits `ref.office`; units/aliases are added by migration or ICT ("ask ICT to add the unit or the alias", `NonAcademic.tsx:157`).

## 10 Data
`iam.person` (id, staff_number UNIQUE, surname, given_names, ended_on, ended_reason, email, phone) — attached; `iam.office_assignment` (id, person_id, office_code→ref.office, scope_kind, scope_id text, instrument, granted_by, valid_from, valid_to) — attached, plus the coordinator guard trigger; `iam.credential`, `iam.credential_event` as in A1; `hrm.staff_record` is written by the importers (other group).

## 11 Scheduled jobs and integrations
None.

## 12 Security notes
- Any of the six grantor offices can grant **any** office including `super` and `ict` to anyone; there is no two-person rule and no check that the grantor outranks the grant. The instrument text is free.
- `GET /iam/persons` exposes username, lock state and last sign-in to the seven reader offices including `audit`.
- The lecturer import issues predictable first passwords (`P<PNO>`) with `must_change`; anyone who knows a PNO can sign in first if the lecturer has not.

## 13 Implementation status
| Feature | Status | Evidence | Notes |
|---|---|---|---|
| Create person, set contact, create/reset credential, grant, end grant | IMPLEMENTED | `People.tsx`, `AccountsController.java`, `IamController.java` | |
| Bulk lecturer onboarding, edit, delete | IMPLEMENTED | `Lecturers.tsx`, `iam.import_lecturers/update_lecturer/delete_lecturers` | |
| Non-academic staff load with dry run | IMPLEMENTED | `NonAcademic.tsx`, `iam.import_staff` | issues no sign-in by design |
| Scope enforcement (dept/faculty offices) | IMPLEMENTED (code-side) | `OfficeScope.java` | applied only where controllers call it |
| Menu badges from `iam/me.waiting` | IMPLEMENTED | `WaitingRepository.java`, `Shell.tsx:338-346` | |
| Ending a person (leaver) from the UI | NOT IMPLEMENTED | no endpoint sets `iam.person.ended_on` in this group | `ended_on` is read by sign-in |
| `/me` appraisal, appointment, next increment | PLACEHOLDER | `Self.tsx:66,87-89` ("Staff module, not yet on the portal") | |

## 14 Common problems and troubleshooting
- "An instrument is needed" — the Authority field was blank. "No such office" — code not in `ref.office`.
- "the MBBS Coordinator is a College lecturer: no current lecturer's office…" — grant the lecturer office in a CHS department first.
- Upload says "n with no matching department" — create the department on the Department upload screen, re-upload (idempotent).
- Non-academic rows "Not placed" — spelling absent from `ref.unit_alias`; correct the sheet or ask ICT for an alias.
- Person cannot sign in although granted — no credential yet ("No account" pill; use "Create account"), or the grant's `valid_from` is in the future, or they signed in before the grant (sign out/in).
- Dashboard says "Your Head-of-Department office is not tied to a department yet" — the `hod` grant has no department scope and the person has no lecturer grant/home department; set "Which one" on the grant.

## 15 Glossary
**Grant / office assignment** — a dated appointment to an office under an instrument. **Scope kind** — what a grant is bounded to. **Live offices** — grants valid today (`iam.live_offices`). **PNO** — the staff number digits on the nominal roll; the staff id becomes `P<PNO>`. **Establishment record** — `hrm.staff_record` (rank, CONUASS/CONTISS, first appointment). **Waiting** — the queue counts the menu shows.

---

# A3. Platform administration  (API module: platform; schemas: platform, public.schema_migration; pages: / (ict/super dashboard), /migrations, /readiness, /platform/mail, /platform/sms, /notices, /healthz)

## 1 Purpose
The platform desks tell the Directorate of ICT what is actually true about the service (status, database, migration ledger), gate go-live (readiness checks), hold the outgoing mail and SMS credentials, show the notice outbox and let failed notices be retried, and offer the guarded data-reset actions. The notice pipeline is the transactional outbox every module writes to through `platform.queue_notice`.

## 2 Users and roles
`/platform/status` public; `/platform/migrations` ict, admin, super; `/platform/readiness` super, ict, admin, registrar, dregistrar, academic, bursar; `/platform/reset-data`, `/remove-demo`, `/remove-demo-courses` super, ict (`PlatformController.java:58,73,84,104,186`); mail and SMS settings `KEEPERS` = ict, admin, super (`MailController.java:24`, `SmsController.java:24`); outbox read ict, admin, super, registrar; retry ict, admin, super (`NoticesController.java:29,43`); `/me/notices` any authenticated non-student (`MeNoticesController.java:34` — api.md's "student" is a parser artefact; the guard is `isAuthenticated() and !hasAuthority('OFFICE_student')`).

## 3 Navigation
ict: Overview → "Platform & Integrations" `t/platform` (home, no URL — the dashboard at `/`), Administration → Mail Server `/platform/mail`, SMS Gateway `/platform/sms`, Notifications `t/notify` `/notices`, Release Pipeline `/release`, Disaster Recovery `/disaster-recovery`, Cloud Readiness `/cloud`. super: Administration → Notification Channels `t/channels` `/notices`, Data Migration `t/migration` `/migrations` (badge "!"), Platform `t/platform` (—). admin: Overview → Go-Live Readiness `/readiness`; Administration → Mail Server, SMS Gateway. (menus.md 459-500, 545-590, 607-660.)

## 4 Screens
**Platform dashboard — `/` for ict and super** (`dashboards/Platform.tsx`, chosen in `app/page.tsx:117`). Sections: `StatsPanel` (student statistics summary); course-structure upload coverage tiles and two panels (from `/catalogue/upload-coverage`); "People and access" panel with "+ New person", "+ Grant an office", "Open the people console" and counts (people on record, with a sign-in, live grants, grants ending within 30 days) — shown to ict, admin, super, registrar, dregistrar; tiles "The service" (up/down, commit), "The database" (reachable, migrations applied, latest), "2025/2026 admission settings" (hard-coded session label; from `/platform/status`), "Acting as"; panel "What is actually true" (Service, Started, Latest migration, Actor, Acting office, Offices held; right side shows `API_URL`); panel "The outbox" (email/SMS provider wired?, waiting/sent/failed/sent in the last day, recent 50); "Danger zone — reset uploaded data" (`ResetData.tsx`, super and ict only) with three actions: "Remove demo courses only…" (type `REMOVE DEMO`), "Remove demo data only…" (type `REMOVE DEMO`), "Reset ALL uploaded data…" (type `RESET` + a reason). Closing note "How attribution works".

**Data Migration — `/migrations`** (`Migrations.tsx`): tiles Migrations applied / Latest / Running commit / Started; table Migration, Applied, By, Checksum (first 12 hex) from `public.schema_migration`. Second note says a legacy data migration "is not shown here because none has been run".

**Go-Live Readiness — `/readiness?session=`** (`Readiness.tsx`): session select (defaults to `intakeSession`), tiles Ready / Blocking / To review / Total checks, and the list of gates with pills Ready / Check / Blocking and a "Fix" link. Gates computed in `PlatformController.readiness` (lines 106-172): Applicant fee set (`admissions.applicant_fee_rule`), Admission policy in force, Session on the calendar (bad if absent, warn unless CURRENT), A semester is open, School-fee schedule set, Clearance scheme in force, Demo data removed (surname DEMO students / DMO-DMC courses), Exam-screened programmes set (always ok), Payment gateway configured (LIVE key ok, TEST warn, none bad), Email (SMTP) configured (`platform.mail_settings.smtp_host`), SMS configured (enabled and keyed). Session parameter must be `dddd/dddd` else `2026/2027` is used.

**Mail Server — `/platform/mail`** (`MailSettings.tsx`): three panels SMTP/IMAP/POP each with Server, Port, Encryption (STARTTLS/SSL/NONE; defaults smtp.office365.com 587 STARTTLS, outlook.office365.com 993 SSL, 995 SSL), panel "The account" (Username "The full email address", From address, "Password or app password" — pasted once; pill "Password set"/"No password"; "Save the settings" → `PUT /platform/mail`; "Clear the password" → `POST /platform/mail/clear-password`). Red note when `configKeyPresent` is false: "No passphrase to encrypt the password with — Set MOAUM_CONFIG_KEY (or MOAUM_AUTH_HMAC_SECRET)…". The closing note "Sending over SMTP arrives with the mail transport… once the SMTP transport is enabled on the API" is **stale**: `NoticeDispatcher` already sends through `SmtpMailer` when the settings are complete (`NoticeDispatcher.java:136-139`).

**SMS Gateway — `/platform/sms`** (`SmsSettings.tsx`): Username, Sender ID (≤ 11 chars), API key (pasted once), checkbox "Send SMS notices through eBulkSMS"; "Save the settings" → `PUT /platform/sms` (provider fixed `EBULKSMS`); "Clear the API key".

**Notifications / Notification Channels — `/notices`** (`notices/Notices.tsx`; route id `t/channels` for super else `t/notify`): note "No provider is wired, so nothing is being sent" when neither relay URL is set; tiles Waiting / Sent today / Failed / Sent, all time; panel "Providers" (Email provider, SMS provider — "None — MOAUM_NOTICES_EMAIL_URL is not set"); panel "The outbox" (When, To, Notice, Channel, Attempts, State: Sent / Failed + error + "Requeue" / Queued), button "Put all n failed back in the queue" → `POST /platform/notices/retry-failed`. **Caveat**: `emailProvider`/`smsProvider` reflect only the HTTP relay URLs (`NoticesController.java:37-38`, `NoticeDispatcher.emailConfigured()`), not the Mail-server or eBulkSMS settings, so this screen can say "No provider is wired" while SMTP/eBulkSMS delivery is in fact working.

**`/healthz`** (`app/healthz/route.ts`): `{status:"up", service:"moaum-portal"}`, no session. API: `/actuator/health` and `GET /api/v1/platform/status` (`service, commit, startedAt, database{reachable, migrationsApplied, latestMigration, admissionSettings2025_2026}`).

## 5 Workflow and statuses — the notice pipeline
1. A module calls `platform.queue_notice(channel, recipient, subject, body, about_kind, about_id)` inside its own transaction; a blank recipient returns NULL and queues nothing (function body, local DB). Row state `QUEUED`; `platform.notice.ck_notice_channel` = `EMAIL|SMS`; `ck_notice_state` = `QUEUED|SENT|FAILED`; `ck_notice_sent` (SENT needs `sent_at`). Attachments (V230) go in `platform.notice_attachment` (filename without slashes, ≤ 15 MB).
2. `NoticeDispatcher.dispatch()` runs every `MOAUM_NOTICES_EVERY_MS` (default 60 000 ms, first after 15 s) (`NoticeDispatcher.java:114`). If neither SMTP (Mail server screen), eBulkSMS (SMS screen, enabled + key) nor a relay URL is configured it logs once and returns — notices stay QUEUED. Otherwise it takes up to 50 `QUEUED` rows with `attempts < 5` oldest first; EMAIL goes by SMTP when the Mail settings are complete (multipart text + branded HTML with the crest from `MOAUM_PORTAL_URL/crest.png`, `SmtpMailer.java`), else by the email relay; SMS goes by eBulkSMS (`https://api.ebulksms.com/sendsms.json`, numbers normalised to `234…`) when enabled, else by the SMS relay. Relay payloads: generic `{to,subject,body,channel,id,attachments[]}`, `termii`, or `resend` (`MOAUM_NOTICES_*_FORMAT`).
3. Outcome written in a separate transaction attributed to NOBODY/`ict` "notice dispatch": success → `SENT`, `sent_at`, `provider_ref`; failure → `attempts+1`, `last_error` (≤ 400 chars), and `FAILED` on the fifth failure. Requeue resets `attempts` to 0 and state to `QUEUED` for `FAILED` rows only.
4. The recipient reads the same row: staff at `/me/notices` (rows whose `about_kind='person' AND about_id = me`, or whose recipient equals the person's email or phone); students on the student portal.

Reset/demo actions: `platform.reset_operational_data(confirm, reason)` refuses unless confirm = `RESET` ("type RESET to confirm clearing all uploaded data") and a reason is given; `remove_demo_data` / `remove_demo_courses` need `REMOVE DEMO`; all require an actor ("a data reset is made by a person").

## 6 Business rules and validations
- Mail: encryption must be STARTTLS/SSL/NONE (`MAIL_ENCRYPTION`); saving a password with no config key → `MAIL_NO_CONFIG_KEY`; singleton row (`ck_mail_singleton`), ports 1–65535. SMS: provider CHECK `EBULKSMS`, sender ≤ 11, `SMS_NO_CONFIG_KEY`. Passwords/keys are encrypted with `MOAUM_CONFIG_KEY` (falls back to the HMAC secret) by `platform.set_mail_settings`/`set_sms_settings` and decrypted only inside the dispatcher (`platform.mail_password(key)`, `platform.sms_api_key(key)`); the config functions return only `password_set`/`api_key_set`. Both settings tables are audit-exempt; the SET/CLEARED events (`platform.mail_settings_event`, `sms_settings_event`) are on the spine.
- Readiness accepts only a `dddd/dddd` session and defaults to `2026/2027` (hard-coded, `PlatformController.java:107`).
- `platform/status` reports the state of the **2025/2026** admission settings by name (line 207) — a fixed label carried from the prototype health check.

## 7 Notifications
This module is the transport; it originates none itself except the outbox retry (none).

## 8 Reports, exports and documents
None (the outbox table has the DTable Print button only).

## 9 Configuration
Tables: `platform.mail_settings` (singleton, encrypted password), `platform.sms_settings` (singleton, encrypted key, `enabled`), both empty by default (one row each in the local DB); env vars `MOAUM_NOTICES_EMAIL_URL`, `MOAUM_NOTICES_SMS_URL`, `MOAUM_NOTICES_TOKEN`, `MOAUM_NOTICES_SMS_FORMAT` (generic|termii), `MOAUM_NOTICES_SMS_FROM` (MOAUM), `MOAUM_NOTICES_EMAIL_FORMAT` (generic|resend), `MOAUM_NOTICES_EMAIL_FROM`, `MOAUM_NOTICES_EVERY_MS`, `MOAUM_NOTICES_INITIAL_MS`, `MOAUM_PORTAL_URL`, `MOAUM_CONFIG_KEY`, `MOAUM_COMMIT`/`RAILWAY_GIT_COMMIT_SHA`, `DB_POOL_SIZE`, `DATABASE_URL`/`JDBC_DATABASE_URL`/`PGUSER`/`PGPASSWORD`, `PORT`.

## 10 Data
`platform.notice` (attached; 1 398 rows locally, all QUEUED — no provider configured there), `platform.notice_attachment` (attached), `platform.number_series` (exempt; `platform.next_number(kind, scope, session)` hands out DSR, receipt, certificate… sequences), `platform.idempotency_key` and `platform.processed_event` (exempt; **no Java code reads or writes them** — grep found no reference outside the migrations: CONFIGURED BUT UNUSED), `platform.service_request`/`request_document` (student help requests, other group), `public.schema_migration` (the migrate.sh ledger; exempt).

## 11 Scheduled jobs and integrations
`NoticeDispatcher` (every minute). Other `@Scheduled` jobs in the API belong to other modules: deferment clock 06:20 Africa/Lagos, examiner reminders 07:15, helpdesk auto-closer hourly, hostel clock hourly. Integrations: SMTP (Microsoft 365 defaults), eBulkSMS, generic/Termii/Resend HTTP relays.

## 12 Security notes
- Secrets never leave the database in the clear; the screens only learn "set".
- `/api/v1/platform/status` is public and discloses the commit, start time, migration count and latest migration filename.
- Reset actions are guarded by a typed word and are recorded on the spine (the function body attributes every deletion to the actor); there is no second approver.

## 13 Implementation status
| Feature | Status | Evidence | Notes |
|---|---|---|---|
| Outbox + dispatcher (SMTP, eBulkSMS, relays) | IMPLEMENTED | `NoticeDispatcher.java` | delivery depends on configuration |
| Outbox screen provider indicator | PARTIALLY IMPLEMENTED | `NoticesController.java:37-38` | ignores SMTP/eBulkSMS settings |
| Mail / SMS settings screens | IMPLEMENTED | `MailSettings.tsx`, `SmsSettings.tsx` | Mail screen footer note stale |
| Readiness gates | IMPLEMENTED | `PlatformController.java:103-172` | default session hard-coded |
| Migration ledger screen | IMPLEMENTED | `Migrations.tsx` | |
| Reset / remove demo | IMPLEMENTED | `ResetData.tsx`, `platform.reset_operational_data` | |
| Idempotency keys / processed events | CONFIGURED BUT UNUSED | tables exist; no code | BFF forwards `Idempotency-Key` but nothing consumes it |
| Legacy data migration console | PLACEHOLDER | `Migrations.tsx:41-43` (text only) | |

## 14 Common problems and troubleshooting
- Notices stay "Queued" forever — no provider: set SMTP on Mail Server (username, host, password + `MOAUM_CONFIG_KEY`), or enable eBulkSMS, or set the relay URLs; the dispatcher logs "notices: no email account…".
- "Failed" with `provider answered 4xx` / `AuthenticationFailedException` — wrong relay token or mail password; fix and "Requeue".
- "No passphrase to encrypt the password with" — `MOAUM_CONFIG_KEY` (or the HMAC secret) unset on the API service.
- Readiness "Blocking": follow each "Fix" link; "Session on the calendar" needs a CURRENT session, i.e. a Senate minute (A5).

## 15 Glossary
**Outbox** — `platform.notice`, the queue of everything the portal intends to send. **Provider** — SMTP account, eBulkSMS account, or an HTTP relay. **Config key** — the passphrase that encrypts stored credentials. **Migration ledger** — `public.schema_migration` (filename, SHA-256, applied_at, applied_by).

---

# A4. Audit spine, audit trail and security posture  (API modules: auditlog, governance (security), platform (AttributedTransactionManager, CorrelationIdFilter, ProblemHandler); schema: audit; pages: /audit, /audit/revenue, /audit/staff, /audit/assets, /security, / (audit and security dashboards))

## 1 Purpose
Every attached table has an `AFTER INSERT OR UPDATE OR DELETE` trigger (`audit.record`) that writes a hash-chained entry naming the actor, the acting office, the reason and the correlation id read from transaction-local settings — and **refuses the write** when no actor/office is set. The application places those settings at the start of every transaction from the request's `AuditContext`. The Audit Log screen reads the entries together with staff and student sign-in events; the Security screen reads the spine's own figures and the sign-in defence. The three `/audit/*` sub-desks are the Internal Audit directorate's read-only views over other modules' data.

## 2 Users and roles
`OVERSIGHT` for `/api/v1/audit/entries` and `/facets` = ict, admin, super, audit, deputyaudit, vc (`AuditLogController.java:21`). `/api/v1/governance/security` = ict, audit, deputyaudit, security, registrar, vc, dvc, admin, super (`GovernanceController.java:129`). Screens: `/audit` menu for admin, ict, registrar, super, vc — but the Registrar's menu item "Audit Trail" opens a screen whose API refuses `registrar` (not in OVERSIGHT) → the Registrar sees a `ProblemNotice` 403. `/security` menu for admin, ict, super, vc. `/audit/revenue|staff|assets` are in the `audit` office menu only and read finance/payroll/stores endpoints.

## 3 Navigation
Audit Log / Audit Trail `t/audit` → `/audit` (super Administration; ict Administration; admin Administration; registrar Administration; vc Administration). Security / Security Posture `t/security` → `/security` (super, ict, admin, vc). audit office: Finance → Revenue & Student Income `/audit/revenue`, Assets Register `/audit/assets`; Staff → Staff Movements `/audit/staff`.

## 4 Screens
**Audit trail — `/audit?action=&office=`** (`AuditTrail.tsx`): note "The audit trail cannot be edited through the application"; tiles "Entries on the record" (audit.entries + sign_in_event + student_event counts), "Today", "Actors today", "Refusals today" (entries whose action ILIKE '%REFUS%' plus failed sign-ins); filters "Domain" (facets: `split_part(action, ':', 1)` over the last 30 days plus `auth`) and "Acting office" (last 30 days) — selecting one navigates with query params; table When, Actor (name or "System", office), Action (red pill when it matches /refus|denied|blocked/), Subject (type, first 8 chars of id), Reason; "Most recent n" (limit 200, max 500). Sign-in rows appear as action `auth:<outcome>` with subject `sign_in`/`student_sign_in` and the username/IP in the reason column. Empty: "No entry matches this filter." The closing note claims that refused database writes are on the trail; **that is not how the spine works** — `audit.record` is an AFTER trigger inside the same transaction, so a refused write (rolled back) leaves no entry; only actions a module explicitly records with a "REFUS…" action, and failed sign-ins, appear.

**Security posture — `/security`** (`Security.tsx`): note green/red on `unattached_tables`; tiles Audit entries (with shard count), Unattached tables, Failed sign-ins 7 days, Last audit entry; panel "The audit spine" (text claims "verified nightly across every shard… A nightly job recomputes the chain" — **no such job exists**: `audit.verify_chain` is called only from `db/check.sql:398,415`); "Sign-in defence" table (Signed in / Wrong password / Unknown username / Locked out, last 7 days, staff events only — `iam.sign_in_event`); "Accounts drawing failed attempts" (top 10 usernames).

**Audit dashboards at `/`**: `AuditDashboard` (audit, deputyaudit) — the same posture plus a 12-row recent-activity feed from `/audit/entries?limit=12` and links; `SecurityDashboard` (security) — posture only.

**Revenue & Student Income — `/audit/revenue?session=`** (default `2026/2027`, hard-coded): tiles from `/finance/bursary` (Fees collected, Confirmed today, Still owed, Open exceptions) and "Revenue by category" from `/reports/revenue`. **Staff Movements — `/audit/staff`**: establishment and pay runs from `/payroll/staff`, `/payroll/runs`. **Assets Register — `/audit/assets`**: `/stores/assets` with "Never verified"/"Overdue verification" (> 1 year) tiles. All read-only.

## 5 Workflow and statuses
`audit.record()` (function body, local DB): (1) reads `moaum.actor_id` and `moaum.actor_office`; missing → SQLSTATE 23514 "unattributed change to schema.table — no audit context on this transaction" with HINT "SET LOCAL moaum.actor_id and moaum.actor_office before writing. Every state change is attributable (P5, D6); there is no exemption." — which `ProblemHandler` turns into **403 `NO_ACTING_OFFICE`** ("This request names no acting office, so it may read but not change anything.", remedy "Send X-Active-Office with one of the offices your token carries."); an office not in `ref.office` → "no such office". (2) captures `before_state`/`after_state` as JSONB; the subject id is the row's own uuid `id`, else an md5-derived uuid over its primary key columns (`audit.subject_key`). (3) period = month, shard = `hashtext(subject) % 16`; `audit.ensure_partition` creates the monthly partition (`audit.entries_YYYYMM`, 24 pre-created through 2028-08 locally); the chain head row `(period, shard)` is locked `FOR UPDATE`, seq incremented. (4) `entry_hash = sha256(canonical(entry) || prev_hash)`; `audit.chain_head.last_hash/last_seq` advanced. `audit.canonical` concatenates id, UTC timestamp, seq, actor, office, action, subject, before, after, reason, correlation id. Action = trigger argument or `TG_OP` (INSERT/UPDATE/DELETE); modules that pass a name to `audit.attach(table, action)` get domain-prefixed actions (the facets split on `:`).
`audit.verify_chain(period)` recomputes every shard and reports `ok`, `first_break`, `broke_at`; `audit.unattached()` lists tables outside `audit`/`reporting` with neither an `audit.exemption` row nor a `trg_audit_%` trigger (the local DB lists ~55 `public.*` scratch tables left by integration tests — noise, not product tables). `audit.exempt(table, reason)` requires a reason longer than 20 characters (`ck_exemption_reason`).
Application side: `AttributedTransactionManager.doBegin` runs `set_config('moaum.actor_id'|'actor_office'|'reason'|'correlation_id'|'source_ip', …, true)` (transaction-local) whenever an `AuditContext` is on the thread; `CorrelationIdFilter` accepts/echoes `X-Correlation-Id` (a non-UUID is replaced) and puts it in MDC; `ProblemHandler` adds `correlationId` to every problem body.

## 6 Business rules and validations
- `audit.entries.ck_entries_office` (non-empty, ≤ 32 chars), `ck_entries_shard` (0–15).
- `verify.sql` asserts on every deploy: no application role holds DELETE anywhere; nothing may write to `audit.*`; an unattributed write is still refused (`db/verify.sql:18-53`).
- Problem mapping (`ProblemHandler.java`): `DomainRuleViolation` → 422 with `code`, `remedy{message, office}` and a human title (`TITLES` map, e.g. AUTH_LOCKED → "Account locked for now"); SQLSTATE 23514/23502/22P02/P0002/23P01 → 422 `DATABASE_RULE_REFUSED` with the HINT as remedy; 23505 → 409 `ALREADY_EXISTS`; 23503 → 409 `REFERENCE_MISSING`; 42501 → 403 `DATABASE_PERMISSION`; other DB errors → 422 `DATABASE_REFUSED` + `sqlstate`; bean validation → 400 `VALIDATION_FAILED` with `violations[]`; `NotFound` → 404.

## 7 Notifications
None.

## 8 Reports, exports and documents
DTable print only. No export of the audit trail; no chain-verification report screen.

## 9 Configuration
`audit.exemption` (relid, reason) — 50 rows locally, each with its written reason; wholesale exemptions: schemas `audit` and `reporting`. Attachment happens in migrations (`SELECT audit.attach('schema.table')`).

## 10 Data
`audit.entries` partitioned by month (id, occurred_at, period, shard, seq, actor_id, actor_office, action, subject_type, subject_id, before_state, after_state, reason, correlation_id, source_ip, prev_hash, entry_hash); `audit.chain_head` (period, shard, last_hash, last_seq); `audit.subject_key`; `audit.exemption`. All append-only from the application's point of view (no write grants).

## 11 Scheduled jobs and integrations
None. (Nightly verification is described on screen but not scheduled.)

## 12 Security notes
- The trail is read by six offices; `before_state/after_state` (full row JSON, including e.g. email/phone) are stored but not shown on the screen.
- `iam.credential`, `student_account`, gateway credentials, mail/SMS settings are exempt precisely so hashes/secrets never enter the trail.
- The Registrar's menu offers "Audit Trail" but the API denies the office (see §2) — a menu/guard mismatch.

## 13 Implementation status
| Feature | Status | Evidence | Notes |
|---|---|---|---|
| Hash-chained, refusing audit spine | IMPLEMENTED | `audit.record`, `AttributedTransactionManager.java` | proven by `AuditSpineIT` (README) |
| Audit trail screen with facets | IMPLEMENTED | `AuditTrail.tsx`, `AuditLogController.java` | before/after not shown |
| Security posture screen | IMPLEMENTED | `Security.tsx` | "nightly verification" claim unfounded |
| Chain verification job / report | NOT IMPLEMENTED | only `db/check.sql` calls `audit.verify_chain` | |
| Refusals on the trail | PARTIALLY IMPLEMENTED | trigger semantics; screen note | only explicit REFUS actions + failed sign-ins |
| Registrar access to /audit | NOT IMPLEMENTED (menu only) | menus.md 540 vs `AuditLogController.java:21` | |
| Audit directorate desks (revenue, staff, assets) | IMPLEMENTED (read-only over other modules) | `audit/*` pages | revenue default session hard-coded |

## 14 Common problems and troubleshooting
- 403 "This request names no acting office" — the office cookie is missing (choose an office top-left) or a batch job forgot to set a context.
- "no such office: x" — a token office code not in `ref.office` (dev token typo).
- Registrar opens Audit Trail and gets "You don't have access to this screen" — expected with the current guard.
- Posture shows "Unattached tables > 0" on a developer database — integration-test residue in `public`; on production it should be 0.

## 15 Glossary
**Spine** — the audit trigger + chain. **Shard** — one of 16 hash chains per month. **Chain head** — the last hash/seq of a shard. **Exemption** — a table deliberately kept off the spine with a written reason. **Correlation id** — the UUID tying a request, its log lines, its audit rows and its problem response.

---

# A5. Governance, disaster recovery and the framework pages  (API module: governance; schema: governance; pages: /governance, /disaster-recovery, /cloud, /release, /ethics)

## 1 Purpose
A small NDPA (Nigeria Data Protection Act 2023) register: the record of processing activities with their DPIA state, a log of data-subject rights requests with statutory due dates, and a disaster-recovery drill log against stated objectives. `/cloud`, `/release` and `/ethics` are explanatory pages with no data.

## 2 Users and roles
`READERS` = registrar, dregistrar, ict, audit, deputyaudit, vc, dvc, admin, super; `WRITERS` (DPIA, DSR) = registrar, dregistrar, ict, super; `ICT` (record a drill) = ict, super (`GovernanceController.java:26-28`). UI: `Governance.tsx:24` may = registrar, dregistrar, ict, super; `DisasterRecovery.tsx:24` may = ict, super.

## 3 Navigation
Governance / Data Governance `t/governance` → `/governance`: super, ict, admin, registrar (badge "2" is a prototype fixture in menus.md), vc. Backups & Recovery / Disaster Recovery `t/dr` → `/disaster-recovery`: super, ict. Cloud Readiness `/cloud`, Release Pipeline `/release`: ict. `/ethics` (`t/ethics`) is routed but in no menu.

## 4 Screens
**Data governance — `/governance`** (`Governance.tsx`): RoleLine "Keeping the processing register and DPIAs — worked by the Registrar, Deputy Registrar (Academic Affairs)"; tiles Processing activities / DPIAs outstanding / Open subject requests / Overdue requests; panel "Record of processing activities" (Activity, Lawful basis, Sensitive Yes/No, Retention, DPIA pill Not required / Outstanding / Complete, button "Mark done" for writers on OUTSTANDING → `POST /governance/register/{id}/dpia {state:"COMPLETE"}`); panel "Data-subject rights requests" (Reference, Type, Requester "received d Mon yyyy", Due (red when overdue), Status pill Received / In progress / Completed / Refused, buttons "Start" (→ IN_PROGRESS) and "Complete" → `POST /governance/dsr/{id}/advance`); panel "Log a data-subject request" (Type select Access/Rectification/Erasure/Portability/Objection, Requester required, Due "Defaults to 30 days") → `POST /governance/dsr` returns `DSR-YYYY-NNNN` (sequence from `platform.next_number('DSR','UNIVERSITY',year)`), note "<ref> logged". Empty states: "The register is empty.", "No data-subject request has been logged…".

**Disaster recovery — `/disaster-recovery`** (`DisasterRecovery.tsx`): note "A backup that has never been restored is not a backup … Continuous backup telemetry is not wired into the portal yet"; tiles Last restore verification / Last full DR drill / Drills on record / Failed drills; panel "Recovery objectives" — a static table (RPO ≤ 15 min · 5 min for results & finance; RTO ≤ 4 hours; restore verification every night; off-site replication daily; full DR drill twice yearly) — **targets typed in the TSX, not measured**; "Drill log" (Drill, Run on, RPO, RTO, Outcome); form "Record a drill" (Drill: Restore verification / Full DR drill / Failover / Backup; Run on; Outcome Passed/Partial/Failed; RPO achieved; RTO achieved; Note) → `POST /governance/dr`.

**Cloud Readiness — `/cloud`**, **Release Pipeline — `/release`**, **`/ethics`**: static notes and bullet lists; each says explicitly it is "not wired to live … telemetry" / "does not surface its own live build or deploy status" / "describes the process rather than showing counts". They call only `/iam/me` for the Shell.

## 5 Workflow and statuses
- DPIA state CHECK `NOT_REQUIRED | OUTSTANDING | COMPLETE` (`ck_pa_dpia`); the UI only moves OUTSTANDING → COMPLETE; the endpoint accepts any of the three (upper-cased) and the DB refuses others.
- DSR kind CHECK `ACCESS | RECTIFICATION | ERASURE | PORTABILITY | OBJECTION`; state CHECK `RECEIVED | IN_PROGRESS | COMPLETED | REFUSED`; new rows start `RECEIVED`, `received_on = today`, `due_on = given or today+30`. The UI offers Start and Complete; **REFUSED cannot be reached from the screen**. No notification, no note editing after the fact except through `advance` (note coalesced).
- Drill kind CHECK `RESTORE_VERIFY | FULL_DR | FAILOVER | BACKUP`; outcome `PASSED | FAILED | PARTIAL` (default PASSED); `ran_on` defaults to today.

## 6 Business rules and validations
Bean validation sizes (`state` ≤ 20, requester ≤ 200, note ≤ 400); reference UNIQUE; activity non-blank. Seed rows (local DB): 7 processing activities (Automated admission scoring — OUTSTANDING; Biometric identity verification at CBT — COMPLETE; CBT proctoring and session logging — OUTSTANDING; Health records — COMPLETE; Payment and financial records, Staff personnel and payroll records, Student academic records — NOT_REQUIRED). There is **no endpoint to add or edit a processing activity**; the register changes by migration.

## 7 Notifications
None.

## 8 Reports, exports and documents
None (DTable print only). The Registrar dashboard note "The NDPA Compliance Audit Return is due on 31 March" is static text (`Registrar.tsx:35`).

## 9 Configuration
`governance.processing_activity` seeded by V075; DR objectives are literals in `DisasterRecovery.tsx:62-68`.

## 10 Data
`governance.processing_activity`, `governance.dsr`, `governance.dr_drill` — all attached to the spine.

## 11 Scheduled jobs and integrations
None.

## 12 Security notes
Writers can complete a DSR without recording what was done; the note is optional. No link between a DSR and the subject's record (no subject id column).

## 13 Implementation status
| Feature | Status | Evidence | Notes |
|---|---|---|---|
| Processing register read + DPIA completion | IMPLEMENTED | `Governance.tsx`, `GovernanceController.java:50-64` | no add/edit of activities |
| DSR log, start, complete | IMPLEMENTED | same | REFUSED state unreachable from UI |
| DR drill log | IMPLEMENTED | `DisasterRecovery.tsx` | objectives are static text |
| Backup telemetry, RPO/RTO measurement | NOT IMPLEMENTED | screen says so | |
| /cloud, /release, /ethics | PLACEHOLDER | pages render text only, call only `/iam/me` | |

## 14 Common problems and troubleshooting
- "Mark done" invisible — acting office not in registrar/dregistrar/ict/super.
- DSR due date in the past shows red; there is no reminder.
- A 422 `DATABASE_RULE_REFUSED` on advance — a state outside the CHECK list was sent.

## 15 Glossary
**DPIA** — data-protection impact assessment. **DSR** — data-subject rights request (`DSR-YYYY-NNNN`). **RPO/RTO** — recovery point/time objectives.

---

# A6. API management  (API module: apimgmt; schema: apimgmt; page: /api-keys)

## 1 Purpose
Registers external consumers of the API (name, owner, space-separated scopes, optional daily quota) and issues them hashed, expiring keys shown once. It is a register only: **nothing in the API authenticates a request by API key** — grep finds `key_hash`/`mk_` only in the issue function; the security chain accepts JWTs alone (`SecurityConfig.java`). Scopes and quotas are stored, never enforced.

## 2 Users and roles
`OPERATORS` = ict, admin, super for all five endpoints (`ApiKeysController.java:26`). Menu: Integrations / API Management `t/api` → `/api-keys` for super, ict (badge "2" is a prototype fixture).

## 4 Screens
**Integrations — `/api-keys`** (`ApiKeys.tsx`): note "Every client is named, scoped and rate-limited, and no key lives longer than a year"; tiles Consumers (ACTIVE count / total), Live keys, Due for rotation (expiring within 14 days), one blank tile; button "+ Register a consumer" (modal: Client name, Owner, Scopes "Space-separated, e.g. catalogue:read verify:read", Daily quota optional) → `POST /apimgmt/consumers`; one panel per consumer (Scopes, Daily quota, Registered; buttons "Issue a key" → `window.prompt("Days until this key expires (max 366):", "365")` → `POST /consumers/{id}/keys` → modal "The key, shown once" with the plaintext `mk_<48 hex>`; "Deprecate" → confirm → `POST /consumers/{id}/deprecate`), table Key (`••••last4`), Issued, Expires (red when due), State (Revoked / Expired / "Due to rotate" + Revoke / Live + Revoke → `POST /keys/{id}/revoke`). Empty: "No consumer is registered…", "No key issued yet."

## 5 Workflow and statuses
Consumer `status` CHECK `ACTIVE | DEPRECATED`; deprecating revokes all its live keys (`apimgmt.deprecate_consumer`). Key: live = not revoked and not expired; `issue_key` clamps days to 1–366 (default 365), stores `sha256(key)` and `last4`, requires an actor and an ACTIVE consumer ("no active consumer to issue a key to", 23503 → 409). `revoke_key` refuses "no live key to revoke". `register_consumer` requires name, owner and scopes ("a consumer is named, owned and scoped").

## 6–12
Validation: name/owner ≤ 120, scopes ≤ 400. Notifications: none. Exports: none. Config: none. Data: `apimgmt.consumer`, `apimgmt.key` (both attached; empty locally). Security: keys are hashed at rest; but since no request path checks them, a leaked key grants nothing today.

## 13 Implementation status
| Feature | Status | Evidence | Notes |
|---|---|---|---|
| Consumer/key register with hashed one-time keys | IMPLEMENTED | `ApiKeysController.java`, `apimgmt.issue_key` | |
| API-key authentication, scope and quota enforcement | NOT IMPLEMENTED | no reader of `apimgmt.key` in `api/src/main/java` | the screen's "rate-limited" wording is aspirational |

## 14 Common problems
"no active consumer to issue a key to" — consumer deprecated. Lost key — revoke and issue another (plaintext is never recoverable).

## 15 Glossary
**Consumer** — a registered client. **Rotation** — issue new, switch, revoke old ("Due to rotate" = expires within 14 days).

---

# A7. Academic calendar and reference data  (API modules: calendar, ref; schemas: policy (academic_session, semester, level_limit), ref; pages: /calendar)

## 1 Purpose
The session/semester calendar every other module reads: which session is CURRENT (under a Senate minute), each semester's windows (lectures, registration, late registration, examinations, results due, query window) and the unit limits per level. The same screen runs the yearly roll-over (promote continuing students) and the "enrol all" backfill. `ref` serves the structure ladder (colleges → faculties → departments → programmes), the session list and courses to every signed-in office, pruned to the caller's scope.

## 2 Users and roles
Read: any authenticated user (`CalendarController` and `RefController` are `@PreAuthorize("isAuthenticated()")`). Write (`WRITERS`): academic, registrar, dregistrar, super, ict (`CalendarController.java:27-28`). Menu "Session & Semester Setup" `t/session` → `/calendar` appears for academic and super only (menus.md 225, 465); registrar/dregistrar/ict can write through the API but have no menu item. Structure pruning: department offices see their department/faculty/college and only the programmes their courses are offered to (lecturer), faculty offices their faculty (`RefRepository.java:24-86`); `/ref/courses` for a department office is forced to their own department (`scopedDept`).

## 4 Screens
**Session & semester setup — `/calendar?session=YYYY/YYYY`** (`SessionSetup.tsx`, `CalendarForms.tsx`, `SemesterLevelForms.tsx`). Panels in order: "Roll the register into a new session" (button "Roll into <session>" → confirm → `POST /calendar/sessions/{s}/roll-over {confirm:"ROLLOVER", reason}` → note "n continuing students promoted…"); "Match the loaded cohort to this session" ("Enrol all into <session>" → `POST …/enrol-all` → "n students enrolled … · already were · eligible"); info note (with an extra sentence for the Super Administrator); tiles Current session / Current semester / Registration (Open / Closed / —) / Score sheets due; "Academic sessions" table (Session, Opens, Closes, Senate minute, Students = `people.enrolment` count, State pill Current/Planned/Closed, action "Edit" or "Reopen") with "+ New session"; "Semesters of <session>" (Semester, Lectures, Registration closes, Examinations, Results due, State Open/Closed/"Not yet open", "Edit windows") with "+ New semester"; a pointer panel "Open the examination session" (→ `/examinations/sessions`); "Levels and unit limits" (Level, Applies to, Minimum units, Maximum units, On probation, "Carryover counts toward the maximum", Edit) with "+ New level".
Modals: **Setup new Session / Edit YYYY/YYYY** — Session (locked on edit, placeholder `2027/2028`), Opens, Closes, Semesters ("2" / "3 (Summer semester)"), Senate minute (placeholder `SEN/2027/…`), State (Planned/Current/Closed; hint "A session stays Planned until its Senate minute is recorded against it."); footer "End this session" (asks a reason, → `POST …/close`) and "Save the change". Saving with State=Current does `PUT /calendar/sessions/{s}` then `POST …/make-current {senateMinute}`; a client check refuses a name not matching `dddd/dddd` ("The session has to be named as the University names one"). **Windows for the … semester / New semester** — Semester (First/Second/…), State, Lectures from/to, Registration opens ("Makes the course form writable for cleared students."), Registration closes ("Freezes the register — and the register is what every score sheet is generated over."), Late registration closes, Examinations from ("Locks the examination roll.")/to, Score sheets due ("What the escalation clock counts from."), Result query window (free text, placeholder "seven days from release") → `PUT …/semesters/{n}`. **Edit level / New level** — Level (100–600 in the select; the DB also allows 700–900 and has rows for them), Applies to (All programmes / MBBS, LL.B and other five-year programmes / One programme), Minimum/Maximum units per semester, Maximum units on probation (blank = probation pronounced but no cut), Carryover counts (Yes/No), Senate minute → `PUT /calendar/levels/{level}`.

## 5 Workflow and statuses
Session `state` CHECK `PLANNED | CURRENT | CLOSED`; exactly one CURRENT (`uq_session_one_current` unique partial index); no two overlap (`ex_session_no_overlap` EXCLUDE on `daterange(starts_on, ends_on, '[]')`); CURRENT requires a non-blank `senate_minute` (`ck_session_current_has_minute`); name `^dddd/dddd$`; `ends_on > starts_on`; semesters 1–3. `makeCurrent` refuses without a minute (`CAL_MINUTE_REQUIRED`: "A session stays planned until its Senate minute is recorded against it, and none was given.") and closes whatever else is current in the same transaction; `saveSession` with state CURRENT does the same. Upsert keeps an existing minute/state when the form sends none. Semester `state` CHECK `NOT_YET_OPEN | OPEN | CLOSED`, number 1–3, date-order CHECKs (`ck_semester_reg`, `_lectures`, `_exams`); (session, number) unique. Level limit: level ∈ {100…900}, `max ≥ min ≥ 0`, `CAL_UNIT_RANGE` from the service, `probation_max_units ≥ 0`. Roll-over (`people.roll_over_session`): needs an actor, the word ROLLOVER, a reason, a `YYYY/YYYY` name; opens the session as PLANNED if new; idempotent. Enrol-all (`people.enrol_current_session`): needs an actor and a valid name.
Local DB state for context: 2025/2026 CLOSED, 2026/2027 PLANNED with two CLOSED semesters, plus integration-test residue sessions (2090/2091 … 9999/0000); no session is CURRENT there. Seeded level limits: 100–400 "All programmes" 18–24; 500 "MBBS, LL.B and other five-year programmes" 18–24; 600 "MBBS" 18–24; 700 "Postgraduate Diploma" 9–48; 800 "Master's degree" 6–48; 900 "MPhil / Doctoral degree" 0–48; all carryover_counts true; no probation ceiling set.

## 6 Business rules and validations
As §5; database errors surface as 422 `DATABASE_RULE_REFUSED` (e.g. an overlap → `23P01`; a second CURRENT → 409 `ALREADY_EXISTS` from the unique index).

## 7 Notifications
None.

## 8 Reports, exports and documents
None (tables print via DTable).

## 9 Configuration
This screen **is** the configuration: `policy.academic_session`, `policy.semester`, `policy.level_limit` (all attached to the spine). `ref.*` structure is edited under the Director of ICT's structure screens (other group); `ref.office` is migration-seeded.

## 10 Data
`policy.academic_session` (id, name UNIQUE, starts_on, ends_on, state, senate_minute, semesters), `policy.semester` (id, session, number, lectures_from/to, registration_opens/closes, late_registration_closes, exams_from/to, results_due, query_window, state), `policy.level_limit` (level PK, applies_to, min_units, max_units, carryover_counts, instrument, probation_max_units). `ref.office`, `ref.college`, `ref.faculty`, `ref.department`, `ref.programme` (code `^C[0-9]{5}$`, category `UNDER GRADUATE | POST GRADUATE`), `ref.unit`, `ref.unit_alias`.

## 11–12
No jobs. Security: readable by every office including students (structure and sessions are not sensitive); writes by five offices, every change on the spine with the acting office.

## 13 Implementation status
| Feature | Status | Evidence | Notes |
|---|---|---|---|
| Session/semester/level CRUD with DB rules | IMPLEMENTED | `SessionSetup.tsx`, `CalendarService.java` | |
| Make current under a minute; one current; no overlap | IMPLEMENTED | `CalendarService.java:110-123`, constraints | |
| Roll-over and enrol-all | IMPLEMENTED | `CalendarController.java:64-76`, `people.roll_over_session` | |
| Menu access for registrar/dregistrar/ict | PARTIALLY IMPLEMENTED | writers by guard, no menu item | reachable by URL |
| Level select 700–900 in the modal | PARTIALLY IMPLEMENTED | `SemesterLevelForms.tsx:18` LEVELS 100–600 | PG rows editable only via existing-row Edit |

## 14 Common problems and troubleshooting
- "A session stays planned until its Senate minute is recorded against it" — fill "Senate minute" before choosing Current.
- Overlap refusal (422 from `ex_session_no_overlap`) — the new session's dates overlap another (including test residue); fix the dates.
- Readiness says "No semester is open" — set a semester's State to Open here; setting exam dates does not open the examination session (that is `/examinations/sessions`).
- "type ROLLOVER to confirm…" — only if the client body was tampered; the screen sends the word.

## 15 Glossary
**Current session** — the one under a Senate minute that registration and results run in. **Semester window** — the dated gates on `policy.semester`. **Unit limit** — min/max units per level per semester. **Roll-over** — promote continuing students one level into the new session. **Scope bar ladder** — the structure `/ref/structure` returns, pruned to the office.

---

# A8. Home routing, dashboards, institutional overview and search  (API modules: reporting (overview), iam (me), student (search — read only here); pages: / (page.tsx + dashboards/*), /admin, /overview, /search)

## 1 Purpose
`/` is a router: it reads `/iam/me`, redirects single-purpose offices to their own home, and renders one of ~18 office dashboards for the rest. The dashboards are read models over other modules (nothing is entered on them); the Institutional overview (`/overview`) and the Administrator's desk (`/admin`) draw the same `reporting/overview` read model as charts and tables; `/search` finds one record across students, staff, courses and credentials.

## 2 Users and roles
`/api/v1/reporting/overview` `MANAGEMENT` = ict, admin, super, vc, dvc, registrar, dregistrar, academic, audit, bursar (`ReportingController.java:20`). `/api/v1/student/search` READERS of the student module (every staff office in the search menu). `/iam/me` any token.

## 3 Navigation
Dashboard `r/academic` → `/` (every menu's Overview group, various labels); Administrator Dashboard `r/admin` → `/admin` (admin); Institutional Overview `t/overview` → `/overview` (admin, dvc, registrar, vc); Search `t/search` → `/search` (every staff office; also the top bar "Search records" button and the `/` keyboard shortcut, `Shell.tsx:381-391`).

## 4 Screens
**Home router — `app/page.tsx`**: redirects applicant → `/applicant`; student → `/college/student` (CHS from 200 level) else `/student`; admin → `/admin`; vc → `/overview`; library → `/credentials/idcards`; provost/collegesecretary/financecontroller → `/college/dashboard`; mbbscoordinator → `/college/coordinator`; ictagent → `/helpdesk`; extexaminer → `/examiner` (lines 41-63). Then: ict/super → `PlatformDashboard` (A3); academic/dregistrar/records/dvc → `AcademicDashboard`; registrar → `RegistrarDashboard`; bursar → `BursarDashboard`; lecturer → `LecturerDashboard`; hod → `HodDashboard`; services → `ClinicDashboard`; exams/facultyexams → `ExamsDashboard`; hrm → `HrDashboard`; dean/facultyofficer → `DeanDashboard`; security → `SecurityDashboard`; audit/deputyaudit → `AuditDashboard`; housing → `HousingDashboard`; siwes → `SiwesDashboard`; pgschool → `PgSchoolDashboard`; pgsecretary → `PgSecretaryDashboard`; anything else → `OfficeDashboard` (a generic "arrives with its module" page with a hard-coded "Session 2026/2027" tile, `Office.tsx:22`). The session used is the CURRENT one from `/ref/sessions`, else the literal `2026/2027` (line 64).
Dashboards in this group's scope: **Registrar** — static NDPA-due note; `StatsPanel`; tiles Students on the register (`/student/students`), Staff on the register (`/iam/persons`, with accounts), Senate business (`/results/sheets` inWorkflow), Credentials in hand; "Registry business" table (admissions cycle, matriculation, convocation, name of the University — the last a static row); "Council and Senate" table with "—"/"No sitting recorded" placeholders. **Academic** — transcript/result-set note, `StatsPanel`, tiles, "Committed admission list", "Registration, by faculty" (Blocked at the Bursary column is "—"), "Credentials in hand" (verification requests row: "Public verification arrives with its module" — stale; verify exists in another module). Other dashboards (Lecturer, HOD, Dean, Exams, HR, Housing, Library, Clinic, PG School, SIWES, Bursar) read their own modules and are documented there; all follow the same shape: a leading `Note` stating the one thing waiting, `Tiles`, panels with `DTable`s, a "desks" panel of `LinkBtn`s.

**Institutional overview — `/overview?session=&sem=`** (`Overview.tsx`): `PeriodPicker`; `StatsPanel`; tiles Students on the register (→ `/reports/students`), Result sets expected, Past Senate (%), Never submitted; tiles Returns overdue / Returns due within 30 days (from `/reports/due`); panels: donut "Where the n result sets stand" (approved / pending in the chain / never submitted), donut "Students by level", stacked bars "Results by faculty" with a red note naming the faculty furthest behind, table "Results by faculty, in figures", line chart "The semester week by week" (cumulative submitted vs approved), bars "Students by faculty", grade spread A–F with a note when F ≥ 15 %. Empty states are per panel ("No score sheet exists for … yet"). **Administrator dashboard — `/admin`** (`Institution.tsx`): same read model with a "Scope" button row (The University / each faculty) that re-cuts tiles (Students, Result sets past Senate, Collected this session, Fees outstanding), the "Academic pipeline" donut with links "Chase the chain" / "To Senate" / "Unraised sheets", the "Money" table (Ledger / Chase / Report / Reconcile links) and "By faculty" bars.

**KPI definitions in `ReportingController.overview`** (`ReportingController.java:33-135`): `students.total` = `people.student` with `status='ACTIVE'` (by faculty via programme, by `current_level`); `results[]` per faculty over `assessment.score_sheet` of MAIN-kind exam sessions for the session/semester — expected = sheets, submitted = stage ≠ ENTRY, approved = published = stage PUBLISHED, in_progress = stage ≠ PUBLISHED; `collection` = `finance.collection_by_faculty(session)`; `grades` = latest `assessment.score` version per (sheet, student) on PUBLISHED sheets with outcome GRADED, banded on `assessment.grace_total(ca+exam)` at 70/60/50/45/40; `weeks` = weekly cumulative counts of `submitted_at`/`published_at` from the first submission (max 26 weeks); `uni.faculties/departments` = row counts of `ref.faculty`/`ref.department`.

**Search — `/search?q=&kind=`** (`Search.tsx`): a box (placeholder "Matriculation number, name, staff number, course code or verification code"), kind tabs Everything / Students / Staff / Courses / Credentials with hit counts, a no-query state with "What you can search for" examples and "Recent searches" (localStorage), a red note "Every search for a person is recorded against your account", an "Exact match on <identifier>" note with "Open <name>", and one panel per kind (Identifier, Name, Detail, Status, Action — student and staff rows open modals; course "Open" and credential "Verify" buttons are **disabled** with titles "The course screens are not on the portal yet" / "Verification is not on the portal yet", `Search.tsx:75,87`). The API writes each searched term to `people.search_log` (`SearchRepository.java:94`).

## 5–7
No state changes on these screens (search writes a log row). No notifications.

## 8 Reports, exports and documents
Charts are inline SVG (`components/proto/vz`); tables print via DTable. Tiles on Registrar/Academic/Overview link to the registers and returns (A9).

## 9–11
No configuration; the CURRENT session comes from the calendar. The `StatsPanel` component fetches `/stats/students/summary` client-side. No jobs.

## 12 Security notes
`/reporting/overview` has no scope cut (VC-level offices only). Search results honour the student module's readers; the search log is on the spine.

## 13 Implementation status
| Feature | Status | Evidence | Notes |
|---|---|---|---|
| Office → home routing | IMPLEMENTED | `app/page.tsx:41-63` | |
| Overview and Administrator desks (charts + tables) | IMPLEMENTED | `Overview.tsx`, `Institution.tsx`, `ReportingController.java` | |
| Generic `OfficeDashboard` | PLACEHOLDER (by design) | `Office.tsx` | hard-coded session tile |
| Registrar "Council and Senate" sittings | PLACEHOLDER | `Registrar.tsx:64-68` | "No sitting recorded" rows |
| Search: students/staff | IMPLEMENTED | `Search.tsx`, `SearchRepository` | |
| Search: open course / verify credential | PARTIALLY IMPLEMENTED | `Search.tsx:75,87` disabled buttons | hits are found; no target screen linked |

## 14 Common problems
- "Your Dean office is not tied to a faculty yet" / HOD equivalent — set the scope on the grant (A2).
- Overview empty — no CURRENT session or no exam session opened; the panels say which.
- Search finds a student but "Open" on a course does nothing — by design today.

## 15 Glossary
**Read model** — figures counted from the desks' own tables, never stored separately. **Never submitted** — expected sheets still at ENTRY. **Past Senate** — PUBLISHED sheets over expected.

---

# A9. Reports, returns, registers and student statistics  (API modules: reports, stats; schemas: reports, reporting; pages: /reports, /reports/*/view, /reports/students, /reports/staff, /reports/snapshots/[id], /stats, /stats/students)

## 1 Purpose
The returns desk lists the University's standard returns with a due register (what is due, when, and whether a kept copy answers it), runs each as a branded printable document with an Excel download, lets the owning office "Keep a copy" (a snapshot with a verification code), mark it filed, and email it with the PDF and workbook attached. Two whole-register views (students, staff) are filterable, paged, exportable. Student statistics (V257) is one engine every dashboard reads: students in study with their fee position and registration, drill-down to the rows behind any figure.

## 2 Users and roles
Guards (`ReportsController.java:27-41`, `SnapshotsController.java:42-45`, `RegistersController.java:31-34`, `StudentStatsController.java:34-40`):
- `ENROLMENT_READERS` (enrolment, registration-cause, carryovers): academic, registrar, dregistrar, records, dvc, vc, ict, admin, super, dean, facultyofficer, hod.
- `REVENUE_READERS` (revenue, expenditure, income-expenditure): bursar, registrar, dregistrar, academic, audit, ict, admin, super, vc, dvc.
- `PG_READERS` (postgraduate): + pgschool, pgsecretary. `STAFF_RATIO_READERS`: + hrm. `trends`: any of the above **except** dean, facultyofficer, hod.
- Snapshots/due register `READERS`: vc, dvc, registrar, dregistrar, academic, records, bursar, audit, deputyaudit, hrm, ict, admin, super, pgschool, pgsecretary — note dean/facultyofficer/hod are **not** readers, so their "Keep a copy" answers 403 and the toolbar says "Your office reads this return; the office that owns it keeps and files the copy." (`ReportToolbar.tsx:69`).
- Registers `READERS`: the snapshot readers plus dean, facultyofficer, hod.
- Stats `READERS`: registrar, dregistrar, bursar, academic, records, ict, admin, super, dvc, vc, pgschool, pgsecretary, provost, collegesecretary, financecontroller, dean, facultyofficer, hod, exams. Amounts (`payable/paid_amount/outstanding/last_reference`) only for `MONEY` offices: bursar, financecontroller, registrar, dregistrar, super, admin, pgschool, pgsecretary, provost, collegesecretary, dvc, vc.
Scope: `OfficeScope.reportScope()` cuts enrolment, registration-cause, carryovers, postgraduate, staff-ratio and both registers to the Dean's faculty or the HOD's department (rows filtered by faculty/department/programme name; option lists narrowed); stats bound: PG offices see `is_pg`, CHS offices `is_chs`, faculty/department offices their own unit. The client-side list of which office may "Run" each return is `frontend/src/lib/report.ts` REPORTS `offices` (e.g. revenue: bursar, registrar, dregistrar, academic, audit, ict, admin, super, vc, dvc).

## 3 Navigation
Reports group in every management menu: Reports & Returns `t/reports` → `/reports`, Student Register `t/regstudents` → `/reports/students`, Staff Register `t/regstaff` → `/reports/staff` (academic, admin, audit, bursar, dean, dregistrar, dvc, facultyofficer, hod, hrm, ict, pgschool, pgsecretary, records, registrar, super, vc). Student Statistics `t/studentstats` → `/stats` (Overview group of academic, admin, bursar, collegesecretary, dregistrar, financecontroller, hod, ict, pgschool, pgsecretary, provost, registrar, super, vc). Return views `/reports/<slug>/view` and kept copies `/reports/snapshots/<id>` are reached by buttons only.

## 4 Screens
**Reports & returns — `/reports?session=`** (`Reports.tsx`, title "Reports & returns"). Tiles Overdue / Due within 30 days / Kept copies / Filed. Panel "Due register" (`GET /reports/due`): Return (title, purpose, "· yours"), Owner, Frequency (Monthly / Per semester / Per session / On demand), Last due (+ period, "kept"/"filed" link), Next due, State pill — "Overdue · n days", "Due today" / "Due · n days ago" / "Due in n days", "Kept · not filed", "Filed", "On demand" — and a "Run"/"Open" button for offices allowed to run it (primary when pending). Panel "Session" (Reporting session select; "Financial returns read the calendar year the session opens in."). Panel "Registers — view all" (Student register / Staff register → Open). Panel "Kept copies" (last 12: Return, Period, Rows, Taken · by, Code, Filed pill, Open). Panel "Standard reports" (the returns the acting office may run, from `lib/report.ts`, each with owner, frequency, "Live · <session>", Run). `Trends` panels (A9 §8). Panel "Enrolment by faculty" (roll-up of the enrolment return; hidden for PG offices, which use the PG calendar's sessions).

**A return view — `/reports/<slug>/view?session=&sem=&due=`** (`reports/*/view/page.tsx`): rendered by `ReportDoc` standalone (outside the Shell, print-clean): crest, University name, title, subtitle (with the scope label "Faculty of …"/"Department of …" when cut), session, the table with totals row, a footing note, "Issued by the portal on <date> · <office>", serial `MOAUM/RPT/yyyymmdd/hhmmss`. Toolbar (`ReportToolbar.tsx`): "← All returns", "Keep a copy" (→ `POST /reports/snapshots` with report, title, subtitle, period, parameters = the URL query, dueOn, headers, rows, totals, note; result "Copy kept · verification code XXXX · open the kept copy"), "Download Excel" (crest-branded workbook built in the browser), "Print / Save as PDF" (`window.print()`). Slugs and sources: admissions (`/admissions/sessions/{s}/cycle`), enrolment, registration (`registration-cause`, `&sem=`), carryovers, staff-ratio, postgraduate, revenue, funding (`/funding/sessions/{s}/report`), expenditure (`?year=` first four digits of the session), income-expenditure, students, staff.

**Student register — `/reports/students?…`** and **Staff register — `/reports/staff?…`** (`RegisterDesk.tsx` + the two pages): filter panel (students: Faculty, Department, Programme, Level, Sex, Status, Entry mode, Entry session; staff: Faculty, Department, Rank, Category, Status, Office held) plus "Search" (students: "Name, matric, admission or JAMB number"; staff: "Name, staff number or email"), buttons "Search", "Clear filters", "Download Excel (n rows)" (fetches every matched row 500 at a time, `options=false`, and builds a branded workbook; a partial fetch alerts "The export stopped after…"), "Print / Save as PDF" (opens `/reports/<kind>/view` with the same query — prints up to 5 000 rows and marks the document PARTIAL beyond that). Tiles: students Matched / Active / Female–Male / Postgraduate; staff Matched / Academic / Active / Female–Male. Table paged 100 per page server-side (Previous/Next). Department and programme options narrow to the chosen faculty/department. Rows link to the student/staff modals.

**Kept copy — `/reports/snapshots/[id]`** (`page.tsx` + `FileReturn.tsx`): the snapshot printed exactly as taken (`ReportDoc kept=`: "Kept copy · taken <date> by <name> (<office>) · filed with <body> on <date> / not yet filed. Verification code <code> — check it at /verify/report/<code>"), serial `MOAUM/RPT/<code>`. Toolbar: "← All returns", status line, "Mark as filed" (modal: "Filed with" with a datalist NUC / JAMB / Council / State treasury / Senate / Management / School Board; Note) → `POST /reports/snapshots/{id}/file`; "Email this return" (modal: To — comma-separated; Message) → the frontend route `POST /reports/snapshots/[id]/email` builds the PDF (`lib/report-pdf.ts`) and the workbook server-side and calls `POST /api/v1/reports/snapshots/{id}/email` with both as base64 attachments; "Download Excel"; "Print / Save as PDF"; below, the dispatch list ("Sent to x · date · delivered to the mail server / failed — error / queued · files").

**Student statistics — `/stats?session=&semester=&fac=&dept=&prog=&level=&status=&degree=`** (`components/stats/StudentStats.tsx` via `app/stats/page.tsx`): PageHead "Student Statistics" with actions "Paid Not Registered", "Not Paid", "All Students"; scope filter bar; `StatTiles` (All students / School fees paid / Course registered / Paid but not registered / Not paid / No charge stated / Not registered — each a link to the detail); donut panels "Payment status" (with the open semester's registration-closes date) and "Registration status"; bar panels by faculty (or "faculty / school" for CHS), department, programme, degree type — click to narrow; tables "By faculty", "By department", "By programme", "By degree type" with each cell a link; "Quick actions" (View Paid Students / View Unpaid Students / View Paid Not Registered / View Registered Students / Export Report). Empty: "No students found". The same `StatsPanel` (compact tiles) is embedded on the Platform, Registrar, Academic, Bursar, HOD, PG dashboards and the Overview.

**Students behind a figure — `/stats/students?which=&q=&page=`** (`Detail.tsx`): breadcrumb Dashboard › Student Statistics › <figure>; PageHead with "Export Excel" / "Export PDF" / "Back to Statistics"; Search (server-side, "Student ID, name, programme, department, faculty or payment reference") and Figure select; table (S/N, Student + number + degree, Programme + dept + faculty, Level, Fees pill Paid / Part payment / Not paid / No charge, [Payable, Paid, Outstanding for money offices], Last payment + reference, Registration pill Locked/Approved/Endorsed/Submitted/Registered/Draft/Returned/"Not registered", Registered date, Open → `/students/{id}`); 50 per page; exports fetch all rows 500 at a time and use `brandedXlsx`/`brandedPrint` with a `MOAUM/STAT/…` serial and S/N first.

## 5 Workflow and statuses — the due register and kept copies
`reports.catalogue` (12 rows; `frequency` CHECK `MONTHLY | PER_SEMESTER | PER_SESSION | ON_DEMAND`; `ck_cat_due`: MONTHLY needs `due_day` 1–28, PER_SEMESTER/PER_SESSION need 1–3 `due_dates` `MM-DD`; `tracked_from` 2026-09-25 locally): admissions 12-31 (registrar), enrolment 12-31 (registrar), registration 03-31 & 08-31 (registrar), carryovers 10-31 (records), staff-ratio 12-31 (hrm), postgraduate 11-30 (pgschool), revenue day 10 monthly (bursar), funding 12-31 (bursar), expenditure day 10 monthly, income-expenditure day 10 monthly (bursar), students and staff ON_DEMAND. `reports.due_register(today)` computes `last_due`/`next_due` (`reports.due_around`), the snapshot answering each, and `state`: `ON_DEMAND`; `FILED`/`TAKEN` when a snapshot with `due_on = last_due` exists; `OVERDUE` when the last due date is more than 14 days past with nothing kept ("a fortnight's grace"); `DUE` otherwise; `days` = days late or days to next. A kept copy (`reports.snapshot`) records report, title, subtitle, period, parameters, `due_on` (the caller's, else the pending last due, else the next — `SnapshotsController.dueFor`), headers/rows/totals as JSONB (`ck_snap_rows`), row_count, note, taken_at/by/office, a UNIQUE `verification_code` generated by the database, and filing (`filed_to`, `filed_at`, `filed_by`, `filed_note`; `ck_snap_filed` keeps `filed_at` and `filed_to` together). Filing is once: a second `file` answers 409 "This snapshot is already filed, or does not exist". Emailing: 1–20 valid addresses ("Give at least one email address", "At most twenty recipients at a time"), attachments ≤ 15 MB in all, one notice per recipient with `about_kind='report_snapshot'`, subject "<title> · <period> — Rev. Fr. Moses Orshio Adasu University", body naming the verification code and `<portal-url>/verify/report/<code>`; dispatch states are those of the outbox (A3).

## 6 Business rules and KPI definitions
- **Enrolment**: `people.student` with `entry_session = :s`, status not in WITHDRAWN/EXPELLED/TRANSFERRED_OUT/DECEASED, by faculty/programme/`current_level`, split M/F/unstated.
- **Registration cause**: `registration.registration_cause(session, semester)` (V143) — expected, registered, not_registered, fee_blocked, cleared_idle per faculty/programme; `schemeInForce` = `policy.in_force('clearance','UNIVERSITY',today)`; the footing changes wording when no clearance scheme is in force.
- **Carryovers**: for ACTIVE/PROBATION students, course registrations APPROVED/LOCKED whose latest PUBLISHED `assessment.course_final` attempt has `points = 0`; grouped by faculty/programme/course; as at today regardless of the session parameter.
- **Revenue**: confirmed `finance.payment_reference` for the session by `purpose` plus confirmed `admissions.fee_reference` (APPLICATION → "Application & Post-UTME", ACCEPTANCE → "Acceptance").
- **Expenditure**: `expenditure.budget_performance(year)`; **Income & expenditure**: `finance.income_expenditure(1 Jan, 31 Dec)` with totals and surplus, plus the budget block.
- **Postgraduate**: per POST GRADUATE programme — session applications (state ≠ DRAFT), offered/accepted/admitted, register counts (entry_mode POSTGRADUATE, statuses ADMITTED/ACTIVE/PROBATION/DORMANT/GRADUATED) by sex and mode, researching (research stage not AWARDED/WITHDRAWN), awarded; award label from `admissions.pg_award_level` (900 MPhil/PhD, 800 Master's, else PGD); default session `admissions.pg_current_session()`.
- **Staff ratio**: academic staff = `hrm.staff_record` rows with a home department whose person holds a live lecturer/hod/dean office; rank buckets by `present_rank` text (PROFESSOR/READER; SENIOR LECTURER; LECTURER; ASSISTANT/GRADUATE); students = ADMITTED/ACTIVE/PROBATION under the department's programmes; ratio = students/academic (1 dp).
- **Trends**: last three `dddd/dddd` sessions (admitted by entry_session, F/M, PG, candidates, offered = offer_state ADMITTED/ACCEPTED, accepted, PG applications/offers, fees confirmed) and the last six calendar months (fees confirmed, payments, vouchers paid/raised).
- **Registers**: students — every `people.student` joined to programme/faculty, filters as listed, `size` ≤ 500; staff — every `iam.person` with a staff number, joined to `hrm.staff_record`/`hrm.employment`; category from employment else "ACADEMIC" if the person holds lecturer/hod/dean/pgschool/provost; status ENDED when `ended_on` set or employment ENDED.
- **Student statistics** (`reporting.student_positions`, comment on the local DB): population = students with status ACTIVE, PROBATION or ADMITTED; **paid** = the charge for the period is fully covered (`finance.payment_position`; whole session uses all payments, a semester uses payments applied to it); `pay_status` = NO_CHARGE (payable 0) / FULLY_PAID / PART_PAYMENT / NOT_PAID; **registered** = the student's own register holds a SUBMITTED/APPROVED/LOCKED registration (undergraduate), SUBMITTED/ENDORSED (postgraduate), or the College enrolment (semester) is registered; "paid but not registered" = paid AND NOT registered; "not paid" = PART_PAYMENT or NOT_PAID; a student with no charge is neither. The summary is cached per (bound, filters) for 60 s in the API process (`StudentStatsController.java:47-52`).

## 7 Notifications
| event | trigger | recipient | channel | subject |
|---|---|---|---|---|
| Kept return emailed | `SnapshotsController.email` → `NoticeRepository.queueEmail` (+ attachments) | each address typed | EMAIL | "<title> · <period> — Rev. Fr. Moses Orshio Adasu University" |

## 8 Reports, exports and documents
Every return: on-screen branded document, browser print-to-PDF, crest-branded `.xlsx` (`buildXlsx` with school, title, generated date, logo); kept copies additionally a server-built PDF (`lib/report-pdf.ts`) for email; register exports (`students-register-<date>.xlsx`, `staff-register-<date>.xlsx`); statistics exports (`brandedXlsx`/`brandedPrint`, serial `MOAUM/STAT/yyyymmdd/hhmmss-rr`, S/N first, names A–Z). Verification: a kept copy's `verification_code` is printed in the footing and checkable at `/verify/report/<code>` (the public verify module — outside this group; the URL is emitted by `SnapshotsController.java:93` and `ReportDoc.tsx:94`).

## 9 Configuration
`reports.catalogue` (slug, title, owner_office, owner_label, frequency, purpose, due_day, due_dates, sort_order, active, tracked_from) — seeded by V229, edited only by migration (attached to the spine). The client list `lib/report.ts` REPORTS duplicates titles/owners/offices and must be kept in step by hand.

## 10 Data
`reports.snapshot` (write-once except the filing columns; attached), `reports.catalogue` (attached); `reporting.student_positions` is a set-returning function (the `reporting` schema is exempt wholesale as derived read models). `people.search_log`.

## 11 Scheduled jobs and integrations
None; no reminder is sent for a due or overdue return.

## 12 Security notes
Money figures in statistics are stripped server-side for non-money offices (`StudentStatsController.java:266`); returns cut to scope by name matching (`inScope`) — a programme name collision across departments would leak a row, and the carryover query passes a Postgres array literal built from programme names (quoted/escaped, `ReportsController.java:186-191`).

## 13 Implementation status
| Feature | Status | Evidence | Notes |
|---|---|---|---|
| Due register with states and grace | IMPLEMENTED | `reports.due_register`, `Reports.tsx` | |
| Twelve returns as branded documents + Excel | IMPLEMENTED | `reports/*/view/page.tsx` | admissions/funding read other modules |
| Keep a copy, file, email with attachments | IMPLEMENTED | `SnapshotsController.java`, `FileReturn.tsx`, `email/route.ts` | delivery needs a provider |
| Trends | IMPLEMENTED | `Trends.tsx` | hidden from dean/facultyofficer/hod by guard |
| Student/staff registers with export | IMPLEMENTED | `RegisterDesk.tsx`, `RegistersController.java` | print view capped at 5 000 rows |
| Student statistics + drill-down + exports | IMPLEMENTED | `StudentStatsController.java`, `StudentStats.tsx`, `Detail.tsx` | |
| Deans/HODs keeping a copy | NOT IMPLEMENTED (by guard) | `SnapshotsController.java:42-45` | toolbar explains |
| Due/overdue reminders | NOT IMPLEMENTED | no job | |

## 14 Common problems and troubleshooting
- "Your office reads this return; the office that owns it keeps and files the copy." — Dean/Faculty Officer/HOD pressed Keep a copy.
- "This snapshot is already filed, or does not exist" — filing is once.
- Emailed return stays "queued" — outbox has no provider (A3).
- Registration return says "No clearance scheme is in force…" — Bursar must put a scheme in force before the fee-blocked split means anything.
- PARTIAL on the printed register — over 5 000 rows; narrow filters or use Excel.
- Statistics figure looks stale by up to a minute — summary cache TTL 60 s.

## 15 Glossary
**Return** — a statutory/management report read off the register. **Due register** — `reports.due_register`, one row per return. **Kept copy / snapshot** — the rows of a return as they were, with a verification code. **Filed** — recorded as sent to the body it is for. **Grace** — 14 days after a due date before OVERDUE. **Paid / registered** (statistics) — as defined by `reporting.student_positions`.

---

# A10. Design system and the Shell  (frontend/src/app/globals.css, frontend/src/styles/prototype.css, frontend/src/components/proto/ui.tsx, blocks.tsx, DTable.tsx, Toast.tsx, Shell.tsx; frontend/src/lib/menus.ts, titles.ts, offices.ts)

## 1 Purpose
One stylesheet (`globals.css` imports `fonts.css` and `styles/prototype.css`) and a small React kit reproduce the prototype's markup so its CSS styles the portal identically. The Shell renders the sidebar (crest, "Signed in as" office select, folded menu groups with waiting counts, collapse control, foot with sign-out), the top bar (menu button, breadcrumb, title/subtitle, identity chip, search) and the content column.

## 2 Tokens (`prototype.css:4-57`)
Colours: `--chrome #0E3F55` (primary, sidebar, primary buttons), `--chrome-2 #1B5A76`, `--chrome-ink #A8CFE2`, `--chrome-dim #7FB2CA`, `--sky #2CAAE1` / `--sky-bg #E8F5FB` / `--sky-line #B6DDF0` (info), `--red #ED1B23` / `--red-ink #B01218` / `--red-deep #8E1015` / `--red-bg #FDEAEB` / `--red-line #F6BCBF` (danger/urgent), `--green #0CA54E` / `--green-ink #0A7A3B` / `--green-bg #E6F6ED` / `--green-line #A9E0C1` (ok/go), `--amber #B7791F` / `--amber-ink #8A5A12` / `--amber-bg #FBF3E2` / `--amber-line #EFD9A6` (warn), `--ink #221F20`, `--muted #5C6570`, `--faint #656E79`, `--bg #F4F6F8`, `--surface #FFFFFF`, `--line #DEE3E8`, `--line-2 #ECEFF2`, `--field #C3CBD3`, `--disabled #E2E7EC`, `--scrim rgba(11,51,69,.35)`. Typography: `--sans "IBM Plex Sans"`, `--serif "IBM Plex Serif"` (login heading, nav brand, report titles), `--mono "IBM Plex Mono"`; self-hosted from `public/fonts` (`layout.tsx:5-6`); body 14 px / 1.5, `-webkit-font-smoothing: antialiased`; type scale `--t-xs 11.5` … `--t-3xl 28`; `.tnum` tabular numerals for every identifier and figure. Spacing `--s-1 4px` … `--s-8 40px`; radii `--r-sm 4`, `--r 6`, `--r-md 8`, `--r-lg 12`, `--r-xl 16`, `--r-pill 999`; shadows `--sh-1/2/3`. The login page alone is re-coloured to the University website's navy/red/gold (`.login-wrap` scope, `prototype.css:108-118`). Focus ring `2px solid var(--sky)`; `prefers-reduced-motion` disables animation.

## 3 Components (`ui.tsx`, `blocks.tsx`)
`PageHead` (in-content title, description, actions, eyebrow); `Tabs` (segmented, or `look="line"`; counts); `Note kind=info|ok|bad` (the `.notice` box with icon, title, text, optional action); `Btn kind=primary|secondary|ghost|go|urgent size=sm|md` (`.btn--primary` chrome, `--secondary` sky tint, `--ghost` outline, `--go` green-ink, `--urgent` red #D6151C; sm 36 px / md 44 px min-height, 44 px on touch widths); `LinkBtn` (same classes on a `Link`); `IcoBtn` (icon-only with aria-label); `RoleLine` (who may act, "You may act — <office>" / "Signed in as <office> · view only"); `Pil kind=grey|info|ok|bad|warn`; `Two` (bold + sub line); `Tiles` (KPI tiles: eyebrow, `.n` 29 px figure — auto-shrinks for long strings —, caption, optional link); `Panel`/`PBody` (`.card`, `.card__head`, `.card__title`, `.card__body`); `KvGrid`; `Ico` (inline SVG glyph set). `blocks.tsx`: `Step/Steps`, `Gate/Gates`, `Row`, `Bar` (meter), `TwoCol`, `Passport` (photo with silhouette fallback), `Modal` (`.mdl` scrim, `.mdl__box` max-width 560 / `is-wide`, Escape and backdrop close, head/body/foot), `Field` (label, control, hint, `required` asterisk, `error` line + `.is-error`), `Num`, `money`/`day`. `DTable` (`cols` "Header|num|mid", data-l labels for stacked layout, search box when > 8 rows with `texts`, paging 10/25/50/100/All, footer count, a Print button that prints the whole table in a hidden iframe, `pageSize={0}` for server-paged lists, auto-stack when wider than its wrap). `Toast` (`notify`, `toast.*`, `notifyProblem` — success 4 s, info 5 s, warn 6 s, error 7 s, network/server errors sticky, max 5, de-duplicated within 2.5 s; 401 → "You are signed out", 403 → "You do not have access to that", 400 → "Please check the form", 409/422 → the refusal's own title). `ProblemNotice` shows a problem's title (humanised), detail, "What to do: <remedy> — <office>" and field violations. Report documents use the `.rpt*` classes in `globals.css:32-69` (900 px paper, crest header, chrome table header, print rules).

## 4 Layout and responsive rules
Shell: `.shell` flex; `.nav` 244 px sticky sidebar in `--chrome`, collapsible to 62 px (`body.nav-slim`, icons only, badges float); `.topbar` sticky with the title (`h1` 19–20 px) and subtitle; `.content` padding 22/24 px, gap 18 px. Breakpoints: ≤ 1180 (misc), ≤ 900 px — sidebar becomes an off-canvas drawer (`body.nav-open`, scrim, `.menu-btn` shown; the collapse button hidden; the search button loses its label), ≤ 760 px — `.card__body` scrolls horizontally, tiles two-up (`grid--4` → 2 columns, `grid--2/3` → 1), `.tile .n` 24 px, buttons 44 px tall, inputs 44 px; ≤ 620/660 px modal and misc tweaks; print hides `.shell, .topbar, .nav, .scrim, .login-wrap, .doc-bar` (`prototype.css:1220`). Grids: `grid--2/3/4/5` auto-fit min 280/240/190/160 px. Single-line inputs are capped at 460 px, numeric at 200 px (`globals.css:76-77`). `img { max-width: 100% }`.

## 5 The Shell (`Shell.tsx`)
- `ROUTES` maps every prototype menu id to a URL (lines 22-252); a menu item with no route renders as a button that shows the notice "<label> is still the prototype's screen" (lines 481-483, 540-556). Unrouted ids in this group's menus: `t/platform` (ict/admin/super home), `t/setup` (super home), `t/mgmt` (dregistrar/dvc home), `r/registrar`, `r/bursar` etc. — the home item goes to `/` (`href()` line 404).
- Menu selection: `me.menu` (a postgraduate student's School menu) → `MENUS[activeOffice]` → `FALLBACK` (label "Office"; groups Records: Search, Dashboard; Me: Leave & Payslip) for an office the prototype drew no menu for (lines 313-320, 364).
- Titles: `TITLES` = prototype titles overridden by `OVERRIDES` (lines 256-311); a page can pass live `title`/`sub`.
- Office switcher: the `<select id="office">` writes the `moaum_office` cookie (path `/`, one year, `samesite=lax`) and `router.refresh()`; options are the token's offices with `roleLabel` (lines 393-396, 441-448). Group badges sum the `waiting` map; an open group shows per-item badges (lines 338-346, 458-472). Breadcrumb = group name › item label when the item label differs from the page title. Sign-out button in the foot; identity chip in the top bar; "Search records ⌘/" button and the `/` shortcut.
- `lib/offices.ts`: `OFFICE_LABELS` (DB labels), `ROLE_LABELS` (prototype label + unit, e.g. hod → "Head of Department" / "Mathematics & Computer Science"), `roleLabel`, `roleUnit`. `lib/menus.ts` (1 797 lines) holds every office's groups/items; `lib/titles.ts` the prototype titles.

## 13 Implementation status
| Feature | Status | Evidence | Notes |
|---|---|---|---|
| Token/kit/utility design system | IMPLEMENTED | `prototype.css`, `ui.tsx`, `blocks.tsx` | no dark mode |
| Responsive shell (drawer ≤ 900, stacking ≤ 760) | IMPLEMENTED | `prototype.css:247-258, 489-551` | |
| Menu items without a portal screen | PLACEHOLDER (announced) | `Shell.tsx:481-483` notice | e.g. `t/platform`, `t/setup`, `t/mgmt` |
| Fallback menu for unknown offices | IMPLEMENTED | `Shell.tsx:313-320` | |
| Office switch updates `platform.session.active_office` | NOT IMPLEMENTED | cookie only | audit uses the header, so attribution is still correct |

## 15 Glossary
**Route id** — the prototype's menu item id (`t/…`, `r/…`, `s/…`, `a/…`, `x/…`, `pg/…`). **Waiting badge** — the count from `iam/me.waiting`. **nav-slim / nav-open** — body classes for the collapsed sidebar and the mobile drawer.

---

# K. Deployment and configuration

**Repository shape.** `api/` Spring Boot 4.1 (Java 21, Spring Modulith, JDBC), `frontend/` Next.js 16 App Router (standalone output), `db/` migrations V001–V263 + `verify.sql`, `check.sql`, `migrate.sh`, `demo.sql`/`demo.sh`, `proto/` + `public/index.html` the HTML prototype, `web/server.js` its server. README's "What this is not, yet" and `api/README.md` "Endpoints so far" are **out of date** (they describe two modules; 47 exist).

**Images and services (Railway, per README "Deploying on Railway").** `Postgres`; `moaum-api` — `api/Dockerfile` (Temurin 21 build → JRE runtime with `postgresql-client`, copies `db/`), `api/railway.json`: `preDeployCommand: bash db/migrate.sh`, health `/actuator/health` (timeout 300), restart ON_FAILURE ×5, 1 replica, `JAVA_TOOL_OPTIONS=-XX:MaxRAMPercentage=75 -XX:+UseSerialGC`, port 8081; `moaum-portal` — `frontend/Dockerfile` (node:22-alpine, `npm ci`, `npm run build`, runs `server.js` as user `portal`, `HOSTNAME=::`, port 3000), `frontend/railway.json` health `/`; `moaum-prototype` — root `Dockerfile` (node:22-slim + postgresql-client), `web/railway.json` start `node web/server.js`, health `/healthz`. Only the API's pre-deploy migrates; `migrate.sh` keeps `public.schema_migration` (filename, SHA-256, applied_at, applied_by) and **stops the deployment when an applied file has changed** (README "The migration runner"); `verify.sql` runs after and raises on: any application role holding DELETE, any write grant on `audit.*`, an unattributed write not being refused, office count (33 asserted; 34 in the local DB), programme count, presence of the 2025/2026 admission settings.

**Environment variables (names only).** API: `PORT`, `DATABASE_URL` (Railway shape, parsed by `DatabaseUrlConfig`) or `JDBC_DATABASE_URL`/`PGUSER`/`PGPASSWORD`, `DB_POOL_SIZE`, `MOAUM_AUTH_HMAC_SECRET` (≥ 32 bytes) or `MOAUM_AUTH_ISSUER_URI`, `MOAUM_CONFIG_KEY`, `MOAUM_PORTAL_URL`, `MOAUM_COMMIT`/`RAILWAY_GIT_COMMIT_SHA`, `MOAUM_NOTICES_EMAIL_URL`, `MOAUM_NOTICES_SMS_URL`, `MOAUM_NOTICES_TOKEN`, `MOAUM_NOTICES_SMS_FORMAT`, `MOAUM_NOTICES_SMS_FROM`, `MOAUM_NOTICES_EMAIL_FORMAT`, `MOAUM_NOTICES_EMAIL_FROM`, `MOAUM_NOTICES_EVERY_MS`, `MOAUM_NOTICES_INITIAL_MS`, `MOAUM_SSO_ISSUER`, `MOAUM_SSO_CLIENT_ID`, `MOAUM_SSO_CLIENT_SECRET`, `MOAUM_SSO_REQUIRE_MFA`, `MOAUM_SSO_MFA_ACR`, `MOAUM_SSO_STAFF_CLAIM`, `MOAUM_SSO_LABEL`, `MOAUM_PAYSTACK_SECRET`, `MOAUM_FLUTTERWAVE_SECRET`, `MOAUM_FLUTTERWAVE_HASH` (payments, other group), plus `moaum.deferments.cron`, `moaum.hostel.cron` properties. Frontend: `PORTAL_API_URL` (private network `http://moaum-api.railway.internal:8081`), `PORTAL_API_TOKEN` and `PORTAL_ACTIVE_OFFICE` (development bypass only; ignored in production by `proxy.ts:72` and `lib/session.ts:15`), `PORT`, `NEXT_TELEMETRY_DISABLED`. Actuator exposes `health,info` only, details never (`application.properties:51-53`).

**CI gates (`.github/workflows/ci.yml`).** Jobs: `web` — rebuild the prototype and run 11 Playwright harnesses; byte-compare `public/index.html`; `db` — Postgres 17, `db/migrate.sh`, second run must say "0 applied", an edited migration must be refused, `check.sql` must print "FOUNDATION GREEN" (see memory note: this grep is known to be vacuous), `verify.sql`, `demo.sh` twice then `verify.sql`; `api` — migrations then `./mvnw verify` (unit tests, Modulith boundaries, `AuditSpineIT`, `ApiIT`); `frontend` — `npm test`, `npm run lint`, `npm run build`; `image` (needs web, db, api) — builds the three images, migrates from inside the image, checks `/readyz`, `/actuator/health`, `/api/v1/platform/status` reachable, `/iam/me` → 401 without a token, bootstraps `ci-boot` through `/api/v1/auth/bootstrap`, signs in through `/api/auth/sign-in` as office `ict`, expects the platform dashboard ("What is actually true") and the Registrar dashboard ("Registry business"), and that the latest migration filename is rendered. Railway deploys only after CI is green ("Wait for CI").

**Demo accounts (`docs/demo-accounts.md`).** `bash db/demo.sh` once; password for every account as printed in that file; staff `demo.<office>` for every office; students `MOAUM/MTC/26/9901` … `9908`; applicant `20269999DM` / `demo.applicant@example.com`. Removed from a live system by "Remove demo data only" (A3).

**Go-live checklist (`docs/go-live-readiness.md`)** orders the setup: calendar & session (`/calendar`), structure, admission policy, CAPS intake, courses, allocation, fees & clearance, photos & records, accounts & access (`/people`, one sign-in of each kind), dry run; the live equivalent is `/readiness` (A3).

---

# Cross-group summary of PARTIAL / PLACEHOLDER / UNUSED items

| Item | Status | Where |
|---|---|---|
| Sessions list/end (own) | backend only | A1 |
| Registrar ending another's session; rate limiting | not implemented | A1 |
| Keycloak SSO | coded, not deployed | A1 |
| Ending a person from the UI | not implemented | A2 |
| Outbox "provider wired" indicator ignores SMTP/eBulkSMS | partial | A3 |
| Mail-server screen footer says SMTP "not yet enabled" | stale text | A3 |
| `platform.idempotency_key`, `platform.processed_event` | configured but unused | A3 |
| Nightly chain verification (claimed on Security screen) | not implemented | A4 |
| Refused writes "on the trail" (claimed) | only explicit REFUS actions/sign-ins | A4 |
| Registrar menu → `/audit` denied by guard | mismatch | A4 |
| Processing-activity add/edit; DSR REFUSED state | not reachable | A5 |
| DR objectives / telemetry; `/cloud`, `/release`, `/ethics` | static / placeholder | A5 |
| API-key authentication, scopes, quotas | not implemented (register only) | A6 |
| Calendar menu for registrar/dregistrar/ict; level select 700–900 | partial | A7 |
| Generic `OfficeDashboard`; Registrar "Council and Senate"; hard-coded `2026/2027` fallbacks | placeholder | A8, A3 |
| Search: open course / verify credential buttons | disabled | A8 |
| Keep-a-copy for dean/facultyofficer/hod; due-return reminders | not implemented | A9 |
| Prototype-only menu items (`t/platform`, `t/setup`, `t/mgmt`) | announced placeholders | A10 |
