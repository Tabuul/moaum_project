"use client";

/** V646: the Duplicate course code report — one course code may carry more than one course (CSC 401 Computer Networks under CCMAS,
 *  CSC 401 Advanced Computer Systems under BMAS), each its own course with its own classes and results. Listed: every code the pool
 *  holds more than once, and every course whose title was changed after it was created (an upload once wrote a file's title over
 *  the course's), with the programmes it is bound to. The Academic Office or the Registry makes a separate course under a code
 *  and moves the programmes that take it; nothing already registered or scored moves. */
import { useState } from "react";
import { useRouter } from "next/navigation";
import { Btn, Note, Panel, PBody, Pil } from "@/components/proto/ui";
import { Field } from "@/components/proto/blocks";
import { DTable } from "@/components/proto/DTable";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { reasonHeader } from "@/lib/reason";
import { brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";
import { codeVariant, shownCode } from "@/lib/course-code";

export interface SameCodeRow {
  shown_code: string; course_code: string; course_id: string; title: string; curriculum: string | null; variant: string | null;
  dept_code: string | null; department: string | null; faculty: string | null; level: number | null; semester: number | null; kind: string | null;
  state: string | null; programmes: number; programme_list: string | null; courses_under_code: number; title_changes: number;
  earlier_titles: string | null; last_title_change: string | null;
}

/** "C00001 (400), C00002 (500)" — the programmes a course is bound to, as the report lists them */
export function bindingsOf(list: string | null): { programme: string; level: number }[] {
  return (list ?? "").split(",").map((s) => s.trim().match(/^(\S+) \((\d+)\)$/)).filter((m): m is RegExpMatchArray => !!m)
    .map((m) => ({ programme: m[1], level: Number(m[2]) }));
}

export function SameCodePanel({ rows, maySeparate }: { rows: SameCodeRow[]; maySeparate: boolean }) {
  const router = useRouter();
  const [q, setQ] = useState("");
  const [only, setOnly] = useState<"" | "SHARED" | "CHANGED">("");
  const [curr, setCurr] = useState("");
  const [open, setOpen] = useState<string | null>(null);
  const [title, setTitle] = useState("");
  const [curriculum, setCurriculum] = useState("");
  const [moving, setMoving] = useState<Record<string, boolean>>({});
  const [reason, setReason] = useState("");
  const [busy, setBusy] = useState(false);
  const shared = new Set(rows.filter((r) => r.courses_under_code > 1).map((r) => r.shown_code)).size;
  const changed = rows.filter((r) => r.title_changes > 0).length;
  const needle = q.trim().toLowerCase();
  const shown = rows.filter((r) => (!needle || `${r.shown_code} ${r.course_code} ${r.title} ${r.department ?? ""}`.toLowerCase().includes(needle))
    && (!only || (only === "SHARED" ? r.courses_under_code > 1 : r.title_changes > 0)) && (!curr || r.curriculum === curr));

  function start(r: SameCodeRow) {
    setOpen(r.course_code); setTitle(""); setCurriculum(r.curriculum === "BMAS" ? "CCMAS" : r.curriculum === "CCMAS" ? "BMAS" : ""); setReason("");
    setMoving({});
  }

  async function separate(r: SameCodeRow) {
    if (!title.trim() || reason.trim().length < 10) return;
    setBusy(true);
    try {
      const bindings = bindingsOf(r.programme_list).filter((b) => moving[`${b.programme}|${b.level}`]);
      const res = await fetch(`/api/bff/api/v1/catalogue/courses/${encodeURIComponent(r.course_code)}/separate`, {
        method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason.trim()) },
        body: JSON.stringify({ title: title.trim(), curriculum: curriculum || null, bindings, reason: reason.trim() }),
      });
      const j = await res.json().catch(() => null);
      if (!res.ok) { notifyProblem(j ?? { status: res.status, title: res.statusText }); return; }
      const out = j as { code: string; bindingsMoved: number; classesOpened: number };
      notify(`${shownCode(out.code)} — ${title.trim()} is a separate course · ${out.bindingsMoved} programme binding${out.bindingsMoved === 1 ? "" : "s"} moved`);
      setOpen(null);
      router.refresh();
    } finally { setBusy(false); }
  }

  async function exportXlsx() {
    const cols = ["Course ID", "Course Code", "Course Title", "Curriculum", "Department", "Faculty", "Level", "Semester", "Kind", "Status", "Programmes (level)", "Courses under the code", "Title changes", "Earlier titles", "Last title change"];
    const data = shown.map((r) => [r.course_id, shownCode(r.course_code) + (r.variant ? ` (${r.variant})` : ""), r.title, r.curriculum ?? "", r.department ?? r.dept_code ?? "", r.faculty ?? "",
      r.level ?? "", r.semester ?? "", r.kind ?? "", r.state ?? "", r.programme_list ?? "", r.courses_under_code, r.title_changes, r.earlier_titles ?? "", r.last_title_change ? r.last_title_change.slice(0, 10) : ""]);
    downloadBlob(await brandedXlsx("Duplicate course code report", cols, data, { serial: docSerial("DCC") }), "Duplicate course code report.xlsx");
  }

  return (
    <Panel title="One code, different titles" right={`${shared} code${shared === 1 ? "" : "s"} held more than once · ${changed} title${changed === 1 ? "" : "s"} changed`}>
      <PBody>
        <div className="sub2 mb-2">
          A course code may carry more than one course, each with its own title, classes and results. Listed: every code held more than once, and
          every course whose title was changed after it was created. Where an upload once wrote one curriculum&rsquo;s title over another&rsquo;s,
          make a separate course under the code and move the programmes that take it. Registrations and results already made stay where they are.
        </div>
        <div className="row row--end">
          <Field id="sc-q" label="Code or title"><input id="sc-q" className="ctl" value={q} placeholder="CSC 401" onChange={(e) => setQ(e.target.value)} /></Field>
          <Field id="sc-only" label="Show">
            <select id="sc-only" className="ctl" value={only} onChange={(e) => setOnly(e.target.value as "" | "SHARED" | "CHANGED")}>
              <option value="">Both</option><option value="SHARED">Codes held more than once</option><option value="CHANGED">Titles changed</option>
            </select>
          </Field>
          <Field id="sc-curr" label="Curriculum">
            <select id="sc-curr" className="ctl" value={curr} onChange={(e) => setCurr(e.target.value)}>
              <option value="">All</option><option value="BMAS">BMAS</option><option value="CCMAS">CCMAS</option>
            </select>
          </Field>
          <Btn kind="ghost" disabled={!shown.length} onClick={() => void exportXlsx()}>Excel</Btn>
        </div>
        {!shown.length ? <div className="sub2 mt-2">{rows.length ? "None matches." : "No code is held more than once, and no title has been changed."}</div> : (
          <DTable cols={["Code", "Title", "Curriculum|mid", "Department", "Level|num", "Programmes", "Title changes", "|mid"]} rows={shown.map((r) => [
            <span key="c" className="tnum"><b>{shownCode(r.course_code)}</b>{codeVariant(r.course_code) ? <div className="sub2">key {r.course_code}</div> : null}</span>,
            <span key="t">{r.title}{r.state && r.state !== "LIVE" ? <div className="sub2">{r.state}</div> : null}</span>,
            r.curriculum ? <Pil key="u" kind="info">{r.curriculum}</Pil> : <span key="u" className="sub2">—</span>,
            <span key="d" className="sub2">{r.department ?? r.dept_code ?? "—"}</span>,
            <span key="l" className="tnum">{r.level ?? "—"}</span>,
            <span key="p" className="sub2 tnum">{r.programmes ? r.programme_list : "None bound"}</span>,
            <span key="h" className="sub2">{r.title_changes ? <>{r.title_changes} · was {r.earlier_titles}{r.last_title_change ? ` · last ${r.last_title_change.slice(0, 10)}` : ""}</> : "—"}</span>,
            maySeparate ? <Btn key="x" kind="ghost" size="sm" onClick={() => start(r)}>Separate course</Btn> : <span key="x" />,
          ])} />
        )}
        {open ? (() => {
          const r = rows.find((x) => x.course_code === open);
          if (!r) return null;
          const binds = bindingsOf(r.programme_list);
          return (
            <Note kind="info" title={`A separate course under ${shownCode(r.course_code)}`}>
              <div className="sub2 mb-2">{shownCode(r.course_code)} — {r.title} stays as it is, with everything already registered and scored under it. The new course takes its units, semester, level and owner, its own title and curriculum, and the programmes you tick.</div>
              <div className="row row--end">
                <Field id="sc-title" label="Title of the separate course"><input id="sc-title" className="ctl" value={title} onChange={(e) => setTitle(e.target.value)} /></Field>
                <Field id="sc-ncurr" label="Curriculum">
                  <select id="sc-ncurr" className="ctl" value={curriculum} onChange={(e) => setCurriculum(e.target.value)}>
                    <option value="">None</option><option value="BMAS">BMAS</option><option value="CCMAS">CCMAS</option>
                  </select>
                </Field>
              </div>
              {binds.length ? (
                <div className="mt-2">
                  <div className="sub2">Programmes that take the separate course from now:</div>
                  <div className="row row--inline row--tight">
                    {binds.map((b) => {
                      const k = `${b.programme}|${b.level}`;
                      return <label key={k} className="row row--inline row--tight"><input type="checkbox" checked={!!moving[k]} onChange={(e) => setMoving((m) => ({ ...m, [k]: e.target.checked }))} /> <span className="tnum">{b.programme} at {b.level}</span></label>;
                    })}
                  </div>
                </div>
              ) : <div className="sub2 mt-2">No programme takes {shownCode(r.course_code)} yet; bind the separate course on the programme&rsquo;s structure.</div>}
              <Field id="sc-reason" label="Reason" hint="Ten characters or more"><input id="sc-reason" className="ctl" value={reason} onChange={(e) => setReason(e.target.value)} /></Field>
              <div className="row mt-2">
                <Btn kind="primary" disabled={busy || !title.trim() || reason.trim().length < 10} onClick={() => void separate(r)}>{busy ? "Working…" : "Make the separate course"}</Btn>
                <Btn kind="ghost" disabled={busy} onClick={() => setOpen(null)}>Cancel</Btn>
              </div>
            </Note>
          );
        })() : null}
      </PBody>
    </Panel>
  );
}
