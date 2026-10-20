# Matriculation number correction

*Oct 2026 (V579).* Records → **Matriculation Correction** (`/matriculation/corrections`) corrects the matriculation number
of a student who already holds one. It is not issuance: a number is still issued under Matriculation Management. A
matriculation number stays permanent (BR-007): the only way one changes is through a correction that one officer
prepares and another decides.

## What a correction changes, and what it keeps

A correction changes `people.student.matric_no` and nothing else. The student keeps the same record and the same portal
account, and the registrations, results, payments, receipts and documents keep their rows and stay with the student. In
the same act:

- The old number is kept as a **former number** (`people.matric_alias`). It is never deleted, and any search for it finds
  the student. It is never given to anyone again:
  - the generator passes over it (`people.matric_number_taken`);
  - a register upload or any other write that gives it to a student is refused by name:
    `MATRIC_NUMBER_CORRECTED: X was corrected to Y (MCR/…)`.
- The **sign-in** moves to the new number. The account belongs to the student, not to the number, so the password is
  unchanged. A student who is still on their first password signs in with the new number as that password. The move is
  recorded in `people.student_username_change`.
- A new number in the form of the student's own **series** goes into the matriculation history like any number issued.
  The generator passes over its sequence, and the series' counter stays where it was.
- The **student is told** by e-mail, SMS and the portal (template `MATRIC_NUMBER_CORRECTED`): the old number, the new
  number, and that the new number is now the sign-in.
- **Documents** issued before the correction (certificates, identity cards, transcripts, receipts) stay as they were
  issued. Documents issued after it carry the new number.
- The **curriculum track** follows the number's prefix (V235). If changing the prefix changes the student's framework, the
  check says so before the decision.

## The check

`people.matric_correction_check(student, number)` runs as the number is typed, again when the correction is prepared, and
again at the moment of the decision.

**Problems** stop the correction:

| Code | When |
|---|---|
| `NO_NUMBER` | the student has no number yet (issue it under Matriculation Management) |
| `DUPLICATE_RECORD` | the record was ended as a duplicate of another |
| `EMPTY`, `SAME`, `SHAPE` | no number given, the number is the student's own, or it is not a matriculation number |
| `TAKEN` | **MATRICULATION NUMBER ALREADY ASSIGNED**: it is another student's number, another student's former number, issued to another student in the history, reserved by a matriculation batch, or proposed for another student by a waiting correction |
| `SERIES_TAKEN` | the sequence of the student's series was issued to another student |
| `PENDING` | a correction of the same student already waits for a decision |

**Points** are shown for the officer to look at; none of them stops the correction:

| Code | What it says |
|---|---|
| `PREFIX`, `YEAR` | the codes and year the configuration gives the student's programme and entry, against the number given |
| `SERIES` | the number takes a sequence of the student's series |
| `LEGACY_FORM` | the number is in the old portal's form, not the configured one |
| `FORMER` | the number is the student's own former number, so the correction gives it back |
| `DOCUMENTS`, `GRADUATED` | documents were already issued under the old number |
| `CURRICULUM` | the curriculum track changes with the prefix |
| `SIGN_IN` | the sign-in moves to the new number, and how the student will be told; with no e-mail or phone on record, the student must be told in person |

`people.matric_correction_suggestions(student)` proposes two numbers from the configuration:

- the same year and sequence under the codes the student's programme carries (`MOAU/AD/BUS/25/12939` becomes
  `MOAU/SC/CSC/25/12939`);
- the next number of the series.

## The workflow

| State | Meaning |
|---|---|
| `PENDING_REVIEW` | prepared, with the kind of error, the reason, any approval reference and evidence; nothing has reached the student |
| `COMPLETED` | approved by another officer and made at once, after a last check with the student, the number and the series locked |
| `REJECTED` | refused with a note |
| `CANCELLED` | withdrawn before a decision by the officer who prepared it, the Academic Office or the Registry |

Each correction has a reference `MCR/YYYY/NNNNNN`. A student has at most one correction waiting, and a number is proposed for
at most one student at a time. The kinds of error are:

- legacy migration error;
- wrong faculty code, programme code, year, series or sequence;
- duplicate assignment;
- data entry error;
- approved programme change;
- another verified error.

Supporting files (the Registrar's memo, the matriculation register, the legacy record) are PDF, JPEG or PNG, up to 5 MB.
They are kept in `people.matric_correction_evidence`, in the file store.

A change of programme is a separate act (the programme swap, V578; the inter-departmental transfer, V070). A transfer never
changes the number on its own: where the number must follow, it is corrected here afterwards.

## Who does what

| Office | Reads | Prepares | Decides |
|---|---|---|---|
| Academic Office, Records, Registrar, Deputy Registrar, Super Administrator | yes | yes | yes, but not a correction they prepared themselves |
| Director of ICT | yes | yes | a legacy migration correction only |
| ICT Support | yes (to help a student) | no | no |
| Internal Audit | yes | no | no |

The database holds every rule (`people.prepare_matric_correction`, `people.decide_matric_correction`,
`people.cancel_matric_correction`), whatever the screen shows.

## Where a former number still finds the student

- The register's search (Students) and the search in the top bar. A hit found by a former number says "Matriculation number
  corrected from …".
- This screen's search: by the current or a former number, the name, the JAMB, admission or application number, or the
  record's id, within a faculty, department, programme or level.
- The student's record. The Matriculation panel shows "Corrected from …", the number's history and any correction waiting.
- The student sign-in. A former number is answered "This matriculation number was corrected", without saying the new one,
  and the student is pointed to the e-mail and SMS that carried it.
- Sign-in help. A former number is recognised, so the student can still ask for help with it.
- `people.student_of_number(number)` for any further reader: CURRENT, CORRECTED, ADMISSION or JAMB.

## API

`/api/v1/matriculation/corrections` (`MatricCorrectionController`):

| Call | Purpose |
|---|---|
| `GET /search` | find students |
| `GET /places` | the faculty, department and programme filters |
| `GET /students/{id}` | the student, the suggestions, the number's history and the corrections |
| `POST /check` | check a number |
| `POST` | prepare a correction |
| `GET ?state=&q=` | list corrections |
| `GET /{id}` | one correction, with the live check while it waits and whether the reader may decide it |
| `POST /{id}/decide` | approve or reject |
| `POST /{id}/cancel` | cancel |
| `POST /{id}/evidence`, `GET /{id}/evidence/{e}` | add and read evidence |

The record's own `GET /api/v1/matriculation/students/{id}/record` carries `numberHistory` and `corrections`.
