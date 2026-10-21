# The Bursary's audit trail and users, on the Bursar's dashboard

The Bursar's dashboard ends with two panels. Both read existing records; nothing is written and no migration was needed.

## Users with the Bursar's role

Everyone who holds, or has held, the Bursar's office, and the Students Account Officer's (the Bursary's sub-office). The list
comes from the office assignments ICT grants under Users & Roles. Those in post come first, Bursars before officers. Each row
shows:

- the person: name, staff number and e-mail;
- the role and its scope;
- the username, and whether the account is locked or its password must be changed;
- when the posting started and, for an acting or ended posting, when it ends;
- the last sign-in;
- the changes made under that office in the last thirty days, and when the last one was;
- the failed sign-ins (wrong password, locked) in the last thirty days.

**Trail** opens the audit trail on that person.

## Bursary audit trail

Every change those people made while acting as the Bursar or the Students Account Officer, and their sign-ins, newest first.
It is read from the University's tamper-evident audit trail (`audit.entries`, hash-chained) and from the staff sign-in record
(`iam.sign_in_event`). Each row shows:

- when, and who (with the office they acted as);
- what was done — Added, Changed or Removed — and on which kind of record: a fee line, a payment, a refund, an old fees upload,
  a student record, a level decision, and so on;
- the details: for a change, each field that changed with its value before and after (up to eight); for a record added or
  removed, its key facts (reference, item, amount, session, semester, level, state);
- the reason the person gave;
- the network address it came from.

The filters are: the user, the office acted as, changes or sign-ins only, the kind of change, the kind of record, a date range
(Lagos days) and a word of the reason. The tiles count the changes (all, and today), the sign-ins and the failed sign-ins within
the filters. **Excel** takes up to 20,000 rows of what is shown, on the University's export header, and the export is on the
export log.

Only changes made under a Bursary office are on this trail. What the same person did under another office they hold appears on
Internal Audit's full Audit Trail, not here.

## Access

The Bursar and Internal Audit (the Director of Audit and the Deputy) read both panels. The Students Account Officer, the
Registrar and other offices are refused (403).

- **API:** `GET /api/v1/finance/bursary/users`; `GET /api/v1/finance/bursary/audit?person&office&kind=ALL|CHANGES|SIGN_INS&action=INSERT|UPDATE|DELETE&subject&q&from&to&page&size`
  (`BursaryAuditController`). The trail is read through the actor index of `audit.entries`, so it stays quick however long the
  University's trail grows.
- **Screen:** `frontend/src/app/dashboards/BursaryAudit.tsx`, with the words in `lib/bursary-audit.ts`.
- **Tests:** `BursaryAuditIT`; `lib/bursary-audit.test.ts`.
