# Course registration approval: automatic, reset and registered again (V491)

## What changed

Before, a student submitted a course registration and it waited (`SUBMITTED`) until the Head of Department approved it
(`APPROVED`); the examination card followed an approved registration and the Bursary's clearance for the examination.
Many current registrations carry courses brought over from the old portal.

Now the approval is a **rule** (`registration.approval_policy`), set by session, and by semester where a semester differs:

| Mode | What a submission does |
|---|---|
| `HOD_APPROVAL_REQUIRED` | waits for the Head of Department (the standing rule, the row with no session) |
| `AUTO_APPROVAL` | approved at once if it passes every rule; otherwise kept for review with the reason |

Each rule also sets two switches:
- **ALLOW STUDENT REGISTRATION RESET** — whether a student may reset the semester's registration.
- **ALLOW EXAM CARD IMMEDIATELY AFTER APPROVAL** — whether the examination card is offered as soon as the registration is
  approved, rather than when Portal Management releases the examination timetable (V335).

V491 set the current session of each route to `AUTO_APPROVAL` with the reset allowed: the University's
(`policy.university_current_session()`), the Centre for Continuing Education's (`policy.route_session('CCE')`) and the
School of Postgraduate Studies' (`admissions.pg_current_session()`). On the live-shaped copy of 13 October 2026 that was
2025/2026 and 2024/2025 (CCE).

**Restoring the Head's approval** is one change of the rule: Academics → Course Registration Approval, choose the session,
HOD APPROVAL REQUIRED, a reason. Nothing of the Head's approval was removed; the approval desk and its API are as before.

## The automatic approval

`registration.student_submit` is unchanged up to the submission. It is the one path for the student's own Submit and ICT
Support's submission on a ticket (`registration.support_submit` calls it). Its checks are now `registration.submit_checks`:
- the session's school fees stated, and the semester's;
- the semester's school fees cleared (V149, V454);
- the GST gate, for the registration and for each GST/EPS course on it;
- the unit range for the level (the CCE load for a CCE student);
- the probation ceiling.

Course choice (`student_choose`, `student_add`) still enforces:
- the student's menu (courses offered to the programme and level this session);
- the code family (BSU-/MOAU-);
- prerequisites where the Academic Office enforces them (V482);
- GST entitlement;
- the registration window.

Under `AUTO_APPROVAL` the submission then calls `registration.auto_approve`, which approves only when:
- the student is admitted, active or on probation;
- the registration carries at least one course;
- every course is on the student's menu for that semester, or was added by ICT Support on the student's ticket.

The approval sets:
- `status = APPROVED`, `approval_mode = 'AUTO'`, `approved_by` empty (the rule approved it, not a person);
- the courses `APPROVED`, which puts them on the class lists and the score sheets.

The student is told once (notice `REG_AUTO_APPROVED`, keyed by the submission) that the registration is approved, and
whether the examination card is available or waits for the Bursary's clearance. A refresh sends nothing.

When a rule fails, the registration stays `SUBMITTED` and goes to `registration.approval_review` with the reason, for
example "CSC 401 is not offered to this student's programme and level for 2025/2026 semester 1", or "the school fees … are
not stated yet". It is never approved blindly.

The Head of Department's approve and return endpoints refuse with `REG_AUTO_APPROVAL_ACTIVE` while the semester is under
automatic approval; super keeps the break-glass approval. The approvals screen says *Automatic approval active*. A Head
approval records `approval_mode = 'HOD'`.

## The registrations already waiting

`registration.auto_approve_pending(session, semester)` judges every `SUBMITTED` registration under `AUTO_APPROVAL` again,
by `submit_checks` and `auto_approve`. It approves those that pass and keeps the rest for review. The migration ran it once.
On the live-shaped copy, 9 were waiting: 7 were approved, and 2 were kept because the student's programme had no school
fees stated. Setting a session to `AUTO_APPROVAL` on the screen runs it again, and *Judge the waiting registrations now*
runs it on demand. One registration is judged again with *Validate again* once its problem is put right.

## The reset

