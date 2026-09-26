# Group G — Student services, hostel, ICT help desk, health, credentials/documents and public verification

Read-only audit of the MOAUM portal as it stands at commit 8c2b6fa. All paths are relative to `C:\Users\ajene\Documents\moaumpp`. `api/` = `api/src/main/java/ng/edu/moaum/portal/`, `app/` = `frontend/src/app/`, `lib/` = `frontend/src/lib/`. Line numbers are those of the files on disk.

Modules covered, in order:

1. Hostel accommodation (V030 + V261)
2. ICT Support Desk — tickets (V251)
3. Help & Requests — service requests to an office (V036 + V040)
4. University Health Services — the clinic (V032)
5. Digital academic documents, the transcript queue, the certificate register and identity cards (V005, V013, V027, V262)
6. The public verification surface (`/verify/**`, `/track`, `/documents/d/{token}`)

---

# 1. Hostel accommodation  (API module: `hostel`; schema: `hostel`; pages: `app/hostel/**`, `app/student/hostel/**`, `app/verify/hostel/[ref]`)

## 1.1 Purpose
The hostel module carries a student's whole stay in University accommodation on the record: the inventory of halls, blocks, rooms and beds (a bed is a row, so a bed under maintenance is a bed nobody is given); the session's application window with its fee, hold time, eligibility rules and allocation method; the application with preferences and a roommate request; the desk's review; the allocation run (ballot from a published seed, first-come, level, faculty, programme, special-needs, or manual seating); the hold that lapses unpaid and passes the bed to the next name on the waiting list; the fee paid through the University's ordinary payment reference; acceptance under the hostel rules; the porter's check-in; transfers; maintenance requests; the checkout inspection, damage charges and the hostel clearance that releases the bed and signs the HOSTEL unit of the graduation clearance. Every step is written to a write-once trail and the student is told by email and SMS at each turn. V030 wrote the fair part (ballot, hold, fee); V261 added everything else (`db/V261__hostel_lifecycle.sql:1-22`).

## 1.2 Users and roles
- **Actors (write)**: `OFFICE = hasAnyAuthority('OFFICE_services','OFFICE_housing','OFFICE_registrar','OFFICE_admin','OFFICE_super')` — Support Services, the Deputy Registrar (Housing, Welfare and Passages), the Registrar, System Administrator, Super Administrator (`api/hostel/HostelLifecycleController.java:42`, `api/hostel/HostelController.java:73`).
- **Readers**: `READERS` adds bursar, dregistrar, academic, ict, audit, vc, dvc (`HostelLifecycleController.java:43`).
- **Student**: `hasAuthority('OFFICE_student')` for everything under `/api/v1/me/hostel…` (`HostelLifecycleController.java:44`).
- The screens repeat the officer list client-side as `OFFICERS = ["services","housing","registrar","admin","super"]` to hide buttons (`app/hostel/HostelDashboard.tsx:17`, `app/hostel/applications/Applications.tsx:18`, `app/hostel/allocations/[id]/Allocation.tsx:16`); the server guard is what enforces it.
- No department/faculty scope is applied: every officer sees every hall.
- Notices to "the desk" go to every person currently holding `housing` or `services` (`V261:344-354`).

