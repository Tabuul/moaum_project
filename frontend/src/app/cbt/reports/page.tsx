import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { LinkBtn, Note, Panel, PBody, Pil } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { whenAt } from "@/lib/cbt";

export const dynamic = "force-dynamic";

interface Row { sitting_id: string; label: string; venue: string; starts_at: string; ends_at: string; exam_id: string; reference: string; title: string; course_code: string; session: string;
  seated: number; incidents: number; filed_at: string | null; filed_by: string | null; phase: "FILED" | "DUE" | "RUNNING" | "TO_COME"; counts: Record<string, number> | null }

const OFFICES: Record<string, [string, string]> = { GST: ["t/gstcbt", "/gst"], EPS: ["t/epscbt", "/eps"], EXAMS: ["t/unicbt", "/exams"], JUPEB: ["jupeb/cbt", "/jupeb"] };
const PHASE: Record<Row["phase"], [string, "ok" | "bad" | "info" | "grey"]> = { FILED: ["Filed", "ok"], DUE: ["Report due", "bad"], RUNNING: ["Running", "info"], TO_COME: ["To come", "grey"] };

/** the office's CBT sittings and their reports in one place (V375): filed, due (over and not filed), running, to come */
export default async function Page({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const office = typeof p.office === "string" && OFFICES[p.office.toUpperCase()] ? p.office.toUpperCase() : "EXAMS";
  const session = typeof p.session === "string" ? p.session : "";
  const [me, rows] = await Promise.all([api<Me>("/api/v1/iam/me"),
    api<Row[]>(`/api/v1/cbt/sitting-reports?office=${office}${session ? `&session=${encodeURIComponent(session)}` : ""}`)]);
  const [route, base] = OFFICES[office];
  const due = rows.ok ? rows.data.filter((r) => r.phase === "DUE").length : 0;
  return (
    <Shell route={route} me={me.ok ? me.data : null}>
      <div className="mb-3"><LinkBtn kind="ghost" href={`${base}/cbt`}>← CBT examinations</LinkBtn></div>
      {!rows.ok ? <ProblemNotice problem={rows.problem} /> : (
        <>
          {due ? <Note kind="bad" title={`${due} sitting${due === 1 ? " has" : "s have"} ended without a report`}>The chief invigilator files it from the sitting&rsquo;s board.</Note> : null}
          <Panel title="Sitting reports" right={<span className="sub2">{rows.data.length} sittings{session ? ` · ${session}` : ""}</span>}>
            {rows.data.length ? (
              <DTable pageSize={50} cols={["When", "Examination", "Sitting", "Seated|num", "Absent|num", "Incidents|num", "Report|mid", "|mid"]} rows={rows.data.map((r) => [
                <span key="w">{whenAt(r.starts_at)}</span>,
                <span key="e"><b className="tnum">{r.course_code}</b> {r.title}<div className="sub2 tnum">{r.reference}</div></span>,
                <span key="s">{r.label}<div className="sub2">{r.venue}</div></span>,
                <span key="n" className="tnum">{r.seated}</span>,
                <span key="a" className="tnum">{r.counts ? r.counts.absent : "—"}</span>,
                <span key="i" className="tnum">{r.incidents}</span>,
                <span key="p"><Pil kind={PHASE[r.phase][1]}>{PHASE[r.phase][0]}</Pil>{r.filed_at ? <div className="sub2">{whenAt(r.filed_at)}{r.filed_by ? ` · ${r.filed_by}` : ""}</div> : null}</span>,
                <LinkBtn key="o" kind={r.phase === "DUE" ? "primary" : "secondary"} href={`/cbt/invigilate/${r.sitting_id}/report`}>{r.filed_at ? "Read" : "Open"}</LinkBtn>,
              ])} texts={rows.data.map((r) => `${r.course_code} ${r.title} ${r.reference} ${r.label} ${r.venue}`)} />
            ) : <PBody><div className="sub2">No sitting yet.</div></PBody>}
          </Panel>
        </>
      )}
    </Shell>
  );
}
