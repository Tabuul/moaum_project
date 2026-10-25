# Collaboration and partnership management (V658)

The University's master prompt "UNIVERSITY COLLABORATION & PARTNERSHIP MANAGEMENT SYSTEM" (25 October 2026). Organisations at home
and abroad propose a collaboration on a public form. The University acknowledges it, screens, routes and assigns it, reviews it with
the offices concerned, asks for more where needed, checks it, decides, prepares and executes an agreement, and follows the
partnership through to its outcomes and its close. Everything sits on one record per proposal, moves through one workflow, and is
kept on the audit spine.

The University's answers of 25 October 2026:

- **Who owns it.** A new office, `linkages` ("Director, Linkages & Partnerships"), owns, screens and routes every proposal. It has
  configurable desks: Linkages & Partnerships (general), Research & Innovation, International Relations, Industry Liaison,
  Advancement & Development, Community & Government Engagement. The existing offices review what they are asked to. A second new
  office, `legal` ("University Legal Officer"), reviews agreements and due diligence.
- **Who approves.** The Vice-Chancellor approves or declines, both for development and for an agreement before it is signed. The DVC
  may act for the VC.
- **References.** Proposals are `PTN/YYYY/NNNNNN` (`PTN/2026/000125`); agreements are `PTN-AGR/YYYY/NNNNNN`.

## The public form

`/partnerships/collaboration` needs no account. It is linked from the sign-in page ("Collaborate with the University"). The page says
what the form is for and what it is not for: not student admissions, job applications, procurement bids, complaints, or private
requests. It says what happens next, when the University aims to acknowledge (`acknowledge_days`), and that submitting creates no
commitment.

It has eight steps:

1. Applicant details
2. Existing University connection
3. Partnership proposal
4. Funding & resources
5. International, legal & compliance
6. Attachments
7. Declarations & consent
8. Review & submit

How the form behaves:

- **Conditional questions.** A question appears only when an earlier answer calls for it: "Other" organisation type, a follow-up's
  previous reference, the contact's details, the countries involved, sensitive data, conflict details.
- **Limits.** Text has character counters within the limits in the settings. The faculty and department are chosen from the
  register.
- **Checks and errors.** Every step is checked in the browser before moving on. An error summary at the top links to each field.
  The server checks the whole enquiry again (`partnership.problems`) before submission and decides.
- **Drafts.** "Save and continue later" keeps a draft at a private link (`#d=<token>` on the form). Drafts are kept for `draft_days`.
- **Attachments.** PDF, DOCX, XLSX and PPTX only, at most `max_files` files of up to `max_file_mb` MB each.
  - The server checks the content, not just the name. A PDF must start `%PDF-`. An Office file must be a ZIP holding the parts of
    its kind.
  - A macro-enabled file (`vbaProject.bin`) is refused, and so are executables and anything else.
  - No malware scanning service is wired to the portal. These checks are what stands in its place.
- **Declarations.** The five declarations are never pre-ticked. Marketing consent is optional and separate.
- **Review.** The review step has Edit on every section.
- **Submission.**
  - It is idempotent: the same draft submitted again answers the same reference.
  - The same title from the same email within a day is refused (`PTN_DUPLICATE`).
  - A honeypot field turns robots away.
  - The doors are rate-limited per connection (`Throttle` `PARTNERSHIP_FORM`, `PARTNERSHIP_LINK`, `PARTNERSHIP_STATUS`, over 15
    minutes).
- **After submission.**
  - The confirmation shows the reference.
  - The applicant is emailed an acknowledgement (`PARTNERSHIP_RECEIVED`) with the private status link and the privacy policy.
  - The routed desk's officers are told.

**The applicant's status page** is `/partnerships/status/<token>`. It shows where the enquiry stands, in words for the applicant, and
the steps shown to them. It holds the messages from the University and the applicant's replies. When information has been requested,
the applicant answers the open request there and uploads the documents asked for. A lost link can be asked for again with the
reference and the email (`POST /public/partnerships/link`). The new link replaces the old one, and the reply never says whether the
reference exists.

**What the University reads from the answers.** These are flags for review, never legal conclusions (`partnership.flags_of`):

- **Flags.** International, personal data, sensitive data, ethics, each high-risk activity, funding, a formal agreement, IP, NDA,
  data sharing, a conflict of interest.
- **Compliance review.** Required when there is a high-risk activity, sensitive data, ethics approval or personal data.
- **Risk level.** Low, medium or high.

## Routing and the workflow

**Routing.** A submission is routed by the first active rule, in priority order, whose stated conditions all match. A rule can
state the category, the category group, international or local, the organisation type, and the funding status. When no rule
matches, the proposal goes to the general desk. A desk's lead takes a proposal routed to it as owner. The Linkages office edits the
categories, desks, desk officers and rules in Settings.

**Statuses.** Received, Initial screening, Awaiting information, Routed, Assigned, Under review, Due diligence, Meeting proposed,
Under development, Pending approval, Approved for development, Agreement review, Agreement executed, Implementation, Active,
Declined, Closed, Cancelled.

