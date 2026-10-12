-- ═══════════════════════════════════════
-- V411 — the Quick Operational Manual brought up to what the portal now does, as a new edition
--
--   Since the first edition (V387) the portal gained:
--
--     · the course allocation desk of the Director of ICT and the ICT Support Desk (V408) — every class of the University,
--       allocation through the department's own engine, reassignment with a reason, co-lecturers, second examiners, the
--       history, conflicts and the bulk upload; an ICT Support Agent works it only within the faculty or department of a
--       posting that carries the capability, which the Head of the Support Desk grants on the posting;
--     · the Head of Department's allocation screen reading the same checks and history, and asking why a lead is replaced
--       or a co-lecturer removed;
--     · every payment classified by programme type, purpose, source module and responsible office (V409): the Bursary's
--       report by programme type and purpose, the Bursary's classification settings, and the Payments Report of the offices
--       that own a purpose (JUPEB, the Centre, GST, EPS, Housing);
--     · the general-ledger sync posted in batches with what remains counted (V410);
--     · JUPEB's old-portal template and passport photographs matched by App No.
--
--   New procedures are seeded as V387 seeds them (published at birth; an existing key is left alone). A procedure of the
--   first edition is revised here only while it is still as V387 seeded it (seeded, version 1, not archived): an edit an
--   administrator has made in Manual Management is theirs and is kept. A revision goes through manual.save_procedure, so
--   the earlier wording is kept as a version. The edition then takes its major step.
--
--   Every {menu:…} below is checked against the portal's menus by frontend/src/lib/manual.test.ts.
-- ═══════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'ict', true),
       set_config('moaum.reason', 'V411: the Quick Operational Manual, a new edition', true);

-- a procedure of the first edition revised only while it is still as V387 seeded it
CREATE FUNCTION pg_temp.manual_revise(p_slug text, p_title text, p_purpose text, p_steps text[], p_expected text)
RETURNS void
LANGUAGE plpgsql AS $$
DECLARE p manual.procedure;
BEGIN
    SELECT * INTO p FROM manual.procedure WHERE slug = p_slug;
    IF p.id IS NULL OR NOT p.seeded OR p.version <> 1 OR p.state = 'ARCHIVED' THEN
        RAISE NOTICE 'V411: % is left as Manual Management has it', p_slug;
        RETURN;
    END IF;
    PERFORM manual.save_procedure(p.id, p.slug, p_title, p_purpose, p.category, p.offices, p.capabilities, p.menu_id, p.route,
                                  p_steps, p_expected, p.sort_order, '00000000-0000-0000-0000-000000000000', 'ict',
                                  'V411: brought up to what the portal now does');
END $$;

-- ── 1 · the course allocation desk: the Director of ICT, the Head of the Support Desk, Admin, Super ─────────────────
SELECT manual.seed('alloc-desk-allocate', 'Allocate a lecturer to a course', 'ACADEMICS', ARRAY['ict', 'helpdeskhead', 'admin', 'super']::text[], 't/allocation', NULL,
    'Give a class its lead lecturer from the University''s allocation desk, through the same checks the department''s allocation runs.',
    ARRAY['Open {menu:t/allocation}.',
          'Choose the `Session` and `Semester`; narrow by `Faculty`, `Department`, `Programme`, `Level` or `Search`.',
          'On the `Courses` tab click the `Unallocated` status; on the class click `Allocate`.',
          'Leave `Allocate as` on Lead lecturer and pick the `Lecturer` (search by name, staff number, e-mail or department).',
          'Read the checks shown: a firm one (course not offered this semester, lecturer not active or not teaching staff) stops the allocation; a heavy load only warns.',
          'Enter a `Reason` (optional for a first allocation) and, when it answers a ticket, its number in `Support ticket`.',
          'Click `Review`, read the summary, then click `Allocate course`.',
          'A course that is not offered is not created here: ask the department or the Academic Office to offer it.'],
    'The class shows its lecturer, the lecturer is told by e-mail, and the history records who allocated it, when and why.', '{}'::text[], 40);
SELECT manual.seed('alloc-desk-reassign', 'Reassign a course, add a co-lecturer or name a second examiner', 'ACADEMICS', ARRAY['ict', 'helpdeskhead', 'admin', 'super']::text[], 't/allocation', NULL,
    'Change who teaches or examines a class without losing who did before.',
    ARRAY['Open {menu:t/allocation}; on the `Courses` tab click `Allocated` (or `Several`); on the class click `View`.',
          'Set `Allocate as`: `Lead lecturer (reassign)`, `Co-lecturer` or `Second examiner`; pick the `Lecturer` and read the checks.',
          'For a reassignment enter the `Reason for reassignment`: it is required.',
          'Add the `Support ticket` when the change answers one.',
          'Click `Review`, then `Reassign course`, `Add co-lecturer` or `Name second examiner`.',
          'To take a co-lecturer off, click `Remove` beside the name, enter the `Reason` and click `Remove allocation`.'],
    'The new lecturer and the one replaced are both told; the history keeps the earlier allocation with its reason — nothing is deleted.', '{}'::text[], 41);
