# Payment History: one student's payments by matriculation number (Oct 2026)

**Where:** Bursar → Reports → **Payment History**; Students Account Officer → Payment Reports → **Payment History**
(`t/studentpaymenthistory`, `/finance/student-payment-history`).

The retired Payment History Upload (`t/paymenthistory`, `/finance/payments-history`, V120, retired by V498) is a different page and
is in no menu.

## What it does

- **Search.** Type the matriculation number and press **Search**. The admission number, JAMB number or a name also work.
  - The portal's student search finds the student (`/api/v1/student/search?kind=students`), and every search is written to the audit trail.
  - A number typed in full opens the student at once. A partial number lists the matches to choose from.
  - The number goes into the address (`?n=`), so the page can be reloaded or shared with a colleague who holds the same office.
- **Payment history** (the default view) shows the student's payments exactly as the Student 360° record's Fees and payments tab
  shows them:
  - the totals;
  - the school fees by session (due, paid, outstanding);
  - every payment with its date, session, semester, purpose, amount, status, channel and **View receipt** (the official receipt with
    its QR, Print and Download PDF), filtered by kind (All, School fees, Other payments) and by session, with Excel;
  - refunds, overpayments decided, payments withdrawn, the old e-wallet and the wallet, where the student has any;
  - school-fees payment swaps on the account.
- **View biodata** shows the student's biodata read-only, in the record's own sections: no field can be changed from this page.
- **Course registration** shows every course registration (session, semester, level, units, status, who approved it, the courses)
  and every reset, with Excel.
- **Full record (Student 360°)** opens the whole record.

Each view is the record's own section (`/api/v1/student/students/{id}/full/finance`, `/full/registrations`,
`/api/v1/student/students/{id}`). Nothing is worked out on this page, and the server refuses a section to an office that does not
read it. The Bursar and the Students Account Officer read all three.
