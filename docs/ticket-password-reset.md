# Password resets from support tickets

*Oct 2026 (V582).* Most tickets at the ICT Support Desk come from students who cannot sign in. This feature resets their
passwords together, from the tickets themselves, on the desk's queue.

**The ticket is the reason, and the only way in.** The API takes ticket ids, never a student id, a username or a number. From
each ticket the server works out the student and whether the student may be reset. A student without an open login or
password ticket can never be reached this way.

## On the desk

1. On the ICT support desk (`/helpdesk`), choose **Issue type → Login and password issues**. The **Login issues** row of
   counts does the same in one click. Each row then shows where its ticket stands for a reset:

   | Shown | Meaning | Can be ticked |
   |---|---|---|
   | Eligible for password reset | the ticket is open, and it is a student's | yes |
   | Eligible — an earlier reset failed | an earlier reset of this ticket's student failed | yes |
   | In a password reset | the ticket is in a reset that has not finished | no |
   | Password reset completed | the ticket's reset is done | no |
   | Not eligible | resolved or closed, or not a student's ticket | no |

2. Tick tickets one by one, with **Select all eligible on this page**, or with **Select all filtered eligible tickets**. The
   last one asks the server for every eligible ticket the filters find, up to 10,000. **Reset selected passwords** stays
   disabled until something is ticked.
3. The server checks every ticket (`helpdesk.ticket_reset_check`). The dialog then shows:
   - how many tickets were selected and how many are eligible;
   - the students to reset, with the duplicate tickets consolidated: a student with several tickets is reset once;
   - which tickets are already reset or in a reset, and which are not eligible, each with its reason.
4. Give the reason and the words the students read on their resolved tickets. A default is filled in, and no password ever
   appears in either. Confirm, and the operation runs (`PWR-TKT/YYYY/NNNNNN`), with its real progress shown.
5. The result lists every ticket with what became of it. A ticket whose student could not be reset stays open on the desk,
   with the reason.

## What a ticket must be

`helpdesk.ticket_reset_check(agent, head, tickets)` refuses a ticket, in this order, when it is:

| Code | When |
|---|---|
| `TICKET_NOT_FOUND` | the agent cannot see the ticket (nothing of it is said) |
| `TICKET_NOT_LOGIN` | its category is not a login and password issue (course registration, fees, GST, hostel, results, admission, payment …) |
| `TICKET_NO_STUDENT` | asked from the sign-in page, and no student (or more than one) holds the number given, or the request is about another portal (V594) |
| `TICKET_NOT_STUDENT` | the ticket was not raised by a student (staff, a JUPEB candidate) |
| `TICKET_SETTLED` | the ticket is resolved or closed |
| `TICKET_IN_OPERATION` | the ticket is in another reset that has not finished |
| `TICKET_RESET_DONE` | the ticket's reset is done already (a reopened ticket may be reset again) |
| `OUT_OF_SCOPE` | the student is outside the agent's `BULK_RESET_FROM_TICKETS` scope |
| `NOT_FOUND`, `RESET_NO_MATRIC`, `RESET_STATUS`, `RESET_MERGED_RECORD`, `RESET_DISABLED` | the student's own checks, as for every reset (V559) |

The ticket is checked when it is ticked, again under lock when the reset starts, and again by the worker just before its
student is reset. Two agents ticking the same ticket reset its student once: a ticket can be in only one unfinished operation
(`helpdesk.bulk_reset_ticket`, unique while it waits).

**Which categories count** is configured under ICT Support Settings → Categories → *Password reset from tickets*
(`helpdesk.category.password_reset_eligible`). Login Issues is on. The Director of ICT can switch on another category, an
account-locked category for example, without a change of code.

## Requests from the sign-in page (V594)

A person who cannot sign in asks from the sign-in page (V363). Such a request names no account (`requester_kind` PUBLIC), and until
V594 the reset from tickets refused every one as *not a student's*: 611 open Login Issues tickets on 20 October 2026, nearly all
of them asked from the sign-in page.

- **The student is found by the number given.** `helpdesk.ticket_student` matches a request about the student portal to the one
  student whose matriculation number, admission number or former matriculation number (V579) is the number given. The number is
  read as the sign-in help reads it: upper case, no spaces. When no student holds the number, or more than one does, there is no
  match (`TICKET_NO_STUDENT`). A request about the applicant portal or a staff account is never matched.
