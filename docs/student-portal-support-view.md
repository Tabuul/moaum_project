# ICT Support opens the student's portal, read-only (V521)

## What it is

An ICT support agent can see a student's portal exactly as the student sees it, without the student's password, to find out
what the student is looking at. Examples: a registration page that shows no courses, a fee the student says is wrong, a message
on the examination card.

- **Who:** every ICT support agent in service. `VIEW_STUDENT_PORTAL` is in the support baseline (V453/V500). The Head of the
  ICT Support Desk, the Director of ICT, admin and super hold it too. An agent off the desk reaches nobody. Any other office
  is refused at the door.
- **Whom:** a student the agent reaches on the support desk, as for every support act. A merged record is not opened.
- **Where:** **Open student portal**
  - in **Support actions** on the support record (`/helpdesk/students/{id}`);
  - beside the student's status on the student record (`/students/{id}`), for the support offices.
- **For how long:** thirty minutes. The student's idle timeout applies too.

## Read-only, enforced on the server

Opening asks for a reason (ten characters or more) and keeps the ticket the agent came from.

`helpdesk.open_portal_view` makes a portal session of the student's own (`platform.session`, office `student`). It records
the opening in `helpdesk.portal_view`, and on the support ledger as `STUDENT_PORTAL_VIEWED` (module `AUTHENTICATION`), and on
the ticket's timeline when there is a ticket. The API then issues the session's token, naming the agent (claim
`support_view`). The token is issued and kept on the server, in an httpOnly cookie the browser's scripts cannot read.

With that token:
- every request that would change something (anything but a read) is refused before it reaches a service, with
  `SUPPORT_VIEW_READ_ONLY`;
- every read runs in a read-only database transaction. A screen that would record something for the student (for example
  counting an examination card issue) is refused the same way, so nothing the student could do is done by the agent;
- the student's own gates (the forced password change, the biodata gate) stand aside, since the agent changes neither;
- the student's own contact and privacy prompts are not shown;
- the token reaches only the student's portal. It carries the office `student` alone, so no office's screen opens with it.

The student's password is never read, shown or changed, and the student's own sessions are untouched.

## The agent's own session

While the view lasts, the agent's own token waits in an httpOnly cookie. Every screen carries a banner: **ICT SUPPORT —
STUDENT VIEW**, whose portal it is, that it is read-only, and the time left.

**LEAVE STUDENT VIEW** (or Sign out) ends the view on the API under the agent's own session (`helpdesk.end_portal_view`, so
the audit names the agent), ends the portal session with it, brings the agent's session back and returns to the record.
Another agent cannot end someone else's view; the Head of the Support Desk can.

## API

| Call | Who | What |
|---|---|---|
| `POST /api/v1/helpdesk/support/students/{id}/portal-view` `{reason, ticket}` | support agents (reach and capability checked) | opens the view; returns the token, the view's id and when it ends |
| `POST /api/v1/helpdesk/support/portal-views/{view}/end` | the agent who opened it, or the desk's head | ends the view and its portal session |
| `GET /api/v1/helpdesk/support/students/{id}/portal-views` | support agents | the views of a student's portal, newest first |

The frontend's `/api/auth/support-view` and `/api/auth/support-view/exit` routes do the cookie exchange.
