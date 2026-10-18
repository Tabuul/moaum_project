# The Registry's records check (V536)

**Records Check** (`/records/check`) lists every live student (admitted, active or on probation) whose record is at odds with
itself or with the register, by what is wrong, and names the office that corrects each. Nothing is changed on the page; each
record is opened (the name links to the student's record) and corrected where its office corrects records.

Offices: Records, the Registrar, the Deputy Registrar, the Academic Office, the School of Postgraduate Studies and its secretary,
ICT, admin and super. A faculty filter narrows it; Excel and PDF go through the export engine and on the export log.

| Issue | Why it matters | Corrected by |
|---|---|---|
| Level beyond the programme | above the final level plus the spillover years allowed (`policy.progression_setting`): no fee line, timetable or result sheet reaches the student | Registry (Records), with the Academic Office |
| Postgraduate entry on an undergraduate programme | keeps every undergraduate fee line from the student, and the programme keeps every postgraduate one | Registry (Records), with the School of Postgraduate Studies |
| Undergraduate level on a postgraduate programme | a postgraduate student is read at 700–900 Level | School of Postgraduate Studies |
| Direct Entry at 100 Level | Direct Entry fee lines name 200 Level and up | Registry (Records) |
| No entry mode | every 2025/2026 fee line names one | Registry (Records) |
| No level, or not a level | matched by no fee line, course or result sheet | Registry (Records) |
| Programme withdrawn from the register | no classes, no fee line | Academic Office, with the Registry |
| No programme on the register | nothing of a programme reaches the student | Registry (Records) |
| No state of origin | charged as a non-indigene whatever the state | the student (biodata form) or the Registry |
| State spelt another way | matched by name: a home state spelt otherwise would be charged as non-indigene (a country, for a student from abroad, needs no correction) | Registry (Records) |

The kinds, their reasons and offices are rows of `people.record_issue_kind` (on the audit spine); `people.record_issues(issue,
faculty)` reads the register once — about 0.6 s for the 54,571 live students of the live-shaped copy, where on 17 Oct 2026 it found
3 levels beyond the programme (the same 3 students as the 3 undergraduate records with the postgraduate entry mode: one at 700 Level
on B.Sc. Accounting, two at 900 Level on MBBS), 423 undergraduates with no state of origin and 394 states spelt another way
(Cross-River, Nassarawa, FCT, or a country) — none of them a spelling of Benue. API: `GET /api/v1/records/issues?issue=&faculty=`.

## States of origin put right (V542)

The spellings the check found were put right by migration, each on the audit spine: a state of origin the register spells
otherwise is given the register's name (Cross-River → Cross River, Nassarawa → Nasarawa, Akwa-Ibom and Akwa Ibon → Akwa Ibom,
FCT, Fct, FCT-Abuja and Abuja → Federal Capital Territory, River → Rivers, C/River → Cross River), and a student with no state
of their own whose admission row spells it otherwise is given the register's name for it. Countries (a student from abroad) are
left as written and are no longer listed.

It stays so: `people.student` puts a known spelling right as it is written, by every path — the record form and the biodata
form already offer only the register's list; the register and biodata uploads and the old portal's carry what was typed — and a
blank state is no state. `ref.state_named(text)` and `ref.country_named(text)` give the register's name for a spelling.

Each issue now carries a **suggestion** (on the screen under the programme, and in the Excel and PDF): for a postgraduate record on
an undergraduate programme, the department's postgraduate programmes (on the copy, the B.Sc. Accounting record's department has
M.Sc. Accounting and Finance and M.Sc./Ph.D. Accounting and Finance; MBBS's department has none on the register); for a state
spelt another way, the register's name. The postgraduate records themselves are for the Registry and the School of Postgraduate
Studies to move: the check lists them with the suggestion.

## Acted on from the check (V548)

**The state of origin given on the Biodata form reaches the record.** The check said a student gives the state "on the biodata
form", but the form wrote only the biodata answer (`people.biodata`), while the fees and the check read the record
(`people.student.state_of_origin`, with the admission's state behind it): nothing a student or the Registry chose on the form
reached it (307 students' forms on the copy name a state the record does not hold). Now a state chosen on the form reaches the
record:

- chosen by an office (the Registry on the student's page, Biodata): always;
- chosen by the student: only where neither the record nor the admission holds a state, and never the home state (Benue) — an
  indigene pays less, which the Registry grants from the certificate of indigeneship by choosing the state on the student's
  Biodata. Until then the check shows, as the suggestion, "The student gave Benue on the Biodata form on …: confirm it from the
  certificate of indigeneship";
- a value that is not a state of the register changes nothing (the suggestion names it).

The students whose form already named a state other than the home state, while the record and the admission held none, were given
it by the migration.

**The students with no state of origin are told.** With "No state of origin" shown, the Registry (Records, the Registrar and Deputy,
ICT) presses **Tell the students**: each student listed (of the faculty chosen, or all) is sent the notice *Give your state of
origin* (template `RECORD_STATE_OF_ORIGIN`, by e-mail, SMS and the portal) — at most once a week each, and not a student who has
given the home state and waits for the Registry. The panel shows how many were told (and when last), have given it since, still
have not, were never told, wait for the Registry, and the notices by channel and state. Each telling is kept in
`people.record_issue_notice`; `people.tell_record_issue(issue, faculty)`, `people.record_issue_progress(issue, faculty)`;
`POST`/`GET /api/v1/records/issues/notices`. On the copy the 423 students were told in one press (408 e-mails, 408 SMS and 423 portal
notices); a second press the same week told nobody.

**A postgraduate record is moved to its programme.** With "Postgraduate entry on an undergraduate programme" (or a level of 700 and
above beyond an undergraduate programme) shown, Records, the Registrar and Deputy, the School of Postgraduate Studies and its
secretary see **Move** on each record: the window lists the postgraduate programmes, the student's department's first, the level
(700, 800 or 900) and asks why (at least ten characters). The move sets the programme, the level and the entry mode POSTGRADUATE,
and is kept in `people.record_move` with the reason, the officer and the office, and on the audit spine. Only a live postgraduate
record on an undergraduate programme is moved here (`RECORD_MOVE_NOT_POSTGRADUATE`); any other change of programme is a transfer.
`people.record_move_options(student)`, `people.move_record_to_programme(student, programme, level, reason)`;
`GET`/`POST /api/v1/records/issues/move/{student}`.