- **It is reset like a student's own ticket.** It goes through the same checks and is reset to the matriculation number, which
  the student changes at the next sign-in. The ticket is resolved, and its requester is e-mailed at the address given.
- **The Head of the ICT Support Desk chose this on 20 October 2026.** What the person typed is not proven. Someone who typed another
  student's number could sign in as that student before the student does. Each reset stays on the ticket it was made from, which
  keeps the name, number, e-mail and phone given.
- **On the desk.** The queue shows the student under such a request ("Student: …"). The ticket page names the student and opens
  them in Support Mode. The queue's *Password reset* column reads *Not eligible — no student holds the number given* when there is
  no match.

## The sign-in help form (V596)

The form at `/login/help` asks less and says whose a number is. These were the Head of the ICT Support Desk's choices of 20 October
2026.

- **Asked.** The form asks only the account type, the number, the name, the e-mail and the phone. It no longer asks what the portal
  says, when the problem started or what happened. `helpdesk.submit_public`, restated from V363's text, requires only the account
  type and the number of the Login Issues fields. A request without a description says what it is about, for example "Cannot sign
  in to the student portal with MOAU/SC/CSC/26/10001." The in-portal ticket form keeps the category's fields as they are.
- **Whose number it is.** As a student-portal number is typed, the form names the student and shows the e-mail and phone on the
  record masked (`a•••••e@gmail.com`, `0803•••4567`), never in full. A person stepping through numbers therefore collects no one's
  contacts. The answer comes from `helpdesk.sign_in_help_student` (`POST /api/v1/helpdesk/sign-in-help/check`), with the same
  throttle as before. The name fills *Your name* when that is still empty.
- **A missing contact saved.** When the record holds no e-mail, or no phone, the one given on the request is saved to it
  (`people.contact_from_sign_in`; a phone given as +234 is kept as 0 and ten digits). It is held unconfirmed as an uploaded contact
  is (V575): a password-reset link goes there only after the student confirms it with a code at sign-in, or the desk confirms it
  with them; since V599 no notice goes there either until then (below). A contact the record already holds is never replaced. The answer to the request says what was
  saved (`saved`: EMAIL, PHONE), and the form tells the student.

## Sign-in help contacts and number checks (V599)

Anyone can type any student's number on the sign-in help form, so a contact it saves must not become the address the University
writes to until someone who knows the student says it is theirs.

- **Held from notices.** The contact is marked as the sign-in help's, with the request that saved it
  (`people.student_contact.email_from_sign_in` / `phone_from_sign_in`, `email_sign_in_ticket` / `phone_sign_in_ticket`).
  `people.student_reach`, the one address every notice reads, leaves it out while it is unconfirmed and falls back to the
  applicant account's, as before. Once the student confirms it with a code at sign-in, or the desk confirms it, notices reach it
  like any other. Anyone writing another value (the student's own save, the desk's edit, an upload) clears the mark with it.
- **The desk.** *ICT Support → Sign-In Help Contacts* (`/helpdesk/sign-in-contacts`) lists the unconfirmed ones within the agent's
  contact-editing scope (`helpdesk.sign_in_contacts`): the student, the contact, the request and who asked. The student's support
  profile marks the contact *From the sign-in page — not confirmed* with the request's number. With `EDIT_CONTACT` the agent
  either:
  - confirms it after checking it with the student (`POST /api/v1/helpdesk/support/students/{id}/contact/confirm`); or
  - removes it as not the student's (`POST …/contact/refuse`, `people.contact_refuse_desk`): the field is emptied and the outcome
    kept as `DESK_REFUSED` with the request (`people.contact_confirmation.sign_in_ticket`). The same refusal serves a contact a
    department uploaded, whose uploader is told as a student's own refusal tells them (V580).
