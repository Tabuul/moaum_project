"use client";

/**
 * The department's registration desk (V027): the course registrations
 * students submitted, with the courses and units on each, approved or
 * returned with the reason — the Head of Department's act, through the
 * endpoints that already served the office.
 */
import { useState } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { Btn, Panel, Pil, Two } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Modal } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import { semesterText } from "@/lib/student-portal";
import { notify } from "@/components/proto/Toast";

export interface RegEntry { code: string; title: string; units: number; kind: string | null; type: string }
export interface RegistrationRow {
  id: string; status: string; level: number; semester?: number; submitted_at: string | null; approved_at: string | null; units: number;
  matric_no: string | null; admission_no: string | null; surname: string; other_names: string; programme: string; dept_code: string; dept_name: string;
  courses: string | null; range: string | null; entries?: RegEntry[];
}

const SEM = (n?: number) => (n === 1 ? "First" : n === 2 ? "Second" : n === 3 ? "Third" : "—");

/** display order: carryover first, then GST, then Core, then Elective */
function entryRank(e: RegEntry): number {
  if ((e.type ?? "").toUpperCase() === "CARRYOVER") return 0;
  const k = (e.kind ?? "").toLowerCase();
  return k === "gst" ? 1 : (k === "core" || k === "compulsory" || k === "required") ? 2 : 3;
}

export function RegistrationApprovals({ rows, session, semester, actingOffice }: { rows: RegistrationRow[]; session: string; semester: number; actingOffice: string | null }) {
  const router = useRouter();
  // approval is one step and it is the Head of Department's (super is system break-glass)
  const may = ["hod", "super"].includes(actingOffice ?? "");
  const [busy, setBusy] = useState<string | null>(null);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [open, setOpen] = useState<RegistrationRow | null>(null);

  async function act(key: string, path: string, body: unknown, reason: string) {
    setBusy(key);
    setProblem(null);
    try {
      const r = await fetch(`/api/bff/api/v1/registration/course-registrations/${path}`, { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) }, body: JSON.stringify(body ?? {}) });
      const j = await r.json().catch(() => null);
      if (!r.ok) { setProblem(j && typeof j === "object" && "status" in j ? (j as Problem) : { status: r.status, title: r.statusText }); return; }
      notify(reason);
      router.refresh();
    } finally {
      setBusy(null);
    }
  }

  return (
    <>
    <Panel title="Course registrations submitted by students" right={`${rows.length} waiting · ${session}${semester ? ` · ${semesterText(semester)}` : " · all semesters"}`}>
      {problem ? <div className="card__body"><ProblemNotice problem={problem} /></div> : null}
      <DTable cols={["Student", "Programme", "Level|mid", "Semester|mid", "Courses", "Units|mid", "Submitted|mid", "|num"]} rows={rows.map((r) => [
        <button key="s" onClick={() => setOpen(r)} title="View the full course registration" style={{ background: "none", border: 0, padding: 0, textAlign: "left", cursor: "pointer" }}>
          <Two a={<span style={{ color: "var(--link, var(--chrome))", textDecoration: "underline" }}>{`${r.surname}, ${r.other_names}`}</span>} b={r.matric_no ?? r.admission_no ?? ""} />
        </button>,
        <span className="sub2" key="p">{r.programme}</span>,
        <span className="tnum" key="l">{r.level}</span>,
        <span className="sub2" key="sem">{SEM(r.semester)}</span>,
        <span className="sub2" key="c">{r.courses ?? "—"}</span>,
        <span key="u"><b className="tnum">{r.units}</b><div className="sub2">of {r.range ?? "—"}</div></span>,
        <span className="sub2 tnum" key="w">{r.submitted_at ? new Date(r.submitted_at).toLocaleDateString("en-GB") : "—"}</span>,
        <span key="a" className="row row--inline row--tight">
          <Btn kind="go" disabled={!may || busy !== null} onClick={() => void act(`ok-${r.id}`, `${r.id}/approve`, {}, `Registration of ${r.matric_no ?? r.admission_no} approved`)}>{busy === `ok-${r.id}` ? "Approving…" : "Approve"}</Btn>
          <Btn kind="ghost" disabled={!may || busy !== null} onClick={() => { const comment = window.prompt("What must the student change? They read this."); if (!comment) return; void act(`back-${r.id}`, `${r.id}/return`, { comment }, `Registration of ${r.matric_no ?? r.admission_no} returned: ${comment}`); }}>Return</Btn>
        </span>,
      ])} texts={rows.map((r) => `${r.surname} ${r.other_names} ${r.matric_no} ${r.admission_no} ${r.programme} ${r.courses ?? ""}`)} />
      {!rows.length ? <div className="card__body"><div className="sub2">Nothing submitted is waiting. A student&rsquo;s registration appears here the moment they submit it; approving it puts them on every class list it carries. <Pil kind="grey">Approved ones are on the class lists</Pil></div></div> : null}
    </Panel>

    {open ? (
      <Modal wide title={`${open.surname}, ${open.other_names}`}
        sub={`${open.matric_no ?? open.admission_no ?? ""} · ${open.programme} · ${open.level} Level · ${SEM(open.semester)} semester · ${session}`}
        onClose={() => setOpen(null)}
        foot={<>
          <Btn kind="ghost" onClick={() => setOpen(null)}>Close</Btn>
          <span className="grow" />
          <Btn kind="ghost" disabled={!may || busy !== null} onClick={() => { const comment = window.prompt("What must the student change? They read this."); if (!comment) return; void act(`back-${open.id}`, `${open.id}/return`, { comment }, `Registration of ${open.matric_no ?? open.admission_no} returned: ${comment}`).then(() => setOpen(null)); }}>Return</Btn>
          <Btn kind="go" disabled={!may || busy !== null} onClick={() => void act(`ok-${open.id}`, `${open.id}/approve`, {}, `Registration of ${open.matric_no ?? open.admission_no} approved`).then(() => setOpen(null))}>{busy === `ok-${open.id}` ? "Approving…" : "Approve"}</Btn>
        </>}>
        <DTable cols={["Code|mid", "Course title", "Units|num", "Kind|mid", "Basis|mid"]} rows={[...(open.entries ?? [])].sort((a, b) => entryRank(a) - entryRank(b) || a.code.localeCompare(b.code)).map((e) => [
          <b className="tnum" key="c">{e.code}</b>,
          <span key="t">{e.title}</span>,
          <span className="tnum" key="u">{e.units}</span>,
          <span className="sub2" key="k">{e.kind ?? "—"}</span>,
          <span key="b">{e.type === "CARRYOVER" ? <Pil kind="warn">Carryover</Pil> : <span className="sub2">{e.type === "REGISTERED" || e.type === "NORMAL" ? "Normal" : e.type}</span>}</span>,
        ])} />
        <div className="sub2" style={{ marginTop: 10, display: "flex", justifyContent: "space-between", flexWrap: "wrap" }}>
          <span><b className="tnum">{open.entries?.length ?? 0}</b> course{(open.entries?.length ?? 0) === 1 ? "" : "s"}</span>
          <span>Total <b className="tnum">{open.units}</b> units of {open.range ?? "—"} · submitted {open.submitted_at ? new Date(open.submitted_at).toLocaleDateString("en-GB") : "—"}</span>
        </div>
        {problem ? <div className="mt-2"><ProblemNotice problem={problem} /></div> : null}
      </Modal>
    ) : null}
    </>
  );
}
