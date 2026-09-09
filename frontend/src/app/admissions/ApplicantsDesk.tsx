"use client";

/**
 * The Academic Office's desk for the applicants (V021), on the Admissions
 * screen under the cycle: the fees stated, payments confirmed against the
 * bank's record, documents reviewed, screening batches made and seated,
 * scores entered and released, the Board's decisions entered and released,
 * the Registry's clearance — and the list that goes back to JAMB, in JAMB's
 * own template. Every act is the office's, on the record.
 */
import { useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { BASES, CLEARANCE_ITEMS, DOCUMENT_KINDS, STAGES, type Application } from "@/lib/applicant";
import { xlsx, type Cell } from "@/lib/xlsx-write";
import { Btn, Note, Panel, PBody, Pil, Tiles, Two } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, Modal } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";

export interface DeskRow {
  id: string; application_no: string; surname: string; other_names: string; jamb_key: string; programme: string; entry_mode: string;
  stage: number; fee_confirmed_at: string | null; submitted_at: string | null; batch: string | null; seat: string | null;
  screening_score: number | null; score_released_at: string | null; decision: string | null; decision_released_at: string | null;
  accepted_at: string | null; declined_at: string | null; cleared_at: string | null; email: string; phone: string;
  references_open: number; documents_pending: number; admission_no: string | null; matric_no: string | null;
}
export interface DeskBatch { id: string; label: string; held_on: string; starts_at: string; ends_at: string; venue: string; capacity: number; seated: number }
export interface DeskReference { id: string; reference: string; kind: string; amount: number; generated_at: string; expires_at: string; application_no: string; surname: string; other_names: string }
export interface Desk {
  session: string;
  applications: DeskRow[];
  batches: DeskBatch[];
  openReferences: DeskReference[];
  fees: { stated: boolean; applicationFee: number; portalCharge: number; acceptanceFee: number };
}

const DOC_LABEL = Object.fromEntries(DOCUMENT_KINDS.map(([k, l]) => [k, l]));
const CL_LABEL = Object.fromEntries(CLEARANCE_ITEMS.map(([k, l]) => [k, l]));

