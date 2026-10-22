# The Post-UTME score and the Screening result wait for the admission decision; the programme eligibility is the admitted applicant's (21 October 2026, V608, V610 and V617)

Two requests on the same day. First: hide **Programme eligibility** and the dashboard's **Your Post-UTME score has been released**
note (the score, the aggregate, *See your full result*) until the applicant is admitted, and only for those who sat the Post-UTME
examination — the index programmes; a programme screened without the examination has its aggregate computed from the O'Level
result, and that aggregate is never shown (V608). Then, seeing the result: the scores are released to **every** applicant of an index
programme on the release, whatever the Board then decides; only the non-index programmes show nothing (V610). The eligibility
panel stays the admitted applicant's alone.

Two more the same afternoon. First, hide the **Screening result** screen (the aggregate as calculated, the UTME cut-off and whether
the applicant meets it, "Where you stand" on the merit list) from every applicant until their admission is decided (a6ad9bec, no
migration). Then, "hide the Post-UTME score on the overview too" (**V617**): the score and the aggregate wait for the decision as well.
The applicant now reads nothing of a Post-UTME score until a decision is theirs to read; a computed aggregate never.

## 1. The rules, enforced in the API

| What | Rule |
|---|---|
| `GET /api/v1/applicant/me` → `result` (score, aggregate, weights, cut-off, merit position), `scoreReleasedAt` | given when the Academic Office has released the scores, the result's source is the Post-UTME examination's (`screening_source` CBT or EXAM, as `admissions.screening_component` reads the record) **and** the admission is decided — a decision the applicant may read (`decisionVisible` and a decision: OFFERED, WAITING or NOT_OFFERED; V617). Otherwise both are `null` (left out of the JSON): before the decision, for a computed aggregate (OLEVEL) or none, and nothing says scores were released |
| `GET /api/v1/applicant/me/eligibility` | `available` only when **admitted** — the released decision is `OFFERED` *and* it is the applicant's to read (`decisionVisible`: Admission Status Checking paid and checked, or the admission under way, as `admissions.status_checking` says); before that `available=false` with the note "Programme eligibility is shown once you are offered admission" and nothing of the verdict, the reasons, the alternatives or the application |
| `POST …/me/eligibility/recalculate`, `POST …/me/eligibility/change` | refused with `ELIG_NOT_ADMITTED` (422) unless admitted |
| `canRequestChange` | the rule of `admissions.request_programme_change` as it stands: the decision not released, or an unsuccessful online screening with no change approved since — one open request at a time. For the admitted applicant, who alone reads it, that is the unsuccessful-screening case |
| The office's view (`forOffice`) | unchanged: the Academic Office reads the score released or not, and the eligibility register as before |

The decision is read exactly as `ApplicantService.view` has read it since V295. A candidate admitted from the JAMB list (V270) is
admitted on the same test.

The database changes are the words of one notice. **V608** restated `admissions.release_scores` to say the score is shown with an
offer of admission; **V610** restates it again with the words V059 gave it — "Sign in to see your score and where you stand" — since
the sitter reads the score from the release; **V617** restates it once more: "The post-UTME screening results for … have been released
to the Admissions Board. Your score and where you stand are shown on the portal with your admission decision, read through Admission
Status Checking" (subject "Post-UTME screening results released"; the SMS the same in short), inviting nobody to sign in and see a
score. The release, the count and who is told (every seated or scored application, which a computed one never is) are as they were.

## 2. The screens

- **Applicant → Overview**: the Post-UTME tile and the note "Your screening result" (the score, the aggregate, *See your full result*)
  appear only when the API gives a result — released, an examination score, with the decision read (`putmeOnDashboard`). Before the
  decision there is no tile and nothing is said of a score; once a decision is read with no result — a programme screened without the
  examination, or none released — nothing either. The progress rail's "Screening score released" now reads "To the Admissions Board;
  shown to you with the admission decision". **Programme eligibility** is mounted only when the offer is read (`admitted(a)`:
  `decision === "OFFERED"`, which the API gives only when visible).