SELECT manual.seed('alloc-desk-lists', 'Read allocations, lecturers'' loads, the history and conflicts', 'ACADEMICS', ARRAY['ict', 'helpdeskhead', 'admin', 'super']::text[], 't/allocation', NULL,
    'See which classes still need a lecturer, who carries what, and every change made.',
    ARRAY['Open {menu:t/allocation}; the figures at the top count courses, allocated, unallocated, several lecturers and conflicts — click one to list them.',
          'On `Courses` use the status `All`, `Unallocated`, `Allocated`, `Several` or `Conflicts`; click `Export (Excel)`.',
          'Click `Lecturers` for each lecturer''s classes and units this semester; click `Export (Excel)`.',
          'Click `History` for every allocation, reassignment and removal with its reason, who made it, from which desk and the ticket; click `Export (Excel)`.',
          'Click `Conflicts` for the classes that need a look; click `View` on one to put it right.'],
    'Every list is the University''s (or your reach''s) for the session and semester chosen.', '{}'::text[], 42);
SELECT manual.seed('alloc-desk-bulk', 'Allocate many courses from a spreadsheet', 'ACADEMICS', ARRAY['ict', 'helpdeskhead', 'admin', 'super']::text[], 't/allocation', NULL,
    'Allocate a semester''s classes at once, each row held to the same checks.',
    ARRAY['Open {menu:t/allocation}; choose the `Session` and `Semester`; click the `Bulk allocate` tab.',
          'Click `Download template` and fill one row per class and lecturer.',
          'Click `Upload Excel / CSV` and choose the file; click `Validate`.',
          'Read the rows; click `Download error report` for the rows refused, correct them and click `Re-validate`.',
          'Click `Import` for the valid records, then `Done`.',
          'The `Import history` keeps each file; click `Error report` on one to read its refusals again.'],
    'Each valid row is allocated as if done by hand; a refused row changes nothing.', '{}'::text[], 43);

-- ── 2 · an ICT Support Agent, within the posting''s faculty or department and capability ────────────────────────────
SELECT manual.seed('cpo-allocation-view', 'Read the course allocations of your posting', 'SUPPORT', ARRAY['ictagent']::text[], 't/allocation', NULL,
    'Answer "who teaches this course?" for the faculty or department you are posted to.',
    ARRAY['Open {menu:t/allocation}: the classes listed are those of your posting''s faculty or department only.',
          'Choose the `Session` and `Semester`; use `Search` for a course code or title.',
          'Click `View` on a class for its lecturer, co-lecturers, second examiner, checks and history.',
          'Click `Lecturers` or `History` for loads and changes; `Export (Excel)` for the office.'],
    'You see what your posting reaches; a class outside it is not listed and cannot be opened.', ARRAY['VIEW_ALLOCATIONS']::text[], 20);
SELECT manual.seed('cpo-allocate', 'Allocate or reassign a course on a ticket', 'SUPPORT', ARRAY['ictagent']::text[], 't/allocation', NULL,
    'Resolve an allocation ticket within your posting, through the department''s own checks.',
    ARRAY['Open {menu:t/allocation}; find the class with `Search` or the `Unallocated` status; click `Allocate` (or `View`).',
          'Choose `Allocate as` and the `Lecturer`; read the checks — a firm one cannot be overridden from the desk.',
          'Enter the `Reason` (required to reassign) and the ticket number in `Support ticket`.',
          'Click `Review`, then `Allocate course`, `Reassign course`, `Add co-lecturer` or `Name second examiner`.',
          'Open {menu:t/helpdesk}; on the ticket click `Send Update` to tell the requester what was done.',
          'A class outside your posting, or a course not yet offered, is not yours to change: click `Escalate to an Office` on the ticket.'],
    'The allocation carries your reason and the ticket; the ticket''s timeline and the history both show it.', ARRAY['ALLOCATE_COURSES']::text[], 21);
