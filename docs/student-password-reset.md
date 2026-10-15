# Student password reset at the ICT Support Desk (V485)

ICT Support resets a student's portal password at the desk without e-mail. The default student credential is the
**matriculation number**: it is the username, and until the student chooses a password it is also the password. The change
is forced at the next sign-in, and the server enforces it.

## What was already there, and what was reused

| Piece | Where | Reused as |
|---|---|---|
| One student account | `iam.student_account` (one row a student, `student_id` unique) | the account reset; no second account, no second user |
| The sign-in on the matriculation number | `StudentAuthService.signIn`, `StudentPortalRepository.byMatric` (V267: once a matriculation number is issued it is the sign-in) | the username rule |
| The "first password" state | an account with `must_change` on and no temporary password: the door accepts the number the student signs in with, and nothing else (V178, V122, restored 13 Oct 2026); once a password is chosen the number opens nothing (V428) | the default credential |
| bcrypt, cost 12 | `BCryptPasswordEncoder(12)` in `StudentAuthService`; `ck_student_hash` on the table | the hash written at the reset |
| The desk's reset | `POST /api/v1/helpdesk/support/students/{id}/password`: `LINK` (one-hour link) and `TEMPORARY` (random, one sign-in, on a ticket) (V346) | a third method, `DEFAULT` |
| Capability and scope | desk capability `RESET_PASSWORD` on a posting; the posting's faculty/department scope (`helpdesk.agent_capabilities_for`, `agent_may_see_student`); the Head, the Director of ICT, admin and super hold every desk capability | `RESET_STUDENT_PASSWORD` = `RESET_PASSWORD`; `VIEW_STUDENT_ACCOUNT_FOR_SUPPORT` = `VIEW_STUDENT`; `VIEW_PASSWORD_RESET_HISTORY` = `VIEW_SUPPORT_AUDIT` |
| The support ledger | `helpdesk.support_action` via `helpdesk.record_support_action` (agent, office, IP, reason, ticket timeline), `ck_hd_sa_no_password` | the audit; action `PASSWORD_RESET` with method `DEFAULT_CREDENTIAL`, plus `ACCOUNT_UNLOCKED` |
| The desk's settings row | `helpdesk.setting`, edited at ICT Support Settings | the reset policy |

## The reset

`POST /api/v1/helpdesk/support/students/{id}/password` with `{ "method": "DEFAULT", "reason": "...", "ticket": "<id>|null", "unlock": true|false }`.

The server checks each of these in order:
1. The office is one of the desk's (`ictagent`, `helpdeskhead`, `ict`, `admin`, `super`); otherwise 403.
2. The student is within the agent's postings; otherwise 404. The desk never says whether such a student exists.
3. A posting covering the student carries `RESET_PASSWORD`; otherwise 422 `SUPPORT_CAPABILITY`.
4. The reason has 10 characters or more; otherwise 422 `SUPPORT_REASON_SHORT`.
5. The ticket is the student's own and within reach, and is required when the policy says so; otherwise `SUPPORT_TICKET_REQUIRED`.
6. The agent is under the policy's hourly limit for resets to the default credential; otherwise `SUPPORT_RESET_RATE`.
7. `iam.student_reset_check(student)` allows the reset:
   - `RESET_DISABLED`: the policy is switched off.
   - `RESET_MERGED_RECORD`: the record was merged into another (V431).
   - `RESET_NO_MATRIC`: the record has no matriculation number. The answer reads "THIS STUDENT DOES NOT HAVE A VALID MATRICULATION NUMBER. PASSWORD RESET USING THE DEFAULT STUDENT CREDENTIAL POLICY IS NOT AVAILABLE." No number is ever invented.
   - `RESET_STATUS`: the student's status is not one the policy allows. Withdrawn, expelled, transferred-out, deceased and rusticated students, and students not yet matriculated, are never reached.

