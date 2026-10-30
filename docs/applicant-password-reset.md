# Post-UTME applicant passwords reset by the University (V687, 28 October 2026)

The University's word: "i want password reset for postutme applicants, let the ict director, academic office and ICT support staff
to reset postutme applicants password".

Until now an applicant who forgot their password could only ask for a link on the sign-in page ("Forgot password"); nobody at the
University could reset one.

## Who

**Applicant Password Reset** (`/admissions/applicant-passwords`, route `t/applicantpw`):

- The Director of ICT (`ict`), next to Student Password Reset.
- The Academic Office (`academic`), under Admissions.
- ICT Support (`ictagent`, `helpdeskhead`), next to Student Password Reset.
- The Database Operators (`dbops`, V688), under Academic, on a grant over the whole University only: an operator held to a faculty,
  department or programme is refused (`SCOPE_UNIVERSITY`), as an applicant belongs to none of them yet.
- The Super Administrator.

Every other office is refused, by the API and by the database (`APW_OFFICE`).

The desk covers every account that signs in at the applicant door: Post-UTME, Direct Entry, the Centre's (CCE) and Preliminary
Science applicants. JUPEB candidates and postgraduate applicants have their own portals and are not on it.

## How

1. **Find the applicant.** Type their JAMB number, application number, email, phone (`0…` or `+234…`) or name, three characters or
   more. Each row shows the account's state: active, locked after failed sign-ins, a temporary password pending, or the first sign-in
   not yet made.
2. **Reset the password**, saying why in ten characters or more (`APW_REASON`). There are two methods:
   - **Temporary password**, for an applicant with you or on the phone. A random twelve-character password is shown once. It works
     for 24 hours. The account is unlocked and its open sessions are ended. At the sign-in the applicant must choose their own
     password: until they do, the portal opens nothing else (`PASSWORD_CHANGE_REQUIRED`, on the server).
   - **Reset link**, the applicant's own one-hour link, sent to the email and phone they registered. The desk sees only where it
     went, masked. At most three links an hour reach one applicant, counting the ones they ask for themselves (`APW_LINK_LIMIT`).

The officer never chooses or sees the applicant's own password. The applicant is told by email and SMS either way.

Every reset is written once on `admissions.applicant_password_reset`: the method, the reason, where a link went, whether the account
was locked, the sessions ended, the officer and the office. The desk lists the resets made, and each applicant's own.

## The applicant

- A temporary password signs in to **Change password** (`/applicant/password`). The applicant enters the temporary password, then
  their own: eight characters or more, not their JAMB or application number, not the one they have. Then their application opens.
- An expired temporary password is refused at the sign-in (`AUTH_TEMP_PASSWORD_EXPIRED`), with the advice to ask again or use
  "Forgot password".
- **Change Password** is in every applicant's menu, to change it at any time. The session making the change stays signed in; every
  other session ends.
- A new password set by a link also clears a pending temporary password and unlocks the account.

## Underneath

| Piece | What it is |
|---|---|
| `admissions.applicant_account` | gains `must_change_password`, `temp_expires_at`, `password_reset_at` |
| `admissions.applicant_password_temporary(account, hash, reason, hours)` | the temporary password set (the hash made by the API) |
| `admissions.applicant_password_link(account, token_hash, reason, sent_to)` | the link recorded |
| `admissions.applicant_password_set(account, hash)` | the applicant's own password, the change cleared |
| `admissions.applicant_password_find(q, limit)` | the desk's finder |
| `ApplicantPasswordDeskController` | `GET /api/v1/applicant-passwords/search`, `GET /{account}`, `POST /{account}/reset`, `GET /history` |
| `ApplicantPasswordGate` | the forced change, on the server |
| `ApplicantController` | `GET` and `POST /api/v1/applicant/me/password` |

## Tests

- `check.sql` V687:
  - the Registry is refused, and so is a short reason;
  - the temporary password unlocks the account, ends its session, requires the change and is written down, and the record is kept;
  - links stop at three an hour;
  - the applicant's own password clears the change;
  - the finder works by JAMB number, application number, email, +234 phone and name.
- `ApplicantIT`:
  - the Registry is refused;
  - ICT Support's temporary password signs in, the portal is held until the change, the number is refused as the new password, the
    same session goes on after the change, and the new password signs in;
  - the Academic Office's link is sent to a masked address;
  - the history lists both resets.
- `lib/applicant-password.test.ts`.

# Back to the default number; postgraduate applicants too (V706, 30 October 2026)

The University's word: "Applicant password reset, should reset to default jamb no and not … also add password reset for pg school
too, it should be on pg dean dashboard and all it support staff, also ict director".

## Undergraduate applicants: the JAMB number

The desk no longer gives a random temporary password (`APW_METHOD` if one is asked for). Its two methods are now:

