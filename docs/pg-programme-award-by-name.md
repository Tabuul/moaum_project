# A postgraduate programme with no award recorded is read by its name (V707)

The University's word of 30 October 2026, with an applicant's portal: "PhD programme coming as Master instead of PhD programme".
Applicant PG/26/000119 applied for **PhD LAW**, and the portal's Programme tile read **Master**.

## Why it happened

- The postgraduate register upload (V203 to V463) makes a programme for an old-portal code it does not know. It names it
  `<AWARD> <DEPARTMENT>` (`PhD LAW`, `MSC CHEMISTRY`, `PGD SOCIOLOGY`) and records no award (`ref.programme.pg_award` is empty,
  `pg_research` false). On the live copy of 10 October 2026 that was 175 of the 364 postgraduate programmes in use, 69 of them PhD.
- V574's programme merge leaves them so: an empty award is how its desk tells an older code from the catalogue's. The School
  merges them into the catalogue's programmes; until then applicants can choose them.
- An application is filed at its programme's award level (`admissions.pg_award_level`), which reads an empty award as a
  Master's (800). A PhD applicant on `PhD LAW` was therefore filed at 800, shown "Master", asked a Master's applicant's documents
  (no higher degree) and no research proposal.
- Students on these programmes are not affected: their level is the one the register gave them (on that copy, 1,234 of the
  1,244 on the PhD ones are at 900).

## What changed

- `admissions.pg_award_of(award, name)`: the award a programme is read at. The recorded award comes first; with none, the award
  its name begins with (V574's `ref.programme_degree`, else the first word without its stops: Ph.D., M.Phil., M.Sc.).
  `admissions.pg_research_of(research, award, name)`: a PhD or MPhil read by its name is a research degree.
- `trg_pg_application_programme_level` (before insert, and when the programme is changed): an application to a programme with
  no award recorded is filed at its name's level (PhD 900, PGD 700), whichever door writes it: the public form or the old
  portal's migration. It runs after V574's alias trigger, so it reads the programme an old code lands on. A programme with an
  award recorded is left to the door, as before.
- The applications already filed at another level and not yet on the register are corrected when V707 runs. An admitted one
  keeps the level its student was given. The migration says how many of each.
- The API reads the award and the research degree the same way: the form's programme list (with its level), the applicant's
  portal, the referee's page and the School's desk. The portal shows the award in words (PhD, MPhil, PGD, M.Sc., …).
- No programme's recorded award is written: the merge desk reads them as before.

## Checked

- check.sql V707: made-up `PhD ZZLAW` and `PGD ZZLAW` with no award beside a catalogue M.Sc.; through the public form they are
  filed at 900 (asked 7 documents), 700 and 800; an application moved onto the PhD one follows it to 900; no application to
  such a programme is left at another level off the register.
- The correction on applications filed the old way: a PhD one at 800 to 900, a PGD one to 700, an admitted one left, a
  catalogue M.Sc. one untouched.
- `PgOneApplicationIT.aPhdProgrammeWithNoAwardRecordedIsAppliedForAsAPhd`: the form's list offers it as a PhD research degree at
  900; the applicant is filed at 900; their portal and the School's desk read PHD.
