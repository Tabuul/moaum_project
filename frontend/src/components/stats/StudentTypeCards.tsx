"use client";

/** The student population by programme type (V469) on a dashboard: the total and one card a type — Undergraduate,
 *  Postgraduate, CCE, Preliminary, Sandwich, JUPEB and any other the registry has learners for — each opening the Student
 *  Query with that type applied. Counted by the one engine (/api/v1/stats/students/query/summary) within the office's
 *  scope, current students only; asked after the page has painted, so the dashboard is never held back by the count. */
import { useEffect, useState } from "react";
import Link from "next/link";
import { LinkBtn, Note, Panel, PBody } from "@/components/proto/ui";
import type { QuerySummary } from "@/lib/student-query";

const n = (v: number) => Number(v).toLocaleString("en-GB");

export function StudentTypeCards({ title = "Student population" }: { title?: string }) {
  const [d, setD] = useState<QuerySummary | null>(null);
  const [failed, setFailed] = useState(false);

  useEffect(() => {
    let live = true;
    const ctl = new AbortController();
    const timer = setTimeout(() => ctl.abort(), 60_000);
    (async () => {
      try {
        const r = await fetch("/api/bff/api/v1/stats/students/query/summary?status=CURRENT", { cache: "no-store", signal: ctl.signal });
        if (!live) return;
        if (!r.ok) { setFailed(true); return; }
        setD((await r.json()) as QuerySummary);
      } catch { if (live) setFailed(true); }
      finally { clearTimeout(timer); }
    })();
    return () => { live = false; ctl.abort(); };
  }, []);

  if (failed) {
    return <Note kind="bad" title="Unable to count the students by type" action={<LinkBtn href="/student-query">Open Student Query</LinkBtn>}>The figures could not be read just now. Please try again.</Note>;
  }
  if (!d) {
    return <Panel title={title} right={<span className="sub2">Counting from the register…</span>}><PBody><div className="sub2">Counting…</div></PBody></Panel>;
  }
  const bound = d.scope.programmeType;
  return (
    <Panel title={title} right={<span className="row row--inline row--tight"><span className="sub2">{d.scope.label} · current students</span><LinkBtn kind="primary" size="sm" href="/student-query?status=CURRENT">Student Query</LinkBtn></span>}>
      <PBody>
        <div className="grid grid--4">
          {bound ? null : (
            <Link href="/student-query?status=CURRENT" className="tile stat-tile" title="Open every current student in your scope">
              <div className="eyebrow">Total students</div>
              <div className="n tnum">{n(d.total)}</div>
              <div className="c">All student types</div>
            </Link>
          )}
          {d.types.map((t) => (
            <Link key={t.code} href={`/student-query?type=${encodeURIComponent(t.code)}&status=CURRENT`} className="tile stat-tile" title={`Open the ${t.name} students`}>
              <div className="eyebrow">{t.name}</div>
              <div className="n tnum">{n(t.count)}</div>
              <div className="c">{t.name} students</div>
            </Link>
          ))}
          {!bound && d.requiresClassification ? (
            <Link href="/student-query?classification=REQUIRES_CLASSIFICATION" className="tile stat-tile" title="Open the students whose classification is to be decided">
              <div className="eyebrow">Requires classification</div>
              <div className="n tnum" style={{ color: "var(--amber-ink)" }}>{n(d.requiresClassification)}</div>
              <div className="c">In no type until the Academic Office decides</div>
            </Link>
          ) : null}
        </div>
      </PBody>
    </Panel>
  );
}