- **Back to the JAMB number.** The account goes back on its first password, as at the first sign-in (V178: it holds the sentinel
  `SET_ON_FIRST_LOGIN`). An applicant with no JAMB number (Preliminary Science, Preliminary Technology, the proficiency courses) goes
  back to the application number; one with neither is refused (`APW_NO_NUMBER`). The number works until the applicant chooses their
  own password, which they must do at the sign-in before anything else. The account is unlocked and its open sessions end. The reset is
  written down as `DEFAULT_NUMBER`, with no expiry. The applicant is told by email and SMS to sign in with the number.
- **Reset link**, as before.

The number is typed in capitals or small letters alike. Once the applicant has chosen a password, the number opens nothing
(`AUTH_FIRST_PASSWORD_RETIRED`). A password set through "Forgot password" also clears a pending reset.

## Postgraduate applicants: the application number

**Applicant Password Reset** (`/admissions/postgraduate/applicant-passwords`, route `t/pgapplicantpw`):

- The Dean of the School of Postgraduate Studies (`pgschool`) and its Secretary (`pgsecretary`), under Admissions, and an
  **Applicant passwords** panel on both their dashboards: a search box that opens the desk, and the latest resets.
- The Director of ICT (`ict`) and ICT Support (`ictagent`, `helpdeskhead`), as **PG Applicant Password Reset** beside the
  undergraduate desk.
- The Super Administrator.

Every other office is refused, by the API and by the database (`PGPW_OFFICE`): the Registry, the Academic Office and the Database
Operators among them.

1. **Find the applicant** by the application number, the old portal's number, the email, the phone (`0…` or `+234…`) or the name.
2. **Reset the password**, saying why in ten characters or more (`APW_REASON`). The password becomes the application number (hashed by
   the database, bcrypt cost 12). The account is unlocked and its sessions end. The applicant is told by email and SMS
   (`admissions.pg_tell_applicant`). An applicant with no application is refused (`PGPW_NO_APPLICATION`).
3. **The applicant** signs in with their email or application number, and the application number as the password. **Change
   password** (`/pg/portal/password`, also in their menu) opens first; the portal opens nothing else until they choose their own
   (`PASSWORD_CHANGE_REQUIRED`, the same gate). The new password is eight characters or more, not the application number (nor the old
   portal's) and not the one they have. The session making the change stays signed in; every other session ends.

Every reset is written once on `admissions.pg_applicant_password_reset`: the application number, the reason, whether the account was
locked, the sessions ended, the officer and the office.

## Underneath (V706)

| Piece | What it is |
|---|---|
| `admissions.applicant_password_default(account, reason)` | an undergraduate account back on its first password |
| `admissions.applicant_default_number(account)` | the JAMB number, or the application number where there is none |
| `admissions.applicant_password_find` | restated: `on_default`, `default_number` |
| `admissions.pg_applicant` | gains `must_change_password`, `password_reset_at` |
| `admissions.pg_applicant_password_default(applicant, reason)` | a postgraduate password reset to the application number |
| `admissions.pg_applicant_password_set(applicant, hash, keep)` | the applicant's own password, the change cleared |
| `admissions.pg_applicant_password_find(q, limit)` | the postgraduate desk's finder |
| `PgApplicantPasswordDeskController` | `GET /api/v1/pg/applicant-passwords/search`, `GET /{applicant}`, `POST /{applicant}/reset`, `GET /history` |
| `PgPortalController` | the sign-in says `mustChange`; `GET` and `POST /api/v1/pg/me/password` |
| `ApplicantPasswordGate` | holds a postgraduate applicant too |

## Tests (V706)

- `check.sql` V706, with made-up applicants:
  - undergraduate: the Registry and a short reason are refused; the reset puts the account back on the sentinel, requires the change,
    unlocks it, ends its session and is written down with no expiry; a preliminary applicant goes back to the application number, and
    one with neither number is refused; the finder says the account is on its number;
  - postgraduate: the Registry and the Database Operators are refused, and so is a short reason; the reset makes the password the
    application number, requires the change, unlocks the account, ends its session, is written down and kept, and the applicant is
    told; an applicant with no application is refused; the finder works by the application number, the old portal's, the email, the
    +234 phone and the name; the applicant's own password clears the change and ends every other session.
- `ApplicantIT`: a temporary password is refused; the reset goes back to the JAMB number and the applicant is told; the number, typed in
  small letters, signs in to a session held until the change; the number is refused as the new password; once a password is chosen
  the number opens nothing.
- `PgApplicantPasswordIT`: the Registry and the Database Operators are refused; ICT Support's reset ends the open session; the old
  password opens nothing, and the application number signs in to a session held until the change; the change refuses a wrong current
  password, the number and a short password; the same session goes on after it; the Secretary resets again; the history lists both.
- `lib/applicant-password.test.ts`.
