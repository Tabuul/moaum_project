"use client";

/** Students due to resume (V264): every deferment in force within the bound, by its return date — upcoming, due,
 *  overdue — searched and filtered on the server by student, programme, faculty, department, session, type and the
 *  expected return; the deferred courses each will find due; the report as Excel or PDF with S/N first. */
import { useState } from "react";
import Link from "next/link";
import { useQueryNav } from "@/lib/query-nav";
import { Btn, LinkBtn, Note, PageHead, Panel, PBody } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field } from "@/components/proto/blocks";
import { brandedPrint, brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";
import { RETURN, StatePil, ReturnPil, dayOf, periodOf, returnOf } from "@/lib/deferments";
import type { ReturnsList } from "./page";

export interface ReturnFilters { status: string; q: string; fac: string; dept: string; prog: string; session: string; kind: string; returnSession: string; returnSemester: string }

export function Returns({ list, filters }: { list: ReturnsList; filters: ReturnFilters }) {
  const queryNav = useQueryNav();
  const [q, setQ] = useState(filters.q);
  const rows = list.rows;
  const faculties = [...new Map(list.options.programmes.map((p) => [p.faculty_code, p.faculty])).entries()];
  const depts = [...new Map(list.options.programmes.filter((p) => !filters.fac || p.faculty_code === filters.fac).map((p) => [p.dept_code, p.department])).entries()];
  const progs = list.options.programmes.filter((p) => (!filters.fac || p.faculty_code === filters.fac) && (!filters.dept || p.dept_code === filters.dept));
  const go = (next: Partial<ReturnFilters>) => { const f = { ...filters, ...next }; if (next.fac !== undefined) { f.dept = ""; f.prog = ""; } if (next.dept !== undefined) f.prog = ""; const qs = new URLSearchParams(); for (const [k, v] of Object.entries(f)) if (v) qs.set(k, v); queryNav(`/deferments/returns?${qs}`); };
  const HEAD = ["S/N", "Student Name", "Matric No.", "Programme", "Department", "Faculty", "Deferment No.", "Type", "Deferred Period", "Expected Return", "Return Date", "Resumption Status", "Deferred Courses Due"];
  const body = () => rows.map((d, i) => [i + 1, `${d.surname}, ${d.other_names}`, d.number, d.programme, d.department, d.faculty, d.reference, d.kind === "SESSION" ? "Session" : "Semester", periodOf(d), returnOf(d), d.return_on ? dayOf(d.return_on) : "", RETURN[d.return_status ?? ""]?.[0] ?? d.return_status ?? "", String(d.deferred_due)]);
  async function excel() { const blob = await brandedXlsx("Students Due to Resume", HEAD, body(), { sheetName: "Resumption", serial: docSerial("DEF"), sub: filters.status || "All" }); downloadBlob(blob, "students-due-to-resume.xlsx"); }
  return (
    <>
      <PageHead title="Students Due to Resume" description="Every deferment in force within your bound, by its return date: upcoming, due, or overdue. Confirm a return on the application when the student presents themselves; their deferred courses then become due on the registration form."
        actions={<>{["", "DUE", "OVERDUE", "UPCOMING"].map((s) => <LinkBtn key={s || "all"} kind={filters.status === s ? "primary" : "ghost"} href={`/deferments/returns${s ? `?status=${s}` : ""}`}>{s ? s.charAt(0) + s.slice(1).toLowerCase() : "All"}</LinkBtn>)}<Btn kind="secondary" onClick={() => void excel()} disabled={!rows.length}>Excel</Btn><Btn kind="ghost" onClick={() => brandedPrint("Students Due to Resume", filters.status || "All", HEAD, body(), docSerial("DEF"))} disabled={!rows.length}>PDF</Btn><LinkBtn href="/deferments">Deferments Desk</LinkBtn></>} />
      <div className="scope">
        {list.scope.kind !== "DEPARTMENT" && list.scope.kind !== "FACULTY" ? <div className="scope__f"><Field id="rt-fac" label="Faculty"><select id="rt-fac" className="ctl" value={filters.fac} onChange={(e) => go({ fac: e.target.value })}><option value="">All</option>{faculties.map(([c, n]) => <option key={c} value={c}>{n}</option>)}</select></Field></div> : null}
        {list.scope.kind !== "DEPARTMENT" ? <div className="scope__f"><Field id="rt-dept" label="Department"><select id="rt-dept" className="ctl" value={filters.dept} onChange={(e) => go({ dept: e.target.value })}><option value="">All</option>{depts.map(([c, n]) => <option key={c} value={c}>{n}</option>)}</select></Field></div> : null}
        <div className="scope__f"><Field id="rt-prog" label="Programme"><select id="rt-prog" className="ctl" value={filters.prog} onChange={(e) => go({ prog: e.target.value })}><option value="">All</option>{progs.map((p) => <option key={p.programme_code} value={p.programme_code}>{p.programme}</option>)}</select></Field></div>
        <div className="scope__f"><Field id="rt-session" label="Deferred session"><select id="rt-session" className="ctl" value={filters.session} onChange={(e) => go({ session: e.target.value })}><option value="">Any</option>{list.options.sessions.map((s) => <option key={s} value={s}>{s}</option>)}</select></Field></div>
        <div className="scope__f"><Field id="rt-kind" label="Type"><select id="rt-kind" className="ctl" value={filters.kind} onChange={(e) => go({ kind: e.target.value })}><option value="">Both</option><option value="SEMESTER">Semester</option><option value="SESSION">Session</option></select></Field></div>
        <div className="scope__f"><Field id="rt-rs" label="Return session"><input id="rt-rs" className="ctl tnum" placeholder="2026/2027" value={filters.returnSession} onChange={(e) => go({ returnSession: e.target.value })} /></Field></div>
        <div className="scope__f"><Field id="rt-rsem" label="Return semester"><select id="rt-rsem" className="ctl" value={filters.returnSemester} onChange={(e) => go({ returnSemester: e.target.value })}><option value="">Any</option><option value="1">First</option><option value="2">Second</option></select></Field></div>
        <div className="scope__f grow"><Field id="rt-q" label="Search" hint="Student name or ID, matriculation number, deferment number or programme">
          <form className="scope__search" onSubmit={(e) => { e.preventDefault(); go({ q: q.trim() }); }}><input id="rt-q" className="ctl" value={q} onChange={(e) => setQ(e.target.value)} /><Btn kind="primary" type="submit">Search</Btn><Btn kind="ghost" onClick={() => { setQ(""); queryNav("/deferments/returns"); }}>Reset</Btn></form>
        </Field></div>
      </div>
      <Panel title="Deferments in force" right={`${rows.length} · by return date`}>
        {rows.length ? (
          <DTable pageSize={0} cols={["S/N|num", "Student", "Matric No.", "Programme", "Deferred period", "Expected return", "Return date|mid", "Deferred courses|num", "Status|mid", "|num"]}
            rows={rows.map((d, i) => [
              <span key="sn" className="tnum sub2">{i + 1}</span>,
              <span key="s"><strong>{d.surname}, {d.other_names}</strong><div className="sub2 tnum">{d.reference} · {d.kind === "SESSION" ? "Session" : "Semester"}</div></span>,
              <span key="m" className="tnum">{d.number}</span>,
              <span key="p">{d.programme}<div className="sub2">{d.department} · {d.faculty}</div></span>,
              <span key="d" className="tnum">{periodOf(d)}</span>,
              <span key="r" className="tnum">{returnOf(d)}</span>,
              <span key="on" className="tnum">{dayOf(d.return_on)}</span>,
              <span key="dc" className="tnum">{d.deferred_due}</span>,
              <span key="st"><ReturnPil status={d.return_status} /> <StatePil state={d.state} /></span>,
              <Link key="o" className="btn btn--primary btn--sm" href={`/deferments/${d.id}`}>Confirm Resumption</Link>,
            ])} texts={rows.map((d) => `${d.surname} ${d.other_names} ${d.number} ${d.reference} ${d.programme}`)} />
        ) : <PBody><Note kind="info" title="No student is due to resume">No deferment is in force within your bound{filters.status ? ` at that stage` : ""} that matches the filters.</Note></PBody>}
      </Panel>
    </>
  );
}
