"use client";

/** V318 · the result pipeline in one panel, for a dashboard: the nine stages with their real counts (each a link
 *  into the monitor filtered to that stage), the coverage counted from the rolls, what needs this desk, and every
 *  programme and level's live broadsheet. The full monitor is /results/pipeline. */
import Link from "next/link";
import type { PipelineView } from "@/lib/results";
import { LinkBtn, Note, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";

/** the monitor, filtered to a stage, in the scope the view was read for */
export function pipelineHref(view: PipelineView, stage?: string): string {
  const q = new URLSearchParams();
  q.set("session", view.session);
  if (view.semester) q.set("sem", String(view.semester));
  if (view.prog) q.set("prog", view.prog);
  if (stage) q.set("stage", stage);
  return `/results/pipeline?${q.toString()}`;
}

export function broadsheetHref(view: PipelineView, p: { programmeCode: string; level: number }, sem?: number | null): string {
  const q = new URLSearchParams();
  q.set("prog", p.programmeCode);
  q.set("level", String(p.level));
  q.set("session", view.session);
  q.set("sem", String(sem ?? view.semester ?? 1));
  return `/results/broadsheet?${q.toString()}`;
}

const STAGE_COLOUR = (stage: string, n: number) => (n === 0 ? null : stage === "ENTRY" ? "var(--red-ink)" : stage === "PUBLISHED" ? "var(--green-ink)" : "var(--chrome)");

export function PipelinePanel({ view, title, programmes = true, summary = true }: { view: PipelineView; title: string; programmes?: boolean; summary?: boolean }) {
  const cv = view.coverage;
  const attention = view.attention.length;
  const missingCourses = view.missing.length;
  return (
    <>
      {summary ? <Panel title={title} right={<LinkBtn kind="primary" href={pipelineHref(view)}>Open the monitor</LinkBtn>}>
        <PBody>
          <div className="row row--tight" style={{ flexWrap: "wrap" }}>
            {view.stages.map((s, i) => (
              <Link key={s.stage} href={pipelineHref(view, s.stage)} className="btn btn--ghost btn--sm" style={{ flexDirection: "column", alignItems: "flex-start", gap: 1, textDecoration: "none", minWidth: 118 }}
                title={`${s.candidates} candidate${s.candidates === 1 ? "" : "s"} · ${s.desk}`}>
                <span className="t-xs">{i + 1}. {s.label}</span>
                <span className="tnum" style={{ fontWeight: 700, fontSize: 18, color: STAGE_COLOUR(s.stage, s.sheets) ?? "inherit" }}>{s.sheets}</span>
              </Link>
            ))}
          </div>
        </PBody>
        <Tiles cls="grid--4" items={[
          ["Results received", `${cv.received} of ${cv.expected}`, cv.missing ? "var(--chrome)" : "var(--green-ink)", `${cv.percent}% of every registration in scope`, pipelineHref(view)],
          ["Still missing", String(cv.missing), cv.missing ? "var(--red-ink)" : "var(--green-ink)", missingCourses ? `${missingCourses} course${missingCourses === 1 ? "" : "s"} not yet in` : "Every result is in", pipelineHref(view, "ENTRY")],
          ["Needs your desk", String(attention), attention ? "var(--red-ink)" : "var(--green-ink)", attention ? `Waiting at ${view.desk || "your desk"}` : "Nothing is waiting on you", "/results/desk"],
          ["Published", `${cv.published} of ${cv.sheets}`, "var(--green-ink)", `${cv.publishedCandidates} candidate result${cv.publishedCandidates === 1 ? "" : "s"} released`, pipelineHref(view, "PUBLISHED")],
        ]} />
        {cv.withoutLecturer ? (
          <PBody>
            <Note kind="bad" title={`${cv.withoutLecturer} offering${cv.withoutLecturer === 1 ? " has" : "s have"} no lecturer, so no sheet can open`} action={<LinkBtn kind="urgent" href="/allocate">Allocate teaching</LinkBtn>}>
              Their candidates cannot be graded until a lecturer is allocated.
            </Note>
          </PBody>
        ) : null}
      </Panel> : null}
      {programmes && view.programmes.length ? (
        <Panel title="Live broadsheets by programme and level" right="Counted from the registrations; a column fills as its sheet is entered">
          <DTable cols={["Programme", "Level|mid", "Students|mid", "Results in|mid", "Missing|mid", "Published sets|mid", "Progress", "|num"]}
            rows={view.programmes.map((p) => [
              <span key="p"><strong>{p.programmeName}</strong><div className="sub2">{p.deptName}</div></span>,
              <span className="tnum" key="l">{p.level}</span>,
              <span className="tnum" key="s">{p.students}</span>,
              <span className="tnum" key="r">{p.received} <span className="sub2">of {p.cells}</span></span>,
              <span className={`tnum${p.missing ? " ink-red b600" : ""}`} key="m">{p.missing}</span>,
              <span className="tnum" key="pub">{p.published}</span>,
              <span key="bar" title={`${p.percent}%`} style={{ display: "inline-block", width: 120, height: 8, background: "var(--line-2)", borderRadius: 4, verticalAlign: "middle" }}>
                <span style={{ display: "block", width: `${p.percent}%`, height: 8, background: p.percent === 100 ? "var(--green-ink)" : "var(--chrome)", borderRadius: 4 }} />
              </span>,
              <LinkBtn key="a" href={broadsheetHref(view, p)} kind="ghost">Open broadsheet</LinkBtn>,
            ])}
            texts={view.programmes.map((p) => `${p.programmeName} ${p.programmeCode} ${p.level} ${p.deptName}`)} />
        </Panel>
      ) : null}
      {attention ? (
        <Panel title={`Needs your desk · ${attention}`} right={view.deskStage ? `At ${view.deskStage.toLowerCase().replace(/_/g, " ")}` : ""}>
          <DTable cols={["Course", "Department", "Candidates|mid", "Received|mid", "Days here|mid", "|num"]}
            rows={view.attention.slice(0, 12).map((s) => [
              <span key="c"><strong className="tnum">{s.courseCode}</strong><div className="sub2">{s.courseTitle}</div></span>,
              <span className="sub2" key="d">{s.deptName}</span>,
              <span className="tnum" key="n">{s.candidates}</span>,
              <span className="tnum" key="r">{s.received}</span>,
              <span className="tnum" key="t">{s.daysAtStage ?? "—"}</span>,
              <LinkBtn key="a" href={s.stage === "ENTRY" ? `/results/sheets/${s.id}` : `/results/chain?sheet=${s.id}`} kind="primary">{s.stage === "ENTRY" ? "Enter marks" : "Open"}</LinkBtn>,
            ])}
            texts={view.attention.map((s) => `${s.courseCode} ${s.courseTitle} ${s.deptName}`)} />
          {attention > 12 ? <PBody><span className="sub2">… and {attention - 12} more on <Link href="/results/desk">the desk</Link>.</span></PBody> : null}
        </Panel>
      ) : null}
      {view.alerts.length ? (
        <Panel title={`Exceptions · ${view.alerts.length}`} right="What the chain flags, read from the record">
          <DTable cols={["Course", "Department", "What", "Detail", "|num"]}
            rows={view.alerts.slice(0, 12).map((a, i) => [
              <strong className="tnum" key={`c${i}`}>{a.courseCode}</strong>,
              <span className="sub2" key={`d${i}`}>{a.deptName}</span>,
              <Pil key={`k${i}`} kind={["OVERDUE", "HIGH_FAIL", "ROLL_GREW", "NO_LECTURER"].includes(a.kind) ? "bad" : a.kind === "ON_BEHALF" || a.kind === "HELD_SCRIPTS" ? "info" : "warn"}>{a.kind.toLowerCase().replace(/_/g, " ")}</Pil>,
              <span key={`t${i}`}>{a.detail}</span>,
              a.sheetId ? <LinkBtn key={`a${i}`} href={`/results/chain?sheet=${a.sheetId}`} kind="ghost">Open</LinkBtn> : <LinkBtn key={`a${i}`} href="/allocate" kind="ghost">Allocate</LinkBtn>,
            ])}
            texts={view.alerts.map((a) => `${a.courseCode} ${a.kind} ${a.deptName}`)} />
        </Panel>
      ) : null}
    </>
  );
}
