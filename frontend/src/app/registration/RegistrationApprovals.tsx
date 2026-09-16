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
import { ProblemNotice } from "@/components/ProblemNotice";

export interface RegistrationRow {
  id: string; status: string; level: number; submitted_at: string | null; approved_at: string | null; units: number;
  matric_no: string | null; admission_no: string | null; surname: string; other_names: string; programme: string; dept_code: string; dept_name: string;
  courses: string | null; range: string | null;
}

export function RegistrationApprovals({ rows, session, semester, actingOffice }: { rows: RegistrationRow[]; session: string; semester: number; actingOffice: string | null }) {
  const router = useRouter();
  const may = ["hod", "lecturer", "academic", "registrar", "dregistrar", "super"].includes(actingOffice ?? "");
  const [busy, setBusy] = useState<string | null>(null);
  const [problem, setProblem] = useState<Problem | null>(null);

  async function act(key: string, path: string, body: unknown, reason: string) {
    setBusy(key);
    setProblem(null);
    try {
      const r = await fetch(`/api/bff/api/v1/registration/course-registrations/${path}`, { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) }, body: JSON.stringify(body ?? {}) });
      const j = await r.json().catch(() => null);
      if (!r.ok) { setProblem(j && typeof j === "object" && "status" in j ? (j as Problem) : { status: r.status, title: r.statusText }); return; }
      router.refresh();
    } finally {
      setBusy(null);
    }
  }

  return (
    <Panel title="Course registrations submitted by students" right={`${rows.length} waiting · ${session} · semester ${semester}`}>
      {problem ? <div className="card__body"><ProblemNotice problem={problem} /></div> : null}
      <DTable cols={["Student", "Programme", "Level|mid", "Courses", "Units|mid", "Submitted|mid", "|num"]} rows={rows.map((r) => [
        <Two key="s" a={`${r.surname}, ${r.other_names}`} b={r.matric_no ?? r.admission_no ?? ""} />,
        <span className="sub2" key="p">{r.programme}</span>,
        <span className="tnum" key="l">{r.level}</span>,
        <span className="sub2" key="c">{r.courses ?? "—"}</span>,
        <span key="u"><b className="tnum">{r.units}</b><div className="sub2">of {r.range ?? "—"}</div></span>,
        <span className="sub2 tnum" key="w">{r.submitted_at ? new Date(r.submitted_at).toLocaleDateString("en-GB") : "—"}</span>,
        <span key="a" style={{ display: "inline-flex", gap: 6 }}>
          <Btn kind="go" disabled={!may || busy !== null} onClick={() => void act(`ok-${r.id}`, `${r.id}/approve`, {}, `Registration of ${r.matric_no ?? r.admission_no} approved`)}>{busy === `ok-${r.id}` ? "Approving…" : "Approve"}</Btn>
          <Btn kind="ghost" disabled={!may || busy !== null} onClick={() => { const comment = window.prompt("What must the student change? They read this."); if (!comment) return; void act(`back-${r.id}`, `${r.id}/return`, { comment }, `Registration of ${r.matric_no ?? r.admission_no} returned: ${comment}`); }}>Return</Btn>
        </span>,
      ])} texts={rows.map((r) => `${r.surname} ${r.other_names} ${r.matric_no} ${r.admission_no} ${r.programme} ${r.courses ?? ""}`)} />
      {!rows.length ? <div className="card__body"><div className="sub2">Nothing submitted is waiting. A student&rsquo;s registration appears here the moment they submit it; approving it puts them on every class list it carries. <Pil kind="grey">Approved ones are on the class lists</Pil></div></div> : null}
    </Panel>
  );
}
