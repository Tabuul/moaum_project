# A bounded office and the scope its desk reads (V316, V318, V325)

Some offices are held over one part of the University, and every desk of that office is scoped to it:

| Office | Held over | The desk reads |
|---|---|---|
| Head of Department, SIWES Coordinator | a department | that department |
| Examinations Officer | a programme (V318) or a department | the programme's department, or the department |
| Dean, Faculty Officer, Faculty Examinations Officer | a faculty | that faculty |
| Lecturer | a department (by the teaching-staff upload) | their department |

The grant (`iam.office_assignment`) carries the register's **code** for its scope. The console (Users & Roles) chooses it from
the register; a name typed through the API resolves to the code (V316: `iam.scope_code`), and a name the register does not
know is refused (`OFFICE_SCOPE_UNKNOWN`).

## What a desk reads, and from where

`iam.acting_department(person, office)` is the one rule, used by `OfficeScope.actingDept()` for every department desk.
It tries each source in turn and takes the **first that resolves to a live department** (not ended):

1. the office's own department grant (newest first);
2. the programme the office is held over (an Examinations Officer over `C00023` works in `MTC`);
3. the person's lecturer grant;
4. the home department on their staff record.

`iam.acting_faculty(person, office)` does the same for the faculty offices: the faculty grant, else the faculty of the staff
record's department. Before V325 the first scope *found* was matched alone, so a grant whose department had since ended hid
the lecturer grant that would have answered.

## The desk explains itself

`GET /api/v1/iam/me/scope` (any signed-in office; `iam.office_scope_state`) answers for the acting office:

```json
{ "office": "hod", "bounded": true, "kind": "department", "resolved": true, "code": "MTC",
  "name": "Mathematics and Computer Science", "source": "OFFICE_GRANT", "reason": null,
  "grant": { "id": "…", "scopeKind": "department", "scopeId": "MTC", "validFrom": "2026-09-01", "validTo": null, "instrument": "CNL/2026/91" } }
```

`source` says which of the four sources answered (`OFFICE_GRANT`, `PROGRAMME_GRANT`, `LECTURER_GRANT`, `STAFF_RECORD`).
`reason` says, when the office's **own** grant did not answer, why — one of:

| reason | meaning | the Registry's remedy |
|---|---|---|
| `NO_LIVE_GRANT` | no live grant of this office today (ended, or dated later than the sign-in that still carries it) | grant it, or sign out and in again if just granted |
| `GRANT_NOT_BOUNDED` | the grant is bounded to something else (the University, a unit…) | amend the grant: bound it to the department / faculty |
| `SCOPE_BLANK` | bounded to a department, none chosen | amend the grant: choose it from the register |
| `SCOPE_NOT_ON_REGISTER` | the scope names nothing on the register | amend the grant: choose it from the register |
| `SCOPE_ENDED` | the department has ended / the programme is archived | amend the grant to the department that replaced it |

The Head of Department's dashboard and staff list, the Examinations Officer's and the Dean's desks print the reason, the
grant's own words (dates, instrument, what it is bounded to) and the remedy in place of the former two-line notice. When a
fallback answered, a quieter note says so ("Read as Mathematics and Computer Science through your lecturer grant"), so the
Registry hears of the grant before anything depends on it. Users & Roles marks a grant whose scope resolves to nothing
live with **not on the register** (`scopeLive` on each grant row).

## A bounded office is granted with its bound (V325)

The grant trigger refuses a department office bounded to anything but a department, an Examinations Officer bounded to
anything but a department or a programme, a faculty office bounded to anything but a faculty — and any of them bounded to
nothing: `OFFICE_SCOPE_REQUIRED` (HTTP 422), with the remedy in the hint. The console offers only the permitted bound for
those offices. Grants already on record are not rewritten; the state function describes them and the console marks them.

## When a desk still says "not tied"

1. Open the desk: the notice now names the grant and the reason.
2. On Users & Roles, find the grant (newest first) — a red **not on the register** marks a scope that resolves to nothing.
3. Amend it (V319: the reason is recorded) choosing the department / programme / faculty from the register.
4. The office holder signs out and in again if the grant was made after their sign-in.

A portal running a build older than V325 shows the former notice; the data rules above apply there too, but the screen
cannot say which one.

## Tests

`db/check.sql` property 172 (refusals; the state through no grant, the grant, an ended department, the lecturer fallback);
`ScopeStateIT` (the refusal over the API, the state and the Head of Department's dashboard through the grant and through
the lecturer fallback).