**Actions** (`partnership.act`). Each is checked against the acting office's grants, what it may see, and the status it moves from.
Each is kept on the timeline. The applicant is told where it concerns them.

- **Start screening, Accept for review.** Acceptance needs an owner (`PTN_OWNER_REQUIRED`).
- **Route** to a desk, with a reason.
- **Assign owner.** An officer of the Linkages office or of one of its desks. The owner is told.
- **Request information.** A question, the documents asked for, and a deadline (`info_days` when none is given). One request is
  open at a time. The applicant's answer puts the proposal back where it was.
- **Start due diligence.** Opens the checklist and asks the Legal Officer to review.
  - The checklist (configurable): organisation identity, registration / accreditation, reputation, funding, legal, data
    protection, research ethics, conflict of interest, security, international compliance, financial risk, intellectual property,
    contractual requirements.
  - Each check is Pending, Satisfactory, Concern (with a note) or Not applicable.
- **Meeting proposed, Under development.**
- **Submit for approval.** Refused while a check is pending (`PTN_DD_OPEN`). Refused when compliance review is required and due
  diligence never ran (`PTN_DD_REQUIRED`). The Vice-Chancellor is told.
- **Approve, Decline.**
  - Approval and a decline at Pending approval are the VC's (or the DVC's).
  - The Linkages office declines before that stage.
  - A decline needs a reason of 10 characters. It may carry a courteous message to the applicant, separate from the internal reason.
- **Start implementation, Activate, Close, Cancel.** Close and Cancel need a reason. An active partnership cannot stand with an
  agreement still being prepared (`PTN_AGREEMENT_OPEN`).

**Due dates.** Each stage sets the proposal's due date in working days from the settings (screening, review, complex review for
compliance or high risk, a request). The desk counts what is past its due date as overdue.

**Reviewers.** The Linkages office asks an office to review: a Dean for a faculty, a Head of Department for a department, the
Registrar, the Bursar, the DVC, the PG School, ICT, Student Affairs or the Academic Office. It can also name a person holding that
office. A reviewer may be allowed to read the confidential conflict-of-interest disclosure.

A reviewing office sees only the proposals it is asked to review, within its own faculty or department. Another faculty's Dean does
not see them. The reviewer gives a recommendation with a comment: Support, Support with conditions, Do not support, or Need more
information. The owner is told. A recommendation informs the decision; it is never the decision.

**Notes and messages.**

- An internal note never leaves the University. A confidential note is only for those who may read the disclosure.
- A message to the applicant is emailed (`PARTNERSHIP_MESSAGE`) and shown on their status page. The applicant's replies come back to
  the same thread.

## Agreements

An agreement is prepared once the VC has approved the partnership for development (`partnership.agreement_create`). Its type is one
of: MOU, MOA, research, student exchange, NDA, data sharing, IP/licensing, or other.

1. **Draft → Legal review.** The Legal Officer is told.
2. **Legal review → Cleared or Returned.** Only the Legal Officer clears or returns it, with a note. Cleared, it awaits approval.
3. **Approval → Signing.** The VC or the DVC approves.
4. **Signing → Executed.** It is executed only with the signed copy attached, and the dates signed and effective. The expiry and
   renewal review dates are optional. The applicant is told.
5. **Executed → Terminated**, or **in preparation → Withdrawn**, each with a reason.

The dates of an executed agreement are kept up to date with a reason. An agreement is never renewed by itself.

`PartnershipJobs` runs each morning at 06:20 Lagos time:

- It marks an agreement expired once its expiry date has passed.
- It tells the owner and the Linkages office as an agreement enters the alert window (`expiry_alert_days`), at 30 days, and on
  expiry, once each.
- It purges unsent drafts older than `draft_days`.

## The partnership under way

- **Activities, deliverables and reports.** Each has a lead, a due date and a status.
- **Outcomes.** Each has a kind from a configurable list (research project, grant, publication, student exchange, staff exchange,
  internship, training, consultancy, technology transfer, joint programme, community project, equipment support, other), with a
  quantity, an amount and its currency.

## The desk

`/partnerships` is on the menus of the Linkages office (its home), the Legal Officer (its home), the VC, the DVC, the Deans, the
Heads of Department, the Registrar, the Deputy Registrar, the Bursar, the PG School, ICT, Student Affairs, the Academic Office,
Internal Audit, Deputy Audit and the Super Administrator.

- **Dashboard.** Tiles for total, new, under review, awaiting information, due diligence, pending approval, agreement review, active,
  declined, closed, overdue, compliance review, unassigned, my assignments, reviews asked of my office, and expiring agreements. Each
  tile opens its list.
- **Proposals.** Filtered and paged on the server: search, status, group, category, faculty, department, country, funding,
  international or local, compliance, owner, desk, and the dates received.
- **A proposal's page** (`/partnerships/<id>`):
  - where it stands, its flags, and the actions the office may take;
  - the answers;
  - reviews and notes;
  - the applicant thread and requests;
  - due diligence;
  - documents (each opening kept on the timeline);
  - agreements;
  - activities and outcomes;
  - the timeline.
  "Correct the record" changes only what is changed, with a reason, and never the applicant's declarations.
