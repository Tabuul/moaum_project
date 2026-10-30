"use client";
/** V710: wallets owing — a student whose wallet was credited with another student's payment, already partly used, once the Bursary
 *  moved the credit to its owner (a payment swap): the wallet owes the rest, settled first by what is credited to it later. On the
 *  Bursar's and the Students Account Officer's dashboards (the few owing most) and on Payment swaps (all, with a search). Read after the
 *  page is drawn, so the page never waits on it. */
import { useEffect, useState } from "react";
import { LinkBtn, Panel, PBody, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { money } from "@/lib/format";
import type { WalletDebts } from "@/lib/payment-swaps";

const when = (v: string | null) => (v ? new Date(v).toLocaleDateString("en-GB", { day: "numeric", month: "short", year: "numeric" }) : "—");

export function WalletDebtsPanel({ full }: { full?: boolean }) {
  const [d, setD] = useState<WalletDebts | null>(null);
  const [failed, setFailed] = useState(false);
  const [q, setQ] = useState("");
  const [asked, setAsked] = useState("");
  useEffect(() => {
    let live = true;
    const url = `/api/bff/api/v1/finance/payment-swaps/wallet-debts?limit=${full ? 500 : 5}${asked ? `&q=${encodeURIComponent(asked)}` : ""}`;
    fetch(url, { cache: "no-store", headers: { "X-Background": "1" } })
      .then(async (r) => { const j = r.ok ? ((await r.json()) as WalletDebts) : null; if (live) { setD(j); setFailed(!j); } })
      .catch(() => { if (live) setFailed(true); });
    return () => { live = false; };
  }, [full, asked]);
  if (!full && d && Number(d.students) === 0) return null;   // nothing owing: the dashboard says nothing
  return (
    <Panel title="Wallets owing" right={full ? <span className="sub2">{d ? `${Number(d.students).toLocaleString()} student${Number(d.students) === 1 ? "" : "s"}` : ""}</span>
      : <LinkBtn kind="ghost" href="/finance/payment-swaps#wallets-owing">All wallets owing</LinkBtn>}>
      {failed ? <PBody><div className="sub2">The wallets owing could not be read just now.</div></PBody> : !d ? <PBody><div className="sub2">Reading…</div></PBody> : (
        <>
          <PBody>
            <Tiles items={[
              ["Students owing", Number(d.students).toLocaleString(), Number(d.students) ? "var(--amber-ink)" : null, "A wallet below nought"],
              ["Owed in all", money(Number(d.owed)), Number(d.owed) ? "var(--red-ink)" : null, "Settled first by later credits"],
            ]} />
            <div className="sub2 mt-2">A payment credited to the wrong student&rsquo;s wallet and partly used, then moved to its owner by a payment swap: that wallet owes the rest. The student was told; their fees stay as they were paid.</div>
            {full ? (
              <div className="row row--inline mt-2" style={{ gap: "var(--s-2)" }}>
                <input className="ctl" style={{ minWidth: 260 }} value={q} placeholder="Matriculation number, name or swap" aria-label="Find a wallet owing"
                  onChange={(e) => setQ(e.target.value)} onKeyDown={(e) => { if (e.key === "Enter") setAsked(q.trim()); }} />
              </div>
            ) : null}
          </PBody>
          {d.rows.length ? (
            <DTable pageSize={full ? 25 : 0} noPrint={!full} cols={["Student", "Owes|num", "By the swap", "Moved to", "Last credited"]}
              texts={d.rows.map((r) => `${r.matric_no ?? ""} ${r.student} ${r.swap_ref ?? ""} ${r.moved_to ?? ""}`)}
              rows={d.rows.map((r) => [
                <span key="s">{r.student}<div className="sub2 tnum">{r.matric_no ?? ""}{r.programme ? ` · ${r.programme}` : ""}</div></span>,
                <b key="o" className="tnum">{money(Number(r.owed))}</b>,
                <span key="w" className="tnum sub2">{r.swap_ref ?? "—"}{r.reference ? <div>{r.reference}</div> : null}{r.swapped_at ? <div>{when(r.swapped_at)}</div> : null}</span>,
                <span key="m" className="tnum sub2">{r.moved_to ?? "—"}</span>,
                <span key="l" className="sub2">{when(r.last_credit_at)}</span>,
              ])} />
          ) : <PBody><div className="sub2">{asked ? "No wallet owing matches." : "No wallet owes anything."}</div></PBody>}
        </>
      )}
    </Panel>
  );
}
