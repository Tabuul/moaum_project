/**
 * V527: the school-fees payments the Bursary reallocated on a student's account — one credited to it in error and moved to the
 * student it belongs to, or the student's own moved onto it — said on the fees page and on the student record. A student never
 * sees who the other student is; the staff record shows the other student's number.
 * V649: and the Bursary's corrections of the student's own payments to another purpose or period (direction PURPOSE) — the same
 * payment, never a second one.
 */
import { Note } from "@/components/proto/ui";
import { money } from "@/lib/format";
import { formatDocDateTime } from "@/lib/document/institution";

export interface PaymentCorrection {
  swap_ref: string; kind: string; reference: string; amount: number; session: string; direction: "AWAY" | "TO" | "PURPOSE"; executed_at: string | null;
  status: string; other_matric?: string | null;
  /** V649: a correction to another purpose or period */
  from_purpose?: string | null; from_session?: string | null; to_purpose?: string | null; balance_after?: number | null;
}

export function PaymentCorrections({ items, staff }: { items: PaymentCorrection[]; staff?: boolean }) {
  if (!items.length) return null;
  return (
    <Note kind="info" title={items.length === 1 ? "A payment on this account was corrected by the Bursary" : "Payments on this account were corrected by the Bursary"}>
      {items.map((c) => (
        <div key={c.swap_ref + c.direction}>
          <b className="tnum">{c.reference}</b> ({money(Number(c.amount))}, {c.direction === "PURPOSE" ? c.from_session ?? c.session : c.session}){" "}
          {c.direction === "PURPOSE"
            ? <>was applied to {c.from_purpose} and {c.kind === "REVERSAL" ? "was put back as" : "now counts as"} {c.to_purpose}{c.balance_after != null && Number(c.balance_after) > 0 ? <>; {money(Number(c.balance_after))} is left to pay</> : null}. It is the same payment — nothing was paid twice</>
            : c.direction === "AWAY"
              ? <>was credited here in error and reallocated{staff && c.other_matric ? <> to <span className="tnum">{c.other_matric}</span></> : null}; it no longer counts towards these fees</>
              : <>was reallocated to this account{staff && c.other_matric ? <> from <span className="tnum">{c.other_matric}</span></> : null}; it counts towards these fees</>}
          {" "}— correction <span className="tnum">{c.swap_ref}</span>, {formatDocDateTime(c.executed_at)}{c.status === "REVERSED" ? " (since reversed)" : ""}.
        </div>
      ))}
    </Note>
  );
}
