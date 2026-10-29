"use client";

/**
 * V700: every correction of a result — the requests the Director of ICT sent the desks of entry, and the amendments the desks raised
 * and took through the chain (V358). Each opens the result it is about; a request still with its desk is withdrawn from there.
 */
import { useState } from "react";
import { useJson } from "@/lib/use-json";
import { ScopeBar, type Ceiling, type ScopeStructure } from "@/components/proto/ScopeBar";
import { Btn, Note, Panel, PBody, Pil } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";
import type { Problem } from "@/lib/api";
import type { Scope } from "@/lib/scope";
import { roleLabel } from "@/lib/offices";
import { RecordDetail, type CorrectionRequest } from "@/components/results/RecordDetail";
import { markWords, monitorQuery, REASON_WORD, REQUEST_STATE_TONE, REQUEST_STATE_WORD, stageWord } from "@/lib/result-monitor";

interface Amendment { id: string; ref: string; kind: string; stage: string; sheetId: string; studentId: string | null; offeringId: string; courseCode: string; session: string;
  semester: number; number: string | null; surname: string | null; otherNames: string | null; programmeCode: string | null; wasCa: number | null; wasExam: number | null;
  wasOutcome: string | null; ca: number | null; exam: number | null; outcome: string | null; wasUnits: number | null; units: number | null; reason: string;
  raisedOffice: string | null; raisedAt: string; appliedAt: string | null; appliedVersion: number | null; closedReason: string | null; senateMinute: string | null; raisedBy: string | null }
interface Answer { state: string; requests: CorrectionRequest[]; amendments: Amendment[]; amendmentsTotal: number; page: number; size: number }

const SIZE = 50;
const when = (s: string | null) => (s ? new Date(s).toLocaleDateString("en-GB", { day: "numeric", month: "short", year: "numeric" }) : "—");

