"use client";

/**
 * V654: a graduate's historical school fees on their own fees page — each session and semester of their record with what is owed,
 * as the Bursary has assessed it (a semester still being assessed is shown as such, never as a debt), the total outstanding, and a
 * reference to pay a session's balance online (outside the session's payment window, never more than is owed). The payment is the
 * session's school fees; the receipt says so.
 */
import { useState } from "react";
import { Btn, Note, Panel, PBody } from "@/components/proto/ui";
import { Field } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import { HistoricalAccount, HistoricalTotals } from "@/components/finance/HistoricalAccount";
import { bySession, naira, num, type Period } from "@/lib/historical-fees";
import { PayByCard, useAct } from "../common";

export interface HistoricalFees {
  periods: Period[]; graduated: boolean; graduationSession: string | null; onlinePayment: boolean;
  open: { reference: string; session: string; amount: number | string; expires_at: string }[]; reference?: string;
}

export function HistoricalFeesStudent({ data }: { data: HistoricalFees }) {
  const { act, busy, problem } = useAct();
  const owing = bySession(data.periods).filter((g) => g.outstanding > 0);
  const [session, setSession] = useState(owing[0]?.session ?? "");
  const [amount, setAmount] = useState(owing[0] ? String(owing[0].outstanding) : "");
  const [made, setMade] = useState<{ reference: string; amount: number } | null>(null);
  const chosen = owing.find((g) => g.session === session) ?? null;
  const amt = Number(amount.replace(/[^0-9.]/g, ""));

  async function pay() {
    const j = await act("hist", "POST", "/me/historical-fees/references", { session, amount: amt }, `Historical school fees reference for ${session}`, "");
    if (j && typeof j.reference === "string") setMade({ reference: j.reference, amount: amt });
  }

  return (
    <Panel title="Historical school fees" right={data.graduationSession ? `Graduated ${data.graduationSession}` : undefined}>
      <PBody>
        <Note kind={owing.length ? "bad" : "ok"} title={owing.length ? "School fees from your sessions remain unpaid" : "No historical school fees are owed on what is assessed"}>
          Your academic status is graduated; it does not change because of a balance. The Bursary clears you financially once every session of your record is settled.
          Amounts are the University&rsquo;s fees for each session at your level then, or an amount the Bursar approved for you.
        </Note>
        <HistoricalTotals periods={data.periods} />
        <div className="mt-2"><HistoricalAccount periods={data.periods} studentView /></div>
        {data.open.map((o) => (
          <div key={o.reference} className="card mt-2"><div className="card__body">
            <div className="sub2">Reference <b className="tnum">{o.reference}</b> · {o.session} · {naira(o.amount)} · expires {new Date(o.expires_at).toLocaleString("en-GB", { timeZone: "Africa/Lagos" })}</div>
            <div className="row mt-2"><PayByCard reference={o.reference} amount={num(o.amount)} /></div>
          </div></div>
        ))}
        {made ? (
          <div className="card mt-2"><div className="card__body">
            <div className="tnum b700">{made.reference}</div>
            <div className="sub2">School fees {session} (historical) · {naira(made.amount)}. Pay by card now, or at a bank with this reference within 24 hours.</div>
            <div className="row mt-2"><PayByCard reference={made.reference} amount={made.amount} /></div>
          </div></div>
        ) : owing.length && data.onlinePayment ? (
          <div className="row row--end mt-2" style={{ flexWrap: "wrap" }}>
            <Field id="hf-pay-ses" label="Session">
              <select id="hf-pay-ses" className="ctl" value={session} onChange={(e) => { setSession(e.target.value); setAmount(String(owing.find((g) => g.session === e.target.value)?.outstanding ?? "")); }}>
                {owing.map((g) => <option key={g.session} value={g.session}>{g.session} — {naira(g.outstanding)} outstanding</option>)}
              </select>
            </Field>
            <Field id="hf-pay-amt" label="Amount (₦)" hint={chosen ? `Up to ${naira(chosen.outstanding)}` : undefined}>
              <input id="hf-pay-amt" className="ctl tnum" inputMode="decimal" value={amount} onChange={(e) => setAmount(e.target.value)} />
            </Field>
            <Btn kind="primary" disabled={busy !== null || !chosen || !(amt > 0) || amt > (chosen?.outstanding ?? 0)} onClick={pay}>{busy === "hist" ? "Generating…" : "Pay outstanding school fees"}</Btn>
          </div>
        ) : owing.length ? <div className="sub2 mt-2">Settle your balance with the Bursary; it is recorded against the session it belongs to.</div> : null}
        {problem ? <ProblemNotice problem={problem} /> : null}
      </PBody>
    </Panel>
  );
}
