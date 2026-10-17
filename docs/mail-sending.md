# Sending e-mail over SMTP: pace, failures and the connection test (V532)

The portal sends e-mail from the account on the **Mail server** screen over SMTP (Microsoft 365 by default). Where that account is not set, it uses an HTTP relay named by `MOAUM_NOTICES_EMAIL_URL`.

## What went wrong on 14–17 Oct 2026

- **Wrong server.** The SMTP server was set to `smtp.mail.outlook.com`. That is one of Microsoft's servers for *incoming* mail, and it never answers a sign-in on port 587. Every e-mail failed with a connection timeout, and about 177,000 waited. The sending server is `smtp.office365.com`, port 587, STARTTLS.
- **Misleading Providers panel.** The panel on the Notices screen said "Email provider: None" throughout. It only looked at the relay variable, not the Mail server screen's account.
- **No pacing.** The dispatcher took 200 e-mails every 30 seconds. One Microsoft 365 mailbox allows about 30 a minute and 10,000 recipients a day. Once the server was right, the backlog would have throttled the mailbox and then got it blocked from sending.
- **Next refusal.** With the server corrected, Microsoft accepted the sign-in but refused every message ("STOREDRV.Submission"). The mailbox is `moaum@bsum.edu.ng` and the From address is `notifications@moaum.edu.ng`. Microsoft refuses a From address the mailbox has no "Send As" right on.

## Pace (`platform.notice_setting.smtp_per_minute`, `smtp_per_day`)

- The defaults are 30 a minute and 10,000 a day, Microsoft 365's limits for one mailbox. An empty limit means no limit; use that only for an SMTP service with limits of its own.
- ICT, admin and super set the limits on **Notices → Delivery → E-mail pace** (`PUT /api/v1/platform/notices/smtp-pace`, `platform.set_smtp_pace`). The change is audited with the other notice settings.
- Every SMTP attempt, including a test e-mail from the Mail server screen, is counted in `platform.smtp_attempt`, which keeps two days of attempts. `platform.smtp_pace()` gives the limits, the attempts in the last minute and in the last 24 hours, and how many more may go now.
- The pace is counted in the database, so it holds across every instance of the API. Each batch takes no more e-mail than the pace allows (`NoticeRepository.sendable(limit, delivery, emailCap)`).
- The screen says how long the waiting e-mail takes at the day's limit.
- The HTTP relay and SMS are not paced; their providers accept bulk sending.

## A failure of the account or the server (`SmtpFailure`)

`SmtpFailure` reads the error, including Microsoft 365's own wording, and sorts it into one of these:

- the server name does not exist;
- the server can't be reached;
- TLS failed;
- the sign-in was refused (535 5.7.139 / 5.7.3 / 5.7.57);
- password sign-in is switched off (550 5.7.30);
- the mailbox may not send as the From address ("SendAsDenied", 5.2.252, 5.7.60);
- the mailbox is blocked ("OutboundSpam");
- the sending limit was reached ("SubmissionQuotaExceeded", 4.4.2, 4.3.2);
- the message was refused for submission (another "STOREDRV.Submission" error);
- one recipient was refused (5.1.1 and the like).

Every case except a refused recipient (or an error it can't read) is the same for every message. When one happens, the dispatcher:

- stops e-mail for the rest of the batch;
- notes the error on the message (`NoticeRepository.held`) without counting an attempt against it, so a long outage no longer turns the waiting e-mail into failures after five tries;
- still counts the attempt on Provider health, so the failure shows there.

A refused recipient, or an error it can't read, counts against that message as before.

## The Providers panel

`GET /api/v1/platform/notices` now returns `emailVia` and `smsVia`, which say what each channel goes through:

- e-mail: "SMTP smtp.office365.com:587 STARTTLS, signed in as …, sending as … (the Mail server screen)", or the relay;
- SMS: the eBulkSMS account, or the relay.

`emailProvider` and `smsProvider` now count the Mail server and SMS gateway screens' accounts. Passwords are never read for this.

## The Mail server screen's test

`POST /api/v1/platform/mail/test` (ICT, admin and super) tries the values on the screen, saved or not. It uses the password typed on the screen, or else the saved one, which is never returned.

- **Test connection:** reaches the server and signs in. Nothing is sent.
- **Send a test e-mail:** sends a short message to the address given, from the From address. This also shows whether the mailbox may send as that address.

The answer says how far the test got (`CONNECTION`, `SIGN_IN`, `SEND`), what the failure means in words, and the server's own error.

The screen also warns before anything is saved:

- when the SMTP server is one of Microsoft's servers for incoming mail (`smtp.mail.outlook.com`, `*.mail.protection.outlook.com`);
- when the From address is on another domain than the mailbox.

## Coming

Microsoft plans to switch off password ("basic") sign-in for SMTP submission by default at the end of December 2026. The error will then be 550 5.7.30. Tenants can switch it back on for now. The lasting fix is OAuth sign-in (XOAUTH2 with an Entra app registration), which the portal does not have yet.

## Tests

- `SmtpFailureTest`: Microsoft 365's answers sorted.
- `SmtpPaceIT`: the pace is set by ICT only and within range, the batch is capped, a held message keeps its attempts, the notices screen names the pace, and the test endpoint reports an unreachable server as `CONNECTION`.
- `check.sql` block V532: the defaults, counting, the allowance never below none, no limit, and refusals.
- `lib/mail-sending.test.ts`: the screens' warnings and the pace in words.
