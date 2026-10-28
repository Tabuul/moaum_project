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
