# MBBS students stand in their own academic session (V733)

The University's master prompt of 12 November 2026, part A: MBBS students' "academic progression and session calendar operate one
academic session behind the general university academic calendar … allow eligible MBBS students to select and update their academic
session from their Student Dashboard without being forced to follow the general university current session … must apply specifically
to MBBS students and must not change the academic session of other programmes."

## What stood before (the root cause)

- A student's session was decided in two places: `people.student_current_session` (the database: a CCE student the Centre's route
  session, a postgraduate student the School's, **everyone else the University's CURRENT session**) and the API's
  `StudentPortalService.sessionOf`, which every `/me` page opens on. MBBS students are regular students, so they always stood in the
  University's session.
- Nothing per student or per programme existed. The only "behind the University" mechanism was the CCE route's offset, keyed by entry
  mode, not programme.
- Four readers decided a student's session by the University's own: the registration gate (the University's semester state of the
  session asked for — a past session's semesters are CLOSED, so a lagging MBBS student could not register in it), the cohort engine
  (`people.academic_position_rows_of`: registered this session, the final year, sessions elapsed), the past-session fee account
  (`finance.historical_rows_read`: every session before the University's current one is past — a lagging student's own session read as
  a past-session debt), and the GST/EPS rows (the level a session reads a student at).
- On the late-October copy of live the lag is real but not uniform: of the 2023/2024 MBBS entrants (300 Level) 95% paid first-semester
  fees of 2024/2025 and 5% of 2025/2026 (85% across the University); the 600 Level group likewise; 200 and 400 Level pay in the current
  session. So the session is the student's to state, within rules — not one offset for the programme.

## The rule

- **Who.** A student of a programme the College runs on its own calendar (`college.runs_programme`: `college.programme_rule` holds MBBS
  only), regular (not CCE or postgraduate), ACTIVE or on PROBATION. Every other student stands in the University's session, unchanged.
- **How far behind.** `college.programme_rule.sessions_behind_max` (1 for MBBS: "one academic session behind"; 0–3).
- **Approved sessions** (`people.study_session_options`): the University's current session and the CURRENT or CLOSED sessions before it
  on the calendar; never a planned (future) or cancelled or merged session; never before the entry session; at most
  `sessions_behind_max` behind. The student may not choose a session earlier than the latest one they registered courses in
  (BEHIND_YOUR_REGISTRATION), nor — while their present level is registered in one session — another session for that level
  (LEVEL_REGISTERED_ELSEWHERE: it would let the level be registered twice), nor a session that holds their registration of another
  level (REGISTERED_AT_ANOTHER_LEVEL: one registration a session and semester).
- **Who changes it.** The student, on the dashboard, confirming the previous session, the new one and the level
  (`people.choose_study_session`); the Academic Office, the Registry, the Provost, the College Secretary or the MBBS Coordinator, any
  approved session on the calendar's rules — a repeated year included — or back to the University's, with a reason of ten characters
  or more (`people.set_study_session`). Choosing the University's session ends the session of one's own. An office may always send a
  student back to the University's session, whatever the record now is; a change of programme or entry mode off the College's calendar
  (an inter-departmental transfer, a programme swap) ends it by itself, recorded.
- **What does not change.** The level, a registration, a result, a payment. A change marks the student's past-session fee account to
  be read again and recomputes their academic position.
- **Recorded.** `people.study_session` (one row a student; none = the University's) and `people.study_session_event`, written once:
  matriculation number, programme, previous and new session, level, when, by whom and as which office, how it stood (NOT_REQUIRED:
  the student's choice within the rules; SET_BY_OFFICE; ROLL_OVER). Both on the audit spine.

## Every module reads it

- **The database.** `people.student_current_session` returns the student's own session first — its twelve readers follow (results
  release per semester, spillover registration, the unit limit, the cohort cap, the level guards, the ID-card fee reference …);
  `people.academic_context` (the dashboard's session); the cohort engine (current session, registered this session, the final year);
  the past-session fee account (the past ends before the student's own session); the GST/EPS rows and their history test (the current
  level from the student's own session on); the results statement's current semester.
- **Registration in a session behind the University's** opens by the **College's semester** of that session and the student's level
  (`college.semester`, kept on College Calendar): `registration.college_semester`, read by the registration gate, the open semester,
  the calendar shown and add/drop. Until the College dates it, the University's (closed) semester refuses registration.
- **The API.** `StudentPortalService.sessionOf` returns the student's own session, so every `/me` page — fees, registration, course
  search, carry-overs, GST/EPS, outstanding fees — opens on it; an MBBS student with a session of their own is "on a calendar of their
  own" (`ownCalendar`), so the examination card, the GST/EPS permit, the docket and the timetable are that session's, and the fees page
  lists the sessions charged to them.
- **The session roll-over** moves every student in a session of their own one session on from it — never into the target, the
  University's next — once a target (a re-run moves nobody twice). Their level is promoted as the University's roll-over would promote
  it (counted from the entry session to the target, below the final level, no department hold), else held at it; the move is recorded
  (ROLL_OVER) and the result counts both (`moved_own_session`, `promoted_own_session`). The lag is kept; the University's roll-over of
  everyone else is unchanged.
- **Reports and dashboards** by session count each registration, payment and enrolment in its own session, as before; an MBBS student
  registered in 2025/2026 is in the 2025/2026 figures.

## The screens

- **Student dashboard** (`/student`, and the College area's overview `/college/student`): *Academic session management* — current
  session, level, the University's session, the approved sessions (each other one says why not), *Update session* with a confirmation
  naming the previous session, the new one and the level, and every change. Shown only to a student who may choose.
- **MBBS Academic Sessions** (`/college/study-sessions`; Provost, College Secretary, MBBS Coordinator, Academic Office): the students in
  a session of their own by session, every change, a student found by number and their session set with a reason.
- The student door's gates (biodata, school fees) let `/api/v1/me/study-session` through: the session decides the fees the student sees.

## Not done

- The two C00061 records with entry mode POSTGRADUATE (900 Level) follow the School's calendar, as before.
- 100 Level MBBS students may choose too (the rule is the programme's); the College may set `sessions_behind_max` to 0 to keep a
  programme on the University's session.
- The Bursary states the MBBS fee lines of a session before the University's where students stand in it (on the live copy C00061 lines
  exist for 2025/2026 only).

Tests: check.sql (V733 block); `StudySessionIT`.
