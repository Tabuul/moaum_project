"use client";
/** V471: the programmes with their structure counted — courses bound, live and ended, the levels they reach — filtered by kind,
 *  faculty, department, a search, or the programmes that carry nothing; each opened on its Programme Structure. */
import Link from "next/link";
import { useQueryNav } from "@/lib/query-nav";
import { Btn, LinkBtn, Panel, PBody, Pil } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field } from "@/components/proto/blocks";
import { SearchSelect } from "@/components/proto/SearchSelect";
import { brandedPrint, brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";
import type { Directory } from "@/lib/catalogue";

export interface ProgrammeRow {
  code: string; name: string; category: string | null; pg_award: string | null; dept_code: string | null; dept_name: string | null; faculty_code: string | null;
  faculty_name: string | null; archived: boolean; courses: number; active_courses: number; inactive_courses: number; levels: number;
}
export interface ProgrammeFilters { category: string; fac: string; dept: string; q: string; empty: string }

const HEAD = ["Programme code", "Programme", "Programme type", "Award", "Faculty", "Department", "Courses", "Active courses", "Inactive courses", "Levels", "Status"];

export function Programmes({ rows, directory, filters, pgOnly }: { rows: ProgrammeRow[]; directory: Directory | null; filters: ProgrammeFilters; pgOnly: boolean }) {
  const go = useQueryNav();
  const nav = (patch: Partial<ProgrammeFilters>) => {
    const next = { ...filters, ...patch };
    const qs = new URLSearchParams();
    for (const [k, v] of Object.entries(next)) if (v) qs.set(k, v);
    go(`/catalogue/structure/programmes${qs.toString() ? `?${qs.toString()}` : ""}`);
  };
  const depts = (directory?.departments ?? []).filter((d) => !filters.fac || d.faculty_code === filters.fac);
  const type = (r: ProgrammeRow) => (r.category === "POST GRADUATE" ? "Postgraduate" : "Undergraduate");
  const body = () => rows.map((r) => [r.code, r.name, type(r), r.pg_award ?? "", r.faculty_name ?? "", r.dept_name ?? r.dept_code ?? "", r.courses, r.active_courses, r.inactive_courses, r.levels,
    r.courses ? "Has a structure" : "No course bound"]);
  const sub = [pgOnly ? "Postgraduate" : filters.category === "POST_GRADUATE" ? "Postgraduate" : filters.category === "UNDER_GRADUATE" ? "Undergraduate" : "Every programme",
    filters.empty === "true" ? "without courses" : filters.empty === "false" ? "with courses" : ""].filter(Boolean).join(" · ");
  const empty = rows.filter((r) => !r.courses).length;

  return (
    <>
      <form className="filterbar" onSubmit={(e) => { e.preventDefault(); const f = new FormData(e.currentTarget); nav({ q: String(f.get("q") ?? "") }); }}>
        <div className="row">
          <Field id="pr-q" label="Search" style={{ flex: "2 1 220px" }}><input id="pr-q" name="q" className="ctl" type="search" defaultValue={filters.q} placeholder="Programme, code or department" /></Field>
          {!pgOnly ? <Field id="pr-cat" label="Programme type" style={{ flex: "0 1 160px" }}><select id="pr-cat" className="ctl" value={filters.category} onChange={(e) => nav({ category: e.target.value })}><option value="">Any</option><option value="POST_GRADUATE">Postgraduate</option><option value="UNDER_GRADUATE">Undergraduate</option></select></Field> : null}
          <Field id="pr-fac" label="Faculty" style={{ flex: "1 1 180px" }}><SearchSelect id="pr-fac" value={filters.fac} onChange={(v) => nav({ fac: v, dept: "" })} allLabel="Any faculty" options={(directory?.faculties ?? []).map((f) => ({ value: f.code, label: f.name }))} /></Field>
          <Field id="pr-dept" label="Department" style={{ flex: "1 1 200px" }}><SearchSelect id="pr-dept" value={filters.dept} onChange={(v) => nav({ dept: v })} allLabel="Any department" options={depts.map((d) => ({ value: d.code, label: d.name }))} /></Field>
          <Field id="pr-empty" label="Structure" style={{ flex: "0 1 170px" }}><select id="pr-empty" className="ctl" value={filters.empty} onChange={(e) => nav({ empty: e.target.value })}><option value="">Any</option><option value="true">Without courses</option><option value="false">With courses</option></select></Field>
          <div className="row row--tight" style={{ alignSelf: "flex-end" }}>
            <Btn kind="primary" type="submit">Search</Btn>
            {Object.values(filters).some(Boolean) ? <Btn kind="ghost" onClick={() => go("/catalogue/structure/programmes")}>Clear</Btn> : null}
          </div>
        </div>
      </form>
      <Panel title={`${rows.length} programme${rows.length === 1 ? "" : "s"}`} right={<span className="row row--inline row--tight">
        <span className="sub2">{empty ? `${empty} without a course` : "Every programme carries a course"}</span>
        <Btn kind="secondary" size="sm" disabled={!rows.length} onClick={async () => downloadBlob(await brandedXlsx("Programme Structures", HEAD, body(), { sub }), "programme-structures.xlsx")}>Excel</Btn>
        <Btn kind="ghost" size="sm" disabled={!rows.length} onClick={() => brandedPrint("Programme Structures", sub, HEAD, body(), docSerial("PRS"))}>PDF</Btn>
      </span>}>
        {rows.length ? (
          <DTable cols={["S/N|num", "Programme", "Type|mid", "Faculty", "Department", "Courses|num", "Active|num", "Inactive|num", "Levels|num", "Status|mid", "|num"]} rows={rows.map((r, i) => [
            <span key="n" className="tnum sub2">{i + 1}</span>,
            <span key="p"><Link className="lnk" href={`/catalogue/structure?prog=${encodeURIComponent(r.code)}`}>{r.name}</Link><div className="sub2 tnum">{r.code}</div></span>,
            <span key="t"><Pil kind={r.category === "POST GRADUATE" ? "info" : "grey"}>{type(r)}</Pil>{r.pg_award ? <div className="sub2">{r.pg_award}</div> : null}</span>,
            <span key="f" className="sub2">{r.faculty_name ?? r.faculty_code ?? ""}</span>,
            <span key="d" className="sub2">{r.dept_name ?? r.dept_code ?? ""}</span>,
            <span key="c" className="tnum">{r.courses}</span>, <span key="a" className="tnum">{r.active_courses}</span>,
            <span key="i" className={`tnum${r.inactive_courses ? " ink-red" : ""}`}>{r.inactive_courses}</span>, <span key="l" className="tnum">{r.levels}</span>,
            r.courses ? <Pil key="s" kind="ok">Has a structure</Pil> : <Pil key="s" kind="bad">No course bound</Pil>,
            <span key="x" className="row row--tight row--right">
              <LinkBtn href={`/catalogue/structure?prog=${encodeURIComponent(r.code)}`}>{r.courses ? "Manage courses" : "Add courses"}</LinkBtn>
              <LinkBtn href={`/catalogue/all?prog=${encodeURIComponent(r.code)}`}>Courses</LinkBtn>
            </span>,
          ])} texts={rows.map((r) => `${r.code} ${r.name} ${r.dept_name ?? ""} ${r.faculty_name ?? ""} ${r.pg_award ?? ""}`)} />
        ) : <PBody><div className="sub2">No programme in view.</div></PBody>}
      </Panel>
    </>
  );
}
