# Notifications: the central engine (V425)

Every module of the portal reaches a person through one outbox: `platform.notice`, queued by `platform.queue_notice`, sent by
the API's dispatcher over the mail account (Mail server screen) or the SMS account (SMS gateway screen) ICT configured, or an
HTTP relay. Fifty database functions and a handful of API classes already queue through it (admission decisions, payments,
results, clearance, hostel, JUPEB, the daily reminders). V425 adds the engine around that one outbox and changes no module's
business rule.

## What the engine adds

| Piece | Where | What it does |
|---|---|---|
| Templates | `platform.notice_template` | The words of every message, keyed by event (`WINDOW_OPENED`, `BIODATA_REMINDER`, `PORTAL_MIGRATION`, `ANNOUNCEMENT` …): an e-mail subject and text, an SMS text, a portal title and text, `[TOKENS]`, a priority, whether the message is mandatory. A key with a suffix (`WINDOW_CLOSED:SCHOOL_FEES_PAYMENT`) overrides the base key for that window type; `CCE_` and `PG_` prefixes fall back to the University's variant. Edited on **Notification templates** (ICT, administrators; the Registry reads). |
| Rendering | `platform.render(key, variant, channel, vars)` | `[TOKEN]` becomes the value given; a token nobody supplied becomes nothing, never stays in the text. `UNIVERSITY_NAME`, `UNIVERSITY_SHORT`, `PORTAL_URL` and `DATE` are always available. |
| One person | `platform.tell_student(student, key, variant, vars, event_key)`, `platform.tell_person(person, …)`, `platform.notify(…)` | The template rendered from the record (name, numbers, programme, department, faculty, level, session) plus the sender's values, queued on every channel the template has for which the person has an address. |
| The portal channel | `platform.notice.channel = 'PORTAL'`, `platform.notice_read` | Delivered on the dashboard the moment it is queued (state SENT); read marks kept apart from the audited row; the bell on the sidebar (`waiting["s/notifications"]`, `waiting["r/notices"]`) counts the unread. |
| One message per event | `platform.notice.event_key`, `ux_notice_event` | The same event never reaches the same person twice on a channel, however often it is raised (a retry, a restart, a second click). |
| Addresses checked | `platform.email_valid`, `platform.phone_valid` | An e-mail that is not one, or a phone that is not a Nigerian number (0 + ten digits, or 234 + ten digits), is recorded FAILED with `INVALID_EMAIL` / `INVALID_PHONE` and never tried; "put the failed back in the queue" leaves those alone. A missing address queues nothing, as before. |
| Big sends as jobs | `platform.notice_job`, `platform.run_notice_job(limit)` | A send too big for one request is a job the scheduler drains every half-minute in batches (`platform.notice_setting.job_batch`, 2,000 by default), the cursor kept so a restart resumes rather than repeats. The portal window messages (open, close, extend, reopen) go this way, through the templates, to the same students as before: the route's students (CCE_, PG_, else every other), in the session. |
| Priority | `platform.notice.priority` | CRITICAL and HIGH leave the outbox first. The dispatcher sends 200 a batch (`moaum.notices.batch`) every half-minute (`moaum.notices.every-ms`). |

## The biodata status

V423 holds the one calculation of what a student still owes (`people.biodata_completion`) and the ICT Director's gate. V425
reads it into a status every screen can show:

| Status | When |
|---|---|
| `INCOMPLETE` | A required item is missing. |
| `OUTDATED` | The review period (`people.biodata_setting.review_days`, blank = never) has passed since the last biodata write or confirmation. |
| `REVIEW_REQUIRED` | The record came over from the old portal (a matriculation number the portal never issued) and the student has neither written to it nor confirmed it since. |
| `UP_TO_DATE` | Otherwise. |

`people.biodata_status(student)` / `people.biodata_statuses(students[])` / `people.biodata_status_counts()`; the student confirms
with `people.confirm_biodata` (`POST /api/v1/me/biodata/confirm`, refused with `BIODATA_INCOMPLETE` while an item is missing).
The dashboard shows a small card only when the status needs the student (update, or review and confirm).

The weekly reminder (`people.remind_biodata`, V423 restated) runs while the gate is ON **or** the reminder switch is
(`people.biodata_setting.remind_enabled`, on the templates screen), to every student whose status is not `UP_TO_DATE`,
through the `BIODATA_REMINDER` template, at most once in seven days, and stops on its own once the record is up to date.
Monday 09:00 (`moaum.biodata.remind-cron`), or "Run the biodata reminder now" on the templates screen.

## Staff contact

A staff member's or lecturer's e-mail and phone are the person's (`iam.person`): what they write on **My profile** reaches
`iam.person` by trigger (`hrm.staff_profile_contact`), and `GET/PUT /api/v1/staff/contact` reads and writes it directly with
the same address checks. The Registry's edit of another person stays on `/persons/{id}/contact`.

## API

| Method | Path | Who |
|---|---|---|
| GET | `/api/v1/notices/templates` | ICT, admin, super, Registry |
| PUT | `/api/v1/notices/templates/{key}` | ICT, admin, super |
| POST | `/api/v1/notices/templates/{key}/preview` | readers — the three texts on sample values |
| POST | `/api/v1/notices/templates/{key}/test` | editors — a real message to one address, about nobody |
| GET / PUT | `/api/v1/notices/settings` | the portal address, the job batch, the biodata reminder switch and review period, the status counts |
| GET | `/api/v1/notices/jobs` | the jobs run or running |
| POST | `/api/v1/notices/biodata-reminders/run` | the weekly reminder, now |
| GET | `/api/v1/platform/notices?channel=&state=&kind=&q=&from=&to=` | the outbox searched; `byChannel` the picture per channel |
| GET | `/api/v1/me/notifications`, `/unread`; POST `/{id}/read`, `/read-all` | the student's portal notices |
| GET | `/api/v1/me/notices/unread`; POST `/{id}/read`, `/read-all` | a staff member's |
| GET | `/api/v1/me/biodata-status`; POST `/api/v1/me/biodata/confirm` | the student's biodata status and confirmation |
| GET / PUT | `/api/v1/staff/contact` | a staff member's own e-mail and phone |

## Writing a message from a module

A new event is a template and one call: `SELECT platform.tell_student(st.id, 'MY_EVENT', NULL, jsonb_build_object('AMOUNT', …),
'my-event:' || the_row_id)`. The event key is what makes a retried transaction harmless. A module's existing call to
`platform.queue_notice(channel, to, subject, body, kind, id)` keeps working unchanged (with the address now checked).

## Not yet (phase 2, V426)

Campaigns (the NEW PORTAL MIGRATION message to everyone brought over, targeted messages and announcements by faculty,
department, programme, level, session or office) with a recipient preview, a test send and a batched send through the job
queue; notification preferences for optional messages; the migration and biodata compliance dashboard, lists and report
on `people.biodata_statuses`.