- **Record a proposal.** For one that came by letter, email or a meeting. It is routed like any other.
- **Reports.** The same filters plus organisation type.
  - On screen: the totals; by status, category group, country, faculty, department, organisation type and funding; budget totals
    by currency; and the flags.
  - Excel (`GET /partnerships/report/workbook`), ten sheets: Summary, Partnership List, Faculty Summary, Department Summary, Country
    Summary, Category Summary, Funding Summary, Compliance Summary, Active Partnerships, Agreements.
  - PDF: landscape, under the University's header.
  - Each export is written to the export log.
- **Settings.**
  - The form open or closed.
  - The response times in working days.
  - The text and file limits.
  - How long drafts are kept, and the expiry alert window.
  - The contact email and phone.
  - The categories, desks with their leads and officers, and routing rules.

## Who may do what (`partnership.grant`)

| Office | May |
|---|---|
| `linkages` (and `super`) | everything but approval: view all and the confidential disclosure, record, correct, screen, route, assign, review, request information, documents, due diligence, decline, agreements, close, reports, export, settings. `super` also approves |
| `vc`, `dvc` | view all and the confidential disclosure, review, documents, approve, decline, reports, export |
| `legal` | review, documents (read and add), due diligence, agreements (clears or returns at legal review) — on the proposals it is asked to review |
| `dean`, `hod`, `registrar`, `dregistrar`, `bursar`, `pgschool`, `ict`, `dsa`, `academic` | review and documents, on the proposals they are asked to review (a Dean or Head within their faculty or department) |
| `audit`, `deputyaudit` | view all and documents, reports, export |

The API checks the grant (`@PreAuthorize` and `partnership.require`). The database holds every list, figure and record to what the
acting office may see (`partnership.visible`). A proposal outside the office's reach reads as not permitted, and its id typed into
the address shows nothing of it.

## The notices

Twenty templates (`PARTNERSHIP_RECEIVED`, `_LINK`, `_SUBMITTED`, `_ROUTED`, `_ASSIGNED`, `_INFORMATION_REQUESTED`,
`_INFORMATION_RECEIVED`, `_MESSAGE`, `_REVIEW_STARTED`, `_REVIEW_REQUESTED`, `_REVIEW_RECEIVED`, `_DUE_DILIGENCE_REQUIRED`,
`_APPROVAL_REQUIRED`, `_APPROVED`, `_DECLINED`, `_AGREEMENT_REQUIRED`, `_AGREEMENT_EXECUTED`, `_ACTIVE`, `_EXPIRING`, `_CLOSED`) go
through the notice pipeline. The applicant receives them by email (`platform.notify`), and staff in the portal (`platform.tell_person`).
Each is sent once per event.

## The API

- **Public** (`/api/v1/public/partnerships`, no session):
  - `GET /options`;
  - `POST /drafts`; `GET` and `PUT /drafts/{token}`; `POST /drafts/{token}/check`;
  - `POST` and `DELETE /drafts/{token}/attachments`; `POST /drafts/{token}/submit`;
  - `GET /status/{token}`; `POST /status/{token}/reply`; `POST /status/{token}/attachments`;
  - `POST /link`.
- **The desk** (`/api/v1/partnerships`):
  - `GET /desk`; `GET` (the list); `GET /{id}`;
  - `POST /{id}/act`; `POST /{id}/reviewers`; `DELETE /reviewers/{id}`; `POST /{id}/review`; `POST /{id}/notes`;
  - `PUT /{id}/due-diligence/{item}`;
  - `POST /{id}/agreements`; `POST /agreements/{id}/act`;
  - `POST /{id}/attachments`; `GET /{id}/attachments/{att}`;
  - `POST /{id}/activities`; `PUT /{id}/activities/{aid}`; `POST /{id}/outcomes`;
  - `POST /record`; `PUT /{id}`;
  - `GET` and `PUT /settings`; `PUT /categories/{code}`; `PUT /desks/{code}`; `PUT /desks/{code}/officers/{person}`; `POST /rules`;
  - `GET /report`; `GET /report/workbook`.

## Limits and caveats

- **File size.** A file travels as text (a data URL) through the portal's front door, which reads at most 10 MB of a request.
  `max_file_mb` is therefore 5 by default and 7 at most.
- **Owners.** A desk officer who does not hold the `linkages` office sees a proposal they own only when their own office may view
  partnerships. Make desk officers holders of the `linkages` office.
- **No advice.** The portal gives no legal, financial or compliance advice. Every flag and checklist item is a prompt for the
  University's own review.

## Checks

- `check.sql` V658: a research proposal with compliance flags and a confidential conflict, and an international student exchange,
  taken from draft to an active partnership and a decline, with the refusals along the way. The block undoes its writes.
- `PartnershipIT`: the public form, the desk, reviewers, due diligence, the approval, agreements, reports and the workbook through
  the API.
- `lib/partnerships.test.ts`.
