"use client";
/** V714: the bulk resets of a desk, newest first — who ran each, when, the reason, how many were asked, reset and passed over — and each
 *  run's own rows (what every number given was found to be and what was done), downloadable. Read after the page is drawn. */
import { useEffect, useState } from "react";
import { Btn, Panel, PBody, Pil } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Modal } from "@/components/proto/blocks";
import { BULK_OUTCOME } from "@/lib/applicant-password";
import { brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";

interface Run { id: string; reference: string; kind: string; reason: string; asked: number; reset: number; passed_over: number; done_at: string; done_office: string; done_by_name: string }
interface RunRow { row_no: number; given: string; outcome: string; applicant: string | null; default_number: string | null; detail: string | null }

const when = (v: string) => new Date(v).toLocaleString("en-GB", { day: "numeric", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit" });

export function BulkRunsPanel({ endpoint, postgraduate, tick = 0 }: { endpoint: string; postgraduate?: boolean; tick?: number }) {
  const [runs, setRuns] = useState<Run[] | null>(null);
  const [failed, setFailed] = useState(false);
  const [open, setOpen] = useState<(Run & { rows: RunRow[] }) | null>(null);
  const [busy, setBusy] = useState<string | null>(null);
  useEffect(() => {
    let live = true;
    fetch(`/api/bff${endpoint}/bulk-runs?limit=100`, { cache: "no-store", headers: { "X-Background": "1" } })
      .then(async (r) => { const j = r.ok ? ((await r.json()) as Run[]) : null; if (live) { setRuns(j); setFailed(!j); } })
      .catch(() => { if (live) setFailed(true); });
    return () => { live = false; };
  }, [endpoint, tick]);
  async function show(id: string) {
    setBusy(id);
    try {
      const r = await fetch(`/api/bff${endpoint}/bulk-runs/${id}`, { cache: "no-store" });
      if (r.ok) setOpen((await r.json()) as Run & { rows: RunRow[] });
    } finally { setBusy(null); }
  }
  async function exportRun(run: Run & { rows: RunRow[] }) {
    const head = ["Row", "Given", "Outcome", "Applicant", "Reset to", "Detail"];
    const body = run.rows.map((r) => [r.row_no, r.given, BULK_OUTCOME[r.outcome]?.[0] ?? r.outcome, r.applicant ?? "", r.default_number ?? "", r.detail ?? ""]);
    downloadBlob(await brandedXlsx(postgraduate ? "Postgraduate applicant passwords reset in bulk" : "Applicant passwords reset in bulk", head, body,
      { sheetName: "Bulk reset", serial: docSerial("APW"), sub: `${run.reference} · ${run.done_by_name} · ${when(run.done_at)}` }), `applicant-passwords-${run.reference.replace(/\//g, "-")}.xlsx`);
  }
  return (
    <Panel title="Bulk resets" right={<span className="sub2">{runs ? `${runs.length} most recent` : ""}</span>}>
      {failed ? <PBody><div className="sub2">The bulk resets could not be read just now.</div></PBody>
        : !runs ? <PBody><div className="sub2">Reading…</div></PBody>
        : runs.length ? (
          <DTable pageSize={10} cols={["Reference", "When", "By", "Reason", "Asked|num", "Reset|num", "Passed over|num", ""]}
            texts={runs.map((r) => `${r.reference} ${r.done_by_name} ${r.reason}`)}
            rows={runs.map((r) => [
              <span key="r" className="tnum">{r.reference}</span>, <span key="w" className="sub2 tnum">{when(r.done_at)}</span>,
              <span key="b" className="sub2">{r.done_by_name} · {r.done_office}</span>, <span key="x" className="sub2">{r.reason}</span>,
              <span key="a" className="tnum">{r.asked}</span>, <b key="s" className="tnum">{r.reset}</b>, <span key="p" className="tnum">{r.passed_over}</span>,
              <Btn key="o" kind="secondary" size="sm" disabled={busy !== null} onClick={() => void show(r.id)}>{busy === r.id ? "Opening…" : "Open"}</Btn>,
            ])} />
        ) : <PBody><div className="sub2">No bulk reset has been made yet.</div></PBody>}
      {open ? (
        <Modal wide title={`Bulk reset ${open.reference}`} sub={`${when(open.done_at)} · ${open.done_by_name} · ${open.reason}`} onClose={() => setOpen(null)}
          foot={<><Btn kind="ghost" onClick={() => void exportRun(open)}>Excel</Btn><span className="grow" /><Btn kind="primary" onClick={() => setOpen(null)}>Done</Btn></>}>
          <div className="sub2 mb-2">{open.asked} asked · {open.reset} reset · {open.passed_over} passed over</div>
          <DTable noPrint pageSize={25} cols={["Row|num", "Given", "Outcome|mid", "Applicant", "Reset to", "Detail"]}
            texts={open.rows.map((r) => `${r.given} ${r.applicant ?? ""} ${r.outcome}`)}
            rows={open.rows.map((r) => {
              const [word, kind] = BULK_OUTCOME[r.outcome] ?? [r.outcome, "grey"];
              return [<span key="n" className="tnum sub2">{r.row_no}</span>, <span key="g" className="tnum">{r.given}</span>, <Pil key="o" kind={kind}>{word}</Pil>,
                <span key="a">{r.applicant ?? "—"}</span>, <span key="d" className="tnum">{r.default_number ?? "—"}</span>, <span key="x" className="sub2">{r.detail ?? ""}</span>];
            })} />
        </Modal>
      ) : null}
    </Panel>
  );
}
