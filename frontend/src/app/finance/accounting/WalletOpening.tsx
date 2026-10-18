"use client";

/** V552: the wallet's opening balance settled — what students held when the wallet came onto the ledger (V545) was opened against
 *  3900 Opening balance / suspense; here it is shown by source and session with the account each part belongs in, and the Bursary
 *  posts the reclassification out of suspense, never more than remains in it. */
import { useEffect, useState } from "react";
import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, Note, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { money } from "@/components/proto/blocks";

interface Part { source_code: string; source_name: string; nature: string; session: string; amount: number; suggested_account: string | null }
interface JLine { account: string; name: string; debit: number; credit: number; narration: string | null }
interface Journal { id: string; journal_no: number; entry_date: string; memo: string; status: string; posted_by_name: string | null; lines: JLine[] }
interface Opening {
  state: { posted: number; reclassified: number; remaining: number; opening_date: string | null };
  breakdown: Part[]; journals: Journal[]; accounts: { code: string; name: string; type: string }[];
}
interface Draft { account: string; amount: string; on: boolean }

const NATURE: Record<string, string> = { LOAN: "Loan", GRANT: "Grant", SELF: "Own money", UNKNOWN: "No source named" };
const key = (p: Part) => `${p.source_code}|${p.session}`;

export function WalletOpening({ may }: { may: boolean }) {
  const [data, setData] = useState<Opening | null>(null);
  const [draft, setDraft] = useState<Record<string, Draft>>({});
  const [busy, setBusy] = useState(false);

  /** the form starts from the breakdown while nothing has been reclassified: each part to its suggested account, for its amount */
  function seed(o: Opening) {
    const fresh = Number(o.state.reclassified) === 0;
    setDraft(Object.fromEntries(o.breakdown.filter((p) => Number(p.amount) > 0).map((p) => [key(p), {
      account: p.suggested_account ?? "", amount: fresh ? String(Number(p.amount)) : "", on: fresh && p.suggested_account != null,
    }])));
  }
  useEffect(() => {
    let live = true;
    fetch("/api/bff/api/v1/finance/accounting/wallet-opening", { cache: "no-store" })
      .then((r) => (r.ok ? r.json() : null))
      .catch(() => null)
      .then((j: Opening | null) => { if (live && j) { setData(j); seed(j); } });
    return () => { live = false; };
  }, []);

  if (!data) return null;
  const { state } = data;
  const parts = data.breakdown;
  const chosen = parts.filter((p) => draft[key(p)]?.on && draft[key(p)]?.account && Number(draft[key(p)]?.amount) > 0);
  const total = chosen.reduce((n, p) => n + Number(draft[key(p)].amount), 0);
  const over = total - Number(state.remaining) > 0.005;
  const set = (p: Part, patch: Partial<Draft>) => setDraft({ ...draft, [key(p)]: { ...draft[key(p)], ...patch } });

  async function post() {
    // one line for each account, the parts going to it added together
    const byAccount = new Map<string, { amount: number; names: string[] }>();
    for (const p of chosen) {
      const d = draft[key(p)];
      const x = byAccount.get(d.account) ?? { amount: 0, names: [] };
      x.amount += Number(d.amount);
      x.names.push(`${p.source_name} ${p.session}`);
      byAccount.set(d.account, x);
    }
    const lines = [...byAccount.entries()].map(([account, x]) => ({ account, amount: Math.round(x.amount * 100) / 100, narration: `Wallet opening balance: ${x.names.join(", ")}`.slice(0, 300) }));
    setBusy(true);
    try {
      const r = await fetch("/api/bff/api/v1/finance/accounting/wallet-opening/reclassify", {
        method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader("The wallet's opening balance reclassified out of suspense") }, body: JSON.stringify({ lines }),
      });
      const j = await r.json().catch(() => null);
      if (!r.ok) { notifyProblem(j ?? { status: r.status, title: r.statusText }); return; }
      setData(j as Opening);
      seed(j as Opening);
      notify(`${money(total)} reclassified out of suspense`);
    } finally {
      setBusy(false);
    }
  }

  if (Number(state.posted) === 0 && !parts.length) return null;
  return (
    <Panel title="Wallet opening balance" right={Number(state.posted) > 0 && Number(state.remaining) === 0 ? <Pil kind="ok">Settled</Pil> : undefined}>
      <PBody>
        <div className="sub2">What students held in their wallets when the wallet came onto the ledger was opened against 3900 Opening balance / suspense. Each part belongs in an account of its own: money lent (NELFUND) is money in the bank that was never booked; a grant is a cost of grants and scholarships; a student&rsquo;s own top-up was booked as other income before the wallet held it.</div>
      </PBody>
      <Tiles items={[
        ["Opened against suspense", money(Number(state.posted)), null, state.opening_date ? `On ${new Date(`${state.opening_date}T12:00:00`).toLocaleDateString("en-GB", { day: "numeric", month: "short", year: "numeric" })}` : "Not posted yet"],
        ["Reclassified", money(Number(state.reclassified)), Number(state.reclassified) ? "var(--green-ink)" : null, `${data.journals.filter((j) => j.status === "POSTED").length} journal${data.journals.filter((j) => j.status === "POSTED").length === 1 ? "" : "s"}`],
        ["Remaining in suspense", money(Number(state.remaining)), Number(state.remaining) ? "var(--amber-ink)" : "var(--green-ink)", "To move to its accounts"],
      ]} />
      {Number(state.posted) === 0 ? (
        <Note kind="info" title="The opening balance is not on the ledger yet">Post what is waiting (Sync) first; the opening balance is posted with it, once.</Note>
      ) : null}
      {parts.length ? (
        <DTable pageSize={0} cols={["Source", "Session|mid", "Held|num", "Account it belongs in", "Amount to move|num"]} rows={parts.map((p) => {
          const d = draft[key(p)];
          return [
            <span key="s">{p.source_name} <span className="sub2">{NATURE[p.nature] ?? p.nature}</span></span>,
            <span key="y" className="tnum">{p.session}</span>,
            <b key="a" className="tnum">{money(Number(p.amount))}</b>,
            d && may && Number(state.remaining) > 0 ? (
              <span key="c" className="row row--tight">
                <input type="checkbox" aria-label={`Move ${p.source_name} ${p.session}`} checked={d.on} onChange={(e) => set(p, { on: e.target.checked })} />
                <select className="ctl" aria-label={`Account for ${p.source_name} ${p.session}`} value={d.account} onChange={(e) => set(p, { account: e.target.value, on: e.target.value !== "" })} style={{ maxWidth: 260 }}>
                  <option value="">Choose the account…</option>
                  {data.accounts.map((a) => <option key={a.code} value={a.code}>{`${a.code} ${a.name}`}</option>)}
                </select>
              </span>
            ) : <span key="c" className="sub2">{p.suggested_account ? `${p.suggested_account} ${data.accounts.find((a) => a.code === p.suggested_account)?.name ?? ""}` : Number(p.amount) < 0 ? "Owed back: a manual journal" : "The Bursary names it"}</span>,
            d && may && Number(state.remaining) > 0
              ? <input key="m" className="ctl tnum" inputMode="decimal" aria-label={`Amount for ${p.source_name} ${p.session}`} value={d.amount} onChange={(e) => set(p, { amount: e.target.value.replace(/[^0-9.]/g, "") })} style={{ width: 130, textAlign: "right" }} />
              : <span key="m" className="sub2">—</span>,
          ];
        })} />
      ) : null}
      {may && Number(state.remaining) > 0 ? (
        <PBody>
          <div className="row" style={{ gap: 8, alignItems: "center", flexWrap: "wrap" }}>
            <Btn kind="primary" disabled={busy || !chosen.length || over} busyLabel="Posting…" onClick={() => post()}>{`Post the reclassification${chosen.length ? ` · ${money(total)}` : ""}`}</Btn>
            <span className="sub2">{over ? `More than the ${money(Number(state.remaining))} still in suspense.` : "One journal: each account debited, 3900 Opening balance / suspense credited."}</span>
          </div>
        </PBody>
      ) : null}
      {data.journals.length ? (
        <DTable pageSize={0} cols={["No.", "Date|mid", "Lines", "Posted by", "|num"]} rows={data.journals.map((j) => [
          <span key="n" className="tnum">#{j.journal_no}</span>,
          <span key="d" className="tnum">{j.entry_date}</span>,
          <span key="l" className="sub2">{j.lines.filter((l) => Number(l.debit) > 0).map((l) => `${l.account} ${l.name} ${money(Number(l.debit))}`).join(" · ")}</span>,
          <span key="b" className="sub2">{j.posted_by_name ?? "—"}</span>,
          j.status === "REVERSED" ? <Pil key="s" kind="bad">Reversed</Pil> : <Pil key="s" kind="ok">Posted</Pil>,
        ])} />
      ) : null}
    </Panel>
  );
}
