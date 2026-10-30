# Hostels: the University's workbook, the 48-hour deadline, late money and room alerts (V705)

The University's hostel brief of 30 October 2026 ("Upgrade the University hostel management system") asked for the Dean of Student
Affairs' hostel desk, the Bursar's hostel fees, eligibility on school fees and course registration, reservations held 48 hours,
special, Student Union and Security rooms, the import of the hostel workbook, accountability and finance reports.

Most of it has been on the portal since 28 September 2026 (V030, V261, V290, V291; `HostelUpgradeIT` walks the brief's own test
scenarios). V705 closes what reading the brief against the code, and the University's own workbook against the import, found missing.

## The University's workbook imports as it stands

The file is the old portal's export (`Hostel_Rooms.xlsx`, 28 September 2026): 14 hostels, 585 rooms, 2,520 beds, rooms of 2 to 14.
Two things in it did not fit the import before:
* **A "Block" there is a hostel.** The Hostel Rooms sheet names it by *Block ID* and *Block Name*, with no hostel column. The import
  now reads Block Name as the hostel and Block ID as its **ID on the old portal** (`hostel.hall.legacy_ref`). A later workbook finds
  the hostel by that ID, whatever its name.
* **Two different hostels are both called "New Ultra-Modern Hostel"** (Western Wing, and Eastern Wing, 2nd Camp). They stay two:
  a name two IDs share is told apart by its location ("New Ultra-Modern Hostel, Western Wing" and "…, Eastern Wing (2nd Camp)"),
  and their codes carry the ID (NUH14, NUH15). Other hostels get their initials (CSH, FMB, TBC, MB2 …).

Also:
* **Gender.** Each hostel's gender is on the *Hostel Blocks* sheet. The import screen reads it from that sheet by the hostel's ID
  and says so; it becomes the hostel's gender, not each room's.
* **Location.** The hostel's location (Western Wing, Eastern Wing …) is saved on the hostel.
* **Rooms.** "Room A1" is saved as room A1, because every screen already says "Room". A room saved earlier either way is matched,
  never duplicated.
* **Footer rows.** The *Total* and *Source:* lines under the data are left out, and the screen says how many.

On a copy with the whole workbook the preview gives 585 new rooms in 14 hostels. A second import changes nothing (585 EXISTING).

**To import:** Hostel Management → Import Hostels & Rooms → `Hostel_Rooms.xlsx` → Preview → Import. Then mark special, Student
Union and Security rooms on Hostels, Rooms & Categories. The old portal's *Reservation* column (1,066 of 2,388 beds held back) is per
hostel, not per room, so it cannot say which rooms they were.

## A capacity is never cut below a held bed

Lowering a room's capacity used to turn the beds above it out of service, even with a student in one. Now the database refuses it
(`HOSTEL_CAPACITY_BELOW_OCCUPANCY`, a trigger on `hostel.room`), and the import's preview marks such a row ERROR ("Bed 2 is held or
occupied"). The room board's capacity is the room's own bed count.

## The 48 hours are 48 hours

* **The reference expires with the hold.** A hostel fee reference for a held bed expires when the hold does, not 24 hours after it
  was made. The gateways refuse an expired reference, so nobody pays after the deadline.
* **An expired hold holds nothing.** Past its deadline a reservation no longer counts in the room lists, the room board or the bed
  board, whether or not the clock has run. A student's reservation, and the Dean's and the desk's allocations, lapse expired holds
  first, so the bed is free at once.
* **The clock runs every five minutes** (it was hourly). It writes the expiry, tells the student and sends the reminders.
* **The lapse happens once.** If the clock and a reservation reach the same hold together, the second passes it over, so nobody is
  told twice.

## Money is never refused

A payment that reached the gateway before the deadline can be confirmed after it. Before V705, if the bed had gone to someone else,
the hostel step raised an error and rolled the whole payment confirmation back, leaving paid money unconfirmed. Now:
* **The money is confirmed as money.** The reservation stays expired.
* **The event is recorded** on the hostel record (PAYMENT_AFTER_EXPIRY).
* **Everyone is told:** the student, the Dean of Student Affairs and the hostel desk, and the Bursary (`hostel.tell_bursary`).
  The Bursary refunds the money, or the Dean allocates a bed that is free.

If the bed is still free and the student holds no other bed, the payment confirms the stay as before.

## "Notify me when a suitable room becomes available"

When no room of the student's choice is free, the student's Hostel page offers **Notify me when a suitable room becomes available**:
* **The choice.** The hostel and room type picked in the filters, or any.
* **Who may set one.** Only a student who is eligible, holds no bed and whose window is open (`hostel.watch_rooms`).
* **One at a time.** One alert a session; a new one replaces it, and the student may cancel it.
* **Telling.** The clock tells the student once, by email and SMS, when a room they could reserve under the same rule as the room
  list has a free bed (`hostel.tell_watchers`). The page then says which room it was. The alert is not a reservation.
* **Ending.** An alert ends when the student reserves or is allocated a bed, or when the window closes.

## Lagos days

The databases run in UTC (V539). Every hostel rule that read `current_date` reads the Lagos day: the window's opening and closing
dates, the sanctions, the checkout requests, the desk's notices. Nine functions were rewritten in place, and the migration fails if
one still reads `current_date`. The check proves it under three session time zones.

## The Dean's dashboard and notices

* **Room figures** (`hostel.room_kpis`):
  * rooms and their capacity;
  * full rooms and maintenance rooms;
  * special, Student Union and Security rooms, with their beds and occupants;
  * reservations awaiting payment;
  * applications waiting;
  * students waiting for a room alert.
* **The desk's notices** (`hostel.tell_desk`) now reach the Dean of Student Affairs as well as the housing desk and Student Services.

## Not changed

**School fees for eligibility** still means the session's school fees paid in full (`finance.position`), as V290 stated it. A
student paying by semester applies once both semesters are paid.

## Checks

* **check.sql** gains V705 (made-up hostels and students): the workbook import, the capacity guard, the window under three time
  zones, the reference and the hold, the expired bed taken before the clock, late money, and an alert told once.
* **`HostelDeadlineAndWorkbookIT`** covers the same through the API, with the dashboard's room figures.
* **`lib/hostel-import.test.ts`** covers the column mapping of the old portal's headings.
