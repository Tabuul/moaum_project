"use client";
/** All courses within the office's scope (V332): one row a course, the programmes that offer it beside it, searched,
 *  filtered, sorted and paged by the server; S/N first; exports to the University's standard. */
import Link from "next/link";
import { useQueryNav } from "@/lib/query-nav";
import { Btn, LinkBtn, PageHead, Panel, PBody, Pil } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field } from "@/components/proto/blocks";
import { SearchSelect } from "@/components/proto/SearchSelect";
import { brandedPrint, brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";
import { KINDS, LEVELS, STATE, semName, type CourseList, type Directory } from "@/lib/catalogue";

export interface Filters { q: string; fac: string; dept: string; prog: string; level: string; semester: string; kind: string; state: string; session: string; sort: string; dir: string; size: string }

export function AllCourses({ list, directory, sessions, filters, page, generatedBy }: { list: CourseList; directory: Directory | null; sessions: string[]; filters: Filters; page: number; generatedBy: string | null }) {
  const go = useQueryNav();
  function nav(patch: Partial<Filters & { page: string }>) {
    const next: Record<string, string> = { ...filters, page: "1", ...patch };
    const qs = new URLSearchParams();
    for (const [k, v] of Object.entries(next)) if (v && !(k === "sort" && v === "code") && !(k === "dir" && v === "asc") && !(k === "size" && v === "50") && !(k === "page" && v === "1")) qs.set(k, v);
    go(`/catalogue/all${qs.toString() ? "?" + qs.toString() : ""}`);
  }
  const filtered = Object.entries(filters).some(([k, v]) => v && !["sort", "dir", "size"].includes(k));
  const depts = (directory?.departments ?? []).filter((d) => !filters.fac || d.faculty_code === filters.fac);
  const progs = (directory?.programmes ?? []).filter((p) => (!filters.dept || p.dept_code === filters.dept) && (!filters.fac || p.faculty_code === filters.fac));
  const scoped = list.scope.dept || list.scope.fac;
  const sortBy = (key: string) => nav({ sort: key, dir: filters.sort === key && filters.dir === "asc" ? "desc" : "asc" });

  const HEAD = ["S/N", "Course code", "Course title", "Units", "Level", "Semester", "Course type", "Faculty", "Owner department", "Owner programme", "Programmes offering", "Last session offered", "Status"];
  const exportRows = () => list.rows.map((r, i) => [i + 1, r.code, r.title, r.units, r.level, semName(r.semester), r.kind, r.faculty_name ?? "", r.dept_name ?? r.dept_code ?? "", r.owner_programme_name ?? "", r.programmes.map((p) => `${p.name} (${p.level})`).join("; "), r.last_session ?? "", STATE[r.state]?.[1] ?? r.state]);
  /** V338: one row per programme offering — the course, its owner, and where it is offered and how */
  const OFFER_HEAD = ["S/N", "Course Code", "Course Title", "Units", "Course Owner Faculty", "Course Owner Department", "Course Owner Programme", "Offering Faculty", "Offering Department", "Offering Programme", "Offering Type", "Level", "Status"];
  const offerRows = () => list.rows.flatMap((r) => r.programmes.map((p) => [r.code, r.title, r.units, r.faculty_name ?? "", r.dept_name ?? r.dept_code ?? "", r.owner_programme_name ?? "",
    p.faculty ?? "", p.deptName ?? p.dept ?? "", p.name, (p.basis ?? "").toUpperCase(), p.level, STATE[r.state]?.[1] ?? r.state])).map((row, i) => [i + 1, ...row]);
  const meta = (): [string, string][] => [["Scope", scoped ? (list.scope.dept ? `Department ${list.scope.dept}` : `Faculty ${list.scope.fac}`) : "The University"], ["Filters", filtered ? Object.entries(filters).filter(([k, v]) => v && !["sort", "dir", "size"].includes(k)).map(([k, v]) => `${k} ${v}`).join(", ") : "None"]];

  return (
    <>
      <PageHead title="All courses" description={`Every course ${scoped ? "your department owns or carries" : "on the catalogue"}, with the programmes that offer it. One course is one record, however many programmes offer it.`}
        actions={<><LinkBtn href="/catalogue">Department courses</LinkBtn><LinkBtn href="/catalogue/structure">Programme structure</LinkBtn></>} />
      <form className="filterbar" onSubmit={(e) => { e.preventDefault(); const f = new FormData(e.currentTarget); nav({ q: String(f.get("q") ?? "") }); }}>
        <div className="row">
          <Field id="ac-q" label="Search" style={{ flex: "2 1 220px" }}><input id="ac-q" name="q" className="ctl" type="search" defaultValue={filters.q} placeholder="Code or title" /></Field>
          {!list.scope.dept ? <>
            {!list.scope.fac ? <Field id="ac-fac" label="Faculty" style={{ flex: "1 1 170px" }}><SearchSelect id="ac-fac" value={filters.fac} onChange={(v) => nav({ fac: v, dept: "", prog: "" })} allLabel="Any faculty" options={(directory?.faculties ?? []).map((f) => ({ value: f.code, label: f.name }))} /></Field> : null}
            <Field id="ac-dept" label="Department (owns or offers)" style={{ flex: "1 1 190px" }}><SearchSelect id="ac-dept" value={filters.dept} onChange={(v) => nav({ dept: v, prog: "" })} allLabel="Any department" options={depts.map((d) => ({ value: d.code, label: d.name }))} /></Field>
          </> : null}
          <Field id="ac-prog" label="Programme offering" style={{ flex: "1 1 220px" }}><SearchSelect id="ac-prog" value={filters.prog} onChange={(v) => nav({ prog: v })} allLabel="Any programme" options={progs.map((p) => ({ value: p.code, label: p.name }))} /></Field>
          <Field id="ac-level" label="Level" style={{ flex: "0 1 100px" }}><select id="ac-level" className="ctl" value={filters.level} onChange={(e) => nav({ level: e.target.value })}><option value="">Any</option>{LEVELS.map((l) => <option key={l} value={String(l)}>{l}</option>)}</select></Field>
          <Field id="ac-sem" label="Semester" style={{ flex: "0 1 110px" }}><select id="ac-sem" className="ctl" value={filters.semester} onChange={(e) => nav({ semester: e.target.value })}><option value="">Any</option><option value="1">First</option><option value="2">Second</option><option value="3">Third</option></select></Field>
          <Field id="ac-kind" label="Course type" style={{ flex: "0 1 120px" }}><select id="ac-kind" className="ctl" value={filters.kind} onChange={(e) => nav({ kind: e.target.value })}><option value="">Any</option>{KINDS.map((k) => <option key={k} value={k}>{k}</option>)}</select></Field>
          <Field id="ac-state" label="Status" style={{ flex: "0 1 140px" }}><select id="ac-state" className="ctl" value={filters.state} onChange={(e) => nav({ state: e.target.value })}><option value="">Any</option>{Object.entries(STATE).map(([k, v]) => <option key={k} value={k}>{v[1]}</option>)}</select></Field>
          <Field id="ac-session" label="Offered in session" style={{ flex: "0 1 140px" }}><select id="ac-session" className="ctl" value={filters.session} onChange={(e) => nav({ session: e.target.value })}><option value="">Any</option>{sessions.map((s) => <option key={s} value={s}>{s}</option>)}</select></Field>
          <div className="row row--tight" style={{ alignSelf: "flex-end" }}>
            <Btn kind="primary" type="submit">Search</Btn>
            {filtered ? <Btn kind="ghost" onClick={() => go("/catalogue/all")}>Clear</Btn> : null}
          </div>
        </div>
      </form>
      <Panel title="Courses" right={<span className="row row--inline row--tight">
        <span className="sub2">{list.total.toLocaleString()} course{list.total === 1 ? "" : "s"} · sorted by</span>
        {[["code", "Code"], ["title", "Title"], ["level", "Level"], ["dept", "Owner"], ["programmes", "Programmes"], ["state", "Status"]].map(([k, l]) => (
          <Btn key={k} kind={filters.sort === k ? "primary" : "ghost"} size="sm" onClick={() => sortBy(k)}>{l}{filters.sort === k ? (filters.dir === "asc" ? " ↑" : " ↓") : ""}</Btn>
        ))}
        {list.rows.length ? <>
          <Btn kind="ghost" size="sm" onClick={async () => downloadBlob(await brandedXlsx("All Courses", HEAD, exportRows(), { sheetName: "Courses", serial: docSerial("CRS"), meta: meta() }), "courses.xlsx")}>Excel</Btn>
          <Btn kind="ghost" size="sm" onClick={async () => downloadBlob(await brandedXlsx("Course Offerings", OFFER_HEAD, offerRows(), { sheetName: "Offerings", serial: docSerial("CRSOFF"), meta: meta() }), "course-offerings.xlsx")}>Offerings (Excel)</Btn>
          <Btn kind="ghost" size="sm" onClick={() => brandedPrint("All Courses", scoped ? `Within ${list.scope.dept || list.scope.fac}` : "The University's catalogue", HEAD, exportRows(), docSerial("CRS"), { meta: meta(), generatedBy, orientation: "landscape" })}>PDF</Btn>
        </> : null}
      </span>}>
        {list.rows.length ? (
          <DTable pageSize={0} cols={["S/N|num", "Code|mid", "Title", "Units|mid", "Level|mid", "Semester|mid", "Type", "Owner", "Programmes offering", "Last session|mid", "Status|mid", "|num"]} rows={list.rows.map((r, i) => [
            <span key="n" className="tnum sub2">{(list.page - 1) * list.size + i + 1}</span>,
            <b key="c" className="tnum">{r.code}</b>,
            <span key="t">{r.title}{r.pending ? <div className="sub2 ink-amber">{r.pending} proposal{r.pending === 1 ? "" : "s"} awaiting a department</div> : null}</span>,
            <span key="u" className="tnum">{r.units}</span>, <span key="l" className="tnum">{r.level}</span>, <span key="s" className="tnum">{semName(r.semester)}</span>,
            <span key="k" className="sub2">{r.kind}{r.general_office ? ` · ${r.general_office}` : ""}</span>,
            <span key="o">{r.dept_name ?? r.dept_code ?? "—"}<div className="sub2">{r.owner_programme_name ? `${r.owner_programme_name} · ` : ""}{r.faculty_name ?? ""}</div></span>,
            <span key="p">{r.programmes.length ? <>{r.programmes.slice(0, 3).map((p) => <div key={`${p.code}-${p.level}`} className="sub2"><Link href={`/catalogue/structure?prog=${encodeURIComponent(p.code)}`} className="lnk">{p.name}</Link> · {p.level}{p.basis !== "Core" ? ` · ${p.basis}` : ""}</div>)}{r.programmes.length > 3 ? <Link href={`/catalogue/course?code=${encodeURIComponent(r.code)}`} className="lnk sub2">+{r.programmes.length - 3} more</Link> : null}</> : <span className="sub2 ink-red">None</span>}</span>,
            <span key="ls" className="tnum sub2">{r.last_session ?? "—"}</span>,
            <Pil key="st" kind={STATE[r.state]?.[0] ?? "grey"}>{STATE[r.state]?.[1] ?? r.state}</Pil>,
            <LinkBtn key="a" size="sm" href={`/catalogue/course?code=${encodeURIComponent(r.code)}`}>Details</LinkBtn>,
          ])} />
        ) : <PBody><div className="sub2">No course matches these filters.</div></PBody>}
        <PBody><div className="row row--base">
          <span className="sub2">{list.total ? `Showing ${(list.page - 1) * list.size + 1}–${Math.min(list.page * list.size, list.total)} of ${list.total.toLocaleString()}` : ""}</span>
          <span className="grow" />
          <Btn kind="ghost" size="sm" disabled={page <= 1} onClick={() => nav({ page: String(page - 1) })}>Previous</Btn>
          <Btn kind="ghost" size="sm" disabled={list.page * list.size >= list.total} onClick={() => nav({ page: String(page + 1) })}>Next</Btn>
          <select className="ctl" value={filters.size} onChange={(e) => nav({ size: e.target.value })} aria-label="Rows a page">{["25", "50", "100", "500", "2000"].map((s) => <option key={s} value={s}>{s} a page</option>)}</select>
        </div></PBody>
      </Panel>
    </>
  );
}
