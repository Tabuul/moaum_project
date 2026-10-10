"use client";

/**
 * V383: Interswitch test references on the Bursary's screen — a small reference
 * against a named student for Interswitch's testers, payable for the days the
 * Bursar chooses (1 to 14, 7 unless said), so a certification test that runs over
 * several days does not fail on the 24-hour expiry of a fee reference. The purpose
 * is "Gateway test by the Bursary", which counts for nothing against the fees.
 * Quickteller is answered for it as for every reference: Status 0 while it is
 * unpaid and unexpired, Status 1 once it is paid, expired or withdrawn.
 */
import { useState } from "react";
import { DTable } from "@/components/proto/DTable";
import { Field, money } from "@/components/proto/blocks";
import { Btn, Note, Pil } from "@/components/proto/ui";
import { OUTCOME, when, type PaydirectTestReference } from "@/lib/bursary";

type Send = (path: string, body: unknown, reason: string, method?: string) => Promise<Record<string, unknown> | null>;

const STATE: Record<PaydirectTestReference["state"], [string, "ok" | "info" | "grey"]> = {
  OPEN: ["Open — answered 0", "ok"],
  PAID: ["Paid", "info"],
  EXPIRED: ["Expired — answered 1", "grey"],
  WITHDRAWN: ["Withdrawn — answered 1", "grey"],
};
const DAYS = Array.from({ length: 14 }, (_, i) => i + 1);

export function InterswitchTestReferences({ refs, may, busy, send, say }: { refs: PaydirectTestReference[]; may: boolean; busy: boolean; send: Send; say: (s: string) => void }) {
  const [form, setForm] = useState({ number: "", amount: "100", days: "7" });
  const [issued, setIssued] = useState<PaydirectTestReference | null>(null);
  const amount = Number(form.amount);
  const amountOk = form.amount.trim() !== "" && amount > 0 && amount <= 10000;

  function copy(s: string) {
    void navigator.clipboard?.writeText(s).then(() => say("Copied: " + s), () => say(s));
  }

  return (
    <>
      <div className="b700">Interswitch test references</div>
      <div className="sub2">
        A fee reference expires after 24 hours (Status 1). A test reference stays payable for the days chosen here and counts nothing against the student&rsquo;s fees; Quickteller is answered Status 0 until it is paid, expires or is withdrawn.
      </div>
      {may ? (
        <>
          <div className="grid grid--3 mt-2">
            <Field id="itr-num" label="Student" hint="Matriculation or admission number.">
              <input id="itr-num" className="ctl tnum" value={form.number} onChange={(e) => setForm({ ...form, number: e.target.value })} placeholder="MOAUM/…" />
            </Field>
            <Field id="itr-amt" label="Amount (₦)" hint="At most ₦10,000; ₦100 is enough." error={form.amount.trim() !== "" && !amountOk ? "Above zero and at most ₦10,000." : undefined}>
              <input id="itr-amt" className="ctl tnum" inputMode="decimal" value={form.amount} onChange={(e) => setForm({ ...form, amount: e.target.value.replace(/[^0-9.]/g, "") })} />
            </Field>
            <Field id="itr-days" label="Payable for" hint="From now; 1 to 14 days.">
              <select id="itr-days" className="ctl" value={form.days} onChange={(e) => setForm({ ...form, days: e.target.value })}>
                {DAYS.map((d) => <option key={d} value={String(d)}>{d === 1 ? "1 day" : `${d} days`}{d === 7 ? " (a week)" : d === 14 ? " (two weeks)" : ""}</option>)}
              </select>
            </Field>
          </div>
          <div className="row">
            <Btn kind="primary" disabled={busy || !form.number.trim() || !amountOk} onClick={async () => {
              const j = await send("/paydirect/test-references", { number: form.number.trim(), amount, days: Number(form.days) },
                `Interswitch test reference issued for ${form.number.trim()}, payable for ${form.days} day${form.days === "1" ? "" : "s"}`);
              if (j) setIssued(j as unknown as PaydirectTestReference);
            }}>Issue a test reference</Btn>
          </div>
        </>
      ) : null}
      {issued ? (
        <Note kind="ok" title={<>Test reference <span className="tnum">{issued.reference}</span></>} action={<Btn kind="ghost" onClick={() => copy(issued.reference)}>Copy</Btn>}>
          {issued.payer} ({issued.number}), {money(Number(issued.amount))}, payable until {when(issued.expires_at)} &mdash; {issued.days} day{issued.days === 1 ? "" : "s"}. Give it to Interswitch&rsquo;s testers.
          {issued.link ? <> A payer sent to Quickteller lands on <span className="tnum">{issued.link}</span>.</> : null}
        </Note>
      ) : null}
      {refs.length ? (
        <DTable cols={["Reference", "Student", "Amount|num", "Payable until|mid", "State|mid", "Quickteller's checks", ""]} rows={refs.map((r) => [
          <span className="tnum" key="r">{r.reference}<div className="sub2">Issued {when(r.generated_at)}{r.issued_by_name ? ` by ${r.issued_by_name}` : ""}</div></span>,
          <span key="s">{r.payer}<div className="sub2 tnum">{r.number}</div></span>,
          <span className="tnum" key="a">{money(Number(r.amount))}</span>,
          <span className="sub2 tnum" key="e">{when(r.state === "WITHDRAWN" ? r.withdrawn_at ?? r.expires_at : r.expires_at)}<div className="sub2">{r.days} day{r.days === 1 ? "" : "s"}</div></span>,
          <span key="t"><Pil kind={STATE[r.state][1]}>{STATE[r.state][0]}</Pil>{r.state === "PAID" && r.receipt_no ? <div className="sub2">{r.receipt_no}{r.channel ? ` · ${r.channel}` : ""}</div> : null}</span>,
          <span className="sub2" key="c">{Number(r.checks) ? <>{r.checks} · last {when(r.last_check_at ?? null)}{r.last_outcome ? ` · ${OUTCOME[r.last_outcome]?.[0] ?? r.last_outcome}` : ""}</> : "None yet"}</span>,
          <span key="x">{may && r.state === "OPEN" ? (
            <Btn kind="ghost" disabled={busy} onClick={async () => {
              if (!window.confirm(`Withdraw ${r.reference}? It expires now, and Quickteller is answered Status 1 for it from then on.`)) return;
              if (await send(`/paydirect/test-references/${encodeURIComponent(r.reference)}/withdraw`, {}, `Interswitch test reference ${r.reference} withdrawn`)) {
                if (issued?.reference === r.reference) setIssued(null);
                say(`${r.reference} withdrawn; Quickteller is answered Status 1 for it`);
              }
            }}>Withdraw</Btn>
          ) : null}</span>,
        ])} texts={refs.map((r) => `${r.reference} ${r.payer} ${r.number} ${r.state}`)} />
      ) : <div className="sub2 mt-2">No test reference has been issued in the last 30 days.</div>}
    </>
  );
}