- **Number checks watched.** Each student number checked on the form from a connection on a network is logged
  (`helpdesk.sign_in_lookup`: the address, the number, whether a student holds it; kept 180 days). A check from the machine itself
  (development, the test suite) is neither logged nor capped.
  - Past the day's figure (`helpdesk.setting.sign_in_lookups_daily`, 200 by default) the connection is refused until the next
    Lagos day: 429, `HELPDESK_CHECK_DAY_LIMIT`. The fifteen-minute limit of 30 checks (V359's throttle) stands beside it.
  - When one connection has checked the alert figure of different numbers in a day (`sign_in_lookups_alert`, 50 by default), the
    Head of the ICT Support Desk is told once that day (the Director of ICT where no Head is in office): notice
    `SIGN_IN_LOOKUP_ALERT`, with the address, the numbers, how many were students' and when it began.
  - A University network shares one address among many students, so the Head and the Director see the day's checks by
    connection on the same page (`GET /api/v1/helpdesk/support/sign-in-contacts/lookups?day=`) and set both figures there
    (`PUT …/lookups/figures {daily, alert}`; empty is none).

## Bulk Password Reset lists the tickets (V594)

*ICT Support → Bulk Password Reset* lists only the open Login Issues tickets within your reach, the oldest first. Each shows:

- the requester, as raised;
- the student: their own record, or the one holding the number given;
- where the ticket stands for a reset.

To reset them:

- **Select all eligible tickets** selects every eligible ticket of the search, across pages. The server sends the ticket ids, and
  the reset checks each again.
- **Clear selection** empties it.
- **Reset and resolve** opens the check and the reset described below. Each student is reset once and every one of their tickets
  is resolved.

The figures at the top give the open tickets and how many were asked from the sign-in page. They also give how many have a
student found, how many have none for the number, and those in a reset now, failed before, or reset today.

The earlier student finder (V559: choose students by search or filter, without a ticket) is a link away, under *Students without a
ticket* (`/helpdesk/password-reset/bulk/students`).

## What the reset does

The reset is the same one the single reset and the student bulk reset make (V485, V559). The same worker runs each student in
a transaction of its own:

- The student's account is put on its first password. The student signs in with the matriculation number as both username
  and temporary password, and must choose a new password at once.
- The matriculation number is never hashed or stored, open sessions end, and the account is unlocked when asked.
- One support act (`PASSWORD_RESET`, method `DEFAULT_CREDENTIAL`) is filed on the newest of the student's tickets and names
  the operation. The audit trail carries the operation as its correlation.
- Every ticket of the student in the operation is resolved through the desk's own steps (`helpdesk.resolve_for_reset`:
  opened, in progress, resolved), and each requester is told. A ticket settled in the meantime is left as it is.
- A student not reset leaves every one of their tickets `FAILED`, with the reason, and open on the desk.

An operation of more students than ICT Support Settings allow waits for a Head's approval, as a student bulk reset does. The
existing **Bulk Password Reset** screens approve, decline and cancel both kinds.

## History and reports

- **On the ticket:** a *Password reset history* panel (`GET …/tickets/password-reset/history/{ticket}`). For every reset from
  the queue, in a student bulk reset, or a single reset on the ticket, it shows when, who, the batch, the result and whether
  the change is forced. It never shows a password.
- **Password resets from tickets** (`/helpdesk/password-reset/tickets`, menu *Ticket Password Resets*): the operations, the
  latest first. Each opens to its tickets, and the failed ones link back to the desk. Two Excel reports, for a period:
  - the Login issue report: every login or password ticket, with its reset status, date and agent;
  - the Password reset operations report: every ticket of every operation, with its result.

## Who

| | Uses it |
|---|---|
| `BULK_RESET_FROM_TICKETS`, granted on a posting (Agents, Queues and Routing) | within the posting's scope; not in the baseline |
| Head of the Support Desk, Director of ICT, administrators | the University |
| `BULK_RESET_PASSWORD` (the student bulk reset) | does not give this capability; the two workflows stay apart |

## API

`/api/v1/helpdesk/tickets/password-reset` (`TicketPasswordResetController`):

| Call | Purpose |
|---|---|
| `GET /summary` | the login figures, and whether the reader may reset from tickets |
| `POST /validate {ticketIds}` | check the tickets |
| `POST /execute {ticketIds, reason, resolution, unlock, key}` | start the reset |
| `GET /operations` and `GET /operations/{id}` | the operations, and one with its tickets |
| `GET /history/{ticket}` | a ticket's reset history |
| `GET /reports/login-issues`, `GET /reports/operations` | the two reports |
| `PUT /categories/{id} {eligible}` | switch a category on or off |

The desk's queue (`GET /api/v1/helpdesk/tickets`) takes `issue=login|other` and returns each row's `reset_state`. With
`eligibleIds=true` it returns the ids of every eligible ticket its filters find. A response never carries a password.
