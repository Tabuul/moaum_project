"use client";

/** The admission funnel (V279): a session's applications at every stage the lifecycle records, counted on the
 *  server within the acting office's scope; each stage opens the applicants behind it. Asked after the page has
 *  painted, so the statistics are never held back by it. */
import { useEffect, useState } from "react";
import Link from "next/link";
import { LinkBtn, Note, Panel, PBody } from "@/components/proto/ui";
import { vzNum } from "@/components/proto/vz";

export interface FunnelStage { key: string; label: string; count: number }
export interface Funnel { scope: { kind: string; label: string; pg: boolean }; session: string; stages: FunnelStage[]; sessions: string[] }

export function AdmissionFunnel({ session, query = "" }: { session: string; query?: string }) {
  const [d, setD] = useState<Funnel | null>(null);
  const [failed, setFailed] = useState(false);
  useEffect(() => {
    let live = true;
    fetch(`/api/bff/api/v1/analytics/admissions/funnel?session=${encodeURIComponent(session)}${query ? `&${query}` : ""}`, { cache: "no-store" })
      .then(async (r) => { if (!live) return; if (!r.ok) { setFailed(true); return; } setD((await r.json()) as Funnel); })
      .catch(() => { if (live) setFailed(true); });
    return () => { live = false; };
  }, [session, query]);
  if (failed) return <Note kind="bad" title="Unable to load the admission funnel">The stages could not be counted just now. Please try again.</Note>;
  if (!d) return <Panel title="Admission funnel" right={<span className="sub2">Counting…</span>}><PBody><div className="sub2">Applications at every stage of the admission are being counted for {session}.</div></PBody></Panel>;
  const top = d.stages[0]?.count ?? 0;
  return (
    <Panel title={`Admission funnel · ${d.session}`} right={<span className="row row--inline row--tight"><span className="sub2">{d.scope.label}{d.scope.pg ? " · postgraduate applications" : ""}</span><LinkBtn size="sm" href={`/stats/funnel?session=${encodeURIComponent(d.session)}${query ? `&${query}` : ""}`}>Open the applicants</LinkBtn></span>}>
      <PBody>
        <div className="funnel">
          {d.stages.map((s, i) => {
            const share = top ? Math.round((100 * s.count) / top) : 0;
            const prev = i ? d.stages[i - 1].count : s.count;
            return (
              <Link key={s.key} href={`/stats/funnel?session=${encodeURIComponent(d.session)}&stage=${s.key}${query ? `&${query}` : ""}`} className="funnel__stage" title={`Open the ${s.label.toLowerCase()}`}>
                <span className="funnel__label">{i + 1}. {s.label}</span>
                <span className="funnel__bar" aria-hidden><span className="funnel__fill" style={{ width: `${share}%` }} /></span>
                <span className="funnel__n tnum">{vzNum(s.count)}<span className="sub2"> · {share}%{i && prev ? ` · ${Math.round((100 * s.count) / prev)}% of the stage before` : ""}</span></span>
              </Link>
            );
          })}
        </div>
      </PBody>
    </Panel>
  );
}
