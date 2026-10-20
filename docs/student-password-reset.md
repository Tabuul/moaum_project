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
| Capability and scope | desk capability `RESET_PASSWORD`: since V500 in the baseline every ICT support agent in service holds across the University (`helpdesk.agent_baseline`), and still grantable on a posting within its faculty/department scope (`helpdesk.agent_capabilities_for`, `agent_may_see_student`); the Head, the Director of ICT, admin and super hold every desk capability | `RESET_STUDENT_PASSWORD` = `RESET_PASSWORD`; `VIEW_STUDENT_ACCOUNT_FOR_SUPPORT` = `VIEW_STUDENT`; `VIEW_PASSWORD_RESET_HISTORY` = `VIEW_RESET_HISTORY` (V500, baseline) or `VIEW_SUPPORT_AUDIT` |
| The support ledger | `helpdesk.support_action` via `helpdesk.record_support_action` (agent, office, IP, reason, ticket timeline), `ck_hd_sa_no_password` | the audit; action `PASSWORD_RESET` with method `DEFAULT_CREDENTIAL`, plus `ACCOUNT_UNLOCKED` |
| The desk's settings row | `helpdesk.setting`, edited at ICT Support Settings | the reset policy |

## The reset

`POST /api/v1/helpdesk/support/students/{id}/password` with `{ "method": "DEFAULT", "reason": "...", "ticket": "<id>|null", "unlock": true|false }`.

The server checks each of these in order:
1. The office is one of the desk's (`ictagent`, `helpdeskhead`, `ict`, `admin`, `super`); otherwise 403.
2. The student is within the agent's postings; otherwise 404. The desk never says whether such a student exists.
3. The agent holds `RESET_PASSWORD` for the student: every agent in service does (V500), and a posting covering the student may carry it; otherwise 422 `SUPPORT_CAPABILITY`. An agent taken off the desk (every posting ended) holds nothing.
4. The reason has 10 characters or more; otherwise 422 `SUPPORT_REASON_SHORT`.
5. The ticket is the student's own and within reach, and is required when the policy says so; otherwise `SUPPORT_TICKET_REQUIRED`.
6. The agent is under the policy's hourly limit for resets to the default credential, when one is stated (none by default since V526); otherwise `SUPPORT_RESET_RATE`.
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
  - V528: for the Head of the desk (and the Director of ICT, admin, super), **Resets by agent** above the list: each agent's resets today and in the last seven days (Lagos days), the daily average and the last one (`helpdesk.reset_counts`, `GET /api/v1/helpdesk/admin/password-resets/by-agent`), an agent at or past the alert figure marked.
- **ICT Support Settings → Student support password reset**:
  - can be changed: on or off, unlock by default, ticket optional or required, the hourly limit per agent (none by default, V526), the statuses reached, and (V528) the day's count of one agent's resets at which the Head is told — once an agent a day, by e-mail and on the portal (`SUPPORT_RESET_ALERT`; the Director of ICT where no Head is in office); empty tells no one, and nothing is refused;
  - fixed, not settings: the default password is the matriculation number, the change is always forced, and a reason is always required.

## Bulk password reset (V559)

Many students reset in one operation, by the same service as the single reset. There is no second reset system: each student is put on the first password by `StudentAuthService.resetToDefault`, the sign-in door accepts the matriculation number while `must_change` holds, and `PasswordChangeGate` forces the change.

- **Who.**
  - The capability is `BULK_RESET_PASSWORD`. A Head of the posting grants it like any other capability; it is not in the V500 baseline.
  - An agent reaches only the students their postings with that capability cover (`helpdesk.agent_scope_for(agent, 'BULK_RESET_PASSWORD')`). A CPO posted to one faculty therefore resets only that faculty's students.
  - The Head of the Support Desk, the Director of ICT, admin and super reach the University.
  - Scope is enforced on the server, and again in the database for each student as they are reset.
