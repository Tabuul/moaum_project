"use client";

/**
 * V702: duplicate results — a student with marks for one course on two classes in a semester (its BSU-/MOAU- twin, or a second course
 * under the code). The Registry's side (Exams & Records, the Registry, the Academic Office) or the Director of ICT chooses the class
 * that stands; the other is withdrawn from the student's registration, its mark kept on its sheet, so the transcript, the CGPA and the
 * broadsheet count the course once. The decision is written down with its reason and may be put back.
 */
import { useEffect, useMemo, useState } from "react";
import { useJson } from "@/lib/use-json";
import { ScopeBar, type Ceiling, type ScopeStructure } from "@/components/proto/ScopeBar";
import { Field, Modal } from "@/components/proto/blocks";
import { Btn, Note, Panel, PBody, Pil, Tabs } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";
import { reasonHeader } from "@/lib/reason";
import { roleLabel } from "@/lib/offices";
import type { Problem } from "@/lib/api";
import type { Scope } from "@/lib/scope";
import { RecordDetail } from "@/components/results/RecordDetail";
import {
  DECISION_WORD, DUPLICATE_HEADERS, duplicateCells, markWords, monitorQuery, resolveProblem, stageWord, toWithdraw, type DuplicateRow,
} from "@/lib/result-monitor";

interface Answer { session: string; semester: number; state: string; open: number; resolved: number; total: number; page: number; size: number; rows: DuplicateRow[] }
type Which = "OPEN" | "RESOLVED" | "ALL";
const SIZE = 50;

