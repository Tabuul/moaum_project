"use client";
/** The JUPEB student's CBT examinations (V365): the University's one CBT engine, behind the JUPEB door — the examinations of the subjects
 *  they are registered for, whether they may sit and why not, the instructions, the start, and the result once released. The same list
 *  and the same examination room the University's students have; the server judges eligibility (admitted, registered for the subject,
 *  the semester's share of the school fee paid) at the start. */
import { useCallback, useEffect, useState } from "react";
import type { Problem } from "@/lib/api";
import { Note, PBody, Panel } from "@/components/proto/ui";
import { ProblemNotice } from "@/components/ProblemNotice";
import { MyExams as CbtMyExams } from "@/components/cbt/MyExams";
import type { MyExams as CbtMyExamsData } from "@/lib/cbt";

const API = "/api/bff/api/v1/jupeb/me/cbt";

export function JupebCbt({ who }: { who: { name: string; number: string } }) {
  const [data, setData] = useState<CbtMyExamsData | null>(null);
  const [problem, setProblem] = useState<Problem | null>(null);
  const load = useCallback(async () => {
    const r = await fetch(API, { cache: "no-store" }).catch(() => null);
    if (!r) { setProblem({ status: 503, title: "The portal could not be reached just now." }); return; }
    const j = await r.json().catch(() => null);
    if (!r.ok) { setProblem((j as Problem) ?? { status: r.status, title: r.statusText }); return; }
    setData(j as CbtMyExamsData);
  }, []);
  useEffect(() => { const t = window.setTimeout(() => void load(), 0); return () => window.clearTimeout(t); }, [load]);

  if (problem) return <ProblemNotice problem={problem} />;
  if (!data) return <Panel title="CBT examinations"><PBody><span className="sub2">Loading…</span></PBody></Panel>;
  return (
    <>
      {!data.rows.length ? (
        <Note kind="info" title="No CBT examination on your subjects yet" />
      ) : null}
      {data.rows.length ? <CbtMyExams data={data} who={who} apiBase={API} roomBase="/jupeb/portal/cbt/room" feesHref="/jupeb/portal?tab=payments" /> : null}
    </>
  );
}
