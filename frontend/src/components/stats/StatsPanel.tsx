import Link from "next/link";
import { api } from "@/lib/api";
import { LinkBtn, Note, Panel, PBody } from "@/components/proto/ui";
import { EMPTY_FILTERS, SEMESTER_WORD, detailHref, type StatSummary } from "@/lib/stats";
import { StatTiles } from "./StudentStats";
import { StatsDonuts } from "./StatsDonuts";

/** The statistics on a dashboard (V257): the five figures as doors, the two donuts and the door to the full
 *  analytics — read on the server from the same engine, scoped to the office that opened the dashboard. */
export async function StatsPanel({ session, title = "Student statistics" }: { session?: string; title?: string }) {
  const r = await api<StatSummary>(`/api/v1/stats/students/summary${session ? `?session=${encodeURIComponent(session)}` : ""}`);
  if (!r.ok) {
    return <Note kind="bad" title="Unable to load student statistics">The figures could not be read just now. Please try again.</Note>;
  }
  const d = r.data;
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
