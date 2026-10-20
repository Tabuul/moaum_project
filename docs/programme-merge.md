# Programme merge

*Oct 2026 (V574).* Records → **Programme Merge** (`/records/programme-merge`) merges duplicate programmes into one, with
their students. A merge moves every record that names the old code onto the kept programme, records each student's move,
keeps the old code as an alias of the kept programme, and archives it. Nothing is deleted, and a merge can be undone from its
record.

## Why there are duplicates

The postgraduate register upload creates a programme for every old-portal code it does not know, and names it from the award
and the department alone ("MSC GEOGRAPHY"). The old portal kept one code per option, so one programme arrived under as many as
eleven codes. On the live-shaped copy that is 175 codes under 60 names, and 3,448 of the 3,450 postgraduate students sit on one
of them. New applicants are admitted to the School's own catalogue (M.Sc. Geography …), so the two catalogues stand side by
side. The catalogue also holds a few twins of its own (LL.M and Master of Laws, MBA twice …).

## The merges proposed

`ref.programme_merge_suggestions(category)` proposes the merges in three steps, which run in this order:

| Step | Kind | Proposal | Ticked when the screen opens |
|---|---|---|---|
| 1 | Same name | Codes of one name in one department, into the one most students sit on | yes |
| 2 | The School's programme | The remaining older code into the catalogue programme of its degree and department with the same subject ("MSC GEOGRAPHY" → "M.Sc. Geography") | yes |
| 2 | The department's only one | The department's only catalogue programme of that degree, whose name is not the same: check it | no |
| 2 | The School chooses | Several catalogue programmes of that degree in the department: pick one | no |
| 2 | None | No catalogue programme of that degree in the department: left as it is | no |
| 3 | Twin | Two catalogue programmes of one subject, award and department: into the one in use | yes |

The suggestions are only proposals. Each row's target can be changed, and the whole list can be downloaded as Excel and
uploaded again with the School's choices. The upload reads the columns **Old code** and **Merge into** (or **From** and
**To**), and leaves out a row with no target. On the live-shaped copy the ticked proposals are 143 merges. They moved students
2,184 times (a student on a code merged twice is moved twice), and the students left on older codes fell from 3,448 to 2,215,
all on codes the School still has to decide. **Preview** shows what the ticked merges would do: each one's students, the rows
moved and the rows kept, or why it is refused. The preview makes the merges and undoes them, so nothing changes.

## What a merge does

`ref.merge_programme(from, to, reason)` does the work. `ref.merge_programmes(pairs, reason)` runs a list of them in order, as
one act, and refreshes the moved students' academic positions once at the end. `ref.programme_reference` classes every column
that names a programme:

| Policy | Columns | In a merge |
|---|---|---|
| MOVE | students, postgraduate applications, CCE candidates, JUPEB applications, transfers and changes of programme asked for into it, a Preliminary Science target, a course's owner, external examiners | moved to the kept programme |
| MOVE_UNLESS_HELD | the programme's own settings: courses offered to it, offer proposals, who teaches its classes, specialisations, postgraduate courses, admission rules, closures, screening, O'Level allowances, College rules, GST fees, JUPEB relevance, routes | moved, unless the kept programme already holds the same; then the old row stays on the old code, with the archived programme |
| FEES | `finance.fee_schedule` | a session's lines are moved where the kept programme states no fees for that session, and ended where it does |
| KEEP | amendments, record moves, old transfers, imports, eligibility history | left as they were: they record what was |
| DERIVED | `people.academic_position` | refreshed from the student |

check.sql makes sure that every column that names a programme by a foreign key is in this list.

A specialisation that the kept programme also has (by name) takes the old one's students and applications. Each student
moved at 700, 800 or 900 level is recorded in `people.record_move` with the reason ("Programme merge: …"). Every row moved is
recorded in `ref.programme_merge_row` by its primary key. The old code becomes an alias of the kept programme in
`ref.programme_alias`, and a code merged into it earlier is pointed on to the kept one. A student, postgraduate application,
fee line or course offer written later with the old code lands on the kept programme (`ref.programme_alias_apply`), so a later
upload from the old portal does not bring the duplicate back.

## Refusals

| Code | When |
|---|---|
| `PROGRAMME_MERGE_REASON` | the reason is shorter than ten characters |
| `PROGRAMME_MERGE_UNKNOWN` | a code that is not a programme |
| `PROGRAMME_MERGE_SAME` | a programme merged into itself |
| `PROGRAMME_MERGE_DONE` | the code is already merged |
| `PROGRAMME_MERGE_ARCHIVED` | the kept programme is archived |
| `PROGRAMME_MERGE_CATEGORY` | an undergraduate and a postgraduate programme |
| `PROGRAMME_MERGE_OFFICE` (403) | an office that does not merge, or the School of Postgraduate Studies with an undergraduate programme |
| `PROGRAMME_MERGE_LATER` | undoing a merge whose kept programme has been merged away since: undo that one first |
| `PROGRAMME_MERGE_UNDONE` | the merge was undone already |

## Undoing a merge

`ref.undo_programme_merge(id, reason)` ends the alias, then sends back every row the merge moved (a fee line it ended comes
back into force), records each student's move back, and restores the old programme as it was before the merge. Merges made
one after another are undone in the reverse order. The history marks the merges that may be undone now.

## Who does it

| Office | Reads (suggestions, preview, history) | Merges and undoes |
|---|---|---|
| Records, Registrar, Deputy Registrar, Super Administrator | yes | every category |
| School of Postgraduate Studies, PG Secretary | yes | postgraduate programmes only (held by the database) |
| Academic Office, ICT, Administrator | yes | no |

The API is `/api/v1/records/programme-merge`: `GET /suggestions?category=`, `POST /preview {pairs}`,
`POST {pairs, reason}`, `GET /history`, and `POST /{id}/undo {reason}` (`ProgrammeMergeController`). The screen sends the
merges 20 at a time, in step order. On the live-shaped copy, the 143 merges took 21.8 s as one call, and their preview took
4.7 s.

## What is left to the School

The older codes the proposals cannot place are left as they are. On the live-shaped copy, 22 codes are under "The School
chooses" and 3 under "None"; 14 more are under "The department's only one", whose names the School checks before ticking
them. The options the old portal kept under separate codes (for example, the specialisations within MSC
GEOGRAPHY) are not in the portal. With the old portal's list of its codes and their option names, each code can be mapped to
the right specialisation, through the same upload.