- **Screen.** ICT Support Desk → Bulk Password Reset (`/helpdesk/password-reset/bulk`, menu id `t/supportpwbulk`).
  - Counters: open Login Issues tickets, resets today, bulk operations, students reset and failed today.
  - Search by name, matriculation, JAMB or application number, phone, e-mail or ticket number. Filter by faculty, department, programme, level, student status and account state (no account, locked, must change, normal), or **Login issues only**: the students with an open Login Issues ticket, newest first, their ticket shown. Only a ticket the agent works (`helpdesk.can_view`: a queue they are posted to, within the posting's scope, or assigned to them) is offered, since the reset is filed on it; the counter counts the same students.
  - Selection: tick boxes, **Select all on this page**, **Select all N matching** (at most 1,000) and **Clear selection**. The choice is kept across pages, filters and a reload. Only the ids and tickets are kept, in the tab's session storage.
  - **Reset passwords (N)** opens the confirmation. The server lists who is eligible and who is not, with the reason. The reason is required (10 characters or more).
  - The work then runs on the server and the dialog shows real progress (processed / total, reset, failed) with **Cancel the rest**: the students not yet reached are recorded as CANCELLED, a student being reset at that moment finishes, and the operation stays CANCELLED with its counts. The result lists every student reset and every one not reset, with Excel.
  - The operation's record (`/bulk/{id}`) and **Bulk reset history** (`/bulk/history`, filterable by date, status, reference, officer or ticket number) are linked from the single reset and its history.
- **Each student, failing alone** (`BulkPasswordResets`, its own transaction a student):
  - the item is locked first, so a cancel that reached it leaves it alone;
  - checked again by `helpdesk.bulk_reset_check`: NOT_FOUND, OUT_OF_SCOPE ("ACCESS NOT AUTHORIZED"), RESET_DISABLED, RESET_MERGED_RECORD, RESET_NO_MATRIC ("MATRICULATION NUMBER NOT AVAILABLE") or RESET_STATUS ("STUDENT NOT ELIGIBLE");
  - the ticket rule of the policy applied;
  - reset, with its sessions ended;
  - recorded on the support ledger as a PASSWORD_RESET (method DEFAULT_CREDENTIAL) that names the BPR reference, plus the unlock where one was made;
  - told by the same no-password e-mail as the single reset.
  
  A student reset moments before by another agent reads **Already reset** and is not reset twice. A failed student never undoes the others. The operation ends COMPLETED, COMPLETED_WITH_EXCEPTIONS, FAILED or CANCELLED.
- **Never twice.**
  - The confirmation sends a key. The same key from the same agent returns the same operation (`UNIQUE (initiated_by, idempotency_key)`).
  - A student chosen twice is one item.
  - The hourly limit of the policy, when the Director sets one, counts the operation's students.
- **Work and records.**
  - One bcrypt hash of a random secret is made for the whole operation (as V294 seals an upload), so a thousand students do not cost a thousand hashings.
  - The request starts the worker once its transaction commits. A timer every 20 s takes up an operation an API restart left open. `JobLock` keeps it to one instance.
  - `helpdesk.bulk_reset` (reference `BPR/YYYY/NNNNNN` by `platform.next_number`, initiator, office, reason, counts, status, times) and `helpdesk.bulk_reset_item` (each student's result, failure code and words, ticket, ledger act) are on the audit spine. Each student's writes carry the operation's id as the correlation.
  - No password or hash is in any of them, in a log or on the screen.
- **Tests.**
  - `BulkPasswordResetIT`: scope, capability, preview, the run, the codes, the idempotent repeat, the forced change at sign-in, the ledger, the history.
  - check.sql's V559 block: codes and scope, one item a student, key, reference, counts, a cancelled operation's state and counts.

## Bulk password reset, finished at the desk (V563)

- **Login tickets resolved with the reset.**
  - When any chosen student has an open Login Issues ticket, the confirmation offers **Resolve each student's login ticket once the student is reset**. It shows the words the students will read (20 characters or more), which the agent can edit.
  - For each student who is reset (or was reset moments before), `helpdesk.resolve_for_reset` takes the ticket through the desk's own steps: submitted → opened → in progress → resolved. Each step goes on the timeline in the agent's name. The requester receives the usual resolution e-mail, so the separate "password was reset" e-mail is not sent to that student.
  - A ticket already resolved or closed is left alone. A student who is not reset keeps the ticket open.
- **Reset links for students without a matriculation number.**
  - These students sign in with their admission or JAMB number. On the result and on the operation's record, **Send reset links (N)** sends each of them the single reset's one-hour link (V485's LINK method) to the e-mail and phone on their record, or to the login ticket's e-mail where the record has none.
  - Each student is checked again first: still within scope and still without a number. One who has since been given a number is told to retry instead.
  - The result is kept on the item: where the link went (masked), or why it was not sent, for example "NO E-MAIL OR PHONE ON RECORD". Each link goes on the support ledger and the ticket, and is never sent twice.
- **Bulk resets apart in the Head's oversight.**
  - Every support act made inside a bulk reset names it (`helpdesk.support_action.bulk_id`). The API sets this from the transaction's `moaum.bulk_reset` for each student, and the `trg_support_action_bulk` trigger records it.
  - The V528 daily alert to the Head counts single resets only: a bulk reset is one reasoned operation under its reference, not an agent resetting student after student.
  - `helpdesk.reset_counts()` and the Resets by agent panel show each agent's students reset in bulk today and over 7 days, and the number of bulk operations today, separately.
- **Retry.**
  - **Retry the students not reset (N)** on the record opens the same confirmation for the students who failed, excluding those who have been sent a link.
  - It creates a new operation (`retry_of`), which only the person who made the original or a Head may start. The original lists its retries.
- **Approval of a large bulk reset.**
  - In ICT Support Settings, the Director of ICT sets the number of students above which a bulk reset waits (`helpdesk.setting.bulk_reset_approval_over`). The default is 200; leaving it empty means never.
  - Above that number, the confirmation says the reset will wait, and the operation opens as AWAITING_APPROVAL. The Head of the Support Desk is told (BULK_RESET_APPROVAL), or the Director of ICT where no Head is in office.
  - A Head other than the person who asked approves it, after which it runs at once with every student checked again, or declines it with a reason (REJECTED: no student is reset, and every item is FAILED with the reason). The person who asked is told (BULK_RESET_DECIDED) and can withdraw the operation until it is decided.
  - The rules are enforced in `helpdesk.decide_bulk_reset`: BULK_APPROVAL_HEAD, BULK_APPROVAL_OWN, BULK_APPROVAL_DECIDED, and SUPPORT_REASON_SHORT for a decline. The desk's counters show the operations awaiting approval.
- **Tests.**
  - `BulkPasswordResetIT.ticketsResolvedLinksSentRetriedAndALargeOneApproved` covers this end to end.
  - check.sql's V563 block covers the approval rules and notices, the ticket's steps, the bulk tag with the alert and counts, retries and the resolution words.
  - `lib/bulk-reset.test.ts` covers which students get a link, which are retried, and the result words.

## Requests in parts, the policy kept, the history by kind (V565)

- **More than 1,000 students in one request.**
  - One request now takes up to 10,000 students: **Select all N matching** goes to 10,000, and so do the preview and the start.
  - `helpdesk.start_bulk_reset` opens consecutive parts of 1,000 in the order chosen (`bulk_reset.series_id`, `part`, `parts`), each with its own BPR reference. They run one after another, since the worker takes the oldest first.
  - The same key returns the first part.
  - The approval figure (now up to 10,000) is read against the whole request. Every part waits, is counted once at the desk and is told to the Head once. A decision on any part decides them all, and cancelling or withdrawing stops every part not yet ended.
  - The dialog reads progress and the result across the parts and lists them with their records. Each record names its part ("Part 2 of 3"), with links to the others. Bulk reset history shows the part.
- **The policy keeps what a save does not name.**
  - `PUT /admin/settings/password-reset` now changes only the settings the request names. A form opened before a setting existed, or a script that knows only some settings, no longer clears the others.
  - A figure sent as empty (null) is cleared, which means "none" for the hourly limit, the alert and the approval figure.
  - Out-of-range figures are refused by name: `HELPDESK_RESET_HOURLY`, `HELPDESK_RESET_ALERT`, `HELPDESK_BULK_APPROVAL`.
- **Password Reset History by kind.**
  - Filter: every reset, single resets, resets in bulk resets, or reset links. API: `GET /support/actions?module=AUTHENTICATION&kind=SINGLE|BULK|LINK`.
  - New column: the bulk reset each act was made in, linked to its record. It is also in the Excel and the PDF.
- **Tests.**
  - `SupportReachIT` covers the policy kept and cleared, single and bulk resets read apart, and a request of 1,500 in two parts.
  - check.sql's V565 block covers parts, waiting, approval and decline as a whole, the 10,000 limit and the figure.

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

## Uploaded contacts and reset links (V575)

A contact a department uploaded is held unconfirmed until the student confirms it with a code, or the desk confirms it with them
(docs/cpo-student-support.md §18). Until then:

- the forgotten-password door sends it no link;
- the desk's reset link, a bulk reset's included, is refused with `AUTH_CONTACT_UNCONFIRMED`.

Notices still reach it.
