"use client";

/** V502: what the retired Payment History Upload recorded that nothing has matched — Old Fees History did not take it over (the
 *  export loaded here has not named its payment number) and it repeats no other record — with what it counts as now; listed
 *  and taken as Excel for the Bursary to look into. A record under the old portal's item name is put right under "Recorded under
 *  a code"; one the export names is taken over when the export is loaded. */
import { useEffect, useState } from "react";
import type { Problem } from "@/lib/api";
import { notifyProblem } from "@/components/proto/Toast";
import { Btn, Note, Panel, PBody, Pil, Tiles, Two } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { money } from "@/components/proto/blocks";
import { brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";
import { COUNTS_AS, LEFT_HEADERS, leftRow, type CountsAs, type LeftRow } from "@/lib/old-fees";

interface Left { count: number; amount: number | string; students: number; countsAs: Partial<Record<CountsAs, number>>; rows: LeftRow[] }

/** tick: a change made elsewhere on the page (an upload, a withdrawal, records put right): the list reads again */
export function OldFeesPaymentHistoryLeft({ tick = 0 }: { tick?: number }) {
  const [data, setData] = useState<Left | null>(null);
  const [answered, setAnswered] = useState<number | null>(null);
  const [preparing, setPreparing] = useState(false);

  useEffect(() => {
    let alive = true;
    void (async () => {
      const r = await fetch("/api/bff/api/v1/finance/legacy-fees/payment-history-left?limit=200", { cache: "no-store" }).catch(() => null);
      const j = r ? await r.json().catch(() => null) : null;
      if (!alive) return;
      setAnswered(tick);
      if (!r || !r.ok) { notifyProblem((j ?? { status: r?.status ?? 0, title: r?.statusText || "The portal could not be reached" }) as Problem); return; }
      setData(j as Left);
    })();
    return () => { alive = false; };
  }, [tick]);
  const loading = answered !== tick;

  async function excel() {
    setPreparing(true);
    try {
      const r = await fetch("/api/bff/api/v1/finance/legacy-fees/payment-history-left?limit=100000", { cache: "no-store" });
      const j = (await r.json().catch(() => null)) as Left | null;
      if (!r.ok || !j) { notifyProblem((j ?? { status: r.status, title: r.statusText }) as unknown as Problem); return; }
      const blob = await brandedXlsx("Recorded by Payment History Upload alone", LEFT_HEADERS, j.rows.map(leftRow), {
        sheetName: "Payment History alone", serial: docSerial("OPL"),
        sub: `Matched by nothing in Old Fees History · ${j.count.toLocaleString()} record${j.count === 1 ? "" : "s"}`,
      });
      downloadBlob(blob, "old-payments-payment-history-alone.xlsx");
    } finally {
      setPreparing(false);
    }
  }

  const as = data?.countsAs ?? {};
  return (
    <Panel title="Recorded by Payment History Upload alone" right="What the retired screen recorded that nothing on Old Fees History matches">
      {!data ? <PBody><div className="sub2">{loading ? "Looking…" : ""}</div></PBody>
        : !data.count ? (
          <PBody><div className="sub2">Every record Payment History Upload made is matched: taken over by Old Fees History, or withdrawn as a repeat.</div></PBody>
        ) : (
          <>
            <PBody>
              <Tiles items={[
                ["Matched by nothing", data.count.toLocaleString(), "var(--red-ink)", `${data.students.toLocaleString()} student${data.students === 1 ? "" : "s"} · ${money(Number(data.amount))}`],
                ["Counted as school fees", (as.SCHOOL_FEES ?? 0).toLocaleString(), null, "Read by the fee gate and the reconciliation"],
                ["Counted as the GST fee", (as.GST ?? 0).toLocaleString(), null, "Read by the GST desk"],
                ["Another item", (as.OTHER ?? 0).toLocaleString(), null, "Not school fees"],
              ]} />
              <Note kind="info" title="How these are matched">
                Choose the old portal&rsquo;s export above and load it: a record whose payment number the export names is taken over, recorded
                with its item, semester and the day paid. One under the old portal&rsquo;s item name (SCHOOL FEES, GST FEES) is put right under
                &ldquo;Recorded under a code&rdquo;. What stays here is not in the export: look into each with the Excel list.
              </Note>
              <div className="row mt-2">
                <Btn kind="ghost" disabled={loading || preparing} onClick={() => void excel()}>{preparing ? "Preparing…" : "Excel"}</Btn>
                {loading ? <span className="sub2" role="status">Looking…</span> : null}
              </div>
            </PBody>
            <DTable cols={["Student", "Session|mid", "Day on record|mid", "Amount|num", "Recorded as", "Counts as"]}
              rows={data.rows.map((l) => [
                <Two key="s" a={l.name} b={l.number} />,
                <span key="se" className="tnum sub2">{l.session}</span>,
                <span key="d" className="tnum sub2">{l.paid_on}{l.number_day && l.number_day !== l.paid_on ? <div>paid {l.number_day}</div> : null}</span>,
                <b key="a" className="tnum">{money(Number(l.amount))}</b>,
                <span key="r" className="sub2">{l.purpose}<div className="tnum">{l.reference}</div></span>,
                <Pil key="c" kind={l.counts_as === "OTHER" ? "grey" : "info"}>{COUNTS_AS[l.counts_as] ?? l.counts_as}</Pil>,
              ])} />
            {data.count > data.rows.length ? <PBody><div className="sub2">The first {data.rows.length.toLocaleString()} of {data.count.toLocaleString()}; the Excel list has them all.</div></PBody> : null}
          </>
        )}
    </Panel>
  );
}
