# A programme's code corrected (V716, 31 October 2026)

The University's word: "can i edit/update or change programme code?" — "do it".

A programme's code (`ref.programme.code`: C and five digits, JAMB's code) is the key 42 tables point at — students, applications, fee
lines, course bindings, specialisations, results. Until now nothing changed it; the programme merge (V574) joined two programmes, which
is not a correction. Now the Director of ICT and the ICT Support Desk correct it, as they correct a course's code (V713): the impact
first, a reason from the list, against the version they read, on a ticket where there is one, with a trail, and undone from the record.

## Who

- The Director of ICT (`ict`), the Head of the ICT Support Desk (`helpdeskhead`) and super, on any programme.
- An ICT Support Agent (`ictagent`) whose posting carries **Change a programme's code** (`EDIT_PROGRAMME_CODE`), over the programme's
  faculty or department. Without it: `STRUCTURE_CAPABILITY`; outside the posting's scope: `STRUCTURE_SCOPE`.
- Nobody else: the database refuses too (`PROGRAMME_CODE_OFFICE`).

## Where

**PG Programmes / Programme Structure › Programmes** (`/catalogue/structure/programmes`): each programme in use has **Correct code**.
**Programme Code Changes** (`/catalogue/programme-changes`, route `t/programmecodechanges`, beside Course Code & Title Changes) lists every
correction, with **Undo** for those who may correct.

## How

1. **Correct code** opens on the programme. Type the new code. As you type, the database says what the change would be: what hangs on
   the programme (students, applications, fee lines, bindings, specialisations, the codes already merged into it, what JAMB calls it)
   and why it would be refused:
   - `PROGRAMME_CODE_SHAPE`: not C and five digits;
   - `PROGRAMME_CODE_UNCHANGED`: the code as it stands;
   - `PROGRAMME_CODE_TAKEN`: another programme holds the code, in use or archived. A correction never joins two programmes; if they
     are one, merge them on Records › Programme Merge. (A code an undone correction left, with nothing naming it, may be taken again.)
   - `PROGRAMME_MERGED`: the programme was merged into another; its code is an alias and is not corrected.
2. Choose the reason: Wrong code entered, JAMB code changed, Senate renumbering, Migration correction, Legacy data correction,
   Duplicate data correction, ICT Support correction, Other (explained in the remarks). Name the ticket where there is one.
3. **Review the change**, then **Confirm change**. A newer version than the one read is refused (`PROGRAMME_CHANGED_SINCE`).

## What happens

- The new code is written as a copy of the programme: every column (name, department, faculty, category, award, matriculation code,
  final level), in use.
- The programme is merged into the copy (`ref.merge_programme`, V574): every record `ref.programme_reference` says moves — students
  (each postgraduate move recorded on `people.record_move`), applications, fee lines, course bindings, specialisations, rules, routes —
  moves to the new code, recorded row by row. History (`KEEP`: record moves, transfers from, old imports) stays as written under the
  old code, which keeps its name.
- The old code becomes an alias of the new (`ref.programme_alias`) and is archived: a student, application, fee line or binding written
  later with the old code — an upload, a JAMB list, an old-portal file — lands on the new code.
- What JAMB calls the programme follows: `ref.jamb_alias` is copied to the new code, `ref.jamb_alias_name` moved.
- The correction is written to `ref.programme_code_change` (the reason, remarks, ticket, the merge, how many students, what moved),
  which is never removed and altered only by its undoing. On a ticket, the change goes on the timeline.

## Undone

**Undo** on Programme Code Changes, with a reason: the merge is undone (every row back on the old code, the alias ended, the old code in
use again), the JAMB names go back, and the new code is archived — it stays on the register because the record of the correction names
it, and a later correction may take it again while nothing names it. A correction is undone once (`PROGRAMME_CODE_CHANGE_UNDONE`).

## Underneath

| Piece | What it is |
|---|---|
| `ref.programme_code_check(code, newCode)` | the programme as it reads, its version, the impact, the refusal; changes nothing |
| `ref.programme_code_impact(code)` | what hangs on the programme, every classed column counted |
| `ref.programme_version(programme)` | the version a correction is made against |
| `ref.correct_programme_code(code, newCode, reasonKind, remarks, version, ticket)` | the correction |
| `ref.undo_programme_code_correction(id, reason)` | undone from the record |
| `ref.programme_code_named(code)`, `ref.programme_code_reusable(code)` | whether anything names a code; whether an undone correction's code may be taken again |
| `ref.programme_code_change` | the trail |
| `ref.programme_merge_office` | restated: passes a code correction (`moaum.programme_correction`) |
| `helpdesk.support_capabilities()` | gains `EDIT_PROGRAMME_CODE` |
| `ProgrammeCodeController` | `POST /api/v1/catalogue/programmes/{code}/code-correction/check`, `POST …/code-correction?ticket=`, `GET /api/v1/catalogue/programme-code-changes`, `POST …/programme-code-changes/{id}/undo` |
| `StructureAccess.mayProgrammeCode / assertProgrammeCode` | the agent's reach |

## Tests

- `check.sql` V716, with a made-up programme: the impact read; the wrong shape, a taken code, the Registry, a stale version and Other
  without remarks refused; corrected — students, fee line, binding and JAMB names on the new code, the old archived and an alias, the
  trail written; a student written with the old code lands on the new; the old code not corrected again; undone — everything back, the
  new code archived with the alias ended; the code taken again by a second correction; undone twice refused; the record never altered.
- `ProgrammeCodeCorrectionIT`: the Registry refused; the check's impact and permission; an agent without the capability, out of scope,
  then within it on a ticket; a stale version; the correction and the alias; the trail read by the Registry, who may not undo; undone by
  the Head of the ICT Support Desk.
- `lib/programme-correction.test.ts`.
