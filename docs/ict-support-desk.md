# The ICT Support Desk across the University: queues, posted agents, routing, transfer, office escalation (V328)

This is the final report the enhancement brief asked for. It is written against what the portal already had, which it
reuses: the ticketing system of V251/V252, the office register and grants (RBAC), the notification outbox, the audit
spine, the secure password reset. Nothing here is a second ticket system, a second user system, a second permission
model or a second finance or academic desk.

## 1. What existed

| Concern | Where | Since |
|---|---|---|
| Tickets | `helpdesk.ticket` (number `TICK-YYYY-NNNNN`, category, priority, requester, department, faculty, agent, escalation to a person, SLA fields), comments (internal or not), attachments, the written-once history `helpdesk.ticket_event` | V251/V252 |
| The desk | `helpdesk.is_agent` (ICT Support Agent, Director of ICT, administrators); every agent saw every ticket | V251 |
| Categories, SLA, settings | `helpdesk.category` (with the fields each asks for), `helpdesk.sla` by priority, `helpdesk.setting` | V251 |
| Screens | `/helpdesk` (queue, figures), `/helpdesk/tickets/[id]`, `/helpdesk/reports`, `/helpdesk/settings`; the requester's `/tickets`; the public `/track` | V251 |
| Offices | `ref.office` and `iam.office_assignment`; a token carries `OFFICE_<code>` authorities; `X-Active-Office` | V001+ |
| Notices, audit | `platform.queue_notice` through `NoticeRepository`; `audit.attach` | — |
| Password reset | `PasswordResetService.forgot` (a one-hour link to the account's email and phone; the same answer whether or not an account exists) | V058 |

What it could not do: there was one pool of agents with no scope, no notion of a queue, no routing, no way to hand a
ticket to the Bursary or the Examinations unit, no way for an office to answer, no Head of the desk distinct from the
Director, no waiting states, no critical priority, and nothing happened to the tickets of an agent who left.

## 2. What changed (V328)

### The Head of ICT Support Desk
A new office `helpdeskhead` (scope `platform`, the 38th on the register). It holds support authority only: every
ticket, assignment, transfer, escalation, the queues, the routing, the agents' postings, the categories and SLAs.
It cannot change a fee, a result, a registration or a refund. The Director of ICT and the administrators keep the same
reach (`HEADS` in the controller; `helpdesk.is_head` in the database).

### Queues
`helpdesk.queue`: code, name, description, the **office that decides** (`office_code` → `ref.office`, the escalation
office), active, order. Eleven seeded: ICT Support (Director of ICT), Bursary Support (Bursar), Academic Office Support
and Course Registration Support (Academic Office), Exams and Results Support (Exams & Records), Library Support
(Librarian), GST Support (Director, General Studies), Student Biodata Support (Registrar), Student Affairs Support (Dean
of Student Affairs), Accommodation Support (Housing), Security and ID Card Support (Chief Security Officer). A queue is
deactivated, never deleted.

### Postings
`helpdesk.agent_assignment`: a person on a queue within a scope (`GLOBAL`, `FACULTY`, `COLLEGE`, `DEPARTMENT`,
`OFFICE` with `scope_ref` on the register), primary or not, availability (`AVAILABLE`, `BUSY`, `AWAY`, `OFFLINE`,
`ON_LEAVE`), dates, who placed them and why. **Only a person who holds the ICT Support Agent office (or the Head's, or
the Director's) can be posted** (`HELPDESK_NOT_AN_AGENT`): support access comes from the office grant under Users &
Roles; a posting only says where and within what scope it is exercised. A CPO posted to the Faculty of Agriculture on
ICT Support sees and is routed that faculty's ICT tickets and nothing else.

### Routing
`helpdesk.routing_rule`: a category (optionally for one faculty or one department) to a queue, with a strategy and an
optional priority floor. The most specific active rule wins (department, then faculty, then the University; ICT
Support when none). Strategies: `FACULTY_AGENT_FIRST` (a posted faculty/college/department agent before a University-wide
one, then least loaded), `OFFICE_AGENT_FIRST`, `LEAST_LOADED`, `ROUND_ROBIN`, `MANUAL` (queued for the Head),
`QUEUE_ONLY`. Seeded: PAYMENT and NELFUND → Bursary; LOGIN, ACCOUNT, EMAIL, PORTAL, NETWORK, GENERAL, OTHER → ICT;
REGISTRATION → Course Registration; RESULTS, EXAMINATIONS → Exams and Results; GST → GST; LIBRARY → Library; HOSTEL →
Accommodation; IDCARD → Security and ID Card; BIODATA → Student Biodata. Six categories were added for the new queues
(GST, LIBRARY, HOSTEL, IDCARD, BIODATA, NELFUND), each with its fields.

`helpdesk.route(ticket)` runs on submission (and `helpdesk.transfer` after a transfer): the queue from the rule, then
`helpdesk.pick_agent` among `helpdesk.eligible_agents` — posted on the queue, active, available or busy, within dates,
scope covering the ticket's faculty/department, still holding the office. The ticket is assigned (event `ASSIGNED`,
"by the faculty agent first rule of the ICT Support queue") or left queued (event `QUEUED`), and the Head is told.

### Scope, enforced on the server
`helpdesk.can_view(person, ticket)`: a head sees all; an agent sees the tickets of the queues they are posted on within
their scope, and any ticket assigned or escalated to them; an agent the Head has never posted anywhere works the whole
desk as before V328 (so nothing is lost on upgrade); an agent whose every posting has ended sees only what is with
them. Every desk endpoint — the queue, the figures, the activity, the ticket, every act on it, every attachment — goes
through it (`requireVisible` → 403). The screens only reflect it.

### Transfer
`helpdesk.transfer(ticket, queue, by, reason)`: a reason is required; a resolved or closed ticket is not transferred;
the same ticket moves (its number unchanged, never a second ticket), loses its agent and office wait, returns to
`OPENED` if it was in hand, is routed again on the new queue; events `TRANSFERRED` (from "queue · agent" to queue) and
`ASSIGNED`/`QUEUED`. The requester is told it moved; the new agent (or the Head) is told.

### Escalation to an office
`helpdesk.escalate_to_office(ticket, office, by, reason)`: a policy or administrative decision goes **only** to the
queue's office; a technical fault to the Director of ICT; anything else is refused (`HELPDESK_ESCALATION_OFFICE`). The
ticket goes `WAITING_FOR_OFFICE` with `escalated_office` and `waiting_since`; the office's holders are told, the
requester is told it was referred. `helpdesk.office_answer(ticket, by, body, internal)`: only a holder of that office
(or a head) answers (`HELPDESK_NOT_THE_OFFICE`); the answer is a comment in the office's name — internal by default,
an instruction to the agent — the wait ends, the ticket returns to the agent (`IN_PROGRESS`) or the queue (`OPENED`);
event `OFFICE_ANSWERED`. The old escalation to a person (`helpdesk.escalate`) stays for the chain inside the desk.
The requester never sees `ESCALATED_TO_OFFICE` or `OFFICE_ANSWERED` on their history — only the status.

### Waiting on the requester
`WAITING_FOR_STUDENT` (named for the brief; it serves staff requesters too) is entered by the agent on a reason
(`HELPDESK_REASON_REQUIRED`), the requester is told what is needed, and their reply (`helpdesk.comment` as REQUESTER)
moves the ticket back to `IN_PROGRESS` by itself (event `STATUS_CHANGED`, "The requester replied"). The desk may also
resume by hand. Leaving `WAITING_FOR_OFFICE` by hand clears the office wait.

### No ticket is lost with a person
`helpdesk.sweep_inactive_agents()` (run hourly by `AutoCloser`, and at once when the Head edits a posting) returns to
its queue every open ticket held by a person who has left the University, no longer holds a support office, or whose
every posting is inactive, on leave or offline; event `RETURNED`; the Head is told once with the numbers.
`helpdesk.deactivate_agent(person, by, reason)` ends every posting and returns everything they hold;
`helpdesk.reassign_open(from, to, by, reason)` moves an agent's open tickets to another, on the record.

### Priority and SLA
`CRITICAL` joins LOW/NORMAL/HIGH/URGENT (SLA 1 h first response, 4 h resolution, editable under Settings); setting it
tells the Head and the Director. A routing rule may raise a category's suggested priority with its floor.

### Figures
`helpdesk.queue_workload()` (agents posted and available, open, unassigned, in progress, waiting on the requester and
on an office, overdue, critical, resolved this week) and `helpdesk.agent_workload(queue)` (open, in progress, waiting,
overdue, critical, resolved today and this week, average resolution). The stats add `waiting_student`,
`waiting_office`, `critical` and `byQueue`.

## 3. API (all under `/api/v1/helpdesk`)

| Endpoint | Who | What |
|---|---|---|
| `GET /tickets?…&queue=&office=&status=open\|waiting\|…&sort=queue` | the desk, within scope | the queue |
| `GET /stats?…&queue=`, `GET /activity` | the desk, within scope | the figures, the last acts |
| `GET /agents?ticket=` | the desk | agents with postings, availability, and against a ticket `eligible`/`posted` |
| `GET /queues`, `GET /workload?queue=` | the desk (an agent reads only their own load) | the queues' and agents' load |
| `GET /tickets/{id}` and every act | the desk, **403 outside scope** | as before |
| `POST /tickets/{id}/transfer` `{queue, reason}` | the desk | the same ticket to another queue |
| `POST /tickets/{id}/escalate-office` `{office, reason}` | the desk | to the queue's office or the Director |
| `POST /tickets/{id}/status` `{status: WAITING_FOR_STUDENT, reason}` / `IN_PROGRESS` | the desk | wait / resume |
| `POST /tickets/{id}/priority` `{priority: CRITICAL}` | the desk | critical |
| `POST /tickets/{id}/password-reset` | the desk | the portal's own reset for the requester's account; the desk sees no password; the requester is told on the ticket |
| `GET /office/tickets`, `GET /office/tickets/{id}` (+ attachments), `POST /office/tickets/{id}/answer` `{body, internal}` | a holder of the office the ticket waits on | the office's door |
| `GET/POST /admin/queues`, `PUT /admin/queues/{code}` | the Head, the Director | queues |
| `GET/POST /admin/routing`, `PUT /admin/routing/{id}` | the Head, the Director | routing rules |
| `GET/POST /admin/agents`, `PUT /admin/agents/{id}`, `POST /admin/agents/{person}/deactivate`, `POST /admin/agents/{person}/reassign` | the Head, the Director | postings |

Refusal codes: `HELPDESK_REASON_REQUIRED`, `HELPDESK_TRANSFER_SAME`, `HELPDESK_TRANSFER_SETTLED`,
`HELPDESK_QUEUE_UNKNOWN`, `HELPDESK_ESCALATION_OFFICE`, `HELPDESK_ESCALATE_SETTLED`, `HELPDESK_NOT_WITH_OFFICE`,
`HELPDESK_NOT_THE_OFFICE`, `HELPDESK_ANSWER_REQUIRED`, `HELPDESK_NOT_AN_AGENT`, `HELPDESK_SCOPE`,
`HELPDESK_SCOPE_UNKNOWN`, `HELPDESK_POSTED_ALREADY`, `HELPDESK_AVAILABILITY`, `HELPDESK_STRATEGY`,
`HELPDESK_QUEUE_CODE`, `HELPDESK_QUEUE_EXISTS`, `HELPDESK_OFFICE_UNKNOWN`, `HELPDESK_CATEGORY_UNKNOWN`.

## 4. Screens

- **ICT Support Desk** (`/helpdesk`): tiles now count In hand, Waiting (on the requester / on an office), Critical; a
  "The queues" panel (office that decides, available of posted agents, open, unassigned, waiting, overdue, critical);
  filters by queue and by waiting status; the rows show the queue and "With <office>". An agent sees only their scope.
- **The ticket** (`/helpdesk/tickets/[id]`): queue in the eyebrow; "With <office>" pill; Transfer to a Queue, Escalate
  to an Office (only the queue's office or the Director offered), Escalate to a Person, Wait for the Requester, Resume
  Work, Send Password Reset Link; the assign dialog lists first the agents the routing would choose ("Posted here",
  "Eligible"); the priority list includes Critical.
- **Support Agents, Queues & Routing** (`/helpdesk/agents`, menu `t/helpdeskagents`, for the Head, the Director and
  the administrators): Agents (postings with availability and End Posting; workload with Move Open and Take Off the
  Desk; who holds the agent office; Post an Agent), Queues (edit, new), Routing (rules, unrouted categories, new).
- **Support Escalations** (`/helpdesk/office`, menu `t/helpdeskoffice`, in the Me group of Bursar, Academic Office,
  Exams & Records, Librarian, GST, Registrar, Dean of Student Affairs, Housing, Security, Director of ICT): what waits
  on the office, what it answered; `/helpdesk/office/[id]` shows the agent's question first, the whole conversation,
  and the answer form (internal to the desk unless the office chooses to show it to the requester).
- **The requester** (`/tickets`, `/tickets/[id]`): the queue on the list; "The support desk needs something from you"
  with what was asked; "Referred to <office> for a decision"; the transfer on the history; never the desk's routing
  business or the office's internal answer.
- The Head of ICT Support Desk has its own menu (`helpdeskhead`); the office label is on `offices.ts`.

## 5. Security and audit
- Support access is never administrative authority: no endpoint here writes to finance, results, registration or the
  register; the office's answer is a comment, and the office acts on its own desk as always.
- Scope is enforced in the database and at every endpoint, never only on the screen; the Head, the Director and the
  administrators are the only ones who see everything; a student reaches only `/my/…`; an office reaches only the
  tickets that wait on it or that it answered.
- A posting is refused to anyone who does not hold the agent office; an unknown scope or office is refused.
- The password reset is the portal's own (`PasswordResetService.forgot`): a one-hour link to the account's email and
  phone; the API returns `{sent: true}` and nothing else; the act is on the ticket history in the agent's name.
- The three new tables are on the audit spine; the history stays written-once; every refusal names its code and remedy.

## 6. Tests
- `db/check.sql` property 176 (EXPECTED 176; the office register now 38): routing by faculty before the University,
  the Bursary queue, scope (`tfftft`), a transfer refused without a reason and moving the one ticket to the new
  queue's agent, escalation refused to the wrong office, answered only by the office and internally, the wait ended
  by the requester's reply, the sweep on leave, the deactivation, the critical SLA, the event chain.
- `SupportDeskIT` (3 tests): routing and 403 outside scope and the transfer; the office escalation end to end
  (wrong office 422, non-holder 403, the office's door, the internal answer hidden from the student, the wait and the
  reply, CRITICAL counted, the password reset recorded and nothing exposed); deactivation returning tickets, the Head
  told, a non-agent refused a posting, an agent refused the admin doors, a queue and a rule kept.
- `HelpdeskIT` (V251) unchanged and still green: an agent never posted anywhere works the whole desk.

The brief's thirty cases map onto these: routing (1–6, 23) property 176 and IT 1; scope (7–10, 25–28) property 176
and IT 1/3; transfer (11–13) IT 1; office escalation (14–18) IT 2; waiting (19–20) IT 2; inactive agents (21–22)
property 176 and IT 3; critical (24) IT 2; password reset (29) IT 2; audit (30) property 176's event chain.

## 7. Assumptions the University should confirm
- An agent the Head has not posted anywhere keeps working the whole desk, as before V328; posting them bounds them.
- The seeded queue → office mapping (above) and the category → queue rules; both are editable by the Head.
- A policy decision is escalated only to the queue's office; a technical fault only to the Director of ICT.
- The office's answer is internal to the desk unless the office chooses otherwise; the agent relays it.
- `WAITING_FOR_STUDENT` is the brief's name; it applies to a staff requester too.
- The critical SLA ships as 1 h / 4 h.
