# A transfer approved on the old portal, restored (V669)

The University's master prompt of 27 October 2026: "Inter-departmental transfer migration correction, Academic Office direct placement & matriculation number preservation".

## What happened

Some students moved department on the old portal, with Senate's approval. They kept the matriculation number of the department they left, as they should.

On this portal they were found in that old department again, by two routes:

- **The programme-mismatch list (`people.programme_mismatches`, V578)** read the department their matriculation number names.
  - Where the registrations migrated from before the transfer agreed with it, the list called the student a CONFIRMED mismatch and suggested the old department.
  - Where only the number differed, it still suggested the old department.
- **An old-portal student file uploaded again** (`people.import_students_rows`, `people.import_biography_rows`) wrote its programme over whatever the record held.

To put them right, the Academic Office had only the transfer desk's "Record an application". That starts the transfer again from the first desk, with the fee and the approvals.

## What already held

- **The matriculation number never changes.** `people.matric_is_immutable` (V013, V579) refuses every change except a matriculation correction. No transfer, programme swap or record move touches it, and no transfer issues a new one.
- **The programme swap moves a student directly.** It changes the programme and level at once (V578; since V633 the officer who starts it makes it). The history is kept, and registrations, results, payments and documents stay as they are.
- **The imports read the programme from the file.** They never read it from the matriculation number. Only the entry session comes from the number's year.

## What V669 does

### The old portal's transfer, recorded

`people.prior_transfer` holds a transfer approved on the old portal:

- the programme left and the programme joined;
- the levels;
- the session and semester it took effect;
- the date approved and the old portal's reference.

It is history, not an application. No transfer desk, fee or approval reads it.

### Restoring it, with no new application

The programme swap gains the kind `APPROVED_TRANSFER_RESTORED`. A plain swap of that kind is refused (`PSW_KIND`); it is made only by `people.restore_approved_transfer`.

1. **`people.restore_transfer_check`.** Every check of the programme swap, with two changes:
   - an application left in the transfer queue for the same programme is to be withdrawn, not a refusal;
   - a student already on the programme and level is recorded, not refused.

   The old portal's transfer is checked: the programme left, the session, the date (not in the future), and not recorded twice (`PTR_RECORDED`). The answer says what is never made: transfer applications, payments, approvals and matriculation numbers, all 0.
2. **`people.restore_approved_transfer`.**
   - The student goes onto the approved programme and level by the swap, made at once.
   - The transfer is recorded.
   - The application left in the queue is withdrawn, with the reason.
   - A student already on the programme gets the record only.

### Restoring in bulk

The bulk transfer (V587) gains the restoration as a mode of the same upload. It uses the same template, plus an **Approved On** column:

- the **Old** columns are the record as it stands;
- the **New** columns are the approved destination;
- the **Effective Session** and **Semester** are when the transfer took effect;
- the **Approval Reference** is the old portal's transfer reference.

Each row is checked by `people.restore_upload_check` and previewed. The valid rows are restored as one batch (`TRR/YYYY/NNNNNN`); the invalid ones are left out with their reasons. No transfer application is made.

### The mismatch list

- **No department from the number alone.** A transferred student keeps the number of the department they left, so `suggested_dept` comes only from the registrations.
- **Recorded moves are respected.** A student whose current programme was set by a recorded move (an effected transfer, a completed programme swap, a transfer approved on the old portal) is not judged by the number or by the admission programme. Only the registrations since that move count.

### The uploads

A placement this portal recorded (`people.placement_settled`) is never undone by an upload: the record keeps its programme and level.

The file's programme and level go to the Academic Office as a placement conflict (`people.placement_conflict`). The office either:

- keeps the record; or
- applies the file's placement by a programme swap (`people.decide_placement_conflict`).

Either way it gives the reason.

### The history

`people.programme_history` shows, in order:

- the original admission;
- the transfer approved on the old portal;
- the restoration (current).

## The screens

- **Transfer desk.**
  - **Restore a transfer approved on the old portal:** find the student by matriculation, JAMB or admission number and open the restoration, or go to **restore in bulk**.
  - "Record a new transfer application" is now clearly for a new request only.
- **Programme swap, one student** (`/programme-swap/{id}?restore=1`).
  - **Change type:** Approved transfer restored (old portal), with the programme left, the session and semester, the date approved and the old portal's reference.
  - **Validate:** shows the before and after, and says "This restores a previously approved transfer. It will NOT create a new transfer application."
  - **Open transfer:** the "transfer under way" note offers the restoration.
- **Student edit.** Its change types are the plain ones. "Transfer approved on the old portal? Restore it" leads to the restoration.
- **Bulk transfer.** "These transfers were approved on the old portal": the restoration template, the check, and "new transfer applications: 0".
- **Programme swap desk.** An **Upload conflicts** tab: what each upload named, what the record kept and why, with Keep or Apply.
- **Programme history** (swap page, student record). It shows "Inter-departmental transfer approved on the old portal" and "Approved transfer restored (no new application)".

## A genuine new transfer

A student asking to move now still applies through the transfer workflow: application, the desks, the fee, Senate, effected.

## Not built

- **Separate permission codes.** The restoration is held to the programme swap's offices: the Academic Office, the Registry, the Director of ICT and the super administrator.
- **A matriculation-number crosswalk.** The record keeps former numbers (`people.matric_alias`), and a student is found by matriculation, JAMB, admission or former number.

## Tests

- **check.sql V669:**
  - the mismatch list suggests nothing from the number alone;
  - the restoration is checked and made: on B at 300, the number unchanged, the application withdrawn, the transfer and history recorded;
  - a plain swap of that kind is refused;
  - an upload naming the department left keeps the record and raises a conflict, which is kept;
  - the rightly placed student is recorded only and no longer judged by the number;
  - recording twice is refused;
  - the bulk restoration restores the valid row and leaves the invalid one out;
  - one application in all (the mistaken one, withdrawn).
- **TransferRestoreIT:** the same through the API, the old-portal upload endpoint included, and a genuine new transfer still entering the queue.
- **`lib/programme-swap.test.ts`, `lib/transfer-bulk.test.ts`:** the restoration's words, the plain kinds, the conflict's words, and the restoration template read back.