When all of these pass, the server:
- Holds the student row, so a second click within a minute is the same reset (`alreadyDone`, nothing written twice).
- Writes a bcrypt hash of a 32-byte random secret that nobody holds, so the old password stops working. It sets `must_change` on, withdraws any temporary password and sets `support_reset_at`. The account is opened in this state if it never was. The lockout is cleared only when `unlock` is ticked (the policy sets the default).
- Ends every session the student holds (`ended_reason` 'password reset by ICT Support'). The temporary-password reset now does the same. Payments are untouched: Interswitch and the gateways notify the server directly, so only the student's own screen needs a fresh sign-in.
- Writes `PASSWORD_RESET_BY_SUPPORT` (and `UNLOCKED_BY_SUPPORT`) on the sign-in log `iam.student_event`.
- Writes the ledger row (`PASSWORD_RESET` / `DEFAULT_CREDENTIAL`) and, when the account was unlocked, `ACCOUNT_UNLOCKED`. When a ticket is named, the ledger row also goes on the ticket's timeline.
- E-mails the student, if an address is on record, that ICT Support reset the password. The e-mail never says what the password is.
- Answers with the outcome only. No password, hash or number is ever in the answer.

**The matriculation number is never written anywhere, not even as a hash.** The sign-in door grants it while the account is in
the first-password state, exactly as it already did for a first sign-in. This meets the requirement that no plaintext be
stored, and it is stronger than storing a hash of a guessable number.

## The forced change

`PasswordChangeGate` is a server interceptor that runs before the biodata gate. A student whose account has `must_change` on can reach only:
- `/api/v1/student-auth/**`: the change, the account's state (`GET /password-status`) and sign-out;
- `/api/v1/iam/session`;
- `/api/v1/iam/me`.

Everything else is refused with 403 `PASSWORD_CHANGE_REQUIRED`, whatever the address, tab, refresh, back button or direct call.
Every student response carries `X-Password-Change`, and the portal's proxy sends any page to `/student/password`. That page reads
"PASSWORD RESET REQUIRED: Your portal password has been reset by ICT Support…" when the desk reset it, then asks for the current
password, the new password and a confirmation. The student's existing rule applies: eight characters or more, never the student's
own matriculation, admission or JAMB number, and now never containing one either (the staff rule against a password holding the
username, applied to students). Once the password is changed the gate opens, and from then on the number opens nothing.

The public sign-in page no longer says that the number is the first password (`AUTH_FIRST_PASSWORD_RETIRED`'s remedy).

## Screens

- **ICT Support Desk → Student Password Reset** (`/helpdesk/password-reset`, menus of `ictagent`, `helpdeskhead`, `ict`, `admin`, `super`):
  - server search by matriculation, JAMB or application number, name or phone, within the agent's reach;
  - the student's details and account state;
  - method, reason, ticket and unlock;
  - RESET STUDENT PASSWORD, a confirmation, RESETTING PASSWORD… while the server works, then PASSWORD RESET SUCCESSFUL or PASSWORD RESET FAILED with the reason.
  
  The same component (`components/support/PasswordReset.tsx`) replaces the old reset dialog on the student's support record, so the desk has one reset screen.
- **Password Reset History** (`/helpdesk/password-reset/history`): the ledger's Authentication acts, showing S/N, student, matriculation number, who reset it, role, method, reason, ticket, date and result. No password, hash or download is offered.
- **ICT Support Settings → Student support password reset**:
  - can be changed: on or off, unlock by default, ticket optional or required, the hourly limit per agent, and the statuses reached;
  - fixed, not settings: the default password is the matriculation number, the change is always forced, and a reason is always required.

## Other reset paths found in the codebase

| Path | What it is | Kept because |
|---|---|---|
| `POST /api/v1/auth/reset`, `/applicant/reset`, `/jupeb/reset` | the e-mailed link for staff, applicants and JUPEB | it is the self-service path for those who have an address |
| `POST /api/v1/helpdesk/tickets/{id}/password-reset` | the link sent from a ticket | it checks the same capability on the student and writes the same ledger row |
| `PUT /api/v1/student-auth/accounts/{id}` | the Registry opens a student account with a first password it types, which must change at sign-in | it is the Registry's act, refuses the student's own number, and the change is now enforced by the gate |
| `PUT /api/v1/iam/persons/{id}/credential` | the Registry sets a staff member's first password | staff, not students |
| JUPEB desk and old-portal import | JUPEB's own temporary passwords, shown once | JUPEB's separate portal |

No password was found in logs, browser storage or analytics, and no hard-coded default password exists. The only answers that
carry a password are the temporary-password reset (V346) and JUPEB's old-portal import, which hands out one-time passwords
once, by design.