## 1.3 Navigation
| Office | Menu group → item | URL |
|---|---|---|
| housing | Students → Hostel Dashboard | `/hostel` |
| housing | Students → Application Window & Rules | `/hostel/window` |
| housing | Students → Hostel Inventory | `/hostel/inventory` |
| housing | Students → Applications & Waitlist | `/hostel/applications` |
| housing | Students → Occupancy & Check-in | `/hostel/occupancy` |
| housing | Students → Checkout & Clearance | `/hostel/clearance` |
| services | Students → Hostel Accommodation | `/hostel` (the sub-screens are reached from the dashboard's buttons, not the menu) |
| student | Services → Hostel | `/student/hostel` |
| (no menu) | — | `/hostel/allocations/{id}`, `/hostel/students/{id}` (reached from the desk screens), `/student/hostel/letter`, `/student/hostel/clearance` (PDF routes), `/verify/hostel/{ref}` (public) |

Registrar, admin and super hold the write guard but have no hostel menu item; they can open `/hostel` by URL.

## 1.4 Screens

### 1.4.1 Accommodation desk — `/hostel` (`app/hostel/page.tsx`, `HostelDashboard.tsx`)
Opens on the session asked for (`?session=YYYY/YYYY`), else the CURRENT session, else the intake session (`page.tsx:11-16`). Calls `GET /api/v1/hostel/sessions/{s}/{y}/dashboard`.
- **PageHead** "Accommodation" with occupancy figure; actions: Session select, "Window & Rules", "Inventory", "Applications", "Occupancy", "Checkout & Clearance" (`HostelDashboard.tsx:61-69`).
- **Window notice**: "Window for {session}" with the state pill (Draft/Open/Closed/Allocated); shows fee, hold hours, open/close dates, method, "review required", "allocation made". For officers: **"Generate Allocation"** (hidden once drawn or when method is MANUAL; disabled when no free bed or nobody approved) and **"Lapse expired holds"** (`:71-79`). If no window: "No window is stated for {session}" with "State the window" button (`:81`).
- **Tiles** (12, each a link): Total beds, Occupied, Reserved, Available, Under maintenance, Students accommodated, Applications, Allocated, Waitlisted, Checked out, Pending clearance, Open maintenance (`:84-97`).
- **"Waiting at this desk"** table: Applications to review, Students to check in, Transfer requests, Checkout requests, Clearances in progress, Maintenance open, each with "Open" (`:99-110`).
- Charts: Beds by status (donut), Applications by status (donut), Occupancy by hostel / by block (bars), Occupancy by room type, Students accommodated by faculty, Applications by hostel preferred, Applications by faculty and level (`:112-146`).
- **"Occupancy by hostel, in figures"** table with **Excel** / **PDF** (`brandedXlsx("Hostel Occupancy by Hall", …)`, serial `docSerial("HST")`) (`:148-153`).
- **Modal "Generate the allocation"**: preview text ("Before allocation: N eligible applicant(s)… The run seats N and waitlists N. Priority categories go first…"); field **Published seed** (required for BALLOT, ≥ 6 chars); button "Confirm and allocate" → `POST /hostel/sessions/{s}/{y}/draw` `{seed}`; toast "{allocated} allocated · {unsuccessful} waitlisted · {priority} by priority" (`:37-45, 155-159`).
- **Modal "Lapse expired holds"** → `POST /hostel/sessions/{s}/{y}/lapse`; toast "{n} hold(s) lapsed and passed on" (`:46-53, 160-163`).

### 1.4.2 Application window & rules — `/hostel/window` (`app/hostel/window/Window.tsx`)
Non-officers see "You are reading this window" and disabled fields (`:50`). After the draw: "The allocation has been made — the method and the seed are on the record; the dates and the rules may still be changed" (`:51`).
- **Panel "Fee, dates and stay"**: Accommodation fee (₦) *required*, Hold window (hours) 1–720 (hint "A bed is held this long for payment"), Maximum applications (blank = no limit), Applications open (date), Applications close (date), Window state (Draft — not visible / Open / Closed / Allocated), Stay from, Stay to, Allocation method (7 options, `lib/hostel.ts:122-125`); checkboxes "The desk reviews each application before allocation", "Keep a waiting list; a lapsed bed passes to the next name" (`:56-70`).
- **Panel "Who is eligible"**: Student status checkboxes (ADMITTED, ACTIVE, PROBATION, DEFERRED, SUSPENDED, DORMANT; default ACTIVE, ADMITTED, PROBATION), Levels 100–900 (none = every level), Faculties (none = every faculty), Kinds of hall open this session, "Course registration for the session submitted", "No unsettled hostel damage charge or uncleared stay" (`:73-98`).
- **Panel "Hostel rules and regulations"**: textarea (max 20000 chars); header shows "Version N — a change makes a new version the student acknowledges again" (`:100-104`).
- Buttons: "Save the window"/"Create the window" (disabled without a fee), "Save and open applications" (when not OPEN), "Save and close applications" (when OPEN) → `PUT /hostel/sessions/{s}/{y}/window` (`:32-43, 106-112`). Toast "Window saved" / "Window opened|closed".

### 1.4.3 Hostel inventory — `/hostel/inventory` (`app/hostel/inventory/Inventory.tsx`)
Loads `GET /api/v1/hostel/inventory?session=`. Hostel filter select; officer buttons **Add a hostel**, **Add a block**, **Add a room**, **Generate rooms**; **Excel**, **PDF** ("Hostel Inventory", room rows), **Bed list (Excel)** (reads occupancy with size=5000) (`:73-80`). Tiles Beds/Occupied/Reserved/Available/Maintenance.
- **Hostels** table (name, code, type, gender, campus, blocks, rooms, state) with "Rooms", "Edit", "Close"/"Reopen" (`:94-102`).
- **Blocks and floors** table with "Edit", "Close"/"Reopen" (`:104-114`).
- **Rooms** table (S/N, hostel, block, floor, room — a link to the occupancy screen's room modal — type, capacity, occupied, available, maintenance, state) with "Edit", "Facilities", "Close"/"Reopen" (`:116-125`).
- **Assets** table (tag, kind, hostel, room, qty, condition, acquired, value, state) with "Add an asset"/"Edit" (`:127-134`).
- Modals and fields:
  - *A new hostel / Hostel {code}*: Code (required, 2–8 letters/digits, upper-cased), Type (hall kinds), Name (required), Gender (Mixed/Female/Male), Campus, Location, Description → `PUT /hostel/halls-full` (`:136-148`). Toast "Hostel saved".
  - *A block*: Hostel, Block code (required, ≤12), Name (default "Block X"), Floors 1–30 → `PUT /hostel/blocks` (`:149-158`).
  - *A room* ("Its beds are numbered from the capacity when it is saved"): Hostel, Block (required, datalist), Floor (0 = ground), Room number (required), Capacity (beds) 1–12 (required), Room type ("From the capacity" default), Gender restriction ("As the hostel"), State (Available/Maintenance/Closed/Reserved), Note → `PUT /hostel/rooms-full`; toast "Room saved; beds numbered" (`:159-173`).
  - *Generate rooms*: Hostel, Block (required), Floor, Number prefix (e.g. "A-"), From number, To number, Beds per room, Room type → `POST /hostel/rooms/generate`; at most 500 in a run (`:174-187`; server rule `HostelLifecycleController.java:345`).
  - *An asset*: Asset tag (required), Asset type (required), Hostel, Room ("Not in a room"), Quantity, Condition (NEW…DISPOSED), Date acquired, Value (₦), Note → `PUT /hostel/assets` (`:188-202`).
  - *Close/Reopen {label}*: for a room a State select (Maintenance/Closed/Reserved), Reason (required when closing) → `POST /hostel/close?session=`; afterwards a red notice "{n} occupant(s) are affected by the closure" listing each student with a link to their allocation ("transfer them from their allocation page and tell them") (`:48-52, 88-92, 203-209`).
  - *Facilities of room B-101*: a quantity per facility (0 removes) → `PUT /hostel/rooms/{id}/facilities` (`:210-215`).

### 1.4.4 Applications & waitlist — `/hostel/applications` (`app/hostel/applications/Applications.tsx`)
Server-side filters in the query string: Standing (Everyone / Pending review / Approved, unallocated / Unallocated / Allocated / Payment pending / Confirmed / Waiting list / Lapsed / Rejected / Withdrawn), Faculty, Department, Programme, Level, Search (name, ID, application number, programme) (`:96-106`; server predicates `HostelLifecycleController.java:488-496`). With `state=WAITLISTED` the title becomes "Waiting list" and the first column is the draw **Position** (`:86, 113`).
- Row: checkbox (officers), S/N, Application/Position, Student (number, level, sex), Programme, Preference (hall, room type, block, priority category pill and note, special need, roommate), Eligibility pill ("Eligible"/"Not eligible" + reason), Standing pill ("Under review", "Correction asked", "Approved — awaiting allocation", or the APP_STATE label), Allocation (reference link, place, ALLOC_STATE pill, "hold to …"), actions **Approve**, **Allocate**, **Reject**, **Correction**, **Withdraw**, **History** (`:110-130`).
- Bulk: "Approve N", "Waitlist N", "Reject N" on the picked rows → `POST …/applications/review-bulk` (`:88, 45-55`).
- **Download Excel / Download PDF** ("Hostel Applications", 17 columns, S/N first) (`:41-43, 89-90`).
- Modals: *review* (Reason required for REJECTED/CORRECTION — client message "Say why."), *Allocate {name}* (Free bed select loaded from `GET …/free-beds?sex=`, Reason required; "Every check the allocation run makes is made here…") → `POST …/applications/{id}/allocate`; toast "Allocated · {reference}"; *Withdraw {ref}* → `POST …/applications/{id}/withdraw` (`:135-151`).
- Empty state: "No application matches. Widen the filters." (`:131`).

### 1.4.5 Occupancy & check-in — `/hostel/occupancy` (`app/hostel/occupancy/Occupancy.tsx`)
Views: **Beds** (bed board), **Students**, **To check in** (CONFIRMED/ACCEPTED), **Checkout requested**; filters Hostel, Block, Status (occupancy states plus HELD/CONFIRMED/ACCEPTED/CHECKED_IN), Faculty, Department, Programme, Level, Gender, Search (`:64-87`; server `HostelLifecycleController.java:578-613`). Excel/PDF ("Hostel Occupancy — Students" or "Hostel Bed Board"). Bed rows show hostel, block, floor, room (opens a **room modal** with facilities, assets, each bed and its occupant, open maintenance, previous occupants), bed, status, student, allocation pill and "Open"; student rows end with **"Check in"** (primary when CONFIRMED/ACCEPTED) or "Open", both leading to the allocation page (`:90-112`). Empty: "There are currently no beds matching these filters." / "Nobody matches these filters."

### 1.4.6 One allocation — `/hostel/allocations/{id}` (`app/hostel/allocations/[id]/Allocation.tsx`)
Header: student name + ALLOC_STATE pill; description with number, programme, level, sex, and the placing. Action buttons (officers): **Check in** (CONFIRMED/ACCEPTED), **Transfer** (any live state), **Checkout inspection** (CHECKED_IN, no clearance yet), **Raise a damage charge** (CHECKED_IN), **Cancel** (live, not CHECKED_IN), **Accommodation history** (`:60-67`). Notices: "Held for payment until …" (HELD), "Paid; the student has not yet accepted under the rules" (CONFIRMED with rules), "Checkout requested for …" with **Inspect the room**, "A transfer request waits" with **Approve and move** / **Reject**, "This stay ended: …" / "Moved here from …" (`:69-73`).
Panels: The stay (passport photograph from `/api/bff/api/v1/student/students/{id}/passport`, hostel, block/floor, room, bed, basis, allocated, fee, accepted with rules version, checked in/out, stay, student status, priority category, special need), Roommates, Inspections, Damage charges (with **Waive** via `window.prompt("Reason for the waiver")`), Hostel clearance {ref} (each requirement with **Clear / Hold / Waive / N/A**; **Complete clearance** enabled only when no item is PENDING; **Reopen** when NOT_CLEARED; or "No clearance yet — Start clearance without inspection"), Transfer requests, Trail (`:75-126`).
Modals: *Check in* (Condition of room and assets Good/Fair/Damaged, Remarks) → `POST /hostel/allocations/{id}/checkin`; *Transfer* (Free bed, Reason required) → `…/transfer` then navigates to the new allocation; *Cancel allocation* (Reason required); *Checkout inspection* (condition, cleanliness Clean/Acceptable/Dirty, Keys returned, Access card returned, Damages found, Remarks) → `…/inspect`, toast "Inspection recorded; clearance opened"; *Damage assessment and charge* (Asset select, Damage required, Estimated repair cost, Replacement cost, Charge to the student required — "A charge above zero becomes a payment reference on the student's fees page… Zero records the damage without a charge") → `…/charge`; *requirement* (Remarks required for NOT_CLEARED/WAIVED); *transfer decision* (Bed to move to for APPROVED, Reason for REJECTED) → `POST /hostel/transfers/{id}` (`:128-177`).

### 1.4.7 Checkout & clearance — `/hostel/clearance` (`app/hostel/clearance/Clearances.tsx`)
Tabs: **Clearances (n)** (filter Status Every/Pending/Cleared/Not cleared, search; columns reference, student, hostel/room, bed, status, outstanding items, charges due, checkout date, cleared date; "Clear"/"Open"), **Checkout requests (n)** ("Inspect"), **Transfer requests (n)** ("Decide"/"Open"), **Maintenance (n)** (priority, issue, room, raised by, assigned to, status; **Update** modal: State Raised/Assigned/Fixed/Closed, Priority, Assigned to, Note to the student → `POST /hostel/maintenance/{id}/update`). Excel/PDF per tab ("Hostel Clearance", "Hostel Checkout Requests", "Hostel Transfer Requests") (`:38-46, 58-103`). Empty: "No clearance record for {session}… A clearance starts at the checkout inspection." / "Nobody has asked to check out." / "No transfer request." / "Nothing raised."

### 1.4.8 Student accommodation history — `/hostel/students/{id}` (`app/hostel/students/[id]/page.tsx`)
Read-only: the student, "Accommodation history" (session, application, hostel, room, bed, allocated, checked in/out, status, clearance), "Damage charges", "Trail"; link "Student record" (`:25-44`). Calls `GET /api/v1/hostel/students/{id}/history`.

### 1.4.9 Student — `/student/hostel` (`app/student/hostel/Hostel.tsx`)
Loads `GET /api/v1/me/hostel/full?session=`. Session select. One **status notice** chosen by state (`:84-120`): not open ("Accommodation for {session} is not open yet"); checked in ("You are checked in — {place}" with **Allocation letter (PDF)**, **Request checkout**, **Request a transfer**); ACCEPTED ("Allocation accepted — check in at the porter's lodge", letter); CONFIRMED ("Fee confirmed — accept your allocation" with **Accept allocation** (opens the rules modal when rules exist) and **Decline**); HELD ("A bed is held for you — N hours to pay" with **Pay ₦… now** and **Decline**); CHECKED_OUT/CLEARED ("Checked out and cleared" with **Clearance certificate (PDF)**); LAPSED; UNSUCCESSFUL ("Waiting list — position N"); REJECTED; APPLIED ("Applied — under review" / "Applied — allocation not yet made" / correction asked, with **Withdraw**); closed; not eligible ("You are not eligible to apply this session" + reason); eligible ("Apply for a bed — ₦… for the session").
- After **Pay**: `POST /me/hostel/fee-reference` → notice "Pay ₦X against {reference}" with link to Fees & payments (`:43-46, 122-126`). A damage charge shows "A damage charge of ₦X stands against you" (`:127`).
- **Steps**: Applied → Allocated → Fee paid → Accepted → Checked in → Checkout → Cleared (`:129-134`).
- **Panel "Apply for accommodation"** (only while the window is open and no application stands): Hall preferred (with free/total beds per hall), Room type preferred, Block preferred (≤12, upper-cased), Priority category (`CATEGORIES`: No priority — the ballot / Disability / Medical condition / First year / Final year / University sports / Other), "What the category rests on" (required when a category is chosen), Special or medical accommodation need, Preferred roommate (matriculation number), Roommate note; "Submit application" → `POST /me/hostel/apply-full` (`:136-164`). Success toast "Hostel application submitted successfully."
- **My allocation** panel (reference, session, hall, block/floor, room, bed, fee, basis, stay, check-in; "Generate the payment reference" while HELD; letter link otherwise) and **Roommates** (`:166-189`).
- **Maintenance and complaints**: table of requests; form What kind of fault (`MAINT_CATS`), Urgency (Low/Normal/High/Urgent), What is wrong; "Send to the housing desk" → `POST /me/hostel/maintenance-full` (`:191-205`).
- **Transfer requests**, **Hostel clearance {ref}** (requirement rows and damage charges), **Hostel rules and regulations** (version, "acknowledged"), **Accommodation history**, **Trail** (`:207-241`).
- Modals: rules acknowledgement (checkbox "I have read the hostel rules and regulations and will abide by them." then **Accept the allocation** → `POST /me/hostel/accept` with `rulesVersion`); decline/withdraw (Reason required); transfer (Hall requested, Room type requested, Reason required → `POST /me/hostel/transfer`); checkout (Intended checkout date, Reason → `POST /me/hostel/checkout`) (`:243-270`).

### 1.4.10 Student PDFs
- **Allocation letter** `GET /student/hostel/letter?session=` (`app/student/hostel/letter/route.ts`): refused with 409 "No allocation letter — The letter is issued once the accommodation fee is confirmed." while HELD/LAPSED/DECLINED/CANCELLED (`:26-28`). Contents: brand header, "HOSTEL ALLOCATION LETTER", reference and issue date, two columns (Student, Student ID, Faculty, Department, Programme, Level, Session, Hostel, Block, Floor, Room, Bed, Stay, Check in from, Fee), a paragraph of terms, "Important instructions", the hostel rules (version, first 2600 chars), a QR to `/verify/hostel/{reference_no}`, signature line "Deputy Registrar (Housing, Welfare and Passages)" (`:37-71`).
- **Clearance certificate** `GET /student/hostel/clearance?session=` (`app/student/hostel/clearance/route.ts`): 409 "No clearance certificate — The certificate is issued when the hostel clearance is complete." unless CLEARED (`:26`); contents: student, programme, session, hostel/block/room/bed, checked in/out, each requirement with its state and remarks, certifying paragraph, QR to `/verify/hostel/{allocation ref}`, the same signature line (`:31-62`).

### 1.4.11 Porter's verification — `/verify/hostel/{ref}` (`app/verify/hostel/[ref]/page.tsx`)
Public. "Hostel allocation verification": green "Genuine — this is the University's record" ("Check that the face below matches the student, and the hostel, room and bed match the letter in hand.") with photograph, name, number, programme, session/reference and cells Hostel, Block · floor, Room, Bed, State, Stay, Checked in, Clearance; or red "Not verified — No hostel allocation matches this reference. Treat the letter as not genuine." (`:28-46`). See §6 for the endpoint.

## 1.5 Workflow and statuses

**Window** (`hostel.session_setting.state`): `DRAFT → OPEN → CLOSED → ALLOCATED` (`ck_hs_state`). The draw sets `ALLOCATED` (`V261:706`). A student may apply only while `OPEN`, before `drawn_at`, and within `applications_open…applications_close` (`V261:574-586`).

**Application** (`hostel.application.state`, `ck_ha_state`): `APPLIED` → (draw or manual seating) `ALLOCATED` → (fee confirmed) `CONFIRMED`; `LAPSED` (hold expired); `UNSUCCESSFUL` (waitlisted by the draw or by review); `WITHDRAWN` (by the student, by the desk, on decline or on cancellation); `REJECTED` (review). `review` ∈ APPROVED/REJECTED/WAITLISTED/CORRECTION or NULL (`ck_ha_review`). When the window does not require review the application is inserted with `review='APPROVED'` (`V261:616`).

**Allocation** (`hostel.allocation.state`, `ck_hal_state`): `HELD` (fee > 0) or `CONFIRMED` (fee = 0) at seating (`V261:549`) → `CONFIRMED` (`hostel.confirm_by_reference`, called from `finance.confirm_payment`, `V030:305`, `V033:228`) → `ACCEPTED` (student accepts; required only when rules text exists) → `CHECKED_IN` (porter) → `CHECKED_OUT` (clearance completed CLEARED). Side exits: `DECLINED` (student, from HELD/CONFIRMED/ACCEPTED), `LAPSED` (clock), `CANCELLED` (desk, or application withdrawn), `TRANSFERRED` (old row on a move; the new row carries the state forward, `V261:917-924`). Basis ∈ PRIORITY/BALLOT/RESERVE.

**Transfer request** (`ck_tr_state`): `SUBMITTED → UNDER_REVIEW → APPROVED/REJECTED → COMPLETED`; `decide_transfer` goes straight to `COMPLETED` when approved with a bed (`V261:965-966`). `CANCELLED` exists in the CHECK but nothing sets it.

**Clearance** (`ck_hcl_state`): `PENDING → CLEARED | NOT_CLEARED`; `reopen_clearance` returns NOT_CLEARED to PENDING. Items (`ck_hci_state`): `PENDING / CLEARED / NOT_CLEARED / WAIVED / NOT_APPLICABLE`. Nine seeded requirements (`V261:456-459`): Room returned in good order, Bed and mattress returned, Key returned, Access card returned, Furniture and assets accounted for, No damage outstanding, No maintenance issue assigned to the student, Accommodation fee settled, Damage charges settled.

**Maintenance request** (`ck_hm_state`): `RAISED → ASSIGNED → FIXED → CLOSED`; category ∈ BED/FURNITURE/WATER/ELECTRICITY/PLUMBING/INTERNET/CLEANING/SECURITY/OTHER; priority LOW/NORMAL/HIGH/URGENT.

**Inventory states**: hall/block `ACTIVE|CLOSED`; room `AVAILABLE|MAINTENANCE|CLOSED|RESERVED`; bed `AVAILABLE|MAINTENANCE|OUT_OF_SERVICE`; asset `ACTIVE|RETIRED`, condition NEW/GOOD/FAIR/DAMAGED/REPAIR_REQUIRED/REPLACED/DISPOSED. The bed board derives an **occupancy** of OCCUPIED (checked in), RESERVED (any other live allocation, or room RESERVED), MAINTENANCE (bed/room/hall/block closed or under maintenance), OUT_OF_SERVICE, AVAILABLE (`V261:1249-1254`).

**Who moves what**: student applies/withdraws/pays/accepts/declines/requests transfer/requests checkout/raises maintenance; desk reviews, seats by hand, runs the draw, checks in, transfers, cancels, inspects, charges, waives, decides items, completes/reopens clearance, closes inventory; the clock lapses holds; the Bursary/gateway confirms the fee.

**On rejection/return**: a REJECTED review ends the application (the student may not be seated: "application % was rejected at review"); CORRECTION keeps it APPLIED and the student is told to withdraw and apply again (`V261:661, 672`; screen text `Applications.tsx:137`). A NOT_CLEARED clearance writes a HELD item on the CONVOCATION clearance under unit HOSTEL naming the outstanding requirements (`V261:1107-1110`).

## 1.6 Business rules and validations (with the messages as written)
Eligibility (`hostel.eligibility`, `V261:358-390`): "Accommodation for {s} is not open"; "A student whose status is {x} is not eligible"; "{L} Level is not eligible this session"; "The faculty is not eligible this session"; "Course registration for {s} has not been submitted" (when `require_registration`); "An unsettled hostel damage charge of NGN {x} stands" and "A previous stay was not cleared" (when `refuse_hostel_debt`); "The student is still checked in to a room of another session".

Apply (`V261:563-625`): "accommodation for % is not open: no fee and no hold window are stated" (hint: Student Services states the fee and hold window first); "applications for % are draft|closed"; "the draw for % has been run; applications are closed"; "applications for % open on %"; "applications for % closed on %"; duplicate 23505 "an application for % already stands" (hint "One application per session; withdraw it before making another."); "not eligible for accommodation: {why}"; "the application window for % is full (% applications)"; "no hall %"; "hall % is not for this student"; roommate: "a roommate is another student", "a roommate shares the hall, so shares the sex restriction", "the roommate asked for is not eligible: …". The controller adds `HOSTEL_ROOMMATE` "No student carries the number X." (`HostelLifecycleController.java:127`).

Seating (`hostel.hold`, `V261:520-559`): "application % is %; only one that waits is seated"; "application % was rejected at review"; "application % has not been approved at review" (hint "Approve it on the applications desk first."); "the student is not eligible: …"; "bed % of room % is maintenance|out of service"; "room % is …"; "hall % is closed"; "the block is closed"; "hall % is not for this student"; "hall % is a % hall, not one open to this session"; "bed % of room % is already taken"; "the student already holds a bed for %" (hint "Transfer the student instead; a student holds one bed a session."). One live allocation per student per session is also a partial unique index `uq_hal_one_live` (`V261:295`). Manual seating requires a reason: "a manual allocation carries its reason" (`:806`).

Review (`:651-674`): "a review approves, rejects, waitlists or asks for a correction"; "say why" for REJECTED/CORRECTION; "application % is %; the review is over".

Draw (`:687-755`): "allocation for % is manual: seat each student from the applications desk"; BALLOT needs "the draw runs from a published seed of at least six characters" (hint: publish it before the draw); "the draw for % was run on % from seed %" (a draw runs once); "no bed is free to allocate". Order: priority categories first by application time, then by the method (FIRST_COME by applied_at; LEVEL higher level first; FACULTY/PROGRAMME grouped then by name; BALLOT/SPECIAL_NEEDS by `md5(seed||student_id)`); bed picked preferring the hall, room type and block asked for (`pick_bed`, `:678-685`); those who find no bed become UNSUCCESSFUL with a draw position.

Hold and lapse (`:758-799`): holds expire at `held_until = allocated + hold_hours` (default 72); `lapse_holds` marks LAPSED, tells the student, and if `waitlist` offers the bed as RESERVE to the next UNSUCCESSFUL applicant of a compatible sex by draw position; an ineligible reserve is skipped silently (`:793`).

Fee reference (`hostel.new_fee_reference`, `V030:245-265`): "no bed is held against this application"; "this allocation is already paid and confirmed" (23505); "the hold on this bed expired at %"; an unexpired unconfirmed reference is reused; the amount is the session fee via `finance.new_purpose_reference`. Confirmation (`V261:820-845`): a settled damage charge marks the DAMAGE_CHARGES_SETTLED item CLEARED; a lapsed hold whose bed was re-given raises "the hold on this bed lapsed before the payment arrived, and the bed went to the next name on the draw" (hint: the Bursary refunds or applies it).

Accept/decline/check-in (`:849-893`): "the accommodation fee is paid before the allocation is accepted"; "allocation % is %"; "the hostel rules (version %) are acknowledged before the allocation is accepted" (the client sends the current `rules_version`); "a declined allocation carries its reason"; "allocation % is %; it cannot be declined now"; "the accommodation fee is not confirmed; nobody checks in on a hold"; "the student accepts the allocation under the hostel rules before checking in" (only when rules text exists). Check-in records a CHECKIN inspection with the condition given (default GOOD).

Transfer (`:897-968`): "a transfer carries its reason"; "allocation % is %; there is nothing to transfer"; "that is the bed the student already holds"; the same bed/room/hall/sex/taken checks; the old row becomes TRANSFERRED and a new row (same application, reference, payment, acceptance, check-in state) is created with `moved_from`. Requests: "a transfer is asked for from a confirmed room"; "a transfer request is already waiting" (23505); decision "say why the transfer is refused"; "name the bed the student moves to"; "a transfer request is approved, rejected or put under review".

Checkout and clearance (`:972-1128`): "checkout follows check-in; the student is %"; inspection only of a CHECKED_IN student; the inspection opens the clearance and pre-answers KEY_RETURNED, ACCESS_CARD_RETURNED, ROOM/BED/ASSETS_RETURNED and NO_DAMAGE from what was recorded; `start_clearance` pre-answers FEES_SETTLED (from `confirmed_at`), DAMAGE_CHARGES_SETTLED (NOT_APPLICABLE when no charge), NO_MAINTENANCE_ISSUE (open requests by the student for the room). Charge: "say what was damaged"; "a charge is an amount, zero or more"; a charge > 0 creates a payment reference "Hostel accommodation damage {ref} {id}" and marks the asset DAMAGED; a zero charge is settled at once. Waiver: "a waiver carries its reason"; "the charge is already settled". Items: "not a clearance state"; "say why" for NOT_CLEARED/WAIVED; "the clearance is complete". Completion: "% requirement(s) still pending" (hint: clear, waive or mark not applicable first); with any NOT_CLEARED the clearance is NOT_CLEARED; when CLEARED the allocation becomes CHECKED_OUT/ended and a CLEARED HOSTEL item is written to `clearance.item` for CONVOCATION (`:1101-1103`). Reopen: "only a clearance found wanting is reopened". Cancel: "a cancellation carries its reason"; "allocation % is already %"; "a student checked in leaves through inspection and clearance". Withdraw: "a student checked in leaves by checkout, not by withdrawing the application".

Inventory: hall code `^[A-Z0-9]{2,8}$` (controller message "A hall has a short code of two to eight letters or digits."); room beds 1–12, floor 0–30; saving a room numbers its beds "Bed 1…n" and marks surplus beds OUT_OF_SERVICE ("The room no longer has this bed") (`V261:148-159`); a block is auto-created when a room names one (`:162-187`); closing needs a reason: "say why it is closed"; "a hall, a block, a room or a bed is closed"; "Generate at most five hundred rooms in a run, from a lower number to a higher one." Window: "State the accommodation fee for the session." (remedy "Zero is a fee; blank is not."); "'X' is not an allocation method."; a rules text change increments `rules_version` (`HostelLifecycleController.java:425, 438`). Maintenance from the portal needs a CONFIRMED/ACCEPTED/CHECKED_IN allocation: "No room stands against you this session." / "The bed is held, not yet yours; pay the fee first." (`:215-218`); desk update "A request is raised, assigned, fixed or closed." (`:801`).

Written-once trail: `hostel.event` refuses UPDATE — "the accommodation trail is written once; it is not edited" (`V261:319-325`).

## 1.7 Notifications (`hostel.tell_student` = EMAIL + SMS via `platform.queue_notice`; `hostel.tell_desk` = EMAIL to every holder of housing/services)
| Event | Trigger | Recipient | Channel | Subject |
|---|---|---|---|---|
| Window created or opened | `HostelLifecycleController.window` (`:446-451`, only when ≤ 5000 eligible students) | every student in an eligible status | email+SMS | "Hostel applications are open" |
| Application received | `hostel.apply` | student | email+SMS | "Your hostel application is in" |
| Application awaits review | `hostel.apply` (requires_review) | desk | email | "A hostel application awaits review" |
| Review decided | `hostel.review` | student | email+SMS | "Your hostel application is approved" / "…was not approved" / "…is on the waiting list" / "…needs a correction" |
| Bed allocated (draw or manual) | `hostel.draw`, `hostel.allocate` | student | email+SMS | "You have been allocated a bed" |
| Waitlisted by the draw | `hostel.draw` | student | email+SMS | "Your hostel application is on the waiting list" |
| Hold lapsed | `hostel.lapse_holds` | student | email+SMS | "Your hostel hold has lapsed" |
| Bed offered from the list | `hostel.lapse_holds` | next student | email+SMS | "A hostel bed has been offered to you" |
| Fee confirmed | `hostel.confirm_by_reference` | desk | email | "A hostel fee has been confirmed" |
| Accepted | `hostel.accept` | student | email+SMS | "Your hostel allocation is accepted" |
| Declined | `hostel.decline` | desk; student | email; email+SMS | "A hostel allocation was declined"; "Your hostel allocation is declined" |
| Checked in | `hostel.checkin` | student | email+SMS | "You are checked in" |
| Transferred | `hostel.transfer` | student | email+SMS | "Your hostel room has changed" |
| Transfer requested | `hostel.request_transfer` | desk; student | email; email+SMS | "A room transfer is requested"; "Your transfer request is in" |
| Transfer refused | `hostel.decide_transfer` | student | email+SMS | "Your transfer request was not approved" |
| Checkout requested | `hostel.request_checkout` | desk; student | email; email+SMS | "A checkout is requested"; "Your checkout request is in" |
| Clearance started | `hostel.start_clearance` | student | email+SMS | "Your hostel clearance has started" |
| Damage charge | `hostel.charge` (charge > 0) | student | email+SMS | "A hostel damage charge stands against you" |
| Clearance complete / outstanding | `hostel.complete_clearance` | student | email+SMS | "Your hostel clearance is complete" / "Your hostel clearance has outstanding items" |
| Cancelled by the desk | `hostel.cancel` | student | email+SMS | "Your hostel allocation is cancelled" |
| Maintenance raised | `HostelLifecycleController.raise` (`:225`) | desk | email | "A hostel maintenance request" |
| Maintenance fixed/closed | `HostelLifecycleController.maintenance` (`:810-813`) | student | email+SMS | "Your maintenance request is fixed|closed" |

## 1.8 Reports, exports and documents
- Excel/PDF (branded, S/N first, serial `HST-…`): Hostel Occupancy by Hall (dashboard), Hostel Inventory and Hostel Bed Inventory (inventory), Hostel Applications (17 columns), Hostel Bed Board / Hostel Occupancy — Students, Hostel Clearance, Hostel Checkout Requests, Hostel Transfer Requests.
- PDFs with QR: the allocation letter and the clearance certificate (§1.4.10); the QR resolves to `/verify/hostel/{allocation reference}` and the porter sees name, photograph, placing, state, stay, check-in and clearance (§6).

## 1.9 Configuration
- `hostel.session_setting` (one row per session): fee, hold_hours (1–720, default 72), applications_open/close, allocation_method (default BALLOT), requires_review (false), waitlist (true), max_applications, eligible_statuses (default {ACTIVE,ADMITTED,PROBATION}), eligible_levels, eligible_faculties, eligible_kinds, require_registration (false), refuse_hostel_debt (true), rules, rules_version, stay_from/to, state, seed, drawn_at/by. Edited on `/hostel/window`. **No window is seeded**; a session must be created before students can apply.
- Reference lists (seeded, edited only in SQL — no screen): `hostel.hall_kind` UNDERGRADUATE, POSTGRADUATE, STAFF, INTERNATIONAL, MEDICAL ("Medical / Health"), SPECIAL_NEEDS, OTHER; `hostel.room_type` SINGLE 1, DOUBLE 2, TRIPLE 3, QUADRUPLE 4, SIX_BED 6, EIGHT_BED 8, OTHER 12; `hostel.facility` 15 codes (Bed, Mattress, Wardrobe, Reading table, Chair, Fan, Air conditioner, Bathroom, Toilet, Water supply, Power supply, Generator, Internet / Wi-Fi, Fire extinguisher, Security system); `hostel.clearance_requirement` 9 codes (§1.5) (`V261:48-63, 112-115, 456-459`).
- Halls, blocks, rooms, beds, assets and facilities are created on `/hostel/inventory`. **No hall is seeded** by a migration (the halls in the local database are integration-test residue).
- `moaum.hostel.cron` (default `0 5 * * * *`, Africa/Lagos) for the hold clock (`api/hostel/HostelClock.java:33`).

## 1.10 Data
All `hostel.*` tables are attached to the audit spine (`triggers.psv`); `hostel.event` is additionally write-once. Tables: `hall` (PK code; kind FK hall_kind; sex; campus; location; state), `hall_kind`, `block` (hall_code, code unique; floors; state), `room` (hall_code, block, room_no unique; block_id; floor; room_type; beds; sex; state; legacy `out_of_service` kept in step by triggers `room_before_write`/`room_after_write`), `bed` (room_id, number unique; label; state), `room_type`, `facility`, `room_facility` (PK room_id, facility_code; quantity), `asset` (tag unique; hall/block/room; quantity; condition; value; state), `session_setting` (PK session), `application` (reference `HST-YYYY-NNNNN` unique; student; session; hall_code; category/category_note; room_type_pref; block_pref; special_need; roommate_id; review…; state; draw_position; withdrawn…), `allocation` (reference_no `ALC-YYYY-NNNNN`; application; student; room; bed/bed_id; basis; draw_position; held_until; `reference` = the payment reference; confirmed_at; state; start/end; accepted_at; rules_version; declined; checked_in…; checkout_requested_at/on/reason; checked_out…; lapsed_at; ended_at/reason; moved_from), `transfer_request`, `maintenance_request` (room; raised_by; issue; category; priority; bed; asset; assigned_to; state; note; decided_at), `inspection` (kind CHECKIN/CHECKOUT; condition; cleanliness; damages; keys/card returned), `damage_charge` (allocation; inspection; asset; description; repair/replacement/charge; `reference` payment ref; settled_at; waived…), `clearance` (allocation unique; reference `HCL-YYYY-NNNNN`; state), `clearance_requirement`, `clearance_item` (clearance, requirement unique; state; officer; remarks), `event` (the trail: application/allocation/student/hall/room/bed, action, from/to, note, actor, at). Numbering uses `platform.next_number(kind,'UNIVERSITY',year)` (`V261:254-258`).

## 1.11 Scheduled jobs and integrations
- **HostelClock** (`api/hostel/HostelClock.java`): hourly at minute 5; for every session with an expired HELD allocation runs `hostel.lapse_holds(session)` under an audit context of office `housing`, actor NOBODY; logs "hostel: {n} hold(s) lapsed and passed on"; failures are logged as warnings, not raised. The desk can run the same by hand ("Lapse expired holds", `POST …/lapse`, and `POST /api/v1/hostel/lapse-all` for every session — the latter has no button).
- **Payments**: the accommodation fee and damage charges are `finance.payment_reference` rows; `finance.confirm_payment` calls `hostel.confirm_by_reference` (`V030:305`, superseded definitions in V031/V033 keep the call). Card/gateway confirmation therefore also confirms a bed.
- **Graduation clearance**: `clearance.item` HOSTEL unit written on completion (`V261:1101-1110`).
- **Notices**: `platform.queue_notice`, dispatched by `NoticeDispatcher` (other group).

## 1.12 Security notes
- `/api/v1/verify/hostel/{ref}` is public (`platform/SecurityConfig.java:56`). It answers only for allocations not in HELD/LAPSED/DECLINED/CANCELLED and returns name, number, programme, placing, dates and the passport photograph (`api/verify/VerifyController.java:369-394`). There is **no check token and no rate limit** on this endpoint: the reference `ALC-YYYY-NNNNN` is sequential, so an outsider can enumerate references and harvest names, photographs and room numbers. Compare the receipt/exam/registration/results endpoints which require a SHA-256 check token, and the document endpoint which is throttled.
- The allocation page loads the passport through `/api/bff/api/v1/student/students/{id}/passport` (student module guard, other group).
- Officers act University-wide; there is no hall-level scope.
- All writes pass through SQL functions that run under the caller's audit context; the clock uses a synthetic actor.

## 1.13 Implementation status
| Feature | Status | Evidence | Notes |
|---|---|---|---|
| Inventory: halls, blocks, rooms, beds, facilities, assets, generate rooms, close/reopen with affected occupants | IMPLEMENTED | `HostelLifecycleController.java:231-406`; `Inventory.tsx` | Hall kinds/room types/facilities lists are SQL-seeded only |
| Application window and rules, rules versioning | IMPLEMENTED | `HostelLifecycleController.java:415-453`; `Window.tsx` | |
| Student application with preferences, roommate, priority category | IMPLEMENTED | `V261:563-625`; `Hostel.tsx:136-164` | Category claim is not verified by the system despite the hint "Verified against its rule"; the desk reviews it manually |
| Review desk (approve/reject/waitlist/correction, bulk) | IMPLEMENTED | `V261:651-674`; `Applications.tsx` | |
| Allocation run by 7 methods, preview | IMPLEMENTED | `V261:687-755`; `HostelDashboard.tsx:37-45` | SPECIAL_NEEDS = special-need applicants first then ballot |
| Manual seating into a named free bed | IMPLEMENTED | `V261:802-816` | |
| Hold, payment reference, confirmation by Bursary/gateway | IMPLEMENTED | `V030:245-265`, `V261:820-845` | |
| Lapse clock and waiting-list pass-on | IMPLEMENTED | `HostelClock.java`, `V261:758-799` | |
| Acceptance under rules, decline, withdraw | IMPLEMENTED | `V261:849-877` | |
| Check-in with condition, allocation letter PDF with QR, porter verification | IMPLEMENTED | `V261:879-893`; `letter/route.ts`; `VerifyController.java:369` | No rate limit/token on the verify endpoint (§1.12) |
| Transfers (desk move, student request, decision) | IMPLEMENTED | `V261:897-968` | `CANCELLED` transfer state never set |
| Maintenance requests (student raise, desk assign/fix/close) | IMPLEMENTED | `HostelLifecycleController.java:209-227, 796-825` | `assigned_to` is free text; no artisan register |
| Checkout request, inspection, damage charge → payment reference, waiver | IMPLEMENTED | `V261:972-1071` | Waiver reason via `window.prompt` |
| Clearance items, completion, certificate PDF, graduation HOSTEL unit | IMPLEMENTED | `V261:1073-1115`; `clearance/route.ts` | |
| Student history, trail | IMPLEMENTED | `HostelLifecycleController.java:829-840` | |
| Legacy V030 endpoints `/me/hostel`, `/me/hostel/apply`, `/me/hostel/maintenance`, `PUT /hostel/halls`, `PUT /hostel/rooms`, `PUT …/setting`, `GET /hostel/sessions/{s}/{y}`, `POST /hostel/maintenance/{id}` | IMPLEMENTED but UNUSED BY THE UI | `HostelController.java:109-175` | Only `fee-reference`, `draw`, `lapse` of this controller are called by screens |
| `POST /api/v1/hostel/lapse-all` | IMPLEMENTED, no UI | `HostelLifecycleController.java:844-852` | |
| Hostel accommodation on the Support Services menu | IMPLEMENTED (single entry) | `menus.md` services | Sub-screens reached from the dashboard |
| End-to-end test | IMPLEMENTED | `api/src/test/java/…/HostelIT.java` | |

## 1.14 Common problems and troubleshooting
- "Accommodation for {session} is not open yet" on the student screen → no `session_setting` row: the housing desk creates the window on `/hostel/window` and saves it OPEN.
- "You are not eligible to apply this session" → the reason is shown (status, level, faculty, registration not submitted, unsettled damage charge, uncleared previous stay, still checked in elsewhere); the desk changes the window's eligibility or the underlying record.
- Student cannot see "Pay" → the allocation is not HELD; if LAPSED the bed has gone; ask the desk to seat manually ("Allocate") into a free bed.
- "the hold on this bed lapsed before the payment arrived…" at confirmation → the Bursary applies or refunds the payment; the desk allocates a free bed.
- "the hostel rules (version N) are acknowledged before the allocation is accepted" → the rules changed after the page loaded; reload and accept again.
- "Generate Allocation" disabled → no free bed or nobody approved (`pv.free_beds`/`pv.approved` zero); add rooms or approve applications; with `requires_review` unreviewed applications are not seated.
- "the draw for … was run on … from seed …" → a draw runs once per session; late applicants are seated manually.
- Check-in refused "nobody checks in on a hold" / "the student accepts the allocation under the hostel rules before checking in" → fee not confirmed / acceptance pending.
- "Complete clearance" disabled → an item is still PENDING; decide each item (Clear/Hold/Waive/N/A) first. Clearance came out NOT_CLEARED → settle charges (payment marks the item) or waive, then **Reopen** and complete again.
- Closing a hall/room reports occupants → they keep their record; transfer each from the allocation page.
- Hourly lapse did not run → check the API log for "hostel: the hold clock did not run"; run "Lapse expired holds" by hand.

## 1.15 Glossary
Window (the session's application settings and state) · Hold (a bed reserved unpaid until `held_until`) · Reserve / waiting list (UNSUCCESSFUL applicants in draw order) · Draw position · Basis (PRIORITY, BALLOT, RESERVE) · Seed (published string the ballot order is derived from) · Bed board (every bed with its physical state and occupancy this session) · Rules version · Porter's check-in · Checkout inspection · Damage charge · Hostel clearance (HCL reference) · Allocation reference (ALC) · Application reference (HST).

---

# 2. ICT Support Desk — tickets  (API module: `helpdesk`; schema: `helpdesk`; pages: `app/helpdesk/**`, `app/tickets/**`, `app/track`)

## 2.1 Purpose
A student or a member of staff reports a problem to the Directorate of ICT and receives a ticket number (TICK-YYYY-NNNNN) at once. The ticket carries the category's own fields (a payment reference, a course code, an error message), the requester's contact as the account holds it, and up to ten attachments. It moves SUBMITTED → OPENED (the first agent to read it) → IN_PROGRESS → RESOLVED (with a written resolution) → CLOSED (the requester confirms, an agent closes on a reason, or the portal closes it after a configured quiet spell); a dissatisfied requester reopens it. Agents keep internal notes the requester never sees. Every act is on a write-once history. The Director of ICT keeps the categories, the SLA hours by priority and the auto-close setting, and reads the reports. A public page opens a ticket's standing from its number and email (`db/V251__ict_support_tickets.sql:1-22`).

## 2.2 Users and roles
- `REQUESTER = isAuthenticated() and !hasAnyAuthority('OFFICE_applicant','OFFICE_pgapplicant')` — any signed-in student or staff member (`api/helpdesk/HelpdeskController.java:56`). *Note: the API inventory (`api.md`) mis-parsed this guard as "applicant, pgapplicant"; applicants are in fact the only ones excluded.* A staff member without a person record is refused: `HELPDESK_NOT_A_MEMBER` "Tickets are raised by students and members of staff signed in to the portal." (`:124-126`).
- `AGENTS = ictagent, ict, admin, super` — the desk (`:54`). `DIRECTOR = ict, admin, super` — categories, SLA, settings (`:55`).
- `helpdesk.is_agent(person)` (a current assignment to ictagent/ict/admin/super) decides who may be assigned or escalated to (`V251:226-232`). The **ICT Support Agent** office (`ictagent`, scope platform) is created by V251 (`V251:31-32`).
- A requester sees only their own tickets (`requireMine`, `:772-776`) and never an internal note or attachment (`detail(id,false)`, `:794-810`).

## 2.3 Navigation
| Office | Menu group → item | URL |
|---|---|---|
| ict, admin, super | (ICT/Platform group) → ICT Support Desk / ICT Support Reports / ICT Support Settings | `/helpdesk`, `/helpdesk/reports`, `/helpdesk/settings` |
| ictagent | Overview → ICT Support Desk | `/helpdesk` (home) |
| every staff office | Me → ICT Support Tickets (`r/tickets`) | `/tickets` |
| student, pgstudent | Services → ICT Support Tickets (`s/tickets`) | `/tickets` |
| (no menu) | — | `/tickets/new`, `/tickets/{id}`, `/helpdesk/tickets/{id}`, `/track` (public) |

`app/tickets/who.ts` picks the student shell for a student and the office shell for everyone else, both at `/tickets`.

## 2.4 Screens

### 2.4.1 My Support Tickets — `/tickets` (`app/tickets/page.tsx`)
Tiles Open / Awaiting your confirmation / Closed / All; green notice "N ticket(s) have been marked as resolved" with "Review {number}"; table Ticket, Subject ("With {agent}"), Category, Status, Priority, Raised, Last updated, "Review"/"Open"; actions **Submit a New Ticket**, **Track a Ticket**. Empty: "You have not raised a ticket yet…" (`:21-56`).

### 2.4.2 Submit a ticket — `/tickets/new` (`app/tickets/new/NewTicket.tsx`)
Panel "Who you are" (read-only from the account: Name, Matriculation/Staff number, Programme, Department, Faculty) with **Email** (required; read-only when the account has one — hint says to change it under Profile/the staff record) and **Phone** (`:82-101`). Panel "What it is about": **Category** (required) with description and "Handled as {priority}" hint, then the category's dynamic fields (types text, date, number, select, session, semester, level; required ones marked) (`:103-116`). Panel "The problem": **Subject** (required, ≤200), **Description** (required, ≤8000), **Attachments** (optional, PDF/JPEG/PNG ≤5 MB each, up to five; bad files are marked "Will be skipped") (`:118-140`). "Submit the Ticket" is enabled when a category is chosen, subject > 2 chars, description > 9 chars, email valid and no required field missing; the helper text says what is missing (`:31, 143`). Submit → `POST /api/v1/helpdesk/my/tickets` then one `POST …/attachments` per file. Success: "Your ticket number is TICK-…" with "Open the Ticket", "My Support Tickets", "Submit Another" (`:65-76`).

### 2.4.3 A requester's ticket — `/tickets/{id}` (`app/tickets/[id]/TicketView.tsx`)
Header number, subject, status and priority pills. State notice: RESOLVED → green "Your issue has been marked as resolved" with **Confirm Resolution** (browser confirm, `POST …/confirm`) and **Reopen Ticket** (modal, reason ≥ 5 chars, `POST …/reopen`); CLOSED → "Closed … by you/{name}" and "A closed ticket takes no more updates"; else "Waiting for the ICT desk to open it" / "The ICT desk has opened your ticket" / "Reopened…" / "The ICT desk is working on it" with the agent (`:55-74`). Panels: What you reported (description + category fields), Your details on the ticket, The conversation (updates only; textarea "Add an update for the desk" → `POST …/comments`; file attach → `POST …/attachments`), Attachments, History (timeline without internal events). **Close This Ticket** (modal, optional reason → `POST …/close`) while open and not RESOLVED (`:76-150`).

### 2.4.4 ICT Support Desk — `/helpdesk` (`app/helpdesk/page.tsx`, `Desk.tsx`)
Loads the queue (`GET /api/v1/helpdesk/tickets?…`, default `status=open`), stats, categories, agents, "with you" (agent=me, sort=due) and the activity feed. KPI tiles: Total tickets, New (SUBMITTED), Opened, In progress (+reopened), Unassigned, High priority, Overdue ("N past first response · N escalated"), Average resolution ("First response … · N% within SLA") (`:72-84`). Panel "With you" (up to 5, "Show All N"). Filter bar: Search (number, subject, name, matric/staff number, email, payment reference — the server also matches `details->>'username'`), Status (All open / each status / In progress or reopened / Everything), Category, Priority, Agent (Any / Assigned to me / Unassigned / each agent), Raised from / To; Search, Clear (`:101-141`). Queue: sort buttons Updated/Raised/Priority/Status/Due/Number with direction; rows Ticket (+"Overdue"/"No response yet" pill), Requester (number/email, Student/Staff), Category, Subject (+"Escalated"), Priority, Status, Agent ("You"), Due, Raised/updated, **Take** (unassigned, not settled → `POST …/assign {agentId: me}`), **Open** (`:143-167`); pager and rows-a-page 10/20/50/100. Panel "Lately on the desk" (last 20 events). Director only: "Agent workload" and "Tickets by category" (`:182-221`). Actions: Reports and Analytics, Categories and SLAs (director), My Own Tickets.

### 2.4.5 The desk's ticket — `/helpdesk/tickets/{id}` (`app/helpdesk/tickets/[id]/DeskTicket.tsx`)
Opening the page calls `GET /api/v1/helpdesk/tickets/{id}`, which **opens a SUBMITTED ticket** (OPENED, recorded, requester emailed) (`HelpdeskController.java:466-475`). Panel "Act on the ticket": **Accept the Ticket / Take It Over**, **Assign to an Agent / Reassign** (modal: Agent select with offices and open load, optional Note), **Start Work** (OPENED/REOPENED → IN_PROGRESS), **Resolve** (IN_PROGRESS; modal Resolution summary ≥5 chars ≤300, Resolution details ≥20 chars ≤8000), **Close as Resolved** (RESOLVED → CLOSED with reason "Closed by the desk after the resolution"), **Reopen** (RESOLVED or CLOSED; reason ≥5), **Escalate** (modal: Escalate to — agents other than yourself, director first; Reason ≥5), priority select (Low/Normal/High/Urgent → `POST …/priority`), **Close on a Reason** (reason ≥5) (`:66-89`). Sub-text shows due date by SLA, first response time or due, and escalation details. Resolution note; panels Requester (with "Open the Student Record" → `/search?q=`), Issue details (opened by), Attachments (upload with "Internal (the requester does not see it)"), Conversation and history (tabs; message type **Internal Note** / **Update to the Requester** — "Seen by the ICT desk only." / "Sent to the requester by email and shown on their ticket."; "Add Internal Note" / "Send Update") (`:96-168`).

### 2.4.6 Reports — `/helpdesk/reports` (`app/helpdesk/reports/Reports.tsx`)
Filters Raised from/To, Category, Priority, Agent, Faculty, Department (query string → `GET /api/v1/helpdesk/stats?…`). Tiles Tickets, Overdue, Average first response, Average resolution (closure, % within SLA). "Monthly ticket volume" (12 months, raised vs resolved bars). Breakdowns with meters: by status, category (with open), priority, requester (Students/Staff), faculty, department; "Tickets by agent" (tickets, open, done, overdue, average resolution); "The SLA in force". **Download the Report** → CSV via `lib/results` `csv/download` ("ICT support report YYYY-MM-DD") — not the branded Excel (`:46-58`).

### 2.4.7 Settings — `/helpdesk/settings` (`app/helpdesk/settings/Settings.tsx`)
Panel "Categories" (order, name/code/description, "Asks for" fields with `*` for required and the attachment hint, "Handled as" priority, tickets count, Active/Inactive, **Edit**); **New Category**. Modal: Name (required, ≤120), Code (optional; made from the name; fixed once created), Order, Handled as (priority), Description, What to attach, "Open for new tickets", and the field list (Label, Key auto-slugged, Type Text/Date/Number/Choice/Academic session/Semester/Level, Required, Hint, Options one a line for Choice; **Add a Field**, **Remove**) with client faults "Every field needs a key and a label." / "Two fields share a key." / "A choice field lists its options." → `POST|PUT /api/v1/helpdesk/admin/categories[/{id}]` (`:40-55, 112-140`). Panel "The SLA by priority": First response (h) and Resolution (h) per priority. Panel "Closing and notice": "Close a resolved ticket automatically after" N days (blank = Off, 1–90), "Email every agent and the Director when a new ticket arrives"; **Save SLA and Settings** → `PUT /api/v1/helpdesk/admin/settings` (`:80-109`).

### 2.4.8 Public tracking — `/track` (`app/track/page.tsx`)
"Track an ICT Support Ticket": Ticket number, Email address, **Track Ticket**, "Sign in to the portal instead". Result card: category, number, subject, status/priority pills, Raised, Last updated, Resolution (or "Closed without a resolution recorded"/"Not yet resolved"), Closed, a green note when RESOLVED ("Sign in to the portal to confirm…"), History (non-internal events), reopen count. Errors: 404 → "No ticket with that number was raised with that email address. Check both and try again."; 422 → "Too many lookups in a short time. Wait a quarter of an hour…" (`:20-30, 45-73`).

## 2.5 Workflow and statuses
`helpdesk.ticket.status` ∈ SUBMITTED, OPENED, IN_PROGRESS, RESOLVED, CLOSED, REOPENED (`ck_hd_ticket_status`). Transitions (`helpdesk.transition`, `V251:321-370`):
- AGENT: SUBMITTED→OPENED, OPENED→IN_PROGRESS, REOPENED→IN_PROGRESS, RESOLVED→CLOSED, RESOLVED|CLOSED→REOPENED (reason), any non-closed→CLOSED (reason required); IN_PROGRESS→RESOLVED only through `helpdesk.resolve` with summary ≥5 and details ≥20 chars (`:373-391`).
- REQUESTER: RESOLVED→CLOSED (confirmation; closure reason "The requester confirmed the resolution"), RESOLVED→REOPENED (reason), SUBMITTED|OPENED|IN_PROGRESS|REOPENED→CLOSED ("Withdrawn by the requester").
- SYSTEM: RESOLVED→CLOSED after `auto_close_days` (`helpdesk.auto_close`, `:500-512`), reason "Closed automatically: N day(s) passed after the resolution with no reply from the requester".
Timestamps: `opened_at/by` on first open; `in_progress_at`; `first_response_at` on the first IN_PROGRESS by an agent, the first non-internal agent comment, or resolution; `resolved_at/by`; `closed_at/by/by_kind` (REQUESTER/AGENT/SYSTEM); `reopen_count`. Priority is the category's suggested priority at submission and may be changed by the desk. Assignment and escalation are independent of status (refused on a CLOSED ticket). Events (`ck_hd_event_action`): SUBMITTED, OPENED, STATUS_CHANGED, ASSIGNED, REASSIGNED, ESCALATED, PRIORITY_CHANGED, INTERNAL_NOTE, UPDATE, RESOLUTION, REOPENED, CLOSED, ATTACHMENT.

## 2.6 Business rules and validations
- Submission (`helpdesk.submit`, `V251:270-300`): "that category is not open for new tickets"; "a ticket has a subject"; "a ticket describes the problem"; "a ticket carries an email address the desk can reach"; "{label} is required for a {category} ticket"; "ten tickets are open already" (per requester, status ≠ CLOSED). The controller keeps only detail keys the category declares, ≤30 keys, each ≤500 chars (`HelpdeskController.java:186-189`); the account's email wins over a typed one (`:183`).
- Number: `TICK-YYYY-NNNNN`, five random digits, never reused; "no free ticket number found after 50 draws" (`V251:241-253`).
- Transitions: "the ticket is already {status}"; "a reason is recorded when a ticket is reopened|closed by the desk"; "a closure by the desk records its reason"; "reopening a ticket says what is still wrong"; "a ticket does not go from {a} to {b} this way" (hint: the ladder). Controller: `HELPDESK_STATUS` "The desk moves a ticket to opened, in progress, closed or reopened; a resolution is recorded through Resolve." (`:501-503`); `HELPDESK_NOT_RESOLVED` "Only a resolved ticket is confirmed." (`:256-258`).
- Resolve: "a ticket is resolved from in progress; this one is …" (hint "Start work on it first."); "a resolution says what was done".
- Assign/escalate: "a closed ticket is not assigned|escalated" (hint "Reopen it first."); "only an ICT Support Agent or the Director of ICT takes a ticket" (hint: appoint the person to the ICT Support Agent office first); "the ticket is with that agent already"; "a ticket is escalated to an ICT Support Agent or the Director of ICT"; "a ticket is escalated to someone else"; "an escalation says why". `HELPDESK_PRIORITY` "A priority is low, normal, high or urgent."
- Comments/attachments: "a closed ticket takes no more updates" (requester); "an update says something"; ≤10 attachments ("ten attachments are on the ticket already"); file rules in the controller: `HELPDESK_FILE_BAD` "The file could not be read.", `HELPDESK_FILE_SIZE` "An attachment is between 1 byte and 5 MB.", `HELPDESK_FILE_TYPE` "An attachment is a PDF, a JPEG or a PNG, and its contents must be what its name says." (magic bytes are sniffed, `:819-848`); filenames are sanitised; content served with `Content-Security-Policy: sandbox`, `nosniff`, no-store (`:855-861`).
- Categories: code `^[A-Z][A-Z0-9_]{1,30}$` (`HELPDESK_CATEGORY_CODE`); field keys `^[a-z][a-z0-9_]{0,30}$`, types text/date/number/select/session/semester/level, choice needs options (`HELPDESK_FIELD`); a category is deactivated, never deleted. SLA: 1–720 h first response, 1–2160 h resolution, `HELPDESK_SLA` "The resolution time is at least the first-response time." (also CHECK `ck_hd_sla_hours`). Auto-close 1–90 days or NULL.
- Public tracking: exact number + case-insensitive email; throttled to 12 lookups per 15 minutes per IP and per email (`HELPDESK_TRACK_SLOW_DOWN`, `:707-719`); returns no names, no attachments, no internal events, no assignment/escalation/priority events (`:721-748`).
- History is written once: "the ticket history is written once; nothing on it is changed or removed" (`V251:210-222`).

## 2.7 Notifications (`api/helpdesk/TicketNotifier.java`; email only, through `NoticeRepository.queueEmail`; a student's notices are filed against the student so they also appear on the student's Notifications page)
| Event | Trigger | Recipient | Subject |
|---|---|---|---|
| Submitted | `submit` → `notifier.submitted` | requester; every agent + Director if `notify_agents_on_new` | "ICT Support Ticket Received — {n}"; "New ICT support ticket {n} — {category}" |
| Opened by the desk / started / status change | `ticket` (first open), `status` → `statusChanged` | requester | "Update on your ICT support ticket {n}" |
| Assigned / reassigned | `assign` → `assigned` | the agent | "Ticket assigned to you — {n}" / "Ticket reassigned to you — {n}" |
| Escalated | `escalate` → `escalated` | the person escalated to | "Ticket escalated to you — {n}" |
| Resolved | `resolve` → `resolved` | requester | "Your ICT support ticket is resolved — {n}" |
| Closed (any actor incl. auto-close) | `confirm`, `withdraw`, `status CLOSED`, `AutoCloser` → `closed` | requester | "Your ICT support ticket is closed — {n}" |
| Reopened | `reopen` (requester) / `status REOPENED` (desk) → `reopened` | assigned agent if reachable, else every agent | "Ticket reopened — {n}" |
| Agent update (non-internal) | `note` → `agentUpdate` | requester | "The ICT desk has an update on {n}" |
| Requester update | `mySay` → `requesterUpdate` | assigned agent or the desk | "Update from the requester — {n}" |
Every body ends with the tracking line pointing to `{portalUrl}/track` (`moaum.portal-url`, default the Railway URL, `TicketNotifier.java:27`). No SMS is sent by this module.

## 2.8 Reports, exports and documents
- Reports page (§2.4.6) and its CSV download (headers Report, Item, Tickets, Open, Done, Overdue, Average resolution (h); scope and totals in the preamble).
- Desk KPIs and the Director's workload/category panels.
- No PDF, no branded Excel, no printed ticket.

## 2.9 Configuration
- `helpdesk.category` — 11 seeded categories with fields and suggested priority (`V251:515-566`): PAYMENT (HIGH; payment_reference*, payment_date*, payment_type* select, amount*), LOGIN (HIGH; account_type*, username*, error*, started_on), REGISTRATION (NORMAL; session*, semester*, programme, level*, course_code, course_title), RESULTS (NORMAL), EXAMINATIONS (HIGH), PORTAL (NORMAL), EMAIL (NORMAL), ACCOUNT (NORMAL), NETWORK (NORMAL), GENERAL (NORMAL, no fields), OTHER (LOW, no fields).
- `helpdesk.sla` seeded LOW 72/240 h, NORMAL 24/120, HIGH 8/48, URGENT 2/24 (`V251:67-68`).
- `helpdesk.setting` single row: `auto_close_days` NULL (off), `notify_agents_on_new` true (`V251:70-78`).
- Application property `moaum.portal-url` for the links in emails.

## 2.10 Data
`helpdesk.ticket` (number unique; category; subject; description; priority; status; requester_kind STUDENT/STAFF, requester_id, name, number, email, phone, department_code, faculty_code; details jsonb; assigned/escalated…; the timestamps above; resolution_summary/details; closure fields; reopen_count), `ticket_comment` (author_kind REQUESTER/AGENT/SYSTEM; internal only for AGENT), `ticket_attachment` (+ `ticket_attachment_blob`, audit-exempt), `ticket_event` (write-once), `category`, `sla`, `setting`. All but the blob are on the audit spine.

## 2.11 Scheduled jobs and integrations
- **AutoCloser** (`api/helpdesk/AutoCloser.java`): `@Scheduled(initialDelay 5 min, fixedDelay 1 h)`; runs `helpdesk.auto_close()` (≤200 tickets a run) under audit office `ict`, then emails each requester; inactive while `auto_close_days` is NULL (the shipped default).
- Notices via `NoticeRepository`/`NoticeDispatcher` (platform module).

## 2.12 Security notes
- `POST /api/v1/helpdesk/track` is public (`SecurityConfig.java:56`), throttled in-memory (per API instance) and answers only with number + email; no names.
- Attachments are sniffed and served sandboxed. Requesters cannot read internal notes or internal files (`content(…, desk=false)`).
- Any authenticated non-applicant may raise tickets; the queue and admin surfaces are guarded as above. Agent identity for assignment is checked in SQL (`is_agent`).

## 2.13 Implementation status
| Feature | Status | Evidence | Notes |
|---|---|---|---|
| Ticket creation by students and staff with category fields and attachments | IMPLEMENTED | `HelpdeskController.java:177-198`; `NewTicket.tsx` | |
| Public tracking by number + email, throttled | IMPLEMENTED | `HelpdeskController.java:722-748`; `track/page.tsx` | Public page can only look up, not create |
| Queue with server-side search/filter/sort/paging; "Take" | IMPLEMENTED | `HelpdeskController.java:294-366`; `Desk.tsx` | |
| Auto-open on first read | IMPLEMENTED | `HelpdeskController.java:466-475` | |
| Assignment, reassignment, escalation, priority | IMPLEMENTED | `V251:393-440` | Escalation records a person; it does not change assignment |
| Internal notes vs updates, internal attachments | IMPLEMENTED | `V251:442-484` | |
| Resolve with summary/details; requester confirm/reopen; withdraw; desk close on reason | IMPLEMENTED | `V251:321-391` | |
| Auto-close job | IMPLEMENTED, off by default | `AutoCloser.java:38`, `V251:500-512` | |
| Satisfaction rating | NOT IMPLEMENTED | no table/column/endpoint | "Satisfaction" exists only as the requester's confirm-or-reopen choice |
| SLA, overdue and response-overdue flags, KPIs, monthly volume | IMPLEMENTED | `HelpdeskController.java:369-435`; `Reports.tsx` | |
| Reports download | IMPLEMENTED (plain CSV) | `Reports.tsx:46-58` | Not the branded `brandedXlsx`/`brandedPrint` |
| Categories/fields editor, SLA editor, settings | IMPLEMENTED | `HelpdeskController.java:589-700`; `Settings.tsx` | |
| Notifications | IMPLEMENTED (email only) | `TicketNotifier.java` | |
| End-to-end test | IMPLEMENTED | `api/src/test/java/…/HelpdeskIT.java` | |

## 2.14 Common problems and troubleshooting
- Staff member gets `HELPDESK_NOT_A_MEMBER` → no `iam.person` row for the account.
- "ten tickets are open already" → close or wait on an existing ticket.
- "{Field} is required for a {Category} ticket" → a required category field was blank (also caught client-side).
- Attachment refused → not PDF/JPEG/PNG, over 5 MB, or the bytes do not match the declared type (e.g. a renamed file).
- "only an ICT Support Agent or the Director of ICT takes a ticket" → give the person the `ictagent` office in IAM first.
- "a ticket is resolved from in progress" → click Start Work first.
- Requester cannot confirm → the ticket is not RESOLVED yet.
- Tracking says not found → number and email must both match the email the ticket was raised with (the account's email, lower-cased).
- Tickets never auto-close → by design until the Director sets "Close a resolved ticket automatically after".

## 2.15 Glossary
Ticket number (TICK) · Opened (first read by an agent) · First response · Internal note · Update · Escalation · Quiet spell (auto-close days) · SLA (first-response and resolution hours by priority) · Overdue / No response yet · Take (self-assign from the queue).

---

# 3. Help & Requests — service requests to an office  (API module: `support`; tables: `platform.service_request`, `platform.request_document(_blob)`; pages: `app/student/support`, `app/support`)

## 3.1 Purpose
A student's one-line request to one of eight offices — the Registry, the Bursary, ICT, the Library, Student Services, the Academic Office, "My department" (hod) or Housing — with an optional detail and up to six supporting documents. The office answers on the record, choosing whether the answer resolves the request or leaves it open for a reply; the student is told by email and SMS (`V036:34-69`). This predates and is separate from the ICT ticket desk (§2), which V251 explicitly left in place (`V251:19-22`).

## 3.2 Users and roles
- Student: `hasAuthority('OFFICE_student')` (`api/support/SupportController.java:73`).
- Offices: `OFFICES = registrar, dregistrar, bursar, ict, library, services, academic, hod, housing, admin, super` (`:35`). Each office sees **only requests addressed to its own office code** (`r.office_code = actorOffice`); `admin`, `super` and `ict` see every office's (`:139-146, 166-171`). Note `dregistrar` is in the guard but a student cannot address `dregistrar`, so that office's desk is always empty. A HOD sees every request addressed to "hod", not only their department's (no scope applied).

## 3.3 Navigation
| Office | Menu | URL |
|---|---|---|
| student, pgstudent | Services → Help & Requests (`s/support`) | `/student/support` |
| none (the office desk `t/support` has a route and title — "Help & requests · What students have put to this office, the oldest open first" — but appears on no office's menu, `routes.md` "t/support" lists no office) | — | `/support` |

## 3.4 Screens
- **Student — `/student/support`** (`app/student/support/Support.tsx`): panel "Your requests" (Reference, Subject with the answer or detail, Office, Raised, Documents pill, Status pill "Resolved" / "Answered — still open" / "With {office}"); panel "Raise a new request": office pills (Registry, Bursary, ICT, Library, Student Services, Academic Office, My department, Housing), "What is the problem?" (one line, required), "Anything more the office should know" (textarea), "Supporting documents" (PDF/JPEG/PNG ≤2 MB each, up to six), **Submit request** → `POST /api/v1/me/requests` then one `POST /api/v1/me/requests/{id}/documents` per file; success note "Request SR-… is with {office} — N document(s) attached" and "You will be notified here and by SMS when it is answered." (`:56-91`).
- **Office desk — `/support`** (`app/support/SupportDesk.tsx`): tiles Open (with the oldest age in days), Answered still open, Resolved, All (newest 300); notice "A request that sits unanswered is the failure this queue exists to prevent"; table Reference, Student, Subject, Raised, Documents, State, **Answer**/**Open**; modal with the detail, the supporting documents (links to `/api/bff/api/v1/support/requests/{id}/documents/{doc}/content`), "Your answer" textarea, checkbox "This resolves the request.", **Answer and resolve** / **Answer, keep open** → `POST /api/v1/support/requests/{id}/answer {answer, resolved}` (`:63-111`).

## 3.5 Workflow and statuses
`platform.service_request.state` ∈ OPEN, WITH_OFFICE, RESOLVED, CLOSED (`ck_sr_state`). Raised as OPEN; an answer sets RESOLVED (resolved=true) or WITH_OFFICE (resolved=false). Nothing in the code sets CLOSED, and there is **no student reply**: "the student may write back" exists only as label text; a WITH_OFFICE request can only be answered again by the office. `ck_sr_answered` requires answer and answered_at for RESOLVED/CLOSED.

## 3.6 Business rules
`platform.raise_request` (`V036:34-50`): office ∈ the eight codes ("requests go to the Registry, the Bursary, ICT, the Library, Student Services, the Academic Office, the department or Housing"); "say what the problem is, in one line"; at most five open requests per student ("five requests are open already; wait for an answer before raising another"); reference `SR-YYYY-NNNNN`. `platform.answer_request` (`:52-69`): "an answer says something"; records `answered_by` from the audit actor. Documents (`V040:35-54`): "a document is attached by a person"; "no such request"; ≤6 per request ("a request carries at most six documents"); CHECKs `ck_rd_type` (pdf/jpeg/png) and `ck_rd_bytes` 1–2 MB; controller messages `SUPPORT_DOC_BAD` "The document could not be read.", `SUPPORT_DOC_SIZE` "A supporting document is between 1 byte and 2 MB.", `SUPPORT_DOC_TYPE` "A supporting document is a PDF, a JPEG or a PNG." (no magic-byte sniffing here, unlike the help desk). A student may attach only to their own request; an office only to (read) requests of its office.

## 3.7 Notifications
| Event | Trigger | Recipient | Channel | Subject |
|---|---|---|---|---|
| Answered | `platform.answer_request` | student | email + SMS | "Your request {ref} is resolved" / "Your request {ref} has an answer" (SMS "Your request {ref}") |
No notice is sent to the office when a request is raised.

## 3.8 Reports and exports — None.
## 3.9 Configuration — None (the office list is hard-coded in SQL and in `Support.tsx:28`).
## 3.10 Data — `platform.service_request` (ref unique; student; office_code; subject; detail; raised_at; state; answer; answered_at/by) on the spine; `platform.request_document` (filename, content_type, bytes, uploaded_by) on the spine; `platform.request_document_blob` audit-exempt (`V040:30`).
## 3.11 Jobs/integrations — None beyond `platform.queue_notice`.
## 3.12 Security — Ownership and office checks in the controller (`requireOwnRequest`, `requireOfficeRequest`); admin/super/ict read every office's requests and documents; document bytes are served inline without `nosniff`/sandbox headers (`SupportController.java:205-208`).

## 3.13 Implementation status
| Feature | Status | Evidence | Notes |
|---|---|---|---|
| Student raises a request to one of eight offices, with documents | IMPLEMENTED | `SupportController.java:79-107`; `Support.tsx` | |
| Office answers, resolve or keep open; student told | IMPLEMENTED | `SupportController.java:149-155`; `V036:52-69` | |
| Office desk page in a menu | PARTIALLY IMPLEMENTED | `routes.md` `t/support` lists no office | The page works at `/support` but no office menu links to it |
| Student reply to an answered request | NOT IMPLEMENTED | no endpoint | label "The student may write back" is aspirational |
| CLOSED state | CONFIGURED BUT UNUSED | `ck_sr_state` | nothing sets it |
| Department scope for HOD | NOT IMPLEMENTED | `SupportController.java:139-146` | any HOD sees every "hod" request |
| Reminder/escalation of unanswered requests | NOT IMPLEMENTED | — | the desk shows the oldest age only |

## 3.14 Troubleshooting — "five requests are open already" (wait or get an answer); a file skipped (type/size); office sees nothing (requests are addressed per office code; the desk only lists its own); "Help & requests" not in an office menu (open `/support` directly).
## 3.15 Glossary — Service request (SR reference) · With office (answered, left open) · Supporting document.

---

# 4. University Health Services — the clinic  (API module: `health`; schema: `health`; pages: `app/clinic`; the student's `/student/health` belongs to the student-portal group and is only referenced here)

## 4.1 Purpose
A minimal clinic record: the student books an appointment or walks in; the clinic puts the patient on a triaged waiting list, opens the record (the opening is logged against the clinician), concludes the visit with an outcome the student sees, an optional referral, a clinical note that never leaves the clinic, and optionally a fitness status (FIT / UNFIT / FIT_WITH_CONDITIONS) that the Registry and department may read. The student consents to blood group, genotype and allergies being on the record and may restrict them (`V032:1-13`).

## 4.2 Users and roles
`CLINIC = hasAnyAuthority('OFFICE_services','OFFICE_super')` for the desk (`api/health/HealthController.java:26`); the student for `/api/v1/me/health…`. There is no dedicated clinician/medical office: Support Services staff act as clinicians. `health.fitness_of(student)` is the only outward-facing read (`V032:192-197`).

## 4.3 Navigation — services: Overview → Clinic (`t/clinic`, home) → `/clinic`. Student: Services → Health → `/student/health` (other group).

## 4.4 Screens — `/clinic` (`app/clinic/Clinic.tsx`)
Notice "Clinical notes never leave this module" (`:51`). Tiles Encounters today, Awaiting triage (longest wait), Referrals this month, Fitness recorded (booked today) (`:56-61`). Panel "Patient arrives": Number (matric or admission), Presenting complaint, Triage (Urgent/Standard/Routine), **Add to the waiting list** → `POST /api/v1/health/visits {number, presenting, triage}`; **Look the patient up** (`?number=`; shows "Nobody carries the number X" or the patron) (`:63-76`). Panel "Booked" (appointments for today and tomorrow) with **Arrived** (posts the appointment id). Panel "Waiting list" ordered urgent first with **See now / Open / Open · {clinician}** → `POST /api/v1/health/visits/{id}/open`, which returns the record and opens the modal (`:83-93`). Panel "Concluded today". Notice "Pharmacy stock is not on the portal — the prototype drew a stock alert table; no dispensing record exists in this module yet" (`:99`). Modal (patient, programme, sex, DOB): Presenting, Triage, Arrived, Blood group / Genotype / Allergies ("Not consented" unless consented and not restricted), earlier visits with notes, fields Outcome (required; "What the patient sees on their record."), Referred to, Fitness (Unchanged/Fit/Fit with conditions/Unfit), Clinical note ("Never leaves the clinic."); **Conclude the visit** → `POST /api/v1/health/visits/{id}/conclude`; **Leave open** (`:101-123`).

## 4.5 Workflow and statuses
Appointment `BOOKED → SEEN` (on arrival) | `CANCELLED` (student) | `MISSED` (in the CHECK, never set). Visit `WAITING → IN_CONSULTATION → DONE`; `LEFT` in the CHECK, never set. Triage URGENT/STANDARD/ROUTINE. Profile fitness PENDING/FIT/UNFIT/FIT_WITH_CONDITIONS.

## 4.6 Business rules (`V032:94-181`)
Book: "say why you want to be seen"; "choose a time ahead" (not more than an hour past); one BOOKED future appointment at a time ("an appointment already stands; cancel it before booking another", 23505). Cancel: only a BOOKED one of the student's own ("no booked appointment %"). Arrive: "the patient is already on the waiting list"; presenting defaults to "Not stated"; a booked appointment becomes SEEN. See: "visit % is not waiting"; logs "opened the visit" in `record_access`; the API's `open` logs "read the record" again (`HealthRepository.java:136`). Conclude: "a visit is concluded with its outcome"; "visit % is not open"; a note is stored only when given; fitness upserts the profile. Service checks: `HLT_NO_PATIENT` "No student carries the number X.", `HLT_TRIAGE` "Triage is urgent, standard or routine.", `HLT_FITNESS` "Fitness is fit, unfit, or fit with conditions." (`HealthService.java:86-108`). Consent overwrites and clears any restriction; restrict sets `restricted_at`.

## 4.7 Notifications — None. Nothing in the health module queues a notice.
## 4.8 Reports/exports — None.
## 4.9 Configuration — None.
## 4.10 Data — `health.profile` (PK student; blood_group; genotype; allergies; consented_at; restricted_at; fitness; fitness_on/by), `health.appointment`, `health.visit` (appointment; presenting; triage; state; seen_at; clinician; outcome; referred_to; concluded_at) — all on the spine; `health.note` and `health.record_access` are audit-exempt with stated reasons (`V032:79-91`).
## 4.11 Jobs — None.
## 4.12 Security — The clinic guard is Support Services + super; every read of a record is logged and (per the migration) shown to the patient on `/student/health` (`accessLog`, `HealthRepository.java:38-44`). Clinical notes are returned to the clinician in the `open` history (`:139-144`) and never to the student (`health.student_visits`).

## 4.13 Implementation status
| Feature | Status | Evidence | Notes |
|---|---|---|---|
| Student booking/cancel, consent, restrict | IMPLEMENTED (API) | `HealthController.java:55-83` | Student screen is in the student-portal group (`app/student/health`) |
| Walk-in / arrival, triage, waiting list | IMPLEMENTED | `HealthService.java:79-91`; `Clinic.tsx` | |
| Open record with access log, conclude with outcome/referral/note/fitness | IMPLEMENTED | `HealthRepository.java:130-147`; `V032:114-141` | |
| Fitness read by Registry/department | IMPLEMENTED (SQL function) | `V032:192-197` | Consumers are in other modules |
| MISSED appointments, LEFT visits | CONFIGURED BUT UNUSED | `ck_ha_state`, `ck_hv_state` | no code sets them |
| Pharmacy / dispensing / stock | NOT IMPLEMENTED | `Clinic.tsx:99` says so | |
| Prescriptions, lab, medical certificates, notifications, exports | NOT IMPLEMENTED | — | |
| Dedicated clinician office | NOT IMPLEMENTED | guard is `services`,`super` | |

## 4.14 Troubleshooting — "Nobody carries the number" (use matric or admission number as issued); "the patient is already on the waiting list"; "choose a time ahead"; "an appointment already stands".
## 4.15 Glossary — Presenting complaint · Triage · Consented facts · Restricted · Fitness status · Access log.

---

# 5. Digital documents, transcripts, certificates and identity cards  (API module: `credentials`; schema: `credentials`; pages: `app/credentials/**`, `app/student/documents/**`, `app/student/transcript`, `app/documents/d/[token]`, `app/student/idcard`, `app/staff/idcard`, `app/verify/document/**`)

## 5.1 Purpose
Two generations coexist. **V005/V013/V027** built the credential store (`credentials.issued` with a statement kept byte for byte, a Crockford verification code, a revocation register naming its minute), the transcript request and its production queue, the printed certificate register with security stationery, and the identity card. **V262** turned them into a digital-documents system: a policy per kind (degree certificate, official full transcript, sessional transcript, mini-transcript, statement of academic record) — billable or free, fees, SLA, self-service, number format, public fields; versioned templates; the statement built from the authoritative result record (undergraduate from `assessment.student_results/student_gpa`, postgraduate from PG coursework and research); a request pipeline — invoice through the ordinary payment reference, validation with findings, generation as a versioned document numbered `PREFIX/YYYY/NNNNNN`, quality check, release by a second officer, delivery by expiring tokens or courier, completion; degree certificates issued singly or in a run to graduated, Senate-approved, cleared students; revocation by the Registrar or VC citing a minute; reissue as a new version (old verifies REPLACED); flags when a score or the award changes after issue; public verification by code or number with rate limiting and a log; and the student's document library (`V262:1-30`). The signature column holds a SHA-256 hash of the statement, **not** a cryptographic signature — "the University has no signing key in custody" (`V262:26-29`; `credentials.issued.signed_with` is nullable since V262 and `credentials.signing_key` is empty).

## 5.2 Users and roles
`api/credentials/DocumentsController.java:43-48`:
- `READERS` academic, registrar, dregistrar, records, dvc, vc, bursar, ict, admin, super, audit — dashboard, requests, register, templates, verification log, office PDF download.
- `OFFICE` academic, registrar, dregistrar, records — start, generate, QC, cancel, complete, deliveries, resend, clear flag.
- `SIGNERS` registrar, dregistrar, academic — release, reissue, issue certificates (single and bulk).
- `REVOKERS` registrar, vc — revoke.
- `CONFIG` registrar, dregistrar, academic, super — policies and templates.
- Student: `/api/v1/me/documents…`.
Legacy `CredentialsController.java:21-25`: READERS adds dean, hod; OFFICE = academic, registrar, dregistrar, records; SIGNERS = registrar, dregistrar, academic (mark-paid, release, reissue). Identity cards (`IdentityCardController.java:581-582`): READERS library, security, registrar, dregistrar, academic, records, ict, super; ISSUERS library, security, super. Segregation of duty: the officer who produced a document cannot release it (`V262:688-690`).

## 5.3 Navigation
| Office | Menu | URL |
|---|---|---|
| academic, records, registrar, dregistrar | Documents Office (`t/documents`) | `/credentials/documents` (sub-pages `/requests`, `/register`, `/settings`, `/requests/{id}` reached from it; `t/documents-requests|register|settings` are route ids with no menu owner) |
| academic, records, registrar, dregistrar | Transcripts (`t/transcripts`, badge) | `/credentials/transcripts` |
| academic, records, registrar | Certificates (`t/certificates`) | `/credentials/certificates` |
| library | Overview → Card Printing (`t/idcards`, home) | `/credentials/idcards` |
| security | Services → Card Collection (`t/idcards`), Lost & Replacement (`t/idlost`) | both `/credentials/idcards`; Overview → "Verify a Card" (`t/idverify`, the office's home) has **no URL** (`menus.md`: `—`; not in `Shell.tsx` ROUTES) |
| student, pgstudent | Academic → My Documents (`s/documents`); Services → Identity Card (`s/idcard`) | `/student/documents`, `/student/idcard` |
| (public) | — | `/verify/document`, `/verify/document/{key}`, `/documents/d/{token}` |
| (redirect) | — | `/student/transcript` → `/student/documents?new=TRANSCRIPT` (`app/student/transcript/page.tsx:7`) |

## 5.4 Screens

### 5.4.1 Documents office — `/credentials/documents` (`app/credentials/documents/Office.tsx`)
`GET /api/v1/documents/dashboard`. Actions: Requests, Issued documents, Policies & templates, Public verification page. Tiles (each a filtered link): New requests (paid, not started), Payment pending (₦ outstanding), Held at clearance, Processing, Quality check, Awaiting release, Ready for delivery, Delivered (+completed), Breaching SLA, Certificates issued (N graduates awaiting), Transcripts issued (full/sessional/mini/statements), Revoked · reissued · flagged (`:65-78`). Charts: Requests by stage (donut), Verification and downloads last 30 days (verifications, not found, downloads; "suspected forgeries" = codes checked ≥3 times never issued), Revenue by document kind, Processing (average days payment→release; by kind; deliveries) (`:80-99`). Panel **"Graduates awaiting a digital certificate"** (graduated, Senate-approved, no active certificate): checkbox (disabled unless cleared), student, programme, award, session, CGPA, class, Cleared/Held pill, **Issue** (signers, cleared only) → `POST /api/v1/documents/certificates`; **Issue N certificate(s)** → modal → `POST …/certificates/bulk` ("One that fails the checks stops the run"); Excel/PDF "Graduates Awaiting Certificate" (`:101-108, 118-122`). Panel "Documents flagged after the record changed" with **Review** (or green "No issued document is flagged") (`:110-114`). Footer: revenue by month and a link to "the earlier transcript queue".

### 5.4.2 Document requests — `/credentials/documents/requests` (`Requests.tsx`)
Filters Stage (Every / Open / New (paid, not started) / Breaching SLA / each stage), Document (4 requestable kinds), Payment (Paid/Pending/Unpaid/No fee), Delivery (Digital/Physical/Both), Faculty, Department, Programme, Search (name, ID, request, document number or code) (`:35-43`; server `DocumentsController.java:259-292`). Rows: request ref (+"SLA" pill or due date), student (status), programme, document (session/semester, document number/version), payment pill + fee, stage pill, delivery (urgent, destination), requested, button **Process / Check / Release / Deliver / Open** by stage (`:45-56`). Excel/PDF "Document Requests" (16 columns).

### 5.4.3 One request — `/credentials/documents/requests/{id}` (`Request.tsx`)
Header ref + stage pill (+"Breaching SLA"). Actions: **Validate the record** (READY/HELD_AT_CLEARANCE/CORRECTION; disabled unpaid) → `…/start`; **Generate the document** (disabled unpaid or when validation not ok) → `…/generate`; **Quality check** (GENERATED; modal Decision Approve / Request correction / Reject, Note/Reason) → `…/qc`; **Authorise and release** (signers, VERIFIED; disabled for the producer with title "The officer who produced a document does not release it") → `…/release`; **Mark completed** (RELEASED/DELIVERED); **Cancel** (AWAITING_PAYMENT/READY/HELD_AT_CLEARANCE); **Document PDF**; **Student record** (`:50-58`). Steps Payment → Ready → Validation → Generated → Quality check → Released → Delivered → Completed. Notices per stage; validation note with findings (error/warning pills). Panels "The request" (document, copies, urgent, delivery, recipient, contact, address, their reference, purpose, fee/payment/receipt), "The document" (number, status, verification code, issued, template, versions), the statement preview or generated statement course by course (programme, entry, standing, CGPA, class, graduation, scope; per session/semester tables with code, title, units, grade, points, quality), "Deliveries" (kind, to, state, courier/tracking, link uses/expiry; **Update** for physical — modal State (all `DELIVERY_STATE`), Courier, Tracking number, Note → `POST /api/v1/documents/deliveries/{id}`; **Resend link** for an email delivery → `…/resend`; **Mark** for the student's token), "Timeline" (`:60-131`).

### 5.4.4 Issued documents register — `/credentials/documents/register` (`Register.tsx`)
Tabs **Documents (n)** / **Verification log (n)**. Filters Kind, Status (Valid/Revoked/Replaced), Flagged, Search. Rows: document (kind, number, vN, Flagged pill + reason), holder, programme/award/class, issued, status pill, verification code (link to `/verify/document/{code}`), "N dl · N ver", **Open**, **PDF** (`/credentials/documents/register/{id}/pdf`, logged as an OFFICE download) (`:78-93`). Modal: code, issued/office, template version, award, class, session, request, downloads, verifications; flags; revocation; Versions; Trail; download/verification excerpts; footer buttons **Clear the flag** (OFFICE), **Reissue (new version)** (SIGNERS, ACTIVE), **Revoke** (REVOKERS, ACTIVE) (`:101-110`). Revoke modal: Reason (required) and **Instrument (the minute)** (required, placeholder "SEN/2026/118") — "Only the Registrar or the Vice-Chancellor revokes, and only citing a Senate or Council minute"; reissue modal: Reason (`:112-118`). Verification log tab: When, Key, Result, Document, Holder, Source (IP); PDF "Document Verifications". Excel/PDF "Issued Documents" (14 columns).

### 5.4.5 Policies & templates — `/credentials/documents/settings` (`Settings.tsx`)
Non-config offices see "You are reading these settings". Panel "Policies by document kind": label, kind and number format `PREFIX/YYYY/NNNNNN`, fee ("Fee schedule" when NULL for the transcript), extras (urgent/physical/intl), SLA (standard / urgent days), self-service, scope (mini-transcript `includes` or "graduates only"), public fields, Active, **Edit** (`:52-64`). Policy modal: Label, Fee (₦; blank = fee schedule for TRANSCRIPT, zero otherwise; disabled when not billable), Urgent processing fee, Physical delivery fee, International delivery fee, Standard processing (working days), Urgent processing (days), "Mini-transcript covers" (current semester / selected semester / selected session / cumulative), checkboxes Billable, Self-service, Graduates only, Active; "Fields shown to a stranger on verification" (holder, matricNo, programme, award, classOfDegree, faculty, department, graduationSession, graduationDate, session, level, standing, cgpa) with the note "Never shown: date of birth, address, phone, email, finances, internal identifiers. Results are never on the public page." → `PUT /api/v1/documents/policies/{kind}` (`:70-92`). Panel "Templates" (kind, version, title/subtitle, signatories, footer, from, In force/Kept) and **New template version** modal (Document, Title*, Subtitle, Signatory*, Signatory's title*, Second signatory, Second signatory's title, Footer, Official remarks; **Put in force**) → `POST /api/v1/documents/templates`; "every document already issued stays under the version it was issued with" (`:65-68, 93-107`).

### 5.4.6 Transcript queue (legacy) — `/credentials/transcripts` (`app/credentials/transcripts/Transcripts.tsx`)
Tiles Open requests, Held at clearance, Breaching SLA ("Over 5 working days"), Average turnaround ("Against a 10-day standard"). Table Request, Student, Destination (mode Sealed/Digital, express, copies), Clearance ("3 of 3" of BURSARY/LIBRARY/DEPARTMENT), SLA day, Stage (Awaiting payment / Held at clearance / Ready to produce / Awaiting Registrar / Released), Action: **Record payment** (signers; `POST …/mark-paid`), "Blocked — {unit}", **Produce & verify** (`POST …/produce` = `produce_transcript` + `qc_transcript(APPROVED,'Verified at the transcript queue')`, `CredentialsRepository.java:78-81`), **Sign & release** (signers; `POST …/release`), "View verification" (a button with no handler) (`:33-79`). Empty: "No transcript request is open… the Academic Office can raise one on a student's behalf through the API." (`POST /api/v1/credentials/transcript-requests` has no screen.)

### 5.4.7 Certificate register (printed) — `/credentials/certificates` (`app/credentials/certificates/Certificates.tsx`)
Tiles Graduands {year}, Certificates printed, Collected, Security stock left ("Reorder at 1,000"). Register table: Certificate no. (`MOAUM/C/YY/NNNNN`), Graduand, Award, Class, Status ("Printed, awaiting collection" with **Collected** and **Hold**; "Collected {date}" with **Reissue** for signers; "Held — reason"; "Reissued — duplicate"; "Revoked"). **Print a certificate** modal (Graduand from the awaiting list, Stationery batch "The next unused serial is taken from it") → `POST /api/v1/credentials/certificates`. Notice about pre-30-December-2024 certificates issued as Benue State University. Panel "Stationery control" (batch, serial range, issued, used, spoiled, returned, **Spoiled one**) and **+ New batch** (Batch, Received on, First serial, Last serial) (`:55-129`). The desk's `/return` endpoint has no button.

### 5.4.8 Identity cards — `/credentials/idcards` (`app/credentials/idcards/IdCards.tsx`)
Tiles Waiting for a card, Live cards, Lost or replaced, Issued today. Notice: "A card is keyed on the matriculation number and released by the scheme — The Library prints it when the Bursary's position releases ID_CARD…; Security hands it over against the photograph on file." Panel "Waiting for a card" (matriculated students in ADMITTED/ACTIVE/PROBATION/DORMANT with no live card; search by matric or surname) with **Issue the card / Issue a replacement** → `POST /api/v1/credentials/identity-cards/students/{id}/issue`. Panel "Cards issued" (card no `MOAUM/ID/YY/NNNNN`, student, issued, valid to, Live/Lost/Replaced, **Report lost** via `window.prompt`) → `…/lost` (`:50-77`). The screen has no printing, no collection recording and no verification: "Card Collection" and "Lost & Replacement" menu items open this same desk.

### 5.4.9 My documents — `/student/documents` (`app/student/documents/Documents.tsx`)
`GET /api/v1/me/documents`. Actions **Request a document**, **Verify a document**. Tiles Certificates, Transcripts & statements, Pending requests, Available downloads. Note "N request(s) in hand" with stage, "pay ₦X against {reference}" and a **PayByCard** control, expected-by date. Panel "Documents issued to you": kind (award/programme/session/version), number, issued, status (Valid/Revoked/Replaced), verification code link, **Download PDF** (`/student/documents/{id}/pdf`, logged), **Secure link** (`POST /api/v1/me/documents/{id}/link {days: 7}` → modal "Valid for seven days; each use is logged" with the URL `/documents/d/{token}`); revoked/superseded rows show the reason (`:75-105`). Panel "My document requests" (ref, type, date, payment, status, delivery, **Timeline**, **Download**). **Wizard** (5 steps; `:121-168`): 1 Select document (kind select with fee or "free"; Academic session for sessional or a session-scoped mini; Semester; explanatory text and "Expected processing time"), 2 Select delivery (Digital / Physical / Both; Copies 1–10; Urgent processing (+fee); International delivery), 3 Recipient (Send to: Myself / An institution / An employer / An embassy / A professional body / Another authorised recipient; Institution/organisation* for a third party; Department/unit; Recipient name; Recipient email — "A secure expiring link is sent here; the document itself is not attached"; Their reference; Postal address* for physical; Purpose), 4 Review the fee (base × copies, urgent, delivery, total), 5 Confirm and submit → `POST /api/v1/me/documents/requests`; 6 done ("Pay ₦X against reference …" with PayByCard, or "The document was issued at once…", or "It is with Exams and Records"). Timeline modal with **Cancel request** (AWAITING_PAYMENT/READY/HELD_AT_CLEARANCE; reason via prompt) and the deliveries.

### 5.4.10 Student identity card — `/student/idcard` (`app/student/idcard/page.tsx`, screen `IdCard` in `app/student/Screens5.tsx`, data from `/api/v1/me/id-card` — student-portal module)
Shows the card as issued or "Not yet issued" / "A card is made after matriculation" / "Your card waits on the Bursary's clearance — Under the scheme in force, the identity card is released at the first instalment." **PDF** `GET /student/idcard/pdf` (`app/student/idcard/pdf/route.ts`): 409 "No identity card issued" without a live card; otherwise an A4 page titled "Rev. Fr. Moses Orshio Adasu University - Student Identity Card" with FRONT (landscape: name, matric number, tag "Student", Faculty, Level, Programme, Blood group (always "—"), Admitted (entry year), Graduates ("—"), footer session and "valid to", serial = card number, passport photograph from `/api/v1/me/passport`, crest) and BACK (barcode of the matric number, serial, "In an emergency" with the reach phone, "PROPERTY OF THE UNIVERSITY · NOT TRANSFERABLE", conditions, "Registrar") (`:19-59`; `lib/idcard-pdf.ts`). No QR and no verification code on the student card.
**Staff card** `GET /staff/idcard/pdf[?id=]` (`app/staff/idcard/pdf/route.ts`): from `/api/v1/hr/staff/me` or `/hr/staff/{id}`; 409 "No staff number" without one; portrait card with name, staff number, Rank, Category (Academic/Non-teaching/Staff), Department or Unit, Faculty, Appointed, Office, "Valid to" = 31 December three years on, serial `STF-{last 8 of staff no}-{year}`, JPEG photo only (`:14-70`). There is **no staff card register**: the serial and validity are computed at print time, nothing is stored.

### 5.4.11 Secure recipient link — `/documents/d/{token}` (`app/documents/d/[token]/page.tsx`, `pdf/route.ts`)
Public. Spends the token (`GET /api/v1/verify/download/{token}`): green "{Kind} {number} — Issued to {holder} ({matric}) · {programme} · issued {date}. This link expires; the verification reference on the document does not." with **Open the document (PDF)** (`/documents/d/{token}/pdf`, which spends the token again) and **Verify it against the record**; or red "This link has expired" / "…used the permitted number of times" / "The document is revoked|replaced" / "This link is not valid" with advice to verify by the reference (`:22-35`).

### 5.4.12 Document PDFs (`lib/document-pdf.ts`)
Rendered from the stored statement under the template version the document was issued with. Degree certificate: the University's own certificate layout — crest top, number top right, "REV. FR. MOSES ORSHIO ADASU UNIVERSITY / MAKURDI, BENUE STATE, NIGERIA", "This is to certify that", holder, award, class, "Having completed an approved course of study", seal and date bottom left, two signatories bottom right (template's second/first signatory, defaults Vice-Chancellor and Registrar), a QR to `/verify/document/{code}` and "Verify this certificate" with the code (`:38-84`). Transcripts/statements: multi-page with matriculation number, programme, sessions and semesters, "GRADING SCALE", class of degree, footer "Not valid without the verification reference.", signatory and QR on the last page (`:98-201`). A REVOKED document prints with a diagonal "REVOKED" watermark, REPLACED with "REPLACED" (`:30-31`).

## 5.5 Workflow and statuses

**Document request** (`credentials.transcript_request.stage`, `ck_tr_stage`): `AWAITING_PAYMENT` (fee > 0) | `HELD_AT_CLEARANCE` (full transcript, TRANSCRIPT clearance not clear) | `READY` (free or paid and clear) → `PROCESSING` (start/validate) → `GENERATED` (document issued vN) → QC: `VERIFIED` | `CORRECTION` (regenerate → GENERATED again as a new version) | `REJECTED` (closed) → `RELEASED` (second officer; deliveries opened) → `DELIVERED` (every delivery DELIVERED, or the student's token spent) → `COMPLETED` (desk). `CANCELLED` by the student or the desk while AWAITING_PAYMENT/READY/HELD_AT_CLEARANCE. Payment confirmation (`finance.confirm_payment` sets `paid_at`) fires `credentials.request_paid`, which stamps `sla_due_on` (standard or urgent days) and logs PAID (`V262:736-748`). A **free self-service** kind (mini-transcript, academic statement as seeded) is generated and RELEASED at once inside `request_document` (`V262:366-370`). The legacy queue (§5.4.6) moves READY → GENERATED → VERIFIED in one click, then RELEASED.

**Document** (`credentials.document_status`): `ACTIVE` | `REVOKED` (row in `credentials.revocation`) | `REPLACED` (a later version supersedes it) (`V262:114-119`). Flags (`flagged_at`) are orthogonal.

**Delivery** (`ck_dl_state`): digital NOT_SENT/READY/SENT/DELIVERED/FAILED/EXPIRED/RESENT; physical PROCESSING/DISPATCHED/IN_TRANSIT/DELIVERED/RETURNED (the desk picks any state; the screen suggests the next). Tokens: STUDENT (50 uses, 30 days at release; 20 uses, 1–90 days when made from the library) and RECIPIENT (10 uses, 30 days), revoked on revocation/reissue.

**Printed certificate** (`credentials.certificate.status`): `PRINTED → COLLECTED | HELD`; `REISSUED` on the original when a duplicate is printed; `REVOKED` exists in the CHECK but no code sets it.

**Identity card** (`ck_card_state`): `ISSUED` → `LOST` (report) | `REPLACED` (a new card issued) | `RETURNED` (in the CHECK, never set); one live card per student (`uq_card_live`).

## 5.6 Business rules and validations
Request (`credentials.request_document`, `V262:315-375`): "no such document kind"; "a document is issued against a matriculation number; the record has none yet" (hint "Matriculation comes first."); "{label} is issued to a graduated student" (graduates_only); "a sessional transcript names its session"; "no published result stands for {session}"; "name the recipient" for a third-party destination; "a physical delivery needs an address"; duplicate within a day "the same request was made within the day and is still in hand" (23505). Controller: `DOC_KIND` "'X' is not a document kind." and "A degree certificate is issued by the Registry, not requested." (`DocumentsController.java:139-140`). Fee = `fee_for` (policy fee or `finance.transcript_fee(session)` for the full transcript × copies + urgent + physical (+ international)); a fee > 0 creates payment reference "Transcript {ref}". Cancel: "request % is %; it is past cancelling" (`:383`).

Validation (`credentials.validate_record`, `:467-497`): ERRORs — no matriculation number; programme not on the reference list; student EXPELLED/RUSTICATED; no published result (for the scope); certificate: not GRADUATED, no Senate-approved award, convocation clearance incomplete; transcript: TRANSCRIPT clearance incomplete. WARNINGs — unpublished registered courses ("issued without them"); not yet graduated; award not APPROVED at Senate. `start_processing`: "request % is not paid; processing begins at payment"; "request % is %". `produce_transcript` (`:603-628`): "request % is not payable yet: the SLA clock runs from payment, and production does"; "request % is held at clearance" (hint: a unit holds the candidate); "the record does not validate: {errors}". QC (`:630-649`): "the quality check approves, asks for a correction or rejects"; "say why"; "request % is %; the quality check is of a generated document". Release (`:680-699`): "request % has not been produced and verified"; **"the officer who produced a transcript does not sign it"** (BR-006). Complete: "request % is %". Resend: `DOC_RESEND` "Only a digital delivery to an email address is resent." (`DocumentsController.java:376`).

Issue (`credentials.issue`, `:501-529`): "a document is issued by a person" (actor required); number from `next_document_number` or inherited on reissue with `version+1` (`uq_issued_number` on number+version); statement enriched with kind, number, version, templateVersion, issuedOn, issuingAuthority; `content_hash` = SHA-256 of the statement text; a new active certificate also links the printed `credentials.certificate` row. Certificate (`issue_certificate`, `:532-548`): `assert_issuable` — "the student record is not GRADUATED", "the award is not Senate-approved", "clearance is incomplete" (hint "BR-001. No office may clear another office's item."); "an active degree certificate already stands; revoke or reissue it" (23505). Bulk issue rolls the whole run back on the first refusal (`DocumentsController.java:483-488`). Revoke (`:550-561`): "document % is already revoked"; `ck_revoke_office` restricts the recorded office to registrar/vc; all tokens revoked. Reissue (`:564-580`): "a reissue carries its reason"; "document % has already been replaced"; the old row's flag is cleared and tokens revoked; the request's `issued_id` moves to the new version. Flags: `trg_score_flags_documents` on `assessment.score` INSERT/UPDATE flags the student's active transcripts/statements ("A result of the student changed after issue"); `trg_graduand_flags_documents` on `records.graduand` UPDATE of cgpa/award/session flags certificates and transcripts ("The award on the record changed after issue") and tells the desk (`:847-880`). Secure link: "document % is %; no link is made for it" unless ACTIVE (`:758`). Token spend (`consume_token`, `:765-785`): NOT_FOUND / REVOKED / EXPIRED / EXHAUSTED / document status; each spend increments uses, logs a download and marks the delivery DELIVERED.

Verification (`credentials.verify_document`, `:813-843`): key upper-cased and trimmed; matched first as a verification code, then as a document number (latest version); NOT_FOUND is logged in `verification` and (via `credentials.verify`) in `lookup_miss` for `suspected_forgeries` (≥3 lookups in 30 days); the status becomes INVALID when the stored hash no longer matches the statement; only the policy's `public_fields` are copied out; every lookup is logged with IP and user agent. API throttle: 40 lookups per 15 minutes per source IP, `VERIFY_THROTTLED` "Too many verifications from this source; try again in a few minutes." (`DocumentsController.java:50-51, 79-92`).

Policies: `ck_dp_kind`, `ck_dp_includes`, `ck_dp_prefix` `^[A-Z]{2,6}$`; `PUT …/policies/{kind}` uses coalesce so an omitted field keeps its value; a fee is cleared when billable is set false (`DocumentsController.java:511-519`). Templates: a new version deactivates the previous; documents keep `template_version`.

Legacy transcript queue (`CredentialsService.java`): `CTP_ALREADY_PAID` "Request … is already paid."; stage on request/mark-paid = AWAITING_PAYMENT or READY/HELD_AT_CLEARANCE by `clearance.is_clear(student,'TRANSCRIPT')` (`:98-103`); SLA = working days from payment, breaching after 5. Certificates: `CRED_NOT_GRADUATED` "No Senate-approved award stands against this student."; `CRED_NOT_CLEARED` "The candidate is held by a unit."; `CRED_BATCH_EXHAUSTED` "Every serial of that batch is used."; `CRED_HELD` "Certificate … is held: …"; `CRED_HOLD_SAYS_WHY` "A held certificate names the reason."; `CRED_REISSUE_SAYS_WHY` "A reissue carries the affidavit and police report reference."; `CRED_BATCH_RANGE` "The serial range runs backwards."; `CRED_COUNT` "A count is a positive number." (`:163-243`). Number `MOAUM/C/YY/NNNNN` (`ck_cert_number`). Identity card (`credentials.issue_identity_card`, `V027:226-250`): "an identity card is keyed on the matriculation number, and % has none yet" (hint "The card is made after matriculation."); "the Bursary has not cleared this student for the identity card in {session}" (hint "The scheme releases the card at the first instalment."; `finance.clears(student, session, 'ID_CARD')`); "a card is issued by a person"; a live card is marked REPLACED; number `MOAUM/ID/YY/NNNNN`; valid four years.

## 5.7 Notifications (`credentials.tell` = email + SMS to the student; `credentials.tell_desk` = email to holders of records/academic)
| Event | Trigger | Recipient | Subject |
|---|---|---|---|
| Request submitted | `request_document` | student; desk (free, non-self-service) | "Document request {ref} submitted"; "A document request awaits" |
| Payment confirmed | `request_paid` trigger | (trail only; no notice) | — |
| Processing started | `start_processing` | student | "Document request {ref} is being processed" |
| Generated | `produce_transcript` | student | "Document request {ref}: document generated" |
| QC approved / correction / rejected | `qc_transcript` | student | "Document request {ref} approved" / "…: correction in hand" / "… rejected" |
| Released | `release_transcript` | student; recipient email (if any) | "Document request {ref}: your document is ready"; "An official document from Rev. Fr. Moses Orshio Adasu University" (secure link) |
| Delivery failed/returned | `mark_delivery` | student; desk | "Delivery of {ref} failed"; "A document delivery failed" |
| All deliveries done | `mark_delivery` | student | "Document request {ref} delivered" |
| Cancelled | `cancel_request` | student | "Document request {ref} cancelled" |
| Certificate issued | `issue_certificate` | student | "Your digital certificate has been issued" |
| Revoked | `revoke_document` | student | "A document of yours has been revoked" |
| Reissued | `reissue_document` | student | "A document of yours has been reissued" |
| Flagged | `flag_documents` | desk | "An issued document may need review" |
| Link resent | `DocumentsController.resend` | recipient | "An official document … (resent)" |
Identity cards, the printed certificate register and the legacy transcript queue send no notices.

## 5.8 Reports, exports and documents
Excel/PDF (branded, serial `DOC-…`): Graduates Awaiting Certificate, Document Requests, Issued Documents, Document Verifications (PDF). Generated PDFs: degree certificate, full/sessional/mini transcript, statement of record (student, office and recipient routes; all with QR + verification code; revoked/replaced watermark); student identity card (front/back, barcode, no QR); staff identity card. The office dashboard's figures (requests by stage, revenue collected/30-day/outstanding by kind and month, average processing days, verification/download counts, suspected forgeries).

## 5.9 Configuration
`credentials.document_policy` seeded (`V262:62-67`; confirmed in the local DB):

| kind | label | billable | fee | SLA days | self-service | prefix | graduates only | public fields |
|---|---|---|---|---|---|---|---|---|
| DEGREE_CERTIFICATE | Degree certificate | no | 0 | 10 | no | CERT | yes | holder, programme, award, classOfDegree, faculty, department, graduationSession, graduationDate |
| TRANSCRIPT | Official full transcript | yes | NULL → `finance.transcript_fee(session)` | 5 | no | TRN | no | holder, programme, faculty, department, award, classOfDegree, graduationSession |
| SESSIONAL_TRANSCRIPT | Sessional transcript | yes | 2000 | 3 | no | STR | no | holder, programme, faculty, department, session |
| MINI_TRANSCRIPT | Mini-transcript | no | 0 | 1 | yes | MTR | no | holder, programme, faculty, department |
| ACADEMIC_STATEMENT | Statement of academic record | no | 0 | 1 | yes | ASR | no | holder, programme, faculty, department, level |
Defaults: urgent/physical/international fees 0, urgent SLA 2 days, includes CUMULATIVE, currency NGN. Templates v1 per kind with signatories (certificate: The Registrar / The Vice-Chancellor; transcript: The Registrar; sessional/mini/statement: Deputy Registrar (Exams and Records) / Exams and Records) (`V262:86-91`). `credentials.signing_key` — no row; nothing signs.

## 5.10 Data
`credentials.issued` (kind; student; verification_code unique, Crockford 5×5; statement jsonb; signature = hash bytes; signed_with NULL; issuing_name; issued_on/at/by/office; supersedes; duplicate_of; number; version; template_version; content_hash; request_id; flagged_at/reason; note), `revocation` (PK credential; reason; instrument; revoked_by/office ∈ registrar/vc), `transcript_request` (ref `TRN-YYYY-NNNNN`; kind; session; semester; destination/name; mode DIGITAL/SEALED; delivery; express; international; copies 1–10; recipient fields; purpose; fee; reference; paid_at; stage; started/validated (validation jsonb)/produced(by)/qc(by,note)/released(by)/delivered/completed/closed(reason); sla_due_on; issued_id), `document_policy`, `document_template`, `event` (write-once trail), `delivery`, `download_token`, `download_log` (exempt), `verification` (exempt), `lookup_miss` (exempt), `certificate`, `stationery_batch`, `identity_card`, `signing_key`. All others on the spine.

## 5.11 Scheduled jobs and integrations
No scheduler. Payments through `finance.new_purpose_reference` / `finance.confirm_payment` (paid_at set by the finance module fires the trigger). Results (`assessment.student_results`, `student_gpa`), graduation (`records.graduand`), clearance (`clearance.is_clear`, `clearance.position`), policy bands (`policy.class_of`, grade/classification bands), PG tables (`admissions.pg_*`). Verification and downloads by strangers write audit-exempt logs.

## 5.12 Security notes
- Public: `/api/v1/verify/document`, `/api/v1/verify/document/{key}`, `/api/v1/verify/download/{token}` (`SecurityConfig.java:56`; the inventory's "Access" column for `/verify/download` is wrong — it is under `/api/v1/verify/**` permitAll). Throttled 40/15 min per IP in memory (per instance); the public answer never includes results or private fields; NOT_FOUND still returns a remedy text.
- Secure-link tokens: 24 random bytes hex, expiry and use limits, revoked with the document; the page and the PDF each spend a use.
- Segregation of duty on release; revocation limited to Registrar/VC both by guard and by CHECK; reissue keeps the old version verifiable as REPLACED.
- Downloads by students/offices/recipients are logged with IP and agent (`download_log`).
- Weakness worth noting: the "signature" is a hash, so a document is tamper-evident only against the University's own store; there is no offline verification as V005 intended (`V005:36-47` versus `V262:26-29`).

## 5.13 Implementation status
| Feature | Status | Evidence | Notes |
|---|---|---|---|
| Policies per kind, templates with versions | IMPLEMENTED | `DocumentsController.java:505-548`; `Settings.tsx` | |
| Student request wizard, fee, payment reference, PayByCard | IMPLEMENTED | `V262:315-375`; `Documents.tsx:121-168` | |
| Free self-service issue at once | IMPLEMENTED | `V262:366-370` | |
| Validation with findings, generation, QC (approve/correction/reject), release by a second officer | IMPLEMENTED | `V262:584-699`; `Request.tsx` | |
| Deliveries: student token, recipient email token, courier tracking, resend, failure notices | IMPLEMENTED | `V262:652-722`; `DocumentsController.java:363-383` | Courier is recorded manually; no carrier integration |
| Degree certificate issue single/bulk with gates | IMPLEMENTED | `V262:532-548`; `Office.tsx:36-51` | Bulk run is all-or-nothing |
| Revoke with instrument; reissue as new version; old REPLACED | IMPLEMENTED | `V262:550-580`; `Register.tsx` | |
| Flags on score/award change; clear flag | IMPLEMENTED | `V262:847-887` | |
| Public verification by code or number, rate limit, verification log, suspected forgeries | IMPLEMENTED | `V262:813-843`; `DocumentsController.java:79-92, 208-220` | |
| Register with versions, trail, downloads, verifications | IMPLEMENTED | `DocumentsController.java:387-423` | |
| Document PDFs (certificate after the University's layout; transcripts) | IMPLEMENTED | `lib/document-pdf.ts` | |
| Cryptographic signing / offline verification | NOT IMPLEMENTED | `V262:26-29`; `signing_key` empty | Hash only |
| Legacy transcript queue | IMPLEMENTED (kept) | `Transcripts.tsx` | "View verification" button does nothing (`:79`); no screen to raise a request on a student's behalf |
| Printed certificate register and stationery | IMPLEMENTED | `Certificates.tsx`; `CredentialsService.java` | `/stationery/{id}/return` has no button; certificate `REVOKED` status never set |
| Identity card issue / report lost (Library, Security) | IMPLEMENTED | `IdentityCardController.java` | No collection record, no card verification: "Verify a Card" (`t/idverify`) is a menu item with no URL — PLACEHOLDER |
| Student card PDF | IMPLEMENTED | `student/idcard/pdf/route.ts` | Blood group / Graduates print as "—"; no QR |
| Staff card PDF | IMPLEMENTED (stateless) | `staff/idcard/pdf/route.ts` | Nothing is stored; validity computed at print |
| `/student/transcript` | IMPLEMENTED as a redirect | `student/transcript/page.tsx` | |
| End-to-end tests | IMPLEMENTED | `DocumentsIT.java`, `CredentialsIT.java` | |

## 5.14 Common problems and troubleshooting
- Student cannot request: "a document is issued against a matriculation number" → not yet matriculated; "no published result stands for {session}" → choose a session with published results; a sessional transcript needs a session; a third-party recipient needs a name; physical delivery needs an address; "the same request was made within the day" → open the existing request.
- Request stuck at "Payment pending" → pay the reference (card or bank); processing starts only after `paid_at`; expired references show "Unpaid".
- "Held at clearance" → a unit (Bursary/Library/Department) holds the student on the TRANSCRIPT clearance; the student's clearance screen names it; the desk cannot generate until clear.
- "Generate the document" disabled → validation has ERROR findings (e.g. no published result, expelled); fix the record, validate again.
- "Authorise and release" disabled → you produced the document; another signer releases.
- Certificate row shows "Held" and no Issue button → convocation clearance incomplete; the certificate is issued only to GRADUATED + Senate APPROVED + cleared.
- Bulk issue failed entirely → one graduate failed a gate; the whole run rolled back; untick or fix and run again.
- Recipient's link "expired/used the permitted number of times" → resend from the request's Deliveries or the student makes a new secure link; the document itself still verifies by its reference.
- Verification says INVALID → stored hash mismatch (statement altered in the database) — a records matter; NOT FOUND → code/number never issued (repeated lookups appear under suspected forgeries).
- "Too many verifications from this source" → 40 per 15 minutes per IP.
- Identity card: "the Bursary has not cleared this student for the identity card" → the ID_CARD release under the fee scheme has not been reached; "keyed on the matriculation number" → not matriculated.

## 5.15 Glossary
Verification code (Crockford base32, 5×5) · Document number (`CERT|TRN|STR|MTR|ASR/YYYY/NNNNNN`) · Version / REPLACED · Statement (the JSON the document renders) · Content hash · Policy · Template version · Self-service kind · Quality check · Release (authorisation by a second officer) · Secure link / download token · Flag · Suspected forgery · Stationery batch / serial · Live card.

---

# 6. The public verification surface  (`app/verify/**`, `app/track`, `app/documents/d/**`; API `verify` + public routes of `credentials` and `helpdesk`)

## 6.1 Purpose
Every printed or downloadable artefact the portal produces carries a QR or a code that opens a public page reading the University's own record, so a forged or altered paper is exposed against the record. `SecurityConfig.java:56` permits `/api/v1/verify/**` and `/api/v1/helpdesk/track` without a token. This section describes the whole surface; the receipt, examination card, registration form, results statement and kept-return checks belong to other groups' modules and are only summarised here.

## 6.2 Entry points
| Page | API | What is checked | Anti-enumeration |
|---|---|---|---|
| `/verify` (`app/verify/page.tsx`) — "Verify a payment": Reference or receipt number + Check code, "Verify payment", camera **Scanner** (`Scanner.tsx`, jsQR; follows only `/verify/…` paths: "That QR is not a MOAUM verification code.") | — | routes to `/verify/receipt/{ref}?c=` | — |
| `/verify/receipt/{reference}?c=` | `GET /api/v1/verify/receipt/{reference}?c=` (`VerifyController.java:49-101`) | a confirmed `finance.payment_reference` by reference or receipt no.; shows payer, matric, programme, level, purpose, session, term, amount, channel, confirmed on, receipt number, passport | token `c` = first 12 hex of SHA-256(`reference|receiptNo`) must match |
| `/verify/exam?m=&s=&sem=&c=` | `GET /api/v1/verify/exam` (`:133-193`) | student name, PHOTO, programme, level, `finance.clears(…,'EXAMINATION')`, approved courses for the session/semester | token SHA-256(`EXAM|matric|session|semester`) |
| `/verify/registration?m=&s=&sem=&c=` | `GET /api/v1/verify/registration` (`:202-242`) | an APPROVED/LOCKED registration: name, programme, level, status, approved on, units, courses (GST/Elective/Core/Carryover) | token `REG|…` |
| `/verify/results?m=&s=&sem=&c=` | `GET /api/v1/verify/results` (`:251-299`) | published results for the semester, GPA, CGPA, class of standing, publication date, Senate minute | token `RESULT|…`; only published rows |
| `/verify/report/{code}` | `GET /api/v1/verify/report/{code}` (`:306-317`) | a kept return (`reports.snapshot`): title, scope, period, taken when/by which office, rows, totals, filed | the code itself (V229) |
| `/verify/putme/{token}` | `GET /api/v1/verify/putme/{token}` (`:324-362`) | Post-UTME slip: candidate, PHOTO, batch, day, time, centre, room, seat, attendance; nothing until the batch is published; warns when POSTPONED/CANCELLED | opaque token |
| `/verify/hostel/{ref}` | `GET /api/v1/verify/hostel/{ref}` (`:369-394`) | allocation letter / clearance certificate: student, PHOTO, hall, block, floor, room, bed, state, stay, check-in, clearance | **none** — sequential `ALC-` reference, no token, no throttle (§1.12) |
| `/verify/document?key=` and `/verify/document/{key}` (`VerifyDocument.tsx`) — "University document verification": field "Verification reference or document number", **Verify document**; answers "VALID DOCUMENT — authentic and currently valid" / "REVOKED — this document was officially revoked" (date, instrument) / "REPLACED — a later version of this document is the official one" / "NOT FOUND — no document bears this reference" / "INVALID — the document could not be validated", then Document type, Number, Status, Issued on, Version, Issued by, Issuing institution and the policy's public fields; footer "Only fields the University has approved for public disclosure are shown." | `GET /api/v1/verify/document[?key=|/{key}]` (`DocumentsController.java:208-220`) | `credentials.verify_document` | 128-bit random code; 40 lookups / 15 min per IP; every lookup logged |
| `/documents/d/{token}` and `/documents/d/{token}/pdf` | `GET /api/v1/verify/download/{token}` (`:222-235`) | spends a secure-link token and returns the statement + template for the PDF | 192-bit token, expiry, use limit, throttle |
| `/track` | `POST /api/v1/helpdesk/track` | ticket standing and non-internal history | number + email, 12 lookups / 15 min per IP and per email |

All pages share the same card layout (crest, "Rev. Fr. Moses Orshio Adasu University, Makurdi", a green "Genuine …" or red "Not verified" note, and a footer "This page reads the University's register directly…").

## 6.3 Notes and gaps
- The landing page `/verify` only offers the receipt form; the other checks are reached from their QR codes (the scanner accepts any `/verify/…` QR).
- Rate limiting exists for document verification, secure links and ticket tracking; the receipt/exam/registration/results/report endpoints rely on their check tokens; the hostel endpoint has neither.
- The verification pages are server-rendered from the API and expose no more than the endpoint returns; photographs are embedded as data URIs.
- Implementation status: all nine verification routes and their pages are IMPLEMENTED (`routes.md` lines 287-296; `VerifyController.java`; `DocumentsController.java`). No verification for identity cards exists (the CSO's "Verify a Card" item is a placeholder without a page).