The student's Course Registration page shows **RESET COURSE REGISTRATION**, with a confirmation naming the session,
semester, student, programme, level and the number of courses, and the buttons CANCEL / RESET AND RE-REGISTER.
`POST /api/v1/me/registration/reset` takes the student from the session token, never an id from the browser.
`registration.student_reset` does the following.

**Refuses**, with the reason (`registration.reset_refusal`, also shown on the page):
- the registration window is closed (the portal's own check);
- the rule closes the reset to students (`REG_RESET_OFF`);
- the registration is locked (`REG_RESET_LOCKED`);
- the semester is closed (`REG_RESET_CLOSED`);
- a mark is already entered against any of its courses (`REG_RESET_HAS_RESULTS`);
- the semester's school fees are not stated or not cleared (`REG_RESET_FEES`). Such a student could not submit again, and
  a reset would leave them with no registration at all. The browser check on the live-shaped copy found a migrated,
  approved registration whose fees were not cleared; resetting it left the student unable to register.

**Records** the registration as it stood on `registration.registration_reset`: status, approval mode, level, every course
with its units and type, what was kept, who reset it, from where, why and when.

**Removes** the chosen courses exactly as choosing courses again already does. Carryovers, deferred courses and ICT
Support's ticketed additions stay, back to `REGISTERED`. The registration becomes `DRAFT` again, with no approval.

**Never touches** results, scores, published results, CGPA, transcripts, earlier semesters, payments, receipts or the
GST/EPS entitlement. A second reset of a registration already clear does nothing.

The student is told (`REG_RESET`) and registers again; the new submission is approved under the same rule.

## The examination card

The card is the existing one (`/student/exams/card/pdf`): the registration's own courses, the photograph and a signed QR
(V360). It never shows an invented date or venue. It is issued for an approved registration the Bursary clears for the
examination.

The Examinations page now offers it for the approved registration of the open semester, without waiting for the timetable
release, when the rule's card switch is on. It has three buttons with immediate feedback: VIEW EXAM CARD, DOWNLOAD PDF and
PRINT EXAM CARD. Each issue of the card is counted on `registration.exam_card_issue` (one row a student and semester, with
how many times).

## Oversight

**Academics → Course Registration Approval** (`/registration/approval`) is open to the Academic Office, the Registrar, the
Deputy Registrar, ICT and super; admin can read it.
- The rule for the session and semester, with who set it, when and why, and the form to change it.
- The figures, each opening its list: total registered, auto-approved, approved by a Head, pending, requires review, reset,
  re-registered, exam cards printed or downloaded.
- Exam cards available, read after the page because it asks the Bursary's clearance of each student.
- *Validate again* for a held registration.

## What was not built

- **Course mapping.** A course from the old portal under another code is the same course merged in Course Management
  (V386 `merge_course` → `course_alias`, V445), not mapped again here. The review list names the course that is not
  offered, so the Academic Office can merge or offer it.
- **Separate card status records.** The card is drawn on demand from the approved registration, so repeated clicks never
  create duplicate cards. Its availability is the approval plus the Bursary's clearance, and its issue is counted.

## Permissions

The portal's permissions are offices.

| Permission asked for | Held by |
|---|---|
| `REGISTER_COURSES`, `VIEW_COURSE_REGISTRATION`, `RESET_COURSE_REGISTRATION`, `VIEW_EXAM_CARD`, `DOWNLOAD_EXAM_CARD`, `PRINT_EXAM_CARD` | the student, on their own record |
| `MANAGE_COURSE_REGISTRATION_APPROVAL_MODE`, `RECONCILE_MIGRATED_COURSE_REGISTRATION` | academic, registrar, dregistrar, ict, super |
| `VIEW_REGISTRATION_EXCEPTIONS`, `VIEW_REGISTRATION_AUDIT` | the same, and admin |
| `VIEW_COURSE_REGISTRATION` for a Head | the existing approvals screen, read only while approval is automatic |

## Audit

| Act | Where it is recorded |
|---|---|
| The rule, a review, a reset | `registration.approval_policy`, `approval_review` and `registration_reset`, all on the audit spine with the actor, office, reason and IP |
| An approval | the registration row: `approval_mode`, `approved_at`, and the actor on the spine |
| An issue of the card | `exam_card_issue` |
| Notices to the student | the notification engine's outbox, once per event |
