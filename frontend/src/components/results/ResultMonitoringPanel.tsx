"use client";

/**
 * V700: result monitoring on the Director of ICT's dashboard — the current session's semester at a glance, read after the page
 * so the dashboard never waits for it: the results in, pending verification and approval, published, missing, the exceptions, the
 * corrections, the broadsheets, and the results by faculty, each opening the list it counts.
 */
import { useEffect, useState } from "react";
import Link from "next/link";
import { Note, Panel, PBody, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { monitorQuery } from "@/lib/result-monitor";

interface Row { facultyCode: string; faculty: string | null; students: number; results: number; withResult: number; awaiting: number; atEntry: number;
  verification: number; approval: number; published: number; missing: number; exceptions?: number }
interface Overview { session: string; semester: number; rows: Row[]; totals: { students: number; results: number; withResult: number; awaiting: number; atEntry: number;
  verification: number; approval: number; published: number; missing: number; exceptions: number | null };
  corrections: { amendmentsOpen: number; amendmentsApplied: number; requestsOpen: number; requestsResolved: number }; broadsheets: number }

const n = (x: number | null | undefined) => (x ?? 0).toLocaleString();

export function ResultMonitoringPanel() {
  const [o, setO] = useState<Overview | null>(null);
  const [state, setState] = useState<"loading" | "ok" | "hidden" | "failed">("loading");
  useEffect(() => {
    let live = true;
    void fetch("/api/bff/api/v1/results/monitor/overview", { cache: "no-store" }).then(async (r) => {
      if (!live) return;
      if (r.status === 403 || r.status === 401) { setState("hidden"); return; }
      if (!r.ok) { setState("failed"); return; }
      setO(await r.json());
      setState("ok");
    }).catch(() => { if (live) setState("failed"); });
    return () => { live = false; };
  }, []);
  if (state === "hidden") return null;
  const period = o ? { session: o.session, sem: o.semester } : {};
  const viewer = (extra: Record<string, string | number> = {}) => `/results/monitor${monitorQuery({ ...period, ...extra })}`;
  return (
    <Panel title="Result monitoring" right={o ? <span className="sub2">{o.session} · semester {o.semester} · <Link href={viewer()}>Result viewer</Link></span> : <span className="sub2">Loading results…</span>}>
      <PBody>
        {state === "failed" ? <Note kind="bad" title="Unable to load results">The result figures did not load; open the <Link href="/results/monitor">Result viewer</Link>.</Note> : null}
        {o ? (
          <>
            <Tiles cls="grid--5" items={[
              ["Results uploaded", n(o.totals.withResult), null, `of ${n(o.totals.results)} registered courses`, viewer({ state: "ENTRY" })],
              ["Pending verification", n(o.totals.verification), o.totals.verification ? "var(--amber)" : null, "with the Programme Examinations Officer", viewer({ state: "VERIFICATION" })],
              ["Pending approval", n(o.totals.approval), o.totals.approval ? "var(--amber)" : null, "Departmental Board to Senate", viewer({ state: "APPROVAL" })],
              ["Published", n(o.totals.published), "var(--green)", `${n(o.broadsheets)} broadsheets with published results`, viewer({ state: "PUBLISHED" })],
              ["Missing results", n(o.totals.missing), o.totals.missing ? "var(--red)" : null, "a submitted sheet without the mark", viewer({ state: "MISSING" })],
            ]} />
            <Tiles cls="grid--4" items={[
              ["Results with exceptions", o.totals.exceptions == null ? "—" : n(o.totals.exceptions), o.totals.exceptions ? "var(--red)" : null, "need a look",
                `/results/monitor/exceptions${monitorQuery(period)}`],
              ["Corrections pending", n(o.corrections.requestsOpen + o.corrections.amendmentsOpen), null,
                `${n(o.corrections.requestsOpen)} requests · ${n(o.corrections.amendmentsOpen)} amendments`, `/results/monitor/corrections${monitorQuery({ ...period, state: "OPEN" })}`],
              ["Corrections completed", n(o.corrections.requestsResolved + o.corrections.amendmentsApplied), null, "applied or corrected",
                `/results/monitor/corrections${monitorQuery({ ...period, state: "CLOSED" })}`],
              ["Not available yet", n(o.totals.awaiting), null, "no sheet, or no mark at entry — never a fail", viewer({ state: "AWAITING" })],
            ]} />
            <DTable pageSize={0} cols={["Faculty", "Students|num", "Results|num", "With a result|num", "Pending|num", "Published|num", "Missing|num", "Exceptions|num"]}
              rows={o.rows.map((r) => [
                <Link key="f" href={viewer({ fac: r.facultyCode })}>{r.faculty ?? r.facultyCode}</Link>, n(r.students), n(r.results), n(r.withResult),
                n(r.atEntry + r.verification + r.approval), n(r.published), r.missing ? <b key="m" style={{ color: "var(--red)" }}>{n(r.missing)}</b> : "0",
                r.exceptions ? <Link key="e" href={`/results/monitor/exceptions${monitorQuery({ ...period, fac: r.facultyCode })}`}>{n(r.exceptions)}</Link> : "0",
              ])} />
            {!o.rows.length ? <Note kind="info" title="No approved registration this semester yet">The figures fill as students register and results are uploaded.</Note> : null}
          </>
        ) : state === "loading" ? <p className="sub2">Loading results…</p> : null}
      </PBody>
    </Panel>
  );
}
