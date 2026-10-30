# Postgraduate applicants admitted on the old portal go straight to school fees (V712)

The University's word of 30 October 2026: "allow all admitted migration pg applicant student to bypass all the process and pay
school fee, but we will upload their history of the other payments from the old portal".

## Before

V675 brought an applicant admitted on the old portal (the admitted template: "Admitted", "Admission Offered", "Accepted") in as the
School's offer, and left them to finish on this portal:

- the acceptance fee, posted only if the old portal verified it, else held for the Bursary;
- physical screening, the old portal's decision applied, else opened here;
- only then the register (`admissions.pg_admit`): the student account, the admission number, school fees.

## Now

- **On the register at once.** An application the old portal decided as admitted (`pg_legacy_application.decided_on_old_portal`;
  offered or accepted here, not yet on the register) is taken as accepted and put on the register (`admissions.pg_mig_admit_direct`):
  - its acceptance date is the old portal's, else the day it is admitted;
  - a screening the old portal cleared is recorded as before; where this portal requires a screening and none has cleared the
    applicant, it is taken as cleared, recorded as the old portal's;
  - `admissions.pg_admit` does the rest, unchanged: the student, the admission number, the student account;
  - nothing is recorded as paid: an acceptance fee the old portal only claimed stays held for the Bursary.
- **Kept back:** an applicant whom this portal's own screening officers found not cleared, or asked to correct something. That
  decision stands.
- **Whenever the migration touches one.** The import calls it for every row (through `admissions.pg_mig_screening`), so an admitted
  file uploaded later puts its applicants on the register as it imports.
- **No application or acceptance fee asked here.** `admissions.pg_new_fee_reference` refuses them those references
  (`PG_FEE_NOT_NEEDED`): those payments are the old portal's, and the Bursary uploads them as history. The applicant portal reads
  `oldPortalAdmitted` and asks for no fee. Its steps read "Admitted on the old portal", then "On the University register", and its
  note sends them to the student portal for school fees.
- **Signing in to pay school fees.** The student portal, on the admission number:
  - an applicant who has not chosen a password signs in with the admission number as the first password (V709);
  - one who chose a password on the applicant portal uses it there too (V709 carries it to the student account);
  - an applicant who had applied on this portal before the migration linked them keeps their own password.
- **Those already migrated** are put on the register when V712 runs; the deploy log names how many, and how many a screening
  decided here keeps back. No notice is sent: the applicant portal shows the admission number at the next sign-in.

## Checked

- check.sql V712: through the real import, an admitted applicant with nothing more on record and one whose acceptance fee the old
  portal only claims are both on the register at the import (the claimed fee still held), and neither is asked an application or
  acceptance fee; an applicant still applying is not touched; one whom this portal's screening did not clear is kept back.
- check.sql V675 restated where V712 changes it: the admitted file's applicant with a held fee, and the claimed applicant moved
  forward by the admitted file, are now on the register at the import.
- V712 on applicants migrated the V675 way: an offer, a linked applicant and one who had signed in put on the register (the offer's
  student account on the admission number, the others' on their own password); one already admitted unchanged.
- `PgMigrationIT`: the admitted applicants are on the register at the import; the applicant portal reads `oldPortalAdmitted` and
  the acceptance fee reference is refused `PG_FEE_NOT_NEEDED`.
