"use client";

/** tPipeline — the result pipeline monitor (V318, over proto/part26's nine stages): where every set in scope is, counted
 *  from the record; the coverage (expected, received, missing) counted from the rolls; the courses whose results are not
 *  in; what the chain flags; what needs this desk; the timeline; and every programme and level's live broadsheet. */
import { useState } from "react";
import { useQueryNav } from "@/lib/query-nav";
import type { Scope } from "@/lib/scope";
import { FLAG_LABEL, type PipelineView, type SheetProgress } from "@/lib/results";
import { roleLabel } from "@/lib/offices";
import { brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";
import { ScopeBar, type Ceiling, type ScopeStructure } from "@/components/proto/ScopeBar";
import { Btn, LinkBtn, Note, Panel, PBody, Pil, Tiles, Two } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { PipelinePanel, broadsheetHref } from "@/components/results/PipelinePanel";

/** the nine stages, with what happens and what each cannot pass without (proto/part26 RP_STAGES, read against the chain V013 carries) */
export const RP_STAGES: [string, string, string, string, string][] = [
  ["ENTRY", "Entry", "Course lecturer", "The lecturer types CA and examination against every approved registration, or records an outcome where there is no mark, then attests. A Programme Examinations Officer may enter and submit on the lecturer's behalf, with the reason on the record (V318).", "A mark or an outcome for every candidate on the roll. A blank is not an outcome."],
  ["VERIFICATION", "Verification", "Programme Examinations Officer", "A second academic checks completeness and the arithmetic against the paper, then sends it to the Board or returns it with the reason.", "A different person from the one who submitted it."],
  ["DEPT_BOARD", "Departmental Board", "Head of Department", "The Board reads the distribution against the course's own history and approves or returns.", "A person who did not take the previous stage."],
  ["FACULTY_SCRUTINY", "Faculty scrutiny", "Faculty Examinations Officer", "Every department's sets are scrutinised in one list and recommended for compilation.", "The Departmental Board's approval on the record."],
  ["FACULTY_COMPILATION", "Faculty compilation", "Faculty Officer", "The scrutinised sets are compiled for the Faculty Board.", "Scrutiny completed; nothing altered in compiling."],
  ["FACULTY_BOARD", "Faculty Board", "Dean", "The Board approves the compilation and forwards it to Exams and Records.", "A fail rate above half the candidates is read before it is approved."],
  ["RECORDS", "Exams and Records", "The Registry", "The sets are validated and the Senate schedule is prepared.", "The Faculty Board's approval on the record."],
  ["SENATE", "Senate", "Registrar, on the minute", "Senate approves the schedule as a body; the Registrar records the minute against every set.", "A minute number. Nothing is published without one."],
  ["PUBLISHED", "Published", "Nobody — the candidates", "The result is visible to its candidates, statements can be issued, the transcript compiler sees the set, and the query window opens.", "The Senate minute on the face of the result."],
];

const WHY: Record<string, [string, "bad" | "warn" | "info"]> = {
  NOT_STARTED: ["No mark entered yet", "bad"],
  PARTIAL: ["Partly entered", "warn"],
  NO_LECTURER: ["No lecturer allocated — no sheet can open", "bad"],
  NO_SHEET: ["No sheet opened over the offering", "warn"],
};

function when(iso: string): string {
  const d = new Date(iso);
  return d.toLocaleDateString("en-GB", { day: "numeric", month: "short" }) + " " + d.toLocaleTimeString("en-GB", { hour: "2-digit", minute: "2-digit" });
}

export function Pipeline({ scope, structure, sessions, ceiling, view, stage, office }: {
  scope: Scope; structure: ScopeStructure; sessions: string[]; ceiling: Ceiling; view: PipelineView; stage: string; office?: string | null;
}) {
  // a lecturer sees only their own courses; a HOD only their department (and the programmes under it); a programme officer their programme
  const hide: ("fac" | "dept" | "prog" | "level")[] = office === "lecturer" ? ["fac", "dept", "prog", "level"] : office === "hod" ? ["fac", "dept", "level"] : ["level"];
  const queryNav = useQueryNav();
  const [showGuide, setShowGuide] = useState(false);
  const cv = view.coverage;
  const at = RP_STAGES.findIndex(([code]) => code === stage);
  const go = (next: string) => { const q = new URLSearchParams(window.location.search); if (next) q.set("stage", next); else q.delete("stage"); queryNav(`/results/pipeline?${q.toString()}`); };
  const shown = stage ? view.sheets.filter((s) => s.stage === stage) : view.sheets;
  const period = `${view.session}${view.semester ? ` · ${view.semester === 1 ? "First" : "Second"} semester` : " · both semesters"}`;
  const flagsOf = (s: SheetProgress) => s.flags.filter((f) => f !== "EMPTY_ROLL" || s.candidates === 0);
  const openHref = (s: SheetProgress) => (s.stage === "ENTRY" && (office === "lecturer" || office === "exams" || office === "academic" || office === "gst" || office === "eps") ? `/results/sheets/${s.id}` : `/results/chain?sheet=${s.id}`);

  async function exportSheets() {
    const head = ["S/N", "Course", "Title", "Department", "Lecturer", "Stage", "With", "Candidates", "Received", "Missing", "Days at stage", "Fail rate", "Flags"];
    const body = [...shown].sort((a, b) => a.courseCode.localeCompare(b.courseCode)).map((s, i) => [i + 1, s.courseCode, s.courseTitle, s.deptName, s.lecturer ?? "", s.stage, s.desk, s.candidates, s.received, s.missing, s.daysAtStage ?? "", s.failRate == null ? "" : `${s.failRate}%`, flagsOf(s).map((f) => FLAG_LABEL[f]?.[0] ?? f).join(", ")]);
    downloadBlob(await brandedXlsx("Result Pipeline", head, body, { sheetName: "Pipeline", serial: docSerial("RPM"), sub: `${period}${stage ? ` · ${RP_STAGES[at]?.[1] ?? stage}` : ""}` }), `result-pipeline-${view.session.replace("/", "-")}${stage ? `-${stage.toLowerCase()}` : ""}.xlsx`);
  }

  async function exportMissing() {
    const head = ["S/N", "Course", "Title", "Department", "Lecturer", "Candidates", "Received", "Missing", "Why"];
    const body = view.missing.map((m, i) => [i + 1, m.courseCode, m.courseTitle, m.deptName, m.lecturer ?? "", m.candidates, m.received, m.missing, WHY[m.why]?.[0] ?? m.why]);
    downloadBlob(await brandedXlsx("Missing Results", head, body, { sheetName: "Missing", serial: docSerial("RPM"), sub: period }), `missing-results-${view.session.replace("/", "-")}.xlsx`);
  }

  return (
    <>
      <ScopeBar scope={scope} structure={structure} sessions={sessions} what="result sets" count={view.sheets.length} of={cv.withLecturer} hide={hide} ceiling={ceiling} onExport={() => void exportSheets()} />
      {view.attention.length ? (
        <Note kind="bad" title={`${view.attention.length} set${view.attention.length === 1 ? "" : "s"} need${view.attention.length === 1 ? "s" : ""} your desk`} action={<LinkBtn kind="urgent" href="/results/desk">Open the desk</LinkBtn>}>
          {view.desk ? `${view.desk}: ` : ""}{view.attention.slice(0, 6).map((s) => s.courseCode).join(", ")}{view.attention.length > 6 ? ` and ${view.attention.length - 6} more` : ""}. Each is listed under Needs your desk below with what it waits for.
        </Note>
      ) : (
        <Note kind="ok" title="Nothing is waiting on your desk in this scope">
          The counts below are read from the record as it stands: every set, every roll, every decision. Press a stage to list what sits there; press a programme to open its live broadsheet.
        </Note>
      )}
      <Tiles items={[
        ["Offerings in scope", String(cv.offerings), null, cv.withoutLecturer ? `${cv.withLecturer} with a lecturer · ${cv.withoutLecturer} without` : "Every one has a lecturer"],
        ["Score sheets", String(cv.sheets), null, `Opened over the offerings · ${period}`],
        ["Results received", `${cv.received} of ${cv.expected}`, cv.missing ? "var(--chrome)" : "var(--green-ink)", `${cv.percent}% of every registration in scope`],
        ["Still missing", String(cv.missing), cv.missing ? "var(--red-ink)" : "var(--green-ink)", view.missing.length ? `Across ${view.missing.length} course${view.missing.length === 1 ? "" : "s"}` : "Every registered candidate has a mark or an outcome"],
      ]} />
      <Panel title="The nine stages — where every set is now" right={<span className="row row--inline row--tight"><span className="sub2">{period}</span><Btn kind="ghost" onClick={() => setShowGuide((v) => !v)}>{showGuide ? "Hide the guide" : "What each stage does"}</Btn></span>}>
        <PBody>
          <div className="row row--tight" style={{ flexWrap: "wrap" }}>
            <Btn kind={!stage ? "primary" : "ghost"} onClick={() => go("")} style={{ flexDirection: "column", alignItems: "flex-start", gap: 1 }}>
              <span>All stages</span>
              <span className="tnum t-xs" style={{ fontWeight: 400, opacity: 0.8 }}>{view.sheets.length} set{view.sheets.length === 1 ? "" : "s"}</span>
            </Btn>
            {view.stages.map((s, i) => (
              <Btn key={s.stage} kind={s.stage === stage ? "primary" : "ghost"} onClick={() => go(s.stage)} style={{ flexDirection: "column", alignItems: "flex-start", gap: 1 }} title={s.desk}>
                <span>{i + 1}. {s.label}</span>
                <span className="tnum t-xs" style={{ fontWeight: 400, opacity: 0.8 }}>{s.sheets} set{s.sheets === 1 ? "" : "s"} · {s.candidates} cand.</span>
              </Btn>
            ))}
          </div>
          {showGuide && at >= 0 ? (
            <div className="grid grid--2 mt-3">
              <div><div className="eyebrow">What happens at {RP_STAGES[at][1]} · {RP_STAGES[at][2]}</div><p style={{ margin: "var(--s-1) 0 0", lineHeight: 1.6 }}>{RP_STAGES[at][3]}</p></div>
              <div><div className="eyebrow">What it cannot pass without</div><p style={{ margin: "var(--s-1) 0 0", lineHeight: 1.6 }}>{RP_STAGES[at][4]}</p></div>
            </div>
          ) : showGuide ? (
            <div className="mt-3">
              {RP_STAGES.map(([code, label, desk, what, gate], i) => (
                <div key={code} className="row row--top" style={{ padding: "6px 0", borderTop: i ? "1px solid var(--line-2)" : undefined }}>
                  <span style={{ minWidth: 190 }}><b>{i + 1}. {label}</b><div className="sub2">{desk}</div></span>
                  <span className="grow t-sm" style={{ lineHeight: 1.5 }}>{what} <span className="sub2">Cannot pass without: {gate}</span></span>
                </div>
              ))}
            </div>
          ) : null}
        </PBody>
      </Panel>
      <Panel title={stage ? `${RP_STAGES[at]?.[1] ?? stage} · ${shown.length} set${shown.length === 1 ? "" : "s"}` : `Every set in scope · ${shown.length}`} right={<span className="row row--inline row--tight"><span className="sub2">As the chain records it</span><Btn kind="ghost" onClick={() => void exportSheets()}>Download Excel</Btn></span>}>
        {shown.length === 0 ? <div className="card__body sub2">{stage ? `No set is at ${RP_STAGES[at]?.[1].toLowerCase() ?? stage} in this scope.` : "No score sheet exists in this scope. Sheets are generated when the examination session is opened over the allocated offerings."}</div> : (
          <DTable cols={["Course", "Department", "Lecturer", "Cand.|mid", "In|mid", "Out|mid", "Stage", "Days|mid", "Flags", "Action|num"]}
            rows={shown.map((x) => [
              <Two key="c" a={<span className="tnum">{x.courseCode}{x.sitting && x.sitting !== "MAIN" ? <span className="pill pill--info" style={{ marginLeft: 6 }}>{x.sitting === "RESIT" ? "Re-sit" : "Special"}</span> : null}</span>} b={x.courseTitle} />,
              <span className="sub2" key="d">{x.deptName}</span>,
              <span className="sub2" key="l">{x.lecturer ?? "—"}</span>,
              <span className="tnum" key="n">{x.candidates}</span>,
              <span className="tnum" key="r">{x.received}</span>,
              <span className={`tnum${x.missing ? " ink-red b600" : ""}`} key="m">{x.missing}</span>,
              <span key="s"><Pil kind={x.stage === "PUBLISHED" ? "ok" : x.stage === "ENTRY" ? "bad" : "info"}>{RP_STAGES.find(([c]) => c === x.stage)?.[1] ?? x.stage}</Pil><div className="sub2">{x.stage === "PUBLISHED" ? "Nobody — published" : x.desk}</div></span>,
              <span className="tnum" key="t" title={x.stageSince ? `Since ${when(x.stageSince)}` : ""}>{x.daysAtStage ?? "—"}</span>,
              <span key="f" className="row row--inline row--tight" style={{ flexWrap: "wrap" }}>{flagsOf(x).map((f) => <Pil key={f} kind={FLAG_LABEL[f]?.[1] ?? "grey"}>{FLAG_LABEL[f]?.[0] ?? f}</Pil>)}</span>,
              <LinkBtn key="a" href={openHref(x)} kind={x.mayAct && !x.blockedForYou ? "primary" : "ghost"}>{x.stage === "ENTRY" && x.mayAct && office === "exams" ? "Enter on behalf" : "Open"}</LinkBtn>,
            ])}
            texts={shown.map((x) => `${x.courseCode} ${x.courseTitle} ${x.deptName} ${x.lecturer ?? ""} ${x.stage} ${x.flags.join(" ")}`)} />
        )}
      </Panel>
      <div className="grid grid--2">
        <Panel title={`Results not yet in · ${view.missing.length}`} right={view.missing.length ? <Btn kind="ghost" onClick={() => void exportMissing()}>Download</Btn> : "Everything is in"}>
          {view.missing.length === 0 ? <div className="card__body sub2">Every registered candidate in scope has a mark or an outcome on a sheet.</div> : (
            <DTable cols={["Course", "Lecturer", "Out|mid", "Why", "|num"]}
              rows={view.missing.map((m, i) => [
                <span key={`c${i}`}><strong className="tnum">{m.courseCode}</strong><div className="sub2">{m.deptName}</div></span>,
                <span className="sub2" key={`l${i}`}>{m.lecturer ?? "—"}</span>,
                <span className="tnum" key={`m${i}`}><b className="ink-red">{m.missing}</b> <span className="sub2">of {m.candidates}</span></span>,
                <Pil key={`w${i}`} kind={WHY[m.why]?.[1] ?? "info"}>{WHY[m.why]?.[0] ?? m.why}</Pil>,
                m.sheetId
                  ? <LinkBtn key={`a${i}`} href={office === "exams" || office === "academic" || office === "lecturer" ? `/results/sheets/${m.sheetId}` : `/results/chain?sheet=${m.sheetId}`} kind="ghost">{office === "exams" ? "Enter on behalf" : "Open"}</LinkBtn>
                  : <LinkBtn key={`a${i}`} href={m.why === "NO_LECTURER" ? "/allocate" : "/examinations/sessions"} kind="ghost">{m.why === "NO_LECTURER" ? "Allocate" : "Sessions"}</LinkBtn>,
              ])}
              texts={view.missing.map((m) => `${m.courseCode} ${m.courseTitle} ${m.deptName} ${m.lecturer ?? ""}`)} />
          )}
        </Panel>
        <Panel title={`Timeline · last ${view.timeline.length}`} right="Every act on the record, newest first">
          {view.timeline.length === 0 ? <div className="card__body sub2">No decision has been taken on a set in this scope yet.</div> : (
            <div style={{ maxHeight: 420, overflow: "auto" }}>
              {view.timeline.map((e, i) => (
                <div key={`${e.sheetId}-${i}`} className="row row--top" style={{ padding: "8px var(--s-4)", borderTop: i ? "1px solid var(--line-2)" : undefined }}>
                  <span className="sub2 tnum" style={{ minWidth: 92 }}>{when(e.decidedAt)}</span>
                  <span className="grow t-sm" style={{ lineHeight: 1.45 }}>
                    <a href={`/results/chain?sheet=${e.sheetId}`} className="tnum b600">{e.courseCode}</a>{" "}
                    {e.kind === "UPLOAD_ON_BEHALF" ? <Pil kind="info">uploaded on behalf</Pil> : e.kind === "RETURN" ? <Pil kind="bad">returned</Pil> : e.kind === "SUBMIT" ? <Pil kind="warn">submitted</Pil> : <Pil kind="ok">{(RP_STAGES.find(([c]) => c === e.toStage)?.[1] ?? e.toStage).toLowerCase()}</Pil>}
                    <span className="sub2"> · {e.actor ?? roleLabel(e.actorOffice)} ({roleLabel(e.actorOffice)}){e.comment ? ` · “${e.comment}”` : ""}</span>
                  </span>
                </div>
              ))}
            </div>
          )}
        </Panel>
      </div>
      <PipelinePanel view={view} title="Needs attention and exceptions" programmes={false} summary={false} />
      {view.programmes.length ? (
        <Panel title="Live broadsheets by programme and level" right="Counted from the registrations; a column fills as its sheet is entered">
          <DTable cols={["Programme", "Level|mid", "Students|mid", "Results in|mid", "Missing|mid", "Published sets|mid", "Progress", "|num"]}
            rows={view.programmes.map((p) => [
              <span key="p"><strong>{p.programmeName}</strong><div className="sub2">{p.deptName} · {p.programmeCode}</div></span>,
              <span className="tnum" key="l">{p.level}</span>,
              <span className="tnum" key="s">{p.students}</span>,
              <span className="tnum" key="r">{p.received} <span className="sub2">of {p.cells}</span></span>,
              <span className={`tnum${p.missing ? " ink-red b600" : ""}`} key="m">{p.missing}</span>,
              <span className="tnum" key="pub">{p.published}</span>,
              <span key="bar" title={`${p.percent}%`} style={{ display: "inline-block", width: 120, height: 8, background: "var(--line-2)", borderRadius: 4, verticalAlign: "middle" }}>
                <span style={{ display: "block", width: `${p.percent}%`, height: 8, background: p.percent === 100 ? "var(--green-ink)" : "var(--chrome)", borderRadius: 4 }} />
              </span>,
              <LinkBtn key="a" href={broadsheetHref(view, p, view.semester ?? (scope.sem ? Number(scope.sem) : 1))} kind="ghost">Open broadsheet</LinkBtn>,
            ])}
            texts={view.programmes.map((p) => `${p.programmeName} ${p.programmeCode} ${p.level} ${p.deptName}`)} />
        </Panel>
      ) : null}
    </>
  );
}
