/** V528: the Head's oversight of student password resets now the hourly limit is gone (V526) — each agent's resets today and in
 *  the last seven days (Lagos days), the daily average, the last one, and the figure at which the Head is told. Nothing is refused. */
import Link from "next/link";
import { Panel, PBody, Pil } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { type ResetsByAgent as Counts, pastAlert, weekAverage } from "@/lib/password-reset";

const when = (iso: string) => new Date(iso).toLocaleString("en-GB", { day: "2-digit", month: "2-digit", year: "numeric", hour: "2-digit", minute: "2-digit", timeZone: "Africa/Lagos" });

export function ResetsByAgent({ counts }: { counts: Counts }) {
  const alert = counts.alert_daily ?? null;
  const today = counts.agents.reduce((n, a) => n + a.today, 0);
  return (
    <Panel title="Resets by agent" right={alert != null
      ? <span className="sub2">The Head is told when one agent&rsquo;s resets in a day reach {alert.toLocaleString("en-GB")} · <Link className="lnk" href="/helpdesk/settings">change</Link></span>
      : <span className="sub2">No one is told of many resets · <Link className="lnk" href="/helpdesk/settings">set a figure</Link></span>}>
      {counts.agents.length ? (
        <DTable pageSize={0} cols={["Agent", "Today|num", "Last 7 days|num", "Daily average|num", "Last reset"]}
          rows={counts.agents.map((a) => [
            <span key="n">{a.name}{pastAlert(a, alert) ? <> <Pil kind="warn">Reached {alert}</Pil></> : null}</span>,
            <b key="t" className="tnum">{a.today.toLocaleString("en-GB")}</b>,
            <span key="w" className="tnum">{a.week.toLocaleString("en-GB")}</span>,
            <span key="avg" className="tnum sub2">{weekAverage(a)}</span>,
            <span key="l" className="sub2 tnum">{a.last_at ? when(a.last_at) : "—"}</span>,
          ])} texts={counts.agents.map((a) => a.name)} />
      ) : <PBody><div className="sub2">No student password reset in the last seven days.</div></PBody>}
      {counts.agents.length ? <PBody><div className="sub2">{today.toLocaleString("en-GB")} reset{today === 1 ? "" : "s"} today across the desk. Each one, with its reason and the student, is listed below.</div></PBody> : null}
    </Panel>
  );
}
