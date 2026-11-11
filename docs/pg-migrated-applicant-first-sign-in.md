# A migrated postgraduate applicant signs in on either number first (V709)

The University's word of 30 October 2026, with the sign-in page refusing an old-portal number (`S00220260204082731`, "Wrong
username or password"): "pg admitted programme cant login from the migrated lagacy data". Asked what a migrated applicant's first
password should be, the University chose **either number**: the old portal's or this portal's `PG/YY/NNNNNN`.

## Why they could not sign in

- **The sign-in page sent the number to the wrong door.** It reads the number typed to choose a door: `PG/YY/NNNNNN` goes to the
  postgraduate applicant's door, but a number of no shape it knows went to the staff door alone. The postgraduate door finds a
  migrated applicant by the old portal's number (V675), but was never asked.
- **Nobody knew the password.** V675 opens a migrated applicant's sign-in sealed: a cost-12 hash of a secret nobody holds. The
  applicant was to use "Forgot password" on their email, which many do not have or did not read.
- **The student portal was sealed too.** An applicant the old portal had screened is admitted to the register by the migration,
  and the student account copies the applicant's (sealed) password.

## What changed

- **The sign-in page.** A number of no known shape that the staff door refuses is tried at the postgraduate door. The hint under the
  username says "A member of staff on the staff number, or a postgraduate or JUPEB student on the old portal's number" (the
  JUPEB words since V718), and names a
  `PG/YY/NNNNNN` number as a postgraduate applicant's.
- **Either number is the first password.** An applicant the migration creates is to choose their own password
  (`pg_applicant.must_change_password`, the flag V706's reset uses). While it holds, the postgraduate door opens the account on the
  old number or the new one, however its letters and spaces are typed, and the portal opens nothing but "Choose your own password"
  until they do. Either number is accepted as the current password there; neither is accepted as the new one. Once they choose
  their own, the numbers open nothing.
- **The student portal on the admission number.** When an application gains its student while the applicant is still on a number,
  the student account is flagged to change too, so the student door's first password is the admission number (as for every
  student's first sign-in). The password the applicant chooses on the applicant portal, or by the reset link, is carried to a
  student account that has never been signed into, so "sign in with the admission number and the password you chose here" holds.
- **The notice.** The migration's email and SMS say to sign in with the old number, the new number or the email, and that either
  number is the first password; the admitted are told the admission number is their first password. An applicant who had applied
  on this portal and was linked by the migration keeps their own password and is told as before.
- **Those already migrated.** V709 puts every applicant the migration created, who has never signed in and never had a reset
  (by the School or by the link), on either number, and their student accounts never signed into on the admission number. The
  migration's notice in the deploy log gives both counts. They were told to use "Forgot password"; that still works too.
- No number is hashed into the accounts: hashing thousands at cost 12 would hold a deploy and an import for minutes. The numbers
  are compared at the door while the flag holds.

## Checked

- check.sql V709: an applicant written while the migration runs is to choose their own, one from the public form is not; on the
  register the first's student account opens on the admission number and the second's does not; the chosen password is carried to
  the student account never signed into, and one chosen after the student has signed in is not; no migrated applicant is left that
  nobody can open.
- V709 on applicants migrated the V675 way: an offer and an admitted applicant put on either number (the student account on the
  admission number); one already signed in, and one who applied here and was linked, left as they were.
- `PgMigrationIT.aMigratedApplicantSignsInOnEitherNumberFirstAndChoosesTheirOwn`: three applicants migrated through the API with
  old-portal numbers of the University's shape. The old number opens as the first password, however typed, and so does the new;
  nothing else opens; the portal asks for the change first; neither number is accepted as the new password; afterwards only the
  chosen password opens. The admitted one signs in to the student portal on the admission number; for another, the password chosen
  on the applicant portal opens the student portal and the admission number no longer does. The notices say how to sign in.
