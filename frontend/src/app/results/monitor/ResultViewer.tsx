"use client";

/**
 * V700: the Director of ICT's result viewer — faculty → department → programme → level → session → semester (the shared scope bar),
 * an overview that drills down until a programme is chosen, then the result records themselves: read from the approved registrations
 * and each course's result (assessment.course_final), as the broadsheet reads them; never a copy.
 */
import { useEffect, useMemo, useState } from "react";
import { useJson } from "@/lib/use-json";
import Link from "next/link";
import { usePathname, useSearchParams } from "next/navigation";
import { ScopeBar, type Ceiling, type ScopeStructure } from "@/components/proto/ScopeBar";
import { Btn, LinkBtn, Note, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { brandedPrint, brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";
import type { Scope } from "@/lib/scope";
import type { Problem } from "@/lib/api";
import { RecordDetail } from "@/components/results/RecordDetail";
import {
  monitorQuery, OUTCOME_WORD, recordCells, RECORD_HEADERS, RESULT_STATES, STATE_TONE, STATE_WORD, stageWord, type RecordRow, type ResultState,
} from "@/lib/result-monitor";

interface Summary { students: number; results: number; withResult: number; awaiting: number; atEntry: number; verification: number; approval: number; published: number; missing: number; exceptions?: number }
interface Records { session: string; semester: number; summary: Summary; total: number; page: number; size: number; rows: RecordRow[] }
interface GroupRow {
  facultyCode: string; faculty: string | null; deptCode: string | null; department: string | null; programmeCode: string | null; programme: string | null; level: number | null;
  students: number; results: number; withResult: number; awaiting: number; atEntry: number; verification: number; approval: number; published: number; missing: number; exceptions?: number;
}
interface Overview { session: string; semester: number; by: "FACULTY" | "DEPARTMENT" | "PROGRAMME"; rows: GroupRow[]; totals: Summary & { exceptions: number | null };
  corrections: { amendmentsOpen: number; amendmentsApplied: number; requestsOpen: number; requestsResolved: number }; broadsheets: number }

const SIZE = 50;
const n = (x: number | null | undefined) => (x ?? 0).toLocaleString();

export function ResultViewer({ scope, structure, sessions, ceiling, initialState }: {
  scope: Scope; structure: ScopeStructure; sessions: string[]; ceiling: Ceiling; initialState?: string;
}) {
  const pathname = usePathname();
  const params = useSearchParams();
  const filters = useMemo(() => ({ session: scope.session, sem: scope.sem, fac: scope.fac, dept: scope.dept, prog: scope.prog, level: scope.level, course: scope.course }),
    [scope.session, scope.sem, scope.fac, scope.dept, scope.prog, scope.level, scope.course]);
  const filtersKey = monitorQuery(filters);
  // "view results" and the page hold for the filters they were chosen under; new filters start again (no effect needed)
  const [listAllFor, setListAllFor] = useState<string | null>(null);
  const listAll = listAllFor === filtersKey;
  const [state, setStateRaw] = useState<ResultState | "">(RESULT_STATES.includes(initialState as ResultState) ? (initialState as ResultState) : "");
  const [q, setQ] = useState("");
  const [typed, setTyped] = useState("");
  const [pager, setPager] = useState<{ key: string; page: number }>({ key: "", page: 1 });
  const viewKey = `${filtersKey}|${state}|${q}`;
  const page = pager.key === viewKey ? pager.page : 1;
  const setPage = (n: number) => setPager({ key: viewKey, page: n });
  const setState = (s: ResultState | "") => setStateRaw(s);
  const [tick, setTick] = useState(0);
  const [open, setOpen] = useState<{ offeringId: string; studentId: string } | null>(null);
  const [exporting, setExporting] = useState(false);
  const showRecords = !!scope.prog || listAll || !!state;

  // the search waits for the typing to stop
  useEffect(() => { const t = setTimeout(() => setQ(typed.trim()), 350); return () => clearTimeout(t); }, [typed]);

  const rec = useJson<Records>(showRecords ? `/api/bff/api/v1/results/monitor/records${monitorQuery({ ...filters, state, q, page, size: SIZE })}` : null, tick);
  const ov = useJson<Overview>(!showRecords ? `/api/bff/api/v1/results/monitor/overview${monitorQuery({ session: filters.session, sem: filters.sem, fac: filters.fac, dept: filters.dept })}` : null, tick);
  const records = showRecords ? rec.data : null;
  const overview = !showRecords ? ov.data : null;
  const loading = showRecords ? rec.loading : ov.loading;
  const failed = showRecords ? rec.failed : ov.failed;
  const load = () => setTick((x) => x + 1);

  /** a link that narrows the scope (the same page, the filters kept) */
  function narrow(patch: Record<string, string>) {
    const p = new URLSearchParams(params.toString());
    for (const [k, v] of Object.entries(patch)) p.set(k, v);
    if (overview) { p.set("session", overview.session); p.set("sem", String(overview.semester)); }
    return `${pathname}?${p.toString()}`;
  }

  async function allRows(): Promise<RecordRow[]> {
    const out: RecordRow[] = [];
    for (let pg = 1; pg <= 40; pg++) {
      const r = await fetch(`/api/bff/api/v1/results/monitor/records${monitorQuery({ ...filters, state, q, page: pg, size: 2000 })}`, { cache: "no-store" });
      const j = await r.json().catch(() => null);
      if (!r.ok) throw j ?? { status: r.status, title: "The export could not read the results" };
      out.push(...(j.rows as RecordRow[]));
      if (out.length >= j.total || !j.rows.length) break;
    }
    return out;
  }

  function context(): [string, string][] {
    const s = records ?? overview;
    const fac = structure.faculties.find((f) => f.code === scope.fac);
    const dept = fac?.departments.find((d) => d.code === scope.dept);
    const prog = dept?.programmes.find((p) => p.code === scope.prog);
    return [
      ["Faculty", fac?.name ?? "All faculties"], ["Department", dept?.name ?? "All departments"], ["Programme", prog?.name ?? "All programmes"],
      ["Level", scope.level ? `${scope.level} Level` : "All levels"], ["Session", s?.session ?? scope.session], ["Semester", String(s?.semester ?? scope.sem ?? "")],
      ...(state ? [["Result status", STATE_WORD[state]] as [string, string]] : []), ...(q ? [["Search", q] as [string, string]] : []),
    ];
  }

  async function exportAs(kind: "xlsx" | "pdf") {
    setExporting(true);
    notify("Export processing…", "ok", 2500);
    const win = kind === "pdf" ? window.open("", "_blank") : null;
    try {
      const rows = await allRows();
      const cells = rows.map(recordCells);
      const serial = docSerial("RES");
      if (kind === "xlsx") {
        downloadBlob(await brandedXlsx("Result records", RECORD_HEADERS, cells, { serial, meta: context(), sheetName: "Results" }), `Result records ${(records?.session ?? "").replace("/", "-")}.xlsx`);
      } else {
        brandedPrint("Result records", context().map(([k, v]) => `${k}: ${v}`).join(" · "), RECORD_HEADERS, cells, serial, { meta: context(), orientation: "landscape", window: win });
      }
      notify(`Export completed — ${rows.length.toLocaleString()} result${rows.length === 1 ? "" : "s"}.`);
    } catch (e) {
      win?.close();
      notifyProblem(e as Problem, "The export did not complete");
    } finally { setExporting(false); }
  }

  const sm = records?.summary;
  return (
    <>
      <ScopeBar scope={scope} structure={structure} sessions={sessions} ceiling={ceiling} what="results"
        count={showRecords ? records?.rows.length ?? 0 : overview?.rows.length ?? 0} of={showRecords ? records?.total ?? 0 : overview?.rows.length ?? 0}
        onExport={showRecords && records?.total ? () => void exportAs("xlsx") : undefined} />
      {failed ? <Note kind="bad" title="Unable to load results">{failed}</Note> : null}
      {loading && !records && !overview ? <p className="sub2">Loading results…</p> : null}

      {!showRecords && overview ? (
        <Panel title={overview.by === "FACULTY" ? "Results by faculty" : overview.by === "DEPARTMENT" ? "Results by department" : "Results by programme and level"}
          right={<span className="row row--inline">
            <span className="sub2">{overview.session} · semester {overview.semester}{loading ? " · loading…" : ""}</span>
            <Btn kind="primary" onClick={() => setListAllFor(filtersKey)}>View results</Btn>
            {scope.prog ? null : <LinkBtn kind="ghost" href={`/results/broadsheet`}>View broadsheet</LinkBtn>}
          </span>}>
          <PBody>
            <Tiles cls="grid--5" items={[
              ["Students", n(overview.totals.students), null, "with an approved registration"],
              ["Course results", n(overview.totals.results), null, "registered courses"],
              ["With a result", n(overview.totals.withResult), null, `${n(overview.totals.published)} published`],
              ["Pending verification", n(overview.totals.verification), "var(--amber)", `${n(overview.totals.approval)} pending approval`],
              ["Exceptions", overview.totals.exceptions == null ? "—" : n(overview.totals.exceptions), overview.totals.exceptions ? "var(--red)" : null,
                `${n(overview.totals.missing)} missing on submitted sheets`, `/results/monitor/exceptions${monitorQuery({ session: overview.session, sem: overview.semester, fac: scope.fac, dept: scope.dept })}`],
            ]} />
            <DTable pageSize={0}
              cols={[overview.by === "FACULTY" ? "Faculty" : overview.by === "DEPARTMENT" ? "Department" : "Programme", ...(overview.by === "PROGRAMME" ? ["Level|num"] : []),
                "Students|num", "Results|num", "With a result|num", "Not available|num", "Pending|num", "Published|num", "Missing|num", "Exceptions|num", ""]}
              rows={overview.rows.map((g) => {
                const label = overview.by === "FACULTY" ? g.faculty ?? g.facultyCode : overview.by === "DEPARTMENT" ? g.department ?? g.deptCode : g.programme ?? g.programmeCode;
                const href = overview.by === "FACULTY" ? narrow({ fac: g.facultyCode }) : overview.by === "DEPARTMENT" ? narrow({ fac: g.facultyCode, dept: g.deptCode ?? "" })
                  : narrow({ fac: g.facultyCode, dept: g.deptCode ?? "", prog: g.programmeCode ?? "", level: String(g.level ?? "") });
                return [
                  <Link key="l" href={href}>{label}</Link>, ...(overview.by === "PROGRAMME" ? [g.level] : []),
                  n(g.students), n(g.results), n(g.withResult), n(g.awaiting), n(g.atEntry + g.verification + g.approval), n(g.published),
                  g.missing ? <b key="m" style={{ color: "var(--red)" }}>{n(g.missing)}</b> : "0", g.exceptions ? <b key="e" style={{ color: "var(--red)" }}>{n(g.exceptions)}</b> : "0",
                  <Link key="o" href={href}>{overview.by === "PROGRAMME" ? "View results" : "Open"}</Link>,
                ];
              })} />
            {!overview.rows.length ? <Note kind="info" title="No approved registration in this scope">Choose another session or semester above.</Note> : null}
          </PBody>
        </Panel>
      ) : null}

      {showRecords && records ? (
        <Panel title={`Result records · ${records.session} · semester ${records.semester}`} right={<span className="row row--inline">
          <Btn kind="ghost" disabled={exporting || !records.total} busy={exporting} onClick={() => void exportAs("xlsx")}>Excel</Btn>
          <Btn kind="ghost" disabled={exporting || !records.total} busy={exporting} onClick={() => void exportAs("pdf")}>PDF</Btn>
          {scope.prog && scope.level ? <LinkBtn kind="ghost" href={`/results/broadsheet${monitorQuery({ prog: scope.prog, level: scope.level, session: records.session, sem: records.semester })}`}>View broadsheet</LinkBtn> : null}
          {!scope.prog ? <Btn kind="ghost" onClick={() => { setListAllFor(null); setState(""); }}>Back to the overview</Btn> : null}
        </span>}>
          <PBody>
            {sm ? (
              <Tiles cls="grid--5" items={[
                ["Students", n(sm.students), null, "unique students"],
                ["Course results", n(sm.results), null, `${n(sm.withResult)} with a result`],
                ["Pending verification", n(sm.verification), sm.verification ? "var(--amber)" : null, `${n(sm.atEntry)} uploaded, not submitted`],
                ["Pending approval", n(sm.approval), sm.approval ? "var(--amber)" : null, `${n(sm.published)} published`],
                ["Missing · exceptions", `${n(sm.missing)} · ${sm.exceptions == null ? "—" : n(sm.exceptions)}`, sm.missing || sm.exceptions ? "var(--red)" : null,
                  `${n(sm.awaiting)} not available yet`, `/results/monitor/exceptions${monitorQuery({ ...filters, session: records.session, sem: records.semester })}`],
              ]} />
            ) : null}
            <div className="row" style={{ gap: 6, margin: "8px 0" }}>
              <Btn kind={state === "" ? "primary" : "ghost"} onClick={() => setState("")}>All</Btn>
              {RESULT_STATES.map((s) => (
                <Btn key={s} kind={state === s ? "primary" : "ghost"} onClick={() => setState(s)}>{STATE_WORD[s]}</Btn>
              ))}
              <span className="grow" />
              <input className="ctl" style={{ maxWidth: 320 }} placeholder="Search name, matric, JAMB, course, lecturer" value={typed} onChange={(e) => setTyped(e.target.value)} aria-label="Search the results" />
            </div>
            {loading ? <p className="sub2">Loading results…</p> : null}
            <DTable pageSize={0} cols={["S/N|num", "Student", "Matric No.", "Programme", "Level|num", "Course", "Units|num", "CA|num", "Exam|num", "Total|num", "Grade|mid", "GP|num", "QP|num", "Status", "Stage", "Lecturer", ""]}
              rows={records.rows.map((r, i) => [
                (records.page - 1) * records.size + i + 1,
                `${r.surname.toUpperCase()}, ${r.otherNames}`, <span className="tnum" key="m">{r.number ?? "—"}</span>, r.programme ?? r.programmeCode, r.level,
                <span key="c" title={r.courseTitle ?? ""}>{r.courseCode}</span>, r.units, r.ca ?? "—", r.exam ?? "—", <b key="t" className="tnum">{r.total ?? "—"}</b>,
                r.grade ?? (r.outcome && r.outcome !== "GRADED" ? OUTCOME_WORD[r.outcome] ?? r.outcome : "—"), r.points ?? "—", r.qualityPoints ?? "—",
                <span key="s"><Pil kind={STATE_TONE[r.state] ?? "grey"}>{STATE_WORD[r.state] ?? r.state}</Pil>{r.openRequest ? <> <Pil kind="info" title="A correction request is open">{r.openRequest.split(" ")[0]}</Pil></> : null}{r.openAmendment ? <> <Pil kind="info" title="An amendment is open">{r.openAmendment.split(" ")[0]}</Pil></> : null}</span>,
                stageWord(r.stage), r.lecturer ?? "—",
                <Btn key="v" kind="ghost" onClick={() => setOpen({ offeringId: r.offeringId, studentId: r.studentId })}>View</Btn>,
              ])} />
            {!records.rows.length && !loading ? <Note kind="info" title="No results match">Change the filters or the search above.</Note> : null}
            <div className="row" style={{ marginTop: 8 }}>
              <span className="sub2">{records.total ? `${((records.page - 1) * records.size + 1).toLocaleString()}–${Math.min(records.page * records.size, records.total).toLocaleString()} of ${records.total.toLocaleString()}` : ""}</span>
              <span className="grow" />
              <Btn kind="ghost" disabled={records.page <= 1 || loading} onClick={() => setPage(records.page - 1)}>Previous</Btn>
              <Btn kind="ghost" disabled={records.page * records.size >= records.total || loading} onClick={() => setPage(records.page + 1)}>Next</Btn>
            </div>
          </PBody>
        </Panel>
      ) : null}

      {open ? <RecordDetail offeringId={open.offeringId} studentId={open.studentId} onClose={() => setOpen(null)} onChanged={load} /> : null}
    </>
  );
}
