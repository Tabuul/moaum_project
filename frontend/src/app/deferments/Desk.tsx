"use client";

/** The deferments desk (V259): the figures for the office's bound, the requests waiting at this desk first, every
 *  request with its filters and search, the students due to return, and the report as Excel or PDF with S/N
 *  first and names A–Z. A Head sees their department, a Dean their faculty, the Registry everyone. */
import { useState } from "react";
import Link from "next/link";
import { useQueryNav } from "@/lib/query-nav";
import { Btn, LinkBtn, Note, PageHead, Panel, PBody, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field } from "@/components/proto/blocks";
import { brandedPrint, brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";
import { SEM, STATE, StatePil, ReturnPil, dayOf, returnOf, type Deferment } from "@/lib/deferments";
import type { DeskFilters, DeskList } from "./page";

export interface DefermentDashboard {
  scope: { kind: string; office: string }; session: string | null;
  totals: { total: number; pending: number; under_review: number; correction: number; approved: number; rejected: number; active: number; returning: number; overdue: number; extensions: number };
  byFaculty: Row[]; byDepartment: Row[]; byProgramme: Row[]; byKind: Row[]; bySession: Row[]; byReason: Row[];
}
interface Row { faculty?: string; department?: string; programme?: string; kind?: string; session?: string; reason?: string; total: number; pending: number; approved: number; active: number; rejected: number }

export function Desk({ list, dash, filters }: { list: DeskList; dash: DefermentDashboard | null; filters: DeskFilters }) {
  const queryNav = useQueryNav();
  const [q, setQ] = useState(filters.q);
  const t = dash?.totals;
  const rows = list.rows;
  const mine = rows.filter((r) => r.state === list.scope.stage);
  const faculties = [...new Map(list.options.programmes.map((p) => [p.faculty_code, p.faculty])).entries()];
  const depts = [...new Map(list.options.programmes.filter((p) => !filters.fac || p.faculty_code === filters.fac).map((p) => [p.dept_code, p.department])).entries()];
  const progs = list.options.programmes.filter((p) => (!filters.fac || p.faculty_code === filters.fac) && (!filters.dept || p.dept_code === filters.dept));
  const go = (next: Partial<DeskFilters>) => { const f = { ...filters, ...next }; if (next.fac !== undefined) { f.dept = ""; f.prog = ""; } if (next.dept !== undefined) f.prog = ""; const qs = new URLSearchParams(); for (const [k, v] of Object.entries(f)) if (v) qs.set(k, v); queryNav(`/deferments?${qs}`); };
  const scope = [filters.session, filters.semester ? SEM(Number(filters.semester)) : null, filters.state ? STATE[filters.state]?.[0] ?? filters.state : null, filters.kind, filters.q ? `search “${filters.q}”` : null].filter(Boolean).join(" · ") || "All requests";

  const HEAD = ["S/N", "Deferment Number", "Student ID", "Student Name", "Faculty", "Department", "Programme", "Type", "Session", "Semester", "Status", "Request Date", "Approval Date", "Expected Return"];
  const body = () => rows.map((r, i) => [i + 1, r.reference, r.number, `${r.surname}, ${r.other_names}`, r.faculty, r.department, r.programme, r.kind === "SESSION" ? "Session" : "Semester", r.session, r.kind === "SESSION" ? "All" : SEM(r.semester), STATE[r.state]?.[0] ?? r.state, r.submitted_at ? dayOf(r.submitted_at) : "", r.decided_at ? dayOf(r.decided_at) : "", returnOf(r)]);
  async function excel() { const blob = await brandedXlsx("Deferment Requests", HEAD, body(), { sheetName: "Deferments", serial: docSerial("DEF"), sub: scope }); downloadBlob(blob, `deferments-${(filters.session || "all").replace("/", "-")}.xlsx`); }
  const pdf = () => brandedPrint("Deferment Requests", scope, HEAD, body(), docSerial("DEF"));

  const table = (items: Deferment[]) => (
    <DTable pageSize={0} cols={["S/N|num", "Reference", "Student", "Programme", "Type|mid", "Period", "Status|mid", "Requested|mid", "Return", "|num"]}
      rows={items.map((r, i) => [
        <span key="sn" className="tnum sub2">{i + 1}</span>,
        <Link key="r" className="lnk tnum b600" href={`/deferments/${r.id}`}>{r.reference}</Link>,
        <span key="s"><strong>{r.surname}, {r.other_names}</strong><div className="sub2 tnum">{r.number} · {r.level} Level</div></span>,
        <span key="p">{r.programme}<div className="sub2">{r.department} · {r.faculty}</div></span>,
        <span key="k">{r.kind === "SESSION" ? "Session" : "Semester"}</span>,
        <span key="pe" className="tnum">{r.session}{r.kind === "SESSION" ? "" : ` · ${SEM(r.semester)}`}</span>,
        <span key="st"><StatePil state={r.state} /> {r.return_status && ["ACTIVE", "APPROVED"].includes(r.state) ? <ReturnPil status={r.return_status} /> : null}</span>,
        <span key="d" className="tnum sub2">{dayOf(r.submitted_at ?? r.created_at)}</span>,
        <span key="rt" className="sub2">{returnOf(r)}</span>,
        <LinkBtn key="o" href={`/deferments/${r.id}`} size="sm" kind={r.state === list.scope.stage ? "primary" : "ghost"}>{r.state === list.scope.stage ? "Review" : "Open"}</LinkBtn>,
      ])} texts={items.map((r) => `${r.reference} ${r.surname} ${r.other_names} ${r.number} ${r.programme} ${r.department} ${STATE[r.state]?.[0] ?? ""}`)} />
  );

  return (
    <>
      <PageHead title="Deferments" description={`${dash?.scope.kind === "DEPARTMENT" ? "Your department's" : dash?.scope.kind === "FACULTY" ? "Your faculty's" : dash?.scope.kind === "PG_SCHOOL" ? "The Postgraduate School's" : dash?.scope.kind === "COLLEGE" ? "The College's" : "The University's"} deferment requests: what waits at this desk, every request, and the students due to return.`}
        actions={<><LinkBtn kind="primary" href="/deferments/returns">Students Due to Return</LinkBtn><Btn kind="secondary" onClick={() => void excel()} disabled={!rows.length}>Download Excel</Btn><Btn kind="ghost" onClick={pdf} disabled={!rows.length}>Download PDF</Btn></>} />

      {t ? (
        <Tiles items={[
          ["Total requests", String(t.total), null, dash?.session ?? "Every session"],
          ["Pending", String(t.pending), t.pending ? "var(--amber-ink)" : null, "Submitted, awaiting the department"],
          ["Under review", String(t.under_review), t.under_review ? "var(--chrome)" : null, "With the faculty or the Registry"],
          ["Approved", String(t.approved), t.approved ? "var(--green-ink)" : null, "Approved, active or completed"],
          ["Rejected", String(t.rejected), null, "With the reason on the record"],
          ["Active deferments", String(t.active), t.active ? "var(--green-ink)" : null, "Periods in force now"],
          ["Returning", String(t.returning), t.returning ? "var(--amber-ink)" : null, "Due to return within the reminder window"],
          ["Overdue returns", String(t.overdue), t.overdue ? "var(--red-ink)" : null, "Past the return date, not confirmed"],
        ]} />
      ) : null}

      {mine.length ? (
        <Panel title="Waiting at this desk" right={`${mine.length} to decide`}>{table(mine)}</Panel>
      ) : <Note kind="ok" title="Nothing waits at this desk">Requests arrive here when they reach this desk&rsquo;s stage; every request within your bound is listed below.</Note>}

      <div className="scope">
        <div className="scope__f"><Field id="dk-session" label="Session"><select id="dk-session" className="ctl" value={filters.session} onChange={(e) => go({ session: e.target.value })}><option value="">Every session</option>{list.options.sessions.map((s) => <option key={s} value={s}>{s}</option>)}</select></Field></div>
        <div className="scope__f"><Field id="dk-sem" label="Semester"><select id="dk-sem" className="ctl" value={filters.semester} onChange={(e) => go({ semester: e.target.value })}><option value="">Any</option><option value="1">First</option><option value="2">Second</option></select></Field></div>
        <div className="scope__f"><Field id="dk-kind" label="Type"><select id="dk-kind" className="ctl" value={filters.kind} onChange={(e) => go({ kind: e.target.value })}><option value="">Both</option><option value="SEMESTER">Semester</option><option value="SESSION">Session</option></select></Field></div>
        <div className="scope__f"><Field id="dk-state" label="Status"><select id="dk-state" className="ctl" value={filters.state} onChange={(e) => go({ state: e.target.value })}><option value="">Every status</option><option value="PENDING">In review</option>{list.options.states.map((s) => <option key={s} value={s}>{STATE[s]?.[0] ?? s}</option>)}</select></Field></div>
        {list.scope.kind === "UNIVERSITY" || list.scope.kind === "PG_SCHOOL" || list.scope.kind === "COLLEGE" ? <div className="scope__f"><Field id="dk-fac" label="Faculty"><select id="dk-fac" className="ctl" value={filters.fac} onChange={(e) => go({ fac: e.target.value })}><option value="">All</option>{faculties.map(([c, n]) => <option key={c} value={c}>{n}</option>)}</select></Field></div> : null}
        {list.scope.kind !== "DEPARTMENT" ? <div className="scope__f"><Field id="dk-dept" label="Department"><select id="dk-dept" className="ctl" value={filters.dept} onChange={(e) => go({ dept: e.target.value })}><option value="">All</option>{depts.map(([c, n]) => <option key={c} value={c}>{n}</option>)}</select></Field></div> : null}
        <div className="scope__f"><Field id="dk-prog" label="Programme"><select id="dk-prog" className="ctl" value={filters.prog} onChange={(e) => go({ prog: e.target.value })}><option value="">All</option>{progs.map((p) => <option key={p.programme_code} value={p.programme_code}>{p.programme}</option>)}</select></Field></div>
        <div className="scope__f grow"><Field id="dk-q" label="Search" hint="Student ID, name, deferment number, programme or department">
          <form className="scope__search" onSubmit={(e) => { e.preventDefault(); go({ q: q.trim() }); }}><input id="dk-q" className="ctl" value={q} onChange={(e) => setQ(e.target.value)} /><Btn kind="primary" type="submit">Search</Btn>{filters.q ? <Btn kind="ghost" onClick={() => { setQ(""); go({ q: "" }); }}>Clear</Btn> : null}</form>
        </Field></div>
      </div>

      <Panel title="Deferment requests" right={`${rows.length} · names A–Z`}>
        {rows.length ? table(rows) : <PBody><Note kind="info" title="No deferment requests found">No requests match the selected session, status and filters within your bound.</Note></PBody>}
      </Panel>

      {dash && (dash.byProgramme.length || dash.byReason.length) ? (
        <div className="grid grid--2">
          <Panel title="By programme"><DTable pageSize={0} cols={["Programme", "Total|num", "In review|num", "Approved|num", "Active|num", "Rejected|num"]} rows={dash.byProgramme.map((r) => [<span key="p">{r.programme}</span>, <span key="t" className="tnum">{r.total}</span>, <span key="pe" className="tnum">{r.pending}</span>, <span key="a" className="tnum">{r.approved}</span>, <span key="ac" className="tnum">{r.active}</span>, <span key="rj" className="tnum">{r.rejected}</span>])} /></Panel>
          <Panel title="By reason"><DTable pageSize={0} cols={["Reason", "Total|num", "In review|num", "Approved|num", "Active|num", "Rejected|num"]} rows={dash.byReason.map((r) => [<span key="p">{r.reason}</span>, <span key="t" className="tnum">{r.total}</span>, <span key="pe" className="tnum">{r.pending}</span>, <span key="a" className="tnum">{r.approved}</span>, <span key="ac" className="tnum">{r.active}</span>, <span key="rj" className="tnum">{r.rejected}</span>])} /></Panel>
        </div>
      ) : null}
      {dash && dash.byFaculty.length > 1 ? (
        <Panel title="By faculty"><DTable pageSize={0} cols={["Faculty", "Total|num", "In review|num", "Approved|num", "Active|num", "Rejected|num"]} rows={dash.byFaculty.map((r) => [<span key="p">{r.faculty}</span>, <span key="t" className="tnum">{r.total}</span>, <span key="pe" className="tnum">{r.pending}</span>, <span key="a" className="tnum">{r.approved}</span>, <span key="ac" className="tnum">{r.active}</span>, <span key="rj" className="tnum">{r.rejected}</span>])} /></Panel>
      ) : null}
    </>
  );
}