export function Corrections({ scope, structure, sessions, ceiling, initialState }: { scope: Scope; structure: ScopeStructure; sessions: string[]; ceiling: Ceiling; initialState?: string }) {
  const [state, setState] = useState<"OPEN" | "CLOSED" | "ALL">(initialState === "CLOSED" || initialState === "ALL" ? initialState : "OPEN");
  const viewKey = `${scope.session}|${scope.sem}|${scope.fac}|${scope.dept}|${state}`;
  const [pager, setPager] = useState<{ key: string; page: number }>({ key: "", page: 1 });
  const page = pager.key === viewKey ? pager.page : 1;
  const setPage = (n: number) => setPager({ key: viewKey, page: n });
  const [tick, setTick] = useState(0);
  const [open, setOpen] = useState<{ offeringId: string; studentId: string } | null>(null);
  const { data, failed, loading } = useJson<Answer>(`/api/bff/api/v1/results/monitor/corrections${monitorQuery({ session: scope.session, sem: scope.sem, fac: scope.fac, dept: scope.dept, state, page, size: SIZE })}`, tick);
  const load = () => setTick((x) => x + 1);

  async function exportExcel() {
    if (!data) return;
    notify("Export processing…", "ok", 2500);
    try {
      const headers = ["Kind", "Ref", "State", "Course", "Session", "Semester", "Student", "Matric No.", "Before", "After", "Reason", "Raised By", "Raised"];
      const rows = [
        ...data.requests.map((q) => ["Correction request", q.ref, REQUEST_STATE_WORD[q.state] ?? q.state, q.courseCode, q.session, q.semester, `${q.surname.toUpperCase()}, ${q.otherNames}`, q.number ?? "",
          markWords({ ca: q.wasCa, exam: q.wasExam, total: q.wasTotal, grade: q.wasGrade, outcome: q.wasOutcome }), q.ca != null || q.outcome ? markWords({ ca: q.ca, exam: q.exam, outcome: q.outcome }) : "Removed or moved",
          `${REASON_WORD[q.reasonKind] ?? q.reasonKind}: ${q.note}`, q.requestedBy ?? "", when(q.requestedAt)]),
        ...data.amendments.map((a) => ["Amendment", a.ref, stageWord(a.stage), a.courseCode, a.session, a.semester, a.surname ? `${a.surname.toUpperCase()}, ${a.otherNames}` : a.programmeCode ?? "", a.number ?? "",
          a.kind === "UNITS" ? `${a.wasUnits ?? "—"} units` : markWords({ ca: a.wasCa, exam: a.wasExam, outcome: a.wasOutcome }),
          a.kind === "UNITS" ? `${a.units ?? "—"} units` : markWords({ ca: a.ca, exam: a.exam, outcome: a.outcome }), a.reason, a.raisedBy ?? "", when(a.raisedAt)]),
      ];
      downloadBlob(await brandedXlsx("Result corrections", headers, rows, { serial: docSerial("RCO"), meta: [["State", state], ["Session", scope.session || "Every session"], ["Semester", scope.sem || "Every semester"]], sheetName: "Corrections" }), "Result corrections.xlsx");
      notify("Export completed.");
    } catch (e) { notifyProblem(e as Problem, "The export did not complete"); }
  }

  return (
    <>
      <ScopeBar scope={scope} structure={structure} sessions={sessions} ceiling={ceiling} hide={["prog", "level"]} what="corrections"
        count={(data?.requests.length ?? 0) + (data?.amendments.length ?? 0)} of={(data?.requests.length ?? 0) + (data?.amendmentsTotal ?? 0)}
        onExport={data ? () => void exportExcel() : undefined} />
      {failed ? <Note kind="bad" title="Unable to load the corrections">{failed}</Note> : null}
      <div className="row" style={{ gap: 6, margin: "8px 0" }}>
        {(["OPEN", "CLOSED", "ALL"] as const).map((s) => (
          <Btn key={s} kind={state === s ? "primary" : "ghost"} onClick={() => setState(s)}>{s === "OPEN" ? "Open" : s === "CLOSED" ? "Closed" : "All"}</Btn>
        ))}
        <span className="grow" />
        {loading ? <span className="sub2">Loading the corrections…</span> : null}
      </div>
      <Panel title="Correction requests" right={<span className="sub2">Asked of the course&rsquo;s desk of entry; the mark changes only through it</span>}>
        <PBody>
          {data && data.requests.length ? (
            <DTable pageSize={0} cols={["Ref", "State", "Course", "Student", "As it stood", "Proposed", "Reason", "Asked by", ""]}
              rows={data.requests.map((q) => [q.ref, <Pil key="s" kind={REQUEST_STATE_TONE[q.state] ?? "grey"}>{REQUEST_STATE_WORD[q.state] ?? q.state}</Pil>,
                `${q.courseCode} · ${q.session} S${q.semester}`, `${q.surname.toUpperCase()}, ${q.otherNames} (${q.number ?? "—"})`,
                markWords({ ca: q.wasCa, exam: q.wasExam, total: q.wasTotal, grade: q.wasGrade, outcome: q.wasOutcome }),
                q.ca != null || q.outcome ? markWords({ ca: q.ca, exam: q.exam, outcome: q.outcome }) : "Removed or moved by the desk",
                <span key="r">{REASON_WORD[q.reasonKind] ?? q.reasonKind}: {q.note}{q.closedNote ? <><br /><span className="sub2">{q.closedNote}</span></> : null}{q.amendmentRef ? <><br /><span className="sub2">Amendment {q.amendmentRef} · {stageWord(q.amendmentStage)}</span></> : null}</span>,
                `${q.requestedBy ?? "—"} · ${when(q.requestedAt)}`,
                <Btn key="v" kind="ghost" onClick={() => setOpen({ offeringId: q.offeringId, studentId: q.studentId })}>View</Btn>])} />
          ) : <p className="sub2">{data ? "No correction request in this view." : "Loading…"}</p>}
        </PBody>
      </Panel>
      <Panel title="Amendments" right={<span className="sub2">Raised by the desk of entry, approved desk by desk, applied on the Senate minute</span>}>
        <PBody>
          {data && data.amendments.length ? (
            <DTable pageSize={0} cols={["Ref", "Stage", "Course", "Student", "Before", "After", "Reason", "Raised by", ""]}
              rows={data.amendments.map((a) => [a.ref, <Pil key="s" kind={a.stage === "APPLIED" ? "ok" : a.stage === "REFUSED" ? "bad" : a.stage === "WITHDRAWN" ? "grey" : "warn"}>{stageWord(a.stage)}</Pil>,
                `${a.courseCode} · ${a.session} S${a.semester}`, a.surname ? `${a.surname.toUpperCase()}, ${a.otherNames} (${a.number ?? "—"})` : `Units of ${a.programmeCode}`,
                a.kind === "UNITS" ? `${a.wasUnits ?? "—"} units` : markWords({ ca: a.wasCa, exam: a.wasExam, outcome: a.wasOutcome }),
                a.kind === "UNITS" ? `${a.units ?? "—"} units` : markWords({ ca: a.ca, exam: a.exam, outcome: a.outcome }),
                a.closedReason ? `${a.reason} — ${a.closedReason}` : a.reason, `${a.raisedBy ?? "—"}${a.raisedOffice ? ` (${roleLabel(a.raisedOffice)})` : ""} · ${when(a.raisedAt)}`,
                a.studentId ? <Btn key="v" kind="ghost" onClick={() => setOpen({ offeringId: a.offeringId, studentId: a.studentId! })}>View</Btn> : ""])} />
          ) : <p className="sub2">{data ? "No amendment in this view." : "Loading…"}</p>}
          {data && data.amendmentsTotal > data.size ? (
            <div className="row" style={{ marginTop: 8 }}>
              <span className="sub2">{`${((data.page - 1) * data.size + 1).toLocaleString()}–${Math.min(data.page * data.size, data.amendmentsTotal).toLocaleString()} of ${data.amendmentsTotal.toLocaleString()}`}</span>
              <span className="grow" />
              <Btn kind="ghost" disabled={data.page <= 1 || loading} onClick={() => setPage(data.page - 1)}>Previous</Btn>
              <Btn kind="ghost" disabled={data.page * data.size >= data.amendmentsTotal || loading} onClick={() => setPage(data.page + 1)}>Next</Btn>
            </div>
          ) : null}
        </PBody>
      </Panel>
      {open ? <RecordDetail offeringId={open.offeringId} studentId={open.studentId} onClose={() => setOpen(null)} onChanged={load} /> : null}
    </>
  );
}
