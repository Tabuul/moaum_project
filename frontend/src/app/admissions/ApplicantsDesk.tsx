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
import { BASES, STAGES, dob, BODY, type Application } from "@/lib/applicant";
import { xlsx, type Cell } from "@/lib/xlsx-write";
import { loadCrest, xlsxRows } from "@/lib/xlsx";
import { Btn, KvGrid, Note, Panel, PBody, Pil, Tiles, Two } from "@/components/proto/ui";
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

export function ApplicantsDesk({ desk, actingOffice }: { desk: Desk; actingOffice: string | null }) {
  const router = useRouter();
  const [busy, setBusy] = useState<string | null>(null);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [open, setOpen] = useState<Application | null>(null);
  const [edits, setEdits] = useState<Record<string, string>>({});
  const [newBatch, setNewBatch] = useState(false);
  const [exporting, setExporting] = useState(false);
  const [jambBusy, setJambBusy] = useState(false);
  const [jambMsg, setJambMsg] = useState<string | null>(null);
  const [jambList, setJambList] = useState<{ tiles: Record<string, number>; rows: Record<string, unknown>[] } | null>(null);
  const [nowMs] = useState(() => Date.now());
  const base = `/api/bff/api/v1/admissions/sessions/${desk.session}`;
  const office = ["academic", "registrar", "dregistrar"].includes(actingOffice ?? "");
  const ageOf = (iso: string | null): number | null => {
    if (!iso) return null;
    const d = new Date(iso);
    if (isNaN(d.getTime())) return null;
    const n = new Date(nowMs);
    let a = n.getFullYear() - d.getFullYear();
    if (n.getMonth() < d.getMonth() || (n.getMonth() === d.getMonth() && n.getDate() < d.getDate())) a--;
    return a >= 0 && a < 130 ? a : null;
  };

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
      const t = j as {
        session: string; programme: string; asAt: string; summary: Record<string, number | null>;
        quotaDistribution: { criterion: string; percent: number; quota: number; admitted: number; shortfall: number }[];
        lgaAnalysis: { lga: string; elg: number; sm: number; nm: number; total: number }[];
        lgaTotal: { lga: string; elg: number; sm: number; nm: number; total: number };
        rows: Record<string, unknown>[];
      };
      // a letterhead in the seven rows the template reserves above the data: the
      // school name and title at the top-left (column B, beside the floating crest),
      // then blank rows so the "SN" column header still lands on row 8
      const head = (title: string): Cell[][] => [
        [null, "REV. FR. MOSES ORSHIO ADASU UNIVERSITY, MAKURDI"],
        [null, `${t.session} UTME MERIT ADMISSION SUMMARY${t.programme ? ` FOR ${t.programme}` : ""}`],
        [null, `${title} AS AT ${t.asAt}`],
        [], [], [], [],
      ];
      const BASIS_LABEL: Record<string, string> = { NM: "National Merit", SM: "State Merit", ELG: "Equality of LG", LOCALITY: "Locality", PLWD: "PLWD", OTHER: "Other" };
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
          (x.decisionBasis ? (BASIS_LABEL[x.decisionBasis as string] ?? (x.decisionBasis as string)) : null) || (x.decisionNote as string) || (x.decision === "OFFERED" ? "Recommended" : x.decision === "WAITING" ? "Waiting list" : x.decision === "NOT_OFFERED" ? "Not recommended" : "Undecided"), ...extra];
      };
      const remarks = (x: Record<string, unknown>): Cell[] => [
        (x.utmeRemark as string) ?? "Correct Combination",
        (x.olRemark as string) ?? "",
      ];
      const merit = t.rows.filter((x) => x.decision === "OFFERED");
      const other = t.rows.filter((x) => x.decision === "WAITING");
      const non = t.rows.filter((x) => x.decision === "NOT_OFFERED");
      const s = t.summary;
      const summary: Cell[][] = [...head("SUMMARY OF UTME ADMISSION"), ["SN", "ITEM", "COUNT"],
        [1, "Total Applicants", s.totalApplicants], [2, "Registered Applicants", s.registeredApplicants], [3, "Qualified Cases", s.qualifiedCases],
        [4, "Non-Qualified Cases", s.nonQualifiedCases], [5, "Total Quota (100%)", s.totalQuota], [6, "UTME Quota (80%)", s.utmeQuota], [7, "Number On Merit List", s.numberOnMeritList]];
      if (t.quotaDistribution.length) {
        summary.push([], [null, "QUOTA DISTRIBUTION"], ["SN", "ADMISSION CRITERIA", "(%)", "QUOTA", "ADMITTED", "S/FALLS", "REMARK"]);
        t.quotaDistribution.forEach((q, i) => summary.push([i + 1, q.criterion, q.percent, q.quota, q.admitted, q.shortfall, q.shortfall ? `${q.admitted} of ${q.quota}` : ""]));
      }
      if (t.lgaAnalysis.length) {
        summary.push([], [null, "NATIONAL/STATE/LOCAL GOVERNMENT ANALYSIS"], ["SN", "LGA NAME", "ELG", "SM", "NM", "TOTAL"]);
        t.lgaAnalysis.forEach((l, i) => summary.push([i + 1, l.lga, l.elg, l.sm, l.nm, l.total]));
        summary.push([null, t.lgaTotal.lga, t.lgaTotal.elg, t.lgaTotal.sm, t.lgaTotal.nm, t.lgaTotal.total]);
      }
      const nonCols = [...cols, "UTME REMARKS", "OL REMARKS"];
      const logo = await loadCrest();
      const book = xlsx([
        ["Admission_Summary", summary],
        ["Merit_List", [...head("MERIT LIST"), cols, ...merit.map((x, i) => line(x, i))]],
        ["Other_Qualified_Cases", [...head("OTHER QUALIFIED CASES"), cols, ...other.map((x, i) => line(x, i))]],
        ["Non_Qualified_Cases", [...head("NON-QUALIFIED CASES"), nonCols, ...non.map((x, i) => line(x, i, remarks(x)))]],
        ["Ranked_sheet", [...head("RANKED SHEET"), nonCols, ...t.rows.map((x, i) => line(x, i, remarks(x)))]],
      ], { logo: logo ?? undefined });
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

  async function refreshJamb() {
    const r = await fetch(`${base}/jamb-admissions`, { cache: "no-store" });
    const j = await r.json().catch(() => null);
    if (r.ok && j) setJambList(j as { tiles: Record<string, number>; rows: Record<string, unknown>[] });
  }

  async function uploadJamb(file: File) {
    setJambBusy(true);
    setProblem(null);
    setJambMsg(null);
    try {
      const grid = await xlsxRows(await file.arrayBuffer());
      const header = (grid[0] ?? []).map((c) => String(c ?? "").trim());
      if (!header.some((h) => /^rg_num$/i.test(h) || /reg/i.test(h))) {
        setProblem({ status: 400, title: "That file is not the JAMB admission-status list.", detail: "The first row must carry RG_NUM (registration number), AdmissionStatus and the other JAMB columns." });
        return;
      }
      const body = grid.slice(1)
        .filter((r) => r.some((c) => String(c ?? "").trim() !== ""))
        .map((r) => { const o: Record<string, string> = {}; header.forEach((h, i) => { if (h) o[h] = String(r[i] ?? "").trim(); }); return o; });
      if (!body.length) { setProblem({ status: 400, title: "The file had no rows to read.", detail: "Fill or download the JAMB admission-status list, then upload it." }); return; }
      const r = await fetch(`${base}/jamb-admissions`, { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`JAMB admission status uploaded for ${desk.session}`) }, body: JSON.stringify({ rows: body }) });
      const j = await r.json().catch(() => null);
      if (!r.ok) { setProblem(j ?? { status: r.status, title: r.statusText }); return; }
      const c = j as { loaded: number; matched: number; accepted: number; offered: number; unmatched: number };
      setJambMsg(`${c.loaded} rows read · ${c.matched} matched the register · ${c.accepted} accepted at JAMB · ${c.offered} offered admission here · ${c.unmatched} not on the register.`);
      await refreshJamb();
      router.refresh();
    } catch {
      setProblem({ status: 400, title: "That file could not be read as a spreadsheet.", detail: "Upload the .xlsx downloaded from JAMB." });
    } finally {
      setJambBusy(false);
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
              <Btn kind="primary" key="v" onClick={() => void view(r.id)}>View details</Btn>,
            ])} />
        ) : <div className="card__body"><div className="sub2">No applicant has registered for {desk.session} yet. Registration starts from the JAMB number on the CAPS list loaded on the JAMB admission lists screen.</div></div>}
      </Panel>

      <Panel title="The list that goes back to JAMB" right="JAMB’s admission template, five sheets">
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

      {office ? (
        <Panel title="Admission status from JAMB" right="The list of candidates who accepted, uploaded back">
          <PBody>
            <div className="sub2">After JAMB offers admission and the candidates accept on JAMB&rsquo;s portal, download the admission-status list from JAMB and upload it here. Each row is matched to the candidate the University screened, by registration number. A candidate JAMB records as <b>Accepted</b> is offered admission here and the offer released &mdash; so the applicant can pay the acceptance fee, pay school fees, register and be matriculated. A number not on the register is held, not admitted on a guess.</div>
            <div style={{ display: "flex", gap: 9, flexWrap: "wrap", alignItems: "center", marginTop: 8 }}>
              <label className="btn btn--primary" style={{ cursor: "pointer", margin: 0 }}>
                {jambBusy ? "Uploading…" : "Upload JAMB admission status"}
                <input type="file" accept=".xlsx" style={{ display: "none" }} disabled={jambBusy} onChange={(e) => { const f = e.target.files?.[0]; if (f) void uploadJamb(f); e.target.value = ""; }} />
              </label>
              <Btn kind="ghost" disabled={jambBusy} onClick={() => void refreshJamb()}>Show what was uploaded</Btn>
            </div>
            {jambMsg ? <Note kind="ok" title="Uploaded and matched">{jambMsg}</Note> : null}
            {jambList ? (
              <div style={{ marginTop: 10 }}>
                <Tiles items={[
                  ["Loaded", String(jambList.tiles.loaded ?? 0), null, "Rows on the JAMB list"],
                  ["Matched", String(jambList.tiles.matched ?? 0), null, "On the register here"],
                  ["Accepted at JAMB", String(jambList.tiles.accepted ?? 0), "var(--green-ink)", "Took their offer"],
                  ["Offered here", String(jambList.tiles.offered ?? 0), "var(--green-ink)", "Can pay and register"],
                  ["Not on the register", String(jambList.tiles.unmatched ?? 0), Number(jambList.tiles.unmatched) ? "var(--red-ink)" : null, "For the Registry"],
                ]} />
                {jambList.rows.length ? (
                  <DTable
                    cols={["Reg number|mid", "Name", "Course", "Status|mid", "Category|mid", "On register|mid", "Offered|mid", "Note"]}
                    rows={jambList.rows.slice(0, 400).map((x) => [
                      <span className="tnum" key="r">{String(x.jamb_reg_no ?? "")}</span>,
                      <span key="n">{String(x.name ?? "")}</span>,
                      <span className="sub2" key="c">{String(x.course_name ?? "")}</span>,
                      <Pil kind={String(x.status ?? "").toLowerCase().startsWith("accept") ? "ok" : "grey"} key="s">{String(x.status ?? "—")}</Pil>,
                      <span className="sub2" key="cat">{String(x.category ?? "—")}</span>,
                      x.matched ? <Pil kind="ok" key="m">Yes</Pil> : <Pil kind="bad" key="m">No</Pil>,
                      x.offered ? <Pil kind="ok" key="o">Offered</Pil> : <span className="sub2" key="o">—</span>,
                      <span className="sub2" key="w">{String(x.why ?? "")}</span>,
                    ])}
                    texts={jambList.rows.slice(0, 400).map((x) => `${x.jamb_reg_no ?? ""} ${x.name ?? ""} ${x.status ?? ""}`)}
                  />
                ) : <div className="sub2">No JAMB admission list uploaded for {desk.session} yet.</div>}
              </div>
            ) : null}
          </PBody>
        </Panel>
      ) : null}


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
          <Panel title="Applicant — read from JAMB" right={open.jambKey}>
            <PBody>
              <div style={{ display: "flex", gap: 16, flexWrap: "wrap" }}>
                {(() => {
                  const p = open.documents.find((d) => d.kind === "PASSPORT");
                  return p ? (
                    // eslint-disable-next-line @next/next/no-img-element
                    <img src={`${base}/applications/${open.id}/documents/${p.id}/content`} alt="Passport photograph" style={{ width: 96, height: 120, objectFit: "cover", borderRadius: 8, border: "1px solid var(--line-2)" }} />
                  ) : (
                    <div className="sub2" style={{ width: 96, height: 120, borderRadius: 8, border: "1px dashed var(--line-2)", display: "grid", placeItems: "center", textAlign: "center", padding: 6 }}>No passport yet</div>
                  );
                })()}
                <div style={{ flex: "1 1 320px" }}>
                  <KvGrid cls="grid--2" pairs={[
                    ["Name", open.name],
                    ["JAMB registration", open.jambKey],
                    ["Date of birth", `${dob(open.biodata.dateOfBirth)}${ageOf(open.biodata.dateOfBirth) !== null ? ` · ${ageOf(open.biodata.dateOfBirth)} years` : ""}`],
                    ["Sex", open.biodata.sex === "F" ? "Female" : open.biodata.sex === "M" ? "Male" : "—"],
                    ["State / LGA of origin", `${open.biodata.stateOfOrigin ?? "—"} · ${open.biodata.lga ?? "—"}`],
                    ["Programme (JAMB)", `${open.programme ?? "—"}${open.faculty ? ` · Faculty of ${open.faculty}` : ""}`],
                    ["Entry", open.entryMode === "UTME" ? "UTME" : open.entryMode.charAt(0) + open.entryMode.slice(1).toLowerCase().replace("_", " ")],
                    ["UTME score", open.biodata.utme ?? "—"],
                    ["Email / phone", `${open.email ?? "—"} · ${open.phone ?? "—"}`],
                    ["Next of kin", open.biodata.nextOfKin ?? "—"],
                  ]} />
                </div>
              </div>
            </PBody>
          </Panel>
          <Panel title="O’Level results" right="As JAMB sent them · up to two sittings">
            <PBody>
              {open.olevel.length ? open.olevel.map((s, i) => (
                <div key={i}>
                  <div style={{ display: "flex", alignItems: "center", gap: 8, margin: "8px 0 6px" }}>
                    <Pil kind="grey">{BODY[s.body] ?? s.body}</Pil>
                    <b>Sitting {i + 1}{s.type ? ` — ${s.type}` : ""}{s.year ? ` ${s.year}` : ""}</b>
                    {s.examNumber ? <span className="sub2 tnum">exam no. {s.examNumber}</span> : null}
                  </div>
                  <DTable cols={["Subject", "Grade|mid"]} rows={s.subjects.map((g) => [<span key="s">{g.subject}</span>, <b className="tnum" key="g">{g.grade}</b>])} />
                </div>
              )) : <div className="sub2">No O&rsquo;Level result has reached the University from JAMB yet.</div>}
            </PBody>
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
              <div className="grid grid--3">
                <Field id="dec" label="Decision" hint="Offered, waiting list or not offered">
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
              </div>
              <div style={{ marginTop: 4 }}>
                <Btn kind="primary" disabled={!office || busy !== null || !!open.decisionReleasedAt || !val("decision", open.decision ?? "") || (val("decision", open.decision ?? "") === "OFFERED" && !val("dbasis", open.decisionBasis ?? ""))} onClick={async () => { await send("decide", "PUT", `/applications/${open.id}/decision`, { decision: val("decision", open.decision ?? ""), note: val("dnote", open.decisionNote ?? "") || undefined, basis: val("dbasis", open.decisionBasis ?? "") || undefined }, `Board decision entered for ${open.applicationNo}`); await refreshOpen(open.id); }}>{busy === "decide" ? "Saving…" : "Enter the decision"}</Btn>
              </div>
              <div className="sub2" style={{ marginTop: 6 }}>Decisions are released together, from the Applicants panel. An offer, released, makes the candidate ADMITTED on the strength of the CAPS row; accepted, ACCEPTED — the same candidate the register is built from.</div>
            </PBody>
          </Panel>
        </Modal>
      ) : null}
    </>
  );
}