- **Applicant → Screening result** (`/applicant/score`): held until the admission is decided (`screeningResultOpen(a)` in
  `lib/applicant-score`: the API gives the decision only when it is the applicant's to read). Until then the menu item is not shown
  (`"when": "decided"` in `lib/menus.ts`, the flag set by `app/applicant/load.ts`) and the page, reached by its address, says "Your
  screening result is shown once your admission is decided" with a link to Admission Status. The Screening Slip's "See your screening
  result" appears only then, and its note says the score and the result are shown with the decision. Once decided:
  "Scores are released when every batch has been screened" until the result is given, with the words that a programme screened
  without the examination has no score to show; the full result as before.
- **Applicant → Admission Status**: the eligibility panel is no longer mounted there (every branch of that page is before the offer, or
  not offered); it stays on the Screening page after an unsuccessful online screening, where the admitted applicant may still ask
  for a listed programme (the Request Change button appears there, since `canRequestChange` follows the engine's rule).

## 3. Consequences to know

- An applicant's own **request for a change of programme before the Board decides** is closed: the applicant cannot see the
  alternatives, so cannot ask. The Admissions Office keeps its own door (`POST …/eligibility/{app}/change`, with a reason code) to
  request a change on an applicant's behalf, and decides it as before; after an unsuccessful online screening the admitted applicant
  may still ask for a listed programme.
- For an admitted applicant the eligibility panel reads as a confirmation of the programme offered. Where the Board offered a place on
  another basis to an applicant the engine finds not eligible, the panel says so with the alternatives; that is the engine's reading,
  not a change to the offer.
- "Sat the examination" is read from the record: a score of the examination stands (entered, uploaded or imported from the CBT
  engine). A programme named in `admissions.screening_exam_programme` is screened by the written examination (EXAM); every other
  programme with a score on record is CBT; a programme with no such score is computed (OLEVEL) or has no component (NONE).
- The Post-UTME **result-checking page** (`/post-utme/results`, V385) is untouched: it shows a released score to the verified candidate
  only while the Director of ICT's `POST_UTME_RESULT_CHECKING` window is open.

## 4. Tests

- `ApplicantIT`: after the release, with no decision yet, the applicant's view has no result and no release date, and the notice
  says the score comes with the decision (no "Sign in to see"); with the offer read the CBT score is there, with the cut-off and the
  merit position as `admissions.screening_result` has them.
- `AdmissionStatusCheckingIT`: a released CBT score on an admitted and a refused applicant — neither reads it before the check; each
  reads it with the decision checked.
- `AdmissionEligibilityIT`: before the offer `available=false` and nothing of the verdict, the change and recalculate doors refused
  `ELIG_NOT_ADMITTED`, a released score nothing for a programme screened without the examination; the Office's request on the
  applicant's behalf decided; admitted, the applicant's own view agrees, no change after the decision, and the computed aggregate still
  never shown; the doors test reads another's application only once admitted.
- `AdmissionLifecycleIT`: the accepted applicant whose screening was unsuccessful reads the panel and may ask for the change.
- `lib/applicant-score.test.ts`: the Overview's score only with a decision (offered, waiting list or not offered), nothing before it;
  `check.sql` V608/V610/V617: the release notice's words (no new block; EXPECTED unchanged).

## 5. The PUTME score card for index courses (22 October 2026, V632)

The University asked for a **PUTME score** card on the Post-UTME applicant's Overview, between **UTME score** and **Stage**, for
applicants who applied for **index courses** only. It also asked that the card show the score as soon as the scores are released,
with a waiting note before that.

- **Index course:** a programme the Academic Office states sits the Post-UTME examination for the session
  (`admissions.screening_exam_programme`, read by `admissions.screened_by_exam` against the programme as JAMB recorded it). For
  2026/2027 these are LL.B (Law), MBBS, Doctor of Pharmacy, Nursing Sciences, Radiography and Radiation Science, and Medical
  Laboratory Science. The Office's applicant list calls the same test `index_programme`.
- **`GET /api/v1/applicant/me` → `putme`:** given to an index-course applicant only, as `{released, score, releasedAt}`.
  - `score` and `releasedAt` come once the Academic Office has released the scores, before any admission decision.
  - Every other applicant gets no `putme`.
  - `result` (the aggregate, the cut-off, the merit position) and the Screening result screen still wait for the decision (V617).
- **The card** (`putmeCard`, `lib/applicant-score.ts`) shows one of three things:
  - **Awaited**, "Shown here once the Academic Office releases the scores", before the release;
  - the score, "of 100 · the Post-UTME examination", once released;
  - **—**, "No Post-UTME score is recorded for you", when released with no score.
  - Without a card the Overview keeps its four cards. The "Your screening result" note under the cards still comes with the
    decision.
- **The release notice** (`admissions.release_scores`, restated from V617):
  - An index-course applicant is told: "Your Post-UTME score is now on your portal Overview".
  - Every other applicant is told, as before, that the score is shown with the admission decision.

**Tests:**
- `check.sql` V632 (EXPECTED 459): one index-course and one other applicant released together, each told once and in their own
  words.
- `PutmeIT.anIndexCourseApplicantReadsThePutmeScoreFromTheRelease`: the card waits, then shows the score before any decision, and
  `result` still waits. The applicant to another programme has no card, and each is told the right thing.
- `ApplicantIT`: an applicant to a programme that is not an index course has no `putme`.
- `lib/applicant-score.test.ts`: the card's three states, and no card without `putme`.
