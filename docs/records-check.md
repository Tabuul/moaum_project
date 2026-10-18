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