SELECT manual.seed('cpo-allocation-remove', 'Remove a co-lecturer', 'SUPPORT', ARRAY['ictagent']::text[], 't/allocation', NULL,
    'Take a co-lecturer off a class within your posting when the department asks.',
    ARRAY['Open {menu:t/allocation}; on the class click `View`.',
          'Click `Remove` beside the co-lecturer.',
          'Enter the `Reason` and the `Support ticket`; click `Remove allocation`.'],
    'The co-lecturer is told; the history keeps that they taught the class.', ARRAY['REMOVE_ALLOCATIONS']::text[], 22);
SELECT manual.seed('cpo-allocation-bulk', 'Upload an allocation spreadsheet', 'SUPPORT', ARRAY['ictagent']::text[], 't/allocation', NULL,
    'Allocate many classes of your posting''s faculty or department from a file the department sends.',
    ARRAY['Open {menu:t/allocation}; choose the `Session` and `Semester`; click `Bulk allocate`.',
          'Click `Download template`; fill one row per class and lecturer.',
          'Click `Upload Excel / CSV`; click `Validate`; a row outside your posting is refused.',
          'Click `Download error report` for the refusals; correct and `Re-validate`; click `Import`.'],
    'Each valid row within your posting is allocated; the import history keeps the file.', ARRAY['BULK_ALLOCATE']::text[], 23);

-- ── 3 · the Head of the Support Desk grants the allocation capabilities on a posting ─────────────────────────────────
SELECT manual.seed('hd-allocation-postings', 'Let an agent allocate courses', 'SUPPORT', ARRAY['helpdeskhead']::text[], 't/helpdeskagents', NULL,
    'Grant an ICT Support Agent the course allocation capabilities for one faculty or department.',
    ARRAY['Open {menu:t/helpdeskagents}; click `Post an Agent` (or `Post` beside the person).',
          'Choose the `Agent` and the `Queue`; set the `Scope` to the faculty or department the agent may allocate in — a capability reaches no further than its posting.',
          'Tick `View course allocations` and, as the work needs, `Allocate and reassign lecturers`, `Remove a co-lecturer`, `Bulk course allocation`.',
          'Click `Post the Agent`.',
          'To change what an agent may do, click `End Posting` and post them again with the capabilities they should hold.'],
    'The agent sees Course Allocation for that scope only; every act carries their name, reason and ticket.', '{}'::text[], 14);

-- ── 4 · payments: the Bursary''s classification and the offices that own a purpose ────────────────────────────────
SELECT manual.seed('bursar-classification', 'State programme types, purposes and who owns a payment', 'SETTINGS', ARRAY['bursar', 'admin', 'super']::text[], 't/finanalytics', NULL,
    'Keep the classification every payment is reported under: programme type, purpose, source module and responsible office.',
    ARRAY['Open {menu:t/finanalytics}; go down to `Payment classification`.',
          'On `Programme types` click `Edit` (or fill a new one); list the `Entry modes of this type` and `Programme categories of this type`; click `State the programme type`.',
          'A type the University does not run yet (Preliminary, Remedial, Foundation) waits with no entry mode or category until its first programme.',
          'On `Purposes` set the `Income account` the purpose posts to and `What a confirmed payment entitles`; click `State the purpose`.',
          'On `Module and office` choose the `Purpose`, a `Programme type` (or none for every type), the `Source module` and the `Responsible office`; click `State the rule`. The most particular rule wins.',
          'Under the payment categories click `Edit` and set the category''s `Purpose`; click `State the category`.'],
    'Reports regroup at once; no payment, amount or reference changes, and every statement is on the audit trail.', '{}'::text[], 32);
SELECT manual.seed('office-payments-report', 'Read your office''s payments', 'REPORTS', ARRAY['jupeb', 'cce', 'gst', 'eps', 'housing']::text[], 't/finanalytics', NULL,
    'See what was paid for your office''s purposes on the University''s one payment ledger.',
    ARRAY['Open {menu:t/finanalytics}: the report holds only the payments your office owns, whatever the filters.',
          'Set `Session of the payment`, or `From` and `To`; narrow by `Programme type`, `Purpose`, `Source module` or `Semester`.',
          'Read the totals and `Revenue by programme type and purpose`; the other tables group by programme type, purpose and source module.',
          'Click `Transactions` on a row for the payments behind it — reference, payer, gateway reference and ledger status; `Search` by name, number or reference.',
          'Click `Excel` or `PDF` on a table, or `Export Excel` / `Export PDF` on the transactions.',
          'Fee amounts and payment records are the Bursary''s: for a wrong amount or a payment not showing, refer the payer to the Bursary.'],
    'The figures are the Bursary''s for the same purposes; nothing on the report changes a payment.', '{}'::text[], 90);

