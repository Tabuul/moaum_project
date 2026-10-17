"use client";

/** V506: the ledger, from Old Fees History — taking over, putting right and withdrawing old payments reverse their postings and
 *  leave them to be posted again under their item; a carried excess is posted with its decision. What waits to be posted
 *  (every payment, refund and voucher of the one ledger, oldest first) is shown here, and the Bursary posts it in batches — the
 *  same sync the Accounting desk runs. */
import { useEffect, useState } from "react";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, Note, Panel, PBody, Tiles } from "@/components/proto/ui";

interface Unposted { payments: number; refunds: number; vouchers: number }
interface SyncBatch { payments: number; refunds: number; vouchers: number; remaining: number }

/** the transactions one sync request posts (the Accounting desk's batch); the panel carries on until none remain */
const BATCH = 2000;

/** tick: a change made elsewhere on the page (an upload, a withdrawal, records put right): read again */
export function OldFeesLedger({ may, tick = 0 }: { may: boolean; tick?: number }) {
  const [data, setData] = useState<Unposted | null>(null);
  const [answered, setAnswered] = useState<string | null>(null);
  const [own, setOwn] = useState(0);
  const [posting, setPosting] = useState(false);
  const [left, setLeft] = useState<number | null>(null);
  const [said, setSaid] = useState<string | null>(null);
  const [problem, setProblem] = useState<Problem | null>(null);
  const asked = `${tick}#${own}`;
  const loading = answered !== asked;

  useEffect(() => {
    let alive = true;
    void (async () => {
      const r = await fetch("/api/bff/api/v1/finance/accounting/unposted", { cache: "no-store" }).catch(() => null);
      const j = r ? await r.json().catch(() => null) : null;
      if (!alive) return;
      setAnswered(asked);
      if (!r || !r.ok) { notifyProblem((j ?? { status: r?.status ?? 0, title: r?.statusText || "The portal could not be reached" }) as Problem); return; }
      setData(j as Unposted);
    })();
    return () => { alive = false; };
  }, [asked]);

  async function post() {
    setPosting(true); setSaid(null); setProblem(null); setLeft(null);
    let posted = 0;
    try {
      for (;;) {
        const r = await fetch(`/api/bff/api/v1/finance/accounting/sync?limit=${BATCH}`, {
          method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader("Ledger posted from Old Fees History") }, body: "{}",
        });
        if (!r.ok) {
          const p = (await r.json().catch(() => ({ status: r.status, title: "The request was refused." }))) as Problem;
          if (posted > 0) p.detail = `${posted.toLocaleString()} posted before this; press again to carry on.${p.detail ? " " + p.detail : ""}`;
          setProblem(p); notifyProblem(p);
          return;
        }
        const b = (await r.json()) as SyncBatch;
        const n = Number(b.payments) + Number(b.refunds) + Number(b.vouchers);
        posted += n;
        setLeft(Number(b.remaining));
        // none left — or none of what is left could be posted, which the books then still show
        if (Number(b.remaining) <= 0 || n === 0) break;
      }
      setSaid(posted === 0 ? "Nothing was waiting to be posted." : `${posted.toLocaleString()} transaction${posted === 1 ? "" : "s"} posted to the ledger.`);
      notify(posted === 0 ? "Nothing was waiting to be posted" : `${posted.toLocaleString()} posted to the ledger`);
    } catch {
      const p: Problem = { status: 0, title: "The network dropped the request.", detail: posted > 0 ? `${posted.toLocaleString()} were posted before this; press again to carry on.` : undefined };
      setProblem(p); notifyProblem(p);
    } finally {
      setPosting(false); setLeft(null); setOwn((x) => x + 1);
    }
  }

  const waiting = data ? Number(data.payments) + Number(data.refunds) + Number(data.vouchers) : 0;
  return (
    <Panel title="The ledger" right="What waits to be posted: payments taken over, put right or carried here are posted again under their item">
      <PBody>
        {said ? <Note kind="ok" title="Posted">{said}</Note> : null}
        {problem ? <Note kind="bad" title={problem.title}>{problem.detail ?? ""}</Note> : null}
        {!data ? <div className="sub2">{loading ? "Looking…" : ""}</div> : (
          <>
            <Tiles items={[
              ["Payments waiting", Number(data.payments).toLocaleString(), Number(data.payments) ? "var(--red-ink)" : null, "Not yet on the books"],
              ["Refunds waiting", Number(data.refunds).toLocaleString(), null, "Paid, not yet on the books"],
              ["Vouchers waiting", Number(data.vouchers).toLocaleString(), null, "Paid, not yet on the books"],
            ]} />
            <div className="row mt-2">
              {may && waiting > 0 ? (
                <Btn kind="primary" disabled={posting || loading} onClick={() => void post()}>
                  {posting ? (left != null && left > 0 ? `Posting… ${left.toLocaleString()} left` : "Posting…") : `Post ${waiting.toLocaleString()} to the ledger`}
                </Btn>
              ) : null}
              {!waiting ? <span className="sub2">Nothing waits to be posted.</span> : null}
              {loading ? <span className="sub2" role="status">Looking…</span> : null}
            </div>
            <div className="sub2 mt-2">Every transaction of the one ledger is posted, oldest first, as on the Accounting desk.</div>
          </>
        )}
      </PBody>
    </Panel>
  );
}
