# Deleting staff: removed or deactivated (V656)

The University's word of 25 October 2026: "add delete button to view all lecturers, we should be able to add and delete lecturers
and non academic staff as well".

## What there was

- **Upload Lecturers** (`/people/lecturers`) could add, edit and tick lecturers for **Delete selected**. The delete
  (`iam.delete_lecturers`, V138) wiped the person outright: the sign-in and its history, every office grant, the establishment
  record. It skipped a lecturer who taught a class, without saying why. Anything else the person had touched (a score sheet, a
  deferment decision, a ticket, a payslip) either blocked the delete or would have lost its link.
- **Upload Non-Academic Staff** (`/people/staff`) could only load the roll. It had no single add and no delete.

## What happens now

A person becomes part of the University's records as soon as anything points at them. So the database decides, person by person:

| The person is… | Deleting them… |
|---|---|
| tied to no record (added by mistake, never used) | **deletes them permanently**: person, sign-in, office grants, staff record, photo and profile |
| tied to any record | **deactivates them**: off every list, sign-in refused, every office grant ended yesterday, open sessions ended. Everything they did stays as it was, and they can be restored. |
| yourself, a holder of a live office other than lecturer (Head of Department, Dean, …), or also a student | **leaves them as they are**, saying why. End the office on Users & roles first. |

"Tied to" is read by `iam.staff_ties_of(ids)`:

- **References to the person:** every foreign key to `iam.person`, read from the database catalogue so a table added later counts
  too. The person's own rows (sign-in, its events, office grants, staff record, photo, profile, contact reminders) don't count.
- **Sign-ins:** a sign-in made, or attempts on record.
- **Changes on the portal:** a change made by the person, from the audit trail's actor.

All of this is read once for the whole set, one query per foreign key. On the live-shaped copy, all 1,505 staff took 1.2 seconds.

## Modes and reasons

- **Delete where possible, deactivate the rest** (AUTO, recommended).
- **Deactivate only**: nobody is deleted; everyone can be restored.
- **Delete only**: a tied person is left as they are (CANNOT_REMOVE).

A reason is required: added in error, a duplicate, left the University, deceased, or other (described in at least a few words). The
dialog previews every person's outcome before anything is written.

## Who may

- **Teaching staff** (anyone who ever held the lecturer office): the Registrar, the Deputy Registrar, the Directorate of ICT, Admin
  and Super Admin. These are the offices that issue lecturers' sign-ins.
- **Non-academic staff:** the same offices, plus Human Resources.

The API checks the office list, and `iam.staff_change_may` checks each person, so Human Resources gets NOT_PERMITTED on a lecturer.

## The record

`iam.staff_change` holds one row for every deletion, deactivation and restoration. Each row has the person, staff record, grants and
sign-in as they were (never the password), what tied them, the reason, who and when, and the batch. Rows are written once: the
`STAFF_CHANGE_KEPT` trigger refuses any change, and only the go-live reset may delete them. The table is on the audit spine.

**Removed staff**, below each list, reads `iam.staff_changes(category)`. **Restore** (`iam.restore_staff`) undoes a deactivation:

- the person is back on the list and can sign in;
- the grants the deactivation ended are reopened to the end each had, unless someone changed them since;
- it works once, and needs a reason (deactivated in error, returned to service, other).

A deletion cannot be restored; the person is added again. Adding a staff id that belongs to a deactivated person is refused on the
screen, with a pointer to Restore.

## API

| | |
|---|---|
| `POST /api/v1/iam/staff/remove/preview` | `{ids, mode}`: each person's outcome and ties. Nothing is written. |
| `POST /api/v1/iam/staff/remove` | `{ids, mode, reasonCode, reason}`: `{removed, deactivated, refused, rows}` |
| `GET /api/v1/iam/staff/removed?category=ACADEMIC\|NON_ACADEMIC` | the record, newest first, with `restorable` |
| `POST /api/v1/iam/staff/removed/{id}/restore` | `{reasonCode, reason}` |

`POST /api/v1/iam/lecturers/delete` is gone.

## On the live-shaped copy

The preview over every staff member (nothing written) gave:

- **Teaching staff (632):** 610 tied to nothing, 10 tied to records (classes taught, allocation history, sign-ins), 12 holding another
  office.
- **Non-academic staff (873):** 870 tied to nothing, 3 holding an office.

## Checked by

- **`db/check.sql` V656** covers five made-up staff:
  - **Preview and permissions:** the preview writes nothing; Human Resources may change non-academic staff only, and a lecturer may
    change nobody.
  - **Reasons and modes:** a reason is required and Other must be described; Delete only leaves a tied person as they were.
  - **Applied:** the unused are deleted. The tied are deactivated: off the list, the grant ended, the session ended, the class still
    theirs, no password kept. The Head of Department and oneself are refused.
  - **Restore:** a deactivation is restored once with its grant reopened; a deletion cannot be restored. The record of changes cannot
    be altered.
- **`StaffRemovalIT`** covers the same through the API, starting from staff loaded by the real uploads. The removed list and the old
  endpoint gone are checked too.
- **`frontend/src/lib/staff-removal.test.ts`**.
