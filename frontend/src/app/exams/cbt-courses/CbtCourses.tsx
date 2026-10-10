"use client";
/** t/cbtcourses — which courses the University examines by CBT (V364). No course is assumed to be one: the Academic Office, the Registry
 *  or Examinations and Records allows a course (the GST and EPS offices their own General Studies courses), and only then is a CBT
 *  examination created, published and sat on it. A course is withdrawn only while no CBT examination of it is still to be completed. */
import { useState } from "react";
import { useRouter } from "next/navigation";
import { useQueryNav } from "@/lib/query-nav";
import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, PageHead, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import type { Problem } from "@/lib/api";

interface CourseRow {
  code: string; title: string; kind: string; general_office: string | null; level: number; semester: number; units: number; dept_code: string | null; department: string | null;
  cbt_enabled: boolean; questions: number; exams: number; open_exams: number;
}
export interface CbtCoursePage { rows: CourseRow[]; total: number; page: number; size: number; canSet: boolean }

export function CbtCourses({ data, query }: { data: CbtCoursePage; query: { q: string; enabled: string; level: string } }) {
  const go = useQueryNav();
  const router = useRouter();
  const [text, setText] = useState(query.q);
  const [busy, setBusy] = useState<string | null>(null);
  const pages = Math.max(1, Math.ceil(data.total / data.size));
  const href = (patch: Record<string, string>) => {
    const p = new URLSearchParams();
    const all = { ...query, page: String(data.page), ...patch };
    for (const [k, v] of Object.entries(all)) if (v && !(k === "page" && v === "1")) p.set(k, v);
    return `/exams/cbt-courses${p.toString() ? `?${p.toString()}` : ""}`;
  };

  async function set(c: CourseRow, on: boolean) {
    setBusy(c.code);
    try {
      const r = await fetch(`/api/bff/api/v1/cbt/catalogue/${encodeURIComponent(c.code)}`, {
        method: "PUT", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`${on ? "Allow" : "Withdraw"} CBT for ${c.code}`) }, body: JSON.stringify({ enabled: on }),
      });
      const j = await r.json().catch(() => null);
      if (!r.ok) { notifyProblem((j as Problem) ?? { status: r.status, title: r.statusText }); return; }
      notify(`${c.code} ${on ? "may now be examined by CBT" : "is no longer a CBT course"}`);
      router.refresh();
    } finally { setBusy(null); }
  }

  return (
    <>
      <PageHead description="A course is withdrawn only while none of its CBT examinations is still to be completed."
        actions={<form className="row row--inline row--tight" onSubmit={(e) => { e.preventDefault(); go(href({ q: text.trim(), page: "1" })); }}>
          <input className="ctl" aria-label="Search courses" placeholder="Code or title" value={text} onChange={(e) => setText(e.target.value)} />
          <select className="ctl" aria-label="CBT" value={query.enabled} onChange={(e) => go(href({ enabled: e.target.value, page: "1" }))}><option value="">Every course</option><option value="true">CBT courses</option><option value="false">Not CBT</option></select>
          <select className="ctl" aria-label="Level" value={query.level} onChange={(e) => go(href({ level: e.target.value, page: "1" }))}><option value="">Every level</option>{[100, 200, 300, 400, 500, 600, 700, 800].map((l) => <option key={l} value={l}>{l}</option>)}</select>
          <Btn kind="secondary" type="submit">Search</Btn>
        </form>} />
      <Tiles items={[
        ["COURSES", data.total.toLocaleString(), null, query.enabled === "true" ? "Allowed CBT" : query.enabled === "false" ? "Not CBT" : "Within your scope"],
        ["ON THIS PAGE", String(data.rows.length), null, `Page ${data.page} of ${pages}`],
        ["CBT HERE", String(data.rows.filter((r) => r.cbt_enabled).length), "var(--green-ink)", "Allowed on this page"],
      ]} />
      <Panel title="Courses" right={<span className="sub2">{data.canSet ? "Allow or withdraw CBT per course" : "Read only: the Academic Office, the Registry or Examinations and Records sets these"}</span>}>
        {data.rows.length ? (
          <DTable pageSize={data.size} cols={["Course", "Department", "Level|mid", "Units|num", "Questions|num", "CBT examinations|num", "CBT|mid", "|num"]} rows={data.rows.map((c) => [
            <span key="c"><b className="tnum">{c.code}</b><div className="sub2">{c.title}</div></span>,
            <span key="d" className="sub2">{c.kind === "GST" ? `${c.general_office ?? "GST"} office` : c.department ?? c.dept_code ?? "—"}</span>,
            <span key="l" className="tnum">{c.level}</span>,
            <span key="u" className="tnum">{c.units}</span>,
            <span key="q" className="tnum">{Number(c.questions).toLocaleString()}</span>,
            <span key="e" className="tnum">{Number(c.exams).toLocaleString()}{Number(c.open_exams) ? <div className="sub2">{c.open_exams} to complete</div> : null}</span>,
            c.cbt_enabled ? <Pil key="s" kind="ok">CBT</Pil> : <Pil key="s" kind="grey">Not CBT</Pil>,
            data.canSet ? (c.cbt_enabled
              ? <Btn key="a" kind="ghost" size="sm" disabled={busy === c.code || Number(c.open_exams) > 0} onClick={() => void set(c, false)}>{busy === c.code ? "…" : "Withdraw"}</Btn>
              : <Btn key="a" kind="primary" size="sm" disabled={busy === c.code} onClick={() => void set(c, true)}>{busy === c.code ? "…" : "Allow CBT"}</Btn>) : <span key="a" />,
          ])} texts={data.rows.map((c) => `${c.code} ${c.title} ${c.department ?? ""}`)} />
        ) : <PBody><div className="sub2">No course matches.</div></PBody>}
        {pages > 1 ? (
          <PBody>
            <div className="row row--inline row--tight">
              <Btn kind="ghost" size="sm" disabled={data.page <= 1} onClick={() => go(href({ page: String(data.page - 1) }))}>Previous</Btn>
              <span className="sub2">Page {data.page} of {pages}</span>
              <Btn kind="ghost" size="sm" disabled={data.page >= pages} onClick={() => go(href({ page: String(data.page + 1) }))}>Next</Btn>
            </div>
          </PBody>
        ) : null}
      </Panel>
    </>
  );
}