-- ── 5 · the procedures of the first edition the portal has outgrown ─────────────────────────────────────────────────
SELECT pg_temp.manual_revise('hod-allocate', 'Allocate teaching',
    'Assign lecturers to the semester''s classes, with the checks the allocation runs and a reason for every replacement.',
    ARRAY['Open {menu:r/allocate}; choose the session and semester.',
          'On a class click `Assign` (or `Manage`); use `Search a lecturer` and click `Choose` beside the lecturer.',
          'Read the checks under the name: a firm one (course not offered, lecturer not active or not teaching staff) stops the save; a heavy load only warns — click `Save as an overload` if the department means it.',
          'Pick the `Second examiner` if any; click `Save the lead & second examiner`.',
          'To replace a lead, choose the new lecturer, enter the `Reason for replacing` and click `Reassign the lead`.',
          'Use `Add a co-lecturer` and click `Add co-lecturer`; to take one off, click `Remove` beside the name, enter the reason and click `Remove co-lecturer`.',
          'Read `Allocation history` for every change, its reason, who made it and from which desk; click `Download Excel`.',
          'For many classes click `Download template`, fill it, `Upload Excel / CSV`, `Validate`, then `Import`.'],
    'The lecturer sees the class under My Courses; every allocation, replacement and removal stays in the history with its reason.');
SELECT pg_temp.manual_revise('bursar-analytics', 'Read the payments report by programme type and purpose',
    'See collections by programme type, purpose, source module, office, category, channel and period — "Sandwich school fees", "JUPEB applications".',
    ARRAY['Open {menu:t/finanalytics}; set `Session of the payment`, `Payment types` and `Trend by`.',
          'Narrow by `Programme type`, `Purpose`, `Source module`, `Responsible office` or `Semester`.',
          'Read `Revenue by programme type and purpose`, then the tables by programme type, purpose, source module and responsible office.',
          'Click `Transactions` on a row for the payments behind it; click `Export Excel` or `Export PDF` there.',
          'Click `Excel` or `PDF` on any table.',
          'Open {menu:t/collegepayments} for the College of Health Sciences.'],
    'Figures read from the one ledger; each payment counted once, under its programme type and purpose.');
SELECT pg_temp.manual_revise('bursar-books', 'Post the ledger and reconcile it',
    'Keep the books: post what the ledger has not yet posted, post journals by hand, and reconcile against the bank.',
    ARRAY['Open {menu:t/accounts}; when it says transactions are not yet on the books, click `Post them now` (or `Sync`).',
          'The sync posts 2,000 at a time, oldest first, and shows how many are left until none remain; if it stops, click it again to carry on — nothing is posted twice.',
          'Click `New journal`; `Add a line` per `Account`; click `Post the journal` (or `Post the reversal`).',
          'Open {menu:t/ledger}; filter `From`; click `Export the journal`.',
          'Open {menu:t/reconcile}; mark rows `Matched` or `Flag` them.'],
    'Every confirmed payment, paid refund and paid voucher is on the books once; the books balance and flagged rows are followed up.');
SELECT pg_temp.manual_revise('jupeb-idcards-import', 'Print identity cards and import old-portal students and passports',
    'Issue cards and bring over the old portal''s students, their logins and their passport photographs.',
    ARRAY['Open {menu:jupeb/idcards}; `Choose all with a photograph`; `Print the chosen`; `Replace the card` with `Why`.',
          'Open {menu:jupeb/import}; click `Download the template` for the columns the upload reads, and fill it from the old portal''s export.',
          'Click `Choose the export (Excel or CSV)`; read the rows; click `Upload … students and create their logins`.',
          'Click `Download login details (Excel)` for the sign-ins created; hand each student their own.',
          'Under `Passport photographs from the old portal`, name each photograph by the App No (JUP-2024-0012.jpg for JUP/2024/0012), JPEG or PNG, up to 5 MB.',
          'Click `Choose the photographs`; tick `Replace a passport a student already has` only to replace one.',
          'Click `Photographs not kept (Excel)` for the photographs no old-portal student matched.'],
    'Students hold cards and sign in; each matched photograph is the student''s verified passport, kept with their documents.');

-- ── 6 · the new edition ─────────────────────────────────────────────────────────────────────────────────────────────
SELECT manual.bump_edition('00000000-0000-0000-0000-000000000000', 'ict',
    'V411: the course allocation desk, the Head of Department''s checks and reasons, the payments report by programme type and purpose, the Bursary''s classification, the ledger sync in batches, JUPEB''s template and passports',
    true);

COMMIT;
