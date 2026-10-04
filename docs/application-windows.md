# Application Registration Control (V312)

Whether a new **Post UTME registration** (`/apply`) or a new **postgraduate application** (`/pg/apply`)
may be started is a rule the Director of ICT sets, and the backend enforces. Nothing on a page decides it:
the login page hides the button, the apply page shows the Director's closure message, the University's
website reads the same state, and the API and the database refuse a new application while the window is
closed, whatever a page shows.

## What the Director does

Portal Management → **Application Registration Control** (`/ict/applications`), office `ict` only.

For each of the two windows, per session:

| Act | Effect |
|---|---|
| Close now | Closed from this moment, with a reason on the record |
| Open now / Reopen now | Open from this moment, with no closing date unless one is given |
| Schedule | Opens and closes by the dates given, on the server's clock (Africa/Lagos) |
| Extend / Shorten | Moves the closing later / earlier; the dates before stay in the history |
| Edit window | Changes either date |
| Save message | The plain-text message the public reads while the window is closed, scheduled or expired |

Both windows are **open by default** until the Director first acts on them for a session, so what runs today
keeps running. Both run over the whole admission exercise of a session: no semester, no late period.

**Closing stops new applications only.** An applicant who registered before the closing signs in, pays,
uploads, submits and reads their status as before. Nothing is deleted, cancelled or reversed. Admission
status checking keeps its own window.

## Where it is enforced

1. `POST /api/v1/applicant/register` and `POST /api/v1/pg/apply` refuse with problem code
   `APPLICATION_CLOSED` (HTTP 422) whose `detail` is the Director's closure message.
2. A `BEFORE INSERT` trigger on `admissions.applicant_account` and `admissions.pg_application` refuses the
   row when the writer is the applicant (audit office `applicant`) and the window is not open. An office
   importing or correcting records is not an applicant registering and is not held.

The state is computed from the server's clock by `policy.window_state(type, session, NULL)`; the two types
are `POST_UTME_REGISTRATION` and `POSTGRADUATE_APPLICATION`. The Post-UTME session is the current academic
session (or the one asked for on `/apply?session=`); the postgraduate session is the School's current session
(`admissions.pg_current_session()`).

## For the University's website

```
GET https://<portal-api>/api/v1/public/application-windows
```

No sign-in, cross-origin allowed, cached for one minute, nothing personal:

```json
{
  "postUtme": {
    "type": "POST_UTME_REGISTRATION", "label": "Post-UTME registration", "session": "2026/2027",
    "status": "CLOSED", "open": false, "opensAt": null, "closesAt": "2026-09-30T22:59:00Z",
    "message": "POST-UTME REGISTRATION IS CURRENTLY CLOSED\n\nThank you for your interest ...",
    "applicationPath": "/apply", "applicationUrl": "https://<portal>/apply"
  },
  "postgraduate": { "type": "POSTGRADUATE_APPLICATION", "label": "Postgraduate application", "status": "OPEN", "open": true, "message": null, "applicationUrl": "https://<portal>/pg/apply", ... },
  "now": "2026-10-04T09:00:00Z"
}
```

`status` is `OPEN`, `CLOSED`, `SCHEDULED` or `EXPIRED`. Show the button and link to `applicationUrl` when
`open` is true; show `message` (plain text, blank lines are paragraphs) when it is not. `?session=2027/2028`
asks about another session's Post-UTME window.

## Where it is recorded

Every act is a row in `policy.portal_window_event` (what it was, what it became, who, when, why), shown in the
history on the screen and on the Payment & Registration Windows screen beside the other windows. The closure
message lives in `policy.portal_window_message`, audited like every table.

## Tests

`ApplicationWindowsIT` (closed → refused at the API and in the database; reopened → taken; scheduled → not
open; the public endpoint follows; the message is plain text; only the Director acts) and one property in
`db/check.sql`.
