"use client";

/** The statistics on a dashboard (V257): the five figures as doors, the two donuts and the door to the full
 *  analytics. The block asks the engine after the page has painted, so a dashboard is never held back by the
 *  count; while the count runs it says so, and if the engine does not answer it says that instead. */
import { useEffect, useState } from "react";
import Link from "next/link";
import { LinkBtn, Note, Panel, PBody } from "@/components/proto/ui";
import { EMPTY_FILTERS, SEMESTER_WORD, detailHref, type StatSummary } from "@/lib/stats";
import { StatTiles } from "./StudentStats";
import { StatsDonuts } from "./StatsDonuts";

export function StatsPanel({ session, title = "Student statistics" }: { session?: string; title?: string }) {
  const [d, setD] = useState<StatSummary | null>(null);
  const [failed, setFailed] = useState(false);

  useEffect(() => {
    let live = true;
    const ctl = new AbortController();
    const timer = setTimeout(() => ctl.abort(), 90_000);
    (async () => {
      try {
        const r = await fetch(`/api/bff/api/v1/stats/students/summary${session ? `?session=${encodeURIComponent(session)}` : ""}`, { cache: "no-store", signal: ctl.signal });
        if (!live) return;
        if (!r.ok) { setFailed(true); return; }
        setD((await r.json()) as StatSummary);
      } catch { if (live) setFailed(true); }
      finally { clearTimeout(timer); }
    })();
    return () => { live = false; ctl.abort(); };
  }, [session]);

  if (failed) {
    return <Note kind="bad" title="Unable to load student statistics" action={<LinkBtn href="/stats">Open Student Statistics</LinkBtn>}>The figures could not be read just now. Please try again.</Note>;
  }
  if (!d) {
    return (
      <Panel title={title} right={<span className="sub2">Counting from the register…</span>}>
        <PBody><div className="sub2">Students in study, paid, registered, paid not registered and not paid are being counted for the current session.</div></PBody>
      </Panel>
    );
  }
  const f = { ...EMPTY_FILTERS, session: d.session, semester: d.semester == null ? "" : String(d.semester) };
  const t = d.totals;
  return (
    <Panel title={title} right={<span className="row row--inline row--tight"><span className="sub2">{d.scope.label} · {d.session} · {SEMESTER_WORD(d.semester)}</span><LinkBtn kind="primary" size="sm" href={`/stats?session=${encodeURIComponent(d.session)}${d.semester ? `&semester=${d.semester}` : ""}`}>Full Analytics</LinkBtn></span>}>
      <PBody>
        <StatTiles t={t} f={f} compact />
        {t.total === 0 ? (
          <div className="sub2 mt-3">No students found. No students match the current academic session and semester within this scope.</div>
        ) : (
          <>
            <div className="mt-3"><StatsDonuts t={t} f={f} /></div>
            <div className="row mt-3">
              <Link className="lnk" href={detailHref(f, "PAID_NOT_REGISTERED")}>Paid but not registered</Link>
              <Link className="lnk" href={detailHref(f, "NOT_PAID")}>Not paid</Link>
              <Link className="lnk" href="/stats">By faculty, department and programme</Link>
            </div>
          </>
        )}
      </PBody>
    </Panel>
  );
}
