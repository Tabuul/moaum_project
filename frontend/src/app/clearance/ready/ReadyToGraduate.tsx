"use client";

/**
 * V668: Ready to graduate — the final clearances whose award is approved and which wait only on the Bursary (every other office has
 * cleared), each with the school-fee account read afresh: ready (nothing owed, for review or pending) first. The Bursar confirms the
 * students chosen; each is confirmed on its own through the clearance engine, read again, and graduated in the same act — or refused
 * with the reason. One student's full check opens on the clearance desk.
 */
import { useState } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { useQueryNav } from "@/lib/query-nav";
import type { ReadyQueue, ReadyRow } from "@/lib/clearance";
import { brandedPrint, brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, LinkBtn, Note, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, Modal } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";

const naira = (n: unknown) => `₦${Number(n ?? 0).toLocaleString("en-NG", { maximumFractionDigits: 2 })}`;
const HEAD = ["S/N", "Student", "Matric No.", "Programme", "Department", "Award", "Senate / Board minute", "Assessed (₦)", "Paid (₦)", "Waived (₦)",
  "Outstanding (₦)", "Sessions owing", "Status", "Clearance"];

export function ReadyToGraduate({ queue, q }: { queue: ReadyQueue; q: string }) {
  const router = useRouter();
  const nav = useQueryNav();
  const [search, setSearch] = useState(q);
  const [selected, setSelected] = useState<Set<string>>(new Set());
  const [asking, setAsking] = useState(false);
  const [busy, setBusy] = useState(false);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [refused, setRefused] = useState<{ process: string; code: string; why: string }[]>([]);
  const ready = queue.rows.filter((r) => r.ready);
  const chosen = queue.rows.filter((r) => selected.has(r.process_id));

  async function confirm() {
    setBusy(true); setProblem(null);
    try {
      const r = await fetch("/api/bff/api/v1/clearance/ready-to-graduate/confirm", {
        method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`Final clearance confirmed for ${selected.size} student(s)`) },
        body: JSON.stringify({ processes: [...selected] }),
      });
      const j = await r.json().catch(() => null);
      if (!r.ok) { const p = (j ?? { status: r.status, title: "The confirmation was refused." }) as Problem; setProblem(p); notifyProblem(p); return; }
      const out = j as { cleared: number; graduated: number; refused: { process: string; code: string; why: string }[] };
      notify(out.graduated ? `${out.graduated} student(s) cleared and graduated${out.refused.length ? `, ${out.refused.length} refused` : ""}` : `${out.refused.length} refused`);
      setRefused(out.refused); setSelected(new Set()); setAsking(false);
      router.refresh();
    } finally { setBusy(false); }
  }

  function rows(list: ReadyRow[]): (string | number)[][] {
    return list.map((r, i) => [i + 1, `${r.surname}, ${r.other_names}`, r.matric_no ?? "", r.programme ?? "", r.department ?? "", r.award ?? "", r.minute ?? "",
      Number(r.assessed), Number(r.paid), Number(r.waived), Number(r.outstanding), r.owing ?? "",
      r.ready ? "Ready" : r.review_periods || r.pending_periods ? "Being assessed" : "Owing", r.reference]);
  }
  async function exportAs(kind: "xlsx" | "pdf") {
    const title = "Ready to graduate";
    const meta: [string, string][] = [["Students", String(queue.total)], ["Ready", String(queue.ready)], ["Search", q || "All"]];
    if (kind === "xlsx") downloadBlob(await brandedXlsx(title, HEAD, rows(queue.rows), { sheetName: "Ready to graduate", serial: docSerial("RTG"), meta }), "ready-to-graduate.xlsx");
    else brandedPrint(title, "Final clearances waiting only on the Bursary", HEAD, rows(queue.rows), docSerial("RTG"), { meta, orientation: "landscape" });
  }

  return (
    <>
      <Panel title="Final clearances waiting on the Bursary" right={<span className="row row--tight">
        <LinkBtn kind="ghost" href="/clearance?wf=FINAL">Clearance desk</LinkBtn>
        <Btn kind="ghost" disabled={!queue.total} onClick={() => void exportAs("xlsx")}>Export (Excel)</Btn>
        <Btn kind="ghost" disabled={!queue.total} onClick={() => void exportAs("pdf")}>PDF</Btn>
      </span>}>
        <PBody>
          <div className="sub2 mb-2">Each student here has an approved award and every other office has cleared them. The Bursary&rsquo;s clearance is the last word: it
            graduates the student, and it is refused while school fees are owed for any session or a semester is still being assessed. The amounts are read afresh.</div>
          <Tiles items={[
            ["Waiting on the Bursary", queue.total.toLocaleString(), null, "Every other office cleared"],
            ["Ready to graduate", queue.ready.toLocaleString(), queue.ready ? "var(--green-ink)" : null, "Nothing owed, nothing being assessed"],
            ["Owing or being assessed", (queue.total - queue.ready).toLocaleString(), queue.total - queue.ready ? "var(--red-ink)" : null, "Not cleared until settled"],
          ]} />
          <form className="row row--end mt-2" style={{ flexWrap: "wrap" }} onSubmit={(e) => { e.preventDefault(); nav(`/clearance/ready${search.trim() ? `?q=${encodeURIComponent(search.trim())}` : ""}`); }}>
            <Field id="rtg-q" label="Search" hint="Name, matriculation number or clearance reference">
              <input id="rtg-q" className="ctl" value={search} onChange={(e) => setSearch(e.target.value)} autoComplete="off" />
            </Field>
            <Btn kind="ghost" type="submit">Search</Btn>
            {queue.canConfirm ? (
              <>
                <span className="grow" />
                <Btn kind="ghost" disabled={!ready.length} onClick={() => setSelected(new Set(ready.map((r) => r.process_id)))}>Select every ready student ({ready.length})</Btn>
                <Btn kind="go" disabled={!selected.size || busy} onClick={() => setAsking(true)}>Confirm clearance &amp; graduate ({selected.size})</Btn>
              </>
            ) : null}
          </form>
        </PBody>
        {problem ? <PBody><ProblemNotice problem={problem} /></PBody> : null}
        {refused.length ? (
          <PBody><Note kind="bad" title={`${refused.length} not cleared — the record says why`} action={<Btn kind="ghost" onClick={() => setRefused([])}>Done</Btn>}>
            {refused.slice(0, 8).map((r) => `${queue.rows.find((x) => x.process_id === r.process)?.surname ?? r.process.slice(0, 8)}: ${r.why}`).join(" · ")}
          </Note></PBody>
        ) : null}
        {queue.rows.length ? (
          <DTable pageSize={50}
            cols={[...(queue.canConfirm ? ["|mid"] : []), "S/N|num", "Student", "Award", "Assessed|num", "Paid|num", "Waived|num", "Outstanding|num", "Status|mid", "|num"]}
            rows={queue.rows.map((r, i) => [
              ...(queue.canConfirm ? [<input key="x" type="checkbox" className="chk" aria-label={`Select ${r.surname}, ${r.other_names}`} disabled={!r.ready}
                checked={selected.has(r.process_id)} onChange={(e) => { const n = new Set(selected); if (e.target.checked) n.add(r.process_id); else n.delete(r.process_id); setSelected(n); }} />] : []),
              <span key="n" className="tnum sub2">{i + 1}</span>,
              <span key="s"><b>{r.surname}, {r.other_names}</b><span className="blk sub2 tnum">{r.matric_no ?? "—"} · {r.reference}</span><span className="blk sub2">{r.programme ?? ""}{r.department ? ` · ${r.department}` : ""}</span></span>,
              <span key="a" className="sub2">{r.award ?? "—"}<span className="blk">{r.basis === "COLLEGE_BOARD" ? "College Board" : "Senate"} minute {r.minute ?? "—"}</span></span>,
              <span key="as" className="tnum">{naira(r.assessed)}</span>, <span key="p" className="tnum">{naira(r.paid)}</span>, <span key="w" className="tnum">{naira(r.waived)}</span>,
              <span key="o" className="tnum" style={{ color: Number(r.outstanding) >= 1 ? "var(--red-ink)" : undefined }}>{naira(r.outstanding)}{r.owing ? <span className="blk sub2">{r.owing}</span> : null}</span>,
              <span key="st">{r.ready ? <Pil kind="ok">Ready</Pil> : r.review_periods || r.pending_periods ? <Pil kind="warn">Being assessed</Pil> : <Pil kind="bad">Owing</Pil>}</span>,
              <LinkBtn key="o2" kind="ghost" size="sm" href={`/clearance?${new URLSearchParams({ wf: "FINAL", session: r.session, process: r.process_id }).toString()}`}>Open</LinkBtn>,
            ])} />
        ) : <PBody><div className="sub2">{q ? "No student matches." : "No final clearance waits on the Bursary."}</div></PBody>}
      </Panel>

      {asking ? (
        <Modal title="Confirm clearance & graduate" sub={`${chosen.length} student(s)`} onClose={() => setAsking(false)} wide
          foot={<><Btn kind="ghost" onClick={() => setAsking(false)}>Cancel</Btn><span className="grow" />
            <Btn kind="go" disabled={busy || !chosen.length} onClick={() => void confirm()}>{busy ? "Processing clearance..." : "CONFIRM CLEARANCE & GRADUATE"}</Btn></>}>
          <div className="sub2 mb-2">Each student is confirmed on their own: the Bursary&rsquo;s stage is cleared against a fresh reading of their school fees for every
            session and semester, the final clearance completes, and the record reads GRADUATED in the same act. Anyone who now owes, or has a semester being assessed,
            is refused with the reason and stays as they are.</div>
          <DTable pageSize={0} cols={["Student", "Award", "Outstanding|num"]} rows={chosen.map((r) => [
            <span key="s"><b>{r.surname}, {r.other_names}</b><span className="blk sub2 tnum">{r.matric_no ?? "—"}</span></span>,
            <span key="a" className="sub2">{r.award ?? "—"}</span>, <span key="o" className="tnum">{naira(r.outstanding)}</span>])} />
        </Modal>
      ) : null}
    </>
  );
}
