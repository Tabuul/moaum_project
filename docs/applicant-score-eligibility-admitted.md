# The Post-UTME score and the programme eligibility are the admitted applicant's (21 October 2026, V608)

The request: hide **Programme eligibility** and the dashboard's **Your Post-UTME score has been released** note (the score, the
aggregate, *See your full result*) from the applicant until they are admitted; an applicant who is not admitted never sees them.
And only the applicants who sat the Post-UTME examination — the index programmes — see a score: a programme screened without the
examination has its aggregate computed from the O'Level result, and that aggregate is never shown to the applicant.

## 1. The rule, enforced in the API

| What | Before | Now |
|---|---|---|
| `GET /api/v1/applicant/me` → `result`, `scoreReleasedAt` | given as soon as the Academic Office released the scores | given only when **admitted** — the released decision is `OFFERED` *and* it is the applicant's to read (`decisionVisible`: Admission Status Checking paid and checked, or the admission under way, as `admissions.status_checking` says) — **and** the score is the Post-UTME examination's (`screening_source` CBT or EXAM). Otherwise both are `null`: nothing says a score exists, nor that scores were released |
| `GET /api/v1/applicant/me/eligibility` | `available` once the form was submitted | `available` only when admitted on the same test; before that `available=false` with the note "Programme eligibility is shown once you are offered admission" and nothing of the verdict, the reasons, the alternatives or the application |
| `POST …/me/eligibility/recalculate`, `POST …/me/eligibility/change` | open to any submitted applicant | refused with `ELIG_NOT_ADMITTED` (422) unless admitted |
| `canRequestChange` | the decision not yet released, no open request | the rule of `admissions.request_programme_change` as it stands: the decision not released, or an unsuccessful online screening with no change approved since — one open request at a time. For the admitted applicant, who alone reads it, that is the unsuccessful-screening case |
| The office's view (`forOffice`) | everything | unchanged: the Academic Office reads the score released or not, and the eligibility register as before |

The decision is read exactly as `ApplicantService.view` has read it since V295: `decision_released_at` set and
`admissions.status_checking(app).decision_visible`. A candidate admitted from the JAMB list (V270) is admitted on the same test.

The one database change, **V608**, restates `admissions.release_scores` with the words of its notice changed: every seated or scored
applicant is still told that the results are released, but the notice no longer says "Sign in to see your score and where you
stand" — it says the score is shown on the portal with an offer of admission, and the decision follows. The release, the count and
who is told are as they were.

## 2. The screens

- **Applicant → Overview**: the Post-UTME tile and the released-score note appear only when the API gives a result (admitted,
  examination score). Before the decision the tile says "Not released — Shown here with an offer of admission, once the scores are
  released" (or "After your screening"); once the decision is read with no result — not offered, waiting, or a programme screened
  without the examination — the tile is gone and nothing is said of a score. **Programme eligibility** is mounted only when the offer
  is read (`admitted(a)`: `decision === "OFFERED"`, which the API gives only when visible).
- **Applicant → Screening result** (`/applicant/score`): until then, "Post-UTME scores are shown to admitted candidates who sat the
  examination", with the Board's offer named as the moment; the full result as before once given.
- **Applicant → Admission Status**: the eligibility panel is no longer mounted there (every branch of that page is before the offer, or
  not offered); it stays on the Screening page after an unsuccessful online screening, where the admitted applicant may still ask
  for a listed programme (the Request Change button now appears there, since `canRequestChange` follows the engine's rule).

## 3. Consequences to know

- An applicant's own **request for a change of programme before the Board decides** is closed: the applicant cannot see the
  alternatives, so cannot ask. The Admissions Office keeps its own door (`POST …/eligibility/{app}/change`, with a reason code) to
  request a change on an applicant's behalf, and decides it as before; after an unsuccessful online screening the admitted applicant
  may still ask for a listed programme.
- For an admitted applicant the eligibility panel reads as a confirmation of the programme offered. Where the Board offered a place on
  another basis to an applicant the engine finds not eligible, the panel says so with the alternatives; that is the engine's reading,
  not a change to the offer.
- The Post-UTME **result-checking page** (`/post-utme/results`, V385) is untouched: it shows a released score to the verified candidate
  only while the Director of ICT's `POST_UTME_RESULT_CHECKING` window is open. If the University means no applicant to see a score
  before admission there either, the window is simply not opened.

## 4. Tests

- `ApplicantIT`: after the release the applicant's view has no result and no release date, and the notice says the score comes with an
  offer; with the offer read through Admission Status Checking, the CBT score and the release date.
- `AdmissionStatusCheckingIT`: a released CBT score on an admitted and a refused applicant — the refused never sees it; the admitted
  not before the check, and with it.
- `AdmissionEligibilityIT`: before the offer `available=false` and nothing of the verdict, the change and recalculate doors refused
  `ELIG_NOT_ADMITTED`, a released score still nothing; the Office's request on the applicant's behalf decided; admitted, the
  applicant's own view agrees, no change after the decision, and an aggregate computed from the O'Level result never shown; the
  doors test reads another's application only once admitted.
- `AdmissionLifecycleIT`: the accepted applicant whose screening was unsuccessful reads the panel and may ask for the change.
- `lib/applicant-score.test.ts`: the dashboard words; `check.sql` V608: the release notice.
