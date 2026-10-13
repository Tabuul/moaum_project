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

## Campaigns (V426)

A message to many, decided by an office, on **Campaigns & announcements** (`/notices/campaigns`): the NEW PORTAL MIGRATION
welcome to everyone brought over, an announcement to a faculty, a department, a programme, a level, a session, the staff,
the lecturers or the applicants. Nobody is typed in: `platform.campaign_recipients` reads the students from the register
(`people.student` with `people.student_reach`), the staff from `iam.person` with an active office, the applicants from
`admissions.application` with their account, by the filters the office set (`platform.notice_campaign.audience`:
session, faculty, department, programme, level, entry mode, status, office, "came over from the old portal", "never
signed in").

| Step | Function | What happens |
|---|---|---|
| Write | `platform.campaign_save` | The template, the audience, the channels, the office's own words for an announcement (`[TITLE]`, `[MESSAGE]`, `[SMS_MESSAGE]`, `[SIGNATURE]`). ICT, the administrators, the Registry, Student Affairs and the Academic Office address anyone; a Dean, a faculty officer or a Head only the students of their own faculty or department (`CAMPAIGN_SCOPE`). |
| Preview | `platform.campaign_preview` | By kind: how many, how many with a good, bad or missing e-mail and phone, how many this campaign already reached. |
| Test | `platform.campaign_test` | The template to one address, about nobody. |
| Send | `platform.campaign_send` | A `CAMPAIGN` job on `platform.notice_job`; the first batch goes in the office's own request, the scheduler drains the rest (students, then staff, then applicants, the kind and cursor kept on the job). Each person is reached once per channel: the event key is `campaign:<id>`. An empty audience is refused (`CAMPAIGN_EMPTY`); a campaign sent is not edited (`CAMPAIGN_NOT_DRAFT`). |
| Report | `platform.campaign_report` | By channel: queued, sent, failed, bad addresses. |
| Cancel | `platform.campaign_cancel` | A draft or a campaign still sending; the job stops at its next batch. |

## Preferences (V426)

`platform.notice_preference`: a student's or staff member's own switch for e-mail and SMS on **optional** messages (an
announcement). A mandatory template (a window, a payment, a result, the biodata reminder) is never switched off;
`platform.notify` reads `platform.channel_allowed`. The student sets theirs on the notifications page
(`GET/PUT /api/v1/me/notifications/preferences`), a staff member on `GET/PUT /api/v1/me/notices/preferences`.

## The compliance view (V426)

**Biodata compliance** (`/biodata/compliance`; `GET /api/v1/biodata/compliance`, `/students`, `/duplicates`,
`POST /refresh`): the counts (up to date, incomplete, review required, outdated; who came over and has reviewed; no e-mail,
no phone, bad addresses; never signed in; reminded this week), the students behind each count filtered by status, faculty,
department, programme, level, entry session, entry mode and "came over", searched by name, number, e-mail or phone, printed
and exported; and the data-quality picture (`people.contact_quality`, `people.duplicate_contacts`: addresses missing, not
addresses, or shared by several students). A Dean, a faculty officer or a Head reads their own faculty or department
(`OfficeScope`).

Computing every student's status takes some ten seconds on a register of 54,000, so the offices read a reading the
scheduler takes every quarter of an hour and after each reminder run (`people.biodata_status_snapshot`,
`people.refresh_biodata_snapshot`; its time is shown; "Take the reading now" for ICT and the Registry). A student's own
status is always computed live, and their confirmation refreshes their row at once.

## Staff reach, and the contact prompt at sign-in (V430)

The campaigns and reminders reach a person only where the record holds an address. On the live register 13,882 students
had no e-mail and 30,886 no phone; of the staff who came over, 627 had never signed in and one had an e-mail on record.

**Staff reach** (the Staff reach panel on Biodata compliance; `GET /api/v1/biodata/compliance/staff`, ICT, the Registry,
HR, Records and the administrators): for every active person with an office, whether the e-mail and the phone are present
and usable — reachable, phone only, e-mail only, unreachable — with who never signed in and who was reminded this week;
the people behind a status, filtered by office and searched (`iam.staff_reach_summary`, `iam.staff_reach_list`). The weekly
reminder (`iam.remind_staff_contact`, Tuesday mornings on ICT's switch `platform.notice_setting.staff_contact_remind`, or
"Run the staff contact reminder now") speaks through the `STAFF_CONTACT_REMINDER` template by the channel the person has
and on the portal, once in seven days; the HR office is told once a week how many staff cannot be reached at all.

**The contact prompt**: `/api/v1/iam/me` carries `contactPrompt` — `ASK` while the portal holds no usable e-mail or phone
for the signed-in student or staff member (`platform.contact_prompt_for`), unless they put it off in the last seven days
(`POST /api/v1/me/contact-prompt/skip`). The shell shows one line with two fields on whatever screen they land on; the
answer is the contact they already keep (a student's `PUT /api/v1/me/contact`, a staff member's `PUT /api/v1/staff/contact`).
Nobody is locked out; applicants are not asked (their account holds the address they applied with).

## The Quickteller door watched, and kept to Interswitch (V433)

For four days in October 2026 a firewall rule in front of the portal refused Interswitch's payment notifications and nobody
on the portal's side knew until Interswitch wrote. The PAYDirect door is now watched: every quarter of an hour
`finance.watch_paydirect()` reads the door's own rhythm from its log (`finance.gateway_event`: the longest quiet spell among
its calls in the fortnight before the last one) and, once per silence, tells the Directorate of ICT and the Bursary through
the `PAYDIRECT_SILENT` template when the door has been quiet for longer than that rhythm allows — never for less than
`finance.paydirect_setting.silence_hours` (6 by default). A door never called, or called fewer than twenty times in that
fortnight, has no rhythm to judge by and is not reported. The message names any call the door itself refused in the quiet
time. The Gateways screen shows the last validation, the last notification, the quiet time against the threshold, and "Check
now"; `PUT /api/v1/payments/paydirect/door` sets the switch and the hours (ICT), `POST …/door/watch` runs it now.

