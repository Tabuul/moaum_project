# The GST & EPS examination permit card (V492, V589)

## What it is

A student sits the GST and EPS examinations on a **GST & EPS examination permit card**. It is a separate document from
the University's examination card, which is unchanged and still lists every registered course.

The permit is drawn with the examination card's own design (`lib/exam-card-pdf.ts`, which both documents now use):
- the crest and the University's name (from the institution profile, V320), and the office line;
- the photograph with the name under it, and the particulars;
- the dark table header, the instructions and regulations in two columns, the verification QR with its check code, and
  the footer.

The permit sets itself apart from the card in three ways:
- its title, **GST & EPS EXAMINATION PERMIT CARD**, is set white on a dark band, with the session and semester under it;
- it carries a **permit number** (`GST-EPS/<year>/<number>`);
- its course table has a **TYPE** column, and the courses are grouped under **GST COURSES** and **EPS COURSES**. A kind
  the student did not register has no heading.

## The one rule

The permit carries only the GST and EPS courses on the student's submitted course registration for the session and
semester. Nothing else appears on it:
- no departmental course;
- no course of another semester;
- no GST or EPS course the programme offers but the student did not register.

`registration.gst_eps_permit_courses(student, session, semester)` reads the courses in one targeted query:
- the student's registration for the semester, submitted — `SUBMITTED`, `RETURNED`, `APPROVED` or `LOCKED`, never a
  `DRAFT` (V589; before it, approved or locked only);
- its entries that stand (`REGISTERED` or `APPROVED`);
- the course classified GST or EPS.

The browser never filters courses. The API sends only these courses.

A course is GST or EPS by the classification the rest of the portal already reads: the GST/EPS engine, the registration
gate and the offices (V366/V367). That is `catalogue.course.kind = 'GST'` with `general_office` set to `GST` or `EPS` (by
code family through `catalogue.general_family`, or claimed by an office). No second classification was added. A course
named "Entrepreneurship and …" that no office holds is a departmental course and stays off the permit.

The code family is read behind the cohort prefix (V644): `GST 112`, `BSU-GST 112` and `MOAU-GST 112` are all the GST family, so a
student registered on `BSU-GST 112` has it on the permit. Before V644 the `BSU-` prefix hid the family and the course kept no office.

The courses are read at every issue, never stored as the permit's content:
- a reset (V491) takes them off;
- a new registration puts the new ones on, under the same permit number;
- a course from an earlier attempt or version is never kept.

Each issue logs the courses it carried.

## When it is issued

V589 (the University's instruction of 20 October 2026: a student who owes nothing prints the examination card and the
permit without effort). The permit is issued on the examination card's own terms (V567) and the GST fee, nothing more.
Before V589 the permit still asked what V567 had taken off the card — the registration approved, the Bursary's clearance
scheme satisfied for the examination (on the scheme in force, the session paid in full) and the cards released — so
students holding the card were refused the permit (226 of the 475 students with GST or EPS courses on the live-shaped
copy, and 2 more whose registration waited for the Head).

`registration.gst_eps_permit_state` gives the first rule that fails, with its code and its words:

