"use client";

/** V558: the lifecycle reconciliation's batches and history — every batch with what it did within the reader's scope, every
 *  reconciliation (names A–Z) with its outcome, the status and level before and after, and the correction that reversed it,
 *  if any. A reconciliation is corrected on a reason, one at a time or a whole batch, and is never rewritten. */
import { useEffect, useState } from "react";
import { useQueryNav } from "@/lib/query-nav";
import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, LinkBtn, Note, Panel, PBody, Pil } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, Modal } from "@/components/proto/blocks";
import { brandedPrint, brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";
import { OUTCOME, batchPath, fmt, reasonOk, recWord, type Batch, type Reconciliation } from "@/lib/lifecycle";
import type { LifeParams } from "./Lifecycle";

const API = "/api/bff/api/v1/cohorts/lifecycle";
type Problem = Parameters<typeof notifyProblem>[0];
const when = (iso: string | null | undefined) => (iso ? new Date(iso).toLocaleString("en-GB", { day: "numeric", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit" }) : "—");
const name = (r: { surname: string; other_names: string }) => `${r.surname}, ${r.other_names}`;
const word = (s: string) => s.toLowerCase().replace(/_/g, " ");

export function LifecycleHistory({ params, scope, canAct, generatedBy, href, onChanged }: {
  params: LifeParams; scope: { fac: string; dept: string; prog: string; q: string }; canAct: boolean; generatedBy: string | null;
  href: (patch: Record<string, string>) => string; onChanged: () => void;
}) {
  const go = useQueryNav();
  const page = Math.max(1, Number(params.page || 1));
  const [batches, setBatches] = useState<Batch[] | null>(null);
  const [history, setHistory] = useState<{ rows: Reconciliation[]; total: number; page: number; size: number } | null>(null);
  const [failed, setFailed] = useState<string | null>(null);
  const [tick, setTick] = useState(0);
  const [correct, setCorrect] = useState<{ id?: string; batch?: string; who: string; reason: string } | null>(null);
  const [progress, setProgress] = useState<string | null>(null);

  const query = (p: number, size: number) => {
    const qs = new URLSearchParams();
    for (const [k, v] of Object.entries({ batch: params.batch, outcome: params.outcome, corrected: params.corrected, fac: scope.fac, dept: scope.dept, prog: scope.prog, q: scope.q }))
      if (v) qs.set(k, v);
    qs.set("page", String(p));
    qs.set("size", String(size));
    return `${API}/history?${qs.toString()}`;
  };
  const historyUrl = query(page, 50);

  useEffect(() => {
    let live = true;
    (async () => {
      try {
        const [b, h] = await Promise.all([fetch(`${API}/batches`, { cache: "no-store" }), fetch(historyUrl, { cache: "no-store" })]);
        const bj = await b.json().catch(() => null);
        const hj = await h.json().catch(() => null);
        if (!live) return;
        if (!b.ok || !h.ok) { setFailed(((b.ok ? hj : bj) as { title?: string } | null)?.title ?? "The history could not be read."); return; }
        setFailed(null);
        setBatches(bj as Batch[]);
        setHistory(hj as { rows: Reconciliation[]; total: number; page: number; size: number });
      } catch { if (live) setFailed("The connection to the portal dropped."); }
    })();
    return () => { live = false; };
  }, [historyUrl, tick]);

  async function runCorrect() {
    if (!correct) return;
    const reason = correct.reason.trim();
    const say = `Lifecycle reconciliation corrected: ${reason}`;
    if (correct.id) {
      const r = await fetch(`${API}/reconciliations/${correct.id}/correct`, { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(say) }, body: JSON.stringify({ reason }) });
      const j = await r.json().catch(() => null);
      if (!r.ok) { notifyProblem((j ?? { status: r.status, title: r.statusText }) as Problem); return; }
      notify(`The reconciliation of ${correct.who} was corrected`);
    } else if (correct.batch) {
      const path = batchPath(correct.batch);
      if (!path) return;
      let done = 0; let refused = 0;
      for (let round = 0; round < 500; round++) {
        setProgress(`Corrected ${fmt(done)}…`);
        const r = await fetch(`${API}/batches/${path}/correct`, { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(say) }, body: JSON.stringify({ reason }) });
        const j = (await r.json().catch(() => null)) as { corrected?: number; refused?: unknown[]; done?: boolean } | null;
        if (!r.ok) { notifyProblem((j ?? { status: r.status, title: r.statusText }) as Problem); break; }
        done += Number(j?.corrected ?? 0);
        refused = j?.refused?.length ?? 0;
        if (j?.done) break;
      }
      setProgress(null);
      notify(`${correct.batch}: ${fmt(done)} corrected${refused ? `, ${fmt(refused)} could not be (the status moved since, or the Senate has acted)` : ""}`, refused ? "warn" : "ok");
    }
    setCorrect(null);
    setTick((t) => t + 1);
    onChanged();
  }

  async function exportHistory(kind: "xlsx" | "pdf") {
    if (!history?.total) return;
    const rows: Reconciliation[] = [];
    for (let p = 1; (p - 1) * 2000 < history.total && p <= 25; p++) {
      const r = await fetch(query(p, 2000), { cache: "no-store" });
      if (!r.ok) { notifyProblem({ status: r.status, title: "The history could not be read." } as Problem); return; }
      const j = (await r.json()) as { rows: Reconciliation[] };
      rows.push(...j.rows);
      if (j.rows.length < 2000) break;
    }
    const head = ["Student", "Matric No.", "Programme", "Batch", "Session", "Recommendation", "Outcome", "Status before", "Status after", "Level before", "Level after",
      "Reason", "Reconciled by", "Reconciled on", "Corrected"];
    const body = rows.map((x) => [name(x), x.matric_no ?? "", x.programme, x.batch_ref, x.effective_session, recWord(x.recommendation), OUTCOME[x.outcome] ?? x.outcome,
      word(x.previous_status), word(x.new_status), x.previous_level ?? "", x.new_level ?? "", x.reason, x.reconciled_by ?? "", when(x.reconciled_at),
      x.corrected_at ? `${when(x.corrected_at)}: ${x.correction_reason ?? ""}` : ""]);
    const title = `${params.batch || "Every batch"} — Lifecycle reconciliation history`;
    if (kind === "xlsx") downloadBlob(await brandedXlsx(title, head, body, { sheetName: "History", serial: docSerial("LCH") }), "lifecycle-reconciliation-history.xlsx");
    else brandedPrint(title, "Every reconciliation, as it was made", head.slice(0, 13), body.map((r) => r.slice(0, 13)), docSerial("LCH"), { generatedBy, orientation: "landscape" });
  }

  return (
    <>
      {failed ? <Note kind="bad" title="The history could not be read">{failed}</Note> : null}
      <Panel title="Batches" right="Newest first · counted within your scope">
        {batches && batches.length ? (
          <DTable pageSize={10} cols={["Batch", "Description", "Session|mid", "Reconciled|mid", "Left out|mid", "Corrected|mid", "What it did", "By", "|num"]} rows={batches.map((b, i) => [
            <a key={"r" + i} className="lnk tnum" href={href({ view: "batches", batch: b.batch_ref, page: "" })}>{b.batch_ref}</a>,
            <span key={"d" + i}>{b.description}<div className="sub2">{b.scope ?? ""}{b.closed_at ? "" : " · still open"}</div></span>,
            <span key={"s" + i} className="tnum">{b.effective_session}</span>,
            <span key={"n" + i} className="tnum">{fmt(b.reconciled)}</span>,
            <span key={"k" + i} className={`tnum${b.skipped ? " ink-amber" : ""}`}>{fmt(b.skipped)}</span>,
            <span key={"c" + i} className={`tnum${b.corrected ? " ink-red" : ""}`}>{fmt(b.corrected)}</span>,
            <span key={"w" + i} className="sub2">{[b.spillover_confirmed ? `${fmt(b.spillover_confirmed)} spillover confirmed` : "", b.kept_at_limit ? `${fmt(b.kept_at_limit)} kept at the maximum` : "",
              b.status_changed ? `${fmt(b.status_changed)} status changed` : "", b.graduation_list ? `${fmt(b.graduation_list)} to the graduation list` : ""].filter(Boolean).join(" · ") || "—"}</span>,
            <span key={"b" + i} className="sub2">{b.created_by ?? "—"}<div>{when(b.created_at)}</div></span>,
            canAct && Number(b.reconciled) > Number(b.corrected) ? <Btn key={"x" + i} kind="ghost" size="sm" onClick={() => setCorrect({ batch: b.batch_ref, who: b.batch_ref, reason: "" })}>Correct the batch…</Btn> : <span key={"x" + i} />,
          ])} />
        ) : batches ? <PBody><div className="sub2">No reconciliation batch yet.</div></PBody> : <PBody><div className="sub2">Reading…</div></PBody>}
      </Panel>

      <Panel title={params.batch ? `History of ${params.batch}` : "History"} right={<span className="row row--inline row--tight">
        <span className="sub2">{history ? `${fmt(history.total)} reconciliation${history.total === 1 ? "" : "s"} · names A–Z` : ""}</span>
        {history?.total ? <><Btn kind="ghost" size="sm" onClick={() => exportHistory("xlsx")}>Excel</Btn><Btn kind="ghost" size="sm" onClick={() => exportHistory("pdf")}>PDF</Btn></> : null}
      </span>}>
        <PBody>
          <div className="row">
            <Field id="lh-outcome" label="Outcome" style={{ flex: "1 1 200px" }}>
              <select id="lh-outcome" className="ctl" value={params.outcome} onChange={(e) => go(href({ view: "batches", outcome: e.target.value, page: "" }))}>
                <option value="">Any</option>{Object.entries(OUTCOME).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
              </select>
            </Field>
            <Field id="lh-corr" label="Corrected" style={{ flex: "1 1 150px" }}>
              <select id="lh-corr" className="ctl" value={params.corrected} onChange={(e) => go(href({ view: "batches", corrected: e.target.value, page: "" }))}>
                <option value="">Either</option><option value="false">Standing</option><option value="true">Corrected</option>
              </select>
            </Field>
            {params.batch ? <div style={{ alignSelf: "flex-end" }}><LinkBtn href={href({ view: "batches", batch: "", page: "" })}>Every batch</LinkBtn></div> : null}
          </div>
        </PBody>
        {history && history.rows.length ? (
          <DTable pageSize={0} cols={["S/N|num", "Student", "Batch", "Recommendation", "Outcome", "Status|mid", "Level|mid", "By", "|num"]} rows={history.rows.map((x, i) => [
            <span key="sn" className="tnum sub2">{(history.page - 1) * history.size + i + 1}</span>,
            <span key="n"><strong>{name(x)}</strong><div className="sub2 tnum">{x.matric_no ?? ""} · {x.programme}</div></span>,
            <span key="b" className="tnum">{x.batch_ref}<div className="sub2">{x.effective_session}</div></span>,
            <span key="r">{recWord(x.recommendation)}<div className="sub2">{x.confidence.toLowerCase()} confidence</div></span>,
            <span key="o">{OUTCOME[x.outcome] ?? x.outcome}{x.graduand_unmet ? <div className="sub2">audit: {x.graduand_unmet}</div> : null}
              {x.corrected_at ? <div><Pil kind="bad">Corrected</Pil> <span className="sub2">{when(x.corrected_at)} by {x.corrected_by ?? "—"}: {x.correction_reason}</span></div> : null}</span>,
            <span key="st" className="tnum">{x.previous_status === x.new_status ? word(x.new_status) : `${word(x.previous_status)} → ${word(x.new_status)}`}</span>,
            <span key="l" className="tnum">{x.previous_level === x.new_level ? x.new_level ?? "—" : `${x.previous_level} → ${x.new_level}`}</span>,
            <span key="by" className="sub2">{x.reconciled_by ?? "—"}<div>{when(x.reconciled_at)}</div></span>,
            canAct && !x.corrected_at ? <Btn key="c" kind="ghost" size="sm" onClick={() => setCorrect({ id: x.id, who: name(x), reason: "" })}>Correct…</Btn> : <span key="c" />,
          ])} />
        ) : history ? <PBody><div className="sub2">No reconciliation within these filters.</div></PBody> : null}
        {history && history.total > history.size ? (
          <PBody><div className="row row--base">
            <span className="sub2">Showing {fmt((history.page - 1) * history.size + 1)}–{fmt(Math.min(history.page * history.size, history.total))} of {fmt(history.total)}</span>
            <span className="grow" />
            {page > 1 ? <LinkBtn href={href({ view: "batches", page: String(page - 1) })}>Previous</LinkBtn> : null}
            {history.page * history.size < history.total ? <LinkBtn href={href({ view: "batches", page: String(page + 1) })}>Next</LinkBtn> : null}
          </div></PBody>
        ) : null}
      </Panel>

      {correct ? (
        <Modal title={correct.batch ? `Correct ${correct.batch}` : `Correct the reconciliation of ${correct.who}`}
          sub="The status is changed back, a level it raised is put back where nobody has moved it since, and a graduation-list entry it added is removed while the Senate has not acted"
          onClose={() => { if (!progress) setCorrect(null); }}
          foot={<><Btn kind="ghost" disabled={progress !== null} onClick={() => setCorrect(null)}>Cancel</Btn>
            <Btn kind="primary" busy={progress !== null} busyLabel={progress ?? "Correcting…"} disabled={!reasonOk(correct.reason)} onClick={() => runCorrect()}>Correct</Btn></>}>
          <Note kind="info" title="Nothing is deleted from the history">The reconciliation stays on record, marked corrected with your reason, and the student is under review again.</Note>
          <Field id="lh-reason" label="Why it is corrected" required>
            <textarea id="lh-reason" className="ctl" rows={3} maxLength={2000} value={correct.reason} onChange={(e) => setCorrect({ ...correct, reason: e.target.value })}
              placeholder="e.g. Reconciled on the wrong entry session; the admission letter says 2019/2020" />
          </Field>
        </Modal>
      ) : null}
    </>
  );
}
