# The Quick Operational Manual (V387)

Every signed-in person has a short manual of their own on the dashboard they already use: what to click, what to
enter, what to confirm and what result to expect — nothing more. It is built on the portal as it is, not beside it.

## What it reuses

| Need | Reused |
|---|---|
| Who the reader is | the one sign-in and the token's acting office (`OFFICE_…`); the sidebar the portal names beside it (a postgraduate's `pgstudent`, a JUPEB applicant's) |
| Finer grants | a support posting's capabilities (`helpdesk.agent_capabilities`, V334): a procedure bound to a capability is read only by a posting that carries it |
| Menu and page names | `frontend/src/lib/menus.ts` and the Shell's route map: a step names a menu item by its id (`{menu:t/matriculation-manage}`) and the portal shows the item's **current** label as a link to its page |
| Print and PDF | the central document system (V320): `printDocument` for the browser, `PdfDocument` for the download — the University's header, the edition, page numbers |
| Audit | `audit.attach` on `manual.procedure` and `manual.edition`; versions and readings kept beside the spine |

## The reader

- **Where**: the `Manual` button at the top of every dashboard (next to *Search records*) opens `/manual`; on a page that has
  procedures of its own a `How to…` list sits beside it (the server's answer for the route and office, nothing a page decides).
- **What**: the published procedures bound to the reader's keys — the office, its sidebar, and *everyone* — grouped by category
  (Dashboard, Account, Students, Payments, Admissions, Academics, Results, Exams, Support, Reports, Settings). A procedure is a
  title, a one-line purpose, numbered steps (a control in `backticks`, a menu item as its current label and link) and the expected result.
- **Search manual**: procedure, menu, action or keyword, over the resolved labels. Categories filter.
- `Print` and `Download PDF` (role, office, edition, date, contents, page numbers). `?p=<key>` opens one procedure.
- Readings (open, search, procedure, print, PDF) are recorded on `manual.view` (audit-exempt, written once).

Who sees what is the database's: `manual.procedures_for(keys, capabilities)`. A Bursary officer never reads the Director of
ICT's procedures; an ICT Support Agent without `MANAGE_REGISTRATION` on a posting does not read *Add a course to a student's registration*.

## Manual Management

`/manual/admin` (Super Administrator, System Administrator, Director of ICT; menu *Administration → Manual Management*):

- `New procedure` / `Edit`: title, key, purpose, category, the offices that may perform it, a capability where one gates it, the
  menu item it lives on, the contextual page, the steps (`Insert menu item` writes a reference), the expected result, the order.
  The screen names any reference the portal does not carry for those offices before it is saved. A new procedure is a **draft**.
- `Publish`, `Unpublish`, `Archive` (with a reason), `Restore`. An edit of a published procedure keeps it published and keeps the
  previous version (`manual.procedure_version`); an archived one is restored before it is edited.
- `Preview as…` any office or sidebar. `↑`/`↓` order within a category.
- The **edition** (`manual.edition`): 1.0 at birth; a minor step on every publication, unpublication, archiving, restoring and
  edit of a published procedure; `Release a new edition` steps the major. The dashboard always shows the current one — nobody
  downloads anything to stay current.

## The first edition

223 procedures seeded by V387 from the portal as wired (the sidebars, the screens' own control labels, `docs/manual`): everyone
(sign in, reset, change password, tickets, notifications, search), students and postgraduate students, applicants, lecturers,
Heads of Department, Deans, exams officers (programme and faculty), Faculty Officers, Exams & Records, the Academic Office, the
Registrar and Deputy Registrar, the Bursar, the Director of ICT, ICT Support Agents (capability-bound), the Head of ICT Support
Desk, the Super and System Administrators, GST and EPS, JUPEB, the CCE, the Postgraduate School and Housing / Student Affairs.

The build checks the seed: `frontend/src/lib/manual.test.ts` reads V387 and refuses a `{menu:…}` that is not on the sidebar of
every office the procedure is bound to, or that has no page. `db/check.sql` holds the V387 property (filtering, capabilities,
draft/publish/edit/archive/restore, the refusals, the edition, readings and audit). `ManualIT` exercises the API.

## API

`GET /api/v1/manual[?menu=&q=]` · `GET /api/v1/manual/context?route=` · `POST /api/v1/manual/views` — any signed-in office.
`GET /api/v1/manual/admin[?q=&state=]` · `GET /admin/preview?office=&menu=&capabilities=` · `POST /admin/procedures` ·
`PUT /admin/procedures/{id}` · `POST /admin/procedures/{id}/{PUBLISH|UNPUBLISH|ARCHIVE|RESTORE}` · `GET /admin/procedures/{id}/versions` ·
`PUT /admin/order` · `POST /admin/edition` — Super Administrator, System Administrator, Director of ICT.
