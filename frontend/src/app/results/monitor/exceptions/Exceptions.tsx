"use client";

/** V700: the results that need a look (assessment.result_exceptions), by kind, each opening the record it is about */
import { useEffect, useMemo, useState } from "react";
import { useJson } from "@/lib/use-json";
import { ScopeBar, type Ceiling, type ScopeStructure } from "@/components/proto/ScopeBar";
import { Btn, LinkBtn, Note, Panel, PBody, Pil } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { brandedPrint, brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";
import type { Problem } from "@/lib/api";
import type { Scope } from "@/lib/scope";
import { RecordDetail } from "@/components/results/RecordDetail";
import { EXCEPTION_KINDS, KIND_NOTE, KIND_WORD, monitorQuery, stageWord, type ExceptionKind } from "@/lib/result-monitor";

interface Row { kind: ExceptionKind; studentId: string | null; offeringId: string | null; sheetId: string | null; courseCode: string; courseTitle: string | null;
  level: number | null; detail: string; number: string | null; surname: string | null; otherNames: string | null; programmeCode: string | null; programme: string | null; stage: string | null }
interface Answer { session: string; semester: number; counts: Record<ExceptionKind, number>; total: number; page: number; size: number; rows: Row[] }

const SIZE = 50;
const HEADERS = ["Exception", "Student", "Matric No.", "Programme", "Level", "Course Code", "Course Title", "Detail", "Stage"];

export function Exceptions({ scope, structure, sessions, ceiling, initialKind }: { scope: Scope; structure: ScopeStructure; sessions: string[]; ceiling: Ceiling; initialKind?: string }) {
  const [kind, setKind] = useState<ExceptionKind | "">(EXCEPTION_KINDS.includes(initialKind as ExceptionKind) ? (initialKind as ExceptionKind) : "");
  const [typed, setTyped] = useState("");
  const [q, setQ] = useState("");
  const filters = useMemo(() => ({ session: scope.session, sem: scope.sem, fac: scope.fac, dept: scope.dept, prog: scope.prog, level: scope.level }),
    [scope.session, scope.sem, scope.fac, scope.dept, scope.prog, scope.level]);
  // the page holds for the view it was turned in; new filters, a kind or a search start again
  const viewKey = `${monitorQuery(filters)}|${kind}|${q}`;
  const [pager, setPager] = useState<{ key: string; page: number }>({ key: "", page: 1 });
  const page = pager.key === viewKey ? pager.page : 1;
  const setPage = (n: number) => setPager({ key: viewKey, page: n });
  const [tick, setTick] = useState(0);
  const [open, setOpen] = useState<{ offeringId: string; studentId: string } | null>(null);
  const [exporting, setExporting] = useState(false);
  useEffect(() => { const t = setTimeout(() => setQ(typed.trim()), 350); return () => clearTimeout(t); }, [typed]);
  const { data, failed, loading } = useJson<Answer>(`/api/bff/api/v1/results/monitor/exceptions${monitorQuery({ ...filters, kind, q, page, size: SIZE })}`, tick);
  const load = () => setTick((x) => x + 1);

  const cells = (r: Row) => [KIND_WORD[r.kind] ?? r.kind, r.surname ? `${r.surname.toUpperCase()}, ${r.otherNames}` : "—", r.number ?? "—", r.programme ?? r.programmeCode ?? "—",
    r.level ?? "—", r.courseCode, r.courseTitle ?? "", r.detail, stageWord(r.stage)];

  async function exportAs(as: "xlsx" | "pdf") {
    setExporting(true);
    notify("Export processing…", "ok", 2500);
    const win = as === "pdf" ? window.open("", "_blank") : null;
    try {
      const r = await fetch(`/api/bff/api/v1/results/monitor/exceptions${monitorQuery({ ...filters, kind, q, page: 1, size: 5000 })}`, { cache: "no-store" });
      const j = await r.json().catch(() => null);
      if (!r.ok) throw j ?? { status: r.status, title: "The export could not read the exceptions" };
      const rows = (j.rows as Row[]).map((x) => cells(x).map((c) => (typeof c === "number" ? c : String(c))));
      const meta: [string, string][] = [["Session", j.session], ["Semester", String(j.semester)], ["Exception", kind ? KIND_WORD[kind] : "Every kind"],
        ...(scope.fac ? [["Faculty", scope.fac] as [string, string]] : []), ...(scope.dept ? [["Department", scope.dept] as [string, string]] : []),
        ...(scope.prog ? [["Programme", scope.prog] as [string, string]] : []), ...(scope.level ? [["Level", scope.level] as [string, string]] : [])];
      const serial = docSerial("REX");
      if (as === "xlsx") downloadBlob(await brandedXlsx("Result exceptions", HEADERS, rows, { serial, meta, sheetName: "Exceptions" }), `Result exceptions ${String(j.session).replace("/", "-")}.xlsx`);
      else brandedPrint("Result exceptions", meta.map(([k, v]) => `${k}: ${v}`).join(" · "), HEADERS, rows, serial, { meta, orientation: "landscape", window: win });
      notify(`Export completed — ${rows.length.toLocaleString()} exception${rows.length === 1 ? "" : "s"}.`);
    } catch (e) {
      win?.close();
      notifyProblem(e as Problem, "The export did not complete");
    } finally { setExporting(false); }
  }

  const total = data ? Object.values(data.counts).reduce((a, b) => a + b, 0) : 0;
  return (
    <>
      <ScopeBar scope={scope} structure={structure} sessions={sessions} ceiling={ceiling} what="exceptions" count={data?.rows.length ?? 0} of={data?.total ?? 0}
        onExport={data?.total ? () => void exportAs("xlsx") : undefined} />
      {failed ? <Note kind="bad" title="Unable to load the exceptions">{failed}</Note> : null}
      <Panel title={data ? `Result exceptions · ${data.session} · semester ${data.semester}` : "Result exceptions"} right={<span className="row row--inline">
        {loading ? <span className="sub2">Loading the exceptions…</span> : null}
        <Btn kind="ghost" disabled={exporting || !data?.total} busy={exporting} onClick={() => void exportAs("xlsx")}>Excel</Btn>
        <Btn kind="ghost" disabled={exporting || !data?.total} busy={exporting} onClick={() => void exportAs("pdf")}>PDF</Btn>
      </span>}>
        <PBody>
          <p className="sub2">Read from the same records as the result viewer and the broadsheet. A result that is not there is never counted as a fail.</p>
          <div className="row" style={{ gap: 6, margin: "8px 0" }}>
            <Btn kind={kind === "" ? "primary" : "ghost"} onClick={() => setKind("")}>{`Every kind (${total.toLocaleString()})`}</Btn>
            {EXCEPTION_KINDS.map((k) => (
              <Btn key={k} kind={kind === k ? "primary" : "ghost"} title={KIND_NOTE[k]} onClick={() => setKind(k)}>{`${KIND_WORD[k]} (${(data?.counts[k] ?? 0).toLocaleString()})`}</Btn>
            ))}
            <span className="grow" />
            <input className="ctl" style={{ maxWidth: 300 }} placeholder="Search name, matric, course" value={typed} onChange={(e) => setTyped(e.target.value)} aria-label="Search the exceptions" />
          </div>
          {kind ? <Note kind="info" title={KIND_WORD[kind]}
            action={kind === "DUPLICATE_RESULT" ? <LinkBtn href="/results/monitor/duplicates" kind="primary">Resolve them</LinkBtn> : undefined}>{KIND_NOTE[kind]}</Note> : null}
          {data ? (
            <DTable pageSize={0} cols={["S/N|num", "Exception", "Student", "Matric No.", "Programme", "Level|num", "Course", "Detail", "Stage", ""]}
              rows={data.rows.map((r, i) => [
                (data.page - 1) * data.size + i + 1, <Pil key="k" kind={r.kind === "MISSING_SCORE" || r.kind === "INVALID_SCORE" || r.kind === "DUPLICATE_RESULT" ? "bad" : "warn"}>{KIND_WORD[r.kind] ?? r.kind}</Pil>,
                r.surname ? `${r.surname.toUpperCase()}, ${r.otherNames}` : "—", <span className="tnum" key="m">{r.number ?? "—"}</span>, r.programme ?? r.programmeCode ?? "—",
                r.level ?? "—", <span key="c" title={r.courseTitle ?? ""}>{r.courseCode}</span>, r.detail, stageWord(r.stage),
                r.offeringId && r.studentId ? <Btn key="v" kind="ghost" onClick={() => setOpen({ offeringId: r.offeringId!, studentId: r.studentId! })}>View</Btn> : "",
              ])} />
          ) : null}
          {data && !data.rows.length && !loading ? <Note kind="ok" title="Nothing needs a look here">No exception of this kind in the scope chosen.</Note> : null}
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
      {open ? <RecordDetail offeringId={open.offeringId} studentId={open.studentId} onClose={() => setOpen(null)} onChanged={load} /> : null}
    </>
  );
}