export function Duplicates({ scope, structure, sessions, ceiling }: { scope: Scope; structure: ScopeStructure; sessions: string[]; ceiling: Ceiling }) {
  const [state, setState] = useState<Which>("OPEN");
  const [typed, setTyped] = useState("");
  const [q, setQ] = useState("");
  const filters = useMemo(() => ({ session: scope.session, sem: scope.sem, fac: scope.fac, dept: scope.dept, prog: scope.prog }),
    [scope.session, scope.sem, scope.fac, scope.dept, scope.prog]);
  const viewKey = `${monitorQuery(filters)}|${state}|${q}`;
  const [pager, setPager] = useState<{ key: string; page: number }>({ key: "", page: 1 });
  const page = pager.key === viewKey ? pager.page : 1;
  const setPage = (n: number) => setPager({ key: viewKey, page: n });
  const [tick, setTick] = useState(0);
  const [choose, setChoose] = useState<{ d: DuplicateRow; keep: string; reason: string } | null>(null);
  const [undo, setUndo] = useState<{ d: DuplicateRow; id: string; note: string } | null>(null);
  const [open, setOpen] = useState<{ offeringId: string; studentId: string } | null>(null);
  const [busy, setBusy] = useState(false);
  const [exporting, setExporting] = useState(false);
  useEffect(() => { const t = setTimeout(() => setQ(typed.trim()), 350); return () => clearTimeout(t); }, [typed]);
  const { data, failed, loading } = useJson<Answer>(`/api/bff/api/v1/results/monitor/duplicates${monitorQuery({ ...filters, state, q, page, size: SIZE })}`, tick);

  async function post(path: string, body: unknown, why: string) {
    const r = await fetch(`/api/bff/api/v1/results/monitor/${path}`, {
      method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(why) }, body: JSON.stringify(body),
    });
    const j = await r.json().catch(() => null);
    if (!r.ok) throw j ?? { status: r.status, title: "Not done" };
    return j;
  }

  async function resolve() {
    if (!choose) return;
    const drops = toWithdraw(choose.keep, choose.d.classes);
    const kept = choose.d.classes.find((c) => c.offeringId === choose.keep);
    setBusy(true);
    try {
      // a course on three classes takes a decision for each class withdrawn
      for (const c of drops) {
        await post("duplicates/resolve", { studentId: choose.d.studentId, keep: choose.keep, drop: c.offeringId, reason: choose.reason.trim() },
          `${choose.d.number ?? choose.d.studentName}: ${kept?.courseCode} stands, ${c.courseCode} withdrawn — ${choose.reason.trim()}`);
      }
      notify(`${kept?.courseCode} stands for ${choose.d.studentName}; ${drops.map((c) => c.courseCode).join(", ")} withdrawn from the registration, the mark kept on its sheet.`);
      setChoose(null);
      setTick((x) => x + 1);
    } catch (e) {
      notifyProblem(e as Problem, "The duplicate was not resolved");
      setTick((x) => x + 1);
    } finally { setBusy(false); }
  }

  async function putBack() {
    if (!undo) return;
    setBusy(true);
    try {
      await post(`duplicates/${undo.id}/undo`, { note: undo.note.trim() }, `${undo.d.number ?? undo.d.studentName}: duplicate decision put back — ${undo.note.trim()}`);
      notify(`Put back: both classes of ${undo.d.baseCode} stand again for ${undo.d.studentName}.`);
      setUndo(null);
      setTick((x) => x + 1);
    } catch (e) {
      notifyProblem(e as Problem, "The decision was not put back");
    } finally { setBusy(false); }
  }

  async function exportXlsx() {
    setExporting(true);
    notify("Export processing…", "ok", 2500);
    try {
      const r = await fetch(`/api/bff/api/v1/results/monitor/duplicates${monitorQuery({ ...filters, state, q, page: 1, size: 5000 })}`, { cache: "no-store" });
      const j = await r.json().catch(() => null);
      if (!r.ok) throw j ?? { status: r.status, title: "The export could not read the duplicates" };
      const rows = (j.rows as DuplicateRow[]).flatMap((d) => duplicateCells(d)).map((row) => row.map((c) => (typeof c === "number" ? c : String(c ?? ""))));
      const meta: [string, string][] = [["Session", j.session], ["Semester", String(j.semester)], ["Listed", state === "OPEN" ? "To decide" : state === "RESOLVED" ? "Resolved" : "Every one"],
        ...(scope.fac ? [["Faculty", scope.fac] as [string, string]] : []), ...(scope.dept ? [["Department", scope.dept] as [string, string]] : []),
        ...(scope.prog ? [["Programme", scope.prog] as [string, string]] : [])];
      downloadBlob(await brandedXlsx("Duplicate results", DUPLICATE_HEADERS, rows, { serial: docSerial("RDP"), meta, sheetName: "Duplicates" }),
        `Duplicate results ${String(j.session).replace("/", "-")}.xlsx`);
      notify(`Export completed — ${(j.rows as DuplicateRow[]).length.toLocaleString()} duplicate${j.rows.length === 1 ? "" : "s"}.`);
    } catch (e) {
      notifyProblem(e as Problem, "The export did not complete");
    } finally { setExporting(false); }
  }

  const problem = choose ? resolveProblem(choose.keep, choose.d.classes, choose.reason) : null;
  return (
    <>
      <ScopeBar scope={scope} structure={structure} sessions={sessions} ceiling={ceiling} what="duplicates" count={data?.rows.length ?? 0} of={data?.total ?? 0}
        onExport={data?.total ? () => void exportXlsx() : undefined} />
      {failed ? <Note kind="bad" title="Unable to load the duplicates">{failed}</Note> : null}
      <Panel title={data ? `Duplicate results · ${data.session} · semester ${data.semester}` : "Duplicate results"} right={<span className="row row--inline">
        {loading ? <span className="sub2">Loading…</span> : null}
        <Btn kind="ghost" disabled={exporting || !data?.total} busy={exporting} onClick={() => void exportXlsx()}>Excel</Btn>
      </span>}>
        <PBody>
          <p className="sub2">One course with marks on two classes — its BSU-/MOAU- twin, or a second course under the code. Choose the class that stands: the other is withdrawn from the registration, its mark kept on its sheet, so the transcript, the CGPA and the broadsheet count the course once.</p>
          <div className="row" style={{ gap: 6, margin: "8px 0" }}>
            <Tabs<Which> label="Which duplicates" value={state} onChange={setState}
              items={[{ id: "OPEN", label: "To decide", count: (data?.open ?? 0).toLocaleString() }, { id: "RESOLVED", label: "Resolved", count: (data?.resolved ?? 0).toLocaleString() },
                { id: "ALL", label: "Every one" }]} />
            <span className="grow" />
            <input className="ctl" style={{ maxWidth: 300 }} placeholder="Search name, matric, course" value={typed} onChange={(e) => setTyped(e.target.value)} aria-label="Search the duplicates" />
          </div>
          {data ? (
            <DTable pageSize={0} cols={["S/N|num", "Student", "Programme", "Level|num", "Course", "Classes and their results", ""]}
              rows={data.rows.map((d, i) => {
                const kept = d.classes.find((c) => c.decision === "KEPT");
                const dropped = d.classes.filter((c) => c.decision === "WITHDRAWN");
                return [
                  (data.page - 1) * data.size + i + 1,
                  <span key="s">{d.studentName}<span className="sub2 tnum" style={{ display: "block" }}>{d.number ?? "—"}</span></span>,
                  d.programmeCode, d.level ?? "—", <b key="b" className="tnum">{d.baseCode}</b>,
                  <span key="c" style={{ display: "grid", gap: 4 }}>
                    {d.classes.map((c) => (
                      <span key={c.offeringId} className="row row--inline" style={{ gap: 6 }}>
                        <b className="tnum">{c.courseCode}</b>
                        <span>{markWords({ ca: c.ca, exam: c.exam, total: c.total, grade: c.grade })}</span>
                        <span className="sub2">{`${stageWord(c.stage)} · registration ${c.entryStatus ? c.entryStatus.toLowerCase() : "none"}`}</span>
                        {c.decision ? <Pil kind={c.decision === "KEPT" ? "ok" : "grey"}>{DECISION_WORD[c.decision]}</Pil> : null}
                        <Btn kind="ghost" onClick={() => setOpen({ offeringId: c.offeringId, studentId: d.studentId })}>View</Btn>
                        {!d.resolved && c.decision !== "WITHDRAWN" ? <Btn kind="primary" onClick={() => setChoose({ d, keep: c.offeringId, reason: "" })}>Keep this one</Btn> : null}
                      </span>
                    ))}
                    {kept && dropped.length ? <span className="sub2">{`Decided by ${roleLabel(kept.decidedOffice ?? dropped[0].decidedOffice ?? "")}: ${dropped[0].decidedReason ?? ""}`}</span> : null}
                  </span>,
                  dropped.length ? <span key="u" style={{ display: "grid", gap: 4 }}>{dropped.map((c) => c.resolutionId ? (
                    <Btn key={c.resolutionId} kind="ghost" onClick={() => setUndo({ d, id: c.resolutionId!, note: "" })}>{`Put ${c.courseCode} back`}</Btn>) : null)}</span> : "",
                ];
              })} />
          ) : null}
          {data && !data.rows.length && !loading ? <Note kind="ok" title={state === "OPEN" ? "No duplicate to decide here" : "None listed"}>No student in the scope chosen has marks for one course on two classes{state === "RESOLVED" ? " resolved" : ""}.</Note> : null}
          {data ? (
            <div className="row" style={{ marginTop: 8 }}>
              <span className="sub2">{data.total ? `${((data.page - 1) * data.size + 1).toLocaleString()}–${Math.min(data.page * data.size, data.total).toLocaleString()} of ${data.total.toLocaleString()}` : ""}</span>
              <span className="grow" />
              <Btn kind="ghost" disabled={data.page <= 1 || loading} onClick={() => setPage(data.page - 1)}>Previous</Btn>
              <Btn kind="ghost" disabled={data.page * data.size >= data.total || loading} onClick={() => setPage(data.page + 1)}>Next</Btn>
            </div>
          ) : null}
        </PBody>
      </Panel>
      {choose ? (() => {
        const kept = choose.d.classes.find((c) => c.offeringId === choose.keep);
        const drops = toWithdraw(choose.keep, choose.d.classes);
        return (
          <Modal title={`${kept?.courseCode} stands — ${choose.d.studentName}`} sub={`${drops.map((c) => c.courseCode).join(", ")} withdrawn from the registration; the mark stays on its sheet`}
            onClose={() => setChoose(null)}
            foot={<><Btn kind="ghost" onClick={() => setChoose(null)}>Cancel</Btn><span className="grow" /><Btn kind="primary" disabled={!!problem || busy} busy={busy} onClick={() => void resolve()}>Keep it</Btn></>}>
            <DTable noPrint pageSize={0} cols={["Class", "Result", "Stage", "After"]} rows={choose.d.classes.filter((c) => c.decision !== "WITHDRAWN").map((c) => [
              <b key="c" className="tnum">{c.courseCode}</b>, markWords({ ca: c.ca, exam: c.exam, total: c.total, grade: c.grade }), stageWord(c.stage),
              c.offeringId === choose.keep ? <Pil key="k" kind="ok">Stands</Pil> : <Pil key="w" kind="grey">Withdrawn</Pil>])} />
            <Field id="dup-why" label="Why this class stands" required hint="Ten characters or more; it goes on the record with your name">
              <textarea id="dup-why" className="ctl" rows={3} value={choose.reason} onChange={(e) => setChoose({ ...choose, reason: e.target.value })} />
            </Field>
            {problem && choose.reason.trim().length ? <p className="sub2">{problem}</p> : null}
          </Modal>
        );
      })() : null}
      {undo ? (
        <Modal title={`Put back — ${undo.d.studentName}, ${undo.d.baseCode}`} sub="The withdrawn class's registration comes back as it stood; the decision stays on the record" onClose={() => setUndo(null)}
          foot={<><Btn kind="ghost" onClick={() => setUndo(null)}>Cancel</Btn><span className="grow" /><Btn kind="urgent" disabled={undo.note.trim().length < 10 || busy} busy={busy} onClick={() => void putBack()}>Put it back</Btn></>}>
          <Field id="dup-undo" label="Why it is put back" required hint="Ten characters or more">
            <textarea id="dup-undo" className="ctl" rows={3} value={undo.note} onChange={(e) => setUndo({ ...undo, note: e.target.value })} />
          </Field>
        </Modal>
      ) : null}
      {open ? <RecordDetail offeringId={open.offeringId} studentId={open.studentId} onClose={() => setOpen(null)} onChanged={() => setTick((x) => x + 1)} /> : null}
    </>
  );
}
