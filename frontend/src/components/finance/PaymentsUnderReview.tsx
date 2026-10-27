/**
 * V670: the payments on a student's account archived for review by the Bursary — under review (not counted in the verified
 * payments until verified), excluded for good (a duplicate record, or money never received), or verified and counted again — said
 * apart from the verified payments, on the fees page and on the student record. Nothing of another student is ever said.
 */
import { Note, Pil } from "@/components/proto/ui";
import { money } from "@/lib/format";
import { formatDocDateTime } from "@/lib/document/institution";
import { STATE_WORDS, isOpen, underReviewNote, type MyArchive } from "@/lib/payment-archive";

export function PaymentsUnderReview({ items }: { items: MyArchive[] }) {
  if (!items.length) return null;
  const note = underReviewNote(items, (n) => money(n));
  return (
    <Note kind={note ? "bad" : "info"} title={note ?? "Payments the Bursary reviewed on this account"}>
      {items.map((a) => (
        <div key={a.archive_ref}>
          <b className="tnum">{a.reference}</b> ({money(Number(a.amount))}, {a.purpose}, paid {formatDocDateTime(a.paid_at)}){" "}
          <Pil kind={STATE_WORDS[a.state]?.[0] ?? "grey"}>{isOpen(a.state) ? "Under review" : STATE_WORDS[a.state]?.[1] ?? a.state}</Pil>{" "}
          {isOpen(a.state) ? "— not counted in your verified payments until the Bursary verifies it."
            : a.state === "RECONCILED" ? "— verified; it counts in your verified payments."
            : a.state === "DUPLICATE_CONFIRMED" ? "— a second record of a payment already counted; it is not counted twice."
            : "— the money never reached the University's account; it is not counted."}
          {" "}<span className="sub2 tnum">{a.archive_ref}</span>
        </div>
      ))}
      {note ? <div className="sub2" style={{ marginTop: 4 }}>If you made a payment under review, keep your bank or gateway receipt; the Bursary may ask for it. Nothing has been deleted and you have not been charged.</div> : null}
    </Note>
  );
}
