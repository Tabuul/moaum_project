"use client";

/** t/paymenthistory — Payment History Upload (V120), retired by V498. It wrote old payments blind to Old Fees History —
 *  every row as school fees, no semester, its own references — so the same export through both screens counted each payment
 *  twice and the two contradicted each other. Old payments now come in on Old Fees History alone; what this screen recorded
 *  twice is listed and withdrawn there. The page stays for old bookmarks and says where to go. */
import { LinkBtn, Note } from "@/components/proto/ui";

export function PaymentsHistory({ actingOffice }: { actingOffice: string | null }) {
  void actingOffice;
  return (
    <Note kind="info" title="Payment History Upload is retired: use Old Fees History"
      action={<LinkBtn kind="primary" href="/finance/legacy-fees">Open Old Fees History</LinkBtn>}>
      Old-portal payments are loaded on <b>Finance → Old Fees History</b>, the one way in. It reads the old portal&rsquo;s export as it is
      (matno, payref, payment item, semester), tells one payment from another by the old portal&rsquo;s payment number, and never records a
      payment twice. This screen recorded every row as school fees, without the semester, and could not see what Old Fees History had
      loaded, so the two contradicted each other. Anything it recorded twice is listed on Old Fees History under <b>Recorded twice</b>,
      where the Bursary withdraws it; the reconciliation with the fee setup is there too.
    </Note>
  );
}
