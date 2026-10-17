/**
 * V527: the school-fees payments the Bursary reallocated on a student's account — one credited to it in error and moved to the
 * student it belongs to, or the student's own moved onto it — said on the fees page and on the student record. A student never
 * sees who the other student is; the staff record shows the other student's number.
 */
import { Note } from "@/components/proto/ui";
import { money } from "@/lib/format";
import { formatDocDateTime } from "@/lib/document/institution";

export interface PaymentCorrection {
  swap_ref: string; kind: string; reference: string; amount: number; session: string; direction: "AWAY" | "TO"; executed_at: string | null;
  status: string; other_matric?: string | null;
}

export function PaymentCorrections({ items, staff }: { items: PaymentCorrection[]; staff?: boolean }) {
  if (!items.length) return null;
  return (
    <Note kind="info" title={items.length === 1 ? "A school fees payment on this account was corrected by the Bursary" : "School fees payments on this account were corrected by the Bursary"}>
      {items.map((c) => (
        <div key={c.swap_ref + c.direction}>
          <b className="tnum">{c.reference}</b> ({money(Number(c.amount))}, {c.session}){" "}
          {c.direction === "AWAY"
            ? <>was credited here in error and reallocated{staff && c.other_matric ? <> to <span className="tnum">{c.other_matric}</span></> : null}; it no longer counts towards these fees</>
            : <>was reallocated to this account{staff && c.other_matric ? <> from <span className="tnum">{c.other_matric}</span></> : null}; it counts towards these fees</>}
          {" "}— correction <span className="tnum">{c.swap_ref}</span>, {formatDocDateTime(c.executed_at)}{c.status === "REVERSED" ? " (since reversed)" : ""}.
        </div>
      ))}
    </Note>
  );
}
