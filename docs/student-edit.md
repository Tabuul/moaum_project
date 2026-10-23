# Academic Office student edit page (V642)

The University's master prompt of 23 October 2026 asked for one page where the Academic Office reads and corrects a student's
record, with every important change validated, transactional, audited and traceable. It adds no second student system and deletes
no history, and it changes no financial transaction. The page is **Academic Office → Students → Student Edit** (`/students/edit`
to find the student, `/students/{id}/edit` for the record). It is also reached from the student's full record with **Edit**.

## Who may do what

`people.student_edit_grant` holds each office's grants. **EDIT_STUDENT_ACADEMIC_RECORD** is the major permission and carries every
other: biodata, admission, academic placement, programme, department, faculty, level, session, status, matriculation,
classification, enrolment, academic history, graduation status, carry-over, spillover, registration, the registration override
(OVERRIDE_STUDENT_REGISTRATION) and VIEW_STUDENT_EDIT_HISTORY.

| Office | Grant |
|---|---|
| Academic Office, Registrar, Deputy Registrar, Super Administrator | EDIT_STUDENT_ACADEMIC_RECORD |
| Records, ICT, Platform administration, Audit, Deputy Audit | VIEW_STUDENT_EDIT_HISTORY |

The API checks the active office against the table on every read and write (`people.student_edit_may`), and the student's reach
(`StudentReach`). The screen hides what the office may not do; the server refuses it regardless.

## The sections

| Section | What is corrected | How |
|---|---|---|
| Biodata | Surname, other names, sex, date of birth | Here (`people.student_edit_apply`) |
| | Every other biodata field and the contacts | The biodata editor, embedded as on the full record |
| Admission | JAMB registration number, admission number, admission session, entry mode, entry level | Here; the two numbers are critical and confirmed |
| Academic placement | Faculty, department, programme, level on the new programme | Programme swap: checked, the impact shown, then made (V578, V633) |
| | Programme type, admission route | Classification decision (V469) |
| | Study mode, centre, curriculum track | Here |
| Level & spillover | Correct, progress, SP1, SP2 or the final year | `people.support_set_level`, `people.support_set_spillover` (V628, V641) |
| Academic status | Any status but GRADUATED, on an instrument | `people.change_status` |
| Matriculation | The matriculation number | Matriculation Correction (V579), opened for the student |
| Registration & carry-over | Add, remove, restore a course, submit; the academic override | The registration engine's own acts (`registration.support_add`, `support_drop`, `support_submit`) |
| Graduation | Apply the recommendation for a student outside the maximum period | A graduation reconciliation batch of one (V638) |
| Finance | Nothing: read only | **Report financial issue** raises a Payment ticket for the Bursary |
| Change history | — | Every change of the record, filtered |

## Validation and audit

- **One reading.** The page reads the record's version (`people.student_edit_version`, the row as read). A save made on an older
  reading is refused with STU_EDIT_STALE: "This student record was updated by another user. Refresh the record before saving your
  changes." The level functions also refuse a level that moved (LEVEL_CHANGED).
- **One transaction.** The fields corrected here are all checked, then all written, or none. The checks cover the permission per
  field, the reason, the version, the uniqueness of the JAMB and admission numbers, the session on the calendar and the entry level
  within the programme's levels.
- **A reason.** An important or critical change needs a reason of fifteen characters and three words or more; "test", "update" and
  "correction" are refused (`people.student_edit_reason_refused`).
- **Severity.** Identity, admission session, entry mode and level, placement, level and registration changes are IMPORTANT. The JAMB
  and admission numbers, a status change and a registration override are CRITICAL and are confirmed by the officer.
- **Kept.** Each change is a row on `people.student_edit` under STU-EDIT/YYYY/NNNNNN: the field, the value before and after, the
  reason, the severity, the effective session and semester, the evidence, who and when. The rows are never changed and are removed
  only with the record by the go-live reset. The audit spine keeps the student row before and after as it does for every write.
- **The history.** `people.student_edit_history` lists the edits beside the record's status changes, completed programme swaps,
  level changes, completed matriculation corrections, graduation reconciliations and classification decisions. A level or status
  change made on the page is shown once, under its STU-EDIT reference.

## Enrolments

One person may hold several student records: an undergraduate one and a postgraduate one, say. The page names every enrolment of
the person and corrects the one open; the name and contacts are the person's.

## API

| Method | Path | |
|---|---|---|
| GET | `/api/v1/student/edit/search?q=` | Name, matriculation, JAMB, admission or application number, student ID, phone or e-mail; twenty at most |
| GET | `/api/v1/student/students/{id}/edit` | The record, its version, the grants, the enrolments, the engine's position, the level options, the lists |
| PUT | `/api/v1/student/students/{id}/edit` | `{changes, reason, version, confirmCritical, effectiveSession, effectiveSemester, evidence}` |
| POST | `…/edit/level` | `{action: PROGRESS \| CORRECTION \| SPILLOVER, level, spilloverYear, expected, reason, acknowledgeRegistration, version}` |
| POST | `…/edit/status` | `{to, instrument, effectiveOn, effectiveSession, effectiveSemester, reason, confirmCritical, version}` |
| GET | `…/edit/registration`, `…/registration/checks`, `…/registration/offerings` | The engine's view, its rules for one course, courses beyond the menu |
| POST | `…/edit/registration/{add\|restore\|drop\|submit}` | `{session, semester, offering, reason, override, description}` |
| GET | `…/edit/history?from&to&user&field&type&q&page&size` | The change history |
| POST | `…/edit/financial-issue` | `{subject, description}`: a Payment ticket and an STU-EDIT note |

Tests: `db/check.sql` (V642) and `StudentEditIT`.