| Code | Why |
|---|---|
| `GST_EPS_PERMIT_NOT_IN_STUDY` | the student is not admitted, active or on probation |
| `GST_EPS_PERMIT_NO_REGISTRATION` | no course registration for the semester |
| `GST_EPS_PERMIT_NOT_SUBMITTED` | the registration is a draft never submitted (the card's `EXAM_CARD_NOT_SUBMITTED`) |
| `GST_EPS_PERMIT_NO_COURSES` | "You have not registered any GST or EPS course for the selected session and semester." No empty permit is made. |
| `GST_EPS_PERMIT_REVOKED` | the GST or EPS office withdrew it (the student reads why) |
| `GST_EPS_PERMIT_GST_PAYMENT` | the GST fee the existing gate (`registration.gst_gate`) asks for is not confirmed. GST payment covers EPS. |
| `GST_EPS_PERMIT_NOT_PAID` | no confirmed school-fees payment for the session, as the card reads it (`registration.exam_card_paid`: any amount, through any channel the portal records it by — the card's `EXAM_CARD_NOT_PAID`) |

Gone with V589: `GST_EPS_PERMIT_NOT_APPROVED` (a submitted or returned registration now issues the permit as it issues the
card), `GST_EPS_PERMIT_NOT_CLEARED` (no clearance scheme is asked) and `GST_EPS_PERMIT_NOT_RELEASED` (no release switch
or V491 card-on-approval rule is asked). The courses are listed for any submitted registration, so an unpaid student sees
what the permit will carry.

V597: the minimum credit load no longer keeps a registration of GST/EPS courses alone, or of carry-overs alone (a GST carry-over
among them), from being submitted (`registration.load_kind`, flexible-course-registration.md), so the permit follows for such a
student too — one GST course of 2 units, paid, is enough. The permit itself never asks a minimum; it reads the submitted
registration's GST/EPS courses for the semester asked, first or second, and makes no empty permit.

No payment rule was added. Finance remains the payment authority, and the course registration remains the registration
authority.

## The examination's date, time and venue

These come from the systems that already hold them, in this order:
1. the student's own CBT sitting and seat (`assessment.cbt_seat` / `cbt_sitting`);
2. the examination timetable's slot (`assessment.exam_timetable`);
3. the CBT examination's window (`assessment.cbt_exam`).

Until one of them is set, the permit reads **TO BE SCHEDULED**. A date, time or venue is never invented. The permit is
drawn on demand, so a timetable change shows the next time it is viewed or printed.

## Issue, count and audit

`registration.issue_gst_eps_permit(student, session, semester, VIEW|DOWNLOAD|PRINT)` works as follows:
- It makes the permit on its first issue: one row in `registration.gst_eps_permit` a student and semester. The row has a
  UUID key and a business reference that is not the database's id.
- It counts every issue, and an advisory lock means a double click never makes two permits.
- It refuses with the reason when a rule fails.

Every act is written once to `registration.gst_eps_permit_event`, with the courses, the actor and the office:

| Act | Event |
|---|---|
| made | `GST_EPS_PERMIT_GENERATED` |
| viewed | `GST_EPS_PERMIT_VIEWED` |
| downloaded | `GST_EPS_PERMIT_DOWNLOADED` |
| printed | `GST_EPS_PERMIT_PRINTED` |
| withdrawn | `GST_EPS_PERMIT_REVOKED` |
| restored | `GST_EPS_PERMIT_RESTORED` |

The permit row and its revocation are on the audit spine. The permit's status reads GENERATED, DOWNLOADED, PRINTED or
REVOKED.

## The student's door

- `GET /api/v1/me/gst-eps-permit?semester=` — the permit's state for the student's own session (the examination card's)
  and the semester (the open one by default).
- `POST /api/v1/me/gst-eps-permit/issue {semester, act}` — the permit issued, with its check code.
- `GET /api/v1/me/gst-eps-permit/document?semester=` (V589) — the permit as the student last issued it, with its check code
  when it stands; nothing is made or counted. ICT Support's read-only view of the student's portal (V521) is refused every
  POST, so the PDF route falls back to this for the view: the agent sees the permit the student has opened, and is told
  when the student has not opened it yet (a permit is made, with its number, at the student's first view). The examination
  card's check code (`/api/v1/me/check-code?kind=EXAM`) likewise counts no issue from the view, which it used to refuse
  (the card's PDF route then said "Try again in a moment"; it now shows the API's own refusal).

The student comes from the session token, and the session is decided by the server. No student or permit id is ever taken
from the browser, so one student cannot ask for another's.

Screens:
- **Learning → GST & EPS Permit** (`/student/exams/gst-eps-permit`): the particulars, the courses by kind, the dates, the
  three buttons and the counts. When the permit is not available, it shows why, with BACK TO COURSE REGISTRATION, GST FEE
  or FEES & PAYMENTS as the remedy.
- **Examinations** shows a permit panel for each semester it shows, beside the examination card.
- **Dashboard**: VIEW GST & EPS PERMIT next to VIEW EXAM CARD, when the submitted registration carries a GST-kind course.

The PDF (`/student/exams/gst-eps-permit/pdf?semester=&act=`) is drawn by the portal's PDF engine (`lib/pdf-write`,
`finishPdf`). Its buttons are VIEW PERMIT ("Loading permit..."), DOWNLOAD PDF ("Preparing permit...") and PRINT PERMIT
("Preparing print..."). Each button is busy while its request runs, so a second click waits.

## Verification

The QR opens `/verify/gst-eps-permit?r=<reference>&c=<code>`. The code is signed by the API over the reference
(`CheckCodes.Kind.GST_EPS_PERMIT`, the V360 key), so references cannot be walked. The answer is the University's record
now:

| Status | What the page shows |
|---|---|
| **VALID** | the name, the photograph and the GST and EPS courses |
| **REVOKED** | the date only, never the reason |
| **INVALID** | a short reason, for example that the registration it was issued for is no longer approved |
| **NOT_FOUND** | no permit matches the reference and code |

No internal id is shown.

## The GST and EPS offices

**General Studies → Examination Permits** (`/gst/permits`, and `/eps/permits` for the EPS office) shows, for a session and
semester:
- the students a submitted registration of the office's courses concerns (V589; approved only before it), with each
  permit's status, reference and counts;
- figures that open their lists (students, generated, not generated, downloaded, printed, withdrawn);
- the examination schedule of the office's courses;
- a permit found by its number;
- a student's permit as the student sees it, with what was done with it.

The two offices are kept apart:
- The GST office reads the GST desk and the EPS office the EPS desk. Other readers (Registry, Academic Office, Bursary, ICT
  and so on) see both.
- A GST or EPS officer reads a student only when a submitted registration of the semester carries one of the office's
  courses.
- An office withdraws or restores a permit, with a reason of at least ten characters, only when it carries one of the
  office's courses (super may act on any).

The student is told (`GST_EPS_PERMIT_REVOKED` / `_RESTORED`) without the reason. The offices never change a registration
here.

## Tests

`GstEpsPermitIT` covers the scenarios A–L asked for:
- GST only, EPS only and both;
- none, which gives no permit;
- GST or EPS beside a departmental course;
- a previous semester's GST course;
- a reset, and a course removed with another registered;
- another student's permit;
- a catalogue course not registered;
- an old-portal approval (no approver);
- the GST fee gate;
- V589: the school fees unpaid read NOT_PAID with the courses still listed; a registration submitted and waiting for the
  Head, with part of the fees paid, has the permit as it has the card while the scheme refuses the examination and the
  cards are neither offered on approval nor released, and is on the offices' roster; ICT Support's view reads the card's
  check code and the issued permit without counting, while the student's own card is counted.

It also covers the offices' reach and the verification states. `check.sql` asserts the course rule and the issue,
logging, revocation and reset properties (the V492 block, restated for V589's codes) and, in the V589 block, the card's
terms with the scheme refusing and the cards unreleased, the draft and the unpaid, and the roster.

## Not built

- A separate attendance or presentation log at the hall: no general one exists, and the verification page is the
  invigilator's check, as for the examination card.
- An office that edits the permit's content: the content is the registration's.