The validation door needs no credential, so the door may be kept to Interswitch: `finance.paydirect_allowed_address` (an
address or a range, `POST …/door/addresses`, `…/addresses/remove`) and the switch `restrict_addresses`. Every call is counted
by its address (`finance.paydirect_door_access`, shown as "who called in the last seven days"), and the switch is refused
while no listed address has been seen at the door in the last seven days (`PAYDIRECT_ADDRESS_UNSEEN`), so it is never
switched on blind; the last listed address is not removed while the door is kept (`PAYDIRECT_LAST_ADDRESS`). The address is
the one the API reads for the caller (`ClientAddress`), so behind CloudFront the API task needs `MOAUM_CLIENT_ADDRESS=2`.

## The outbox paused, switched and cleared (V436)

While the portal is being tested, what waits in the outbox must be stoppable without a trace being lost, and what the modules
generate must be keepable from real students without the modules being touched. On **Notifications** (`/notices`):

| Piece | Where | What it does |
|---|---|---|
| The delivery switches | `platform.notice_setting.dispatch_enabled / email_delivery / sms_delivery / portal_delivery`; `PUT /api/v1/platform/notices/delivery` (ICT, administrators) | Delivery only. Queue processing paused holds every channel; e-mail or SMS delivery off is generated and held (the dispatcher's batch, `NoticeRepository.sendable`, takes only the channels switched on); a portal notice is delivered the moment it is made, so the portal switch keeps it from being made (`platform.queue_notice`). Templates are still tested and previewed; the outbox is still inspected. |
| A message cancelled | `platform.notice.state = 'CANCELLED'`, `cancelled_at`, `cancelled_by`, `cancel_reason` | Never deleted. The dispatcher picks QUEUED only and the retries FAILED only, so a cancelled message is never sent. Its event key stays, so the same event is not raised again to that person. |
| The clearance | `platform.clear_notice_queue(channels, reason, actor, office)`; `POST /api/v1/platform/notices/clear` (the ICT Director and the Super Administrator only) | After a confirmation naming the counts. The API pauses queue processing first, in a transaction of its own, then runs the clearance under the dispatcher's own lock (`JobLock` `notice-dispatcher`): a batch in flight finishes before it, none starts during it, and a lock that does not come free is reported (`NOTICE_DISPATCH_BUSY`), never worked around. E-mail, SMS or both (`NOTICE_CLEAR_CHANNEL`), a reason required (`NOTICE_CLEAR_REASON`), refused by the database while processing runs (`NOTICE_CLEAR_DISPATCHING`). Processing stays paused until the office resumes it. |
| The record | `platform.notice_clearance` (audited) | Who, when, why, what waited per channel, what was cancelled, what still waits, the sent and failed history left untouched, the jobs open — the clearance report, and "last cleared" on the screen. The cancelled messages themselves are audited row by row. |
| The jobs | `platform.open_notice_jobs()`, `platform.cancel_notice_job(job, reason, actor, office)`; `POST …/jobs/{id}/cancel` | A job still running (a window's messages, a campaign) would refill the queue it just emptied: ended here, state `CANCELLED`, never picked by `run_notice_job`; a campaign's job cancels the campaign (`campaign_cancel` now marks its job cancelled too). The weekly biodata and staff reminders keep their own switches. |

## Reminders before a window closes (V438)

Three days and one day before a school fees payment or course registration window closes (the University's, the Centre's
and the School's), the students of the session who have not yet done what the window is for are reminded: fees not paid in
full (`finance.position`; a student whose fees are not stated has nothing to pay and is left alone), no registration
submitted for the semester (`policy.window_done`). A daily pass at 08:00 Lagos (`platform.queue_closing_reminders`,
`moaum.windows.remind-cron`; "Run the closing reminders now" on the templates screen) queues one `WINDOW` job with the action
`CLOSING` per window, deadline and day — the deadline being the close, or the end of the late period once the close has
passed — and the job runner reminds through `WINDOW_CLOSING` (variants `:SCHOOL_FEES_PAYMENT`, `:COURSE_REGISTRATION`;
`[DAYS_WORD]`, `[DEADLINE]`), once per person under the event key `window-closing:<window>:<deadline date>:<days>`. The switch
is `platform.notice_setting.closing_reminders`.

## Delivery receipts (V438)

A message is SENT when the provider accepts it. A provider that reports further posts its report to the receipt door,
`POST /api/v1/notices/receipts/{resend|ebulksms|generic}`, behind the token the Directorate of ICT generates on Notifications
(`platform.notice_setting.receipt_token`, as `?token=` or `X-Receipt-Token`). The report is matched to the message by the
provider's id the dispatcher kept (`platform.notice.provider_id`: Resend's id; for eBulkSMS the message id the portal sent,
which is the notice's own) and written on it as `delivery_state` DELIVERED, BOUNCED or UNDELIVERED with `delivered_at` and
`delivery_detail` (`platform.record_receipt`) — never changing `state`: a late report on a cancelled or failed message is
logged as NOT_SENT and nothing changes. Every report is kept on `platform.notice_receipt` as it came (DELIVERED, BOUNCED,
UNDELIVERED, IGNORED for a word that says nothing, UNMATCHED, NOT_SENT), shown on Notifications, so what a provider actually
sends is seen before it is trusted; Resend's events are read as `type` + `data.email_id`, eBulkSMS's as `msgid` + `status`
(DELIVRD, UNDELIV, EXPIRED, REJECTD), a plain `{id, status, detail}` otherwise. The by-channel picture and the clearance
report count the delivered and the bounced. Mail sent over SMTP has no receipt: bounces come back as mail and are not read.

## Applicant deadlines (V440)

The daily pass of V438 also queues the applicant windows: Post-UTME registration (an application started and not
submitted), admission status checking (a submitted application whose status was never checked) and the Post-UTME CBT (a
submitted application with no attempt). The job runner reminds the applicants of the session who have not yet done what the
window is for (`platform.applicant_window_audience`, `policy.applicant_window_done`) through `WINDOW_CLOSING`'s variants
`:POST_UTME_REGISTRATION`, `:ADMISSION_STATUS_CHECKING` and `:POST_UTME_CBT`, with the applicant's own tokens
(`[APPLICATION_NUMBER]`, `[JAMB_NUMBER]`), once per deadline and day. JUPEB, postgraduate and CCE application windows are
not reminded yet: their applications and contacts live in their own modules.

## A person's messages, and one sent again (V440)

Student 360 (the offices that read the whole University's records) and the staff record (the Registry, HR, Records and ICT)
show every e-mail, SMS and portal notice the portal sent the person, newest first, with the provider's word where there is
one (`platform.messages_for`; `GET /api/v1/students/{id}/messages`, `GET /api/v1/hr/staff/{id}/messages`). A message that
failed, was cancelled, bounced or went undelivered is sent again once (`platform.resend_notice`; `POST …/{notice}/resend`),
to the address the record holds now rather than the one on the message — correct the record first when the address was
the trouble — and the new message remembers the one it repeats (`platform.notice.resent_from`). A portal notice is on the
dashboard already and is not sent again (`NOTICE_RESEND_CHANNEL`); a queued or delivered message is not either
(`NOTICE_RESEND_STATE`).

The Quick Operational Manual (edition 2.1) carries the procedures of these screens: notification templates and settings,
campaigns, the delivery switches and the queue cleared, the receipt door, biodata compliance and staff reach, the
Quickteller door, and a student's messages.

## The providers watched (V442)

The dispatcher counts every attempt by channel, provider (`smtp`, `ebulksms`, `relay`) and hour, with the last error
(`platform.dispatch_tally`). Every ten minutes (`ProviderWatch`, `moaum.providers.watch-every-ms`) the SMS balance is read from
eBulkSMS when an eBulkSMS account is set (a GET of `https://api.ebulksms.com/balance/{username}/{apikey}`, as eBulkSMS documents
it; the answer is kept as it came and read as a number when it is one), and `platform.watch_providers` judges each channel
(`platform.provider_status`): **Off** (processing paused or the channel's delivery switched off — not a fault), **Failing** (at
least `failing_min`, 10, tried and `failing_share`, 50 %, failed in the last two clock hours), **Stuck** (a message has waited
`stuck_minutes`, 30, with nothing tried: no provider wired, or the dispatcher not running), **Low balance** (below
`sms_low_balance`, 500 units; 0 switches it off), else OK or Idle. A problem is told to every ICT office holder once per
episode through `PROVIDER_PROBLEM` (variants `:FAILING`, `:STUCK`, `:LOW_BALANCE`) on the channels that still work — an e-mail
problem by SMS and on the portal, an SMS problem by e-mail and on the portal; a channel well again ends the episode.
Provider health on Notifications shows it all, with "Check now" and the settings (`PUT /api/v1/platform/notices/providers`,
`POST …/providers/check`).

## The accounts still on their first password (V442)

With the first sign-in on the person's own number restored, an account nobody has claimed opens to whoever knows the number.
First passwords on Biodata compliance counts and lists them as the doors judge them — a student account to be changed with
no temporary password standing, a staff credential to be changed, an applicant account on its first-login sentinel
(`iam.first_password_summary`, `_units`, `_students`, `_staff`, `_others`; `GET /api/v1/biodata/compliance/first-passwords`,
`…/first-passwords/staff`). A Dean or Head reads their own faculty or department; the staff and the migrated applicants are
read by the offices that read the whole University. A reminder is a campaign: the filter "Only those still on their first
password" (`first_password` in `platform.campaign_recipients`, for students, staff and applicants) with the template
`FIRST_PASSWORD_REMINDER` ("Choose your own password").

## The SMS cost of a campaign (V444)

An SMS is charged by the page: 160 characters of the GSM alphabet make one, 153 a page once a message runs longer; a message
with any character outside it is sent as Unicode, 70 characters one, 67 a page (`platform.sms_units`). The campaign's own SMS
is rendered for its first recipient and allowed fifteen characters for longer names; its pages times the recipients with a
usable phone is what it needs (`platform.campaign_sms_cost`), set against the balance the provider watch last read. The
preview shows it beside the recipients; the send is refused while the balance is known and does not cover it
(`CAMPAIGN_SMS_CREDIT`), and the screen asks whether to send anyway (`{"acceptShortfall": true}`): the e-mail and portal
messages all go, the SMS stop when the credit runs out.

## The other application deadlines (V444)

The daily pass of V438/V440 now also reminds the applicants of the JUPEB application window (a draft, or an application
returned for correction), the postgraduate application window (a draft) and the CCE application window (not yet submitted),
each through `WINDOW_CLOSING`'s variant for the route, on the address the route's own module holds
(`platform.tell_route_applicant`: `jupeb.application`, `admissions.pg_applicant`, the CCE candidate's applicant account), once
per deadline and day. The Post-UTME windows no longer reach a CCE candidate.

## Not yet

Bounces of mail sent over SMTP (they come back as mail; reading the mailbox is not built); eBulkSMS's delivery reports are
read by the field names their documentation gives and are kept as they come, so the first real one shows whether the reading
is right.
