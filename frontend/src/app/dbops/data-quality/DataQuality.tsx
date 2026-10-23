"use client";

/** V640: data quality — the faults of the scope by area, each figure opening its records (names A to Z, S/N first on the exports).
 *  Database Operations identifies, reports and recommends; the change itself is the owning office's, through its own screen. */
import Link from "next/link";
import { useState } from "react";
import { usePathname, useSearchParams } from "next/navigation";
import type { Problem } from "@/lib/api";
import type { Scope } from "@/lib/scope";

import { reasonHeader } from "@/lib/reason";
import { notifyProblem } from "@/components/proto/Toast";
import { ScopeBar, type Ceiling, type ScopeStructure } from "@/components/proto/ScopeBar";
import { Btn, LinkBtn, Panel, PBody, Two } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { ProblemNotice } from "@/components/ProblemNotice";
import { brandedPrint, brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";
import { DQ_AREAS } from "@/lib/dbops";

export interface DqFigures { rows: { kind: string; label: string; area: string; n: number }[]; scope: string; session: string; semester: number; at: string }
export interface DqRows {
  kind: string; total: number; page: number; size: number; scope: string; at: string;
  rows: { student_id: string; surname: string; other_names: string; matric_no: string | null; jamb_no: string | null; status: string; level: number | null;
    entry_session: string | null; programme: string | null; department: string | null; faculty: string | null; detail: string | null }[];
}

/** where each fault is put right: the office and the screen that own the change */
const OWNER: Record<string, [string, string]> = {
  INVALID_PROGRAMME: ["Academic Office", "/structure/programmes"], MISSING_FACULTY_DEPARTMENT: ["Directorate of ICT", "/structure/programmes"],
  MISSING_ENTRY_SESSION: ["Registry", "/students"], INVALID_LEVEL: ["Registry", "/cohorts"], LEVEL_INCONSISTENT: ["Registry", "/cohorts"],
  MISSING_MATRIC: ["Registry", "/students"], DUPLICATE_MATRIC: ["Registry", "/matriculation/corrections"], DUPLICATE_JAMB: ["Registry", "/students"],
  UNCLASSIFIED: ["Academic Office", "/student-query/classification"], CONFLICTING_STATUS: ["Registry", "/cohorts?tab=lifecycle"],
  GRADUATED_STILL_ACTIVE: ["Registry", "/graduation/manage"], BEYOND_MAXIMUM_PERIOD: ["Academic Office", "/graduation/manage?gr=ALL#outside"],
  PAID_NOT_REGISTERED: ["the student and the department", "/reports/exam-readiness?cat=PAID_NOT_REGISTERED"],
  REGISTERED_NOT_PAID: ["the student and the Bursary", "/reports/exam-readiness?cat=NOT_PAID_REGISTERED"],
};

export function DataQuality({ scope, structure, sessions, ceiling, figures, kind, rows, actorName }: {
  scope: Scope; structure: ScopeStructure; sessions: string[]; ceiling: Ceiling; figures: DqFigures; kind: string; rows: DqRows | null; actorName: string | null;
}) {
  const pathname = usePathname();
  const params = useSearchParams();
  const [list, setList] = useState<DqRows | null>(rows);
  const [busy, setBusy] = useState(false);
  const [problem, setProblem] = useState<Problem | null>(null);
  const href = (k: string) => {
    const p = new URLSearchParams(params.toString());
    if (k) p.set("kind", k);
    else p.delete("kind");
    return `${pathname}?${p.toString()}`;
  };
  const label = figures.rows.find((r) => r.kind === kind)?.label ?? kind;
  const query = (page: number, size: number) => {
    const p = new URLSearchParams({ page: String(page), size: String(size), session: figures.session, semester: String(figures.semester) });
    if (scope.fac) p.set("fac", scope.fac);
    if (scope.dept) p.set("dept", scope.dept);
    if (scope.prog) p.set("prog", scope.prog);
    return `/api/bff/api/v1/dbops/data-quality/${kind}?${p.toString()}`;
  };

  async function get(page: number, size: number): Promise<DqRows | null> {
    setProblem(null);
    const r = await fetch(query(page, size), { headers: { "X-Reason": reasonHeader(`Data quality read: ${kind}`) } });
    const j = await r.json().catch(() => null);
    if (!r.ok) { const p = j ?? { status: r.status, title: r.statusText }; setProblem(p); notifyProblem(p); return null; }
    return j as DqRows;
  }

  async function exportAll(format: "XLSX" | "PDF") {
    const w = format === "PDF" ? window.open("", "_blank") : null;
    setBusy(true);
    try {
      const all = await get(1, 50000);
      if (!all) { w?.close(); return; }
      const headers = ["Student Name", "Matric No", "JAMB No", "Faculty", "Department", "Programme", "Level", "Status", "Entry session", "Finding"];
      const data = all.rows.map((r) => [`${r.surname}, ${r.other_names}`, r.matric_no ?? "", r.jamb_no ?? "", r.faculty ?? "", r.department ?? "", r.programme ?? "",
        r.level ?? "", r.status, r.entry_session ?? "", r.detail ?? ""]);
      const meta: [string, string][] = [["Finding", label], ["Scope", all.scope], ["Session", figures.session], ["Records", all.total.toLocaleString("en-GB")],
        ["Put right by", OWNER[kind]?.[0] ?? ""], ["Data as of", new Date(all.at).toLocaleString("en-GB")], ...(actorName ? [["Generated by", actorName] as [string, string]] : [])];
      const title = `Data quality — ${label}`;
      const serial = docSerial("DBO-DQ");
      if (format === "XLSX") {
        downloadBlob(await brandedXlsx(title, headers, data, { serial, meta }), `data-quality-${kind.toLowerCase()}.xlsx`);
      } else {
        brandedPrint(title, all.scope, headers, data, serial, { meta, orientation: "landscape", window: w, generatedBy: actorName });
      }
      await fetch("/api/bff/api/v1/dbops/log", { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`Data quality exported: ${kind}`) },
        body: JSON.stringify({ action: format === "PDF" ? "PRINT" : "EXPORT", source: "DATA_QUALITY", title, rows: all.total, format, definition: { kind } }) });
    } finally {
      setBusy(false);
    }
  }

  return (
    <>
      <ScopeBar scope={scope} structure={structure} sessions={sessions} ceiling={ceiling} what="findings"
        count={figures.rows.reduce((n, r) => n + Number(r.n), 0)} of={figures.rows.reduce((n, r) => n + Number(r.n), 0)} />
      {problem ? <ProblemNotice problem={problem} /> : null}
      {DQ_AREAS.map((area) => {
        const items = figures.rows.filter((r) => r.area === area);
        if (!items.length) return null;
        return (
          <Panel key={area} title={area} right={area === "Payment and registration" ? `${figures.session} · semester ${figures.semester}` : figures.scope}>
            <DTable pageSize={0} noPrint cols={["Finding", "Records|num", "Put right by", ""]}
              rows={items.map((r) => [
                <span key="l">{r.label}</span>,
                Number(r.n) ? <Link key="n" className="lnk tnum" href={href(r.kind)}>{Number(r.n).toLocaleString("en-GB")}</Link> : <span key="n" className="sub2 tnum">0</span>,
                <span key="o" className="sub2">{OWNER[r.kind]?.[0] ?? ""}</span>,
                OWNER[r.kind] ? <LinkBtn key="g" kind="ghost" href={OWNER[r.kind][1]}>Open the screen</LinkBtn> : <span key="g" />,
              ])} />
          </Panel>
        );
      })}
      {list ? (
        <Panel title={label} right={`${list.total.toLocaleString("en-GB")} record${list.total === 1 ? "" : "s"} · read ${new Date(list.at).toLocaleTimeString("en-GB")}`}>
          <PBody>
            <div className="row" style={{ gap: "var(--s-2)", alignItems: "center" }}>
              <span className="sub2">Database Operations reports and recommends; {OWNER[kind]?.[0] ?? "the owning office"} puts it right on its own screen, under its own permissions.</span>
              <span className="ml-auto row row--tight">
                <Btn kind="ghost" size="sm" disabled={busy || !list.total} onClick={() => void exportAll("XLSX")}>Excel</Btn>
                <Btn kind="ghost" size="sm" disabled={busy || !list.total} onClick={() => void exportAll("PDF")}>PDF</Btn>
                <LinkBtn kind="ghost" href={href("")}>Close</LinkBtn>
              </span>
            </div>
          </PBody>
          {list.rows.length ? (
            <DTable pageSize={0} noPrint cols={["S/N|num", "Student", "Programme", "Level|num", "Status", "Finding", "|num"]}
              rows={list.rows.map((r, i) => [
                <span key="n" className="tnum">{(list.page - 1) * list.size + i + 1}</span>,
                <Two key="s" a={`${r.surname}, ${r.other_names}`} b={r.matric_no ?? r.jamb_no ?? "—"} />,
                <Two key="p" a={r.programme ?? "—"} b={r.department ?? ""} />,
                <span key="l" className="tnum">{r.level ?? "—"}</span>, <span key="st">{r.status}</span>,
                <span key="d" className="sub2">{r.detail ?? ""}</span>,
                <LinkBtn key="v" kind="ghost" href={`/students/${r.student_id}`}>Record</LinkBtn>,
              ])} />
          ) : <PBody><div className="sub2">No record.</div></PBody>}
          <PBody>
            <div className="row" style={{ gap: "var(--s-2)", alignItems: "center" }}>
              <span className="sub2">Page {list.page} of {Math.max(1, Math.ceil(list.total / list.size))} · names A to Z</span>
              <span className="ml-auto row row--tight">
                <Btn kind="ghost" size="sm" disabled={busy || list.page <= 1} onClick={async () => { const r = await get(list.page - 1, 50); if (r) setList(r); }}>Previous</Btn>
                <Btn kind="ghost" size="sm" disabled={busy || list.page * list.size >= list.total} onClick={async () => { const r = await get(list.page + 1, 50); if (r) setList(r); }}>Next</Btn>
              </span>
            </div>
          </PBody>
        </Panel>
      ) : null}
    </>
  );
}
