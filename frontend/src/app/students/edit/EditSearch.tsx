"use client";

/** V642: the student found on the server — by name, matriculation, JAMB, admission or application number, the record's id, phone or e-mail — and opened for editing */
import Link from "next/link";
import { useEffect, useState } from "react";
import type { Problem } from "@/lib/api";
import { Note, Panel, PBody, Pil } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import { words, type SearchHit } from "@/lib/student-edit";

export function EditSearch() {
  const [q, setQ] = useState("");
  const [hits, setHits] = useState<SearchHit[] | null>(null);
  const [problem, setProblem] = useState<Problem | null>(null);
  const typed = q.trim();
  useEffect(() => {
    const t = typed;
    if (t.length < 3) return;
    let live = true;
    const h = setTimeout(async () => {
      const r = await fetch(`/api/bff/api/v1/student/edit/search?q=${encodeURIComponent(t)}`, { cache: "no-store" });
      const j = await r.json().catch(() => null);
      if (!live) return;
      if (r.ok) { setHits(j as SearchHit[]); setProblem(null); } else setProblem((j as Problem) ?? { status: r.status, title: r.statusText });
    }, 300);
    return () => { live = false; clearTimeout(h); };
  }, [typed]);
  // fewer than three characters search nothing: what was found before is not shown
  const shown = typed.length >= 3 ? hits : null;
  return (
    <Panel title="Find the student" right={<span className="sub2">Searched on the server; twenty at most</span>}>
      <PBody>
        <Field id="se-q" label="Name, matriculation number, JAMB number, application or admission number, student ID, phone or e-mail" full>
          <input id="se-q" className="ctl" autoFocus value={q} onChange={(e) => setQ(e.target.value)} placeholder="MOAU/SCI/23/1487, 202312345678AB, ADAMU Grace …" />
        </Field>
        {problem ? <ProblemNotice problem={problem} /> : null}
        {shown && !shown.length ? <Note kind="info" title="No student found">Check the number, or search by name.</Note> : null}
      </PBody>
      {shown && shown.length ? <DTable pageSize={0} cols={["Student", "Matriculation number", "JAMB number", "Programme", "Level|mid", "Status|mid", "|num"]} rows={shown.map((h) => [
        <b key="n">{h.name}</b>, <span key="m" className="tnum">{h.matric_no ?? h.admission_no ?? "—"}</span>, <span key="j" className="tnum">{h.jamb_reg_no ?? "—"}</span>,
        <span key="p">{h.programme ?? "—"}{h.programme_type ? <span className="sub2"> · {h.programme_type}</span> : null}</span>, h.current_level,
        <Pil key="s" kind={h.status === "ACTIVE" ? "ok" : "grey"}>{words(h.status)}</Pil>,
        <Link key="e" className="btn btn--primary btn--sm" href={`/students/${h.id}/edit`}>Edit</Link>,
      ])} /> : null}
    </Panel>
  );
}