export function ApplicantsDesk({ desk, actingOffice }: { desk: Desk; actingOffice: string | null }) {
  const router = useRouter();
  const [busy, setBusy] = useState<string | null>(null);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [open, setOpen] = useState<Application | null>(null);
  const [edits, setEdits] = useState<Record<string, string>>({});
  const [newBatch, setNewBatch] = useState(false);
  const [exporting, setExporting] = useState(false);
  const base = `/api/bff/api/v1/admissions/sessions/${desk.session}`;
  const office = ["academic", "registrar", "dregistrar"].includes(actingOffice ?? "");
  const registry = office || actingOffice === "records";

  async function send(key: string, method: "PUT" | "POST", path: string, body: unknown, reason: string): Promise<Record<string, unknown> | null> {
    setBusy(key);
    setProblem(null);
    try {
      const r = await fetch(`${base}${path}`, { method, headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) }, body: JSON.stringify(body ?? {}) });
      const j = await r.json().catch(() => null);
      if (!r.ok) { setProblem(j && typeof j === "object" && "status" in j ? (j as Problem) : { status: r.status, title: r.statusText }); return null; }
      router.refresh();
      return (j ?? {}) as Record<string, unknown>;
    } finally {
      setBusy(null);
    }
  }

  async function view(id: string) {
    setProblem(null);
    const r = await fetch(`${base}/applications/${id}`, { cache: "no-store" });
    const j = await r.json().catch(() => null);
    if (r.ok) setOpen(j as Application);
    else setProblem(j ?? { status: r.status, title: r.statusText });
  }

  async function refreshOpen(id: string) {
    const r = await fetch(`${base}/applications/${id}`, { cache: "no-store" });
    if (r.ok) setOpen((await r.json()) as Application);
  }

  async function exportTemplate(programme: string) {
    setExporting(true);
    setProblem(null);
    try {
      const r = await fetch(`${base}/jamb-template${programme ? `?programme=${encodeURIComponent(programme)}` : ""}`, { cache: "no-store" });
      const j = await r.json().catch(() => null);
      if (!r.ok) { setProblem(j ?? { status: r.status, title: r.statusText }); return; }
      const t = j as { session: string; programme: string; asAt: string; summary: Record<string, number | null>; rows: Record<string, unknown>[] };
      const head = (title: string): Cell[][] => [[], [], [], [], [null, null, null, null, null, "REV. FR. MOSES ORSHIO ADASU UNIVERSITY, MAKURDI"], [null, null, null, null, null, `${t.session} UTME MERIT ADMISSION SUMMARY${t.programme ? ` FOR ${t.programme}` : ""}`], [null, null, null, null, null, `${title} AS AT ${t.asAt}`]];
      const cols = ["SN", "REG_NO", "NAME", "GENDER", "STATE", "LGA", "ENG", "SUBJ2", "SUBJ2 SCORE", "SUBJ3", "SUBJ3 SCORE", "SUBJ4", "SUBJ4 SCORE", "UTME SCORE", "ENG GRADE", "ENG POINT", "MATHS GRADE", "MATHS POINT", "SUBJ3", "SUBJ3 GRADE", "SUBJ3 POINT", "SUBJ4", "SUBJ4 GRADE", "SUBJ4 POINT", "SUBJ5", "SUBJ5 GRADE", "SUBJ5 POINT", "SITINGS", "OL/TEST TOTAL SCORE", "NO OF SITTINGS POINTS", "TOTAL O/L SCORE", "OL/TEST SCORE RATIO (_%)", "UTME SCORE RATIO (_%)", "TOTAL SCORE (100%)", "GENERAL REMARKS"];
      const line = (x: Record<string, unknown>, i: number, extra: Cell[] = []): Cell[] => {
        const us = (x.utmeSubjects as { subject: string; score: string }[]) ?? [];
        const eng = us.find((u) => u.subject.toLowerCase().startsWith("eng"));
        const rest = us.filter((u) => u !== eng);
        const o = (x.others as { subject: string; grade: string; points: number }[]) ?? [];
        const num = (v: unknown) => (v === null || v === undefined || v === "" ? null : Number(v));
        return [i + 1, String(x.regNo ?? ""), String(x.name ?? ""), String(x.gender ?? ""), String(x.state ?? ""), String(x.lga ?? ""),
          eng ? num(eng.score) : null, rest[0]?.subject ?? null, rest[0] ? num(rest[0].score) : null, rest[1]?.subject ?? null, rest[1] ? num(rest[1].score) : null, rest[2]?.subject ?? null, rest[2] ? num(rest[2].score) : null,
          num(x.utmeScore), (x.engGrade as string) ?? null, num(x.engPoint), (x.mathsGrade as string) ?? null, num(x.mathsPoint),
          o[0]?.subject ?? null, o[0]?.grade ?? null, o[0] ? num(o[0].points) : null, o[1]?.subject ?? null, o[1]?.grade ?? null, o[1] ? num(o[1].points) : null, o[2]?.subject ?? null, o[2]?.grade ?? null, o[2] ? num(o[2].points) : null,
          num(x.sittings), num(x.cbtScore) ?? 0, num(x.sittingPoints), num(x.olevelTotal), num(x.olevelRatio), num(x.utmeRatio), num(x.total),
          (x.decisionBasis as string) || (x.decisionNote as string) || (x.decision === "OFFERED" ? "Recommended" : x.decision === "WAITING" ? "Waiting list" : x.decision === "NOT_OFFERED" ? "Not recommended" : "Undecided"), ...extra];
      };
      const merit = t.rows.filter((x) => x.decision === "OFFERED");
      const other = t.rows.filter((x) => x.decision === "WAITING");
      const non = t.rows.filter((x) => x.decision === "NOT_OFFERED");
      const s = t.summary;
      const summary: Cell[][] = [...head("SUMMARY OF UTME ADMISSION"), ["SN", "ITEM", "COUNT"],
        [1, "Total Applicants", s.totalApplicants], [2, "Registered Applicants", s.registeredApplicants], [3, "Qualified Cases", s.qualifiedCases],
        [4, "Non-Qualified Cases", s.nonQualifiedCases], [5, "Admission Quota", s.admissionQuota], [6, "Number On Merit List", s.numberOnMeritList]];
      const nonCols = [...cols, "UTME REMARKS", "OL REMARKS"];
      const book = xlsx([
        ["Admission_Summary", summary],
        ["Merit_List", [...head("MERIT LIST"), cols, ...merit.map((x, i) => line(x, i))]],
        ["Other_Qualified_Cases", [...head("OTHER QUALIFIED CASES"), cols, ...other.map((x, i) => line(x, i))]],
        ["Non_Qualified_Cases", [...head("NON-QUALIFIED CASES"), nonCols, ...non.map((x, i) => line(x, i, [
          x.cutoff !== null && x.total !== null && Number(x.total) < Number(x.cutoff) ? "Below cut-off" : "Correct Combination",
          x.olevelTotal === null || Number(x.olevelTotal) === 0 ? "Insufficient OLevel; " : "",
        ]))]],
      ]);
      const blob = new Blob([book.buffer as ArrayBuffer], { type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" });
      const url = URL.createObjectURL(blob);
      const a = document.createElement("a");
      a.href = url;
      a.download = `ADMISSION TEMPLATE ${t.programme ? t.programme.replace(/[^A-Za-z0-9]+/g, " ").trim() : "ALL PROGRAMMES"} ${t.session.replace("/", "-")}.xlsx`;
      a.click();
      URL.revokeObjectURL(url);
    } finally {
      setExporting(false);
    }
  }

  const rows = desk.applications;
  const programmes = [...new Set(rows.map((r) => r.programme))].sort();
  const stageOf = (n: number) => STAGES[Math.min(n, 9)][0];
  const val = (k: string, d = "") => (k in edits ? edits[k] : d);

  return (
    <>
      <Tiles items={[
        ["Application accounts", String(rows.length), null, `${rows.filter((r) => r.submitted_at).length} submitted`],
        ["References open", String(desk.openReferences.length), null, "Paid on the gateway; the Bursary sees each payment"],
        ["Documents to review", String(rows.reduce((n, r) => n + Number(r.documents_pending), 0)), null, "Uploaded, not yet accepted"],
        ["Decisions entered", `${rows.filter((r) => r.decision).length} / ${rows.filter((r) => r.score_released_at).length}`, null, `${rows.filter((r) => r.decision_released_at).length} released`],
      ]} />
      {problem ? <ProblemNotice problem={problem} /> : null}

      <Note kind="info" title="Applicant fees are set by the Bursary and paid on the gateway">
        The Post-UTME screening fee and the acceptance fee are stated on the Bursary&rsquo;s fee-setup screen, under &ldquo;Applicant · Post-UTME fees&rdquo;. An applicant generates a reference and pays it on the payment gateway; the payment confirms itself and the Bursary sees it &mdash; there is no confirmation step here.
      </Note>

      <Panel title="Screening batches" right={<span style={{ display: "inline-flex", gap: 8, alignItems: "center" }}>{`${desk.batches.length} batch${desk.batches.length === 1 ? "" : "es"}`}<Btn kind="ghost" disabled={!office} onClick={() => { setNewBatch(true); setEdits({}); }}>New batch</Btn><Btn kind="primary" disabled={!office || busy !== null} onClick={() => void send("release-scores", "POST", "/screening-scores/release", {}, `Screening results released for ${desk.session}`)}>{busy === "release-scores" ? "Releasing…" : "Release results"}</Btn></span>}>
        {desk.batches.length ? (
          <DTable cols={["Batch", "When", "Venue", "Seated|mid", "|num"]} rows={desk.batches.map((b) => [
            <b key="l">{b.label}</b>,
            <span key="w">{new Date(b.held_on).toLocaleDateString("en-GB", { weekday: "long", day: "numeric", month: "long" })} · {String(b.starts_at).slice(0, 5)}–{String(b.ends_at).slice(0, 5)}</span>,
            <span className="sub2" key="v">{b.venue}</span>,
            <span className="tnum" key="s">{b.seated} / {b.capacity}</span>,
            <span key="a" style={{ display: "inline-flex", gap: 6 }}>
              <Link href={`/admissions/screening/${b.id}?session=${encodeURIComponent(desk.session)}`} className="btn btn--ghost btn--sm">Hall list</Link>
              <Btn kind="ghost" disabled={!office || busy !== null || Number(b.seated) >= b.capacity} onClick={() => void send(`seat-${b.id}`, "POST", `/screening-batches/${b.id}/assign`, {}, `Seats assigned in batch ${b.label}`)}>{busy === `seat-${b.id}` ? "Seating…" : "Seat the submitted"}</Btn>
            </span>,
          ])} />
        ) : <div className="card__body"><div className="sub2">No batch yet. Make one, then seat the submitted applications over it; the slip appears on each applicant&rsquo;s screen the moment they are seated.</div></div>}
      </Panel>

      <Panel title="Applicants" right={<span style={{ display: "inline-flex", gap: 8, alignItems: "center" }}>{`${rows.length} · ${desk.session}`}<Btn kind="primary" disabled={!office || busy !== null} onClick={() => void send("release-decisions", "POST", "/decisions/release", {}, `Admission decisions released for ${desk.session}`)}>{busy === "release-decisions" ? "Releasing…" : "Release decisions"}</Btn></span>}>
        {rows.length ? (
          <DTable cols={["Applicant", "Programme", "Stage|mid", "Seat|mid", "Score|mid", "Decision|mid", "|num"]} texts={rows.map((r) => `${r.surname} ${r.other_names} ${r.application_no} ${r.jamb_key} ${r.programme}`)}
            rows={rows.map((r) => [
              <Two key="a" a={`${r.surname}, ${r.other_names}`} b={`${r.application_no} · ${r.jamb_key}${r.admission_no ? ` · ${r.admission_no}` : ""}`} />,
              <span className="sub2" key="p">{r.programme}</span>,
              <span key="s"><Pil kind={r.stage >= 6 ? "ok" : r.stage >= 2 ? "info" : "grey"}>{r.stage + 1}</Pil> <span className="sub2">{stageOf(r.stage)}</span>{Number(r.documents_pending) ? <div className="sub2">{r.documents_pending} document{Number(r.documents_pending) === 1 ? "" : "s"} to review</div> : null}</span>,
              <span className="tnum" key="t">{r.seat ?? "—"}</span>,
              <span className="tnum" key="c">{r.screening_score ?? "—"}{r.score_released_at ? "" : r.screening_score !== null ? " ·held" : ""}</span>,
              r.decision ? <Pil kind={r.decision === "OFFERED" ? "ok" : r.decision === "WAITING" ? "info" : "bad"} key="d">{r.decision}{r.decision_released_at ? "" : " · held"}</Pil> : <span className="sub2" key="d">—</span>,
              <Btn kind="ghost" key="v" onClick={() => void view(r.id)}>Open</Btn>,
            ])} />
        ) : <div className="card__body"><div className="sub2">No applicant has registered for {desk.session} yet. Registration starts from the JAMB number on the CAPS list loaded on the JAMB admission lists screen.</div></div>}
      </Panel>

      <Panel title="The list that goes back to JAMB" right="JAMB’s admission template, four sheets">
        <PBody>
          <div className="sub2">Admission summary, merit list, other qualified cases and non-qualified cases, per programme, with the UTME subjects as CAPS sent them, the O&rsquo;Level grades and points under this session&rsquo;s grading, the sittings and their bonus, both ratios under the session&rsquo;s weighting, and the Board&rsquo;s decision as the remark. Built from the record, never typed.</div>
          <div style={{ display: "flex", gap: 9, flexWrap: "wrap", alignItems: "center", marginTop: 8 }}>
            <select className="ws__select" style={{ maxWidth: 420 }} value={val("export", "")} onChange={(e) => setEdits({ ...edits, export: e.target.value })} aria-label="Programme to export">
              <option value="">Every programme in one workbook</option>
              {programmes.map((p) => <option key={p} value={p}>{p}</option>)}
            </select>
            <Btn kind="primary" disabled={exporting || !rows.length} onClick={() => void exportTemplate(val("export", ""))}>{exporting ? "Building…" : "Download for JAMB"}</Btn>
          </div>
        </PBody>
      </Panel>


      {newBatch ? (
        <Modal title="A screening batch" sub={desk.session} onClose={() => setNewBatch(false)}
          foot={<><Btn kind="ghost" onClick={() => setNewBatch(false)}>Cancel</Btn><span style={{ flexGrow: 1 }} />
            <Btn kind="primary" disabled={busy !== null || !val("label") || !val("heldOn") || !val("venue")} onClick={async () => { const ok = await send("batch", "POST", "/screening-batches", { label: val("label"), heldOn: val("heldOn"), startsAt: val("starts", "09:00"), endsAt: val("ends", "10:00"), venue: val("venue"), capacity: Number(val("capacity", "120")) }, `Screening batch ${val("label")} made`); if (ok) setNewBatch(false); }}>{busy === "batch" ? "Making…" : "Make the batch"}</Btn></>}>
          <div className="grid grid--2 rfgrid">
            <Field id="b-label" label="Batch"><input id="b-label" className="ctl" value={val("label")} onChange={(e) => setEdits({ ...edits, label: e.target.value })} placeholder="C" /></Field>
            <Field id="b-date" label="Date"><input id="b-date" className="ctl" type="date" value={val("heldOn")} onChange={(e) => setEdits({ ...edits, heldOn: e.target.value })} /></Field>
            <Field id="b-starts" label="Starts"><input id="b-starts" className="ctl" type="time" value={val("starts", "09:00")} onChange={(e) => setEdits({ ...edits, starts: e.target.value })} /></Field>
            <Field id="b-ends" label="Ends"><input id="b-ends" className="ctl" type="time" value={val("ends", "10:00")} onChange={(e) => setEdits({ ...edits, ends: e.target.value })} /></Field>
            <Field id="b-venue" label="Venue" full><input id="b-venue" className="ctl" value={val("venue")} onChange={(e) => setEdits({ ...edits, venue: e.target.value })} placeholder="CBT Hall B, ICT Directorate" /></Field>
            <Field id="b-cap" label="Capacity"><input id="b-cap" className="ctl tnum" value={val("capacity", "120")} onChange={(e) => setEdits({ ...edits, capacity: e.target.value })} /></Field>
          </div>
        </Modal>
      ) : null}

      {open ? (
        <Modal title={`${open.name} · ${open.applicationNo}`} sub={`${open.programme ?? ""} · stage ${open.stage + 1} of 10 · ${stageOf(open.stage)}`} wide onClose={() => setOpen(null)}
          foot={<><span style={{ flexGrow: 1 }} /><Btn kind="ghost" onClick={() => setOpen(null)}>Close</Btn></>}>
          {problem ? <ProblemNotice problem={problem} /> : null}
          <Panel title="Documents" right={`${open.documents.filter((d) => d.status === "ACCEPTED").length} of ${open.documents.length} accepted`}>
            {open.documents.length ? (
              <DTable cols={["Document", "File", "Status|mid", "|num"]} rows={open.documents.map((d) => [
                <span key="k">{DOC_LABEL[d.kind] ?? d.kind}</span>,
                <a key="f" className="sub2 tnum" href={`${base}/applications/${open.id}/documents/${d.id}/content`} target="_blank" rel="noreferrer">{d.filename} · {Math.round(d.bytes / 1024)} KB</a>,
                d.status === "ACCEPTED" ? <Pil kind="ok" key="s">Accepted</Pil> : d.status === "REJECTED" ? <Pil kind="bad" key="s">Rejected</Pil> : <Pil kind="info" key="s">Pending</Pil>,
                <span key="a" style={{ display: "inline-flex", gap: 6 }}>
                  <Btn kind="go" disabled={!office || busy !== null || d.status === "ACCEPTED"} onClick={async () => { await send(`acc-${d.id}`, "POST", `/applications/${open.id}/documents/${d.id}/review`, { status: "ACCEPTED" }, `${DOC_LABEL[d.kind]} accepted`); await refreshOpen(open.id); }}>Accept</Btn>
                  <Btn kind="ghost" disabled={!office || busy !== null} onClick={async () => { const note = window.prompt("What is wrong with it? The applicant reads this."); if (!note) return; await send(`rej-${d.id}`, "POST", `/applications/${open.id}/documents/${d.id}/review`, { status: "REJECTED", note }, `${DOC_LABEL[d.kind]} rejected: ${note}`); await refreshOpen(open.id); }}>Reject</Btn>
                </span>,
              ])} />
            ) : <div className="card__body"><div className="sub2">Nothing uploaded yet.</div></div>}
          </Panel>
          <Panel title="Screening" right={open.screeningSlip ? `Batch ${open.screeningSlip.batch} · seat ${open.screeningSlip.seat}` : "Not seated"}>
            <PBody>
              <div style={{ display: "flex", gap: 12, flexWrap: "wrap", alignItems: "flex-end" }}>
                <Field id="score" label="CBT score, of 100" hint={open.scoreReleasedAt ? "Released; corrected by the Board on the record" : "Leave blank where the O’Level score is the screening"}>
                  <input id="score" className="ctl tnum" style={{ width: 120 }} value={val("score", open.screeningScore === null || open.screeningScore === undefined ? "" : String(open.screeningScore))} disabled={!office || !!open.scoreReleasedAt || !open.screeningSlip} onChange={(e) => setEdits({ ...edits, score: e.target.value })} />
                </Field>
                <Btn kind="primary" disabled={!office || busy !== null || !!open.scoreReleasedAt || !open.screeningSlip || !val("score")} onClick={async () => { await send("score", "PUT", `/applications/${open.id}/screening-score`, { score: Number(val("score")) }, `CBT score entered for ${open.applicationNo}`); await refreshOpen(open.id); }}>{busy === "score" ? "Saving…" : "Enter the score"}</Btn>
              </div>
              {open.result ? (
                <div className="sub2" style={{ marginTop: 8 }}>
                  UTME {open.result.utme ?? "—"} scaled {open.result.utmeScaled ?? "—"} · screening {open.result.screening ?? "—"} ({open.result.screeningSource === "OLEVEL" ? "O’Level" : open.result.screeningSource}) · aggregate <b className="tnum">{open.result.aggregate ?? "—"}</b> · cut-off {open.result.cutoff ?? "not stated"} · position {open.result.meritPosition ?? "—"} of {open.result.applied ?? "—"}{open.scoreReleasedAt ? " · released" : " · not yet released"}
                </div>
              ) : null}
            </PBody>
          </Panel>
          <Panel title="The Board’s decision" right={open.decisionReleasedAt ? <Pil kind="ok">Released</Pil> : open.decision ? <Pil kind="info">Entered, not released</Pil> : <Pil kind="grey">None</Pil>}>
            <PBody>
              <div style={{ display: "flex", gap: 12, flexWrap: "wrap", alignItems: "flex-end" }}>
                <Field id="dec" label="Decision">
                  <select id="dec" className="ctl" value={val("decision", open.decision ?? "")} disabled={!office || !!open.decisionReleasedAt} onChange={(e) => setEdits({ ...edits, decision: e.target.value })}>
                    <option value="">Choose…</option><option value="OFFERED">Offered</option><option value="WAITING">Waiting list</option><option value="NOT_OFFERED">Not offered</option>
                  </select>
                </Field>
                <Field id="dbasis" label="Basis" hint="What goes back to JAMB as the general remark; an offer names one">
                  <select id="dbasis" className="ctl" value={val("dbasis", open.decisionBasis ?? "")} disabled={!office || !!open.decisionReleasedAt} onChange={(e) => setEdits({ ...edits, dbasis: e.target.value })}>
                    <option value="">—</option>
                    {BASES.map(([code, label]) => <option key={code} value={code}>{code} · {label}</option>)}
                  </select>
                </Field>
                <Field id="dnote" label="Note" hint="Anything the Board minuted beyond the basis"><input id="dnote" className="ctl" value={val("dnote", open.decisionNote ?? "")} disabled={!office || !!open.decisionReleasedAt} onChange={(e) => setEdits({ ...edits, dnote: e.target.value })} /></Field>
                <Btn kind="primary" disabled={!office || busy !== null || !!open.decisionReleasedAt || !val("decision", open.decision ?? "") || (val("decision", open.decision ?? "") === "OFFERED" && !val("dbasis", open.decisionBasis ?? ""))} onClick={async () => { await send("decide", "PUT", `/applications/${open.id}/decision`, { decision: val("decision", open.decision ?? ""), note: val("dnote", open.decisionNote ?? "") || undefined, basis: val("dbasis", open.decisionBasis ?? "") || undefined }, `Board decision entered for ${open.applicationNo}`); await refreshOpen(open.id); }}>{busy === "decide" ? "Saving…" : "Enter the decision"}</Btn>
              </div>
              <div className="sub2" style={{ marginTop: 6 }}>Decisions are released together, from the Applicants panel. An offer, released, makes the candidate ADMITTED on the strength of the CAPS row; accepted, ACCEPTED — the same candidate the register is built from.</div>
            </PBody>
          </Panel>
          <Panel title="Clearance at the Registry" right={open.acceptedAt ? `${open.clearance.filter((c) => c.state === "VERIFIED").length} of 6 verified` : "Opens when the offer is accepted"}>
            <DTable cols={["Document", "State|mid", "|num"]} rows={CLEARANCE_ITEMS.map(([k, label]) => {
              const c = open.clearance.find((x) => x.item === k);
              return [
                <Two key="d" a={label} b={c?.note ?? ""} />,
                c?.state === "VERIFIED" ? <Pil kind="ok" key="s">Verified</Pil> : c?.state === "QUERY" ? <Pil kind="bad" key="s">Query</Pil> : <Pil kind="info" key="s">Not presented</Pil>,
                <span key="a" style={{ display: "inline-flex", gap: 6 }}>
                  <Btn kind="go" disabled={!registry || busy !== null || !open.acceptedAt || c?.state === "VERIFIED"} onClick={async () => { await send(`cl-${k}`, "PUT", `/applications/${open.id}/clearance/${k}`, { state: "VERIFIED" }, `${CL_LABEL[k]} verified at clearance`); await refreshOpen(open.id); }}>Verified</Btn>
                  <Btn kind="ghost" disabled={!registry || busy !== null || !open.acceptedAt} onClick={async () => { const note = window.prompt("What is the query? The applicant reads this."); if (!note) return; await send(`cq-${k}`, "PUT", `/applications/${open.id}/clearance/${k}`, { state: "QUERY", note }, `${CL_LABEL[k]} queried: ${note}`); await refreshOpen(open.id); }}>Query</Btn>
                </span>,
              ];
            })} />
          </Panel>
        </Modal>
      ) : null}
    </>
  );
}
