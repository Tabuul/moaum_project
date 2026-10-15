"use client";
/** V471: the programme structure's checks (catalogue.structure_issues) — every problem with its programme and course, each
 *  opened where it is put right: the programme's structure, or the course. Filtered by kind and by the kind of programme;
 *  printed (PDF) and downloaded (Excel) as listed, S/N first. */
import Link from "next/link";
import type { Problem } from "@/lib/api";
import { useQueryNav } from "@/lib/query-nav";
import { Btn, Note, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { ProblemNotice } from "@/components/ProblemNotice";
import { brandedPrint, brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";

export interface IssueRow {
  kind: string; programme_code: string | null; programme: string | null; course_code: string | null; course: string | null; level: number | null;
  dept_code: string | null; dept_name: string | null; faculty_code: string | null; faculty_name: string | null; detail: string;
}
export interface IssuesData { category: string; total: number; byKind: Record<string, number>; rows: IssueRow[] }

/** each check: what it is called, how serious, and what puts it right */
export const ISSUE_KIND: Record<string, { label: string; tone: "bad" | "warn" | "grey"; fix: string }> = {
  PROGRAMME_WITHOUT_COURSES: { label: "Programme without courses", tone: "bad", fix: "Bind its courses on its Programme Structure" },
  REGISTERED_OFF_STRUCTURE: { label: "Registered off the structure", tone: "bad", fix: "Bind the course into the programme at that level, or amend the registrations" },
  LEVEL_OFF_PROGRAMME: { label: "Bound off the programme's levels", tone: "bad", fix: "Remove the binding and bind the course at one of the programme's levels" },
  ENDED_COURSE_BOUND: { label: "Ended course still bound", tone: "warn", fix: "Restore the course, or remove it from the programme" },
  BOUND_AT_TWO_LEVELS: { label: "Bound at two levels", tone: "warn", fix: "Keep the level the programme takes it at; remove the other" },
  PREREQUISITE_CYCLE: { label: "Prerequisite cycle", tone: "bad", fix: "Remove one prerequisite of the loop on the course" },
  PG_CLASS_UNBOUND: { label: "PG class no programme takes", tone: "warn", fix: "Bind the course into the postgraduate programmes that take it" },
  COURSE_WITHOUT_DEPARTMENT: { label: "Course without a department", tone: "warn", fix: "Give the course its owning department (Change owner)" },
  PROGRAMME_DEPARTMENT: { label: "Programme's department out of step", tone: "grey", fix: "The Directorate of ICT corrects the programme's department or faculty" },
};

const CATEGORIES: [string, string][] = [["", "Every programme"], ["POST_GRADUATE", "Postgraduate"], ["UNDER_GRADUATE", "Undergraduate"]];
const HEAD = ["Check", "Programme", "Programme code", "Course", "Course title", "Level", "Department", "Faculty", "What is wrong", "Put right by"];

export function Checks({ data, problem, kind, category, pgOnly }: { data: IssuesData | null; problem: Problem | null; kind: string; category: string; pgOnly: boolean }) {
  const go = useQueryNav();
  const at = (k: string, c: string) => {
    const qs = new URLSearchParams();
    if (k) qs.set("kind", k);
    if (c) qs.set("category", c);
    const s = qs.toString();
    return `/catalogue/structure/checks${s ? `?${s}` : ""}`;
  };
  const rows = data?.rows ?? [];
  const sub = `${kind ? ISSUE_KIND[kind]?.label ?? kind : "Every check"} · ${pgOnly ? "Postgraduate programmes" : CATEGORIES.find((c) => c[0] === category)?.[1] ?? "Every programme"}`;
  const body = () => rows.map((r) => [ISSUE_KIND[r.kind]?.label ?? r.kind, r.programme ?? "", r.programme_code ?? "", r.course_code ?? "", r.course ?? "", r.level == null ? "" : String(r.level),
    r.dept_name ?? r.dept_code ?? "", r.faculty_name ?? r.faculty_code ?? "", r.detail, ISSUE_KIND[r.kind]?.fix ?? ""]);

  return (
    <>
      <div className="scope">
        {!pgOnly ? (
          <div className="scope__f"><label htmlFor="ck-cat">Programmes</label>
            <select id="ck-cat" className="ws__select" value={category} onChange={(e) => go(at(kind, e.target.value))}>
              {CATEGORIES.map(([v, l]) => <option key={v} value={v}>{l}</option>)}
            </select></div>
        ) : null}
        <div className="scope__f"><label htmlFor="ck-kind">Check</label>
          <select id="ck-kind" className="ws__select" value={kind} onChange={(e) => go(at(e.target.value, category))}>
            <option value="">Every check</option>
            {Object.entries(ISSUE_KIND).map(([k, v]) => <option key={k} value={k}>{v.label}</option>)}
          </select></div>
      </div>
      {problem ? <ProblemNotice problem={problem} /> : null}
      {data ? (
        <>
          <Tiles cls="grid--4" items={Object.entries(ISSUE_KIND).filter(([k]) => (data.byKind[k] ?? 0) > 0 || k === kind).slice(0, 8).map(([k, v]) => [
            v.label, String(data.byKind[k] ?? 0), (data.byKind[k] ?? 0) ? (v.tone === "bad" ? "var(--red-ink)" : v.tone === "warn" ? "var(--amber-ink)" : null) : null, v.fix, at(k, category),
          ])} />
          {!data.total ? <Note kind="ok" title="Nothing to put right">{kind ? "No problem of this kind is found." : "Every structure in view passes the checks."}</Note> : null}
          <Panel title={`${data.total} problem${data.total === 1 ? "" : "s"}`} right={<span className="row row--inline row--tight">
            <span className="sub2">{sub}</span>
            <Btn kind="secondary" size="sm" disabled={!rows.length} onClick={async () => downloadBlob(await brandedXlsx("Programme Structure Checks", HEAD, body(), { sub }), "programme-structure-checks.xlsx")}>Excel</Btn>
            <Btn kind="ghost" size="sm" disabled={!rows.length} onClick={() => brandedPrint("Programme Structure Checks", sub, HEAD, body(), docSerial("PSC"))}>PDF</Btn>
          </span>}>
            {rows.length ? (
              <DTable cols={["S/N|num", "Check", "Programme", "Course", "Level|mid", "Department", "What is wrong", "|num"]} rows={rows.map((r, i) => [
                <span key="n" className="tnum sub2">{i + 1}</span>,
                <Pil key="k" kind={ISSUE_KIND[r.kind]?.tone ?? "grey"}>{ISSUE_KIND[r.kind]?.label ?? r.kind}</Pil>,
                r.programme_code ? <span key="p">{r.programme}<div className="sub2 tnum">{r.programme_code}</div></span> : <span key="p" className="sub2">—</span>,
                r.course_code ? <span key="c"><Link className="lnk tnum" href={`/catalogue/course?code=${encodeURIComponent(r.course_code)}`}>{r.course_code}</Link><div className="sub2">{r.course}</div></span> : <span key="c" className="sub2">—</span>,
                <span key="l" className="tnum">{r.level ?? ""}</span>,
                <span key="d" className="sub2">{r.dept_name ?? r.dept_code ?? ""}{r.faculty_name ? <div>{r.faculty_name}</div> : null}</span>,
                <span key="w" className="sub2">{r.detail}<div className="ink-chrome">{ISSUE_KIND[r.kind]?.fix ?? ""}</div></span>,
                r.programme_code ? <Link key="o" className="lnk" href={`/catalogue/structure?prog=${encodeURIComponent(r.programme_code)}`}>Open structure</Link>
                  : r.course_code ? <Link key="o" className="lnk" href={`/catalogue/course?code=${encodeURIComponent(r.course_code)}`}>Open course</Link> : <span key="o" />,
              ])} texts={rows.map((r) => `${ISSUE_KIND[r.kind]?.label ?? r.kind} ${r.programme ?? ""} ${r.programme_code ?? ""} ${r.course_code ?? ""} ${r.course ?? ""} ${r.dept_name ?? ""} ${r.faculty_name ?? ""}`)} />
            ) : <PBody><div className="sub2">No problem in view.</div></PBody>}
          </Panel>
        </>
      ) : null}
    </>
  );
}
