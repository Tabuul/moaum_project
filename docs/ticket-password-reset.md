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
| `TICKET_NOT_STUDENT` | the ticket was not raised by a student |
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
