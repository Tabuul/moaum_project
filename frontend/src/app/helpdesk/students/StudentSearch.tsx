"use client";
/** The support desk's student search (V334): the students within the agent's reach, by name, number, phone or email, filtered
 *  by faculty, department, programme, level, status and entry session — the server searches and pages; S/N first; exports
 *  only where the posting carries them. */
import { useQueryNav } from "@/lib/query-nav";
import { Btn, LinkBtn, Note, PageHead, Panel, PBody, Pil } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field } from "@/components/proto/blocks";
import { SearchSelect } from "@/components/proto/SearchSelect";
import { brandedPrint, brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";
import { statusWord } from "@/lib/cohorts";
import type { SupportList, SupportRow } from "@/lib/support";

export interface Filters { q: string; fac: string; dept: string; prog: string; level: string; status: string; session: string; size: string }
const REG: Record<string, ["ok" | "info" | "grey" | "warn" | "bad", string]> = { REGISTERED: ["ok", "Registered"], ENROLLED: ["info", "Enrolled"], NOT_REGISTERED: ["warn", "Not registered"] };
const fullName = (r: SupportRow) => `${r.surname}, ${r.other_names}`;

export function StudentSearch({ list, filters, page, generatedBy }: { list: SupportList; filters: Filters; page: number; generatedBy: string | null }) {
  const go = useQueryNav();
  const caps = new Set(list.capabilities);
  function nav(patch: Partial<Filters & { page: string }>) {
    const next: Record<string, string> = { ...filters, page: "1", ...patch };
    const qs = new URLSearchParams();
    for (const [k, v] of Object.entries(next)) if (v && !(k === "size" && v === "50") && !(k === "page" && v === "1")) qs.set(k, v);
    go(`/helpdesk/students${qs.toString() ? "?" + qs.toString() : ""}`);
  }
  const filtered = Object.entries(filters).some(([k, v]) => v && k !== "size");
  const opts = list.options ?? { faculties: [], departments: [], programmes: [], sessions: [] };
  const depts = opts.departments.filter((d) => !filters.fac || d.faculty_code === filters.fac);
  const progs = opts.programmes.filter((p) => (!filters.dept || p.dept_code === filters.dept) && (!filters.fac || depts.some((d) => d.code === p.dept_code)));
  const HEAD = ["Student", "Matriculation number", "JAMB number", "Faculty", "Department", "Programme", "Level", "Session", "Status", "Registration"];
  const exportRows = (rows: SupportRow[]) => rows.map((r) => [fullName(r), r.matric_no ?? "", r.jamb_reg_no ?? "", r.faculty ?? "", r.department ?? "", r.programme, r.current_level, r.current_session ?? "", statusWord(r.status), REG[r.registration]?.[1] ?? r.registration]);
  const meta = (): [string, string][] => [["Scope", list.scope || "—"], ["Filters", filtered ? Object.entries(filters).filter(([k, v]) => v && k !== "size").map(([k, v]) => `${k} ${v}`).join(", ") : "None"]];
  async function exportAll(kind: "xlsx" | "pdf") {
    const qs = new URLSearchParams();
    for (const [k, v] of Object.entries(filters)) if (v && k !== "size") qs.set(k, v);
    qs.set("export", "true"); qs.set("size", "2000"); qs.set("page", "1");
    const r = await fetch(`/api/bff/api/v1/helpdesk/support/students?${qs.toString()}`);
    if (!r.ok) return;
    const j = (await r.json()) as SupportList;
    if (kind === "xlsx") downloadBlob(await brandedXlsx("Students — ICT Support", HEAD, exportRows(j.rows), { sheetName: "Students", serial: docSerial("SUP"), meta: meta() }), "students-support.xlsx");
    else brandedPrint("Students — ICT Support", list.scope ? `Within ${list.scope}` : "", HEAD, exportRows(j.rows), docSerial("SUP"), { meta: meta(), generatedBy, orientation: "landscape" });
  }

  return (
    <>
      <PageHead title="Student support" description={`Find a student within your reach${list.scope ? ` — ${list.scope}` : ""}`}
        actions={<><LinkBtn href="/helpdesk">Support Desk</LinkBtn></>} />
      {!caps.has("VIEW_STUDENT") ? <Note kind="bad" title="Your posting does not carry student records">Ask the Head of the ICT Support Desk to grant it.</Note> : null}
      <form className="filterbar" onSubmit={(e) => { e.preventDefault(); const f = new FormData(e.currentTarget); nav({ q: String(f.get("q") ?? "") }); }}>
        <div className="row">
          <Field id="ss-q" label="Search" style={{ flex: "2 1 260px" }}><input id="ss-q" name="q" className="ctl" type="search" defaultValue={filters.q} placeholder="Name, matriculation, JAMB, application or admission number, student ID, phone, email" /></Field>
          <Field id="ss-fac" label="Faculty" style={{ flex: "1 1 170px" }}><SearchSelect id="ss-fac" value={filters.fac} onChange={(v) => nav({ fac: v, dept: "", prog: "" })} allLabel="Any faculty" options={opts.faculties.map((f) => ({ value: f.code, label: f.name }))} /></Field>
          <Field id="ss-dept" label="Department" style={{ flex: "1 1 170px" }}><SearchSelect id="ss-dept" value={filters.dept} onChange={(v) => nav({ dept: v, prog: "" })} allLabel="Any department" options={depts.map((d) => ({ value: d.code, label: d.name }))} /></Field>
          <Field id="ss-prog" label="Programme" style={{ flex: "1 1 200px" }}><SearchSelect id="ss-prog" value={filters.prog} onChange={(v) => nav({ prog: v })} allLabel="Any programme" options={progs.map((p) => ({ value: p.code, label: p.name }))} /></Field>
          <Field id="ss-level" label="Level" style={{ flex: "0 1 100px" }}><select id="ss-level" className="ctl" value={filters.level} onChange={(e) => nav({ level: e.target.value })}><option value="">Any</option>{[100, 200, 300, 400, 500, 600, 700, 800, 900].map((l) => <option key={l} value={String(l)}>{l}</option>)}</select></Field>
          <Field id="ss-status" label="Status" style={{ flex: "0 1 150px" }}><select id="ss-status" className="ctl" value={filters.status} onChange={(e) => nav({ status: e.target.value })}><option value="">Any</option>{["ADMITTED", "ACTIVE", "PROBATION", "DEFERRED", "SUSPENDED", "RUSTICATED", "WITHDRAWN", "VOLUNTARY_WITHDRAWAL", "EXPELLED", "TRANSFERRED_OUT", "GRADUATED", "DECEASED", "DORMANT"].map((s) => <option key={s} value={s}>{statusWord(s)}</option>)}</select></Field>
          <Field id="ss-session" label="Entry session" style={{ flex: "0 1 130px" }}><select id="ss-session" className="ctl" value={filters.session} onChange={(e) => nav({ session: e.target.value })}><option value="">Any</option>{opts.sessions.map((s) => <option key={s} value={s}>{s}</option>)}</select></Field>
          <div className="row row--tight" style={{ alignSelf: "flex-end" }}>
            <Btn kind="primary" type="submit">Search</Btn>
            {filtered ? <Btn kind="ghost" onClick={() => go("/helpdesk/students")}>Clear</Btn> : null}
          </div>
        </div>
      </form>
      <Panel title="Students" right={<span className="row row--inline row--tight">
        <span className="sub2">{list.total.toLocaleString()} within reach{filtered ? " · filtered" : ""}</span>
        {caps.has("EXPORT_STUDENTS") && list.rows.length ? <><Btn kind="ghost" size="sm" onClick={() => void exportAll("xlsx")}>Excel</Btn><Btn kind="ghost" size="sm" onClick={() => void exportAll("pdf")}>PDF</Btn></> : null}
      </span>}>
        {list.rows.length ? (
          <DTable pageSize={0} cols={["S/N|num", "Student", "Matric No.", "JAMB No.", "Faculty", "Department", "Programme", "Level|mid", "Session|mid", "Status|mid", "Registration|mid", "|num"]} rows={list.rows.map((r, i) => [
            <span key="n" className="tnum sub2">{(list.page - 1) * list.size + i + 1}</span>,
            <span key="s"><strong>{fullName(r)}</strong><div className="sub2 tnum">{r.admission_no ?? ""}</div></span>,
            <span key="m" className="tnum">{r.matric_no ?? <span className="sub2">—</span>}</span>,
            <span key="j" className="tnum">{r.jamb_reg_no ?? <span className="sub2">—</span>}</span>,
            <span key="f" className="sub2">{r.faculty ?? ""}</span>, <span key="d" className="sub2">{r.department ?? ""}</span>, <span key="p">{r.programme}</span>,
            <span key="l" className="tnum">{r.current_level}</span>, <span key="c" className="tnum">{r.current_session ?? "—"}</span>,
            <Pil key="st" kind={r.status === "ACTIVE" ? "ok" : r.status === "GRADUATED" ? "info" : "grey"}>{statusWord(r.status)}</Pil>,
            <Pil key="rg" kind={REG[r.registration]?.[0] ?? "grey"}>{REG[r.registration]?.[1] ?? r.registration}</Pil>,
            <LinkBtn key="a" kind="primary" size="sm" href={`/helpdesk/students/${r.id}`}>Open</LinkBtn>,
          ])} />
        ) : <PBody><div className="sub2">{filters.q || filtered ? "No student within your reach matches." : "Search by name, number, phone or email, or filter by faculty, department or programme."}</div></PBody>}
        <PBody><div className="row row--base">
          <span className="sub2">{list.total ? `Showing ${(list.page - 1) * list.size + 1}–${Math.min(list.page * list.size, list.total)} of ${list.total.toLocaleString()}` : ""}</span>
          <span className="grow" />
          <Btn kind="ghost" size="sm" disabled={page <= 1} onClick={() => nav({ page: String(page - 1) })}>Previous</Btn>
          <Btn kind="ghost" size="sm" disabled={list.page * list.size >= list.total} onClick={() => nav({ page: String(page + 1) })}>Next</Btn>
          <select className="ctl" value={filters.size} onChange={(e) => nav({ size: e.target.value })} aria-label="Rows a page">{["25", "50", "100", "500"].map((s) => <option key={s} value={s}>{s} a page</option>)}</select>
        </div></PBody>
      </Panel>
    </>
  );
}
