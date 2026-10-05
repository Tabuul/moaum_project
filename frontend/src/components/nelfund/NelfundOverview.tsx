"use client";
/** The Bursary's NELFUND questions answered for a session (V327): received, funded, applied, remaining, refundable, refunds by state,
 *  the old portal's money posted or waiting, who is short and by how much — and the one policy the Bursar keeps: the order the sources
 *  settle a charge in, whether a top-up may exceed the shortfall, which natures may be refunded. */
import { useState } from "react";
import { useRouter } from "next/navigation";
import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, KvGrid, Note, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { Field, money } from "@/components/proto/blocks";
import type { Problem } from "@/lib/api";
import type { NelfundFigures, WalletPolicy } from "@/lib/wallet";

const NAT: Record<string, string> = { LOAN: "Loans (NELFUND)", GRANT: "Grants (scholarships, sponsors)", SELF: "The student's own money" };
const parseArr = (s: string | null | undefined): string[] => (s ?? "").replace(/[{}"]/g, "").split(",").map((x) => x.trim()).filter(Boolean);

export function NelfundOverview({ figures, policy, session, canSet, onStudents }: { figures: NelfundFigures; policy: WalletPolicy; session: string; canSet: boolean; onStudents: (filter: string) => void }) {
  const router = useRouter();
  const f = figures;
  const n = (x: number | string | null | undefined) => Number(x ?? 0).toLocaleString();
  const [order, setOrder] = useState<string[]>(parseArr(policy.apply_order));
  const [over, setOver] = useState<boolean>(policy.topup_over_shortfall);
  const [refund, setRefund] = useState<string[]>(parseArr(policy.refund_natures));
  const [busy, setBusy] = useState(false);
  const [problem, setProblem] = useState<Problem | null>(null);

  async function save() {
    setBusy(true); setProblem(null);
    try {
      const r = await fetch("/api/bff/api/v1/nelfund/policy", { method: "PUT", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader("Wallet policy set: the order sources settle a charge, top-up above the shortfall, refundable natures") },
        body: JSON.stringify({ applyOrder: order, topupOverShortfall: over, refundNatures: refund }) });
      const j = await r.json().catch(() => null);
      if (!r.ok) { setProblem(j ?? { status: r.status, title: r.statusText }); notifyProblem(j ?? { status: r.status, title: r.statusText }); return; }
      notify("Wallet policy saved"); router.refresh();
    } finally { setBusy(false); }
  }
  const move = (i: number, d: -1 | 1) => { const a = [...order]; const j = i + d; if (j < 0 || j >= a.length) return; [a[i], a[j]] = [a[j], a[i]]; setOrder(a); };

  return (
    <>
      <Tiles items={[
        ["NELFUND received", money(Number(f.received)), null, `Remittances and the old portal · ${n(f.students_funded)} students funded`],
        ["Applied to fees", money(Number(f.nelfund_applied)), null, "Settled the session charges"],
        ["Remaining on wallets", money(Number(f.nelfund_remaining)), null, "Credited, not yet applied or refunded"],
        ["Refundable", money(Number(f.nelfund_refundable)), Number(f.nelfund_refundable) ? "var(--chrome)" : null, `${n(f.students_refundable)} student${Number(f.students_refundable) === 1 ? "" : "s"} · the Fund's money after the fees were paid`],
      ]} />
      <Tiles items={[
        ["Refunds pending", n(f.refunds_pending), Number(f.refunds_pending) ? "var(--red-ink)" : null, `${money(Number(f.refunds_pending_amount))} awaiting a decision`, undefined],
        ["Approved, to pay", n(f.refunds_approved), Number(f.refunds_approved) ? "var(--chrome)" : null, "A second officer pays"],
        ["Refunds paid", n(f.refunds_paid), "var(--green-ink)", money(Number(f.refunds_paid_amount))],
        ["Rejected", n(f.refunds_rejected), null, "With the reason, on the record"],
      ]} />
      <Tiles items={[
        ["Students with a shortfall", n(f.students_shortfall), Number(f.students_shortfall) ? "var(--red-ink)" : null, `${money(Number(f.shortfall_amount))} in all · ${n(f.students_topup)} may top up now`],
        ["Paid before the Fund arrived", n(f.students_paid_before_fund), null, "Fees settled by other means; the Fund's money is refundable"],
        ["Old portal posted", money(Number(f.legacy_posted)), null, `${n(f.legacy_posted_rows)} payments on wallets`],
        ["Old portal waiting", n(f.legacy_review_rows), Number(f.legacy_review_rows) ? "var(--red-ink)" : null, `${money(Number(f.legacy_review_amount))} for an officer to resolve`],
      ]} />
      <div className="grid grid--2">
        <Panel title="The questions, answered" right={session}>
          <PBody>
            <KvGrid cls="grid--2" pairs={[
              ["How much NELFUND has the University received?", money(Number(f.received))], ["How many students received it?", n(f.students_funded)],
              ["How much has been used for fees?", money(Number(f.nelfund_applied))], ["How much remains?", money(Number(f.nelfund_remaining))],
              ["How much is refundable?", money(Number(f.nelfund_refundable))], ["How much has been refunded?", money(Number(f.refunds_paid_amount))],
              ["How much is pending refund?", money(Number(f.refunds_pending_amount))], ["How much came from the old portal?", money(Number(f.legacy_posted))],
              ["Scholarships and sponsors credited", money(Number(f.grants_credited))], ["Students' own top-ups", money(Number(f.self_credited))],
            ]} />
            <div className="row row--inline row--tight mt-2" style={{ flexWrap: "wrap" }}>
              <Btn kind="ghost" size="sm" onClick={() => onStudents("SHORTFALL")}>Who has a shortfall?</Btn>
              <Btn kind="ghost" size="sm" onClick={() => onStudents("TOPUP")}>Who may top up?</Btn>
              <Btn kind="ghost" size="sm" onClick={() => onStudents("REFUNDABLE")}>Who is eligible for a refund?</Btn>
              <Btn kind="ghost" size="sm" onClick={() => onStudents("PAID_BEFORE_FUND")}>Who paid before the Fund?</Btn>
              <Btn kind="ghost" size="sm" onClick={() => onStudents("LEGACY")}>Who was funded on the old portal?</Btn>
            </div>
          </PBody>
        </Panel>
        <Panel title="Wallet policy" right={policy.updated_at ? <span className="sub2">Set {new Date(policy.updated_at).toLocaleDateString("en-GB")} by {policy.updated_office ?? "the Bursary"}</span> : <Pil kind="grey">Default</Pil>}>
          <PBody>
            {problem ? <Note kind="bad" title={problem.title}>{problem.detail}</Note> : null}
            <div className="sub2 mb-1">The order the wallet&rsquo;s sources settle a charge in. The loan first means the Fund&rsquo;s money is used before a grant or the student&rsquo;s own.</div>
            {order.map((k, i) => (
              <div key={k} className="row row--inline row--tight mb-1"><b style={{ minWidth: 24 }}>{i + 1}.</b><span style={{ minWidth: 220 }}>{NAT[k] ?? k}</span>
                {canSet ? <><Btn kind="ghost" size="sm" disabled={i === 0} onClick={() => move(i, -1)}>Up</Btn><Btn kind="ghost" size="sm" disabled={i === order.length - 1} onClick={() => move(i, 1)}>Down</Btn></> : null}</div>
            ))}
            <Field id="wp-over" label="A top-up above the shortfall"><select id="wp-over" className="ctl" value={over ? "yes" : "no"} disabled={!canSet} onChange={(e) => setOver(e.target.value === "yes")}><option value="no">Not allowed — exactly the shortfall (default)</option><option value="yes">Allowed, by University policy</option></select></Field>
            <Field id="wp-refund" label="What a student may have refunded" hint="A grant is never refunded through the wallet">
              <span className="row row--inline row--tight" style={{ flexWrap: "wrap" }}>
                {(["LOAN", "SELF"] as const).map((k) => <label key={k} className="row row--inline row--tight"><input type="checkbox" disabled={!canSet} checked={refund.includes(k)} onChange={(e) => setRefund(e.target.checked ? [...refund, k] : refund.filter((x) => x !== k))} /> {NAT[k]}</label>)}
              </span>
            </Field>
            {canSet ? <Btn kind="primary" disabled={busy} onClick={() => void save()}>Save the policy</Btn> : <div className="sub2">The Bursar sets the policy.</div>}
          </PBody>
        </Panel>
      </div>
    </>
  );
}
