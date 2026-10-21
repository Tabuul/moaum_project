# The Post-UTME score is the sitter's; the programme eligibility is the admitted applicant's (21 October 2026, V608 and V610)

Two requests on the same day. First: hide **Programme eligibility** and the dashboard's **Your Post-UTME score has been released**
note (the score, the aggregate, *See your full result*) until the applicant is admitted, and only for those who sat the Post-UTME
examination — the index programmes; a programme screened without the examination has its aggregate computed from the O'Level
result, and that aggregate is never shown (V608). Then, seeing the result: the scores are released to **every** applicant of an index
programme on the release, whatever the Board then decides; only the non-index programmes show nothing (V610). The eligibility
panel stays the admitted applicant's alone.

## 1. The rules, enforced in the API

| What | Rule |
|---|---|
| `GET /api/v1/applicant/me` → `result`, `scoreReleasedAt` | given when the Academic Office has released the scores **and** the result's source is the Post-UTME examination's (`screening_source` CBT or EXAM, as `admissions.screening_component` reads the record). Otherwise both are `null`: a computed aggregate (OLEVEL) or none is never shown, and nothing says scores were released. The decision plays no part |
| `GET /api/v1/applicant/me/eligibility` | `available` only when **admitted** — the released decision is `OFFERED` *and* it is the applicant's to read (`decisionVisible`: Admission Status Checking paid and checked, or the admission under way, as `admissions.status_checking` says); before that `available=false` with the note "Programme eligibility is shown once you are offered admission" and nothing of the verdict, the reasons, the alternatives or the application |
| `POST …/me/eligibility/recalculate`, `POST …/me/eligibility/change` | refused with `ELIG_NOT_ADMITTED` (422) unless admitted |
| `canRequestChange` | the rule of `admissions.request_programme_change` as it stands: the decision not released, or an unsuccessful online screening with no change approved since — one open request at a time. For the admitted applicant, who alone reads it, that is the unsuccessful-screening case |
| The office's view (`forOffice`) | unchanged: the Academic Office reads the score released or not, and the eligibility register as before |

The decision is read exactly as `ApplicantService.view` has read it since V295. A candidate admitted from the JAMB list (V270) is
admitted on the same test.

The database changes are the words of one notice. **V608** restated `admissions.release_scores` to say the score is shown with an
offer of admission; **V610** restates it again with the words V059 gave it — "Sign in to see your score and where you stand" — since
the sitter reads the score from the release. The release, the count and who is told (every seated or scored application, which a
computed one never is) are as they were.

## 2. The screens

- **Applicant → Overview**: the Post-UTME tile and the released-score note appear when the API gives a result (released, an
  examination score). Before the release the tile says "Not released — Shown here once the Academic Office releases the scores" (or
  "After your screening"); once a decision is read with no result — a programme screened without the examination, or none released —
  the tile is gone and nothing is said of a score. **Programme eligibility** is mounted only when the offer is read (`admitted(a)`:
  `decision === "OFFERED"`, which the API gives only when visible).
- **Applicant → Screening result** (`/applicant/score`): "Scores are released when every batch has been screened" until the result is
  given, with the words that a programme screened without the examination has no score to show; the full result as before.
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

- `ApplicantIT`: after the release the applicant's view has the CBT score and the release date with no decision yet, and the notice
  invites them to sign in; the score stays with the offer read.
- `AdmissionStatusCheckingIT`: a released CBT score on an admitted and a refused applicant — both read it from the release, before and
  after the check.
- `AdmissionEligibilityIT`: before the offer `available=false` and nothing of the verdict, the change and recalculate doors refused
  `ELIG_NOT_ADMITTED`, a released score nothing for a programme screened without the examination; the Office's request on the
  applicant's behalf decided; admitted, the applicant's own view agrees, no change after the decision, and the computed aggregate still
  never shown; the doors test reads another's application only once admitted.
- `AdmissionLifecycleIT`: the accepted applicant whose screening was unsuccessful reads the panel and may ask for the change.
- `lib/applicant-score.test.ts`: the dashboard words; `check.sql` V608/V610: the release notice.
