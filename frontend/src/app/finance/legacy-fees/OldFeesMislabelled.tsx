"use client";

/** V498: what earlier uploads recorded under the old portal's payment-item code ("10048 (legacy)" — 10048 is SCHOOL FEES), or
 *  under a label the rules now read otherwise ("GST FEES (legacy)" is the GST fee), or (V502) by the retired Payment History Upload
 *  under the old portal's item name ("SCHOOL FEES"): a paid semester recorded so is not counted.
 *  Listed with what each is, taken as Excel, and put right by the Bursary with a reason — renamed or relabelled so school fees
 *  count, or withdrawn where the same payment is on record under its item; each kept on its register, its ledger posting
 *  reversed so the ledger posts it again under its item, once. */
import { useEffect, useState } from "react";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, Note, Panel, PBody, Pil, Tiles, Two } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, Modal, money } from "@/components/proto/blocks";
import { brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";
import { MISLABEL_ACTION, MISLABELLED_HEADERS, mislabelledRow, type MislabelAction, type MislabelledRow } from "@/lib/old-fees";

interface Mislabelled {
  count: number; amount: number | string; students: number; codes: number; actions: Partial<Record<MislabelAction, number>>;
  unknownCodes: string[]; rows: MislabelledRow[];
}

/** tick: a change made elsewhere on the page (the list reads again); onChanged: told when this list changes the records */
export function OldFeesMislabelled({ may, tick: changed = 0, onChanged }: { may: boolean; tick?: number; onChanged?: () => void }) {
  const [data, setData] = useState<Mislabelled | null>(null);
  const [busy, setBusy] = useState<string | null>("load");
  const [tick, setTick] = useState(0);
  const [asking, setAsking] = useState(false);
  const [reason, setReason] = useState("");
  const [progress, setProgress] = useState<string | null>(null);
  const [said, setSaid] = useState<string | null>(null);

  useEffect(() => {
    let alive = true;
    void (async () => {
      const r = await fetch("/api/bff/api/v1/finance/legacy-fees/mislabelled?limit=200", { cache: "no-store" }).catch(() => null);
      const j = r ? await r.json().catch(() => null) : null;
      if (!alive) return;
      setBusy(null);
      if (!r || !r.ok) { notifyProblem((j ?? { status: r?.status ?? 0, title: r?.statusText || "The portal could not be reached" }) as Problem); return; }
      setData(j as Mislabelled);
    })();
    return () => { alive = false; };
  }, [tick, changed]);

  async function excel() {
    setBusy("excel");
    try {
      const r = await fetch("/api/bff/api/v1/finance/legacy-fees/mislabelled?limit=100000", { cache: "no-store" });
      const j = (await r.json().catch(() => null)) as Mislabelled | null;
      if (!r.ok || !j) { notifyProblem((j ?? { status: r.status, title: r.statusText }) as unknown as Problem); return; }
      const blob = await brandedXlsx("Old payments recorded under a code", MISLABELLED_HEADERS, j.rows.map(mislabelledRow), {
        sheetName: "Under a code", serial: docSerial("OPC"), sub: `${j.count.toLocaleString()} record${j.count === 1 ? "" : "s"} · what each is and what putting it right does`,
      });
      downloadBlob(blob, "old-payments-under-a-code.xlsx");
    } finally {
      setBusy(null);
    }
  }

  async function putRight() {
    setBusy("put");
    setSaid(null);
    const t = { renamed: 0, relabelled: 0, withdrawn: 0, reversed: 0 };
    try {
      for (;;) {
        const r = await fetch("/api/bff/api/v1/finance/legacy-fees/mislabelled/put-right", {
          method: "POST",
          headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`Old payments recorded under a code put right: ${reason.trim()}`) },
          body: JSON.stringify({ reason: reason.trim(), limit: 5000 }),
        });
        const j = await r.json().catch(() => null);
        if (!r.ok) { notifyProblem((j ?? { status: r.status, title: r.statusText }) as Problem); break; }
        const w = j as { renamed: number; relabelled: number; withdrawn: number; ledger_reversed: number; unknown_codes: number; remaining: number };
        const done = Number(w.renamed) + Number(w.relabelled) + Number(w.withdrawn);
        t.renamed += Number(w.renamed); t.relabelled += Number(w.relabelled); t.withdrawn += Number(w.withdrawn); t.reversed += Number(w.ledger_reversed);
        setProgress(`${(t.renamed + t.relabelled + t.withdrawn).toLocaleString()} put right${Number(w.remaining) ? `, ${Number(w.remaining).toLocaleString()} to go` : ""}…`);
        if (!Number(w.remaining) || !done) {
          setSaid(`${t.renamed.toLocaleString()} recorded as what they are, ${t.relabelled.toLocaleString()} relabelled, ${t.withdrawn.toLocaleString()} withdrawn as on record under their item.${t.reversed ? ` ${t.reversed.toLocaleString()} ledger posting${t.reversed === 1 ? "" : "s"} reversed: the ledger posts each again under its item.` : ""}${Number(w.unknown_codes) ? ` ${Number(w.unknown_codes).toLocaleString()} wait: their code is not in the list.` : ""}`);
          break;
        }
      }
      notify("Put right");
      setAsking(false);
      setReason("");
    } finally {
      setProgress(null);
      setBusy("load");
      setTick((x) => x + 1);
      onChanged?.();
    }
  }

  const acts = data?.actions ?? {};
  const doable = (acts.RENAME ?? 0) + (acts.RELABEL ?? 0) + (acts.DOUBLE ?? 0);
  return (
    <Panel title="Recorded under a code" right="Earlier uploads that carried the old portal's payment-item code (10048 is SCHOOL FEES), an old label, or the old portal's item name (Payment History Upload's SCHOOL FEES): a paid semester recorded so is not counted">
      {said ? <PBody><Note kind="ok" title="Put right">{said} Each one is kept on its register with your reason.</Note></PBody> : null}
      {!data ? <PBody><div className="sub2">{busy === "load" ? "Looking…" : ""}</div></PBody>
        : !data.count ? (
          <PBody><div className="sub2">No old payment is recorded under a code or an old label.{data.codes ? ` ${data.codes.toLocaleString()} payment-item codes are known.` : ""}</div></PBody>
        ) : (
          <>
            <PBody>
              <Tiles items={[
                ["Recorded under a code", data.count.toLocaleString(), "var(--red-ink)", `${data.students.toLocaleString()} student${data.students === 1 ? "" : "s"} · ${money(Number(data.amount))}`],
                [MISLABEL_ACTION.RENAME[0], (acts.RENAME ?? 0).toLocaleString(), null, "Renamed, so school fees and the GST fee count"],
                [MISLABEL_ACTION.DOUBLE[0], (acts.DOUBLE ?? 0).toLocaleString(), null, "The same payment is on record under its name"],
                ["Code not in the list", (acts.UNKNOWN_CODE ?? 0).toLocaleString(), acts.UNKNOWN_CODE ? "var(--red-ink)" : null, `${data.codes.toLocaleString()} codes known`],
              ]} />
              {acts.UNKNOWN_CODE ? (
                <Note kind="info" title="Some codes are not in the list yet">
                  {data.unknownCodes.slice(0, 20).join(", ")}{data.unknownCodes.length > 20 ? ", …" : ""}. Choose the old portal&rsquo;s export above: its payment_type sheet names
                  every code, and is read as soon as the file is chosen.
                </Note>
              ) : null}
              <div className="row mt-2">
                <Btn kind="ghost" disabled={!!busy} onClick={() => void excel()}>{busy === "excel" ? "Preparing…" : "Excel"}</Btn>
                {may && doable > 0 ? <Btn kind="primary" disabled={!!busy} onClick={() => setAsking(true)}>{`Put ${doable.toLocaleString()} right`}</Btn> : null}
              </div>
            </PBody>
            <DTable pageSize={0} cols={["Student", "Session|mid", "Day paid|mid", "Amount|num", "Recorded as", "What it is", ""]}
              rows={data.rows.map((m) => [
                <Two key="s" a={m.name} b={m.number} />,
                <span key="se" className="tnum sub2">{m.session}</span>,
                <span key="d" className="tnum sub2">{m.paid_on}</span>,
                <b key="a" className="tnum">{money(Number(m.amount))}</b>,
                <span key="r" className="sub2">{m.stored_purpose}<div className="tnum">{m.reference}</div></span>,
                <span key="w" className="sub2">{m.target_purpose ?? "—"}{m.target_reference && m.target_reference !== m.reference ? <div className="tnum">{m.target_reference}</div> : null}</span>,
                <Pil key="p" kind={MISLABEL_ACTION[m.action]?.[1] ?? "grey"}>{MISLABEL_ACTION[m.action]?.[0] ?? m.action}</Pil>,
              ])} />
            {data.count > data.rows.length ? <PBody><div className="sub2">The first {data.rows.length.toLocaleString()} of {data.count.toLocaleString()}; the Excel list has them all.</div></PBody> : null}
          </>
        )}
      {asking ? (
        <Modal title={`Put ${doable.toLocaleString()} records right`} onClose={() => { if (!busy) setAsking(false); }}
          foot={<><Btn kind="ghost" disabled={!!busy} onClick={() => setAsking(false)}>Cancel</Btn>
            <Btn kind="primary" disabled={!!busy || reason.trim().length < 10} onClick={() => void putRight()}>{busy === "put" ? (progress ?? "Putting right…") : "Put right"}</Btn></>}>
          <p>
            Each record is recorded as what its code names: school fees and the GST fee are renamed so they count, another item keeps its own name.
            Its ledger posting, made under another item, is reversed, and the ledger posts it again under its item. Where the same payment is
            already on record under its name (the same amount and day), the coded copy is withdrawn: its ledger posting reversed, the record kept
            on the register. Every change is kept with your reason. A code the list does not name waits.
          </p>
          <Field id="opc-reason" label="Why" required hint="At least ten characters; kept with each record">
            <textarea id="opc-reason" className="ctl" rows={2} maxLength={500} value={reason} onChange={(e) => setReason(e.target.value)}
              placeholder="e.g. the old-portal upload carried payment-item codes instead of their names" />
          </Field>
        </Modal>
      ) : null}
    </Panel>
  );
}
